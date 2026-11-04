# G1-tauri The Shelf Implementation Plan (Windows and Linux)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows/Linux Tauri app gets sub-project G1, shelf and send. While files are dragged over the open island it splits into **Ask** (left: today's drop, unchanged) and **Shelf** (right: a tray). A Shelf drop keeps up to 30 files on a shelf (as paths, newest first; the desktop cat is not waited for and does not fly in). A new shelf view shows them, and opens from a Shelf drop, from a tray item and from a small count at the right end of the compact island. Each tile can **Ask** (the file goes to the chat like a drop on Ask), **Send** (the Windows Share window), **Show in folder**, **Remove**, and be **dragged out** of the island into any folder, mail window or chat with the system's own drag. The plan starts with a **spike** of that native drag source (Windows OLE, Linux GTK), and states its fallback below.

**Architecture:** Rust owns the shelf. `src-tauri/src/shelf.rs` is the Rust twin of the shelf contract (it replays `tests/fixtures/shelf/`) and the store: `shelf.json` in the app's data folder (at most 30, a backup of an unreadable or trimmed file before it is overwritten), copies under `shelf/<id>/` where an item has one, and an existence check only when the shelf is listed. **The page holds ids and never a path:** every command that touches a file takes an id (only a drop brings paths in). The page keeps the list (`shelf/store.ts`, `State.shelf`) and a TypeScript port of the contract (`shelf/rules.ts`: `zoneAt`, `shelfClean`, `shelfAdd`, `readShelf`) that decides the half and runs the in-memory shelf of the browser and of `?dev`. The two halves are a **layer over today's drop canvas** (`shelf/zones.ts`), which is not touched; a Shelf drop is a second branch of the island's drop handler. Drag out (`dragout.rs` with `platform/windows/drag.rs` and `platform/linux/drag.rs`), Send (`platform/windows/share.rs`) and Show in folder (`platform::reveal_file`) are native, and the boot info says what a system can do.

**Tech Stack:** TypeScript 5 and Vite 6 (already in `windows/`), Node 22 (`node --test` reading the TypeScript source with `--experimental-strip-types`), Rust with `serde_json`, Tauri 2, `gtk` 0.18 and the `windows` crate 0.61 (more of its features), `playwright-cli` (headless Chromium, for the pictures only). **One new direct dependency, for the owner to approve** (Open question 1): `windows-collections = "0.2"`, which is already in `Cargo.lock` as a dependency of the `windows` crate and is needed only to hand the Windows Share window a list of files. No new npm package.

**Spec:** `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`, revision 2, sub-project G1 only (G2 is another round). The contract is merged (G1-0, `42af43d`): `docs/SHELF-CONTRACT.md` and `tests/fixtures/shelf/` (`zone-cases.json`, `shelf-cases.json`, `reference.py`, which decides when this plan's code and a fixture disagree). The format and the conventions are the last Windows plans': `docs/superpowers/plans/2026-10-12-h-tauri-desktop-cat.md`, and the controller brief's `docs/superpowers/plans/2026-10-13-fixes-after-h.md`. The Mac twin (G1-mac) is its own plan.

**Base:** branch `g1/tauri-shelf`, in a git worktree, from `notchmeow/rebrand` **at `619b407` or later** (G1-0 is merged, `42af43d`, and so are the desktop cat, the file catch and the fixes after H: the Setup block checks `git merge-base --is-ancestor 42af43d HEAD`). Nothing is pushed.

## The spike and its fallback (read first)

Dragging a file out of the island cannot be done by the page: Tauri's drag-and-drop setting, which the island needs to receive files, turns the webview's own drag off. So Task 1 is the owner-approved **spike** (owner's answer 3, 2026-10-14): a native drag source, started from the island, written for both systems.

- **Windows:** OLE `DoDragDrop` with a shell data object that holds the files and a drop source that follows the left button (`platform/windows/drag.rs`).
- **Linux:** a GTK drag source with a `text/uri-list` (`platform/linux/drag.rs`). Wayland is the known risk: a compositor may refuse a drag that does not come from the press that started it.

**What the session can prove, and what it cannot.** The session writes both and compiles the Linux one with `cargo-linux.sh check` when Docker is up. Nothing the session can run compiles the Windows one (the container is Linux): that is `windows-tests.yml` on the owner's next pull request. And whether a drag really leaves the island on a real machine only a person can see. So the spike ends in **Checkpoint 0**: a ping to the main session with the compile result and the five-step check below. **The plan does not wait for the answer:** Tasks 2 to 7 do not depend on it, and Task 8 builds the shelf's drag behind the boot info's `shelf.dragOut`, which is `dragout::supported()`.

**The fallback, one line per system** (in `windows/src-tauri/src/dragout.rs`): `pub const WINDOWS: bool = true;` and `pub const LINUX: bool = true;`. If the real-machine check fails on a system, that system's constant goes to `false` and **that system ships without drag out**, keeping Ask, Send and Show in folder (Linux has no Send anyway: Ask and Show in folder). The tiles are still ticked by a click, the tests accept either value, and Task 10 has the exact README edit. If the owner answered before Task 8, the controller applies the fallback in Task 8's commit; if not, both stay `true` and the owner's real-build checklist decides.

**The five-step check** (Checkpoint 0; on a Windows PC and on a Linux machine, any compositor):

1. `cd windows && npm run tauri dev` (a Debug build).
2. A small green tab, **drag test file**, sits in the middle of the compact island. Press it and move the pointer.
3. Drop it on the desktop, in a folder window and on a mail or chat window. A file `NotchMeow drag test.txt` arrives as a copy, the tab says `drag: copied`, and the original in `%LOCALAPPDATA%\NotchMeow\spike\` (Linux: `~/.local/share/notchmeow/spike/`) is untouched.
4. Press Esc in the middle of a drag: the tab says `drag: cancelled`.
5. Drop the tab back on the island: nothing opens, no drop view.

Report: works, refused (and which compositor, Wayland or X11) or crashed.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and the contract; a line marked "(plan decision)" is a choice this plan makes where the spec is silent, and is listed again under "Open questions for the owner".

- **Frozen IDs and contract strings.** Cat IDs, pill IDs, display mode IDs, the desktop size IDs, `nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent` are untouched. The shelf's view ID is `shelf` and its tray item ID is `shelf` (new, frozen from now on).
- **The shelf contract (`docs/SHELF-CONTRACT.md`).** At most **30** items, newest first. Items past 30 are refused with a short note and **nothing old is removed silently**; the one exception is on the read side (a hand-edited or damaged `shelf.json` keeps the 30 newest). The half is `zoneAt(x, width)`: the centre line is **Ask**, the right half **Shelf**, outside the island is null. An unreadable `shelf.json` is an empty shelf and **a backup copy of the unreadable file is kept before a new one is written**. An item is `{id, name, size, folder, copy, link?, addedAt}`; a copy lives in `shelf/<id>/<name>`; originals are never touched.
- **The half is decided by the pointer's position at release** (spec). On Windows that is the last polled cursor position; on Linux/Wayland, which has no global cursor, the drag event's own `position` (plan decision: the spec says the event carries paths only, but Tauri 2.12's `enter`, `over` and `drop` payloads carry the pointer's position too).
- **Ask is unchanged** (spec, "the Ask half is today's canvas"): a drop on Ask takes the first file only, the cat catches it, the desktop cat waits its turn. **A drop on Shelf** takes every file, takes a fresh drop token (a waiting Ask drop never runs), clears the file alert, stops the upload sequence, does not wait for the desktop cat and plays no new motion.
- **Never restyle what ships.** No existing view, canvas, header button or CSS rule changes: `src/upload/*`, `src/views/upload.ts` and `src/views/icons.ts` are not edited, and `src/style.css` only gains lines. The shelf is a new view, a layer over the drop canvas and a badge, all in the island's style.
- **The page holds ids, never paths.** `shelf_remove`, `shelf_ask`, `shelf_drag_out`, `shelf_reveal` and `shelf_send` take ids, `shelf_list` and `shelf_clear` take nothing, and only `shelf_add` takes paths (a drop's). The page never learns a link.
- **No telemetry. The log says only that a send started** (`shelf send started`), never a name, a path, an id or a recipient. The OS share window keeps its recipients private from NotchMeow.
- **0 % CPU when the island is hidden. Nothing here adds a timer, a poll or a watcher.** Whether the originals still exist is looked at only when the shelf is listed (it opens). The badge is a function of the island's mode: it never opens, reveals or expands the island and never keeps one visible. The only timers are one-shot: the 15 s hold after a Send.
- **No global shortcut on Windows and Linux** (spec: the `shelf` shortcut is the Mac's).
- **No new third-party code** except `windows-collections 0.2` (Open question 1); no new npm package.
- **Rust runs only through `windows/scripts/cargo-linux.sh`, with `--target-dir /repo/windows/target/g1-tauri`, and never builds or pulls the Docker image.** Windows-only Rust is not compiled by anything the session can run; it is owed to CI.
- **Models and commits** (CLAUDE.md, 2026-10-12): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local, lists only the files its task names, and ends with the `Co-Authored-By` line of the model that did the task: `Claude Haiku 5.5 <noreply@anthropic.com>` for `nm-implementer-light` and `nm-implementer`, `Claude Sonnet 5.5 <noreply@anthropic.com>` for `nm-implementer-deep`. Never push.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app, and never start the Tauri app (`npm run tauri dev`, a built `notchmeow.exe`): the owner runs it. Serving the front end with `npx --no-install vite` and looking at it in the headless `playwright-cli` browser is allowed, and only that.
  2. Install nothing, download nothing, use no network except `127.0.0.1`, and never run `docker build` or `docker pull`. If `docker image inspect notchmeow-linux-dev` fails or the daemon is down, say so: the Rust steps are owed, and the TypeScript tasks go on.
  3. Use `trash`, never `rm -rf`. Pictures and one-off scripts go in `.claude/checkpoints/g1-tauri/` (gitignored). Stop the dev server by its saved PID only, close browsers by session name (`playwright-cli -s=<name> close`), never `close-all`, and run `playwright-cli` from `.claude/checkpoints/g1-tauri/` with the default `TMPDIR`.
  4. Never edit `design/prototype/cat-core.js`, anything under `tests/`, `shared/theme.json`, `NotchBuddy/`, `windows/src/upload/`, `windows/src/views/upload.ts`, `windows/src/views/icons.ts`, `windows/src/theme.generated.*` or the Mac's files. `windows/src/style.css` only gains lines.
  5. Never read, print or write the real `~/.claude`, `%USERPROFILE%\.claude` or the owner's own folders; the tests make their own temporary folders.
  6. If a step's find text occurs zero or two times, or a command is refused, stop and report: do not look for another way.
  7. Haiku 5.5 for every task except the two the table below names; never Opus or Fable.

## Review Focus

The spec says what the shelf does. It is silent on these inputs, each of which would bite a person first (most likely first). Each names the test that pins it.

1. **A drop at the centre line, outside the island, on a screen with another scale, or where there is no global cursor.** Expected: the centre line is Ask (today's drop); outside both halves is Ask's; on Linux the half comes from the event's position in physical pixels divided by the page's scale; a missing or non-finite position never throws. Tests: Task 2 (`zoneAt` against 34 fixture rows), Task 5 (`shelf-dropflow.test.mjs`: the pointer's x on both systems, the plan for a drop).
2. **A Shelf drop while the desktop cat is out or flying, or while an Ask drop is still waiting for it or copying.** Expected: the shelf does not wait, the cat goes back by its normal rule, the waiting Ask drop never runs and never clears the new alert, an Ask copy still in flight shows no note over the shelf. Tests: Task 5 (`shelf-drop.test.mjs`, the browser run with the island's drop handler).
3. **A damaged, hand-edited or hostile `shelf.json`** (a lone surrogate, a byte order mark, text after the value, 10 000 nested lists, 300 items, a repeated id, a name `CON.txt`). Expected: the other items stay, an unreadable file is an empty shelf **and is kept as `shelf.json.bad-<time>` before it is overwritten**, the 30 newest stay. Tests: Task 3 (the 132 + 30 + 18 fixture rows through Rust, `a_lone_surrogate_costs_one_item_not_the_shelf`, `an_unreadable_or_trimmed_file_is_kept_as_a_backup`).
4. **Files that cannot be shelved or are shelved twice**: a relative path, a path that is gone, a name the contract refuses (a trailing dot, a zero-width character), a folder, the same file dropped twice, 32 files in one drop. Expected: one word per path (`added`, `duplicate`, `full`, `invalid`), nothing already shelved removed, a note for what was left off, a folder shelved as a link and never offered to Ask. Tests: Task 3 (`adding_files_keeps_them_in_the_order_dropped...`), Task 4 (`shelfNote`, `canAsk`).
5. **An item dragged out and dropped back on the island, a missing original, Escape in the middle of a drag, two drags in a row.** Expected: the item is not added twice and the drop view does not open (during the drag and for 600 ms after it), a missing file is not dragged and has only Remove, a second drag does not start while one runs. Tests: Task 8 (`DragOutGuard`), Task 6 (a missing tile), Task 3 (`resolve` leaves out a file that is gone).

---
## File Structure

All paths are under `windows/` unless they say otherwise.

| Path | Responsibility |
|---|---|
| `src/shelf/rules.ts` | New. The contract's three rules and `readShelf`: `zoneAt`, `shelfClean`, `shelfAdd`, `readShelf`, the constants and the types. Pure. |
| `src-tauri/src/shelf.rs` | New. The Rust twin of `shelfClean`, `shelfAdd` and `readShelf` (replays `shelf-cases.json`), and the store: `shelf.json`, copies, the backup, the 30 cap, `Entry` (what the page gets: no link, and `missing`). Std and `serde_json` only. |
| `src/shelf/store.ts`, `src/shelf/backend.ts` | New. The page's shelf (`ShelfStore`: the list, the ticks, the note, `targets`, `canAsk`), `shelfNote`, `sizeLabel`; the two backends: Rust's commands, and an in-memory shelf that runs the contract's rules (the browser and `?dev`). |
| `src/shelf/dropflow.ts`, `src/shelf/zones.ts`, `src/shelf/icons.ts` | New. Which half a drop landed in and what it does (pure); the Ask and Shelf halves as a layer over the drop canvas; the shelf's own icons. |
| `src/views/shelf.ts` | New. The shelf view: tiles, buttons, ticks, press-or-drag. |
| `src/shelf/badge.ts`, `src/shelf/dragguard.ts`, `src/shelf/devshelf.ts`, `src/shelf/dragspike.ts` | New. The compact badge's rule (pure); the guard around a drag out (pure); the `?dev` panel; the spike's tab (dev server only). |
| `src-tauri/src/dragout.rs`, `src-tauri/src/platform/windows/drag.rs`, `src-tauri/src/platform/linux/drag.rs`, `src-tauri/src/platform/windows/share.rs` | New. The native drag source and its fallback switches, `file_uri`, `show_items_args`; the OLE drag (Windows); the GTK drag (Linux); the Windows Share window. |
| `src/core/state.ts`, `src/core/layout.ts`, `src/core/bridge.ts`, `src/views/views.ts`, `src/island/island.ts`, `src/main.ts`, `src/cat/dev.ts`, `src/style.css` | Changed, additively: `State.shelf`, `shelfCaps`, `dropZone`; the `shelf` view and its place; the shelf commands, the boot info's `shelf`; `ViewActions.shelf`; the drop handler's two branches, the badge, `openShelf`, `askShelf`, the drag out, Send and Show actions; the tray case; the Shelf panel; new rules at the end of the style sheet. |
| `src-tauri/src/lib.rs`, `src-tauri/src/tray.rs`, `src-tauri/src/platform/mod.rs`, `src-tauri/src/platform/windows.rs`, `src-tauri/src/platform/linux.rs`, `src-tauri/Cargo.toml`, `Cargo.lock` | Changed: the shelf commands and the spike command, the boot info's `shelf`, the tray's Shelf item, `DragDone`, `drag_out`, `share_files`, `reveal_file`, `SHARE`; the `windows` features and `windows-collections`. |
| `scripts/cat-tests/shelf-*.test.mjs` | New: `rules`, `store`, `dropflow`, `drop`, `view`, `badge`, `dragout`, `send`, `commands`. |
| `README.md`, `../CLAUDE.md`, `../ARCHITECT.md`, `../docs/SHELF-CONTRACT.md`, `../.github/workflows/windows-tests.yml` | The docs and the CI path filter, in Task 10. |

**Staged edits.** Most tasks edit files earlier tasks created or changed. Every edit below is a Python script whose replacements assert that the find text occurs exactly once; the text is what the tree has after the tasks before it. Run each script from the repository root, as it is. If a find text occurs zero or two times, stop and report: the tree is not what the plan expects.

## Tasks and agents

`CLAUDE.md`: Haiku 5.5 first, Sonnet 5.5 only on a named trigger. **Tasks 1 and 9 are `nm-implementer-deep` (Sonnet 5.5, high), trigger 1** (platform APIs the task must design, not copy): Task 1 is the spike of the native drag source (OLE and GTK, threads and a modal loop); Task 9 is the Windows Share window opened from a window that never takes focus (the spec asks for a short spike of both the picker and the Share window) and the Linux file-manager call. Tasks 2 and 4 give every line of their code: `nm-implementer-light` (Haiku 5.5, medium). Tasks 3, 5, 6, 7 and 8 are multi-file with their code given, some run a browser or Docker: `nm-implementer` (Haiku 5.5, high). Task 10 is docs and checks: `nm-implementer-light`. Each task is then reviewed by `nm-reviewer` (Haiku 5.5, high), and the whole branch by `nm-reviewer-deep` (Sonnet 5.5, high) after Checkpoint 2. If a step's expected output differs and the cause is not obvious (a Rust compile error, a layout that overlaps), hand that task to `nm-implementer-deep` (trigger 2); a task Haiku has failed twice goes there too.

| # | Task | Agent | Model | Review |
|---|---|---|---|---|
| 1 | **Spike:** a native file drag source (Windows OLE, Linux GTK `text/uri-list`), the fallback switches, a Debug trigger | `nm-implementer-deep` (trigger 1) | Sonnet 5.5 | `nm-reviewer` |
| | **Checkpoint 0:** a ping with the compile result and the five-step check (the plan goes on) | the executing session | | |
| 2 | The contract's rules in TypeScript (replays both fixtures) | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 3 | The Rust twin and the store: `shelf.rs`, the commands (replays `shelf-cases.json`) | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 4 | The page's shelf: store, backends, the bridge, `State.shelf` | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 5 | The Ask and Shelf halves as a layer over today's drop, and the Shelf drop path | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 6 | The shelf view, the `shelf` view plumbing and the `?dev` Shelf panel | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 1:** the owner looks at the pictures from the `?dev` page and the dev island | the executing session | | |
| 7 | The tray item, the compact badge, Ask from a tile | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 8 | Drag out in the shelf: the guard, `shelf_drag_out`, the boot info | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 9 | Send (Windows Share) and Show in folder (Explorer, the file manager) | `nm-implementer-deep` (trigger 1) | Sonnet 5.5 | `nm-reviewer` |
| 10 | The docs, the CI path filter and the final checks | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 2:** the owner signs off | the executing session | | |
| Final | Whole-branch review | `nm-reviewer-deep` (trigger 4) | Sonnet 5.5 | none |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; `nm-implementer-deep` also `superpowers:systematic-debugging`. Reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Ponytail never cuts what this plan or the spec asks for, nor tests, security or privacy rules. The agents of Tasks 5, 6 and 7 also load `playwright-cli`.

## Execution

**One worktree chat session** runs the whole plan: branch `g1/tauri-shelf`, model **Haiku 5.5 at high effort** (the controller; the two Sonnet tasks are subagents with a named trigger). It runs on a base where **G1-0 is merged** (`42af43d`). It touches the island's drop path (`island.ts`) and `windows/src/` broadly, so it should not run beside another plan that does (G1-mac touches only `NotchBuddy/`, and can run in parallel). Nothing is pushed. The session never starts the Tauri app: the owner's real-build checks are listed at the end.

**The session is started in three steps** (`ARCHITECT.md`):

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run the Setup block of `docs/superpowers/plans/2026-10-14-g1-tauri-shelf.md`. If any check in it fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, that plan, `docs/SHELF-CONTRACT.md` and `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md` (revision 2, G1 only). Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief below as the next message.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-14-g1-tauri-shelf.md` with `superpowers:subagent-driven-development`, task by task, on branch `g1/tauri-shelf`. Do its Setup first. Dispatch each task to the agent and model the plan's "Tasks and agents" table names (Haiku 5.5 first; Sonnet 5.5 only for the two tasks the table marks trigger 1, or for a task Haiku failed twice, and then the trigger goes in the ledger; never Opus or Fable), then to `nm-reviewer`; fix what the review finds before the next task. These rules hold for you and for every brief you write:
>
> 1. **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this session's worktree and the second `g1/tauri-shelf`. If either differs, stop and report. Commit with `git commit -F -`, the message on stdin, ending with the `Co-Authored-By` line of the model that did the task. **Never push.**
> 2. **The ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-g1-tauri-shelf/progress.md`: one line per task with its status, its commit, the test counts it printed, the model and agent that ran it, the trigger if it was `nm-implementer-deep`, and what the review found and how it was fixed. Write it after every step that changes a status.
> 3. **Briefs are task-sized.** A subagent gets one task: its text from the plan, the Global Constraints, the SUBAGENT RULES block, the files to read and the exact commands. Never hand it the whole plan.
> 4. **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots) restricted to the task's files, never two-dot, and the task's own text.
> 5. **Shell.** Every shell block you write or edit passes `bash -n` first. Stop the dev server by its saved PID only (`kill "$(cat .claude/checkpoints/g1-tauri/vite.pid)"`), never `kill $(lsof ...)`. Close `playwright-cli` browsers by session name, never `close-all`. Run `playwright-cli` with the default `TMPDIR`, from `.claude/checkpoints/g1-tauri/`.
> 6. **Never** launch, quit or replace a NotchMeow app or start the Tauri app; install, download or build a Docker image (if `docker image inspect notchmeow-linux-dev` fails or the daemon is down, say so: the Rust steps are owed, and the TypeScript tasks go on); use the network; or use `rm -rf` (use `trash`). Rust only through `windows/scripts/cargo-linux.sh` with `--target-dir /repo/windows/target/g1-tauri`.
> 7. **Refusals and failures.** If any command is refused by a permission prompt, or a find text in a staged edit occurs zero or two times, stop and report. Do not look for another way.
> 8. **Ping the main session.** Its `ListAgents` name is `NotchMeow — fork research & cat design`. At **Checkpoint 0** (after Task 1), **Checkpoint 1**, **Checkpoint 2**, at the end, and whenever you stop (a refusal, a failed check, a question), send your report to that name with `SendMessage`, as well as writing it in your own chat, so the main session can double-check the work (its own clone, merge and full checks) before anything reaches the owner.
> 9. **Checkpoints.** Run Task 1, then **Checkpoint 0: ping and go on** (it does not wait). Run Tasks 2 to 6, then stop for **Checkpoint 1**: copy the pictures into `.claude/checkpoints/g1-tauri/` (the list is under the checkpoint), send the owner their paths and the list, and wait. After the owner's reply run Tasks 7 to 10 and stop for **Checkpoint 2**; after the owner's OK dispatch `nm-reviewer-deep` over the whole branch. Never start the next stage before the owner's reply.
> 10. **Report:** the commits; for `windows/`: `npx --no-install tsc --noEmit`, `npm run check:cat`, `npm run check:ai`, `npm run check:claude`, and the `cargo test --workspace` and `cargo check` counts (or that the image was missing); the output of `bash scripts/test-shelf-contract.sh` and `bash scripts/test-cat-contract.sh`; the pictures of the checkpoints; the Windows `cargo check` and a release build (owed to CI); the spike's result; and anything you could not settle.

## Setup (the controller, once)

- [ ] Put the session's worktree on the plan's branch, check that G1-0 is merged and that the base has what the plan reads, and copy the main checkout's front-end packages. This plan adds no npm package, so nothing is downloaded: no `npm install` or `npm ci`. `cp -c` makes an APFS clone, which is instant. It must be a real folder, not a symlink, because `.gitignore` ignores `/windows/node_modules` as a folder.

```bash
git status                                   # must be clean
git switch -c g1/tauri-shelf notchmeow/rebrand
git merge-base --is-ancestor 42af43d HEAD && echo "G1-0 is merged (42af43d)"   # if this prints nothing, stop
git log --oneline -3
git ls-files tests/fixtures/shelf/shelf-cases.json tests/fixtures/shelf/zone-cases.json docs/SHELF-CONTRACT.md docs/superpowers/plans/2026-10-14-g1-tauri-shelf.md
git rev-parse --show-toplevel; git branch --show-current
cp -cR "/path/to/notchmeow/windows/node_modules" windows/node_modules
git status --short                           # still empty: the copy is ignored
mkdir -p .claude/checkpoints/g1-tauri .superpowers/sdd/2026-10-14-g1-tauri-shelf
cd windows && node --version                 # 22.6 or newer
```

`G1-0 is merged (42af43d)` must print, and so must the four paths (if a fixture is missing G1-0 is not merged: stop; if the plan's own path prints nothing, the plan is not committed on this branch: stop).

- [ ] Check that the contract is the one this plan was written against, and that the starting point is green.

```bash
bash scripts/test-shelf-contract.sh 2>&1 | tail -3
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1
(cd .. && bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two generator")
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && echo "image ok" || echo "image missing or the daemon is down: the Rust steps are owed"
cd ..
```

Expected: `all shelf contract checks passed`, `✓ shelf-cases.json matches build_cases.py`, `✓ zone-cases.json matches build_cases.py`, `tsc exit 0` with no type error before it, `ℹ tests 372`, `ℹ pass 372`, `ℹ fail 0`, `All AI UI checks passed`, `All Claude Code UI checks passed`, `# tests 319`, `# pass 319`, `# fail 0`, `✓ 16 fixture files match cat-core.js`, `✓ two generator runs write identical bytes` and `image ok`. If `image ok` does not print, **do not build the image**: do the TypeScript tasks only and report that the Rust steps (Tasks 1, 3, 8 and 9) are owed. Their code is complete either way, and CI's `windows-tests.yml` runs `cargo test` (Windows) when the owner pushes.

## How to run this plan

**Blocks.** A code step is a `bash` block: either a file written with `cat > path <<'EOF'` (the file's exact content, from the repository root), or a Python script whose `edit` helper replaces text that must occur exactly once in the file it names, or a plain command. Run each block from the repository root, as it is. Never type a block from memory and never "improve" one. A `Run:` block's `Expected:` line says what it prints (every backticked literal must appear). A `Run:` block that starts with `cd windows` ends in `cd ..` and came back. URLs with a `?` are quoted, because the shell would read the `?` as a wildcard.

**Red first.** Each task writes its tests, runs them to see them fail, writes the code, and runs them to see them pass. A "prove it bites" step changes one line with the given helper, runs the tests, and puts the line back (the helper restores the file itself): it is never committed.

**Pixels.** There are no pixel tests. The look is checked by eye in a headless browser (`playwright-cli`, with Vite alone, never the Tauri app). Keep every picture in `.claude/checkpoints/g1-tauri/` and say what you saw. **What no test program and no headless browser can show** is what the owner's real-build checks at the end are for (a drag that leaves the window, the Share window, the file manager, click-through on both systems, a second monitor); never claim them.

**Starting and stopping the dev server** (Tasks 5, 6 and 7 use it; port 14631, so that it never meets another worktree's):

```bash
mkdir -p .claude/checkpoints/g1-tauri
cd windows
(npx --no-install vite --port 14631 --strictPort > ../.claude/checkpoints/g1-tauri/vite.log 2>&1 & echo $! > ../.claude/checkpoints/g1-tauri/vite.pid)
sleep 3
cd ..
tail -3 .claude/checkpoints/g1-tauri/vite.log
```

Expected: `VITE v6` and `http://127.0.0.1:14631/`. If it says the port is in use, another session has it: pick another port in `14631` to `14699` and use it everywhere below. When a task is done with it: `kill "$(cat .claude/checkpoints/g1-tauri/vite.pid)"` (nothing else) and, for each session it opened, `playwright-cli -s=<name> close`.

---

**The "prove it bites" helper** (written once, here; every proof step below calls it). It changes one line, runs the given test files, prints the pass and fail counts and puts the file back; it refuses a change whose find text does not occur exactly once.

```bash
mkdir -p .claude/checkpoints/g1-tauri
cat > .claude/checkpoints/g1-tauri/mut.py <<'EOF'
import sys, subprocess, shutil, os
# usage, from windows/: python3 ../.claude/checkpoints/g1-tauri/mut.py <file> <find> <replace> <test files...>
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

---

# Stage 0: the spike

### Task 1: Spike: a native file drag source

**Agent:** `nm-implementer-deep` (Sonnet 5.5, high), **trigger 1** (platform APIs the task must design: OLE's modal `DoDragDrop` and its drop source, a GTK drag begun outside the press that started it, the main thread that both need). Loads `superpowers:systematic-debugging` too.

**Files:**
- Create: `windows/src-tauri/src/dragout.rs`, `windows/src-tauri/src/platform/windows/drag.rs`, `windows/src-tauri/src/platform/linux/drag.rs`, `windows/src/shelf/dragspike.ts`, `windows/scripts/cat-tests/shelf-commands.test.mjs`
- Modify: `windows/src-tauri/src/lib.rs`, `windows/src-tauri/src/platform/mod.rs`, `windows/src-tauri/src/platform/windows.rs`, `windows/src-tauri/src/platform/linux.rs`, `windows/src-tauri/Cargo.toml`, `windows/src/core/bridge.ts`, `windows/src/main.ts`

**Interfaces:**
- Consumes: `island::window(&AppHandle)`, the `windows` and `gtk` crates already in `Cargo.toml`, `tokio` (`sync`, `time`).
- Produces: `dragout::start(&AppHandle, Vec<PathBuf>) -> Result<&'static str, String>` (resolves `copied`, `none` or `cancelled`, when the drag ends), `dragout::supported()`, the switches `dragout::WINDOWS` and `dragout::LINUX`, `dragout::file_uri(&Path) -> String`; `platform::drag_out(&WebviewWindow, Vec<PathBuf>, DragDone)` and `platform::DragDone` on both systems; the command `drag_out_spike` (Debug builds); `Bridge.dragOutSpike()`; the dev server's green tab. Tasks 8 and 9 use all of it.

**What the spike must settle, and how it reports.** The two native sources must be written, compiled where the session can (Linux, in Docker) and wired so a person can press a tab and drag a file out. The task **ends with a written report** in the ledger and in the Checkpoint 0 ping: for Linux, whether `cargo-linux.sh check` compiled it (and the first ten lines of any error); for Windows, that nothing the session can run compiles it (CI will); and the five-step check for the owner. It never claims that a drag works. If the Linux code does not compile and the cause is the gtk-rs API (not a typo), the deep agent fixes it against the container's `gtk` 0.18 source; if it cannot, it says so and leaves the file as it is: the fallback is one line (see "The spike and its fallback").

- [ ] **Step 1: Write the test that pins the names the page and Rust must agree on, and the shape of the drag source**


```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/shelf-commands.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The names the page calls and the commands Rust registers are two strings that nothing else ties together, and a mistake in one fails silently (the bridge answers null). This pins them:
// every shelf command and the drag-out commands in bridge.ts have a `#[tauri::command]` in lib.rs and are in `generate_handler!`, and the commands take ids, never a path (only a drop
// brings paths in).
const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const bridge = read("src/core/bridge.ts"), lib = read("src-tauri/src/lib.rs");
const called = [...bridge.matchAll(/(?:call|callOrThrow)<[^>]*(?:<[^>]*>)?[^>]*>\("((?:shelf|drag_out)_?[a-z_]*)"/g)].map((m) => m[1]);
const handler = lib.slice(lib.indexOf("generate_handler!["), lib.indexOf("])", lib.indexOf("generate_handler![")));

test("the page's shelf and drag-out calls are the commands Rust registers", () => {
  assert.ok(called.includes("drag_out_spike"), `found ${called.join(", ")}`);
  for (const name of called) {
    assert.match(lib, new RegExp(`#\\[tauri::command\\]\\s*(?:async )?fn ${name}\\(`), `${name} is a command`);
    assert.match(handler, new RegExp(`\\b${name},`), `${name} is registered`);
  }
});

test("every shelf command that touches a file takes an id or a list of ids; only shelf_add takes paths (a drop's)", () => {
  for (const name of called.filter((n) => n.startsWith("shelf_"))) {
    const sig = lib.match(new RegExp(`fn ${name}\\(([^)]*)\\)`))[1];
    if (name === "shelf_add") assert.match(sig, /paths: Vec<String>/);
    else assert.doesNotMatch(sig, /path/i, `${name}(${sig})`);
  }
  assert.match(lib, /fn drag_out_spike\(app: AppHandle\)/, "the spike takes nothing: it makes its own file");
});

test("the spike refuses in a release build, and makes its own file, never one of the user's", () => {
  const spike = lib.slice(lib.indexOf("async fn drag_out_spike"), lib.indexOf("fn secret_present"));
  assert.match(spike, /if !cfg!\(debug_assertions\) \{\s*return Err\(/);
  assert.match(spike, /settings::local_dir\(\)\.join\("spike"\)/);
  assert.match(spike, /dragout::start\(&app, vec!\[file\]\)\.await/);
});

test("the drag source exists for both systems with the same shape, behind one type and one pair of switches", () => {
  const mod = read("src-tauri/src/platform/mod.rs"), win = read("src-tauri/src/platform/windows.rs"), lin = read("src-tauri/src/platform/linux.rs"), drag = read("src-tauri/src/dragout.rs");
  assert.match(mod, /pub type DragDone = Box<dyn FnOnce\(Result<&'static str, String>\)>;/);
  assert.match(win, /pub fn drag_out\(_win: &WebviewWindow, paths: Vec<PathBuf>, done: DragDone\)/);
  assert.match(lin, /pub fn drag_out\(win: &WebviewWindow, paths: Vec<PathBuf>, done: DragDone\)/);
  assert.match(drag, /pub const WINDOWS: bool = (?:true|false);\s*\/\/\/ Linux can drag[^\n]*\npub const LINUX: bool = (?:true|false);/, "one switch per system: the fallback is flipping one");
  assert.match(read("src-tauri/src/platform/windows/drag.rs"), /DoDragDrop\(&data, &source, DROPEFFECT_COPY, &mut effect\)/, "copy only: an original is never moved");
  assert.match(read("src-tauri/src/platform/linux/drag.rs"), /drag_begin_with_coordinates\(&targets, gdk::DragAction::COPY, 1, None, -1, -1\)/, "copy only");
  assert.match(drag, /win\.run_on_main_thread\(move \|\| \{/, "OLE and GTK both need the main thread");
});

test("the Windows build asks the windows crate for the features the drag source uses, and no new crate", () => {
  const toml = read("src-tauri/Cargo.toml");
  for (const f of ["Win32_System_Com", "Win32_System_SystemServices", "Win32_UI_Shell", "Win32_UI_Shell_Common", "Win32_System_Ole"]) assert.match(toml, new RegExp(`"${f}"`), f);
  assert.doesNotMatch(toml, /\bsnow\b|mdns/, "G2's crates are not here");
});

test("the spike's tab is mounted only by the dev server, and presses with the same 4 px rule as everything else", () => {
  assert.match(read("src/main.ts"), /if \(import\.meta\.env\.DEV\) void import\("\.\/shelf\/dragspike"\)\.then\(\(m\) => m\.mountDragSpike\(\)\);/);
  const tab = read("src/shelf/dragspike.ts");
  assert.match(tab, /new PressDrag\(\)/);
  assert.match(tab, /Bridge\.dragOutSpike\(\)/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-commands.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
cd ..
```

Expected: `# fail 6` (every test fails: `lib.rs` has no `drag_out_spike` yet and `dragout.rs` is not there).

- [ ] **Step 3: Write the drag source and its tab**

`dragout.rs` is the shared part (the switches, `file_uri`, `start`); the two `drag.rs` files are the systems'. Everything the page needs of a drag is in `start`: it runs the platform's drag on the main thread and answers when the drag ends.


```bash
mkdir -p windows/src-tauri/src
cat > windows/src-tauri/src/dragout.rs <<'EOF'
// Dragging files out of the island (sub-project G1; the spike of the Windows/Linux plan's Task 1, then the shelf's drag out).
//
// The page cannot start a drag of real files: Tauri's drag-and-drop setting (which the island needs, to receive files) turns the webview's own drag off. So a press that moves on a
// shelf tile asks Rust for a native drag source: Windows runs OLE's `DoDragDrop` with a shell data object (platform/windows/drag.rs), Linux starts a GTK drag whose data is a
// `text/uri-list` (platform/linux/drag.rs). Both only copy: an original is never moved or deleted by a drag.
//
// THE FALLBACK, one line each. If the owner's real-machine check says a system cannot do it, that system's constant below goes to `false`: the shelf then hides the drag (the tile
// is still ticked by a click) and keeps Ask, Send and Show in folder. Nothing else changes.

use std::path::{Path, PathBuf};
use std::time::Duration;

use tauri::AppHandle;

use crate::{island, platform};

/// Windows can drag files out of the island (OLE `DoDragDrop`). Set to `false` if the real-machine check fails.
pub const WINDOWS: bool = true;
/// Linux can drag files out of the island (a GTK drag source with `text/uri-list`). Set to `false` if the real-machine check fails on Linux.
pub const LINUX: bool = true;

/// Whether this system's island can drag files out. The shelf shows the drag only where this is true.
pub fn supported() -> bool {
    if cfg!(windows) {
        WINDOWS
    } else {
        LINUX
    }
}

/// A `file://` URI for a path, as a `text/uri-list` holds it: every byte outside `A-Za-z0-9-._~` and the path separator and a drive colon is `%XX` of its UTF-8 byte.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn file_uri(path: &Path) -> String {
    let text = path.to_string_lossy().replace('\\', "/");
    let mut out = String::from("file://");
    if !text.starts_with('/') {
        out.push('/'); // C:/Users/... becomes file:///C:/Users/...
    }
    for (i, b) in text.bytes().enumerate() {
        let drive_colon = b == b':' && i == 1 && text.as_bytes()[0].is_ascii_alphabetic();
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~' | b'/') || drive_colon {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// Drags these files out of the island's window until the user lets go: `copied` when a target took a copy, `none` when it landed where nothing accepts files, `cancelled`
/// for Escape. Runs on the main thread (OLE and GTK both need it) and answers when the drag ends, so the caller can ignore the drop that comes back to the island itself.
pub async fn start(app: &AppHandle, paths: Vec<PathBuf>) -> Result<&'static str, String> {
    if !supported() {
        return Err("Dragging files out is not available on this system.".into());
    }
    if paths.is_empty() {
        return Err("Nothing to drag.".into());
    }
    let win = island::window(app).ok_or_else(|| "The island window is not there.".to_string())?;
    let (tx, rx) = tokio::sync::oneshot::channel::<Result<&'static str, String>>();
    let target = win.clone();
    win.run_on_main_thread(move || {
        platform::drag_out(&target, paths, Box::new(move |result| drop(tx.send(result))));
    })
    .map_err(|e| e.to_string())?;
    // A drag that never reports its end (a compositor that lost it) must not hang the page's call for good.
    match tokio::time::timeout(Duration::from_secs(300), rx).await {
        Ok(Ok(result)) => result,
        Ok(Err(_)) => Err("The drag ended without an answer.".into()),
        Err(_) => Err("The drag did not end.".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_unix_path_becomes_a_file_uri_with_everything_unusual_escaped() {
        assert_eq!(file_uri(Path::new("/home/me/a b#c%d.txt")), "file:///home/me/a%20b%23c%25d.txt");
        assert_eq!(file_uri(Path::new("/tmp/é😀")), "file:///tmp/%C3%A9%F0%9F%98%80");
        assert_eq!(file_uri(Path::new("/a/b-c_d.e~f")), "file:///a/b-c_d.e~f");
    }

    #[test]
    fn a_windows_path_gets_its_drive_and_forward_slashes() {
        assert_eq!(file_uri(Path::new("C:\\Users\\me\\My Files\\é.txt")), "file:///C:/Users/me/My%20Files/%C3%A9.txt");
        assert_eq!(file_uri(Path::new("c:\\x")), "file:///c:/x");
    }

    #[test]
    fn a_colon_that_is_not_a_drive_is_escaped() {
        assert_eq!(file_uri(Path::new("/home/me/a:b")), "file:///home/me/a%3Ab");
    }

    #[test]
    fn the_fallback_is_the_constant_of_the_system_it_runs_on() {
        // The plan's fallback is a one-line edit of WINDOWS or LINUX; `supported` reads the one for this system.
        assert_eq!(supported(), if cfg!(windows) { WINDOWS } else { LINUX });
    }
}
EOF
```

```bash
mkdir -p windows/src-tauri/src/platform/windows
cat > windows/src-tauri/src/platform/windows/drag.rs <<'EOF'
// The Windows drag source (sub-project G1): starts an OLE drag of real files from the island, the way Explorer does. The page cannot do this itself: with Tauri's drag-and-drop
// setting on (the island needs it, to receive files), WebView2 hands the page no HTML5 drag. So a press that moves on a shelf tile asks Rust, and Rust runs `DoDragDrop` with a
// shell data object that holds the files (CF_HDROP and the rest, built by the shell from their paths) and a drop source that follows the left button.
//
// `run` is modal: it returns when the button is released or Escape is pressed, so it is called on the main thread (the one OLE is initialised on, which is also where the window's own
// drop target lives) and never from an async worker. Only copying is allowed: an original is never moved or deleted by a drag.

use std::os::windows::ffi::OsStrExt;
use std::path::PathBuf;

use ::windows::core::{implement, BOOL, HRESULT, PCWSTR};
use ::windows::Win32::Foundation::{DRAGDROP_S_CANCEL, DRAGDROP_S_DROP, DRAGDROP_S_USEDEFAULTCURSORS, S_OK};
use ::windows::Win32::System::Com::{IBindCtx, IDataObject};
use ::windows::Win32::System::Ole::{DoDragDrop, IDropSource, IDropSource_Impl, DROPEFFECT, DROPEFFECT_COPY};
use ::windows::Win32::System::SystemServices::{MK_LBUTTON, MODIFIERKEYS_FLAGS};
use ::windows::Win32::UI::Shell::Common::ITEMIDLIST;
use ::windows::Win32::UI::Shell::{ILFree, SHCreateDataObject, SHParseDisplayName};

/// The drop source: the drag goes on while the left button is down, ends in a drop when it is released and is cancelled by Escape. The cursors are the system's.
#[implement(IDropSource)]
struct Source;

impl IDropSource_Impl for Source_Impl {
    fn QueryContinueDrag(&self, fescapepressed: BOOL, grfkeystate: MODIFIERKEYS_FLAGS) -> HRESULT {
        if fescapepressed.as_bool() {
            DRAGDROP_S_CANCEL
        } else if grfkeystate.0 & MK_LBUTTON.0 == 0 {
            DRAGDROP_S_DROP
        } else {
            S_OK
        }
    }

    fn GiveFeedback(&self, _effect: DROPEFFECT) -> HRESULT {
        DRAGDROP_S_USEDEFAULTCURSORS
    }
}

/// The shell's item ids for the paths, freed when this goes out of scope (the data object keeps its own copies).
struct Pidls(Vec<*mut ITEMIDLIST>);

impl Drop for Pidls {
    fn drop(&mut self) {
        for p in &self.0 {
            unsafe { ILFree(Some(*p as *const ITEMIDLIST)) };
        }
    }
}

/// Drags these files (they must exist) until the button is released. `Ok("copied")` when a target took a copy, `Ok("none")` when the drop landed nowhere that accepts files,
/// `Ok("cancelled")` for Escape, `Err` when the system could not even start.
pub fn run(paths: &[PathBuf]) -> Result<&'static str, String> {
    let mut pidls = Pidls(Vec::new());
    for p in paths {
        let wide: Vec<u16> = p.as_os_str().encode_wide().chain(Some(0)).collect();
        let mut pidl: *mut ITEMIDLIST = std::ptr::null_mut();
        unsafe { SHParseDisplayName(PCWSTR(wide.as_ptr()), None::<&IBindCtx>, &mut pidl, 0, None) }.map_err(|e| format!("cannot find {}: {e}", p.display()))?;
        pidls.0.push(pidl);
    }
    let absolute: Vec<*const ITEMIDLIST> = pidls.0.iter().map(|p| *p as *const ITEMIDLIST).collect();
    let data: IDataObject = unsafe { SHCreateDataObject(None, Some(&absolute), None::<&::windows::core::IUnknown>) }.map_err(|e| format!("cannot make the data object: {e}"))?;
    let source: IDropSource = Source.into();
    let mut effect = DROPEFFECT(0);
    let hr = unsafe { DoDragDrop(&data, &source, DROPEFFECT_COPY, &mut effect) };
    if hr == DRAGDROP_S_DROP {
        Ok(if effect == DROPEFFECT_COPY { "copied" } else { "none" })
    } else if hr == DRAGDROP_S_CANCEL {
        Ok("cancelled")
    } else {
        Err(format!("DoDragDrop failed: {hr:?}"))
    }
}
EOF
```

```bash
mkdir -p windows/src-tauri/src/platform/linux
cat > windows/src-tauri/src/platform/linux/drag.rs <<'EOF'
// The Linux drag source (sub-project G1): starts a GTK drag of real files from the island's window. The data is a `text/uri-list` of `file://` URIs, which file managers, mail clients and
// browsers all take. Only copying is offered. GTK runs this on the main thread; `begin` returns at once and `done` is called from the drag's end.
//
// Wayland is the risk the spike exists to measure: a compositor may refuse a drag that does not come from the press that started it (GTK then returns no drag context, and `done` gets
// that error). X11 and XWayland do not mind. See dragout.rs for the fallback.

use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

use gtk::gdk;
use gtk::glib::SignalHandlerId;
use gtk::prelude::*;

use crate::dragout::file_uri;
use crate::platform::DragDone;

pub fn begin(window: &gtk::ApplicationWindow, paths: &[PathBuf], done: DragDone) {
    let uris: Vec<String> = paths.iter().map(|p| file_uri(p)).collect();
    let source: gtk::Widget = window.clone().upcast();
    let done = Rc::new(RefCell::new(Some(done)));
    let handlers: Rc<RefCell<Vec<SignalHandlerId>>> = Rc::new(RefCell::new(Vec::new()));

    // Both handlers are taken off the window again when the drag is over, so a second drag starts clean.
    let finish = {
        let (source, handlers, done) = (source.clone(), handlers.clone(), done.clone());
        Rc::new(move |result: Result<&'static str, String>| {
            for id in handlers.borrow_mut().drain(..) {
                source.disconnect(id);
            }
            if let Some(d) = done.borrow_mut().take() {
                d(result);
            }
        })
    };

    let get = source.connect_drag_data_get(move |_, _, data, _, _| {
        let refs: Vec<&str> = uris.iter().map(String::as_str).collect();
        data.set_uris(&refs);
    });
    let end = {
        let finish = finish.clone();
        source.connect_drag_end(move |_, ctx| finish(Ok(if ctx.selected_action() == gdk::DragAction::COPY { "copied" } else { "cancelled" })))
    };
    handlers.borrow_mut().extend([get, end]);

    let targets = gtk::TargetList::new(&[gtk::TargetEntry::new("text/uri-list", gtk::TargetFlags::OTHER_APP, 0)]);
    if source.drag_begin_with_coordinates(&targets, gdk::DragAction::COPY, 1, None, -1, -1).is_none() {
        finish(Err("The system would not start the drag (on Wayland it needs the press that began it).".into()));
    }
}
EOF
```

```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/dragspike.ts <<'EOF'
// The drag-out spike's trigger (sub-project G1, Task 1): a small green tab in the compact island that, pressed and moved 4 px, drags a test file out of the island through the native
// drag source (src-tauri/src/dragout.rs). It exists so a person can try the drag on a real Windows or Linux machine before the shelf depends on it: press the tab and drag it onto
// the desktop, a folder window, a mail window or a text editor. The tab says what happened. Dev server only: main.ts mounts it behind `import.meta.env.DEV`, so a release build does not
// contain it. Drag it by its own press, never by the shelf's: this is the check of the system, not of the shelf.

import { Bridge } from "../core/bridge";
import { PressDrag } from "../cat/pressdrag";

export function mountDragSpike(): void {
  const tab = document.createElement("div");
  tab.id = "nm-drag-spike";
  tab.textContent = "drag test file";
  tab.style.cssText = "position:fixed;top:4px;left:calc(50% - 64px);width:128px;height:24px;line-height:24px;text-align:center;z-index:99999;font:600 11px system-ui,sans-serif;color:#07130e;background:#34d399;border-radius:12px;cursor:grab;user-select:none";
  const press = new PressDrag();
  const say = (text: string) => { tab.textContent = text; window.setTimeout(() => (tab.textContent = "drag test file"), 4000); };
  tab.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    press.press(e.clientX, e.clientY);
    const move = (m: MouseEvent) => {
      if (press.move(m.clientX, m.clientY) !== "start") return;
      cleanup();
      press.cancel();
      Bridge.dragOutSpike().then((result) => say(`drag: ${result}`)).catch((err) => say(`drag failed: ${String(err).slice(0, 40)}`));
    };
    const up = () => { cleanup(); press.cancel(); };
    const cleanup = () => { window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up); };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  });
  document.body.append(tab);
}
EOF
```

- [ ] **Step 4: Wire it in** (the platform functions, the `windows` crate's features, the Debug command, the bridge and the tab's mount)


```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src-tauri/src/platform/mod.rs", [
('''use std::path::PathBuf;
''', '''use std::path::PathBuf;

/// What a native drag out of the island reports when it ends (dragout.rs): `copied`, `none` or `cancelled`, or why it could not start.
pub type DragDone = Box<dyn FnOnce(Result<&'static str, String>)>;
'''),
])
edit("windows/src-tauri/src/platform/windows.rs", [
('''use super::LocalTime;
''', '''mod drag;

use super::{DragDone, LocalTime};
'''),
('''pub fn reveal_folder(path: &str) {''', '''/// Drags these files out of the island with OLE (windows/drag.rs). Modal: returns when the button is released, so it runs on the main thread (dragout.rs).
pub fn drag_out(_win: &WebviewWindow, paths: Vec<PathBuf>, done: DragDone) {
    done(drag::run(&paths));
}

pub fn reveal_folder(path: &str) {'''),
])
edit("windows/src-tauri/src/platform/linux.rs", [
('''use super::{home_dir, LocalTime};
''', '''mod drag;

use super::{home_dir, DragDone, LocalTime};
'''),
('''pub fn reveal_folder(path: &str) {''', '''/// Starts a GTK drag of these files out of the island (linux/drag.rs). Returns at once; `done` is called when the drag ends.
pub fn drag_out(win: &WebviewWindow, paths: Vec<PathBuf>, done: DragDone) {
    match win.gtk_window() {
        Ok(gw) => drag::begin(&gw, &paths, done),
        Err(e) => done(Err(e.to_string())),
    }
}

pub fn reveal_folder(path: &str) {'''),
])
edit("windows/src-tauri/Cargo.toml", [
('''  "Win32_Graphics_Gdi",
  "Win32_System_LibraryLoader",
  "Win32_System_Ole",''', '''  "Win32_Graphics_Gdi",
  "Win32_System_Com",
  "Win32_System_LibraryLoader",
  "Win32_System_Ole",'''),
('''  "Win32_System_SystemInformation",
  "Win32_System_Threading",
  "Win32_UI_Input_KeyboardAndMouse",''', '''  "Win32_System_SystemInformation",
  "Win32_System_SystemServices",
  "Win32_System_Threading",
  "Win32_UI_Input_KeyboardAndMouse",
  "Win32_UI_Shell",
  "Win32_UI_Shell_Common",'''),
])
edit("windows/src-tauri/src/lib.rs", [
('''mod desktop;
mod files;''', '''mod desktop;
mod dragout;
mod files;'''),
('''#[tauri::command]
fn secret_present(key: String) -> bool {''', '''/// The drag-out spike (Debug builds only): makes a small text file of its own and drags it out of the island, so a person can try dropping it in Explorer, the file manager or a mail
/// window on a real machine. Release builds refuse. The shelf's own drag out is `shelf_drag_out`.
#[tauri::command]
async fn drag_out_spike(app: AppHandle) -> Result<&'static str, String> {
    if !cfg!(debug_assertions) {
        return Err("The drag-out spike is a Debug-build tool.".into());
    }
    let dir = settings::local_dir().join("spike");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let file = dir.join("NotchMeow drag test.txt");
    std::fs::write(&file, "Dragged out of the NotchMeow island.\\n").map_err(|e| e.to_string())?;
    dragout::start(&app, vec![file]).await
}

#[tauri::command]
fn secret_present(key: String) -> bool {'''),
('''            ingest_file,
            secret_present,''', '''            ingest_file,
            drag_out_spike,
            secret_present,'''),
])
edit("windows/src/core/bridge.ts", [
('''  /** Only ever tells you whether a key exists — never its value. */''', '''  /** The drag-out spike (Debug builds of the app): drags a small test file of Rust's own out of the island. Resolves when the drag ends: "copied", "none" or "cancelled". */
  dragOutSpike: () => callOrThrow<string>("drag_out_spike"),
  /** Only ever tells you whether a key exists — never its value. */'''),
])
edit("windows/src/main.ts", [
('''  if (boot && !boot.cursorPoll) island.followPageCursor();
''', '''  if (boot && !boot.cursorPoll) island.followPageCursor();
  // Dev server only: a small tab in the compact island that drags a test file out, to try the native drag source on a real machine (shelf/dragspike.ts).
  if (import.meta.env.DEV) void import("./shelf/dragspike").then((m) => m.mountDragSpike());
'''),
])
print("applied")
PYEOF
```

Expected: `applied`

- [ ] **Step 5: Run the checks to see them pass**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-commands.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: `# pass 6`, `# fail 0`, `tsc exit 0`, `ℹ tests 378`, `ℹ pass 378`, `ℹ fail 0`.

- [ ] **Step 6: Prove the pins bite**

Run:

```bash
cd windows
m() { python3 ../.claude/checkpoints/g1-tauri/mut.py "$@"; }; T=scripts/cat-tests/shelf-commands.test.mjs
m src-tauri/src/lib.rs '            drag_out_spike,
' '' $T
m src-tauri/src/platform/windows/drag.rs 'DoDragDrop(&data, &source, DROPEFFECT_COPY, &mut effect)' 'DoDragDrop(&data, &source, DROPEFFECT_COPY | DROPEFFECT_MOVE, &mut effect)' $T
m src/main.ts 'if (import.meta.env.DEV) void import("./shelf/dragspike")' 'void import("./shelf/dragspike")' $T
cd ..
```

Expected: each line ends `# pass 5 # fail 1` (the registration, copy only, and the dev-server-only mount).

- [ ] **Step 7: The Rust (needs the image)**

The pure part of `dragout.rs` (`file_uri`) is tested; the two drag sources are compiled, not run. `cargo check` compiles the Linux code (the GTK source) and proves it type-checks; the Windows code compiles only on Windows.

Run:

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && {
  bash windows/scripts/cargo-linux.sh test -p notchmeow dragout:: --target-dir /repo/windows/target/g1-tauri 2>&1 | grep -E "^test result|^error|^warning"
  bash windows/scripts/cargo-linux.sh check -p notchmeow --target-dir /repo/windows/target/g1-tauri 2>&1 | grep -E "^error|^warning|Finished" | head -20
} || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok. 4 passed` for `dragout::`, then `Finished` and no `error` and no `warning` (or the line saying the Rust is owed). A GTK error here is the spike's finding: report the first ten lines. The Windows `cargo check` is owed to CI.

- [ ] **Step 8: Write the spike's report, then commit**

In the ledger (`.superpowers/sdd/2026-10-14-g1-tauri-shelf/progress.md`) write the report: Linux `cargo check` (compiled, or the error), Windows (not compiled here; owed to `windows-tests.yml`), and "a drag has not been run on any machine". That text is the body of the **Checkpoint 0** ping, with the five-step check from "The spike and its fallback".


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/scripts/cat-tests/shelf-commands.test.mjs windows/src-tauri/src/dragout.rs windows/src-tauri/src/platform windows/src-tauri/src/lib.rs windows/src-tauri/Cargo.toml windows/src/shelf/dragspike.ts windows/src/core/bridge.ts windows/src/main.ts
git commit -F - <<'MSG'
spike(shelf): a native file drag source for the island (OLE on Windows, GTK on Linux)

A drag of real files out of the island cannot be started by the page, so Rust starts it: DoDragDrop with a shell data object on Windows, a GTK drag of a text/uri-list on Linux, copy only,
on the main thread, answering when the drag ends. The two systems each have one fallback switch in dragout.rs. A Debug-only command and a dev-server tab try it with a test file.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts printed above, the agent, the model and the trigger.

## Checkpoint 0: the spike's result (ping and go on)

The session sends the main session the spike's report (Step 8) with `SendMessage`, and **goes on to Task 2 without waiting**. The main session relays the five-step check to the owner. When the owner answers (works, refused, crashed, with the compositor), the controller records it in the ledger and applies the fallback in Task 8 if one system failed. Until then both switches stay `true`.

---

# Stage 1: the contract's rules

### Task 2: The contract's rules in TypeScript

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `windows/src/shelf/rules.ts`, `windows/scripts/cat-tests/shelf-rules.test.mjs`

**Interfaces:**
- Consumes: `tests/fixtures/shelf/zone-cases.json` and `shelf-cases.json` (read at test time), nothing else.
- Produces: `SHELF_MAX`, `ID_RE`, `NAME_MAX`, `LINK_MAX`, `NUMBER_MAX`; `type Zone = "ask" | "shelf"`, `interface ShelfItem`, `type AddWord`; `zoneAt(x: unknown, width: unknown): Zone | null`, `shelfClean(raw: unknown): ShelfItem[]`, `shelfAdd(items: unknown, incoming: unknown): { items: ShelfItem[]; results: AddWord[] }`, `readShelf(bytes: Uint8Array): ShelfItem[]`. Pure: no DOM, no Tauri. Tasks 4, 5 and 6 use them.

- [ ] **Step 1: Write the test**


```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/shelf-rules.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import * as R from "../../src/shelf/rules.ts";

// The shelf contract (G1-0), replayed from tests/fixtures/shelf/. `reference.py` decides when this file and a fixture disagree.
const fx = (name) => JSON.parse(fs.readFileSync(new URL(`../../../tests/fixtures/shelf/${name}`, import.meta.url), "utf8"));
const cases = fx("shelf-cases.json"), zones = fx("zone-cases.json");
const json = (v) => JSON.parse(JSON.stringify(v));

test("the constants are the fixture's", () => {
  assert.deepEqual([R.SHELF_MAX, R.ID_RE.source.replace(/^\^|\$$/g, ""), R.NAME_MAX, R.LINK_MAX, R.NUMBER_MAX], [cases.max, cases.idPattern, cases.nameMax, cases.linkMax, cases.numberMax]);
});

test("zoneAt replays every row of zone-cases.json (a missing key stands for a value JSON cannot hold)", () => {
  assert.ok(zones.cases.length >= 30);
  for (const c of zones.cases) assert.equal(R.zoneAt(c.x, c.width), c.out, c.name);
});

test("zoneAt: the centre line is Ask, the rest of the right half is Shelf, outside is null, and no input throws", () => {
  assert.equal(R.zoneAt(300, 600), "ask");
  assert.equal(R.zoneAt(300.0001, 600), "shelf");
  assert.equal(R.zoneAt(-0.0001, 600), null);
  assert.equal(R.zoneAt(600.0001, 600), null);
  for (const bad of [undefined, null, true, "5", [], {}, NaN, Infinity, 1e300]) {
    assert.equal(R.zoneAt(bad, 600), null);
    assert.equal(R.zoneAt(5, bad), null);
  }
});

test("shelfClean replays every cleanCases row, in the contract's field order", () => {
  assert.ok(cases.cleanCases.length >= 100);
  for (const c of cases.cleanCases) assert.deepEqual(json(R.shelfClean(c.raw)), c.out, c.name);
  const [one] = R.shelfClean({ items: [{ id: "a", name: "f.txt", size: 1, folder: false, copy: false, link: "/p/a", addedAt: 5, extra: 1 }] });
  assert.deepEqual(Object.keys(one), ["id", "name", "size", "folder", "copy", "link", "addedAt"]);
});

test("shelfAdd replays every addCases row", () => {
  assert.ok(cases.addCases.length >= 25);
  for (const c of cases.addCases) assert.deepEqual(json(R.shelfAdd(c.items, c.incoming)), c.out, c.name);
});

test("readShelf replays every parseCases row (text, or hex when the bytes are not UTF-8)", () => {
  assert.ok(cases.parseCases.length >= 15);
  for (const c of cases.parseCases) {
    const bytes = c.text !== undefined ? new TextEncoder().encode(c.text) : Uint8Array.from(Buffer.from(c.hex, "hex"));
    assert.deepEqual(json(R.readShelf(bytes)), c.out, c.name);
  }
});

test("a drop on a full shelf refuses the extras and removes nothing; a re-dropped file says duplicate even then", () => {
  const mk = (n) => ({ id: `i${n}`, name: `f${n}.txt`, size: 1, folder: false, copy: false, link: `/p/${n}`, addedAt: 1000 + n });
  const full = Array.from({ length: R.SHELF_MAX }, (_, n) => mk(n));
  const res = R.shelfAdd(full, [mk(5), mk(99), { nope: 1 }]);
  assert.deepEqual(res.results, ["duplicate", "full", "invalid"]);
  assert.equal(res.items.length, R.SHELF_MAX);
  assert.deepEqual(new Set(res.items.map((i) => i.id)), new Set(full.map((i) => i.id)));
});

test("a hostile shelf never throws and a clean one stays clean (the rules are idempotent)", () => {
  for (const hostile of [undefined, null, 5, "x", [], { items: 5 }, { items: [null, 1, "a", [], { id: 5 }] }, { items: Array.from({ length: 300 }, (_, n) => ({ id: `a${n}`, name: "n", link: `/${n}`, addedAt: n })) }]) {
    const once = R.shelfClean(hostile);
    assert.deepEqual(R.shelfClean({ items: once }), once);
    assert.ok(once.length <= R.SHELF_MAX);
  }
  assert.equal(R.shelfClean({ items: Array.from({ length: 300 }, (_, n) => ({ id: `a${n}`, name: "n", link: `/${n}`, addedAt: n })) })[0].addedAt, 299, "300 items keep the 30 newest");
});

test("minus zero is the number 0 (JSON.parse gives -0; Object.is tells them apart where a JSON round trip would not)", () => {
  const [it] = R.readShelf(new TextEncoder().encode('{"items":[{"id":"a","name":"f.txt","size":-0,"copy":true,"addedAt":-0.0}]}'));
  assert.ok(Object.is(it.size, 0) && Object.is(it.addedAt, 0));
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-rules.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ERR_MODULE_NOT_FOUND" | head -3
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND` (the file cannot load, so no test runs).

- [ ] **Step 3: Write the rules**

Two notes for the reader: a Unicode category is a regular expression's `\p{Cc}` and its kin (the `u` flag), so no table is needed; and the ranges `\x00-\x1f\x7f-\x9f` are the contract's "control" for a link, which, unlike a name, may hold format characters.


```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/rules.ts <<'EOF'
// The shelf contract's three rules in TypeScript (sub-project G1; docs/SHELF-CONTRACT.md, tests/fixtures/shelf/). Pure: no DOM, no Tauri, nothing stored.
// `tests/fixtures/shelf/reference.py` is the tie-breaker; scripts/cat-tests/shelf-rules.test.mjs replays every row of both fixtures through this file.
// The Rust twin for the file on disk is src-tauri/src/shelf.rs (it replays the same rows).

export const SHELF_MAX = 30;
export const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
export const NAME_MAX = 255;
export const LINK_MAX = 8192;
export const NUMBER_MAX = 9007199254740991;

export type Zone = "ask" | "shelf";

/** One thing on the shelf. A copy lives in `shelf/<id>/<name>` and has no link; every other item points at its original by `link` (a path here). */
export interface ShelfItem {
  id: string;
  name: string;
  size: number;
  folder: boolean;
  copy: boolean;
  link?: string;
  addedAt: number;
}

export type AddWord = "added" | "duplicate" | "full" | "invalid";

const own = (o: object, k: string): unknown => (Object.prototype.hasOwnProperty.call(o, k) ? (o as Record<string, unknown>)[k] : undefined);
const isObject = (v: unknown): v is object => typeof v === "object" && v !== null && !Array.isArray(v);

/** Which half of the open island the pointer is in: `x` from the island's left edge, `width` the island's. The centre line is Ask. Null outside the island or for anything that is not a number. */
export function zoneAt(x: unknown, width: unknown): Zone | null {
  for (const v of [x, width]) if (typeof v !== "number" || !Number.isFinite(v) || Math.abs(v) > NUMBER_MAX) return null;
  const px = x as number, w = width as number;
  if (w <= 0 || px < 0 || px > w) return null;
  return px * 2 <= w ? "ask" : "shelf";
}

/** Windows device names, refused as a name's stem or an id (ASCII case-insensitively; the superscript digits are reserved too). */
const RESERVED = new Set(["CON", "PRN", "AUX", "NUL", ...[1, 2, 3, 4, 5, 6, 7, 8, 9].flatMap((n) => [`COM${n}`, `LPT${n}`]), "COM\xb9", "COM\xb2", "COM\xb3", "LPT\xb9", "LPT\xb2", "LPT\xb3"]);
const asciiUpper = (s: string) => s.replace(/[a-z]/g, (c) => c.toUpperCase());
const reserved = (s: string) => RESERVED.has(asciiUpper(s.split(".", 1)[0].replace(/ +$/, "")));
const BAD_NAME_CHAR = /[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]/u;
const BAD_LINK_CHAR = /[\x00-\x1f\x7f-\x9f\p{Cs}]/u;
const codePoints = (s: string) => Array.from(s).length;

function nameOk(name: unknown): name is string {
  if (typeof name !== "string") return false;
  const n = codePoints(name);
  if (n < 1 || n > NAME_MAX) return false;
  if (BAD_NAME_CHAR.test(name) || name.includes("/") || name.includes("\\") || /^\.+$/.test(name) || /[. ]$/.test(name)) return false;
  return !reserved(name);
}

/** A whole number from 0 to NUMBER_MAX (5 and 5.0 are the same JSON number), else 0. */
function whole(v: unknown): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > NUMBER_MAX) return 0;
  return v === 0 ? 0 : v;
}

function itemClean(raw: unknown): ShelfItem | null {
  if (!isObject(raw)) return null;
  const id = own(raw, "id"), name = own(raw, "name");
  if (typeof id !== "string" || !ID_RE.test(id) || reserved(id) || !nameOk(name)) return null;
  const copy = own(raw, "copy") === true, folder = own(raw, "folder") === true;
  if (copy && folder) return null; // a folder is only ever a link
  const size = whole(own(raw, "size")), addedAt = whole(own(raw, "addedAt"));
  if (copy) return { id, name, size, folder, copy, addedAt };
  const link = own(raw, "link");
  if (typeof link !== "string" || codePoints(link) < 1 || codePoints(link) > LINK_MAX || BAD_LINK_CHAR.test(link)) return null;
  return { id, name, size, folder, copy, link, addedAt };
}

/** Newest first (stable), then the first of each id (ASCII case-insensitive) and of each link (exact), then the first SHELF_MAX. One pass in sorted order. */
function tidy(items: ShelfItem[]): ShelfItem[] {
  const sorted = [...items].sort((a, b) => b.addedAt - a.addedAt);
  const ids = new Set<string>(), links = new Set<string>(), out: ShelfItem[] = [];
  for (const it of sorted) {
    const idKey = asciiLower(it.id);
    if (ids.has(idKey) || (it.link !== undefined && links.has(it.link))) continue;
    ids.add(idKey);
    if (it.link !== undefined) links.add(it.link);
    out.push(it);
  }
  return out.slice(0, SHELF_MAX);
}
const asciiLower = (s: string) => s.replace(/[A-Z]/g, (c) => c.toLowerCase());

/** The parsed content of shelf.json to the items the shelf holds. Never throws. */
export function shelfClean(raw: unknown): ShelfItem[] {
  if (!isObject(raw)) return [];
  const items = own(raw, "items");
  if (!Array.isArray(items)) return [];
  return tidy(items.map(itemClean).filter((i): i is ShelfItem => i !== null));
}

/** Files dropped on the Shelf half. One word per incoming item; nothing already shelved is ever removed. */
export function shelfAdd(items: unknown, incoming: unknown): { items: ShelfItem[]; results: AddWord[] } {
  const current = shelfClean({ items });
  const ids = new Set(current.map((i) => asciiLower(i.id)));
  const links = new Set(current.flatMap((i) => (i.link !== undefined ? [i.link] : [])));
  const accepted: ShelfItem[] = [], results: AddWord[] = [];
  for (const raw of Array.isArray(incoming) ? incoming : []) {
    const it = itemClean(raw);
    if (it === null) results.push("invalid");
    else if (ids.has(asciiLower(it.id)) || (it.link !== undefined && links.has(it.link))) results.push("duplicate");
    else if (current.length + accepted.length >= SHELF_MAX) results.push("full");
    else {
      accepted.push(it);
      ids.add(asciiLower(it.id));
      if (it.link !== undefined) links.add(it.link);
      results.push("added");
    }
  }
  return { items: tidy([...accepted, ...current]), results };
}

/** The bytes of shelf.json to the items it holds. Unreadable bytes (not UTF-8, a BOM, NaN, text after the value, not an object) are an empty shelf. Never throws. */
export function readShelf(bytes: Uint8Array): ShelfItem[] {
  try {
    const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
    return shelfClean(JSON.parse(text));
  } catch {
    return [];
  }
}
EOF
```

- [ ] **Step 4: Run the tests and the types**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-rules.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: `# pass 9`, `# fail 0`, `tsc exit 0`, `ℹ tests 387`, `ℹ pass 387`, `ℹ fail 0`.

- [ ] **Step 5: Prove the rules bite**

Run:

```bash
cd windows
m() { python3 ../.claude/checkpoints/g1-tauri/mut.py src/shelf/rules.ts "$@"; }; T=scripts/cat-tests/shelf-rules.test.mjs
m 'px * 2 <= w ? "ask"' 'px * 2 < w ? "ask"' $T
m 'if (copy && folder) return null; // a folder is only ever a link' 'if (false) return null;' $T
m 'if (ids.has(idKey) || (it.link !== undefined && links.has(it.link))) continue;' 'if (ids.has(idKey)) continue;' $T
m 'else if (current.length + accepted.length >= SHELF_MAX)' 'else if (current.length + accepted.length > SHELF_MAX)' $T
m 'ignoreBOM: true' 'ignoreBOM: false' $T
m 'const BAD_NAME_CHAR = /[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]/u' 'const BAD_NAME_CHAR = /[\p{Cc}\p{Cs}\p{Zl}\p{Zp}]/u' $T
m 'return v === 0 ? 0 : v;' 'return v;' $T
cd ..
```

Expected: each line ends `# fail 1` or `# fail 2`: a fail count of at least 1 (the proofs for the centre line, the folder rule, the link duplicates, the full shelf, the byte order mark, a format character and minus zero all fail something).

- [ ] **Step 6: Commit**


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/src/shelf/rules.ts windows/scripts/cat-tests/shelf-rules.test.mjs
git commit -F - <<'MSG'
feat(shelf): the shelf contract's rules in TypeScript

zoneAt, shelfClean, shelfAdd and readShelf, replayed against every row of tests/fixtures/shelf/. Pure; the Windows and Linux app decides the half of a drop with zoneAt.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts printed above, the agent and the model.

---

# Stage 2: the store

### Task 3: The Rust twin and the store

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Create: `windows/src-tauri/src/shelf.rs`
- Modify: `windows/src-tauri/src/lib.rs`

**Interfaces:**
- Consumes: `settings::local_dir()`, `files::ingest`, `files::DroppedFile`, `serde_json` (with `preserve_order`, already there).
- Produces: `shelf::{Item, Entry, Store, MAX, clean, add_values, read, neutralize_lone_surrogates}`; `Store::{new, load, entries, add_paths, remove, clear, resolve, path_of}`; the commands `shelf_list`, `shelf_add(paths)`, `shelf_remove(id)`, `shelf_clear`, `shelf_ask(id)`. **`Entry` has no link: the page never learns a path.** Tasks 4, 8 and 9 use them.

**Why the Rust twin replays the same fixtures, and one trap.** The page's TypeScript and this file are two implementations of one rule; the fixtures keep them equal (`reference.py` decides). The trap: the fixture file itself holds lone surrogate escapes (`\ud800`), which are valid JSON text but which `serde_json` refuses, so a real `shelf.json` with one would make `serde_json` drop the **whole shelf** where the contract keeps the other items. `neutralize_lone_surrogates` turns each into a control character before parsing (an item with one in its name or link is dropped, as the contract says), and the test loads the fixture through it too. The format characters (category Cf) have no table in Rust's standard library, so `FORMAT_RANGES` lists them; it was checked against Unicode 16's Cf, range for range.

- [ ] **Step 1: Write the module, with its tests**

Rust has no separate red step here (the tests live in the file they test): the proof that they bite is Step 4.


```bash
mkdir -p windows/src-tauri/src
cat > windows/src-tauri/src/shelf.rs <<'EOF'
// The shelf (sub-project G1): files parked in the notch. Two halves in this file:
//
//  1. The contract's rules in Rust (`clean`, `add_values`, `read`), the twin of src/shelf/rules.ts. Both replay tests/fixtures/shelf/ (docs/SHELF-CONTRACT.md);
//     tests/fixtures/shelf/reference.py is the tie-breaker. `zoneAt` is not here: the page decides the half.
//  2. The store: `shelf.json` and the copies under the app's data folder. The page never holds a path: it holds ids, and every command that touches a file takes an id.
//
// Nothing here runs unless the user does something (a drop on the Shelf half, a click): no timer, no watcher, no poll. Whether the files still exist is looked at only when
// the shelf is listed (it opens).

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;
use serde_json::Value;

pub const MAX: usize = 30;
const NAME_MAX: usize = 255;
const LINK_MAX: usize = 8192;
const NUMBER_MAX: u64 = 9_007_199_254_740_991;
const ID_MAX: usize = 64;

/// One thing on the shelf, as the contract's `shelfClean` leaves it (fields in the contract's order). A copy has no link.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Item {
    pub id: String,
    pub name: String,
    pub size: u64,
    pub folder: bool,
    pub copy: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub link: Option<String>,
    pub added_at: u64,
}

// ── The rules ─────────────────────────────────────────────────────────────────

/// Unicode category Cf (format characters: the bidi controls, the zero-width space, the byte order mark). Rust's standard library has no table for it.
const FORMAT_RANGES: &[(u32, u32)] = &[
    (0x00AD, 0x00AD), (0x0600, 0x0605), (0x061C, 0x061C), (0x06DD, 0x06DD), (0x070F, 0x070F), (0x0890, 0x0891), (0x08E2, 0x08E2), (0x180E, 0x180E),
    (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x2064), (0x2066, 0x206F), (0xFEFF, 0xFEFF), (0xFFF9, 0xFFFB), (0x110BD, 0x110BD), (0x110CD, 0x110CD),
    (0x13430, 0x1343F), (0x1BCA0, 0x1BCA3), (0x1D173, 0x1D17A), (0xE0001, 0xE0001), (0xE0020, 0xE007F),
];

fn is_format(c: char) -> bool {
    let n = c as u32;
    FORMAT_RANGES.iter().any(|&(lo, hi)| n >= lo && n <= hi)
}

/// A name may not hold a control (Cc), a format character (Cf), a line or paragraph separator (Zl, Zp). (A lone surrogate, Cs, cannot be held by a Rust string at all.)
fn bad_name_char(c: char) -> bool {
    c.is_control() || is_format(c) || c == '\u{2028}' || c == '\u{2029}'
}

const RESERVED: &[&str] = &[
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    "COM\u{b9}", "COM\u{b2}", "COM\u{b3}", "LPT\u{b9}", "LPT\u{b2}", "LPT\u{b3}",
];

/// A Windows device name as the stem (the part before the first dot, trailing spaces trimmed), ASCII case-insensitively.
fn reserved(s: &str) -> bool {
    let stem = s.split('.').next().unwrap_or("").trim_end_matches(' ').to_ascii_uppercase();
    RESERVED.contains(&stem.as_str())
}

fn name_ok(name: &str) -> bool {
    let n = name.chars().count();
    if !(1..=NAME_MAX).contains(&n) {
        return false;
    }
    if name.chars().any(bad_name_char) || name.contains('/') || name.contains('\\') || name.chars().all(|c| c == '.') || name.ends_with('.') || name.ends_with(' ') {
        return false;
    }
    !reserved(name)
}

fn id_ok(id: &str) -> bool {
    (1..=ID_MAX).contains(&id.len()) && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') && !reserved(id)
}

/// A whole number from 0 to 2^53 - 1 (5 and 5.0 are the same JSON number), else 0.
fn whole(v: Option<&Value>) -> u64 {
    let Some(Value::Number(n)) = v else { return 0 };
    if let Some(u) = n.as_u64() {
        return if u <= NUMBER_MAX { u } else { 0 };
    }
    match n.as_f64() {
        Some(f) if f.is_finite() && f.fract() == 0.0 && f >= 0.0 && f <= NUMBER_MAX as f64 => f as u64,
        _ => 0,
    }
}

fn item_clean(raw: &Value) -> Option<Item> {
    let o = raw.as_object()?;
    let id = o.get("id")?.as_str()?;
    let name = o.get("name")?.as_str()?;
    if !id_ok(id) || !name_ok(name) {
        return None;
    }
    let copy = o.get("copy") == Some(&Value::Bool(true));
    let folder = o.get("folder") == Some(&Value::Bool(true));
    if copy && folder {
        return None; // a folder is only ever a link
    }
    let link = if copy {
        None
    } else {
        let link = o.get("link")?.as_str()?;
        let n = link.chars().count();
        if !(1..=LINK_MAX).contains(&n) || link.chars().any(|c| c.is_control()) {
            return None;
        }
        Some(link.to_string())
    };
    Some(Item { id: id.to_string(), name: name.to_string(), size: whole(o.get("size")), folder, copy, link, added_at: whole(o.get("addedAt")) })
}

/// Newest first (stable), then the first of each id (ASCII case-insensitive) and of each link (exact), then the first MAX. One pass in sorted order.
fn tidy(mut items: Vec<Item>) -> Vec<Item> {
    items.sort_by(|a, b| b.added_at.cmp(&a.added_at));
    let mut ids = std::collections::HashSet::new();
    let mut links = std::collections::HashSet::new();
    let mut out = Vec::new();
    for it in items {
        let key = it.id.to_ascii_lowercase();
        if ids.contains(&key) || it.link.as_ref().is_some_and(|l| links.contains(l)) {
            continue;
        }
        ids.insert(key);
        if let Some(l) = &it.link {
            links.insert(l.clone());
        }
        out.push(it);
    }
    out.truncate(MAX);
    out
}

/// The parsed content of shelf.json to the items the shelf holds. Never panics.
pub fn clean(raw: &Value) -> Vec<Item> {
    let Some(items) = raw.get("items").and_then(Value::as_array) else { return Vec::new() };
    tidy(items.iter().filter_map(item_clean).collect())
}

/// The result of one incoming item in a drop on the Shelf half.
pub type Word = &'static str;

/// Files dropped on the Shelf half: the new shelf and one word per incoming item (`added`, `duplicate`, `full` or `invalid`). Nothing already shelved is ever removed.
pub fn add_values(items: &Value, incoming: &Value) -> (Vec<Item>, Vec<Word>) {
    let current = clean(&serde_json::json!({ "items": items }));
    let mut ids: std::collections::HashSet<String> = current.iter().map(|i| i.id.to_ascii_lowercase()).collect();
    let mut links: std::collections::HashSet<String> = current.iter().filter_map(|i| i.link.clone()).collect();
    let mut accepted: Vec<Item> = Vec::new();
    let mut results: Vec<Word> = Vec::new();
    for raw in incoming.as_array().map(Vec::as_slice).unwrap_or(&[]) {
        match item_clean(raw) {
            None => results.push("invalid"),
            Some(it) if ids.contains(&it.id.to_ascii_lowercase()) || it.link.as_ref().is_some_and(|l| links.contains(l)) => results.push("duplicate"),
            Some(_) if current.len() + accepted.len() >= MAX => results.push("full"),
            Some(it) => {
                ids.insert(it.id.to_ascii_lowercase());
                if let Some(l) = &it.link {
                    links.insert(l.clone());
                }
                accepted.push(it);
                results.push("added");
            }
        }
    }
    accepted.extend(current);
    (tidy(accepted), results)
}

/// A JSON text with every lone surrogate escape (`\ud800` not followed by a low one, or a low one on its own) replaced by `\u0000`. serde_json refuses the whole file for one;
/// the contract keeps the other items, and an item with a control character in its name or link is dropped, which is what a lone surrogate there does.
pub fn neutralize_lone_surrogates(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let hex4 = |at: usize| -> Option<u32> {
        let s: String = chars.get(at..at + 4)?.iter().collect();
        if s.len() == 4 && s.chars().all(|c| c.is_ascii_hexdigit()) { u32::from_str_radix(&s, 16).ok() } else { None }
    };
    let mut out = String::with_capacity(text.len());
    let (mut i, mut in_string) = (0, false);
    while i < chars.len() {
        let c = chars[i];
        if in_string && c == '\\' && i + 1 < chars.len() {
            if chars[i + 1] == 'u' {
                if let Some(unit) = hex4(i + 2) {
                    let high = (0xD800..0xDC00).contains(&unit);
                    let low = (0xDC00..0xE000).contains(&unit);
                    let pair = high && chars.get(i + 6) == Some(&'\\') && chars.get(i + 7) == Some(&'u') && hex4(i + 8).is_some_and(|u| (0xDC00..0xE000).contains(&u));
                    if pair {
                        out.extend(&chars[i..i + 12]);
                        i += 12;
                    } else if high || low {
                        out.push_str("\\u0000");
                        i += 6;
                    } else {
                        out.extend(&chars[i..i + 6]);
                        i += 6;
                    }
                    continue;
                }
            }
            out.push(c);
            out.push(chars[i + 1]);
            i += 2;
            continue;
        }
        if c == '"' {
            in_string = !in_string;
        }
        out.push(c);
        i += 1;
    }
    out
}

/// The value of a shelf file's bytes, strictly: UTF-8 (a byte order mark is not stripped), no NaN or Infinity, nothing after the value. None when unreadable.
fn parse_strict(bytes: &[u8]) -> Option<Value> {
    let text = std::str::from_utf8(bytes).ok()?;
    serde_json::from_str(&neutralize_lone_surrogates(text)).ok()
}

/// The bytes of shelf.json to the items it holds. Unreadable bytes are an empty shelf. Never panics.
pub fn read(bytes: &[u8]) -> Vec<Item> {
    parse_strict(bytes).map(|v| clean(&v)).unwrap_or_default()
}

// ── The store ─────────────────────────────────────────────────────────────────

/// What the page gets for one item: no link (it is never shown, and the page never needs a path), and whether the original is gone.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub size: u64,
    pub folder: bool,
    pub copy: bool,
    pub added_at: u64,
    pub missing: bool,
}

/// One writer at a time: a drop and a Remove in the same instant cannot lose each other's change.
static LOCK: Mutex<()> = Mutex::new(());
static COUNTER: AtomicU64 = AtomicU64::new(0);

fn new_id() -> String {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    format!("s{:x}{:x}", nanos, COUNTER.fetch_add(1, Ordering::Relaxed))
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

pub struct Store {
    root: PathBuf,
}

impl Store {
    /// `root` is the app's data folder: `shelf.json` lives in it and copies under `shelf/<id>/<name>`.
    pub fn new(root: PathBuf) -> Store {
        Store { root }
    }

    fn file(&self) -> PathBuf {
        self.root.join("shelf.json")
    }

    fn copies(&self) -> PathBuf {
        self.root.join("shelf")
    }

    pub fn load(&self) -> Vec<Item> {
        std::fs::read(self.file()).map(|b| read(&b)).unwrap_or_default()
    }

    /// Writes the list. Before it overwrites a file it could not read, or one that held items the clean-up drops (a hand-edited or damaged file), the old bytes are kept as
    /// `shelf.json.bad-<ms>` (the contract). The write goes to a temporary file first, so a crash leaves the old file or the new one, never half of one.
    fn save(&self, items: &[Item]) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.root)?;
        let file = self.file();
        if let Ok(old) = std::fs::read(&file) {
            let kept = parse_strict(&old).map(|v| (clean(&v).len(), v.get("items").and_then(Value::as_array).map(Vec::len).unwrap_or(0)));
            let lossy = match kept {
                None => !old.is_empty(),
                Some((clean_len, raw_len)) => raw_len > clean_len,
            };
            if lossy {
                let _ = std::fs::write(self.root.join(format!("shelf.json.bad-{}", now_ms())), &old);
            }
        }
        let body = serde_json::to_vec(&serde_json::json!({ "version": 1, "items": items }))?;
        let tmp = self.root.join("shelf.json.tmp");
        std::fs::write(&tmp, body)?;
        std::fs::rename(&tmp, &file)
    }

    /// Where the item's file is: a copy under `shelf/<id>/<name>`, otherwise its original. None for a link that is not an absolute path.
    pub fn path_of(&self, item: &Item) -> Option<PathBuf> {
        if item.copy {
            return Some(self.copies().join(&item.id).join(&item.name));
        }
        let p = PathBuf::from(item.link.as_ref()?);
        p.is_absolute().then_some(p)
    }

    fn entries_of(&self, items: &[Item]) -> Vec<Entry> {
        items
            .iter()
            .map(|i| Entry {
                id: i.id.clone(),
                name: i.name.clone(),
                size: i.size,
                folder: i.folder,
                copy: i.copy,
                added_at: i.added_at,
                missing: self.path_of(i).map(|p| !p.exists()).unwrap_or(true),
            })
            .collect()
    }

    /// The shelf as it opens: every item, with whether its original is gone. The only place the files are looked at.
    pub fn entries(&self) -> Vec<Entry> {
        self.entries_of(&self.load())
    }

    /// The files of a Shelf drop. An item is built for each path that is an absolute path to something that exists with a name the contract allows; the rest are `invalid`.
    pub fn add_paths(&self, paths: &[String]) -> std::io::Result<(Vec<Entry>, Vec<Word>)> {
        let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let now = now_ms();
        let incoming: Vec<Value> = paths
            .iter()
            .map(|p| {
                let path = Path::new(p);
                let meta = if path.is_absolute() { std::fs::metadata(path).ok() } else { None };
                let name = path.file_name().map(|n| n.to_string_lossy().to_string());
                match (meta, name) {
                    (Some(m), Some(name)) => serde_json::json!({
                        "id": new_id(), "name": name, "size": if m.is_dir() { 0 } else { m.len() },
                        "folder": m.is_dir(), "copy": false, "link": p, "addedAt": now,
                    }),
                    _ => Value::Null,
                }
            })
            .collect();
        let current = self.load();
        let (items, results) = add_values(&serde_json::to_value(&current)?, &Value::Array(incoming));
        if results.contains(&"added") {
            self.save(&items)?;
        }
        Ok((self.entries_of(&items), results))
    }

    /// Takes one item off the shelf and deletes its copy, if it has one. Originals are never touched. An unknown id changes nothing.
    pub fn remove(&self, id: &str) -> std::io::Result<Vec<Entry>> {
        let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let current = self.load();
        let Some(gone) = current.iter().find(|i| i.id == id) else { return Ok(self.entries_of(&current)) };
        self.drop_copy(gone);
        let rest: Vec<Item> = current.iter().filter(|i| i.id != id).cloned().collect();
        self.save(&rest)?;
        Ok(self.entries_of(&rest))
    }

    /// Clear all: every copy goes, every original stays.
    pub fn clear(&self) -> std::io::Result<Vec<Entry>> {
        let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
        for item in self.load() {
            self.drop_copy(&item);
        }
        self.save(&[])?;
        Ok(Vec::new())
    }

    /// A copy lives in its own folder, `shelf/<id>/`, and the id is the contract's `[A-Za-z0-9_-]{1,64}`, so the folder cannot leave `shelf/`.
    fn drop_copy(&self, item: &Item) {
        if item.copy && id_ok(&item.id) {
            let _ = std::fs::remove_dir_all(self.copies().join(&item.id));
        }
    }

    /// The files of these ids that exist, in the order asked (a drag out, a share, Show in folder). An id that is not on the shelf or whose file is gone is left out.
    pub fn resolve(&self, ids: &[String]) -> Vec<PathBuf> {
        let items = self.load();
        ids.iter().filter_map(|id| items.iter().find(|i| &i.id == id)).filter_map(|i| self.path_of(i)).filter(|p| p.exists()).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn fixture(name: &str) -> Value {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/shelf").join(name);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        serde_json::from_str(&neutralize_lone_surrogates(&text)).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
    }

    fn as_value(items: &[Item]) -> Value {
        serde_json::to_value(items).unwrap()
    }

    fn temp(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("notchmeow-shelf-{tag}-{}-{}", std::process::id(), COUNTER.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn the_constants_are_the_fixtures() {
        let s = fixture("shelf-cases.json");
        assert_eq!(s["max"], MAX);
        assert_eq!(s["nameMax"], NAME_MAX);
        assert_eq!(s["linkMax"], LINK_MAX);
        assert_eq!(s["numberMax"], NUMBER_MAX);
        assert_eq!(s["idPattern"], format!("[A-Za-z0-9_-]{{1,{ID_MAX}}}"));
    }

    #[test]
    fn clean_replays_every_clean_case() {
        let s = fixture("shelf-cases.json");
        let cases = s["cleanCases"].as_array().unwrap();
        assert!(cases.len() >= 100);
        for c in cases {
            assert_eq!(as_value(&clean(&c["raw"])), c["out"], "{}", c["name"]);
        }
    }

    #[test]
    fn add_replays_every_add_case() {
        let s = fixture("shelf-cases.json");
        let cases = s["addCases"].as_array().unwrap();
        assert!(cases.len() >= 25);
        for c in cases {
            let (items, results) = add_values(&c["items"], &c["incoming"]);
            assert_eq!(serde_json::json!({ "items": items, "results": results }), c["out"], "{}", c["name"]);
        }
    }

    #[test]
    fn read_replays_every_parse_case() {
        let s = fixture("shelf-cases.json");
        let cases = s["parseCases"].as_array().unwrap();
        assert!(cases.len() >= 15);
        for c in cases {
            let bytes: Vec<u8> = match c.get("text").and_then(Value::as_str) {
                Some(t) => t.as_bytes().to_vec(),
                None => {
                    let hex = c["hex"].as_str().unwrap();
                    (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap()).collect()
                }
            };
            assert_eq!(as_value(&read(&bytes)), c["out"], "{}", c["name"]);
        }
    }

    #[test]
    fn a_lone_surrogate_costs_one_item_not_the_shelf_and_a_pair_survives() {
        let (hi, lo) = (format!("{}ud83d", '\\'), format!("{}ude00", '\\'));
        let text = format!(
            r#"{{"items":[{{"id":"a","name":"x\ud800y","copy":true,"addedAt":2}},{{"id":"b","name":"ok{hi}{lo}","copy":true,"addedAt":1}},{{"id":"c","name":"c.txt","link":"back\\ud800slash","addedAt":0}}]}}"#
        );
        let got = read(text.as_bytes());
        assert_eq!(got.iter().map(|i| i.id.as_str()).collect::<Vec<_>>(), ["b", "c"]);
        assert_eq!(got[0].name, "ok\u{1F600}");
        assert_eq!(got[1].link.as_deref(), Some("back\\ud800slash"), "an escaped backslash is not an escape");
    }

    #[test]
    fn the_format_table_is_the_contracts_examples() {
        for c in ['\u{202E}', '\u{200B}', '\u{FEFF}', '\u{00AD}', '\u{2066}'] {
            assert!(is_format(c), "{c:?}");
        }
        for c in ['a', 'é', '\u{2028}', '\u{3000}', '\u{1F600}'] {
            assert!(!is_format(c), "{c:?}");
        }
    }

    #[test]
    fn adding_files_keeps_them_in_the_order_dropped_refuses_what_cannot_be_shelved_and_stops_at_thirty() {
        let root = temp("add");
        let data = temp("files");
        let store = Store::new(root.clone());
        let paths: Vec<String> = (0..32)
            .map(|n| {
                let p = data.join(format!("f{n}.txt"));
                std::fs::write(&p, vec![b'x'; n]).unwrap();
                p.to_string_lossy().to_string()
            })
            .collect();
        let dir = data.join("a folder");
        std::fs::create_dir_all(&dir).unwrap();

        let mut drop = vec![paths[0].clone(), "relative/file.txt".to_string(), data.join("gone.txt").to_string_lossy().to_string(), dir.to_string_lossy().to_string()];
        drop.push(paths[0].clone());
        let (entries, words) = store.add_paths(&drop).unwrap();
        assert_eq!(words, ["added", "invalid", "invalid", "added", "duplicate"]);
        assert_eq!(entries.len(), 2);
        assert!(entries.iter().any(|e| e.folder && e.name == "a folder" && e.size == 0));
        assert!(entries.iter().all(|e| !e.missing));

        let (entries, words) = store.add_paths(&paths[1..].to_vec()).unwrap();
        assert_eq!(entries.len(), MAX, "the cap holds");
        assert_eq!(words.iter().filter(|w| **w == "added").count(), MAX - 2);
        assert_eq!(words.iter().filter(|w| **w == "full").count(), 31 - (MAX - 2));
        assert!(std::fs::read_to_string(root.join("shelf.json")).unwrap().contains("\"version\":1"));
        assert_eq!(store.load().len(), MAX, "it survives a restart (a new Store reads the same file)");
        assert_eq!(Store::new(root).load().len(), MAX);
    }

    #[test]
    fn a_missing_original_shows_as_missing_and_remove_never_touches_an_original() {
        let root = temp("missing");
        let data = temp("orig");
        let store = Store::new(root);
        let file = data.join("note.txt");
        std::fs::write(&file, b"hello").unwrap();
        let (entries, _) = store.add_paths(&[file.to_string_lossy().to_string()]).unwrap();
        let id = entries[0].id.clone();
        assert_eq!(store.resolve(&[id.clone(), "nope".into()]), vec![file.clone()]);
        std::fs::remove_file(&file).unwrap();
        assert!(store.entries()[0].missing, "looked at when the shelf is listed");
        assert!(store.resolve(&[id.clone()]).is_empty());
        std::fs::write(&file, b"back").unwrap();
        assert!(!store.entries()[0].missing);
        let after = store.remove(&id).unwrap();
        assert!(after.is_empty());
        assert_eq!(std::fs::read(&file).unwrap(), b"back", "the original is never touched");
        assert!(store.remove("unknown").unwrap().is_empty());
    }

    #[test]
    fn a_copy_resolves_under_shelf_id_name_and_removing_it_deletes_only_its_folder() {
        let root = temp("copy");
        let store = Store::new(root.clone());
        let folder = root.join("shelf").join("c1");
        std::fs::create_dir_all(&folder).unwrap();
        std::fs::write(folder.join("pic.png"), b"png").unwrap();
        let keep = root.join("shelf").join("c2");
        std::fs::create_dir_all(&keep).unwrap();
        std::fs::write(keep.join("keep.txt"), b"k").unwrap();
        let text = r#"{"version":1,"items":[{"id":"c1","name":"pic.png","size":3,"copy":true,"addedAt":2},{"id":"c2","name":"keep.txt","size":1,"copy":true,"addedAt":1}]}"#;
        std::fs::write(root.join("shelf.json"), text).unwrap();
        assert_eq!(store.resolve(&["c1".into()]), vec![folder.join("pic.png")]);
        store.remove("c1").unwrap();
        assert!(!folder.exists());
        assert!(keep.join("keep.txt").exists());
        store.clear().unwrap();
        assert!(!keep.exists());
        assert!(store.load().is_empty());
    }

    #[test]
    fn an_unreadable_or_trimmed_file_is_kept_as_a_backup_before_it_is_overwritten() {
        let root = temp("bad");
        let data = temp("badfiles");
        let store = Store::new(root.clone());
        let file = data.join("a.txt");
        std::fs::write(&file, b"a").unwrap();
        let bad = |root: &Path| std::fs::read_dir(root).unwrap().flatten().filter(|e| e.file_name().to_string_lossy().starts_with("shelf.json.bad-")).count();

        std::fs::write(root.join("shelf.json"), b"{\"items\": [").unwrap();
        store.add_paths(&[file.to_string_lossy().to_string()]).unwrap();
        assert_eq!(bad(&root), 1, "a truncated file is kept");

        let mut raw: Vec<Value> = (0..40).map(|n| serde_json::json!({ "id": format!("h{n}"), "name": "n", "link": format!("/p/{n}"), "addedAt": n })).collect();
        raw.push(Value::Null);
        std::fs::write(root.join("shelf.json"), serde_json::to_vec(&serde_json::json!({ "items": raw })).unwrap()).unwrap();
        store.remove("h39").unwrap();
        assert_eq!(bad(&root), 2, "a file with more than the clean-up keeps is kept before the cap trims it");

        let n = bad(&root);
        store.remove("nothing").unwrap();
        store.clear().unwrap();
        store.add_paths(&[file.to_string_lossy().to_string()]).unwrap();
        assert_eq!(bad(&root), n, "a file the store itself wrote is clean, so it never makes a backup");
    }
}
EOF
```

- [ ] **Step 2: Register the module and the commands**


```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src-tauri/src/lib.rs", [
('''mod secrets;
mod settings;
mod tray;
''', '''mod secrets;
mod settings;
mod shelf;
mod tray;
'''),
('''#[tauri::command]
fn secret_present(key: String) -> bool {''', '''// ── The shelf (sub-project G1) ────────────────────────────────────────────────
// The page holds ids, never paths: every command that touches a file takes an id and Rust finds the file. They run off the main thread, because looking at the files of a
// shelf (a network drive that went away) can take a while.

fn shelf_store() -> shelf::Store {
    shelf::Store::new(settings::local_dir())
}

async fn blocking<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work).await.map_err(|e| e.to_string())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ShelfAdded {
    entries: Vec<shelf::Entry>,
    /// One word per dropped path: `added`, `duplicate`, `full` or `invalid`.
    results: Vec<&'static str>,
}

/// The shelf as it opens, each item with whether its original is gone (the only time the files are looked at).
#[tauri::command]
async fn shelf_list() -> Result<Vec<shelf::Entry>, String> {
    blocking(|| shelf_store().entries()).await
}

#[tauri::command]
async fn shelf_add(paths: Vec<String>) -> Result<ShelfAdded, String> {
    let (entries, results) = blocking(move || shelf_store().add_paths(&paths)).await?.map_err(|e| e.to_string())?;
    Ok(ShelfAdded { entries, results })
}

#[tauri::command]
async fn shelf_remove(id: String) -> Result<Vec<shelf::Entry>, String> {
    blocking(move || shelf_store().remove(&id)).await?.map_err(|e| e.to_string())
}

#[tauri::command]
async fn shelf_clear() -> Result<Vec<shelf::Entry>, String> {
    blocking(|| shelf_store().clear()).await?.map_err(|e| e.to_string())
}

/// Ask: the shelf item goes into the inbox like a file dropped on Ask (the same screening, the same copy), and the page starts a new chat with it.
#[tauri::command]
async fn shelf_ask(id: String) -> Result<DroppedFile, String> {
    blocking(move || {
        let path = shelf_store().resolve(&[id]).into_iter().next().ok_or_else(|| "That file is gone.".to_string())?;
        files::ingest(&path.to_string_lossy())
    })
    .await?
}

#[tauri::command]
fn secret_present(key: String) -> bool {'''),
('''            drag_out_spike,
            secret_present,''', '''            drag_out_spike,
            shelf_list,
            shelf_add,
            shelf_remove,
            shelf_clear,
            shelf_ask,
            secret_present,'''),
])
print("applied")
PYEOF
```

Expected: `applied`

- [ ] **Step 3: Run the Rust tests (needs the image)**

Run:

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test -p notchmeow shelf:: --target-dir /repo/windows/target/g1-tauri 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok. 10 passed` for `shelf::`, no `error`, no `warning` (or the line saying the Rust is owed). The ten: the constants, 132 clean cases, 30 add cases, 18 parse cases, a lone surrogate, the format table, adding files, a missing original, a copy, and the backup.

- [ ] **Step 4: Prove the tests bite (needs the image)**

Each line changes one line of `shelf.rs`, runs `shelf::` and puts it back. A fail count of at least 1 is a bite.


```bash
cp windows/src-tauri/src/shelf.rs .claude/checkpoints/g1-tauri/shelf.rs.keep
for m in 's/neutralize_lone_surrogates(text)).ok()/text).ok()/' 's/>= MAX => results.push("full")/> MAX => results.push("full")/' 's/c.is_control() || is_format(c) || //'; do
  sed -i.bak "$m" windows/src-tauri/src/shelf.rs
  docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test -p notchmeow shelf:: --target-dir /repo/windows/target/g1-tauri 2>&1 | grep -E "^test result" | head -1
  cp .claude/checkpoints/g1-tauri/shelf.rs.keep windows/src-tauri/src/shelf.rs; trash windows/src-tauri/src/shelf.rs.bak
done
git diff --stat -- windows/src-tauri/src/shelf.rs | tail -1
```

Expected: three lines ending `1 failed`, `2 failed` and `3 failed` (the parse, the cap and the control and format characters; measured with a native `cargo test` in a scratch crate: 9 passed 1 failed, 8 passed 2 failed, 7 passed 3 failed), and no line from `git diff` (the file is back as it was; it is untracked, so nothing prints).

- [ ] **Step 5: Commit**


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/src-tauri/src/shelf.rs windows/src-tauri/src/lib.rs
git commit -F - <<'MSG'
feat(shelf): the Rust twin of the shelf contract and the store

shelf.rs replays shelf-cases.json (clean, add, parse) and keeps shelf.json: at most 30, a backup of an unreadable or trimmed file before it is overwritten, copies under shelf/<id>/, the originals never touched, an existence check only when the shelf is listed. The commands take ids; the page never learns a path.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the Rust test line (or that the image was missing), the agent and the model.

---

### Task 4: The page's shelf: store, backends, the bridge

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `windows/src/shelf/store.ts`, `windows/src/shelf/backend.ts`, `windows/scripts/cat-tests/shelf-store.test.mjs`
- Modify: `windows/src/core/bridge.ts`, `windows/src/core/state.ts`

**Interfaces:**
- Consumes: Task 2's `shelfAdd`, `AddWord`, `ShelfItem`; Task 3's commands.
- Produces: `interface ShelfEntry { id, name, size, folder, copy, addedAt, missing }`, `interface ShelfBackend { list, add, remove, clear }`, `shelfNote(results)`, `sizeLabel(bytes)`, `class ShelfStore { entries, selected, note, attach(backend), count, refresh(), add(paths), remove(id), clear(), toggle(id), targets(id), canAsk(id) }`; `bridgeBackend()`, `mockBackend(seed?, gone?)`; `Bridge.shelfList/shelfAdd/shelfRemove/shelfClear/shelfAsk`; `State.shelf`. **`store.ts` imports nothing of Tauri** (the plain-Node checks load it; `State` imports it).

- [ ] **Step 1: Write the test**


```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/shelf-store.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { ShelfStore, shelfNote, sizeLabel } from "../../src/shelf/store.ts";
import { SHELF_MAX } from "../../src/shelf/rules.ts";
import { State } from "../../src/core/state.ts";

// The page's shelf (G1): the list Rust last gave, the ticks and the note. The backend is faked; the in-memory one the browser uses runs the contract's own rules.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const entry = (id, over = {}) => ({ id, name: `${id}.txt`, size: 10, folder: false, copy: false, addedAt: 1, missing: false, ...over });
function fake(start = []) {
  let list = start;
  const calls = [];
  return {
    calls,
    list: async () => (calls.push("list"), list),
    add: async (paths) => (calls.push(["add", paths]), (list = [...paths.map((p, i) => entry(`n${list.length + i}`, { name: p })), ...list].slice(0, SHELF_MAX)), { entries: list, results: paths.map(() => "added") }),
    remove: async (id) => (calls.push(["remove", id]), (list = list.filter((e) => e.id !== id))),
    clear: async () => (calls.push("clear"), (list = [])),
  };
}

test("the note after a drop: nothing to say when every file went on, one sentence for what was left off", () => {
  assert.equal(shelfNote(["added", "duplicate"]), null);
  assert.match(shelfNote(["added", "full"]), /shelf is full \(30\)\. One file was left off/);
  assert.match(shelfNote(["full", "full", "added"]), /2 files were left off/);
  assert.match(shelfNote(["invalid"]), /can't go on the shelf/);
  assert.match(shelfNote(["full", "invalid"]), /full/, "full comes first");
});

test("sizes read like a file manager's, and a folder has none to show", () => {
  assert.deepEqual([0, 999, 1000, 12345, 3400000, 250000000, 5e12].map(sizeLabel), ["0 B", "999 B", "1 KB", "12.3 KB", "3.4 MB", "250 MB", "5 TB"]);
});

test("nothing is read until refresh, and a store with no backend does nothing", async () => {
  const s = new ShelfStore();
  assert.equal(s.count, 0);
  await s.refresh(); await s.add(["/a"]); await s.remove("x"); await s.clear();
  assert.equal(s.count, 0);
  const b = fake([entry("a")]);
  s.attach(b);
  assert.equal(b.calls.length, 0);
  await s.refresh();
  assert.deepEqual(b.calls, ["list"]);
  assert.equal(s.count, 1);
});

test("add, remove and clear take Rust's answer, tell the page, and drop ticks for items that are gone", async () => {
  let changes = 0;
  const s = new ShelfStore(() => changes++);
  s.attach(fake([entry("a"), entry("b"), entry("c")]));
  await s.refresh();
  s.toggle("a"); s.toggle("b");
  assert.deepEqual([...s.selected], ["a", "b"]);
  await s.remove("a");
  assert.deepEqual([...s.selected], ["b"]);
  assert.deepEqual(s.entries.map((e) => e.id), ["b", "c"]);
  const before = changes;
  assert.deepEqual(await s.add([]), [], "an empty drop asks nobody");
  assert.equal(changes, before);
  assert.deepEqual(await s.add(["/x/new.txt"]), ["added"]);
  assert.equal(s.entries[0].name, "/x/new.txt");
  await s.clear();
  assert.equal(s.count, 0);
  assert.equal(s.selected.size, 0);
  s.toggle("nobody");
  assert.equal(s.selected.size, 0, "an unknown id cannot be ticked");
});

test("a refused file leaves a note that the next change clears", async () => {
  const s = new ShelfStore();
  s.attach({ ...fake(), add: async () => ({ entries: [entry("a")], results: ["added", "full"] }) });
  await s.add(["/a", "/b"]);
  assert.match(s.note, /left off/);
  await s.remove("a");
  assert.equal(s.note, null);
});

test("Send and Show act on the ticked items when the tile is one of several, else on the tile; Ask is off with several ticked, for a folder and for a missing original", async () => {
  const s = new ShelfStore();
  s.attach(fake([entry("a"), entry("b"), entry("c", { folder: true }), entry("d", { missing: true })]));
  await s.refresh();
  assert.deepEqual(s.targets("a"), ["a"]);
  s.toggle("a");
  assert.deepEqual(s.targets("a"), ["a"], "one ticked is just that one");
  assert.equal(s.canAsk("b"), true);
  s.toggle("b");
  assert.deepEqual(s.targets("a"), ["a", "b"]);
  assert.deepEqual(s.targets("c"), ["c"], "a tile outside the ticks is only itself");
  assert.equal(s.canAsk("a"), false, "several ticked");
  s.toggle("b");
  assert.equal(s.canAsk("a"), true);
  assert.equal(s.canAsk("c"), false, "a folder");
  assert.equal(s.canAsk("d"), false, "a missing original");
  assert.equal(s.canAsk("zzz"), false);
});

test("State holds the shelf and notifies the island when it changes; the store imports nothing of Tauri", async () => {
  let n = 0;
  const off = State.subscribe(() => n++);
  State.shelf.attach(fake([entry("a")]));
  await State.shelf.refresh();
  off();
  assert.equal(n, 1);
  assert.doesNotMatch(source("shelf/store.ts"), /bridge|@tauri-apps/, "pure: the plain-Node checks load it");
  assert.match(source("core/state.ts"), /shelf = new ShelfStore\(\(\) => this\.notify\(\)\);/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-store.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ERR_MODULE_NOT_FOUND" | head -3
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 3: Write the store and the backends**

A class parameter property (`constructor(private x)`) is not allowed by Node's strip-only mode, so the store declares its field and assigns it.


```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/store.ts <<'EOF'
// The shelf as the island's page holds it (sub-project G1): the list Rust last gave, which items are selected, and the short note after a drop. The files themselves are Rust's
// (src-tauri/src/shelf.rs); the page holds ids and never a path. Pure and DOM-free: the backend is handed in, so the plain-Node checks fake it.

import type { AddWord } from "./rules.ts";

/** What Rust says about one item. No path: the page never needs one. `missing`: its original is gone (looked at when the shelf is listed, never in the background). */
export interface ShelfEntry {
  id: string;
  name: string;
  size: number;
  folder: boolean;
  copy: boolean;
  addedAt: number;
  missing: boolean;
}

export interface ShelfBackend {
  list(): Promise<ShelfEntry[]>;
  add(paths: string[]): Promise<{ entries: ShelfEntry[]; results: AddWord[] }>;
  remove(id: string): Promise<ShelfEntry[]>;
  clear(): Promise<ShelfEntry[]>;
}

/** The short note under the tray after a drop, or null when every file went on. */
export function shelfNote(results: readonly AddWord[]): string | null {
  const full = results.filter((w) => w === "full").length, invalid = results.filter((w) => w === "invalid").length;
  if (full > 0) return full === 1 ? "The shelf is full (30). One file was left off." : `The shelf is full (30). ${full} files were left off.`;
  if (invalid > 0) return invalid === 1 ? "One file can't go on the shelf." : `${invalid} files can't go on the shelf.`;
  return null;
}

/** "12 KB", "3.4 MB": the size under a name. Folders have none. */
export function sizeLabel(bytes: number): string {
  if (bytes < 1000) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let v = bytes / 1000, u = 0;
  while (v >= 1000 && u < units.length - 1) { v /= 1000; u++; }
  return `${v >= 100 || Number.isInteger(v) ? Math.round(v) : v.toFixed(1)} ${units[u]}`;
}

export class ShelfStore {
  entries: ShelfEntry[] = [];
  /** The ids ticked for Send. Ask is off while more than one is ticked. */
  selected = new Set<string>();
  /** Shown under the tray after a drop that left something off; cleared by the next change. */
  note: string | null = null;
  private backend: ShelfBackend | null = null;

  private readonly changed: () => void;

  constructor(changed: () => void = () => {}) { this.changed = changed; }

  /** Hand in the backend (Rust in the app, an in-memory one in the browser). Nothing is read until `refresh`. */
  attach(backend: ShelfBackend) { this.backend = backend; }

  get count(): number { return this.entries.length; }

  private set(entries: ShelfEntry[]) {
    this.entries = entries;
    const ids = new Set(entries.map((e) => e.id));
    for (const id of [...this.selected]) if (!ids.has(id)) this.selected.delete(id);
    this.changed();
  }

  /** Reads the shelf, and looks at whether the originals are still there (called when the shelf opens and at launch). */
  async refresh(): Promise<void> {
    if (this.backend) this.set(await this.backend.list());
  }

  /** The files of a drop on the Shelf half, in the order dropped. Returns the words, one per path. */
  async add(paths: string[]): Promise<AddWord[]> {
    if (!this.backend || paths.length === 0) return [];
    const { entries, results } = await this.backend.add(paths);
    this.note = shelfNote(results);
    this.set(entries);
    return results;
  }

  async remove(id: string): Promise<void> {
    if (!this.backend) return;
    this.note = null;
    this.set(await this.backend.remove(id));
  }

  async clear(): Promise<void> {
    if (!this.backend) return;
    this.note = null;
    this.set(await this.backend.clear());
  }

  toggle(id: string) {
    if (!this.entries.some((e) => e.id === id)) return;
    if (!this.selected.delete(id)) this.selected.add(id);
    this.changed();
  }

  /** Who a Send or Show on this tile is for: the ticked items when this one is among several ticked, else just this one. */
  targets(id: string): string[] {
    return this.selected.has(id) && this.selected.size > 1 ? this.entries.filter((e) => this.selected.has(e.id)).map((e) => e.id) : [id];
  }

  /** Ask hands one file to the chat: off while several are ticked, for a folder (the chat reads files) and for an item whose original is gone. */
  canAsk(id: string): boolean {
    const e = this.entries.find((x) => x.id === id);
    return !!e && !e.folder && !e.missing && this.selected.size <= 1;
  }
}
EOF
```

```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/backend.ts <<'EOF'
// The shelf's two backends (sub-project G1): Rust's commands inside the app, and a small in-memory shelf in a plain browser, so that `npm run dev` and the `?dev` page show the
// shelf working with no app behind it. The in-memory one runs the contract's own rules (rules.ts), so it refuses and caps exactly as Rust does.

import { Bridge } from "../core/bridge";
import { shelfAdd, type AddWord, type ShelfItem } from "./rules.ts";
import type { ShelfBackend, ShelfEntry } from "./store.ts";

/** Rust's commands. */
export function bridgeBackend(): ShelfBackend {
  return {
    list: async () => (await Bridge.shelfList()) ?? [],
    add: async (paths) => (await Bridge.shelfAdd(paths)) ?? { entries: [], results: [] },
    remove: async (id) => (await Bridge.shelfRemove(id)) ?? [],
    clear: async () => (await Bridge.shelfClear()) ?? [],
  };
}

/** A shelf in memory. `sizes` and `gone` let the `?dev` panel pick a size and mark an original as missing. */
export function mockBackend(seed: ShelfItem[] = [], gone: Set<string> = new Set()): ShelfBackend & { items: ShelfItem[]; gone: Set<string> } {
  let n = 0;
  const entries = (): ShelfEntry[] => self.items.map((i) => ({ id: i.id, name: i.name, size: i.size, folder: i.folder, copy: i.copy, addedAt: i.addedAt, missing: self.gone.has(i.id) }));
  const self = {
    items: [...seed],
    gone,
    list: async () => entries(),
    add: async (paths: string[]) => {
      const now = Date.now();
      const incoming = paths.map((p) => {
        const name = p.split(/[\\/]/).pop() ?? "";
        const folder = !name.includes(".");
        return { id: `m${now.toString(36)}${n++}`, name, size: folder ? 0 : (name.length * 7919) % 900000 + 1200, folder, copy: false, link: p, addedAt: now };
      });
      const res = shelfAdd(self.items, incoming);
      self.items = res.items;
      return { entries: entries(), results: res.results as AddWord[] };
    },
    remove: async (id: string) => { self.items = self.items.filter((i) => i.id !== id); return entries(); },
    clear: async () => { self.items = []; return entries(); },
  };
  return self;
}
EOF
```

- [ ] **Step 4: The bridge and `State`**


```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/core/bridge.ts", [
('''import type { DesktopWorld } from "../cat/desktopview";
''', '''import type { DesktopWorld } from "../cat/desktopview";
import type { AddWord } from "../shelf/rules";
import type { ShelfEntry } from "../shelf/store";
'''),
('''  /** Only ever tells you whether a key exists — never its value. */''', '''  // ── The shelf (sub-project G1): the page holds ids, Rust holds the paths ──────
  /** The shelf as it opens, each item with whether its original is gone. */
  shelfList: () => call<ShelfEntry[]>("shelf_list"),
  /** The files of a drop on the Shelf half: the new list and one word per path. */
  shelfAdd: (paths: string[]) => callOrThrow<{ entries: ShelfEntry[]; results: AddWord[] }>("shelf_add", { paths }),
  shelfRemove: (id: string) => callOrThrow<ShelfEntry[]>("shelf_remove", { id }),
  shelfClear: () => callOrThrow<ShelfEntry[]>("shelf_clear"),
  /** Ask: Rust copies the shelf item into the inbox like a drop on Ask, and the chat starts with it. */
  shelfAsk: (id: string) => callOrThrow<DroppedFile>("shelf_ask", { id }),
  /** Only ever tells you whether a key exists — never its value. */'''),
])
edit("windows/src/core/state.ts", [
('''import type { Kitten, KittenEvent } from "../cat/kittens.ts";
''', '''import type { Kitten, KittenEvent } from "../cat/kittens.ts";
import { ShelfStore } from "../shelf/store.ts";
'''),
('''  /** Where `giveCoats` takes its random numbers: `Math.random`, and a test's own. */''', '''  /** The shelf (sub-project G1): what Rust last said, the ticked items and the note after a drop. Empty until main.ts hands it a backend and reads it. */
  shelf = new ShelfStore(() => this.notify());

  /** Where `giveCoats` takes its random numbers: `Math.random`, and a test's own. */'''),
])
print("applied")
PYEOF
```

Expected: `applied`

- [ ] **Step 5: Run the checks**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-store.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: `# pass 7`, `# fail 0`, `tsc exit 0`, `ℹ tests 394`, `ℹ pass 394`, `ℹ fail 0`.

- [ ] **Step 6: Prove the store bites**

Run:

```bash
cd windows
m() { python3 ../.claude/checkpoints/g1-tauri/mut.py src/shelf/store.ts "$@"; }; T=scripts/cat-tests/shelf-store.test.mjs
m 'return this.selected.has(id) && this.selected.size > 1 ?' 'return this.selected.size > 1 ?' $T
m 'this.selected.size <= 1;' 'this.selected.size <= 2;' $T
m 'for (const id of [...this.selected]) if (!ids.has(id)) this.selected.delete(id);' '' $T
m 'if (full > 0)' 'if (invalid > 0)' $T
cd ..
```

Expected: each line ends with `# fail 1` or `# fail 2` (measured: 6 passed 1 failed, 6 passed 1 failed, 6 passed 1 failed, 5 passed 2 failed).

- [ ] **Step 7: Commit**


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/src/shelf/store.ts windows/src/shelf/backend.ts windows/scripts/cat-tests/shelf-store.test.mjs windows/src/core/bridge.ts windows/src/core/state.ts
git commit -F - <<'MSG'
feat(shelf): the page's shelf, its two backends and the bridge

ShelfStore holds Rust's last list, the ticks and the note after a drop, and knows who a Send acts on and when Ask is off. The backend is Rust's commands in the app and an in-memory shelf, running the contract's rules, in a browser. State holds the store.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, the agent and the model.

---

# Stage 3: the halves

### Task 5: The Ask and Shelf halves as a layer over today's drop, and the Shelf drop path

**Agent:** `nm-implementer` (Haiku 5.5, high). Also loads `playwright-cli`.

**Files:**
- Create: `windows/src/shelf/dropflow.ts`, `windows/src/shelf/zones.ts`, `windows/src/shelf/icons.ts`, `windows/scripts/cat-tests/shelf-dropflow.test.mjs`, `windows/scripts/cat-tests/shelf-drop.test.mjs`
- Modify: `windows/src/island/island.ts`, `windows/src/core/state.ts`, `windows/src/core/bridge.ts`, `windows/src/core/layout.ts`, `windows/src/views/views.ts`, `windows/src/main.ts`, `windows/src/style.css`

**Interfaces:**
- Consumes: Task 2's `zoneAt`, `Zone`; Task 4's `State.shelf`; the island's existing `whenCatIsHere`, `swallow`, `catchTurn`, `dropCount`, `UploadSeq`.
- Produces: `pointerX(PointerInput)`, `dropZone(PointerInput, islandWidth) -> Zone | null`, `planDrop(zone, paths) -> DropPlan`; `class ShelfZones { el, sync(on, hot) }`; `State.dropZone`; `Island.shelfDrop`, `Island.setCursorPoll`; the view name `"shelf"` with its `VIEW_LAYOUTS` entry (a placeholder view until Task 6). **Ask is today's drop line for line; `src/upload/*` and `src/views/upload.ts` are not edited.**

**The design in three lines.** (1) The half is the contract's `zoneAt` on the pointer: the cursor poll on Windows, the drag event's own position on Linux. (2) A drop on Ask runs the same two lines as before (`whenCatIsHere(() => swallow(path))`); a drop on Shelf takes all the files, takes a fresh token, stops the upload sequence and shows the shelf, with no wait. (3) The halves are one DOM layer over the drop canvas, `pointer-events: none`, only while files are dragged over the open drop view. The tray is see-through so the cat that follows the pointer onto it stays in sight; the right half dims the end of the Ask side's chips row (the centre line crosses it), which is the one visible cost of "Ask unchanged" and is looked at in Checkpoint 1.

- [ ] **Step 1: Write the tests**


```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/shelf-dropflow.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { dropZone, planDrop, pointerX } from "../../src/shelf/dropflow.ts";

// Which half a drop landed in and what it does (G1). The half itself is the contract's zoneAt (shelf-rules.test.mjs).
const win = { cursorPoll: true, polledX: 100, position: null, scale: 1.5, islandX: 40 };

test("with a global cursor (Windows) the polled x is the pointer, whatever position the event carried", () => {
  assert.equal(pointerX(win), 100);
  assert.equal(pointerX({ ...win, position: { x: 900, y: 10 } }), 100);
});

test("without one (Linux) the event's position is the pointer: physical px to CSS px, then from the island's left edge", () => {
  const lin = { ...win, cursorPoll: false, position: { x: 780, y: 10 } };
  assert.equal(pointerX(lin), 780 / 1.5 - 40);
  assert.equal(pointerX({ ...lin, position: null }), 100, "no position: the last polled x");
  assert.equal(pointerX({ ...lin, scale: 0 }), 100, "a scale that cannot divide is not used");
});

test("dropZone is the contract's rule on that pointer: the centre line is Ask, the right half Shelf, outside is null", () => {
  assert.equal(dropZone({ ...win, polledX: 320 }, 640), "ask");
  assert.equal(dropZone({ ...win, polledX: 320.5 }, 640), "shelf");
  assert.equal(dropZone({ ...win, polledX: 639 }, 640), "shelf");
  assert.equal(dropZone({ ...win, polledX: 100 }, 640), "ask");
  assert.equal(dropZone({ ...win, polledX: -2 }, 640), null);
  assert.equal(dropZone({ ...win, polledX: 641 }, 640), null);
  assert.equal(dropZone({ ...win, polledX: NaN }, 640), null);
  assert.equal(dropZone({ ...win, cursorPoll: false, position: { x: (40 + 400) * 1.5, y: 0 } }, 640), "shelf");
});

test("a drop on Ask takes the first file only; on Shelf all of them in order; outside both it is Ask's; no files is nothing", () => {
  const paths = ["/a.txt", "/b.txt", "/c.txt"];
  assert.deepEqual(planDrop("ask", paths), { kind: "ask", path: "/a.txt" });
  assert.deepEqual(planDrop("shelf", paths), { kind: "shelf", paths });
  assert.deepEqual(planDrop(null, paths), { kind: "ask", path: "/a.txt" });
  assert.deepEqual(planDrop("shelf", []), { kind: "none" });
  assert.deepEqual(planDrop("ask", undefined), { kind: "none" });
  const copy = planDrop("shelf", paths);
  copy.paths.push("/x");
  assert.equal(paths.length, 3, "the plan holds a copy");
});
EOF
```

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/shelf-drop.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The Ask and Shelf halves (G1) as the island wires them. The island needs the DOM and the bridge to run, so these are source pins; the rules they call are replayed in
// shelf-rules.test.mjs and shelf-dropflow.test.mjs, and the picture of the two halves is the checkpoint's.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const isl = source("island/island.ts");
const between = (s, a, b) => s.slice(s.indexOf(a), s.indexOf(b));

test("a drop on Ask is today's drop, line for line: the first file, then the catch waits for the desktop cat", () => {
  const drop = between(isl, 'case "drop": {', "/** Where the OS has no global cursor");
  assert.match(drop, /const plan = planDrop\(this\.zoneNow\(\), e\.paths\);/);
  assert.match(drop, /const path = plan\.path;\s*this\.whenCatIsHere\(\(\) => this\.swallow\(path\)\);/);
  assert.match(drop, /if \(plan\.kind === "none"\) \{\s*this\.setView\(State\.defaultView\(\)\);\s*return;\s*\}/, "no file: the same fall back as before");
  assert.match(isl, /private swallow\(path: string\) \{\s*const name = path\.split/, "swallow still takes one path");
});

test("a drop on Shelf takes every file, skips the desktop cat's wait and the catch, takes a fresh drop token and stops the upload sequence", () => {
  const shelf = isl.match(/private shelfDrop\(paths: string\[\]\) \{[\s\S]*?\n  \}\n/)[0];
  assert.doesNotMatch(shelf, /whenCatIsHere|swallow|engine\.triggerEmote|uploadCanvas\.drop|Sound\.play/, "no wait, no catch, no chime");
  assert.match(shelf, /this\.catchTurn\+\+;\s*this\.dropCount\+\+;\s*this\.dropWaiting = false;\s*UploadSeq\.deactivate\(\);\s*this\.uploadCanvas\.hover\(false\);\s*this\.setView\("shelf"\);\s*void State\.shelf\.add\(paths\);/);
  assert.match(isl, /if \(plan\.kind === "shelf"\) \{\s*this\.shelfDrop\(plan\.paths\);\s*return;\s*\}/);
});

test("the file alert ends with the drag: a drop or a leave clears the drag and the half, and fileCatch reads the drop flow, which the shelf view is not in", () => {
  assert.match(isl, /State\.fileDragOver = false;\s*State\.dropZone = null;\s*\/\/ The island deliberately stays open/, "leave");
  assert.match(isl, /State\.fileDragOver = false;\s*State\.dropZone = null;\s*if \(plan\.kind === "none"\)/, "drop");
  assert.match(isl, /State\.fileCatch = \(\) => State\.fileDragOver \|\| this\.dropWaiting \|\| this\.uploadActive;/, "unchanged");
  assert.match(isl, /const UPLOAD_VIEWS: ReadonlySet<IslandViewName> = new Set\(\["upload", "uploading", "choose"\]\);/, "the shelf view is not an upload view");
});

test("the halves are a layer over the drop canvas and change nothing of it: the canvas, the sequence and the upload views do not know the shelf", () => {
  for (const f of ["upload/canvas.ts", "upload/sequence.ts", "views/upload.ts"]) assert.doesNotMatch(source(f), /shelf/i, f);
  assert.match(isl, /this\.uploadCanvas\.el,\s*this\.zones\.el,\s*this\.contentEl,/, "the layer sits right over the canvas, under the header's content");
  assert.match(isl, /this\.zones\.sync\(uploadActive && State\.fileDragOver, State\.dropZone\);/, "only while files are dragged over the open drop view");
  const z = source("shelf/zones.ts");
  assert.doesNotMatch(z, /setInterval|setTimeout|requestAnimationFrame|addEventListener/, "it draws nothing by itself and takes no mouse");
  assert.match(fs.readFileSync(new URL("../../src/style.css", import.meta.url), "utf8"), /#shelf-zones \{[^}]*pointer-events: none;/);
});

test("the pointer's half follows the cursor poll while files are over the island, and is read again at the drop; where there is no global cursor the event's position is the pointer", () => {
  assert.match(isl, /UploadSeq\.updateCursor\(State\.mouseInIsland\.x, State\.mouseInIsland\.y\);\s*this\.trackZone\(\);/);
  assert.match(isl, /case "over": \{\s*this\.noteDragPosition\(e\.position\);\s*if \(State\.fileDragOver\) return;/);
  assert.match(isl, /private trackZone\(\) \{\s*const zone = State\.fileDragOver \? this\.zoneNow\(\) : null;\s*if \(zone === State\.dropZone\) return;/, "only a change is announced");
  assert.match(source("main.ts"), /island\.setCursorPoll\(boot \? boot\.cursorPoll : true\);/);
});

test("the shelf is a view of the island with a place of its own, not an upload view", async () => {
  const L = await import("../../src/core/layout.ts");
  assert.deepEqual(L.VIEW_LAYOUTS.shelf, { height: 176, botX: 46, botY: 108, botDiameter: 44, agentMode: "none" });
  assert.equal(L.islandSize("expanded", "shelf").h, 176);
  assert.match(source("views/views.ts"), /map\.set\("shelf", /);
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-dropflow.test.mjs scripts/cat-tests/shelf-drop.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
cd ..
```

Expected: `# fail` greater than 0 (the dropflow file cannot load; the island's source has no second branch).

- [ ] **Step 3: Write the pure rule, the layer and the icons**


```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/dropflow.ts <<'EOF'
// Which half a drop landed in, and what it does (sub-project G1). Pure, so the plain-Node checks load it.
//
// The drop event carries the paths, and the pointer's position in the webview's physical pixels. Windows has a global cursor (the island's own poll), which keeps the position
// the drop sequence already follows; Linux/Wayland has none, so the event's own position is the pointer. One rule turns either into the contract's `zoneAt(x, width)`.

import { zoneAt, type Zone } from "./rules.ts";

export interface PointerInput {
  /** The OS has a global cursor (Windows): `polledX` is the pointer. Otherwise the drag event's own `position` is. */
  cursorPoll: boolean;
  /** The pointer's x from the island's left edge, as the cursor poll last reported it (CSS px). */
  polledX: number;
  /** The drag event's position in the webview's physical pixels, when it had one. */
  position?: { x: number; y: number } | null;
  /** CSS px to physical px (the page's `devicePixelRatio`). */
  scale: number;
  /** The island's left edge in the window (CSS px). */
  islandX: number;
}

/** The pointer's x from the island's left edge, in CSS px. */
export function pointerX(i: PointerInput): number {
  if (!i.cursorPoll && i.position && i.scale > 0) return i.position.x / i.scale - i.islandX;
  return i.polledX;
}

/** The contract's rule on the pointer: "ask", "shelf", or null outside the island. */
export function dropZone(i: PointerInput, islandWidth: number): Zone | null {
  return zoneAt(pointerX(i), islandWidth);
}

export type DropPlan = { kind: "ask"; path: string } | { kind: "shelf"; paths: string[] } | { kind: "none" };

/** What a drop does. Ask takes the first file only, as it always has. Shelf takes them all. A drop outside both halves is Ask's, the drop that exists today. */
export function planDrop(zone: Zone | null, paths: readonly string[] | undefined): DropPlan {
  if (!paths || paths.length === 0) return { kind: "none" };
  return zone === "shelf" ? { kind: "shelf", paths: [...paths] } : { kind: "ask", path: paths[0] };
}
EOF
```

```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/zones.ts <<'EOF'
// The two halves of the drop view (sub-project G1): Ask on the left, Shelf on the right, split at the island's centre line. This is a layer ON TOP of the drop canvas
// (upload/canvas.ts), never a change to it: the canvas, the drop sequence and the views stay exactly as they were, and the layer only exists while files are dragged over the open
// island. It takes no mouse (the OS drag does). The half that is hot is the one the pointer is in (State.dropZone, from the contract's zoneAt).

import { h, svg } from "../views/dom";
import { SHELF_ICONS } from "./icons.ts";
import type { Zone } from "./rules.ts";

/** The drop canvas' card, in the island's px (upload/sequence.ts USC): the Shelf half is the right half of it. */
const CARD = { x: 10, y: 42, w: 620, h: 124 } as const;
export const CENTRE_X = 320;

export class ShelfZones {
  readonly el: HTMLElement;

  constructor() {
    const ask = h("div", { class: "sz-chip sz-ask", text: "Ask" });
    // The cat follows the pointer onto the tray, so the words sit at the edges and the icon in the middle is faint: the cat stays in sight.
    const shelf = h(
      "div",
      { class: "sz-shelf" },
      h("div", { class: "sz-chip sz-name", text: "Shelf" }),
      h("div", { class: "sz-icon" }, svg(SHELF_ICONS.tray, 30, { stroke: 1.4 })),
      h("div", { class: "sz-sub", text: "Keep it here, drag it out later" }),
    );
    this.el = h("div", { id: "shelf-zones" }, ask, shelf);
    this.el.style.setProperty("--sz-x", `${CENTRE_X}px`);
    this.el.style.setProperty("--sz-y", `${CARD.y}px`);
    this.el.style.setProperty("--sz-w", `${CARD.x + CARD.w - CENTRE_X}px`);
    this.el.style.setProperty("--sz-h", `${CARD.h}px`);
  }

  /** `on`: files are being dragged over the open drop view; `hot`: the half the pointer is in. */
  sync(on: boolean, hot: Zone | null) {
    this.el.classList.toggle("on", on);
    this.el.dataset.hot = hot ?? "";
  }
}
EOF
```

```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/icons.ts <<'EOF'
// The shelf's few icons: stroke paths on a 24x24 grid, drawn with svg(path, size, { stroke }). Own file so no shipping icon list changes.

export const SHELF_ICONS = {
  // an open tray
  tray: "M22 12h-6l-2 3h-4l-2-3H2M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z",
  // a sheet with a folded corner
  file: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5",
  // a folder
  folder: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z",
  // a paper plane
  send: "M21 3 10 14M21 3l-7 18-4-7-7-4z",
  // a folder with an arrow out
  reveal: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM12 15v-5M9.5 12.5 12 10l2.5 2.5",
  // a speech bubble
  ask: "M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z",
  // a cross
  remove: "M6 6l12 12M18 6 6 18",
  // a tick
  check: "M5 12.5 10 17.5 19 7",
} as const;
EOF
```

- [ ] **Step 4: Wire the island: the two branches of the drop, the layer, the view's name**

The view `shelf` needs a name and a place (`layout.ts`) and, until Task 6, a placeholder card (`views.ts`).


```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/core/state.ts", [
('import { ShelfStore } from "../shelf/store.ts";\n', 'import { ShelfStore } from "../shelf/store.ts";\nimport type { Zone } from "../shelf/rules.ts";\n'),
('  fileDragOver = false;', '  fileDragOver = false;\n  /** Files are dragged over the open drop view: the half the pointer is in (Ask or Shelf), or null outside the island (shelf/dropflow.ts). */\n  dropZone: Zone | null = null;'),
])
edit("windows/src/core/bridge.ts", [
('''export interface DragDropPayload {
  type: "enter" | "over" | "drop" | "leave";
  paths?: string[];
}''', '''export interface DragDropPayload {
  type: "enter" | "over" | "drop" | "leave";
  paths?: string[];
  /** The pointer in the webview's physical pixels (Tauri sends it with enter, over and drop). The half of the drop view is decided from it where the OS has no global cursor. */
  position?: { x: number; y: number };
}'''),
])

edit("windows/src/island/island.ts", [
# imports
('''import { UploadCanvas } from "../upload/canvas";
''', '''import { UploadCanvas } from "../upload/canvas";
import { dropZone, planDrop } from "../shelf/dropflow";
import { ShelfZones } from "../shelf/zones";
import type { Zone } from "../shelf/rules";
'''),
# fields
('''  private uploadCanvas!: UploadCanvas;
''', '''  private uploadCanvas!: UploadCanvas;
  /** The Ask and Shelf halves of the drop view: a layer over the drop canvas, never a change to it (sub-project G1). */
  private zones!: ShelfZones;
  /** The OS has a global cursor, so `State.mouseInIsland` is the pointer during a drag (Windows). Where it has none (Wayland) the drag event's own position is. */
  private cursorPoll = true;
  /** The last position a drag event carried (physical px of the webview). */
  private dragPos: { x: number; y: number } | null = null;
'''),
# build
('''    this.clipEl = h(
      "div",
      { id: "island-clip" },
      this.greetingCanvas,
      this.uploadCanvas.el,
      this.contentEl,
    );''', '''    this.zones = new ShelfZones();
    this.clipEl = h(
      "div",
      { id: "island-clip" },
      this.greetingCanvas,
      this.uploadCanvas.el,
      this.zones.el,
      this.contentEl,
    );'''),
# geometry
('''    this.uploadCanvas.el.style.left = `${(w - EXPANDED_W) / 2}px`;
''', '''    this.uploadCanvas.el.style.left = `${(w - EXPANDED_W) / 2}px`;
    this.zones.el.style.left = `${(w - EXPANDED_W) / 2}px`;
'''),
# drag handler
('''  private onDragDrop(e: { type: string; paths?: string[] }) {
    if (e.type !== "over") void Bridge.log(`drag ${e.type} ${e.paths?.length ?? 0} file(s)`);
    if (State.paused) return;
    switch (e.type) {
      case "enter":
      case "over": {
        if (State.fileDragOver) return;
        State.fileDragOver = true;''', '''  private onDragDrop(e: { type: string; paths?: string[]; position?: { x: number; y: number } }) {
    if (e.type !== "over") void Bridge.log(`drag ${e.type} ${e.paths?.length ?? 0} file(s)`);
    if (State.paused) return;
    switch (e.type) {
      case "enter":
      case "over": {
        this.noteDragPosition(e.position);
        if (State.fileDragOver) return;
        State.fileDragOver = true;'''),
('''        State.fileDragOver = false;
        // The island deliberately stays open: the drag session is still alive.
        UploadSeq.exitZone();
        this.uploadCanvas.hover(false);
        State.notify();
        break;
      }
      case "drop": {
        State.fileDragOver = false;
        const path = e.paths?.[0];
        if (!path) {
          this.setView(State.defaultView());
          return;
        }
        this.whenCatIsHere(() => this.swallow(path));
        break;
      }
    }
  }
''', '''        State.fileDragOver = false;
        State.dropZone = null;
        // The island deliberately stays open: the drag session is still alive.
        UploadSeq.exitZone();
        this.uploadCanvas.hover(false);
        State.notify();
        break;
      }
      case "drop": {
        // The half the pointer is in decides (shelf/dropflow.ts, the contract's zoneAt). Ask is today's drop, line for line; Shelf takes all the files and never waits for the desktop cat.
        this.noteDragPosition(e.position);
        const plan = planDrop(this.zoneNow(), e.paths);
        State.fileDragOver = false;
        State.dropZone = null;
        if (plan.kind === "none") {
          this.setView(State.defaultView());
          return;
        }
        if (plan.kind === "shelf") {
          this.shelfDrop(plan.paths);
          return;
        }
        const path = plan.path;
        this.whenCatIsHere(() => this.swallow(path));
        break;
      }
    }
  }

  /** Where the OS has no global cursor the pointer is the drag event's position; the pointer's half follows it. */
  private noteDragPosition(position: { x: number; y: number } | undefined) {
    this.dragPos = position ?? null;
    this.trackZone();
  }

  /** The half of the open island the pointer is in now (null outside it). */
  private zoneNow(): Zone | null {
    const rect = this.islandRect();
    return dropZone({ cursorPoll: this.cursorPoll, polledX: State.mouseInIsland.x, position: this.dragPos, scale: window.devicePixelRatio || 1, islandX: rect.x }, rect.w);
  }

  /** While files are dragged over the island the hot half follows the pointer; only a change is announced. */
  private trackZone() {
    const zone = State.fileDragOver ? this.zoneNow() : null;
    if (zone === State.dropZone) return;
    State.dropZone = zone;
    State.notify();
  }

  /** Whether the OS has a global cursor (Boot's `cursorPoll`). */
  setCursorPoll(on: boolean) {
    this.cursorPoll = on;
  }

  /**
   * Files dropped on the Shelf half (sub-project G1). The drop takes a fresh token, so an Ask drop still waiting for the desktop cat never runs and never clears this alert, and an Ask
   * file still being copied shows no note over the shelf. It does not wait for the desktop cat and nothing catches it: the upload sequence stops, the file alert is over
   * (`State.fileCatch` is false once the flow is left, so the desktop cat goes back by its normal rule), and the island shows the shelf.
   */
  private shelfDrop(paths: string[]) {
    this.catchTurn++;
    this.dropCount++;
    this.dropWaiting = false;
    UploadSeq.deactivate();
    this.uploadCanvas.hover(false);
    this.setView("shelf");
    void State.shelf.add(paths);
    State.notify();
  }
'''),
# cursor
('''    if (UploadSeq.isActive && !UploadSeq.dropped) {
      UploadSeq.updateCursor(State.mouseInIsland.x, State.mouseInIsland.y);
    }''', '''    if (UploadSeq.isActive && !UploadSeq.dropped) {
      UploadSeq.updateCursor(State.mouseInIsland.x, State.mouseInIsland.y);
      this.trackZone();
    }'''),
# frame
('''    this.uploadCanvas.el.classList.toggle("on", uploadActive);
''', '''    this.uploadCanvas.el.classList.toggle("on", uploadActive);
    this.zones.sync(uploadActive && State.fileDragOver, State.dropZone);
'''),
])

edit("windows/src/main.ts", [
('''import { registerIntegrationHandlers, refreshConfigured } from "./island/integrations";
''', '''import { registerIntegrationHandlers, refreshConfigured } from "./island/integrations";
import { bridgeBackend, mockBackend } from "./shelf/backend";
'''),
('''  if (boot && !boot.cursorPoll) island.followPageCursor();
''', '''  island.setCursorPoll(boot ? boot.cursorPoll : true);
  if (boot && !boot.cursorPoll) island.followPageCursor();
  // The shelf (sub-project G1): Rust's store inside the app, a small one in memory in a plain browser. Read once at launch, so the badge knows the count.
  State.shelf.attach(IS_TAURI ? bridgeBackend() : mockBackend());
  void State.shelf.refresh();
'''),
])
print("applied")

# The view name and its place, so the shelf can be shown: the real view is Task 6, a placeholder until then.
edit("windows/src/core/layout.ts", [
('''  | "settings"
  | "greeting";''', '''  | "settings"
  | "shelf"
  | "greeting";'''),
('''  settings: { height: 160, botX: 54, botY: null, botDiameter: 46, agentMode: "none" },
''', '''  settings: { height: 160, botX: 54, botY: null, botDiameter: 46, agentMode: "none" },
  // The shelf (sub-project G1): the cat small at the left, the tray's tiles to its right.
  shelf: { height: 176, botX: 46, botY: 108, botDiameter: 44, agentMode: "none" },
'''),
])
edit("windows/src/views/views.ts", [
('''  map.set("choose", buildChoose(actions));
''', '''  map.set("choose", buildChoose(actions));
  map.set("shelf", buildPlaceholder("Shelf", ""));
'''),
])
print("layout and placeholder applied")
PYEOF
```

Expected: `applied`, `applied`, `layout and placeholder applied` (the script's three prints).

```bash
cat >> windows/src/style.css <<'EOF'

/* ── The shelf (sub-project G1) ─────────────────────────────────────────── */

/* The two halves of the drop view: a layer over the drop canvas, only while files are dragged over the open island. The canvas under it is untouched. */
#shelf-zones {
  position: absolute;
  top: 0;
  left: 0;
  width: 640px;
  height: 176px;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.15s ease-in-out;
}

#shelf-zones.on {
  opacity: 1;
}

.sz-chip {
  position: absolute;
  left: 24px;
  top: 50px;
  padding: 2px 9px;
  border-radius: 9px;
  font-size: 11px;
  font-weight: 500;
  color: #b9bdc4;
  background: rgba(255, 255, 255, 0.07);
  transition: color 0.15s, background 0.15s;
}

#shelf-zones[data-hot="ask"] .sz-ask {
  color: #07130e;
  background: #34d399;
}

.sz-shelf {
  position: absolute;
  left: var(--sz-x);
  top: var(--sz-y);
  width: var(--sz-w);
  height: var(--sz-h);
  border-radius: 0 20px 20px 0;
  /* See-through, so the cat that follows the pointer onto the tray stays in sight. */
  background: rgba(13, 14, 16, 0.5);
  border: 1.5px dashed rgba(255, 255, 255, 0.14);
  color: #d5d7db;
  transition: border-color 0.15s, background 0.15s;
}

#shelf-zones[data-hot="shelf"] .sz-shelf {
  border-color: rgba(52, 212, 153, 0.55);
  background: rgba(16, 40, 30, 0.4);
}

.sz-shelf .sz-name {
  left: 14px;
  top: 7px;
}

#shelf-zones[data-hot="shelf"] .sz-name {
  color: #07130e;
  background: #34d399;
}

.sz-icon {
  position: absolute;
  left: 50%;
  top: 38px;
  transform: translateX(-50%);
  display: flex;
  color: #9398a1;
  opacity: 0.4;
}

#shelf-zones[data-hot="shelf"] .sz-icon {
  color: #34d399;
}

.sz-sub {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 7px;
  text-align: center;
  font-size: 11px;
  color: #8e939c;
}
EOF
```

- [ ] **Step 5: Run the checks**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-dropflow.test.mjs scripts/cat-tests/shelf-drop.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
git diff --stat -- windows/src/upload windows/src/views/upload.ts windows/src/views/icons.ts | tail -1
```

Expected: `# pass 10`, `# fail 0`, `tsc exit 0`, `ℹ tests 404`, `ℹ pass 404`, `ℹ fail 0`, and **nothing** from the last line (the drop canvas, the sequence and the upload views are byte for byte as they were).

- [ ] **Step 6: Prove the island's two branches bite**

Run:

```bash
cd windows
m() { python3 ../.claude/checkpoints/g1-tauri/mut.py src/island/island.ts "$@"; }; T=scripts/cat-tests/shelf-drop.test.mjs
m 'this.catchTurn++;
    this.dropCount++;' 'this.dropCount++;' $T
m 'this.shelfDrop(plan.paths);' 'this.whenCatIsHere(() => this.shelfDrop(plan.paths));' $T
m '    UploadSeq.deactivate();
    this.uploadCanvas.hover(false);
    this.setView("shelf");' '    this.setView("shelf");' $T
m 'this.zones.sync(uploadActive && State.fileDragOver, State.dropZone);' 'this.zones.sync(uploadActive, State.dropZone);' $T
m 'const plan = planDrop(this.zoneNow(), e.paths);' 'const plan = planDrop("shelf", e.paths);' $T
m() { python3 ../.claude/checkpoints/g1-tauri/mut.py src/shelf/dropflow.ts "$@"; }
m 'return zone === "shelf" ? { kind: "shelf", paths: [...paths] }' 'return zone !== "ask" ? { kind: "shelf", paths: [...paths] }' scripts/cat-tests/shelf-dropflow.test.mjs
m 'if (!i.cursorPoll && i.position && i.scale > 0)' 'if (i.position && i.scale > 0)' scripts/cat-tests/shelf-dropflow.test.mjs
cd ..
```

Expected: every line ends with `# fail 1` or higher.

- [ ] **Step 7: Look at it in the dev island** (a browser stands in for the OS's drag: it calls the island's own drop handler with the events Tauri would send)

Start the dev server (the block in "How to run this plan"), then:


```bash
S=g1-drop; cd .claude/checkpoints/g1-tauri
pw() { playwright-cli -s="$S" "$@"; }
ev() { pw eval "$1" 2>&1 | grep -A1 "### Result" | tail -1; }
pw open 'http://127.0.0.1:14631/' > /dev/null 2>&1; pw resize 760 360 > /dev/null 2>&1; sleep 7
ev "(() => { window.__nm.island.alert('overview'); return window.__nm.State.view; })()"
sleep 2
ev "(() => { const {island, State} = window.__nm; island.onDragDrop({type:'enter', paths:['C:/a.pdf','C:/b.txt']}); island.onCursor(40+500, 90); return JSON.stringify([State.fileDragOver, State.dropZone, State.view]); })()"
sleep 1.8
ev "(() => { const {island, State} = window.__nm; island.onCursor(40+100, 90); return JSON.stringify([State.dropZone]); })()"
pw screenshot --filename="$(pwd)/drag-ask-hot.png" > /dev/null 2>&1
ev "(() => { const {island, State} = window.__nm; island.onCursor(40+500, 90); return JSON.stringify([State.dropZone]); })()"
sleep 0.5
pw screenshot --filename="$(pwd)/drag-shelf-hot.png" > /dev/null 2>&1
ev "(() => { const {island, State} = window.__nm; island.onDragDrop({type:'drop', paths:['C:/a.pdf','C:/b.txt']}); return JSON.stringify([State.fileDragOver, State.dropZone, State.view]); })()"
sleep 0.6
ev "(() => { const {State} = window.__nm; return JSON.stringify([State.view, State.shelf.count, State.shelf.entries.map(e=>e.name)]); })()"
pw console 2>&1 | grep '\[ERROR\]' | grep -vc favicon
pw close > /dev/null 2>&1
cd ../..
```

Expected: `"overview"`, `"[true,\"shelf\",\"upload\"]"` (files over the right half: Shelf is hot), `"[\"ask\"]"` (over the left), `"[\"shelf\"]"`, `"[false,null,\"shelf\"]"` (the drop on Shelf: the drag is over, the half is cleared, the view is the shelf), `"[\"shelf\",2,[\"a.pdf\",\"b.txt\"]]"` (both files were shelved, in the order dropped, and the island shows the shelf) and `0` (no console error besides the favicon's). Open `drag-ask-hot.png` and `drag-shelf-hot.png` and say what you see: the **Ask** chip lit and the cat under the pointer on the left; the **Shelf** chip lit, the tray's border green, the cat still in sight over the tray, and the Ask side's chips row ending at the centre line. A blank or broken picture is a failed step.

- [ ] **Step 8: Commit**


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/src/shelf/dropflow.ts windows/src/shelf/zones.ts windows/src/shelf/icons.ts windows/scripts/cat-tests/shelf-dropflow.test.mjs windows/scripts/cat-tests/shelf-drop.test.mjs windows/src/island/island.ts windows/src/core/state.ts windows/src/core/bridge.ts windows/src/core/layout.ts windows/src/views/views.ts windows/src/main.ts windows/src/style.css
git commit -F - <<'MSG'
feat(shelf): the Ask and Shelf halves of the drop, and the Shelf drop path

While files are dragged over the open island a see-through layer marks the two halves; the half is the contract's zoneAt on the pointer (the cursor poll on Windows, the drag event's position on Linux). A drop on Ask is today's drop line for line. A drop on Shelf takes every file, takes a fresh drop token, stops the upload sequence, does not wait for the desktop cat and shows the shelf. The drop canvas is not touched.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, the two pictures' paths, the agent and the model.

---

# Stage 4: the view

### Task 6: The shelf view, the view plumbing and the `?dev` Shelf panel

**Agent:** `nm-implementer` (Haiku 5.5, high). Also loads `playwright-cli`.

**Files:**
- Create: `windows/src/views/shelf.ts`, `windows/src/shelf/devshelf.ts`, `windows/scripts/cat-tests/shelf-view.test.mjs`
- Modify: `windows/src/core/state.ts`, `windows/src/views/views.ts`, `windows/src/island/island.ts`, `windows/src/cat/dev.ts`, `windows/src/style.css`

**Interfaces:**
- Consumes: Task 4's `State.shelf` (`entries`, `selected`, `note`, `count`, `targets`, `canAsk`, `toggle`, `remove`, `clear`), `sizeLabel`; Task 5's `SHELF_ICONS`; the existing `PressDrag`, `ViewHost`, `ViewActions`.
- Produces: `interface ShelfActions { ask(id), send(ids), reveal(ids), dragOut(ids) }` (Task 9 changes `reveal` to one id), `buildShelf(actions) -> ViewHost`, `ViewActions.shelf`, `State.shelfCaps = { dragOut, send }` (both false until Rust says), `mountShelfDev(root, before)`. The island's four tile actions are stubs (`() => {}`) until Tasks 7, 8 and 9 give them bodies.

**Design.** Tiles in a row that scrolls sideways: a file icon (a folder icon for a folder), the name (one line, the full name as a tooltip) and the size; hovering shows **Ask about it**, **Send** (only where the system has one), **Show in folder** and **Remove from the shelf**; a click ticks a tile; several ticked tiles are sent together and **Ask is off** while several are ticked, for a folder and for a missing original; a missing original is dimmed, says "Missing" and keeps only Remove; a press that moves 4 px starts a drag out where the system can. The header says "Shelf" and the count, or the note after a drop that left something off; **Clear all** empties it. No thumbnails: the page holds no path, so it shows the icon (the spec says "a thumbnail or file icon"; Open question 3). Nothing of the header, the tabs or any existing view changes.

- [ ] **Step 1: Write the test**


```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/shelf-view.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { State } from "../../src/core/state.ts";

// The shelf view (G1). It needs the DOM, so the checks are source pins; what it draws is looked at in the `?dev` page's Shelf panel (the checkpoint's pictures).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const view = source("views/shelf.ts");

test("the shelf view is a new view and no existing view changes: the header, the upload views and the style sheet only gain", () => {
  const views = source("views/views.ts");
  assert.match(views, /map\.set\("shelf", buildShelf\(actions\.shelf\)\);/);
  assert.match(views, /\/\*\* What the shelf view's tiles do \(sub-project G1\)\. \*\/\s*shelf: ShelfActions;/);
  const header = views.slice(views.indexOf("export function buildHeader"), views.indexOf("// ── Overview"));
  assert.doesNotMatch(header, /shelf/i, "no new tab or button in the header");
  assert.doesNotMatch(source("views/upload.ts"), /shelf/i);
  assert.doesNotMatch(source("views/icons.ts"), /shelf|tray/i, "the shelf's icons are its own");
});

test("the tiles show the file's icon, name and size, and the four buttons the spec lists; only Remove is there for a missing original", () => {
  assert.match(view, /e\.folder \? SHELF_ICONS\.folder : SHELF_ICONS\.file/);
  assert.match(view, /e\.missing \? "Missing" : e\.folder \? "Folder" : sizeLabel\(e\.size\)/);
  for (const label of ["Ask about it", "Show in folder", "Remove from the shelf"]) assert.match(view, new RegExp(label));
  assert.match(view, /e\.missing \? null : button\("Ask about it", SHELF_ICONS\.ask, \(\) => act\.ask\(e\.id\), !State\.shelf\.canAsk\(e\.id\)\)/, "Ask is off where the store says so");
  assert.match(view, /e\.missing \|\| !State\.shelfCaps\.send \? null : button\(ids\(\)\.length > 1/, "Send only where the system has one, and for the ticked items");
  assert.match(view, /button\("Remove from the shelf", SHELF_ICONS\.remove, \(\) => void State\.shelf\.remove\(e\.id\)\)/);
  assert.match(view, /text: "Clear all", onclick: \(\) => void State\.shelf\.clear\(\)/);
});

test("a press on a tile is a click (it ticks) or, moved 4 px, a drag out where the system can do it; the view holds ids and never a path", () => {
  assert.match(view, /new PressDrag\(\)/, "the same press-or-drag rule as the big cat's");
  assert.match(view, /if \(State\.shelfCaps\.dragOut && !e\.missing\) act\.dragOut\(ids\(\)\);/);
  assert.match(view, /if \(press\.release\(\) === "click"\) State\.shelf\.toggle\(e\.id\);/);
  assert.match(view, /if \(ev\.button !== 0 \|\| \(ev\.target as HTMLElement\)\.closest\("\.sh-acts"\)\) return;/, "a press on a button is the button's");
  assert.doesNotMatch(view, /\.path|\.link|bridge|Bridge|setInterval|setTimeout|requestAnimationFrame/, "no path, no call out, no timer");
});

test("it redraws only when what it shows changed, so a tile under the pointer is not replaced while it is pressed", () => {
  assert.match(view, /const key = JSON\.stringify\(\[s\.entries, \[\.\.\.s\.selected\], s\.note, caps\]\);\s*if \(key === drawn\) return;/);
});

test("State starts with no system abilities, so a view built before Rust says shows only Ask, Show in folder and Remove", () => {
  assert.deepEqual(State.shelfCaps, { dragOut: false, send: false });
});

test("the Shelf panel of the ?dev page is registered behind the dev server's own check, and the release build does not hold it", () => {
  assert.match(source("cat/dev.ts"), /mountShelfDev\(root, wrap\);/);
  assert.match(source("main.ts"), /if \(import\.meta\.env\.DEV && new URLSearchParams\(location\.search\)\.has\("dev"\)\) \{\s*const \{ mountDev \} = await import\("\.\/cat\/dev"\);/, "dev.ts, and with it the panel, is only ever imported dynamically behind DEV");
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-view.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
cd ..
```

Expected: `# fail` greater than 0.

- [ ] **Step 3: Write the view and the panel**


```bash
mkdir -p windows/src/views
cat > windows/src/views/shelf.ts <<'EOF'
// The shelf view (sub-project G1): what is parked in the notch. A new view in the island's own style; no existing view changes. Each tile is a file icon (or a folder), its name and
// its size; hovering it shows Ask, Send, Show in folder and Remove; a click ticks it (several ticked can be sent together); a press that moves 4 px starts a drag out of the island
// where the system can do it (State.shelfCaps.dragOut). The list is State.shelf, Rust's last answer: the page holds ids, never a path.

import { h, svg, clear } from "./dom";
import { State } from "../core/state";
import { PressDrag } from "../cat/pressdrag";
import { SHELF_ICONS } from "../shelf/icons";
import { sizeLabel } from "../shelf/store";
import type { ShelfEntry } from "../shelf/store";
import type { ViewHost } from "./views";

/** What the island does for a tile's buttons. Ids only: Rust finds the files. */
export interface ShelfActions {
  /** Hand the file to the chat, like a drop on Ask. One id. */
  ask(id: string): void;
  /** The system's share (Windows). */
  send(ids: string[]): void;
  /** Show in Explorer or the file manager. */
  reveal(ids: string[]): void;
  /** Start dragging these files out of the island (the pointer is down). */
  dragOut(ids: string[]): void;
}

const icon = (path: string, size = 14) => svg(path, size, { stroke: 1.7 });

function button(label: string, path: string, onclick: () => void, off = false): HTMLElement {
  return h("button", { class: off ? "sh-act off" : "sh-act", title: label, "aria-label": label, disabled: off, onclick: (e: Event) => { e.stopPropagation(); if (!off) onclick(); } }, icon(path));
}

function tile(e: ShelfEntry, act: ShelfActions, press: PressDrag): HTMLElement {
  const sel = State.shelf.selected.has(e.id);
  const ids = () => State.shelf.targets(e.id);
  const acts = h(
    "div",
    { class: "sh-acts" },
    e.missing ? null : button("Ask about it", SHELF_ICONS.ask, () => act.ask(e.id), !State.shelf.canAsk(e.id)),
    e.missing || !State.shelfCaps.send ? null : button(ids().length > 1 ? `Send ${ids().length} files` : "Send", SHELF_ICONS.send, () => act.send(ids())),
    e.missing ? null : button("Show in folder", SHELF_ICONS.reveal, () => act.reveal(ids())),
    button("Remove from the shelf", SHELF_ICONS.remove, () => void State.shelf.remove(e.id)),
  );
  const el = h(
    "div",
    { class: `sh-tile${sel ? " sel" : ""}${e.missing ? " missing" : ""}`, title: e.name },
    h("div", { class: "sh-pick" }, sel ? icon(SHELF_ICONS.check, 10) : null),
    h("div", { class: "sh-ico" }, icon(e.folder ? SHELF_ICONS.folder : SHELF_ICONS.file, 26)),
    h("div", { class: "sh-name", text: e.name }),
    h("div", { class: "sh-size", text: e.missing ? "Missing" : e.folder ? "Folder" : sizeLabel(e.size) }),
    acts,
  );
  // A press on the tile is a click (tick it) or, moved 4 px with the button down, the start of a drag out of the island. Missing files have nothing to drag.
  el.addEventListener("mousedown", (ev) => {
    if (ev.button !== 0 || (ev.target as HTMLElement).closest(".sh-acts")) return;
    press.press(ev.clientX, ev.clientY);
    const move = (m: MouseEvent) => {
      if (press.move(m.clientX, m.clientY) !== "start") return;
      cleanup();
      press.cancel();
      if (State.shelfCaps.dragOut && !e.missing) act.dragOut(ids());
    };
    const up = () => {
      cleanup();
      if (press.release() === "click") State.shelf.toggle(e.id);
    };
    const cleanup = () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
    };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  });
  return el;
}

export function buildShelf(act: ShelfActions): ViewHost {
  const press = new PressDrag();
  const title = h("span", { class: "sh-title", text: "Shelf" });
  const count = h("span", { class: "sh-count" });
  const sendMany = h("button", { class: "btn secondary sh-small", onclick: () => act.send(State.shelf.targets([...State.shelf.selected][0] ?? "")) });
  const clearAll = h("button", { class: "btn secondary sh-small", text: "Clear all", onclick: () => void State.shelf.clear() });
  const tiles = h("div", { class: "sh-tiles" });
  tiles.addEventListener("wheel", (e) => { tiles.scrollLeft += e.deltaY + e.deltaX; e.preventDefault(); }, { passive: false });
  const empty = h("div", { class: "sh-empty" }, h("div", { class: "sh-empty-ico" }, svg(SHELF_ICONS.tray, 30, { stroke: 1.4 })), h("div", { text: "Nothing on the shelf." }), h("div", { class: "sh-empty-sub", text: "Drop files on the right half of the island to keep them here." }));
  const body = h("div", { class: "sh-body" }, h("div", { class: "sh-head" }, title, count, h("span", { class: "sh-spacer" }), sendMany, clearAll), tiles, empty);
  const el = h("div", { class: "view" }, h("div", { class: "card sh-card" }, body));
  let drawn = "";

  return {
    el,
    sync() {
      const s = State.shelf, caps = State.shelfCaps;
      // Rebuilt only when what it shows changed, so a tile under the pointer is not replaced while it is pressed.
      const key = JSON.stringify([s.entries, [...s.selected], s.note, caps]);
      if (key === drawn) return;
      drawn = key;
      count.textContent = s.note ?? (s.count === 0 ? "" : s.count === 1 ? "1 file" : `${s.count} files`);
      count.classList.toggle("note", s.note !== null);
      const many = s.selected.size > 1 && caps.send;
      sendMany.style.display = many ? "" : "none";
      sendMany.textContent = `Send ${s.selected.size}`;
      clearAll.style.display = s.count > 0 ? "" : "none";
      tiles.style.display = s.count > 0 ? "" : "none";
      empty.style.display = s.count > 0 ? "none" : "";
      clear(tiles);
      for (const e of s.entries) tiles.append(tile(e, act, press));
    },
  };
}
EOF
```

```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/devshelf.ts <<'EOF'
// The `?dev` page's "Shelf" panel (sub-project G1), the Windows/Linux counterpart of the Mac's Debug shelf panel: the real shelf view inside an island frame, fed by a shelf in memory that
// runs the contract's own rules, with buttons for every state worth looking at (a few files, a full shelf and its note, a folder, a missing original, ticks, the system's abilities
// switched on and off), the half-of-the-island probe, and the compact badge. Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window needed). Only the dev server serves it:
// main.ts loads dev.ts behind `import.meta.env.DEV`, so a release build does not contain it.

import { BotEngine } from "../cat/engine.ts";
import { PRESETS } from "../cat/presets.ts";
import { State } from "../core/state.ts";
import { buildShelf } from "../views/shelf.ts";
import { mockBackend } from "./backend.ts";
import { zoneAt } from "./rules.ts";
import { THEME } from "../theme.generated.ts";

const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;

const NAMES = ["report.pdf", "photo.png", "notes.md", "build.zip", "main.rs", "Screenshot 2026-10-14 at 09.41.png", "budget.xlsx", "talk.key", "logo.svg", "todo.txt", "invoice-0042.pdf", "recording.m4a"];

function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}

export function mountShelfDev(root: HTMLElement, before: Node | null): void {
  const mock = mockBackend();
  State.shelf.attach(mock);
  State.shelfCaps = { dragOut: true, send: true };
  const log: string[] = [];
  const said = (line: string) => { log.push(line); refresh(); };
  const act = {
    ask: (id: string) => said(`ask ${id}`),
    send: (ids: string[]) => said(`send ${ids.join(",")}`),
    reveal: (ids: string[]) => said(`reveal ${ids.join(",")}`),
    dragOut: (ids: string[]) => said(`dragOut ${ids.join(",")}`),
  };
  const view = buildShelf(act);
  view.el.classList.add("on");

  const box = document.createElement("section");
  box.id = "shelf-dev";
  box.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  box.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">Shelf</h2>
    <p style="color:${B.dim};margin:0 0 12px;font-size:13px">The shelf view in its island, fed by a shelf in memory that follows the contract (at most 30, newest first, an overflow is refused, a re-dropped file is a duplicate). Hover a tile for its buttons, click one to tick it. The buttons below fill the shelf; "Sent to" shows what the tiles asked for.</p>`;

  // The island frame: 640 x 176, the card 620 x 124 where the island puts it, the cat at the view's place.
  const stage = document.createElement("div");
  stage.style.cssText = "position:relative;width:640px;height:176px;background:#000;border-radius:0 0 22px 22px;overflow:hidden;margin:6px 0 12px";
  const slot = document.createElement("div");
  slot.style.cssText = "position:absolute;left:10px;right:10px;top:42px;bottom:10px";
  slot.append(view.el);
  const cat = document.createElement("canvas");
  const D = 44 / 0.6, dpr = Math.min(2, devicePixelRatio || 1);
  cat.width = Math.round(D * dpr); cat.height = Math.round(D * dpr);
  cat.style.cssText = `position:absolute;left:${46 - D / 2}px;top:${108 - D / 2}px;width:${D}px;height:${D}px;pointer-events:none`;
  const engine = new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 });
  const paintCat = () => {
    const c = cat.getContext("2d")!;
    c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, D, D);
    engine.update(1 / 60); engine.draw(c, D, D);
  };
  stage.append(slot, cat);
  box.append(stage);

  const bar = document.createElement("div");
  bar.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px";
  let n = 0;
  const paths = (count: number) => Array.from({ length: count }, () => `C:/Users/me/${NAMES[n++ % NAMES.length].replace(/(\.\w+)?$/, (m) => (n > NAMES.length ? ` ${Math.floor(n / NAMES.length)}${m}` : m))}`);
  const refresh = () => { view.sync(); sent.textContent = log.slice(-4).join("  |  ") || "nothing yet"; };
  const add = (count: number) => () => void State.shelf.add(paths(count)).then(refresh);
  bar.append(
    button("Drop 3 files", add(3)),
    button("Drop 12", add(12)),
    button("Fill to 30", () => void State.shelf.add(paths(30)).then(refresh)),
    button("Drop 5 more", add(5)),
    button("Drop a folder", () => void State.shelf.add(["C:/Users/me/Projects/notes"]).then(refresh)),
    button("Re-drop the first", () => void State.shelf.add([`C:/Users/me/${State.shelf.entries.at(-1)?.name ?? "x"}`]).then(refresh)),
    button("First one missing", () => { const id = State.shelf.entries[0]?.id; if (id) mock.gone.add(id); void State.shelf.refresh().then(refresh); }),
    button("Tick two", () => { for (const e of State.shelf.entries.slice(0, 2)) State.shelf.toggle(e.id); refresh(); }),
    button("Clear", () => void State.shelf.clear().then(refresh)),
  );
  box.append(bar);

  const caps = document.createElement("div");
  caps.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;align-items:center";
  const toggle = (label: string, key: "dragOut" | "send") => {
    const b = button("", () => { State.shelfCaps = { ...State.shelfCaps, [key]: !State.shelfCaps[key] }; sync(); refresh(); });
    const sync = () => { b.textContent = `${label}: ${State.shelfCaps[key] ? "on" : "off"}`; b.style.borderColor = State.shelfCaps[key] ? B.accent : B.line; };
    sync();
    caps.append(b);
  };
  toggle("Drag out", "dragOut");
  toggle("Send (Windows share)", "send");
  box.append(caps);

  const sent = document.createElement("pre");
  sent.id = "shelf-dev-sent";
  sent.style.cssText = `color:${B.dim};font-size:12px;margin:0 0 10px;white-space:pre-wrap`;
  const sentRow = document.createElement("div");
  sentRow.style.cssText = `font-size:12px;color:${B.dim}`;
  sentRow.append("Sent to: ", sent);
  box.append(sentRow);

  // Which half a pointer is in: the contract's zoneAt on a 640 px island.
  const probe = document.createElement("div");
  probe.style.cssText = "display:flex;gap:10px;align-items:center;font-size:12px";
  const slider = document.createElement("input");
  slider.type = "range"; slider.min = "-20"; slider.max = "660"; slider.value = "100"; slider.style.width = "320px"; slider.id = "shelf-dev-x";
  const readout = document.createElement("span");
  readout.id = "shelf-dev-zone";
  const probeZone = () => { const x = Number(slider.value), z = zoneAt(x, 640); readout.textContent = `x = ${x}: ${z ?? "outside the island"}`; };
  slider.oninput = probeZone;
  probeZone();
  probe.append("Pointer x on a 640 px island", slider, readout);
  box.append(probe);

  root.insertBefore(box, before);
  // What the island does for every State change: draw the view again (it redraws only when what it shows changed).
  State.subscribe(refresh);
  State.shelf.attach(mock);
  void State.shelf.refresh().then(refresh);
  // The cat is drawn a few frames and then left: the panel is a still picture of the view, not an animation.
  let frames = 0;
  const tick = () => { paintCat(); if (++frames < 30) requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
}
EOF
```

- [ ] **Step 4: Register the view, the abilities and the panel**


```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/core/state.ts", [
('''  /** Where `giveCoats` takes its random numbers: `Math.random`, and a test's own. */''', '''  /** What this system can do for a shelf item, from Rust's boot info: drag it out of the island, send it through the system's share. Show in folder and Ask always work. */
  shelfCaps = { dragOut: false, send: false };

  /** Where `giveCoats` takes its random numbers: `Math.random`, and a test's own. */'''),
])
edit("windows/src/views/views.ts", [
('''import { buildChoose, buildUpload, buildUploading } from "./upload";
''', '''import { buildChoose, buildUpload, buildUploading } from "./upload";
import { buildShelf, type ShelfActions } from "./shelf";
'''),
('''  /** A one-off face from the cat, e.g. a yawn while a local model wakes up. */
  emote(name: BotEmoteName): void;
}''', '''  /** A one-off face from the cat, e.g. a yawn while a local model wakes up. */
  emote(name: BotEmoteName): void;
  /** What the shelf view's tiles do (sub-project G1). */
  shelf: ShelfActions;
}'''),
('''  map.set("shelf", buildPlaceholder("Shelf", ""));
''', '''  map.set("shelf", buildShelf(actions.shelf));
'''),
])
edit("windows/src/island/island.ts", [
('''      emote: (name) => this.engine.triggerEmote(name),
    };''', '''      emote: (name) => this.engine.triggerEmote(name),
      // The shelf's tiles: Ask is Task 7, Send and Show in folder Task 9, dragging out Task 8.
      shelf: { ask: () => {}, send: () => {}, reveal: () => {}, dragOut: () => {} },
    };'''),
])
edit("windows/src/cat/dev.ts", [
('''import { mountDesktopDev } from "./devdesktop.ts";
''', '''import { mountDesktopDev } from "./devdesktop.ts";
import { mountShelfDev } from "../shelf/devshelf.ts";
'''),
('''  mountDesktopDev(root, wrap, ticks);
''', '''  mountDesktopDev(root, wrap, ticks);
  // ── Sub-project G1: the shelf, its half of the island and its badge ──
  mountShelfDev(root, wrap);
'''),
])
print("applied")
PYEOF
```

Expected: `applied`

```bash
cat >> windows/src/style.css <<'EOF'

/* The shelf view: a row of tiles, each a file icon, its name and its size. */
.sh-card {
  padding: 0;
}

.sh-body {
  position: absolute;
  inset: 0;
  padding: 9px 16px 8px 98px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.sh-head {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 24px;
  flex: 0 0 24px;
}

.sh-title {
  font: 600 15px var(--font);
}

.sh-count {
  font: 400 12px var(--font);
  color: var(--dim);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.sh-count.note {
  color: var(--amber);
}

.sh-spacer {
  flex: 1;
}

.btn.sh-small {
  padding: 4px 11px;
  font-size: 11.5px;
}

.sh-tiles {
  flex: 1;
  min-height: 0;
  display: flex;
  gap: 8px;
  overflow-x: auto;
  overflow-y: hidden;
  scrollbar-width: thin;
  scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
}

.sh-tile {
  position: relative;
  flex: 0 0 88px;
  padding: 8px 6px 6px;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.05);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1px;
  transition: background 0.12s;
}

.sh-tile:hover {
  background: rgba(255, 255, 255, 0.09);
}

.sh-tile.sel {
  background: rgba(52, 211, 153, 0.14);
  box-shadow: inset 0 0 0 1px rgba(52, 211, 153, 0.5);
}

.sh-tile.missing {
  opacity: 0.55;
}

.sh-pick {
  position: absolute;
  top: 5px;
  left: 5px;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  border: 1.5px solid rgba(255, 255, 255, 0.25);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #07130e;
  opacity: 0;
  transition: opacity 0.12s;
}

.sh-tile:hover .sh-pick,
.sh-tile.sel .sh-pick {
  opacity: 1;
}

.sh-tile.sel .sh-pick {
  background: #34d399;
  border-color: #34d399;
}

.sh-ico {
  height: 30px;
  display: flex;
  align-items: center;
  color: var(--dim);
}

.sh-name {
  max-width: 100%;
  font: 500 11px var(--font);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.sh-size {
  font: 400 10px var(--font);
  color: var(--dim-3);
}

.sh-acts {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  padding: 3px;
  display: flex;
  justify-content: center;
  gap: 2px;
  border-radius: 0 0 12px 12px;
  background: rgba(14, 15, 17, 0.94);
  opacity: 0;
  transition: opacity 0.12s;
}

.sh-tile:hover .sh-acts {
  opacity: 1;
}

.sh-act {
  width: 20px;
  height: 20px;
  padding: 0;
  border: 0;
  border-radius: 6px;
  background: none;
  color: var(--ink-2);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: default;
}

.sh-act:hover {
  background: rgba(255, 255, 255, 0.14);
}

.sh-act.off {
  opacity: 0.3;
}

.sh-empty {
  margin: auto;
  text-align: center;
  font: 500 13px var(--font);
  color: var(--ink-2);
}

.sh-empty-ico {
  display: flex;
  justify-content: center;
  color: var(--dim-3);
  margin-bottom: 4px;
}

.sh-empty-sub {
  font: 400 11.5px var(--font);
  color: var(--dim);
  margin-top: 2px;
}
EOF
```

- [ ] **Step 5: Run the checks**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-view.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: `# pass 6`, `# fail 0`, `tsc exit 0`, `ℹ tests 410`, `ℹ pass 410`, `ℹ fail 0`.

- [ ] **Step 6: Prove the view bites**

Run:

```bash
cd windows
m() { python3 ../.claude/checkpoints/g1-tauri/mut.py "$@"; }; T=scripts/cat-tests/shelf-view.test.mjs
m src/views/shelf.ts 'if (State.shelfCaps.dragOut && !e.missing) act.dragOut(ids());' 'act.dragOut(ids());' $T
m src/views/shelf.ts 'e.missing || !State.shelfCaps.send ? null' 'e.missing ? null' $T
m src/views/shelf.ts 'if (key === drawn) return;' '' $T
m src/views/views.ts '  tabDrop.classList.toggle("on", v === "upload");' '  tabDrop.classList.toggle("on", v === "upload" || v === "shelf");' $T
cd ..
```

Expected: each line ends `# pass 5 # fail 1`.

- [ ] **Step 7: The pictures for Checkpoint 1** (the `?dev` page's Shelf panel, and the view in the real island)

Start the dev server, then:


```bash
S=g1-dev; cd .claude/checkpoints/g1-tauri
pw() { playwright-cli -s="$S" "$@"; }
ev() { pw eval "$1" 2>&1 | grep -A1 "### Result" | tail -1; }
pw open 'http://127.0.0.1:14631/?dev' > /dev/null 2>&1; pw resize 1000 900 > /dev/null 2>&1; sleep 1
ev "(() => { const b = document.querySelector('#shelf-dev'); b.scrollIntoView({block:'start'}); return b ? 'panel' : 'none'; })()"
click() { ev "(() => { [...document.querySelector('#shelf-dev').querySelectorAll('button')].find((b) => b.textContent === '$1').click(); return 1; })()" > /dev/null; sleep 0.5; }
click 'Drop 12'; click 'Drop a folder'; click 'First one missing'; click 'Tick two'
ev "document.querySelectorAll('.sh-tile').length + ' tiles, ' + document.querySelectorAll('.sh-tile.sel').length + ' ticked, ' + document.querySelectorAll('.sh-tile.missing').length + ' missing, ' + document.querySelector('.sh-count').textContent"
pw screenshot --filename="$(pwd)/shelf-view.png" > /dev/null 2>&1
pw hover ".sh-tile:nth-child(4)" > /dev/null 2>&1; sleep 0.3; pw screenshot --filename="$(pwd)/shelf-hover.png" > /dev/null 2>&1
click 'Fill to 30'; click 'Drop 5 more'
ev "document.querySelectorAll('.sh-tile').length + ' tiles, note: ' + document.querySelector('.sh-count').textContent"
pw screenshot --filename="$(pwd)/shelf-full-note.png" > /dev/null 2>&1
click 'Clear'
ev "document.querySelector('.sh-empty').style.display === '' ? 'empty state' : 'not empty'"
pw screenshot --filename="$(pwd)/shelf-empty.png" > /dev/null 2>&1
ev "(() => { const x = document.querySelector('#shelf-dev-x'); x.value = 320; x.dispatchEvent(new Event('input')); const a = document.querySelector('#shelf-dev-zone').textContent; x.value = 321; x.dispatchEvent(new Event('input')); const b = document.querySelector('#shelf-dev-zone').textContent; x.value = 641; x.dispatchEvent(new Event('input')); return a + ' | ' + b + ' | ' + document.querySelector('#shelf-dev-zone').textContent; })()"
pw console 2>&1 | grep '\[ERROR\]' | grep -vc favicon
pw close > /dev/null 2>&1
cd ../..
```

Expected: `"panel"`, `"13 tiles, 2 ticked, 1 missing, 13 files"`, `"30 tiles, note: The shelf is full (30). 5 files were left off."`, `"empty state"`, `"x = 320: ask | x = 321: shelf | x = 641: outside the island"` and `0`. The pictures are `shelf-view.png` (tiles with two ticked and one dimmed "Missing"), `shelf-hover.png` (the four buttons over the tile under the pointer), `shelf-full-note.png` (the amber note in the header) and `shelf-empty.png` (the empty state's words). Say what you see in each.

```bash
S=g1-isl; cd .claude/checkpoints/g1-tauri
pw() { playwright-cli -s="$S" "$@"; }
ev() { pw eval "$1" 2>&1 | grep -A1 "### Result" | tail -1; }
pw open 'http://127.0.0.1:14631/' > /dev/null 2>&1; pw resize 760 360 > /dev/null 2>&1; sleep 7
ev "(async () => { const {island, State} = window.__nm; await State.shelf.add(['C:/a.pdf','C:/b.txt','C:/c.md','C:/d.txt']); island.alert('shelf'); return State.view; })()"
sleep 1.5
pw screenshot --filename="$(pwd)/shelf-in-island.png" > /dev/null 2>&1
pw close > /dev/null 2>&1
cd ../..
```

Expected: `"shelf"`, and `shelf-in-island.png` shows the real island open on the shelf: the cat small at the left, "Shelf" and "4 files", four tiles, **Clear all**.

- [ ] **Step 8: Commit**


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/src/views/shelf.ts windows/src/shelf/devshelf.ts windows/scripts/cat-tests/shelf-view.test.mjs windows/src/core/state.ts windows/src/views/views.ts windows/src/island/island.ts windows/src/cat/dev.ts windows/src/style.css
git commit -F - <<'MSG'
feat(shelf): the shelf view and the ?dev Shelf panel

A new island view in the island's style: tiles with a file icon, name and size; Ask, Send, Show in folder and Remove on hover; ticks for sending several; Missing for an original that is gone; a note after a drop that left something off; Clear all. The island's tile actions are filled in by the next tasks. The ?dev page gets a Shelf panel with a shelf in memory.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, the agent and the model.

## Checkpoint 1: the owner looks at the halves and the shelf

Tasks 2 to 6 are done. The session **stops here**, copies the pictures into `.claude/checkpoints/g1-tauri/` (they are already there from Steps 7 of Tasks 5 and 6), sends the owner their paths and this list, sends the same to the main session with `SendMessage`, and waits.

**Pictures:** `drag-ask-hot.png` and `drag-shelf-hot.png` (the two halves, each hot in turn), `shelf-in-island.png` (the real island on the shelf), `shelf-view.png` (ticks and a missing original), `shelf-hover.png` (the tile's four buttons), `shelf-full-note.png` (the full shelf's note) and `shelf-empty.png` (the empty state).

**What to look for, and the questions the owner answers:**
1. **The two halves.** Is it clear which half is which? The right half dims the end of the Ask side's chips row ("Code", "Docs") because the centre line crosses it; the Ask canvas itself is unchanged. Accept, or move the Shelf half's left edge right so the chips stay whole (a visual change of the tray only; the zone rule stays the centre line).
2. **The cat over the tray** stays visible because the tray is see-through. Accept, or make the tray solid (the cat then disappears under it while the pointer is over Shelf).
3. **The tiles.** The icon is a file or a folder (no thumbnail: the page holds no path). Accept, or ask for thumbnails, which would add a Rust command that returns a small image for an id.
4. **The wording:** "Ask about it", "Send", "Show in folder", "Remove from the shelf", "Clear all", "Nothing on the shelf.", "The shelf is full (30). N files were left off."

---

# Stage 5: entry points

### Task 7: The tray item, the compact badge, and Ask from a tile

**Agent:** `nm-implementer` (Haiku 5.5, high). Also loads `playwright-cli`.

**Files:**
- Create: `windows/src/shelf/badge.ts`, `windows/scripts/cat-tests/shelf-badge.test.mjs`
- Modify: `windows/src/island/island.ts`, `windows/src/main.ts`, `windows/src-tauri/src/tray.rs`, `windows/src/shelf/devshelf.ts` (replaced whole), `windows/scripts/cat-tests/shelf-drop.test.mjs`, `windows/src/style.css`

**Interfaces:**
- Consumes: Task 4's `State.shelf`, `Bridge.shelfAsk`; Task 5's `shelfDrop`; the island's `whenCatIsHere`, `swallow`, `alert`, `fsm`.
- Produces: `badgeShown(mode, count, greeting)`, `badgeLabel(count)`, `badgeTitle(count)`, `badgePlace(islandW, islandH)`; `Island.openShelf()`, the private `askShelf(id)`; `swallow(path, ingest?)` (its one new default parameter: a drop on Ask still ingests with `Bridge.ingestFile`); the tray's `shelf` event. The shelf's four entry points are then all there: a Shelf drop (Task 5), the tray item, the badge, and `openShelf`.

**Design.** *The tray:* a **Shelf** item after Open, the same event path as the others (`tray` event `shelf`), so a hidden island comes up on the shelf. *The badge:* one 16 px cell at the right end of the compact island's wing (after the 2x2 grid), a count up to 9 and "9+", **shown only while the island is already compact**: `badgeShown("hidden", …)` is false, so a shelf change never wakes a hidden island, and the island's code only draws it (no `alert`, `reveal`, `expand` or `setView` in that code). A press on it opens the shelf and is nothing else (it stops the island's own press, which would open the Home view). There is no wing that steps aside on Windows (that is the Mac's), so the badge does not fade with it (Open question 5). *Ask from a tile:* the drop view opens with the file already over the cat, the desktop cat is waited for as for any drop, the catch plays, and Rust copies the file into the inbox **from the shelf's id** (the page holds no path); the chat starts new with it. The inbox copy is the same one a drop on Ask makes: the shelf's own folders are never the inbox.

- [ ] **Step 1: Write the test**


```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/shelf-badge.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { badgeLabel, badgePlace, badgeShown, badgeTitle } from "../../src/shelf/badge.ts";
import { COMPACT_W, NOTCH_H } from "../../src/core/layout.ts";

// The compact badge, the tray item and Ask from a tile (G1). The badge's rule is pure; the island's wiring is pinned in its source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const isl = source("island/island.ts");

test("the badge shows only while the island is compact and something is on the shelf: never hidden, never open, never over the greeting", () => {
  assert.equal(badgeShown("compact", 3, false), true);
  assert.equal(badgeShown("hidden", 3, false), false, "it never wakes a hidden island");
  assert.equal(badgeShown("expanded", 3, false), false);
  assert.equal(badgeShown("compact", 0, false), false);
  assert.equal(badgeShown("compact", 3, true), false);
});

test("it says the count up to nine and 9+ after, its tooltip says it in words, and it sits at the right end of the compact wing", () => {
  assert.deepEqual([0, 1, 9, 10, 30].map(badgeLabel), ["0", "1", "9", "9+", "9+"]);
  assert.equal(badgeTitle(1), "Shelf: 1 file");
  assert.equal(badgeTitle(12), "Shelf: 12 files");
  const p = badgePlace(COMPACT_W, NOTCH_H);
  assert.deepEqual(p, { left: COMPACT_W - 25, top: NOTCH_H / 2 - 8 });
  assert.ok(p.left >= 236 && p.left + 16 <= COMPACT_W - 7, "inside the right ear, past the 2x2 grid (which ends 25 px from the edge), clear of the island's corner");
});

test("the island only draws the badge: a press on it opens the shelf and nothing else, and drawing it never opens, reveals or expands the island", () => {
  assert.match(isl, /this\.shelfBadge\.addEventListener\("mousedown", \(e\) => e\.stopPropagation\(\)\);\s*this\.shelfBadge\.addEventListener\("click", \(e\) => \{ e\.stopPropagation\(\); this\.openShelf\(\); \}\);/);
  const draw = isl.slice(isl.indexOf("// The shelf's badge: a function of the mode"), isl.indexOf("syncMiniBotStates(State.tasks);"));
  assert.match(draw, /const showBadge = badgeShown\(State\.mode, State\.shelf\.count, greetingActive\);/);
  assert.doesNotMatch(draw, /alert\(|reveal\(|expand\(|setView\(|fsm\.|forceHome|setMode/, "a function of the mode, never a cause of it");
  assert.match(isl, /this\.shelfBadge\.style\.pointerEvents = showBadge \? "auto" : "none";/, "it takes the mouse only while it is shown");
  assert.match(isl, /this\.miniGrid,\s*this\.shelfBadge,\s*this\.countdown,/);
});

test("the shelf opens from the tray item, the badge and a drop; opening it looks at the files, and a hidden island comes up on it", () => {
  assert.match(source("main.ts"), /case "shelf":\s*setPaused\(false\);\s*island\.openShelf\(\);\s*break;/);
  assert.match(isl, /openShelf\(\) \{\s*void State\.shelf\.refresh\(\);\s*this\.alert\("shelf"\);\s*\}/);
  const tray = fs.readFileSync(new URL("../../src-tauri/src/tray.rs", import.meta.url), "utf8");
  assert.match(tray, /MenuItem::with_id\(app, "shelf", "Shelf", true, None::<&str>\)\?;/);
  assert.match(tray, /Menu::with_items\(app, &\[&open, &shelf, &desktop, &sep1, &settings, &pause, &sep2, &quit\]\)/);
});

test("Ask from a tile is a drop on Ask without the drag: the drop view opens, the cat is waited for, the catch plays, and Rust ingests by id", () => {
  const ask = isl.slice(isl.indexOf("private askShelf(id: string) {"), isl.indexOf("/** Whether the OS has a global cursor"));
  assert.match(ask, /if \(!entry \|\| !State\.shelf\.canAsk\(id\)\) return;\s*UploadSeq\.enterZone\(USC\.REST_X, USC\.REST_Y\);\s*this\.uploadCanvas\.hover\(true\);\s*this\.setView\("upload"\);\s*this\.whenCatIsHere\(\(\) => this\.swallow\(entry\.name, \(\) => Bridge\.shelfAsk\(id\)\)\);/);
  assert.match(isl, /shelf: \{ ask: \(id\) => this\.askShelf\(id\),/);
  assert.match(isl, /void ingest\(path\)\s*\.then\(async \(file\) => \{/, "the same copy, chime and chat reset as a drop: only the source of the file differs");
  assert.doesNotMatch(source("core/bridge.ts").match(/shelfAsk:[^\n]*/)[0], /path/, "the bridge sends an id");
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-badge.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ERR_MODULE_NOT_FOUND" | head -3
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 3: Write the badge's rule, and replace the panel with the one that also shows the badge**


```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/badge.ts <<'EOF'
// The compact island's shelf badge (sub-project G1): a small count at the right end of the wing, shown only while the island is already compact. It never wakes a hidden island and
// never keeps an island visible: what it shows is a function of the mode, nothing here opens, reveals or expands. Pure, so the plain-Node checks load it.

import type { IslandMode } from "../core/layout.ts";

/** Whether the badge is shown: the island is compact (not hidden, not open), there is something on the shelf, and no greeting is playing. */
export function badgeShown(mode: IslandMode, count: number, greeting: boolean): boolean {
  return mode === "compact" && count > 0 && !greeting;
}

/** What the badge says: the count, "9+" past nine (it is 16 px wide). */
export function badgeLabel(count: number): string {
  return count > 9 ? "9+" : String(Math.max(0, Math.floor(count)));
}

/** Its tooltip. */
export function badgeTitle(count: number): string {
  return count === 1 ? "Shelf: 1 file" : `Shelf: ${count} files`;
}

/** Where it sits in the compact island, in the island's px: the right end of the wing, after the 2x2 grid (which ends 25 px from the right edge). */
export function badgePlace(islandW: number, islandH: number): { left: number; top: number } {
  return { left: islandW - 25, top: islandH / 2 - 8 };
}
EOF
```

```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/devshelf.ts <<'EOF'
// The `?dev` page's "Shelf" panel (sub-project G1), the Windows/Linux counterpart of the Mac's Debug shelf panel: the real shelf view inside an island frame, fed by a shelf in memory that
// runs the contract's own rules, with buttons for every state worth looking at (a few files, a full shelf and its note, a folder, a missing original, ticks, the system's abilities
// switched on and off), the half-of-the-island probe, and the compact badge. Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window needed). Only the dev server serves it:
// main.ts loads dev.ts behind `import.meta.env.DEV`, so a release build does not contain it.

import { BotEngine } from "../cat/engine.ts";
import { PRESETS } from "../cat/presets.ts";
import { State } from "../core/state.ts";
import { buildShelf } from "../views/shelf.ts";
import { COMPACT_W, NOTCH_H } from "../core/layout.ts";
import type { IslandMode } from "../core/layout.ts";
import { badgeLabel, badgePlace, badgeShown, badgeTitle } from "./badge.ts";
import { mockBackend } from "./backend.ts";
import { zoneAt } from "./rules.ts";
import { THEME } from "../theme.generated.ts";

const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;

const NAMES = ["report.pdf", "photo.png", "notes.md", "build.zip", "main.rs", "Screenshot 2026-10-14 at 09.41.png", "budget.xlsx", "talk.key", "logo.svg", "todo.txt", "invoice-0042.pdf", "recording.m4a"];

function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}

export function mountShelfDev(root: HTMLElement, before: Node | null): void {
  const mock = mockBackend();
  State.shelf.attach(mock);
  State.shelfCaps = { dragOut: true, send: true };
  const log: string[] = [];
  const said = (line: string) => { log.push(line); refresh(); };
  const act = {
    ask: (id: string) => said(`ask ${id}`),
    send: (ids: string[]) => said(`send ${ids.join(",")}`),
    reveal: (ids: string[]) => said(`reveal ${ids.join(",")}`),
    dragOut: (ids: string[]) => said(`dragOut ${ids.join(",")}`),
  };
  const view = buildShelf(act);
  view.el.classList.add("on");

  const box = document.createElement("section");
  box.id = "shelf-dev";
  box.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  box.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">Shelf</h2>
    <p style="color:${B.dim};margin:0 0 12px;font-size:13px">The shelf view in its island, fed by a shelf in memory that follows the contract (at most 30, newest first, an overflow is refused, a re-dropped file is a duplicate). Hover a tile for its buttons, click one to tick it. The buttons below fill the shelf; "Sent to" shows what the tiles asked for.</p>`;

  // The island frame: 640 x 176, the card 620 x 124 where the island puts it, the cat at the view's place.
  const stage = document.createElement("div");
  stage.style.cssText = "position:relative;width:640px;height:176px;background:#000;border-radius:0 0 22px 22px;overflow:hidden;margin:6px 0 12px";
  const slot = document.createElement("div");
  slot.style.cssText = "position:absolute;left:10px;right:10px;top:42px;bottom:10px";
  slot.append(view.el);
  const cat = document.createElement("canvas");
  const D = 44 / 0.6, dpr = Math.min(2, devicePixelRatio || 1);
  cat.width = Math.round(D * dpr); cat.height = Math.round(D * dpr);
  cat.style.cssText = `position:absolute;left:${46 - D / 2}px;top:${108 - D / 2}px;width:${D}px;height:${D}px;pointer-events:none`;
  const engine = new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 });
  const paintCat = () => {
    const c = cat.getContext("2d")!;
    c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, D, D);
    engine.update(1 / 60); engine.draw(c, D, D);
  };
  stage.append(slot, cat);
  box.append(stage);

  const bar = document.createElement("div");
  bar.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px";
  let n = 0;
  const paths = (count: number) => Array.from({ length: count }, () => `C:/Users/me/${NAMES[n++ % NAMES.length].replace(/(\.\w+)?$/, (m) => (n > NAMES.length ? ` ${Math.floor(n / NAMES.length)}${m}` : m))}`);
  const refresh = () => { view.sync(); sent.textContent = log.slice(-4).join("  |  ") || "nothing yet"; };
  const add = (count: number) => () => void State.shelf.add(paths(count)).then(refresh);
  bar.append(
    button("Drop 3 files", add(3)),
    button("Drop 12", add(12)),
    button("Fill to 30", () => void State.shelf.add(paths(30)).then(refresh)),
    button("Drop 5 more", add(5)),
    button("Drop a folder", () => void State.shelf.add(["C:/Users/me/Projects/notes"]).then(refresh)),
    button("Re-drop the first", () => void State.shelf.add([`C:/Users/me/${State.shelf.entries.at(-1)?.name ?? "x"}`]).then(refresh)),
    button("First one missing", () => { const id = State.shelf.entries[0]?.id; if (id) mock.gone.add(id); void State.shelf.refresh().then(refresh); }),
    button("Tick two", () => { for (const e of State.shelf.entries.slice(0, 2)) State.shelf.toggle(e.id); refresh(); }),
    button("Clear", () => void State.shelf.clear().then(refresh)),
  );
  box.append(bar);

  const caps = document.createElement("div");
  caps.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;align-items:center";
  const toggle = (label: string, key: "dragOut" | "send") => {
    const b = button("", () => { State.shelfCaps = { ...State.shelfCaps, [key]: !State.shelfCaps[key] }; sync(); refresh(); });
    const sync = () => { b.textContent = `${label}: ${State.shelfCaps[key] ? "on" : "off"}`; b.style.borderColor = State.shelfCaps[key] ? B.accent : B.line; };
    sync();
    caps.append(b);
  };
  toggle("Drag out", "dragOut");
  toggle("Send (Windows share)", "send");
  box.append(caps);

  const sent = document.createElement("pre");
  sent.id = "shelf-dev-sent";
  sent.style.cssText = `color:${B.dim};font-size:12px;margin:0 0 10px;white-space:pre-wrap`;
  const sentRow = document.createElement("div");
  sentRow.style.cssText = `font-size:12px;color:${B.dim}`;
  sentRow.append("Sent to: ", sent);
  box.append(sentRow);

  // The compact island's badge: the same rule and place the island uses, on a compact island drawn here, with the island's mode to choose (it shows only while compact).
  let mode: IslandMode = "compact";
  const compact = document.createElement("div");
  compact.style.cssText = `position:relative;width:${COMPACT_W}px;height:${NOTCH_H}px;background:#000;border-radius:0 0 14px 14px;margin:10px 0 6px`;
  const badge = document.createElement("button");
  badge.id = "shelf-badge";
  compact.append(badge);
  const paintBadge = () => {
    const place = badgePlace(COMPACT_W, NOTCH_H), shown = badgeShown(mode, State.shelf.count, false);
    badge.style.left = `${place.left}px`; badge.style.top = `${place.top}px`;
    badge.textContent = badgeLabel(State.shelf.count); badge.title = badgeTitle(State.shelf.count);
    badge.style.opacity = shown ? "1" : "0"; badge.style.pointerEvents = shown ? "auto" : "none";
  };
  const modes = document.createElement("div");
  modes.style.cssText = "display:flex;gap:6px;align-items:center;font-size:12px;margin-bottom:8px";
  const modeButtons = (["compact", "hidden", "expanded"] as const).map((m) => {
    const b = button(m, () => { mode = m; modeButtons.forEach((x) => (x.style.borderColor = x === b ? B.accent : B.line)); paintBadge(); });
    return b;
  });
  modeButtons[0].style.borderColor = B.accent;
  modes.append("Island:", ...modeButtons);
  box.append(compact, modes);
  State.subscribe(paintBadge);
  paintBadge();

  // Which half a pointer is in: the contract's zoneAt on a 640 px island.
  const probe = document.createElement("div");
  probe.style.cssText = "display:flex;gap:10px;align-items:center;font-size:12px";
  const slider = document.createElement("input");
  slider.type = "range"; slider.min = "-20"; slider.max = "660"; slider.value = "100"; slider.style.width = "320px"; slider.id = "shelf-dev-x";
  const readout = document.createElement("span");
  readout.id = "shelf-dev-zone";
  const probeZone = () => { const x = Number(slider.value), z = zoneAt(x, 640); readout.textContent = `x = ${x}: ${z ?? "outside the island"}`; };
  slider.oninput = probeZone;
  probeZone();
  probe.append("Pointer x on a 640 px island", slider, readout);
  box.append(probe);

  root.insertBefore(box, before);
  // What the island does for every State change: draw the view again (it redraws only when what it shows changed).
  State.subscribe(refresh);
  State.shelf.attach(mock);
  void State.shelf.refresh().then(refresh);
  // The cat is drawn a few frames and then left: the panel is a still picture of the view, not an animation.
  let frames = 0;
  const tick = () => { paintCat(); if (++frames < 30) requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
}
EOF
```

- [ ] **Step 4: Wire the island, the tray and the page**

Task 5's pin on `swallow` follows its one new default parameter (the script changes it).


```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/island/island.ts", [
('''import { Bridge, IS_TAURI, onDragDrop } from "../core/bridge";
''', '''import { Bridge, IS_TAURI, onDragDrop, type DroppedFile } from "../core/bridge";
'''),
('''import { dropZone, planDrop } from "../shelf/dropflow";
''', '''import { badgeLabel, badgePlace, badgeShown, badgeTitle } from "../shelf/badge";
import { dropZone, planDrop } from "../shelf/dropflow";
'''),
('''  private miniGrid!: HTMLElement;
''', '''  private miniGrid!: HTMLElement;
  /** The shelf's count at the right end of the compact island's wing (sub-project G1). */
  private shelfBadge!: HTMLElement;
'''),
('''    this.miniGrid = h("div", { id: "mini-grid" });
''', '''    this.miniGrid = h("div", { id: "mini-grid" });
    // A press on the badge opens the shelf and is nothing else: it must not reach the island's own press, which opens the island on its Home view.
    this.shelfBadge = h("button", { id: "shelf-badge" });
    this.shelfBadge.addEventListener("mousedown", (e) => e.stopPropagation());
    this.shelfBadge.addEventListener("click", (e) => { e.stopPropagation(); this.openShelf(); });
'''),
('''      this.miniGrid,
      this.countdown,
    );''', '''      this.miniGrid,
      this.shelfBadge,
      this.countdown,
    );'''),
('''    this.miniGrid.style.top = `${hh / 2 - 14.5}px`;
''', '''    this.miniGrid.style.top = `${hh / 2 - 14.5}px`;
    const badge = badgePlace(w, hh);
    this.shelfBadge.style.left = `${badge.left}px`;
    this.shelfBadge.style.top = `${badge.top}px`;
'''),
('''    syncMiniBotStates(State.tasks);
    this.engine.setState(State.effectiveState);
  }
''', '''    // The shelf's badge: a function of the mode and the count. Nothing here opens, reveals or expands the island (shelf/badge.ts).
    const showBadge = badgeShown(State.mode, State.shelf.count, greetingActive);
    this.shelfBadge.style.opacity = showBadge ? "1" : "0";
    this.shelfBadge.style.pointerEvents = showBadge ? "auto" : "none";
    this.shelfBadge.textContent = badgeLabel(State.shelf.count);
    this.shelfBadge.title = badgeTitle(State.shelf.count);

    syncMiniBotStates(State.tasks);
    this.engine.setState(State.effectiveState);
  }
'''),
# openShelf and askShelf
('''  /** Whether the OS has a global cursor (Boot's `cursorPoll`). */''', '''  /**
   * The shelf opens: from the tray's item, the badge, a drop on the Shelf half. A hidden island comes up on it (an explicit act of the user, never the shelf's own doing). Whether
   * the originals are still there is looked at now, and only now.
   */
  openShelf() {
    void State.shelf.refresh();
    this.alert("shelf");
  }

  /**
   * Ask, from a shelf tile: the file goes to the chat the way a drop on Ask does. The drop view opens with the file already over it, the desktop cat (if out) is waited for as for
   * any drop, and the catch plays; Rust copies the file into the inbox from the shelf's id (the page holds no path), and the chat starts new with it.
   */
  private askShelf(id: string) {
    const entry = State.shelf.entries.find((e) => e.id === id);
    if (!entry || !State.shelf.canAsk(id)) return;
    UploadSeq.enterZone(USC.REST_X, USC.REST_Y);
    this.uploadCanvas.hover(true);
    this.setView("upload");
    this.whenCatIsHere(() => this.swallow(entry.name, () => Bridge.shelfAsk(id)));
  }

  /** Whether the OS has a global cursor (Boot's `cursorPoll`). */'''),
('''  private swallow(path: string) {''', '''  private swallow(path: string, ingest: (path: string) => Promise<DroppedFile> = (p) => Bridge.ingestFile(p)) {'''),
('''    void Bridge.ingestFile(path)
      .then(async (file) => {''', '''    void ingest(path)
      .then(async (file) => {'''),
('''      // The shelf's tiles: Ask is Task 7, Send and Show in folder Task 9, dragging out Task 8.
      shelf: { ask: () => {}, send: () => {}, reveal: () => {}, dragOut: () => {} },''', '''      // The shelf's tiles: Send and Show in folder are Task 9, dragging out Task 8.
      shelf: { ask: (id) => this.askShelf(id), send: () => {}, reveal: () => {}, dragOut: () => {} },'''),
])

edit("windows/src/main.ts", [
('''      case "desktop":
        void desktop.toggle();
        break;''', '''      case "desktop":
        void desktop.toggle();
        break;
      case "shelf":
        setPaused(false);
        island.openShelf();
        break;'''),
])

edit("windows/src-tauri/src/tray.rs", [
('''// Notification-area icon: Open, Settings, Pause, Quit.''', '''// Notification-area icon: Open, Shelf, Cat on the desktop, Settings, Pause, Quit.'''),
('''    let desktop = MenuItem::with_id(app, "desktop", "Cat on the desktop", true, None::<&str>)?;
''', '''    let shelf = MenuItem::with_id(app, "shelf", "Shelf", true, None::<&str>)?;
    let desktop = MenuItem::with_id(app, "desktop", "Cat on the desktop", true, None::<&str>)?;
'''),
('''    let menu = Menu::with_items(app, &[&open, &desktop, &sep1, &settings, &pause, &sep2, &quit])?;''', '''    let menu = Menu::with_items(app, &[&open, &shelf, &desktop, &sep1, &settings, &pause, &sep2, &quit])?;'''),
])
# Task 5's pin on swallow follows its one new default parameter: a drop on Ask still ingests the path it was given.
edit("windows/scripts/cat-tests/shelf-drop.test.mjs", [
('''  assert.match(isl, /private swallow\\(path: string\\) \\{\\s*const name = path\\.split/, "swallow still takes one path");''', '''  assert.match(isl, /private swallow\\(path: string, ingest: \\(path: string\\) => Promise<DroppedFile> = \\(p\\) => Bridge\\.ingestFile\\(p\\)\\) \\{\\s*const name = path\\.split/, "swallow still takes one path, and ingests it with Bridge.ingestFile unless told otherwise");'''),
])

print("applied")
PYEOF
```

Expected: `applied`

```bash
cat >> windows/src/style.css <<'EOF'

/* The shelf's badge: a count at the right end of the compact island's wing. Shown only while the island is compact (the page decides), and it takes the mouse only then. */
#shelf-badge {
  position: absolute;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  border: 0;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.16);
  color: #e9ebee;
  font: 600 10px/16px var(--font);
  text-align: center;
  opacity: 0;
  pointer-events: none;
  cursor: default;
  transition: opacity 0.25s ease-in-out, background 0.12s;
}

#shelf-badge:hover {
  background: rgba(255, 255, 255, 0.28);
}
EOF
```

- [ ] **Step 5: Run the checks**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-badge.test.mjs scripts/cat-tests/shelf-drop.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: `# pass 11`, `# fail 0`, `tsc exit 0`, `ℹ tests 415`, `ℹ pass 415`, `ℹ fail 0`.

- [ ] **Step 6: Prove the badge and Ask bite**

Run:

```bash
cd windows
m() { python3 ../.claude/checkpoints/g1-tauri/mut.py "$@"; }; T=scripts/cat-tests/shelf-badge.test.mjs
m src/shelf/badge.ts 'return mode === "compact" && count > 0' 'return mode !== "expanded" && count > 0' $T
m src/shelf/badge.ts 'count > 9 ? "9+"' 'count > 99 ? "9+"' $T
m src/island/island.ts '    this.shelfBadge.addEventListener("mousedown", (e) => e.stopPropagation());' '' $T
m src/island/island.ts '    this.whenCatIsHere(() => this.swallow(entry.name, () => Bridge.shelfAsk(id)));' '    this.swallow(entry.name, () => Bridge.shelfAsk(id));' $T
m src-tauri/src/tray.rs '&[&open, &shelf, &desktop,' '&[&open, &desktop,' $T
cd ..
```

Expected: each line ends `# pass 4 # fail 1`.

- [ ] **Step 7: Look at the badge, the hidden island and Ask in the dev island**

Start the dev server, then:


```bash
S=g1-badge; cd .claude/checkpoints/g1-tauri
pw() { playwright-cli -s="$S" "$@"; }
ev() { pw eval "$1" 2>&1 | grep -A1 "### Result" | tail -1; }
pw open 'http://127.0.0.1:14631/' > /dev/null 2>&1; pw resize 760 360 > /dev/null 2>&1; sleep 7
ev "(() => { const {island, State} = window.__nm; island.collapse(); return State.mode; })()"
sleep 1
ev "(() => document.querySelector('#shelf-badge').style.opacity)()"
ev "(async () => { const {State} = window.__nm; await State.shelf.add(['C:/a.pdf','C:/b.txt','C:/c.md']); await new Promise(r => setTimeout(r, 700)); const b = document.querySelector('#shelf-badge'); return JSON.stringify([State.mode, b.textContent, b.style.opacity, b.style.pointerEvents]); })()"
pw screenshot --filename="$(pwd)/badge-compact.png" > /dev/null 2>&1
ev "(() => { const {island, State} = window.__nm; island.fsm.forceHidden(); return State.mode; })()"
sleep 1
ev "(async () => { const {State} = window.__nm; await State.shelf.add(['C:/d.txt']); await new Promise(r => setTimeout(r, 500)); return JSON.stringify([State.mode, State.shelf.count, document.querySelector('#shelf-badge').style.opacity]); })()"
ev "(() => { const {island, State} = window.__nm; island.fsm.forcePetit(); return State.mode; })()"
sleep 1
ev "(() => { document.querySelector('#shelf-badge').click(); return window.__nm.State.view + '/' + window.__nm.State.mode; })()"
sleep 1.2
pw screenshot --filename="$(pwd)/shelf-from-badge.png" > /dev/null 2>&1
ev "(() => { document.querySelector('.sh-tile .sh-act[title=\"Ask about it\"]').click(); return window.__nm.State.view; })()"
sleep 0.5
ev "(() => { const {State} = window.__nm; return JSON.stringify([State.view, State.droppedFile && State.droppedFile.name]); })()"
pw screenshot --filename="$(pwd)/shelf-ask.png" > /dev/null 2>&1
pw console 2>&1 | grep '\[ERROR\]' | grep -v favicon | head -3
pw close > /dev/null 2>&1
cd ../..
```

Expected: `"compact"`, `"0"` (no badge on an empty shelf), `"[\"compact\",\"3\",\"1\",\"auto\"]"`, `"hidden"`, `"[\"hidden\",4,\"0\"]"` (a file added while the island is hidden: the island stays hidden and the badge stays off), `"compact"`, `"shelf/expanded"` (a press on the badge opens the shelf), `"uploading"` (Ask starts the catch at once) and then a `note` view, because a plain browser has no Rust to copy the file: the dev island shows its error note, which is the same path a refused drop takes. `badge-compact.png` shows the island's right ear with the 2x2 grid and a small "3" after it; `shelf-from-badge.png` the shelf with four tiles. Say what you see.

- [ ] **Step 8: The Rust (needs the image)**

Run:

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh check -p notchmeow --target-dir /repo/windows/target/g1-tauri 2>&1 | grep -E "^error|^warning|Finished" | head -10 || echo "image missing or the daemon is down: owed"
```

Expected: `Finished` and no `error` and no `warning` (or the line saying the Rust is owed).

- [ ] **Step 9: Commit**


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/src/shelf/badge.ts windows/scripts/cat-tests/shelf-badge.test.mjs windows/scripts/cat-tests/shelf-drop.test.mjs windows/src/island/island.ts windows/src/main.ts windows/src-tauri/src/tray.rs windows/src/shelf/devshelf.ts windows/src/style.css
git commit -F - <<'MSG'
feat(shelf): the tray item, the compact badge and Ask from a tile

The shelf opens from a tray item and from a small count at the right end of the compact island, which shows only while the island is already compact and never wakes a hidden one. Ask on a tile starts the same catch as a drop on Ask, with Rust copying the file into the inbox from the shelf's id.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, the agent and the model.

---

# Stage 6: drag out

### Task 8: Drag out in the shelf: the guard, `shelf_drag_out`, the boot info

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Create: `windows/src/shelf/dragguard.ts`, `windows/scripts/cat-tests/shelf-dragout.test.mjs`
- Modify: `windows/src-tauri/src/lib.rs`, `windows/src/core/bridge.ts`, `windows/src/main.ts`, `windows/src/island/island.ts`

**Interfaces:**
- Consumes: Task 1's `dragout::start`, `dragout::supported`; Task 3's `Store::resolve`; Task 6's `ShelfActions.dragOut`, `State.shelfCaps`.
- Produces: `DragOutGuard { start(), end(now), active, blocks(now) }`, `DRAG_OUT_GRACE_MS` (600); the command `shelf_drag_out(ids)`; the boot info's `shelf: { dragOut, send }`; `Bridge.shelfDragOut(ids)`; `Island.dragOutShelf`.

**Design.** A press that moves 4 px on a tile (Task 6) asks `island.dragOutShelf(ids)`: the island is held open for the drag (`holdOpen`), Rust resolves the ids to the files that still exist and runs the system's drag (`dragout::start`), and when it ends (dropped, cancelled or failed) the island lets go and tells the page. **A drag event that comes back to the island during the drag, and for 600 ms after it, is the item's own** (the system reports the drop on its own schedule, sometimes after the call returned) and is ignored before the halves and the Ask drop see it: an item dragged out and back is not added twice, and the drop view does not open under the drag. A second drag does not start while one runs. **If the owner has answered Checkpoint 0 with a failure, apply the fallback now:** the controller sets `dragout::WINDOWS` or `dragout::LINUX` to `false` in this task's commit (Step 4 has the exact line); the tests accept either value.

- [ ] **Step 1: Write the test**


```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/shelf-dragout.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DRAG_OUT_GRACE_MS, DragOutGuard } from "../../src/shelf/dragguard.ts";

// Dragging a shelf item out of the island (G1): the guard that keeps an item dragged out and back in from being added twice, and how the island wires the native drag source.
const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const isl = read("src/island/island.ts");

test("the guard blocks the item's own drop during the drag and for a short grace after it, and nothing else", () => {
  const g = new DragOutGuard();
  assert.equal(g.blocks(0), false, "nothing is blocked before any drag");
  assert.equal(g.blocks(1e9), false);
  g.start();
  assert.equal(g.active, true);
  assert.equal(g.blocks(5), true);
  assert.equal(g.blocks(1e9), true, "a drag can last as long as the user likes");
  g.end(10_000);
  assert.equal(g.active, false);
  assert.equal(g.blocks(10_000 + DRAG_OUT_GRACE_MS - 1), true, "the drop the system reports after the call returned");
  assert.equal(g.blocks(10_000 + DRAG_OUT_GRACE_MS), false);
  g.start();
  g.end(20_000);
  assert.equal(g.blocks(20_100), true, "a second drag has its own grace");
});

test("the island ignores every drag event during and just after its own drag, before the halves and the Ask drop see it", () => {
  const handler = isl.slice(isl.indexOf("private onDragDrop("), isl.indexOf("switch (e.type) {", isl.indexOf("private onDragDrop(")));
  assert.match(handler, /if \(State\.paused\) return;\s*\/\/ An item dragged out of the shelf[^\n]*\n\s*if \(this\.dragOut\.blocks\(performance\.now\(\)\)\) return;/);
});

test("a drag out keeps the island open while it lasts, asks Rust by id, and lets go of the pin and tells the page when it ends, whatever the end", () => {
  const out = isl.match(/private dragOutShelf\(ids: string\[\]\) \{[\s\S]*?\n  \}\n/)[0];
  assert.match(out, /if \(!State\.shelfCaps\.dragOut \|\| this\.dragOut\.active \|\| ids\.length === 0\) return;\s*this\.dragOut\.start\(\);\s*this\.holdOpen\(\);/);
  assert.match(out, /Bridge\.shelfDragOut\(ids\)\s*\.catch\(\(err\) => void Bridge\.log\(`drag out failed: \$\{String\(err\)\}`\)\)\s*\.finally\(\(\) => \{\s*this\.dragOut\.end\(performance\.now\(\)\);\s*this\.fsm\.pinned = State\.isPinned;\s*State\.notify\(\);/);
  assert.match(isl, /dragOut: \(ids\) => this\.dragOutShelf\(ids\) \},/);
  assert.doesNotMatch(out, /setTimeout|setInterval/, "the guard's grace is a comparison of times, not a timer");
});

test("Rust: the drag-out command resolves ids to the files that exist, and the boot info says what this system can do", () => {
  const lib = read("src-tauri/src/lib.rs");
  assert.match(lib, /async fn shelf_drag_out\(app: AppHandle, ids: Vec<String>\) -> Result<&'static str, String> \{\s*let paths = blocking\(move \|\| shelf_store\(\)\.resolve\(&ids\)\)\.await\?;\s*dragout::start\(&app, paths\)\.await/);
  assert.match(lib, /shelf: ShelfCaps \{ drag_out: dragout::supported\(\), send: [^}]+ \},/, "the drag out comes from the one switch in dragout.rs");
  assert.match(read("src/core/bridge.ts"), /shelf: \{ dragOut: boolean; send: boolean \};/);
  assert.match(read("src/main.ts"), /if \(boot\?\.shelf\) State\.shelfCaps = \{ dragOut: boot\.shelf\.dragOut, send: boot\.shelf\.send \};/);
});

test("with no drag out (the fallback), a press on a tile only ticks it and the view shows no drag", async () => {
  const { State } = await import("../../src/core/state.ts");
  assert.equal(State.shelfCaps.dragOut, false, "off until Rust says it can");
  assert.match(read("src/views/shelf.ts"), /if \(State\.shelfCaps\.dragOut && !e\.missing\) act\.dragOut\(ids\(\)\);/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-dragout.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ERR_MODULE_NOT_FOUND" | head -3
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 3: Write the guard and wire the drag out**


```bash
mkdir -p windows/src/shelf
cat > windows/src/shelf/dragguard.ts <<'EOF'
// The guard around a drag out of the island (sub-project G1). While a shelf item is being dragged away, and for a moment after, a drop event that comes back to the island is the item's
// own: it must not be taken as a new drop (an item dragged out and back in is not added twice, and the drop view must not open under the drag). The system reports the drop on its own
// schedule, sometimes after the drag call has returned, so the guard outlasts the call by a short grace. Pure, so the plain-Node checks load it.

/** How long after a drag ends a drop event still counts as the drag's own (ms). */
export const DRAG_OUT_GRACE_MS = 600;

export class DragOutGuard {
  private on = false;
  private endedAt = -Infinity;

  /** A drag out has started. */
  start(): void { this.on = true; }

  /** The drag call has returned (dropped, cancelled or failed). `now` in ms. */
  end(now: number): void { this.on = false; this.endedAt = now; }

  /** A drag out is under way: a second one is not started. */
  get active(): boolean { return this.on; }

  /** Whether a drag or drop event at `now` belongs to the item's own drag: during it, and for the grace after. */
  blocks(now: number): boolean { return this.on || now - this.endedAt < DRAG_OUT_GRACE_MS; }
}
EOF
```

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src-tauri/src/lib.rs", [
('''    /// False where the system places windows itself (GNOME): Settings says so under the desktop cat's switch.
    desktop_positioned: bool,
}''', '''    /// False where the system places windows itself (GNOME): Settings says so under the desktop cat's switch.
    desktop_positioned: bool,
    /// What the shelf can do on this system: drag a file out of the island, send it through the system's share.
    shelf: ShelfCaps,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ShelfCaps {
    drag_out: bool,
    send: bool,
}'''),
('''        desktop_positioned: platform::desktop_positioned(),
    }''', '''        desktop_positioned: platform::desktop_positioned(),
        shelf: ShelfCaps { drag_out: dragout::supported(), send: false },
    }'''),
('''/// Ask: the shelf item goes into the inbox''', '''/// Drag out of the island: Rust finds the files from the ids (the page holds no path), and a native drag source (dragout.rs) carries them until the user lets go.
/// Resolves with `copied`, `none` or `cancelled`.
#[tauri::command]
async fn shelf_drag_out(app: AppHandle, ids: Vec<String>) -> Result<&'static str, String> {
    let paths = blocking(move || shelf_store().resolve(&ids)).await?;
    dragout::start(&app, paths).await
}

/// Ask: the shelf item goes into the inbox'''),
('''            shelf_ask,
''', '''            shelf_ask,
            shelf_drag_out,
'''),
])

edit("windows/src/core/bridge.ts", [
('''  /** Whether the desktop cat's window can be put where we want it: false on GNOME, where Settings says so under the switch. */
  desktopPositioned: boolean;
}''', '''  /** Whether the desktop cat's window can be put where we want it: false on GNOME, where Settings says so under the switch. */
  desktopPositioned: boolean;
  /** What the shelf can do here (sub-project G1): drag a file out of the island, send it through the system's share. */
  shelf: { dragOut: boolean; send: boolean };
}'''),
('''  /** Ask: Rust copies the shelf item into the inbox like a drop on Ask, and the chat starts with it. */''', '''  /** Drag these shelf items out of the island (the pointer is down). Resolves when the drag ends: "copied", "none" or "cancelled". */
  shelfDragOut: (ids: string[]) => callOrThrow<string>("shelf_drag_out", { ids }),
  /** Ask: Rust copies the shelf item into the inbox like a drop on Ask, and the chat starts with it. */'''),
])

edit("windows/src/main.ts", [
('''  island.setCursorPoll(boot ? boot.cursorPoll : true);''', '''  island.setCursorPoll(boot ? boot.cursorPoll : true);
  if (boot?.shelf) State.shelfCaps = { dragOut: boot.shelf.dragOut, send: boot.shelf.send };'''),
])

edit("windows/src/island/island.ts", [
('''import { dropZone, planDrop } from "../shelf/dropflow";
''', '''import { DragOutGuard } from "../shelf/dragguard";
import { dropZone, planDrop } from "../shelf/dropflow";
'''),
('''  /** The last position a drag event carried (physical px of the webview). */
  private dragPos: { x: number; y: number } | null = null;
''', '''  /** The last position a drag event carried (physical px of the webview). */
  private dragPos: { x: number; y: number } | null = null;
  /** A shelf item is being dragged out of the island, or just was: a drop that comes back to the island is its own (shelf/dragguard.ts). */
  private dragOut = new DragOutGuard();
'''),
('''    if (State.paused) return;
    switch (e.type) {
      case "enter":
      case "over": {
        this.noteDragPosition(e.position);''', '''    if (State.paused) return;
    // An item dragged out of the shelf and dropped back on the island is not a new drop, and the drop view must not open under the drag.
    if (this.dragOut.blocks(performance.now())) return;
    switch (e.type) {
      case "enter":
      case "over": {
        this.noteDragPosition(e.position);'''),
('''  /** Whether the OS has a global cursor (Boot's `cursorPoll`). */''', '''  /**
   * Drags these shelf items out of the island, to anywhere (Explorer, the file manager, mail, a chat). The island stays open while the drag lasts, and a drop that comes back to it is
   * ignored (`dragOut`). Rust finds the files from the ids and carries them with the system's own drag (dragout.rs).
   */
  private dragOutShelf(ids: string[]) {
    if (!State.shelfCaps.dragOut || this.dragOut.active || ids.length === 0) return;
    this.dragOut.start();
    this.holdOpen();
    Bridge.shelfDragOut(ids)
      .catch((err) => void Bridge.log(`drag out failed: ${String(err)}`))
      .finally(() => {
        this.dragOut.end(performance.now());
        this.fsm.pinned = State.isPinned;
        State.notify();
      });
  }

  /** Whether the OS has a global cursor (Boot's `cursorPoll`). */'''),
('''      // The shelf's tiles: Send and Show in folder are Task 9, dragging out Task 8.
      shelf: { ask: (id) => this.askShelf(id), send: () => {}, reveal: () => {}, dragOut: () => {} },''', '''      // The shelf's tiles: Send and Show in folder are Task 9.
      shelf: { ask: (id) => this.askShelf(id), send: () => {}, reveal: () => {}, dragOut: (ids) => this.dragOutShelf(ids) },'''),
])
print("applied")
PYEOF
```

Expected: `applied`

- [ ] **Step 4: The fallback, only if the owner's answer to Checkpoint 0 was a failure**

If a system failed, flip its switch (one of these, run from the repository root; skip this step if nothing failed or nobody has answered yet):


```bash
# Linux failed:
sed -i.bak 's/^pub const LINUX: bool = true;/pub const LINUX: bool = false;/' windows/src-tauri/src/dragout.rs && trash windows/src-tauri/src/dragout.rs.bak
# Windows failed:
sed -i.bak 's/^pub const WINDOWS: bool = true;/pub const WINDOWS: bool = false;/' windows/src-tauri/src/dragout.rs && trash windows/src-tauri/src/dragout.rs.bak
```

Expected: nothing printed. `grep -n "^pub const" windows/src-tauri/src/dragout.rs` shows the switch at `false`. With a system at `false` its boot info says `dragOut: false`, the tiles are only ticked by a click, and Task 10 edits the README sentence.

- [ ] **Step 5: Run the checks**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-dragout.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: `# pass 5`, `# fail 0`, `tsc exit 0`, `ℹ tests 420`, `ℹ pass 420`, `ℹ fail 0`.

- [ ] **Step 6: Prove the guard and the wiring bite**

Run:

```bash
cd windows
m() { python3 ../.claude/checkpoints/g1-tauri/mut.py "$@"; }; T=scripts/cat-tests/shelf-dragout.test.mjs
m src/shelf/dragguard.ts 'return this.on || now - this.endedAt < DRAG_OUT_GRACE_MS;' 'return this.on;' $T
m src/island/island.ts '    if (this.dragOut.blocks(performance.now())) return;
' '' $T
m src/island/island.ts '    this.holdOpen();
    Bridge.shelfDragOut(ids)' '    Bridge.shelfDragOut(ids)' $T
m src-tauri/src/lib.rs 'shelf: ShelfCaps { drag_out: dragout::supported(), send: false },' 'shelf: ShelfCaps { drag_out: true, send: false },' $T
cd ..
```

Expected: each line ends `# pass 4 # fail 1`.

- [ ] **Step 7: The Rust (needs the image)**

Run:

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh check -p notchmeow --target-dir /repo/windows/target/g1-tauri 2>&1 | grep -E "^error|^warning|Finished" | head -10 || echo "image missing or the daemon is down: owed"
```

Expected: `Finished` and no `error` and no `warning` (or the line saying the Rust is owed).

- [ ] **Step 8: Commit**


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/src/shelf/dragguard.ts windows/scripts/cat-tests/shelf-dragout.test.mjs windows/src-tauri/src/lib.rs windows/src-tauri/src/dragout.rs windows/src/core/bridge.ts windows/src/main.ts windows/src/island/island.ts
git commit -F - <<'MSG'
feat(shelf): drag a shelf item out of the island

A press that moves on a tile asks Rust, by id, for the system's own drag of the files. The island stays open for the drag, and a drop event that comes back to it during the drag or just after is the item's own and is ignored, so an item dragged out and back is not added twice. The boot info says whether this system can.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, whether a fallback was applied, the agent and the model.

---

# Stage 7: Send and Show in folder

### Task 9: Send (Windows Share) and Show in folder

**Agent:** `nm-implementer-deep` (Sonnet 5.5, high), **trigger 1** (the spec asks for a short spike of the Share window: it is opened from a window that never takes focus, through WinRT from a click-through layered window; and Linux's file manager is a D-Bus call). Loads `superpowers:systematic-debugging` too.

**Files:**
- Create: `windows/src-tauri/src/platform/windows/share.rs`, `windows/scripts/cat-tests/shelf-send.test.mjs`
- Modify: `windows/src-tauri/src/lib.rs`, `windows/src-tauri/src/platform/windows.rs`, `windows/src-tauri/src/platform/linux.rs`, `windows/src-tauri/src/dragout.rs`, `windows/src-tauri/Cargo.toml`, `windows/Cargo.lock`, `windows/src/core/bridge.ts`, `windows/src/views/shelf.ts`, `windows/src/shelf/devshelf.ts`, `windows/src/island/island.ts`

**Interfaces:**
- Consumes: Task 3's `Store::resolve`, `blocking`; Task 8's boot info `shelf`; the existing `platform::set_activating`, `hwnd_of`, `reveal_folder`, `log::line`.
- Produces: `platform::SHARE` (true on Windows, false on Linux), `platform::share_files(&WebviewWindow, &[PathBuf]) -> Result<(), String>`, `platform::reveal_file(&Path)`, `dragout::show_items_args(&Path) -> Vec<String>`; the commands `shelf_reveal(id)` and `shelf_send(ids)`; `Bridge.shelfReveal(id)`, `Bridge.shelfSend(ids)`; `ShelfActions.reveal(id: string)` (one id now); `Island.sendShelf`, `revealShelf`.

**Design.** *Send (Windows):* two steps on two threads. On a worker thread the paths become WinRT storage items (the WinRT `.get()` blocks, as in the OCR code of `ai/attachments.rs`); on the main thread the island's window is made activatable for the moment (`set_activating`, `set_focus`: the Share window needs a foreground owner, and the island never takes focus), `IDataTransferManagerInterop::ShowShareUIForWindow` is asked for over it, and its `DataRequested` event is answered with the items (`SetStorageItems`, read-only). Folders are shared as folders. Sending always starts with a click, and the log says only `shelf send started`. The island holds itself open for 15 s afterwards (nothing tells us when the system's window closes: Open question 6). **Linux has no system share**, so there is no Send there (`SHARE = false`, no button). *Show in folder:* Windows `explorer /select,"path"` (with `raw_arg`, because Explorer reads that with its own rules); Linux the freedesktop `FileManager1.ShowItems` call through `gdbus` (it ships with GLib: no dependency), and the folder opened with `xdg-open` where no file manager answers. It acts on the tile's own file (Open question 4). **If the Share window will not open on a real machine** (the owner's check), the fallback is `pub const SHARE: bool = false;` in `platform/windows.rs`: Windows keeps Ask and Show in folder.

**The one dependency decision (Open question 1):** `DataPackage::SetStorageItems` takes an `IIterable<IStorageItem>`, a type of the crate `windows-collections`, which the `windows` crate uses but does not re-export. The app therefore names it: `windows-collections = "0.2"` in the Windows dependencies, the version already in `Cargo.lock`, and Cargo's lock file gains that one edge (Step 3).

- [ ] **Step 1: Write the test**


```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/shelf-send.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Send and Show in folder (G1). The Share window and the file managers are the system's; what a test can pin is who calls what, on which thread, with what, and that the shelf never logs
// a name or a recipient.
const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const lib = read("src-tauri/src/lib.rs"), isl = read("src/island/island.ts");
const win = read("src-tauri/src/platform/windows.rs"), lin = read("src-tauri/src/platform/linux.rs"), share = read("src-tauri/src/platform/windows/share.rs");

test("Send is the Windows Share window and Linux has none: one switch per system, read by the boot info, by the command and by the view", () => {
  assert.match(win, /pub const SHARE: bool = (?:true|false);/, "the fallback, if the Share window will not open from the island, is this one word");
  assert.match(lin, /pub const SHARE: bool = false;/);
  assert.match(lin, /pub fn share_files\(_win: &WebviewWindow, _paths: &\[PathBuf\]\) -> Result<\(\), String> \{\s*Err\(/);
  assert.match(lib, /shelf: ShelfCaps \{ drag_out: dragout::supported\(\), send: platform::SHARE \},/);
  assert.match(lib, /async fn shelf_send\(app: AppHandle, ids: Vec<String>\) -> Result<\(\), String> \{\s*if !platform::SHARE \{/);
  assert.match(read("src/views/shelf.ts"), /e\.missing \|\| !State\.shelfCaps\.send \? null/, "no Send button where the system has no share");
});

test("the Windows Share window: files are resolved on a worker thread, the window is asked for on the main thread, over the island's window made activatable for the moment", () => {
  assert.match(win, /let items = share::prepare\(paths\)\?;/);
  assert.match(win, /win\.run_on_main_thread\(move \|\| \{\s*set_activating\(&target, true\);\s*let _ = target\.set_focus\(\);\s*let shown = share::show\(HWND\(raw as \*mut _\), items\);\s*set_activating\(&target, false\);/);
  assert.match(lib, /blocking\(move \|\| \{\s*let paths = shelf_store\(\)\.resolve\(&ids\);\s*if paths\.is_empty\(\) \{\s*return Err\("Those files are gone\.".to_string\(\)\);\s*\}\s*log::line\("shelf send started"\);\s*platform::share_files\(&win, &paths\)/);
  assert.match(share, /DataTransferManager, IDataTransferManagerInterop|factory::<DataTransferManager, IDataTransferManagerInterop>\(\)/);
  assert.match(share, /interop\.ShowShareUIForWindow\(window\)/);
  assert.match(share, /\.SetStorageItems\(&IIterable::<IStorageItem>::from\(/);
});

test("the log says only that a send started: no name, no path, no id, no recipient anywhere in the send or show code", () => {
  const send = lib.slice(lib.indexOf("async fn shelf_reveal"), lib.indexOf("/// Ask: the shelf item"));
  assert.deepEqual([...send.matchAll(/log::line\(([^)]*)\)/g)].map((m) => m[1]), ['"shelf send started"']);
  assert.doesNotMatch(share, /log::|println!|eprintln!/);
  assert.doesNotMatch(isl.slice(isl.indexOf("private sendShelf"), isl.indexOf("/** Whether the OS has a global cursor")), /Bridge\.log\([^)]*ids/);
});

test("Show in folder selects the file: Explorer's /select with its own quoting on Windows, the file manager's ShowItems on Linux, the folder as the fallback; one item, by id", () => {
  assert.match(win, /Command::new\("explorer"\)\.raw_arg\(format!\("\/select,\\"\{\}\\"", path\.display\(\)\)\)\.spawn\(\);/);
  assert.match(lin, /Command::new\("gdbus"\)\.args\(crate::dragout::show_items_args\(path\)\)\.status\(\)/);
  assert.match(lin, /if !asked \{\s*if let Some\(parent\) = path\.parent\(\) \{\s*reveal_folder\(&parent\.to_string_lossy\(\)\);/);
  assert.match(lib, /async fn shelf_reveal\(id: String\) -> Result<\(\), String>/);
  assert.match(read("src/views/shelf.ts"), /act\.reveal\(e\.id\)/);
});

test("the island holds itself open for the Share window and lets go afterwards; Send and Show do nothing the system cannot", () => {
  const out = isl.slice(isl.indexOf("private sendShelf(ids: string[]) {"), isl.indexOf("/** Whether the OS has a global cursor"));
  assert.match(out, /if \(!State\.shelfCaps\.send \|\| ids\.length === 0\) return;\s*this\.holdOpen\(\);\s*Bridge\.shelfSend\(ids\)/);
  assert.match(out, /\.finally\(\(\) => window\.setTimeout\(\(\) => \{ this\.fsm\.pinned = State\.isPinned; \}, SEND_HOLD_MS\)\);/);
  assert.match(isl, /const SEND_HOLD_MS = 15_000;/);
  assert.match(isl, /shelf: \{ ask: \(id\) => this\.askShelf\(id\), send: \(ids\) => this\.sendShelf\(ids\), reveal: \(id\) => this\.revealShelf\(id\), dragOut: \(ids\) => this\.dragOutShelf\(ids\) \},/);
});

test("the Windows build names the crate and the features the Share window uses, and the lock file gains exactly that one edge", () => {
  const toml = read("src-tauri/Cargo.toml");
  assert.match(toml, /windows-collections = "0\.2"/);
  for (const f of ["ApplicationModel", "ApplicationModel_DataTransfer", "Foundation_Collections"]) assert.match(toml, new RegExp(`"${f}"`), f);
  assert.match(read("Cargo.lock"), / "windows 0\.61\.3",\n "windows-collections 0\.2\.0",\n "zip",\n\]/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-send.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
cd ..
```

Expected: `# fail` greater than 0 (the Windows `share.rs`, `SHARE` and the commands are not there).

- [ ] **Step 3: Write the Share window and wire Send and Show in folder**

`share.rs` is written against the `windows` 0.61.3 sources (its WinRT types and `IDataTransferManagerInterop`); nothing the session can run compiles it.


```bash
mkdir -p windows/src-tauri/src/platform/windows
cat > windows/src-tauri/src/platform/windows/share.rs <<'EOF'
// The system's Share window for files (sub-project G1, Windows): `DataTransferManager`, reached through `IDataTransferManagerInterop` the way a desktop program that is not a packaged app
// has to. Two steps, because they live on different threads:
//   1. `prepare` (a worker thread): turns the paths into WinRT storage items. The WinRT `.get()` blocks, so it never runs on the main thread (the same rule as the OCR in ai/attachments.rs).
//   2. `show` (the main thread): asks for the Share window over the island's window and answers its `DataRequested` event with those items.
// Sending always starts with the user's click, and the log says only that a send started, never what or to whom: what the user picks in the Share window is the system's, and never ours.

use std::path::PathBuf;

use ::windows::core::{factory, Interface, HSTRING};
use ::windows::ApplicationModel::DataTransfer::{DataRequestedEventArgs, DataTransferManager};
use ::windows::Foundation::TypedEventHandler;
use ::windows::Storage::{IStorageItem, StorageFile, StorageFolder};
use ::windows::Win32::Foundation::HWND;
use ::windows::Win32::UI::Shell::IDataTransferManagerInterop;
use ::windows_collections::IIterable;

/// The files and folders as storage items. Folders are shared as folders.
pub fn prepare(paths: &[PathBuf]) -> Result<Vec<IStorageItem>, String> {
    let mut items = Vec::new();
    for p in paths {
        let path = HSTRING::from(p.as_os_str());
        let item: IStorageItem = if p.is_dir() {
            StorageFolder::GetFolderFromPathAsync(&path).and_then(|op| op.get()).and_then(|f| f.cast())
        } else {
            StorageFile::GetFileFromPathAsync(&path).and_then(|op| op.get()).and_then(|f| f.cast())
        }
        .map_err(|e| format!("cannot open {}: {e}", p.display()))?;
        items.push(item);
    }
    Ok(items)
}

/// Shows the Share window over `window` and hands it `items` when it asks. Returns when the window has been asked for, not when it is closed.
pub fn show(window: HWND, items: Vec<IStorageItem>) -> Result<(), String> {
    let interop = factory::<DataTransferManager, IDataTransferManagerInterop>().map_err(|e| e.to_string())?;
    let manager: DataTransferManager = unsafe { interop.GetForWindow(window) }.map_err(|e| e.to_string())?;
    let items = std::sync::Mutex::new(Some(items));
    manager
        .DataRequested(&TypedEventHandler::<DataTransferManager, DataRequestedEventArgs>::new(move |_, args| {
            let Some(args) = args.as_ref() else { return Ok(()) };
            let data = args.Request()?.Data()?;
            data.Properties()?.SetTitle(&HSTRING::from("Files from NotchMeow"))?;
            if let Some(items) = items.lock().ok().and_then(|mut i| i.take()) {
                data.SetStorageItems(&IIterable::<IStorageItem>::from(items.into_iter().map(Some).collect::<Vec<_>>()), true)?;
            }
            Ok(())
        }))
        .map_err(|e| e.to_string())?;
    unsafe { interop.ShowShareUIForWindow(window) }.map_err(|e| e.to_string())
}
EOF
```

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src-tauri/src/platform/windows.rs", [
('''mod drag;
''', '''mod drag;
mod share;
'''),
('''pub fn reveal_folder(path: &str) {''', '''/// Windows has a system Share window (platform/windows/share.rs).
pub const SHARE: bool = true;

/// Opens the system's Share window over the island with these files. Called from a worker thread: it resolves the files there, then shows the window on the main thread, with the
/// island's window made activatable for the moment (the Share window needs a foreground owner, and the island is a window that never takes focus).
pub fn share_files(win: &WebviewWindow, paths: &[PathBuf]) -> Result<(), String> {
    let items = share::prepare(paths)?;
    let raw = hwnd_of(win).ok_or_else(|| "The island window is not there.".to_string())?.0 as isize;
    let target = win.clone();
    let (tx, rx) = std::sync::mpsc::channel();
    win.run_on_main_thread(move || {
        set_activating(&target, true);
        let _ = target.set_focus();
        let shown = share::show(HWND(raw as *mut _), items);
        set_activating(&target, false);
        let _ = tx.send(shown);
    })
    .map_err(|e| e.to_string())?;
    rx.recv().map_err(|e| e.to_string())?
}

/// Show in Explorer: the folder opens with the file selected. `raw_arg`, because Explorer reads `/select,"C:\\a b\\c.txt"` with its own rules and Rust's quoting would add a second pair.
pub fn reveal_file(path: &std::path::Path) {
    let _ = Command::new("explorer").raw_arg(format!("/select,\\"{}\\"", path.display())).spawn();
}

pub fn reveal_folder(path: &str) {'''),
])
edit("windows/src-tauri/src/platform/linux.rs", [
('''pub fn reveal_folder(path: &str) {''', '''/// Linux has no system share.
pub const SHARE: bool = false;

pub fn share_files(_win: &WebviewWindow, _paths: &[PathBuf]) -> Result<(), String> {
    Err("There is no system share on this system. Use Show in folder.".into())
}

/// Show in the file manager with the file selected, through the freedesktop `FileManager1.ShowItems` call (GNOME Files, Dolphin, Nautilus, Thunar and others answer it); a system
/// whose file manager does not, gets the folder opened instead. `gdbus` ships with GLib, so this adds no dependency.
pub fn reveal_file(path: &Path) {
    let asked = Command::new("gdbus").args(crate::dragout::show_items_args(path)).status().map(|s| s.success()).unwrap_or(false);
    if !asked {
        if let Some(parent) = path.parent() {
            reveal_folder(&parent.to_string_lossy());
        }
    }
}

pub fn reveal_folder(path: &str) {'''),
])
edit("windows/src-tauri/src/dragout.rs", [
('''/// Drags these files out of the island''', '''/// The arguments of `gdbus` for the freedesktop call that shows a file selected in the user's file manager: `FileManager1.ShowItems(["file://…"], "")`.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn show_items_args(path: &Path) -> Vec<String> {
    // `file_uri` escapes everything but letters, digits and `-._~/`, so the URI holds no quote that could end the list early.
    let list = format!("['{}']", file_uri(path));
    ["call", "--session", "--dest", "org.freedesktop.FileManager1", "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems"]
        .iter()
        .map(|s| s.to_string())
        .chain([list, String::new()])
        .collect()
}

/// Drags these files out of the island'''),
('''    #[test]
    fn the_fallback_is_the_constant''', '''    #[test]
    fn show_in_folder_asks_the_file_manager_by_gdbus_with_a_uri_list_that_cannot_break_out_of_its_quotes() {
        let args = show_items_args(Path::new("/home/me/it's here/a b.txt"));
        assert_eq!(args[..8], ["call", "--session", "--dest", "org.freedesktop.FileManager1", "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems"]);
        assert_eq!(args[8], "['file:///home/me/it%27s%20here/a%20b.txt']");
        assert_eq!(args[9], "", "the startup id");
        assert_eq!(args.len(), 10);
    }

    #[test]
    fn the_fallback_is_the_constant'''),
])
print("applied")
PYEOF
```

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src-tauri/Cargo.toml", [
('''[target.'cfg(windows)'.dependencies]
keyring = { version = "3", features = ["windows-native"] }
windows = { version = "0.61", features = [
  "Data_Pdf",
  "Foundation",
''', '''[target.'cfg(windows)'.dependencies]
keyring = { version = "3", features = ["windows-native"] }
# The WinRT collection types the Share window's data needs (an IIterable of storage items). Microsoft's own, the one the `windows` crate below already builds on (it is in Cargo.lock
# already), named here because the `windows` crate does not re-export it.
windows-collections = "0.2"
windows = { version = "0.61", features = [
  "ApplicationModel",
  "ApplicationModel_DataTransfer",
  "Data_Pdf",
  "Foundation",
  "Foundation_Collections",
'''),
])

edit("windows/src-tauri/src/lib.rs", [
('''        shelf: ShelfCaps { drag_out: dragout::supported(), send: false },''', '''        shelf: ShelfCaps { drag_out: dragout::supported(), send: platform::SHARE },'''),
('''/// Ask: the shelf item goes into the inbox''', '''/// Show in Explorer or the file manager, with the file selected. One item: its id, and Rust finds the file.
#[tauri::command]
async fn shelf_reveal(id: String) -> Result<(), String> {
    blocking(move || {
        let path = shelf_store().resolve(&[id]).into_iter().next().ok_or_else(|| "That file is gone.".to_string())?;
        platform::reveal_file(&path);
        Ok(())
    })
    .await?
}

/// Send: the system's Share window (Windows) opens over the island with these items. Always started by a click; nothing but the fact that a send started is logged.
#[tauri::command]
async fn shelf_send(app: AppHandle, ids: Vec<String>) -> Result<(), String> {
    if !platform::SHARE {
        return Err("There is no system share on this system.".into());
    }
    let win = island::window(&app).ok_or_else(|| "The island window is not there.".to_string())?;
    blocking(move || {
        let paths = shelf_store().resolve(&ids);
        if paths.is_empty() {
            return Err("Those files are gone.".to_string());
        }
        log::line("shelf send started");
        platform::share_files(&win, &paths)
    })
    .await?
}

/// Ask: the shelf item goes into the inbox'''),
('''            shelf_drag_out,
''', '''            shelf_drag_out,
            shelf_reveal,
            shelf_send,
'''),
])

edit("windows/src/core/bridge.ts", [
('''  /** Ask: Rust copies the shelf item into the inbox like a drop on Ask, and the chat starts with it. */''', '''  /** Show in Explorer or the file manager, with the file selected. */
  shelfReveal: (id: string) => callOrThrow<void>("shelf_reveal", { id }),
  /** The system's Share window over the island (Windows only: `BootInfo.shelf.send`). Resolves when the window has been asked for. */
  shelfSend: (ids: string[]) => callOrThrow<void>("shelf_send", { ids }),
  /** Ask: Rust copies the shelf item into the inbox like a drop on Ask, and the chat starts with it. */'''),
])

edit("windows/src/views/shelf.ts", [
('''  /** Show in Explorer or the file manager. */
  reveal(ids: string[]): void;''', '''  /** Show in Explorer or the file manager, with this file selected. */
  reveal(id: string): void;'''),
('''    e.missing ? null : button("Show in folder", SHELF_ICONS.reveal, () => act.reveal(ids())),''', '''    e.missing ? null : button("Show in folder", SHELF_ICONS.reveal, () => act.reveal(e.id)),'''),
])
edit("windows/src/shelf/devshelf.ts", [
('''    reveal: (ids: string[]) => said(`reveal ${ids.join(",")}`),''', '''    reveal: (id: string) => said(`reveal ${id}`),'''),
])

edit("windows/src/island/island.ts", [
('''  /** Whether the OS has a global cursor (Boot's `cursorPoll`). */''', '''  /** Send, through the system's Share window (Windows). The island stays open a little while the window comes up; what the user picks in it is the system's. */
  private sendShelf(ids: string[]) {
    if (!State.shelfCaps.send || ids.length === 0) return;
    this.holdOpen();
    Bridge.shelfSend(ids)
      .catch((err) => void Bridge.log(`send failed: ${String(err)}`))
      .finally(() => window.setTimeout(() => { this.fsm.pinned = State.isPinned; }, SEND_HOLD_MS));
  }

  /** Show in Explorer or the file manager. */
  private revealShelf(id: string) {
    Bridge.shelfReveal(id).catch((err) => void Bridge.log(`show in folder failed: ${String(err)}`));
  }

  /** Whether the OS has a global cursor (Boot's `cursorPoll`). */'''),
('''/** Same margin as the Rust hit test (src-tauri/src/island.rs). */''', '''/** How long the island stays open after the Share window was asked for (ms): the window is the system's, and nothing tells us when it closes. */
const SEND_HOLD_MS = 15_000;
/** Same margin as the Rust hit test (src-tauri/src/island.rs). */'''),
('''      // The shelf's tiles: Send and Show in folder are Task 9.
      shelf: { ask: (id) => this.askShelf(id), send: () => {}, reveal: () => {}, dragOut: (ids) => this.dragOutShelf(ids) },''', '''      shelf: { ask: (id) => this.askShelf(id), send: (ids) => this.sendShelf(ids), reveal: (id) => this.revealShelf(id), dragOut: (ids) => this.dragOutShelf(ids) },'''),
])
print("applied")

# The one new edge in the lock file: the app now names windows-collections itself (it was already in the lock, as a dependency of the `windows` crate).
edit("windows/Cargo.lock", [
(''' "tauri-plugin-single-instance",
 "tokio",
 "windows 0.61.3",
 "zip",
]''', ''' "tauri-plugin-single-instance",
 "tokio",
 "windows 0.61.3",
 "windows-collections 0.2.0",
 "zip",
]'''),
])
PYEOF
```

Expected: `applied`, `applied`

- [ ] **Step 4: Run the checks**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/shelf-send.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
git diff --stat -- windows/Cargo.lock | tail -1
```

Expected: `# pass 6`, `# fail 0`, `tsc exit 0`, `ℹ tests 426`, `ℹ pass 426`, `ℹ fail 0`, and `1 file changed, 1 insertion(+)` for the lock file (the one edge).

- [ ] **Step 5: Prove the send and the show bite**

Run:

```bash
cd windows
m() { python3 ../.claude/checkpoints/g1-tauri/mut.py "$@"; }; T=scripts/cat-tests/shelf-send.test.mjs
m src-tauri/src/platform/windows.rs '        let _ = target.set_focus();
' '' $T
m src-tauri/src/lib.rs '        log::line("shelf send started");' '        log::line(&format!("shelf send {paths:?}"));' $T
m src-tauri/src/platform/windows.rs 'raw_arg(format!("/select,\"{}\"", path.display()))' 'arg(format!("/select,{}", path.display()))' $T
m src-tauri/src/platform/linux.rs 'pub const SHARE: bool = false;' 'pub const SHARE: bool = true;' $T
m src/island/island.ts '    this.holdOpen();
    Bridge.shelfSend(ids)' '    Bridge.shelfSend(ids)' $T
m src-tauri/Cargo.toml 'windows-collections = "0.2"' '' $T
cd ..
```

Expected: each line ends `# pass 5 # fail 1`, except the log line's, which ends `# pass 4 # fail 2` (it breaks two pins).

- [ ] **Step 6: The Rust (needs the image)**

The pure part (`show_items_args`) is tested; the Linux `reveal_file` is compiled; the Windows share is not compilable here.

Run:

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && {
  bash windows/scripts/cargo-linux.sh test -p notchmeow dragout:: --target-dir /repo/windows/target/g1-tauri 2>&1 | grep -E "^test result|^error|^warning"
  bash windows/scripts/cargo-linux.sh check -p notchmeow --target-dir /repo/windows/target/g1-tauri 2>&1 | grep -E "^error|^warning|Finished" | head -10
} || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok. 5 passed` for `dragout::`, then `Finished` and no `error` and no `warning` (or the line saying the Rust is owed). The Windows `cargo check` is owed to CI: the first thing to read in its log is `platform/windows/share.rs` and `platform/windows/drag.rs`.

- [ ] **Step 7: Commit**


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/src-tauri/src/platform windows/src-tauri/src/lib.rs windows/src-tauri/src/dragout.rs windows/src-tauri/Cargo.toml windows/Cargo.lock windows/scripts/cat-tests/shelf-send.test.mjs windows/src/core/bridge.ts windows/src/views/shelf.ts windows/src/shelf/devshelf.ts windows/src/island/island.ts
git commit -F - <<'MSG'
feat(shelf): Send through the Windows Share window, and Show in folder

Windows opens the system's Share window over the island with the shelf's files, from a click, and the log says only that a send started. Show in folder selects the file in Explorer, or asks the Linux file manager through FileManager1.ShowItems and opens the folder where none answers. Linux has no system share, so no Send. The app names windows-collections, already in the lock file, for the Share window's list of files.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, the Rust lines (or that the image was missing), the agent, the model and the trigger.

---

# Stage 8: the docs and the checks

### Task 10: The docs, the CI path filter and the final checks

**Agent:** `nm-implementer-light` (Haiku 5.5, medium; Step 4 runs the whole suites).

**Files:**
- Modify: `windows/README.md`, `CLAUDE.md`, `ARCHITECT.md`, `docs/SHELF-CONTRACT.md`, `.github/workflows/windows-tests.yml`

**Interfaces:**
- Consumes: everything above. `CLAUDE.md` and `ARCHITECT.md` get one new line each (the Windows/Linux part of sub-project G1), added as new lines so that a merge with the Mac twin's edits has no conflict. The root `README.md`'s roadmap row and `docs/INTEGRATIONS.md` are not touched: the main session sets the roadmap row's final status when both G1 plans have landed.
- Produces: the CI hook G1-0 left to this plan: `windows-tests.yml` now runs on `tests/fixtures/shelf/**`.

- [ ] **Step 1: Edit the docs and the workflow**


```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit(".github/workflows/windows-tests.yml", [
("""      - 'tests/fixtures/cat/**'
""", """      - 'tests/fixtures/cat/**'
      - 'tests/fixtures/shelf/**'
"""),
])

edit("windows/README.md", [
('''| `Esc` | Closes the island |
| Tray icon | Open, Cat on the desktop (Bring the cat home while it is out), Settings…, Pause, Quit |''', '''| Drag files onto the right half of the island | While files are over it the island opens into two halves: **Ask** on the left, the catch you know, and **Shelf** on the right, a tray. Release over Shelf and the files are kept there, up to 30, as links to the originals. The cat does not catch them and the desktop cat does not fly in |
| `Esc` | Closes the island |
| Tray icon | Open, Shelf, Cat on the desktop (Bring the cat home while it is out), Settings…, Pause, Quit |'''),
('''## Claude Code
''', '''## The shelf

Files can wait in the notch. Drag them over the island: it opens into two halves, **Ask** (left: the cat catches one file, as ever) and **Shelf** (right: a tray). Release over Shelf and every file is kept there, up to 30, newest first. The shelf holds links to the originals and copies nothing, and it is remembered across restarts (`shelf.json` in `%LOCALAPPDATA%\\NotchMeow\\` or `~/.local/share/notchmeow/`; a damaged one is kept as `shelf.json.bad-<time>` before a new one is written). It opens from a Shelf drop, from the tray's **Shelf** item, or from the small count at the right end of the compact island, which shows only while the island is already compact and never wakes a hidden one.

Each tile has **Ask about it** (the file goes to the chat like a drop on Ask, as a new chat), **Send** (Windows: the system's Share window; Linux has none), **Show in folder** (with the file selected) and **Remove** (an original is never touched). A click ticks a tile, and several ticked tiles are sent together; Ask is off while several are ticked, for a folder and for a missing file. Press a tile and move it to drag the file out of the island into a folder, a mail window or a chat. A file that moved or was deleted shows as Missing, found when the shelf opens and never in the background. A full shelf refuses extra files with a short note instead of dropping old ones, and a drop on Shelf never waits for the desktop cat. There is no shortcut for the shelf here (the Mac has one).

## Claude Code
'''),
('''### Testing the cats
''', '''### Testing the shelf

The shelf (sub-project G1) follows `tests/fixtures/shelf/` (`docs/SHELF-CONTRACT.md`): `src/shelf/rules.ts` (`zoneAt`, `shelfClean`, `shelfAdd`, `readShelf`) and its Rust twin `src-tauri/src/shelf.rs`, which is also the store, replay both fixtures. `npm run check:cat` runs the TypeScript (`shelf-*.test.mjs`) and `windows/scripts/cargo-linux.sh test -p notchmeow shelf::` the Rust. `?dev` has a **Shelf** panel: the shelf view in its island, fed by a shelf in memory that follows the contract, with buttons for a few files, a full shelf, a folder, a missing original, ticks and the system's abilities, and a probe for which half a pointer is in. In the dev server only, a green **drag test file** tab in the compact island drags a test file out through the native drag source (in a Debug build of the app), to try it on a real machine.

### Testing the cats
'''),
('''- The desktop cat has no global shortcut here (the Mac has one)''', '''- The shelf holds paths only: promised files (Mail, Photos) and browser images do not exist here, so nothing is copied; its tiles show a file icon, not a thumbnail; it opens from a tray item, not a menu-bar one; and it has no global shortcut. Send is the Windows Share window, and Linux has Show in folder only. Dragging a tile out is the system's own drag: OLE on Windows, GTK (`text/uri-list`) on Linux.
- The desktop cat has no global shortcut here (the Mac has one)'''),
('''- **The cat's eyes** follow the pointer only while it is over the island: Wayland
  gives no app the cursor position anywhere else.''', '''- **The cat's eyes** follow the pointer only while it is over the island: Wayland
  gives no app the cursor position anywhere else.
- **The shelf** has no Send (there is no system share). **Show in folder** asks the file
  manager to select the file (the freedesktop `FileManager1.ShowItems` call, through `gdbus`) and
  opens the folder where none answers. A drag out of a tile is a GTK drag of a `text/uri-list`;
  a compositor that refuses it leaves the shelf without drag out (`dragout::LINUX`). Where the
  drop's position is all there is of the pointer, the half is decided from it.'''),
])

edit("CLAUDE.md", [
('''- `docs/index.html`, `docs/testers.html`, `docs/site.css` — the site''', '''- Sub-project G1 on Windows/Linux (the shelf): `windows/src/shelf/rules.ts` ports the shelf contract (`zoneAt`, `shelfClean`, `shelfAdd`, `readShelf`, replayed from `tests/fixtures/shelf/`), and `src-tauri/src/shelf.rs` is its Rust twin and the store (`shelf.json` and copies under `shelf/<id>/`, a backup before an unreadable or trimmed file is overwritten, at most 30; the page holds ids and never a path). The Ask and Shelf halves are a layer over the drop canvas (`shelf/zones.ts`, `shelf/dropflow.ts`: the half is the pointer's at the drop, from the cursor poll on Windows and the drag event's position on Linux), the view is `views/shelf.ts`, the badge `shelf/badge.ts` (only while compact, never wakes a hidden island). Drag out is `src-tauri/src/dragout.rs` with `platform/windows/drag.rs` (OLE) and `platform/linux/drag.rs` (GTK `text/uri-list`) behind the one-line switches `dragout::WINDOWS` and `dragout::LINUX`; Send is the Windows Share window (`platform/windows/share.rs`); Show in folder is `platform::reveal_file`. `?dev` has a Shelf panel.
- `docs/index.html`, `docs/testers.html`, `docs/site.css` — the site'''),
])

edit("ARCHITECT.md", [
('''   - **Sub-project I (the wardrobe):**''', '''   - **Sub-project G1 on Windows/Linux (the shelf):** `src/shelf/rules.ts` and `src-tauri/src/shelf.rs` replay `tests/fixtures/shelf/`; Rust owns `shelf.json` and the files (the page holds ids, never paths: every command that touches a file takes an id), the page holds the list (`shelf/store.ts`, `State.shelf`). A drop's half is `zoneAt` on the pointer (`shelf/dropflow.ts`); the halves are a layer over the unchanged drop canvas (`shelf/zones.ts`), a Shelf drop skips the desktop cat's wait (`Island.shelfDrop`), and an item dragged out and back is ignored (`shelf/dragguard.ts`). Drag out, Send and Show in folder are native (`dragout.rs`, `platform/*/drag.rs`, `platform/windows/share.rs`, `platform::reveal_file`), and `BootInfo.shelf` says what a system can do. The badge (`shelf/badge.ts`) is a function of the island's mode.
   - **Sub-project I (the wardrobe):**'''),
])

edit("docs/SHELF-CONTRACT.md", [
('''Both app plans add their own replay of the two files (`shelf-cases.json`, `zone-cases.json`) to their tests.''', '''Both app plans add their own replay of the two files (`shelf-cases.json`, `zone-cases.json`) to their tests. Windows/Linux: `windows/scripts/cat-tests/shelf-rules.test.mjs` (`npm run check:cat`) replays both through `windows/src/shelf/rules.ts`, and `cargo test -p notchmeow shelf::` replays `shelf-cases.json` through `windows/src-tauri/src/shelf.rs` (the Rust twin leaves `zoneAt` to the page, which decides the half).'''),
])
print("applied")
PYEOF
```

Expected: `applied`

- [ ] **Step 2: Check that the docs say what the code does**

Run:

```bash
grep -c "shelf.rs" CLAUDE.md windows/README.md ARCHITECT.md docs/SHELF-CONTRACT.md
grep -n "tests/fixtures/shelf" .github/workflows/windows-tests.yml
grep -c "The shelf" windows/README.md
```

Expected: `CLAUDE.md:1`, `windows/README.md:1`, `ARCHITECT.md:1`, `docs/SHELF-CONTRACT.md:1`, the workflow line `tests/fixtures/shelf/**`, and `5` for the README's headings and bullets.

- [ ] **Step 3: If a fallback was ordered at Checkpoint 0** (skip this step otherwise)

Edit the README to say what ships: for Windows or Linux **without** drag out, replace the sentence "Press a tile and move it to drag the file out of the island into a folder, a mail window or a chat." with "Dragging a tile out of the island does not work on this system yet: use **Show in folder**.", and in "What's different from the Mac version" and the Linux list drop "Dragging a tile out is the system's own drag: OLE on Windows, GTK (`text/uri-list`) on Linux." (or its Linux half). Run `grep -n "drag" windows/README.md | grep -i tile` to find them.

- [ ] **Step 4: Run every check**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1
(cd .. && bash scripts/test-shelf-contract.sh 2>&1 | tail -1)
(cd .. && bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two generator")
npx --no-install vite build --outDir ../.claude/checkpoints/g1-tauri/dist --emptyOutDir 2>&1 | tail -1
for s in nm-drag-spike shelf-dev mountShelfDev "drag test file" "Pointer x on a 640"; do printf "%s: " "$s"; grep -rl "$s" ../.claude/checkpoints/g1-tauri/dist | wc -l; done
trash ../.claude/checkpoints/g1-tauri/dist
cd ..
git status --short
```

Expected: `tsc exit 0`, `ℹ tests 426`, `ℹ pass 426`, `ℹ fail 0`, `All AI UI checks passed`, `All Claude Code UI checks passed`, `✓ zone-cases.json matches build_cases.py`, `# tests 319`, `# pass 319`, `# fail 0`, `✓ 16 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`, `✓ built in`, five lines ending `0` (a release bundle holds none of the dev server's tab or panel), and then the five doc and workflow files as modified (` M`) and nothing else.

Then the Rust suite (needs the image):


```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/g1-tauri 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok.` for the library and the relay, no `error`, no `warning` (or the line saying the Rust is owed). The Windows `cargo check` and a release build are owed to CI.

- [ ] **Step 5: Check that nothing forbidden changed**

Run:

```bash
git diff --numstat notchmeow/rebrand...HEAD -- windows/src/style.css | awk '{print "style.css added " $1 ", deleted " $2}'
git diff --stat notchmeow/rebrand...HEAD -- windows/src/upload windows/src/views/upload.ts windows/src/views/icons.ts design tests scripts docs/CAT-CONTRACT.md | tail -1
git diff --name-only notchmeow/rebrand...HEAD | grep -E "^(NotchBuddy|design|tests|scripts)/" | wc -l
```

Expected: `deleted 0` for the style sheet (it only gained lines), nothing printed by the second (the drop canvas, the sequence, the upload views, the icons, the core, the fixtures and the contract document are untouched), and `0` for the third.

- [ ] **Step 6: Commit**


```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g1/tauri-shelf
git add windows/README.md CLAUDE.md ARCHITECT.md docs/SHELF-CONTRACT.md .github/workflows/windows-tests.yml
git commit -F - <<'MSG'
docs(shelf): the shelf on Windows and Linux, and the CI path filter

The README, the Windows line of CLAUDE.md and ARCHITECT.md describe the shelf: its halves, view, badge, tray item, drag out, Send and Show in folder, and what differs by system. windows-tests.yml now runs on changes to tests/fixtures/shelf/.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts printed above, the agent and the model.

---

## Checkpoint 2: the owner signs off

Tasks 1 to 10 are done. The session **stops here** and reports (the report the controller brief lists), with the pictures: `badge-compact.png` (the count in the compact island's right ear), `shelf-from-badge.png` (the shelf opened by the badge) and `shelf-ask.png` (Ask from a tile: the catch starts at once), and the spike's result. The same report goes to the main session with `SendMessage`. After the owner's OK, the main session dispatches **`nm-reviewer-deep`** (Sonnet 5.5, high; trigger 4) over `git diff notchmeow/rebrand...HEAD`, with the cross-task contracts, the Review Focus above, and the security and privacy rules: **the page holds ids and never a path** (every command but `shelf_add` takes ids; `Entry` carries no link), **a copy's folder cannot leave `shelf/`** (the id is the contract's `[A-Za-z0-9_-]{1,64}`), **a damaged `shelf.json` is kept before it is overwritten and never loses the other items**, **a drag and a share only copy**, **the log names nothing** (`shelf send started`), no network, no timer or poll beyond the one-shot 15 s hold, the badge never wakes a hidden island, and the new dependency.

### The owner's real-build checks (what this plan could not see)

Run on a real machine with `cd windows && npm run tauri dev` (or an installed build). The headless browser proved the page, the rules and the layout; it proved nothing about a window, a drag that leaves it, the Share window or a file manager.

**On Windows (10 or 11):**
1. **The spike** (Checkpoint 0's five steps): the green tab drags `NotchMeow drag test.txt` to Explorer, the desktop and a mail window as a copy; Esc cancels; dropped back on the island nothing opens.
2. **The halves:** drag a file from Explorer over the island: it opens into Ask and Shelf, the half under the pointer lights, and the cat follows the pointer onto the tray. Release just left of the centre line: the ordinary Ask catch. Release just right of it: the file goes on the shelf, the island shows it, no catch, no chime.
3. **Several files:** drop five on Shelf: all five, newest first. Drop five on Ask: only the first is caught.
4. **A full shelf:** fill it to 30 and drop three more: the amber note says three were left off, nothing old is removed. Drop one already shelved: nothing is added.
5. **The desktop cat out:** take the cat out onto the desktop. Drag a file on Ask: the cat flies in, catches it and flies back. Drag a file on Shelf: no wait, no catch, the cat goes back by its normal rule. Drop on Shelf while an Ask catch is still running: the shelf wins and no stale note appears.
6. **The tiles:** hover shows Ask, Send, Show in folder and Remove. A click ticks; with two ticked, Ask greys out. **Ask about it** starts a new chat with the file (the cat flies it to its mouth). **Show in folder** opens Explorer with the file selected. **Remove** takes it off and never touches the original (check in Explorer). A file deleted behind the shelf's back shows **Missing** after the shelf is reopened and keeps only Remove.
7. **Send:** the system's Share window opens over the island (if it does not, or the island flickers, write down what happened: the fallback is `platform::SHARE`); pick Nearby sharing or Mail: the files arrive. The island stays open about 15 seconds. Send two ticked files together.
8. **Drag a tile out** into Explorer (a copy arrives, the original stays), into a mail compose window (an attachment) and a chat box; press Esc in the middle; drop it back on the island (not added twice, the drop view does not open). Drag a tile whose file is missing: nothing starts.
9. **Restart:** quit from the tray and relaunch: the shelf is as it was; the badge shows the count.
10. **The tray:** the **Shelf** item opens the island on the shelf, also from a hidden island.
11. **The badge:** visible only in the compact island (move the pointer away and let it fold); gone when the island is hidden or open; a press on it opens the shelf, not the Home view; the island stays hidden while you add files from the tray's shelf. Add a file with the island hidden: it stays hidden.
12. **A second monitor and 150 % scale:** the centre line is still the centre line.
13. **CPU in Task Manager:** about 0 % with the island hidden and a full shelf.
14. **A damaged `shelf.json`** (cut it in half with Notepad): the shelf opens empty and `shelf.json.bad-<time>` appears beside it.

**On Linux (KDE Plasma or another layer-shell compositor, then GNOME, then X11 if available):**
1. **The spike:** the same five steps. On Wayland a refusal is the finding: write down the compositor and what the tab said. If it fails, the controller sets `dragout::LINUX` to `false` (Task 10 has the README edit) and Linux ships without drag out.
2. **The halves** (no global cursor: the half comes from the drag event's position): drag over, release left and right of the centre line, on a 100 % and a 200 % screen. If the half is wrong on a scaled screen, write it down: `pointerX` divides the position by the page's scale.
3. The same shelf checks as Windows 3 to 6, 9, 10 (the tray item needs the AppIndicator support of the desktop) and 11 to 14.
4. **Show in folder** selects the file in Dolphin, Nautilus or Thunar; on a system whose file manager does not answer it opens the folder. There is **no Send button**.
5. **Drag a tile out** into the file manager, a mail window and a browser upload box (a file chooser that accepts a drag).

---

## Parity with macOS

**macOS is the primary platform**: the Mac gets at least what Windows and Linux get. The Mac twin (G1-mac) is a separate plan, written against the same spec and the same contract (`shelfClean`, `shelfAdd`, `zoneAt`, replayed from `tests/fixtures/shelf/`). The main session reads the two together and decides where they differ.

**Both apps do the same, on purpose:** the two halves split at the centre line, the half decided by the pointer's position at release; Ask is today's drop and a Shelf drop takes all the files, takes a fresh token, clears the file alert and skips the desktop cat's wait; at most 30 items, an overflow refused with a note and nothing old removed, the contract's read-side cap of the 30 newest; the shelf is never the inbox; Ask from a tile is a drop on Ask (a new chat); the badge only while the island is compact and never waking a hidden one; the shelf opens from a Shelf drop, a tray or menu-bar item and the badge; a drag out that is not added twice when dropped back; Send always starts with a click and the log never names a file or a recipient.

**Different here, on purpose (Windows-only or Linux-only extras and gaps):** paths only (no promised files or browser images, so no copies are made: the copy code resolves and removes only); no global shortcut (the Mac's `shelf` shortcut is the Mac's); the tray item instead of a menu-bar item; the Windows Share window instead of the share picker plus an AirDrop button, and no Send on Linux; Show in folder as `explorer /select` and the file manager's `ShowItems`; the half from the polled cursor (Windows) or the drag event's position (Linux) instead of the drag's own location; no thumbnails; no wing that steps aside, so the badge does not fade with it; a Debug tab and a `?dev` panel instead of the Mac's Debug shelf panel.

**What the Mac has that Windows does not need:** security-scoped bookmarks and the App Store sandbox rules; the hold-open rule for the share picker (here a 15 s hold).

---

## Open questions for the owner

Each has the answer this plan assumed, with the alternatives (the recommended one first). The pictures at Checkpoint 1 answer 7 and 8; the others are answered in chat.

1. **A new direct dependency, `windows-collections = "0.2"`, for the Windows Share window.** It is Microsoft's, already in `Cargo.lock` as a dependency of the `windows` crate we use, and nothing new is downloaded; the app must name it because the `windows` crate does not re-export `IIterable`. (a) **Allow it** (assumed). (b) Ship Windows without Send (Ask, Show in folder and drag out only): Task 9 then drops `share.rs`, the dependency and `shelf_send`, and `SHARE` is `false` on both.
2. **The spike's tab and its Debug command stay** after the real-machine check, as dev tools beside the `?dev` Shelf panel (assumed; the tab exists only in the dev server and the command refuses in a release build). The alternative is to delete both once the check is answered.
3. **No thumbnails:** a tile shows a file or a folder icon (assumed; the spec says "a thumbnail or file icon"). The alternative adds a Rust command that returns a small image for an id.
4. **Show in folder acts on the tile's own file**, not on all the ticked ones (assumed: it would open one window per file). The alternative selects them all in one folder window where they share one.
5. **The badge does not fade with a wing** (assumed: the wing that steps aside is the Mac's; Windows has none).
6. **The island stays open 15 s after Send** (assumed; nothing tells us when the system's Share window closes, and the Mac holds it open while the picker shows). Alternatives: until the pointer next enters the island, or no hold.
7. **The right half dims the end of the Ask side's chips row**, and the cat shows through the tray (assumed; looked at in Checkpoint 1). Alternatives: move the tray's left edge right of the chips, or make the tray solid.
8. **The half on Windows is the polled cursor and on Linux the drag event's own position** (assumed). The spec says the event carries paths only; Tauri 2.12's payload carries the pointer too, which is the only pointer Wayland gives. The alternative is the polled cursor on Windows only and Ask on Linux.
9. **A file whose name the contract refuses** (a trailing dot or space, a zero-width character, a Windows device name) cannot be shelved: it is `invalid` and the note says "can't go on the shelf" (assumed: the contract keeps every platform's shelf the same).
10. **Folders** are shelved as links (the spec), Ask is off for them, Send shares them as folders, Show in folder selects them (assumed).

---

## Self-review notes

- **Spec coverage.** G1, in order: dropping (the halves, the half decided at release, what Shelf accepts: paths and folders, the Shelf drop's token, alert and no wait, a full shelf: Tasks 2, 3, 5); the shelf view and its actions (Ask, Send, Show in folder, Remove, Clear all, multi-select, the cap, the badge, how it opens: Tasks 6, 7, 9); dragging out with a spike first and the stated fallback (Tasks 1 and 8); storage (paths, copies, `shelf.json`, missing originals, removal, existence checked only on open: Task 3); Send (Windows Share, Linux Show in folder, the click rule, the log rule: Task 9); the tray item, the `?dev` panel, the CI path filter, the README differences (Tasks 7, 6, 10); the Mac-only items (the shortcut, bookmarks) are out of scope here by the spec.
- **Placeholders.** None. The island's four tile actions are stubs in Task 6 and each later task replaces its stub with the exact text it finds; every code step is a full file or a script whose replacements assert their anchors; every `Run:` has an `Expected:`.
- **Type consistency.** The names are one spelling throughout: `ShelfItem` (rules) and `ShelfEntry` (what the page holds: no link, `missing`), `AddWord`, `Zone`, `ShelfBackend`, `ShelfStore`, `ShelfActions`, `ShelfCaps`, `DragOutGuard`, `DragDone`, `PointerInput`, `DropPlan`, and the commands `shelf_list`, `shelf_add`, `shelf_remove`, `shelf_clear`, `shelf_ask`, `shelf_drag_out`, `shelf_reveal`, `shelf_send`, `drag_out_spike`. One signature changes on purpose: `ShelfActions.reveal(ids)` (Task 6) becomes `reveal(id)` (Task 9, Open question 4).
- **Review Focus** lines 1 to 5 each have named tests above.
- **What this plan deliberately does not do:** G2 (between machines), thumbnails, a Send on Linux, a global shortcut, the shelf's own sounds, promised files and browser images, the Mac, any real window, the Windows `cargo check` and a release build (owed to CI), and a drag run on any machine.

---

## Dry run (2026-10-14)

The plan was run before it was handed over, in a throwaway clone of this repository (`git clone --local --shared` on `notchmeow/rebrand` at `619b407`, in the session scratchpad, with `windows/node_modules` copied with `cp -cR`), never in the repository's own working tree. Nothing was committed or pushed, no NotchMeow app and no Tauri app was started, nothing was installed or downloaded, no Docker image was built or pulled, and no network was used except `127.0.0.1`.

**Method.** The code of every task was first written and checked in one clone, then this file was generated from those verified files (each file and each edit script is read from disk, never retyped), and the whole file was replayed in a fresh clone by a small runner: it takes every `bash` block in order, runs `bash -n` on it, runs it from the clone's root and compares its output with the backticked literals of the `Expected:` line that follows it.

| Task | Agent | What the replay printed (the plan's Expected) |
|---|---|---|
| 1 | deep | red: `# fail 6`; green: 6 pass, `tsc exit 0`, `check:cat` 378; three proofs fail 1 each |
| 2 | light | red: `ERR_MODULE_NOT_FOUND`; green: 9 pass, `check:cat` 387; seven proofs fail 1 or 2 |
| 3 | nm-implementer | Rust not run in Docker; the same file in a scratch crate: 10 `shelf::` tests pass, proofs 1, 2 and 3 failures |
| 4 | light | 7 pass, `check:cat` 394; four proofs fail 1 or 2 |
| 5 | nm-implementer | 10 pass, `check:cat` 404, the drop canvas untouched (empty `git diff`); seven proofs fail 1; in the browser the half is `ask`, `shelf`, then a Shelf drop leaves the island on the shelf with both files shelved |
| 6 | nm-implementer | 6 pass, `check:cat` 410; four proofs fail 1; the panel: `13 tiles, 2 ticked, 1 missing`, the full-shelf note, the empty state, the zone probe at 320, 321 and 641 |
| 7 | nm-implementer | 11 pass, `check:cat` 415; five proofs fail 1; the badge is `3` and visible while compact, off while hidden (a file added while hidden leaves the island hidden), a press opens the shelf, Ask starts the catch |
| 8 | nm-implementer | 5 pass, `check:cat` 420; four proofs fail 1 |
| 9 | deep | 6 pass, `check:cat` 426, the lock file gains one line; six proofs fail 1 (the log line's fails 2) |
| 10 | light | docs applied; `check:cat` 426; the release bundle holds none of the dev tab or panel strings; the contract scripts as in Setup |

The replay found, and the text now fixes: the new folders (`windows/src/shelf/`, the two `platform/` subfolders) did not exist, so each file block makes its folder first; the Windows `platform` edits of Task 9 were missing from the script (the test caught it: three failures); the three red steps print only `ERR_MODULE_NOT_FOUND`; and the CSS appends no longer sit between a script and its `Expected` line.

**Not run, and owed.**

- **All Rust through `cargo-linux.sh`.** The Docker daemon was not running (`docker info` could not connect), and the plan's rule is never to build or pull the image, so no `cargo test` or `cargo check` of the real crate ran: `lib.rs`, `tray.rs`, the platform files and the Linux GTK drag source (`platform/linux/drag.rs`) are uncompiled. Expect at most a compile error or a missing import on the first run; the executing session reports the first ten lines and the main session decides (`nm-implementer-deep`).
- **What ran instead, outside the plan's own commands.** `shelf.rs` and the pure half of `dragout.rs` (`file_uri`, `show_items_args`) were compiled and tested natively in a scratch crate with the cached `serde_json` (offline): **15 tests pass** (the 10 of `shelf::`, which replay 132 clean, 30 add and 18 parse fixture rows, and 5 of `dragout::`), and the proofs of Task 3 Step 4 were measured there (9 passed 1 failed, 8 passed 2 failed, 7 passed 3 failed). The format-character table was compared with Python's `unicodedata` (Unicode 16.0): identical, range for range. `cargo metadata --offline` produced the lock file's one new edge.
- **Everything Windows.** `platform/windows/drag.rs` and `platform/windows/share.rs` were written against the `windows` 0.61.3 sources in the local registry (the names, the features and the signatures were looked up there), but nothing can compile them here: the container is Linux, and a `cargo check` of the `windows` crate on this Mac fails inside its own dependencies (`windows-future` needs Windows). They are owed to `windows-tests.yml` on the owner's next pull request.
- **Every commit step:** every `git add` and `git commit` block was skipped in the clone and has to be run by the executing session in its worktree.
- **The Tauri app itself.** No window of the real app was opened, so a drag that leaves the island, the Share window, the file manager, click-through on both systems and a second monitor are the owner's real-build checks (listed at Checkpoint 2), not something this run proved. The pages were driven in a headless browser from the Vite dev server with no Tauri, which proves the drawing, the layout and the logic (the island's own drop handler was called with the events Tauri would send), and nothing about the shell around them.

The clone, its snapshots and the shots were moved to the Trash (`trash`, never `rm -rf`).


## The owner's answers (2026-10-14)

The owner approved this plan with these answers:
- The badge is **not clickable while the wing shows agent cats**: the wing stays as shipped; the shelf still opens from the menu-bar or tray item, the shortcut (Mac) or a drop.
- The Shelf half's overlap with the end of the chips row is accepted (nothing that ships moves); tiles use the **system file-type icons** (no file contents read).
- The `shelf` shortcut is **⌃⌥S, off by default** (Mac); the island **stays open 15 s after Send**; a browser-image or promised-file drag over Ask is **refused** (Shelf takes it).
- Windows: the `windows-collections 0.2` crate is **allowed** for Send; the drop's half comes from the **polled cursor on Windows** and the **event position on Linux**.
