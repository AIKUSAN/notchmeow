# E3. Connect Claude: your Claude plan through your own Claude Code, or an API key. Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chat turn can be answered by the user's own installed, unmodified Claude Code (their Claude plan, or whatever Claude Code is signed in with), at three levels picked per chat (Chat only, Read-only, Agent), with Agent steps behind NotchMeow's approval card inside the chat; plus a smoother "Connect Claude" setup for an API key. On the Mac first, then on Windows and Linux.

**Architecture:** A new provider, `claudeCode` (placement `cloud`), runs one `claude -p` process per turn with stream-json in and out. A pure core builds the command line, cleans the environment and parses the transcript; a thin runner owns the process and Stop. The provider joins the E1 router as one more cloud engine that is "ready" only when the user connected it and the last check found Claude Code signed in. Approvals in Agent mode ride the hooks NotchMeow already installs: a `PermissionRequest` whose `session_id` is one of a chat's own session ids goes to that chat's card, never to a pill. Everything that can be tested without a real Claude Code is tested against a fake `claude` and transcripts shared by both apps in `tests/fixtures/ai/claude-code/`.

**Tech Stack:** Swift 6 (`Process`, SwiftUI, `swiftc` test programs), Rust (`std::process`, no new crates), TypeScript (Tauri front end, `node --experimental-strip-types`), Python 3 (the fake `claude` and the fixture self-check). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-06-connect-claude-design.md` (sub-project E3). It builds on `docs/superpowers/specs/2026-10-03-local-models-design.md` (E1). Also read `CLAUDE.md`, `ARCHITECT.md` and `docs/AI-PROVIDERS.md`. Executors read the spec and this plan together.

**Base:** `notchmeow/rebrand` at `5abfa45`. Branch `e3/connect-claude`, in a worktree. Every edit below is anchored by exact text, never by line number.

## Global Constraints

Every task's requirements include this section.

- **Owner's decisions (E3 spec, 2026-10-06):**
  - Scope is **A + B now, C later**: A is "Use my Claude plan" through the user's installed Claude Code, B is a smoother "Connect Claude" setup for an API key. C (OpenRouter, Amazon Bedrock, Google Vertex) is out.
  - NotchMeow runs the user's own installed, **unmodified** `claude` program for each chat turn. Claude Code signs in through Anthropic's own flow; NotchMeow never sees, stores or forwards a login.
  - Three levels, picked **per chat** with a chip next to the model chip; **every new chat starts at Chat only**. Read-only and Agent ask for a folder.
  - Agent mode asks before every edit and every command, with NotchMeow's existing approval card shown in the chat. Nothing runs without a click.
  - **Mac and Windows/Linux, Mac built first.** The Mac App Store build compiles the Claude Code engine out and offers only the API-key path.
  - The engine is called **"Use my Claude plan"** in the UI, with the plain-text note "runs your installed Claude Code". Never "Claude Code" as a label, a title or a feature name, and no Anthropic logo (identifiers in code, the install and sign-in guidance, and the plain-text note are fine).
- **Out of scope (spec):** OpenRouter, Bedrock, Vertex; any Claude.ai sign-in inside NotchMeow and any reuse of Claude Code's tokens or Keychain items; the Claude Agent SDK; installing Claude Code for the user (NotchMeow links to Anthropic's installer); App Attest.
- **Order of work (the owner's):** the contract (fixtures) first, then the Mac, then Windows/Linux. The Mac gets at least what Windows/Linux gets.
- **The command line, copied from the spec.** One turn is one run:

  ```
  claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages
         --session-id <uuid>          (first turn; NotchMeow picks the id)
         --resume <session_id>        (later turns)
         --model sonnet|opus|haiku
         <the level's flags>
  ```

  | Level | Working folder | Flags |
  |---|---|---|
  | Chat only | an empty folder NotchMeow owns (`Application Support/NotchMeow/claude-chat/`, Windows `%APPDATA%\NotchMeow\claude-chat\`) | `--safe-mode --tools "WebSearch,WebFetch" --allowedTools "WebSearch,WebFetch" --disallowedTools "mcp__*" --permission-mode dontAsk` |
  | Read-only | the chosen folder | `--safe-mode --tools "Read,Grep,Glob,WebSearch,WebFetch" --allowedTools "Read,Grep,Glob,WebSearch,WebFetch" --permission-mode dontAsk --settings '{"permissions":{"blockReadsOutsideWorkingDirectories":true}}'` |
  | Agent | the chosen folder | `--permission-mode default --settings '{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":false}}'`. The user's own Claude Code setup (CLAUDE.md, MCP servers, plugins, hooks) loads, as in a terminal. |

  In an argument list each quoted value is **one argument** (no shell). Native Windows has no command sandbox, so there Agent passes `--permission-mode default` and no sandbox `--settings`: every command asks. **Never `--bare`**: it breaks subscription auth. `--tools` does not cover MCP tools, hence `--disallowedTools "mcp__*"` for Chat only. On macOS and Linux Glob and Grep are named explicitly in `--tools` (they are in both lists above).
- **stdin:** one line, `{"type":"user","message":{"role":"user","content":[…]},"parent_tool_use_id":null}`, then stdin is closed. A dropped image or PDF goes in as a content block, other files as their extracted text, as in E1. Claude Code keeps the history in its own session: NotchMeow sends only the new message (the one exception is a level change that moves the working folder, Task 8).
- **Environment:** the run drops `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_PROFILE` and every `CLAUDE_CODE_USE_*` variable. An `apiKeyHelper` in the user's own Claude Code settings still wins over the plan; the model chip shows what `system/init` reports, so the label is always true.
- **Finding Claude Code, in this order:** `~/.local/bin/claude`, the Homebrew prefixes, the npm global bin, the login shell's `PATH`; on Windows `%USERPROFILE%\.local\bin\claude.exe` first, preferred over a Desktop `Claude.exe` that may shadow it on `PATH`. `claude --version` gives the version; `claude auth status` exits 0 when signed in and 1 when not, its JSON has `authMethod` (`none|claude.ai|oauth_token|api_key|api_key_helper|third_party`). Sign-in is `claude auth login` in a terminal (`/login` does not work in `-p`). These checks run **when Settings opens and before a chat's first turn, never on a timer**.
- **Failures** (Claude Code's own words, from the spec): `assistant.error` is one of `authentication_failed`, `billing_error`, `rate_limit`, `overloaded`, `server_error`; `{"type":"system","subtype":"api_retry",…}`; `{"type":"rate_limit_event","rate_limit_info":{"status":"allowed|allowed_warning|rejected","resetsAt"}}`; strings "Not logged in · Please run /login", "You've hit your session limit · resets 3:45pm", "Unable to connect to API. Check your internet connection". Missing auth is a non-zero exit with the text as the result. **The exact JSON of every failure is not documented**, so every parser here is tolerant: an unknown shape is "Claude stopped unexpectedly", never a guess, and the owner's manual checks (Tasks 13 and 20) are what confirm the shapes.
- **Approvals:** the hooks in `~/.claude/settings.json` still fire in `-p`. `PermissionRequest` is answered with `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"|"deny"}}}`; with no decision the step is denied. A `PermissionRequest` whose `session_id` is one of a chat's own session ids (NotchMeow chose it with `--session-id`) goes to that chat. **No new contract strings:** no `nm_*` field changes, no new hook relay change.
- **Credentials and privacy:** NotchMeow never reads Claude Code's Keychain items, credential files or OAuth tokens, and never passes a login on. It parses only `authMethod` out of `claude auth status` and never keeps or logs the rest. Logs (`AppLog`, `nm.log`, Rust `log::line`) record event types and error kinds only: never argv, a folder path or name, stdin, stdout, stderr, a session id or an environment value. A leak test proves it (Task 6, Task 16).
- **No timers, no polling.** Checks run when Settings opens and before a chat's first turn. 0 % CPU while the island is hidden. Stop must leave no process behind.
- **The App Store build** compiles the provider, the locator and the plan card out behind the existing `APPSTORE` flag (`#if !APPSTORE`), as the cat panel is compiled out. `scripts/check-app-binary.sh … appstore` fails if a marker string of any of them is present, and its `release` and `debug` modes fail if one is missing (so the check can fail). Release builds also compile out the Debug-only `NM_CLAUDE_CODE_PATH_OVERRIDE`, as `NM_AI_BASE_URL_OVERRIDE` is.
- **Never restyle what ships** (`CLAUDE.md`). The only changes to existing views are: the level chip beside the model chip; the Connect Claude row at the top of Settings → AI (not in the App Store build); a "Connect Claude" button in the chat's empty state (the spec's "first run"); a Claude plan section in the model pickers (the chat's and Settings') and the Preferred cloud picker; step rows and the approval card inside the chat. New views reuse `TickerRowView`, `CodeBlock`, `PrimaryButton` and `SecondaryButton` as they are. `ClaudePlanCardView` is the existing plan-usage gauge: it is not touched and not the "plan card" the App Store flag removes (that is the new `ConnectClaudePlanView`).
- **Contract strings:** provider ID `claudeCode` (placement `cloud`, API `claude-code`) joins `tests/fixtures/ai/providers.json`; it is frozen once shipped, like every provider ID. The twelve error kinds do not change: Claude Code's failures map onto them with a code (`nm_signed_out`, `nm_plan_limit`, `nm_claude_missing`, `nm_claude_old`, `nm_claude_crashed`, `nm_claude_offline`, `nm_needs_git`, `nm_folder_missing`).
- **Mac:** Swift 6 with `-strict-concurrency=complete`, SwiftUI and AppKit, no third-party dependency; `project.yml` through XcodeGen (never edit the `.xcodeproj`); `AI/Core/*.swift` stays Foundation-only (`scripts/test-ai-router.sh` fails otherwise); new Swift tests are `swiftc` programs under `scripts/test-*.sh`; no `UserDefaults` suite in any test.
- **Windows/Linux:** Rust with `std::process` only (no tokio `process` feature, no new crate, no `Cargo.toml` change); TypeScript strict with `noUnusedLocals` and `noUnusedParameters`; install nothing (`npx --no-install` only). Native Windows runs `claude.exe` only (a `.cmd` shim cannot take JSON arguments safely).
- **Repo rules (`CLAUDE.md`):** commits are local and only as each task's commit step says; never push; nothing of Coucou's comes back; `main` is the App Store build. Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (`Claude Haiku 4.5` when a light task ran on it).
- **House rules for every session and every subagent brief (the SUBAGENT RULES block):**
  1. Never run `claude` itself, never touch the owner's Claude account, and never put a real transcript in the repo.
  2. Never launch, quit or replace any NotchMeow app. A Debug build for a checkpoint is the main session's to start.
  3. Install nothing. No network calls (`cargo --offline`, `npx --no-install`).
  4. Use `trash`, never `rm -rf`; unique scratch names under the scratchpad.
  5. No `UserDefaults` suites in tests; tests write no log outside a temp `NM_LOG_DIR`.
  6. Never push. Commit only in a task's commit step.
  7. If a command is denied, stop and report it. Do not look for a workaround.

## Review Focus

The spec says what the engine does. It is silent on these, and each would bite a person first. Each line names its test.

1. **A chat switched from Agent to Chat only mid-conversation.** Claude Code stores a session under its working folder, and Chat only runs in NotchMeow's own empty folder, so `--resume` from there cannot find a session made in the user's folder. Expected: the chat keeps its messages, the next answer still knows the earlier turns (a recap rides in front of the new message), the old session id is retired and the approvals still waiting on it are handed back. The chip is disabled while a reply is streaming. Tests: Task 8 (`ClaudeChatSession`: "a level change that keeps the folder resumes; one that moves it starts a new session", and the recap), Task 9 (`ChatApprovalQueue.removeAll(session:)`), Task 10 (source pins: a retired session, a new conversation and Stop each hand the waiting approvals back; the recap reaches the provider through the factory), Task 17 (`a_chats_session`, `the_recap_of_a_chat`, `a_level_change_that_moves_the_folder_starts_a_new_session_with_a_recap`), the owner's checks in Tasks 13 and 20.
2. **Stop during a tool step.** Expected: the process and anything it started are gone within seconds (interrupt, then terminate, then kill), the step row ends as stopped and never stays "running", the approvals waiting on that run are answered `ask` (refused) and the card goes, and the partial reply is kept. Tests: Task 6 (a fake `claude` that hangs mid-tool, one that ignores interrupt and terminate, and a child process that must die), Task 5 (`ChatStep.endingUnfinished`), Task 10 (pin: Stop hands the approvals back), Task 16 (`stop_ends_the_process_and_what_it_started`, with the Windows tree kill), Task 18 (`endUnfinished`).
3. **Two chats at once.** Both apps hold one conversation, but a reset (a file drop, ⌘K) can happen while a turn still runs, and a second turn can start before the first process has finished dying. Expected: each run has its own session id, process and parser; the old run is stopped and its output dropped (the chat's existing generation guard); nothing the old run writes reaches the new chat. Tests: Task 6 ("Two runs at once": separate sessions, processes and output), Task 8 (retired ids), Task 16 (`two_runs_at_once_do_not_share_anything`).
4. **The user's own Claude Code sessions running alongside.** Expected: their `PermissionRequest`s still reach their own pills and cards, exactly as today; a chat's request never displaces theirs and theirs never displaces a chat's. Tests: Task 8 (`ClaudeHookRouting` replays `hook-routing.json`: an unknown `session_id`, a missing or non-string one, an id in another case, a Codex or `nm_agent` payload all route to "not a chat"), Task 10 (a source pin that `HookServer` asks the router before any pill logic, in all three handlers), Task 18 (the same cases through `routeHook`, and the same pin for `hooks.ts`).
5. **`apiKeyHelper` set in the user's Claude Code.** Expected: the chip says "Claude · API key" (what `system/init` reports), never "your plan"; an unknown `apiKeySource` says just "Claude". Tests: Task 5 (`api-key-helper.jsonl` and `unknown-source.jsonl` in `expected-parse.json`), Task 8 (`labels.json`), Task 15 (the same transcripts in Rust), Task 18 (`modelChip`).
6. **A folder with spaces or non-ASCII characters** (`/Users/Zoé/Mes projets/ünï côde`, `C:\Users\José\Mis Proyectos`). Expected: it is the process's working folder and appears nowhere in the argument list; the sign-in script and every shell string quote it correctly; the chip shows its name. Tests: Task 4 (`expected-args.json` cases and the working folder), Task 6 (a run in such a folder), Task 7 (the sign-in script), Task 15 and Task 16 (the same cases, `a_folder_with_spaces_and_non_ascii_characters`, `quoting_for_a_shell_and_for_powershell`), Task 18 (`folderName`).
7. **Windows without Git for Windows.** Claude Code on native Windows refuses to start without it. Expected: "Claude Code needs Git for Windows" with a link, not "stopped unexpectedly". Tests: Task 15 (`the_words_of_each_failure`, the stderr shape in `expected-parse.json`), Task 16 (`git_for_windows_is_looked_for_in_the_usual_places`, a refused run in `failures`), the owner's check in Task 20.
8. **Agent mode asks before every command, even sandboxed ones.** Claude Code's sandbox defaults to auto-allow mode (`sandbox.autoAllowBashIfSandboxed` defaults to `true`, per code.claude.com/docs/en/sandboxing), which would run sandboxed commands without a request and so without a card. The owner decided on 2026-10-06 that every command asks: the Agent settings JSON sets `"autoAllowBashIfSandboxed":false` in every port and in `expected-args.json`. The owner still checks one harmless command in Tasks 13 (B5) and 20: a card must appear.
9. **Agent mode with NotchMeow's hooks not installed.** Claude Code denies every step. Expected: the level menu says so before the user picks Agent, and the denial is not shown as a mystery. Tests: Task 8 (`ClaudeAgentReadiness`), Task 9 (`hooksInstalled(in:)`), Task 11 and Task 18 (the menus), the owner's checks.
10. **A reply made of several assistant messages around tool calls** ("I'll read it.", a tool, "It says…"). Expected: the text reads as paragraphs, not "it.It". Tests: Task 5 (`tool-use.jsonl` in `expected-parse.json`), Task 15 (the same in Rust).
11. **Secrets and paths in logs.** Expected: no folder name, prompt, file name, session id or environment value in `nm.log`. Tests: the leak tests of Task 6 ("Log leak test") and Task 16 (`nothing_private_reaches_the_log`).

---


## File Structure

New Swift files are found by XcodeGen. The tracked `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` is generated, so each Mac task that adds a Swift file runs `xcodegen` and commits the regenerated project with it (never edit it by hand). The Windows/Linux side adds no crate and no `Cargo.toml` line.

| Path | Responsibility |
|---|---|
| `tests/fixtures/ai/providers.json`, `router-cases.json`, `reference.py` | The shared router contract gains the provider `claudeCode` and nine router cases (Task 1). |
| `tests/fixtures/ai/claude-code/` | New. The Claude Code contract (Task 2): `fake_claude.py` (the stand-in `claude`), `transcripts/*.jsonl` (what it replays), `expected-args.json`, `expected-env.json`, `expected-parse.json`, `auth-status.json`, `versions.json`, `locator-cases.json`, `hook-routing.json`, `labels.json`, `copy.json`, and `reference.py`, an independent Python model of all of it that is the tie-breaker. |
| `scripts/test-ai-contract.sh` | Runs the new reference too. |
| `NotchBuddy/Sources/App/AI/Core/AICatalog.swift`, `ModelRouter.swift`, `ProviderFactory.swift`, `Attachments.swift`, `NotchBuddy/Sources/App/IslandTypes.swift` | The provider ID, `ClaudeCodeModel`, the router's cloud order, the factory's case (Task 3). |
| `NotchBuddy/Sources/App/AI/Core/ClaudeCodeEngine.swift` | New. The command line per level and turn, the cleaned environment, the message on stdin. Pure. |
| `NotchBuddy/Sources/App/AI/Core/ClaudeStreamParser.swift` | New. What a transcript means: text, steps, who pays, how a run failed, in the shared error kinds with codes. Pure and tolerant. |
| `NotchBuddy/Sources/App/AI/Core/ModelProvider.swift`, `ReplyAccumulator.swift`, `ChatRunner.swift` | `ChatStep`, `EngineReport`, `ChatChunk.step`/`.engine`, `AIError.resetsAt`, `RunEvent.step`/`.engine`, and "steps taken, so no other model" (Task 5). |
| `NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift` | New. A `ModelProvider` that runs one `claude -p` per turn and owns the process and Stop (interrupt, terminate, kill, the whole tree). |
| `NotchBuddy/Sources/App/AI/Core/ClaudeCodeLocator.swift` | New. Where `claude` is, its version, `claude auth status`, the sign-in script. |
| `NotchBuddy/Sources/App/AI/Core/ClaudeChatSession.swift` | New. A chat's session, the recap, `ClaudeCodeSetup`, and whether Agent can ask (hooks installed). |
| `NotchBuddy/Sources/App/AI/Core/ClaudeHookRouting.swift` | New. Which hook payloads belong to a chat. |
| `NotchBuddy/Sources/App/AI/Core/ClaudeCodeText.swift`, `AIMessages.swift` | New and changed. The chips, the sign-in words, the note and button for each Claude Code failure. |
| `NotchBuddy/Sources/App/AI/Core/ClaudeChatApproval.swift` | New. The approval card's text, the queue of waiting requests, the hooks-installed check. |
| `NotchBuddy/Sources/App/SessionStepText.swift`, `HookServer.swift` | The step words move out of `HookServer` unchanged so the chat can use them (Task 9); `HookServer` then routes a chat's requests to its card (Task 10). |
| `NotchBuddy/Sources/App/ClaudeService.swift`, `AI/AIService.swift`, `AppState.swift`, `ClaudeCodeActions.swift` | The chat's session and level, the status check, the connected flag, Sign in (Task 10). |
| `NotchBuddy/Sources/App/ClaudeChatViews.swift`, `IslandViewContent.swift`, `SettingsView.swift` | New and changed. The level chip, step rows and approval card in the chat, the Connect Claude box, the model pickers (Task 11). |
| `scripts/test-claude-code.sh`, `scripts/test-session-steps.sh`, `tests/ClaudeCode*Tests.swift`, `tests/SessionStepTextTests.swift` | New. One `swiftc` test program per file, run by the scripts. |
| `scripts/check-app-binary.sh` | Proves the App Store build has no engine, locator or plan card, and the other builds do (Task 12). |
| `windows/src-tauri/src/ai/catalog.rs`, `router.rs`, `provider.rs`, `errors.rs`, `settings.rs` | The provider, the router, the shared types, the error codes and the two settings fields (Tasks 14 and 15). |
| `windows/src-tauri/src/ai/claude_code.rs` | New. The Rust port of the engine and parser, against the same fixtures. |
| `windows/src-tauri/src/ai/claude_cli.rs`, `claude_run.rs` | New. Locator, status, sign-in, Git for Windows; the runner with Stop (process group on Unix, `taskkill /T /F` on Windows). |
| `windows/src-tauri/src/ai/claude_chat.rs`, `session.rs`, `mod.rs`, `lib.rs` | New and changed. The chat's session, the turn through the existing `AiState`, the commands the front end calls. |
| `windows/src/core/steps.ts`, `claude.ts`, `bridge.ts`, `state.ts` | New and changed. The step and approval words, the pure chat logic (routing, chips, queue), the bridge commands and events, the state. |
| `windows/src/island/hooks.ts`, `island.ts`, `views/chat.ts`, `settings/main.ts`, `style.css`, `scripts/check-claude-ui.mjs`, `package.json` | New and changed. Routing a chat's requests to its card, the level chip, steps and card in the chat, the Connect Claude box, `npm run check:claude`. |
| `docs/AI-PROVIDERS.md`, `docs/INTEGRATIONS.md`, `windows/README.md`, `.github/workflows/build.yml`, `windows-tests.yml` | Documentation and CI (Task 19). |


## Tasks and agents

Each task goes to the agent below, then to `nm-reviewer`; fix what the review finds before the next task. Per `CLAUDE.md` the lightest model that fits: Tasks 1, 2, 12 and 19 are fixtures, one script and docs with their text given, so Haiku; Tasks 3, 4, 5, 7, 8, 9, 11, 14, 15 and 18 are multi-file with their code given, so Sonnet 5.5 medium; Tasks 6, 10, 16 and 17 are processes and their process groups, a hook server that must answer on a socket, and the Tauri session, so Sonnet 5.5 high. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep`. The worktree session itself runs on Sonnet 5.5 high (hard integration, platform APIs and many cross-task interfaces; the main session sets model and effort after the chip starts, as `ARCHITECT.md` says).

| # | Task | Agent | Review |
|---|---|---|---|
| 1 | Contract: the Claude plan joins the shared router fixtures | `nm-implementer-light` | `nm-reviewer` |
| 2 | Contract: the fake `claude`, its transcripts and the expected files | `nm-implementer-light` | `nm-reviewer` |
| 3 | Mac: the provider ID, the catalog and the router | `nm-implementer` | `nm-reviewer` |
| 4 | Mac: the command line, the environment and the message on stdin | `nm-implementer` | `nm-reviewer` |
| 5 | Mac: the transcript parser, steps and the runner's new events | `nm-implementer` | `nm-reviewer` |
| 6 | Mac: the provider, one process per turn, and Stop | `nm-implementer-deep` | `nm-reviewer` |
| 7 | Mac: finding Claude Code, its status and signing in | `nm-implementer` | `nm-reviewer` |
| 8 | Mac: a chat's session, hook routing, the chips and the words | `nm-implementer` | `nm-reviewer` |
| 9 | Mac: approvals waiting in a chat, and the step words move out of `HookServer` | `nm-implementer` | `nm-reviewer` |
| 10 | Mac: the wiring (service, hook server, state, factory) | `nm-implementer-deep` | `nm-reviewer` |
| 11 | Mac: the views (level chip, steps and card in the chat, Connect Claude, pickers) | `nm-implementer` | `nm-reviewer` |
| 12 | Mac: the App Store proof (`check-app-binary.sh`) | `nm-implementer-light` | `nm-reviewer` |
| 13 | Owner checkpoint: the Mac | the main session and the owner | none |
| 14 | Windows/Linux: the provider ID, catalog, router, errors and settings fields | `nm-implementer` | `nm-reviewer` |
| 15 | Windows/Linux: `claude_code.rs`, the command line, the environment and the transcript | `nm-implementer` | `nm-reviewer` |
| 16 | Windows/Linux: finding Claude Code, and the runner with Stop (`claude_cli.rs`, `claude_run.rs`) | `nm-implementer-deep` | `nm-reviewer` |
| 17 | Windows/Linux: a chat's session and the turn (`claude_chat.rs`, `session.rs`, the commands) | `nm-implementer-deep` | `nm-reviewer` |
| 18 | Windows/Linux: the front end (routing, chips, steps, card, Connect Claude) | `nm-implementer` | `nm-reviewer` |
| 19 | Docs and CI | `nm-implementer-light` | `nm-reviewer` |
| 20 | Owner checkpoint: both apps, with a real Claude Code | the main session and the owner | none |
| Final | Whole-branch review | `nm-reviewer-deep` | none |

**Controller brief** (what the main session sends the worktree session once its model is set):

> Run `docs/superpowers/plans/2026-10-06-e3-connect-claude.md` with `superpowers:subagent-driven-development`, task by task, on branch `e3/connect-claude`. Dispatch each task to the agent the plan names for it, then to `nm-reviewer`; fix what the review finds before the next task. Put the plan's SUBAGENT RULES block (Global Constraints) in every brief, and tell Tasks 1 and 2 that `bash scripts/test-ai-router.sh` (Mac) and the Windows `cargo test` stay red on the new fixtures until Tasks 3 and 14: the contract comes first. Run Tasks 1 to 12, then stop and report to the main session for the owner checkpoint (Task 13). After the owner's reply run Tasks 14 to 19, then stop again for Task 20; after that dispatch `nm-reviewer-deep` over the whole branch. No agent ever runs `claude`, touches the owner's Claude account, launches or quits a NotchMeow build, installs anything or uses the network. Commit only as the plan's commit steps say, never push. Report the commits; the output of `bash scripts/test-ai-contract.sh`, `bash scripts/test-claude-code.sh`, `bash scripts/test-session-steps.sh` and every `bash scripts/test-ai-*.sh`; the Debug, Release and App Store build lines and the three `check-app-binary.sh` lines; in `windows/` the Rust test counts, `npx --no-install tsc --noEmit`, `npm run check:claude`, `npm run check:ai` and `npm run check:cat`; the Windows `cargo check` result or why it was owed to CI; and anything you could not settle.


## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go.

**Red first, and the contract first.** Tasks 1 and 2 add fixtures before any code reads them, so `bash scripts/test-ai-router.sh` and the Windows `cargo test` for the router and the catalog are red from Task 1 until Task 3 (Mac) and Task 14 (Windows/Linux) make them pass. That is the owner's order (contract, then Mac, then Windows/Linux), not a mistake. Every other task is green when it ends.

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-*.sh`; none needs Xcode. A build is `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO`; the App Store target is `-scheme NotchMeowAppStore` and the Release configuration `-configuration Release`, each with its own `-derivedDataPath` under `build/` (git ignores `NotchBuddy/build/`). Add `| tail -3` to read the last lines. Never start a built app.

**Rust runs only through `windows/scripts/cargo-linux.sh`** (Docker Desktop running), with this plan's own target directory, because other worktrees share that script's Docker volume. Check the image first and stop if it is missing (the script would build it, which pulls a base image):

```bash
docker image inspect notchmeow-linux-dev >/dev/null && echo "image ok"
CL=windows/scripts/cargo-linux.sh
TD=/repo/windows/target/e3-claude      # this plan's own target dir: the Docker volume is shared by every worktree
```

Every Rust command below is `$CL <cargo arguments> --target-dir $TD`, and a test filter goes after `--`. The Linux run compiles the Unix side; the `#[cfg(windows)]` lines (`taskkill`, the `.exe` locations, PowerShell) are compiled by Task 17's Windows `cargo check`. Never `npm install`, never `npm run build` or `npm run dev` (their `pre` steps build the relay for the host); use `npx --no-install`.

**Merging.** The tracked `project.pbxproj` is generated: if it conflicts when this branch merges, take either side and run `cd NotchBuddy && xcodegen` again.

**Subagent rules.** The SUBAGENT RULES block in Global Constraints goes into every brief. In particular: no `claude`, no owner account, no real transcript in the repo, no `rm -rf` (use `trash`), no `UserDefaults` suite in a test. (The test scripts the plan adds clean their own `mktemp` folder with `rm -rf` in a `trap`, as every existing `scripts/test-*.sh` does: that is the repo's convention for a script's own temp folder, not a command an agent runs.)

---


## Tasks

### Task 1: Contract: the Claude plan joins the shared router fixtures

**Agent:** `nm-implementer-light`. The edits are given in full. Expect the two ports' router and catalog tests (`bash scripts/test-ai-router.sh`, the Windows `cargo test`) to turn red when this task lands, and to stay red until Tasks 3 and 14: that is the contract-first order.

**Files:**
- Modify: `tests/fixtures/ai/providers.json`
- Modify: `tests/fixtures/ai/router-cases.json`
- Modify: `tests/fixtures/ai/reference.py` (the Python reference model of the router)

**Interfaces:**
- Consumes: the E1 shared AI contract (`tests/fixtures/ai/`), which both apps already replay.
- Produces: the provider row `claudeCode` (placement `cloud`, API `claude-code`, no keychain key, default model alias `sonnet`); Auto's cloud order "preferred, then the others of `claudeCode`, `anthropic`, `openai`, then `google`"; the rule that `keys` holds `claudeCode` only when the user connected it and the last check found Claude Code signed in; and nine router cases pinning them (a plan failure of kind `auth` or `billing` never falls back; a temporary one gets the one local retry like any cloud provider). Tasks 3 and 14 read them.

- [ ] **Step 1: Add the fixtures first**

The provider row goes last in the catalog, so the existing providers keep their order.

**Edit `tests/fixtures/ai/providers.json`**, find this text (it occurs exactly once):

```json
     "keychainKey": null, "defaultModel": "system"},
    {"id": "custom", "name": "Local server", "placement": "computed", "api": "openai-chat",
     "chatPath": "/v1/chat/completions", "modelsPath": "/v1/models", "keychainKey": "custom-server-key", "defaultModel": null}
  ],
  "cloudOrder": ["anthropic", "openai", "google"],
```

and replace it with:

```json
     "keychainKey": null, "defaultModel": "system"},
    {"id": "custom", "name": "Local server", "placement": "computed", "api": "openai-chat",
     "chatPath": "/v1/chat/completions", "modelsPath": "/v1/models", "keychainKey": "custom-server-key", "defaultModel": null},
    {"id": "claudeCode", "name": "Claude plan", "placement": "cloud", "api": "claude-code",
     "keychainKey": null, "defaultModel": "sonnet"}
  ],
  "cloudOrder": ["anthropic", "openai", "google"],
```

Nine router cases join the end of the file:

**Edit `tests/fixtures/ai/router-cases.json`**, find this text (it occurs exactly once):

```json
    {"name": "apple can be the fallback",
     "input": {"keys": ["anthropic"], "failure": "timeout", "appleReady": true},
     "expect": {"primary": "anthropic", "outcome": "fallback", "answeredBy": "apple", "label": "local", "errorKind": "timeout"}}
  ]
}
```

and replace it with:

```json
    {"name": "apple can be the fallback",
     "input": {"keys": ["anthropic"], "failure": "timeout", "appleReady": true},
     "expect": {"primary": "anthropic", "outcome": "fallback", "answeredBy": "apple", "label": "local", "errorKind": "timeout"}},
    {"name": "claude plan preferred and ready → claude plan",
     "input": {"keys": ["claudeCode", "anthropic"], "preferredCloud": "claudeCode"},
     "expect": {"primary": "claudeCode", "outcome": "ok", "answeredBy": "claudeCode", "label": "cloud", "errorKind": null}},
    {"name": "claude plan is the other cloud when the preferred has no key",
     "input": {"keys": ["claudeCode"], "preferredCloud": "anthropic"},
     "expect": {"primary": "claudeCode", "outcome": "ok", "answeredBy": "claudeCode", "label": "cloud", "errorKind": null}},
    {"name": "preferred api key beats a ready claude plan",
     "input": {"keys": ["claudeCode", "anthropic"], "preferredCloud": "anthropic"},
     "expect": {"primary": "anthropic", "outcome": "ok", "answeredBy": "anthropic", "label": "cloud", "errorKind": null}},
    {"name": "claude plan not ready (not in keys) → the api key",
     "input": {"keys": ["anthropic"], "preferredCloud": "claudeCode"},
     "expect": {"primary": "anthropic", "outcome": "ok", "answeredBy": "anthropic", "label": "cloud", "errorKind": null}},
    {"name": "claude plan beats openai when the preferred cloud is openai without a key",
     "input": {"keys": ["claudeCode", "anthropic"], "preferredCloud": "openai"},
     "expect": {"primary": "claudeCode", "outcome": "ok", "answeredBy": "claudeCode", "label": "cloud", "errorKind": null}},
    {"name": "claude plan temporary failure → one local retry",
     "input": {"keys": ["claudeCode"], "preferredCloud": "claudeCode", "failure": "server", "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "claudeCode", "outcome": "fallback", "answeredBy": "ollama", "label": "local", "errorKind": "server"}},
    {"name": "claude plan signed out (auth) never falls back",
     "input": {"keys": ["claudeCode"], "preferredCloud": "claudeCode", "failure": "auth", "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "claudeCode", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "auth"}},
    {"name": "claude plan limit (billing) never falls back and never counts down",
     "input": {"keys": ["claudeCode"], "preferredCloud": "claudeCode", "failure": "billing", "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "claudeCode", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "billing"}},
    {"name": "an explicit claude plan choice is used even when it is not ready",
     "input": {"setting": {"provider": "claudeCode", "model": "sonnet"}, "keys": []},
     "expect": {"primary": "claudeCode", "outcome": "ok", "answeredBy": "claudeCode", "label": "cloud", "errorKind": null}}
  ]
}
```

- [ ] **Step 2: Run the reference model to see it fail**

Run: `python3 tests/fixtures/ai/reference.py`
Expected: FAIL. The provider list differs (the reference does not know `claudeCode`), and every new case that needs the Claude plan to be a cloud provider fails with it:

```text
  ✗ provider ids
  ✗ claude plan preferred and ready → claude plan
  ✗ claude plan is the other cloud when the preferred has no key
  ✗ claude plan beats openai when the preferred cloud is openai without a key
  ✗ claude plan temporary failure → one local retry
  ✗ an explicit claude plan choice is used even when it is not ready
```


- [ ] **Step 3: Teach the reference model the new provider**

**Edit `tests/fixtures/ai/reference.py`**, find this text (it occurs exactly once):

```python
    ids = [p["id"] for p in cat["providers"]]
    check("provider ids", ids, ["anthropic", "openai", "google", "ollama", "lmstudio",
                                "llamacpp", "jan", "apple", "custom"])
    ports = {p["id"]: p.get("port") for p in cat["providers"] if p.get("port")}
    check("local ports", ports, {"ollama": 11434, "lmstudio": 1234, "llamacpp": 8080, "jan": 1337})
```

and replace it with:

```python
    ids = [p["id"] for p in cat["providers"]]
    check("provider ids", ids, ["anthropic", "openai", "google", "ollama", "lmstudio",
                                "llamacpp", "jan", "apple", "custom", "claudeCode"])
    ports = {p["id"]: p.get("port") for p in cat["providers"] if p.get("port")}
    check("local ports", ports, {"ollama": 11434, "lmstudio": 1234, "llamacpp": 8080, "jan": 1337})
```

**Edit `tests/fixtures/ai/reference.py`**, find this text (it occurs exactly once):

```python
BILLING_CODES = {"insufficient_quota", "credit_balance_exhausted", "organization_usage_limit_exceeded",
                 "billing_error"}
CLOUD = {"anthropic", "openai", "google"}


def _cloud_choice(inp):
    order = [inp["preferredCloud"]] + [p for p in ("anthropic", "openai") if p != inp["preferredCloud"]] + ["google"]
    for p in order:
        if p in inp["keys"]:
```

and replace it with:

```python
BILLING_CODES = {"insufficient_quota", "credit_balance_exhausted", "organization_usage_limit_exceeded",
                 "billing_error"}
CLOUD = {"anthropic", "openai", "google", "claudeCode"}


def _cloud_choice(inp):
    order = [inp["preferredCloud"]] + [p for p in ("claudeCode", "anthropic", "openai") if p != inp["preferredCloud"]] + ["google"]
    for p in order:
        if p in inp["keys"]:
```

- [ ] **Step 4: Run it again**

Run: `python3 tests/fixtures/ai/reference.py`
Expected: PASS, every line starts with `✓` and there is no `✗`.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/ai/providers.json tests/fixtures/ai/router-cases.json tests/fixtures/ai/reference.py
git commit -q -m "test(ai): the Claude plan joins the shared router fixtures" -m "Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```


### Task 2: Contract: the fake `claude`, its transcripts and the expected files

**Agent:** `nm-implementer-light`. Every file is given in full. Nothing here runs a real `claude`: the transcripts are built from the documented event shapes (the owner's manual checks in Tasks 13 and 20 confirm the undocumented failure shapes), and no real transcript is ever committed.

**Files:**
- Create: `tests/fixtures/ai/claude-code/fake_claude.py`, `reference.py`
- Create: `tests/fixtures/ai/claude-code/transcripts/*.jsonl` (13 transcripts)
- Create: `tests/fixtures/ai/claude-code/expected-args.json`, `expected-env.json`, `expected-parse.json`, `auth-status.json`, `versions.json`, `locator-cases.json`, `hook-routing.json`, `labels.json`, `copy.json`
- Modify: `scripts/test-ai-contract.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces, for every later task, the whole Claude Code contract in one folder:
  - **The fake `claude`** (`fake_claude.py`): answers `--version` and `auth status`, records `auth login`, and for `-p` records `{argv, env, cwd, stdin, pid}` as one JSON line in `$NM_FAKE_CLAUDE_LOG`, reads stdin to its end, then replays `$NM_FAKE_CLAUDE_TRANSCRIPT` (`__SESSION_ID__` and `__CWD__` are filled in) and exits `$NM_FAKE_CLAUDE_EXIT`. It can write a stderr text (`NM_FAKE_CLAUDE_STDERR`), hang after N lines (`NM_FAKE_CLAUDE_HANG_AFTER`) while a child process it started runs (its pid goes to `NM_FAKE_CLAUDE_CHILD_PIDFILE`), ignore interrupt and terminate while it hangs (`NM_FAKE_CLAUDE_STUBBORN`: only a kill stops it), and ask NotchMeow's socket for a permission (`NM_FAKE_CLAUDE_ASK_SOCKET`, for the owner's hand checks). It never contacts anything and never reads a login.
  - **Transcripts**: `success`, `tool-use`, `agent-steps`, `signed-out`, `plan-limit`, `api-key-rate-limit`, `offline`, `overloaded`, `crash`, `empty`, `max-turns`, `api-key-helper`, `unknown-source`.
  - **Expected files**, each a list of named cases both apps replay: `expected-args.json` (`cases[]` of `{name, platform, level, model, resume, sessionId, folder?, cwd, argv}`), `expected-env.json` (the stripped names and prefixes, and `cases[]` of `{name, platform, base, expect}`), `expected-parse.json` (`cases[]` of `{name, transcript, exit, stderr, platform, expect{engine, text, steps, finish, error}}`), `auth-status.json`, `versions.json` (minimum 2.1.211), `locator-cases.json`, `hook-routing.json`, `labels.json`, `copy.json`.
  - **`reference.py`**, an independent model of all of it in plain Python. It is the tie-breaker when an app and a fixture disagree.

- [ ] **Step 1: Create the transcripts (what the fake replays)**

**Create `tests/fixtures/ai/claude-code/transcripts/success.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-sonnet-5-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":["WebSearch","WebFetch"],"permissionMode":"dontAsk","apiKeySource":"none"}
{"type":"stream_event","event":{"type":"message_start","message":{"role":"assistant","content":[]}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bonjour "}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Zoé, "}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello! 🐱"}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"__SESSION_ID__"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Bonjour Zoé, hello! 🐱"}]},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"__SESSION_ID__"}
{"type":"result","subtype":"success","is_error":false,"result":"Bonjour Zoé, hello! 🐱","session_id":"__SESSION_ID__","total_cost_usd":0.0042,"usage":{"input_tokens":12,"output_tokens":9},"num_turns":1,"permission_denials":[],"terminal_reason":"completed"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/tool-use.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-sonnet-5-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":["Read","Grep","Glob","WebSearch","WebFetch"],"permissionMode":"dontAsk","apiKeySource":"none"}
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","resetsAt":1791301500},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_start","message":{"role":"assistant","content":[]}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I'll read "}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"the README."}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01A","name":"Read","input":{}}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"file_pa"}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"th\":\"/work/README.md\"}"}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_stop","index":1},"session_id":"__SESSION_ID__"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I'll read the README."},{"type":"tool_use","id":"toolu_01A","name":"Read","input":{"file_path":"/work/README.md"}}]},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"tool_use"}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"__SESSION_ID__"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01A","content":"# Demo project\nA tiny demo.","is_error":false}]},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_start","message":{"role":"assistant","content":[]}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01B","name":"Read","input":{}}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"file_path\":\"/work/missing.md\"}"}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"__SESSION_ID__"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01B","name":"Read","input":{"file_path":"/work/missing.md"}}]},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"tool_use"}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"__SESSION_ID__"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01B","content":"File does not exist.","is_error":true}]},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_start","message":{"role":"assistant","content":[]}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"It says "}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"it is a tiny demo."}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"__SESSION_ID__"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"It says it is a tiny demo."}]},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"__SESSION_ID__"}
{"type":"result","subtype":"success","is_error":false,"result":"It says it is a tiny demo.","session_id":"__SESSION_ID__","total_cost_usd":0.0131,"usage":{"input_tokens":410,"output_tokens":61},"num_turns":3,"permission_denials":[],"terminal_reason":"completed"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/agent-steps.jsonl`** with exactly this content:

```json
{"type": "system", "subtype": "init", "session_id": "__SESSION_ID__", "model": "claude-sonnet-5-5", "claude_code_version": "2.1.211", "cwd": "__CWD__", "tools": ["Bash", "Write", "Edit"], "permissionMode": "default", "apiKeySource": "none"}
{"type": "stream_event", "event": {"type": "message_start", "message": {"role": "assistant", "content": []}}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "tool_use", "id": "toolu_02A", "name": "Bash", "input": {}}}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "content_block_start", "index": 1, "content_block": {"type": "tool_use", "id": "toolu_02B", "name": "Write", "input": {}}}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "content_block_stop", "index": 0}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "content_block_stop", "index": 1}, "session_id": "__SESSION_ID__"}
{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "toolu_02A", "name": "Bash", "input": {"command": "npm test -- --watch=false\nsecond line", "description": "Run the tests"}}, {"type": "tool_use", "id": "toolu_02B", "name": "Write", "input": {"file_path": "/work/notes.txt", "content": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}}]}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "message_delta", "delta": {"stop_reason": "tool_use"}}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "message_stop"}, "session_id": "__SESSION_ID__"}
{"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_02B", "content": "File created", "is_error": false}, {"type": "tool_result", "tool_use_id": "toolu_02A", "content": "1 passed", "is_error": false}]}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "message_start", "message": {"role": "assistant", "content": []}}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Done."}}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "content_block_stop", "index": 0}, "session_id": "__SESSION_ID__"}
{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "Done."}]}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "message_delta", "delta": {"stop_reason": "end_turn"}}, "session_id": "__SESSION_ID__"}
{"type": "stream_event", "event": {"type": "message_stop"}, "session_id": "__SESSION_ID__"}
{"type": "result", "subtype": "success", "is_error": false, "result": "Done.", "session_id": "__SESSION_ID__", "total_cost_usd": 0.02, "usage": {"input_tokens": 5, "output_tokens": 5}, "num_turns": 2, "permission_denials": [], "terminal_reason": "completed"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/signed-out.jsonl`** with exactly this content:

```json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Not logged in · Please run /login"}]},"error":"authentication_failed","session_id":"__SESSION_ID__"}
{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login","session_id":"__SESSION_ID__","total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0},"num_turns":1,"permission_denials":[],"terminal_reason":"error"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/plan-limit.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-sonnet-5-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":["WebSearch","WebFetch"],"permissionMode":"dontAsk","apiKeySource":"none"}
{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":1791301500},"session_id":"__SESSION_ID__"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"You've hit your session limit · resets 3:45pm"}]},"error":"rate_limit","session_id":"__SESSION_ID__"}
{"type":"result","subtype":"success","is_error":true,"result":"You've hit your session limit · resets 3:45pm","session_id":"__SESSION_ID__","total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0},"num_turns":1,"permission_denials":[],"terminal_reason":"error"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/api-key-rate-limit.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-sonnet-5-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":["WebSearch","WebFetch"],"permissionMode":"dontAsk","apiKeySource":"user"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"API Error: Rate limit reached"}]},"error":"rate_limit","session_id":"__SESSION_ID__"}
{"type":"result","subtype":"success","is_error":true,"result":"API Error: Rate limit reached","session_id":"__SESSION_ID__","total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0},"num_turns":1,"permission_denials":[],"terminal_reason":"error"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/offline.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-sonnet-5-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":["WebSearch","WebFetch"],"permissionMode":"dontAsk","apiKeySource":"none"}
{"type":"system","subtype":"api_retry","attempt":1,"max_retries":10,"retry_delay_ms":1000,"error_status":null,"error":"unknown","session_id":"__SESSION_ID__"}
{"type":"system","subtype":"api_retry","attempt":2,"max_retries":10,"retry_delay_ms":2000,"error_status":null,"error":"unknown","session_id":"__SESSION_ID__"}
{"type":"result","subtype":"success","is_error":true,"result":"Unable to connect to API. Check your internet connection","session_id":"__SESSION_ID__","total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0},"num_turns":1,"permission_denials":[],"terminal_reason":"error"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/overloaded.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-sonnet-5-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":["WebSearch","WebFetch"],"permissionMode":"dontAsk","apiKeySource":"user"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"API Error: Overloaded"}]},"error":"overloaded","session_id":"__SESSION_ID__"}
{"type":"result","subtype":"success","is_error":true,"result":"API Error: Overloaded","session_id":"__SESSION_ID__","total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0},"num_turns":1,"permission_denials":[],"terminal_reason":"error"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/crash.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-sonnet-5-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":["WebSearch","WebFetch"],"permissionMode":"dontAsk","apiKeySource":"none"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Let me look"}},"session_id":"__SESSION_ID__"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_de
```

**Create `tests/fixtures/ai/claude-code/transcripts/empty.jsonl`** as an empty file.

**Create `tests/fixtures/ai/claude-code/transcripts/max-turns.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-opus-5-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":["WebSearch","WebFetch"],"permissionMode":"dontAsk","apiKeySource":"oauth"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Still working on it"}},"session_id":"__SESSION_ID__"}
{"type":"result","subtype":"error_max_turns","is_error":true,"result":"","session_id":"__SESSION_ID__","total_cost_usd":0.5,"usage":{"input_tokens":1,"output_tokens":1},"num_turns":25,"permission_denials":[],"terminal_reason":"max_turns"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/api-key-helper.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-haiku-4-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":["WebSearch","WebFetch"],"permissionMode":"dontAsk","apiKeySource":"project"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ok"}},"session_id":"__SESSION_ID__"}
{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"__SESSION_ID__","total_cost_usd":0.001,"usage":{"input_tokens":1,"output_tokens":1},"num_turns":1,"permission_denials":[],"terminal_reason":"completed"}
```

**Create `tests/fixtures/ai/claude-code/transcripts/unknown-source.jsonl`** with exactly this content:

```json
{"type":"system","subtype":"init","session_id":"__SESSION_ID__","model":"claude-sonnet-5-5","claude_code_version":"2.1.211","cwd":"__CWD__","tools":[],"permissionMode":"dontAsk"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}},"session_id":"__SESSION_ID__"}
{"type":"result","subtype":"success","is_error":false,"result":"hi","session_id":"__SESSION_ID__","total_cost_usd":0,"usage":{"input_tokens":1,"output_tokens":1},"num_turns":1,"permission_denials":[],"terminal_reason":"completed"}
```

- [ ] **Step 2: Create the fake `claude`**

**Create `tests/fixtures/ai/claude-code/fake_claude.py`** with exactly this content:

```python
#!/usr/bin/env python3
"""A stand-in for the `claude` program, for tests. It never contacts anything and never reads a login.

It records what it was started with, then plays back a transcript chosen by the test. Both apps' tests run
against it, so the Mac and Windows/Linux engines are held to the same command lines and the same transcripts.

What it understands (everything is controlled by environment variables, so a test can pass a clean one):
  claude --version                       prints NM_FAKE_CLAUDE_VERSION (default "2.1.211 (Claude Code)")
  claude auth status                     prints NM_FAKE_CLAUDE_AUTH_JSON (default {"authMethod":"claude.ai"}),
                                         exits NM_FAKE_CLAUDE_AUTH_EXIT (default 0)
  claude auth login                      records the call, exits 0
  claude -p ...                          a turn: reads stdin to its end (so a caller that forgets to close it hangs),
                                         then replays NM_FAKE_CLAUDE_TRANSCRIPT line by line and exits
                                         NM_FAKE_CLAUDE_EXIT (default 0)

  NM_FAKE_CLAUDE_LOG          append one JSON line per call: argv, env, cwd, stdin, pid
  NM_FAKE_CLAUDE_TRANSCRIPT   path of a .jsonl transcript; __SESSION_ID__ and __CWD__ are replaced
  NM_FAKE_CLAUDE_STDERR       text written to stderr before the transcript
  NM_FAKE_CLAUDE_EXIT         exit status after the transcript
  NM_FAKE_CLAUDE_HANG_AFTER   after this many transcript lines, stay alive until killed (a tool step that never ends)
  NM_FAKE_CLAUDE_CHILD_PIDFILE  when hanging, start a child process and write its pid here (the tree must die too)
  NM_FAKE_CLAUDE_STUBBORN     when hanging, ignore SIGINT and SIGTERM (only SIGKILL stops it)
  NM_FAKE_CLAUDE_PIDFILE      write this process's pid here
  NM_FAKE_CLAUDE_ASK_SOCKET   a Unix socket path (NotchMeow's nm.sock): after the first transcript line, send a
                              PermissionRequest hook payload for this run's session id, as the hook relay does, wait for
                              the one-line reply and record it in the log as {"permission": <reply>}. For checking the
                              approval card by hand against a Debug build; no test depends on it
"""
import json
import os
import signal
import socket
import subprocess
import sys
import time


def record(argv, stdin_text=""):
    path = os.environ.get("NM_FAKE_CLAUDE_LOG")
    if not path:
        return
    entry = {"argv": argv, "env": dict(os.environ), "cwd": os.getcwd(), "stdin": stdin_text, "pid": os.getpid()}
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def session_id(argv):
    for flag in ("--session-id", "--resume"):
        if flag in argv and argv.index(flag) + 1 < len(argv):
            return argv[argv.index(flag) + 1]
    return "00000000-0000-4000-8000-000000000000"


def ask_permission(path, sid, env):
    """What the hook relay does for a PermissionRequest: send one JSON line, read one line back."""
    payload = {"hook_event_name": "PermissionRequest", "session_id": sid, "tool_name": "Bash",
               "tool_input": {"command": "echo asked-by-the-fake"}, "cwd": os.getcwd()}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(130)
        s.connect(path)
        s.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        reply = s.makefile("r", encoding="utf-8").readline().strip()
    log = env.get("NM_FAKE_CLAUDE_LOG")
    if log:
        with open(log, "a", encoding="utf-8") as f:
            f.write(json.dumps({"permission": reply}) + "\n")


def hang(env):
    child = None
    pidfile = env.get("NM_FAKE_CLAUDE_CHILD_PIDFILE")
    if pidfile:
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(pidfile, "w", encoding="utf-8") as f:
            f.write(str(child.pid))

    def stop(*_):
        if child is not None:
            child.kill()
        os._exit(130)

    if env.get("NM_FAKE_CLAUDE_STUBBORN"):
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    else:
        signal.signal(signal.SIGINT, stop)
        signal.signal(signal.SIGTERM, stop)
    while True:
        time.sleep(0.05)


def main():
    argv = sys.argv[1:]
    env = os.environ
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    if env.get("NM_FAKE_CLAUDE_PIDFILE"):
        with open(env["NM_FAKE_CLAUDE_PIDFILE"], "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
    if argv[:1] == ["--version"]:
        record(argv)
        print(env.get("NM_FAKE_CLAUDE_VERSION", "2.1.211 (Claude Code)"))
        return 0
    if argv[:2] == ["auth", "status"]:
        record(argv)
        print(env.get("NM_FAKE_CLAUDE_AUTH_JSON", '{"authMethod":"claude.ai"}'))
        return int(env.get("NM_FAKE_CLAUDE_AUTH_EXIT", "0"))
    if argv[:2] == ["auth", "login"]:
        record(argv)
        return 0

    stdin_text = sys.stdin.read()
    record(argv, stdin_text)
    if env.get("NM_FAKE_CLAUDE_STDERR"):
        sys.stderr.write(env["NM_FAKE_CLAUDE_STDERR"])
        sys.stderr.flush()
    hang_after = env.get("NM_FAKE_CLAUDE_HANG_AFTER")
    path = env.get("NM_FAKE_CLAUDE_TRANSCRIPT")
    if path:
        sid, cwd = session_id(argv), os.getcwd()
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        for number, line in enumerate(lines, start=1):
            sys.stdout.write(line.replace("__SESSION_ID__", sid).replace("__CWD__", json.dumps(cwd, ensure_ascii=False)[1:-1]) + "\n")
            sys.stdout.flush()
            if number == 1 and env.get("NM_FAKE_CLAUDE_ASK_SOCKET"):
                ask_permission(env["NM_FAKE_CLAUDE_ASK_SOCKET"], sid, env)
            if hang_after is not None and number >= int(hang_after):
                hang(env)
    elif hang_after is not None:
        hang(env)
    return int(env.get("NM_FAKE_CLAUDE_EXIT", "0"))


if __name__ == "__main__":
    sys.exit(main())
```

Run: `chmod +x tests/fixtures/ai/claude-code/fake_claude.py`

- [ ] **Step 3: Create the expected files (the contract itself)**

**Create `tests/fixtures/ai/claude-code/expected-args.json`** with exactly this content:

```json
{
  "version": 1,
  "note": "One claude turn's arguments. Every quoted flag value is one argument (no shell). `cwd` says which folder the process runs in: the chat folder NotchMeow owns, or the user's folder. The folder never appears in the arguments.",
  "chatFolder": "/support/NotchMeow/claude-chat",
  "models": ["sonnet", "opus", "haiku"],
  "cases": [
    {"name": "chat only, first turn", "platform": "mac", "level": "chat", "model": "sonnet", "resume": false, "sessionId": "11111111-1111-4111-8111-111111111111", "cwd": "chatFolder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--session-id", "11111111-1111-4111-8111-111111111111", "--model", "sonnet", "--safe-mode", "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch", "--disallowedTools", "mcp__*", "--permission-mode", "dontAsk"]},
    {"name": "chat only, later turn", "platform": "mac", "level": "chat", "model": "sonnet", "resume": true, "sessionId": "11111111-1111-4111-8111-111111111111", "cwd": "chatFolder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--resume", "11111111-1111-4111-8111-111111111111", "--model", "sonnet", "--safe-mode", "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch", "--disallowedTools", "mcp__*", "--permission-mode", "dontAsk"]},
    {"name": "chat only, opus", "platform": "linux", "level": "chat", "model": "opus", "resume": false, "sessionId": "11111111-1111-4111-8111-111111111111", "cwd": "chatFolder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--session-id", "11111111-1111-4111-8111-111111111111", "--model", "opus", "--safe-mode", "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch", "--disallowedTools", "mcp__*", "--permission-mode", "dontAsk"]},
    {"name": "read-only, first turn", "platform": "mac", "level": "read", "model": "sonnet", "resume": false, "sessionId": "11111111-1111-4111-8111-111111111111", "folder": "/Users/zoe/Projects/notchmeow", "cwd": "folder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--session-id", "11111111-1111-4111-8111-111111111111", "--model", "sonnet", "--safe-mode", "--tools", "Read,Grep,Glob,WebSearch,WebFetch", "--allowedTools", "Read,Grep,Glob,WebSearch,WebFetch", "--permission-mode", "dontAsk", "--settings", "{\"permissions\":{\"blockReadsOutsideWorkingDirectories\":true}}"]},
    {"name": "read-only, later turn, haiku", "platform": "linux", "level": "read", "model": "haiku", "resume": true, "sessionId": "11111111-1111-4111-8111-111111111111", "folder": "/home/zoe/projects/notchmeow", "cwd": "folder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--resume", "11111111-1111-4111-8111-111111111111", "--model", "haiku", "--safe-mode", "--tools", "Read,Grep,Glob,WebSearch,WebFetch", "--allowedTools", "Read,Grep,Glob,WebSearch,WebFetch", "--permission-mode", "dontAsk", "--settings", "{\"permissions\":{\"blockReadsOutsideWorkingDirectories\":true}}"]},
    {"name": "read-only, a folder with spaces and non-ASCII", "platform": "mac", "level": "read", "model": "sonnet", "resume": false, "sessionId": "11111111-1111-4111-8111-111111111111", "folder": "/Users/Zoé/Mes projets/ünï côde", "cwd": "folder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--session-id", "11111111-1111-4111-8111-111111111111", "--model", "sonnet", "--safe-mode", "--tools", "Read,Grep,Glob,WebSearch,WebFetch", "--allowedTools", "Read,Grep,Glob,WebSearch,WebFetch", "--permission-mode", "dontAsk", "--settings", "{\"permissions\":{\"blockReadsOutsideWorkingDirectories\":true}}"]},
    {"name": "agent, first turn, macOS has the sandbox", "platform": "mac", "level": "agent", "model": "sonnet", "resume": false, "sessionId": "11111111-1111-4111-8111-111111111111", "folder": "/Users/zoe/Projects/notchmeow", "cwd": "folder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--session-id", "11111111-1111-4111-8111-111111111111", "--model", "sonnet", "--permission-mode", "default", "--settings", "{\"sandbox\":{\"enabled\":true,\"allowUnsandboxedCommands\":false,\"autoAllowBashIfSandboxed\":false}}"]},
    {"name": "agent, later turn, Linux has the sandbox", "platform": "linux", "level": "agent", "model": "opus", "resume": true, "sessionId": "11111111-1111-4111-8111-111111111111", "folder": "/home/zoe/projects/notchmeow", "cwd": "folder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--resume", "11111111-1111-4111-8111-111111111111", "--model", "opus", "--permission-mode", "default", "--settings", "{\"sandbox\":{\"enabled\":true,\"allowUnsandboxedCommands\":false,\"autoAllowBashIfSandboxed\":false}}"]},
    {"name": "agent on native Windows: no sandbox, every command asks", "platform": "windows", "level": "agent", "model": "sonnet", "resume": false, "sessionId": "11111111-1111-4111-8111-111111111111", "folder": "C:\\Users\\José\\Mis Proyectos", "cwd": "folder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--session-id", "11111111-1111-4111-8111-111111111111", "--model", "sonnet", "--permission-mode", "default"]},
    {"name": "read-only on native Windows, a folder with spaces", "platform": "windows", "level": "read", "model": "sonnet", "resume": false, "sessionId": "11111111-1111-4111-8111-111111111111", "folder": "C:\\Users\\José\\Mis Proyectos", "cwd": "folder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--session-id", "11111111-1111-4111-8111-111111111111", "--model", "sonnet", "--safe-mode", "--tools", "Read,Grep,Glob,WebSearch,WebFetch", "--allowedTools", "Read,Grep,Glob,WebSearch,WebFetch", "--permission-mode", "dontAsk", "--settings", "{\"permissions\":{\"blockReadsOutsideWorkingDirectories\":true}}"]},
    {"name": "chat only on native Windows", "platform": "windows", "level": "chat", "model": "haiku", "resume": true, "sessionId": "11111111-1111-4111-8111-111111111111", "cwd": "chatFolder", "argv": ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--resume", "11111111-1111-4111-8111-111111111111", "--model", "haiku", "--safe-mode", "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch", "--disallowedTools", "mcp__*", "--permission-mode", "dontAsk"]}
  ]
}
```

**Create `tests/fixtures/ai/claude-code/expected-env.json`** with exactly this content:

```json
{
  "version": 1,
  "note": "What a claude run keeps of the caller's environment. Names listed or starting with a listed prefix are dropped, whatever their value; they outrank the user's plan login. On Windows names compare without regard to case.",
  "stripped": ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_PROFILE"],
  "strippedPrefixes": ["CLAUDE_CODE_USE_"],
  "cases": [
    {"name": "the variables that outrank the plan login are dropped", "platform": "mac", "base": {"PATH": "/usr/bin:/bin", "HOME": "/Users/zoe", "ANTHROPIC_API_KEY": "sk-ant-FAKE", "ANTHROPIC_AUTH_TOKEN": "tok-FAKE", "CLAUDE_CODE_OAUTH_TOKEN": "oauth-FAKE", "ANTHROPIC_PROFILE": "work"}, "expect": {"PATH": "/usr/bin:/bin", "HOME": "/Users/zoe"}},
    {"name": "every CLAUDE_CODE_USE_ variable goes", "platform": "linux", "base": {"PATH": "/usr/bin", "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_USE_VERTEX": "1", "CLAUDE_CODE_USE_FOUNDRY": "1", "CLAUDE_CODE_USE_ANYTHING_NEW": "1"}, "expect": {"PATH": "/usr/bin"}},
    {"name": "similar names stay", "platform": "mac", "base": {"MY_ANTHROPIC_API_KEY": "x", "ANTHROPIC_BASE_URL": "https://proxy.example", "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Git\\bin\\bash.exe", "CLAUDE_CONFIG_DIR": "/c", "CLAUDE_CODE_USER": "1"}, "expect": {"MY_ANTHROPIC_API_KEY": "x", "ANTHROPIC_BASE_URL": "https://proxy.example", "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Git\\bin\\bash.exe", "CLAUDE_CONFIG_DIR": "/c", "CLAUDE_CODE_USER": "1"}},
    {"name": "an empty value is dropped too", "platform": "mac", "base": {"ANTHROPIC_API_KEY": "", "HOME": "/Users/zoe"}, "expect": {"HOME": "/Users/zoe"}},
    {"name": "names are case-sensitive on macOS and Linux", "platform": "mac", "base": {"anthropic_api_key": "x", "claude_code_use_bedrock": "1"}, "expect": {"anthropic_api_key": "x", "claude_code_use_bedrock": "1"}},
    {"name": "names are case-insensitive on Windows", "platform": "windows", "base": {"Anthropic_Api_Key": "x", "claude_code_use_bedrock": "1", "Path": "C:\\Windows", "SystemRoot": "C:\\Windows"}, "expect": {"Path": "C:\\Windows", "SystemRoot": "C:\\Windows"}},
    {"name": "nothing to drop", "platform": "linux", "base": {}, "expect": {}}
  ]
}
```

**Create `tests/fixtures/ai/claude-code/expected-parse.json`** with exactly this content:

```json
{
  "version": 1,
  "note": "What a transcript means, whatever the app. `exit` is the status the fake was told to exit with: it is informational, a classification never depends on it. `<sid>` is the session id the run was started with. Steps keep only command, file_path, path, query, pattern and url (each cut to 200 Unicode scalars): never a file's content. Text from different assistant messages is joined by a blank line. A crash is an `interrupted` error with the code nm_claude_crashed; the chat turns it into \"stopped unexpectedly\" when there is no text to keep.",
  "sessionId": "11111111-1111-4111-8111-111111111111",
  "cwd": "/work",
  "cases": [
    {"name": "a plain answer", "transcript": "success.jsonl", "exit": 0, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-sonnet-5-5", "paidBy": "plan", "version": "2.1.211"}, "text": "Bonjour Zoé, hello! 🐱", "steps": [], "finish": "stop", "error": null}},
    {"name": "two tool steps, one fails, and the text reads as paragraphs", "transcript": "tool-use.jsonl", "exit": 0, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-sonnet-5-5", "paidBy": "plan", "version": "2.1.211"}, "text": "I'll read the README.\n\nIt says it is a tiny demo.", "steps": [{"id": "toolu_01A", "tool": "Read", "input": {"file_path": "/work/README.md"}, "state": "done"}, {"id": "toolu_01B", "tool": "Read", "input": {"file_path": "/work/missing.md"}, "state": "failed"}], "finish": "stop", "error": null}},
    {"name": "a step keeps only the fields that say what it does", "transcript": "agent-steps.jsonl", "exit": 0, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-sonnet-5-5", "paidBy": "plan", "version": "2.1.211"}, "text": "Done.", "steps": [{"id": "toolu_02A", "tool": "Bash", "input": {"command": "npm test -- --watch=false\nsecond line"}, "state": "done"}, {"id": "toolu_02B", "tool": "Write", "input": {"file_path": "/work/notes.txt"}, "state": "done"}], "finish": "stop", "error": null}},
    {"name": "signed out, in the result", "transcript": "signed-out.jsonl", "exit": 1, "stderr": "", "platform": "mac", "expect": {"engine": null, "text": "", "steps": [], "finish": null, "error": {"kind": "auth", "code": "nm_signed_out", "resetsAt": null}}},
    {"name": "signed out, only on stderr", "transcript": "empty.jsonl", "exit": 1, "stderr": "Not logged in · Please run /login\n", "platform": "mac", "expect": {"engine": null, "text": "", "steps": [], "finish": null, "error": {"kind": "auth", "code": "nm_signed_out", "resetsAt": null}}},
    {"name": "the plan's limit, with when it resets", "transcript": "plan-limit.jsonl", "exit": 1, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-sonnet-5-5", "paidBy": "plan", "version": "2.1.211"}, "text": "", "steps": [], "finish": null, "error": {"kind": "billing", "code": "nm_plan_limit", "resetsAt": 1791301500}}},
    {"name": "an API key's rate limit is only a rate limit", "transcript": "api-key-rate-limit.jsonl", "exit": 1, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-sonnet-5-5", "paidBy": "api_key", "version": "2.1.211"}, "text": "", "steps": [], "finish": null, "error": {"kind": "rate_limited", "code": null, "resetsAt": null}}},
    {"name": "Anthropic is overloaded", "transcript": "overloaded.jsonl", "exit": 1, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-sonnet-5-5", "paidBy": "api_key", "version": "2.1.211"}, "text": "", "steps": [], "finish": null, "error": {"kind": "overloaded", "code": null, "resetsAt": null}}},
    {"name": "offline: retries, then an error result", "transcript": "offline.jsonl", "exit": 1, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-sonnet-5-5", "paidBy": "plan", "version": "2.1.211"}, "text": "", "steps": [], "finish": null, "error": {"kind": "unreachable", "code": "nm_claude_offline", "resetsAt": null}}},
    {"name": "cut in the middle of a line, after some text", "transcript": "crash.jsonl", "exit": 2, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-sonnet-5-5", "paidBy": "plan", "version": "2.1.211"}, "text": "Let me look", "steps": [], "finish": null, "error": {"kind": "interrupted", "code": "nm_claude_crashed", "resetsAt": null}}},
    {"name": "a crash with no output at all", "transcript": "empty.jsonl", "exit": 139, "stderr": "", "platform": "mac", "expect": {"engine": null, "text": "", "steps": [], "finish": null, "error": {"kind": "interrupted", "code": "nm_claude_crashed", "resetsAt": null}}},
    {"name": "a clean exit that never sent a result", "transcript": "empty.jsonl", "exit": 0, "stderr": "", "platform": "mac", "expect": {"engine": null, "text": "", "steps": [], "finish": null, "error": {"kind": "interrupted", "code": "nm_claude_crashed", "resetsAt": null}}},
    {"name": "too many turns keeps what was said", "transcript": "max-turns.jsonl", "exit": 1, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-opus-5-5", "paidBy": "plan", "version": "2.1.211"}, "text": "Still working on it", "steps": [], "finish": "length", "error": null}},
    {"name": "a project's API key is an API key", "transcript": "api-key-helper.jsonl", "exit": 0, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-haiku-4-5", "paidBy": "api_key", "version": "2.1.211"}, "text": "ok", "steps": [], "finish": "stop", "error": null}},
    {"name": "an init without apiKeySource says nothing about who pays", "transcript": "unknown-source.jsonl", "exit": 0, "stderr": "", "platform": "mac", "expect": {"engine": {"sessionId": "<sid>", "model": "claude-sonnet-5-5", "paidBy": "unknown", "version": "2.1.211"}, "text": "hi", "steps": [], "finish": "stop", "error": null}},
    {"name": "too old: an option it does not know", "transcript": "empty.jsonl", "exit": 1, "stderr": "error: unknown option '--safe-mode'\n", "platform": "mac", "expect": {"engine": null, "text": "", "steps": [], "finish": null, "error": {"kind": "bad_request", "code": "nm_claude_old", "resetsAt": null}}},
    {"name": "Windows without Git for Windows", "transcript": "empty.jsonl", "exit": 1, "stderr": "Claude Code on Windows requires git-bash (https://git-scm.com/downloads/win). If installed but not in PATH, set environment variable pointing to your bash.exe, similar to: CLAUDE_CODE_GIT_BASH_PATH=C:\\Program Files\\Git\\bin\\bash.exe\n", "platform": "windows", "expect": {"engine": null, "text": "", "steps": [], "finish": null, "error": {"kind": "bad_request", "code": "nm_needs_git", "resetsAt": null}}}
  ]
}
```

**Create `tests/fixtures/ai/claude-code/auth-status.json`** with exactly this content:

```json
{
  "version": 1,
  "note": "`claude auth status` exits 0 when signed in and 1 when not. Only `authMethod` is read; every other field is ignored and never kept. `exit` is null when the program could not be run.",
  "authMethods": ["none", "claude.ai", "oauth_token", "api_key", "api_key_helper", "third_party"],
  "cases": [
    {"name": "signed in with a Claude plan", "exit": 0, "stdout": "{\"authMethod\":\"claude.ai\"}", "expect": {"state": "signedIn", "authMethod": "claude.ai"}},
    {"name": "an OAuth token", "exit": 0, "stdout": "{\"authMethod\":\"oauth_token\"}", "expect": {"state": "signedIn", "authMethod": "oauth_token"}},
    {"name": "an API key", "exit": 0, "stdout": "{\"authMethod\":\"api_key\"}", "expect": {"state": "signedIn", "authMethod": "api_key"}},
    {"name": "an API key helper", "exit": 0, "stdout": "{\"authMethod\":\"api_key_helper\"}", "expect": {"state": "signedIn", "authMethod": "api_key_helper"}},
    {"name": "a cloud account", "exit": 0, "stdout": "{\"authMethod\":\"third_party\"}", "expect": {"state": "signedIn", "authMethod": "third_party"}},
    {"name": "signed out: exit 1 and none", "exit": 1, "stdout": "{\"authMethod\":\"none\"}", "expect": {"state": "signedOut", "authMethod": null}},
    {"name": "signed out: exit 1 and nothing on stdout", "exit": 1, "stdout": "", "expect": {"state": "signedOut", "authMethod": null}},
    {"name": "none on exit 0 is still signed out", "exit": 0, "stdout": "{\"authMethod\":\"none\"}", "expect": {"state": "signedOut", "authMethod": null}},
    {"name": "other fields are ignored", "exit": 0, "stdout": "{\"authMethod\":\"claude.ai\",\"email\":\"someone@example.com\",\"orgName\":\"Example Org\"}", "expect": {"state": "signedIn", "authMethod": "claude.ai"}},
    {"name": "a method this build does not know", "exit": 0, "stdout": "{\"authMethod\":\"something_new\"}", "expect": {"state": "signedIn", "authMethod": "something_new"}},
    {"name": "exit 0 with output that is not JSON", "exit": 0, "stdout": "Logged in as someone", "expect": {"state": "signedIn", "authMethod": null}},
    {"name": "any other exit status is unknown", "exit": 2, "stdout": "", "expect": {"state": "unknown", "authMethod": null}},
    {"name": "the program could not be run", "exit": null, "stdout": "", "expect": {"state": "unknown", "authMethod": null}}
  ]
}
```

**Create `tests/fixtures/ai/claude-code/versions.json`** with exactly this content:

```json
{
  "version": 1,
  "note": "The version is the first x.y.z in the output of `claude --version`. The minimum is the version the flags in expected-args.json were verified against (2026-10-06); one number to lower once older versions are checked.",
  "minimum": [2, 1, 211],
  "parse": [{"text": "2.1.211 (Claude Code)", "expect": [2, 1, 211]}, {"text": "2.1.211 (Claude Code)\n", "expect": [2, 1, 211]}, {"text": "claude 2.2.5", "expect": [2, 2, 5]}, {"text": "10.0.0 (Claude Code)", "expect": [10, 0, 0]}, {"text": "nonsense", "expect": null}, {"text": "", "expect": null}],
  "check": [
    {"version": [2, 1, 211], "expect": "ok"},
    {"version": [2, 1, 210], "expect": "tooOld"},
    {"version": [2, 0, 999], "expect": "tooOld"},
    {"version": [2, 2, 0], "expect": "ok"},
    {"version": [10, 0, 0], "expect": "ok"},
    {"version": null, "expect": "unknown"}
  ]
}
```

**Create `tests/fixtures/ai/claude-code/locator-cases.json`** with exactly this content:

```json
{
  "version": 1,
  "note": "Where claude is looked for, in order. macOS and Linux: ~/.local/bin/claude, /opt/homebrew/bin/claude, /usr/local/bin/claude, ~/.npm-global/bin/claude, $NPM_CONFIG_PREFIX/bin/claude, then the login shell's `command -v claude` (asked only when nothing earlier exists). Windows: %USERPROFILE%\\.local\\bin\\claude.exe first, then claude.exe on PATH unless it sits in a Claude Desktop folder (a name that contains anthropicclaude or windowsapps, any case). A claude.cmd shim is never run: it cannot take JSON arguments safely.",
  "windowsDesktopMarkers": ["anthropicclaude", "windowsapps"],
  "cases": [
    {"name": "the official installer's link wins", "platform": "mac", "home": "/Users/zoe", "env": {}, "executables": ["/Users/zoe/.local/bin/claude", "/opt/homebrew/bin/claude"], "loginShell": null, "expect": "/Users/zoe/.local/bin/claude", "shimOnly": false, "loginShellCalled": false},
    {"name": "Homebrew on Apple silicon", "platform": "mac", "home": "/Users/zoe", "env": {}, "executables": ["/opt/homebrew/bin/claude"], "loginShell": null, "expect": "/opt/homebrew/bin/claude", "shimOnly": false, "loginShellCalled": false},
    {"name": "Homebrew on Intel", "platform": "mac", "home": "/Users/zoe", "env": {}, "executables": ["/usr/local/bin/claude"], "loginShell": null, "expect": "/usr/local/bin/claude", "shimOnly": false, "loginShellCalled": false},
    {"name": "the npm global bin", "platform": "linux", "home": "/home/zoe", "env": {}, "executables": ["/home/zoe/.npm-global/bin/claude"], "loginShell": null, "expect": "/home/zoe/.npm-global/bin/claude", "shimOnly": false, "loginShellCalled": false},
    {"name": "an npm prefix from the environment", "platform": "linux", "home": "/home/zoe", "env": {"NPM_CONFIG_PREFIX": "/opt/npm"}, "executables": ["/opt/npm/bin/claude"], "loginShell": null, "expect": "/opt/npm/bin/claude", "shimOnly": false, "loginShellCalled": false},
    {"name": "the login shell finds it in a folder nothing else knows", "platform": "mac", "home": "/Users/zoe", "env": {}, "executables": ["/Users/zoe/tools/bin/claude"], "loginShell": "/Users/zoe/tools/bin/claude\n", "expect": "/Users/zoe/tools/bin/claude", "shimOnly": false, "loginShellCalled": true},
    {"name": "the login shell answers with something that is not an absolute path", "platform": "mac", "home": "/Users/zoe", "env": {}, "executables": [], "loginShell": "claude: aliased to something\n", "expect": null, "shimOnly": false, "loginShellCalled": true},
    {"name": "the login shell names a file that is not there", "platform": "mac", "home": "/Users/zoe", "env": {}, "executables": [], "loginShell": "/Users/zoe/gone/claude\n", "expect": null, "shimOnly": false, "loginShellCalled": true},
    {"name": "nothing installed", "platform": "linux", "home": "/home/zoe", "env": {}, "executables": [], "loginShell": null, "expect": null, "shimOnly": false, "loginShellCalled": true},
    {"name": "a home folder with non-ASCII characters and spaces", "platform": "mac", "home": "/Users/Zoé Ünï", "env": {}, "executables": ["/Users/Zoé Ünï/.local/bin/claude"], "loginShell": null, "expect": "/Users/Zoé Ünï/.local/bin/claude", "shimOnly": false, "loginShellCalled": false},
    {"name": ".local\\bin wins over a Desktop claude.exe that shadows it on PATH", "platform": "windows", "home": "C:\\Users\\José", "env": {"PATH": "C:\\Users\\José\\AppData\\Local\\AnthropicClaude\\app-1.0.0;C:\\Windows\\System32"}, "executables": ["C:\\Users\\José\\.local\\bin\\claude.exe", "C:\\Users\\José\\AppData\\Local\\AnthropicClaude\\app-1.0.0\\claude.exe"], "loginShell": null, "expect": "C:\\Users\\José\\.local\\bin\\claude.exe", "shimOnly": false, "loginShellCalled": false},
    {"name": "only Claude Desktop on PATH is nothing", "platform": "windows", "home": "C:\\Users\\José", "env": {"PATH": "C:\\Users\\José\\AppData\\Local\\AnthropicClaude\\app-1.0.0"}, "executables": ["C:\\Users\\José\\AppData\\Local\\AnthropicClaude\\app-1.0.0\\claude.exe"], "loginShell": null, "expect": null, "shimOnly": false, "loginShellCalled": false},
    {"name": "a Desktop folder in another case is still Desktop", "platform": "windows", "home": "C:\\Users\\José", "env": {"PATH": "C:\\Users\\José\\AppData\\Local\\ANTHROPICCLAUDE\\app-1.0.0"}, "executables": ["C:\\Users\\José\\AppData\\Local\\ANTHROPICCLAUDE\\app-1.0.0\\claude.exe"], "loginShell": null, "expect": null, "shimOnly": false, "loginShellCalled": false},
    {"name": "a claude.exe elsewhere on PATH", "platform": "windows", "home": "C:\\Users\\José", "env": {"PATH": "C:\\Tools;C:\\Windows"}, "executables": ["C:\\Tools\\claude.exe"], "loginShell": null, "expect": "C:\\Tools\\claude.exe", "shimOnly": false, "loginShellCalled": false},
    {"name": "only a claude.cmd shim is not run", "platform": "windows", "home": "C:\\Users\\José", "env": {"PATH": "C:\\Users\\José\\AppData\\Roaming\\npm"}, "executables": ["C:\\Users\\José\\AppData\\Roaming\\npm\\claude.cmd"], "loginShell": null, "expect": null, "shimOnly": true, "loginShellCalled": false}
  ]
}
```

**Create `tests/fixtures/ai/claude-code/hook-routing.json`** with exactly this content:

```json
{
  "version": 1,
  "note": "Which hook payloads belong to a chat. `live` is the set of session ids NotchMeow chose with --session-id for chats that are still open. Only an exact match of a string `session_id` counts, and a payload from another agent (`nm_agent`) never does. 'chat' payloads go to that chat and never create or touch a pill; everything else is handled exactly as before.",
  "live": ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"],
  "cases": [
    {"name": "a chat's permission request", "payload": {"hook_event_name": "PermissionRequest", "session_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "tool_name": "Bash", "tool_input": {"command": "ls"}, "cwd": "/work"}, "expect": "chat"},
    {"name": "the other live chat's request", "payload": {"hook_event_name": "PermissionRequest", "session_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "tool_name": "Edit"}, "expect": "chat"},
    {"name": "a chat's other events are swallowed too", "payload": {"hook_event_name": "PreToolUse", "session_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "tool_name": "Read"}, "expect": "chat"},
    {"name": "a chat's question hook", "payload": {"nm_kind": "ask_user_question", "session_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}, "expect": "chat"},
    {"name": "the user's own session", "payload": {"hook_event_name": "PermissionRequest", "session_id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "term_program": "vscode", "tool_name": "Bash"}, "expect": "other"},
    {"name": "a session id that is not live any more", "payload": {"hook_event_name": "PermissionRequest", "session_id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc"}, "live": ["bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"], "expect": "other"},
    {"name": "nothing is live", "payload": {"hook_event_name": "PermissionRequest", "session_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}, "live": [], "expect": "other"},
    {"name": "no session id", "payload": {"hook_event_name": "PermissionRequest", "tool_name": "Bash"}, "expect": "other"},
    {"name": "a session id that is not a string", "payload": {"hook_event_name": "PermissionRequest", "session_id": 42}, "expect": "other"},
    {"name": "an empty session id", "payload": {"hook_event_name": "PermissionRequest", "session_id": ""}, "expect": "other"},
    {"name": "Codex's conversation id is never a chat", "payload": {"hook_event_name": "PermissionRequest", "conversation_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "nm_agent": "codex"}, "expect": "other"},
    {"name": "another agent that carries a live id", "payload": {"hook_event_name": "PermissionRequest", "session_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "nm_agent": "gemini"}, "expect": "other"},
    {"name": "the id in another case is not a match", "payload": {"hook_event_name": "PermissionRequest", "session_id": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"}, "expect": "other"}
  ]
}
```

**Create `tests/fixtures/ai/claude-code/labels.json`** with exactly this content:

```json
{
  "version": 1,
  "note": "Words on the two chips. The model chip says who pays: init's apiKeySource wins once a turn has run, the status's authMethod before that. The level chip names the folder by its last part.",
  "modelChip": [
    {"name": "not run yet, signed in with a plan", "authMethod": "claude.ai", "paidBy": null, "expect": "Claude · your plan"},
    {"name": "an OAuth token is a plan too", "authMethod": "oauth_token", "paidBy": null, "expect": "Claude · your plan"},
    {"name": "init says plan", "authMethod": "claude.ai", "paidBy": "plan", "expect": "Claude · your plan"},
    {"name": "init says API key even though the status said plan (an apiKeyHelper)", "authMethod": "claude.ai", "paidBy": "api_key", "expect": "Claude · API key"},
    {"name": "an API key, not run yet", "authMethod": "api_key", "paidBy": null, "expect": "Claude · API key"},
    {"name": "an API key helper, not run yet", "authMethod": "api_key_helper", "paidBy": null, "expect": "Claude · API key"},
    {"name": "a cloud account is neither", "authMethod": "third_party", "paidBy": "plan", "expect": "Claude"},
    {"name": "nothing known", "authMethod": null, "paidBy": null, "expect": "Claude"},
    {"name": "init without a source and no status", "authMethod": null, "paidBy": "unknown", "expect": "Claude"},
    {"name": "init says plan and the status is unknown", "authMethod": null, "paidBy": "plan", "expect": "Claude · your plan"}
  ],
  "levelChip": [
    {"level": "chat", "folder": null, "expect": "Chat only"},
    {"level": "read", "folder": "/Users/zoe/Projects/notchmeow", "expect": "Read-only · notchmeow"},
    {"level": "read", "folder": "/Users/Zoé/Mes projets/ünï côde/", "expect": "Read-only · ünï côde"},
    {"level": "agent", "folder": "C:\\Users\\José\\Mis Proyectos", "expect": "Agent · Mis Proyectos"},
    {"level": "agent", "folder": "C:\\Users\\José\\Mis Proyectos\\", "expect": "Agent · Mis Proyectos"},
    {"level": "agent", "folder": "/", "expect": "Agent · /"},
    {"level": "agent", "folder": "C:\\", "expect": "Agent · C:"},
    {"level": "read", "folder": null, "expect": "Read-only"}
  ]
}
```

**Create `tests/fixtures/ai/claude-code/copy.json`** with exactly this content:

```json
{
  "version": 1,
  "note": "What the chat says for each Claude Code failure (the codes are AIError.code / AiError.code on top of the twelve shared error kinds). `resetsAt` is Unix seconds; the time is shown in the viewer's time zone and locale, lower-cased (3:45 pm). `action` is the one button under the note.",
  "cases": [
    {"code": "nm_claude_missing", "kind": "unreachable", "text": "Claude Code isn't installed.", "action": "installGuide"},
    {"code": "nm_signed_out", "kind": "auth", "text": "Claude Code is signed out.", "action": "signIn"},
    {"code": "nm_plan_limit", "kind": "billing", "resetsAt": null, "text": "Your Claude plan's limit was reached.", "action": null},
    {"code": "nm_plan_limit", "kind": "billing", "resetsAt": 1791301500, "timeZone": "UTC", "locale": "en_US", "text": "Your Claude plan's limit resets at 3:45 pm.", "action": null},
    {"code": "nm_plan_limit", "kind": "billing", "resetsAt": 1791301500, "timeZone": "UTC", "locale": "fr_FR", "text": "Your Claude plan's limit resets at 15:45.", "action": null},
    {"code": "nm_claude_old", "kind": "bad_request", "text": "Update Claude Code.", "action": "updateGuide"},
    {"code": "nm_claude_crashed", "kind": "server", "text": "Claude stopped unexpectedly.", "action": "retry"},
    {"code": "nm_claude_offline", "kind": "unreachable", "text": "Couldn't reach Claude.", "action": null},
    {"code": "nm_needs_git", "kind": "bad_request", "text": "Claude Code needs Git for Windows.", "action": "gitGuide"},
    {"code": "nm_folder_missing", "kind": "bad_request", "text": "That folder isn't there any more. Pick another one.", "action": null}
  ]
}
```

- [ ] **Step 4: Run the reference model: there is none yet**

Run: `python3 tests/fixtures/ai/claude-code/reference.py`
Expected: FAIL, `No such file or directory`.

- [ ] **Step 5: Create the reference model**

It builds each command line, environment and parse result itself, from the rules in the spec, and compares them with the files above; it also runs the fake once to prove the fake replays what it is given.

**Create `tests/fixtures/ai/claude-code/reference.py`** with exactly this content:

```python
#!/usr/bin/env python3
"""Reference implementation of the Claude Code engine's contract (E3).

Every fixture in this folder is run against a small, obviously-correct Python model: the command line per
level and turn, the cleaned environment, what a transcript means, `claude auth status`, versions, where
claude is looked for, which hook payloads belong to a chat, and the words on the chips. It also runs the
fake `claude` once to prove it replays what it is given. Both apps implement the same behaviour natively;
this file is the tie-breaker when they disagree. It never runs the real `claude`.
"""
import datetime
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
FAILURES = 0


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


def check(label, got, expected):
    global FAILURES
    if got == expected:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}\n    got:      {got!r}\n    expected: {expected!r}")
        FAILURES += 1


# ── the command line ─────────────────────────────────────────────────────────────

BASE = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--include-partial-messages"]
READ_TOOLS = "Read,Grep,Glob,WebSearch,WebFetch"
CHAT_TOOLS = "WebSearch,WebFetch"


def build_args(platform, level, model, resume, session_id):
    args = BASE + (["--resume", session_id] if resume else ["--session-id", session_id]) + ["--model", model]
    if level == "chat":
        return args + ["--safe-mode", "--tools", CHAT_TOOLS, "--allowedTools", CHAT_TOOLS,
                       "--disallowedTools", "mcp__*", "--permission-mode", "dontAsk"]
    if level == "read":
        return args + ["--safe-mode", "--tools", READ_TOOLS, "--allowedTools", READ_TOOLS,
                       "--permission-mode", "dontAsk",
                       "--settings", '{"permissions":{"blockReadsOutsideWorkingDirectories":true}}']
    args += ["--permission-mode", "default"]
    if platform != "windows":
        args += ["--settings", '{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":false}}']
    return args


def check_args():
    print("expected-args.json")
    data = load("expected-args.json")
    check("models", data["models"], ["sonnet", "opus", "haiku"])
    for c in data["cases"]:
        check(c["name"], build_args(c["platform"], c["level"], c["model"], c["resume"], c["sessionId"]), c["argv"])
        check(c["name"] + " (the folder is not in the arguments)",
              any(c.get("folder", "\0") in a for a in c["argv"]), False)


# ── the environment ──────────────────────────────────────────────────────────────

def clean_env(base, platform, stripped, prefixes):
    ci = platform == "windows"
    names = {n.upper() if ci else n for n in stripped}
    pre = [p.upper() if ci else p for p in prefixes]
    out = {}
    for k, v in base.items():
        key = k.upper() if ci else k
        if key in names or any(key.startswith(p) for p in pre):
            continue
        out[k] = v
    return out


def check_env():
    print("expected-env.json")
    data = load("expected-env.json")
    for c in data["cases"]:
        check(c["name"], clean_env(c["base"], c["platform"], data["stripped"], data["strippedPrefixes"]), c["expect"])


# ── what a transcript means ──────────────────────────────────────────────────────

STEP_FIELDS = ["command", "file_path", "path", "query", "pattern", "url"]
STEP_FIELD_CAP = 200
KEY_SOURCES = {"none": "plan", "oauth": "plan", "user": "api_key", "project": "api_key", "org": "api_key",
               "temporary": "api_key"}


def step_input(raw):
    out = {}
    for k in STEP_FIELDS:
        v = raw.get(k) if isinstance(raw, dict) else None
        if isinstance(v, str):
            out[k] = v[:STEP_FIELD_CAP]
    return out


def parse(lines, exit_code, stderr, platform="mac"):
    engine, text, steps, order = None, "", {}, []
    needs_break = False
    result, assistant_error, rejected, retried = None, None, None, False
    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if not isinstance(ev, dict):
            continue
        t = ev.get("type")
        if t == "system" and ev.get("subtype") == "init":
            engine = {"sessionId": ev.get("session_id"), "model": ev.get("model"),
                      "paidBy": KEY_SOURCES.get(ev.get("apiKeySource"), "unknown"),
                      "version": ev.get("claude_code_version")}
        elif t == "system" and ev.get("subtype") == "api_retry":
            retried = True
        elif t == "stream_event":
            e = ev.get("event") or {}
            et = e.get("type")
            if et == "message_start":
                needs_break = needs_break or text != ""
            elif et == "content_block_start":
                block = e.get("content_block") or {}
                if block.get("type") == "tool_use" and isinstance(block.get("id"), str):
                    needs_break = needs_break or text != ""
                    if block["id"] not in steps:
                        order.append(block["id"])
                    steps[block["id"]] = {"id": block["id"], "tool": block.get("name", ""), "input": {},
                                          "state": "running"}
                elif block.get("type") == "text" and needs_break and text != "":
                    text += "\n\n"
                    needs_break = False
            elif et == "content_block_delta":
                d = e.get("delta") or {}
                if d.get("type") == "text_delta" and isinstance(d.get("text"), str):
                    if needs_break and text != "":
                        text += "\n\n"
                    needs_break = False
                    text += d["text"]
        elif t == "assistant":
            if isinstance(ev.get("error"), str):
                assistant_error = ev["error"]
            for block in (ev.get("message") or {}).get("content") or []:
                if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("id") in steps:
                    steps[block["id"]]["input"] = step_input(block.get("input"))
        elif t == "user":
            content = (ev.get("message") or {}).get("content")
            for block in content if isinstance(content, list) else []:
                if isinstance(block, dict) and block.get("type") == "tool_result" and block.get("tool_use_id") in steps:
                    steps[block["tool_use_id"]]["state"] = "failed" if block.get("is_error") else "done"
        elif t == "rate_limit_event":
            info = ev.get("rate_limit_info") or {}
            if info.get("status") == "rejected":
                rejected = info.get("resetsAt") if isinstance(info.get("resetsAt"), (int, float)) else 0
        elif t == "result":
            result = ev
    out = {"engine": engine, "text": text, "steps": [steps[i] for i in order], "finish": None, "error": None}
    if result is not None and not result.get("is_error") and result.get("subtype") == "success":
        out["finish"] = "stop"
        return out
    if result is not None and result.get("subtype") == "error_max_turns":
        out["finish"] = "length"
        return out
    words = ((result or {}).get("result") if result is not None else "") or ""
    blob = (words + "\n" + stderr).lower()
    paid = engine["paidBy"] if engine else None

    def failure(kind, code=None, resets=None):
        out["error"] = {"kind": kind, "code": code, "resetsAt": resets}
        return out

    if "git-bash" in blob or "claude_code_git_bash_path" in blob or "git for windows" in blob:
        return failure("bad_request", "nm_needs_git")
    if assistant_error == "authentication_failed" or "not logged in" in blob or "please run /login" in blob:
        return failure("auth", "nm_signed_out")
    if "unknown option" in blob:
        return failure("bad_request", "nm_claude_old")
    if rejected is not None or (assistant_error == "rate_limit" and paid == "plan"):
        return failure("billing", "nm_plan_limit", int(rejected) if rejected else None)
    if assistant_error == "rate_limit":
        return failure("rate_limited")
    if assistant_error == "billing_error":
        return failure("billing", "billing_error")
    if assistant_error == "overloaded":
        return failure("overloaded")
    if assistant_error == "server_error":
        return failure("server")
    if result is not None and (retried or "unable to connect" in blob):
        return failure("unreachable", "nm_claude_offline")
    return failure("interrupted", "nm_claude_crashed")


def check_parse():
    print("expected-parse.json")
    data = load("expected-parse.json")
    for c in data["cases"]:
        with open(os.path.join(HERE, "transcripts", c["transcript"]), encoding="utf-8") as f:
            raw = f.read().replace("__SESSION_ID__", data["sessionId"]).replace("__CWD__", data["cwd"])
        got = parse(raw.splitlines(), c["exit"], c["stderr"], c["platform"])
        expect = json.loads(json.dumps(c["expect"]).replace("<sid>", data["sessionId"]))
        check(c["name"], got, expect)


# ── auth status, versions, the locator ───────────────────────────────────────────

def auth_status(exit_code, stdout):
    if exit_code is None:
        return {"state": "unknown", "authMethod": None}
    method = None
    try:
        parsed = json.loads(stdout)
        if isinstance(parsed, dict) and isinstance(parsed.get("authMethod"), str):
            method = parsed["authMethod"]
    except ValueError:
        pass
    if exit_code == 1 or method == "none":
        return {"state": "signedOut", "authMethod": None}
    if exit_code == 0:
        return {"state": "signedIn", "authMethod": method}
    return {"state": "unknown", "authMethod": None}


def parse_version(text):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", text)
    return [int(m.group(1)), int(m.group(2)), int(m.group(3))] if m else None


def check_version(version, minimum):
    if version is None:
        return "unknown"
    return "ok" if version >= minimum else "tooOld"


def check_status_and_versions():
    print("auth-status.json")
    for c in load("auth-status.json")["cases"]:
        check(c["name"], auth_status(c["exit"], c["stdout"]), c["expect"])
    print("versions.json")
    data = load("versions.json")
    for c in data["parse"]:
        check(f"parse {c['text']!r}", parse_version(c["text"]), c["expect"])
    for c in data["check"]:
        check(f"check {c['version']}", check_version(c["version"], data["minimum"]), c["expect"])


def locate(platform, home, env, executables, login_shell):
    """Returns (path or None, shim_only, login_shell_called)."""
    exe = set(executables)
    if platform == "windows":
        markers = load("locator-cases.json")["windowsDesktopMarkers"]
        candidates = [home + "\\.local\\bin\\claude.exe"]
        shim = False
        for d in (env.get("PATH") or "").split(";"):
            if not d:
                continue
            if any(m in d.lower() for m in markers):
                continue
            candidates.append(d.rstrip("\\") + "\\claude.exe")
            shim = shim or (d.rstrip("\\") + "\\claude.cmd") in exe
        for c in candidates:
            if c in exe:
                return c, False, False
        return None, shim, False
    candidates = [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                  home + "/.npm-global/bin/claude"]
    if env.get("NPM_CONFIG_PREFIX"):
        candidates.append(env["NPM_CONFIG_PREFIX"].rstrip("/") + "/bin/claude")
    for c in candidates:
        if c in exe:
            return c, False, False
    lines = [ln.strip() for ln in (login_shell or "").splitlines() if ln.strip()]
    asked = True
    if lines and lines[-1].startswith("/") and lines[-1] in exe:
        return lines[-1], False, asked
    return None, False, asked


def check_locator():
    print("locator-cases.json")
    for c in load("locator-cases.json")["cases"]:
        path, shim, called = locate(c["platform"], c["home"], c["env"], c["executables"], c["loginShell"])
        # An unusual case: nothing earlier exists and the shell had nothing to say: it is still asked.
        check(c["name"], (path, shim, called if c["platform"] != "windows" else False),
              (c["expect"], c["shimOnly"], c["loginShellCalled"]))


# ── hook routing and the chips ───────────────────────────────────────────────────

def route_hook(payload, live):
    sid = payload.get("session_id")
    if isinstance(payload.get("nm_agent"), str) and payload["nm_agent"] != "":
        return "other"
    return "chat" if isinstance(sid, str) and sid != "" and sid in live else "other"


def check_hooks():
    print("hook-routing.json")
    data = load("hook-routing.json")
    for c in data["cases"]:
        check(c["name"], route_hook(c["payload"], set(c.get("live", data["live"]))), c["expect"])


def model_chip(auth_method, paid_by):
    if auth_method == "third_party":
        return "Claude"
    if paid_by == "plan":
        return "Claude · your plan"
    if paid_by == "api_key":
        return "Claude · API key"
    if auth_method in ("claude.ai", "oauth_token"):
        return "Claude · your plan"
    if auth_method in ("api_key", "api_key_helper"):
        return "Claude · API key"
    return "Claude"


def folder_name(folder):
    trimmed = folder.rstrip("/\\")
    if trimmed == "":
        return folder[:1] or ""
    return re.split(r"[/\\]", trimmed)[-1]


def level_chip(level, folder):
    words = {"chat": "Chat only", "read": "Read-only", "agent": "Agent"}[level]
    if level == "chat" or not folder:
        return words
    return f"{words} · {folder_name(folder)}"


def check_labels():
    print("labels.json")
    data = load("labels.json")
    for c in data["modelChip"]:
        check(c["name"], model_chip(c["authMethod"], c["paidBy"]), c["expect"])
    for c in data["levelChip"]:
        check(f"{c['level']} {c['folder']!r}", level_chip(c["level"], c["folder"]), c["expect"])


def reset_time(epoch, tz, locale):
    # The two locales the fixture uses: UTC only, English 12-hour and French 24-hour.
    d = datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc)
    if locale.startswith("en"):
        return f"{d.hour % 12 or 12}:{d.minute:02d} {'am' if d.hour < 12 else 'pm'}"
    return f"{d.hour:02d}:{d.minute:02d}"


def check_copy():
    print("copy.json")
    for c in load("copy.json")["cases"]:
        if c["code"] == "nm_plan_limit" and c.get("resetsAt"):
            text = f"Your Claude plan's limit resets at {reset_time(c['resetsAt'], c['timeZone'], c['locale'])}."
        elif c["code"] == "nm_plan_limit":
            text = "Your Claude plan's limit was reached."
        else:
            text = {"nm_claude_missing": "Claude Code isn't installed.", "nm_signed_out": "Claude Code is signed out.",
                    "nm_claude_old": "Update Claude Code.", "nm_claude_crashed": "Claude stopped unexpectedly.",
                    "nm_claude_offline": "Couldn't reach Claude.",
                    "nm_needs_git": "Claude Code needs Git for Windows.",
                    "nm_folder_missing": "That folder isn't there any more. Pick another one."}[c["code"]]
        check(f"{c['code']} {c.get('locale', '')}", text, c["text"])


# ── the transcripts and the fake claude ──────────────────────────────────────────

def check_fixture_files():
    print("transcripts/ and the fake claude")
    tdir = os.path.join(HERE, "transcripts")
    for name in sorted(os.listdir(tdir)):
        with open(os.path.join(tdir, name), encoding="utf-8") as f:
            lines = f.read().splitlines()
        bad = 0
        for ln in lines:
            try:
                json.loads(ln)
            except ValueError:
                bad += 1
        check(f"{name}: lines that are not JSON", bad, 1 if name == "crash.jsonl" else 0)
    fake = os.path.join(HERE, "fake_claude.py")
    with tempfile.TemporaryDirectory() as tmp:
        log = os.path.join(tmp, "log.jsonl")
        env = {"PATH": os.environ.get("PATH", ""), "NM_FAKE_CLAUDE_LOG": log,
               "NM_FAKE_CLAUDE_TRANSCRIPT": os.path.join(tdir, "success.jsonl"), "NM_FAKE_CLAUDE_EXIT": "0",
               "CANARY": "kept"}
        sid = "11111111-1111-4111-8111-111111111111"
        run = subprocess.run([sys.executable, fake, "-p", "--session-id", sid, "--model", "sonnet"],
                             input='{"type":"user"}\n', capture_output=True, text=True, cwd=tmp, env=env, timeout=30)
        check("the fake replays the transcript, one line each", len(run.stdout.splitlines()), 11)
        check("the fake fills in the session id", sid in run.stdout and "__SESSION_ID__" not in run.stdout, True)
        entry = json.loads(open(log, encoding="utf-8").read().splitlines()[0])
        check("the fake records argv, stdin and the environment",
              (entry["argv"][:3], entry["stdin"], entry["env"].get("CANARY")),
              (["-p", "--session-id", sid], '{"type":"user"}\n', "kept"))
        version = subprocess.run([sys.executable, fake, "--version"], capture_output=True, text=True, env=env, timeout=30)
        check("the fake's version", version.stdout.strip(), "2.1.211 (Claude Code)")
        status = subprocess.run([sys.executable, fake, "auth", "status"],
                                capture_output=True, text=True, env=dict(env, NM_FAKE_CLAUDE_AUTH_EXIT="1"), timeout=30)
        check("the fake's auth status exit", status.returncode, 1)
        # It can ask for a permission the way the hook relay does, for checking the approval card by hand.
        sock_path = os.path.join(tmp, "nm.sock")
        seen = []

        def serve():
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as srv:
                srv.bind(sock_path)
                srv.listen(1)
                conn, _ = srv.accept()
                with conn:
                    seen.append(json.loads(conn.makefile("r", encoding="utf-8").readline()))
                    conn.sendall(b'{"permissionDecision":"allow"}\n')

        server = threading.Thread(target=serve, daemon=True)
        server.start()
        while not os.path.exists(sock_path):
            pass
        ask_log = os.path.join(tmp, "ask.jsonl")
        subprocess.run([sys.executable, fake, "-p", "--session-id", sid],
                       input="{}\n", capture_output=True, text=True, cwd=tmp, timeout=30,
                       env=dict(env, NM_FAKE_CLAUDE_LOG=ask_log, NM_FAKE_CLAUDE_ASK_SOCKET=sock_path))
        server.join(10)
        check("the fake asks for a permission with its session id",
              (seen[0]["hook_event_name"], seen[0]["session_id"]) if seen else None, ("PermissionRequest", sid))
        entries = [json.loads(line) for line in open(ask_log, encoding="utf-8").read().splitlines()]
        check("and records the answer", entries[-1], {"permission": '{"permissionDecision":"allow"}'})


CHECKS = [check_args, check_env, check_parse, check_status_and_versions, check_locator, check_hooks, check_labels,
          check_copy, check_fixture_files]


def main():
    for fn in CHECKS:
        fn()
    if FAILURES:
        print(f"\n{FAILURES} failure(s)")
        sys.exit(1)
    print("\nAll Claude Code contract checks passed")


if __name__ == "__main__":
    main()
```

Run: `chmod +x tests/fixtures/ai/claude-code/reference.py`

- [ ] **Step 6: Run it**

Run: `python3 tests/fixtures/ai/claude-code/reference.py`
Expected: PASS, the last line is `All Claude Code contract checks passed` and no line has `✗`.

- [ ] **Step 7: Prove the reference can fail**

A check that cannot fail proves nothing. Break one expectation on purpose (Claude Code 2.1.210 is accepted), see it caught, and put it back.

Run: `sed -i.bak 's/"version": \[2, 1, 210\], "expect": "tooOld"/"version": [2, 1, 210], "expect": "ok"/' tests/fixtures/ai/claude-code/versions.json && python3 tests/fixtures/ai/claude-code/reference.py`
Expected: FAIL, a `✗` line names the version check.

Run: `mv tests/fixtures/ai/claude-code/versions.json.bak tests/fixtures/ai/claude-code/versions.json && python3 tests/fixtures/ai/claude-code/reference.py | tail -1`
Expected: PASS, `All Claude Code contract checks passed`.

- [ ] **Step 8: Run it with the rest of the AI contract**

**Edit `scripts/test-ai-contract.sh`**, find this text (it occurs exactly once):

```bash
cd "$(dirname "$0")/.."
python3 tests/fixtures/ai/reference.py
python3 tests/test_fake_server.py
```

and replace it with:

```bash
cd "$(dirname "$0")/.."
python3 tests/fixtures/ai/reference.py
python3 tests/fixtures/ai/claude-code/reference.py
python3 tests/test_fake_server.py
```

Run: `bash scripts/test-ai-contract.sh`
Expected: PASS, three scripts run in turn and none fails.

- [ ] **Step 9: Commit**

```bash
git add scripts/test-ai-contract.sh tests/fixtures/ai/claude-code
git commit -q -m "test(ai): the Claude Code contract, a fake claude, its transcripts and an independent reference" -m "Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```


### Task 3: Mac: the provider ID, the catalog and the router

**Agent:** `nm-implementer`. Seven small edits across one subsystem; the compiler finds every `switch` that must learn the new case, so the build at the end is part of the task.

**Files:**
- Modify: `NotchBuddy/Sources/App/AI/Core/AICatalog.swift`, `ModelRouter.swift`, `ProviderFactory.swift`, `Attachments.swift`
- Modify: `NotchBuddy/Sources/App/IslandTypes.swift` (`ChatProvider`, the chat's own mirror of the provider IDs)
- Test: `tests/AIRouterTests.swift`, `tests/AIAttachmentTests.swift`

**Interfaces:**
- Consumes: Task 1's fixtures (`providers.json` lists `claudeCode`; `router-cases.json` uses it).
- Produces, for Tasks 4 to 11:
  - `AIProviderID.claudeCode` (raw value `"claudeCode"`, frozen), with `isCloud == true`;
  - `AIProviderAPI.claudeCode` (raw value `"claude-code"`);
  - `enum ClaudeCodeModel: String, CaseIterable, Sendable, Codable { case sonnet, opus, haiku; var label: String }`, in `AICatalog.swift` so the model pickers compile in the App Store build too (the engine behind it does not);
  - `AICatalog.info(.claudeCode)`: name "Claude plan", placement `cloud`, default model `sonnet`, no key;
  - `ModelRouter.cloudChoice`: preferred first, then the others of `claudeCode`, `anthropic`, `openai`, then `google`, the first that is in `keys`. `keys` holds `claudeCode` only when it is ready; `AIService.cloudKeys` decides that in Task 10;
  - `ProviderFactory.make` returns `UnavailableProvider(id: .claudeCode)` until Task 10 gives it a setup;
  - `ChatProvider.claudeCode` (name "Claude plan", accent `#E07950`, default model `sonnet`) and PDFs and images for it sized like Anthropic's.

- [ ] **Step 1: Write the failing tests**

The router test replays Task 1's fixtures, and both tests learn the new case.

**Edit `tests/AIRouterTests.swift`**, find this text (it occurs exactly once):

```swift
        }
        T.check("cloud order", AICatalog.cloudOrder.map(\.rawValue), json["cloudOrder"] as! [String])
        let web = json["webSearch"] as? [String: [String: Any]] ?? [:]
        let claude = web["anthropic"] ?? [:]
```

and replace it with:

```swift
        }
        T.check("cloud order", AICatalog.cloudOrder.map(\.rawValue), json["cloudOrder"] as! [String])
        T.check("Claude Code counts as cloud, and its default model is an alias", [AIProviderID.claudeCode.isCloud, AICatalog.info(.claudeCode).defaultModel == ClaudeCodeModel.sonnet.rawValue], [true, true])
        T.check("Claude Code's model aliases", ClaudeCodeModel.allCases.map(\.rawValue), ["sonnet", "opus", "haiku"])
        let web = json["webSearch"] as? [String: [String: Any]] ?? [:]
        let claude = web["anthropic"] ?? [:]
```

**Edit `tests/AIAttachmentTests.swift`**, find this text (it occurs exactly once):

```swift
        T.check("text PDF → Anthropic native", p(pdf, .anthropic, vision: true, .cloud), ["pdf"])
        T.check("text PDF → OpenAI native", p(pdf, .openaiResponses, vision: true, .cloud), ["pdf"])
        T.check("text PDF → Google text", p(pdf, .openaiChat, vision: true, .cloud), ["fileText"])
        T.check("text PDF → local text", p(pdf, .openaiChat, vision: false), ["fileText"])
        T.check("scanned PDF → vision local gets pages", p(scan, .openaiChat, vision: true), ["text", "image image/png"])
        T.check("scanned PDF → text-only local gets OCR", p(scan, .openaiChat, vision: false), ["fileText"])
        T.check("scanned PDF → Anthropic native", p(scan, .anthropic, vision: true, .cloud), ["pdf"])
        T.check("image → vision model", p(png, .openaiChat, vision: true), ["text", "image image/png"])
        T.check("image → Apple gets OCR text", p(png, .apple, vision: false), ["fileText"])
```

and replace it with:

```swift
        T.check("text PDF → Anthropic native", p(pdf, .anthropic, vision: true, .cloud), ["pdf"])
        T.check("text PDF → OpenAI native", p(pdf, .openaiResponses, vision: true, .cloud), ["pdf"])
        T.check("text PDF → Claude Code native", p(pdf, .claudeCode, vision: true, .cloud), ["pdf"])
        T.check("text PDF → Google text", p(pdf, .openaiChat, vision: true, .cloud), ["fileText"])
        T.check("text PDF → local text", p(pdf, .openaiChat, vision: false), ["fileText"])
        T.check("scanned PDF → vision local gets pages", p(scan, .openaiChat, vision: true), ["text", "image image/png"])
        T.check("scanned PDF → text-only local gets OCR", p(scan, .openaiChat, vision: false), ["fileText"])
        T.check("scanned PDF → Anthropic native", p(scan, .anthropic, vision: true, .cloud), ["pdf"])
        T.check("image → Claude Code gets the image", p(png, .claudeCode, vision: true, .cloud), ["text", "image image/png"])
        T.check("image → vision model", p(png, .openaiChat, vision: true), ["text", "image image/png"])
        T.check("image → Apple gets OCR text", p(png, .apple, vision: false), ["fileText"])
```

- [ ] **Step 2: Run the router test to see it fail**

Run: `bash scripts/test-ai-router.sh`
Expected: FAIL, the build stops with a compile error: the type has no member `claudeCode`.

```text
tests/AIRouterTests.swift:38:161: error: cannot find 'ClaudeCodeModel' in scope
tests/AIRouterTests.swift:38:97: error: type 'AIProviderID' has no member 'claudeCode'
tests/AIRouterTests.swift:38:133: error: type 'AIProviderID' has no member 'claudeCode'
```

- [ ] **Step 3: Teach the catalog, the router, the factory and the chat's provider list**

**Edit `NotchBuddy/Sources/App/AI/Core/AICatalog.swift`**, find this text (it occurs exactly once):

```swift
/// UserDefaults and match `tests/fixtures/ai/providers.json`.
enum AIProviderID: String, CaseIterable, Codable, Sendable {
    case anthropic, openai, google, ollama, lmstudio, llamacpp, jan, apple, custom

    var isCloud: Bool { self == .anthropic || self == .openai || self == .google }
}

```

and replace it with:

```swift
/// UserDefaults and match `tests/fixtures/ai/providers.json`.
enum AIProviderID: String, CaseIterable, Codable, Sendable {
    case anthropic, openai, google, ollama, lmstudio, llamacpp, jan, apple, custom, claudeCode

    /// `claudeCode` runs on Anthropic's servers through the user's own Claude Code, so it counts as cloud.
    var isCloud: Bool { self == .anthropic || self == .openai || self == .google || self == .claudeCode }
}

/// Claude Code's own model aliases (its `--model` values): plain names, like a catalog row. The engine that uses them
/// is compiled out of the App Store build; the model picker and Settings read the list in both.
enum ClaudeCodeModel: String, CaseIterable, Sendable, Codable {
    case sonnet, opus, haiku

    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

```

**Edit `NotchBuddy/Sources/App/AI/Core/AICatalog.swift`**, find this text (it occurs exactly once):

```swift
    case openaiChat = "openai-chat"
    case apple
}

```

and replace it with:

```swift
    case openaiChat = "openai-chat"
    case apple
    case claudeCode = "claude-code"
}

```

**Edit `NotchBuddy/Sources/App/AI/Core/AICatalog.swift`**, find this text (it occurs exactly once):

```swift
        .init(id: .custom, name: "Local server", placement: "computed", api: .openaiChat,
              chatPath: "/v1/chat/completions", modelsPath: "/v1/models", keychainKey: "custom-server-key"),
    ]

```

and replace it with:

```swift
        .init(id: .custom, name: "Local server", placement: "computed", api: .openaiChat,
              chatPath: "/v1/chat/completions", modelsPath: "/v1/models", keychainKey: "custom-server-key"),
        .init(id: .claudeCode, name: "Claude plan", placement: "cloud", api: .claudeCode, defaultModel: "sonnet"),
    ]

```

**Edit `NotchBuddy/Sources/App/AI/Core/AICatalog.swift`**, find this text (it occurs exactly once):

```swift
                    && !Filters.openAIExclude.contains { l.contains($0) }
            }
        case .anthropic, .apple:
            return ids
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
```

and replace it with:

```swift
                    && !Filters.openAIExclude.contains { l.contains($0) }
            }
        case .anthropic, .apple, .claudeCode:
            return ids
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
```

**Edit `NotchBuddy/Sources/App/AI/Core/ModelRouter.swift`**, find this text (it occurs exactly once):

```swift
    static func shouldAutoRetry(retries: Int) -> Bool { retries < maxAutoRetries }

    /// Preferred cloud, then the other of Claude/OpenAI, then Google; the first with a key.
    static func cloudChoice(_ input: RouteInput) -> AIProviderID? {
        let other: [AIProviderID] = [.anthropic, .openai].filter { $0 != input.preferredCloud }
        return ([input.preferredCloud] + other + [.google]).first { input.keys.contains($0) }
    }
```

and replace it with:

```swift
    static func shouldAutoRetry(retries: Int) -> Bool { retries < maxAutoRetries }

    /// Preferred cloud, then the others of Claude plan / Claude API / OpenAI, then Google; the first that is ready.
    /// `keys` holds the cloud providers with a key, plus `claudeCode` when the user connected it and the last
    /// check found Claude Code signed in.
    static func cloudChoice(_ input: RouteInput) -> AIProviderID? {
        let other: [AIProviderID] = [.claudeCode, .anthropic, .openai].filter { $0 != input.preferredCloud }
        return ([input.preferredCloud] + other + [.google]).first { input.keys.contains($0) }
    }
```

**Edit `NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift`**, find this text (it occurs exactly once):

```swift
        case .apple:
            return apple ?? UnavailableProvider(id: .apple)
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
            let server = servers[t.serverID ?? t.provider.rawValue]
```

and replace it with:

```swift
        case .apple:
            return apple ?? UnavailableProvider(id: .apple)
        case .claudeCode:
            return UnavailableProvider(id: .claudeCode)
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
            let server = servers[t.serverID ?? t.provider.rawValue]
```

**Edit `NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift`**, find this text (it occurs exactly once):

```swift
    func details(_ t: ChatTarget) async -> (vision: Bool, contextTokens: Int?) {
        switch t.provider {
        case .anthropic, .openai, .google: return (true, nil)
        case .apple: return (false, appleContextTokens)
        default:
```

and replace it with:

```swift
    func details(_ t: ChatTarget) async -> (vision: Bool, contextTokens: Int?) {
        switch t.provider {
        case .anthropic, .openai, .google, .claudeCode: return (true, nil)
        case .apple: return (false, appleContextTokens)
        default:
```

**Edit `NotchBuddy/Sources/App/AI/Core/Attachments.swift`**, find this text (it occurs exactly once):

```swift

    /// The parts for one file and one model, plus the truncation notice shown to the user.
    /// Anthropic and OpenAI read PDFs natively (both see page images); other vision models get
    /// images; everything else gets text cut to the model's budget.
    static func parts(for file: PreparedFile, api: AIProviderAPI, vision: Bool,
                      placement: AIPlacement, contextTokens: Int?) -> (parts: [ChatRequest.Part], notice: String?) {
        let nativePDF = vision && (api == .anthropic || api == .openaiResponses)
        func text(_ t: String?) -> ([ChatRequest.Part], String?) {
            let cut = ContextBudget.cut(t ?? "", placement: placement, contextTokens: contextTokens)
```

and replace it with:

```swift

    /// The parts for one file and one model, plus the truncation notice shown to the user.
    /// Anthropic, OpenAI and Claude Code read PDFs natively (all see page images); other vision models get
    /// images; everything else gets text cut to the model's budget.
    static func parts(for file: PreparedFile, api: AIProviderAPI, vision: Bool,
                      placement: AIPlacement, contextTokens: Int?) -> (parts: [ChatRequest.Part], notice: String?) {
        let nativePDF = vision && (api == .anthropic || api == .openaiResponses || api == .claudeCode)
        func text(_ t: String?) -> ([ChatRequest.Part], String?) {
            let cut = ContextBudget.cut(t ?? "", placement: placement, contextTokens: contextTokens)
```

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`**, find this text (it occurs exactly once):

```swift
    case apple     = "apple"
    case custom    = "custom"

    init(_ id: AIProviderID) { self.init(rawValue: id.rawValue)! }
```

and replace it with:

```swift
    case apple     = "apple"
    case custom    = "custom"
    case claudeCode = "claudeCode"

    init(_ id: AIProviderID) { self.init(rawValue: id.rawValue)! }
```

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`**, find this text (it occurs exactly once):

```swift
        case .apple:     "Apple on-device"
        case .custom:    "Local server"
        }
    }
```

and replace it with:

```swift
        case .apple:     "Apple on-device"
        case .custom:    "Local server"
        case .claudeCode: "Claude plan"
        }
    }
```

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`**, find this text (it occurs exactly once):

```swift
        case .apple:     "#C8CDD4"
        case .custom:    "#94A3B8"
        }
    }
```

and replace it with:

```swift
        case .apple:     "#C8CDD4"
        case .custom:    "#94A3B8"
        case .claudeCode: "#E07950"
        }
    }
```

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`**, find this text (it occurs exactly once):

```swift
        case .lmstudio:  "local-model"
        case .apple:     "system"
        case .llamacpp, .jan, .custom: ""
        }
```

and replace it with:

```swift
        case .lmstudio:  "local-model"
        case .apple:     "system"
        case .claudeCode: "sonnet"
        case .llamacpp, .jan, .custom: ""
        }
```

- [ ] **Step 4: Run every AI test program**

Run: `for s in scripts/test-ai-*.sh; do bash "$s" > /dev/null 2>&1 && echo "ok $s" || { echo "FAILED $s"; exit 1; }; done`
Expected: PASS, one `ok` line per script, `scripts/test-ai-contract.sh` and `scripts/test-ai-router.sh` among them, and no `FAILED`.

- [ ] **Step 5: The app still builds**

`ChatProvider` and the catalog are switched over in many files, so build the app: the compiler lists any `switch` that must learn the new case.

Run: `(cd NotchBuddy && xcodegen --quiet && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

`xcodegen` leaves `NotchBuddy.xcodeproj/project.pbxproj` unchanged here (no file was added); `git status --short` shows only the seven files above.

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/AICatalog.swift NotchBuddy/Sources/App/AI/Core/ModelRouter.swift NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift NotchBuddy/Sources/App/AI/Core/Attachments.swift NotchBuddy/Sources/App/IslandTypes.swift tests/AIRouterTests.swift tests/AIAttachmentTests.swift
git commit -q -m "feat(ai): the Claude plan is a cloud provider in the Mac catalog and router" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 4: Mac: the command line, the environment and the message on stdin

**Agent:** `nm-implementer`.

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/ClaudeCodeEngine.swift`
- Create: `scripts/test-claude-code.sh`, `tests/ClaudeCodeEngineTests.swift`
- Modify: `NotchBuddy/Sources/App/AI/Core/AnthropicProvider.swift` (`block` becomes internal, so the engine writes the same image and PDF blocks)
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (generated by `xcodegen`)

**Interfaces:**
- Consumes: Task 2's `expected-args.json` and `expected-env.json`; `ClaudeCodeModel` (Task 3); `ChatRequest.Part` and `AnthropicProvider.block` (existing).
- Produces, all compiled out of the App Store build (`#if !APPSTORE`):

  ```swift
  enum ClaudeCodeEngine { static let note = "runs your installed Claude Code" }
  enum ClaudeCodePlatform: String, Sendable { case mac, linux, windows; static let current = ClaudeCodePlatform.mac }
  enum ClaudeCodeLevel: Sendable, Equatable { case chatOnly, readOnly(folder: String), agent(folder: String); var folder: String?; var key: String }
  struct ClaudeCodeTurn: Sendable, Equatable { var level: ClaudeCodeLevel; var model: ClaudeCodeModel = .sonnet; var sessionID: String; var resume: Bool; var platform: ClaudeCodePlatform = .current }
  enum ClaudeCodeCommand {
      static let base: [String]                                   // "-p" … "--include-partial-messages"
      static func arguments(_ turn: ClaudeCodeTurn) -> [String]   // base, the session flag, the model, the level's flags
      static func workingDirectory(_ turn: ClaudeCodeTurn, chatFolder: String) -> String
      static func environment(from base: [String: String], platform: ClaudeCodePlatform) -> [String: String]
      static func userLine(parts: [ChatRequest.Part], preamble: String? = nil) -> Data   // one JSON line + "\n"
  }
  ```

  The note string "runs your installed Claude Code" and the variable `CLAUDE_CODE_OAUTH_TOKEN` are also what `check-app-binary.sh` (Task 12) looks for: only the engine has them.

- [ ] **Step 1: Write the failing test and the script that runs every Claude Code test program**

The script compiles each `tests/ClaudeCode*Tests.swift` together with the AI core (Foundation only), the log and the shared test helpers, with `-D DEBUG` as a Debug build is; later tasks add their test programs to the same script by filename.

**Create `scripts/test-claude-code.sh`** with exactly this content:

```bash
#!/usr/bin/env bash
# The Claude Code engine against the shared fixtures in tests/fixtures/ai/claude-code/ and the fake `claude` there:
# the command line, the environment, the transcript parser, the runner, the locator and the chat's session.
# Never runs a real claude. One test program per tests/ClaudeCode*Tests.swift, built with -D DEBUG as a Debug build is
# (the Debug-only path override is tested; Release and App Store builds compile it out, which check-app-binary.sh proves).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-claude-code.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
for test in tests/ClaudeCode*Tests.swift; do
    name="$(basename "$test" .swift)"
    swiftc -swift-version 6 -D DEBUG \
        NotchBuddy/Sources/App/AI/Core/*.swift \
        NotchBuddy/Sources/App/AppLog.swift \
        tests/AITestSupport.swift "$test" \
        -o "$TEST_DIR/$name"
    echo "== $name"
    "$TEST_DIR/$name"
done
```

Run: `chmod +x scripts/test-claude-code.sh`

The test replays the two fixture files, then pins the message on stdin: one JSON line, a dropped PDF as a block, the recap in front, non-ASCII text intact. It pins Review Focus 6: the `expected-args.json` case with a folder like `/Users/Zoé/Mes projets/ünï côde` has that folder as the working folder and nowhere in the argument list.

**Create `tests/ClaudeCodeEngineTests.swift`** with exactly this content:

```swift
import Foundation

@main
@MainActor
enum ClaudeCodeEngineTests {
    static func main() {
        arguments()
        environment()
        stdinLine()
        T.finish()
    }

    static func level(_ key: String, _ folder: String?) -> ClaudeCodeLevel {
        switch key {
        case "read": .readOnly(folder: folder ?? "")
        case "agent": .agent(folder: folder ?? "")
        default: .chatOnly
        }
    }

    // MARK: - expected-args.json

    static func arguments() {
        T.section("The command line of one turn")
        let data = T.fixture("claude-code/expected-args.json")
        let chatFolder = data["chatFolder"] as! String
        T.check("model aliases", ClaudeCodeModel.allCases.map(\.rawValue), data["models"] as! [String])
        for c in data["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let turn = ClaudeCodeTurn(level: level(c["level"] as! String, c["folder"] as? String),
                                      model: ClaudeCodeModel(rawValue: c["model"] as! String)!,
                                      sessionID: c["sessionId"] as! String, resume: c["resume"] as! Bool,
                                      platform: ClaudeCodePlatform(rawValue: c["platform"] as! String)!)
            let argv = ClaudeCodeCommand.arguments(turn)
            T.check(name, argv, c["argv"] as! [String])
            let cwd = ClaudeCodeCommand.workingDirectory(turn, chatFolder: chatFolder)
            T.check("\(name): runs in", cwd, c["cwd"] as! String == "chatFolder" ? chatFolder : c["folder"] as! String)
            if let folder = c["folder"] as? String {
                T.checkTrue("\(name): the folder is not an argument", !argv.contains { $0.contains(folder) })
            }
            T.checkTrue("\(name): --bare is never used", !argv.contains("--bare"))
        }
    }

    // MARK: - expected-env.json

    static func environment() {
        T.section("The environment of a run")
        let data = T.fixture("claude-code/expected-env.json")
        T.check("stripped names", ClaudeCodeCommand.strippedVariables, Set(data["stripped"] as! [String]))
        T.check("stripped prefixes", ClaudeCodeCommand.strippedPrefixes, data["strippedPrefixes"] as! [String])
        for c in data["cases"] as! [[String: Any]] {
            let platform = ClaudeCodePlatform(rawValue: c["platform"] as! String)!
            T.check(c["name"] as! String,
                    ClaudeCodeCommand.environment(from: c["base"] as! [String: String], platform: platform),
                    c["expect"] as! [String: String])
        }
    }

    // MARK: - stdin

    static func stdinLine() {
        T.section("The message on stdin")
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let line = ClaudeCodeCommand.userLine(parts: [.fileText(name: "notes.txt", text: "hello"),
                                                      .image(mime: "image/png", data: png),
                                                      .pdf(name: "a.pdf", data: Data([0x25, 0x50])),
                                                      .text("What is in these? Zoé 🐱")])
        T.check("one line that ends with a newline", line.last, 0x0A)
        T.check("and has no other newline", line.dropLast().contains(0x0A), false)
        let json = try! JSONSerialization.jsonObject(with: line) as! [String: Any]
        T.check("a user message", json["type"] as? String, "user")
        T.checkTrue("parent_tool_use_id is null", json["parent_tool_use_id"] is NSNull)
        let message = json["message"] as! [String: Any]
        T.check("role", message["role"] as? String, "user")
        let blocks = message["content"] as! [[String: Any]]
        T.check("block types", blocks.map { $0["type"] as! String }, ["text", "image", "document", "text"])
        T.check("a file's text is introduced by its name", blocks[0]["text"] as? String, "File: notes.txt\n\nhello")
        T.check("the question keeps its Unicode", blocks[3]["text"] as? String, "What is in these? Zoé 🐱")
        let withRecap = ClaudeCodeCommand.userLine(parts: [.text("and now?")], preamble: "Earlier in this chat: …")
        let recapBlocks = ((try! JSONSerialization.jsonObject(with: withRecap) as! [String: Any])["message"] as! [String: Any])["content"] as! [[String: Any]]
        T.check("a recap comes first", recapBlocks.map { $0["text"] as! String }, ["Earlier in this chat: …", "and now?"])
        T.check("the note next to the engine's name says what it does, in plain text", ClaudeCodeEngine.note, "runs your installed Claude Code")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-claude-code.sh`
Expected: FAIL, compile errors in `tests/ClaudeCodeEngineTests.swift`: the engine's types do not exist, starting with `cannot find type 'ClaudeCodeLevel' in scope`.

```text
tests/ClaudeCodeEngineTests.swift:13:60: error: cannot find type 'ClaudeCodeLevel' in scope
tests/ClaudeCodeEngineTests.swift:30:24: error: cannot find 'ClaudeCodeTurn' in scope
tests/ClaudeCodeEngineTests.swift:33:49: error: cannot find 'ClaudeCodePlatform' in scope
```

- [ ] **Step 3: Write the engine**

`AnthropicProvider.block` turns one request part into a content block (text, image, PDF). It is private today; the engine needs the same blocks, so it becomes internal.

**Edit `NotchBuddy/Sources/App/AI/Core/AnthropicProvider.swift`**, find this text (it occurs exactly once):

```swift
    }

    private static func block(_ part: ChatRequest.Part) -> [String: Any] {
        switch part {
        case .text(let t):
```

and replace it with:

```swift
    }

    /// One content block of the Messages API shape; Claude Code takes the same blocks on stdin.
    static func block(_ part: ChatRequest.Part) -> [String: Any] {
        switch part {
        case .text(let t):
```

**Create `NotchBuddy/Sources/App/AI/Core/ClaudeCodeEngine.swift`** with exactly this content:

```swift
import Foundation

// Claude Code as an engine, the pure parts: the levels, the command line of one turn, the environment it runs
// in and the message written to its stdin. Nothing here starts a process (`ClaudeCodeProvider.swift` does).
// `tests/fixtures/ai/claude-code/` is what both apps must agree on; its `reference.py` is the tie-breaker.
// The App Store build compiles all of this out (`scripts/check-app-binary.sh` looks for strings only the engine has).

#if !APPSTORE

enum ClaudeCodeEngine {
    /// The plain-text note next to the engine's name in the UI. Never "Claude Code" as a label.
    static let note = "runs your installed Claude Code"
}

enum ClaudeCodePlatform: String, Sendable {
    case mac, linux, windows

    /// The Mac app is always `mac`; the other two exist for the shared fixtures.
    static let current = ClaudeCodePlatform.mac
}

/// What Claude may do in a chat. Read-only and Agent carry the folder the user chose.
enum ClaudeCodeLevel: Sendable, Equatable {
    case chatOnly
    case readOnly(folder: String)
    case agent(folder: String)

    var folder: String? {
        switch self {
        case .chatOnly: nil
        case .readOnly(let folder), .agent(let folder): folder
        }
    }

    /// `chat`, `read` or `agent`, as in the fixtures.
    var key: String {
        switch self {
        case .chatOnly: "chat"
        case .readOnly: "read"
        case .agent: "agent"
        }
    }
}

/// One run of Claude Code: everything except the message itself.
struct ClaudeCodeTurn: Sendable, Equatable {
    var level: ClaudeCodeLevel
    var model: ClaudeCodeModel = .sonnet
    /// The id NotchMeow chose for this chat's Claude Code session (lower-case UUID).
    var sessionID: String
    /// False on a chat's first turn (`--session-id`), true on the later ones (`--resume`).
    var resume: Bool
    var platform: ClaudeCodePlatform = .current
}

enum ClaudeCodeCommand {
    static let base = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--include-partial-messages"]
    private static let chatTools = "WebSearch,WebFetch"
    private static let readTools = "Read,Grep,Glob,WebSearch,WebFetch"
    private static let readSettings = #"{"permissions":{"blockReadsOutsideWorkingDirectories":true}}"#
    private static let sandboxSettings = #"{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":false}}"#

    /// The arguments after the program name. Every quoted value of the spec is one element: there is no shell.
    /// The folder is the process's working folder, never an argument.
    static func arguments(_ turn: ClaudeCodeTurn) -> [String] {
        var args = base + [turn.resume ? "--resume" : "--session-id", turn.sessionID, "--model", turn.model.rawValue]
        switch turn.level {
        case .chatOnly:
            args += ["--safe-mode", "--tools", chatTools, "--allowedTools", chatTools,
                     "--disallowedTools", "mcp__*", "--permission-mode", "dontAsk"]
        case .readOnly:
            args += ["--safe-mode", "--tools", readTools, "--allowedTools", readTools,
                     "--permission-mode", "dontAsk", "--settings", readSettings]
        case .agent:
            args += ["--permission-mode", "default"]
            // Native Windows has no command sandbox: there every command asks.
            if turn.platform != .windows { args += ["--settings", sandboxSettings] }
        }
        return args
    }

    /// The folder the process runs in: the user's for Read-only and Agent, NotchMeow's own empty one for Chat only.
    static func workingDirectory(_ turn: ClaudeCodeTurn, chatFolder: String) -> String {
        turn.level.folder ?? chatFolder
    }

    // MARK: Environment

    /// Variables that outrank the user's plan login in Claude Code's own order of precedence.
    static let strippedVariables: Set<String> = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
                                                 "ANTHROPIC_PROFILE"]
    static let strippedPrefixes = ["CLAUDE_CODE_USE_"]

    /// The environment of a run: the caller's, without what would outrank the plan login. On Windows names
    /// compare without regard to case. An `apiKeyHelper` is a setting, not a variable: it is not touched.
    static func environment(from base: [String: String], platform: ClaudeCodePlatform) -> [String: String] {
        let insensitive = platform == .windows
        return base.filter { name, _ in
            let key = insensitive ? name.uppercased() : name
            return !strippedVariables.contains(key) && !strippedPrefixes.contains { key.hasPrefix($0) }
        }
    }

    // MARK: stdin

    /// The one line written to stdin: the new message as content blocks (a dropped image or PDF as a block, other
    /// files as text), in the documented user-message shape. `preamble` is a recap of the chat so far, only for a
    /// session that is started afresh in the middle of a chat (`ClaudeChatSession` decides when).
    static func userLine(parts: [ChatRequest.Part], preamble: String? = nil) -> Data {
        var content: [[String: Any]] = []
        if let preamble, !preamble.isEmpty { content.append(["type": "text", "text": preamble]) }
        content += parts.map(AnthropicProvider.block)
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": content],
                                      "parent_tool_use_id": NSNull()]
        var data = (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
        data.append(0x0A)
        return data
    }
}

#endif
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-claude-code.sh`
Expected: PASS, `== ClaudeCodeEngineTests`, every line `✓`, no `✗`.

```text
== ClaudeCodeEngineTests
All tests passed.
```

- [ ] **Step 5: Register the new Swift file and commit**

Run: `(cd NotchBuddy && xcodegen --quiet) && git status --short`
Expected: PASS, the status lists `project.pbxproj` as modified: it now names the new Swift file.

```bash
git add NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj NotchBuddy/Sources/App/AI/Core/ClaudeCodeEngine.swift NotchBuddy/Sources/App/AI/Core/AnthropicProvider.swift scripts/test-claude-code.sh tests/ClaudeCodeEngineTests.swift
git commit -q -m "feat(claude-code): the command line, the environment and the message of one turn" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 5: Mac: the transcript parser, steps and the runner's new events

**Agent:** `nm-implementer`.

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/ClaudeStreamParser.swift`
- Create: `tests/ClaudeCodeParserTests.swift`
- Modify: `NotchBuddy/Sources/App/AI/Core/ModelProvider.swift`, `ReplyAccumulator.swift`, `ChatRunner.swift`
- Modify: `NotchBuddy/Sources/App/ClaudeService.swift` (only so its `switch` over run events stays exhaustive until Task 10 wires them)
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (generated)

**Interfaces:**
- Consumes: `ClaudeCodeModel` (Task 3), the fixtures `expected-parse.json` and `transcripts/` (Task 2), `ChatChunk`, `AIError`, `ReplyAccumulator`, `ChatRunner` (existing).
- Produces:

  ```swift
  struct ChatStep: Sendable, Equatable, Hashable {                  // ModelProvider.swift
      enum State: String, Sendable { case running, done, failed, stopped }
      let id: String; var tool: String; var input: [String: String] = [:]; var state: State = .running
      static func endingUnfinished(_ steps: [ChatStep]) -> [ChatStep]   // running -> stopped, others untouched
  }
  struct EngineReport: Sendable, Equatable { enum Payer: String, Sendable { case plan, apiKey = "api_key", unknown }
      var sessionID: String; var model: String; var paidBy: Payer; var version: String? }
  enum ChatChunk { …; case step(ChatStep); case engine(EngineReport) }   // two new cases
  struct AIError { …; var resetsAt: Date? = nil }                          // when a usage limit resets
  enum RunEvent { …; case step(ChatStep); case engine(EngineReport) }     // ChatRunner.swift
  struct RunResult { …; var tookSteps = false }                            // steps taken: Auto never hands the question to another model
  enum ClaudeCodeError { static let missing, signedOut, planLimit, tooOld, crashed, offline, needsGit, folderMissing }   // the AIError.code values, "nm_…"
  struct ClaudeStreamParser {
      static let stepFields = ["command", "file_path", "path", "query", "pattern", "url"]; static let stepFieldCap = 200
      private(set) var engine: EngineReport?; private(set) var text: String
      mutating func consume(line: String) -> [ChatChunk]   // one line of stdout; junk and unknown events give []
      func failure(stderr: String) -> AIError?             // call once, after the process exited; nil when the run ended well
  }
  ```

  The parser is the contract's `parse()` in `reference.py`: text deltas are the reply (text of separate assistant messages around a tool call is joined by a blank line); a `tool_use` becomes a step row that keeps only the six fields above, each cut to 200 Unicode scalars, so a Write's `content` never leaves the parser; `tool_result` ends the step as done or failed; `system/init` says who pays (`apiKeySource` none or oauth is the plan; user, project, org or temporary is an API key; anything else says nothing). Failures: exit status is never read, because Claude Code does not document it; the result, the assistant's `error`, the rate-limit event and stderr decide, and anything unrecognised is `nm_claude_crashed` ("Claude stopped unexpectedly"), never a guess.

- [ ] **Step 1: Write the failing test**

It replays every case of `expected-parse.json` (a transcript, an exit status and a stderr text in; the engine report, the text, the steps, the finish reason and the error out), then pins what no fixture covers: junk lines, an unreadable reset time, a warning that is not a failure, the 200-scalar cut, the fields a step keeps, and `ChatStep.endingUnfinished`. It pins Review Focus 5 (`api-key-helper.jsonl` and `unknown-source.jsonl`: who pays is what `system/init` reports, and an unknown source says nothing), Review Focus 10 (`tool-use.jsonl`: separate assistant messages read as paragraphs) and the "never stays running" half of Review Focus 2.

**Create `tests/ClaudeCodeParserTests.swift`** with exactly this content:

```swift
import Foundation

@main
@MainActor
enum ClaudeCodeParserTests {
    /// A whole run folded the way the chat sees it.
    struct Folded {
        var engine: EngineReport?
        var text = ""
        var steps: [ChatStep] = []
        var finish: FinishReason?
        var error: AIError?
    }

    static func fold(lines: [String], stderr: String) -> Folded {
        var parser = ClaudeStreamParser()
        var out = Folded()
        for line in lines {
            for chunk in parser.consume(line: line) {
                switch chunk {
                case .engine(let r): out.engine = r
                case .text(let t): out.text += t
                case .finish(let f): out.finish = f
                case .step(let s):
                    if let i = out.steps.firstIndex(where: { $0.id == s.id }) { out.steps[i] = s } else { out.steps.append(s) }
                default: break
                }
            }
        }
        out.error = parser.failure(stderr: stderr)
        return out
    }

    static func main() {
        transcripts()
        edges()
        T.finish()
    }

    // MARK: - expected-parse.json

    static func transcripts() {
        T.section("What a transcript means (expected-parse.json)")
        let data = T.fixture("claude-code/expected-parse.json")
        let sid = data["sessionId"] as! String
        for c in data["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let path = T.fixtureURL("claude-code/transcripts/\(c["transcript"] as! String)")
            let raw = try! String(contentsOf: path, encoding: .utf8)
                .replacingOccurrences(of: "__SESSION_ID__", with: sid)
                .replacingOccurrences(of: "__CWD__", with: data["cwd"] as! String)
            let got = fold(lines: raw.components(separatedBy: "\n").filter { !$0.isEmpty }, stderr: c["stderr"] as! String)
            let expect = c["expect"] as! [String: Any]

            if let e = expect["engine"] as? [String: Any] {
                T.check("\(name): engine", got.engine.map { [$0.sessionID, $0.model, $0.paidBy.rawValue, $0.version ?? ""] },
                        [sid, e["model"] as! String, e["paidBy"] as! String, e["version"] as! String])
            } else {
                T.check("\(name): no engine report", got.engine == nil, true)
            }
            T.check("\(name): text", got.text, expect["text"] as! String)
            let steps = (expect["steps"] as! [[String: Any]]).map { s in
                ChatStep(id: s["id"] as! String, tool: s["tool"] as! String, input: s["input"] as! [String: String],
                         state: ChatStep.State(rawValue: s["state"] as! String)!)
            }
            T.check("\(name): steps", got.steps, steps)
            T.check("\(name): finish", got.finish?.rawValue, expect["finish"] as? String)
            if let e = expect["error"] as? [String: Any] {
                T.check("\(name): error kind", got.error?.kind.rawValue, e["kind"] as? String)
                T.check("\(name): error code", got.error?.code, e["code"] as? String)
                T.check("\(name): resets at", got.error?.resetsAt.map { Int64($0.timeIntervalSince1970) }, (e["resetsAt"] as? NSNumber)?.int64Value)
            } else {
                T.check("\(name): no error", got.error == nil, true)
            }
        }
    }

    // MARK: - Shapes no fixture covers

    static func edges() {
        T.section("Tolerance")
        let junk = fold(lines: ["", "not json", "[1,2]", #"{"type":"mystery"}"#, #"{"type":"stream_event"}"#,
                                #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}}"#],
                        stderr: "")
        T.check("junk lines are skipped and the text survives", junk.text, "hi")
        T.check("a run with no result is a crash", junk.error?.code, ClaudeCodeError.crashed)

        let numberTime = fold(lines: [#"{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":"soon"}}"#,
                                      #"{"type":"result","subtype":"success","is_error":true,"result":"limit"}"#], stderr: "")
        T.check("a rejection with a time we cannot read is still the plan's limit", numberTime.error?.code, ClaudeCodeError.planLimit)
        T.check("and carries no time", numberTime.error?.resetsAt == nil, true)

        let allowed = fold(lines: [#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","resetsAt":1791301500}}"#,
                                   #"{"type":"result","subtype":"success","is_error":false,"result":"ok"}"#], stderr: "")
        T.check("a warning is not a failure", allowed.error == nil, true)

        let longInput = String(repeating: "é", count: 300)
        let capped = fold(lines: [
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"Bash","input":{}}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"\#(longInput)","timeout":5000,"content":"secret"}}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":""}"#], stderr: "")
        T.check("a step's input is cut to 200 scalars", capped.steps.first?.input["command"]?.unicodeScalars.count, 200)
        T.check("and keeps only the fields that name the work", capped.steps.first?.input.keys.sorted(), ["command"])
        T.check("a tool use the result never answered stays running", capped.steps.first?.state, .running)
        let mixed = [ChatStep(id: "a", tool: "Read", state: .done), ChatStep(id: "b", tool: "Bash", state: .running), ChatStep(id: "c", tool: "Edit", state: .failed)]
        T.check("Stop ends a step that never finished as stopped, and leaves the others alone", ChatStep.endingUnfinished(mixed).map(\.state), [.done, .stopped, .failed])

        T.section("Failures")
        func code(_ stderr: String, lines: [String] = []) -> String? {
            fold(lines: lines, stderr: stderr).error?.code
        }
        T.check("git-bash in any case", code("CLAUDE_CODE_GIT_BASH_PATH=C:\\x"), ClaudeCodeError.needsGit)
        T.check("a signed-out result without an assistant error",
                code("", lines: [#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}"#]),
                ClaudeCodeError.signedOut)
        T.check("billing_error is billing", fold(lines: [#"{"type":"assistant","error":"billing_error","message":{"content":[]}}"#,
                                                         #"{"type":"result","subtype":"success","is_error":true,"result":"x"}"#], stderr: "").error?.kind, .billing)
        T.check("server_error is a server failure", fold(lines: [#"{"type":"assistant","error":"server_error","message":{"content":[]}}"#,
                                                                #"{"type":"result","subtype":"success","is_error":true,"result":"x"}"#], stderr: "").error?.kind, .server)
        T.check("an unknown error result is a crash, never a guess",
                code("", lines: [#"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}"#]),
                ClaudeCodeError.crashed)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-claude-code.sh`
Expected: FAIL, a compile error in `tests/ClaudeCodeParserTests.swift`: the parser and `ChatStep` do not exist.

```text
tests/ClaudeCodeParserTests.swift:8:21: error: cannot find type 'EngineReport' in scope
tests/ClaudeCodeParserTests.swift:10:21: error: cannot find type 'ChatStep' in scope
tests/ClaudeCodeParserTests.swift:16:22: error: cannot find 'ClaudeStreamParser' in scope
```

- [ ] **Step 3: Write the shared types, the parser and the runner's side**

The shared types first: a step, what the engine says about itself, two chunk cases, and the time a limit resets.

**Edit `NotchBuddy/Sources/App/AI/Core/ModelProvider.swift`**, find this text (it occurs exactly once):

```swift
}

enum FinishReason: String, Sendable, Equatable {
    case stop, length, refusal
```

and replace it with:

```swift
}

/// One tool step Claude Code takes on its own (reading a file, running a command), shown as a row in the chat.
struct ChatStep: Sendable, Equatable, Hashable {
    enum State: String, Sendable { case running, done, failed, stopped }

    let id: String
    var tool: String
    /// Only the fields that say what the step does (command, file_path, path, query, pattern, url), each cut to
    /// 200 Unicode scalars: never a file's content.
    var input: [String: String] = [:]
    var state: State = .running

    /// A step that never finished (Stop, a crash) ends as stopped: no row stays "running". The others are left alone.
    static func endingUnfinished(_ steps: [ChatStep]) -> [ChatStep] {
        steps.map { step in
            var ended = step
            if ended.state == .running { ended.state = .stopped }
            return ended
        }
    }
}

/// What a Claude Code run says about itself in its first event (`system/init`).
struct EngineReport: Sendable, Equatable {
    enum Payer: String, Sendable {
        case plan
        case apiKey = "api_key"
        case unknown
    }

    var sessionID: String
    var model: String
    var paidBy: Payer
    var version: String?
}

enum FinishReason: String, Sendable, Equatable {
    case stop, length, refusal
```

**Edit `NotchBuddy/Sources/App/AI/Core/ModelProvider.swift`**, find this text (it occurs exactly once):

```swift
    /// Counts as the first token for timeouts; carries nothing to show.
    case activity
}

```

and replace it with:

```swift
    /// Counts as the first token for timeouts; carries nothing to show.
    case activity
    /// A step Claude Code is taking, or has finished (the same `id` updates the same row).
    case step(ChatStep)
    /// What the engine reported about the run it started.
    case engine(EngineReport)
}

```

**Edit `NotchBuddy/Sources/App/AI/Core/ModelProvider.swift`**, find this text (it occurs exactly once):

```swift
    /// `x-request-id` / `request-id`, logged for support.
    var requestID: String? = nil
}

```

and replace it with:

```swift
    /// `x-request-id` / `request-id`, logged for support.
    var requestID: String? = nil
    /// When a usage limit resets (the Claude plan's limit), so the chat can say when.
    var resetsAt: Date? = nil
}

```

`ReplyAccumulator` notes that steps were taken, and `ChatRunner` forwards the two new events and refuses to hand a question that already did work to another model.

**Edit `NotchBuddy/Sources/App/AI/Core/ReplyAccumulator.swift`**, find this text (it occurs exactly once):

```swift
    private var finishReason: FinishReason?
    private(set) var error: AIErrorKind?

    init(stripsThinkBlocks: Bool) { self.stripsThinkBlocks = stripsThinkBlocks }
```

and replace it with:

```swift
    private var finishReason: FinishReason?
    private(set) var error: AIErrorKind?
    /// Claude Code took at least one step: the work is done, so Auto must not hand the question to another model.
    private(set) var sawSteps = false

    init(stripsThinkBlocks: Bool) { self.stripsThinkBlocks = stripsThinkBlocks }
```

**Edit `NotchBuddy/Sources/App/AI/Core/ReplyAccumulator.swift`**, find this text (it occurs exactly once):

```swift
        case .error(let kind):
            error = kind
        case .activity:
            break
        }
    }
```

and replace it with:

```swift
        case .error(let kind):
            error = kind
        case .activity, .engine:
            break
        case .step:
            sawSteps = true
        }
    }
```

**Edit `NotchBuddy/Sources/App/AI/Core/ChatRunner.swift`**, find this text (it occurs exactly once):

```swift
    case waking(ChatTarget)
    case fellBack(from: ChatTarget, to: ChatTarget, kind: AIErrorKind)
}

```

and replace it with:

```swift
    case waking(ChatTarget)
    case fellBack(from: ChatTarget, to: ChatTarget, kind: AIErrorKind)
    /// Claude Code started, or updated, a step.
    case step(ChatStep)
    /// What Claude Code said about the run it started (who pays, which model).
    case engine(EngineReport)
}

```

**Edit `NotchBuddy/Sources/App/AI/Core/ChatRunner.swift`**, find this text (it occurs exactly once):

```swift
    var citations: [Citation] = []
    var finish: FinishReason? = nil
    /// The failure behind `error`, `retryCountdown`, `fallback` (the primary's) or `interrupted`.
    var error: AIError? = nil
```

and replace it with:

```swift
    var citations: [Citation] = []
    var finish: FinishReason? = nil
    /// Claude Code took steps before the failure: whatever they did stays done.
    var tookSteps = false
    /// The failure behind `error`, `retryCountdown`, `fallback` (the primary's) or `interrupted`.
    var error: AIError? = nil
```

**Edit `NotchBuddy/Sources/App/AI/Core/ChatRunner.swift`**, find this text (it occurs exactly once):

```swift
        // Out of room is not a passing problem: another model would not be asked the same question, so
        // the user is told, with a way to pick another model.
        if !first.text.isEmpty || error.kind == .cancelled || error.kind == .refusal
            || error.code == AIError.outOfRoomCode {
            return first
```

and replace it with:

```swift
        // Out of room is not a passing problem: another model would not be asked the same question, so
        // the user is told, with a way to pick another model.
        if !first.text.isEmpty || first.tookSteps || error.kind == .cancelled || error.kind == .refusal
            || error.code == AIError.outOfRoomCode {
            return first
```

**Edit `NotchBuddy/Sources/App/AI/Core/ChatRunner.swift`**, find this text (it occurs exactly once):

```swift
                case .citation(let c):
                    await onEvent(.citation(c))
                default:
                    break
```

and replace it with:

```swift
                case .citation(let c):
                    await onEvent(.citation(c))
                case .step(let step):
                    shown.set()
                    await onEvent(.step(step))
                case .engine(let report):
                    await onEvent(.engine(report))
                default:
                    break
```

**Edit `NotchBuddy/Sources/App/AI/Core/ChatRunner.swift`**, find this text (it occurs exactly once):

```swift
            let outcome: RouteOutcome = failure.kind == .cancelled ? .cancelled : (text.isEmpty ? .error : .interrupted)
            return RunResult(outcome: outcome, answeredBy: text.isEmpty ? nil : target, text: text,
                             citations: acc.citations, error: failure)
        }
        await onEvent(.text(acc.visibleText))
```

and replace it with:

```swift
            let outcome: RouteOutcome = failure.kind == .cancelled ? .cancelled : (text.isEmpty ? .error : .interrupted)
            return RunResult(outcome: outcome, answeredBy: text.isEmpty ? nil : target, text: text,
                             citations: acc.citations, tookSteps: acc.sawSteps, error: failure)
        }
        await onEvent(.text(acc.visibleText))
```

`ClaudeService` switches over every run event with no `default`, so the app would stop compiling; give the two new events a place to go (Task 10 replaces this with the real handling).

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
                    case .fellBack(let from, let to, _):
                        state.chatHistory[i].notice = AIMessages.fellBack(from: from, to: to)
                    }
                }
```

and replace it with:

```swift
                    case .fellBack(let from, let to, _):
                        state.chatHistory[i].notice = AIMessages.fellBack(from: from, to: to)
                    case .step, .engine:
                        break  // what Claude Code does and says about itself: shown once the chat is wired to it
                    }
                }
```

**Create `NotchBuddy/Sources/App/AI/Core/ClaudeStreamParser.swift`** with exactly this content:

```swift
import Foundation

// What Claude Code's stream-json output means: text, steps, who pays, and how a run failed. Read one line at a time.
// The rules are `parse()` in `tests/fixtures/ai/claude-code/reference.py`; `expected-parse.json` pins them.
//
// The exact JSON of Claude Code's failures is not documented, so this is tolerant on purpose: a line that is not
// JSON, or an event it does not know, is skipped; a run that ends without a result and without a failure it
// recognises is "Claude stopped unexpectedly", never a guess at what went wrong.

#if !APPSTORE

/// Codes on `AIError.code` for Claude Code's failures, on top of the twelve shared error kinds.
enum ClaudeCodeError {
    static let missing = "nm_claude_missing"
    static let signedOut = "nm_signed_out"
    static let planLimit = "nm_plan_limit"
    static let tooOld = "nm_claude_old"
    static let crashed = "nm_claude_crashed"
    static let offline = "nm_claude_offline"
    static let needsGit = "nm_needs_git"
    static let folderMissing = "nm_folder_missing"
}

struct ClaudeStreamParser {
    /// Only these fields of a tool's input say what the step does. A Write's `content` never gets here.
    static let stepFields = ["command", "file_path", "path", "query", "pattern", "url"]
    static let stepFieldCap = 200

    private(set) var engine: EngineReport?
    /// Everything shown so far, so the failure rules know whether anything was said.
    private(set) var text = ""

    private var needsBreak = false
    private var steps: [String: ChatStep] = [:]
    private var finished = false
    private var resultSeen = false
    private var resultIsError = false
    private var resultSubtype = ""
    private var resultText = ""
    private var assistantError: String?
    /// nil: no rate-limit event that rejected; 0: rejected, no time given; else Unix seconds.
    private var rejectedResetsAt: Int64?
    private var retried = false

    /// Chunks for one line of stdout.
    mutating func consume(line: String) -> [ChatChunk] {
        guard let data = line.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        switch event["type"] as? String {
        case "system":
            switch event["subtype"] as? String {
            case "init":
                let report = EngineReport(sessionID: event["session_id"] as? String ?? "",
                                          model: event["model"] as? String ?? "",
                                          paidBy: Self.payer(event["apiKeySource"] as? String),
                                          version: event["claude_code_version"] as? String)
                engine = report
                return [.engine(report)]
            case "api_retry":
                retried = true
                return [.activity]
            default:
                return []
            }
        case "stream_event":
            return consumeStream(event["event"] as? [String: Any] ?? [:])
        case "assistant":
            return consumeAssistant(event)
        case "user":
            return consumeToolResults(event)
        case "rate_limit_event":
            let info = event["rate_limit_info"] as? [String: Any] ?? [:]
            if info["status"] as? String == "rejected" {
                rejectedResetsAt = (info["resetsAt"] as? NSNumber).map { $0.int64Value } ?? 0
            }
            return []
        case "result":
            resultSeen = true
            resultIsError = event["is_error"] as? Bool ?? false
            resultSubtype = event["subtype"] as? String ?? ""
            resultText = event["result"] as? String ?? ""
            if !resultIsError && resultSubtype == "success" {
                finished = true
                return [.finish(.stop)]
            }
            if resultSubtype == "error_max_turns" {
                finished = true
                return [.finish(.length)]
            }
            return []
        default:
            return []
        }
    }

    private static func payer(_ source: String?) -> EngineReport.Payer {
        switch source {
        case "none", "oauth": .plan
        case "user", "project", "org", "temporary": .apiKey
        default: .unknown
        }
    }

    private mutating func consumeStream(_ e: [String: Any]) -> [ChatChunk] {
        switch e["type"] as? String {
        case "message_start":
            needsBreak = needsBreak || !text.isEmpty
            return []
        case "content_block_start":
            let block = e["content_block"] as? [String: Any] ?? [:]
            if block["type"] as? String == "tool_use", let id = block["id"] as? String {
                needsBreak = needsBreak || !text.isEmpty
                let step = ChatStep(id: id, tool: block["name"] as? String ?? "")
                steps[id] = step
                return [.step(step)]
            }
            if block["type"] as? String == "text", needsBreak, !text.isEmpty {
                needsBreak = false
                text += "\n\n"
                return [.text("\n\n")]
            }
            return []
        case "content_block_delta":
            let delta = e["delta"] as? [String: Any] ?? [:]
            guard delta["type"] as? String == "text_delta", let piece = delta["text"] as? String else { return [] }
            var out: [ChatChunk] = []
            if needsBreak, !text.isEmpty { text += "\n\n"; out.append(.text("\n\n")) }
            needsBreak = false
            text += piece
            out.append(.text(piece))
            return out
        default:
            return []
        }
    }

    private mutating func consumeAssistant(_ event: [String: Any]) -> [ChatChunk] {
        if let error = event["error"] as? String { assistantError = error }
        var out: [ChatChunk] = []
        let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        for block in content where block["type"] as? String == "tool_use" {
            guard let id = block["id"] as? String, var step = steps[id] else { continue }
            step.input = Self.stepInput(block["input"] as? [String: Any] ?? [:])
            steps[id] = step
            out.append(.step(step))
        }
        return out
    }

    private mutating func consumeToolResults(_ event: [String: Any]) -> [ChatChunk] {
        var out: [ChatChunk] = []
        let content = (event["message"] as? [String: Any])?["content"] as? [Any] ?? []
        for case let block as [String: Any] in content where block["type"] as? String == "tool_result" {
            guard let id = block["tool_use_id"] as? String, var step = steps[id] else { continue }
            step.state = (block["is_error"] as? Bool ?? false) ? .failed : .done
            steps[id] = step
            out.append(.step(step))
        }
        return out
    }

    private static func stepInput(_ raw: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for key in stepFields {
            guard let value = raw[key] as? String else { continue }
            out[key] = String(String.UnicodeScalarView(value.unicodeScalars.prefix(stepFieldCap)))
        }
        return out
    }

    // MARK: The end of the run

    /// `nil` when the run ended well. Call once, after the process has exited. `stderr` is only read, never kept.
    /// The exit status is not used: Claude Code does not document one, and a result decides when there is one.
    func failure(stderr: String) -> AIError? {
        if finished { return nil }
        let words = (resultSeen ? resultText : "")
        let blob = (words + "\n" + stderr).lowercased()
        let paid = engine?.paidBy
        func fail(_ kind: AIErrorKind, _ code: String? = nil, resetsAt: Int64? = nil) -> AIError {
            AIError(kind: kind, code: code,
                    resetsAt: resetsAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil })
        }
        if blob.contains("git-bash") || blob.contains("claude_code_git_bash_path") || blob.contains("git for windows") {
            return fail(.badRequest, ClaudeCodeError.needsGit)
        }
        if assistantError == "authentication_failed" || blob.contains("not logged in") || blob.contains("please run /login") {
            return fail(.auth, ClaudeCodeError.signedOut)
        }
        if blob.contains("unknown option") { return fail(.badRequest, ClaudeCodeError.tooOld) }
        if rejectedResetsAt != nil || (assistantError == "rate_limit" && paid == .plan) {
            return fail(.billing, ClaudeCodeError.planLimit, resetsAt: rejectedResetsAt)
        }
        if assistantError == "rate_limit" { return fail(.rateLimited) }
        if assistantError == "billing_error" { return fail(.billing, "billing_error") }
        if assistantError == "overloaded" { return fail(.overloaded) }
        if assistantError == "server_error" { return fail(.server) }
        if resultSeen, retried || blob.contains("unable to connect") { return fail(.unreachable, ClaudeCodeError.offline) }
        return fail(.interrupted, ClaudeCodeError.crashed)
    }
}

#endif
```

- [ ] **Step 4: Run the Claude Code tests**

Run: `bash scripts/test-claude-code.sh`
Expected: PASS, `== ClaudeCodeEngineTests` and `== ClaudeCodeParserTests`, every line `✓`, no `✗`.

```text
== ClaudeCodeEngineTests
All tests passed.
== ClaudeCodeParserTests
All tests passed.
```

- [ ] **Step 5: Run the other AI test programs and build the app**

The runner and the accumulator are shared with every provider, so the whole AI suite must stay green.

Run: `for s in scripts/test-ai-*.sh; do bash "$s" > /dev/null 2>&1 && echo "ok $s" || { echo "FAILED $s"; exit 1; }; done`
Expected: PASS, one `ok` line per script and no `FAILED`.

Run: `(cd NotchBuddy && xcodegen --quiet && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

`xcodegen` has regenerated `project.pbxproj`, which now lists the new Swift file; it is committed below.

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj NotchBuddy/Sources/App/AI/Core/ClaudeStreamParser.swift NotchBuddy/Sources/App/AI/Core/ModelProvider.swift NotchBuddy/Sources/App/AI/Core/ReplyAccumulator.swift NotchBuddy/Sources/App/AI/Core/ChatRunner.swift NotchBuddy/Sources/App/ClaudeService.swift tests/ClaudeCodeParserTests.swift
git commit -q -m "feat(claude-code): the transcript parser, steps, and the runner's step and engine events" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 6: Mac: the provider, one process per turn, and Stop

**Agent:** `nm-implementer-deep`. A process, its pipes and its children, concurrency under Swift 6, and a Stop that must not leave anything running. If a test is flaky, fix the code, not the test: a Stop that sometimes leaves a process behind is the bug this task exists to prevent.

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift`
- Create: `tests/ClaudeCodeProviderTests.swift`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (generated)

**Interfaces:**
- Consumes: `ClaudeCodeCommand`, `ClaudeCodeTurn` (Task 4); `ClaudeStreamParser`, `ClaudeCodeError`, `ChatChunk.step/.engine` (Task 5); `ModelProvider`, `ChatRequest`, `SSELineSplitter`, `AILog` (existing); the fake `claude` (Task 2).
- Produces:

  ```swift
  struct ClaudeProcessTimings: Sendable, Equatable { var startup: TimeInterval = 30; var interruptGrace = 2.0; var terminateGrace = 2.0; var drain = 1.0; static let standard }
  enum ClaudeCodeFolders { static func chatFolder() -> String; static func ensure(_ path: String) }   // <Application Support>/NotchMeow/claude-chat, mode 0700
  struct ClaudeCodeProvider: ModelProvider {      // id .claudeCode, "Claude plan", placement .cloud
      var executable: String; var turn: ClaudeCodeTurn; var chatFolder: String = ClaudeCodeFolders.chatFolder()
      var preamble: String? = nil; var baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
      var timings: ClaudeProcessTimings = .standard
      func listModels() async throws -> [ModelInfo]                  // Sonnet, Opus, Haiku
      func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error>
  }
  ```

  `stream` writes the request's last user message to stdin (with the recap in front when `preamble` is set), then closes it, and yields the parser's chunks. When the consumer goes away (Stop, a new conversation) it interrupts the process, terminates it after `interruptGrace`, kills it after `terminateGrace`, and kills every descendant it saw when Stop was pressed. Failures are thrown as `AIError` with the codes of Task 5, plus `nm_claude_missing` (the program could not start), `nm_folder_missing` (the working folder is gone) and a `.timeout` when `system/init` does not come in `startup` seconds. Exactly one watchdog sleep runs, and only during a turn: nothing polls and nothing runs while the chat is idle.

- [ ] **Step 1: Write the failing test**

Every case runs the fake `claude`, never a real one. It checks one whole turn (the argv, the stripped environment, stdin, the working folder, the parsed chunks), each failure transcript, Stop (a fake that hangs mid-tool with a child process; one that ignores interrupt and terminate), two runs at once, a folder with spaces and non-ASCII characters, and a leak test: a unique marker in the prompt, the folder name and the environment must appear nowhere in the log. It pins Review Focus 2 (Stop), 3 (two runs at once), 6 (the folder) and 11 (the leak test).

**Create `tests/ClaudeCodeProviderTests.swift`** with exactly this content:

```swift
import Foundation

// The runner against the fake `claude` (tests/fixtures/ai/claude-code/fake_claude.py). No real claude is ever run.

@main
@MainActor
enum ClaudeCodeProviderTests {
    static let sid = "11111111-1111-4111-8111-111111111111"
    static let marker = "ZZ-LEAK-MARKER-7391"
    static var fixtures: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/ai/claude-code")
    }
    static var fake: String { fixtures.appendingPathComponent("fake_claude.py").path }

    /// A scratch folder of this test's own, removed at the end.
    final class Scratch: @unchecked Sendable {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nm-claude-test-\(UUID().uuidString)")
        init() { try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        func folder(_ name: String) -> String {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url.path
        }
        func file(_ name: String) -> String { root.appendingPathComponent(name).path }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    struct Outcome: @unchecked Sendable {   // `calls` holds parsed JSON
        var chunks: [ChatChunk] = []
        var error: AIError?
        var calls: [[String: Any]] = []
        var text: String { chunks.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined() }
        var steps: [ChatStep] {
            var out: [ChatStep] = []
            for case .step(let s) in chunks {
                if let i = out.firstIndex(where: { $0.id == s.id }) { out[i] = s } else { out.append(s) }
            }
            return out
        }
        /// The one `claude -p` call (not a --version or auth call).
        var turn: [String: Any]? { calls.first { ($0["argv"] as? [String])?.first == "-p" } }
    }

    static func request(_ text: String = "Hello") -> ChatRequest {
        ChatRequest(model: "sonnet", system: "", messages: [.init(role: .user, parts: [.text(text)])])
    }

    static func readLog(_ path: String) -> [[String: Any]] {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    static func provider(_ scratch: Scratch, transcript: String?, level: ClaudeCodeLevel = .chatOnly, resume: Bool = false,
                         session: String = sid, extra: [String: String] = [:], log: String? = nil,
                         timings: ClaudeProcessTimings = ClaudeProcessTimings(startup: 20, interruptGrace: 2, terminateGrace: 2, drain: 1),
                         executable: String? = nil) -> ClaudeCodeProvider {
        var env = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
                   "NM_FAKE_CLAUDE_LOG": log ?? scratch.file("log.jsonl"),
                   "CANARY": "kept",
                   // What must never reach the run:
                   "ANTHROPIC_API_KEY": "sk-ant-FAKE", "ANTHROPIC_AUTH_TOKEN": "tok-FAKE",
                   "CLAUDE_CODE_OAUTH_TOKEN": "oauth-FAKE", "ANTHROPIC_PROFILE": "work", "CLAUDE_CODE_USE_BEDROCK": "1"]
        if let transcript { env["NM_FAKE_CLAUDE_TRANSCRIPT"] = fixtures.appendingPathComponent("transcripts/\(transcript)").path }
        env.merge(extra) { $1 }
        return ClaudeCodeProvider(executable: executable ?? fake,
                                  turn: ClaudeCodeTurn(level: level, sessionID: session, resume: resume),
                                  chatFolder: scratch.folder("chat"), baseEnvironment: env, timings: timings)
    }

    static func collect(_ provider: ClaudeCodeProvider, _ req: ChatRequest = request(), log: String) async -> Outcome {
        var out = Outcome()
        do {
            for try await chunk in provider.stream(req) { out.chunks.append(chunk) }
        } catch {
            out.error = error as? AIError ?? AIError(kind: .server)
        }
        out.calls = readLog(log)
        return out
    }

    static func alive(_ pidFile: String) -> Bool {
        guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8), let pid = Int32(text) else { return false }
        return kill(pid, 0) == 0
    }

    static func waitUntilGone(_ files: [String], seconds: Double) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if files.allSatisfy({ !alive($0) }) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    static func main() async {
        // A hung run would hang the build: stop the whole program instead.
        DispatchQueue.global().asyncAfter(deadline: .now() + 180) { print("timed out"); exit(3) }
        let scratch = Scratch()
        await turns(scratch)
        await failures(scratch)
        await stopping(scratch)
        await concurrency(scratch)
        await folders(scratch)
        await leaks(scratch)
        T.finish()
    }

    // MARK: - One turn

    static func turns(_ s: Scratch) async {
        T.section("A turn")
        let log = s.file("turn.jsonl")
        let p = provider(s, transcript: "success.jsonl", log: log)
        let out = await collect(p, log: log)
        T.check("the reply", out.text, "Bonjour Zoé, hello! 🐱")
        T.check("no error", out.error == nil, true)
        let turn = out.turn!
        T.check("the command line is the engine's", turn["argv"] as? [String], ClaudeCodeCommand.arguments(p.turn))
        T.check("it runs in the chat folder", URL(fileURLWithPath: turn["cwd"] as! String).resolvingSymlinksInPath().path,
                URL(fileURLWithPath: p.chatFolder).resolvingSymlinksInPath().path)
        let env = turn["env"] as! [String: String]
        T.check("what outranks the plan login is gone",
                ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_PROFILE", "CLAUDE_CODE_USE_BEDROCK"].filter { env[$0] != nil }, [])
        T.check("the rest of the environment is kept", env["CANARY"], "kept")
        let stdin = try! JSONSerialization.jsonObject(with: Data((turn["stdin"] as! String).utf8)) as! [String: Any]
        let blocks = (stdin["message"] as! [String: Any])["content"] as! [[String: Any]]
        T.check("the message goes in on stdin, and stdin was closed (the fake reads to its end)", blocks.first?["text"] as? String, "Hello")
        T.check("the engine's report", out.chunks.contains { if case .engine(let r) = $0 { r.model == "claude-sonnet-5-5" && r.paidBy == .plan } else { false } }, true)

        let tools = await collect(provider(s, transcript: "tool-use.jsonl", level: .readOnly(folder: s.folder("project")), resume: true, log: s.file("tools.jsonl")), log: s.file("tools.jsonl"))
        T.check("steps arrive as rows that update", tools.steps.map { "\($0.id):\($0.state.rawValue)" }, ["toolu_01A:done", "toolu_01B:failed"])
        T.check("and the text reads as paragraphs", tools.text, "I'll read the README.\n\nIt says it is a tiny demo.")
        T.check("a later turn resumes the session", (tools.turn?["argv"] as? [String])?.contains("--resume"), true)
    }

    // MARK: - Failures

    static func failures(_ s: Scratch) async {
        T.section("Failures")
        func run(_ transcript: String, exit: String = "1", stderr: String = "", name: String) async -> Outcome {
            let log = s.file("f-\(name).jsonl")
            return await collect(provider(s, transcript: transcript, extra: ["NM_FAKE_CLAUDE_EXIT": exit, "NM_FAKE_CLAUDE_STDERR": stderr], log: log), log: log)
        }
        let signedOut = await run("signed-out.jsonl", name: "so")
        T.check("signed out", signedOut.error?.code, ClaudeCodeError.signedOut)
        let limit = await run("plan-limit.jsonl", name: "pl")
        T.check("the plan's limit", [limit.error?.kind.rawValue, limit.error?.code], ["billing", ClaudeCodeError.planLimit])
        T.check("and when it resets", limit.error?.resetsAt, Date(timeIntervalSince1970: 1791301500))
        let offline = await run("offline.jsonl", name: "off")
        T.check("offline", offline.error?.code, ClaudeCodeError.offline)
        let crash = await run("crash.jsonl", exit: "2", name: "cr")
        T.check("a cut stream keeps what was said", crash.text, "Let me look")
        T.check("and is an interrupted reply", [crash.error?.kind.rawValue, crash.error?.code], ["interrupted", ClaudeCodeError.crashed])
        let git = await run("empty.jsonl", stderr: "Claude Code on Windows requires git-bash", name: "git")
        T.check("Git for Windows missing, from stderr", git.error?.code, ClaudeCodeError.needsGit)

        let none = await collect(provider(s, transcript: nil, executable: "/nonexistent/claude"), log: s.file("none.jsonl"))
        T.check("no such program is 'not installed'", [none.error?.kind.rawValue, none.error?.code], ["unreachable", ClaudeCodeError.missing])
        let gone = await collect(provider(s, transcript: "success.jsonl", level: .readOnly(folder: "/nonexistent-folder-zz")), log: s.file("gone.jsonl"))
        T.check("a folder that is not there", [gone.error?.kind.rawValue, gone.error?.code], ["bad_request", ClaudeCodeError.folderMissing])
        T.check("and nothing was started", gone.turn == nil, true)

        let quiet = provider(s, transcript: nil, extra: ["NM_FAKE_CLAUDE_HANG_AFTER": "0", "NM_FAKE_CLAUDE_PIDFILE": s.file("quiet.pid")],
                             log: s.file("quiet.jsonl"), timings: ClaudeProcessTimings(startup: 0.6, interruptGrace: 0.2, terminateGrace: 0.2, drain: 0.2))
        let silent = await collect(quiet, log: s.file("quiet.jsonl"))
        T.check("a run that never says anything times out", silent.error?.kind, .timeout)
        T.checkTrue("and is stopped", await waitUntilGone([s.file("quiet.pid")], seconds: 5))
    }

    // MARK: - Stop

    static func stopping(_ s: Scratch) async {
        T.section("Stop")
        for stubborn in [false, true] {
            let tag = stubborn ? "stubborn" : "polite"
            let pid = s.file("\(tag).pid"), child = s.file("\(tag).child")
            var extra = ["NM_FAKE_CLAUDE_HANG_AFTER": "8", "NM_FAKE_CLAUDE_PIDFILE": pid, "NM_FAKE_CLAUDE_CHILD_PIDFILE": child]
            if stubborn { extra["NM_FAKE_CLAUDE_STUBBORN"] = "1" }
            let p = provider(s, transcript: "tool-use.jsonl", extra: extra, log: s.file("\(tag).jsonl"),
                             timings: ClaudeProcessTimings(startup: 20, interruptGrace: 0.3, terminateGrace: 0.3, drain: 0.3))
            var sawStep = false
            do {
                for try await chunk in p.stream(request()) {
                    if case .step = chunk {
                        sawStep = true
                        // The fake writes the pid of the child it started a moment after its step line: wait for it, so
                        // that "gone" below means something.
                        var waited = 0
                        while !FileManager.default.fileExists(atPath: child), waited < 250 {
                            try? await Task.sleep(nanoseconds: 20_000_000)
                            waited += 1
                        }
                        T.checkTrue("\(tag): the process and its child were both running when Stop came", alive(pid) && alive(child))
                        break
                    }
                }
            } catch {}
            T.checkTrue("\(tag): a step was running when Stop came", sawStep)
            let started = Date()
            T.checkTrue("\(tag): the process and what it started are gone", await waitUntilGone([pid, child], seconds: 8))
            print("    (\(String(format: "%.1f", Date().timeIntervalSince(started))) s)")
        }
    }

    // MARK: - Two at once

    static func concurrency(_ s: Scratch) async {
        T.section("Two runs at once")
        let aLog = s.file("a.jsonl"), bLog = s.file("b.jsonl")
        let a = provider(s, transcript: "success.jsonl", session: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", log: aLog)
        let b = provider(s, transcript: "tool-use.jsonl", level: .readOnly(folder: s.folder("other")), session: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", log: bLog)
        async let first = collect(a, log: aLog)
        async let second = collect(b, log: bLog)
        let (one, two) = await (first, second)
        T.check("each run has its own reply", [one.text, two.text], ["Bonjour Zoé, hello! 🐱", "I'll read the README.\n\nIt says it is a tiny demo."])
        T.check("and its own session",
                [(one.turn?["argv"] as? [String])?.contains("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
                 (two.turn?["argv"] as? [String])?.contains("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")], [true, true])
        T.check("a chat's steps never reach the other", [one.steps.count, two.steps.count], [0, 2])
    }

    // MARK: - Folders with spaces and non-ASCII characters

    static func folders(_ s: Scratch) async {
        T.section("A folder with spaces and non-ASCII characters")
        let folder = s.folder("Zoé Mes projets/ünï côde")
        let log = s.file("unicode.jsonl")
        let p = provider(s, transcript: "tool-use.jsonl", level: .readOnly(folder: folder), log: log)
        let out = await collect(p, log: log)
        T.check("it works", out.error == nil && out.text.hasSuffix("tiny demo."), true)
        T.check("the process runs in it", URL(fileURLWithPath: out.turn!["cwd"] as! String).resolvingSymlinksInPath().path,
                URL(fileURLWithPath: folder).resolvingSymlinksInPath().path)
        T.checkTrue("and no argument carries it", !(out.turn!["argv"] as! [String]).contains { $0.contains("ünï") })
    }

    // MARK: - Nothing private in the log

    static func leaks(_ s: Scratch) async {
        T.section("Log leak test")
        final class Lines: @unchecked Sendable {
            let lock = NSLock()
            var all: [String] = []
            func add(_ l: String) { lock.withLock { all.append(l) } }
        }
        let lines = Lines()
        AILog.sink.replace { lines.add($0) }
        let folder = s.folder("\(marker)-folder")
        let log = s.file("leak.jsonl")
        for transcript in ["success.jsonl", "plan-limit.jsonl", "crash.jsonl"] {
            let p = provider(s, transcript: transcript, level: .readOnly(folder: folder),
                             extra: ["NM_FAKE_CLAUDE_STDERR": "stderr says \(marker)", "LEAK_ENV": marker, "NM_FAKE_CLAUDE_EXIT": "1"], log: log)
            _ = await collect(p, request("tell me about \(marker)"), log: log)
        }
        let captured = lines.lock.withLock { lines.all }
        T.checkTrue("events were logged", captured.count >= 3)
        T.check("no log line holds the prompt, the folder, stderr or the environment", captured.filter { $0.contains(marker) }, [])
        T.check("and none holds the session id", captured.filter { $0.contains(sid) }, [])
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-claude-code.sh`
Expected: FAIL, a compile error in `tests/ClaudeCodeProviderTests.swift`: `ClaudeCodeProvider` does not exist.

```text
tests/ClaudeCodeProviderTests.swift:57:56: error: cannot find type 'ClaudeCodeProvider' in scope
tests/ClaudeCodeProviderTests.swift:56:35: error: cannot find type 'ClaudeProcessTimings' in scope
tests/ClaudeCodeProviderTests.swift:71:37: error: cannot find type 'ClaudeCodeProvider' in scope
```

- [ ] **Step 3: Write the provider**

**Create `NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift`** with exactly this content:

```swift
import Foundation

// Claude Code as a provider: one `claude -p` process per turn. This file owns the process; the command line and the
// transcript's meaning are in `ClaudeCodeEngine.swift` and `ClaudeStreamParser.swift`.
//
// Nothing runs on a timer. A turn starts one process and ends when it does; Stop interrupts it, then terminates it,
// then kills it (and whatever it started), so no process outlives the chat. Nothing is logged but event types and
// error kinds (`AILog`): never the arguments, the folder, stdin, stdout, stderr or the environment.

#if !APPSTORE

struct ClaudeProcessTimings: Sendable, Equatable {
    /// Seconds to wait for the run's first event. Claude Code says `system/init` within a second or two.
    var startup: TimeInterval = 30
    /// Stop: seconds after the interrupt before the process is terminated, and after that before it is killed.
    var interruptGrace: TimeInterval = 2
    var terminateGrace: TimeInterval = 2
    /// Seconds a pipe may stay open after the process exited (a grandchild that kept it).
    var drain: TimeInterval = 1

    static let standard = ClaudeProcessTimings()
}

/// Where Claude Code's chat-only runs happen: a folder NotchMeow owns and keeps empty.
enum ClaudeCodeFolders {
    /// `<Application Support>/NotchMeow/claude-chat`
    static func chatFolder() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchMeow/claude-chat").path
    }

    /// Makes `path` (and what is above it) if it is not there, readable by the user only.
    static func ensure(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }
}

struct ClaudeCodeProvider: ModelProvider {
    let id = AIProviderID.claudeCode
    let displayName = "Claude plan"
    let placement = AIPlacement.cloud

    /// The program: found by `ClaudeCodeLocator`, never modified.
    var executable: String
    var turn: ClaudeCodeTurn
    var chatFolder: String = ClaudeCodeFolders.chatFolder()
    /// A recap of the chat so far, for a session started afresh in the middle of it.
    var preamble: String? = nil
    /// The caller's environment, from which the run's is made. Tests pass their own.
    var baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    var timings: ClaudeProcessTimings = .standard

    func listModels() async throws -> [ModelInfo] {
        ClaudeCodeModel.allCases.map { ModelInfo(id: $0.rawValue, label: "Claude \($0.label)", capabilities: [.vision, .tools]) }
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AILog.record(.request(id, model: turn.model.rawValue, placement: placement))
        let provider = self
        return AsyncThrowingStream { continuation in
            let run = ClaudeRun()
            let work = Task.detached { await provider.execute(request, run: run, continuation: continuation) }
            continuation.onTermination = { _ in
                run.stop(provider.timings)
                work.cancel()
            }
        }
    }

    private func execute(_ request: ChatRequest, run: ClaudeRun,
                         continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) async {
        let started = Date()
        func fail(_ error: AIError) {
            AILog.record(.failure(id, kind: error.kind, status: nil, code: error.code, requestID: nil))
            continuation.finish(throwing: error)
        }
        let cwd = ClaudeCodeCommand.workingDirectory(turn, chatFolder: chatFolder)
        if turn.level.folder == nil { ClaudeCodeFolders.ensure(cwd) }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isFolder), isFolder.boolValue else {
            return fail(AIError(kind: .badRequest, code: ClaudeCodeError.folderMissing))
        }
        guard let message = request.messages.last(where: { $0.role == .user }) else {
            return fail(AIError(kind: .badRequest))
        }
        let line = ClaudeCodeCommand.userLine(parts: message.parts, preamble: preamble)
        let environment = ClaudeCodeCommand.environment(from: baseEnvironment, platform: turn.platform)
        let output: AsyncStream<Data>
        do {
            output = try run.launch(executable: executable, arguments: ClaudeCodeCommand.arguments(turn),
                                    environment: environment, directory: cwd, stdin: line, drain: timings.drain)
        } catch {
            return fail(AIError(kind: .unreachable, code: ClaudeCodeError.missing))
        }
        // The run must say something soon. After that it may take as long as it needs: a build can run for minutes.
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(timings.startup * 1_000_000_000))
            if !Task.isCancelled, !run.sawOutput { run.timedOut(timings) }
        }
        defer { watchdog.cancel() }

        var parser = ClaudeStreamParser()
        var splitter = SSELineSplitter()
        func feed(_ line: String) {
            for chunk in parser.consume(line: line) { continuation.yield(chunk) }
        }
        for await data in output {
            run.markOutput()
            for byte in data {
                if let complete = splitter.push(byte) { feed(complete) }
            }
        }
        if let last = splitter.flush() { feed(last) }
        await run.waitForExit()
        // Stop is not a failure of the run: the consumer has already gone.
        if run.wasStopped, !run.didTimeOut { return continuation.finish() }
        if run.didTimeOut { return fail(AIError(kind: .timeout)) }
        if let error = parser.failure(stderr: run.stderrText) { return fail(error) }
        AILog.record(.reply(id, ms: Int(Date().timeIntervalSince(started) * 1000), finish: .stop))
        continuation.finish()
    }
}

/// One process. Everything that touches it is behind the lock.
private final class ClaudeRun: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var launched = false
    private var exited = false
    private var stopRequested = false
    private var timedOutFlag = false
    private var outputSeen = false
    private var errorBytes = Data()
    private var exitCallbacks: [@Sendable () -> Void] = []

    private static let errorLimit = 65_536
    private static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    var sawOutput: Bool { lock.withLock { outputSeen } }
    var wasStopped: Bool { lock.withLock { stopRequested } }
    var didTimeOut: Bool { lock.withLock { timedOutFlag } }
    func markOutput() { lock.withLock { outputSeen = true } }
    var stderrText: String { lock.withLock { String(decoding: errorBytes, as: UTF8.self) } }

    /// Starts the process, writes `stdin` to it and closes it, and returns what it prints, in pieces. The stream
    /// ends when stdout does (or `drain` seconds after the process exited).
    func launch(executable: String, arguments: [String], environment: [String: String], directory: String,
                stdin line: Data, drain: TimeInterval) throws -> AsyncStream<Data> {
        _ = Self.ignoreSIGPIPE
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            guard let self else { return }
            self.lock.withLock { if self.errorBytes.count < Self.errorLimit { self.errorBytes.append(data) } }
        }
        process.terminationHandler = { [weak self] _ in
            // A grandchild may still hold the pipe: give the last bytes a moment, then let go.
            DispatchQueue.global().asyncAfter(deadline: .now() + drain) {
                output.fileHandleForReading.readabilityHandler = nil
                continuation.finish()
            }
            guard let self else { return }
            let callbacks = self.lock.withLock { () -> [@Sendable () -> Void] in
                self.exited = true
                defer { self.exitCallbacks = [] }
                return self.exitCallbacks
            }
            callbacks.forEach { $0() }
        }
        try process.run()
        lock.withLock { launched = true }
        // Written on its own thread: a large PDF must not wait for the pipe while the reply is being read.
        DispatchQueue.global().async {
            try? input.fileHandleForWriting.write(contentsOf: line)
            try? input.fileHandleForWriting.close()
        }
        return stream
    }

    func waitForExit() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let already = lock.withLock { () -> Bool in
                if exited || !launched { return true }
                exitCallbacks.append { done.resume() }
                return false
            }
            if already { done.resume() }
        }
    }

    private var running: Bool { lock.withLock { launched && !exited } }

    /// No first event in time: the same as Stop, but the failure is a timeout.
    func timedOut(_ timings: ClaudeProcessTimings) {
        lock.withLock { timedOutFlag = true }
        stop(timings)
    }

    /// Stop. Interrupt first (Claude Code ends the tool it is running), then terminate, then kill the process and
    /// everything it had started when Stop was pressed. Safe to call twice, or after the process ended.
    func stop(_ timings: ClaudeProcessTimings) {
        let pid: Int32? = lock.withLock {
            guard launched, !exited, !stopRequested else { return nil }
            stopRequested = true
            return process.processIdentifier
        }
        guard let pid else { return }
        let family = Self.descendants(of: pid)
        kill(pid, SIGINT)
        Task.detached { [self] in
            try? await Task.sleep(nanoseconds: UInt64(timings.interruptGrace * 1_000_000_000))
            if running { kill(pid, SIGTERM) }
            try? await Task.sleep(nanoseconds: UInt64(timings.terminateGrace * 1_000_000_000))
            if running { kill(pid, SIGKILL) }
            for child in family where kill(child, 0) == 0 { kill(child, SIGKILL) }
        }
    }

    /// Children, grandchildren and so on. `pgrep -P` lists the children of one process.
    static func descendants(of pid: Int32) -> [Int32] {
        var found: [Int32] = []
        var queue = [pid]
        while let next = queue.popLast() {
            let ask = Process()
            ask.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            ask.arguments = ["-P", String(next)]
            let out = Pipe()
            ask.standardOutput = out
            ask.standardError = FileHandle.nullDevice
            guard (try? ask.run()) != nil else { continue }
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            ask.waitUntilExit()
            let children = text.split(whereSeparator: \.isNewline).compactMap { Int32($0) }
            found += children
            queue += children
        }
        return found
    }
}

#endif
```

- [ ] **Step 4: Run the Claude Code tests**

Run: `bash scripts/test-claude-code.sh`
Expected: PASS, three test programs and no `✗`. The provider's own takes a few seconds (the Stop cases wait for processes to die).

```text
== ClaudeCodeEngineTests
All tests passed.
== ClaudeCodeParserTests
All tests passed.
== ClaudeCodeProviderTests
All tests passed.
```

- [ ] **Step 5: Prove the Stop tests can fail**

A Stop test that cannot fail proves nothing. Take away the kill of the children, see the tests catch it, and put it back.

Run: `sed -i.bak 's/{ kill(child, SIGKILL) }/{ _ = child }/' NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift && bash scripts/test-claude-code.sh`
Expected: FAIL, a `✗` line in the Stop section: the child process survived.

Run: `mv NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift.bak NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift && sed -i.bak 's/if running { kill(pid, SIGKILL) }/if running { _ = pid }/' NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift && bash scripts/test-claude-code.sh`
Expected: FAIL, a `✗` line in the Stop section: the process that ignores interrupt and terminate was not killed.

Run: `mv NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift.bak NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift && bash scripts/test-claude-code.sh > /dev/null && echo "all pass"`
Expected: PASS, `all pass`.

The two broken runs left what they could not stop running (that is what they prove): the fake `claude` and its child. End them; the patterns only ever match the fake and its sleeping child.

Run: `pkill -f fake_claude.py; pkill -f "import time; time.sleep\(600\)"; echo cleaned`
Expected: PASS, `cleaned`.

- [ ] **Step 6: Build the app, register the file and commit**

Run: `(cd NotchBuddy && xcodegen --quiet && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

```bash
git add NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift tests/ClaudeCodeProviderTests.swift
git commit -q -m "feat(claude-code): the provider, one process per turn, with a Stop that leaves nothing behind" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 7: Mac: finding Claude Code, its status and signing in

**Agent:** `nm-implementer`.

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/ClaudeCodeLocator.swift`
- Create: `tests/ClaudeCodeLocatorTests.swift`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (generated)

**Interfaces:**
- Consumes: `ClaudeCodeCommand.environment(from:platform:)` (Task 4); `locator-cases.json`, `versions.json`, `auth-status.json` and the fake `claude` (Task 2).
- Produces (all `#if !APPSTORE`):

  ```swift
  struct ClaudeCodeStatus: Equatable, Sendable {
      enum State: Equatable, Sendable { case notInstalled, tooOld, signedOut, signedIn, unknown }
      var state: State; var executable: String? = nil; var version: String? = nil; var authMethod: String? = nil
      var isReady: Bool      // state == .signedIn: the only state the router treats as ready
      static let notInstalled: ClaudeCodeStatus
  }
  enum ClaudeCodeLocator {
      static let minimumVersion = [2, 1, 211]; static let installGuide = "https://docs.claude.com/en/docs/claude-code/setup"
      static func candidates(home: String, environment: [String: String]) -> [String]
      static func find(home: String, environment: [String: String], isExecutable: (String) -> Bool, loginShell: () -> String?) -> (path: String?, askedShell: Bool)
      static func parseVersion(_ text: String) -> [Int]?;  enum VersionCheck { case ok, tooOld, unknown };  static func check(version: [Int]?) -> VersionCheck
      enum AuthResult: Equatable, Sendable { case signedIn(authMethod: String?), signedOut, unknown };  static func parseAuth(exit: Int32?, stdout: String) -> AuthResult
      static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) async -> String?
      static func status(environment: [String: String] = ProcessInfo.processInfo.environment) async -> ClaudeCodeStatus
      static func statusOf(executable: String, environment: [String: String]) async -> ClaudeCodeStatus
  }
  enum ClaudeCodeCLI { static func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval) async -> (status: Int32?, output: String) }
  enum ClaudeCodeSignIn { static func quoted(_ path: String) -> String; static func script(executable: String) -> String; static func write(executable: String, into folder: String) -> String? }
  ```

  Rules: the search order is `~/.local/bin/claude`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `$NPM_CONFIG_PREFIX/bin`, and only then the login shell's `command -v claude` (a login shell is slow, and a Finder-launched app has almost none of the user's `PATH`); the version is the first `x.y.z` of `claude --version`; `claude auth status` exits 0 when signed in and 1 when not, and **only `authMethod` is read** (nothing else is kept, logged or shown); `none` is signed out whatever the exit status says. Both questions are asked in the run's own environment (without what would outrank the plan login), with a 5 and a 10 second limit. A Debug build reads `NM_CLAUDE_CODE_PATH_OVERRIDE` to point the app at the fake; it is behind `#if DEBUG`, so a Release build cannot be pointed at another program (Task 12 proves it). The sign-in script runs `claude auth login` in Terminal through a `.command` file whose path is single-quoted for any shell. Nothing here runs on a timer.

- [ ] **Step 1: Write the failing test**

It replays `locator-cases.json`, `versions.json` and `auth-status.json`, runs the real status checks against the fake `claude` (signed in, signed out, too old, and a `claude` that is not there), and runs the sign-in script for a path with a quote, spaces and accents, checking that it really calls `auth login`. The sign-in script is Review Focus 6's second half: every shell string quotes the folder or path correctly.

**Create `tests/ClaudeCodeLocatorTests.swift`** with exactly this content:

```swift
import Foundation

// The locator and the two checks, against the shared fixtures and the fake `claude`. No real claude is ever run.

@main
@MainActor
enum ClaudeCodeLocatorTests {
    static var fixtures: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/ai/claude-code")
    }

    static func main() async {
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { print("timed out"); exit(3) }
        searchOrder()
        versions()
        authStatus()
        await realChecks()
        await signIn()
        T.finish()
    }

    // MARK: - locator-cases.json

    static func searchOrder() {
        T.section("Where claude is looked for (locator-cases.json)")
        let data = T.fixture("claude-code/locator-cases.json")
        for c in data["cases"] as! [[String: Any]] where (c["platform"] as! String) != "windows" {
            let existing = Set(c["executables"] as! [String])
            var asked = false
            let found = ClaudeCodeLocator.find(home: c["home"] as! String, environment: c["env"] as! [String: String],
                                               isExecutable: { existing.contains($0) },
                                               loginShell: { asked = true; return c["loginShell"] as? String })
            T.check(c["name"] as! String, found.path, c["expect"] as? String)
            T.check("\(c["name"] as! String): the login shell is asked only when nothing earlier exists", asked, c["loginShellCalled"] as! Bool)
        }
        print("  (the Windows cases are run by the Rust tests)")
    }

    // MARK: - versions.json

    static func versions() {
        T.section("Versions (versions.json)")
        let data = T.fixture("claude-code/versions.json")
        T.check("the pinned minimum", ClaudeCodeLocator.minimumVersion, data["minimum"] as! [Int])
        for c in data["parse"] as! [[String: Any]] {
            T.check("parse \(c["text"] as! String)", ClaudeCodeLocator.parseVersion(c["text"] as! String), c["expect"] as? [Int])
        }
        for c in data["check"] as! [[String: Any]] {
            let expect: ClaudeCodeLocator.VersionCheck = switch c["expect"] as! String { case "ok": .ok; case "tooOld": .tooOld; default: .unknown }
            T.check("check \(String(describing: c["version"]))", ClaudeCodeLocator.check(version: c["version"] as? [Int]), expect)
        }
    }

    // MARK: - auth-status.json

    static func authStatus() {
        T.section("Auth status (auth-status.json)")
        let data = T.fixture("claude-code/auth-status.json")
        for c in data["cases"] as! [[String: Any]] {
            let got = ClaudeCodeLocator.parseAuth(exit: (c["exit"] as? NSNumber).map { Int32(truncating: $0) }, stdout: c["stdout"] as! String)
            let e = c["expect"] as! [String: Any]
            let expect: ClaudeCodeLocator.AuthResult = switch e["state"] as! String {
            case "signedIn": .signedIn(authMethod: e["authMethod"] as? String)
            case "signedOut": .signedOut
            default: .unknown
            }
            T.check(c["name"] as! String, got, expect)
        }
    }

    // MARK: - The fake, end to end

    static func realChecks() async {
        T.section("The checks, against the fake claude")
        let fake = fixtures.appendingPathComponent("fake_claude.py").path
        #if DEBUG
        let overridden = await ClaudeCodeLocator.locate(environment: ["NM_CLAUDE_CODE_PATH_OVERRIDE": fake])
        T.check("a Debug build can be pointed at the fake", overridden, fake)
        #endif
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        func status(_ extra: [String: String]) async -> ClaudeCodeStatus {
            let env = ["PATH": path, "HOME": NSHomeDirectory(), "ANTHROPIC_API_KEY": "sk-ant-FAKE"].merging(extra) { $1 }
            return await ClaudeCodeLocator.statusOf(executable: fake, environment: env)
        }
        let ok = await status([:])
        T.check("signed in with a plan", [ok.state == .signedIn, ok.authMethod == "claude.ai", ok.version == "2.1.211"], [true, true, true])
        let out = await status(["NM_FAKE_CLAUDE_AUTH_EXIT": "1", "NM_FAKE_CLAUDE_AUTH_JSON": "{\"authMethod\":\"none\"}"])
        T.check("signed out", out.state, .signedOut)
        let old = await status(["NM_FAKE_CLAUDE_VERSION": "2.1.100 (Claude Code)"])
        T.check("too old", old.state, .tooOld)
        let odd = await status(["NM_FAKE_CLAUDE_VERSION": "hello"])
        T.check("not Claude Code at all", odd.state, .notInstalled)
        let missing = await ClaudeCodeLocator.statusOf(executable: "/nonexistent/claude", environment: ["PATH": path])
        T.check("a program that cannot run is unknown", missing.state, .notInstalled)
    }

    // MARK: - Sign in

    static func signIn() async {
        T.section("Sign in")
        T.check("quoting", ClaudeCodeSignIn.quoted("/Users/O'Brien/Zoé Ünï/.local/bin/claude"), "'/Users/O'\\''Brien/Zoé Ünï/.local/bin/claude'")
        // The script really runs `auth login` with a path full of awkward characters.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nm-signin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("O'Brien Zoé Ünï/bin")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("claude").path
        try! FileManager.default.copyItem(atPath: fixtures.appendingPathComponent("fake_claude.py").path, toPath: copy)
        let log = root.appendingPathComponent("log.jsonl").path
        guard let script = ClaudeCodeSignIn.write(executable: copy, into: root.appendingPathComponent("scripts").path) else {
            return T.checkTrue("the script was written", false)
        }
        T.check("the script is executable", FileManager.default.isExecutableFile(atPath: script), true)
        let env = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin", "NM_FAKE_CLAUDE_LOG": log]
        let ran = await ClaudeCodeCLI.run("/bin/zsh", [script], environment: env, timeout: 20)
        T.check("it ran", ran.status, 0)
        let calls = ((try? String(contentsOfFile: log, encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        T.check("and it called `auth login`", calls.first?["argv"] as? [String], ["auth", "login"])
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-claude-code.sh`
Expected: FAIL, a compile error in `tests/ClaudeCodeLocatorTests.swift`: `ClaudeCodeLocator` does not exist.

```text
tests/ClaudeCodeLocatorTests.swift:30:25: error: cannot find 'ClaudeCodeLocator' in scope
tests/ClaudeCodeLocatorTests.swift:44:39: error: cannot find 'ClaudeCodeLocator' in scope
tests/ClaudeCodeLocatorTests.swift:46:54: error: cannot find 'ClaudeCodeLocator' in scope
```

- [ ] **Step 3: Write the locator**

**Create `NotchBuddy/Sources/App/AI/Core/ClaudeCodeLocator.swift`** with exactly this content:

```swift
import Foundation

// Finding the user's Claude Code and asking it two questions: its version and whether it is signed in. These run
// when Settings opens and before a chat's first turn, never on a timer. NotchMeow never reads Claude Code's
// credential files or Keychain items: it only reads `authMethod` out of `claude auth status` and keeps nothing else.
// The rules are in `tests/fixtures/ai/claude-code/` (`locator-cases.json`, `auth-status.json`, `versions.json`).

#if !APPSTORE

/// What the last check found. `signedIn` is the only state the router treats as ready.
struct ClaudeCodeStatus: Equatable, Sendable {
    enum State: Equatable, Sendable { case notInstalled, tooOld, signedOut, signedIn, unknown }

    var state: State
    var executable: String? = nil
    /// "2.1.211"
    var version: String? = nil
    /// What `claude auth status` reports (`claude.ai`, `api_key`, …): the sign-in method, never an account.
    var authMethod: String? = nil

    var isReady: Bool { state == .signedIn }
    static let notInstalled = ClaudeCodeStatus(state: .notInstalled)
}

enum ClaudeCodeLocator {
    /// The version the flags in `expected-args.json` were verified against (2026-10-06). One number to lower
    /// once older versions have been checked.
    static let minimumVersion = [2, 1, 211]
    /// Where Anthropic's installer is. NotchMeow links to it and installs nothing.
    static let installGuide = "https://docs.claude.com/en/docs/claude-code/setup"

    // MARK: Where it is

    /// The candidates, in order, before the login shell is asked.
    static func candidates(home: String, environment: [String: String]) -> [String] {
        var list = [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                    home + "/.npm-global/bin/claude"]
        if var prefix = environment["NPM_CONFIG_PREFIX"], !prefix.isEmpty {
            while prefix.hasSuffix("/") { prefix.removeLast() }
            list.append(prefix + "/bin/claude")
        }
        return list
    }

    /// The first candidate that is an executable file; failing that, what the login shell's `command -v claude`
    /// printed (its last line, when it is an absolute path to an executable). `loginShell` is only called when no
    /// candidate exists: starting a login shell is slow.
    static func find(home: String, environment: [String: String], isExecutable: (String) -> Bool,
                     loginShell: () -> String?) -> (path: String?, askedShell: Bool) {
        if let hit = candidates(home: home, environment: environment).first(where: isExecutable) { return (hit, false) }
        let lines = (loginShell() ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let last = lines.last, last.hasPrefix("/"), isExecutable(last) { return (last, true) }
        return (nil, true)
    }

    // MARK: Its answers

    /// The first x.y.z in the output of `claude --version`.
    static func parseVersion(_ text: String) -> [Int]? {
        guard let range = text.range(of: #"(\d+)\.(\d+)\.(\d+)"#, options: .regularExpression) else { return nil }
        let parts = text[range].split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : nil
    }

    enum VersionCheck: Equatable { case ok, tooOld, unknown }

    static func check(version: [Int]?) -> VersionCheck {
        guard let version else { return .unknown }
        return version.lexicographicallyPrecedes(minimumVersion) ? .tooOld : .ok
    }

    enum AuthResult: Equatable, Sendable {
        case signedIn(authMethod: String?)
        case signedOut
        case unknown
    }

    /// `claude auth status`: exit 0 signed in, 1 signed out. Only `authMethod` is read. `none` is signed out
    /// whatever the exit status says. `exit` is nil when the program could not be run.
    static func parseAuth(exit: Int32?, stdout: String) -> AuthResult {
        guard let exit else { return .unknown }
        var method: String?
        if let data = stdout.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            method = json["authMethod"] as? String
        }
        if exit == 1 || method == "none" { return .signedOut }
        return exit == 0 ? .signedIn(authMethod: method) : .unknown
    }

    // MARK: The checks that start processes

    /// Where the program is on this Mac, asking the login shell last.
    static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) async -> String? {
        #if DEBUG
        // Debug builds only: `NM_CLAUDE_CODE_PATH_OVERRIDE=…/fake_claude.py` runs a chat against the fake claude. Compiled out
        // of Release builds (scripts/check-app-binary.sh proves it), so a shipped app can't be pointed at another program.
        if let path = environment["NM_CLAUDE_CODE_PATH_OVERRIDE"], !path.isEmpty { return path }
        #endif
        let home = NSHomeDirectory()
        let isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) && !isDirectory($0) }
        if let hit = candidates(home: home, environment: environment).first(where: isExecutable) { return hit }
        let shell = environment["SHELL"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/bin/zsh"
        // -l: the user's PATH is set up in their profile; a Finder-launched app has almost none of it.
        let printed = await ClaudeCodeCLI.run(shell, ["-l", "-c", "command -v claude"], environment: environment, timeout: 5)
        return find(home: home, environment: environment, isExecutable: isExecutable, loginShell: { printed.output }).path
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Where it is, its version and whether it is signed in. Both questions are asked in the run's own environment
    /// (without what would outrank the plan login), so the answer is what a chat would get.
    static func status(environment: [String: String] = ProcessInfo.processInfo.environment) async -> ClaudeCodeStatus {
        guard let exe = await locate(environment: environment) else { return .notInstalled }
        return await statusOf(executable: exe, environment: environment)
    }

    /// The same for a program that is already known.
    static func statusOf(executable exe: String, environment: [String: String]) async -> ClaudeCodeStatus {
        let clean = ClaudeCodeCommand.environment(from: environment, platform: .current)
        async let versionRun = ClaudeCodeCLI.run(exe, ["--version"], environment: clean, timeout: 5)
        async let authRun = ClaudeCodeCLI.run(exe, ["auth", "status"], environment: clean, timeout: 10)
        let (versionOut, authOut) = await (versionRun, authRun)
        guard let version = parseVersion(versionOut.output) else { return ClaudeCodeStatus(state: .notInstalled) }
        let shown = version.map(String.init).joined(separator: ".")
        var status = ClaudeCodeStatus(state: .unknown, executable: exe, version: shown)
        if check(version: version) == .tooOld { status.state = .tooOld; return status }
        switch parseAuth(exit: authOut.status, stdout: authOut.output) {
        case .signedIn(let method): status.state = .signedIn; status.authMethod = method
        case .signedOut: status.state = .signedOut
        case .unknown: status.state = .unknown
        }
        return status
    }
}

/// Runs a short program and returns its output, or a `nil` status when it could not be run or took too long.
/// The output is only ever parsed, never logged.
enum ClaudeCodeCLI {
    private final class Job: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var expired = false
        var timedOut: Bool { lock.withLock { expired } }
        func expire() { lock.withLock { expired = true }; if process.isRunning { process.terminate() } }
    }

    static func run(_ executable: String, _ arguments: [String], environment: [String: String],
                    timeout: TimeInterval) async -> (status: Int32?, output: String) {
        await withCheckedContinuation { (done: CheckedContinuation<(status: Int32?, output: String), Never>) in
            DispatchQueue.global().async {
                let job = Job()
                job.process.executableURL = URL(fileURLWithPath: executable)
                job.process.arguments = arguments
                job.process.environment = environment
                let out = Pipe()
                job.process.standardOutput = out
                job.process.standardError = FileHandle.nullDevice
                job.process.standardInput = FileHandle.nullDevice
                guard (try? job.process.run()) != nil else { return done.resume(returning: (nil, "")) }
                let timer = DispatchWorkItem { job.expire() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                job.process.waitUntilExit()
                timer.cancel()
                done.resume(returning: (job.timedOut ? nil : job.process.terminationStatus,
                                        String(decoding: data.prefix(65_536), as: UTF8.self)))
            }
        }
    }
}

/// The script Terminal runs for "Sign in": `claude auth login`, in Anthropic's own flow. NotchMeow never sees what
/// is typed or opened there.
enum ClaudeCodeSignIn {
    /// Single-quoted for any shell, whatever the path holds (spaces, quotes, accents).
    static func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func script(executable: String) -> String {
        """
        #!/bin/zsh
        clear
        echo "Signing in. Your browser opens to finish."
        \(quoted(executable)) auth login
        echo
        echo "You can close this window and go back to NotchMeow."
        """ + "\n"
    }

    /// Writes the script as an executable `.command` file, which Terminal opens and runs. Returns its path.
    static func write(executable: String, into folder: String) -> String? {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let path = folder + "/claude-sign-in.command"
        guard (try? script(executable: executable).write(toFile: path, atomically: true, encoding: .utf8)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }
}

#endif
```

- [ ] **Step 4: Run the Claude Code tests**

Run: `bash scripts/test-claude-code.sh`
Expected: PASS, four test programs and no `✗`.

```text
== ClaudeCodeEngineTests
All tests passed.
== ClaudeCodeLocatorTests
All tests passed.
== ClaudeCodeParserTests
All tests passed.
== ClaudeCodeProviderTests
All tests passed.
```

- [ ] **Step 5: Build the app, register the file and commit**

Run: `(cd NotchBuddy && xcodegen --quiet && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

```bash
git add NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj NotchBuddy/Sources/App/AI/Core/ClaudeCodeLocator.swift tests/ClaudeCodeLocatorTests.swift
git commit -q -m "feat(claude-code): finding Claude Code, its version and sign-in status, and the sign-in script" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 8: Mac: a chat's session, hook routing, the chips and the words

**Agent:** `nm-implementer`. Three small pure files and one test program; nothing here starts a process or touches a window.

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/ClaudeChatSession.swift`, `ClaudeHookRouting.swift`, `ClaudeCodeText.swift`
- Create: `tests/ClaudeCodeSessionTests.swift`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (generated)

**Interfaces:**
- Consumes: `ClaudeCodeLevel`, `ClaudeCodeTurn`, `ClaudeCodeModel` (Tasks 3 and 4); `EngineReport.Payer`, `ClaudeCodeError`, `AIError.resetsAt` (Task 5); the fixtures `hook-routing.json`, `labels.json`, `copy.json` (Task 2).
- Produces (all `#if !APPSTORE`):

  ```swift
  struct ClaudeChatSession: Sendable, Equatable {
      struct Plan: Sendable, Equatable { var turn: ClaudeCodeTurn; var needsRecap: Bool; var retired: String? }
      private(set) var sessionID: String; private(set) var started: Bool; private(set) var startedIn: String?
      var level: ClaudeCodeLevel = .chatOnly; var model: ClaudeCodeModel = .sonnet
      static func newID() -> String                                  // a lower-case UUID
      init(sessionID: String = Self.newID())
      mutating func plan(chatFolder: String, platform: ClaudeCodePlatform = .current, newID: () -> String = Self.newID) -> Plan
      mutating func confirmStarted(in folder: String)               // Claude Code reported the session: the next turn resumes it
      mutating func reset(newID: () -> String = Self.newID) -> String   // a new conversation: returns the retired id, starts at Chat only
  }
  enum ClaudeCodeRecap { static func text(turns: [(role: ChatRequest.Role, text: String)]) -> String? }
  enum ClaudeAgentReadiness: Equatable { case ready, needsHooks; static func check(hooksInstalled: Bool) -> ClaudeAgentReadiness; static let hooksNote: String }
  enum ClaudeHookRouting { enum Route: Equatable { case chat(sessionID: String), other }; static func route(payload: [String: Any], live: Set<String>) -> Route }
  enum ClaudeCodeText {
      struct Note: Equatable { enum Action: String { case installGuide, signIn, updateGuide, retry, gitGuide }; var text: String; var action: Action? }
      static func modelChip(authMethod: String?, paidBy: EngineReport.Payer?) -> String
      static func levelChip(_ level: ClaudeCodeLevel) -> String
      static func folderName(_ path: String) -> String
      static func message(for error: AIError, timeZone: TimeZone = .current, locale: Locale = .current) -> Note?
  }
  ```

  The rules behind them. **A session lives under its working folder**, because Claude Code keeps it there: a level change that keeps the folder (Read-only to Agent in the same folder) resumes the same session with the new flags; one that moves it (Agent in a project, then Chat only, which runs in NotchMeow's own empty folder) starts a new session with a text recap of the chat and retires the old id. **Routing is by exact `session_id`**: only a string id that is one of the live chats' own counts, and a payload with `nm_agent` (Gemini, Antigravity, Codex) never does, so the user's own sessions keep their pills and cards. **The model chip never claims "your plan" without being told**: what the last run reported wins; before any run the sign-in method decides; `third_party` and anything unknown say just "Claude". The recap keeps the last 20 turns, each cut to 1,500 characters and the whole to 20,000, oldest first out, words only. `message(for:)` returns the note and its one button for each of Claude Code's failure codes (an `AIError` with no such code gives `nil`, so `AIMessages` decides as before); a plan limit says when it resets, in the viewer's time zone and locale ("3:45 pm", "15:45").

- [ ] **Step 1: Write the failing test**

It covers the session across level changes (Review Focus 1 and 3), the recap, `ClaudeAgentReadiness` (Review Focus 9), every case of `hook-routing.json` (Review Focus 4), the two chips from `labels.json` (Review Focus 5), and the notes from `copy.json` in two locales.

**Create `tests/ClaudeCodeSessionTests.swift`** with exactly this content:

```swift
import Foundation

@main
@MainActor
enum ClaudeCodeSessionTests {
    static func main() {
        sessions()
        recap()
        readiness()
        hookRouting()
        chips()
        notes()
        T.finish()
    }

    /// Mixed values compared as text.
    static func said(_ values: Any...) -> [String] { values.map { "\($0)" } }

    // MARK: - A chat's session

    static func sessions() {
        T.section("A chat's session")
        var ids = ["id-1", "id-2", "id-3"].makeIterator()
        func next() -> String { ids.next()! }
        var chat = ClaudeChatSession(sessionID: next())
        let chatFolder = "/support/NotchMeow/claude-chat"

        let first = chat.plan(chatFolder: chatFolder, newID: next)
        T.check("a new chat starts at Chat only, on a fresh session", said(first.turn.level == .chatOnly, first.turn.resume, first.needsRecap), said(true, false, false))
        T.check("with the id NotchMeow chose", first.turn.sessionID, "id-1")

        var again = chat
        T.check("a turn that never reached init is planned the same way", again.plan(chatFolder: chatFolder, newID: next).turn.resume, false)

        chat.confirmStarted(in: chatFolder)
        T.check("after init the next turn resumes", chat.plan(chatFolder: chatFolder, newID: next).turn.resume, true)

        chat.level = .readOnly(folder: "/Users/zoe/Projects/notchmeow")
        let moved = chat.plan(chatFolder: chatFolder, newID: next)
        T.check("a level change that moves the working folder starts a new session", said(moved.turn.sessionID, moved.turn.resume, moved.needsRecap), said("id-2", false, true))
        T.check("and retires the old one", moved.retired, "id-1")
        chat.confirmStarted(in: "/Users/zoe/Projects/notchmeow")

        chat.level = .agent(folder: "/Users/zoe/Projects/notchmeow")
        let kept = chat.plan(chatFolder: chatFolder, newID: next)
        T.check("Read-only to Agent in the same folder resumes the session, with the new flags",
                said(kept.turn.sessionID, kept.turn.resume, kept.needsRecap, kept.retired == nil), said("id-2", true, false, true))
        T.check("and the level is the new one", kept.turn.level, .agent(folder: "/Users/zoe/Projects/notchmeow"))

        chat.level = .chatOnly
        let back = chat.plan(chatFolder: chatFolder, newID: next)
        T.check("Agent back to Chat only moves it again: a new session and a recap", said(back.turn.sessionID, back.needsRecap, back.retired ?? "-"), said("id-3", true, "id-2"))

        var reset = chat
        let gone = reset.reset(newID: { "id-9" })
        T.check("a new conversation retires the id and starts clean", said(gone, reset.sessionID, reset.started, reset.level == .chatOnly), said("id-3", "id-9", false, true))
        let real = ClaudeChatSession.newID()
        T.check("a real id is a lower-case UUID", real == real.lowercased() && UUID(uuidString: real) != nil, true)
    }

    // MARK: - The recap

    static func recap() {
        T.section("The recap of a chat")
        T.check("nothing to recall", ClaudeCodeRecap.text(turns: []) == nil, true)
        let text = ClaudeCodeRecap.text(turns: [(.user, "What is in main.swift?"), (.assistant, "A greeting."), (.user, "  "), (.user, "Thanks")])!
        T.check("the words, in order, with who said them",
                text.components(separatedBy: "\n").dropFirst().map { $0 }, ["User: What is in main.swift?", "Assistant: A greeting.", "User: Thanks"])
        let long = String(repeating: "x", count: 5000)
        let cut = ClaudeCodeRecap.text(turns: [(.user, long)])!
        T.check("a long turn is cut", cut.count < 1700, true)
        let many = (0..<60).map { (ChatRequest.Role.user, "message \($0) " + String(repeating: "y", count: 1200)) }
        let recent = ClaudeCodeRecap.text(turns: many)!
        T.check("only the most recent turns, within the budget", recent.count <= ClaudeCodeRecap.maxChars + 200 && recent.contains("message 59") && !recent.contains("message 0 "), true)
    }

    // MARK: - Agent needs the hooks

    static func readiness() {
        T.section("Agent needs NotchMeow's hooks")
        T.check("with them", ClaudeAgentReadiness.check(hooksInstalled: true), .ready)
        T.check("without them", ClaudeAgentReadiness.check(hooksInstalled: false), .needsHooks)
        T.checkTrue("the note says what to do", ClaudeAgentReadiness.hooksNote.contains("Settings"))
    }

    // MARK: - hook-routing.json

    static func hookRouting() {
        T.section("Which hook payloads belong to a chat (hook-routing.json)")
        let data = T.fixture("claude-code/hook-routing.json")
        let live = Set(data["live"] as! [String])
        for c in data["cases"] as! [[String: Any]] {
            let route = ClaudeHookRouting.route(payload: c["payload"] as! [String: Any], live: (c["live"] as? [String]).map(Set.init) ?? live)
            let expect = c["expect"] as! String
            T.check(c["name"] as! String, route == .other ? "other" : "chat", expect)
        }
        let payload = ["hook_event_name": "PermissionRequest", "session_id": "chat-1", "tool_name": "Bash"] as [String: Any]
        T.check("the route names the chat it goes to", ClaudeHookRouting.route(payload: payload, live: ["chat-1"]), .chat(sessionID: "chat-1"))
    }

    // MARK: - labels.json

    static func chips() {
        T.section("The chips (labels.json)")
        let data = T.fixture("claude-code/labels.json")
        for c in data["modelChip"] as! [[String: Any]] {
            let paid = (c["paidBy"] as? String).flatMap(EngineReport.Payer.init(rawValue:))
            T.check(c["name"] as! String, ClaudeCodeText.modelChip(authMethod: c["authMethod"] as? String, paidBy: paid), c["expect"] as! String)
        }
        for c in data["levelChip"] as! [[String: Any]] {
            let folder = c["folder"] as? String ?? ""
            let level: ClaudeCodeLevel = switch c["level"] as! String { case "read": .readOnly(folder: folder); case "agent": .agent(folder: folder); default: .chatOnly }
            T.check("\(c["level"] as! String) \(folder)", ClaudeCodeText.levelChip(level), c["expect"] as! String)
        }
    }

    // MARK: - copy.json

    static func notes() {
        T.section("What the chat says (copy.json)")
        let data = T.fixture("claude-code/copy.json")
        for c in data["cases"] as! [[String: Any]] {
            let resets = (c["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let error = AIError(kind: AIErrorKind(rawValue: c["kind"] as! String)!, code: c["code"] as? String, resetsAt: resets)
            let note = ClaudeCodeText.message(for: error, timeZone: TimeZone(identifier: c["timeZone"] as? String ?? "UTC")!,
                                              locale: Locale(identifier: c["locale"] as? String ?? "en_US"))
            T.check("\(c["code"] as! String) \(c["locale"] as? String ?? "")", note?.text, c["text"] as? String)
            T.check("\(c["code"] as! String): the one button", note?.action?.rawValue, c["action"] as? String)
        }
        T.check("any other error is left to AIMessages", ClaudeCodeText.message(for: AIError(kind: .server)) == nil, true)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-claude-code.sh`
Expected: FAIL, a compile error in `tests/ClaudeCodeSessionTests.swift`: `ClaudeChatSession` does not exist.

```text
tests/ClaudeCodeSessionTests.swift:25:20: error: cannot find 'ClaudeChatSession' in scope
tests/ClaudeCodeSessionTests.swift:29:97: error: cannot infer contextual base in reference to member 'chatOnly'
tests/ClaudeCodeSessionTests.swift:38:23: error: cannot infer contextual base in reference to member 'readOnly'
```

- [ ] **Step 3: Write the three files**

**Create `NotchBuddy/Sources/App/AI/Core/ClaudeChatSession.swift`** with exactly this content:

```swift
import Foundation

// One chat's Claude Code session: its id, whether it has started, the level and model the chat is at, and what a
// level change means. Pure: `ClaudeService` holds one per conversation and asks it for each turn.

#if !APPSTORE

struct ClaudeChatSession: Sendable, Equatable {
    /// What the next turn is: the run to make, whether it needs a recap of the chat so far, and the id that is
    /// retired because the session could not be continued.
    struct Plan: Sendable, Equatable {
        var turn: ClaudeCodeTurn
        var needsRecap: Bool
        var retired: String?
    }

    private(set) var sessionID: String
    /// Claude Code has created the session (it said so in `system/init`): later turns resume it.
    private(set) var started = false
    /// Claude Code keeps a session under the folder it ran in, so it can only be resumed from there.
    private(set) var startedIn: String?
    var level: ClaudeCodeLevel = .chatOnly
    var model: ClaudeCodeModel = .sonnet

    static func newID() -> String { UUID().uuidString.lowercased() }

    init(sessionID: String = Self.newID()) { self.sessionID = sessionID }

    /// The next turn. A level change that keeps the working folder resumes the same session with the new flags.
    /// One that moves it (Agent in a project, then Chat only) starts a new session, to be seeded with a recap, and
    /// retires the old id: Claude Code could not find the old session from the new folder, and a late approval
    /// request from it must be refused.
    mutating func plan(chatFolder: String, platform: ClaudeCodePlatform = .current,
                       newID: () -> String = Self.newID) -> Plan {
        let folder = level.folder ?? chatFolder
        var retired: String?
        var recap = false
        if started, startedIn != folder {
            retired = sessionID
            sessionID = newID()
            started = false
            startedIn = nil
            recap = true
        }
        let turn = ClaudeCodeTurn(level: level, model: model, sessionID: sessionID, resume: started, platform: platform)
        return Plan(turn: turn, needsRecap: recap, retired: retired)
    }

    /// Claude Code reported the session: the next turn resumes it.
    mutating func confirmStarted(in folder: String) {
        started = true
        startedIn = folder
    }

    /// A new conversation: the old id is returned so it can be retired, and nothing of it is kept.
    mutating func reset(newID: () -> String = Self.newID) -> String {
        let old = sessionID
        self = ClaudeChatSession(sessionID: newID())
        return old
    }
}

/// A recap of the chat so far, for a session started afresh in the middle of it.
enum ClaudeCodeRecap {
    static let maxTurns = 20
    static let maxTurnChars = 1_500
    static let maxChars = 20_000

    /// nil when there is nothing to recall. Oldest turns go first when the recap is too long. Only the words are
    /// kept (no file bodies).
    static func text(turns: [(role: ChatRequest.Role, text: String)]) -> String? {
        var lines: [String] = []
        for turn in turns.suffix(maxTurns) {
            let words = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if words.isEmpty { continue }
            let cut = words.count > maxTurnChars ? String(words.prefix(maxTurnChars)) + "…" : words
            lines.append((turn.role == .user ? "User: " : "Assistant: ") + cut)
        }
        while lines.joined(separator: "\n").count > maxChars, lines.count > 1 { lines.removeFirst() }
        guard !lines.isEmpty else { return nil }
        return "Earlier in this chat, for context only (it is already answered):\n" + lines.joined(separator: "\n")
    }
}

/// Agent mode asks for every step through NotchMeow's hooks. Without them Claude Code refuses every step.
enum ClaudeAgentReadiness: Equatable {
    case ready
    case needsHooks

    static func check(hooksInstalled: Bool) -> ClaudeAgentReadiness { hooksInstalled ? .ready : .needsHooks }

    static let hooksNote = "Agent needs NotchMeow's hooks in Claude Code, or every step is refused. Install them in Settings."
}

#endif
```

**Create `NotchBuddy/Sources/App/AI/Core/ClaudeHookRouting.swift`** with exactly this content:

```swift
import Foundation

// Which hook payloads belong to a chat. `PermissionRequest` carries the `session_id` Claude Code was started with;
// NotchMeow chose that id (`--session-id`), so a match is a chat's own run. Everything else is handled as before:
// the user's own sessions keep reaching their own pills and cards. No `nm_*` field is involved.
// Rules: `tests/fixtures/ai/claude-code/hook-routing.json`.

#if !APPSTORE

enum ClaudeHookRouting {
    enum Route: Equatable {
        case chat(sessionID: String)
        case other
    }

    /// `live`: the ids of the chats that are open. Only an exact match of a string `session_id` counts, and a payload
    /// from another agent (`nm_agent`) never does.
    static func route(payload: [String: Any], live: Set<String>) -> Route {
        if let agent = payload["nm_agent"] as? String, !agent.isEmpty { return .other }
        guard let id = payload["session_id"] as? String, !id.isEmpty, live.contains(id) else { return .other }
        return .chat(sessionID: id)
    }
}

#endif
```

**Create `NotchBuddy/Sources/App/AI/Core/ClaudeCodeText.swift`** with exactly this content:

```swift
import Foundation

// The words on the two chips and what the chat says for each Claude Code failure.
// Fixtures: `tests/fixtures/ai/claude-code/labels.json` and `copy.json`.

#if !APPSTORE

enum ClaudeCodeText {
    /// The note for a failure, with its one button. The button's names are `copy.json`'s; the app maps them to its own actions.
    struct Note: Equatable {
        enum Action: String, Equatable { case installGuide, signIn, updateGuide, retry, gitGuide }
        var text: String
        var action: Action?
    }

    // MARK: Chips

    /// Who pays, as Claude Code says it. What the last run reported wins; before any run, the sign-in method.
    /// A cloud account (Bedrock, Vertex) is neither, and an unknown answer never claims "your plan".
    static func modelChip(authMethod: String?, paidBy: EngineReport.Payer?) -> String {
        if authMethod == "third_party" { return "Claude" }
        switch paidBy {
        case .plan: return "Claude · your plan"
        case .apiKey: return "Claude · API key"
        default: break
        }
        switch authMethod {
        case "claude.ai", "oauth_token": return "Claude · your plan"
        case "api_key", "api_key_helper": return "Claude · API key"
        default: return "Claude"
        }
    }

    /// "Chat only", "Read-only · notchmeow", "Agent · Mis Proyectos".
    static func levelChip(_ level: ClaudeCodeLevel) -> String {
        let words: String
        switch level {
        case .chatOnly: return "Chat only"
        case .readOnly: words = "Read-only"
        case .agent: words = "Agent"
        }
        guard let folder = level.folder, !folder.isEmpty else { return words }
        return "\(words) · \(folderName(folder))"
    }

    /// The last part of a path, whichever separator it uses; "/" and "C:" keep their own names.
    static func folderName(_ path: String) -> String {
        var trimmed = path
        while trimmed.hasSuffix("/") || trimmed.hasSuffix("\\") { trimmed.removeLast() }
        if trimmed.isEmpty { return String(path.prefix(1)) }
        return trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? trimmed
    }

    // MARK: Failures

    /// The note for one of Claude Code's failures, or nil for any other error (`AIMessages` then decides).
    static func message(for error: AIError, timeZone: TimeZone = .current, locale: Locale = .current) -> Note? {
        switch error.code {
        case ClaudeCodeError.missing: return Note(text: "Claude Code isn't installed.", action: .installGuide)
        case ClaudeCodeError.signedOut: return Note(text: "Claude Code is signed out.", action: .signIn)
        case ClaudeCodeError.planLimit:
            return Note(text: planLimit(resetsAt: error.resetsAt, timeZone: timeZone, locale: locale), action: nil)
        case ClaudeCodeError.tooOld: return Note(text: "Update Claude Code.", action: .updateGuide)
        case ClaudeCodeError.crashed: return Note(text: "Claude stopped unexpectedly.", action: .retry)
        case ClaudeCodeError.offline: return Note(text: "Couldn't reach Claude.", action: nil)
        case ClaudeCodeError.needsGit: return Note(text: "Claude Code needs Git for Windows.", action: .gitGuide)
        case ClaudeCodeError.folderMissing:
            return Note(text: "That folder isn't there any more. Pick another one.", action: nil)
        default: return nil
        }
    }

    /// "Your Claude plan's limit resets at 3:45 pm." in the viewer's time zone and locale.
    static func planLimit(resetsAt: Date?, timeZone: TimeZone, locale: Locale) -> String {
        guard let resetsAt else { return "Your Claude plan's limit was reached." }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        // Recent macOS puts a narrow no-break space before PM: use a plain one, and lower-case "PM".
        let time = formatter.string(from: resetsAt).replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ").lowercased()
        return "Your Claude plan's limit resets at \(time)."
    }
}

#endif
```

- [ ] **Step 4: Run the Claude Code tests**

Run: `bash scripts/test-claude-code.sh`
Expected: PASS, five test programs and no `✗`.

```text
== ClaudeCodeEngineTests
All tests passed.
== ClaudeCodeLocatorTests
All tests passed.
== ClaudeCodeParserTests
All tests passed.
== ClaudeCodeProviderTests
All tests passed.
== ClaudeCodeSessionTests
All tests passed.
```

- [ ] **Step 5: Build the app, register the files and commit**

Run: `(cd NotchBuddy && xcodegen --quiet && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

```bash
git add NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj NotchBuddy/Sources/App/AI/Core/ClaudeChatSession.swift NotchBuddy/Sources/App/AI/Core/ClaudeHookRouting.swift NotchBuddy/Sources/App/AI/Core/ClaudeCodeText.swift tests/ClaudeCodeSessionTests.swift
git commit -q -m "feat(claude-code): a chat's session, hook routing by session id, the chips and the words" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 9: Mac: approvals waiting in a chat, and the step words move out of `HookServer`

**Agent:** `nm-implementer`. One pure file for the approvals, and a move of existing code that must not change a word of what the session view shows.

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/ClaudeChatApproval.swift`, `NotchBuddy/Sources/App/SessionStepText.swift`
- Create: `tests/ClaudeCodeApprovalTests.swift`, `tests/SessionStepTextTests.swift`, `scripts/test-session-steps.sh`
- Modify: `NotchBuddy/Sources/App/HookServer.swift` (`frenchStep` delegates; its body and `oneLine` move out unchanged)
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (generated)

**Interfaces:**
- Consumes: `ClaudeAgentReadiness` (Task 8).
- Produces:

  ```swift
  enum SessionStepText { static func line(tool: String, input: [String: Any]) -> String }   // "Lit · README.md", "Exécute · npm test": the session view's words, unchanged
  // #if !APPSTORE
  struct ChatApproval: Sendable, Equatable, Identifiable { let id: UUID; var sessionID: String; var tool: String; var target: String }
  enum ChatApprovalText { static let fields: [String]; static func target(tool: String, input: [String: Any]) -> String }   // "Bash · npm test"; a Write's content is never on the card
  struct ChatApprovalQueue<Token: Sendable>: Sendable {
      struct Entry: Sendable { var approval: ChatApproval; var token: Token }
      var front: ChatApproval? { get }; var isEmpty: Bool { get }
      mutating func push(_ approval: ChatApproval, token: Token)
      mutating func popFront() -> Entry?                         // answered
      mutating func remove(id: UUID) -> Entry?                   // its connection closed, or it timed out
      mutating func removeAll(session: String? = nil) -> [Entry] // one session's, or all: Stop, a new conversation, a retired session
  }
  extension ClaudeAgentReadiness { static func hooksInstalled(in settings: [String: Any]) -> Bool }   // is NotchMeow's PermissionRequest hook in Claude Code's settings
  ```

  Requests wait in arrival order (parallel tool calls ask together) and the card shows the first. `Token` is whatever the caller needs to answer one: Task 10 puts the hook's connection in it. The chat's step rows (Task 11) use `SessionStepText` so they read exactly as the session view's do; moving the words out of `HookServer` and not copying them keeps one set of words.

- [ ] **Step 1: Write the failing tests**

`SessionStepTextTests` pins what the session view has always said (written from the old code's behaviour, including the Bash verbs, the 60-character cut and Codex's tools); `ClaudeCodeApprovalTests` covers the card's words, the queue, and the hooks check. The queue's `removeAll(session:)` is Review Focus 1 (a retired session's waiting approvals are handed back) and `hooksInstalled(in:)` is Review Focus 9.

**Create `tests/SessionStepTextTests.swift`** with exactly this content:

```swift
import Foundation

// The step rows' words, as the session view has always shown them. They were moved out of HookServer unchanged:
// these cases are what they said before.

@main
enum SessionStepTextTests {
    nonisolated(unsafe) static var failures = 0

    static func check(_ label: String, _ got: String, _ expected: String) {
        if got == expected { print("  ✓ \(label)") } else { print("  ✗ \(label)\n    got:      \(got)\n    expected: \(expected)"); failures += 1 }
    }

    static func main() {
        let step = SessionStepText.line
        check("Bash infers a verb: reading", step("Bash", ["command": "cat a.txt"]), "Lit · cat a.txt")
        check("Bash infers a verb: searching", step("Bash", ["command": "ls -la src"]), "Cherche · ls -la src")
        check("Bash infers a verb: testing", step("Bash", ["command": "npm test -- --watch"]), "Teste · npm test -- --watch")
        check("Bash otherwise runs", step("Bash", ["command": "echo hi"]), "Exécute · echo hi")
        check("a multi-line command is one line", step("Bash", ["command": "a\nb\tc"]), "Exécute · a b c")
        check("a long command is cut at 60", step("Bash", ["command": String(repeating: "x", count: 70)]), "Exécute · " + String(repeating: "x", count: 60) + "…")
        check("Read shows the file's name", step("Read", ["file_path": "/work/README.md"]), "Lit · README.md")
        check("Edit", step("Edit", ["file_path": "/work/a/b.swift"]), "Modifie · b.swift")
        check("a path field works too", step("LS", ["path": "/work/src"]), "Liste · src")
        check("a query", step("WebSearch", ["query": "swift concurrency"]), "Recherche web · swift concurrency")
        check("a tool with nothing to show is its label", step("Glob", ["pattern": "*.swift"]), "Cherche")
        check("an unknown tool keeps its name", step("Frobnicate", [:]), "Frobnicate")
        check("an MCP tool is server · tool", step("mcp__github__create_issue", [:]), "github · create_issue")
        check("a patch shows its first file", step("apply_patch", ["command": "*** Begin Patch\n*** Update File: src/foo.txt\n@@"]), "Modifie · foo.txt")
        check("a Codex plan", step("update_plan", [:]), "Tâches")
        if failures == 0 { print("\nAll tests passed."); exit(0) }
        print("\n\(failures) test(s) failed."); exit(1)
    }
}
```

**Create `scripts/test-session-steps.sh`** with exactly this content:

```bash
#!/usr/bin/env bash
# The words of the session view's step rows (moved out of HookServer, unchanged).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-session-steps.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/SessionStepText.swift tests/SessionStepTextTests.swift -o "$TEST_DIR/session-step-tests"
"$TEST_DIR/session-step-tests"
```

Run: `chmod +x scripts/test-session-steps.sh`

**Create `tests/ClaudeCodeApprovalTests.swift`** with exactly this content:

```swift
import Foundation

@main
@MainActor
enum ClaudeCodeApprovalTests {
    static func main() {
        text()
        queue()
        hooks()
        T.finish()
    }

    static func text() {
        T.section("What the card says")
        T.check("a command", ChatApprovalText.target(tool: "Bash", input: ["command": " npm test "]), "Bash · npm test")
        T.check("a file", ChatApprovalText.target(tool: "Write", input: ["file_path": "/work/.env", "content": "SECRET"]), "Write · /work/.env")
        T.check("a path", ChatApprovalText.target(tool: "Read", input: ["path": "/etc/hosts"]), "Read · /etc/hosts")
        T.check("a URL", ChatApprovalText.target(tool: "WebFetch", input: ["url": "https://example.com"]), "WebFetch · https://example.com")
        T.check("an unfamiliar tool with nothing to show is its name", ChatApprovalText.target(tool: "Frob", input: ["x": 1]), "Frob")
        T.check("a blank field is skipped", ChatApprovalText.target(tool: "Grep", input: ["command": "  ", "pattern": "TODO"]), "Grep · TODO")
        T.checkTrue("the content of a Write is never on the card", !ChatApprovalText.target(tool: "Write", input: ["file_path": "a", "content": "SECRET"]).contains("SECRET"))
    }

    static func queue() {
        T.section("Requests waiting for a click")
        func approval(_ session: String, _ tool: String) -> ChatApproval { ChatApproval(id: UUID(), sessionID: session, tool: tool, target: tool) }
        var q = ChatApprovalQueue<Int>()
        T.check("empty", q.front == nil, true)
        let a = approval("s1", "Bash"), b = approval("s1", "Edit"), c = approval("s2", "Write")
        q.push(a, token: 1); q.push(b, token: 2); q.push(c, token: 3)
        T.check("the first to arrive is shown", q.front?.tool, "Bash")
        T.check("answering takes the first", q.popFront()?.token, 1)
        T.check("and shows the next", q.front?.tool, "Edit")
        T.check("a connection that closed leaves only itself", q.remove(id: c.id)?.token, 3)
        T.check("and an unknown id is nothing", q.remove(id: UUID()) == nil, true)
        q.push(c, token: 3)
        T.check("one session's requests go together", q.removeAll(session: "s1").map(\.token), [2])
        T.check("the other session's stay", q.front?.sessionID, "s2")
        T.check("all of them", q.removeAll().map(\.token), [3])
        T.check("then it is empty", q.isEmpty, true)
    }

    static func hooks() {
        T.section("Are NotchMeow's hooks installed")
        func settings(_ command: String) -> [String: Any] {
            ["hooks": ["PermissionRequest": [["hooks": [["type": "command", "command": command, "timeout": 120]]]]]]
        }
        T.check("the hook NotchMeow installs", ClaudeAgentReadiness.hooksInstalled(in: settings("\"/Users/zoe/Library/Application Support/NotchMeow/nm-hook\"")), true)
        T.check("someone else's hook", ClaudeAgentReadiness.hooksInstalled(in: settings("/usr/local/bin/other")), false)
        T.check("no hooks at all", ClaudeAgentReadiness.hooksInstalled(in: [:]), false)
        T.check("hooks for other events only", ClaudeAgentReadiness.hooksInstalled(in: ["hooks": ["Stop": [["hooks": [["command": "nm-hook"]]]]]]), false)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-session-steps.sh`
Expected: FAIL, `error opening input file`: `SessionStepText.swift` is not there yet.

```text
<unknown>:0: error: error opening input file 'NotchBuddy/Sources/App/SessionStepText.swift' (No such file or directory)
```

Run: `bash scripts/test-claude-code.sh`
Expected: FAIL, a compile error in `tests/ClaudeCodeApprovalTests.swift`: `ChatApprovalText` does not exist.

```text
tests/ClaudeCodeApprovalTests.swift:15:30: error: cannot find 'ChatApprovalText' in scope
tests/ClaudeCodeApprovalTests.swift:16:27: error: cannot find 'ChatApprovalText' in scope
```

- [ ] **Step 3: Write the approvals, and move the step words**

**Create `NotchBuddy/Sources/App/AI/Core/ClaudeChatApproval.swift`** with exactly this content:

```swift
import Foundation

// What an approval inside a chat is made of: the card's words, the queue of requests waiting for a click, and whether
// NotchMeow's hooks are in Claude Code's settings (without them every Agent step is refused).

#if !APPSTORE

/// One step Claude Code is waiting to take, shown as a card in the chat.
struct ChatApproval: Sendable, Equatable, Identifiable {
    let id: UUID
    var sessionID: String
    var tool: String
    /// "Bash · npm test", "Write · /work/notes.txt": what Allow actually authorises.
    var target: String
}

enum ChatApprovalText {
    /// Ordered by how specific the field is, so an unfamiliar tool still shows whatever identifies its target.
    static let fields = ["command", "file_path", "path", "url", "query", "pattern", "prompt"]

    /// "Approving Write tells you nothing; approving `Write · /work/.env` tells you everything."
    static func target(tool: String, input: [String: Any]) -> String {
        for field in fields {
            if let value = (input[field] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return "\(tool) · \(value)"
            }
        }
        return tool
    }
}

/// Requests wait here in the order they arrived (parallel tool calls ask together); the card shows the first.
/// `Token` is whatever the caller needs to answer one (the hook's connection).
struct ChatApprovalQueue<Token: Sendable>: Sendable {
    struct Entry: Sendable {
        var approval: ChatApproval
        var token: Token
    }

    private(set) var entries: [Entry] = []

    var front: ChatApproval? { entries.first?.approval }
    var isEmpty: Bool { entries.isEmpty }

    mutating func push(_ approval: ChatApproval, token: Token) { entries.append(Entry(approval: approval, token: token)) }

    /// The first request, answered or given up on.
    mutating func popFront() -> Entry? { entries.isEmpty ? nil : entries.removeFirst() }

    /// One request by id (its connection closed, or it timed out).
    mutating func remove(id: UUID) -> Entry? {
        guard let i = entries.firstIndex(where: { $0.approval.id == id }) else { return nil }
        return entries.remove(at: i)
    }

    /// Every request of one chat session, or all of them (`nil`): Stop, a new conversation, a level change.
    mutating func removeAll(session: String? = nil) -> [Entry] {
        let gone = entries.filter { session == nil || $0.approval.sessionID == session }
        entries.removeAll { session == nil || $0.approval.sessionID == session }
        return gone
    }
}

extension ClaudeAgentReadiness {
    /// Whether Claude Code's settings carry a NotchMeow `PermissionRequest` hook (what `HookServer` installs).
    static func hooksInstalled(in settings: [String: Any]) -> Bool {
        guard let groups = (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] else { return false }
        return groups.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains {
                let command = $0["command"] as? String ?? ""
                return command.contains("nm-hook") || command.contains("NotchMeow") || command.contains("notchmeow")
            }
        }
    }
}

#endif
```

The words move to their own file; `HookServer.frenchStep` becomes one call, and `oneLine` (used only by those words) goes with them.

**Create `NotchBuddy/Sources/App/SessionStepText.swift`** with exactly this content:

```swift
import Foundation

/// The words of a session step row ("Lit · README.md", "Exécute · npm test"). They lived in `HookServer`; the chat's
/// step rows read the same way, so they live here, unchanged.
enum SessionStepText {
    // MARK: - French step labels

    static func line(tool: String, input: [String: Any]) -> String {
        let labels: [String: String] = [
            "Bash":        "Exécute",
            "Read":        "Lit",
            "Write":       "Écrit",
            "Edit":        "Modifie",
            "Glob":        "Cherche",
            "Grep":        "Recherche",
            "WebSearch":   "Recherche web",
            "WebFetch":    "Récupère",
            "TodoWrite":   "Tâches",
            "Task":        "Agent",
            "LS":          "Liste",
            "MultiEdit":   "Modifie",
            "NotebookEdit": "Notebook",
            // Codex tools
            "apply_patch": "Modifie",
            "update_plan": "Tâches",
            "spawn_agent": "Agent",
        ]
        var label = labels[tool] ?? tool

        // Codex MCP tools arrive as mcp__server__tool — show "server · tool"
        if tool.hasPrefix("mcp__") {
            let rest = String(tool.dropFirst(5))
            let parts = rest.components(separatedBy: "__")
            label = parts.count >= 2 ? "\(parts[0]) · \(parts.dropFirst().joined(separator: "__"))" : rest
        }

        // Bash: infer a more precise verb from the command
        if tool == "Bash", let cmd = input["command"] as? String {
            return "\(bashVerb(cmd)) · \(oneLine(cmd))"
        }

        // apply_patch: extract the first file name from the patch
        if tool == "apply_patch", let patch = input["command"] as? String {
            for line in patch.split(separator: "\n") {
                for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] {
                    if line.hasPrefix(prefix) {
                        let path = String(line.dropFirst(prefix.count))
                        return "\(label) · \(URL(fileURLWithPath: path).lastPathComponent)"
                    }
                }
            }
            return label
        }

        if let cmd = input["command"] as? String {
            return "\(label) · \(oneLine(cmd))"
        } else if let path = input["path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: path).lastPathComponent)"
        } else if let file = input["file_path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: file).lastPathComponent)"
        } else if let query = input["query"] as? String {
            return "\(label) · \(oneLine(query))"
        }
        return label
    }

    /// Infers a French verb from a shell command's first word.
    private static func bashVerb(_ command: String) -> String {
        let first = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        switch first {
        case "cat", "bat", "head", "tail", "less", "more", "nl": return "Lit"
        case "rg", "grep", "find", "fd", "ls", "tree", "wc":    return "Cherche"
        default: break
        }
        let testRunners = ["pytest", "vitest", "jest", "npm test", "npm run test",
                           "cargo test", "go test", "swift test", "make test",
                           "xcodebuild test", "unittest"]
        if testRunners.contains(where: { command.contains($0) }) { return "Teste" }
        return "Exécute"
    }

    /// Collapses whitespace so a multi-line command stays one ticker row.
    private static func oneLine(_ text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
                            .joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }
}
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift

    private func frenchStep(tool: String, input: [String: Any]) -> String {
        let labels: [String: String] = [
            "Bash":        "Exécute",
            "Read":        "Lit",
            "Write":       "Écrit",
            "Edit":        "Modifie",
            "Glob":        "Cherche",
            "Grep":        "Recherche",
            "WebSearch":   "Recherche web",
            "WebFetch":    "Récupère",
            "TodoWrite":   "Tâches",
            "Task":        "Agent",
            "LS":          "Liste",
            "MultiEdit":   "Modifie",
            "NotebookEdit": "Notebook",
            // Codex tools
            "apply_patch": "Modifie",
            "update_plan": "Tâches",
            "spawn_agent": "Agent",
        ]
        var label = labels[tool] ?? tool

        // Codex MCP tools arrive as mcp__server__tool — show "server · tool"
        if tool.hasPrefix("mcp__") {
            let rest = String(tool.dropFirst(5))
            let parts = rest.components(separatedBy: "__")
            label = parts.count >= 2 ? "\(parts[0]) · \(parts.dropFirst().joined(separator: "__"))" : rest
        }

        // Bash: infer a more precise verb from the command
        if tool == "Bash", let cmd = input["command"] as? String {
            return "\(bashVerb(cmd)) · \(oneLine(cmd))"
        }

        // apply_patch: extract the first file name from the patch
        if tool == "apply_patch", let patch = input["command"] as? String {
            for line in patch.split(separator: "\n") {
                for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] {
                    if line.hasPrefix(prefix) {
                        let path = String(line.dropFirst(prefix.count))
                        return "\(label) · \(URL(fileURLWithPath: path).lastPathComponent)"
                    }
                }
            }
            return label
        }

        if let cmd = input["command"] as? String {
            return "\(label) · \(oneLine(cmd))"
        } else if let path = input["path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: path).lastPathComponent)"
        } else if let file = input["file_path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: file).lastPathComponent)"
        } else if let query = input["query"] as? String {
            return "\(label) · \(oneLine(query))"
        }
        return label
    }

    /// Infers a French verb from a shell command's first word.
    private func bashVerb(_ command: String) -> String {
        let first = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        switch first {
        case "cat", "bat", "head", "tail", "less", "more", "nl": return "Lit"
        case "rg", "grep", "find", "fd", "ls", "tree", "wc":    return "Cherche"
        default: break
        }
        let testRunners = ["pytest", "vitest", "jest", "npm test", "npm run test",
                           "cargo test", "go test", "swift test", "make test",
                           "xcodebuild test", "unittest"]
        if testRunners.contains(where: { command.contains($0) }) { return "Teste" }
        return "Exécute"
    }

```

and replace it with:

```swift

    private func frenchStep(tool: String, input: [String: Any]) -> String {
        SessionStepText.line(tool: tool, input: input)
    }

```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// Collapses whitespace so a multi-line command stays one ticker row.
    private func oneLine(_ text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
                            .joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    // MARK: - Logging

```

and replace it with:

```swift
    }

    // MARK: - Logging

```

- [ ] **Step 4: Run both**

Run: `bash scripts/test-session-steps.sh`
Expected: PASS, `All tests passed.`

Run: `bash scripts/test-claude-code.sh`
Expected: PASS, six test programs and no `✗`.

```text
== ClaudeCodeApprovalTests
All tests passed.
== ClaudeCodeEngineTests
All tests passed.
== ClaudeCodeLocatorTests
All tests passed.
== ClaudeCodeParserTests
All tests passed.
== ClaudeCodeProviderTests
All tests passed.
== ClaudeCodeSessionTests
All tests passed.
```

- [ ] **Step 5: Build the app, register the files and commit**

The session view must still build and say the same things: the only caller of the words is `HookServer`.

Run: `(cd NotchBuddy && xcodegen --quiet && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

```bash
git add NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj NotchBuddy/Sources/App/AI/Core/ClaudeChatApproval.swift NotchBuddy/Sources/App/SessionStepText.swift NotchBuddy/Sources/App/HookServer.swift scripts/test-session-steps.sh tests/ClaudeCodeApprovalTests.swift tests/SessionStepTextTests.swift
git commit -q -m "feat(claude-code): the approvals waiting in a chat; the session view's step words move out of HookServer unchanged" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 10: Mac: the wiring (service, hook server, state, factory)

**Agent:** `nm-implementer-deep`. A hook server that must answer on a socket before Claude Code gives up, a chat service with generations, and SwiftUI state, in one app. No test program can run the app's windows, so the tests are the pure parts plus source pins (below); the builds are part of the task.

**Files:**
- Create: `NotchBuddy/Sources/App/ClaudeCodeActions.swift`, `tests/ClaudeCodeWiringTests.swift`
- Modify: `NotchBuddy/Sources/App/AI/Core/ClaudeChatSession.swift` (`ClaudeCodeSetup`), `ProviderFactory.swift`, `AIMessages.swift`
- Modify: `NotchBuddy/Sources/App/AI/AIService.swift`, `AppState.swift`, `ClaudeService.swift`, `HookServer.swift`, `IslandViewContent.swift`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (generated)

**Interfaces:**
- Consumes: everything from Tasks 3 to 9.
- Produces:
  - `struct ClaudeCodeSetup: Sendable, Equatable { var executable: String; var turn: ClaudeCodeTurn; var preamble: String? }`, and `ProviderFactory.claude: ClaudeCodeSetup?` (`make` returns a `ClaudeCodeProvider` for a `.claudeCode` target when it is set, an `UnavailableProvider` otherwise; `#if !APPSTORE`).
  - `AIAction` gains `signInClaude, installClaude, updateClaude, installGit, tryAgain`; `AIMessages.error` answers a `.claudeCode` target's failure with `ClaudeCodeText.message(for:)` and `AIMessages.action(for:)` maps its button; `AIMessages.shortName` says "Claude" for it.
  - `AppState` (`#if !APPSTORE`): `claudeCodeEnabled` (saved), `claudeCodeModel` (saved), `claudeCodeStatus: ClaudeCodeStatus`, `claudeRunReport: EngineReport?`, `claudeLevel: ClaudeCodeLevel` (this chat's, always `.chatOnly` for a new chat), `chatApproval: ChatApproval?`; `ChatMessage.steps: [ChatStep]`.
  - `AIService`: `cloudKeys` includes `.claudeCode` when `claudeCodeEnabled` and the last check found it signed in (that is what makes Auto choose it); `refreshClaudeStatus() async`, called when Settings opens and before a chat's first turn, never on a timer; `chip(_:)` says what Claude Code last reported; the target's label reads "Claude plan · Sonnet".
  - `ClaudeService`: one `ClaudeChatSession` per conversation, `liveClaudeSessions: Set<String>` (the ids `HookServer` routes by: only the current one), `resendLastMessage(state:)` ("Try again"); the turn's `ClaudeCodeSetup` (level, model, session, recap) goes into the factory; `.step` events update the reply's rows, `.engine` records who pays and confirms the session; a step that never finished ends as stopped (`ChatStep.endingUnfinished`); a plan limit shows the rate-limit cat.
  - `HookServer`: a chat's `PermissionRequest` becomes a card in that chat (`state.chatApproval`), never a pill and never touching the one pending approval of the user's own sessions; `sendChatApprovalDecision(_ decision: String)` answers `allow` or `deny` (no "Always"); `cancelChatApprovals()` hands every waiting request back as `ask`, which Claude Code treats as a refusal; a request left unanswered is dropped after 115 s (the hook waits 120); `static func claudeHooksInstalled() -> Bool` reads `~/.claude/settings.json`; `AskUserQuestion` from a chat's run is handed back (a question cannot be answered in a chat run) and every other event of a chat's run is not a session.
  - `ClaudeCodeActions.signIn()` (opens the `.command` file in Terminal; with no Claude Code to run, the install page) and `.openInstallGuide()`.

- [ ] **Step 1: Write the failing test**

Two sections for the pure parts (the factory builds the provider for a setup; the notes and their buttons), and one of source pins. The pins exist because no test program can run the app's windows: they check that `HookServer`'s three handlers ask the router before they look at a session (Review Focus 4: a chat never makes or touches a pill), and that a new conversation, Stop and a retired session each hand the waiting approvals back (Review Focus 1 and 2).

**Create `tests/ClaudeCodeWiringTests.swift`** with exactly this content:

```swift
import Foundation

// What the app wires together from the pure parts: the provider the factory makes, the words and buttons the chat shows
// for Claude Code's failures, and (as source pins, because no test program can run the app's windows) where a chat's
// approvals are routed and handed back.

@main
@MainActor
enum ClaudeCodeWiringTests {
    static func main() {
        factory()
        messages()
        pins()
        T.finish()
    }

    static func factory() {
        T.section("The provider factory")
        let target = ChatTarget(provider: .claudeCode, model: "sonnet", placement: .cloud)
        var factory = ProviderFactory()
        T.check("without a setup there is no engine", factory.make(target) is UnavailableProvider, true)
        factory.claude = ClaudeCodeSetup(executable: "/x/claude", turn: ClaudeCodeTurn(level: .chatOnly, sessionID: "s", resume: false), preamble: "recap")
        let provider = factory.make(target) as? ClaudeCodeProvider
        T.check("with one it is Claude Code, on that turn", [provider?.executable, provider?.turn.sessionID, provider?.preamble], ["/x/claude", "s", "recap"])
        T.check("and it is cloud", provider?.placement, .cloud)
        T.check("other providers are untouched", factory.make(ChatTarget(provider: .ollama, model: "m", placement: .local)) is OpenAICompatibleProvider, true)
    }

    static func messages() {
        T.section("Notes and buttons")
        let target = ChatTarget(provider: .claudeCode, model: "sonnet", placement: .cloud)
        let signedOut = AIMessages.error(AIError(kind: .auth, code: ClaudeCodeError.signedOut), target: target)
        T.check("signed out", [signedOut.text, signedOut.action == .signInClaude ? "sign in" : "other"], ["Claude Code is signed out.", "sign in"])
        T.check("the pairs", [
            AIMessages.error(AIError(kind: .unreachable, code: ClaudeCodeError.missing), target: target).action == .installClaude,
            AIMessages.error(AIError(kind: .badRequest, code: ClaudeCodeError.tooOld), target: target).action == .updateClaude,
            AIMessages.error(AIError(kind: .server, code: ClaudeCodeError.crashed), target: target).action == .tryAgain,
            AIMessages.error(AIError(kind: .badRequest, code: ClaudeCodeError.needsGit), target: target).action == .installGit,
        ], [true, true, true, true])
        let limit = AIMessages.error(AIError(kind: .billing, code: ClaudeCodeError.planLimit), target: target)
        T.check("a plan limit says so", limit.text, "Your Claude plan's limit was reached.")
        T.check("with no button, and never a billing page", limit.action == nil, true)
        T.check("another provider's key note is unchanged",
                AIMessages.error(AIError(kind: .auth), target: ChatTarget(provider: .anthropic, model: "m", placement: .cloud)).text,
                "Your Anthropic key was rejected.")
        T.check("an error with no Claude Code code falls through to the general words",
                AIMessages.error(AIError(kind: .overloaded), target: target).text, "Claude is still busy. Try again in a moment.")
    }

    // MARK: - Source pins

    /// The text of the function `name` in `text`: from its signature to the next member.
    static func body(of name: String, in text: String) -> String {
        guard let start = text.range(of: "func \(name)(") else { return "" }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n    (@MainActor|private func |func |static func |// MARK)", options: .regularExpression)?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    static func pins() {
        T.section("Where a chat's approvals are routed (source pins)")
        let hook = (try? String(contentsOfFile: "NotchBuddy/Sources/App/HookServer.swift", encoding: .utf8)) ?? ""
        T.checkTrue("HookServer.swift was read", hook.contains("final class HookServer"))
        for name in ["processEvent", "processPermissionRequest", "processQuestionRequest"] {
            let text = body(of: name, in: hook)
            let route = text.range(of: "ClaudeHookRouting.route(")?.lowerBound
            let session = text.range(of: "let sessionId")?.lowerBound
            T.checkTrue("\(name) asks the router before it looks at a session, so a chat never makes or touches a pill",
                        route != nil && session != nil && route! < session!)
            let guarded = text.range(of: "#if !APPSTORE")?.lowerBound
            T.checkTrue("and only in a build that has the engine", guarded != nil && route != nil && guarded! < route!)
        }
        let service = (try? String(contentsOfFile: "NotchBuddy/Sources/App/ClaudeService.swift", encoding: .utf8)) ?? ""
        T.checkTrue("ClaudeService.swift was read", service.contains("final class ClaudeService"))
        T.checkTrue("a new conversation hands every waiting approval back", body(of: "clearConversation", in: service).contains("cancelChatApprovals()"))
        T.checkTrue("so does Stop", body(of: "stop", in: service).contains("cancelChatApprovals()"))
        T.checkTrue("and a session retired by a level change", service.contains("if next.retired != nil { HookServer.shared.cancelChatApprovals() }"))
        T.checkTrue("only the chat's current session is live", service.contains("var liveClaudeSessions: Set<String> { [claudeSession.sessionID] }"))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-claude-code.sh`
Expected: FAIL, a compile error in `tests/ClaudeCodeWiringTests.swift`: `ClaudeCodeSetup` and the factory's `claude` do not exist.

```text
tests/ClaudeCodeWiringTests.swift:22:26: error: cannot find 'ClaudeCodeSetup' in scope
tests/ClaudeCodeWiringTests.swift:22:17: error: value of type 'ProviderFactory' has no member 'claude'
tests/ClaudeCodeWiringTests.swift:33:69: error: type 'AIAction?' has no member 'signInClaude'
```

- [ ] **Step 3: The pure parts first: the setup, the factory and the words**

**Edit `NotchBuddy/Sources/App/AI/Core/ClaudeChatSession.swift`**, find this text (it occurs exactly once):

```swift
}

/// A recap of the chat so far, for a session started afresh in the middle of it.
enum ClaudeCodeRecap {
```

and replace it with:

```swift
}

/// What one chat turn needs to run Claude Code: the program, the turn (session, level, model) and, for a session
/// started afresh, a recap of the chat so far.
struct ClaudeCodeSetup: Sendable, Equatable {
    var executable: String
    var turn: ClaudeCodeTurn
    var preamble: String?
}

/// A recap of the chat so far, for a session started afresh in the middle of it.
enum ClaudeCodeRecap {
```

**Edit `NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift`**, find this text (it occurs exactly once):

```swift
    var apple: (any ModelProvider)? = nil
    var appleContextTokens: Int = AICatalog.Limits.defaultLocalContextTokens

    func make(_ t: ChatTarget) -> any ModelProvider {
```

and replace it with:

```swift
    var apple: (any ModelProvider)? = nil
    var appleContextTokens: Int = AICatalog.Limits.defaultLocalContextTokens
    #if !APPSTORE
    /// The Claude Code run this turn would make: the chat's session and level (`ClaudeService` sets it).
    var claude: ClaudeCodeSetup? = nil
    #endif

    func make(_ t: ChatTarget) -> any ModelProvider {
```

**Edit `NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift`**, find this text (it occurs exactly once):

```swift
            return apple ?? UnavailableProvider(id: .apple)
        case .claudeCode:
            return UnavailableProvider(id: .claudeCode)
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
```

and replace it with:

```swift
            return apple ?? UnavailableProvider(id: .apple)
        case .claudeCode:
            #if !APPSTORE
            if let setup = claude {
                return ClaudeCodeProvider(executable: setup.executable, turn: setup.turn, preamble: setup.preamble)
            }
            #endif
            return UnavailableProvider(id: .claudeCode)
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
```

**Edit `NotchBuddy/Sources/App/AI/Core/AIMessages.swift`**, find this text (it occurs exactly once):

```swift
    case openGuide
    case chooseModel
}

```

and replace it with:

```swift
    case openGuide
    case chooseModel
    /// Claude Code: open Terminal to sign in, show Anthropic's install page, show its update page, show Git for
    /// Windows' page, or send the last message again.
    case signInClaude, installClaude, updateClaude, installGit, tryAgain
}

```

**Edit `NotchBuddy/Sources/App/AI/Core/AIMessages.swift`**, find this text (it occurs exactly once):

```swift
    static func shortName(_ t: ChatTarget) -> String {
        switch t.provider {
        case .anthropic: return "Claude"
        case .openai: return "OpenAI"
        case .google: return "Gemini"
```

and replace it with:

```swift
    static func shortName(_ t: ChatTarget) -> String {
        switch t.provider {
        case .anthropic, .claudeCode: return "Claude"
        case .openai: return "OpenAI"
        case .google: return "Gemini"
```

**Edit `NotchBuddy/Sources/App/AI/Core/AIMessages.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// Drop card line for a file the AI can't take.
    static func rejected(_ reason: AttachmentRejection) -> String {
```

and replace it with:

```swift
    }

    #if !APPSTORE
    /// The button under a Claude Code note, as the app's own action.
    static func action(for action: ClaudeCodeText.Note.Action) -> AIAction {
        switch action {
        case .installGuide: .installClaude
        case .signIn: .signInClaude
        case .updateGuide: .updateClaude
        case .retry: .tryAgain
        case .gitGuide: .installGit
        }
    }
    #endif

    /// Drop card line for a file the AI can't take.
    static func rejected(_ reason: AttachmentRejection) -> String {
```

**Edit `NotchBuddy/Sources/App/AI/Core/AIMessages.swift`**, find this text (it occurs exactly once):

```swift
    /// The message (and its one action) for a failed reply.
    static func error(_ e: AIError, target t: ChatTarget) -> (text: String, action: AIAction?) {
        let name = shortName(t)
        let local = t.placement != .cloud
```

and replace it with:

```swift
    /// The message (and its one action) for a failed reply.
    static func error(_ e: AIError, target t: ChatTarget) -> (text: String, action: AIAction?) {
        #if !APPSTORE
        if t.provider == .claudeCode, let note = ClaudeCodeText.message(for: e) {
            return (note.text, note.action.map(action(for:)))
        }
        #endif
        let name = shortName(t)
        let local = t.placement != .cloud
```

- [ ] **Step 4: Run it: the pins fail, as they should**

Run: `bash scripts/test-claude-code.sh`
Expected: FAIL, the factory and notes sections pass, and the source pins fail because the app does not route anything yet.

```text
  ✗ processEvent asks the router before it looks at a session, so a chat never makes or touches a pill
  ✗ and only in a build that has the engine
  ✗ processPermissionRequest asks the router before it looks at a session, so a chat never makes or touches a pill
  ✗ and only in a build that has the engine
  ✗ processQuestionRequest asks the router before it looks at a session, so a chat never makes or touches a pill
  ✗ and only in a build that has the engine
  ✗ a new conversation hands every waiting approval back
  ✗ so does Stop
  ✗ and a session retired by a level change
  ✗ only the chat's current session is live
```

- [ ] **Step 5: Wire the app: state, service, hook server and the island**

State first (`AppState`): the connected flag and model, what the last check found, the last run's report, the chat's level, the card, and a message's steps.

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
        didSet { Self.saveJSON(customServers, "aiCustomServers") }
    }
    /// Last model used on each local server, by server ID.
    @Published var localModelMemory: [String: String] = [:] {
```

and replace it with:

```swift
        didSet { Self.saveJSON(customServers, "aiCustomServers") }
    }
    #if !APPSTORE
    /// The user connected "Use my Claude plan": Auto may use it while the last check finds Claude Code signed in.
    @Published var claudeCodeEnabled: Bool = false {
        didSet { UserDefaults.standard.set(claudeCodeEnabled, forKey: "aiClaudeCodeEnabled") }
    }
    /// Claude Code's model alias for the chat (sonnet, opus, haiku).
    @Published var claudeCodeModel: ClaudeCodeModel = .sonnet {
        didSet { UserDefaults.standard.set(claudeCodeModel.rawValue, forKey: "aiClaudeCodeModel") }
    }
    #endif
    /// Last model used on each local server, by server ID.
    @Published var localModelMemory: [String: String] = [:] {
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    @Published var appleStatus: AppleOnDevice.Status = .hidden
    @Published var isOnline: Bool = true
    /// "Waking up qwen3.5…" or the busy countdown, shown where the typing dots are.
    @Published var chatNotice: ChatNotice? = nil
```

and replace it with:

```swift
    @Published var appleStatus: AppleOnDevice.Status = .hidden
    @Published var isOnline: Bool = true
    #if !APPSTORE
    /// What the last check found of Claude Code (Settings opening, a chat's first turn): never on a timer.
    @Published var claudeCodeStatus: ClaudeCodeStatus = .notInstalled
    /// What the last Claude Code run said about itself (who pays, which model).
    @Published var claudeRunReport: EngineReport? = nil
    /// The level of the current chat. Every new chat starts at Chat only.
    @Published var claudeLevel: ClaudeCodeLevel = .chatOnly
    /// The step Claude Code is waiting to take in the current chat (Agent level).
    @Published var chatApproval: ChatApproval? = nil
    #endif
    /// "Waking up qwen3.5…" or the busy countdown, shown where the typing dots are.
    @Published var chatNotice: ChatNotice? = nil
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
        case .google: googleChatModel = ref.model
        case .apple: break
        default: localModelMemory[ref.serverID ?? ref.provider.rawValue] = ref.model
        }
```

and replace it with:

```swift
        case .google: googleChatModel = ref.model
        case .apple: break
        case .claudeCode:
            #if !APPSTORE
            claudeCodeModel = ClaudeCodeModel(rawValue: ref.model) ?? .sonnet
            #endif
        default: localModelMemory[ref.serverID ?? ref.provider.rawValue] = ref.model
        }
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
        if let v = Self.loadJSON([CustomServer].self, "aiCustomServers") { customServers = v }
        if let v = Self.loadJSON([String: String].self, "aiLocalModels") { localModelMemory = v }
        migrateChatSettings(ud)
        // Migrate old 60s default → 15s
```

and replace it with:

```swift
        if let v = Self.loadJSON([CustomServer].self, "aiCustomServers") { customServers = v }
        if let v = Self.loadJSON([String: String].self, "aiLocalModels") { localModelMemory = v }
        #if !APPSTORE
        if let v = ud.object(forKey: "aiClaudeCodeEnabled") as? Bool { claudeCodeEnabled = v }
        if let v = ud.string(forKey: "aiClaudeCodeModel"), let m = ClaudeCodeModel(rawValue: v) { claudeCodeModel = m }
        #endif
        migrateChatSettings(ud)
        // Migrate old 60s default → 15s
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    /// The stream was cut: the partial reply is kept with Continue · Retry.
    var interrupted: Bool = false
}

```

and replace it with:

```swift
    /// The stream was cut: the partial reply is kept with Continue · Retry.
    var interrupted: Bool = false
    /// Steps Claude Code took for this reply (reading a file, running a command), shown as rows above it.
    var steps: [ChatStep] = []
}

```

`AIService`: what is ready, the check, the chip and the label.

**Edit `NotchBuddy/Sources/App/AI/AIService.swift`**, find this text (it occurs exactly once):

```swift
    }

    var cloudKeys: Set<AIProviderID> { Set(AICatalog.cloudOrder.filter { key($0) != nil }) }

    /// The remembered model for a cloud provider, else its catalog default.
```

and replace it with:

```swift
    }

    /// The cloud providers Auto may use: those with a key, and Claude Code once the user connected it and the last
    /// check found it signed in.
    var cloudKeys: Set<AIProviderID> {
        var ready = Set(AICatalog.cloudOrder.filter { key($0) != nil })
        #if !APPSTORE
        if state.claudeCodeEnabled, state.claudeCodeStatus.isReady { ready.insert(.claudeCode) }
        #endif
        return ready
    }

    /// The remembered model for a cloud provider, else its catalog default.
```

**Edit `NotchBuddy/Sources/App/AI/AIService.swift`**, find this text (it occurs exactly once):

```swift
        case .anthropic: state.claudeModel
        case .openai: state.openAIChatModel
        default: state.googleChatModel
        }
```

and replace it with:

```swift
        case .anthropic: state.claudeModel
        case .openai: state.openAIChatModel
        #if !APPSTORE
        case .claudeCode: state.claudeCodeModel.rawValue
        #endif
        default: state.googleChatModel
        }
```

**Edit `NotchBuddy/Sources/App/AI/AIService.swift`**, find this text (it occurs exactly once):

```swift
    func target(_ provider: AIProviderID, model: String, placement: AIPlacement, serverID: String?) -> ChatTarget {
        let server = state.localServers.first { $0.serverID == (serverID ?? provider.rawValue) }
        let label = state.fetchedProviderModels[provider]?.first { $0.id == model }?.label
        return ChatTarget(provider: provider, model: model, placement: placement,
                          serverID: serverID ?? server?.serverID, host: server?.host, modelLabel: label)
```

and replace it with:

```swift
    func target(_ provider: AIProviderID, model: String, placement: AIPlacement, serverID: String?) -> ChatTarget {
        let server = state.localServers.first { $0.serverID == (serverID ?? provider.rawValue) }
        var label = state.fetchedProviderModels[provider]?.first { $0.id == model }?.label
        #if !APPSTORE
        if provider == .claudeCode { label = "Claude plan · \(ClaudeCodeModel(rawValue: model)?.label ?? model)" }
        #endif
        return ChatTarget(provider: provider, model: model, placement: placement,
                          serverID: serverID ?? server?.serverID, host: server?.host, modelLabel: label)
```

**Edit `NotchBuddy/Sources/App/AI/AIService.swift`**, find this text (it occurs exactly once):

```swift
        let t = resolve(feature).primary
        let accent = t.map { ChatProvider($0.provider).accentHex } ?? "#5C6370"
        let model = t.map { $0.provider == .apple ? "Apple on-device" : $0.model } ?? "No model yet"
        if case .auto = state.choice(for: feature) { return ("Auto · \(model)", accent) }
```

and replace it with:

```swift
        let t = resolve(feature).primary
        let accent = t.map { ChatProvider($0.provider).accentHex } ?? "#5C6370"
        #if !APPSTORE
        // The engine says who pays; the label is whatever Claude Code last reported, never a guess.
        if t?.provider == .claudeCode {
            return (ClaudeCodeText.modelChip(authMethod: state.claudeCodeStatus.authMethod, paidBy: state.claudeRunReport?.paidBy), accent)
        }
        #endif
        let model = t.map { $0.provider == .apple ? "Apple on-device" : $0.model } ?? "No model yet"
        if case .auto = state.choice(for: feature) { return ("Auto · \(model)", accent) }
```

**Edit `NotchBuddy/Sources/App/AI/AIService.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// Cloud model list (also checks a pasted key). `failure` says why a call failed, so "offline" is never
    /// read as "refused"; an empty list with no failure still counts as refused.
```

and replace it with:

```swift
    }

    #if !APPSTORE
    /// Looks for Claude Code and asks it two questions (version, signed in). Called when Settings opens and before a
    /// chat's first turn, never on a timer.
    func refreshClaudeStatus() async {
        let found = await ClaudeCodeLocator.status()
        if state.claudeCodeStatus != found { state.claudeCodeStatus = found }
    }
    #endif

    /// Cloud model list (also checks a pasted key). `failure` says why a call failed, so "offline" is never
    /// read as "refused"; an empty list with no failure still counts as refused.
```

The Sign in and install actions:

**Create `NotchBuddy/Sources/App/ClaudeCodeActions.swift`** with exactly this content:

```swift
import AppKit

#if !APPSTORE

/// The buttons that open something outside NotchMeow: Terminal for signing in, Anthropic's install page.
@MainActor
enum ClaudeCodeActions {
    /// "Sign in": Terminal runs `claude auth login`, which finishes in the browser. NotchMeow never sees the login.
    /// With no Claude Code to run, the install page opens instead.
    static func signIn() {
        guard let executable = AppState.shared.claudeCodeStatus.executable,
              let script = ClaudeCodeSignIn.write(executable: executable, into: HookServer.supportDir.path) else {
            return openInstallGuide()
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: script))
    }

    static func openInstallGuide() {
        if let url = URL(string: ClaudeCodeLocator.installGuide) { NSWorkspace.shared.open(url) }
    }
}

#endif
```

`ClaudeService`: the chat's session, the setup it hands the factory, the steps, the report, Stop, and "Try again". This replaces Task 5's placeholder for the two new run events.

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
    var currentFeature: AIFeature { conversation.feature }

    /// Starts over when a new file or window is attached, so the next turn carries it. Clears what
    /// the model gets and the transcript on screen together, like the Windows build does on drop.
```

and replace it with:

```swift
    var currentFeature: AIFeature { conversation.feature }

    #if !APPSTORE
    /// This chat's Claude Code session; replaced when the conversation is cleared.
    private var claudeSession = ClaudeChatSession()
    /// The session ids whose hook events belong to this chat: `HookServer` routes by them.
    var liveClaudeSessions: Set<String> { [claudeSession.sessionID] }
    #endif

    /// Starts over when a new file or window is attached, so the next turn carries it. Clears what
    /// the model gets and the transcript on screen together, like the Windows build does on drop.
```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
        state.chatStreaming = false
        if state.stateOverride == .thinking { state.stateOverride = nil }
    }

```

and replace it with:

```swift
        state.chatStreaming = false
        if state.stateOverride == .thinking { state.stateOverride = nil }
        #if !APPSTORE
        // A new chat: a new Claude Code session at Chat only. The old id is retired with its approvals.
        HookServer.shared.cancelChatApprovals()
        _ = claudeSession.reset()
        state.claudeLevel = .chatOnly
        #endif
    }

```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
        replyTask?.cancel()
        countdownTask?.cancel()
    }

```

and replace it with:

```swift
        replyTask?.cancel()
        countdownTask?.cancel()
        #if !APPSTORE
        HookServer.shared.cancelChatApprovals()
        #endif
    }

```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
        let generation = conversationGeneration
        let service = AIService.shared
        var input = service.routeInput(conversation.feature)
        if ModelRouter.plan(input) == nil {
```

and replace it with:

```swift
        let generation = conversationGeneration
        let service = AIService.shared
        #if !APPSTORE
        // Before a chat's first turn: is Claude Code there, and signed in? (Never on a timer.)
        if conversation.turns.count <= 1, state.claudeCodeEnabled || usesClaudeCodeByChoice() {
            await service.refreshClaudeStatus()
            guard generation == conversationGeneration else { return }
        }
        #endif
        var input = service.routeInput(conversation.feature)
        if ModelRouter.plan(input) == nil {
```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
        }
        let primary = service.primaryTarget(plan)
        let factory = service.factory()
        let convo = conversation
        let system = systemPrompt
        let notices = NoticeBox()
        let runner = ChatRunner(
            makeProvider: { factory.make($0) },
            makeRequest: { target in
                let details = await factory.details(target)
                let built = convo.request(model: target.model, api: AICatalog.info(target.provider).api,
                                          vision: details.vision, placement: target.placement,
```

and replace it with:

```swift
        }
        let primary = service.primaryTarget(plan)
        var factory = service.factory()
        #if !APPSTORE
        var claudeFolder = ""
        if primary.provider == .claudeCode {
            claudeSession.level = state.claudeLevel
            claudeSession.model = ClaudeCodeModel(rawValue: primary.model) ?? state.claudeCodeModel
            let chatFolder = ClaudeCodeFolders.chatFolder()
            let next = claudeSession.plan(chatFolder: chatFolder)
            if next.retired != nil { HookServer.shared.cancelChatApprovals() }
            // A session started afresh in the middle of a chat is told what was said before (the new message is last).
            let recap = next.needsRecap
                ? ClaudeCodeRecap.text(turns: conversation.turns.dropLast().map { ($0.role, $0.text) }) : nil
            factory.claude = ClaudeCodeSetup(executable: state.claudeCodeStatus.executable ?? "", turn: next.turn, preamble: recap)
            claudeFolder = next.turn.level.folder ?? chatFolder
        }
        let sessionFolder = claudeFolder
        #endif
        let runFactory = factory
        let convo = conversation
        let system = systemPrompt
        let notices = NoticeBox()
        let runner = ChatRunner(
            makeProvider: { runFactory.make($0) },
            makeRequest: { target in
                let details = await runFactory.details(target)
                let built = convo.request(model: target.model, api: AICatalog.info(target.provider).api,
                                          vision: details.vision, placement: target.placement,
```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
                    case .fellBack(let from, let to, _):
                        state.chatHistory[i].notice = AIMessages.fellBack(from: from, to: to)
                    case .step, .engine:
                        break  // what Claude Code does and says about itself: shown once the chat is wired to it
                    }
                }
```

and replace it with:

```swift
                    case .fellBack(let from, let to, _):
                        state.chatHistory[i].notice = AIMessages.fellBack(from: from, to: to)
                    case .step(let step):
                        if let j = state.chatHistory[i].steps.firstIndex(where: { $0.id == step.id }) {
                            state.chatHistory[i].steps[j] = step
                        } else {
                            state.chatHistory[i].steps.append(step)
                        }
                    case .engine(let report):
                        #if !APPSTORE
                        state.claudeRunReport = report
                        // Claude Code has made the session: the next turn resumes it, from the same folder.
                        ClaudeService.shared.claudeSession.confirmStarted(in: sessionFolder)
                        #endif
                    }
                }
```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
        state.stateOverride = nil
        let i = state.chatHistory.firstIndex { $0.id == msgID }
        func removePlaceholder() { if let i { state.chatHistory.remove(at: i) } }
        func takeBackUserTurn() { if addedUserTurn { conversation.removeLastUser() } }
```

and replace it with:

```swift
        state.stateOverride = nil
        let i = state.chatHistory.firstIndex { $0.id == msgID }
        // A step that never finished (Stop, a crash) ends as stopped: no row stays "running".
        if let i { state.chatHistory[i].steps = ChatStep.endingUnfinished(state.chatHistory[i].steps) }
        func removePlaceholder() { if let i { state.chatHistory.remove(at: i) } }
        func takeBackUserTurn() { if addedUserTurn { conversation.removeLastUser() } }
```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        case .cancelled:
            if result.text.isEmpty {
                removePlaceholder()
                takeBackUserTurn()
            } else {
                conversation.addAssistant(result.text)
```

and replace it with:

```swift
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        case .cancelled:
            // Stop during Claude Code's work keeps the steps it took (stopped), even with no words yet.
            let keptSteps = i.map { !state.chatHistory[$0].steps.isEmpty } ?? false
            if result.text.isEmpty, !keptSteps {
                removePlaceholder()
                takeBackUserTurn()
            } else if result.text.isEmpty {
                // The steps stay on screen; the chat has nothing of Claude's to remember for this turn.
            } else {
                conversation.addAssistant(result.text)
```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
            takeBackUserTurn()
            let (text, action) = AIMessages.error(result.error ?? AIError(kind: .server), target: primary)
            showError(text, action: action, state: state)
        }
    }
```

and replace it with:

```swift
            takeBackUserTurn()
            let (text, action) = AIMessages.error(result.error ?? AIError(kind: .server), target: primary)
            // The plan's limit is the cat's rate-limit look, not its error face.
            var cat = BotState.error
            #if !APPSTORE
            if result.error?.code == ClaudeCodeError.planLimit { cat = .ratelimit }
            #endif
            showError(text, action: action, state: state, cat: cat)
        }
    }
```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// The partial reply's "Continue".
    func continueReply(state: AppState) {
```

and replace it with:

```swift
    }

    #if !APPSTORE
    /// The chat's model choice names Claude Code explicitly (so its status is looked at even before it is connected).
    private func usesClaudeCodeByChoice() -> Bool {
        if case .explicit(let ref) = AppState.shared.choice(for: conversation.feature), ref.provider == .claudeCode { return true }
        return false
    }
    #endif

    /// "Try again" under a note: the last message is sent again.
    func resendLastMessage(state: AppState) {
        guard !state.chatStreaming, let i = state.chatHistory.lastIndex(where: { $0.role == .user }) else { return }
        let text = state.chatHistory[i].content
        state.chatHistory.remove(at: i)
        send(query: text, context: nil, state: state)
    }

    /// The partial reply's "Continue".
    func continueReply(state: AppState) {
```

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`**, find this text (it occurs exactly once):

```swift
    }

    private func showError(_ message: String, action: AIAction?, state: AppState) {
        state.stateOverride = .error
        state.noteMessage = message
        state.noteAction = action.map { NoteAction(message: message, action: $0) }
```

and replace it with:

```swift
    }

    private func showError(_ message: String, action: AIAction?, state: AppState, cat: BotState = .error) {
        state.stateOverride = cat
        state.noteMessage = message
        state.noteAction = action.map { NoteAction(message: message, action: $0) }
```

`HookServer`: the router first in the three handlers, then the chat's own card and its decisions.

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
    private func processEvent(name: String, payload: [String: Any]) {
        let state = AppState.shared
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
```

and replace it with:

```swift
    private func processEvent(name: String, payload: [String: Any]) {
        let state = AppState.shared
        #if !APPSTORE
        // The events of a chat's own Claude Code run are not a session: the chat's stream already shows its steps.
        if case .chat = ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) { return }
        #endif
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
    private func processPermissionRequest(fd: Int32, payload: [String: Any]) {
        let state = AppState.shared
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
```

and replace it with:

```swift
    private func processPermissionRequest(fd: Int32, payload: [String: Any]) {
        let state = AppState.shared
        #if !APPSTORE
        // A chat's own Claude Code run asks here too (same hooks). Its card is in that chat, never a pill, and it never
        // touches the one pending approval of the user's own sessions.
        if case .chat(let chatSession) = ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) {
            processChatPermission(fd: fd, sessionID: chatSession, payload: payload)
            return
        }
        #endif
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
    }

    // MARK: - Question request

    @MainActor
    private func processQuestionRequest(fd: Int32, parsed: AskQuestion, payload: [String: Any]) {
        let state = AppState.shared
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
```

and replace it with:

```swift
    }

    // MARK: - A chat's own Claude Code run (Agent level)

    #if !APPSTORE
    /// The hook's connection for one waiting request, and what watches it.
    private struct ChatApprovalToken: @unchecked Sendable {
        let fd: Int32
        let source: any DispatchSourceRead
    }
    private var chatApprovals = ChatApprovalQueue<ChatApprovalToken>()

    /// A request from a chat's own run: queued, shown as a card in that chat. Nothing runs without a click. When the
    /// hook is not installed it never gets here, and Claude Code refuses the step.
    @MainActor
    private func processChatPermission(fd: Int32, sessionID: String, payload: [String: Any]) {
        let tool = payload["tool_name"] as? String ?? "Tool"
        // A question cannot be answered in a chat run: hand it back, Claude Code carries on without.
        if tool == "AskUserQuestion" {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let approval = ChatApproval(id: UUID(), sessionID: sessionID, tool: tool,
                                    target: ChatApprovalText.target(tool: tool, input: input))
        // Claude Code gave up (Stop, a crash): the connection closes and the card goes. The cancel handler closes the fd.
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.dropChatApproval(id: approval.id) }
        source.setCancelHandler { close(fd) }
        source.resume()
        chatApprovals.push(approval, token: ChatApprovalToken(fd: fd, source: source))
        showChatApproval()
        // The hook waits 120 s at most: after 115 the card would be lying.
        DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in self?.dropChatApproval(id: approval.id) }
    }

    /// Puts the first waiting request on the chat's card (or takes the card away), and brings the chat up for a new one.
    @MainActor
    private func showChatApproval() {
        let state = AppState.shared
        let before = state.chatApproval
        state.chatApproval = chatApprovals.front
        if before == nil, chatApprovals.front != nil {
            SoundEngine.shared.play("approval")
            state.isPinned = true
            if state.mode == .expanded {
                state.view = .prompt
            } else {
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
            }
        } else if chatApprovals.isEmpty, state.pendingApproval == nil {
            state.isPinned = false
        }
    }

    /// Allow or Deny on the chat's card.
    @MainActor
    func sendChatApprovalDecision(_ decision: String) {
        guard let entry = chatApprovals.popFront() else { return }
        let json = decision == "allow" ? #"{"permissionDecision":"allow"}"# : #"{"permissionDecision":"deny"}"#
        let fd = entry.token.fd, source = entry.token.source
        Task.detached { [weak self] in
            self?.sendLine(fd: fd, text: json)
            DispatchQueue.main.async { source.cancel() }
        }
        showChatApproval()
    }

    /// One request gone (its connection closed, or it timed out): no decision is sent, and Claude Code refuses the step.
    @MainActor
    private func dropChatApproval(id: UUID) {
        guard let entry = chatApprovals.remove(id: id) else { return }
        entry.token.source.cancel()
        showChatApproval()
    }

    /// Stop, a new conversation, a level change: every waiting request is handed back (`ask` is a refusal in `-p`).
    @MainActor
    func cancelChatApprovals() {
        for entry in chatApprovals.removeAll() {
            let fd = entry.token.fd, source = entry.token.source
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { source.cancel() }
            }
        }
        showChatApproval()
    }

    /// Whether Claude Code's settings carry NotchMeow's `PermissionRequest` hook: Agent mode asks through it.
    static func claudeHooksInstalled() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return ClaudeAgentReadiness.hooksInstalled(in: settings)
    }
    #endif

    // MARK: - Question request

    @MainActor
    private func processQuestionRequest(fd: Int32, parsed: AskQuestion, payload: [String: Any]) {
        let state = AppState.shared
        #if !APPSTORE
        // A chat's run cannot be asked a question on the island: Claude Code carries on without.
        if case .chat = ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        #endif
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
```

The note's new buttons, in the island's `NoteView`:

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
        case .openGuide: "Open guide"
        case .chooseModel: "Choose model"
        }
    }
```

and replace it with:

```swift
        case .openGuide: "Open guide"
        case .chooseModel: "Choose model"
        case .signInClaude: "Sign in"
        case .installClaude: "How to install"
        case .updateClaude: "How to update"
        case .installGit: "Get Git for Windows"
        case .tryAgain: "Try again"
        }
    }
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
            state.view = .prompt
            state.openModelPicker = true
        }
    }
```

and replace it with:

```swift
            state.view = .prompt
            state.openModelPicker = true
        case .signInClaude:
            #if !APPSTORE
            ClaudeCodeActions.signIn()
            #endif
        case .installClaude, .updateClaude:
            #if !APPSTORE
            ClaudeCodeActions.openInstallGuide()
            #endif
        case .installGit:
            if let url = URL(string: "https://git-scm.com/downloads/win") { NSWorkspace.shared.open(url) }
        case .tryAgain:
            state.stateOverride = nil
            state.view = .prompt
            ClaudeService.shared.resendLastMessage(state: state)
        }
    }
```

- [ ] **Step 6: Run the Claude Code tests**

Run: `bash scripts/test-claude-code.sh`
Expected: PASS, seven test programs and no `✗`, the pins among them.

```text
== ClaudeCodeApprovalTests
All tests passed.
== ClaudeCodeEngineTests
All tests passed.
== ClaudeCodeLocatorTests
All tests passed.
== ClaudeCodeParserTests
All tests passed.
== ClaudeCodeProviderTests
All tests passed.
== ClaudeCodeSessionTests
All tests passed.
== ClaudeCodeWiringTests
All tests passed.
```

- [ ] **Step 7: Build all three ways**

The App Store target must still build: every line above that only the engine needs is behind `#if !APPSTORE`.

Run: `(cd NotchBuddy && xcodegen --quiet && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

Run: `(cd NotchBuddy && xcodebuild -scheme NotchMeowAppStore -configuration Debug -derivedDataPath build/store build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj NotchBuddy/Sources/App/ClaudeCodeActions.swift NotchBuddy/Sources/App/AI/Core/ClaudeChatSession.swift NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift NotchBuddy/Sources/App/AI/Core/AIMessages.swift NotchBuddy/Sources/App/AI/AIService.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/ClaudeService.swift NotchBuddy/Sources/App/HookServer.swift NotchBuddy/Sources/App/IslandViewContent.swift tests/ClaudeCodeWiringTests.swift
git commit -q -m "feat(claude-code): the chat runs Claude Code, with its approvals on a card in the chat" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 11: Mac: the views (level chip, steps and card in the chat, Connect Claude, pickers)

**Agent:** `nm-implementer`. SwiftUI built from the app's own pieces; the one pure addition has a test, the rest is checked by building both targets and by the owner's checkpoint (Task 13).

**Files:**
- Create: `NotchBuddy/Sources/App/ClaudeChatViews.swift`
- Modify: `NotchBuddy/Sources/App/AI/Core/ClaudeCodeText.swift` (`signInWords`)
- Modify: `NotchBuddy/Sources/App/IslandViewContent.swift`, `SettingsView.swift`, `AppState.swift`
- Test: `tests/ClaudeCodeSessionTests.swift`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (generated)

**Interfaces:**
- Consumes: `AppState.claudeLevel`, `chatApproval`, `claudeCodeStatus`, `claudeCodeEnabled`, `ChatMessage.steps` (Task 10); `HookServer.sendChatApprovalDecision`, `claudeHooksInstalled()`; `ClaudeCodeText`, `ClaudeAgentReadiness` (Tasks 8 and 9); `SessionStepText` (Task 9); the app's `TickerRowView`, `CodeBlock`, `PrimaryButton`, `SecondaryButton`, `AgentWho`.
- Produces (all `#if !APPSTORE`, in `ClaudeChatViews.swift`): `ClaudeStepsView(steps:)` (one session-style step row per step, with a mark when it failed or was stopped), `ChatApprovalCard(approval:)` ("Claude needs permission", the target in a `CodeBlock`, Deny and Allow), `ClaudeLevelChip(state:)` and its popover `ClaudeLevelMenu` (Chat only, Read-only, Agent; the last two open a folder picker; Agent is disabled, with the reason, when the hooks are not installed; the chip is disabled while a reply streams), `ConnectClaudePlanView(state:)` (where Claude Code is, whether it is signed in, one button; it looks when Settings opens and when asked, never on a timer); and `ClaudeCodeText.signInWords(_:) -> String`.
- **What changes in existing views, and only this** (`CLAUDE.md`: never restyle what ships): the level chip beside the model chip; step rows above a reply and the approval card in the chat; a "Connect Claude" button in the chat's empty state; the model picker lists the Claude plan's three models when it is ready; in Settings → AI a "Connect Claude" box above "Which model answers" (the whole Connect Claude box is compiled out of the App Store build; its existing "Anthropic API" field is the API-key path there), a Claude plan entry in the model pickers, and the Preferred cloud picker listing what is ready. Nothing else, and no colour, size or spacing of an existing element changes.

- [ ] **Step 1: Write the failing test**

**Edit `tests/ClaudeCodeSessionTests.swift`**, find this text (it occurs exactly once):

```swift
        hookRouting()
        chips()
        notes()
        T.finish()
```

and replace it with:

```swift
        hookRouting()
        chips()
        signInWords()
        notes()
        T.finish()
```

**Edit `tests/ClaudeCodeSessionTests.swift`**, find this text (it occurs exactly once):

```swift
    }

    // MARK: - copy.json

```

and replace it with:

```swift
    }

    static func signInWords() {
        T.section("How Claude Code is signed in")
        T.check("a plan", ClaudeCodeText.signInWords("claude.ai"), "your Claude plan")
        T.check("an API key helper", ClaudeCodeText.signInWords("api_key_helper"), "an API key helper")
        T.check("a method this build does not know", ClaudeCodeText.signInWords("something_new"), "its own sign-in")
        T.check("none given", ClaudeCodeText.signInWords(nil), "its own sign-in")
    }

    // MARK: - copy.json

```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-claude-code.sh`
Expected: FAIL, a compile error in `tests/ClaudeCodeSessionTests.swift`: `ClaudeCodeText` has no member `signInWords`.

```text
tests/ClaudeCodeSessionTests.swift:120:42: error: type 'ClaudeCodeText' has no member 'signInWords'
tests/ClaudeCodeSessionTests.swift:121:53: error: type 'ClaudeCodeText' has no member 'signInWords'
```

- [ ] **Step 3: Write the words and the views**

**Edit `NotchBuddy/Sources/App/AI/Core/ClaudeCodeText.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// The last part of a path, whichever separator it uses; "/" and "C:" keep their own names.
    static func folderName(_ path: String) -> String {
```

and replace it with:

```swift
    }

    /// How Claude Code is signed in, in words: "your Claude plan", "an API key".
    static func signInWords(_ authMethod: String?) -> String {
        switch authMethod {
        case "claude.ai": "your Claude plan"
        case "oauth_token": "an OAuth token"
        case "api_key": "an API key"
        case "api_key_helper": "an API key helper"
        case "third_party": "a cloud account"
        default: "its own sign-in"
        }
    }

    /// The last part of a path, whichever separator it uses; "/" and "C:" keep their own names.
    static func folderName(_ path: String) -> String {
```

**Create `NotchBuddy/Sources/App/ClaudeChatViews.swift`** with exactly this content:

```swift
import SwiftUI
import AppKit

// The Claude Code engine's views: the level chip next to the model chip, the step rows and the approval card in the
// chat, and the "Use my Claude plan" half of Settings' Connect Claude box. They are built from the pieces the app
// already has (`TickerRowView`, `CodeBlock`, `PrimaryButton`, `SecondaryButton`, `AgentWho`) and follow the model
// chip's look. The App Store build compiles all of it out.

#if !APPSTORE

// MARK: - Steps in the chat

/// The steps Claude Code took for one reply: the session view's own step rows, one per step.
struct ClaudeStepsView: View {
    let steps: [ChatStep]

    private static let scale: CGFloat = 11.5 / 13   // the ticker's completed-row size

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps, id: \.id) { step in
                TickerRowView(text: Self.words(step), phase: step.state == .running ? 0 : 1, isActive: step.state == .running)
                    .scaleEffect(Self.scale, anchor: .leading)
                    .frame(height: 20)
            }
        }
    }

    /// "Lit · README.md", with a mark when it failed or was stopped.
    static func words(_ step: ChatStep) -> String {
        let line = SessionStepText.line(tool: step.tool, input: step.input)
        switch step.state {
        case .running, .done: return line
        case .failed: return line + " ⚠"
        case .stopped: return line + " · stopped"
        }
    }
}

// MARK: - The approval card in the chat

/// "Claude needs permission" for one step, with Allow and Deny. The island's own approval card, in the chat.
struct ChatApprovalCard: View {
    let approval: ChatApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AgentWho(task: nil, label: "Claude needs permission")
            CodeBlock(text: approval.target)
            HStack(spacing: 8) {
                SecondaryButton("Deny") { HookServer.shared.sendChatApprovalDecision("deny") }
                PrimaryButton("Allow") { HookServer.shared.sendChatApprovalDecision("allow") }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#F5B544").opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - The level chip

/// Chat only, Read-only or Agent, per chat. Next to the model chip, in its look. Every new chat starts at Chat only;
/// Read-only and Agent ask for a folder. It cannot change while a reply is streaming.
struct ClaudeLevelChip: View {
    @ObservedObject var state: AppState
    @State private var showMenu = false

    var body: some View {
        Button { showMenu.toggle() } label: {
            HStack(spacing: 5) {
                Text(ClaudeCodeText.levelChip(state.claudeLevel))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(hex: "#7B8089"))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(Color(hex: "#5C6370"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state.chatStreaming)
        .opacity(state.chatStreaming ? 0.5 : 1)
        .accessibilityLabel("What Claude may do in this chat")
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            ClaudeLevelMenu(state: state, isPresented: $showMenu).frame(width: 290)
        }
    }
}

struct ClaudeLevelMenu: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool

    private var hooksReady: Bool { ClaudeAgentReadiness.check(hooksInstalled: HookServer.claudeHooksInstalled()) == .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Chat only", "Answers, dropped files, web search and fetch.", isCurrent: state.claudeLevel == .chatOnly) {
                choose(.chatOnly)
            }
            row("Read-only", "Also reads and searches files in a folder you choose.", isCurrent: isReadOnly) {
                pickFolder { choose(.readOnly(folder: $0)) }
            }
            row("Agent", "Also edits files and runs commands there, each step behind a card.", isCurrent: isAgent, enabled: hooksReady) {
                pickFolder { choose(.agent(folder: $0)) }
            }
            if !hooksReady {
                Text(ClaudeAgentReadiness.hooksNote)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#8A8F98"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
        .padding(10)
        .background(Color(hex: "#16171B"))
    }

    private var isReadOnly: Bool { if case .readOnly = state.claudeLevel { true } else { false } }
    private var isAgent: Bool { if case .agent = state.claudeLevel { true } else { false } }

    private func row(_ title: String, _ detail: String, isCurrent: Bool, enabled: Bool = true,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title).font(.system(size: 12, weight: .medium))
                        .foregroundColor(isCurrent ? Color(hex: "#E07950") : Color(hex: "#C8CDD4"))
                    Spacer()
                    if isCurrent {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#E07950"))
                    }
                }
                Text(detail).font(.system(size: 10.5)).foregroundColor(Color(hex: "#8A8F98"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color(hex: "#E07950").opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func choose(_ level: ClaudeCodeLevel) {
        state.claudeLevel = level
        isPresented = false
        SoundEngine.shared.play("blip")
    }

    /// The chat's working folder. NotchMeow is an accessory app: it comes forward for the panel and gives the island
    /// back afterwards.
    private func pickFolder(then use: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder Claude may work in"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { use(url.path) }
    }
}

// MARK: - Settings: Use my Claude plan

/// Settings → AI → Connect Claude, the plan half: where Claude Code is, whether it is signed in, and one button.
/// It looks when Settings opens and when asked, never on a timer.
struct ConnectClaudePlanView: View {
    @ObservedObject var state: AppState
    @State private var checking = false

    private var status: ClaudeCodeStatus { state.claudeCodeStatus }
    private var inUse: Bool { state.claudeCodeEnabled && state.preferredCloud == .claudeCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                dot
                Text("Use my Claude plan").font(.system(size: 12, weight: .semibold))
                Text(ClaudeCodeEngine.note).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text(line).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                switch status.state {
                case .signedIn:
                    if inUse {
                        Text("Claude is now your main AI.").font(.system(size: 11)).foregroundColor(Color(hex: "#22C55E"))
                        Button("Stop using it") { stopUsing() }
                    } else {
                        Button("Use my Claude plan") { startUsing() }.buttonStyle(.borderedProminent)
                    }
                case .signedOut:
                    Button("Sign in") { ClaudeCodeActions.signIn() }.buttonStyle(.borderedProminent)
                case .notInstalled, .tooOld:
                    if let guide = URL(string: ClaudeCodeLocator.installGuide) {
                        Link(status.state == .tooOld ? "How to update" : "How to install", destination: guide).font(.system(size: 11))
                    }
                case .unknown:
                    EmptyView()
                }
                Button(checking ? "Checking…" : "Check again") { Task { await refresh() } }.disabled(checking)
            }
            .buttonStyle(.bordered)
        }
        .onAppear { Task { await refresh() } }
    }

    private var dot: some View {
        Circle().fill(status.isReady ? Color(hex: "#22C55E") : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
    }

    private var line: String {
        let version = status.version.map { " \($0)" } ?? ""
        switch status.state {
        case .notInstalled: return "Claude Code isn't installed on this Mac."
        case .tooOld: return "Claude Code\(version) is too old for this."
        case .signedOut: return "Claude Code\(version) is signed out. Signing in opens Terminal, and finishes in your browser."
        case .unknown: return "Couldn't ask Claude Code. Is it installed properly?"
        case .signedIn: return "✓ Claude Code\(version), signed in with \(ClaudeCodeText.signInWords(status.authMethod))."
        }
    }

    private func refresh() async {
        checking = true
        await AIService.shared.refreshClaudeStatus()
        checking = false
    }

    private func startUsing() {
        state.claudeCodeEnabled = true
        state.preferredCloud = .claudeCode
        state.setChoice(.auto, for: .chat)
    }

    private func stopUsing() {
        state.claudeCodeEnabled = false
        if state.preferredCloud == .claudeCode { state.preferredCloud = .anthropic }
    }
}

#endif
```

The chat: the card, the chip, the steps, the empty state's button and the model picker.

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                                    ChatBubble(message: msg).id(msg.id)
                                }
                                if state.stateOverride != nil || state.chatNotice != nil {
                                    HStack(spacing: 8) {
```

and replace it with:

```swift
                                    ChatBubble(message: msg).id(msg.id)
                                }
                                #if !APPSTORE
                                if let approval = state.chatApproval { ChatApprovalCard(approval: approval).id("approval") }
                                #endif
                                if state.stateOverride != nil || state.chatNotice != nil {
                                    HStack(spacing: 8) {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                            }
                        }
                        .onChange(of: state.stateOverride) { _, v in
                            if v != nil {
```

and replace it with:

```swift
                            }
                        }
                        #if !APPSTORE
                        .onChange(of: state.chatApproval) { _, v in
                            if v != nil { withAnimation { proxy.scrollTo("approval", anchor: .bottom) } }
                        }
                        #endif
                        .onChange(of: state.stateOverride) { _, v in
                            if v != nil {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
```

and replace it with:

```swift
                HStack(spacing: 0) {
                    Spacer()
                    #if !APPSTORE
                    if AIService.shared.resolve(ClaudeService.shared.currentFeature).primary?.provider == .claudeCode {
                        ClaudeLevelChip(state: state).padding(.trailing, 6)
                    }
                    #endif
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
            focused = true
            AIService.shared.prewarm(ClaudeService.shared.currentFeature)
        }
        .onChange(of: state.openModelPicker) { _, open in
```

and replace it with:

```swift
            focused = true
            AIService.shared.prewarm(ClaudeService.shared.currentFeature)
            #if !APPSTORE
            // Before a chat's first message: is Claude Code there, and signed in? (Never on a timer.)
            if state.claudeCodeEnabled, state.chatHistory.isEmpty { Task { await AIService.shared.refreshClaudeStatus() } }
            #endif
        }
        .onChange(of: state.openModelPicker) { _, open in
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
    private var sources: [Source] {
        var list: [Source] = [.auto] + AICatalog.cloudOrder.map { .cloud($0) }
        list += state.localServers.filter(\.isReady).map { .server($0.serverID) }
        if state.appleStatus == .ready { list.append(.apple) }
```

and replace it with:

```swift
    private var sources: [Source] {
        var list: [Source] = [.auto] + AICatalog.cloudOrder.map { .cloud($0) }
        #if !APPSTORE
        if state.claudeCodeEnabled, state.claudeCodeStatus.isReady { list.insert(.cloud(.claudeCode), at: 1) }
        #endif
        list += state.localServers.filter(\.isReady).map { .server($0.serverID) }
        if state.appleStatus == .ready { list.append(.apple) }
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                .padding(.vertical, 4)
        case .cloud(let p):
            if state.loadingProviderModels.contains(p) {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
```

and replace it with:

```swift
                .padding(.vertical, 4)
        case .cloud(let p):
            if p == .claudeCode {
                modelRows(ClaudeCodeModel.allCases.map { ($0.rawValue, "Claude \($0.label)") },
                          accent: ChatProvider.claudeCode.accentHex) { ModelRef(provider: .claudeCode, model: $0) }
            } else if state.loadingProviderModels.contains(p) {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift

    var body: some View {
        if !message.content.isEmpty {
            HStack(alignment: .top) {
                if message.role == .user {
```

and replace it with:

```swift

    var body: some View {
        if !message.content.isEmpty || !message.steps.isEmpty {
            HStack(alignment: .top) {
                if message.role == .user {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ChatMarkdownView(markdown: message.content)
                        ReplyFooter(message: message)
                    }
```

and replace it with:

```swift
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        #if !APPSTORE
                        if !message.steps.isEmpty { ClaudeStepsView(steps: message.steps) }
                        #endif
                        if !message.content.isEmpty { ChatMarkdownView(markdown: message.content) }
                        ReplyFooter(message: message)
                    }
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                    showNote(AIMessages.localGuide, action: nil, markdown: true, state: state)
                }
            }
        }
```

and replace it with:

```swift
                    showNote(AIMessages.localGuide, action: nil, markdown: true, state: state)
                }
                #if !APPSTORE
                SecondaryButton("Connect Claude") {
                    NotificationCenter.default.post(name: .openFullSettings, object: "chat")
                }
                #endif
            }
        }
```

Settings: the Connect Claude box, the Preferred cloud picker and the model pickers.

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, find this text (it occurs exactly once):

```swift

    @ViewBuilder private var chatSection: some View {
        GroupBox("Which model answers") {
            VStack(alignment: .leading, spacing: 10) {
```

and replace it with:

```swift

    @ViewBuilder private var chatSection: some View {
        GroupBox("Connect Claude") {
            VStack(alignment: .leading, spacing: 12) {
                #if !APPSTORE
                ConnectClaudePlanView(state: state)
                Divider()
                #endif
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Paste an API key").font(.system(size: 12, weight: .semibold))
                        keyMark(.anthropic)
                    }
                    Text("From the Claude Console. It is checked and saved in the Keychain.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        SecureField("API key (sk-ant-…)", text: $apiKey).textFieldStyle(.roundedBorder)
                        Button("Save") {
                            saveKey(.anthropic, apiKey)
                            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { state.preferredCloud = .anthropic }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(6)
        }

        GroupBox("Which model answers") {
            VStack(alignment: .leading, spacing: 10) {
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, find this text (it occurs exactly once):

```swift
                    }
                }
                if AIService.shared.cloudKeys.isSuperset(of: [.anthropic, .openai]) {
                    HStack(spacing: 8) {
                        Text("Preferred cloud").frame(width: 110, alignment: .leading)
                        Picker("", selection: $state.preferredCloud) {
                            Text("Claude").tag(AIProviderID.anthropic)
                            Text("OpenAI").tag(AIProviderID.openai)
                        }
                        .labelsHidden()
```

and replace it with:

```swift
                    }
                }
                if AIService.shared.cloudKeys.intersection([.claudeCode, .anthropic, .openai]).count >= 2 {
                    let ready = AIService.shared.cloudKeys
                    HStack(spacing: 8) {
                        Text("Preferred cloud").frame(width: 110, alignment: .leading)
                        Picker("", selection: $state.preferredCloud) {
                            if ready.contains(.claudeCode) { Text("Claude plan").tag(AIProviderID.claudeCode) }
                            if ready.contains(.anthropic) {
                                Text(ready.contains(.claudeCode) ? "Claude API" : "Claude").tag(AIProviderID.anthropic)
                            }
                            if ready.contains(.openai) { Text("OpenAI").tag(AIProviderID.openai) }
                        }
                        .labelsHidden()
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, find this text (it occurs exactly once):

```swift
            }
        }
        let servers = state.localServers.filter(\.isReady)
        if !servers.isEmpty {
```

and replace it with:

```swift
            }
        }
        #if !APPSTORE
        if state.claudeCodeEnabled, state.claudeCodeStatus.isReady {
            Section("Claude plan") {
                ForEach(ClaudeCodeModel.allCases, id: \.self) { model in
                    Text("Claude plan · \(model.label)")
                        .tag(FeatureSetting.explicit(ModelRef(provider: .claudeCode, model: model.rawValue)))
                }
            }
        }
        #endif
        let servers = state.localServers.filter(\.isReady)
        if !servers.isEmpty {
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, find this text (it occurs exactly once):

```swift

    private func isListed(_ ref: ModelRef) -> Bool {
        if ref.provider.isCloud { return AIService.shared.key(ref.provider) != nil && AIService.shared.cloudModel(ref.provider) == ref.model }
        if ref.provider == .apple { return state.appleStatus == .ready }
```

and replace it with:

```swift

    private func isListed(_ ref: ModelRef) -> Bool {
        if ref.provider == .claudeCode {
            #if !APPSTORE
            return state.claudeCodeEnabled && state.claudeCodeStatus.isReady
            #else
            return false
            #endif
        }
        if ref.provider.isCloud { return AIService.shared.key(ref.provider) != nil && AIService.shared.cloudModel(ref.provider) == ref.model }
        if ref.provider == .apple { return state.appleStatus == .ready }
```

`AppState.fetchModelsIfNeeded` must not ask for an API model list for the Claude plan (it has no key and no list):

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    /// Fetches a cloud provider's models if not already loaded or loading.
    func fetchModelsIfNeeded(for provider: AIProviderID) {
        guard provider.isCloud, !loadingProviderModels.contains(provider),
              fetchedProviderModels[provider] == nil else { return }
        guard let key = AIService.shared.key(provider) else {
```

and replace it with:

```swift
    /// Fetches a cloud provider's models if not already loaded or loading.
    func fetchModelsIfNeeded(for provider: AIProviderID) {
        guard provider.isCloud, provider != .claudeCode, !loadingProviderModels.contains(provider),
              fetchedProviderModels[provider] == nil else { return }
        guard let key = AIService.shared.key(provider) else {
```

The level menu's Agent row follows `ClaudeAgentReadiness` (Review Focus 9): disabled, with `hooksNote` under it, until NotchMeow's hooks are in Claude Code. No test program can run the menu; the build, the review and Task 13 check it.

- [ ] **Step 4: Run the Claude Code tests**

Run: `bash scripts/test-claude-code.sh`
Expected: PASS, seven test programs and no `✗`.

```text
== ClaudeCodeApprovalTests
All tests passed.
== ClaudeCodeEngineTests
All tests passed.
== ClaudeCodeLocatorTests
All tests passed.
== ClaudeCodeParserTests
All tests passed.
== ClaudeCodeProviderTests
All tests passed.
== ClaudeCodeSessionTests
All tests passed.
== ClaudeCodeWiringTests
All tests passed.
```

- [ ] **Step 5: Build both targets**

Run: `(cd NotchBuddy && xcodegen --quiet && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

Run: `(cd NotchBuddy && xcodebuild -scheme NotchMeowAppStore -configuration Debug -derivedDataPath build/store build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj NotchBuddy/Sources/App/ClaudeChatViews.swift NotchBuddy/Sources/App/AI/Core/ClaudeCodeText.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/Sources/App/SettingsView.swift NotchBuddy/Sources/App/AppState.swift tests/ClaudeCodeSessionTests.swift
git commit -q -m "feat(claude-code): the level chip, steps and approval card in the chat, and Connect Claude in Settings" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 12: Mac: the App Store proof (`check-app-binary.sh`)

**Agent:** `nm-implementer-light`. One script, given in full. The point of the task is that the check can fail both ways, so Steps 5 and 6 are not optional.

**Files:**
- Modify: `scripts/check-app-binary.sh`

**Interfaces:**
- Consumes: the three builds of the app (Debug, the App Store target, Release) and the strings only the engine has: `--include-partial-messages` (its command line), `CLAUDE_CODE_OAUTH_TOKEN` (the variable it strips) and `runs your installed Claude Code` (its note, shown on the plan card).
- Produces: `bash scripts/check-app-binary.sh <app> [release|appstore|debug]`, with these meanings:
  - `appstore` (a build of the App Store target, even in Debug): no cat panel, no Debug-only path override, and **none** of the three engine strings, so the engine, the locator and the plan card are compiled out;
  - `release` (the Developer ID build, CI's check): no cat panel, no override, no AI base-URL override, and **all three** engine strings (a build that lost the engine fails too);
  - `debug`: the cat panel, the override and the engine must all be there, so the other two modes can fail.
  All modes still require FoundationModels weak-linked (the app must launch on macOS 15). Marker strings are checked on the whole binary, once.

- [ ] **Step 1: Build the Release app and the App Store app**

The Debug app from Task 11 is already in `NotchBuddy/build/debug` and the App Store app in `NotchBuddy/build/store`; build them again so this task stands alone, and build Release without signing.

Run: `(cd NotchBuddy && xcodegen --quiet && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

Run: `(cd NotchBuddy && xcodebuild -scheme NotchMeowAppStore -configuration Debug -derivedDataPath build/store build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

Run: `(cd NotchBuddy && xcodebuild -scheme NotchBuddy -configuration Release -derivedDataPath build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD" | head -5)`
Expected: PASS, `** BUILD SUCCEEDED **`.

- [ ] **Step 2: See the gap in today's script**

The Release app is the Developer ID build: it contains the engine. Today's `appstore` mode only looks for the cat panel, so it lets that build through.

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app appstore`
Expected: PASS, `✓ No cat panel in this build`. That is the bug: an App Store check must not accept a build that contains the engine.

- [ ] **Step 3: Write the new script**

**Edit `scripts/check-app-binary.sh`**, find this text (it occurs exactly once):

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
    "")
        # No mode argument provided: just run the shared checks (FoundationModels)
```

and replace it with:

```bash
#!/usr/bin/env bash
# Checks a built NotchMeow.app: FoundationModels weak-linked (the app must launch on macOS 15), and, for Release builds,
# the Debug-only AI base-URL override compiled out.
# `release` is the CI check: it also fails when FoundationModels isn't linked at all, which means the
# SDK had none and the Apple on-device provider was silently compiled out. It also fails when the Debug-only
# cat panel (CatDevPanel.swift, marked NM_CAT_DEV_PANEL) or the Debug-only Claude Code path override is in the binary, and
# when the Claude Code engine is missing (the Developer ID build ships it).
# `appstore` is for a build of the App Store target, even in its Debug configuration: no cat panel either, and no
# Claude Code engine, locator or plan card (the App Store build offers only the API-key path).
# `debug` is the other half of that proof: a Debug build must contain the cat panel, the engine and the override, so the
# checks above can fail.
# Usage: bash scripts/check-app-binary.sh path/to/NotchMeow.app [release|appstore|debug]
set -euo pipefail
APP="$1"
BINS=("$APP"/Contents/MacOS/NotchMeow*)   # Debug builds put the code in NotchMeow.debug.dylib
[ -e "${BINS[0]}" ] || { echo "No binary in $APP/Contents/MacOS" >&2; exit 1; }
STRINGS="$(mktemp "${TMPDIR:-/tmp}/nm-binary-strings.XXXXXX")"
trap 'rm -f "$STRINGS"' EXIT
weak=0
for BIN in "${BINS[@]}"; do
    if grep -q FoundationModels < <(otool -l "$BIN" | grep -A2 'LC_LOAD_DYLIB$'); then
        echo "✗ $(basename "$BIN") links FoundationModels strongly: NotchMeow would not launch on macOS 15" >&2
        exit 1
    fi
    if grep -q FoundationModels < <(otool -l "$BIN" | grep -A2 'LC_LOAD_WEAK_DYLIB'); then weak=1; fi
    strings "$BIN" >> "$STRINGS"
done
has() { grep -qF -- "$1" "$STRINGS"; }
panel=0; has NM_CAT_DEV_PANEL && panel=1
override=0; has NM_CLAUDE_CODE_PATH_OVERRIDE && override=1
# What only the Claude Code engine has: its command line, the variable it strips, the plan card's note.
engine_missing=0
for text in "--include-partial-messages" "CLAUDE_CODE_OAUTH_TOKEN" "runs your installed Claude Code"; do
    has "$text" || engine_missing=$((engine_missing + 1))
done
if [ "${2:-}" = "release" ] && has NM_AI_BASE_URL_OVERRIDE; then
    echo "✗ this build still reads NM_AI_BASE_URL_OVERRIDE" >&2
    exit 1
fi
case "${2:-}" in
    release)
        [ "$panel" = 0 ] || { echo "✗ the Debug-only cat panel (NM_CAT_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is in this build" >&2; exit 1; }
        [ "$engine_missing" = 0 ] || { echo "✗ the Claude Code engine is missing from this build" >&2; exit 1; }
        echo "✓ No cat panel and no Claude Code override in this build; the Claude Code engine is in it" ;;
    appstore)
        [ "$panel" = 0 ] || { echo "✗ the Debug-only cat panel (NM_CAT_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override is in this build" >&2; exit 1; }
        [ "$engine_missing" = 3 ] || { echo "✗ part of the Claude Code engine (its command line, environment or plan card) is in the App Store build" >&2; exit 1; }
        echo "✓ No cat panel and no Claude Code engine in this build" ;;
    debug)
        [ "$panel" = 1 ] || { echo "✗ the cat panel (NM_CAT_DEV_PANEL) is missing from this Debug build" >&2; exit 1; }
        [ "$override" = 1 ] || { echo "✗ the Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is missing from this Debug build" >&2; exit 1; }
        [ "$engine_missing" = 0 ] || { echo "✗ the Claude Code engine is missing from this Debug build" >&2; exit 1; }
        echo "✓ The cat panel, the Claude Code engine and its override are in this Debug build" ;;
    "")
        # No mode argument provided: just run the shared checks (FoundationModels)
```

- [ ] **Step 4: The same command now fails**

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app appstore`
Expected: FAIL, `✗ part of the Claude Code engine (its command line, environment or plan card) is in the App Store build`.

- [ ] **Step 5: Each build passes its own check**

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore`
Expected: PASS, `✓ No cat panel and no Claude Code engine in this build`.

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app release`
Expected: PASS, `✓ No cat panel and no Claude Code override in this build; the Claude Code engine is in it`.

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/debug/Build/Products/Debug/NotchMeow.app debug`
Expected: PASS, `✓ The cat panel, the Claude Code engine and its override are in this Debug build`.

- [ ] **Step 6: Each check can fail the other way**

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app release`
Expected: FAIL, `✗ the Claude Code engine is missing from this build`: a Developer ID build that lost the engine would be caught.

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app debug`
Expected: FAIL, `✗ the cat panel (NM_CAT_DEV_PANEL) is missing from this Debug build`.

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/debug/Build/Products/Debug/NotchMeow.app release`
Expected: FAIL, `✗ this build still reads NM_AI_BASE_URL_OVERRIDE` (the first Debug-only string it meets; the cat panel and the path override would fail it too): a Debug build is never accepted as a release.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-app-binary.sh
git commit -q -m "test(app-store): check-app-binary proves the App Store build has no Claude Code engine, and the other builds do" -m "Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```


### Task 13: Owner checkpoint: the Mac

**Who:** the main session runs Steps 1 and 2 and shows the results to the owner; no implementer agent. Nothing here changes code. Step 3 is the owner's own manual check on a Debug build, after quitting the installed app: no session ever launches, quits or replaces any NotchMeow app, and none ever runs `claude` or touches the owner's Claude account. Parts A and B of Step 3 need Claude Code installed only for B.

**What the owner gets:** the Mac side of E3 finished and proved by tests and builds, a way to click through every state with the fake `claude` and no account, and a list of what only a real Claude Code can confirm (the shapes of the failures the docs do not give, and whether Agent mode's sandbox runs a command without asking). The owner's answers decide whether Windows/Linux (Tasks 14 to 19) starts as planned.

- [ ] **Step 1: The evidence**

From the branch's top folder, and show the last lines of each:

```bash
bash scripts/test-ai-contract.sh
bash scripts/test-claude-code.sh
bash scripts/test-session-steps.sh
for s in scripts/test-ai-*.sh; do bash "$s" > /dev/null 2>&1 && echo "ok $s" || echo "FAILED $s"; done
```

Expected: no `✗`, no `FAILED`. Then the three builds and the three binary checks of Task 12, with the output lines of `scripts/check-app-binary.sh` for `appstore`, `release` and `debug`, and `git log --oneline e3/connect-claude ^notchmeow/rebrand` (Tasks 1 to 12).

- [ ] **Step 2: The Debug app and the fake**

Build it (Task 12 already did: `NotchBuddy/build/debug/Build/Products/Debug/NotchMeow.app`). The Debug build reads `NM_CLAUDE_CODE_PATH_OVERRIDE`, which points the app at the fake `claude` instead of the real one (a Release build contains no such thing). The fake's behaviour is set by environment variables the app passes on; `open --env` sets them for one launch. For example, a turn that uses tools:

```bash
F="$PWD/tests/fixtures/ai/claude-code"
open -n --env NM_CLAUDE_CODE_PATH_OVERRIDE="$F/fake_claude.py" --env NM_FAKE_CLAUDE_TRANSCRIPT="$F/transcripts/tool-use.jsonl" NotchBuddy/build/debug/Build/Products/Debug/NotchMeow.app
```

Print these launch lines for the owner, one per transcript below. The main session does not run them.

- [ ] **Step 3: What the owner checks**

**A. With the fake (no account, no Claude Code needed).** Quit the installed NotchMeow first. For each line below relaunch with the transcript named, then open Settings → AI and the chat.

| Launch with | Do | Expected |
|---|---|---|
| `transcripts/success.jsonl` | Settings → AI → Connect Claude → **Use my Claude plan**; ask anything | a check mark, the version "2.1.211" and "signed in with your Claude plan"; the model chip says "Claude · your plan"; the level chip says "Chat only"; a streamed answer |
| `transcripts/tool-use.jsonl` | ask anything | step rows above the answer ("Lit · …", one marked ⚠), in the session view's own words; the answer reads as paragraphs |
| `transcripts/signed-out.jsonl` plus `NM_FAKE_CLAUDE_AUTH_EXIT=1` and `NM_FAKE_CLAUDE_AUTH_JSON='{"authMethod":"none"}'` | Settings shows **Sign in**; click it | Terminal opens and runs the fake's `auth login` (the fake logs it and exits); in the chat a signed-out run says "Claude Code is signed out." with a Sign in button |
| `transcripts/plan-limit.jsonl` | ask anything | the cat's rate-limit look and "Your Claude plan's limit resets at …" in your time zone, no billing button |
| `transcripts/offline.jsonl` | ask anything | "Couldn't reach Claude."; with a local model set up, Auto falls back to it like any cloud failure |
| `transcripts/crash.jsonl` | ask anything | "Claude stopped unexpectedly." with a **Try again** button that sends the same message again |
| `transcripts/success.jsonl`, `NM_FAKE_CLAUDE_ASK_SOCKET="$HOME/Library/Application Support/NotchMeow/nm.sock"` and `NM_FAKE_CLAUDE_LOG="$TMPDIR/fake-claude.jsonl"` | choose **Agent** (pick a folder; the Agent row is enabled once NotchMeow's hooks are installed in Claude Code, as in B4: the "Claude Code Hooks" box in Settings), ask anything | an approval card **in the chat** ("Claude needs permission", `Bash · echo asked-by-the-fake`), not a pill; **Deny** or **Allow** answers it, and the last line of the log file says which |

Also with the fake: the level chip is disabled while a reply streams; **Stop** during a reply leaves no `fake_claude.py` running (`pgrep -fl fake_claude` prints nothing); a new chat (⌘K or a file drop) starts at Chat only.

**B. With your own Claude Code** (sign in once with `claude auth login` in a terminal, as usual; NotchMeow never sees it). Relaunch without any `--env`.

1. **Connect:** Settings → AI → Connect Claude shows the version and "signed in with …". The chip says "Claude · your plan" after the first answer (or "Claude · API key" if an `apiKeyHelper` or `ANTHROPIC_API_KEY` is how your Claude Code is signed in: the chip is what Claude Code reports, never a guess).
2. **Chat only:** ask a question and ask it to search the web. Then ask it to read a file on your disk: it must refuse (it has no file tools).
3. **Read-only:** pick a folder, ask what is in it. Step rows appear. Ask it to create a file: it must refuse, and no file appears.
4. **Agent:** ask it to create `hello.txt` containing `hi`. A card appears in the chat. **Deny**: no file. Ask again, **Allow**: the file exists. If NotchMeow's hooks are not installed in Claude Code, the Agent row says so before you can pick it.
5. **The sandbox question (Review Focus 8):** in Agent, ask it to run a harmless command, `echo sandboxed`. **Did a card appear first?** If it ran without asking, tell the main session: the plan's open question 1 applies.
5b. **A tool the user's own Claude Code settings already allow** (for example a Bash rule): in Agent it runs with no card; this is Claude Code's own rule, not NotchMeow's.
6. **Stop during a tool:** in Agent, ask for `sleep 60`, **Allow**, then **Stop**. In a terminal, `pgrep -fl "sleep 60"` must print nothing a few seconds later, and the step row says "stopped".
7. **Agent back to Chat only:** in Agent, ask about a file in your folder; switch the chip to Chat only; ask "what did you just tell me?". The answer still knows (the chat sent a recap to a new session).
8. **Your own sessions alongside:** with NotchMeow's hooks installed, run `claude` in a terminal in another folder and trigger one of its approvals while a chat is open. It still appears as its own pill and card, and the chat's card never replaces it.
9. **A folder with spaces and accents:** make `~/Desktop/Mes projets/ünï côde`, choose it for Read-only, and ask what is in it.
10. **The shapes the docs do not give (Review Focus and the spec's risks):** sign out (`claude auth logout` in a terminal) and ask: the chat must say "Claude Code is signed out." and offer Sign in. If it says "Claude stopped unexpectedly." instead, the signed-out shape differs from the fixtures: run `claude -p "hi" --output-format stream-json --verbose` yourself, keep the output **in a scratch folder, never in the repo** (it may contain your session id and paths), and tell the main session which line carries the error. Do the same if you ever see a plan limit or an offline run word-for-word different from the notes above.
11. **The API-key path is unchanged:** in Debug and Release builds Settings → AI → Connect Claude → Paste an API key, and in the App Store build the existing "Anthropic API" field; both still save, check and set Claude as the preferred cloud.

- [ ] **Step 4: Ask the owner**

Show Step 1's evidence and the owner's results. Ask: (1) Did the Agent sandbox run a command without a card (open question 1)? (2) Are the words right: "Use my Claude plan", "runs your installed Claude Code", the level names and their one-line explanations? (3) Did any failure show the wrong note (the shapes in B10)? (4) Go for Windows/Linux (Tasks 14 to 19)? A change to a shape or a flag is one edit in `tests/fixtures/ai/claude-code/` and in `reference.py` first, then in `ClaudeCodeEngine.swift` or `ClaudeStreamParser.swift` (their tests fail until they match), and later in the Rust port.


### Task 14: Windows/Linux: the provider ID, catalog, router, errors and settings fields

**Agent:** `nm-implementer`. Small edits in five files of one crate; the compiler finds every struct literal that needs the two new `AiError` fields.

**Files:**
- Modify: `windows/src-tauri/src/ai/catalog.rs`, `router.rs`, `provider.rs`, `errors.rs`
- Modify: `windows/src-tauri/src/settings.rs`

**Interfaces:**
- Consumes: Task 1's fixtures (`providers.json` lists `claudeCode`; `router-cases.json` has nine more cases, 39 in all).
- Produces, for Tasks 15 to 18:
  - `catalog::Api::ClaudeCode` (`"claude-code"`) and the `PROVIDERS` row `claudeCode`: name "Claude plan", cloud, no key, no URL, default model `sonnet`; `catalog::is_cloud("claudeCode")` is true; `brand` says "Claude"; `reads_pdf_natively("claudeCode")` is true; `keychain_name("claudeCode")` is `None` (a key there would be a login).
  - `router::cloud_choice`: the preferred cloud, then the others of `claudeCode`, `anthropic`, `openai`, then `google`, the first that is in `keys`; `keys` holds `claudeCode` only when it is ready (Task 17 decides).
  - In `provider.rs`: `Step { id, tool, input: BTreeMap<String, String>, state: StepState }` (`StepState`: Running, Done, Failed, Stopped; serialises lower-case), `Payer` (Plan, ApiKey, Unknown; serialises `plan`, `api_key`, `unknown`), `EngineReport { session_id, model, paid_by, version }` (camelCase), `ChatChunk::Step(Step)` and `ChatChunk::Engine(EngineReport)`, and `AiError { …, resets_at: Option<u64>, after_steps: bool }` (Unix seconds; "steps were taken, so no other model").
  - `settings::AiSettings { claude_code_enabled: bool, claude_code_model: String }` (saved as `claudeCodeEnabled` and `claudeCodeModel`; an old `settings.json` without them loads with `false` and `"sonnet"`), and `preferred_cloud` may be `"claudeCode"`.

- [ ] **Step 1: Write the failing tests**

The catalog test pins the row; the router test's count of fixture cases changes from 30 to 39 on purpose.

**Edit `windows/src-tauri/src/ai/catalog.rs`**, find this text (it occurs exactly once):

```rust
            Api::OpenAIChat => "openai-chat",
            Api::Apple => "apple",
        }
    }
```

and replace it with:

```rust
            Api::OpenAIChat => "openai-chat",
            Api::Apple => "apple",
            Api::ClaudeCode => "claude-code",
        }
    }
```

**Edit `windows/src-tauri/src/ai/catalog.rs`**, find this text (it occurs exactly once):

```rust
        keychain_key: Some("custom-server-key"), default_model: None,
    },
];

```

and replace it with:

```rust
        keychain_key: Some("custom-server-key"), default_model: None,
    },
    ProviderDef {
        id: "claudeCode", name: "Claude plan", placement: CatalogPlacement::Cloud, api: Api::ClaudeCode,
        base_url: None, port: None, probe_path: None, chat_path: None, models_path: None,
        keychain_key: None, default_model: Some("sonnet"),
    },
];

```

**Edit `windows/src-tauri/src/ai/catalog.rs`**, find this text (it occurs exactly once):

```rust
}

pub fn is_cloud(id: &str) -> bool {
    CLOUD_ORDER.contains(&id)
}

/// The name used in "… is busy" and "… will read this": the product for Claude,
/// the company otherwise.
pub fn brand(id: &str) -> &'static str {
    match id {
        "anthropic" => "Claude",
        other => get(other).map(|p| p.name).unwrap_or("The server"),
    }
```

and replace it with:

```rust
}

/// The cloud providers, and Claude Code, which runs on Anthropic's servers through the user's own program.
pub fn is_cloud(id: &str) -> bool {
    CLOUD_ORDER.contains(&id) || id == "claudeCode"
}

/// The name used in "… is busy" and "… will read this": the product for Claude,
/// the company otherwise.
pub fn brand(id: &str) -> &'static str {
    match id {
        "anthropic" | "claudeCode" => "Claude",
        other => get(other).map(|p| p.name).unwrap_or("The server"),
    }
```

**Edit `windows/src-tauri/src/ai/catalog.rs`**, find this text (it occurs exactly once):

```rust
/// Anthropic and OpenAI take PDFs as-is; everyone else gets extracted text.
pub fn reads_pdf_natively(provider: &str) -> bool {
    provider == "anthropic" || provider == "openai"
}

```

and replace it with:

```rust
/// Anthropic and OpenAI take PDFs as-is; everyone else gets extracted text.
pub fn reads_pdf_natively(provider: &str) -> bool {
    provider == "anthropic" || provider == "openai" || provider == "claudeCode"
}

```

**Edit `windows/src-tauri/src/ai/catalog.rs`**, find this text (it occurs exactly once):

```rust
    }

    #[test]
    fn local_servers_are_the_catalog_ports_in_order() {
```

and replace it with:

```rust
    }

    #[test]
    fn claude_code_is_cloud_without_a_key_or_a_url() {
        let def = get("claudeCode").unwrap();
        assert_eq!((def.placement, def.api, def.keychain_key, def.base_url), (CatalogPlacement::Cloud, Api::ClaudeCode, None, None));
        assert!(is_cloud("claudeCode") && reads_pdf_natively("claudeCode"));
        assert_eq!(brand("claudeCode"), "Claude");
        assert_eq!(default_model("claudeCode", &[]).as_deref(), Some("sonnet"));
        assert_eq!(keychain_name("claudeCode"), None, "there is no key to read: a key would be a login");
        assert_eq!(placement_of("claudeCode", None), Placement::Cloud);
    }

    #[test]
    fn local_servers_are_the_catalog_ports_in_order() {
```

**Edit `windows/src-tauri/src/ai/router.rs`**, find this text (it occurs exactly once):

```rust
        let data = testkit::load_json("router-cases.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 30, "router-cases.json changed: update this count on purpose");
        for case in cases {
            let mut input = data["defaults"].clone();
```

and replace it with:

```rust
        let data = testkit::load_json("router-cases.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 39, "router-cases.json changed: update this count on purpose");
        for case in cases {
            let mut input = data["defaults"].clone();
```

- [ ] **Step 2: Run them to see them fail**

Run: `$CL test -p notchmeow --target-dir $TD -- ai::catalog ai::router`
Expected: FAIL, a compile error: no variant `ClaudeCode` on `Api`.

```text
error[E0599]: no variant, associated function, or constant named `ClaudeCode` found for enum `ai::catalog::Api` in the current scope
error[E0599]: no variant, associated function, or constant named `ClaudeCode` found for enum `Api` in the current scope
error[E0599]: no variant, associated function, or constant named `ClaudeCode` found for enum `ai::catalog::Api` in the current scope
```

- [ ] **Step 3: Write the catalog row, the router order, the types and the fields**

**Edit `windows/src-tauri/src/ai/catalog.rs`**, find this text (it occurs exactly once):

```rust
    OpenAIChat,
    Apple,
}

```

and replace it with:

```rust
    OpenAIChat,
    Apple,
    /// The user's own Claude Code, run as a process (never a URL).
    ClaudeCode,
}

```

**Edit `windows/src-tauri/src/ai/router.rs`**, find this text (it occurs exactly once):

```rust
}

/// The Preferred cloud, then the other of Claude/OpenAI, then Google — the first with a key.
pub fn cloud_choice(input: &RouteInput) -> Option<String> {
    let preferred = input.preferred_cloud.as_str();
    let mut order = vec![preferred];
    order.extend(["anthropic", "openai"].into_iter().filter(|p| *p != preferred));
    order.push("google");
    order.into_iter().find(|p| input.keys.iter().any(|k| k == p)).map(str::to_string)
```

and replace it with:

```rust
}

/// The Preferred cloud, then the others of Claude plan / Claude API / OpenAI, then Google — the first that is ready.
/// `keys` holds the cloud providers with a key, plus `claudeCode` when the user connected it and the last check found
/// Claude Code signed in.
pub fn cloud_choice(input: &RouteInput) -> Option<String> {
    let preferred = input.preferred_cloud.as_str();
    let mut order = vec![preferred];
    order.extend(["claudeCode", "anthropic", "openai"].into_iter().filter(|p| *p != preferred));
    order.push("google");
    order.into_iter().find(|p| input.keys.iter().any(|k| k == p)).map(str::to_string)
```

**Edit `windows/src-tauri/src/ai/provider.rs`**, find this text (it occurs exactly once):

```rust
}

#[derive(Debug, Clone, PartialEq)]
pub enum ChatChunk {
```

and replace it with:

```rust
}

/// One tool step Claude Code takes on its own (reading a file, running a command), shown as a row in the chat.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Step {
    pub id: String,
    pub tool: String,
    /// Only the fields that say what the step does (command, file_path, path, query, pattern, url), each cut to 200
    /// Unicode scalars: never a file's content.
    pub input: std::collections::BTreeMap<String, String>,
    pub state: StepState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum StepState {
    Running,
    Done,
    Failed,
    Stopped,
}

/// Who pays for a Claude Code run, as its own first event says.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Payer {
    Plan,
    ApiKey,
    Unknown,
}

/// What a Claude Code run says about itself in `system/init`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EngineReport {
    pub session_id: String,
    pub model: String,
    pub paid_by: Payer,
    pub version: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ChatChunk {
```

**Edit `windows/src-tauri/src/ai/provider.rs`**, find this text (it occurs exactly once):

```rust
    Finish(Finish),
    Error(ErrorKind),
}

```

and replace it with:

```rust
    Finish(Finish),
    Error(ErrorKind),
    /// A step Claude Code is taking, or has finished (the same `id` updates the same row).
    Step(Step),
    /// What the engine reported about the run it started.
    Engine(EngineReport),
}

```

**Edit `windows/src-tauri/src/ai/provider.rs`**, find this text (it occurs exactly once):

```rust
    /// The provider's error code, e.g. `insufficient_quota`.
    pub code: Option<String>,
}

impl AiError {
    pub fn new(kind: ErrorKind) -> Self {
        AiError { kind, status: None, retry_after: None, request_id: None, detail: None, code: None }
    }
}
```

and replace it with:

```rust
    /// The provider's error code, e.g. `insufficient_quota`.
    pub code: Option<String>,
    /// When a usage limit resets, in Unix seconds (the Claude plan's limit), so the chat can say when.
    pub resets_at: Option<u64>,
    /// Claude Code took steps before it failed: whatever they did stays done, so Auto must not hand the
    /// question to another model.
    pub after_steps: bool,
}

impl AiError {
    pub fn new(kind: ErrorKind) -> Self {
        AiError { kind, status: None, retry_after: None, request_id: None, detail: None, code: None, resets_at: None, after_steps: false }
    }
}
```

**Edit `windows/src-tauri/src/ai/errors.rs`**, find this text (it occurs exactly once):

```rust
        detail: error_field(body.as_ref(), "message").map(|m| m.chars().take(200).collect()),
        code: error_field(body.as_ref(), "code").map(str::to_string),
    }
}
```

and replace it with:

```rust
        detail: error_field(body.as_ref(), "message").map(|m| m.chars().take(200).collect()),
        code: error_field(body.as_ref(), "code").map(str::to_string),
        resets_at: None,
        after_steps: false,
    }
}
```

**Edit `windows/src-tauri/src/settings.rs`**, find this text (it occurs exactly once):

```rust
    /// Which model answers questions about a dropped file.
    pub files: Choice,
    /// "anthropic" or "openai": the cloud Auto tries first.
    pub preferred_cloud: String,
    /// Remembered model per cloud provider, e.g. {"anthropic": "claude-opus-5"}.
```

and replace it with:

```rust
    /// Which model answers questions about a dropped file.
    pub files: Choice,
    /// "claudeCode", "anthropic" or "openai": the cloud Auto tries first.
    pub preferred_cloud: String,
    /// Remembered model per cloud provider, e.g. {"anthropic": "claude-opus-5"}.
```

**Edit `windows/src-tauri/src/settings.rs`**, find this text (it occurs exactly once):

```rust
    /// The server added with "Add server…", e.g. "http://studio-pc:11434".
    pub custom_server: Option<String>,
}

```

and replace it with:

```rust
    /// The server added with "Add server…", e.g. "http://studio-pc:11434".
    pub custom_server: Option<String>,
    /// The user connected "Use my Claude plan": Auto may use it while the last check finds Claude Code signed in.
    pub claude_code_enabled: bool,
    /// Claude Code's model alias for the chat: sonnet, opus or haiku.
    pub claude_code_model: String,
}

```

**Edit `windows/src-tauri/src/settings.rs`**, find this text (it occurs exactly once):

```rust
            last_used_local: None,
            custom_server: None,
        }
    }
```

and replace it with:

```rust
            last_used_local: None,
            custom_server: None,
            claude_code_enabled: false,
            claude_code_model: "sonnet".into(),
        }
    }
```

- [ ] **Step 4: Run the AI and settings tests**

Run: `$CL test -p notchmeow --target-dir $TD -- ai:: settings::`
Expected: PASS, `test result: ok.` and no `FAILED`.

```text
test result: ok. 132 passed; 0 failed; 0 ignored; 0 measured; 3 filtered out; finished in 6.63s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/ai/catalog.rs windows/src-tauri/src/ai/router.rs windows/src-tauri/src/ai/provider.rs windows/src-tauri/src/ai/errors.rs windows/src-tauri/src/settings.rs
git commit -q -m "feat(claude-code): the Claude plan is a cloud provider in the Windows/Linux catalog and router" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 15: Windows/Linux: `claude_code.rs`, the command line, the environment and the transcript

**Agent:** `nm-implementer`. The Rust port of Tasks 4 and 5, held to the same fixtures; the Swift files are the reference to read, `reference.py` the tie-breaker.

**Files:**
- Create: `windows/src-tauri/src/ai/claude_code.rs` (its tests are in the file, as in every module of this crate)
- Modify: `windows/src-tauri/src/ai/mod.rs` (`pub mod claude_code;`), `errors.rs` (five `Action` variants and the Claude Code wording), `windows/src-tauri/src/settings.rs` (the model alias is sanitised)

**Interfaces:**
- Consumes: Task 14's `Step`, `Payer`, `EngineReport`, `ChatChunk::Step/Engine`, `AiError { resets_at, after_steps }`; Task 2's fixtures; `Part`, `file_text`, `Wording`, `Action` (existing).
- Produces, in `ai::claude_code` (no `cfg` gate: this crate has no App Store build):

  ```rust
  pub const MODELS: [&str; 3];  pub fn model_or_default(alias: &str) -> String;        // sonnet, opus, haiku; anything else is sonnet
  pub const MISSING, SIGNED_OUT, PLAN_LIMIT, TOO_OLD, CRASHED, OFFLINE, NEEDS_GIT, FOLDER_MISSING: &str;   // "nm_…", on AiError::code
  pub enum Platform { Mac, Linux, Windows }  impl Platform { pub fn current() -> Self }
  pub enum Level { ChatOnly, ReadOnly(String), Agent(String) }  impl Level { pub fn key(&self) -> &'static str; pub fn folder(&self) -> Option<&str> }
  pub struct Turn { pub level: Level, pub model: String, pub session_id: String, pub resume: bool, pub platform: Platform }
  pub fn arguments(turn: &Turn) -> Vec<String>;   pub fn working_directory(turn: &Turn, chat_folder: &str) -> String;
  pub fn environment(base: impl IntoIterator<Item = (String, String)>, platform: Platform) -> Vec<(String, String)>;
  pub fn user_line(parts: &[Part], preamble: Option<&str>) -> String;                   // one JSON line, with its "\n"
  pub struct Stream { … }  impl Stream { pub fn new() -> Self; pub fn text(&self) -> &str; pub fn took_steps(&self) -> bool; pub fn engine(&self) -> Option<&EngineReport>;
      pub fn consume(&mut self, line: &str) -> Vec<ChatChunk>;  pub fn failure(&self, stderr: &str) -> Option<AiError> }
  pub fn wording(err: &AiError) -> Option<Wording>;     // the note and its one button for each code
  ```

  `errors::Action` gains `SignInClaude, InstallClaude, UpdateClaude, InstallGit, TryAgain`, and `errors::error_copy` answers a `claudeCode` provider's error with `claude_code::wording`. The rules are the Swift parser's: text of separate assistant messages joined by a blank line; a step keeps only the six fields, each cut to 200 Unicode scalars; exit status is never read; anything unrecognised is `nm_claude_crashed`. The time of a plan limit is not formatted here: the webview does it in the viewer's time zone and locale, from `resets_at` (Task 18). On native Windows names are compared without regard to case when the environment is cleaned, and Agent passes no sandbox settings: every command asks.

- [ ] **Step 1: Write the failing tests**

The module is declared, and the file holds only its tests: every case of `expected-args.json`, `expected-env.json` and `expected-parse.json` (including a folder with spaces and non-ASCII characters, Windows paths, a Windows environment with mixed-case variable names, the Git for Windows stderr, the unknown `apiKeySource`), the stdin line, tolerance, and the words of each failure. They pin Review Focus 5 (the payer), 6 (the folder), 7 (the Git for Windows stderr gives "Claude Code needs Git for Windows") and 10 (paragraphs) on the Rust side.

**Edit `windows/src-tauri/src/ai/mod.rs`**, find this text (it occurs exactly once):

```rust
pub mod budget;
pub mod catalog;
pub mod discovery;
pub mod errors;
```

and replace it with:

```rust
pub mod budget;
pub mod catalog;
pub mod claude_code;
pub mod discovery;
pub mod errors;
```

**Create `windows/src-tauri/src/ai/claude_code.rs`** with exactly this content (only its tests for now):

```rust
// Claude Code as an engine, the pure parts: the levels, the command line of one turn, the environment it runs in, the
// message written to its stdin, what its stream-json output means, and the words of each failure. Nothing here starts a
// process (`claude_run.rs` does). It mirrors NotchBuddy/Sources/App/AI/Core/ClaudeCode*.swift: both apps are held to
// tests/fixtures/ai/claude-code/, and `reference.py` there is the tie-breaker.
//
// The exact JSON of Claude Code's failures is not documented, so the parser is tolerant on purpose: a line that is not
// JSON, or an event it does not know, is skipped; a run that ends without a result and without a failure it recognises
// is "Claude stopped unexpectedly", never a guess at what went wrong.

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;

    fn level(key: &str, folder: Option<&str>) -> Level {
        match key {
            "read" => Level::ReadOnly(folder.unwrap_or("").to_string()),
            "agent" => Level::Agent(folder.unwrap_or("").to_string()),
            _ => Level::ChatOnly,
        }
    }

    fn platform(name: &str) -> Platform {
        match name {
            "windows" => Platform::Windows,
            "linux" => Platform::Linux,
            _ => Platform::Mac,
        }
    }

    #[test]
    fn the_command_line_of_every_level_and_turn() {
        let data = testkit::load_json("claude-code/expected-args.json");
        let chat_folder = data["chatFolder"].as_str().unwrap();
        assert_eq!(MODELS.to_vec(), data["models"].as_array().unwrap().iter().map(|m| m.as_str().unwrap()).collect::<Vec<_>>());
        for c in data["cases"].as_array().unwrap() {
            let name = c["name"].as_str().unwrap();
            let turn = Turn {
                level: level(c["level"].as_str().unwrap(), c["folder"].as_str()),
                model: c["model"].as_str().unwrap().to_string(),
                session_id: c["sessionId"].as_str().unwrap().to_string(),
                resume: c["resume"].as_bool().unwrap(),
                platform: platform(c["platform"].as_str().unwrap()),
            };
            let argv = arguments(&turn);
            let want: Vec<String> = c["argv"].as_array().unwrap().iter().map(|a| a.as_str().unwrap().to_string()).collect();
            assert_eq!(argv, want, "{name}");
            let cwd = working_directory(&turn, chat_folder);
            let expected = if c["cwd"] == "chatFolder" { chat_folder } else { c["folder"].as_str().unwrap() };
            assert_eq!(cwd, expected, "{name}: runs in");
            if let Some(folder) = c["folder"].as_str() {
                assert!(!argv.iter().any(|a| a.contains(folder)), "{name}: the folder is an argument");
            }
            assert!(!argv.iter().any(|a| a == "--bare"), "{name}: --bare breaks subscription auth");
        }
    }

    #[test]
    fn the_environment_of_a_run() {
        let data = testkit::load_json("claude-code/expected-env.json");
        let names: Vec<&str> = data["stripped"].as_array().unwrap().iter().map(|n| n.as_str().unwrap()).collect();
        assert_eq!(STRIPPED.to_vec(), names);
        assert_eq!(STRIPPED_PREFIXES.to_vec(), vec![data["strippedPrefixes"][0].as_str().unwrap()]);
        for c in data["cases"].as_array().unwrap() {
            let pairs = |v: &Value| -> BTreeMap<String, String> {
                v.as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_str().unwrap().to_string())).collect()
            };
            let got: BTreeMap<String, String> = environment(pairs(&c["base"]), platform(c["platform"].as_str().unwrap())).into_iter().collect();
            assert_eq!(got, pairs(&c["expect"]), "{}", c["name"]);
        }
    }

    #[test]
    fn a_model_alias_from_settings_is_one_of_claude_codes() {
        assert_eq!((model_or_default("opus"), model_or_default("gpt-6"), model_or_default("")), ("opus".to_string(), "sonnet".to_string(), "sonnet".to_string()));
    }

    #[test]
    fn the_message_on_stdin() {
        let line = user_line(
            &[
                Part::FileText { name: "notes.txt".into(), text: "hello".into() },
                Part::Image { name: "a.png".into(), mime: "image/png".into(), base64: "iVBO".into() },
                Part::Pdf { name: "a.pdf".into(), base64: "JVBE".into() },
                Part::Text("What is in these? Zoé 🐱".into()),
            ],
            None,
        );
        assert!(line.ends_with('\n') && !line[..line.len() - 1].contains('\n'), "one line");
        let json: Value = serde_json::from_str(&line).unwrap();
        assert_eq!((json["type"].as_str(), json["message"]["role"].as_str()), (Some("user"), Some("user")));
        assert!(json["parent_tool_use_id"].is_null());
        let blocks = json["message"]["content"].as_array().unwrap();
        let types: Vec<&str> = blocks.iter().map(|b| b["type"].as_str().unwrap()).collect();
        assert_eq!(types, ["text", "image", "document", "text"]);
        assert_eq!(blocks[0]["text"], "File: notes.txt\n\nhello");
        assert_eq!(blocks[3]["text"], "What is in these? Zoé 🐱");
        let recap: Value = serde_json::from_str(&user_line(&[Part::Text("and now?".into())], Some("Earlier in this chat: …"))).unwrap();
        let texts: Vec<&str> = recap["message"]["content"].as_array().unwrap().iter().map(|b| b["text"].as_str().unwrap()).collect();
        assert_eq!(texts, ["Earlier in this chat: …", "and now?"], "a recap comes first");
    }

    /// A whole run folded the way the chat sees it.
    fn fold(lines: &str, stderr: &str) -> (Option<EngineReport>, String, Vec<Step>, Option<Finish>, Option<AiError>) {
        let mut stream = Stream::new();
        let (mut engine, mut text, mut steps, mut finish) = (None, String::new(), Vec::<Step>::new(), None);
        for line in lines.lines().filter(|l| !l.is_empty()) {
            for chunk in stream.consume(line) {
                match chunk {
                    ChatChunk::Engine(r) => engine = Some(r),
                    ChatChunk::Text(t) => text.push_str(&t),
                    ChatChunk::Finish(f) => finish = Some(f),
                    ChatChunk::Step(s) => match steps.iter_mut().find(|x| x.id == s.id) {
                        Some(old) => *old = s,
                        None => steps.push(s),
                    },
                    _ => {}
                }
            }
        }
        (engine, text, steps, finish, stream.failure(stderr))
    }

    #[test]
    fn what_a_transcript_means() {
        let data = testkit::load_json("claude-code/expected-parse.json");
        let sid = data["sessionId"].as_str().unwrap();
        for c in data["cases"].as_array().unwrap() {
            let name = c["name"].as_str().unwrap();
            let path = testkit::fixtures_dir().join("claude-code/transcripts").join(c["transcript"].as_str().unwrap());
            let raw = std::fs::read_to_string(path).unwrap().replace("__SESSION_ID__", sid).replace("__CWD__", data["cwd"].as_str().unwrap());
            let (engine, text, steps, finish, error) = fold(&raw, c["stderr"].as_str().unwrap());
            let expect = &c["expect"];
            match expect["engine"].as_object() {
                Some(e) => {
                    let got = engine.unwrap_or_else(|| panic!("{name}: no engine report"));
                    assert_eq!(
                        (got.session_id.as_str(), got.model.as_str(), serde_json::to_value(got.paid_by).unwrap(), got.version.as_deref()),
                        (sid, e["model"].as_str().unwrap(), e["paidBy"].clone(), e["version"].as_str()),
                        "{name}: engine"
                    );
                }
                None => assert!(engine.is_none(), "{name}: no engine report"),
            }
            assert_eq!(text, expect["text"].as_str().unwrap(), "{name}: text");
            let want_steps: Vec<(String, String, BTreeMap<String, String>, String)> = expect["steps"]
                .as_array()
                .unwrap()
                .iter()
                .map(|s| {
                    let input = s["input"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_str().unwrap().to_string())).collect();
                    (s["id"].as_str().unwrap().into(), s["tool"].as_str().unwrap().into(), input, s["state"].as_str().unwrap().into())
                })
                .collect();
            let got_steps: Vec<_> =
                steps.iter().map(|s| (s.id.clone(), s.tool.clone(), s.input.clone(), serde_json::to_value(s.state).unwrap().as_str().unwrap().to_string())).collect();
            assert_eq!(got_steps, want_steps, "{name}: steps");
            assert_eq!(finish.map(|f| serde_json::to_value(f).unwrap()), expect["finish"].as_str().map(|f| json!(f)), "{name}: finish");
            match expect["error"].as_object() {
                Some(e) => {
                    let err = error.unwrap_or_else(|| panic!("{name}: no error"));
                    assert_eq!(serde_json::to_value(err.kind).unwrap(), e["kind"], "{name}: error kind");
                    assert_eq!(err.code.as_deref(), e["code"].as_str(), "{name}: error code");
                    assert_eq!(err.resets_at, e["resetsAt"].as_u64(), "{name}: resets at");
                }
                None => assert!(error.is_none(), "{name}: no error"),
            }
        }
    }

    #[test]
    fn tolerance() {
        let (_, text, _, _, error) = fold("\nnot json\n[1,2]\n{\"type\":\"mystery\"}\n{\"type\":\"stream_event\"}\n{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"hi\"}}}", "");
        assert_eq!(text, "hi", "junk lines are skipped and the text survives");
        assert_eq!(error.unwrap().code.as_deref(), Some(CRASHED), "a run with no result is a crash");

        let (.., error) = fold("{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"rejected\",\"resetsAt\":\"soon\"}}\n{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":true,\"result\":\"limit\"}", "");
        let error = error.unwrap();
        assert_eq!((error.code.as_deref(), error.resets_at), (Some(PLAN_LIMIT), None), "a rejection with a time we cannot read is still the plan's limit");

        let (.., error) = fold("{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"allowed_warning\",\"resetsAt\":1791301500}}\n{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"ok\"}", "");
        assert!(error.is_none(), "a warning is not a failure");

        let long = "é".repeat(300);
        let lines = format!(
            "{}\n{}\n{}",
            r#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"Bash","input":{}}}}"#,
            json!({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":long,"timeout":5000,"content":"secret"}}]}}),
            r#"{"type":"result","subtype":"success","is_error":false,"result":""}"#
        );
        let (_, _, steps, ..) = fold(&lines, "");
        assert_eq!(steps[0].input["command"].chars().count(), 200, "a step's input is cut to 200 scalars");
        assert_eq!(steps[0].input.keys().collect::<Vec<_>>(), ["command"], "and keeps only the fields that name the work");
        assert_eq!(steps[0].state, StepState::Running, "a tool use the result never answered stays running");

        let code = |stderr: &str, lines: &str| fold(lines, stderr).4.and_then(|e| e.code);
        assert_eq!(code("CLAUDE_CODE_GIT_BASH_PATH=C:\\x", "").as_deref(), Some(NEEDS_GIT));
        assert_eq!(
            code("", r#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}"#).as_deref(),
            Some(SIGNED_OUT)
        );
        let kind = |lines: &str| fold(lines, "").4.map(|e| e.kind);
        assert_eq!(
            kind("{\"type\":\"assistant\",\"error\":\"billing_error\",\"message\":{\"content\":[]}}\n{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":true,\"result\":\"x\"}"),
            Some(ErrorKind::Billing)
        );
        assert_eq!(
            code("", r#"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}"#).as_deref(),
            Some(CRASHED),
            "an unknown error result is a crash, never a guess"
        );
    }

    #[test]
    fn the_words_of_each_failure() {
        let data = testkit::load_json("claude-code/copy.json");
        for c in data["cases"].as_array().unwrap() {
            // The time of a plan limit is the webview's to format; here only the words without one.
            if c["resetsAt"].is_number() {
                continue;
            }
            let err = AiError { code: c["code"].as_str().map(str::to_string), ..AiError::new(ErrorKind::Server) };
            let note = wording(&err).unwrap_or_else(|| panic!("{}: no words", c["code"]));
            assert_eq!(note.text, c["text"].as_str().unwrap(), "{}", c["code"]);
            let action = note.action.map(|a| serde_json::to_value(a).unwrap()["kind"].as_str().unwrap().to_string());
            let expect = c["action"].as_str().map(|a| match a {
                "installGuide" => "installClaude",
                "signIn" => "signInClaude",
                "updateGuide" => "updateClaude",
                "retry" => "tryAgain",
                "gitGuide" => "installGit",
                other => other,
            });
            assert_eq!(action.as_deref(), expect, "{}: the one button", c["code"]);
        }
        assert!(wording(&AiError::new(ErrorKind::Server)).is_none(), "any other error is left to the general words");
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `$CL test -p notchmeow --target-dir $TD -- ai::claude_code`
Expected: FAIL, compile errors: `cannot find` the macro, the types and the functions the tests use (`json!`, `Level`, `Turn`, `Platform`, `arguments`, and so on).

```text
error: cannot find macro `json` in this scope
error: cannot find macro `json` in this scope
error[E0425]: cannot find type `Level` in this scope
```

- [ ] **Step 3: Write the engine, the parser and the words**

The implementation goes in front of the test module.

**Edit `windows/src-tauri/src/ai/claude_code.rs`**, find this text (it occurs exactly once):

```rust
#[cfg(test)]
mod tests {
```

and replace it with:

```rust
use std::collections::BTreeMap;

use serde_json::{json, Value};

use crate::ai::errors::{Action, Wording};
use crate::ai::provider::{file_text, AiError, ChatChunk, EngineReport, ErrorKind, Finish, Part, Payer, Step, StepState};

/// Claude Code's own model aliases (its `--model` values).
pub const MODELS: [&str; 3] = ["sonnet", "opus", "haiku"];

/// A model alias from settings: itself when it is one of Claude Code's, else the default.
pub fn model_or_default(alias: &str) -> String {
    if MODELS.contains(&alias) { alias } else { MODELS[0] }.to_string()
}

/// The codes on `AiError::code` for Claude Code's failures, on top of the twelve shared error kinds.
pub const MISSING: &str = "nm_claude_missing";
pub const SIGNED_OUT: &str = "nm_signed_out";
pub const PLAN_LIMIT: &str = "nm_plan_limit";
pub const TOO_OLD: &str = "nm_claude_old";
pub const CRASHED: &str = "nm_claude_crashed";
pub const OFFLINE: &str = "nm_claude_offline";
pub const NEEDS_GIT: &str = "nm_needs_git";
pub const FOLDER_MISSING: &str = "nm_folder_missing";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    Mac,
    Linux,
    Windows,
}

impl Platform {
    pub fn current() -> Self {
        if cfg!(windows) {
            Platform::Windows
        } else if cfg!(target_os = "macos") {
            Platform::Mac
        } else {
            Platform::Linux
        }
    }
}

/// What Claude may do in a chat. Read-only and Agent carry the folder the user chose.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Level {
    ChatOnly,
    ReadOnly(String),
    Agent(String),
}

impl Level {
    /// `chat`, `read` or `agent`, as in the fixtures.
    pub fn key(&self) -> &'static str {
        match self {
            Level::ChatOnly => "chat",
            Level::ReadOnly(_) => "read",
            Level::Agent(_) => "agent",
        }
    }

    pub fn folder(&self) -> Option<&str> {
        match self {
            Level::ChatOnly => None,
            Level::ReadOnly(f) | Level::Agent(f) => Some(f),
        }
    }
}

/// One run of Claude Code: everything except the message itself.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Turn {
    pub level: Level,
    pub model: String,
    /// The id NotchMeow chose for this chat's Claude Code session (lower-case UUID).
    pub session_id: String,
    /// False on a chat's first turn (`--session-id`), true on the later ones (`--resume`).
    pub resume: bool,
    pub platform: Platform,
}

const BASE: [&str; 7] =
    ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"];
const CHAT_TOOLS: &str = "WebSearch,WebFetch";
const READ_TOOLS: &str = "Read,Grep,Glob,WebSearch,WebFetch";
const READ_SETTINGS: &str = r#"{"permissions":{"blockReadsOutsideWorkingDirectories":true}}"#;
const SANDBOX_SETTINGS: &str = r#"{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":false}}"#;

/// The arguments after the program name. Every quoted value of the spec is one element: there is no shell. The folder is
/// the process's working folder, never an argument.
pub fn arguments(turn: &Turn) -> Vec<String> {
    let mut args: Vec<String> = BASE.iter().map(|s| s.to_string()).collect();
    args.extend([
        if turn.resume { "--resume" } else { "--session-id" }.to_string(),
        turn.session_id.clone(),
        "--model".to_string(),
        turn.model.clone(),
    ]);
    let more: &[&str] = match &turn.level {
        Level::ChatOnly => &[
            "--safe-mode", "--tools", CHAT_TOOLS, "--allowedTools", CHAT_TOOLS, "--disallowedTools", "mcp__*",
            "--permission-mode", "dontAsk",
        ],
        Level::ReadOnly(_) => &[
            "--safe-mode", "--tools", READ_TOOLS, "--allowedTools", READ_TOOLS, "--permission-mode", "dontAsk",
            "--settings", READ_SETTINGS,
        ],
        // Native Windows has no command sandbox: there every command asks.
        Level::Agent(_) if turn.platform == Platform::Windows => &["--permission-mode", "default"],
        Level::Agent(_) => &["--permission-mode", "default", "--settings", SANDBOX_SETTINGS],
    };
    args.extend(more.iter().map(|s| s.to_string()));
    args
}

/// The folder the process runs in: the user's for Read-only and Agent, NotchMeow's own empty one for Chat only.
pub fn working_directory(turn: &Turn, chat_folder: &str) -> String {
    turn.level.folder().unwrap_or(chat_folder).to_string()
}

/// Variables that outrank the user's plan login in Claude Code's own order of precedence.
pub const STRIPPED: [&str; 4] = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_PROFILE"];
pub const STRIPPED_PREFIXES: [&str; 1] = ["CLAUDE_CODE_USE_"];

/// The environment of a run: the caller's, without what would outrank the plan login. On Windows names compare without
/// regard to case. An `apiKeyHelper` is a setting, not a variable: it is not touched.
pub fn environment(base: impl IntoIterator<Item = (String, String)>, platform: Platform) -> Vec<(String, String)> {
    let insensitive = platform == Platform::Windows;
    base.into_iter()
        .filter(|(name, _)| {
            let key = if insensitive { name.to_uppercase() } else { name.clone() };
            !STRIPPED.contains(&key.as_str()) && !STRIPPED_PREFIXES.iter().any(|p| key.starts_with(p))
        })
        .collect()
}

fn block(part: &Part) -> Value {
    match part {
        Part::Text(t) => json!({ "type": "text", "text": t }),
        Part::FileText { name, text } => json!({ "type": "text", "text": file_text(name, text) }),
        Part::Image { mime, base64, .. } => {
            json!({ "type": "image", "source": { "type": "base64", "media_type": mime, "data": base64 } })
        }
        Part::Pdf { base64, .. } => {
            json!({ "type": "document", "source": { "type": "base64", "media_type": "application/pdf", "data": base64 } })
        }
    }
}

/// The one line written to stdin: the new message as content blocks (a dropped image or PDF as a block, other files as
/// text), in the documented user-message shape. `preamble` is a recap of the chat so far, only for a session that is
/// started afresh in the middle of a chat.
pub fn user_line(parts: &[Part], preamble: Option<&str>) -> String {
    let mut content = Vec::new();
    if let Some(recap) = preamble.filter(|p| !p.is_empty()) {
        content.push(json!({ "type": "text", "text": recap }));
    }
    content.extend(parts.iter().map(block));
    let mut line = json!({
        "type": "user",
        "message": { "role": "user", "content": content },
        "parent_tool_use_id": Value::Null,
    })
    .to_string();
    line.push('\n');
    line
}

// ── What the stream means ───────────────────────────────────────────────────────────────────────────────────────────

const STEP_FIELDS: [&str; 6] = ["command", "file_path", "path", "query", "pattern", "url"];
const STEP_FIELD_CAP: usize = 200;

fn payer(source: Option<&str>) -> Payer {
    match source {
        Some("none") | Some("oauth") => Payer::Plan,
        Some("user") | Some("project") | Some("org") | Some("temporary") => Payer::ApiKey,
        _ => Payer::Unknown,
    }
}

fn step_input(raw: &Value) -> BTreeMap<String, String> {
    STEP_FIELDS
        .iter()
        .filter_map(|k| raw.get(*k).and_then(Value::as_str).map(|v| (k.to_string(), v.chars().take(STEP_FIELD_CAP).collect())))
        .collect()
}

/// One run's output, read a line at a time.
#[derive(Debug, Default)]
pub struct Stream {
    engine: Option<EngineReport>,
    text: String,
    need_break: bool,
    steps: BTreeMap<String, Step>,
    finished: bool,
    result_seen: bool,
    result_text: String,
    assistant_error: Option<String>,
    /// None: no rate-limit event that rejected; Some(0): rejected, no time given; else Unix seconds.
    rejected_resets_at: Option<u64>,
    retried: bool,
}

impl Stream {
    pub fn new() -> Self {
        Stream::default()
    }

    /// Everything shown so far.
    pub fn text(&self) -> &str {
        &self.text
    }

    /// Whether Claude Code took at least one step.
    pub fn took_steps(&self) -> bool {
        !self.steps.is_empty()
    }

    pub fn engine(&self) -> Option<&EngineReport> {
        self.engine.as_ref()
    }

    /// Chunks for one line of stdout.
    pub fn consume(&mut self, line: &str) -> Vec<ChatChunk> {
        let Ok(event) = serde_json::from_str::<Value>(line) else { return Vec::new() };
        match event.get("type").and_then(Value::as_str) {
            Some("system") => match event.get("subtype").and_then(Value::as_str) {
                Some("init") => {
                    let report = EngineReport {
                        session_id: event.get("session_id").and_then(Value::as_str).unwrap_or("").to_string(),
                        model: event.get("model").and_then(Value::as_str).unwrap_or("").to_string(),
                        paid_by: payer(event.get("apiKeySource").and_then(Value::as_str)),
                        version: event.get("claude_code_version").and_then(Value::as_str).map(str::to_string),
                    };
                    self.engine = Some(report.clone());
                    vec![ChatChunk::Engine(report)]
                }
                Some("api_retry") => {
                    self.retried = true;
                    Vec::new()
                }
                _ => Vec::new(),
            },
            Some("stream_event") => self.stream_event(event.get("event").unwrap_or(&Value::Null)),
            Some("assistant") => self.assistant(&event),
            Some("user") => self.tool_results(&event),
            Some("rate_limit_event") => {
                let info = event.get("rate_limit_info").unwrap_or(&Value::Null);
                if info.get("status").and_then(Value::as_str) == Some("rejected") {
                    self.rejected_resets_at = Some(info.get("resetsAt").and_then(Value::as_u64).unwrap_or(0));
                }
                Vec::new()
            }
            Some("result") => {
                self.result_seen = true;
                let is_error = event.get("is_error").and_then(Value::as_bool).unwrap_or(false);
                let subtype = event.get("subtype").and_then(Value::as_str).unwrap_or("");
                self.result_text = event.get("result").and_then(Value::as_str).unwrap_or("").to_string();
                if !is_error && subtype == "success" {
                    self.finished = true;
                    return vec![ChatChunk::Finish(Finish::Stop)];
                }
                if subtype == "error_max_turns" {
                    self.finished = true;
                    return vec![ChatChunk::Finish(Finish::Length)];
                }
                Vec::new()
            }
            _ => Vec::new(),
        }
    }

    fn stream_event(&mut self, e: &Value) -> Vec<ChatChunk> {
        match e.get("type").and_then(Value::as_str) {
            Some("message_start") => {
                self.need_break = self.need_break || !self.text.is_empty();
                Vec::new()
            }
            Some("content_block_start") => {
                let block = e.get("content_block").unwrap_or(&Value::Null);
                let kind = block.get("type").and_then(Value::as_str);
                if let (Some("tool_use"), Some(id)) = (kind, block.get("id").and_then(Value::as_str)) {
                    self.need_break = self.need_break || !self.text.is_empty();
                    let step = Step {
                        id: id.to_string(),
                        tool: block.get("name").and_then(Value::as_str).unwrap_or("").to_string(),
                        input: BTreeMap::new(),
                        state: StepState::Running,
                    };
                    self.steps.insert(id.to_string(), step.clone());
                    return vec![ChatChunk::Step(step)];
                }
                if kind == Some("text") && self.need_break && !self.text.is_empty() {
                    self.need_break = false;
                    self.text.push_str("\n\n");
                    return vec![ChatChunk::Text("\n\n".to_string())];
                }
                Vec::new()
            }
            Some("content_block_delta") => {
                let delta = e.get("delta").unwrap_or(&Value::Null);
                let (Some("text_delta"), Some(piece)) = (delta.get("type").and_then(Value::as_str), delta.get("text").and_then(Value::as_str))
                else {
                    return Vec::new();
                };
                let mut out = Vec::new();
                if self.need_break && !self.text.is_empty() {
                    self.text.push_str("\n\n");
                    out.push(ChatChunk::Text("\n\n".to_string()));
                }
                self.need_break = false;
                self.text.push_str(piece);
                out.push(ChatChunk::Text(piece.to_string()));
                out
            }
            _ => Vec::new(),
        }
    }

    fn assistant(&mut self, event: &Value) -> Vec<ChatChunk> {
        if let Some(error) = event.get("error").and_then(Value::as_str) {
            self.assistant_error = Some(error.to_string());
        }
        let mut out = Vec::new();
        let content = event.pointer("/message/content").and_then(Value::as_array).cloned().unwrap_or_default();
        for block in content.iter().filter(|b| b.get("type").and_then(Value::as_str) == Some("tool_use")) {
            let Some(id) = block.get("id").and_then(Value::as_str) else { continue };
            let Some(step) = self.steps.get_mut(id) else { continue };
            step.input = step_input(block.get("input").unwrap_or(&Value::Null));
            out.push(ChatChunk::Step(step.clone()));
        }
        out
    }

    fn tool_results(&mut self, event: &Value) -> Vec<ChatChunk> {
        let mut out = Vec::new();
        let content = event.pointer("/message/content").and_then(Value::as_array).cloned().unwrap_or_default();
        for block in content.iter().filter(|b| b.get("type").and_then(Value::as_str) == Some("tool_result")) {
            let Some(id) = block.get("tool_use_id").and_then(Value::as_str) else { continue };
            let Some(step) = self.steps.get_mut(id) else { continue };
            step.state = if block.get("is_error").and_then(Value::as_bool).unwrap_or(false) { StepState::Failed } else { StepState::Done };
            out.push(ChatChunk::Step(step.clone()));
        }
        out
    }

    /// `None` when the run ended well. Call once, after the process has exited. `stderr` is only read, never kept. The
    /// exit status is not used: Claude Code does not document one, and a result decides when there is one.
    pub fn failure(&self, stderr: &str) -> Option<AiError> {
        if self.finished {
            return None;
        }
        let words = if self.result_seen { self.result_text.as_str() } else { "" };
        let blob = format!("{words}\n{stderr}").to_lowercase();
        let paid = self.engine.as_ref().map(|e| e.paid_by);
        let fail = |kind: ErrorKind, code: Option<&str>, resets_at: Option<u64>| {
            Some(AiError { code: code.map(str::to_string), resets_at: resets_at.filter(|t| *t > 0), ..AiError::new(kind) })
        };
        let assistant = self.assistant_error.as_deref();
        if blob.contains("git-bash") || blob.contains("claude_code_git_bash_path") || blob.contains("git for windows") {
            return fail(ErrorKind::BadRequest, Some(NEEDS_GIT), None);
        }
        if assistant == Some("authentication_failed") || blob.contains("not logged in") || blob.contains("please run /login") {
            return fail(ErrorKind::Auth, Some(SIGNED_OUT), None);
        }
        if blob.contains("unknown option") {
            return fail(ErrorKind::BadRequest, Some(TOO_OLD), None);
        }
        if self.rejected_resets_at.is_some() || (assistant == Some("rate_limit") && paid == Some(Payer::Plan)) {
            return fail(ErrorKind::Billing, Some(PLAN_LIMIT), self.rejected_resets_at);
        }
        match assistant {
            Some("rate_limit") => return fail(ErrorKind::RateLimited, None, None),
            Some("billing_error") => return fail(ErrorKind::Billing, Some("billing_error"), None),
            Some("overloaded") => return fail(ErrorKind::Overloaded, None, None),
            Some("server_error") => return fail(ErrorKind::Server, None, None),
            _ => {}
        }
        if self.result_seen && (self.retried || blob.contains("unable to connect")) {
            return fail(ErrorKind::Unreachable, Some(OFFLINE), None);
        }
        fail(ErrorKind::Interrupted, Some(CRASHED), None)
    }
}

// ── The words ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// The note for one of Claude Code's failures, or `None` for any other error (the general words then decide). The time of
/// a plan limit is not formatted here: the webview does it in the viewer's time zone and locale, from `resets_at`.
pub fn wording(err: &AiError) -> Option<Wording> {
    let (text, action) = match err.code.as_deref()? {
        MISSING => ("Claude Code isn't installed.", Some(Action::InstallClaude)),
        SIGNED_OUT => ("Claude Code is signed out.", Some(Action::SignInClaude)),
        PLAN_LIMIT => ("Your Claude plan's limit was reached.", None),
        TOO_OLD => ("Update Claude Code.", Some(Action::UpdateClaude)),
        CRASHED => ("Claude stopped unexpectedly.", Some(Action::TryAgain)),
        OFFLINE => ("Couldn't reach Claude.", None),
        NEEDS_GIT => ("Claude Code needs Git for Windows.", Some(Action::InstallGit)),
        FOLDER_MISSING => ("That folder isn't there any more. Pick another one.", None),
        _ => return None,
    };
    Some(Wording { text: text.to_string(), action })
}

#[cfg(test)]
mod tests {
```

The error copy and the settings use it:

**Edit `windows/src-tauri/src/ai/errors.rs`**, find this text (it occurs exactly once):

```rust
    ChooseModel,
    Cancel,
}

```

and replace it with:

```rust
    ChooseModel,
    Cancel,
    /// Claude Code: open a terminal to sign in, show Anthropic's install page, show its update page, show Git for
    /// Windows' page, or send the last message again.
    SignInClaude,
    InstallClaude,
    UpdateClaude,
    InstallGit,
    TryAgain,
}

```

**Edit `windows/src-tauri/src/ai/errors.rs`**, find this text (it occurs exactly once):

```rust
/// plus the cases it leaves out, worded the same way).
pub fn error_copy(kind: ErrorKind, who: &Who, err: Option<&AiError>) -> Wording {
    let cloud = catalog::is_cloud(&who.provider);
    let brand = if cloud { catalog::brand(&who.provider).to_string() } else { who.name.clone() };
```

and replace it with:

```rust
/// plus the cases it leaves out, worded the same way).
pub fn error_copy(kind: ErrorKind, who: &Who, err: Option<&AiError>) -> Wording {
    if who.provider == "claudeCode" {
        if let Some(note) = err.and_then(crate::ai::claude_code::wording) {
            return note;
        }
    }
    let cloud = catalog::is_cloud(&who.provider);
    let brand = if cloud { catalog::brand(&who.provider).to_string() } else { who.name.clone() };
```

**Edit `windows/src-tauri/src/settings.rs`**, find this text (it occurs exactly once):

```rust
pub fn sanitized(mut settings: Settings) -> Settings {
    settings.ai.custom_server = settings.ai.custom_server.as_deref().and_then(crate::ai::discovery::clean_server_url);
    settings
}
```

and replace it with:

```rust
pub fn sanitized(mut settings: Settings) -> Settings {
    settings.ai.custom_server = settings.ai.custom_server.as_deref().and_then(crate::ai::discovery::clean_server_url);
    settings.ai.claude_code_model = crate::ai::claude_code::model_or_default(&settings.ai.claude_code_model);
    settings
}
```

- [ ] **Step 4: Run them**

Run: `$CL test -p notchmeow --target-dir $TD -- ai::claude_code ai::errors settings::`
Expected: PASS, `test result: ok.` and no `FAILED`; `ai::claude_code` alone runs 7 tests.

```text
test ai::claude_code::tests::a_model_alias_from_settings_is_one_of_claude_codes ... ok
test ai::claude_code::tests::the_message_on_stdin ... ok
test ai::claude_code::tests::the_words_of_each_failure ... ok
test ai::claude_code::tests::the_environment_of_a_run ... ok
test ai::claude_code::tests::the_command_line_of_every_level_and_turn ... ok
test ai::claude_code::tests::tolerance ... ok
test ai::claude_code::tests::what_a_transcript_means ... ok
test result: ok. 22 passed; 0 failed; 0 ignored; 0 measured; 120 filtered out; finished in 0.01s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/ai/claude_code.rs windows/src-tauri/src/ai/mod.rs windows/src-tauri/src/ai/errors.rs windows/src-tauri/src/settings.rs
git commit -q -m "feat(claude-code): the Rust port of the engine, the transcript parser and the words of each failure" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 16: Windows/Linux: finding Claude Code, and the runner with Stop (`claude_cli.rs`, `claude_run.rs`)

**Agent:** `nm-implementer-deep`. The Rust port of Tasks 6 and 7, with a Unix process group and a Windows tree kill that must not leave anything running. If a test is flaky, fix the code, not the test.

**Files:**
- Create: `windows/src-tauri/src/ai/claude_cli.rs`, `claude_run.rs` (their tests are in the files)
- Modify: `windows/src-tauri/src/ai/mod.rs` (two `pub mod` lines)

**Interfaces:**
- Consumes: Task 15's `claude_code::{Platform, Turn, Stream, arguments, environment, user_line, MODELS, MISSING, FOLDER_MISSING}`; Task 14's types; `ModelProvider`, `ChatRequest`, `Aggregate`, `Placement`, `crate::log` and `crate::platform::{home_dir, find_on_path, no_console}` (existing); the fake `claude` (Task 2). `libc` is already a dependency of this crate on Linux; no `Cargo.toml` line changes.
- Produces, in `ai::claude_cli` (std::process only, no async):

  ```rust
  pub const MINIMUM_VERSION: [u32; 3] = [2, 1, 211];  pub const INSTALL_GUIDE: &str;  pub const GIT_FOR_WINDOWS: &str;
  pub struct Found { pub path: Option<String>, pub shim_only: bool, pub asked_shell: bool }
  pub fn find(platform: Platform, home: &str, env: &BTreeMap<String, String>, is_executable: impl Fn(&str) -> bool, login_shell: impl FnOnce() -> Option<String>) -> Found
  pub fn locate(env: &BTreeMap<String, String>) -> Option<String>                      // a debug build reads NM_CLAUDE_CODE_PATH_OVERRIDE
  pub fn parse_version(text: &str) -> Option<[u32; 3]>;  pub enum VersionCheck { Ok, TooOld, Unknown };  pub fn check_version(v: Option<[u32; 3]>) -> VersionCheck
  pub enum Auth { SignedIn(Option<String>), SignedOut, Unknown };  pub fn parse_auth(exit: Option<i32>, stdout: &str) -> Auth
  pub fn git_bash_candidates(env: &BTreeMap<String, String>) -> Vec<String>           // CLAUDE_CODE_GIT_BASH_PATH, Program Files, Program Files (x86), %LOCALAPPDATA%\Programs
  pub enum State { NotInstalled, TooOld, SignedOut, SignedIn, Unknown }                // serialises camelCase
  pub struct Status { pub state: State, pub executable: Option<String>, pub version: Option<String>, pub auth_method: Option<String>, pub shim_only: bool, pub needs_git: bool }
  impl Status { pub fn not_installed() -> Self; pub fn is_ready(&self) -> bool }
  pub fn status(env: &BTreeMap<String, String>) -> Status;  pub fn status_of(exe: &str, env: &BTreeMap<String, String>) -> Status    // blocking: call off the async threads
  pub fn run(exe: &str, args: &[String], env: &BTreeMap<String, String>, timeout: Duration) -> (Option<i32>, String)
  pub fn sh_quoted(path: &str) -> String;  pub fn powershell_quoted(path: &str) -> String;  pub fn sign_in_script(exe: &str) -> String
  pub fn linux_terminal_command(exe: &str, on_path: impl Fn(&str) -> bool) -> Option<(String, Vec<String>)>;  pub fn open_sign_in(exe: &str) -> bool
  pub fn pick_folder() -> Option<String>;  pub fn check_folder(path: &str) -> Result<String, String>
  ```

  and in `ai::claude_run`: `Timings { startup, interrupt_grace, terminate_grace, drain }` (30 s, 2 s, 2 s, 1 s), `Run { executable, leading_args, turn, chat_folder, preamble, base_env, timings }`, and `ClaudeCode::new(run: Run)`, a `ModelProvider` (id `claudeCode`, name "Claude plan", placement cloud) whose `stream` writes the last user message to stdin, closes it, and feeds the chunks of `claude_code::Stream` to the sink. **Stop is the turn's future being dropped**: on Unix the run was started as its own process group, and Stop sends the group SIGINT, then SIGTERM after `interrupt_grace`, then SIGKILL after `terminate_grace`, so whatever the run started goes too; on Windows (no interrupt to give a console child) `taskkill /PID <pid> /T /F` takes the tree at once. Failures use the codes of Task 15, plus `nm_claude_missing` when the program cannot start, `nm_folder_missing`, and a timeout when no first line comes in `startup`. Nothing is logged but event types and error kinds.

  Windows rules: `%USERPROFILE%\.local\bin\claude.exe` first, then `claude.exe` on `PATH` unless it sits in a Claude Desktop folder (`AnthropicClaude`, `WindowsApps`); a `claude.cmd` shim alone is `shim_only` and is never run (a `.cmd` cannot take JSON arguments safely); Git for Windows' `bash.exe` is looked for in `CLAUDE_CODE_GIT_BASH_PATH` and the usual places, and its absence is `needs_git`, which the chat turns into "Claude Code needs Git for Windows" (Review Focus 7). Sign-in opens Windows Terminal, else PowerShell, running `claude auth login`; on Linux the first of a list of terminals that is installed.

- [ ] **Step 1: Write the failing tests**

The two modules are declared, and each file holds only its tests. `claude_cli`: the locator cases on all three platforms, Desktop shadowing, the shim, versions, `auth status`, Git for Windows' locations (with a folder under `José`), quoting for a POSIX shell and for PowerShell (a quote, spaces, accents), the first installed Linux terminal, a folder check, and the real checks against the fake `claude`. `claude_run`: one whole turn against the fake (the argv, the stripped environment, stdin, the folder), each failure, Stop (a fake that hangs mid-tool with a child process, one that ignores interrupt and terminate), two runs at once, a folder with spaces and non-ASCII characters, and a leak test: a unique marker in the prompt, the folder name and the environment must not reach the log. They pin Review Focus 2 (Stop and the process group), 3 (two runs), 6 (the folder, the quoting), 7 (Git for Windows' locations) and 11 (the leak test).

**Edit `windows/src-tauri/src/ai/mod.rs`**, find this text (it occurs exactly once):

```rust
pub mod budget;
pub mod catalog;
pub mod claude_code;
pub mod discovery;
pub mod errors;
```

and replace it with:

```rust
pub mod budget;
pub mod catalog;
pub mod claude_cli;
pub mod claude_code;
pub mod claude_run;
pub mod discovery;
pub mod errors;
```

**Create `windows/src-tauri/src/ai/claude_cli.rs`** with exactly this content (only its tests for now):

```rust
// Finding the user's Claude Code and asking it two questions: its version and whether it is signed in. These run when
// Settings opens and before a chat's first turn, never on a timer. NotchMeow never reads Claude Code's credential files
// or keychain items: it only reads `authMethod` out of `claude auth status` and keeps nothing else. The rules are in
// tests/fixtures/ai/claude-code/ (locator-cases.json, auth-status.json, versions.json). std::process only.

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;

    fn strings(v: &Value) -> Vec<String> {
        v.as_array().unwrap().iter().map(|s| s.as_str().unwrap().to_string()).collect()
    }

    #[test]
    fn where_claude_is_looked_for() {
        let data = testkit::load_json("claude-code/locator-cases.json");
        let markers: Vec<String> = strings(&data["windowsDesktopMarkers"]);
        assert_eq!(DESKTOP_MARKERS.to_vec(), markers);
        for c in data["cases"].as_array().unwrap() {
            let existing: Vec<String> = strings(&c["executables"]);
            let env: BTreeMap<String, String> = c["env"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_str().unwrap().to_string())).collect();
            let platform = if c["platform"] == "windows" { Platform::Windows } else { Platform::Linux };
            let found = find(platform, c["home"].as_str().unwrap(), &env, |p| existing.iter().any(|e| e == p), || c["loginShell"].as_str().map(str::to_string));
            let name = c["name"].as_str().unwrap();
            assert_eq!(found.path.as_deref(), c["expect"].as_str(), "{name}");
            assert_eq!(found.shim_only, c["shimOnly"].as_bool().unwrap(), "{name}: a shim is never run");
            if platform != Platform::Windows {
                assert_eq!(found.asked_shell, c["loginShellCalled"].as_bool().unwrap(), "{name}: the login shell is asked only when nothing earlier exists");
            }
        }
    }

    #[cfg(debug_assertions)]
    #[test]
    fn a_debug_build_can_be_pointed_at_the_fake() {
        let env: BTreeMap<String, String> = [("NM_CLAUDE_CODE_PATH_OVERRIDE".to_string(), "/x/fake_claude.py".to_string())].into();
        assert_eq!(locate(&env).as_deref(), Some("/x/fake_claude.py"));
    }

    #[test]
    fn versions() {
        let data = testkit::load_json("claude-code/versions.json");
        assert_eq!(MINIMUM_VERSION.to_vec(), data["minimum"].as_array().unwrap().iter().map(|n| n.as_u64().unwrap() as u32).collect::<Vec<_>>());
        for c in data["parse"].as_array().unwrap() {
            let want = c["expect"].as_array().map(|a| [a[0].as_u64().unwrap() as u32, a[1].as_u64().unwrap() as u32, a[2].as_u64().unwrap() as u32]);
            assert_eq!(parse_version(c["text"].as_str().unwrap()), want, "parse {}", c["text"]);
        }
        for c in data["check"].as_array().unwrap() {
            let version = c["version"].as_array().map(|a| [a[0].as_u64().unwrap() as u32, a[1].as_u64().unwrap() as u32, a[2].as_u64().unwrap() as u32]);
            let want = match c["expect"].as_str().unwrap() {
                "ok" => VersionCheck::Ok,
                "tooOld" => VersionCheck::TooOld,
                _ => VersionCheck::Unknown,
            };
            assert_eq!(check_version(version), want, "check {}", c["version"]);
        }
    }

    #[test]
    fn auth_status() {
        let data = testkit::load_json("claude-code/auth-status.json");
        for c in data["cases"].as_array().unwrap() {
            let got = parse_auth(c["exit"].as_i64().map(|e| e as i32), c["stdout"].as_str().unwrap());
            let e = &c["expect"];
            let want = match e["state"].as_str().unwrap() {
                "signedIn" => Auth::SignedIn(e["authMethod"].as_str().map(str::to_string)),
                "signedOut" => Auth::SignedOut,
                _ => Auth::Unknown,
            };
            assert_eq!(got, want, "{}", c["name"]);
        }
    }

    #[test]
    fn git_for_windows_is_looked_for_in_the_usual_places() {
        let env: BTreeMap<String, String> = [
            ("CLAUDE_CODE_GIT_BASH_PATH", "D:\\Tools\\Git\\bin\\bash.exe"),
            ("ProgramFiles", "C:\\Program Files\\"),
            ("ProgramFiles(x86)", "C:\\Program Files (x86)"),
            ("LOCALAPPDATA", "C:\\Users\\José\\AppData\\Local"),
        ]
        .into_iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
        assert_eq!(
            git_bash_candidates(&env),
            [
                "D:\\Tools\\Git\\bin\\bash.exe",
                "C:\\Program Files\\Git\\bin\\bash.exe",
                "C:\\Program Files (x86)\\Git\\bin\\bash.exe",
                "C:\\Users\\José\\AppData\\Local\\Programs\\Git\\bin\\bash.exe",
            ]
        );
        assert!(git_bash_candidates(&BTreeMap::new()).is_empty());
    }

    #[test]
    fn quoting_for_a_shell_and_for_powershell() {
        assert_eq!(sh_quoted("/Users/O'Brien/Zoé Ünï/.local/bin/claude"), "'/Users/O'\\''Brien/Zoé Ünï/.local/bin/claude'");
        assert_eq!(powershell_quoted("C:\\Users\\José O'Neil\\claude.exe"), "'C:\\Users\\José O''Neil\\claude.exe'");
    }

    #[test]
    fn the_linux_terminal_is_the_first_one_installed() {
        let (program, args) = linux_terminal_command("/home/zoe/.local/bin/claude", |p| p == "konsole" || p == "xterm").unwrap();
        assert_eq!((program.as_str(), args[0].as_str(), args[1].as_str()), ("konsole", "-e", "sh"));
        assert!(args[3].contains("'/home/zoe/.local/bin/claude' auth login"));
        assert!(linux_terminal_command("/x/claude", |_| false).is_none(), "no terminal installed");
    }

    #[test]
    fn a_folder_the_chat_may_work_in() {
        let dir = testkit::TempDir::new("folder");
        assert_eq!(check_folder(&format!("  {}  ", dir.path().display())).unwrap(), dir.path().display().to_string());
        assert!(check_folder("").is_err() && check_folder(&dir.path().join("nope").display().to_string()).is_err());
    }

    /// The checks against the fake `claude`. Unix only: a script cannot be run as a program on Windows.
    #[cfg(unix)]
    #[test]
    fn the_checks_against_the_fake_claude() {
        let dir = testkit::TempDir::new("cli");
        let fake = dir.path().join("claude");
        std::fs::copy(testkit::fixtures_dir().join("claude-code/fake_claude.py"), &fake).unwrap();
        let env_with = |extra: &[(&str, &str)]| -> BTreeMap<String, String> {
            let mut env: BTreeMap<String, String> = std::env::vars().filter(|(k, _)| k == "PATH").collect();
            env.insert("ANTHROPIC_API_KEY".into(), "sk-ant-FAKE".into());
            env.extend(extra.iter().map(|(k, v)| (k.to_string(), v.to_string())));
            env
        };
        let exe = fake.to_string_lossy().to_string();
        let ok = status_of(&exe, &env_with(&[]));
        assert_eq!((ok.state, ok.auth_method.as_deref(), ok.version.as_deref()), (State::SignedIn, Some("claude.ai"), Some("2.1.211")));
        let out = status_of(&exe, &env_with(&[("NM_FAKE_CLAUDE_AUTH_EXIT", "1"), ("NM_FAKE_CLAUDE_AUTH_JSON", "{\"authMethod\":\"none\"}")]));
        assert_eq!(out.state, State::SignedOut);
        assert_eq!(status_of(&exe, &env_with(&[("NM_FAKE_CLAUDE_VERSION", "2.1.100 (Claude Code)")])).state, State::TooOld);
        assert_eq!(status_of(&exe, &env_with(&[("NM_FAKE_CLAUDE_VERSION", "hello")])).state, State::NotInstalled);
        assert_eq!(status_of("/nonexistent/claude", &env_with(&[])).state, State::NotInstalled);
    }
}
```

**Create `windows/src-tauri/src/ai/claude_run.rs`** with exactly this content (only its tests for now):

```rust
// Claude Code as a provider: one `claude -p` process per turn. This file owns the process; the command line and the
// meaning of the transcript are in `claude_code.rs`. std::process only (no tokio `process` feature, no new crate).
//
// Nothing runs on a timer. A turn starts one process and ends when it does; Stop (the turn's future being dropped)
// interrupts it, then terminates it, then kills it and everything it started, so no process outlives the chat. Nothing is
// logged but event types and error kinds: never the arguments, the folder, stdin, stdout, stderr or the environment.

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use crate::ai::claude_code::{Level, Platform, CRASHED, NEEDS_GIT, PLAN_LIMIT, SIGNED_OUT};
    use crate::ai::provider::{Message, Part};
    use crate::ai::testkit;

    const SID: &str = "11111111-1111-4111-8111-111111111111";
    const MARKER: &str = "ZZ-LEAK-MARKER-7391";

    fn request(text: &str) -> ChatRequest {
        ChatRequest {
            model: "sonnet".into(),
            system: String::new(),
            messages: vec![Message { role: Role::User, parts: vec![Part::Text(text.into())] }],
            tools: Vec::new(),
            response_format: None,
            max_tokens: 1,
        }
    }

    struct Sandbox {
        dir: testkit::TempDir,
    }

    impl Sandbox {
        fn new() -> Self {
            Sandbox { dir: testkit::TempDir::new("claude-run") }
        }

        fn file(&self, name: &str) -> String {
            self.dir.path().join(name).to_string_lossy().to_string()
        }

        fn folder(&self, name: &str) -> String {
            let path = self.dir.path().join(name);
            std::fs::create_dir_all(&path).unwrap();
            path.to_string_lossy().to_string()
        }

        /// The fake claude, run through whatever Python this machine has.
        fn run(&self, transcript: Option<&str>, level: Level, extra: &[(&str, &str)], log: &str) -> Run {
            let python = testkit::python();
            let mut leading: Vec<String> = python.get_args().map(|a| a.to_string_lossy().to_string()).collect();
            leading.push(testkit::fixtures_dir().join("claude-code/fake_claude.py").to_string_lossy().to_string());
            let mut env: Vec<(String, String)> = vec![
                ("PATH".into(), std::env::var("PATH").unwrap_or_default()),
                ("NM_FAKE_CLAUDE_LOG".into(), log.to_string()),
                ("CANARY".into(), "kept".into()),
                // What must never reach the run:
                ("ANTHROPIC_API_KEY".into(), "sk-ant-FAKE".into()),
                ("ANTHROPIC_AUTH_TOKEN".into(), "tok-FAKE".into()),
                ("CLAUDE_CODE_OAUTH_TOKEN".into(), "oauth-FAKE".into()),
                ("ANTHROPIC_PROFILE".into(), "work".into()),
                ("CLAUDE_CODE_USE_BEDROCK".into(), "1".into()),
            ];
            if let Some(t) = transcript {
                env.push(("NM_FAKE_CLAUDE_TRANSCRIPT".into(), testkit::fixtures_dir().join("claude-code/transcripts").join(t).to_string_lossy().to_string()));
            }
            env.extend(extra.iter().map(|(k, v)| (k.to_string(), v.to_string())));
            Run {
                executable: python.get_program().to_string_lossy().to_string(),
                leading_args: leading,
                turn: Turn { level, model: "sonnet".into(), session_id: SID.into(), resume: false, platform: Platform::Linux },
                chat_folder: self.folder("chat"),
                preamble: None,
                base_env: env,
                timings: Timings { startup: Duration::from_secs(20), interrupt_grace: Duration::from_secs(2), terminate_grace: Duration::from_secs(2), drain: Duration::from_secs(1) },
            }
        }
    }

    struct Outcome {
        chunks: Vec<ChatChunk>,
        result: Result<Aggregate, AiError>,
        calls: Vec<serde_json::Value>,
    }

    async fn collect(run: Run, text: &str, log: &str) -> Outcome {
        let provider = ClaudeCode::new(run);
        let mut chunks = Vec::new();
        let result = provider.stream(&request(text), &mut |c| chunks.push(c)).await;
        let calls = std::fs::read_to_string(log).unwrap_or_default().lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
        Outcome { chunks, result, calls }
    }

    impl Outcome {
        fn turn(&self) -> &serde_json::Value {
            self.calls.iter().find(|c| c["argv"][0] == "-p").expect("one claude -p call")
        }

        fn steps(&self) -> Vec<String> {
            let mut out: Vec<(String, String)> = Vec::new();
            for c in &self.chunks {
                if let ChatChunk::Step(s) = c {
                    let row = (s.id.clone(), serde_json::to_value(s.state).unwrap().as_str().unwrap().to_string());
                    match out.iter_mut().find(|r| r.0 == s.id) {
                        Some(old) => *old = row,
                        None => out.push(row),
                    }
                }
            }
            out.into_iter().map(|(id, state)| format!("{id}:{state}")).collect()
        }
    }

    fn alive(pid_file: &str) -> bool {
        std::fs::read_to_string(pid_file).ok().and_then(|t| t.trim().parse::<i32>().ok()).is_some_and(|pid| unsafe { libc::kill(pid, 0) == 0 })
    }

    async fn wait_until_gone(files: &[String], seconds: u64) -> bool {
        let end = std::time::Instant::now() + Duration::from_secs(seconds);
        while std::time::Instant::now() < end {
            if files.iter().all(|f| !alive(f)) {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        false
    }

    #[tokio::test]
    async fn a_turn() {
        let s = Sandbox::new();
        let log = s.file("turn.jsonl");
        let run = s.run(Some("success.jsonl"), Level::ChatOnly, &[], &log);
        let argv = claude_code::arguments(&run.turn);
        let chat = run.chat_folder.clone();
        let out = collect(run, "Hello", &log).await;
        let agg = out.result.as_ref().unwrap();
        assert_eq!(agg.text, "Bonjour Zoé, hello! 🐱");
        assert_eq!(agg.finish, Some(Finish::Stop));
        let turn = out.turn();
        let got: Vec<String> = turn["argv"].as_array().unwrap().iter().map(|a| a.as_str().unwrap().to_string()).collect();
        assert_eq!(got, argv, "the command line is the engine's");
        assert_eq!(std::fs::canonicalize(turn["cwd"].as_str().unwrap()).unwrap(), std::fs::canonicalize(&chat).unwrap(), "it runs in the chat folder");
        let env = turn["env"].as_object().unwrap();
        for gone in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_PROFILE", "CLAUDE_CODE_USE_BEDROCK"] {
            assert!(!env.contains_key(gone), "{gone} outranks the plan login");
        }
        assert_eq!(env["CANARY"], "kept");
        let stdin: serde_json::Value = serde_json::from_str(turn["stdin"].as_str().unwrap()).unwrap();
        assert_eq!(stdin["message"]["content"][0]["text"], "Hello", "the message goes in on stdin, and stdin was closed (the fake reads to its end)");
        assert!(out.chunks.iter().any(|c| matches!(c, ChatChunk::Engine(r) if r.model == "claude-sonnet-5-5")));

        let tools_log = s.file("tools.jsonl");
        let mut run = s.run(Some("tool-use.jsonl"), Level::ReadOnly(s.folder("project")), &[], &tools_log);
        run.turn.resume = true;
        let tools = collect(run, "Read it", &tools_log).await;
        assert_eq!(tools.steps(), ["toolu_01A:done", "toolu_01B:failed"], "steps arrive as rows that update");
        assert_eq!(tools.result.unwrap().text, "I'll read the README.\n\nIt says it is a tiny demo.");
        assert!(tools.calls[0]["argv"].as_array().unwrap().iter().any(|a| a == "--resume"), "a later turn resumes the session");
    }

    #[tokio::test]
    async fn failures() {
        let s = Sandbox::new();
        let run_with = |transcript: &str, exit: &str, stderr: &str, name: &str| {
            let log = s.file(&format!("f-{name}.jsonl"));
            (s.run(Some(transcript), Level::ChatOnly, &[("NM_FAKE_CLAUDE_EXIT", exit), ("NM_FAKE_CLAUDE_STDERR", stderr)], &log), log)
        };
        let (run, log) = run_with("signed-out.jsonl", "1", "", "so");
        assert_eq!(collect(run, "hi", &log).await.result.unwrap_err().code.as_deref(), Some(SIGNED_OUT));
        let (run, log) = run_with("plan-limit.jsonl", "1", "", "pl");
        let err = collect(run, "hi", &log).await.result.unwrap_err();
        assert_eq!((err.kind, err.code.as_deref(), err.resets_at), (ErrorKind::Billing, Some(PLAN_LIMIT), Some(1_791_301_500)));
        let (run, log) = run_with("offline.jsonl", "1", "", "off");
        assert_eq!(collect(run, "hi", &log).await.result.unwrap_err().code.as_deref(), Some(claude_code::OFFLINE));
        let (run, log) = run_with("crash.jsonl", "2", "", "cr");
        let crash = collect(run, "hi", &log).await.result.unwrap();
        assert_eq!((crash.text.as_str(), crash.error), ("Let me look", Some(ErrorKind::Interrupted)), "a cut stream keeps what was said, marked as cut");
        let (run, log) = run_with("empty.jsonl", "139", "", "none");
        let nothing = collect(run, "hi", &log).await.result.unwrap_err();
        assert_eq!((nothing.kind, nothing.code.as_deref()), (ErrorKind::Server, Some(CRASHED)), "a crash with nothing to keep is a failed request");
        let (run, log) = run_with("empty.jsonl", "1", "Claude Code on Windows requires git-bash", "git");
        assert_eq!(collect(run, "hi", &log).await.result.unwrap_err().code.as_deref(), Some(NEEDS_GIT));

        let mut missing = s.run(None, Level::ChatOnly, &[], &s.file("none.jsonl"));
        missing.executable = "/nonexistent/claude".into();
        missing.leading_args.clear();
        let err = collect(missing, "hi", &s.file("none.jsonl")).await.result.unwrap_err();
        assert_eq!((err.kind, err.code.as_deref()), (ErrorKind::Unreachable, Some(MISSING)), "no such program is 'not installed'");
        let gone = collect(s.run(Some("success.jsonl"), Level::ReadOnly("/nonexistent-folder-zz".into()), &[], &s.file("gone.jsonl")), "hi", &s.file("gone.jsonl")).await;
        assert_eq!(gone.result.unwrap_err().code.as_deref(), Some(FOLDER_MISSING));
        assert!(gone.calls.is_empty(), "and nothing was started");

        let mut quiet = s.run(None, Level::ChatOnly, &[("NM_FAKE_CLAUDE_HANG_AFTER", "0"), ("NM_FAKE_CLAUDE_PIDFILE", &s.file("quiet.pid"))], &s.file("quiet.jsonl"));
        quiet.timings = Timings { startup: Duration::from_millis(600), interrupt_grace: Duration::from_millis(200), terminate_grace: Duration::from_millis(200), drain: Duration::from_millis(200) };
        let silent = collect(quiet, "hi", &s.file("quiet.jsonl")).await;
        assert_eq!(silent.result.unwrap_err().kind, ErrorKind::Timeout, "a run that never says anything times out");
        assert!(wait_until_gone(&[s.file("quiet.pid")], 5).await, "and is stopped");
    }

    #[tokio::test]
    async fn stop_ends_the_process_and_what_it_started() {
        for stubborn in [false, true] {
            let s = Sandbox::new();
            let tag = if stubborn { "stubborn" } else { "polite" };
            let (pid, child) = (s.file(&format!("{tag}.pid")), s.file(&format!("{tag}.child")));
            let mut extra = vec![("NM_FAKE_CLAUDE_HANG_AFTER", "8"), ("NM_FAKE_CLAUDE_PIDFILE", pid.as_str()), ("NM_FAKE_CLAUDE_CHILD_PIDFILE", child.as_str())];
            if stubborn {
                extra.push(("NM_FAKE_CLAUDE_STUBBORN", "1"));
            }
            let log = s.file(&format!("{tag}.jsonl"));
            let mut run = s.run(Some("tool-use.jsonl"), Level::ChatOnly, &extra, &log);
            run.timings = Timings { startup: Duration::from_secs(20), interrupt_grace: Duration::from_millis(300), terminate_grace: Duration::from_millis(300), drain: Duration::from_millis(300) };
            let provider = ClaudeCode::new(run);
            let (seen_tx, seen_rx) = tokio::sync::oneshot::channel::<()>();
            let seen_tx = Mutex::new(Some(seen_tx));
            let req = request("go");
            let mut sink = |c: ChatChunk| {
                if matches!(c, ChatChunk::Step(_)) {
                    if let Some(tx) = seen_tx.lock().unwrap().take() {
                        let _ = tx.send(());
                    }
                }
            };
            // Stop: the future is dropped while a step is running, as `session::attempt` does. The fake writes the
            // pid of the child it started a moment after its step line: wait for it, so "gone" means something.
            let (pid_file, child_file) = (pid.clone(), child.clone());
            tokio::select! {
                _ = provider.stream(&req, &mut sink) => panic!("{tag}: the run was meant to hang"),
                _ = async {
                    let _ = seen_rx.await;
                    while !Path::new(&child_file).exists() {
                        tokio::time::sleep(Duration::from_millis(20)).await;
                    }
                    assert!(alive(&pid_file) && alive(&child_file), "{tag}: both were running when Stop came");
                } => {}
            }
            assert!(wait_until_gone(&[pid, child], 8).await, "{tag}: the process and what it started are gone");
        }
    }

    #[tokio::test]
    async fn two_runs_at_once_do_not_share_anything() {
        let s = Sandbox::new();
        let (a_log, b_log) = (s.file("a.jsonl"), s.file("b.jsonl"));
        let mut a = s.run(Some("success.jsonl"), Level::ChatOnly, &[], &a_log);
        a.turn.session_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa".into();
        let mut b = s.run(Some("tool-use.jsonl"), Level::ReadOnly(s.folder("other")), &[], &b_log);
        b.turn.session_id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb".into();
        let (one, two) = tokio::join!(collect(a, "hi", &a_log), collect(b, "hi", &b_log));
        assert_eq!(one.result.as_ref().unwrap().text, "Bonjour Zoé, hello! 🐱");
        assert_eq!(two.result.as_ref().unwrap().text, "I'll read the README.\n\nIt says it is a tiny demo.");
        let has = |o: &Outcome, id: &str| o.turn()["argv"].as_array().unwrap().iter().any(|a| a == id);
        assert!(has(&one, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa") && has(&two, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"), "each run has its own session");
        assert_eq!((one.steps().len(), two.steps().len()), (0, 2), "a chat's steps never reach the other");
    }

    #[tokio::test]
    async fn a_folder_with_spaces_and_non_ascii_characters() {
        let s = Sandbox::new();
        let folder = s.folder("Zoé Mes projets/ünï côde");
        let log = s.file("unicode.jsonl");
        let out = collect(s.run(Some("tool-use.jsonl"), Level::ReadOnly(folder.clone()), &[], &log), "hi", &log).await;
        assert!(out.result.as_ref().unwrap().text.ends_with("tiny demo."));
        assert_eq!(std::fs::canonicalize(out.turn()["cwd"].as_str().unwrap()).unwrap(), std::fs::canonicalize(&folder).unwrap());
        assert!(!out.turn()["argv"].as_array().unwrap().iter().any(|a| a.as_str().unwrap().contains("ünï")), "and no argument carries it");
    }

    #[tokio::test]
    async fn nothing_private_reaches_the_log() {
        let s = Sandbox::new();
        let folder = s.folder(&format!("{MARKER}-folder"));
        let log = s.file("leak.jsonl");
        for transcript in ["success.jsonl", "plan-limit.jsonl", "crash.jsonl"] {
            let run = s.run(Some(transcript), Level::ReadOnly(folder.clone()), &[("NM_FAKE_CLAUDE_STDERR", &format!("stderr says {MARKER}")), ("LEAK_ENV", MARKER), ("NM_FAKE_CLAUDE_EXIT", "1")], &log);
            let _ = collect(run, &format!("tell me about {MARKER}"), &log).await;
        }
        let lines = crate::log::CAPTURED.lock().unwrap().clone();
        assert!(lines.iter().any(|l| l.starts_with("ai claude failure")), "failures were logged");
        assert!(!lines.iter().any(|l| l.contains(MARKER)), "no log line holds the prompt, the folder, stderr or the environment");
        assert!(!lines.iter().any(|l| l.contains(SID)), "and none holds the session id");
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `$CL test -p notchmeow --target-dir $TD -- ai::claude_cli ai::claude_run`
Expected: FAIL, compile errors: `cannot find` the types, constants and functions the tests use.

```text
error[E0425]: cannot find type `Value` in this scope
error[E0425]: cannot find value `DESKTOP_MARKERS` in this scope
error[E0425]: cannot find type `BTreeMap` in this scope
```

- [ ] **Step 3: Write the locator and the runner**

**Edit `windows/src-tauri/src/ai/claude_cli.rs`**, find this text (it occurs exactly once):

```rust
#[cfg(test)]
mod tests {
```

and replace it with:

```rust
use std::collections::BTreeMap;
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde::Serialize;
use serde_json::Value;

use crate::ai::claude_code::{self, Platform};

/// The version the flags in expected-args.json were verified against (2026-10-06). One number to lower once older
/// versions have been checked.
pub const MINIMUM_VERSION: [u32; 3] = [2, 1, 211];
/// Where Anthropic's installer is. NotchMeow links to it and installs nothing.
pub const INSTALL_GUIDE: &str = "https://docs.claude.com/en/docs/claude-code/setup";
pub const GIT_FOR_WINDOWS: &str = "https://git-scm.com/downloads/win";

/// A folder name that marks Claude Desktop's own install, which can shadow Claude Code's `claude.exe` on `PATH`.
const DESKTOP_MARKERS: [&str; 2] = ["anthropicclaude", "windowsapps"];

// ── Where it is ─────────────────────────────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Found {
    pub path: Option<String>,
    /// Only a `claude.cmd` shim was found: it cannot take JSON arguments safely, so it is never run.
    pub shim_only: bool,
    pub asked_shell: bool,
}

/// The first place claude is, in order. macOS and Linux: ~/.local/bin/claude, /opt/homebrew/bin/claude,
/// /usr/local/bin/claude, ~/.npm-global/bin/claude, $NPM_CONFIG_PREFIX/bin/claude, then the login shell's `command -v
/// claude` (asked only when nothing earlier exists: starting a login shell is slow). Windows:
/// %USERPROFILE%\.local\bin\claude.exe first, then claude.exe on PATH unless it sits in a Claude Desktop folder.
pub fn find(
    platform: Platform,
    home: &str,
    env: &BTreeMap<String, String>,
    is_executable: impl Fn(&str) -> bool,
    login_shell: impl FnOnce() -> Option<String>,
) -> Found {
    if platform == Platform::Windows {
        let mut candidates = vec![format!("{home}\\.local\\bin\\claude.exe")];
        let mut shim = false;
        for dir in env.get("PATH").map(String::as_str).unwrap_or("").split(';').filter(|d| !d.is_empty()) {
            let lower = dir.to_lowercase();
            if DESKTOP_MARKERS.iter().any(|m| lower.contains(m)) {
                continue;
            }
            let dir = dir.trim_end_matches('\\');
            candidates.push(format!("{dir}\\claude.exe"));
            shim = shim || is_executable(&format!("{dir}\\claude.cmd"));
        }
        return match candidates.into_iter().find(|c| is_executable(c)) {
            Some(path) => Found { path: Some(path), ..Found::default() },
            None => Found { shim_only: shim, ..Found::default() },
        };
    }
    let mut candidates = vec![
        format!("{home}/.local/bin/claude"),
        "/opt/homebrew/bin/claude".to_string(),
        "/usr/local/bin/claude".to_string(),
        format!("{home}/.npm-global/bin/claude"),
    ];
    if let Some(prefix) = env.get("NPM_CONFIG_PREFIX").filter(|p| !p.is_empty()) {
        candidates.push(format!("{}/bin/claude", prefix.trim_end_matches('/')));
    }
    if let Some(path) = candidates.into_iter().find(|c| is_executable(c)) {
        return Found { path: Some(path), ..Found::default() };
    }
    let printed = login_shell().unwrap_or_default();
    let last = printed.lines().map(str::trim).rfind(|l| !l.is_empty()).unwrap_or("");
    let path = (last.starts_with('/') && is_executable(last)).then(|| last.to_string());
    Found { path, shim_only: false, asked_shell: true }
}

#[cfg(unix)]
fn executable_on_disk(path: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
}

#[cfg(windows)]
fn executable_on_disk(path: &str) -> bool {
    Path::new(path).is_file()
}

/// Where the program is on this computer. The login shell is asked last, on macOS and Linux only.
pub fn locate(env: &BTreeMap<String, String>) -> Option<String> {
    // Debug builds only: `NM_CLAUDE_CODE_PATH_OVERRIDE` runs a chat against the fake claude. Compiled out of release builds,
    // so a shipped app can't be pointed at another program.
    #[cfg(debug_assertions)]
    if let Some(path) = env.get("NM_CLAUDE_CODE_PATH_OVERRIDE").filter(|p| !p.is_empty()) {
        return Some(path.clone());
    }
    let home = crate::platform::home_dir().to_string_lossy().to_string();
    let platform = Platform::current();
    find(platform, &home, env, executable_on_disk, || login_shell_says(env)).path
}

/// `$SHELL -l -c 'command -v claude'`: a desktop-launched app has almost none of the user's PATH, their profile has it.
fn login_shell_says(env: &BTreeMap<String, String>) -> Option<String> {
    if cfg!(windows) {
        return None;
    }
    let shell = env.get("SHELL").filter(|s| s.starts_with('/')).cloned().unwrap_or_else(|| "/bin/sh".to_string());
    let (status, out) = run(&shell, &["-l".into(), "-c".into(), "command -v claude".into()], env, Duration::from_secs(5));
    status.map(|_| out)
}

// ── Its answers ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// The first x.y.z in the output of `claude --version`.
pub fn parse_version(text: &str) -> Option<[u32; 3]> {
    text.split(|c: char| !(c.is_ascii_digit() || c == '.')).find_map(|token| {
        let mut parts = token.split('.').map(|p| p.parse::<u32>().ok());
        Some([parts.next()??, parts.next()??, parts.next()??])
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VersionCheck {
    Ok,
    TooOld,
    Unknown,
}

pub fn check_version(version: Option<[u32; 3]>) -> VersionCheck {
    match version {
        None => VersionCheck::Unknown,
        Some(v) if v < MINIMUM_VERSION => VersionCheck::TooOld,
        Some(_) => VersionCheck::Ok,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Auth {
    SignedIn(Option<String>),
    SignedOut,
    Unknown,
}

/// `claude auth status`: exit 0 signed in, 1 signed out. Only `authMethod` is read. `none` is signed out whatever the exit
/// status says. `exit` is `None` when the program could not be run.
pub fn parse_auth(exit: Option<i32>, stdout: &str) -> Auth {
    let Some(exit) = exit else { return Auth::Unknown };
    let method = serde_json::from_str::<Value>(stdout).ok().and_then(|v| v.get("authMethod").and_then(Value::as_str).map(str::to_string));
    if exit == 1 || method.as_deref() == Some("none") {
        return Auth::SignedOut;
    }
    if exit == 0 {
        Auth::SignedIn(method)
    } else {
        Auth::Unknown
    }
}

/// Where Claude Code on native Windows needs Git for Windows' bash: an environment variable, then the usual places.
pub fn git_bash_candidates(env: &BTreeMap<String, String>) -> Vec<String> {
    let mut list: Vec<String> = env.get("CLAUDE_CODE_GIT_BASH_PATH").filter(|p| !p.is_empty()).cloned().into_iter().collect();
    for (var, tail) in [
        ("ProgramFiles", "\\Git\\bin\\bash.exe"),
        ("ProgramFiles(x86)", "\\Git\\bin\\bash.exe"),
        ("LOCALAPPDATA", "\\Programs\\Git\\bin\\bash.exe"),
    ] {
        if let Some(base) = env.get(var).filter(|b| !b.is_empty()) {
            list.push(format!("{}{tail}", base.trim_end_matches('\\')));
        }
    }
    list
}

// ── The check that starts processes ─────────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum State {
    NotInstalled,
    TooOld,
    SignedOut,
    SignedIn,
    Unknown,
}

/// What the last check found. `signed_in` is the only state the router treats as ready.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub state: State,
    #[serde(skip)]
    pub executable: Option<String>,
    /// "2.1.211"
    pub version: Option<String>,
    /// What `claude auth status` reports (`claude.ai`, `api_key`, …): the sign-in method, never an account.
    pub auth_method: Option<String>,
    /// Only a `claude.cmd` shim is installed (Windows).
    pub shim_only: bool,
    /// Windows: Git for Windows' bash was not found, and Claude Code will refuse to start without it.
    pub needs_git: bool,
}

impl Status {
    pub fn not_installed() -> Self {
        Status { state: State::NotInstalled, executable: None, version: None, auth_method: None, shim_only: false, needs_git: false }
    }

    pub fn is_ready(&self) -> bool {
        self.state == State::SignedIn
    }
}

/// The environment of a check: the same as a turn's, so the answer is what a chat would get.
fn clean(env: &BTreeMap<String, String>) -> BTreeMap<String, String> {
    claude_code::environment(env.clone(), Platform::current()).into_iter().collect()
}

/// Where it is, its version and whether it is signed in. Blocking: call it off the async threads.
pub fn status(env: &BTreeMap<String, String>) -> Status {
    let located = locate(env);
    let mut status = match located {
        Some(exe) => status_of(&exe, env),
        None => Status::not_installed(),
    };
    if cfg!(windows) {
        status.needs_git = !git_bash_candidates(env).iter().any(|p| Path::new(p).is_file());
        if status.state == State::NotInstalled {
            // A claude.cmd shim next to nothing else: say so rather than "not installed".
            let home = crate::platform::home_dir().to_string_lossy().to_string();
            status.shim_only = find(Platform::Windows, &home, env, |p| Path::new(p).is_file(), || None).shim_only;
        }
    }
    status
}

/// The same for a program that is already known.
pub fn status_of(exe: &str, env: &BTreeMap<String, String>) -> Status {
    let clean = clean(env);
    let (_, version_out) = run(exe, &["--version".into()], &clean, Duration::from_secs(5));
    let (auth_exit, auth_out) = run(exe, &["auth".into(), "status".into()], &clean, Duration::from_secs(10));
    let Some(version) = parse_version(&version_out) else { return Status::not_installed() };
    let shown = version.iter().map(u32::to_string).collect::<Vec<_>>().join(".");
    let mut status = Status { state: State::Unknown, executable: Some(exe.to_string()), version: Some(shown), ..Status::not_installed() };
    if check_version(Some(version)) == VersionCheck::TooOld {
        status.state = State::TooOld;
        return status;
    }
    match parse_auth(auth_exit, &auth_out) {
        Auth::SignedIn(method) => {
            status.state = State::SignedIn;
            status.auth_method = method;
        }
        Auth::SignedOut => status.state = State::SignedOut,
        Auth::Unknown => status.state = State::Unknown,
    }
    status
}

/// Runs a short program and returns its exit status and output, or a `None` status when it could not be run or took too
/// long. The output is only ever parsed, never logged.
pub fn run(exe: &str, args: &[String], env: &BTreeMap<String, String>, timeout: Duration) -> (Option<i32>, String) {
    let mut cmd = Command::new(exe);
    cmd.args(args).env_clear().envs(env).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
    crate::platform::no_console(&mut cmd);
    let Ok(mut child) = cmd.spawn() else { return (None, String::new()) };
    let mut stdout = child.stdout.take().expect("piped");
    let reader = std::thread::spawn(move || {
        let mut out = Vec::new();
        let _ = stdout.by_ref().take(65_536).read_to_end(&mut out);
        String::from_utf8_lossy(&out).to_string()
    });
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s.code(),
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                let _ = reader.join();
                return (None, String::new());
            }
        }
    };
    (status, reader.join().unwrap_or_default())
}

// ── Sign in ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/// Single-quoted for any POSIX shell, whatever the path holds (spaces, quotes, accents).
pub fn sh_quoted(path: &str) -> String {
    format!("'{}'", path.replace('\'', "'\\''"))
}

/// Single-quoted for PowerShell: a quote inside is doubled.
pub fn powershell_quoted(path: &str) -> String {
    format!("'{}'", path.replace('\'', "''"))
}

/// What a terminal runs for "Sign in": `claude auth login`, in Anthropic's own flow. NotchMeow never sees what is typed or
/// opened there.
pub fn sign_in_script(exe: &str) -> String {
    format!("echo 'Signing in. Your browser opens to finish.'; {} auth login; echo; echo 'You can close this window and go back to NotchMeow.'; read -r _", sh_quoted(exe))
}

/// The terminals tried on Linux, in order: (program, the arguments before the command to run).
const LINUX_TERMINALS: [(&str, &[&str]); 5] = [
    ("x-terminal-emulator", &["-e"]),
    ("gnome-terminal", &["--"]),
    ("konsole", &["-e"]),
    ("xfce4-terminal", &["-x"]),
    ("xterm", &["-e"]),
];

/// The command that opens a terminal running the sign-in, on Linux; `None` when no terminal is installed.
pub fn linux_terminal_command(exe: &str, on_path: impl Fn(&str) -> bool) -> Option<(String, Vec<String>)> {
    let (program, lead) = LINUX_TERMINALS.iter().find(|(p, _)| on_path(p))?;
    let mut args: Vec<String> = lead.iter().map(|a| a.to_string()).collect();
    args.extend(["sh".into(), "-c".into(), sign_in_script(exe)]);
    Some((program.to_string(), args))
}

/// Opens a terminal that runs `claude auth login`. `false` when it could not be opened.
pub fn open_sign_in(exe: &str) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NEW_CONSOLE: u32 = 0x0000_0010;
        let script = format!("& {} auth login", powershell_quoted(exe));
        Command::new("powershell.exe").args(["-NoExit", "-Command", &script]).creation_flags(CREATE_NEW_CONSOLE).spawn().is_ok()
    }
    #[cfg(not(windows))]
    {
        let Some((program, args)) = linux_terminal_command(exe, |p| crate::platform::find_on_path(p).is_some()) else { return false };
        Command::new(program).args(args).spawn().is_ok()
    }
}

// ── The folder ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// The folder to work in, from the system's own dialog. `None` when the user cancelled or no dialog is available (the
/// chat then asks for the path as text).
pub fn pick_folder() -> Option<String> {
    #[cfg(windows)]
    let output = {
        let script = "Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog; \
                      $d.Description = 'Choose the folder Claude may work in'; \
                      if ($d.ShowDialog() -eq 'OK') { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Output $d.SelectedPath }";
        let mut cmd = Command::new("powershell.exe");
        cmd.args(["-NoProfile", "-STA", "-Command", script]);
        crate::platform::no_console(&mut cmd);
        cmd.output().ok()?
    };
    #[cfg(not(windows))]
    let output = {
        let attempts: [(&str, &[&str]); 2] = [
            ("zenity", &["--file-selection", "--directory", "--title=Choose the folder Claude may work in"]),
            ("kdialog", &["--getexistingdirectory", "."]),
        ];
        let (program, args) = attempts.iter().find(|(p, _)| crate::platform::find_on_path(p).is_some())?;
        Command::new(program).args(*args).output().ok()?
    };
    let chosen = String::from_utf8_lossy(&output.stdout).lines().next()?.trim().to_string();
    (output.status.success() && !chosen.is_empty()).then_some(chosen)
}

/// A folder the chat may work in: it exists and is a folder.
pub fn check_folder(path: &str) -> Result<String, String> {
    let trimmed = path.trim();
    if !trimmed.is_empty() && Path::new(trimmed).is_dir() {
        Ok(trimmed.to_string())
    } else {
        Err("That folder isn't there.".to_string())
    }
}

#[cfg(test)]
mod tests {
```

**Edit `windows/src-tauri/src/ai/claude_run.rs`**, find this text (it occurs exactly once):

```rust
#[cfg(all(test, unix))]
mod tests {
```

and replace it with:

```rust
use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::mpsc::unbounded_channel;

use crate::ai::claude_code::{self, Stream, Turn, FOLDER_MISSING, MISSING, MODELS};
use crate::ai::provider::{
    Aggregate, AiError, BoxFuture, Capabilities, ChatChunk, ChatRequest, ErrorKind, Finish, ModelInfo, ModelProvider, Placement, Role,
};
use crate::log;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Timings {
    /// How long to wait for the run's first line. Claude Code says `system/init` within a second or two; after that it
    /// may take as long as it needs (a build can run for minutes).
    pub startup: Duration,
    /// Stop: the wait after the interrupt before the group is terminated, and after that before it is killed.
    pub interrupt_grace: Duration,
    pub terminate_grace: Duration,
    /// How long a pipe may stay open after the process exited (a grandchild that kept it).
    pub drain: Duration,
}

impl Default for Timings {
    fn default() -> Self {
        Timings {
            startup: Duration::from_secs(30),
            interrupt_grace: Duration::from_secs(2),
            terminate_grace: Duration::from_secs(2),
            drain: Duration::from_secs(1),
        }
    }
}

/// Everything one turn needs to run Claude Code, besides the message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Run {
    /// The program: found by `claude_cli::locate`, never modified.
    pub executable: String,
    /// Arguments before the turn's own. Empty, except in tests that run the fake through an interpreter.
    pub leading_args: Vec<String>,
    pub turn: Turn,
    /// Where chat-only runs happen: a folder NotchMeow owns and keeps empty.
    pub chat_folder: String,
    /// A recap of the chat so far, for a session started afresh in the middle of it.
    pub preamble: Option<String>,
    /// The caller's environment, from which the run's is made.
    pub base_env: Vec<(String, String)>,
    pub timings: Timings,
}

pub struct ClaudeCode {
    run: Run,
}

impl ClaudeCode {
    pub fn new(run: Run) -> Self {
        ClaudeCode { run }
    }
}

enum Msg {
    Line(String),
    Eof,
    Exited,
}

/// Stops the process when it is dropped: the turn's future is dropped on Stop. Safe to call twice, or after the process
/// ended.
struct StopGuard {
    pid: u32,
    exited: Arc<AtomicBool>,
    timings: Timings,
}

impl StopGuard {
    fn stop(&self) {
        if self.exited.load(Ordering::SeqCst) {
            return;
        }
        stop_process_tree(self.pid, self.timings, self.exited.clone());
    }
}

impl Drop for StopGuard {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Windows has no interrupt to give a console child: the tree goes at once.
#[cfg(windows)]
fn stop_process_tree(pid: u32, _timings: Timings, _exited: Arc<AtomicBool>) {
    let mut cmd = Command::new("taskkill");
    cmd.args(["/PID", &pid.to_string(), "/T", "/F"]).stdout(Stdio::null()).stderr(Stdio::null());
    crate::platform::no_console(&mut cmd);
    let _ = cmd.status();
}

/// Interrupt first (Claude Code ends the tool it is running), then terminate, then kill: the whole process group, so
/// whatever the run started goes too. The run was started as its own group leader.
#[cfg(unix)]
fn stop_process_tree(pid: u32, timings: Timings, _exited: Arc<AtomicBool>) {
    let group = -(pid as i32);
    let gone = move || unsafe { libc::kill(group, 0) != 0 };
    unsafe { libc::kill(group, libc::SIGINT) };
    std::thread::spawn(move || {
        let wait = |grace: Duration| {
            let start = std::time::Instant::now();
            while !gone() && start.elapsed() < grace {
                std::thread::sleep(Duration::from_millis(20));
            }
        };
        wait(timings.interrupt_grace);
        if gone() {
            return;
        }
        unsafe { libc::kill(group, libc::SIGTERM) };
        wait(timings.terminate_grace);
        if !gone() {
            unsafe { libc::kill(group, libc::SIGKILL) };
        }
    });
}

impl ModelProvider for ClaudeCode {
    fn id(&self) -> &str {
        "claudeCode"
    }

    fn display_name(&self) -> &str {
        "Claude plan"
    }

    fn placement(&self) -> Placement {
        Placement::Cloud
    }

    fn list_models(&self) -> BoxFuture<'_, Result<Vec<ModelInfo>, AiError>> {
        Box::pin(async {
            Ok(MODELS
                .iter()
                .map(|m| ModelInfo {
                    id: m.to_string(),
                    display_name: format!("Claude {}{}", m[..1].to_uppercase(), &m[1..]),
                    context_tokens: None,
                    capabilities: Capabilities { tools: true, vision: true, json: false },
                })
                .collect())
        })
    }

    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>> {
        Box::pin(self.execute(request, sink))
    }
}

impl ClaudeCode {
    async fn execute(&self, request: &ChatRequest, sink: &mut (dyn FnMut(ChatChunk) + Send)) -> Result<Aggregate, AiError> {
        let run = &self.run;
        let cwd = claude_code::working_directory(&run.turn, &run.chat_folder);
        if run.turn.level.folder().is_none() {
            let _ = std::fs::create_dir_all(&cwd);
        }
        if !Path::new(&cwd).is_dir() {
            return Err(AiError { code: Some(FOLDER_MISSING.into()), ..AiError::new(ErrorKind::BadRequest) });
        }
        let Some(message) = request.messages.iter().rev().find(|m| m.role == Role::User) else {
            return Err(AiError::new(ErrorKind::BadRequest));
        };
        let line = claude_code::user_line(&message.parts, run.preamble.as_deref());

        let mut cmd = Command::new(&run.executable);
        cmd.args(&run.leading_args)
            .args(claude_code::arguments(&run.turn))
            .env_clear()
            .envs(claude_code::environment(run.base_env.clone(), run.turn.platform))
            .current_dir(&cwd)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        crate::platform::no_console(&mut cmd);
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            cmd.process_group(0);
        }
        let Ok(mut child) = cmd.spawn() else {
            return Err(AiError { code: Some(MISSING.into()), ..AiError::new(ErrorKind::Unreachable) });
        };

        let exited = Arc::new(AtomicBool::new(false));
        let guard = StopGuard { pid: child.id(), exited: exited.clone(), timings: run.timings };
        let (tx, mut rx) = unbounded_channel::<Msg>();

        // Written on its own thread: a large PDF must not wait for the pipe while the reply is being read.
        let mut stdin = child.stdin.take().expect("piped");
        std::thread::spawn(move || {
            let _ = stdin.write_all(line.as_bytes());
        });
        let stdout = child.stdout.take().expect("piped");
        let lines = tx.clone();
        std::thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            let mut buf = Vec::new();
            loop {
                buf.clear();
                match reader.read_until(b'\n', &mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(_) => {
                        let text = String::from_utf8_lossy(&buf);
                        if lines.send(Msg::Line(text.trim_end_matches(['\n', '\r']).to_string())).is_err() {
                            return;
                        }
                    }
                }
            }
            let _ = lines.send(Msg::Eof);
        });
        let errors = Arc::new(Mutex::new(Vec::<u8>::new()));
        let stderr = child.stderr.take().expect("piped");
        let sink_errors = errors.clone();
        std::thread::spawn(move || {
            let mut reader = BufReader::new(stderr);
            let mut buf = Vec::new();
            while let Ok(n) = reader.read_until(b'\n', &mut buf) {
                if n == 0 {
                    break;
                }
                let mut all = sink_errors.lock().unwrap();
                if all.len() < 65_536 {
                    all.extend_from_slice(&buf);
                }
                buf.clear();
            }
        });
        let done = exited.clone();
        std::thread::spawn(move || {
            let _ = child.wait();
            done.store(true, Ordering::SeqCst);
            let _ = tx.send(Msg::Exited);
        });

        let mut stream = Stream::new();
        let mut finish = None;
        let (mut eof, mut gone, mut spoke) = (false, false, false);
        while !(eof && gone) {
            let limit = if gone {
                Some(run.timings.drain)
            } else if !spoke {
                Some(run.timings.startup)
            } else {
                None
            };
            let next = match limit {
                Some(wait) => tokio::time::timeout(wait, rx.recv()).await,
                None => Ok(rx.recv().await),
            };
            match next {
                Ok(Some(Msg::Line(text))) => {
                    spoke = true;
                    for chunk in stream.consume(&text) {
                        if let ChatChunk::Finish(f) = &chunk {
                            finish = Some(*f);
                        }
                        sink(chunk);
                    }
                }
                Ok(Some(Msg::Eof)) => eof = true,
                Ok(Some(Msg::Exited)) => gone = true,
                Ok(None) => break,
                // The run never said anything, or a pipe stayed open after the process ended.
                Err(_) if gone => break,
                Err(_) => {
                    guard.stop();
                    log::line("ai claude failure kind=timeout");
                    return Err(AiError::new(ErrorKind::Timeout));
                }
            }
        }

        let stderr_text = String::from_utf8_lossy(&errors.lock().unwrap()).to_string();
        let text = stream.text().to_string();
        match stream.failure(&stderr_text) {
            None => Ok(Aggregate { text, finish: finish.or(Some(Finish::Stop)), ..Aggregate::default() }),
            // What was said is kept, and marked as cut.
            Some(_) if !text.trim().is_empty() => Ok(Aggregate { text, error: Some(ErrorKind::Interrupted), ..Aggregate::default() }),
            Some(mut err) => {
                // Nothing to keep: a failed request. Steps already taken stay done, so no other model is asked.
                if err.kind == ErrorKind::Interrupted {
                    err.kind = ErrorKind::Server;
                }
                err.after_steps = stream.took_steps();
                log::line(format!("ai claude failure kind={} code={}", err.kind.as_str(), err.code.as_deref().unwrap_or("-")));
                Err(err)
            }
        }
    }
}

#[cfg(all(test, unix))]
mod tests {
```

- [ ] **Step 4: Run them**

Run: `$CL test -p notchmeow --target-dir $TD -- ai::claude_cli ai::claude_run`
Expected: PASS, `test result: ok.` and no `FAILED`: 9 tests in `claude_cli` and 6 in `claude_run`. The Stop tests wait for processes to die, so the run takes a few seconds.

```text
test ai::claude_cli::tests::a_debug_build_can_be_pointed_at_the_fake ... ok
test ai::claude_cli::tests::git_for_windows_is_looked_for_in_the_usual_places ... ok
test ai::claude_cli::tests::quoting_for_a_shell_and_for_powershell ... ok
test ai::claude_cli::tests::the_linux_terminal_is_the_first_one_installed ... ok
test ai::claude_cli::tests::a_folder_the_chat_may_work_in ... ok
test ai::claude_cli::tests::auth_status ... ok
test ai::claude_cli::tests::versions ... ok
test ai::claude_cli::tests::where_claude_is_looked_for ... ok
test ai::claude_run::tests::a_folder_with_spaces_and_non_ascii_characters ... ok
test ai::claude_run::tests::a_turn ... ok
test ai::claude_run::tests::nothing_private_reaches_the_log ... ok
test ai::claude_run::tests::two_runs_at_once_do_not_share_anything ... ok
test ai::claude_cli::tests::the_checks_against_the_fake_claude ... ok
test ai::claude_run::tests::stop_ends_the_process_and_what_it_started ... ok
test ai::claude_run::tests::failures ... ok
test result: ok. 15 passed; 0 failed; 0 ignored; 0 measured; 142 filtered out; finished in 1.16s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

- [ ] **Step 5: Prove the Stop tests can fail**

Take away what makes Stop reach the whole group, see the tests catch it, and put it back.

Run: `sed -i.bak 's/let group = -(pid as i32);/let group = pid as i32;/' windows/src-tauri/src/ai/claude_run.rs && $CL test -p notchmeow --target-dir $TD -- ai::claude_run`
Expected: FAIL, the Stop test fails: the child process survived because only the leader was signalled.

Run: `mv windows/src-tauri/src/ai/claude_run.rs.bak windows/src-tauri/src/ai/claude_run.rs && sed -i.bak 's/unsafe { libc::kill(group, libc::SIGKILL) };/let _ = group;/' windows/src-tauri/src/ai/claude_run.rs && $CL test -p notchmeow --target-dir $TD -- ai::claude_run`
Expected: FAIL, the Stop test fails: the run that ignores interrupt and terminate was never killed.

Run: `mv windows/src-tauri/src/ai/claude_run.rs.bak windows/src-tauri/src/ai/claude_run.rs && $CL test -p notchmeow --target-dir $TD -- ai::claude_run`
Expected: PASS, `test result: ok. 6 passed`.

The two broken runs left what they could not stop running: the fake `claude` and its child. End them; the patterns only ever match the fake and its sleeping child (inside the Docker container they are gone with it).

Run: `pkill -f fake_claude.py; pkill -f "import time; time.sleep\(600\)"; echo cleaned`
Expected: PASS, `cleaned`.

- [ ] **Step 6: Commit**

```bash
git add windows/src-tauri/src/ai/claude_cli.rs windows/src-tauri/src/ai/claude_run.rs windows/src-tauri/src/ai/mod.rs
git commit -q -m "feat(claude-code): the Rust locator and the runner, with a Stop that takes the whole process group" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 17: Windows/Linux: a chat's session and the turn (`claude_chat.rs`, `session.rs`, the commands)

**Agent:** `nm-implementer-deep`. The turn runs through the existing `AiState` and `run_turn`, which already own Stop, the generation guard and Auto's fallback; this task plugs Claude Code into them without changing what any other provider does.

**Files:**
- Create: `windows/src-tauri/src/ai/claude_chat.rs` (its tests are in the file)
- Modify: `windows/src-tauri/src/ai/session.rs` (its tests are in the file), `mod.rs`, `windows/src-tauri/src/lib.rs`

**Interfaces:**
- Consumes: Tasks 14 to 16 (`Step`, `EngineReport`, `AiError.after_steps/resets_at`, `claude_code::{Level, Platform, Turn}`, `claude_cli::{Status, State, status, check_folder, pick_folder, open_sign_in}`, `claude_run::{ClaudeCode, Run, Timings}`); `AiState`, `Env`, `run_turn`, `Conversation`, `testkit` (existing).
- Produces:

  ```rust
  // claude_chat.rs
  pub struct Plan { pub turn: Turn, pub needs_recap: bool, pub retired: Option<String>, pub folder: String }
  pub struct Session { … }   // Debug, Clone, PartialEq, Eq, Default (a fresh random id)
  impl Session { pub fn with_id(String) -> Self; pub fn id(&self) -> &str;
      pub fn plan(&mut self, level: &Level, model: &str, chat_folder: &str, platform: Platform, new_id: impl FnOnce() -> String) -> Plan;
      pub fn confirm_started(&mut self, folder: &str);                     // Claude Code reported the session: the next turn resumes it
      pub fn reset(&mut self, new_id: impl FnOnce() -> String) -> String } // a new conversation: the retired id
  pub struct ClaudeChat { pub session: Session, pub level: Level, pub status: Status, pub chat_folder: Option<String> }  impl ClaudeChat { pub fn reset(&mut self) -> String }
  pub fn chat_folder() -> String;  pub fn new_id() -> String;  pub fn recap(turns: &[(Role, String)]) -> Option<String>
  // session.rs
  AiEvent::ClaudeSession { session_id: String, retired: Option<String> },  AiEvent::Step(Step),  AiEvent::Engine(EngineReport),  AiEvent::Error { …, resets_at: Option<u64> }
  Env.claude: Arc<Mutex<ClaudeChat>>;  Target.claude: Option<ClaudeTarget>;  pub struct ClaudeTarget { run, session_id, retired, folder, needs_recap }
  // mod.rs: AiState.claude, and four Tauri commands
  claude_status() -> Result<claude_cli::Status, String>;  claude_set_level(level: String, folder: Option<String>) -> Result<LevelDto, String>;
  claude_pick_folder() -> Option<String>;  claude_sign_in() -> Result<bool, String>
  ```

  The rules. **Readiness:** `ready_clouds` adds `claudeCode` to the router's `keys` only when the user connected it (`claude_code_enabled`) and the last check found it signed in; the check runs when Settings opens (`claude_status`) and before a chat's first turn (`ai_chat`), never on a timer. **A session lives under its working folder** exactly as on the Mac (Task 8): a level change that keeps the folder resumes the session, one that moves it starts a new one with a text recap and emits `ClaudeSession { retired }` so the front end drops the old id. **The webview learns the session id before anything runs** (`ClaudeSession`), so a `PermissionRequest` carrying it is the chat's. **Steps taken, no other model:** a failure after steps (`after_steps`) never falls back, and a plan limit (kind `billing`) never falls back or counts down; it carries `resets_at` so the island words it in the viewer's time zone. `claude_set_level` takes `chat`, or `read`/`agent` with a folder that exists (the front end gets the folder from `claude_pick_folder`, or asks for the path as text where the system has no dialog); a new conversation (`AiState::reset`) puts the chat back at Chat only on a new session.

- [ ] **Step 1: Write the failing tests**

`claude_chat.rs` holds only its tests for now (the session across a level change, a real id being a lower-case version-4 UUID, a new chat at Chat only, the recap), and the module is declared. In `session.rs`: readiness (connected and signed in, never connected, signed out), a whole Claude turn through the existing pipeline with the fake `claude` behind a shell script (the session event first, the caption "cloud · Claude plan · Sonnet", the engine report, the steps ending with the failed one, the reply as paragraphs, the next turn resuming), a level change that moves the folder (a new session with a recap, no `--resume`), the plan limit (a time, no fallback, the local model never asked), steps taken then a crash (no fallback, no notice), and a `claude` that is not installed (temporary, nothing done, so the one local retry runs). The level-change test is Review Focus 1 on this side (a new session, a recap in front of the new message, the old id retired), and `claude_chat`'s tests are the session rules.

**Edit `windows/src-tauri/src/ai/mod.rs`**, find this text (it occurs exactly once):

```rust
pub mod budget;
pub mod catalog;
pub mod claude_cli;
pub mod claude_code;
```

and replace it with:

```rust
pub mod budget;
pub mod catalog;
pub mod claude_chat;
pub mod claude_cli;
pub mod claude_code;
```

**Create `windows/src-tauri/src/ai/claude_chat.rs`** with exactly this content (only its tests for now):

```rust
// One chat's Claude Code session: its id, whether it has started, the level the chat is at, and what a level change means.
// Mirrors NotchBuddy/Sources/App/AI/Core/ClaudeChatSession.swift. Pure: `AiState` holds one `ClaudeChat` and `session.rs`
// asks it for each turn.

#[cfg(test)]
mod tests {
    use super::*;

    const CHAT: &str = "/support/NotchMeow/claude-chat";

    fn ids() -> impl FnMut() -> String {
        let mut n = 0;
        move || {
            n += 1;
            format!("id-{n}")
        }
    }

    #[test]
    fn a_chats_session() {
        let mut next = ids();
        let mut chat = Session::with_id(next());
        let first = chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((first.turn.level.clone(), first.turn.resume, first.needs_recap, first.turn.session_id.as_str()), (Level::ChatOnly, false, false, "id-1"));

        let mut again = chat.clone();
        assert!(!again.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next).turn.resume, "a turn that never reached init is planned the same way");

        chat.confirm_started(CHAT);
        assert!(chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next).turn.resume, "after init the next turn resumes");

        let project = "/home/zoe/projects/notchmeow";
        let moved = chat.plan(&Level::ReadOnly(project.into()), "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((moved.turn.session_id.as_str(), moved.turn.resume, moved.needs_recap), ("id-2", false, true), "a level change that moves the working folder starts a new session");
        assert_eq!(moved.retired.as_deref(), Some("id-1"), "and retires the old one");
        chat.confirm_started(project);

        let kept = chat.plan(&Level::Agent(project.into()), "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((kept.turn.session_id.as_str(), kept.turn.resume, kept.needs_recap, kept.retired), ("id-2", true, false, None), "Read-only to Agent in the same folder resumes the session");
        assert_eq!(kept.turn.level, Level::Agent(project.into()), "with the new flags");

        let back = chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((back.turn.session_id.as_str(), back.needs_recap, back.retired.as_deref()), ("id-3", true, Some("id-2")), "Agent back to Chat only moves it again");

        let mut reset = chat.clone();
        assert_eq!(reset.reset(|| "id-9".into()), "id-3");
        assert_eq!((reset.id(), reset.started), ("id-9", false), "a new conversation retires the id and starts clean");
    }

    #[test]
    fn a_real_id_is_a_lower_case_version_4_uuid() {
        for _ in 0..3 {
            let id = new_id();
            let parts: Vec<&str> = id.split('-').collect();
            assert_eq!(parts.iter().map(|p| p.len()).collect::<Vec<_>>(), [8, 4, 4, 4, 12], "{id}");
            assert!(id.chars().all(|c| c == '-' || c.is_ascii_hexdigit() && !c.is_ascii_uppercase()), "{id}");
            assert!(parts[2].starts_with('4') && "89ab".contains(&parts[3][..1]), "{id}");
        }
        assert_ne!(new_id(), new_id());
    }

    #[test]
    fn a_new_chat_starts_at_chat_only() {
        let mut chat = ClaudeChat::default();
        chat.level = Level::Agent("/x".into());
        let old = chat.session.id().to_string();
        assert_eq!(chat.reset(), old);
        assert_eq!(chat.level, Level::ChatOnly);
        assert_ne!(chat.session.id(), old);
    }

    #[test]
    fn the_recap_of_a_chat() {
        assert_eq!(recap(&[]), None, "nothing to recall");
        let text = recap(&[(Role::User, "What is in main.rs?".into()), (Role::Assistant, "A greeting.".into()), (Role::User, "  ".into()), (Role::User, "Thanks".into())]).unwrap();
        assert_eq!(text.lines().skip(1).collect::<Vec<_>>(), ["User: What is in main.rs?", "Assistant: A greeting.", "User: Thanks"], "the words, in order, with who said them");
        assert!(recap(&[(Role::User, "x".repeat(5000))]).unwrap().chars().count() < 1700, "a long turn is cut");
        let many: Vec<(Role, String)> = (0..60).map(|i| (Role::User, format!("message {i} {}", "y".repeat(1200)))).collect();
        let recent = recap(&many).unwrap();
        assert!(recent.chars().count() <= RECAP_MAX_CHARS + 200 && recent.contains("message 59") && !recent.contains("message 0 "), "only the most recent turns, within the budget");
    }
}
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
        Env {
            settings: AiSettings::default(),
            keys: keys.iter().map(|k| (k.to_string(), Some("test-key".to_string()))).collect(),
            servers: local.map(|f| vec![running("ollama", &f.base, Placement::Local)]).unwrap_or_default(),
```

and replace it with:

```rust
        Env {
            settings: AiSettings::default(),
            claude: Default::default(),
            keys: keys.iter().map(|k| (k.to_string(), Some("test-key".to_string()))).collect(),
            servers: local.map(|f| vec![running("ollama", &f.base, Placement::Local)]).unwrap_or_default(),
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
    }

    #[tokio::test]
    async fn auto_with_a_key_answers_from_the_cloud_and_streams() {
```

and replace it with:

```rust
    }

    // ── Claude Code ──────────────────────────────────────────────────────────────────────────────────────────────────

    /// A `claude` that is a shell script around the fake, with its transcript and log fixed in the script itself, so no
    /// test touches the process environment (tests run in parallel).
    #[cfg(unix)]
    fn claude_script(dir: &testkit::TempDir, transcript: &str, name: &str) -> (String, String) {
        use std::os::unix::fs::PermissionsExt;
        let python = testkit::python();
        let log = dir.path().join(format!("{name}.jsonl")).to_string_lossy().to_string();
        let body = format!(
            "#!/bin/sh\nexport NM_FAKE_CLAUDE_TRANSCRIPT='{}'\nexport NM_FAKE_CLAUDE_LOG='{log}'\nexec {} {} '{}' \"$@\"\n",
            transcript,
            python.get_program().to_string_lossy(),
            python.get_args().map(|a| a.to_string_lossy().to_string()).collect::<Vec<_>>().join(" "),
            testkit::fixtures_dir().join("claude-code/fake_claude.py").display(),
        );
        let path = dir.path().join(name);
        std::fs::write(&path, body).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        (path.to_string_lossy().to_string(), log)
    }

    fn transcript(name: &str) -> String {
        testkit::fixtures_dir().join("claude-code/transcripts").join(name).to_string_lossy().to_string()
    }

    /// An Env where the user connected "Use my Claude plan" and Claude Code is signed in.
    fn claude_env(dir: &testkit::TempDir, exe: &str) -> Env {
        let mut env = env(&[], None, None);
        env.settings.claude_code_enabled = true;
        env.settings.preferred_cloud = "claudeCode".into();
        {
            let mut chat = env.claude.lock().unwrap();
            chat.status = crate::ai::claude_cli::Status {
                state: crate::ai::claude_cli::State::SignedIn,
                executable: Some(exe.to_string()),
                version: Some("2.1.211".into()),
                auth_method: Some("claude.ai".into()),
                shim_only: false,
                needs_git: false,
            };
            chat.chat_folder = Some(dir.path().join("chat").to_string_lossy().to_string());
        }
        env
    }

    fn fake_calls(log: &str) -> Vec<serde_json::Value> {
        std::fs::read_to_string(log).unwrap_or_default().lines().filter_map(|l| serde_json::from_str(l).ok()).collect()
    }

    #[test]
    fn claude_code_is_ready_only_when_connected_and_signed_in() {
        let dir = testkit::TempDir::new("claude-ready");
        let mut env = claude_env(&dir, "/x/claude");
        assert!(route_input(&env, Feature::Chat).keys.contains(&"claudeCode".to_string()));
        env.settings.claude_code_enabled = false;
        assert!(!route_input(&env, Feature::Chat).keys.contains(&"claudeCode".to_string()), "never connected: not used");
        env.settings.claude_code_enabled = true;
        env.claude.lock().unwrap().status.state = crate::ai::claude_cli::State::SignedOut;
        assert!(!route_input(&env, Feature::Chat).keys.contains(&"claudeCode".to_string()), "signed out: not ready");
        let res = resolve(&claude_env(&dir, "/x/claude"), Feature::Chat);
        assert_eq!((res.provider.as_deref(), res.model.as_deref(), res.model_name.as_deref()), (Some("claudeCode"), Some("sonnet"), Some("sonnet")));
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn a_claude_turn_streams_steps_and_text_and_confirms_the_session() {
        let dir = testkit::TempDir::new("claude-turn");
        let (exe, log) = claude_script(&dir, &transcript("tool-use.jsonl"), "claude");
        let mut env = claude_env(&dir, &exe);
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("read it")).await;
        let id = env.claude.lock().unwrap().session.id().to_string();
        assert!(matches!(&events[0], AiEvent::ClaudeSession { session_id, retired: None } if *session_id == id), "the chat learns the session before anything runs: {events:?}");
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { caption, fallback: false, .. } if caption == "cloud · Claude plan · Sonnet")));
        assert!(events.iter().any(|e| matches!(e, AiEvent::Engine(r) if r.model == "claude-sonnet-5-5")));
        let steps: Vec<String> = events.iter().filter_map(|e| if let AiEvent::Step(s) = e { Some(format!("{}:{:?}", s.id, s.state)) } else { None }).collect();
        assert_eq!(steps.last().map(String::as_str), Some("toolu_01B:Failed"));
        assert_eq!(done_text(&events).as_deref(), Some("I'll read the README.\n\nIt says it is a tiny demo."));
        assert_eq!(conv.lock().unwrap().turns.len(), 2);
        let again = env.claude.lock().unwrap().session.plan(&claude_code::Level::ChatOnly, "sonnet", &dir.path().join("chat").to_string_lossy(), Platform::Linux, || "x".into());
        assert!(again.turn.resume, "Claude Code made the session: the next turn resumes it");
        assert_eq!(fake_calls(&log).iter().filter(|c| c["argv"][0] == "-p").count(), 1);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn a_level_change_that_moves_the_folder_starts_a_new_session_with_a_recap() {
        let dir = testkit::TempDir::new("claude-move");
        let (exe, log) = claude_script(&dir, &transcript("success.jsonl"), "claude");
        let mut env = claude_env(&dir, &exe);
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("first question")).await;
        let first = env.claude.lock().unwrap().session.id().to_string();
        let project = dir.path().join("project");
        std::fs::create_dir_all(&project).unwrap();
        env.claude.lock().unwrap().level = claude_code::Level::ReadOnly(project.to_string_lossy().to_string());
        let events = turn(&mut env, &conv, ask("second question")).await;
        assert!(matches!(&events[0], AiEvent::ClaudeSession { session_id, retired: Some(old) } if *old == first && *session_id != first), "the old id is retired: {events:?}");
        let calls: Vec<serde_json::Value> = fake_calls(&log).into_iter().filter(|c| c["argv"][0] == "-p").collect();
        assert_eq!(calls.len(), 2);
        let argv: Vec<&str> = calls[1]["argv"].as_array().unwrap().iter().map(|a| a.as_str().unwrap()).collect();
        assert!(argv.contains(&"--session-id") && !argv.contains(&"--resume"), "a new session, not a resume that could not find the old one");
        let stdin: serde_json::Value = serde_json::from_str(calls[1]["stdin"].as_str().unwrap()).unwrap();
        let texts: Vec<&str> = stdin["message"]["content"].as_array().unwrap().iter().map(|b| b["text"].as_str().unwrap()).collect();
        assert!(texts[0].starts_with("Earlier in this chat") && texts[0].contains("User: first question") && texts[1] == "second question", "{texts:?}");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn the_plan_limit_says_when_it_resets_and_never_falls_back() {
        let dir = testkit::TempDir::new("claude-limit");
        let (exe, _) = claude_script(&dir, &transcript("plan-limit.jsonl"), "claude");
        let local = FakeServer::start(&[]);
        let mut env = claude_env(&dir, &exe);
        env.servers = vec![running("ollama", &local.base, Placement::Local)];
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        match events.last().unwrap() {
            AiEvent::Error { kind, message, resets_at, action, retry_after } => {
                assert_eq!((*kind, message.as_str(), *resets_at, action.is_none(), retry_after.is_none()), (ErrorKind::Billing, "Your Claude plan's limit was reached.", Some(1_791_301_500), true, true));
            }
            other => panic!("{other:?}"),
        }
        assert!(local.requests().is_empty(), "the local model must not be asked");
        assert!(conv.lock().unwrap().turns.is_empty(), "a failed message leaves no half turn");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn steps_already_taken_are_never_handed_to_another_model() {
        let dir = testkit::TempDir::new("claude-steps");
        // A step starts, then the run dies with nothing said: a temporary failure, but the step stays done.
        let broken = dir.path().join("steps-then-crash.jsonl");
        std::fs::write(&broken, "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"__SESSION_ID__\",\"model\":\"claude-sonnet-5-5\",\"apiKeySource\":\"none\"}\n{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"Bash\",\"input\":{}}}}\n").unwrap();
        let (exe, _) = claude_script(&dir, &broken.to_string_lossy(), "claude");
        let local = FakeServer::start(&[]);
        let mut env = claude_env(&dir, &exe);
        env.servers = vec![running("ollama", &local.base, Placement::Local)];
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("run it")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Server, message, .. } if message == "Claude stopped unexpectedly."), "{events:?}");
        assert!(local.requests().is_empty(), "Auto does not ask the local model after steps");
        assert!(!events.iter().any(|e| matches!(e, AiEvent::Notice { .. })), "and says nothing about falling back");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn a_claude_that_is_not_installed_falls_back_like_any_cloud() {
        let dir = testkit::TempDir::new("claude-missing");
        let local = FakeServer::start(&["--persona", "ollama"]);
        let mut env = claude_env(&dir, "/nonexistent/claude");
        env.servers = vec![running("ollama", &local.base, Placement::Local)];
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { fallback: true, .. })), "temporary, nothing done: the local retry runs: {events:?}");
    }

    #[tokio::test]
    async fn auto_with_a_key_answers_from_the_cloud_and_streams() {
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Error { kind: ErrorKind::Auth, message: "Your Anthropic key was rejected.".into(), action: Some(Action::OpenSettings), retry_after: None }
        );
        assert!(local.requests().is_empty(), "the local model must not be asked");
```

and replace it with:

```rust
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Error { kind: ErrorKind::Auth, message: "Your Anthropic key was rejected.".into(), action: Some(Action::OpenSettings), retry_after: None, resets_at: None }
        );
        assert!(local.requests().is_empty(), "the local model must not be asked");
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
                action: Some(Action::OpenGuide),
                retry_after: None,
            }
        );
```

and replace it with:

```rust
                action: Some(Action::OpenGuide),
                retry_after: None,
                resets_at: None,
            }
        );
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
        let event = AiEvent::Problem { kind: ProblemKind::CantSee, message: "x".into(), action: None };
        assert_eq!(serde_json::to_value(event).unwrap(), serde_json::json!({ "type": "problem", "kind": "cant_see", "message": "x", "action": null }));
        let event = AiEvent::Error { kind: ErrorKind::RateLimited, message: "x".into(), action: None, retry_after: Some(2) };
        assert_eq!(
            serde_json::to_value(event).unwrap(),
```

and replace it with:

```rust
        let event = AiEvent::Problem { kind: ProblemKind::CantSee, message: "x".into(), action: None };
        assert_eq!(serde_json::to_value(event).unwrap(), serde_json::json!({ "type": "problem", "kind": "cant_see", "message": "x", "action": null }));
        let event = AiEvent::Error { kind: ErrorKind::RateLimited, message: "x".into(), action: None, retry_after: Some(2), resets_at: None };
        assert_eq!(
            serde_json::to_value(event).unwrap(),
```

- [ ] **Step 2: Run them to see them fail**

Run: `$CL test -p notchmeow --target-dir $TD -- ai::claude_chat ai::session`
Expected: FAIL, compile errors: `cannot find` the session types the tests use (`Level`, `Platform`, `ClaudeChat`).

```text
error[E0433]: cannot find type `Level` in this scope
error[E0433]: cannot find type `Platform` in this scope
error[E0433]: cannot find type `Level` in this scope
```

- [ ] **Step 3: Write the session, plug it into the turn, and add the commands**

The implementation goes in front of the test module of `claude_chat.rs`.

**Edit `windows/src-tauri/src/ai/claude_chat.rs`**, find this text (it occurs exactly once):

```rust
#[cfg(test)]
mod tests {
```

and replace it with:

```rust
use crate::ai::claude_cli::Status;
use crate::ai::claude_code::{Level, Platform, Turn};
use crate::ai::provider::Role;

/// What the next turn is: the run to make, whether it needs a recap of the chat so far, and the id that is retired because
/// the session could not be continued.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    pub turn: Turn,
    pub needs_recap: bool,
    pub retired: Option<String>,
    /// The folder this turn runs in (what `confirm_started` is told when Claude Code reports the session).
    pub folder: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Session {
    session_id: String,
    /// Claude Code has created the session (it said so in `system/init`): later turns resume it.
    started: bool,
    /// Claude Code keeps a session under the folder it ran in, so it can only be resumed from there.
    started_in: Option<String>,
}

/// Where Chat only runs happen: a folder NotchMeow owns and keeps empty (`%APPDATA%\NotchMeow\claude-chat` on Windows).
pub fn chat_folder() -> String {
    crate::settings::config_dir().join("claude-chat").to_string_lossy().to_string()
}

pub fn new_id() -> String {
    // A random version-4 UUID. It is an identifier, not a secret (it is in the process list), so no new crate for it.
    let mut bytes = [0u8; 16];
    #[cfg(unix)]
    {
        use std::io::Read;
        if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
            let _ = f.read_exact(&mut bytes);
        }
    }
    #[cfg(not(unix))]
    {
        // Windows: the hasher's random keys are seeded by the OS for every process and every `RandomState`.
        use std::hash::{BuildHasher, Hasher};
        for chunk in bytes.chunks_mut(8) {
            let mut h = std::collections::hash_map::RandomState::new().build_hasher();
            h.write_u64(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0));
            chunk.copy_from_slice(&h.finish().to_le_bytes()[..chunk.len()]);
        }
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("{}-{}-{}-{}-{}", &hex[0..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..32])
}

impl Default for Session {
    fn default() -> Self {
        Session::with_id(new_id())
    }
}

impl Session {
    pub fn with_id(session_id: String) -> Self {
        Session { session_id, started: false, started_in: None }
    }

    pub fn id(&self) -> &str {
        &self.session_id
    }

    /// The next turn. A level change that keeps the working folder resumes the same session with the new flags. One that
    /// moves it (Agent in a project, then Chat only) starts a new session, to be seeded with a recap, and retires the old
    /// id: Claude Code could not find the old session from the new folder, and a late approval request from it must be
    /// refused.
    pub fn plan(&mut self, level: &Level, model: &str, chat_folder: &str, platform: Platform, new_id: impl FnOnce() -> String) -> Plan {
        let folder = level.folder().unwrap_or(chat_folder).to_string();
        let mut retired = None;
        let mut recap = false;
        if self.started && self.started_in.as_deref() != Some(folder.as_str()) {
            retired = Some(std::mem::replace(&mut self.session_id, new_id()));
            self.started = false;
            self.started_in = None;
            recap = true;
        }
        let turn = Turn { level: level.clone(), model: model.to_string(), session_id: self.session_id.clone(), resume: self.started, platform };
        Plan { turn, needs_recap: recap, retired, folder }
    }

    /// Claude Code reported the session: the next turn resumes it.
    pub fn confirm_started(&mut self, folder: &str) {
        self.started = true;
        self.started_in = Some(folder.to_string());
    }

    /// A new conversation: the old id is returned so it can be retired, and nothing of it is kept.
    pub fn reset(&mut self, new_id: impl FnOnce() -> String) -> String {
        std::mem::replace(self, Session::with_id(new_id())).session_id
    }
}

/// The chat's side of Claude Code: its session, its level, and what the last check found.
#[derive(Debug, Clone)]
pub struct ClaudeChat {
    pub session: Session,
    pub level: Level,
    pub status: Status,
    /// Where Chat only runs. `None` is `chat_folder()`; a test points it at a folder of its own.
    pub chat_folder: Option<String>,
}

impl Default for ClaudeChat {
    fn default() -> Self {
        ClaudeChat { session: Session::default(), level: Level::ChatOnly, status: Status::not_installed(), chat_folder: None }
    }
}

impl ClaudeChat {
    /// A new conversation starts at Chat only, on a new session. Returns the id that was retired.
    pub fn reset(&mut self) -> String {
        self.level = Level::ChatOnly;
        self.session.reset(new_id)
    }
}

const RECAP_MAX_TURNS: usize = 20;
const RECAP_MAX_TURN_CHARS: usize = 1_500;
const RECAP_MAX_CHARS: usize = 20_000;

/// A recap of the chat so far, for a session started afresh in the middle of it. `None` when there is nothing to recall.
/// Oldest turns go first when it is too long. Only the words are kept (no file bodies).
pub fn recap(turns: &[(Role, String)]) -> Option<String> {
    let skip = turns.len().saturating_sub(RECAP_MAX_TURNS);
    let mut lines: Vec<String> = turns[skip..]
        .iter()
        .filter_map(|(role, text)| {
            let words = text.trim();
            if words.is_empty() {
                return None;
            }
            let cut = if words.chars().count() > RECAP_MAX_TURN_CHARS {
                format!("{}…", words.chars().take(RECAP_MAX_TURN_CHARS).collect::<String>())
            } else {
                words.to_string()
            };
            Some(format!("{}{cut}", if *role == Role::User { "User: " } else { "Assistant: " }))
        })
        .collect();
    while lines.join("\n").chars().count() > RECAP_MAX_CHARS && lines.len() > 1 {
        lines.remove(0);
    }
    (!lines.is_empty()).then(|| format!("Earlier in this chat, for context only (it is already answered):\n{}", lines.join("\n")))
}

#[cfg(test)]
mod tests {
```

The turn: readiness, the target, the provider, the events, and Auto's rule about steps.

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
use crate::ai::budget;
use crate::ai::catalog::{self, Api};
use crate::ai::discovery::{self, Probe, Server, ServerStatus};
use crate::ai::errors::{self, Action, Who};
use crate::ai::openai::OpenAI;
use crate::ai::openai_compat::OpenAICompat;
use crate::ai::provider::{
    file_label, AiError, Aggregate, ChatChunk, ChatRequest, Endpoint, ErrorKind, Finish, Message, ModelInfo,
    ModelProvider, Part, Placement, Role, Timeouts,
};
use crate::ai::router::{self, Choice, ModelRef, Outcome, Ready, RouteInput};
```

and replace it with:

```rust
use crate::ai::budget;
use crate::ai::catalog::{self, Api};
use crate::ai::claude_chat::{self, ClaudeChat};
use crate::ai::claude_code::{self, Platform};
use crate::ai::claude_run::{ClaudeCode, Run, Timings as ClaudeTimings};
use crate::ai::discovery::{self, Probe, Server, ServerStatus};
use crate::ai::errors::{self, Action, Who};
use crate::ai::openai::OpenAI;
use crate::ai::openai_compat::OpenAICompat;
use crate::ai::provider::{
    file_label, AiError, Aggregate, ChatChunk, ChatRequest, Endpoint, EngineReport, ErrorKind, Finish, Message, ModelInfo,
    ModelProvider, Part, Placement, Role, Step, Timeouts,
};
use crate::ai::router::{self, Choice, ModelRef, Outcome, Ready, RouteInput};
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
    /// A failure of a provider or the network: `kind` is one of the contract's twelve
    /// `ErrorKind`s, spelled as in `ErrorKind::as_str`. `retry_after` is set when the island
    /// should count down and send again.
    Error { kind: ErrorKind, message: String, action: Option<Action>, retry_after: Option<u64> },
    /// One of the island's own notices (`ProblemKind`), not a contract error kind.
    Problem { kind: ProblemKind, message: String, action: Option<Action> },
```

and replace it with:

```rust
    /// A failure of a provider or the network: `kind` is one of the contract's twelve
    /// `ErrorKind`s, spelled as in `ErrorKind::as_str`. `retry_after` is set when the island
    /// should count down and send again. `resets_at` (Unix seconds) is when a usage limit resets: the
    /// island words it in the viewer's time zone.
    Error {
        kind: ErrorKind,
        message: String,
        action: Option<Action>,
        retry_after: Option<u64>,
        #[serde(skip_serializing_if = "Option::is_none")]
        resets_at: Option<u64>,
    },
    /// Claude Code: the session this run belongs to, so its hook events are the chat's and not a pill's. `retired` is the
    /// id this turn gave up (a level change that moved the working folder).
    ClaudeSession { session_id: String, retired: Option<String> },
    /// A step Claude Code is taking, or has finished (the same `id` updates the same row).
    Step(Step),
    /// What Claude Code said about the run it started: which model, and who pays.
    Engine(EngineReport),
    /// One of the island's own notices (`ProblemKind`), not a contract error kind.
    Problem { kind: ProblemKind, message: String, action: Option<Action> },
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
    /// The debug-only cloud redirect (`catalog::debug_override()`).
    pub cloud_override: Option<String>,
    /// Model lists already fetched, for display names and Google's default.
    pub models: HashMap<String, Vec<ModelInfo>>,
```

and replace it with:

```rust
    /// The debug-only cloud redirect (`catalog::debug_override()`).
    pub cloud_override: Option<String>,
    /// The chat's Claude Code session, level and last status.
    pub claude: Arc<Mutex<ClaudeChat>>,
    /// Model lists already fetched, for display names and Google's default.
    pub models: HashMap<String, Vec<ModelInfo>>,
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
}

pub fn route_input(env: &Env, feature: Feature) -> RouteInput {
    RouteInput {
        setting: env.settings.choice(feature).clone(),
        preferred_cloud: env.settings.preferred_cloud.clone(),
        keys: catalog::CLOUD_ORDER.iter().filter(|p| env.keys.contains_key(**p)).map(|p| p.to_string()).collect(),
        online: true,
        local_ready: ready_list(env),
```

and replace it with:

```rust
}

/// The cloud providers Auto may use: those with a key, and Claude Code once the user connected it and the last check found
/// it signed in.
fn ready_clouds(env: &Env) -> Vec<String> {
    let mut ready: Vec<String> = catalog::CLOUD_ORDER.iter().filter(|p| env.keys.contains_key(**p)).map(|p| p.to_string()).collect();
    if env.settings.claude_code_enabled && env.claude.lock().unwrap().status.is_ready() {
        ready.push("claudeCode".to_string());
    }
    ready
}

pub fn route_input(env: &Env, feature: Feature) -> RouteInput {
    RouteInput {
        setting: env.settings.choice(feature).clone(),
        preferred_cloud: env.settings.preferred_cloud.clone(),
        keys: ready_clouds(env),
        online: true,
        local_ready: ready_list(env),
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
    pub context_tokens: Option<u64>,
    host: String,
}

```

and replace it with:

```rust
    pub context_tokens: Option<u64>,
    host: String,
    /// Claude Code: the run to make (it has no URL, no key and no server).
    pub claude: Option<ClaudeTarget>,
}

/// One Claude Code turn: the process to run, and what the chat must learn about its session.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClaudeTarget {
    pub run: Run,
    pub session_id: String,
    pub retired: Option<String>,
    /// The folder the turn runs in, told to the session when Claude Code reports it.
    pub folder: String,
    /// The session is new in the middle of a chat: the first message carries a recap.
    pub needs_recap: bool,
}

```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
/// looked for again when the last discovery didn't see it running.
async fn target_for(env: &mut Env, provider: &str, model: Option<String>) -> Result<Target, TargetError> {
    if catalog::is_cloud(provider) {
        let def = catalog::get(provider).unwrap();
```

and replace it with:

```rust
/// looked for again when the last discovery didn't see it running.
async fn target_for(env: &mut Env, provider: &str, model: Option<String>) -> Result<Target, TargetError> {
    if provider == "claudeCode" {
        return Ok(claude_target(env, model));
    }
    if catalog::is_cloud(provider) {
        let def = catalog::get(provider).unwrap();
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
            .map(|m| m.display_name.clone())
            .unwrap_or_else(|| model.clone());
        return Ok(Target { endpoint, model, model_name, vision: true, context_tokens: None, host: String::new() });
    }

```

and replace it with:

```rust
            .map(|m| m.display_name.clone())
            .unwrap_or_else(|| model.clone());
        return Ok(Target { endpoint, model, model_name, vision: true, context_tokens: None, host: String::new(), claude: None });
    }

```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
        model,
        host: server.host.clone(),
    })
}

fn prepare_event(err: PrepareError) -> AiEvent {
    match err {
```

and replace it with:

```rust
        model,
        host: server.host.clone(),
        claude: None,
    })
}

/// Claude Code: the chat's session plans the turn (resume it, or start a new one when the level moved the folder).
fn claude_target(env: &Env, model: Option<String>) -> Target {
    let alias = model.filter(|m| claude_code::MODELS.contains(&m.as_str())).unwrap_or_else(|| env.settings.claude_code_model.clone());
    let (plan, executable, chat_folder) = {
        let mut chat = env.claude.lock().unwrap();
        let chat_folder = chat.chat_folder.clone().unwrap_or_else(claude_chat::chat_folder);
        let (level, executable) = (chat.level.clone(), chat.status.executable.clone().unwrap_or_default());
        (chat.session.plan(&level, &alias, &chat_folder, Platform::current(), claude_chat::new_id), executable, chat_folder)
    };
    let label = format!("{}{}", alias[..1].to_uppercase(), &alias[1..]);
    let run = Run {
        executable,
        leading_args: Vec::new(),
        turn: plan.turn,
        chat_folder,
        preamble: None,
        base_env: std::env::vars().collect(),
        timings: ClaudeTimings::default(),
    };
    Target {
        endpoint: Endpoint {
            provider: "claudeCode".into(),
            name: "Claude plan".into(),
            base_url: String::new(),
            key: None,
            placement: Placement::Cloud,
            timeouts: env.timeouts(Placement::Cloud),
        },
        model: alias,
        model_name: format!("Claude plan · {label}"),
        vision: true,
        context_tokens: None,
        host: String::new(),
        claude: Some(ClaudeTarget { session_id: run.turn.session_id.clone(), retired: plan.retired, folder: plan.folder, needs_recap: plan.needs_recap, run }),
    }
}

fn prepare_event(err: PrepareError) -> AiEvent {
    match err {
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
        Err(event) => return Attempt::Stopped(event),
    };
    let provider = make_provider(target.endpoint.clone());
    log::line(format!("ai start provider={} placement={} fallback={fallback}", provider.id(), provider.placement().as_str()));
    emit(AiEvent::Started {
```

and replace it with:

```rust
        Err(event) => return Attempt::Stopped(event),
    };
    let claude_chat = env.claude.clone();
    let provider: Box<dyn ModelProvider> = match target.claude.as_mut() {
        Some(claude) => {
            // A session started afresh in the middle of a chat is told what was said before (the new message is last).
            if claude.needs_recap {
                let said: Vec<(Role, String)> = turns[..turns.len().saturating_sub(1)].iter().map(|t| (t.role, t.text.clone())).collect();
                claude.run.preamble = claude_chat::recap(&said);
            }
            emit(AiEvent::ClaudeSession { session_id: claude.session_id.clone(), retired: claude.retired.clone() });
            Box::new(ClaudeCode::new(claude.run.clone()))
        }
        None => make_provider(target.endpoint.clone()),
    };
    let claude_folder = target.claude.as_ref().map(|c| c.folder.clone());
    log::line(format!("ai start provider={} placement={} fallback={fallback}", provider.id(), provider.placement().as_str()));
    emit(AiEvent::Started {
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
            }
            ChatChunk::Citation { url, title } => emit(AiEvent::Citation { url, title }),
            _ => {}
        };
```

and replace it with:

```rust
            }
            ChatChunk::Citation { url, title } => emit(AiEvent::Citation { url, title }),
            ChatChunk::Step(step) => emit(AiEvent::Step(step)),
            ChatChunk::Engine(report) => {
                // Claude Code has made the session: the next turn resumes it, from the same folder.
                if let Some(folder) = &claude_folder {
                    claude_chat.lock().unwrap().session.confirm_started(folder);
                }
                emit(AiEvent::Engine(report));
            }
            _ => {}
        };
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
        action: w.action,
        retry_after: countdown.then(|| err.retry_after.unwrap_or(errors::DEFAULT_RETRY_SECONDS)),
    }
}
```

and replace it with:

```rust
        action: w.action,
        retry_after: countdown.then(|| err.retry_after.unwrap_or(errors::DEFAULT_RETRY_SECONDS)),
        resets_at: err.resets_at,
    }
}
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
            log::line(format!("ai refusal provider={}", target.endpoint.provider));
            let message = if text.trim().is_empty() { errors::error_copy(ErrorKind::Refusal, &target.who(), None).text } else { text };
            emit(AiEvent::Error { kind: ErrorKind::Refusal, message, action: None, retry_after: None });
            None
        }
```

and replace it with:

```rust
            log::line(format!("ai refusal provider={}", target.endpoint.provider));
            let message = if text.trim().is_empty() { errors::error_copy(ErrorKind::Refusal, &target.who(), None).text } else { text };
            emit(AiEvent::Error { kind: ErrorKind::Refusal, message, action: None, retry_after: None, resets_at: None });
            None
        }
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
    }
    let decision = router::route(&after);
    if decision.outcome != Outcome::Fallback {
        undo_user(conv, generation, pushed);
        emit(error_event(&err, &who));
```

and replace it with:

```rust
    }
    let decision = router::route(&after);
    // Claude Code took steps before it failed: they stay done, and no other model is asked the same question.
    if decision.outcome != Outcome::Fallback || err.after_steps {
        undo_user(conv, generation, pushed);
        emit(error_event(&err, &who));
```

**Edit `windows/src-tauri/src/ai/session.rs`**, find this text (it occurs exactly once):

```rust
    let model = match &input.setting {
        Choice::Explicit(m) => Some(m.model.clone()),
        Choice::Auto(_) if catalog::is_cloud(&primary) => env
            .settings
```

and replace it with:

```rust
    let model = match &input.setting {
        Choice::Explicit(m) => Some(m.model.clone()),
        Choice::Auto(_) if primary == "claudeCode" => Some(env.settings.claude_code_model.clone()),
        Choice::Auto(_) if catalog::is_cloud(&primary) => env
            .settings
```

The state and the four commands the front end calls, and their registration:

**Edit `windows/src-tauri/src/ai/mod.rs`**, find this text (it occurs exactly once):

```rust
use crate::settings::AiSettings;
use crate::Shared;
use discovery::{Probe, Server, ServerStatus};
use errors::Who;
```

and replace it with:

```rust
use crate::settings::AiSettings;
use crate::Shared;
use claude_chat::ClaudeChat;
use claude_code::Level;
use discovery::{Probe, Server, ServerStatus};
use errors::Who;
```

**Edit `windows/src-tauri/src/ai/mod.rs`**, find this text (it occurs exactly once):

```rust
    /// Bumped whenever a key changes: a read that started before the change is not kept.
    key_epoch: AtomicU64,
}

impl AiState {
    /// `chat_reset`: a new conversation; a reply still on its way is stopped and dropped.
    pub fn reset(&self) {
        self.conversation.lock().unwrap().reset();
        self.cancel_running();
    }
```

and replace it with:

```rust
    /// Bumped whenever a key changes: a read that started before the change is not kept.
    key_epoch: AtomicU64,
    /// The chat's Claude Code session, its level and what the last check found of it.
    pub claude: Arc<Mutex<ClaudeChat>>,
}

impl AiState {
    /// `chat_reset`: a new conversation; a reply still on its way is stopped and dropped.
    pub fn reset(&self) {
        self.conversation.lock().unwrap().reset();
        // A new chat: a new Claude Code session at Chat only. The old id is retired with it.
        self.claude.lock().unwrap().reset();
        self.cancel_running();
    }
```

**Edit `windows/src-tauri/src/ai/mod.rs`**, find this text (it occurs exactly once):

```rust
        probes: probes(&settings, keys.get("custom").cloned().flatten()),
        settings,
        keys,
        servers: ai.servers.lock().unwrap().clone(),
        cloud_override: catalog::debug_override(),
        models: ai.models.lock().unwrap().clone(),
        timeouts: None,
    }
}

```

and replace it with:

```rust
        probes: probes(&settings, keys.get("custom").cloned().flatten()),
        settings,
        keys,
        servers: ai.servers.lock().unwrap().clone(),
        cloud_override: catalog::debug_override(),
        claude: ai.claude.clone(),
        models: ai.models.lock().unwrap().clone(),
        timeouts: None,
    }
}

```

**Edit `windows/src-tauri/src/ai/mod.rs`**, find this text (it occurs exactly once):

```rust
        probes: Vec::new(),
        settings,
        keys,
        servers: ai.servers.lock().unwrap().clone(),
        cloud_override: catalog::debug_override(),
        models: ai.models.lock().unwrap().clone(),
        timeouts: None,
    }
}

```

and replace it with:

```rust
        probes: Vec::new(),
        settings,
        keys,
        servers: ai.servers.lock().unwrap().clone(),
        cloud_override: catalog::debug_override(),
        claude: ai.claude.clone(),
        models: ai.models.lock().unwrap().clone(),
        timeouts: None,
    }
}

```

**Edit `windows/src-tauri/src/ai/mod.rs`**, find this text (it occurs exactly once):

```rust
) -> Result<(), String> {
    let running = ai.begin_turn().ok_or_else(|| "A reply is still on its way.".to_string())?;
    let inbox = crate::files::inbox_dir();
    let mut files = Vec::new();
```

and replace it with:

```rust
) -> Result<(), String> {
    let running = ai.begin_turn().ok_or_else(|| "A reply is still on its way.".to_string())?;
    // Before a chat's first turn: is Claude Code there, and signed in? (Never on a timer.)
    let wants_claude = {
        let settings = shared.settings.lock().unwrap().ai.clone();
        let by_choice = matches!(settings.choice(feature), router::Choice::Explicit(m) if m.provider == "claudeCode");
        ai.conversation.lock().unwrap().turns.is_empty() && (settings.claude_code_enabled || by_choice)
    };
    if wants_claude {
        let env: std::collections::BTreeMap<String, String> = std::env::vars().collect();
        if let Ok(found) = tokio::task::spawn_blocking(move || claude_cli::status(&env)).await {
            ai.claude.lock().unwrap().status = found;
        }
    }
    let inbox = crate::files::inbox_dir();
    let mut files = Vec::new();
```

**Edit `windows/src-tauri/src/ai/mod.rs`**, find this text (it occurs exactly once):

```rust
}

/// Discovery at launch (spec §2), in the background.
pub fn discover_at_launch(app: AppHandle) {
```

and replace it with:

```rust
}

/// Claude Code: where it is, its version and whether it is signed in. Looked at when Settings opens and before a chat's
/// first turn, never on a timer. Blocking work, off the async threads.
#[tauri::command]
pub async fn claude_status(ai: State<'_, AiState>) -> Result<claude_cli::Status, String> {
    let env: std::collections::BTreeMap<String, String> = std::env::vars().collect();
    let found = tokio::task::spawn_blocking(move || claude_cli::status(&env)).await.map_err(|e| e.to_string())?;
    ai.claude.lock().unwrap().status = found.clone();
    Ok(found)
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LevelDto {
    pub level: &'static str,
    pub folder: Option<String>,
}

/// What Claude may do in this chat: `chat`, or `read` / `agent` with a folder that exists. A new chat starts at `chat`.
#[tauri::command]
pub fn claude_set_level(ai: State<'_, AiState>, level: String, folder: Option<String>) -> Result<LevelDto, String> {
    let chosen = match (level.as_str(), folder) {
        ("chat", _) => Level::ChatOnly,
        ("read", Some(f)) => Level::ReadOnly(claude_cli::check_folder(&f)?),
        ("agent", Some(f)) => Level::Agent(claude_cli::check_folder(&f)?),
        _ => return Err("Pick a folder first.".to_string()),
    };
    let dto = LevelDto { level: chosen.key(), folder: chosen.folder().map(str::to_string) };
    ai.claude.lock().unwrap().level = chosen;
    Ok(dto)
}

/// The system's folder dialog; `None` when cancelled or when this system has none (the chat then asks for the path as text).
#[tauri::command]
pub async fn claude_pick_folder() -> Option<String> {
    tokio::task::spawn_blocking(claude_cli::pick_folder).await.ok().flatten()
}

/// "Sign in": a terminal runs `claude auth login`, which finishes in the browser. NotchMeow never sees the login.
#[tauri::command]
pub async fn claude_sign_in(ai: State<'_, AiState>) -> Result<bool, String> {
    let exe = ai.claude.lock().unwrap().status.executable.clone();
    let Some(exe) = exe else { return Ok(false) };
    Ok(tokio::task::spawn_blocking(move || claude_cli::open_sign_in(&exe)).await.unwrap_or(false))
}

/// Discovery at launch (spec §2), in the background.
pub fn discover_at_launch(app: AppHandle) {
```

**Edit `windows/src-tauri/src/lib.rs`**, find this text (it occurs exactly once):

```rust
            ai::ai_chat,
            ai::ai_cancel,
            chat_reset,
            ingest_file,
```

and replace it with:

```rust
            ai::ai_chat,
            ai::ai_cancel,
            ai::claude_status,
            ai::claude_set_level,
            ai::claude_pick_folder,
            ai::claude_sign_in,
            chat_reset,
            ingest_file,
```

- [ ] **Step 4: Run them**

Run: `$CL test -p notchmeow --target-dir $TD -- ai::claude_chat ai::session`
Expected: PASS, `test result: ok.` and no `FAILED`; `ai::claude_chat` runs 4 tests and the six Claude tests of `ai::session` are among them.

```text
test ai::claude_chat::tests::a_chats_session ... ok
test ai::claude_chat::tests::a_new_chat_starts_at_chat_only ... ok
test ai::claude_chat::tests::a_real_id_is_a_lower_case_version_4_uuid ... ok
test ai::claude_chat::tests::the_recap_of_a_chat ... ok
test ai::session::tests::a_claude_turn_streams_steps_and_text_and_confirms_the_session ... ok
test ai::session::tests::a_claude_that_is_not_installed_falls_back_like_any_cloud ... ok
test ai::session::tests::claude_code_is_ready_only_when_connected_and_signed_in ... ok
test result: ok. 47 passed; 0 failed; 0 ignored; 0 measured; 120 filtered out; finished in 4.53s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

- [ ] **Step 5: Run the whole workspace**

Run: `$CL test --workspace --target-dir $TD`
Expected: PASS, every `test result:` line is `ok` and there is no `FAILED`. Note the library's test count for the report.

```text
test result: ok. 164 passed; 0 failed; 0 ignored; 0 measured; 3 filtered out; finished in 7.63s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

- [ ] **Step 6: Check the Windows-only code compiles (needs the network inside a throwaway container)**

The `#[cfg(windows)]` lines (`taskkill`, the `.exe` locations, PowerShell, the Windows Terminal) are not compiled by the Linux runs. Compile them for the Windows target in the same image, in a throwaway container with its own volume (the toolchain and `mingw-w64` are installed inside the container, never on the host; this one step needs network access from the container):

```bash
docker run --rm --pull=never \
  -v "$PWD":/repo -v notchmeow-e3claude-win:/repo/windows/target \
  -v notchmeow-linux-cargo:/usr/local/cargo/registry \
  -w /repo/windows notchmeow-linux-dev bash -c '
    set -e
    rustup target add x86_64-pc-windows-gnu
    apt-get update -qq && apt-get install -y -qq --no-install-recommends mingw-w64
    cargo build --release -q -p notchmeow-hook
    touch target/release/notchmeow-hook.exe      # tauri-build only needs the bundled relay to exist for a check
    cargo check --target x86_64-pc-windows-gnu --workspace --all-targets'
```

Expected: `Finished` with no `error` and no `warning:` from `notchmeow`. If the container has no network, say so in the report: this step is then owed to CI (`windows-tests.yml` runs `cargo test --workspace` on Windows for pull requests), and the owner decides.

- [ ] **Step 7: Commit**

```bash
git add windows/src-tauri/src/ai/claude_chat.rs windows/src-tauri/src/ai/session.rs windows/src-tauri/src/ai/mod.rs windows/src-tauri/src/lib.rs
git commit -q -m "feat(claude-code): a chat's session and its turn on Windows/Linux, with the commands the front end calls" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 18: Windows/Linux: the front end (routing, chips, steps, card, Connect Claude)

**Agent:** `nm-implementer`. TypeScript without a framework, in the app's own style; the logic that can be pure is in one file with a plain-Node check, the rest is glue checked by the type checker, the build and the owner.

**Files:**
- Create: `windows/src/core/steps.ts`, `windows/src/core/claude.ts`, `windows/scripts/check-claude-ui.mjs`
- Modify: `windows/package.json` (`check:claude`), `windows/src/core/bridge.ts`, `state.ts`, `windows/src/island/hooks.ts`, `island.ts`, `windows/src/views/chat.ts`, `windows/src/settings/main.ts`, `windows/src/style.css`

**Interfaces:**
- Consumes: Task 17's commands (`claude_status`, `claude_set_level`, `claude_pick_folder`, `claude_sign_in`) and events (`claudeSession`, `step`, `engine`, `error.resetsAt`); Task 14's settings fields (`claudeCodeEnabled`, `claudeCodeModel`, `preferredCloud: "claudeCode"`); the fixtures `hook-routing.json`, `labels.json`, `copy.json` (Task 2).
- Produces:
  - `core/steps.ts` (no imports): `lastPathComponent`, `stepLabel(tool, input)` and `approvalTarget(tool, input)`, moved out of `island/hooks.ts` unchanged so the chat's rows and the island's read the same way.
  - `core/claude.ts` (imports only `steps.ts`): types `ClaudeLevel` (`"chat" | "read" | "agent"`), `ClaudeChatLevel`, `Payer`, `ClaudeStatus`, `ClaudeStep`; `INSTALL_GUIDE`, `GIT_FOR_WINDOWS`; `routeHook(payload, live: ReadonlySet<string>): "chat" | "other"`; `modelChip(authMethod, paidBy)`, `levelChip(level, folder)`, `folderName(path)`, `signInWords(authMethod)`; `endUnfinished(steps)`; `stepRow(step)`; `planLimitNote(message, resetsAt, locale?, timeZone?)`; `ApprovalQueue` (`front`, `length`, `push`, `popFront`, `remove(requestId)`, `removeAll(sessionId?)`).
  - `Bridge.claudeStatus()`, `claudeSetLevel(level, folder)`, `claudePickFolder()`, `claudeSignIn()`; `AiEvent` gains the three events and `resetsAt`; `State.claudeSessions`, `claudeLevel`, `claudeStatus`, `claudePaidBy`, `chatApprovals`, `resetClaude()`.
  - `island/hooks.ts`: `releaseChatApprovals(sessionId?)` (hands every waiting request back; Claude Code refuses those steps), `decideChatApproval("allow" | "deny")`; `handleHook` asks `routeHook` before it looks at a session, so a chat's request becomes a card in that chat, never a pill, and never touches the one pending approval of the user's own sessions. A request left unanswered is dropped after 110 s (the hook waits 120).
  - In the chat: a level chip beside the model chip (only when Claude Code is the engine; disabled while a reply streams), a level picker (Chat only, Read-only, Agent; the last two ask for a folder through the system dialog, else as typed text; Agent is disabled, with the reason, when the hooks are not installed), step rows above a reply, the approval card, the model chip reading what Claude Code reported, the plan-limit note with its time, the rate-limit cat, the note buttons (Sign in, How to install, How to update, Get Git for Windows, Try again), a Claude plan section in the model picker, and a "Connect Claude" button in the empty state.
  - In Settings → AI: a "Connect Claude" box above "Which model answers" with the two paths (Use my Claude plan, Paste an API key), the Claude plan models in the model lists, and the Preferred cloud list showing what is ready.
- The same rule as the Mac (`CLAUDE.md`): nothing else in an existing view changes, and the new elements reuse the app's classes (`chip`, `picker-item`, `card`, `btn primary`, `btn secondary`, `note-btn`).

- [ ] **Step 1: Write the failing check**

`scripts/check-claude-ui.mjs` runs plain Node (22.6 or newer) against the shared fixtures: every case of `hook-routing.json` through `routeHook`, a source pin that `handleHook` asks the router before it looks at a session, the chips and the folder names from `labels.json`, the plan-limit note in two locales from `copy.json`, the step rows and the approval card's words, `endUnfinished`, and the queue. They pin Review Focus 4 (a chat's payload never reaches a pill, an unknown or missing id, a Codex payload, an id in another case), 5 (`modelChip`), 6 (`folderName`) and 2 (`endUnfinished`); Review Focus 9 is the level picker's Agent row, disabled with its reason until the hooks are installed, which the build and the owner check.

**Create `windows/scripts/check-claude-ui.mjs`** with exactly this content:

```javascript
// Plain-Node checks for the Claude Code parts of the chat that hold logic: no DOM, no framework. They run against the
// shared fixtures in tests/fixtures/ai/claude-code/, so the Windows/Linux app and the Mac app cannot drift apart.
// Needs Node 22.6 or newer, which can read the TypeScript source directly:
//
//   cd windows && npm run check:claude
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  ApprovalQueue, endUnfinished, folderName, levelChip, modelChip, planLimitNote, routeHook, signInWords, stepRow,
} from "../src/core/claude.ts";
import { approvalTarget, stepLabel } from "../src/core/steps.ts";

const fixture = (name) => JSON.parse(readFileSync(new URL(`../../tests/fixtures/ai/claude-code/${name}`, import.meta.url), "utf8"));

// Which hook payloads belong to a chat.
const routing = fixture("hook-routing.json");
for (const c of routing.cases) {
  assert.equal(routeHook(c.payload, new Set(c.live ?? routing.live)), c.expect, c.name);
}
console.log(`✓ ${routing.cases.length} hook payloads go to the right place`);
// A chat's payload never reaches a pill: the island asks the router before it looks at a session (a source pin, because
// no check here can run the island).
const hooks = readFileSync(new URL("../src/island/hooks.ts", import.meta.url), "utf8");
const handler = hooks.slice(hooks.indexOf("function handleHook("));
assert.ok(handler.includes("routeHook(") && handler.indexOf("routeHook(") < handler.indexOf("hook_event_name ?? \"\""), "handleHook asks the router first");
console.log("✓ the island asks the router before it makes or touches a pill");

// The two chips.
const labels = fixture("labels.json");
for (const c of labels.modelChip) assert.equal(modelChip(c.authMethod, c.paidBy), c.expect, c.name);
for (const c of labels.levelChip) assert.equal(levelChip(c.level, c.folder), c.expect, `${c.level} ${c.folder}`);
console.log("✓ the model chip never claims 'your plan' without being told, and the level chip names the folder");
assert.equal(folderName("C:\\Users\\José\\Mis Proyectos\\"), "Mis Proyectos");
assert.equal(signInWords("claude.ai"), "your Claude plan");
assert.equal(signInWords("something_new"), "its own sign-in");

// What the chat says for a plan limit, in the viewer's time zone and locale.
for (const c of fixture("copy.json").cases.filter((x) => x.resetsAt != null)) {
  const note = planLimitNote("Your Claude plan's limit was reached.", c.resetsAt, c.locale.replace("_", "-"), c.timeZone);
  assert.equal(note, c.text, c.locale);
}
assert.equal(planLimitNote("Your Claude plan's limit was reached.", null), "Your Claude plan's limit was reached.");
console.log("✓ a plan limit says when it resets, as the Mac does");

// The step rows read as the island's own do; a failed or stopped step says so.
assert.equal(stepLabel("Read", { file_path: "C:\\work\\README.md" }), "Lit · README.md");
assert.equal(stepLabel("Bash", { command: "npm test" }), "Exécute · npm test");
assert.equal(stepLabel("Frobnicate", {}), "Frobnicate");
assert.equal(stepRow({ id: "1", tool: "Read", input: { file_path: "/work/a.md" }, state: "done" }), "Lit · a.md");
assert.equal(stepRow({ id: "1", tool: "Read", input: { file_path: "/work/a.md" }, state: "failed" }), "Lit · a.md ⚠");
assert.equal(stepRow({ id: "1", tool: "Bash", input: { command: "sleep 60" }, state: "stopped" }), "Exécute · sleep 60 · stopped");
// Stop ends a step that never finished as stopped, and leaves the others alone.
const mixed = [{ id: "a", tool: "Read", input: {}, state: "done" }, { id: "b", tool: "Bash", input: {}, state: "running" }, { id: "c", tool: "Edit", input: {}, state: "failed" }];
assert.deepEqual(endUnfinished(mixed).map((s) => s.state), ["done", "stopped", "failed"]);
assert.equal(mixed[1].state, "running", "the input is not changed");
// What the card says is what Allow authorises.
assert.equal(approvalTarget("Write", { file_path: "C:\\work\\.env", content: "SECRET" }), "Write · C:\\work\\.env");
assert.equal(approvalTarget("Bash", { command: "  npm test " }), "Bash · npm test");
assert.equal(approvalTarget("Frob", { x: 1 }), "Frob");
console.log("✓ step rows and the approval card use the island's own words");

// Requests wait in order.
const q = new ApprovalQueue();
const req = (requestId, sessionId, tool) => ({ requestId, sessionId, tool, command: tool });
q.push(req("a", "s1", "Bash")); q.push(req("b", "s1", "Edit")); q.push(req("c", "s2", "Write"));
assert.equal(q.front?.tool, "Bash");
assert.equal(q.popFront()?.requestId, "a");
assert.equal(q.front?.tool, "Edit");
assert.equal(q.remove("c")?.requestId, "c");
assert.equal(q.remove("nope"), null);
q.push(req("c", "s2", "Write"));
assert.deepEqual(q.removeAll("s1").map((x) => x.requestId), ["b"]);
assert.equal(q.front?.sessionId, "s2");
assert.deepEqual(q.removeAll().map((x) => x.requestId), ["c"]);
assert.equal(q.length, 0);
console.log("✓ approvals wait in the order they came, and a session's go together");

console.log("\nAll Claude Code UI checks passed");
```

**Edit `windows/package.json`**, find this text (it occurs exactly once):

```json
    "icons": "node scripts/gen-icons.mjs",
    "check:ai": "node --experimental-strip-types scripts/check-ai-ui.mjs",
    "check:cat": "node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/*.test.mjs",
    "tauri": "tauri",
```

and replace it with:

```json
    "icons": "node scripts/gen-icons.mjs",
    "check:ai": "node --experimental-strip-types scripts/check-ai-ui.mjs",
    "check:claude": "node --experimental-strip-types scripts/check-claude-ui.mjs",
    "check:cat": "node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/*.test.mjs",
    "tauri": "tauri",
```

- [ ] **Step 2: Run it to see it fail**

Run: `(cd windows && npm run check:claude)`
Expected: FAIL, `ERR_MODULE_NOT_FOUND`: `src/core/claude.ts` does not exist.

```text
    throw new ERR_MODULE_NOT_FOUND(
Error [ERR_MODULE_NOT_FOUND]: Cannot find module '<repo>/windows/src/core/claude.ts' imported from <repo>/windows/scripts/check-claude-ui.mjs
```

- [ ] **Step 3: Write the pure files**

**Create `windows/src/core/steps.ts`** with exactly this content:

```typescript
// The words of a step row and of the approval card, moved out of island/hooks.ts unchanged so the chat's step rows and the
// island's own read the same way. No imports, so the plain-Node check in scripts/check-claude-ui.mjs can load this file
// as it is.

export function lastPathComponent(p: string): string {
  const cleaned = p.replace(/[\\/]+$/, "");
  const idx = Math.max(cleaned.lastIndexOf("\\"), cleaned.lastIndexOf("/"));
  return idx >= 0 ? cleaned.slice(idx + 1) : cleaned;
}

/** frenchStep() — same labels as the macOS app. */
const TOOL_LABELS: Record<string, string> = {
  Bash: "Exécute",
  Read: "Lit",
  Write: "Écrit",
  Edit: "Modifie",
  Glob: "Cherche",
  Grep: "Recherche",
  WebSearch: "Recherche web",
  WebFetch: "Récupère",
  TodoWrite: "Tâches",
  Task: "Agent",
  LS: "Liste",
  MultiEdit: "Modifie",
  NotebookEdit: "Notebook",
  PowerShell: "Exécute",
};

export function stepLabel(tool: string, input: Record<string, unknown>): string {
  const label = TOOL_LABELS[tool] ?? tool;
  const str = (k: string) => (typeof input[k] === "string" ? (input[k] as string) : null);
  const cmd = str("command");
  if (cmd) return `${label} · ${cmd.slice(0, 40)}`;
  const path = str("path");
  if (path) return `${label} · ${lastPathComponent(path)}`;
  const file = str("file_path");
  if (file) return `${label} · ${lastPathComponent(file)}`;
  const query = str("query");
  if (query) return `${label} · ${query.slice(0, 40)}`;
  return label;
}

/**
 * What the Allow button actually authorises. Approving "Write" tells you nothing
 * — approving `Write · C:\…\.env` tells you everything, and the difference is
 * the whole point of approving from the island rather than blind.
 *
 * Ordered by how specific the field is, so an unfamiliar tool still shows
 * whatever identifying string it carries instead of falling back to its name.
 */
const APPROVAL_FIELDS = [
  "command", // Bash, PowerShell
  "file_path", // Write, Edit, MultiEdit, NotebookEdit
  "path", // Read, LS
  "url", // WebFetch
  "query", // WebSearch
  "pattern", // Glob, Grep
  "prompt", // Task
] as const;

export function approvalTarget(tool: string, input: Record<string, unknown>): string {
  for (const field of APPROVAL_FIELDS) {
    const value = input[field];
    if (typeof value === "string" && value.trim()) {
      return `${tool} · ${value.trim()}`;
    }
  }
  return tool;
}
```

**Create `windows/src/core/claude.ts`** with exactly this content:

```typescript
// Claude Code in the chat, the parts that hold logic: which hook payloads belong to a chat, the words on the chips, the
// step rows and the note for a plan limit, and the queue of approvals waiting for a click. No DOM, and no imports besides
// types and `steps.ts`, so the plain-Node check in scripts/check-claude-ui.mjs loads this file as it is. The rules are the
// shared fixtures in tests/fixtures/ai/claude-code/ (hook-routing.json, labels.json, copy.json).

import { stepLabel } from "./steps.ts";

export type ClaudeLevel = "chat" | "read" | "agent";

/** What Claude may do in this chat (`claude_set_level` in Rust). Every new chat starts at Chat only. */
export interface ClaudeChatLevel {
  level: ClaudeLevel;
  folder: string | null;
}

/** Who pays for a run, as Claude Code's own first event says. */
export type Payer = "plan" | "api_key" | "unknown";

/** What the last check found of Claude Code (`claude_status` in Rust). `signedIn` is the only state that counts as ready. */
export interface ClaudeStatus {
  state: "notInstalled" | "tooOld" | "signedOut" | "signedIn" | "unknown";
  version: string | null;
  authMethod: string | null;
  shimOnly: boolean;
  needsGit: boolean;
}

/** One step Claude Code takes on its own, shown as a row in the chat. */
export interface ClaudeStep {
  id: string;
  tool: string;
  input: Record<string, string>;
  state: "running" | "done" | "failed" | "stopped";
}

/** Where Anthropic's installer is: NotchMeow links to it and installs nothing. */
export const INSTALL_GUIDE = "https://docs.claude.com/en/docs/claude-code/setup";
export const GIT_FOR_WINDOWS = "https://git-scm.com/downloads/win";

/**
 * Which hook payloads belong to a chat. `live` is the set of session ids NotchMeow chose with --session-id for chats that
 * are still open. Only an exact match of a string `session_id` counts, and a payload from another agent (`nm_agent`) never
 * does. A chat's payload goes to that chat and never creates or touches a pill; everything else is handled as before.
 */
export function routeHook(payload: { session_id?: unknown; nm_agent?: unknown }, live: ReadonlySet<string>): "chat" | "other" {
  if (typeof payload.nm_agent === "string" && payload.nm_agent !== "") return "other";
  const id = payload.session_id;
  return typeof id === "string" && id !== "" && live.has(id) ? "chat" : "other";
}

/**
 * Who pays, in words. What the last run reported wins; before any run, the sign-in method. A cloud account (Bedrock,
 * Vertex) is neither, and an unknown answer never claims "your plan".
 */
export function modelChip(authMethod: string | null, paidBy: Payer | null): string {
  if (authMethod === "third_party") return "Claude";
  if (paidBy === "plan") return "Claude · your plan";
  if (paidBy === "api_key") return "Claude · API key";
  if (authMethod === "claude.ai" || authMethod === "oauth_token") return "Claude · your plan";
  if (authMethod === "api_key" || authMethod === "api_key_helper") return "Claude · API key";
  return "Claude";
}

/** The last part of a path, whichever separator it uses; "/" and "C:" keep their own names. */
export function folderName(folder: string): string {
  const trimmed = folder.replace(/[\\/]+$/, "");
  if (trimmed === "") return folder.slice(0, 1);
  return trimmed.split(/[\\/]/).pop() ?? trimmed;
}

/** "Chat only", "Read-only · notchmeow", "Agent · Mis Proyectos". */
export function levelChip(level: ClaudeLevel, folder: string | null): string {
  const words = { chat: "Chat only", read: "Read-only", agent: "Agent" }[level];
  if (level === "chat" || !folder) return words;
  return `${words} · ${folderName(folder)}`;
}

/** How Claude Code is signed in, in words: "your Claude plan", "an API key". */
export function signInWords(authMethod: string | null): string {
  switch (authMethod) {
    case "claude.ai": return "your Claude plan";
    case "oauth_token": return "an OAuth token";
    case "api_key": return "an API key";
    case "api_key_helper": return "an API key helper";
    case "third_party": return "a cloud account";
    default: return "its own sign-in";
  }
}

/** A step that never finished (Stop, a crash) ends as stopped: no row stays "running". The others are left alone. */
export function endUnfinished(steps: ClaudeStep[]): ClaudeStep[] {
  return steps.map((s) => (s.state === "running" ? { ...s, state: "stopped" as const } : s));
}

/** "Lit · README.md", with a mark when the step failed or was stopped. */
export function stepRow(step: ClaudeStep): string {
  const line = stepLabel(step.tool, step.input);
  if (step.state === "failed") return `${line} ⚠`;
  if (step.state === "stopped") return `${line} · stopped`;
  return line;
}

/**
 * "Your Claude plan's limit resets at 3:45 pm." in the viewer's time zone and locale; Rust sends only the base words and
 * `resetsAt` (Unix seconds). A recent ICU puts a narrow no-break space before PM: a plain one is used, and PM is lower-cased.
 */
export function planLimitNote(message: string, resetsAt: number | null | undefined, locale?: string, timeZone?: string): string {
  if (resetsAt == null) return message;
  const time = new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit", timeZone })
    .format(new Date(resetsAt * 1000))
    .replace(/[\u202f\u00a0]/g, " ")
    .toLowerCase();
  return `Your Claude plan's limit resets at ${time}.`;
}

/** A step Claude Code is waiting to take: the card in the chat shows the first. Mirrors `ApprovalInfo` in state.ts. */
export interface WaitingApproval {
  requestId: string;
  sessionId: string;
  tool: string;
  command: string;
}

/** Requests wait here in the order they arrived (parallel tool calls ask together); the card shows the first. */
export class ApprovalQueue {
  private items: WaitingApproval[] = [];

  get front(): WaitingApproval | null {
    return this.items[0] ?? null;
  }

  get length(): number {
    return this.items.length;
  }

  push(item: WaitingApproval): void {
    this.items.push(item);
  }

  /** The first request, answered or given up on. */
  popFront(): WaitingApproval | null {
    return this.items.shift() ?? null;
  }

  /** One request by id (its connection closed, or it timed out). */
  remove(requestId: string): WaitingApproval | null {
    const i = this.items.findIndex((x) => x.requestId === requestId);
    return i < 0 ? null : this.items.splice(i, 1)[0];
  }

  /** Every request of one session, or all of them (no argument): Stop, a new conversation, a level change. */
  removeAll(sessionId?: string): WaitingApproval[] {
    const gone = this.items.filter((x) => sessionId === undefined || x.sessionId === sessionId);
    this.items = this.items.filter((x) => !gone.includes(x));
    return gone;
  }
}
```

- [ ] **Step 4: Run it again: the routing and the words pass, the island does not ask the router yet**

Run: `(cd windows && npm run check:claude)`
Expected: FAIL, the hook payloads pass and the source pin fails: `handleHook asks the router first`.

```text
✓ 13 hook payloads go to the right place
AssertionError [ERR_ASSERTION]: handleHook asks the router first
```

- [ ] **Step 5: Wire the front end**

The bridge and the state first:

**Edit `windows/src/core/bridge.ts`**, find this text (it occurs exactly once):

```typescript
import { listen } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import type { AiAction, Settings } from "./state";

```

and replace it with:

```typescript
import { listen } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import type { ClaudeChatLevel, ClaudeLevel, ClaudeStatus, ClaudeStep, Payer } from "./claude";
import type { AiAction, Settings } from "./state";

```

**Edit `windows/src/core/bridge.ts`**, find this text (it occurs exactly once):

```typescript
  /** Loads the selected local model before the first message. */
  aiPrewarm: (feature: Feature) => call<void>("ai_prewarm", { feature }),
  /** Starts a new conversation (a file was dropped, or the chat was cleared). */
  chatReset: () => call<void>("chat_reset"),
```

and replace it with:

```typescript
  /** Loads the selected local model before the first message. */
  aiPrewarm: (feature: Feature) => call<void>("ai_prewarm", { feature }),
  // ── Claude Code (the user's own installed program) ───────────────────────
  /** Where it is, its version and whether it is signed in. Looked at when Settings opens and before a chat's first turn. */
  claudeStatus: () => call<ClaudeStatus>("claude_status"),
  /** What Claude may do in this chat. Read-only and Agent need a folder that exists. */
  claudeSetLevel: (level: ClaudeLevel, folder: string | null) => callOrThrow<ClaudeChatLevel>("claude_set_level", { level, folder }),
  /** The system's folder dialog; null when cancelled or when this system has none. */
  claudePickFolder: () => call<string>("claude_pick_folder"),
  /** Opens a terminal that runs `claude auth login`; the sign-in finishes in the browser. */
  claudeSignIn: () => call<boolean>("claude_sign_in"),
  /** Starts a new conversation (a file was dropped, or the chat was cleared). */
  chatReset: () => call<void>("chat_reset"),
```

**Edit `windows/src/core/bridge.ts`**, find this text (it occurs exactly once):

```typescript
  | { type: "notice"; text: string }
  | { type: "done"; text: string; interrupted: boolean; cancelled: boolean }
  | { type: "error"; kind: ErrorKind; message: string; action: AiAction | null; retryAfter: number | null }
  | { type: "problem"; kind: ProblemKind; message: string; action: AiAction | null }
  | { type: "emptyState" };

export interface ModelInfo {
```

and replace it with:

```typescript
  | { type: "notice"; text: string }
  | { type: "done"; text: string; interrupted: boolean; cancelled: boolean }
  | { type: "error"; kind: ErrorKind; message: string; action: AiAction | null; retryAfter: number | null; resetsAt?: number }
  | { type: "problem"; kind: ProblemKind; message: string; action: AiAction | null }
  | { type: "emptyState" }
  /** Claude Code: the session this run belongs to, so its hook events are the chat's. `retired` is the id this turn gave up. */
  | { type: "claudeSession"; sessionId: string; retired: string | null }
  | ({ type: "step" } & ClaudeStep)
  | { type: "engine"; sessionId: string; model: string; paidBy: Payer; version: string | null };

export interface ModelInfo {
```

**Edit `windows/src/core/state.ts`**, find this text (it occurs exactly once):

```typescript

import type { Feature } from "./bridge";
import type { BotEmoteName, BotStateName, IslandMode, IslandViewName } from "./layout";
import type { EyeShape } from "../cat/engine";
```

and replace it with:

```typescript

import type { Feature } from "./bridge";
import type { ClaudeChatLevel, ClaudeStatus, ClaudeStep, Payer } from "./claude";
import { ApprovalQueue } from "./claude.ts";
import type { BotEmoteName, BotStateName, IslandMode, IslandViewName } from "./layout";
import type { EyeShape } from "../cat/engine";
```

**Edit `windows/src/core/state.ts`**, find this text (it occurs exactly once):

```typescript
  | { kind: "openGuide" }
  | { kind: "chooseModel" }
  | { kind: "cancel" };

export interface ChatSource {
```

and replace it with:

```typescript
  | { kind: "openGuide" }
  | { kind: "chooseModel" }
  | { kind: "cancel" }
  | { kind: "signInClaude" }
  | { kind: "installClaude" }
  | { kind: "updateClaude" }
  | { kind: "installGit" }
  | { kind: "tryAgain" };

export interface ChatSource {
```

**Edit `windows/src/core/state.ts`**, find this text (it occurs exactly once):

```typescript
  /** Under a reply: the setting that answered, so Continue and Retry use it again. */
  feature?: Feature;
}

```

and replace it with:

```typescript
  /** Under a reply: the setting that answered, so Continue and Retry use it again. */
  feature?: Feature;
  /** Steps Claude Code took for this reply (reading a file, running a command), shown as rows above it. */
  steps?: ClaudeStep[];
}

```

**Edit `windows/src/core/state.ts`**, find this text (it occurs exactly once):

```typescript
  files: ModelChoice;
  /** Which cloud Auto tries first. */
  preferredCloud: "anthropic" | "openai";
  /** Remembered model per cloud provider. */
  cloudModels: Record<string, string>;
```

and replace it with:

```typescript
  files: ModelChoice;
  /** Which cloud Auto tries first. */
  preferredCloud: "claudeCode" | "anthropic" | "openai";
  /** Remembered model per cloud provider. */
  cloudModels: Record<string, string>;
```

**Edit `windows/src/core/state.ts`**, find this text (it occurs exactly once):

```typescript
  /** The server added with "Add server…". */
  customServer: string | null;
}

```

and replace it with:

```typescript
  /** The server added with "Add server…". */
  customServer: string | null;
  /** The user connected "Use my Claude plan": Auto may use it while the last check finds Claude Code signed in. */
  claudeCodeEnabled: boolean;
  /** Claude Code's model alias for the chat. */
  claudeCodeModel: "sonnet" | "opus" | "haiku";
}

```

**Edit `windows/src/core/state.ts`**, find this text (it occurs exactly once):

```typescript
  lastUsedLocal: null,
  customServer: null,
};

```

and replace it with:

```typescript
  lastUsedLocal: null,
  customServer: null,
  claudeCodeEnabled: false,
  claudeCodeModel: "sonnet",
};

```

**Edit `windows/src/core/state.ts`**, find this text (it occurs exactly once):

```typescript
  pendingApproval: ApprovalInfo | null = null;

  integrations: Record<string, IntegrationInfo> = {};

```

and replace it with:

```typescript
  pendingApproval: ApprovalInfo | null = null;

  /** Claude Code: the session ids whose hook events belong to this chat (island/hooks.ts routes by them). */
  claudeSessions = new Set<string>();
  /** What Claude may do in this chat. Every new chat starts at Chat only. */
  claudeLevel: ClaudeChatLevel = { level: "chat", folder: null };
  /** What the last check found of Claude Code; null until one ran. */
  claudeStatus: ClaudeStatus | null = null;
  /** Who paid for the last Claude Code run, as it said itself. */
  claudePaidBy: Payer | null = null;
  /** The steps Claude Code is waiting to take in this chat (Agent level), in the order they asked. */
  chatApprovals = new ApprovalQueue();

  integrations: Record<string, IntegrationInfo> = {};

```

**Edit `windows/src/core/state.ts`**, find this text (it occurs exactly once):

```typescript
  }

  get focusTask(): AgentTask | null {
    return this.tasks.find((t) => t.id === this.focusId) ?? this.tasks[0] ?? null;
```

and replace it with:

```typescript
  }

  /** A new conversation: a new Claude Code session at Chat only. (Hooks.ts hands back any waiting approval first.) */
  resetClaude() {
    this.claudeSessions.clear();
    this.claudeLevel = { level: "chat", folder: null };
  }

  get focusTask(): AgentTask | null {
    return this.tasks.find((t) => t.id === this.focusId) ?? this.tasks[0] ?? null;
```

`island/hooks.ts`: the step words move out to `steps.ts`, and a chat's requests get their own handler ahead of the pill logic.

**Edit `windows/src/island/hooks.ts`**, find this text (it occurs exactly once):

```typescript

import { Bridge, onEvent } from "../core/bridge";
import { Sound } from "../core/sound";
import { State } from "../core/state";
import type { Island } from "./island";

```

and replace it with:

```typescript

import { Bridge, onEvent } from "../core/bridge";
import { routeHook } from "../core/claude.ts";
import { Sound } from "../core/sound";
import { State } from "../core/state";
import { approvalTarget, lastPathComponent, stepLabel } from "../core/steps.ts";
import type { Island } from "./island";

```

**Edit `windows/src/island/hooks.ts`**, find this text (it occurs exactly once):

```typescript
let pendingTimeout: number | null = null;

interface HookPayload {
  hook_event_name?: string;
```

and replace it with:

```typescript
let pendingTimeout: number | null = null;

/** The same for each request waiting on a chat's own card: after this the terminal has taken over. */
const chatTimeouts = new Map<string, number>();

interface HookPayload {
  hook_event_name?: string;
```

**Edit `windows/src/island/hooks.ts`**, find this text (it occurs exactly once):

```typescript
}

function lastPathComponent(p: string): string {
  const cleaned = p.replace(/[\\/]+$/, "");
  const idx = Math.max(cleaned.lastIndexOf("\\"), cleaned.lastIndexOf("/"));
  return idx >= 0 ? cleaned.slice(idx + 1) : cleaned;
}

/** frenchStep() — same labels as the macOS app. */
const TOOL_LABELS: Record<string, string> = {
  Bash: "Exécute",
  Read: "Lit",
  Write: "Écrit",
  Edit: "Modifie",
  Glob: "Cherche",
  Grep: "Recherche",
  WebSearch: "Recherche web",
  WebFetch: "Récupère",
  TodoWrite: "Tâches",
  Task: "Agent",
  LS: "Liste",
  MultiEdit: "Modifie",
  NotebookEdit: "Notebook",
  PowerShell: "Exécute",
};

function stepLabel(tool: string, input: Record<string, unknown>): string {
  const label = TOOL_LABELS[tool] ?? tool;
  const str = (k: string) => (typeof input[k] === "string" ? (input[k] as string) : null);
  const cmd = str("command");
  if (cmd) return `${label} · ${cmd.slice(0, 40)}`;
  const path = str("path");
  if (path) return `${label} · ${lastPathComponent(path)}`;
  const file = str("file_path");
  if (file) return `${label} · ${lastPathComponent(file)}`;
  const query = str("query");
  if (query) return `${label} · ${query.slice(0, 40)}`;
  return label;
}

/**
 * What the Allow button actually authorises. Approving "Write" tells you nothing
 * — approving `Write · C:\…\.env` tells you everything, and the difference is
 * the whole point of approving from the island rather than blind.
 *
 * Ordered by how specific the field is, so an unfamiliar tool still shows
 * whatever identifying string it carries instead of falling back to its name.
 */
const APPROVAL_FIELDS = [
  "command", // Bash, PowerShell
  "file_path", // Write, Edit, MultiEdit, NotebookEdit
  "path", // Read, LS
  "url", // WebFetch
  "query", // WebSearch
  "pattern", // Glob, Grep
  "prompt", // Task
] as const;

function approvalTarget(tool: string, input: Record<string, unknown>): string {
  for (const field of APPROVAL_FIELDS) {
    const value = input[field];
    if (typeof value === "string" && value.trim()) {
      return `${tool} · ${value.trim()}`;
    }
  }
  return tool;
}

function upsert(projectName: string, cwd: string) {
  const t = State.tasks.find((x) => x.id === CLAUDE_ID);
```

and replace it with:

```typescript
}

function upsert(projectName: string, cwd: string) {
  const t = State.tasks.find((x) => x.id === CLAUDE_ID);
```

**Edit `windows/src/island/hooks.ts`**, find this text (it occurs exactly once):

```typescript
}

function handleHook(island: Island, payload: HookPayload) {
  if (State.paused) {
```

and replace it with:

```typescript
}

/** Hands every waiting request of a chat back to Claude Code (it refuses those steps) and takes the card away. */
export function releaseChatApprovals(sessionId?: string) {
  for (const waiting of State.chatApprovals.removeAll(sessionId)) {
    window.clearTimeout(chatTimeouts.get(waiting.requestId));
    chatTimeouts.delete(waiting.requestId);
    if (waiting.requestId) void Bridge.approvalDecline(waiting.requestId);
  }
  if (State.chatApprovals.length === 0 && !State.pendingApproval) State.isPinned = false;
  State.notify();
}

/** Allow or Deny on the chat's card: the first waiting request is answered, and the next one shows. */
export function decideChatApproval(decision: "allow" | "deny") {
  const waiting = State.chatApprovals.popFront();
  if (!waiting) return;
  window.clearTimeout(chatTimeouts.get(waiting.requestId));
  chatTimeouts.delete(waiting.requestId);
  if (waiting.requestId) void Bridge.approvalDecision(waiting.requestId, decision);
  if (State.chatApprovals.length === 0 && !State.pendingApproval) State.isPinned = false;
  State.notify();
}

/**
 * A request from a chat's own Claude Code run. Its card is in that chat, never a pill, and it never touches the one
 * pending approval of the user's own sessions. Nothing runs without a click: when the app does not answer, Claude Code
 * refuses the step. Everything else a chat's run sends is not a session: the chat's own stream already shows its steps.
 */
function handleChatHook(island: Island, payload: HookPayload) {
  if (payload.hook_event_name !== "PermissionRequest") return;
  const requestId = payload.request_id ?? "";
  const tool = payload.tool_name ?? "Tool";
  // A chat's run cannot be asked a question on the island: hand it back, Claude Code carries on without.
  if (tool === "AskUserQuestion") {
    if (requestId) void Bridge.approvalDecline(requestId);
    return;
  }
  const first = State.chatApprovals.length === 0;
  State.chatApprovals.push({
    requestId,
    sessionId: payload.session_id ?? "",
    tool,
    command: approvalTarget(tool, payload.tool_input ?? {}),
  });
  // The relay's short ack window closes in 800 ms; everything above is synchronous.
  if (requestId) void Bridge.approvalAck(requestId);
  if (requestId) {
    chatTimeouts.set(requestId, window.setTimeout(() => {
      State.chatApprovals.remove(requestId);
      chatTimeouts.delete(requestId);
      if (State.chatApprovals.length === 0 && !State.pendingApproval) State.isPinned = false;
      State.notify();
    }, 110_000));
  }
  if (first) {
    Sound.play("approval");
    State.isPinned = true;
    // The card is in the chat: bring the chat up if the island shows something else.
    if (State.mode === "expanded") island.setView("prompt");
    else island.alert("prompt");
  }
  State.notify();
}

function handleHook(island: Island, payload: HookPayload) {
  if (State.paused) {
```

**Edit `windows/src/island/hooks.ts`**, find this text (it occurs exactly once):

```typescript
  }

  const name = payload.hook_event_name ?? "";
  const cwd = payload.cwd ?? "";
```

and replace it with:

```typescript
  }

  // A chat's own Claude Code run asks here too (the same hooks): its card is in that chat, never a pill.
  if (routeHook(payload, State.claudeSessions) === "chat") {
    handleChatHook(island, payload);
    return;
  }

  const name = payload.hook_event_name ?? "";
  const cwd = payload.cwd ?? "";
```

A new conversation hands the waiting approvals back:

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```typescript
import { h } from "../views/dom";
import { IslandStateMachine } from "./fsm";

const BOT_OVERHANG = 40;
```

and replace it with:

```typescript
import { h } from "../views/dom";
import { IslandStateMachine } from "./fsm";
import { releaseChatApprovals } from "./hooks";

const BOT_OVERHANG = 40;
```

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```typescript
    State.chatHistory = [];
    State.chatEpoch++;
    void Bridge.chatReset();

```

and replace it with:

```typescript
    State.chatHistory = [];
    State.chatEpoch++;
    // A new chat: a new Claude Code session at Chat only. Whatever it was waiting to do is refused.
    releaseChatApprovals();
    State.resetClaude();
    void Bridge.chatReset();

```

The chat: the chips, the picker, the steps, the card and the events.

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
import { ICONS } from "./icons";
import { Bridge, CLOUD_PROVIDERS, onEvent, type AiEvent, type AiServer, type Feature, type Resolution } from "../core/bridge";
import { featureFor, forgetDrop, stillBusy } from "../core/feature";
import { Sound } from "../core/sound";
import { State, type AiAction, type ChatMessage, type ModelChoice } from "../core/state";
import type { ViewActions, ViewHost } from "./views";

```

and replace it with:

```typescript
import { ICONS } from "./icons";
import { Bridge, CLOUD_PROVIDERS, onEvent, type AiEvent, type AiServer, type Feature, type Resolution } from "../core/bridge";
import { GIT_FOR_WINDOWS, INSTALL_GUIDE, endUnfinished, levelChip, modelChip, planLimitNote, stepRow, type ClaudeLevel } from "../core/claude.ts";
import { featureFor, forgetDrop, stillBusy } from "../core/feature";
import { Sound } from "../core/sound";
import { State, type AiAction, type ChatMessage, type ModelChoice } from "../core/state";
import { decideChatApproval, releaseChatApprovals } from "../island/hooks";
import type { ViewActions, ViewHost } from "./views";

```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
function chipLabel(r: Resolution | null): string {
  if (!r || r.empty) return "No model yet";
  const name = r.modelName ?? r.provider ?? "";
  return r.auto ? `Auto · ${name}` : name;
```

and replace it with:

```typescript
function chipLabel(r: Resolution | null): string {
  if (!r || r.empty) return "No model yet";
  // Who pays is what Claude Code reported, never a guess.
  if (r.provider === "claudeCode") return modelChip(State.claudeStatus?.authMethod ?? null, State.claudePaidBy);
  const name = r.modelName ?? r.provider ?? "";
  return r.auto ? `Auto · ${name}` : name;
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
  const chipRow = h("div", { class: "chip-row" });
  const fileChipSlot = h("span", {});
  const modelChip = h("button", { class: "chip model-chip", title: "Which model answers" });
  chipRow.append(fileChipSlot, modelChip);
  const log = h("div", { class: "chat-log" });
  const picker = h("div", { class: "model-picker" });
  const input = h("input", {
    type: "text",
```

and replace it with:

```typescript
  const chipRow = h("div", { class: "chip-row" });
  const fileChipSlot = h("span", {});
  const modelChipEl = h("button", { class: "chip model-chip", title: "Which model answers" });
  // What Claude may do in this chat (only when Claude Code is the engine): Chat only, Read-only or Agent.
  const levelChipEl = h("button", { class: "chip level-chip", title: "What Claude may do in this chat" });
  chipRow.append(fileChipSlot, levelChipEl, modelChipEl);
  const log = h("div", { class: "chat-log" });
  const picker = h("div", { class: "model-picker" });
  const levelPicker = h("div", { class: "model-picker" });
  const input = h("input", {
    type: "text",
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
    "div",
    { class: "view" },
    h("div", { class: "card wash chat-card" }, h("div", { class: "chat-body" }, chipRow, log, picker, bar)),
  );
  (el.querySelector(".card") as HTMLElement).style.setProperty("--wash", "rgba(99,102,241,0.5)");
```

and replace it with:

```typescript
    "div",
    { class: "view" },
    h("div", { class: "card wash chat-card" }, h("div", { class: "chat-body" }, chipRow, log, picker, levelPicker, bar)),
  );
  (el.querySelector(".card") as HTMLElement).style.setProperty("--wash", "rgba(99,102,241,0.5)");
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
  let showGuide = false;
  let pickerOpen = false;
  let countdown: { note: ChatMessage; left: number; timer: number; files: string[] } | null = null;

  async function refreshModel() {
    resolution = await Bridge.aiResolve(nextFeature());
    modelChip.textContent = chipLabel(resolution);
    State.notify();
  }
```

and replace it with:

```typescript
  let showGuide = false;
  let pickerOpen = false;
  let levelPickerOpen = false;
  let countdown: { note: ChatMessage; left: number; timer: number; files: string[] } | null = null;

  async function refreshModel() {
    resolution = await Bridge.aiResolve(nextFeature());
    modelChipEl.textContent = chipLabel(resolution);
    State.notify();
  }
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
        cancelCountdown();
        break;
    }
    State.notify();
```

and replace it with:

```typescript
        cancelCountdown();
        break;
      case "signInClaude":
        void Bridge.claudeSignIn().then((opened) => {
          if (!opened) note("Open a terminal and run: claude auth login");
          State.notify();
        });
        break;
      case "installClaude":
      case "updateClaude":
        actions.openUrl(INSTALL_GUIDE);
        break;
      case "installGit":
        actions.openUrl(GIT_FOR_WINDOWS);
        break;
      case "tryAgain": {
        // The message that got no answer goes again.
        const last = [...State.chatHistory].reverse().find((m) => m.role === "user");
        if (last) {
          State.chatHistory = State.chatHistory.filter((m) => m !== last);
          input.value = last.content;
          submit();
        }
        break;
      }
    }
    State.notify();
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
      if (stale()) return;
      switch (e.type) {
        case "started":
          reply.caption = e.caption;
```

and replace it with:

```typescript
      if (stale()) return;
      switch (e.type) {
        case "claudeSession":
          // The chat learns its Claude Code session before anything runs: its hook events are the chat's.
          State.claudeSessions.add(e.sessionId);
          if (e.retired) {
            State.claudeSessions.delete(e.retired);
            releaseChatApprovals(e.retired);
          }
          break;
        case "step": {
          const { type: _type, ...step } = e;
          const steps = reply.steps ?? [];
          const at = steps.findIndex((s) => s.id === step.id);
          if (at >= 0) steps[at] = step;
          else steps.push(step);
          reply.steps = steps;
          if (!State.chatHistory.includes(reply)) State.chatHistory.push(reply);
          break;
        }
        case "engine":
          State.claudePaidBy = e.paidBy;
          break;
        case "started":
          reply.caption = e.caption;
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
          reply.content = e.text || reply.content;
          reply.status = e.interrupted ? "interrupted" : e.cancelled ? "stopped" : undefined;
          // Drop the "waking up" line once the model has spoken.
          reply.notices = (reply.notices ?? []).filter((n) => !n.startsWith("Waking up"));
          if (!reply.content) {
            State.chatHistory = State.chatHistory.filter((m) => m !== reply);
            if (e.cancelled) giveBack(req.attachments);
```

and replace it with:

```typescript
          reply.content = e.text || reply.content;
          reply.status = e.interrupted ? "interrupted" : e.cancelled ? "stopped" : undefined;
          // A step that never finished (Stop, a crash) ends as stopped: no row stays "running".
          if (reply.steps) reply.steps = endUnfinished(reply.steps);
          // Drop the "waking up" line once the model has spoken.
          reply.notices = (reply.notices ?? []).filter((n) => !n.startsWith("Waking up"));
          // Stop during Claude Code's work keeps the steps it took, even with no words yet.
          if (!reply.content && !reply.steps?.length) {
            State.chatHistory = State.chatHistory.filter((m) => m !== reply);
            if (e.cancelled) giveBack(req.attachments);
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
          State.chatHistory = State.chatHistory.filter((m) => m !== reply);
          Sound.play("error");
          // The cat shows its error face once; it never loops on an error.
          State.stateOverride = "error";
          window.setTimeout(() => {
            if (State.stateOverride === "error") State.stateOverride = null;
            State.notify();
          }, 1500);
          const n = note(e.message, e.action);
          const wait = e.type === "error" ? e.retryAfter : null;
          const retrying = wait != null && req.retries < MAX_AUTO_RETRIES;
```

and replace it with:

```typescript
          State.chatHistory = State.chatHistory.filter((m) => m !== reply);
          Sound.play("error");
          // The cat shows its error face once, or the rate-limit look for the plan's limit; it never loops on an error.
          State.stateOverride = e.type === "error" && e.resetsAt != null ? "ratelimit" : "error";
          window.setTimeout(() => {
            if (State.stateOverride === "error") State.stateOverride = null;
            State.notify();
          }, 1500);
          // The plan's limit says when it resets, in the viewer's time zone.
          const text = e.type === "error" ? planLimitNote(e.message, e.resetsAt) : e.message;
          const n = note(text, e.action);
          const wait = e.type === "error" ? e.retryAfter : null;
          const retrying = wait != null && req.retries < MAX_AUTO_RETRIES;
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
    if (sending) {
      void Bridge.aiCancel();
      return;
    }
```

and replace it with:

```typescript
    if (sending) {
      void Bridge.aiCancel();
      // Whatever Claude Code was waiting to do is refused, and the card goes.
      releaseChatApprovals();
      return;
    }
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
      });
    picker.append(option("Auto", "auto"));
    if (clouds.length) picker.append(h("div", { class: "picker-head", text: "Cloud" }));
    for (const { c, models } of clouds) {
```

and replace it with:

```typescript
      });
    picker.append(option("Auto", "auto"));
    if (State.settings.ai.claudeCodeEnabled && State.claudeStatus?.state === "signedIn") {
      picker.append(h("div", { class: "picker-head", text: "Claude plan" }));
      for (const m of ["sonnet", "opus", "haiku"]) {
        picker.append(option(`Claude plan · ${m[0].toUpperCase()}${m.slice(1)}`, { provider: "claudeCode", model: m }));
      }
    }
    if (clouds.length) picker.append(h("div", { class: "picker-head", text: "Cloud" }));
    for (const { c, models } of clouds) {
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
  }

  modelChip.addEventListener("click", () => {
    if (pickerOpen) {
      pickerOpen = false;
      State.notify();
      onHeightChange();
    } else {
      void openPicker();
    }
  });

  // ── Rendering ───────────────────────────────────────────────────────────────

```

and replace it with:

```typescript
  }

  modelChipEl.addEventListener("click", () => {
    if (pickerOpen) {
      pickerOpen = false;
      State.notify();
      onHeightChange();
    } else {
      levelPickerOpen = false;
      void openPicker();
    }
  });

  // ── Level picker (Claude Code only) ─────────────────────────────────────────

  /** Whether Claude Code is the engine that answers the next message. */
  const usesClaude = () => resolution?.provider === "claudeCode";

  async function chooseLevel(level: ClaudeLevel, folder: string | null) {
    try {
      State.claudeLevel = (await Bridge.claudeSetLevel(level, folder)) ?? State.claudeLevel;
      levelPickerOpen = false;
    } catch (err) {
      note(String(err).replace(/^Error:\s*/, ""));
    }
    State.notify();
    onHeightChange();
  }

  /** The folder Claude may work in: the system's dialog, else the path typed in. */
  async function drawLevelPicker() {
    clear(levelPicker);
    const hooksReady = (await Bridge.hooksStatus())?.installed ?? false;
    const row = (label: string, detail: string, level: ClaudeLevel, enabled = true) =>
      h("button", {
        class: State.claudeLevel.level === level ? "picker-item on" : "picker-item",
        text: `${label} — ${detail}`,
        disabled: !enabled,
        onclick: async () => {
          if (level === "chat") return void chooseLevel("chat", null);
          const picked = await Bridge.claudePickFolder();
          if (picked) return void chooseLevel(level, picked);
          // No dialog here (or it was cancelled): ask for the path as text.
          pathRow(level);
        },
      });
    function pathRow(level: ClaudeLevel) {
      const path = h("input", { type: "text", class: "chat-input", placeholder: "Folder path", spellcheck: "false" }) as HTMLInputElement;
      const use = h("button", { class: "note-btn", text: "Use it", onclick: () => void chooseLevel(level, path.value.trim()) });
      levelPicker.append(h("div", { class: "picker-path" }, path, use));
      path.focus();
      onHeightChange();
    }
    levelPicker.append(
      row("Chat only", "answers, dropped files, web search", "chat"),
      row("Read-only", "also reads files in a folder you choose", "read"),
      row("Agent", "also edits files and runs commands there, each behind a card", "agent", hooksReady),
    );
    if (!hooksReady) {
      levelPicker.append(h("div", { class: "picker-head", text: "Agent needs NotchMeow's hooks in Claude Code, or every step is refused. Install them in Settings." }));
    }
    onHeightChange();
  }

  levelChipEl.addEventListener("click", () => {
    if (sending) return;
    levelPickerOpen = !levelPickerOpen;
    if (levelPickerOpen) {
      pickerOpen = false;
      void drawLevelPicker();
    }
    State.notify();
    onHeightChange();
  });

  // ── Rendering ───────────────────────────────────────────────────────────────

```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
      case "chooseModel": return "Choose model";
      case "cancel": return "Cancel";
    }
  }
```

and replace it with:

```typescript
      case "chooseModel": return "Choose model";
      case "cancel": return "Cancel";
      case "signInClaude": return "Sign in";
      case "installClaude": return "How to install";
      case "updateClaude": return "How to update";
      case "installGit": return "Get Git for Windows";
      case "tryAgain": return "Try again";
    }
  }
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
      );
    }
    const col = h("div", { class: "reply-col" }, h("div", { class: "reply", text: m.content }));
    if (m.status === "interrupted" && m === State.chatHistory.at(-1)) {
      col.append(
```

and replace it with:

```typescript
      );
    }
    const col = h("div", { class: "reply-col" });
    // Steps Claude Code took: one row each, in the island's own words.
    if (m.steps?.length) {
      col.append(h("div", { class: "reply-steps" }, ...m.steps.map((s) => h("div", { class: `step-row ${s.state}`, text: stepRow(s) }))));
    }
    if (m.content) col.append(h("div", { class: "reply", text: m.content }));
    if (m.status === "interrupted" && m === State.chatHistory.at(-1)) {
      col.append(
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
      h("button", { class: "btn primary", text: "Add a cloud key", onclick: () => actions.openSettingsWindow() }),
      h("button", { class: "btn secondary", text: "Use a local model", onclick: () => { showGuide = true; State.notify(); } }),
    );
  }
```

and replace it with:

```typescript
      h("button", { class: "btn primary", text: "Add a cloud key", onclick: () => actions.openSettingsWindow() }),
      h("button", { class: "btn secondary", text: "Use a local model", onclick: () => { showGuide = true; State.notify(); } }),
      // The first run: Settings → AI opens on the Connect Claude box.
      h("button", { class: "btn secondary", text: "Connect Claude", onclick: () => actions.openSettingsWindow() }),
    );
  }

  /** "Claude needs permission" for the step it is waiting to take, with Allow and Deny: the island's own approval card. */
  function approvalCard(): HTMLElement | null {
    const waiting = State.chatApprovals.front;
    if (!waiting) return null;
    return h(
      "div",
      { class: "chat-row" },
      h(
        "div",
        { class: "chat-approval" },
        h("div", { class: "who", text: "Claude needs permission" }),
        h("div", { class: "code", text: waiting.command || waiting.tool }),
        h("div", { class: "actions" },
          h("button", { class: "btn secondary", text: "Deny", onclick: () => decideChatApproval("deny") }),
          h("button", { class: "btn primary", text: "Allow", onclick: () => decideChatApproval("allow") })),
      ),
    );
  }
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
      const thinking = State.stateOverride === "thinking";
      const empty = !!resolution?.empty;
      const key = [
        thinking, empty, showGuide,
        // A note's text can change at the same length (a countdown), so notes key on their text.
        ...State.chatHistory.map((m) =>
          `${m.id}:${m.role === "note" ? m.content : m.content.length}:${m.status ?? ""}:${m.caption ?? ""}:${m.sources?.length ?? 0}:${m.notices?.length ?? 0}:${m.action?.kind ?? ""}`),
      ].join("|");
      if (key !== renderedKey) {
        renderedKey = key;
        clear(log);
        for (const m of State.chatHistory) {
          if (m.role === "assistant" && !m.content && thinking) continue;
          log.append(bubble(m));
        }
        if (thinking) log.append(typingDots());
        if (empty && !showGuide) log.append(emptyState());
```

and replace it with:

```typescript
      const thinking = State.stateOverride === "thinking";
      const empty = !!resolution?.empty;
      const waiting = State.chatApprovals.front;
      const key = [
        thinking, empty, showGuide, waiting?.requestId ?? "",
        // A note's text can change at the same length (a countdown), so notes key on their text.
        ...State.chatHistory.map((m) =>
          `${m.id}:${m.role === "note" ? m.content : m.content.length}:${m.status ?? ""}:${m.caption ?? ""}:${m.sources?.length ?? 0}:${m.notices?.length ?? 0}:${m.action?.kind ?? ""}:${(m.steps ?? []).map((s) => s.id + s.state).join(",")}`),
      ].join("|");
      if (key !== renderedKey) {
        renderedKey = key;
        clear(log);
        for (const m of State.chatHistory) {
          if (m.role === "assistant" && !m.content && !m.steps?.length && thinking) continue;
          log.append(bubble(m));
        }
        const card = approvalCard();
        if (card) log.append(card);
        if (thinking) log.append(typingDots());
        if (empty && !showGuide) log.append(emptyState());
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript

      picker.style.display = pickerOpen ? "" : "none";
      const mode = sending ? "stop" : "send";
      if (send.dataset.mode !== mode) {
```

and replace it with:

```typescript

      picker.style.display = pickerOpen ? "" : "none";
      levelPicker.style.display = levelPickerOpen ? "" : "none";
      levelChipEl.style.display = usesClaude() ? "" : "none";
      // The level chip takes the right-hand edge, and the model chip sits beside it.
      modelChipEl.style.marginLeft = usesClaude() ? "0" : "";
      levelChipEl.textContent = levelChip(State.claudeLevel.level, State.claudeLevel.folder);
      levelChipEl.toggleAttribute("disabled", sending);
      const mode = sending ? "stop" : "send";
      if (send.dataset.mode !== mode) {
```

**Edit `windows/src/views/chat.ts`**, find this text (it occurs exactly once):

```typescript
      input.focus();
      input.select();
      void refreshModel();
      void Bridge.aiPrewarm(nextFeature());
    },
```

and replace it with:

```typescript
      input.focus();
      input.select();
      void (async () => {
        // Before a chat's first message: is Claude Code there, and signed in? (Never on a timer.)
        if (State.settings.ai.claudeCodeEnabled && State.chatHistory.length === 0) {
          State.claudeStatus = (await Bridge.claudeStatus()) ?? State.claudeStatus;
        }
        await refreshModel();
      })();
      void Bridge.aiPrewarm(nextFeature());
    },
```

Settings:

**Edit `windows/src/settings/main.ts`**, find this text (it occurs exactly once):

```typescript
import "./settings.css";
import { Bridge, CLOUD_PROVIDERS, onEvent, type AiServer, type Feature, type HookAgent, type HookStatus, type ModelInfo } from "../core/bridge";
import { DEFAULT_SETTINGS, type AiSettings, type ModelChoice, type Settings } from "../core/state";
import { keyCheckFailure } from "../core/feature";
```

and replace it with:

```typescript
import "./settings.css";
import { Bridge, CLOUD_PROVIDERS, onEvent, type AiServer, type Feature, type HookAgent, type HookStatus, type ModelInfo } from "../core/bridge";
import { INSTALL_GUIDE, GIT_FOR_WINDOWS, signInWords, type ClaudeStatus } from "../core/claude.ts";
import { DEFAULT_SETTINGS, type AiSettings, type ModelChoice, type Settings } from "../core/state";
import { keyCheckFailure } from "../core/feature";
```

**Edit `windows/src/settings/main.ts`**, find this text (it occurs exactly once):

```typescript

function aiSection(present: Record<string, boolean>): HTMLElement {
  const which = h("div", { class: "ai-box" });
  const clouds = h("div", { class: "ai-box" });
```

and replace it with:

```typescript

function aiSection(present: Record<string, boolean>): HTMLElement {
  const connect = h("div", { class: "ai-box" });
  const which = h("div", { class: "ai-box" });
  const clouds = h("div", { class: "ai-box" });
```

**Edit `windows/src/settings/main.ts`**, find this text (it occurs exactly once):

```typescript
  }

  async function refresh() {
    servers = (await Bridge.aiDiscover()) ?? [];
    const stale = (id: string) => !models[id] || Date.now() - (loadedAt[id] ?? 0) > MODEL_LIST_MAX_AGE_MS;
```

and replace it with:

```typescript
  }

  // 0. Connect Claude: your Claude plan through your own installed Claude Code, or an API key. It looks when this window
  // opens and when asked, never on a timer.
  let claude: ClaudeStatus | null = null;
  const claudeReady = () => settings.ai.claudeCodeEnabled && claude?.state === "signedIn";

  async function drawConnect() {
    claude = (await Bridge.claudeStatus()) ?? null;
    clear(connect);
    connect.append(h("h3", { text: "Connect Claude" }));

    const button = (label: string, onclick: () => void, kind = "") => h("button", { class: kind, text: label, onclick });
    const feedback = h("div", {});
    const inUse = settings.ai.claudeCodeEnabled && settings.ai.preferredCloud === "claudeCode";
    const sayStatus = (): string => {
      const version = claude?.version ? ` ${claude.version}` : "";
      switch (claude?.state) {
        case "tooOld": return `Claude Code${version} is too old for this.`;
        case "signedOut": return `Claude Code${version} is signed out. Signing in opens a terminal, and finishes in your browser.`;
        case "signedIn": return `✓ Claude Code${version}, signed in with ${signInWords(claude.authMethod)}.`;
        case "unknown": return "Couldn't ask Claude Code. Is it installed properly?";
        default: return claude?.shimOnly
          ? "Only a claude.cmd shim was found, which NotchMeow can't run. Install Claude Code with Anthropic's own installer."
          : "Claude Code isn't installed on this computer.";
      }
    };

    const actions = h("div", { class: "row" });
    if (claude?.state === "signedIn") {
      if (inUse) {
        actions.append(
          h("span", { class: "check ok", text: "Claude is now your main AI." }),
          button("Stop using it", async () => {
            settings.ai = {
              ...settings.ai,
              claudeCodeEnabled: false,
              preferredCloud: settings.ai.preferredCloud === "claudeCode" ? "anthropic" : settings.ai.preferredCloud,
            };
            await save();
            await drawConnect();
            void drawWhich();
          }),
        );
      } else {
        actions.append(button("Use my Claude plan", async () => {
          settings.ai = { ...settings.ai, claudeCodeEnabled: true, preferredCloud: "claudeCode", chat: "auto" };
          await save();
          await drawConnect();
          void drawWhich();
        }, "primary"));
      }
    } else if (claude?.state === "signedOut") {
      actions.append(button("Sign in", async () => {
        clear(feedback);
        if (!(await Bridge.claudeSignIn())) {
          feedback.append(h("div", { class: "notice warn", text: "Open a terminal and run: claude auth login" }));
        }
      }, "primary"));
    } else {
      actions.append(h("a", { href: INSTALL_GUIDE, text: claude?.state === "tooOld" ? "How to update" : "How to install", onclick: (e: Event) => { e.preventDefault(); void Bridge.openUrl(INSTALL_GUIDE); } }));
    }
    actions.append(button("Check again", () => void drawConnect()));
    if (claude?.needsGit) {
      feedback.append(h("div", { class: "notice err" },
        "Claude Code needs Git for Windows. ",
        h("a", { href: GIT_FOR_WINDOWS, text: "Get it", onclick: (e: Event) => { e.preventDefault(); void Bridge.openUrl(GIT_FOR_WINDOWS); } }),
        ", then check again."));
    }

    // Path 2: an API key from the Claude Console, checked and saved like any other.
    const field = h("input", { type: "password", placeholder: "sk-ant-...", style: "flex:1 1 auto;min-width:0", autocomplete: "off", spellcheck: "false" }) as HTMLInputElement;
    const keyFeedback = h("div", {});
    const saveKey = button("Save key", async () => {
      const value = field.value.trim();
      if (!value) return;
      clear(keyFeedback);
      try {
        await Bridge.secretSet("anthropic-api-key", value);
        field.value = "";
        present["anthropic-api-key"] = true;
        settings.ai = { ...settings.ai, preferredCloud: "anthropic" };
        await save();
        keyFeedback.append(h("div", { class: "notice ok", text: "Saved. It never touches disk." }));
        drawClouds();
        void drawWhich();
      } catch (err) {
        keyFeedback.append(h("div", { class: "notice err", text: `Could not save: ${String(err)}` }));
      }
    }, "primary");

    connect.append(
      h("div", { class: "provider" },
        h("h4", {}, statusDot(claudeReady() || claude?.state === "signedIn"), h("span", { text: "Use my Claude plan" })),
        h("div", { class: "hint", text: "runs your installed Claude Code" }),
        h("div", { class: "hint", text: sayStatus() }),
        actions,
        feedback),
      h("div", { class: "provider" },
        h("h4", {}, h("span", { text: "Paste an API key" })),
        h("div", { class: "hint", text: "From the Claude Console. It is checked and saved in the Credential Manager." }),
        h("div", { class: "row" }, h("label", { text: "API key" }), field, saveKey),
        keyFeedback),
    );
  }

  async function refresh() {
    void drawConnect();
    servers = (await Bridge.aiDiscover()) ?? [];
    const stale = (id: string) => !models[id] || Date.now() - (loadedAt[id] ?? 0) > MODEL_LIST_MAX_AGE_MS;
```

**Edit `windows/src/settings/main.ts`**, find this text (it occurs exactly once):

```typescript
      }
      if (cloud.children.length) select.append(cloud);
      for (const s of servers.filter((x) => x.status === "running" && x.models.length)) {
        const group = h("optgroup", { label: `Local · ${s.name}` });
```

and replace it with:

```typescript
      }
      if (cloud.children.length) select.append(cloud);
      if (claudeReady()) {
        const plan = h("optgroup", { label: "Claude plan" });
        for (const m of ["sonnet", "opus", "haiku"]) {
          plan.append(h("option", { value: choiceValue({ provider: "claudeCode", model: m }), text: `Claude plan · ${m[0].toUpperCase()}${m.slice(1)}` }));
        }
        select.append(plan);
      }
      for (const s of servers.filter((x) => x.status === "running" && x.models.length)) {
        const group = h("optgroup", { label: `Local · ${s.name}` });
```

**Edit `windows/src/settings/main.ts`**, find this text (it occurs exactly once):

```typescript
      });
    }
    // Preferred cloud: only when both Claude and OpenAI have a key.
    if (present["anthropic-api-key"] && present["openai-api-key"]) {
      const pref = h("select", {}) as HTMLSelectElement;
      pref.append(h("option", { value: "anthropic", text: "Claude" }), h("option", { value: "openai", text: "OpenAI" }));
      pref.value = settings.ai.preferredCloud;
      pref.addEventListener("change", async () => {
```

and replace it with:

```typescript
      });
    }
    // Preferred cloud: only when there is more than one to choose from (Claude plan, Claude API key, OpenAI).
    const choices: [AiSettings["preferredCloud"], string][] = [];
    if (claudeReady()) choices.push(["claudeCode", "Claude plan"]);
    if (present["anthropic-api-key"]) choices.push(["anthropic", claudeReady() ? "Claude API" : "Claude"]);
    if (present["openai-api-key"]) choices.push(["openai", "OpenAI"]);
    if (choices.length >= 2) {
      const pref = h("select", {}) as HTMLSelectElement;
      for (const [value, label] of choices) pref.append(h("option", { value, text: label }));
      pref.value = settings.ai.preferredCloud;
      pref.addEventListener("change", async () => {
```

**Edit `windows/src/settings/main.ts`**, find this text (it occurs exactly once):

```typescript
  // Opened in a window that is already showing (plain `npm run dev` in a browser tab).
  if (document.visibilityState === "visible" && document.hasFocus()) void refreshOnOpen();
  return h("section", {}, h("h2", {}, h("span", { text: "AI" })), which, clouds, locals);
}

```

and replace it with:

```typescript
  // Opened in a window that is already showing (plain `npm run dev` in a browser tab).
  if (document.visibilityState === "visible" && document.hasFocus()) void refreshOnOpen();
  return h("section", {}, h("h2", {}, h("span", { text: "AI" })), connect, which, clouds, locals);
}

```

The styles, in the app's own variables and classes:

**Edit `windows/src/style.css`**, find this text (it occurs exactly once):

```css
  padding: 6px 0;
}
```

and replace it with:

```css
  padding: 6px 0;
}

/* Claude Code in the chat: the level chip beside the model chip, the steps Claude took, and the approval card. */
.level-chip {
  margin-left: auto;
  border-color: rgba(255, 255, 255, 0);
  transform: none;
  cursor: default;
}

.level-chip:hover {
  background: rgba(255, 255, 255, 0.16);
}

.level-chip[disabled] {
  opacity: 0.5;
}

.picker-path {
  display: flex;
  gap: 6px;
  padding: 4px 6px;
}

.picker-path input {
  flex: 1 1 auto;
  min-width: 0;
}

.reply-steps {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.step-row {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 500 11.5px var(--font);
  color: var(--dim-3);
}

.step-row::before {
  content: "✓ ";
  opacity: 0.6;
}

.step-row.running {
  color: var(--ink-2);
}

.step-row.running::before {
  content: "› ";
  opacity: 1;
}

.step-row.stopped::before {
  content: "– ";
}

.chat-approval {
  display: flex;
  flex-direction: column;
  gap: 6px;
  width: 100%;
  padding: 8px 10px;
  border: 1px solid rgba(245, 165, 36, 0.35);
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.07);
}

.chat-approval .who {
  font: 400 12px var(--font);
  color: var(--dim-3);
}

.chat-approval .actions {
  display: flex;
  gap: 8px;
}
```

- [ ] **Step 6: Run the checks**

Run: `(cd windows && npm run check:claude)`
Expected: PASS, `All Claude Code UI checks passed`.

```text
✓ 13 hook payloads go to the right place
✓ the island asks the router before it makes or touches a pill
✓ the model chip never claims 'your plan' without being told, and the level chip names the folder
✓ a plan limit says when it resets, as the Mac does
✓ step rows and the approval card use the island's own words
✓ approvals wait in the order they came, and a session's go together
All Claude Code UI checks passed
```

Run: `(cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?")`
Expected: PASS, `tsc exit 0` (strict mode, no unused locals or parameters).

Run: `(cd windows && npm run check:ai 2>&1 | tail -2)`
Expected: PASS, `All AI UI checks passed`.

Run: `(cd windows && npm run check:cat 2>&1 | tail -8)`
Expected: PASS, the cat tests pass and none fails.

Run: `(cd windows && npx --no-install vite build 2>&1 | tail -3)`
Expected: PASS, the last line says `built in`.

`git status --short` must list only the files of this task (`windows/dist` is ignored). Never `npm install`.

- [ ] **Step 7: Commit**

```bash
git add windows/package.json windows/scripts/check-claude-ui.mjs windows/src/core/steps.ts windows/src/core/claude.ts windows/src/core/bridge.ts windows/src/core/state.ts windows/src/island/hooks.ts windows/src/island/island.ts windows/src/views/chat.ts windows/src/settings/main.ts windows/src/style.css
git commit -q -m "feat(claude-code): the Windows/Linux front end for Claude Code: level chip, steps, approvals in the chat, Connect Claude" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


### Task 19: Docs and CI

**Agent:** `nm-implementer-light`. Docs and YAML; the text is given.

**Files:**
- Modify: `docs/AI-PROVIDERS.md` (the shared contract's description), `docs/INTEGRATIONS.md` (in French, like the rest of that file), `windows/README.md`
- Modify: `.github/workflows/build.yml`, `.github/workflows/windows-tests.yml`

**Interfaces:**
- Consumes: the commands and names of Tasks 2 to 18 (`scripts/test-claude-code.sh`, `scripts/test-session-steps.sh`, `scripts/check-app-binary.sh <app> appstore`, `npm run check:claude`, `NM_CLAUDE_CODE_PATH_OVERRIDE`).
- Produces: the written contract (`AI-PROVIDERS.md`: the provider row, Auto's new order, the Claude Code section with the command line, levels, environment, failures and approvals, and the fixture formats), what the plan route sends and to whom (`INTEGRATIONS.md` §5quinquies: the message, files and, in Read-only and Agent, the folder's files go to Anthropic through the user's own Claude Code; the stripped variables; the log rule; the two things to re-check before a public release), the Windows/Linux README (the feature, Git for Windows, no sandbox, how the fake is used in a debug build), and CI that runs the new tests and proves the App Store build has no engine. The macOS CI job also builds the App Store target (Debug) and runs `check-app-binary.sh … appstore` on it; the Windows tests job runs `npm run check:claude`.

- [ ] **Step 1: Document the contract and the data flow**

**Edit `docs/AI-PROVIDERS.md`**, find this text (it occurs exactly once):

```markdown
| `apple` | Apple on-device | local | Foundation Models (macOS 26+) | `SystemLanguageModel.default.availability` |
| `custom` | Local server | local or network | OpenAI-compatible | added by the user |

A `custom` server is `local` when its host is 127.0.0.1, ::1 or localhost, and `network` otherwise.
```

and replace it with:

```markdown
| `apple` | Apple on-device | local | Foundation Models (macOS 26+) | `SystemLanguageModel.default.availability` |
| `custom` | Local server | local or network | OpenAI-compatible | added by the user |
| `claudeCode` | Claude plan | cloud | the user's own installed Claude Code, run as a process (stream-json) | found on disk, then `claude auth status` |

A `custom` server is `local` when its host is 127.0.0.1, ::1 or localhost, and `network` otherwise.
```

**Edit `docs/AI-PROVIDERS.md`**, find this text (it occurs exactly once):

```markdown
## Auto

Auto tries the Preferred cloud (Claude or OpenAI), then the other of the two, then Google,
using the first one with a key. Without a key, it uses the last-used local model, then the
first ready local model, then Apple on-device. A temporary cloud failure retries once on a
local model. See `tests/fixtures/ai/router-cases.json` for every rule as a test case.

## Reply length

```

and replace it with:

```markdown
## Auto

Auto tries the Preferred cloud (Claude plan, Claude API key or OpenAI), then the others of those three, then Google,
using the first one that is ready: one with a key, or `claudeCode` once the user connected it and the last check found
Claude Code signed in (the apps put it in `keys` for the router). Without a key, it uses the last-used local model, then the
first ready local model, then Apple on-device. A temporary cloud failure retries once on a
local model. See `tests/fixtures/ai/router-cases.json` for every rule as a test case.

## Claude Code (`claudeCode`)

The UI calls it **Use my Claude plan**, with the plain-text note "runs your installed Claude Code"; never "Claude Code" as
a label. NotchMeow runs the user's own, unmodified `claude` program, one process per chat turn, and never sees, stores or
forwards a login. Mac and Windows/Linux; the Mac App Store build compiles it out. Everything below is pinned by
`tests/fixtures/ai/claude-code/`; `claude-code/reference.py` is the tie-breaker.

- **Command line.** `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages`,
  then `--session-id <uuid>` on a chat's first turn or `--resume <id>` after, `--model sonnet|opus|haiku`, and the level's
  flags (`expected-args.json`). Every quoted value is one argument. Never `--bare`.
- **Levels**, per chat, every new chat starting at **Chat only**: Chat only (an empty folder NotchMeow owns, web search and
  fetch), Read-only (a folder the user picks, read tools), Agent (the same folder, every edit and command behind NotchMeow's
  approval card). On native Windows Agent passes no sandbox settings: every command asks.
- **Environment.** `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_PROFILE` and every
  `CLAUDE_CODE_USE_*` are dropped (case-insensitively on Windows), because they outrank the plan login (`expected-env.json`).
- **A session lives under its working folder.** A level change that keeps the folder resumes the session; one that moves it
  starts a new session, seeded with a recap of the chat, and retires the old id.
- **What a transcript means** (`expected-parse.json`, `transcripts/`): text deltas are the reply (assistant messages around
  a tool call are joined by a blank line); `tool_use` blocks are step rows that keep only `command`, `file_path`, `path`,
  `query`, `pattern` and `url`; `system/init` says who pays (`apiKeySource`: none or oauth is the plan; user, project, org or
  temporary is an API key; anything else says nothing).
- **Failures** map onto the twelve error kinds with a code in `AiError.code`: `nm_signed_out` (auth), `nm_plan_limit`
  (billing, with `resetsAt`), `nm_claude_missing` (unreachable), `nm_claude_old` and `nm_needs_git` and `nm_folder_missing`
  (bad_request), `nm_claude_offline` (unreachable), `nm_claude_crashed` (interrupted, or server when nothing was said). An
  unknown shape is a crash, never a guess. The exact JSON of Claude Code's failures is not documented: the owner's manual check
  confirms the shapes.
- **Approvals.** The hooks NotchMeow installs in `~/.claude/settings.json` still fire in `-p`. A `PermissionRequest` whose
  `session_id` is one of a chat's own ids goes to that chat's card (`hook-routing.json`); nothing in `nm_*` changes. With no
  decision Claude Code denies the step.
- **Finding it.** `~/.local/bin/claude`, the Homebrew prefixes, the npm global bin, the login shell's `PATH`; on Windows
  `%USERPROFILE%\.local\bin\claude.exe` first (`locator-cases.json`). `claude --version` must be at least the pinned minimum
  (`versions.json`); `claude auth status` gives `authMethod` (`auth-status.json`) and nothing else is kept.

## Reply length

```

**Edit `docs/AI-PROVIDERS.md`**, find this text (it occurs exactly once):

```markdown
| `history-cases.json` | `rule{reservedOutputDivisor, binaryAttachmentChars, notice}` plus `cases[]` of `{name, placement, contextTokens, system, turns[{role, text, files[]}], expect{dropped, notice}}`; a `text` is `{fill, count}`, `fill` repeated `count` times |
| `attachment-cases.json` | `cases[]` of `{file, kind, reason?, mime?, contains?, notContains?}`; run `make_attachments.py <dir>` first |
| `sse/<format>/<name>.txt` | a raw SSE stream exactly as sent on the wire |
| `sse/<format>/<name>.expected.json` | `{text, toolCalls[{id,name,arguments}], citations[{url,title}], refusal, finish, error}` |
```

and replace it with:

```markdown
| `history-cases.json` | `rule{reservedOutputDivisor, binaryAttachmentChars, notice}` plus `cases[]` of `{name, placement, contextTokens, system, turns[{role, text, files[]}], expect{dropped, notice}}`; a `text` is `{fill, count}`, `fill` repeated `count` times |
| `attachment-cases.json` | `cases[]` of `{file, kind, reason?, mime?, contains?, notContains?}`; run `make_attachments.py <dir>` first |
| `claude-code/fake_claude.py` | a stand-in for `claude` that records its argv, environment and stdin and replays a transcript (see its docstring); never contacts anything |
| `claude-code/transcripts/*.jsonl` | what the fake prints: success, tool use, signed out, plan limit, offline, crash and a few more, built from the documented shapes |
| `claude-code/expected-args.json` | `cases[]` of `{name, platform, level, model, resume, sessionId, folder?, cwd, argv}` |
| `claude-code/expected-env.json` | the stripped names and prefixes, and `cases[]` of `{name, platform, base, expect}` |
| `claude-code/expected-parse.json` | `cases[]` of `{name, transcript, exit, stderr, platform, expect{engine, text, steps, finish, error}}` |
| `claude-code/auth-status.json`, `versions.json`, `locator-cases.json`, `hook-routing.json`, `labels.json`, `copy.json` | the other rules above, one file each |
| `sse/<format>/<name>.txt` | a raw SSE stream exactly as sent on the wire |
| `sse/<format>/<name>.expected.json` | `{text, toolCalls[{id,name,arguments}], citations[{url,title}], refusal, finish, error}` |
```

**Edit `docs/INTEGRATIONS.md`**, find this text (it occurs exactly once):

```markdown
---

## 6. Mail (app Mail du Mac)

```

and replace it with:

```markdown
---

## 5quinquies. Claude par le Claude Code de l'utilisateur (« Use my Claude plan »)

**Plateforme** : macOS (hors build Mac App Store, qui n'a que la clé d'API), Windows et Linux.

Un tour de chat = une exécution du programme `claude` **installé et non modifié** de l'utilisateur (`claude -p`, entrée et sortie `stream-json`). L'utilisateur se connecte à Claude Code par le flux d'Anthropic (`claude auth login`, dans un terminal) : NotchMeow ne voit, ne garde et ne transmet jamais cette connexion, et ne lit jamais les éléments du Trousseau ou les fichiers d'identifiants de Claude Code. Seul le champ `authMethod` de `claude auth status` est lu, et rien d'autre n'est conservé.

- **Ce qui part, et où** : le message, les fichiers déposés (image ou PDF en bloc, le reste en texte) vont à Claude Code, qui les envoie à Anthropic au titre du forfait de l'utilisateur. En mode Read-only et Agent, Claude Code lit aussi les fichiers du dossier choisi et peut les envoyer à Anthropic. Chat only ne lit aucun fichier de l'ordinateur.
- **Trois niveaux**, choisis par chat (un nouveau chat commence en **Chat only**) : Chat only (dossier vide de NotchMeow, recherche et lecture web), Read-only (un dossier choisi, outils de lecture), Agent (idem, chaque modification et chaque commande derrière la carte d'approbation de NotchMeow, dans le chat). Rien ne s'exécute sans un clic ; sans hooks installés, Claude Code refuse chaque étape.
- **Variables d'environnement retirées** pour que la connexion au forfait l'emporte : `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_PROFILE` et toute variable `CLAUDE_CODE_USE_*`. Un `apiKeyHelper` des réglages de Claude Code reste prioritaire ; la puce du modèle indique ce que Claude Code annonce (« Claude · your plan » ou « Claude · API key »).
- **Approbations** : les hooks de `~/.claude/settings.json` fonctionnent aussi en `-p`. Une `PermissionRequest` dont le `session_id` est celui d'un chat (choisi par NotchMeow avec `--session-id`) ouvre sa carte dans ce chat ; les sessions de l'utilisateur gardent leurs pastilles.
- **Journal** : types d'événements et codes d'erreur seulement, jamais les arguments, un dossier, le message, la sortie ou l'environnement.
- **À revérifier avant chaque version publique** : la page « legal and compliance » de Claude Code et la facturation des programmes qui lancent Claude Code ; les Conditions commerciales d'Anthropic doivent être acceptées par le titulaire.

Les règles précises sont dans `docs/AI-PROVIDERS.md` et `tests/fixtures/ai/claude-code/`.

---

## 6. Mail (app Mail du Mac)

```

**Edit `windows/README.md`**, find this text (it occurs exactly once):

```markdown
  your network; plain `http` to another computer is flagged as unencrypted.

Every reply is labelled `cloud`, `local` or `network`, and web-search sources
from Claude and OpenAI are clickable. OpenAI requests always send `store: false`.
```

and replace it with:

```markdown
  your network; plain `http` to another computer is flagged as unencrypted.

### Use my Claude plan

**Settings… → AI → Connect Claude** can run your own installed Claude Code for the chat (its note says "runs your installed
Claude Code"). It is found in `%USERPROFILE%\.local\bin\claude.exe` (or on `PATH`), checked when Settings opens and before a
chat's first message, never on a timer. **Sign in** opens a terminal that runs `claude auth login`; the sign-in finishes in your
browser and NotchMeow never sees it. A chat has a **level** next to its model chip: Chat only (the default), Read-only or Agent,
the last two on a folder you pick. In Agent, every edit and command asks through NotchMeow's approval card in the chat, using the
hooks NotchMeow installs for Claude Code (Settings → Claude Code); without them every step is refused. On Windows, Claude Code
needs **Git for Windows**, and has no command sandbox, so every command asks. Only `claude.exe` is run, not a `claude.cmd` shim.

Every reply is labelled `cloud`, `local` or `network`, and web-search sources
from Claude and OpenAI are clickable. OpenAI requests always send `store: false`.
```

**Edit `windows/README.md`**, find this text (it occurs exactly once):

```markdown
server in `tests/fake_local_llm.py`, so it needs Python 3. From a Mac, run the
same thing in Docker: `windows/scripts/cargo-linux.sh test --workspace`.
`npm run check:ai` (Node 22.6 or newer) checks which model setting answers a message.

To click through the chat without keys or models, debug builds read
```

and replace it with:

```markdown
server in `tests/fake_local_llm.py`, so it needs Python 3. From a Mac, run the
same thing in Docker: `windows/scripts/cargo-linux.sh test --workspace`.
`npm run check:ai` (Node 22.6 or newer) checks which model setting answers a message, and `npm run check:claude` the
Claude Code parts of the chat (hook routing, the chips, step rows) against `tests/fixtures/ai/claude-code/`. The Claude Code
engine is tested with a fake `claude` (`tests/fixtures/ai/claude-code/fake_claude.py`); no test runs the real one. A debug build
reads `NM_CLAUDE_CODE_PATH_OVERRIDE` to point the app at the fake (release builds don't contain it).

To click through the chat without keys or models, debug builds read
```

- [ ] **Step 2: Add the tests to CI**

**Edit `.github/workflows/build.yml`**, find this text (it occurs exactly once):

```yaml
        run: bash scripts/test-ai-settings.sh

      - name: Test plan gauge
        run: bash scripts/test-plan-gauge.sh
```

and replace it with:

```yaml
        run: bash scripts/test-ai-settings.sh

      - name: Claude Code engine (fake claude, shared fixtures)
        run: bash scripts/test-claude-code.sh

      - name: Session step rows
        run: bash scripts/test-session-steps.sh

      - name: Test plan gauge
        run: bash scripts/test-plan-gauge.sh
```

**Edit `.github/workflows/build.yml`**, find this text (it occurs exactly once):

```yaml
            CODE_SIGNING_REQUIRED=NO

      - name: Check app binary (weak FoundationModels, no Debug override)
        run: bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app release
```

and replace it with:

```yaml
            CODE_SIGNING_REQUIRED=NO

      - name: Check app binary (weak FoundationModels, no Debug override, Claude Code engine in)
        run: bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app release

      - name: Build the App Store target (Debug)
        run: |
          xcodebuild \
            -project NotchBuddy/NotchBuddy.xcodeproj \
            -scheme NotchMeowAppStore \
            -configuration Debug \
            -derivedDataPath NotchBuddy/build-store \
            build \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO

      - name: Check the App Store binary (no Claude Code engine, locator or plan card)
        run: bash scripts/check-app-binary.sh NotchBuddy/build-store/Build/Products/Debug/NotchMeow.app appstore
```

**Edit `.github/workflows/windows-tests.yml`**, find this text (it occurs exactly once):

```yaml
      - name: Cat checks
        run: npm run check:cat
      - name: Test
        shell: bash
```

and replace it with:

```yaml
      - name: Cat checks
        run: npm run check:cat
      - name: Claude Code chat checks
        run: npm run check:claude
      - name: Test
        shell: bash
```

- [ ] **Step 3: Check the YAML and that every name the docs and CI use exists**

Run: `ruby -e 'require "yaml"; %w[build windows-tests].each { |f| YAML.load_file(".github/workflows/#{f}.yml") }; puts "yaml ok"'`
Expected: PASS, `yaml ok`.

Run: `grep -c "test-claude-code.sh\|test-session-steps.sh\|NotchMeowAppStore\|check:claude" .github/workflows/build.yml .github/workflows/windows-tests.yml`
Expected: PASS, a count of 3 for `build.yml` (the two test scripts and the App Store scheme) and 1 for `windows-tests.yml`.

Run: `ls scripts/test-claude-code.sh scripts/test-session-steps.sh scripts/check-app-binary.sh windows/scripts/check-claude-ui.mjs tests/fixtures/ai/claude-code/fake_claude.py`
Expected: PASS, all five files are listed.

- [ ] **Step 4: Commit**

```bash
git add docs/AI-PROVIDERS.md docs/INTEGRATIONS.md windows/README.md .github/workflows/build.yml .github/workflows/windows-tests.yml
git commit -q -m "docs: the Claude Code engine's contract, what it sends, and CI that tests it and proves the App Store build has none" -m "Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```


### Task 20: Owner checkpoint: both apps, with a real Claude Code

**Who:** the main session runs Step 1 and shows it to the owner; no implementer agent. Step 2 is the owner's own manual check, on a Windows machine (and a Linux one if there is one), with a Debug build of the Windows/Linux app and the owner's own Claude Code. Nothing here changes code. No session ever runs `claude`, touches the owner's Claude account, or launches, quits or replaces a NotchMeow app. The same checks the owner already did on the Mac (Task 13, Part B) apply here; this list is what differs.

**What the owner gets:** both apps finished, the contract proved by the same fixtures on both, and the list of what only Windows or a real Claude Code can confirm.

- [ ] **Step 1: The evidence**

From the branch's top folder, and show the last lines of each:

```bash
CL=windows/scripts/cargo-linux.sh; TD=/repo/windows/target/e3-claude
$CL test --workspace --target-dir $TD
(cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?")
(cd windows && npm run check:claude)
(cd windows && npm run check:ai 2>&1 | tail -2)
(cd windows && npm run check:cat 2>&1 | tail -8)
(cd windows && npx --no-install vite build 2>&1 | tail -3)
bash scripts/test-ai-contract.sh
```

Expected: every `test result:` line `ok`, `tsc exit 0`, `All Claude Code UI checks passed`, no `FAILED`. Then the Windows `cargo check` of Task 17 (or its result in CI on the pull request: `windows-tests.yml` runs the workspace tests on Windows), and `git log --oneline e3/connect-claude ^notchmeow/rebrand` (Tasks 1 to 19). Say what was not run (Docker, a real Windows machine).

- [ ] **Step 2: What the owner checks on Windows (and Linux)**

Build and run the Debug app as the repository's README says (`cd windows && npm install && npm run tauri dev`; the owner's own machine, the owner's own `npm install`). Sign in to Claude Code once with `claude auth login` in a terminal.

1. **Finding it:** Settings → AI → Connect Claude shows the version and "signed in with …". With Claude Code installed by Anthropic's installer (`%USERPROFILE%\.local\bin\claude.exe`) it is found even when Claude Desktop's own `claude.exe` is first on `PATH`. If only an npm `claude.cmd` shim exists, the box says NotchMeow can't run it and points at Anthropic's own installer.
2. **Git for Windows (Review Focus 7):** on a machine without Git for Windows (a clean VM is enough), the box says "Claude Code needs Git for Windows. Get it", a chat run says the same with a **Get Git for Windows** button, and neither says "stopped unexpectedly".
3. **Sign in:** with Claude Code signed out, **Sign in** opens Windows Terminal (else PowerShell; on Linux the first installed terminal) running `claude auth login`; the sign-in finishes in the browser and nothing of it appears in NotchMeow.
4. **Each level:** the same as the Mac's B2 to B4: Chat only answers and searches the web but cannot read your disk; Read-only reads the folder and cannot write; Agent shows an approval card in the chat for each edit **and for every command** (native Windows has no command sandbox, so there Review Focus 8 does not apply: every command asks). **Deny** leaves no file, **Allow** creates it.
5. **Stop during a tool:** in Agent ask for `ping -n 60 127.0.0.1`, **Allow**, then **Stop**. After a few seconds `tasklist | findstr PING` prints nothing, and the step row says "stopped".
6. **Agent back to Chat only, your own sessions alongside, a folder with spaces and accents** (`C:\Users\<you>\Mes projets\ünï côde`), **signed out**, **offline**: as in Task 13, Part B (B7 to B10). The signed-out run must say "Claude Code is signed out." with a Sign in button; if it says anything else, the signed-out shape differs from the fixtures: capture `claude -p "hi" --output-format stream-json --verbose` into a scratch folder (never the repo) and tell the main session.
7. **The approval card on the island:** with the chat open and the island collapsed, a chat's request opens the island on the chat and plays the approval sound; **Allow** or **Deny** works from there, and a request from your own terminal session still shows as its own pill.
8. **Mac parity:** nothing here is Windows-only that the Mac lacks, except the typed-path fallback when the system has no folder dialog and the Git for Windows note.

- [ ] **Step 3: The release checklist (the spec's "Owner actions before a public release")**

Tell the owner, and do nothing about them in code: (1) accept Anthropic's Commercial Terms, which are required to run Claude Code inside a product; (2) re-read Claude Code's legal and compliance page and Anthropic's billing for programs that run Claude Code (it changed several times in 2026; `docs/INTEGRATIONS.md` §5quinquies lists it); (3) the manual checks above and in Task 13 with a real Claude Code, including a plan limit when one happens naturally.

- [ ] **Step 4: Ask the owner**

Show Step 1 and the owner's results. Ask the open questions below that the checks bear on (1, 2 and 5), and whether to merge. A shape or flag that differs is one edit in `tests/fixtures/ai/claude-code/` and `reference.py` first, then in both ports (their tests fail until they match).

### Final review

**Agent:** `nm-reviewer-deep`, over the whole branch (`git diff 5abfa45...e3/connect-claude`), after the owner's checkpoints.

Check across tasks: (1) the contract: `tests/fixtures/ai/claude-code/` changed only in Task 2 (or a deliberate fix after a checkpoint, with `reference.py` updated first), contains no real transcript, no account, no path or id of the owner's, and both ports replay it (`git grep -n "expected-args.json"` finds the Mac test, the Rust test and `reference.py`); (2) the same case gives the same argv in Swift, Rust and Python (read `ClaudeCodeEngine.swift`, `claude_code.rs` and `reference.py` side by side), with `--bare` nowhere in the diff; (3) the App Store proof: every Claude Code file is wrapped in `#if !APPSTORE` or reached only from code that is, `scripts/check-app-binary.sh` passes its three modes and fails the other three, and `NM_CLAUDE_CODE_PATH_OVERRIDE` is behind `#if DEBUG`; (4) approvals: routing is by `session_id` only, `git diff 5abfa45 -- windows/hook` is empty and no hook payload field (`nm_kind`, `nm_agent`, what the relay answers) is added or changed (the only new `nm_` strings are the `AiError.code` values of the failure table), `HookServer` and `hooks.ts` ask the router before any pill logic, no "Always" is offered, and a request nobody answers is refused; (5) 0 % CPU hidden: `git diff 5abfa45 | grep -n "Timer\|setInterval\|scheduledTimer\|makeTimerSource\|loop {"` finds no polling timer, and the one sleep per turn is the startup watchdog; (6) privacy: no `AILog`, `log::line`, `print` or `console.` line in the new non-test code carries an argument list, a folder, a file name, a prompt, a session id, stdout, stderr or an environment value, and Claude Code's Keychain items and credential files are never read; (7) never restyle: the diffs of `IslandViewContent.swift`, `SettingsView.swift`, `chat.ts`, `settings/main.ts` and `style.css` touch only the places the plan lists, and no existing colour, size or spacing changed; (8) the Mac gets everything Windows/Linux got: the level chip, steps, approvals, Connect Claude, Sign in, the recap, Stop that takes the whole tree, Try again; (9) the Review Focus: each of its eleven lines has the test the plan names, and the tests can fail (the Stop mutations of Tasks 6 and 16, the binary-check negatives of Task 12); (10) no `UserDefaults` suite, no network, no `rm -rf` in a test or an agent command, nothing launched, `claude` never run, and nothing pushed.



---

## Decisions the plan makes

The spec leaves these open; the plan decided them so the code could be written. Each is one edit if the owner disagrees.

1. **Minimum Claude Code: 2.1.211**, the version the flags were verified against (2026-10-06). Below it the box says "Update Claude Code". One number (`ClaudeCodeLocator.minimumVersion`, `claude_cli::MINIMUM_VERSION`, `versions.json`) to lower once older versions are checked.
2. **Allow and Deny only.** The card has no "Always allow": a chat's approval is for one step. A request nobody answers is refused after 115 s on the Mac and 110 s on Windows/Linux (the hook waits 120).
3. **A question cannot be answered in a chat run.** `AskUserQuestion` from a chat's run is handed back as `ask`, and Claude Code carries on without; the user's own sessions keep their question card.
4. **A level change that moves the working folder starts a new session** with a text recap: the last 20 turns, each cut to 1,500 characters and the whole to 20,000, oldest first out, words only (no file bodies).
5. **Steps keep six fields.** A step row's input keeps only `command`, `file_path`, `path`, `query`, `pattern` and `url`, each cut to 200 Unicode scalars, so a Write's content never leaves the parser. Auto never hands a question to another model once steps were taken, and a plan limit never falls back or counts down.
6. **The sign-in is a script in Terminal.** The Mac writes `claude-sign-in.command` (mode 0700) into NotchMeow's support folder and opens it; Windows opens Windows Terminal, else PowerShell; Linux the first installed terminal. NotchMeow never sees what happens there.
7. **Windows runs `claude.exe` only.** A `claude.cmd` shim cannot take JSON arguments safely, so it is reported ("install with Anthropic's installer") and never run. Git for Windows' `bash.exe` is looked for in `CLAUDE_CODE_GIT_BASH_PATH` and the usual places, only to say so before the first turn.
8. **The model aliases are `sonnet`, `opus`, `haiku`,** shown as "Claude plan · Sonnet" and so on; the default is Sonnet. The picker never lists API model IDs for this provider.
9. **What is stored:** `claudeCodeEnabled` and `claudeCodeModel` in the settings (UserDefaults on the Mac, `settings.json` on Windows/Linux); the empty `claude-chat` folder and, on the Mac, the sign-in script. Nothing else: no login, no token, no transcript, no history of the chat (Claude Code keeps its own).
10. **Failure words** are the plain ones in `copy.json`. A plan limit says "resets at 3:45 pm" in the viewer's time zone and locale, with no button and never a billing page.
11. **Debug-only fake:** `NM_CLAUDE_CODE_PATH_OVERRIDE` (like `NM_AI_BASE_URL_OVERRIDE`) lets a Debug build run the fake `claude`; Release and App Store builds do not contain the string, and `check-app-binary.sh` proves it.

## Self-review notes

Run against the spec after writing:

- **Spec coverage.** *§1 what the user sees:* Connect Claude with its two paths in Settings and a button in the chat's empty state (Tasks 11 and 18); the level chip, its three levels and the folder picker (11, 18); the model chip reading what Claude Code reports, and the model picker's Sonnet, Opus and Haiku (8, 10, 11, 18); step rows and the approval card inside the chat (9, 11, 18); the cat's rate-limit look (10, 18). *§2 architecture:* the provider `claudeCode`, cloud, in the shared fixtures and both catalogs (1, 3, 14); one run per turn with the exact command line, stdin and stdout handling (2, 4, 5, 6, 15, 16); the stripped variables (4, 15); the three levels and the Windows exception (4, 15); finding Claude Code and the checks that never run on a timer (7, 10, 16, 17); the App Store build (3 to 12). *§3 approvals:* Chat only and Read-only never ask (the argv), Agent through the existing hooks and routed by `session_id` with no new contract string (8, 9, 10, 17, 18); credentials never read; the re-check (19, 20). *§4 errors:* every row of the table has a code, a note, a button and a test (5, 8, 15), and Auto's fallback follows the E1 rules (1, 3, 14, 17). *§5 testing:* the fake `claude` (2), the Mac programs (4 to 10), the Rust tests (15 to 17), the App Store proof (12), the routing tests for both apps (8, 10, 18). *Owner actions and risks:* Tasks 13, 19 and 20; billing drift and the Windows sandbox are named, startup time is left as the spec leaves it.
- **Placeholder scan:** none left. Every code step carries its full code or its exact old and new text, and no step points at another task for code.
- **Type consistency:** the names a later task uses are the ones an earlier task produces: `ClaudeCodeTurn`, `ClaudeCodeLevel` and `ClaudeCodeCommand` (4) in the provider (6), the session (8) and the wiring (10); `ChatStep`, `EngineReport`, `ClaudeCodeError` (5) in the views (11); `ClaudeCodeSetup` (10) in the factory; `claude_code::{Level, Turn, Stream}` (15) in `claude_run` (16) and `claude_chat` (17); `Step`, `EngineReport`, `AiError.after_steps/resets_at` (14) in `session.rs` (17); the four command names and event names of Task 17 are the ones `bridge.ts` invokes and `chat.ts` handles (18).
- **Review Focus:** each of the eleven lines names the tests that pin it, in the task that owns the code, and Tasks 6, 12 and 16 show those tests failing when the code is broken.
- **Known limits, said plainly.** The exact JSON of some Claude Code failures is not documented: the fixtures hold the documented shapes and the parser treats anything else as "stopped unexpectedly", so a real shape that differs costs a wrong note, never a wrong action (the owner's checks in Tasks 13 and 20 confirm them). No unit test can know whether Agent mode's sandbox runs a command without asking (Review Focus 8, open question 1). The SwiftUI and DOM views are checked by building and by the owner, not by unit tests.


## Dry run (2026-10-06)

**Method.** The plan's blocks were applied, task by task and step by step, to a throwaway clone of `notchmeow/rebrand` at `5abfa45` (`git clone --shared`, in a scratch folder), with a small script that applies every Create and Edit block (an edit fails unless its find text occurs exactly once), runs every `Run:` line (checking that it fails or passes as the plan says, and that the text the plan quotes is in the output), and runs every commit block. The quoted red and green outputs above are the ones it captured. After every task the clone's tree was compared with the tree the code was first written and verified in: for all 19 tasks, applied in order (1 to 12, then 14 to 19, in one clone), `git diff` was empty, which includes the generated XcodeGen project. A separate lint found no placeholder, no step that points at another task for code, and no `Run:` line without an `Expected:`.

**Contract (Tasks 1 and 2).** Red then green as quoted. The reference model fails when one expectation is broken on purpose (Task 2, Step 7), and `bash scripts/test-ai-contract.sh` passes (13 fake-server tests).

**Mac (Tasks 3 to 12).** Every red step is the compile error quoted. `bash scripts/test-claude-code.sh` ends with seven test programs and 393 checks, none failing; `bash scripts/test-session-steps.sh` 15; the ten `scripts/test-ai-*.sh` pass after Tasks 3 and 5. The source pins of Task 10 fail before the wiring and pass after it. Both Stop mutations of Task 6 fail the Stop tests, and the restored code passes. The Debug build is `** BUILD SUCCEEDED **` after each of Tasks 3, 5 to 11 (so the app compiles after every Mac task), the App Store target (Debug) after Tasks 10 to 12 and the unsigned Release after Task 12. `check-app-binary.sh` printed the three positive lines and the three negative ones quoted in Task 12.

**Windows/Linux Rust (Tasks 14 to 17).** Docker was not running, and the real crate cannot build offline here (its `auto-launch` dependency is not in the cargo cache and downloads were not allowed), so `windows/scripts/cargo-linux.sh` was not used. The plan's `$CL test …` lines were run, with `cargo test --offline`, in a throwaway crate next to the app crate (untracked, outside git) that compiles the app's real pure modules in place (`provider`, `catalog`, `router`, `errors`, `session`, `sse`, `budget`, the three providers, `discovery`, `attachments`, the four `claude_*` files) and the real `settings.rs`, with stand-ins for `log`, `platform` and `hooks::stamp`. Results: Task 14 `ai:: settings::` 132 passed; Task 15 `ai::claude_code` 7 tests (22 with `ai::errors` and `settings::`); Task 16 15 passed (9 in `claude_cli`, 6 in `claude_run`) and both Stop mutations fail the Stop test; Task 17 47 passed (4 in `claude_chat` and the six new ones in `session`); the whole throwaway crate 164 passed. Three existing tests that drive tokio's clock (`real_silence_of_120_seconds_still_ends_the_turn`, `reasoning_events_keep_a_cloud_turn_alive_past_the_silence_limit`, `a_model_that_only_reasons_for_61_seconds_is_not_timed_out`) fail in that crate at the base commit too (its tokio features differ from the app's), so they were skipped there and are not in the counts. The Rust tests ran on macOS: the Unix process-group Stop is proved, the `taskkill` path is not.

**Not compiled in the dry run.** The Tauri glue: `AiState`'s new field, the four commands and the readiness block of `ai_chat` in `ai/mod.rs` were compiled separately, in a throwaway module with a stand-in for `tauri::State`, and type-check; the `#[tauri::command]` attributes, the registration in `lib.rs` and every `#[cfg(windows)]` line (the tree kill, the `.exe` locations, PowerShell, Windows Terminal) were not, until Task 17 Step 6 or CI compiles them.

**Front end (Task 18).** With the repository's `node_modules` linked in and `npx --no-install`: `tsc --noEmit` exit 0, `npm run check:claude` red then green as quoted, `npm run check:ai` passes, `npm run check:cat` 83 tests pass, `vite build` builds. No browser check of the chat view was made (an earlier plan had a stubbed-backend one): the DOM glue is checked by the type checker, the build and the owner (Task 20).

**Docs and CI (Task 19).** Both workflow files parse as YAML and every name they use exists. The workflows themselves did not run.

**Never run, by design.** `claude` (every run used the fake), any NotchMeow app (the SwiftUI views and the DOM were built, not run), the owner's account, the network, Docker, a Windows or Linux machine, and the owner's manual checks.


## Open questions for the owner

1. **Sandboxed commands:** decided 2026-10-06: every command asks (`"autoAllowBashIfSandboxed":false` in the Agent settings JSON). The owner confirms a card appears in Task 13 (B5).
2. **Is 2.1.211 the right floor?** It is the version the flags were verified on, so older ones are refused with "Update Claude Code". Lowering it needs someone to run the flags on an older version.
3. **Should Chat only keep web search and fetch?** The spec says yes. It means a chat can fetch a URL the user's message (or a page it read) names, so Chat only is "no files, but not offline". The alternative is no tools at all (`--tools ""`), one line in each port and the fixture.
4. **Windows without a native `claude.exe`** (only the npm `claude.cmd` shim): the plan reports it and refuses to run it. The alternative is running it through `cmd /c`, which cannot take the JSON arguments safely. The plan keeps the refusal.
5. **The failure shapes** (signed out, plan limit, offline) are built from the documented events. The owner's real runs in Tasks 13 and 20 confirm them; the fixtures and `reference.py` change first if they differ.
6. **Before any public release:** accept Anthropic's Commercial Terms, and re-read the legal and compliance page and the billing for programs that run Claude Code (Task 20, Step 3). Not code.

## The owner's answers (2026-10-06)

- **Plan:** approved, run in a worktree session on Sonnet 5.5, effort high.
- **Question 1, sandboxed commands:** always ask. `"autoAllowBashIfSandboxed":false` is in the plan's code and fixtures, and the spec is updated to match.
- **Questions 2 and 3, not asked separately; as planned:** the floor stays at 2.1.211, the version the flags were verified on, and Chat only keeps web search and fetch, as the approved spec says.
- **Question 4, Windows npm shim:** keep refusing it and ask for Anthropic's native installer.
- **App Store build (Task 13):** no Connect Claude box; App Store Settings → AI stays exactly as it ships.
