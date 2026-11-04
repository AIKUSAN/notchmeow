# P-tauri: the Projects view on Windows and Linux: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows/Linux app (`windows/`) shows every live Claude Code project and its sessions as the Mac does since P-mac: project pills and a big card when Claude Code is the only agent, a count capsule, a chevron and an expandable section with other agents, a Projects screen, a hover peek on the left card, a project cat per project (with its coat, kittens and mood on the big cat), a compact waiting count and a tray item, all from the hook events it already receives.

**Architecture:** The rules are `shared/projects-core.js`, copied into `windows/src/projects/core.generated.ts` by a new `scripts/gen-projects-ts.mjs` (the sidekick's pattern) and typed by `projects/core.ts`; `npm run check:projects` replays all eight fixtures of `tests/fixtures/projects/` and the Mac's scripted scenarios against the copy, in CI. One memory-only `ProjectsModel` (`projects/model.ts`) holds the registry, the step words, the pin, the last click, the peek, the panel flag and the layout; `island/hooks.ts` feeds it right after the Sidekick, before anything can refuse the event. The page computes one `ProjectsFrame` per read (`State.projectsNow()`); the island's own rules and words are ports of the Mac's `ProjectsLayout` (`projects/cells.ts`, `projects/present.ts`); the views (`views/projects.ts`) render the frame. Rust changes only where it must: the `projectCats` clean-up in `cat_settings.rs` and one tray item. A small Task 0b first adds the two hostile-input caps P-mac found to the shared core.

**Tech Stack:** TypeScript (Node 22 `--experimental-strip-types` tests; erasable syntax only: no enums, namespaces or parameter properties; `.ts` extensions in imports the tests load), CSS, Rust (Tauri 2, `serde_json`; run through `windows/scripts/cargo-linux.sh`), the Vite dev server for the checkpoint pictures; Task 0b also JavaScript (the core) and the Mac's `swiftc` test scripts.

**Spec (binding):** `docs/superpowers/specs/2026-10-17-projects-view-design.md`. **Contract:** `shared/projects-core.js`, `tests/fixtures/projects/` (eight files), `docs/PROJECTS-CONTRACT.md`. **The Mac is the reference** (merged at `5d4cb85b`): `docs/superpowers/plans/2026-10-17-p-mac-projects.md` (its "Plan calls" and "Owner's answers (2026-10-20)"), the archived ledger `.claude/archive/sdd/p-mac-projects/2026-10-17-p-mac-projects/progress.md` (the checkpoint rulings), `NotchBuddy/Sources/App/Projects*.swift`, `CatSettingsView.swift`'s Project cats card and `tests/Projects*Tests.swift`. **Settings:** `docs/superpowers/specs/2026-10-17-settings-restyle-design.md` (answers 6 and 7) and CLAUDE.md's "Settings on Windows and Linux" bullet.

**Base:** a new branch `p-tauri/projects` in a git worktree, from `main` at `684e015c` or later (`git merge-base --is-ancestor 684e015c HEAD` and `git merge-base --is-ancestor 5d4cb85b HEAD` must both succeed). If a find text below no longer occurs exactly once because the base moved, stop and report; do not guess.

## Refresh 2026-10-21

What it builds is the same feature; these changed since the 2026-10-17 draft (P-mac merged, the Windows/Linux Settings restyle merged, the title-row fixes merged):

- Base moved from `414d89e6` to `684e015c`; every anchor was re-counted there (Task 0, "Dry run").
- New Task 0b: the core gets P-mac's two hostile-input caps (`CWD_MAX_BYTES` 4096, `PENDING_MAX` 16) with fixture cases, so both ports replay them; the Mac's four count pins in `tests/ProjectsRegistryTests.swift` and one stale comment change with it.
- The "(M)" calls are settled by P-mac, Mac is primary: each now matches the Mac's code, and the "main session settles it at Checkpoint 1" mechanism is gone.
- Claude-only grid: the Mac's `gridCells` (4 cells; past 4 projects, 3 projects and "+N" that opens the screen; leftover cells for the other pills, owner's answer 1).
- With other agents: the title row gets only a fixed count capsule (projects, and an amber waiting one) and the chevron; "N projects · M waiting" is the first line of the section (P-mac checkpoint 2), never squeezed into the title row.
- The section is one row of three (`panelCells`, "+N" top-aligned on the pills' row), 92 px (overview 160 → 252), each tile a pill with "N sessions · ago" under it; no subagent heads there (the Mac has none).
- The big cat in the Claude-only card follows the big card's project entirely: coat, kittens and state (owner's answer 3); Two cats mode keeps today's overview entirely, no chevron, no section (P-mac ruling).
- The big card keeps its ↗ and its title never leaves an orphan "·": the folder truncates, "· N sessions" stays whole; a same-name project shows its parent on a line of its own, on the card and on the pill (`pillNameParts`).
- The peek is exactly the left card's box; its lines are capped to fit with "+N more"; its header's count stays whole; the big cat and its kittens step aside while it shows.
- The Projects screen is 240 px, top-aligned, scrolls, starts at island x 90 with the cat beside it, and ends 22 px (the corner radius) under its last row.
- Pills keep a stable identity: the views key them by `cellKey`, never by slot, so Pin never pins the wrong project and a peek never sticks; Pin holds the island 0.5 s past the menu (P-mac checkpoint 2).
- The "… ago" one-shot became the Mac's tick: one one-shot due at the nearest of 60 s and the next time-based boundary (`nextDelay`), only while expanded with a live project.
- Words follow `ProjectsLayout`: "now" (not "just now"), "Terminal", the badge's title "Projects, N waiting", the empty Settings sentence and the 256 help line; a pick that would evict another project's stored cat is refused.
- The compact count reuses the shelf badge's rules and spot (waiting first): the Mac's place, 66 px from the right edge, is inside the 184 px middle on Windows/Linux (Questions for the owner, 1).
- Settings moved with the restyle: "Project cats" is a card of Cat → Agents' cats, built in `settings/cat.ts` from the kit (`card`, `row`, `setValue`), live names through `SettingsBackend` (`askProjectsLive`, `"projects-live"`), and the map gains `cat.projectCats` (`win`, Task 2) and the card (`winHomes`, Task 9); `settings/display.ts` and `settings/main.ts` are no longer touched.
- Title rows: the active row keeps `labelGivesWay` (`views/titlefit.ts`) with the capsule beside it; the idle row gets the same whole-or-nothing rule only while the capsule is in it (the Mac's `ProjectsTitleFit`); without the capsule both rows are as shipped.
- Tests can fail: comment-blind source pins (`code()`), fixture groups with literal row counts, and the Mac's scenario fixture replayed through the Windows model (P-mac's wave 2 lessons).
- Four pins change on purpose in Task 7 (big cat coat, collar, dance, wardrobe line) and two in Task 2 (`display.test.mjs` lines 90 and 96); they are named where they change.

## Global Constraints

Every task's requirements include this section.

- **The contract decides.** Only Task 0b edits `shared/projects-core.js`, `tests/fixtures/projects/` and the generator. The Windows app carries no hand-made port of the core's rules: only the generated copy, typed by `core.ts`. If an app test and a fixture disagree, the core is right. `tests/fixtures/settings/controls.json` changes only by Task 2's and Task 9's additions; `tests/fixtures/mac/projects-scenarios.json` is read, never written.
- **Mac is primary.** Windows/Linux gets at most what the Mac gets, with the Mac's names and words (`ProjectsLayout.swift`): the view `projects`, the screen "Projects", the card "Project cats", `No Claude Code session is running.`, `Waiting in Claude App` (the core's), "Claude App" / "VS Code" / "Terminal", "now" / "N min ago" / "N h ago". Windows/Linux has no global shortcut (CLAUDE.md: the Mac's ⌃⌥P is Mac-only) and no menu-bar item (the tray item is its twin).
- **Nothing that ships is restyled.** Additions only: the folder tab after `+`, the count capsule and chevron in the Claude Code card's title row (with other agents), the section under the two cards, the Claude-only card and grid (only while a project is live, the focus is Claude Code or none, and Two cats is off), the compact waiting count, the tray item, the Settings card. With the projects layout not in use, the overview renders exactly as on `main` (pinned).
- **0 % CPU when the island is hidden, no polling.** No `setInterval`, no new `requestAnimationFrame` loop, no thread. Two one-shots: the projects tick (armed only while the island is expanded with a live project, due at `nextDelay`, cleared on fold) and the peek's dwell (`PEEK_DWELL_MS` = 400, armed on a pill's `mouseenter`, cleared on `mouseleave`, on fold and when its project leaves); plus the Pin menu's 500 ms release (one `setTimeout` per menu). The waiting dot pulses (CSS) only while the island is expanded; the compact count is still. Time-based states are computed when the page reads the registry.
- **Waiting is a count, never an alert** (spec call 7): feeding the registry never opens, reveals, holds or pins the island, never calls the desktop cat, plays no sound; `State.attentionNeeded` and `island/tuckaway.ts` are not touched.
- **Privacy** (spec call 1, contract "What never leaves memory"): a session's full `cwd` lives only in `ProjectsModel` (memory), is read only by the jump (`cwdOf`, handed straight to `Bridge.openInVSCode`), and is never shown, logged, stored, sent to another window or put in a fixture or picture. Views, the tray text, the page events and the stored settings carry folder names, worktree names, roles, state words, host words and step words only. Step words never carry a command or a query (`Runs`, `Web search`, `Reads · a.ts`). A leak test pins it.
- **Frozen values.** Pill IDs, cat IDs, display mode IDs, the relay (`windows/hook/` unchanged: it forwards `cwd`, `session_id`, `agent_id`, `agent_type`, `term_program`, `hook_event_name`, `tool_name`, `message`, `nm_agent` = `claude-desktop`, and drops transcripts and the assistant's words), existing event names. New: the island view `projects`, the `cat` block key `projectCats` (map key `cat.projectCats`), the tray item id `projects`, the command `projects_menu_text`, the page events `projects-live` and `projects-live-ask`.
- **Never block Claude Code:** the feed is synchronous, never throws (the core returns `null` for anything it does not know), never waits; the PermissionRequest ack paths in `hooks.ts` are unchanged.
- **Rust** runs as `windows/scripts/cargo-linux.sh test -p notchmeow <filter> --offline --target-dir /repo/windows/target/p-tauri` when Docker is up; when it is down, mark the step "needs Docker". No new crate. The Windows-only branches are compiled by `windows-tests.yml`, never claimed here.
- **Models and commits** (CLAUDE.md, "Working with AI agents"): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local, never pushed, lists only its task's files, and ends with `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` (or `Claude Sonnet 5.5` for an escalated task).
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app; no task sends an event to a real hook socket. A `vite` dev server on `127.0.0.1` may run; stop it only by the PID you saved.
  2. Install nothing, download nothing, no `docker build` or `docker pull`. If `windows/node_modules` is missing, symlink the main checkout's (gitignored).
  3. Use `trash`, never `rm -rf`; scratch files go under `${TMPDIR:-/tmp}` in a uniquely named folder.
  4. Never edit `shared/projects-core.js`, `scripts/gen-projects-fixtures.mjs`, any file under `tests/fixtures/`, `design/prototype/cat-core.js`, `windows/hook/`, a generated theme file or anything under `NotchBuddy/` or `tests/*.swift`, except where your task's **Files** list names it. `windows/src/projects/core.generated.ts` is written only by `node scripts/gen-projects-ts.mjs`.
  5. Never push. Commit only in a task's commit step, after checking `git rev-parse --show-toplevel` is this worktree and `git branch --show-current` is `p-tauri/projects`.
  6. Never rename a frozen ID; write no `Coucou` or `Mochi` anywhere; no real user or machine name in a sample (`settings-tests/privacy.test.mjs`).
  7. Never read, print or write the real `~/.claude`, `~/.gemini` or `~/.codex`; the fake paths in tests start with `C:/dev/`, `C:\\dev\\` or `/home/dev/`.
  8. If a command is refused by a permission prompt, or a find text occurs zero or two times, stop and report; do not look for a workaround.
  9. A pin you break is fixed by changing the code back, unless your task names that pin as one to update.
  10. Skills: `ponytail:ponytail`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`; for Rust also read `~/.claude/plugins/marketplaces/ecc/skills/rust-patterns/SKILL.md` and `.../rust-testing/SKILL.md` (only the parts that fit). Ponytail never cuts a test, a privacy rule or what this plan asks for.

## Review Focus

The spec is silent on these; each would bite a person first (most likely first) and names the test that pins it.

1. **A Claude App session's request is answered `ask` at once by `hooks.ts`** (`Bridge.approvalDecline`). A feed placed after that branch would never count it. Expected: the feed is right after `Hub.sk?.hook(payload);`, before the `switch`; the session shows `approval` with `Waiting in Claude App` and counts. Tests: Task 4 (wiring order, comment-blind), Task 3 (model: a `claude-desktop` PermissionRequest is waiting 1 with the note, and ends after 10 min).
2. **A chat's own `claude -p` run** sends the same hooks and must not become a project. Expected: the feed is after the `routeHook(...) === "chat"` return. Test: Task 4.
3. **Pills reorder while the pointer is on one or its menu is open** (a waiting project jumps first, any tool event reorders). Expected: a pill's element, its peek and its Pin target follow its project, never its slot; a peek whose project leaves closes; a pin on a project that ended while the menu was open is not taken. Tests: Task 3 (`togglePin` ignores a project that is not live; `frame()` clears `peeking` when its project leaves; `cellKey`), Task 5 (the views key elements by `cellKey`, `ProjectPeek.sync` leaves a gone project).
4. **Windows paths**: `C:\Users\sam\Code\app\.claude\worktrees\p1`, a lower-case drive letter, a trailing backslash. Expected: one project `app` with a side session `p1`; no name, label or step holds `\` or `/`. Test: Task 3 (model test).
5. **The island folds or hides while a peek, the tick or the Pin menu's release is pending.** Expected: the peek and the tick are cleared on fold; nothing runs while hidden; the compact count never reveals or expands. Tests: Task 3 (`ProjectsTick`, `PeekDwell` with a fake timer), Task 7 (wiring: the tick's sync condition, `leaveAllPeeks()` on fold, no timer in `projects/*.ts`).

Also pinned: the Settings window opened before any project or reopened later asks the island for the live names and gets them on each change (Task 9); a pick that would evict another project's stored cat is refused (Task 2); the core's caps, including Task 0b's, come from the fixtures (Task 1); a non-finite clock never ages anything (Task 1).

---

## The Windows design

**Where the rules live.** `ProjectsModel` is the one holder (`State.projects`), made once in `main.ts` with the home folder from `boot.home` and the clock `() => Date.now() + Skew.ms` (the Sidekick's dev skew). The feed takes an optional `waitIn`; this plan never passes it (focus awareness on Windows/Linux is `2026-10-17-focus-awareness-tauri.md`; whichever of the two plans merges second passes the host at the PermissionRequest path, and the two never run side by side: both edit `hooks.ts`, `island.ts`, `views.ts`, `style.css`, `lib.rs`).

**Claude only, and the four slots.** The pills passed to `claudeOnly` are `settings.activeIntegrations` plus the ids of `State.tasks`. `activeIntegrations` holds both the services and the agent switches (`agent_gemini`, `agent_antigravity`, at most four together, `core/state.ts` `toggleIntegration`); a switched-on agent's pill stays (idle) and its `agent_*` id counts as an agent in the core, so a switched-on agent means "with other agents" even while it is idle, as an enabled agent pill does on the Mac. A transient `agent_*` pill counts while it exists. The layout follows `islandLayout` (kept while open, re-read when folded); the Claude-only card is used only while `usesProjects` holds (the layout is `projects`, a project is live, the focus is Claude Code or none, Two cats is off).

**The Claude-only card.** Left card: the big card (`bigCardOf`: pin, else last click, else the most recent): the state dot, the folder part of the name (truncates first) and "· N sessions" (whole), the parent on its own line for a same-name project, the step (or the state words, amber while waiting), `<host> · <ago>`; a click on the card or its ↗ brings the newest session's app forward (↗ hidden only when the route is `none`). Right card: the existing 2×2 pill grid filled by `gridCells` (projects in pill order, then the other pills of `State.pillRow` while they fit; past four projects, three and "+N", which opens the screen). The big cat wears the big card's project cat, shows its state and draws that project's subagents as its kittens; cat 2 does not exist here (Two cats keeps today's overview).

**With other agents.** On the Claude Code card's title row (active or idle), while it is focused, a project is live and Two cats is off: a fixed capsule with the project count, an amber one with the waiting count when above 0, and the chevron (`chevronShown`). The name and its label give way first (the label whole or not drawn: `labelGivesWay`). The chevron toggles the panel flag (memory, spec call 5): the island grows by `PANEL_EXTRA` = 92 (160 → 252) on the existing spring; the section under the two cards shows "N projects · M waiting" (the waiting part amber) and one row of `panelCells` (three columns, "+N" top-aligned), each tile a pill and "N sessions · ago" under it, the big card's project outlined. Focusing another pill hides it (the flag is kept).

**The Projects screen.** The island view `projects`: 240 px, the small cat at the left (x 46, Ø44, the shelf's), the list top-aligned at island x 90, scrolling, ending 22 px under its last row. One section per project (its cat, its name, "N waiting" in amber when above 0), its sessions as rows (dot, label, the note in amber else the step, `<host> · <ago>`), each subagent indented under its session (a small cat of the project's coat and its type or "subagent"). A row's click opens the approval card when that session owns `State.pendingApproval`, else brings its app forward. Opened from the folder tab after `+` (title "Projects"), the tray's **Projects** item (`Projects (N)`, `Projects` at 0), a "+N" cell, and a click on the compact count. Empty: `No Claude Code session is running.`

**The jump.** `openRoute("integration_claude", State.claudeApp, host === "claude-app")` (`core/openagent.ts`): `claude-app` → `Bridge.openClaudeApp()`, `vscode` → `Bridge.openInVSCode(State.projects.cwdOf(id))` (as the Claude Code pill's ↗ does today for any terminal), `none` (Linux, a Claude App session) does nothing.

**Pin.** A right-click on a project pill (either layout): one native menu item, `Pin` or `Unpin`, built once and reused like the Wardrobe menu, holding the island while open and 500 ms after it closes (`PIN_MENU_RELEASE_MS`, P-mac's fix: the click that chose the item must not fold the island). The pin is taken only for a live project. Outside Tauri (the dev server) the right-click toggles the pin directly.

**The peek.** After 400 ms on a project pill, the left card's own box (absolute, inset 0, its radius) shows that project: its name (truncates first) and "N sessions" (whole), then its session and subagent lines, `peekLineCapacity(cardH)` of them with "+N more" when cut (4 on Windows/Linux's 108 px card; the Mac's 98 pt card gives 3: one rule). `pointer-events: none`; the big cat and its kittens step aside while it shows.

**The compact waiting count.** The shelf badge's rules (`badgeShown`, `badgeLabel`, `badgePlace`) with the waiting count, amber, title `Projects, N waiting`; while it shows, the shelf badge does not (one spot, waiting first; Questions for the owner, 1); a click opens the Projects screen. Like the shelf badge, it lands only while the wing rule is inactive (the owner's answer 4 on the Mac: a signal; the folder tab and the tray reach the screen).

**Project cats.** `projectCats` in the `cat` block, cleaned by `cleanProjectCats` in `cleanCatBlock` and by a Rust twin in `clean_cat_block`. Settings → Cat → Agents' cats gains the card "Project cats" after "Cats for your agents", in every display mode: one row per live project (its name, in pill order) then per stored-only folder name (UTF-16 order), each a kit `row` with a live preview, the cat picker and, on a stored one, Reset; the empty sentence and the 256 help line are the Mac's. The live names reach the Settings window as page events (`projects-live` from the island, `projects-live-ask` from Settings), through `SettingsBackend`.

## File Structure

| Path | Responsibility | Task |
|---|---|---|
| `shared/projects-core.js`, `scripts/gen-projects-fixtures.mjs`, `tests/fixtures/projects/{event,registry}-cases.json` (generated), `tests/projects/paths.test.mjs`, `docs/PROJECTS-CONTRACT.md`, `scripts/print-projects-tables.mjs`, `tests/ProjectsRegistryTests.swift`, `NotchBuddy/Sources/App/ProjectsRegistry.swift` (comment only) | The core's two caps, their cases, the Mac's counts | 0b |
| `scripts/gen-projects-ts.mjs` (new), `windows/src/projects/core.generated.ts` (generated), `windows/src/projects/core.ts` (new), `windows/scripts/projects-tests/{util.mjs,fixtures.test.mjs,fresh.test.mjs,util.test.mjs}` (new), `windows/package.json`, `.github/workflows/windows-tests.yml` | The generated copy, its types, the replay, `check:projects` in CI | 1 |
| `windows/src/cat/display.ts`, `windows/scripts/cat-tests/display.test.mjs`, `windows/scripts/projects-tests/catblock.test.mjs` (new), `windows/src-tauri/src/cat_settings.rs`, `tests/fixtures/settings/controls.json`, `windows/scripts/settings-tests/map.test.mjs` | `projectCats` in the `cat` block, both languages, and its map key | 2 |
| `windows/src/projects/{model,present,cells,clock}.ts` (new), `windows/scripts/projects-tests/{model,present,cells,clock}.test.mjs` (new) | The model, the words, the island rules, the tick and the dwell | 3 |
| `windows/src/core/state.ts`, `windows/src/island/hooks.ts`, `windows/src/main.ts`, `windows/src/projects/{scenarios,dev}.ts` (new), `windows/scripts/projects-tests/{wiring,leak,scenarios,mac-scenarios}.test.mjs` (new) | The feed, the frame, the dev scenarios, the leak pin, the Mac's scenarios | 4 |
| `windows/src/views/projects.ts` (new), `windows/src/projects/projects.css` (new), `windows/src/core/layout.ts`, `windows/src/views/views.ts`, `windows/src/views/icons.ts`, `windows/src/island/island.ts`, `windows/src/main.ts`, `windows/scripts/projects-tests/views.test.mjs` (new) | The screen, rows, pills, peek, actions, the header tab | 5 |
| `windows/src/views/views.ts`, `windows/src/views/projects.ts`, `windows/src/views/icons.ts`, `windows/src/projects/projects.css`, `windows/scripts/projects-tests/overview.test.mjs` (new) | The Claude-only card, the capsule and chevron, the section | 6 |
| `windows/src/island/island.ts`, `windows/src/style.css` (one selector), `windows/src/main.ts`, `windows/src/core/bridge.ts`, `windows/src/projects/projects.css`, `windows/src-tauri/src/{tray,lib}.rs`, `windows/scripts/projects-tests/island.test.mjs` (new), `windows/scripts/cat-tests/{sites,dance,collar-wiring,wardrobe-wiring}.test.mjs` | The island frame: the big cat's look, kittens, peek fade, height, compact count, tick, tray | 7 |
| `windows/src/projects/devprojects.ts` (new), `windows/src/cat/dev.ts`, `windows/scripts/projects-tests/dev.test.mjs` (new) | The `?dev` Projects panel (Checkpoint 1) | 8 |
| `windows/src/settings/{projectcats.ts (new),cat.ts,app.ts,backend.ts,devseed.ts}`, `windows/src/main.ts`, `windows/src/core/bridge.ts`, `tests/fixtures/settings/controls.json`, `windows/scripts/projects-tests/settings.test.mjs` (new) | Settings → Cat → Agents' cats → Project cats, the live names between windows | 9 |
| `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md`, `docs/PROJECTS-CONTRACT.md`, `windows/README.md` | Docs | 10 |

## Tasks and agents

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 0b | The core's two hostile-input caps | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 1 | The generated core, its types, `check:projects` in CI | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 2 | `projectCats` in the `cat` block (TypeScript, Rust, the map key) | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 3 | The model, the words, the island rules, the tick and the dwell | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 4 | The feed, the frame in `State`, the dev scenarios, the leak pin, the Mac's scenarios | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 5 | The Projects screen, rows, pills, peek, actions and the header tab | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 6 | The Claude-only card, the capsule and chevron, the section | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 7 | The island frame: look, kittens, peek fade, height, compact count, tick, tray | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 8 | The `?dev` Projects panel | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 8b | **Owner checkpoint 1**: the `?dev` panel and the island page runs | the main session and the owner | none |
| 9 | Settings → Cat → Agents' cats → Project cats | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 10 | Docs | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| After 10 | The whole branch: cross-task interfaces, the 0 % rule, privacy, restyle | `nm-reviewer-deep`, **Sonnet 5.5**, high (trigger 4), with `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` (`model: sonnet`) and `security-review` | none |
| 11 | **Owner checkpoint 2**: the real machines | the main session and the owner | none |

No task designs platform code: the Pin menu copies the Wardrobe menu, the tray item copies the desktop item, the height copies `animateGeometry`, the page events copy `onEvent`. A Haiku task that fails twice, or fails with no obvious cause, goes to `nm-implementer-deep` (trigger 2), named in the ledger. Task 7's review may run on Sonnet (P-mac ran its island-geometry review there, trigger 1) if the controller names the trigger in the ledger.

## Execution

One worktree chat session runs the plan on branch `p-tauri/projects`, on **Sonnet 5.5 at high effort** (trigger 5: twelve tasks whose interfaces cross: `ProjectsFrame`, `ProjectActions`, `ProjectsSource`, the cat block, the settings backend). It edits `island.ts`, `views.ts`, `layout.ts`, `main.ts`, `state.ts`, `hooks.ts`, `style.css`, `tray.rs`, `lib.rs`, `cat_settings.rs`, `settings/cat.ts`, `settings/app.ts`: it must not run beside another plan that edits those (the focus-awareness Tauri plan included). Started in the three steps of `ARCHITECT.md`: the chip only runs Task 0 Steps 1 and 2 and replies "ready" (its prompt carries the owner's advance approval of the controller brief); the main session sets Sonnet 5.5 high; then sends the controller brief: run this plan with `superpowers:subagent-driven-development`, one task-sized brief per task (its text, the Global Constraints, the SUBAGENT RULES), `nm-reviewer` after each, a ledger at `.superpowers/sdd/2026-10-17-p-tauri/progress.md`, reviews on `git diff main...HEAD` narrowed to the task's files, every shell block through `bash -n` first, stop at Checkpoint 1 and after the final review, and `SendMessage` the main session at each checkpoint, at the end and whenever it stops.

**How to read a step.** Every `Run:` is from the repository root unless it starts with `cd windows`. "Find" texts must occur exactly once; if not, stop and report.

---

## Tasks

### Task 0: Worktree and baseline

**Agent: the session itself.**

- [ ] **Step 1: The branch**

```bash
git switch -c p-tauri/projects main
git merge-base --is-ancestor 684e015c HEAD && git merge-base --is-ancestor 5d4cb85b HEAD && echo "base ok"
git rev-parse --show-toplevel && git branch --show-current
```

Expected: `base ok`; the worktree folder; `p-tauri/projects`.

- [ ] **Step 2: The anchors this plan edits** (each `grep -c` prints `1`)

```bash
cd windows
for p in '  Hub.sk?.hook(payload);' '  if (routeHook(payload, State.claudeSessions) === "chat") {' '  switch (name) {'; do grep -Fc -- "$p" src/island/hooks.ts; done
for p in '  Hub.sk = new Sidekick(sidekickEnv(island, boot?.home ?? ""));' '      case "shelf":' 'State.subscribe(() => Hub.sk?.stateChanged());' '  registerHookHandlers(island);' 'import "./link/link.css";'; do grep -Fc -- "$p" src/main.ts; done
grep -Fc 'export const cleanCatBlock = (raw: unknown): CatBlock => ({' src/cat/display.ts
for p in '  claudeAppHost = false;' '  get pillRow(): { task: AgentTask; cat: string }[] {'; do grep -Fc -- "$p" src/core/state.ts; done
for p in '  shelf: ShelfActions;' '  map.set("link", buildLink());' '  const tabDrop = h("button", { class: "tab", title: "Drop", onclick: () => go("upload") }, svg(ICONS.plus, 13));' '      tabDrop.classList.toggle("on", v === "upload");' 'function buildOverview(actions: ViewActions): ViewHost {' '        who.append(dot(task.color, 7), nameEl, toolEl);' '          leftBody.append(renderIntegrationCard(task, hooks));' '      jump.style.display = detailOpen ? "none" : "";'; do grep -Fc -- "$p" src/views/views.ts; done
grep -Fc '  chevronLeft: "M15 5.5 8.5 12 15 18.5",' src/views/icons.ts
for p in '  | "link";' '  noteLines = 1,' '      const cardH = 84;'; do grep -Fc -- "$p" src/core/layout.ts; done
for p in '    const focus = State.focusTask;' '    this.engine.setCoat(State.cast.big.cat);' '    this.engine.collarColor = bigCatCollar(State.effectiveState, focus?.color);' '    this.engine.setDancing(shouldDance(State.musicPlaying, State.effectiveState, State.mode));' '    syncMiniBotStates(State.tasks);' '    this.drawKittenLayer(dt, greetingActive);' '    this.botCanvas.style.opacity = visible && !State.desktopNotchEmpty ? "1" : "0";' '    const showBadge = badgeShown(State.mode, State.shelf.count, greetingActive);' '    this.shelfBadge = h("button", { id: "shelf-badge" });' '  openShelf() {' '  private async showWardrobeMenu(): Promise<void> {' '      shelf: { ask: (id) => this.askShelf(id), send: (ids) => this.sendShelf(ids), reveal: (id) => this.revealShelf(id), dragOut: (ids) => this.dragOutShelf(ids) },'; do grep -Fc -- "$p" src/island/island.ts; done
grep -Fc '#island.wing-on #shelf-badge {' src/style.css
grep -Fc '  mountLinkDev(root, wrap);' src/cat/dev.ts
for p in '  if (display && pairCard && agentsCard) groups.agentcats.push(card("Display", null, ...display.before), pairCard, agentsCard);' '      display?.draw(dt);' '    display?.sync();'; do grep -Fc -- "$p" src/settings/cat.ts; done
grep -Fc '        desktopNote: ctx.desktopNote,' src/settings/app.ts
grep -Fc '  on<T>(event: "settings-changed" | "ai-servers-changed" | "settings-place" | "settings-hidden", handler: (payload: T) => void): void;' src/settings/backend.ts
grep -Fc '    on: () => {},' src/settings/devseed.ts
grep -Fc '  desktopMenuText: (out: boolean) => call<void>("desktop_menu_text", { out }),' src/core/bridge.ts
grep -Fc '    let shelf = MenuItem::with_id(app, "shelf", "Shelf", true, None::<&str>)?;' src-tauri/src/tray.rs
grep -Fc '            desktop::desktop_menu_text,' src-tauri/src/lib.rs
grep -Fc 'o.insert("outfit".to_string(), clean_wardrobe_settings(raw)["outfit"].clone());' src-tauri/src/cat_settings.rs
cd ..
```

Expected: every line prints `1` (the two-line find `syncMiniBotStates(State.tasks);` + `this.engine.setState(State.effectiveState);` is the one in `syncDom`; `this.engine.setState(State.effectiveState);` alone occurs twice and is never used as a find). Any other count: stop and report which.

- [ ] **Step 3: Baselines (into the ledger)**

```bash
cd windows && for s in cat sidekick settings link; do npm run check:$s 2>&1 | grep -E "^ℹ (tests|fail)"; done; npx --no-install tsc --noEmit && echo "tsc ok"; cd ..
bash scripts/test-projects-contract.sh 2>&1 | tail -2
windows/scripts/cargo-linux.sh test -p notchmeow cat_settings --offline --target-dir /repo/windows/target/p-tauri 2>&1 | grep -E "^test result|FAILED|^error" | head
```

Expected (seen at `684e015c`): `check:cat` 635 tests, `check:sidekick` 140, `check:settings` 368, `check:link` 45, each `fail 0`; `tsc ok`; the contract's two `✓` lines; Rust `test result: ok` (or "needs Docker").

- [ ] **Step 4: Nothing to commit.**

---

### Task 0b: The core's two hostile-input caps

**Agent: `nm-implementer` (Haiku 5.5, high).** P-mac's security review found that the hook socket takes payloads up to 1 MB and that a `cwd` is compared with every root, and that a session's `pending` grows with distinct `agent_id`s; the Swift port capped both (`ProjectsRegistry.cwdMaxBytes`, `pendingMax`) and left the core for "a later change". This is that change, so both ports replay the same rule.

**Files:**
- Modify: `shared/projects-core.js`, `scripts/gen-projects-fixtures.mjs`, `tests/projects/paths.test.mjs`, `docs/PROJECTS-CONTRACT.md`, `scripts/print-projects-tables.mjs`, `tests/ProjectsRegistryTests.swift` (four numbers), `NotchBuddy/Sources/App/ProjectsRegistry.swift` (the comment above `cwdMaxBytes` only)
- Regenerate: `tests/fixtures/projects/event-cases.json`, `tests/fixtures/projects/registry-cases.json` (by `node scripts/gen-projects-fixtures.mjs`)

**Interfaces:**
- Produces: `api.CWD_MAX_BYTES = 4096`, `api.PENDING_MAX = 16`. `projectEventFrom`: a `cwd` whose UTF-8 encoding is longer than 4096 bytes reads as `''` (a first-seen ask is then filed under the home project; any other first-seen kind starts nothing), as the Mac's `utf8.count <= cwdMaxBytes`. `registryApply`: after an approval or question is pushed, a session keeps its newest 16 pending entries (the Mac's `removeFirst`).

- [ ] **Step 1: Write the failing cases** in `scripts/gen-projects-fixtures.mjs`, in the forms the file already uses:
  - in `event-cases.json`, after the waitIn cases, three `ev(...)` cases with `p('UserPromptSubmit', { cwd: … })` payloads: `'a cwd of exactly 4096 bytes is kept'` (`'/' + 'a'.repeat(4095)`, expect `E('prompt', { cwd: that text })`), `'a cwd of 4097 bytes reads as none'` (`'/' + 'a'.repeat(4096)`, expect `E('prompt', { cwd: '' })`), `'a cwd is measured in UTF-8 bytes, not code points'` (`'/' + 'é'.repeat(2048)`, 2049 code points and 4097 bytes, expect `E('prompt', { cwd: '' })`);
  - in `registry-cases.json`, one `seq(...)` case `'a 17th asker drops the oldest open ask'`: `[0, p('UserPromptSubmit', 's1', R)]`, `[1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' }), 'Terminal']` (a stepped-back ask: 10 min), sixteen steps `[2000 + 1000 * i, p('PermissionRequest', 's1', R, { tool_name: 'Bash', agent_id: 'k' + (i + 1) })]` for `i` 0…15, then the views `[18000, [W('notchmeow', 'approval', ['main:approval'], { waiting: 1 })], []]` (the stepped ask is already gone: no note) and `[200000, [W('notchmeow', 'working', ['main:working'])]]` (the card asks ended after 120 s; without the cap the stepped ask would still hold `approval` with `main:Waiting in Terminal`);
  - in `tests/projects/paths.test.mjs`, beside the constants line: `assert.equal(P.CWD_MAX_BYTES, 4096); assert.equal(P.PENDING_MAX, 16);`.

- [ ] **Step 2: Run:** `node scripts/gen-projects-fixtures.mjs --check; node --test tests/projects/*.test.mjs 2>&1 | grep -E "^ℹ fail"`. Expected: the generator stops with "the core says … the case says …" on a new case, and the paths test fails.

- [ ] **Step 3: Implement in the core.** The two constants after `PROJECT_CATS_MAX`; in `projectEventFrom` the event's `cwd` is the payload's when it is text of at most `CWD_MAX_BYTES` UTF-8 bytes, else `''` (a small `utf8Over(s, max)` that counts code units, 1/2/3 bytes and 4 for a surrogate pair, a lone surrogate as 3, and stops past `max`); in `registryApply`'s `approval`/`question` branch, after the push, `if (s.pending.length > api.PENDING_MAX) s.pending.splice(0, s.pending.length - api.PENDING_MAX);`. Update the two functions' doc comments.

- [ ] **Step 4: Regenerate and run the contract:** `node scripts/gen-projects-fixtures.mjs && node scripts/gen-projects-fixtures.mjs --check && bash scripts/test-projects-contract.sh 2>&1 | tail -2 && bash scripts/test-projects-scenarios-core.sh 2>&1 | tail -1`. Expected: the fixtures written, `--check` clean, the two `✓` lines, `All tests passed.`

- [ ] **Step 5: The contract's words.** `docs/PROJECTS-CONTRACT.md`: two rows in the Constants table after `PROJECT_CATS_MAX` (`CWD_MAX_BYTES` `4096` "A `cwd` longer than this in UTF-8 bytes reads as none."; `PENDING_MAX` `16` "Open asks kept per session (the newest).") and one sentence each in the `projectEventFrom` and `registryApply` sections; `scripts/print-projects-tables.mjs`: the two rows beside `SESSIONS_MAX`'s.

- [ ] **Step 6: The Mac's count pins.** In `tests/ProjectsRegistryTests.swift`: line 90 `expect: 50` → `expect: 53`; line 100 `expect: 30` → `expect: 31`; the comment at line 104 "(85 and 50" → "(103 and 52"; line 132 `"… hold 85 event steps and 50 view steps", [payloadSteps, viewSteps], [85, 50]` → `103` and `52` in the words and the list. In `NotchBuddy/Sources/App/ProjectsRegistry.swift`, the comment above `static let cwdMaxBytes = 4096, pendingMax = 16` says these are the contract's `CWD_MAX_BYTES` and `PENDING_MAX` (`shared/projects-core.js`), replayed from `event-cases.json` and `registry-cases.json`, instead of "not yet in shared/projects-core.js"; no code changes.

- [ ] **Step 7: Run the Mac's tests:** `for s in scripts/test-projects-{rules,registry,layout,cats,model,leak,wiring}.sh; do bash "$s" >/dev/null 2>&1 && echo "ok $s" || echo "FAIL $s"; done`. Expected: seven `ok` lines (the registry test now counts 53 events, 31 cases, 103 and 52 steps, and replays the new rows through the Swift port, which already caps both).

- [ ] **Step 8: Commit** the files above and the two fixtures: `feat(projects): the contract caps a cwd at 4096 bytes and a session's open asks at 16 (P-mac's hardening, in the core)`.

---

### Task 1: The generated core, its types, `check:projects` in CI

**Agent: `nm-implementer-light` (Haiku 5.5, medium).**

**Files:**
- Create: `scripts/gen-projects-ts.mjs`, `windows/src/projects/core.generated.ts` (by running the script), `windows/src/projects/core.ts`, `windows/scripts/projects-tests/util.mjs`, `util.test.mjs`, `fixtures.test.mjs`, `fresh.test.mjs`
- Modify: `windows/package.json` (one script), `.github/workflows/windows-tests.yml` (paths and one step)

**Interfaces:**
- Produces (`windows/src/projects/core.ts`), every name later tasks import:

```ts
export type StateWord = "approval" | "question" | "working" | "finished" | "idle";
export type Host = "claude-app" | "vscode" | "terminal";
export type Layout = "projects" | "agents";
export interface ProjectEvent { at: number; agent: string; kind: string; sessionId: string; cwd: string; subagentId: string; subagentType: string; fromApp: boolean; termProgram: string; bundleId: string; waitIn: string; stepped: boolean }
export interface PendingAsk { by: string; kind: "approval" | "question"; at: number; inApp: boolean; waitIn: string }
export interface RegSubagent { id: string; type: string; state: string; born: number; last: number }
export interface RegSession { id: string; cwd: string; root: string; worktree: string; seq: number; startedAt: number; lastAt: number; run: "idle" | "working" | "finished"; finishedAt: number | null; pending: PendingAsk[]; fromApp: boolean; termProgram: string; bundleId: string; subagents: RegSubagent[] }
export interface Registry { version: 1; home: string; sessions: RegSession[]; otherAgentSeen: boolean; nextSeq: number }
export interface SessionState { state: StateWord; dim: boolean; gone: boolean; waitingInApp: boolean }
export interface SubagentRow { id: string; type: string; state: "approval" | "working" }
export interface SessionRow { id: string; role: "main" | "side"; label: string; state: StateWord; dim: boolean; waitingInApp: boolean; note: string; step: string; host: Host; lastAt: number; agoMin: number; subagents: SubagentRow[] }
export interface ProjectRow { id: string; name: string; catKey: string; cat: string; state: StateWord; dim: boolean; waiting: number; sessionCount: number; lastAt: number; agoMin: number; step: string; host: Host; sessions: SessionRow[] }
export interface ProjectsView { projects: ProjectRow[]; waiting: number; sessionCount: number; otherAgentSeen: boolean }
export interface ViewOpts { steps?: Record<string, string>; projectCats?: unknown; mainCat?: unknown }
export interface BigCard { project: string | null; pinned: string | null; clicked: string | null }
// functions, each `ProjectsCore.<name> as (...) => ...`:
normPath(cwd: unknown): string; projectOf(cwd: unknown, roots: unknown, home: unknown): { root: string; worktree: string } | null;
projectNames(roots: unknown, home: unknown): { root: string; name: string; catKey: string }[]; rolesOf(sessions: unknown): { id: string; role: "main" | "side"; label: string }[];
sessionOrder(rows: unknown): string[]; projectEventFrom(payload: unknown, now: number, waitIn?: unknown): ProjectEvent | null;
emptyRegistry(home?: unknown): Registry; registryApply(registry: Registry, ev: ProjectEvent | null): Registry; registryPrune(registry: Registry, now: number): Registry;
sessionStateAt(session: unknown, now: unknown): SessionState; projectStateOf(states: unknown): StateWord; cleanStep(text: unknown): string; waitLabel(host?: unknown): string;
projectsView(registry: Registry, now: unknown, opts?: ViewOpts): ProjectsView; projectOrder<T>(projects: T[]): T[]; bigCardOf(projects: unknown, pinned: unknown, clicked: unknown): BigCard;
waitingCount(projects: unknown): number; claudeOnly(activePills: unknown, otherAgentSeen: unknown): boolean; islandLayout(current: unknown, claudeOnlyNow: unknown, open: unknown): Layout;
cleanProjectCats(raw: unknown): Record<string, string>; projectCatOf(catKey: unknown, projectCats: unknown, mainCat: unknown): { cat: string; stored: boolean }; agoOf(now: unknown, lastAt: unknown): number; fnv1a(s: string): string;
// constants: VERSION, QUIET_IDLE_MS, DIM_MS, REMOVE_MS, FINISHED_MS, APP_WAIT_MS, CARD_APPROVAL_MS, CARD_QUESTION_MS, PEEK_DWELL_MS, AGO_TICK_MS,
// SUBAGENTS_MAX, SESSIONS_MAX, NAME_MAX, STEP_MAX, PROJECT_CATS_MAX, CWD_MAX_BYTES, PENDING_MAX (numbers), APP_WAIT_LABEL, HOME_NAME (strings), STATES (readonly StateWord[]), CAT_IDS (readonly string[]).
```

- Produces (`windows/scripts/projects-tests/util.mjs`): `load(name)` (a fixture of `tests/fixtures/projects/`), `source(rel)` (`windows/src/<rel>` as text; fails on a missing or empty file), `code(rel)` (the same with every `//` and `/* */` comment replaced by spaces, strings and template literals kept, so a pin never matches a comment), `rows(fixture, group, n)` (asserts the group is an array of objects with exactly `n` rows and returns it).

- [ ] **Step 1: Write `scripts/gen-projects-ts.mjs`** as a copy of `scripts/gen-sidekick-ts.mjs` with `SOURCE` = `shared/projects-core.js`, `OUTPUT` = `windows/src/projects/core.generated.ts`, the head's first line `// GENERATED by scripts/gen-projects-ts.mjs from shared/projects-core.js. Do not edit: change the source and run \`node scripts/gen-projects-ts.mjs\`.`, the export line `export const ProjectsCore = module.exports;`, and the messages naming the projects files. It exports `SOURCE`, `OUTPUT` and `render(source)`.

- [ ] **Step 2: Run it**

Run: `node scripts/gen-projects-ts.mjs && node scripts/gen-projects-ts.mjs --check`
Expected: `wrote windows/src/projects/core.generated.ts`, then `✓ windows/src/projects/core.generated.ts matches shared/projects-core.js`.

- [ ] **Step 3: Write the failing tests.** `fresh.test.mjs`: the two tests of `sidekick-tests/fresh.test.mjs`, importing `OUTPUT, SOURCE, render` from `../../../scripts/gen-projects-ts.mjs`. `util.test.mjs`: `code()` blanks a pin written in a `//` comment and in a `/* */` block, keeps `"https://x"` and a template literal holding `//` whole; `rows()` throws on a missing group, a group of the wrong length and a row that is not an object. `fixtures.test.mjs` imports `* as P from "../../src/projects/core.ts"` and replays every file with the groups counted (the counts after Task 0b):

```js
const T = 1_760_000_000_000;
test("project-cases.json", () => {
  const f = load("project-cases.json");
  for (const c of rows(f, "projectOf", 25)) assert.deepEqual(P.projectOf(c.cwd, c.roots, c.home), c.expect, c.name);
  for (const c of rows(f, "names", 19)) assert.deepEqual(P.projectNames(c.roots, c.home), c.expect, c.name);
  for (const c of rows(f, "roles", 4)) assert.deepEqual(P.rolesOf(c.sessions), c.expect, c.name);
  for (const c of rows(f, "order", 2)) assert.deepEqual(P.sessionOrder(c.rows), c.expect, c.name);
  for (const c of rows(f, "ids", 2)) {
    const reg = P.registryApply(P.emptyRegistry(), P.projectEventFrom({ hook_event_name: "UserPromptSubmit", session_id: "s1", cwd: c.root }, T));
    assert.equal(P.projectsView(reg, T).projects[0].id, c.expect, c.name);
  }
});
test("event-cases.json", () => { for (const c of rows(load("event-cases.json"), "cases", 53)) assert.deepEqual(P.projectEventFrom(c.payload, c.now, c.waitIn), c.expect, c.name); });
test("registry-cases.json: every step is a payload or a view, every view, the notes, the presentation and the caps", () => {
  const f = load("registry-cases.json");
  let payloads = 0, views = 0;
  for (const c of rows(f, "cases", 31)) {
    let reg = P.emptyRegistry(c.home);
    for (const s of c.steps) {
      assert.notEqual("payload" in s, "view" in s, `${c.name}: a step is a payload or a view`);
      if (s.payload) { payloads++; reg = P.registryApply(reg, P.projectEventFrom(s.payload, s.at, s.waitIn)); continue; }
      views++;
      const view = P.projectsView(reg, s.at, {});
      assert.deepEqual(view, s.view, c.name);
      if (s.notes) assert.deepEqual(view.projects.flatMap((p) => p.sessions).filter((r) => r.note !== "").map((r) => `${r.label}:${r.note}`), s.notes, c.name);
    }
  }
  assert.deepEqual([payloads, views], [103, 52]);
  for (const c of rows(f, "presentation", 7)) {
    let reg = P.emptyRegistry(c.home);
    for (const s of c.payloads) reg = P.registryApply(reg, P.projectEventFrom(s.payload, s.at));
    assert.deepEqual(P.projectsView(reg, c.at, c.opts), c.view, c.name);
  }
  for (const c of rows(f, "caps", 8)) {
    let reg = P.emptyRegistry(c.home);
    for (const e of c.events) reg = P.registryApply(reg, P.projectEventFrom(e.payload, e.at));
    const got = { sessions: reg.sessions.map((s) => `${s.id}#${s.seq}`), nextSeq: reg.nextSeq,
      subagents: Object.fromEntries(reg.sessions.filter((s) => s.subagents.length).map((s) => [s.id, s.subagents.map((k) => k.id)])),
      lastAt: Object.fromEntries(reg.sessions.map((s) => [s.id, s.lastAt])) };
    for (const k of Object.keys(c.expect)) assert.ok(k in got, `${c.name}: expect key ${k} is one the test reads`);
    assert.deepEqual(Object.fromEntries(Object.keys(c.expect).map((k) => [k, got[k]])), c.expect, c.name);
  }
});
// state-cases.json: rows(f, "sessions", 30) → sessionStateAt; rows(f, "projects", 6) → projectStateOf; rows(f, "agoCases", 5) → agoOf.
// order-cases.json: rows(f, "order", 4) → projectOrder ids; rows(f, "bigCard", 8) → bigCardOf; rows(f, "waiting", 3) → waitingCount.
// claude-only-cases.json: rows(f, "claudeOnly", 7) → claudeOnly; rows(f, "layout", 5) → islandLayout.
// cat-cases.json: rows(f, "cat", 11) → projectCatOf; rows(f, "clean", 9) → cleanProjectCats.
// step-cases.json: rows(f, "steps", 13) → cleanStep; rows(f, "views", 1) → replay its payloads, projectsView(reg, c.at, c.opts) deepEquals c.view.
test("the app's own cats agree: the core's pick is cat/agentcat.ts pickCat with cat/base.ts rng, and CAT_IDS are presets.ts's", () => {
  assert.deepEqual([...P.CAT_IDS], [...CAT_IDS]);
  for (let i = 0; i < 300; i++) for (const main of CAT_IDS) assert.equal(P.projectCatOf(`n${i}`, {}, main).cat, pickCat([main], rng(parseInt(P.fnv1a(`n${i}`), 16)), null));
});
test("a number that is not a number never ages anything (the port's own non-finite case)", () => {
  const reg = P.registryApply(P.emptyRegistry("C:/Users/dev"), P.projectEventFrom({ hook_event_name: "PermissionRequest", session_id: "s1", cwd: "C:/dev/app", tool_name: "Bash" }, T));
  for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
    assert.equal(P.projectEventFrom({ hook_event_name: "Stop", session_id: "s1" }, bad), null);
    assert.equal(P.projectsView(reg, bad).waiting, 1);
    assert.equal(P.sessionStateAt(reg.sessions[0], bad).state, "approval");
  }
});
```

with the imports `pickCat` from `../../src/cat/agentcat.ts`, `rng` from `../../src/cat/base.ts`, `CAT_IDS` from `../../src/cat/presets.ts`. A group whose count changes on purpose (a fixture change) updates the number here, as the Mac's `PJFixtureRows` does.

- [ ] **Step 4: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/projects-tests/*.test.mjs 2>&1 | tail -5`
Expected: FAIL (`core.ts` and `util.mjs` do not exist).

- [ ] **Step 5: Write `windows/src/projects/core.ts`** with the types and the casts of the Interfaces block (the sidekick's `core.ts` is the model: a header comment, `import { ProjectsCore } from "./core.generated.ts";`, one `export const name = ProjectsCore.name as (...) => ...;` per function and constant), and `util.mjs` as in the Interfaces block.

- [ ] **Step 6: Add the script and CI.** In `windows/package.json` after the `check:sidekick` line: `"check:projects": "node --experimental-strip-types --test --test-reporter=spec scripts/projects-tests/*.test.mjs",`. In `.github/workflows/windows-tests.yml`, in both `paths:` lists after `- 'scripts/gen-sidekick-ts.mjs'`: `- 'tests/fixtures/projects/**'`, `- 'tests/fixtures/mac/projects-scenarios.json'`, `- 'shared/projects-core.js'`, `- 'scripts/gen-projects-ts.mjs'`; after the "Sidekick checks" step a step `- name: Projects checks` / `run: npm run check:projects`.

- [ ] **Step 7: Run everything**

Run: `cd windows && npm run check:projects 2>&1 | grep -E "^ℹ (tests|fail)"; npx --no-install tsc --noEmit && echo "tsc ok"`
Expected: `fail 0`; `tsc ok`.

- [ ] **Step 8: Commit** the seven new files and `windows/package.json`, `.github/workflows/windows-tests.yml`: `feat(projects/tauri): the generated projects core, its types and check:projects`.

---

### Task 2: `projectCats` in the `cat` block (TypeScript, Rust, the map key)

**Agent: `nm-implementer` (Haiku 5.5, high).** Rust skills from the SUBAGENT RULES.

**Files:**
- Modify: `windows/src/cat/display.ts`, `windows/scripts/cat-tests/display.test.mjs` (lines 90 and 96, on purpose), `windows/src-tauri/src/cat_settings.rs`, `tests/fixtures/settings/controls.json` (`cat.display`'s `win`), `windows/scripts/settings-tests/map.test.mjs` (`FROZEN.settings` and the cat block scan)
- Create: `windows/scripts/projects-tests/catblock.test.mjs`

**Interfaces:**
- Consumes: `cleanProjectCats`, `PROJECT_CATS_MAX` from `../projects/core.ts` (Task 1).
- Produces (`cat/display.ts`): `CatBlock` gains `projectCats: Record<string, string>`; `withProjectCat(b: CatBlock, catKey: unknown, catId: unknown): CatBlock` (refuses: returns `b` itself when the clean-up would drop a key `b` already stores, the Mac's `updateProjectCats` guard, or when the key or the cat is not kept); `withoutProjectCat(b: CatBlock, catKey: unknown): CatBlock`. Rust: `pub fn clean_project_cats(raw: &Value) -> Value`; `clean_cat_block` inserts `"projectCats"`. The map: the Windows key `cat.projectCats` under `cat.display`.

- [ ] **Step 1: Write the failing tests.** `catblock.test.mjs`:

```js
import * as D from "../../src/cat/display.ts";
test("projectCats is cleaned with the block and edited by two helpers", () => {
  assert.deepEqual(D.cleanCatBlock(null).projectCats, {});
  assert.deepEqual(D.cleanCatBlock({ projectCats: { notchmeow: "oreo", "a/b": "momo", x: "tiger", constructor: "momo" } }).projectCats, { notchmeow: "oreo" });
  const b = D.withProjectCat(D.defaultCatBlock(), "notchmeow", "oreo");
  assert.deepEqual(b.projectCats, { notchmeow: "oreo" });
  assert.equal(D.withProjectCat(b, "C:\\x", "momo"), b, "a key that looks like a path is never stored: the block comes back as it was");
  assert.deepEqual(D.withoutProjectCat(b, "notchmeow").projectCats, {});
  assert.deepEqual(D.defaultCatBlock().projectCats, {}, "the input is not changed");
  assert.deepEqual(D.cleanCatBlock(b), b, "cleaning twice changes nothing");
  assert.equal(D.withDisplayMode(b, "two").projectCats.notchmeow, "oreo", "another row's edit keeps it");
});
test("at 256 stored cats a pick that would push one out is refused; a stored one can still change", () => {
  const full = D.cleanCatBlock({ projectCats: Object.fromEntries(Array.from({ length: 256 }, (_, i) => [`k${String(i).padStart(3, "0")}`, "momo"])) });
  assert.equal(Object.keys(full.projectCats).length, 256);
  assert.equal(D.withProjectCat(full, "a-new-one", "oreo"), full, "'a-new-one' sorts first and would evict k255");
  assert.equal(D.withProjectCat(full, "k255", "oreo").projectCats.k255, "oreo");
});
```

In `cat-tests/display.test.mjs` line 90 add `"projectCats"` to the sorted key list (between `"pair"` and nothing: the list becomes `[…, "outfit", "pair", "projectCats"]`) and line 96 add `projectCats: {}` after `outfit: "auto"`. In `settings-tests/map.test.mjs`: `FROZEN.settings` gains `"cat.projectCats"` after `"cat.agentCats"`, and the cat block scan's list gains `"cat.projectCats"` after `"cat.outfit"`.

- [ ] **Step 2: Run:** `cd windows && npm run check:projects 2>&1 | tail -3; npm run check:cat 2>&1 | grep -E "^ℹ fail"; npm run check:settings 2>&1 | grep -E "^ℹ fail"`. Expected: FAIL on all three (`withProjectCat` is not a function; the block has no `projectCats`; `cat.projectCats` sits under no control).

- [ ] **Step 3: Implement in `cat/display.ts`.** `CatBlock` = `… & { desktop: DesktopSettings; outfit: OutfitId; projectCats: Record<string, string> }`; `cleanCatBlock` adds `projectCats: cleanProjectCats(isPlain(raw) ? raw.projectCats : undefined)` as the last key; `withProjectCat` cleans `{ ...b, projectCats: { ...b.projectCats, [String(catKey)]: catId } }` and returns `b` when a key of `b.projectCats` is missing from the result or `String(catKey)` is not in it; `withoutProjectCat` copies `b.projectCats` without `String(catKey)` and cleans the block. Update the header comment and the `cleanCatBlock` doc line (sub-project P). In `controls.json`, `cat.display`'s `"win"` gains `{ "key": "cat.projectCats", "store": "settings" }` last (one line, the file's style).

- [ ] **Step 4: Run** the three commands of Step 2. Expected: `fail 0` on all three.

- [ ] **Step 5: Write the failing Rust tests** in `cat_settings.rs`'s `mod tests`: a `projects_fixture(name)` beside `fixture` reading `../../tests/fixtures/projects/<name>`; `the_project_cats_clean_up_replays_cat_cases` (each `clean` case: `assert_same(&clean_project_cats(&c["raw"]), &c["expect"], name)`, and the group has 9 rows); `the_project_cats_keep_the_first_256_in_utf16_order` (300 keys `k000`…`k299` keep 256, the first `k000`, the last `k255`; and `utf16_sorted(vec!["\u{FF5E}", "\u{1F600}"])` is `["\u{1F600}", "\u{FF5E}"]`, the contract's UTF-16 order, not byte order); `the_block_holds_project_cats` (`clean_cat_block(&json!({"projectCats": {"notchmeow": "oreo", "a/b": "momo", "x": "tiger"}}))["projectCats"] == json!({"notchmeow": "oreo"})` and `block_default()["projectCats"] == json!({})`).

- [ ] **Step 6: Run:** `windows/scripts/cargo-linux.sh test -p notchmeow cat_settings --offline --target-dir /repo/windows/target/p-tauri 2>&1 | grep -E "^test result|FAILED|error\[" | head`. Expected: FAIL (`clean_project_cats` not found), or "needs Docker".

- [ ] **Step 7: Implement `clean_project_cats`** after `clean_wardrobe_settings`: a port of `cleanProjectCats`: 256 kept, a key kept when it is non-empty, at most 60 `chars()`, has no `/` or `\`, no invisible character (`fn is_invisible_pj(c: char) -> bool`: U+0000–001F, U+007F–009F, U+00AD, U+061C, U+180E, U+200B–200F, U+202A–202E, U+2028, U+2029, U+2060, U+2066–2069, U+FEFF, U+FFF9–FFFB, U+E0000–E007F, the class of `INVISIBLE` in `projects-core.js` line 48; not `link/name.rs`'s larger table), is not `__proto__`, `constructor` or `prototype`, and its value is one of `CAT_IDS`; keys sorted by `encode_utf16()` (`fn utf16_sorted`), the first 256 kept. In `clean_cat_block` insert `o.insert("projectCats".to_string(), clean_project_cats(raw.get("projectCats").unwrap_or(&NULL)));` after the `outfit` line; one line in the file's header comment.

- [ ] **Step 8: Run** Step 6's command. Expected: `test result: ok`.

- [ ] **Step 9: Commit** the six files: `feat(projects/tauri): projectCats in the cat block, cleaned in TypeScript and Rust, never evicting a stored cat`.

---

### Task 3: The model, the words, the island rules, the tick and the dwell

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Create: `windows/src/projects/model.ts`, `present.ts`, `cells.ts`, `clock.ts`; `windows/scripts/projects-tests/model.test.mjs`, `present.test.mjs`, `cells.test.mjs`, `clock.test.mjs`

**Interfaces:**
- Consumes: `core.ts` (Task 1); `stepLabel` from `../core/steps.ts`; `type Kitten` from `../cat/kittens.ts`; `type AgentTask` from `../core/state.ts` (type-only, erased at run time).
- Produces:

```ts
// cells.ts: the Mac's ProjectsLayout rules (ProjectsLayout.swift), pure
export const GRID_CAPACITY = 4, PANEL_COLUMNS = 3, PANEL_EXTRA = 92, SCREEN_H = 240, SCREEN_LEADING = 80, SCREEN_BOTTOM = 22, PIN_MENU_RELEASE_MS = 500;
export type Cell = { kind: "project"; id: string } | { kind: "more"; count: number } | { kind: "pill"; id: string };
export function cellKey(c: Cell): string;                                    // "p:" + id, "more", "pill:" + id
export function gridCells(projects: readonly string[], otherPills: readonly string[], capacity?: number): Cell[];
export function panelCells(projects: readonly string[], columns?: number): Cell[];
export function usesProjects(layout: Layout, focusId: string | null, projectCount: number, twoCats: boolean): boolean;
export function chevronShown(layout: Layout, focusId: string | null, projectCount: number, twoCats: boolean): boolean;
export function peekLineCapacity(cardH: number): number;                     // floor((cardH − 2·10 − 16 − 6 + 2) / (14 + 2))
export function cut(lines: number, capacity: number): { shown: number; more: number };
export function pillNameParts(name: string): { folder: string; detail: string | null };
// present.ts: the words (ProjectsLayout.swift's, exact)
export const STATE_WORDS: Readonly<Record<StateWord, string>>;   // approval "waiting for you", question "has a question", working "working", finished "finished", idle "idle"
export const EMPTY_SCREEN = "No Claude Code session is running.";
export const EMPTY_SETTINGS = "No Claude Code project is running. Each one is listed here while it runs, and keeps the cat you give it.";
export const CATS_HELP = "Each project wears the cat you give it, by its folder's name; up to 256 projects keep one. A project without one gets a cat that is not the Main cat.";
export const CLAUDE_COLOR = "#F5F6F8";                            // the Claude Code pill's colour (state.ts INTEGRATION_AGENTS)
export function hostWord(host: string): string; export function agoWord(min: number): string; export function sessionsWord(n: number): string;
export function projectsWord(n: number): string; export function waitingWord(n: number): string; export function moreWord(n: number): string;
export function moreRowsWord(n: number): string; export function subagentWord(type: string): string; export function rowDetail(note: string, step: string): string;
export function bigStepLine(p: ProjectRow): string;                // p.step, else STATE_WORDS[p.state]
export function badgeTitle(n: number): string;                    // "Projects, N waiting"
export function pinTitle(pinned: boolean): string;                 // "Unpin" / "Pin"
export function dotClass(state: StateWord, open: boolean): string;
export function projectStep(tool: unknown, input: unknown): string | null;
export function projectKittens(subs: readonly SubagentRow[]): Kitten[];
export function projectTask(p: ProjectRow): AgentTask;
export interface LiveProject { catKey: string; name: string }
export interface CatRow { catKey: string; name: string; cat: string; stored: boolean; live: boolean }
export function projectCatRows(live: readonly LiveProject[], stored: unknown, main: unknown): CatRow[];   // ProjectCatList.rows
// clock.ts
export interface OneShot { set(fn: () => void, ms: number): number; clear(id: number): void }
export function nextDelay(reg: Registry, now: number): number;   // ProjectsClock.nextDelay: the nearest boundary after now, else AGO_TICK_MS; never below 50
export class ProjectsTick { constructor(timer: OneShot, now: () => number, delay: () => number, fire: () => void); sync(open: boolean): void; get armed(): boolean }
export class PeekDwell { constructor(timer: OneShot, show: (id: string) => void, hide: () => void); enter(id: string): void; leave(): void; get shown(): string | null }
// model.ts
export interface ProjectsEnv { home: string; now: () => number }
export interface FrameInput { projectCats: unknown; mainCat: unknown; activePills: readonly string[]; open: boolean; focusId: string | null; twoCats: boolean }
export interface ProjectsFrame { view: ProjectsView; big: ProjectRow | null; layout: Layout; usesProjects: boolean; chevron: boolean; panelShown: boolean; pinned: string | null; expanded: boolean; peeking: string | null }
export class ProjectsModel {
  constructor(env?: Partial<ProjectsEnv>);
  hook(payload: unknown, waitIn?: string): boolean;   // true when the payload made an event
  frame(input: FrameInput): ProjectsFrame;            // the view now, the big card (stores bigCardOf's pin and click), the layout, the panel, the peek reconciled
  select(projectId: string): void;                    // the big card's project, by a click
  togglePin(projectId: string): void;                 // only a live project; one pin at a time; the pinned one unpins
  isPinned(projectId: string): boolean;
  toggleExpanded(): void; get expanded(): boolean;
  setPeeking(id: string | null): void;
  cwdOf(sessionId: string): string | null;            // memory only: for the jump
  newestSession(p: ProjectRow): SessionRow | null;    // greatest lastAt, the first on a tie
  liveProjects(view: ProjectsView): LiveProject[];    // one per catKey, in pill order, with the first project's name
  nextDelay(): number;                                // clock.ts nextDelay on the registry, now
  get stepsSize(): number;
}
```

- [ ] **Step 1: Write the failing tests.**

`model.test.mjs` (rig: `const w = { t: T }; const m = new ProjectsModel({ home, now: () => w.t });`, `const IN = { projectCats: {}, mainCat: "shrimpy", activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false };`):

```js
test("Windows paths: a worktree under a backslash repo is its side session; nothing shown holds a separator", () => {
  const { m } = rig("C:\\Users\\dev");
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "c:\\dev\\Code\\app\\" });
  m.hook({ hook_event_name: "PreToolUse", session_id: "b", cwd: "C:\\dev\\Code\\app\\.claude\\worktrees\\p1", tool_name: "Read", tool_input: { file_path: "C:\\dev\\Code\\app\\src\\a.ts" } });
  const v = m.frame(IN).view;
  assert.equal(v.projects.length, 1);
  assert.equal(v.projects[0].name, "app");
  assert.deepEqual(v.projects[0].sessions.map((s) => [s.role, s.label, s.step]), [["main", "main", ""], ["side", "p1", "Reads · a.ts"]]);
  for (const s of [v.projects[0].name, ...v.projects[0].sessions.flatMap((x) => [x.label, x.step])]) assert.doesNotMatch(s, /[\/\\]/);
  assert.equal(m.cwdOf("b"), "C:/dev/Code/app/.claude/worktrees/p1");
});
test("a Claude App request answered ask is waiting, labelled, counted, and ends by itself after 10 min", () => {
  const { w, m } = rig();
  m.hook({ hook_event_name: "PermissionRequest", session_id: "d", cwd: "C:/dev/app", nm_agent: "claude-desktop", tool_name: "Bash", tool_input: { command: "ls" } });
  const v = m.frame(IN).view;
  assert.equal(v.waiting, 1);
  assert.deepEqual([v.projects[0].sessions[0].note, v.projects[0].sessions[0].host], ["Waiting in Claude App", "claude-app"]);
  w.t += 600_000;
  assert.equal(m.frame(IN).view.waiting, 0);
});
test("the step words never carry a command or a query; AskUserQuestion leaves none; a prompt clears it", () => {
  const { m } = rig();
  m.hook({ hook_event_name: "PreToolUse", session_id: "s", cwd: "C:/dev/app", tool_name: "Bash", tool_input: { command: "rm -rf SECRET" } });
  assert.equal(m.frame(IN).view.projects[0].step, "Runs");
  m.hook({ hook_event_name: "PreToolUse", session_id: "s", cwd: "C:/dev/app", tool_name: "WebSearch", tool_input: { query: "SECRET" } });
  assert.equal(m.frame(IN).view.projects[0].step, "Web search");
  m.hook({ hook_event_name: "PreToolUse", session_id: "s", cwd: "C:/dev/app", tool_name: "AskUserQuestion", tool_input: { questions: [] } });
  assert.equal(m.frame(IN).view.projects[0].step, "Web search");
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "s", cwd: "C:/dev/app", prompt: "x" });
  assert.equal(m.frame(IN).view.projects[0].step, "");
});
test("one pin at a time, a pin goes with its project, and a pin on a project that is not live is not taken", () => {
  const { w, m } = rig();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/one" }); w.t += 1000;
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "b", cwd: "C:/dev/two" });
  const [two, one] = m.frame(IN).view.projects.map((p) => p.id);
  assert.equal(m.frame(IN).big.id, two, "the most recently active");
  m.togglePin(one); assert.equal(m.frame(IN).big.id, one);
  m.togglePin(two); assert.deepEqual([m.isPinned(one), m.isPinned(two)], [false, true]);
  assert.equal(m.frame({ ...IN, open: true }).big.id, two, "the pin holds through a fold and a reopen");
  m.hook({ hook_event_name: "SessionEnd", session_id: "b" });
  const f = m.frame(IN);
  assert.deepEqual([f.big.id, f.pinned, m.isPinned(two)], [one, null, false]);
  m.togglePin(two); assert.equal(m.isPinned(two), false, "the menu stayed open while its project ended");
});
test("the layout: projects while Claude only; another agent switches it only while folded; usesProjects needs a live project, the focus and no Two cats", () => {
  const { m } = rig();
  assert.deepEqual([m.frame(IN).layout, m.frame(IN).usesProjects], ["projects", false], "nothing live");
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/app" });
  assert.equal(m.frame(IN).usesProjects, true);
  assert.equal(m.frame({ ...IN, focusId: "integration_stripe" }).usesProjects, false);
  assert.equal(m.frame({ ...IN, twoCats: true }).usesProjects, false);
  assert.equal(m.frame({ ...IN, activePills: ["integration_claude", "agent_gemini"] }).layout, "agents", "a switched-on agent counts while idle");
  assert.equal(m.frame(IN).layout, "projects", "folded, Claude only again");
  m.hook({ hook_event_name: "PreToolUse", session_id: "g", cwd: "C:/dev/app", nm_agent: "gemini" });
  assert.equal(m.frame({ ...IN, open: true }).layout, "projects", "open: kept");
  assert.equal(m.frame(IN).layout, "agents", "folded: switched");
});
test("the chevron and the panel: agents layout, a live project, the Claude Code focus, no Two cats; the panel also needs the flag", () => {
  const { m } = rig();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/app" });
  const A = { ...IN, activePills: ["agent_codex"] };
  assert.deepEqual([m.frame(A).chevron, m.frame(A).panelShown], [true, false]);
  m.toggleExpanded();
  assert.deepEqual([m.frame(A).panelShown, m.frame({ ...A, focusId: "agent_codex" }).panelShown, m.frame({ ...A, twoCats: true }).chevron, m.frame(IN).panelShown], [true, false, false, false]);
});
test("a peek is let go when its project leaves", () => {
  const { m } = rig();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/app" });
  const id = m.frame(IN).view.projects[0].id;
  m.setPeeking(id); assert.equal(m.frame(IN).peeking, id);
  m.hook({ hook_event_name: "SessionEnd", session_id: "a" });
  assert.equal(m.frame(IN).peeking, null);
});
test("steps live only as long as their session; an unknown payload changes nothing and never throws", () => {
  const { m } = rig();
  m.hook({ hook_event_name: "PreToolUse", session_id: "s", cwd: "C:/dev/app", tool_name: "Edit", tool_input: { file_path: "C:/dev/app/x.ts" } });
  assert.equal(m.stepsSize, 1);
  m.hook({ hook_event_name: "SessionEnd", session_id: "s" });
  assert.equal(m.stepsSize, 0);
  for (const bad of [null, 5, "x", [], { hook_event_name: "Nope", session_id: "s" }]) assert.equal(m.hook(bad), false);
});
test("a chosen cat shows; liveProjects is one row per folder name, in pill order", () => {
  const { w, m } = rig();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/notchbuddy" }); w.t += 1000;
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "b", cwd: "C:/dev/site" });
  const f = m.frame({ ...IN, projectCats: { "Notch Buddy": "oreo" } });
  assert.equal(f.view.projects.find((p) => p.catKey === "Notch Buddy").cat, "oreo");
  assert.deepEqual(m.liveProjects(f.view), [{ catKey: "site", name: "site" }, { catKey: "Notch Buddy", name: "Notch Buddy" }]);
});
```

`present.test.mjs`: `[0, 1, 59, 60, 125].map(agoWord)` is `["now", "1 min ago", "59 min ago", "1 h ago", "2 h ago"]`; `hostWord("claude-app")`, `("vscode")`, `("terminal")`, `("x")` are `"Claude App"`, `"VS Code"`, `"Terminal"`, `"Terminal"`; `sessionsWord(1)` `"1 session"`, `(2)` `"2 sessions"`; `projectsWord(1)` `"1 project"`; `waitingWord(2)` `"2 waiting"`; `moreWord(3)` `"+3"`; `moreRowsWord(2)` `"+2 more"`; `subagentWord("")` `"subagent"`; `rowDetail("", "Runs")` `"Runs"`, `rowDetail("Waiting in Claude App", "Runs")` the note; `bigStepLine` of a project with step `""` and state `approval` is `"waiting for you"`; `badgeTitle(3)` `"Projects, 3 waiting"`; `pinTitle(true)` `"Unpin"`; `projectStep("Bash", { command: "x" })` `"Runs"`, `("Edit", { file_path: "C:\\a\\b.ts" })` `"Edits · b.ts"`, `("Grep", { pattern: "SECRET", path: "/home/dev/src" })` `"Searches · src"`, `("WebSearch", { query: "q" })` `"Web search"`, `("AskUserQuestion", {})` and `("", {})` and `(undefined, null)` `null`; `dotClass("approval", true)` `"pj-dot pj-approval pj-pulse"`, `("question", true)` `"pj-dot pj-question pj-pulse"`, `("question", false)` `"pj-dot pj-question"`, `("working", true)` `"pj-dot pj-working"`; `EMPTY_SCREEN`, `EMPTY_SETTINGS` and `CATS_HELP` equal the Interfaces block's strings; `projectKittens([{id:"k1",type:"Explore",state:"approval"},{id:"k2",type:"Plan",state:"working"}])` keeps the order and states with `session` and `until` null; `projectTask(p)` has id `p.id`, name `p.name`, color `CLAUDE_COLOR`, state `p.state`, steps `[]`, source `"claudeCode"`; `projectCatRows([{catKey:"b",name:"b — x"},{catKey:"a",name:"a"},{catKey:"b",name:"b — y"}], {c:"momo", a:"oreo", "x/y":"momo"}, "shrimpy")` deepEquals `[{catKey:"b",name:"b — x",cat:<projectCatOf("b",…).cat>,stored:false,live:true},{catKey:"a",name:"a",cat:"oreo",stored:true,live:true},{catKey:"c",name:"c",cat:"momo",stored:true,live:false}]`.

`cells.test.mjs` (the Mac's `ProjectsLayoutTests` cases): `gridCells([], ["s1","s2"])` is two pills; `gridCells(["a","b"], ["s1","s2","s3"])` is a, b, s1, s2; `gridCells(["a","b","c","d","e"], ["s1"])` is a, b, c and `{kind:"more", count:2}`; seven projects give three and `+4`; `panelCells(["a","b","c"])` three projects, four give a, b and `+2`; `cellKey` of each kind is `"p:a"`, `"more"`, `"pill:s1"`, and the "+N" key does not change with its count; `usesProjects("projects", null, 1, false)` true, with `"integration_claude"` true, with `"agent_codex"` false, with 0 projects false, with Two cats false, with `"agents"` false; `chevronShown("agents", "integration_claude", 1, false)` true, with `null` focus false, with Two cats false, with `"projects"` false; `peekLineCapacity(98)` 3 (the Mac's card), `peekLineCapacity(108)` 4; `cut(3, 3)` `{shown:3, more:0}`, `cut(5, 3)` `{shown:2, more:3}`, `cut(1, 0)` `{shown:0, more:1}`; `pillNameParts("notchmeow — Code")` `{folder:"notchmeow", detail:"Code"}`, `("notchmeow — Code · 2")` detail `"Code · 2"`, `("site — ")` `{folder:"site", detail:null}`, `(" — x")` `{folder:" — x", detail:null}`, `("app")` `{folder:"app", detail:null}`; the constants equal `4, 3, 92, 240, 80, 22, 500`.

`clock.test.mjs` with a fake one-shot (`set` records `{fn, ms}` under a new id, `clear` deletes it, `fire()` runs and removes the first) and a fake clock:

```js
test("nextDelay: 60 s with nothing due, the nearest later boundary otherwise, never at or before now, never below 50 ms", () => {
  const P = core;
  const reg = (events) => events.reduce((r, [at, p]) => P.registryApply(r, P.projectEventFrom(p, at)), P.emptyRegistry("C:/Users/dev"));
  assert.equal(nextDelay(P.emptyRegistry(""), T), 60_000);
  const stop = reg([[T, { hook_event_name: "UserPromptSubmit", session_id: "s", cwd: "C:/dev/a" }], [T + 1000, { hook_event_name: "Stop", session_id: "s" }]]);
  assert.equal(nextDelay(stop, T + 1000), 5200, "finished ends 5.2 s after the stop");
  assert.equal(nextDelay(stop, T + 6200), 60_000, "a boundary at exactly now has passed");
  assert.equal(nextDelay(stop, T + 6190), 50, "the floor");
  const ask = reg([[T, { hook_event_name: "PermissionRequest", session_id: "s", cwd: "C:/dev/a", tool_name: "Bash" }]]);
  assert.equal(nextDelay(ask, T + 100_000), 20_000, "a card's approval ends at 120 s");
});
test("ProjectsTick: one one-shot while open, re-armed only for an earlier boundary, cleared once folded", () => {
  const t = fake(); let now = 0, delay = 60_000, fired = 0;
  const k = new ProjectsTick(t, () => now, () => delay, () => fired++);
  k.sync(false); assert.equal(t.live.size, 0);
  k.sync(true); k.sync(true); assert.equal(t.live.size, 1); assert.equal([...t.live.values()][0].ms, 60_000);
  now = 1000; delay = 60_000; k.sync(true); assert.equal([...t.live.values()][0].ms, 60_000, "a later boundary never pushes it back");
  delay = 5200; k.sync(true); assert.deepEqual([t.live.size, [...t.live.values()][0].ms], [1, 5200], "an earlier one replaces it");
  t.fire(); assert.deepEqual([fired, k.armed], [1, false]);
  k.sync(true); k.sync(false); assert.equal(t.live.size, 0);
});
test("PeekDwell: shows after PEEK_DWELL_MS on the same pill; leaving clears and hides; a new pill replaces the pending one", () => {
  const t = fake(); const seen = []; const d = new PeekDwell(t, (id) => seen.push(`show ${id}`), () => seen.push("hide"));
  d.enter("p1"); assert.equal([...t.live.values()][0].ms, 400);
  d.enter("p2"); assert.equal(t.live.size, 1);
  t.fire(); assert.deepEqual([seen, d.shown], [["show p2"], "p2"]);
  d.leave(); assert.deepEqual([seen.at(-1), d.shown, t.live.size], ["hide", null, 0]);
});
```

- [ ] **Step 2: Run:** `cd windows && npm run check:projects 2>&1 | tail -3`. Expected: FAIL (modules missing).

- [ ] **Step 3: Implement.** `model.ts`: a `Registry` (`emptyRegistry(env.home)`), a `Map<string, string>` of steps, `pinned`/`clicked`/`peeking` (`string | null`), `expandedFlag`, `current: Layout = "agents"`. `hook`: `projectEventFrom(payload, now(), waitIn)`; `null` → false; apply; for a Claude event of kind `preTool`, `projectStep(tool_name, tool_input)` stored when not null; a `prompt` deletes its session's step; then every step whose session is not in the registry goes; true. `frame`: `projectsView(reg, now(), { steps, projectCats, mainCat })`; `bigCardOf(view.projects, pinned, clicked)`, its `pinned` and `clicked` stored; `peeking` cleared when not a live project id; `current = islandLayout(current, claudeOnly(activePills, reg.otherAgentSeen), open)`; `layout = current`; `usesProjects`, `chevron` from `cells.ts`; `panelShown = expandedFlag && chevron`; `big` is the view's project with the big card's id. `togglePin(id)`: only when `id` is a live project now (`projectsView(reg, now())`), then pinned = pinned === id ? null : id. `present.ts`: `projectStep` returns null for a non-text or empty tool and for `AskUserQuestion`, else `stepLabel(tool, input reduced to its string "path" and "file_path")`; `projectKittens` gives `born` and `last` `subs.length - i`. `clock.ts`: `nextDelay` is the Mac's `ProjectsClock.nextDelay` (a working session's `lastAt + QUIET_IDLE_MS`, a finished one's `finishedAt + FINISHED_MS`, each pending ask's `at + (inApp ? APP_WAIT_MS : approval ? CARD_APPROVAL_MS : CARD_QUESTION_MS)`; only `> now` counts; the minimum with `AGO_TICK_MS`; floored at 50). `ProjectsTick` keeps one id and its due time; `sync(true)` arms when none is armed or `now() + delay()` is earlier; its fire clears the id and calls `fire`; `sync(false)` clears. `PeekDwell` holds one id and `shown`. No timer of their own: only the injected one.

- [ ] **Step 4: Run:** `cd windows && npm run check:projects 2>&1 | grep -E "^ℹ (tests|fail)"; npx --no-install tsc --noEmit && echo "tsc ok"`. Expected: `fail 0`; `tsc ok`.

- [ ] **Step 5: Commit** the eight files: `feat(projects/tauri): the projects model, its words, the island rules, the tick and the dwell`.

---

### Task 4: The feed, the frame in `State`, the dev scenarios, the leak pin, the Mac's scenarios

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Modify: `windows/src/core/state.ts`, `windows/src/island/hooks.ts`, `windows/src/main.ts`
- Create: `windows/src/projects/scenarios.ts`, `windows/src/projects/dev.ts`, `windows/scripts/projects-tests/wiring.test.mjs`, `leak.test.mjs`, `scenarios.test.mjs`, `mac-scenarios.test.mjs`

**Interfaces:**
- Consumes: `ProjectsModel`, `ProjectsFrame` (Task 3); `Skew` from `../sidekick/appenv`.
- Produces: `State.projects: ProjectsModel` (a plain field, replaced once by `main.ts`); `State.projectsNow(): ProjectsFrame`; `PROJECT_SCENARIOS: Readonly<Record<string, { note: string; steps: readonly { at: number; payload: Record<string, unknown> }[] }>>`; `projectScenarios(hook: (p: Record<string, unknown>) => void, age: (ms: number) => void): { run(name: string): void; age(minutes: number): void; names: string[] }` (dev only).

- [ ] **Step 1: Write the failing tests.**

`wiring.test.mjs` (pins on `code()`, so a comment never satisfies one):

```js
const hooks = code("island/hooks.ts"), main = code("main.ts"), state = code("core/state.ts");
test("the feed is after a chat's own run is routed away, right after the Sidekick's, before any refusal", () => {
  const at = hooks.indexOf("  State.projects.hook(payload);");
  assert.ok(at > 0 && hooks.indexOf("State.projects.hook(", at + 1) < 0, "once, and in code");
  assert.ok(hooks.indexOf('routeHook(payload, State.claudeSessions) === "chat"') < at);
  assert.ok(hooks.indexOf("  Hub.sk?.hook(payload);") < at);
  assert.ok(at < hooks.indexOf("  switch (name) {"));
});
test("main.ts makes the one model with the home folder and the skewed clock, before the hooks are registered", () => {
  const made = main.indexOf('State.projects = new ProjectsModel({ home: boot?.home ?? "", now: () => Date.now() + Skew.ms });');
  assert.ok(made > 0 && made < main.indexOf("  registerHookHandlers(island);"));
});
test("State's frame takes the cat block, every pill (the four switches included), the focus and Two cats", () => {
  const fn = state.slice(state.indexOf("projectsNow(): ProjectsFrame {"), state.indexOf("\n  }\n", state.indexOf("projectsNow(): ProjectsFrame {")));
  assert.match(fn, /activePills: \[\.\.\.this\.settings\.activeIntegrations, \.\.\.this\.tasks\.map\(\(t\) => t\.id\)\]/);
  assert.match(fn, /focusId: this\.focusId,/);
  assert.match(fn, /twoCats: this\.cast\.second !== null,/);
});
test("no timer and no loop in the projects modules", () => {
  for (const f of ["projects/model.ts", "projects/present.ts", "projects/cells.ts", "projects/clock.ts", "projects/core.ts", "projects/scenarios.ts"])
    assert.doesNotMatch(code(f), /setInterval|setTimeout|requestAnimationFrame/, f);
});
test("feeding the registry raises no alert: attentionNeeded and the tuck-away rule do not read it", () => {
  assert.doesNotMatch(state.slice(state.indexOf("get attentionNeeded"), state.indexOf("get focusTask")), /projects/);
  assert.doesNotMatch(code("island/tuckaway.ts"), /projects/i);
});
```

`leak.test.mjs`: a `ProjectsModel` fed with payloads carrying markers `LEAK-DIR-p7` (as the grandparent folder: `C:\\LEAK-DIR-p7\\Code\\app`), `LEAK-PROMPT-p7` (`prompt`), `LEAK-CMD-p7` (`tool_input.command`), `LEAK-QUERY-p7` (`tool_input.query`), `LEAK-TRANSCRIPT-p7` (`transcript_path`), `LEAK-MSG-p7?` (a Notification `message`), `LEAK-WORDS-p7` (`last_assistant_message`), `LEAK-TERM-p7` (`term_program`), with `console.*` spied; then asserts none of the markers, and no `C:\\` or `C:/`, is in: `JSON.stringify(frame.view)`; every `bigStepLine`, `rowDetail`, `hostWord`, `projectsWord`, `badgeTitle` output; `JSON.stringify(model.liveProjects(view))`; `JSON.stringify(withProjectCat(defaultCatBlock(), key, "oreo"))` for each live key; the spied log. It also checks that it saw something: the view has one project named `app` with the step `Runs`.

`scenarios.test.mjs`: every scenario's payloads give an event through `projectEventFrom` (`other`'s is `kind: "other"`), every `cwd` starts with `C:/dev/`, the names are `["two", "appWait", "cardWait", "collide", "subagents", "many", "other", "end"]`, `at` never decreases inside a scenario, and `many` has seven distinct project folders.

`mac-scenarios.test.mjs` replays `tests/fixtures/mac/projects-scenarios.json` through a `ProjectsModel` (home = the fixture's `home`, a leading `~` in a `cwd` replaced by it, the clock `1760000000000 + at`, the step's `waitIn` passed): after each step, `frame({ projectCats: {}, mainCat: "shrimpy", activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false })` is checked against every `expect` key the core replay reads (`projects` as `name:state:waiting`, `rows` as `label:state` per named project, `notes` as `label:note`, `waiting`, `layout`); an unknown step or expect key fails; the step counts are `{ "claude-app-wait": 4, "collide-and-home": 7, end: 4, "other-agent": 2, "two-projects": 11 }` and the expectations run are exactly 70 (the numbers of `scripts/test-projects-scenarios-core.mjs`).

- [ ] **Step 2: Run:** `cd windows && npm run check:projects 2>&1 | tail -3`. Expected: FAIL.

- [ ] **Step 3: `state.ts`.** Import `ProjectsModel` and `type ProjectsFrame` from `../projects/model.ts`. After `  claudeAppHost = false;` add `projects = new ProjectsModel();` with a one-line comment (sub-project P, memory only, replaced by `main.ts` with the home folder), and after `get pillRow()`'s closing brace:

```ts
  /** The Projects frame now (sub-project P): the live projects, the big card, the layout, the panel and the peek, computed from the registry at this moment (no timer moves the time-based states). */
  projectsNow(): ProjectsFrame {
    return this.projects.frame({
      projectCats: this.settings.cat.projectCats, mainCat: this.settings.cat.character,
      activePills: [...this.settings.activeIntegrations, ...this.tasks.map((t) => t.id)],
      open: this.mode === "expanded",
      focusId: this.focusId,
      twoCats: this.cast.second !== null,
    });
  }
```

- [ ] **Step 4: `hooks.ts`.** After `  Hub.sk?.hook(payload);` add:

```ts
  // The Projects registry (sub-project P) is fed here too, for the same reason: a Claude App request answered "ask" below, or one the one card turns away, still counts as waiting. Memory only.
  State.projects.hook(payload);
```

- [ ] **Step 5: `main.ts`.** Import `ProjectsModel` from `./projects/model.ts` and `Skew` from `./sidekick/appenv` (in the existing `sidekickEnv` import). Before `  Hub.sk = new Sidekick(sidekickEnv(island, boot?.home ?? ""));` add `  State.projects = new ProjectsModel({ home: boot?.home ?? "", now: () => Date.now() + Skew.ms });` with a comment. After the `void import("./sidekick/dev")…` block add a dev-only block that imports `./projects/dev` and assigns `__nm.projects = projectScenarios((p) => handleHook(island, p as HookPayload), (ms) => { Skew.ms += ms; State.notify(); })`.

- [ ] **Step 6: `scenarios.ts` and `dev.ts`.** The eight scenarios, all under `C:/dev/` with session ids `dev-…`: `two` (a main session in `C:/dev/Code/notchmeow`, a side session in its `.claude/worktrees/p-tauri`, a session in `C:/dev/Code/site`, a few `PreToolUse` steps); `appWait` (a `claude-desktop` session and its `PermissionRequest`); `cardWait` (a terminal session's `PermissionRequest`, which also raises the notch card as today); `collide` (`C:/dev/Code/notchmeow` and `C:/dev/Old/notchmeow`); `subagents` (three `SubagentStart` of types `Explore`, `Plan`, `general-purpose`, one of them asking a `PermissionRequest`); `many` (seven projects, for "+N"); `other` (a `PreToolUse` with `nm_agent: "gemini"`); `end` (`SessionEnd` for every session id above). `dev.ts` replays a scenario's steps through `hook` at once (the `at` only orders them) and `age(minutes)` calls the given `age` with `minutes * 60_000`.

- [ ] **Step 7: Run:** `cd windows && npm run check:projects 2>&1 | grep -E "^ℹ (tests|fail)"; for s in sidekick cat; do npm run check:$s 2>&1 | grep -E "^ℹ fail"; done; npx --no-install tsc --noEmit && echo "tsc ok"`. Expected: `fail 0` three times; `tsc ok`.

- [ ] **Step 8: Commit** the nine files: `feat(projects/tauri): feed the projects registry from the hooks, State's frame, dev scenarios, the leak pin, the Mac's scenarios`.

---

### Task 5: The Projects screen, rows, pills, peek, actions and the header tab

**Agent: `nm-implementer` (Haiku 5.5, high).** Copy the Wardrobe menu's pattern for Pin (`island.ts` `showWardrobeMenu`).

**Files:**
- Create: `windows/src/views/projects.ts`, `windows/src/projects/projects.css`, `windows/scripts/projects-tests/views.test.mjs`
- Modify: `windows/src/core/layout.ts`, `windows/src/views/views.ts`, `windows/src/views/icons.ts`, `windows/src/island/island.ts`, `windows/src/main.ts` (one import)

**Interfaces:**
- Consumes: `State.projectsNow()` (Task 4); `present.ts`, `cells.ts`, `clock.ts` (Task 3); `createMiniBot`, `pruneMiniBots` from `../cat/minibots`; `openRoute` from `../core/openagent.ts`.
- Produces (`views/projects.ts`):

```ts
export interface ProjectActions {
  select(projectId: string): void;       // a pill's click: the big card's project
  jumpProject(projectId: string): void;  // the big card's click and its ↗: the newest session's app
  jumpSession(sessionId: string): void;  // a row's click: the approval card when that session owns it, else its app
  menu(projectId: string): void;         // a pill's right-click: Pin / Unpin
  toggleExpanded(): void;                // the chevron
  openScreen(): void;                    // a "+N" cell
}
export interface ProjectsSource { frame(): ProjectsFrame; open(): boolean; peek(id: string | null): void }
export const appProjectsSource: ProjectsSource;   // frame: State.projectsNow(), open: State.mode === "expanded", peek: State.projects.setPeeking(id) and State.notify()
export function sessionRows(p: ProjectRow, act: ProjectActions | null, open: boolean, limit?: number): HTMLElement;   // act null: plain rows (the peek); limit: cut() with "+N more"
export function projectPill(p: ProjectRow, act: ProjectActions, peek: ProjectPeek | null, open: boolean): HTMLElement;
export function moreCell(count: number, act: ProjectActions): HTMLElement;
export function keyedCells(host: HTMLElement, cells: readonly Cell[], make: (c: Cell) => HTMLElement, kept: Map<string, HTMLElement>, refresh: (el: HTMLElement, c: Cell) => void): void;
export class ProjectPeek { constructor(src: ProjectsSource, card: HTMLElement, cardH: number); readonly el: HTMLElement; enter(id: string): void; leave(): void; sync(): void }
export function leaveAllPeeks(): void;
export function buildProjects(act: ProjectActions, src?: ProjectsSource): ViewHost;   // the "projects" island view
```

- Produces (`layout.ts`): `IslandViewName` gains `"projects"`; `VIEW_LAYOUTS.projects = { height: 240, botX: 46, botY: null, botDiameter: 44, agentMode: "none" }` (the shelf view's cat, head ending at x 68, before the list's x 90); `islandSize(mode, view, chatCount = 0, noteLines = 1, overviewExtra = 0)`, an expanded `overview` being `VIEW_LAYOUTS.overview.height + overviewExtra`; `botPosition` reads the overview's height as `Math.min(islandH, VIEW_LAYOUTS.overview.height)` (the big cat does not move down when the section opens; the Mac's guard).
- Produces (`views.ts`): `ViewActions.projects: ProjectActions`; `map.set("projects", buildProjects(actions.projects));`; a header tab `tabProjects` (title "Projects", `svg(ICONS.folder, 13)`) after `tabDrop`. `ICONS.folder` (a filled folder path, comment `// folder.fill`).
- Produces (`island.ts`): the `projects: ProjectActions` entry of `actions` and `openProjects(): void` (`this.alert("projects")`).

- [ ] **Step 1: Write the failing tests** `views.test.mjs`:

```js
import * as L from "../../src/core/layout.ts";
test("the projects view's geometry, and the overview's section height", () => {
  assert.deepEqual(L.VIEW_LAYOUTS.projects, { height: 240, botX: 46, botY: null, botDiameter: 44, agentMode: "none" });
  assert.equal(L.islandSize("expanded", "projects").h, 240);
  assert.equal(L.islandSize("expanded", "overview").h, 160);
  assert.equal(L.islandSize("expanded", "overview", 0, 1, 92).h, 252);
  assert.equal(L.islandSize("expanded", "settings", 0, 1, 92).h, 160, "only the overview grows");
  assert.equal(L.botPosition("expanded", "overview", 252).cy, L.botPosition("expanded", "overview", 160).cy, "the big cat stays where it is");
  const cat = L.botPosition("expanded", "projects", 240);
  assert.ok(cat.cx + cat.diameter / 2 < 90, "the cat's head ends before the list");
});
test("the view is registered and the header gains one tab, after the + tab", () => {
  const v = code("views/views.ts"), header = v.slice(v.indexOf("export function buildHeader"), v.indexOf("function buildOverview"));
  assert.match(v, /map\.set\("projects", buildProjects\(actions\.projects\)\);/);
  assert.match(header, /const tabProjects = h\("button", \{ class: "tab", title: "Projects", onclick: \(\) => go\("projects"\) \}, svg\(ICONS\.folder, 13\)\);/);
  assert.match(header, /h\("div", \{ class: "tabs" \}, tabHome, tabChat, tabDrop, tabProjects\)/);
  assert.match(header, /tabProjects\.classList\.toggle\("on", v === "projects"\);/);
});
test("the views hold no path, call out to nothing, run no loop, show the Mac's words and key every pill by its cell key", () => {
  const p = code("views/projects.ts");
  assert.doesNotMatch(p, /cwd|cwdOf|Bridge|setInterval|requestAnimationFrame/);
  for (const w of ["EMPTY_SCREEN", "dotClass(", "rowDetail(", "hostWord(", "agoWord(", "moreRowsWord(", "pillNameParts(", "new PeekDwell("]) assert.ok(p.includes(w), w);
  assert.match(p, /kept\.get\(cellKey\(/, "an element is found by its cell's key");
  assert.doesNotMatch(p, /\.children\[|childNodes\[/, "never by its slot");
});
test("the peek takes the left card's own box, caps its lines from the card's height, and lets go of a project that left", () => {
  const p = code("views/projects.ts"), css = code("projects/projects.css");
  assert.match(p, /peekLineCapacity\(/);
  assert.match(css, /\.pj-peek \{[^}]*position: absolute;[^}]*inset: 0;[^}]*border-radius: inherit;[^}]*pointer-events: none;/);
  assert.match(p, /sync\(\): void \{[\s\S]*?leave\(\)/);
});
test("the island's actions: a row owning the notch card shows it, else the app by openRoute; the cwd goes only to openInVSCode", () => {
  const i = code("island/island.ts");
  assert.match(i, /State\.pendingApproval\?\.sessionId === sessionId/);
  assert.match(i, /openRoute\("integration_claude", State\.claudeApp, row\.host === "claude-app"\)/);
  assert.match(i, /Bridge\.openInVSCode\(State\.projects\.cwdOf\(sessionId\)\)/);
  assert.equal((i.match(/cwdOf\(/g) ?? []).length, 1, "the one read of a session's folder");
  assert.match(i, /openProjects\(\) \{\s*this\.alert\("projects"\);/);
  assert.match(i, /window\.setTimeout\(\(\) => this\.fsm\.menuHold\(false, this\.wasInIsland\), PIN_MENU_RELEASE_MS\)/, "the Pin menu holds the island a little past its close");
});
```

- [ ] **Step 2: Run:** `cd windows && npm run check:projects 2>&1 | tail -3`. Expected: FAIL.

- [ ] **Step 3: `layout.ts`** as in the Interfaces block (`| "projects"` after `| "link"`; every other entry and line kept).

- [ ] **Step 4: `views/projects.ts` and `projects.css`.** The screen (`.pj-screen`, absolute inset 0, scrolling inside, padding `4px 12px SCREEN_BOTTOM px SCREEN_LEADING px` so the list starts at island x 90 and ends 22 px under the last row): one `.pj-section` per project (a 20 px mini cat of `p.cat` via `createMiniBot(projectTask(p), 20, p.cat)`, the name truncating, `waitingWord(p.waiting)` in amber when above 0), its `sessionRows` indented 28 px; the empty state `EMPTY_SCREEN`. A session line (`.pj-row`): `span.${dotClass(row.state, open)}`, the label, `rowDetail(row.note, row.step)` (amber when it is the note), then right-aligned `${hostWord(row.host)} · ${agoWord(row.agoMin)}`; `.pj-dim` (opacity 0.5) when `row.dim`; a click calls `act.jumpSession(row.id)`; each subagent a `.pj-sub` line indented 16 px (a 12 px mini cat of the project's coat, `subagentWord(type)`). With `limit`, the lines (sessions and subagents together) are cut by `cut()` and the last says `moreRowsWord(more)`. The list redraws only when the `JSON.stringify` of what it shows changed (as the shelf view does). A project pill (`.pill.pj-pill`, the existing pill class): a 22 px mini cat of `p.cat`, the folder (and the detail on a second, smaller line when `pillNameParts` gives one), its state dot at the top right; `.pj-dim` when `p.dim`; `click` → `act.select(p.id)`; `contextmenu` → `preventDefault(); act.menu(p.id)`; `mouseenter`/`mouseleave` → the peek. `keyedCells` keeps one element per `cellKey` in `kept` (built by `make` the first time, refreshed in place by `refresh` when what it shows changed, removed when its key leaves, appended in the cells' order), so an element and its handlers follow its project. `moreCell` is the pill's capsule with `moreWord(count)`; its click is `act.openScreen()`. `ProjectPeek` owns a `PeekDwell` over `{ set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id) }`; it is a `.pj-peek` child of the given card; when shown it calls `src.peek(id)` and fills itself with the name (truncates first) and `sessionsWord` (whole), then `sessionRows(p, null, open, peekLineCapacity(cardH))` of the project read fresh from `src.frame()`; `leave()` hides it and calls `src.peek(null)`; `sync()` leaves when `src.open()` is false or its project is no longer in the frame. Every `ProjectPeek` adds itself to a module `Set` that `leaveAllPeeks()` walks. CSS: new `pj-` rules only, including `@keyframes pj-pulse` used by `.pj-pulse` and the amber `#F5A524` for both waiting states; import the file once in `main.ts` (`import "./projects/projects.css";` after `import "./link/link.css";`).

- [ ] **Step 5: `views.ts` and `icons.ts`.** `projects: ProjectActions;` in `ViewActions` after the `shelf` line with a one-line comment; the tab, its `sync` line; the view registered after `map.set("link", buildLink());`. `folder` in `ICONS`.

- [ ] **Step 6: `island.ts`.** In `build()`'s `actions` after the `shelf:` line add `projects: { select, jumpProject, jumpSession, menu, toggleExpanded, openScreen }`: `select(id)` → `State.projects.select(id); Sound.play("blip"); State.notify()`; `jumpProject(id)` → the project in `State.projectsNow().view`, `State.projects.newestSession(p)`, `jumpSession` its id; `jumpSession(sessionId)`: when `State.pendingApproval?.sessionId === sessionId`, `this.setView("approval")`; else find the row and switch on `openRoute("integration_claude", State.claudeApp, row.host === "claude-app")`: `claude-app` → `void Bridge.openClaudeApp()`, `vscode` → `void Bridge.openInVSCode(State.projects.cwdOf(sessionId))`, otherwise nothing; `menu(id)` → `void this.showProjectMenu(id)`; `toggleExpanded()` → `State.projects.toggleExpanded(); State.notify()` (Task 7 animates the height from the frame); `openScreen()` → `this.openProjects()`. `showProjectMenu(id)`: outside Tauri (`!IS_TAURI`) toggle the pin and notify; inside, build once `{ menu, item }` with `MenuItem.new({ text: "Pin", action: () => { State.projects.togglePin(this.menuTarget); State.notify(); } })`, set `this.menuTarget = id`, `await item.setText(pinTitle(State.projects.isPinned(id)))`, `this.fsm.menuHold(true, this.wasInIsland)`, `await menu.popup()` in a `try`, and in `finally` release the hold with `window.setTimeout(() => this.fsm.menuHold(false, this.wasInIsland), PIN_MENU_RELEASE_MS)` (P-mac: the click that chose the item must not fold the island; on GTK the popup resolves on open, as for the Wardrobe menu). `openProjects()` beside `openShelf()`.

- [ ] **Step 7: Run:** `cd windows && npm run check:projects 2>&1 | grep -E "^ℹ (tests|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ fail"; npx --no-install tsc --noEmit && echo "tsc ok"`. Expected: `fail 0` twice; `tsc ok`.

- [ ] **Step 8: Commit** the eight files: `feat(projects/tauri): the Projects screen, its rows, pills, peek, actions and the header tab`.

---

### Task 6: The Claude-only card, the capsule and chevron, the section

**Agent: `nm-implementer` (Haiku 5.5, high).**

**Files:**
- Modify: `windows/src/views/views.ts` (`buildOverview`; `buildPill` exported as `buildAgentPill`, its body unchanged), `windows/src/views/projects.ts`, `windows/src/views/icons.ts`, `windows/src/projects/projects.css`
- Create: `windows/scripts/projects-tests/overview.test.mjs`

**Interfaces:**
- Consumes: Task 5's `ProjectActions`, `ProjectsSource`, `projectPill`, `moreCell`, `keyedCells`, `ProjectPeek`; `gridCells`, `panelCells`, `pillNameParts` (Task 3); `labelGivesWay` from `./titlefit.ts`.
- Produces (`views/projects.ts`):

```ts
export function buildBigCard(src: ProjectsSource, act: ProjectActions): { el: HTMLElement; sync(): void };   // the left card's body in the Claude-only layout
export function buildProjectGrid(src: ProjectsSource, act: ProjectActions, peek: ProjectPeek, otherPill: (id: string) => HTMLElement | null): { el: HTMLElement; sync(): void };
export function buildTitleCap(act: ProjectActions): { el: HTMLElement; sync(f: ProjectsFrame): void };          // the count capsule(s) and the chevron
export function buildClaudePanel(src: ProjectsSource, act: ProjectActions, peek: ProjectPeek): { el: HTMLElement; sync(): void };
```

`buildBigCard`: a `.pj-big` body with the state dot and the folder (`pillNameParts(big.name).folder`, `.pj-name`, truncates) then `· ${sessionsWord(n)}` as one span (`.pj-count`, `flex: 0 0 auto`, never cut, so its dot never travels alone), the detail on a line of its own when there is one, `bigStepLine(big)` (amber while waiting), `${hostWord(big.host)} · ${agoWord(big.agoMin)}`; `.pj-dim` when dimmed; its own ↗ (`icon-btn jump`, `svg(ICONS.arrowUpRight, 8)`, the shipped button's look), hidden when `openRoute` for the newest session is `none`; a click on the card or the ↗ is `act.jumpProject(big.id)`. `buildProjectGrid`: a `.pills` grid (the existing class) filled by `keyedCells` from `gridCells(projects, otherPills)`: a project cell is `projectPill`, a "+N" `moreCell`, a pill cell the overview's own pill for that id (`otherPill`). `buildTitleCap`: `span.pj-cap` (`flex: 0 0 auto`) holding a grey capsule with `view.projects.length`, an amber capsule with `view.waiting` when above 0, and the chevron button (`icon-btn pj-chev`, `svg(ICONS.chevronDown, 8)`, `.pj-up` while `frame.expanded`, click `act.toggleExpanded()`), `aria-label` `projectsWord(n)` plus `, ${waitingWord(m)}` when above 0. `buildClaudePanel`: `.pj-panel`: a first line `projectsWord(n)` and, when above 0, ` · ${waitingWord(m)}` in amber; then a row (`display: grid`, three columns, `align-items: start` so "+N" sits on the pills' row) from `panelCells`, each project tile a `projectPill` and under it `${sessionsWord} · ${agoWord}`, the big card's project outlined (`.pj-sel`).

- [ ] **Step 1: Write the failing tests** `overview.test.mjs` (pins on `code()`; `fnText`-style slices bounded by the function's closing brace):

```js
const v = code("views/views.ts"), ov = v.slice(v.indexOf("function buildOverview"), v.indexOf("function buildAgentPill"));
test("the Claude-only card takes the two cards only when the frame uses projects, and gives them back whole", () => {
  assert.match(ov, /const frame = State\.projectsNow\(\);/);
  assert.match(ov, /if \(frame\.usesProjects\) \{/);
  assert.match(ov, /mode = null;\s*cardKey = "";\s*pillIds = "";/, "leaving it rebuilds the shipped cards");
  assert.match(ov, /if \(frame\.usesProjects\) \{[\s\S]*?jump\.style\.display = "none";[\s\S]*?return;/, "the shipped ↗ hides while the big card draws its own");
});
test("the capsule and chevron go in the Claude Code card's title row, active or idle, only with frame.chevron; the label rule holds", () => {
  const active = ov.slice(ov.indexOf("if (task && sessionActive) {"), ov.indexOf("} else if (task) {"));
  assert.match(active, /who\.append\(dot\(task\.color, 7\), nameEl, toolEl\);\s*if \(frame\.chevron\) who\.append\(cap\.el\);/);
  assert.ok(active.indexOf("who.append(cap.el)") < active.indexOf("labelGivesWay("), "measured after the capsule is in the row");
  assert.match(ov, /head\.classList\.toggle\("pj-fit", fit\);/);
  assert.match(ov, /if \(fit && labelGivesWay\(name\.scrollWidth, name\.clientWidth\)\) sub\.remove\(\);/);
  assert.match(ov, /el\.classList\.toggle\("pj-open", frame\.panelShown\);/);
});
test("without the capsule both rows are as shipped, and nothing shipped is redefined", () => {
  const css = code("projects/projects.css");
  assert.match(css, /\.int-head\.pj-fit b \{/);
  assert.match(css, /\.view\.overview\.pj-open \{/);
  assert.doesNotMatch(css, /^\.(overview|pill|card|pills|who|int-head)( [^{]*)? \{/m, "no shipped rule is redefined, only pj- classes and pj- modifiers");
  assert.doesNotMatch(code("style.css"), /pj-/, "the shipped stylesheet gains nothing here (Task 7 adds one wing selector)");
});
```

- [ ] **Step 2: Run:** `cd windows && npm run check:projects 2>&1 | tail -3`. Expected: FAIL.

- [ ] **Step 3: Implement.** Rename `buildPill` to `export function buildAgentPill` (body unchanged; its one caller updated). In `buildOverview`: build `const peek = new ProjectPeek(appProjectsSource, left, 108)` (its `el` inside the left card), `big = buildBigCard(…)`, `grid = buildProjectGrid(appProjectsSource, actions.projects, peek, (id) => …the shipped pill for that id from State.pillRow via buildAgentPill…)`, `cap = buildTitleCap(actions.projects)`, `panel = buildClaudePanel(appProjectsSource, actions.projects, peek)` appended to `el`; add `chevronDown: "M5.5 9 12 15.5 18.5 9",` to `ICONS` after `chevronLeft`. At the top of `sync()`: `const frame = State.projectsNow();`. When `frame.usesProjects`: put `big.el` in `leftBody` and `grid.el` in the right card in place of `pills` the first time, `jump.style.display = "none";`, hide the panel, `big.sync(); grid.sync(); peek.sync(); cap.sync(frame);` and return. When not and it was on: put `tickerBody`/`pills` back and `mode = null; cardKey = ""; pillIds = "";` (the shipped `jump.style.display` line below shows the ↗ again). In the active row, the line `if (frame.chevron) who.append(cap.el);` goes right after `who.append(dot(task.color, 7), nameEl, toolEl);` and before the `count` append, so the existing `labelGivesWay` line measures with the capsule in place. In the idle branch, after the card is (re)built: `const head = leftBody.querySelector<HTMLElement>(".int-head")`, `fit = frame.chevron && task.id === "integration_claude"`, `head.classList.toggle("pj-fit", fit);`, append `cap.el` to it when `fit` (else `cap.el.remove()`), then `const name = head.querySelector("b"), sub = head.querySelector("span");` and `if (fit && labelGivesWay(name.scrollWidth, name.clientWidth)) sub.remove();` (a removed subtitle comes back at the next rebuild of the card). Then `cap.sync(frame); el.classList.toggle("pj-open", frame.panelShown); panel.sync(); peek.sync();`. CSS: `.int-head.pj-fit b` (nowrap, ellipsis, `min-width: 0`, `flex: 0 1 auto`) and `.int-head.pj-fit > span` (`flex: 0 0 auto`); `.view.overview.pj-open { bottom: auto; height: 108px; }`; `.pj-panel { position: absolute; left: 0; right: 0; top: 116px; height: 84px; display: none; }` and `.view.overview.pj-open .pj-panel { display: block; }`; `.pj-cap`, `.pj-chev`, `.pj-big`, `.pj-sel`.

- [ ] **Step 4: Run:** `cd windows && npm run check:projects 2>&1 | grep -E "^ℹ (tests|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ fail"; npx --no-install tsc --noEmit && echo "tsc ok"`. Expected: `fail 0` twice (`title-fit.test.mjs` still passes); `tsc ok`.

- [ ] **Step 5: Look at it.** `cd windows && npx vite --host 127.0.0.1 --port 1421` in the background (PID saved under `${TMPDIR:-/tmp}/p-tauri-<unique>/`); open `/`, run `__nm.projects.run("two")` then `__nm.island.alert("overview")`: the Claude-only card; `__nm.projects.run("many")`: three pills and "+5"; `__nm.projects.run("other")`, `__nm.island.collapse()`, `__nm.island.alert("overview")`: the agents layout with the capsule and chevron on the Claude Code card. Stop the server by its PID. (The height and the big cat follow in Task 7.)

- [ ] **Step 6: Commit** the five files: `feat(projects/tauri): the Claude-only card, the count capsule and chevron, the section`.

---

### Task 7: The island frame: look, kittens, peek fade, height, compact count, tick, tray

**Agent: `nm-implementer` (Haiku 5.5, high).** Rust skills from the SUBAGENT RULES.

**Files:**
- Modify: `windows/src/island/island.ts`, `windows/src/style.css` (one selector), `windows/src/main.ts`, `windows/src/core/bridge.ts`, `windows/src/projects/projects.css` (the badge's rule), `windows/src-tauri/src/tray.rs`, `windows/src-tauri/src/lib.rs`; four pins on purpose: `windows/scripts/cat-tests/sites.test.mjs:41`, `dance.test.mjs:91`, `collar-wiring.test.mjs:47`, `wardrobe-wiring.test.mjs:64`
- Create: `windows/scripts/projects-tests/island.test.mjs`

**Interfaces:**
- Consumes: `projectKittens`, `badgeTitle`, `CLAUDE_COLOR` (Task 3), `ProjectsTick` (Task 3), `PANEL_EXTRA` (Task 3), `leaveAllPeeks`, `openProjects` (Task 5), `badgeShown`, `badgeLabel`, `badgePlace` from `../shelf/badge`.
- Produces: `Bridge.projectsMenuText(count: number): Promise<void | null>` → command `projects_menu_text(app, count: u32)`; `pub fn projects_text(count: u32) -> String` in `tray.rs` (`"Projects"` at 0, else `"Projects (N)"`); the tray item id `projects` (emits `tray` `"projects"` like the others).

- [ ] **Step 1: Write the failing tests** `island.test.mjs` (on `code()`):

```js
const i = code("island/island.ts"), main = code("main.ts");
test("the big cat's look: the big card's project's coat and state in the open Claude-only card, else today's; one source for coat, collar, dance and state", () => {
  assert.match(i, /private bigLook\(\): \{ coat: string; state: BotStateName \} \{[\s\S]*?State\.mode === "expanded" && State\.view === "overview" && f\.usesProjects && f\.big/);
  assert.match(i, /const focus = State\.focusTask;\s*const look = this\.bigLook\(\);\s*this\.engine\.setCoat\(look\.coat\);\s*this\.engine\.collarColor = bigCatCollar\(look\.state, focus\?\.color\);/);
  assert.match(i, /this\.engine\.setDancing\(shouldDance\(State\.musicPlaying, look\.state, State\.mode\)\);/);
  assert.match(i, /syncMiniBotStates\(State\.tasks\);\s*this\.engine\.setState\(this\.bigLook\(\)\.state\);/);
});
test("the kittens: the big card's project's subagents in the Claude-only card; the shipped line stays; both step aside while a peek shows", () => {
  assert.match(i, /const big = shown && cast\.big\.pill && !State\.desktopNotchEmpty \? State\.kittenView\(cast\.big\.pill, now\) : \[\]/);
  assert.match(i, /projectKittens\(/);
  assert.match(i, /this\.drawKittenLayer\(dt, greetingActive \|\| this\.peeking\(\)\);/);
  assert.match(i, /this\.botCanvas\.style\.opacity = visible && !State\.desktopNotchEmpty \? "1" : "0";\s*if \(this\.peeking\(\)\) this\.botCanvas\.style\.opacity = "0";/);
});
test("the section's height follows the frame, on the existing spring", () => {
  assert.match(i, /State\.projectsNow\(\)\.panelShown \? PANEL_EXTRA : 0/);
  assert.match(i, /if \(panelShown !== this\.panelWasShown\) \{\s*this\.panelWasShown = panelShown;\s*this\.animateGeometry\(!panelShown\);/);
});
test("the compact count: the shelf badge's rules and spot, waiting first; a click opens the Projects screen; nothing reveals", () => {
  assert.match(i, /const showWait = badgeShown\(State\.mode, frame\.view\.waiting, greetingActive\);/);
  assert.match(i, /const showBadge = badgeShown\(State\.mode, State\.shelf\.count, greetingActive\) && !showWait;/);
  assert.match(i, /this\.waitBadge\.addEventListener\("click", \(e\) => \{ e\.stopPropagation\(\); this\.openProjects\(\); \}\);/);
  assert.match(i, /this\.waitBadge\.title = badgeTitle\(frame\.view\.waiting\);/);
  assert.match(code("style.css"), /#island\.wing-on #projects-badge,\s*#island\.wing-on #shelf-badge \{/);
});
test("the tick runs only while expanded with a live project; the peeks are let go on fold", () => {
  assert.match(i, /this\.projectsTick\.sync\(State\.mode === "expanded" && frame\.view\.projects\.length > 0\);/);
  assert.match(i, /new ProjectsTick\(\{ set: \(fn, ms\) => window\.setTimeout\(fn, ms\), clear: \(id\) => window\.clearTimeout\(id\) \}, \(\) => Date\.now\(\), \(\) => State\.projects\.nextDelay\(\), \(\) => State\.notify\(\)\)/);
  assert.match(i, /if \(mode !== "expanded"\) leaveAllPeeks\(\);/);
});
test("the tray: a Projects item, its words set only when the count changes, and the tray event opens the screen", () => {
  assert.match(main, /case "projects":\s*setPaused\(false\);\s*island\.openProjects\(\);\s*break;/);
  assert.match(main, /if \(n !== lastProjects\) \{\s*lastProjects = n;\s*void Bridge\.projectsMenuText\(n\);/);
  assert.match(source("../src-tauri/src/tray.rs"), /MenuItem::with_id\(app, "projects", "Projects", true, None::<&str>\)\?/);
  assert.match(source("../src-tauri/src/lib.rs"), /tray::projects_menu_text,/);
});
```

(`source("../src-tauri/…")` reads relative to `windows/src/`.) Update the four pins on purpose: `sites.test.mjs:41` to `/const focus = State\.focusTask;\s*const look = this\.bigLook\(\);\s*this\.engine\.setCoat\(look\.coat\);/` (its message: the coat comes from `bigLook`, the cast's unless the Claude-only card shows a project); `dance.test.mjs:91` to `look.state` for `State.effectiveState`; `collar-wiring.test.mjs:47` and `wardrobe-wiring.test.mjs:64` to `bigCatCollar\(look\.state, focus\?\.color\)`.

- [ ] **Step 2: Run:** `cd windows && npm run check:projects 2>&1 | tail -3; npm run check:cat 2>&1 | grep -E "^ℹ fail"`. Expected: FAIL on both.

- [ ] **Step 3: `island.ts`.** (a) `private bigLook(): { coat: string; state: BotStateName }`: when `State.mode === "expanded" && State.view === "overview" && f.usesProjects && f.big` (with `f = State.projectsNow()`), `{ coat: f.big.cat, state: State.stateOverride ?? State.shownState(f.big.state) }`, else `{ coat: State.cast.big.cat, state: State.effectiveState }`. In `drawBot`, after `const focus = State.focusTask;`: `const look = this.bigLook();`, then the coat, the collar and the dance read `look` (the four pinned lines above); in `syncDom` the line after `syncMiniBotStates(State.tasks);` becomes `this.engine.setState(this.bigLook().state);`. (b) `private peeking(): boolean { return State.projectsNow().peeking !== null; }`; the line `if (this.peeking()) this.botCanvas.style.opacity = "0";` right after the pinned opacity line; `this.drawKittenLayer(dt, greetingActive || this.peeking());`. In `drawKittenLayer`, after the pinned `const big = …` line: when the island is expanded on the overview and the frame `usesProjects` with a big card, the list drawn as the big cat's is `projectKittens(f.big.sessions.flatMap((s) => s.subagents))` and its `parentCat` `f.big.cat` and `color` `CLAUDE_COLOR`; otherwise `big` as today (the early return, the pair's count and the single draw read that list). (c) `private panelWasShown = false;`; `targetSize()` passes `State.projectsNow().panelShown ? PANEL_EXTRA : 0` as `islandSize`'s fifth argument; in `syncDom`, `const frame = State.projectsNow(); const panelShown = frame.panelShown;` and the pinned `if` (so the island also shrinks when the last project leaves with the section open). (d) The waiting count: `private waitBadge!: HTMLElement;` made beside `shelfBadge` (`h("button", { id: "projects-badge" })`, `mousedown` stops propagation, `click` as pinned), appended right after `this.shelfBadge` in the island element, placed in `applyGeometry` at the same `badgePlace(w, hh)`; in `syncDom` the find `    const showBadge = badgeShown(State.mode, State.shelf.count, greetingActive);` becomes the two pinned lines, followed by the wait badge's opacity, `pointerEvents`, `textContent = badgeLabel(frame.view.waiting)` and the pinned title, in the shelf badge's pattern. (e) `private projectsTick = new ProjectsTick(…)` as pinned, synced in `syncDom`; in `setMode`, `if (mode !== "expanded") leaveAllPeeks();`.

- [ ] **Step 4: `style.css`.** Add `#island.wing-on #projects-badge,` on its own line just before `#island.wing-on #shelf-badge {` in "The wings step aside" list (the only line added to `style.css`; `u1b-wing-wiring.test.mjs` keeps passing). The badge's own rule goes in `projects/projects.css`: the shelf badge's metrics with `background: #F5A524`, `color: #0b0c0e`.

- [ ] **Step 5: `main.ts` and `bridge.ts`.** In the `tray` switch add `case "projects":` as pinned, after `case "shelf":`'s block. After `State.subscribe(() => Hub.sk?.stateChanged());` add `let lastProjects = -1; State.subscribe(() => { const n = State.projectsNow().view.projects.length; if (n !== lastProjects) { … } });` as pinned. `Bridge.projectsMenuText: (count: number) => call<void>("projects_menu_text", { count }),` beside `desktopMenuText`.

- [ ] **Step 6: Rust.** `tray.rs`: a `ProjectsItem(pub MenuItem<tauri::Wry>)` managed beside `DesktopItem`; `let projects = MenuItem::with_id(app, "projects", "Projects", true, None::<&str>)?;` placed after `shelf` in the menu; `pub fn projects_text(count: u32) -> String`; `#[tauri::command] pub fn projects_menu_text(app: AppHandle, count: u32)` that sets the item's text; a `#[cfg(test)]` test `projects_text(0) == "Projects"`, `projects_text(3) == "Projects (3)"`; the file's first comment lists Projects. `lib.rs`: `tray::projects_menu_text,` after `desktop::desktop_menu_text,` in the handler list.

- [ ] **Step 7: Run:** `cd windows && npm run check:projects 2>&1 | grep -E "^ℹ (tests|fail)"; for s in cat sidekick; do npm run check:$s 2>&1 | grep -E "^ℹ fail"; done; npx --no-install tsc --noEmit && echo "tsc ok"; cd ..; windows/scripts/cargo-linux.sh test -p notchmeow tray --offline --target-dir /repo/windows/target/p-tauri 2>&1 | grep -E "^test result|FAILED|error\[" | head`. Expected: `fail 0` three times; `tsc ok`; `test result: ok` (or "needs Docker").

- [ ] **Step 8: Commit** the eleven files and `island.test.mjs`: `feat(projects/tauri): the island frame: the big cat follows its project, peek fade, section height, waiting count, tick, tray item`.

---

### Task 8: The `?dev` Projects panel

**Agent: `nm-implementer` (Haiku 5.5, high).** Model it on `windows/src/shelf/devshelf.ts`. It is the Windows/Linux twin of the Mac's `render-projects.sh` and `fake-projects-events.py` (the Mac has no Debug panel for Projects, P-mac Plan call 19).

**Files:**
- Create: `windows/src/projects/devprojects.ts`, `windows/scripts/projects-tests/dev.test.mjs`
- Modify: `windows/src/cat/dev.ts` (one import, one call)

**Interfaces:**
- Consumes: `ProjectsModel` (Task 3), `PROJECT_SCENARIOS` (Task 4), `buildBigCard`, `buildProjectGrid`, `buildTitleCap`, `buildClaudePanel`, `buildProjects`, `ProjectPeek`, `type ProjectsSource`, `type ProjectActions` (Tasks 5 and 6), `badgeShown`, `badgeLabel`, `badgePlace`.
- Produces: `export function mountProjectsDev(root: HTMLElement, before: Node | null): void`.

- [ ] **Step 1: Write the failing test** `dev.test.mjs`: `cat/dev.ts` imports `mountProjectsDev` from `../projects/devprojects.ts` and calls `mountProjectsDev(root, wrap);` after `mountLinkDev(root, wrap);`; `devprojects.ts` builds its own `new ProjectsModel(` with a dev clock (`now: () => T0 + offset`), runs no `setInterval` and no `requestAnimationFrame`, names every scenario button from `Object.keys(PROJECT_SCENARIOS)`, and has the buttons `+10 min`, `+30 min`, `+2 h`, `Claude only`, `With other agents`, `Two cats`, `Pin the first`, `Clear`.

- [ ] **Step 2: Run:** `cd windows && npm run check:projects 2>&1 | tail -3`. Expected: FAIL.

- [ ] **Step 3: Implement** a section `#projects-dev` titled "Projects" with the note "The Projects views fed by a registry in memory that follows the contract: pick a scenario, age it, switch the layout, pin. Nothing here is the app's own state." It holds its own `ProjectsModel`, a `ProjectsSource` over it (`frame` with `activePills` `["integration_claude"]` or `["integration_claude", "agent_codex"]` and `twoCats` by the layout buttons, `open: true`, `focusId: "integration_claude"`; `peek` sets the dev model's peek), dev `ProjectActions` that act on its model (`select`, `menu` → `togglePin`, `toggleExpanded`, the jumps and `openScreen` log their target as "jump <host>" or "open screen"), and five black island frames: (1) 640×160 the Claude-only overview (the big card and the grid, a still big cat of the big card's coat at the overview's place), (2) 640×252 the agents layout with the section open (a stand-in Claude Code card with `buildTitleCap` in its title row and `buildClaudePanel` under), (3) 640×240 the Projects screen (`buildProjects(actions, src)`), (4) the peek shown for the first project on its left card, (5) 288×32 the compact strip with the waiting count at `badgePlace`. Each frame re-syncs when a button changes the model (no loop).

- [ ] **Step 4: Run:** `cd windows && npm run check:projects 2>&1 | grep -E "^ℹ (tests|fail)"; npx --no-install tsc --noEmit && echo "tsc ok"`. Expected: `fail 0`; `tsc ok`. Then start the dev server (as in Task 6 Step 5), open `/?dev`, click each scenario and age button once, check the console has no error, stop the server by its PID.

- [ ] **Step 5: Commit** the three files: `feat(projects/tauri): the ?dev Projects panel`.

---

### Task 8b: Owner checkpoint 1 (the main session and the owner)

The worktree session stops and pings the main session. The main session starts the dev server, takes the pictures with the Browser pane (viewport 1280×900 for `/?dev`, 720×320 for `/`) and copies them to `.claude/checkpoints/p-tauri/` of the worktree:

1. `/?dev` Projects panel after `two`, `subagents`, `appWait` and `collide`: the five frames (the same-name pills on two lines, the big card's count whole).
2. The same after `+30 min` (dimmed rows), after `many` ("+N" on the grid and the section, top-aligned) and after `+2 h` (the empty state).
3. `/` (the island page): `__nm.projects.run("two"); __nm.projects.run("appWait"); __nm.island.alert("overview")` (the Claude-only card, the amber pulsing dot first, the big cat in the project's coat and mood), a pointer rest on a pill (the peek on the left card, the big cat gone), `__nm.island.alert("projects")` (the screen: top-aligned, the cat beside the list, the last row clear of the corner), then `__nm.projects.run("other"); __nm.island.collapse()`, reopen with `__nm.island.alert("overview")` (the capsule and chevron), click the chevron (the section on the spring: its first line, the row of three), then fold (the compact waiting count).
4. What to judge, sent to the owner: the pictures against the Mac's checkpoint pictures; Questions for the owner 1 and 2 (below) if still open. Changes go back to Tasks 3, 5, 6 or 7 before Task 9.

---

### Task 9: Settings → Cat → Agents' cats → Project cats

**Agent: `nm-implementer` (Haiku 5.5, high).** Read CLAUDE.md's "Settings on Windows and Linux" bullet first: a page's `sync` never writes the control in use (`setValue`), the kit keeps words whole at 415 px.

**Files:**
- Create: `windows/src/settings/projectcats.ts`, `windows/scripts/projects-tests/settings.test.mjs`
- Modify: `windows/src/settings/cat.ts`, `windows/src/settings/app.ts`, `windows/src/settings/backend.ts`, `windows/src/settings/devseed.ts`, `windows/src/main.ts`, `windows/src/core/bridge.ts`, `tests/fixtures/settings/controls.json` (`cat.display`'s `winHomes`)

**Interfaces:**
- Consumes: `withProjectCat`, `withoutProjectCat` (Task 2); `projectCatRows`, `EMPTY_SETTINGS`, `CATS_HELP`, `type LiveProject` (Task 3); `card`, `row`, `help`, `button`, `setValue` from `./kit.ts`.
- Produces: `projectCatRows` used by `export function projectCatsCard(host: { block(): CatBlock; put(next: CatBlock, final: boolean): void; live(): readonly LiveProject[] }, ui: { menu: …; sized: … }): { el: HTMLElement; sync(): void; draw(dt: number): void }` in `settings/projectcats.ts`; `CatHost.projects?: () => readonly LiveProject[]`; `SettingsBackend.askProjectsLive(): void` and `"projects-live"` in `on`'s event names; `Bridge.emitProjectsLive(list: readonly LiveProject[]): Promise<void>` (to `"settings"`) and `Bridge.askProjectsLive(): Promise<void>` (to `"island"`), both no-ops outside Tauri, through `emitTo` of `@tauri-apps/api/event`.

- [ ] **Step 1: Write the failing test** `settings.test.mjs` (pins on `code()`):

```js
test("the island answers the settings window with the live names whenever they change and when asked; never a path", () => {
  const main = code("main.ts");
  assert.match(main, /const live = State\.projects\.liveProjects\(State\.projectsNow\(\)\.view\);/);
  assert.match(main, /await onEvent<null>\("projects-live-ask", \(\) => void Bridge\.emitProjectsLive\(State\.projects\.liveProjects\(State\.projectsNow\(\)\.view\)\)\);/);
});
test("the settings window listens before its first await, asks once booted, and passes the names to the Cat page", () => {
  const app = code("settings/app.ts");
  assert.ok(app.indexOf('backend.on<LiveProject[]>("projects-live", ') < app.indexOf("await backend.boot()"));
  assert.match(app, /backend\.askProjectsLive\(\);/);
  assert.match(app, /projects: \(\) => projectsLive,/);
  assert.match(code("settings/backend.ts"), /askProjectsLive: \(\) => void Bridge\.askProjectsLive\(\),/);
});
test("the card: in Agents' cats after the agents' card, in every display mode, built from the kit, with the Mac's words", () => {
  const cat = code("settings/cat.ts"), r = code("settings/projectcats.ts");
  assert.match(cat, /if \(projects\) groups\.agentcats\.push\(projects\.el\);/);
  assert.doesNotMatch(cat, /projects\.el\.hidden|projectsCard\.hidden/, "not hidden by the mode");
  assert.match(cat, /display\?\.draw\(dt\);\s*projects\?\.draw\(dt\);/);
  assert.match(r, /card\("Project cats", null,/);
  for (const w of ["projectCatRows(", "withProjectCat(", "withoutProjectCat(", "EMPTY_SETTINGS", "CATS_HELP", "setValue("]) assert.ok(r.includes(w), w);
  assert.doesNotMatch(r, /\.value = /, "a picker is written through setValue only");
});
```

- [ ] **Step 2: Run:** `cd windows && npm run check:projects 2>&1 | tail -3`. Expected: FAIL.

- [ ] **Step 3: Implement.** `projectcats.ts`: `card("Project cats", null, …rows, help(CATS_HELP))`; with no rows, `help(EMPTY_SETTINGS)` instead of the rows; one kit `row(r.name, [preview, picker, reset?])` per `projectCatRows(host.live(), block.projectCats, block.character)` entry: the preview a `.cat-agent-cv` span holding a 40 px canvas of a mini `BotEngine` of `r.cat` (drawn by `draw`), the picker `ui.menu(catOptions, (v) => host.put(withProjectCat(host.block(), r.catKey, v), true))` with its `aria-label` "Cat for <name>", and on a stored one `button("Reset", () => host.put(withoutProjectCat(host.block(), r.catKey), true))`; the rows rebuilt only when the rows' keys, names, cats or stored flags change, otherwise each picker gets `setValue(picker, r.cat)` (so a refused pick at 256 shows the stored cat again). No new CSS (the kit's rows and the agents' `.cat-agent-cv`). `cat.ts`: after the pinned agents' push, `const projects = want("agentcats") ? projectCatsCard({ block: () => host.cat(), put: (next, final) => change(next, final), live: () => host.projects?.() ?? [] }, { menu, sized }) : null;`, the pinned push line, `projects?.sync()` in `paint`, `projects?.draw(dt)` after `display?.draw(dt);`, and `|| projects !== null` in `drawing`. `backend.ts`: the `on` union gains `"projects-live"`, the interface gains `askProjectsLive(): void`, the bridge backend implements it as pinned. `devseed.ts`: `askProjectsLive: () => {}` and `on` calls a `"projects-live"` handler once with `[{ catKey: "notchmeow", name: "notchmeow" }, { catKey: "site", name: "site" }]` on the `ready` sample (stress: one more with a 60-character folder name), and `catFor("ready")` stores `{ site: "oreo" }` (sample names only: `privacy.test.mjs`). `app.ts`: `let projectsLive: LiveProject[] = [];` and its listener (cleans the list to `{catKey, name}` text pairs, then `shell?.sync()`) before the first await; `backend.askProjectsLive();` once booted; `projects: () => projectsLive,` in the Cat host. `main.ts`: a `lastLive` string beside `lastProjects`; when `JSON.stringify(live)` changes, `void Bridge.emitProjectsLive(live)`; and the `projects-live-ask` listener as pinned. `controls.json`: `cat.display`'s `"winHomes"` gains `{ "page": "cat", "tab": "agentcats", "card": "Project cats" }` last.

- [ ] **Step 4: Run:** `cd windows && npm run check:projects 2>&1 | grep -E "^ℹ (tests|fail)"; for s in cat settings; do npm run check:$s 2>&1 | grep -E "^ℹ fail"; done; npx --no-install tsc --noEmit && echo "tsc ok"`. Expected: `fail 0` three times (`map.test.mjs` finds the card title, `pages.test.mjs` and `settings-ui.test.mjs` keep passing); `tsc ok`. Then `bash windows/scripts/render-settings.sh --page cat --tab agentcats` (and `--stress`, and the `empty` sample) and look at 415/720/1100 px: names whole, the picker and Reset never cut. If the Tauri build later refuses `emitTo` from a page (Checkpoint 2), replace the two helpers by a `projects_live_relay` command copied from `desktop_relay` and record it.

- [ ] **Step 5: Commit** the nine files: `feat(projects/tauri): Settings → Cat → Agents' cats → Project cats, with the live names from the island`.

---

### Task 10: Docs

**Agent: `nm-implementer-light` (Haiku 5.5, medium).** Docs only.

**Files:** `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md`, `docs/PROJECTS-CONTRACT.md`, `windows/README.md`

- [ ] **Step 1: `CLAUDE.md`.** After the "Sub-project G2 on Windows/Linux" bullet, one bullet "Sub-project P on Windows/Linux (the Projects view, `docs/PROJECTS-CONTRACT.md`)" naming: `windows/src/projects/core.generated.ts` written by `node scripts/gen-projects-ts.mjs` (never edited by hand; `npm run check:projects` fails on a stale copy, replays all of `tests/fixtures/projects/` with counted groups and the Mac's `projects-scenarios.json` through the model, in CI), `core.ts` types it, `model.ts` (`ProjectsModel`, `State.projects`, fed by `island/hooks.ts` right after the Sidekick, memory only; `State.projectsNow()` is the frame), `cells.ts` and `present.ts` (the Mac's `ProjectsLayout` rules and words), `clock.ts` (the one tick at `nextDelay` while expanded with a project, the peek's 0.4 s dwell), `views/projects.ts` (the screen `projects`, the rows, the pills keyed by `cellKey`, the peek, the Claude-only card, the capsule and chevron, the section), `projects/devprojects.ts` (the `?dev` panel) and `projects/dev.ts` (`__nm.projects`), the compact count on the shelf badge's spot (waiting first), the `projectCats` key of the `cat` block (`cleanCatBlock`, Rust `clean_project_cats`, map key `cat.projectCats`), the tray's Projects item (`projects_menu_text`), Settings → Cat → Agents' cats → Project cats (`settings/projectcats.ts`, the live names as the `projects-live` page event through `SettingsBackend`); no global shortcut; the relay is unchanged. In the "Sub-project P on the Mac" bullet, replace "The Windows/Linux port is P-tauri." by "The Windows/Linux port is P-tauri (below)."

- [ ] **Step 2: `ARCHITECT.md`.** In "7. **Projects (sub-project P).**" replace "The Windows/Linux port is P-tauri (the generated copy)." by a sentence saying P-tauri built it on Windows/Linux (the generated copy, the model fed by `hooks.ts`, the views, the tray item instead of the menu-bar item, no shortcut); keep the rest.

- [ ] **Step 3: `docs/SPEC.md` (French).** At the end of `### Les projets (sous-projet P)`, a paragraph "**Windows et Linux.**": the same rules (the generated copy of the contract) and the same views and words as the Mac; what differs: the screen opens from the folder tab, the tray's « Projects » item and the compact count, with no global shortcut; the compact count takes the shelf badge's place (the wing is 52 px) and hides it while something waits; the peek holds four lines (the card is 108 px); the jump opens the Claude app on Windows, VS Code for a terminal session, nothing on Linux for a Claude App session; Réglages → Cat → Agents' cats, carte « Project cats »; the stored value is `projectCats` in the `cat` block of `settings.json`.

- [ ] **Step 4: `docs/PROJECTS-CONTRACT.md`.** In the "Ports:" line replace "the generated TypeScript copy (P-tauri)" by "the generated TypeScript copy `windows/src/projects/core.generated.ts` (P-tauri, `npm run check:projects`)".

- [ ] **Step 5: `windows/README.md`.** In "Using it", the tray row reads "Open, Shelf, Projects, Cat on the desktop …"; a section "## Projects" after "## The shelf" (each layout, the screen, the peek, Pin, the waiting count and its shared spot, project cats, what is kept in memory only, no shortcut); under "Build it yourself" a "### Testing the projects" paragraph (`npm run check:projects`, `?dev`'s Projects panel, `__nm.projects.run(name)` and `__nm.projects.age(minutes)` on the dev server, the Rust filters `cat_settings` and `tray`); in "What's different from the Mac version" one line: Projects opens from the tray and the folder tab, with no global shortcut, and its compact count shares the shelf badge's spot.

- [ ] **Step 6: Run:** `cd windows && for s in projects cat sidekick settings link; do npm run check:$s 2>&1 | grep -E "^ℹ fail"; done; npx --no-install tsc --noEmit && echo "tsc ok"; cd ..; node scripts/gen-projects-ts.mjs --check; bash scripts/test-projects-contract.sh | tail -2`. Expected: `fail 0` five times; `tsc ok`; the copy matches; the contract passes.

- [ ] **Step 7: Commit** the five files: `docs(projects/tauri): CLAUDE.md, ARCHITECT.md, SPEC.md, the contract's ports, the README`.

Then the session dispatches the whole-branch review (`nm-reviewer-deep` with `pr-review-toolkit:silent-failure-hunter`, `pr-review-toolkit:pr-test-analyzer` and `security-review` on `git diff main...HEAD`), fixes what it finds in one wave, runs Step 6 again, and stops for Task 11.

---

### Task 11: Owner checkpoint 2: the real machines (the main session and the owner)

Owed, none claimed: on Windows, a Claude Code session in Windows Terminal and one in the Claude desktop app each make a project (the Claude App request shows "Waiting in Claude App" and the count); a worktree session under `.claude\worktrees\` is a side session; the tray's Projects item and its count; the Pin menu (Pin, then fold and reopen: the big card is the pinned project; the island did not fold on the menu's click); the jump (the Claude app; VS Code); the section and its spring; the compact count's click while the wing rule is inactive; Settings → Cat → Agents' cats with the island running (the page events allowed by `core:default`), a picked coat showing on the pill at once, Reset on a stored row; the compile of the Windows-only Rust (CI). On Linux (X11 and Wayland): the same, without the Claude app, and the Pin menu on GTK (its popup resolves on open: the 500 ms release may end before the pick).

---

## Plan calls (Windows/Linux only; everything else follows the Mac)

1. The compact count shares the shelf badge's spot, waiting first (Question 1).
2. The peek's line capacity is the Mac's rule on Windows/Linux's 108 px card: 4 lines.
3. The Projects screen's cat is the shelf view's (x 46, Ø44); the list starts at island x 90 as on the Mac.
4. The ↗ of the big card is hidden only when the jump has no route (Linux, a Claude App session).
5. The section's `PIN_MENU_RELEASE_MS` tail is a `setTimeout` per menu, the Mac's 0.5 s.
6. The `?dev` panel is the twin of the Mac's render and fake-events scripts; the Mac keeps its scripts, so neither app has less.

## Questions for the owner

**Owner's answers, 2026-10-21:** 1 (a), the waiting count shares the shelf badge's spot, waiting first (the plan as written); 2 (a), the three reserved folder names keep the Main cat on both apps, no contract change. Both are settled: Checkpoint 1 does not reopen them.

1. **Where does the compact waiting count sit?** The Mac puts it 66 pt from the right edge, in the right wing's free inner end. On Windows/Linux the compact island is 288 px with a 52 px wing that the 2×2 grid and the shelf badge already fill (`MINI_CELL`, `badgePlace`), so 66 px from the edge is inside the 184 px middle, which stays empty on a PC for parity with the notch. Options: (a) share the shelf badge's spot, waiting first (the plan as written); (b) draw it at x = w − 66 in the middle, beside the shelf badge, always reachable even with the wing rule on. **Recommended: (a)**, since the middle is the island's hover zone and never shows anything, and the shelf comes back as soon as nothing waits.
2. **Folders named `prototype`, `constructor` or `__proto__`.** The core refuses them as cat keys (an object-key hazard), so they wear the Main cat and their Settings picker does nothing, on the Mac today and in this plan. P-mac's review left it to you. Options: (a) keep it, both apps as they are; (b) a later contract change (P-0.1, both apps): the core picks a coat from the name for them as for any folder, and the Settings row shows that cat with no picker. **Recommended: (a) now, (b) only if it ever bites**: such a project folder is improbable, and (b) changes a fixture group and the Mac's Settings card.

## Dry run (what was checked while refreshing, at `684e015c`)

- **Baselines run:** `check:cat` 635 tests, `check:sidekick` 140, `check:settings` 368, `check:link` 45, each `fail 0`; `tsc --noEmit` clean; `bash scripts/test-projects-contract.sh` green (8 fixtures match).
- **Every find text of Task 0 Step 2 was counted** and prints `1`, except `this.engine.setState(State.effectiveState);`, which occurs twice (the dizzy recovery and `syncDom`): Task 7 uses the two-line find after `syncMiniBotStates(State.tasks);`.
- **Moved since the draft:** Settings: `settings/display.ts` no longer returns `after` and `settings/main.ts` only starts the app; the cards are built in `settings/cat.ts` (`groups.agentcats.push(...)`, pinned by `pages.test.mjs:754`), the window's data flows through `SettingsBackend` (`backend.ts`, `devseed.ts`'s `on: () => {}`), the map is `controls.json`'s `winHomes`/`win` replayed by `map.test.mjs` (52 entries; `cat.projectCats` joins `cat.display`, so the count stays). The title row: `labelGivesWay` in `views/titlefit.ts`, pinned by `title-fit.test.mjs` (`who.append(dot(task.color, 7), nameEl, toolEl)` exact, measured after); the idle row is `integrations.ts`'s `header()` (`.int-head` with `b` and `span`), reached from `views.ts` after `renderIntegrationCard`.
- **Pins this plan meets:** `desktop-island.test.mjs:64` and `:67` pin the big cat's opacity line and the `const big = …` kitten line (both kept; the plan adds lines after them); `sites.test.mjs:41`, `dance.test.mjs:91`, `collar-wiring.test.mjs:47`, `wardrobe-wiring.test.mjs:64` pin `State.cast.big.cat` / `State.effectiveState` in `drawBot` (Task 7 changes them on purpose); `display.test.mjs:90` and `:96` pin the block's keys (Task 2); `settings-ui.test.mjs:41` pins `display?.draw(dt);` right after the preview (Task 9 appends after it); `u1b-wing-wiring.test.mjs` pins `#island.wing-on #shelf-badge` (Task 7's line goes before it).
- **Geometry checked:** the compact island is 288 px (`COMPACT_W`), the notch 184, each wing 52; the grid's cells sit at 240 and 256 (Ø13), the shelf badge at w − 25: no free spot in the wing (Question 1). The overview's cards fill 108 px (content padding 8/10/10, header 34): the section sits at 116 for 84 px in a 252 px island; the peek capacity is 4 there. `botPosition` centres the overview's cat on the island's height (hence the Mac's clamp). The projects view's cat at x 46 Ø44 ends at 68, before the list's 90.
- **Facts re-checked:** the relay forwards `cwd`, `session_id`, `agent_id`, `agent_type`, `term_program`, `nm_agent` and drops `tool_response`, `transcript_path`, `agent_transcript_path`, `last_assistant_message`, `prompt_response` (`windows/hook/src/main.rs` line 39); the feed's place in `handleHook` (after `routeHook` and `Hub.sk?.hook`, before `island.agentActivity()` and the `switch`); `activeIntegrations` holds the services and the two agent switches under one cap of four (`toggleIntegration`); `State.pillRow` already leaves out the focused pill; `State.focusId` is `string | null`; `core:default` covers the `island` and `settings` windows (`capabilities/default.json`); `createMiniBot` keeps a mini cat's engine while its canvas is connected, so a pill element kept by key keeps its cat; `stepLabel`'s words (`Runs`, `Searches`, `Web search`) come from `TOOL_LABELS`.
- **Task 0b's numbers:** the new cases add 3 event rows (50 → 53) and one registry case of 18 payload steps and 2 views (30 → 31 cases, 85 → 103 and 50 → 52 steps), the four literals of `tests/ProjectsRegistryTests.swift`; the Swift port already applies both caps (`ProjectsRegistry.swift` lines 143, 257, 360), so its replay passes once the counts change. The stepped ask is the oldest pending entry, so the 17th asker drops it at once: the view at +18000 has no note, and at +200000 the session is `working`.
- **Not run:** the DOM views and the island frame (checked by comment-blind source pins, the Mac's scenarios through the model, and the Checkpoint 1 pictures), the Rust (Docker not started for this refresh), anything with a real window, the Tauri `emitTo` permission (Task 9 and Task 11), the GTK Pin menu (Task 11).
