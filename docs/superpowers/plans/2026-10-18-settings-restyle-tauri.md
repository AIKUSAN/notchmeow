# Settings restyle (Windows and Linux): Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows/Linux Settings window (`windows/settings.html`, today one long dark scrolling page of ten sections) becomes the Mac's six pages: General, Agents, AI and chat, Services, Cat, Devices.
- The sidebar collapses to icons in a narrow window.
- Tabs appear where the Mac has them, minus what this platform lacks.
- The window follows the system's light or dark appearance.
- One small layout kit keeps every word whole and every button untruncated from 415 px to full screen.
- Agents get per-agent "Where you code" switches that share the four-slot rule.
- Every control that exists today has a named home, and every stored value keeps its key and meaning.

**Architecture:** Four parts.
1. **Pure rules.** Plain TypeScript with no DOM, tested by `node --test` in `windows/scripts/settings-tests/`:
   - `route.ts`: pages, tabs, and how old stored tags map to them.
   - `layout.ts`: widths, and the `~` display of paths.
   - `status.ts`: status words.
   - `drafts.ts`: typed but unsaved text.
   - `sidekicktab.ts`: the Sidekick tab's rules.
   - `airows.ts`: the AI rows and Make main.
   - `aicache.ts`: the AI cache's refresh rule.

   They port the merged Mac rules. Drift pins that read the Swift sources keep them in step, and `tests/fixtures/settings/controls.json` gains a Windows/Linux column.
2. **The island side of the agent switches.** In `core/state.ts`, an agent pill that is on stays on the island and takes a slot (the Mac's rule). The hook path is untouched.
3. **A DOM kit (`kit.ts`) and a shell (`shell.ts`).** The shell builds each page only while it is shown. A token palette in `settings.css` has dark and light values, and contrast tests check every text pair. Every page takes a `SettingsCtx` whose `backend` is either the real Tauri bridge or a dev-server sample backend (`devseed.ts`). That lets `windows/scripts/render-settings.sh` and a `?dev` panel draw every page, in both appearances, before the real window switches over (owner checkpoint 1). The render script uses headless Chrome on `npx vite`, renders through an iframe harness, and asserts each frame's width.
4. **The swap.** `settings/main.ts` boots `app.ts` with the bridge backend, the old section functions are deleted, and the source pins move with the code. Rust changes three things in `lib.rs`: the window's size, an optional page for `open_settings_window`, and a `settings-hidden` event.

**Tech Stack:**
- TypeScript (strict, `verbatimModuleSyntax`), with plain DOM through `h()` (`windows/src/views/dom.ts`).
- CSS custom properties in `windows/src/settings/settings.css`, switched by `prefers-color-scheme`.
- Node 22 `--experimental-strip-types --test`.
- Vite 6, dev server only.
- Tauri 2 / Rust, `lib.rs` only.
- Headless Google Chrome and `sips` for the pictures. Both are already on the owner's Mac; nothing is installed.

**Spec:** `docs/superpowers/specs/2026-10-17-settings-restyle-design.md`. It was owner-approved on 2026-10-17 with its "Calls made by the main session", "Calls made after the builder check" and "Owner's answers" 1 to 5. **"Owner's answers for Windows and Linux (2026-10-18)" 6 and 7** add light mode and agent switches for this platform. The spec's "Windows and Linux" section is this plan's brief.

The plan to mirror is `docs/superpowers/plans/2026-10-17-settings-restyle-mac.md` (merged as `50e55140`). The rulings in its ledger apply here wherever this platform has the same thing, and each is carried into the task that owns it. The ledger files are `.claude/archive/sdd/settings-restyle-mac/progress.md`, `polish-brief.md` and `final-fix-brief.md`.

The rules this plan ports live in `NotchBuddy/Sources/App/`: `SettingsRoute.swift`, `SettingsLayout.swift`, `SettingsStatus.swift`, `SettingsDraftBook.swift`, `SettingsSidekick.swift`, `SettingsAI.swift` and `SettingsColors.swift`. The Mac's contrast test is `tests/SettingsContrastTests.swift`. The Mac's hidden-pill rule is `AppState.loadIntegrationTasks`, `removeTask` and `toggleIntegration`, together with `HookServer.upsertWorkspaceTask`.

**Base:** a new branch `settings/restyle-tauri` in a git worktree from `main` at `50e55140` or later (`git merge-base --is-ancestor 50e55140 HEAD` must succeed). If a find text below does not occur exactly the number of times stated, stop and report; do not guess.

## Global Constraints

Every task's requirements include this section. A line marked "Plan call" is a choice this plan makes where the spec leaves one, with its reason.

- **TypeScript and plain DOM; no new dependency.** No npm package or crate is added; `package.json` gains one script line. Pure rule files import only `.ts` paths and `import type`, so Node can load them. Rust changes only `windows/src-tauri/src/lib.rs`.
- **The never-restyle rule is lifted for the Settings window only.** That means `windows/settings.html` and `windows/src/settings/`, plus the one island rule in `core/state.ts` that answer 7 asks for (Task 4).
  - These stay exactly as in `main`: the island's `src/style.css`, `src/views/`, `src/link/link.css` (pinned by `link-tests/wiring.test.mjs`) and every other view.
  - Settings keeps its controls: `.switch`, `button`, `button.primary`, `button.danger`, `.hint`, `.notice`, `.diff`, `.path`.
  - New rules use the `st-` prefix.
  - Colours are tokens on `:root` only (Task 6). The cats and their black preview boxes keep their own colours.
- **Light and dark (answer 6).** Settings follows `prefers-color-scheme`: the dark values are today's look, and the light values mirror the Mac Settings' light look. Every pair of text and background meets 4.5:1 in both appearances, which is the floor of the Mac's `test-settings-contrast.sh`. `contrast.test.mjs` proves it.
- **Numbers are the Mac's `SettingsLayout.swift`**, and a drift pin holds them there (Task 1). All are CSS px, which are the window's logical px.
  - Window: minimum content 415 × 420, default 720 × 560, no maximum.
  - Breakpoint 600: a narrower window gets the icon sidebar (CSS `@media (max-width: 599.98px)`).
  - Sidebar 200 wide, or 56 collapsed.
  - Column at most 640, centred beyond that.
  - Side padding 20, or 16 collapsed.
  - Field at most 420; number field 64; picker 180.
  - Help text 12; tab bar row 28.
- **Pages and tabs are the Mac's, minus what this platform lacks.**
  - **General has no tabs.** Windows and Linux have no global shortcuts and no island key list (CLAUDE.md: "The Windows and Linux app has none"; `grep -rlE "global-shortcut|globalShortcut|global_shortcut" windows/src windows/src-tauri` finds nothing). Plan call: a single tab is no tab bar.
  - **Absent, not greyed:** the Codex hooks card (`HookAgent` is `"gemini" | "antigravity"`), Plan usage, the main-pill picker, the AI pill switches, Apple on-device, Music, and the Resend From field. None of them exists in the Windows app today.
  - **Agents → "Where you code" (answer 7)** has a switch for Gemini CLI and one for Antigravity, the two agents whose hooks this platform installs. Claude Code always shows the "Main" chip.
  - **Windows/Linux only:** "Island lives on" (`screen`), in General → Island.
- **Every stored value keeps its name and meaning.**
  - `settings.json` keeps the `Settings` and `AiSettings` fields and the `cat` and `sidekick` blocks.
  - The credential store keeps the eleven keys, `custom-server-key.default` and the link's items.
  - `link.json` keeps `visible` and `deviceName`.
  - New keys:
    - The Settings window's `localStorage` gains `settingsSection` and `settingsTab.<page>`. Plan call: this is per-viewer UI state, read and written inside `try`/`catch`, falling back to General.
    - Answer 7's stored setting is the agent pill ids `agent_gemini` and `agent_antigravity` inside the existing `activeIntegrations` list. Plan call: the Mac stores agent switches exactly so, in the same list as services, and the shared four-slot cap counts that list. The default list holds no agent, so every existing user keeps today's behaviour: an agent's pill shows while it works and goes when its session ends. Rust's `Vec<String>` already keeps any id, so no Rust twin is needed.
  - Task 2's map test proves nothing is lost or renamed.
- **Frozen IDs untouched:** pill IDs (`agent_gemini` and `agent_antigravity` included), cat IDs, outfit IDs, `notchmeow-hook`, and the bundle identifier.
- **The agent switch never touches the hook path.** `windows/hook/` and `island/hooks.ts` are not modified. The relay still answers at once, a request on an agent whose switch is off is shown exactly as today, and the switch only decides whether the pill stays after the session.
- **Secrets.**
  - The page never reads a stored secret back; it knows only whether one exists (`secret_present`).
  - Keys are typed into `type="password"` fields.
  - Saving is a click. Typed text is never saved by a page or tab change, a close or a hide, and it is dropped on Rust's `settings-hidden` (Task 3).
  - A refused credential-store write shows the error and is never shown as saved.
  - Removing or replacing a server's key is awaited. If it fails, nothing else happens, so no server is left without its key and no old key is sent to a new origin.
  - Pictures and samples use made-up values only (`sample-key-0000`, home `C:\Users\sample`).
- **No CPU while Settings is hidden, and no new timer, observer or poll while it is open.**
  - Hidden pages and tabs are not in the DOM, and their cat previews and Devices' "on screen" report stop when they are left.
  - The only new listeners are `window` `resize` (the tab bar's fit, coalesced to one `requestAnimationFrame` per burst) and the three Rust events.
  - No `setInterval`, `ResizeObserver` or `MutationObserver`.
  - The one-shot `setTimeout`s that ship today move unchanged: the hook card's 2.6 s refresh and the Cat page's 3 s "Done".
- **A page's `sync()` never overwrites the control the user is in.** No `input`, `select` or range that is `document.activeElement` is written by a sync. A volume slider mid-drag and a field being typed in keep their values, as `devices.ts` already does for its name field.
- **Network calls are today's only.** The model list is fetched on a key save, and when the AI and chat page is shown or refocused (stale after 10 min). Discovery runs at the same moments. A Get link opens the system browser on a click.
- **The confirm flows do not change.** Each hook card keeps its preview diff, "Back up and write" / "Back up and remove", Cancel, `hooks_apply` / `agent_hooks_apply` with the preview's fingerprint, and the error path with Back. Paths and diffs are *shown* with the home folder as `~`; this is display only, and the file keeps the real path.
- **Never block an agent; never overwrite a hook file without a backup and a confirm.** The Rust flows are unchanged.
- **No telemetry.** Nothing new is logged.
- **macOS is primary.**
  - Mac files are not modified, except `tests/fixtures/settings/controls.json`. It gains keys the Mac decoder ignores (`win`, `winHomes`, `winOnly`, `winPages`).
  - `bash scripts/test-settings-map.sh` and `bash scripts/test-settings-wiring.sh` must still pass.
- **Rust only through Docker.**
  - Tests: `windows/scripts/cargo-linux.sh … --target-dir /repo/windows/target/settings-tauri`.
  - Windows type check: `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-settings-tauri`.
  - Docker Desktop must be running; if it is not, stop and ask the owner.
- **The site bundle is untouched.**
  - Nothing changes under `windows/src/cat/` except one mount line in `cat/dev.ts`, which the site does not import.
  - Nothing changes in `src/site/` or the theme.
  - `bash scripts/check-site.sh` passes unchanged, and `docs/assets/cats.js` is not rebuilt.
- **Models and commits** (CLAUDE.md, "Working with AI agents").
  - Haiku 5.5 first; Sonnet 5.5 only on a named trigger; never Opus or Fable.
  - Each commit is local, never pushed, and lists only its task's files.
  - Commit with `git commit -F <file>`, ending the message with the `Co-Authored-By` line of the model that did the task.
- **Plans in flight cite anchors this plan deletes.**
  - `2026-10-17-focus-awareness-tauri.md` greps the Open on hover hint in `settings/main.ts` (its line 108) and adds its row there (its Task 4).
  - `2026-10-17-p-tauri-projects.md` changes `settings/main.ts` and `settings/display.ts` (its Task 9).
  - After Task 13 here, those anchors are in `general.ts`, `app.ts` and `cat.ts`. Whichever plan lands second ports the other's rows (the **[focus]** and **[projects]** steps here). The main session tells those plans' sessions; this plan does not edit them.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app, and never run `npm run tauri dev`. `npx vite` and the render script are not the app and may run; stop them by PID when done.
  2. Install nothing and download nothing: no `npm install`, `docker build` or `docker pull`. The only network use is the local Vite server on 127.0.0.1.
  3. Delete by hand only with `trash`, never `rm -rf`. Put scratch files under `${TMPDIR:-/tmp}` in a uniquely named folder.
  4. Never read, print or write real credential-store items, `~/.claude`, `~/.gemini` or the real `settings.json`. No real user or machine name goes in any file, picture or sample.
  5. Never edit any of these:
     - `design/prototype/cat-core.js` or anything under `shared/`;
     - generated files (`core.generated.ts`, `theme.generated.*`);
     - a fixture other than `tests/fixtures/settings/controls.json`;
     - any `NotchBuddy/` file, `src/style.css`, `src/link/link.css` or `docs/assets/`;
     - `windows/hook/` or `island/hooks.ts`.
  6. Never push. Commit only in a task's commit step, and only after `git rev-parse --show-toplevel` shows this worktree and `git branch --show-current` shows `settings/restyle-tauri`.
  7. Never rename a frozen ID or a stored key. Write no `Coucou` or `Mochi` name anywhere.
  8. Stop and report if a command is denied by a permission prompt, or if a find text occurs a different number of times than stated.

## Review Focus

The spec says what Settings does but is silent on these conditions, listed most likely first. Each line names the test that pins it.

1. **The narrowest column with the longest strings.**
   - At 415 px the column is 327 px, less the card's padding.
   - The strings: a 90-character Windows path; a diff line with an escaped relay path; a long model id; a long server or machine name ("Forget A machine with a rather long name…?"); a long error; "Use my OpenAI plan" with "Coming with the new chat".
   - Expected: words wrap between words, rows stack, ordinary buttons and chips never truncate, a machine button may wrap between its words, a path may break anywhere inside a path block, and there is no horizontal scroll.
   - Tests:
     - Task 5's CSS pins.
     - Every page drawn at a frame width of exactly 415, in both appearances and with `--stress`: Tasks 7 to 10, with the harness asserting the width.
     - Checkpoint 1.
2. **Leaving Devices must close the pairing gate.** With pages, Devices leaves the screen when another page is chosen while the window stays visible.
   - Expected: `setDevicesOpen(false)` is sent as soon as the page is left, and its listeners are removed.
   - Tests: Task 5 (the shell disposes the old page before building the next) and Task 8 (`dispose` removes `pagehide` and `focus` and sends `false`).
3. **A sync while the user is in a control.**
   - The case: the island changes a setting (`settings-changed`) while the user drags the volume slider or types in a field.
   - Expected: the control the user is in keeps its value, and only the other controls update.
   - Tests: Task 5 (`setValue` skips `document.activeElement`), Task 8 and Task 12 (the shell calls page `sync` only through it).
4. **The four-slot cap shared by agents and services while the island changes the list.**
   - The case: two agents and two services are on, and the island turns one off while Services is shown.
   - Expected: every off switch on every page reads the new count. At four, an off switch is disabled with "4 of 4 slots used. Turn another off.", and General's line is amber and names the four.
   - Tests: Task 1 (`pillSwitch`, `slots`), Task 4 (island cap), Task 7 (every switch built from `pillSwitch`) and Task 12 (`settings-changed` → `shell.sync()`).
5. **The `~` display of Windows and Linux paths.** The cases:
   - `C:\Users\sam\.claude\settings.json`;
   - the JSON-escaped form inside a diff;
   - the relay under `%LOCALAPPDATA%` written with another case (`c:\users\SAM\AppData\Local\…`);
   - a relay outside the home (`D:\Tools\…`, `/opt/…`);
   - `/home/sam/…`;
   - a home whose name is a prefix of another (`C:\Users\sam` vs `C:\Users\samuel`).

   Expected: `~` replaces the home, case-insensitively on Windows, so the user name never shows when the path is under the home. A path outside the home is shown as it is. Tests: Task 1 (`displayPath`, `displayText`), Task 7 (every path and diff on Agents goes through them) and Task 5 (privacy pin).

Also covered:
- An agent switched off while its session runs or its card waits: Task 4 (the pill is never removed while not idle).
- A server added with a key the credential store refuses: Task 9 (aborted, URL not saved).
- A kind's switch versus the dismissal memory: Task 1 (`stuckSwitch`, `withMuted`).
- A garbage stored selection: Task 1 (`migrate`, `tabFor`).
- An `open_settings_window` place that is not a page: Task 3 (`settings_place`).

---

## File Structure

| Path | Responsibility |
|---|---|
| `windows/src/settings/route.ts`, `layout.ts`, `status.ts`, `drafts.ts`, `sidekicktab.ts` (new); `windows/src/sidekick/settings.ts` (`withMuted`) | Pure rules A (Task 1). |
| `windows/scripts/settings-tests/rules.test.mjs`, `drift.test.mjs` (new); `windows/package.json` (`check:settings`); `.github/workflows/windows-tests.yml` | Their tests and CI (Task 1). |
| `windows/src/settings/airows.ts`, `aicache.ts` (new); `tests/fixtures/settings/controls.json` (Windows column) | Pure rules B (Task 2). |
| `windows/scripts/settings-tests/airows.test.mjs`, `aicache.test.mjs`, `map.test.mjs` (new) | Their tests (Task 2). |
| `windows/src-tauri/src/lib.rs`; `windows/src/core/bridge.ts`; `windows/src/views/{views,chat,shelfdevice}.ts`; `windows/src/island/island.ts`; `windows/scripts/settings-tests/window.test.mjs` (new) | Window size, open at a place, the hidden event (Task 3). |
| `windows/src/core/state.ts`, `windows/scripts/cat-tests/agent-switch.test.mjs` (new) | Agent switches on the island (Task 4). |
| `windows/src/settings/kit.ts`, `shell.ts`, `backend.ts`, `ctx.ts`, `app.ts`, `icons.ts`, `devseed.ts`, `devpanel.ts` (new); `settings.css`; `settings/main.ts` (dev route); `cat/dev.ts` (one line); `windows/scripts/render-settings.sh` (new); `windows/scripts/settings-tests/kit.test.mjs`, `privacy.test.mjs` (new) | The kit, the shell, the sample frame, the shot harness and the pictures (Task 5). |
| `windows/src/settings/settings.css` (tokens), `windows/settings.html`, `windows/src/settings/devices.ts` (one colour), `windows/scripts/settings-tests/contrast.test.mjs` (new) | The light and dark palette (Task 6). |
| `windows/src/settings/agents.ts`, `services.ts` (new) | Agents (with Where you code) and Services (Task 7). |
| `windows/src/settings/general.ts` (new), `devices.ts` | General and Devices (Task 8). |
| `windows/src/settings/ai.ts` (new) | AI and chat: Your AI, Keys, Local models (Task 9). |
| `windows/src/settings/sidekick.ts`, `cat.ts`, `display.ts`, `wardrobe.ts` | The Sidekick tab and the Cat tabs (Task 10). |
| `windows/src/settings/main.ts`, `app.ts`, `settings.css`; moved pins in `windows/scripts/{cat,sidekick,link}-tests/` | The swap (Task 12). |
| `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, `docs/SPEC.md` | Docs (Task 13). |

## Tasks and agents

Every coding agent loads `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`.
- The deep agent also loads `superpowers:systematic-debugging`.
- The kit, palette and page tasks (5 to 10 and 12) read `frontend-patterns`, a file at `~/.claude/plugins/marketplaces/ecc/skills/frontend-patterns/SKILL.md`.
- Tasks 5 to 10 also read `accessibility` and `design-system` (files in the same folder) as an audit only. ARCHITECT.md's "Settings polish" says `design-system` never writes a tokens file. The Settings palette lives in `settings.css`, not `shared/theme.json`, which stays untouched.
- Task 3 reads `rust-patterns` and `rust-testing` (files).

Reviewers load `ponytail:ponytail-review`. The final reviewer also loads `security-review` (credential store, hook writers, the place event) and runs `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` beside it (`model: sonnet`, trigger 4).

| # | Task | Agent, model, effort | Trigger | Review |
|---|---|---|---|---|
| 0 | Worktree and baseline | the session | | none |
| 1 | Pure rules A: route, layout, status, drafts, Sidekick tab, drift pins | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 2 | Pure rules B: AI rows, AI cache, the map's Windows column | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 3 | Rust and bridge: window size, open at a place, `settings-hidden` | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 4 | Agent switches on the island (the Mac's hidden-pill rule) | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 5 | The kit, the shell, the backend, the sample frame, the shot harness, `?dev`, the render script | `nm-implementer`, Haiku 5.5, high (`nm-implementer-deep` only after two failures, trigger 2) | | `nm-reviewer` |
| 6 | The light and dark palette, contrast-tested | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 7 | Pages: Agents (with Where you code) and Services | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 8 | Pages: General and Devices | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 9 | Pages: AI and chat (Your AI, Keys, Local models) | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 10 | Pages: the Sidekick tab and the Cat tabs | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 11 | **Owner checkpoint 1:** the pictures, dark and light | the main session and the owner | | none |
| 12 | The swap: the real window boots the shell; old sections out; pins moved | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 13 | Docs | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| After 13 | Whole branch: nothing lost, secrets, absences, CPU, the gate, the hook path | `nm-reviewer-deep`, Sonnet 5.5, high | 4 | none |
| 14 | **Owner checkpoints 2 and 3:** the real window on Windows and Linux, then sign-off | the owner (and the main session) | | none |

**Task 5 runs on Haiku** (`nm-implementer`, high), by the main session's ruling. If Haiku fails it twice, it moves to `nm-implementer-deep` (Sonnet 5.5, trigger 2). It is the hardest task in the plan, because the kit is where the spec's layout promises are designed:
- CSS that keeps labels whole and stacks rows only when they do not fit;
- the icon sidebar;
- the tab bar's text-or-menu fallback;
- a page lifecycle that builds only the shown page and disposes the last one first. Devices' pairing gate and the Cat loop depend on that order.
- a `sync` that never writes the active control;
- a shot harness that gives headless Chrome a real 415 px viewport. Chrome clamps its own window to 500 px.

Its brief carries every value above, so Haiku has nothing to invent.

**Why Task 4 is Haiku.** It copies an existing Mac rule into three `State` methods, with tests that pin each case. No trigger applies. If a Haiku task fails twice, hand it to `nm-implementer-deep` (trigger 2) and write the trigger in the ledger.

## Execution

- **Session.** One worktree chat session runs the whole plan on branch `settings/restyle-tauri`, at **Sonnet 5.5, high effort**. That is trigger 5: an app plan with many cross-task interfaces (the kit, `SettingsCtx`, six page builders, the backend, the palette and the AI cache).
- **Start-up**, in the three steps of `ARCHITECT.md`:
  1. The chip runs only Task 0 Steps 1 to 3, reads `CLAUDE.md`, `ARCHITECT.md`, this plan and the spec, replies "ready" and stops.
  2. The main session sets the model and effort.
  3. The main session sends the controller brief.
- **Ledger.** `.superpowers/sdd/2026-10-18-settings-tauri/progress.md`, one line per task.
- **Reviews** read `git diff main...HEAD`, narrowed to the task's files.
- **Bash blocks.** Every ```` ```bash ```` block passes `bash -n` before it is run.
- **Pings.** The session pings the main session with `SendMessage` at Task 11, at the end, and whenever it stops.
- **Order.**
  1. Run Tasks 1 to 10.
  2. Stop for checkpoint 1. The pictures go in `.claude/checkpoints/settings-tauri/` of the worktree and are never committed.
  3. Run Tasks 12 and 13 and the whole-branch review.
  4. Stop for Task 14.

**Plans in flight that touch the same files.** Each follows the spec's "Rows other plans add". See also the Global Constraints' coordination note.
- **Focus awareness (Tauri)** adds `"Step back when I'm already in the app"` with `settings.focusAware` to today's `generalSection`, and pins it in `windows/scripts/cat-tests/focus-wiring.test.mjs`.
  - Check: `grep -c focusAware windows/src/core/state.ts` ≥ 1 means it is merged.
  - If it merges before Task 8, Tasks 2, 8 and 12 carry its row and move its pin (steps marked **[focus]**).
- **Projects (P-tauri)** adds `settings/projectcats.ts` and its box in `display.ts`'s `after`. It also adds a `projects-live` listener in `settings/main.ts`, pinned in `windows/scripts/projects-tests/settings.test.mjs`.
  - Check: `grep -c projectCats windows/src/cat/display.ts` ≥ 1 means it is merged.
  - If it merges before Task 10, Tasks 10 and 12 carry it (steps marked **[projects]**).
- **F3a (companion)** has no Windows Settings part yet; `COMPANION_TAB_SHOWN` stays `false`.

---

### Task 0: Worktree and baseline

- [ ] **Step 1: Branch and dependencies.**
  - `git switch -c settings/restyle-tauri main`, then check that `git merge-base --is-ancestor 50e55140 HEAD && echo ok` prints `ok`.
  - `cp -cR "$MAIN_CHECKOUT/windows/node_modules" windows/node_modules`, where `MAIN_CHECKOUT` is the main checkout of this repository. This is an APFS clone, as in G2-tauri. It must be a real folder, because `.gitignore` ignores the folder; nothing is downloaded.
- [ ] **Step 2: Anchors.** Each command prints `1` unless noted.
  ```bash
  W=windows/src; R=windows/src-tauri/src
  grep -c '.inner_size(560.0, 680.0)' $R/lib.rs
  grep -c '.min_inner_size(460.0, 480.0)' $R/lib.rs
  grep -c 'fn open_settings_window(app: AppHandle) {' $R/lib.rs
  grep -c 'link_cmd::settings_hidden(&app);' $R/lib.rs
  grep -c 'openSettingsWindow: () => call<void>("open_settings_window"),' $W/core/bridge.ts
  grep -c 'export type HookAgent = "gemini" | "antigravity";' $W/core/bridge.ts
  grep -c 'export const mute = SidekickCore.mute' $W/sidekick/core.ts
  grep -c 'export function catSection(host: CatHost)' $W/settings/cat.ts
  grep -c 'export function sidekickSection(host: SidekickHost)' $W/settings/sidekick.ts
  grep -c 'agentHooksSection({ agent: "antigravity"' $W/settings/main.ts
  grep -c '  toggleIntegration(id: string) {' $W/core/state.ts
  grep -c '  removeTask(id: string) {' $W/core/state.ts
  grep -c 'State.removeTask(agentId);' $W/island/hooks.ts                 # 2
  grep -c 'color-scheme: dark;' $W/settings/settings.css
  grep -c 'style="background: #0b0c0e; color: #f5f6f8"' windows/settings.html
  grep -c 'static let breakpoint = 600.0' NotchBuddy/Sources/App/SettingsLayout.swift
  grep -rlE "global-shortcut|globalShortcut|global_shortcut" windows/src windows/src-tauri/src windows/src-tauri/Cargo.toml | wc -l   # 0
  grep -c focusAware $W/core/state.ts          # 0, or ≥1: [focus] steps apply
  grep -c projectCats $W/cat/display.ts         # 0, or ≥1: [projects] steps apply
  ```
- [ ] **Step 3: Baseline.** Every command below must pass; write the last line of each in the ledger.
  - From `windows/`: `npx --no-install tsc --noEmit`, then `npm run check:cat`, `npm run check:sidekick`, `npm run check:link`, `npm run check:claude` and `npm run check:ai`.
  - From the repo root: `bash scripts/check-site.sh`, `bash scripts/test-settings-map.sh` and `bash scripts/test-settings-wiring.sh`.
  - Rust: `windows/scripts/cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/settings-tauri`.

---

### Task 1: Pure rules A: route, layout, status, drafts, the Sidekick tab, drift pins

**Files:**
- Create: `windows/src/settings/route.ts`, `layout.ts`, `status.ts`, `drafts.ts`, `sidekicktab.ts`, `windows/scripts/settings-tests/rules.test.mjs`, `windows/scripts/settings-tests/drift.test.mjs`
- Modify: `windows/src/sidekick/settings.ts`, `windows/package.json`, `.github/workflows/windows-tests.yml`

**Interfaces (Produces; later tasks use these exact names):**
```ts
// route.ts
export type Page = "general" | "agents" | "chat" | "services" | "cat" | "devices";
export type Tab = "general" | "shortcuts" | "yourai" | "keys" | "localmodels" | "sidekick" | "companion" | "look" | "outfits" | "personality" | "agentcats";
export interface Place { page: Page; tab: Tab | null }
export const PAGES: readonly Page[];                       // sidebar order
export const COMPANION_TAB_SHOWN = false;
export const SHORTCUTS_TAB_SHOWN = false;                  // no global shortcuts on Windows and Linux
export const SECTION_KEY = "settingsSection";
export function tabKey(page: Page): string;                 // "settingsTab.<page>"
export function pageTitle(page: Page): string;
export function tabTitle(tab: Tab): string;
export function pageColor(page: Page): string;
export function tabs(page: Page, opts?: { companion?: boolean; shortcuts?: boolean }): Tab[];
export function migrate(stored: string | null | undefined): Place;
export function tabFor(page: Page, stored: string | null | undefined): Tab | null;
// layout.ts
export type SidebarMode = "expanded" | "icons";
export const MIN_W = 415, MIN_H = 420, DEFAULT_W = 720, DEFAULT_H = 560, BREAKPOINT = 600, SIDEBAR_WIDE = 200, SIDEBAR_ICONS = 56,
  COLUMN_MAX = 640, PADDING = 20, PADDING_COLLAPSED = 16, FIELD_MAX = 420, NUMBER_FIELD = 64, PICKER_WIDTH = 180, HELP_SIZE = 12, TAB_BAR_HEIGHT = 28;
export function sidebarMode(windowWidth: number): SidebarMode;
export function columnWidth(windowWidth: number): number;
export function displayPath(path: string, home: string): string;
export function displayText(text: string, home: string): string;
// status.ts
export interface Slots { text: string; names: string[]; full: boolean }
export interface PillSwitch { showsSwitch: boolean; chip: string | null; disabled: boolean }
export type Tone = "ok" | "warn" | "neutral" | "error";
export const MAX_SLOTS = 4;
export const CAP_SENTENCE = "4 of 4 slots used. Turn another off.";
export function slots(active: readonly string[], catalog: readonly { id: string; name: string }[]): Slots;
export function pillSwitch(isOn: boolean, isMain: boolean, activeCount: number, missing: string | null): PillSwitch;
export function hookChip(installed: boolean | null, needsUpdate: boolean): string | null;
export function keyChip(saved: boolean): string;           // "Ready" | "No key yet"
export function serviceChip(saved: boolean): string;       // "Saved" | "No key yet"
export function tone(chip: string): Tone;
// drafts.ts
export class DraftBook {
  constructor(present: Record<string, boolean>);
  text(id: string): string;
  edit(id: string, text: string): void;
  isDirty(id: string): boolean;             // text(id).trim() !== ""
  anyDirty(ids: readonly string[]): boolean;
  isSaved(id: string): boolean;
  markSaved(id: string, present: boolean): void;   // after a write or removal that succeeded: typed text cleared, presence set
  setPresent(id: string, present: boolean): void;  // a fresh look: typed text kept
  clearTyped(): void;                       // the window was hidden
}
// sidekicktab.ts
export const STUCK_KINDS: readonly NudgeKind[];
export const STUCK_NAMES: readonly { kind: NudgeKind; label: string }[];
export const PERMISSION_LINE = "Always on: it tells you what a permission would do.";
export const NOTHING_LEAVES = "Nothing leaves this computer unless you pick a cloud AI as your main AI.";
export const COMES_WITH_F3A = "Comes with F3a";
export function stuckSwitch(isMuted: (kind: string) => boolean): { on: boolean; detail: string | null };
export function example(kind: string): string | null;
// sidekick/settings.ts (added)
export const withMuted = (s: SidekickSettings, kind: NoteKind): SidekickSettings => …;   // cleanSidekickSettings({ ...s, dismissals: mute(s.dismissals, kind) })
```

The rules, exactly. Each one is the Swift rule of the same name unless it says otherwise.
- **`PAGES`, titles, colours.**
  - `PAGES`: `["general", "agents", "chat", "services", "cat", "devices"]`.
  - `pageColor`: general `#8E939C`, agents `#3B9EFF`, chat `#E07950`, services `#7C5CFF`, cat `#D9A066`, devices `#5B8DEF`.
  - `tabTitle`: General, Shortcuts, Your AI, Keys, Local models, Sidekick, Companion, Look, Outfits, Personality, Agents' cats.
- **`tabs`.** `opts` defaults to `{ companion: COMPANION_TAB_SHOWN, shortcuts: SHORTCUTS_TAB_SHOWN }`.
  - general: `["general", "shortcuts"]` when `shortcuts`, else `[]`.
  - chat: `["yourai", "keys", "localmodels", "sidekick"]`, plus `"companion"` last when `companion`.
  - cat: `["look", "outfits", "personality", "agentcats"]`.
  - agents, services, devices: `[]`.
- **`migrate`.** It is the Mac's rule, with one Plan call: a tab is returned only when `tabs(page)` shows it.
  - Old tags: `activepills` → general; `integrations` → services; `shortcuts` → general (tab only if shown); `sidekick` → chat with tab `sidekick`.
  - A bare page name → that page, tab null.
  - `<page>/<tab>` (one slash) with a known page and a shown tab → that place.
  - A known page with an unknown or hidden tab → the page, tab null.
  - Anything else → general, tab null.
- **`tabFor`.** The stored tab when it is shown, else `tabs(page)[0]`, else `null`.
- **`sidebarMode`, `columnWidth`.**
  - The mode is `"icons"` when `windowWidth < BREAKPOINT`, else `"expanded"`.
  - The column is `max(0, min(windowWidth - sidebar - 2 × padding, COLUMN_MAX))`. The sidebar is 56 in icons mode and 200 otherwise; the padding is 16 in icons mode and 20 otherwise.
- **`displayPath`.** Plan call: it understands both separators, and is case-insensitive for a Windows home.
  - The relay path comes from `%LOCALAPPDATA%` or `XDG_DATA_HOME` (`settings::hook_exe_path`), not from `home_dir`, so its case may differ from the home's.
  - Empty `home` → unchanged.
  - A Windows home (it matches `/^[A-Za-z]:\\/`) compares case-insensitively; a POSIX home compares exactly.
  - `path` equal to `home` → `~`.
  - A path that starts with `home + "\\"` or `home + "/"` → `~` plus the rest, the rest kept as written.
  - Anything else, a path outside the home included, is unchanged.
- **`displayText`.** Display only. With the same case rule as `displayPath`, apply these replacements in order:
  1. `escHome + "\\\\"` → `~\\`. `escHome` is `home` with each `\` doubled: the JSON-escaped form serde writes.
  2. `home + "\\"` → `~\`.
  3. `home + "/"` → `~/`.
  4. `home.replaceAll("/", "\\/") + "\\/"` → `~\/`.

  Build each pattern as a `RegExp` from the escaped literal, with the flags `gi` for a Windows home and `g` otherwise. An empty `home` changes nothing.
- **`slots`.**
  - `text` is `"<n> of 4 slots used"`.
  - `names` are the catalog names of the active ids, in catalog order. An id the catalog does not hold is counted but not named.
  - `full` is `n >= 4`.
- **`pillSwitch`.**
  - The main pill → `{ showsSwitch: false, chip: "Main", disabled: false }`.
  - Off and at the cap → `{ true, CAP_SENTENCE, true }`.
  - Otherwise → `{ true, missing, false }`.
- **`hookChip`.** `needsUpdate` → `"Needs update"`; else `true` → `"Installed"`, `false` → `"Not installed"`, `null` → `null`.
- **`tone`.**
  - ok: `Ready`, `Installed`, `Saved`, `Main`, or anything starting `Running`.
  - warn: `Needs update`, `Not saved`, `Hooks not installed`, `Key not configured`, `Not connected`, `Update needed`, `CAP_SENTENCE`, or anything starting `Off`.
  - error: `Not ready`.
  - neutral: everything else.
- **`DraftBook`.** Plan call: the page never holds a stored secret, so "dirty" means "something typed", and Remove is the explicit way to clear a stored value.
- **`stuckSwitch`.** With n muted among the four kinds:
  - n = 4 → `{ on: false, detail: null }`.
  - n = 0 → `{ on: true, detail: null }`.
  - Otherwise → `{ on: true, detail: "<4-n> of 4" }`.
- **`example`.** It runs the core's own wording (`nudgeText`, `recapOf` from `../sidekick/core.ts`) on a made-up session at `now = 10_000_000`. It never touches a live ledger.
  - The session: `key: "integration_claude|example"`, `agentId: "integration_claude"`, `sessionId: "example"`, `startedAt: now - 20 min`, `lastEventAt: now - 5 min`, `endedAt: null`, `state: "approval"`, `last: ""`, `project: "my-app"`, `pendingApprovalAt: now - 30_000`, `pendingKey: null`, `subagents: {}`, `nudgedAt: null`.
  - Its `ring`: three entries `{ at: now - (3 - i) min, kind: "tool", tool: "Edit", target: f, file: f, key: "Edit#i", ok: true }` for `f` in `app.ts`, `lib.ts`, `main.ts`.
  - A stuck kind → `nudgeText({ kind, reasonId: "example", key, agentId }, { sessions: [s] }, now, { platform: "windows" })`.
  - `recap` → the first line of `recapOf({ awaySince: now - 10 min, now, sessions: [s] })`.
  - Anything else → `null`.

- [ ] **Step 1: Write the failing test** `windows/scripts/settings-tests/rules.test.mjs` (`node:test`, `node:assert/strict`; it imports the five `.ts` files and `../../src/sidekick/settings.ts`). The cases:
  ```js
  // route
  assert.deepEqual(PAGES, ["general", "agents", "chat", "services", "cat", "devices"]);
  assert.deepEqual(PAGES.map(pageTitle), ["General", "Agents", "AI and chat", "Services", "Cat", "Devices"]);
  assert.deepEqual(tabs("general"), []);
  assert.deepEqual(tabs("general", { shortcuts: true }), ["general", "shortcuts"]);
  assert.deepEqual(tabs("chat"), ["yourai", "keys", "localmodels", "sidekick"]);
  assert.equal(tabs("chat", { companion: true }).at(-1), "companion");
  assert.deepEqual(tabs("cat").map(tabTitle), ["Look", "Outfits", "Personality", "Agents' cats"]);
  for (const p of ["agents", "services", "devices"]) assert.deepEqual(tabs(p), []);
  assert.ok(PAGES.every((p) => tabs(p).length <= 4));
  assert.equal(tabKey("cat"), "settingsTab.cat");
  assert.deepEqual(PAGES.map(pageColor), ["#8E939C", "#3B9EFF", "#E07950", "#7C5CFF", "#D9A066", "#5B8DEF"]);
  const M = (s) => migrate(s);
  assert.deepEqual(M("activepills"), { page: "general", tab: null });
  assert.deepEqual(M("integrations"), { page: "services", tab: null });
  assert.deepEqual(M("shortcuts"), { page: "general", tab: null });
  assert.deepEqual(M("sidekick"), { page: "chat", tab: "sidekick" });
  for (const p of PAGES) assert.deepEqual(M(p), { page: p, tab: null });
  for (const bad of [null, undefined, "", "Chat", "bogus", "yourai", "/keys", "nope/keys", "chat/keys/x", "chat/", "Chat/keys"]) assert.deepEqual(M(bad), { page: "general", tab: null }, String(bad));
  assert.deepEqual(M("chat/keys"), { page: "chat", tab: "keys" });
  assert.deepEqual(M("chat/look"), { page: "chat", tab: null });
  assert.deepEqual(M("chat/companion"), { page: "chat", tab: null });
  assert.deepEqual(M("general/shortcuts"), { page: "general", tab: null });
  assert.deepEqual(M("agents/keys"), { page: "agents", tab: null });
  for (const p of PAGES) for (const t of tabs(p)) assert.deepEqual(M(`${p}/${t}`), { page: p, tab: t });
  assert.equal(tabFor("cat", "outfits"), "outfits");
  assert.equal(tabFor("cat", "keys"), "look");
  assert.equal(tabFor("chat", "companion"), "yourai");
  assert.equal(tabFor("agents", "keys"), null);
  assert.equal(tabFor("general", "shortcuts"), null);
  // layout
  const W = [415, 559, 560, 599, 600, 720, 1100, 3000];
  assert.deepEqual(W.map(sidebarMode), ["icons", "icons", "icons", "icons", "expanded", "expanded", "expanded", "expanded"]);
  assert.deepEqual(W.map(columnWidth), [327, 471, 472, 511, 360, 480, 640, 640]);
  for (let w = 415; w <= 3000; w++) assert.ok(columnWidth(w) >= 327, String(w));
  assert.equal(columnWidth(40), 0);
  const home = String.raw`C:\Users\sam`;
  assert.equal(displayPath(String.raw`C:\Users\sam\.claude\settings.json`, home), String.raw`~\.claude\settings.json`);
  assert.equal(displayPath(String.raw`c:\users\SAM\AppData\Local\NotchMeow\bin\notchmeow-hook.exe`, home), String.raw`~\AppData\Local\NotchMeow\bin\notchmeow-hook.exe`);
  assert.equal(displayPath(String.raw`D:\Tools\NotchMeow\bin\notchmeow-hook.exe`, home), String.raw`D:\Tools\NotchMeow\bin\notchmeow-hook.exe`);
  assert.equal(displayPath(home, home), "~");
  assert.equal(displayPath(String.raw`C:\Users\samuel\x`, home), String.raw`C:\Users\samuel\x`);
  assert.equal(displayPath("/home/sam/.gemini/settings.json", "/home/sam"), "~/.gemini/settings.json");
  assert.equal(displayPath("/home/Sam/x", "/home/sam"), "/home/Sam/x", "POSIX is case-sensitive");
  assert.equal(displayPath("/opt/notchmeow/bin/notchmeow-hook", "/home/sam"), "/opt/notchmeow/bin/notchmeow-hook");
  assert.equal(displayPath("/a/b", ""), "/a/b");
  assert.equal(displayText(String.raw`+  "command": "C:\\Users\\sam\\AppData\\Local\\NotchMeow\\bin\\notchmeow-hook.exe --agent gemini"`, home),
    String.raw`+  "command": "~\\AppData\\Local\\NotchMeow\\bin\\notchmeow-hook.exe --agent gemini"`);
  assert.equal(displayText(String.raw`+  "command": "c:\\users\\SAM\\AppData\\x.exe"`, home), String.raw`+  "command": "~\\AppData\\x.exe"`);
  assert.equal(displayText(String.raw`Backup → C:\Users\sam\.claude\settings.json.bak-20261018`, home), String.raw`Backup → ~\.claude\settings.json.bak-20261018`);
  assert.equal(displayText('"command": "/home/sam/.local/share/notchmeow/bin/notchmeow-hook"', "/home/sam"), '"command": "~/.local/share/notchmeow/bin/notchmeow-hook"');
  assert.equal(displayText(String.raw`{"command":"\/Users\/name\/.claude\/notchmeow\/nm-hook"}`, "/Users/name"), String.raw`{"command":"~\/.claude\/notchmeow\/nm-hook"}`);
  assert.ok(!/sam/i.test(displayText(String.raw`C:\\Users\\sam\\x and C:\Users\sam\y`, home)));
  assert.equal(displayText(String.raw`C:\Users\samuel\x`, home), String.raw`C:\Users\samuel\x`);
  // status
  const cat = [{ id: "agent_gemini", name: "Gemini CLI" }, { id: "integration_resend", name: "Resend" }, { id: "integration_github", name: "GitHub" }];
  assert.deepEqual(slots(["integration_github", "agent_gemini"], cat), { text: "2 of 4 slots used", names: ["Gemini CLI", "GitHub"], full: false });
  assert.equal(slots(["integration_github", "integration_resend", "agent_gemini", "integration_gone"], cat).full, true);
  assert.deepEqual(pillSwitch(false, true, 4, "x"), { showsSwitch: false, chip: "Main", disabled: false });
  assert.deepEqual(pillSwitch(false, false, 4, null), { showsSwitch: true, chip: "4 of 4 slots used. Turn another off.", disabled: true });
  assert.equal(pillSwitch(true, false, 4, null).disabled, false);
  assert.deepEqual(pillSwitch(false, false, 1, "Hooks not installed"), { showsSwitch: true, chip: "Hooks not installed", disabled: false });
  assert.deepEqual([hookChip(true, true), hookChip(true, false), hookChip(false, false), hookChip(null, false)], ["Needs update", "Installed", "Not installed", null]);
  assert.deepEqual([keyChip(true), keyChip(false), serviceChip(true), serviceChip(false)], ["Ready", "No key yet", "Saved", "No key yet"]);
  assert.deepEqual(["Ready", "Running, 4 models", "Installed", "Saved", "Main", "Needs update", "Not saved", CAP_SENTENCE, "Off", "Not ready", "No key yet", "Coming with the new chat", "Server off"].map(tone),
    ["ok", "ok", "ok", "ok", "ok", "warn", "warn", "warn", "warn", "error", "neutral", "neutral", "neutral"]);
  // drafts
  const d = new DraftBook({ "anthropic-api-key": true, "resend-api-key": false });
  assert.equal(d.text("anthropic-api-key"), ""); assert.ok(!d.isDirty("anthropic-api-key")); assert.ok(d.isSaved("anthropic-api-key"));
  d.edit("resend-api-key", "  "); assert.ok(!d.isDirty("resend-api-key"), "spaces alone are not a draft");
  d.edit("resend-api-key", " re_123 "); assert.ok(d.isDirty("resend-api-key")); assert.ok(d.anyDirty(["n8n-url", "resend-api-key"]));
  assert.ok(!d.isDirty("anthropic-api-key"), "another field is untouched");
  d.setPresent("resend-api-key", false); assert.equal(d.text("resend-api-key"), " re_123 ");
  d.markSaved("resend-api-key", true); assert.equal(d.text("resend-api-key"), ""); assert.ok(d.isSaved("resend-api-key")); assert.ok(!d.isDirty("resend-api-key"));
  d.edit("anthropic-api-key", "sk-new"); d.clearTyped(); assert.equal(d.text("anthropic-api-key"), ""); assert.ok(d.isSaved("anthropic-api-key"));
  d.markSaved("anthropic-api-key", false); assert.ok(!d.isSaved("anthropic-api-key"));
  assert.equal(d.text("nope"), ""); assert.ok(!d.isSaved("nope"));
  // sidekick tab
  assert.deepEqual(stuckSwitch(() => false), { on: true, detail: null });
  assert.deepEqual(stuckSwitch((k) => k.startsWith("stuck.")), { on: false, detail: null });
  assert.deepEqual(stuckSwitch((k) => k !== "stuck.loop" && k.startsWith("stuck.")), { on: true, detail: "1 of 4" });
  assert.deepEqual(STUCK_NAMES.map((n) => n.label), ["Repeated steps", "Repeated errors", "Waiting for your OK", "Gone quiet"]);
  assert.equal(example("stuck.loop"), "Claude Code has run the same step 4 times.");
  assert.equal(example("stuck.errors"), "Claude Code hit 3 errors in a row.");
  assert.equal(example("stuck.waiting"), "Claude Code is still waiting for your OK.");
  assert.equal(example("stuck.silent"), "Claude Code has been quiet for 5 minutes.");
  assert.ok(example("recap")?.startsWith("While you were away, Claude Code in my-app"));
  for (const k of ["recap", ...STUCK_KINDS]) assert.ok(!(example(k) ?? "/").includes("/") && !(example(k) ?? "\\").includes("\\"), k);
  assert.equal(example("risk"), null);
  const s0 = cleanSidekickSettings(null);
  assert.equal(withMuted(s0, "recap").dismissals.recap, 2);
  assert.equal(withMuted({ ...s0, dismissals: { ...s0.dismissals, recap: 1 } }, "recap").dismissals.recap, 2);
  assert.equal(withUnmuted(withMuted(s0, "stuck.loop"), "stuck.loop").dismissals["stuck.loop"], 0);
  assert.deepEqual(s0, cleanSidekickSettings(null), "withMuted does not change its input");
  ```
- [ ] **Step 2: Write the failing drift test** `windows/scripts/settings-tests/drift.test.mjs`. It reads `../../../NotchBuddy/Sources/App/<file>` as text, and each assertion message names the Swift file it checks.
  - **(a) `SettingsLayout.swift`.** Each `static let` number equals its TS constant. Parse the `static let` lines with `/(\w+) = ([\d.]+)/g`. The pairs: `minWidth`↔`MIN_W`, `minHeight`↔`MIN_H`, `defaultWidth`↔`DEFAULT_W`, `defaultHeight`↔`DEFAULT_H`, `breakpoint`↔`BREAKPOINT`, `sidebarWide`↔`SIDEBAR_WIDE`, `sidebarIcons`↔`SIDEBAR_ICONS`, `columnMax`↔`COLUMN_MAX`, `padding`↔`PADDING`, `paddingCollapsed`↔`PADDING_COLLAPSED`, `fieldMax`↔`FIELD_MAX`, `numberField`↔`NUMBER_FIELD`, `pickerWidth`↔`PICKER_WIDTH`, `helpSize`↔`HELP_SIZE`, `tabBarHeight`↔`TAB_BAR_HEIGHT`.
  - **(b) `SettingsRoute.swift`.** It contains:
    - `case general, agents, chat, services, cat, devices`, and the raw values `yourai`, `localmodels` and `agentcats`;
    - every TS page and tab title as `return "<title>"`;
    - every page colour as `"#XXXXXX")`;
    - `[.yourAI, .keys, .localModels, .sidekick]` and `[.look, .outfits, .personality, .agentCats]`.
  - **(c) `SettingsStatus.swift`.** It contains `capSentence = "4 of 4 slots used. Turn another off."`, and each word of the TS `tone` lists inside its `tone(` function.
  - **(d) `SettingsSidekick.swift`.** It contains `permissionLine = "<PERMISSION_LINE>"`, `comesWithF3a = "<COMES_WITH_F3A>"` and the four labels. Its `nothingLeaves`, with `this Mac` replaced by `this computer`, equals `NOTHING_LEAVES`. Plan call: the platform word is the one allowed difference.
- [ ] **Step 3: npm script and CI.**
  - In `windows/package.json` `scripts`, after `"check:sidekick"`, add `"check:settings": "node --experimental-strip-types --test --test-reporter=spec scripts/settings-tests/*.test.mjs",`.
  - In `.github/workflows/windows-tests.yml`, add `- 'tests/fixtures/settings/**'` and `- 'NotchBuddy/Sources/App/Settings*.swift'` to both `paths:` lists (`pull_request` and `push`).
  - In the same file, add this step after `Link checks`:
  ```yaml
      - name: Settings checks
        run: npm run check:settings
  ```
- [ ] **Step 4: Run** `cd windows && npm run check:settings`. It fails: the modules are missing.
- [ ] **Step 5: Implement** the five files and `withMuted`. Each file opens with a header comment naming the spec section and the Swift file it ports. None uses a clock, the DOM, storage or `Bridge`.
- [ ] **Step 6: Verify.** `npm run check:settings`, `npm run check:sidekick` and `npx --no-install tsc --noEmit` all pass.
- [ ] **Step 7: Commit** the ten files: `feat(settings/tauri): the pure rules of the restyled Settings, held to the Mac's by drift pins`.

---

### Task 2: Pure rules B: AI rows, the AI cache, the map's Windows column

**Files:**
- Create: `windows/src/settings/airows.ts`, `windows/src/settings/aicache.ts`, `windows/scripts/settings-tests/airows.test.mjs`, `aicache.test.mjs`, `map.test.mjs`
- Modify: `tests/fixtures/settings/controls.json`, `windows/scripts/settings-tests/drift.test.mjs`

**Interfaces:**
- **Consumes:** `status.ts` (`keyChip`). It takes `import type` only from `../core/state` (`ModelChoice`), `../core/bridge` (`AiServer`, `ModelInfo`) and `../core/claude` (`ClaudeStatus`).
- **Produces:**
```ts
// airows.ts
export type KeyProvider = "anthropic" | "google" | "openai";
export type Row = { kind: "claudePlan" } | { kind: "openAIPlan" } | { kind: "key"; provider: KeyProvider } | { kind: "server"; id: string };
export interface ServerIn { id: string; name: string; network: boolean; models: string[] }   // id = AiServer.provider
export interface AiInput {
  claudeState: ClaudeStatus["state"] | null; claudeEnabled: boolean; claudeModel: string;
  keys: readonly KeyProvider[]; cloudModel: Record<string, string>; servers: readonly ServerIn[]; memory: Record<string, string>;
}
export type Choice = { provider: string; model: string };
export type MakeMain = { kind: "set"; choice: Choice } | { kind: "menu"; choices: Choice[] } | { kind: "unavailable"; reason: string };
export const PLAN_LINE = "Runs your own installed app, signed in by you. NotchMeow never sees your login.";
export const COMING = "Coming with the new chat";
export const KEY_PROVIDERS: readonly KeyProvider[];          // ["anthropic", "google", "openai"]
export function rowKey(r: Row): string;                      // "claudePlan" | "openAIPlan" | "key:<p>" | "server:<id>"
export function rows(i: AiInput): Row[];
export function title(r: Row, i: AiInput): string;
export function line(r: Row, i: AiInput): string;
export function chip(r: Row, i: AiInput): string;
export function makeMain(r: Row, i: AiInput): MakeMain;
export function helpLine(r: Row, i: AiInput): string | null;
export function reasonLine(r: Row, i: AiInput): string | null;
export function isMain(r: Row, chat: ModelChoice): boolean;
export function serverChip(status: AiServer["status"], modelCount: number): string;
export function getLink(provider: string): string | null;
// aicache.ts
export interface AiBackend {
  aiDiscover(): Promise<AiServer[] | undefined>;
  aiListModels(provider: string): Promise<ModelInfo[]>;      // throws on a failed check
  claudeStatus(): Promise<ClaudeStatus | undefined>;
}
export class AiCache {
  servers: AiServer[]; models: Record<string, ModelInfo[]>; claude: ClaudeStatus | null;
  works: Record<string, { ok: boolean; text: string } | undefined>;
  constructor(backend: AiBackend, providers: readonly { id: string; key: string }[], present: (key: string) => boolean, now?: () => number);
  loadCloud(id: string): Promise<boolean>;
  forget(id: string): void;
  refreshOnOpen(): Promise<boolean>;                         // false when skipped: running, or < 1000 ms since the last one ended
  setServers(next: AiServer[]): boolean;                     // false when JSON-equal
}
```

The rules, exactly:
- **`rows`.** In order: `claudePlan`, `openAIPlan`, then `key` for each of `KEY_PROVIDERS`, then `server` for each server with at least one model, in input order. There is no Google plan row (owner's answer 5) and no Apple row.
- **`title`.** `Use my Claude plan`; `Use my OpenAI plan`; `Anthropic API key`; `Google AI API key`; `OpenAI API key`; a server row uses the server's name.
- **`line`.**
  - Both plan rows → `PLAN_LINE`.
  - A key row → `Your own key, saved on the Keys tab.`
  - A server → `A model server on this computer.`, or `A model server on your network.` when `network`.
- **`chip`.**
  - Claude plan:
    - `signedIn` and enabled → `Ready`;
    - `signedIn` and not enabled → `Off`;
    - `signedOut` → `Not signed in`;
    - `notInstalled` → `Not installed`;
    - `tooOld` → `Needs update`;
    - `unknown` or `null` → `Not ready`.
  - OpenAI plan → `COMING`.
  - A key row → `keyChip(…)`.
  - A server → `serverChip("running", n)`.
- **`serverChip`.**
  - `running` with 0 models → `Running, no models yet`; with 1 → `Running, 1 model`; with N → `Running, N models`.
  - `off` → `Server off`; `notInstalled` → `Not installed`; `outdated` → `Update needed`.
- **`makeMain`.**
  - **Claude plan:** signed in and enabled → `set {claudeCode, claudeModel}`; otherwise `unavailable "Connect your Claude plan first."`.
  - **OpenAI plan:** `unavailable "Coming with the new chat."`.
  - **Key, no key saved:** `unavailable "Add a key on the Keys tab first."`.
  - **Key, saved but no model:** `cloudModel[p]` empty → `unavailable "Pick a model for it in the chat first."`.
  - **Key, saved with a model:** `set {p, model}`.
  - **Server without models:** `unavailable "Start the server and load a model first."`.
  - **Server with one model:** `set` that model.
  - **Server with several models:** `menu`, with the remembered model (`memory[id]`) first when it is one of them, and the rest in order.
- **`helpLine`.** `null` for a key row with no key; otherwise `line`.
- **`reasonLine`.** `null` for a key row with no key, and `null` unless the choice is `unavailable`. It is also `null` when the reason equals the chip plus `"."`. Otherwise it is the reason.
- **`isMain`.** `"auto"` → false.
  - Claude plan ↔ provider `claudeCode`.
  - Key `p` ↔ provider `p`.
  - Server `id` ↔ provider `id`, when `id` is none of `claudeCode`, `anthropic`, `google`, `openai`.
  - The OpenAI plan is never main.
- **`getLink`.** `ollama` → `https://ollama.com/download`; `lmstudio` → `https://lmstudio.ai`; `jan` → `https://jan.ai`; `llamacpp` → `https://github.com/ggml-org/llama.cpp`; anything else → `null`.
- **`AiCache`** is today's `aiSection` logic, moved: `loadCloud`, `refresh`, `refreshOnOpen`, and `MODEL_LIST_MAX_AGE_MS = 10 * 60 * 1000`.
  - `refreshOnOpen` does three steps: `claudeStatus`, then `aiDiscover`, then `loadCloud` for each provider whose key is present and whose list is missing or older than 10 minutes.
  - One refresh runs at a time, and none starts within 1000 ms of the last one's end.
- **`controls.json`'s Windows column.** The Mac decoder (`JSONDecoder`) ignores unknown keys, so every existing field stays byte for byte.
  - Each control gains `"winHomes": [{page, tab|null, card}]` (an empty array means "not on Windows/Linux") and `"win": [{key, store}]`.
  - The stores are:
    - `settings`: a dotted path in `settings.json`;
    - `credential`: the OS credential store;
    - `file`: a file Settings writes outside preferences;
    - `link`: `link.json`;
    - `local`: the Settings window's `localStorage`.
  - At top level, add `"winPages"` (the six pages with this platform's tabs; general has `[]`) and `"winOnly"` (controls that exist only here).
  - Append to `note`: ` The Windows/Linux columns (winHomes, win, winOnly, winPages) are read by windows/scripts/settings-tests/map.test.mjs; the Mac ignores them.`

  The values (homes as `page/tab/card`; `–` means no tab):

| id | winHomes | win |
|---|---|---|
| `sound.enabled` | general/–/Sound | settings `soundEnabled` |
| `sound.volume` | general/–/Sound | settings `soundVolume` |
| `island.openOnHover` | general/–/Island | settings `openOnHover` |
| `island.hoverGlow` | general/–/Island | settings `hoverGlow` |
| `island.tuckAway` | general/–/Island | settings `tuckAway` |
| `island.closeAfter` | general/–/Island | settings `autoCloseInterval` |
| `startup.launch` | general/–/Startup | settings `autostart` |
| `pills.main` | (none) | (none) |
| `pills.slots` | general/–/On the island | (none) |
| `pills.switches` | agents/–/Where you code; services/–/Resend, n8n, Vercel, GitHub, Stripe, Cal.com, Notion | settings `activeIntegrations` |
| `hooks.claude` | agents/–/Claude Code hooks | file `~/.claude/settings.json`, settings `hooksInstalled` |
| `hooks.gemini` | agents/–/Gemini CLI hooks | file `~/.gemini/settings.json` |
| `hooks.antigravity` | agents/–/Antigravity hooks | file `~/.gemini/config/hooks.json` |
| `hooks.codex`, `plan.usage`, `ai.apple`, `service.music`, `shortcuts.global`, `shortcuts.island` | (none) | (none) |
| `ai.claudePlan` | chat/yourai/Choose your AI | settings `ai.claudeCodeEnabled`, `ai.claudeCodeModel` |
| `ai.openAIPlan` | chat/yourai/Choose your AI | (none) |
| `ai.routing` | chat/yourai/Which one answers; chat/yourai/Choose your AI | settings `ai.chat`, `ai.files`, `ai.preferredCloud`, `ai.cloudModels` |
| `ai.key.anthropic` | chat/keys/Anthropic | credential `anthropic-api-key` |
| `ai.key.google` | chat/keys/Google AI | credential `google-api-key` |
| `ai.key.openai` | chat/keys/OpenAI | credential `openai-api-key` |
| `ai.local` | chat/localmodels/Local models | settings `ai.customServer`, `ai.localModels`, `ai.lastUsedLocal`; credential `custom-server-key.default` |
| `service.resend` | services/–/Resend | credential `resend-api-key` |
| `service.n8n` | services/–/n8n | credential `n8n-url`, `n8n-api-key` |
| `service.vercel` / `github` / `stripe` / `calcom` / `notion` | services/–/Vercel, GitHub, Stripe, Cal.com, Notion (one each) | credential `vercel-token`, `github-token`, `stripe-api-key`, `calcom-api-key`, `notion-api-key` (one each) |
| `cat.main` | cat/look/Main cat | settings `cat.character` |
| `cat.look` | cat/look/Look | settings `cat.collar`, `cat.cats.<id>.collar`, `cat.furLines` |
| `cat.desktop` | cat/look/Desktop | settings `cat.desktop.on`, `cat.desktop.size`, `cat.desktop.spots` |
| `cat.wardrobe` | cat/outfits/Wardrobe | settings `cat.outfit` |
| `cat.personality` | cat/personality/Personality | settings `cat.cats.<id>.personality` |
| `cat.motion` | cat/personality/Motion | settings `cat.motionStyle`, `cat.cats.<id>.motion` |
| `cat.everyCat` | cat/personality/Every cat | (none) |
| `cat.display` | cat/agentcats/Display; cat/agentcats/Your two cats; cat/agentcats/Cats for your agents | settings `cat.displayMode`, `cat.pair`, `cat.agentCats` |
| `sidekick.master` | chat/sidekick/Notes | settings `sidekick.on` |
| `sidekick.kinds` | chat/sidekick/Notes; chat/sidekick/Muted notes | settings `sidekick.dismissals` |
| `sidekick.example` | chat/sidekick/Notes | (none) |
| `sidekick.words` | chat/sidekick/Where its words come from | settings `sidekick.local` |
| `sidekick.quiet` | chat/sidekick/Quiet times | (none) |
| `sidekick.today` | chat/sidekick/Today so far | (none) |
| `devices.thisMac` | devices/–/This computer | link `visible`, link `deviceName` |
| `devices.machines` | devices/–/Machines | credential `link.peer.<id>`, `link.peers`, `link.static-key`, `link.device-id` |
| `devices.received` | devices/–/Received files | (none) |
| `settings.selection` | general/–/(the shell) | local `settingsSection`, local `settingsTab.<page>` |

  - **`winOnly`** holds `{ "id": "island.screen", "was": "General: Island lives on (Windows and Linux)", "winHomes": [general/–/Island], "win": [settings `screen`] }`.
  - **[focus]** If focus awareness is merged first, also add `island.focusAware` (home general/–/Island, settings `focusAware`).
  - The agent switches add no control: their values live in `activeIntegrations` under `pills.switches`.

- [ ] **Step 1: Write the failing AI tests** `airows.test.mjs`. The base input is `I = { claudeState: "signedIn", claudeEnabled: true, claudeModel: "sonnet", keys: ["anthropic"], cloudModel: { anthropic: "claude-sonnet-5-5", openai: "gpt-6.1-sol" }, servers: [{ id: "ollama", name: "Ollama", network: false, models: ["qwen3.5:2b", "llama4"] }, { id: "custom", name: "Studio PC", network: true, models: ["big"] }, { id: "lmstudio", name: "LM Studio", network: false, models: [] }], memory: { ollama: "llama4" } }`. The cases:
  ```js
  assert.deepEqual(rows(I).map(rowKey), ["claudePlan", "openAIPlan", "key:anthropic", "key:google", "key:openai", "server:ollama", "server:custom"]);
  assert.ok(!rows(I).map((r) => title(r, I)).some((t) => /Google plan|ChatGPT/.test(t)));
  assert.deepEqual([title({ kind: "claudePlan" }, I), title({ kind: "openAIPlan" }, I), title({ kind: "key", provider: "google" }, I)], ["Use my Claude plan", "Use my OpenAI plan", "Google AI API key"]);
  assert.equal(line({ kind: "openAIPlan" }, I), PLAN_LINE);
  assert.deepEqual([line({ kind: "server", id: "custom" }, I), line({ kind: "server", id: "ollama" }, I)], ["A model server on your network.", "A model server on this computer."]);
  assert.deepEqual(rows(I).slice(0, 6).map((r) => chip(r, I)), ["Ready", "Coming with the new chat", "Ready", "No key yet", "No key yet", "Running, 2 models"]);
  assert.equal(chip({ kind: "claudePlan" }, { ...I, claudeEnabled: false }), "Off");
  for (const [st, word] of [["signedOut", "Not signed in"], ["notInstalled", "Not installed"], ["tooOld", "Needs update"], ["unknown", "Not ready"], [null, "Not ready"]]) assert.equal(chip({ kind: "claudePlan" }, { ...I, claudeState: st }), word);
  assert.deepEqual([serverChip("running", 0), serverChip("running", 1), serverChip("off", 0), serverChip("notInstalled", 0), serverChip("outdated", 0)], ["Running, no models yet", "Running, 1 model", "Server off", "Not installed", "Update needed"]);
  assert.deepEqual(makeMain({ kind: "claudePlan" }, I), { kind: "set", choice: { provider: "claudeCode", model: "sonnet" } });
  assert.deepEqual(makeMain({ kind: "claudePlan" }, { ...I, claudeEnabled: false }), { kind: "unavailable", reason: "Connect your Claude plan first." });
  assert.deepEqual(makeMain({ kind: "openAIPlan" }, I), { kind: "unavailable", reason: "Coming with the new chat." });
  assert.deepEqual(makeMain({ kind: "key", provider: "anthropic" }, I), { kind: "set", choice: { provider: "anthropic", model: "claude-sonnet-5-5" } });
  assert.deepEqual(makeMain({ kind: "key", provider: "openai" }, I), { kind: "unavailable", reason: "Add a key on the Keys tab first." });
  assert.deepEqual(makeMain({ kind: "key", provider: "google" }, { ...I, keys: ["google"] }), { kind: "unavailable", reason: "Pick a model for it in the chat first." });
  assert.deepEqual(makeMain({ kind: "server", id: "ollama" }, I), { kind: "menu", choices: [{ provider: "ollama", model: "llama4" }, { provider: "ollama", model: "qwen3.5:2b" }] });
  assert.deepEqual(makeMain({ kind: "server", id: "custom" }, I), { kind: "set", choice: { provider: "custom", model: "big" } });
  assert.deepEqual(makeMain({ kind: "server", id: "lmstudio" }, I), { kind: "unavailable", reason: "Start the server and load a model first." });
  assert.equal(helpLine({ kind: "key", provider: "openai" }, I), null);
  assert.equal(reasonLine({ kind: "openAIPlan" }, I), null);
  assert.equal(reasonLine({ kind: "claudePlan" }, { ...I, claudeEnabled: false }), "Connect your Claude plan first.");
  assert.ok(rows(I).every((r) => !isMain(r, "auto")));
  assert.deepEqual(rows(I).filter((r) => isMain(r, { provider: "ollama", model: "qwen3.5:2b" })).map(rowKey), ["server:ollama"]);
  assert.deepEqual(rows(I).filter((r) => isMain(r, { provider: "anthropic", model: "claude-opus-5-5" })).map(rowKey), ["key:anthropic"]);
  assert.deepEqual(rows(I).filter((r) => isMain(r, { provider: "claudeCode", model: "opus" })).map(rowKey), ["claudePlan"]);
  assert.deepEqual([getLink("ollama"), getLink("llamacpp"), getLink("anthropic")], ["https://ollama.com/download", "https://github.com/ggml-org/llama.cpp", null]);
  ```
- [ ] **Step 2: Write the failing cache test** `aicache.test.mjs`. It uses a fake backend that counts its calls, a fake clock, and providers `[{ id: "anthropic", key: "anthropic-api-key" }, { id: "openai", key: "openai-api-key" }]` with only the Anthropic key present. The cases:
  - Two calls started together: the second returns `false`, and `aiDiscover` ran once.
  - A call 500 ms after the end returns `false`; a call 1001 ms after the end runs.
  - Only Anthropic's list is loaded.
  - A list loaded at `t` is not reloaded at `t + 9 min`, but is at `t + 10 min + 1 ms`.
  - A failing `aiListModels` makes `loadCloud` return `false` and leaves the list undefined.
  - `forget` removes the list and `works`.
  - `setServers` returns `false` for a JSON-equal list and `true` for a different one.
- [ ] **Step 3: Write the failing map test** `map.test.mjs`. It reads `new URL("../../../tests/fixtures/settings/controls.json", import.meta.url)` and the sources. The sections:
  1. **Shape.** Every control has `winHomes` and `win` arrays. Ids are unique across `controls` and `winOnly`.
  2. **Homes.** Every `winHomes` page is in `PAGES`. Its tab is `null` when `tabs(page, { companion: true })` is empty, and otherwise one of those tabs.
  3. **Pages.** `winPages` equals `PAGES.map((p) => ({ page: p, title: pageTitle(p), tabs: tabs(p) }))`.
  4. **Frozen keys.** The test holds a frozen list of every `settings`, `credential`, `file` and `link` key of the table above, plus `screen` (and **[focus]** `focusAware`): 35 settings keys plus `screen`, 16 credential keys, 3 file keys and 2 link keys.
     - Each frozen key sits under exactly one control (`controls` plus `winOnly`), with the same store.
     - Every key in a `win` column is either frozen or `local`.
  5. **Source scans**, so a key the hand list misses still fails (the Mac's Task 3 lesson):
     - **(a) `Settings` fields.** Every field of `export interface Settings {…}` in `windows/src/core/state.ts` is covered. A plain field must be a `settings` key.
       - `ai` must cover every field of `export interface AiSettings {…}` as `ai.<field>`.
       - `cat` must cover `cat.character`, `cat.motionStyle`, `cat.collar`, `cat.furLines`, `cat.cats.`, `cat.displayMode`, `cat.pair`, `cat.agentCats`, `cat.desktop.` and `cat.outfit`.
       - `sidekick` must cover `on`, `local` and `dismissals`.
       - **[projects]** `projectCats` is listed as P-tauri's, with its reason, until that plan maps it.
     - **(b) Credential keys.** Every credential name used in Settings must be a `credential` key. That means every string literal in `secretSet(`, `secretPresent(`, `secretClear(` or a `key: "…"` property in `windows/src/settings/*.ts`; the three `key:` values of `CLOUD_PROVIDERS`; and `CUSTOM_KEY`'s value.
     - **(c) Link keys.** `windows/src-tauri/src/link/settings.rs` mentions `visible` and `deviceName`.
  6. **The Mac's fields keep their shape.** `mac` stays `{key, store}` and `homes` stays `{page, tab, card}`.
- [ ] **Step 4: Extend `drift.test.mjs`** with checks against `SettingsAI.swift`:
  - `planLine`, `coming` and the three key titles are equal.
  - The two server lines are equal after replacing `this Mac` with `this computer`.
  - The five `makeMain` reasons, the five server-chip words and the four Get URLs all appear as literals.
- [ ] **Step 5: Run** `npm run check:settings`. The new tests fail.
- [ ] **Step 6: Implement** `airows.ts` and `aicache.ts`, then edit `controls.json`.
  - In each control, put `winHomes` and `win` right after `mac`.
  - Put `winPages` after `pages`, and `winOnly` after `controls`.
  - Keep the 2-space indent and every existing line.
- [ ] **Step 7: Verify.**
  - `npm run check:settings` passes.
  - From the repo root, `bash scripts/test-settings-map.sh` and `bash scripts/test-settings-wiring.sh` pass.
  - `git diff --stat -- tests/fixtures/settings/controls.json` shows insertions only.
- [ ] **Step 8: Commit** the seven files: `feat(settings/tauri): the AI rows, the AI cache and the Windows/Linux column of the control map`.

---

### Task 3: Rust and bridge: window size, open at a place, `settings-hidden`

**Files:**
- Modify: `windows/src-tauri/src/lib.rs`, `windows/src/core/bridge.ts`, `windows/src/views/views.ts`, `windows/src/views/chat.ts`, `windows/src/views/shelfdevice.ts`, `windows/src/island/island.ts`
- Create: `windows/scripts/settings-tests/window.test.mjs`

**Interfaces:**
- **Produces:**
  - Rust: `fn settings_place(raw: Option<String>) -> Option<String>`.
  - The command `open_settings_window(app: AppHandle, place: Option<String>)`.
  - Two events to the window labelled `settings`: `settings-place` (a `String`) and `settings-hidden` (`()`).
  - TS: `Bridge.openSettingsWindow(place?: string)`, and `openSettingsWindow(place?: string): void` in `views.ts`'s `Actions`.

The rules:
- **Window.** `.inner_size(560.0, 680.0)` becomes `.inner_size(720.0, 560.0)`, and `.min_inner_size(460.0, 480.0)` becomes `.min_inner_size(415.0, 420.0)`.
- **`settings_place`.** It keeps the value only when it matches `^[a-z]+(/[a-z]+)?$` and is at most 32 bytes; anything else is `None`. Its doc line: "The Settings place the island asks for (`devices`, `chat/keys`): lower-case letters and at most one slash; anything else is dropped, and the window opens where it was. The page reads it through `migrate`."
- **`open_settings_window`.** It calls `show_settings_window(&app)`. When `settings_place(place)` is `Some(p)`, it then runs `let _ = app.emit_to("settings", "settings-place", p);`. The tray keeps calling `show_settings_window` with no place.
- **`settings-hidden`.** In the `CloseRequested` closure, right after `link_cmd::settings_hidden(&app);`, add `let _ = app.emit_to("settings", "settings-hidden", ());` with this comment: "The page drops what was typed and not saved (the restyle spec's rule 11): the window is only hidden, so it never reloads."
- **Bridge.** `openSettingsWindow: (place?: string) => call<void>("open_settings_window", { place: place ?? null }),`.
- **Callers:**
  - `shelfdevice.ts` "Open Devices" → `"devices"`.
  - `chat.ts:630` "Add a cloud key" → `"chat/keys"`.
  - `chat.ts:633` "Connect Claude" → `"chat/yourai"`. Change its comment to "The first run: Settings → AI and chat opens on Your AI."
  - `chat.ts:140`, the `openSettings` action → `"chat/keys"`. Rust gives that action only with an auth error, "Your Anthropic key was rejected." (`ai/errors.rs`).
  - `views.ts:178`, the integration hooks' `openSettings` → `"services"`.
  - `views.ts`'s `Actions` → `openSettingsWindow(place?: string): void;`.
  - `island.ts:313` → `openSettingsWindow: (place?: string) => void Bridge.openSettingsWindow(place),`.
  - `views.ts:533` stays without a place.

- [ ] **Step 1: Write the failing Rust tests** in `lib.rs`. Use its test module, or create `#[cfg(test)] mod settings_place_tests`.
  - Kept: `Some("devices")`, `Some("chat/keys")`, `Some("cat/agentcats")`.
  - `None`: `Some("Chat")`, `Some("")`, `Some("chat/")`, `Some("/keys")`, `Some("chat/keys/x")`, `Some("../x")`, `Some("chat keys")`, a 33-byte `"a".repeat(33)`, and `None`.

  Run `windows/scripts/cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/settings-tauri -- settings_place`. It fails to compile.
- [ ] **Step 2: Write the failing pins** `window.test.mjs`.
  - `lib.rs` contains the new size pair and neither old pair.
  - It contains `fn open_settings_window(app: AppHandle, place: Option<String>)` and `app.emit_to("settings", "settings-place", p)`.
  - `app.emit_to("settings", "settings-hidden", ())` comes after `link_cmd::settings_hidden(&app);`.
  - The Rust numbers equal `DEFAULT_W`/`DEFAULT_H` and `MIN_W`/`MIN_H`.
  - The caller lines are as listed above.

  Run them; they fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.**
  - `cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/settings-tauri` passes; run it all, not only the filter.
  - `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-settings-tauri` passes.
  - `tsc`, `npm run check:settings`, `npm run check:cat` and `npm run check:link` pass.
- [ ] **Step 5: Commit** the seven files: `feat(settings/tauri): the window's Mac sizes, opening at a page, and the hidden event`.

---

### Task 4: Agent switches on the island (the Mac's hidden-pill rule)

The owner's answer 7. On the Mac, an agent pill that is on (`activeIntegrations` holds it) is loaded idle at start, takes a slot, and stays when its session ends: `removeTask` resets it to idle. A pill that is off is transient: `HookServer.upsertWorkspaceTask` creates it when the agent sends an event, and it is removed when the session ends. Windows already does the transient part (`State.upsertExternalAgent`, then `State.removeTask` in `island/hooks.ts` after `Stop` or `SessionEnd`). This task adds the on part in `State` alone. The hook path, the relay and `island/hooks.ts` do not change, so no request ever waits on the switch.

**Files:**
- Modify: `windows/src/core/state.ts`
- Create: `windows/scripts/cat-tests/agent-switch.test.mjs`

**Interfaces:**
- **Consumes:** `agentPillName` and `agentColor` from `core/pills.ts`, a file with no imports of its own. `state.ts` does not import it today, so add `import { agentColor, agentPillName } from "./pills.ts";`. The import is cycle-free.
- **Produces:**
  - `export const AGENT_SWITCHES: readonly { id: string; tag: string }[] = [{ id: "agent_gemini", tag: "gemini" }, { id: "agent_antigravity", tag: "antigravity" }];`
  - `State.loadIntegrationTasks()`, `State.removeTask(id)` and `State.toggleIntegration(id)`, with the rules below.

The rules:
- **`loadIntegrationTasks`.** Keep today's loop over `INTEGRATION_AGENTS`, then loop over `AGENT_SWITCHES`:
  - **On and not loaded:** push `{ id, name: agentPillName(tag), color: agentColor(tag), state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false }`. This is the shape `upsertExternalAgent` builds, so a pill looks the same whether it is persistent or transient. Then call `this.giveCoats([id])`.
  - **Off and loaded, with state `"idle"`:** remove the pill (and its kittens). Plan call: a busy pill (working, asking or finished) is never removed here; its session's own `Stop` or `SessionEnd` removes it as today. This function runs on every `settings-changed` (`main.ts:131`). So an idle pill of an agent that is off goes at the next `settings-changed` and comes back with that agent's next event, which is the Mac's hidden-pill rule.
  - Then today's sort and focus.
- **`removeTask(id)`.** When `id` is in `AGENT_SWITCHES` and in `settings.activeIntegrations`, do not remove the pill. Reset it the way the Mac's `removeTask` does for an active declared pill: `state = "idle"`, `steps = []`, `stepIndex = 0`, `pillBadge = null`, `name = agentPillName(tag)`, then `notify()`. Kittens and focus stay, as on the Mac. Every other id keeps today's body.
- **`toggleIntegration(id)`.** Unchanged. It already caps at 4 over the whole list (agents included) and calls `loadIntegrationTasks`.
- **The default.** `DEFAULT_SETTINGS.activeIntegrations` is unchanged and holds no agent id, so a new or existing user keeps today's behaviour.

- [ ] **Step 1: Write the failing test** `agent-switch.test.mjs`. It imports `State` and `AGENT_SWITCHES` the way `state-cast.test.mjs` does, using a `fresh(active)` helper that resets `State.settings.activeIntegrations`, `tasks`, `focusId` and `persistSettings` and calls `loadIntegrationTasks()`. The cases:
  - With `["integration_stripe"]`, no `agent_*` pill is loaded.
  - After `upsertExternalAgent("agent_gemini", "gemini", "#8AB4F8")` then `removeTask("agent_gemini")`, the pill is gone. This is today's transient rule.
  - With `["agent_gemini"]`, an `agent_gemini` pill is loaded idle with `name === agentPillName("gemini")` and `color === agentColor("gemini")`.
  - Set its state to `"working"` with one step and call `removeTask("agent_gemini")`: the pill is still there, idle, with `steps.length === 0` and `pillBadge === null`.
  - Turn it off (`activeIntegrations = []`) while it is `"working"` and call `loadIntegrationTasks()`: the pill stays. Set it `"idle"` and call `loadIntegrationTasks()` again: it is gone.
  - `toggleIntegration("agent_antigravity")` with four ids already active changes nothing. With three, it adds the id and loads the pill.
  - `toggleIntegration("integration_claude")` changes nothing.
  - Source pins:
    - `island/hooks.ts` still contains `State.removeTask(agentId);` twice and no `activeIntegrations`.
    - `windows/hook/src/agents.rs` has no `activeIntegrations` and no `settings`.
- [ ] **Step 2: Run** `npm run check:cat`. The new test fails.
- [ ] **Step 3: Implement** in `state.ts`.
- [ ] **Step 4: Verify.** `npm run check:cat` passes, including `state-cast`, `sleep`, `pill-labels` and `subagents`, and so do `tsc` and `npm run check:sidekick`.
- [ ] **Step 5: Commit** the two files: `feat(island/tauri): an agent switched on stays on the island (the Mac's rule); the hook path is unchanged`.

---

### Task 5: The kit, the shell, the backend, the sample frame, the shot harness, `?dev` and the render script

**Agent:** `nm-implementer` (Haiku 5.5, high), by the main session's ruling. Move it to `nm-implementer-deep` (Sonnet 5.5) only if Haiku fails it twice (trigger 2), and write that in the ledger. Read the spec's "The window", "The layout kit" and "Page rules" first.

**Files:**
- Create: `windows/src/settings/kit.ts`, `shell.ts`, `backend.ts`, `ctx.ts`, `app.ts`, `icons.ts`, `devseed.ts`, `devpanel.ts`, `windows/scripts/render-settings.sh`, `windows/scripts/settings-tests/kit.test.mjs`, `privacy.test.mjs`
- Modify: `windows/src/settings/settings.css` (append), `windows/src/settings/main.ts` (the dev routes only), `windows/src/cat/dev.ts` (one import, one mount line)

**Interfaces:**
- **Consumes:** Task 1's `route.ts`, `layout.ts`, `status.ts` and `drafts.ts`; `h`, `clear` and `svg` from `../views/dom`; `ICONS.gearFill` and `ICONS.bubble` from `../views/icons`; `LinkBackend` from `../link/model.ts`; `platformOf` and `Platform` from `./devices`; `devBackend(name)` from `../link/devseed.ts` (it exists; seeds `on`, `off`, `empty`, `problem`, `note`).
- **Produces** (later tasks use these exact signatures):
```ts
// backend.ts — the only settings file besides main.ts that imports Bridge.
export interface SettingsBackend {
  boot(): Promise<BootInfo | undefined>;
  save(settings: Settings): Promise<void>;
  hooksStatus(): Promise<HookStatus | undefined>;
  hooksPreview(install: boolean): Promise<HookPreview>;
  hooksApply(install: boolean, fingerprint: string): Promise<string>;
  agentHooksStatus(agent: HookAgent): Promise<HookStatus | undefined>;
  agentHooksPreview(agent: HookAgent, install: boolean): Promise<HookPreview>;
  agentHooksApply(agent: HookAgent, install: boolean, fingerprint: string): Promise<string>;
  secretPresent(key: string): Promise<boolean | undefined>;
  secretSet(key: string, value: string): Promise<void>;       // throws on a refusal
  secretClear(key: string): Promise<void>;                    // throws on a refusal
  aiListModels(provider: string): Promise<ModelInfo[]>;
  aiDiscover(): Promise<AiServer[] | undefined>;
  aiResolve(feature: Feature): Promise<Resolution | undefined>;
  claudeStatus(): Promise<ClaudeStatus | undefined>;
  claudeSignIn(): Promise<boolean | undefined>;
  aiLocalModel(): Promise<string | null | undefined>;
  openUrl(url: string): void;
  copyText(text: string): void;
  link: LinkBackend;
  on<T>(event: "settings-changed" | "ai-servers-changed" | "settings-place" | "settings-hidden", handler: (payload: T) => void): void;
}
export function bridgeSettingsBackend(link: LinkBackend): SettingsBackend;
// ctx.ts — Task 9 adds `ai: AiCache`.
export interface SettingsCtx {
  backend: SettingsBackend; settings(): Settings; save(next: Settings): Promise<void>;
  home: string; drafts: DraftBook; open(place: Place): void; platform: Platform; desktopNote: string | null;
}
export interface PageView { el: HTMLElement; sync?(): void; dispose?(): void }
// kit.ts
export function card(title: string, opts: { summary?: string | null; footer?: string; dot?: string } | null, ...children: Node[]): HTMLElement;
export function row(label: string, control: Node | Node[], help?: string): HTMLElement;
export interface SwitchRow { el: HTMLElement; set(on: boolean, o?: { chip?: string | null; disabled?: boolean }): void }
export function switchRow(label: string, o: { on: boolean; onChange: (v: boolean) => void; help?: string; chip?: string | null; disabled?: boolean }): SwitchRow;
export function keyField(o: { id: string; drafts: DraftBook; placeholder: string; secure?: boolean; onInput: () => void }): HTMLInputElement;
export function chip(text: string): HTMLElement;
export function wrapRow(...children: Node[]): HTMLElement;
export function pathDisclosure(lines: readonly { label: string; path: string; shown: string }[], copy: (text: string) => void): HTMLElement;   // shows `shown`, copies `path`
export function help(text: string, warn?: boolean): HTMLElement;
export function notice(kind: "ok" | "err" | "warn", text: string): HTMLElement;
export function button(text: string, onclick: () => void, kind?: "primary" | "danger"): HTMLButtonElement;
export function select(options: readonly (readonly [string, string])[], value: string, onChange: (v: string) => void): HTMLSelectElement;
export function setValue(el: HTMLInputElement | HTMLSelectElement, value: string): void;   // skipped when el is document.activeElement
export function details(summary: string, ...children: Node[]): HTMLDetailsElement;
export function renderDiff(text: string): HTMLElement;
export function tabBar(list: readonly Tab[], selected: Tab, onSelect: (t: Tab) => void): { el: HTMLElement; fit(): void };
// shell.ts
export function buildShell(o: {
  version: string; build: (place: Place) => PageView;
  storage: Pick<Storage, "getItem" | "setItem"> | null; initial?: Place | null;
}): { el: HTMLElement; select(place: Place): void; sync(): void; current(): Place };
// app.ts
export function startSettingsApp(root: HTMLElement, backend: SettingsBackend, o: { initial?: Place | null; storage: Pick<Storage, "getItem" | "setItem"> | null }): Promise<void>;
// devseed.ts (dev server only)
export function devSettingsBackend(sample: string, stress: boolean, link: LinkBackend): SettingsBackend;
// devpanel.ts (dev server only)
export function mountSettingsDev(root: HTMLElement, before: Node | null): void;
export function mountShotFrame(root: HTMLElement, width: number, height: number, src: string): void;
```

What each piece does. The spec's kit, with `layout.ts`'s numbers:
- **`buildShell`.**
  - **Layout.** A grid `.st-shell` with the sidebar and `.st-detail`.
  - **Sidebar.** A header ("NotchMeow" and the version; hidden in icons mode), then one `<button class="st-nav">` per page.
    - Each button has `aria-label` and `title` set to the page title, and the selected one gets `aria-current="page"`.
    - Each shows a 22 px rounded tile in `pageColor` holding its `icons.ts` icon, then the title (hidden in icons mode).
  - **Detail.** The page title (an `h1`, 17 px semibold), then the `tabBar` when `tabs(page)` is not empty, then a scroll area holding `.st-column`.
  - **The first place** is `o.initial`. Without one, it is `migrate(storage SECTION_KEY)`, with the tab from `tabFor(page, storage tabKey(page))`.
  - **`select(place)`.**
    1. Calls `dispose()` on the current view.
    2. Builds the next view with `o.build` and mounts it.
    3. Writes both keys.

    Every read and write of `storage` is wrapped in `try`/`catch`.
  - **`sync()`** calls the current view's `sync`.
  - **One `window` `resize` listener** calls the tab bar's `fit()`, through one `requestAnimationFrame` per burst.
- **`tabBar`.** A row `.st-tabs` of text buttons, one per tab.
  - Each button has `white-space: nowrap`. The selected one has `aria-selected="true"` and a 2 px `--ink` underline. The row is 28 px tall.
  - A hidden `select` lists the same tabs. `fit()` shows the select instead of the buttons when `row.scrollWidth > row.clientWidth`.
  - Never a segmented control, never shortened labels, never a scroll (builder call 8).
- **`card`.** A `<section class="st-card">`.
  - Its head row holds the dot (when `dot` is set), the title (13 px semibold), and `chip(summary)` on the right. The chip wraps under the title when there is no room.
  - Then the children, then `help(footer)`.
- **`row`.** `.st-row`, holding a `.st-label` and a `.st-control`.
  - The label wraps between words and has `min-width: min-content`.
  - With `flex-wrap: wrap`, the control goes under the label when the two do not fit on one line.
  - Then `help`.
- **`switchRow`.** A `row` whose control is the window's `.switch`.
  - Write `aria-pressed` with `setAttribute("aria-pressed", String(on))`.
  - The chip sits before the switch, and a `<label>` toggles it.
  - `disabled` disables both. `set()` updates in place, so focus stays.
- **`keyField`.** An input, `type="password"` unless `secure === false`, with `autocomplete="off"`, `spellcheck="false"` and `max-width: 420px`.
  - It shows `drafts.text(id)`.
  - On input it calls `drafts.edit`, then `onInput()`.
- **`setValue`.** It writes `el.value` only when `el !== document.activeElement`. Every page's `sync` writes inputs, selects and ranges only through it, so a slider mid-drag or a field being typed in is never reset.
- **`chip`.** `span.st-chip.st-<tone>`: a 7 px dot (ok `--green`, warn `--amber`, error `--red`, neutral `--dim`) and 11.5 px text with `white-space: nowrap`.
- **`wrapRow`.** `.st-wrap`: `display: flex; flex-wrap: wrap; gap: 6px 8px`.
- **`pathDisclosure`.** A "Show path" / "Hide path" button, closed at first.
  - Each line shows its label and the path in `.st-path`: mono, selectable, `overflow-wrap: anywhere`.
  - A Copy button copies the **real** path, never the `~` display text. Each line is `{ label, path, shown }`: `shown` is drawn and `path` is copied.
  - Callers pass display paths. Plan call: there is no "Show in folder", because no command reveals an arbitrary path.
- **`help`.** `div.hint`, plus the class `warn` when `warn` is true.
- **CSS**, a block appended as `/* Settings restyle (the kit and the shell) */`:
  - `body.settings-window.st-app #settings-root { max-width: none; padding: 0; }`.
  - `.st-shell { display: grid; grid-template-columns: 200px 1fr; height: 100vh; }`, and `.st-detail` with 20 px side padding.
  - `.st-column { max-width: 640px; margin: 0 auto; width: 100%; display: flex; flex-direction: column; gap: 18px; }`.
  - `@media (max-width: 599.98px) { .st-shell { grid-template-columns: 56px 1fr; } … }`: 16 px padding, the labels and header hidden, the tiles centred.
  - `.st-card input[type="number"] { width: 64px; }` and `.st-control select { width: 180px; max-width: 100%; }`. Plan call: a stacked pop-up keeps its 180 px, as the Mac's ledger ruled.
  - `button, .st-chip, .st-tabs button { white-space: nowrap; }`.
  - `.st-wrapbtn { white-space: normal; overflow-wrap: normal; max-width: 100%; text-align: left; }`. It is used only for a button whose label holds a user-given name ("Forget <name>?", Task 8). Such a button wraps between words and never makes the page scroll sideways. Plan call: the name stays in the label, as today.
  - Colours here use only the existing tokens. Task 6 tokenizes the rest.
  - **Where the block goes.** Insert it **before** the line `/* Wardrobe (sub-project I): the tiles reuse .cat-cell; these are new class names only. */` (`settings.css:463`), never after it. `cat-tests/wardrobe-ui.test.mjs` (lines 68–76) slices `settings.css` from that comment to the end of the file and requires every selector there to be `.wardrobe-*`. Placed before the comment, the block leaves that test unchanged. Task 10's narrow-width rules and Task 6's light blocks go before that comment too. Kit pin: in `settings.css`, `indexOf("/* Settings restyle")` < `indexOf("/* Wardrobe (sub-project I)")`, and every `:root` block also comes before the Wardrobe comment.
- **`app.ts` `startSettingsApp`.**
  1. **The place listener comes first.** Before any `await`, register `backend.on("settings-place", p => pending = migrate(p); shell?.select(pending))`. A place that arrives during boot is applied right after the shell is built.
  2. **Boot.** `backend.boot()`.
  3. **Key presence.** Load the presence of the eleven keys into one `DraftBook`: `anthropic-api-key`, `google-api-key`, `openai-api-key`, `stripe-api-key`, `github-token`, `vercel-token`, `n8n-url`, `n8n-api-key`, `resend-api-key`, `notion-api-key`, `calcom-api-key`.
  4. **Context.** Build `SettingsCtx`. Its `desktopNote` is today's GNOME sentence when `boot.desktopPositioned === false`.
  5. **Mount.** Add the class `st-app` to `document.body`, then mount `buildShell(...)`.
  6. **`build`.** One `switch` on the page, and on the tab for `chat` and `cat`. In this task every case returns `{ el: card("Sample", null, help("<page>/<tab>")) }`. Tasks 7 to 10 replace them.
- **`devseed.ts`.** An in-memory `SettingsBackend` for `sample` ∈ `ready | empty | error`; `stress` adds long strings. The home is `C:\Users\sample`.
  - In this task it holds the skeleton and `boot`. Tasks 7 to 10 add their samples, and its header lists them.
  - Fake values only.
- **`main.ts`, the dev routes.** At the start of `main()`; this code is DEV only:
  ```ts
  const params = new URLSearchParams(location.search);
  const shot = import.meta.env.DEV ? params.get("shot") : null;
  if (shot) {
    const { mountShotFrame } = await import("./devpanel");
    params.delete("shot");
    mountShotFrame(root, Number(shot), Number(params.get("h") ?? "2400"), `/settings.html?${params}`);
    return;
  }
  const sample = import.meta.env.DEV ? params.get("sample") : null;
  if (sample) {
    const theme = params.get("theme");
    if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme;
    const { devSettingsBackend } = await import("./devseed");
    const link = (await import("../link/devseed")).devBackend(params.get("linkdev") ?? "on");
    const page = params.get("page");
    await startSettingsApp(root, devSettingsBackend(sample, params.has("stress"), link), { storage: null, initial: page ? migrate(params.get("tab") ? `${page}/${params.get("tab")}` : page) : null });
    return;
  }
  ```
  The rest of `main()` stays exactly as it is.
- **`devpanel.ts`.**
  - **`mountShotFrame(root, width, height, src)`.** It clears `root`, sets `document.body.style.margin = "0"`, and puts one borderless `<iframe>` at (0, 0) with `width` × `height` and `src`. When the frame loads, it writes `<output id="frame-width">${frame.contentWindow!.innerWidth}</output>` after it. Same origin, so the read is allowed.
  - **`mountSettingsDev(root, before)`.** A `<section id="settings-dev">` mounted in `cat/dev.ts` right after `mountLinkDev(root, wrap);`.
    - Controls: a place select, a state select, a Stress checkbox, a Theme select (dark, light) and a height.
    - Three iframes, 415, 720 and 1100 wide, each showing `/settings.html?sample=…&page=…[&tab=…][&stress]&theme=…`.
- **`windows/scripts/render-settings.sh`** draws the owner's checkpoint pictures; it is not in CI. Plan call: the CRITICAL review finding was that headless Chrome clamps its window to at least 500 px. So the script renders each width through the shot harness, asserts the frame's real width, and crops the picture.
  - **Options.**
    - `--out DIR` (default `${TMPDIR:-/tmp}/settings-tauri`).
    - `--state ready|empty|error` (default `ready`), `--stress`, `--page P`, `--tab T`.
    - `--width W` (default 415, 720 and 1100) and `--height H` (default 2400).
    - `--theme dark|light|both` (default `both`).
    - An unknown option prints the usage and exits 2.
  - **Server.** Start `npx --no-install vite --port 1421 --strictPort --host 127.0.0.1` from `windows/` in the background. Wait with at most 60 tries of `curl -s -o /dev/null` 0.5 s apart. A `trap` kills the server's PID.
  - **Per place, theme and width:**
    1. Build the URL `http://127.0.0.1:1421/settings.html?shot=<W>&h=<H>&sample=<state>&page=<p>[&tab=<t>][&stress]&theme=<theme>`.
    2. Run `"$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --disable-extensions --user-data-dir="$PROFILE" --window-size=<max(W,500)>,<H> --virtual-time-budget=5000 --dump-dom "<url>"`. Require it to contain `id="frame-width">W<`. If `frame-width` is missing, retry the run once, because Vite's first run can re-optimise its dependencies and reload the page. If it is still missing, or shows another number, print `the frame is N px wide, not W` (or `no frame width after a retry`) and exit 1.
    3. Run the same command with `--screenshot="<file>"`.
    4. `sips -c <H> <W> --cropOffset 0 0 "<file>"`.
  - **Names and paths.** `CHROME` defaults to `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`. `PROFILE` comes from `mktemp -d` and is trashed at the end. Files are named `<page>[-<tab>]-<W>-<theme>[-stress][-<state>].png`, with the state left out when it is `ready`.
  - **Output.** It prints `wrote <file>` per picture and `drew N pictures` at the end.
- **Pins** (`kit.test.mjs`):
  - `tabBar` contains `scrollWidth > ` and `clientWidth` and a `"select"`, and no `segmented`.
  - `shell.ts` calls `dispose` before `o.build(`, uses `migrate(` and `tabFor(`, wraps `getItem` and `setItem` in `try`, and adds a `resize` listener.
  - `kit.ts` defines `setValue` with `document.activeElement`, and contains `setAttribute("aria-pressed", String(`.
  - `app.ts` registers `"settings-place"` before its first `await`.
  - None of `kit.ts`, `shell.ts` or `app.ts` contains `setInterval`, `setTimeout`, `ResizeObserver` or `MutationObserver`.
  - `settings.css` contains:
    - `@media (max-width: 599.98px)`;
    - `grid-template-columns: 200px 1fr` and `grid-template-columns: 56px 1fr`;
    - `max-width: 640px`, `max-width: 420px`, `width: 64px`, `width: 180px`;
    - `min-width: min-content`, `white-space: nowrap`, and the `.st-wrapbtn` rule.
  - `settings.css` contains no `text-overflow: ellipsis` and no `-webkit-line-clamp`. `word-break: break-all` appears only in `.path`.
  - The CSS numbers equal `layout.ts`'s constants.
  - Only `backend.ts` and `main.ts` contain `Bridge.`.
  - `render-settings.sh` contains `--dump-dom`, `frame-width` and `sips -c`.
- **Privacy** (`privacy.test.mjs`):
  - These files contain no `/\b(ike|lorenz|tazan)\b/i` and no `/raill/i`: `devseed.ts`, `devpanel.ts`, `render-settings.sh` and every `windows/src/settings/*.ts`.
  - `devseed.ts` uses the home `C:\Users\sample`, and contains no `process.env`, `os.`, `navigator.userAgent` or `homedir`.
  - `render-settings.sh` writes nowhere but `--out` and its throwaway profile.

- [ ] **Step 1: Write the pins.** Run them; they fail.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify the code.** `tsc`, `npm run check:settings`, `npm run check:cat`, `npm run check:link` and `bash scripts/check-site.sh` all pass.
- [ ] **Step 4: The pictures.**
  - Run `bash windows/scripts/render-settings.sh --page general --theme dark --out "${TMPDIR:-/tmp}/st5"`, then the same with `--page chat --tab keys`. Every run passes its width check.
  - Open the PNGs and check: at 415, icons only; at 720 and 1100, labels; at 1100, a 640 px column, centred; the four chat tabs as text at 720 and as a menu at 415 if they do not fit; no horizontal scrollbar; each picture exactly W px wide (`sips -g pixelWidth`).
  - Open `npx --no-install vite` → `http://127.0.0.1:1420/?dev` and check that the Settings panel shows three frames. Stop the server by its PID.
- [ ] **Step 5: Commit** the fourteen files: `feat(settings/tauri): the layout kit, the shell, the sample frame and the width-checked pictures`.

---

### Task 6: The light and dark palette, contrast-tested

The owner's answer 6.

**Files:**
- Modify: `windows/src/settings/settings.css`, `windows/settings.html`, `windows/src/settings/devices.ts` (the `DOT` colours)
- Create: `windows/scripts/settings-tests/contrast.test.mjs`

**The rule.** Every colour value in `settings.css` becomes a token on `:root`. The dark value is today's literal, with one exception: `--dim-2` rises from `#6b7079` to `#8d929b`, because today's is 3.67:1 over `--card`, below the floor. The light value mirrors the Mac Settings' light look: the Mac's window `#ECECEC`, white cards, and black label text at the system's alphas, written as solid colours. Light accents are darkened until their text passes. Plan call: these values are computed in this plan's dry run, and all pass.

The cat preview boxes (`background: #000`) and the canvases keep their colours, because they show the island's look.

| Token | Dark (today, except `--dim-2`) | Light |
|---|---|---|
| `--bg` | `#0b0c0e` | `#ececec` |
| `--card` | `#141518` | `#ffffff` |
| `--hairline` | `rgba(255,255,255,0.07)` | `rgba(0,0,0,0.1)` |
| `--ink` | `#f5f6f8` | `#262626` |
| `--dim` | `#9398a1` | `#5c5c5c` |
| `--dim-2` | `#8d929b` | `#666666` |
| `--green` | `#22c55e` | `#116b34` |
| `--red` | `#f4505e` | `#b42318` |
| `--amber` | `#f5a524` | `#8a5200` |
| `--btn` / `--btn-hover` | `rgba(255,255,255,0.09)` / `0.15` | `rgba(0,0,0,0.06)` / `0.1` |
| `--primary-ink` / `--primary-hover` | `#0b0c0e` / `#fff` | `#ffffff` / `#000000` |
| `--danger-bg` / `--danger-ink` | `rgba(244,80,94,0.16)` / `#ff8d97` | `rgba(244,80,94,0.12)` / `#b42318` |
| `--switch-off` / `--knob` / `--track` | `rgba(255,255,255,0.15)` / `#fff` / `rgba(255,255,255,0.2)` | `rgba(0,0,0,0.15)` / `#fff` / `rgba(0,0,0,0.2)` |
| `--field` / `--field-line` / `--option-bg` | `rgba(255,255,255,0.07)` / `rgba(255,255,255,0.28)` / `#1a1c20` | `rgba(0,0,0,0.04)` / `rgba(0,0,0,0.35)` / `#ffffff` |
| `--diff-bg` / `--add-ink` / `--del-ink` | `#08090b` / `#86efac` / `#ff8d97` | `#f5f5f5` / `#116b34` / `#b42318` |
| `--ok-bg` / `--ok-ink` | `rgba(34,197,94,0.12)` / `#86efac` | `rgba(34,197,94,0.12)` / `#116b34` |
| `--err-bg` / `--err-ink` | `rgba(244,80,94,0.14)` / `#ff8d97` | `rgba(244,80,94,0.12)` / `#b42318` |
| `--warn-bg` / `--warn-ink` | `rgba(245,165,36,0.13)` / `#fbc06a` | `rgba(245,165,36,0.16)` / `#8a5200` |
| `--cell-hover` / `--cell-on` / `--cell-on-line` / `--soft` | `rgba(255,255,255,0.09)` / `0.1` / `0.55` / `0.05` | `rgba(0,0,0,0.06)` / `0.06` / `0.45` / `0.04` |

**CSS structure.**
- `:root { color-scheme: dark light; <dark tokens> }`.
- `@media (prefers-color-scheme: light) { :root:not([data-theme="dark"]) { color-scheme: light; <light tokens> } }`.
- `:root[data-theme="light"] { color-scheme: light; <light tokens> }`, which the dev server's `&theme=light` sets.
- `:root[data-theme="dark"] { color-scheme: dark; }`.

The test checks that the two light blocks are identical.
- **`settings.html`.** Delete the inline `style="background: #0b0c0e; color: #f5f6f8"` and add `<meta name="color-scheme" content="dark light">`, so the first paint follows the system. `body.settings-window` already takes `var(--bg)` and `var(--ink)`.
- **`devices.ts`.** In `DOT`, `pairedOffline: "rgba(255,255,255,0.35)"` becomes `"var(--dim-2)"`. The other two dots keep their colours.
- **The island is untouched.** Neither `src/style.css` nor `src/link/link.css` changes. Its one `color: var(--ink)` rule inside Settings follows the tokens.

**`contrast.test.mjs`.** It parses the dark tokens from the first `:root` block and the light tokens from `:root[data-theme="light"]`. It blends any `rgba` over `--card`, then computes the WCAG ratio, the same formula as `SettingsColors.contrast`. In each palette, every pair must be at least 4.5:1:
- `--ink`, `--dim` and `--dim-2` over `--bg`, `--card`, `--diff-bg` and `--option-bg`, and `--dim` and `--dim-2` over `--field` blended over `--card` (placeholders and field text). With the dark `--dim-2` at `#8d929b`, that pair is 4.90:1; at `#878c95` it was 4.54, too thin a margin;
- `--green`, `--red` and `--amber` over `--card`;
- `--add-ink` and `--del-ink` over `--diff-bg`;
- `--ok-ink` over `--ok-bg`, `--err-ink` over `--err-bg`, and `--warn-ink` over `--warn-bg`;
- `--danger-ink` over `--danger-bg`;
- `--primary-ink` over `--ink`, since `--ink` is the primary button's fill;
- `--ink` over `--btn`.

It also checks:
- The light blocks are equal.
- No `#` or `rgb` literal is left in `settings.css` outside the token blocks, except `#000` in the three cat-preview rules.
- `.hint` uses `color: var(--dim)` at `12px`.
- `settings.html` has no inline `background:` and has the `color-scheme` meta.

- [ ] **Step 1: Write the failing test.**
- [ ] **Step 2: Tokenize and add the light blocks.**
- [ ] **Step 3: Verify.**
  - `npm run check:settings` and `npm run check:cat` pass. `settings-ui.test.mjs`'s CSS-block tests ("new class names only") still pass, because colour declarations change but selectors do not.
  - `npm run check:link` passes.
  - Run `render-settings.sh --page general --theme both`. Dark looks like today's window; light has a light grey window, white cards and dark text, with no white-on-white.
- [ ] **Step 4: Commit** the four files: `feat(settings/tauri): a light palette beside the dark one, every text pair at 4.5:1`.

---

### Task 7: Pages: Agents (with Where you code) and Services

**Files:**
- Create: `windows/src/settings/agents.ts`, `windows/src/settings/services.ts`, `windows/scripts/settings-tests/pages.test.mjs`
- Modify: `windows/src/settings/app.ts` (two cases), `windows/src/settings/devseed.ts` (their samples)

**Interfaces:**
- **Consumes:** the kit, `SettingsCtx` and `PageView` (Task 5); `displayPath`, `displayText`, `hookChip`, `pillSwitch` and `serviceChip` (Task 1); `AGENT_SWITCHES` (Task 4); `agentLabel` (`core/pills.ts`).
- **Produces:**
```ts
export function agentsPage(ctx: SettingsCtx): PageView;
export interface ServiceDef { id: string; name: string; color: string; fields: { key: string; label: string; placeholder: string; secret: boolean }[] }
export const SERVICES: readonly ServiceDef[];      // Resend, n8n, Vercel, GitHub, Stripe, Cal.com, Notion
export function servicesPage(ctx: SettingsCtx): PageView;
export function pillCatalog(): { id: string; name: string }[];   // AGENT_SWITCHES (agentLabel) then SERVICES: General's slots and links
```

**Agents.** Four cards, in this order.
1. **`card("Where you code")`** (answer 7).
   - **Claude Code:** a row with `chip("Main")` and no switch (`pillSwitch(true, true, …)`).
   - **One `switchRow` per `AGENT_SWITCHES` entry**, labelled `agentLabel(id)` ("Gemini CLI", "Antigravity").
     - Its state is `pillSwitch(on, false, active.length, installed ? null : "Hooks not installed")`. `installed` comes from that agent's hook status, which this page reads on build. The chip never disables (rule 10).
     - A click saves `{ ...s, activeIntegrations }` with today's cap rule: an off switch at four does nothing. Rust tells the island through `settings-changed`, and the island runs `loadIntegrationTasks` (Task 4).
   - **Help under the card:** `help("On: the pill stays on the island and takes a slot. Off: it shows only while the agent is working.")`. Plan call: the wording.
   - `sync()` recomputes the three rows from the current settings.
2. **`card("Claude Code hooks")`.**
3. **`card("Gemini CLI hooks")`.**
4. **`card("Antigravity hooks")`.**

The three hook cards share one function, `hookCard(ctx, kind: "claude" | "gemini" | "antigravity")`. It merges today's `claudeSection` and `agentHooksSection` and moves them with the same calls, words and flow. Inside the hints, the agent keeps today's name: `Claude Code`, `Gemini CLI`, `Antigravity (agy)`.
- **State.**
  - The card's summary chip is `hookChip(status.installed, false)`. Plan call: these hooks have no "needs update" state on this platform.
  - The status is read on build.
- **Normal body.**
  - Today's hint.
  - Today's `notice("warn", …)` when `!hookReady`.
  - A `wrapRow` of buttons:
    - `Install hooks…`, or `Reinstall hooks…` when installed. It has the class `primary` only when not installed: one prominent button per card (ledger). It is disabled with today's title when `!hookReady`.
    - `Uninstall hooks…` (`danger`), when installed.
  - `pathDisclosure` with two lines, `settings.json` (Claude) or `Config file`, then `Relay`. Each line is `{ label, path: <the real path>, shown: displayPath(<the real path>, ctx.home) }`, so Copy copies the real path and the page shows `~`.
- **Preview** (only this shows while it is open):
  - Today's hint and `renderDiff(displayText(preview.diff, ctx.home))`.
  - `Backup → ${displayPath(preview.backup, ctx.home)}`, or today's "The file doesn't exist yet, so it will be created."
  - A `wrapRow` with the confirm button (`primary` "Back up and write" or `danger` "Back up and remove") and Cancel. Cancel redraws the normal body, so no prompt is left behind.
  - The write is `hooksApply(install, preview.fingerprint)` or `agentHooksApply(kind, install, preview.fingerprint)`.
  - **On success:** today's notice, with the backup through `displayPath`, then today's `window.setTimeout(refresh, 2600)`. That `refresh` re-reads this card's status, and for Gemini CLI or Antigravity it also updates the matching Where you code switch's chip. The `hookStatus` map shared by the page is set, and that row's `set(…, { chip: installed ? null : "Hooks not installed" })` is called, so the chip clears without leaving the page.
  - **On failure:** today's `Could not write: …`.
  - **A preview that throws:** today's error and Back.

**Samples.**
- `ready`:
  - Claude Code is installed and its relay is ready. `settingsPath` is `C:\Users\sample\.claude\settings.json`. `hookPath` is `c:\users\SAMPLE\AppData\Local\NotchMeow\bin\notchmeow-hook.exe`, a case that differs from the home, so the `~` rule is exercised.
  - Gemini CLI is installed and its switch is on. Antigravity is not installed.
- `empty`: no hooks are installed and the relay is not ready.
- `error`:
  - `hooksPreview(true)` rejects with `"~/.claude/settings.json is not valid JSON: NotchMeow has not touched it."`.
  - The Gemini CLI preview's `+` line holds an escaped relay path under `C:\\Users\\sample\\…`.
  - Four pills are on (both agents, Resend and GitHub), so every off switch shows the cap.
- `--stress`: a 90-character config path.

**Services.** `SERVICES` is today's `INTEGRATIONS`, moved and put in the spec's order. Ids, colours, keys, labels and placeholders do not change. There is no Music card and no From field.
- **The card.** `card(name, { dot: color, summary: serviceChip(saved) })`, where `saved` means every field of the service is present.
- **The first row.** `switchRow("Show on the island", …)`, whose state is `pillSwitch(on, false, active.length, null)`. It reads `activeIntegrations`, agents included, so the four-slot rule is shared. `sync()` recomputes every switch.
- **The fields.** For each field, `row(label, [keyField(…), notSaved])`, where `notSaved` is `chip("Not saved")` shown only while `drafts.isDirty(key)`. `onInput` refreshes that chip and the Save button.
  - The placeholder is `"••••••••  (stored)"` when the value is present.
  - When it is present, a `Remove` button (`danger`) runs `await secretClear(key)`, then `drafts.markSaved(key, false)`, then `notice("ok", "Key removed.")`. A refusal shows `notice("err", "Couldn't remove it from the credential store.")`.
- **Save.** It is enabled, and `primary`, only when `drafts.anyDirty(card's keys)`.
  - For each dirty field: `await ctx.backend.secretSet(key, drafts.text(key).trim())`, then `drafts.markSaved(key, true)`.
  - The first refusal stops the save with `notice("err", "Couldn't save to the credential store.")`, and that field keeps its text.
  - When all are written, `notice("ok", "Saved. It never touches disk.")`.
  - Save writes only that card's fields (spec call 2).
- **The page head.** `help("Pick up to 4 pills to show next to your cat, counting the agents you turned on. Keys are stored in your system's credential store, never on disk.")`.

**Samples.**
- `ready`: Resend, GitHub and Vercel are saved; Gemini CLI, Resend, n8n and Vercel are active.
- `empty`: nothing is saved and nothing is active.
- `error`: Resend is typed and not saved, so Save is lit and "Not saved" shows.
- `--stress`: a 120-character n8n URL.

- [ ] **Step 1: Pins** (`pages.test.mjs`, section "Agents and Services").
  - **`agents.ts`, layout and absences:**
    - `card("Where you code"` comes before `card("Claude Code hooks"`.
    - `AGENT_SWITCHES` and `pillSwitch(` are used.
    - It contains `"Hooks not installed"`, and no `codex`, `Plan usage` or `Cursor`.
  - **`agents.ts`, writes and display:**
    - It contains `hooksApply(install, preview.fingerprint)` and `agentHooksApply(`, and every apply call is inside the confirm handler.
    - It contains `displayText(preview.diff, ctx.home)`, at least 3 calls to `displayPath(`, and `hookChip(`.
    - The install button's class is `status.installed ? "" : "primary"`.
    - The refresh after a write updates the agent switch's chip: inside `refresh`, `"Hooks not installed"` (or the shared helper that builds it) and the switch row's `.set(` appear.
    - Copy gets the real path: `pathDisclosure(` is called with `shown: displayPath(` and a `path:` that is not `displayPath(`.
  - **`services.ts`, writes:**
    - `secretSet(` appears once, awaited inside a `try` whose next statement is `markSaved(`. The `catch` holds the refusal sentence and no `markSaved`.
    - `secretClear(` is awaited.
  - **`services.ts`, the rest:**
    - Save's `disabled` is `!ctx.drafts.anyDirty(`.
    - It contains `"Not saved"`.
    - It contains no `"Music"` and no `resend-from`.
    - `new Set(SERVICES.map(s => s.id))` equals `new Set(TOGGLEABLE_INTEGRATION_IDS)`, read from `core/state.ts`. The order is the spec's, checked as a list.

  Run them; they fail.
- [ ] **Step 2: Implement.** Replace the `agents` and `services` cases, and add the samples.
- [ ] **Step 3: Verify.**
  - `tsc` and `npm run check:settings` pass.
  - Render `--page agents` and `--page services` with `--theme both`, `--stress` and `--state error`. At 415, check:
    - no button reads "…";
    - every shown path starts with `~` or is outside the home, with no `sample` and no `SAMPLE`;
    - at most one blue button per card;
    - Where you code's cap chip wraps whole, in both themes.
- [ ] **Step 4: Commit** the five files: `feat(settings/tauri): Agents (Where you code and the hook cards) and Services in the kit`.

---

### Task 8: Pages: General and Devices

**Files:**
- Create: `windows/src/settings/general.ts`
- Modify: `windows/src/settings/devices.ts`, `windows/src/settings/app.ts`, `windows/src/settings/devseed.ts`, `windows/scripts/settings-tests/pages.test.mjs`, `windows/scripts/link-tests/wiring.test.mjs` (the Devices `pagehide` pin only)

**Interfaces:**
- **Consumes:** the kit (`setValue` included); `slots` (Task 1); `pillCatalog` (Task 7).
- **Produces:**
  - `export function generalPage(ctx: SettingsCtx): PageView`.
  - `devicesSection(host)` keeps its signature and its `{ el, sync(s), dispose }`.

**General.** No tab bar. Four cards and a closing line. Every row is today's, moved from `generalSection`, unless stated otherwise.
- **`card("Sound")`.**
  - `switchRow("Enable sounds", …)`.
  - `row("Volume", [range 0 to 0.2, step 0.005, "NN %"])`, disabled while sounds are off.
- **`card("Island")`.**
  - `switchRow("Open on hover", { help: "Hovering the island opens it; it folds again shortly after the pointer leaves. Click inside to keep it open." })`.
  - **[focus]** `switchRow("Step back when I'm already in the app", …)`.
  - `switchRow("Hover glow", { help: "A soft rainbow glow along the island's edge while the pointer is over it." })`.
  - `row("Tuck the island away", select([["never", "Never"], ["1", "After 1 min"], ["5", "After 5 min"], ["15", "After 15 min"], ["30", "After 30 min"]]), "The compact island hides by itself only when no agent is working or waiting, and this long has passed since the last hook event, alert or click on the island.")`.
  - `row("Close after", [number 5..120 step 1, "seconds"], "After you leave the island.")`. Clamp with `Math.max(5, Math.min(120, Number(v) || 15))`.
  - `row("Island lives on", select([["primary", "Main display"], ["cursor", "Display under the cursor"]]))`.
- **`card("On the island")`.**
  - The line `slots(active, pillCatalog()).text`, with the class `hint warn` when `full`.
  - A `wrapRow` of link-style buttons, one per name. An agent's button opens `agents`; a service's opens `services`.
  - `help("Each pill's switch is on the Agents or Services page.")`.
- **`card("Startup")`.** `switchRow("Launch at startup", …)`.
- **The closing line.** `help("No telemetry. Network requests only go to the services you configure yourself.")`.
- **Saving.** Each change saves `{ ...ctx.settings(), <field>: v }`.
- **`sync()`.** It updates the switches with `set`, writes the range, selects and number field through `setValue` (Review Focus 3), and rebuilds the slots line.
- **Samples.**
  - `ready`: sounds at 0.12, two active (Gemini CLI and GitHub).
  - `empty`: none active.
  - `error` and `--stress`: four active.

**Devices.** `devices.ts` is restyled in place. Every closure, the snapshot handling and every word stay.
- **`el` becomes a `div` holding three cards:**
  - `card("This computer")`: the Visible row (today's `h("button", { class: "switch" … })`) and its hint, `row("Name", name)` and its hint, then `nameWarn` and `status`.
  - `card("Machines")`: `list`, `note` and `help`.
  - `card("Received files")`: its hint, `folder`, and `wrapRow(button("Show folder", …))`.
- **Machine rows.** Each row is built from the kit: an `.st-row` holding the dot, the name in a `.st-label`, `chip(stateWords(r.state))`, and its buttons in a `wrapRow`. It does **not** use `lk-machine`, `lk-mname` or `lk-mstate`. Those rules in `link/link.css` (lines 164–178: `nowrap`, a 190 px name cut with an ellipsis, a 100 px minimum) are frozen and would overflow at 415. The list container drops `lk-machines`, and the "Machines" and "Received files" sub-headings (`lk-sub`) go too, since the card titles replace them.
  - The `Forget ${r.name}?` and `Keep` buttons carry the class `st-wrapbtn`, so a long name wraps between words and never scrolls the page sideways (Review Focus 1).
- **`DOT`** keeps Task 6's token.
- **The pairing gate** (Review Focus 2):
  - The `pagehide` listener becomes a named `onHide`. `dispose()` removes it, together with `focus` and `visibilitychange`, and still ends with `backend.setDevicesOpen(false)`.
  - The `IntersectionObserver` observes the first card ("This computer"), not the whole tall `el`, keeping `threshold: 0.2`. Plan call: the card fits the window, so 20 % of it always means "on screen", whatever `el`'s height.
- **The link pin moves.** It changes from `window.addEventListener("pagehide", () => backend.setDevicesOpen(false))` to `window.addEventListener("pagehide", onHide)` plus `window.removeEventListener("pagehide", onHide)`.
- **In `app.ts`,** the `devices` case wraps the section so the types match `PageView`:
  ```ts
  const d = devicesSection({ backend: ctx.backend.link, platform: ctx.platform });
  return { el: d.el, dispose: () => d.dispose() };
  ```
  The section syncs itself from its own link snapshots; the shell's `sync()` does not call it.
- **Samples.** They use `link/devseed.ts`'s existing seeds: `on` for `ready`, `off` for `empty`, `problem` for `error`. `--stress` passes a seed name the dev page builds from `on` with an added row, "A machine with a rather long name for testing the column". This is the one addition `devseed.ts` (settings) makes, by wrapping the link backend's snapshot. `link/devseed.ts` itself is not edited.

- [ ] **Step 1: Pins.**
  - **`general.ts`, cards and rows:**
    - The four cards in order.
    - `switchRow("Hover glow"` and `hoverGlow`.
    - The Tuck values and texts with `tuckAway`, and the Tuck help sentence.
    - `"Close after"` and `"seconds"`.
    - `"Island lives on"`.
  - **`general.ts`, behaviour:**
    - It calls `slots(`, `pillCatalog(` and `setValue(`.
    - It has no `tabBar` and no `Shortcuts`.
  - **[focus]** The focus row comes between `"Open on hover"` and `"Hover glow"`.
  - **`devices.ts`:**
    - It emits none of `lk-machine`, `lk-mname`, `lk-mstate`, `lk-machines` or `lk-sub` (match `/lk-(machine|mname|mstate|sub)/`).
    - The three card titles.
    - `` `Forget ${r.name}?` `` with `st-wrapbtn`, and `"Keep"`.
    - `removeEventListener("pagehide", onHide)`.
    - `observer.observe(` takes the first card.
  - **The Devices link pins** stay as they are, except for the `pagehide` one, which changes as above.
  - **`app.ts`** wraps `devicesSection(` and returns `dispose`.

  Run them; they fail.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - `tsc`, `npm run check:settings` and `npm run check:link` pass.
  - The old long page still builds, because it still calls `devicesSection` and appends `devices.el`.
  - Render `--page general` and `--page devices` with `--stress` and `--theme both`. At 415, check that no word breaks and that "Forget A machine with…?" wraps inside the column, with no sideways scroll.
- [ ] **Step 4: Commit** the six files: `feat(settings/tauri): General and Devices in the kit`.

---

### Task 9: Pages: AI and chat (Your AI, Keys, Local models)

**Files:**
- Create: `windows/src/settings/ai.ts`
- Modify: `windows/src/settings/ctx.ts` (`ai: AiCache`), `windows/src/settings/app.ts` (the cache, three cases, the AI refresh), `windows/src/settings/devseed.ts`, `windows/scripts/settings-tests/pages.test.mjs`

**Interfaces:**
- **Consumes:**
  - The kit, plus `airows.ts` imported as a namespace (`import * as Rows from "./airows.ts"`, so `Rows.chip` does not collide with the kit's `chip`), `AiCache` (Task 2) and `keyChip` (Task 1).
  - `CLOUD_PROVIDERS`, which only `app.ts` passes in.
  - `keyCheckFailure`, from `../core/feature`.
  - `INSTALL_GUIDE`, `GIT_FOR_WINDOWS` and `signInWords`, from `../core/claude.ts`.
- **Produces:**
  - `yourAiTab(ctx)`, `keysTab(ctx)` and `localModelsTab(ctx)`, each returning `PageView`.
  - `aiInput(ctx): AiInput`.
  - `SettingsCtx.ai: AiCache`.
  - `aiArrive(): Promise<void>` in `app.ts`.

**`aiInput`.**
- `claudeState` is `ai.claude?.state ?? null`. `claudeEnabled` and `claudeModel` come from `settings.ai`.
- `keys` are the providers whose key is present.
- `cloudModel[p]` is `settings.ai.cloudModels[p] ?? ai.models[p]?.[0]?.id ?? ""`. Plan call: the remembered model first, else the first of the live list.
- `servers` are `ai.servers` with `id: provider`, `network: placement === "network"`, and the model ids.
- `memory` is `settings.ai.localModels`.

**Your AI** has two cards.
- **`card("Which one answers")`.** Today's `drawWhich`, moved.
  - For Chat and File questions: a `row(label, select)` with the same option groups and the "(not available now)" item.
  - Below it, `help` with today's resolution words.
  - The prefer row reads "When Auto picks a cloud model, prefer", with the labels `Claude plan`, `Claude API` and `OpenAI`. It shows only when there are two or more choices.
  - `sync()` writes the selects through `setValue`.
- **`card("Choose your AI")`.** One block per row.
  - Each block has the title, `help(Rows.helpLine(r, i))`, `chip(Rows.chip(r, i))` and an action:
    - `isMain` → `chip("Main")`.
    - `set` → `button("Make main")`, which saves only `ai.chat` (call 4).
    - `menu` → a `select` whose first option is the disabled, selected "Make main…", followed by the models. A change saves `ai.chat`. Plan call: on this platform the menu is a select.
    - `unavailable` → a disabled "Make main" button with `help(reasonLine)`.
    - A key row with no key also gets `button("Add a key", () => ctx.open({ page: "chat", tab: "keys" }))`.
  - **Claude plan details.** Its block adds `details("Details", …)`, holding today's `drawConnect` controls word for word:
    - the `sayStatus` line;
    - "Stop using it" / "Use my Claude plan" / "Sign in" / "How to install" or "How to update";
    - "Check again" (`backend.claudeStatus()` into `ai.claude`, then `sync()`);
    - the Git notice;
    - `row("Model", select([["sonnet", "Sonnet"], ["opus", "Opus"], ["haiku", "Haiku"]]))`, which saves `ai.claudeCodeModel`;
    - `help("NotchMeow never signs in to Claude and never reads Claude Code's credentials.")`.
  - The "Paste an API key" box and its `preferredCloud` side effect are gone (call 3).

**Keys.** One card each for Anthropic, Google AI and OpenAI, in that order. Plan call: no colour dot.
- **The field row.** `keyField(...)` with `chip("Not saved")` while dirty. The placeholder is `"••••••••••••  (stored)"` when the key is present, else the `CLOUD_PROVIDERS` placeholder.
- **The buttons**, in a `wrapRow`:
  - Save: enabled and `primary` only when the field is dirty.
  - The check mark from `ai.works[p]`: `✓` with class `check ok`, or `✗ <text>` with `check bad`.
  - Remove (`danger`), when the key is present.
- **Help lines.**
  - Anthropic: `From the Claude Console. Saved in your system's credential store, checked when you save.`
  - Google AI: `From Google AI Studio. Saved in your system's credential store, checked when you save.`
  - OpenAI: `From the OpenAI dashboard. Saved in your system's credential store, checked when you save.`
- **Save.** Today's `providerKey` flow, moved:
  1. `await secretSet(key, text.trim())`.
  2. `drafts.markSaved(key, true)`, then `notice("ok", "Saved. It never touches disk.")`.
  3. `ai.loadCloud(p)`. On success, `works[p] = ✓`; on failure, `keyCheckFailure`.
  - A refusal shows `notice("err", \`Could not save: ${err}\`)` and skips the rest: no `markSaved`, no check.
  - It never writes `preferredCloud`.
- **Remove.** Today's flow: `await secretClear`, `ai.forget(p)`, `markSaved(key, false)`, then `notice("ok", "Key removed.")`. A refusal shows `Could not remove: …`.

**Local models.** One `card("Local models")`, today's `drawLocals` moved.
- **The card's help.** `help("Models running on this computer, or on a server you add. Found automatically on this computer only.")`.
- **One block per server:**
  - the dot and name (plus ` · <host>` on the network);
  - `chip(serverChip(…))`;
  - `help("unencrypted on your network", true)` when the server is unencrypted;
  - `help("Start the server and load a model first.")`, only for an installed server that is off or running with no models;
  - a `Get <name>` / `Update` button through `openUrl`, when `getLink` is set and the status is `notInstalled` or `outdated`.
- **Buttons**, in a `wrapRow`: `Rescan`, `Add server…`, and `Remove server` (`danger`, when `customServer` is set).
  - Rescan calls `backend.aiDiscover()`, then `ctx.ai.setServers`, then `sync()`.
- **Add server.** It keeps today's form, but every credential call is awaited and checked (review finding). The order of steps:
  1. If `!isHttpUrl(url)` → `notice("err", "That doesn't look like a URL.")`, and stop.
  2. If a key was typed: `await secretSet(CUSTOM_KEY, key)`. If refused → `notice("err", "Couldn't save the server's key to the credential store.")`, and stop. The URL is not saved.
  3. Else, if a server was already set and `originOf(url) !== originOf(old)`: `await secretClear(CUSTOM_KEY)`. If refused → `notice("err", "Couldn't remove the old server's key from the credential store.")`, and stop. The old key is never sent to a new origin.
  4. Only then save `ai.customServer = url`, then `refresh`.
- **Remove server.** `await secretClear(CUSTOM_KEY)` comes first. If it is refused → the same removal error, and the server stays. Otherwise, save `customServer: null`, then `refresh`.
- **No `.catch(() => undefined)`** on any `secretSet` or `secretClear`.

**The refresh rule (`app.ts`).**
- `aiArrive()` runs when the shell selects a `chat` tab, and on `window` `focus` or `visibilitychange` → `visible` while the page is `chat`. The cache throttles it.
- `backend.on("ai-servers-changed", s => { if (ctx.ai.setServers(s) && page is chat) shell.sync(); })`.

**Samples.**
- `ready`:
  - Claude Code is signed in (`2.1.289`).
  - The Anthropic key is present, with models `claude-sonnet-5-5` and `claude-haiku-5-5`.
  - Servers: Ollama, running 2 models; Studio PC (`custom`, network, `http://192.168.1.20:11434`, unencrypted, 1 model); LM Studio, off.
  - Chat is on Auto; File questions is on Ollama.
- `empty`: Claude Code is not installed; no keys; no servers.
- `error`:
  - The OpenAI key is typed and refused.
  - Claude Code is signed out, with `needsGit`.
  - Add server with a typed key whose `secretSet` is refused.
- `--stress`:
  - A server named "Studio PC in the back office (LM Studio)" with a 40-character model id.
  - A long resolution line.

**The token rule** (ledger): a model id or any token without spaces is shown only in a one-line field or a select, never in wrapping help. The resolution line is the one exception.

- [ ] **Step 1: Pins** (section "AI and chat").
  - **`ai.ts` contains:** the three card titles, the prefer label, `"Claude API"`, `details("Details"`, `"Make main"`, `"Make main…"`, `makeMain(`, `isMain(`, `"Not saved"`, and `setValue(`.
  - **`ai.ts` does not contain:** `Use my Google plan`, `ChatGPT`, `Paste an API key`, `preferredCloud: "anthropic"`, `files:` in a Make main handler, or `.catch(() => undefined)`.
  - **The key-save handler:** the order is `await ctx.backend.secretSet(` < `ctx.drafts.markSaved(` < `ctx.ai.loadCloud(`. Its `catch` has no `markSaved` and no `loadCloud`, and it never mentions `preferredCloud`.
  - **Add server:** both `await ctx.backend.secretSet(CUSTOM_KEY` and `await ctx.backend.secretClear(CUSTOM_KEY` come before `customServer: url`, and each is followed by a `return` in its error path.
  - **Remove server:** `await ctx.backend.secretClear(CUSTOM_KEY` comes before `customServer: null`.
  - **`app.ts`:** `aiArrive` is called from the select path and from the two listeners, and there is no `setInterval`.

  Run them; they fail.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - `tsc` and `npm run check:settings` pass.
  - Render `--page chat` for the three tabs, with `--theme both`, `--stress`, `--state empty` and `--state error`. At 415, check that the following stay whole: "Use my OpenAI plan" with "Coming with the new chat", "Make main", and the long model id in its select.
- [ ] **Step 4: Commit** the five files: `feat(settings/tauri): AI and chat (Your AI, Keys, Local models) in the kit`.

---

### Task 10: Pages: the Sidekick tab and the Cat tabs

**Files:**
- Modify:
  - `windows/src/settings/`: `sidekick.ts`, `cat.ts`, `display.ts`, `wardrobe.ts`, `settings.css`, `app.ts`, `devseed.ts`, and `main.ts` (only the old page's `cat.el, cat.wardrobe,` line).
  - `windows/scripts/settings-tests/pages.test.mjs`.
  - `windows/scripts/sidekick-tests/settings.test.mjs` (only its `sidekick.ts` tests).
  - In `windows/scripts/cat-tests/`, only the assertions on `cat.ts`, `display.ts` and `wardrobe.ts`: `settings-ui.test.mjs`, `wardrobe-ui.test.mjs`, `wardrobe-clock.test.mjs`, `desktop-menu.test.mjs` and `desktop-settings.test.mjs`.

**Interfaces:**
- **Consumes:** the kit; `sidekicktab.ts` and `withMuted` (Task 1); the existing `withUnmuted`, `withSidekickOn`, `withLocal`, `mutedKinds` and `KIND_LABELS`.
- **Produces:**
  - `sidekickSection(host: SidekickHost): { el; sync; dispose }`, with the same host as today.
  - `export type CatTab = "look" | "outfits" | "personality" | "agentcats";`.
  - `catSection(host: CatHost, tab: CatTab | null = null): { el: HTMLElement; sync(): void; dispose(): void }`. A `null` tab gives every card, for the old page.
  - `displayRows` also returns `pair: HTMLElement[]` and `agents: HTMLElement`.

**The Sidekick tab.** Five cards, in this order.
1. **`card("Notes")`.**
   - **The master switch:** `switchRow("Show notes from the sidekick", …)`, which sets `withSidekickOn`.
   - **The kind rows** below are disabled while the master is off:
     - `switchRow("Away recaps", { help: "A short recap when you come back and an agent did something." })`. On is `!muted("recap")`; turning it off is `withMuted`, on is `withUnmuted`. It has a `Show me an example` button.
     - `switchRow("Stuck nudges", { help: "A nudge when an agent looks stuck.", chip: stuckSwitch(...).detail })`. Turning it off mutes all four kinds, on unmutes them. It has a `Show me an example` button (the `stuck.loop` line) and `details("Choose which", …)` with four switches named by `STUCK_NAMES`.
     - `switchRow("Permission line", { help: PERMISSION_LINE, on: true, disabled: true })`. It is locked on and has no stored key (owner's answer 1).
     - `switchRow("Jokes and moods", { on: false, chip: COMES_WITH_F3A, disabled: true })`.
   - **Show me an example** toggles a `div.st-example` box inside the card.
     - The box's head is `Claude Code · Welcome back` or `Claude Code · needs a look`, the island note's own words. Its line is `example(kind)`.
     - It is never the island, never a sound and never a ledger write (builder call 6).
     - It is sized to its text (polish item 7).
2. **`card("Quiet times", { summary: COMES_WITH_F3A })`.**
   - `help("Coming with F3a: hold notes while an app is full screen, during calls and screen sharing, and at hours you choose. Until then notes never show over your work or while you type.")`.
   - Three disabled switch rows, each with the chip: "Full-screen apps", "Calls and screen sharing", "Chosen hours".
3. **`card("Where its words come from")`.**
   - Three radio choices:
     - "Plain rules";
     - "A model on this computer" (`withLocal`), with today's `Found: <name>` or `No local model found` under it;
     - "My main AI", disabled, with the chip.
   - Then `help(NOTHING_LEAVES)` and `help("Only a model on this computer is ever asked, and only with the words of the note.")`.
4. **`card("Today so far", { summary: COMES_WITH_F3A })`.** It holds a disabled button.
5. **`card("Muted notes")`.**
   - Today's list: every muted kind with `Unmute`.
   - `"Nothing is muted"` when none is.
   - The line `"A note you dismiss twice is muted until you unmute it here."`.

The switches are built once, and `sync()` updates them with `set`. There is no timer and no `requestAnimationFrame`.

**The Cat tabs.** `cat.ts` keeps one `VisibleLoop`.
- **The loop.** `visible()` gains `!disposed &&`, and the loop draws only the canvases this build created.
- **`dispose()`** sets `disposed`, removes the three listeners (now named functions), and calls `loop.sync()`.
- **Selects.** `paint()` writes its selects and ranges through `setValue`.

The cards by tab:
- **`look`:**
  - `card("Main cat")`: the hint, plus `.cat-top`.
  - `card("Look")`: Collar and its hint; This cat's collar with `collarWhose`; Fur lines and its hint.
  - `card("Desktop")`: `row("Cat on the desktop", desktop, …)`, its hint, and `host.desktopNote` when set.
- **`outfits`:** the wardrobe element. In `wardrobe.ts`, the `section` becomes `card("Wardrobe", null, …)` with the same children.
- **`personality`:**
  - `card("Personality")`: the preset row, `whose` and the six sliders.
  - `card("Motion")`: Motion style and its hint; This cat's motion with `catWhose`.
  - `card("Every cat")`: Apply to every cat, plus `applied`.
- **`agentcats`:**
  - `card("Display", null, ...display.before)`.
  - `card("Your two cats", null, ...display.pair)`, shown only in mode `two`.
  - `card("Cats for your agents", null, display.agents)`, shown only in mode `perAgent`.
  - **[projects]** `card("Project cats", null, <P's box>)`, last.
- **`null`:** every card above, in that order.

**Narrow widths** (CSS):
- `.cat-grid { grid-template-columns: repeat(auto-fill, 56px); flex: 1 1 260px; }`. The tiles wrap and are never scaled (builder call 9).
- `.cat-notch canvas { max-width: 100%; height: auto; }`.
- `@media (max-width: 599.98px) { .row.cat-trait { grid-template-columns: 1fr 1fr; grid-template-areas: "label label" "slider slider" "low high"; } }`. Plan call: this is the spec's "name above, two ends below", used only where one line does not fit.

**Pins that move here.**
- **`settings-ui.test.mjs`:**
  - The "rows in their order" test becomes "cards in tab order": `card("Main cat"` < `card("Look"` < `card("Desktop"` < `card("Personality"` < `card("Motion"` < `card("Every cat"` < `card("Display"`.
  - The row order stays pinned within each tab.
  - The `.cat-trait` grid test gains the media rule.
  - The `.row > label` `min-width: 132px` assertion stays.
  - The `main.ts` assertion (line 28) stays until Task 12.
- **`wardrobe-ui.test.mjs`:**
  - `return { el, wardrobe: wardrobe.el, sync: paint };` becomes `return { el, sync: paint, dispose };`.
  - The `main` assertion becomes `cat\.el,[\s\S]*?generalSection\(\),`, together with the old page's one-line change.
- **`desktop-settings.test.mjs`:** `row("Cat on the desktop"` inside `card("Desktop"`, after the Main cat hint.
- **`desktop-menu.test.mjs` and `wardrobe-clock.test.mjs`:** their `cat.ts` regexes change only if the text did.
- **`sidekick-tests/settings.test.mjs`:**
  - **The words test** checks for "Show notes from the sidekick", "Away recaps", "Stuck nudges", "Choose which", "Permission line", "Nothing is muted", "Muted notes", "Unmute", "No local model found", "Found: ", "Where its words come from", "Quiet times" and "Today so far".
  - **The class test** allows the window's own classes and any `st-` class.
  - **The `aria-pressed` test:** `kit.ts` contains `setAttribute("aria-pressed", String(`, `sidekick.ts` contains `const masterSwitch = switchRow(` with `masterSwitch.set(`, and there is no `while (el.lastChild`.

- [ ] **Step 1: Move the pins and add new ones** (section "Sidekick and Cat" in `pages.test.mjs`).
  - `sidekick.ts`: the five card titles in order; `withMuted(`; `example(`; `"Claude Code · needs a look"`; and no `explain`, `setTimeout` or `Bridge`.
  - `cat.ts`: `!disposed &&` in `visible:`; `removeEventListener("visibilitychange"`; each `CatTab` value tested; `setValue(`.

  Run them; they fail.
- [ ] **Step 2: Implement.** In `app.ts`, replace the `chat/sidekick` and `cat/*` cases:
  - `chat/sidekick` → `sidekickSection({ sidekick: () => ctx.settings().sidekick, put: (n) => void ctx.save({ ...ctx.settings(), sidekick: n }), found: async () => (await ctx.backend.aiLocalModel()) ?? null })`.
  - `cat/<t>` → `catSection({ cat: () => ctx.settings().cat, put: (n, final) => …, desktopNote: ctx.desktopNote }, t)`. The `put` keeps `n` and saves only when `final`.
- [ ] **Step 3: Samples.**
  - Sidekick:
    - `ready`: `stuck.errors` and `stuck.silent` muted, with the model "Local · qwen3.5:2b".
    - `empty`: nothing muted and no model.
    - `error`: the master switch off and all four stuck kinds muted.
  - Cat: `agentcats` in `perAgent` mode. `--stress` adds `agent_a-rather-long-agent-name`.
- [ ] **Step 4: Verify.**
  - `tsc`, `npm run check:settings`, `npm run check:cat` and `npm run check:sidekick` pass.
  - Render the Sidekick tab and the four Cat tabs with `--stress` and `--theme both`. Check:
    - a hidden tab draws nothing;
    - four tiles fit across at 415;
    - the sliders stack at 415 and stay on one line at 720;
    - the Display preview fits the column.
- [ ] **Step 5: Commit** the fifteen files: `feat(settings/tauri): the Sidekick tab and the Cat tabs in the kit`.

---

### Task 11: Owner checkpoint 1: the pictures, dark and light

- [ ] **Render.** The session renders into `.claude/checkpoints/settings-tauri/` of the worktree, each run with `--theme both` and into its own folder: `bash windows/scripts/render-settings.sh --out …/ready`, `--stress --out …/stress`, `--state empty --out …/empty` and `--state error --out …/error`.
- [ ] **Send.** It sends the owner the 415 and 720 pictures of every page and tab, in dark and light, and asks him to sign off on:
  - the page map, the absences, and General without tabs;
  - Where you code, with its help line. With the default list, which already holds four services (Resend, n8n, Vercel, GitHub), both agent switches start disabled behind the "4 of 4 slots used. Turn another off." chip. The Mac behaves the same, so the owner should expect it;
  - the breakpoint (600) and the column (640);
  - the light palette;
  - the new wordings: the Services head, General's "Each pill's switch is on the Agents or Services page.", the Keys help, Close after's help, and "This computer";
  - the Plan calls on the banner (no page banner; the notices stay in their card) and on agent switches living in `activeIntegrations`.
- [ ] **Changes.** A changed number must change on both platforms, so report it to the main session; the drift pin will fail otherwise. Wording changes go in the page files. **Nothing from Task 12 on starts until the owner says go.**

---

### Task 12: The swap: the real window boots the shell; old sections out; pins moved

**Files:**
- Modify:
  - `windows/src/settings/main.ts`, `app.ts` and `settings.css`.
  - `windows/scripts/settings-tests/pages.test.mjs` and `map.test.mjs`.
  - The moved pins: `windows/scripts/cat-tests/{tuck-wiring,hover-glow,desktop-menu,desktop-settings,wardrobe-ui,wardrobe-clock,settings-ui}.test.mjs`, `windows/scripts/sidekick-tests/{settings,voice}.test.mjs` and `windows/scripts/link-tests/wiring.test.mjs`.
  - **[focus]** `cat-tests/focus-wiring.test.mjs`.
  - **[projects]** `projects-tests/settings.test.mjs`.

**The new `main.ts`.**
- **Imports:** `./settings.css`, `../link/link.css`, `startSettingsApp`, the bridge backend, and `migrate` (for the dev routes).
- **Dev routes:** Task 5's two routes, `shot` and `sample`, unchanged.
- **The `linkdev` lines stay as they are:** `const linkdev = import.meta.env.DEV ? new URLSearchParams(location.search).get("linkdev") : null;`, and the link backend from `(await import("../link/devseed")).devBackend(linkdev)` or `bridgeLinkBackend()`.
- **Start:** `await startSettingsApp(root, bridgeSettingsBackend(link), { storage: localStorageOrNull(), initial: null })`. `localStorageOrNull()` returns `window.localStorage` inside a `try`, else `null`.
- **Deleted:** `claudeSection`, `agentHooksSection`, `aiSection`, `integrationsSection`, `generalSection`, `toggle`, `statusDot`, `renderDiff`, `serverStatus`, `choiceValue`, `FEATURES`, `INTEGRATIONS`, `MAX_ACTIVE` and the old boot. Their bodies already live in the new files.

**`app.ts` gains the window's events.** Each is registered before the first `await`, like `settings-place`.
- **`settings-changed`:**
  1. `settings = { ...settings, ...s }`.
  2. `settings.cat = cleanCatBlock(settings.cat)` and `settings.sidekick = cleanSidekickSettings(settings.sidekick)`.
  3. `shell.sync()`.

  Pages write only through `setValue` and `set`, so the control the user is in is skipped (Review Focus 3).
- **`settings-hidden`:** `() => { ctx.drafts.clearTyped(); shell.sync(); }`.
- **Boot clean-ups,** as today's `main.ts` does them: `settings.cat = cleanCatBlock(settings.cat);` and `settings.sidekick = cleanSidekickSettings(settings.sidekick);`, and `desktopNote: boot && !boot.desktopPositioned ? "<today's GNOME sentence>" : null`.
- **[projects]** P-tauri's `projects-live` listener and its `askProjectsLive()` move here, through the backend.

**`settings.css`.** Delete only the rules the old page used alone: `#settings-root`'s `max-width: 720px` and gap, and the `body.st-app` override. Before deleting any other selector, check that `grep -rn "<class>" windows/src` finds no user.

**Pins that move** (each keeps asserting the same wiring, at its new file):
- **`tuck-wiring.test.mjs`** (lines 42–66) → `general.ts`: the `select([["never", "Never"], …])` form, `tuckAway` saved with its `TuckChoice` cast, the hint, and no absence row.
- **`hover-glow.test.mjs`** (line 59) → `general.ts`: `switchRow("Hover glow"[\s\S]*?hoverGlow`.
- **`desktop-menu.test.mjs`** (line 14), **`desktop-settings.test.mjs`** (line 62) and **`settings-ui.test.mjs`** (line 28, `settings.cat = cleanCatBlock(settings.cat);`) → `app.ts`.
- **`wardrobe-clock.test.mjs`** (line 133) → `app.ts`'s `cat` `put`, which saves only when `final`.
- **`wardrobe-ui.test.mjs`:** the `main` order assertion is replaced by `app.ts` building `catSection(` with the tab.
- **`sidekick-tests/settings.test.mjs`** (lines 40–46) and **`voice.test.mjs`** (line 138) → `app.ts`:
  - the clean-up line, the saving `put`, `found: async () => (await ctx.backend.aiLocalModel()) ?? null`, and `shell.sync()` in `settings-changed`.
  - The "between Cat and General" assertion becomes: `tabs("chat")` holds `"sidekick"`, and `app.ts` builds `sidekickSection(` for `chat/sidekick`.
- **`link-tests/wiring.test.mjs`** (lines 68–71):
  - The `linkdev` and `devseed` assertions stay on `main.ts`.
  - `sidekick\.el,\s*devices\.el,\s*generalSection\(\),` becomes `app.ts` building `devicesSection({ backend: ctx.backend.link`.
  - The `importers` list stays.
- **[focus]** `focus-wiring.test.mjs` → `general.ts`.
- **[projects]** `projects-tests/settings.test.mjs` → `app.ts`.

**New pins** (section "The swap"):
- `main.ts` has fewer than 70 lines, contains `startSettingsApp(` and `bridgeSettingsBackend(`, and contains none of the deleted names or the words "Paste an API key", "Cloud providers" or "Preferred cloud".
- `app.ts` listens to `settings-changed`, `settings-place` and `settings-hidden`, all before its first `await`. `settings-hidden` calls `drafts.clearTyped()`, and no handler calls `secretSet` or `markSaved`.
- `map.test.mjs` gains the cards check: every `winHomes` card except `(the shell)` appears as a string literal in `windows/src/settings/*.ts`, with group cards checked name by name. That includes `"Where you code"`.
- No page file contains `"Shortcuts"`, `codex` or `Plan usage`.
- `grep -rn "Settings… → \(Claude Code\|Gemini CLI\|Antigravity\|AI\b\)" windows/src` finds nothing.

- [ ] **Step 1: Move the pins and write the new ones.** The moved ones fail at first.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - From `windows/`: `npx --no-install tsc --noEmit`, `npm run check:settings`, `check:cat`, `check:sidekick`, `check:link`, `check:claude` and `check:ai`, plus **[projects]** `check:projects`.
  - `npx --no-install vite build`, then `git status --short` shows no `dist/`.
  - Rust: `cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/settings-tauri` and `cargo-windows-check.sh --target-dir /repo/windows/target/win-settings-tauri`.
  - From the repo root: `bash scripts/check-site.sh`, `bash scripts/test-settings-map.sh` and `bash scripts/test-settings-wiring.sh`.
  - Render the full set again with `--stress --theme both`. It is unchanged from checkpoint 1, except for what the owner asked.
- [ ] **Step 4: Commit:** `feat(settings/tauri): six pages in the new shell; the old long page goes`.

---

### Task 13: Docs

**Files:** `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, `docs/SPEC.md`

- [ ] **Step 1: CLAUDE.md.** Add one bullet after the "Settings on the Mac" bullet (line 9):
  > - Settings on Windows and Linux (same spec, answers 6 and 7; plan `docs/superpowers/plans/2026-10-18-settings-restyle-tauri.md`):
  >   - **Pages.** The Mac's six pages. Only AI and chat (Your AI, Keys, Local models, Sidekick) and Cat (Look, Outfits, Personality, Agents' cats) have tabs; General has none (no shortcuts here).
  >   - **Agents → Where you code.** One switch each for Gemini CLI and Antigravity. They are stored as `agent_*` ids in `activeIntegrations` and share the four-slot cap. `core/state.ts` keeps a pill that is on, idle, after its session ends (the Mac's rule); one that is off shows only while its agent works. The hook path is unchanged.
  >   - **Absent:** Codex, Plan usage, the main-pill picker, the AI pill switches, Apple and Music. "Island lives on" is in General → Island.
  >   - **Light and dark.** Settings follows the system: the tokens in `settings.css` have dark and light values, and `contrast.test.mjs` holds every text pair to 4.5:1.
  >   - **Pure rules** in `windows/src/settings/`, tested by `npm run check:settings`:
  >     - `route.ts`: the selection in `localStorage` (`settingsSection`, `settingsTab.<page>`).
  >     - `layout.ts`: the Mac's numbers, and `~` for the home, case-insensitive on Windows and JSON-escaped too.
  >     - `status.ts`.
  >     - `drafts.ts`: the page knows only whether a key is stored, and typed text is dropped on Rust's `settings-hidden`.
  >     - `sidekicktab.ts`, `airows.ts` and `aicache.ts`.
  >   - **Pins.** `drift.test.mjs` holds the pure rules to the Mac's `Settings*.swift`. `map.test.mjs` replays the `winHomes`/`win`/`winOnly`/`winPages` columns of `tests/fixtures/settings/controls.json`.
  >   - **Kit, shell and pages.** `kit.ts` and `shell.ts` build only the shown page and dispose the last one first, and a page's `sync` never writes the control in use (`setValue`). The pages are `general.ts`, `agents.ts`, `ai.ts`, `services.ts`, `cat.ts`/`display.ts`/`wardrobe.ts`, `sidekick.ts` and `devices.ts`. They go through `backend.ts`.
  >   - **Dev tools.** `devseed.ts` is the dev server's sample backend (`settings.html?sample=…&theme=…`). `?dev` has a Settings panel. `bash windows/scripts/render-settings.sh` draws every page through the `?shot=` frame (headless Chrome clamps its own window to 500 px), checks each frame's width, and crops with `sips`.
  >   - **Rust.** `lib.rs` sets 720 × 560 (minimum 415 × 420), lets `open_settings_window` take a place (the `settings-place` event), and emits `settings-hidden`.
- [ ] **Step 2: ARCHITECT.md.** After "**Settings (Mac).**" (line 52), add a paragraph headed "**Settings (Windows and Linux).**". It covers:
  - the same three layers, in TypeScript, plus the island's agent-switch rule;
  - that a page exists only while it is shown;
  - that Make main writes only `ai.chat`;
  - that the page never reads a stored secret;
  - that the window follows the system's appearance;
  - that the island opens a page through `open_settings_window(place)`.
- [ ] **Step 3: windows/README.md.**
  - Replace every "Settings… → Claude Code / Gemini CLI / Antigravity / AI (→ Connect Claude, → Add server…) / Cat / Wardrobe / Devices" with its new place. The lines are 55, 59, 67, 69, 79, 84, 101, 102, 108, 125, 130, 242, **287** (Cat → Display becomes Cat → Agents' cats) and **293** (the wardrobe sentence becomes "Cat → Outfits"; drop "its own card right under Cat").
  - Add a "**Settings**" paragraph to the differences: six pages, the absences, Where you code, "Island lives on", light and dark, and keys shown only as stored or not.
  - Change the source-tree comment at line 207.
- [ ] **Step 4: docs/SPEC.md.** In §10, after the paragraph that starts "Mise en page :", add this paragraph in French:
  > **Windows et Linux.** Mêmes six pages et mêmes onglets, sauf General, qui n'en a pas (pas de raccourcis sur ces systèmes). Pas de carte Codex, de Plan usage, de choix de pastille principale, d'interrupteurs des fournisseurs d'IA, d'Apple on-device ni de Music. Agents → « Where you code » a un interrupteur pour Gemini CLI et pour Antigravity. Ils sont gardés dans `activeIntegrations` et comptent dans les quatre places. Une pastille allumée reste sur l'île après la session ; une pastille éteinte n'apparaît que pendant que l'agent travaille, comme avant. Les hooks ne sont jamais retenus. « Island lives on » est dans General → Island. La fenêtre fait 720 × 560 (415 × 420 au minimum) et suit l'apparence claire ou sombre du système, chaque texte à 4,5:1 au moins. La page ne lit jamais une clé enregistrée ; ce qui a été tapé sans être enregistré survit aux changements de page et disparaît quand la fenêtre se cache. Une page cachée n'existe pas, et quitter Devices ferme l'appairage entrant. L'île peut ouvrir une page précise. La sélection est gardée dans le `localStorage` de la fenêtre.
- [ ] **Step 5: Check and commit.**
  - Run `npm run check:settings` and `bash scripts/check-site.sh`.
  - `grep -n "Settings…\? → AI\b\|Settings…\? → Claude Code\|Settings…\? → Gemini CLI\|Cat → Display\|Wardrobe is its own card" windows/README.md` prints nothing. The `…\?` also catches the plain `Settings →` of README lines 130 and 242.
  - **Commit** the four files: `docs(settings/tauri): the six pages, light mode and agent switches in CLAUDE.md, ARCHITECT.md, the Windows README and SPEC.md`.

---

### After Task 13: whole-branch review

`nm-reviewer-deep` (Sonnet 5.5, high, trigger 4) reviews `git diff main...HEAD`, with `security-review` loaded and `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` beside it (`model: sonnet`). It checks:

- **Nothing lost.** Every control of the old `settings/main.ts` has a home. Every moved body is today's, compared function by function.
- **Keys and secrets.**
  - No secret is read back, drawn, logged or put in a sample.
  - A refused write is never shown as saved, and every server-key step is awaited and aborts on failure.
  - `preferredCloud` is not written by a key save, and Make main writes only `ai.chat`.
- **Window behaviour.**
  - Typed text is dropped on `settings-hidden`.
  - Devices sends `false` when it is left, and no listener outlives its page.
  - No sync overwrites the active control.
- **Performance.** No timer, poll or observer was added, and the Cat loop stops when its page goes.
- **The place.** `settings_place` accepts only `[a-z]+(/[a-z]+)?`.
- **Agent switches.**
  - The default keeps today's behaviour.
  - A pill is never removed while it is not idle.
  - The four-slot cap counts agents and services together.
  - `windows/hook/` and `island/hooks.ts` are unchanged.
- **Palette and pictures.** Both palettes pass contrast, and the island's CSS is unchanged. The render harness asserts its widths.
- **What stays untouched.** The Mac's `controls.json` fields and its two scripts pass, and the site is untouched.

---

### Task 14: Owner checkpoints 2 and 3

**Checkpoint 2, the real window.** The owner runs it himself, with `cd windows && npm run tauri dev` on a Windows PC or a Linux box, or with a CI artifact after he pushes the branch (only the owner pushes). He checks each of these, with its expected result:
1. **Opening.** Open Settings from the tray: it opens on General. Choose Cat → Outfits, close the window and reopen it: it opens on Cat → Outfits.
2. **Resizing.** Resize from the narrowest to full screen on each page and tab. At 415 px the sidebar shows icons with tooltips, no word breaks, no button reads "…" and nothing scrolls sideways. At full screen the cards stay 640 px wide and centred.
3. **Appearance.** Switch the system between light and dark: Settings follows, and the island does not change. On Linux, if WebKitGTK does not follow the GTK theme, note it; this is owed.
4. **Typed text.** Type in the Anthropic field, switch to Sidekick and back: the text is there, with "Not saved". Close and reopen the window: the text is gone. While typing, change the volume from the island's quick control: the field keeps its text.
5. **The four slots.** Turn on Gemini CLI in Where you code, then three services. Every other off switch on Agents and Services is disabled with "4 of 4 slots used. Turn another off.", and General's line is amber and names the four.
6. **An agent switched off.** Run a Gemini CLI session with its switch off: the pill appears while it works and goes after it stops, as today. With the switch on, the pill stays, idle. A permission request is never delayed by either setting.
7. **Hooks.** Agents → Claude Code hooks → Install hooks…: the diff shows `~`, Cancel restores the card, and "Back up and write" writes with a backup.
8. **Make main.** In AI and chat → Your AI, use Make main on a running local model. Chat changes; File questions keeps its own choice.
9. **Sidekick.** In Sidekick, turn Stuck nudges off and on. Show me an example draws inside the card and never in the island.
10. **Island links.** "Open Devices" opens Devices. A service's "Settings…" opens Services. "Add a cloud key" and the key-rejected error's "Open Settings" open Keys.
11. **Pairing.** In Devices, turn Visible on, then go to General. No incoming pairing can start until Devices is shown again.

**Checkpoint 3, sign-off.** After the owner's go, the main session merges according to its own process. This plan never pushes.

---

## Self-review

- **Spec coverage.**
  - **Structure:**
    - The pages and tabs: Tasks 1 and 5.
    - The absences: Global Constraints, the map and Task 12's pins.
    - The switches beside their owners: Services (Task 7), Where you code (Tasks 4 and 7, answer 7) and General's line (Task 8).
  - **AI and chat:**
    - Your AI with Make main, and no credentials read: Tasks 2 and 9.
    - One key box per provider: Task 9.
  - **Sidekick:** Tasks 1 and 10. The permission line is locked (answer 1).
  - **Layout at any width:** Tasks 1 and 5, plus the width-checked pictures.
  - **Light mode (answer 6):** Task 6.
  - **Nothing lost:** Task 2's map and Task 12's card check.
  - **The window:** Task 3 (sizes), Task 5 (shell and tabs) and Tasks 1 and 12 (drafts).
  - **Page rules:**
    - Rules 1 to 6 and 8: the kit.
    - Rule 7: Task 7.
    - Rule 9: `migrate`.
    - Rule 10: `pillSwitch`.
    - Rule 11: drafts.
    - Rule 12: the card orders.
  - **The spec's Windows section:** the third column (Task 2) and the `?dev` page (Task 5).
  - **The main session's calls 1–9 and the builder calls 1–9:**
    - Call 1, the Hotkey group: no such control here.
    - Call 2: Task 7.
    - Calls 3 and 4: Task 9.
    - Call 5, no banner: a Plan call.
    - Call 6: Task 5.
    - Call 7: Task 2.
    - Call 8, Cursor: absent here.
    - Call 9: `COMPANION_TAB_SHOWN`.
    - Builder calls 1 (Task 3), 2 (Task 2), 3 (Remove), 4 (Task 1), 5 (Task 5), 6 (Task 10), 7 (none added), 8 (Task 5) and 9 (Task 10).
- **Plan-review findings fixed:**
  - Headless Chrome's 500 px clamp: the shot harness, its width assertion and `sips` (Task 5).
  - Server-key calls: awaited, and the step aborts on failure (Task 9).
  - Sync skips the active control: `setValue`, in the Global Constraints, Tasks 5, 8, 9 and 10, and Review Focus 3.
  - `PageView` vs `devicesSection.sync(s)`: the `app.ts` wrap (Task 8).
  - Long machine buttons: `st-wrapbtn` (Tasks 5 and 8).
  - `settings-ui.test.mjs:28`: moved in Task 12.
  - `displayPath`: case-insensitive on Windows, with a non-home case (Task 1).
  - Service ids compared as sets: Task 7.
  - `link/devseed.ts` seeds named: Tasks 5 and 8.
  - The "Not saved" chip: Tasks 7 and 9.
  - The Devices observer: Task 8.
  - The place listener registered before boot: Tasks 5 and 12.
  - README lines 287 and 293: Task 13.
  - `chat.ts:140`: Task 3.
  - The note on other plans' anchors: Global Constraints and Execution.
- **Ledger rulings carried:**
  - One prominent button per card; Save lit only when dirty: Tasks 7 and 9.
  - Install prominent only when there is something to install; Cancel clears: Task 7.
  - `~` in previews: Tasks 1 and 7.
  - Make main writes Chat only; no `preferredCloud` from a key save; a refusal is never shown as saved: Task 9 (and Task 7 for refusals).
  - Half-typed keys and old tags: Tasks 1 and 12.
  - "Start the server…" only for an installed server: Task 9.
  - The example sized to its text: Task 10.
  - The stacked pop-up keeps its width: Task 5.
  - Model ids only in fields and selects: Task 9.
- **Type consistency:**
  - `SettingsCtx` and `PageView` (Task 5) → Tasks 7–10 and 12.
  - `DraftBook` (Task 1) → `keyField` and Tasks 7 and 9.
  - `AiCache`, `AiInput`, `Row` and `rowKey` (Task 2) → Task 9.
  - `AGENT_SWITCHES` (Task 4) → Task 7.
  - `pillCatalog` (Task 7) → Task 8.
  - `CatTab` and `catSection` (Task 10) → `app.ts`.
  - `migrate` (Task 1) → Tasks 5 and 12.
  - `setValue` (Task 5) → Tasks 8–10.
- **Proportion.** Code appears only where the text is pinned: the tests, the map, the token table, the dev routes and the CSS numbers.

## Dry run

Every task was walked as its implementer would, against `main` at `50e55140`.

- **Anchors.** Every Task 0 anchor was grepped and prints the stated count.
  - `lib.rs`: the size pair, `fn open_settings_window(app: AppHandle) {` (line 555) and `link_cmd::settings_hidden(&app);`.
  - `bridge.ts`: `openSettingsWindow` (line 80) and `HookAgent` (line 298).
  - `sidekick/core.ts`: `mute` (line 72).
  - `catSection` and `sidekickSection`.
  - `state.ts`: `toggleIntegration` (line 531) and `removeTask` (line 507).
  - `island/hooks.ts`: `State.removeTask(agentId);` twice (lines 327 and 344).
  - `settings.css`: `color-scheme: dark;` (line 6).
  - `settings.html`: the inline style.
  - No global-shortcut code exists. `focusAware` and `projectCats` are 0 today.
- **Agent switches, read in code.**
  - **The Mac.** `loadIntegrationTasks` loads `mainPill ∪ activeIntegrations` (`AppState.swift` 680–708). `removeTask` resets an active declared pill instead of removing it (568–590). `toggleIntegration` caps at 4 (715–725). `HookServer.upsertWorkspaceTask` creates a transient pill for an agent that is off (1014–1037).
  - **Windows today** is exactly the Mac's "off" path: `upsertExternalAgent` on an event (`hooks.ts` 248), then `removeTask` after `Stop` (5.2 s) or at `SessionEnd`.
  - **Where the list is read.** `loadIntegrationTasks` runs on every `settings-changed` (`main.ts` 131), hence the "not while busy" rule. Only `state.ts` and Settings read `activeIntegrations`, and Rust keeps any string in `active_integrations: Vec<String>`.
  - **The relay.** It decides its answer in `hook/src/agents.rs` from the agent tag alone, and never reads settings.
- **Light palette.** Every pair in Task 6's test was computed with the WCAG formula. The lowest pair is 4.90:1 in dark (`--dim-2` `#8d929b` over `--field` blended on `--card`, `#242528`) and 4.86:1 in light (`--dim-2` over `--bg`). Today's dark `--dim-2` was 3.67:1, hence the one dark change; `#878c95` would have been 4.54 over the field.
  - The literal colours in `settings.css` were listed with grep; every one has a token, except the three `#000` cat-preview rules.
  - Inside Settings, `link.css` contributes one `color: var(--ink)` rule.
  - `devices.ts`'s `DOT` holds the only colour literal in a page file that affects the light look.
- **Headless Chrome.**
  - It is installed, and so is `sips`, whose `-c H W --cropOffset 0 0` exists (`sips --help`).
  - Chrome clamps its own window, so the harness gives the frame its real width. `--dump-dom` shows the top document, which reads the same-origin frame's `innerWidth` into `#frame-width`.
- **Run, not just read.**
  - Task 1's `example` lines were run through `windows/src/sidekick/core.ts` with Node, and all four stuck lines and the recap prefix match.
  - The column numbers are the Mac's, proven there.
  - Each commit's file count was recounted.
- **Stored keys.**
  - The `Settings`, `AiSettings`, cat-block and sidekick fields were read in `state.ts` and `settings.rs`.
  - `link.json` is `visible` and `deviceName`.
  - The credential keys come from `main.ts` 982–986, plus `CUSTOM_KEY`; the link's items from `keystore.rs` 27–30.
  - The relay path comes from `settings::hook_exe_path()`, which is `local_dir()/bin`. That is not `home_dir`, hence the case-insensitive rule.
- **The Mac.** `SettingsMapTests` decodes only `version`, `note`, `pages` and `controls` (`id`, `was`, `homes`, `mac`), so the new keys are ignored. `SettingsWiringTests`' card check reads only `controls[].homes`.
- **Source pins this plan moves.** They are listed with their files and lines in Tasks 8, 10 and 12, including `settings-ui.test.mjs:28`. `wardrobe-dev` and `wardrobe-wiring` hold as they are, and `check-ai-ui.mjs` and `check-claude-ui.mjs` do not read `settings/`.
- **Imports.** The pure files and `aicache.ts` load in Node: `.ts` specifiers, `import type`, and `CLOUD_PROVIDERS` passed in as an argument. The new State test imports `State` the way `state-cast.test.mjs` does.
- **The site.** `src/site/main.ts` imports nothing from `settings/`, and `cat/dev.ts` is not in the site bundle.
- **Second review (applied in place).** Each fix was re-walked in its task.
  - **Task 5.** The `st-` CSS block goes before the `/* Wardrobe (sub-project I)` comment (`settings.css:463`), because `wardrobe-ui.test.mjs:68-76` slices from that comment to the end of the file. A pin guards that order. The render script retries a frame once when `frame-width` is missing.
  - **Task 4.** The `git diff main` pin is dropped, since CI is a shallow checkout. Its wording now says an off agent's idle pill goes and comes back.
  - **Task 8.** Devices rows no longer use `lk-machine`, `lk-mname`, `lk-mstate`, `lk-machines` or `lk-sub` (`link.css:164-178` is frozen). A pin guards this, and grep found no other pin on those classes.
  - **Task 7.**
    - A hook refresh updates the agent switch's chip, with its assertion.
    - Copy takes the real path.
  - **Task 6.** The contrast test adds `--dim` and `--dim-2` over `--field`, and the dark `--dim-2` moves to `#8d929b` (4.90:1; computed).
  - **Task 9.** `airows` is imported as `Rows`.
  - **Task 13.** The README grep is now `Settings…\? →`.
  - **Task 11.** It notes that both agent switches start disabled behind the default four services.
  - **Model.** Task 5 is Haiku by ruling, with Sonnet only after two failures; the worktree session stays Sonnet (trigger 5).
- **Fixed in this rewrite** (owner answers 6 and 7, plus the plan review):
  - "Dark only" is gone, and Task 6 adds the palette.
  - The agent switches have their own island task (Task 4), and the Agents page's Where you code card is Task 7.
  - Every review finding is in its task (see "Plan-review findings fixed" above).
  - Tasks were renumbered: the review's Tasks 4–12 are now 5, 7–10 and 12–14.
