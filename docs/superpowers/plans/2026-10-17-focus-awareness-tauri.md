# Focus awareness (Windows and Linux): Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Mac's focus awareness on Windows and Linux: when a permission request comes from a session whose app is the foreground app, the island declines it at once (the existing `Bridge.approvalDecline`, so the agent asks in its own window), stays closed and silent, puts a still amber dot on the pill (open island and compact notch), a read-only "Waiting in <app>: <verb>" note on the Claude Code card, and Projects counts it as "Waiting in <app>", until the session moves on or 10 minutes pass.

**Architecture:** A pure `windows/src/core/focusaware.ts` holds the host tables (Windows by process image name, Linux X11 by `WM_CLASS`), the match, the marks and their endings, the wording (through `projects/core.ts` `waitLabel`) and the dot and second-line rules; it is the Mac's `FocusAware.swift` case for case where the platforms agree, with drift pins. Rust reads the foreground app once per request through one async command, `foreground_app` (`GetForegroundWindow` + the process image on Windows; `_NET_ACTIVE_WINDOW` + `WM_CLASS` through GDK's own X connection under X11; nothing under Wayland). `island/hooks.ts` gains `takeHook`, which asks it only when the setting is on and the request's host is in the table, then hands the existing `handleHook` the request alone (today's path) or the request plus its mark. The Sidekick holds the waiting nudge per session and wakes once at each mark's end (the owner's bounded exception).

**Tech Stack:** TypeScript (Node 22 `--experimental-strip-types` tests: no enums, no parameter properties, `.ts` imports), CSS, Rust (Tauri 2; the `windows` crate features already in `Cargo.toml`; Xlib and GDK 3's X11 calls through direct `extern "C"` links like the existing `mod x11` in `platform/linux.rs`).

**Spec:** `docs/superpowers/specs/2026-10-17-focus-awareness-design.md` (binding: "Windows", "Linux", "Windows/Linux", "The island (Mac)" for the cat-2 line rule, calls 1 to 10, and calls 1 to 8 after the builder check). The Mac code merged on `main` is the reference: `NotchBuddy/Sources/App/FocusAware.swift`, `FocusAwareApp.swift`, `FocusAwareViews.swift`, the call sites in `HookServer.swift`, `IslandViewContent.swift`, `IslandRootView.swift`, `Sidekick.swift`, `SidekickEngine.swift`, and the owner's rulings in `.claude/archive/sdd/focus-awareness-mac/2026-10-17-focus-mac/progress.md`. Where the Swift and the TypeScript disagree on a shared rule, the Swift decides (drift pins below). Mac is primary: Windows/Linux gets at most what the Mac gets, in the Mac's words.

**Base:** `main` at `0997356d` (the Mac version merged). A new branch `focus/tauri` in a git worktree. If a find text below does not occur exactly once, stop and report; do not guess.

## Refresh 2026-10-22

- Base set to `0997356d`: the Mac version is merged, so the "after the Mac plan" gate is gone.
- The own `waitLabel` port and its drift test are dropped: `noteText` uses `waitLabel` from `windows/src/projects/core.ts` (P-tauri, merged), already fixture-tested against `projects-core.js`; the `appWaitLabel` pin now reads `ProjectsRules.swift`, where the Mac moved it.
- Old Step 5b is unconditional (P-tauri is merged): `State.projects.hook(payload, stepBack?.host)`, and P-tauri's wiring pin moves with it.
- `twinWaitIn` is not ported: Windows has no `--ask` hook, and Claude Code's ordinary PreToolUse comes before the PermissionRequest it belongs to, so no twin can land after the mark. Pinned in Task 1's notes, said in the README.
- Settings follows the restyle: the row is in `settings/general.ts`'s Island card (General has no tabs here), with the Mac's words; `controls.json`'s `island.focusAware` row gets its `winHomes`/`win`, `FROZEN.settings` gains `focusAware`, and `map.test.mjs`'s count stays 53 (the row already exists) with its message corrected.
- The Sidekick hold is per session, as the Mac's review fixed it (a rule view of the ledger without the stepped-back waits), not a global `cardShown`.
- The Sidekick work is its own task (Task 4), so the old Tasks 4 to 6 are now 5 to 7; the map row and frozen key move into Task 3 with the `Settings` field, because `map.test.mjs`'s source scan fails as soon as the field exists.
- The owner's one bounded wake at a mark's 10-minute end is added (the stuck clock, armed even with the Sidekick off), and recorded in the docs.
- The cat-2 line rule (`showsNoteOverSecondLine`, owner 2026-10-22) replaces "the note always hides `second`".
- A request from NotchMeow's own chat never steps back: `routeHook(...) === "chat"` returns before the step-back, and the Rust read gives `None` for our own process. Both pinned.
- Host words follow the Mac's per app: `Cursor.exe` (and X11 `Cursor`) reads "Cursor", not "VS Code".
- The mark's session ID is the Sidekick ledger's (`session_id`, else `conversation_id`, cut to 128 code points, else `"unknown"`), and a mark lives while `-600 s < age < 600 s`, as the Mac's review fixed both.
- The mark endings run before the Sidekick's feed (the Mac's open item: one spurious redraw when they run after).
- `handleHook` gains a third parameter, so two existing pins that spell its signature (`sleep.test.mjs`, `two-cats.test.mjs`) are updated; the dev `__nm.hook` stays as it is and `__nm.take` / `__nm.foreground` are added.
- The compact dots' wing fade is a rule of its own: the existing `#island.wing-on` block is pinned by `u1b-wing-wiring.test.mjs` and `projects-tests/island.test.mjs`.
- `views/titlefit.ts` is untouched: the note sits in the ticker's body, not the title row.
- The Mac's "Handled in …" card note (call 7) has no Windows twin to replace: nothing to port.
- Docs: `ARCHITECT.md`'s two focus lines also get the Windows/Linux half.

## What the platforms allow (no polling anywhere)

| Platform | Foreground read | Hosts matched (words) | Not matched (today's card) |
|---|---|---|---|
| Windows | Once per request: `GetForegroundWindow` → `GetWindowThreadProcessId` (our own pid → none) → `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` → `QueryFullProcessImageNameW`, the base name only. No new `windows` feature. | Claude app sessions: `Claude.exe` ("Claude App"); `term_program` = `vscode`: `Code.exe`, `Code - Insiders.exe`, `VSCodium.exe` ("VS Code"), `Cursor.exe` ("Cursor"); `wt_session` set: `WindowsTerminal.exe` ("Windows Terminal"); tagged agents by the same rows from their own event | plain consoles (`cmd`, PowerShell in conhost) and every other terminal: the relay carries no marker for them (spec call 4); Codex has no Windows route |
| Linux, X11 session (`platform::pointer_feed()` true) | Once per request, on the main thread through GDK's own X connection inside GDK's error trap: `_NET_ACTIVE_WINDOW` of the root, then that window's `WM_CLASS` class | `term_program` = `vscode`: `Code`, `Code - Insiders`, `VSCodium` ("VS Code"), `Cursor` ("Cursor"); `TERM_PROGRAM` `kitty` (`kitty`), `WezTerm` (`org.wezfurlong.wezterm`), `Alacritty` (`Alacritty`), `ghostty` (`com.mitchellh.ghostty`) in the Mac's words | Claude app sessions (no Linux app), every other terminal, a window manager without `_NET_ACTIVE_WINDOW` |
| Linux, Wayland (and XWayland inside Wayland) | **None.** The page is told `foreground: "none"` at boot and never calls the command | nothing | everything: the card shows as today |

**No question card exists on Windows or Linux** (`island/hooks.ts` has no `--ask` path: a question is a `Notification` that sets the pill's state). The step-back applies to `PermissionRequest`; one whose tool is `AskUserQuestion` is a mark of kind `question` (no step words), as on the Mac.

## Global Constraints

Every task's requirements include this section.

- **The only answer is the existing decline** (`Bridge.approvalDecline(requestId)`: the relay writes nothing, so Claude Code asks in its own window; Antigravity's `{"decision":"ask"}` in the relay is unchanged). Never `approvalDecision`, never "allow". No relay change (`windows/hook/` untouched).
- **Never block Claude Code.** The relay waits 800 ms for the ack (`pipe.rs` `ACK_TIMEOUT`): the page waits at most **300 ms** for the foreground read, then declines (step back) or goes on to today's card path, which acks synchronously as now.
- **0 % CPU when hidden.** The foreground app is read once per request, only when the setting is on, the platform can read it (`foregroundKind !== "none"`) and the request's host is in the table. No `SetWinEventHook`, no `EVENT_SYSTEM_FOREGROUND`, no `XSelectInput`, no `setInterval`, no new thread. Timers: the 300 ms race, alive only while a read is pending, and the owner-approved one-shot wake at a mark's 10-minute end through the Sidekick's stuck clock (spec, calls after the builder check, item 8): one per mark lifetime, never repeating, re-armed only for the earliest live mark.
- **Privacy.** Only the foreground process's image base name (Windows) or window class (Linux) is read; it is mapped to the table's fixed words or dropped, never logged (no `log::line`, no `Bridge.log`), stored, shown or put in the Sidekick's ledger. No window title, document name or content. The mark holds the session ID, the pill, the table's words, the kind, the step verb and the time; never a command, path or prompt.
- **Every doubt is today's behaviour:** no host, Wayland, a read that fails or takes more than 300 ms, a name not in the table: not matched.
- **A stepped-back request touches nothing else:** no `island.alert`, `reveal`, `holdOpen`, pin, sound, `setPillBadge`, `updateTask`, `ensurePill`, `upsert`, focus change, desktop-cat call, and it never displaces a pending approval (rule 7). A request from NotchMeow's own chat never steps back.
- **Mac-primary.** Nothing under `NotchBuddy/` changes. Shared values are pinned against the Swift: `markLifetime` 600, `marksMax` 64, the `endingEvents` list, the `AskUserQuestion` exception, `appWaitLabel` (in `ProjectsRules.swift`).
- **Never restyle what ships.** New CSS is only `.fa-dot`, `.fa-mini-dot`, `.fa-compact-dot`, `.fa-note` and one new `#island.wing-on .fa-compact-dot` rule; existing rules are untouched. Colour: `var(--nm-state-color-approval)` (generated, `#F5A524`); no change to `shared/theme.json`.
- **No new crate, no new `windows` feature** (if the build proves one is needed, stop and ask the owner).
- **Rust** runs through `windows/scripts/cargo-linux.sh` (offline; `--target-dir /repo/windows/target/focus`) and `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-focus` when Docker is up; when it is down, mark the step "needs Docker". Windows-only code is linked and run only by `windows-tests.yml` on `windows-latest`: say so in the ledger and never claim it ran.
- **Models and commits** as in CLAUDE.md: Haiku 5.5 first, Sonnet 5.5 only on the named trigger, never Opus or Fable; local commits with `git commit -F <file>`, only the task's files; never push.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app. A `vite` dev server on `127.0.0.1` may run; stop it only by the PID you saved. No task sends a hook event to a real socket or pipe.
  2. Install nothing; no network calls; no `docker build` or `docker pull`.
  3. Use `trash`, never `rm -rf`; scratch files under `${TMPDIR:-/tmp}` in a uniquely named folder.
  4. Never edit `design/prototype/cat-core.js`, `shared/*`, a generated theme or core file, `windows/hook/`, or anything under `NotchBuddy/`. The one fixture this plan edits is `tests/fixtures/settings/controls.json` (Task 3, the `island.focusAware` row only).
  5. Never push. Commit only in a task's commit step, after `git rev-parse --show-toplevel` shows this worktree and `git branch --show-current` shows `focus/tauri`.
  6. Never rename a frozen ID; write no `Coucou` or `Mochi` name.
  7. Never read, print or write the real `~/.claude/settings.json` or anything in the real `~/.claude`, `~/.gemini`, `~/.codex`.
  8. If a command is denied by a permission prompt, stop and report it.

## Review Focus

Most likely to bite first; each names its test.

1. **The 800 ms ack window and a slow or hung foreground read.** A busy main thread or a dead X server must not cost Claude Code two minutes. Expected: after 300 ms the page treats it as "not matched" and the card path acks in time; Rust gives up its main-thread wait after 40 ms. Tests: Task 1 (`raceForeground` with a never-resolving read gives `null`), Task 2 (the 40 ms `recv_timeout` pin), Task 3 (the race wraps the read).
2. **Events that arrive while the read is pending.** Another session's events may be handled before the waiting request; the same session cannot send any (it is blocked on this request). Expected: the waiting request is handled exactly once, by today's code or the step-back; the mark is recorded before the Sidekick is fed. Tests: Task 3 pins (one `handleHook` call per outcome; `recordFocusMark` before `Hub.sk?.hook(payload)`).
3. **A stored `focusAware` that is not a Boolean.** A hand-edited `"focusAware": "no"` must not fail the whole `settings.json` (a wrong type in a typed field would). Expected: it reads as on, the rest loads. Test: Task 2 (`bool_or_true` cases).
4. **The Sidekick and a blocked agent.** Expected: no "still waiting for your OK" for the stepped-back session while its mark lives, another session's waiting nudge still comes, and at the 10-minute end the app redraws once even with the Sidekick off, with no second wake. Test: Task 4 (`stuck.test.mjs`, three cases).
5. **Our own windows, our own chat and the shell.** Settings or the desktop cat in front, the desktop/taskbar (`explorer.exe`), or a request from the chat's own `claude` must never step back. Expected: our own process gives `None`; `explorer.exe` is in no row; the chat route returns first. Tests: Task 1 (no row names `explorer.exe` or the app), Task 2 (own-pid pin), Task 3 (`routeHook(...) === "chat"` before `takeHook` asks).

---

## File Structure

| Path | Responsibility |
|---|---|
| `windows/src/core/focusaware.ts` (new), `windows/src/core/steps.ts` (modify: `stepVerb`), `windows/scripts/cat-tests/focusaware.test.mjs` (new) | The pure rules and their drift pins (Task 1). |
| `windows/src-tauri/src/foreground.rs` (new), `platform/windows.rs`, `platform/linux.rs`, `lib.rs`, `settings.rs` (modify) | The foreground read, the command, `BootInfo.foreground`, the `focusAware` setting (Task 2). |
| `windows/src/island/hooks.ts`, `core/bridge.ts`, `core/state.ts`, `main.ts`, `tests/fixtures/settings/controls.json` (modify), `windows/scripts/cat-tests/focus-wiring.test.mjs` (new), `cat-tests/sleep.test.mjs`, `cat-tests/two-cats.test.mjs`, `projects-tests/wiring.test.mjs`, `settings-tests/map.test.mjs` (modify) | The step-back in the page, the marks, the Projects feed, the stored key and its map row (Task 3). |
| `windows/src/sidekick/controller.ts`, `sidekick/appenv.ts` (modify), `windows/scripts/sidekick-tests/stuck.test.mjs` (modify) | The per-session hold and the lapse wake (Task 4). |
| `windows/src/views/views.ts`, `island/island.ts`, `settings/general.ts`, `style.css`, `windows/scripts/settings-tests/pages.test.mjs`, `cat-tests/focus-wiring.test.mjs` (modify) | The dot, the compact dots, the note, the Settings row (Task 5). |
| `windows/README.md`, `docs/SPEC.md`, `CLAUDE.md`, `ARCHITECT.md` (modify) | The limits, the French sentence, the map bullets (Task 6). |

## Tasks and agents

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`; the Rust task also reads `rust-patterns` and `rust-testing` *(files: `~/.claude/plugins/marketplaces/ecc/skills/<name>/SKILL.md`)* and loads `superpowers:systematic-debugging`. Reviewers load `ponytail:ponytail-review`; the final reviewer also loads `security-review` and runs `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` beside it (`model: sonnet`, trigger 4).

| # | Task | Agent, model, effort | Trigger | Review |
|---|---|---|---|---|
| 0 | Worktree and baseline | the session | | none |
| 1 | The pure rules and their tests | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 2 | Rust: the foreground read, the command, boot, the setting | `nm-implementer-deep`, **Sonnet 5.5**, high | 1 (the Win32 process query; Xlib through GDK's display and error trap on the main thread, reached from an async command) | `nm-reviewer` |
| 3 | The page: `takeHook`, the marks, the Projects feed | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 4 | The Sidekick: per-session hold and the lapse wake | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 5 | The dot, the compact dots, the note, the Settings row | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 5b | **Owner checkpoint 1:** dev-server and Settings pictures | the main session and the owner | | none |
| 6 | Docs: README, SPEC.md, CLAUDE.md, ARCHITECT.md | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| After 6 | Whole branch: never allow, the ack window, no poll, the one wake, privacy, Wayland no-op | `nm-reviewer-deep`, Sonnet 5.5, high | 4 | none |
| 7 | **Owner checkpoint 2:** a real PC and a Linux X11 session | the main session and the owner | | none |

## Execution

One worktree chat session, branch `focus/tauri`, **Sonnet 5.5 at high effort** (trigger 5: an interface that crosses Rust and TypeScript, an async step inside the hook path, and the Sidekick's clock; the session dispatches Haiku subagents for Tasks 1, 3, 4, 5, 6). It edits `hooks.ts`, `island.ts`, `views.ts`, `lib.rs`, `settings.rs`, `style.css`, `controller.ts` and `controls.json`: do not run it beside another plan that edits them. Start it in the three steps of `ARCHITECT.md`; it pings the main session with `SendMessage` at Task 5b, at the end and whenever it stops. Ledger: `.superpowers/sdd/2026-10-17-focus-tauri/progress.md`. Reviews read `git diff main...HEAD` narrowed to the task's files.

---

### Task 0: Worktree and baseline

- [ ] **Step 1:** `git switch -c focus/tauri main`; `git rev-parse --short HEAD` starts with `0997356d` (or a later `main` the main session names), and `grep -c 'static let markLifetime: Double = 600' NotchBuddy/Sources/App/FocusAware.swift` prints `1`.
- [ ] **Step 2:** Anchor counts (each must print `1`):
  ```bash
  W=windows/src; c() { grep -cF -- "$2" "$1"; }
  c $W/island/hooks.ts '  Hub.sk?.hook(payload);'
  c $W/island/hooks.ts '      if (isExternalAgent || fromClaudeApp) {'
  c $W/island/hooks.ts '  void onEvent<HookPayload>("hook", (payload) => handleHook(island, payload));'
  c $W/island/hooks.ts 'export function handleHook(island: Island, payload: HookPayload) {'
  c $W/island/hooks.ts '  State.projects.hook(payload);'
  c $W/island/hooks.ts 'import { Bridge, onEvent } from "../core/bridge";'
  c $W/main.ts 'if (boot) State.claudeApp = boot.claudeApp;'
  c $W/main.ts 'if (import.meta.env.DEV) (window as unknown as { __nm: { sk: unknown } }).__nm.sk = Hub.sk;'
  c $W/views/views.ts '      const pillKey = row.map(({ task: t }) => `${t.id}:${t.pillBadge ?? ""}`).join("|");'
  c $W/views/views.ts '  const tickerBody = h("div", { class: "card-body" }, who, ticker.el, second);'
  c $W/views/views.ts '    pill.append(badge);'
  c $W/island/island.ts '      const key = row.map(({ task }) => task.id).join("|");'
  c $W/island/island.ts '          this.miniGrid.append(createMiniBot(task, 13, cat));'
  c $W/settings/general.ts '  const island = card("Island", null, hover.el, glow.el, tuckRow, closeRow, screenRow);'
  c $W/settings/general.ts '    glow.set(s.hoverGlow);'
  c $W/core/state.ts '  hoverGlow: true,'
  c $W/core/state.ts '  claudeApp = false;'
  c $W/core/bridge.ts '  approvalDecline: (requestId: string) => call<void>("approval_decline", { requestId }),'
  c $W/sidekick/controller.ts '      this.clock.arm(this.deadline(stuckStep(this.ledger.snapshot, now, ctx).nextAt, now));'
  c $W/sidekick/appenv.ts '    wait: (ms, signal) => new Promise<void>((resolve) => {'
  c windows/src-tauri/src/lib.rs '        claude_app: platform::CLAUDE_APP,'
  c windows/src-tauri/src/lib.rs '            approval_decline,'
  c windows/src-tauri/src/settings.rs '    pub hover_glow: bool,'
  c windows/scripts/settings-tests/map.test.mjs '  assert.equal(all.length, 53,'
  c tests/fixtures/settings/controls.json '"id": "island.focusAware",'
  ```
- [ ] **Step 3:** Baseline in `windows/`: `npm run check:cat`, `npm run check:sidekick`, `npm run check:projects`, `npm run check:settings`, `npx --no-install tsc --noEmit` pass; `windows/scripts/cargo-linux.sh test -p notchmeow settings:: --target-dir /repo/windows/target/focus` passes (or "needs Docker"). First ledger line.

---

### Task 1: The pure rules and their tests

**Files:**
- Create: `windows/src/core/focusaware.ts`, `windows/scripts/cat-tests/focusaware.test.mjs`
- Modify: `windows/src/core/steps.ts`

**Interfaces:**
- Consumes: `waitLabel`, `APP_WAIT_LABEL`, `APP_WAIT_MS` from `windows/src/projects/core.ts` (the only import of `focusaware.ts`); the test also reads `NotchBuddy/Sources/App/FocusAware.swift` and `ProjectsRules.swift` as text and loads `shared/sidekick-core.js` through `createRequire`.
- Produces:
  ```ts
  export const MARK_LIFETIME_MS = 600_000;
  export const MARKS_MAX = 64;
  export const FOREGROUND_WAIT_MS = 300;
  export const ENDING_EVENTS: readonly string[];   // the Mac's eight, in its order
  export type ForegroundKind = "windows" | "x11" | "none";
  export type FocusKind = "permission" | "question";
  export interface FocusApp { name: string; words: string }
  export interface FocusHost { apps: readonly FocusApp[] }
  export interface FocusMark { sessionId: string; pillId: string; host: string; kind: FocusKind; words: string | null; at: number }
  export function focusEnabled(stored: unknown): boolean
  export function focusSessionKey(p: { session_id?: unknown; conversation_id?: unknown }): string
  export function focusHost(p: { nm_agent?: unknown; term_program?: unknown; wt_session?: unknown }, kind: ForegroundKind): FocusHost | null
  export function matchForeground(host: FocusHost, foreground: string | null | undefined): string | null   // the matched app's words
  export function raceForeground(read: () => Promise<string | null>, waitMs: number, setTimer: (fn: () => void, ms: number) => unknown, clearTimer: (t: unknown) => void): Promise<string | null>
  export function noteText(host: string, words: string | null): string
  export function showsDot(markLive: boolean, badgeShown: boolean, cardWaiting: boolean): boolean
  export function showsNoteOverSecondLine(markLive: boolean, secondWaiting: boolean): boolean
  export function recordMark(marks: readonly FocusMark[], mark: FocusMark): FocusMark[]
  export function endMarks(marks: readonly FocusMark[], sessionId: string, event: string, tool: string): FocusMark[]
  export function liveMarks(marks: readonly FocusMark[], now: number): FocusMark[]
  export function markForPill(marks: readonly FocusMark[], pillId: string, now: number): FocusMark | null
  export function markForSession(marks: readonly FocusMark[], sessionId: string, now: number): FocusMark | null
  export function lapseMs(markAt: number, now: number, nowMs: number): number
  // steps.ts
  export function stepVerb(tool: string): string | null
  ```

The rules, exactly (the Mac's where they are shared):

- `focusEnabled`: `stored !== false` (absent or not a Boolean reads as on).
- `focusSessionKey`: the first of `session_id`, `conversation_id` that is a non-empty string, cut to 128 code points, else `"unknown"` (the Sidekick ledger's own key, `sidekick-core.js` `eventFrom`).
- `focusHost`, `kind === "none"` → `null`. Lower-case `term_program`; `wt_session` counts when it is a non-empty string. Precedence: the Claude app tag, then `vscode`, then the terminal (VS Code's own terminal can inherit `WT_SESSION`).
  - `"windows"`: `nm_agent === "claude-desktop"` → `[{Claude.exe, "Claude App"}]`; `term_program === "vscode"` → `[{Code.exe, "VS Code"}, {Code - Insiders.exe, "VS Code"}, {VSCodium.exe, "VS Code"}, {Cursor.exe, "Cursor"}]`; `wt_session` set → `[{WindowsTerminal.exe, "Windows Terminal"}]`; else `null`.
  - `"x11"`: `nm_agent === "claude-desktop"` → `null`; `vscode` → `[{Code, "VS Code"}, {Code - Insiders, "VS Code"}, {VSCodium, "VS Code"}, {Cursor, "Cursor"}]`; `kitty` → `[{kitty, "kitty"}]`; `wezterm` → `[{org.wezfurlong.wezterm, "WezTerm"}]`; `alacritty` → `[{Alacritty, "Alacritty"}]`; `ghostty` → `[{com.mitchellh.ghostty, "Ghostty"}]`; else `null`. The words are `HookOrigin.terminalNames`'; "Windows Terminal" is Windows' own. Names are the documented defaults, unverified here (spec call 5): a wrong one only means today's card.
- `matchForeground`: `null` for a null or empty foreground; else the words of the first app whose name equals it ignoring case, else `null`.
- `raceForeground`: resolves with the read's value, or `null` if the read rejects or `waitMs` passes first; the timer is cleared when the read wins.
- `noteText`: `waitLabel(host)`, then `: ${words}` when `words` is a non-empty string (the Mac's `noteText`).
- `showsDot`: `markLive && !badgeShown && !cardWaiting`. `showsNoteOverSecondLine`: `markLive && !secondWaiting`.
- `recordMark`: drop the entry with the same `pillId` and `sessionId`, drop entries not live at `mark.at`, append, keep the newest `MARKS_MAX` by `at`; never changes its input.
- `endMarks`: drop every entry of `sessionId` when `event` is in `ENDING_EVENTS`, except `event === "PreToolUse" && tool === "AskUserQuestion"` (no `--ask` twin exists here, but the rule is the Mac's and the pin keeps it); never changes its input.
- Live: `-MARK_LIFETIME_MS < now - at < MARK_LIFETIME_MS` (the Mac's clamp). `markForPill` / `markForSession`: the newest live entry, or `null`.
- `lapseMs`: `nowMs + (markAt + MARK_LIFETIME_MS - now)` (the Mac's, in ms: marks use `Date.now()`, the Sidekick's clock may be skewed).
- `stepVerb`: the own-key value of `TOOL_LABELS`, else `null`; never reads an input. (The Mac's `mcp__` words are not ported: Windows' table has none; the note then says "Waiting in <host>" alone, spec call 5.)

- [ ] **Step 1: Write the failing test** `windows/scripts/cat-tests/focusaware.test.mjs` (`node:test`, `node:assert/strict`):
  - `"the setting reads on unless it is false"`: `focusEnabled(undefined)`, `(true)`, `("no")`, `(0)`, `(null)` are `true`; `(false)` is `false`.
  - `"the session key is the Sidekick ledger's"`: `createRequire(import.meta.url)("../../../shared/sidekick-core.js")`; for payloads `{session_id:"S1"}`, `{session_id:"", conversation_id:"C"}`, `{}`, `{session_id: 42}`, `{session_id: "x".repeat(130)}`, `{session_id: "\u{1F431}".repeat(130)}` (each with `hook_event_name: "PermissionRequest"`), `focusSessionKey(p) === core.eventFrom(p, 1).sessionId`.
  - `"Windows hosts"`: `{nm_agent:"claude-desktop", term_program:"vscode"}` → Claude.exe only; `{term_program:"VSCode", wt_session:"x"}` → the VS Code row; `{term_program:"", wt_session:"abc"}` → Windows Terminal; `{wt_session:""}` → `null`; `{nm_agent:"gemini", wt_session:"abc"}` → Windows Terminal; any input with `"none"` → `null`.
  - `"X11 hosts"`: `{term_program:"vscode"}` → the four classes; `"WezTerm"` → `org.wezfurlong.wezterm`; `"ghostty"` → `com.mitchellh.ghostty`; `{nm_agent:"claude-desktop"}` → `null`; `"xterm"` → `null`.
  - `"no row names the shell or the app itself"`: no name in any row, lower-cased, is `explorer.exe`, `notchmeow.exe` or `notchmeow`.
  - `"the match gives the app's words"`: VS Code row with `code.exe` → `"VS Code"`, with `CURSOR.EXE` → `"Cursor"`, with `WindowsTerminal.exe` → `null`; `null` and `""` → `null`.
  - `"the race"` (fake timers: an array of pending callbacks): a read resolving `"Code.exe"` first → `"Code.exe"` and the timer was cleared; a never-resolving read, timer fired → `null`; a rejecting read → `null`.
  - `"words, dot and cat 2's line"`: `noteText("VS Code", "Runs") === "Waiting in VS Code: Runs"`; `noteText("Windows Terminal", null) === "Waiting in Windows Terminal"`; `noteText("  ", "Edits") === "Waiting in Claude App: Edits"`; `stepVerb("PowerShell") === "Runs"`, `stepVerb("Edit") === "Edits"`, `stepVerb("AskUserQuestion") === null`, `stepVerb("constructor") === null`; `showsDot` is true only for `(true, false, false)`; `showsNoteOverSecondLine` only for `(true, false)`.
  - `"marks"`: with `m = { sessionId:"S1", pillId:"integration_claude", host:"VS Code", kind:"permission", words:"Edits", at:1_000_000 }`: live at `at + 599_999`, gone at `at + 600_000`, live at `at - 5000`, gone at `at - 600_000`; a second mark of S1 replaces the first; `endMarks(…, "S1", "PreToolUse", "AskUserQuestion")` and `"Notification"` keep it; S2's `"Stop"` keeps it; each of `ENDING_EVENTS` with tool `"Bash"` ends it; 70 records keep 64, the oldest kept `at` is the seventh; `recordMark` and `endMarks` leave their inputs deep-equal to before; `markForSession` gives the newest of two pills' marks of one session; `lapseMs(1_000_000, 1_060_000, 5_000) === 545_000`.
  - `"the shared rules match the Swift"`: `FocusAware.swift` contains `static let markLifetime: Double = 600` (`MARK_LIFETIME_MS === 600 * 1000 === APP_WAIT_MS`), `static let marksMax = 64`, the `endingEvents` literal whose quoted names in order equal `ENDING_EVENTS`, and `!(event == "PreToolUse" && tool == "AskUserQuestion")`; `ProjectsRules.swift` contains `static let appWaitLabel = "Waiting in Claude App"` and `APP_WAIT_LABEL === "Waiting in Claude App"`.
  Run `cd windows && node --experimental-strip-types --test scripts/cat-tests/focusaware.test.mjs` → fails (module not found).
- [ ] **Step 2: Implement** `focusaware.ts` (header comment: the Mac twin is `FocusAware.swift`, the spec path, "pure: every time is a parameter; the only import is projects/core.ts") and `stepVerb` in `steps.ts` (after `stepLabel`).
- [ ] **Step 3: Run** the test → all pass; `npm run check:cat` and `npx --no-install tsc --noEmit` pass.
- [ ] **Step 4: Commit** the three files: `feat(focus): the pure rules of focus awareness (Windows and Linux)`.

---

### Task 2: Rust: the foreground read, the command, boot, the setting

**Files:**
- Create: `windows/src-tauri/src/foreground.rs`
- Modify: `windows/src-tauri/src/platform/windows.rs`, `platform/linux.rs`, `lib.rs`, `settings.rs`

**Interfaces:**
- Produces:
  ```rust
  // foreground.rs (pure, every platform; `mod foreground;` in lib.rs)
  pub fn image_base_name(full: &str) -> Option<String>            // last segment after '\' or '/', None when empty
  pub fn kind(windows: bool, pointer_feed: bool) -> &'static str   // "windows" | "x11" | "none"
  // platform/windows.rs and platform/linux.rs, same signature
  pub fn foreground_app(app: &AppHandle) -> Option<String>
  // lib.rs
  #[tauri::command] async fn foreground_app(app: AppHandle) -> Option<String>   // registered next to approval_decline
  BootInfo { …, foreground: &'static str }                         // serialized "foreground"
  // settings.rs
  #[serde(default = "default_true", deserialize_with = "bool_or_true")] pub focus_aware: bool   // JSON "focusAware"
  ```

- [ ] **Step 1: Write the failing tests.** In `foreground.rs`: `image_base_name(r"C:\Program Files\Microsoft VS Code\Code.exe") == Some("Code.exe")`, `("/usr/bin/kitty") == Some("kitty")`, `("Code.exe") == Some("Code.exe")`, `("") == None`, `(r"C:\dir\") == None`; `kind(true, false) == "windows"`, `kind(false, true) == "x11"`, `kind(false, false) == "none"`. In `settings.rs`'s test module, after `a_settings_file_without_open_on_hover_gets_it_off_and_keeps_it_when_set`, with the same `old` JSON: no `focusAware` → `true`, serializes `"focusAware": true`; `"focusAware":false` → `false`; `"focusAware":"no"` → `true` and `sound_volume == 0.12`; `"focusAware":null` → `true`. Run `windows/scripts/cargo-linux.sh test -p notchmeow foreground:: settings:: --target-dir /repo/windows/target/focus` → fails to compile.
- [ ] **Step 2: Implement `foreground.rs`** and, in `settings.rs`, the field after `hover_glow` (doc: "Step back when I'm already in the app (focus awareness): a permission request whose app is in front is declined at once so the agent asks there (on by default). A value that is not a Boolean reads as on."), `focus_aware: true` in `Default`, and `fn bool_or_true<'de, D: serde::Deserializer<'de>>(d: D) -> Result<bool, D::Error>` that deserializes a `serde_json::Value` and returns `v.as_bool().unwrap_or(true)`.
- [ ] **Step 3: Windows read** (`platform/windows.rs`), `foreground_app` only: `GetForegroundWindow` (null → `None`); `GetWindowThreadProcessId`; our own `std::process::id()` → `None` (Settings, the desktop cat, the chat); `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid)` (error → `None`); `QueryFullProcessImageNameW(handle, PROCESS_NAME_WIN32, …)` into a `[u16; 1024]`; `CloseHandle` on every path; `crate::foreground::image_base_name`. No logging; `_app` unused. (`Win32_System_Threading` and `Win32_UI_WindowsAndMessaging` are in `Cargo.toml`; `fullscreen_app_covers` already reads the foreground pid the same way.)
- [ ] **Step 4: Linux read** (`platform/linux.rs`), `foreground_app` only: `!pointer_feed()` → `None`. Else ask the main thread with `app.run_on_main_thread` and wait on a channel with `recv_timeout(Duration::from_millis(40))` (the `press_is_own` pattern; `None` on timeout). On the main thread: `gtk::gdk::Display::default()`; its raw `GdkDisplay*` (`ToGlibPtr`, imported already); `gdk_x11_display_get_xdisplay`; `gdk_x11_display_error_trap_push`; `XInternAtom(xd, "_NET_ACTIVE_WINDOW", True)` (`0` → `None`); `XGetWindowProperty(xd, XDefaultRootWindow(xd), atom, 0, 1, False, XA_WINDOW = 33, …)` → the window (`0` or no item → `None`; `XFree` the property); `XGetClassHint` → `res_class` as a `String` (`XFree` `res_name` and `res_class`); `gdk_x11_display_error_trap_pop_ignored`. `mod x11` gains `XInternAtom`, `XGetWindowProperty`, `XGetClassHint`, `XFree` and the `XClassHint` struct; a new `#[link(name = "gdk-3")]` block declares the three `gdk_x11_display_*` calls (GTK already links the library: no crate). Plan call: GDK's connection and error trap, because a `BadWindow` for a window closed between the two reads would reach Xlib's default handler, which exits the process. No logging.
- [ ] **Step 5: The command and boot** (`lib.rs`): `mod foreground;`; the command, async so the Linux main-thread hop never waits on the main thread itself:
  ```rust
  /// The foreground app's process image name (Windows) or window class (Linux under X11), read once for one permission request (focus awareness). Compared by the page and
  /// dropped: never logged, stored or sent anywhere. None where it cannot be read (Wayland, our own window, a failed read).
  #[tauri::command]
  async fn foreground_app(app: AppHandle) -> Option<String> {
      let a = app.clone();
      blocking(move || platform::foreground_app(&a)).await.ok().flatten()
  }
  ```
  Register `foreground_app,` after `approval_decline,`. `BootInfo` gains, after `claude_app`, `/// Which foreground read this system has for focus awareness: "windows", "x11" or "none" (Wayland). foreground: &'static str,`, filled after `claude_app: platform::CLAUDE_APP,` with `foreground: foreground::kind(cfg!(windows), platform::pointer_feed()),`.
- [ ] **Step 6: Run.** `windows/scripts/cargo-linux.sh test -p notchmeow foreground:: settings:: --target-dir /repo/windows/target/focus` passes; `… clippy -p notchmeow --target-dir /repo/windows/target/focus -- -D warnings` is clean for the new code; `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-focus` passes. Ledger: the Windows read was type-checked only and runs in `windows-tests.yml`.
- [ ] **Step 7: Commit** the five files: `feat(focus): read the foreground app once per request (Windows, Linux X11)`.

---

### Task 3: The page: `takeHook`, the marks, the Projects feed

**Files:**
- Create: `windows/scripts/cat-tests/focus-wiring.test.mjs`
- Modify: `windows/src/island/hooks.ts`, `core/bridge.ts`, `core/state.ts`, `main.ts`, `tests/fixtures/settings/controls.json`, `windows/scripts/cat-tests/sleep.test.mjs`, `cat-tests/two-cats.test.mjs`, `projects-tests/wiring.test.mjs`, `settings-tests/map.test.mjs`

**Interfaces:**
- Consumes: Task 1's exports; Task 2's `foreground_app` and `BootInfo.foreground`.
- Produces:
  ```ts
  // bridge.ts
  BootInfo.foreground: ForegroundKind;
  foregroundApp: () => call<string | null>("foreground_app"),
  // state.ts
  Settings.focusAware: boolean;                  // DEFAULT_SETTINGS.focusAware = true
  foregroundKind: ForegroundKind = "none";
  focusMarks: FocusMark[] = [];
  recordFocusMark(mark: FocusMark): void          // recordMark; no notify (handleHook notifies)
  endFocusMarks(sessionId: string, event: string, tool: string): void
  focusDot(pillId: string, now = Date.now()): boolean   // showsDot(markForPill(...) !== null, task?.pillBadge != null, this.pendingApproval?.pillId === pillId)
  // hooks.ts
  export function takeHook(island: Island, payload: HookPayload): void
  export function handleHook(island: Island, payload: HookPayload, stepBack?: FocusMark): void
  export function setDevForeground(name: string | null): void   // dev server only
  ```

- [ ] **Step 1: Write the failing pins** in `focus-wiring.test.mjs` (source read as text, comments blanked as `projects-tests/util.mjs` `code` does):
  - `hooks.ts`: `registerHookHandlers` subscribes `(payload) => takeHook(island, payload)`. `takeHook` calls `Bridge.foregroundApp` only inside `raceForeground(` with `FOREGROUND_WAIT_MS`; before asking it checks `focusEnabled(State.settings.focusAware)`, `State.foregroundKind !== "none"`, `payload.hook_event_name === "PermissionRequest"`, `!State.paused` and `routeHook(payload, State.claudeSessions) !== "chat"`; it calls `handleHook(island, payload)` and `handleHook(island, payload, mark)` and no other function of the island; no `setInterval`, `approvalDecision` or `log` in it.
  - `hooks.ts` `handleHook`: `State.endFocusMarks(focusSessionKey(payload), payload.hook_event_name ?? "", payload.tool_name ?? "");` then `if (stepBack) State.recordFocusMark(stepBack);` then `  Hub.sk?.hook(payload);`, all three after `handleChatHook(island, payload);`; `  State.projects.hook(payload, stepBack?.host);` once; in the `PermissionRequest` case `if (stepBack) {` comes before `if (isExternalAgent || fromClaudeApp) {` and its block holds `Bridge.approvalDecline(` and `break;` and none of `alert(`, `reveal(`, `Sound.play`, `setPillBadge`, `updateTask`, `isPinned`, `upsert(`, `ensurePill(`, `pendingApproval =`.
  - `main.ts`: `if (boot) State.foregroundKind = boot.foreground;`; the DEV line `__nm.hook` is unchanged and a new DEV line adds `take: (payload: HookPayload) => takeHook(island, payload)` and `foreground: setDevForeground` to `__nm`.
  - `bridge.ts`: `foregroundApp: () => call<string | null>("foreground_app"),`. `lib.rs` registers `foreground_app,` and has no `log::line` inside `async fn foreground_app`; `platform/windows.rs` and `platform/linux.rs` contain no `SetWinEventHook`, `EVENT_SYSTEM_FOREGROUND` or `XSelectInput`; `platform/windows.rs`'s `foreground_app` compares with `std::process::id()`; `platform/linux.rs`'s holds `recv_timeout(std::time::Duration::from_millis(40))`.
  - `state.ts`: `focusAware: true,` in `DEFAULT_SETTINGS`.
  Update the pins the new signature breaks: `sleep.test.mjs`'s `function handleHook\(island: Island, payload: HookPayload\) \{` becomes `function handleHook\(island: Island, payload: HookPayload, stepBack\?: FocusMark\) \{` (the rest of the regex as is); `two-cats.test.mjs`'s `export function handleHook\(island: Island, payload: HookPayload\)` becomes `export function handleHook\(island: Island, payload: HookPayload, stepBack\?: FocusMark\)`; in `projects-tests/wiring.test.mjs` both spellings of `"  State.projects.hook(payload);"` become `"  State.projects.hook(payload, stepBack?.host);"` (its order checks unchanged). The stored key's map, in the same step because `map.test.mjs`'s source scan fails as soon as `Settings` gains a field: in `controls.json`'s `island.focusAware` row, `"winHomes": [{ "page": "general", "tab": null, "card": "Island" }]` and `"win": [{ "key": "focusAware", "store": "settings" }]`; in `map.test.mjs`, `"focusAware"` after `"hoverGlow"` in `FROZEN.settings`, and the count line's message becomes `"the map holds 52 controls and winOnly's screen"` (the count stays `53`). Run `npm run check:cat` and `npm run check:projects` → the new and the updated pins fail.
- [ ] **Step 2: State, bridge, main.** `Settings.focusAware` (doc: "Step back when I'm already in the app (focus awareness), on by default.") after `hoverGlow: boolean;`, and `focusAware: true,` after `hoverGlow: true,`; the State members and methods above after `claudeApp = false;` (times are `Date.now()`, the wall clock, as the Mac's); `BootInfo.foreground` after `claudeApp: boolean;` and `Bridge.foregroundApp` after `approvalDecline`; in `main.ts`, after `if (boot) State.claudeApp = boot.claudeApp;`, `if (boot) State.foregroundKind = boot.foreground;`, the import gains `takeHook, setDevForeground`, and after the `__nm.sk` DEV line: `if (import.meta.env.DEV) Object.assign((window as unknown as { __nm: Record<string, unknown> }).__nm, { take: (payload: HookPayload) => takeHook(island, payload), foreground: setDevForeground });`.
- [ ] **Step 3: `takeHook`** (`hooks.ts`, before `handleHook`). When the five checks hold and `focusHost(payload, State.foregroundKind)` is non-null, `void` an async run: `const fg = await raceForeground(IS_TAURI ? () => Bridge.foregroundApp() : () => Promise.resolve(devForeground), FOREGROUND_WAIT_MS, setTimeout, clearTimeout)`; `const words = matchForeground(host, fg)`; `words === null` → `handleHook(island, payload)`; else `handleHook(island, payload, mark)` with `mark = { sessionId: focusSessionKey(payload), pillId: isClaudeDesktopTag(payload.nm_agent) || !validateAgent(payload.nm_agent) ? CLAUDE_ID : \`agent_${validateAgent(payload.nm_agent)}\`, host: words, kind: payload.tool_name === "AskUserQuestion" ? "question" : "permission", words: kind === "permission" ? stepVerb(payload.tool_name ?? "") : null, at: Date.now() }` (the pill by `handleHook`'s own rule, `validateAgent` reused). Every other event goes to `handleHook(island, payload)` at once. `setDevForeground(name)` stores `devForeground = name` and sets `State.foregroundKind = name === null ? "none" : "windows"`, so `takeHook` has no dev branch but the read. Plan call: an awaited read lets other sessions' events through first; the requesting session is blocked on this request and sends nothing meanwhile.
- [ ] **Step 4: `handleHook`.** Signature `handleHook(island: Island, payload: HookPayload, stepBack?: FocusMark)`. Right before `  Hub.sk?.hook(payload);`: `State.endFocusMarks(focusSessionKey(payload), payload.hook_event_name ?? "", payload.tool_name ?? "");` then `if (stepBack) State.recordFocusMark(stepBack);` (Plan call: endings before the feed, so the Sidekick reads the marks as they are now; the Mac's open item). `  State.projects.hook(payload);` becomes `  State.projects.hook(payload, stepBack?.host);` (P-tauri's `hook(payload, waitIn?)`: a step-back is a "Waiting in <host>" wait). In `case "PermissionRequest":`, first:
  ```ts
      // Focus awareness: the session's app is in front, so its own prompt is the place to answer. Declined at once (the agent asks there): no card, no sound, nothing opens.
      if (stepBack) {
        if (payload.request_id) void Bridge.approvalDecline(payload.request_id);
        break;
      }
  ```
  `registerHookHandlers` subscribes `takeHook`. (The kitten and `noteEvent` lines run as for a Claude app request today.)
- [ ] **Step 5: Run.** `npm run check:cat`, `npm run check:projects`, `npm run check:sidekick`, `npm run check:settings`, `node --experimental-strip-types scripts/check-claude-ui.mjs`, `npx --no-install tsc --noEmit` pass; `bash scripts/test-settings-map.sh` (the Mac's, which ignores the `win*` fields) still passes.
- [ ] **Step 6: Commit** the ten files: `feat(focus): step back to the session's app when it is in front (Windows and Linux)`.

---

### Task 4: The Sidekick: per-session hold and the lapse wake

**Files:** Modify `windows/src/sidekick/controller.ts`, `windows/src/sidekick/appenv.ts`, `windows/scripts/sidekick-tests/stuck.test.mjs`, `windows/scripts/cat-tests/focus-wiring.test.mjs`

**Interfaces:**
- Consumes: `State.focusMarks`, `markForSession`, `liveMarks`, `lapseMs` (Task 1/3).
- Produces (all optional, so the hand-built envs in the sidekick tests still type-check):
  ```ts
  // SidekickEnv
  stepBackEnd?(sessionId: string): number | null;   // the session's live mark's end on the Sidekick's clock, or null
  focusLapseAt?(): number | null;                   // the earliest live mark's end on the Sidekick's clock, or null
  focusLapsed?(): void;                             // a mark ran out: the app redraws
  ```

The Mac's `SidekickEngine` (`ruleLedger`, `focusLapseAt`), in this controller's shape:
- `private ruleView(): Ledger`: the ledger snapshot with every session whose `state === "approval"` and `this.env.stepBackEnd?.(s.sessionId) != null` given `pendingApprovalAt: null` (a copy; the ledger is not changed). Every `this.ledger.snapshot` that is passed to `stuckStep(` or `nudgeText(` (six places: `dropDueWhileAway`, `evaluate`'s loop, its `nudgeText`, its `clock.arm`, `rewordWaiting`, `stillTrue`) reads `this.ruleView()` instead; `signature`, `nudged`, `status`, `recap` and `deadline`'s give-up keep the real snapshot.
- `private focusLapseAt: number | null = null`. In `evaluate`: first, `const lapsed = this.focusLapseAt !== null && now >= this.focusLapseAt;` and clear it when true. The switch-off / away / rate-limit branch arms the lapse instead of stopping: `this.focusLapseAt = this.nextLapse(now); this.clock.arm(this.focusLapseAt);` (with no live mark this is `arm(null)`, today's `stop()`). The normal path ends with `this.focusLapseAt = this.nextLapse(now)` and arms the earlier of `this.deadline(…)` and it. After arming, `if (lapsed) this.env.focusLapsed?.();`. `nextLapse(now)` is `env.focusLapseAt?.()` when it is a number greater than `now`, else `null`. One wake per mark lifetime, re-armed only for the earliest live mark (owner 2026-10-22).
- `appenv.ts`, after `wait`: `stepBackEnd: (id) => { const m = markForSession(State.focusMarks, id, Date.now()); return m ? lapseMs(m.at, Date.now(), Date.now() + Skew.ms) : null; }`, `focusLapseAt: () => { const now = Date.now(); const ends = liveMarks(State.focusMarks, now).map((m) => lapseMs(m.at, now, now + Skew.ms)); return ends.length ? Math.min(...ends) : null; }`, `focusLapsed: () => State.notify()`.

- [ ] **Step 1: Write the failing tests** in `stuck.test.mjs` (the `rig` gains an optional `w.marks` map, sessionId → end time, wired to `stepBackEnd: (id) => w.marks.get(id) ?? null`, `focusLapseAt: () => (w.marks.size ? Math.min(...w.marks.values()) : null)`, `focusLapsed: () => w.lapsed++`):
  - `"a stepped-back session gets no waiting nudge while its mark lives; another session's still comes"`: S1 marked to `T0 + 10*MIN`, S1 `PermissionRequest`, S2 `PermissionRequest` (another session ID), `advance(MIN)` → exactly one `stuck.waiting` note, about S2's key.
  - `"the mark's end wakes the clock once, even with the switch off, and tells the app once"`: settings `{ on: false }`, S1 marked to `T0 + 10*MIN`, a `PermissionRequest` → one timer armed for `T0 + 10*MIN`; `advance(10*MIN)` → `w.lapsed === 1`; delete the mark, `advance(30*MIN)` → `w.lapsed === 1` and no timer armed.
  - `"two marks: the clock is armed for the earliest, then for the next"`: marks at `+5*MIN` and `+8*MIN`; armed at `+5*MIN`; after the first lapse (mark deleted), armed at `+8*MIN`.
  Append to `focus-wiring.test.mjs`: `controller.ts` holds no `stuckStep(this.ledger.snapshot` and no `nudgeText(n, this.ledger.snapshot` / `nudgeText(nudge, this.ledger.snapshot`, and `this.ruleView()` six times; `env.timer.set` is still asked for in one place (the existing pin in `stuck.test.mjs` line `ctl.split("env.timer.set")` stays green); `appenv.ts` passes `focusLapsed: () => State.notify()`. Run `npm run check:sidekick` → the new tests fail.
- [ ] **Step 2: Implement** the three optional members on `SidekickEnv` (doc lines from the Mac's `Env`), `ruleView`, `nextLapse` and the `evaluate` changes; `appenv.ts`'s three functions (imports `markForSession`, `liveMarks`, `lapseMs` from `../core/focusaware.ts`).
- [ ] **Step 3: Run** `npm run check:sidekick`, `npm run check:cat`, `npx --no-install tsc --noEmit` → pass.
- [ ] **Step 4: Commit** the four files: `feat(focus): the Sidekick holds a stepped-back wait and wakes once at its end (Windows and Linux)`.

---

### Task 5: The dot, the compact dots, the note, the Settings row

**Files:**
- Modify: `windows/src/views/views.ts`, `windows/src/island/island.ts`, `windows/src/settings/general.ts`, `windows/src/style.css`, `windows/scripts/settings-tests/pages.test.mjs`, `windows/scripts/cat-tests/focus-wiring.test.mjs`

**Interfaces:**
- Consumes: `State.focusDot(pillId)`, `State.focusMarks`, `markForPill`, `noteText`, `showsNoteOverSecondLine`, `State.cast`, `State.desktopNotchEmpty`, `State.pendingApproval`, the island's `botCx`/`botCy`/`botSize` and `bot2Cx`/`bot2Cy`/`bot2Size` springs, `this.pairShown`.

Plan calls (the spec leaves them to the builder; the Mac's `FocusWaitDot`, `FocusWaitNote`, `FocusWaitCompactDots` sizes): the pill dot is 8 px amber on a 10 px `#0b0c0e` ring at the badge's place (`top: -3px; right: 3px`), no icon, no shadow; the mini-grid and compact dots are a plain 5 px amber dot; nothing animates. The note is 11 px amber, one line with an ellipsis, on the Claude Code ticker card; with Projects' Claude-only layout the wait shows through Projects alone (as on the Mac).

- [ ] **Step 1: Write the failing pins.** Append to `focus-wiring.test.mjs`: `views.ts`'s pill key is `` `${t.id}:${t.pillBadge ?? ""}:${State.focusDot(t.id) ? 1 : 0}` ``; `buildAgentPill` has `else if (State.focusDot(task.id)) pill.append(h("div", { class: "fa-dot" }));` right after the `pill-badge` block; `tickerBody` is built `who, ticker.el, faNote, second`; `sync()` calls `markForPill(State.focusMarks, task.id, Date.now())` and `showsNoteOverSecondLine(` with `State.pendingApproval?.pillId === two.pill`; `island.ts`'s mini-grid key includes `State.focusDot(task.id)`, a dotted cell gets `fa-mini-dot`, and `fa-compact-dot` is placed from `this.botCx.value` / `this.bot2Cx.value` only when `State.mode === "compact"`; `style.css` has `.fa-dot`, `.fa-mini-dot`, `.fa-compact-dot`, `.fa-note` with `var(--nm-state-color-approval)` and no `animation`, and a rule `#island.wing-on .fa-compact-dot { filter: opacity(var(--nm-wing, 1)); }` of its own. In `pages.test.mjs`'s "General: the Sound and Island rows" test add: `switchRow("Step back when I'm already in the app"` is in `general.ts`, between the Open on hover and Hover glow rows, with `focusAware` and the Mac's help words. Run `npm run check:cat` and `npm run check:settings` → the new pins fail.
- [ ] **Step 2: The pill and the note** (`views.ts`). The pill key and the dot as pinned. `const faNote = h("div", { class: "fa-note" });` before `tickerBody`, which becomes `h("div", { class: "card-body" }, who, ticker.el, faNote, second)`. In `sync()`, right after the existing `second.textContent = …` line (the focused task is `State.focusTask`, the value `task` takes on the next line):
  ```ts
      const mark = State.focusTask ? markForPill(State.focusMarks, State.focusTask.id, Date.now()) : null;
      const showNote = showsNoteOverSecondLine(mark !== null, Boolean(two?.pill && State.pendingApproval?.pillId === two.pill));
      faNote.textContent = showNote && mark ? noteText(mark.host, mark.words) : "";
      faNote.style.display = showNote ? "block" : "none";
      second.style.display = showNote ? "none" : "";
  ```
  Plan call: in Two cats mode the note takes the second line's place, one line for one line, so the card's height is unchanged; in one-cat mode `second` is already hidden by CSS and the note is the line under the ticker, as on the Mac.
- [ ] **Step 3: The compact grid and the compact dots** (`island.ts`). The mini-grid key becomes `` row.map(({ task }) => `${task.id}:${State.focusDot(task.id) ? 1 : 0}`).join("|") ``, and a dotted cell gets `h("i", { class: "fa-mini-dot" })` appended to the slot `createMiniBot` returned. Two `fa-compact-dot` spans are made once beside `this.miniGrid` and appended to the island element; where the grid's opacity is set, each is shown (`opacity`) only while `showGrid` holds and its pill has `State.focusDot`: the big cat's (`State.cast.big.pill`, not while `State.desktopNotchEmpty`) at `left = this.botCx.value + this.botSize.value * 0.42 - 2.5`, `top = this.botCy.value - this.botSize.value * 0.42 - 2.5`; cat 2's (`State.cast.second?.pill`, only while `this.pairShown`) from the `bot2` springs the same way (the Mac's `d * 0.42`).
- [ ] **Step 4: Settings** (`general.ts`): after the `hover` row, `const stepBack = switchRow("Step back when I'm already in the app", { on: s0.focusAware !== false, help: "When an agent asks for permission or a question while its app is in front, it asks there: the island stays closed and quiet, and an amber dot on its pill shows it is waiting.", onChange: (v) => void ctx.save({ ...ctx.settings(), focusAware: v }) });` (the Mac's label and help); the Island card becomes `card("Island", null, hover.el, stepBack.el, glow.el, tuckRow, closeRow, screenRow)`; in `sync()`, after `glow.set(s.hoverGlow);`, `stepBack.set(s.focusAware !== false);`.
- [ ] **Step 5: CSS** (`style.css`, a new block at the end titled `/* ── Focus awareness: the waiting dot and note ── */`): `.fa-dot` (absolute, `top: -3px; right: 3px`, a 10 px `#0b0c0e` circle with an 8 px `var(--nm-state-color-approval)` circle inside, `pointer-events: none`), `.fa-mini-dot` (absolute, `top: -2px; right: -2px`, 5 px circle), `.fa-compact-dot` (absolute, 5 px circle, `pointer-events: none`, `opacity: 0`, `transition: opacity 0.25s ease-in-out` as the grid's), `#island.wing-on .fa-compact-dot { filter: opacity(var(--nm-wing, 1)); }`, `.fa-note` (`display: none; margin: 0 12px 0 108px; font: 500 11px var(--font); color: var(--nm-state-color-approval); white-space: nowrap; overflow: hidden; text-overflow: ellipsis;`) and `.overview.two .fa-note { margin-left: 147px; }`.
- [ ] **Step 6: Run.** `npm run check:cat`, `npm run check:settings`, `npm run check:sidekick`, `npm run check:projects`, `npx --no-install tsc --noEmit` pass.
- [ ] **Step 7: The pictures.** In `windows/`, start `npx vite` in the background and save its PID; open `http://127.0.0.1:1420/` in the browser pane; in the console: `__nm.foreground("Code.exe")`, `__nm.take({ hook_event_name: "PreToolUse", session_id: "S1", cwd: "/tmp/demo", tool_name: "Edit", tool_input: { file_path: "/tmp/demo/a.ts" }, term_program: "vscode" })`, then the same with `hook_event_name: "PermissionRequest", request_id: "r1"`. Screenshot the compact island (dot on the big cat), then the open island (the note "Waiting in VS Code: Edits" on the Claude Code card; a pill dot when another pill holds the focus). With `?display=two`, the same twice: cat 2 not waiting (the note takes the second line) and cat 2's pill holding the pending approval (the second line stays). Then `__nm.foreground("explorer.exe")` and a second `PermissionRequest` (`request_id: "r2"`) → the card opens as today; screenshot. Stop the server by its PID. Then `bash windows/scripts/render-settings.sh --page general --theme both` for the row.
- [ ] **Step 8: Commit** the six files: `feat(focus): the waiting dot, the note and the Settings row (Windows and Linux)`.

---

### Task 5b: Owner checkpoint 1

- [ ] The main session sends the owner the Task 5 pictures (compact dot, pill dot, note in one-cat and both Two cats cases, the card when the foreground does not match, the General page in dark and light) and waits for go.

---

### Task 6: Docs

**Files:** Modify `windows/README.md`, `docs/SPEC.md`, `CLAUDE.md`, `ARCHITECT.md`.

- [ ] **Step 1: `windows/README.md`**, in "What's different from the Mac version", one bullet: focus awareness covers permission requests only (no question card here, and no `--ask` hook, so nothing like the Mac's twin rule); Windows matches the Claude app, the VS Code family (`TERM_PROGRAM=vscode`, Cursor named as Cursor) and Windows Terminal (`WT_SESSION`); plain consoles and other terminals are not matched (the relay carries no marker for them); Linux matches only under X11 (the VS Code family, kitty, WezTerm, Alacritty, Ghostty by window class) and does nothing under Wayland; the foreground read waits 300 ms at most; the process and class names are unverified on real machines, and a mismatch only means the card shows as today; the setting is General → Island, `focusAware` in `settings.json`.
- [ ] **Step 2: `docs/SPEC.md`**, at the end of item 11 « Se retirer quand on est déjà dans l'app », add: « Windows et Linux (`windows/src/core/focusaware.ts`) : mêmes règles pour les demandes de permission (il n'y a ni carte de question ni crochet `--ask`) ; l'app au premier plan est lue une fois par demande en Rust (`foreground_app` : le nom du processus sous Windows, la classe `WM_CLASS` de `_NET_ACTIVE_WINDOW` sous X11), en 300 ms au plus, sinon la carte s'affiche comme avant. Windows reconnaît l'app Claude, la famille VS Code (`TERM_PROGRAM=vscode`) et Windows Terminal (`WT_SESSION`), pas les consoles simples ; Linux, sous X11 seulement, la famille VS Code, kitty, WezTerm, Alacritty et Ghostty ; sous Wayland, rien ne change. Le réveil unique à la fin des 10 minutes passe par l'horloge du compagnon, comme sur Mac. Réglage : Réglages → General → Island, clé `focusAware` de `settings.json` (une valeur qui n'est pas un booléen vaut « activé »). »
- [ ] **Step 3: `CLAUDE.md`**: append to the `FocusAware.swift` bullet: "The Windows/Linux twin is `windows/src/core/focusaware.ts` (permission requests only; `focusaware.test.mjs` with drift pins against `FocusAware.swift`, `ProjectsRules.swift` and the Sidekick ledger's session key), fed by `island/hooks.ts` `takeHook`, which asks Rust's `foreground_app` (`platform::foreground_app`: the process image on Windows, never our own; `_NET_ACTIVE_WINDOW`'s `WM_CLASS` through GDK's X connection under X11; nothing under Wayland; `BootInfo.foreground`) once per request, at most 300 ms, only with `focusAware` on, outside a chat's own run and with a host in the table; Projects gets `State.projects.hook(payload, stepBack?.host)`; the Sidekick holds per session (`SidekickEnv.stepBackEnd`) and wakes once per mark (`focusLapseAt`, `focusLapsed`)." Append to the bounded-exception bullet: "Windows/Linux: the same wake through the stuck clock (`sidekick/controller.ts`), armed even with the Sidekick off."
- [ ] **Step 4: `ARCHITECT.md`**: on the "Focus awareness:" line, replace `Windows/Linux: \`windows/src/core/focusaware.ts\`, the foreground read in Rust.` with `Windows/Linux: \`windows/src/core/focusaware.ts\` through \`island/hooks.ts\` \`takeHook\`, the foreground read in Rust (\`foreground_app\`, once per request, 300 ms at most).`; append to the bounded-exception line: "Windows/Linux: the stuck clock of `sidekick/controller.ts`, the same rule."
- [ ] **Step 5:** `npm run check:cat` still passes; `bash scripts/check-no-leftovers.sh` passes. **Commit** the four files: `docs(focus): focus awareness on Windows and Linux`.

---

### After Task 6: whole-branch review

`nm-reviewer-deep` (Sonnet 5.5, high, trigger 4) on `git diff main...HEAD`, with `security-review`, `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` (`model: sonnet`). It checks: the only new reply is `approvalDecline`; the page never waits more than 300 ms before the card path's ack; the Linux main-thread wait is bounded at 40 ms and the command is async; no foreground hook or poll exists; the one new wake is the stuck clock's, once per mark, also with the Sidekick off, never repeating; the foreground name is in no log line, `State` field, ledger entry or event (only the table's words reach the mark); a Wayland session never calls the command; a chat's own run never steps back; the stepped-back branch touches no alert, sound, pin, badge or pill; the full `npm run check:*` set and `tsc` pass; Windows-only code was type-checked, and the ledger says what CI must still run. One fix round, then stop before any merge.

---

### Task 7: Owner checkpoint 2: real machines

The owner, on a Windows PC with the built app (the main session never launches it):

1. A Claude Code session in VS Code's terminal, VS Code in front, a tool that needs approval → VS Code asks at once; the island stays closed and silent; the Claude Code pill shows the dot; the card shows "Waiting in VS Code: <verb>"; Projects shows "Waiting in VS Code"; the next tool or the Stop removes them. With File Explorer in front → the card, as today.
2. The same in Windows Terminal (in front) → step back; in a plain PowerShell console window → the card, as today (known limit).
3. A request left unanswered for 10 minutes → the dot and the note go by themselves, with the Sidekick on and with it off.
4. Settings → General → Island, the switch off → the card, as today.
5. If a name did not match: the owner reports the process name in Task Manager's Details tab for VS Code, Windows Terminal and Claude, and the table in `focusaware.ts` is corrected (spec call 5).

On a Linux X11 session: check 1 with VS Code and with kitty or WezTerm; on a Wayland session: the card always shows, as today.

---

## Questions for the owner

None new. Every design choice here is the Mac's or a spec call; the ones this plan makes on its own (the 300 ms race, the per-app words such as "Windows Terminal", the X11 class table, endings before the Sidekick's feed) are marked "Plan call" where they sit, and real-machine checks of the names are owed (Task 7, spec call 5).

## Self-review

- Spec coverage: the Windows and Linux host tables → Task 1; "the foreground read in Rust, one function each, called once per request through one Tauri command" → Task 2; rules 1 to 8 → Tasks 1 and 3 (rule 1's question half: the `AskUserQuestion` permission request only, there is no `--ask` path); "The Projects fit" → Task 3 (`waitIn`); the dot (call 3 after the check: badge place, amber, no number, a badge or a waiting card wins) → Tasks 1 and 5: Plan call, drawn at the badge's place but not stored in `pillBadge`, because `setFocus` and the Stop timer clear `pillBadge` and the mark must last to rule 4's end; the compact dot (call 2) → Task 5; the cat-2 line rule → Tasks 1 and 5; the switch, its key and a non-Boolean as on → Tasks 2, 3, 5; the Sidekick check and the one wake (call 8) → Task 4; `ensurePill`/`upsert` never run for a step-back → Task 3 pin; own chat never steps back → Tasks 2 and 3; calls 4 and 5 after the check → Task 6 README and Task 7.
- Types: `FocusMark`, `FocusHost`, `FocusApp`, `ForegroundKind` are defined in Task 1 and used unchanged in Tasks 3 to 5; `BootInfo.foreground` is `&'static str` in Rust and `ForegroundKind` in TypeScript with the same three values; `stepBack?.host` is a `string`, as `ProjectsModel.hook(payload, waitIn?: string)` takes.
- Proportion: about as long as the old plan, shorter than the code it describes; code blocks only for the command, the decline branch and the `bool_or_true` shape.

## Dry run

Walked each task as its implementer against `main` at `0997356d`:

- Every Task 0 anchor occurs once (checked with `grep -cF`). `controls.json` holds the `island.focusAware` row with `"winHomes": []` and `"win": []`; `map.test.mjs` asserts 53 entries and counts that row already, so filling it changes no count; `FROZEN.settings` does not list `focusAware`, and the "source scan, settings" test fails as soon as `Settings` gains the field, so the row, the frozen key and the field land together in Task 3.
- `sleep.test.mjs` and `two-cats.test.mjs` spell `handleHook`'s two-parameter signature: updated in Task 3. `two-cats.test.mjs` also pins the `__nm.hook` DEV line exactly: kept, the new names go in a separate `Object.assign` line. `check-claude-ui.mjs` needs `routeHook(` before `hook_event_name ?? ""` inside `handleHook`: the new lines use `payload.hook_event_name ?? ""` after the chat return, so the first `hook_event_name ?? ""` stays after `routeHook(`. `tuck-wiring.test.mjs` needs `island.agentActivity();` within 200 characters after `Hub.sk?.hook(payload);`: the new lines go before the feed, not between.
- `projects-tests/wiring.test.mjs` pins `"  State.projects.hook(payload);"` twice in one test and no `return` between the Sidekick's feed and it: both spellings change, and the new lines sit before the feed.
- `u1b-wing-wiring.test.mjs` and `projects-tests/island.test.mjs` pin the `#island.wing-on` block's selector list: the compact dots get their own rule.
- `projects/model.ts` `hook(payload: unknown, waitIn?: string): boolean` exists; `projects/core.ts` exports `waitLabel`, `APP_WAIT_LABEL`, `APP_WAIT_MS` (600 000).
- `ProjectsRules.swift` holds `static let appWaitLabel = "Waiting in Claude App", homeName = "Home"` (the pin matches the prefix up to the closing quote); `FocusAware.swift` holds `static let markLifetime: Double = 600` followed by spaces and a comment, `static let marksMax = 64`, the `endingEvents` literal and the `!(event == "PreToolUse" && tool == "AskUserQuestion")` clause.
- `sidekick-core.js` `eventFrom` gives `sessionId` as `cap128(first non-empty of session_id, conversation_id) || 'unknown'`; `focusSessionKey` is pinned to it.
- `controller.ts` passes `this.ledger.snapshot` to `stuckStep`/`nudgeText` in six places (lines 301, 335, 340, 347, 375, 383); `evaluate`'s switch-off branch calls `this.clock.stop()`, which the lapse replaces with `arm(nextLapse)`; the existing "no nudge and no clock" tests have no marks, so `arm(null)` keeps them green. `StuckClock.arm(null)` stops. `Hub.sk` is made unconditionally in `main.ts`, so the wake exists with the Sidekick off.
- `views.ts`: `second` is `display: none` in one-cat mode and `display: block` under `.overview.two`; hiding it with inline `display: none` while the note shows keeps one line for one line. The Claude-only layout returns before the ticker code, so the note is never drawn there (Projects shows the wait). The dot is in `buildAgentPill`, which the Projects grid also calls for the other agents' pills.
- `island.ts`: the mini grid's key and `createMiniBot(task, 13, cat)` are in the compact-grid block, where `showGrid` is computed; `this.pairShown`, the `bot*` springs and `State.desktopNotchEmpty` exist.
- `general.ts` has no tabs; `switchRow` returns `{ el, set }`; `pages.test.mjs` checks the Island card's rows by substring, so an added row breaks nothing and the new assertion is added there.
- `lib.rs`: `blocking` exists (`spawn_blocking`); `boot` builds `BootInfo` with `claude_app: platform::CLAUDE_APP,`; `approval_decline,` is in the invoke list once. `platform/linux.rs` has `mod x11` (`#[link(name = "X11")]`), `press_is_own` (main-thread hop, 40 ms), `pointer_feed()` false under Wayland and under XWayland in a Wayland session, and imports `ToGlibPtr`. `platform/windows.rs` imports `GetForegroundWindow`, `GetWindowThreadProcessId`, `CloseHandle`, `HANDLE`, and `Win32_System_Threading` covers `OpenProcess` and `QueryFullProcessImageNameW`.
- `settings.rs` fields are typed: a non-Boolean would fail the whole file under plain `serde(default)`, hence `bool_or_true`; `default_true` exists.
- The relay (`windows/hook/`) has no `--ask` path and answers Gemini and Antigravity itself, so their `PermissionRequest` rarely reaches the page; a chat's `claude` inherits NotchMeow's environment (only the login variables are stripped), so `WT_SESSION` could be set: the chat route return and the own-pid check both cover it.
