# Settings restyle (Mac): Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Mac's Settings window becomes six pages (General, Agents, AI and chat, Services, Cat, Devices), three of them with tabs, built from one small layout kit so that no word breaks inside itself and no button truncates at any width from 415 pt to full screen; every control that exists today has a named home and every stored key keeps its name and meaning.

**Architecture:** Three layers. (1) Pure Foundation rules, tested by `swiftc` programs: the pages, tabs and old-tag migration (`SettingsRoute`), the widths (`SettingsLayout`), the drafts (`SettingsDraftBook`), status words (`SettingsStatus`), the Sidekick tab's rules (`SettingsSidekick`), the AI rows and Make main (`SettingsAI`), and the control map (`SettingsMap` with `tests/fixtures/settings/controls.json`), plus a new `mute(kind)` in `shared/sidekick-core.js`. (2) A view kit (one file each) and page views that take only plain values, bindings and closures, so `scripts/render-settings.sh` draws all six pages before anything is wired (owner checkpoint 1). (3) The app side: `SettingsController` (the transient state and actions moved out of today's 1,544-line `SettingsView.swift`), `SettingsDrafts`, and `SettingsSections.swift`, which reads `AppState`, the Keychain and the services and hands the page views their values. `SettingsView` becomes the shell's host.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`ViewThatFits`, a custom `Layout`, `GeometryReader`, `NSHostingView`), Foundation-only rule files, `swiftc` test programs under `tests/` run by `scripts/test-*.sh`, Node 22 for the sidekick contract, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-17-settings-restyle-design.md` (binding, owner-approved 2026-10-17, including "Calls made by the main session", "Calls made after the builder check" and "Owner's answers" 1 to 5). Answer 4 renames the plan rows ("Use my Claude plan", "Use my OpenAI plan", each with the line "Runs your own installed app, signed in by you. NotchMeow never sees your login.", no logos); **answer 5 removes the Google plan row**: Your AI lists the Claude plan, the OpenAI plan, API keys (Google among them) and local models. The closest earlier plans: `2026-10-14-i-mac-wardrobe.md` (a Settings section and render checkpoints) and `2026-10-15-u1-upstream-fixes-and-island-qol.md` (pins, Settings rows). The Windows/Linux Settings plan comes after checkpoint 1 is signed.

**Base:** a new branch `settings/mac` in a git worktree from `main` at `414d89e6` or later (`git merge-base --is-ancestor 414d89e6 HEAD` must succeed; the Tuck the island away merge is in it). If a find text below does not occur exactly once, stop and report; do not guess.

## Global Constraints

Every task's requirements include this section. Values are the spec's; a line marked "Plan call" is a choice this plan makes where the spec leaves one, with its reason.

- **Swift 6, SwiftUI + AppKit, no new dependency.** The shell is a plain `HStack` of sidebar and detail; no `NavigationSplitView`. Rule files import Foundation only (`SettingsColors.swift` is the one AppKit exception, for the contrast check).
- **The never-restyle rule is lifted for the Settings window only.** Every other view (island, pills, cards, chat) stays exactly as in `main`. The existing style stays: `GroupBox`-based cards, standard `Toggle`/`Picker`, `.bordered` and `.borderedProminent` buttons, the sidebar's coloured icon tiles (`SettingsSidebarRow`) and their colours, SF Pro at today's sizes except help text, system semantic colours. No new colour token, no change to `shared/theme.json`.
- **Numbers (spec "What is left to the builder", starting values, tuned at checkpoint 1):** window minimum content 415 × 420 pt, default 720 × 560, no maximum; breakpoint **600 pt** (narrower: icon sidebar; Plan call, review finding 4: with the spec's starting 560 the column jumped from 471 pt at 559 to 320 pt at 560, narrower than the 415 window's 327; at 600 the expanded sidebar leaves a 360 pt column, so 327 at 415 stays the narrowest column the window allows); sidebar 200 pt, 56 pt collapsed; column maximum 640 pt, centred beyond it; side padding 20 pt, 16 pt collapsed; field maximum 420 pt; number field 64 pt; picker 180 pt side by side, full width stacked; help text 12 pt. Plan call: tab bar row height 28 pt; the divider between sidebar and detail is an overlay that takes no width (so the widths add up exactly).
- **Every stored key keeps its name and meaning** (spec's control map). New keys: only `settingsTab.<page>`. `settingsSection` keeps working through `SettingsRoute.migrate` (rule 9). The control map test proves nothing is lost or renamed.
- **Frozen IDs untouched:** pill IDs, cat IDs, shortcut action IDs, outfit IDs, `nm-hook`, `nm.sock`, bundle identifiers. Never rename a pill ID.
- **Secrets:** keys stay in the Keychain, stay masked (`SecureField`), and are never put in a picture, a log or a fixture. Page views and the render tool never touch `KeychainStore`; the render tool uses obviously fake values (`sample-key-0000`). Saving stays an explicit click; a half-typed key is never saved by a tab or page change (rule 11).
- **No CPU while Settings is closed and no new timer, observer or poll while it is open.** Hidden tabs are not in the view tree. The cat previews keep `WindowVisibility`. The only network calls are today's (the key check, the model list, the n8n and Vercel lists), each on a click or on Settings opening as today.
- **The App Store build (`#if APPSTORE`) keeps its differences:** Claude Code hooks through the folder picker and its alert; no Gemini, Antigravity or Codex hook cards; no Plan usage; no Claude plan or OpenAI plan rows; no Music card (Apple Music is `githubOnly`). Those rows are absent, not greyed.
- **Never block Claude Code; never overwrite `~/.claude/settings.json`:** the install flows keep their preview, "Confirm & write", backup and notes exactly; only where they sit changes.
- **No telemetry.** Nothing new is logged.
- **macOS is primary; Windows/Linux files are not touched** except the generated `windows/src/sidekick/core.generated.ts` (Task 1, written by its generator).
- **Never edit `NotchBuddy.xcodeproj` by hand.** A task that adds an app file runs `cd NotchBuddy && xcodegen` before building and commits the regenerated `project.pbxproj`.
- **Models and commits** (CLAUDE.md, "Working with AI agents"): Haiku 5.5 first; Sonnet 5.5 only on a named trigger; never Opus or Fable. Each commit is local, never pushed, lists only its task's files, uses `git commit -F <file>`, and ends with the `Co-Authored-By` line of the model that did the task.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app. Builds only build; the render scripts are not the app and may run.
  2. Install nothing; no network calls; no downloads.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; scratch files go under `${TMPDIR:-/tmp}` in a uniquely named folder.
  4. Never read, print or write the real Keychain items, `~/.claude`, `~/.gemini` or `~/.codex`. No `UserDefaults` suite and no write to `UserDefaults.standard` in a test.
  5. Never edit `design/prototype/cat-core.js`, `shared/projects-core.js`, `shared/theme.json`, a generated theme file, a fixture outside `tests/fixtures/settings/` and `tests/fixtures/sidekick/` (the latter only through its generator, Task 1), or anything under `windows/` except through `node scripts/gen-sidekick-ts.mjs`.
  6. Never push. Commit only in a task's commit step, after `git rev-parse --show-toplevel` shows this worktree and `git branch --show-current` shows `settings/mac`.
  7. Never rename a frozen ID; write no `Coucou` or `Mochi` name anywhere.
  8. If a command is denied by a permission prompt, or a find text occurs zero or two times, stop and report it.

## Review Focus

The spec says what Settings does; it is silent on these conditions, most likely first. Each names the test that pins it.

1. **The narrowest column with the longest strings.** At 415 pt the column is 327 pt, the narrowest the window allows (just above the 600 pt breakpoint it is 360 pt; at 599 it is 511): a long model name, a long path, a long server or device name, a long error, "Use my OpenAI plan" with its chip, the island's shortcut list. Expected: words wrap between words, rows stack, buttons and chips never truncate, nothing is clipped. Tests: Task 4's kit pins (`fixedSize` buttons and chips, `WrapRow` is a `Layout`, labels never `lineLimit(1)`), every page drawn with `--stress` at 415 in Tasks 5 to 8, and checkpoint 1.
2. **A stored selection from an older build.** `settingsSection` = `activepills`, `integrations`, `shortcuts`, `sidekick`, empty, or garbage; `settingsTab.cat` = `keys` (a tab of another page) or garbage; the island's "Settings…" button posting `integrations`. Expected: the mapped page and tab, General when unknown, never a blank detail. Tests: Task 2 (`migrate`, `tab(for:stored:)`), Task 12 pins (the island posts `services`; the shell migrates on appear and on change).
3. **A half-typed key, and one Save writing another card's fields.** Typing in the Anthropic field, switching to Sidekick and back; saving the Resend card while n8n has unsaved text. Expected: the text is kept with a "Not saved" chip; one card's Save writes only that card's fields; GitHub's side effects run only when its token changed. Tests: Task 2 (`SettingsDraftBook`), Task 10 pins (`saveService(_:)` writes only `SettingsMap.serviceFields[id]`).
4. **The four-slot cap seen from a page that is not the one you changed.** Four pills on (two agents, Anthropic, Resend), then a switch on the Keys tab or a Local models row; the main pill changed to Cursor. Expected: every off switch in every page is disabled with "4 of 4 slots used. Turn another off."; the main pill shows "Main" and no switch; the General line names the four. Tests: Task 2 (`SettingsStatus.pillSwitch`, `slots`), Task 10 pins (one helper builds every pill row).
5. **A kind's switch and the dismissal memory disagreeing.** A kind switched off and then dismissed once more; a kind unmuted from the Muted notes list; three of the four stuck kinds muted. Expected: off is "muted" (count 2) and stays 2; unmute turns the switch on; the stuck switch reads on with "1 of 4" when three are muted (on means at least one is unmuted). Tests: Task 1 (`mute` cases), Task 2 (`SettingsSidekick.stuckSwitch`).

Also covered: the App Store build's absences (`--appstore` pictures, Task 12 pins on `#if !APPSTORE`), a saved key never in a picture (Task 4 privacy check), Make main on a provider whose model is unknown (Task 3).

---

## File Structure

| Path | Responsibility |
|---|---|
| `shared/sidekick-core.js`, `scripts/gen-sidekick-fixtures.mjs`, `tests/fixtures/sidekick/dismiss-cases.json` (generated), `windows/src/sidekick/core.generated.ts` (generated), `tests/sidekick/settings.test.mjs`, `docs/SIDEKICK-CONTRACT.md` | `mute(kind)` and its cases (Task 1). |
| `NotchBuddy/Sources/App/SidekickSettings.swift`, `SidekickStore.swift`, `tests/SidekickSettingsTests.swift` | The Mac port of `mute`, the store's `mute(_:)` (Task 1). |
| `NotchBuddy/Sources/App/SettingsRoute.swift`, `SettingsLayout.swift`, `SettingsDraftBook.swift`, `SettingsStatus.swift`, `SettingsSidekick.swift` (new) | Pure rules A (Task 2). |
| `tests/SettingsRulesTests.swift`, `scripts/test-settings-rules.sh` (new) | Their test (Task 2). |
| `NotchBuddy/Sources/App/SettingsMap.swift`, `SettingsAI.swift`, `SettingsColors.swift` (new); `tests/fixtures/settings/controls.json` (new) | Pure rules B: the control map, the AI rows and Make main, the help colour (Task 3). |
| `tests/SettingsMapTests.swift`, `tests/SettingsAITests.swift`, `tests/SettingsContrastTests.swift`, `scripts/test-settings-map.sh`, `scripts/test-settings-ai.sh`, `scripts/test-settings-contrast.sh` (new) | Their tests (Task 3). |
| `NotchBuddy/Sources/App/SettingsShell.swift`, `SettingsPage.swift`, `SettingsCard.swift`, `SettingRow.swift`, `SwitchRow.swift`, `KeyRow.swift`, `StatusChip.swift`, `WrapRow.swift`, `PathDisclosure.swift`, `HelpText.swift`, `SettingsTabBar.swift`, `SettingsBanner.swift` (new) | The kit, one file each (Task 4). |
| `scripts/render-settings.sh`, `scripts/render-settings.swift`, `scripts/check-settings-render-private.sh`, `tests/SettingsWiringTests.swift`, `scripts/test-settings-wiring.sh` (new) | The pictures, the privacy pin, the source pins (Task 4, grown by later tasks). |
| `NotchBuddy/Sources/App/SettingsGeneralPage.swift` (new), `ShortcutsSettingsView.swift`, `LinkViews.swift` (`DevicesSettingsView` only) | General (both tabs) and Devices (Task 5). |
| `NotchBuddy/Sources/App/SettingsAgentsPage.swift`, `SettingsServicesPage.swift` (new) | Agents and Services (Task 6). |
| `NotchBuddy/Sources/App/SettingsAIPage.swift` (new), `AISettingsViews.swift` | Your AI, Keys, Local models (Task 7). |
| `NotchBuddy/Sources/App/SidekickSettingsView.swift`, `CatSettingsView.swift`, `CatSettingsSection.swift`, `WardrobeSettingsView.swift` | The Sidekick tab and the Cat tabs (Task 8). |
| `NotchBuddy/Sources/App/SettingsController.swift`, `SettingsDrafts.swift`, `SettingsSections.swift` (new) | The app side (Tasks 10, 11). |
| `NotchBuddy/Sources/App/SettingsView.swift`, `AppDelegate.swift`, `IslandViewContent.swift`, `ClaudeChatViews.swift` | The swap: the shell host, the window minimum, the island's tag, the old Connect Claude view removed (Tasks 11, 12). |
| `tests/CatWiringTests.swift`, `CatSettingsTests.swift`, `WardrobeWiringTests.swift`, `DesktopCatWiringTests.swift`, `IslandTuckAwayWiringTests.swift`, `HookInstallNoteTests.swift`, `SidekickWiringTests.swift`, `scripts/test-link-wiring.sh`, `scripts/test-u1-wiring.sh`, `scripts/check-no-leftovers.sh`, `scripts/render-cat-settings.sh`, `scripts/render-sidekick.swift` | Pins and scripts that move with the code (Tasks 8, 12). |
| `.github/workflows/build.yml` | One step per new test script (Tasks 2, 3, 4, 12). |
| `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md`, `docs/INTEGRATIONS.md`, `docs/PROJECTS-CONTRACT.md`, `NotchBuddy/Sources/App/PillCatalog.swift` (a comment) | Docs and names (Task 13). |

## Tasks and agents

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`; the deep agent also `superpowers:systematic-debugging`. View tasks (4 to 8, 10 to 12) also read `swiftui-patterns` *(file: `~/.claude/plugins/marketplaces/ecc/skills/swiftui-patterns/SKILL.md`)*; Tasks 4 to 8 read `accessibility` and `design-system` *(files, same folder)* as an audit only (ARCHITECT.md, "Settings polish": `design-system` never writes a tokens file). Reviewers load `ponytail:ponytail-review`. The final reviewer also loads `security-review` (the Keychain, the hook writers) and runs `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` beside it (`model: sonnet`, trigger 4).

| # | Task | Agent, model, effort | Trigger | Review |
|---|---|---|---|---|
| 0 | Worktree and baseline | the session | | none |
| 1 | `mute(kind)`: the contract, the generated copies, the Mac port | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 2 | Pure rules A: route, layout, drafts, status, Sidekick tab | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 3 | Pure rules B: control map, AI rows, help colour | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 4 | The kit, the render frame, the privacy and kit pins | `nm-implementer-deep`, **Sonnet 5.5, high** | 1 | `nm-reviewer` |
| 5 | Pages: General (General, Shortcuts) and Devices | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 6 | Pages: Agents and Services | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 7 | Pages: AI and chat (Your AI, Keys, Local models) | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 8 | Pages: the Sidekick tab and the Cat tabs | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 9 | **Owner checkpoint 1:** the pictures | the main session and the owner | | none |
| 10 | App side A: controller, drafts, General, Agents, Services, Devices | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 11 | App side B: AI and chat, Make main, Sidekick, Cat | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 12 | The swap: shell host, window, migration, old code out, pins moved | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 13 | Docs and names | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| After 13 | Whole branch: nothing lost, secrets, App Store absences, CPU | `nm-reviewer-deep`, Sonnet 5.5, high | 4 | none |
| 14 | **Owner checkpoints 2 and 3:** the real window, then sign-off | the main session and the owner | | none |

Why Task 4 is Sonnet (trigger 1): the kit is where the spec's layout promises are designed, not copied: `ViewThatFits` fallbacks that never shorten a label, a custom `Layout` that wraps `fixedSize` buttons, a text tab bar with a menu fallback, the shell's breakpoint from `GeometryReader`, and offscreen `NSHostingView` pictures in both appearances. Everything else uses the kit or moves existing code. If a Haiku task fails twice, hand it to `nm-implementer-deep` (trigger 2) and write the trigger in the ledger.

## Execution

One worktree chat session runs the whole plan: branch `settings/mac`, **Sonnet 5.5 at high effort** (trigger 5: an app plan with many cross-task interfaces: the kit, five page model types, the controller and the sections). Start it in the three steps of `ARCHITECT.md`: the chip runs only Task 0 Steps 1 to 3 (`git switch -c settings/mac main`, the base checks), reads `CLAUDE.md`, `ARCHITECT.md`, this plan and the spec, replies "ready" and stops; the main session sets the model and effort; then it sends the controller brief. Keep a ledger at `.superpowers/sdd/2026-10-17-settings-mac/progress.md` (one line per task: agent, model, commit, test lines, review verdict, escalations). Reviews read `git diff main...HEAD` narrowed to the task's files. Every ```` ```bash ```` block passes `bash -n` before it is run. The session pings the main session with `SendMessage` at Task 9, at the end, and whenever it stops. Run Tasks 1 to 8, stop for checkpoint 1 (copy the PNGs to `.claude/checkpoints/settings-mac/` of the worktree, never committed), then Tasks 10 to 13, the whole-branch review, and stop for Task 14.

**Plans in flight that touch the same files** (each whichever-merges-second rule is the spec's "Rows other plans add"):
- **Focus awareness (Mac)** adds `Toggle("Step back when I'm already in the app", isOn: $state.focusAware)` to today's `SettingsView` and pins it in `tests/FocusAwareWiringTests.swift`. If it is merged before Task 10 (`grep -c 'var focusAware' NotchBuddy/Sources/App/AppState.swift` prints `1`), Tasks 5, 10 and 12 carry its row and move its pin (steps marked **[focus]**). If it merges after this plan, its own plan must put the row in `GeneralSettingsModel.focusAware` instead.
- **Projects (P-mac)** adds "Project cats" to `CatSettingsView`. If merged before Task 8 (`grep -c 'projectCats' NotchBuddy/Sources/App/CatSettingsStore.swift` ≥ 1), Task 8 puts its group in the Agents' cats tab after `agentsGroup` (step **[projects]**).
- **F3a (Mac companion)** adds a "Companion" sidebar row. The spec puts it in a fifth, hidden tab on AI and chat (`SettingsRoute.companionTabShown`, Task 2). Do not run F3a-mac's Settings task beside this plan; whichever lands second hosts `CompanionSettingsView` in the Companion tab and flips the flag.

---

### Task 0: Worktree and baseline

- [ ] **Step 1:** `git switch -c settings/mac main`; `git merge-base --is-ancestor 414d89e6 HEAD && echo ok` prints `ok`.
- [ ] **Step 2: Anchors** (each prints `1` unless noted):
  ```bash
  A=NotchBuddy/Sources/App
  grep -c '@AppStorage("settingsSection") private var selectedSection: String = "general"' $A/SettingsView.swift
  grep -c 'win.contentMinSize = NSSize(width: 640, height: 420)' $A/AppDelegate.swift
  grep -c 'host.sizingOptions = \[.minSize\]' $A/AppDelegate.swift          # 3 (Settings and the two Debug panels)
  grep -c 'default:                 section = "integrations"' $A/IslandViewContent.swift
  grep -c 'struct ConnectClaudePlanView: View {' $A/ClaudeChatViews.swift
  grep -c 'api.unmute = (state, kind) =>' shared/sidekick-core.js
  grep -c "run('a whole number is 1'" scripts/gen-sidekick-fixtures.mjs
  grep -c 'func unmuted(_ kind: String) -> SidekickSettings {' $A/SidekickSettings.swift
  grep -cF 'func unmute(_ kind: String) { update { $0 = $0.unmuted(kind) } }' $A/SidekickStore.swift
  grep -cF 's = (op["op"] as! String) == "dismiss" ? s.dismissed(kind) : s.unmuted(kind)' tests/SidekickSettingsTests.swift
  grep -c 'struct DevicesSettingsView: View {' $A/LinkViews.swift
  grep -c 'WardrobeSettingsGroup(store: store, active: active, day: wardrobeDay)' $A/CatSettingsView.swift
  grep -c 'var focusAware' $A/AppState.swift            # 0 or 1: [focus] steps apply when 1
  grep -c 'projectCats' $A/CatSettingsStore.swift       # 0, or ≥1: [projects] step applies
  ```
- [ ] **Step 3: Baseline** (all pass, write the last lines in the ledger): `bash scripts/test-sidekick-contract.sh`, `bash scripts/test-sidekick-settings.sh`, `bash scripts/test-sidekick-wiring.sh`, `bash scripts/test-cat-wiring.sh`, `bash scripts/test-cat-settings.sh`, `bash scripts/test-wardrobe-wiring.sh`, `bash scripts/test-cat-desktop-wiring.sh`, `bash scripts/test-island-tuck-away-wiring.sh`, `bash scripts/test-hook-install-note.sh`, `bash scripts/test-link-wiring.sh`, `bash scripts/test-u1-wiring.sh`, `bash scripts/test-shortcuts.sh`, `bash scripts/check-no-leftovers.sh`; and `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet` → `BUILD SUCCEEDED`. Do not open the app.

---

### Task 1: `mute(kind)`: the contract, the generated copies, the Mac port

The spec's rule S1: turning a kind's switch off writes it as muted, the same as two dismissals (`sidekick.dismissals` count 2); turning it on is the existing `unmute`. The JS core decides.

**Files:**
- Modify: `shared/sidekick-core.js`, `scripts/gen-sidekick-fixtures.mjs`, `tests/sidekick/settings.test.mjs`, `docs/SIDEKICK-CONTRACT.md`, `NotchBuddy/Sources/App/SidekickSettings.swift`, `NotchBuddy/Sources/App/SidekickStore.swift`, `tests/SidekickSettingsTests.swift`
- Regenerate: `tests/fixtures/sidekick/dismiss-cases.json`, `windows/src/sidekick/core.generated.ts`

**Interfaces:**
- Produces: JS `api.mute(state, kind) -> Dismissals`; Swift `SidekickSettings.muting(_ kind: String) -> SidekickSettings`; `SidekickStore.mute(_ kind: String)`.

- [ ] **Step 1: The failing JS test.** In `tests/sidekick/settings.test.mjs`, extend the test "dismiss and unmute do not change the state they are given" to also call `core.mute(s, 'recap')` and still find `s` unchanged, and add:
  ```js
  test('mute is two dismissals at once, for the five kinds only', () => {
    for (const k of core.DISMISS_KINDS) assert.equal(core.mute(null, k)[k], core.MUTE_AT);
    assert.deepEqual(core.mute(null, 'risk'), core.cleanDismissals(null));
    assert.deepEqual(core.mute({ recap: 1 }, 'recap').recap, 2);
    assert.ok(core.muted(core.mute(null, 'stuck.silent'), 'stuck.silent'));
  });
  ```
  Run `node --test tests/sidekick/settings.test.mjs` → fails (`core.mute is not a function`).
- [ ] **Step 2: The rule.** In `shared/sidekick-core.js`, right after the `api.unmute = …` line, add `api.mute` with the doc comment "A kind's switch turned off in Settings: that kind is muted at once, the same as two dismissals. A kind that is not one of the five changes nothing." Body: clean the state; for a known kind set it to `MUTE_AT`; return it. Re-run → passes.
- [ ] **Step 3: The fixture cases.** In `scripts/gen-sidekick-fixtures.mjs`, `SECTIONS['dismiss-cases.json']`: change the ops comment to `['dismiss' | 'unmute' | 'mute', kind]`; after the `run('a whole number is 1', …)` line append:
  ```js
  run('mute is the same as two dismissals', null, [['mute', 'stuck.loop']], [[s({ 'stuck.loop': 2 }), ['stuck.loop']]]);
  run('mute after one dismissal goes to two', s({ recap: 1 }), [['mute', 'recap']], [[s({ recap: 2 }), ['recap']]]);
  run('mute of a muted kind stays at two', s({ recap: 2 }), [['mute', 'recap']], [[s({ recap: 2 }), ['recap']]]);
  run('mute, then unmute, is back to zero', null, [['mute', 'stuck.waiting'], ['unmute', 'stuck.waiting']], [[s({ 'stuck.waiting': 2 }), ['stuck.waiting']], [zero, []]]);
  run('mute of a kind that does not exist changes nothing', null, [['mute', 'risk'], ['mute', null]], [[zero, []], [zero, []]]);
  ```
  and append to the section's `note` string: ` mute(state, kind) mutes a kind at once (a switch turned off in Settings), the same as two dismissals.` Run `node scripts/gen-sidekick-fixtures.mjs` then `node scripts/gen-sidekick-ts.mjs`. `git diff --stat` shows `dismiss-cases.json` and `core.generated.ts` changed, and no other fixture file.
- [ ] **Step 4: The failing Swift replay.** In `tests/SidekickSettingsTests.swift`, replace the line `s = (op["op"] as! String) == "dismiss" ? s.dismissed(kind) : s.unmuted(kind)` with a `switch op["op"] as! String` over `"dismiss"` → `s.dismissed(kind)`, `"unmute"` → `s.unmuted(kind)`, `"mute"` → `s.muting(kind)`, `default:` record a diff `"unknown op"`. Run `bash scripts/test-sidekick-settings.sh` → compile error (`muting`).
- [ ] **Step 5: The port.** `SidekickSettings.muting(_:)` after `unmuted(_:)`, same shape (a known kind set to `Self.muteAt`), with a doc line; add `mute` to the file's header comment list of ports ("Port of `dismiss`, `muted`, `unmute`, `mute` and …"). `SidekickStore.mute(_ kind: String) { update { $0 = $0.muting(kind) } }` after `unmute`. Re-run → `All tests passed.`
- [ ] **Step 6: The contract doc.** In `docs/SIDEKICK-CONTRACT.md`, rename the heading to `` ### `dismiss`, `muted`, `unmute`, `mute`, `cleanSidekickSettings` `` and add one sentence under it: "`mute(state, kind)` sets a kind to 2 at once: Settings → AI and chat → Sidekick turns a kind's switch off with it, and on again with `unmute`."
- [ ] **Step 7: Verify.** `bash scripts/test-sidekick-contract.sh` (ends `✓ two generator runs write identical bytes`), `node scripts/gen-sidekick-ts.mjs --check` (exit 0), `(cd windows && node --experimental-strip-types --test scripts/sidekick-tests/*.test.mjs)` (all pass), `bash scripts/test-sidekick-settings.sh`, `bash scripts/test-sidekick-wiring.sh` (the 21 files' token pins still hold).
- [ ] **Step 8: Commit** the nine files with `feat(sidekick): mute(kind), the switch's twin of unmute (contract, fixture, Mac port)`.

---

### Task 2: Pure rules A: route, layout, drafts, status, Sidekick tab

**Files:**
- Create: `NotchBuddy/Sources/App/SettingsRoute.swift`, `SettingsLayout.swift`, `SettingsDraftBook.swift`, `SettingsStatus.swift`, `SettingsSidekick.swift`, `tests/SettingsRulesTests.swift`, `scripts/test-settings-rules.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces (Produces; later tasks use these exact names):**
```swift
enum SettingsRoute {
    enum Page: String, CaseIterable, Sendable { case general, agents, chat, services, cat, devices }
    enum Tab: String, CaseIterable, Sendable {
        case general, shortcuts, yourAI = "yourai", keys, localModels = "localmodels", sidekick, companion,
             look, outfits, personality, agentCats = "agentcats"
    }
    struct Place: Equatable, Sendable { var page: Page; var tab: Tab? = nil }
    static let companionTabShown = false
    static let sectionKey = "settingsSection"
    static func tabKey(_ page: Page) -> String                       // "settingsTab.<page.rawValue>"
    static func title(_ page: Page) -> String                        // General, Agents, AI and chat, Services, Cat, Devices
    static func title(_ tab: Tab) -> String                          // General, Shortcuts, Your AI, Keys, Local models, Sidekick, Companion, Look, Outfits, Personality, Agents' cats
    static func icon(_ page: Page) -> (symbol: String, color: String)
    static func tabs(_ page: Page, companion: Bool = companionTabShown) -> [Tab]
    static func migrate(storedSection: String?) -> Place
    static func tab(for page: Page, stored: String?) -> Tab?         // a valid stored tab of that page, else its first tab; nil for a page without tabs
}
enum SettingsLayout {
    enum SidebarMode: Equatable, Sendable { case expanded, icons }
    static let minWidth = 415.0, minHeight = 420.0, defaultWidth = 720.0, defaultHeight = 560.0
    static let breakpoint = 600.0, sidebarWide = 200.0, sidebarIcons = 56.0, columnMax = 640.0
    static let padding = 20.0, paddingCollapsed = 16.0, fieldMax = 420.0, numberField = 64.0, pickerWidth = 180.0
    static let helpSize = 12.0, tabBarHeight = 28.0
    static func sidebarMode(windowWidth: Double) -> SidebarMode
    static func sidebarWidth(_ mode: SidebarMode) -> Double
    static func padding(_ mode: SidebarMode) -> Double
    static func detailWidth(windowWidth: Double) -> Double
    static func columnWidth(windowWidth: Double) -> Double
    static func displayPath(_ path: String, home: String) -> String
}
struct SettingsDraftBook: Equatable, Sendable {
    init(saved: [String: String])                 // field id → the stored value ("" when none)
    func text(_ id: String) -> String
    mutating func edit(_ id: String, _ text: String)
    mutating func markSaved(_ id: String, stored: String)   // what was really written (a trimmed key, "" after a removal)
    func isDirty(_ id: String) -> Bool
    func isSaved(_ id: String) -> Bool
}
enum SettingsStatus {
    struct Slots: Equatable, Sendable { var text: String; var names: [String]; var full: Bool }
    struct PillSwitch: Equatable, Sendable { var showsSwitch: Bool; var chip: String?; var disabled: Bool }
    enum Tone: String, Sendable { case ok, warn, neutral, error }
    static let maxSlots = 4
    static let capSentence = "4 of 4 slots used. Turn another off."
    static func slots(active: Set<String>, catalog: [(id: String, name: String)]) -> Slots
    static func pillSwitch(isOn: Bool, isMain: Bool, activeCount: Int, missing: String?) -> PillSwitch
    static func hookChip(installed: Bool?, needsUpdate: Bool) -> String?
    static func keyChip(saved: Bool) -> String          // "Ready" | "No key yet"
    static func serviceChip(saved: Bool) -> String      // "Saved" | "No key yet"
    static func tone(_ chip: String) -> Tone
}
enum SettingsSidekick {
    static let stuckKinds = ["stuck.loop", "stuck.errors", "stuck.waiting", "stuck.silent"]
    static let stuckNames: [(kind: String, label: String)]   // the four, labelled as today: Repeated steps, Repeated errors, Waiting for your OK, Gone quiet
    static let permissionLine = "Always on: it tells you what a permission would do."
    static let nothingLeaves = "Nothing leaves this Mac unless you pick a cloud AI as your main AI."
    static let comesWithF3a = "Comes with F3a"
    static func stuckSwitch(isMuted: (String) -> Bool) -> (on: Bool, detail: String?)
    static func example(_ kind: String) -> String?          // recap, stuck.loop, stuck.errors, stuck.waiting, stuck.silent; nil otherwise
}
```

The rules, exactly:
- `icon`: general `gearshape.fill` `#8E939C`; agents `terminal.fill` `#3B9EFF`; chat `bubble.left.and.bubble.right.fill` `#E07950`; services `puzzlepiece.extension.fill` `#7C5CFF`; cat `pawprint.fill` `#D9A066`; devices `laptopcomputer.and.iphone` `#5B8DEF`.
- `tabs`: general `[.general, .shortcuts]`; chat `[.yourAI, .keys, .localModels, .sidekick]` plus `.companion` last when `companion`; cat `[.look, .outfits, .personality, .agentCats]`; agents, services, devices `[]`.
- `migrate` (rule 9): `general`, `agents`, `chat`, `services`, `cat`, `devices` → that page, tab nil; `activepills` → general; `integrations` → services; `shortcuts` → general, `.shortcuts`; `sidekick` → chat, `.sidekick`; `<page>/<tab>` with a valid page and one of its visible tabs (`chat/keys`, `chat/yourai`) → that place (Plan call, review finding 14: so the island's buttons can open a tab; `AppDelegate` writes the posted text into `settingsSection` as today and the shell migrates it); a valid page with an unknown tab (`chat/x`, `chat/companion` while hidden) → the page, tab nil; anything else (nil, empty, unknown, `Chat` with a capital) → general.
- `tab(for:stored:)`: the stored raw value when it is one of `tabs(page)`, else `tabs(page).first`.
- `sidebarMode`: `.icons` when `windowWidth < breakpoint`. `detailWidth` = `windowWidth - sidebarWidth(mode)`. `columnWidth` = `max(0, min(detailWidth - 2 * padding(mode), columnMax))`.
- `displayPath`: `home` itself → `~`; a path starting with `home + "/"` → `~` + the rest; anything else unchanged (an empty `home` changes nothing).
- `SettingsDraftBook`: `text` is the edited text, else the saved value, else `""`; `isDirty` is `text(id) != saved[id] ?? ""`; `isSaved` is a non-empty saved value; `markSaved` sets both the saved value and the text to `stored`.
- `slots`: `text` = `"\(active.count) of 4 slots used"`; `names` = the catalog names of the active ids, in catalog order (ids not in the catalog are counted but not named); `full` = `active.count >= 4`.
- `pillSwitch`: main → `(false, "Main", false)`; off and `activeCount >= 4` → `(true, capSentence, true)`; else `(true, missing, false)` (rule 10: a missing prerequisite never disables).
- `hookChip`: `needsUpdate` → `"Needs update"`; else `installed == true` → `"Installed"`; `false` → `"Not installed"`; `nil` → `nil`.
- `tone`: ok for `Ready`, `Installed`, `Saved`, `Main` and anything starting `Running`; warn for `Needs update`, `Not saved`, `Hooks not installed`, `Key not configured`, `Not connected`, `Update needed`, `capSentence`, anything starting `Off`; error for `Not ready`; neutral for everything else (`Not installed`, `Not signed in`, `No key yet`, `Server off`, `Coming with the new chat`, `Comes with F3a`). Plan call: one table so every chip of the same word has the same dot.
- `stuckSwitch`: n = muted among the four; n == 4 → `(false, nil)`; n == 0 → `(true, nil)`; else `(true, "\(4 - n) of 4")` (spec: mixed shows on with "3 of 4"; "on" means at least one still shows).
- `example`: a made-up Claude Code session (`agentId` `integration_claude`, project `my-app`) on a fixed clock (`now = 10_000_000` ms), never the real ledger. `stuck.*` → `SidekickStuck.text(SKNudge(kind:, reasonId: "example", key: <the session's key>, agentId: "integration_claude"), ledger, now: now)` with `pendingApprovalAt = now - 30_000` and `lastEventAt = now - 5 * SK.minute`; `recap` → the first line of `SidekickRecap.recap(awaySince: now - 10 * SK.minute, now: now, sessions: [the session])` with a ring of at least three tool calls on files (the implementer builds the session through `SKSession`'s initialiser as `tests/SidekickRecapTests.swift` does and tunes the ring until `recap` is non-nil).

- [ ] **Step 1: Write the failing test** `tests/SettingsRulesTests.swift` (`@main enum SettingsRulesTests`, `CT` from `tests/CatTestSupport.swift`). Cases with these exact values:
  ```swift
  // route
  CT.check("sidebar order", SettingsRoute.Page.allCases.map(\.rawValue), ["general", "agents", "chat", "services", "cat", "devices"])
  CT.check("titles", SettingsRoute.Page.allCases.map { SettingsRoute.title($0) }, ["General", "Agents", "AI and chat", "Services", "Cat", "Devices"])
  CT.check("chat tabs", SettingsRoute.tabs(.chat).map(\.rawValue), ["yourai", "keys", "localmodels", "sidekick"])
  CT.check("chat tabs with Companion", SettingsRoute.tabs(.chat, companion: true).count, 5)
  CT.check("Companion hidden for now", SettingsRoute.companionTabShown, false)
  CT.check("cat tab titles", SettingsRoute.tabs(.cat).map { SettingsRoute.title($0) }, ["Look", "Outfits", "Personality", "Agents' cats"])
  CT.checkTrue("no tabs on three pages", [.agents, .services, .devices].allSatisfy { SettingsRoute.tabs($0).isEmpty })
  CT.checkTrue("at most four tabs", SettingsRoute.Page.allCases.allSatisfy { SettingsRoute.tabs($0).count <= 4 })
  CT.check("tab key", SettingsRoute.tabKey(.cat), "settingsTab.cat")
  CT.check("AI icon", SettingsRoute.icon(.chat).symbol, "bubble.left.and.bubble.right.fill")
  let M = { SettingsRoute.migrate(storedSection: $0) }
  CT.check("activepills", M("activepills"), .init(page: .general))
  CT.check("integrations", M("integrations"), .init(page: .services))
  CT.check("shortcuts", M("shortcuts"), .init(page: .general, tab: .shortcuts))
  CT.check("sidekick", M("sidekick"), .init(page: .chat, tab: .sidekick))
  CT.check("chat kept", M("chat"), .init(page: .chat))
  CT.check("devices kept", M("devices"), .init(page: .devices))
  for bad in [nil, "", "Chat", "bogus", "yourai", "/keys", "nope/keys"] { CT.check("unknown \(bad ?? "nil")", M(bad), .init(page: .general)) }
  CT.check("page and tab", M("chat/keys"), .init(page: .chat, tab: .keys))
  CT.check("page and tab, Your AI", M("chat/yourai"), .init(page: .chat, tab: .yourAI))
  CT.check("a tab of another page", M("chat/look"), .init(page: .chat))
  CT.check("hidden Companion", M("chat/companion"), .init(page: .chat))
  CT.check("stored tab", SettingsRoute.tab(for: .cat, stored: "outfits"), .outfits)
  CT.check("another page's tab", SettingsRoute.tab(for: .cat, stored: "keys"), .look)
  CT.check("garbage tab", SettingsRoute.tab(for: .chat, stored: "x"), .yourAI)
  CT.check("hidden Companion is not restored", SettingsRoute.tab(for: .chat, stored: "companion"), .yourAI)
  CT.check("no tabs", SettingsRoute.tab(for: .agents, stored: "keys"), nil)
  // layout: the spec's widths
  let W: [Double] = [415, 559, 560, 599, 600, 720, 1100, 3000]
  CT.check("modes", W.map { SettingsLayout.sidebarMode(windowWidth: $0) }, [.icons, .icons, .icons, .icons, .expanded, .expanded, .expanded, .expanded])
  CT.check("columns", W.map { SettingsLayout.columnWidth(windowWidth: $0) }, [327, 471, 472, 511, 360, 480, 640, 640])
  CT.checkTrue("no window from 415 up has a column narrower than the 415 one", stride(from: 415.0, through: 3000, by: 1).allSatisfy { SettingsLayout.columnWidth(windowWidth: $0) >= 327 })
  CT.check("tiny window never negative", SettingsLayout.columnWidth(windowWidth: 40), 0)
  CT.check("min", [SettingsLayout.minWidth, SettingsLayout.minHeight], [415, 420])
  CT.check("tilde", SettingsLayout.displayPath("/Users/sam/.claude/settings.json", home: "/Users/sam"), "~/.claude/settings.json")
  CT.check("home itself", SettingsLayout.displayPath("/Users/sam", home: "/Users/sam"), "~")
  CT.check("a longer name is not home", SettingsLayout.displayPath("/Users/samuel/x", home: "/Users/sam"), "/Users/samuel/x")
  CT.check("empty home", SettingsLayout.displayPath("/a/b", home: ""), "/a/b")
  // drafts
  var d = SettingsDraftBook(saved: ["anthropic-api-key": "sk-old", "resend-from": ""])
  CT.check("seeded", d.text("anthropic-api-key"), "sk-old"); CT.checkTrue("clean", !d.isDirty("anthropic-api-key"))
  d.edit("anthropic-api-key", "sk-new"); CT.checkTrue("dirty after an edit", d.isDirty("anthropic-api-key"))
  CT.checkTrue("another field is untouched", !d.isDirty("resend-from") && !d.isSaved("resend-from"))
  d.edit("anthropic-api-key", "sk-old"); CT.checkTrue("typed back to the saved value is clean", !d.isDirty("anthropic-api-key"))
  d.edit("anthropic-api-key", " sk-new "); d.markSaved("anthropic-api-key", stored: "sk-new")
  CT.check("saved as written", d.text("anthropic-api-key"), "sk-new"); CT.checkTrue("clean after save", !d.isDirty("anthropic-api-key"))
  d.markSaved("anthropic-api-key", stored: ""); CT.checkTrue("removed", !d.isSaved("anthropic-api-key") && d.text("anthropic-api-key") == "")
  CT.check("an unknown field", d.text("nope"), "")
  // status
  let cat = [(id: "agent_antigravity", name: "Antigravity"), (id: "agent_codex", name: "Codex"), (id: "integration_resend", name: "Resend")]
  CT.check("slots", SettingsStatus.slots(active: ["agent_codex", "agent_antigravity"], catalog: cat), .init(text: "2 of 4 slots used", names: ["Antigravity", "Codex"], full: false))
  CT.check("full", SettingsStatus.slots(active: ["agent_codex", "agent_antigravity", "integration_resend", "ai_gone"], catalog: cat).full, true)
  CT.check("main", SettingsStatus.pillSwitch(isOn: false, isMain: true, activeCount: 4, missing: "Hooks not installed"), .init(showsSwitch: false, chip: "Main", disabled: false))
  CT.check("cap", SettingsStatus.pillSwitch(isOn: false, isMain: false, activeCount: 4, missing: nil), .init(showsSwitch: true, chip: "4 of 4 slots used. Turn another off.", disabled: true))
  CT.check("on at the cap can still turn off", SettingsStatus.pillSwitch(isOn: true, isMain: false, activeCount: 4, missing: nil).disabled, false)
  CT.check("missing never disables", SettingsStatus.pillSwitch(isOn: false, isMain: false, activeCount: 1, missing: "Hooks not installed"), .init(showsSwitch: true, chip: "Hooks not installed", disabled: false))
  CT.check("hook chips", [SettingsStatus.hookChip(installed: true, needsUpdate: true), SettingsStatus.hookChip(installed: true, needsUpdate: false), SettingsStatus.hookChip(installed: false, needsUpdate: false), SettingsStatus.hookChip(installed: nil, needsUpdate: false)], ["Needs update", "Installed", "Not installed", nil])
  CT.check("key chips", [SettingsStatus.keyChip(saved: true), SettingsStatus.keyChip(saved: false), SettingsStatus.serviceChip(saved: true)], ["Ready", "No key yet", "Saved"])
  CT.check("tones", ["Ready", "Running, 4 models", "Needs update", SettingsStatus.capSentence, "No key yet", "Not ready", "Coming with the new chat"].map { SettingsStatus.tone($0) }, [.ok, .ok, .warn, .warn, .neutral, .error, .neutral])
  // sidekick tab
  let none: (String) -> Bool = { _ in false }, all: (String) -> Bool = { $0.hasPrefix("stuck.") }, three: (String) -> Bool = { $0 != "stuck.loop" && $0.hasPrefix("stuck.") }
  CT.checkTrue("none muted", SettingsSidekick.stuckSwitch(isMuted: none) == (true, nil))
  CT.checkTrue("all muted", SettingsSidekick.stuckSwitch(isMuted: all) == (false, nil))
  CT.checkTrue("three muted", SettingsSidekick.stuckSwitch(isMuted: three) == (true, "1 of 4"))
  CT.check("stuck names", SettingsSidekick.stuckNames.map(\.label), ["Repeated steps", "Repeated errors", "Waiting for your OK", "Gone quiet"])
  CT.check("loop example", SettingsSidekick.example("stuck.loop"), "Claude Code has run the same step 4 times.")
  CT.check("errors example", SettingsSidekick.example("stuck.errors"), "Claude Code hit 3 errors in a row.")
  CT.check("waiting example", SettingsSidekick.example("stuck.waiting"), "Claude Code is still waiting for your OK.")
  CT.check("quiet example", SettingsSidekick.example("stuck.silent"), "Claude Code has been quiet for 5 minutes.")
  CT.checkTrue("recap example", SettingsSidekick.example("recap")?.hasPrefix("While you were away, Claude Code in my-app") == true)
  CT.checkTrue("no path in any example", (["recap"] + SettingsSidekick.stuckKinds).allSatisfy { !(SettingsSidekick.example($0) ?? "/").contains("/") })
  CT.check("no example for the permission line", SettingsSidekick.example("risk"), nil)
  CT.finish()
  ```
  (`stuckSwitch` returns a tuple: compare with `==` as written, not with `CT.check`, which needs `Equatable`.)
- [ ] **Step 2: Write `scripts/test-settings-rules.sh`** in the shape of `scripts/test-sidekick-settings.sh` (`set -euo pipefail`, `cd "$(dirname "$0")/.."`, `mktemp -d` with an `EXIT` trap, `export NM_LOG_DIR`). Compile list: the five new files, `$APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift` (the list of `scripts/test-sidekick-recap.sh`), then `tests/CatTestSupport.swift tests/SettingsRulesTests.swift`. Header: "Settings, the pure rules: pages, tabs and the old tags; the widths; the drafts; the status words; the Sidekick tab. Nothing here launches NotchMeow."
- [ ] **Step 3: Run it** → compile error (types missing).
- [ ] **Step 4: Implement** the five files (Foundation only; a header comment each naming the spec section; no clock, timer, `UserDefaults` or `KeychainStore`).
- [ ] **Step 5: Run** → `All tests passed.`
- [ ] **Step 6: CI.** In `.github/workflows/build.yml`, after the step `Settings → Agents install notes (what Confirm & write reports)`:
  ```yaml
      - name: Settings rules (pages, tabs, old tags, widths, drafts, status words, Sidekick tab)
        run: bash scripts/test-settings-rules.sh
  ```
- [ ] **Step 7: Commit** the seven files with `feat(settings): the pure rules of the restyled Settings (route, layout, drafts, status, Sidekick tab)`. (No `xcodegen` yet: Task 4's first build regenerates the project with every new file.)

---

### Task 3: Pure rules B: control map, AI rows, help colour

**Files:**
- Create: `NotchBuddy/Sources/App/SettingsMap.swift`, `SettingsAI.swift`, `SettingsColors.swift`, `tests/fixtures/settings/controls.json`, `tests/SettingsMapTests.swift`, `tests/SettingsAITests.swift`, `tests/SettingsContrastTests.swift`, `scripts/test-settings-map.sh`, `scripts/test-settings-ai.sh`, `scripts/test-settings-contrast.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `SettingsRoute` (Task 2); `AIProviderID`, `FeatureSetting`, `ModelRef`, `ServerStatus` (AI/Core, in every build). Not `ClaudeCodeStatus`: it is inside `#if !APPSTORE` (`ClaudeCodeLocator.swift` line 8), so `SettingsAI` has its own `ClaudeState` and `aiInput` (Task 11) maps to it inside the `#if`.
- Produces:
```swift
enum SettingsMap {
    struct Home: Equatable, Sendable { var page: SettingsRoute.Page; var tab: SettingsRoute.Tab?; var card: String }
    struct StoredKey: Equatable, Sendable { var key: String; var store: String }       // store: defaults | keychain | file
    struct Control: Equatable, Sendable { var id: String; var was: String; var homes: [Home]; var mac: [StoredKey] }
    static let controls: [Control]
    static func pillHome(_ pillId: String) -> SettingsRoute.Place      // workspace/agent → agents; ai_anthropic/google/openai → chat/keys; ai_ollama/lmstudio → chat/localModels; services → services
    static let serviceFields: [String: [String]]                      // pill id → its Keychain field ids, in card order
}
enum SettingsAI {
    enum Row: Hashable, Sendable { case claudePlan, openAIPlan, key(AIProviderID), server(String), apple }
    enum ClaudeState: Equatable, Sendable { case notInstalled, tooOld, signedOut, signedIn, unknown }   // ClaudeCodeStatus.State's cases, in every build
    struct Server: Equatable, Sendable { var id: String; var provider: AIProviderID; var name: String; var network: Bool; var models: [String] }
    struct Input: Equatable, Sendable {
        var githubBuild: Bool; var claudeState: ClaudeState; var claudeVersion: String?; var claudeSignIn: String
        var claudeEnabled: Bool; var claudeModel: String; var keys: Set<AIProviderID>; var cloudModel: [AIProviderID: String]
        var servers: [Server]; var memory: [String: String]; var appleReady: Bool
    }
    enum MakeMain: Equatable, Sendable { case set(FeatureSetting), menu([ModelRef]), unavailable(String) }
    static let planLine = "Runs your own installed app, signed in by you. NotchMeow never sees your login."
    static let coming = "Coming with the new chat"
    static let keyProviders: [AIProviderID] = [.anthropic, .google, .openai]
    static func rows(_ i: Input) -> [Row]
    static func title(_ r: Row, _ i: Input) -> String
    static func line(_ r: Row, _ i: Input) -> String
    static func chip(_ r: Row, _ i: Input) -> String
    static func makeMain(_ r: Row, _ i: Input) -> MakeMain
    static func isMain(_ r: Row, chat: FeatureSetting) -> Bool
    static func serverChip(_ s: ServerStatus) -> String
    static func getLink(_ p: AIProviderID) -> String?                 // today's LocalServerRow.getURLs
}
enum SettingsColors {   // import AppKit
    static let help: NSColor                                           // NSColor.labelColor.withAlphaComponent(0.72)
    static func contrast(_ fg: NSColor, over bg: NSColor, appearance: NSAppearance.Name) -> Double
}
```

The rules, exactly:
- **`controls.json`** has `version: 1`, a `note`, `pages` (each page with its title and tab raw values, from `SettingsRoute`) and `controls`, each `{id, was, homes: [{page, tab|null, card}], mac: [{key, store}]}`. `SettingsMap.controls` holds the same list in Swift; the test compares them field by field, so the JSON is the Windows plan's starting file. The controls, in this order (homes as `page/tab/card`; `…` = several homes as listed):

| id | homes | mac keys |
|---|---|---|
| `sound.enabled` | general/general/Sound | `soundEnabled` |
| `sound.volume` | general/general/Sound | `soundVolume` |
| `island.openOnHover` | general/general/Island | `openOnHover` |
| `island.hoverGlow` | general/general/Island | `island.hoverGlow` |
| `island.tuckAway` | general/general/Island | `island.tuckAway` |
| `island.closeAfter` | general/general/Island | `autoCloseInterval` |
| `startup.launch` | general/general/Startup | none |
| `pills.main` | general/general/On the island | `mainPill` |
| `pills.slots` | general/general/On the island | none (derived) |
| `pills.switches` | agents/–/On the island; chat/keys/Anthropic, Google AI, OpenAI; chat/localmodels/Local models; services/–/Resend, n8n, Vercel, GitHub, Stripe, Cal.com, Notion, Music | `activeIntegrations` |
| `hooks.claude` | agents/–/Claude Code hooks | file `~/.claude/notchmeow/nm-hook`, file `~/.claude/settings.json` |
| `hooks.gemini` | agents/–/Gemini CLI hooks | file `~/.gemini/settings.json` |
| `hooks.antigravity` | agents/–/Antigravity hooks | file `~/.gemini/config/hooks.json` |
| `hooks.codex` | agents/–/Codex hooks | file `~/.codex/hooks.json` |
| `plan.usage` | agents/–/Plan usage | `showPlanInNotch`, `claudePlanUsage`, file `~/.claude/settings.json` |
| `ai.claudePlan` | chat/yourai/Choose your AI | `aiClaudeCodeEnabled`, `aiClaudeCodeModel` |
| `ai.openAIPlan` | chat/yourai/Choose your AI | none |
| `ai.routing` | chat/yourai/Which one answers; chat/yourai/Choose your AI | `aiChoices`, `aiPreferredCloud` |
| `ai.key.anthropic` | chat/keys/Anthropic | keychain `anthropic-api-key`, `claudeModel` |
| `ai.key.google` | chat/keys/Google AI | keychain `google-api-key`, `googleChatModel` |
| `ai.key.openai` | chat/keys/OpenAI | keychain `openai-api-key`, `openAIChatModel` |
| `ai.local` | chat/localmodels/Local models | `aiCustomServers`, keychain `custom-server-key.<id>`, `aiLastUsedLocal`, `aiLocalModels` |
| `ai.apple` | chat/localmodels/Local models; chat/yourai/Choose your AI | none |
| `service.resend` | services/–/Resend | keychain `resend-api-key`, `resend-from` |
| `service.n8n` | services/–/n8n | keychain `n8n-url`, `n8n-api-key`; `n8nWorkflowFilter` |
| `service.vercel` | services/–/Vercel | keychain `vercel-token`; `vercelProjectFilter` |
| `service.github` | services/–/GitHub | keychain `github-token` |
| `service.stripe` | services/–/Stripe | keychain `stripe-api-key` |
| `service.calcom` | services/–/Cal.com | keychain `calcom-api-key` |
| `service.notion` | services/–/Notion | keychain `notion-api-key` |
| `service.music` | services/–/Music | none |
| `shortcuts.global` | general/shortcuts/Global shortcuts | `hotkeyEnabled`, `hotkeyFlags`, `hotkeyCode`, `shortcut.<id>.enabled`, `shortcut.<id>.keyCode`, `shortcut.<id>.flags` |
| `shortcuts.island` | general/shortcuts/In the island | none |
| `cat.main` | cat/look/Main cat | `cat.character` |
| `cat.look` | cat/look/Look | `cat.collar`, `cat.collar.<id>`, `cat.furLines` |
| `cat.desktop` | cat/look/Desktop | `cat.desktop.on`, `cat.desktop.size`, `cat.desktop.spots` |
| `cat.wardrobe` | cat/outfits/Wardrobe | `cat.outfit` |
| `cat.personality` | cat/personality/Personality | `cat.personality.<id>` |
| `cat.motion` | cat/personality/Motion | `cat.motionStyle`, `cat.motion.<id>` |
| `cat.everyCat` | cat/personality/Every cat | none |
| `cat.display` | cat/agentcats/Display; cat/agentcats/Your two cats; cat/agentcats/Cats for your agents | `cat.displayMode`, `cat.pair`, `cat.agentCat.<pillId>` |
| `sidekick.master` | chat/sidekick/Notes | `sidekick.on` |
| `sidekick.kinds` | chat/sidekick/Notes; chat/sidekick/Muted notes | `sidekick.dismissals` |
| `sidekick.example` | chat/sidekick/Notes | none |
| `sidekick.words` | chat/sidekick/Where its words come from | `sidekick.local` |
| `sidekick.quiet` | chat/sidekick/Quiet times | none |
| `sidekick.today` | chat/sidekick/Today so far | none |
| `devices.thisMac` | devices/–/This Mac | `link.visible`, `link.deviceName` |
| `devices.machines` | devices/–/Machines | keychain `link.peer.<id>`, `link.static-key`, `link.device-id` |
| `devices.received` | devices/–/Received files | none |
| `settings.selection` | general/–/(the shell) | `settingsSection`, `settingsTab.<page>` |

  `was` is the spec table's first column (for example `"General: Enable sounds"`, `"(new)"` for the new controls). Plan call: one control per stored setting group, with several homes when the same state shows in several places (the pill switches, the AI choice, the dismissals), so "each key under exactly one control" holds without splitting a key.
- **`pillHome`** decides by id alone (no `PillCatalog` import, so the test compiles without the app): `integration_claude` and any `agent_*` → agents; `ai_anthropic`, `ai_google`, `ai_openai` → chat/keys; `ai_ollama`, `ai_lmstudio` (and any other `ai_*`) → chat/localModels; any other `integration_*` → services; anything else → general.
- **`serviceFields`**: `integration_resend` → `["resend-api-key", "resend-from"]`; `integration_n8n` → `["n8n-url", "n8n-api-key"]`; `integration_vercel` → `["vercel-token"]`; `integration_github` → `["github-token"]`; `integration_stripe` → `["stripe-api-key"]`; `integration_calcom` → `["calcom-api-key"]`; `integration_notion` → `["notion-api-key"]`; `integration_music` → `[]`.
- **`SettingsAI.rows`**: `.claudePlan` and `.openAIPlan` only when `githubBuild`; then `.key(.anthropic)`, `.key(.google)`, `.key(.openai)`; then `.server(id)` for each server with models, in input order; then `.apple` when `appleReady`. No Google plan row (owner's answer 5).
- **`title`**: `Use my Claude plan`, `Use my OpenAI plan`, `Anthropic API key`, `Google AI API key`, `OpenAI API key`, the server's name, `Apple on-device`. **`line`**: the two plan rows → `planLine`; a key row → `Your own key, saved on the Keys tab.`; a server → `A model server on this Mac.` or, when `network`, `A model server on your network.`; Apple → `Apple's model, on this Mac.` (Plan call: the spec leaves the one-liners to the builder; reviewed in the pictures.)
- **`chip`**: Claude plan: `.signedIn` and enabled → `Ready`; `.signedIn` and not enabled → `Off`; `.signedOut` → `Not signed in`; `.notInstalled` → `Not installed`; `.tooOld` → `Needs update`; `.unknown` → `Not ready`. OpenAI plan → `coming`. Key → `SettingsStatus.keyChip(saved:)`. Server → `serverChip`. Apple → `Ready`.
- **`serverChip`**: `.running([])` → `Running, no models yet`; `.running(m)` → `Running, 1 model` / `Running, N models`; `.off` → `Server off`; `.notInstalled` → `Not installed`; `.outdated` → `Update needed`.
- **`makeMain`**: Claude plan ready (signed in and enabled) → `.set(.explicit(ModelRef(provider: .claudeCode, model: claudeModel)))`, else `.unavailable("Connect your Claude plan first.")`. OpenAI plan → `.unavailable("Coming with the new chat.")`. Key with a saved key and a non-empty `cloudModel[p]` → `.set(.explicit(ModelRef(provider: p, model: cloudModel[p]!)))`; no key → `.unavailable("Add a key on the Keys tab first.")`; a key but no model → `.unavailable("Pick a model for it in the chat first.")`. Server with one model → `.set(.explicit(ModelRef(provider: server.provider, model: m, serverID: server.id)))`; with more → `.menu` of all its models as `ModelRef`s, the remembered one (`memory[id]`, if it is among them) first, the rest in order (builder call 2). Apple → `.set(.explicit(ModelRef(provider: .apple, model: "system")))`.
- **`isMain`**: only an explicit Chat choice is main (Plan call: under Auto no row says Main; Which one answers already shows what Auto resolves to). `.claudePlan` ↔ provider `.claudeCode`; `.key(p)` ↔ provider `p` (any model); `.server(id)` ↔ `(ref.serverID ?? ref.provider.rawValue) == id` and the provider is neither cloud nor `.apple`; `.apple` ↔ provider `.apple`; `.openAIPlan` never (yet).
- **`getLink`**: `.ollama` `https://ollama.com/download`, `.lmstudio` `https://lmstudio.ai`, `.jan` `https://jan.ai`, `.llamacpp` `https://github.com/ggml-org/llama.cpp`, else nil.
- **`SettingsColors.contrast`**: both colours resolved in that appearance (`NSAppearance(named:)!.performAsCurrentDrawingAppearance`) to sRGB, the foreground's alpha blended over the background, then the WCAG ratio `(L1 + 0.05) / (L2 + 0.05)`.

- [ ] **Step 1: Write the failing map test** `tests/SettingsMapTests.swift`. It holds its own frozen list of today's keys, each with the literal that must appear in some `.swift` file under `NotchBuddy/Sources/App` (read with `FileManager.enumerator`, concatenated):
  ```swift
  static let frozen: [(key: String, store: String, literal: String)] = [
      ("soundEnabled", "defaults", "\"soundEnabled\""), ("soundVolume", "defaults", "\"soundVolume\""), ("openOnHover", "defaults", "\"openOnHover\""),
      ("island.hoverGlow", "defaults", "\"island.hoverGlow\""), ("island.tuckAway", "defaults", "\"island.tuckAway\""), ("autoCloseInterval", "defaults", "\"autoCloseInterval\""),
      ("hotkeyEnabled", "defaults", "\"hotkeyEnabled\""), ("hotkeyFlags", "defaults", "\"hotkeyFlags\""), ("hotkeyCode", "defaults", "\"hotkeyCode\""),
      ("mainPill", "defaults", "\"mainPill\""), ("activeIntegrations", "defaults", "\"activeIntegrations\""), ("showPlanInNotch", "defaults", "\"showPlanInNotch\""),
      ("claudePlanUsage", "defaults", "\"claudePlanUsage\""), ("aiClaudeCodeEnabled", "defaults", "\"aiClaudeCodeEnabled\""), ("aiClaudeCodeModel", "defaults", "\"aiClaudeCodeModel\""),
      ("aiChoices", "defaults", "\"aiChoices\""), ("aiPreferredCloud", "defaults", "\"aiPreferredCloud\""), ("claudeModel", "defaults", "\"claudeModel\""),
      ("googleChatModel", "defaults", "\"googleChatModel\""), ("openAIChatModel", "defaults", "\"openAIChatModel\""), ("aiCustomServers", "defaults", "\"aiCustomServers\""),
      ("aiLastUsedLocal", "defaults", "\"aiLastUsedLocal\""), ("aiLocalModels", "defaults", "\"aiLocalModels\""), ("n8nWorkflowFilter", "defaults", "\"n8nWorkflowFilter\""),
      ("vercelProjectFilter", "defaults", "\"vercelProjectFilter\""),
      ("shortcut.<id>.enabled", "defaults", "\"shortcut.\\(rawValue).enabled\""), ("shortcut.<id>.keyCode", "defaults", "\"shortcut.\\(rawValue).keyCode\""), ("shortcut.<id>.flags", "defaults", "\"shortcut.\\(rawValue).flags\""),
      ("cat.character", "defaults", "\"cat.character\""), ("cat.motionStyle", "defaults", "\"cat.motionStyle\""), ("cat.furLines", "defaults", "\"cat.furLines\""), ("cat.collar", "defaults", "\"cat.collar\""),
      ("cat.motion.<id>", "defaults", "\"cat.motion.\\(id)\""), ("cat.collar.<id>", "defaults", "\"cat.collar.\\(id)\""), ("cat.personality.<id>", "defaults", "\"cat.personality.\\(id)\""),
      ("cat.displayMode", "defaults", "\"cat.displayMode\""), ("cat.pair", "defaults", "\"cat.pair\""), ("cat.agentCat.<pillId>", "defaults", "\"cat.agentCat.\""),
      ("cat.desktop.on", "defaults", "\"cat.desktop.on\""), ("cat.desktop.size", "defaults", "\"cat.desktop.size\""), ("cat.desktop.spots", "defaults", "\"cat.desktop.spots\""), ("cat.outfit", "defaults", "\"cat.outfit\""),
      ("sidekick.on", "defaults", "\"sidekick.on\""), ("sidekick.local", "defaults", "\"sidekick.local\""), ("sidekick.dismissals", "defaults", "\"sidekick.dismissals\""),
      ("link.visible", "defaults", "\"link.visible\""), ("link.deviceName", "defaults", "\"link.deviceName\""), ("settingsSection", "defaults", "\"settingsSection\""),
      ("anthropic-api-key", "keychain", "\"anthropic-api-key\""), ("google-api-key", "keychain", "\"google-api-key\""), ("openai-api-key", "keychain", "\"openai-api-key\""),
      ("resend-api-key", "keychain", "\"resend-api-key\""), ("resend-from", "keychain", "\"resend-from\""), ("n8n-url", "keychain", "\"n8n-url\""), ("n8n-api-key", "keychain", "\"n8n-api-key\""),
      ("vercel-token", "keychain", "\"vercel-token\""), ("github-token", "keychain", "\"github-token\""), ("stripe-api-key", "keychain", "\"stripe-api-key\""),
      ("calcom-api-key", "keychain", "\"calcom-api-key\""), ("notion-api-key", "keychain", "\"notion-api-key\""), ("custom-server-key.<id>", "keychain", "\"custom-server-key.\\(id)\""),
      ("link.peer.<id>", "keychain", "\"link.peer."), ("link.static-key", "keychain", "\"link.static-key\""), ("link.device-id", "keychain", "\"link.device-id\""),
  ]
  static let new: Set<String> = ["settingsTab.<page>"]
  ```
  Sections: (1) `controls.json` equals `SettingsMap.controls` (same ids in order, same homes, same keys); (2) every frozen key appears under exactly one control with the same `store`; (3) every key in the map is frozen, new, or a `file` entry; (4) every frozen literal is found in the app's sources (`✗ <key>: <literal> not found` otherwise); (5) every home's page is a `SettingsRoute.Page`, its tab is one of `SettingsRoute.tabs(page, companion: true)` or nil for a page without tabs, and a page with tabs never has a nil tab (except `settings.selection`); (6) every page has at most 4 tabs (5 with Companion); (7) `pillHome` for every id in `PillCatalog.all`'s literal list (`integration_claude`, `agent_cursor`, `agent_antigravity`, `agent_codex`, `agent_gemini`, `ai_anthropic`, `ai_google`, `ai_openai`, `ai_ollama`, `ai_lmstudio`, the eight `integration_*` services) gives the page above; (8) `serviceFields` keys are the eight service pill ids and every field id is a frozen keychain key under its own `service.*` control.
- [ ] **Step 2: Write the failing AI test** `tests/SettingsAITests.swift`. A base input `I` (`githubBuild: true`, `claudeState: .signedIn`, `claudeVersion: "2.1.289"`, `claudeSignIn: "your Claude plan"`, `claudeEnabled: true`, `claudeModel: "sonnet"`, `keys: [.anthropic]`, `cloudModel: [.anthropic: "claude-sonnet-5-5", .openai: "gpt-6.1-sol"]`, `servers: [S("ollama", .ollama, "Ollama", false, ["qwen3.5:2b", "llama4"]), S("custom-ab12", .custom, "Studio PC", true, ["big"])]`, `memory: ["ollama": "llama4"]`, `appleReady: true`). Cases:
  ```swift
  CT.check("rows", SettingsAI.rows(I), [.claudePlan, .openAIPlan, .key(.anthropic), .key(.google), .key(.openai), .server("ollama"), .server("custom-ab12"), .apple])
  var store = I; store.githubBuild = false
  CT.check("App Store: no plan rows", SettingsAI.rows(store).first, .key(.anthropic))
  CT.checkTrue("no Google plan row (owner's answer 5)", !SettingsAI.rows(I).map { SettingsAI.title($0, I) }.contains { $0.contains("Google plan") })
  CT.check("titles", [SettingsAI.title(.claudePlan, I), SettingsAI.title(.openAIPlan, I), SettingsAI.title(.key(.google), I)], ["Use my Claude plan", "Use my OpenAI plan", "Google AI API key"])
  CT.check("plan line", SettingsAI.line(.openAIPlan, I), "Runs your own installed app, signed in by you. NotchMeow never sees your login.")
  CT.check("network line", SettingsAI.line(.server("custom-ab12"), I), "A model server on your network.")
  CT.check("chips", [.claudePlan, .openAIPlan, .key(.anthropic), .key(.openai), .server("ollama"), .apple].map { SettingsAI.chip($0, I) }, ["Ready", "Coming with the new chat", "Ready", "No key yet", "Running, 2 models", "Ready"])
  var off = I; off.claudeEnabled = false
  CT.check("Claude off", SettingsAI.chip(.claudePlan, off), "Off")
  for (st, word) in [(SettingsAI.ClaudeState.signedOut, "Not signed in"), (.notInstalled, "Not installed"), (.tooOld, "Needs update"), (.unknown, "Not ready")] { var x = I; x.claudeState = st; CT.check("Claude \(word)", SettingsAI.chip(.claudePlan, x), word) }
  CT.check("server chips", [SettingsAI.serverChip(.running([])), SettingsAI.serverChip(.off), SettingsAI.serverChip(.notInstalled), SettingsAI.serverChip(.outdated)], ["Running, no models yet", "Server off", "Not installed", "Update needed"])
  CT.check("Make main Claude", SettingsAI.makeMain(.claudePlan, I), .set(.explicit(ModelRef(provider: .claudeCode, model: "sonnet"))))
  CT.check("Make main Claude off", SettingsAI.makeMain(.claudePlan, off), .unavailable("Connect your Claude plan first."))
  CT.check("Make main OpenAI plan", SettingsAI.makeMain(.openAIPlan, I), .unavailable("Coming with the new chat."))
  CT.check("Make main key", SettingsAI.makeMain(.key(.anthropic), I), .set(.explicit(ModelRef(provider: .anthropic, model: "claude-sonnet-5-5"))))
  CT.check("Make main no key", SettingsAI.makeMain(.key(.openai), I), .unavailable("Add a key on the Keys tab first."))
  var g = I; g.keys = [.google]
  CT.check("Make main key without a model", SettingsAI.makeMain(.key(.google), g), .unavailable("Pick a model for it in the chat first."))
  CT.check("Make main server menu, remembered first", SettingsAI.makeMain(.server("ollama"), I), .menu([ModelRef(provider: .ollama, model: "llama4", serverID: "ollama"), ModelRef(provider: .ollama, model: "qwen3.5:2b", serverID: "ollama")]))
  CT.check("Make main one model", SettingsAI.makeMain(.server("custom-ab12"), I), .set(.explicit(ModelRef(provider: .custom, model: "big", serverID: "custom-ab12"))))
  CT.check("Make main Apple", SettingsAI.makeMain(.apple, I), .set(.explicit(ModelRef(provider: .apple, model: "system"))))
  CT.checkTrue("Auto: nothing is main", SettingsAI.rows(I).allSatisfy { !SettingsAI.isMain($0, chat: .auto) })
  let ollama = FeatureSetting.explicit(ModelRef(provider: .ollama, model: "qwen3.5:2b"))
  CT.check("main follows the choice", SettingsAI.rows(I).filter { SettingsAI.isMain($0, chat: ollama) }, [.server("ollama")])
  CT.check("any Anthropic model is the Anthropic row", SettingsAI.rows(I).filter { SettingsAI.isMain($0, chat: .explicit(ModelRef(provider: .anthropic, model: "claude-opus-5-5"))) }, [.key(.anthropic)])
  CT.check("get link", [SettingsAI.getLink(.ollama), SettingsAI.getLink(.anthropic)], ["https://ollama.com/download", nil])
  ```
- [ ] **Step 3: Write the failing contrast test** `tests/SettingsContrastTests.swift`: for `.aqua` and `.darkAqua`, `SettingsColors.contrast(SettingsColors.help, over: .windowBackgroundColor, …) >= 4.5` and the same over `.controlBackgroundColor`; print (not assert) `.secondaryLabelColor`'s ratio over `.windowBackgroundColor` in dark as an information line. Plan call: a `GroupBox`'s own fill is a translucent material that cannot be resolved offscreen, so the check uses the two system backgrounds a card sits on, and checkpoint 1's pictures show the real card.
- [ ] **Step 4: The three scripts**, each in the shape of `scripts/test-settings-rules.sh`: `test-settings-map.sh` compiles `SettingsRoute.swift SettingsMap.swift tests/CatTestSupport.swift tests/SettingsMapTests.swift`; `test-settings-ai.sh` compiles `NotchBuddy/Sources/App/AI/Core/*.swift NotchBuddy/Sources/App/AppLog.swift SettingsStatus.swift SettingsAI.swift tests/CatTestSupport.swift tests/SettingsAITests.swift`; `test-settings-contrast.sh` compiles `SettingsColors.swift tests/CatTestSupport.swift tests/SettingsContrastTests.swift`. Run each → compile errors.
- [ ] **Step 5: Implement** `SettingsMap.swift` (Foundation; the table above, `pillHome`, `serviceFields`), `controls.json` (2-space indent, keys in the order `id, was, homes, mac`), `SettingsAI.swift` (Foundation; uses AI/Core types only), `SettingsColors.swift` (`import AppKit` only).
- [ ] **Step 6: Run** the three scripts → `All tests passed.` each.
- [ ] **Step 7: CI.** After the Task 2 step add three steps: `Settings control map (every stored key has one home and keeps its name)` → `bash scripts/test-settings-map.sh`; `Settings AI rows and Make main` → `bash scripts/test-settings-ai.sh`; `Settings help text contrast (4.5:1 in light and dark)` → `bash scripts/test-settings-contrast.sh`.
- [ ] **Step 8: Commit** the eleven files with `feat(settings): the control map, the AI rows and Make main, the help colour`.

---

### Task 4: The kit, the render frame, the privacy and kit pins

**Agent:** `nm-implementer-deep` (Sonnet 5.5, trigger 1). Read the spec's "The layout kit" and "Page rules" first.

**Files:**
- Create: the twelve kit files (File Structure), `scripts/render-settings.sh`, `scripts/render-settings.swift`, `scripts/check-settings-render-private.sh`, `tests/SettingsWiringTests.swift`, `scripts/test-settings-wiring.sh`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (xcodegen), `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `SettingsRoute`, `SettingsLayout`, `SettingsStatus.tone`, `SettingsColors.help`; existing `SettingsSidebarRow`, `SidebarBackground` (bottom of `SettingsView.swift`).
- Produces (later tasks use these exact signatures):
```swift
extension EnvironmentValues { var settingsMode: SettingsLayout.SidebarMode }        // set by SettingsShell
struct SettingsShell<Detail: View>: View {
    init(version: String, icon: NSImage?, page: Binding<SettingsRoute.Page>, scrolls: Bool = true,
         @ViewBuilder detail: @escaping (SettingsRoute.Page) -> Detail)
}
struct SettingsPage<Content: View>: View {
    init(page: SettingsRoute.Page, tab: Binding<SettingsRoute.Tab?>, banner: String? = nil, dismissBanner: @escaping () -> Void = {},
         scrolls: Bool = true, @ViewBuilder content: @escaping () -> Content)
}
struct SettingsCard<Content: View>: View { init(_ title: String, summary: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) }
struct SettingRow<Control: View>: View { init(_ label: String, help: String? = nil, @ViewBuilder control: () -> Control) }
struct SwitchRow: View { init(_ label: String, help: String? = nil, isOn: Binding<Bool>, chip: String? = nil, disabled: Bool = false) }
struct KeyRow: View {
    init(_ placeholder: String, text: Binding<String>, saved: Bool, dirty: Bool, works: Bool? = nil, secure: Bool = true,
         save: (() -> Void)? = nil, remove: (() -> Void)? = nil)
}
struct StatusChip: View { init(_ text: String) }                                  // dot colour from SettingsStatus.tone
struct WrapRow<Content: View>: View { init(spacing: CGFloat = 8, lineSpacing: CGFloat = 6, @ViewBuilder content: () -> Content) }
struct PathDisclosure: View { init(path: String, copy: @escaping (String) -> Void, reveal: (() -> Void)? = nil) }
struct HelpText: View { init(_ text: String) }
struct SettingsTabBar: View { init(tabs: [SettingsRoute.Tab], selection: Binding<SettingsRoute.Tab?>) }
struct SettingsBanner: View { init(_ text: String, dismiss: @escaping () -> Void) }
```

What each one does (the spec's kit; the numbers are `SettingsLayout`'s):
- **`SettingsShell`**: a `GeometryReader` gives the window width → `SettingsLayout.sidebarMode`; sidebar at `sidebarWidth(mode)` on `SidebarBackground`: header (icon 32 pt, "NotchMeow", version; icons mode: the icon only), then the six `SettingsRoute.Page.allCases` rows as `SettingsSidebarRow` with `title`/`icon` from `SettingsRoute` (icons mode: the tile only, `.help(title)`, `.accessibilityLabel(title)`); a 1 pt divider overlay at the sidebar's trailing edge; the detail gets the rest. Sets `.environment(\.settingsMode, mode)`. `.frame(minWidth: SettingsLayout.minWidth, minHeight: SettingsLayout.minHeight)`. `icon == nil` draws a rounded grey tile (the render tool has no app icon). Selection by `List(selection:)` as today.
- **`SettingsPage`**: the title (`.title2`, semibold), then `SettingsTabBar` when `SettingsRoute.tabs(page)` is not empty, then `SettingsBanner` when `banner` is non-empty (the title, the tab bar and the banner stay above the scroll area, so a result is seen whatever the scroll position; review finding 9), then the content in a `VStack(spacing: 18)` of width `columnWidth`, centred in the detail, inside a `ScrollView` when `scrolls`. Padding `SettingsLayout.padding(mode)`.
- **`SettingsCard`**: a `GroupBox` whose label is the title and, when `summary` is set, a `StatusChip` on the right (a `ViewThatFits`: title and chip on one line, else the chip under the title); `footer` as `HelpText` at the bottom; content `.frame(maxWidth: .infinity, alignment: .leading)`, padding 6.
- **`SettingRow`**: `ViewThatFits(in: .horizontal)` of (A) an `HStack` with the label `.fixedSize()`, a `Spacer(minLength: 12)` and the control; (B) a `VStack(alignment: .leading)` with the label wrapping between words (`.fixedSize(horizontal: false, vertical: true)`) and the control at full width. Help text (`HelpText`) under either. Rule 1 by construction: a label is never squeezed; when it does not fit on one line beside its control the row stacks.
- **`SwitchRow`**: a `SettingRow` whose control is a `Toggle("", isOn:)` `.labelsHidden()` `.toggleStyle(.switch)`, with the chip (`StatusChip`) before the switch in (A) and under the label in (B); the label is a `Button` that flips the binding (not when `disabled`); `disabled` disables both.
- **`KeyRow`**: a `SecureField` (or `TextField` when `!secure`) `.textFieldStyle(.roundedBorder)` `.frame(maxWidth: SettingsLayout.fieldMax)`, then in a `WrapRow`: Save (`.borderedProminent`, only when `save != nil`), the ✓/✗ mark exactly as today's `keyMark` (green `#22C55E` `checkmark.circle.fill` "Key works" / red `xmark.circle.fill` "Key rejected"), `StatusChip("Not saved")` when `dirty`, and Remove (`.bordered`, only when `saved && remove != nil`).
- **`StatusChip`**: a 7 pt dot (ok `#22C55E`, warn `.orange`, error `.red`, neutral `.secondary`) and the text at 11 pt, `.fixedSize()`, never `lineLimit`; inside rows it sits in `ViewThatFits` so it moves to its own line before it would truncate.
- **`WrapRow`**: a custom `Layout` (flow): places children left to right with `spacing`, starts a new line with `lineSpacing` when the next child would pass the proposed width; each child is measured at its ideal size (callers mark buttons `.fixedSize()`, and `WrapRow` applies `.fixedSize()` to each child itself so a button can never truncate).
- **`PathDisclosure`**: a "Show path" / "Hide path" `.bordered` small button; open shows the path in 11 pt monospaced, `.textSelection(.enabled)`, wrapping (never truncating), and a `WrapRow` with Copy (calls `copy(path)`) and, when `reveal != nil`, Show in Finder. Starts closed. `path` is already the display form (callers use `SettingsLayout.displayPath`).
- **`HelpText`**: 12 pt (`SettingsLayout.helpSize`), `Color(nsColor: SettingsColors.help)`, `.fixedSize(horizontal: false, vertical: true)`, no line limit.
- **`SettingsTabBar`**: `ViewThatFits(in: .horizontal)` of (A) an `HStack` of text buttons, one per tab (`SettingsRoute.title`), each `.fixedSize()`, the selected one in the accent colour with a 2 pt underline, row height `SettingsLayout.tabBarHeight`; (B) a `Menu` labelled with the current tab's title listing every tab. Never a segmented control, never shortened labels, never a scroll (builder call 8).
- **`SettingsBanner`**: the text wrapping (12 pt), red when it starts with `❌`, `.secondary` otherwise, on a rounded card-coloured background (`Color(nsColor: .controlBackgroundColor)`), with an `xmark` button that calls `dismiss` (`.accessibilityLabel("Dismiss")`). Today's message texts are passed unchanged.

**The render frame.** `scripts/render-settings.sh` is `scripts/render-link.sh`'s shape: compile every `NotchBuddy/Sources/App/*.swift` (recursively, `find … -name '*.swift' ! -name NotchBuddyApp.swift`) with `scripts/render-settings.swift`, `-swift-version 6 -suppress-warnings`, defines `-D DEBUG`, or `-D APPSTORE` when `--appstore` is among the arguments; run through `scripts/render-home-guard.sh` in a home folder of its own; delete the `render-settings` defaults domain and plist on exit. Header comment: what it draws, the options, "about two minutes (the whole app is compiled); nothing is launched; no Keychain item, real path or user name is read". Plan call: the whole app is compiled (as `render-link.sh` does) because the page views use the app's value types (`HookNote`, `DiscoveredServer`, `LinkDirectory.Row`, `CatSettingsStore`, `CardBackground`); the page views still take plain values only, which the privacy check pins.

`scripts/render-settings.swift`:
- Options: `--out DIR` (default `${TMPDIR}/settings-render`, created), `--page P`, `--tab T`, `--width W` (default all of 415, 720, 1100), `--light` (default dark), `--appstore` (only marks file names; the build define does the rest), `--stress`, `--states empty|ready|error` (default `ready`), `--kit`. Unknown option → usage on stderr, exit 2.
- `Shot.save(view:width:scheme:url)`: an `NSHostingView` in a borderless `NSWindow` never shown, `appearance` `.darkAqua` or `.aqua`, height from `NSHostingController(rootView:).sizeThatFits(in: CGSize(width: W, height: 100_000))`, `cacheDisplay`, flattened on the window background colour of that appearance (render-cat-settings' fill step), written as PNG, `print("wrote \(path)")`.
- `--kit`: one PNG per width (415, 720) of a column made of every kit piece: two cards, a `SettingRow` with a short and a long label, `SwitchRow`s with and without chips (one with `SettingsStatus.capSentence`, disabled), a `KeyRow` dirty with a ✗, `WrapRow` of five buttons ("Install hooks", "Uninstall", "Confirm & write", "Cancel", "Show in Finder"), a `PathDisclosure` opened, `HelpText` of three sentences, `StatusChip`s for every tone, a `SettingsTabBar` for the AI page, a `SettingsBanner` error.
- Pages: the shell (`scrolls: false`) at each width with `SettingsPage` for each page and tab (or the one asked), content from `enum SettingsSamples { static func page(_ p: SettingsRoute.Page, tab: SettingsRoute.Tab?, state: String, stress: Bool) -> AnyView }`. In this task every case returns a placeholder `SettingsCard("Sample")` with a `HelpText`; Tasks 5 to 8 replace the cases. File names `<page>[-<tab>]-<width>-<dark|light>[-appstore][-stress][-<state>].png` (state omitted when `ready`).
- After the pages, a contact sheet `sheet-<dark|light>[-appstore][-stress][-<state>].png`: every picture drawn this run at 0.35 scale, four across, each captioned with its file name (CoreGraphics + `NSAttributedString` drawing). Last line `drew N pictures`.
- Fake values only: no `KeychainStore`, `AppState`, `HookServer`, `AIService`, `LinkService`, `UserDefaults` write, `NSHomeDirectory`, `NSUserName`, `Host`, `ProcessInfo` in this file.

`scripts/check-settings-render-private.sh` (shape of `scripts/check-link-render-private.sh`, same `check` helper and `HOSTREAD` pattern):
- the render tool (`render-settings.swift`, `.sh`, comment lines excluded) reads no host name, user or environment, and names none of `KeychainStore`, `AppState`, `HookServer`, `AIService.shared`, `LinkService.shared`, `SMAppService`;
- the kit files and the page files (`ls NotchBuddy/Sources/App/Settings{Shell,Page,Card,TabBar,Banner,GeneralPage,AgentsPage,ServicesPage,AIPage}.swift NotchBuddy/Sources/App/{SettingRow,SwitchRow,KeyRow,StatusChip,WrapRow,PathDisclosure,HelpText}.swift 2>/dev/null`) name none of `AppState`, `KeychainStore`, `UserDefaults`, `NSHomeDirectory`, `homeDirectoryForCurrentUser`, `NSUserName`, `HookServer`, `AIService.shared`, `LinkService.shared`;
- no real person or device name (`grep -nwiE 'ike|lorenz|tazan'` and `grep -niE 'raill'`) in those files and the render tool.
Ends `All tests passed.` or `1 test(s) failed.` with exit 1.

`tests/SettingsWiringTests.swift` (shape of `tests/IslandTuckAwayWiringTests.swift`: `source(_:)`, `count(_:in:)`, `at(_:in:)`), grown by later tasks above the line `// @@WIRING-SECTIONS`. This task's section, "the kit":
- `WrapRow.swift` contains `: Layout` and `.fixedSize()`; `StatusChip.swift` contains `.fixedSize()` and no `lineLimit`; `HelpText.swift` contains `SettingsColors.help` and `SettingsLayout.helpSize` and no `lineLimit`; `SettingRow.swift` contains `ViewThatFits`.
- `SettingsTabBar.swift` contains `ViewThatFits` and `Menu` and no `.segmented`; no kit file contains `.pickerStyle(.segmented)`, `NavigationSplitView`, `Timer`, `asyncAfter`, `DispatchSource`, `onReceive`.
- `SettingsShell.swift` contains `SettingsLayout.sidebarMode(windowWidth:` and `SettingsLayout.minWidth`.
`scripts/test-settings-wiring.sh` compiles `tests/CatTestSupport.swift tests/SettingsWiringTests.swift` and runs it (shape of `scripts/test-island-tuck-away-wiring.sh`).

- [ ] **Step 1: Write the pins** (`tests/SettingsWiringTests.swift`, `scripts/test-settings-wiring.sh`, `scripts/check-settings-render-private.sh`); run both → the kit pins fail (files missing); the privacy check passes on nothing.
- [ ] **Step 2: Implement** the twelve kit files (`import SwiftUI`, plus `AppKit` where `NSImage`/`NSColor` are used). No `#if` in the kit.
- [ ] **Step 3: Build.** `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet` → `BUILD SUCCEEDED`, and the App Store target `xcodebuild -scheme NotchMeowAppStore -configuration Debug -derivedDataPath build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet` → `BUILD SUCCEEDED` (the rule files of Tasks 2 and 3 are compiled into it here for the first time). Run `bash scripts/test-settings-wiring.sh` and `bash scripts/check-settings-render-private.sh` → all pass.
- [ ] **Step 4: The render frame.** Write `scripts/render-settings.sh` (`chmod +x`) and `scripts/render-settings.swift`. Run `bash scripts/render-settings.sh --kit --out "${TMPDIR:-/tmp}/settings-kit"` → `wrote …kit-415-dark.png`, `wrote …kit-720-dark.png`, `drew 2 pictures` (plus the sheet). Then `bash scripts/render-settings.sh --page general --out "${TMPDIR:-/tmp}/settings-shell"` and `--light`. Open the PNGs and check by eye: at 415 the sidebar is icons only and every button label is whole; the five-button row wraps; the chip with the cap sentence is whole; the tab bar shows four text tabs at 720 and a menu if they do not fit; light and dark both readable. A blank or broken image (system controls missing) is a failed step: then position the window at `(-20000, -20000)` and `orderFrontRegardless()` before `cacheDisplay` (never on screen), and say so in the ledger.
- [ ] **Step 5: CI.** After Task 3's steps: `Settings wiring (source pins of the kit, the pages and the app side)` → `bash scripts/test-settings-wiring.sh`; `Settings pictures stay private (no real name, path or key)` → `bash scripts/check-settings-render-private.sh`.
- [ ] **Step 6: Commit** the kit, the scripts, the tests, `project.pbxproj` and `build.yml` with `feat(settings): the layout kit and the render frame`.

---

### Task 5: Pages: General (General, Shortcuts) and Devices

**Files:**
- Create: `NotchBuddy/Sources/App/SettingsGeneralPage.swift`
- Modify: `NotchBuddy/Sources/App/ShortcutsSettingsView.swift`, `NotchBuddy/Sources/App/LinkViews.swift` (only `DevicesSettingsView`), `scripts/render-settings.swift`, `tests/SettingsWiringTests.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: the kit (Task 4); `SettingsStatus.Slots`, `SettingsRoute.Place` (Task 2); `IslandTuckAway.Choice` (existing).
- Produces:
```swift
struct GeneralSettingsModel {
    var soundEnabled: Binding<Bool>
    var soundVolume: Binding<Double>                 // 0...0.2, shown as 0–100 %
    var openOnHover: Binding<Bool>
    var focusAware: Binding<Bool>? = nil             // [focus]: only once focus awareness is merged
    var hoverGlow: Binding<Bool>
    var tuckAway: Binding<IslandTuckAway.Choice>
    var closeAfter: Binding<TimeInterval>
    var mainPill: Binding<String>
    var mainChoices: [(id: String, name: String)]
    var slots: SettingsStatus.Slots
    var slotLinks: [(name: String, place: SettingsRoute.Place)]
    var launchAtStartup: Binding<Bool>
    var open: (SettingsRoute.Place) -> Void
}
struct GeneralSettingsTab: View { let model: GeneralSettingsModel }
```
`ShortcutsSettingsView()` keeps its no-argument init. `DevicesSettingsView` keeps its init exactly (the render-link script calls it).

The General tab, four cards in this order (spec "General tab"):
- `SettingsCard("Sound")`: `SwitchRow("Enable sounds", isOn:)`; `SettingRow("Volume")` with the slider (disabled when sounds are off) and the `NN %` text, as today.
- `SettingsCard("Island")`: `SwitchRow("Open on hover", help: <today's .help text>)`; **[focus]** `SwitchRow("Step back when I'm already in the app", help: <focus plan's help text>)` right after it, only when `focusAware != nil`; `SwitchRow("Hover glow", help: <today's>)`; `SettingRow("Tuck the island away", help: <today's>)` with the menu picker (Never, After 1, 5, 15, 30 min) at `pickerWidth`; `SettingRow("Close after")` with a 64 pt number field and the word `seconds` (spec: the row that broke).
- `SettingsCard("On the island")`: `SettingRow("Main pill")` with the picker of `mainChoices`; a line `StatusChip`-free text `slots.text` in amber (`.orange`) when `slots.full`, else primary; the names as link buttons (`.link` style), one per `slotLinks` entry, in a `WrapRow`, each calling `open(place)`; `HelpText("Each pill's switch is on the Agents, AI and chat and Services pages.")`.
- `SettingsCard("Startup")`: `SwitchRow("Launch at Mac startup", isOn:)`.
No Hotkey card (call 1: the shortcut is the first row of the Shortcuts tab).

The Shortcuts tab: `ShortcutsSettingsView` keeps its logic; its two `GroupBox`es become `SettingsCard("Global shortcuts")` and `SettingsCard("In the island")`; its grey notes become `HelpText`; each action row is a `SettingRow(action.displayName)` whose control is the switch, the recorder and the conflict tags in a `WrapRow`; Turn all on and Reset to defaults in a `WrapRow`; the island's list is a two-column row (keys 90 pt, action) while `settingsMode == .expanded` and stacks (keys above action) in `.icons`. No logic, key or `HotKeyCenter` call changes.

Devices: `DevicesSettingsView`'s three `GroupBox`es become `SettingsCard("This Mac")`, `SettingsCard("Machines")`, `SettingsCard("Received files")`; every grey note becomes `HelpText` (the orange ones keep `.orange`); "Visible on this network" a `SwitchRow`; the Name field `.frame(maxWidth: SettingsLayout.fieldMax)` in a `SettingRow("Name")`; each machine row: the dot, the name (wrapping, no fixed 190 pt), a `StatusChip` with "Paired", "Paired, not seen" or "Available", and its buttons in a `WrapRow` ("Pair"; "Forget"; or "Forget \(row.name)?" in red and "Keep"). Every closure call and the `.onAppear` stay; `DevicesSettingsSection` is unchanged.

- [ ] **Step 1: Pins** (append a section "General, Shortcuts and Devices" to `tests/SettingsWiringTests.swift`): `SettingsGeneralPage.swift` contains `SettingsCard("Sound")`, `SettingsCard("Island")`, `SettingsCard("On the island")`, `SettingsCard("Startup")` in that order, `SwitchRow("Hover glow", help:` and `isOn: model.hoverGlow`, `SettingRow("Tuck the island away"`, `.tag(IslandTuckAway.Choice.never)`, `.tag(IslandTuckAway.Choice.m30)`, `SettingRow("Close after")`, `"seconds"`, and no `Hotkey` and no `ShortcutRecorderButton`; `ShortcutsSettingsView.swift` contains `SettingsCard("Global shortcuts")` and `SettingsCard("In the island")` and no `GroupBox`; `LinkViews.swift`'s `DevicesSettingsView` (text between `struct DevicesSettingsView` and `struct DevicesSettingsSection`) contains the three `SettingsCard(` titles, `Button("Forget \(row.name)?")` and `Button("Keep")` inside a `WrapRow`, and no `GroupBox`. Run → fail.
- [ ] **Step 2: Implement** `SettingsGeneralPage.swift`, the Shortcuts restyle and the Devices restyle.
- [ ] **Step 3: Samples.** In `render-settings.swift`, `SettingsSamples.page(.general, tab: .general, …)` builds a `GeneralSettingsModel` from `.constant` bindings: sounds on at 0.12, Open on hover off, Hover glow on, Tuck away `.m15`, Close after 15, main pill `integration_claude` among Claude Code, Cursor, Antigravity, Codex; `ready`: slots of Antigravity and Codex; `empty`: no active pill; `error` and `--stress`: four active (Antigravity, Codex, Anthropic, a stress name "Studio PC in the back office") so the line is amber. `.shortcuts` → `ShortcutsSettingsView()` (the tool's own defaults domain: everything at its default). `.devices` → `DevicesSettingsView` with `ready`: visible, name "Studio Mac", listening, rows "Desk PC" (paired online), "Travel laptop" (paired offline), "Office Mac mini" (available); `empty`: not visible, no rows; `error`: visible, problem "The network refused to listen. Turn Visible off and on again.", note in orange; `--stress`: a row named "A machine with a rather long name for testing the column".
- [ ] **Step 4: Verify.** `xcodegen` and the Debug build succeed; `bash scripts/test-settings-wiring.sh`, `bash scripts/check-settings-render-private.sh`, `bash scripts/test-link-wiring.sh`, `bash scripts/test-shortcuts.sh` pass; `bash scripts/render-link.sh --devices --out "${TMPDIR:-/tmp}/link-dev"` still writes its PNG. `bash scripts/render-settings.sh --page general --stress --out "${TMPDIR:-/tmp}/s5"` and `--page devices --stress`, and `--page general --light`: open the 415 pictures and check: no word broken, no truncated button, the Close after row on one or two clean lines, the island's shortcut list stacked at 415.
- [ ] **Step 5: Commit** the six files with `feat(settings): General (General, Shortcuts) and Devices in the kit`.

---

### Task 6: Pages: Agents and Services

**Files:**
- Create: `NotchBuddy/Sources/App/SettingsAgentsPage.swift`, `NotchBuddy/Sources/App/SettingsServicesPage.swift`
- Modify: `NotchBuddy/Sources/App/SettingsView.swift` (only `struct IntegrationFilterRow` at its bottom), `scripts/render-settings.swift`, `tests/SettingsWiringTests.swift`, `project.pbxproj`

**Interfaces:**
- Consumes: the kit; `SettingsStatus`; `HookNote`, `HookNoteLine`, `IntegrationFilterRow` (existing).
- Produces:
```swift
struct PillSwitchModel: Identifiable { let id: String; var name: String; var color: String; var isOn: Bool; var state: SettingsStatus.PillSwitch }
enum HookKind: String, CaseIterable { case claude, gemini, antigravity, codex }
struct HookCardModel: Identifiable {
    var id: HookKind { kind }
    var kind: HookKind; var title: String; var chip: String?; var next: String?; var path: String
    var revealable: Bool; var note: HookNote?; var pendingJSON: String?; var needsUpdate: Bool
}
struct PlanUsageModel { var showInNotch: Bool; var relayInstalled: Bool; var note: HookNote?; var heard: String?; var pendingJSON: String? }
struct AgentsSettingsModel { var pills: [PillSwitchModel]; var hooks: [HookCardModel]; var plan: PlanUsageModel? }
struct AgentsSettingsActions {
    var toggle: (String) -> Void
    var install: (HookKind) -> Void; var uninstall: (HookKind) -> Void; var confirm: (HookKind) -> Void; var cancel: (HookKind) -> Void
    var setShowPlan: (Bool) -> Void; var installRelay: () -> Void; var uninstallRelay: () -> Void; var confirmRelay: () -> Void; var cancelRelay: () -> Void
    var copy: (String) -> Void; var reveal: (HookKind) -> Void
}
struct AgentsSettingsPage: View { let model: AgentsSettingsModel; let actions: AgentsSettingsActions }
struct PillSwitchRow: View { let pill: PillSwitchModel; let toggle: (String) -> Void }   // shared with Task 7's Keys and Local models

struct ServiceFieldModel: Identifiable { let id: String; var placeholder: String; var secure: Bool }      // id = Keychain key
struct ServiceFilterModel { var label: String; var items: [String]; var filter: Binding<Set<String>>; var loading: Bool; var onLoad: () -> Void }
struct ServiceCardModel: Identifiable {
    let id: String                                                                                         // pill id
    var name: String; var color: String; var chip: String?; var pill: PillSwitchModel
    var fields: [ServiceFieldModel]; var help: String?; var filter: ServiceFilterModel?
}
struct ServicesSettingsPage: View {
    let cards: [ServiceCardModel]
    let text: (String) -> Binding<String>; let dirty: (String) -> Bool; let saved: (String) -> Bool
    let save: (String) -> Void; let toggle: (String) -> Void
}
```
Plan call: Services takes the drafts through three closures (`text`, `dirty`, `saved`) rather than the app's `SettingsDrafts` object, so the page file stays free of app types and the render tool feeds a dictionary.

Agents, cards in order (spec "Agents"):
1. `SettingsCard("On the island")`: one `PillSwitchRow` per pill (a colour dot, the name, and `SwitchRow`-style switch with `pill.state.chip`; when `!pill.state.showsSwitch`, a `StatusChip("Main")` instead of the switch; `pill.state.disabled` disables it).
2. One `SettingsCard(card.title, summary: card.chip)` per hook card: `HelpText(card.next)` when set; when `needsUpdate`, an `Update hooks` button (calls `install`); a `WrapRow` with `Install hooks` (`.borderedProminent`) and `Uninstall` (`.bordered`); then `if let note = card.note { HookNoteLine(note: note) }`; then `if let json = card.pendingJSON {` a `DisclosureGroup("Preview")` opened by default holding the JSON (10 pt monospaced, 140 pt scroll, text background, as today) and a `WrapRow` with `Confirm & write` and `Cancel` `}`; then `PathDisclosure(path: card.path, copy: actions.copy, reveal: card.revealable ? { actions.reveal(card.kind) } : nil)`. The same order for every kind (spec rule 7: the confirm flow is unchanged; the diff sits in a disclosure).
3. `SettingsCard("Plan usage", summary: relay chip)` when `plan != nil`: `HelpText("Shows your Claude plan usage (5-hour and weekly limits) in the notch header. Pro and Max plans only.")` and a `DisclosureGroup("More")` with `HelpText("NotchMeow adds a status line relay to ~/.claude/settings.json. If you already have a status line, it keeps working as before.")`; `SwitchRow("Show in the notch", isOn: Binding(get: { model.showInNotch }, set: { actions.setShowPlan($0) }))`; a `WrapRow` with `Install relay` (`.borderedProminent`, calls `installRelay`) or `Uninstall relay`; `if let note = plan.note { HookNoteLine(note: note) }`; `if let heard = plan.heard { HookNoteLine(note: HookNote(ok: true, text: heard)) }`; the JSON disclosure with `Confirm & write`/`Cancel` (100 pt) when `pendingJSON != nil`; `PathDisclosure(path: "~/.claude/settings.json", …)`. The relay chip: `Installed` or `Not installed`.

Services: one `SettingsCard(card.name, summary: card.chip)` per card; its first row is a colour dot and `PillSwitchRow`-style switch labelled `Show on the island` (`card.pill`); then a `KeyRow(field.placeholder, text: text(field.id), saved: saved(field.id), dirty: dirty(field.id), secure: field.secure)` per field (no Save of its own); `HelpText(help)` when set; the filter behind `DisclosureGroup("Choose which to watch")` holding `IntegrationFilterRow`; then a `Save` button (`.borderedProminent`) that calls `save(card.id)` when the card has fields. A card with no fields (Music) shows only its switch and `HelpText(card.help)`.

`IntegrationFilterRow` is restyled in place (review finding 6; same init, same filter rule): its label is 12 pt; Load list / Refresh and Clear are `.bordered` `.controlSize(.small)` buttons in a `WrapRow` (not `.mini`); each item is a checkbox `Toggle` whose name wraps between words (`.fixedSize(horizontal: false, vertical: true)`, 12 pt); "Watching N of M" is `HelpText`. Today's only caller is the old Integrations section, which keeps compiling.

- [ ] **Step 1: Pins** (section "Agents and Services"): in `SettingsAgentsPage.swift`, in the hook card's body the order is `Button("Uninstall")` < `if let note = card.note { HookNoteLine(note: note) }` < `if let json = card.pendingJSON {` < `PathDisclosure(`; `Button("Confirm & write")` and `Button("Cancel")` occur inside a `WrapRow`; the plan card's order is `Button("Install relay")` < `if let note = plan.note { HookNoteLine(note: note) }` < `if let heard = plan.heard` < `if let json = plan.pendingJSON {`; the plan switch reads `get: { model.showInNotch }` and nothing named `pending` in its getter; no `.pickerStyle(.segmented)`. In `SettingsServicesPage.swift`: `save(card.id)` occurs once, `KeyRow(` has no `save:` argument, `DisclosureGroup("Choose which to watch")`, `Show on the island`; `SettingsView.swift`'s `struct IntegrationFilterRow` contains `WrapRow` and no `.controlSize(.mini)`. Run → fail.
- [ ] **Step 2: Implement** the two files and the `IntegrationFilterRow` restyle.
- [ ] **Step 3: Samples.** `.agents`: pills Claude Code (main), Cursor (off), Antigravity (on), Codex (on), Gemini CLI (off, chip "Hooks not installed"); hook cards for the four kinds with paths `~/.claude/notchmeow/nm-hook` (Claude, revealable), `~/.gemini/settings.json`, `~/.gemini/config/hooks.json`, `~/.codex/hooks.json`; `ready`: Claude installed, Gemini installed with next "Restart Gemini CLI to activate", Codex installed with next "Open Codex, run /hooks or open Hooks in the app's settings, and trust them", Antigravity not installed; plan relay installed, heard "Last heard from Claude Code 2 minutes ago."; `empty`: none installed, relay not installed; `error`: Claude "Needs update" with the update sentence, note `HookNote(ok: false, text: "❌ ~/.claude/settings.json is not valid JSON — NotchMeow has not touched it.")`, a pending JSON preview open on Gemini, four pills on so Gemini's switch shows the cap; `--stress`: a 90-character path under `~/Library/Application Support/NotchMeow/…`. Under `--appstore` (`#if APPSTORE` in the sample), only the Claude card and no plan. `.services`: the eight cards with today's placeholders (Resend: `API key  (re_…)`, `From address  (you@yourdomain.com)`; n8n: `Instance URL  (https://…)`, `API key`; Vercel `Token`; GitHub `Personal Access Token` with today's scope sentence as help; Stripe `Secret key  (sk_live_… or sk_test_…)`; Cal.com `API key  (cal_live_…)`; Notion `Integration token  (secret_…)`; Music no field, help "Shows what the Music app is playing. Nothing to enter.", not under `--appstore`), drafts from a dictionary: `ready` with `sample-key-0000` saved for Resend, GitHub, Vercel and n8n's workflows list of five sample names with three watched; `empty` all empty; `error`/`--stress`: Resend typed and not saved (dirty), an n8n URL of 120 characters, the workflows list opened with "Sync the customer onboarding spreadsheet to the CRM every night" and a Vercel project "marketing-site-preview-environment-for-the-autumn-launch" (a hyphenated name: it may only wrap at its hyphens), and a long project name in the agents' coats (Task 8).
- [ ] **Step 4: Verify.** Build, pins, privacy check pass. Render `--page agents` and `--page services` at all widths, with `--stress`, `--states error` and `--appstore` (the last compiles with `-D APPSTORE`): open the 415 ones; no truncated button ("Install hooks", "Confirm & write", "Uninstall relay"), the error note wraps, the App Store picture has one hook card and no Plan usage or Music.
- [ ] **Step 5: Commit** the five files with `feat(settings): Agents and Services in the kit`.

---

### Task 7: Pages: AI and chat (Your AI, Keys, Local models)

**Files:**
- Create: `NotchBuddy/Sources/App/SettingsAIPage.swift`
- Modify: `NotchBuddy/Sources/App/AISettingsViews.swift` (delete `LocalServerRow`; `AddServerSheet` unchanged), `scripts/render-settings.swift`, `tests/SettingsWiringTests.swift`, `project.pbxproj`

**Interfaces:**
- Consumes: the kit; `SettingsAI` (Task 3); `PillSwitchModel`, `PillSwitchRow` (Task 6); `FeatureSetting`, `AIFeature`, `AIProviderID`, `ModelRef`, `ClaudeCodeModel` (existing, every build), `SettingsAI.ClaudeState` (Task 3); `AddServerSheet` (existing).
- Produces:
```swift
struct AIChoiceSection: Identifiable { let id: String; var title: String?; var items: [(label: String, value: FeatureSetting)] }
struct AIFeatureRow: Identifiable { let id: AIFeature; var label: String; var selection: Binding<FeatureSetting>; var sections: [AIChoiceSection]; var resolution: String? }
struct AIPreferModel { var selection: Binding<AIProviderID>; var choices: [(id: AIProviderID, label: String)] }
struct AIRowModel: Identifiable { let id: SettingsAI.Row; var title: String; var line: String; var chip: String; var isMain: Bool; var makeMain: SettingsAI.MakeMain; var addKey: Bool }
struct ClaudePlanDetails {
    var state: SettingsAI.ClaudeState; var line: String; var inUse: Bool; var checking: Bool; var model: Binding<ClaudeCodeModel>
    var connect: () -> Void; var stop: () -> Void; var checkAgain: () -> Void; var signIn: () -> Void; var guide: URL?
}
struct YourAIModel { var features: [AIFeatureRow]; var prefer: AIPreferModel?; var rows: [AIRowModel]; var claude: ClaudePlanDetails? }
struct YourAITab: View { let model: YourAIModel; let setChat: (FeatureSetting) -> Void; let openKeys: () -> Void }

struct AnthropicModelPicker { var choice: Binding<String>; var options: [(id: String, label: String)]; var customTag: String; var custom: Binding<String> }
struct KeyCardModel: Identifiable {
    var id: AIProviderID { provider }
    var provider: AIProviderID; var name: String; var color: String; var help: String; var fieldId: String; var placeholder: String
    var works: Bool?; var pill: PillSwitchModel?; var anthropicModel: AnthropicModelPicker?
}
struct KeysTab: View {
    let cards: [KeyCardModel]
    let text: (String) -> Binding<String>; let dirty: (String) -> Bool; let saved: (String) -> Bool
    let save: (AIProviderID) -> Void; let remove: (AIProviderID) -> Void; let toggle: (String) -> Void
}
struct ServerRowModel: Identifiable { let id: String; var name: String; var chip: String; var ready: Bool; var network: String?; var getLink: (label: String, url: URL)?; var removable: Bool; var pill: PillSwitchModel? }
struct LocalModelsModel { var servers: [ServerRowModel]; var apple: String?; var rescanning: Bool }
struct LocalModelsTab: View {
    let model: LocalModelsModel; @Binding var showAddServer: Bool
    let rescan: () -> Void; let remove: (String) -> Void; let toggle: (String) -> Void
    let addServer: (_ name: String, _ baseURL: String, _ key: String?) -> Void
}
```

**Your AI**, two cards:
- `SettingsCard("Which one answers")`: per feature a `SettingRow(row.label)` with a `Picker` (`.menu`) whose items are `Auto` then each section (`Section(title)` when titled) as today's `choiceItems`; under it `HelpText(resolution)` when the choice is Auto. When `prefer != nil`, `SettingRow("When Auto picks a cloud model, prefer")` with a `.menu` picker (Plan call: a menu, because three segmented labels truncate at 180 pt).
- `SettingsCard("Choose your AI")`: one row per `rows` entry: the title (semibold 12 pt), `HelpText(line)`, `StatusChip(chip)`, and the action: `isMain` → `StatusChip("Main")`; `.set(s)` → `Button("Make main") { setChat(s) }`; `.menu(refs)` → `Menu("Make main")` with one button per ref labelled `ref.model`; `.unavailable(reason)` → the button disabled and `HelpText(reason)`; a key row with `addKey` adds `Button("Add a key") { openKeys() }`. Title, chip and buttons lay out through `SettingRow` (stack when narrow). The Claude plan row, when `claude != nil`, adds `DisclosureGroup("Details")`: today's Connect Claude controls with plain values: `HelpText(claude.line)`; in a `WrapRow` by state, exactly today's buttons: signed in and in use → green "Claude is now your main AI." and `Stop using it`; signed in, not in use → `Use my Claude plan` (`.borderedProminent`, calls `connect`); signed out → `Sign in`; not installed or too old → a link "How to install" / "How to update" to `guide`; then `Check again` (`Checking…` while `checking`, disabled); a `SettingRow("Model")` picker over `ClaudeCodeModel.allCases` (`label`); `HelpText("NotchMeow never signs in to Claude and never reads Claude Code's credentials.")`.

**Keys**, one `SettingsCard(card.name)` per provider (Anthropic, Google AI, OpenAI): a colour dot in the title row; `KeyRow(card.placeholder, text:, saved:, dirty:, works: card.works, save: { save(card.provider) }, remove: { remove(card.provider) })`; `PillSwitchRow` labelled "Show on the island" when `pill != nil`; `HelpText(card.help)`; for Anthropic, `SettingRow("Model")` with today's picker (`options`, then `Custom…` tagged `customTag`) and, when Custom, a `TextField("Model ID (e.g. claude-sonnet-5-5)")` at `fieldMax`, and `HelpText("Used by the chat. The list comes from your Anthropic account.")`. Help lines (Plan call): Anthropic `From the Claude Console. Saved in the Keychain, checked when you save.`; Google AI `From Google AI Studio. Saved in the Keychain, checked when you save.`; OpenAI `From the OpenAI dashboard. Saved in the Keychain, checked when you save.` Placeholders as today: `API key (sk-ant-…)`, `API key (AI Studio)`, `API key (sk-…)`.

**Local models**, one `SettingsCard("Local models")`: `HelpText("Models running on this Mac, or on a server you add. Found automatically on this Mac only.")`; one row per server: a filled green dot when `ready` (else a ring, as today), the name, `StatusChip(chip)`, a `WrapRow` with the get/update `Link` when set and `Remove` when `removable`, `HelpText(network)` when set, and `PillSwitchRow` "Show on the island" when `pill != nil`; the Apple row (`Apple on-device` and `StatusChip(apple)`) when `apple != nil`; a `WrapRow` with `Rescan` (`Scanning…` and disabled while `rescanning`) and `Add server…`; `.sheet(isPresented: $showAddServer) { AddServerSheet(isPresented: $showAddServer, onAdd: addServer) }`.

- [ ] **Step 1: Pins** (section "AI and chat"): `SettingsAIPage.swift` contains `SettingsCard("Which one answers")`, `SettingsCard("Choose your AI")`, `Button("Make main")`, `Menu("Make main")`, `DisclosureGroup("Details")`, `SettingsCard("Local models")`, `AddServerSheet(isPresented: $showAddServer, onAdd: addServer)`, and does not contain `Use my Google plan`, `ChatGPT`, `.pickerStyle(.segmented)`, `KeychainStore`; the Keys card's `KeyRow(` passes `works: card.works`; `AISettingsViews.swift` no longer contains `struct LocalServerRow`. Run → fail.
- [ ] **Step 2: Implement** `SettingsAIPage.swift`; delete `LocalServerRow` (its `getURLs` live in `SettingsAI.getLink`; its status words in `SettingsAI.serverChip`). Nothing else uses it (today only `SettingsView.swift` does, and Task 12 replaces that call; until then keep the build green by leaving `SettingsView`'s old `chatSection` compiling: replace its one `LocalServerRow(server: server) { removeServer(server.serverID) }` line with `Text(server.name)` — a placeholder that Task 12 deletes with the section).
- [ ] **Step 3: Samples.** `.chat` with `.yourAI`, `.keys`, `.localModels`: built from a `SettingsAI.Input` like Task 3's base input, mapped through `SettingsAI.rows/title/line/chip/makeMain/isMain` (the render does what the app's section will do); Which one answers with Chat on Auto (resolution "Claude plan · Sonnet, falls back to Apple on-device") and File questions on Ollama; `ready`: Anthropic key saved with ✓, servers Ollama (2 models) and Studio PC (network, "network · unencrypted on your network"), Apple ready; `empty`: no keys, Claude not installed, no servers, Apple hidden; `error`: the OpenAI key typed, saved and rejected (✗), banner `❌ That key was refused by OpenAI. Check it and save again.`; `--stress`: a custom Anthropic model `claude-sonnet-5-5-20261001-extended-thinking-preview` (in the Custom… field), a server named "Studio PC in the back office (LM Studio)" with a 40-character model name in its Make main menu, and the resolution line "Studio PC in the back office (LM Studio) · a-long-local-model-name, falls back to Apple on-device". Rule for every page (review finding 6): a model id, a token or any unspaced value is shown only in a one-line field or a pop-up, never in `HelpText` or a wrapping label; the resolution line is the one exception and wraps at its spaces and ` · ` (its model part is at most one token). `--appstore`: no plan rows, no Details.
- [ ] **Step 4: Verify.** Debug build and the App Store target build (Task 4 Step 3's command) succeed; pins, privacy check, `bash scripts/test-settings-ai.sh` pass. Render `--page chat` (all three tabs), with `--stress`, `--states empty`, `--states error`, `--appstore`; open the 415 pictures: "Use my OpenAI plan" and its chip "Coming with the new chat" whole, Make main never truncated, the custom model id sits whole in its one-line `TextField` (the field scrolls; a model id has no spaces and is never put in wrapping text), and the Make main menu and pickers show it in their own pop-ups.
- [ ] **Step 5: Commit** the five files with `feat(settings): AI and chat (Your AI, Keys, Local models) in the kit`.

---

### Task 8: Pages: the Sidekick tab and the Cat tabs

**Files:**
- Modify: `NotchBuddy/Sources/App/SidekickSettingsView.swift`, `CatSettingsView.swift`, `CatSettingsSection.swift`, `WardrobeSettingsView.swift`, `scripts/render-settings.swift`, `scripts/render-cat-settings.sh`, `scripts/render-sidekick.swift` (its `renderSettings` height), `tests/SettingsWiringTests.swift`, `tests/SidekickWiringTests.swift`, `tests/CatWiringTests.swift`, `tests/CatSettingsTests.swift`, `tests/WardrobeWiringTests.swift`, `tests/DesktopCatWiringTests.swift`

**Interfaces:**
- Consumes: the kit; `SettingsSidekick` (Task 2); `SidekickStore.mute` (Task 1); `SettingsRoute.Tab`.
- Produces: `SidekickSettingsView(store: SidekickStore, found: String?)` (init unchanged; `scripts/render-sidekick.swift` keeps calling it); `CatSettingsView(store:alwaysActive:agents:lookup:wardrobeDay:tab:)` with a new last parameter `tab: SettingsRoute.Tab? = nil` (nil draws every group, for `render-cat-settings.sh`); `CatSettingsSection(tab: SettingsRoute.Tab? = nil)` (review finding 2: today's `SettingsView` calls `CatSettingsSection()` until Task 12, so the build stays green; nil shows every group, as before).

**The Sidekick tab** (spec "The Sidekick tab"; `SidekickSettingsView.swift` is one of the 21 sidekick files of `tests/SidekickWiringTests.swift`: it must not contain `#if`, `Timer`, `repeats`, `UserDefaults`, `print(` or any of that test's `never` tokens, even in a comment). Cards in order:
1. `SettingsCard("Notes")`: `SwitchRow("Show notes from the sidekick", isOn: <store.settings.on, store.setOn>)`; then, indented, `SwitchRow("Away recaps", help: "A short recap when you come back and an agent did something.", isOn: <!isMuted("recap"); on → unmute, off → mute>)` with `Button("Show me an example")`; `SwitchRow("Stuck nudges", help: "A nudge when an agent looks stuck.", isOn: <SettingsSidekick.stuckSwitch(...).on; off → mute all four, on → unmute all four>, chip: stuckSwitch's detail)` with `Show me an example` and a `DisclosureGroup("Choose which")` of four `SwitchRow`s named by `SettingsSidekick.stuckNames` (each mute/unmute its kind); `SwitchRow("Permission line", help: SettingsSidekick.permissionLine, isOn: .constant(true), disabled: true)` (owner's answer 1: locked on, no key); `SwitchRow("Jokes and moods", isOn: .constant(false), chip: SettingsSidekick.comesWithF3a, disabled: true)`. **Show me an example** toggles a `@State` kind and draws, inside the card, a 98 pt-high sample in the island note's look: `CardBackground(wash: nil)` with `SidekickView.title(kind)` (12 pt semibold, `#F5F6F8`) and `SettingsSidekick.example(kind)` (12 pt, `#C8CDD4`) and no buttons (builder call 6: never in the island, no sound, no ledger). For "Stuck nudges" the example is `stuck.loop`'s. The per-kind switches are disabled while the master switch is off.
2. `SettingsCard("Quiet times", summary: SettingsSidekick.comesWithF3a)`: `HelpText("Coming with F3a: hold notes while an app is full screen, during calls and screen sharing, and at hours you choose. Until then notes never show over your work or while you type.")` and three disabled `SwitchRow`s "Full-screen apps", "Calls and screen sharing", "Chosen hours".
3. `SettingsCard("Where its words come from")`: a `Picker` (`.radioGroup`) with "Plain rules" (`local == false`), "A model on this Mac" (`local == true`), and a disabled row "My main AI" with `StatusChip(SettingsSidekick.comesWithF3a)`; under "A model on this Mac", `HelpText(found.map { "Found: \($0)" } ?? "No local model found")`; always visible: `HelpText(SettingsSidekick.nothingLeaves)`; and today's line `HelpText("Only a model on this computer is ever asked, and only with the words of the note. Off means the plain words.")` reworded to `"Only a model on this computer is ever asked, and only with the words of the note."`.
4. `SettingsCard("Today so far", summary: SettingsSidekick.comesWithF3a)`: a disabled `Button("Today so far")`.
5. `SettingsCard("Muted notes")`: today's list (`kindNames` filtered by `isMuted`), each a `SettingRow(label)` with `Button("Unmute") { store.unmute(row.kind) }`; `"Nothing is muted"` when none; the line "A note you dismiss twice is muted until you unmute it here." always.

**The Cat tabs.** `CatSettingsView.body` becomes, exactly:
```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if shows(.look) {
                characterGroup
                lookGroup
                desktopGroup
            }
            if shows(.outfits) { WardrobeSettingsGroup(store: store, active: active, day: wardrobeDay) }
            if shows(.personality) {
                personalityGroup
                motionGroup
                allCatsGroup
            }
            if shows(.agentCats) {
                displayGroup
                if store.display.mode == .two { pairGroup }
                if store.display.mode == .perAgent { agentsGroup }
            }
        }
        .background(WindowVisibility(visible: $windowVisible))
    }
```
with `private func shows(_ t: SettingsRoute.Tab) -> Bool { tab == nil || tab == t }`. **[projects]** if P-mac is merged, its group goes right after the `agentsGroup` line inside `shows(.agentCats)`. Every `GroupBox("X")` in `CatSettingsView` and `WardrobeSettingsGroup` becomes `SettingsCard("X")` with the same title; every `.font(.system(size: 11)).foregroundColor(.secondary)` note becomes `HelpText`; `Toggle("Cat on the desktop", …)` and `Toggle("Fur lines", …)` become `SwitchRow`s with the same bindings; the 130 pt labels become `SettingRow`s; the Display picker becomes `.menu` (Plan call: three segmented labels do not fit a 327 pt column); the motion style stays segmented at 180 pt (two short labels fit); the coat grid stays `LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)])` (it already wraps: as many 66 pt tiles as fit, about six across at 720 and four at 415; builder call 9: tiles not scaled); the agents' rows' fixed 112 pt name becomes wrapping; "Reset to defaults" and its note go in a `WrapRow`. Previews, their `active:` arguments, `CatPreviewView` calls, `dressed:` flags and store calls stay character for character. `CatSettingsSection` gains `var tab: SettingsRoute.Tab? = nil` and passes `tab: tab`.

- [ ] **Step 1: Move the pins first** (they fail now, pass after Step 2):
  - `tests/SidekickWiringTests.swift`, the `sidekickSettings` checks (lines 142 to 144 today): the master switch is `SwitchRow("Show notes from the sidekick"` bound through `store.setOn($0)`; `store.setLocal(` is used; `"Found: \($0)"`, `"No local model found"`, `"Nothing is muted"`, `Button("Unmute") { store.unmute(row.kind) }` stay; `store.mute(` occurs; `SettingsSidekick.permissionLine` and `isOn: .constant(true), disabled: true` occur (the permission line is locked on); the five kind names stay; `!sidekickSettings.contains("risk")` and `!…contains("badge")` stay. Leave the line-141 sidebar check for Task 12.
  - `tests/CatWiringTests.swift` (Settings → Cat section): `SettingsCard("Main cat")` instead of `GroupBox("Main cat")` (and still no `"Character"` title); the order pin becomes `at("if shows(.look) {") < at("characterGroup\n") < at("if shows(.outfits)") < at("if shows(.personality)") < at("if shows(.agentCats) {") < at("displayGroup\n") < at("pairGroup }")`, with `agentsGroup }` after `pairGroup }`; the two mode pins unchanged; the `settings` (SettingsView) checks untouched until Task 12; `count("active: active", in: view) >= 5` unchanged.
  - `tests/WardrobeWiringTests.swift`: "the group follows Desktop and comes before the pair" becomes "the Wardrobe group is the Outfits tab": `view.contains("if shows(.outfits) { WardrobeSettingsGroup(store: store, active: active, day: wardrobeDay) }")`; any pin naming `GroupBox("Wardrobe")` names `SettingsCard("Wardrobe")`.
  - `tests/DesktopCatWiringTests.swift` line 78: `SwitchRow("Cat on the desktop"` instead of `Toggle("Cat on the desktop"`; line 79: `HelpText(desktopNote)` instead of `Text(desktopNote)` (the `#if !APPSTORE` note text unchanged).
  - `tests/CatSettingsTests.swift` line 131 to 133: unchanged (`store.setCharacter`, no `UserDefaults`, `paused: !active`, `WindowVisibility(visible: $windowVisible)`).
  - `tests/SettingsWiringTests.swift`, section "Sidekick and Cat": `CatSettingsSection.swift` passes `tab: tab`; `SidekickSettingsView.swift` contains `SettingsCard("Notes")`, `SettingsCard("Quiet times"`, `SettingsCard("Where its words come from")`, `SettingsCard("Today so far"`, `SettingsCard("Muted notes")` in that order, `SettingsSidekick.example(`, `CardBackground(wash: nil)`, and no `Sidekick.shared`, `engine`, `AppState`.
- [ ] **Step 2: Implement** the four view files; add `$APP/SettingsRoute.swift $APP/SettingsLayout.swift $APP/SettingsStatus.swift $APP/SettingsColors.swift $APP/SettingsCard.swift $APP/SettingRow.swift $APP/SwitchRow.swift $APP/StatusChip.swift $APP/WrapRow.swift $APP/HelpText.swift` to `scripts/render-cat-settings.sh`'s compile list (before `$APP/CatDisplayPreview.swift`). In `scripts/render-sidekick.swift`'s `renderSettings`, replace the fixed `height = 470.0` by the view's own height (`NSHostingController(rootView:).sizeThatFits(in: CGSize(width: width, height: 100_000)).height`), because the Sidekick tab is now much taller (review finding 13).
- [ ] **Step 3: Samples.** `.chat/.sidekick` → `SidekickSettingsView(store: <a SidekickStore on a MemoryBacking-like backing defined in render-settings.swift, as render-sidekick.swift does>, found: "Local · qwen3.5:2b")`; `ready`: `stuck.errors` and `stuck.silent` muted; `empty`: nothing muted, no model found; `error`: all four stuck kinds muted and the master off. `.cat/*` → `CatSettingsView(store: <a CatSettingsStore on its own backing, as render-cat-settings.swift does>, alwaysActive: true, agents: <CatDisplaySample's agent pills>, tab: tab)`; `--stress`: an agent named "A rather long agent name for the column". The Display mode is `perAgent` for the Agents' cats picture.
- [ ] **Step 4: Verify.** Build; `bash scripts/test-settings-wiring.sh`, `bash scripts/test-sidekick-wiring.sh`, `bash scripts/test-cat-wiring.sh`, `bash scripts/test-cat-settings.sh`, `bash scripts/test-wardrobe-wiring.sh`, `bash scripts/test-cat-desktop-wiring.sh`, `bash scripts/check-settings-render-private.sh` pass; `bash scripts/render-cat-settings.sh --out "${TMPDIR:-/tmp}/cat.png" --mode perAgent --agents` and `bash scripts/render-sidekick.sh --out "${TMPDIR:-/tmp}/sk.png" --settings-out "${TMPDIR:-/tmp}/sk-settings.png"` still write their PNGs. Render `--page chat --tab sidekick` and `--page cat` (four tabs) with `--stress` and `--light`; open them: a hidden tab draws nothing, the coat grid shows about six tiles across at 720 and four at 415, never scaled, the example note reads the template sentence.
- [ ] **Step 5: Commit** the twelve files with `feat(settings): the Sidekick tab and the Cat tabs in the kit`.

---

### Task 9: Owner checkpoint 1: the pictures

- [ ] The session runs, into `.claude/checkpoints/settings-mac/` of the worktree: `bash scripts/render-settings.sh --out …/dark`, `--light --out …/light`, `--stress --out …/stress`, `--states empty --out …/empty`, `--states error --out …/error`, `--appstore --out …/appstore`, `--kit --out …/kit`. It sends the owner the six contact sheets and the 415 pictures of every page, and asks him to sign off the page map, the tabs, the breakpoint (600; the spec's 560 made a 320 pt column, see Global Constraints), the column maximum (640), the sidebar widths and the new one-line wordings (Your AI lines, Keys help, Quiet times, the Island card's "seconds"). Changed numbers go into `SettingsLayout` (and Task 2's expected values); changed wordings into the page files. **Nothing from Task 10 on starts until the owner says go.** The Windows/Linux Settings plan may start once he signs.

---

### Task 10: App side A: controller, drafts, General, Agents, Services, Devices

**Files:**
- Create: `NotchBuddy/Sources/App/SettingsController.swift`, `SettingsDrafts.swift`, `SettingsSections.swift`
- Modify: `tests/SettingsWiringTests.swift`, `project.pbxproj`

**Interfaces:**
- Consumes: every page model of Tasks 5 to 7; `SettingsDraftBook`, `SettingsStatus`, `SettingsMap.serviceFields`, `SettingsMap.pillHome`, `SettingsLayout.displayPath`.
- Produces:
```swift
@MainActor final class SettingsDrafts: ObservableObject {
    init(read: (String) -> String)                       // seeds every Keychain field id in SettingsDrafts.fieldIds at once (never during a view update)
    static let fieldIds: [String]                        // the 3 AI key ids + every SettingsMap.serviceFields value
    func text(_ id: String) -> Binding<String>
    func isDirty(_ id: String) -> Bool
    func isSaved(_ id: String) -> Bool
    func markSaved(_ id: String, stored: String)
}
@MainActor final class SettingsController: ObservableObject {
    @Published var banner: String = ""                   // today's statusMessage, same texts
    @Published var claudeNote: HookNote?
    @Published var hookNeedsUpdate: Bool
    @Published var pending: [HookKind: String] = [:]     // the JSON preview of each kind waiting for Confirm & write
    // GitHub build only (#if !APPSTORE): geminiInstalled, agyInstalled, codexInstalled, geminiPendingInstall, agyPendingInstall, codexPendingInstall,
    //   planNote, pendingStatusLineJSON, statusLinePendingInstall, planTogglePending
    @Published var launchAtStartup: Bool
    @Published var vercelProjects: [String] = []; @Published var loadingVercel = false
    @Published var n8nWorkflows: [String] = []; @Published var loadingN8n = false
    func installHooks(); func confirmInstall(); func uninstallHooks()              // Claude Code, GitHub build
    func installHooksAppStore(); func uninstallHooksAppStore()                    // App Store build
    func install(_ k: HookKind); func uninstall(_ k: HookKind); func confirm(_ k: HookKind); func cancel(_ k: HookKind)
    func installStatusLine(); func uninstallStatusLine(); func confirmStatusLine(); func setShowPlan(_ on: Bool)
    func installRelay(); func uninstallRelay(); func cancelRelay()          // the Plan usage card's three buttons
    func saveService(_ pillId: String, drafts: SettingsDrafts)
    func loadVercelProjects(); func loadN8nWorkflows()
    func toggleStartup(_ on: Bool)
    func reveal(_ k: HookKind); func copy(_ text: String)
}
extension SettingsSections {   // enum SettingsSections, @MainActor static builders
    static func general(state: AppState, controller: SettingsController, open: @escaping (SettingsRoute.Place) -> Void) -> GeneralSettingsModel
    static func pills(state: AppState, ids: [String]) -> [PillSwitchModel]
    static func agents(state: AppState, controller: SettingsController) -> (AgentsSettingsModel, AgentsSettingsActions)
    static func services(state: AppState, controller: SettingsController, drafts: SettingsDrafts) -> [ServiceCardModel]
}
```
Plan call: `SettingsSections` is an `enum` of static builders (no stored state of its own) so `SettingsView` reads `AppState` once per body and the builders stay simple to pin.

The rules:
- **Moved, not rewritten.** Every body of today's `SettingsView` actions moves into `SettingsController` with the same name and the same statements, `statusMessage` renamed `banner`, `@State` reads turned into the controller's `@Published` properties: `installHooks`, `confirmInstall`, `uninstallHooks`, `installHooksAppStore`, `uninstallHooksAppStore`, `pickClaudeFolder`, `triggerGeminiPreview`, `confirmGeminiOp`, `triggerAgyPreview`, `confirmAgyOp`, `triggerCodexPreview`, `confirmCodexOp`, `installStatusLine`, `uninstallStatusLine`, `confirmStatusLine`, `loadVercelProjects`, `loadN8nWorkflows`, `fetchN8nWorkflows`, `toggleStartup`. `install/uninstall/confirm/cancel(_ k:)` dispatch to them by kind (`.claude` → `installHooks` (App Store: `installHooksAppStore`), `.gemini` → `triggerGeminiPreview(install:)`…); the pending JSON of each kind is `pending[k]` (today's `pendingHookJSON`, `pendingGeminiJSON`, … and their `show…Diff` flags become `pending[k] != nil`). The URLSession callbacks capture `[weak self]` and hop to the main actor as today. `setShowPlan(_:)` is the body of today's "Show in the notch" setter; `installRelay()` is `planTogglePending = true; installStatusLine()`; `uninstallRelay()` is `uninstallStatusLine()`; `cancelRelay()` is today's Cancel (`pendingStatusLineJSON = ""` with its flag, `planTogglePending = false`). `AgentsSettingsActions`' `installRelay`, `uninstallRelay`, `confirmRelay` (`confirmStatusLine`) and `cancelRelay` map to them.
- `reveal(_:)`: `NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: <the real path>)])` for `.claude` (the script, `HookServer.hookScriptPath`) and the settings files expanded from `~`; `copy(_:)`: `NSPasteboard.general.clearContents(); setString(text, forType: .string)`.
- **`saveService(_ pillId:drafts:)`** writes only `SettingsMap.serviceFields[pillId]`: each field through today's `saveKey(_:value:)` (empty → remove), then `drafts.markSaved(id, stored: value)`; for `integration_github` it keeps today's change detection and side effects (clear `githubPulse` and `githubActivity`, `githubStats` when removed, `triggerPulseNow` and `refreshActivityIfStale` when set); banner `"✓ \(name) saved."` (Plan call: today's "✓ Integration keys saved." named per card).
- **`pills(state:ids:)`** is the one builder of every pill row (Agents, Keys, Local models, Services): `SettingsStatus.pillSwitch(isOn: state.activeIntegrations.contains(id), isMain: id == state.mainPillId, activeCount: state.activeIntegrations.count, missing:)`, with `missing` = `"Hooks not installed"` for `agent_gemini`, `agent_antigravity`, `agent_codex` when their `HookServer.*HooksInstalled()` is false and for `integration_claude` when `HookServer.claudeHooksInstalled()` is false (GitHub build only; nil in the App Store build and for Cursor); for the AI pills, today's words (review finding 5): `ai_anthropic`, `ai_google`, `ai_openai` → `"Key not configured"` when `KeychainStore.shared.get(<its key>)` is nil; `ai_ollama`, `ai_lmstudio` → `"Not connected"` when no ready server has that provider's id (`state.localServers.contains { $0.serverID == provider.rawValue && $0.isReady }` is false). Only ids in `PillCatalog.available` are built (so the App Store lists what it offers, and the Claude App pill never). The toggle is `state.toggleIntegration(id)`.
- **General**: bindings `$state.soundEnabled`, `$state.soundVolume`, `$state.openOnHover`, **[focus]** `$state.focusAware`, `$state.hoverGlow`, `$state.tuckAway`, `$state.autoCloseInterval`; `mainPill` is a binding whose setter does today's `onChange` (`state.mainPillId = id; state.activeIntegrations.remove(id); state.loadIntegrationTasks(); state.setFocus(id)`); `mainChoices` = available workspace pills not `comingSoon`; `slots` = `SettingsStatus.slots(active: state.activeIntegrations, catalog: PillCatalog.available.map { ($0.id, $0.name) })`; `slotLinks` = those names with `SettingsMap.pillHome(id)`; `launchAtStartup` bound to the controller (setter calls `toggleStartup`).
- **Agents**: pills for `integration_claude`, `agent_cursor`, `agent_antigravity`, `agent_codex`, `agent_gemini`; hook cards: Claude (title "Claude Code hooks"; chip `SettingsStatus.hookChip(installed: <GitHub: HookServer.claudeHooksInstalled(); App Store: nil>, needsUpdate: controller.hookNeedsUpdate)`; next: needs update → `"Hooks outdated — update them to answer Claude's questions from the notch"`, else nil; path: GitHub `SettingsLayout.displayPath(HookServer.hookScriptPath, home: FileManager.default.homeDirectoryForCurrentUser.path)`, revealable; App Store the literal `~/.claude/notchmeow/nm-hook`, not revealable); GitHub build only: Gemini ("Gemini CLI hooks", next when installed `"Restart Gemini CLI to activate"`, path `~/.gemini/settings.json`), Antigravity ("Antigravity hooks", `"Restart Antigravity to activate"`, `~/.gemini/config/hooks.json`), Codex ("Codex hooks", `"Open Codex, run /hooks or open Hooks in the app's settings, and trust them"`, `~/.codex/hooks.json`), chips from their installed flags; plan (GitHub only) from `state.showPlanInNotch`, `state.planRelayInstalled`, `controller.planNote`, `ClaudePlanGauge.statusNote(relayInstalled: state.planRelayInstalled, usage: state.claudePlanUsage)`, `controller.pendingStatusLineJSON`.
- **Services**: the eight cards (Music GitHub only) with today's placeholders and colours (Resend `#22C55E`, n8n `#F29B38`, Vercel `#7C5CFF`, GitHub `#F4505E`, Stripe `#0570DE`, Cal.com `#C9956A`, Notion `#E8E8E8`, Music `#FA2D48`), chip `SettingsStatus.serviceChip(saved: drafts.isSaved(<first field>))` (n8n: both fields saved), the filters bound to `$state.n8nWorkflowFilter` and `$state.vercelProjectFilter` with the controller's lists and loaders. Music has no chip.
- **Devices**: unchanged (`DevicesSettingsSection()`).

- [ ] **Step 1: Pins** (section "App side A"): `SettingsController.swift` contains each moved function name once (`func installHooks()`, `func confirmInstall()`, …, `func confirmStatusLine()`); `func saveService(` reads `SettingsMap.serviceFields[pillId]` and contains `GithubPoller.shared.triggerPulseNow()`; `SettingsSections.swift` contains `SettingsStatus.pillSwitch(` exactly once and `state.toggleIntegration(` exactly once, `"Key not configured"` and `"Not connected"` once each, `hoverGlow: $state.hoverGlow`, `tuckAway: $state.tuckAway`, `state.activeIntegrations.remove(` (the main pill's side effect), `ClaudePlanGauge.statusNote(relayInstalled: state.planRelayInstalled, usage: state.claudePlanUsage)`, `homeDirectoryForCurrentUser`; `SettingsDrafts.swift` contains `SettingsDraftBook` and seeds in `init`. Run → fail.
- [ ] **Step 2: Implement** the three files (the controller's `#if APPSTORE`/`#if !APPSTORE` blocks mirror today's).
- [ ] **Step 3: Verify.** `xcodegen`, Debug build and App Store target build (`xcodebuild -scheme NotchMeowAppStore -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet`) succeed; `bash scripts/test-settings-wiring.sh` passes. Nothing is shown yet (Task 12 swaps).
- [ ] **Step 4: Commit** with `feat(settings): the app side of General, Agents, Services and Devices`.

---

### Task 11: App side B: AI and chat, Make main, Sidekick, Cat

**Files:**
- Modify: `NotchBuddy/Sources/App/SettingsController.swift`, `SettingsSections.swift`, `ClaudeChatViews.swift` (delete `ConnectClaudePlanView`), `tests/SettingsWiringTests.swift`

**Interfaces:**
- Consumes: Task 7's models; `SettingsAI`; `AIService.shared` (`key`, `cloudKeys`, `cloudModel`, `resolutionLine`, `discover`, `refreshClaudeStatus`, `listCloudModels`); `AIMessages.listFailure`.
- Produces:
```swift
// SettingsController (added)
@Published var keyWorks: [AIProviderID: Bool] = [:]
@Published var fetchedModels: [(id: String, label: String)] = []; @Published var modelChoice: String; @Published var customModel: String
@Published var showAddServer = false; @Published var rescanning = false; @Published var checkingClaude = false
static let fallbackModels: [(id: String, label: String)]; static let customModelTag = "__custom__"
func saveKey(_ provider: AIProviderID, drafts: SettingsDrafts)
func removeKey(_ provider: AIProviderID, drafts: SettingsDrafts)
func fetchModelsIfNeeded()                    // today's onAppear model fetch
func applyCustomModel(_ value: String)
func removeServer(_ id: String); func addServer(name: String, baseURL: String, key: String?); func rescan()
func setChat(_ setting: FeatureSetting)       // state.setChoice(setting, for: .chat): Make main changes Chat only (call 4)
// GitHub build: func connectClaude(); func stopClaude(); func checkClaude()
// SettingsSections (added)
static func yourAI(state: AppState, controller: SettingsController, openKeys: @escaping () -> Void) -> YourAIModel
static func keys(state: AppState, controller: SettingsController, drafts: SettingsDrafts) -> [KeyCardModel]
static func localModels(state: AppState, controller: SettingsController) -> LocalModelsModel
static func aiInput(state: AppState) -> SettingsAI.Input
```

The rules:
- `saveKey` is today's `saveKey(_:_:)` with the value taken from `drafts.text(fieldId).wrappedValue` and `drafts.markSaved(fieldId, stored: <the trimmed key>)` after the Keychain write; **it no longer sets `preferredCloud`** (call 3: that side effect went with the second Anthropic box). `removeKey` is the same path with an empty value (builder call 3).
- `fetchModelsIfNeeded`, `applyCustomModel`, `removeServer`, the Add server closure and Rescan are today's bodies; `fallbackModels` and `customModelTag` move with their values.
- `connectClaude`/`stopClaude`/`checkClaude` are today's `ConnectClaudePlanView.startUsing`, `stopUsing` and `refresh` (`checkingClaude` around `await AIService.shared.refreshClaudeStatus()`); the view struct is deleted from `ClaudeChatViews.swift` (lines from `struct ConnectClaudePlanView: View {` to its closing brace, before the file's last `#endif`). Its `line` text moves into `yourAI`'s `ClaudePlanDetails.line` word for word.
- `aiInput`: `githubBuild` true except under `#if APPSTORE`; Claude fields (inside `#if !APPSTORE`, `ClaudeCodeStatus.State` mapped case for case to `SettingsAI.ClaudeState`) from `state.claudeCodeStatus`, `state.claudeCodeEnabled`, `state.claudeCodeModel.rawValue`, `ClaudeCodeText.signInWords(status.authMethod)` (GitHub only; App Store `.notInstalled`, false, `"sonnet"`, ""); `keys` = `SettingsAI.keyProviders` filtered by `AIService.shared.key($0) != nil`; `cloudModel` from `AIService.shared.cloudModel`; servers from `state.localServers` (`placement == .network` → `network`); `memory` = `state.localModelMemory`; `appleReady` = `state.appleStatus == .ready`.
- `yourAI`: features Chat and File questions with today's `choiceBinding` and the sections of today's `choiceItems` (Auto, Cloud, Claude plan (GitHub only, when enabled and ready), Local, Apple on-device, and the "(not running)" stand-in), resolution `AIService.shared.resolutionLine(feature)` under Auto; `prefer` when `AIService.shared.cloudKeys.intersection([.claudeCode, .anthropic, .openai]).count >= 2`, with today's labels; rows from `SettingsAI` (`addKey` for key rows with no key); `claude` (GitHub only) with `$state.claudeCodeModel`, `inUse` = `state.claudeCodeEnabled && state.preferredCloud == .claudeCode`, guide `URL(string: ClaudeCodeLocator.installGuide)`, `signIn` = `ClaudeCodeActions.signIn()`.
- `keys`: the three cards (Task 7's names, help lines and placeholders; colours `ChatProvider(p).accentHex` through its pill definition), `fieldId` = `AICatalog.info(p).keychainKey!`, `works` = `controller.keyWorks[p]`, the pill `ai_anthropic`/`ai_google`/`ai_openai` from `pills(state:ids:)`, Anthropic's `AnthropicModelPicker` over `controller.fetchedModels` (else `fallbackModels`), `$controller.modelChoice` (setter: today's `onChange`, `state.claudeModel = choice` or `applyCustomModel`), `$controller.customModel`.
- `localModels`: rows from `state.localServers` with `SettingsAI.serverChip(server.status)`, network note `"network · unencrypted on your network"` for an `http://` network server, `"network"` for others, get/update links from `SettingsAI.getLink` (label `"Update"` when outdated, `"Get \(name)"` when not installed), `removable` for ids starting with `CustomServer.idPrefix`, pills `ai_ollama`/`ai_lmstudio` for those two servers; `apple` = `state.appleStatus.line` mapped to `"Ready"` when ready, else the line; `.onAppear { Task { await AIService.shared.discover() } }` happens in `SettingsView` when the page is AI and chat (Task 12), as today.
- Sidekick: `SidekickSettingsSection()` (unchanged). Cat: `CatSettingsSection(tab:)`.

- [ ] **Step 1: Pins** (section "App side B"): `SettingsController.swift`'s `func saveKey(` contains `AIService.shared.listCloudModels(` and `AIMessages.listFailure(` and does not contain `preferredCloud`; `func setChat(` contains `state.setChoice(setting, for: .chat)` and not `.files`; `ClaudeChatViews.swift` does not contain `ConnectClaudePlanView`; `SettingsSections.swift` contains `SettingsAI.makeMain(`, `SettingsAI.isMain(`, `AIService.shared.resolutionLine(`, `#if !APPSTORE` around the `claude:` details and the Claude plan choice section; the mapping `ClaudeCodeStatus.State` → `SettingsAI.ClaudeState` sits inside `#if !APPSTORE` in `aiInput`. Run → fail.
- [ ] **Step 2: Implement.** Today's `SettingsView` still calls its own copies; its `chatSection` still references `ConnectClaudePlanView`, so in the same step replace that one line with `EmptyView()` (Task 12 deletes the section).
- [ ] **Step 3: Verify.** Both builds succeed; `bash scripts/test-settings-wiring.sh`, `bash scripts/test-claude-code.sh` pass.
- [ ] **Step 4: Commit** with `feat(settings): the app side of AI and chat, Make main, Sidekick and Cat`.

---

### Task 12: The swap: shell host, window, migration, old code out, pins moved

**Files:**
- Modify: `NotchBuddy/Sources/App/SettingsView.swift`, `AppDelegate.swift`, `IslandViewContent.swift`, `tests/SettingsWiringTests.swift`, `tests/CatWiringTests.swift`, `tests/CatSettingsTests.swift`, `tests/IslandTuckAwayWiringTests.swift`, `tests/HookInstallNoteTests.swift`, `tests/SidekickWiringTests.swift`, `scripts/test-link-wiring.sh`, `scripts/test-u1-wiring.sh`, `scripts/check-no-leftovers.sh`, `.github/workflows/build.yml`; **[focus]** `tests/FocusAwareWiringTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `struct SettingsView: View` (no init arguments, as today), `SettingsView.swift` keeping only `SettingsView` and the shared helpers already at its bottom (`HookNoteLine`, `SidebarBackground`, `SettingsSidebarRow`, `IntegrationFilterRow`, `ShortcutRecorderButton` and the `shortcutRecordingStarted` name), unchanged.

The new `SettingsView`:
- `@ObservedObject private var state = AppState.shared`; `@StateObject private var controller = SettingsController()`; `@StateObject private var drafts = SettingsDrafts(read: { KeychainStore.shared.get($0) ?? "" })` (window life: `AppDelegate.openSettings` makes a new window, so a new `SettingsView`, each time the window was closed: drafts are dropped on close as today, with no observer); `@AppStorage(SettingsRoute.sectionKey) private var storedSection = "general"`.
- The page is `SettingsRoute.migrate(storedSection:).page`. On appear and on change of `storedSection`: when the migrated tag differs from the stored one, write `place.page.rawValue` back and, if `place.tab != nil`, `UserDefaults.standard.set(place.tab!.rawValue, forKey: SettingsRoute.tabKey(place.page))` (an old `shortcuts`/`sidekick` lands on its tab; `AppDelegate`'s notification path writes the raw tag and gets the same treatment).
- The tab is held in `@State private var tab: SettingsRoute.Tab?` (review finding 9: a binding straight onto `UserDefaults` would redraw only by accident). It is loaded from `SettingsRoute.tab(for: page, stored: UserDefaults.standard.string(forKey: SettingsRoute.tabKey(page)))` on appear and on every page change (after the migration's write), and every change of it writes the raw value to `SettingsRoute.tabKey(page)` (per page, builder call 5). Changing page or tab clears `controller.banner` (today's rule).
- Body: `SettingsShell(version:, icon: NSApplication.shared.applicationIconImage, page:) { page in SettingsPage(page:, tab:, banner: controller.banner, dismissBanner: { controller.banner = "" }) { content(page, tab) } }` where content switches: general/general → `GeneralSettingsTab(model: SettingsSections.general(…, open: { place in select it }))`; general/shortcuts → `ShortcutsSettingsView()`; agents → `AgentsSettingsPage`; chat/yourAI → `YourAITab(model:, setChat: controller.setChat, openKeys: { select chat/keys })`; chat/keys → `KeysTab` with `drafts` closures and controller actions; chat/localModels → `LocalModelsTab(model:, showAddServer: $controller.showAddServer, …)`; chat/sidekick → `SidekickSettingsSection()`; chat/companion → `EmptyView()` (never reached while hidden); services → `ServicesSettingsPage(cards:, text: drafts.text, dirty: drafts.isDirty, saved: drafts.isSaved, save: { controller.saveService($0, drafts: drafts) }, toggle: { state.toggleIntegration($0) })`; cat → `CatSettingsSection(tab: tab ?? .look)`; devices → `DevicesSettingsSection()`.
- `.onAppear`: `state.refreshPlanRelayState()` (GitHub only) and `controller.fetchModelsIfNeeded()`, as today; when the page becomes AI and chat, `Task { await AIService.shared.discover() }` (today's Local models `onAppear`) and, in the GitHub build, `controller.checkClaude()` (today's `ConnectClaudePlanView` asked Claude Code on appear; review finding 3). Both run once per arrival on the page (an `.onChange(of: page)` plus the first appearance), never on a timer.
- Everything else of the old struct (the `@State` list, `generalSection`, `activePillsSection`, `agentsSection`, `chatSection`, `integrationsSection`, the actions, `pillRow`) is deleted.

**Window** (`AppDelegate.openSettings`): `NSRect(x: 0, y: 0, width: SettingsLayout.defaultWidth, height: SettingsLayout.defaultHeight)` and `win.contentMinSize = NSSize(width: SettingsLayout.minWidth, height: SettingsLayout.minHeight)`; `host.sizingOptions = [.minSize]` stays. Plan call (the spec's "settles which number is real"): today `.minSize` lets SwiftUI's minimum (sidebar 200 + the old detail's ≈215) replace the 640 written after it, which is why the owner's window goes to 415; now the shell's own minimum is exactly 415 × 420, so the two agree and the narrow layout is a promise. The owner's check (Task 14) confirms it on screen.

**The island's tags** (`IslandViewContent.swift`): `default:                 section = "integrations"` becomes `default:                 section = "services"`; in the same switch `case .ai:                section = "chat"` becomes `case .ai:                section = "chat/" + (SettingsMap.pillHome(task.id).tab?.rawValue ?? "keys")` (so `chat/keys` or `chat/localmodels`) (an AI pill goes to the tab its control lives on: a cloud provider to Keys, `ai_ollama` and `ai_lmstudio` to Local models; pinned: the switch reads `SettingsMap.pillHome`, and a test asserts `pillHome("ai_ollama")` is AI and chat / Local models and `pillHome("ai_anthropic")` is AI and chat / Keys); in `AIEmptyStateView`, the "Add a cloud key" button posts `"chat/keys"` and the "Connect Claude" button posts `"chat/yourai"` (review finding 14). `perform(.openSettings)` keeps `"chat"` (the last tab used). The `"agents"` case stays.

**Pins that read `SettingsView.swift` today move** (each keeps asserting the same wiring, at its new file):
- `tests/CatWiringTests.swift` line 23 to 28: `settings` reads `SettingsSections.swift` plus `SettingsView.swift`; "Settings hosts the section through CatSettingsSection" becomes `SettingsView.swift` contains `CatSettingsSection(tab: tab ?? .look)` and `CatSettingsSection.swift` still reads `AppState`.
- `tests/CatSettingsTests.swift` line 130 and 134: Settings has a Cat page (`SettingsRoute.swift` contains `case general, agents, chat, services, cat, devices` and `SettingsView.swift` contains `CatSettingsSection(`), and Settings names `CatSettingsSection` once and `CatSettingsView` nowhere (`SettingsView.swift`).
- `tests/IslandTuckAwayWiringTests.swift` line 13 to 15 and 54 to 64: `settings` reads `SettingsGeneralPage.swift` (the row: `SettingRow("Tuck the island away"`, the five tags, after `SwitchRow("Hover glow"`, the help sentence, no "without movement") and the binding pin reads `SettingsSections.swift` (`tuckAway: $state.tuckAway`); the "six files are there" check names `struct GeneralSettingsTab` instead of `struct SettingsView`.
- `tests/HookInstallNoteTests.swift` line 35 to 63: `view` reads `SettingsAgentsPage.swift` and a new `controller` reads `SettingsController.swift`. The Claude box pin uses the hook card's body (`Button("Uninstall")` < `if let note = card.note { HookNoteLine(note: note) }` < `if let json = card.pendingJSON {`); the plan box pin (`Button("Install relay")` < `if let note = plan.note { HookNoteLine(note: note) }` < `if let heard = plan.heard` < `if let json = plan.pendingJSON {`) and the heard line's source is `SettingsSections.swift` (`ClaudePlanGauge.statusNote(relayInstalled: state.planRelayInstalled, usage: state.claudePlanUsage)`); `body(controller, "func confirmInstall() {")`, `"func installHooks() {"`, `"func uninstallHooks() {"`, `"func confirmStatusLine() {"`, `"func installStatusLine() {"` with the same `contains` checks; the switch pin: the page's getter is `get: { model.showInNotch }` and `SettingsSections.swift` passes `showInNotch: state.showPlanInNotch`; the Install relay pin: `func installRelay() {` body contains `planTogglePending = true` and `installStatusLine()`. Update the file's header comment to name the new files.
- `tests/SidekickWiringTests.swift` line 141: replaced by "Settings shows the Sidekick as a tab of AI and chat": `SettingsRoute.swift` contains `sidekick` inside the `Tab` enum (the tabs share one `case` line, so the pin matches the word `sidekick` between `enum Tab` and its closing brace) and `SettingsView.swift` contains `SidekickSettingsSection()` once.
- `scripts/test-link-wiring.sh` line 148: `pin "Settings has a Devices page" 1 $APP/SettingsView.swift -- 'DevicesSettingsSection\(\)'`.
- `scripts/test-u1-wiring.sh` line 81: `has "the switch is in Settings" SettingsGeneralPage.swift 'SwitchRow("Hover glow", help:'` and a second line `has "...bound to the stored value" SettingsSections.swift 'hoverGlow: $state.hoverGlow'`.
- **[focus]** `tests/FocusAwareWiringTests.swift`: the Settings pin reads `SettingsGeneralPage.swift` (`SwitchRow("Step back when I'm already in the app"` after `SwitchRow("Open on hover"` and before `SwitchRow("Hover glow"`) and `SettingsSections.swift` (`focusAware: $state.focusAware`).

**Leftovers:** in `scripts/check-no-leftovers.sh`, after the last `check` line add:
```bash
check 'the old Settings tags live only in SettingsRoute.migrate (and its test)' '"activepills"|"integrations"' --exclude=SettingsRoute.swift --exclude=SettingsRulesTests.swift
check 'no Active pills page and no Hotkey group in Settings' 'title: "Active pills"|GroupBox\("Hotkey"\)|Save integrations'
```

**New pins** (section "The swap" in `tests/SettingsWiringTests.swift`): `SettingsView.swift` contains `SettingsRoute.migrate(storedSection:`, `SettingsRoute.tabKey(`, `@State private var tab: SettingsRoute.Tab?`, `SettingsShell(`, `SettingsPage(`, `controller.banner = ""` and no `GroupBox`, `statusMessage`, `activePillsSection`, `integrationsSection`, `NavigationSplitView`, `Timer`; `AppDelegate.swift` contains `SettingsLayout.minWidth` and `SettingsLayout.defaultWidth` and not `width: 640, height: 420`; `IslandViewContent.swift` contains `section = "services"`, `section = "chat/keys"`, `object: "chat/keys")` once, `object: "chat/yourai")` once, and not `section = "integrations"`; every `card` of `tests/fixtures/settings/controls.json` (except the shell's) appears as a string literal `"<card>"` in one of `Settings*.swift`, `CatSettingsView.swift`, `WardrobeSettingsView.swift`, `SidekickSettingsView.swift`, `ShortcutsSettingsView.swift`, `LinkViews.swift` (read the JSON with `JSONSerialization`); `Claude Code hooks`, `Gemini CLI hooks`, `Antigravity hooks`, `Codex hooks` and `Plan usage` sit inside `#if !APPSTORE` in `SettingsSections.swift` except Claude Code's; no Settings view file contains `.pickerStyle(.segmented)` except `CatSettingsView.swift`'s motion style (`count == 1` there).

- [ ] **Step 1: Move the pins and write the new ones** (as above). Run the moved scripts → they fail (the old view is still there).
- [ ] **Step 2: Implement** the new `SettingsView`, the window lines, the island's tag, the two leftover checks.
- [ ] **Step 3: Verify.** `xcodegen`; Debug, Release (`xcodebuild -scheme NotchBuddy -configuration Release -derivedDataPath build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet`, from `NotchBuddy/`) and App Store target builds succeed; `bash scripts/check-app-binary.sh <each .app> debug|release|appstore` pass. All of: `bash scripts/test-settings-{rules,map,ai,contrast,wiring}.sh`, `bash scripts/check-settings-render-private.sh`, `bash scripts/test-cat-wiring.sh`, `bash scripts/test-cat-settings.sh`, `bash scripts/test-wardrobe-wiring.sh`, `bash scripts/test-cat-desktop-wiring.sh`, `bash scripts/test-island-tuck-away-wiring.sh`, `bash scripts/test-hook-install-note.sh`, `bash scripts/test-sidekick-wiring.sh`, `bash scripts/test-sidekick-settings.sh`, `bash scripts/test-link-wiring.sh`, `bash scripts/test-u1-wiring.sh`, `bash scripts/test-shortcuts.sh`, `bash scripts/test-claude-code.sh`, `bash scripts/check-no-leftovers.sh`, **[focus]** `bash scripts/test-focus-aware-wiring.sh`. `wc -l NotchBuddy/Sources/App/SettingsView.swift` is under 400. Render the full set once more (`bash scripts/render-settings.sh --stress`) and compare with checkpoint 1: unchanged except what the owner asked.
- [ ] **Step 4: CI.** Add `bash scripts/test-island-tuck-away-wiring.sh` to `build.yml` if it is not there yet (`Island tuck away wiring (source pins)`), after the `Settings wiring` step.
- [ ] **Step 5: Commit** with `feat(settings): six pages in the new shell; the old sections go`.

---

### Task 13: Docs and names

**Files:** `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md`, `docs/INTEGRATIONS.md`, `docs/PROJECTS-CONTRACT.md`, `NotchBuddy/Sources/App/PillCatalog.swift` (comment only)

- [ ] **Step 1: CLAUDE.md.** One bullet in "Where things are", after the `ShortcutLogic.swift` bullet:
  > - Settings on the Mac (`docs/superpowers/specs/2026-10-17-settings-restyle-design.md`): six pages (General, Agents, AI and chat, Services, Cat, Devices) and their tabs (General: General, Shortcuts; AI and chat: Your AI, Keys, Local models, Sidekick, and a hidden Companion; Cat: Look, Outfits, Personality, Agents' cats) in `SettingsRoute.swift` with `migrate` for old `settingsSection` tags and `settingsTab.<page>`; the widths in `SettingsLayout.swift` (415 × 420 minimum, icon sidebar under 600, a 640 pt column); the drafts (`SettingsDraftBook`, `SettingsDrafts`), status words (`SettingsStatus`), the Sidekick tab's rules (`SettingsSidekick`) and the AI rows with Make main (`SettingsAI`) are pure. `SettingsMap.swift` and `tests/fixtures/settings/controls.json` name every control's home and stored keys; `scripts/test-settings-map.sh` fails if a stored key is lost, renamed or homed twice. The kit (`SettingsShell`, `SettingsPage`, `SettingsCard`, `SettingRow`, `SwitchRow`, `KeyRow`, `StatusChip`, `WrapRow`, `PathDisclosure`, `HelpText`, `SettingsTabBar`, `SettingsBanner`) keeps words whole and buttons untruncated at any width; the page views (`Settings{General,Agents,Services,AI}Page.swift`, `SidekickSettingsView`, `CatSettingsView(tab:)`, `ShortcutsSettingsView`, `DevicesSettingsView`) take plain values; `SettingsSections.swift` and `SettingsController.swift` are the only Settings files that read `AppState`, the Keychain or `HookServer`. `bash scripts/render-settings.sh` draws every page and tab at 415/720/1100 in dark or light (`--appstore`, `--stress`, `--states`, `--kit`) without the app; `scripts/check-settings-render-private.sh`, `test-settings-{rules,map,ai,contrast,wiring}.sh` are its tests. The never-restyle rule is lifted for Settings only.
- [ ] **Step 2: ARCHITECT.md.** In "Code map" or after "Main flows" item 7, a short paragraph "**Settings (Mac).**": the three layers (pure rules and the control map, the kit and plain-value pages drawn by `render-settings.sh`, the app side in `SettingsController` and `SettingsSections`), that Make main writes only `aiChoices.chat`, and that the Windows/Linux Settings gets the same pages in its own plan.
- [ ] **Step 3: docs/SPEC.md.** Replace the list under "## 10. Barre de menus et réglages" ("Fenêtre Réglages … sections dans l'ordre d'affichage" down to "**Startup**") with the six pages in French: **Général** (onglets Général et Raccourcis : Son, Île (Open on hover, Hover glow, Tuck the island away, Close after N secondes), Sur l'île (pastille principale, « N of 4 slots used » avec les noms, liens vers les pages), Démarrage ; Raccourcis : raccourcis globaux et ceux de l'île) ; **Agents** (Sur l'île : les interrupteurs des agents ; une carte par hooks Claude Code, Gemini CLI, Antigravity, Codex avec état, Install/Uninstall, aperçu et Confirm & write, « Show path » ; Plan usage) ; **AI and chat** (Your AI : Which one answers, Choose your AI avec Use my Claude plan, Use my OpenAI plan (« Coming with the new chat »), les clés et les modèles locaux, chacun avec son état et Make main, qui ne change que Chat ; Keys : une carte par fournisseur (Anthropic avec le modèle, Google AI, OpenAI), clé au Trousseau, interrupteur de la pastille ; Local models ; Sidekick : un interrupteur par sorte de note, l'exemple, Quiet times et Today so far à venir avec F3a, d'où viennent ses mots, les notes en sourdine) ; **Services** (une carte par service avec sa clé, son interrupteur « Show on the island » et son propre Save) ; **Cat** (onglets Look, Outfits, Personality, Agents' cats) ; **Appareils** (inchangé). Then one paragraph: la mise en page (415 × 420 au minimum, barre latérale en icônes sous 600 pt, colonne de 640 pt au plus, aucun mot coupé, aucun bouton tronqué, texte d'aide de 12 pt, chemins derrière « Show path » avec `~`) ; une ancienne valeur de `settingsSection` mène à sa nouvelle page ; aucune clé enregistrée ne change. In "### 13.3 Réglages", replace a mention of "Settings → Shortcuts" or the Hotkey group by "Réglages → Général → Raccourcis" (the Hotkey group no longer exists: the shortcut lives only there). In "### Le compagnon (sous-projet F1)", replace "Settings → Sidekick" by "Réglages → AI and chat → Sidekick" and say a kind can be switched off there (`mute`).
- [ ] **Step 4: Names.** `docs/INTEGRATIONS.md` line 103: "le catalogue Active pills" → "les interrupteurs des pages Agents, AI and chat et Services". `docs/PROJECTS-CONTRACT.md` line 203: "in the Active pills" → "among the active pills (`activeIntegrations`)" (the rule is unchanged). `PillCatalog.swift`'s comment on `available`: "Settings → Active pills" → "Settings' pill switches (Agents, AI and chat, Services)". `grep -rn "Active pills\|Settings → Integrations" NotchBuddy/Sources docs/SPEC.md docs/INTEGRATIONS.md docs/PROJECTS-CONTRACT.md CLAUDE.md ARCHITECT.md` prints nothing.
- [ ] **Step 5:** `bash scripts/test-settings-wiring.sh`, `bash scripts/check-no-leftovers.sh`, `bash scripts/test-projects-contract.sh` (if present) pass. **Commit** the six files with `docs(settings): the six pages in CLAUDE.md, ARCHITECT.md and SPEC.md`.

---

### After Task 13: whole-branch review

`nm-reviewer-deep` (Sonnet 5.5, high, trigger 4) on `git diff main...HEAD`, with `security-review` loaded and `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` beside it (`model: sonnet`). It checks: every control of the spec's map has a home and every stored key its name (`test-settings-map.sh` and a read of the old `SettingsView` in `main` against the new files); every moved action body is today's (diff them function by function); no key is ever in a picture, a log, a fixture or a page file; Save is always a click and a half-typed key is never written by navigation; the App Store build has no Claude plan, OpenAI plan, Gemini/Antigravity/Codex card, Plan usage or Music card; no timer, observer or poll was added (the only `NotificationCenter` use is the Devices section's existing window watcher); `preferredCloud` is no longer written by a key save; Make main writes only Chat; the install flows keep backup, diff and Confirm & write.

---

### Task 14: Owner checkpoints 2 and 3

**Checkpoint 2, the real window.** The owner builds and runs a Debug build himself (or asks the main session for a computer-use pass: then follow `use-computer-use-for-owner-checks`; the main session never replaces the running app on its own). Checks, each with the expected result:
1. Open Settings: it opens on the page it was on (a build from before shows the mapped page: from Shortcuts, General → Shortcuts).
2. Resize from the narrowest to full screen on each page and tab: at 415 the sidebar is icons with tooltips; nothing breaks inside a word; no button reads "…"; at full screen the cards stay 640 pt wide and centred.
3. Type in the Anthropic field, switch to Sidekick and back: the text is there with "Not saved"; close and reopen Settings: it is gone and the saved key shows masked.
4. Turn four pills on across Agents, Keys and Services: every other off switch is disabled with "4 of 4 slots used. Turn another off."; General's line is amber and names the four; a name opens its page.
5. Agents → Claude Code hooks → Install hooks: the preview opens, Confirm & write writes with a backup note, exactly as before.
6. AI and chat → Your AI → Make main on a running local model: the Chat picker above shows it, File questions keeps its own choice.
7. Sidekick → Stuck nudges off, then on; Show me an example draws inside the card; the island does not open.
8. The island's "Settings…" on an unconfigured service pill opens Services.

**Checkpoint 3, sign-off.** After the owner's go, the main session merges per its own process (never pushed by this plan), and the Windows/Linux Settings plan uses `controls.json` and the pictures as its starting point.

---

## Self-review

- **Spec coverage.** Goals 1 to 8: pages and tabs (Tasks 2, 4, 12), switches beside their owners and Active pills removed (Tasks 5 to 7, 10, 12 leftovers), provider-neutral Your AI with Make main and no credentials read (Tasks 3, 7, 11; answer 5's no-Google-plan pinned in Tasks 3 and 7), one key box per provider (Tasks 7, 11; the second Anthropic box and its `preferredCloud` side effect gone, call 3), the Sidekick tab (Tasks 1, 2, 8; answer 1 locked permission line), layout at any width (Tasks 2, 4, every page's `--stress` picture), nothing lost (Task 3's map test, Task 12's card-name pin), Mac first (the Windows plan follows checkpoint 1). The window (min size, sidebar, collapse, column, tabs, banner, drafts): Tasks 2, 4, 10, 12. Page rules 1 to 12: the kit (1 to 6, 8), the moved flows (7), migration (9), `pillSwitch` (10), drafts (11), card orders (12). Every page section: Tasks 5 to 8. Rows other plans add: the [focus], [projects] and Companion notes. Tests, checkpoints and proof: Tasks 2 to 4, 9, 12, 14. Calls 1 to 9 and builder calls 1 to 9: Task 5 (call 1), Task 6/10 (call 2), Task 11 (calls 3, 4, builder 2, 3), Task 4 (calls 5, 6, builder 8), Task 7 (call 7, 8 via `pills` excluding the Claude App), Task 2 (call 9, builder 5), Task 8 (builder 6, 9), Task 12 (builder 1, 7: no page shortcuts are added).
- **Placeholders.** None: wordings the spec leaves open are fixed here as Plan calls and reviewed at checkpoint 1.
- **Type consistency.** `PillSwitchModel`/`PillSwitchRow` (Task 6) are used by Tasks 7 and 10; `HookKind` (Task 6) by Task 10; `SettingsAI.Row`/`MakeMain` (Task 3) by Tasks 7 and 11; `SettingsRoute.Tab` by Tasks 4, 8, 12; `CatSettingsSection(tab:)` (Task 8) by Task 12; `SettingsDrafts.text/isDirty/isSaved/markSaved` (Task 10) match the closures of Tasks 6 and 7.
- **Proportion.** Code is given only where text is pinned (the Cat body, the fixture's key list, the test cases); the rest is signatures, rules and values.

## Dry run

Walked each task as its implementer against `main` at `414d89e6`:

- Present once each: `@AppStorage("settingsSection") private var selectedSection: String = "general"`, `win.contentMinSize = NSSize(width: 640, height: 420)`, `default:                 section = "integrations"` (IslandViewContent.swift:2368), `struct ConnectClaudePlanView: View {` (ClaudeChatViews.swift:179, inside the file-wide `#if !APPSTORE` of lines 9 to 252), `api.unmute = (state, kind) =>` (sidekick-core.js:900), `run('a whole number is 1'`, `func unmuted(_ kind: String)`, the store's `unmute`, the test's dismiss/unmute ternary, `struct DevicesSettingsView`, the `WardrobeSettingsGroup(store: store, active: active, day: wardrobeDay)` line. `host.sizingOptions = [.minSize]` occurs three times (Settings and two Debug panels): the anchor says 3.
- Every frozen key literal of Task 3 was grepped in `NotchBuddy/Sources/App` and found (none at zero). The spec's table names `localModelMemory` as a key: the real UserDefaults key is `aiLocalModels` (`AppState.swift:166`), and the plan uses the real one. `claudeHooksInstalled()` exists only in the GitHub build (`HookServer.swift:908`, inside `#if !APPSTORE`): the App Store Claude card has no installed chip (Task 10).
- Pins that read files this plan changes, beyond the spec's six: `tests/CatSettingsTests.swift` (reads `SettingsView.swift`), `tests/WardrobeWiringTests.swift` and `tests/DesktopCatWiringTests.swift` (read `CatSettingsView.swift`'s group order and `Toggle("Cat on the desktop"`, `Text(desktopNote)`), and `tests/SidekickWiringTests.swift` lines 142 to 144 (the Sidekick view's rows). Each is moved in the task that changes its file (Task 8 or 12).
- `SidekickSettingsView.swift` is one of the 21 files of `SidekickWiringTests`' forbidden-token check (`#if`, `Timer`, `repeats`, `UserDefaults`, `print(` …, comments included): the Sidekick tab's rules went into a new `SettingsSidekick.swift` (not a `Sidekick*` name, which no glob checks but the list's comment counts), and Task 8 warns the implementer.
- `scripts/render-sidekick.swift` calls `SidekickSettingsView(store:found:)` and `scripts/render-link.swift` calls `DevicesSettingsView(…)`: both inits are kept. `scripts/render-cat-settings.sh` compiles a fixed list: Task 8 adds the kit files `CatSettingsView` now needs.
- `ShortcutRecorderButton`, `HookNoteLine`, `IntegrationFilterRow`, `SettingsSidebarRow`, `SidebarBackground` live at the bottom of `SettingsView.swift`; the page views use them, so Task 12 keeps them there rather than moving them.
- `LocalServerRow` and `ConnectClaudePlanView` are used only by `SettingsView`; Tasks 7 and 11 replace those single lines with placeholders so the build stays green until Task 12 deletes the old sections (first draft deleted them without that and would have broken the build between tasks).
- `dismiss-cases.json` is replayed by Node (`tests/sidekick/settings.test.mjs`, `windows/scripts/sidekick-tests/fixtures.test.mjs`, both call `core[o.op]`, so `mute` works unchanged) and by Swift (`SidekickSettingsTests`, a two-way ternary that would treat `mute` as `unmute`): Task 1 Step 4 changes it to a three-way switch.
- `AppDelegate.openSettings` makes a new window (and a new `SettingsView`) whenever the old one is not visible, so `@StateObject` drafts die with the window: rule 11's "dropped when the window closes" needs no window observer.
- `AIService.cloudModel(.google)` can be empty (Google has no `defaultModel` in `AICatalog`): Make main says "Pick a model for it in the chat first." instead of storing an empty model (Task 3).
- The spec's control-map table lists `Active pills: Claude Code…` and the Claude App pill: `PillCatalog.available` already filters `agent_claude-desktop`, and `pills(state:ids:)` builds only available ids.
- Owner update during writing (answer 5): the Google plan row was removed from `SettingsAI.rows`, the samples and the pins (a pin asserts no "Google plan" title).
- Commands checked to exist: `scripts/test-sidekick-contract.sh`, `scripts/gen-sidekick-ts.mjs --check`, `windows/package.json`'s `check:sidekick` (run directly with `node --experimental-strip-types --test` so `windows/node_modules` is not needed), `scripts/render-home-guard.sh` (`render_home_guard`), `scripts/check-app-binary.sh <app> debug|release|appstore`, the App Store scheme `NotchMeowAppStore`.

## Review fixes (2026-10-17, after nm-reviewer-deep's plan review)

Each finding was confirmed by grep against `main` at `414d89e6` before the fix.

1. **Critical, the App Store build broke at Task 3.** `ClaudeCodeStatus` is inside `#if !APPSTORE` (`AI/Core/ClaudeCodeLocator.swift` line 8, and so are `ClaudeCodeText` and `ClaudeCodeEngine`). Fixed: `SettingsAI.ClaudeState` (same five cases) in `Input` and in `ClaudePlanDetails.state`; `aiInput` maps the real status inside `#if !APPSTORE` (Task 11, pinned). Task 4 Step 3 and Task 7 Step 4 now build the App Store target too.
2. **Critical, Task 8 broke the build.** `SettingsView.swift:214` calls `CatSettingsSection()` until Task 12. Fixed: `var tab: SettingsRoute.Tab? = nil` (nil shows every group).
3. **Important, Claude Code was no longer checked when Settings opened.** `ConnectClaudePlanView` ran its check on appear (`ClaudeChatViews.swift:216`). Fixed: Task 12 calls `controller.checkClaude()` (GitHub build) when the user arrives on AI and chat, beside `discover()`.
4. **Important, the column jumped at the breakpoint.** With 560 the column was 471 pt at 559 and 320 pt at 560, narrower than the 415 pt window's 327. Fixed: the breakpoint is 600 (Plan call in Global Constraints; the column is 360 at 600). Task 2 tests 559, 560, 599 and 600 and checks every width from 415 up. Review Focus 1, checkpoint 1, CLAUDE.md and SPEC.md now say 600.
5. **Important, the AI pills had lost their chips.** Rule 10 chips were missing for those pills: today's `pillRow` shows "Key not configured" (cloud) and "Not connected" (local) (`SettingsView.swift` around line 1330). Fixed: `pills(state:ids:)` sets both (Task 10, pinned), and `SettingsStatus.tone` makes them warn.
6. **Important, the stress cases had gaps.**
   - Fixed: Task 6 restyles `IntegrationFilterRow` (12 pt, names wrap, small buttons in a `WrapRow`, not `.mini`; pinned).
   - Fixed: the stress samples add a long workflow name, a hyphenated project name and a long agent name.
   - Fixed: unspaced model IDs are shown only in one-line fields or pop-ups, never in wrapping text. Task 7 Step 4 now expects the Custom field to scroll; it no longer expects the ID to wrap.
7. **Minor, anchor 9 printed 0.** Its `$0` is a regex anchor, so `grep -c` printed 0 on macOS (confirmed: `grep -cF` prints 1). It now uses `grep -cF`, and so does the ternary anchor beside it, for safety.
8. **Minor, the Release build.** Task 12's Release command now carries `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`.
9. **Minor, the tab and the banner.**
   - The tab is now held in `@State` and written to `settingsTab.<page>` on change (pinned).
   - The title, tab bar and banner sit above the scroll area (Task 4's `SettingsPage`).
10. **Minor, SPEC.md wording.** SPEC.md's page list said "Chat" for the Cat page; it now says "Cat".
11. **Minor, the coat grid count.** The grid with `.adaptive(minimum: 66)` is described as about six tiles at 720 pt and four at 415, not five.
12. **Minor, Task 10's Produces list.** It now names `geminiPendingInstall`, `agyPendingInstall`, `codexPendingInstall`, `uninstallRelay()` and `cancelRelay()`, and maps the Plan usage card's actions.
13. **Minor, the Sidekick picture's height.** `scripts/render-sidekick.swift` (fixed height 470) joins Task 8's files, and its settings picture takes the view's own height.
14. **Minor, the island's AI buttons.** They posted `chat`, which opened the last tab used. Fixed:
    - `SettingsRoute.migrate` accepts `<page>/<tab>` (tested).
    - The island posts `chat/keys` for an unconfigured AI pill and for "Add a cloud key", and `chat/yourai` for "Connect Claude".
    - `perform(.openSettings)` keeps `chat`. All of this is pinned in Task 12.

Dry run of the touched tasks:
- Re-walked Tasks 0, 2, 3, 4, 6, 7, 8, 10, 11 and 12.
- The gated files in `AI/Core` are the eight `Claude*` files. `ModelRouter`, `AICatalog` (`ClaudeCodeModel`), `Discovery` (`ServerStatus`) and `ModelProvider` are in every build, so `SettingsAI` compiles in the App Store target.
- `IslandViewContent.swift` has `case .ai:                section = "chat"` once (line 2367) and `object: "chat")` three times. After the change: one `chat/keys`, one `chat/yourai`, one `chat`.
- `grep -cF` prints 1 for both fixed anchors.
- The new column numbers follow `detailWidth - 2 × padding`:
  - 415: 359 − 32 = 327
  - 559: 503 − 32 = 471
  - 560: 504 − 32 = 472
  - 599: 543 − 32 = 511
  - 600: 400 − 40 = 360
  - 720: 520 − 40 = 480
- `render-sidekick.swift:156` was confirmed as the fixed frame.

### Main-session fixes after the re-check (2026-10-17)
- Task 12, the island's tags: an AI pill's tag comes from `SettingsMap.pillHome` (`chat/keys` for a cloud provider, `chat/localmodels` for Ollama and LM Studio), pinned, instead of `chat/keys` for every AI pill.
- Task 12's Sidekick pin matches `sidekick` inside the `Tab` enum (the tabs share one `case` line), so it can pass.
- The spec's breakpoint now reads 600 pt (lines 76, 275, 298), matching this plan.
