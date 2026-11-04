# Settings (Windows and Linux) polish: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Close what the first Windows/Linux Settings restyle (`docs/superpowers/plans/2026-10-18-settings-restyle-tauri.md`, merged as `76c4ac71`) left parked: three inherited silent failures (an unreadable credential store looks like "No key yet", a failed `settings.json` save is invisible, a failed settings read shows defaults without a word), one flaky Rust test, every parked minor of that plan's ledger, and the residuals of its final report.

**Owner approval:** the owner said "polish and fix all of it" (relayed by the main session, 2026-10-20). Same SDD rules as the first plan. Branch `settings/tauri-polish` from `76c4ac71`.

**Spec:** `docs/superpowers/specs/2026-10-17-settings-restyle-design.md` (unchanged), plus the first plan's Global Constraints, which still bind.

## Global Constraints

- **The first plan's Global Constraints apply**, in particular: TypeScript and plain DOM, no new dependency (no npm package, no crate); Rust only through `windows/scripts/cargo-linux.sh` with `--target-dir /repo/windows/target/settings-tauri` and the Windows check with `windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-settings-tauri` (Docker is running; never `docker build` or `docker pull`); never push, merge or stash; commit locally per task with `git commit -F <file>`; secrets only through the OS credential store and never read back by the page; no timers, polls or observers added (the one-shot listeners already allowed stay); a page's `sync()` never writes the control in use; words never break inside a word and buttons never truncate; no colour literals outside the tokens in `settings.css`; island (`src/style.css`, `src/link/link.css`, `windows/hook/`, `island/hooks.ts`), Mac, `shared/` and generated files stay untouched, except where a task names one file.
- **`trash`, never `rm -rf`**, for every deletion including picture folders (`/usr/bin/trash` exists).
- **Never treat an unreadable credential store as an absent key**: no key may be overwritten, removed or shown as "No key yet" because a read failed.
- **A save that fails is never shown as saved**: the control goes back to the stored value and the card that saved says so.
- **Defaults are never written over the user's file** because the file could not be read; only an intentional change (or the explicit "Start fresh" button) may.
- **Models** (CLAUDE.md): Haiku 5.5 first (`nm-implementer`, `nm-implementer-light` for given-text work), `nm-implementer-deep` only on trigger 1 or 2 (named in the ledger); task reviews `nm-reviewer`; the whole-branch review `nm-reviewer-deep` with `security-review`, plus `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` (`model: sonnet`). Never Opus or Fable.
- **SUBAGENT RULES** are in the workspace's `rules.md` (copied from the first plan's list; the trailer is `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`).

## File structure (what the tasks touch)

| Path | Task |
|---|---|
| `windows/src-tauri/src/secrets.rs`, `lib.rs` (`secret_present`), `windows/src/core/bridge.ts`, `windows/src/settings/{backend,drafts,status,kit,ai,services,app,devseed}.ts` | 1 |
| `windows/src-tauri/src/settings.rs`, `lib.rs` (`save_settings`), `windows/src/core/bridge.ts`, `windows/src/settings/{backend,ctx,app,kit,shell}.ts` | 2 |
| `windows/src-tauri/src/settings.rs`, `lib.rs` (boot), `windows/src/core/bridge.ts`, `windows/src/settings/{backend,app,shell,devseed}.ts` | 3 |
| `windows/src-tauri/src/files.rs` | 4 |
| `windows/scripts/settings-tests/*`, `windows/src/settings/{sidekicktab,layout,airows,aicache}.ts` and pins | 5 |
| `windows/src/settings/{ai,aicache,agents,services,kit,shell,app,devices,devseed,cat,tabbar}.ts`, `windows/src/core/state.ts`, `settings.css` | 6 |
| `windows/src-tauri/src/{lib.rs,hooks.rs}` | 7 |
| `windows/src/settings/{devices,devseed,devpanel,kit,main}.ts`, `settings.css`, `windows/scripts/check-settings-layout.sh`, `windows/scripts/settings-tests/{kit,pages}.test.mjs` | 8 |

## Tasks and agents

| # | Task | Agent, model | Review |
|---|---|---|---|
| 1 | Presence is tri-state (present, absent, unreadable) | `nm-implementer`, Haiku high | `nm-reviewer` |
| 2 | A failed settings save is visible and reverts | `nm-implementer`, Haiku high (deep after two failures, trigger 2) | `nm-reviewer` |
| 3 | A failed settings read is visible and never writes defaults | `nm-implementer`, Haiku high (deep after two failures, trigger 2) | `nm-reviewer` |
| 4 | The flaky `ingest` test gets its own temp dir | `nm-implementer-light`, Haiku medium | `nm-reviewer` |
| 5 | Parked minors A: tests, pins and pure rules | `nm-implementer`, Haiku high | `nm-reviewer` |
| 6 | Parked minors B: page behaviour | `nm-implementer`, Haiku high | `nm-reviewer` |
| 7 | Parked minors C: Rust (logs, hook notes) | `nm-implementer`, Haiku high | `nm-reviewer` |
| 8 | Residuals of the final report | `nm-implementer`, Haiku high | `nm-reviewer` |
| After 8 | Whole branch | `nm-reviewer-deep` + `security-review`, `silent-failure-hunter`, `pr-test-analyzer` (sonnet) | one fix wave |

## Ledger of parked items

The workspace's `progress.md` carries the table of every parked minor of the first plan's ledger and of its final reviews, each with a disposition (`fixed in Task N` or `ruled out: why`), updated as tasks complete.

---

### Task 1: Presence is tri-state

**Files:** `windows/src-tauri/src/secrets.rs`, `windows/src-tauri/src/lib.rs`, `windows/src/core/bridge.ts`, `windows/src/settings/backend.ts`, `drafts.ts`, `status.ts`, `kit.ts`, `ai.ts`, `services.ts`, `app.ts`, `devseed.ts`, tests under `windows/scripts/settings-tests/`.

**Rust.**
- In `secrets.rs` add `pub enum Presence { Present, Absent, Unreadable }` (serde `rename_all = "lowercase"`, `Serialize`) and `pub fn presence(key: &str) -> Presence`: a key outside `is_allowed` is `Absent`; `Entry::new` failing is `Unreadable`; `get_password()` returning `Ok(v)` with a non-empty `v` is `Present`, `Ok("")` is `Absent`; `Err(keyring::Error::NoEntry)` is `Absent`; **every other error** (`NoStorageAccess`, `PlatformFailure`, `Ambiguous`, `BadEncoding`, any other variant) is `Unreadable`. Put the classification in a pure `fn classify(result: Result<String, keyring::Error>) -> Presence` so a test covers each variant without a keychain.
- Keep `present()` and `get()` as they are for every Rust-side user (the AI router, the pollers): a key that cannot be read cannot be used.
- **Add** a command `secret_presence(key) -> Presence` (register it in the invoke handler list). **Keep** `secret_present(key) -> bool` and `Bridge.secretPresent` exactly as they are: the island's own pages call them (`windows/src/island/integrations.ts:31`, `windows/src/views/chat.ts:433`) and must not change. Only the Settings window moves to the new command.
- Rust tests: `classify` for `Ok("x")`, `Ok("")`, `NoEntry`, `NoStorageAccess`, `PlatformFailure`, `BadEncoding`; and that `presence` of a key outside the allow list is `Absent`.

**TypeScript.**
- `Bridge.secretPresence(key): Promise<"present" | "absent" | "unreadable" | null>`; `null` (the bridge's failure value) is treated as `"unreadable"` by the Settings backend, never as absent.
- `SettingsBackend.secretPresence(key): Promise<Presence>` (`Presence = "present" | "absent" | "unreadable"`), replacing the Settings backend's `secretPresent`. `app.ts` loads the eleven keys with it. `DraftBook` keeps presence as `Record<string, Presence>`-like state: `isSaved(id)` is true only for `present`; add `isUnreadable(id)`; `markSaved(id, present: boolean)` keeps its meaning (present or absent after a write), `setPresence(id, presence)` replaces `setPresent`. A typed draft is kept across a presence change.
- Pages: where a key is `unreadable`, `keyField` is **disabled** with the placeholder "Can't read the credential store", Save is disabled, Remove is not shown, the card's chip is "Couldn't read" (warn tone), and a `help` line says "Couldn't read the credential store." with a **Check again** button (wrapRow, not primary) that re-asks `secretPresence` for that key once and repaints. Services (`services.ts`) and the AI Keys tab (`ai.ts`) both do this; the Your AI rows treat `unreadable` as "not ready" with the chip "Couldn't read the credential store" (never "No key yet"), via `airows.ts` input: `keys` becomes the providers that are `present`, and a new `unreadable: readonly KeyProvider[]` input selects the chip (`airows.ts` is a pure Task 2 file of the first plan: keep every existing export and its tests; add the field optional with default `[]`, and extend the tests).
- `status.ts`: `keyChip(saved)` stays; add `presenceChip(p: Presence): string` → `"Ready"` is not its job: it returns `"Couldn't read"` for unreadable and defers to `keyChip` otherwise; add `"Couldn't read"` to `tone()` as warn.
- Never enable Save as if empty, never call `secretSet` or `secretClear` for a key that is unreadable (pin: the save and remove handlers return early when `isUnreadable`).
- Devseed: the `error` sample makes one Services key and one AI key `unreadable` (the two other keys stay present or absent as before), so the pictures show it.
- Tests (written first): `rules.test.mjs`/`pages.test.mjs` pins for the above; a behaviour test of `DraftBook` (unreadable is not saved, not dirty, typed text kept, `setPresence` after Check again); `airows.test.mjs` for the chip; the Rust tests above.

**Verify:** tsc, `check:settings`, `check:cat`, `check:link`, `check:ai`, `check:claude`, Rust full run and Windows check; render `--page services --state error` and `--page chat --tab keys --state error` at 415 and read them.

**Commit:** `feat(settings/tauri): an unreadable credential store says so; presence is present, absent or unreadable`.

---

### Task 2: A failed settings save is visible and reverts

**Files:** `windows/src-tauri/src/settings.rs`, `lib.rs` (`save_settings`), `windows/src/core/bridge.ts`, `windows/src/settings/{backend,ctx,app,kit,shell}.ts`, tests.

**Rust.**
- `save_settings(...) -> Result<(), String>`. The disk write now comes **first**: `settings::save(&settings)` must succeed before the shared copy is replaced, the autostart or screen side effects run, or `settings-changed` is emitted. On failure return `Err("Couldn't save the settings.".into())` (a fixed sentence: no path, no OS text) and log the fixed line `settings.json could not be saved` with `crate::log::line`. Extract the ordering into a pure, testable function in `settings.rs`: `pub fn commit(current: &Mutex<Settings>, next: Settings, write: impl Fn(&Settings) -> std::io::Result<()>) -> Result<Settings /* the previous value */, std::io::Error>`: it writes first, then swaps; on a failed write `current` is unchanged. Tests: a failing `write` leaves `current` untouched and returns `Err`; a succeeding one swaps and returns the previous.
- The island's own saves (`Bridge.saveSettings`, fire and forget) keep working: when the write fails they now do not change the shared copy either; the island's page keeps its own copy and the next successful save sends the whole struct (note in the report).

**TypeScript.**
- `bridge.ts`: a checked variant of `call`: `callChecked<T>(cmd, args): Promise<{ ok: true; value: T | null } | { ok: false; error: string }>` (outside Tauri: `{ ok: true, value: null }`). `Bridge.saveSettings` keeps its old fire-and-forget behaviour (island callers unchanged); add `Bridge.saveSettingsChecked(settings): Promise<boolean>` (true on success).
- `SettingsBackend.save(settings): Promise<boolean>` (was `Promise<void>`); the bridge backend uses `saveSettingsChecked`; the dev backend returns `true`, and under the `error` sample `?failsave=1` returns `false` once so a picture can show it.
- `app.ts`: track `stored` = the last settings Rust confirmed (boot, each `settings-changed`, each successful save). `ctx.save(next)`: capture `document.activeElement` **synchronously**, apply `next` locally (as today), `await backend.save(next)`; on `true` set `stored = next`; on `false` set `settings = stored`, run the revert sync with **forced values** (below), and show the notice **"Couldn't save."** in the card that contained the captured element (`closest(".st-card")`); if no card contains it, show it in a page-level strip at the top of the column. Only the latest save's failure reverts (a sequence number), and a later successful save or any page change clears the notice. `ctx.save` returns `Promise<boolean>`.
- `kit.ts`: `forceValues(fn)` runs `fn` with a module flag set so `setValue` ignores the "is the active element" guard (the control that just changed must go back); `cardNote(card, text)` / `clearCardNote(card)` add and remove one `.st-cardnote` notice node at the top of a card (`notice("err", text)` styled by existing rules; no colour literals). `shell.ts` exposes `banner(text | null)` for the page-level strip.
- Tests (first): `app.ts`/kit source pins; a **behaviour test with a rejecting fake backend** (a small DOM-free harness: extract the revert decision into a pure `saveOutcome(stored, next, ok)` in `status.ts` or a new `savestate.ts` returning what to store and whether to show the note, tested for ok, failed, and the sequence rule); Rust `commit` tests.

**Verify:** tsc, `check:settings`, `check:cat`, `check:link`, Rust full and Windows check; render `--page general --state error` with `&failsave=1` and read the notice.

**Commit:** `feat(settings/tauri): a failed settings save says so and the control goes back to the stored value`.

---

### Task 3: A failed settings read is visible and never writes defaults

**Files:** `windows/src-tauri/src/settings.rs`, `lib.rs` (boot, a shared problem field, three commands), `windows/src/core/bridge.ts`, `windows/src/settings/{backend,app,shell,devseed}.ts`, tests.

**Rust.**
- `settings::load_checked() -> (Settings, Option<LoadProblem>)`, `LoadProblem` = `Unreadable` (the file exists but cannot be read) or `Unparseable { kept_as: String }` (parsed badly; `load_with` already keeps a `.bad-<stamp>` copy: carry its **file name** only). A missing file is not a problem. `settings::load()` stays (calls `load_checked().0`). `load_with` gets the test seam it already has.
- At startup (`lib.rs` ~line 580) keep the problem in the shared state: `Shared.settings_problem: Mutex<Option<LoadProblem>>`. `BootInfo` gains `settings_problem: Option<SettingsProblem>` serialised as `{ kind: "unreadable" | "unparseable", keptAs?: string }`.
- While the problem is `Unreadable`, `save_settings` returns `Err("Your settings file couldn't be read.".into())` and writes nothing (the island's automatic saves therefore cannot overwrite a file it never read). Two new commands: `settings_retry_load()` re-reads the file; on success it replaces the shared settings, clears the problem and emits `settings-changed`, returning the settings (or `Err` if it still fails); `settings_start_fresh()` clears the problem so saves are allowed again (the user's explicit choice to replace the unreadable file). For `Unparseable` the backup already exists, so saves stay allowed; the problem is reported once at boot (`settings_problem` stays in `BootInfo` for the session; `settings_retry_load` is also allowed).
- Tests (Rust, first): `load_checked` for missing file (no problem), unreadable (use a directory at the path so `fs::read` fails with a non-NotFound error), unparseable (problem names the `.bad-…` file, no content), valid; the refusal gate as a pure function `fn save_allowed(problem: &Option<LoadProblem>) -> bool`.

**TypeScript.**
- `BootInfo.settingsProblem`, `Bridge.settingsRetryLoad()` (checked variant: returns the settings or an error) and `Bridge.settingsStartFresh()`; matching `SettingsBackend` methods.
- A boot where `backend.boot()` returns `undefined` (the command itself failed) is the same condition: `app.ts` treats it as `{ kind: "unreadable" }` with the in-memory defaults and **does not save** until the user chooses.
- `shell.ts` banner (page-level strip above the column, same element Task 2 added): text "Your settings couldn't be read, so you are seeing defaults. Nothing is saved until you choose." with **Try again** (re-load) and, for `unreadable`, **Start fresh** (accept defaults; then saves work); for `unparseable`: "Your settings file couldn't be read. It was kept as <name>; you are seeing defaults." with Try again and a dismiss. Words from the app's plain voice; the file **name** only, never a path. After a successful retry the banner goes and the pages `sync()` from the loaded settings (forced). While the problem stands, `ctx.save` shows Task 2's "Couldn't save." (Rust refuses) rather than pretending.
- Tests (first): the boot-failure branch in `app.ts` (pins); a pure `bootState(boot)` in `status.ts` returning `{ settings, banner }` tested for undefined boot, unreadable, unparseable, none; the Devseed `error` sample shows the banner via `?bootproblem=unreadable|unparseable`.

**Verify:** tsc, `check:settings`, `check:cat`, `check:link`, Rust full and Windows check; render with `&bootproblem=unreadable` and read it.

**Commit:** `feat(settings/tauri): a settings file that can't be read says so, and defaults are never written over it unasked`.

---

### Task 4: The flaky `ingest` test gets its own temp dir

**Files:** `windows/src-tauri/src/files.rs` (test module only).

`ingest_copies_and_never_overwrites` builds `std::env::temp_dir().join(format!("notchmeow-test-{}", std::process::id()))`, which two tests of the same process (or a leftover from an earlier run with the same pid) can share; it failed once in a full run and passes alone. Give every test in that module its own directory: create it with a unique name (process id + a per-process atomic counter + a nanosecond timestamp) through a small `fn scratch(name: &str) -> PathBuf` helper that creates it fresh (removing a leftover first with `std::fs::remove_dir_all` — this is inside the test's own `temp_dir` path, a test cleaning its own scratch is fine) and remove it at the end of the test. No other behaviour changes. Run the **full Rust suite three times** in a row; all three must pass.

**Commit:** `test(settings/tauri): the ingest test uses its own scratch folder`.

---

### Task 5: Parked minors A (tests, pins, pure rules)

**Files:** `windows/scripts/settings-tests/*.test.mjs`, `windows/src/settings/{sidekicktab,layout,airows,status}.ts`, `windows/scripts/cat-tests/agent-switch.test.mjs`.

Each item is its own test-first step; the workspace ledger lists the item ids.
- A1 `drift.test.mjs`: the tab-title pin scoped to `tabTitle`'s body (not the whole file).
- A2 `sidekicktab.ts`: `STUCK_NAMES` derived from `KIND_LABELS` (import) instead of a second copy; `layout.ts` `displayPath`: the two closures shrunk to one normaliser (behaviour identical: every `rules.test` case still passes).
- A3 `map.test.mjs`: the credential scan accepts any `key:` string property in `windows/src/settings/*.ts` that is passed to `secretSet`/`secretPresence`/`secretClear` or listed in a `SERVICES`/`CLOUD_PROVIDERS` field, not only `{ key, label }` and suffix names; the "card" check requires the literal to be a card title (a `card("<name>"` call or a listed constant), not any string.
- A4 `contrast.test.mjs`: add `--dim` and `--dim-2` over `--btn` and `--soft` (both palettes, ≥ 4.5), `--ink` over `--field`, the selected sidebar row's text over its fill, the tone dots over `--card` (3:1 for non-text, state it), `.check.bad` ink over `--card`; shrink `outsideTokens` to the one-line regex form.
- A5 `kit.test.mjs`: the `indexOf`-first-match pins become body-sliced (`await`/`dispose` pins), so a comment cannot satisfy them.
- A6 `agent-switch.test.mjs`: `fresh()` resets `State.kittens`.
- A7 tests the reviewers named (final-review-tests G9-G21, ids in the ledger): `aiInput` keeps servers regardless of status and `isMain`'s reserved ids (`airows.test`); `migrate` legacy-tag table pinned against `SettingsRoute.swift` (`drift.test`); the Cat card-to-tab mapping pinned (`pages.test`); the Sidekick radios' `withLocal` writes pinned; a pin that the default `activeIntegrations` holds four services (so both agent switches start disabled) so a change shows in review; drift pins for `claudeChip` words, `example()` lines, the `stuckSwitch` detail format and `DraftBook` semantics (words from `SettingsAI.swift`/`SettingsSidekick.swift`/`SettingsDraftBook.swift` as text).
- A8 `shell.ts` + `route.ts` rule (pure part): `select()` of an **unknown** well-formed place keeps the current page (a pure `placeOrCurrent(raw, current)` in `route.ts`, tested); a bare page remembers its last tab (a pure helper tested with an injected storage).

**Commit:** `test(settings/tauri): the parked minors of the first plan: pins, drift, contrast pairs and rules`.

---

### Task 6: Parked minors B (page behaviour)

**Files:** `windows/src/settings/{ai,aicache,agents,services,kit,shell,app,devices,devseed,cat}.ts`, `windows/src/core/state.ts`, `settings.css`, tests.

Each item test-first, its own pin or behaviour test:
- B1 `aicache.ts`: a generation counter so a `loadCloud` in flight when `forget()` runs cannot repopulate the removed key; a failed `aiDiscover` (undefined) keeps the last server list instead of wiping it (test with the fake backend).
- B2 `ai.ts`: `checkClaude` gets its own `try/catch` (a rejection sets the "Couldn't check Claude Code." state); `yourAiTab.sync()` calls `aiResolve` only when the settings or the key presence changed (a signature), not on every echo.
- B3 `services.ts`: the Save button has an in-flight guard (disabled while the write runs, re-enabled in `finally`); every Remove button gets `aria-label="Remove <field label>"`.
- B4 `kit.ts` `rowOf`: set `aria-labelledby` only on controls that have **no** accessible name of their own (no text content, no `aria-label`); `app.ts` comment "never overwrites" made true or corrected.
- B5 `shell.ts`: after choosing a tab (or page) with the keyboard, focus lands on the newly selected tab/nav button; the tab bar's `fit()` also runs when the window is shown (the `focus` and `visibilitychange` handlers `app.ts` already has call it).
- B6 `devices.ts`: on `settings-hidden` the Name field is restored to the stored name (it commits on blur today; a hide while focused must not keep typed text) — expose a `reset()` on the section and have the hide handler call it for the Devices page; pin it.
- B7 `app.ts`: `away` is cleared on the first `pointerdown` or `keydown` after a hide (re-armed at each hide; `{ once: true }`), so a tray show with no focus event still refreshes; `ai-servers-changed` is registered **before** the first `await`.
- B8 `core/state.ts` `toggleIntegration`: accepts only ids in `TOGGLEABLE_INTEGRATION_IDS` plus `AGENT_SWITCHES` ids (anything else returns); test.
- B9 ponytail shrinks, each only if the existing tests still pass unchanged: `app.ts` `drafts`/`book` duplicate variable; `shell.ts` `tabHost` wrapper; `ai.ts` `paintPref` memo → `painter`, `optionNodes` grouping, `fillSelect` signature, `checkMark` inline, the double "Saved." paint in `saveKey`; `airows.ts` `rowKey`, `claudeChip` inline; `aicache.ts` redundant `delete`; `agents.ts` kind maps and `switchState`/`stateOf` shared helper; `kit.ts` two `classList` toggles loop; `devseed.ts` orphan comment and `activeFor` taking `page` as a parameter instead of re-reading `location.search`.
- B10 dead CSS: `.path` and `.spacer` rules and the pin that keeps `.path` alive, only if `grep -rn` finds no user in `windows/src`.
- B11 `app.ts`/`kit.ts`: the Cat page `held` value cannot be lost or shadow an island change: when `settings-changed` arrives during a drag, keep the drag value until release, then reconcile with the latest event (test the pure `reconcile(held, incoming)`).

- B12 `ai.ts`: the added server's key (`CUSTOM_KEY`) writes in `addServer`/`removeServer` (`secretSet`, both `secretClear` sites) also go through `ctx.drafts.canWrite(CUSTOM_KEY)`; pin it.
- B13 `kit.ts` `checkAgain`: repaint first (so "Couldn't read" and the disabled field do not linger during the model fetch), then run `onPresent` (`loadCloud`), then repaint again; `.then` form instead of `void (async…)()`.
- B14 `services.ts` `saveAll`: when an unreadable typed field stayed unsaved the final notice says "Saved the readable ones." instead of "Saved. It never touches disk."; pin and outcome-test the choice with a pure helper.
- B15 `savestate.ts` `makeSaver`: a REJECTING `write` counts as a refusal (revert + note), `notePlacement` takes the card (`HTMLElement | null`) instead of a wrapper object, the settings-changed echo goes through `tidy()` like boot; trivial tests cut (`stored()` accessor stays as the test seam).

- B16 (from Task 5's review) `route.ts`: one `LEGACY` table read by both `migrate` and `placeOrCurrent` (no second copy of the four legacy tags), tests for `placeOrCurrent("integrations")` and `("shortcuts")` too; `app.ts` skips `shell.select` when `placeOrCurrent` returns the place already shown (no needless dispose/rebuild that would clear typing and the banner); `contrast.test.mjs` finds each CSS rule with a rule-anchored regex slice instead of first-match `indexOf`; one shared slicer helper for the three near-identical test slicers; the dev `initial` path (render pictures) is checked: a bare place with a stored tab must not change the pictures (they pass `storage: null`).

- B17 (from part 1's review) `ai.ts` and `services.ts` `removeKey`: return early while a Save for the same key/card is in flight (`writing` set), so a clear and a set cannot interleave; the `writing` sets live at module/ctx level (kept across a tab switch within the window's life) not inside the page closure; update the pins.
- B18 `drafts.ts` `markSaved`: after a successful write clear the typed text only if it still equals the text that was sent (text typed during the write is kept and the field stays dirty); `saveAll`/`saveKey` pass the sent text; outcome test.
- B19 `aicache.ts`: a rejected `aiListModels` keeps the held model list for that provider (a failed read is not an empty one) and records the failure in `works` so the Keys card shows the error; test with the fake backend.
- B20 `ai.ts` `refreshServers` (Rescan, Add server, Remove server paths): a rejected discovery is caught and the page says "Couldn't look for servers." in the card (kept list, no unhandled rejection); test the pure choice of note.

**Commit(s):** two commits, `fix(settings/tauri): the parked minors of the first plan, part 1: credential rows, saves and the AI cache` (B1-B5, B12-B15) and `fix(settings/tauri): the parked minors of the first plan, part 2: focus, refresh, devices, state and ponytail shrinks` (B6-B11, B16), each its own dispatch and review.

---

### Task 7: Parked minors C (Rust)

**Files:** `windows/src-tauri/src/lib.rs`, `windows/src-tauri/src/hooks.rs`.

- C1 `lib.rs`: the `let _ = app.emit(...)` of `settings-hidden` and `settings-place` (and the two other `emit` sites the silent-failure review named: `lib.rs:121` and `:284`) log the fixed line `could not tell the Settings window` through `crate::log::line` when the emit fails; `open_settings_window` logs `Settings place was not a page` when `settings_place` drops a value (fixed sentences only, never the value).
- C2 `hooks.rs`: the Claude hook flow's notice says "Backup → …" only when a backup was actually made (the file existed); when it did not, the note says "The file didn't exist, so it was created." (find the two sites, `hooks.rs` ~267 and ~294-303, and the TS words that render them in `agents.ts`); `hooks::status()` distinguishes "settings.json is not valid JSON" from "not installed" (a new `error: Option<String>` field, fixed sentence, `HookStatus` serialised to the page, shown by `agents.ts` as "Couldn't read settings.json." on the card instead of "Not installed"); tests in Rust for both, and the TS card words pinned.
- C3 (ruled in the ledger, no code): the diff shown for confirmation is rewritten with `~` for display only; the file keeps the real path.

- C4 `lib.rs` `hooks_apply` (~line 281): it ignores a failed `settings::save` and still emits `settings-changed`, so the window's stored value can claim `hooks_installed` that is not on disk. Make it honest: save first (through `settings::commit`), update the shared copy and emit only on success; on failure log the fixed line and still return the hook result (the hook files are written either way) with the page's notice words unchanged. Same for `ai/mod.rs` `store_learned` (~line 242-250): save first, then mutate the shared settings and emit, never emit a value the disk does not hold. Rust tests through the `commit` seam.
- C5 `settings.rs` `save`: write through a temp file and rename (as `hooks.rs` and `shelf.rs` do) so a crash mid-write cannot leave a file that boots as Unparseable; test with the seam (a failing rename leaves the old file intact and removes the temp).
- C6 `hooks.rs` tests: `writing_backs_up_preserves_and_refuses_a_changed_file` (and any other test that calls `std::env::set_var`) must restore the process environment: an RAII guard that sets `HOME` (or `XDG_*`) and restores the previous value on drop, serialised with a shared mutex for every test that mutates the environment (this is the root cause of the flaky ingest test found in Task 4). Grep every `set_var` in `windows/src-tauri/src` and fix each the same way.
- C7 `settings.rs` leftovers from Task 3's reviews: `read_only_at` logs "could not be read" for a present-but-unparseable file (reword to a fixed sentence that says what it is), one `unreadable()` tuple helper for the two repeated returns, make the `START_FRESH_*` consts private, drop a duplicated `save_allowed(&None)` assertion.

**Commit:** `fix(settings/tauri): failed emits are logged, a hook note names a backup only when one exists, an unreadable hook file says so, saves are atomic and honest`.

---

### Task 8: Residuals of the final report

**Files:** `windows/src/settings/{devices,devseed,devpanel,kit,main}.ts`, `settings.css`, `windows/scripts/check-settings-layout.sh`, `windows/scripts/settings-tests/{kit,pages}.test.mjs`, tests. (The review round added `kit.ts` (the non-short row's help line after its control, and the picker class) and `main.ts` (the font=wide route and the forget hook), which the table did not name; the tests are the two pin files.)

- D1 Devices machine rows use the kit's short-row rule: the name wraps, the state chip and the Forget/Pair buttons stay beside or under the name tidily with no overflow at 415, including the stress long name. The layout check gets a Devices machines case (`--stress`: a long-named machine; asserts no horizontal overflow and that chip and button are inside the row).
- D2 Add a server that is **running with no models** to the `ready` sample (Local models tab) and to the layout check, so the "Running, no models yet" chip is measured at 415; report its width vs the room.
- D3 The two select rows ("Tuck the island away", "Island lives on") at 415. The Mac was rendered (`scripts/render-settings.sh --page general --width 415`; picture `.claude/checkpoints/settings-tauri-polish/mac-general-415-dark.png`): the Mac STACKS "Tuck the island away" (label above its pop-up), puts "Main pill" beside its label, and its pop-ups are content-sized (~123-125 pt), not a fixed 180. Make the Windows selects content-sized with `max-width: 180px` (replace the fixed `width: 180px` of `.st-control select`, keep the pin consistent), so a row stacks only when label + select really don't fit: "Island lives on" then sits beside its label; "Tuck the island away" stacks if it does not fit (as on the Mac) or sits beside if it fits — either is correct; report which. The layout check asserts: no select row overflows at 415, and the ones that stack stack with the select inside the card.
- D4 A wide-font sanity variant of the layout check: `--font wide` swaps `--font` for a wide system font (Verdana/Trebuchet if present, else Arial at 1.1× letter-spacing) at 415 and asserts the same rules; this stands in for Segoe UI, which cannot be installed here (ledger the real-window check as still owed).

**Commit:** `fix(settings/tauri): the residuals of the first plan's final report`.
