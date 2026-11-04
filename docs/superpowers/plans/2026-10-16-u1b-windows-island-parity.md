# U1b: The island gets out of your way on Windows and Linux: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The three island follow-ups the owner agreed to after U1 (where the Mac got them in U1), on Windows and Linux: (1) a click outside the open island folds it, (2) both wings of the compact island step aside (the island swooshes into its notch-wide middle while the pointer is over a wing, and the mouse passes through to what is underneath), (3) the Claude App pill's "Open" action starts the Claude desktop app.

**Architecture:** The Mac's pure rules are ported case for case to TypeScript (`island/outsideclick.ts`, `island/wing.ts`) and tested by the same cases, with drift pins that read the Swift constants. The island page owns the facts; the OS gives it the pointer it already gives it (the Windows cursor poll in `island.rs`, plus one thing it did not read before: the mouse buttons, on every poll tick and only while the island is expanded). There is **no global mouse hook, no window-blur trick and no new poll**: the 16 ms cursor poll that already runs while the island is showing reads the buttons, and the one new timer is a one-shot that the wing's driver arms only while a 0.4 s dwell or the 1 s return is running (the Mac gets that tick from its 60 Hz poll; here the cursor event comes only when the pointer moves). Where the OS gives an app no global pointer (every Wayland session), both features are off and nothing else changes; Linux under X11 gets the pointer through Xlib in one task that can be dropped on its own. Click-through, the mechanism the wings need, is the existing one: the `WS_EX_TRANSPARENT` toggle driven by the cursor poll on Windows, the input region on Linux, both fed by the island's rectangle the page already pushes.

**Tech Stack:** TypeScript (Node 22 `--experimental-strip-types` tests, no parameter properties or enums), CSS, Rust (Tauri 2; `windows` crate 0.61 already in the tree; Xlib through a direct `extern "C"` link like the existing gtk-layer-shell calls; run through `windows/scripts/cargo-linux.sh`), Vite dev server for the pictures.

**Spec:** the owner's agreement after U1 (2026-10-15), restated under "The items" below; there is no spec file. The Mac rules are `NotchBuddy/Sources/App/IslandOutsideClick.swift` and `IslandWing.swift`, their tests `tests/IslandOutsideClickTests.swift` and `tests/IslandWingTests.swift`, `docs/SPEC.md` ("L'aile droite s'efface", "Le halo au survol, le clic en dehors, l'ouverture au survol"), and U1 (`docs/superpowers/plans/2026-10-15-u1-upstream-fixes-and-island-qol.md`, Tasks 9, 13 and 14, and its archived ledger `.claude/archive/sdd/u1-upstream-fixes-and-qol/progress.md`).

**Base:** a new branch `u1b/windows-island-parity` in a git worktree, from `notchmeow/rebrand` at `dc91b739` or later (`git merge-base --is-ancestor dc91b739 HEAD` must succeed). If a find text below no longer occurs exactly once because the base moved, stop and report; do not guess.

## The items (the owner's agreement, 2026-10-15)

1. **A click outside the open island folds it.** Mac (U1 Task 9): on the release of a click (a press that moves more than 4 pt before the release is a drag), never while the island is pinned, a permission request or question waits, the user is typing in the chat, the shelf holds it, the cat's head is dragged out or the Wardrobe menu is open. Windows/Linux: the same rules, the same 4 px, the same fold as Escape (`collapse()`).
2. **Both wings step aside.** Mac (U1 Task 14): over the right wing the island folds at once; over the left wing (the big cat) only after the pointer has rested there 0.4 s with no mouse button pressed; the whole island shrinks to the notch's width on a spring (0.22 s, damping 0.68), the cats, the grid and the shelf badge fade (0.15 s out, 0.25 s in), the mouse passes through the wings, 1 s after the pointer has left both wings it swooshes back out, an alert cancels it at once, and with Open on hover on the pointer on a wing opens nothing (a hover-only hold). Windows/Linux: the same, with the PC's own geometry (below).
3. **The Claude App pill's "Open" action.** Mac (U1 Task 13): the pill's tap and the finished card's "Open Claude" start the Claude desktop app by its bundle ID. Windows/Linux: the relay tag, the pill's name and colour already ship (U1); the Open action does not.

## What the three things mean on a PC (the design decisions)

**The PC's island has no notch, but it has the same shape.** The compact island is 288 px wide and 32 px high at the top centre of the screen, with a 184 px middle (`NOTCH_W`) and 52 px on each side (`COMPACT_W = NOTCH_W + 104`): the big cat on the left, the grid and the shelf badge on the right. It sits on whatever the user has at the top centre of the screen (a maximized window's title bar, a browser's tabs). "Step aside" therefore means exactly what it means on the Mac: the island shrinks to its 184 px middle, so the 52 px beside it show again and take the mouse. The 184 px middle stays on screen as a black pill, because on a PC there is no notch behind it to disappear into (open question 4).

**What "outside click" is detected with.** Rejected, with the reason:

| Signal | Why not |
|---|---|
| Window blur / focus loss | The island never has the focus: it is `WS_EX_NOACTIVATE` on Windows, `focusable: false` and `KEYBOARD_NONE` on Linux. It takes the keyboard only while the chat's text field is up, and then the rule says "typing keeps the island". So a blur can never fire at the moment the rule wants it. |
| A global mouse hook (`WH_MOUSE_LL`, `XGrabPointer`, XInput2 raw events) | Heavier than the Mac's one monitor, needs a message pump or a grab, antivirus products flag it, and the repo's rule is "no new poll or monitor". |
| A full-screen invisible catcher window | It swallows the click the user meant for the app underneath (the Mac lets it through), and it needs layer-shell, which GNOME lacks. |
| **The cursor poll that already runs** | **Chosen.** While the island is showing, `island.rs` already wakes every 16 ms and reads the cursor (Windows). It reads the three mouse buttons there too, only while the page says the island is expanded, and sends the edges (`pointer-button`). The island's rectangle is already in Rust, so the click-through decision stays in the same tick. |

**Windows.** The poll reads `GetAsyncKeyState` for the left, right and middle buttons on every tick while watching, **before** the existing "pointer has not moved" skip (a click does not move the pointer). A press is checked with `WindowFromPoint` + the process ID: a click on another window of this app (Settings, the desktop cat, the tray's menu) is not outside. A click shorter than one tick (16 ms) can be missed; a real click lasts 60 ms or more. Mouse buttons swapped in Windows' settings do not matter: all three are watched.

**Linux, three cases.**

| Session | Outside click | Wings |
|---|---|---|
| X11 (Task 5, droppable) | Yes: Xlib `XQueryPointer` from the poll thread's own connection, and GDK's `window_at_position` on the main thread at each press to tell the app's own windows | Yes, same source |
| Wayland with layer-shell (KDE, COSMIC, Hyprland, Sway, other wlroots) | **No.** A Wayland app is told nothing about a click that lands on another app's surface, and a layer surface gets no pointer event outside its input region | **No**: with the input region set to the folded middle the page would never see the pointer leave the wing, so it could not know when to come back |
| GNOME on Wayland (no layer-shell) | No, same reason | No |

On the "No" rows nothing breaks: `boot.cursorPoll` is false, the page keeps `followPageCursor`, the new code is told `feed(null, false)` and `watchPointerButtons` is never called, so the island behaves exactly as it does today (Escape, the click on the compact island, its own auto-close). This is documented in `windows/README.md` (Task 7) in those words.

**The Claude desktop app.** Windows: a classic install is found by its usual paths and the Start-menu shortcut; a packaged (MSIX) install is found by asking `Get-StartApps` for the entry named exactly "Claude" and started through the shell by its AppUserModelID (validated: letters, digits, `.`, `-`, `_`, one `!`). Nothing is ever put on a command line through `cmd`. Starting an already-running Electron app brings its window forward, which is what the Mac's `openApplication` does. **Which install the owner's machines have is not verified here** (open question 3): the resolver is tested with fake folders. Linux: Anthropic ships no desktop app, so the button is not shown and the pill's ↗ does nothing.

## Global Constraints

Every task's requirements include this section.

- **TypeScript is run by Node's strip-only mode in the tests:** no enums, no namespaces, no constructor parameter properties; import with the `.ts` extension in files the tests load. `npx --no-install tsc --noEmit` stays green.
- **0 % CPU when the island is hidden, and nothing new while it shows.** No `setInterval`, no new `requestAnimationFrame` loop, no new thread. The only new timer is the wing driver's one one-shot (armed while a 0.4 s dwell or the 1 s return runs, none at rest). The buttons are read only while the island is expanded, by the poll that already runs. Pinned by tests.
- **No global mouse hook** (`SetWindowsHookEx`, `WH_MOUSE_LL`, `XGrabPointer`, XInput2) anywhere in `windows/src-tauri/src` (a test greps for it).
- **Mac-primary rule.** Nothing in `NotchBuddy/` changes. The Mac rules stay the reference: if the TypeScript and the Swift disagree, the Swift decides, and the drift pins in `wing.test.mjs` and `outside-click.test.mjs` read the Swift constants.
- **Never restyle a shipping view.** The only visible change is the wings' fold and fade (new) and the finished card's button label for a Claude App session (it said "Open terminal"). A resting island has no new CSS applied (`wing-on` exists only while the fade is not at rest).
- **Where there is no global pointer (Wayland) nothing changes.** Every new behaviour is gated on `boot.cursorPoll`.
- **Frozen values.** Pill IDs (`agent_claude-desktop`, `integration_claude`), cat IDs, settings keys and event names already shipped are untouched. New names: the events `pointer-button`, the commands `watch_pointer_buttons` and `open_claude_app`, `BootInfo.claudeApp`, `CursorPayload.down`.
- **Rust** runs through `windows/scripts/cargo-linux.sh` (offline, `--target-dir /repo/windows/target/u1b`, never builds or pulls an image) when Docker is up; when it is down, mark the step "needs Docker". The Windows-only code is compiled by `windows-tests.yml` on `windows-latest`, not here: say so in the ledger and do not claim it compiled.
- **No new dependency.** Xlib is linked directly (`#[link(name = "X11")]`, always present because GTK 3 links it), as the island already calls libgtk-layer-shell.
- **Models and commits** (CLAUDE.md, "Working with AI agents"): Haiku 5.5 first, Sonnet 5.5 only on a named trigger (the table names each), never Opus or Fable. Each commit is local only, never pushed, lists only the files its task names, and ends with the `Co-Authored-By` line of the model that did the task: `Claude Haiku 5.5` for `nm-implementer-light` and `nm-implementer`, `Claude Sonnet 5.5` for `nm-implementer-deep`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app: the installed app is running and owns the hook socket. A `vite` dev server on `127.0.0.1` is not the app and may run; stop it only by the PID you saved. No task sends a hook event to a real socket.
  2. Install nothing. No network calls, no downloads, no `docker build` or `docker pull`.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; put scratch files under `${TMPDIR:-/tmp}` in a folder with a unique name.
  4. Never edit `design/prototype/cat-core.js`, a fixture of `tests/fixtures/`, a generated theme file, or anything under `NotchBuddy/`.
  5. Never push. Commit only in a task's commit step, after checking the worktree and the branch.
  6. Haiku 5.5 for every task except where the table names Sonnet 5.5 and its trigger; never Opus or Fable.
  7. Never rename a frozen ID; write no `Coucou` or `Mochi` name anywhere.
  8. Never read, print or write the real `~/.claude/settings.json` (or anything in the real `~/.claude`, `~/.gemini`, `~/.codex`), by hand or in a script.
  9. If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.

## Review Focus

The items say what changes. They are silent on these conditions, and each would bite a person first, most likely first. Each names the test that pins it.

1. **A click on one of the app's own other windows, or while something holds the island.** Clicking Settings, the desktop cat or the tray menu while the island is open must not fold it (on the Mac those clicks never reach the monitor); a waiting card, the shelf's drag-out or Send hold, a native menu, typing in the chat or a pin must keep it. Tests: Task 1 (`shouldFold` with every reason and every pair; the glue reads the context at the press), Task 2 (`press_is_own` is asked at the press only; the pin), Task 3 (the context's six lines are pinned).
2. **A click that does not move the pointer, and a very short one.** The existing poll skips every tick where the pointer has not moved by 1 px, so a plain click would never be seen. Expected: the buttons are read before that skip, on every tick, while the island is expanded; a button already held when the watch starts is not a click. Tests: Task 2 (`ButtonEdges`, and the pin that the read comes before the skip), Task 1 (a release with no press is not a click).
3. **A drag that ends on the island, and a window dragged.** A file taken out of Explorer and dropped on the island, a window moved by its title bar, a text selection: the press is outside, the release is not a click (more than 4 px). Expected: no fold; a file drag in progress is also "busy". Tests: Task 1 (`ClickTracker`: 2 px yes, 20 px no, 3.6 px yes), Task 3 (`busy` includes `State.fileDragOver` and the upload view).
4. **A pointer that stops on a wing, and an alert that arrives while it rests there.** The cursor event comes only when the pointer moves, so the left wing's 0.4 s dwell and the 1 s return would never happen if nothing woke them. Expected: one one-shot timer is armed while a dwell or a return runs (and none otherwise); a permission card, a file drag, the desktop cat leaving, the shelf's hold or a pin arriving with the pointer parked on a wing puts the island back at once; a button pressed during the dwell cancels it. Tests: Task 1 (`WingDriver` with a fake clock: dwell without a cursor event, return without one, nothing pending at rest, the alert, the press), Task 4 (the alert list is pinned).
5. **The first tick of the fold, and the strip beside the middle.** Click-through must flip on the very tick the island folds (not after the spring), the 14 px hit margin Rust adds must not leave a dead band next to the 184 px middle, and the unfold must take the mouse back at once. Expected: while folded, Rust is told a rectangle the margin-width narrower on each side; otherwise the island's own frame; Rust recomputes click-through when the shape changes even if the pointer did not move. Tests: Task 1 (`foldedHitRect`), Task 2 (`rect_dirty` pin), Task 4 (the rectangle line is pinned).

Also covered, in their tasks: a Wayland session changes nothing (Task 4's gating line, Task 3's `cursorPoll` condition), and the Claude app's name from the system's Start list is validated before it is put on a command line (Task 6, `valid_aumid`).

---

## File Structure

| Path | Responsibility |
|---|---|
| `windows/src/island/outsideclick.ts` (new), `windows/src/island/wing.ts` (new), `windows/src/island/wingdriver.ts` (new), `windows/scripts/cat-tests/outside-click.test.mjs`, `wing.test.mjs`, `wingdriver.test.mjs` (new) | The pure rules, the Mac's cases, the drift pins (Task 1). |
| `windows/src-tauri/src/pointer.rs` (new), `island.rs`, `lib.rs`, `platform/windows.rs`, `platform/linux.rs`, `windows/scripts/cat-tests/u1b-pointer-wiring.test.mjs` (new) | The buttons, the `pointer-button` event, the shape-changed recompute (Task 2). |
| `windows/src/core/bridge.ts`, `windows/src/main.ts`, `windows/src/island/island.ts`, `windows/scripts/cat-tests/u1b-outside-wiring.test.mjs` (new) | The outside click in the page (Task 3). |
| `windows/src/island/fsm.ts`, `island.ts`, `desktop.ts`, `windows/src/main.ts`, `windows/src/style.css`, `windows/scripts/cat-tests/fsm-wing.test.mjs`, `u1b-wing-wiring.test.mjs` (new) | The wings in the page (Task 4). |
| `windows/src-tauri/src/platform/linux.rs`, `lib.rs`, `island.rs` | Linux under X11: the pointer feed (Task 5). |
| `windows/src-tauri/src/claude_app.rs` (new), `lib.rs`, `platform/windows.rs`, `platform/linux.rs`, `windows/src/core/openagent.ts` (new), `bridge.ts`, `state.ts`, `main.ts`, `island/island.ts`, `views/views.ts`, `windows/scripts/cat-tests/u1b-claude-app.test.mjs` (new) | Open Claude (Task 6). |
| `windows/README.md`, `docs/SPEC.md`, `docs/AGENTS.md`, `CLAUDE.md` | The honest limits, the French spec sentences, the map bullet (Task 7). |

## Tasks and agents

CLAUDE.md: the lightest model that fits. **Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Effort: **medium** for light tasks (code given in full), **high** for `nm-implementer`, the deep agent and every review.

| # | Task | Agent, model, effort | Trigger | Review |
|---|---|---|---|---|
| 0 | Worktree and baseline | the session | | none |
| 1 | The pure rules in TypeScript, the Mac's cases, the drift pins | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| 2 | Rust: the mouse buttons in the poll, `pointer-button`, the shape-changed recompute | `nm-implementer-deep`, **Sonnet 5.5**, high | 1 (Tauri windowing and click-through: the poll thread, `WS_EX_TRANSPARENT`, Win32) | `nm-reviewer` |
| 3 | The outside click in the island page | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 4 | The wings step aside in the island page, and Open on hover's wing hold | `nm-implementer-deep`, **Sonnet 5.5**, high | 1 (a spring-driven frame, click-through at the full zones, a poll that gives no tick) | `nm-reviewer` |
| 4b | **Owner checkpoint 1:** the pictures from the dev server | the main session and the owner | | none |
| 5 | Linux under X11: the pointer feed (droppable) | `nm-implementer-deep`, **Sonnet 5.5**, high | 1 (Xlib FFI on the poll thread, GDK on the main thread, input-region click-through kept) | `nm-reviewer` |
| 6 | Open Claude: the resolver, the commands, the four buttons | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 6b | **Owner checkpoint 2:** the pictures | the main session and the owner | | none |
| 7 | README, French spec sentences, AGENTS.md, the CLAUDE.md map bullet, the last checks | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| After 7 | The whole branch: cross-task contracts, the 0 % rule, privacy, the Wayland no-op | `nm-reviewer-deep`, **Sonnet 5.5**, high | 4 | none |
| 8 | **Owner checkpoint:** the real-machine checks | the main session and the owner | | none |

Why not Haiku for 2, 4 and 5: they design platform code rather than copy it (trigger 1): a poll thread that must read buttons before an existing early `continue`, click-through that must flip on the tick the shape changes, and an Xlib connection per thread. Their code is given in full and was checked against the files; a Haiku attempt is a reasonable first try only for Task 2's Rust and only if the owner prefers it. If a Haiku task fails twice, hand it to `nm-implementer-deep` (trigger 2) and say so in the ledger.

## Execution

One worktree chat session runs the whole plan: branch `u1b/windows-island-parity`. The session's model is **Sonnet 5.5 at high effort** (trigger 5: three Sonnet tasks, and tasks whose interfaces cross Rust and TypeScript; a Sonnet session dispatches Haiku subagents for the rest). The session dispatches every task to the agent in the table. Nothing is pushed. It edits `island.rs`, `lib.rs`, `island.ts` and `style.css`, so it must not run beside another plan that edits them (G2-tauri, if started).

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run `git switch -c u1b/windows-island-parity notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-16-u1b-windows-island-parity.md`: only its Steps 1 and 2 (the base checks: `git merge-base --is-ancestor dc91b739 HEAD` must succeed, and the anchor counts must match). Read `CLAUDE.md`, `ARCHITECT.md` and that plan. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1. The owner approves in advance the controller brief the main session will send as your next message.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-16-u1b-windows-island-parity.md` with `superpowers:subagent-driven-development`, task by task, on branch `u1b/windows-island-parity`. Dispatch each task to the agent the plan's "Tasks and agents" table names (Haiku 5.5 first; Sonnet 5.5 only where the table names it or for a task Haiku failed twice, and then the trigger goes in the ledger), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `u1b/windows-island-parity`. If either is wrong, stop and report. Commit with `git commit -F <file>`, never `-m`, with the trailer of the model that did the task. Never push.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-16-u1b/progress.md`: one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files, never `..` and never a diff against a moving working tree.
> - **Every shell block in the plan passes `bash -n` before it is run**, and a script you write passes it too.
> - **Rust** runs as `windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/u1b` (Task 7) and per task as the task says, never with `docker build` or `docker pull`; if the image is missing or Docker is down, say so and mark the step "needs Docker". The Windows-only Rust is compiled by CI only: never write "compiled" for it.
> - **Servers and processes.** The dev server is `cd windows && npx vite --host 127.0.0.1 --port 1421` started in the background with its PID saved to a file under `${TMPDIR:-/tmp}/u1b-<unique>/`; stop it only by that PID. Never launch, quit or replace a NotchMeow app. Install and download nothing. Never read the real `~/.claude`.
> - **Stop and report on any refusal** (a denied command, a permission prompt): do not look for a workaround.
> - **Ping the main session.** The main session is the one named “NotchMeow — fork research & cat design” (its `local_…` id is in the chip prompt that started you). At each owner checkpoint (after Task 4 and after Task 6), at the end, and whenever you stop (a refusal, a failed check, a question), send your report to it with `SendMessage` as well as writing it in your own chat, so the main session can double-check the work (its own clone, merge and full checks) before anything reaches the owner.
> - **Owner checkpoints.** After Task 4 stop and report: the main session takes the pictures of 4b with the Browser pane over the dev server and copies them to `.claude/checkpoints/u1b/` of the worktree (gitignored); the owner may change the numbers (the 52 px wings are fixed by `COMPACT_W`; the fade and spring are the Mac's) or decide open question 4. After Task 6 stop for 6b the same way. After Task 7 dispatch `nm-reviewer-deep` over the whole branch, fix what it finds, then stop and report (Task 8).
>
> Report: the commits; the output of `cd windows && npm run check:cat`, `npx --no-install tsc --noEmit`, `windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/u1b` (or why it was skipped); the paths of the pictures; what is owed to CI or to a real machine; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is **Create `path`** (the file's exact content, given in full below), **Edit `path`** (a find text that occurs exactly once in that file at that point, and its replacement), or **Run**. Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see. Edit blocks that need a `$` or backslash show it as it is in the file. Edits to one file are applied top to bottom, and a later task's find text may include text an earlier task wrote (it says so).

**Windows/Linux commands** run in `windows/` (`npm run check:cat`, `npx --no-install tsc --noEmit`); `windows/node_modules` may be missing in a fresh worktree: symlink the main checkout's (`ln -s <main checkout>/windows/node_modules windows/node_modules`; it is gitignored) and install nothing. A `sed -i` differs between macOS and Linux: use the Edit blocks, not `sed`.

**Rust.** `windows/scripts/cargo-linux.sh <cargo args>` runs cargo in the Linux container that holds the Tauri build dependencies (Docker Desktop must be up). Always `--offline --target-dir /repo/windows/target/u1b`. It compiles the Linux side only; `platform/windows.rs` and the Windows-only branches are compiled by `windows-tests.yml`.

**Pictures.** The island is the dev server's page `/` (`http://127.0.0.1:1421/`, `IS_TAURI` false, `window.__nm.island` exposed); `/?dev` is the cat contact sheet and has no island. The main session takes the pictures (Browser pane, viewport 720 x 320) and drives the island through `__nm.island` (`onCursor`, `onPointerButton`, `fsm`), with the snippets of Task 4b and Task 6b.

**Bite steps.** Some steps break the code on purpose to prove a test fails. Back the file up into a folder you made with `mktemp -d`, change it as the step says, run the test, and copy the backup back; the next step starts from the real file.

## Dry run (what was run before this plan was written, and what was not)

Run against `dc91b739` in a scratch copy made with `git archive` (nothing in the repository was touched):

- Task 1's six files exactly as printed below: `wing.test.mjs`, `outside-click.test.mjs`, `wingdriver.test.mjs` pass (**22 tests**, Node 22.23, `--experimental-strip-types`); the Swift constants are read from the real Swift files by the drift pins.
- Task 2's `pointer.rs` and Task 6's `claude_app.rs` as printed, in a scratch cargo crate (**9 tests** pass, `cargo test --offline`).
- Every **Edit** block in this plan was applied by a script, in task order, to the scratch copy: each find text occurred exactly once (**80 finds**), then `npx --no-install tsc --noEmit` and `npm run check:cat` ran on the result: `npx --no-install tsc --noEmit` is clean; `npm run check:cat` runs **577 tests, 0 failed** (525 at the base plus the 52 new ones of Tasks 1 to 6); `npm run check:sidekick` passes 139 of 140, the one failure being the base's own (Task 0 Step 3); `npm run check:claude` passes.
- The Linux Rust of Tasks 2, 5 and 6 (`pointer.rs`, `island.rs`, `lib.rs`, `platform/linux.rs` with its Xlib and GDK code, `claude_app.rs`) compiled in the project's Linux container with no warning, and **14 tests passed** (`pointer::` 3, `claude_app::` 6, `x11_tests` 2, the existing `island::zoom_tests` 3), through a scratch copy of `windows/scripts/cargo-linux.sh` and `--target-dir /repo/windows/target/u1b-dry`.

Not run: any Windows-only Rust (`platform/windows.rs`, the Windows branches of `island.rs`), the X11 code of Task 5 (needs an X server), the PowerShell call and the real Claude install paths (no Windows machine), and anything with a real window. Those are named in each task and in Task 8.

---

## Tasks

### Task 0: Worktree and baseline

**Agent: the session itself.** Steps 1 and 2 are all the setup chip runs; Steps 3 and 4 run in the controller phase.

- [ ] **Step 1: The branch**

```bash
git switch -c u1b/windows-island-parity notchmeow/rebrand
git merge-base --is-ancestor dc91b739 HEAD && echo "base ok"
git rev-parse --show-toplevel && git branch --show-current
```

Expected: `base ok`; the worktree's folder; `u1b/windows-island-parity`. If the ancestor check fails, stop and report.

- [ ] **Step 2: The anchors this plan edits still read as they did**

```bash
cd windows
grep -c 'use crate::platform::{self, cursor_physical, left_button_down};' src-tauri/src/island.rs
grep -c 'let (period, screen_every) = if platform::CURSOR_POLL { (16, 30) } else { (500, 1) };' src-tauri/src/island.rs
grep -c 'let _ = win.emit("cursor", CursorPayload { x, y });' src-tauri/src/island.rs
grep -c 'cursor_poll: platform::CURSOR_POLL,' src-tauri/src/lib.rs
grep -c 'pub fn left_button_down() -> bool {' src-tauri/src/platform/windows.rs src-tauri/src/platform/linux.rs
grep -c 'import { IslandStateMachine } from "./fsm";' src/island/island.ts
grep -c 'private dragOut = new DragOutGuard();' src/island/island.ts
grep -c 'get pointerInside(): boolean {' src/island/island.ts
grep -c 'const inIsland = this.hitRectContains(x, y);' src/island/island.ts
grep -c 'this.radius.step(dt, nowMs);' src/island/island.ts
grep -c 'await onEvent<{ x: number; y: number }>("cursor", ({ x, y }) => island.onCursor(x, y));' src/main.ts
grep -c 'get canCarry(): boolean { return this.trip.phase === "home"; }' src/island/desktop.ts
grep -c 'shelfCaps = { dragOut: false, send: false };' src/core/state.ts
grep -c 'btn("Open terminal", "primary", () => actions.openTerminal()),' src/views/views.ts
cd ..
```

Expected: every line prints `1` (the `left_button_down` line prints `src-tauri/src/platform/windows.rs:1` and `src-tauri/src/platform/linux.rs:1`). Any other count: the base moved; stop and report which.

- [ ] **Step 3: Baselines (record the numbers in the ledger)**

```bash
cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)|✖"; npx --no-install tsc --noEmit && echo "tsc ok"; cd ..
windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/u1b 2>&1 | grep -E "^test result|FAILED|^error" | head
```

Expected: `check:cat` `fail 0` (the dry run saw `tests 525`); **`check:sidekick` has one failure at the base** (`explain.test.mjs`, "the card: the line sits between the command and the buttons...": it pins the Deny and Allow button lines that U1's click guard rewrote; found while writing this plan, not ours, left alone: record it in the ledger and expect exactly that one `✖` at every later step); `tsc ok`; every `test result: ok`. If Docker is down, write "needs Docker" for the Rust line and go on.

- [ ] **Step 4: Nothing to commit.** The ledger has the branch, the base commit and the three baseline lines.

---

### Task 1: The pure rules in TypeScript, the Mac's cases, the drift pins

**Agent: `nm-implementer-light` (Haiku 5.5, medium).** The code is given in full; it was run in the dry run.

**Files:**
- Create: `windows/src/island/outsideclick.ts`, `windows/src/island/wing.ts`, `windows/src/island/wingdriver.ts`
- Create: `windows/scripts/cat-tests/outside-click.test.mjs`, `windows/scripts/cat-tests/wing.test.mjs`, `windows/scripts/cat-tests/wingdriver.test.mjs`

**Interfaces:**
- Produces (`outsideclick.ts`): `CLICK_SLOP = 4`; `OutsideContext` (`expanded`, `pinned`, `held`, `typing`, `pointerInIsland`, `busy`: boolean); `shouldFold(c): boolean`; `class ClickTracker` (`down(x, y)`, `up(x, y): boolean`, `reset()`); `ButtonEvent` (`down`, `x`, `y`, `own`); `class OutsideClick` (`constructor(context: (e: ButtonEvent) => OutsideContext, fold: () => void)`, `onButton(e)`, `reset()`).
- Produces (`wing.ts`): `FADE_OUT 0.15`, `FADE_IN 0.25`, `RETURN_DELAY 1`, `LEFT_DWELL 0.4`, `SPRING_RESPONSE 0.22`, `SPRING_DAMPING 0.68`; `Rect`, `Zone`, `Wings`; `wings(island, notchWidth, slop?)`, `zoneOf(w, x, y)`, `foldedWidth`, `widthAt(full, notchWidth, swoosh)`, `foldedHitRect(viewportW, h, notchWidth, margin)`, `stepFade(level, folded, dt)`, `isActive(compact, greetingTail, dragging, alert)`; `WingOut` (`faded`, `passThrough`); `class WingYield` (`step(now, zone, active, buttonDown)`, `nextDeadline(now): number | null`).
- Produces (`wingdriver.ts`): `WingEnv` (`now()` in seconds, `set(fn, ms)`, `clear(id)`); `class WingDriver` (`constructor(env, buttonDown, changed)`, `state`, `pending`, `feed(zone, active)`, `poke()`).
- Consumes: nothing.

- [ ] **Step 1: Write the three tests**

**Create `windows/scripts/cat-tests/outside-click.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { CLICK_SLOP, ClickTracker, OutsideClick, shouldFold } from "../../src/island/outsideclick.ts";

// The cases of tests/IslandOutsideClickTests.swift (the Mac), in the same order.
const open = { expanded: true, pinned: false, held: false, typing: false, pointerInIsland: false, busy: false };
const withOnly = (edit) => ({ ...open, ...edit });

test("the 4 pt slop is the Mac's", () => {
  assert.equal(CLICK_SLOP, 4);
  const swift = fs.readFileSync(new URL("../../../NotchBuddy/Sources/App/IslandOutsideClick.swift", import.meta.url), "utf8");
  assert.equal(Number(/static let clickSlop: CGFloat = ([0-9.]+)/.exec(swift)?.[1]), CLICK_SLOP);
});

test("an open island with nothing waiting folds on a click outside; every reason to stay keeps it", () => {
  assert.equal(shouldFold(open), true);
  assert.equal(shouldFold(withOnly({ expanded: false })), false, "a compact or hidden island is never folded by a click");
  assert.equal(shouldFold(withOnly({ pinned: true })), false);
  assert.equal(shouldFold(withOnly({ held: true })), false);
  assert.equal(shouldFold(withOnly({ typing: true })), false);
  assert.equal(shouldFold(withOnly({ pointerInIsland: true })), false);
  assert.equal(shouldFold(withOnly({ busy: true })), false);
  const reasons = [{ pinned: true }, { held: true }, { typing: true }, { pointerInIsland: true }, { busy: true }];
  reasons.forEach((a, i) => reasons.slice(i + 1).forEach((b) => assert.equal(shouldFold(withOnly({ ...a, ...b })), false, `two reasons to stay (${i})`)));
});

test("a click is a press and a release within 4 px; a drag is not", () => {
  const t = new ClickTracker();
  t.down(100, 100);
  assert.equal(t.up(102, 101), true, "2 px apart is a click");
  t.down(100, 100);
  assert.equal(t.up(100, 120), false, "dragged 20 px (a file taken from Explorer, a window moved) is not a click");
  assert.equal(t.up(100, 100), false, "a release with no press seen is not a click, and the press is forgotten after each release");
  t.down(0, 0);
  assert.equal(t.up(3, 2), true, "3.6 px is still a click");
  t.down(0, 0);
  t.reset();
  assert.equal(t.up(0, 0), false, "a reset forgets the press");
  t.down(0, 0);
  assert.equal(t.up(NaN, 0), false, "a point that is not a number is not a click");
});

test("the glue folds on the release of a click, deciding by what was true at the press", () => {
  let folds = 0, ctx = open;
  const seen = [];
  const oc = new OutsideClick((e) => (seen.push(e), ctx), () => folds++);
  const press = (x, y, own = false) => oc.onButton({ down: true, x, y, own });
  const release = (x, y) => oc.onButton({ down: false, x, y, own: false });
  press(500, 300); release(501, 300);
  assert.equal(folds, 1, "a click outside folds");
  press(500, 300); release(500, 340);
  assert.equal(folds, 1, "a drag does not");
  release(500, 300);
  assert.equal(folds, 1, "a release with no press does not");
  ctx = withOnly({ typing: true });
  press(500, 300);
  ctx = open;                       // the press took the keyboard away from the chat before the release
  release(500, 300);
  assert.equal(folds, 1, "what was true at the press decides, not what is true at the release");
  press(500, 300); oc.reset(); release(500, 300);
  assert.equal(folds, 1, "a reset forgets a press in flight");
  press(10, 20, true);
  assert.deepEqual(seen.at(-1), { down: true, x: 10, y: 20, own: true }, "the context is asked with the whole event, so it can see the point and whether it is the app's own window");
});
```

**Create `windows/scripts/cat-tests/wing.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import * as W from "../../src/island/wing.ts";

// The cases of tests/IslandWingTests.swift (the Mac), in the same order. The Mac's y axis points up and the page's down: the island's strip is y 0..32 here, the Mac's 288..320.
const tick = (y, t, zone, { active = true, button = false } = {}) => y.step(t, zone, active, () => button);
const out = (faded, passThrough) => ({ faded, passThrough });
const near = (a, b) => assert.ok(Math.abs(a - b) <= 1e-9, `${a} is not ${b}`);

test("the numbers the owner chose, and the Mac's file still says the same", () => {
  near(W.FADE_OUT, 0.15);
  near(W.RETURN_DELAY, 1.0);
  assert.ok(W.FADE_IN >= W.FADE_OUT && W.FADE_IN < W.RETURN_DELAY);
  near(W.SPRING_RESPONSE, 0.22);
  assert.ok(W.SPRING_DAMPING < 1 && W.SPRING_DAMPING > 0.5);
  near(W.LEFT_DWELL, 0.4);
  // The drift pin: the Swift constants are read from the Swift file, so changing one side alone fails here.
  const swift = fs.readFileSync(new URL("../../../NotchBuddy/Sources/App/IslandWing.swift", import.meta.url), "utf8");
  const num = (name) => Number(new RegExp(`static let ${name}: (?:TimeInterval|Double) = ([0-9.]+)`).exec(swift)?.[1]);
  near(num("fadeOut"), W.FADE_OUT);
  near(num("fadeIn"), W.FADE_IN);
  near(num("returnDelay"), W.RETURN_DELAY);
  near(num("leftDwell"), W.LEFT_DWELL);
  near(num("springResponse"), W.SPRING_RESPONSE);
  near(num("springDamping"), W.SPRING_DAMPING);
});

test("the two wings: the parts beside the notch", () => {
  const island = { x: 188, y: 0, w: 344, h: 32 };
  const w = W.wings(island, 184);
  assert.deepEqual([w.left.x, w.left.x + w.left.w], [188, 268], "the left wing runs from the island's left edge to the notch's left edge");
  assert.deepEqual([w.right.x, w.right.x + w.right.w], [452, 532]);
  assert.deepEqual([w.left.y, w.left.y + w.left.h, w.right.y, w.right.y + w.right.h], [0, 32, 0, 32], "both are the strip's height");
  const inAny = (x, y) => W.zoneOf(w, x, y) !== null;
  assert.ok(!inAny(360, 16) && !inAny(268.1, 16) && !inAny(451.9, 16), "the notch is in neither: it is the hover-open zone");
  assert.ok(inAny(188, 16) && inAny(267.9, 16) && inAny(452, 16) && inAny(531.9, 16), "the first and last points of each wing are in it");
  const slopped = W.wings(island, 184, 6);
  assert.deepEqual([slopped.left.x, slopped.left.x + slopped.left.w, slopped.right.x, slopped.right.x + slopped.right.w, slopped.left.y, slopped.right.y + slopped.right.h], [182, 268, 452, 538, -6, 38],
    "with the hover slop each wing reaches further out, up and down, and not towards the notch");
  const bar = W.wings({ x: 240, y: 0, w: 240, h: 24 }, 80);
  assert.deepEqual([bar.left.w, bar.right.w, bar.right.h], [80, 80, 24], "the same rule around an 80 px bar");
  const none = W.wings({ x: 100, y: 0, w: 50, h: 30 }, 184);
  assert.deepEqual([none.left.w, none.right.w], [0, 0], "an island narrower than its notch has no wing at all");
  // The PC's compact island: 288 wide, the 184 px middle, 52 px a side; the page's hit margin is 14 px.
  const pc = W.wings({ x: 216, y: 0, w: 288, h: 32 }, 184, 14);
  assert.deepEqual([pc.left.x, pc.left.w, pc.right.x, pc.right.w], [202, 66, 452, 66]);
});

test("what the island folds to", () => {
  assert.equal(W.foldedWidth(184), 184);
  assert.equal(W.widthAt(344, 184, 0), 344);
  assert.equal(W.widthAt(344, 184, 1), 184);
  assert.equal(W.widthAt(344, 184, 0.5), 264);
});

test("click-through while folded, and the fade, one frame at a time", () => {
  assert.deepEqual(W.foldedHitRect(720, 32, 184, 14), { x: 282, y: 0, w: 156, h: 32 }, "the middle shrunk by the 14 px margin on each side: the window adds it back and covers exactly the notch-wide middle");
  const r = W.foldedHitRect(720, 32, 184, 14);
  assert.deepEqual([r.x - 14, r.x + r.w + 14], [268, 452], "no dead band beside the middle: the wing zones start where it ends");
  assert.equal(W.foldedHitRect(720, 32, 20, 14).w, 0, "a margin wider than the middle leaves nothing");
  near(W.stepFade(1, true, 0.15), 0);
  near(W.stepFade(1, true, 0.075), 0.5);
  near(W.stepFade(0, false, 0.25), 1);
  near(W.stepFade(0, false, 0.125), 0.5);
  near(W.stepFade(0.2, true, 5), 0);
  near(W.stepFade(0.8, false, 5), 1);
});

test("when the island can step aside", () => {
  assert.ok(W.isActive(true, false, false, false));
  assert.ok(!W.isActive(false, false, false, false), "not hidden or expanded");
  assert.ok(!W.isActive(true, true, false, false), "not while the greeting's tail draws the session cats");
  assert.ok(!W.isActive(true, false, true, false), "not while the cat's head is being dragged");
  assert.ok(!W.isActive(true, false, false, true), "not while an alert wants the island");
});

test("the fold: in at once, out one second after the pointer has left both wings", () => {
  const y = new W.WingYield();
  assert.deepEqual(tick(y, 0, null), out(false, false));
  assert.deepEqual(tick(y, 1.0, "right"), out(true, true), "the pointer reaches a wing: folded, and the mouse passes through on that very tick");
  assert.deepEqual(tick(y, 11.0, "right"), out(true, true), "it stays while the pointer stays (ten seconds)");
  assert.deepEqual(tick(y, 12.0, null), out(true, false), "the pointer leaves: still folded, the mouse no longer passed on");
  assert.deepEqual(tick(y, 12.9, null), out(true, false));
  assert.deepEqual(tick(y, 13.0, null), out(false, false), "1 s after the pointer was first seen away it swooshes back out");
  assert.deepEqual(tick(y, 20.0, null), out(false, false));
});

test("the left wing folds the island only after a 0.4 s rest with no button; the right wing at once", () => {
  let y = new W.WingYield();
  assert.deepEqual(tick(y, 5.0, "left"), out(false, false));
  assert.deepEqual(tick(y, 5.399, "left"), out(false, false));
  assert.deepEqual(tick(y, 5.4, "left"), out(true, true));
  assert.deepEqual(tick(y, 9.0, "left"), out(true, true));
  y = new W.WingYield();
  tick(y, 1.0, "left");
  assert.deepEqual(tick(y, 1.2, "left", { button: true }), out(false, false), "a press at 200 ms cancels the dwell");
  assert.deepEqual(tick(y, 1.4, "left"), out(false, false), "the button released at 400 ms: the dwell starts over");
  assert.deepEqual(tick(y, 1.799, "left"), out(false, false));
  assert.deepEqual(tick(y, 1.8, "left"), out(true, true));
  y = new W.WingYield();
  tick(y, 0, "left");
  tick(y, 0.3, null);
  assert.deepEqual(tick(y, 0.5, "left"), out(false, false), "leaving before the dwell is over cancels it");
  assert.deepEqual(tick(y, 0.899, "left"), out(false, false));
  assert.deepEqual(tick(y, 0.9, "left"), out(true, true));
  y = new W.WingYield();
  assert.deepEqual(tick(y, 0, "right"), out(true, true), "the right wing needs no dwell");
  const held = new W.WingYield();
  for (let t = 0; t <= 3.0001; t += 0.1) tick(held, t, "left", { button: true });
  assert.deepEqual(tick(held, 3.1, "left", { button: true }), out(false, false), "a button held the whole time never folds it");
  const lazy = new W.WingYield();
  let leftAsked = 0;
  for (let i = 0; i < 20; i++) lazy.step(i * 0.01, i < 10 ? null : "left", true, () => (leftAsked++, false));
  assert.equal(leftAsked, 10, "the button is asked only while the pointer is on the left wing");
  const folded = new W.WingYield();
  tick(folded, 0, "right");
  let askedFolded = 0;
  for (let i = 1; i < 10; i++) folded.step(i, "left", true, () => (askedFolded++, false));
  assert.equal(askedFolded, 0, "once folded, the left wing asks nothing and keeps the fold");
});

test("both wings are one hover", () => {
  const y = new W.WingYield();
  tick(y, 0, "right");
  tick(y, 5.0, null);
  assert.deepEqual(tick(y, 5.8, "right"), out(true, true), "back in the other wing at 5.8 s: still folded");
  tick(y, 6.0, null);
  assert.deepEqual(tick(y, 6.9, null), out(true, false), "away again at 6.0 s: 0.9 s later still folded");
  assert.deepEqual(tick(y, 7.0, null), out(false, false));
});

test("the mouse button held: a file dragged in, or a click that began elsewhere", () => {
  const y = new W.WingYield();
  assert.deepEqual(tick(y, 0, "right", { button: true }), out(false, false));
  assert.deepEqual(tick(y, 0.1, "right"), out(true, true), "releasing it over the wing then folds it");
  assert.deepEqual(tick(y, 0.2, "right", { button: true }), out(true, true), "a button pressed over a folded island leaves it folded");
});

test("an alert cancels the step-aside at once, and an inactive island never folds or asks about the button", () => {
  const y = new W.WingYield();
  tick(y, 0, "right");
  assert.deepEqual(tick(y, 0.5, "right", { active: false }), out(false, false));
  assert.deepEqual(tick(y, 0.6, "right", { active: false }), out(false, false));
  assert.deepEqual(tick(y, 0.7, "right"), out(true, true), "when the alert is over and the pointer is still on the wing, a new fold begins");
  const z = new W.WingYield();
  let asked = 0;
  z.step(0, null, true, () => (asked++, false));
  assert.equal(asked, 0);
  z.step(1, "right", true, () => (asked++, false));
  z.step(2, "right", true, () => (asked++, false));
  assert.equal(asked, 1, "asked once, when the fold begins");
  const quiet = new W.WingYield();
  let q = 0;
  for (let i = 0; i < 50; i++) quiet.step(i, i % 2 === 0 ? "right" : null, false, () => (q++, false));
  assert.equal(q, 0);
});

test("a clock that is not a time", () => {
  const y = new W.WingYield();
  tick(y, 0, "right");
  assert.deepEqual(tick(y, NaN, "right"), out(false, false));
  assert.deepEqual(tick(y, Infinity, "right"), out(false, false));
  assert.deepEqual(tick(y, 3, "right"), out(true, true));
  tick(y, 4, null);
  assert.deepEqual(tick(y, 1, null), out(true, false), "a clock that runs backwards does not bring the island back early");
  assert.equal(y.nextDeadline(NaN), null);
});

test("nextDeadline: the one wake-up the page needs, and nothing when nothing is pending", () => {
  const y = new W.WingYield();
  assert.equal(y.nextDeadline(0), null, "at rest: no timer");
  tick(y, 0, "left");
  const d = y.nextDeadline(0.1);
  assert.ok(Math.abs(d - 0.3) < 1e-9, `the dwell ends in about 0.3 s, got ${d}`);
  assert.deepEqual(tick(y, 0.1 + d, "left"), out(true, true), "waking at the deadline folds it");
  assert.equal(y.nextDeadline(1), null, "folded with the pointer on the wing: no timer");
  tick(y, 2, null);
  const r = y.nextDeadline(2.25);
  assert.ok(Math.abs(r - 0.75) < 1e-9, `the return ends in 0.75 s, got ${r}`);
  assert.deepEqual(tick(y, 2.25 + r, null), out(false, false));
  assert.equal(y.nextDeadline(5), null, "back at rest: no timer");
  const right = new W.WingYield();
  tick(right, 0, "right");
  assert.equal(right.nextDeadline(0), null, "the right wing has no dwell");
});

test("fuzz: 20000 ticks that must keep the rules", () => {
  let seed = 12345;
  const rnd = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 2 ** 32);
  const f = new W.WingYield();
  let t = 0, broke = 0, lastIn = -100, wasFaded = false;
  for (let i = 0; i < 20000; i++) {
    t += rnd() * 0.05;
    const p = rnd(), zone = p < 0.15 ? "left" : p < 0.3 ? "right" : null, inWing = zone !== null, active = rnd() < 0.95;
    const o = tick(f, t, zone, { active, button: rnd() < 0.05 });
    if (o.passThrough && !o.faded) broke++;
    if (!active && o.faded) broke++;
    if (o.passThrough && !inWing) broke++;
    if (active && inWing && o.faded) lastIn = t;
    if (active && !inWing && wasFaded && !o.faded && t - lastIn < W.RETURN_DELAY) broke++;
    wasFaded = active && o.faded;
  }
  assert.equal(broke, 0);
});
```

**Create `windows/scripts/cat-tests/wingdriver.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import { WingDriver } from "../../src/island/wingdriver.ts";

// A clock and a timer the test turns by hand.
function rig({ button = () => false } = {}) {
  let t = 0, nextId = 1;
  const timers = new Map();
  const changes = [];
  const env = { now: () => t, set: (fn, ms) => { const id = nextId++; timers.set(id, { fn, at: t * 1000 + ms }); return id; }, clear: (id) => { timers.delete(id); } };
  const driver = new WingDriver(env, () => button(), (now, before) => changes.push([before.faded, now.faded, now.passThrough]));
  const advance = (s) => {
    const end = t + s;
    for (;;) {
      const due = [...timers.entries()].filter(([, x]) => x.at <= end * 1000).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      t = due[1].at / 1000; timers.delete(due[0]); due[1].fn();
    }
    t = end;
  };
  return { driver, advance, timers, changes, at: () => t };
}

test("the right wing folds at once and arms nothing while the pointer stays", () => {
  const r = rig();
  assert.deepEqual(r.driver.feed("right", true), { faded: true, passThrough: true });
  assert.equal(r.timers.size, 0, "no wake-up is needed while the pointer rests on a folded island");
  assert.deepEqual(r.changes, [[false, true, true]]);
});

test("the left wing folds by itself after the 0.4 s dwell, with one timer and no cursor event", () => {
  const r = rig();
  assert.deepEqual(r.driver.feed("left", true), { faded: false, passThrough: false });
  assert.equal(r.timers.size, 1, "one one-shot wake-up for the dwell");
  r.advance(0.39);
  assert.equal(r.driver.state.faded, false);
  r.advance(0.02);
  assert.deepEqual(r.driver.state, { faded: true, passThrough: true });
  assert.equal(r.timers.size, 0, "folded with the pointer on the wing: nothing pending");
});

test("it comes back by itself 1 s after the pointer has left, and then nothing is pending", () => {
  const r = rig();
  r.driver.feed("right", true);
  r.advance(3);
  r.driver.feed(null, true);
  assert.equal(r.timers.size, 1);
  r.advance(0.99);
  assert.equal(r.driver.state.faded, true);
  r.advance(0.02);
  assert.deepEqual(r.driver.state, { faded: false, passThrough: false });
  assert.equal(r.timers.size, 0);
  assert.equal(r.driver.pending, false);
});

test("an alert cancels it at once and clears the wake-up; leaving the left wing cancels the dwell", () => {
  const r = rig();
  r.driver.feed("left", true);
  r.driver.feed(null, true);
  assert.equal(r.timers.size, 0, "the dwell was cancelled, so no wake-up is left");
  r.driver.feed("right", true);
  r.driver.feed("right", false);
  assert.deepEqual(r.driver.state, { faded: false, passThrough: false });
  assert.equal(r.timers.size, 0);
});

test("a button pressed during the dwell cancels it when the page pokes the driver", () => {
  let down = false;
  const r = rig({ button: () => down });
  r.driver.feed("left", true);
  r.advance(0.2);
  down = true;
  r.driver.poke();
  assert.equal(r.timers.size, 0, "a press ends the dwell; nothing is pending until the button is up");
  r.advance(1);
  assert.equal(r.driver.state.faded, false);
  down = false;
  r.driver.poke();
  r.advance(0.41);
  assert.equal(r.driver.state.faded, true, "released: the dwell starts over and folds 0.4 s later");
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/outside-click.test.mjs scripts/cat-tests/wing.test.mjs scripts/cat-tests/wingdriver.test.mjs 2>&1 | grep -E "^ℹ (tests|pass|fail)|ERR_MODULE_NOT_FOUND" | head -5`
Expected: FAIL: `ERR_MODULE_NOT_FOUND` for `src/island/outsideclick.ts` (and `wing.ts`, `wingdriver.ts`).

- [ ] **Step 3: The rules**

**Create `windows/src/island/outsideclick.ts`:**

```ts
// A click outside the open island folds it (Windows, and Linux under X11). The rules, as plain values: when a click counts, and when the island stays. Port of
// NotchBuddy/Sources/App/IslandOutsideClick.swift, case for case (windows/scripts/cat-tests/outside-click.test.mjs). No DOM, no Tauri: the island page owns the facts
// (`OutsideContext`) and the OS gives it the button edges (Rust `pointer-button`, island.rs). Nothing here listens to anything on its own.

/** A press that moves farther than this (logical px) before it is released is a drag (a file taken out of Explorer, a window moved, a selection), not a click. */
export const CLICK_SLOP = 4;

/** What the page knows when a click is pressed. */
export interface OutsideContext {
  /** The island is expanded. */
  expanded: boolean;
  /** The island is pinned open (an approval pins it, and so does a chat card). */
  pinned: boolean;
  /** Something holds the island open: a permission request or question waiting, the shelf's drag-out or share hold, a native menu of the island. */
  held: boolean;
  /** The user is typing in the chat: the chat view is showing and a text field has the keyboard. */
  typing: boolean;
  /** The press is over the island (with its hit margin) or over another window of this app (Settings, the desktop cat, the tray menu): not outside. */
  pointerInIsland: boolean;
  /** The cat's head is being dragged out of the notch, a file is being dragged in, or a shelf tile is dragged out. */
  busy: boolean;
}

/** Whether a click outside folds the island now. */
export function shouldFold(c: OutsideContext): boolean {
  return c.expanded && !c.pinned && !c.held && !c.typing && !c.pointerInIsland && !c.busy;
}

/** Tells a click from a drag: remembers where the button went down, and says on release whether the pair was a click (it did not move more than `CLICK_SLOP`). */
export class ClickTracker {
  private downAt: { x: number; y: number } | null = null;

  down(x: number, y: number): void {
    this.downAt = { x, y };
  }

  /** The release. True when it ends a click; the press is forgotten either way. A release with no press seen is not a click. */
  up(x: number, y: number): boolean {
    const d = this.downAt;
    this.downAt = null;
    if (!d) return false;
    return Math.hypot(x - d.x, y - d.y) <= CLICK_SLOP;
  }

  /** Forget a press (the watch was switched off). */
  reset(): void {
    this.downAt = null;
  }
}

/** A mouse button edge from the OS, in the island window's logical px. `own`: the point is over a window of this app. */
export interface ButtonEvent {
  down: boolean;
  x: number;
  y: number;
  own: boolean;
}

/**
 * The glue: feed it the button edges while the island is expanded. What the page knew at the press decides (a press can take the keyboard away from the chat before it is
 * released); the release folds when the pair was a click and not a drag.
 */
export class OutsideClick {
  private readonly tracker = new ClickTracker();
  private atDown: OutsideContext | null = null;
  private readonly context: (e: ButtonEvent) => OutsideContext;
  private readonly fold: () => void;

  constructor(context: (e: ButtonEvent) => OutsideContext, fold: () => void) {
    this.context = context;
    this.fold = fold;
  }

  onButton(e: ButtonEvent): void {
    if (e.down) {
      this.tracker.down(e.x, e.y);
      this.atDown = this.context(e);
      return;
    }
    const ctx = this.atDown;
    this.atDown = null;
    if (!this.tracker.up(e.x, e.y) || !ctx) return;
    if (shouldFold(ctx)) this.fold();
  }

  /** The watch was switched off (the island is no longer expanded): forget a press in flight. */
  reset(): void {
    this.tracker.reset();
    this.atDown = null;
  }
}
```

**Create `windows/src/island/wing.ts`:**

```ts
// The compact island's two wings step aside for the pointer (Windows, and Linux under X11). The rules, as plain numbers and times: the wings' rectangles, when the island can
// step aside, the swoosh's numbers and the fold's timing. Port of NotchBuddy/Sources/App/IslandWing.swift, case for case (windows/scripts/cat-tests/wing.test.mjs). On a PC the
// compact island is 288 px wide with the 184 px "notch" in the middle, so each wing is 52 px; while the pointer is over EITHER wing the whole island swooshes into the
// notch-wide middle, its cats, grid and badge fade as it shrinks, and the window passes the mouse on to whatever is under the wings. `RETURN_DELAY` seconds after the pointer has left
// both wings it swooshes back out. The right wing (the grid) folds the island at once; the left wing (the big cat) only after the pointer has rested there `LEFT_DWELL` seconds
// with no mouse button pressed. An alert cancels it at once. Unlike the Mac there is no poll tick to feed it every 16 ms (the cursor event comes only when the pointer moves), so
// `WingYield.nextDeadline` tells the page when to wake it again: one one-shot timer, armed only while a dwell or a return is running.

/** How long the cats, the grid and the badge take to fade out as the island shrinks (s), and to fade back in (s). */
export const FADE_OUT = 0.15;
export const FADE_IN = 0.25;
/** How long the pointer must have been away from both wings before the island swooshes back out (s). */
export const RETURN_DELAY = 1.0;
/** How long the pointer must rest on the LEFT wing, with no mouse button pressed, before the island folds (s). The right wing folds it at once. */
export const LEFT_DWELL = 0.4;
/** The swoosh is a spring: about 0.22 s to settle, with a slight overshoot (a damping fraction a little under 1). */
export const SPRING_RESPONSE = 0.22;
export const SPRING_DAMPING = 0.68;
/** The slack the dwell's comparison allows, so that 0.4 s on a clock of binary fractions is 0.4 s. */
const EPSILON = 1e-9;

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export type Zone = "left" | "right";

export interface Wings {
  left: Rect;
  right: Rect;
}

/** Half-open, like CGRect.contains on the Mac: the first point is in, the last edge is not, and an empty rectangle holds nothing. */
function inRect(r: Rect, px: number, py: number): boolean {
  return px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h;
}

/**
 * The two wings in the window's coordinates (y down), each the strip's whole height: the left from the island's left edge to the notch's left edge, the right from the notch's right
 * edge to the island's right edge. `island` is the compact island's FULL frame and `notchWidth` the notch's. `slop` is how far the island's hover area reaches beyond the strip: each
 * wing takes it on its outer side, top and bottom, and not on the side towards the notch.
 */
export function wings(island: Rect, notchWidth: number, slop = 0): Wings {
  const midX = island.x + island.w / 2;
  const notchLeft = midX - notchWidth / 2;
  const notchRight = midX + notchWidth / 2;
  const leftWidth = Math.max(0, notchLeft - (island.x - slop));
  const rightWidth = Math.max(0, island.x + island.w + slop - notchRight);
  return {
    left: { x: island.x - slop, y: island.y - slop, w: leftWidth, h: island.h + 2 * slop },
    right: { x: notchRight, y: island.y - slop, w: rightWidth, h: island.h + 2 * slop },
  };
}

/** Which wing the point is in, if any. */
export function zoneOf(w: Wings, px: number, py: number): Zone | null {
  return inRect(w.left, px, py) ? "left" : inRect(w.right, px, py) ? "right" : null;
}

/** The width the island shrinks to: the notch's own. */
export function foldedWidth(notchWidth: number): number {
  return notchWidth;
}

/** The island's drawn width at `swoosh` (0 at rest, 1 folded into the notch): linear; the page lets a spring move `swoosh`. */
export function widthAt(full: number, notchWidth: number, swoosh: number): number {
  return full - (full - foldedWidth(notchWidth)) * swoosh;
}

/**
 * The rectangle the window uses for click-through while the island is folded (window coordinates, `viewportW` wide): the notch-wide middle, shrunk by the hit margin on each side
 * because the window adds the margin back. The wings pass the mouse on from the first tick, and no dead band is left beside the middle.
 */
export function foldedHitRect(viewportW: number, h: number, notchWidth: number, margin: number): Rect {
  const w = Math.max(0, foldedWidth(notchWidth) - 2 * margin);
  return { x: (viewportW - w) / 2, y: 0, w, h };
}

/** The cats', grid's and badge's opacity, moved one frame (`dt` seconds): down to 0 in `FADE_OUT` seconds while the island is folded, back up to 1 in `FADE_IN` seconds. */
export function stepFade(level: number, folded: boolean, dt: number): number {
  return folded ? Math.max(0, level - dt / FADE_OUT) : Math.min(1, level + dt / FADE_IN);
}

/**
 * Whether the island can step aside now: only in the compact island, not while the greeting's tail still draws the session cats in the grid's place, not while a drag of the cat's head
 * is under way, and not while an alert wants the island (a permission request or question waits, a file is on its way in, the desktop cat is away from the notch, the shelf holds the island).
 */
export function isActive(compact: boolean, greetingTail: boolean, dragging: boolean, alert: boolean): boolean {
  return compact && !greetingTail && !dragging && !alert;
}

export interface WingOut {
  /** The island is folded into the notch (or folding). */
  faded: boolean;
  /** The pointer is over a wing of the folded island: the window must not take the mouse, and the island must not count the pointer as over it. */
  passThrough: boolean;
}

/** The island's memory between two ticks. */
export class WingYield {
  private faded = false;
  /** When the pointer was first seen away from both wings (while folded); null while it is over one. */
  private leftAt: number | null = null;
  /** When the pointer began to rest on the left wing with no button pressed (before the island has folded); null otherwise. */
  private restSince: number | null = null;

  private reset(): void {
    this.faded = false;
    this.leftAt = null;
    this.restSince = null;
  }

  /**
   * One tick, `now` in seconds. `zone`: the wing the pointer is in, if any. `active`: `isActive`. `buttonDown` says whether any mouse button is held (a file being dragged in, a click
   * that began on the big cat, a right-click): then no fold begins, a dwell on the left wing starts over, and a fold that has begun is not undone by it. It is asked only while the pointer
   * is in a wing and the island has not folded yet.
   */
  step(now: number, zone: Zone | null, active: boolean, buttonDown: () => boolean): WingOut {
    if (!active || !Number.isFinite(now)) {
      this.reset();
      return { faded: false, passThrough: false };
    }
    if (zone) {
      this.leftAt = null;
      if (this.faded) return { faded: true, passThrough: true };
      if (zone === "right") {
        this.restSince = null;
        if (!buttonDown()) this.faded = true;
      } else if (buttonDown()) {
        this.restSince = null;
      } else {
        const since = this.restSince ?? now;
        this.restSince = since;
        if (now - since + EPSILON >= LEFT_DWELL) this.faded = true;
      }
      return { faded: this.faded, passThrough: this.faded };
    }
    this.restSince = null;
    if (this.faded) {
      const since = this.leftAt ?? now;
      this.leftAt = since;
      if (now - since >= RETURN_DELAY) this.reset();
    }
    return { faded: this.faded, passThrough: false };
  }

  /**
   * Seconds from `now` until the next instant at which `step` would answer differently with no new input: the left dwell ending, or the return delay ending. null when nothing is
   * pending (the page arms no timer then).
   */
  nextDeadline(now: number): number | null {
    if (!Number.isFinite(now)) return null;
    if (!this.faded && this.restSince !== null) return Math.max(0, this.restSince + LEFT_DWELL - now);
    if (this.faded && this.leftAt !== null) return Math.max(0, this.leftAt + RETURN_DELAY - now);
    return null;
  }
}
```

**Create `windows/src/island/wingdriver.ts`:**

```ts
// Feeds the wing's rules (island/wing.ts) from what the island page has: the pointer's wing, whether the island can step aside, the mouse button. The Mac asks every 16 ms; here the
// cursor event comes only when the pointer moves, so after every answer the driver arms ONE one-shot timer for the next instant the rules would answer differently (the left wing's
// dwell ending, the return delay ending), and nothing at all when nothing is pending. The clock and the timer are injected so the plain-Node checks can turn time by hand.

import { WingYield, type WingOut, type Zone } from "./wing.ts";

export interface WingEnv {
  /** Seconds, monotonic. */
  now(): number;
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
}

export class WingDriver {
  private readonly rules = new WingYield();
  private out: WingOut = { faded: false, passThrough: false };
  private zone: Zone | null = null;
  private active = false;
  private timer: number | null = null;
  private readonly env: WingEnv;
  private readonly buttonDown: () => boolean;
  private readonly changed: (now: WingOut, before: WingOut) => void;

  constructor(env: WingEnv, buttonDown: () => boolean, changed: (now: WingOut, before: WingOut) => void) {
    this.env = env;
    this.buttonDown = buttonDown;
    this.changed = changed;
  }

  /** The last answer. */
  get state(): WingOut {
    return this.out;
  }

  /** Whether a wake-up is armed (a test and the 0 % pin look at it). */
  get pending(): boolean {
    return this.timer !== null;
  }

  /** The pointer is in `zone` (null: in no wing) and the island may (`active`) or may not step aside now. */
  feed(zone: Zone | null, active: boolean): WingOut {
    this.zone = zone;
    this.active = active;
    return this.run();
  }

  /** Ask again with the last inputs: a mouse button went down or came up. */
  poke(): WingOut {
    return this.run();
  }

  private run(): WingOut {
    const before = this.out;
    this.out = this.rules.step(this.env.now(), this.zone, this.active, this.buttonDown);
    this.rearm();
    if (this.out.faded !== before.faded || this.out.passThrough !== before.passThrough) this.changed(this.out, before);
    return this.out;
  }

  private rearm(): void {
    if (this.timer !== null) {
      this.env.clear(this.timer);
      this.timer = null;
    }
    const seconds = this.rules.nextDeadline(this.env.now());
    if (seconds === null) return;
    this.timer = this.env.set(() => {
      this.timer = null;
      this.run();
    }, Math.ceil(seconds * 1000) + 1);
  }
}
```

- [ ] **Step 4: Run them**

Run: `cd windows && node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/outside-click.test.mjs scripts/cat-tests/wing.test.mjs scripts/cat-tests/wingdriver.test.mjs 2>&1 | grep -E "^ℹ (tests|pass|fail)|✖"`
Expected: PASS: `tests 22`, `pass 22`, `fail 0`.

Run: `cd windows && npx --no-install tsc --noEmit && echo "tsc ok"`
Expected: `tsc ok`.

- [ ] **Step 5: Bite: the drift pin is real**

Back `windows/src/island/wing.ts` up into a folder you made with `mktemp -d`. Change `export const LEFT_DWELL = 0.4;` to `0.5`, run `node --experimental-strip-types --test scripts/cat-tests/wing.test.mjs 2>&1 | grep -E "^ℹ fail"` from `windows/`.
Expected: at least `fail 2` (the Mac-numbers test and the left-wing dwell cases). Copy the backup back and run Step 4 again: PASS.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/src/island/outsideclick.ts windows/src/island/wing.ts windows/src/island/wingdriver.ts windows/scripts/cat-tests/outside-click.test.mjs windows/scripts/cat-tests/wing.test.mjs windows/scripts/cat-tests/wingdriver.test.mjs
git commit -F - <<'MSG'
feat(windows): the outside click and the wings' rules, ported case for case from the Mac

IslandOutsideClick and IslandWing as plain TypeScript with the Mac's test cases, drift pins that read the Swift constants, a driver that
arms one one-shot timer for the left wing's dwell and the return (the cursor event comes only when the pointer moves), the rectangle
Rust should use while folded, and the fade step. Nothing is wired yet.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

---

### Task 2: Rust: the mouse buttons in the poll, `pointer-button`, the shape-changed recompute

**Agent: `nm-implementer-deep` (Sonnet 5.5, high; CLAUDE.md trigger 1: Tauri windowing and click-through: the poll thread, `WS_EX_TRANSPARENT`, Win32).** Loads `superpowers:systematic-debugging` besides the usual skills.

**Files:**
- Create: `windows/src-tauri/src/pointer.rs`, `windows/scripts/cat-tests/u1b-pointer-wiring.test.mjs`
- Modify: `windows/src-tauri/src/island.rs`, `windows/src-tauri/src/lib.rs`, `windows/src-tauri/src/platform/windows.rs`, `windows/src-tauri/src/platform/linux.rs`

**Interfaces:**
- Produces: `pointer::ButtonEdges` (`step(down) -> Option<Edge>`, `sync(down)`), `pointer::Edge::{Press, Release}`; `PollGate.watch_buttons: AtomicBool` (pub), `PollGate::take_rect_dirty() -> bool`; the Tauri command `watch_pointer_buttons(on: bool)`; the event `pointer-button` with payload `{ down: bool, x: f64, y: f64, own: bool }` (window-logical px; `own` only meaningful on a press); `CursorPayload.down: bool` (any mouse button held, sent with each `cursor` event); `platform::pointer_feed() -> bool`, `platform::any_button_down() -> bool`, `platform::press_is_own(app: &AppHandle, x: f64, y: f64) -> bool` (x, y physical px); `BootInfo.cursorPoll` now reports `platform::pointer_feed()`.
- Consumes: the existing `PollGate`, `spawn_cursor_poll`, `platform::CURSOR_POLL` (unchanged: it still means "click-through is the WS_EX_TRANSPARENT toggle", Windows only).

**Design.** The poll thread already wakes every 16 ms while the island is showing. Today it skips the whole tick when the cursor has moved less than 1 px; a click does not move the pointer, so the button read goes **before** that skip. The read happens only while the page has set `watch_buttons` (the island is expanded). The edges become `pointer-button` events; the press carries `own` (is the window under the point one of this app's?). The skip also stops when the island's shape changed (`rect_dirty`), so the wings' click-through flips on the tick the page pushes the folded rectangle. `platform::pointer_feed()` says whether the OS gives a global pointer: Windows always; Linux false for now (Task 5 makes it true under X11). The `set_ignore_cursor_events` toggle stays Windows-only (`CURSOR_POLL`), so a later X11 feed does not fight the input region.

- [ ] **Step 1: The pins, and watch them fail**

**Create `windows/scripts/cat-tests/u1b-pointer-wiring.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the Rust side of the outside click is wired (island.rs, lib.rs, the platform files), pinned as source text. The Windows-only code is compiled by CI (windows-tests.yml), not here.
const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const island = read("src-tauri/src/island.rs"), lib = read("src-tauri/src/lib.rs"), win = read("src-tauri/src/platform/windows.rs"), linux = read("src-tauri/src/platform/linux.rs");

test("the poll reads the buttons on every tick, before the skip for a pointer that has not moved, and only while the page watches", () => {
  const watching = island.indexOf("let watching = gate.watch_buttons.load(Ordering::Relaxed);");
  const step = island.indexOf("buttons.step(platform::any_button_down())");
  const skip = island.indexOf("if !moved && !gate.take_rect_dirty() {");
  assert.ok(watching > 0 && step > watching && skip > step, "the watch flag, then the read, then the skip");
  assert.match(island, /if watching != was_watching \{\s*was_watching = watching;\s*buttons\.sync\(watching && platform::any_button_down\(\)\);/, "switching the watch on adopts a held button without reporting a press");
});

test("a press is checked against the app's own windows, a release is not, and the event carries the window's logical px", () => {
  assert.match(island, /let own = press && platform::press_is_own\(&app, cx, cy\);/);
  assert.match(island, /win\.emit\("pointer-button", ButtonPayload \{ down: press, x, y, own \}\)/);
});

test("a new island shape is applied even when the pointer has not moved, and every set_rect marks it", () => {
  assert.match(island, /pub fn set_rect\(&self, rect: IslandRect\) \{[^}]*self\.rect_dirty\.store\(true, Ordering::Relaxed\);/);
  assert.match(island, /pub fn take_rect_dirty\(&self\) -> bool \{\s*self\.rect_dirty\.swap\(false, Ordering::Relaxed\)/);
});

test("click-through by WS_EX_TRANSPARENT stays with the cursor poll of Windows, and the cursor event says whether a button is down", () => {
  assert.match(island, /if platform::CURSOR_POLL \{\s*if gate\.ignoring\.load\(Ordering::Relaxed\) == accept \{[\s\S]{0,200}set_ignore_cursor_events\(!accept\)/);
  assert.match(island, /CursorPayload \{ x, y, down: platform::any_button_down\(\) \}/);
  assert.match(island, /let \(period, screen_every\) = if platform::pointer_feed\(\) \{ \(16, 30\) \} else \{ \(500, 1\) \};/);
});

test("the page switches the watch with one command, and boot tells it whether the OS gives a pointer", () => {
  assert.match(lib, /fn watch_pointer_buttons\(shared: State<Shared>, on: bool\) \{\s*shared\.gate\.watch_buttons\.store\(on, Ordering::Relaxed\);/);
  assert.match(lib, /set_island_rect,\s*watch_pointer_buttons,\s*focus_window,/);
  assert.match(lib, /cursor_poll: platform::pointer_feed\(\),/);
  assert.match(lib, /^mod pointer;$/m);
});

test("Windows reads the three mouse buttons and asks which window is under the point; Linux has the same three names", () => {
  assert.match(win, /VK_LBUTTON, VK_MBUTTON, VK_RBUTTON/);
  assert.match(win, /WindowFromPoint/);
  assert.match(win, /pub fn pointer_feed\(\) -> bool/);
  assert.match(win, /pub fn any_button_down\(\) -> bool/);
  assert.match(win, /pub fn press_is_own\(_app: &AppHandle, x: f64, y: f64\) -> bool/);
  for (const name of ["pointer_feed", "any_button_down", "press_is_own"]) assert.match(linux, new RegExp(`pub fn ${name}\\(`), `Linux has ${name}`);
});

test("no global mouse hook anywhere: the poll's button reads are the only source", () => {
  const dir = new URL("../../src-tauri/src/", import.meta.url);
  for (const f of fs.readdirSync(dir, { recursive: true })) {
    if (!String(f).endsWith(".rs")) continue;
    const text = fs.readFileSync(new URL(String(f), dir), "utf8");
    assert.doesNotMatch(text, /SetWindowsHookEx|WH_MOUSE_LL|XGrabPointer|XInput2|XISelectEvents/, `${f} installs no global mouse hook`);
  }
});
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/u1b-pointer-wiring.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"`
Expected: FAIL (`fail 6`: everything but the "no global hook" test, which already holds).

- [ ] **Step 2: The pure edge detector**

**Create `windows/src-tauri/src/pointer.rs`:**

```rust
// Mouse button edges for the outside click (island.rs). The poll reads "is any button down" every tick while the island is expanded; this turns two reads into a press or a
// release. Pure, so the Linux container tests it like the rest.

/// One change of the buttons' state between two reads.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Edge {
    Press,
    Release,
}

#[derive(Debug, Default)]
pub struct ButtonEdges {
    down: bool,
}

impl ButtonEdges {
    /// One read: `Some(Press)` when a button has just gone down, `Some(Release)` when the last one has just come up, `None` when nothing changed.
    pub fn step(&mut self, down: bool) -> Option<Edge> {
        let edge = match (self.down, down) {
            (false, true) => Some(Edge::Press),
            (true, false) => Some(Edge::Release),
            _ => None,
        };
        self.down = down;
        edge
    }

    /// Adopts the current state without reporting an edge: the watch has just been switched on, and a button already held then was pressed before it (its release is not a click).
    pub fn sync(&mut self, down: bool) {
        self.down = down;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_press_and_a_release_are_each_reported_once() {
        let mut e = ButtonEdges::default();
        assert_eq!(e.step(false), None);
        assert_eq!(e.step(true), Some(Edge::Press));
        assert_eq!(e.step(true), None, "held: no new edge");
        assert_eq!(e.step(true), None);
        assert_eq!(e.step(false), Some(Edge::Release));
        assert_eq!(e.step(false), None);
    }

    #[test]
    fn a_button_already_down_when_the_watch_starts_is_not_a_press() {
        let mut e = ButtonEdges::default();
        e.sync(true);
        assert_eq!(e.step(true), None);
        assert_eq!(e.step(false), Some(Edge::Release), "its release still comes, and the page ignores a release it saw no press for");
    }

    #[test]
    fn two_quick_clicks_between_reads_are_one_edge_pair_per_read() {
        let mut e = ButtonEdges::default();
        let seen: Vec<_> = [true, false, true, false].iter().filter_map(|d| e.step(*d)).collect();
        assert_eq!(seen, vec![Edge::Press, Edge::Release, Edge::Press, Edge::Release]);
    }
}
```

- [ ] **Step 3: The poll (`island.rs`)**

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
use crate::platform::{self, cursor_physical, left_button_down};
```

replace with

```rust
use crate::platform::{self, cursor_physical, left_button_down};
use crate::pointer::{ButtonEdges, Edge};
```

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
#[derive(Serialize, Clone)]
pub struct CursorPayload {
    pub x: f64,
    pub y: f64,
}
```

replace with

```rust
#[derive(Serialize, Clone)]
pub struct CursorPayload {
    pub x: f64,
    pub y: f64,
    /// Any mouse button is held (the wing's left-side dwell does not start, or starts over, while one is).
    pub down: bool,
}

/// A mouse button went down or came up while the page watches (the outside click). `x`, `y` are window-logical px like the cursor event; `own` (meaningful on a press) says the
/// window under the point belongs to this app (Settings, the desktop cat, the tray's menu): a click there is not outside the island.
#[derive(Serialize, Clone)]
pub struct ButtonPayload {
    pub down: bool,
    pub x: f64,
    pub y: f64,
    pub own: bool,
}
```

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
    /// Mirrors the window flag so we only call into the OS when it changes.
    ignoring: AtomicBool,
}
```

replace with

```rust
    /// Mirrors the window flag so we only call into the OS when it changes.
    ignoring: AtomicBool,
    /// The page sets this while the island is expanded: the poll then reads the mouse buttons on every tick and sends `pointer-button` for each edge (the outside click).
    pub watch_buttons: AtomicBool,
    /// The island's shape changed since the poll last looked: the click-through decision is made again even though the pointer has not moved (the wings folding).
    rect_dirty: AtomicBool,
}
```

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
            ignoring: AtomicBool::new(false),
        }
    }

    pub fn set_rect(&self, rect: IslandRect) {
        *self.rect.lock().unwrap() = rect;
    }
```

replace with

```rust
            ignoring: AtomicBool::new(false),
            watch_buttons: AtomicBool::new(false),
            rect_dirty: AtomicBool::new(false),
        }
    }

    pub fn set_rect(&self, rect: IslandRect) {
        *self.rect.lock().unwrap() = rect;
        self.rect_dirty.store(true, Ordering::Relaxed);
    }

    /// True once after each `set_rect`.
    pub fn take_rect_dirty(&self) -> bool {
        self.rect_dirty.swap(false, Ordering::Relaxed)
    }
```

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
        let mut was_down = false;
```

replace with

```rust
        let mut was_down = false;
        // The outside click: edges of the mouse buttons, read only while the page watches.
        let mut buttons = ButtonEdges::default();
        let mut was_watching = false;
```

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
        let (period, screen_every) = if platform::CURSOR_POLL { (16, 30) } else { (500, 1) };
```

replace with

```rust
        let (period, screen_every) = if platform::pointer_feed() { (16, 30) } else { (500, 1) };
```

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
                if (x - last.0).abs() < 1.0 && (y - last.1).abs() < 1.0 {
                    continue;
                }
                last = (x, y);
```

replace with

```rust
                // The outside click: while the page watches (the island is expanded) the buttons are read on EVERY tick, moved or not, because a click does not move the pointer.
                // A button already held when the watch starts is adopted without an edge, so its release is not taken for a click.
                let watching = gate.watch_buttons.load(Ordering::Relaxed);
                if watching != was_watching {
                    was_watching = watching;
                    buttons.sync(watching && platform::any_button_down());
                } else if watching {
                    if let Some(edge) = buttons.step(platform::any_button_down()) {
                        let press = edge == Edge::Press;
                        let own = press && platform::press_is_own(&app, cx, cy);
                        let _ = win.emit("pointer-button", ButtonPayload { down: press, x, y, own });
                    }
                }
                let moved = !((x - last.0).abs() < 1.0 && (y - last.1).abs() < 1.0);
                // A new island shape (the wings folding) is applied even when the pointer has not moved.
                if !moved && !gate.take_rect_dirty() {
                    continue;
                }
                last = (x, y);
```

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
                let accept = on_island || dragging;
                if gate.ignoring.load(Ordering::Relaxed) == accept {
                    gate.ignoring.store(!accept, Ordering::Relaxed);
                    let _ = win.set_ignore_cursor_events(!accept);
                }

                let _ = win.emit("cursor", CursorPayload { x, y });
```

replace with

```rust
                let accept = on_island || dragging;
                // Click-through by WS_EX_TRANSPARENT is the Windows poll's job. Where the pointer is read without it (Linux under X11, platform::pointer_feed) the input region stays the click-through.
                if platform::CURSOR_POLL {
                    if gate.ignoring.load(Ordering::Relaxed) == accept {
                        gate.ignoring.store(!accept, Ordering::Relaxed);
                        let _ = win.set_ignore_cursor_events(!accept);
                    }
                }

                let _ = win.emit("cursor", CursorPayload { x, y, down: platform::any_button_down() });
```

- [ ] **Step 4: The command and the module (`lib.rs`)**

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
mod platform;
mod secrets;
```

replace with

```rust
mod platform;
mod pointer;
mod secrets;
```

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
        cursor_poll: platform::CURSOR_POLL,
```

replace with

```rust
        cursor_poll: platform::pointer_feed(),
```

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
#[tauri::command]
fn focus_window(app: AppHandle, focused: bool) {
```

replace with

```rust
/// The outside click: the page turns the reading of the mouse buttons on while the island is expanded and off otherwise (island.rs, `pointer-button`). Off, the poll reads nothing extra.
#[tauri::command]
fn watch_pointer_buttons(shared: State<Shared>, on: bool) {
    shared.gate.watch_buttons.store(on, Ordering::Relaxed);
}

#[tauri::command]
fn focus_window(app: AppHandle, focused: bool) {
```

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
            set_island_rect,
            focus_window,
```

replace with

```rust
            set_island_rect,
            watch_pointer_buttons,
            focus_window,
```

- [ ] **Step 5: The platform seams**

**Edit `windows/src-tauri/src/platform/windows.rs`:** find

```rust
use ::windows::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON};
```

replace with

```rust
use ::windows::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON, VK_MBUTTON, VK_RBUTTON};
```

**Edit `windows/src-tauri/src/platform/windows.rs`:** find

```rust
use ::windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, GetClassNameW, GetCursorPos, GetForegroundWindow, GetWindowLongPtrW, GetWindowRect, GetWindowThreadProcessId, SetWindowLongPtrW,
    GWL_EXSTYLE, GWL_STYLE, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};
```

replace with

```rust
use ::windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, GetClassNameW, GetCursorPos, GetForegroundWindow, GetWindowLongPtrW, GetWindowRect, GetWindowThreadProcessId, SetWindowLongPtrW, WindowFromPoint,
    GWL_EXSTYLE, GWL_STYLE, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};
```

**Edit `windows/src-tauri/src/platform/windows.rs`:** find

```rust
pub fn left_button_down() -> bool {
    unsafe { (GetAsyncKeyState(VK_LBUTTON.0 as i32) as u16 & 0x8000) != 0 }
}
```

replace with

```rust
pub fn left_button_down() -> bool {
    unsafe { (GetAsyncKeyState(VK_LBUTTON.0 as i32) as u16 & 0x8000) != 0 }
}

/// The OS gives this app the pointer anywhere on screen (the island's poll reads it).
pub fn pointer_feed() -> bool {
    true
}

/// True while any mouse button is held. All three are watched, so swapped buttons (Settings → Mouse) make no difference.
pub fn any_button_down() -> bool {
    [VK_LBUTTON, VK_RBUTTON, VK_MBUTTON].iter().any(|k| unsafe { (GetAsyncKeyState(k.0 as i32) as u16 & 0x8000) != 0 })
}

/// Whether the window under the point (physical screen px) belongs to this app: the island, Settings, the desktop cat, the tray's menu. A click there is not outside the island.
pub fn press_is_own(_app: &AppHandle, x: f64, y: f64) -> bool {
    unsafe {
        let hwnd = WindowFromPoint(POINT { x: x.round() as i32, y: y.round() as i32 });
        if hwnd.0.is_null() {
            return false;
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid as *mut u32));
        pid == std::process::id()
    }
}
```

**Edit `windows/src-tauri/src/platform/linux.rs`:** find

```rust
pub fn left_button_down() -> bool {
    false
}
```

replace with

```rust
pub fn left_button_down() -> bool {
    false
}

/// Wayland gives an app no global pointer. (Task 5 of U1b turns this on under X11.)
pub fn pointer_feed() -> bool {
    false
}

pub fn any_button_down() -> bool {
    false
}

pub fn press_is_own(_app: &AppHandle, _x: f64, _y: f64) -> bool {
    false
}
```

- [ ] **Step 6: Run the Rust tests and the pins**

```bash
windows/scripts/cargo-linux.sh test -p notchmeow --offline --target-dir /repo/windows/target/u1b -- pointer:: island:: 2>&1 | grep -E "^test |^test result|^error|warning: unused" | head -20
cd windows && node --experimental-strip-types --test scripts/cat-tests/u1b-pointer-wiring.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"; cd ..
```

Expected: the three `pointer::tests::` and the three `island::zoom_tests::` tests `ok`, `test result: ok`, no `error`, no new `unused` warning from `island.rs` (on Linux `accept` and `dragging` are still read inside the `if platform::CURSOR_POLL` block); the pins `pass 7`, `fail 0`. If Docker is down: "needs Docker" for the cargo line, the pins still run. **Say in the ledger that `platform/windows.rs` was not compiled here** (CI compiles it).

- [ ] **Step 7: Bite: the read really is before the skip**

Back `island.rs` up into a folder you made with `mktemp -d`. Swap the order by hand: move the `let moved = ...` and the `if !moved && !gate.take_rect_dirty() { continue; }` lines above the `let watching = ...` line. Run the pins: the first test must fail ("the watch flag, then the read, then the skip"). Copy the backup back; run the pins again: PASS.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/src-tauri/src/pointer.rs windows/src-tauri/src/island.rs windows/src-tauri/src/lib.rs windows/src-tauri/src/platform/windows.rs windows/src-tauri/src/platform/linux.rs windows/scripts/cat-tests/u1b-pointer-wiring.test.mjs
git commit -F - <<'MSG'
feat(windows): the poll reads the mouse buttons while the island is open, and re-decides click-through when its shape changes

For the outside click and the wings, with no hook and no new poll: while the page says the island is expanded, the cursor poll that already
runs reads the three buttons on every tick (before the skip for a pointer that has not moved) and sends pointer-button for each edge, a
press with whether the window under it is the app's own. set_island_rect marks the shape changed, so click-through is decided again on the next
tick even if the pointer is still. Windows-only code is compiled by CI.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
```

---

### Task 3: The outside click in the island page

**Agent: `nm-implementer` (Haiku 5.5, high).** Every edit's find text is given; if one does not occur exactly once, stop and report.

**Files:**
- Modify: `windows/src/core/bridge.ts`, `windows/src/main.ts`, `windows/src/island/island.ts`
- Create: `windows/scripts/cat-tests/u1b-outside-wiring.test.mjs`

**Interfaces:**
- Consumes (Task 1): `OutsideClick`, `ButtonEvent`, `OutsideContext`. (Task 2): the event `pointer-button` (`{ down, x, y, own }`), the command `watch_pointer_buttons(on)`.
- Produces: `Bridge.watchPointerButtons(on: boolean)`; `Island.onPointerButton(e: ButtonEvent)` (public: the dev server's pictures call it); `Island.outsideContext(e)` (private).

**Design.** The Mac installs one global monitor while the island is expanded and removes it otherwise; here the same lifetime is one boolean sent to Rust by `setMode` (and by `setCursorPoll`, because the boot answer arrives after the first mode): `cursorPoll && mode === "expanded"`. Where the OS has no global pointer (`cursorPoll` false) it is never sent. The Mac's six facts become the PC's: `pinned` = `State.isPinned` (an approval or a chat card pins it), `held` = `fsm.pinned` (a waiting card, the shelf's drag-out and Send hold) or a native menu, `typing` = the chat is showing and a text field has the keyboard (`document.hasFocus()`: the island takes focus only for the chat), `pointerInIsland` = the press is over the island with its hit margin or over another window of this app (`e.own`), `busy` = the big cat is being dragged out (`PressDrag`), a shelf tile is dragged out, a file is dragged in or the drop view is up. The Mac's `wasInIsland` is replaced by the press's own point, so a click an instant after the pointer entered is not mistaken. The fold is `collapse()`: the same as Escape.

- [ ] **Step 1: The pins, and watch them fail**

**Create `windows/scripts/cat-tests/u1b-outside-wiring.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the island page calls the outside click's rules (island.ts, main.ts, bridge.ts), pinned as source text.
const read = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const island = read("island/island.ts"), main = read("main.ts"), bridge = read("core/bridge.ts"), rules = read("island/outsideclick.ts");

test("the glue is built once and folds with collapse(), the same fold as Escape", () => {
  assert.match(island, /private outside = new OutsideClick\(\(e\) => this\.outsideContext\(e\), \(\) => this\.collapse\(\)\);/);
  assert.match(island, /onPointerButton\(e: ButtonEvent\) \{\s*this\.outside\.onButton\(e\);/);
});

test("the OS is asked to read the buttons only while the island is expanded and the OS has a global pointer", () => {
  assert.match(island, /const on = this\.cursorPoll && State\.mode === "expanded";/);
  assert.match(island, /State\.mode = mode;\s*this\.syncGlow\(\);\s*this\.syncPointerWatch\(\);/, "setMode follows the mode");
  assert.match(island, /setCursorPoll\(on: boolean\) \{\s*this\.cursorPoll = on;\s*this\.syncPointerWatch\(\);/, "and so does the boot answer");
  assert.equal((island.match(/Bridge\.watchPointerButtons\(/g) ?? []).length, 1, "one call site");
  assert.match(bridge, /watchPointerButtons: \(on: boolean\) => call<void>\("watch_pointer_buttons", \{ on \}\)/);
  assert.match(bridge, /\{ name: "pointer-button"; payload: \{ down: boolean; x: number; y: number; own: boolean \} \}/);
  assert.match(main, /onEvent<ButtonEvent>\("pointer-button", \(e\) => island\.onPointerButton\(e\)\)/);
});

test("the reasons to stay are the Mac's list, in the PC's own facts", () => {
  assert.match(island, /expanded: State\.mode === "expanded",/);
  assert.match(island, /pinned: State\.isPinned,/);
  assert.match(island, /held: this\.fsm\.pinned \|\| this\.fsm\.menuOpen,/);
  assert.match(island, /typing: State\.view === "prompt" && document\.hasFocus\(\) && \(field instanceof HTMLTextAreaElement \|\| field instanceof HTMLInputElement\),/);
  assert.match(island, /pointerInIsland: e\.own \|\| this\.hitRectContains\(e\.x, e\.y\),/);
  assert.match(island, /busy: this\.press\.active \|\| this\.dragOut\.active \|\| State\.fileDragOver \|\| this\.uploadActive,/);
});

test("it costs nothing of its own: no timer, no listener, no frame in the rules, and no new interval or frame loop in the island", () => {
  assert.doesNotMatch(rules, /setTimeout|setInterval|addEventListener|requestAnimationFrame|performance\.now/);
  assert.equal((island.match(/setInterval/g) ?? []).length, 0);
  assert.equal((island.match(/requestAnimationFrame/g) ?? []).length, 2, "the island's two existing frame requests, no more");
});
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/u1b-outside-wiring.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"`
Expected: FAIL (`fail 4`).

- [ ] **Step 2: The bridge**

**Edit `windows/src/core/bridge.ts`:** find

```ts
  | { name: "cursor"; payload: { x: number; y: number } }
```

replace with

```ts
  | { name: "cursor"; payload: { x: number; y: number; down?: boolean } }
  | { name: "pointer-button"; payload: { down: boolean; x: number; y: number; own: boolean } }
```

**Edit `windows/src/core/bridge.ts`:** find

```ts
  setIslandRect: (x: number, y: number, width: number, height: number) =>
    call<void>("set_island_rect", { x, y, width, height }),
```

replace with

```ts
  setIslandRect: (x: number, y: number, width: number, height: number) =>
    call<void>("set_island_rect", { x, y, width, height }),

  /** The outside click: Rust reads the mouse buttons on every poll tick and sends `pointer-button` for each edge, only while this is on (the island is expanded). */
  watchPointerButtons: (on: boolean) => call<void>("watch_pointer_buttons", { on }),
```

- [ ] **Step 3: The event**

**Edit `windows/src/main.ts`:** find

```ts
import { Island } from "./island/island";
```

replace with

```ts
import { Island } from "./island/island";
import type { ButtonEvent } from "./island/outsideclick.ts";
```

**Edit `windows/src/main.ts`:** find

```ts
  await onEvent<{ x: number; y: number }>("cursor", ({ x, y }) => island.onCursor(x, y));
```

replace with

```ts
  await onEvent<{ x: number; y: number }>("cursor", ({ x, y }) => island.onCursor(x, y));
  // The outside click (island/outsideclick.ts): a mouse button went down or came up while the island is expanded.
  await onEvent<ButtonEvent>("pointer-button", (e) => island.onPointerButton(e));
```

- [ ] **Step 4: The island**

**Edit `windows/src/island/island.ts`:** find

```ts
import { IslandStateMachine } from "./fsm";
```

replace with

```ts
import { IslandStateMachine } from "./fsm";
import { OutsideClick, type ButtonEvent, type OutsideContext } from "./outsideclick.ts";
```

**Edit `windows/src/island/island.ts`:** find

```ts
  private dragOut = new DragOutGuard();
```

replace with

```ts
  private dragOut = new DragOutGuard();
  /** A click outside the open island folds it (island/outsideclick.ts). Fed the button edges Rust sends while `watchingButtons`; the fold is the same as Escape's. */
  private outside = new OutsideClick((e) => this.outsideContext(e), () => this.collapse());
  /** Rust has been asked to read the mouse buttons (the island is expanded and the OS has a global pointer). */
  private watchingButtons = false;
```

**Edit `windows/src/island/island.ts`:** find

```ts
    State.mode = mode;
    this.syncGlow();
    if (mode !== "hidden") Hub.sk?.islandOpened();
```

replace with

```ts
    State.mode = mode;
    this.syncGlow();
    this.syncPointerWatch();
    if (mode !== "hidden") Hub.sk?.islandOpened();
```

**Edit `windows/src/island/island.ts`:** find

```ts
  /** The pointer is over the island (the Sidekick does not swap a nicer sentence in under it). */
  get pointerInside(): boolean {
```

replace with

```ts
  /** Rust reads the mouse buttons on every poll tick only while this is on: the island is expanded and the OS has a global pointer (the outside click). Nothing runs on the page for it. */
  private syncPointerWatch() {
    const on = this.cursorPoll && State.mode === "expanded";
    if (on === this.watchingButtons) return;
    this.watchingButtons = on;
    if (!on) this.outside.reset();
    void Bridge.watchPointerButtons(on);
  }

  /** A mouse button went down or came up (Rust `pointer-button`): the outside click's input. */
  onPointerButton(e: ButtonEvent) {
    this.outside.onButton(e);
  }

  /** What is true when a button goes down, for the outside click's rule (the Mac's counterpart is IslandWindowController.handleOutsideClick). */
  private outsideContext(e: ButtonEvent): OutsideContext {
    const field = document.activeElement;
    return {
      expanded: State.mode === "expanded",
      pinned: State.isPinned,
      held: this.fsm.pinned || this.fsm.menuOpen,
      typing: State.view === "prompt" && document.hasFocus() && (field instanceof HTMLTextAreaElement || field instanceof HTMLInputElement),
      pointerInIsland: e.own || this.hitRectContains(e.x, e.y),
      busy: this.press.active || this.dragOut.active || State.fileDragOver || this.uploadActive,
    };
  }

  /** The pointer is over the island (the Sidekick does not swap a nicer sentence in under it). */
  get pointerInside(): boolean {
```

**Edit `windows/src/island/island.ts`:** find

```ts
  setCursorPoll(on: boolean) {
    this.cursorPoll = on;
  }
```

replace with

```ts
  setCursorPoll(on: boolean) {
    this.cursorPoll = on;
    this.syncPointerWatch();
  }
```

- [ ] **Step 5: Run**

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/u1b-outside-wiring.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"
npx --no-install tsc --noEmit && echo "tsc ok"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: pins `pass 4`, `fail 0`; `tsc ok`; `check:cat` `fail 0` (the baseline of Task 0 plus Task 1's 22 and these 4).

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/src/core/bridge.ts windows/src/main.ts windows/src/island/island.ts windows/scripts/cat-tests/u1b-outside-wiring.test.mjs
git commit -F - <<'MSG'
feat(windows): a click outside the open island folds it

Except when it is pinned, something holds it (a waiting card, the shelf's drag-out or Send, a native menu), the user is typing in the chat,
the press is on the island or on another window of the app, or a cat or file drag is under way. The island asks Rust to read the mouse buttons only while
it is expanded and the OS has a global pointer; the rules are the Mac's, ported in Task 1. Wayland sessions are untouched (no pointer, no watch).

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

---

### Task 4: The wings step aside in the island page, and Open on hover's wing hold

**Agent: `nm-implementer-deep` (Sonnet 5.5, high; CLAUDE.md trigger 1: a spring-driven frame, click-through at the full zones, and a poll that gives no tick).** Loads `superpowers:systematic-debugging` besides the usual skills.

**Files:**
- Modify: `windows/src/island/fsm.ts`, `windows/src/island/island.ts`, `windows/src/island/desktop.ts`, `windows/src/main.ts`, `windows/src/style.css`
- Create: `windows/scripts/cat-tests/fsm-wing.test.mjs`, `windows/scripts/cat-tests/u1b-wing-wiring.test.mjs`

**Interfaces:**
- Consumes (Task 1): `wings`, `zoneOf`, `widthAt`, `foldedHitRect`, `stepFade`, `isActive`, `SPRING_RESPONSE`, `SPRING_DAMPING`, `WingDriver`, `WingOut`. (Task 2): the `cursor` event's `down`; `set_island_rect` re-decides click-through even when the pointer is still. (Task 3): the `private outside` line it edits around.
- Produces: `IslandStateMachine.pointerOnWing: boolean` and `IslandStateMachine.hoverResume()`; `Island.onCursor(x, y, down?)`; `DesktopBrain.awayFromHome`.

**Design (what the Mac does, in the PC's pieces).**

- *Geometry.* `wings(islandRect(), NOTCH_W, HIT_MARGIN)`: for the 288 px compact island that is 66 px on each side (52 + the 14 px hit margin outward), the 184 px middle is the hover zone. `islandRect()` is the island at rest (the width `Tracked`, which the swoosh never touches), so the zones stay put while the drawn island shrinks.
- *The swoosh.* A second `Tracked` (`swoosh`, 0 at rest, 1 folded) sprung with the Mac's numbers; the drawn width is `widthAt(full, NOTCH_W, swoosh)`, only in the compact mode (any other mode puts it back at once). The cats, the grid and the badge fade through a CSS variable the stylesheet multiplies in with `filter: opacity()`, so the opacities the page sets inline are not fought and a resting island has no filter at all.
- *Click-through.* The page tells Rust the island's rectangle (`setIslandRect`). Folded, that rectangle is `foldedHitRect` (the middle, narrower by the hit margin on each side, because Rust adds the margin back), so the wings pass the mouse on from the tick the fold starts and no dead band is left; otherwise it is the island at rest, so the unfold takes the mouse back at once. Rust recomputes on the next tick even if the pointer is still (Task 2).
- *The ticks.* The cursor event feeds the rules; `syncDom` feeds them again (an alert arriving with the pointer parked); a mouse button changing feeds them (a press during the dwell); and the driver's one-shot timer feeds them when the dwell or the return ends. When the driver's answer changes outside a cursor event, the pointer's enter/leave bookkeeping is run again with the last position (the Mac does it on the same poll tick).
- *Alerts.* `wingActive()`: compact, no greeting tail, no press on the big cat, and none of: a pending approval, `fsm.pinned` (a waiting chat card, the shelf's drag-out and Send hold), `State.isPinned`, a native menu, a file on its way in, a shelf tile dragged out, the desktop cat away from the notch.
- *Open on hover.* `fsm.pointerOnWing` holds the hover-open (the dwell never starts, and a dwell already running does not open); `hoverResume()` arms the dwell again when the pointer comes off a wing into the middle, where there is no enter edge.
- *Wayland.* `feedWing` returns `wing.feed(null, false)` when `cursorPoll` is false: nothing folds and nothing is armed.

- [ ] **Step 1: The tests and the pins, and watch them fail**

**Create `windows/scripts/cat-tests/fsm-wing.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";

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
function machine() { timers.clear(); const f = new IslandStateMachine(); f.openOnHover = true; return f; }

// The wing cases of tests/IslandHoverTests.swift (the Mac): the pointer on a wing is a hover-only hold.
test("the pointer on a wing arms no dwell, with Open on hover on", () => {
  const fsm = machine();
  fsm.pointerOnWing = true;
  fsm.mouseEntered();
  seconds(1);
  assert.equal(fsm.state, "petit", "the usual peek still happens");
  assert.equal(fsm.openedByHover, false);
});

test("a wing reached while the dwell runs cancels the open", () => {
  const fsm = machine();
  fsm.mouseEntered();
  seconds(0.1);
  fsm.pointerOnWing = true;
  seconds(0.1);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
});

test("coming off a wing into the middle arms the dwell again, and the island opens 150 ms later", () => {
  const fsm = machine();
  fsm.pointerOnWing = true;
  fsm.mouseEntered();
  seconds(0.5);
  fsm.pointerOnWing = false;
  fsm.hoverResume();
  seconds(0.149);
  assert.equal(fsm.state, "petit");
  seconds(0.001);
  assert.equal(fsm.state, "home");
  assert.equal(fsm.openedByHover, true);
});

test("hoverResume does nothing with the switch off, a pin, a menu, a wing under the pointer, or an island that is already open", () => {
  for (const edit of [(f) => { f.openOnHover = false; }, (f) => { f.pinned = true; }, (f) => { f.menuOpen = true; }, (f) => { f.pointerOnWing = true; }]) {
    const fsm = machine();
    fsm.pointerOnWing = true;           // no dwell is armed on entry
    fsm.mouseEntered();
    fsm.pointerOnWing = false;
    edit(fsm);
    fsm.hoverResume();
    seconds(0.2);
    assert.equal(fsm.state, "petit");
  }
  const open = machine();
  open.forceHome();
  open.hoverResume();
  seconds(0.2);
  assert.equal(open.openedByHover, false, "an open island has nothing to resume");
});

test("with the switch off the pointer on a wing changes nothing", () => {
  const fsm = machine();
  fsm.openOnHover = false;
  fsm.pointerOnWing = true;
  fsm.mouseEntered();
  seconds(5);
  assert.equal(fsm.state, "petit");
});
```

**Create `windows/scripts/cat-tests/u1b-wing-wiring.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the island page calls the wing's rules (island.ts, fsm.ts, style.css, desktop.ts), pinned as source text.
const read = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const island = read("island/island.ts"), fsm = read("island/fsm.ts"), css = read("style.css"), desktop = read("island/desktop.ts"), main = read("main.ts"), driver = read("island/wingdriver.ts"), rules = read("island/wing.ts");

test("the pointer feeds the rules from the cursor event, and only where the OS gives a global pointer", () => {
  assert.match(island, /if \(!this\.cursorPoll\) return this\.wing\.feed\(null, false\);/, "Wayland: the wings stay put");
  assert.match(island, /const zone = active \? this\.wingZone\(x, y\) : null;\s*this\.fsm\.pointerOnWing = zone !== null;\s*return this\.wing\.feed\(zone, active\);/);
  assert.match(island, /const wing = this\.feedWing\(x, y\);\s*const inIsland = this\.hitRectContains\(x, y\) && !wing\.passThrough;/, "the pointer on a folded wing is not on the island");
  assert.match(island, /return zoneOf\(wings\(this\.islandRect\(\), NOTCH_W, HIT_MARGIN\), x, y\);/, "the zones are the full island's, never the shrunk one");
  assert.match(main, /onEvent<\{ x: number; y: number; down\?: boolean \}>\("cursor", \(\{ x, y, down \}\) => island\.onCursor\(x, y, down\)\)/);
});

test("the alert list: everything that wants the island cancels the step-aside", () => {
  const m = /private wingActive\(\): boolean \{([\s\S]*?)\n  \}/.exec(island);
  assert.ok(m, "wingActive exists");
  for (const need of ["State.pendingApproval !== null", "this.fsm.pinned", "State.isPinned", "this.fsm.menuOpen", "State.fileCatch()", "this.dragOut.active", "this.desktop?.awayFromHome", "State.desktopNotchEmpty",
    'State.mode === "compact"', "this.greetingShown()", "this.press.active"]) assert.ok(m[1].includes(need), `wingActive looks at ${need}`);
  assert.match(desktop, /get awayFromHome\(\): boolean \{ return this\.trip\.phase !== "home"; \}/);
});

test("the swoosh, the fade and click-through follow the rules", () => {
  assert.match(island, /private swoosh = new Tracked\(0\);/);
  assert.match(island, /this\.swoosh\.springTo\(now\.faded \? 1 : 0, SPRING_RESPONSE, SPRING_DAMPING\);/);
  assert.match(island, /const w = swoosh === 0 \? full : widthAt\(full, NOTCH_W, swoosh\);/);
  assert.match(island, /this\.wing\.state\.faded && State\.mode === "compact" \? foldedHitRect\(viewportWidth\(\), hh, NOTCH_W, HIT_MARGIN\) : \{ x: \(viewportWidth\(\) - full\) \/ 2, y: 0, w: full, h: hh \}/);
  assert.match(island, /this\.swoosh\.animating \|\| this\.wingFade !== \(this\.wing\.state\.faded \? 0 : 1\)/, "the frame loop runs while the swoosh or the fade moves, and stops after");
  assert.match(island, /this\.islandEl\.style\.setProperty\("--nm-wing", String\(this\.wingFade\)\);/);
});

test("Open on hover: the pointer on a wing holds the dwell, and coming off a wing into the middle arms it again", () => {
  assert.match(fsm, /pointerOnWing = false;/);
  assert.match(fsm, /\|\| this\.pinned \|\| this\.menuOpen \|\| this\.pointerOnWing\) return;/);
  assert.match(fsm, /hoverResume\(\) \{/);
  assert.match(island, /if \(inIsland && this\.wasInIsland && wasOnWing && !this\.fsm\.pointerOnWing\) this\.fsm\.hoverResume\(\);/);
});

test("the style: opacity by filter, only while the fade is not at rest, and no transition of its own on the cats", () => {
  const start = css.indexOf("The wings step aside");
  assert.ok(start > 0, "the wing block exists");
  const block = css.slice(start, css.indexOf("}", css.indexOf("#island.wing-on #bot-glow", start)) + 1);
  assert.match(block, /#island\.wing-on #bot-canvas,[\s\S]*#island\.wing-on #shelf-badge \{\s*filter: opacity\(var\(--nm-wing, 1\)\);/);
  assert.match(block, /#island\.wing-on #bot-glow \{\s*filter: blur\(6px\) opacity\(var\(--nm-wing, 1\)\);/);
  assert.doesNotMatch(block, /transition/, "no transition is added to a canvas that other code hides");
});

test("it costs nothing of its own: one one-shot timer through the driver, no interval, no new frame loop", () => {
  assert.equal((island.match(/setInterval/g) ?? []).length, 0);
  assert.equal((island.match(/requestAnimationFrame/g) ?? []).length, 2);
  assert.doesNotMatch(rules, /setTimeout|setInterval|addEventListener|requestAnimationFrame/);
  assert.doesNotMatch(driver, /setInterval|requestAnimationFrame|addEventListener/);
  assert.match(driver, /this\.timer = this\.env\.set\(/);
});
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/fsm-wing.test.mjs scripts/cat-tests/u1b-wing-wiring.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"`
Expected: FAIL (the wiring and the FSM property are not there).

- [ ] **Step 2: The state machine**

**Edit `windows/src/island/fsm.ts`:** find

```ts
  /** A native menu of the island is open (the pointer is on it, outside the island): nothing folds while it is up. */
  menuOpen = false;
```

replace with

```ts
  /** A native menu of the island is open (the pointer is on it, outside the island): nothing folds while it is up. */
  menuOpen = false;
  /** The pointer is over a wing of the compact island (island/wing.ts): a hover-only hold, so Open on hover never opens the island from a wing. The click, the love emote and the cat's wake are untouched. */
  pointerOnWing = false;
```

**Edit `windows/src/island/fsm.ts`:** find

```ts
    // Open on hover: the island opens once the pointer has stayed `hoverDwell`. Not while an alert pins it, nor under an open native menu.
    if (this.openOnHover && (this.state === "hidden" || this.state === "petit") && !this.pinned && !this.menuOpen) this.scheduleHoverOpen();
  }
```

replace with

```ts
    this.hoverResume();
  }

  /**
   * Open on hover: the island opens once the pointer has stayed `hoverDwell`. Not while an alert pins it, nor under an open native menu, nor from a wing. Also called when the pointer comes
   * off a wing into the middle while still over the island: there is no enter edge then, so the dwell is armed again here (it clears and re-arms its one one-shot timer).
   */
  hoverResume() {
    if (this.openOnHover && (this.state === "hidden" || this.state === "petit") && !this.pinned && !this.menuOpen && !this.pointerOnWing) this.scheduleHoverOpen();
  }
```

**Edit `windows/src/island/fsm.ts`:** find

```ts
      if ((this.state !== "hidden" && this.state !== "petit") || this.pinned || this.menuOpen) return;
```

replace with

```ts
      if ((this.state !== "hidden" && this.state !== "petit") || this.pinned || this.menuOpen || this.pointerOnWing) return;
```

- [ ] **Step 3: The desktop cat's phase (an alert for the wings)**

**Edit `windows/src/island/desktop.ts`:** find

```ts
  get canCarry(): boolean { return this.trip.phase === "home"; }
```

replace with

```ts
  get canCarry(): boolean { return this.trip.phase === "home"; }

  /** The cat is out, or flying to or from the notch: an alert to the compact island's wings (island/wing.ts), as the Mac's `desktopPhase != .home`. */
  get awayFromHome(): boolean { return this.trip.phase !== "home"; }
```

- [ ] **Step 4: The cursor event carries the button**

**Edit `windows/src/main.ts`:** find

```ts
  await onEvent<{ x: number; y: number }>("cursor", ({ x, y }) => island.onCursor(x, y));
```

replace with

```ts
  await onEvent<{ x: number; y: number; down?: boolean }>("cursor", ({ x, y, down }) => island.onCursor(x, y, down));
```

- [ ] **Step 5: The island: imports and fields**

**Edit `windows/src/island/island.ts`:** find

```ts
import { OutsideClick, type ButtonEvent, type OutsideContext } from "./outsideclick.ts";
```

replace with

```ts
import { OutsideClick, type ButtonEvent, type OutsideContext } from "./outsideclick.ts";
import { SPRING_DAMPING, SPRING_RESPONSE, foldedHitRect, isActive as wingIsActive, stepFade, widthAt, wings, zoneOf, type WingOut, type Zone as WingZone } from "./wing.ts";
import { WingDriver } from "./wingdriver.ts";
```

**Edit `windows/src/island/island.ts`:** find

```ts
  private outside = new OutsideClick((e) => this.outsideContext(e), () => this.collapse());
```

replace with

```ts
  private outside = new OutsideClick((e) => this.outsideContext(e), () => this.collapse());
  /** The compact island's wings step aside (island/wing.ts): the rules' memory plus its one one-shot wake-up. The swoosh is 0 at rest and 1 folded into the notch-wide middle, moved by a spring. */
  private swoosh = new Tracked(0);
  private wingFade = 1;
  private wing = new WingDriver(
    { now: () => performance.now() / 1000, set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id) },
    () => this.mouseButtonDown,
    (now) => this.onWingChange(now),
  );
  /** A mouse button is held, as far as the page can tell: its own mouse events while the window takes the mouse, the cursor event's `down` otherwise. */
  private mouseButtonDown = false;
  /** `onCursor` is running: a change of the wing's answer inside it is handled by the code that follows. */
  private inCursor = false;
```

- [ ] **Step 6: The island: geometry and the frame**

**Edit `windows/src/island/island.ts`:** find

```ts
  private applyGeometry() {
    const w = this.width.value;
    const hh = this.height.value;
    const r = this.radius.value;
```

replace with

```ts
  private applyGeometry() {
    // The wings (island/wing.ts): `full` is the island as it would be at rest, `w` what is drawn, narrowed towards the notch-wide middle by the swoosh. The hover zones and the pointer keep using `full`.
    const full = this.width.value;
    const swoosh = State.mode === "compact" ? this.swoosh.value : 0;
    const w = swoosh === 0 ? full : widthAt(full, NOTCH_W, swoosh);
    const hh = this.height.value;
    const r = this.radius.value;
```

**Edit `windows/src/island/island.ts`:** find

```ts
    const rect = { x: (viewportWidth() - w) / 2, y: 0, w, h: hh };
    const p = this.pushedRect;
```

replace with

```ts
    // Click-through follows the pointer's zone, not the drawn width: folded, only the notch-wide middle takes the mouse (from the tick the fold starts), otherwise the island as it would be at rest.
    const rect = this.wing.state.faded && State.mode === "compact" ? foldedHitRect(viewportWidth(), hh, NOTCH_W, HIT_MARGIN) : { x: (viewportWidth() - full) / 2, y: 0, w: full, h: hh };
    // The cats, the grid and the badge fade with the fold: a CSS variable the stylesheet multiplies into their opacity (style.css "The wings step aside").
    this.islandEl.classList.toggle("wing-on", State.mode === "compact" && this.wingFade < 1);
    this.islandEl.style.setProperty("--nm-wing", String(this.wingFade));
    const p = this.pushedRect;
```

**Edit `windows/src/island/island.ts`:** find

```ts
    this.radius.step(dt, nowMs);
    this.applyGeometry();
```

replace with

```ts
    this.radius.step(dt, nowMs);
    this.stepWing(dt, nowMs);
    this.applyGeometry();
```

**Edit `windows/src/island/island.ts`:** find

```ts
    const settling =
      this.width.animating || this.height.animating || this.radius.animating;
```

replace with

```ts
    const settling =
      this.width.animating || this.height.animating || this.radius.animating || this.swoosh.animating || this.wingFade !== (this.wing.state.faded ? 0 : 1);
```

- [ ] **Step 7: The island: the methods**

**Edit `windows/src/island/island.ts`:** find

```ts
  /** The pointer is over the island (the Sidekick does not swap a nicer sentence in under it). */
  get pointerInside(): boolean {
```

replace with

```ts
  // ── The wings step aside (island/wing.ts; the Mac's counterpart is IslandWindowController.pollFrame) ──────────────────────────────

  /** Which wing of the compact island the point (window px) is in, if any. The zones are the island at rest, never the shrunk one. */
  private wingZone(x: number, y: number): WingZone | null {
    return zoneOf(wings(this.islandRect(), NOTCH_W, HIT_MARGIN), x, y);
  }

  /** Whether the island can step aside now: compact, and nothing wants it (the Mac's `wingAlert`). */
  private wingActive(): boolean {
    const alert = State.pendingApproval !== null || this.fsm.pinned || State.isPinned || this.fsm.menuOpen || State.fileCatch() || this.dragOut.active
      || (this.desktop?.awayFromHome ?? false) || State.desktopNotchEmpty;
    return wingIsActive(State.mode === "compact", this.greetingShown(), this.press.active, alert);
  }

  /** Asks the rules with the pointer at (x, y). Where the OS gives no global pointer (Wayland) the wings stay put. */
  private feedWing(x: number, y: number): WingOut {
    if (!this.cursorPoll) return this.wing.feed(null, false);
    const active = this.wingActive();
    const zone = active ? this.wingZone(x, y) : null;
    this.fsm.pointerOnWing = zone !== null;
    return this.wing.feed(zone, active);
  }

  /** The rules look at state the cursor does not carry (an alert arriving, the island leaving the compact mode): ask again with the pointer's last place. */
  private refreshWing() {
    this.feedWing(State.mouse.x, State.mouse.y);
  }

  /** The island folded or came back: spring the swoosh, and, when this did not come from a cursor event, run the pointer's enter and leave again (the Mac does it on the same poll tick). */
  private onWingChange(now: WingOut) {
    this.swoosh.springTo(now.faded ? 1 : 0, SPRING_RESPONSE, SPRING_DAMPING);
    this.ensureRunning();
    State.notify();
    if (!this.inCursor) this.onCursor(State.mouse.x, State.mouse.y);
  }

  /** The swoosh and the cats' fade, a frame at a time. Both belong to the compact island: any other mode puts them back at once. */
  private stepWing(dt: number, nowMs: number) {
    if (State.mode !== "compact") {
      if (this.swoosh.value !== 0 || this.swoosh.animating) this.swoosh.jump(0);
      this.wingFade = 1;
      return;
    }
    this.swoosh.step(dt, nowMs);
    this.wingFade = stepFade(this.wingFade, this.wing.state.faded, dt);
  }

  /** The pointer is over the island (the Sidekick does not swap a nicer sentence in under it). */
  get pointerInside(): boolean {
```

- [ ] **Step 8: The island: the cursor, the buttons, the sync**

**Edit `windows/src/island/island.ts`:** find

```ts
  onCursor(x: number, y: number) {
    State.mouse = { x, y };
```

replace with

```ts
  onCursor(x: number, y: number, down?: boolean) {
    this.inCursor = true;
    if (down !== undefined) this.mouseButtonDown = down;
    State.mouse = { x, y };
```

**Edit `windows/src/island/island.ts`:** find

```ts
    const inIsland = this.hitRectContains(x, y);

    if (inIsland && !this.wasInIsland) {
```

replace with

```ts
    // The wings step aside: over either wing of the compact island the whole island folds into the notch-wide middle, and the pointer there is not on the island.
    const wasOnWing = this.fsm.pointerOnWing;
    const wing = this.feedWing(x, y);
    const inIsland = this.hitRectContains(x, y) && !wing.passThrough;

    if (inIsland && !this.wasInIsland) {
```

**Edit `windows/src/island/island.ts`:** find

```ts
    this.wasInIsland = inIsland;
    this.syncGlow();

    // Bot hover → love
```

replace with

```ts
    // The pointer came off a wing into the middle while still over the island: no enter edge, so Open on hover's dwell is armed again here.
    if (inIsland && this.wasInIsland && wasOnWing && !this.fsm.pointerOnWing) this.fsm.hoverResume();
    this.wasInIsland = inIsland;
    this.syncGlow();
    this.inCursor = false;

    // Bot hover → love
```

**Edit `windows/src/island/island.ts`:** find

```ts
    window.addEventListener("mouseup", (e) => this.carryUp(e.clientX, e.clientY));
```

replace with

```ts
    window.addEventListener("mouseup", (e) => this.carryUp(e.clientX, e.clientY));
    // The left wing's dwell must know whether a mouse button is held (island/wing.ts): a press cancels it, the release starts it over. While the window takes the mouse the page's own events say so.
    const buttons = (e: MouseEvent) => {
      const down = e.buttons !== 0;
      if (down === this.mouseButtonDown) return;
      this.mouseButtonDown = down;
      this.wing.poke();
    };
    window.addEventListener("mousedown", buttons, true);
    window.addEventListener("mouseup", buttons, true);
    window.addEventListener("mousemove", buttons, true);
```

**Edit `windows/src/island/island.ts`:** find

```ts
  private syncDom() {
    const expanded = State.mode === "expanded";
```

replace with

```ts
  private syncDom() {
    this.refreshWing();
    const expanded = State.mode === "expanded";
```

- [ ] **Step 9: The style**

**Edit `windows/src/style.css`:** find

```css
#shelf-badge:hover {
  background: rgba(255, 255, 255, 0.28);
}
```

replace with

```css
#shelf-badge:hover {
  background: rgba(255, 255, 255, 0.28);
}

/* The wings step aside (island/wing.ts, island.ts `stepWing`): while the compact island folds into its notch-wide middle, the cats, the grid and the shelf's badge fade with it.
   `--nm-wing` is their opacity (1 at rest), multiplied in by `filter: opacity()`, which composes with the opacities the page sets inline. The class exists only while the fade is not at
   rest, so a resting island has no filter at all, and nothing here puts a CSS animation on a canvas that other code hides. */
#island.wing-on #bot-canvas,
#island.wing-on #bot2-canvas,
#island.wing-on #kitten-canvas,
#island.wing-on #mini-grid,
#island.wing-on #shelf-badge {
  filter: opacity(var(--nm-wing, 1));
}

#island.wing-on #bot-glow {
  filter: blur(6px) opacity(var(--nm-wing, 1));
}
```

- [ ] **Step 10: Run**

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/fsm-wing.test.mjs scripts/cat-tests/u1b-wing-wiring.test.mjs scripts/cat-tests/fsm-hover.test.mjs 2>&1 | grep -E "^ℹ (tests|pass|fail)|✖"
npx --no-install tsc --noEmit && echo "tsc ok"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: the three files `fail 0` (`fsm-hover` is the existing Open on hover file and must stay green: the wing hold is off by default); `tsc ok`; `check:cat` `fail 0`.

- [ ] **Step 11: Look at it once yourself (no picture needed from you)**

Start the dev server: `mkdir -p "${TMPDIR:-/tmp}/u1b-run" && cd windows && (npx vite --host 127.0.0.1 --port 1421 > "${TMPDIR:-/tmp}/u1b-run/vite.log" 2>&1 & echo $! > "${TMPDIR:-/tmp}/u1b-run/vite.pid")`, wait until `curl -s http://127.0.0.1:1421/ | head -c 200` answers, and report the URL and that the server is running; the main session takes the pictures of 4b with it and stops it by the PID in that file. If your tools include the Browser pane you may check `window.__nm.island.onCursor(480, 16)` yourself, but the main session's pictures are the checkpoint.

- [ ] **Step 12: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/src/island/fsm.ts windows/src/island/island.ts windows/src/island/desktop.ts windows/src/main.ts windows/src/style.css windows/scripts/cat-tests/fsm-wing.test.mjs windows/scripts/cat-tests/u1b-wing-wiring.test.mjs
git commit -F - <<'MSG'
feat(windows): both wings of the compact island step aside

The island swooshes into its notch-wide middle (a 0.22 s spring, the cats, grid and badge fading) while the pointer is over either wing: the
right at once, the left after a 0.4 s rest with no button pressed. Click-through follows from the first tick, the zones stay at the island's
rest frame, it comes back 1 s after the pointer leaves, an alert cancels it, and Open on hover opens nothing from a wing. The rules are the
Mac's (Task 1); the wake-ups for a parked pointer are one one-shot timer. Where the OS gives no global pointer (Wayland) nothing changes.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
```

---

### Task 4b: Owner checkpoint 1: the pictures (the main session and the owner)

**Not a subagent task.** After Task 4 and its review, the main session takes the pictures with the Browser pane over the dev server of Task 4 Step 11 (`http://127.0.0.1:1421/`, viewport 720 x 320; `window.__nm.island` is the island). Copy them to `.claude/checkpoints/u1b/` of the worktree (gitignored).

1. **Set up.** In the page's console: `const i = __nm.island; __nm.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/p/app" }); i.fsm.forcePetit();` The compact island shows the big cat on the left and the grid on the right.
2. **At rest** (`wings-rest`): a picture.
3. **Right wing** (`wings-right-folded`): `i.onCursor(480, 16)`; wait 400 ms; a picture (the black strip is 184 px wide, no cat, no grid). Read `i.wing.state` (`{ faded: true, passThrough: true }`) and the width of `#island`.
4. **Mid-swoosh** (`wings-mid`, best effort: the spring settles in about 110 ms): `i.onCursor(700, 200)` then wait 1100 ms (it is back); then, in ONE batch, `i.onCursor(480, 16)` and a screenshot at once (the island between 288 and 184 px, the cats half faded). Also read, in the same call as the trigger, `setTimeout(() => console.log(i.swoosh.value, i.wingFade), 40)`: a swoosh between 0.3 and 0.9 and a fade between 0.2 and 0.8 prove the motion even if the picture lands late.
5. **Left wing** (`wings-left`): `i.onCursor(240, 16)`; a picture at 200 ms (not folded yet) and at 450 ms (folded).
6. **Back** : `i.onCursor(700, 200)`; a picture at 1200 ms (it is back, cats visible).
7. **Outside click** (`outside-click`): `i.fsm.forceHome();` a picture of the open island; then `i.onPointerButton({ down: true, x: 650, y: 300, own: false }); i.onPointerButton({ down: false, x: 651, y: 300, own: false });` a picture (compact again). Then `i.fsm.forceHome(); i.fsm.pinned = true;` repeat the two events: still open. `i.fsm.pinned = false; i.fsm.forceHome();` a third time with `{ down: false, x: 650, y: 340 }` for the release (a drag): still open.
8. **Stop the server** by the PID in `${TMPDIR:-/tmp}/u1b-run/vite.pid` and report the pictures with one sentence each of what they show.

The owner looks at the pictures and answers open question 4 (is the 184 px middle left on screen when folded?) before Task 5 starts.

---

### Task 5: Linux under X11: the pointer feed (droppable)

**Agent: `nm-implementer-deep` (Sonnet 5.5, high; CLAUDE.md trigger 1: Xlib on the poll thread, GDK on the main thread, and the input-region click-through left alone).** Loads `superpowers:systematic-debugging` besides the usual skills.

**Do this task only if the owner said yes to open question 1.** Nothing else in the plan depends on it: without it Linux behaves as the Wayland rows of the design table, everywhere.

**Files:**
- Modify: `windows/src-tauri/src/platform/linux.rs`, `windows/src-tauri/src/platform/windows.rs`, `windows/src-tauri/src/lib.rs`
- Create: `windows/scripts/cat-tests/u1b-x11-wiring.test.mjs`

**Interfaces:**
- Consumes (Task 2): `platform::pointer_feed()`, `any_button_down()`, `press_is_own(&AppHandle, x, y)` and the poll's use of them; `platform::cursor_physical()`.
- Produces: `platform::detect_pointer_feed()` (main thread, once, at setup; a no-op on Windows); Linux `cursor_physical()` now answers under X11.

**Design.** The island's page treats `boot.cursorPoll` as "the OS gives a global pointer". Under X11 it does: `XQueryPointer` on the root window returns the pointer's root position and the buttons' mask, from a connection of the poll thread's own (an Xlib `Display` is not shared between threads, and the poll thread is the only caller). Under Wayland, XWayland would answer with a stale position, so the test is GDK's own: the default display is a `GdkX11Display`. `CURSOR_POLL` stays false on Linux: it means "click-through is the `WS_EX_TRANSPARENT` toggle" (and the desktop cat's own poll reads it too), and Linux click-through stays the input region, which Task 2 made the poll respect. A side effect, accepted in open question 1: with a global pointer the cat's eyes follow it across the whole screen under X11, as on Windows. To tell the app's own windows at a press (Settings, the desktop cat), the poll thread asks the main thread, which asks GDK (`window_at_position` is `None` for another app's window); the wait is 40 ms at most and happens at button presses only. No XInput, no grab, no hook.

- [ ] **Step 1: The pins, and watch them fail**

**Create `windows/scripts/cat-tests/u1b-x11-wiring.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the X11 pointer feed is wired (platform/linux.rs, lib.rs, platform/windows.rs), pinned as source text. A real X server is not part of these checks.
const read = (rel) => fs.readFileSync(new URL(`../../src-tauri/src/${rel}`, import.meta.url), "utf8");
const linux = read("platform/linux.rs"), lib = read("lib.rs"), win = read("platform/windows.rs");

test("Xlib is linked directly and only three calls are made: open, the root window, query the pointer", () => {
  assert.match(linux, /#\[link\(name = "X11"\)\]/);
  const calls = [...linux.matchAll(/pub fn (X[A-Za-z]+)\(/g)].map((m) => m[1]).sort();
  assert.deepEqual(calls, ["XDefaultRootWindow", "XOpenDisplay", "XQueryPointer"]);
  assert.match(linux, /thread_local! \{\s*static DISPLAY: Cell<usize>/, "one connection per thread: an Xlib display is not shared");
});

test("only a GDK X11 display counts, and Linux click-through stays the input region", () => {
  assert.match(linux, /d\.type_\(\)\.name\(\) == "GdkX11Display"/);
  assert.match(linux, /pub const CURSOR_POLL: bool = false;/);
  assert.match(linux, /if !pointer_feed\(\) \{\s*return None;\s*\}\s*x11_pointer\(\)/);
});

test("the display is looked at on the main thread before the poll starts, and Windows has nothing to detect", () => {
  const detect = lib.indexOf("platform::detect_pointer_feed();");
  assert.ok(detect > 0 && detect < lib.indexOf("island::spawn_cursor_poll("), "detect, then spawn");
  assert.match(win, /pub fn detect_pointer_feed\(\) \{\}/);
});

test("the app's own window is asked of GDK on the main thread, for at most 40 ms, at presses only", () => {
  assert.match(linux, /app\.run_on_main_thread\(move \|\| \{/);
  assert.match(linux, /rx\.recv_timeout\(std::time::Duration::from_millis\(40\)\)/);
  assert.match(linux, /p\.window_at_position\(\)\.0\.is_some\(\)/);
});
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/u1b-x11-wiring.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"`
Expected: FAIL.

- [ ] **Step 2: The Linux side**

**Edit `windows/src-tauri/src/platform/linux.rs`:** find

```rust
/// Nothing polls the cursor here: the page reports it over the island, and the
/// input region decides click-through (see the top of this file).
pub const CURSOR_POLL: bool = false;

pub fn cursor_physical() -> Option<(f64, f64)> {
    None
}
```

replace with

```rust
/// Click-through here is the input region, never the poll's `WS_EX_TRANSPARENT` toggle, so this stays false even where the pointer can be read (`pointer_feed`, X11).
pub const CURSOR_POLL: bool = false;

/// The pointer in physical root pixels, under X11 (`pointer_feed`); nothing under Wayland.
pub fn cursor_physical() -> Option<(f64, f64)> {
    if !pointer_feed() {
        return None;
    }
    x11_pointer().map(|(x, y, _)| (x, y))
}
```

**Edit `windows/src-tauri/src/platform/linux.rs`:** find

```rust
/// Wayland gives an app no global pointer. (Task 5 of U1b turns this on under X11.)
pub fn pointer_feed() -> bool {
    false
}

pub fn any_button_down() -> bool {
    false
}

pub fn press_is_own(_app: &AppHandle, _x: f64, _y: f64) -> bool {
    false
}
```

replace with

```rust
// ── The pointer feed (X11 only) ───────────────────────────────────────────────────────────────

/// Whether GDK runs on its X11 backend, where the pointer can be read anywhere on the screen. A Wayland session gives an app no global pointer (XWayland would answer with a stale
/// one), so it is not counted even if libX11 can connect. Set once by `detect_pointer_feed`.
static X11_POINTER: AtomicBool = AtomicBool::new(false);

pub fn pointer_feed() -> bool {
    X11_POINTER.load(Ordering::Relaxed)
}

/// Main thread, once, at setup: is GDK's display the X11 one?
pub fn detect_pointer_feed() {
    let x11 = gtk::gdk::Display::default().map(|d| d.type_().name() == "GdkX11Display").unwrap_or(false);
    X11_POINTER.store(x11, Ordering::Relaxed);
    crate::log::line(format!("pointer feed: {}", if x11 { "X11 (global pointer)" } else { "none (no global pointer)" }));
}

mod x11 {
    use std::os::raw::{c_char, c_int, c_uint, c_ulong, c_void};
    // libX11 is always there: GTK 3 links it, even in a Wayland session. These are the three calls the pointer read needs.
    #[link(name = "X11")]
    extern "C" {
        pub fn XOpenDisplay(name: *const c_char) -> *mut c_void;
        pub fn XDefaultRootWindow(display: *mut c_void) -> c_ulong;
        pub fn XQueryPointer(display: *mut c_void, w: c_ulong, root: *mut c_ulong, child: *mut c_ulong, root_x: *mut c_int, root_y: *mut c_int, win_x: *mut c_int, win_y: *mut c_int, mask: *mut c_uint) -> c_int;
    }
}

/// Button1Mask, Button2Mask and Button3Mask of an X pointer state (the wheel's buttons 4 and 5 are not buttons held).
fn buttons_down(mask: u32) -> bool {
    mask & ((1 << 8) | (1 << 9) | (1 << 10)) != 0
}

/// The pointer's root position (physical px) and whether a button is held, from a connection of the calling thread's own: an Xlib display is not shared between threads, and the island's poll thread is the
/// only caller. None when X cannot be reached.
fn x11_pointer() -> Option<(f64, f64, bool)> {
    use std::cell::Cell;
    use std::os::raw::{c_int, c_uint, c_ulong, c_void};
    thread_local! {
        static DISPLAY: Cell<usize> = const { Cell::new(0) };
    }
    DISPLAY.with(|cell| unsafe {
        let mut display = cell.get() as *mut c_void;
        if display.is_null() {
            display = x11::XOpenDisplay(std::ptr::null());
            if display.is_null() {
                return None;
            }
            cell.set(display as usize);
        }
        let (mut root, mut child): (c_ulong, c_ulong) = (0, 0);
        let (mut rx, mut ry, mut wx, mut wy): (c_int, c_int, c_int, c_int) = (0, 0, 0, 0);
        let mut mask: c_uint = 0;
        let ok = x11::XQueryPointer(display, x11::XDefaultRootWindow(display), &mut root, &mut child, &mut rx, &mut ry, &mut wx, &mut wy, &mut mask);
        (ok != 0).then(|| (rx as f64, ry as f64, buttons_down(mask)))
    })
}

pub fn any_button_down() -> bool {
    pointer_feed() && x11_pointer().map(|(_, _, down)| down).unwrap_or(false)
}

/// Whether the window under the pointer belongs to this app (GDK answers `None` for another app's window). GDK is main-thread only, so the poll thread asks the main thread and waits at
/// most 40 ms; this runs at button presses only.
pub fn press_is_own(app: &AppHandle, _x: f64, _y: f64) -> bool {
    if !pointer_feed() {
        return false;
    }
    let (tx, rx) = std::sync::mpsc::channel();
    let asked = app.run_on_main_thread(move || {
        let own = gtk::gdk::Display::default()
            .and_then(|d| d.default_seat())
            .and_then(|s| s.pointer())
            .map(|p| p.window_at_position().0.is_some())
            .unwrap_or(false);
        let _ = tx.send(own);
    });
    asked.is_ok() && rx.recv_timeout(std::time::Duration::from_millis(40)).unwrap_or(false)
}

#[cfg(test)]
mod x11_tests {
    use super::*;

    #[test]
    fn only_the_three_buttons_count_as_held() {
        assert!(buttons_down(1 << 8), "button 1");
        assert!(buttons_down(1 << 9), "button 2");
        assert!(buttons_down(1 << 10), "button 3");
        assert!(buttons_down((1 << 8) | 0x4), "a button with control held");
        assert!(!buttons_down(0), "nothing held");
        assert!(!buttons_down(0x4 | 0x1), "control and shift alone");
        assert!(!buttons_down((1 << 11) | (1 << 12)), "the wheel's buttons 4 and 5 are not held buttons");
    }

    #[test]
    fn without_the_feed_nothing_is_read() {
        // detect_pointer_feed has not run in a unit test, so the feed is off and no X connection is opened.
        assert!(!pointer_feed());
        assert_eq!(cursor_physical(), None);
        assert!(!any_button_down());
    }
}
```

**Edit `windows/src-tauri/src/platform/windows.rs`:** find

```rust
        pid == std::process::id()
    }
}
```

replace with

```rust
        pid == std::process::id()
    }
}

/// Nothing to detect: Windows always gives the pointer.
pub fn detect_pointer_feed() {}
```

- [ ] **Step 3: Detect before the poll starts**

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
            island::spawn_cursor_poll(handle.clone(), gate.clone());
```

replace with

```rust
            // Under X11 the pointer can be read anywhere on screen; the poll's period and boot's `cursorPoll` follow (platform::pointer_feed).
            platform::detect_pointer_feed();
            island::spawn_cursor_poll(handle.clone(), gate.clone());
```

- [ ] **Step 4: Run**

```bash
windows/scripts/cargo-linux.sh test -p notchmeow --offline --target-dir /repo/windows/target/u1b -- x11_tests pointer:: 2>&1 | grep -E "^test |^test result|^error|^warning: unused" | head
cd windows && node --experimental-strip-types --test scripts/cat-tests/u1b-x11-wiring.test.mjs scripts/cat-tests/u1b-pointer-wiring.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)"; cd ..
```

Expected: the two `x11_tests` and the three `pointer::` tests `ok`; no `error`; the pins `fail 0`. If `d.type_()` does not compile, add `use gtk::glib::object::ObjectExt;` to that function and say so. If Docker is down: "needs Docker".

**What was not and could not be tested here:** a real X server. Task 8 lists the checks for a machine with X11 (the pointer read, the 40 ms ask, the cat's eyes across the screen, the wings and the outside click over a real window).

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/src-tauri/src/platform/linux.rs windows/src-tauri/src/platform/windows.rs windows/src-tauri/src/lib.rs windows/scripts/cat-tests/u1b-x11-wiring.test.mjs
git commit -F - <<'MSG'
feat(linux): under X11 the island reads the pointer, so the outside click and the wings work there

XQueryPointer from the poll thread's own Xlib connection (no grab, no hook, no XInput), chosen only when GDK runs on its X11 backend; the
app's own windows are told apart at a press through GDK on the main thread. Click-through stays the input region. Wayland sessions are
unchanged. Not run against a real X server.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
```

---

### Task 6: Open Claude: the resolver, the commands, the four buttons

**Agent: `nm-implementer` (Haiku 5.5, high).** The Rust resolver and its tests are given in full and were run in the dry run.

**Files:**
- Create: `windows/src-tauri/src/claude_app.rs`, `windows/src/core/openagent.ts`, `windows/scripts/cat-tests/u1b-claude-app.test.mjs`
- Modify: `windows/src-tauri/src/lib.rs`, `windows/src-tauri/src/platform/windows.rs`, `windows/src-tauri/src/platform/linux.rs`, `windows/src/core/bridge.ts`, `windows/src/core/state.ts`, `windows/src/main.ts`, `windows/src/island/island.ts`, `windows/src/views/views.ts`, and two existing Sidekick pin files that pin the lines this task changes: `windows/scripts/sidekick-tests/agentdrop.test.mjs`, `windows/scripts/sidekick-tests/notes.test.mjs`

**Interfaces:**
- Produces: the Tauri command `open_claude_app() -> bool`; `platform::CLAUDE_APP: bool` (Windows true, Linux false) and `platform::open_claude_app() -> bool`; `BootInfo.claudeApp`; `State.claudeApp`; `Bridge.openClaudeApp()`; `openRoute(pillId, claudeApp)`, `finishedAction(pillId, claudeApp)`, `CLAUDE_APP_PILL` in `core/openagent.ts`; `claude_app::{Launch, candidates, valid_aumid, start_app_id, pick}`.

**Design.** Four places open an agent's app on the Mac (`AgentTarget.bringForward`): the pill's ↗, the finished card's primary button, a Sidekick nudge's button, and a file dropped on the pill's cat. For `agent_claude-desktop` each now starts the Claude desktop app (Windows) or does nothing and shows no button (Linux). Starting is `explorer.exe <path>` or `explorer.exe shell:AppsFolder\<AUMID>`: no `cmd`, no shell string. The resolver tries, in order, the classic install's paths and its Start-menu shortcut, then asks PowerShell for the Start-menu entry named exactly "Claude" and accepts its AppID only if it is a well-formed AUMID. An already-running instance is brought forward by the app's own single-instance handling, as `NSWorkspace.openApplication` does on the Mac. Which install the owner has is **not verified** (open question 3): the order is a guess that the tests cover with fake folders.

- [ ] **Step 1: The tests, and watch them fail**

**Create `windows/scripts/cat-tests/u1b-claude-app.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { CLAUDE_APP_PILL, finishedAction, openRoute } from "../../src/core/openagent.ts";

test("the Claude App pill's Open starts the Claude app where there is one, and nothing where there is none", () => {
  assert.equal(CLAUDE_APP_PILL, "agent_claude-desktop");
  assert.equal(openRoute(CLAUDE_APP_PILL, true), "claude-app");
  assert.equal(openRoute(CLAUDE_APP_PILL, false), "none", "Linux: no official app, so the ↗ does nothing rather than open VS Code on the wrong thing");
  assert.equal(openRoute("integration_claude", true), "vscode", "Claude Code is as it was");
  assert.equal(openRoute("integration_claude", false), "vscode");
  assert.equal(openRoute("agent_gemini", true), "other");
  assert.equal(openRoute(null, true), "other");
});

test("the finished card and the Sidekick's nudge: Open Claude for a session from the app, Open terminal for the rest, no button on Linux for the app", () => {
  assert.deepEqual(finishedAction(CLAUDE_APP_PILL, true), { label: "Open Claude", kind: "claude-app" });
  assert.equal(finishedAction(CLAUDE_APP_PILL, false), null);
  assert.deepEqual(finishedAction("integration_claude", false), { label: "Open terminal", kind: "terminal" });
  assert.deepEqual(finishedAction("agent_gemini", true), { label: "Open terminal", kind: "terminal" });
  assert.deepEqual(finishedAction(undefined, true), { label: "Open terminal", kind: "terminal" });
});

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the page asks Rust to start the app from the four places that open an agent's app", () => {
  const island = read("src/island/island.ts"), views = read("src/views/views.ts"), bridge = read("src/core/bridge.ts"), main = read("src/main.ts"), state = read("src/core/state.ts");
  assert.match(bridge, /openClaudeApp: \(\) => call<boolean>\("open_claude_app"\)/);
  assert.match(bridge, /claudeApp: boolean;/);
  assert.match(main, /if \(boot\) State\.claudeApp = boot\.claudeApp;/);
  assert.match(state, /claudeApp = false;/);
  assert.match(island, /if \(openRoute\(task\.id, State\.claudeApp\) === "claude-app"\) void Bridge\.openClaudeApp\(\);/, "the pill's ↗");
  assert.match(island, /openTerminal: \(\) => this\.openAgent\(State\.focusTask\?\.id, State\.focusTask\?\.sessionCwd \?\? null\),/, "the finished card");
  assert.match(island, /this\.openAgent\(id, State\.tasks\.find\(\(t\) => t\.id === id\)\?\.sessionCwd \?\? null\);/, "the Sidekick's nudge");
  assert.match(island, /if \(agentId === CLAUDE_APP_PILL\) void Bridge\.openClaudeApp\(\);/, "a file dropped on the pill's cat");
  assert.match(views, /const open = btn\("Open terminal", "primary", \(\) => actions\.openTerminal\(\)\);/);
  assert.match(views, /const act = finishedAction\(note\.agentId, State\.claudeApp\);/);
});

test("Rust starts only what the resolver picks, through the shell, with no command interpreter", () => {
  const lib = read("src-tauri/src/lib.rs"), win = read("src-tauri/src/platform/windows.rs"), linux = read("src-tauri/src/platform/linux.rs");
  assert.match(lib, /async fn open_claude_app\(\) -> bool \{\s*blocking\(platform::open_claude_app\)\.await\.unwrap_or\(false\)/);
  assert.match(lib, /open_claude_app,/);
  assert.match(lib, /claude_app: platform::CLAUDE_APP,/);
  const body = /pub fn open_claude_app\(\) -> bool \{[\s\S]*?\n\}\n/.exec(win)?.[0] ?? "";
  assert.ok(body.length > 100, "the Windows function exists");
  assert.match(body, /crate::claude_app::pick\(/);
  assert.match(body, /Command::new\("explorer\.exe"\)/);
  assert.match(body, /shell:AppsFolder\\\\\{id\}/);
  assert.match(body, /Get-StartApps/);
  assert.doesNotMatch(body, /"cmd"|"cmd\.exe"|Command::new\("sh"\)|-c"|\/c/, "no command interpreter ever sees a name from the system");
  assert.match(linux, /pub const CLAUDE_APP: bool = false;/);
  assert.match(linux, /pub fn open_claude_app\(\) -> bool \{\s*false\s*\}/);
});
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/u1b-claude-app.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)|ERR_MODULE"`
Expected: FAIL (`ERR_MODULE_NOT_FOUND` for `src/core/openagent.ts`).

- [ ] **Step 2: The pure TypeScript**

**Create `windows/src/core/openagent.ts`:**

```ts
// What the island's "open this agent's app" actions do for a Claude Code session from the Claude desktop app (the pill `agent_claude-desktop`, the relay's `claude-desktop` tag). The
// Mac opens that app by its bundle ID (AgentTarget.swift) and labels the finished card's button "Open Claude". Here the app can be started on Windows only: Anthropic ships no
// Claude desktop app for Linux, so there the pill has nothing to open and its buttons are not shown. Pure, so the plain-Node checks can load it.

/** The frozen pill ID of Claude Code sessions from the Claude desktop app. */
export const CLAUDE_APP_PILL = "agent_claude-desktop";

/** Where the ↗ button of the focused pill goes: "claude-app" (start the Claude desktop app), "vscode" (the project in VS Code), "none" (nothing to open here), "other" (the integrations' own links). */
export function openRoute(pillId: string | null | undefined, claudeApp: boolean): "claude-app" | "vscode" | "none" | "other" {
  if (pillId === CLAUDE_APP_PILL) return claudeApp ? "claude-app" : "none";
  if (pillId === "integration_claude") return "vscode";
  return "other";
}

/** The primary button of the finished card and of a Sidekick nudge about `pillId`: its label and what it starts, or null when there is no such button (Linux, for the Claude desktop app). */
export function finishedAction(pillId: string | null | undefined, claudeApp: boolean): { label: string; kind: "claude-app" | "terminal" } | null {
  if (pillId === CLAUDE_APP_PILL) return claudeApp ? { label: "Open Claude", kind: "claude-app" } : null;
  return { label: "Open terminal", kind: "terminal" };
}
```

- [ ] **Step 3: The resolver (Rust)**

**Create `windows/src-tauri/src/claude_app.rs`:**

```rust
// Finding the Claude desktop app on Windows, for the pill's Open action (the Mac opens it by its bundle ID). Pure and platform-neutral so the Linux container tests it: the Windows
// side (platform/windows.rs `open_claude_app`) supplies the folders, the "does it exist" test and the Start-menu listing, and starts what this module picks. Anthropic ships no
// desktop app for Linux, so there `platform::open_claude_app` finds nothing and the page hides the button.

use std::path::{Path, PathBuf};

/// How to start the app.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Launch {
    /// A program or a Start-menu shortcut that exists on disk: started by the shell, which also brings an already-running instance forward.
    Path(PathBuf),
    /// A packaged (MSIX) app, started through the shell by its AppUserModelID: `explorer.exe shell:AppsFolder\<id>`.
    Aumid(String),
}

/// The places a classic (non-packaged) install and its Start-menu shortcut live, most likely first. `local` is %LOCALAPPDATA%, `roaming` is %APPDATA%, `programs` is %ProgramFiles%.
pub fn candidates(local: Option<&Path>, roaming: Option<&Path>, programs: Option<&Path>) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Some(l) = local {
        out.push(l.join("AnthropicClaude").join("claude.exe"));
        out.push(l.join("Programs").join("Claude").join("Claude.exe"));
    }
    if let Some(p) = programs {
        out.push(p.join("Claude").join("Claude.exe"));
    }
    if let Some(r) = roaming {
        out.push(r.join("Microsoft").join("Windows").join("Start Menu").join("Programs").join("Claude.lnk"));
    }
    out
}

/// An AppUserModelID of a packaged app: `<package family name>!<app id>`, letters, digits, dot, dash and underscore only. Anything else (a path, a GUID, a space, a quote, an
/// ampersand) is not started: the text comes from the system's own list, but it is still put on a command line.
pub fn valid_aumid(s: &str) -> bool {
    let Some((family, app)) = s.split_once('!') else { return false };
    let ok = |part: &str| !part.is_empty() && part.len() <= 128 && part.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_'));
    ok(family) && ok(app) && !app.contains('!')
}

/// The AppID of the Start-menu entry named exactly "Claude", from the lines `Get-StartApps` printed as `Name<TAB>AppID` (the caller asks PowerShell to print them that way).
pub fn start_app_id(listing: &str) -> Option<String> {
    listing
        .lines()
        .filter_map(|line| line.split_once('\t'))
        .find(|(name, id)| name.trim() == "Claude" && valid_aumid(id.trim()))
        .map(|(_, id)| id.trim().to_string())
}

/// Picks how to start the app: the first candidate that exists, else the packaged app the Start menu lists. `listing` is asked for only when no file was found (it starts PowerShell).
pub fn pick(candidates: &[PathBuf], exists: impl Fn(&Path) -> bool, listing: impl FnOnce() -> Option<String>) -> Option<Launch> {
    if let Some(found) = candidates.iter().find(|p| exists(p)) {
        return Some(Launch::Path(found.clone()));
    }
    listing().and_then(|text| start_app_id(&text)).map(Launch::Aumid)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dirs() -> Vec<PathBuf> {
        candidates(Some(Path::new("L")), Some(Path::new("R")), Some(Path::new("P")))
    }

    #[test]
    fn candidates_come_in_order_and_skip_missing_folders() {
        let all = dirs();
        assert_eq!(all.len(), 4);
        assert_eq!(all[0], Path::new("L").join("AnthropicClaude").join("claude.exe"));
        assert!(all[3].ends_with("Claude.lnk"));
        assert_eq!(candidates(None, None, None), Vec::<PathBuf>::new());
        assert_eq!(candidates(Some(Path::new("L")), None, None).len(), 2);
    }

    #[test]
    fn the_first_file_that_exists_wins_and_the_listing_is_never_asked() {
        let all = dirs();
        let second = all[1].clone();
        let got = pick(&all, |p| p == second || p == all[3], || panic!("PowerShell must not start when a file was found"));
        assert_eq!(got, Some(Launch::Path(second)));
    }

    #[test]
    fn with_no_file_the_packaged_app_is_found_in_the_start_menu_listing() {
        let all = dirs();
        let listing = "Calculator\tMicrosoft.WindowsCalculator_8wekyb3d8bbwe!App\nClaude\tClaude_pzs8sxrjxfjjc!Claude\n";
        let got = pick(&all, |_| false, || Some(listing.to_string()));
        assert_eq!(got, Some(Launch::Aumid("Claude_pzs8sxrjxfjjc!Claude".into())));
    }

    #[test]
    fn nothing_found_is_none_and_a_failed_listing_is_none() {
        assert_eq!(pick(&dirs(), |_| false, || None), None);
        assert_eq!(pick(&dirs(), |_| false, || Some(String::new())), None);
        assert_eq!(pick(&[], |_| true, || None), None);
    }

    #[test]
    fn only_an_entry_named_exactly_claude_with_a_well_formed_id_counts() {
        assert_eq!(start_app_id("Claude Code\tFoo_abc!App\n"), None, "a similar name is not Claude");
        assert_eq!(start_app_id("claude\tFoo_abc!App\n"), None);
        assert_eq!(start_app_id("Claude\tC:\\Program Files\\Claude\\Claude.exe\n"), None, "a path is not an AUMID");
        assert_eq!(start_app_id("Claude\tFoo & calc!App\n"), None);
        assert_eq!(start_app_id("Claude\tFoo\"bar!App\n"), None);
        assert_eq!(start_app_id("Claude\tFoo!App!Extra\n"), None);
        assert_eq!(start_app_id("Claude Foo_abc!App\n"), None, "no tab, no entry");
        assert_eq!(start_app_id("Claude\t Foo_abc!App \r\n"), Some("Foo_abc!App".into()), "padding and a CRLF are trimmed");
    }

    #[test]
    fn aumid_rules() {
        assert!(valid_aumid("Claude_pzs8sxrjxfjjc!Claude"));
        assert!(!valid_aumid(""));
        assert!(!valid_aumid("!App"));
        assert!(!valid_aumid("Foo!"));
        assert!(!valid_aumid("Foo bar!App"));
        assert!(!valid_aumid(&format!("{}!App", "a".repeat(129))));
    }
}
```

- [ ] **Step 4: The commands and the platform**

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
mod cat_settings;
mod desktop;
```

replace with

```rust
mod cat_settings;
#[cfg_attr(not(windows), allow(dead_code))]
mod claude_app;
mod desktop;
```

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
    /// What the shelf can do on this system: drag a file out of the island, send it through the system's share.
    shelf: ShelfCaps,
}
```

replace with

```rust
    /// What the shelf can do on this system: drag a file out of the island, send it through the system's share.
    shelf: ShelfCaps,
    /// There is a Claude desktop app the pill's Open can start (Windows). Anthropic ships none for Linux.
    claude_app: bool,
}
```

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
        shelf: ShelfCaps { drag_out: dragout::supported(), send: platform::SHARE },
```

replace with

```rust
        shelf: ShelfCaps { drag_out: dragout::supported(), send: platform::SHARE },
        claude_app: platform::CLAUDE_APP,
```

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
/// Puts a text on the clipboard: the paths of the files dropped on an agent's cat
```

replace with

```rust
/// The pill's Open for a Claude Code session from the Claude desktop app: starts the app (Windows), or brings it forward when it runs. False when it cannot be found, and always on Linux, where
/// Anthropic ships no desktop app. The lookup may start PowerShell, so it runs off the main thread.
#[tauri::command]
async fn open_claude_app() -> bool {
    blocking(platform::open_claude_app).await.unwrap_or(false)
}

/// Puts a text on the clipboard: the paths of the files dropped on an agent's cat
```

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
            open_in_vscode,
```

replace with

```rust
            open_in_vscode,
            open_claude_app,
```

**Edit `windows/src-tauri/src/platform/windows.rs`:** find

```rust
pub fn open_url(url: &str) {
    let _ = no_console(Command::new("rundll32.exe").args(["url.dll,FileProtocolHandler", url]))
        .spawn();
}
```

replace with

```rust
pub fn open_url(url: &str) {
    let _ = no_console(Command::new("rundll32.exe").args(["url.dll,FileProtocolHandler", url]))
        .spawn();
}

/// The Claude desktop app can be started (the pill's Open).
pub const CLAUDE_APP: bool = true;

/// Starts the Claude desktop app, or brings it forward when it runs (the app's own single-instance handling does that). The choice of what to start is `claude_app::pick`: the classic
/// install's paths and its Start-menu shortcut, else the packaged app the Start menu lists by name. Started through the shell with the path or the validated AUMID as ONE argument; no `cmd`.
pub fn open_claude_app() -> bool {
    let dir = |name: &str| std::env::var_os(name).map(PathBuf::from);
    let (local, roaming, programs) = (dir("LOCALAPPDATA"), dir("APPDATA"), dir("ProgramFiles"));
    let places = crate::claude_app::candidates(local.as_deref(), roaming.as_deref(), programs.as_deref());
    let launch = crate::claude_app::pick(&places, |p| p.is_file(), || {
        let out = no_console(Command::new("powershell.exe").args([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            r#"Get-StartApps | ForEach-Object { $_.Name + "`t" + $_.AppID }"#,
        ]))
        .output()
        .ok()?;
        out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
    });
    match launch {
        Some(crate::claude_app::Launch::Path(path)) => no_console(Command::new("explorer.exe").arg(path)).spawn().is_ok(),
        Some(crate::claude_app::Launch::Aumid(id)) => no_console(Command::new("explorer.exe").arg(format!("shell:AppsFolder\\{id}"))).spawn().is_ok(),
        None => false,
    }
}
```

**Edit `windows/src-tauri/src/platform/linux.rs`:** find

```rust
pub fn open_url(url: &str) {
    let _ = Command::new("xdg-open").arg(url).spawn();
}
```

replace with

```rust
pub fn open_url(url: &str) {
    let _ = Command::new("xdg-open").arg(url).spawn();
}

/// Anthropic ships no Claude desktop app for Linux, so the pill has nothing to open here and the page shows no button.
pub const CLAUDE_APP: bool = false;

pub fn open_claude_app() -> bool {
    false
}
```

- [ ] **Step 5: The page**

**Edit `windows/src/core/bridge.ts`:** find

```ts
  openInVSCode: (path: string | null) => call<boolean>("open_in_vscode", { path }),
```

replace with

```ts
  openInVSCode: (path: string | null) => call<boolean>("open_in_vscode", { path }),

  /** The Claude App pill's Open: starts the Claude desktop app (Windows), or brings it forward. False where it cannot be found, and always on Linux. */
  openClaudeApp: () => call<boolean>("open_claude_app"),
```

**Edit `windows/src/core/bridge.ts`:** find

```ts
  shelf: { dragOut: boolean; send: boolean };
```

replace with

```ts
  shelf: { dragOut: boolean; send: boolean };
  /** There is a Claude desktop app the Claude App pill can open (Windows); false on Linux, where Anthropic ships none. */
  claudeApp: boolean;
```

**Edit `windows/src/core/state.ts`:** find

```ts
  shelfCaps = { dragOut: false, send: false };
```

replace with

```ts
  shelfCaps = { dragOut: false, send: false };
  /** There is a Claude desktop app the Claude App pill's Open can start (Windows); Anthropic ships none for Linux (core/openagent.ts). */
  claudeApp = false;
```

**Edit `windows/src/main.ts`:** find

```ts
  if (boot?.shelf) State.shelfCaps = { dragOut: boot.shelf.dragOut, send: boot.shelf.send };
```

replace with

```ts
  if (boot?.shelf) State.shelfCaps = { dragOut: boot.shelf.dragOut, send: boot.shelf.send };
  if (boot) State.claudeApp = boot.claudeApp;
```

**Edit `windows/src/island/island.ts`:** find

```ts
import { notchCatLocal } from "../core/notchspot";
```

replace with

```ts
import { notchCatLocal } from "../core/notchspot";
import { CLAUDE_APP_PILL, finishedAction, openRoute } from "../core/openagent.ts";
```

**Edit `windows/src/island/island.ts`:** find

```ts
      openTerminal: () => this.openTerminalIn(State.focusTask?.sessionCwd ?? null),
```

replace with

```ts
      openTerminal: () => this.openAgent(State.focusTask?.id, State.focusTask?.sessionCwd ?? null),
```

**Edit `windows/src/island/island.ts`:** find

```ts
        if (task.id === "integration_claude") void Bridge.openInVSCode(task.sessionCwd ?? null);
        else if (task.id === "integration_n8n") void Bridge.openN8n();
```

replace with

```ts
        if (openRoute(task.id, State.claudeApp) === "claude-app") void Bridge.openClaudeApp();
        else if (task.id === "integration_claude") void Bridge.openInVSCode(task.sessionCwd ?? null);
        else if (task.id === "integration_n8n") void Bridge.openN8n();
```

**Edit `windows/src/island/island.ts`:** find

```ts
      sidekickOpen: () => {
        const id = State.sidekickNote?.agentId;
        this.openTerminalIn(State.tasks.find((t) => t.id === id)?.sessionCwd ?? null);
      },
```

replace with

```ts
      sidekickOpen: () => {
        const id = State.sidekickNote?.agentId;
        this.openAgent(id, State.tasks.find((t) => t.id === id)?.sessionCwd ?? null);
      },
```

**Edit `windows/src/island/island.ts`:** find

```ts
  /** "Open terminal": the project folder in VS Code. The chat's button and a Sidekick note both go through here. */
  private openTerminalIn(cwd: string | null) {
    void Bridge.openInVSCode(cwd);
  }
```

replace with

```ts
  /** "Open terminal": the project folder in VS Code. The chat's button and a Sidekick note both go through here. */
  private openTerminalIn(cwd: string | null) {
    void Bridge.openInVSCode(cwd);
  }

  /** The primary action of a card about one agent: the Claude app for a session from it, the project in VS Code for any other (core/openagent.ts). None where there is no app to open. */
  private openAgent(pillId: string | null | undefined, cwd: string | null) {
    const act = finishedAction(pillId, State.claudeApp);
    if (act === null) return;
    if (act.kind === "claude-app") void Bridge.openClaudeApp();
    else this.openTerminalIn(cwd);
  }
```

**Edit `windows/src/island/island.ts`:** find

```ts
      if (platformName() === "windows") void Bridge.openInVSCode(State.tasks.find((t) => t.id === agentId)?.sessionCwd ?? null);
```

replace with

```ts
      if (platformName() === "windows") {
        if (agentId === CLAUDE_APP_PILL) void Bridge.openClaudeApp();
        else void Bridge.openInVSCode(State.tasks.find((t) => t.id === agentId)?.sessionCwd ?? null);
      }
```

**Edit `windows/src/views/views.ts`:** find

```ts
import { badgeText } from "../sidekick/explain.ts";
```

replace with

```ts
import { badgeText } from "../sidekick/explain.ts";
import { finishedAction } from "../core/openagent.ts";
```

**Edit `windows/src/views/views.ts`:** find

```ts
  const row = h("div", { class: "actions" },
    btn("Open terminal", "primary", () => actions.openTerminal()),
    btn("OK", "secondary", () => actions.collapse()),
  );
  const el = h("div", { class: "view" }, card("green", stack(116, 16, who, title, row)));
  return {
    el,
    sync() {
      clear(who);
      who.append(agentWho(State.focusTask, "Claude Code finished"));
      title.textContent = State.focusTask?.steps.at(-1) ?? "Session finished";
    },
  };
```

replace with

```ts
  const open = btn("Open terminal", "primary", () => actions.openTerminal());
  const row = h("div", { class: "actions" },
    open,
    btn("OK", "secondary", () => actions.collapse()),
  );
  const el = h("div", { class: "view" }, card("green", stack(116, 16, who, title, row)));
  return {
    el,
    sync() {
      clear(who);
      who.append(agentWho(State.focusTask, "Claude Code finished"));
      title.textContent = State.focusTask?.steps.at(-1) ?? "Session finished";
      // "Open terminal", or "Open Claude" for a session from the Claude desktop app; no button where there is no app to open (Linux). Core/openagent.ts.
      const act = finishedAction(State.focusTask?.id, State.claudeApp);
      open.style.display = act ? "" : "none";
      if (act && open.firstElementChild) open.firstElementChild.textContent = act.label;
    },
  };
```

**Edit `windows/src/views/views.ts`:** find

```ts
      else row.append(btn("Not now", "secondary", () => actions.sidekickDismiss()), btn("Open terminal", "primary", () => actions.sidekickOpen()));
```

replace with

```ts
      else {
        const act = finishedAction(note.agentId, State.claudeApp);
        row.append(btn("Not now", "secondary", () => actions.sidekickDismiss()));
        if (act) row.append(btn(act.label, "primary", () => actions.sidekickOpen()));
      }
```

- [ ] **Step 5b: The Sidekick's pins follow the lines this task changed**

These three assertions pin the exact text of three lines Step 5 rewrote (the file-drop handoff, the nudge's button, the nudge's open path). They are updated to the new text, not loosened.

**Edit `windows/scripts/sidekick-tests/agentdrop.test.mjs`:** find

```js
  assert.match(handoff, /if \(platformName\(\) === "windows"\) void Bridge\.openInVSCode\(State\.tasks\.find\(\(t\) => t\.id === agentId\)\?\.sessionCwd \?\? null\);/);
```

replace with

```js
  assert.match(handoff, /if \(platformName\(\) === "windows"\) \{\s*if \(agentId === CLAUDE_APP_PILL\) void Bridge\.openClaudeApp\(\);\s*else void Bridge\.openInVSCode\(State\.tasks\.find\(\(t\) => t\.id === agentId\)\?\.sessionCwd \?\? null\);\s*\}/);
```

**Edit `windows/scripts/sidekick-tests/notes.test.mjs`:** find

```js
  assert.match(views, /btn\("Open terminal", "primary", \(\) => actions\.sidekickOpen\(\)\)/, "Open terminal is not a dismissal");
```

replace with

```js
  assert.match(views, /if \(act\) row\.append\(btn\(act\.label, "primary", \(\) => actions\.sidekickOpen\(\)\)\);/, "Open terminal (or Open Claude) is not a dismissal");
```

**Edit `windows/scripts/sidekick-tests/notes.test.mjs`:** find

```js
  assert.match(island, /sidekickOpen: \(\) => \{\s*const id = State\.sidekickNote\?\.agentId;\s*this\.openTerminalIn\(/);
```

replace with

```js
  assert.match(island, /sidekickOpen: \(\) => \{\s*const id = State\.sidekickNote\?\.agentId;\s*this\.openAgent\(/);
  assert.match(island, /else this\.openTerminalIn\(cwd\);/, "and the one path to VS Code is still openTerminalIn");
```

- [ ] **Step 6: Run**

```bash
windows/scripts/cargo-linux.sh test -p notchmeow --offline --target-dir /repo/windows/target/u1b -- claude_app:: 2>&1 | grep -E "^test |^test result|^error|^warning" | head -12
cd windows
node --experimental-strip-types --test scripts/cat-tests/u1b-claude-app.test.mjs 2>&1 | grep -E "^ℹ (pass|fail)|✖"
npx --no-install tsc --noEmit && echo "tsc ok"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)|✖"
cd ..
```

Expected: the six `claude_app::tests::` tests `ok`; no `error` and no dead-code warning on Linux; the TypeScript file `pass 4`, `fail 0`; `tsc ok`; `check:cat` `fail 0`; `check:sidekick` fails only the one test it failed at the base (Task 0 Step 3). If Docker is down: "needs Docker" for the cargo line. **`platform/windows.rs` is compiled by CI only: say so.**

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/src-tauri/src/claude_app.rs windows/src-tauri/src/lib.rs windows/src-tauri/src/platform/windows.rs windows/src-tauri/src/platform/linux.rs windows/src/core/openagent.ts windows/src/core/bridge.ts windows/src/core/state.ts windows/src/main.ts windows/src/island/island.ts windows/src/views/views.ts windows/scripts/cat-tests/u1b-claude-app.test.mjs
git commit -F - <<'MSG'
feat(windows): the Claude App pill's Open starts the Claude desktop app

The pill's arrow, the finished card's "Open Claude" button, a Sidekick nudge's button and a file dropped on the pill's cat. Windows finds a classic
install, its Start-menu shortcut or the packaged app the Start menu lists by name (the AppUserModelID is validated, nothing goes through cmd);
Linux has no official app, so the button is not shown. The install paths are not verified on a real machine.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

---

### Task 6b: Owner checkpoint 2: the pictures (the main session and the owner)

**Not a subagent task.** Same setup as 4b (dev server `http://127.0.0.1:1421/`, viewport 720 x 320, copies in `.claude/checkpoints/u1b/`).

1. **A Claude App session.** In the console: `const i = __nm.island; __nm.State.claudeApp = true; __nm.hook({ hook_event_name: "UserPromptSubmit", nm_agent: "claude-desktop", session_id: "s1", cwd: "C:/p/app" }); __nm.hook({ hook_event_name: "Stop", nm_agent: "claude-desktop", session_id: "s1", cwd: "C:/p/app" });` If the finished card is not showing: `__nm.State.setFocus("agent_claude-desktop"); i.alert("finished");`. Pictures: the overview with the Claude App pill (amber, `#E3A857`, label "Claude App") and the ↗ button; the finished card with **Open Claude** and OK (`pill-claude-app-windows`).
2. **Linux** (`State.claudeApp = false`, then `i.alert("finished")` again): the finished card with OK only (`pill-claude-app-linux`).
3. **Claude Code is as it was:** focus `integration_claude` (`__nm.State.setFocus("integration_claude")`), `i.alert("finished")`: **Open terminal** and OK.
4. Report the pictures with one sentence each; stop the server by its PID.

---

### Task 7: README, the French spec sentences, AGENTS.md, the CLAUDE.md map, and the last checks

**Agent: `nm-implementer-light` (Haiku 5.5, medium).** Docs only; every find text is given.

**Files:**
- Modify: `windows/README.md`, `docs/SPEC.md`, `docs/AGENTS.md`, `CLAUDE.md`

- [ ] **Step 1: The README**

**Edit `windows/README.md`:** find

```markdown
- The wardrobe has no global shortcut here (the Mac's ⌃⌥G, off by default):
```

replace with

```markdown
- **The island gets out of your way** (the Mac's wings and outside click, U1b). On the compact island the pointer over either **wing** (the 52 px each side of the 184 px middle; the big cat on the left, the grid and the shelf badge on the right) makes the whole island swoosh into its middle: over the right wing at once, over the left (the big cat) after the pointer has rested there 0.4 s with no mouse button pressed, so a click, the drag out to the desktop and the right-click on the cat work as before. The cats, grid and badge fade, the mouse passes through to what is under the wings (a window's title bar, a tab), the island comes back 1 s after the pointer has left both wings, and a waiting card, a file on its way in, the shelf's hold or the desktop cat away from the notch cancels it. The 184 px middle stays on screen: a PC has no notch to disappear into. With Open on hover on, the pointer on a wing opens nothing. A **click outside the open island folds it** (like Escape), on the release of a click (a press that moves more than 4 px, such as a file taken out of Explorer, is not one), except when something waits for you (a permission request, a question, the shelf's drag-out or Send), it is pinned, you are typing in the chat, a native menu of the island is open, the click is on another window of NotchMeow (Settings, the desktop cat, the tray's menu), or the cat or a file is being dragged. How: the island's cursor poll, which already runs while it is showing, also reads the three mouse buttons, and only while the island is open; there is no mouse hook and no new timer (one one-shot timer runs only during the left wing's 0.4 s or the 1 s return). A click shorter than the poll's 16 ms tick can be missed.
- **The Claude App pill's Open** starts the Claude desktop app: the pill's arrow, the finished card's "Open Claude" button, a Sidekick nudge's button and a file dropped on the pill's cat. It finds a classic install (and its Start-menu shortcut) or the packaged app that the Start menu lists as "Claude"; an app that is already running is brought forward. Linux has no official Claude desktop app, so the button is not shown there.
- The wardrobe has no global shortcut here (the Mac's ⌃⌥G, off by default):
```

**Edit `windows/README.md`:** find

```markdown
- **The wardrobe's menu** holds the island open only where the menu blocks
```

replace with

```markdown
- **The wings and the outside click** need to know where the pointer is on the whole screen. **Under X11 they work** (the island reads the pointer through Xlib about 60 times a second while it is showing, nothing while it is hidden; the cat's eyes then follow the pointer across the screen, as on Windows). **Under Wayland, on every compositor (KDE, COSMIC, Hyprland, Sway and GNOME alike), they do not exist**: Wayland tells an app nothing about a click that lands on another app's window, and a layer surface gets no pointer event outside its input region (which is what lets clicks through), so the island could neither see an outside click nor see the pointer leave a wing to come back. There the island behaves as before: Escape, a click on the compact island, its own auto-close. Nothing is polled and nothing changes. Window blur is not a way round it: the island never takes the keyboard focus except for the chat.
- **The Claude desktop app** has no Linux build from Anthropic, so the Claude App pill shows no Open button on Linux.
- **The wardrobe's menu** holds the island open only where the menu blocks
```

- [ ] **Step 2: The French spec**

**Edit `docs/SPEC.md`:** find

```markdown
(macOS seulement ; section gardée
```

replace with

```markdown
(macOS, puis Windows et Linux sous X11 ; section gardée
```

**Edit `docs/SPEC.md`:** find

```markdown
Windows et Linux : rien (une suite d'un plan ultérieur, comme le clic en dehors).
```

replace with

```markdown
Windows et Linux sous X11 (U1b, `windows/src/island/wing.ts`, mêmes règles et mêmes constantes, vérifiées contre `IslandWing.swift`) : l'île `compact` fait 288 px (un « notch » de 184 px et deux ailes de 52 px), et c'est ce milieu de 184 px qui reste à l'écran quand elle se replie ; la zone laisse passer la souris dès le premier tick (rectangle de clic-à-travers réduit de la marge de 14 px de chaque côté), le suivi du pointeur est le sondage du curseur qui tourne déjà, et le seul minuteur ajouté est un minuteur à un coup, armé seulement pendant le délai de 0,4 s de l'aile gauche et pendant la seconde du retour. Linux sous Wayland (tous les compositeurs) : rien, faute de position globale du pointeur ; l'île reste comme avant.
```

**Edit `docs/SPEC.md`:** find

```markdown
le moniteur de souris n'existe que tant que l'île est ouverte.
```

replace with

```markdown
le moniteur de souris n'existe que tant que l'île est ouverte. Windows et Linux sous X11 (U1b) : le même clic en dehors, sans moniteur ni crochet : le sondage du curseur de l'île, qui tourne déjà tant qu'elle est visible, lit aussi les trois boutons de la souris, et seulement tant que l'île est ouverte ; un clic sur une autre fenêtre de NotchMeow (Réglages, chat de bureau, menu de la zone de notification) n'est pas « en dehors » ; sous Wayland, rien.
```

- [ ] **Step 3: AGENTS.md**

**Edit `docs/AGENTS.md`:** find

```markdown
On Windows and Linux the pill appears while the session runs; the button that opens the app is for a later plan.
```

replace with

```markdown
On Windows the pill's ↗, the finished card's "Open Claude" button, a Sidekick nudge's button and a file dropped on the pill's cat start the Claude app (a classic install, its Start-menu shortcut, or the packaged app that the Start menu lists as "Claude"); on Linux, where Anthropic ships no desktop app, the pill appears while the session runs and has nothing to open.
```

- [ ] **Step 4: CLAUDE.md**

**Edit `CLAUDE.md`:** find

```markdown
wings step aside (Mac only):
```

replace with

```markdown
wings step aside (Mac; Windows and Linux under X11 through U1b):
```

**Edit `CLAUDE.md`:** find

```markdown
The Windows and Linux app has none (a follow-up plan, with the outside click).
```

replace with

```markdown
The Windows and Linux app has the same rules in `windows/src/island/wing.ts` (U1b: tested by the same cases and a drift pin that reads this file's constants).
```

**Edit `CLAUDE.md`:** find

```markdown
(a click outside the open island folds it, Mac only: one global mouse monitor
```

replace with

```markdown
(a click outside the open island folds it, on the Mac: one global mouse monitor
```

**Edit `CLAUDE.md`:** find

```markdown
draw the pictures (about seven minutes each: they compile the whole app).
```

replace with

```markdown
draw the pictures (about seven minutes each: they compile the whole app).
- U1b, the island on Windows and Linux (`docs/superpowers/plans/2026-10-16-u1b-windows-island-parity.md`): the Mac's outside click and both wings, ported case for case: `windows/src/island/outsideclick.ts` and `wing.ts` (pure; `outside-click.test.mjs` and `wing.test.mjs` replay the Mac's cases and read the Swift constants), `wingdriver.ts` (feeds the rules and arms ONE one-shot timer, only while the left wing's 0.4 s dwell or the 1 s return runs: the Windows cursor event comes only when the pointer moves, so there is no 16 ms tick). No mouse hook and no new poll: `island.rs`'s cursor poll reads the three mouse buttons on every tick, before its skip for a still pointer, and only while the page says the island is expanded (`watch_pointer_buttons`), and sends `pointer-button` (`pointer.rs` turns the reads into edges; a press says whether the window under it is the app's own); `set_island_rect` marks the shape changed so click-through is re-decided on the next tick, and while folded the page pushes `foldedHitRect`. Only where the OS gives a global pointer (`platform::pointer_feed()`: Windows, and Linux under X11 from Xlib `XQueryPointer`; never Wayland, where both features are simply off). `Island.feedWing`/`stepWing` and `style.css` ("The wings step aside", opacity by `filter` so inline opacities are not fought). Open on hover's `fsm.pointerOnWing` and `hoverResume()` are the Mac's hover-only hold. The Claude App pill's Open: `claude_app.rs` (the resolver, tested on Linux), `platform::open_claude_app` (Windows: `explorer.exe`, no `cmd`), `core/openagent.ts` (`openRoute`, `finishedAction`); Linux has no app and shows no button. Tests: `outside-click`, `wing`, `wingdriver`, `fsm-wing`, `u1b-*` in `windows/scripts/cat-tests/` and the Rust tests of `pointer.rs`, `claude_app.rs`, `platform/linux.rs` (X11 helpers).
```

- [ ] **Step 5: The last checks**

```bash
cd windows
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:claude 2>&1 | tail -3
npx --no-install tsc --noEmit && echo "tsc ok"
cd ..
bash scripts/check-no-leftovers.sh | tail -2
bash scripts/check-site.sh 2>&1 | tail -3
windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/u1b 2>&1 | grep -E "^test result|FAILED|^error" | head
git status --short
```

Expected: `fail 0` on `check:cat` (the Task 0 count plus about 52 new tests) and `check:claude`, and on `check:sidekick` only the one failure it had at the base (Task 0 Step 3); `tsc ok`; leftovers and site checks pass (the site bundle does not contain the island, so it is not stale); every `test result: ok`; `git status` shows only the four doc files of this task. If Docker is down: "needs Docker" for the cargo line. State in the ledger which Rust is compiled only by CI (`platform/windows.rs` and the Windows branches).

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/README.md docs/SPEC.md docs/AGENTS.md CLAUDE.md
git commit -F - <<'MSG'
docs: the island's wings, the outside click and Open Claude on Windows and Linux, and their honest limits

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

---

### After Task 7: the whole-branch review

`nm-reviewer-deep` (Sonnet 5.5, high; CLAUDE.md trigger 4) reads `git diff notchmeow/rebrand...HEAD` for: the cross-task contracts (the event and command names and payload shapes in Rust, `bridge.ts`, `main.ts`; `foldedHitRect` against `HIT_MARGIN` in both places; `cursorPoll` gating in every new call); the 0 % rule (nothing new while hidden; no `setInterval`; the wing driver's single one-shot; the button read only while watching); privacy and safety (no global hook, the AUMID validation, nothing built from a path with `cmd`, nothing logged that is a prompt or a path); the Wayland no-op (a session without a pointer sees the same island as before); and the Mac untouched (`git diff --stat notchmeow/rebrand...HEAD -- NotchBuddy` is empty). Fix what it finds, then stop and report (Task 8).

---

### Task 8: Owner checkpoint: the real-machine checks (the main session and the owner)

Not claimed as passed by any agent. Nothing here was run on a real Windows or Linux machine.

**Windows**
1. Open the island (hover or click). Click on the desktop or in another app's window: it folds. A press, a 20 px drag and a release (move a window by its title bar, or select text): it stays.
2. With the island open, click NotchMeow's Settings window, the desktop cat and the tray menu: it stays.
3. A permission card waiting, then click elsewhere: it stays. Type in the chat, then click elsewhere: it stays. A shelf tile dragged out, and the Share window: it stays.
4. A very short tap (as short as you can) and a click that does not move the mouse at all: both fold it. (Expected rarity: a tap under 16 ms may not.)
5. Drag a file from Explorer onto the island and drop it: nothing folds.
6. Compact island over a maximized browser's tab row: the pointer on the right wing folds it at once, and a click on the tab beneath works at once (not after the spring). The left wing: 0.4 s with the pointer still, then it folds; a click on the big cat within the 0.4 s still works as before; the drag of the cat's head out to the desktop works; the right-click wardrobe menu works.
7. Leave both wings: it comes back after a second, and stays back with the pointer still on the middle.
8. A permission request arriving while the pointer is parked on a wing: the island is back at once.
9. High DPI / 125 % scaling and a second monitor: the wings are where the picture shows them; no strip beside the 184 px middle eats clicks.
10. Open on hover on: the pointer on a wing opens nothing; the middle opens after 150 ms.
11. The Claude desktop app: with the classic install, with the packaged (Store/MSIX) install, and not installed: the pill's ↗ and the finished card's Open Claude start it, bring it forward when it runs, and do nothing visible (no crash) when it is missing. **Tell the main session which install you have: the resolver's order is a guess.**

**Linux under X11** (Task 5, if kept): the same list minus 11, and the cat's eyes now follow the pointer across the screen; the poll's CPU while the island shows (the `top` figure of the app on an idle island should be about 1 % or less).

**Linux under Wayland** (KDE or Sway, and GNOME): the island behaves exactly as before this branch: Escape folds, a click outside does not, the wings do not move; nothing in the log says otherwise.

## Owner's answers (2026-10-16)

The folded island keeps its 184 px middle on screen; Task 5 (Linux X11) stays; no Settings switch for the wings or the outside click, as on the Mac. Runs now, beside D1b; G2-tauri waits for this plan to merge.
