# F3a-tauri: One Chat and the Companion on Windows and Linux: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows/Linux app's chat becomes the companion for the 2026-11-13 relaunch, as on the Mac: one chat for every brain (the model chip picks it; E3's level chip becomes the **Folder** control, shown only for the Claude plan), a bigger chat view and a **Pop out** window, conversations stored as files (at most 50; rename, pin, delete, delete all), the cat's personality with humor and the quiet rule, a **"Right now"** block from the Projects registry so "what are my agents doing" is answered without a tool, **Fix / Rewrite / Explain** on the field's text and **Explain this screenshot** on a pasted or dropped image, the **Companion** tab in Settings → AI and chat, and the Sidekick tab's "Comes with F3a" chip renamed "Coming soon".

**Architecture:** The rules are `shared/companion-core.js` (F3a-0), copied into `windows/src/companion/core.generated.ts` by a new `scripts/gen-companion-ts.mjs` (the Projects pattern) and typed by `companion/core.ts`; `npm run check:companion` replays `tests/fixtures/companion/` against the copy. The page builds each turn's system text (`promptOf`, with a new `device: 'pc'` word set added to the core in Task 1) and hands it to Rust with the turn; Rust keeps the conversation as today (`ai/session.rs`), puts that text in place of its built-in prompt (and, for the Claude plan, at the head of the turn's preamble), and remembers the last request's text parts in memory for "What the AI saw last". Conversations are files Rust writes (`companion_store.rs`: owner-only, atomic, no symlink, 8 MiB cap); the page cleans every record with `conversationClean` before a save and after a load. The pop-out is a second webview (`chat.html`), created hidden at launch like Settings, that owns the chat while it is shown; the island relays it the "Right now" context and the chat's approval cards (the desktop cat's relay pattern). Nothing runs while the chat is idle.

**Tech Stack:** TypeScript (Node 22 `--experimental-strip-types` tests; erasable syntax only; `.ts` extensions in imports the tests load), CSS, Rust (Tauri 2, `serde_json`; through `windows/scripts/cargo-linux.sh` and `cargo-windows-check.sh`), JavaScript for the core (Task 1), headless Chrome for the pictures. No new crate, no npm package.

**Spec (binding):** `docs/superpowers/specs/2026-10-17-notchmeow-chat-design.md`, approved 2026-10-22: "Owner's answers, 2026-10-22" (relaunch scope), Goals 1–3 and 5, rules 4–7, 12, 14 (the F3a part), "The chat (Mac)" (One view, Size, Conversation list, The cat, Quick actions, the Sidekick tab's rows), "Windows and Linux", "Privacy and CPU", calls 1, 2, 4, 9, 14, 15 and, after the builder check, 3, 4, 5, 7, 9. **Contract:** `docs/superpowers/plans/2026-10-17-f3a-0-companion-contract.md` ("Interface for the app plans"), `docs/COMPANION-CONTRACT.md`, `tests/fixtures/companion/`. **The Mac is the reference:** `docs/superpowers/plans/2026-10-17-f3a-mac-companion.md` (being rewritten as this is written). Where it and this plan differ on a word, a size or a behaviour, **the Mac's merged code wins** (CLAUDE.md: Mac is primary; Windows/Linux gets at most what the Mac gets, with the Mac's words); Task 12 pins the shared words to the Mac's Swift.

**Not in this plan (1.1, owner 2026-10-22):** memory's app side (the memory file and screen, "Remember this?", "Use memory"), the Day log, the daily recap and "Today so far", the sidekick upgrade, F3a2 (OpenAI plan, OpenCode), F3b–F3d (tools, actions, brainstorm to plan, computer use). The prompt is built with `useMemory: false`.

**Base:** a new branch `f3a-tauri/companion` in a git worktree, from `main` at `9c439961` or later **after F3a-0 has merged** (Task 0 checks `shared/companion-core.js` and the ten fixtures). Tasks 0–11 can run beside F3a-mac. **Task 12 needs F3a-mac merged** (it adds the Windows columns to F3a-mac's Companion entries in the shared `tests/fixtures/settings/controls.json`, and its drift pins read the Mac's Swift); if F3a-mac is not on `main` when Task 11's checkpoint is done, the controller stops and pings (Questions for the owner, 5). If a find text below no longer occurs exactly once because the base moved, stop and report; do not guess.

## Global Constraints

Every task's requirements include this section.

- **The contract decides.** Only Task 1 edits `shared/companion-core.js`, `scripts/gen-companion-fixtures.mjs`, `tests/companion/`, `tests/fixtures/companion/` and `docs/COMPANION-CONTRACT.md`, and only by addition. The app carries no hand-made port of a rule: only the generated copy, typed by `companion/core.ts`. If an app test and a fixture disagree, the core is right.
- **Mac is primary.** Words, sizes and behaviours are the Mac's (`CompanionChrome.swift`, `ChatSizing.swift` and the views of F3a-mac). Where this plan names a word before the Mac's code exists, it is the old Mac plan's word, and Task 12 replaces it with the merged Mac's if they differ. No global shortcut on Windows/Linux (the Mac's `openChat` is Mac-only). No Services menu: quick actions work on the message field and on a pasted or dropped image (spec, "Windows and Linux").
- **Prompt (rules 4–6, 12).** Built only by `promptOf` with `device: 'pc'`, `useMemory: false`, `userName` absent (Plan call: no account name is read on Windows/Linux; the prompt says "the user's"), the Main cat's label and personality (`settings.cat.character`, `settings.cat.cats[id].personality`), `humor` and `seeSessions` from `settings.companion`, `quiet` = `companionQuiet({waiting: view.waiting, card: State.attentionNeeded})`, `mood` = `State.effectiveState`, `rightNow` = `rightNowOf(view)` with `view` from the Projects registry (`ProjectsModel.view()`), `today` the local day `YYYY-MM-DD`. Nothing else of the machine goes in.
- **What reaches Rust as the system text** is the page's `promptOf` output, at most 32,000 characters (Rust cuts). Rust adds one line after it for providers that search the web (`WEB_LINE`, below) and nothing else. The Claude plan gets it as the head of the turn's preamble (`CLAUDE_HEAD`, the Mac's words), joined with E3's recap; **E3's command lines and `tests/fixtures/ai/claude-code/` are unchanged byte for byte** (`git diff --quiet main -- tests/fixtures/ai` holds at every task).
- **Stored files:** conversations at `%APPDATA%\NotchMeow\companion\conversations\<id>.json` (Windows, next to `settings.json`) and `$XDG_DATA_HOME/notchmeow/companion/conversations/<id>.json` (Linux, the app's existing data folder; spec, "Windows and Linux"). The folder is private (`platform::ensure_private_dir`), files `0600` on Linux, written atomically (a uniquely named temp file opened with `create_new`, then `rename`), a symbolic link at either path refused (read as absent, never followed or replaced), a file over 8 MiB read as absent and never overwritten. An id is `^[a-z0-9][a-z0-9-]{0,63}$` (the contract's). **No log line, no `settings.json` value and no credential holds a message, a prompt, a reply or a path**; `nm.log` gets fixed sentences only. Deleting from the app deletes the file.
- **What leaves the machine:** only through the brain the user picked, labelled by the existing caption. "Right now" goes only while See my sessions is on (default on, call 15); a cloud brain gets `cloudNotice` once per provider (call 9), recorded in `companion.cloudNoticeShown`.
- **0 % CPU when the island is hidden, and nothing while the chat is idle.** No `setInterval`, no new `requestAnimationFrame` loop, no thread, no file watcher, no poll. The pop-out window exists hidden from launch (a WebView2 window made later comes up blank in this app, `lib.rs` `create_settings_window`) and does nothing until shown; the island pushes it the chat context only while it is shown, on the island's existing `State.notify`.
- **Never restyle what ships.** Allowed changes, all named by the spec: the chat view grows (call 1), gains a menu, the conversation list pane, a quick-result card, a screenshot chip, Markdown in replies (the contract's conduct line asks the brain for light Markdown; Questions for the owner, 3); E3's level chip shows the Folder words; Settings gets the Companion tab and the renamed chip. Everything else stays as on `main`. New pieces use existing classes (`chip`, `model-picker`/`picker-item`, `chat-note`, `note-btn`, `btn primary|secondary`, `chat-approval`) and the Settings kit (`card`, `row`, `switchRow`, `select`, `button`, `help`).
- **Frozen values.** Pill IDs, cat IDs, action IDs, existing settings keys, command and event names, the hook contract strings, the `claude -p` arguments. New and frozen from now on: the `companion` block of `settings.json` (`companion.humor`, `companion.useMemory`, `companion.seeSessions`, `companion.polishRecap`, `companion.recapDismissals`, `companion.lastRecapDay`, `companion.cloudNoticeShown`: the contract's keys, all kept at every save), the window label `chat`, the commands `ai_quick`, `ai_load_turns`, `companion_last_sent`, `companion_list`, `companion_load`, `companion_save`, `companion_delete`, `companion_delete_all`, `ingest_png`, `show_chat_window`, `hide_chat_window`, `chat_relay`, the events `chat-msg`, `chat-window-open`, `chat-window-hidden`.
- **Never block Claude Code, never approve anything.** No hook, no approval path and no tool is added. The chat's approval card (E3, Agent level) works as today, from either window, and only a click answers it.
- **Rust** runs as `windows/scripts/cargo-linux.sh test -p notchmeow <filter> --offline --target-dir /repo/windows/target/f3a-tauri`, and every task that touches `#[cfg(windows)]` code also runs `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-f3a-tauri` and reports its last line. When Docker is down, mark the step "needs Docker". Windows-only code is linked and run only by `windows-tests.yml`: say so in the ledger, never claim it ran.
- **Models and commits** (CLAUDE.md): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local, never pushed, lists only its task's files, and ends with `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` (or `Claude Sonnet 5.5` for Tasks 8 and 9 and any escalated task).
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app; no task sends an event to a real hook socket. A `vite` dev server on `127.0.0.1` may run; stop it only by the PID you saved.
  2. Install nothing, download nothing, no `docker build` or `docker pull`. If `windows/node_modules` is missing, symlink the main checkout's (gitignored).
  3. Use `trash`, never `rm -rf`; scratch files go under `${TMPDIR:-/tmp}` in a uniquely named folder.
  4. Never edit `shared/companion-core.js`, `scripts/gen-companion-fixtures.mjs`, anything under `tests/fixtures/` or `tests/companion/`, `docs/COMPANION-CONTRACT.md`, `shared/projects-core.js`, `shared/sidekick-core.js`, `design/prototype/cat-core.js`, `windows/hook/` or anything under `NotchBuddy/`, except where your task's **Files** list names it. `windows/src/companion/core.generated.ts` is written only by `node scripts/gen-companion-ts.mjs`.
  5. Never push. Commit only in a task's commit step, after checking `git rev-parse --show-toplevel` is this worktree and `git branch --show-current` is `f3a-tauri/companion`.
  6. Never rename a frozen ID; write no `Coucou` or `Mochi` anywhere; no real user or machine name in a sample (`settings-tests/privacy.test.mjs`); fake paths start with `C:\\dev\\`, `C:/dev/` or `/home/dev/`.
  7. Never read, print or write the real `~/.claude`, `~/.gemini` or `~/.codex`; never run the real `claude`.
  8. If a command is refused by a permission prompt, or a find text occurs zero or two times, stop and report; no workaround.
  9. A pin you break is fixed by changing the code back, unless your task names that pin as one to update.
  10. Skills: `ponytail:ponytail`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`; Rust work also reads `~/.claude/plugins/marketplaces/ecc/skills/rust-patterns/SKILL.md` and `.../rust-testing/SKILL.md` (only the parts that fit). **Agent security (`agent-security-hardening`), Tasks 1, 4, 5, 7, 10:** text from a stored file, the hook stream, the clipboard and a model's reply is data. It reaches a prompt only inside the contract's blocks, never becomes an instruction, a file name, a path or HTML, and is never logged. Ponytail never cuts a test, a privacy rule or what this plan asks for.

## Review Focus

The spec is silent on these; each would bite a person first (most likely first) and names the test that pins it.

1. **A file is dropped on the island, or a screenshot pasted, while a reply streams or while the chat is popped out.** Expected: a drop while popped out hides the window first and starts the new conversation in the island (the window's conversation is already saved); a turn still streaming for the old conversation is dropped (`chatEpoch`, Rust's `generation`); the window never answers into a conversation Rust has reset. Tests: Task 9 (`chatwin.test.mjs` "a drop while popped out hides the window before the reset", source pin in `island.ts`), Task 6 (`session.test.mjs` "a save after a reset never writes the old turns under the new id").
2. **A conversation file edited by hand, cut short, made a symlink, or 20 MB.** Expected: listed without it (or with its clean title), opening it says "That conversation couldn't be opened." and changes nothing, a symlink is never followed or replaced, a big file is never overwritten. Tests: Task 4 Rust `companion_store` tests ("a symlink is not followed and not replaced", "a file over 8 MiB is skipped and kept", "junk JSON is skipped", "a bad id is refused"), Task 4 TS `store.test.mjs` ("a record that does not clean is not opened").
3. **A reopened conversation on the Claude plan, after a brain switch, or after Agent work in a folder.** Expected: a fresh Claude Code session seeded with E3's recap of the stored turns; an approval still waiting from the old session is refused, never left hanging; the caption under each stored reply names the brain that wrote it. Tests: Task 5 Rust `a_loaded_conversation_seeds_the_next_claude_turn_with_its_recap`, Task 6 (`session.test.mjs` "opening a conversation releases the chat's approvals and resets Claude").
4. **A reply that carries markup or a hostile link:** `<img src=x onerror=…>`, `[click](javascript:alert(1))`, `[x](file:///C:/)`, a 5,000-line code block. Expected: shown as text; only `http:` and `https:` links become links, and they open through `actions.openUrl`; nothing is ever put in `innerHTML`. Tests: Task 7 (`markdown.test.mjs` rows, and a source pin: no `innerHTML` in `companion/` or `views/chat.ts`).
5. **"Right now" from Windows paths and a stepped-back wait.** A step word holding `C:\Users\sam\Code\app\src\main.ts`, a project in a worktree, a permission request answered in Windows Terminal. Expected: only last parts reach the prompt; the waiting count makes the chat quiet (no joke line); nothing with `\Users\` or `/home/` is in the system text. Test: Task 5 (`turn.test.mjs` "a Windows path in a step never reaches the prompt, and a stepped-back wait keeps it quiet", fed through the real `ProjectsModel.hook`).

Also pinned: the cloud line is shown once per provider and never for a local model (Task 5); a stored conversation's title is `titleOf` its first user message and a rename goes through `titleOf` (Task 6); a quick request's closing tag cannot end the data block (the contract, replayed in Task 2).

---

## The Windows/Linux design

**The prompt for each turn.** `companion/turn.ts` reads the turn context (`TurnContext`: the "Right now" text, quiet, mood) through a `ChatLink` (the island's own State, or, in the pop-out window, the last context the island pushed), builds `promptOf(...)` with `device: 'pc'`, and passes it to `Bridge.aiChat(..., system, onEvent)`. Before a send to a cloud brain, `needsCloudNotice` may add the one-time line as a chat note. Rust: `Env.system` replaces `SYSTEM_PROMPT_SEARCH`/`SYSTEM_PROMPT_PLAIN` (which stay for a turn with no system text: tests and any caller without one), plus `WEB_LINE` = `"You can search the web."` where today's prompt claims web search (`catalog::reads_pdf_natively(provider)`, the same test as now). The Claude plan's preamble is `CLAUDE_HEAD + "\n" + system`, then `"\n\n"` and E3's recap when there is one, on every turn (the "Right now" text changes between turns). `build_request` writes the request's text parts to `AiState.sent` (memory only) for "What the AI saw last".

**Conversations.** The page holds the open conversation (`State.chatHistory`, `State.chatId`, its `createdAt` and `pinned`); Rust holds its turns (unchanged) and the files (`companion_store.rs`). After each finished exchange the page saves `conversationClean(recordOf(...))`, then `conversationsKeep` over `companion_list` and deletes the evicted. Opening one: load, clean, show, and `ai_load_turns` (Rust resets, takes the stored user/assistant texts, and marks a fresh Claude session to be seeded with a recap). A new chat (menu, Explain, a drop) is `chat_reset` as today plus `chatId = null`. Nothing to migrate (call 3): no chat is stored on `main` on Windows/Linux.

**The chat view.** A `⋯` menu chip at the left of the chip row: New chat, Conversations, Pop out, then Fix, Rewrite, Explain (enabled when the field has text). The Conversations pane replaces the log while open (pinned first, then newest, as `conversationsKeep` orders `keep`): a row opens; Pin/Unpin, Rename (inline, Enter), Delete; "Delete all" behind a confirm row. The level chip shows the Folder words. Replies render light Markdown (paragraphs, lists, bold, italic, inline code, fenced code, `http(s)` links), built with `createElement`/`textContent` only. The view's height is the Mac's `ChatSizing` (300 + 40 a message, at most 560), so the island window grows from 320 to 600 px.

**Pop out.** `chat.html` (`src/chatwin/main.ts`) builds the same `buildPrompt` with a window `ChatLink`. Created hidden at launch (label `chat`, title "Chat — NotchMeow", 520 × 640, at least 420 × 360, resizable); Pop out saves the conversation, sets `State.chatPoppedOut`, and calls `show_chat_window(id)` (Rust shows it and emits `chat-window-open {conversationId}` to it; the window opens that conversation from the store). Closing hides it (`prevent_close`) and emits `chat-window-hidden` to the island, which reopens the current conversation (the window tells the island its id on each save) and takes the chat back. While popped out, the island's chat tab brings the window forward and the island's chat view shows only `POPPED_OUT_NOTE` and "Bring it back". Relay messages (`chat_relay(to, msg)`, event `chat-msg`): island → window `{kind: "context", context: TurnContext, approval: WaitingApproval | null}` (on `State.notify` while shown, skipped when unchanged); window → island `{kind: "session", id, retired}`, `{kind: "decide", decision, requestId}`, `{kind: "release", sessionId}`, `{kind: "current", id}`. The window has no cat; the island's cat does not show "thinking" for a reply streaming in the window (Plan call).

**Quick actions.** On the field's text: Fix and Rewrite are one call through `ai_quick` (a throwaway conversation and, for the Claude plan, a throwaway Chat-only session; the chat's own conversation and session are untouched) and show a card above the field ("Fixed"/"Rewritten", the text, "Cut to the first 8,000 characters." when cut, **Copy** and ×); there is no Replace (no source app on Windows/Linux). Explain starts a new conversation whose first turn uses the explain prompt as its system text; follow-ups are normal companion turns (the Mac's call). A screenshot: Ctrl+V of an image in the field (or a dropped image) becomes the waiting attachment (`ingest_png` writes it to the inbox) and a chip "Explain this screenshot" starts a new conversation with it and the `explainImage` prompt; a brain that cannot see says `QUICK_NO_VISION`. The clipboard is never read by NotchMeow (Questions for the owner, 2).

**Settings → AI and chat → Companion** (shown: `COMPANION_TAB_SHOWN = true`): the Mac's relaunch rows that exist here — Humor (Off · A little · More), See my sessions (with the line saying where it goes), Conversations (the count and Delete all), What the AI saw last (the last request's text parts from `companion_last_sent`, or "Nothing sent since NotchMeow started.", "Kept in memory only, gone when NotchMeow quits.").

## File Structure

| Path | Responsibility | Task |
|---|---|---|
| `shared/companion-core.js`, `scripts/gen-companion-fixtures.mjs`, the `tests/companion/` files that replay `prompt-cases.json` and `quick-cases.json`, `tests/fixtures/companion/{prompt,quick}-cases.json` (generated), `docs/COMPANION-CONTRACT.md` | The `device: 'pc'` words, by addition | 1 |
| `scripts/gen-companion-ts.mjs` (new), `windows/src/companion/core.generated.ts` (generated), `windows/src/companion/core.ts` (new), `windows/scripts/companion-tests/{util.mjs,fixtures.test.mjs,fresh.test.mjs}` (new), `windows/package.json`, `.github/workflows/windows-tests.yml` | The generated copy, its types, `check:companion` in CI | 2 |
| `windows/src-tauri/src/companion_settings.rs` (new), `windows/src-tauri/src/{settings,lib}.rs`, `windows/src/core/state.ts`, `windows/scripts/companion-tests/settings.test.mjs` (new) | The `companion` block, both languages | 3 |
| `windows/src-tauri/src/companion_store.rs` (new), `windows/src-tauri/src/lib.rs`, `windows/src/companion/store.ts` (new), `windows/src/core/bridge.ts`, `windows/scripts/companion-tests/store.test.mjs` (new) | Conversation files and the page's records | 4 |
| `windows/src-tauri/src/ai/{session,mod,claude_chat}.rs`, `windows/src-tauri/src/lib.rs`, `windows/src/companion/{turn,link}.ts` (new), `windows/src/projects/model.ts`, `windows/src/core/{state,bridge}.ts`, `windows/src/views/{chat,views}.ts`, `windows/scripts/companion-tests/{turn,wiring}.test.mjs` (new) | The companion in every turn, the cloud line, what was sent | 5 |
| `windows/src/companion/session.ts` (new), `windows/src/views/chat.ts`, `windows/src/core/state.ts`, `windows/src/island/island.ts`, `windows/scripts/companion-tests/session.test.mjs` (new) | Stored conversations in the chat: the menu, the list pane, save, open, new | 6 |
| `windows/src/companion/{chrome,markdown}.ts` (new), `windows/src/companion/companion.css` (new), `windows/src/views/chat.ts`, `windows/src/main.ts`, `windows/scripts/companion-tests/{chrome,markdown}.test.mjs` (new) | The Folder words, Markdown replies | 7 |
| `windows/src/core/layout.ts`, `windows/src-tauri/src/island.rs`, `windows/scripts/companion-tests/size.test.mjs` (new), any existing pin of the 320/300 values the task names | The bigger chat and the taller island window | 8 |
| `windows/chat.html` (new), `windows/src/chatwin/main.ts` (new), `windows/src/companion/link.ts`, `windows/vite.config.ts`, `windows/src-tauri/src/lib.rs`, `windows/src-tauri/capabilities/default.json`, `windows/src/core/{bridge,state}.ts`, `windows/src/views/{chat,views}.ts`, `windows/src/island/island.ts`, `windows/src/main.ts`, `windows/scripts/companion-tests/chatwin.test.mjs` (new) | The pop-out window and its relay | 9 |
| `windows/src-tauri/src/ai/mod.rs`, `windows/src-tauri/src/{files,lib}.rs`, `windows/src/companion/quick.ts` (new), `windows/src/views/chat.ts`, `windows/src/core/{bridge,state}.ts`, `windows/scripts/companion-tests/quick.test.mjs` (new) | Quick actions and the pasted screenshot | 10 |
| `windows/src/companion/devcompanion.ts` (new), `windows/src/cat/dev.ts`, `windows/src/chatwin/main.ts`, `windows/scripts/render-companion.sh` (new) | The `?dev` Companion panel and the pictures | 11 |
| `windows/src/settings/{companion.ts (new),route.ts,app.ts,sidekicktab.ts,sidekick.ts,backend.ts,devseed.ts}`, `tests/fixtures/settings/controls.json`, `windows/scripts/settings-tests/{map,drift,pages,rules}.test.mjs` | The Companion tab, "Coming soon", the drift pins | 12 |
| `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, `docs/SPEC.md` | Docs | 13 |

## Tasks and agents

| # | Task | Agent, model, effort | Extra skills | Review |
|---|---|---|---|---|
| 0 | Worktree and baseline | the session | | none |
| 1 | The core's PC words | `nm-implementer`, Haiku 5.5, high | `agent-security-hardening` | `nm-reviewer` |
| 2 | The generated copy, its types, `check:companion` in CI | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| 3 | The `companion` settings block (TS and Rust) | `nm-implementer`, Haiku 5.5, high | rust | `nm-reviewer` |
| 4 | Conversation files and records | `nm-implementer`, Haiku 5.5, high | rust, `security-review`, `agent-security-hardening` | `nm-reviewer` |
| 5 | The companion in every turn | `nm-implementer`, Haiku 5.5, high | rust, `agent-security-hardening` | `nm-reviewer` |
| 6 | Stored conversations in the chat | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 7 | The Folder words and Markdown replies | `nm-implementer`, Haiku 5.5, high | `agent-security-hardening` | `nm-reviewer` |
| 8 | The bigger chat and the taller island window | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1: the island window's size, click-through and the Linux input region)** | rust | `nm-reviewer` |
| 9 | The pop-out window | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1: a second Tauri webview, its lifetime and the relay between two pages)** | rust | `nm-reviewer` |
| 10 | Quick actions and the pasted screenshot | `nm-implementer`, Haiku 5.5, high | rust, `agent-security-hardening` | `nm-reviewer` |
| 11 | The `?dev` panel and the pictures, then **owner checkpoint 1** | `nm-implementer`, Haiku 5.5, high | | the main session and the owner |
| 12 | Settings → Companion, "Coming soon", drift with the Mac (**needs F3a-mac merged**) | `nm-implementer`, Haiku 5.5, high | `accessibility` *(file)* | `nm-reviewer` |
| 13 | Docs | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| After 13 | The whole branch: cross-task interfaces, the 0 % rule, privacy, prompt-injection boundaries, restyle | `nm-reviewer-deep`, Sonnet 5.5, high (trigger 4), with `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` beside it (`model: sonnet`) | `agent-security-hardening`, `security-review` | none |
| 14 | **Owner checkpoint 2:** a real Windows PC and a real Linux desktop | the main session and the owner | | none |

"rust" = the two Rust skill files of SUBAGENT RULE 10. A Haiku task that fails twice, or fails with no obvious cause, goes to `nm-implementer-deep` (trigger 2), named in the ledger.

**Size:** about 6 working days: Tasks 1–3 half a day each, 4 and 5 a day together, 6–7 a day, 8 half a day, 9 a day, 10 half a day, 11 half a day plus the checkpoint, 12–13 half a day.

## Execution

One worktree chat session runs the plan on branch `f3a-tauri/companion`, on **Sonnet 5.5 at high effort** (trigger 5: fourteen tasks whose interfaces cross: `ChatLink`, `TurnContext`, `StoreBackend`, the relay, `Env.system`, the store commands). It edits `chat.ts`, `views.ts`, `island.ts`, `main.ts`, `state.ts`, `bridge.ts`, `layout.ts`, `lib.rs`, `island.rs`, `settings.rs`, `ai/session.rs`, `ai/mod.rs`: it must not run beside another plan that edits those. Started in the three steps of `ARCHITECT.md`: the chip only runs Task 0 Steps 1–3 and replies "ready" (its prompt carries the owner's advance approval of the controller brief); the main session sets Sonnet 5.5 high; then sends the controller brief: run this plan with `superpowers:subagent-driven-development`, one task-sized brief per task (its text, the Global Constraints, the SUBAGENT RULES), `nm-reviewer` after each, a ledger at `.superpowers/sdd/2026-10-22-f3a-tauri/progress.md` (base commit, then one line per task: agent, model, commit, test lines, review verdict, escalations with their trigger, "needs Docker" and "Windows-only: type-checked only" notes), reviews on `git diff "$(git merge-base HEAD main)"...HEAD` narrowed to the task's files, every shell block through `bash -n` first, stop at Checkpoint 1 (after Task 11) and before Task 12 if F3a-mac is not merged, and `SendMessage` the main session at each checkpoint, at the end and whenever it stops. Final report: the commits; `npm run check:companion`, `check:settings`, `check:projects`, `check:sidekick`, `check:cat`, `check:claude`, `check:ai` (each `ℹ fail 0`); `npx --no-install tsc --noEmit`; `bash scripts/test-companion-contract.sh`; the Rust test lines and the Windows check's last line; the picture paths.

**How to read a step.** Every `Run:` is from the repository root unless it starts with `cd windows`. "Find" texts must occur exactly once; if not, stop and report. A test step names its file and assertions; a code step gives the file, signatures and the values that are pinned, and the implementer writes the bodies. Test files in `windows/scripts/companion-tests/` load the source with `import ... from "../../src/companion/<file>.ts"` and the fixtures through `util.mjs`'s `load(name)`.

---

## Tasks

### Task 0: Worktree and baseline

**Agent: the session itself.** No commit.

- [ ] **Step 1: The branch**

```bash
git switch -c f3a-tauri/companion main
git merge-base --is-ancestor 9c439961 HEAD && echo "base ok"
test -f shared/companion-core.js && ls tests/fixtures/companion/*.json | wc -l && echo "F3a-0 in"
grep -c "^api.promptOf = \|^api.quickRequest = \|^api.conversationClean = \|^api.cleanCompanionSettings = \|^api.rightNowOf = " shared/companion-core.js
git log --oneline main -- NotchBuddy/Sources/App/CompanionChrome.swift | head -1; test -f NotchBuddy/Sources/App/CompanionChrome.swift && echo "F3a-mac in" || echo "F3a-mac not yet"
git rev-parse --show-toplevel && git branch --show-current
```

Expected: `base ok`, `10`, `F3a-0 in`, `5` (if the core assigns its exports another way, read its Interface table and record the five names); either F3a-mac line, recorded in the ledger; the worktree and `f3a-tauri/companion`. Without F3a-0: stop.

- [ ] **Step 2: The anchors** (each prints `1`)

```bash
cd windows
c(){ grep -Fc -- "$2" "$1"; }
c src/views/chat.ts 'export function buildPrompt(actions: ViewActions, onHeightChange: () => void): ViewHost {'
c src/views/chat.ts '      await Bridge.aiChat(req.feature, req.text, req.attachments, req.regenerate, onEvent);'
c src/views/chat.ts '          State.claudeSessions.add(e.sessionId);'
c src/views/chat.ts '      levelChipEl.textContent = levelChip(State.claudeLevel.level, State.claudeLevel.folder);'
c src/views/chat.ts '      row("Chat only", "answers, dropped files, web search", "chat"),'
c src/views/chat.ts '    if (m.content) col.append(h("div", { class: "reply", text: m.content }));'
c src/views/chat.ts '  chipRow.append(fileChipSlot, levelChipEl, modelChipEl);'
c src/views/chat.ts '    State.chatHistory.push({ id: nextId++, role: "user", content: text, attachments });'
c src/views/views.ts '  map.set("prompt", buildPrompt(actions, onChatHeightChange));'
c src/views/views.ts '  const tabChat = h("button", { class: "tab", title: "Ask", onclick: () => go("prompt") }, svg(ICONS.bubble, 13));'
c src/core/layout.ts '  return Math.min(300, 240 + messageCount * 40);'
c src/core/layout.ts 'export const PANEL_H = 320;'
c src/core/state.ts '  chatEpoch = 0;'
c src/core/state.ts '  sidekick: cleanSidekickSettings(null),'
c src/core/state.ts '  sidekick: SidekickSettings;'
c src/core/bridge.ts '  chatReset: () => call<void>("chat_reset"),'
c src/core/bridge.ts '    return callOrThrow<void>("ai_chat", { feature, text, attachments, regenerate, onEvent: channel });'
c src/island/island.ts '    State.chatEpoch++;'
c src/projects/model.ts '  /** The frame the island draws now: the view, the big card (its pin and click are kept), the layout, the section and the peek. */'
c src/main.ts '  await onEvent<Settings>("settings-changed", (s) => {'
c src/settings/route.ts 'export const COMPANION_TAB_SHOWN = false;'
c src/settings/sidekicktab.ts 'export const COMES_WITH_F3A = "Comes with F3a";'
c src/settings/app.ts '      default: return yourAiTab(ctx, CLOUD_PROVIDERS);'
c vite.config.ts '        desktop: resolve(__dirname, "desktop.html"),'
c package.json '    "check:projects": "node --experimental-strip-types --test --test-reporter=spec scripts/projects-tests/*.test.mjs",'
c src-tauri/src/island.rs 'pub const PANEL_H: f64 = 320.0;'
c src-tauri/src/ai/session.rs '    let system = if catalog::reads_pdf_natively(&reader.provider) { SYSTEM_PROMPT_SEARCH } else { SYSTEM_PROMPT_PLAIN };'
c src-tauri/src/ai/session.rs '                claude.run.preamble = claude_chat::recap(&said);'
c src-tauri/src/ai/session.rs '    pub timeouts: Option<Timeouts>,'
c src-tauri/src/ai/session.rs '    let (request, notices) = match build_request(target, turns, conv, generation).await {'
c src-tauri/src/ai/mod.rs '    let request = TurnRequest { feature, text, files, regenerate };'
c src-tauri/src/ai/claude_chat.rs '    /// Claude Code reported the session: the next turn resumes it.'
c src-tauri/src/settings.rs '    settings.sidekick = crate::sidekick_settings::clean_sidekick(&settings.sidekick);'
c src-tauri/src/settings.rs '            sidekick: crate::sidekick_settings::default_value(),'
c src-tauri/src/lib.rs 'mod sidekick_settings;'
c src-tauri/src/lib.rs '            chat_reset,'
c src-tauri/src/lib.rs '            create_settings_window(&handle);'
c src-tauri/src/lib.rs 'fn create_settings_window(app: &AppHandle) {'
c src-tauri/capabilities/default.json '  "windows": ["island", "settings"],'
c ../.github/workflows/windows-tests.yml '        run: npm run check:projects'
c scripts/settings-tests/map.test.mjs '    "sidekick.on", "sidekick.dismissals", "sidekick.local",'
c scripts/settings-tests/map.test.mjs '    if (f === "ai" || f === "cat" || f === "sidekick") continue;'
grep -Fc "      - 'scripts/gen-projects-ts.mjs'" ../.github/workflows/windows-tests.yml   # 2: once under pull_request, once under push
cd ..
```

Expected: every line `1`, the last `2` (seen at `9c439961`). Any other count: stop and report which.

- [ ] **Step 3: Baselines (into the ledger)**

```bash
cd windows && for s in cat claude ai sidekick projects settings link; do npm run check:$s 2>&1 | grep -E "^ℹ (tests|fail)"; done; npx --no-install tsc --noEmit && echo "tsc ok"; cd ..
bash scripts/test-companion-contract.sh 2>&1 | tail -2
windows/scripts/cargo-linux.sh test -p notchmeow ai:: settings:: --offline --target-dir /repo/windows/target/f3a-tauri 2>&1 | grep -E "^test result|FAILED|^error" | head
```

Expected: each check `ℹ fail 0` (record the test counts), `tsc ok`, the contract's two `✓` lines, Rust `test result: ok` (or "needs Docker").

---

### Task 1: The core's PC words

**Agent: `nm-implementer` (Haiku 5.5, high).** The contract's personality line says the cat "lives in the notch of … Mac", its conduct line says "You cannot act on the Mac yet", and the quick prompts say "selected on their Mac" and "from the user's Mac". On Windows and Linux those are false. This adds a PC word set, by addition, so the Mac's rows and port are untouched (Questions for the owner, 1).

**Files:**
- Modify: `shared/companion-core.js`, `scripts/gen-companion-fixtures.mjs`, the `tests/companion/*.test.mjs` file that replays `prompt-cases.json` and the one that replays `quick-cases.json`, `docs/COMPANION-CONTRACT.md`
- Regenerate: `tests/fixtures/companion/prompt-cases.json`, `tests/fixtures/companion/quick-cases.json`

**Interfaces:**
- Produces: `api.DEVICES = ['mac', 'pc']`; `promptOf(input)` and `personalityLine(input)` read `input.device`: `'pc'` gives the PC words, anything else the Mac's (every existing row unchanged); `api.CONDUCT_PC`; `api.QUICK_SYSTEM_PC`; `quickRequest(kind, text, device)` (a third, optional argument; `'pc'` takes its `system` from `QUICK_SYSTEM_PC`).
- The PC words, exactly:
  - personality: `` `You are ${cat}, a cat who lives at the top of ${owner} screen and keeps them company while they work.` `` (the rest of the line as the Mac's).
  - `CONDUCT_PC` = `CONDUCT` with `You cannot act on the Mac yet` replaced by `You cannot act on this computer yet`.
  - `QUICK_SYSTEM_PC` = `QUICK_SYSTEM` with `explain`'s `the user selected on their Mac` replaced by `the user pasted from their computer`, and `explainImage`'s `from the user's Mac` replaced by `from the user's computer`; `fix` and `rewrite` are the same text.

- [ ] **Step 1: Write the failing cases** in the generator, in its own forms, as **new groups** (the Mac's replay reads only the existing groups): in `prompt-cases.json` a group `pc` with three rows typed by hand — `'pc: everything on, a balanced cat'` (the existing "everything on" input plus `device: 'pc'`, expect the PC personality line, `CONDUCT_PC`, the memory block, `RIGHT-NOW`, the date), `'pc: quiet'` (plus `quiet: true`), `'pc: junk device is the Mac'` (`device: 'PC'`, expect the Mac's line); in `quick-cases.json` a group `pc` with `'pc: fix is the same'`, `'pc: explain says computer'`, `'pc: a screenshot from the computer'`, `'pc: an unknown device is the Mac'` (`device: 'win'`). In the two test files: replay both `pc` groups, and assert `C.CONDUCT_PC === C.CONDUCT.replace('act on the Mac yet', 'act on this computer yet') && C.CONDUCT_PC !== C.CONDUCT`, `!C.promptOf({ device: 'pc', today: '2026-10-17' }).includes('Mac')`, `!Object.values(C.QUICK_SYSTEM_PC).some(s => s.includes('Mac'))`, `C.quickRequest('fix', 'x', 'pc').system === C.QUICK_SYSTEM.fix`.

- [ ] **Step 2: Run:** `node scripts/gen-companion-fixtures.mjs --check; node --test tests/companion/*.test.mjs 2>&1 | grep -E "^# fail"`. Expected: the generator stops with "… the core says … the case says …" on a new row, and the tests fail.

- [ ] **Step 3: Implement** the Interfaces above in the core, with a doc comment on each new name. No existing constant or row changes.

- [ ] **Step 4: Regenerate and run:** `node scripts/gen-companion-fixtures.mjs && bash scripts/test-companion-contract.sh 2>&1 | tail -2`. Expected: the two `✓` lines. If F3a-mac is merged (Task 0), also `for s in scripts/test-companion-*.sh; do bash "$s" >/dev/null 2>&1 && echo "ok $s" || echo "FAIL $s"; done`: every line `ok` (the Mac never reads the `pc` groups).

- [ ] **Step 5: The contract's words.** `docs/COMPANION-CONTRACT.md`: a section `## Windows and Linux words (device: 'pc')` with the three replacements, why (no notch, not a Mac), and that the Mac's port need not implement them.

- [ ] **Step 6: Commit:** `feat(companion): F3a-tauri the core's PC words (device: 'pc'), by addition`.

---

### Task 2: The generated copy, its types, `check:companion` in CI

**Agent: `nm-implementer-light` (Haiku 5.5, medium).** A copy of the Projects pattern.

**Files:**
- Create: `scripts/gen-companion-ts.mjs`, `windows/src/companion/core.ts`, `windows/scripts/companion-tests/util.mjs`, `fixtures.test.mjs`, `fresh.test.mjs`
- Generate: `windows/src/companion/core.generated.ts`
- Modify: `windows/package.json`, `.github/workflows/windows-tests.yml`

**Interfaces:**
- Produces (`companion/core.ts`, erasable TypeScript, `import { CompanionCore } from "./core.generated.ts"`): `export type Humor = "off" | "little" | "more"`; `export type QuickKind = "fix" | "rewrite" | "explain" | "explainImage"`; `export interface CompanionSettings { humor: Humor; useMemory: boolean; seeSessions: boolean; polishRecap: boolean; recapDismissals: number; lastRecapDay: string; cloudNoticeShown: string[] }`; `export interface StoredMessage { role: "user" | "assistant"; text: string; caption: string; files: string[] }`; `export interface Conversation { version: 1; id: string; title: string; pinned: boolean; createdAt: number; updatedAt: number; messages: StoredMessage[] }`; `export interface QuickRequest { system: string; user: string; cut: boolean }`; `export interface PromptInput { catName?: string; userName?: string; personality?: Record<string, number>; humor?: Humor; quiet?: boolean; mood?: string; useMemory?: boolean; memory?: unknown; seeSessions?: boolean; rightNow?: string; today?: string; placement?: string; contextTokens?: number | null; device?: "mac" | "pc" }`; typed re-exports of `promptOf(i: PromptInput): string`, `companionQuiet(i: { waiting: number; card: boolean }): boolean`, `moodHint(state: string): string`, `rightNowOf(view: unknown): string`, `cloudNotice(provider: string): string`, `needsCloudNotice(i: { placement: string | null; seeSessions: boolean; provider: string | null; shown: readonly string[] }): boolean`, `titleOf(text: unknown): string`, `conversationClean(raw: unknown): Conversation | null`, `conversationsKeep(entries: readonly { id: string; pinned: boolean; updatedAt: number }[]): { keep: string[]; evict: string[] }`, `cleanCompanionSettings(raw: unknown): CompanionSettings`, `quickRequest(kind: string, text: string, device?: "mac" | "pc"): QuickRequest | null`, `quickResultClean(kind: string, reply: unknown): string`, and the constants `HUMOR_LEVELS`, `CONVERSATIONS_MAX`, `TITLE_MAX`, `QUICK_KINDS`, `QUICK_TEXT_MAX`, `QUICK_NO_VISION`, `RIGHT_NOW_MAX`.

- [ ] **Step 1: The generator.** `scripts/gen-companion-ts.mjs` is `scripts/gen-projects-ts.mjs` with `projects` → `companion`, `Projects` → `Companion`, `ProjectsCore` → `CompanionCore`, `PROJECTS` → `COMPANION` (`sed` it, then read it once). `fresh.test.mjs` is `windows/scripts/projects-tests/fresh.test.mjs` with the same replacements. `util.mjs` exports `load(name)` (the fixture loader of `projects-tests/util.mjs`, pointed at `tests/fixtures/companion/`) and nothing else.

- [ ] **Step 2: `fixtures.test.mjs`** replays every group of all ten files against `core.ts` (`note-cases.json`, `memory-cases.json`, `daylog-cases.json` and `recap-cases.json` through the generated copy's own exports, since the relaunch does not type them: `CompanionCore.<name>`), each group asserted non-empty, each row `assert.deepEqual(actual, c.expect, c.name)`, the `pc` groups of Task 1 included (`quickRequest(c.kind, c.text, "pc")`, `promptOf({ ...c.input })`).

- [ ] **Step 3: Run to fail:** `cd windows && node --experimental-strip-types --test scripts/companion-tests/*.test.mjs 2>&1 | grep -E "^ℹ fail"` → not 0 (no copy yet).

- [ ] **Step 4: Write the copy and the types:** `node scripts/gen-companion-ts.mjs`, then `core.ts`. In `package.json`, after the `check:projects` line: `"check:companion": "node --experimental-strip-types --test --test-reporter=spec scripts/companion-tests/*.test.mjs",`. In `windows-tests.yml`: `- 'shared/companion-core.js'`, `- 'scripts/gen-companion-ts.mjs'`, `- 'tests/fixtures/companion/**'` after each of the two `- 'scripts/gen-projects-ts.mjs'` lines, and after the step `run: npm run check:projects`, a step `- name: Companion checks` / `run: npm run check:companion` in the same indentation.

- [ ] **Step 5: Run:** `cd windows && npm run check:companion 2>&1 | grep -E "^ℹ (tests|fail)" && npx --no-install tsc --noEmit && echo "tsc ok"` → `fail 0`, `tsc ok`; `node scripts/gen-companion-ts.mjs --check` → `✓ …`.

- [ ] **Step 6: Commit:** `feat(companion): F3a-tauri the generated core, its types and check:companion`.

---

### Task 3: The `companion` settings block

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Create: `windows/src-tauri/src/companion_settings.rs`, `windows/scripts/companion-tests/settings.test.mjs`
- Modify: `windows/src-tauri/src/settings.rs`, `windows/src-tauri/src/lib.rs` (`mod companion_settings;` after `mod sidekick_settings;`), `windows/src/core/state.ts`

**Interfaces:**
- Produces (Rust): `pub fn clean_companion(raw: &serde_json::Value) -> serde_json::Value` and `pub fn default_value() -> serde_json::Value`, the twin of `cleanCompanionSettings` (`{humor, useMemory, seeSessions, polishRecap, recapDismissals, lastRecapDay, cloudNoticeShown}` in that order; `humor` one of `off`/`little`/`more` else `little`; `useMemory` and `seeSessions` true unless the boolean `false`; `polishRecap` only the boolean `true`; `recapDismissals` a whole number above 0 (a float with no fraction counts, as `2.0` does in JS) capped at 2, else 0; `lastRecapDay` a real `YYYY-MM-DD` day (month 1–12, the month's real length, leap years) else `""`; `cloudNoticeShown` the strings of an array matching `^[a-zA-Z][a-zA-Z0-9_-]{0,31}$`, unique, sorted, at most 16). `Settings.companion: serde_json::Value` with `#[serde(default = "crate::companion_settings::default_value")]`, cleaned in `sanitized` (after the `sidekick` line) and set in `Default`.
- Produces (TS): `Settings.companion: CompanionSettings`, default `cleanCompanionSettings(null)`.

- [ ] **Step 1: Write the failing tests.** Rust, in `companion_settings.rs` (the `sidekick_settings.rs` fixture reader pointed at `tests/fixtures/companion`): `every_row_of_settings_cases_json` (each `cases` row: `clean_companion(raw) == expect`), `cleaning_twice_is_cleaning_once`, `junk_never_panics` (`5`, `"x"`, `[1]`, `null`, `{"humor":{}, "cloudNoticeShown":"anthropic"}`). In `settings.rs`, beside the sidekick's two tests: `the_companion_settings_survive_a_save_a_load_and_a_round_trip` (`humor: "more"`, `seeSessions: false`, `cloudNoticeShown: ["openai","anthropic"]` → saved and loaded as `["anthropic","openai"]`) and `one_bad_field_in_the_companion_object_never_fails_the_settings_file` (the six bad shapes of the sidekick's test, the file kept, the block the default). TS `settings.test.mjs`: `DEFAULT_SETTINGS.companion` deep-equals `cleanCompanionSettings(null)` and has `humor: "little"`, `seeSessions: true`.

- [ ] **Step 2: Run to fail:** `windows/scripts/cargo-linux.sh test -p notchmeow companion_settings settings:: --offline --target-dir /repo/windows/target/f3a-tauri 2>&1 | grep -E "^test result|error\[" | head -3` → errors; `cd windows && npm run check:companion 2>&1 | grep "^ℹ fail"` → not 0.

- [ ] **Step 3: Implement** the Interfaces. In `state.ts`, `companion: CompanionSettings;` after `  sidekick: SidekickSettings;` (with a doc comment: the companion block, clean, sub-project F3a) and `companion: cleanCompanionSettings(null),` after `  sidekick: cleanSidekickSettings(null),`.

- [ ] **Step 4: Run:** the two commands of Step 2 → `test result: ok`, `ℹ fail 0`; `cd windows && npm run check:settings 2>&1 | grep "^ℹ fail"` → `0` (the map's source scan skips `companion` only from Task 12 on: if it fails now on `Settings.companion`, add `|| f === "companion"` to the skip line `    if (f === "ai" || f === "cat" || f === "sidekick") continue;` in `map.test.mjs`, the one map edit this task may make); `npx --no-install tsc --noEmit`.

- [ ] **Step 5: Commit:** `feat(companion): F3a-tauri the companion block of settings.json, kept at every save`.

---

### Task 4: Conversation files and records

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Create: `windows/src-tauri/src/companion_store.rs`, `windows/src/companion/store.ts`, `windows/scripts/companion-tests/store.test.mjs`
- Modify: `windows/src-tauri/src/lib.rs` (`mod companion_store;`, the five commands in the invoke list after `            chat_reset,`), `windows/src/core/bridge.ts`

**Interfaces:**
- Produces (Rust, `companion_store.rs`):
  - `pub const FILE_MAX_BYTES: u64 = 8 * 1024 * 1024;` `pub fn is_id(s: &str) -> bool` (the contract's id); `pub fn companion_dir() -> PathBuf` (`#[cfg(windows)]` `settings::config_dir().join("companion")`, else `settings::local_dir().join("companion")`).
  - `#[derive(Serialize)] #[serde(rename_all = "camelCase")] pub struct Head { pub id: String, pub title: String, pub pinned: bool, pub updated_at: f64 }`.
  - `pub struct Store { root: PathBuf }` with `new(root)`, `list(&self) -> Vec<Head>` (every `<id>.json` that is a regular file, not a symlink, at most `FILE_MAX_BYTES`, parses as a JSON object whose `id` equals its file name; its `title` string or `""`, `pinned === true`, `updatedAt` finite or 0; anything else skipped), `load(&self, id) -> Option<serde_json::Value>` (the same checks), `save(&self, record: &serde_json::Value) -> Result<(), &'static str>` (the id from `record["id"]`, refused when not `is_id`; the text at most `FILE_MAX_BYTES`; refused when a symlink or an over-size file is at the path; the folder made with `platform::ensure_private_dir`; a temp file `.<id>.<n>.tmp` opened with `OpenOptions::create_new` (and mode `0o600` on Unix), written, then `rename`d over), `delete(&self, id) -> Result<(), &'static str>` (only a regular `<id>.json`; a missing file is fine), `delete_all(&self) -> Result<usize, &'static str>` (only regular files named `<id>.json`; nothing else in the folder is touched).
  - Commands, each through `lib.rs`'s `blocking` helper on `Store::new(companion_dir().join("conversations"))`: `companion_list() -> Vec<Head>`, `companion_load(id: String) -> Option<Value>`, `companion_save(record: Value) -> Result<(), String>`, `companion_delete(id: String) -> Result<(), String>`, `companion_delete_all() -> Result<usize, String>`. Refusals are the fixed sentences `"The conversation could not be saved."` and `"The conversation could not be deleted."`; no path or OS text ever goes back or into `nm.log`.
- Produces (TS, `companion/store.ts`): `export interface Head { id: string; title: string; pinned: boolean; updatedAt: number }`; `export interface StoreBackend { list(): Promise<Head[]>; load(id: string): Promise<unknown>; save(rec: Conversation): Promise<boolean>; remove(id: string): Promise<boolean>; removeAll(): Promise<boolean> }`; `export const bridgeStore: StoreBackend` (over the five `Bridge.companion*` calls); `export function newId(): string` (`crypto.randomUUID()`); `export function recordOf(c: { id: string; createdAt: number; pinned: boolean; title?: string }, history: readonly ChatMessage[], now: number): Conversation | null` (user and assistant messages only, `text` = `content`, `caption`, `files` = each attachment's last part; `title` the given one, else `titleOf` of the first user message; through `conversationClean`); `export function messagesOf(rec: Conversation, nextId: () => number): ChatMessage[]`; `export async function saveAndKeep(store: StoreBackend, rec: Conversation): Promise<boolean>` (save; then `conversationsKeep(await store.list())` and `remove` each evicted id; false when the save was refused). `Bridge`: `companionList`, `companionLoad`, `companionSave`, `companionDelete`, `companionDeleteAll` (none outside Tauri: `[]`, `null`, `false`).

- [ ] **Step 1: Write the failing tests.** Rust (a temp root per test, as `shelf.rs` does): `a_saved_record_lists_and_loads_back`, `a_bad_id_is_refused` (`"../x"`, `"A"`, `""`, a 65-character id), `a_symlink_is_not_followed_and_not_replaced` (Unix: a link at `<id>.json` to a file outside; `list` skips it, `load` is `None`, `save` refuses and the target is unchanged), `a_file_over_8_mib_is_skipped_and_kept`, `junk_json_and_a_mismatched_id_are_skipped`, `delete_all_removes_only_conversation_files` (a `notes.txt` and a sub-folder survive), `the_file_is_owner_only` (Unix: mode `0o600`), `no_temp_file_is_left_after_a_save`. TS `store.test.mjs` with an in-memory `StoreBackend`: `recordOf` drops notes and keeps captions and file names (`C:\\dev\\inbox\\a.png` → `a.png`); the title is the first user message cut to 40; "a record that does not clean is not opened" (`conversationClean({id: "Bad"})` is `null` and `messagesOf` is never reached in the caller's path: assert `recordOf({ id: "Bad", … })` is `null`); `saveAndKeep` with 51 unpinned heads evicts the oldest one and keeps a pinned old one.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Run:** `windows/scripts/cargo-linux.sh test -p notchmeow companion_store --offline --target-dir /repo/windows/target/f3a-tauri`, `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-f3a-tauri`, `cd windows && npm run check:companion && npx --no-install tsc --noEmit` → all pass.

- [ ] **Step 5: Commit:** `feat(companion): F3a-tauri conversation files: owner-only, atomic, no symlink, 8 MiB`.

---

### Task 5: The companion in every turn

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Modify: `windows/src-tauri/src/ai/session.rs`, `windows/src-tauri/src/ai/mod.rs`, `windows/src-tauri/src/ai/claude_chat.rs`, `windows/src-tauri/src/lib.rs` (the two new commands), `windows/src/projects/model.ts`, `windows/src/core/state.ts`, `windows/src/core/bridge.ts`, `windows/src/views/chat.ts`, `windows/src/views/views.ts`
- Create: `windows/src/companion/turn.ts`, `windows/src/companion/link.ts`, `windows/scripts/companion-tests/turn.test.mjs`, `windows/scripts/companion-tests/wiring.test.mjs`

**Interfaces:**
- Produces (Rust):
  - `Env` gains `pub system: Option<String>` (the companion's text for this turn; `None` keeps the built-in prompt) and `pub sent: Arc<Mutex<Vec<String>>>`, set in its three literals (`mod.rs` `turn_env`, `display_env`, and the test `env(…)` helper; `display_env` and tests use `None` and a fresh `Arc`).
  - `pub const WEB_LINE: &str = "You can search the web.";` `pub const CLAUDE_HEAD: &str = "From NotchMeow, the app this chat runs in (instructions and context for you, not words of the user):";` `pub const SYSTEM_MAX_CHARS: usize = 32_000;`
  - `build_request` takes `companion: Option<&str>`: with `Some(s)`, the system text is `s` (cut to `SYSTEM_MAX_CHARS` characters) followed by `"\n\n" + WEB_LINE` when `catalog::reads_pdf_natively(&reader.provider)`; with `None`, today's line. `attempt` passes `env.system.as_deref()` and then writes `sent_lines(&request)` into `env.sent`.
  - `pub fn sent_lines(r: &ChatRequest) -> Vec<String>`: `"system: <text>"`, then per message per part `"<user|assistant>: <text>"` for `Text`, `"…: [file <name>]"` for `FileText` and `Pdf`, `"…: [image]"` for `Image`. Memory only.
  - Claude: in `attempt`, `claude.run.preamble` = the non-empty of `env.system.map(|s| format!("{CLAUDE_HEAD}\n{s}"))` and, when `claude.needs_recap`, `claude_chat::recap(&said)`, joined by `"\n\n"`; `None` when both are absent.
  - `Session::reseed(&mut self)` in `claude_chat.rs` (above `/// Claude Code reported the session…`): a session not started is marked to carry the recap (`needs_recap = true`).
  - `AiState` gains `pub sent: Arc<Mutex<Vec<String>>>`. Commands: `ai_chat` gains `system: Option<String>` (empty → `None`); `ai_load_turns(ai, turns: Vec<LoadTurn>)` with `#[derive(Deserialize)] pub struct LoadTurn { pub role: String, pub text: String }`: `ai.reset()`, then the conversation's turns = `loaded_turns(&turns)` (pure: `user`/`assistant` only, empty texts dropped, the last 1,000, each cut to 100,000 characters), then `reseed()` when any; `companion_last_sent(ai) -> Vec<String>`.
- Produces (TS):
  - `ProjectsModel.view(): ProjectsView` (above the `frame` doc comment): `projectsView(this.reg, this.now(), { steps: Object.fromEntries(this.steps) })`, no other effect.
  - `companion/turn.ts`: `export interface TurnContext { rightNow: string; quiet: boolean; mood: string }`; `export function contextOf(i: { view: ProjectsView; attention: boolean; mood: string }): TurnContext`; `export function localDay(d: Date): string`; `export function systemFor(ctx: TurnContext, settings: Settings, today: string): string` (the Global Constraints' `promptOf` input; `catName` = `PRESETS[settings.cat.character]?.label`); `export function brandOf(provider: string): string` (`anthropic`/`claudeCode` → `Anthropic`, `openai` → `OpenAI`, `google` → `Google`, else the id); `export function cloudLine(r: { provider: string | null; placement: string | null } | null, s: CompanionSettings): { line: string; shown: string[] } | null` (`needsCloudNotice`; the new `shown` sorted).
  - `State.contextNow(): TurnContext` = `contextOf({ view: this.projects.view(), attention: this.attentionNeeded, mood: this.effectiveState })`.
  - `companion/link.ts`: `export interface ChatLink { context(): TurnContext; approval(): WaitingApproval | null; decide(d: "allow" | "deny", requestId: string): void; release(sessionId?: string): void; session(id: string, retired: string | null): void }`; `export function islandLink(): ChatLink` (State's context, `State.chatApprovals.front`, `decideChatApproval`, `releaseChatApprovals`, and `session` = what `chat.ts`'s `claudeSession` case does today).
  - `buildPrompt(actions: ChatActions, onHeightChange: () => void, link: ChatLink): ViewHost` with `export type ChatActions = Pick<ViewActions, "openSettingsWindow" | "openUrl" | "emote">`; `views.ts` passes `islandLink()`. `chat.ts` no longer imports `../island/hooks`; its approval card reads `link.approval()`, its buttons call `link.decide`, Stop calls `link.release()`, the `claudeSession` event calls `link.session`.
  - `Ask` gains `system?: string`; `ask` sends `req.system ?? systemFor(link.context(), State.settings, localDay(new Date()))` as the new `system` argument of `Bridge.aiChat(feature, text, attachments, regenerate, system, onEvent)`. In `submit`, before the send, `cloudLine(resolution, State.settings.companion)`: when not null, `note(line)`, `State.settings.companion.cloudNoticeShown = shown`, `Bridge.saveSettings(State.settings)`. `Bridge.aiLoadTurns(turns)`, `Bridge.companionLastSent()`.

- [ ] **Step 1: Write the failing tests.** Rust, in `session.rs`'s tests with the existing fakes: `a_turn_with_companion_text_sends_it_as_the_system_prompt` (local fake; `env.sent` line 0 is `"system: COMPANION-TEXT"`, no `WEB_LINE`), `a_search_provider_gets_the_web_line` (a cloud fake for which `reads_pdf_natively` holds; line 0 ends with `"\n\nYou can search the web."`), `no_companion_text_keeps_the_built_in_prompt`, `the_claude_preamble_carries_the_head_and_the_text_every_turn` (the Claude fake; the user line of two turns both start with `CLAUDE_HEAD`), `a_loaded_conversation_seeds_the_next_claude_turn_with_its_recap` (`loaded_turns` of two stored turns, `reseed`, then a turn: the user line holds `CLAUDE_HEAD`, then `Earlier in this chat`, then the new message last; read as `a_new_session_that_failed_before_it_started_is_retried_with_its_recap` reads it), and in `claude_chat.rs` `a_reseeded_session_plans_a_recap_and_no_resume`; `loaded_turns_keeps_two_roles_and_cuts`. TS `turn.test.mjs`: `contextOf` on a `ProjectsModel` fed through `hook()` with a `UserPromptSubmit` and a `PreToolUse` whose `tool_input.file_path` is `C:\\Users\\sam\\Code\\app\\src\\main.ts` and `cwd` `C:\\Users\\sam\\Code\\app`, then a `PermissionRequest` with `waitIn` `Windows Terminal` (call `hook(payload, "Windows Terminal")`): `quiet === true`, `rightNow` names `app` and holds no `\\Users\\`; `systemFor` holds `"at the top of the user's screen"`, never `"Mac"`, never `"\\Users\\"`, holds `QUIET` words and not the humor line while quiet; with `seeSessions: false` it holds no `"Claude Code"` sessions block; `cloudLine` gives a line for `{provider: "anthropic", placement: "cloud"}` once and `null` when `shown` holds it or the placement is `local`. `wiring.test.mjs` (comment-blind, as `projects-tests/wiring.test.mjs` reads sources): `chat.ts` does not import `../island/hooks` and does not read `State.chatApprovals` (both of today's reads go through `link.approval()`); calls `systemFor(` once; passes `system` to `Bridge.aiChat(`; `views.ts` passes `islandLink()` to `buildPrompt(`.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Run:** `windows/scripts/cargo-linux.sh test -p notchmeow ai:: --offline --target-dir /repo/windows/target/f3a-tauri` (the whole `ai::` suite, so E3's tests prove the command lines unchanged), `git diff --quiet main -- tests/fixtures/ai && echo "ai fixtures untouched"`, `cd windows && for s in companion claude ai projects sidekick; do npm run check:$s 2>&1 | grep "^ℹ fail"; done && npx --no-install tsc --noEmit`.

- [ ] **Step 5: Commit:** `feat(companion): F3a-tauri the companion prompt in every turn, Right now, quiet, the cloud line`.

---

### Task 6: Stored conversations in the chat

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Create: `windows/src/companion/session.ts`, `windows/scripts/companion-tests/session.test.mjs`
- Modify: `windows/src/views/chat.ts`, `windows/src/core/state.ts`, `windows/src/island/island.ts`

**Interfaces:**
- Consumes: Task 4 (`StoreBackend`, `recordOf`, `messagesOf`, `saveAndKeep`, `newId`), Task 5 (`ChatLink`).
- Produces:
  - `State`: `chatId: string | null = null`, `chatCreatedAt = 0`, `chatPinned = false`, `chatTitle: string | null = null` (after `  chatEpoch = 0;`).
  - `companion/session.ts`: `export interface ChatBackend { reset(): void; loadTurns(t: { role: string; text: string }[]): void }` (`bridgeChat` over `Bridge.chatReset` and `Bridge.aiLoadTurns`); `export function startNewChat(link: ChatLink, chat: ChatBackend): void` (what `island.ts`'s drop resets today for the chat: `chatHistory`, `localAnswers`, `pendingAttachment`, `chatEpoch++`, `link.release()`, `State.resetClaude()`, `chat.reset()`, plus `chatId = null`, `chatTitle = null`, `chatPinned = false`); `export async function saveCurrent(store: StoreBackend, now: number): Promise<boolean>` (nothing when the history has no user message; a first save sets `chatId = newId()` and `chatCreatedAt = now`); `export async function openConversation(store: StoreBackend, id: string, link: ChatLink, chat: ChatBackend): Promise<boolean>` (load → `conversationClean` → false and nothing changed when null; else `startNewChat`, then `chatId`, `chatTitle`, `chatPinned`, `chatCreatedAt`, `chatHistory = messagesOf(...)`, `chat.loadTurns(...)`); `export async function rename(store, title: string)`, `togglePin(store)`, `removeOne(store, id)`, `removeAll(store)`.
  - `chat.ts`: a menu chip `⋯` first in the chip row (find `  chipRow.append(fileChipSlot, levelChipEl, modelChipEl);`), its list (`model-picker` / `picker-item`) with "New chat", "Conversations" (and the slots Tasks 9 and 10 fill); the Conversations pane in place of the log while `pane === "list"` (rows in `conversationsKeep(heads).keep` order: title, a small "pinned" mark, Pin/Unpin, Rename, Delete; a footer "Delete all" → a confirm row `Delete all N conversations? This can't be undone.` with Delete and Cancel; an empty list says `No saved conversations yet.`; a failed open adds the note `That conversation couldn't be opened.`). `saveCurrent(bridgeStore, Date.now())` after a `done` that kept a reply, and after rename and pin.
  - `island.ts`: after `    State.chatEpoch++;` the line `    State.chatId = null;` (a drop starts a new conversation that is not saved yet).

- [ ] **Step 1: Write the failing tests** (`session.test.mjs`, an in-memory `StoreBackend`, a recording `ChatBackend` and a recording `ChatLink`): "a first save gives the conversation an id and its first message's title"; "a second save keeps the id and createdAt"; "opening a conversation releases the chat's approvals and resets Claude" (`link.release` called, `State.claudeLevel.level === "chat"`, `loadTurns` given the user/assistant texts only); "a record that does not clean is not opened" (returns false, `chatHistory` unchanged); "a save after a reset never writes the old turns under the new id" (save, `startNewChat`, add one user message, save: two files, the second holds one message); "rename goes through titleOf" (`'  x'.repeat(30)` → 40 code points); "delete all empties the list and starts a new chat when the open one was in it".

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Run:** `cd windows && npm run check:companion && npm run check:claude && npx --no-install tsc --noEmit`.

- [ ] **Step 5: Commit:** `feat(companion): F3a-tauri stored conversations: the menu, the list, rename, pin, delete`.

---

### Task 7: The Folder words and Markdown replies

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Create: `windows/src/companion/chrome.ts`, `windows/src/companion/markdown.ts`, `windows/src/companion/companion.css`, `windows/scripts/companion-tests/chrome.test.mjs`, `windows/scripts/companion-tests/markdown.test.mjs`
- Modify: `windows/src/views/chat.ts`, `windows/src/main.ts` (`import "./companion/companion.css";` beside the other CSS imports)

**Interfaces:**
- Produces:
  - `companion/chrome.ts` (the Mac's words; Task 12 pins them): `folderLabel(level: ClaudeLevel, folder: string | null): string` (`chat` → `No folder`; `read` → `Reads · <name>`; `agent` → `Works in · <name>`; `<name>` by `folderName` of `core/claude.ts`; a `read` or `agent` with no folder → `Reads` or `Works in`); `FOLDER_ROWS = ["No folder", "Read a folder…", "Work in a folder…"]`; `FOLDER_TITLE = "The folder Claude may use in this chat"`; `POPPED_OUT_NOTE = "The chat is in its own window."`; `BRING_BACK = "Bring it back"`; `QUICK_TITLES = { fix: "Fixed", rewrite: "Rewritten" }`; `CUT_NOTE = "Cut to the first 8,000 characters."`; `SCREENSHOT_CHIP = "Explain this screenshot"`; `MENU = { newChat: "New chat", conversations: "Conversations", popOut: "Pop out", fix: "Fix", rewrite: "Rewrite", explain: "Explain" }`; `sentTo(brain: string): string` = `` `This is sent with your messages to ${brain}.` ``. (Task 6's pane words move here too.)
  - `companion/markdown.ts`: `export type Inline = { t: "text" | "b" | "i" | "code"; s: string } | { t: "link"; s: string; href: string }`; `export type Block = { t: "p"; inl: Inline[] } | { t: "ul" | "ol"; items: Inline[][] } | { t: "pre"; s: string }`; `export function parseMarkdown(text: string): Block[]` (pure: fenced ```` ``` ```` blocks with an optional language word (kept as text, never a class); lines starting `- `, `* ` or `N. ` grouped into a list; `#`-headings become a `p` whose inlines are bold; blank lines split paragraphs; inline `**x**`, `*x*`/`_x_`, `` `x` ``, `[label](url)` → a `link` only when `url` starts with `http://` or `https://`, else the whole thing as text; anything unmatched is text); `export function renderBlocks(blocks: Block[], openUrl: (u: string) => void): DocumentFragment` (`createElement`/`textContent` only; a link is an `a` with no `href` attribute whose click calls `openUrl(href)`).
  - `chat.ts`: the level chip shows `folderLabel(...)` with `title = FOLDER_TITLE`; the three level rows read `FOLDER_ROWS` with their existing detail text after ` — `; an assistant reply renders `renderBlocks(parseMarkdown(m.content), actions.openUrl)` inside the `reply` div (user bubbles and notes stay plain text).
  - `companion.css`: spacing only for `.reply p`, `.reply ul`, `.reply ol`, `.reply pre`, `.reply code`, `.reply a`, the menu chip, the pane rows and the quick card (`.cm-*` names), using the island's existing colours.

- [ ] **Step 1: Write the failing tests.** `chrome.test.mjs`: the four `folderLabel` cases (`chat` → `No folder`; `read`, `C:\\dev\\notchmeow` → `Reads · notchmeow`; `agent`, `/home/dev/site/` → `Works in · site`; `agent`, null → `Works in`); `sentTo("Claude · your plan")`. `markdown.test.mjs` (`parseMarkdown` only; Node has no DOM): a paragraph with bold, italic and code; a `-` list and a `1.` list; a fenced block keeps its text exactly and its language is not a class; `<img src=x onerror=alert(1)>` is one text inline; `[click](javascript:alert(1))` and `[x](file:///C:/)` are text, `[a](https://x.y/z)` is a link with that `href`; 5,000 lines in a fence parse in under 200 ms; `"# Title"` is a bold paragraph. Source pins: no `innerHTML`, `outerHTML`, `insertAdjacentHTML` or `DOMParser` in `windows/src/companion/` or `windows/src/views/chat.ts`; `chat.ts` calls `parseMarkdown(` once.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Run:** `cd windows && npm run check:companion && npm run check:claude && npx --no-install tsc --noEmit` (the shared `levelChip` fixture still passes: the function is untouched; only the chip's call changes).

- [ ] **Step 5: Commit:** `feat(companion): F3a-tauri the Folder words and Markdown in replies`.

---

### Task 8: The bigger chat and the taller island window

**Agent: `nm-implementer-deep` (Sonnet 5.5, high; trigger 1).** The island's window is a fixed 720 × 320 transparent panel; the chat grows to 560 inside it, so the panel becomes 600 tall. What must not change: the area of the panel outside the island stays click-through on Windows (the cursor poll and `set_island_rect`) and on Linux (the input region), the wings and the outside click keep their rects, and nothing else in the island moves.

**Files:**
- Modify: `windows/src/core/layout.ts`, `windows/src-tauri/src/island.rs`, the existing tests that pin the chat's 300 cap or the panel's 320 (find them with `grep -rn "chatPromptHeight\|PANEL_H\|320" windows/scripts windows/src-tauri/src` and name each in the ledger)
- Create: `windows/scripts/companion-tests/size.test.mjs`

**Interfaces:**
- Produces: `chatPromptHeight(n)` = `Math.min(560, 300 + n * 40)` (the Mac's `ChatSizing`); `PANEL_H` = 600 in `layout.ts` and `600.0` in `island.rs`; a comment beside each naming the other.

- [ ] **Step 1: Write the failing test:** `size.test.mjs`: `chatPromptHeight` 0 → 300, 1 → 340, 6 → 540, 7 → 560, 100 → 560; `PANEL_H` read from `layout.ts` equals the number in `island.rs`'s `pub const PANEL_H: f64 = …;` and is at least 560 + 22 (the corner radius); every `VIEW_LAYOUTS` height fits in it.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, then read `island.rs` (`apply_geometry`, the cursor poll's fallback size), `lib.rs` `set_island_rect` and `platform/linux.rs`'s input-region code, and confirm in the ledger, with the line numbers, that click-through is decided by the island's rect and not by the panel's size. If any path uses the panel's size as the hit area, fix it to the island's rect and add a Rust test beside it.

- [ ] **Step 4: Run:** `cd windows && for s in companion cat projects sidekick; do npm run check:$s 2>&1 | grep "^ℹ fail"; done && npx --no-install tsc --noEmit`; `windows/scripts/cargo-linux.sh test -p notchmeow island:: pointer:: platform:: --offline --target-dir /repo/windows/target/f3a-tauri`; `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-f3a-tauri`. Then the dev server (`cd windows && npx --no-install vite --port 1422 --strictPort &`, PID saved) and `http://127.0.0.1:1422/?dev`: a screenshot of the chat at 0 and at 8 messages, looked at (the island ends where the numbers say; the cat stays where the prompt view puts it). Stop Vite by its PID.

- [ ] **Step 5: Commit:** `feat(companion): F3a-tauri a bigger chat: 300 to 560 px, the island window 600 tall`, `Co-Authored-By: Claude Sonnet 5.5`.

---

### Task 9: The pop-out window

**Agent: `nm-implementer-deep` (Sonnet 5.5, high; trigger 1).**

**Files:**
- Create: `windows/chat.html`, `windows/src/chatwin/main.ts`, `windows/scripts/companion-tests/chatwin.test.mjs`
- Modify: `windows/src/companion/link.ts` (`windowLink`), `windows/vite.config.ts`, `windows/src-tauri/src/lib.rs`, `windows/src-tauri/capabilities/default.json`, `windows/src/core/{bridge,state}.ts`, `windows/src/views/{chat,views}.ts`, `windows/src/island/island.ts`, `windows/src/main.ts`

**Interfaces:**
- Consumes: `buildPrompt(actions, onHeightChange, link)`, `ChatLink`, `TurnContext` (Task 5); `openConversation`, `saveCurrent`, `startNewChat` (Task 6); `POPPED_OUT_NOTE`, `BRING_BACK`, `MENU.popOut` (Task 7).
- Produces:
  - Rust (`lib.rs`): `fn create_chat_window(app: &AppHandle)` built like `create_settings_window` (label `chat`, `chat.html` through a `chat_page_url` like `settings_page_url`, title `Chat — NotchMeow`, 520 × 640, min 420 × 360, resizable, hidden, centred; `CloseRequested` → `prevent_close`, hide, `emit_to("island", "chat-window-hidden", ())`), called right after `            create_settings_window(&handle);`; commands `show_chat_window(app, conversation_id: Option<String>)` (show, unminimize, focus, then `emit_to("chat", "chat-window-open", { "conversationId": … })`, the id dropped unless `companion_store::is_id`), `hide_chat_window(app)` (hide and the same `chat-window-hidden`), `chat_relay(app, to: String, msg: serde_json::Value)` (`to` `island` or `chat`, else nothing; event `chat-msg`), with `logged_emit`. `capabilities/default.json` lists `"chat"` with the two existing windows. `vite.config.ts` input `chat: resolve(__dirname, "chat.html"),` after the `desktop` line.
  - `link.ts`: `export function windowLink(send: (msg: unknown) => void): ChatLink & { take(msg: unknown): void }` — `context()` and `approval()` return what the last `{kind: "context"}` message held (`{rightNow: "", quiet: false, mood: "idle"}` and `null` before any); `decide`, `release`, `session` send `{kind: "decide", decision, requestId}`, `{kind: "release", sessionId}`, `{kind: "session", id, retired}`.
  - `chatwin/main.ts`: boots settings (`Bridge.boot()`), listens to `settings-changed`, mounts `buildPrompt({ openSettingsWindow, openUrl, emote: () => {} }, () => {}, link)` full-window, listens to `chat-msg` (into `link.take`) and `chat-window-open` (`openConversation(bridgeStore, id, …)` or `startNewChat` when the id is null, then focus the field), and after every save sends `{kind: "current", id: State.chatId}` to the island. No timer, no listener beyond these.
  - Island: `State.chatPoppedOut = false`. The menu's Pop out (disabled while a reply streams): `saveCurrent`, `chatPoppedOut = true`, `Bridge.showChatWindow(State.chatId)`, `island.collapse()`. While `chatPoppedOut`: on `State.notify`, `Bridge.chatRelay("chat", {kind: "context", context: State.contextNow(), approval: State.chatApprovals.front})` only when it differs (as JSON) from the last one sent; the island's chat view shows only `POPPED_OUT_NOTE` and a `BRING_BACK` button (`Bridge.hideChatWindow()`); the chat tab's click also calls `Bridge.showChatWindow(State.chatId)`. `chat-msg` from the window: `decide` → `decideChatApproval`, `release` → `releaseChatApprovals`, `session` → the island link's `session`, `current` → `State.chatId = id`. `chat-window-hidden` → `chatPoppedOut = false`, then `openConversation(bridgeStore, State.chatId, islandLink(), bridgeChat)` when an id is set. A drop (`swallow`) while popped out calls `Bridge.hideChatWindow()` before its reset.

- [ ] **Step 1: Write the failing tests** (`chatwin.test.mjs`): `windowLink`'s defaults, then a `context` message is returned by `context()` and `approval()`, and `decide`/`release`/`session` send the three shapes; source pins (comment-blind): `lib.rs` builds the `chat` window once, before the island's page (`create_chat_window(&handle)` follows `create_settings_window(&handle)`), its `CloseRequested` handler calls `prevent_close`; `default.json` lists `chat`; `chatwin/main.ts` has no `setInterval`, `setTimeout` or `requestAnimationFrame`; `island.ts`'s `swallow` calls `hideChatWindow` before `Bridge.chatReset()` ("a drop while popped out hides the window before the reset"); the context relay is sent only while `chatPoppedOut`.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Run:** `cd windows && npm run check:companion && npm run check:claude && npx --no-install tsc --noEmit && npx --no-install vite build --config vite.config.ts --outDir "$(mktemp -d)" 2>&1 | tail -2` (the three pages build; the scratch folder goes to the Trash); `windows/scripts/cargo-linux.sh test -p notchmeow --offline --target-dir /repo/windows/target/f3a-tauri 2>&1 | grep "^test result"`; `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-f3a-tauri`. The dev server serves `chat.html`; a screenshot of it with a sample conversation (Task 11's `?sample=1` comes later: here, an empty chat is enough), looked at.

- [ ] **Step 5: Commit:** `feat(companion): F3a-tauri the chat pops out into its own window`, `Co-Authored-By: Claude Sonnet 5.5`.

---

### Task 10: Quick actions and the pasted screenshot

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Modify: `windows/src-tauri/src/ai/mod.rs` (`ai_quick`), `windows/src-tauri/src/files.rs` (`ingest_png_in`), `windows/src-tauri/src/lib.rs` (`ingest_png`, the invoke list), `windows/src/views/chat.ts`, `windows/src/core/{bridge,state}.ts`
- Create: `windows/src/companion/quick.ts`, `windows/scripts/companion-tests/quick.test.mjs`

**Interfaces:**
- Produces (Rust):
  - `ai_quick(app, shared, ai, feature: Feature, system: String, text: String, attachments: Vec<String>, on_event: Channel<AiEvent>)`: the same `begin_turn` gate and inbox check as `ai_chat`; `env.system = Some(system)`; `env.claude` = a new `Arc<Mutex<ClaudeChat>>` holding a default chat with the current `status` (Chat only, a new session id, never the chat's own); a local `Mutex<Conversation>`; `session::run_turn`. The chat's conversation and Claude session are untouched.
  - `files.rs`: `pub fn ingest_png_in(root: &Path, bytes: &[u8]) -> Result<DroppedFile, String>`: refused unless it starts with the PNG signature `89 50 4E 47 0D 0A 1A 0A` and is at most the drop's 25 MB cap (the constant `attachments::screen` uses); written as `inbox/screenshot.png`, `screenshot (2).png`… (the drop's naming); `pub fn ingest_png(bytes: &[u8])` on `settings::local_dir()`.
  - `lib.rs`: `#[tauri::command] async fn ingest_png(request: tauri::ipc::Request<'_>) -> Result<DroppedFile, String>` reading `InvokeBody::Raw` (anything else: `"That isn't a picture NotchMeow can read."`), through `blocking`.
- Produces (TS):
  - `companion/quick.ts`: `export interface QuickResult { kind: "fix" | "rewrite"; text: string; running: boolean; cut: boolean; note: string | null }`; `export function isImageName(name: string): boolean` (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, any case); `export function quickNote(e: { type: string; kind?: string; message?: string }): string` (`problem` with `kind === "cant_see"` → `QUICK_NO_VISION`, else the event's `message`).
  - `State.quickResult: QuickResult | null = null`. `Bridge.aiQuick(feature, system, text, attachments, onEvent)`, `Bridge.ingestPng(bytes: Uint8Array)` (`invoke("ingest_png", bytes)`).
  - `chat.ts`: the menu's Fix, Rewrite, Explain (enabled when the field is not empty, read when chosen). Fix/Rewrite: `quickRequest(kind, field, "pc")`; `null` → nothing; else `quickResult = {running: true, …}` and `Bridge.aiQuick("chat", r.system, r.user, [], …)` collecting `delta`s; on `done` the text through `quickResultClean`; an `error`/`problem` sets `note` by `quickNote`. The card above the field: `QUICK_TITLES[kind]`, the text (selectable), `CUT_NOTE` when `cut`, **Copy** (`Bridge.copyText`; false → note `Too long to copy.`) and ×. Explain: `saveCurrent`, `startNewChat`, push the user message with the field's text, `ask({ text: r.user, system: r.system, … })`. A `paste` event on the field whose `clipboardData` holds an `image/png` file: `Bridge.ingestPng(...)` → it becomes the waiting attachment and file chip, as a drop's copy does, without resetting the conversation. While the waiting attachment `isImageName`, a chip `SCREENSHOT_CHIP`: `startNewChat`, the user message `Explain this screenshot.` with that attachment, `ask({ feature: "files", text: r.user, attachments, system: r.system })` with `r = quickRequest("explainImage", "", "pc")`; a `cant_see` problem in that turn shows `QUICK_NO_VISION`.

- [ ] **Step 1: Write the failing tests.** Rust: in `files.rs`, `a_png_is_written_to_the_inbox_with_a_free_name`, `not_a_png_is_refused`, `over_the_cap_is_refused` (temp roots); in `ai/mod.rs` or `session.rs` tests, `a_quick_turn_leaves_the_chat_conversation_untouched` (run a quick turn against the local fake with a conversation of two turns held aside: still two turns, and `env.sent` line 0 is the quick system text). TS `quick.test.mjs`: `isImageName` rows; `quickNote` rows; wiring pins: `chat.ts` calls `quickRequest(` with `"pc"` three times (fix/rewrite, explain, explainImage); `Bridge.aiQuick(` is the only call for fix and rewrite; nothing in `companion/` or `chat.ts` reads `navigator.clipboard`.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Run:** `windows/scripts/cargo-linux.sh test -p notchmeow files:: ai:: --offline --target-dir /repo/windows/target/f3a-tauri`, `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-f3a-tauri`, `cd windows && npm run check:companion && npx --no-install tsc --noEmit`.

- [ ] **Step 5: Commit:** `feat(companion): F3a-tauri Fix, Rewrite, Explain, and Explain this screenshot`.

---

### Task 11: The `?dev` panel and the pictures, then owner checkpoint 1

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Create: `windows/src/companion/devcompanion.ts`, `windows/scripts/render-companion.sh`
- Modify: `windows/src/cat/dev.ts` (mount the panel after `  mountLinkDev(root, wrap);`), `windows/src/chatwin/main.ts` (`?sample=1` in the dev server only)

**Interfaces:**
- Produces: a `?dev` "Companion" panel: fill the chat with 0, 4, 8 or 14 sample messages (made-up words, one reply with a list, bold, code and a link), show the Conversations pane with six sample heads (two pinned), a running and a finished quick card, the screenshot chip, the Folder chip at each level (`C:\\dev\\notchmeow`), quiet on/off with a sample "Right now", the cloud line; and a "Prompt" box showing `systemFor(...)` for the current sample. Nothing of it exists outside `import.meta.env.DEV`. `render-companion.sh [--out DIR]` (the shape of `render-settings.sh`: a Vite on a free port, headless Chrome, a throwaway profile moved to the Trash, the PID stopped) writes `chat-0.png`, `chat-4.png`, `chat-8.png`, `chat-14.png`, `conversations.png`, `quick-running.png`, `quick-done.png`, `screenshot-chip.png`, `folder-read.png`, `folder-agent.png`, `cloud-line.png`, `popout.png` (`chat.html?sample=1` at 520 × 640), and `bash windows/scripts/render-settings.sh --page chat` stays the Settings picture.

- [ ] **Step 1: Implement and run:** `bash windows/scripts/render-companion.sh --out "${TMPDIR:-/tmp}/f3a-tauri-pictures"`. Open every PNG and say in one sentence each what it shows against what it should; a blank picture is a failed step.

- [ ] **Step 2: Commit:** `feat(companion): F3a-tauri the ?dev Companion panel and render-companion.sh`.

- [ ] **Step 3: Owner checkpoint 1.** Copy the PNGs to `.claude/checkpoints/f3a-tauri/` of the worktree (gitignored), ping the main session with `SendMessage`, and wait. What to look at: the chat heights (300 → 560) and that nothing else in the island moved; the menu and the Conversations pane; the quick card; the Folder chip's words; Markdown in a reply; the pop-out window; the prompt text in the panel (no "Mac", "Right now" as expected). Put to the owner: "Questions for the owner" below. A change the owner asks for is one task-sized fix with its review, before Task 12.

---

### Task 12: Settings → Companion, "Coming soon", drift with the Mac

**Agent: `nm-implementer` (Haiku 5.5, high).** **Precondition:** F3a-mac is on `main` and this branch is rebased or merged onto it (the controller does that and reruns Task 0 Step 2's Settings anchors).

**Files:**
- Create: `windows/src/settings/companion.ts`
- Modify: `windows/src/settings/{route,app,sidekicktab,sidekick,backend,devseed}.ts`, `windows/src/core/bridge.ts` (if `companionLastSent` needs a backend twin), `windows/src/companion/chrome.ts` (only to match the Mac), `tests/fixtures/settings/controls.json` (only the `winHomes`, `win` and `winPages` columns), `windows/scripts/settings-tests/{map,drift,pages,rules}.test.mjs`

**Interfaces:**
- Consumes: F3a-mac's `SettingsMap.swift` / `controls.json` Companion entries, `SettingsSidekick.swift`'s renamed chip constant, `CompanionChrome.swift`, `ChatSizing.swift`.
- Produces:
  - `route.ts`: `COMPANION_TAB_SHOWN = true`. `app.ts`: `case "companion": return companionTab({ settings: () => ctx.settings().companion, put: (next) => void ctx.save({ ...ctx.settings(), companion: next }), lastSent: () => ctx.backend.companionLastSent(), conversations: () => ctx.backend.companionCount(), deleteAll: () => ctx.backend.companionDeleteAll(), brain: async () => …the chat's resolution's model name… })` before the `default:` line.
  - `settings/companion.ts`: `export function companionTab(o): SettingsPage` built from the kit with the cards and rows of the Mac's relaunch Companion tab that exist on Windows/Linux, in the Mac's order and words (read them from the merged `CompanionSettingsView.swift`/`SettingsMap.swift`); at least: Humor (`select` Off · A little · More → `companion.humor`), See my sessions (`switchRow` → `companion.seeSessions`, with `help(sentTo(<brain>))`), Conversations (the count, Delete all behind a confirm), What the AI saw last (a button that shows `companion_last_sent`'s lines in a read-only, scrollable, selectable box, or `Nothing sent since NotchMeow started.`, with `Kept in memory only, gone when NotchMeow quits.`). A Mac row that is memory or recap (1.1) is not drawn here.
  - `sidekicktab.ts`: `COMES_WITH_F3A` becomes the Mac's constant name and value (`"Coming soon"`, spec owner's answer 1), every use in `settings/sidekick.ts` and the tests renamed with it.
  - `controls.json`: each F3a-mac Companion control gets `winHomes` (`chat` / `companion` / its card) and `win` (`{ "key": "companion.humor" | "companion.seeSessions", "store": "settings" }`, or `[]` for a control that stores nothing), `winPages`' `chat` tabs gain `"companion"`; a Mac-only control gets `"winHomes": [], "win": []`.
  - `map.test.mjs`: `FROZEN.settings` gains `"companion.humor", "companion.seeSessions"`; the source scan skips `companion` and checks `settings/companion.ts` writes only those two keys; the control count becomes 53 + the Mac's new controls. `drift.test.mjs`: the chip line reads the Mac's renamed constant; new lines pin `chrome.ts`'s `folderLabel` cases, `FOLDER_ROWS`, `POPPED_OUT_NOTE`, `QUICK_TITLES`, `CUT_NOTE` and `chatPromptHeight`'s 300/40/560 to `CompanionChrome.swift` and `ChatSizing.swift` (fix `chrome.ts` and `layout.ts` to the Mac's where they differ, and say so in the ledger). `windows-tests.yml` path filters gain `'NotchBuddy/Sources/App/Companion*.swift'` and `'NotchBuddy/Sources/App/ChatSizing.swift'` beside `'NotchBuddy/Sources/App/Settings*.swift'` (twice). `devseed.ts`: the sample backend answers the three new calls.

- [ ] **Step 1: Write the failing tests** (the map, drift and pages edits above, and in `pages.test.mjs` the four `COMES_WITH_F3A` patterns now on the new name, plus a `companion.ts` pin: it writes `companion.humor` and `companion.seeSessions` and no other `companion.` key).

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Run:** `cd windows && npm run check:settings && npm run check:companion && npx --no-install tsc --noEmit`; `bash scripts/test-settings-map.sh` (the Mac's map test still passes: only Windows columns changed); `bash windows/scripts/render-settings.sh --page chat --tab companion --out "${TMPDIR:-/tmp}/f3a-tauri-settings"` and the Sidekick tab, both themes, looked at (the chip reads "Coming soon").

- [ ] **Step 5: Commit:** `feat(companion): F3a-tauri Settings → Companion, Coming soon, the Mac's words pinned`.

---

### Task 13: Docs

**Agent: `nm-implementer-light` (Haiku 5.5, medium).**

**Files:** `CLAUDE.md` (one bullet after the "Sub-project F1 on Windows/Linux" bullet: the files of this plan, `check:companion`, the store paths, the pop-out's relay, what is absent: Services, clipboard reading, global shortcut, Replace, memory and recap until 1.1), `ARCHITECT.md` (the "Chat" flow's Windows line gains the companion prompt, the store and the pop-out window), `windows/README.md` (what differs from the Mac: no Services, quick actions on the field and a pasted image, no Replace), `docs/SPEC.md` (the French section on the chat, Windows/Linux paragraph).

- [ ] **Step 1: Write**, **Step 2:** `bash scripts/check-no-leftovers.sh | tail -1` → clean; **Step 3: Commit:** `docs(companion): F3a-tauri`.

---

### After Task 13: the whole-branch review

`nm-reviewer-deep` (Sonnet 5.5, high, trigger 4) with `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` (`model: sonnet`), skills `agent-security-hardening` and `security-review`, on `git diff "$(git merge-base HEAD main)"...HEAD`. Brief: the Global Constraints and Review Focus; the prompt-injection boundaries (stored files, clipboard images, model replies rendered as Markdown); what leaves the machine; the 0 % rule (no timer added, the relay only while shown); the store's file handling; the relay's message shapes on both sides; the restyle rule. Fixes are task-sized with their own review.

### Task 14: Owner checkpoint 2: the real machines

The main session and the owner, on a Windows PC and a Linux desktop (X11, and Wayland for the pop-out): an install build; the chat with a cloud key, a local model and the Claude plan (Folder at each level, an Agent approval answered from the pop-out); a stored conversation reopened after a restart; Fix and Rewrite on pasted text; Win+Shift+S then Ctrl+V and "Explain this screenshot"; the island taller but still click-through below; Task Manager or `top` showing no CPU while the island is hidden and the pop-out hidden. The Windows-only Rust is linked and run by `windows-tests.yml` on the branch's CI run, read before the merge.

---

## Plan calls

- **PC words come from the core,** not from a string replace in the app (Task 1).
- **No account name in the prompt** on Windows/Linux ("the user's"); the Mac reads its first name.
- **Conversation files** follow the spec's folders: `%APPDATA%\NotchMeow\companion\` on Windows, the app's existing `~/.local/share/notchmeow/companion/` on Linux (the spec writes `NotchMeow`; the Linux folder has always been lower case).
- **Rust writes the files and the page cleans the records:** no Rust twin of `conversationClean`; Rust checks the id, the size, links and owner-only writes.
- **"What the AI saw last" is recorded by Rust** from the request it built (text parts only), so it covers the pop-out window and quick calls without a relay; for the Claude plan the same text rides the preamble.
- **The pop-out owns the chat while shown;** the island's cat does not show "thinking" for a reply streaming there; a drop on the island while popped out hides the window first.
- **Explain** opens a new conversation whose first turn uses the explain prompt (the Mac's call); **Fix and Rewrite** are one throwaway call with a card, no Replace.
- **No migration** (call 3): nothing is stored on Windows/Linux today.

## Questions for the owner

1. **PC words in the shared prompt.** The contract's prompt tells the model it lives "in the notch of the user's Mac" and "cannot act on the Mac yet"; the quick prompts say "on their Mac". Task 1 adds a `device: 'pc'` word set to `shared/companion-core.js`, by addition ("lives at the top of the user's screen", "this computer"), so the Mac's rows and port do not change. **Recommended: yes.** Without it the Windows/Linux companion would call the PC a Mac.
2. **No clipboard reading on Windows/Linux.** The Mac's menu acts on the field, else on the clipboard. Here the quick actions act on the field only, and a screenshot comes in by Ctrl+V into the field (or a drop): the paste is the user's own gesture, needs no clipboard API and no permission prompt, and covers Win+Shift+S. **Recommended: field and paste only.** The alternative is a native clipboard read in Rust per platform (Win32 and GTK), about half a day more.
3. **Markdown in replies.** The contract's conduct line asks every brain for light Markdown; the Windows/Linux chat shows replies as plain text today, so the user would see raw `**` and backticks. Task 7 adds a small renderer (paragraphs, lists, bold, italic, code, `http(s)` links; never HTML). This changes how a reply looks in the chat view only. **Recommended: yes** (the Mac renders it).
4. **The pop-out window** is made hidden at launch and kept (WebView2 shows a blank window when one is made later in this app), costs memory but no CPU while hidden, and owns the chat while shown; the island's chat tab brings it forward. **Recommended: as planned.** The alternative, a window made on demand, needs the WebView2 problem solved first.
5. **Order with the Mac.** Tasks 0–11 run beside F3a-mac; Task 12 (Settings and the shared control map) waits until F3a-mac is merged, because the map and the drift pins are shared. If F3a-mac slips past about 2026-11-07, **recommended:** ship Task 12 with this plan's words and the Mac pins added by whichever plan merges second.

## Dry run

- **Checked on `main` at `9c439961`:** every Task 0 anchor occurs exactly once (`'scripts/gen-projects-ts.mjs'` twice in `windows-tests.yml`, by design); `TurnRequest` has eleven literals, so the system text goes on `Env` (three literals) instead; `ai_chat` resets nothing and the conversation lives in Rust (`AiState.reset`, `chat_reset`), so stored conversations reseed it with `ai_load_turns`; `ClaudeChat::reset` leaves a fresh session with no recap, hence `Session::reseed`; `claude_code::user_line(parts, preamble)` already puts a preamble first, so the companion text rides it and E3's arguments stay; `ai_oneshot` is local-only and 1,200 characters, so quick calls need `ai_quick`; `copy_text` allows 32 KB, enough for 8,000 code points; `create_settings_window`'s comment is why the pop-out is made at launch; `capabilities/default.json` lists windows by label; the island panel is 720 × 320 in both languages and the question card does not grow on Windows (so the chat is the first view above 320); `ProjectsModel.frame` moves the layout and the big card, so the companion reads a new side-effect-free `view()`; `State.attentionNeeded` covers a notch card, a chat card and a waiting pill; `settings-changed` is broadcast to every window; `levelChip` is pinned by `tests/fixtures/ai/claude-code/labels.json`, so the Folder words are a new function and `levelChip` stays; `drift.test.mjs` pins `COMES_WITH_F3A` to `SettingsSidekick.swift` and `controls.json` is checked field by field by the Mac, so Task 12 waits for F3a-mac.
- **Not on `main` yet:** `shared/companion-core.js` and its fixtures (F3a-0); the plan uses the names of its "Interface for the app plans" table and Task 0 checks five of them. F3a-mac's Swift names (Task 12) are read from the merged code, not assumed.

## Owner's answers and rulings, 2026-10-22
- **Owner's answers:** all five questions as recommended. (1) A `device: 'pc'` set of words in `shared/companion-core.js` as new fixture groups the Mac never reads. (2) Quick actions on the message field only; screenshots by paste or drop; no clipboard reading. (3) A small Markdown renderer that never uses HTML. (4) The pop-out window is created hidden at launch and kept. (5) If F3a-mac slips past about 2026-11-07, Task 12 ships with this plan's words and whichever plan merges second adds the drift pins.
- **Ruling (main session): "Coming soon" belongs to F3a-mac's Task 9**, which changes the Mac and the four Windows lines together because `drift.test.mjs` pins them. Task 12 here only checks that the rename is present (and does it only if F3a-mac has not merged by then, under answer 5).
