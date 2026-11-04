# H-tauri The Desktop Cat Implementation Plan (Windows and Linux)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows/Linux Tauri app gets sub-project H: the user drags the **big cat** out of the notch and keeps it on the desktop as a companion. It floats above windows in a second transparent window that only its body takes the mouse in, shows what the big cat shows (its coat, state badge, collar, its agent's kittens, cursor-watching, sleep, and the music dance where a music source exists), flies back into the notch when an approval or a question needs the user and out again when they are answered, and costs almost nothing while it sits there (5 frames a second idle, a still frame every two seconds asleep, nothing when it cannot be seen). A tray item and a Settings → Cat switch take it out and bring it home, a click opens the island, a double-click sends it home, and a right-click menu has Open the notch, Send home and Size (Small Ø48, Medium Ø64 by default, Large Ø96). Whether it is out, its size and its spot (a spot per arrangement of screens) are remembered.

**Architecture:** Everything pure is a TypeScript port of `design/prototype/cat-core.js` (the tie-breaker), replayed in plain Node against `tests/fixtures/cat/desktop-cases.json` within 1e-9: `cat/desktop.ts` (the trip machine `desktopStep`, the flight `desktopFlightAt`, the frame rate `desktopFps`, the kitten slots, the spots on the screens and `cleanDesktopSettings`). On top of it, small pure modules of this plan's own, tested the same way: the window's layout and hit shapes (`desktopview.ts`), the flight's clock (`desktopflight.ts`), a press that is a click, a double-click or a drag (`gestures.ts`, `pressdrag.ts`), the trip as the island runs it (`desktoptrip.ts`: it turns every `act` into a message and a save, with a fake environment in the tests), the frame governor (`desktopgov.ts`) and the drawing (`desktopdraw.ts`). The `desktop` object of the `cat` block of `settings.json` holds `on`, `size` and `spots`; a Rust twin (`clean_desktop_settings` in `cat_settings.rs`) cleans it and `settings.rs` carries it through every save. **Two pages, one machine:** the island's page is the *brain* (`island/desktop.ts`: it knows the agents, the approvals and the settings, runs the trip and tells the window what to draw), and a second window, `desktop.html`, is the *body* (`desktop/body.ts`: it draws the cat, runs the flight and the drag, and answers with clicks, moves and "flight done"); Rust (`src-tauri/src/desktop.rs`) only creates the window hidden at launch, moves and shows it, decides what takes the mouse and relays the messages between the pages. Every check runs without launching the app: `npm run check:cat`, `tsc`, the Vite dev server with `playwright-cli` for the pictures, and Rust through `windows/scripts/cargo-linux.sh`.

**Tech Stack:** TypeScript 5 and Vite 6 (already in `windows/`), Canvas 2D, Node 22 (`node --test` reading the TypeScript source with `--experimental-strip-types`), Rust with `serde_json`, Tauri 2 and `gtk` (all already there; no new crate and no new feature), `playwright-cli` (headless Chromium, for the pictures only). No new npm or cargo dependency.

**Spec:** `docs/superpowers/specs/2026-10-08-desktop-cat-design.md`: §4 step 2 (H-tauri) with §1 "The trip", §2 "On the desktop" and §3 "Frame rate, CPU and the platforms". The contract is merged (H-0, `99e3be1`): `design/prototype/cat-core.js` ("The desktop cat" sections), `tests/fixtures/cat/desktop-cases.json` and `docs/CAT-CONTRACT.md` ("The desktop cat (H-0)"). The H-0 plan is `docs/superpowers/plans/2026-10-08-h0-desktop-cat-contract.md`; the format and the conventions are the last Windows plan's, `docs/superpowers/plans/2026-10-08-b-tauri-display-kittens.md`. The Mac twin (H-mac) is drafted at the same time; "Parity with macOS" below says what differs. Read the Windows cat code first (`windows/src/cat/`, `windows/src/island/`, `windows/src/core/state.ts`, `windows/src/settings/cat.ts`, `windows/src-tauri/src/island.rs`, `lib.rs`, `platform/`) and `windows/README.md`.

**Base:** branch `h-tauri/desktop-cat`, in a git worktree, from `notchmeow/rebrand` **at `99e3be1` or later** (H-0 is merged: nothing of the H-0 plan is applied by this plan; the Setup block checks `git merge-base --is-ancestor 99e3be1 HEAD`). Nothing is pushed.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and the contract; a line marked "(plan decision)" is a choice this plan makes where the spec is silent, and is listed again under "Open questions for the owner".

- **Frozen IDs.** Cat IDs (in this order): `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle` (an unknown stored ID is Shrimpy). Collar style IDs: `tag`, `band`, `kerchief`, `off`. Display mode IDs: `one`, `perAgent`, `two`. **Desktop size IDs, from now on: `small`, `medium`, `large`** (anything else stored is `medium`). The seven phases (`home`, `flyingOut`, `onDesktop`, `retracting`, `atNotchForAlert`, `returning`, `flyingHome`) and the nine events are the contract's. Pill IDs are frozen. Never rename a contract string (`nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`).
- **The trip (spec §1, contract).** One desktop cat at a time, the big cat keeping its role: One cat, the Main cat; A cat for each agent, the focused agent's cat (its coat follows the focus); Two cats, cat 1 (cat 2 stays in the notch). While the cat is on the desktop or in the air the big cat's spot in the notch is empty (the pills, the grid and cat 2 stay as they are), so there are never two copies of one cat. A drop on empty desktop **places** the cat (no flight); the tray item, the Settings switch and a launch **fly** it out; a double-click, "Send home", the tray item, the switch off or a drop on the notch **fly** it home. When `pendingApproval`, a chat's approval or a pill in `approval` or `question` becomes set the cat gives the surprised emote and flies into its notch spot; when all are clear it flies back out. An alert that clears mid-flight turns the cat around; a send-home during an alert ends the trip at home; an approval that lands while the cat is home takes nothing out; a take-out during a pending alert waits for the next alert. The flight is `desktopFlightAt`: an arc eased in and out, 600 ms, the cat at full size the whole way.
- **On the desktop (spec §2).** The big cat at full detail (no small eyes), its state badge, its agent's kittens (up to 3 then "+N", `desktopKittenSlots`, mirrored to the cat's left in the right half of its screen), its collar in the working agent's colour, cursor-watching (Windows: wherever the cursor is; Linux and Wayland: ahead unless the cursor is over the cat), the music dance (where `State.musicPlaying` is set; nothing sets it on Windows and Linux yet), and the ten-minute sleep with the sweep of stale kittens (the island's existing `SleepClock`; a hover or a click wakes it). Sizes Ø48, Ø64 (default) and Ø96. **Click:** the happy emote and the island opens at the notch, after one double-click interval so a double-click never also opens it; **double-click:** it flies home; **drag:** moves it, and on release the spot is clamped (`clampSpot`) and saved (`rememberSpot`); **right-click:** Open the notch, Send home and Size. Only the cat's body (the head, the badge and the kitten slots) takes the mouse. Not on the desktop cat: dropping files, the slap and the hairball.
- **Frame rate (spec §3, contract `desktopFps`).** 60 fps only during motion (a flight, a drag, an emote, a kitten arriving or leaving, the dance); 20 fps while the agent works or the cursor is within 150 points; 5 fps idle and awake; a still frame every 2 s asleep; **0 when it cannot be seen** (screen asleep or locked, a fullscreen app covering it, `home`): no timer and no frame callback. Nothing new polls while the cat is home; the island's own rule (0 % CPU while it is hidden) is unchanged. **The owner's answer (2026-10-12), for Windows and Linux only, overrides spec §3's "nothing new polls":** while the cat is out and awake there are light checks, a cursor check at about 10 Hz and a fullscreen check at 2 Hz, and they stop whenever the cat is at home, asleep, away (locked or display off) or hidden; Task 8b builds them and the bench reports the page's cost. Target: under 1 % of a core idle and awake, about 0 % asleep.
- **Storage (spec §3, contract).** `desktop: {on, size, spots}` in the `cat` block of `settings.json`, through `cleanDesktopSettings` (a clean-up of its own: `settings-cases.json` and `display-cases.json` stay byte for byte). `on` is true only for the boolean true; an unknown size is `medium`; a bad spot is dropped; `spots` is a map from `screenKey` to `{x, y}` with at most 32 arrangements. **A clean-up of the block that uses the Cat settings alone drops the Display keys and `desktop` at the next save: every clean-up of the block, in TypeScript and in Rust, cleans all three.** "On" is stored as the phase's `on` (`DESKTOP_PHASE_INFO`): quitting mid-flight home leaves the cat home.
- **Platforms (spec §3).** Windows: a second transparent, borderless, always-on-top window, skipped in the taskbar, that takes the mouse only over the body (the island's mechanism: a cursor poll flips `WS_EX_TRANSPARENT`; here it runs only while the cat is out, at 16 ms near the cat and 100 ms far from it). Linux with layer-shell (KDE Plasma, COSMIC, Hyprland, Sway and other wlroots): a surface on the top layer (below fullscreen windows, so it steps aside) placed with margins, its input region the body's shape. GNOME (a regular window): a small always-on-top window; GNOME ignores the position, so the cat lands where GNOME puts it (drag-out from the notch stays on, the flight is drawn inside the cat's own window, the spot is always saved but GNOME may not keep it) and **Settings says so under the switch**. **There are no global shortcuts on Windows and Linux.** The window is created hidden at launch, before the island's webview (WebView2 comes up blank for a window created later), with the same `additionalBrowserArgs`.
- **Positions are points (plan decision).** The contract's unit: physical pixels divided by the primary screen's scale factor, the origin at the top left of the main screen, y down. The cat on a screen with another scale factor keeps the size that screen gives it (`window_origin`). Settings and the page never see physical pixels.
- **Tolerance and tie-breaker.** Numbers compare within **1e-9** against the fixture. **`cat-core.js` is the tie-breaker.** This plan never edits `design/prototype/cat-core.js`, `tests/fixtures/cat/`, `scripts/gen-cat-fixtures.mjs` or `docs/CAT-CONTRACT.md`: a change there is the main session's. The cat code never calls `Math.random()` and reads a clock only as the late-bound default of a constructor or a parameter.
- **Files loaded by `npm run check:cat`** (everything under `windows/src/cat/` except `dev.ts` and `devdesktop.ts`, plus `core/layout.ts`, `core/notchspot.ts`, `core/state.ts`, `island/sleep.ts` and the others the earlier plans listed) use erasable TypeScript only (no `enum`, no `namespace`, no constructor parameter properties), `import type` for types, and relative imports **with the `.ts` extension**, because Node reads the source as it is. Files outside that set (`island/island.ts`, `island/desktop.ts`, `desktop/`, `settings/`, `main.ts`, `core/bridge.ts`) keep the repo's extension-less imports.
- **Never restyle what ships.** The only change in the notch is the empty big-cat spot while the cat is out. The new Settings row is built from the Settings window's own `.row` and `.switch` (a new row, no new CSS class). No pill, card, view or Settings row changes beyond what a task says.
- **No Coucou or Mochi names** anywhere (`mocha` is a coat, not a name to avoid); `names.test.mjs` keeps guarding `windows/`. **No telemetry:** the window talks to nothing but the island's page.
- **No new dependency.** No `npm install` of anything, **no change to `Cargo.lock`, and to `Cargo.toml` only the four `windows` crate features that Task 8b names (ruling 9)** (the window uses Tauri's own API, `gtk` and `libgtk-layer-shell` as the island does, and the `windows` crate features already enabled). Rust runs **only** through `windows/scripts/cargo-linux.sh` (Docker Desktop running), with this plan's own target directory, because other worktrees share that script's Docker volume: `windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/h-tauri`. Never install a toolchain on the host.
- **Performance.** 0 % CPU while the island is hidden and Settings is closed (unchanged). The new window's page runs nothing while the window is hidden, and its poll thread is parked on a condvar while the cat is home. No `setInterval` anywhere in the new code: the cat's frames come from the governor's one timer (or the display's frame callback at 60), the click's wait from one `setTimeout`.
- **Commits:** local only, never pushed, via `git commit -F -` with the message on stdin. End every commit message with the line `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` for a task a Haiku agent ran, or `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` for a Sonnet one (Tasks 3, 5 and 8b, and any task handed to `nm-implementer-deep`): the table says which.
- **The model rule** (`CLAUDE.md`, "Working with AI agents", 2026-10-12): Haiku 5.5 first, Sonnet 5.5 only for a named trigger, never Opus or Fable. The session runs on Sonnet 5.5 at high effort (trigger 5). Tasks 3, 5 and 8b use `nm-implementer-deep` for **trigger 1** (Tauri/Rust windowing, click-through, layer-shell, several monitors; pointer capture and a window moved on every frame). Every other task is Haiku 5.5, and the whole branch goes to `nm-reviewer-deep` (trigger 4).
- **House rules for every session and every subagent brief (the SUBAGENT RULES block):**
  1. **Never launch, quit or replace any NotchMeow app, and never start the Tauri app** (`npm run tauri dev`, a built `notchmeow.exe`): the owner runs it. Serving the front end with `npx --no-install vite` and looking at it in the headless `playwright-cli` browser is allowed, and only that.
  2. **Install nothing and download nothing.** `npx --no-install` only; never `npm install`, `npm ci`, `npm run build`, `npm run dev` or `npm run tauri`.
  3. **Rust only through `windows/scripts/cargo-linux.sh`** with `--target-dir /repo/windows/target/h-tauri`. Check the image first: `docker image inspect notchmeow-linux-dev`. **Never build or pull the image** (the script would, if it is missing): if the image is missing or the daemon is down, **the step stops and the session reports it**; the TypeScript tasks go on, and the Rust steps are owed.
  4. **Use `trash`, never `rm -rf`.** Pictures and the one-off scripts go in `.claude/checkpoints/h-tauri/` (gitignored), never anywhere that git tracks. Stop the dev server **by its saved PID only** (`kill "$(cat .claude/checkpoints/h-tauri/vite.pid)"`), never `kill $(lsof ...)`; close every browser session **by its name** (`playwright-cli -s=<name> close`), never `close-all`. Run `playwright-cli` with the default `TMPDIR` (a long one breaks its socket path), from `.claude/checkpoints/h-tauri/` so that its own `.playwright-cli` folder lands in the gitignored place.
  5. **Never push.** Commit only in a task's commit step, with `git commit -F -`, after `git rev-parse --show-toplevel` and `git branch --show-current` have said that the session is in its worktree on `h-tauri/desktop-cat`. Never edit `CLAUDE.md` or `ARCHITECT.md` except where Task 10 says so.
  6. **If a command is denied by a permission prompt, stop and report it.** Do not look for a workaround.
  7. Every shell block of this plan passes `bash -n`; a block that a brief edits must still pass it.

## Review Focus

The spec says what the desktop cat must do. It is silent on these inputs, and each would bite a person first. Each line names its test.

1. **A hand-edited or half-written `desktop` object, and the next save.** `on` as `"true"`, `1` or a list; a size of `"Huge"` or `["small"]`; `spots` as cut-off JSON text, with `__proto__`, with a key that has a trailing newline, a leading zero, `-0`, an unsorted pair of frames or 300 entries; then the Cat section saves. Expected: the app starts, the rest of the block is kept, no `settings.json.bad-…` appears, `desktop` is cleaned and **still there after the save** (a clean-up of the block from the Cat settings alone would drop it). Tests: Task 1 ("spots with numbers…", "nothing is changed in place…", `cleanDesktopSettings`), Task 2 (`desktop-settings.test.mjs`; the Rust `the_desktop_clean_up_replays_the_fixture`, `the_desktop_spots_keep_the_first_32…`, `bad_desktop_values_are_cleaned…`, `the_desktop_settings_survive_a_save_a_load_and_a_round_trip`).
2. **Screens that come and go.** A monitor unplugged while the cat sits on it, a spot on a screen that is gone, a laptop alone versus with a monitor, a screen with another scale, a screens change in mid-flight. Expected: the spot is found again for the arrangement (`spotFor`) and held inside the visible frame, 24 points from the head's edge; the cat is never left off screen; the flight's desktop end follows. Tests: Task 1 (the fixture's `clamps`, `spotFor`, `remembers`), Task 4 ("the screens changed…"), Task 3 (Rust `a_physical_rectangle_is_in_points_and_the_window_goes_where_the_head_is`).
3. **An alert at an awkward moment.** An approval during the flight out, a second one during the flight in, the answer mid-flight, a send-home while the cat sits in the notch for an alert, a take-out while one is pending, an approval while the cat is home or flying home, and an alert that was already pending when the island started. Expected: the contract's machine, and nothing else. Tests: Task 4 (every trip of `desktop-trip.test.mjs`, and the walk over every phase), Task 6 ("State says when…").
4. **A press that is a click, a double-click or a drag.** A drag that ends off screen or on the notch, a click that waits for a second one, a wobble under 4 px, a drag cancelled by a menu, a press on the notch's cat while the island is hidden, greeting or showing the drop sequence, and a press when the cat is already out. Expected: a click is a click (the island's old behaviour, unchanged, at release), a drag never clicks, a drop on the notch puts the cat back, a refused drop puts it back, and nothing happens in a view that has no big cat. Tests: Task 4 (gestures), Task 5 (`desktop-island.test.mjs`: the press, the island pins).
5. **Click-through that swallows a click, or lets one through that it should not.** A shape that pokes out of the window, the corners of the window, a cursor that is far, a cat being carried. Expected: only the head with its ears, the badge and the kitten slots take the mouse, every shape is inside the window, the corners pass through, the whole window takes the mouse while the cat is carried. Tests: Task 3 (`desktop-view.test.mjs`, Rust `only_the_cat_takes_the_mouse` and `the_cursor_poll_is_fast_only_near_the_window`).
6. **A frame rate that does not drop.** A hidden page, a sleeping cat, a rate set from inside a frame, a rate of NaN or 120, a cat that was shown and hidden again. Expected: 0 stops every timer and frame callback; asleep is one frame every 2 s; a rate changed from inside a frame is scheduled once; the hidden island draws nothing. Tests: Task 4 (`desktop-gov.test.mjs`), Task 8 (the rule's pins and the browser's zero-frame check).

---

## File Structure

All paths are under `windows/` unless they say otherwise.

| Path | Responsibility |
|---|---|
| `src/cat/desktop.ts` | New. The contract's desktop rules: the trip (`desktopStep`, the phases, events and acts), `desktopFlightAt`, `DESKTOP_SIZES`, `desktopFps`, `desktopKittenSlots`, the spots on the screens (`screenKey`, `clampSpot`, `spotFor`, `rememberSpot`, `cleanDesktopSpots`) and `cleanDesktopSettings`. |
| `src/cat/display.ts`, `src/settings/cat.ts` | `CatBlock` holds `desktop`; `cleanCatBlock` cleans all three parts; `withDesktop*` edit helpers; the "Cat on the desktop" row (a switch under the Display rows) and, at the end, the GNOME note. |
| `src/cat/desktopview.ts` | New. The window's layout (size, where the head is, the hit circles: head with ears, badge, kitten slots), `hitsCat`, `kittenSide`, and `DesktopWorld`, what Rust knows about the screens. |
| `src/cat/desktopflight.ts`, `gestures.ts`, `pressdrag.ts` | New. The flight's clock (it can turn round and move its ends); a press as click, double-click or drag; the press on the notch's cat as click or drag. |
| `src/cat/desktoptrip.ts` | New. The trip as the island lives it: it keeps the phase, turns every `act` into messages for the window (`BodyMsg`) and saves, with a `TripEnv` the tests fake. The message types of both pages. |
| `src/cat/desktopgov.ts`, `src/cat/desktopdraw.ts` | New. The frame governor (one timer; 0 stops everything); one frame of the desktop cat with its collar and kittens. |
| `src/core/notchspot.ts` | New. The notch's big-cat spot in points, and the island window's px to points and back. |
| `src/island/desktop.ts`, `src/island/island.ts`, `src/core/state.ts`, `src/main.ts` | New and changed. The brain; the press on the big cat (a click or a drag out), the empty big-cat spot (no cat, glow or kittens, cat 2 stays), the greeting hook; `State.desktopNotchEmpty` and `State.attentionNeeded`; the brain's wiring and the tray's item. |
| `desktop.html`, `src/desktop/main.ts`, `src/desktop/body.ts` | New. The desktop window's page: it draws the cat, flies it, takes the pointer, keeps to the frame rate. `vite.config.ts` builds it; `capabilities/default.json` lets it use the app's commands. |
| `src/core/bridge.ts` | The desktop commands (`desktopScreens`, `desktopLayout`, `desktopPlace`, `desktopShow`, `desktopDrag`, `desktopNativeDrag`, `desktopCursor`, `desktopRelay`, `desktopMenuText`) and `desktopPositioned` of the boot info. |
| `src/cat/dev.ts`, `src/cat/devdesktop.ts` | The `?dev` page's Desktop cat panel: the mock desktop, the alert flight, the bench. |
| `src-tauri/src/desktop.rs`, `src-tauri/src/lib.rs`, `src-tauri/src/island.rs`, `src-tauri/src/tray.rs` | New and changed. The window (created hidden at launch), its placement in points, its hit shapes, the poll thread, the commands; the registration; `target_monitor` is public; the tray's "Cat on the desktop" item. |
| `src-tauri/src/platform/windows.rs`, `src-tauri/src/platform/linux.rs` | The OS parts: a non-activating window and fullscreen detection (Windows); a top-layer layer-shell surface with margins and an input region, or a plain window (Linux). |
| `src-tauri/src/cat_settings.rs`, `src-tauri/src/settings.rs` | The Rust twin of the desktop clean-up (`clean_desktop_settings`, `is_screen_key`, `clean_desktop_spots`); `clean_cat_block` cleans all three parts, and `sanitized` keeps them at every save. |
| `scripts/cat-tests/*.test.mjs` | New: `desktop`, `desktop-settings`, `desktop-view`, `desktop-window`, `desktop-flight`, `desktop-trip`, `desktop-gov`, `desktop-island`, `desktop-alert`, `desktop-draw`, `desktop-look`, `desktop-rate`, `desktop-menu`. Changed: `display.test.mjs` (the block has nine keys) and `two-cats.test.mjs` (one source pin moved). |
| `README.md`, `../CLAUDE.md`, `../ARCHITECT.md` | The docs, in Task 10. **`../.github/workflows/windows-tests.yml` needs no change:** it already runs on `windows/**` and `tests/fixtures/cat/**`, which cover every new file. |

**Staged edits.** Most tasks edit files earlier tasks created or changed. Every edit below is a Python script whose replacements assert that the find text occurs exactly once; the text is what the tree has after the tasks before it. Run each script from the repository root, as it is. If a find text occurs zero or two times, stop and report: the tree is not what the plan expects.

## Tasks and agents

`CLAUDE.md`: Haiku 5.5 first, Sonnet 5.5 only on a named trigger. Tasks 1, 4 and 10 give every line of their code: transcription, `nm-implementer-light` (Haiku 5.5, medium). Tasks 2, 6, 7, 8 and 9 are multi-file with their code given, and some run a browser or Docker: `nm-implementer` (Haiku 5.5, high). **Tasks 3, 5 and 8b are `nm-implementer-deep` (Sonnet 5.5, high), trigger 1** (8b: the platform's lock, display-power and double-click APIs): Task 3 creates a Tauri window and decides what takes the mouse on two operating systems and several monitors (click-through, layer-shell, a position in points); Task 5 moves that window from one page while another holds the mouse (pointer capture across the island's window edge, a window placed on every frame, messages between two webviews). Each task is then reviewed by `nm-reviewer` (Haiku 5.5, high), and the whole branch by `nm-reviewer-deep` (Sonnet 5.5, high) after Checkpoint 3. If a step's expected output differs and the cause is not obvious (a Rust compile error, a layout that overlaps, a click that does not reach the page), hand that task to `nm-implementer-deep` (trigger 2); a task Haiku has failed twice goes there too.

| # | Task | Agent | Model | Review |
|---|---|---|---|---|
| 1 | The contract's desktop rules in TypeScript (replays `desktop-cases.json`) | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 2 | Settings: `desktop` in the block (TypeScript and Rust), kept at every save, and the Settings switch | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 3 | The window and its click-through: layout, hit shapes, `desktop.rs`, the platform parts, the page's shell | `nm-implementer-deep` (trigger 1) | Sonnet 5.5 | `nm-reviewer` |
| 4 | The flight's clock, the gestures, the trip and the frame governor (pure, tested with fakes) | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 5 | Dragging out, the flight and sending home: the brain, the body, the island's press | `nm-implementer-deep` (trigger 1) | Sonnet 5.5 | `nm-reviewer` |
| 6 | Alerts: `State.attentionNeeded`, the trip told at every change | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 7 | What it shows: badge, kittens, collar, eyes, cursor, dance and sleep; the `?dev` mock desktop | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 1:** pictures of S, M and L on a desktop mock, and the Settings switch | the executing session | | |
| 8 | The frame-rate rule and the bench; the alert flight as a strip of frames | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 8b | Away and awake (lock, unlock, display off, light checks only while awake) and the system's double-click time | `nm-implementer-deep` (trigger 1) | Sonnet 5.5 | `nm-reviewer` |
| | **Checkpoint 2:** the alert flight as a strip of frames, and the bench numbers | the executing session | | |
| 9 | The tray item, the Settings GNOME note | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 10 | The docs and the final checks | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 3:** the owner signs off | the executing session | | |
| Final | Whole-branch review | `nm-reviewer-deep` (trigger 4) | Sonnet 5.5 | none |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; `nm-implementer-deep` also `superpowers:systematic-debugging`. Reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Ponytail never cuts what this plan or the spec asks for, nor tests, security or privacy rules. The agents of Tasks 3, 5, 7 and 8 also load `playwright-cli`.

## Execution

**One worktree chat session** runs the whole plan: branch `h-tauri/desktop-cat`, model **Sonnet 5.5 at high effort** (trigger 5: an app plan with platform windowing and many cross-task interfaces), in parallel with the Mac twin, which has its own worktree. It runs on a base where **H-0 is merged** (`99e3be1` on `notchmeow/rebrand`, or any later commit). Nothing is pushed. The session never starts the Tauri app: the owner's real-build checks are listed at the end.

**The session is started in three steps** (`ARCHITECT.md`), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run the Setup block of `docs/superpowers/plans/2026-10-12-h-tauri-desktop-cat.md`. If any check in it fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, that plan and `docs/superpowers/specs/2026-10-08-desktop-cat-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief below as the next message.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

**Controller brief** (what the main session sends the worktree session once its model is set):

> Run `docs/superpowers/plans/2026-10-12-h-tauri-desktop-cat.md` with `superpowers:subagent-driven-development`, task by task, on branch `h-tauri/desktop-cat`. Do its Setup first. Dispatch each task to the agent and model the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. These rules hold for you and for every brief you write:
>
> 1. **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this session's worktree and the second `h-tauri/desktop-cat`. If either differs, stop and report. Commit with `git commit -F -`, the message on stdin, ending with the `Co-Authored-By` line of the model that did the task. Never push.
> 2. **The ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md` (the SDD plugin's scripts are refused by auto mode): one line per task with its status, its commit, the test counts it printed, the model and agent that ran it, the trigger if it was `nm-implementer-deep`, and what the review found and how it was fixed. Write it after every step that changes a status.
> 3. **Briefs are task-sized.** A subagent gets one task: its text from the plan, the Global Constraints, the SUBAGENT RULES block, the files to read and the exact commands. Never hand it the whole plan.
> 4. **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots) restricted to the task's files, never two-dot, and the task's own text.
> 5. **Shell.** Every shell block you write or edit passes `bash -n` first. Stop the dev server by its saved PID only (`kill "$(cat .claude/checkpoints/h-tauri/vite.pid)"`), never `kill $(lsof ...)`. Close `playwright-cli` browsers by session name (`-s=<name> close`), never `close-all`. Run `playwright-cli` with the default `TMPDIR`, from `.claude/checkpoints/h-tauri/`.
> 6. **Never** launch, quit or replace a NotchMeow app or start the Tauri app; install, download or build a Docker image (if `docker image inspect notchmeow-linux-dev` fails or the daemon is down, say so: the Rust steps are owed, and the TypeScript tasks go on); use the network; or use `rm -rf` (use `trash`). Rust only through `windows/scripts/cargo-linux.sh` with `--target-dir /repo/windows/target/h-tauri`.
> 7. **Refusals.** If any command is refused by a permission prompt, stop and report it. Do not look for another way.
> 8. **Checkpoints.** Run Tasks 1 to 7, then stop for **Checkpoint 1**: copy the pictures into `.claude/checkpoints/h-tauri/` (the `?dev` page's mock desktop at S, M and L, and the Settings switch), send the owner their paths and the list under the checkpoint, and wait. After the owner's reply run Tasks 8 and 8b and stop for **Checkpoint 2** (the alert flight's strip of frames and the bench numbers). After the owner's reply run Tasks 9 and 10 and stop for **Checkpoint 3**; after the owner's OK dispatch `nm-reviewer-deep` over the whole branch. Never start the next stage before the owner's reply.
> 9. **Report:** the commits; for `windows/`: `npx --no-install tsc --noEmit`, `npm run check:cat`, `npm run check:ai`, `npm run check:claude` and the `cargo test --workspace` counts (or that the image was missing); the output of `bash scripts/test-cat-contract.sh`; the bench numbers of Task 8; the pictures of the three checkpoints; the Windows `cargo check` and a release build (owed to CI); and anything you could not settle.

## Setup (the controller, once)

- [ ] Put the session's worktree on the plan's branch, check that H-0 is merged (`99e3be1` is an ancestor of `HEAD`), check that the base has what the plan reads (the fixture and the contract's numbers that Task 1 copies), and copy the main checkout's front-end packages. This plan adds no package, so nothing is downloaded: no `npm install` or `npm ci`. `cp -c` makes an APFS clone, which is instant and takes no extra disk space. It must be a real folder, not a symlink, because `.gitignore` ignores `/windows/node_modules` as a folder.

```bash
git status                                   # must be clean
git switch -c h-tauri/desktop-cat notchmeow/rebrand
git merge-base --is-ancestor 99e3be1 HEAD && echo "H-0 is merged (99e3be1)"   # if this prints nothing, stop
git log --oneline -3
git ls-files tests/fixtures/cat/desktop-cases.json docs/CAT-CONTRACT.md docs/superpowers/plans/2026-10-12-h-tauri-desktop-cat.md
git rev-parse --show-toplevel; git branch --show-current
cp -cR "/path/to/notchmeow/windows/node_modules" windows/node_modules
git status --short                           # still empty: the copy is ignored
mkdir -p .claude/checkpoints/h-tauri .superpowers/sdd/2026-10-12-h-tauri-desktop-cat
cd windows && node --version                 # 22.6 or newer
```

`H-0 is merged (99e3be1)` must print, and so must the three paths (if the fixture is missing H-0 is not merged: stop; if the plan's own path prints nothing, the plan is not committed on this branch: stop).

- [ ] Check that the contract is the one this plan was written against: the numbers Task 1 copies (`DESKTOP_SIZES`, the frame rates, the flight's time and arc, the margin, the default spot, the kittens' place) must be the core's, and a later change to any of them must be copied into Task 1 first.

```bash
node -e '
const core = require("./design/prototype/cat-core.js"), assert = require("node:assert/strict");
const json = (v) => JSON.parse(JSON.stringify(v));
assert.deepEqual(json(core.DESKTOP_SIZES), { small: 48, medium: 64, large: 96 });
assert.deepEqual(json(core.DESKTOP_FPS), { motion: 60, active: 20, idle: 5, asleep: 0.5, off: 0 });
assert.deepEqual(json(core.DESKTOP_KITTEN_PLACE), { unit: "D", max: 3, d: 0.3, x0: 0.82, y0: 0.22, step: 0.33, moreSize: 0.2 });
assert.deepEqual(json(core.DESKTOP_ARC), { lift: 0.25, max: 90 });
assert.equal(core.DESKTOP_FLIGHT_MS, 600); assert.equal(core.DESKTOP_NEAR, 150); assert.equal(core.DESKTOP_MARGIN, 24); assert.equal(core.MAX_DESKTOP_SPOTS, 32);
assert.deepEqual(json(core.DESKTOP_DEFAULT), { x: 0.6, y: 1 / 3 });
assert.deepEqual(core.DESKTOP_PHASES, ["home", "flyingOut", "onDesktop", "retracting", "atNotchForAlert", "returning", "flyingHome"]);
assert.deepEqual(core.DESKTOP_SIZE_IDS, ["small", "medium", "large"]);
console.log("the contract is the one this plan was written against");
'
```

Expected: `the contract is the one this plan was written against`. If an assertion fails, stop and tell the main session which number differs.

- [ ] Check that the starting point is green.

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1
(cd .. && bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two generator")
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && echo "image ok" || echo "image missing or the daemon is down: the Rust steps are owed"
```

Expected: `tsc exit 0` with no type error before it, `ℹ tests 274`, `ℹ pass 274`, `ℹ fail 0`, `All AI UI checks passed`, `All Claude Code UI checks passed`, `# tests 284`, `# pass 284`, `# fail 0`, `✓ 15 fixture files match cat-core.js`, `✓ two generator runs write identical bytes` and `image ok`. If `image ok` does not print, **do not build the image**: do the TypeScript tasks only and report that the Rust steps (Tasks 2, 3, 8b and 9) are owed. Their code is complete either way, and CI's `windows-tests.yml` runs `cargo test`.

## How to run this plan

**Blocks.** A code step is a `bash` block: either a file written with `cat > path <<'EOF'` (the file's exact content, from the repository root), or a Python script whose `edit` helper replaces text that must occur exactly once in the file it names, or a plain command. Run each block from the repository root, as it is. Never type a block from memory and never "improve" one. A `Run:` block's `Expected:` line says what it prints (every backticked literal must appear). A `Run:` block that starts with `cd windows` ends in `cd ..` and came back. URLs with a `?` are quoted, because the shell would read the `?` as a wildcard.

**Red first.** Each task writes its tests, runs them to see them fail, writes the code, and runs them to see them pass. A "prove it bites" step changes one line with the given script, runs the tests, and puts the line back (the script restores the file itself): it is never committed.

**Pixels.** There are no pixel tests. The look is checked by eye in a headless browser (`playwright-cli`, with Vite alone, never the Tauri app) and the cost by the `?dev` page's own bench. Keep every picture in `.claude/checkpoints/h-tauri/`, and say what you saw. **What no test program and no headless browser can show** is what the owner's real-build checks at the end are for (the window itself, click-through on both systems, a flight across two monitors, a fullscreen app, a lock screen); never claim them.

**The owner's checkpoints** are marked `Checkpoint N`: the session stops there, sends the owner the pictures and the list, and waits. Never start the next stage before the owner's OK.

**Starting and stopping the dev server** (Tasks 3, 5, 7 and 8 use it; port 14611 so that it never meets another worktree's):

```bash
mkdir -p .claude/checkpoints/h-tauri
cd windows
(npx --no-install vite --port 14611 --strictPort > ../.claude/checkpoints/h-tauri/vite.log 2>&1 & echo $! > ../.claude/checkpoints/h-tauri/vite.pid)
sleep 3
cd ..
tail -3 .claude/checkpoints/h-tauri/vite.log
```

Expected: `VITE v6` and `http://127.0.0.1:14611/`. When a task is done with it: `kill "$(cat .claude/checkpoints/h-tauri/vite.pid)"` (nothing else) and, for each session it opened, `playwright-cli -s=<name> close`.

---

**The "prove it bites" helper** (written once, here; every proof step below calls it). It changes one line, runs the given test files, prints the pass and fail counts and puts the file back; it refuses a change whose find text does not occur exactly once.

```bash
mkdir -p .claude/checkpoints/h-tauri
cat > .claude/checkpoints/h-tauri/mut.py <<'EOF'
import sys, subprocess, shutil, os
# usage, from windows/: python3 ../.claude/checkpoints/h-tauri/mut.py <file> <find> <replace> <test files...>
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

# Stage 1: the settings

### Task 1: The contract's desktop rules in TypeScript

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `windows/src/cat/desktop.ts`
- Test: `windows/scripts/cat-tests/desktop.test.mjs`

**Interfaces:**
- Consumes: the fixture `desktop-cases.json` (keys `phaseIds`, `phases`, `events`, `acts`, `flightMs`, `arc`, `steps`, `trips`, `flights`, `sizes`, `sizeIds`, `defaultSize`, `sizeCases`, `fps`, `near`, `fpsCases`, `kittenPlace`, `kittenSlots`, `kittenSizes`, `margin`, `defaultSpot`, `maxSpots`, `screenKeys`, `isScreenKey`, `clamps`, `defaultSpots`, `spotFor`, `remembers`, `spotMaps`, `settingsDefaults`, `settingsCases`) and from the cat code `base.ts`'s `EZ`, `clamp`, `own` and `util.mjs`'s `load`, `same`, `near`, `finite`.
- Produces: `DESKTOP_PHASES`, `DESKTOP_PHASE_INFO`, `DESKTOP_EVENTS`, `DESKTOP_ACTS`, `DESKTOP_NEXT`, `desktopStep`, `DESKTOP_FLIGHT_MS`, `DESKTOP_ARC`, `desktopFlightAt`, `DESKTOP_SIZES`, `DESKTOP_SIZE_IDS`, `DEFAULT_DESKTOP_SIZE`, `desktopSizeOf`, `DESKTOP_FPS`, `DESKTOP_NEAR`, `desktopFps`, `DESKTOP_KITTEN_PLACE`, `desktopKittenSlots`, `DESKTOP_MARGIN`, `DESKTOP_DEFAULT`, `MAX_DESKTOP_SPOTS`, `screenKey`, `isScreenKey`, `defaultDesktopSpot`, `clampSpot`, `cleanDesktopSpots`, `spotFor`, `rememberSpot`, `spotOf`, `cleanDesktopSettings`, `defaultDesktopSettings`; types `Spot`, `Rect`, `Screen`, `DesktopPhase`, `DesktopEvent`, `DesktopAct`, `DesktopStep`, `DesktopSettings`, `DesktopSizeId`, `DesktopFpsInput`, `DesktopKittenSlots`. Everything later reads these.

- [ ] **Step 1: Write the failing test**

It replays every row of the fixture and holds the cases a JSON file cannot (NaN, an infinity, text for a number, a `__proto__` key), the "nothing is changed in place" check, and the hostile stored settings.

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_DESKTOP_SIZE, DESKTOP_ACTS, DESKTOP_ARC, DESKTOP_DEFAULT, DESKTOP_EVENTS, DESKTOP_FLIGHT_MS, DESKTOP_FPS, DESKTOP_KITTEN_PLACE, DESKTOP_MARGIN, DESKTOP_NEAR, DESKTOP_PHASES,
  DESKTOP_PHASE_INFO, DESKTOP_SIZES, DESKTOP_SIZE_IDS, MAX_DESKTOP_SPOTS, clampSpot, cleanDesktopSettings, cleanDesktopSpots, defaultDesktopSettings, defaultDesktopSpot, desktopFlightAt,
  desktopFps, desktopKittenSlots, desktopSizeOf, desktopStep, isScreenKey, rememberSpot, screenKey, spotFor,
} from "../../src/cat/desktop.ts";
import { finite, load, near, same } from "./util.mjs";

// The desktop cat's rules, replayed from tests/fixtures/cat/desktop-cases.json (H-0), and the inputs a JSON file cannot hold: NaN, infinities, text for a number.
const fx = load("desktop-cases.json");
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
const LAPTOP = [{ frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true }];

test("the constants, the phases, the events and the acts are the fixture's", () => {
  assert.deepEqual([...DESKTOP_PHASES], fx.phaseIds);
  assert.deepEqual([...DESKTOP_EVENTS], fx.events);
  assert.deepEqual([...DESKTOP_ACTS], fx.acts);
  same(DESKTOP_PHASE_INFO, fx.phases, "phases");
  same({ flightMs: DESKTOP_FLIGHT_MS, arc: DESKTOP_ARC, sizes: DESKTOP_SIZES, fps: DESKTOP_FPS, near: DESKTOP_NEAR, kittenPlace: DESKTOP_KITTEN_PLACE, margin: DESKTOP_MARGIN, maxSpots: MAX_DESKTOP_SPOTS },
    { flightMs: fx.flightMs, arc: fx.arc, sizes: fx.sizes, fps: fx.fps, near: fx.near, kittenPlace: fx.kittenPlace, margin: fx.margin, maxSpots: fx.maxSpots }, "numbers");
  same(DESKTOP_DEFAULT, fx.defaultSpot, "default spot");
  assert.deepEqual([...DESKTOP_SIZE_IDS], fx.sizeIds);
  assert.equal(DEFAULT_DESKTOP_SIZE, fx.defaultSize);
});

test("desktopStep replays all steps (every phase and event, and input that is neither) and every trip, event by event", () => {
  assert.ok(fx.steps.length >= 89 && fx.trips.length >= 11);
  for (const c of fx.steps) same(desktopStep(c.state, c.event), c.out, `${JSON.stringify(c.state)} ${JSON.stringify(c.event)}`);
  for (const t of fx.trips) {
    let state = t.from;
    t.events.forEach((ev, i) => { const r = desktopStep(state, ev); same(r, t.out[i], `${t.name}, event ${i + 1}`); state = r.state; });
  }
});

test("a phase that is drawn has an empty notch spot, 'on' is stored for every phase but the two homes, and a flight is exactly a change between flights", () => {
  for (const p of DESKTOP_PHASES) {
    const i = DESKTOP_PHASE_INFO[p];
    if (i.drawn) assert.equal(i.notchEmpty, true, `${p}: never two copies of one cat`);
    assert.equal(i.flight, i.dir !== null, p);
  }
  assert.deepEqual(DESKTOP_PHASES.filter((p) => !DESKTOP_PHASE_INFO[p].on), ["home", "flyingHome"]);
  // 'turn' is a change between two flights whose direction differs, 'keep' between two with the same direction.
  for (const s of fx.steps) {
    if (s.out.act !== "turn" && s.out.act !== "keep") continue;
    const a = DESKTOP_PHASE_INFO[s.state], b = DESKTOP_PHASE_INFO[s.out.state];
    assert.ok(a.flight && b.flight, `${s.state} ${s.event.type}`);
    assert.equal(s.out.act === "turn", a.dir !== b.dir, `${s.state} ${s.event.type}`);
  }
});

test("a drop or a move without a valid spot changes nothing, and the machine never throws on anything", () => {
  for (const spot of [undefined, null, 5, "x", {}, { x: 1 }, { x: NaN, y: 1 }, { x: 1, y: Infinity }, { x: "1", y: 2 }, { x: 1e5 + 1, y: 0 }, [1, 2]]) {
    same(desktopStep("home", { type: "dragOut", spot }), { state: "home", act: null }, `dragOut ${JSON.stringify(spot)}`);
    same(desktopStep("onDesktop", { type: "move", spot }), { state: "onDesktop", act: null }, `move ${JSON.stringify(spot)}`);
  }
  same(desktopStep("home", { type: "dragOut", spot: { x: 1e5, y: -1e5 } }), { state: "onDesktop", act: "place" }, "the limit itself is a spot");
  for (const state of [undefined, null, 7, {}, [], "constructor", "__proto__", "HOME"]) for (const ev of [undefined, null, 3, "toggle", [], {}, { type: 7 }, { type: "constructor" }, { type: "__proto__" }, { type: "toggle" }]) {
    const r = desktopStep(state, ev);
    assert.ok(DESKTOP_PHASES.includes(r.state), `${String(state)} ${JSON.stringify(ev)}`);
  }
  same(desktopStep("constructor", { type: "toggle" }), { state: "flyingOut", act: "flyOut" }, "a state that is not a phase counts as home");
});

test("desktopFlightAt replays the fixture, holds t to 0..1, and a flight retraces itself when its ends are swapped", () => {
  assert.ok(fx.flights.length >= 80);
  for (const c of fx.flights) same(desktopFlightAt(c.from, c.to, c.t), c.out, `${c.name} t ${c.t}`);
  const a = { x: 480, y: 16 }, b = { x: 576, y: 180 };
  for (let i = 0; i <= 20; i++) {
    const t = i / 20, p = desktopFlightAt(a, b, t), q = desktopFlightAt(b, a, 1 - t);
    near(p.x, q.x); near(p.y, q.y); assert.equal(p.scale, 1);
  }
});

test("a flight with a t, a from or a to that is not a number is the default, and nothing is ever NaN: what a JSON fixture cannot hold", () => {
  const a = { x: 10, y: 20 }, b = { x: 300, y: 400 };
  for (const t of [NaN, "0.5", null, undefined, {}, [], true]) same(desktopFlightAt(a, b, t), desktopFlightAt(a, b, 0), `t ${String(t)}`);
  same(desktopFlightAt(a, b, Infinity), desktopFlightAt(a, b, 1), "+Infinity is held to 1");
  same(desktopFlightAt(a, b, -Infinity), desktopFlightAt(a, b, 0), "-Infinity is held to 0");
  for (const bad of [null, undefined, 5, "x", {}, { x: NaN, y: 0 }, { x: 0, y: Infinity }, { x: "1", y: 1 }]) {
    same(desktopFlightAt(bad, b, 0.4), desktopFlightAt({ x: 0, y: 0 }, b, 0.4), `from ${JSON.stringify(bad)}`);
    same(desktopFlightAt(a, bad, 0.4), desktopFlightAt(a, { x: 0, y: 0 }, 0.4), `to ${JSON.stringify(bad)}`);
  }
  finite(desktopFlightAt(a, a, 0.5));
  finite(desktopFlightAt({ x: 1e5, y: 1e5 }, { x: -1e5, y: -1e5 }, 0.5));
});

test("sizes: the three IDs, and anything else (a number, text in another case, a list, __proto__) is medium", () => {
  for (const c of fx.sizeCases) assert.equal(desktopSizeOf(c.raw), c.out, JSON.stringify(c.raw));
  for (const raw of [undefined, null, NaN, 48, "Small", "SMALL", " small", "small ", ["small"], { 0: "small" }, "toString"]) assert.equal(desktopSizeOf(raw), "medium", String(raw));
});

test("desktopFps replays the fixture and treats only true as a flag and only a finite number as a distance", () => {
  assert.ok(fx.fpsCases.length >= 39);
  for (const c of fx.fpsCases) assert.equal(desktopFps(c.input), c.out, c.name);
  const base = { phase: "onDesktop" };
  for (const flag of ["hidden", "dragging", "emote", "kittenMotion", "dance", "asleep", "working"]) {
    for (const v of [1, "true", {}, [], null, undefined, "yes"]) assert.equal(desktopFps({ ...base, [flag]: v }), DESKTOP_FPS.idle, `${flag} ${JSON.stringify(v)}`);
    assert.notEqual(desktopFps({ ...base, [flag]: true }), DESKTOP_FPS.idle, `${flag} true`);
  }
  for (const d of [NaN, Infinity, -Infinity, "10", null, undefined, {}, DESKTOP_NEAR + 0.001]) assert.equal(desktopFps({ ...base, cursorDist: d }), DESKTOP_FPS.idle, `cursorDist ${String(d)}`);
  assert.equal(desktopFps({ ...base, cursorDist: DESKTOP_NEAR }), DESKTOP_FPS.active, "within 150 is inclusive");
  assert.equal(desktopFps({ ...base, asleep: true, cursorDist: 5, working: true }), DESKTOP_FPS.asleep, "sleep beats the cursor and work");
  assert.equal(desktopFps({ ...base, asleep: true, hidden: true }), 0, "hidden beats everything");
  for (const i of [undefined, null, 5, "onDesktop", [], {}, { phase: "nope" }, { phase: "constructor" }, { phase: undefined }]) assert.equal(desktopFps(i), 0, JSON.stringify(i));
});

test("desktopKittenSlots replays the fixture, scales with the size, and mirrors for a cat in the right half of its screen", () => {
  assert.ok(fx.kittenSlots.length >= 21);
  for (const c of fx.kittenSlots) same(desktopKittenSlots(c.kittens, c.side), c.out, c.name);
  assert.equal(fx.kittenSizes.length, 12);
  for (const c of fx.kittenSizes) {
    const ks = Array.from({ length: c.count }, (_, i) => ({ id: `k${i}`, state: ["approval", "searching", "working"][i % 3] })), s = desktopKittenSlots(ks, 1);
    same({ count: s.count, more: s.more, shown: s.shown.map((q) => ({ id: q.id, state: q.state, x: q.x * c.d, y: q.y * c.d, d: q.d * c.d })), moreAt: s.moreAt && { x: s.moreAt.x * c.d, y: s.moreAt.y * c.d, size: s.moreAt.size * c.d } },
      { count: c.count, more: c.more, shown: c.shown, moreAt: c.moreAt }, `${c.size} ${c.count}`);
  }
  for (const side of [undefined, 0, 2, "-1", null, NaN]) same(desktopKittenSlots([{ id: "a" }], side), desktopKittenSlots([{ id: "a" }], 1), `side ${String(side)} is 1`);
  assert.deepEqual(desktopKittenSlots("nope", 1).shown, [], "a list that is not a list shows nothing");
  assert.equal(desktopKittenSlots([{ id: "" }, { id: 5 }, null, { id: "ok" }], 1).count, 1, "only real kitten IDs count");
});

test("screenKey, isScreenKey, clampSpot, defaultDesktopSpot, spotFor and rememberSpot replay the fixture", () => {
  assert.equal(fx.screenKeys.length >= 19 && fx.isScreenKey.length >= 30 && fx.clamps.length >= 54 && fx.defaultSpots.length >= 8 && fx.spotFor.length >= 13 && fx.remembers.length >= 8, true);
  for (const c of fx.screenKeys) assert.equal(screenKey(c.screens), c.out, c.name);
  for (const c of fx.isScreenKey) assert.equal(isScreenKey(c.key), c.out, JSON.stringify(c.key));
  for (const c of fx.clamps) same(clampSpot(c.spot, c.screens, c.size), c.out, c.name);
  for (const c of fx.defaultSpots) same(defaultDesktopSpot(c.screens, c.size), c.out, c.name);
  for (const c of fx.spotFor) same(spotFor(c.spots, c.screens, c.size), c.out, c.name);
  for (const c of fx.remembers) same(rememberSpot(c.spots, c.screens, c.spot, c.size), c.out, c.name);
});

test("spots with numbers a JSON file cannot hold: a spot that is NaN or infinite is on no screen, and a screen that is NaN is no screen", () => {
  const d = defaultDesktopSpot(LAPTOP, "medium");
  for (const spot of [{ x: NaN, y: 100 }, { x: 100, y: Infinity }, { x: "100", y: 100 }, null, undefined]) same(clampSpot(spot, LAPTOP, "medium"), d, JSON.stringify(spot));
  const bad = [{ frame: { x: NaN, y: 0, w: 100, h: 100 } }, { frame: { x: 0, y: 0, w: Infinity, h: 100 } }, { frame: { x: 0, y: 0, w: 0, h: 100 } }, { frame: { x: 0, y: 0, w: 1e6 + 1, h: 100 } }, null, 7];
  assert.equal(screenKey(bad), "");
  assert.equal(clampSpot({ x: 5, y: 5 }, bad, "medium"), null);
  assert.equal(spotFor({}, bad, "medium"), null);
  assert.equal(defaultDesktopSpot(bad), null);
  assert.deepEqual(rememberSpot({ "0,0,1,1": { x: 1, y: 1 } }, bad, { x: 5, y: 5 }), { "0,0,1,1": { x: 1, y: 1 } });
  // Half up, not half away from zero: -0.5 rounds to 0 and -1.5 to -1.
  assert.equal(screenKey([{ frame: { x: -0.5, y: -1.5, w: 10.5, h: 10.4 } }]), "0,-1,11,10");
  // The cat's centre is margin + D/2 from every edge of the visible frame, for each size.
  for (const [id, D] of Object.entries(DESKTOP_SIZES)) {
    const c = clampSpot({ x: 0, y: 0 }, LAPTOP, id), m = DESKTOP_MARGIN + D / 2;
    near(c.x, m); near(c.y, 37 + m);
    const r = clampSpot({ x: 1511, y: 981 }, LAPTOP, id);
    near(r.x, 1512 - m); near(r.y, 912 - m);
  }
});

test("nothing is changed in place, and a stored map is cleaned the same however it is written", () => {
  const spots = deepFreeze(JSON.parse('{"0,0,1512,982":{"x":300,"y":400,"extra":1},"__proto__":{"x":1,"y":1}}'));
  const before = JSON.stringify(spots);
  rememberSpot(spots, LAPTOP, { x: 10, y: 10 }, "large"); spotFor(spots, LAPTOP, "small"); cleanDesktopSpots(spots); deepFreeze(LAPTOP); clampSpot({ x: 1, y: 1 }, LAPTOP, "large"); screenKey(LAPTOP);
  assert.equal(JSON.stringify(spots), before);
  for (const c of fx.spotMaps) { same(cleanDesktopSpots(c.raw), c.out, c.name); if (c.raw !== null && typeof c.raw === "object" && !Array.isArray(c.raw)) same(cleanDesktopSpots(JSON.stringify(c.raw)), c.out, `${c.name} as JSON text`); }
  for (const text of ["{not json", "", "null", "[1]", "7", "\"x\""]) assert.deepEqual(cleanDesktopSpots(text), {}, JSON.stringify(text));
  const many = {};
  for (let i = 0; i < 300; i++) many[`${i},0,100,100`] = { x: i, y: i };
  const keys = Object.keys(cleanDesktopSpots(many));
  assert.equal(keys.length, MAX_DESKTOP_SPOTS);
  assert.deepEqual(keys, [...keys].sort(), "code-point order");
  const full = rememberSpot(many, LAPTOP, { x: 100, y: 100 }, "medium");
  assert.equal(Object.keys(full).length, MAX_DESKTOP_SPOTS);
  assert.ok("0,0,1512,982" in full, "the arrangement just written is always kept");
});

test("cleanDesktopSettings replays the fixture; 'on' is only the boolean true; the defaults are medium, off, no spots", () => {
  same(defaultDesktopSettings(), fx.settingsDefaults, "defaults");
  assert.ok(fx.settingsCases.length >= 41);
  for (const c of fx.settingsCases) { same(cleanDesktopSettings(c.raw), c.out, c.name); same(cleanDesktopSettings(cleanDesktopSettings(c.raw)), c.out, `${c.name} twice`); }
  for (const on of [1, "true", "1", [], {}, null, undefined, 0.5]) assert.equal(cleanDesktopSettings({ on }).on, false, JSON.stringify(on));
  for (const raw of [undefined, null, 5, "x", [], [{ on: true }], true]) same(cleanDesktopSettings(raw), fx.settingsDefaults, JSON.stringify(raw));
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (tests|pass|fail)" | cut -c1-90; cd ..
```

Expected: a line with `ERR_MODULE_NOT_FOUND` (the module `desktop.ts` does not exist yet), `# tests 1`, `# pass 0` and `# fail 1`.

- [ ] **Step 3: Write the module**

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/desktop.ts <<'EOF'
// The desktop cat (sub-project H): the big cat leaves the notch and lives on the desktop. These are the pure rules of it, a port of "The desktop cat" in
// design/prototype/cat-core.js (the tie-breaker; fixture tests/fixtures/cat/desktop-cases.json; docs/CAT-CONTRACT.md "The desktop cat (H-0)"): the trip `desktopStep`
// (seven phases) and the flight `desktopFlightAt`, the sizes, the frame rate `desktopFps`, the kittens' slots `desktopKittenSlots`, the spots on the screens
// (`screenKey`, `clampSpot`, `spotFor`, `rememberSpot`) and the stored settings `cleanDesktopSettings`. All new names: nothing in the older rules changes. Pure: no clock,
// no DOM, nothing is changed in place, and every function takes input of any shape and never throws. A spot is the head centre in points, y down, the origin at the top left of
// the main screen. Imports base.ts only, so the plain-Node checks (npm run check:cat) can load it.

import { EZ, clamp, own } from "./base.ts";

const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);
const isKittenId = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= 128;

// ── The trip ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** The seven phases of the trip. Frozen contract values, like the cat IDs. */
export const DESKTOP_PHASES = ["home", "flyingOut", "onDesktop", "retracting", "atNotchForAlert", "returning", "flyingHome"] as const;
export type DesktopPhase = (typeof DESKTOP_PHASES)[number];

export interface DesktopPhaseInfo { flight: boolean; dir: "out" | "in" | null; drawn: boolean; notchEmpty: boolean; on: boolean }
/** What a phase means to the app: in the air or not, which way it flies, whether the desktop window draws the cat, whether the notch's big-cat spot is empty, and whether Settings stores "out". */
export const DESKTOP_PHASE_INFO: Readonly<Record<DesktopPhase, DesktopPhaseInfo>> = {
  home: { flight: false, dir: null, drawn: false, notchEmpty: false, on: false },
  flyingOut: { flight: true, dir: "out", drawn: true, notchEmpty: true, on: true },
  onDesktop: { flight: false, dir: null, drawn: true, notchEmpty: true, on: true },
  retracting: { flight: true, dir: "in", drawn: true, notchEmpty: true, on: true },
  atNotchForAlert: { flight: false, dir: null, drawn: false, notchEmpty: false, on: true },
  returning: { flight: true, dir: "out", drawn: true, notchEmpty: true, on: true },
  flyingHome: { flight: true, dir: "in", drawn: true, notchEmpty: true, on: false },
};

export const DESKTOP_EVENTS = ["dragOut", "move", "toggle", "sendHome", "alertOn", "alertOff", "flightDone", "launch", "screensChanged"] as const;
export type DesktopEventType = (typeof DESKTOP_EVENTS)[number];
/** An event for the machine; `dragOut` and `move` carry the `spot` the cat was released at. */
export type DesktopEvent = { type: DesktopEventType; spot?: Spot };

export const DESKTOP_ACTS = ["place", "flyOut", "flyHome", "retract", "turn", "keep", "land", "dock", "goHome", "move", "resettle"] as const;
export type DesktopAct = (typeof DESKTOP_ACTS)[number];

/** phase, then event, then [next phase, act]. An event that is not listed makes no sense in that phase and changes nothing. */
export const DESKTOP_NEXT: Readonly<Record<DesktopPhase, Readonly<Partial<Record<DesktopEventType, readonly [DesktopPhase, DesktopAct]>>>>> = {
  home: { dragOut: ["onDesktop", "place"], toggle: ["flyingOut", "flyOut"], launch: ["flyingOut", "flyOut"] },
  flyingOut: { toggle: ["flyingHome", "turn"], sendHome: ["flyingHome", "turn"], alertOn: ["retracting", "turn"], flightDone: ["onDesktop", "land"], screensChanged: ["flyingOut", "resettle"] },
  onDesktop: { move: ["onDesktop", "move"], toggle: ["flyingHome", "flyHome"], sendHome: ["flyingHome", "flyHome"], alertOn: ["retracting", "retract"], screensChanged: ["onDesktop", "resettle"] },
  retracting: { toggle: ["flyingHome", "keep"], sendHome: ["flyingHome", "keep"], alertOff: ["returning", "turn"], flightDone: ["atNotchForAlert", "dock"] },
  atNotchForAlert: { toggle: ["home", "goHome"], sendHome: ["home", "goHome"], alertOff: ["returning", "flyOut"] },
  returning: { toggle: ["flyingHome", "turn"], sendHome: ["flyingHome", "turn"], alertOn: ["retracting", "turn"], flightDone: ["onDesktop", "land"], screensChanged: ["returning", "resettle"] },
  flyingHome: { toggle: ["flyingOut", "turn"], flightDone: ["home", "dock"] },
};

export interface Spot { x: number; y: number }
const SPOT_LIMIT = 1e5;
/** A spot is {x, y} of finite numbers no larger than 100000 in size; anything else is not a spot (null). The result has only x and y. */
export const spotOf = (v: unknown): Spot | null => (isPlain(v) && typeof v.x === "number" && typeof v.y === "number" && Math.abs(v.x) <= SPOT_LIMIT && Math.abs(v.y) <= SPOT_LIMIT ? { x: v.x, y: v.y } : null);

export interface DesktopStep { state: DesktopPhase; act: DesktopAct | null }

/** The trip's machine: `state` is a phase (anything else counts as home), `ev` an event. The next phase and what the app does, or the same phase and `act: null` when the event makes no sense there. */
export function desktopStep(state: unknown, ev: unknown): DesktopStep {
  const s: DesktopPhase = (DESKTOP_PHASES as readonly unknown[]).includes(state) ? (state as DesktopPhase) : "home";
  const same: DesktopStep = { state: s, act: null };
  if (!isPlain(ev) || typeof ev.type !== "string" || !own(DESKTOP_NEXT[s], ev.type)) return same;
  if ((ev.type === "dragOut" || ev.type === "move") && !spotOf(ev.spot)) return same;
  const [next, act] = DESKTOP_NEXT[s][ev.type as DesktopEventType] as readonly [DesktopPhase, DesktopAct];
  return { state: next, act };
}

/** The flight between the notch spot and the desktop spot takes this long (ms). */
export const DESKTOP_FLIGHT_MS = 600;
/** The arc bows `lift` of the distance away from the straight line, never more than `max` points, always upwards (a vertical flight bows to the right). */
export const DESKTOP_ARC = { lift: 0.25, max: 90 } as const;

/** Where the cat is `t` of the way along a flight (held to 0..1, a `t` that is not a number is 0): the position and scale 1 (the cat keeps its full size). The path is the same both ways. */
export function desktopFlightAt(from: unknown, to: unknown, t: unknown): { x: number; y: number; scale: number } {
  const f = spotOf(from) ?? { x: 0, y: 0 }, g = spotOf(to) ?? { x: 0, y: 0 };
  const k = typeof t === "number" && !Number.isNaN(t) ? clamp(t, 0, 1) : 0, q = EZ.inOut(k);
  const dx = g.x - f.x, dy = g.y - f.y, len = Math.hypot(dx, dy);
  let nx = 0, ny = 0;
  if (len > 0) { nx = dy / len; ny = -dx / len; if (ny > 0 || (ny === 0 && nx < 0)) { nx = -nx; ny = -ny; } }
  const lift = Math.min(len * DESKTOP_ARC.lift, DESKTOP_ARC.max), cx = (f.x + g.x) / 2 + nx * lift, cy = (f.y + g.y) / 2 + ny * lift, u = 1 - q;
  return { x: u * u * f.x + 2 * u * q * cx + q * q * g.x, y: u * u * f.y + 2 * u * q * cy + q * q * g.y, scale: 1 };
}

// ── Size, frame rate and kittens ────────────────────────────────────────────────────────────────────────────────────────────────────────

/** The three sizes, as the head width in points. The IDs are frozen contract values; `medium` is the default. */
export const DESKTOP_SIZES = { small: 48, medium: 64, large: 96 } as const;
export const DESKTOP_SIZE_IDS = ["small", "medium", "large"] as const;
export type DesktopSizeId = (typeof DESKTOP_SIZE_IDS)[number];
export const DEFAULT_DESKTOP_SIZE: DesktopSizeId = "medium";
/** A stored size to one of the three IDs; anything else, the case and the type included, is `medium`. */
export const desktopSizeOf = (v: unknown): DesktopSizeId => ((DESKTOP_SIZE_IDS as readonly unknown[]).includes(v) ? (v as DesktopSizeId) : DEFAULT_DESKTOP_SIZE);

/** The frame rates (per second): `asleep` is one still frame every 2 s, `off` draws nothing. */
export const DESKTOP_FPS = { motion: 60, active: 20, idle: 5, asleep: 0.5, off: 0 } as const;
/** The cursor is "near" the cat within this many points of the cat's centre. */
export const DESKTOP_NEAR = 150;

/** What the frame rate depends on; leave `cursorDist` out when the app cannot know it (Wayland). Only `true` counts for a flag. */
export interface DesktopFpsInput {
  phase: DesktopPhase; hidden?: boolean; dragging?: boolean; emote?: boolean; kittenMotion?: boolean; dance?: boolean; asleep?: boolean; working?: boolean; cursorDist?: number;
}
/** The frame rate to aim for: 0 when the phase is not drawn on the desktop or the cat is hidden; 60 for any motion (a flight included); 0.5 asleep; 20 working or the cursor near; else 5. */
export function desktopFps(i: unknown): number {
  if (!isPlain(i) || !(DESKTOP_PHASES as readonly unknown[]).includes(i.phase)) return DESKTOP_FPS.off;
  const info = DESKTOP_PHASE_INFO[i.phase as DesktopPhase];
  if (!info.drawn || i.hidden === true) return DESKTOP_FPS.off;
  if (info.flight || i.dragging === true || i.emote === true || i.kittenMotion === true || i.dance === true) return DESKTOP_FPS.motion;
  if (i.asleep === true) return DESKTOP_FPS.asleep;
  if (i.working === true || (typeof i.cursorDist === "number" && Number.isFinite(i.cursorDist) && i.cursorDist <= DESKTOP_NEAR)) return DESKTOP_FPS.active;
  return DESKTOP_FPS.idle;
}

/** Where the desktop cat's kittens sit, in D (the head width) from its head centre, x right, y down: up to 3 in a row at the lower right, then "+N" at the next slot. */
export const DESKTOP_KITTEN_PLACE = { unit: "D", max: 3, d: 0.3, x0: 0.82, y0: 0.22, step: 0.33, moreSize: 0.2 } as const;

export interface DesktopKittenSlots {
  place: "desktop"; unit: "D"; count: number; shown: { id: string; state: string; x: number; y: number; d: number }[]; more: number; moreAt: { x: number; y: number; size: number } | null; label: null;
}
/** The slots for the cat's kittens (`kittens` is what kittenView returned, already in order). `side` -1 mirrors every x (a cat in the right half of its screen); anything else is 1. */
export function desktopKittenSlots(kittens: unknown, side?: unknown): DesktopKittenSlots {
  const P = DESKTOP_KITTEN_PLACE, m = side === -1 ? -1 : 1;
  const L = (Array.isArray(kittens) ? kittens : []).filter((k): k is Record<string, unknown> => isPlain(k) && isKittenId(k.id)), count = L.length, n = Math.min(count, P.max), more = count - n;
  return {
    place: "desktop", unit: "D", count,
    shown: L.slice(0, n).map((k, i) => ({ id: k.id as string, state: typeof k.state === "string" ? k.state : "working", x: m * (P.x0 + i * P.step), y: P.y0, d: P.d })),
    more, moreAt: more > 0 ? { x: m * (P.x0 + P.max * P.step), y: P.y0, size: P.moreSize } : null, label: null,
  };
}

// ── Spots on the screens ────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** The cat keeps this many points between its head and the edge of the visible frame. */
export const DESKTOP_MARGIN = 24;
/** The first spot ever: this fraction of the main screen's visible frame across and down. */
export const DESKTOP_DEFAULT = { x: 0.6, y: 1 / 3 } as const;
/** A stored map keeps the spots of at most this many screen arrangements. */
export const MAX_DESKTOP_SPOTS = 32;

export interface Rect { x: number; y: number; w: number; h: number }
/** A screen: `frame` the whole screen, `visible` what the menu bar and the taskbar leave, `main` the screen with the primary taskbar. In points, y down. */
export interface Screen { frame: Rect; visible: Rect; main: boolean }

const rectOf = (v: unknown): Rect | null => (isPlain(v) && ["x", "y", "w", "h"].every((k) => typeof v[k] === "number" && Math.abs(v[k] as number) <= 1e6) && (v.w as number) >= 1 && (v.h as number) >= 1 ? { x: v.x as number, y: v.y as number, w: v.w as number, h: v.h as number } : null);
/** The screens that are screens, sorted by frame and at most 16; a visible frame that is missing or outside its frame is the frame. */
function screensOf(raw: unknown): Screen[] {
  const out: Screen[] = [];
  for (const s of Array.isArray(raw) ? raw.slice(0, 256) : []) {
    const f = isPlain(s) ? rectOf(s.frame) : null;
    if (!f) continue;
    const v = rectOf((s as Record<string, unknown>).visible), x0 = v ? Math.max(v.x, f.x) : 0, y0 = v ? Math.max(v.y, f.y) : 0, x1 = v ? Math.min(v.x + v.w, f.x + f.w) : 0, y1 = v ? Math.min(v.y + v.h, f.y + f.h) : 0;
    out.push({ frame: f, visible: v && x1 > x0 && y1 > y0 ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : f, main: (s as Record<string, unknown>).main === true });
  }
  return out.sort((a, b) => a.frame.x - b.frame.x || a.frame.y - b.frame.y || a.frame.w - b.frame.w || a.frame.h - b.frame.h).slice(0, 16);
}
const roundHalfUp = (v: number) => Math.floor(v + 0.5);

/** The key an arrangement of screens is remembered under: the frames rounded to whole points (half up), sorted, written `x,y,w,h` and joined with `|`; no usable screen is "". */
export function screenKey(screens: unknown): string {
  return screensOf(screens).map((s) => [s.frame.x, s.frame.y, s.frame.w, s.frame.h].map(roundHalfUp)).sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2] || a[3] - b[3]).map((r) => r.join(",")).join("|");
}
const SCREEN_KEY = /^-?\d{1,7},-?\d{1,7},\d{1,7},\d{1,7}(\|-?\d{1,7},-?\d{1,7},\d{1,7},\d{1,7}){0,15}$/;
/** True for exactly the strings screenKey writes: the whole-string shape, no leading zeros or -0, positive sizes, frames in sorted order, at most 16. */
export const isScreenKey = (k: unknown): k is string =>
  typeof k === "string" && SCREEN_KEY.test(k) && screenKey(k.split("|").map((q) => { const [x, y, w, h] = q.split(",").map(Number); return { frame: { x, y, w, h } }; })) === k;

const holds = (r: Rect, p: Spot) => p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h;
const mainScreen = (S: Screen[]): Screen => S.find((s) => s.main) ?? S.find((s) => holds(s.frame, { x: 0, y: 0 })) ?? S[0];
/** The spot held inside a screen's visible frame, `d` (the head width) and DESKTOP_MARGIN from every edge; a frame too small for that holds the centre. */
function place(s: Screen, p: Spot, d: number): Spot {
  const v = s.visible, m = DESKTOP_MARGIN + d / 2, at = (lo: number, len: number, c: number) => (len <= 2 * m ? lo + len / 2 : clamp(c, lo + m, lo + len - m));
  return { x: at(v.x, v.w, p.x), y: at(v.y, v.h, p.y) };
}

/** The first spot ever, on the main screen, for a size ID. null with no screens. */
export function defaultDesktopSpot(screens: unknown, size?: unknown): Spot | null {
  const S = screensOf(screens);
  if (!S.length) return null;
  const s = mainScreen(S), v = s.visible;
  return place(s, { x: v.x + v.w * DESKTOP_DEFAULT.x, y: v.y + v.h * DESKTOP_DEFAULT.y }, DESKTOP_SIZES[desktopSizeOf(size)]);
}

/** Keeps a spot where the cat may sit: on the screen whose frame holds it, inside that screen's visible frame, 24 points from the head's edge. A spot on no screen goes to the main screen's default spot; null with no screens. */
export function clampSpot(spot: unknown, screens: unknown, size?: unknown): Spot | null {
  const S = screensOf(screens);
  if (!S.length) return null;
  const p = spotOf(spot), s = p && S.find((q) => holds(q.frame, p));
  return s && p ? place(s, p, DESKTOP_SIZES[desktopSizeOf(size)]) : defaultDesktopSpot(screens, size);
}

/** A stored map from screen key to spot, cleaned: an object or its JSON text, only keys isScreenKey accepts, only values that are spots, in code-point order of the keys, the first 32. */
export function cleanDesktopSpots(raw: unknown): Record<string, Spot> {
  let v = raw;
  if (typeof v === "string") { try { v = JSON.parse(v); } catch { return {}; } }
  const out: Record<string, Spot> = {};
  if (!isPlain(v)) return out;
  let n = 0;
  for (const k of Object.keys(v).filter(isScreenKey).sort()) {
    if (n >= MAX_DESKTOP_SPOTS) break;
    const s = spotOf(v[k]);
    if (s) { out[k] = s; n++; }
  }
  return out;
}

/** The spot to use now: the one remembered for this arrangement, held where the cat may sit, else the default spot. null with no screens. */
export function spotFor(spots: unknown, screens: unknown, size?: unknown): Spot | null {
  if (!screensOf(screens).length) return null;
  const k = screenKey(screens), m = cleanDesktopSpots(spots);
  return own(m, k) ? clampSpot(m[k], screens, size) : defaultDesktopSpot(screens, size);
}

/** The map after the cat was released at `spot` on these screens: this arrangement's spot is the clamped one, the others stay, and the new key is always kept. */
export function rememberSpot(spots: unknown, screens: unknown, spot: unknown, size?: unknown): Record<string, Spot> {
  const m = cleanDesktopSpots(spots), c = clampSpot(spot, screens, size);
  if (!c) return m;
  const k = screenKey(screens), out: Record<string, Spot> = {};
  for (const q of Object.keys(m).filter((q) => q !== k).slice(0, MAX_DESKTOP_SPOTS - 1).concat(k).sort()) out[q] = q === k ? c : m[q];
  return out;
}

// ── The stored settings ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** What the cat's menu and Settings save: whether it is out, its size, and its spot for each arrangement of screens. In settings.json it is the `desktop` object of the `cat` block. */
export interface DesktopSettings { on: boolean; size: DesktopSizeId; spots: Record<string, Spot> }

/** Everything the desktop cat saves, cleaned: `on` is true only for the boolean true, `size` one of the three IDs, `spots` as cleanDesktopSpots. Raw in, clean out, never a throw. */
export function cleanDesktopSettings(raw: unknown): DesktopSettings {
  const r: Record<string, unknown> = isPlain(raw) ? raw : {};
  return { on: r.on === true, size: desktopSizeOf(r.size), spots: cleanDesktopSpots(r.spots) };
}
/** What a fresh install holds: the cat at home, Medium, no spots. */
export const defaultDesktopSettings = (): DesktopSettings => cleanDesktopSettings(null);
EOF
```

- [ ] **Step 4: Run it to see it pass**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..
```

Expected: `# tests 13`, `# pass 13`, `# fail 0`.

- [ ] **Step 5: Prove the tests can bite**

Each line changes one rule, runs the file and puts the rule back.

Run:

```bash
cd windows
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktop.ts 'export const DESKTOP_MARGIN = 24;' 'export const DESKTOP_MARGIN = 20;' scripts/cat-tests/desktop.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktop.ts 'if (ny > 0 || (ny === 0 && nx < 0))' 'if (ny > 0)' scripts/cat-tests/desktop.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktop.ts 'i.asleep === true) return DESKTOP_FPS.asleep' 'i.asleep !== false) return DESKTOP_FPS.asleep' scripts/cat-tests/desktop.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktop.ts 'if (n >= MAX_DESKTOP_SPOTS) break;' 'if (n > MAX_DESKTOP_SPOTS) break;' scripts/cat-tests/desktop.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktop.ts 'on: r.on === true' 'on: !!r.on' scripts/cat-tests/desktop.test.mjs
cd ..
```

Expected, in order: `# fail 2`, `# fail 1`, `# fail 1`, `# fail 2`, `# fail 1` (each line also prints `# pass` with the rest of the 13).

- [ ] **Step 6: Run the whole checks**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `ℹ tests 287`, `ℹ pass 287`, `ℹ fail 0`.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src/cat/desktop.ts windows/scripts/cat-tests/desktop.test.mjs
git commit -F - <<'MSG'
feat(desktop): the contract's desktop rules in TypeScript

The trip machine, the flight, the sizes, the frame rate, the kitten slots, the spots on the screens and the stored settings, replayed from desktop-cases.json.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model.

---

### Task 2: Settings: `desktop` in the block (TypeScript and Rust), kept at every save, and the Settings switch

**Agent:** `nm-implementer` (Haiku 5.5, high). The Rust steps need the image (`image ok`); without it they are owed and the TypeScript steps go on.

**Files:**
- Modify: `windows/src/cat/display.ts`, `windows/scripts/cat-tests/display.test.mjs`, `windows/src/settings/cat.ts`
- Create: `windows/scripts/cat-tests/desktop-settings.test.mjs`
- Modify: `windows/src-tauri/src/cat_settings.rs`, `windows/src-tauri/src/settings.rs`

**Interfaces:**
- Consumes: Task 1's `cleanDesktopSettings`, `cleanDesktopSpots`, `desktopSizeOf`, `DesktopSettings`; the earlier plan's `cleanCatBlock`, `withCatSettings` and the Cat section's `row` and `.switch`.
- Produces: `CatBlock` with `desktop`; `withDesktop`, `withDesktopOn`, `withDesktopSize`, `withDesktopSpots`; the Rust `clean_desktop_settings`, `clean_desktop_spots`, `is_screen_key`, and `clean_cat_block` that cleans all three parts; the Settings row "Cat on the desktop" (the same switch the tray item and the cat's menu use: the island sees the stored "out" change and takes the trip, Task 5).

- [ ] **Step 1: Write the tests**

`desktop-settings.test.mjs` is new; `display.test.mjs` already pins the block's key list, so its three lines that count keys move with it (the script in Step 3 does it).

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-settings.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { defaultDesktopSettings } from "../../src/cat/desktop.ts";
import * as D from "../../src/cat/display.ts";
import { cleanCatSettings, withCharacter } from "../../src/cat/settings.ts";
import { load, same } from "./util.mjs";

// The desktop cat's settings live in the `cat` block of settings.json beside the Cat settings and the Display settings, and no clean-up of the block drops them (sub-project H).
const fx = load("desktop-cases.json");
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const SPOTS = { "0,0,1512,982": { x: 300, y: 400 }, "0,0,1512,982|1512,-100,2560,1440": { x: 2000, y: 800 } };

test("the block holds `desktop`: fresh installs get the cat at home, Medium, no spots; the Cat settings and Display settings are untouched by it", () => {
  const b = D.defaultCatBlock();
  same(b.desktop, defaultDesktopSettings(), "default");
  assert.deepEqual(cleanCatSettings(b), cleanCatSettings({ ...b, desktop: undefined }));
  assert.deepEqual(D.cleanCatBlock({ desktop: { on: true, size: "large", spots: SPOTS } }).desktop, { on: true, size: "large", spots: SPOTS });
  for (const c of fx.settingsCases) same(D.cleanCatBlock({ desktop: c.raw }).desktop, c.out, c.name);
  assert.deepEqual(D.cleanCatBlock({ desktop: SPOTS }).desktop, defaultDesktopSettings(), "a block whose desktop is the wrong shape is the default");
});

test("a block cleaned again, or through JSON, is the same block, and a hostile `desktop` never throws or leaks into the other keys", () => {
  const b = D.cleanCatBlock({ character: "momo", displayMode: "two", desktop: { on: true, size: "small", spots: SPOTS, extra: 1 } });
  assert.deepEqual(D.cleanCatBlock(b), b);
  assert.deepEqual(D.cleanCatBlock(JSON.parse(JSON.stringify(b))), b);
  assert.equal("extra" in b.desktop, false);
  for (const desktop of [undefined, null, 5, "on", [], [true], { on: "true" }, { size: "XL" }, { spots: "{not json" }, JSON.parse('{"spots":{"__proto__":{"x":1,"y":1}}}')]) {
    const out = D.cleanCatBlock({ character: "ginger", desktop });
    assert.equal(out.character, "ginger");
    assert.deepEqual(Object.keys(out.desktop).sort(), ["on", "size", "spots"]);
  }
});

test("an edit of the Cat settings, of the Display settings or of the desktop each keep the other two parts", () => {
  const start = D.withDesktopOn(D.withDesktopSize(D.withDisplayMode(D.defaultCatBlock(), "two"), "large"), true);
  assert.deepEqual([start.desktop.on, start.desktop.size, start.displayMode], [true, "large", "two"]);
  const edited = D.withCatSettings(start, withCharacter(start, "momo"));
  assert.deepEqual([edited.character, edited.desktop, edited.displayMode], ["momo", start.desktop, "two"]);
  const shown = D.withDisplayMode(start, "perAgent");
  assert.deepEqual([shown.desktop, shown.character], [start.desktop, start.character]);
  const sized = D.withDesktopSize(start, "small");
  assert.deepEqual([sized.desktop.size, sized.desktop.on, sized.displayMode], ["small", true, "two"]);
  assert.equal(D.withDesktopSize(start, "Huge").desktop.size, "medium", "an unknown size is Medium");
  assert.equal(D.withDesktopOn(start, false).desktop.on, false);
  assert.equal(D.withDesktopOn(start, 1).desktop.on, false, "only the boolean true is on");
  const spotted = D.withDesktopSpots(start, SPOTS);
  assert.deepEqual(spotted.desktop.spots, SPOTS);
  assert.deepEqual(D.withDesktopSpots(spotted, { nope: { x: 1, y: 1 } }).desktop.spots, {}, "a key that is not a screen arrangement is dropped");
  assert.deepEqual(Object.keys(start).sort(), Object.keys(D.defaultCatBlock()).sort());
});

test("the edits never touch their input", () => {
  const b = Object.freeze(D.defaultCatBlock());
  const before = JSON.stringify(b);
  D.withDesktopOn(b, true); D.withDesktopSize(b, "small"); D.withDesktopSpots(b, SPOTS); D.withDesktop(b, { on: true });
  assert.equal(JSON.stringify(b), before);
});

test("State starts with the default block, and the Settings window and the island both clean the whole block", () => {
  assert.match(source("core/state.ts"), /cat: defaultCatBlock\(\),/);
  assert.match(source("settings/main.ts"), /settings\.cat = cleanCatBlock\(settings\.cat\);/);
  assert.match(source("island/island.ts"), /const block = cleanCatBlock\(State\.settings\.cat\);/);
});

test("Settings → Cat has the 'Cat on the desktop' switch under the Display picker and its preview, built from the window's own row and switch, saving through withCatSettings", () => {
  const cat = source("settings/cat.ts");
  assert.match(cat, /row\("Cat on the desktop", desktop, /);
  assert.match(cat, /onclick: \(\) => change\(withDesktopOn\(host\.cat\(\), !host\.cat\(\)\.desktop\.on\)\)/);
  assert.match(cat, /desktop\.classList\.toggle\("on", out\);/);
  const at = (t) => cat.indexOf(t);
  assert.ok(at("...display.before,") < at('row("Cat on the desktop"') && at('row("Cat on the desktop"') < at("Main cat: the cat of One cat mode"), "right under the Display rows, above the Main cat");
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-settings.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..
```

Expected: `# tests 6`, `# pass 1`, `# fail 5` (the block has no `desktop` yet; only the State and island pin test passes).

- [ ] **Step 3: Edit the block, its tests and the Cat section**

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/cat/display.ts", [
('''import { catIdOf, cleanCatSettings } from "./settings.ts";
import type { CatSettings } from "./settings.ts";''', '''import { cleanDesktopSettings, cleanDesktopSpots, desktopSizeOf } from "./desktop.ts";
import type { DesktopSettings } from "./desktop.ts";
import { catIdOf, cleanCatSettings } from "./settings.ts";
import type { CatSettings } from "./settings.ts";'''),
('''// ── The whole `cat` block: the Cat settings and the Display settings ────────────────────────────────────────────────────────────────────────

/** The `cat` block of settings.json, clean: the Cat settings (settings.ts) and the Display settings. */
export type CatBlock = CatSettings & DisplaySettings;

/** Cleans the block with both clean-ups: a clean-up that used cleanCatSettings alone would drop the three display keys at the next save. Never throws. */
export const cleanCatBlock = (raw: unknown): CatBlock => ({ ...cleanCatSettings(raw), ...cleanDisplaySettings(raw) });''', '''// ── The whole `cat` block: the Cat settings, the Display settings and the desktop cat's ────────────────────────────────────────────────────

/** The `cat` block of settings.json, clean: the Cat settings (settings.ts), the Display settings and the desktop cat's (`desktop`, desktop.ts: sub-project H). */
export type CatBlock = CatSettings & DisplaySettings & { desktop: DesktopSettings };

/** Cleans the block with all three clean-ups: a clean-up that used cleanCatSettings alone would drop the display keys and `desktop` at the next save. Never throws. */
export const cleanCatBlock = (raw: unknown): CatBlock => ({ ...cleanCatSettings(raw), ...cleanDisplaySettings(raw), desktop: cleanDesktopSettings(isPlain(raw) ? raw.desktop : undefined) });'''),
('''/** The dice and "Reset to defaults" give back a whole map (rerollAgentCat's and assignAgentCats'). */
export const withAgentCats''', '''/** The desktop cat's settings, changed in part: whether it is out, its size, its spots. Each is cleaned with the rest of the block. */
export const withDesktop = (b: CatBlock, patch: Partial<DesktopSettings>): CatBlock => cleanCatBlock({ ...b, desktop: { ...b.desktop, ...patch } });
export const withDesktopOn = (b: CatBlock, on: boolean): CatBlock => withDesktop(b, { on });
export const withDesktopSize = (b: CatBlock, size: unknown): CatBlock => withDesktop(b, { size: desktopSizeOf(size) });
export const withDesktopSpots = (b: CatBlock, spots: unknown): CatBlock => withDesktop(b, { spots: cleanDesktopSpots(spots) });
/** The dice and "Reset to defaults" give back a whole map (rerollAgentCat's and assignAgentCats'). */
export const withAgentCats'''),
])

edit("windows/scripts/cat-tests/display.test.mjs", [
('test("the whole block: the Cat settings and the Display settings are cleaned together, and a clean-up with the Cat settings alone would drop the display keys"', 'test("the whole block: the Cat settings, the Display settings and the desktop cat\'s are cleaned together, and a clean-up with the Cat settings alone would drop the display keys"'),
('["agentCats", "cats", "character", "collar", "displayMode", "furLines", "motionStyle", "pair"]', '["agentCats", "cats", "character", "collar", "desktop", "displayMode", "furLines", "motionStyle", "pair"]'),
('assert.deepEqual(D.cleanCatBlock(null), { ...defaultCatSettings(), ...DEFAULTS });', 'assert.deepEqual(D.cleanCatBlock(null), { ...defaultCatSettings(), ...DEFAULTS, desktop: { on: false, size: "medium", spots: {} } });'),
('"all eight keys"', '"all nine keys"'),
])

edit("windows/src/settings/cat.ts", [
('import { withCatSettings, type CatBlock } from "../cat/display";', 'import { withCatSettings, withDesktopOn, type CatBlock } from "../cat/display";'),
('''  const fur = h("button", { class: "switch", "aria-pressed": "false", onclick: () => change(withFurLines(now(), !now().furLines)) });
''', '''  const fur = h("button", { class: "switch", "aria-pressed": "false", onclick: () => change(withFurLines(now(), !now().furLines)) });
  // Cat on the desktop (sub-project H): the same switch as the tray's item and the cat's own menu. The island sees the stored "out" change and sends the cat on its trip.
  const desktop = h("button", { class: "switch", "aria-pressed": "false", "aria-label": "Cat on the desktop", onclick: () => change(withDesktopOn(host.cat(), !host.cat().desktop.on)) });
'''),
('''    fur.classList.toggle("on", s.furLines);
    fur.setAttribute("aria-pressed", String(s.furLines));
''', '''    fur.classList.toggle("on", s.furLines);
    fur.setAttribute("aria-pressed", String(s.furLines));
    const out = host.cat().desktop.on;
    desktop.classList.toggle("on", out);
    desktop.setAttribute("aria-pressed", String(out));
'''),
('''    ...display.before,
    h("div", { class: "hint", text: "Main cat:''', '''    ...display.before,
    row("Cat on the desktop", desktop, h("span", { class: "hint", text: "Drag the big cat out of the notch, or switch it here. Double-click it to send it home." })),
    h("div", { class: "hint", text: "Main cat:'''),
])
print("applied")
PYEOF
```

- [ ] **Step 4: Run the tests and the type check**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; node --experimental-strip-types --test scripts/cat-tests/desktop-settings.test.mjs scripts/cat-tests/display.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `# tests 16`, `# pass 16`, `# fail 0` (the two files), then `ℹ tests 293`, `ℹ pass 293`, `ℹ fail 0`.

- [ ] **Step 5: Prove it bites**

Run:

```bash
cd windows
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/display.ts ', desktop: cleanDesktopSettings(isPlain(raw) ? raw.desktop : undefined)' '' scripts/cat-tests/desktop-settings.test.mjs
cd ..
```

Expected: `# fail 3` (a block with no clean-up of `desktop` drops it).

- [ ] **Step 6: Look at the Settings switch**

The Settings page renders in the browser (the bridge is a no-op there). Start the dev server (see "Starting and stopping the dev server"), then:

```bash
cd .claude/checkpoints/h-tauri
playwright-cli -s=htauri-set open 'http://127.0.0.1:14611/settings.html' > /dev/null 2>&1
playwright-cli -s=htauri-set resize 700 900 > /dev/null 2>&1
playwright-cli -s=htauri-set eval "(() => { const el = document.querySelector('[aria-label=\"Cat on the desktop\"]'); el.closest('.row').scrollIntoView({block:'start'}); window.scrollBy(0,-160); return el.className; })()" 2>&1 | grep -A1 "### Result"
playwright-cli -s=htauri-set screenshot --filename="$(pwd)/settings-switch.png" > /dev/null 2>&1
playwright-cli -s=htauri-set close > /dev/null 2>&1
cd ../../..
```

Expected: a result containing `switch` (the switch is off), then `settings-switch.png` in `.claude/checkpoints/h-tauri/`. Look at it: the row "Cat on the desktop" sits right under the Display row's preview and above the Main cat's hint, with the window's own switch, off, and a one-line hint. Say what you saw. (Keep this picture for Checkpoint 1.)

- [ ] **Step 7: The Rust twin**

The tests are written with the code, and they replay the fixture and the settings round trips. The script adds `is_screen_key`, `clean_desktop_spots`, `clean_desktop_settings` to `cat_settings.rs`, makes `clean_cat_block` clean all three parts (so `settings::sanitized` keeps `desktop` at every save) and adds the tests; the `desktop` key is in `block_default()` from then on.

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

CAT = "windows/src-tauri/src/cat_settings.rs"
edit(CAT, [
('''// returns only the five Cat settings and drops those keys, so the block is cleaned with both, by `clean_cat_block`: a clean-up with the Cat settings alone would
// drop the three display keys at the next save.
''', '''// returns only the five Cat settings and drops those keys, so the block is cleaned with both, by `clean_cat_block`: a clean-up with the Cat settings alone would
// drop the three display keys at the next save.
//
// And the desktop cat's settings (sub-project H), cleaned by `clean_desktop_settings`, a port of `cleanDesktopSettings` in the same file of the contract
// (tests/fixtures/cat/desktop-cases.json): `desktop: { on, size, spots: { <screenKey>: { x, y } } }`. `clean_cat_block` cleans that too.
'''),
('''/// The whole `cat` block: the Cat settings and the Display settings, each cleaned by its own clean-up. This is what `settings::sanitized` runs the block through.
pub fn clean_cat_block(raw: &Value) -> Value {
    let mut block = clean_cat_settings(raw);
    if let (Some(o), Value::Object(display)) = (block.as_object_mut(), clean_display_settings(raw)) {
        for (k, v) in display {
            o.insert(k, v);
        }
    }
    block
}
''', '''// ── The desktop cat's settings (sub-project H) ────────────────────────────────────────────────────────────────────────────────────────────────

/// The desktop cat's size IDs: frozen contract values. An unknown stored size is `medium`.
const DESKTOP_SIZES: [&str; 3] = ["small", "medium", "large"];
/// A stored map keeps the spots of at most this many screen arrangements (the first by code-point order of their keys).
pub const MAX_DESKTOP_SPOTS: usize = 32;
/// A spot is two numbers no larger than this in size.
const SPOT_LIMIT: f64 = 100_000.0;

/// One frame of a screen key, `x,y,w,h`: whole numbers of one to seven digits, `x` and `y` with an optional minus sign.
fn frame_of(q: &str) -> Option<[i64; 4]> {
    let parts: Vec<&str> = q.split(',').collect();
    if parts.len() != 4 {
        return None;
    }
    let mut out = [0i64; 4];
    for (i, p) in parts.iter().copied().enumerate() {
        let digits = if i < 2 { p.strip_prefix('-').unwrap_or(p) } else { p };
        if digits.is_empty() || digits.len() > 7 || !digits.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        out[i] = p.parse().ok()?;
    }
    Some(out)
}

/// True for exactly the strings `screenKey` writes (cat-core.js): one to sixteen frames `x,y,w,h` joined with `|`, in sorted order, sizes of at least 1, nothing past a million, and
/// the digits written the way a number is (no leading zero, no `-0`), the whole string.
pub fn is_screen_key(k: &str) -> bool {
    let frames: Vec<&str> = k.split('|').collect();
    if frames.len() > 16 {
        return false;
    }
    let mut rects: Vec<[i64; 4]> = Vec::new();
    for q in frames {
        match frame_of(q) {
            Some(r) => rects.push(r),
            None => return false,
        }
    }
    if rects.iter().any(|r| r.iter().any(|v| v.abs() > 1_000_000) || r[2] < 1 || r[3] < 1) || !rects.windows(2).all(|w| w[0] <= w[1]) {
        return false;
    }
    let written: Vec<String> = rects.iter().map(|r| format!("{},{},{},{}", r[0], r[1], r[2], r[3])).collect();
    written.join("|") == k
}

/// A spot, `{x, y}` of two numbers no larger than 100000 in size, reduced to those two; None for anything else.
fn spot_of(v: &Value) -> Option<Value> {
    let o = v.as_object()?;
    let (x, y) = (o.get("x")?, o.get("y")?);
    let (fx, fy) = (x.as_f64()?, y.as_f64()?);
    (fx.abs() <= SPOT_LIMIT && fy.abs() <= SPOT_LIMIT).then(|| json!({ "x": x, "y": y }))
}

/// A stored map from screen key to spot, cleaned: an object or the JSON text of one (text that is not JSON is `{}`), only the keys `is_screen_key` accepts (`__proto__` is never
/// one), only values that are spots, in code-point order of the keys, the first 32.
pub fn clean_desktop_spots(raw: &Value) -> Value {
    let parsed;
    let v = match raw {
        Value::String(s) => {
            parsed = serde_json::from_str::<Value>(s).unwrap_or(Value::Null);
            &parsed
        }
        other => other,
    };
    let mut out = Map::new();
    let Some(o) = v.as_object() else { return Value::Object(out) };
    let mut keys: Vec<&String> = o.keys().filter(|k| is_screen_key(k)).collect();
    keys.sort();
    for k in keys {
        if out.len() >= MAX_DESKTOP_SPOTS {
            break;
        }
        if let Some(s) = o.get(k.as_str()).and_then(spot_of) {
            out.insert(k.clone(), s);
        }
    }
    Value::Object(out)
}

/// Everything the desktop cat saves, cleaned: `{ on, size, spots }`. `on` is true only for the boolean true (the number 1 and the text "true" are off), `size` one of the three
/// IDs (anything else is `medium`), `spots` as `clean_desktop_spots`. Never panics.
pub fn clean_desktop_settings(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    json!({
        "on": r.get("on") == Some(&Value::Bool(true)),
        "size": word(r.get("size"), &DESKTOP_SIZES, "medium"),
        "spots": clean_desktop_spots(r.get("spots").unwrap_or(&NULL)),
    })
}

/// The whole `cat` block: the Cat settings, the Display settings and the desktop cat's, each cleaned by its own clean-up. This is what `settings::sanitized` runs the block through.
pub fn clean_cat_block(raw: &Value) -> Value {
    let mut block = clean_cat_settings(raw);
    if let (Some(o), Value::Object(display)) = (block.as_object_mut(), clean_display_settings(raw)) {
        for (k, v) in display {
            o.insert(k, v);
        }
    }
    if let Some(o) = block.as_object_mut() {
        o.insert("desktop".to_string(), clean_desktop_settings(raw.get("desktop").unwrap_or(&NULL)));
    }
    block
}
'''),
('''    #[test]
    fn the_whole_block_keeps_both_parts_and_a_clean_up_with_the_cat_settings_alone_drops_the_display_keys() {''', '''    #[test]
    fn the_desktop_clean_up_replays_the_fixture() {
        let fx = fixture("desktop-cases.json");
        let keys = fx["isScreenKey"].as_array().unwrap();
        assert!(keys.len() >= 30);
        for c in keys {
            assert_eq!(c["key"].as_str().map(is_screen_key).unwrap_or(false), c["out"].as_bool().unwrap(), "key {}", c["key"]);
        }
        let cases = fx["settingsCases"].as_array().unwrap();
        assert!(cases.len() >= 41);
        for c in cases {
            assert_same(&clean_desktop_settings(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
        for c in fx["spotMaps"].as_array().unwrap() {
            assert_same(&clean_desktop_spots(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
        assert_same(&clean_desktop_settings(&Value::Null), &fx["settingsDefaults"], "defaults");
        let sizes: Vec<&str> = fx["sizeIds"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(sizes, DESKTOP_SIZES);
        assert_eq!(fx["maxSpots"].as_u64(), Some(MAX_DESKTOP_SPOTS as u64));
    }

    #[test]
    fn the_desktop_spots_keep_the_first_32_in_code_point_order_and_hostile_input_never_panics() {
        let mut many = Map::new();
        for i in (0..300).rev() {
            many.insert(format!("{i},0,100,100"), json!({"x": i, "y": i}));
        }
        let out = clean_desktop_spots(&Value::Object(many));
        let keys: Vec<&String> = out.as_object().unwrap().keys().collect();
        assert_eq!(keys.len(), MAX_DESKTOP_SPOTS);
        let mut sorted = keys.clone();
        sorted.sort();
        assert_eq!(keys, sorted, "code-point order");
        for raw in [
            json!(null), json!(5), json!("{not json"), json!("[1]"), json!([1]), json!({"__proto__": {"x": 1, "y": 1}}),
            json!({"0,0,1,1": {"x": "1", "y": 2}}), json!({"0,0,1,1": {"x": 1e300, "y": 2}}), json!({"0,0,1,1": [1, 2]}), json!({"-0,0,1,1": {"x": 1, "y": 2}}),
            json!({"0,0,1512,982\\n": {"x": 1, "y": 2}}), json!({"007,0,10,10": {"x": 1, "y": 2}}), json!({"0,0,0,10": {"x": 1, "y": 2}}), json!({"5,0,1,1|0,0,1,1": {"x": 1, "y": 2}}),
        ] {
            assert_eq!(clean_desktop_spots(&raw), json!({}), "{raw}");
        }
        assert_eq!(clean_desktop_spots(&json!("{\\"0,0,1512,982\\":{\\"x\\":3,\\"y\\":4,\\"z\\":5}}")), json!({"0,0,1512,982": {"x": 3, "y": 4}}), "the Mac's JSON text, reduced to x and y");
        assert_eq!(clean_desktop_settings(&json!({"on": "true", "size": "XL"})), json!({"on": false, "size": "medium", "spots": {}}));
        assert_eq!(clean_desktop_settings(&json!({"on": 1})), clean_desktop_settings(&Value::Null));
        assert_eq!(clean_desktop_settings(&json!({"on": true, "size": "large", "extra": 1})), json!({"on": true, "size": "large", "spots": {}}));
        for raw in [json!(null), json!(5), json!([]), json!("x")] {
            assert_eq!(clean_desktop_settings(&raw), clean_desktop_settings(&Value::Null), "{raw}");
        }
    }

    #[test]
    fn the_whole_block_holds_the_desktop_settings_and_cleaning_it_twice_changes_nothing() {
        let raw = json!({"character": "momo", "displayMode": "two", "desktop": {"on": true, "size": "small", "spots": {"0,0,1512,982": {"x": 300, "y": 400}}}});
        let block = clean_cat_block(&raw);
        assert_eq!(block["desktop"], json!({"on": true, "size": "small", "spots": {"0,0,1512,982": {"x": 300, "y": 400}}}));
        assert_eq!((&block["character"], &block["displayMode"]), (&json!("momo"), &json!("two")));
        assert_eq!(clean_cat_block(&block), block);
        assert_eq!(block_default()["desktop"], json!({"on": false, "size": "medium", "spots": {}}));
        assert!(clean_cat_settings(&raw).get("desktop").is_none(), "the Cat settings clean-up alone drops it: that is why the block has a clean-up of its own");
        assert!(clean_display_settings(&raw).get("desktop").is_none());
    }

    #[test]
    fn the_whole_block_keeps_both_parts_and_a_clean_up_with_the_cat_settings_alone_drops_the_display_keys() {'''),
])

SET = "windows/src-tauri/src/settings.rs"
edit(SET, [
('''    /// The webview is not trusted, and a hand-edited file is not either: bad display keys are cleaned without failing the file or touching the rest of the block.''', '''    /// The desktop cat's settings sit in the same `cat` block: a save keeps them, a load gives them back, and `sanitized` cleans them.
    #[test]
    fn the_desktop_settings_survive_a_save_a_load_and_a_round_trip() {
        let dir = std::env::temp_dir().join(format!("notchmeow-desktop-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.cat = serde_json::json!({
            "character": "momo", "displayMode": "two",
            "desktop": {"on": true, "size": "large", "spots": {"0,0,1512,982": {"x": 300, "y": 400}, "0,0,1512,982|1512,-100,2560,1440": {"x": 2000, "y": 800}}}
        });
        let sent = sanitized(s);
        assert_eq!(sent.cat["desktop"]["on"], true);
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = load_from(&path);
        assert_eq!(back.cat, sent.cat, "what was saved is what loads");
        assert_eq!(back.cat["desktop"]["size"], "large");
        assert_eq!(back.cat["desktop"]["spots"]["0,0,1512,982"]["x"], 300);
        assert_eq!(back.cat["desktop"]["spots"]["0,0,1512,982|1512,-100,2560,1440"]["y"], 800);
        assert_eq!((&back.cat["character"], &back.cat["displayMode"]), (&serde_json::json!("momo"), &serde_json::json!("two")), "the other two parts are still there");
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).cat, back.cat, "a second round trip changes nothing");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A hand-edited file with a bad `desktop` is cleaned without failing the file or touching the rest of the block.
    #[test]
    fn bad_desktop_values_are_cleaned_and_never_fail_the_settings_file() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-desktop-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        for cat in [
            r#"{"character":"momo","desktop":7}"#,
            r#"{"character":"momo","desktop":null}"#,
            r#"{"character":"momo","desktop":{"on":"true","size":["small"],"spots":"{not json"}}"#,
            r#"{"character":"momo","desktop":{"on":1,"size":"HUGE","spots":{"__proto__":{"x":1,"y":1},"0,0,1,1":{"x":"a","y":1}}}}"#,
        ] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"cat":{cat}}}"#)).unwrap();
            let s = load_from(&path);
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {cat}");
            assert_eq!(s.cat["character"], "momo", "the Cat settings next to it are kept: {cat}");
            assert_eq!(s.cat["desktop"], serde_json::json!({"on": false, "size": "medium", "spots": {}}), "{cat}");
            assert!(path.exists(), "the file is not moved aside: {cat}");
        }
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The webview is not trusted, and a hand-edited file is not either: bad display keys are cleaned without failing the file or touching the rest of the block.'''),
('''    /// The Cat section of Settings (spec §4) and its Display settings (sub-project B): `{character, motionStyle, collar, furLines, cats, displayMode, pair,''', '''    /// The Cat section of Settings (spec §4), its Display settings (sub-project B) and the desktop cat's (sub-project H, `desktop: {on, size, spots}`): `{character, motionStyle, collar, furLines, cats, displayMode, pair,'''),
])
print("applied")
PYEOF
```

Run (needs the image; otherwise this step and Step 8 are owed):

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/h-tauri -- cat_settings:: settings:: 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok.` with no `error` and no `warning` (the counts: `cat_settings::` and `settings::` together pass the earlier plans' tests plus these five: `the_desktop_clean_up_replays_the_fixture`, `the_desktop_spots_keep_the_first_32_in_code_point_order_and_hostile_input_never_panics`, `the_whole_block_holds_the_desktop_settings_and_cleaning_it_twice_changes_nothing`, `the_desktop_settings_survive_a_save_a_load_and_a_round_trip`, `bad_desktop_values_are_cleaned_and_never_fail_the_settings_file`, and the changed block tests). If it does not compile and the cause is not obvious, hand the step to `nm-implementer-deep`.

- [ ] **Step 8: Run the whole Rust suite**

Run:

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/h-tauri 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok.` for the app's library and the relay, no `error`, no `warning`.

- [ ] **Step 9: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src/cat/display.ts windows/src/settings/cat.ts windows/scripts/cat-tests/display.test.mjs windows/scripts/cat-tests/desktop-settings.test.mjs windows/src-tauri/src/cat_settings.rs windows/src-tauri/src/settings.rs
git commit -F - <<'MSG'
feat(desktop): the desktop settings in the cat block, TypeScript and Rust

The cat block holds the desktop cat's on, size and spots; every clean-up of the block cleans all three parts, so a save keeps them. The Settings -> Cat section has the Cat on the desktop switch.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model.

---

# Stage 2: the window and its click-through

### Task 3: The window and its click-through

**Agent:** `nm-implementer-deep` (Sonnet 5.5, high). **Trigger 1:** a Tauri window on Windows and Linux (layer-shell on the top layer, an input region), click-through decided from the cursor, a position in points across monitors with different scales. The pure part (the layout) is given with its test; the window itself is Rust that no test program can open, so it is given in full and checked by its unit tests, by source pins and, at the end, by the owner.

**Files:**
- Create: `windows/src/cat/desktopview.ts`, `windows/src/desktop/body.ts`, `windows/src/desktop/main.ts`, `windows/desktop.html`, `windows/src-tauri/src/desktop.rs`
- Modify: `windows/vite.config.ts`, `windows/src-tauri/capabilities/default.json`, `windows/src/core/bridge.ts`, `windows/src-tauri/src/lib.rs`, `windows/src-tauri/src/island.rs`, `windows/src-tauri/src/platform/windows.rs`, `windows/src-tauri/src/platform/linux.rs`
- Test: `windows/scripts/cat-tests/desktop-view.test.mjs`, `windows/scripts/cat-tests/desktop-window.test.mjs`

**Interfaces:**
- Consumes: Task 1's `DESKTOP_SIZES`, `desktopKittenSlots`, `desktopSizeOf`, `Rect`, `Screen`; `presets.ts`'s `catById`; `kittendraw.ts`'s `BADGE_RIGHT`; the island's window code (`island.rs`: `target_monitor`, `PollGate`'s pattern, `apply_geometry`'s GTK notes) and `lib.rs`'s `create_settings_window` (why a window is made before the island's).
- Produces: `desktopWindowLayout(size, coat, kittenCount, side)` (the window's px, where the head is, the hit circles), `hitsCat`, `kittenSide`, `DesktopWorld`, `defaultWorld`; the window `desktop` (hidden, transparent, borderless, always on top, no taskbar, no focus, no file drops); the commands `desktop_screens`, `desktop_layout`, `desktop_place`, `desktop_show`, `desktop_drag`, `desktop_native_drag`, `desktop_cursor`, `desktop_relay`; the Bridge's `desktop*` calls; `platform::{make_desktop_window, desktop_positioned, place_desktop, set_desktop_input, fullscreen_app_covers}`; a page shell that draws one frame of the cat when it is told to show it (Task 5 replaces it).

**How the window works (read this before the code).** `create_window` makes the window at launch, hidden, with the island's `additionalBrowserArgs`; `desktop_show(true)` shows it and wakes a poll thread that is parked on a condvar the rest of the time. The page sends its size and its hit circles (`desktop_layout`); Rust resizes the window (physical size = logical size times the scale factor of the screen the window is on) and, on Linux, sets the input region to the circles' squares. `desktop_place(x, y)` puts the window so that the head's centre is at the spot, in points: physical position = spot times the primary screen's scale factor, minus the head's offset times the window's own scale (`window_origin`, tested); on a layer surface the position is the margins on the output that holds the spot. **On Windows** the poll flips `WS_EX_TRANSPARENT` from the cursor (16 ms near the cat, 100 ms far from it): the window takes the mouse only on the cat's circles and, while it is carried, everywhere. **On Linux** nothing polls the cursor; the input region is the click-through. The poll also looks at the screens twice a second and tells the island's page when they change (`{k: "screens"}`), and on Windows hides the window under a fullscreen app.

- [ ] **Step 1: Write the tests**

The layout's tests (what is inside the window, the mirror, the sizes, hostile input, what takes the mouse), and the pins of the Rust and of the files that make the page.

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-view.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { DESKTOP_SIZES, desktopKittenSlots } from "../../src/cat/desktop.ts";
import { HEAD_HIT_K, desktopWindowLayout, hitsCat, kittenSide } from "../../src/cat/desktopview.ts";
import { BADGE_RIGHT } from "../../src/cat/kittendraw.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import { finite, near } from "./util.mjs";

// Where the desktop cat's window is and what in it takes the mouse (sub-project H).

test("the window is sized for the cat, its badge and its kittens, and no larger: every shape and the canvas are inside it, at every size, coat, count and side", () => {
  for (const size of Object.keys(DESKTOP_SIZES)) for (const coat of CAT_IDS) for (const n of [0, 1, 3, 4, 8]) for (const side of [1, -1]) {
    const L = desktopWindowLayout(size, coat, n, side), tag = `${size} ${coat} ${n} ${side}`;
    finite(L);
    for (const q of desktopKittenSlots(Array.from({ length: n }, (_, i) => ({ id: `k${i}` })), side).shown) {
      const edge = L.headX + side * (Math.abs(q.x) + q.d * BADGE_RIGHT) * L.D;
      assert.ok(edge >= -1e-9 && edge <= L.w + 1e-9, `${tag}: a kitten's state badge sticks out beside its head and is inside the window`);
    }
    assert.equal(L.D, DESKTOP_SIZES[size], tag);
    near(L.canvasW * 0.6, L.D);
    assert.ok(L.canvasX >= -1e-9 && L.canvasX + L.canvasW <= L.w + 1e-9, `${tag}: the canvas is inside`);
    assert.equal(L.canvasH, L.h, tag);
    near(L.headY, L.canvasW / 2 + L.overhang, 1);
    for (const c of L.shapes) assert.ok(c.x - c.r >= -1e-9 && c.x + c.r <= L.w + 1e-9 && c.y - c.r >= -1e-9 && c.y + c.r <= L.h + 1e-9, `${tag}: a hit circle ${JSON.stringify(c)} is inside the ${L.w}x${L.h} window`);
    assert.equal(L.shapes.length, 2 + Math.min(n, 3) + (n > 3 ? 1 : 0), tag);
    // No larger than needed: with no kittens the window is the canvas; with kittens it grows on their side only.
    if (n === 0) assert.ok(L.w >= Math.ceil(L.canvasW) && L.w <= Math.ceil(L.canvasW) + 3, `${tag}: the canvas, and at most a few px more for a wide badge`);
    else assert.ok(side === 1 ? L.headX <= Math.ceil(L.canvasW / 2) : L.w - L.headX <= Math.ceil(L.canvasW / 2) + 3, `${tag}: grows on the kittens' side only`);
  }
});

test("the layout is a mirror: a left side puts the kittens at the left and the window grows to the left", () => {
  const a = desktopWindowLayout("medium", "momo", 4, 1), b = desktopWindowLayout("medium", "momo", 4, -1);
  assert.equal(a.w, b.w);
  near(a.headX + b.headX, a.w, 1);
  const kitten = (L, i) => L.shapes[2 + i];
  near(kitten(a, 0).x - a.headX, -(kitten(b, 0).x - b.headX));
  assert.ok(kitten(a, 0).x > a.headX && kitten(b, 0).x < b.headX);
});

test("the three sizes scale: the same cat and kittens, Small 48, Medium 64, Large 96", () => {
  const [s, m, l] = ["small", "medium", "large"].map((z) => desktopWindowLayout(z, "shrimpy", 3, 1));
  near(m.w / s.w, 64 / 48, 0.05);
  near(l.w / m.w, 96 / 64, 0.05);
  assert.ok(s.w < m.w && m.w < l.w && s.h < m.h && m.h < l.h);
});

test("an unknown size, coat, count or side is Medium, Shrimpy, none and the right", () => {
  const base = desktopWindowLayout("medium", "shrimpy", 0, 1);
  for (const size of [undefined, null, "Large", 96, {}, "constructor"]) assert.deepEqual(desktopWindowLayout(size, "shrimpy", 0, 1), base, String(size));
  assert.deepEqual(desktopWindowLayout("medium", "nope", 0, 1), base, "an unknown coat is Shrimpy");
  assert.deepEqual(desktopWindowLayout("medium", 7, 0, 1), base);
  for (const n of [NaN, Infinity, -3, "4", null, undefined, {}]) assert.deepEqual(desktopWindowLayout("medium", "shrimpy", n, 1), base, `count ${String(n)}`);
  assert.equal(desktopWindowLayout("medium", "shrimpy", 99, 1).shapes.length, 6, "held to eight kittens: the head, the badge, three kittens and the +N");
  for (const side of [0, 2, "-1", null, NaN]) assert.deepEqual(desktopWindowLayout("medium", "shrimpy", 3, side), desktopWindowLayout("medium", "shrimpy", 3, 1), String(side));
});

test("only the cat takes the mouse: the head with its ears, the badge, the kittens; the corners of the window pass through", () => {
  const L = desktopWindowLayout("medium", "shrimpy", 3, 1);
  assert.ok(hitsCat(L.shapes, L.headX, L.headY));
  assert.ok(hitsCat(L.shapes, L.headX, L.headY - L.D * HEAD_HIT_K + 1), "the top of the head");
  assert.ok(hitsCat(L.shapes, L.shapes[1].x, L.shapes[1].y), "the badge");
  assert.ok(hitsCat(L.shapes, L.shapes[2].x, L.shapes[2].y), "a kitten");
  assert.equal(hitsCat(L.shapes, 0, 0), false, "the top-left corner");
  assert.equal(hitsCat(L.shapes, L.w - 1, 0), false, "the top-right corner");
  assert.equal(hitsCat(L.shapes, L.headX, L.h + 50), false, "outside the window");
  assert.equal(hitsCat(L.shapes, L.headX + L.D * HEAD_HIT_K + 3, L.headY, 0), false);
  assert.equal(hitsCat(L.shapes, L.headX + L.D * HEAD_HIT_K + 3, L.headY, 4), true, "slack widens it");
  assert.equal(hitsCat([], 1, 1), false);
});

test("the kittens are on the right in the left half of the screen and on the left in the right half", () => {
  assert.equal(kittenSide(100, 0, 1000), 1);
  assert.equal(kittenSide(499.9, 0, 1000), 1);
  assert.equal(kittenSide(500, 0, 1000), -1);
  assert.equal(kittenSide(2100, 1000, 2000), -1);
  assert.equal(kittenSide(1100, 1000, 2000), 1);
});
EOF
```

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-window.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The desktop cat's window (sub-project H): the Rust side and the files that make the page, pinned by source (no test program can open a window).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");
const root = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("Rust: the window is made hidden at launch before the island's, takes no files and no focus, and its poll thread sleeps until the cat is out", () => {
  const d = rust("src/desktop.rs"), l = rust("src/lib.rs");
  assert.match(d, /\.visible\(false\)/);
  assert.match(d, /\.drag_and_drop\(false\)/);
  assert.match(d, /\.focused\(false\)/);
  assert.match(d, /gate\.wait_until_active\(\);/);
  assert.match(d, /while gate\.is_active\(\) \{\s*std::thread::sleep/);
  assert.match(l, /create_settings_window\(&handle\);\s*desktop::create_window\(&handle\);\s*desktop::spawn_poll\(handle\.clone\(\)/);
  assert.ok(l.indexOf("desktop::create_window(&handle);") < l.indexOf("if let Some(win) = island::window(&handle)"), "before the island's webview, which WebView2 needs");
  for (const c of ["desktop_screens", "desktop_layout", "desktop_place", "desktop_show", "desktop_drag", "desktop_native_drag", "desktop_cursor", "desktop_relay"]) assert.ok(l.includes(`desktop::${c},`), c);
  assert.match(l, /pub\(crate\) const BROWSER_ARGS/);
  assert.match(JSON.parse(root("src-tauri/capabilities/default.json").replace(/\/\/.*$/gm, "")).windows.join(), /desktop/);
  assert.match(root("vite.config.ts"), /desktop: resolve\(__dirname, "desktop\.html"\)/);
  assert.match(root("desktop.html"), /src="\/src\/desktop\/main\.ts"/);
});

test("Rust: the relay forwards only to the two windows, the top layer steps aside for fullscreen, and nothing in the window code reads a file or opens a network connection", () => {
  const d = rust("src/desktop.rs"), lin = rust("src/platform/linux.rs");
  assert.match(d, /"island" => crate::island::WINDOW_LABEL,\s*"desktop" => WINDOW_LABEL,\s*_ => return,/);
  assert.match(lin, /gtk_layer_set_layer\(ptr, layer::LAYER_TOP\);/);
  assert.doesNotMatch(d, /std::fs|reqwest|TcpStream|Command::new/);
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-view.test.mjs scripts/cat-tests/desktop-window.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|ENOENT|^# (tests|pass|fail)" | cut -c1-100 | sort -u; cd ..
```

Expected: a line with `ERR_MODULE_NOT_FOUND` (no `desktopview.ts` yet), a line with `ENOENT` (no `desktop.rs` yet), and `# fail 3` (the layout file fails to load, and both pins fail).

- [ ] **Step 3: Write the layout**

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/desktopview.ts <<'EOF'
// Where the desktop cat's window is and what in it takes the mouse (sub-project H, spec §2): the window is sized for the cat, its badge and its kittens, and no larger,
// and only the head, the badge and the kitten slots take the mouse; everything else passes through. Pure: sizes in px (CSS), no DOM, so the plain-Node checks (npm run check:cat) can
// load it. `DesktopWorld` is what Rust knows about the screens (src-tauri/src/desktop.rs `desktop_screens`), in the points the contract's rules use. The cat is drawn by `BotEngine.draw(ctx, W, H)` into a canvas W wide (the head is 0.6 W across) and `overhang` taller than wide, with the head's centre at
// (W/2, W/2 + overhang): the layout puts that canvas in the window so the head's centre is at (headX, headY).

import { DESKTOP_SIZES, desktopKittenSlots, desktopSizeOf } from "./desktop.ts";
import type { Rect, Screen } from "./desktop.ts";
import { BADGE_RIGHT } from "./kittendraw.ts";
import { catById } from "./presets.ts";

/** What Rust knows about the screens (src-tauri/src/desktop.rs `desktop_screens`), in points: the connected screens, the one the island is on, and the scales. */
export interface DesktopWorld {
  screens: Screen[];
  /** The frame of the screen the island lives on. */
  island: Rect;
  /** The island's screen scale divided by the primary screen's: one CSS px of the island is this many points. */
  islandK: number;
  /** The primary screen's scale factor, the one unit of the points: a CSS px of a window whose page has `devicePixelRatio` is `devicePixelRatio / scale` points. */
  scale: number;
  /** Whether the app can put the desktop window where it wants (false on GNOME, a Wayland session without layer-shell). */
  positioned: boolean;
}

/** An empty world: one 1920 x 1080 screen, for a page that runs outside Tauri (the dev server). */
export const defaultWorld = (): DesktopWorld => {
  const f = { x: 0, y: 0, w: 1920, h: 1080 };
  return { screens: [{ frame: f, visible: { x: 0, y: 0, w: 1920, h: 1040 }, main: true }], island: f, islandK: 1, scale: 1, positioned: true };
};

/** A circle that takes the mouse, in window px. */
export interface HitCircle { x: number; y: number; r: number }

export interface DesktopWindowLayout {
  /** The window, in px. */
  w: number; h: number;
  /** The head's centre in the window. */
  headX: number; headY: number;
  /** The head width D, and the canvas the engine draws into: W = D / 0.6 wide, W + overhang tall, with its top-left at (canvasX, 0). */
  D: number; canvasW: number; canvasH: number; canvasX: number; overhang: number;
  /** Which side the kittens are on: 1 right, -1 left. */
  side: 1 | -1;
  /** What takes the mouse: the head (with the ears), the badge, and one circle per kitten and for the "+N". */
  shapes: HitCircle[];
}

/** Room above the head for ears and the particles that fly out (hearts, z's), as a fraction of D: 40/58, the Mac's number (44 px at Medium). */
export const OVERHANG_K = 40 / 58;
/** The head's hit circle is this fraction of D across the radius, so the ears count as the cat. */
export const HEAD_HIT_K = 0.55;

/** The window for a cat of this size and coat with `kittenCount` kittens on `side`. A size ID that is unknown is Medium, a coat that is unknown is Shrimpy, a count is held to 0..8. */
export function desktopWindowLayout(size: unknown, coat: unknown, kittenCount: unknown, side: unknown): DesktopWindowLayout {
  const D = DESKTOP_SIZES[desktopSizeOf(size)], W = D / 0.6, overhang = Math.round(D * OVERHANG_K), s: 1 | -1 = side === -1 ? -1 : 1;
  const n = typeof kittenCount === "number" && Number.isFinite(kittenCount) ? Math.max(0, Math.min(8, Math.floor(kittenCount))) : 0;
  const slots = desktopKittenSlots(Array.from({ length: n }, (_, i) => ({ id: `k${i}` })), s);
  const half = W / 2;
  // How far the kittens reach on their side, in D from the head's centre: the last kitten's state badge (it sticks out beside its head), or the end of the "+N" label (about 2.2 label heights wide).
  let reach = 0;
  for (const q of slots.shown) reach = Math.max(reach, Math.abs(q.x) + q.d * BADGE_RIGHT);
  if (slots.moreAt) reach = Math.max(reach, Math.abs(slots.moreAt.x) + slots.moreAt.size * 2.2);
  const rx = catById(typeof coat === "string" ? coat : "shrimpy").rx, R = D / (2 * rx);
  // The badge is at the upper right of the head, 1.4 R across and about 0.36 R wide: the window holds it on that side whatever the coat's head shape.
  const kit = Math.ceil(reach * D), badge = Math.ceil(1.4 * R + 0.36 * R);
  const left = Math.max(half, s === -1 ? kit : 0), right = Math.max(half, badge, s === 1 ? kit : 0);
  const headX = Math.ceil(left), w = headX + Math.ceil(right), headY = Math.round(half + overhang), canvasH = Math.round(W) + overhang;
  const shapes: HitCircle[] = [
    { x: headX, y: headY, r: D * HEAD_HIT_K },
    { x: headX + 1.4 * R, y: headY - 0.92 * R, r: 0.36 * R },
    ...slots.shown.map((q) => ({ x: headX + q.x * D, y: headY + q.y * D, r: (q.d * D) / 2 })),
    ...(slots.moreAt ? [{ x: headX + slots.moreAt.x * D + s * slots.moreAt.size * D * 1.1, y: headY + slots.moreAt.y * D, r: slots.moreAt.size * D * 1.1 }] : []),
  ];
  return { w, h: canvasH, headX, headY, D, canvasW: W, canvasH, canvasX: headX - half, overhang, side: s, shapes };
}

/** True when (x, y), in window px, is on the cat: inside any shape, `slack` px wider. */
export const hitsCat = (shapes: readonly HitCircle[], x: number, y: number, slack = 0): boolean =>
  shapes.some((c) => Math.hypot(x - c.x, y - c.y) <= c.r + slack);

/** The side the kittens are on for a cat at `x` on a screen whose visible frame is `[left, left + width)`: the left half keeps them on the right, the right half on the left. */
export const kittenSide = (x: number, left: number, width: number): 1 | -1 => (x >= left + width / 2 ? -1 : 1);
EOF
```

- [ ] **Step 4: Run the layout's tests**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-view.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..
```

Expected: `# tests 6`, `# pass 6`, `# fail 0`.

- [ ] **Step 5: Prove the layout's tests can bite**

Run:

```bash
cd windows
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktopview.ts 'Math.abs(q.x) + q.d * BADGE_RIGHT' 'Math.abs(q.x) + q.d / 2' scripts/cat-tests/desktop-view.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktopview.ts 'r: 0.36 * R },' 'r: 0.9 * R },' scripts/cat-tests/desktop-view.test.mjs
cd ..
```

Expected: `# fail 1` for each (a kitten's state badge outside the window; a badge circle that pokes out of it).

- [ ] **Step 6: The page's shell, the build and the permissions, the Bridge**

The shell draws one frame when it is told to show the cat, so the window and its click-through can be tried before there is a trip; Task 5 replaces `body.ts` with the whole body.

```bash
mkdir -p windows
cat > windows/desktop.html <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>NotchMeow cat</title>
    <style>
      html, body { margin: 0; background: transparent; overflow: hidden; user-select: none; -webkit-user-select: none; }
      canvas { display: block; }
    </style>
  </head>
  <body>
    <div id="desktop-root"></div>
    <script type="module" src="/src/desktop/main.ts"></script>
  </body>
</html>
EOF
```

```bash
mkdir -p windows/src/desktop
cat > windows/src/desktop/main.ts <<'EOF'
// Entry point of the desktop cat's window (sub-project H): a transparent page that draws the big cat when the island's page says so. The page is created hidden at launch
// (src-tauri/src/desktop.rs) and costs nothing while the cat is at home: no timer and no frame callback run until it is shown (cat/desktopgov.ts).

import { DesktopBody } from "./body";

const root = document.getElementById("desktop-root");
if (root) {
  const body = new DesktopBody(root);
  // Dev server only: `window.__body.handle({...})` feeds the page the same messages the island's page sends, so it can be looked at without the Tauri app.
  if (import.meta.env.DEV) (window as unknown as { __body: DesktopBody }).__body = body;
  void body.start();
}
EOF
```

```bash
mkdir -p windows/src/desktop
cat > windows/src/desktop/body.ts <<'EOF'
// The desktop cat's window, the body (sub-project H), first stage: it draws one frame of the cat when it is told to show it, so the window, its size, where it is put and what takes the mouse
// can be tried before the trip, the flight and the clicks exist (the next tasks replace this file with the whole body). It runs no timer and no frame callback: a window that is shown draws
// once, and a window that is hidden does nothing.

import { Bridge, onEvent } from "../core/bridge";
import type { Settings } from "../core/state";
import { cleanCatBlock } from "../cat/display";
import type { Spot } from "../cat/desktop";
import { desktopWindowLayout } from "../cat/desktopview";
import { BotEngine, catCfg } from "../cat/engine";
import { applyCatSettings } from "../cat/settings";

/** What this stage understands: show the cat's head at a spot, or hide the window. */
type Msg = { k: "show"; spot: Spot; coat: string; size: string; kittens?: number } | { k: "hide" };

export class DesktopBody {
  private readonly root: HTMLElement;
  private readonly cv = document.createElement("canvas");
  private readonly engine = new BotEngine();

  constructor(root: HTMLElement) {
    this.root = root;
  }

  async start(): Promise<void> {
    this.root.append(this.cv);
    const boot = await Bridge.boot();
    if (boot) applyCatSettings(catCfg, cleanCatBlock(boot.settings.cat));
    await onEvent<Msg>("desktop-msg", (m) => this.handle(m));
    await onEvent<Settings>("settings-changed", (s) => applyCatSettings(catCfg, cleanCatBlock(s.cat)));
  }

  /** A message (public so the dev server can feed one by hand). */
  handle(m: Msg): void {
    if (!m || typeof m !== "object") return;
    if (m.k === "hide") {
      void Bridge.desktopShow(false);
      return;
    }
    const lay = desktopWindowLayout(m.size, m.coat, m.kittens ?? 0, 1);
    const dpr = Math.min(2, window.devicePixelRatio || 1), ctx = this.cv.getContext("2d");
    this.cv.width = Math.round(lay.w * dpr); this.cv.height = Math.round(lay.h * dpr);
    this.cv.style.width = `${lay.w}px`; this.cv.style.height = `${lay.h}px`;
    void Bridge.desktopLayout(lay.w, lay.h, lay.headX, lay.headY, lay.shapes.map((c) => ({ x: c.x, y: c.y, r: c.r })));
    void Bridge.desktopPlace(m.spot.x, m.spot.y);
    void Bridge.desktopShow(true);
    if (!ctx) return;
    this.engine.setCoat(m.coat);
    this.engine.particleOverhang = lay.overhang;
    this.engine.update(1 / 60);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, lay.w, lay.h);
    ctx.save();
    ctx.translate(lay.canvasX, 0);
    this.engine.draw(ctx, lay.canvasW, lay.canvasH);
    ctx.restore();
  }
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

edit("windows/vite.config.ts", [
('''        settings: resolve(__dirname, "settings.html"),
''', '''        settings: resolve(__dirname, "settings.html"),
        desktop: resolve(__dirname, "desktop.html"),
'''),
])
edit("windows/src-tauri/capabilities/default.json", [
('"windows": ["island", "settings"],', '"windows": ["island", "settings", "desktop"],'),
])
edit("windows/src/core/bridge.ts", [
('''import type { AiAction, Settings } from "./state";
''', '''import type { AiAction, Settings } from "./state";
import type { DesktopWorld } from "../cat/desktopview";
'''),
('''  /** Tray → Pause. Stops the integration pollers, not just the island. */
  setPaused: (paused: boolean) => call<void>("set_paused", { paused }),
};''', '''  /** Tray → Pause. Stops the integration pollers, not just the island. */
  setPaused: (paused: boolean) => call<void>("set_paused", { paused }),

  // ── The desktop cat (sub-project H): its own window, which the island's page runs and the desktop page draws ──
  /** The connected screens, the island's screen and whether the window can be put where we want it, in the points the contract's rules use. */
  desktopScreens: () => call<DesktopWorld>("desktop_screens"),
  /** The window is `w` x `h` CSS px with the head's centre at (headX, headY); `shapes` are the circles that take the mouse, in window px. */
  desktopLayout: (w: number, h: number, headX: number, headY: number, shapes: { x: number; y: number; r: number }[]) => call<void>("desktop_layout", { w, h, headX, headY, shapes }),
  /** Puts the window where the head's centre is at this spot (points). */
  desktopPlace: (x: number, y: number) => call<void>("desktop_place", { x, y }),
  desktopShow: (visible: boolean) => call<void>("desktop_show", { visible }),
  /** While the desktop cat is carried by the pointer the whole window takes the mouse. */
  desktopDrag: (on: boolean) => call<void>("desktop_drag", { on }),
  /** Where the system moves windows by itself (GNOME): the system drags the window. */
  desktopNativeDrag: () => call<void>("desktop_native_drag"),
  /** The cursor in points, or null where the system gives an app none (Wayland). */
  desktopCursor: () => call<{ x: number; y: number } | null>("desktop_cursor"),
  /** A message between the island's page (the brain) and the desktop page (the body): `to` is the window's label. */
  desktopRelay: (to: "island" | "desktop", msg: unknown) => call<void>("desktop_relay", { to, msg }),
};'''),
('''export type BridgeEvent =
  | { name: "cursor"; payload: { x: number; y: number } }
  | { name: "tray"; payload: string }''', '''export type BridgeEvent =
  | { name: "cursor"; payload: { x: number; y: number } }
  | { name: "tray"; payload: string }
  | { name: "desktop-msg"; payload: unknown }'''),
])
print("applied")
PYEOF
```

- [ ] **Step 7: The window, in Rust**

`desktop.rs` (given in full: the window, the gate, the screens, the placement, the commands, the poll and three unit tests), then the registration and the platform parts. **Read what you paste**: the Linux parts call the gtk-layer-shell C library the way `make_non_activating` does (the top layer, anchored top and left, placed with margins; the island uses the overlay layer), and the Windows part finds a fullscreen foreground window with the Win32 calls already enabled in `Cargo.toml` (no new crate or feature).

```bash
mkdir -p windows/src-tauri/src
cat > windows/src-tauri/src/desktop.rs <<'EOF'
// The desktop cat's window (sub-project H, spec §3): a second transparent, borderless, always-on-top window that holds the big cat while it lives on the desktop. The page in it
// (src/desktop/body.ts) draws the cat; the island's page (src/island/desktop.ts) runs the trip. This file only moves the window and decides what takes the mouse:
//   * the window is created hidden at launch, before the island's webview (a WebView2 window created later comes up blank, see lib.rs), and shown only while the cat is on the
//     desktop or in the air;
//   * click-through is the body's shape: on Windows a poll flips WS_EX_TRANSPARENT from the cursor, slowly while the cursor is far from the cat and at 60 Hz when it is near, and
//     only while the cat is out; on Linux the window's input region is the shape, and nothing polls the cursor (Wayland gives an app none);
//   * positions are in points, the contract's unit (cat/desktop.ts): physical pixels divided by the primary screen's scale factor, the origin at the top left of the main screen.
//     A window on a screen with another scale factor keeps the cat the size that screen gives it;
//   * a fullscreen app covering the cat's screen hides the window (Windows; on Linux the layer is below fullscreen windows by itself).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, Monitor, PhysicalSize, State, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

use crate::platform;

pub const WINDOW_LABEL: &str = "desktop";

/// The mouse is let in this many logical px outside the body's circles, so a click is never swallowed at the edge.
const HIT_SLACK: f64 = 4.0;
/// The cursor poll runs at 60 Hz within this many logical px of the window, and at 10 Hz farther away.
const NEAR_PX: f64 = 90.0;
const NEAR_MS: u64 = 16;
const FAR_MS: u64 = 100;
/// The screens and a fullscreen app are looked at this often (ms) while the cat is out.
const CHECK_MS: u128 = 500;

#[derive(Serialize, Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

#[derive(Serialize)]
pub struct ScreenOut {
    pub frame: Rect,
    pub visible: Rect,
    pub main: bool,
}

/// What the page needs to know about the screens, in points (see the top of this file).
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct World {
    pub screens: Vec<ScreenOut>,
    /// The frame of the screen the island is on.
    pub island: Rect,
    /// The island screen's scale factor over the primary screen's.
    pub island_k: f64,
    /// The primary screen's scale factor: the unit of a point.
    pub scale: f64,
    /// False where the system places windows itself (GNOME): the cat's position is then not ours to set or to remember.
    pub positioned: bool,
}

#[derive(Serialize)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

/// A circle that takes the mouse, in window logical px.
#[derive(Deserialize, Clone, Copy, Debug, Default)]
pub struct Circle {
    pub x: f64,
    pub y: f64,
    pub r: f64,
}

#[derive(Default)]
struct Placed {
    /// The window's logical size, and the head's centre in it.
    w: f64,
    h: f64,
    head_x: f64,
    head_y: f64,
    shapes: Vec<Circle>,
    /// Where the head's centre is, in points; None before the first placement.
    spot: Option<(f64, f64)>,
    /// The scale factor of the screen the window is on.
    scale: f64,
}

/// What the commands and the poll thread share about the desktop window.
pub struct Gate {
    active: Mutex<bool>,
    cv: Condvar,
    placed: Mutex<Placed>,
    /// The page wants the window shown, and a fullscreen app covers it: shown means both.
    wanted: AtomicBool,
    covered: AtomicBool,
    /// The cat is carried by the pointer: the whole window takes the mouse.
    dragging: AtomicBool,
    /// Mirrors the window flag so the OS is only called when it changes.
    ignoring: AtomicBool,
}

pub type DesktopGate = Arc<Gate>;

impl Gate {
    pub fn new() -> Self {
        Self {
            active: Mutex::new(false),
            cv: Condvar::new(),
            placed: Mutex::new(Placed { scale: 1.0, ..Default::default() }),
            wanted: AtomicBool::new(false),
            covered: AtomicBool::new(false),
            dragging: AtomicBool::new(false),
            ignoring: AtomicBool::new(true),
        }
    }

    fn set_active(&self, on: bool) {
        let mut g = self.active.lock().unwrap();
        *g = on;
        self.cv.notify_all();
    }

    fn wait_until_active(&self) {
        let mut g = self.active.lock().unwrap();
        while !*g {
            g = self.cv.wait(g).unwrap();
        }
    }

    fn is_active(&self) -> bool {
        *self.active.lock().unwrap()
    }
}

// ── Pure helpers (tested) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// True when (x, y), in window logical px, is on one of the circles, `slack` px wider.
pub fn hits(shapes: &[Circle], x: f64, y: f64, slack: f64) -> bool {
    shapes.iter().any(|c| (x - c.x).hypot(y - c.y) <= c.r + slack)
}

/// A physical rectangle as points: every number divided by the primary screen's scale factor.
pub fn rect_in_points(pos: (i32, i32), size: (u32, u32), unit: f64) -> Rect {
    let s = if unit > 0.0 { unit } else { 1.0 };
    Rect { x: pos.0 as f64 / s, y: pos.1 as f64 / s, w: size.0 as f64 / s, h: size.1 as f64 / s }
}

/// The window's top-left in physical px so that the head's centre (`head`, in the window's logical px) is at `spot` (points): the spot is physical / `unit`, the head is
/// logical * `scale`, the scale factor of the screen the window is on.
pub fn window_origin(spot: (f64, f64), head: (f64, f64), unit: f64, scale: f64) -> (i32, i32) {
    ((spot.0 * unit - head.0 * scale).round() as i32, (spot.1 * unit - head.1 * scale).round() as i32)
}

/// How long the cursor poll sleeps: 16 ms when the cursor is within 90 logical px of the window, else 100 ms.
pub fn poll_ms(lx: f64, ly: f64, w: f64, h: f64) -> u64 {
    if lx > -NEAR_PX && lx < w + NEAR_PX && ly > -NEAR_PX && ly < h + NEAR_PX { NEAR_MS } else { FAR_MS }
}

fn same_monitor(a: &Monitor, b: &Monitor) -> bool {
    a.position() == b.position() && a.size() == b.size()
}

// ── Screens ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// The primary screen's scale factor, the unit of a point.
fn unit(app: &AppHandle) -> f64 {
    app.primary_monitor().ok().flatten().map(|m| m.scale_factor()).filter(|s| *s > 0.0).unwrap_or(1.0)
}

fn frame_of(m: &Monitor, u: f64) -> Rect {
    rect_in_points((m.position().x, m.position().y), (m.size().width, m.size().height), u)
}

fn visible_of(m: &Monitor, u: f64) -> Rect {
    let a = m.work_area();
    rect_in_points((a.position.x, a.position.y), (a.size.width, a.size.height), u)
}

pub fn world(app: &AppHandle, pref: &str) -> World {
    let u = unit(app);
    let primary = app.primary_monitor().ok().flatten();
    let monitors = app.available_monitors().unwrap_or_default();
    let screens: Vec<ScreenOut> = monitors
        .iter()
        .map(|m| ScreenOut { frame: frame_of(m, u), visible: visible_of(m, u), main: primary.as_ref().is_some_and(|p| same_monitor(p, m)) })
        .collect();
    let island = crate::island::target_monitor(app, pref);
    let (island_rect, island_k) = match &island {
        Some(m) => (frame_of(m, u), m.scale_factor() / u),
        None => (Rect { x: 0.0, y: 0.0, w: 1920.0, h: 1080.0 }, 1.0),
    };
    World { screens, island: island_rect, island_k, scale: u, positioned: platform::desktop_positioned() }
}

/// The monitor that holds `spot` (points) and its index, else the primary one.
fn monitor_for(app: &AppHandle, spot: (f64, f64)) -> Option<(usize, Monitor)> {
    let u = unit(app);
    let list = app.available_monitors().ok()?;
    let held = |m: &Monitor| {
        let r = frame_of(m, u);
        spot.0 >= r.x && spot.0 < r.x + r.w && spot.1 >= r.y && spot.1 < r.y + r.h
    };
    let index = list.iter().position(held).or_else(|| {
        let p = app.primary_monitor().ok().flatten()?;
        list.iter().position(|m| same_monitor(&p, m))
    })?;
    Some((index, list[index].clone()))
}

/// The arrangement of screens, as a string: a change means the spot has to be found again.
fn screens_key(app: &AppHandle) -> String {
    let mut parts: Vec<String> = app
        .available_monitors()
        .unwrap_or_default()
        .iter()
        .map(|m| format!("{},{},{},{},{}", m.position().x, m.position().y, m.size().width, m.size().height, m.scale_factor().to_bits()))
        .collect();
    parts.sort();
    parts.join("|")
}

// ── The window ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

pub fn window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window(WINDOW_LABEL)
}

/// In a dev build the page is served by Vite, so the window needs the absolute dev URL; a bundled build resolves it inside the app bundle.
fn page_url(app: &AppHandle) -> WebviewUrl {
    #[cfg(dev)]
    if let Some(mut base) = app.config().build.dev_url.clone() {
        base.set_path("/desktop.html");
        return WebviewUrl::External(base);
    }
    let _ = app;
    WebviewUrl::App("desktop.html".into())
}

/// Creates the desktop cat's window, hidden. It exists from launch on, so a cat that is out never has to wait for a webview to start (and a WebView2 window created later comes up
/// blank in this app, see lib.rs). Its page runs nothing while the window is hidden.
pub fn create_window(app: &AppHandle) {
    let builder = WebviewWindowBuilder::new(app, WINDOW_LABEL, page_url(app))
        .additional_browser_args(crate::BROWSER_ARGS)
        .title("NotchMeow cat")
        .inner_size(120.0, 160.0)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .resizable(false)
        .focused(false)
        .visible(false)
        .maximizable(false)
        .minimizable(false)
        .closable(false)
        .drag_and_drop(false);
    #[cfg(target_os = "linux")]
    let builder = builder.focusable(false).visible_on_all_workspaces(true);
    match builder.build() {
        Ok(win) => platform::make_desktop_window(&win),
        Err(err) => crate::log::line(format!("desktop window failed: {err}")),
    }
}

/// Shown while the page wants it and nothing covers it.
fn apply_visibility(app: &AppHandle, gate: &Gate) {
    let Some(win) = window(app) else { return };
    let show = gate.wanted.load(Ordering::Relaxed) && !gate.covered.load(Ordering::Relaxed);
    if show {
        // Until the poll sees the cursor on the cat, nothing takes the mouse. (On Linux the input region is the shape and the flag stays off.)
        if platform::CURSOR_POLL {
            gate.ignoring.store(true, Ordering::Relaxed);
            let _ = win.set_ignore_cursor_events(true);
        }
        let _ = win.show();
        let _ = win.set_always_on_top(true);
    } else {
        let _ = win.hide();
    }
}

/// Puts the window where the head's centre is at `spot` (points), on the screen that holds it.
fn place(app: &AppHandle, gate: &Gate, x: f64, y: f64) {
    let Some(win) = window(app) else { return };
    let Some((index, m)) = monitor_for(app, (x, y)) else { return };
    let (u, s2) = (unit(app), m.scale_factor());
    let (head, size, rescale) = {
        let mut p = gate.placed.lock().unwrap();
        let rescale = (p.scale - s2).abs() > 1e-9;
        p.scale = s2;
        p.spot = Some((x, y));
        ((p.head_x, p.head_y), (p.w, p.h), rescale)
    };
    if rescale && size.0 > 0.0 {
        let _ = win.set_size(PhysicalSize::new((size.0 * s2).round().max(1.0) as u32, (size.1 * s2).round().max(1.0) as u32));
    }
    let (px, py) = window_origin((x, y), head, u, s2);
    platform::place_desktop(&win, px, py, index, (m.position().x, m.position().y), s2);
}

// ── Commands ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

#[tauri::command]
pub fn desktop_screens(app: AppHandle, shared: State<crate::Shared>) -> World {
    let pref = shared.settings.lock().unwrap().screen.clone();
    world(&app, &pref)
}

/// The page's size and what takes the mouse changed (a size picked, a kitten came): the window is resized, and put back so the head stays where it was.
#[tauri::command]
pub fn desktop_layout(app: AppHandle, gate: State<DesktopGate>, w: f64, h: f64, head_x: f64, head_y: f64, shapes: Vec<Circle>) {
    if !(w.is_finite() && h.is_finite() && head_x.is_finite() && head_y.is_finite()) || w < 1.0 || h < 1.0 || w > 4000.0 || h > 4000.0 {
        return;
    }
    let shapes: Vec<Circle> = shapes.into_iter().filter(|c| c.x.is_finite() && c.y.is_finite() && c.r.is_finite() && c.r >= 0.0).take(32).collect();
    let (s2, spot) = {
        let mut p = gate.placed.lock().unwrap();
        p.w = w;
        p.h = h;
        p.head_x = head_x;
        p.head_y = head_y;
        p.shapes = shapes.clone();
        (p.scale, p.spot)
    };
    let Some(win) = window(&app) else { return };
    // GTK never sizes a non-resizable window below its natural size: ask for resizable just before the resize (as island.rs does).
    #[cfg(target_os = "linux")]
    let _ = win.set_resizable(true);
    let _ = win.set_size(PhysicalSize::new((w * s2).round().max(1.0) as u32, (h * s2).round().max(1.0) as u32));
    let rects: Vec<(f64, f64, f64, f64)> = shapes.iter().map(|c| (c.x - c.r - HIT_SLACK, c.y - c.r - HIT_SLACK, 2.0 * (c.r + HIT_SLACK), 2.0 * (c.r + HIT_SLACK))).collect();
    platform::set_desktop_input(&win, &rects);
    if let Some((x, y)) = spot {
        place(&app, &gate, x, y);
    }
}

#[tauri::command]
pub fn desktop_place(app: AppHandle, gate: State<DesktopGate>, x: f64, y: f64) {
    if x.is_finite() && y.is_finite() && x.abs() < 1e6 && y.abs() < 1e6 {
        place(&app, &gate, x, y);
    }
}

#[tauri::command]
pub fn desktop_show(app: AppHandle, gate: State<DesktopGate>, visible: bool) {
    gate.wanted.store(visible, Ordering::Relaxed);
    apply_visibility(&app, &gate);
    gate.set_active(visible);
}

#[tauri::command]
pub fn desktop_drag(app: AppHandle, gate: State<DesktopGate>, on: bool) {
    gate.dragging.store(on, Ordering::Relaxed);
    if on && platform::CURSOR_POLL {
        gate.ignoring.store(false, Ordering::Relaxed);
        if let Some(win) = window(&app) {
            let _ = win.set_ignore_cursor_events(false);
        }
    }
}

#[tauri::command]
pub fn desktop_native_drag(app: AppHandle) {
    if let Some(win) = window(&app) {
        let _ = win.start_dragging();
    }
}

#[tauri::command]
pub fn desktop_cursor(app: AppHandle) -> Option<Point> {
    let u = unit(&app);
    platform::cursor_physical().map(|(x, y)| Point { x: x / u, y: y / u })
}

/// A message between the island's page and the desktop page. Rust only forwards it, to the one window the label names.
#[tauri::command]
pub fn desktop_relay(app: AppHandle, to: String, msg: serde_json::Value) {
    let label = match to.as_str() {
        "island" => crate::island::WINDOW_LABEL,
        "desktop" => WINDOW_LABEL,
        _ => return,
    };
    let _ = app.emit_to(label, "desktop-msg", msg);
}

// ── The poll ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// Runs only while the cat is out: parked on a condvar the rest of the time, so a cat at home costs nothing. It flips click-through from the cursor (Windows), tells the island's page when
/// the screens changed, and hides the window under a fullscreen app.
pub fn spawn_poll(app: AppHandle, gate: DesktopGate) {
    std::thread::spawn(move || {
        let mut last_screens: Option<String> = None;
        let mut last_check = Instant::now();
        let mut covered = false;
        loop {
            gate.wait_until_active();
            last_screens = None;
            let mut period = if platform::CURSOR_POLL { FAR_MS } else { CHECK_MS as u64 };
            while gate.is_active() {
                std::thread::sleep(Duration::from_millis(period));
                if last_check.elapsed().as_millis() >= CHECK_MS {
                    last_check = Instant::now();
                    let key = screens_key(&app);
                    if last_screens.as_ref().is_some_and(|k| *k != key) {
                        let _ = app.emit_to(crate::island::WINDOW_LABEL, "desktop-msg", serde_json::json!({ "k": "screens" }));
                    }
                    last_screens = Some(key);
                    let rects: Vec<(i32, i32, u32, u32)> =
                        app.available_monitors().unwrap_or_default().iter().map(|m| (m.position().x, m.position().y, m.size().width, m.size().height)).collect();
                    let now = platform::fullscreen_app_covers(&rects);
                    if now != covered {
                        covered = now;
                        gate.covered.store(now, Ordering::Relaxed);
                        apply_visibility(&app, &gate);
                    }
                }
                if platform::CURSOR_POLL {
                    period = click_through(&app, &gate);
                }
            }
        }
    });
}

/// One look at the cursor: the window takes the mouse over the cat's shape (or while the cat is carried) and lets it through everywhere else. Returns how long to sleep.
fn click_through(app: &AppHandle, gate: &Gate) -> u64 {
    let Some(win) = window(app) else { return FAR_MS };
    let (Some((cx, cy)), Ok(origin)) = (platform::cursor_physical(), win.outer_position()) else { return FAR_MS };
    let (shapes, w, h, s2) = {
        let p = gate.placed.lock().unwrap();
        (p.shapes.clone(), p.w, p.h, if p.scale > 0.0 { p.scale } else { 1.0 })
    };
    let (lx, ly) = ((cx - origin.x as f64) / s2, (cy - origin.y as f64) / s2);
    let accept = gate.dragging.load(Ordering::Relaxed) || hits(&shapes, lx, ly, HIT_SLACK);
    if gate.ignoring.load(Ordering::Relaxed) == accept {
        gate.ignoring.store(!accept, Ordering::Relaxed);
        let _ = win.set_ignore_cursor_events(!accept);
    }
    poll_ms(lx, ly, w, h)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cat() -> Vec<Circle> {
        vec![Circle { x: 53.0, y: 90.0, r: 35.0 }, Circle { x: 90.0, y: 60.0, r: 8.0 }]
    }

    #[test]
    fn only_the_cat_takes_the_mouse() {
        let shapes = cat();
        assert!(hits(&shapes, 53.0, 90.0, 0.0), "the head");
        assert!(hits(&shapes, 90.0, 60.0, 0.0), "the badge");
        assert!(!hits(&shapes, 0.0, 0.0, 0.0), "a corner of the window passes through");
        assert!(!hits(&shapes, 53.0, 90.0 + 35.0 + 3.0, 0.0), "just outside the head");
        assert!(hits(&shapes, 53.0, 90.0 + 35.0 + 3.0, HIT_SLACK), "the slack lets the edge in");
        assert!(!hits(&[], 1.0, 1.0, HIT_SLACK), "no shapes, no mouse");
        assert!(!hits(&shapes, f64::NAN, 1.0, 0.0) && !hits(&shapes, 1.0, f64::INFINITY, 0.0), "a cursor that is not a number is on nothing");
    }

    #[test]
    fn a_physical_rectangle_is_in_points_and_the_window_goes_where_the_head_is() {
        assert_eq!(rect_in_points((1920, 0), (2560, 1440), 2.0), Rect { x: 960.0, y: 0.0, w: 1280.0, h: 720.0 });
        assert_eq!(rect_in_points((0, 0), (100, 100), 0.0), Rect { x: 0.0, y: 0.0, w: 100.0, h: 100.0 }, "a scale that is not positive is 1");
        // The head's centre (53, 90) in a window on a screen with scale 1.5, the unit 1.25: spot (400, 300) points is (500, 375) physical.
        assert_eq!(window_origin((400.0, 300.0), (53.0, 90.0), 1.25, 1.5), (421, 240));
        assert_eq!(window_origin((0.0, 0.0), (53.0, 90.0), 1.0, 1.0), (-53, -90), "the window may start off screen: the head is what is on it");
    }

    #[test]
    fn the_cursor_poll_is_fast_only_near_the_window() {
        assert_eq!(poll_ms(50.0, 80.0, 110.0, 160.0), NEAR_MS, "over the window");
        assert_eq!(poll_ms(-50.0, 80.0, 110.0, 160.0), NEAR_MS, "just outside it");
        assert_eq!(poll_ms(-100.0, 80.0, 110.0, 160.0), FAR_MS);
        assert_eq!(poll_ms(300.0, 80.0, 110.0, 160.0), FAR_MS);
        assert_eq!(poll_ms(50.0, 400.0, 110.0, 160.0), FAR_MS);
    }
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

edit("windows/src-tauri/src/island.rs", [
("fn target_monitor(app: &AppHandle, pref: &str) -> Option<Monitor> {", "pub fn target_monitor(app: &AppHandle, pref: &str) -> Option<Monitor> {"),
])

edit("windows/src-tauri/src/lib.rs", [
("mod cat_settings;\nmod files;", "mod cat_settings;\nmod desktop;\nmod files;"),
("const BROWSER_ARGS: &str =", "pub(crate) const BROWSER_ARGS: &str ="),
("""        .manage(Pending::default())
        .manage(ai::AiState::default())""", """        .manage(Pending::default())
        .manage(desktop::DesktopGate::new(desktop::Gate::new()))
        .manage(ai::AiState::default())"""),
("""            open_settings_window,
            set_paused,
        ])""", """            open_settings_window,
            set_paused,
            desktop::desktop_screens,
            desktop::desktop_layout,
            desktop::desktop_place,
            desktop::desktop_show,
            desktop::desktop_drag,
            desktop::desktop_native_drag,
            desktop::desktop_cursor,
            desktop::desktop_relay,
        ])"""),
("""            // Before the island: see create_settings_window.
            create_settings_window(&handle);
""", """            // Before the island: see create_settings_window. The desktop cat's window is made the same way, hidden, and its poll thread sleeps until the cat is out.
            create_settings_window(&handle);
            desktop::create_window(&handle);
            desktop::spawn_poll(handle.clone(), handle.state::<desktop::DesktopGate>().inner().clone());
"""),
])

edit("windows/src-tauri/src/platform/windows.rs", [
("use ::windows::Win32::Foundation::{CloseHandle, HANDLE, HLOCAL, HWND, LPARAM, LocalFree, POINT};", "use ::windows::Win32::Foundation::{CloseHandle, HANDLE, HLOCAL, HWND, LPARAM, LocalFree, POINT, RECT};"),
("""    EnumChildWindows, GetClassNameW, GetCursorPos, GetWindowLongPtrW, SetWindowLongPtrW,
    GWL_EXSTYLE, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,""", """    EnumChildWindows, GetClassNameW, GetCursorPos, GetForegroundWindow, GetWindowLongPtrW, GetWindowRect, GetWindowThreadProcessId, SetWindowLongPtrW,
    GWL_EXSTYLE, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,"""),
("""/// Click-through here is the poll's WS_EX_TRANSPARENT toggle, not a region.
pub fn set_input_region(_win: &WebviewWindow, _rect: Option<(f64, f64, f64, f64)>) {}""", """/// Click-through here is the poll's WS_EX_TRANSPARENT toggle, not a region.
pub fn set_input_region(_win: &WebviewWindow, _rect: Option<(f64, f64, f64, f64)>) {}

// ── Desktop cat window (sub-project H) ────────────────────────────────────────────────────────────────────────────────────────────────────

/// The desktop cat's window never takes focus and stays out of Alt-Tab, like the island's.
pub fn make_desktop_window(win: &WebviewWindow) {
    make_non_activating(win);
}

/// Windows lets an app put its windows where it wants.
pub fn desktop_positioned() -> bool {
    true
}

/// Puts the desktop window's top-left at (x, y) physical px.
pub fn place_desktop(win: &WebviewWindow, x: i32, y: i32, _monitor: usize, _monitor_origin: (i32, i32), _scale: f64) {
    let _ = win.set_position(tauri::PhysicalPosition::new(x, y));
}

/// Click-through is the poll's WS_EX_TRANSPARENT toggle (desktop.rs), not a region.
pub fn set_desktop_input(_win: &WebviewWindow, _rects: &[(f64, f64, f64, f64)]) {}

/// True when the foreground window belongs to another process and covers a whole monitor (a fullscreen game or video, F11 in a browser): the desktop cat steps aside. The desktop
/// itself and the taskbar are never "fullscreen". `monitors` are (x, y, width, height) in physical px.
pub fn fullscreen_app_covers(monitors: &[(i32, i32, u32, u32)]) -> bool {
    unsafe {
        let fg = GetForegroundWindow();
        if fg.0.is_null() {
            return false;
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(fg, Some(&mut pid as *mut u32));
        if pid == std::process::id() {
            return false;
        }
        let mut name = [0u16; 64];
        let len = GetClassNameW(fg, &mut name);
        if len > 0 {
            let class = String::from_utf16_lossy(&name[..len as usize]);
            if matches!(class.as_str(), "Progman" | "WorkerW" | "Shell_TrayWnd" | "Shell_SecondaryTrayWnd") {
                return false;
            }
        }
        let mut r = RECT::default();
        if GetWindowRect(fg, &mut r).is_err() {
            return false;
        }
        monitors.iter().any(|&(x, y, w, h)| r.left <= x && r.top <= y && r.right >= x + w as i32 && r.bottom >= y + h as i32)
    }
}"""),
])

edit("windows/src-tauri/src/platform/linux.rs", [
("use std::sync::atomic::{AtomicBool, Ordering};", "use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};"),
("""    pub const LAYER_OVERLAY: c_int = 3;
    pub const EDGE_TOP: c_int = 2;""", """    pub const LAYER_OVERLAY: c_int = 3;
    pub const LAYER_TOP: c_int = 2;
    pub const EDGE_LEFT: c_int = 0;
    pub const EDGE_TOP: c_int = 2;"""),
("""        pub fn gtk_layer_set_keyboard_mode(window: *mut GtkWindow, mode: c_int);
""", """        pub fn gtk_layer_set_keyboard_mode(window: *mut GtkWindow, mode: c_int);
        pub fn gtk_layer_set_margin(window: *mut GtkWindow, edge: c_int, margin_size: c_int);
        pub fn gtk_layer_set_monitor(window: *mut GtkWindow, monitor: *mut gtk::gdk::ffi::GdkMonitor);
"""),
("""#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_private_directory_of_ours_can_hold_the_relay_socket() {""", """// ── Desktop cat window (sub-project H) ────────────────────────────────────────────────────────────────────────────────────────────────────

/// True once the desktop cat's window is a layer-shell surface.
static DESKTOP_LAYER: AtomicBool = AtomicBool::new(false);
/// The monitor (its index) the layer surface was last put on, so it is only moved to another output when the cat changes screen.
static DESKTOP_MONITOR: AtomicUsize = AtomicUsize::new(usize::MAX);
/// The input region last asked for (the cat's shape), re-applied whenever the window is mapped: GTK resets it to the whole window on map. Empty until the page reports a layout,
/// so nothing takes the mouse.
static DESKTOP_REGION: Mutex<Vec<(f64, f64, f64, f64)>> = Mutex::new(Vec::new());

/// Makes the desktop cat's window a layer-shell surface on the TOP layer, anchored at the top left and placed with margins, that never takes the keyboard. The top layer (not the
/// overlay the island uses) is drawn below fullscreen windows, so the cat steps aside over a fullscreen app by itself. Must run before the window is first shown.
///
/// Without layer-shell (GNOME, X11, or NOTCHMEOW_LAYER_SHELL=0) the window stays an ordinary always-on-top window that refuses focus; on X11 its position is ours, on GNOME's
/// Wayland session it is the compositor's (see `desktop_positioned`).
pub fn make_desktop_window(win: &WebviewWindow) {
    let Ok(gw) = win.gtk_window() else { return };
    let wanted = std::env::var("NOTCHMEOW_LAYER_SHELL").map(|v| v != "0").unwrap_or(true);
    let supported = unsafe { layer::gtk_layer_is_supported() } != 0;
    if !wanted || !supported || gw.is_realized() {
        crate::log::line("desktop cat is a regular window");
        gw.set_accept_focus(false);
        gw.connect_map_event(|w, _| {
            apply_rects(w, &DESKTOP_REGION.lock().unwrap());
            gtk::glib::Propagation::Proceed
        });
        return;
    }
    // See make_non_activating: a layer surface has no titlebar, and a client-decorated GtkWindow recomputes its own input region on every map.
    gw.set_titlebar(None::<&gtk::Widget>);
    let ptr = gtk_window_ptr(&gw);
    unsafe {
        layer::gtk_layer_init_for_window(ptr);
        layer::gtk_layer_set_namespace(ptr, c"notchmeow-cat".as_ptr());
        layer::gtk_layer_set_layer(ptr, layer::LAYER_TOP);
        layer::gtk_layer_set_anchor(ptr, layer::EDGE_TOP, 1);
        layer::gtk_layer_set_anchor(ptr, layer::EDGE_LEFT, 1);
        layer::gtk_layer_set_exclusive_zone(ptr, 0);
        layer::gtk_layer_set_keyboard_mode(ptr, layer::KEYBOARD_NONE);
    }
    // WebKitGTK in a freshly mapped layer surface never paints its first frame (see make_non_activating): unmap and map it once, right after the first map.
    let remapped = std::cell::Cell::new(false);
    gw.connect_map_event(move |w, _| {
        apply_rects(w, &DESKTOP_REGION.lock().unwrap());
        if !remapped.replace(true) {
            let w = w.clone();
            gtk::glib::idle_add_local_once(move || {
                w.hide();
                w.show_all();
                apply_rects(&w, &DESKTOP_REGION.lock().unwrap());
            });
        }
        gtk::glib::Propagation::Proceed
    });
    DESKTOP_LAYER.store(true, Ordering::Relaxed);
    crate::log::line("desktop cat is a layer-shell surface");
}

/// Whether the app can put the desktop cat's window where it wants: a layer-shell surface (margins), or any window on X11. GNOME's Wayland session ignores a window's position, so
/// there the cat's spot is not ours to set or to remember, and Settings says so under the switch. NOTCHMEOW_DESKTOP_POSITION=1 or 0 overrides the guess.
pub fn desktop_positioned() -> bool {
    match std::env::var("NOTCHMEOW_DESKTOP_POSITION").as_deref() {
        Ok("1") => return true,
        Ok("0") => return false,
        _ => {}
    }
    DESKTOP_LAYER.load(Ordering::Relaxed) || std::env::var_os("WAYLAND_DISPLAY").is_none()
}

/// Puts the desktop window's top-left at (x, y) physical px: the margins of a layer surface on the monitor's output, or the window's position.
pub fn place_desktop(win: &WebviewWindow, x: i32, y: i32, monitor_index: usize, monitor_origin: (i32, i32), scale: f64) {
    if !DESKTOP_LAYER.load(Ordering::Relaxed) {
        let _ = win.set_position(tauri::PhysicalPosition::new(x, y));
        return;
    }
    let Ok(gw) = win.gtk_window() else { return };
    let ptr = gtk_window_ptr(&gw);
    let s = if scale > 0.0 { scale } else { 1.0 };
    unsafe {
        if DESKTOP_MONITOR.swap(monitor_index, Ordering::Relaxed) != monitor_index {
            // tao lists the monitors in GDK's order, so the index is the same one.
            if let Some(m) = gtk::gdk::Display::default().and_then(|d| d.monitor(monitor_index as i32)) {
                layer::gtk_layer_set_monitor(ptr, m.to_glib_none().0);
            }
        }
        layer::gtk_layer_set_margin(ptr, layer::EDGE_LEFT, ((x - monitor_origin.0) as f64 / s).round() as std::os::raw::c_int);
        layer::gtk_layer_set_margin(ptr, layer::EDGE_TOP, ((y - monitor_origin.1) as f64 / s).round() as std::os::raw::c_int);
    }
}

/// Only these rectangles (window logical px) take the mouse; everything else goes to the window underneath.
pub fn set_desktop_input(win: &WebviewWindow, rects: &[(f64, f64, f64, f64)]) {
    *DESKTOP_REGION.lock().unwrap() = rects.to_vec();
    let Ok(gw) = win.gtk_window() else { return };
    apply_rects(&gw, rects);
}

fn apply_rects(gw: &impl IsA<gtk::Widget>, rects: &[(f64, f64, f64, f64)]) {
    let Some(gdk_window) = gw.window() else { return };
    let region = gtk::cairo::Region::create();
    for &(x, y, w, h) in rects {
        let _ = region.union_rectangle(&gtk::cairo::RectangleInt::new(x.floor() as i32, y.floor() as i32, w.ceil() as i32, h.ceil() as i32));
    }
    gdk_window.input_shape_combine_region(&region, 0, 0);
}

/// Nothing to look for: the cat's layer is below fullscreen windows already.
pub fn fullscreen_app_covers(_monitors: &[(i32, i32, u32, u32)]) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_private_directory_of_ours_can_hold_the_relay_socket() {"""),
])
print("applied")
PYEOF
```

Run (needs the image; otherwise this step and Step 8 are owed and the Rust is reviewed by reading only):

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/h-tauri -- desktop:: 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok. 3 passed` with no `error` and no `warning` (`only_the_cat_takes_the_mouse`, `a_physical_rectangle_is_in_points_and_the_window_goes_where_the_head_is`, `the_cursor_poll_is_fast_only_near_the_window`). A compile error whose cause is not obvious: stop and report it with the first ten lines (this task already runs on Sonnet 5.5; the main session decides).

- [ ] **Step 8: Run the whole Rust suite, and check that nothing was added to the manifests**

Run:

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/h-tauri 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
git diff --stat notchmeow/rebrand -- windows/Cargo.lock windows/Cargo.toml windows/src-tauri/Cargo.toml | wc -l
```

Expected: `test result: ok.` for the library and the relay with no `error` and no `warning`, and `0` (no change to a manifest or the lock file). The Windows build of `platform/windows.rs` cannot run here: it is owed to `windows-tests.yml` and `windows.yml` on the owner's next push.

- [ ] **Step 9: Run the checks, then look at the page's shell**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `ℹ tests 301`, `ℹ pass 301`, `ℹ fail 0`.

Start the dev server (see "Starting and stopping the dev server"), then feed the page the three sizes by hand, the way the island's page will:

```bash
cd .claude/checkpoints/h-tauri
playwright-cli -s=htauri-win open 'http://127.0.0.1:14611/desktop.html' > /dev/null 2>&1
for s in small medium large; do playwright-cli -s=htauri-win eval "(() => { window.__body.handle({ k: 'show', spot: { x: 300, y: 300 }, coat: 'shrimpy', size: '$s' }); const c = document.querySelector('canvas'); return c.style.width.replace('px', '') + 'x' + c.style.height.replace('px', ''); })()" 2>&1 | grep -A1 "### Result" | tail -1; done
playwright-cli -s=htauri-win screenshot --filename="$(pwd)/window-large.png" > /dev/null 2>&1
playwright-cli -s=htauri-win console 2>&1 | grep '\[ERROR\]' | grep -vc favicon
playwright-cli -s=htauri-win close > /dev/null 2>&1
cd ../../..
```

Expected: `"80x113"`, `"108x151"`, `"160x226"` (the window's px at Small, Medium and Large with no kittens), `0` (no console error besides the favicon's 404), and `window-large.png` showing the Large cat, drawn at full detail, in the top left of a white page. Stop the server by its PID.

- [ ] **Step 10: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src/cat/desktopview.ts windows/desktop.html windows/src/desktop windows/vite.config.ts windows/src-tauri/capabilities/default.json windows/src/core/bridge.ts windows/src-tauri/src/desktop.rs windows/src-tauri/src/lib.rs windows/src-tauri/src/island.rs windows/src-tauri/src/platform windows/scripts/cat-tests/desktop-view.test.mjs windows/scripts/cat-tests/desktop-window.test.mjs
git commit -F - <<'MSG'
feat(desktop): the desktop cat's window and its click-through

A second transparent window, created hidden at launch, that holds the big cat on the desktop: its size and hit shapes, its placement in points, click-through from the cursor (Windows) or the input region (Linux), a top-layer layer-shell surface, and the commands the two pages use.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model and the trigger.

---

# Stage 3: dragging out, the flight and sending home

### Task 4: The flight's clock, the gestures, the trip and the frame governor

**Agent:** `nm-implementer-light` (Haiku 5.5, medium): every line is given, and everything here is pure and tested with fakes.

**Files:**
- Create: `windows/src/cat/desktopflight.ts`, `windows/src/cat/gestures.ts`, `windows/src/cat/desktoptrip.ts`, `windows/src/cat/desktopgov.ts`
- Test: `windows/scripts/cat-tests/desktop-flight.test.mjs`, `windows/scripts/cat-tests/desktop-trip.test.mjs`, `windows/scripts/cat-tests/desktop-gov.test.mjs`

**Interfaces:**
- Consumes: Task 1's `desktopStep`, `desktopFlightAt`, `DESKTOP_PHASE_INFO`, `clampSpot`, `rememberSpot`, `spotFor`, `spotOf`, `desktopFps`, `DESKTOP_FPS`.
- Produces: `DesktopFlight` (a flight's clock: `at(now)` gives the spot and whether it is over; `turn(now)` carries on from progress `1 - t` over the same path the other way; `setNotch` and `setDesktop` move its two ends); `Gestures` (a click acts after one double-click interval, so a double-click never also opens the island; a press that moves 4 px or more is a drag, reported as the pointer's distance from where it was pressed); `DesktopTrip` with `TripEnv`, `BodyMsg`, `BrainMsg`, `BodyLook` (the machine run for the island: every `act` becomes a message, a save or a change of the notch's empty spot); `FrameGovernor` (one timer; rate 0 stops everything).

**How the trip is wired.** `DesktopTrip.event(ev)` runs `desktopStep`; on a change it performs the act (`place`/`move`: clamp, remember, `show`; `flyOut`/`flyHome`/`retract`: a `fly` message with the notch end and the desktop end, `retract` with the surprised emote and a 450 ms delay; `turn`: a `turn` message; `resettle`: the spot again for the new screens; `dock`/`goHome`: `hide`), then tells the environment the notch's big-cat spot is empty or not (`DESKTOP_PHASE_INFO[phase].notchEmpty`) and saves `on` when it differs (`DESKTOP_PHASE_INFO[phase].on`). Only a change of the alert is an event (`alert(on)`), `sync()` turns a Settings switch that disagrees with the phase into a `toggle`, `launch()` flies a cat that was out back out, and `notchMoved()` tells a flight in the air that the notch spot moved (only a change is sent).

- [ ] **Step 1: Write the tests**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-flight.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { desktopFlightAt } from "../../src/cat/desktop.ts";
import { DesktopFlight } from "../../src/cat/desktopflight.ts";
import { finite, near } from "./util.mjs";

// The flight's clock (sub-project H): the path is the contract's `desktopFlightAt`; this keeps the time, turns the flight round and moves its ends.

test("a flight keeps its own clock: it ends in 600 ms at the target, and the same flight swapped retraces itself", () => {
  const a = { x: 480, y: 16 }, b = { x: 900, y: 500 };
  const f = new DesktopFlight(a, b, 1000, "out");
  assert.deepEqual([f.progress(1000), f.progress(1300), f.progress(1600), f.progress(9999), f.progress(500)], [0, 0.5, 1, 1, 0]);
  near(f.at(1000).x, a.x); near(f.at(1600).y, b.y);
  assert.equal(f.at(1599).done, false);
  assert.equal(f.at(1600).done, true);
  for (const t of [0, 0.25, 0.5, 0.9]) near(f.at(1000 + 600 * t).x, desktopFlightAt(a, b, t).x);
  assert.equal(f.direction, "out");
});

test("a flight that turns around carries on from 1 - t and is exactly where it was at the turn, then ends at the notch (a send-home or an alert that clears)", () => {
  const notch = { x: 480, y: 16 }, desk = { x: 900, y: 500 };
  const f = new DesktopFlight(notch, desk, 0, "out");
  const before = f.at(240);
  f.turn(240);
  const after = f.at(240);
  near(after.x, before.x); near(after.y, before.y);
  assert.equal(f.direction, "in");
  assert.equal(f.at(240 + 239).done, false);
  assert.equal(f.at(240 + 240).done, true, "back at the notch after the same time it had flown");
  near(f.at(480).x, notch.x); near(f.at(480).y, notch.y);
  f.turn(480);
  assert.equal(f.direction, "out");
  near(f.progress(480), 0, 1e-12);
  near(f.at(480).x, notch.x);
});

test("the notch end of a flight follows the notch spot, whichever way it flies, and the desktop end follows the desktop spot", () => {
  const f = new DesktopFlight({ x: 0, y: 0 }, { x: 100, y: 100 }, 0, "out");
  f.setNotch({ x: 10, y: 10 });
  near(f.at(0).x, 10);
  f.setDesktop({ x: 200, y: 200 });
  near(f.at(600).x, 200);
  f.turn(600);
  f.setNotch({ x: 30, y: 30 });
  near(f.at(600 + 600).x, 30, 1e-9);
  f.setNotch({ x: NaN, y: 0 });
  near(f.at(600 + 600).x, 30, 1e-9);
  assert.equal(new DesktopFlight({ x: NaN, y: 1 }, null, NaN, "in", -5).at(0).done, false);
  finite(new DesktopFlight(null, undefined, Infinity, "out", NaN).at(NaN));
});
EOF
```

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-trip.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { DESKTOP_PHASE_INFO, DESKTOP_PHASES, defaultDesktopSettings, desktopStep, spotFor } from "../../src/cat/desktop.ts";
import { DOUBLE_MS, DRAG_PX, Gestures } from "../../src/cat/gestures.ts";
import { SURPRISE_MS, DesktopTrip } from "../../src/cat/desktoptrip.ts";

// The trip as the island runs it: a fake environment records every message to the desktop window, every save and every change of the notch's big-cat spot.
const LAPTOP = [{ frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true }];
const NOTCH = { x: 756, y: 16 };
function world(over = {}) {
  const w = { settings: defaultDesktopSettings(), sent: [], saves: 0, empty: [], notch: NOTCH, screens: LAPTOP, ...over };
  w.env = {
    body: (m) => w.sent.push(m), notchSpot: () => w.notch, screens: () => w.screens, settings: () => w.settings,
    save: (s) => { w.settings = s; w.saves++; }, notchEmpty: (e) => w.empty.push(e),
  };
  w.trip = new DesktopTrip(w.env);
  return w;
}
const kinds = (w) => w.sent.map((m) => m.k);

test("taking the cat out from the menu: it flies from the notch to its default spot, the notch spot empties, 'out' is stored, and the landing changes nothing on screen", () => {
  const w = world();
  w.trip.toggle();
  assert.equal(w.trip.phase, "flyingOut");
  const want = spotFor({}, LAPTOP, "medium");
  assert.deepEqual(w.sent, [{ k: "fly", from: NOTCH, to: want, dir: "out" }]);
  assert.equal(w.settings.on, true);
  assert.equal(w.empty.at(-1), true);
  w.trip.flightDone();
  assert.equal(w.trip.phase, "onDesktop");
  assert.equal(w.sent.length, 1, "land sends nothing: the window is already there");
});

test("a drop on the desktop places the cat, held on the screen, and remembers the spot for these screens without a flight", () => {
  const w = world();
  w.trip.dragOut({ x: 5, y: 5 });
  assert.equal(w.trip.phase, "onDesktop");
  assert.deepEqual(w.sent, [{ k: "show", spot: { x: 56, y: 93 } }], "held 24 points from the head's edge, below the menu bar");
  assert.deepEqual(w.settings.spots, { "0,0,1512,982": { x: 56, y: 93 } });
  assert.equal(w.settings.on, true);
  // A move saves the new spot; a drop that is not a spot changes nothing.
  w.trip.move({ x: 700, y: 400 });
  assert.deepEqual(w.settings.spots["0,0,1512,982"], { x: 700, y: 400 });
  assert.deepEqual(w.sent.at(-1), { k: "show", spot: { x: 700, y: 400 } });
  const n = w.sent.length;
  w.trip.move({ x: NaN, y: 400 });
  w.trip.dragOut({ x: 1, y: 1 });
  assert.equal(w.sent.length, n);
  assert.equal(w.trip.phase, "onDesktop");
});

test("an approval takes the cat to the notch with the surprised emote, and the answer sends it back out to its spot", () => {
  const w = world();
  w.trip.dragOut({ x: 700, y: 400 });
  w.sent.length = 0;
  w.trip.alert(true);
  assert.equal(w.trip.phase, "retracting");
  assert.deepEqual(w.sent, [{ k: "fly", from: { x: 700, y: 400 }, to: NOTCH, dir: "in", emote: "surprised", delayMs: SURPRISE_MS }]);
  w.trip.flightDone();
  assert.equal(w.trip.phase, "atNotchForAlert");
  assert.deepEqual(w.sent.at(-1), { k: "hide" }, "docked: the notch shows the cat again");
  assert.equal(w.empty.at(-1), false);
  assert.equal(w.settings.on, true, "still out as far as Settings goes");
  w.trip.alert(false);
  assert.equal(w.trip.phase, "returning");
  assert.deepEqual(w.sent.at(-1), { k: "fly", from: NOTCH, to: { x: 700, y: 400 }, dir: "out" });
  w.trip.flightDone();
  assert.equal(w.trip.phase, "onDesktop");
});

test("an alert that clears mid-flight turns the cat around; one that comes mid-return turns it again", () => {
  const w = world();
  w.trip.dragOut({ x: 700, y: 400 });
  w.trip.alert(true);
  w.trip.alert(false);
  assert.equal(w.trip.phase, "returning");
  assert.equal(w.sent.at(-1).k, "turn");
  w.trip.alert(true);
  assert.equal(w.trip.phase, "retracting");
  assert.equal(w.sent.at(-1).k, "turn");
});

test("a send-home during an alert ends the trip at home, and an approval that lands while the cat is home takes nothing out", () => {
  const w = world();
  w.trip.dragOut({ x: 700, y: 400 });
  w.trip.alert(true);
  w.trip.flightDone();
  w.trip.sendHome();
  assert.equal(w.trip.phase, "home");
  assert.equal(w.settings.on, false);
  assert.equal(w.empty.at(-1), false);
  const n = w.sent.length;
  w.trip.alert(false); w.trip.alert(true);
  assert.equal(w.trip.phase, "home");
  assert.equal(w.sent.length, n, "an approval while the cat is home does not take it out");
});

test("a double-click flies the cat home, 'out' is cleared at once, and the landing hides the window and shows the notch cat", () => {
  const w = world();
  w.trip.dragOut({ x: 700, y: 400 });
  w.sent.length = 0;
  w.trip.sendHome();
  assert.equal(w.trip.phase, "flyingHome");
  assert.deepEqual(w.sent, [{ k: "fly", from: { x: 700, y: 400 }, to: NOTCH, dir: "in" }]);
  assert.equal(w.settings.on, false, "quitting mid-flight leaves the cat home");
  assert.equal(w.empty.at(-1), true, "the notch spot stays empty until the cat lands");
  w.trip.flightDone();
  assert.deepEqual([w.trip.phase, w.sent.at(-1), w.empty.at(-1)], ["home", { k: "hide" }, false]);
});

test("the switch flips the cat's trip: the stored 'out' says one thing and the phase another, and sync() takes the trip it asked for; a save of our own is not a request", () => {
  const w = world();
  assert.equal(w.trip.sync(), null);
  w.settings = { ...w.settings, on: true };
  w.trip.sync();
  assert.equal(w.trip.phase, "flyingOut");
  assert.equal(w.trip.sync(), null, "the machine stored on: true itself, so nothing is asked");
  w.settings = { ...w.settings, on: false };
  w.trip.sync();
  assert.equal(w.trip.phase, "flyingHome");
  w.settings = { ...w.settings, on: true };
  w.trip.sync();
  assert.equal(w.trip.phase, "flyingOut", "switched on again mid-flight: it turns around");
  assert.equal(w.sent.at(-1).k, "turn");
});

test("a cat that was out flies back out after the greeting, and a cat that was home does not", () => {
  const home = world();
  assert.equal(home.trip.launch().act, null);
  assert.equal(home.trip.phase, "home");
  const out = world();
  out.settings = { ...out.settings, on: true };
  out.trip.launch();
  assert.equal(out.trip.phase, "flyingOut");
  out.trip.launch();
  assert.equal(out.trip.phase, "flyingOut", "a second launch changes nothing");
});

test("the screens changed: the cat finds its spot again on the new arrangement, and the flight's desktop end follows", () => {
  const w = world();
  w.trip.dragOut({ x: 1400, y: 600 });
  w.screens = [{ frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: 0, y: 0, w: 800, h: 600 }, main: true }];
  w.trip.screensChanged();
  assert.equal(w.trip.phase, "onDesktop");
  const s = w.sent.at(-1);
  assert.equal(s.k, "desktopEnd");
  assert.ok(s.spot.x <= 800 - 24 - 32 && s.spot.y <= 600 - 24 - 32, "back on the small screen, in its default spot");
  w.trip.alert(true);
  const n = w.sent.length;
  w.trip.screensChanged();
  assert.equal(w.trip.phase, "retracting");
  assert.equal(w.sent.length, n, "a screens change mid-retract: the machine ignores it, the window keeps flying");
});

test("a flight in the air follows the notch spot; nothing is sent when the cat is not flying", () => {
  const w = world();
  w.trip.notchMoved();
  assert.equal(w.sent.length, 0);
  w.trip.dragOut({ x: 700, y: 400 });
  w.sent.length = 0;
  w.trip.notchMoved();
  assert.equal(w.sent.length, 0, "on the desktop");
  w.trip.alert(true);
  w.sent.length = 0;
  w.notch = { x: 756, y: 58 };
  w.trip.notchMoved();
  assert.deepEqual(w.sent, [{ k: "notchEnd", spot: { x: 756, y: 58 } }]);
  w.trip.notchMoved();
  assert.equal(w.sent.length, 1, "only a change is sent");
  w.notch = NOTCH;
  w.trip.notchMoved();
  assert.deepEqual(w.sent.at(-1), { k: "notchEnd", spot: NOTCH }, "and it can move back");
});

test("only a change of the alert is an event, and an event that makes no sense changes nothing: no message, no save, no notch change", () => {
  const w = world();
  assert.equal(w.trip.alert(false), null);
  w.trip.alert(true);
  assert.equal(w.trip.alert(true), null);
  assert.equal(w.sent.length + w.saves + w.empty.length, 0, "an alert while home does nothing");
  for (const ev of [{ type: "flightDone" }, { type: "move", spot: { x: 1, y: 1 } }, { type: "bogus" }, null, 7]) {
    const r = w.trip.event(ev);
    assert.equal(r.act, null);
  }
  assert.equal(w.sent.length + w.saves + w.empty.length, 0);
});

test("every phase the trip can reach agrees with the contract: the notch is empty exactly where the cat is drawn, and 'on' is what the machine stored", () => {
  // Walk every event from every phase the trip reaches and compare the side effects with the phase's table row.
  const seen = new Set();
  const walk = (path) => {
    const w = world();
    for (const ev of path) w.trip.event(ev);
    const info = DESKTOP_PHASE_INFO[w.trip.phase];
    if (w.empty.length) assert.equal(w.empty.at(-1), info.notchEmpty, JSON.stringify(path));
    if (w.empty.length) assert.equal(w.settings.on, info.on, JSON.stringify(path));
    seen.add(w.trip.phase);
    return w;
  };
  const evs = [{ type: "toggle" }, { type: "sendHome" }, { type: "alertOn" }, { type: "alertOff" }, { type: "flightDone" }, { type: "dragOut", spot: { x: 700, y: 400 } }];
  const frontier = [[]];
  for (let depth = 0; depth < 5; depth++) for (const p of frontier.splice(0)) for (const ev of evs) { const q = [...p, ev]; walk(q); if (depth < 4) frontier.push(q); }
  assert.deepEqual([...seen].sort(), [...DESKTOP_PHASES].sort(), "every phase was reached");
  assert.equal(desktopStep("home", { type: "launch" }).act, "flyOut");
});

// ── gestures ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

function pointer() {
  const p = { now: 0, timers: [], out: [] };
  p.g = new Gestures({
    set: (fn, ms) => { p.timers.push({ at: p.now + ms, fn, id: p.timers.length + 1 }); return p.timers.length; },
    clear: (id) => { const t = p.timers.find((x) => x.id === id); if (t) t.fn = null; },
    emit: (g) => p.out.push(g),
  });
  p.advance = (ms) => { p.now += ms; for (const t of p.timers) if (t.fn && t.at <= p.now) { const f = t.fn; t.fn = null; f(); } };
  return p;
}

test("a click acts after one double-click interval, so a double-click never also opens the island", () => {
  const p = pointer();
  p.g.press(10, 10); p.g.release();
  assert.deepEqual(p.out, []);
  p.advance(DOUBLE_MS - 1);
  assert.deepEqual(p.out, []);
  p.advance(1);
  assert.deepEqual(p.out, [{ k: "click" }]);
  p.out.length = 0;
  p.g.press(10, 10); p.g.release();
  p.advance(100);
  p.g.press(10, 10); p.g.release();
  p.advance(5000);
  assert.deepEqual(p.out, [{ k: "double" }], "a double-click, and no click after it");
});

test("a press that moves 4 px or more is a drag, reported in steps, and never a click; a wobble under 4 px is still a click", () => {
  const p = pointer();
  p.g.press(100, 100); p.g.move(102, 102); p.g.release();
  p.advance(DOUBLE_MS);
  assert.deepEqual(p.out, [{ k: "click" }]);
  p.out.length = 0;
  p.g.press(100, 100); p.g.move(100 + DRAG_PX - 0.1, 100); p.g.move(104, 100); p.g.move(110, 105); p.g.release();
  assert.deepEqual(p.out, [{ k: "dragStart" }, { k: "drag", dx: 4, dy: 0 }, { k: "drag", dx: 10, dy: 5 }, { k: "dragEnd" }], "each step is the pointer's distance from where it was pressed: the window follows it back to the press point");
  p.advance(5000);
  assert.equal(p.out.length, 4, "no click after a drag");
});

test("a drag cancels a click that was waiting, a cancel ends a drag, and a point that is not a number is ignored", () => {
  const p = pointer();
  p.g.press(1, 1); p.g.release();
  p.g.press(1, 1); p.g.move(50, 50);
  assert.deepEqual(p.out, [{ k: "dragStart" }, { k: "drag", dx: 49, dy: 49 }]);
  p.g.cancel();
  assert.equal(p.out.at(-1).k, "dragEnd");
  p.advance(5000);
  assert.equal(p.out.some((g) => g.k === "click" || g.k === "double"), false);
  const q = pointer();
  q.g.press(NaN, 1); q.g.move(Infinity, 1); q.g.release(); q.g.move(5, 5); q.g.release();
  q.advance(5000);
  assert.deepEqual(q.out, []);
});
EOF
```

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-gov.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { DESKTOP_FPS, desktopFps } from "../../src/cat/desktop.ts";
import { FrameGovernor, MAX_DT } from "../../src/cat/desktopgov.ts";

// The frame-rate governor (sub-project H, spec §3): it keeps to the rate the rule gives with one timer, and stops everything at 0.
function clock() {
  const c = { t: 0, timers: [], rafs: [], frames: [], nextId: 1 };
  c.env = {
    now: () => c.t,
    raf: (cb) => { const id = c.nextId++; c.rafs.push({ id, cb }); return id; },
    caf: (id) => { c.rafs = c.rafs.filter((r) => r.id !== id); },
    set: (fn, ms) => { const id = c.nextId++; c.timers.push({ id, at: c.t + ms, fn }); return id; },
    clear: (id) => { c.timers = c.timers.filter((x) => x.id !== id); },
  };
  c.gov = new FrameGovernor(c.env, (dt) => c.frames.push({ t: c.t, dt }));
  /** Runs `ms` of time: timers fire at their time, the display's frame callback every 1000/60 ms. */
  c.run = (ms) => {
    const end = c.t + ms;
    for (;;) {
      const next = Math.min(...c.timers.map((x) => x.at), c.rafs.length ? c.t + 1000 / 60 : Infinity, end + 0.0001);
      if (next > end) { c.t = end; return; }
      c.t = next;
      for (const x of c.timers.filter((q) => q.at <= c.t)) { c.timers = c.timers.filter((q) => q !== x); x.fn(); }
      if (c.rafs.length && Math.abs(next - (Math.round(next / (1000 / 60)) * (1000 / 60))) < 1e-6) { const r = c.rafs.splice(0); r.forEach((q) => q.cb()); }
    }
  };
  return c;
}

test("rate 0 schedules nothing: no timer and no frame callback, so a cat that cannot be seen costs nothing", () => {
  const c = clock();
  c.gov.setRate(0);
  c.run(10_000);
  assert.deepEqual([c.frames.length, c.timers.length, c.rafs.length, c.gov.running], [0, 0, 0, false]);
  c.gov.setRate(5);
  c.run(1100);
  c.gov.setRate(0);
  assert.deepEqual([c.timers.length, c.rafs.length, c.gov.running], [0, 0, false], "stopping clears both");
});

test("each rate draws about that many frames a second: 5 idle, 20 working, 0.5 asleep with the long gap's dt held to MAX_DT, 60 on the display's own callback", () => {
  for (const [fps, expect] of [[5, 5], [20, 20], [60, 60]]) {
    const c = clock();
    c.gov.setRate(fps);
    c.run(2000);
    assert.ok(Math.abs(c.frames.length / 2 - expect) <= expect * 0.1 + 1, `${fps} fps drew ${c.frames.length / 2} a second`);
  }
  const c = clock();
  c.gov.setRate(DESKTOP_FPS.asleep);
  c.run(7000);
  assert.deepEqual(c.frames.map((f) => Math.round(f.t)), [2000, 4000, 6000]);
  assert.equal(c.frames[0].dt, 0, "the first frame after a start has no dt");
  assert.equal(c.frames[1].dt, MAX_DT, "a 2 s gap is held to MAX_DT");
});

test("a new rate takes effect at once and the same rate leaves the schedule alone; a rate that is not a number is 0; 120 is 60", () => {
  const c = clock();
  c.gov.setRate(5);
  const timer = c.timers[0];
  c.gov.setRate(5);
  assert.equal(c.timers[0], timer, "the same rate: the same timer");
  c.gov.setRate(20);
  assert.equal(c.timers.length, 1);
  assert.equal(c.timers[0].at, 50);
  for (const bad of [NaN, Infinity, -5, "20", null, undefined]) { c.gov.setRate(bad); assert.equal(c.gov.fps, 0, String(bad)); assert.equal(c.gov.running, false); }
  c.gov.setRate(120);
  assert.equal(c.gov.fps, 60);
  assert.equal(c.rafs.length, 1);
});

test("poke() draws one frame now and carries on at the rate; it does nothing at rate 0; a rate set from inside a frame is not scheduled twice", () => {
  const c = clock();
  c.gov.poke();
  assert.equal(c.frames.length, 0);
  c.gov.setRate(5);
  c.run(50);
  c.gov.poke();
  assert.equal(c.frames.length, 1);
  assert.equal(c.timers.length, 1, "one timer, not two");
  const d = clock();
  let g;
  g = new FrameGovernor(d.env, () => { g.setRate(20); });
  g.setRate(5);
  d.run(500);
  assert.ok(d.timers.length + d.rafs.length === 1, "one schedule after a frame that changed the rate");
});

test("the frame-rate rule and the governor agree: a cat on the desktop idles at 5, works at 20, sleeps at 0.5, is still at 60 only in motion and costs nothing hidden", () => {
  const rate = (o) => desktopFps({ phase: "onDesktop", ...o });
  assert.deepEqual([rate({}), rate({ working: true }), rate({ asleep: true }), rate({ dragging: true }), rate({ hidden: true })], [5, 20, 0.5, 60, 0]);
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-flight.test.mjs scripts/cat-tests/desktop-trip.test.mjs scripts/cat-tests/desktop-gov.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (tests|pass|fail)" | cut -c1-90 | sort -u; cd ..
```

Expected: a line with `ERR_MODULE_NOT_FOUND`, `# tests 3`, `# pass 0` and `# fail 3` (each file fails to load).

- [ ] **Step 3: Write the modules**

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/desktopflight.ts <<'EOF'
// The desktop cat's flight in the air (sub-project H, spec §1): one clock for a trip between the notch spot and the desktop spot. The path is `desktopFlightAt`; this keeps the
// time. A flight that turns around (an alert that clears, a send-home during a flight) keeps its clock and carries on from progress 1 - t over the same path the other way. Pure:
// the time is given, never read.

import { DESKTOP_FLIGHT_MS, desktopFlightAt, spotOf } from "./desktop.ts";
import type { Spot } from "./desktop.ts";

export class DesktopFlight {
  private from: Spot;
  private to: Spot;
  private t0: number;
  private p0 = 0;
  /** Which end is the notch spot now: the flight starts at it (`out`) or ends at it (`in`). */
  private notchIs: "from" | "to";
  private readonly ms: number;

  /** A flight from `from` to `to` that begins at `now` (ms). `dir` 'out' means `from` is the notch spot, 'in' that `to` is. */
  constructor(from: Spot, to: Spot, now: number, dir: "out" | "in", ms = DESKTOP_FLIGHT_MS) {
    this.from = spotOf(from) ?? { x: 0, y: 0 };
    this.to = spotOf(to) ?? { x: 0, y: 0 };
    this.t0 = Number.isFinite(now) ? now : 0;
    this.notchIs = dir === "out" ? "from" : "to";
    this.ms = Number.isFinite(ms) && ms > 0 ? ms : DESKTOP_FLIGHT_MS;
  }

  /** How far along it is, 0 to 1. */
  progress(now: number): number {
    const t = this.p0 + (Number.isFinite(now) ? (now - this.t0) / this.ms : 0);
    return t < 0 ? 0 : t > 1 ? 1 : t;
  }

  /** The cat's spot and whether the flight is over. */
  at(now: number): { x: number; y: number; done: boolean } {
    const p = desktopFlightAt(this.from, this.to, this.progress(now));
    return { x: p.x, y: p.y, done: this.progress(now) >= 1 };
  }

  /** Reverses the flight: carries on from progress 1 - t, towards the end it came from. */
  turn(now: number): void {
    const t = this.progress(now);
    [this.from, this.to] = [this.to, this.from];
    this.notchIs = this.notchIs === "from" ? "to" : "from";
    this.p0 = 1 - t;
    this.t0 = Number.isFinite(now) ? now : this.t0;
  }

  /** The notch spot moved (the island opened for an alert, or shut): the notch end follows it. */
  setNotch(spot: Spot): void {
    const s = spotOf(spot);
    if (!s) return;
    if (this.notchIs === "from") this.from = s; else this.to = s;
  }

  /** The desktop spot moved (the screens changed): the desktop end follows it. */
  setDesktop(spot: Spot): void {
    const s = spotOf(spot);
    if (!s) return;
    if (this.notchIs === "from") this.to = s; else this.from = s;
  }

  get direction(): "out" | "in" { return this.notchIs === "from" ? "out" : "in"; }
}
EOF
```

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/gestures.ts <<'EOF'
// A press on the desktop cat is a click, a double-click or the start of a drag (sub-project H, spec §2). A click waits one double-click interval before it acts, so a double-click
// never also opens the island. Pure: the timer is injected and the points are the caller's (any one coordinate space), so the plain-Node checks (npm run check:cat) turn time by hand.

export type Gesture =
  | { k: "click" }
  | { k: "double" }
  | { k: "dragStart" }
  /** The pointer is (dx, dy) from where it was pressed. The caller moves what is dragged by that, and the pointer is back at the press point: the next step is the pointer's next move. */
  | { k: "drag"; dx: number; dy: number }
  | { k: "dragEnd" };

export interface GestureEnv {
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
  emit(g: Gesture): void;
}

/** Pixels the pointer must move before a press is a drag. */
export const DRAG_PX = 4;
/** The double-click interval (ms) when the system's cannot be read (the page asks Rust for it, Task 8b): 0.5 s, the Mac's fallback too. */
export const DOUBLE_MS = 500;

export class Gestures {
  private down: { x: number; y: number } | null = null;
  private dragging = false;
  private pending: number | null = null;
  private readonly env: GestureEnv;
  private readonly dragPx: number;
  /** The click's wait (ms): set from the system's double-click time when the page can read it. */
  doubleMs: number;

  constructor(env: GestureEnv, dragPx = DRAG_PX, doubleMs = DOUBLE_MS) {
    this.env = env;
    this.dragPx = dragPx;
    this.doubleMs = doubleMs;
  }

  /** The pointer went down on the cat. */
  press(x: number, y: number): void {
    if (![x, y].every(Number.isFinite)) return;
    this.down = { x, y };
    this.dragging = false;
  }

  /** The pointer moved with the button down. */
  move(x: number, y: number): void {
    if (!this.down || ![x, y].every(Number.isFinite)) return;
    if (!this.dragging) {
      if (Math.hypot(x - this.down.x, y - this.down.y) < this.dragPx) return;
      this.cancelPending();
      this.dragging = true;
      this.env.emit({ k: "dragStart" });
    }
    this.env.emit({ k: "drag", dx: x - this.down.x, dy: y - this.down.y });
  }

  /** The button was released. */
  release(): void {
    if (!this.down) return;
    this.down = null;
    if (this.dragging) {
      this.dragging = false;
      this.env.emit({ k: "dragEnd" });
      return;
    }
    if (this.pending !== null) {
      this.cancelPending();
      this.env.emit({ k: "double" });
      return;
    }
    this.pending = this.env.set(() => { this.pending = null; this.env.emit({ k: "click" }); }, this.doubleMs);
  }

  /** The press was cancelled (the pointer left the window, or a menu opened): nothing is emitted, and a drag ends. */
  cancel(): void {
    const wasDragging = this.dragging;
    this.down = null;
    this.dragging = false;
    if (wasDragging) this.env.emit({ k: "dragEnd" });
  }

  private cancelPending(): void {
    if (this.pending !== null) { this.env.clear(this.pending); this.pending = null; }
  }

  get isDragging(): boolean { return this.dragging; }
}
EOF
```

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/desktoptrip.ts <<'EOF'
// The desktop cat's trip as the island lives it (sub-project H, spec §1). `desktopStep` (desktop.ts, the contract) says which phase comes next and what to do; this runs it:
// it keeps the phase, turns every `act` into messages for the desktop window (the body) and calls for the rest (save the settings, empty the notch's big-cat spot). It does not draw
// and does not read a clock: everything it touches is in `TripEnv`, so the plain-Node checks (npm run check:cat) drive it with a fake one. The brain is the island's page; the body is
// the desktop window's page, which draws the cat and runs the flight (cat/desktopflight.ts) and answers with `BrainMsg`.

import { DESKTOP_PHASE_INFO, clampSpot, desktopStep, rememberSpot, spotFor, spotOf } from "./desktop.ts";
import type { DesktopEvent, DesktopPhase, DesktopSettings, DesktopSizeId, DesktopStep, Screen, Spot } from "./desktop.ts";

/** How long the cat shows the surprised emote before it flies to the notch for an alert (ms). */
export const SURPRISE_MS = 450;

/** What the desktop cat looks like now, as the island's page (the brain) knows it: the body draws it. */
export interface BodyLook { coat: string; state: string; size: DesktopSizeId }

/** What the brain tells the body. */
export type BodyMsg =
  /** How the cat looks (and its size): sent whenever it changes while the cat is on the desktop, and before the first `show` or `fly`. */
  | { k: "look"; look: BodyLook }
  /** The cat is carried by the pointer, out of the notch (`on`), or has been put down. */
  | { k: "carry"; on: boolean }
  /** Play an emote now (a click's happy). */
  | { k: "emote"; name: string }
  /** Show the cat at this spot, with no flight. */
  | { k: "show"; spot: Spot }
  /** Fly from `from` to `to`; `dir` says which end is the notch spot. A delay and an emote come first (the alert's surprise). */
  | { k: "fly"; from: Spot; to: Spot; dir: "out" | "in"; emote?: string; delayMs?: number }
  /** Reverse the flight in progress. */
  | { k: "turn" }
  /** The notch spot moved: the notch end of the flight follows. */
  | { k: "notchEnd"; spot: Spot }
  /** The desktop spot moved (the screens changed): put the cat there, or move the desktop end of the flight. */
  | { k: "desktopEnd"; spot: Spot }
  /** Stop drawing and hide the window. */
  | { k: "hide" };

/** What the body tells the brain. */
export type BrainMsg =
  | { k: "ready" }
  | { k: "flightDone" }
  | { k: "click" }
  | { k: "doubleClick" }
  | { k: "move"; spot: Spot }
  | { k: "dragOut"; spot: Spot }
  | { k: "menu"; item: "open" | "home" | "small" | "medium" | "large" }
  | { k: "wake"; why: "hover" | "click" }
  | { k: "screens" };

export interface TripEnv {
  /** Sends a message to the desktop window. */
  body(msg: BodyMsg): void;
  /** The big cat's spot in the notch right now (the compact place, or the expanded one while the island is open for an alert), in points; null before the island knows. */
  notchSpot(): Spot | null;
  /** The connected screens, in points. */
  screens(): Screen[];
  /** The stored desktop settings, and a place to put new ones. */
  settings(): DesktopSettings;
  save(next: DesktopSettings): void;
  /** The big cat's spot in the notch is empty (true) while the cat is on the desktop or in the air. */
  notchEmpty(empty: boolean): void;
  /** The phase changed (the tray item's words follow it). */
  phase?(phase: DesktopPhase): void;
}

export class DesktopTrip {
  private _phase: DesktopPhase = "home";
  private spot: Spot | null = null;
  private alerting = false;
  /** The notch spot the flight in the air was last told about, so `notchMoved` sends only a change. */
  private notchKey = "";
  private readonly env: TripEnv;

  constructor(env: TripEnv) { this.env = env; }

  get phase(): DesktopPhase { return this._phase; }

  /** Runs one event through the machine and carries out what it says. An event that makes no sense in this phase changes nothing. */
  event(ev: DesktopEvent): DesktopStep {
    const r = desktopStep(this._phase, ev);
    if (r.act === null) return r;
    this._phase = r.state;
    this.perform(r.act, ev);
    const info = DESKTOP_PHASE_INFO[r.state], s = this.env.settings();
    this.env.notchEmpty(info.notchEmpty);
    this.env.phase?.(r.state);
    if (s.on !== info.on) this.env.save({ ...s, on: info.on });
    return r;
  }

  private notch(): Spot { return this.env.notchSpot() ?? this.spot ?? { x: 0, y: 0 }; }
  private keyOf = (p: Spot) => `${p.x},${p.y}`;
  /** Where the cat sits on the desktop now: the remembered spot for these screens, else the default one. */
  private desktopSpot(): Spot {
    const s = this.env.settings();
    return spotFor(s.spots, this.env.screens(), s.size) ?? this.spot ?? { x: 300, y: 300 };
  }
  /** Saves `spot`, held where the cat may sit, as this arrangement's spot, and returns it. With no screens nothing is kept and the spot stands as it came. */
  private remember(spot: Spot): Spot {
    const s = this.env.settings(), screens = this.env.screens(), clamped = clampSpot(spot, screens, s.size);
    if (!clamped) return spot;
    this.env.save({ ...s, spots: rememberSpot(s.spots, screens, clamped, s.size) });
    return clamped;
  }

  private perform(act: NonNullable<DesktopStep["act"]>, ev: DesktopEvent): void {
    const send = (m: Parameters<TripEnv["body"]>[0]) => this.env.body(m);
    switch (act) {
      case "place": case "move": {
        this.spot = this.remember(spotOf(ev.spot) as Spot);
        send({ k: "show", spot: this.spot });
        break;
      }
      case "flyOut": {
        const to = this.desktopSpot(), from = this.notch();
        this.spot = to;
        this.notchKey = this.keyOf(from);
        send({ k: "fly", from, to, dir: "out" });
        break;
      }
      case "flyHome": case "retract": {
        const from = this.spot ?? this.desktopSpot(), to = this.notch();
        this.notchKey = this.keyOf(to);
        send(act === "retract" ? { k: "fly", from, to, dir: "in", emote: "surprised", delayMs: SURPRISE_MS } : { k: "fly", from, to, dir: "in" });
        break;
      }
      case "turn":
        send({ k: "turn" });
        break;
      case "resettle":
        this.spot = this.desktopSpot();
        send({ k: "desktopEnd", spot: this.spot });
        break;
      case "dock": case "goHome":
        send({ k: "hide" });
        break;
      case "keep": case "land":
        break;
    }
  }

  // ── The events, one method each ───────────────────────────────────────────────────────────────────────────────────────────────────────

  /** The big cat was dropped on empty desktop at `spot`. */
  dragOut(spot: Spot) { return this.event({ type: "dragOut", spot }); }
  /** The desktop cat was released at `spot`. */
  move(spot: Spot) { return this.event({ type: "move", spot }); }
  toggle() { return this.event({ type: "toggle" }); }
  sendHome() { return this.event({ type: "sendHome" }); }
  flightDone() { return this.event({ type: "flightDone" }); }
  screensChanged() { return this.event({ type: "screensChanged" }); }
  /** The app started and the greeting is over: a cat that was out flies back out. */
  launch() { return this.settingsOn ? this.event({ type: "launch" }) : { state: this._phase, act: null }; }

  /** An approval or a question is pending (true) or both are clear (false). Only a change is an event. */
  alert(on: boolean): DesktopStep | null {
    if (on === this.alerting) return null;
    this.alerting = on;
    return this.event({ type: on ? "alertOn" : "alertOff" });
  }

  private get settingsOn(): boolean { return this.env.settings().on === true; }

  /** Settings changed (the switch in Settings, or the tray): the stored "out" says one thing and the phase another, so the cat takes the trip the switch asked for. */
  sync(): DesktopStep | null {
    return this.settingsOn === DESKTOP_PHASE_INFO[this._phase].on ? null : this.event({ type: "toggle" });
  }

  /** The notch spot moved (the island opened or shut): a flight in the air follows it. Only a change is sent. */
  notchMoved(): void {
    if (!DESKTOP_PHASE_INFO[this._phase].flight) return;
    const n = this.notch(), key = this.keyOf(n);
    if (key === this.notchKey) return;
    this.notchKey = key;
    this.env.body({ k: "notchEnd", spot: n });
  }
}
EOF
```

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/desktopgov.ts <<'EOF'
// The desktop cat's frame-rate governor (sub-project H, spec §3). `desktopFps` (desktop.ts, the contract) says how many frames a second the cat needs; this keeps to it. At 60 it
// follows the display's own frame callback; at any lower rate it sleeps on one timer between frames, so a cat that is idle wakes the page five times a second and a cat that cannot be
// seen (0) wakes it never: no timer, no frame callback. Pure: the clock, the timers and the frame callback are injected, so the plain-Node checks (npm run check:cat) turn time by hand.

export interface GovEnv {
  now(): number;
  raf(cb: () => void): number;
  caf(id: number): void;
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
}

/** A frame may be this many seconds after the last, however long the wait was (a cat asleep draws every 2 s): the engine holds it to 0.25 anyway. */
export const MAX_DT = 0.25;

export class FrameGovernor {
  private rate = 0;
  private raf: number | null = null;
  private timer: number | null = null;
  private last = -1;
  private readonly env: GovEnv;
  private readonly draw: (dt: number) => void;

  /** `draw` gets the seconds since the last frame: 0 on the first after a start, never more than MAX_DT. */
  constructor(env: GovEnv, draw: (dt: number) => void) {
    this.env = env;
    this.draw = draw;
  }

  /** Frames a second now: 0 stops everything; a rate that is not a finite number is 0. A new rate takes effect at once, and the same rate leaves the schedule alone. */
  setRate(fps: number): void {
    const next = typeof fps === "number" && Number.isFinite(fps) && fps > 0 ? Math.min(60, fps) : 0;
    if (next === this.rate) return;
    this.rate = next;
    this.stop();
    if (next === 0) { this.last = -1; return; }
    this.schedule();
  }

  /** Draws one frame now, whatever the rate (an emote started, a message arrived) and carries on at the rate. */
  poke(): void {
    if (this.rate === 0) return;
    this.stop();
    this.frame();
  }

  get fps(): number { return this.rate; }
  get running(): boolean { return this.raf !== null || this.timer !== null; }

  private stop(): void {
    if (this.raf !== null) { this.env.caf(this.raf); this.raf = null; }
    if (this.timer !== null) { this.env.clear(this.timer); this.timer = null; }
  }

  private schedule(): void {
    if (this.rate >= 60) this.raf = this.env.raf(() => { this.raf = null; this.frame(); });
    else this.timer = this.env.set(() => { this.timer = null; this.frame(); }, 1000 / this.rate);
  }

  private frame(): void {
    const now = this.env.now(), dt = this.last < 0 ? 0 : Math.min(MAX_DT, Math.max(0, (now - this.last) / 1000));
    this.last = now;
    this.draw(Number.isFinite(dt) ? dt : 0);
    if (this.rate > 0 && !this.running) this.schedule();
  }
}
EOF
```

- [ ] **Step 4: Run the tests to see them pass**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-flight.test.mjs scripts/cat-tests/desktop-trip.test.mjs scripts/cat-tests/desktop-gov.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..
```

Expected: `# tests 23`, `# pass 23`, `# fail 0`.

- [ ] **Step 5: Prove the tests can bite**

Run:

```bash
cd windows
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktopflight.ts 'this.p0 = 1 - t;' 'this.p0 = t;' scripts/cat-tests/desktop-flight.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktopflight.ts 'this.notchIs = this.notchIs === "from" ? "to" : "from";' '' scripts/cat-tests/desktop-flight.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/gestures.ts 'if (Math.hypot(x - this.down.x, y - this.down.y) < this.dragPx) return;' 'if (Math.hypot(x - this.down.x, y - this.down.y) <= this.dragPx) return;' scripts/cat-tests/desktop-trip.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/gestures.ts 'this.pending = this.env.set(() => { this.pending = null; this.env.emit({ k: "click" }); }, this.doubleMs);' 'this.env.emit({ k: "click" });' scripts/cat-tests/desktop-trip.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktoptrip.ts 'if (s.on !== info.on) this.env.save({ ...s, on: info.on });' '' scripts/cat-tests/desktop-trip.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktoptrip.ts 'this.env.notchEmpty(info.notchEmpty);' '' scripts/cat-tests/desktop-trip.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktoptrip.ts 'if (key === this.notchKey) return;' '' scripts/cat-tests/desktop-trip.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktopgov.ts 'if (this.rate > 0 && !this.running) this.schedule();' 'if (this.rate > 0) this.schedule();' scripts/cat-tests/desktop-gov.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktopgov.ts 'Math.min(MAX_DT,' 'Math.min(9,' scripts/cat-tests/desktop-gov.test.mjs
cd ..
```

Expected, in order: `# fail 1`, `# fail 2`, `# fail 1`, `# fail 2`, `# fail 4`, `# fail 4`, `# fail 1`, `# fail 1`, `# fail 1`.

- [ ] **Step 6: Run the whole checks**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `ℹ tests 324`, `ℹ pass 324`, `ℹ fail 0`.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src/cat/desktopflight.ts windows/src/cat/gestures.ts windows/src/cat/desktoptrip.ts windows/src/cat/desktopgov.ts windows/scripts/cat-tests/desktop-flight.test.mjs windows/scripts/cat-tests/desktop-trip.test.mjs windows/scripts/cat-tests/desktop-gov.test.mjs
git commit -F - <<'MSG'
feat(desktop): the flight's clock, the gestures, the trip and the frame governor

Pure modules tested with fakes: a flight that can turn round, a press that is a click, a double-click or a drag, the trip as the island runs it (every act becomes a message and a save), and the governor that keeps to a frame rate with one timer.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model.

---

### Task 5: Dragging out, the flight and sending home

**Agent:** `nm-implementer-deep` (Sonnet 5.5, high). **Trigger 1:** a press that becomes a drag across the island window's edge (mouse capture on both systems), a window placed on every frame of a drag and a flight from the other page, and messages between two webviews; the island's `mousedown` handling is rebuilt around it. The code is given in full and the logic is tested; the real behaviour is the owner's to check.

**Files:**
- Create: `windows/src/core/notchspot.ts`, `windows/src/cat/pressdrag.ts`, `windows/src/island/desktop.ts`
- Replace: `windows/src/desktop/body.ts` (the shell of Task 3)
- Modify: `windows/src/core/state.ts`, `windows/src/island/island.ts`, `windows/src/main.ts`, `windows/scripts/cat-tests/two-cats.test.mjs`
- Test: `windows/scripts/cat-tests/desktop-island.test.mjs`

**Interfaces:**
- Consumes: Task 4's `DesktopTrip`, `DesktopFlight`, `Gestures`, `FrameGovernor`, `BodyMsg`, `BrainMsg`; Task 3's `desktopWindowLayout`, `kittenSide`, `DesktopWorld`, the Bridge's `desktop*` calls and the commands; Task 2's `withDesktopSize`; the island's `alert`, `noteActivity`, `isBotHit`, `islandRect`.
- Produces: `notchCatLocal`, `islandToSpot`, `spotToIsland`; `PressDrag`; `DesktopBrain` (`trip`, `start`, `settingsChanged`, `afterGreeting`, `canCarry`, `carryStart`, `carry`, `carryEnd`) with `DesktopHost`; `DesktopBody` (a message in, a click, a double-click, a move, a menu choice or "flight done" out); `State.desktopNotchEmpty`; the island's changes: a press on the big cat is decided at release (a click, as before, or a drag out of the notch), the big cat, its glow and its kittens are not drawn while it is out (cat 2 and the pills stay), the launch greeting's end flies a cat that was out back out, and `main.ts` makes and starts the brain.

**How a drag out works.** A press on the big cat (compact or open island, not hidden, not during the greeting or the drop sequence, only for a cat at home, on GNOME too) is held until the button comes up. If the pointer moves 4 px it is a drag: `carryStart` empties the notch's spot and tells the body (`carry`); every `mousemove` (the page keeps receiving them outside its window while the button is down) puts the desktop window under the pointer (`desktop_place`, in points); on release the cat is put down (`trip.dragOut(spot)`: clamped, remembered, no flight) or, when it is dropped on the notch or the drop is refused, goes back. If the pointer never moves far it is the click it always was. **How the desktop cat is moved:** the body's drag is the pointer's distance from where it was pressed, which the window follows, so the pointer stays on the same point of the cat; on release the body tells the brain (`move`), which clamps and saves the spot. Where the system moves windows itself (`positioned: false`, GNOME) the body hands the drag to the system (the spot is still saved; GNOME may not honour it), and a drag out of the notch still works: the window comes up where the system puts it and the flight is a hop inside it.

- [ ] **Step 1: Write the test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-island.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DRAG_PX } from "../../src/cat/gestures.ts";
import { PressDrag } from "../../src/cat/pressdrag.ts";
import { PAIR, PANEL_W } from "../../src/core/layout.ts";
import { defaultWorld } from "../../src/cat/desktopview.ts";
import { islandToSpot, notchCatLocal, spotToIsland } from "../../src/core/notchspot.ts";
import { near } from "./util.mjs";

// The island's half of the desktop cat (sub-project H): the notch spot, the press on the big cat that is a click or a drag, and the seams the island's page and the desktop page are
// wired by, pinned by source (they need a browser).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");
const root = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the notch spot: the compact cat is at 40 in a 288 island, the pair's first at 30, and a hidden island counts as compact", () => {
  near(notchCatLocal("compact", "overview", false).x, (PANEL_W - 288) / 2 + 40);
  assert.equal(notchCatLocal("compact", "overview", false).y, 16);
  near(notchCatLocal("hidden", "overview", false).x, notchCatLocal("compact", "overview", false).x);
  near(notchCatLocal("compact", "overview", true).x, (PANEL_W - 288) / 2 + PAIR.compact.x1);
  const open = notchCatLocal("expanded", "approval", false);
  assert.ok(open.x > 100 && open.x < 300 && open.y > 20 && open.y < 140, `the open island's cat is at ${JSON.stringify(open)}`);
  assert.notDeepEqual(open, notchCatLocal("compact", "approval", false), "the notch spot moves when the island opens: a flight in the air follows it");
});

test("the island window's px are points on the desktop, and back: the middle of the window is the middle of the island's screen", () => {
  const w = { ...defaultWorld(), island: { x: 0, y: 0, w: 1512, h: 982 }, islandK: 1 };
  assert.deepEqual(islandToSpot(w, PANEL_W / 2, 16), { x: 756, y: 16 });
  assert.deepEqual(islandToSpot(w, PANEL_W / 2 - 100, 40), { x: 656, y: 40 });
  const second = { ...w, island: { x: 1512, y: -100, w: 2560, h: 1440 }, islandK: 1.5 };
  assert.deepEqual(islandToSpot(second, PANEL_W / 2, 0), { x: 1512 + 1280, y: -100 });
  assert.deepEqual(islandToSpot(second, PANEL_W / 2 + 10, 10), { x: 1512 + 1280 + 15, y: -100 + 15 }, "one px of an island on a screen with another scale is islandK points");
  for (const world of [w, second]) for (const p of [{ x: 10, y: 5 }, { x: 360, y: 16 }, { x: 700, y: 300 }]) {
    const s = islandToSpot(world, p.x, p.y), b = spotToIsland(world, s);
    near(b.x, p.x); near(b.y, p.y);
  }
});

test("a press on the big cat is a click when it never moves 4 px and a drag when it does; a drag never clicks, and a press that is not a number is no press", () => {
  const p = new PressDrag();
  assert.deepEqual([p.move(1, 1), p.release()], [null, null], "nothing is pressed");
  p.press(100, 100);
  assert.deepEqual([p.move(102, 101), p.move(100, 103), p.dragging], [null, null, false]);
  assert.equal(p.release(), "click");
  assert.equal(p.release(), null);
  p.press(100, 100);
  assert.equal(p.move(100 + DRAG_PX, 100), "start");
  assert.deepEqual([p.move(200, 200), p.move(100, 100), p.dragging], ["drag", "drag", true], "once started it is a drag, even back at the press point");
  assert.equal(p.release(), "drop");
  p.press(NaN, 1);
  assert.deepEqual([p.active, p.move(50, 50), p.release()], [false, null, null]);
  p.press(1, 1); p.cancel();
  assert.deepEqual([p.active, p.release()], [false, null]);
  p.press(0, 0);
  assert.equal(p.move(NaN, 9), null, "a point that is not a number moves nothing");
});

test("the island: a press on the big cat is a click or a drag decided when the button comes up, the notch draws nothing of a cat that has left, cat 2 and the pills stay", () => {
  const i = source("island/island.ts");
  assert.match(i, /this\.desktop\?\.canCarry && !State\.desktopNotchEmpty && State\.mode !== "hidden" && !this\.greetingShown\(\) && !this\.uploadActive && this\.isBotHit\(x, y\)/);
  assert.match(i, /this\.pressAction = \(\) => this\.pressed\(x, y\);/);
  assert.match(i, /window\.addEventListener\("mousemove", \(e\) => this\.carryMove\(e\.clientX, e\.clientY\)\);\s*window\.addEventListener\("mouseup", \(e\) => this\.carryUp\(e\.clientX, e\.clientY\)\);/);
  assert.match(i, /this\.botCanvas\.style\.opacity = visible && !State\.desktopNotchEmpty \? "1" : "0";/);
  assert.match(i, /this\.pairShown = pair !== null && visible;/, "cat 2 is drawn whether the big cat is out or not");
  assert.match(i, /if \(!State\.desktopNotchEmpty\) this\.drawBot\(dt\);\s*if \(this\.pairShown\) this\.drawBot2\(dt\);/);
  assert.match(i, /const big = shown && cast\.big\.pill && !State\.desktopNotchEmpty \? State\.kittenView\(cast\.big\.pill, now\) : \[\]/);
  assert.match(i, /&& !this\.uploadActive && !State\.desktopNotchEmpty\) \{\s*const d = p\.diameter;/, "no glow for a cat that is not there");
  assert.match(i, /this\.greeting\.onComplete = \(\) => \{ this\.fsm\.greetComplete\(\); this\.desktop\?\.afterGreeting\(\); \};/);
  assert.match(i, /open: \(\) => this\.alert\(State\.defaultView\(\)\),/, "a click on the desktop cat opens the island the way the tray's Open does");
});

test("main.ts makes the brain after the settings are loaded, starts it before the greeting, and tells it when the settings changed", () => {
  const m = source("main.ts");
  assert.match(m, /const desktop = new DesktopBrain\(island\.desktopHost\(\)\);\s*island\.attachDesktop\(desktop\);/);
  assert.ok(m.indexOf("State.giveCoats();") < m.indexOf("new DesktopBrain"), "after the coats");
  assert.ok(m.indexOf("await desktop.start();") < m.indexOf("island.launch();"), "before the launch greeting");
  assert.match(m, /void refreshConfigured\(\);\s*desktop\.settingsChanged\(\);/);
});

test("the brain sends a look before the first show or fly, sends only a change, and the desktop window's page runs nothing it does not need", () => {
  const b = source("island/desktop.ts");
  assert.match(b, /if \(m\.k === "show" \|\| m\.k === "fly"\) this\.sendLook\(true\);/);
  assert.match(b, /if \(!force && key === this\.last\) return;/);
  assert.match(b, /get canCarry\(\): boolean \{ return this\.trip\.phase === "home"; \}/);
  assert.doesNotMatch(b, /setInterval|setTimeout|requestAnimationFrame/, "the brain runs no timer of its own");
  const body = source("desktop/body.ts");
  assert.doesNotMatch(body, /setInterval/);
  assert.equal(body.match(/requestAnimationFrame/g).length, 1, "the governor's frame callback is the only one");
  assert.match(body, /this\.cv\.addEventListener\("pointerdown"/);
  assert.match(body, /document\.addEventListener\("visibilitychange", \(\) => this\.rate\(\)\);/);
  assert.match(body, /if \(!this\.world\.positioned\) \{ void Bridge\.desktopNativeDrag\(\); this\.gest\.cancel\(\); break; \}/, "where the system moves windows (GNOME) it drags the window");
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-island.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (tests|pass|fail)" | cut -c1-90 | sort -u; cd ..
```

Expected: a line with `ERR_MODULE_NOT_FOUND`, `# tests 1`, `# pass 0` and `# fail 1`.

- [ ] **Step 3: Write the modules**

```bash
mkdir -p windows/src/core
cat > windows/src/core/notchspot.ts <<'EOF'
// Where the big cat's spot in the notch is on the desktop, and back (sub-project H, spec §1). The desktop cat's flight starts and ends there, and a cat dragged out of the notch is
// carried by the pointer, so the island's window pixels have to be turned into the points the contract's rules use (desktop.ts: the primary screen's scale as the one unit, the origin
// at the top left of the main screen) and back. Rust says where the island's screen is (`desktop_screens`); this is the arithmetic. Pure, so the plain-Node checks (npm run check:cat) can load it.

import type { Spot } from "../cat/desktop.ts";
import type { DesktopWorld } from "../cat/desktopview.ts";
import { PANEL_W, botPosition, islandSize, pairPlacement } from "./layout.ts";
import type { IslandMode, IslandViewName } from "./layout.ts";

/** The big cat's centre in the island window's px: where the compact cat sits (the hidden island counts as compact), or where the view puts it; the first of the pair in Two cats mode. */
export function notchCatLocal(mode: IslandMode, view: IslandViewName, pair: boolean): { x: number; y: number } {
  const m: IslandMode = mode === "hidden" ? "compact" : mode, size = islandSize(m, view);
  const p = (pair ? pairPlacement(m, view, size.h)?.first : null) ?? botPosition(m, view, size.h);
  return { x: (PANEL_W - size.w) / 2 + p.cx, y: p.cy };
}

/** A point of the island window (CSS px, the window is PANEL_W wide while the island is open) as a spot on the desktop. */
export const islandToSpot = (w: DesktopWorld, x: number, y: number): Spot => ({ x: w.island.x + w.island.w / 2 + (x - PANEL_W / 2) * w.islandK, y: w.island.y + y * w.islandK });

/** The inverse: a spot as a point of the island window. */
export const spotToIsland = (w: DesktopWorld, s: Spot): { x: number; y: number } => ({ x: PANEL_W / 2 + (s.x - (w.island.x + w.island.w / 2)) / w.islandK, y: (s.y - w.island.y) / w.islandK });
EOF
```

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/pressdrag.ts <<'EOF'
// A press on the big cat in the notch is a click or the start of a drag out of it (sub-project H, spec §1). A click acts when the button is released, as it always did (the
// caller keeps what a press did before); a press that moves 4 px or more is a drag, which never clicks. Pure: the points are the caller's, in any one coordinate space.

import { DRAG_PX } from "./gestures.ts";

export class PressDrag {
  private from: { x: number; y: number } | null = null;
  private drag = false;
  private readonly dragPx: number;

  constructor(dragPx = DRAG_PX) { this.dragPx = dragPx; }

  /** The button went down on the cat. A point that is not a number is no press. */
  press(x: number, y: number): void {
    this.from = Number.isFinite(x) && Number.isFinite(y) ? { x, y } : null;
    this.drag = false;
  }

  /** The pointer moved with the button down: "start" the first time it has moved far enough, "drag" after that, null while it is a click or when no press is on. */
  move(x: number, y: number): "start" | "drag" | null {
    if (!this.from || !Number.isFinite(x) || !Number.isFinite(y)) return null;
    if (this.drag) return "drag";
    if (Math.hypot(x - this.from.x, y - this.from.y) < this.dragPx) return null;
    this.drag = true;
    return "start";
  }

  /** The button was released: "click" for a press that never moved far, "drop" at the end of a drag, null with no press on. */
  release(): "click" | "drop" | null {
    if (!this.from) return null;
    const r = this.drag ? "drop" : "click";
    this.from = null;
    this.drag = false;
    return r;
  }

  /** The press was cancelled (the pointer was lost): nothing happens. */
  cancel(): void { this.from = null; this.drag = false; }

  get active(): boolean { return this.from !== null; }
  get dragging(): boolean { return this.drag; }
}
EOF
```

```bash
mkdir -p windows/src/island
cat > windows/src/island/desktop.ts <<'EOF'
// The desktop cat, the island's half (sub-project H). The island's page is the brain: it knows the agents, the approvals and the settings, runs the trip (cat/desktoptrip.ts) and
// tells the desktop window's page, the body (desktop/body.ts), what to draw and where to fly; the body answers with clicks, moves and "flight done". Messages go through Rust
// (`desktop_relay`), which owns nothing of the rules. Everything the user can do ends here as one event of the contract's machine.

import { Bridge, onEvent } from "../core/bridge";
import { islandToSpot } from "../core/notchspot";
import { defaultWorld } from "../cat/desktopview";
import type { DesktopWorld } from "../cat/desktopview";
import { State } from "../core/state";
import { cleanCatBlock, withDesktopSize } from "../cat/display";
import { DESKTOP_PHASE_INFO, desktopSizeOf } from "../cat/desktop";
import { DesktopTrip } from "../cat/desktoptrip";
import type { BodyLook, BodyMsg, BrainMsg } from "../cat/desktoptrip";

/** What the brain needs of the island. */
export interface DesktopHost {
  /** Opens the island at the notch, as a click on the notch does. */
  open(): void;
  /** A hover or a click wakes a sleeping cat (island/sleep.ts). */
  wake(kind: "hover" | "click"): void;
  /** The big cat's centre in the island window's px now. */
  notchLocal(): { x: number; y: number };
}

export class DesktopBrain {
  readonly trip: DesktopTrip;
  private world: DesktopWorld;
  private readonly host: DesktopHost;
  private last = "";
  private carrying = false;

  constructor(host: DesktopHost, world: DesktopWorld = defaultWorld()) {
    this.host = host;
    this.world = world;
    this.trip = new DesktopTrip({
      body: (m) => this.send(m),
      notchSpot: () => { const p = host.notchLocal(); return islandToSpot(this.world, p.x, p.y); },
      screens: () => this.world.screens,
      settings: () => State.settings.cat.desktop,
      save: (next) => {
        State.settings.cat = cleanCatBlock({ ...State.settings.cat, desktop: next });
        void Bridge.saveSettings(State.settings);
      },
      notchEmpty: (empty) => {
        if (State.desktopNotchEmpty === empty) return;
        State.desktopNotchEmpty = empty;
        State.notify();
      },
    });
  }

  /** Looks at the screens once and listens to the desktop window. Call it after the settings are loaded. */
  async start(): Promise<void> {
    await this.refresh();
    await onEvent<BrainMsg>("desktop-msg", (m) => this.onMsg(m));
    State.subscribe(() => this.changed());
  }

  /** The screens are asked for again (a monitor came or went). */
  private async refresh(): Promise<void> {
    const w = await Bridge.desktopScreens();
    if (w && Array.isArray(w.screens)) this.world = w;
  }

  get positioned(): boolean { return this.world.positioned; }

  private send(m: BodyMsg): void {
    // The body draws what it was last told: the first `show` or `fly` must come after a look.
    if (m.k === "show" || m.k === "fly") this.sendLook(true);
    void Bridge.desktopRelay("desktop", m);
  }

  /** What the desktop cat looks like: the big cat as the cast makes it. */
  private look(): BodyLook {
    return { coat: State.cast.big.cat, state: State.effectiveState, size: desktopSizeOf(State.settings.cat.desktop.size) };
  }

  /** Tells the body how the cat looks; only a change is sent (the clock does not count), unless forced. */
  private sendLook(force = false): void {
    const look = this.look(), key = JSON.stringify({ ...look, now: 0 });
    if (!force && key === this.last) return;
    this.last = key;
    void Bridge.desktopRelay("desktop", { k: "look", look } satisfies BodyMsg);
  }

  /** Something in State changed: an approval or a question may have come or gone, and the cat may look different. */
  private changed(): void {
    if (DESKTOP_PHASE_INFO[this.trip.phase].drawn || this.carrying) this.sendLook();
  }

  /** The settings changed (the switch in Settings, a size): the trip takes the trip the stored "out" asks for, and the cat is looked at again. */
  settingsChanged(): void {
    this.trip.sync();
    if (DESKTOP_PHASE_INFO[this.trip.phase].drawn) this.sendLook(true);
  }

  /** The greeting is over: a cat that was out flies back out. */
  afterGreeting(): void { this.trip.launch(); }

  private onMsg(m: BrainMsg): void {
    if (!m || typeof m !== "object") return;
    switch (m.k) {
      case "ready": this.sendLook(true); break;
      case "flightDone": this.trip.flightDone(); break;
      case "click": this.host.wake("click"); this.host.open(); break;
      case "doubleClick": this.trip.sendHome(); break;
      case "move": this.trip.move(m.spot); break;
      case "wake": if (m.why === "hover" || m.why === "click") this.host.wake(m.why); break;
      case "screens": void this.refresh().then(() => this.trip.screensChanged()); break;
      case "menu":
        if (m.item === "open") this.host.open();
        else if (m.item === "home") this.trip.sendHome();
        else if (m.item === "small" || m.item === "medium" || m.item === "large") {
          State.settings.cat = withDesktopSize(State.settings.cat, m.item);
          void Bridge.saveSettings(State.settings);
          this.sendLook(true);
        }
        break;
    }
  }

  // ── Dragging the big cat out of the notch ───────────────────────────────────────────────────────────────────────────────────────────

  /** Only the cat at home can be taken out by hand (on GNOME too: the window comes up where the system puts it). */
  get canCarry(): boolean { return this.trip.phase === "home"; }

  /** The drag began: the cat leaves the notch's spot and is carried by the pointer (the window follows it). */
  carryStart(): void {
    this.carrying = true;
    State.desktopNotchEmpty = true;
    State.notify();
    this.sendLook(true);
    this.send({ k: "carry", on: true });
  }

  /** The pointer is at (x, y) in the island window. */
  carry(x: number, y: number): void {
    const s = islandToSpot(this.world, x, y);
    void Bridge.desktopPlace(s.x, s.y);
  }

  /** The button was released at (x, y): the cat is put down on the desktop, or back in the notch when it was dropped on it (or the drop was refused). */
  carryEnd(x: number, y: number, onNotch: boolean): void {
    this.carrying = false;
    this.send({ k: "carry", on: false });
    const r = onNotch ? null : this.trip.dragOut(islandToSpot(this.world, x, y));
    if (r && r.act !== null) return;
    this.send({ k: "hide" });
    State.desktopNotchEmpty = false;
    State.notify();
  }
}

EOF
```

```bash
mkdir -p windows/src/desktop
cat > windows/src/desktop/body.ts <<'EOF'
// The desktop cat's window, the body (sub-project H): it draws the big cat (cat/desktopdraw.ts) as the island's page, the brain (island/desktop.ts), says it looks, runs the flight
// (cat/desktopflight.ts) and the drag, and answers with clicks, moves and "flight done". It runs the frame rate the rule gives (`desktopFps`) with one timer and nothing else: a cat that
// cannot be seen runs nothing. Pointer events only arrive over the cat's body, because Rust lets the mouse through everywhere else (src-tauri/src/desktop.rs).

import { CheckMenuItem, Menu, MenuItem, Submenu } from "@tauri-apps/api/menu";
import { Bridge, onEvent } from "../core/bridge";
import type { Settings } from "../core/state";
import { defaultWorld } from "../cat/desktopview";
import type { DesktopWorld } from "../cat/desktopview";
import type { StateName } from "../cat/base";
import { cleanCatBlock } from "../cat/display";
import { DESKTOP_FPS, DESKTOP_SIZE_IDS, desktopSizeOf } from "../cat/desktop";
import type { DesktopSizeId, Spot } from "../cat/desktop";
import { DesktopFlight } from "../cat/desktopflight";
import { FrameGovernor } from "../cat/desktopgov";
import type { BodyLook, BodyMsg, BrainMsg } from "../cat/desktoptrip";
import { desktopWindowLayout, kittenSide } from "../cat/desktopview";
import type { DesktopWindowLayout } from "../cat/desktopview";
import { BotEngine, catCfg } from "../cat/engine";
import { Gestures } from "../cat/gestures";
import type { Gesture } from "../cat/gestures";
import { applyCatSettings } from "../cat/settings";

const SIZE_LABELS: Record<DesktopSizeId, string> = { small: "Small", medium: "Medium", large: "Large" };
/** The happy reaction to a click, and how long the cat is "in an emote" for the frame rate (ms): the longest emote of `cat-core.js`'s `EMOUTH` (love and proud), 1.8 s. */
const HAPPY_MS = 1800;

export class DesktopBody {
  private readonly root: HTMLElement;
  private readonly cv = document.createElement("canvas");
  private readonly engine = new BotEngine();
  private world: DesktopWorld = defaultWorld();
  private look: BodyLook | null = null;
  private lay: DesktopWindowLayout = desktopWindowLayout("medium", "shrimpy", 0, 1);
  private sentLayout = "";
  /** The head's centre on the desktop, in points. */
  private spot: Spot | null = null;
  private visible = false;
  private carrying = false;
  private dragging = false;
  private flight: DesktopFlight | null = null;
  private emoteUntil = 0;
  private shownState = "";
  private readonly gov: FrameGovernor;
  private readonly gest: Gestures;

  constructor(root: HTMLElement) {
    this.root = root;
    this.gov = new FrameGovernor(
      { now: () => performance.now(), raf: (cb) => requestAnimationFrame(cb), caf: (id) => cancelAnimationFrame(id), set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id) },
      (dt) => this.frame(dt),
    );
    this.gest = new Gestures({ set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id), emit: (g) => this.gesture(g) });
  }

  async start(): Promise<void> {
    this.root.append(this.cv);
    const boot = await Bridge.boot();
    if (boot) this.applySettings(boot.settings);
    this.world = (await Bridge.desktopScreens()) ?? this.world;
    await onEvent<BodyMsg>("desktop-msg", (m) => this.handle(m));
    await onEvent<Settings>("settings-changed", (s) => this.applySettings(s));
    document.addEventListener("visibilitychange", () => this.rate());
    this.cv.addEventListener("pointerdown", (e) => { if (e.button === 0) { this.cv.setPointerCapture(e.pointerId); this.gest.press(e.clientX, e.clientY); } });
    this.cv.addEventListener("pointermove", (e) => { if (e.buttons & 1) this.gest.move(e.clientX, e.clientY); });
    this.cv.addEventListener("pointerup", (e) => { if (e.button === 0) this.gest.release(); });
    this.cv.addEventListener("pointercancel", () => this.gest.cancel());
    this.cv.addEventListener("contextmenu", (e) => { e.preventDefault(); this.gest.cancel(); void this.menu(); });
    this.say({ k: "ready" });
  }

  private say(m: BrainMsg): void { void Bridge.desktopRelay("island", m); }

  private applySettings(s: Settings): void { applyCatSettings(catCfg, cleanCatBlock(s.cat)); }

  // ── From the brain ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  /** A message from the brain (public so the dev server can feed one by hand). */
  handle(m: BodyMsg): void {
    if (!m || typeof m !== "object") return;
    const now = performance.now();
    switch (m.k) {
      case "look":
        this.look = m.look;
        this.relayout();
        break;
      case "carry":
        this.carrying = m.on;
        if (m.on) this.visible = true;
        if (m.on) void Bridge.desktopShow(true);
        break;
      case "emote": this.emote(m.name); break;
      case "show":
        this.flight = null;
        this.present(m.spot);
        break;
      case "fly": {
        this.present(m.from);
        this.flight = new DesktopFlight(m.from, m.to, now + Math.max(0, m.delayMs ?? 0), m.dir);
        if (m.emote) this.emote(m.emote);
        break;
      }
      case "turn": this.flight?.turn(now); break;
      case "notchEnd": this.flight?.setNotch(m.spot); break;
      case "desktopEnd":
        if (this.flight) this.flight.setDesktop(m.spot);
        else this.present(m.spot);
        break;
      case "hide":
        this.flight = null;
        this.visible = false;
        void Bridge.desktopShow(false);
        break;
    }
    this.rate();
    this.gov.poke();
  }

  /** Shows the cat with its head at `spot`: the window is sized, put there and shown. */
  private present(spot: Spot): void {
    this.spot = spot;
    this.visible = true;
    this.relayout(true);
    void Bridge.desktopPlace(spot.x, spot.y);
    void Bridge.desktopShow(true);
  }

  private emote(name: string): void {
    this.engine.emote(name);
    this.emoteUntil = performance.now() + HAPPY_MS;
  }

  /** The window's size and what takes the mouse follow the cat's size, its coat and its kittens; Rust is told only when they change. */
  private relayout(force = false): void {
    const look = this.look;
    if (!look) return;
    const screen = this.spot ? this.world.screens.find((s) => this.spot!.x >= s.frame.x && this.spot!.x < s.frame.x + s.frame.w && this.spot!.y >= s.frame.y && this.spot!.y < s.frame.y + s.frame.h) : null;
    const side = screen && this.spot ? kittenSide(this.spot.x, screen.visible.x, screen.visible.w) : 1;
    this.lay = desktopWindowLayout(look.size, look.coat, 0, side);
    const L = this.lay, key = JSON.stringify([L.w, L.h, L.headX, L.headY, L.shapes]);
    if (!force && key === this.sentLayout) return;
    this.sentLayout = key;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.cv.width = Math.round(L.w * dpr); this.cv.height = Math.round(L.h * dpr);
    this.cv.style.width = `${L.w}px`; this.cv.style.height = `${L.h}px`;
    void Bridge.desktopLayout(L.w, L.h, L.headX, L.headY, L.shapes.map((c) => ({ x: c.x, y: c.y, r: c.r })));
  }

  // ── The frame ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  private frame(dt: number): void {
    const now = performance.now(), look = this.look;
    if (this.flight) {
      const p = this.flight.at(now);
      this.spot = { x: p.x, y: p.y };
      if (this.world.positioned) void Bridge.desktopPlace(p.x, p.y);
      // Where the system places windows itself (GNOME) the window cannot fly: the flight is a hop inside the cat's own window.
      else this.cv.style.transform = `translateY(${-Math.sin(Math.PI * this.flight.progress(now)) * this.lay.D * 0.3}px)`;
      if (p.done) { this.flight = null; this.cv.style.transform = ""; this.say({ k: "flightDone" }); }
    }
    if (!look) return;
    if (this.shownState !== look.state) { this.shownState = look.state; this.engine.setState(look.state as StateName); }
    const dpr = Math.min(2, window.devicePixelRatio || 1), ctx = this.cv.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, this.lay.w, this.lay.h);
    // The cat itself: its coat, its state and the room for its particles. (Its badge, collar and kittens come with "what it shows".)
    this.engine.setCoat(look.coat);
    this.engine.particleOverhang = this.lay.overhang;
    this.engine.update(dt);
    ctx.save();
    ctx.translate(this.lay.canvasX, 0);
    this.engine.draw(ctx, this.lay.canvasW, this.lay.canvasH);
    ctx.restore();
    this.rate();
  }

  /** The frame rate the cat needs now: 60 while it flies, is carried or plays an emote, else 5 (the rule that knows more comes with the frame-rate task); 0 while it is not shown. */
  private rate(): void {
    const moving = this.flight !== null || this.carrying || this.dragging || performance.now() < this.emoteUntil;
    this.gov.setRate(this.visible || this.carrying ? (moving ? DESKTOP_FPS.motion : DESKTOP_FPS.idle) : 0);
  }

  // ── The pointer ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  /** Points per CSS px of this window. */
  private get k(): number { return (window.devicePixelRatio || 1) / (this.world.scale || 1); }

  private gesture(g: Gesture): void {
    switch (g.k) {
      case "click":
        this.emote("happy");
        this.say({ k: "wake", why: "click" });
        this.say({ k: "click" });
        break;
      case "double": this.say({ k: "doubleClick" }); break;
      case "dragStart":
        // Where the system moves windows itself (GNOME) it drags the window; the spot is still saved, and GNOME may not keep it.
        if (!this.world.positioned) { void Bridge.desktopNativeDrag(); this.gest.cancel(); break; }
        this.dragging = true;
        void Bridge.desktopDrag(true);
        break;
      case "drag":
        if (this.spot && this.dragging) {
          this.spot = { x: this.spot.x + g.dx * this.k, y: this.spot.y + g.dy * this.k };
          void Bridge.desktopPlace(this.spot.x, this.spot.y);
        }
        break;
      case "dragEnd":
        if (this.dragging) {
          this.dragging = false;
          void Bridge.desktopDrag(false);
          if (this.spot) this.say({ k: "move", spot: this.spot });
        }
        break;
    }
    this.rate();
  }

  /** The right-click menu: Open the notch, Send home and Size. A native menu, so it needs no room in the window. */
  private async menu(): Promise<void> {
    const size = desktopSizeOf(this.look?.size);
    const sizes = await Promise.all(DESKTOP_SIZE_IDS.map((id) => CheckMenuItem.new({ id, text: SIZE_LABELS[id], checked: size === id, action: () => this.say({ k: "menu", item: id }) })));
    const open = await MenuItem.new({ id: "open", text: "Open the notch", action: () => this.say({ k: "menu", item: "open" }) });
    const home = await MenuItem.new({ id: "home", text: "Send home", action: () => this.say({ k: "menu", item: "home" }) });
    const menu = await Menu.new({ items: [open, home, await Submenu.new({ text: "Size", items: sizes })] });
    await menu.popup();
  }
}
EOF
```

- [ ] **Step 4: Edit State, the island, `main.ts` and the older pin**

`island.ts`'s press handling moves into `pressed`, `carryMove` and `carryUp`, the big cat is drawn only while it is in the notch, and `two-cats.test.mjs` pins the moved line.

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/core/state.ts", [
('''  /** Music is playing: the cat in the compact island bobs to it''', '''  /** The big cat's spot in the notch is empty: the desktop cat has left it (sub-project H). Set by the trip (island/desktop.ts); while it is true the island draws no big cat, glow or kittens for it. */
  desktopNotchEmpty = false;

  /** Music is playing: the cat in the compact island bobs to it'''),
])

edit("windows/src/island/island.ts", [
('''import { createMiniBot, pruneMiniBots, syncMiniBotStates, tickKittenStrips, tickMiniBots } from "../cat/minibots";
''', '''import { createMiniBot, pruneMiniBots, syncMiniBotStates, tickKittenStrips, tickMiniBots } from "../cat/minibots";
import { PressDrag } from "../cat/pressdrag";
import { notchCatLocal } from "../core/notchspot";
'''),
('''import { releaseChatApprovals, resurfaceChatApproval } from "./hooks";
''', '''import { releaseChatApprovals, resurfaceChatApproval } from "./hooks";
import type { DesktopBrain, DesktopHost } from "./desktop";
'''),
('''  private greeting = new Greeting();
''', '''  private greeting = new Greeting();
  /** The desktop cat's brain (island/desktop.ts), attached by main.ts once the screens are known. */
  private desktop: DesktopBrain | null = null;
  /** A press on the big cat of the notch: a click when the button comes up, or the start of a drag out of the notch (sub-project H). */
  private press = new PressDrag();
  private pressAction: (() => void) | null = null;
'''),
('''    this.greeting.onComplete = () => this.fsm.greetComplete();
''', '''    this.greeting.onComplete = () => { this.fsm.greetComplete(); this.desktop?.afterGreeting(); };
'''),
('''    this.islandEl.addEventListener("mousedown", (e) => {
      Sound.resume();
      this.sleep.event("click");
      State.lastActivity = performance.now();
      if (State.mode !== "expanded") {
        this.fsm.click();
        return;
      }
      // Two cats: a click on the second cat focuses its agent, as a click on a pill does.
      const second = this.cast.second;
      const hit = catClickTarget(e.clientX, e.clientY, this.botCircle(), second?.pill ? this.bot2Circle() : null);
      if (hit === 2 && second?.pill) {
        State.setFocus(second.pill);
        Sound.play("blip");
        return;
      }
      if (hit === 1) {
        this.cancelBotHover();
        this.engine.slap();
      }
    });
''', '''    this.islandEl.addEventListener("mousedown", (e) => {
      Sound.resume();
      this.sleep.event("click");
      State.lastActivity = performance.now();
      // The big cat can be dragged out of the notch (sub-project H): a press on it is a click or a drag, decided when the button comes up.
      const x = e.clientX, y = e.clientY;
      if (this.desktop?.canCarry && !State.desktopNotchEmpty && State.mode !== "hidden" && !this.greetingShown() && !this.uploadActive && this.isBotHit(x, y)) {
        this.press.press(x, y);
        this.pressAction = () => this.pressed(x, y);
        return;
      }
      this.pressed(x, y);
    });
    window.addEventListener("mousemove", (e) => this.carryMove(e.clientX, e.clientY));
    window.addEventListener("mouseup", (e) => this.carryUp(e.clientX, e.clientY));
'''),
('''  /**
   * Takes the cursor from the page's own mouse events instead of Rust's poll.''', '''  /** What a press on the island does: a click on the compact island opens it; in the open island a press slaps the big cat or focuses the second cat's agent. */
  private pressed(x: number, y: number) {
    if (State.mode !== "expanded") {
      this.fsm.click();
      return;
    }
    // Two cats: a click on the second cat focuses its agent, as a click on a pill does.
    const second = this.cast.second;
    const hit = catClickTarget(x, y, this.botCircle(), second?.pill ? this.bot2Circle() : null);
    if (hit === 2 && second?.pill) {
      State.setFocus(second.pill);
      Sound.play("blip");
      return;
    }
    if (hit === 1) {
      this.cancelBotHover();
      this.engine.slap();
    }
  }

  /** The pointer moved with a press on the big cat: past 4 px it is a drag, and the cat is carried out of the notch by it (the window follows it, across the screen). */
  private carryMove(x: number, y: number) {
    const step = this.press.move(x, y);
    if (step === "start") this.desktop?.carryStart();
    if (step) this.desktop?.carry(x, y);
  }

  /** The button came up: a press that never moved far is the click it always was; the end of a drag puts the cat down (or back in the notch when it is dropped on it). */
  private carryUp(x: number, y: number) {
    const r = this.press.release(), act = this.pressAction;
    this.pressAction = null;
    if (r === "click") act?.();
    else if (r === "drop") {
      const rect = this.islandRect();
      this.desktop?.carryEnd(x, y, x >= rect.x - HIT_MARGIN && x <= rect.x + rect.w + HIT_MARGIN && y >= rect.y - HIT_MARGIN && y <= rect.y + rect.h + HIT_MARGIN);
    }
  }

  /** The desktop cat's brain (island/desktop.ts), made by main.ts once the screens are known. */
  attachDesktop(brain: DesktopBrain) { this.desktop = brain; }

  /** What the desktop cat needs of the island. A click on the desktop cat opens the island the way the tray's Open does. */
  desktopHost(): DesktopHost {
    return {
      open: () => this.alert(State.defaultView()),
      wake: (kind) => this.noteActivity(kind),
      notchLocal: () => notchCatLocal(State.mode, State.view, !!this.cast.second),
    };
  }

  /**
   * Takes the cursor from the page's own mouse events instead of Rust's poll.'''),
('''    this.botCanvas.style.opacity = visible ? "1" : "0";''', '''    // The desktop cat has left the big cat's spot (sub-project H): nothing of it is drawn in the notch, and cat 2 and the pills stay.
    this.botCanvas.style.opacity = visible && !State.desktopNotchEmpty ? "1" : "0";'''),
('''    if (State.mode === "expanded" && State.view !== "uploading" && !greetingActive && !this.uploadActive) {
      const d = p.diameter;''', '''    if (State.mode === "expanded" && State.view !== "uploading" && !greetingActive && !this.uploadActive && !State.desktopNotchEmpty) {
      const d = p.diameter;'''),
('''      this.drawBot(dt);
      if (this.pairShown) this.drawBot2(dt);''', '''      if (!State.desktopNotchEmpty) this.drawBot(dt);
      if (this.pairShown) this.drawBot2(dt);'''),
('''    const big = shown && cast.big.pill ? State.kittenView(cast.big.pill, now) : []''', '''    const big = shown && cast.big.pill && !State.desktopNotchEmpty ? State.kittenView(cast.big.pill, now) : []'''),
])

edit("windows/src/main.ts", [
('''import { Island } from "./island/island";
''', '''import { Island } from "./island/island";
import { DesktopBrain } from "./island/desktop";
'''),
('''  State.giveCoats();
  if (boot && !boot.cursorPoll) island.followPageCursor();
''', '''  State.giveCoats();
  // The desktop cat (sub-project H): this page runs its trip, and the desktop window's page draws it.
  const desktop = new DesktopBrain(island.desktopHost());
  island.attachDesktop(desktop);
  if (boot && !boot.cursorPoll) island.followPageCursor();
'''),
('''    island.applySettings();
    State.loadIntegrationTasks();
    void refreshConfigured();
  });
''', '''    island.applySettings();
    State.loadIntegrationTasks();
    void refreshConfigured();
    desktop.settingsChanged();
  });
'''),
('''  registerIntegrationHandlers(island);

  island.launch();''', '''  registerIntegrationHandlers(island);
  await desktop.start();

  island.launch();'''),
])

edit("windows/scripts/cat-tests/two-cats.test.mjs", [
('const hit = catClickTarget\\(e\\.clientX, e\\.clientY, this\\.botCircle\\(\\)', 'const hit = catClickTarget\\(x, y, this\\.botCircle\\(\\)'),
])
print("applied")
PYEOF
```

- [ ] **Step 5: Run the tests and the type check**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; node --experimental-strip-types --test scripts/cat-tests/desktop-island.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `# tests 6`, `# pass 6`, `# fail 0`, then `ℹ tests 330`, `ℹ pass 330`, `ℹ fail 0`.

- [ ] **Step 6: Prove the tests can bite**

Run:

```bash
cd windows
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/pressdrag.ts 'if (Math.hypot(x - this.from.x, y - this.from.y) < this.dragPx) return null;' 'if (Math.hypot(x - this.from.x, y - this.from.y) <= this.dragPx) return null;' scripts/cat-tests/desktop-island.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/island/island.ts 'visible && !State.desktopNotchEmpty ? "1" : "0"' 'visible ? "1" : "0"' scripts/cat-tests/desktop-island.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/island/island.ts 'if (!State.desktopNotchEmpty) this.drawBot(dt);' 'this.drawBot(dt);' scripts/cat-tests/desktop-island.test.mjs
cd ..
```

Expected: `# fail 1` for each.

- [ ] **Step 7: Exercise the body in the browser**

The body's page runs in the dev server with no Tauri (the bridge is a no-op): feed it the messages the island's page sends, in the order it sends them, and check that nothing throws and that the window follows the look.

Start the dev server, then:

```bash
cd .claude/checkpoints/h-tauri
playwright-cli -s=htauri-body open 'http://127.0.0.1:14611/desktop.html' > /dev/null 2>&1
playwright-cli -s=htauri-body eval "(() => { const b = window.__body, look = { coat: 'momo', state: 'idle', size: 'medium' }, a = { x: 480, y: 16 }, z = { x: 760, y: 420 }; b.handle({ k: 'look', look }); b.handle({ k: 'fly', from: a, to: z, dir: 'out' }); b.handle({ k: 'turn' }); b.handle({ k: 'notchEnd', spot: { x: 500, y: 40 } }); b.handle({ k: 'desktopEnd', spot: z }); b.handle({ k: 'emote', name: 'surprised' }); b.handle({ k: 'carry', on: true }); b.handle({ k: 'carry', on: false }); b.handle({ k: 'show', spot: z }); const c = document.querySelector('canvas'); return c.style.width.replace('px', '') + 'x' + c.style.height.replace('px', ''); })()" 2>&1 | grep -A1 "### Result" | tail -1
sleep 1
playwright-cli -s=htauri-body eval "(() => { window.__body.handle({ k: 'hide' }); window.__body.handle({ k: 'bogus' }); window.__body.handle(null); return 'done'; })()" 2>&1 | grep -A1 "### Result" | tail -1
playwright-cli -s=htauri-body console 2>&1 | grep '\[ERROR\]' | grep -vc favicon
playwright-cli -s=htauri-body close > /dev/null 2>&1
cd ../../..
```

Expected: `"108x151"` (Medium, no kittens), `"done"` and `0` (no console error besides the favicon's 404). Stop the server by its PID.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src/core/notchspot.ts windows/src/cat/pressdrag.ts windows/src/island/desktop.ts windows/src/desktop/body.ts windows/src/core/state.ts windows/src/island/island.ts windows/src/main.ts windows/scripts/cat-tests/two-cats.test.mjs windows/scripts/cat-tests/desktop-island.test.mjs
git commit -F - <<'MSG'
feat(desktop): dragging the cat out, its flight and sending it home

The island's page runs the trip and the desktop window's page draws it: a press on the big cat is a click or a drag out of the notch, the cat flies, is dragged, clicked and double-clicked, and the notch's big-cat spot is empty while it is out.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model and the trigger.

---

# Stage 4: alerts

### Task 6: Alerts

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Modify: `windows/src/core/state.ts`, `windows/src/island/desktop.ts`
- Test: `windows/scripts/cat-tests/desktop-alert.test.mjs`

**Interfaces:**
- Consumes: Task 5's brain (`changed()` runs at every `State.notify()`), Task 4's `DesktopTrip.alert` and `notchMoved`, the island's `SleepClock` rule (`blocked`).
- Produces: `State.attentionNeeded`: an approval or a question is waiting for the user, in the notch (`pendingApproval`), in a chat (`chatApprovals`) or on a pill (`approval` or `question`): the same rule as the nap's `blocked` (the cat never sleeps through one), now named once. The brain asks it at every change: the trip gets `alertOn` or `alertOff` only when the answer changed, and a flight in the air follows the notch spot when the island opens or shuts for the alert.

**What already works.** The machine, the surprised emote with its 450 ms before the flight, the turn-round, "an approval that lands while the cat is home takes nothing out", "a take-out during a pending alert waits for the next alert" and "a send-home during an alert ends the trip at home" are the contract's and are tested in Task 4 (`desktop-trip.test.mjs`); the body flies the `retract` flight and the `turn` (Task 5). The hook handlers set `pendingApproval` and then call `State.updateTask`, and the island's `decide` and the 110 s timeout clear it and call `State.updateTask` or `State.notify()` after: every change reaches `State.subscribe`, so the brain needs no new call in `hooks.ts` or `island.ts`.

- [ ] **Step 1: Write the test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-alert.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { State } from "../../src/core/state.ts";

// The alert (sub-project H, spec §1): an approval or a question that waits takes the cat to the notch, and clearing them sends it back.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const task = (id, state = "idle") => ({ id, name: id, color: "#8AB4F8", state, stepIndex: 0, steps: [], source: "agent", isIntegration: false });

test("State says when an approval or a question is waiting (a pending approval, a chat's, or a pill in that state), and the sleep timer's blocked rule is the same", () => {
  State.tasks = [task("integration_claude"), task("agent_gemini")]; State.pendingApproval = null;
  assert.equal(State.attentionNeeded, false);
  State.tasks[1].state = "question";
  assert.equal(State.attentionNeeded, true);
  State.tasks[1].state = "approval";
  assert.equal(State.attentionNeeded, true);
  State.tasks[1].state = "working";
  assert.equal(State.attentionNeeded, false);
  State.pendingApproval = { requestId: "r", sessionId: "s", tool: "Bash", command: "ls" };
  assert.equal(State.attentionNeeded, true);
  State.pendingApproval = null;
  State.chatApprovals.push({ requestId: "c1", sessionId: "s", tool: "Bash", command: "ls" });
  assert.equal(State.attentionNeeded, true, "a step Claude Code waits to take in a chat counts");
  State.chatApprovals.removeAll();
  assert.equal(State.attentionNeeded, false);
  assert.equal(State.desktopNotchEmpty, false, "the big cat's spot holds the cat until the trip says otherwise");
  assert.match(source("island/island.ts"), /blocked: \(\) => State\.pendingApproval !== null \|\| State\.chatApprovals\.length > 0 \|\| State\.tasks\.some\(\(t\) => t\.state === "approval" \|\| t\.state === "question"\),/, "the nap's rule is the one attentionNeeded copies");
});

test("the brain asks the trip about the alert at every change of State, and a flight in the air follows the notch spot", () => {
  const b = source("island/desktop.ts");
  assert.match(b, /this\.trip\.alert\(State\.attentionNeeded\);\s*this\.trip\.notchMoved\(\);/);
  assert.match(b, /State\.subscribe\(\(\) => this\.changed\(\)\);/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-alert.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..
```

Expected: `# tests 2`, `# pass 0`, `# fail 2` (`State.attentionNeeded` is not there, and the brain does not ask it).

- [ ] **Step 3: Write the getter and the brain's call**

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/core/state.ts", [
('''  get focusTask(): AgentTask | null {''', '''  /** An approval or a question is waiting for the user, in the notch or in a chat: the desktop cat flies to the notch for it (cat/desktoptrip.ts), and the cat never sleeps through it (island/sleep.ts). */
  get attentionNeeded(): boolean {
    return this.pendingApproval !== null || this.chatApprovals.length > 0 || this.tasks.some((t) => t.state === "approval" || t.state === "question");
  }

  get focusTask(): AgentTask | null {'''),
])
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

edit('windows/src/island/desktop.ts', [
('''  private changed(): void {
''', '''  private changed(): void {
    this.trip.alert(State.attentionNeeded);
    this.trip.notchMoved();
'''),
])
PYEOF
```

- [ ] **Step 4: Run the test, the type check and the whole suite**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; node --experimental-strip-types --test scripts/cat-tests/desktop-alert.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `# tests 2`, `# pass 2`, `# fail 0`, then `ℹ tests 332`, `ℹ pass 332`, `ℹ fail 0`.

- [ ] **Step 5: Prove the tests can bite**

Run:

```bash
cd windows
python3 ../.claude/checkpoints/h-tauri/mut.py src/core/state.ts '|| t.state === "question"' '' scripts/cat-tests/desktop-alert.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/core/state.ts 'this.pendingApproval !== null || this.chatApprovals.length > 0 ||' 'this.pendingApproval !== null ||' scripts/cat-tests/desktop-alert.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/island/desktop.ts 'this.trip.notchMoved();' '' scripts/cat-tests/desktop-alert.test.mjs
cd ..
```

Expected: `# fail 1` for each.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src/core/state.ts windows/src/island/desktop.ts windows/scripts/cat-tests/desktop-alert.test.mjs
git commit -F - <<'MSG'
feat(desktop): an approval or a question takes the cat to the notch

State.attentionNeeded names the rule the nap already used (an approval or a question is waiting, in the notch, in a chat or on a pill); the brain tells the trip when it changes and when the notch spot moves.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model.

---

# Stage 5: what it shows

### Task 7: What it shows

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Create: `windows/src/cat/desktopdraw.ts`, `windows/src/cat/devdesktop.ts`
- Modify: `windows/src/desktop/body.ts`, `windows/src/island/desktop.ts`, `windows/src/cat/desktoptrip.ts`, `windows/src/cat/dev.ts`
- Test: `windows/scripts/cat-tests/desktop-draw.test.mjs`, `windows/scripts/cat-tests/desktop-look.test.mjs`

**Interfaces:**
- Consumes: Task 3's `desktopWindowLayout`; Task 1's `desktopKittenSlots`; the engine (`BotEngine`, `setCoat`, `collarColor`, `particleOverhang`, `badgeLeft`, `earRoom`, `setDancing`, `lookX`, `lookY`), `kittendraw.ts`'s `KittenPool` and `kittenCatState`, `kittens.ts`'s `kittenView`, `geometry.ts`'s `cursorLook`, `collar.ts`'s `bigCatCollar`, `dance.ts`'s `shouldDance`; the brain and the body of Task 5.
- Produces: `drawDesktopCat` (one frame: the cat at full detail, its badge, its collar, up to three kittens in its colour, "+N"); the whole `BodyLook` (coat, state, collar, kittens, pill, dancing, working, asleep, size, `now`); the body's cursor-watching (Rust's `desktop_cursor` where the system has one, the pointer over the cat where it has not, ahead when the cat sleeps), the hover that wakes a sleeping cat, and the kittens drawn in the brain's clock; the `?dev` page's Desktop cat panel with the mock desktop.

**What the cat shows.** The big cat's **coat** from the cast (`State.cast.big.cat`, so A cat for each agent follows the focus), its **state** (`State.effectiveState`, so an idle cat sleeps while the cats are asleep), the **badge** the engine draws for it at the upper right (never the notch's left side), the **collar** in the focused agent's colour in the style its coat wears (`bigCatCollar`, `catCfg.collars`), **its agent's kittens** (`State.kittens[pill]`, drawn in the brain's clock through the skew), **cursor-watching** (the eyes follow the cursor within the window's reach; a sleeping cat does not watch) and the **dance** (`shouldDance`; nothing sets `State.musicPlaying` on Windows and Linux yet). **Waking (spec §2):** a hover or a click wakes it, and in the Playful style it wakes with zoomies, because the body puts its engine in the state the island says (`sleeping` to `idle`), which is what starts them in the notch (the third pin of `desktop-look.test.mjs`). **Eyes:** the cat is far above Ø28, so it is drawn with the realistic eyes and never with the small coloured ones. **Sleep:** the island's `SleepClock` already puts the cats to sleep after ten quiet minutes and sweeps stale kittens then; a hover over the desktop cat is an "I was woken" event for it (`noteActivity("hover")`, at most every 2 s), and a click is one too.

- [ ] **Step 1: Write the tests**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-draw.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { BotEngine } from "../../src/cat/engine.ts";
import { drawDesktopCat } from "../../src/cat/desktopdraw.ts";
import { DESKTOP_SIZES } from "../../src/cat/desktop.ts";
import { desktopWindowLayout } from "../../src/cat/desktopview.ts";
import { KittenPool } from "../../src/cat/kittendraw.ts";
import { CAT_IDS, PRESETS } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const K = (id, state = "working", born = 0) => ({ id, type: "", session: null, state, born, last: born, until: state === "leaving" ? 600 : null });
const look = (o = {}) => ({ coat: "momo", collar: "#8AB4F8", kittens: [], lookX: 0, lookY: 0, dancing: false, pill: "integration_claude", ...o });
const engine = () => new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 });

test("the desktop cat is the big cat at full detail: one frame at every size and coat draws finite numbers, in the coat it is given, with the collar's colour", () => {
  for (const size of Object.keys(DESKTOP_SIZES)) for (const coat of CAT_IDS) {
    const ctx = fakeCanvas(), e = engine(), L = desktopWindowLayout(size, coat, 0, 1);
    drawDesktopCat(ctx, e, new KittenPool(), L, look({ coat, collar: "#22C55E" }), 1 / 60);
    assert.equal(e.p.name, coat, `${size} ${coat}`);
    assert.ok(ctx.calls.save >= 1 && ctx.calls.restore === ctx.calls.save, "balanced save and restore");
    assert.ok(Object.values(ctx.calls).reduce((n, c) => n + c, 0) > 100, "a cat was drawn");
  }
});

test("the engine is told what the desktop needs: the collar, no ear fit, the badge on the right, room for particles, and where to look", () => {
  const e = engine(), L = desktopWindowLayout("large", "shrimpy", 0, 1);
  e.earRoom = 5; e.badgeLeft = true;
  drawDesktopCat(fakeCanvas(), e, new KittenPool(), L, look({ coat: "shrimpy", collar: "#E879F9", lookX: 0.5, lookY: -0.5, dancing: true }), 1 / 60);
  assert.deepEqual([e.collarColor, e.earRoom, e.badgeLeft, e.particleOverhang, e.lookX, e.lookY, e.isDancing], ["#E879F9", null, false, L.overhang, 0.5, -0.5, true]);
  drawDesktopCat(fakeCanvas(), e, new KittenPool(), L, look({ coat: "nope", collar: null }), 1 / 60);
  assert.equal(e.collarColor, null);
  assert.equal(e.p.name, "shrimpy", "an unknown coat is Shrimpy");
});

test("up to three kittens are drawn beside the cat in its colour, then a +N, on the side the layout says; each is an engine of the cat's coat", () => {
  const list = [K("a", "approval", 3), K("b", "searching", 2), K("c", "working", 1), K("d", "leaving", 0), K("e", "working", 4)];
  for (const side of [1, -1]) {
    const pool = new KittenPool(), ctx = fakeCanvas(), L = desktopWindowLayout("medium", "momo", list.length, side);
    drawDesktopCat(ctx, engine(), pool, L, look({ kittens: list, collar: "#8AB4F8" }), 1 / 60);
    assert.equal(pool.size, 3, "three kittens are made");
    assert.deepEqual(ctx.seen.texts, ["+2"], `side ${side}`);
    const e = pool.get("desktop:integration_claude:a", "momo", "approval");
    assert.equal(e.collarColor, "#8AB4F8");
    assert.equal(e.p.base, "momo");
  }
  const none = fakeCanvas();
  drawDesktopCat(none, engine(), new KittenPool(), desktopWindowLayout("medium", "momo", 0, 1), look(), 1 / 60);
  assert.deepEqual(none.seen.texts, []);
});

test("a kitten engine nobody draws for 30 frames goes, and a cat with no kittens makes none", () => {
  const pool = new KittenPool(), L = desktopWindowLayout("medium", "momo", 1, 1);
  drawDesktopCat(fakeCanvas(), engine(), pool, L, look({ kittens: [K("a")] }), 0);
  assert.equal(pool.size, 1);
  for (let i = 0; i < 31; i++) drawDesktopCat(fakeCanvas(), engine(), pool, desktopWindowLayout("medium", "momo", 0, 1), look(), 0);
  assert.equal(pool.size, 0);
});
EOF
```

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-look.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// What the desktop cat shows (sub-project H, spec §2): the seams between the island's page and the desktop page, pinned by source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("the brain tells the body what the cat looks like: the cast's coat, the effective state, the collar in the focused agent's colour, its agent's kittens, whether it works, sleeps or dances, and its size", () => {
  const b = source("island/desktop.ts");
  assert.match(b, /coat: cast\.big\.cat, state, collar: bigCatCollar\(state, State\.focusTask\?\.color\), kittens: pill \? State\.kittens\[pill\] \?\? \[\] : \[\], pill,/);
  assert.match(b, /dancing: shouldDance\(State\.musicPlaying, state, "compact"\), working: BUSY\.has\(state\), asleep: State\.asleep, size: desktopSizeOf\(State\.settings\.cat\.desktop\.size\), now: performance\.now\(\),/);
  const body = source("desktop/body.ts");
  assert.match(body, /const kittens = kittenView\(look\.kittens, now \+ this\.skew\)/, "the kittens' times are in the brain's clock");
  assert.match(body, /drawDesktopCat\(ctx, this\.engine, this\.pool, this\.lay, \{ coat: look\.coat, collar: look\.collar, kittens, lookX: gaze\.x, lookY: gaze\.y, dancing: look\.dancing, pill: look\.pill \}, dt\);/);
  assert.match(body, /gaze = c && at && !look\.asleep \?/, "a sleeping cat does not watch the cursor");
  assert.match(body, /if \(now - this\.lastWake > WAKE_EVERY_MS\) \{ this\.lastWake = now; this\.say\(\{ k: "wake", why: "hover" \}\); \}/);
  assert.match(body, /if \(this\.cursorAsked \|\| this\.flight \|\| this\.carrying \|\| this\.dragging \|\| this\.look\?\.asleep\) return;/, "the cursor is asked for one question at a time, and not while the cat is busy");
  assert.match(body, /if \(!this\.globalCursor\) this\.cursor = null;/, "where the system gives no cursor (Wayland) the cat looks ahead unless the pointer is over it");
});

test("waking a sleeping desktop cat: the body puts the engine in the state the island says, so the Playful style's waking zoomies play as they do in the notch, and a hover or a click tells the island", () => {
  const body = source("desktop/body.ts");
  assert.match(body, /this\.engine\.setState\(look\.state as StateName\)/);
  assert.match(source("cat/engine.ts"), /zoomies/);
  assert.match(body, /this\.say\(\{ k: "wake", why: "hover" \}\)/);
  assert.match(body, /this\.say\(\{ k: "wake", why: "click" \}\)/);
});

test("the ?dev page has the desktop panel: the mock desktop at three sizes", () => {
  const dev = source("cat/devdesktop.ts");
  assert.ok(dev.includes('"desktop-mock"'));
  assert.match(source("cat/dev.ts"), /mountDesktopDev\(root, wrap, ticks\);/);
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-draw.test.mjs scripts/cat-tests/desktop-look.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (tests|pass|fail)" | cut -c1-90 | sort -u; cd ..
```

Expected: a line with `ERR_MODULE_NOT_FOUND` (no `desktopdraw.ts` yet), `# tests 4`, `# pass 0` and `# fail 4` (the draw file fails to load; all three look pins fail).

- [ ] **Step 3: Write the drawing and the panel**

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/desktopdraw.ts <<'EOF'
// Drawing the desktop cat (sub-project H, spec §2): the big cat at full detail by the same renderer as the notch's, its collar, its state badge (the engine draws it) and up to three
// of its agent's kittens at the lower right (or left), then "+N". No small eyes: the cat is far above Ø28. The window's layout (desktopview.ts) says where everything goes; this
// draws one frame into a canvas the caller has cleared and given the DPR transform. Imports engine.ts and kittendraw.ts, so the plain-Node checks (npm run check:cat) can load it.

import type { BotEngine } from "./engine.ts";
import { desktopKittenSlots } from "./desktop.ts";
import type { DesktopWindowLayout } from "./desktopview.ts";
import { KittenPool, kittenCatState } from "./kittendraw.ts";
import type { Kitten } from "./kittens.ts";

/** What the desktop cat shows: the coat the big cat wears now, its collar colour (null for none), its agent's kittens as `kittenView` returned them, where it looks (-1..1) and whether it dances. */
export interface DesktopLook {
  coat: string; collar: string | null; kittens: readonly Kitten[]; lookX: number; lookY: number; dancing: boolean;
  /** The agent pill the kittens belong to (their engines are kept per pill). */
  pill: string;
}

/** A small rounded label ("+3") `size` px high, its left edge at `x`, centred on `y`. */
function label(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number) {
  const sz = Math.max(8, size);
  ctx.font = `700 ${sz}px system-ui, "Segoe UI", sans-serif`;
  const w = ctx.measureText(text).width + sz * 0.6;
  ctx.fillStyle = "#2a2c31"; ctx.beginPath(); ctx.roundRect(x, y - sz * 0.65, w, sz * 1.3, sz * 0.65); ctx.fill();
  ctx.fillStyle = "#cfd0d4"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(text, x + w / 2, y + 0.5);
}

/** Draws one frame, `dt` seconds after the last: updates and draws the cat, then its kittens. Returns nothing; the caller owns the canvas. */
export function drawDesktopCat(ctx: CanvasRenderingContext2D, engine: BotEngine, pool: KittenPool, lay: DesktopWindowLayout, look: DesktopLook, dt: number): void {
  engine.setCoat(look.coat);
  engine.collarColor = look.collar;
  engine.particleOverhang = lay.overhang;
  engine.badgeLeft = false;
  engine.earRoom = null;
  engine.setDancing(look.dancing);
  engine.lookX = look.lookX;
  engine.lookY = look.lookY;
  engine.update(dt);
  ctx.save();
  ctx.translate(lay.canvasX, 0);
  engine.draw(ctx, lay.canvasW, lay.canvasH);
  ctx.restore();

  const slots = desktopKittenSlots(look.kittens, lay.side), D = lay.D;
  for (const q of slots.shown) {
    const e = pool.get(`desktop:${look.pill}:${q.id}`, look.coat, kittenCatState(q.state)), w = (q.d * D) / 0.6;
    e.collarColor = look.collar;
    e.update(dt);
    ctx.save();
    ctx.translate(lay.headX + q.x * D - w / 2, lay.headY + q.y * D - w / 2);
    e.draw(ctx, w, w);
    ctx.restore();
  }
  if (slots.moreAt) {
    ctx.save();
    const size = slots.moreAt.size * D, x = lay.headX + slots.moreAt.x * D;
    label(ctx, `+${slots.more}`, lay.side === 1 ? x : x - size * 2.2, lay.headY + slots.moreAt.y * D, size);
    ctx.restore();
  }
  pool.endFrame();
}
EOF
```

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/devdesktop.ts <<'EOF'
// The `?dev` page's "Desktop cat" panel (sub-project H): the desktop cat at Small, Medium and Large on a mock desktop (with its badge, collar and kittens), the flight as a strip of
// frames (out, and out then turned round by an alert that clears), and the frame-time bench with the CPU each frame rate would cost. Open http://127.0.0.1:1420/?dev with `npx vite`
// (no Tauri window needed). Only the dev server serves it: main.ts loads dev.ts behind `import.meta.env.DEV`, so a release build does not contain it.

import { DESKTOP_SIZES } from "./desktop.ts";
import type { DesktopSizeId } from "./desktop.ts";
import { drawDesktopCat } from "./desktopdraw.ts";
import type { DesktopLook } from "./desktopdraw.ts";
import { desktopWindowLayout, kittenSide } from "./desktopview.ts";
import { BotEngine } from "./engine.ts";
import { KittenPool } from "./kittendraw.ts";
import type { Kitten } from "./kittens.ts";
import { PRESETS } from "./presets.ts";
import type { StateName } from "./base.ts";
import { AGENT_PILL_COLORS } from "../core/pills.ts";
import { THEME } from "../theme.generated.ts";

const FONT = "system-ui,-apple-system,'Segoe UI',sans-serif";
const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;
const COLLAR = AGENT_PILL_COLORS.agent_gemini;
const DESK_W = 900, DESK_H = 330;

function fit(cv: HTMLCanvasElement, w: number, h: number): CanvasRenderingContext2D {
  const dpr = Math.min(2, devicePixelRatio || 1);
  if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
  cv.style.width = `${w}px`; cv.style.height = `${h}px`;
  const c = cv.getContext("2d")!;
  c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, w, h);
  return c;
}
function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}
function section(title: string, note: string): HTMLElement {
  const s = document.createElement("section");
  s.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  s.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">${title}</h2><p style="color:${B.dim};margin:0 0 12px;font-size:13px">${note}</p>`;
  return s;
}
function row(label: string): HTMLElement {
  const r = document.createElement("div");
  r.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:8px";
  const h = document.createElement("span");
  h.style.cssText = `font-size:12px;color:${B.dim};width:72px;flex:none`; h.textContent = label;
  r.append(h);
  return r;
}
function choice<T>(label: string, items: readonly (readonly [T, string])[], get: () => T, set: (v: T) => void): HTMLElement {
  const r = row(label), bs: [HTMLButtonElement, T][] = [];
  const sync = () => bs.forEach(([b, v]) => { b.style.borderColor = get() === v ? B.accent : B.line; b.style.color = get() === v ? B.accent : B.ink; });
  for (const [v, l] of items) { const b = button(l, () => { set(v); sync(); }); bs.push([b, v]); r.append(b); }
  sync();
  return r;
}

/** Kittens for the mock: `n` of them, the first waiting on an approval, the second searching, one leaving when there are four or more. */
const kittensOf = (n: number): Kitten[] => Array.from({ length: n }, (_, i) => ({ id: `k${i}`, type: "Explore", session: null, state: i === 0 ? "approval" : i === 1 ? "searching" : i === 3 ? "leaving" : "working", born: i, last: i, until: null }));

/** The wallpaper, a menu bar, three fake windows and the notch's strip, behind the cats. */
function drawDesktop(c: CanvasRenderingContext2D) {
  const g = c.createLinearGradient(0, 0, DESK_W, DESK_H);
  g.addColorStop(0, "#3b4a6b"); g.addColorStop(1, "#7a5c8a");
  c.fillStyle = g; c.fillRect(0, 0, DESK_W, DESK_H);
  c.fillStyle = "rgba(0,0,0,.35)"; c.fillRect(0, 0, DESK_W, 24);
  for (const [x, y, w, h] of [[40, 50, 330, 200], [330, 90, 300, 190], [600, 60, 270, 230]]) {
    c.fillStyle = "#e8e9ec"; c.beginPath(); c.roundRect(x, y, w, h, 8); c.fill();
    c.fillStyle = "#c9cbd1"; c.beginPath(); c.roundRect(x, y, w, 22, [8, 8, 0, 0]); c.fill();
    c.fillStyle = "#b6b8bf"; for (let i = 0; i < 5; i++) c.fillRect(x + 14, y + 40 + i * 24, w * (0.45 + 0.08 * ((i * 3) % 5)), 8);
  }
  c.fillStyle = "#000"; c.beginPath(); c.roundRect(DESK_W / 2 - 144, 0, 288, 32, [0, 0, 14, 14]); c.fill();
  c.fillStyle = "rgba(0,0,0,.45)"; c.fillRect(0, DESK_H - 30, DESK_W, 30);
}

/** Puts the "Desktop cat" panel into the `?dev` page before `before`, and registers its live drawing in `ticks`. */
export function mountDesktopDev(root: HTMLElement, before: HTMLElement, ticks: (() => void)[]): void {
  // ── The cats on a mock desktop ──
  const box = section("Desktop cat", "The big cat on the desktop at Small (Ø48), Medium (Ø64, the default) and Large (Ø96): its badge, its collar and its agent's kittens (up to three, then +N); in the right half of the screen the kittens stand on the left. The black strip at the top is the notch's.");
  const st = { coat: "shrimpy", state: null as StateName | null, kittens: 5, collar: true };
  const spots: { id: DesktopSizeId; x: number; y: number }[] = [{ id: "small", x: 140, y: 190 }, { id: "medium", x: 400, y: 190 }, { id: "large", x: 740, y: 180 }];
  const own: Record<DesktopSizeId, StateName> = { small: "approval", medium: "working", large: "idle" };
  const cats = spots.map((s) => ({ ...s, e: new BotEngine(PRESETS[st.coat], { state: own[s.id] }), pool: new KittenPool(), shown: own[s.id] as StateName }));
  const cv = document.createElement("canvas");
  cv.id = "desktop-mock"; cv.setAttribute("aria-label", "The desktop cat at three sizes on a mock desktop"); cv.style.cssText = "display:block;border-radius:12px;margin-top:12px;max-width:100%";
  box.append(
    choice("Coat", (["shrimpy", "momo", "ginger", "midnight", "snow"] as const).map((c) => [c, PRESETS[c].label] as const), () => st.coat, (v) => { st.coat = v; }),
    choice("State", ([null, "idle", "working", "searching", "approval", "question", "error", "finished", "sleeping"] as const).map((s) => [s, s ?? "each its own"] as const), () => st.state, (v) => { st.state = v; }),
    choice("Kittens", ([0, 1, 3, 5, 8] as const).map((n) => [n, String(n)] as const), () => st.kittens, (v) => { st.kittens = v; }),
    choice("Collar", ([[true, "on"], [false, "off"]] as const), () => st.collar, (v) => { st.collar = v; }),
    cv,
  );
  let last = performance.now();
  ticks.push(() => {
    const now = performance.now(), dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const c = fit(cv, DESK_W, DESK_H);
    drawDesktop(c);
    const t = now / 1000;
    for (const cat of cats) {
      const want = st.state ?? own[cat.id];
      if (cat.shown !== want) { cat.e.setState(want); cat.shown = want; }
      const side = kittenSide(cat.x, 0, DESK_W), lay = desktopWindowLayout(cat.id, st.coat, st.kittens, side);
      const look: DesktopLook = { coat: st.coat, collar: st.collar ? COLLAR : null, kittens: kittensOf(st.kittens), lookX: Math.sin(t * 0.7), lookY: Math.sin(t * 0.5) * 0.3, dancing: false, pill: "dev" };
      c.save(); c.translate(cat.x - lay.headX, cat.y - lay.headY);
      c.strokeStyle = "rgba(255,255,255,.35)"; c.setLineDash([4, 3]); c.strokeRect(0, 0, lay.w, lay.h); c.setLineDash([]);
      drawDesktopCat(c, cat.e, cat.pool, lay, look, dt);
      c.restore();
      c.fillStyle = "rgba(255,255,255,.9)"; c.font = `600 12px ${FONT}`; c.textAlign = "center"; c.fillText(`${cat.id} Ø${DESKTOP_SIZES[cat.id]}`, cat.x, cat.y + lay.D / 2 + 46);
    }
  });
  root.insertBefore(box, before);
}
EOF
```

- [ ] **Step 4: The body, the brain, the trip's look and the `?dev` page**

The body's frame now draws through `drawDesktopCat`, asks for the cursor, wakes on a hover and shows the kittens; the brain sends the whole look; `BodyLook` is the whole look; `dev.ts` mounts the panel.

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/desktop/body.ts", [
('''    this.cv.addEventListener("pointercancel", () => this.gest.cancel());
''', '''    this.cv.addEventListener("pointercancel", () => this.gest.cancel());
    this.cv.addEventListener("pointerleave", () => { if (!this.globalCursor) this.cursor = null; });
'''),
('''this.cv.addEventListener("pointermove", (e) => { if (e.buttons & 1) this.gest.move(e.clientX, e.clientY); });''', '''this.cv.addEventListener("pointermove", (e) => { this.over(e); if (e.buttons & 1) this.gest.move(e.clientX, e.clientY); });'''),
('''  private gesture(g: Gesture): void {''', '''  /** The pointer is over the cat: where the system gives an app no cursor (Wayland), this is the only cursor it gets; and a hover wakes a sleeping cat. */
  private over(e: PointerEvent): void {
    if (this.spot) this.cursor = { x: this.spot.x + (e.clientX - this.lay.headX) * this.k, y: this.spot.y + (e.clientY - this.lay.headY) * this.k };
    const now = performance.now();
    if (now - this.lastWake > WAKE_EVERY_MS) { this.lastWake = now; this.say({ k: "wake", why: "hover" }); }
    this.rate();
  }

  private gesture(g: Gesture): void {'''),
('''  /** The frame rate the cat needs now: 60 while it flies''', '''  /** Where the cursor is, in points, from Rust (Windows). One question at a time, and none while the cat is in the air or carried: it looks at what it is doing. */
  private askCursor(): void {
    if (this.cursorAsked || this.flight || this.carrying || this.dragging || this.look?.asleep) return;
    this.cursorAsked = true;
    void Bridge.desktopCursor().then((p) => { this.cursorAsked = false; if (p) { this.cursor = p; this.globalCursor = true; } });
  }

  /** The frame rate the cat needs now: 60 while it flies'''),
('''    if (!look) return;
    if (this.shownState !== look.state) { this.shownState = look.state; this.engine.setState(look.state as StateName); }
    const dpr = Math.min(2, window.devicePixelRatio || 1), ctx = this.cv.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, this.lay.w, this.lay.h);
    // The cat itself: its coat, its state and the room for its particles. (Its badge, collar and kittens come with "what it shows".)
    this.engine.setCoat(look.coat);
    this.engine.particleOverhang = this.lay.overhang;
    this.engine.update(dt);
    ctx.save();
    ctx.translate(this.lay.canvasX, 0);
    this.engine.draw(ctx, this.lay.canvasW, this.lay.canvasH);
    ctx.restore();
    this.rate();
''', '''    if (!look) return;
    this.askCursor();
    const kittens = kittenView(look.kittens, now + this.skew);
    if (this.shownState !== look.state) { this.shownState = look.state; this.engine.setState(look.state as StateName); }
    const c = this.cursor, at = this.spot, gaze = c && at && !look.asleep ? { x: cursorLook(c.x - at.x, 0).x, y: cursorLook(0, c.y - at.y).y } : { x: 0, y: 0 };
    const dpr = Math.min(2, window.devicePixelRatio || 1), ctx = this.cv.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, this.lay.w, this.lay.h);
    drawDesktopCat(ctx, this.engine, this.pool, this.lay, { coat: look.coat, collar: look.collar, kittens, lookX: gaze.x, lookY: gaze.y, dancing: look.dancing, pill: look.pill }, dt);
    this.rate();
'''),
('''desktopWindowLayout(look.size, look.coat, 0, side)''', '''desktopWindowLayout(look.size, look.coat, look.kittens.length, side)'''),
('''        this.look = m.look;
        this.relayout();
''', '''        this.look = m.look;
        this.skew = m.look.now - now;
        this.relayout();
'''),
('''  private shownState = "";
''', '''  private shownState = "";
  private lastWake = -1e9;
'''),
('''  private flight: DesktopFlight | null = null;
  private emoteUntil = 0;
''', '''  private flight: DesktopFlight | null = null;
  private cursor: Spot | null = null;
  private cursorAsked = false;
  /** The system gave an app a cursor at least once (Windows, X11): without one (Wayland) the cat looks ahead unless the pointer is over it. */
  private globalCursor = false;
  private emoteUntil = 0;
'''),
('''  private look: BodyLook | null = null;
''', '''  private look: BodyLook | null = null;
  /** The brain's clock minus ours: its kittens' times are in its clock. */
  private skew = 0;
'''),
('''  private readonly engine = new BotEngine();
''', '''  private readonly engine = new BotEngine();
  private readonly pool = new KittenPool();
'''),
('''const HAPPY_MS = 1800;
''', '''const HAPPY_MS = 1800;
/** A hover tells the island's page at most this often (ms): it only needs to wake the cat. */
const WAKE_EVERY_MS = 2000;
'''),
('''import type { Gesture } from "../cat/gestures";
''', '''import type { Gesture } from "../cat/gestures";
import { KittenPool } from "../cat/kittendraw";
import { kittenView } from "../cat/kittens";
'''),
('''import { BotEngine, catCfg } from "../cat/engine";
''', '''import { BotEngine, catCfg } from "../cat/engine";
import { cursorLook } from "../cat/geometry";
'''),
('''import type { DesktopSizeId, Spot } from "../cat/desktop";
''', '''import type { DesktopSizeId, Spot } from "../cat/desktop";
import { drawDesktopCat } from "../cat/desktopdraw";
'''),
])
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

edit('windows/src/island/desktop.ts', [
('''  /** What the desktop cat looks like: the big cat as the cast makes it. */
  private look(): BodyLook {
    return { coat: State.cast.big.cat, state: State.effectiveState, size: desktopSizeOf(State.settings.cat.desktop.size) };
  }
''', '''  /** What the desktop cat looks like: the big cat as the cast and the focused agent make it. */
  private look(): BodyLook {
    const cast = State.cast, pill = cast.big.pill ?? "", state = State.effectiveState as StateName;
    return {
      coat: cast.big.cat, state, collar: bigCatCollar(state, State.focusTask?.color), kittens: pill ? State.kittens[pill] ?? [] : [], pill,
      dancing: shouldDance(State.musicPlaying, state, "compact"), working: BUSY.has(state), asleep: State.asleep, size: desktopSizeOf(State.settings.cat.desktop.size), now: performance.now(),
    };
  }
'''),
('''import { State } from "../core/state";
''', '''import { State } from "../core/state";
import { BUSY } from "../cat/base";
import type { StateName } from "../cat/base";
import { bigCatCollar } from "../cat/collar";
import { shouldDance } from "../cat/dance";
'''),
])
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

edit('windows/src/cat/desktoptrip.ts', [
('''/** What the desktop cat looks like now, as the island's page (the brain) knows it: the body draws it. */
export interface BodyLook { coat: string; state: string; size: DesktopSizeId }
''', '''/** What the desktop cat looks like now, as the island's page (the brain) knows it: the body draws it. `now` is the brain's clock (`performance.now()`), the one the kittens' times are in. */
export interface BodyLook {
  coat: string; state: string; collar: string | null; kittens: Kitten[]; pill: string; dancing: boolean; working: boolean; asleep: boolean; size: DesktopSizeId; now: number;
}
'''),
('''import type { DesktopEvent, DesktopPhase, DesktopSettings, DesktopSizeId, DesktopStep, Screen, Spot } from "./desktop.ts";
''', '''import type { DesktopEvent, DesktopPhase, DesktopSettings, DesktopSizeId, DesktopStep, Screen, Spot } from "./desktop.ts";
import type { Kitten } from "./kittens.ts";
'''),
])
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

edit("windows/src/cat/dev.ts", [
('import { KittenPool, drawKittens } from "./kittendraw.ts";', 'import { KittenPool, drawKittens } from "./kittendraw.ts";\nimport { mountDesktopDev } from "./devdesktop.ts";'),
('''  ticks.push(() => greeting.draw(fit(gCv, 640, 150)));
''', '''  ticks.push(() => greeting.draw(fit(gCv, 640, 150)));
  // ── Sub-project H: the desktop cat, its flight and its frame time ──
  mountDesktopDev(root, wrap, ticks);
'''),
])
PYEOF
```

- [ ] **Step 5: Run the tests and the type check**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; node --experimental-strip-types --test scripts/cat-tests/desktop-draw.test.mjs scripts/cat-tests/desktop-look.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `# tests 7`, `# pass 7`, `# fail 0`, then `ℹ tests 339`, `ℹ pass 339`, `ℹ fail 0`.

- [ ] **Step 6: Prove the tests can bite**

Run:

```bash
cd windows
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktopdraw.ts 'engine.collarColor = look.collar;' 'engine.collarColor = null;' scripts/cat-tests/desktop-draw.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/cat/desktopdraw.ts 'engine.earRoom = null;' 'engine.earRoom = 5;' scripts/cat-tests/desktop-draw.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/desktop/body.ts 'gaze = c && at && !look.asleep ?' 'gaze = c && at ?' scripts/cat-tests/desktop-look.test.mjs
python3 ../.claude/checkpoints/h-tauri/mut.py src/desktop/body.ts 'if (this.cursorAsked || this.flight || this.carrying || this.dragging || this.look?.asleep) return;' 'if (this.cursorAsked) return;' scripts/cat-tests/desktop-look.test.mjs
cd ..
```

Expected: `# fail 1` for each.

- [ ] **Step 7: Look at it (the pictures of Checkpoint 1)**

Start the dev server (see "Starting and stopping the dev server"). The `?dev` page's Desktop cat panel draws the real code (the layout, `drawDesktopCat`, the engine) on a mock desktop; the body's own page draws the same through the real body.

```bash
cd .claude/checkpoints/h-tauri
playwright-cli -s=htauri-mock open 'http://127.0.0.1:14611/?dev' > /dev/null 2>&1
playwright-cli -s=htauri-mock resize 1000 900 > /dev/null 2>&1
playwright-cli -s=htauri-mock eval "(() => { document.querySelector('#desktop-mock').scrollIntoView({block:'start'}); return document.querySelector('#desktop-mock').width > 0 ? 'mock' : 'empty'; })()" 2>&1 | grep -A1 "### Result" | tail -1
sleep 1.5
playwright-cli -s=htauri-mock screenshot --filename="$(pwd)/mock-desktop.png" > /dev/null 2>&1
playwright-cli -s=htauri-mock eval "(() => { const box = document.querySelector('#desktop-mock').parentElement, pick = (t) => [...box.querySelectorAll('button')].find((b) => b.textContent === t).click(); pick('Momo'); pick('sleeping'); pick('0'); pick('off'); return 'set'; })()" 2>&1 | grep -A1 "### Result" | tail -1
sleep 2
playwright-cli -s=htauri-mock screenshot --filename="$(pwd)/mock-desktop-asleep.png" > /dev/null 2>&1
playwright-cli -s=htauri-mock console 2>&1 | grep '\[ERROR\]' | grep -vc favicon
playwright-cli -s=htauri-mock close > /dev/null 2>&1
playwright-cli -s=htauri-win open 'http://127.0.0.1:14611/desktop.html' > /dev/null 2>&1
playwright-cli -s=htauri-win eval "(() => { const k = (id, s) => ({ id, type: '', session: null, state: s, born: 0, last: 0, until: null }); const b = window.__body; b.handle({ k: 'look', look: { coat: 'momo', state: 'working', collar: '#8AB4F8', kittens: [k('a','approval'), k('b','searching'), k('c','working'), k('d','working'), k('e','working')], pill: 'integration_claude', dancing: false, working: true, asleep: false, size: 'medium', now: performance.now() } }); b.handle({ k: 'show', spot: { x: 300, y: 300 } }); const c = document.querySelector('canvas'); return c.style.width.replace('px', '') + 'x' + c.style.height.replace('px', ''); })()" 2>&1 | grep -A1 "### Result" | tail -1
sleep 1
playwright-cli -s=htauri-win screenshot --filename="$(pwd)/window-medium-kittens.png" > /dev/null 2>&1
playwright-cli -s=htauri-win console 2>&1 | grep '\[ERROR\]' | grep -vc favicon
playwright-cli -s=htauri-win close > /dev/null 2>&1
cd ../../..
```

Expected: `"mock"`, `"set"`, `0` (no console error besides the favicon's 404), `"198x151"` (Medium with three kittens and a "+N": the window grew on the kittens' side only), `0` (no console error besides the favicon's 404), and three pictures in `.claude/checkpoints/h-tauri/`. Look at them and say what you saw: **`mock-desktop.png`**: three cats on the mock desktop, Small (a state badge), Medium (the "working" dots) and Large (right half of the screen: its kittens stand on its **left**), each with its collar in the agent's blue, up to three kittens and "+2", the dashed rectangles being the windows (no larger than the cat, its badge and its kittens); **`mock-desktop-asleep.png`**: Momo asleep with no kittens and no collar; **`window-medium-kittens.png`**: the body's own page, a Medium Momo with its badge, collar and three kittens and "+2", the last kitten's state badge inside the canvas. Stop the server by its PID. Keep the pictures and `settings-switch.png` of Task 2 for Checkpoint 1.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src/cat/desktopdraw.ts windows/src/cat/devdesktop.ts windows/src/desktop/body.ts windows/src/island/desktop.ts windows/src/cat/desktoptrip.ts windows/src/cat/dev.ts windows/scripts/cat-tests/desktop-draw.test.mjs windows/scripts/cat-tests/desktop-look.test.mjs
git commit -F - <<'MSG'
feat(desktop): what the desktop cat shows

The desktop cat shows the big cat's coat, state and badge, its collar, its agent's kittens, where the cursor is, and sleeps and wakes; the ?dev page has a mock desktop with it at the three sizes.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model.

---

## Checkpoint 1: the owner looks at the cat on a desktop mock and at the Settings switch

Tasks 1 to 7 are done. The session **stops here**, copies the pictures into `.claude/checkpoints/h-tauri/` (they are there already) and sends the owner their paths with this list. **Nothing of Task 8 starts before the owner's reply.**

1. **Pictures:** `mock-desktop.png` (S, M and L on a mock desktop), `mock-desktop-asleep.png`, `window-medium-kittens.png` (the body's own page) and `settings-switch.png` (the Settings → Cat switch, off).
2. **What to look at:** the three sizes (Ø48, Ø64, Ø96) at full detail with the realistic eyes; the state badge at the upper right; the collar; up to three kittens at the lower right, "+N" after them, and on the right half of the screen on the cat's left; the window (the dashed rectangle) no larger than the cat, its badge and its kittens; the switch under the Display picker, built from the window's own row and switch.
3. **Questions:** is the badge's and the kittens' place right at Small? Are the kittens too small at Small (Ø14 each)? Anything to move before the flight is drawn?
4. **What no picture shows** (owed to the owner's real-build checks): the window itself, click-through, dragging, the flight.

---

# Stage 6: the frame-rate rule and the bench

### Task 8: The frame-rate rule and the bench

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Modify: `windows/src/desktop/body.ts`
- Replace: `windows/src/cat/devdesktop.ts` (the mock desktop of Task 7 gets the alert flight and the bench)
- Test: `windows/scripts/cat-tests/desktop-rate.test.mjs`

**Interfaces:**
- Consumes: Task 1's `desktopFps`, `DESKTOP_FPS`; Task 4's `FrameGovernor`; Task 7's body (cursor, kittens, look) and `drawDesktopCat`.
- Produces: the body keeps to the contract's rate with every input it knows: the phase (a flight, on the desktop, not shown), `hidden` (`document.visibilityState`, which the system sets for a locked screen and a covered window, and Rust sets by hiding the window under a fullscreen app), dragging or carried, an emote in progress, a kitten arriving or leaving (600 ms), the dance, asleep, working and the cursor's distance in points (left out when the cursor is unknown, as on Wayland); the `?dev` page's **alert flight as a strip of frames** (the cat gives the surprised emote, flies to its spot in the notch and, once you have answered, back out) and its **bench**: the median time of one frame at each size with no kittens and with three, and what each frame rate would cost (`ms * fps / 10` = percent of one core).

**The rule, in the body.** (Task 8b adds `away`, a locked session or a display that is off, as another way to be hidden.) The governor is told the rate after every message, every frame, every gesture and every hover: 60 while it moves, 20 while the agent works or the cursor is near, 5 idle, 0.5 asleep (one still frame every 2 s), 0 when it cannot be seen. At 0 the governor holds no timer and no frame callback (Task 4's tests), and the brain's `desktop_show(false)` hides the window; Rust's poll thread is parked while the cat is home (Task 3). So a cat that cannot be seen costs nothing in either page.

- [ ] **Step 1: Write the test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-rate.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The frame-rate rule and the bench (sub-project H, spec §3), pinned by source where they need a browser.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("the body keeps to the contract's frame rate: desktopFps with every flag it knows, the cursor's distance, a kitten arriving or leaving as motion, and a hidden page at 0", () => {
  const body = source("desktop/body.ts");
  assert.match(body, /this\.gov\.setRate\(desktopFps\(\{/);
  assert.match(body, /phase: this\.flight \? "flyingOut" : this\.visible \|\| this\.carrying \? "onDesktop" : "home", hidden: document\.visibilityState === "hidden"( \|\| this\.away)?, dragging: this\.carrying \|\| this\.dragging,/);
  assert.match(body, /emote: now < this\.emoteUntil, kittenMotion: now < this\.kittenMotionUntil, dance: look\?\.dancing === true, asleep: look\?\.asleep === true, working: look\?\.working === true,/);
  assert.match(body, /\.\.\.\(c && at \? \{ cursorDist: Math\.hypot\(c\.x - at\.x, c\.y - at\.y\) \} : \{\}\),/, "no cursor, no distance");
  assert.match(body, /if \(sig !== this\.kittenSig\) \{ this\.kittenSig = sig; this\.kittenMotionUntil = now \+ KITTEN_MOTION_MS; \}/);
  assert.doesNotMatch(body, /DESKTOP_FPS/, "the rule is the contract's, not a copy");
});

test("the ?dev page has the alert flight as a strip of frames and the bench with the CPU of each rate", () => {
  const dev = source("cat/devdesktop.ts");
  for (const id of ["desktop-mock", "desktop-flight", "desktop-bench", "desktop-bench-run"]) assert.ok(dev.includes(`"${id}"`), id);
  assert.match(dev, /ms \* fps\) \/ 10/, "ms per frame times frames a second over ten is a percent of one core");
  assert.match(dev, /DESKTOP_FPS\.asleep, DESKTOP_FPS\.idle|pct\(DESKTOP_FPS\.asleep\)/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-rate.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..
```

Expected: `# tests 2`, `# pass 0`, `# fail 2` (the body still uses Task 5's simple rate, and the panel has no flight or bench).

- [ ] **Step 3: Use the contract's rate in the body, and complete the panel**

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/desktop/body.ts", [
('''  /** The frame rate the cat needs now: 60 while it flies, is carried or plays an emote, else 5 (the rule that knows more comes with the frame-rate task); 0 while it is not shown. */
  private rate(): void {
    const moving = this.flight !== null || this.carrying || this.dragging || performance.now() < this.emoteUntil;
    this.gov.setRate(this.visible || this.carrying ? (moving ? DESKTOP_FPS.motion : DESKTOP_FPS.idle) : 0);
  }
''', '''  /** The frame rate the cat needs now (cat/desktop.ts `desktopFps`): the governor keeps to it, and 0 stops every timer. */
  private rate(): void {
    const now = performance.now(), look = this.look, c = this.cursor, at = this.spot;
    this.gov.setRate(desktopFps({
      phase: this.flight ? "flyingOut" : this.visible || this.carrying ? "onDesktop" : "home", hidden: document.visibilityState === "hidden", dragging: this.carrying || this.dragging,
      emote: now < this.emoteUntil, kittenMotion: now < this.kittenMotionUntil, dance: look?.dancing === true, asleep: look?.asleep === true, working: look?.working === true,
      ...(c && at ? { cursorDist: Math.hypot(c.x - at.x, c.y - at.y) } : {}),
    }));
  }
'''),
('''    const kittens = kittenView(look.kittens, now + this.skew);
''', '''    const kittens = kittenView(look.kittens, now + this.skew), sig = kittens.map((k) => `${k.id}${k.state === "leaving" ? "!" : ""}`).join();
    if (sig !== this.kittenSig) { this.kittenSig = sig; this.kittenMotionUntil = now + KITTEN_MOTION_MS; }
'''),
('''  private emoteUntil = 0;
''', '''  private emoteUntil = 0;
  private kittenMotionUntil = 0;
  private kittenSig = "";
'''),
('''const HAPPY_MS = 1800;
''', '''const HAPPY_MS = 1800;
/** A kitten counts as motion for this long (ms) after any change to the kitten list, an arrival or a leave: `KITTEN_LEAVE_MS`, 0.6 s. */
const KITTEN_MOTION_MS = 600;
'''),
('''import { DESKTOP_FPS, DESKTOP_SIZE_IDS, desktopSizeOf } from "../cat/desktop";''', '''import { DESKTOP_SIZE_IDS, desktopFps, desktopSizeOf } from "../cat/desktop";'''),
])
PYEOF
```

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/devdesktop.ts <<'EOF'
// The `?dev` page's "Desktop cat" panel (sub-project H): the desktop cat at Small, Medium and Large on a mock desktop (with its badge, collar and kittens), the flight as a strip of
// frames (out, and out then turned round by an alert that clears), and the frame-time bench with the CPU each frame rate would cost. Open http://127.0.0.1:1420/?dev with `npx vite`
// (no Tauri window needed). Only the dev server serves it: main.ts loads dev.ts behind `import.meta.env.DEV`, so a release build does not contain it.

import { DESKTOP_FPS, DESKTOP_SIZES, desktopFlightAt } from "./desktop.ts";
import type { DesktopSizeId } from "./desktop.ts";
import { drawDesktopCat } from "./desktopdraw.ts";
import type { DesktopLook } from "./desktopdraw.ts";
import { desktopWindowLayout, kittenSide } from "./desktopview.ts";
import { BotEngine } from "./engine.ts";
import { KittenPool } from "./kittendraw.ts";
import type { Kitten } from "./kittens.ts";
import { PRESETS } from "./presets.ts";
import type { StateName } from "./base.ts";
import { AGENT_PILL_COLORS } from "../core/pills.ts";
import { THEME } from "../theme.generated.ts";

const FONT = "system-ui,-apple-system,'Segoe UI',sans-serif";
const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;
const COLLAR = AGENT_PILL_COLORS.agent_gemini;
const DESK_W = 900, DESK_H = 330;

function fit(cv: HTMLCanvasElement, w: number, h: number): CanvasRenderingContext2D {
  const dpr = Math.min(2, devicePixelRatio || 1);
  if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
  cv.style.width = `${w}px`; cv.style.height = `${h}px`;
  const c = cv.getContext("2d")!;
  c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, w, h);
  return c;
}
function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}
function section(title: string, note: string): HTMLElement {
  const s = document.createElement("section");
  s.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  s.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">${title}</h2><p style="color:${B.dim};margin:0 0 12px;font-size:13px">${note}</p>`;
  return s;
}
function row(label: string): HTMLElement {
  const r = document.createElement("div");
  r.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:8px";
  const h = document.createElement("span");
  h.style.cssText = `font-size:12px;color:${B.dim};width:72px;flex:none`; h.textContent = label;
  r.append(h);
  return r;
}
function choice<T>(label: string, items: readonly (readonly [T, string])[], get: () => T, set: (v: T) => void): HTMLElement {
  const r = row(label), bs: [HTMLButtonElement, T][] = [];
  const sync = () => bs.forEach(([b, v]) => { b.style.borderColor = get() === v ? B.accent : B.line; b.style.color = get() === v ? B.accent : B.ink; });
  for (const [v, l] of items) { const b = button(l, () => { set(v); sync(); }); bs.push([b, v]); r.append(b); }
  sync();
  return r;
}

/** Kittens for the mock: `n` of them, the first waiting on an approval, the second searching, one leaving when there are four or more. */
const kittensOf = (n: number): Kitten[] => Array.from({ length: n }, (_, i) => ({ id: `k${i}`, type: "Explore", session: null, state: i === 0 ? "approval" : i === 1 ? "searching" : i === 3 ? "leaving" : "working", born: i, last: i, until: null }));

/** The wallpaper, a menu bar, three fake windows and the notch's strip, behind the cats. */
function drawDesktop(c: CanvasRenderingContext2D) {
  const g = c.createLinearGradient(0, 0, DESK_W, DESK_H);
  g.addColorStop(0, "#3b4a6b"); g.addColorStop(1, "#7a5c8a");
  c.fillStyle = g; c.fillRect(0, 0, DESK_W, DESK_H);
  c.fillStyle = "rgba(0,0,0,.35)"; c.fillRect(0, 0, DESK_W, 24);
  for (const [x, y, w, h] of [[40, 50, 330, 200], [330, 90, 300, 190], [600, 60, 270, 230]]) {
    c.fillStyle = "#e8e9ec"; c.beginPath(); c.roundRect(x, y, w, h, 8); c.fill();
    c.fillStyle = "#c9cbd1"; c.beginPath(); c.roundRect(x, y, w, 22, [8, 8, 0, 0]); c.fill();
    c.fillStyle = "#b6b8bf"; for (let i = 0; i < 5; i++) c.fillRect(x + 14, y + 40 + i * 24, w * (0.45 + 0.08 * ((i * 3) % 5)), 8);
  }
  c.fillStyle = "#000"; c.beginPath(); c.roundRect(DESK_W / 2 - 144, 0, 288, 32, [0, 0, 14, 14]); c.fill();
  c.fillStyle = "rgba(0,0,0,.45)"; c.fillRect(0, DESK_H - 30, DESK_W, 30);
}

/** Puts the "Desktop cat" panel into the `?dev` page before `before`, and registers its live drawing in `ticks`. */
export function mountDesktopDev(root: HTMLElement, before: HTMLElement, ticks: (() => void)[]): void {
  // ── The cats on a mock desktop ──
  const box = section("Desktop cat", "The big cat on the desktop at Small (Ø48), Medium (Ø64, the default) and Large (Ø96): its badge, its collar and its agent's kittens (up to three, then +N); in the right half of the screen the kittens stand on the left. The black strip at the top is the notch's.");
  const st = { coat: "shrimpy", state: null as StateName | null, kittens: 5, collar: true };
  const spots: { id: DesktopSizeId; x: number; y: number }[] = [{ id: "small", x: 140, y: 190 }, { id: "medium", x: 400, y: 190 }, { id: "large", x: 740, y: 180 }];
  const own: Record<DesktopSizeId, StateName> = { small: "approval", medium: "working", large: "idle" };
  const cats = spots.map((s) => ({ ...s, e: new BotEngine(PRESETS[st.coat], { state: own[s.id] }), pool: new KittenPool(), shown: own[s.id] as StateName }));
  const cv = document.createElement("canvas");
  cv.id = "desktop-mock"; cv.setAttribute("aria-label", "The desktop cat at three sizes on a mock desktop"); cv.style.cssText = "display:block;border-radius:12px;margin-top:12px;max-width:100%";
  box.append(
    choice("Coat", (["shrimpy", "momo", "ginger", "midnight", "snow"] as const).map((c) => [c, PRESETS[c].label] as const), () => st.coat, (v) => { st.coat = v; }),
    choice("State", ([null, "idle", "working", "searching", "approval", "question", "error", "finished", "sleeping"] as const).map((s) => [s, s ?? "each its own"] as const), () => st.state, (v) => { st.state = v; }),
    choice("Kittens", ([0, 1, 3, 5, 8] as const).map((n) => [n, String(n)] as const), () => st.kittens, (v) => { st.kittens = v; }),
    choice("Collar", ([[true, "on"], [false, "off"]] as const), () => st.collar, (v) => { st.collar = v; }),
    cv,
  );
  let last = performance.now();
  ticks.push(() => {
    const now = performance.now(), dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const c = fit(cv, DESK_W, DESK_H);
    drawDesktop(c);
    const t = now / 1000;
    for (const cat of cats) {
      const want = st.state ?? own[cat.id];
      if (cat.shown !== want) { cat.e.setState(want); cat.shown = want; }
      const side = kittenSide(cat.x, 0, DESK_W), lay = desktopWindowLayout(cat.id, st.coat, st.kittens, side);
      const look: DesktopLook = { coat: st.coat, collar: st.collar ? COLLAR : null, kittens: kittensOf(st.kittens), lookX: Math.sin(t * 0.7), lookY: Math.sin(t * 0.5) * 0.3, dancing: false, pill: "dev" };
      c.save(); c.translate(cat.x - lay.headX, cat.y - lay.headY);
      c.strokeStyle = "rgba(255,255,255,.35)"; c.setLineDash([4, 3]); c.strokeRect(0, 0, lay.w, lay.h); c.setLineDash([]);
      drawDesktopCat(c, cat.e, cat.pool, lay, look, dt);
      c.restore();
      c.fillStyle = "rgba(255,255,255,.9)"; c.font = `600 12px ${FONT}`; c.textAlign = "center"; c.fillText(`${cat.id} Ø${DESKTOP_SIZES[cat.id]}`, cat.x, cat.y + lay.D / 2 + 46);
    }
  });
  root.insertBefore(box, before);

  // ── The alert flight as a strip of frames ──
  const fbox = section("The alert flight", "An approval arrives while the cat is on the desktop: it gives the surprised emote, flies to its spot in the notch (0.6 s: an arc, eased in and out, at full size the whole way), waits while you answer, then flies back out to where it was. Eight frames, each the mock desktop at half size; the times are from the approval.");
  const fcv = document.createElement("canvas");
  fcv.id = "desktop-flight"; fcv.setAttribute("aria-label", "The alert flight as a strip of eight frames"); fcv.style.cssText = "display:block;border-radius:12px;margin-top:12px;max-width:100%";
  fbox.append(fcv);
  const PW = DESK_W / 2, PH = DESK_H / 2;
  function drawFlights() {
    const c = fit(fcv, DESK_W, PH * 4), desk = { x: 640, y: 215 }, notch = { x: DESK_W / 2, y: 16 };
    let clock = 0;
    const lay = desktopWindowLayout("medium", st.coat, 0, 1);
    const cat = new BotEngine(PRESETS[st.coat], { quiet: true, now: () => clock, rand: () => 0.5 }), pool = new KittenPool();
    const step = (ms: number) => { for (let n = 0; n < Math.round(ms / 16.7); n++) { clock += 16.7; cat.update(1 / 60); } };
    const small = new BotEngine(PRESETS[st.coat], { mini: true, quiet: true, now: () => clock, rand: () => 0.5 });
    const frames: { label: string; at: { x: number; y: number } | null; emote?: boolean }[] = [
      { label: "0 ms: on the desktop", at: desk },
      { label: "300 ms: an approval arrives, surprised", at: desk, emote: true },
      { label: "750 ms: flying in, t 0.25", at: desktopFlightAt(desk, notch, 0.25) },
      { label: "900 ms: t 0.5", at: desktopFlightAt(desk, notch, 0.5) },
      { label: "1050 ms: t 0.75", at: desktopFlightAt(desk, notch, 0.75) },
      { label: "1350 ms: in the notch while you answer", at: null },
      { label: "answered + 300 ms: flying out, t 0.5", at: desktopFlightAt(notch, desk, 0.5) },
      { label: "answered + 600 ms: back on the desktop", at: desk },
    ];
    frames.forEach((f, i) => {
      const x0 = (i % 2) * PW, y0 = Math.floor(i / 2) * PH;
      c.save(); c.beginPath(); c.rect(x0, y0, PW, PH); c.clip(); c.translate(x0, y0); c.scale(0.5, 0.5);
      drawDesktop(c);
      if (f.at) {
        if (f.emote) cat.emote("surprised");
        step(f.emote ? 250 : 16);
        c.save(); c.translate(f.at.x - lay.headX, f.at.y - lay.headY);
        drawDesktopCat(c, cat, pool, lay, { coat: st.coat, collar: COLLAR, kittens: [], lookX: 0.2, lookY: 0.1, dancing: false, pill: "dev" }, 0);
        c.restore();
      } else {
        step(16); small.update(1 / 60);
        const w = 20 / 0.6;
        c.save(); c.translate(notch.x - w / 2, notch.y - w / 2); small.draw(c, w, w); c.restore();
      }
      c.restore();
      c.fillStyle = "rgba(0,0,0,.55)"; c.fillRect(x0 + 6, y0 + PH - 24, PW - 12, 18);
      c.fillStyle = "#fff"; c.font = `600 11px ${FONT}`; c.textAlign = "left"; c.fillText(f.label, x0 + 12, y0 + PH - 11);
      c.strokeStyle = "rgba(255,255,255,.25)"; c.strokeRect(x0 + 0.5, y0 + 0.5, PW - 1, PH - 1);
    });
  }
  drawFlights();
  fbox.append(button("Redraw with the chosen coat", drawFlights));
  root.insertBefore(fbox, before);

  // ── The bench ──
  const bbox = section("Frame time and CPU", `One frame of the desktop cat with no kittens and with three kittens at each size, drawn in this browser's software canvas (slower than the app's, so the numbers err on the high side), and what each frame rate would cost: ms per frame x frames per second / 10 = % of one core. Rates: asleep ${DESKTOP_FPS.asleep}, idle ${DESKTOP_FPS.idle}, working or the cursor near ${DESKTOP_FPS.active}, motion ${DESKTOP_FPS.motion}. Target: under 1 % idle without kittens and about 0 % asleep; 5 fps with three kittens is reported, not held.`);
  const note = document.createElement("pre");
  note.id = "desktop-bench"; note.style.cssText = `color:${B.ink};font-size:12px;margin:10px 0 0;white-space:pre-wrap`; note.textContent = "Press Measure.";
  const median = (a: number[]) => [...a].sort((x, y) => x - y)[a.length >> 1];
  const once = (id: DesktopSizeId, frames: number, kittens = 3): number => {
    const e = new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 }), pool = new KittenPool(), lay = desktopWindowLayout(id, "shrimpy", kittens, 1);
    const c = fit(document.createElement("canvas"), lay.w, lay.h), look: DesktopLook = { coat: "shrimpy", collar: COLLAR, kittens: kittensOf(kittens), lookX: 0.2, lookY: 0, dancing: false, pill: "bench" }, t0 = performance.now();
    for (let f = 0; f < frames; f++) drawDesktopCat(c, e, pool, lay, look, 1 / 60);
    return (performance.now() - t0) / frames;
  };
  const measure = () => {
    const lines = ["size   kittens  ms/frame   asleep   idle     working  motion   (% of one core)"];
    for (const id of ["small", "medium", "large"] as const) for (const n of [0, 3]) {
      once(id, 20, n);
      const ms = median([once(id, 60, n), once(id, 60, n), once(id, 60, n)]), pct = (fps: number) => ((ms * fps) / 10).toFixed(2).padStart(6);
      lines.push(`${id.padEnd(7)}${String(n).padStart(4)}${ms.toFixed(2).padStart(11)}   ${pct(DESKTOP_FPS.asleep)}   ${pct(DESKTOP_FPS.idle)}   ${pct(DESKTOP_FPS.active)}   ${pct(DESKTOP_FPS.motion)}`);
    }
    lines.push("", "The cursor check (about 10 Hz) and the fullscreen check (2 Hz) run in Rust while the cat is awake: their cost is the owner's number from Task Manager.");
    note.textContent = lines.join("\n");
  };
  const brow = row("Bench");
  const run = button("Measure the desktop cat", measure);
  run.id = "desktop-bench-run";
  brow.append(run);
  bbox.append(brow, note);
  root.insertBefore(bbox, before);
}
EOF
```

- [ ] **Step 4: Run the test, the type check and the whole suite**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; node --experimental-strip-types --test scripts/cat-tests/desktop-rate.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `# tests 2`, `# pass 2`, `# fail 0`, then `ℹ tests 341`, `ℹ pass 341`, `ℹ fail 0`.

- [ ] **Step 5: Prove the test can bite**

Run:

```bash
cd windows
python3 ../.claude/checkpoints/h-tauri/mut.py src/desktop/body.ts 'emote: now < this.emoteUntil, kittenMotion: now < this.kittenMotionUntil,' 'emote: now < this.emoteUntil,' scripts/cat-tests/desktop-rate.test.mjs
cd ..
```

Expected: `# fail 1`.

- [ ] **Step 6: The zero-frame check and the bench (the numbers of Checkpoint 2)**

Start the dev server. First, the body's page must schedule **nothing** once the cat is hidden: count every timer and frame callback it asks for while it is shown for 1.2 s, then for 1.5 s after a `hide`.

```bash
cd .claude/checkpoints/h-tauri
playwright-cli -s=htauri-zero open 'http://127.0.0.1:14611/desktop.html' > /dev/null 2>&1
playwright-cli -s=htauri-zero eval "(async () => { const b = window.__body; let n = 0; const raf = window.requestAnimationFrame.bind(window), st = window.setTimeout.bind(window); window.requestAnimationFrame = (cb) => { n++; return raf(cb); }; window.setTimeout = (fn, ms, ...a) => { n++; return st(fn, ms, ...a); }; b.handle({ k: 'look', look: { coat: 'momo', state: 'idle', collar: null, kittens: [], pill: '', dancing: false, working: false, asleep: false, size: 'medium', now: performance.now() } }); b.handle({ k: 'show', spot: { x: 300, y: 300 } }); await new Promise((r) => st(r, 1200)); const shown = n; n = 0; b.handle({ k: 'hide' }); await new Promise((r) => st(r, 1500)); const hidden = n; window.requestAnimationFrame = raf; window.setTimeout = st; return JSON.stringify({ shown, hidden }); })()" 2>&1 | grep -A1 "### Result" | tail -1
playwright-cli -s=htauri-zero console 2>&1 | grep '\[ERROR\]' | grep -vc favicon
playwright-cli -s=htauri-zero close > /dev/null 2>&1
cd ../../..
```

Expected: `hidden\":0}` in the result (the JSON is printed as a string, so its quotes carry a backslash), with `shown` between 4 and 9 (an idle cat draws 5 frames a second, one timer each), and then `0` (no console error besides the favicon's 404).

Then the bench and the alert flight on the `?dev` page:

```bash
cd .claude/checkpoints/h-tauri
playwright-cli -s=htauri-bench open 'http://127.0.0.1:14611/?dev' > /dev/null 2>&1
playwright-cli -s=htauri-bench resize 1000 900 > /dev/null 2>&1
playwright-cli -s=htauri-bench eval "(() => { document.querySelector('#desktop-bench-run').click(); const t = document.querySelector('#desktop-bench').textContent, rows = t.split('\n').slice(1, 7), col = (l, i) => l.trim().split(/\s+/)[i]; return JSON.stringify({ rows: rows.length, idleUnder1: rows.filter((l) => col(l, 1) === '0').every((l) => parseFloat(col(l, 4)) < 1), asleepUnder1: rows.every((l) => parseFloat(col(l, 3)) < 0.1), text: t }); })()" 2>&1 | grep -A1 "### Result" | tail -1 | tee bench.txt
playwright-cli -s=htauri-bench eval "(() => { document.querySelector('#desktop-flight').scrollIntoView({block:'start'}); return 'ok'; })()" 2>&1 | grep -A1 "### Result" | tail -1
sleep 1
playwright-cli -s=htauri-bench screenshot --filename="$(pwd)/alert-flight.png" > /dev/null 2>&1
playwright-cli -s=htauri-bench console 2>&1 | grep '\[ERROR\]' | grep -vc favicon
playwright-cli -s=htauri-bench close > /dev/null 2>&1
cd ../../..
```

Expected: `rows\":6`, `idleUnder1\":true`, `asleepUnder1\":true` (in the result, which also holds the table: for each size, one row with no kittens (idle held under 1 %) and one with three kittens (5 fps reported, not held): ms per frame, and the percent of one core at asleep, idle, working and motion; the numbers differ per machine: a headless software canvas is slower than the app's, so they err on the high side), `"ok"`, `0`, and `alert-flight.png`: eight frames, two columns by four, each the mock desktop at half size: on the desktop; an approval arrives and the cat is surprised; flying in at t 0.25, 0.5 and 0.75; in the notch while you answer (a small cat in the notch strip); flying out; back on the desktop. Say what you saw. Stop the server by its PID.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src/desktop/body.ts windows/src/cat/devdesktop.ts windows/scripts/cat-tests/desktop-rate.test.mjs
git commit -F - <<'MSG'
feat(desktop): the frame-rate rule, the bench and the alert flight strip

The desktop window's page keeps to the contract's frame rate (60 in motion, 20 working or with the cursor near, 5 idle, a still frame every 2 s asleep, nothing when it cannot be seen). The ?dev panel has the alert flight as a strip of frames and a bench of the cost of each rate.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model.

---

### Task 8b: Away and awake, and the system's double-click time

**Agent:** `nm-implementer-deep` (Sonnet 5.5, high). **Trigger 1:** platform APIs designed here, not copied: Windows session and display-power notifications (a message-only window on its own thread), logind's signals over D-Bus on Linux, a double-click time read from each system. Rulings 2, 8 and 9 of "Parity rulings" below. Owner's answer on polling (2026-10-12), which overrides spec §3's "nothing new polls" for Windows and Linux only: **light checks while the cat is out**, a cursor check at about 10 Hz and a fullscreen check at 2 Hz, **both only while the cat is on the desktop and awake**.

**Files:**
- Modify: `windows/src-tauri/Cargo.toml` (four features of the `windows` crate that is already there: `Win32_System_RemoteDesktop`, `Win32_System_Power`, `Win32_System_LibraryLoader`, `Win32_Graphics_Gdi`; no new package, and `Cargo.lock` must not change), `windows/src-tauri/src/desktop.rs`, `windows/src-tauri/src/lib.rs`, `windows/src-tauri/src/platform/windows.rs`, `windows/src-tauri/src/platform/linux.rs`, `windows/src/core/bridge.ts`, `windows/src/cat/desktoptrip.ts`, `windows/src/desktop/body.ts`
- Test: `windows/scripts/cat-tests/desktop-away.test.mjs`

**What it does.**
- **Away.** Rust tells the desktop page `{k: "away", on}` when the session locks or unlocks and when the display turns off or on (Windows: `WTSRegisterSessionNotification` and the console display-state power setting, received by a message-only window that blocks in `GetMessageW`, so nothing polls), and on Linux when logind signals `Lock`, `Unlock` or `PrepareForSleep` (over the system bus, through gio, which GTK already brings). Where neither is available the page's own `document.visibilityState` still does it. The page treats `away` as `hidden` in `desktopFps`, so the frame rate is 0 and nothing is scheduled.
- **Awake.** The page tells Rust whether the cat is awake (shown, not asleep, not away, page visible: `desktop_awake`). The 2 Hz screens and fullscreen check in the poll thread runs only while it is awake, or while a fullscreen app covers the cat (the check is what ends the covering, so it cannot stop then: a deviation from the ruling's "both stop at covered", reported). The click-through poll stays while the window is shown, at 10 Hz when the cursor is far and 16 ms near the cat, because a hover must be able to wake a sleeping cat. The page's cursor read (`desktop_cursor`) is held to 10 Hz and is not asked while the cat is asleep, away, in the air or carried.
- **Double-click time.** The page asks the system (`desktop_double_click_ms`: `GetDoubleClickTime` on Windows, GTK's `gtk-double-click-time` on Linux) and uses it for the click's wait when it is between 200 and 900 ms; otherwise 500 ms.
- **The cost.** The bench prints the cost of the page's frames, and a line saying that the two Rust checks cost what Task Manager shows: that number is the owner's (Checkpoint 3's real-build list).

- [ ] **Step 1: Write the test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-away.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Away and awake (sub-project H): the seams between the desktop page and Rust, pinned by source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");

test("the page treats a locked session and a display that is off as hidden, tells Rust when it is awake, holds its cursor reads to 10 Hz and takes the system's double-click time; Rust watches the platform's own notifications and checks only while awake", () => {
  const body = source("desktop/body.ts"), d = rust("src/desktop.rs"), l = rust("src/lib.rs");
  assert.match(body, /hidden: document\.visibilityState === "hidden" \|\| this\.away,/);
  assert.match(body, /case "away": this\.away = m\.on; break;/);
  assert.match(body, /void Bridge\.desktopAwake\(awake\);/);
  assert.match(body, /if \(t - this\.lastCursor < 100\) return;/);
  assert.match(body, /this\.gest\.doubleMs = ms;/);
  assert.match(source("cat/desktoptrip.ts"), /\{ k: "away"; on: boolean \}/);
  assert.match(source("cat/gestures.ts"), /export const DOUBLE_MS = 500;/);
  assert.match(d, /CHECK_MS && \(gate\.awake\.load\(Ordering::Relaxed\) \|\| covered\)/);
  assert.match(d, /pub fn desktop_awake\(/);
  assert.match(d, /pub fn desktop_double_click_ms\(\) -> Option<u32>/);
  assert.match(l, /platform::watch_away\(move \|on\|/);
  assert.match(rust("src/platform/windows.rs"), /WTSRegisterSessionNotification/);
  assert.match(rust("src/platform/windows.rs"), /GetDoubleClickTime/);
  assert.match(rust("src/platform/linux.rs"), /org\.freedesktop\.login1/);
  assert.match(rust("src/platform/linux.rs"), /gtk_double_click_time/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-away.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..
```

Expected: `# tests 1`, `# pass 0`, `# fail 1`.

- [ ] **Step 3: The page's half**

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src/core/bridge.ts", [
('''  /** A message between the island's page (the brain) and the desktop page (the body): `to` is the window's label. */''', '''  /** The cat is awake and drawn (shown, not asleep, not away): only then does Rust run its light checks (the screens and a fullscreen app, 2 Hz). */
  desktopAwake: (on: boolean) => call<void>("desktop_awake", { on }),
  /** The system's double-click time in ms, or null where the app cannot read it (the page then waits 500 ms). */
  desktopDoubleClick: () => call<number>("desktop_double_click_ms"),
  /** A message between the island's page (the brain) and the desktop page (the body): `to` is the window's label. */'''),
])
edit("windows/src/cat/desktoptrip.ts", [
('''  /** Stop drawing and hide the window. */
  | { k: "hide" };''', '''  /** The session is locked or the display is off (`on`), or both are back: Rust says so from the platform's own notifications; the page draws nothing while away. */
  | { k: "away"; on: boolean }
  /** Stop drawing and hide the window. */
  | { k: "hide" };'''),
])
edit("windows/src/desktop/body.ts", [
('''  private kittenSig = "";
''', '''  private kittenSig = "";
  /** The session is locked or the display is off (Rust's `away` message): the same as a hidden page for the frame rate. */
  private away = false;
  /** What Rust was last told by `desktopAwake`. */
  private awakeSent = false;
  /** When the cursor was last asked for (ms): the read is held to about 10 Hz. */
  private lastCursor = -1e9;
'''),
('''    this.world = (await Bridge.desktopScreens()) ?? this.world;
''', '''    this.world = (await Bridge.desktopScreens()) ?? this.world;
    void Bridge.desktopDoubleClick().then((ms) => { if (typeof ms === "number" && ms >= 200 && ms <= 900) this.gest.doubleMs = ms; });
'''),
('''      case "emote": this.emote(m.name); break;
''', '''      case "emote": this.emote(m.name); break;
      case "away": this.away = m.on; break;
'''),
('''    this.cursorAsked = true;
''', '''    const t = performance.now();
    if (t - this.lastCursor < 100) return;
    this.lastCursor = t;
    this.cursorAsked = true;
'''),
('''phase: this.flight ? "flyingOut" : this.visible || this.carrying ? "onDesktop" : "home", hidden: document.visibilityState === "hidden", dragging:''', '''phase: this.flight ? "flyingOut" : this.visible || this.carrying ? "onDesktop" : "home", hidden: document.visibilityState === "hidden" || this.away, dragging:'''),
('''      ...(c && at ? { cursorDist: Math.hypot(c.x - at.x, c.y - at.y) } : {}),
    }));
''', '''      ...(c && at ? { cursorDist: Math.hypot(c.x - at.x, c.y - at.y) } : {}),
    }));
    // Rust's light checks run only while the cat is awake: shown, awake, not away, page visible.
    const awake = this.visible && !this.away && look?.asleep !== true && document.visibilityState !== "hidden";
    if (awake !== this.awakeSent) { this.awakeSent = awake; void Bridge.desktopAwake(awake); }
'''),
])
print("applied")
PYEOF
```

- [ ] **Step 4: The Rust half**

Read what you paste: the Windows part uses the `windows` crate's `Win32::UI::WindowsAndMessaging` and `System::Power` and `System::RemoteDesktop` items, and the Linux part uses `gtk::gio`. A compile error whose cause is not obvious: stop and report the first ten lines.

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src-tauri/Cargo.toml", [
('''  "Win32_System_Ole",
''', '''  "Win32_Graphics_Gdi",
  "Win32_System_LibraryLoader",
  "Win32_System_Ole",
  "Win32_System_Power",
  "Win32_System_RemoteDesktop",
'''),
])
edit("windows/src-tauri/src/desktop.rs", [
('''    dragging: AtomicBool,
''', '''    dragging: AtomicBool,
    /// The cat is awake and drawn: shown, not asleep, not away, page visible. The page says so; the poll's light checks run only then.
    awake: AtomicBool,
'''),
('''            dragging: AtomicBool::new(false),
''', '''            dragging: AtomicBool::new(false),
            awake: AtomicBool::new(false),
'''),
('''#[tauri::command]
pub fn desktop_native_drag(app: AppHandle) {''', '''/// The page says whether the cat is awake and drawn. Only then does the poll look at the screens and for a fullscreen app (twice a second), except while a fullscreen app covers
/// the cat: that check is what ends the covering.
#[tauri::command]
pub fn desktop_awake(gate: State<DesktopGate>, on: bool) {
    gate.awake.store(on, Ordering::Relaxed);
}

/// The system's double-click time in ms, or None where the app cannot read it: the page then waits 500 ms.
#[tauri::command]
pub fn desktop_double_click_ms() -> Option<u32> {
    platform::double_click_ms()
}

#[tauri::command]
pub fn desktop_native_drag(app: AppHandle) {'''),
('''                if last_check.elapsed().as_millis() >= CHECK_MS {''', '''                if last_check.elapsed().as_millis() >= CHECK_MS && (gate.awake.load(Ordering::Relaxed) || covered) {'''),
])
edit("windows/src-tauri/src/lib.rs", [
('''            desktop::desktop_native_drag,
''', '''            desktop::desktop_native_drag,
            desktop::desktop_awake,
            desktop::desktop_double_click_ms,
'''),
('''            desktop::spawn_poll(handle.clone(), handle.state::<desktop::DesktopGate>().inner().clone());
''', '''            desktop::spawn_poll(handle.clone(), handle.state::<desktop::DesktopGate>().inner().clone());
            // Lock, unlock and display off or on come from the platform's own notifications (nothing polls): the desktop page treats them as hidden.
            let away_handle = handle.clone();
            platform::watch_away(move |on| {
                let _ = away_handle.emit_to(desktop::WINDOW_LABEL, "desktop-msg", serde_json::json!({ "k": "away", "on": on }));
            });
'''),
])
edit("windows/src-tauri/src/platform/windows.rs", [
('''/// True when the foreground window belongs to another process''', '''/// The system's double-click time in ms.
pub fn double_click_ms() -> Option<u32> {
    Some(unsafe { ::windows::Win32::UI::WindowsAndMessaging::GetDoubleClickTime() })
}

static AWAY: std::sync::OnceLock<Box<dyn Fn(bool) + Send + Sync>> = std::sync::OnceLock::new();

/// Session lock and unlock (`WM_WTSSESSION_CHANGE`) and the display turning off or on (`WM_POWERBROADCAST` with the console display state): `notify(true)` while away. A message-only
/// window on its own thread receives them and blocks in `GetMessageW`, so nothing polls.
unsafe extern "system" fn away_proc(hwnd: HWND, msg: u32, wp: ::windows::Win32::Foundation::WPARAM, lp: LPARAM) -> ::windows::Win32::Foundation::LRESULT {
    use ::windows::Win32::System::Power::{GUID_CONSOLE_DISPLAY_STATE, POWERBROADCAST_SETTING};
    use ::windows::Win32::System::RemoteDesktop::{WTS_SESSION_LOCK, WTS_SESSION_UNLOCK};
    use ::windows::Win32::UI::WindowsAndMessaging::{DefWindowProcW, PBT_POWERSETTINGCHANGE, WM_POWERBROADCAST, WM_WTSSESSION_CHANGE};
    let tell = |away: bool| {
        if let Some(f) = AWAY.get() {
            f(away);
        }
    };
    match msg {
        WM_WTSSESSION_CHANGE => {
            match wp.0 as u32 {
                WTS_SESSION_LOCK => tell(true),
                WTS_SESSION_UNLOCK => tell(false),
                _ => {}
            }
            ::windows::Win32::Foundation::LRESULT(0)
        }
        WM_POWERBROADCAST if wp.0 as u32 == PBT_POWERSETTINGCHANGE => {
            let s = unsafe { &*(lp.0 as *const POWERBROADCAST_SETTING) };
            if s.PowerSetting == GUID_CONSOLE_DISPLAY_STATE {
                // 0 off, 1 on, 2 dimmed.
                tell(s.Data[0] == 0);
            }
            ::windows::Win32::Foundation::LRESULT(1)
        }
        _ => unsafe { DefWindowProcW(hwnd, msg, wp, lp) },
    }
}

/// Starts listening (once). `notify(true)` while the session is locked or the display is off.
pub fn watch_away(notify: impl Fn(bool) + Send + Sync + 'static) {
    if AWAY.set(Box::new(notify)).is_err() {
        return;
    }
    std::thread::spawn(|| unsafe {
        use ::windows::core::w;
        use ::windows::Win32::System::LibraryLoader::GetModuleHandleW;
        use ::windows::Win32::System::Power::{RegisterPowerSettingNotification, GUID_CONSOLE_DISPLAY_STATE};
        use ::windows::Win32::System::RemoteDesktop::{WTSRegisterSessionNotification, NOTIFY_FOR_THIS_SESSION};
        use ::windows::Win32::UI::WindowsAndMessaging::{
            CreateWindowExW, DispatchMessageW, GetMessageW, RegisterClassW, TranslateMessage, DEVICE_NOTIFY_WINDOW_HANDLE, HWND_MESSAGE, MSG, WINDOW_EX_STYLE, WINDOW_STYLE, WNDCLASSW,
        };
        let Ok(module) = GetModuleHandleW(None) else { return };
        let class = WNDCLASSW { lpfnWndProc: Some(away_proc), hInstance: module.into(), lpszClassName: w!("NotchMeowAway"), ..Default::default() };
        RegisterClassW(&class);
        let Ok(hwnd) = CreateWindowExW(WINDOW_EX_STYLE(0), w!("NotchMeowAway"), w!(""), WINDOW_STYLE(0), 0, 0, 0, 0, Some(HWND_MESSAGE), None, Some(module.into()), None) else { return };
        let _ = WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION);
        let _ = RegisterPowerSettingNotification(::windows::Win32::Foundation::HANDLE(hwnd.0), &GUID_CONSOLE_DISPLAY_STATE, DEVICE_NOTIFY_WINDOW_HANDLE);
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    });
}

/// True when the foreground window belongs to another process'''),
])
edit("windows/src-tauri/src/platform/linux.rs", [
('''/// Nothing to look for: the cat's layer is below fullscreen windows already.''', '''/// GTK's double-click time in ms.
pub fn double_click_ms() -> Option<u32> {
    gtk::Settings::default().map(|s| s.gtk_double_click_time().max(0) as u32)
}

/// Lock, unlock and suspend from logind, over the system bus through gio (nothing polls): `notify(true)` while away. Where logind is not there the page's own visibility still
/// hides the cat. Must be called on the GTK main thread (the setup is).
pub fn watch_away(notify: impl Fn(bool) + Send + Sync + 'static) {
    use gtk::gio;
    let notify = std::sync::Arc::new(notify);
    gio::bus_get(gio::BusType::System, gio::Cancellable::NONE, move |conn| {
        let Ok(conn) = conn else { return };
        let n = notify.clone();
        let _ = conn.signal_subscribe(
            Some("org.freedesktop.login1"), Some("org.freedesktop.login1.Manager"), Some("PrepareForSleep"), Some("/org/freedesktop/login1"), None, gio::DBusSignalFlags::NONE,
            move |_, _, _, _, _, params| n(params.child_value(0).get::<bool>().unwrap_or(false)),
        );
        for (signal, away) in [("Lock", true), ("Unlock", false)] {
            let n = notify.clone();
            let _ = conn.signal_subscribe(
                Some("org.freedesktop.login1"), Some("org.freedesktop.login1.Session"), Some(signal), None, None, gio::DBusSignalFlags::NONE,
                move |_, _, _, _, _, _| n(away),
            );
        }
    });
}

/// Nothing to look for: the cat's layer is below fullscreen windows already.'''),
])
print("applied")
PYEOF
```

Run (needs the image; otherwise this step is owed):

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/h-tauri 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
git diff --stat notchmeow/rebrand -- windows/Cargo.lock | wc -l
```

Expected: `test result: ok.` for the library and the relay with no `error` and no `warning` (or the line saying it is owed), and `0` (the lock file did not change).

- [ ] **Step 5: Run the test, the type check and the whole suite**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; node --experimental-strip-types --test scripts/cat-tests/desktop-away.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `# tests 1`, `# pass 1`, `# fail 0`, then `ℹ tests 342`, `ℹ pass 342`, `ℹ fail 0`.

- [ ] **Step 6: Prove the test can bite**

Run:

```bash
cd windows
python3 ../.claude/checkpoints/h-tauri/mut.py src/desktop/body.ts 'hidden: document.visibilityState === "hidden" || this.away,' 'hidden: document.visibilityState === "hidden",' scripts/cat-tests/desktop-away.test.mjs
cd ..
```

Expected: `# fail 1`.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src-tauri/Cargo.toml windows/src-tauri/src/desktop.rs windows/src-tauri/src/lib.rs windows/src-tauri/src/platform windows/src/core/bridge.ts windows/src/cat/desktoptrip.ts windows/src/desktop/body.ts windows/scripts/cat-tests/desktop-away.test.mjs
git commit -F - <<'MSG'
feat(desktop): away and awake, and the system's double-click time

The desktop cat stops drawing when the session locks or the display turns off (the platform's own notifications, no polling), its light checks run only while it is awake, and a click waits the system's double-click time.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent, the model and the trigger.

---


## Checkpoint 2: the owner looks at the alert flight and the bench

Tasks 1 to 8b are done. The session **stops here**, copies the pictures and the bench output into `.claude/checkpoints/h-tauri/` (`alert-flight.png`, `bench.txt`) and sends the owner their paths with this list. **Nothing of Task 9 starts before the owner's reply.**

1. **Pictures and numbers:** `alert-flight.png` (the alert flight as a strip of eight frames) and `bench.txt` (ms per frame at Small, Medium and Large with no kittens and with three, and the percent of one core at 0.5, 5, 20 and 60 frames a second, from the headless software canvas), and the zero-frame result (`"hidden":0`: a hidden cat schedules nothing).
2. **What to look at:** the arc (bows upward, eased in and out: slow at both ends, 0.6 s, the cat at full size the whole way); the surprised emote before it leaves; the cat arriving in the notch strip as the small compact cat; the numbers against the target (**under 1 % of a core idle and awake, about 0 % asleep**): is idle under 1 % at every size?
3. **Questions:** the bench measures this browser's software canvas, which is slower than the app's real one: is that bound (the "idle" column) enough, or should the owner's real-build check in Task Manager decide? Is 20 fps while an agent works smooth enough at Large?
4. **What no picture shows:** the real window's flight across the screen (a window moved on every frame), a flight across two monitors, a fullscreen app hiding it.

---

# Stage 7: the tray item and the GNOME note

### Task 9: The tray item and the Settings GNOME note

**Agent:** `nm-implementer` (Haiku 5.5, high). The Rust steps need the image; without it they are owed.

**Files:**
- Modify: `windows/src-tauri/src/tray.rs`, `windows/src-tauri/src/lib.rs`, `windows/src-tauri/src/desktop.rs`, `windows/src/core/bridge.ts`, `windows/src/main.ts`, `windows/src/island/desktop.ts`, `windows/src/settings/cat.ts`, `windows/src/settings/main.ts`
- Test: `windows/scripts/cat-tests/desktop-menu.test.mjs`

**Interfaces:**
- Consumes: Task 5's brain and `main.ts`'s `"tray"` listener; Task 3's `desktop.rs` and `platform::desktop_positioned`; Task 2's switch row.
- Produces: the tray's **"Cat on the desktop"** item between Open and Settings (it becomes **"Bring the cat home"** while the cat is out: the brain tells Rust at every phase change, `desktop_menu_text`); its click reaches the island as the tray event `desktop`, which toggles the trip; the boot info's `desktopPositioned`, and a line under the Settings switch where it is false (GNOME): "On this system the desktop decides where the cat's window goes: it lands where the system puts it and may not keep its spot between runs; you can drag it from there."

**There are no global shortcuts on Windows and Linux** (spec): the tray item, the Settings switch, dragging it out and a double-click are the controls.

- [ ] **Step 1: Write the test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/desktop-menu.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The tray's item and Settings' note under the switch (sub-project H), pinned by source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");
const root = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the tray's item toggles the trip, its words follow the phase, and Settings names the system that places windows itself under the switch", () => {
  assert.match(source("main.ts"), /case "desktop":\s*desktop\.trip\.toggle\(\);\s*break;/);
  assert.match(source("island/desktop.ts"), /phase: \(p\) => void Bridge\.desktopMenuText\(DESKTOP_PHASE_INFO\[p\]\.on\),/);
  assert.match(source("settings/cat.ts"), /\.\.\.\(host\.desktopNote \? \[h\("div", \{ class: "hint", text: host\.desktopNote \}\)\] : \[\]\),/);
  assert.match(source("settings/main.ts"), /desktopNote: boot && !boot\.desktopPositioned/);
  const t = rust("src/tray.rs"), l = rust("src/lib.rs"), d = rust("src/desktop.rs");
  assert.match(t, /MenuItem::with_id\(app, "desktop", "Cat on the desktop", true, None::<&str>\)/);
  assert.match(t, /if out \{ "Bring the cat home" \} else \{ "Cat on the desktop" \}/);
  assert.match(l, /desktop_positioned: platform::desktop_positioned\(\),/);
  assert.ok(l.includes("desktop::desktop_menu_text,") && d.includes("pub fn desktop_menu_text"));
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows && node --experimental-strip-types --test scripts/cat-tests/desktop-menu.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..
```

Expected: `# tests 1`, `# pass 0`, `# fail 1`.

- [ ] **Step 3: The item, the note and the words**

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/src-tauri/src/desktop.rs", [
("""// ── The poll ──────""", """#[tauri::command]
pub fn desktop_menu_text(app: AppHandle, out: bool) {
    crate::tray::set_desktop_text(&app, out);
}

// ── The poll ──────"""),
])
edit("windows/src-tauri/src/lib.rs", [
("""    /// False where the OS has no global cursor (Wayland): the page then reports
    /// the cursor from its own mouse events.
    cursor_poll: bool,
}""", """    /// False where the OS has no global cursor (Wayland): the page then reports
    /// the cursor from its own mouse events.
    cursor_poll: bool,
    /// False where the system places windows itself (GNOME): Settings says so under the desktop cat's switch.
    desktop_positioned: bool,
}"""),
("""        cursor_poll: platform::CURSOR_POLL,
    }
}""", """        cursor_poll: platform::CURSOR_POLL,
        desktop_positioned: platform::desktop_positioned(),
    }
}"""),
("""            desktop::desktop_relay,
        ])""", """            desktop::desktop_relay,
            desktop::desktop_menu_text,
        ])"""),
])
edit("windows/src-tauri/src/tray.rs", [
("""use crate::island::WINDOW_LABEL;

pub fn build""", """use crate::island::WINDOW_LABEL;

/// The tray's "Cat on the desktop" item, kept so its words can follow the trip: "Bring the cat home" while the cat is out (sub-project H).
pub struct DesktopItem(pub MenuItem<tauri::Wry>);

pub fn set_desktop_text(app: &AppHandle, out: bool) {
    if let Some(item) = app.try_state::<DesktopItem>() {
        let _ = item.0.set_text(if out { "Bring the cat home" } else { "Cat on the desktop" });
    }
}

pub fn build"""),
("use tauri::{AppHandle, Emitter};", "use tauri::{AppHandle, Emitter, Manager};"),
("""    let settings = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;""", """    let desktop = MenuItem::with_id(app, "desktop", "Cat on the desktop", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;"""),
("""    let menu = Menu::with_items(app, &[&open, &sep1, &settings, &pause, &sep2, &quit])?;""", """    let menu = Menu::with_items(app, &[&open, &desktop, &sep1, &settings, &pause, &sep2, &quit])?;
    app.manage(DesktopItem(desktop));"""),
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

edit("windows/src/core/bridge.ts", [
('''  desktopRelay: (to: "island" | "desktop", msg: unknown) => call<void>("desktop_relay", { to, msg }),
};''', '''  desktopRelay: (to: "island" | "desktop", msg: unknown) => call<void>("desktop_relay", { to, msg }),
  /** The tray item reads "Bring the cat home" while the cat is out. */
  desktopMenuText: (out: boolean) => call<void>("desktop_menu_text", { out }),
};'''),
('''  /** False where the OS has no global cursor (Wayland): see Island.followPageCursor. */
  cursorPoll: boolean;
}''', '''  /** False where the OS has no global cursor (Wayland): see Island.followPageCursor. */
  cursorPoll: boolean;
  /** Whether the desktop cat's window can be put where we want it: false on GNOME, where Settings says so under the switch. */
  desktopPositioned: boolean;
}'''),
])
edit("windows/src/main.ts", [
('''      case "open":
        setPaused(false);
        island.alert(State.defaultView());
        break;''', '''      case "open":
        setPaused(false);
        island.alert(State.defaultView());
        break;
      case "desktop":
        desktop.trip.toggle();
        break;'''),
])
edit("windows/src/settings/cat.ts", [
('''  put(next: CatBlock, final: boolean): void;
}''', '''  put(next: CatBlock, final: boolean): void;
  /** A line under the desktop cat's switch where the system does not let the app place windows (GNOME); null or missing elsewhere. */
  desktopNote?: string | null;
}'''),
('''    row("Cat on the desktop", desktop, h("span", { class: "hint", text: "Drag the big cat out of the notch, or switch it here. Double-click it to send it home." })),
''', '''    row("Cat on the desktop", desktop, h("span", { class: "hint", text: "Drag the big cat out of the notch, or switch it here. Double-click it to send it home." })),
    ...(host.desktopNote ? [h("div", { class: "hint", text: host.desktopNote })] : []),
'''),
])
edit("windows/src/settings/main.ts", [
('''  const cat = catSection({
    cat: () => settings.cat,
    put: (next, final) => {
      settings.cat = next;
      if (final) void save();
    },
  });''', '''  const cat = catSection({
    cat: () => settings.cat,
    put: (next, final) => {
      settings.cat = next;
      if (final) void save();
    },
    // GNOME's Wayland session decides where a window goes: say so under the desktop cat's switch.
    desktopNote: boot && !boot.desktopPositioned
      ? "On this system the desktop decides where the cat's window goes: it lands where the system puts it and may not keep its spot between runs; you can drag it from there."
      : null,
  });'''),
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

edit('windows/src/island/desktop.ts', [
('''        State.notify();
      },
    });''', '''        State.notify();
      },
      // The tray's item reads "Bring the cat home" while the cat is out.
      phase: (p) => void Bridge.desktopMenuText(DESKTOP_PHASE_INFO[p].on),
    });'''),
])
PYEOF
```

- [ ] **Step 4: Run the test, the type check and the whole suite**

Run:

```bash
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; node --experimental-strip-types --test scripts/cat-tests/desktop-menu.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: `tsc exit 0`, `# tests 1`, `# pass 1`, `# fail 0`, then `ℹ tests 343`, `ℹ pass 343`, `ℹ fail 0`.

- [ ] **Step 5: The Rust suite**

Run:

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/h-tauri 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok.` for the library and the relay with no `error` and no `warning`. A compile error in `tray.rs` or `lib.rs`: stop and report the first ten lines.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/src-tauri/src/tray.rs windows/src-tauri/src/lib.rs windows/src-tauri/src/desktop.rs windows/src/core/bridge.ts windows/src/main.ts windows/src/island/desktop.ts windows/src/settings/cat.ts windows/src/settings/main.ts windows/scripts/cat-tests/desktop-menu.test.mjs
git commit -F - <<'MSG'
feat(desktop): the tray item and the Settings note for GNOME

The tray menu has Cat on the desktop (Bring the cat home while it is out), and Settings says under the switch that the system places the window where it wants where it does (GNOME). No global shortcut on Windows and Linux.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model.

---

# Stage 8: the docs

### Task 10: The docs and the final checks

**Agent:** `nm-implementer-light` (Haiku 5.5, medium; Step 3 runs the whole suites).

**Files:**
- Modify: `windows/README.md`, `CLAUDE.md`, `ARCHITECT.md`

**Interfaces:**
- Consumes: everything above. `CLAUDE.md` and `ARCHITECT.md` get one new line each (the Windows/Linux part of sub-project H), added as new lines so that a merge with the Mac twin's edits (which touch other lines) has no conflict. The roadmap row of the root `README.md` and `docs/INTEGRATIONS.md` are not touched here: the main session sets the roadmap row's final status when both plans have landed.

- [ ] **Step 1: Edit the docs**

```bash
python3 - <<'PYEOF'
def edit(path, pairs):
    s = open(path).read()
    for a, b in pairs:
        assert s.count(a) == 1, f"{path}: {a[:70]!r} occurs {s.count(a)} times"
        s = s.replace(a, b)
    open(path, "w").write(s)

edit("windows/README.md", [
('''| `Esc` | Closes the island |
| Tray icon | Open, Settings…, Pause, Quit |''', '''| Drag the big cat out of the notch and drop it on the desktop | It lives there, above your windows: it watches the pointer, wears its badge, collar and kittens, and sleeps and wakes like the notch's cat. Click it to open the island, double-click to send it home, right-click for Open the notch, Send home and Size |
| `Esc` | Closes the island |
| Tray icon | Open, Cat on the desktop (Bring the cat home while it is out), Settings…, Pause, Quit |'''),
('''## Claude Code
''', '''**The cat on the desktop.** The big cat can leave the notch and live on the desktop as a companion: drag it out and drop it on empty desktop, or use **Settings… → Cat → Cat on the desktop**, or the tray item. It is the same cat the notch would show (the Main cat, the focused agent's cat in A cat for each agent, or cat 1 in Two cats), so the big cat's spot in the notch is empty meanwhile; cat 2 and the pills stay. It floats above windows with its state badge, its collar in the working agent's colour and up to three of its agent's kittens (then "+N"; on the right half of the screen they stand on its left), and clicks pass through everywhere but its body. A click opens the island and a double-click sends it home; right-click has **Open the notch**, **Send home** and **Size** (Small Ø48, Medium Ø64 by default, Large Ø96). When an approval or a question is waiting it gives the surprised emote and flies into its notch spot, and flies back out when you have answered. It remembers whether it is out, its size and its spot (a spot per arrangement of screens, so a laptop alone and a laptop with a monitor each keep their own), and a cat that was out flies back out after the launch greeting. It draws 60 frames a second only while it moves, 20 while an agent works or the pointer is near, 5 while it is idle, a still frame every two seconds asleep, and nothing while it is hidden by a fullscreen app or the screen is locked.

## Claude Code
'''),
('''### Testing the cats
''', '''### Testing the cats

The desktop cat (sub-project H) is ported from the same contract: `src/cat/desktop.ts` (the trip `desktopStep`, the flight, the frame rate `desktopFps`, the spots on the screens and `cleanDesktopSettings`, replayed from `desktop-cases.json`), with its Rust twin `clean_desktop_settings` in `src-tauri/src/cat_settings.rs`. The island's page runs the trip (`island/desktop.ts` with `cat/desktoptrip.ts`) and a second window, `desktop.html` (`src/desktop/body.ts`, `src-tauri/src/desktop.rs`), draws the cat (`cat/desktopdraw.ts`, `desktopview.ts`, `desktopflight.ts`, `desktopgov.ts`); they talk through the `desktop_relay` command. `?dev` has a **Desktop cat** panel: the cat at the three sizes on a mock desktop with its badge, collar and kittens, the alert flight as a strip of frames, and a **Measure** button that times a frame at each size and prints what each frame rate costs. In the dev server, `http://127.0.0.1:1420/desktop.html` loads the window's page, and `__body.handle({ k: "show", ... })` feeds it the messages the island's page sends.
'''),
('''- Images and scanned PDFs for a model that can't see go through Windows' own OCR
  (`Windows.Media.Ocr`) instead of the Mac's Vision framework.
''', '''- Images and scanned PDFs for a model that can't see go through Windows' own OCR
  (`Windows.Media.Ocr`) instead of the Mac's Vision framework.
- The desktop cat has no global shortcut here (the Mac has one): the tray item, the Settings switch, dragging it out and a double-click do the same. A fullscreen app hides it (found by looking at the foreground window). Windows' virtual desktops are not followed: it stays on the one it was put on.
'''),
('''- **Click-through** is the window's input region, kept equal to the island
  shape, so the compositor sends every other click to what is underneath.''', '''- **Click-through** is the window's input region, kept equal to the island
  shape, so the compositor sends every other click to what is underneath.
- **The cat on the desktop** is its own small window. On compositors with layer-shell it is a surface on the top layer (below fullscreen windows, so it steps aside over a fullscreen app) placed with margins on the screen that holds it. On GNOME's Wayland session the system ignores a window's position: the cat lands where GNOME puts it, you can drag it from there, the flight is drawn inside its own window, its spot is saved but GNOME may not keep it, and Settings says so under the switch. On X11 its position is ours. `NOTCHMEOW_DESKTOP_POSITION=1` or `0` overrides the guess.'''),
])

edit("CLAUDE.md", [
('''- `docs/index.html` — placeholder GitHub Pages site''', '''- Sub-project H on Windows/Linux (the desktop cat): `windows/src/cat/desktop.ts` ports the contract's desktop rules (`desktopStep`, `desktopFlightAt`, `desktopFps`, the spots and `cleanDesktopSettings`, tested against `desktop-cases.json`), stored as the `desktop` object of the `cat` block (`cat/display.ts` cleans the whole block; the Rust twin is `clean_desktop_settings` in `cat_settings.rs`). The island's page is the brain (`island/desktop.ts` runs `cat/desktoptrip.ts`) and a second transparent window, `desktop.html` (`src/desktop/body.ts`, `src-tauri/src/desktop.rs`), is the body that draws the cat (`cat/desktopdraw.ts`, `desktopview.ts`, `desktopflight.ts`, `desktopgov.ts`); they talk through the `desktop_relay` command. Click-through is the cursor poll (Windows, only while the cat is out) or the input region (Linux); GNOME may ignore the position, and there is no global shortcut. `?dev` has a Desktop cat panel (the mock desktop, the alert flight, the bench) and the dev server serves `desktop.html`.
- `docs/index.html` — placeholder GitHub Pages site'''),
])

edit("ARCHITECT.md", [
('''The two H app plans build on it.''', '''The two H app plans build on it.
   - **Sub-project H on Windows/Linux:** the `cat` block's `desktop` object (`on`, `size`, `spots`) is cleaned with the rest of the block by `cat/display.ts` and `clean_cat_block`. The island's page is the brain: `island/desktop.ts` runs the trip (`cat/desktoptrip.ts`, from `desktopStep`), takes the cat out of the notch (a press on it that moves 4 px, `cat/pressdrag.ts`), asks `State.attentionNeeded` for alerts and keeps the notch's big-cat spot empty (`State.desktopNotchEmpty`) while the cat is out. A second window, `desktop.html`, is the body: `desktop/body.ts` draws the cat, flies it (`cat/desktopflight.ts`), takes the clicks and the drag (`cat/gestures.ts`), and keeps to the frame rate the contract gives (`cat/desktopgov.ts`). Rust (`src-tauri/src/desktop.rs`) only moves and shows the window, decides what takes the mouse and relays the messages between the two pages.'''),
])
print("applied")
PYEOF
```

- [ ] **Step 2: Check that the docs say what the code does**

Run:

```bash
grep -c "desktop_relay" CLAUDE.md windows/README.md ARCHITECT.md
grep -n "Cat on the desktop" windows/README.md | cut -c1-80
```

Expected: `CLAUDE.md:1`, `windows/README.md:1`, `ARCHITECT.md:0` for the first, and at least three lines for the second (the table row, the tray row, the paragraph).

- [ ] **Step 3: Run every check**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1
(cd .. && bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two generator")
cd ..
git status --short
```

Expected: `tsc exit 0`, `ℹ tests 343`, `ℹ pass 343`, `ℹ fail 0`, `All AI UI checks passed`, `All Claude Code UI checks passed`, `# tests 284`, `# pass 284`, `# fail 0`, `✓ 15 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`, and then the three doc files as modified (` M`) and nothing else.

Then the Rust suite (needs the image):

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/h-tauri 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok.` for the library and the relay, no `error`, no `warning` (or the line saying the Rust is owed). The Windows `cargo check` and a release build are owed to CI.

- [ ] **Step 4: Check that nothing forbidden changed**

Run:

```bash
git diff --stat notchmeow/rebrand...HEAD -- design tests scripts docs/CAT-CONTRACT.md windows/Cargo.lock | tail -1
git diff --name-only notchmeow/rebrand...HEAD | grep -E "^(NotchBuddy|design|tests|scripts)/" | wc -l
```

Expected: nothing printed by the first (no change to the core, the fixtures, the generator, the contract or the lock file; `windows/src-tauri/Cargo.toml` changes only in Task 8b, four features of the `windows` crate), and `0` for the second.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and h-tauri/desktop-cat
git add windows/README.md CLAUDE.md ARCHITECT.md
git commit -F - <<'MSG'
docs(desktop): the desktop cat on Windows and Linux

The README, the Windows line of CLAUDE.md and ARCHITECT.md describe the desktop cat: its two pages, its window and click-through, its settings, its controls and what differs by system.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```
Then write the task's line in the ledger (`.superpowers/sdd/2026-10-12-h-tauri-desktop-cat/progress.md`): the commit, the test counts printed above, the agent and the model.

---

## Checkpoint 3: the owner signs off

Tasks 1 to 10 are done. The session **stops here** and reports (the report the controller brief lists), with the pictures of the three checkpoints. After the owner's OK, the main session dispatches **`nm-reviewer-deep`** (Sonnet 5.5, high; trigger 4) over `git diff notchmeow/rebrand...HEAD`, with the cross-task contracts, the security and privacy rules (no network, nothing stored beyond the three fields, the window forwards messages only between the two pages) and "Review Focus" above, then the owner's real-build checks:

**The owner's real-build checks** (the spec's list, and what this plan could not see): on **Windows**: drag the cat out of the notch and drop it; find it there after a restart at its size and spot; click (the island opens), double-click (it flies home), right-click (Open the notch, Send home, Size); an approval takes it to the notch with the surprised emote and brings it back after the answer; click-through (a click beside the cat reaches the window under it; the cat's body takes the mouse); two monitors (drag it across, unplug the one it is on: it must be on the other, in its default spot; mixed scaling); the taskbar and the Dock-like margins (it never sits under the taskbar); a fullscreen game or a video in F11 hides it; lock and unlock the screen, display off and on (the cat must stop drawing and come back; on Linux through logind), sleep and wake, and that its spot and size survive a restart; **CPU in Task Manager**: under 1 % idle, about 0 % asleep, 0 % with the cat home; the tray item's words. On **Linux**: KDE Plasma or any layer-shell compositor (the top layer: it must stay below a fullscreen window), the same drag, click and flight, two outputs; GNOME if available (the position is the system's, the native drag works, Settings says so under the switch); X11.

---

## Parity with macOS

**macOS is the primary platform**: the Mac gets at least what Windows and Linux get. The Mac twin (H-mac) is drafted at the same time by another drafter, so this section was written against the spec's own Mac lines and the contract, not against a finished Mac plan: **the main session reads the two together and decides where they differ**. Both plans build the same machine from the same contract (`desktopStep`, `desktopFlightAt`, `desktopFps`, `clampSpot`, `screenKey`, `spotFor`, `cleanDesktopSettings`, `desktopKittenSlots`, replayed from `desktop-cases.json`), the three owner checkpoints, and the same order of tasks (settings, window and click-through, drag/flight/home, alerts, what it shows, frame rate and bench, the controls, docs).

**What both apps do the same, on purpose.** The seven phases and their events; the empty big-cat spot in the notch while the cat is out (cat 2, the pills and the grid stay); a drop places the cat (no flight), the menu item and the switch and a launch fly it; an alert's surprised emote then the flight; the flight's arc and 600 ms; the sizes Ø48, Ø64 (default) and Ø96; the clicks (a click waits one double-click interval, then the happy emote and the island opens; a double-click sends it home; right-click Open the notch, Send home, Size); the badge, the collar, up to three kittens then "+N", mirrored to the cat's left in the right half of its screen; cursor-watching; sleep with the sweep; the frame-rate rule (60, 20, 5, a still frame every 2 s, 0 hidden); one spot per arrangement of screens; the drop rule's difference (the Mac attaches a window a cat is dropped on; here any drop places the cat, because there is no attach).

**Added here that the Mac plan should consider** (each line says whether the Mac should add it or whether it is Windows-only on purpose):

1. **The delay and the emote of the alert flight are numbers of this plan:** 450 ms of surprised emote before the flight (`SURPRISE_MS`) and the system's double-click time for the click's wait (`DOUBLE_MS`, 500 ms when it cannot be read: `GetDoubleClickTime` on Windows, GTK's `gtk-double-click-time` on Linux). *Mac: `NSEvent.doubleClickInterval` with the same 0.5 s fallback (ruling 2).*
2. **A flight that changes its notch end** (the island opens for the alert while the cat flies in) follows the notch spot (`notchMoved`, only a change is sent). *Mac: the same; the contract says the notch end is the compact place or the expanded one.*
3. **The alert rule is `State.attentionNeeded`:** a pending approval, a chat's waiting step (Claude plan, Agent) or a pill in `approval` or `question`; the same rule as the nap's. *Mac: `pendingApproval`/`pendingQuestion` plus the chat's card, the same three.*
4. **A press on the notch's cat is decided at release** (a click, as ever, or a drag out) and a cat that is out cannot be pressed in the notch. *Mac: the same, and its drop rule (a window attaches, no window places) keeps the Mac's attach unchanged.*
5. **The hit shapes are circles** (the head's circle of 0.55 D so the ears count as the cat, the badge, each kitten, the "+N") and the window is exactly as large as the cat, its badge and its kittens (the last kitten's state badge included: `BADGE_RIGHT` of `kittendraw.ts`). *Mac: its click-through "follows the body's shape"; the same shapes would make the two feel alike.*
6. **`State.desktopNotchEmpty` hides the big cat, its glow and its kittens, but not cat 2.** *Mac: the same in `AppState`.*
7. **A cat that was out flies back out when the launch greeting completes** (`Greeting.onComplete`), not at the end of its last beat. *Mac: "after the greeting, if it was out": the same moment is the greeting's completion.*
8. **The size menu saves through the brain** (one writer), and the Settings switch and the tray item are the same event. *Mac: its menu-bar item, ⌃⌥D and the switch are the same `toggle`.*

**Windows-only on purpose (platform extras):** no global shortcut (the spec: "there are none on Windows and Linux"; the Mac's ⌃⌥D is the Mac's); the Windows cursor poll (16 ms near the cat, 100 ms far, only while the cat is out) instead of the Mac's mouse-moved event monitor; the Linux input region and the top layer-shell surface; GNOME's note under the switch and the native window drag where the system places windows; Windows' fullscreen detection by the foreground window; Windows' virtual desktops are not followed (the Mac's panel joins all Spaces); the right-click menu is a native menu from the Tauri menu API; `window.__body.handle(...)` and `?dev`'s panel (dev server only) for the pictures, where the Mac draws sheets with `render-cats.sh`.

**What the Mac has that Windows does not need:** the music dance (a music source exists on the Mac; here `State.musicPlaying` is the seam and nothing sets it, so the desktop cat does not dance on Windows or Linux until a plan fills it), the Mac's drop-on-a-window attach, and Spaces.

**Docs.** `CLAUDE.md` and `ARCHITECT.md` get one new line each (Task 10), as new lines so that a merge with the Mac twin's edits has no conflict. The Mac plan edits the root `README.md`, `docs/INTEGRATIONS.md` and its own bullets; this plan touches none of them (its CI needs no change), so **the main session sets the roadmap row's final status when both plans have landed**.

---

## Open questions for the owner

Each has the answer this plan assumed. Ask at the checkpoint named, or at the owner's real-build checks.

1. **Positions are points: physical pixels over the primary screen's scale factor** (the contract's unit), and a cat on a screen with another scale keeps the size that screen gives it. Mixed scaling (a 100 % laptop beside a 200 % monitor) is the case where one point is not one pixel on every screen; the clamp's 24-point margin is then 24 points of the primary scale. Assumed: fine. *Ask at the real-build checks (two monitors, mixed scaling).*
2. **Windows' virtual desktops are not followed.** The window floats above windows on the desktop it was put on; Tauri has no API for a window on every virtual desktop on Windows (Linux has `visible_on_all_workspaces`, used). The spec says "every Space" for the Mac. Assumed: acceptable on Windows. *Ask at the real-build checks.*
3. **On GNOME (a Wayland session without layer-shell) drag-out from the notch stays on (spec: drag out on Linux, ruling 11), but the app cannot place the window:** the window comes up where GNOME puts it (`positioned: false`), the flight is a hop drawn inside the cat's own window, the spot is always saved, and Settings says under the switch that GNOME may not keep it. The desktop cat can then be dragged by the system's own window drag. Assumed: as drawn. *Ask at the real-build checks if GNOME is available.*
4. **The right-click menu is a native menu** (the Tauri menu API), so it needs no room in the window. On layer-shell compositors a native menu popped up from a layer surface may not appear; the tray item then does the same jobs (Open, bring home) and only Size would be missing. Assumed: try it, and say if it fails. *Ask at the real-build checks on KDE or Sway.*
5. **A press on the notch's cat can start a drag in the compact and the open island** (anywhere the big cat is drawn), not during the greeting, the drop sequence or a hidden island. In the open island a press on the cat used to slap it at once; it now slaps at release, and a press that moves 4 px is a drag. Assumed: yes (the slap is a click).
6. **The cat keeps receiving the pointer outside the island's window during a drag out** (a mouse press is captured by the page on both systems), and the desktop window follows it. If a system loses the capture the drag ends where the pointer left; the owner checks it. Assumed: works on Windows and GTK.
7. **A drag of the desktop cat is the pointer's distance from where it was pressed**, which the window follows, so no screen coordinates of the pointer are needed (Wayland gives none). A lag of one frame between the pointer and the window is possible; the owner judges it. Assumed: smooth enough.
8. **The window is created hidden at launch** and costs a webview that does nothing (no timer, no frame callback) while the cat is home, plus a parked thread. Assumed: acceptable (the Settings window works the same way, and WebView2 needs it).
9. **Fullscreen detection on Windows** is "the foreground window of another process covers a whole monitor" (a game, F11 in a browser), checked twice a second while the cat is out; the desktop and the taskbar's classes are never fullscreen. A game in exclusive fullscreen is covered by the system itself. Assumed: fine; no new crate or feature is added. *Ask at the real-build checks.*
10. **Light checks while the cat is out (the owner's answer, 2026-10-12; it overrides spec §3's "nothing new polls" for Windows and Linux only).** The page reads the cursor at about 10 Hz (`desktop_cursor`, held to one call per 100 ms, and not while the cat is asleep, away, in the air or carried), Rust checks the screens and a fullscreen app at 2 Hz, and the click-through poll runs at 10 Hz when the cursor is far from the cat and 16 ms near it (a hover must be able to wake a sleeping cat). All of it runs only while the cat is on the desktop, and the 2 Hz check only while it is awake or covered (it is what ends the covering). On Linux/Wayland the cat looks ahead unless the pointer is over it. Assumed: fine; the owner reads the real cost in Task Manager.
11. **A click on the desktop cat opens the island the way the tray's Open does** (`alert(defaultView)`), also from a hidden island. Assumed: yes (the spec says "like a click on the notch").
12. **Sounds for the trip are out of scope** (spec); the cat plays the existing emotes' own sounds only through the engine, as the notch's cat does.
13. **A Settings write and the island's write can overwrite each other** (last write wins), as the sound toggle's save already does; the island saves the spot and `on` (rarely), the Settings window saves everything it holds, and both hold the latest through `settings-changed`. Assumed: fine.
14. **`on` is stored as the phase's `on`:** the cat in the notch for an alert counts as out (it flies back after the answer), and a cat flying home counts as home (quitting mid-flight leaves it home). Assumed: as the contract says.

---

## Self-review notes

- **Spec coverage.** §4 step 2, in order: (1) the settings and the clean-up port, TypeScript and Rust, kept at every save, with the Settings switch (Tasks 1 and 2); (2) the window and its click-through, on Windows, Linux with layer-shell and GNOME (Task 3); (3) dragging out, the flight and sending home (Tasks 4 and 5); (4) alerts (Task 6); (5) what it shows: badge, kittens, collar, eyes, cursor, dance, sleep (Task 7); (6) the frame-rate rule and the bench (Task 8); (7) the tray item and the Settings switch with the GNOME note (Tasks 2 and 9; no global shortcut); (8) the docs (Task 10). The three checkpoints are after Tasks 7, 8 and 10, and `nm-reviewer-deep` is last.
- **Placeholders.** None: every code step is a full file or a script whose replacements assert their anchors; every `Run:` has an `Expected:`, taken from the dry run below.
- **Type consistency.** The names are the contract's (`desktopStep`, `desktopFlightAt`, `desktopFps`, `desktopKittenSlots`, `screenKey`, `clampSpot`, `spotFor`, `rememberSpot`, `cleanDesktopSettings`, `DESKTOP_SIZES`, `DESKTOP_PHASE_INFO`) with the app's own (`DesktopTrip`, `TripEnv`, `BodyMsg`, `BrainMsg`, `BodyLook`, `DesktopFlight`, `Gestures`, `PressDrag`, `FrameGovernor`, `DesktopBrain`, `DesktopBody`, `DesktopWorld`, `desktopWindowLayout`, `drawDesktopCat`, `State.desktopNotchEmpty`, `State.attentionNeeded`) used with one spelling.
- **Review Focus** lines 1 to 6 each have named tests above.
- **What this plan deliberately does not do:** two desktop cats, Two cats' cat 2 on the desktop, a cat that walks, the wardrobe, dropping files on the desktop cat, global shortcuts, sounds for the trip, following Windows' virtual desktops, GNOME's position, the Windows `cargo check` and a release build (owed to CI), and any real window (the owner's real-build checks).

---

## Dry run (2026-10-12)

The plan was run before it was handed over, in throwaway clones of this repository (`git clone --local --shared` on `notchmeow/rebrand` at `99e3be1`, in the session scratchpad), never in the repository's own working tree. Nothing was committed or pushed (in a clone or in the main checkout), no NotchMeow app and no Tauri app was started, nothing was installed or downloaded (`windows/node_modules` was copied with `cp -cR`), no Docker image was built or pulled, and no network was used except `127.0.0.1`.

**Method.** The code of every task was first written and checked in one clone, then this file was generated from those verified files, and the whole file was replayed in a fresh clone by a small runner: it takes every `bash` block of this plan in order, runs `bash -n` on it (**all 105 blocks pass**), runs it from the clone's root, and compares its output with the backticked literals of the `Expected:` line that follows it. The result: **105 blocks, 85 run, 20 skipped (the git blocks of Setup, the commit blocks, the `git diff` checks and the Docker and Rust blocks), 0 problems** (a literal that names a file or is prose is not compared). The Setup's contract check printed `the contract is the one this plan was written against`. The baseline: `tsc exit 0`, `ℹ tests 274`, the contract's `# tests 284` and `✓ 15 fixture files match cat-core.js`. After Task 10 the clone's tree is byte for byte the tree the files were first verified in, and the files the commit steps name are exactly the files the plan created or changed.

| Task | Agent | What the run printed (the plan's Expected) |
|---|---|---|
| 1 | light | `desktop.test.mjs` 13 pass, red first (`ERR_MODULE_NOT_FOUND`); five rule changes fail 2, 1, 1, 2 and 1 tests; `check:cat` 287 |
| 2 | nm-implementer | `desktop-settings.test.mjs` red (1 of 6 passes), green 6; with the two older files 16; with `desktop` left out of the clean-up 3 fail; `check:cat` 293; `settings.html` renders the switch; the Rust script applies (not run) |
| 3 | deep | `desktop-view` 6 and `desktop-window` 2 pins, red (3 fail); two proofs fail 1 each; `check:cat` 301; the body's page at Small, Medium and Large: `80x113`, `108x151`, `160x226`, no console error besides the favicon's |
| 4 | light | flight 3, trip 15 and governor 5 tests pass (red: 3 files fail to load); nine proofs fail 1, 2, 1, 2, 4, 4, 1, 1, 1; `check:cat` 324 |
| 5 | deep | `desktop-island.test.mjs` 6 pass; three proofs fail 1; `check:cat` 330; the body takes the island's messages in order and draws `108x151` |
| 6 | nm-implementer | `desktop-alert.test.mjs` 2 pass (red: 2 fail); three proofs fail 1; `check:cat` 332 |
| 7 | nm-implementer | draw 4 and look 3 pass (red: 4 fail); four proofs fail 1; `check:cat` 339; the mock desktop at three sizes, an asleep Momo, the body's Medium with three kittens and "+2": `198x151` |
| 8 | nm-implementer | `desktop-rate.test.mjs` 2 pass (red: 2 fail); one proof fails 1; `check:cat` 341; a hidden cat schedules 0 timers and frame callbacks (7 while shown); the bench (three runs): Medium 0.3 ms a frame, 0.16 to 0.18 % of a core at 5 fps, 0.65 to 0.73 % at 20 and 0.02 % at 0.5; the strip of eight frames |
| 8b | deep | `desktop-away.test.mjs` 1 pass (red: 1 fail); one proof fails 1; `check:cat` 342 |
| 9 | nm-implementer | `desktop-menu.test.mjs` 1 pass (red: 1 fail); `check:cat` 343 |
| 10 | light | docs applied; `grep` counts as Expected |

**What the replay found on the way** (each is fixed in the text):

- **The window was too small for what it holds.** Drawing the real page showed the last kitten's state badge cut off (a badge sticks out beside its head) and, for a wide-headed coat (Latte), the cat's own badge a pixel outside. The layout now reaches to `BADGE_RIGHT` and to the badge's own reach, and a test pins both (a first mutation of the reach did not bite, so the test grew).
- **A drag step is the pointer's distance from where it was pressed,** not from the last event: the window follows the pointer, so the pointer is back at the press point after every step, and an incremental step would have undone itself. Lag between the pointer and the window is open question 7.
- **Task order.** The Bridge (Task 3) needs `DesktopWorld`, which first lived with the island's arithmetic (Task 5): `tsc` said so when the tasks were run in order, so the type lives in `desktopview.ts`. For the same reason a private field that nothing reads yet (`kittenMotionUntil`) is added with the code that reads it (Task 8): `noUnusedLocals` refuses a field that is only written.
- **An older source pin moved:** `two-cats.test.mjs` pinned `e.clientX, e.clientY` in the island's `mousedown` handler, which moves into `pressed(x, y)`; Task 5's script changes the pin. And the alert test did not cover a chat's waiting step until it was added.
- **Shell and browser details:** a URL with `?` is quoted (zsh reads it as a wildcard); `playwright-cli` makes a `.playwright-cli` folder in its working directory (so it is run from `.claude/checkpoints/h-tauri/`); a fresh browser session logs a 404 for `/favicon.ico` (the console check counts errors except that one); `canvas.style.width` carries `px` (the check strips it); a Python heredoc cannot contain its own terminator (the helper's text avoids `EOF`).

**Not run, and owed.**

- **All Rust.** The Docker daemon was not running (`docker image ls` could not connect), and the plan's rule is never to build or pull the image, so no `cargo test` ran: the Rust of Tasks 2, 3 and 9 (the clean-up and its tests, `desktop.rs` with its three unit tests, the platform parts, the tray) was written against the APIs of the pinned crates (Tauri 2.12's `Monitor::work_area`, `WebviewWindowBuilder`, `Menu`; gtk 0.18 and gtk-layer-shell as `platform/linux.rs` already uses them; the Win32 calls of `Win32_UI_WindowsAndMessaging`) and read through twice, but it has not been compiled. Expect at most a compile error or a missing import on the first run; the executing session reports the first ten lines and the main session decides (`nm-implementer-deep`). The Rust tests' expected counts (`3 passed` for `desktop::`) are unverified.
- **The Windows build** (`cargo check` and a release build): owed to `windows-tests.yml` and `windows.yml` on the owner's next push. Only `platform/windows.rs` touches Win32 and nothing was added to `Cargo.toml`.
- **Every commit step:** every `git add` and `git commit` block was skipped in the clones and has to be run by the executing session in its worktree.
- **The Tauri app itself.** No window of the real app was opened, so the window's creation order, click-through on both systems, the layer-shell surface, the right-click native menu, a drag across the island's edge, a flight across monitors, a fullscreen app and the lock screen are the owner's real-build checks (listed at Checkpoint 3), not something this run proved. The pages were driven in a headless browser from the Vite dev server with no Tauri, which proves the drawing, the layout and the logic, and nothing about the shell around them.
- **The Mac.** Nothing under `NotchBuddy/` is touched, and the Mac twin was not read (it is drafted at the same time).

The clones, their snapshots and the shots were moved to the Trash (`trash`, never `rm -rf`).

---

## Parity rulings (2026-10-12)

A parity check against the H-mac plan found gaps; the coordinator ruled as follows, and the plan above was changed to match (the code, the tests, the Expected lines, the parity section and the open questions).

**Values both plans share:**

1. **Surprise beat before a flight: 450 ms** (unchanged: `SURPRISE_MS`).
2. **Double-click:** the system's double-click time where it can be read (`GetDoubleClickTime` on Windows, GTK's `gtk-double-click-time` on Linux, through the new command `desktop_double_click_ms`, accepted between 200 and 900 ms), else **500 ms** (`DOUBLE_MS`, was a fixed 350 ms). The Mac uses `NSEvent.doubleClickInterval` with the same 0.5 s fallback. (Task 4's constant, Task 8b's lookup.)
3. **Drag threshold: 4 px** (unchanged).
4. **An emote counts as motion for 1800 ms** (`HAPPY_MS`, was 1500): the longest emote of `cat-core.js`'s `EMOUTH` (love and proud).
5. **A kitten counts as motion for 600 ms** (`KITTEN_MOTION_MS` = `KITTEN_LEAVE_MS`, was 700) after any change to the kitten list: an arrival, or a leave (a kitten that starts leaving or is removed).
6. **Window room for the hearts: D*40/58** (`OVERHANG_K = 40 / 58`, was 0.6). The windows are now 80x113, 108x151 and 160x226 with no kittens (and 198x151 for Medium with three), and every Expected line says so.
7. **The bench reports two rows at S, M and L:** idle without kittens (held under 1 %, the check prints `idleUnder1`) and 5 fps with three kittens (reported, not held): six rows.

**The owner's answer on polling (2026-10-12), Windows and Linux only; it overrides spec §3's "Nothing new polls":**

8. **Light checks while the cat is out:** a cursor check at about 10 Hz (the page's `desktop_cursor` read is held to one per 100 ms; the click-through poll runs at 10 Hz when the cursor is far from the cat and 16 ms near it) and a fullscreen check at 2 Hz. They run only while the cat is on the desktop and awake (`desktop_awake`), and stop at home, asleep, away and hidden. **One deviation, reported:** the 2 Hz check also runs while a fullscreen app covers the cat, because it is what ends the covering; and the click-through poll cannot stop while the cat is asleep, because a hover has to be able to wake it. The bench prints the page's cost and says that the two Rust checks cost what Task Manager shows (the owner's number). Open question 10 says so.

**Gaps against the spec and the contract:**

9. **Display off and lock detection without polling** (new **Task 8b**, `nm-implementer-deep`, trigger 1): Windows `WTSRegisterSessionNotification` and the console display-state power setting (a message-only window blocked in `GetMessageW`); Linux logind's `Lock`, `Unlock` and `PrepareForSleep` over D-Bus through gio; `document.visibilityState` stays the fallback. The page treats `away` as hidden. It enables four features of the `windows` crate that is already in `Cargo.toml` (`Win32_System_RemoteDesktop`, `Win32_System_Power`, `Win32_System_LibraryLoader`, `Win32_Graphics_Gdi`: no new package, `Cargo.lock` unchanged), which the earlier "no change to Cargo.toml" rule now allows for this task only.
10. **Zoomies on wake in the Playful style** (spec §2): the body puts its engine in the state the island says (`sleeping` to `idle`), which starts them as in the notch; a third pin of `desktop-look.test.mjs` says so (Task 7).
11. **GNOME keeps drag-out on** (spec: "drag … on Linux"): `canCarry` no longer needs `positioned`; the window comes up where GNOME puts it; the flight is a hop drawn inside the cat's own window; the spot is always saved; the Settings note says GNOME may not keep it. Open question 3 is rewritten.
12. **The real-build checks list** gains display off and on, the logind path on Linux, and the spot and size kept after a restart (Checkpoint 3).

**What could not be applied as ruled, or was not verified:** (a) the Rust of Task 8b (the Windows message window and the gio signals) is written against the pinned crates' APIs and was not compiled (no Docker image); (b) the 2 Hz check cannot stop while a fullscreen app covers the cat, and the click-through poll cannot stop while the cat is asleep (ruling 8's deviations above); (c) the cost of the Rust checks is not measured by the bench (it runs in a browser): it is the owner's Task Manager number.

**After the parity rulings** (same day) the changed blocks were replayed again in a fresh clone by the same runner (113 blocks, 91 run; the TypeScript, the tests, the browser checks and the Expected lines of every task, including the new Task 8b; the only block that printed no `Expected` literal was the dev server's start line, which had not finished its first message when the output was read, and every later browser block then ran against it). The Rust of Task 8b was not compiled (see "Parity rulings").

## The owner's answers (2026-10-13)

- **Approved as assumed:** every open question takes its assumed answer, with the parity rulings of 2026-10-12 applied.
- The two checks that keep running are approved: the 2 Hz fullscreen check while a fullscreen app covers the cat, and the cursor check while the cat sleeps, so a hover can wake it. Both stop when the cat is home, the screen is locked or the display is off.
- **Starts once Docker is up,** so Task 8b's Rust and the other Rust tasks compile in the session from the first task. If the image is missing, the session stops and reports; it never builds or pulls it.
