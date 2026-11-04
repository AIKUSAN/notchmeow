# H-0 Desktop Cat Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both apps what sub-project H needs from the shared contract before the app plans run: the pure rules for the desktop cat (its trip between the notch and the desktop and the flight, its frame rate, its sizes, where it may sit on the connected screens, what Settings stores and where its kittens stand), all in `design/prototype/cat-core.js` and pinned by one new fixture, `desktop-cases.json`, and the prototype's Desktop panel that draws it, which the owner approves at a checkpoint. The apps use none of it yet: that is the H-mac and H-tauri plans.

**Architecture:** Four new sections go into the one plain script, above the end-of-core marker, each reusing what is already there (`EZ`, `clamp`, `own`, `isPlain`, `isKittenId`). Everything is a new name: `KITTEN_PLACES`, `kittenSlots`, `flightAt`, `FLIGHT_MS`, `cleanCatSettings`, `cleanDisplaySettings` and every existing fixture line stay exactly as they are, so both apps stay green on `notchmeow/rebrand` until their H plans land. `scripts/gen-cat-fixtures.mjs` gains one builder for one new file, grown a section per task; `scripts/check-fixtures-additive.mjs 1627851` proves that no existing line moved. The prototype page gets a Desktop panel driven by the core: a mock screen with the notch, the big cat draggable out of it, the flight, an alert, a size picker, the frame-rate readout, the badge and kittens, and the empty spot in the notch. The owner's screenshots are taken headless with `playwright-cli` against a local static server.

**Tech Stack:** JavaScript (one file for a browser and Node 22), `node:test` and `node:assert` (no npm packages), Bash, Python 3 for the patches, `playwright-cli` with its cached browsers for the screenshots.

**Spec:** `docs/superpowers/specs/2026-10-08-desktop-cat-design.md`, section 4 step 1 (the contract) with sections 1 to 3 for the rules: §1 "The trip", §2 "On the desktop", §3 "Frame rate, CPU and the platforms". It extends `docs/CAT-CONTRACT.md` and `design/prototype/cat-core.js` as merged by A and B (plan `2026-10-08-b0-display-kittens-contract.md` is the format). Read the whole spec before starting.

**Base:** branch `h0/desktop-cat-contract`, created from `notchmeow/rebrand` at `1627851` or later, with this plan file already committed to `notchmeow/rebrand`. The cat contract must still be the one from `1627851` (231 self-checks, 14 fixtures): the additive check compares with that commit. This plan touches no app code under `NotchBuddy/` or `windows/`. **It changes no pixel and no behaviour in either app.** In the prototype page it adds one panel and one call in the frame loop; no existing panel changes.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed again under "Open questions for the owner".

- **Only new names.** Change no existing constant or function that the apps copy or pin: `KITTEN_PLACES`, `SMALL_EYE`, `kittenSlots`, `flightAt`, `FLIGHT_MS`, `cleanCatSettings`, `cleanDisplaySettings` and the rest. `tests/cat/fixtures.test.mjs`'s file list gains only `desktop-cases.json`. Every existing fixture stays byte-identical: `node scripts/check-fixtures-additive.mjs 1627851` must pass. The Mac cat tests (`scripts/test-cat-*.sh`) and the Windows `npm run check:cat` must pass unchanged.
- **The desktop cat (spec §1, §2):** one cat, the big cat, showing exactly what the big cat shows in the notch; its spot in the notch is empty while it is out; never two copies of one cat. The states `home`, `flyingOut`, `onDesktop`, `retracting`, `atNotchForAlert`, `returning` (the spec's six) plus `flyingHome` (plan decision: "flies it home" needs a phase of its own).
- **The events (spec §1):** `dragOut{spot}`, `move{spot}`, `toggle`, `sendHome`, `alertOn`, `alertOff`, `flightDone`, `launch`, `screensChanged`. An alert that clears mid-flight turns the cat around. A `sendHome` during an alert ends the trip at home. Events that make no sense in the current state change nothing.
- **The flight (spec §1):** an arc from the notch spot to the desktop spot, eased, about 0.6 s, the cat at full size the whole way; a pure function in the core, called `desktopFlightAt(from, to, t)` (plan decision: `flightAt` is the file catch's and both apps copy it).
- **Sizes (spec §2):** Small Ø48, Medium Ø64 (the default), Large Ø96. The IDs `small`, `medium`, `large` are frozen like the cat IDs. An unknown stored size is `medium`, a bad spot is dropped, a bad `on` is `false`.
- **Frame rate (spec §3):** 60 fps during motion (dragging, flying, an emote, a kitten arriving or leaving, the dance); 20 fps while an agent works, thinks or searches or the cursor is within 150 pt; 5 fps idle and awake; a still frame redrawn for a slow breath every 2 s asleep; 0 when the screen is asleep or locked, the display is off, a fullscreen app covers the cat, or `home`.
- **Spots (spec §1):** `clampSpot` keeps the cat 24 pt inside the visible frame, never under the menu bar or the Dock; a spot whose screen is gone moves to the main screen's default spot, a third of the way down the main screen, right of centre; the spot is stored per screen arrangement, under `screenKey(screens)`, built from the connected screens' frames sorted so their order does not matter.
- **Storage (spec §3):** macOS UserDefaults `cat.desktop.on` (Bool), `cat.desktop.size` (`small`, `medium` or `large`) and `cat.desktop.spots` (JSON: screen-arrangement key to spot); Windows and Linux the same three fields in the `cat` block of `settings.json`. They go through `cleanDesktopSettings`, a clean-up of its own, so `settings-cases.json` and `display-cases.json` stay byte for byte.
- **Kittens (spec §2):** up to 3 beside the desktop cat, then "+N", from a new place, `DESKTOP_KITTEN_PLACE`, measured in the cat's diameter, through `desktopKittenSlots(kittens)`, with the same slot maths as `kittenSlots`. It is a separate constant, not a new entry in `KITTEN_PLACES`. B's rules for kittens are unchanged.
- **Tolerance:** fixtures store 12 significant digits and apps compare within **1e-9**. There are no pixel tests. A fixture number of 1000 or more is a whole number or a half, or the 12 digits would cost more than the tolerance: the fixtures keep every other fraction under 1000 points.
- **`cat-core.js` is the tie-breaker:** it stays numbers in, numbers out: no canvas, no DOM, no clock, no `Math.random`. Nothing here needs randomness or a clock: time comes in as `t` and as flags.
- **Never restyle what ships.** The prototype is the visual source of truth for new character work. Its existing panels stay as they are: the Desktop panel is new, with new CSS classes, and the frame loop gains one call.
- **Node standard library only, no npm packages;** Node 22 or newer. Same code style as the core: compact one-liners with a comment above, plain commented code elsewhere.
- **Nothing of Coucou's comes back, and the names Coucou and Mochi appear in no new code** (`mocha` is a coat). Upstream's desktop pet (`git show 2b02b91`) may be read for ideas, never copied. `scripts/check-no-leftovers.sh` reads `scripts/` and `tests/`: it must stay green.
- **Commits:** local only, never pushed. End every commit message with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, or with the model that wrote it when an implementer runs on another one (the light tasks below name `Claude Haiku 4.5`).

## SUBAGENT RULES

Every subagent and the controller follow these; the controller puts them in each brief.

- **Never launch, quit or replace a NotchMeow app or the Tauri app.** The work is files, Node tests and a static page in a headless browser.
- **Install and download nothing.** `npx --no-install` only; never `npm install`, `npm run build` or `npm run dev`; `playwright-cli` uses the browsers already cached.
- **Delete with `trash`, never `rm -rf`,** and give scratch files unique names (the prefix `h0-`). Screenshots go outside the repository, in `${TMPDIR:-/tmp}/h0-shots`. The static server listens on `127.0.0.1` only, and every server and browser a task starts is stopped before the task ends.
- **Never run the real `claude` binary, never read tokens, never sign in.**
- **Never write to `~/Library/Logs/NotchMeow/` or to an app's preferences.** Tests never use `UserDefaults.standard` or `UserDefaults` suites (nothing in this plan touches them).
- **No Coucou or Mochi names as identity.** Upstream's desktop pet (`git show 2b02b91`, `NotchBuddy/Sources/App/DesktopMochi*.swift` on `upstream/main`) may be read for ideas only; never copy its names or assets.
- **Commit only in a task's commit step, and never push.**
- **Subagents are the `nm-*` agents** (Sonnet 5.5 at most, Haiku 4.5 for light work); the table below says which one runs each task.
- **If a command is denied by a permission prompt, stop and report it.**

## Review Focus

The spec says what the rules are. It is silent on these inputs, and each would bite a person (or a port) first. Each line names its test.

1. **A hostile settings file for the desktop cat:** `on` as the text `"true"` or the number 1, a size in the wrong case, a spots map that is cut-off JSON text, has `__proto__` or `constructor` keys, 300 arrangements, coordinates as text or beyond any screen, keys with a trailing newline. Expected: `on` false, `medium`, the spots that are valid in code-point order and at most 32, never a throw, nothing on `Object.prototype`. Tests: Task 4 "on is true only for…", "the spots: text that is not JSON…", "hostile files never throw…" and the 3000-case fuzz; the fixture's `settingsCases` rows.
2. **Events in the wrong order or the wrong phase:** an alert that clears mid-flight, a second alert while the cat flies back out, a `sendHome` in every phase, a `flightDone` while resting, a `toggle` mid-flight, a `dragOut` with a spot that is NaN, text or beyond the limit, a state that is not a phase, an event that is not an event. Expected: the cat turns around or carries on as the table says, never gets stuck (every phase has a way home), and anything that makes no sense changes nothing. Tests: Task 1 "an alert clearing mid-flight…", "a sendHome during an alert…", "every phase can get home…" and "events that are not events…"; the fixture's `steps` and `trips`.
3. **The screens change under the cat:** the monitor is unplugged while the cat is on it, a monitor to the left (negative coordinates), the first point of the second screen, a gap between two screens, the same frames in another order, fractional frames, a screen with no size, no screens at all. Expected: a spot on no screen goes to the main screen's default spot, the key does not depend on the order, and with no screens the answer is `null`, not a made-up spot. Tests: Task 3 "screenKey…", "clampSpot: two screens, one gone…", "spotFor…" and "rememberSpot…"; the fixture's `screenKeys`, `clamps`, `spotFor` and `remembers`.
4. **A screen too small for the cat, or an inset on the side:** a visible frame smaller than the cat and its margins, a Dock on the left, a Windows taskbar, a Large cat on a laptop, a visible frame that sticks out of or lies outside its frame. Expected: the centre when it cannot fit, the margins measured from the visible frame at every size, no cat under the menu bar or the Dock. Tests: Task 3 "clampSpot: each edge…", "clampSpot: a Dock on the side…" and the 4000-spot property test.
5. **The frame rate that lies:** a cat hidden under a fullscreen app while it flies, asleep with the cursor near, the cursor exactly 150 points away, flags that are the text "true" or the number 1, a cat at home or in the notch with everything else going on, a phase that is not a phase. Expected: 0 when it cannot be seen, 0.5 asleep, 20 at 150 and 5 at 150.01, only `true` counts. Tests: Task 2 "the frame rate: …" (five of them) and the 6000-input comparison with the rules written as a table.

---

## File Structure

| Path | Responsibility |
|---|---|
| `design/prototype/cat-core.js` | The contract. Four new sections above the end-of-core marker: "The desktop cat: the trip" (`DESKTOP_PHASES`, `DESKTOP_PHASE_INFO`, `DESKTOP_EVENTS`, `DESKTOP_ACTS`, `DESKTOP_NEXT`, `desktopStep`, `DESKTOP_FLIGHT_MS`, `DESKTOP_ARC`, `desktopFlightAt`); "size, frame rate and kittens" (`DESKTOP_SIZES`, `DESKTOP_SIZE_IDS`, `DEFAULT_DESKTOP_SIZE`, `desktopSizeOf`, `DESKTOP_FPS`, `DESKTOP_NEAR`, `desktopFps`, `DESKTOP_KITTEN_PLACE`, `desktopKittenSlots`); "spots on the screens" (`DESKTOP_MARGIN`, `DESKTOP_DEFAULT`, `MAX_DESKTOP_SPOTS`, `screenKey`, `isScreenKey`, `defaultDesktopSpot`, `clampSpot`, `cleanDesktopSpots`, `spotFor`, `rememberSpot`); "the stored settings" (`cleanDesktopSettings`, `defaultDesktopSettings`). |
| `scripts/gen-cat-fixtures.mjs` | Gains one builder above the `@@BUILDERS` marker, `FILES['desktop-cases.json']`, which each task grows above its own marker. |
| `tests/fixtures/cat/desktop-cases.json` | The new fixture (generated: about 106 KB). |
| `tests/cat/desktop.test.mjs` | The self-checks (13, 10, 13 and 7: 43) and the fixture replays (4, 2, 3 and 1: 10), grown a task at a time. |
| `tests/cat/fixtures.test.mjs` | The file list gains `desktop-cases.json` (15 files). |
| `design/prototype/notchmeow.html` | The Desktop panel: the mock screen with the notch and the draggable cat, the flight, the alert, the size picker, the frame-rate readout, the badge and kittens, the empty spot, the right-click menu, the alert flight's strip and the three sizes. |
| `docs/CAT-CONTRACT.md` | One row of the API table, one row of the fixture table, a section "The desktop cat (H-0)" and eight decisions. |
| `CLAUDE.md`, `ARCHITECT.md` | One line each. |
| `docs/superpowers/specs/2026-10-08-desktop-cat-design.md` | Five small edits, so the spec says what the contract does (the seventh phase, `desktopFlightAt`, the head's edge, the `desktop` object, the name in §4). |
| `${TMPDIR:-/tmp}/h0-shots/` | The owner's screenshots. Outside the repository, never committed. |

The "prove it bites" steps (Tasks 1 to 4) are one-offs and are never committed. **CI needs no change:** `scripts/test-cat-contract.sh`, which CI already runs, globs `tests/cat/*.test.mjs` and its `--check` covers every builder in the generator, so the new test file and fixture are picked up on their own.

**Order of tasks:** the rules and their fixtures one by one, each with its own tests (1 the trip, 2 size, frame rate and kittens, 3 spots on the screens, 4 the stored settings), then the prototype, then the screenshots for the owner's checkpoint, then the docs.

1. The trip: `desktopStep` and `desktopFlightAt`, and the first part of `desktop-cases.json`
2. Size, frame rate and kittens: `desktopFps`, `DESKTOP_SIZES` and `desktopKittenSlots`
3. Spots on the screens: `screenKey`, `clampSpot`, `spotFor` and `rememberSpot`
4. The stored settings: `cleanDesktopSettings`
5. The prototype: the Desktop panel
6. Owner checkpoint: screenshots
7. Docs and the final checks

## Tasks and agents

CLAUDE.md: the lightest model that fits. Tasks 1 to 4 and 7 give every line of their code and docs, so they are transcription: `nm-implementer-light` (Haiku 4.5). Task 5 also gives its patch in full, but it loads a page in a headless browser, clicks through it and judges what it draws, and Task 6 reads screenshots and reports what they show, so both are `nm-implementer` (Sonnet 5.5, medium). Each task is then reviewed by `nm-reviewer`; the whole branch by `nm-reviewer-deep` after Task 7. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep`.

| Task | Deliverable | Agent | Review |
|---|---|---|---|
| 1. The trip | `cat-core.js` section, `desktop.test.mjs` (13 self-checks, 4 replays), `desktop-cases.json` (phases, steps, trips, flights) | `nm-implementer-light` | `nm-reviewer` |
| 2. Size, frame rate, kittens | `cat-core.js` section, 10 self-checks, 2 replays, the fixture's sizes, fps and kitten rows | `nm-implementer-light` | `nm-reviewer` |
| 3. Spots | `cat-core.js` section, 13 self-checks, 3 replays, the fixture's screen, clamp, spot rows | `nm-implementer-light` | `nm-reviewer` |
| 4. Settings | `cat-core.js` section, 7 self-checks, 1 replay, the fixture's settings rows | `nm-implementer-light` | `nm-reviewer` |
| 5. The prototype | `notchmeow.html` patched, loaded and clicked through in a headless browser, console empty | `nm-implementer` | `nm-reviewer` |
| 6. Owner checkpoint | 8 screenshots in `${TMPDIR:-/tmp}/h0-shots`, and a stop | `nm-implementer` | the owner |
| 7. Docs, final checks | `CAT-CONTRACT.md`, two pointers, five spec edits, every check | `nm-implementer-light` | `nm-reviewer` |
| After Task 7 | The whole branch: cross-task contracts, privacy and security rules | `nm-reviewer-deep` | n/a |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). The Task 5 and 6 agents also load `playwright-cli`.

## Execution

One worktree chat session runs the whole plan: branch `h0/desktop-cat-contract`, model **Sonnet 5.5 at medium effort** (ARCHITECT.md: a plan whose tasks are mostly given in full; the prototype's visual judgement is one task and a screenshot review). Nothing is pushed. The Mac and Windows/Linux H plans are drafted from this plan's "Interface for the app plans" and start once the owner has approved the checkpoint and this branch is merged.

**Before the session starts,** the plan file is committed to `notchmeow/rebrand` (a docs-only commit): the controller does this, with the owner's OK, so the branch the session starts from already holds the plan it runs. **The base is `1627851` or later:** `git merge-base --is-ancestor 1627851 HEAD` must succeed.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c h0/desktop-cat-contract notchmeow/rebrand`, then `git merge-base --is-ancestor 1627851 HEAD` and `git ls-files docs/superpowers/plans/2026-10-08-h0-desktop-cat-contract.md`: the first must succeed and the second must print the plan's path. If either fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/CAT-CONTRACT.md`, `docs/superpowers/plans/2026-10-08-h0-desktop-cat-contract.md` and `docs/superpowers/specs/2026-10-08-desktop-cat-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message:

   > Run `docs/superpowers/plans/2026-10-08-h0-desktop-cat-contract.md` with `superpowers:subagent-driven-development`, task by task, on this branch. Dispatch each task to the agent the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. **The SDD skill's plugin scripts are refused by the auto-mode permission check here, so do not call them:** keep the ledger at `.superpowers/sdd/2026-10-08-h0-desktop-cat-contract/progress.md`, write each task brief with the Write tool just before you dispatch it, write each review's diff with `git diff` (to a file under `.superpowers/sdd/2026-10-08-h0-desktop-cat-contract/`), and create files one at a time. Put the plan's SUBAGENT RULES in every brief. **Stop after Task 6**: report the screenshot folder and file names and what each shows, and wait for the main session's go (the owner approves the look and the open questions at this checkpoint; their notes may change numbers in the core or the page, which Task 7 then documents). After the go, run Task 7, then dispatch `nm-reviewer-deep` over the whole branch. Commit only as the plan's commit steps say, and never push. Never launch a NotchMeow app. The work installs and downloads nothing (`npx --no-install` only; `playwright-cli` uses the cached browsers). Stop every server and browser you start. When you are done, report: the commits; the output of `node scripts/check-fixtures-additive.mjs 1627851`; the test count of `bash scripts/test-cat-contract.sh` and the `✓ 15 fixture files match cat-core.js` line; the Mac `scripts/test-cat-*.sh` results; the Windows `npm run check:cat` count; and anything you could not settle.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

## Interface for the app plans

What the Mac (H-mac) and Windows/Linux (H-tauri) plans consume. Names are exact: every one is a member of `CatCore` (the global on a page, `require()` in Node). Each app ports the rules natively and replays the fixture; the prototype page is the look. `docs/CAT-CONTRACT.md`, "The desktop cat (H-0)", has the notes for ports (Task 7 writes it).

### 1. The trip: `desktopStep` and `desktopFlightAt`

| Name | Signature and meaning |
|---|---|
| `DESKTOP_PHASES` | `['home', 'flyingOut', 'onDesktop', 'retracting', 'atNotchForAlert', 'returning', 'flyingHome']`. Contract values, pinned by the fixture (never stored, so not frozen like the cat IDs). |
| `DESKTOP_PHASE_INFO` | phase → `{flight, dir ('out', 'in' or null), drawn, notchEmpty, on}`: in the air, which way, the desktop window draws it, the notch's big-cat spot is empty, Settings stores it as "out". |
| `DESKTOP_EVENTS` | The nine event types. `dragOut` and `move` carry `spot: {x, y}`; the rest carry nothing. |
| `desktopStep(state, event)` | `{state, act}`. `act` is one of `DESKTOP_ACTS` or `null` (the event makes no sense there, or has a bad spot, and nothing changed). |
| `DESKTOP_ACTS` | `place`, `flyOut`, `flyHome`, `retract`, `turn`, `keep`, `land`, `dock`, `goHome`, `move`, `resettle`: what the app does (see the doc's "The trip"). |
| `DESKTOP_NEXT`, `DESKTOP_FLIGHT_MS`, `DESKTOP_ARC` | The transition table (phase → event → `[next phase, act]`), 600, and `{lift: 0.25, max: 90}`: pinned by `steps`, `flightMs` and `arc`. |
| `desktopFlightAt(from, to, t)` | `{x, y, scale}`: the cat `t` (0 to 1) of the way along a 600 ms flight (`DESKTOP_FLIGHT_MS`) between two spots. An arc bowing upwards by a quarter of the distance (at most 90 pt), eased in and out, `scale` 1. `(from, to, t)` and `(to, from, 1 - t)` are the same point, so a turn-around carries on from `1 - t`. |

**What each app does.** The app owns the phase, the flight's clock and the spot; the core owns the rules. On every event: `const r = desktopStep(phase, event); phase = r.state;` then act on `r.act`:
- `place`, `move`: take `event.spot`, store `rememberSpot(spots, screens, event.spot, size)` and read the spot back with `spotFor`. `resettle`: `spotFor` again (a flight in progress re-aims at it).
- `flyOut`, `flyHome`, `retract`: start the flight clock (`retract` plays the surprised emote first and starts the flight about 0.35 s later). `flyOut` runs from the notch spot to the spot; `flyHome` and `retract` from where the cat is on screen (its spot, or the drop point for a cat dropped on the notch) to the notch spot. The notch spot is the big cat's place in the island: its compact place, or its expanded place when the island opens for an alert.
- `turn`: keep the clock, swap the flight's ends and start at progress `1 - t`. `keep`: nothing. `land`: the cat rests at its spot. `dock`, `goHome`: the notch shows the cat again and the desktop window shows nothing.
- `flightDone` is the app's own event: send it when the flight's clock reaches 600 ms.
- Where the cat is each frame is `desktopFlightAt` while `DESKTOP_PHASE_INFO[phase].flight`, the pointer while it is dragged, else its spot. The cat is at its desktop size the whole way (the spec); a flight that ends at the compact notch pops from the desktop size to Ø20 at the last frame, as the prototype shows (open question 7).
- **`alertOn`** is sent when `pendingApproval` or `pendingQuestion` becomes set (Mac `AppState.pendingApproval` and `pendingQuestion`; Windows `State.pendingApproval` and a task in the `question` state, set in `island/hooks.ts`), **`alertOff`** when both are clear; **`launch`** after the greeting, only when the stored `on` is true; **`screensChanged`** when the connected screens change.
- The label of the menu-bar item (the tray item) is `DESKTOP_PHASE_INFO[phase].on ? 'Bring the cat home' : 'Cat on the desktop'`. Dropping the cat on the island is `sendHome`; a double-click is `sendHome` after one double-click interval of waiting for a second click; a single click waits that interval, then opens the island with the happy emote.

### 2. Size, frame rate and kittens

| Name | Signature and meaning |
|---|---|
| `DESKTOP_SIZES`, `DESKTOP_SIZE_IDS`, `DEFAULT_DESKTOP_SIZE`, `desktopSizeOf(v)` | `{small: 48, medium: 64, large: 96}`, the IDs in Settings order, `'medium'`, and the clean-up of a stored size (anything else is `'medium'`). |
| `desktopFps({phase, hidden, dragging, emote, kittenMotion, dance, asleep, working, cursorDist})` | 0, 60, 0.5, 20 or 5 (`DESKTOP_FPS`): in that order: 0 when the phase is not drawn on the desktop or `hidden`; 60 for a flight or any motion flag; 0.5 asleep; 20 working or the cursor within `DESKTOP_NEAR` (150) points; else 5. Only `true` counts for a flag. |
| `desktopKittenSlots(kittens, side)` | `{place: 'desktop', unit: 'D', count, shown: [{id, state, x, y, d}], more, moreAt, label: null}` for the kittens of `kittenView`: up to 3 in a row at the lower right of the cat, then a "+N". Multiples of D, the cat's head width, from its head centre (x right, y down). `side` -1 mirrors every x. Draw a kitten as a cat of head width `d * D` at `centre + (x, y) * D`, in `kittenOf(the big cat's coat)`, with the agent's collar and its own state badge. |

- **The loop.** The app's frame loop reads `desktopFps` each frame and draws only when the time since the last drawn frame reaches `1000 / fps` (0 draws nothing and clears the window once). Nothing new polls: the Mac watches the cursor with a mouse-moved event monitor that exists only while the cat is out (spec §3), and passes `cursorDist` in points from the cursor to the cat's centre; on Wayland, where the cursor is known only over the app's own surface, leave `cursorDist` out unless the cursor is over the cat. `asleep` is the existing ten-minute sleep; clear it the moment a hover, a click or an agent event wakes the cat.
- **Which side.** Put the kittens on the left (`side` -1) when the cat's centre is in the right half of its screen's visible frame, else on the right: the prototype's rule. The contract gives both layouts and the apps pick one.
- **The window and the body.** Size the desktop window (panel) for the cat's head, ears and badge (from `layout()`, as the renderer already does) and the kittens' slots for the side in use, with no more than the glow needs. The body that takes the mouse is the head circle (radius 0.55 D), the badge circle and the kitten and "+N" slots; everything else passes through (the prototype's "Hit area" shows the circles). That is layout, not contract.

### 3. Spots on the screens

| Name | Signature and meaning |
|---|---|
| `screenKey(screens)` | The key an arrangement is remembered under: the frames rounded half up, sorted, `x,y,w,h` joined by `\|`; `""` with no usable screen. Independent of the order of the screens, of the visible frames and of the main flag. |
| `isScreenKey(key)` | True for exactly the strings `screenKey` writes (whole-string match). |
| `clampSpot(spot, screens, size)` | The spot held on the screen whose frame holds it, inside its visible frame, 24 pt plus half the head from every edge; a spot on no screen, or not a spot, is the default spot; `null` with no screens. `size` is a size ID. |
| `defaultDesktopSpot(screens, size)` | 0.6 across and a third down the main screen's visible frame (the one marked `main`, else the one holding the origin, else the first by frame), held inside its margins. |
| `spotFor(spots, screens, size)` | The spot remembered for this arrangement, clamped, else the default. |
| `rememberSpot(spots, screens, spot, size)` | The map with this arrangement's clamped spot (at most 32 arrangements; the one just written is always kept). |
| `cleanDesktopSpots(raw)` | An object, or the JSON text of one, to `{screenKey: {x, y}}`: only keys `isScreenKey` accepts and values that are spots, in code-point order, the first 32. |
| `DESKTOP_MARGIN` (24), `DESKTOP_DEFAULT` (`{x: 0.6, y: 1/3}`), `MAX_DESKTOP_SPOTS` (32) | The numbers. |

A screen is `{frame: {x, y, w, h}, visible: {x, y, w, h}, main: true}` in points, y down, the origin at the top left of the main screen. **Mac:** `NSScreen.frame` and `visibleFrame` converted from AppKit's bottom-left origin (`yTop = primaryHeight - frame.maxY`); `main` is the screen with the menu bar (`NSScreen.screens[0]`). **Windows:** each monitor's rectangle and work area (the taskbar is outside the work area); the primary monitor is `main`. **Linux:** the compositor's output geometry; a layer-shell surface's exclusive zones give the visible frame; where the compositor does not say, `visible` is the frame. Send `screensChanged` when the arrangement changes (NSApplication's screen-parameters notification, the monitors-changed event).

### 4. The stored settings: `cleanDesktopSettings`

| Name | Signature and meaning |
|---|---|
| `cleanDesktopSettings(raw)` | `{on, size, spots}`: `on` true only for the boolean true, `size` one of the three IDs (else `'medium'`), `spots` as `cleanDesktopSpots`. Never throws. |
| `defaultDesktopSettings()` | `{on: false, size: 'medium', spots: {}}`. |

| macOS (`UserDefaults`) | Raw field |
|---|---|
| `cat.desktop.on` | `on` (read the object and check for a boolean: `UserDefaults.bool(forKey:)` turns `"true"` and 1 into `true`) |
| `cat.desktop.size` | `size` |
| `cat.desktop.spots` | `spots`, as the JSON text of the map |

Windows and Linux keep `{on, size, spots}` as the `desktop` object of the `cat` block of `settings.json` (`spots` an object). **`windows/src-tauri/src/settings.rs` (`sanitized`) rebuilds the `cat` block through `clean_cat_block`:** H-tauri must carry the `desktop` object through (a `clean_desktop_settings` next to the display one in `cat_settings.rs`), or the next save drops it, exactly as B's keys needed. The Mac side: `CatSettingsStore` builds the raw value from UserDefaults as plain JSON values, runs a Swift port of `cleanDesktopSettings`, and uses only the result. **Call the three clean-ups (`cleanCatSettings`, `cleanDisplaySettings`, `cleanDesktopSettings`) on the same stored block;** none of them sees the others' keys. Settings → Cat gets a "Cat on the desktop" switch under the Display picker (on GNOME a note: the system may ignore the position); Settings → Shortcuts lists the `desktop` action.

### 5. Platform notes (from the spec, for the app plans)

- **Mac window:** a borderless, non-activating floating `NSPanel` that is never key, so it never steals focus; it joins all Spaces, stays out of fullscreen Spaces (fullscreen auxiliary off) and is excluded from the window cycle; click-through follows the body's shape (the panel's `ignoresMouseEvents` toggled from the mouse position, as `IslandWindowController` does for the island). In Debug, Release and App Store builds; `scripts/check-app-binary.sh` keeps passing. A flight moves the panel's frame along `desktopFlightAt` each frame.
- **Mac shortcut and menu:** a `desktop` case in `ShortcutAction` (`ShortcutLogic.swift`), ⌃⌥D, on by default, listed in Settings → Shortcuts and tested by `scripts/test-shortcuts.sh`; `HotKeyCenter.swift` registers it. The menu-bar item is in `AppDelegate`'s `statusItem` menu. A debug bench `render-cats.sh --bench-desktop` measures each rate.
- **The Mac drop rule (the existing drag-to-attach):** the big cat is dragged out of the island by the existing window attach drag (`IslandWindowController`: `attachDragStart`, `inAttachDrag`, the ghost panel and `updateWindowHighlight`). On release over another app's window the cat still attaches that window to a chat, exactly as today; only a release over no window places the cat (`dragOut`). The App Store build has no attach, so there any drop places the cat. Test the rule so attaching keeps working as it does today.
- **Windows:** a second transparent, borderless, always-on-top Tauri window, skipped in the taskbar; it takes the mouse only over the body, with the same click-through mechanism as the island (`set_ignore_cursor_events` in `windows/src-tauri/src/island.rs`). The tray item is in `tray.rs` (`Open`, `Settings…`, `Pause`, `Quit`: add the cat's item). Global shortcuts are out of scope on Windows and Linux.
- **Linux:** on compositors with layer-shell (KDE Plasma, COSMIC, Hyprland, Sway and other wlroots) an overlay-layer surface placed with margins; on GNOME, where the island is already a regular window, a small always-on-top window, and GNOME may ignore the position, so the spot is remembered only where the system honours it and Settings says so. Wayland gives an app the cursor only over its own surface: the cat looks ahead unless the cursor is over it.
- **What it shows:** the big cat's coat from `castOf` (One cat: the Main cat; A cat for each agent: the focused agent's cat; Two cats: cat 1, Momo stays in the notch), the state badge of its role, its agent's kittens, its collar, cursor-watching, the music dance (Mac), the ten-minute sleep with the sweep of stale kittens, full detail (no small eyes below Ø28 here, so they never apply). Not on the desktop cat: dropping files, the slap, the hairball. The island and every existing view look exactly as they ship; the one change in the notch is the empty big-cat spot while the cat is out (`DESKTOP_PHASE_INFO[phase].notchEmpty`).

### 6. The fixture

| Key | Rows | Replay |
|---|---|---|
| `phaseIds`, `phases`, `events`, `acts`, `flightMs`, `arc` | the constants | compare with the app's constants |
| `steps` | 89 `{state, event, out}`: all 63 pairs, then input that is not a phase or an event | `desktopStep` |
| `trips` | 11 `{name, from, events, out}`: the whole trip, an alert that clears mid-flight, a `sendHome` during an alert (in the notch and in flight), a change of mind in flight, … | `desktopStep` over the events, comparing the state and act after each |
| `flights` | 89 `{name, from, to, t, out}`: nine routes at nine `t` (out of range included), then bad inputs | `desktopFlightAt` |
| `sizes`, `sizeIds`, `defaultSize`, `sizeCases` | the sizes and 17 `{raw, out}` | `desktopSizeOf` |
| `fps`, `near`, `fpsCases` | the rates and 39 `{name, input, out}`: every row of the table | `desktopFps` |
| `kittenPlace`, `kittenSlots`, `kittenSizes` | the place; 21 `{name, kittens, side, out}` (0, 1, 2, 3, 4 and 8 kittens on both sides, then bad input); 12 `{size, d, count, shown, more, moreAt}` in points | `desktopKittenSlots` |
| `margin`, `defaultSpot`, `maxSpots` | the numbers | compare |
| `screenKeys`, `isScreenKey` | 19 `{name, screens, out}` and 30 `{key, out}` | `screenKey`, `isScreenKey` |
| `clamps` | 54 `{name, spot, screens, size, out}`: each edge of a laptop at the three sizes, a Dock on the left, a taskbar, a small screen, two screens, a screen gone, a gap, bad spots, no screens | `clampSpot` |
| `defaultSpots`, `spotFor`, `remembers`, `spotMaps` | 8, 13, 8 and 18 rows | `defaultDesktopSpot`, `spotFor`, `rememberSpot`, `cleanDesktopSpots` |
| `settingsDefaults`, `settingsCases` | the defaults and 41 `{name, raw, out}`, with the 300-arrangement block written out in full | `cleanDesktopSettings` |

The file has `version` 1 and `tolerance` 1e-9. **JSON cannot hold `undefined`, NaN or Infinity,** so the fixture uses a missing key, `null` or text, and each port adds its own tests for a `t`, a spot or a `cursorDist` that is not finite. A missing `side` or `size` is a missing key.

### 7. The look: what the prototype shows, for the app plans to match

`design/prototype/notchmeow.html` after Task 5, the Desktop panel: `dkScene` (the mock screen: wallpaper, two windows, the Dock, the menu bar, the island, the empty spot), `dkCatDraw` and `dkKittens` (the cat, its badge and `desktopKittenSlots`), `dkSend` (every event goes through `desktopStep` and the page does what `act` says), `drawDesktop` (the base canvas every frame, the cat canvas at `desktopFps`), `drawStrip` (the alert flight) and `drawSizes` (the three sizes, with the body outlined). The page's layout numbers (the mock is 960 by 540 points, a menu bar of 32 and a Dock of 64) are a reference, not part of the contract.

**Not in H-0:** any app code; the Settings switch and the menus; the window and its click-through; the bench numbers (the app plans measure them); sounds for the trip; what the desktop window looks like at its edges (glow, shadow).

---

### Task 1: The trip: `desktopStep` and `desktopFlightAt`

**Files:**
- Modify: `design/prototype/cat-core.js` (a new section above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (a builder above the `@@BUILDERS` marker), `tests/cat/fixtures.test.mjs` (the file list)
- Create: `tests/cat/desktop.test.mjs`, `tests/fixtures/cat/desktop-cases.json` (generated)

**Interfaces:**
- Consumes from the core: `EZ`, `clamp`, `own`, `isPlain`; from the generator: `compare`, `fix`, `format`, `finish`, `FILES`.
- Produces in `CatCore`: `DESKTOP_PHASES`, `DESKTOP_PHASE_INFO`, `DESKTOP_EVENTS`, `DESKTOP_ACTS`, `DESKTOP_NEXT`, `desktopStep`, `DESKTOP_FLIGHT_MS`, `DESKTOP_ARC`, `desktopFlightAt`, exactly as in "Interface for the app plans" section 1; and the first keys of `desktop-cases.json` (`phaseIds`, `phases`, `events`, `acts`, `flightMs`, `arc`, `steps`, `trips`, `flights`). The section also holds `dkSpot` (a spot or `null`, not exported), which Tasks 2 to 4 reuse.

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/cat/desktop.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const roundTrip = v => JSON.parse(JSON.stringify(v));
const PHASES = core.DESKTOP_PHASES, EVENTS = core.DESKTOP_EVENTS, INFO = core.DESKTOP_PHASE_INFO;
const SPOT = { x: 640, y: 300 };
const ev = type => (type === 'dragOut' || type === 'move' ? { type, spot: SPOT } : { type });
const step = (state, type) => core.desktopStep(state, ev(type));
const near = (a, b, msg) => assert.ok(Math.abs(a - b) <= 1e-9, `${msg}: ${a} vs ${b}`);

test('the frozen values: seven phases, nine events, the acts, a flight of 600 ms', () => {
  assert.deepEqual(PHASES, ['home', 'flyingOut', 'onDesktop', 'retracting', 'atNotchForAlert', 'returning', 'flyingHome']);
  assert.deepEqual(EVENTS, ['dragOut', 'move', 'toggle', 'sendHome', 'alertOn', 'alertOff', 'flightDone', 'launch', 'screensChanged']);
  assert.deepEqual(core.DESKTOP_ACTS, ['place', 'flyOut', 'flyHome', 'retract', 'turn', 'keep', 'land', 'dock', 'goHome', 'move', 'resettle']);
  assert.equal(core.DESKTOP_FLIGHT_MS, 600);
  assert.deepEqual(Object.keys(INFO), PHASES);
  assert.deepEqual(Object.keys(core.DESKTOP_NEXT), PHASES);
});

test('the older flight is untouched: flightAt and FLIGHT_MS still belong to the file catch', () => {
  assert.equal(typeof core.desktopFlightAt, 'function');
  assert.equal(core.FLIGHT_MS, 380);
  assert.deepEqual(Object.keys(core.flightAt({ x: 0, y: 0 }, { x: 10, y: 10 }, 20, .5)).sort(), ['rot', 'size', 'x', 'y']);
  assert.notEqual(core.desktopFlightAt, core.flightAt);
});

test('every phase and event pair answers with a phase and an act, and the table says which ones do something', () => {
  let moves = 0;
  for (const s of PHASES) for (const type of EVENTS) {
    const r = step(s, type), listed = Object.prototype.hasOwnProperty.call(core.DESKTOP_NEXT[s], type);
    assert.deepEqual(Object.keys(r), ['state', 'act'], `${s} + ${type}`);
    assert.ok(PHASES.includes(r.state), `${s} + ${type}`);
    if (listed) { moves++; assert.ok(core.DESKTOP_ACTS.includes(r.act), `${s} + ${type} has an act`); assert.deepEqual(core.DESKTOP_NEXT[s][type], [r.state, r.act]); }
    else assert.deepEqual(r, { state: s, act: null }, `${s} + ${type} makes no sense and changes nothing`);
  }
  assert.equal(PHASES.length * EVENTS.length, 63);
  assert.equal(moves, 27, 'the table lists 27 pairs that do something');
});

test('the whole trip: out, an alert to the notch and back, home', () => {
  const run = (from, types) => types.reduce((acc, t) => { const r = step(acc.at(-1).state, t); return [...acc, r]; }, [{ state: from, act: null }]).slice(1);
  assert.deepEqual(run('home', ['toggle', 'flightDone', 'alertOn', 'flightDone', 'alertOff', 'flightDone', 'sendHome', 'flightDone']).map(r => `${r.state}:${r.act}`), [
    'flyingOut:flyOut', 'onDesktop:land', 'retracting:retract', 'atNotchForAlert:dock', 'returning:flyOut', 'onDesktop:land', 'flyingHome:flyHome', 'home:dock']);
  assert.deepEqual(step('home', 'dragOut'), { state: 'onDesktop', act: 'place' }, 'dropping the cat on the desktop places it, no flight');
  assert.deepEqual(step('home', 'launch'), { state: 'flyingOut', act: 'flyOut' }, 'a cat that was out flies out after the greeting');
});

test('an alert clearing mid-flight turns the cat around, and so does every change of mind', () => {
  assert.deepEqual(step('retracting', 'alertOff'), { state: 'returning', act: 'turn' });
  assert.deepEqual(step('returning', 'alertOn'), { state: 'retracting', act: 'turn' });
  assert.deepEqual(step('flyingOut', 'alertOn'), { state: 'retracting', act: 'turn' });
  assert.deepEqual(step('flyingOut', 'sendHome'), { state: 'flyingHome', act: 'turn' });
  assert.deepEqual(step('returning', 'sendHome'), { state: 'flyingHome', act: 'turn' });
  assert.deepEqual(step('flyingHome', 'toggle'), { state: 'flyingOut', act: 'turn' });
  // The rule behind the three words: both phases fly, the direction differs: turn; the same direction: keep. Nothing else is turn or keep.
  for (const a of PHASES) for (const type of EVENTS) {
    const r = step(a, type), flights = INFO[a].flight && INFO[r.state].flight && r.state !== a;
    assert.equal(r.act === 'turn', flights && INFO[a].dir !== INFO[r.state].dir, `${a} + ${type}`);
    assert.equal(r.act === 'keep', flights && INFO[a].dir === INFO[r.state].dir, `${a} + ${type}`);
  }
});

test('a sendHome during an alert ends the trip at home, and an alert at home takes nothing out', () => {
  assert.deepEqual(step('retracting', 'sendHome'), { state: 'flyingHome', act: 'keep' }, 'already flying to the notch: it just carries on, and ends at home');
  assert.deepEqual(step('atNotchForAlert', 'sendHome'), { state: 'home', act: 'goHome' });
  assert.deepEqual(step('atNotchForAlert', 'toggle'), { state: 'home', act: 'goHome' });
  assert.deepEqual(step('flyingHome', 'flightDone'), { state: 'home', act: 'dock' });
  assert.deepEqual(step('flyingHome', 'alertOn'), { state: 'flyingHome', act: null }, 'an alert during the flight home does not bring it back out');
  assert.deepEqual(step('home', 'alertOn'), { state: 'home', act: null });
  assert.deepEqual(step('home', 'alertOff'), { state: 'home', act: null });
  assert.deepEqual(step('home', 'sendHome'), { state: 'home', act: null });
  assert.deepEqual(step('onDesktop', 'alertOff'), { state: 'onDesktop', act: null });
  assert.deepEqual(step('atNotchForAlert', 'alertOn'), { state: 'atNotchForAlert', act: null });
});

test('the phases agree with their acts, and there are never two copies of one cat', () => {
  for (const s of PHASES) {
    assert.ok(!INFO[s].drawn || INFO[s].notchEmpty, `${s}: drawn on the desktop means the notch spot is empty`);
    assert.equal(INFO[s].flight, INFO[s].dir !== null, `${s}: a direction exactly when it flies`);
    for (const [type, [next, act]] of Object.entries(core.DESKTOP_NEXT[s])) {
      const N = INFO[next], at = `${s} + ${type}`;
      if (act === 'flyOut') assert.ok(N.flight && N.dir === 'out', at);
      if (act === 'flyHome' || act === 'retract') assert.ok(N.flight && N.dir === 'in', at);
      if (act === 'land') assert.ok(INFO[s].flight && next === 'onDesktop', at);
      if (act === 'dock') assert.ok(INFO[s].flight && !N.flight && !N.drawn && !N.notchEmpty, at);
      if (act === 'goHome') assert.ok(next === 'home' && !INFO[s].flight, at);
      if (act === 'place') assert.ok(s === 'home' && next === 'onDesktop', at);
      if (act === 'move' || act === 'resettle') assert.equal(next, s, at);
    }
  }
  assert.deepEqual(PHASES.filter(p => INFO[p].on), ['flyingOut', 'onDesktop', 'retracting', 'atNotchForAlert', 'returning'], 'the five that Settings stores as "out"');
});

test('every phase can get home, and no event sequence ever leaves the seven phases: 20000 random events', () => {
  const home = new Set(['home']);
  for (let again = true; again;) { again = false; for (const s of PHASES) if (!home.has(s) && EVENTS.some(t => home.has(step(s, t).state))) { home.add(s); again = true; } }
  assert.equal(home.size, 7, 'a path to home from every phase');
  const r = core.rng(8), pick = a => a[Math.floor(r() * a.length)];
  let s = 'home';
  for (let i = 0; i < 20000; i++) { const t = pick(EVENTS), out = core.desktopStep(s, ev(t)); assert.ok(PHASES.includes(out.state)); s = out.state; }
});

test('events that are not events, spots that are not spots and states that are not phases change nothing', () => {
  for (const bad of [null, undefined, 'toggle', 7, [], ['toggle'], {}, { type: 7 }, { type: ['toggle'] }, { type: null }, { type: 'Toggle' }, { type: 'toggle ' }, { type: '__proto__' }, { type: 'constructor' }, { type: 'hasOwnProperty' }, { type: 'launch2' }])
    assert.deepEqual(core.desktopStep('onDesktop', bad), { state: 'onDesktop', act: null }, JSON.stringify(bad));
  for (const type of ['dragOut', 'move']) {
    const from = type === 'dragOut' ? 'home' : 'onDesktop';
    assert.equal(core.desktopStep(from, { type, spot: { x: 1, y: 2 } }).act, type === 'dragOut' ? 'place' : 'move');
    for (const spot of [undefined, null, 7, 'x', [], [1, 2], {}, { x: 1 }, { y: 2 }, { x: '1', y: 2 }, { x: NaN, y: 2 }, { x: 1, y: Infinity }, { x: true, y: 2 }, { x: 1e6, y: 2 }, { x: 1, y: -1e6 }])
      assert.deepEqual(core.desktopStep(from, { type, spot }), { state: from, act: null }, `${type} ${String(JSON.stringify(spot))}`);
  }
  for (const bad of ['', 'Home', 'home ', 'fly', null, undefined, 7, ['home'], {}, '__proto__', 'constructor']) {
    assert.deepEqual(core.desktopStep(bad, { type: 'sendHome' }), { state: 'home', act: null }, String(bad));
    assert.deepEqual(core.desktopStep(bad, { type: 'toggle' }), { state: 'flyingOut', act: 'flyOut' }, 'a state that is not a phase counts as home');
  }
  const frozen = Object.freeze({ type: 'move', spot: Object.freeze({ x: 5, y: 6 }) });
  assert.doesNotThrow(() => core.desktopStep('onDesktop', frozen));
});

test('desktopFlightAt: the ends, the clamping and the full size', () => {
  const a = { x: 480, y: 16 }, b = { x: 576, y: 180 };
  assert.deepEqual(core.desktopFlightAt(a, b, 0), { x: 480, y: 16, scale: 1 });
  const end = core.desktopFlightAt(a, b, 1);
  near(end.x, 576, 'x at 1'); near(end.y, 180, 'y at 1'); assert.equal(end.scale, 1);
  for (const t of [-5, -0.001, -Infinity]) assert.deepEqual(core.desktopFlightAt(a, b, t), core.desktopFlightAt(a, b, 0), `t ${t}`);
  for (const t of [1.001, 2, 1e9, Infinity]) assert.deepEqual(core.desktopFlightAt(a, b, t), core.desktopFlightAt(a, b, 1), `t ${t}`);
  for (const t of [NaN, undefined, null, '0.5', [], {}]) assert.deepEqual(core.desktopFlightAt(a, b, t), core.desktopFlightAt(a, b, 0), `t ${String(t)}`);
  for (let i = 0; i <= 100; i++) assert.equal(core.desktopFlightAt(a, b, i / 100).scale, 1, 'the cat keeps its size the whole way');
});

test('desktopFlightAt: an arc that bows upwards, eased, that never overshoots its ends', () => {
  const a = { x: 480, y: 16 }, b = { x: 576, y: 180 }, mid = core.desktopFlightAt(a, b, .5);
  assert.ok(mid.y < (a.y + b.y) / 2 - 1, 'the middle of the flight is above the straight line');
  assert.ok(mid.x > (a.x + b.x) / 2, 'and so to the right of it, on a flight that goes down and right');
  const slow = core.desktopFlightAt(a, b, .1), fast = core.desktopFlightAt(a, b, .4);
  assert.ok(Math.hypot(slow.x - a.x, slow.y - a.y) < Math.hypot(fast.x - slow.x, fast.y - slow.y), 'it starts slowly: the first tenth covers less than the next three');
  let prev = 0;
  for (let i = 1; i <= 200; i++) { const p = core.desktopFlightAt(a, b, i / 200), d = Math.hypot(p.x - a.x, p.y - a.y); assert.ok(d >= prev - 1e-9 || i / 200 > .5, 'the distance from the start grows until the middle'); prev = d; }
  // The lift is a quarter of the distance, never more than 90 points, and a flight of no distance does not move.
  const far = core.desktopFlightAt({ x: 0, y: 0 }, { x: 3000, y: 0 }, .5);
  near(far.x, 1500, 'a flat flight, x'); near(far.y, -45, 'the lift is 90 at the top of the curve, so 45 at the middle of the path (half of it)');
  assert.deepEqual(core.desktopFlightAt({ x: 5, y: 5 }, { x: 5, y: 5 }, .5), { x: 5, y: 5, scale: 1 });
  const down = core.desktopFlightAt({ x: 100, y: 0 }, { x: 100, y: 400 }, .5);
  assert.ok(down.x > 100, 'a vertical flight bows to the right');
  const up = core.desktopFlightAt({ x: 100, y: 400 }, { x: 100, y: 0 }, .5);
  near(up.x, down.x, 'the same bow on the way back');
});

test('desktopFlightAt: the path is the same both ways, so a flight that turns around retraces itself', () => {
  const r = core.rng(3), pt = () => ({ x: Math.round(r() * 3000 - 500), y: Math.round(r() * 1600 - 200) });
  for (let i = 0; i < 400; i++) {
    const a = pt(), b = pt(), t = r();
    const there = core.desktopFlightAt(a, b, t), back = core.desktopFlightAt(b, a, 1 - t);
    near(there.x, back.x, `x ${JSON.stringify([a, b, t])}`); near(there.y, back.y, `y ${JSON.stringify([a, b, t])}`);
  }
  for (const [a, b] of [[{ x: 0, y: 0 }, { x: 0, y: 300 }], [{ x: 0, y: 0 }, { x: 300, y: 0 }], [{ x: 50, y: 50 }, { x: 50, y: 50 }]])
    for (const t of [0, .25, .5, .8, 1]) { const p = core.desktopFlightAt(a, b, t), q = core.desktopFlightAt(b, a, 1 - t); near(p.x, q.x, 'x'); near(p.y, q.y, 'y'); }
});

test('desktopFlightAt: ends that are not points count as 0, 0 and nothing throws', () => {
  for (const bad of [null, undefined, 7, 'x', [], {}, { x: 1 }, { x: NaN, y: 1 }, { x: '1', y: 1 }, { x: 1e9, y: 1 }]) {
    assert.deepEqual(core.desktopFlightAt(bad, { x: 100, y: 100 }, 0), { x: 0, y: 0, scale: 1 }, String(JSON.stringify(bad)));
    const end = core.desktopFlightAt({ x: 100, y: 100 }, bad, 1); near(end.x, 0, 'x'); near(end.y, 0, 'y');
  }
  const r = core.rng(21), junk = [null, undefined, NaN, Infinity, -1, 0, 1, 2, 1e300, 'a', {}, [], { x: 1, y: 2 }, { x: 1e5, y: -1e5 }];
  for (let i = 0; i < 2000; i++) { const p = core.desktopFlightAt(junk[Math.floor(r() * junk.length)], junk[Math.floor(r() * junk.length)], junk[Math.floor(r() * junk.length)]); assert.ok(Number.isFinite(p.x) && Number.isFinite(p.y) && p.scale === 1); }
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 13`, `# pass 0`, `# fail 13`: the core has no `desktopStep` yet.

- [ ] **Step 3: Add the section to the core**

This inserts "The desktop cat: the trip" above the `@@END-OF-CORE` marker, after the small eyes. It reuses `EZ`, `clamp`, `own` and `isPlain`; nothing else in the file changes.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── The desktop cat: the trip (sub-project H) ────────────────────────────────
// The big cat can leave the notch and live on the desktop. desktopStep is the one machine for its trip and desktopFlightAt the flight between the notch and
// the desktop. A "spot" is the cat's head centre on the desktop, in points, y down, the origin at the top left of the main screen. Everything here is new
// names: nothing above this section changed, and the apps' copies of the older rules (KITTEN_PLACES, kittenSlots, flightAt, the cleaners) stay valid.
/**
 * The phases of the trip. Frozen contract values, like the cat IDs. The spec lists six; flyingHome is the seventh: a double-click, the menu or the switch
 * "flies it home", and none of the six is that flight (retracting ends at the notch spot for an alert, flyingHome ends at home).
 */
const DESKTOP_PHASES=['home','flyingOut','onDesktop','retracting','atNotchForAlert','returning','flyingHome'];
/**
 * What each phase means to an app. flight: the cat is in the air. dir: 'out' flies towards the desktop spot, 'in' towards the notch spot.
 * drawn: the desktop window draws the cat. notchEmpty: the big cat's spot in the notch is empty (never two copies of one cat: drawn implies notchEmpty).
 * on: what Settings stores as "the cat is out". home and flyingHome are off, so quitting mid-flight leaves the cat home.
 */
const DESKTOP_PHASE_INFO={
 home:{flight:false,dir:null,drawn:false,notchEmpty:false,on:false},
 flyingOut:{flight:true,dir:'out',drawn:true,notchEmpty:true,on:true},
 onDesktop:{flight:false,dir:null,drawn:true,notchEmpty:true,on:true},
 retracting:{flight:true,dir:'in',drawn:true,notchEmpty:true,on:true},
 atNotchForAlert:{flight:false,dir:null,drawn:false,notchEmpty:false,on:true},
 returning:{flight:true,dir:'out',drawn:true,notchEmpty:true,on:true},
 flyingHome:{flight:true,dir:'in',drawn:true,notchEmpty:true,on:false}};
/**
 * The events desktopStep takes. dragOut and move carry a `spot` {x, y}; the others carry nothing.
 *   dragOut{spot}  the big cat was dropped on the desktop         move{spot}   the desktop cat was dragged to a new spot
 *   toggle         the menu-bar item, ⌃⌥D or the Settings switch  sendHome     a double-click, "Send home", or the cat dropped on the notch
 *   alertOn        an approval or a question became pending       alertOff     both are clear         flightDone  a flight reached its end
 *   launch         the app started after the greeting and the cat was out         screensChanged   the connected screens changed
 */
const DESKTOP_EVENTS=['dragOut','move','toggle','sendHome','alertOn','alertOff','flightDone','launch','screensChanged'];
/**
 * What an app does on a transition (the `act` desktopStep returns; null means nothing). Flights go between the notch spot and the desktop spot.
 *   place     the cat was dropped at event.spot: show it there, no flight        flyOut    fly from the notch spot to the desktop spot
 *   flyHome   fly from the desktop spot to the notch spot                          retract   the surprised emote, then fly from the desktop spot to the notch spot
 *   turn      reverse the flight in progress: carry on the other way from progress 1 - t (desktopFlightAt retraces its own path)
 *   keep      the flight goes on the same way under its new phase; nothing to show   land   the flight ended at the desktop spot
 *   dock      the flight ended at the notch spot: the notch shows the cat again       goHome the cat was already in the notch spot: it is simply back there
 *   move      the dragged cat was released at event.spot: clamp it (clampSpot) and save it
 *   resettle  the screens changed: find the spot again (spotFor) and put the cat there
 */
const DESKTOP_ACTS=['place','flyOut','flyHome','retract','turn','keep','land','dock','goHome','move','resettle'];
/** phase → event → [next phase, act]. An event that is not listed makes no sense in that phase and changes nothing. */
const DESKTOP_NEXT={
 home:{dragOut:['onDesktop','place'],toggle:['flyingOut','flyOut'],launch:['flyingOut','flyOut']},
 flyingOut:{toggle:['flyingHome','turn'],sendHome:['flyingHome','turn'],alertOn:['retracting','turn'],flightDone:['onDesktop','land'],screensChanged:['flyingOut','resettle']},
 onDesktop:{move:['onDesktop','move'],toggle:['flyingHome','flyHome'],sendHome:['flyingHome','flyHome'],alertOn:['retracting','retract'],screensChanged:['onDesktop','resettle']},
 retracting:{toggle:['flyingHome','keep'],sendHome:['flyingHome','keep'],alertOff:['returning','turn'],flightDone:['atNotchForAlert','dock']},
 atNotchForAlert:{toggle:['home','goHome'],sendHome:['home','goHome'],alertOff:['returning','flyOut']},
 returning:{toggle:['flyingHome','turn'],sendHome:['flyingHome','turn'],alertOn:['retracting','turn'],flightDone:['onDesktop','land'],screensChanged:['returning','resettle']},
 flyingHome:{toggle:['flyingOut','turn'],flightDone:['home','dock']}};
/** A spot is {x, y} of finite numbers no larger than 100000 in size. */
const SPOT_LIMIT=1e5;
const dkSpot=v=>isPlain(v)&&typeof v.x==='number'&&typeof v.y==='number'&&Math.abs(v.x)<=SPOT_LIMIT&&Math.abs(v.y)<=SPOT_LIMIT?{x:v.x,y:v.y}:null;
/**
 * The trip's machine. `state` is a phase (anything else counts as 'home'), `ev` an event {type, ...}. Returns {state, act}: the next phase and what the app does
 * (DESKTOP_ACTS), or the same phase with act null when the event makes no sense there. dragOut and move without a valid spot make no sense either. An alert that
 * clears mid-flight turns the cat around (retracting + alertOff is returning); a sendHome during an alert ends the trip at home (an approval that lands while
 * the cat is home does not take it out). Pure, and it never throws.
 */
function desktopStep(state,ev){const s=DESKTOP_PHASES.includes(state)?state:'home',same={state:s,act:null};
 if(!isPlain(ev)||typeof ev.type!=='string'||!own(DESKTOP_NEXT[s],ev.type))return same;
 if((ev.type==='dragOut'||ev.type==='move')&&!dkSpot(ev.spot))return same;
 const [next,act]=DESKTOP_NEXT[s][ev.type];return{state:next,act}}
/** The flight between the notch spot and the desktop spot takes this long (ms), about 0.6 s. */
const DESKTOP_FLIGHT_MS=600;
/** The flight's arc bows `lift` of the distance away from the straight line, never more than `max` points, always upwards (a vertical flight bows to the right). */
const DESKTOP_ARC={lift:.25,max:90};
/**
 * Where the cat is `t` (0 to 1, held to that range; a t that is not a number is 0) of the way along a flight from `from` to `to` ({x, y}; anything else counts as 0, 0):
 * a quadratic arc eased in and out (EZ.inOut), with the cat at full size the whole way (scale 1). Returns {x, y, scale}. The path is the same both ways:
 * the position at (from, to, t) is the position at (to, from, 1 - t), so a flight that turns around carries on from 1 - t and retraces itself.
 */
function desktopFlightAt(from,to,t){const f=dkSpot(from)||{x:0,y:0},g=dkSpot(to)||{x:0,y:0},k=typeof t==='number'&&!Number.isNaN(t)?clamp(t,0,1):0,q=EZ.inOut(k),dx=g.x-f.x,dy=g.y-f.y,len=Math.hypot(dx,dy);
 let nx=0,ny=0;if(len>0){nx=dy/len;ny=-dx/len;if(ny>0||(ny===0&&nx<0)){nx=-nx;ny=-ny}}
 const lift=Math.min(len*DESKTOP_ARC.lift,DESKTOP_ARC.max),cx=(f.x+g.x)/2+nx*lift,cy=(f.y+g.y)/2+ny*lift,u=1-q;
 return{x:u*u*f.x+2*u*q*cx+q*q*g.x,y:u*u*f.y+2*u*q*cy+q*q*g.y,scale:1}}
Object.assign(api,{DESKTOP_PHASES,DESKTOP_PHASE_INFO,DESKTOP_EVENTS,DESKTOP_ACTS,DESKTOP_NEXT,desktopStep,DESKTOP_FLIGHT_MS,DESKTOP_ARC,desktopFlightAt});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 78 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 13`, `# pass 13`, `# fail 0`.

- [ ] **Step 5: Prove the guards bite (not committed)**

The turn-around and the arc's tie rule are the two things a reader changes by mistake. Take each out, see its tests fail, put it back.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "alertOff:['returning','turn'],flightDone:['atNotchForAlert','dock']"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "alertOff:['atNotchForAlert','dock'],flightDone:['atNotchForAlert','dock']"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "alertOff:['atNotchForAlert','dock'],flightDone:['atNotchForAlert','dock']"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "alertOff:['returning','turn'],flightDone:['atNotchForAlert','dock']"))
PY
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "if(ny>0||(ny===0&&nx<0)){nx=-nx;ny=-ny}"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "if(ny>0){nx=-nx;ny=-ny}"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "if(ny>0){nx=-nx;ny=-ny}"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "if(ny>0||(ny===0&&nx<0)){nx=-nx;ny=-ny}"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: first run `not ok 5 - an alert clearing mid-flight turns the cat around, and so does every change of mind`, `# pass 12`, `# fail 1`; second run `not ok 11 - desktopFlightAt: an arc that bows upwards, eased, that never overshoots its ends`, `not ok 12 - desktopFlightAt: the path is the same both ways, so a flight that turns around retraces itself`, `# pass 11`, `# fail 2`; after putting both lines back, `# pass 13` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 244`, `# pass 244`, `# fail 0`; fourteen `✓` fixture lines, `✓ 14 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. (No fixture changed yet: the 231 old tests and the 13 new ones.)

- [ ] **Step 7: Add the replay tests and the fixture to the file list**

```bash
cat >> tests/cat/desktop.test.mjs <<'EOF'

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/desktop-cases.json', import.meta.url), 'utf8'));

test('desktop-cases.json: the frozen values and the phase table are the core\'s', () => {
  assert.deepEqual(fx.phaseIds, PHASES);
  assert.deepEqual(fx.phases, INFO);
  assert.deepEqual(fx.events, EVENTS);
  assert.deepEqual(fx.acts, core.DESKTOP_ACTS);
  assert.equal(fx.flightMs, 600);
  assert.deepEqual(compare(fx.arc, core.DESKTOP_ARC), []);
});

test('desktop-cases.json: every step replays from its own input, and all 63 pairs are there', () => {
  for (const c of fx.steps) assert.deepEqual(core.desktopStep(c.state, c.event), c.out, JSON.stringify([c.state, c.event]));
  const pairs = new Set(fx.steps.filter(c => PHASES.includes(c.state) && c.event && EVENTS.includes(c.event.type) && (c.event.spot || !['dragOut', 'move'].includes(c.event.type))).map(c => `${c.state}|${c.event.type}`));
  assert.equal(pairs.size, 63);
  assert.ok(fx.steps.length >= 85, 'and the input that is not a phase or an event');
  assert.ok(fx.steps.some(c => c.state === null) && fx.steps.some(c => c.event === null) && fx.steps.some(c => c.event && c.event.type === '__proto__'));
});

test('desktop-cases.json: every trip replays, and the three stories of the spec are in it', () => {
  for (const t of fx.trips) {
    let s = t.from;
    t.events.forEach((e, i) => { const r = core.desktopStep(s, e); assert.deepEqual(r, t.out[i], `${t.name} step ${i}`); s = r.state; });
    assert.equal(t.out.length, t.events.length, t.name);
  }
  const named = n => fx.trips.find(t => t.name.startsWith(n));
  assert.deepEqual(named('an alert that clears mid-flight').out.map(r => r.state), ['retracting', 'returning', 'onDesktop']);
  assert.deepEqual(named('sendHome during an alert, in flight').out.map(r => r.state), ['retracting', 'flyingHome', 'flyingHome', 'flyingHome', 'home']);
  assert.deepEqual(named('sendHome during an alert, in the notch').out.map(r => r.state), ['retracting', 'atNotchForAlert', 'home', 'home', 'home']);
  assert.ok(fx.trips.length >= 11);
});

test('desktop-cases.json: every flight replays, and every route is sampled at the ends, the middle and out of range', () => {
  for (const c of fx.flights) assert.deepEqual(compare(roundTrip(core.desktopFlightAt(c.from, c.to, c.t)), c.out), [], c.name + ' ' + c.t);
  const by = new Map();
  for (const c of fx.flights) by.set(c.name, [...(by.get(c.name) || []), c.t]);
  const routes = [...by].filter(([, ts]) => ts.length === 9);
  assert.equal(routes.length, 9);
  for (const [name, ts] of routes) assert.deepEqual(ts, [-.5, 0, .1, .25, .5, .75, .9, 1, 1.5], name);
  const cut = fx.flights.filter(c => c.name === 'down and right: the default spot');
  assert.deepEqual(cut.find(c => c.t === -.5).out, cut.find(c => c.t === 0).out, 'before the start is the start');
  assert.deepEqual(cut.find(c => c.t === 1.5).out, cut.find(c => c.t === 1).out, 'after the end is the end');
  assert.ok(fx.flights.every(c => c.out.scale === 1));
  assert.ok(fx.flights.every(c => Math.abs(c.out.x) < 1000 && Math.abs(c.out.y) < 1000), 'positions stay under 1000 points, so that 12 significant digits keep the 1e-9 tolerance');
});
EOF
python3 - <<'PY'
p = 'tests/cat/fixtures.test.mjs'
s = open(p, encoding='utf-8').read()
was = "'collar-cases.json', 'display-cases.json', 'geometry-cases.json'"
assert s.count(was) == 1, was
open(p, 'w', encoding='utf-8').write(s.replace(was, "'collar-cases.json', 'desktop-cases.json', 'display-cases.json', 'geometry-cases.json'"))
PY
node --test tests/cat/desktop.test.mjs tests/cat/fixtures.test.mjs 2>&1 | grep -E "^(not ok|# (pass|fail))|ENOENT" | head
```

Expected: `not ok` lines for the fixtures tests (the list now has `desktop-cases.json`, which does not exist yet), `ENOENT` lines that name `desktop-cases.json`, and `not ok 1 - tests/cat/desktop.test.mjs`: the replay part of that file cannot load without the fixture. The 13 self-checks from Step 1 still pass on their own.

- [ ] **Step 8: Add the builder and generate the fixture**

The builder goes above the `@@BUILDERS` marker, and has a marker of its own, `@@DESKTOP-SECTIONS`, that Tasks 2 to 4 insert their keys above. Its rows are what an app could send, written as JSON; the flights stay under 1000 points so that 12 significant digits keep the 1e-9 tolerance.

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '// @@BUILDERS: each task adds'
assert s.count(marker) == 1
snippet = r'''// ── The desktop cat (H-0): the trip, the frame rate, the spots, the settings and the kittens ──────────
// One fixture file for all of it; each task of the plan adds its keys to `out` above the marker below. Every event, spot and screen is JSON (so no undefined, NaN
// or Infinity: a port adds its own tests for a number that is not a number). `out` of a row is what the core function returns.
FILES['desktop-cases.json'] = () => {
  const out = {
    version: 1,
    note: 'The desktop cat (sub-project H). A spot is the cat\'s head centre in points, y down, the origin at the top left of the main screen. phases: the seven phases and what each means. steps: desktopStep(state, event) is out, for every phase and event and for input that is not a phase or an event. trips: desktopStep over a script of events, out is the state and act after each. flights: desktopFlightAt(from, to, t) is out.',
  };
  const SPOT = { x: 640, y: 300 }, evOf = type => (type === 'dragOut' || type === 'move' ? { type, spot: SPOT } : { type });

  // The trip.
  out.phaseIds = core.DESKTOP_PHASES;
  out.phases = core.DESKTOP_PHASE_INFO;
  out.events = core.DESKTOP_EVENTS;
  out.acts = core.DESKTOP_ACTS;
  out.flightMs = core.DESKTOP_FLIGHT_MS;
  out.arc = core.DESKTOP_ARC;
  out.steps = [
    ...core.DESKTOP_PHASES.flatMap(state => core.DESKTOP_EVENTS.map(type => ({ state, event: evOf(type), out: core.desktopStep(state, evOf(type)) }))),
    ...[
      ['home', { type: 'dragOut' }], ['home', { type: 'dragOut', spot: { x: 1 } }], ['home', { type: 'dragOut', spot: { x: '1', y: 2 } }], ['home', { type: 'dragOut', spot: [1, 2] }],
      ['home', { type: 'dragOut', spot: { x: 1e6, y: 2 } }], ['onDesktop', { type: 'move' }], ['onDesktop', { type: 'move', spot: null }], ['onDesktop', { type: 'move', spot: { x: 5, y: 6 } }],
      ['onDesktop', null], ['onDesktop', 'toggle'], ['onDesktop', 7], ['onDesktop', []], ['onDesktop', {}], ['onDesktop', { type: 7 }], ['onDesktop', { type: ['toggle'] }], ['onDesktop', { type: 'Toggle' }],
      ['onDesktop', { type: 'toggle ' }], ['onDesktop', { type: '__proto__' }], ['onDesktop', { type: 'constructor' }],
      [null, { type: 'toggle' }], [7, { type: 'toggle' }], ['', { type: 'toggle' }], ['Home', { type: 'toggle' }], ['flying', { type: 'toggle' }], [['home'], { type: 'toggle' }], ['__proto__', { type: 'toggle' }],
    ].map(([state, event]) => ({ state, event, out: core.desktopStep(state, event) })),
  ];
  const trip = (name, from, events) => ({ name, from, events, out: events.reduce((acc, e) => [...acc, core.desktopStep(acc.length ? acc.at(-1).state : from, e)], []) });
  out.trips = [
    trip('the whole trip: out, an alert to the notch and back, home', 'home', ['toggle', 'flightDone', 'alertOn', 'flightDone', 'alertOff', 'flightDone', 'sendHome', 'flightDone'].map(evOf)),
    trip('dropped on the desktop, moved, the screens change, then home', 'home', [evOf('dragOut'), evOf('move'), evOf('screensChanged'), { type: 'move', spot: { x: 'a', y: 1 } }, evOf('toggle'), evOf('flightDone')]),
    trip('an alert that clears mid-flight turns the cat around', 'onDesktop', ['alertOn', 'alertOff', 'flightDone'].map(evOf)),
    trip('a second alert while the cat flies back out turns it around again', 'atNotchForAlert', ['alertOff', 'alertOn', 'flightDone', 'alertOff', 'flightDone'].map(evOf)),
    trip('sendHome during an alert, in the notch', 'onDesktop', ['alertOn', 'flightDone', 'sendHome', 'alertOff', 'alertOn'].map(evOf)),
    trip('sendHome during an alert, in flight: it ends the trip at home', 'onDesktop', ['alertOn', 'sendHome', 'alertOff', 'alertOn', 'flightDone'].map(evOf)),
    trip('sendHome while the cat flies back out after an alert', 'atNotchForAlert', ['alertOff', 'sendHome', 'flightDone'].map(evOf)),
    trip('an alert at home does not take the cat out', 'home', ['alertOn', 'alertOff', 'toggle', 'alertOn', 'flightDone'].map(evOf)),
    trip('the user changes their mind in flight', 'home', ['toggle', 'toggle', 'toggle', 'flightDone'].map(evOf)),
    trip('a cat that was out flies out after the greeting', 'home', ['launch', 'flightDone', 'launch'].map(evOf)),
    trip('events that make no sense in a resting phase', 'onDesktop', ['dragOut', 'flightDone', 'launch', 'alertOff'].map(evOf)),
  ];
  // desktopFlightAt over six flights and the t that matter: the ends, the middle, either side of the middle, and out of range. `desktopFlightAt(from, to, t)`.
  const NOTCH = { x: 480, y: 16 }, SPOTS = { downRight: { x: 576, y: 180 }, down: { x: 480, y: 300 }, left: { x: 120, y: 200 }, far: { x: 800, y: 560 } };
  const flightRows = [
    ['down and right: the default spot', NOTCH, SPOTS.downRight], ['up and left: back to the notch', SPOTS.downRight, NOTCH], ['straight down', NOTCH, SPOTS.down], ['straight up', SPOTS.down, NOTCH],
    ['down and left', NOTCH, SPOTS.left], ['straight across', { x: 100, y: 200 }, { x: 700, y: 200 }], ['a short hop', { x: 100, y: 100 }, { x: 110, y: 105 }],
    ['no distance', { x: 50, y: 60 }, { x: 50, y: 60 }], ['a long flight: the lift stops at 90', { x: 0, y: 0 }, SPOTS.far],
  ];
  out.flights = [
    ...flightRows.flatMap(([name, from, to]) => [-.5, 0, .1, .25, .5, .75, .9, 1, 1.5].map(t => ({ name, from, to, t, out: core.desktopFlightAt(from, to, t) }))),
    ...[
      ['a start that is not a point', null, SPOTS.downRight, .5], ['an end that is not a point', NOTCH, 'there', .5], ['a start with a missing y', { x: 5 }, SPOTS.downRight, 0], ['an end beyond the limit', NOTCH, { x: 1e6, y: 0 }, 1],
      ['t is a string', NOTCH, SPOTS.downRight, '0.5'], ['t is null', NOTCH, SPOTS.downRight, null], ['t is a huge number', NOTCH, SPOTS.downRight, 1e300], ['t is a huge negative number', NOTCH, SPOTS.downRight, -1e300],
    ].map(([name, from, to, t]) => ({ name, from, to, t, out: core.desktopFlightAt(from, to, t) })),
  ];

  // @@DESKTOP-SECTIONS: each task adds its keys to `out` immediately above this line.
  return out;
};

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/desktop-cases.json
```

Expected: `wrote 15 fixture files to tests/fixtures/cat` and a `desktop-cases.json` of about 26 KB (under the 400 KB the fixtures test allows).

- [ ] **Step 9: Run the tests, then prove the fixture is additive and that no-drift covers it**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok|✓|✗"`
Expected: `# tests 248`, `# pass 248`, `# fail 0`; fifteen `✓` fixture lines (`desktop-cases.json` among them), `✓ 15 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 1627851 | tail -3`
Expected: `  ✓ warp-cases.json: 121 old lines unchanged`, `  + desktop-cases.json is new` and `✓ fixtures changed only by addition since 1627851`.

Run: `git diff --stat -- tests/fixtures/cat`
Expected: no output (no existing fixture changed; the new one is untracked).

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const DESKTOP_ARC={lift:.25,max:90};"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const DESKTOP_ARC={lift:.25,max:80};"))
PY
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E "✗|Fixtures drifted"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const DESKTOP_ARC={lift:.25,max:80};"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const DESKTOP_ARC={lift:.25,max:90};"))
PY
node scripts/gen-cat-fixtures.mjs --check | tail -1
```

Expected: first `✗ desktop-cases.json drifted from cat-core.js (30 differences)` and `Fixtures drifted. cat-core.js is the tie-breaker…`; after putting the line back, `✓ 15 fixture files match cat-core.js`.

- [ ] **Step 10: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js`, ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/fixtures.test.mjs`, `?? tests/cat/desktop.test.mjs`, `?? tests/fixtures/cat/desktop-cases.json`.

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/fixtures.test.mjs tests/cat/desktop.test.mjs tests/fixtures/cat/desktop-cases.json
git commit -m "feat(cat): the desktop cat's trip is a machine in the core

desktopStep (seven phases, nine events) and desktopFlightAt, pinned by desktop-cases.json. New names only: flightAt and the older tables are untouched.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Size, frame rate and kittens: `desktopFps`, `DESKTOP_SIZES` and `desktopKittenSlots`

**Files:**
- Modify: `design/prototype/cat-core.js` (a second section above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (keys inside the desktop builder), `tests/cat/desktop.test.mjs` (appended)
- Regenerate: `tests/fixtures/cat/desktop-cases.json`

**Interfaces:**
- Consumes from Task 1: `DESKTOP_PHASES`, `DESKTOP_PHASE_INFO`; from the core: `isPlain`, `isKittenId`.
- Produces in `CatCore`: `DESKTOP_SIZES`, `DESKTOP_SIZE_IDS`, `DEFAULT_DESKTOP_SIZE`, `desktopSizeOf`, `DESKTOP_FPS`, `DESKTOP_NEAR`, `desktopFps`, `DESKTOP_KITTEN_PLACE`, `desktopKittenSlots`, exactly as in "Interface for the app plans" section 2; and the fixture keys `sizes`, `sizeIds`, `defaultSize`, `sizeCases`, `fps`, `near`, `fpsCases`, `kittenPlace`, `kittenSlots`, `kittenSizes`.

- [ ] **Step 1: Write the failing tests**

```bash
cat >> tests/cat/desktop.test.mjs <<'EOF'

// ── Sizes, frame rate and kittens ────────────────────────────────────────────
const DRAWN = PHASES.filter(p => INFO[p].drawn);
const fps = (phase, o = {}) => core.desktopFps({ phase, ...o });
const kits = n => Array.from({ length: n }, (_, i) => ({ id: 'k' + i, type: 'Explore', session: null, state: i === 0 ? 'approval' : 'working', born: i, last: i, until: null }));

test('the sizes: three frozen IDs at Ø48, Ø64 and Ø96, and anything else is medium', () => {
  assert.deepEqual(core.DESKTOP_SIZES, { small: 48, medium: 64, large: 96 });
  assert.deepEqual(core.DESKTOP_SIZE_IDS, ['small', 'medium', 'large']);
  assert.equal(core.DEFAULT_DESKTOP_SIZE, 'medium');
  for (const id of core.DESKTOP_SIZE_IDS) assert.equal(core.desktopSizeOf(id), id);
  for (const bad of ['Small', 'LARGE', ' large', 'large ', 'huge', 'tiny', '', '48', 48, 64, null, undefined, true, ['small'], {}, '__proto__', 'constructor', 'medium\n']) assert.equal(core.desktopSizeOf(bad), 'medium', String(JSON.stringify(bad)));
});

test('the frame rate: every row of the table', () => {
  assert.deepEqual(core.DESKTOP_FPS, { motion: 60, active: 20, idle: 5, asleep: .5, off: 0 });
  assert.equal(core.DESKTOP_NEAR, 150);
  // 60: dragging, flying, an emote, a kitten arriving or leaving, the dance.
  for (const flag of ['dragging', 'emote', 'kittenMotion', 'dance']) assert.equal(fps('onDesktop', { [flag]: true }), 60, flag);
  for (const p of PHASES.filter(p => INFO[p].flight)) assert.equal(fps(p), 60, `${p} flies`);
  // 20: an agent working, thinking or searching, or the cursor within 150 points.
  assert.equal(fps('onDesktop', { working: true }), 20);
  assert.equal(fps('onDesktop', { cursorDist: 0 }), 20);
  assert.equal(fps('onDesktop', { cursorDist: 150 }), 20, '150 points is near');
  assert.equal(fps('onDesktop', { cursorDist: 150.01 }), 5, 'a hair further is not');
  // 5: idle and awake. A still frame every 2 s asleep. Nothing when it cannot be seen.
  assert.equal(fps('onDesktop'), 5);
  assert.equal(fps('onDesktop', { cursorDist: 900 }), 5);
  assert.equal(fps('onDesktop', { asleep: true }), .5);
  assert.equal(fps('onDesktop', { hidden: true }), 0);
});

test('the frame rate: home, and the cat sitting in the notch, draw nothing on the desktop, whatever else is going on', () => {
  const all = { hidden: false, dragging: true, emote: true, kittenMotion: true, dance: true, asleep: true, working: true, cursorDist: 0 };
  for (const p of PHASES.filter(p => !INFO[p].drawn)) { assert.equal(fps(p), 0, p); assert.equal(fps(p, all), 0, p); }
  assert.deepEqual(PHASES.filter(p => !INFO[p].drawn), ['home', 'atNotchForAlert']);
  assert.equal(fps('home', { working: true, dance: true }), 0);
});

test('the frame rate: the order of the rules', () => {
  assert.equal(fps('onDesktop', { hidden: true, dragging: true, working: true }), 0, 'hidden beats everything, motion included');
  assert.equal(fps('flyingOut', { hidden: true }), 0, 'a flight under a fullscreen app is not drawn');
  assert.equal(fps('onDesktop', { dragging: true, asleep: true, working: true }), 60, 'motion beats sleep and work');
  assert.equal(fps('onDesktop', { asleep: true, working: true, cursorDist: 10 }), .5, 'a sleeping cat does not watch the cursor');
  assert.equal(fps('onDesktop', { working: true, cursorDist: 10 }), 20);
  assert.equal(fps('retracting', { asleep: true }), 60, 'a flight is always 60');
});

test('the frame rate: only true counts, and input that is not input draws nothing', () => {
  for (const v of ['true', 1, 'yes', {}, [], null, undefined, 0, NaN]) for (const flag of ['hidden', 'dragging', 'emote', 'kittenMotion', 'dance', 'asleep', 'working'])
    assert.equal(fps('onDesktop', { [flag]: v }), 5, `${flag}: ${String(JSON.stringify(v))} is not true`);
  for (const d of ['10', null, undefined, NaN, Infinity, -Infinity, {}, [5], true]) assert.equal(fps('onDesktop', { cursorDist: d }), 5, `cursorDist ${String(d)}`);
  for (const bad of [null, undefined, 7, 'onDesktop', [], ['onDesktop'], {}, { phase: null }, { phase: 'Home' }, { phase: 'flying' }, { phase: ['onDesktop'] }, { phase: '__proto__' }, { phase: 'constructor' }]) assert.equal(core.desktopFps(bad), 0, String(JSON.stringify(bad)));
  assert.equal(core.desktopFps(Object.freeze({ phase: 'onDesktop' })), 5);
});

test('the frame rate: 6000 random inputs give one of the five rates, the same as the rules written as a table', () => {
  const r = core.rng(99), flags = ['hidden', 'dragging', 'emote', 'kittenMotion', 'dance', 'asleep', 'working'], phases = [...PHASES, 'nowhere', null], dists = [undefined, null, 0, 149.9, 150, 150.1, 5000, NaN, '3'];
  const rates = new Set([0, .5, 5, 20, 60]), pick = a => a[Math.floor(r() * a.length)];
  for (let n = 0; n < 6000; n++) {
    const i = { phase: pick(phases), cursorDist: pick(dists) };
    for (const f of flags) if (r() < .3) i[f] = r() < .85;
    const got = core.desktopFps(i);
    assert.ok(rates.has(got), JSON.stringify(i));
    const drawn = PHASES.includes(i.phase) && INFO[i.phase].drawn && i.hidden !== true;
    const motion = drawn && (INFO[i.phase].flight || i.dragging === true || i.emote === true || i.kittenMotion === true || i.dance === true);
    const near = typeof i.cursorDist === 'number' && Number.isFinite(i.cursorDist) && i.cursorDist <= 150;
    const want = !drawn ? 0 : motion ? 60 : i.asleep === true ? .5 : (i.working === true || near) ? 20 : 5;
    assert.equal(got, want, JSON.stringify(i));
  }
});

test('the desktop kittens: the slots at the three sizes, with 0, 1, 3 and 8 kittens', () => {
  const P = core.DESKTOP_KITTEN_PLACE;
  assert.deepEqual(P, { unit: 'D', max: 3, d: .3, x0: .82, y0: .22, step: .33, moreSize: .2 });
  for (const n of [0, 1, 3, 8]) {
    const s = core.desktopKittenSlots(kits(n));
    assert.deepEqual(Object.keys(s), ['place', 'unit', 'count', 'shown', 'more', 'moreAt', 'label']);
    assert.equal(s.place, 'desktop'); assert.equal(s.unit, 'D'); assert.equal(s.count, n); assert.equal(s.label, null);
    assert.equal(s.shown.length, Math.min(n, 3), `${n} kittens`);
    assert.equal(s.more, Math.max(0, n - 3));
    s.shown.forEach((q, i) => { assert.equal(q.id, 'k' + i); near(q.x, P.x0 + i * P.step, 'x'); assert.equal(q.y, P.y0); assert.equal(q.d, P.d); });
    if (n > 3) { near(s.moreAt.x, P.x0 + 3 * P.step, '"+N" x'); assert.equal(s.moreAt.y, P.y0); assert.equal(s.moreAt.size, P.moreSize); } else assert.equal(s.moreAt, null);
    // The numbers are multiples of the head width, so each size is the same layout scaled: Ø48 kittens are 14.4 points across, Ø64 19.2 and Ø96 28.8.
    for (const [id, d] of Object.entries(core.DESKTOP_SIZES)) s.shown.forEach(q => { near(q.d * d, { small: 14.4, medium: 19.2, large: 28.8 }[id], `${id} kitten`); assert.ok(q.x * d > d / 2, 'a kitten stands beside the head, not on it'); });
  }
  assert.equal(core.desktopKittenSlots(kits(8)).shown[0].state, 'approval', 'the state travels with the kitten');
});

test('the desktop kittens: the left side is the right side mirrored, and any other side is the right', () => {
  for (const n of [0, 1, 3, 8]) {
    const R = core.desktopKittenSlots(kits(n), 1), L = core.desktopKittenSlots(kits(n), -1);
    R.shown.forEach((q, i) => { near(L.shown[i].x, -q.x, 'x'); assert.equal(L.shown[i].y, q.y); assert.equal(L.shown[i].d, q.d); });
    if (R.moreAt) { near(L.moreAt.x, -R.moreAt.x, '"+N" x'); assert.equal(L.moreAt.y, R.moreAt.y); } else assert.equal(L.moreAt, null);
  }
  for (const side of [undefined, null, 0, 2, -2, '-1', 'left', NaN, true, [-1], {}]) assert.deepEqual(core.desktopKittenSlots(kits(4), side), core.desktopKittenSlots(kits(4), 1), String(JSON.stringify(side)));
});

test('the desktop kittens: clear of the badge and of the head and ruff, on every coat at every size', () => {
  for (const id of core.CAT_IDS) for (const d of Object.values(core.DESKTOP_SIZES)) {
    const p = core.PRESETS[id], s = core.newPose(); s.badgeS = 1;
    const L = core.layout(p, s, 0, 0, d, { badgeSide: 1 }), ruff = p.ruff ? p.ruff.rx * L.R : 0, badge = { x: L.badge.x, y: L.badge.y, r: .3 * L.R }, slots = core.desktopKittenSlots(kits(4));
    for (const q of [...slots.shown, { ...slots.moreAt, d: slots.moreAt.size }]) {
      const x = q.x * d, y = q.y * d, r = q.d * d / 2;
      assert.ok(x - r > Math.max(L.rx, ruff) + .02 * d, `${id} Ø${d}: a kitten overlaps the head or the ruff`);
      assert.ok(Math.hypot(x - badge.x, y - badge.y) > r + badge.r + .02 * d, `${id} Ø${d}: a kitten touches the badge`);
    }
  }
});

test('the desktop kittens: B\'s tables are untouched, and what is not a kitten is skipped', () => {
  assert.deepEqual(Object.keys(core.KITTEN_PLACES), ['bigExpanded', 'bigCompact', 'pairCompact', 'pairExpanded', 'pill']);
  assert.equal(core.kittenSlots('desktop', kits(2)).shown.length, 0, 'kittenSlots does not know the desktop place');
  const list = [kits(1)[0], null, 7, 'k', { id: '' }, { id: 5 }, { state: 'working' }, [], { id: 'ok', state: 7 }];
  const s = core.desktopKittenSlots(list);
  assert.deepEqual(s.shown.map(q => q.id), ['k0', 'ok']);
  assert.equal(s.shown[1].state, 'working', 'a state that is not text counts as working');
  for (const bad of [null, undefined, 'k0', 7, {}, { length: 2 }]) assert.deepEqual(core.desktopKittenSlots(bad).shown, [], String(JSON.stringify(bad)));
  const frozen = Object.freeze(kits(4).map(Object.freeze));
  assert.doesNotThrow(() => core.desktopKittenSlots(frozen, -1));
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 27`, `# pass 17`, `# fail 10`: the 17 tests of Task 1 pass, the ten new ones need the section.

- [ ] **Step 3: Add the section to the core**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── The desktop cat: size, frame rate and kittens (sub-project H) ────────────
/** The desktop cat's three sizes, as the head width in points. The IDs are frozen contract values, like the cat IDs; `medium` is the default. */
const DESKTOP_SIZES={small:48,medium:64,large:96};
const DESKTOP_SIZE_IDS=['small','medium','large'];
const DEFAULT_DESKTOP_SIZE='medium';
/** A stored size to one of the three IDs. Anything else, the case and the type included, is 'medium'. */
const desktopSizeOf=v=>DESKTOP_SIZE_IDS.includes(v)?v:DEFAULT_DESKTOP_SIZE;
/** The frame rates (per second). `asleep` is one still frame every 2 s, redrawn for a slow breath; `off` draws nothing. */
const DESKTOP_FPS={motion:60,active:20,idle:5,asleep:.5,off:0};
/** The cursor is "near" the cat within this many points of the cat's centre. */
const DESKTOP_NEAR=150;
/**
 * The frame rate the app aims for, from what the cat is doing: {phase, hidden, dragging, emote, kittenMotion, dance, asleep, working, cursorDist}.
 *   phase         a DESKTOP_PHASES ID; only a phase the desktop window draws (flyingOut, onDesktop, retracting, returning, flyingHome) is ever drawn there
 *   hidden        true while the screen is asleep or locked, the display is off, or a fullscreen app covers the cat
 *   dragging, emote, kittenMotion (a kitten arriving or leaving), dance (the music bob)   each true when it is going on
 *   asleep        the ten-minute sleep; the app clears it the moment a hover, a click or an agent event wakes the cat
 *   working       the cat's agent is working, thinking or searching
 *   cursorDist    points from the cursor to the cat's centre; leave it out when the app cannot know (Wayland)
 * In this order: 0 when it is not drawn or hidden; 60 for any motion (a flight included); 0.5 asleep; 20 working or the cursor near; else 5.
 * Only `true` counts for a flag, and anything that is not an object, or has no phase, draws nothing. Pure, and it never throws.
 */
function desktopFps(i){if(!isPlain(i)||!DESKTOP_PHASES.includes(i.phase)||!DESKTOP_PHASE_INFO[i.phase].drawn||i.hidden===true)return DESKTOP_FPS.off;
 if(DESKTOP_PHASE_INFO[i.phase].flight||i.dragging===true||i.emote===true||i.kittenMotion===true||i.dance===true)return DESKTOP_FPS.motion;
 if(i.asleep===true)return DESKTOP_FPS.asleep;
 if(i.working===true||(Number.isFinite(i.cursorDist)&&i.cursorDist<=DESKTOP_NEAR))return DESKTOP_FPS.active;
 return DESKTOP_FPS.idle}
/**
 * Where the desktop cat's kittens sit: the same slot maths as KITTEN_PLACES (the i-th kitten at x0 + i * step, up to `max`, then "+N" at the next slot), in its own
 * table so the table both apps copy stays as it is. Units are D, the cat's head width, from its head centre (x right, y down): the kittens stand in a row at the
 * lower right, clear of the badge (upper right) and of the ruff. They scale with the size, so one table serves Ø48, Ø64 and Ø96.
 */
const DESKTOP_KITTEN_PLACE={unit:'D',max:3,d:.3,x0:.82,y0:.22,step:.33,moreSize:.2};
/**
 * The slots for the cat's kittens. `kittens` is what kittenView returned (already in order). `side` 1 puts them on the right of the cat, -1 on its left
 * (a cat in the right half of its screen keeps them on screen); anything else is 1. Returns {place: 'desktop', unit, count, shown, more, moreAt, label: null}
 * as kittenSlots does: `shown` the first three as {id, state, x, y, d}, `more` how many are left over, `moreAt` {x, y, size} of the "+N" or null.
 */
function desktopKittenSlots(kittens,side){const P=DESKTOP_KITTEN_PLACE,m=side===-1?-1:1,L=Array.isArray(kittens)?kittens.filter(k=>isPlain(k)&&isKittenId(k.id)):[],count=L.length,n=Math.min(count,P.max),more=count-n;
 return{place:'desktop',unit:P.unit,count,shown:L.slice(0,n).map((k,i)=>({id:k.id,state:typeof k.state==='string'?k.state:'working',x:m*(P.x0+i*P.step),y:P.y0,d:P.d})),more,
  moreAt:more>0?{x:m*(P.x0+P.max*P.step),y:P.y0,size:P.moreSize}:null,label:null}}
Object.assign(api,{DESKTOP_SIZES,DESKTOP_SIZE_IDS,DEFAULT_DESKTOP_SIZE,desktopSizeOf,DESKTOP_FPS,DESKTOP_NEAR,desktopFps,DESKTOP_KITTEN_PLACE,desktopKittenSlots});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 43 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 27`, `# pass 27`, `# fail 0`.

- [ ] **Step 5: Prove the cursor boundary bites (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "i.cursorDist<=DESKTOP_NEAR"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "i.cursorDist<DESKTOP_NEAR"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "i.cursorDist<DESKTOP_NEAR"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "i.cursorDist<=DESKTOP_NEAR"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: first run `not ok 19 - the frame rate: every row of the table`, `not ok 23 - the frame rate: 6000 random inputs give one of the five rates, the same as the rules written as a table`, `# pass 25`, `# fail 2`; after putting the line back, `# pass 27` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗"`
Expected: `# tests 258`, `# pass 258`, `# fail 0`.

- [ ] **Step 7: Add the replay tests and the fixture keys**

```bash
cat >> tests/cat/desktop.test.mjs <<'EOF'

test('desktop-cases.json: the sizes and the frame-rate table replay, every row of the spec\'s table is there', () => {
  assert.deepEqual(fx.sizes, core.DESKTOP_SIZES);
  assert.deepEqual(fx.sizeIds, core.DESKTOP_SIZE_IDS);
  assert.equal(fx.defaultSize, 'medium');
  for (const c of fx.sizeCases) assert.equal(core.desktopSizeOf(c.raw), c.out, JSON.stringify(c.raw));
  assert.deepEqual(fx.fps, core.DESKTOP_FPS);
  assert.equal(fx.near, 150);
  for (const c of fx.fpsCases) assert.equal(core.desktopFps(c.input), c.out, c.name);
  const rate = name => fx.fpsCases.find(c => c.name === name).out;
  assert.equal(rate('home, nothing going on'), 0);
  assert.equal(rate('dragging'), 60); assert.equal(rate('an emote'), 60); assert.equal(rate('a kitten arriving or leaving'), 60); assert.equal(rate('the dance'), 60); assert.equal(rate('flyingOut, nothing going on'), 60);
  assert.equal(rate('an agent working'), 20); assert.equal(rate('the cursor exactly 150 points away'), 20); assert.equal(rate('the cursor 150.01 points away'), 5);
  assert.equal(rate('idle and awake'), 5); assert.equal(rate('asleep'), .5); assert.equal(rate('hidden: the screen is asleep, locked or covered'), 0);
  assert.deepEqual([...new Set(fx.fpsCases.map(c => c.out))].sort((a, b) => a - b), [0, .5, 5, 20, 60], 'all five rates occur');
});

test('desktop-cases.json: the kitten slots replay, and the same layout at each size is a multiple of the head width', () => {
  assert.deepEqual(fx.kittenPlace, core.DESKTOP_KITTEN_PLACE);
  for (const c of fx.kittenSlots) assert.deepEqual(compare(roundTrip(core.desktopKittenSlots(c.kittens, c.side)), c.out), [], c.name);
  assert.deepEqual(fx.kittenSlots.filter(c => /^\d+ kittens/.test(c.name)).map(c => c.out.shown.length), [0, 0, 1, 1, 2, 2, 3, 3, 3, 3, 3, 3]);
  assert.deepEqual(fx.kittenSlots.filter(c => /^(0|1|3|8) kittens/.test(c.name)).map(c => c.out.count), [0, 0, 1, 1, 3, 3, 8, 8]);
  assert.equal(fx.kittenSizes.length, 12);
  for (const c of fx.kittenSizes) {
    assert.equal(core.DESKTOP_SIZES[c.size], c.d, c.size);
    const s = core.desktopKittenSlots(fx.kittenSlots.find(r => r.name === `${c.count} kittens, side 1`).kittens);
    assert.deepEqual(compare(roundTrip(c.shown.map(q => ({ id: q.id, state: q.state, x: q.x / c.d, y: q.y / c.d, d: q.d / c.d }))), s.shown), [], `${c.size} ${c.count}`);
    assert.equal(c.more, s.more);
  }
  assert.deepEqual(compare(fx.kittenSizes.find(c => c.size === 'small' && c.count === 3).shown.map(q => q.d), [14.4, 14.4, 14.4]), []);
  assert.deepEqual(compare(fx.kittenSizes.find(c => c.size === 'large' && c.count === 8).moreAt, { x: 96 * (.82 + .99), y: 96 * .22, size: 96 * .2 }), []);
});
EOF
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '  // @@DESKTOP-SECTIONS: each task adds its keys to `out` immediately above this line.'
assert s.count(marker) == 1
snippet = r'''  out.note += ' sizeCases: desktopSizeOf(raw) is out. fpsCases: desktopFps(input) is out. kittenSlots: desktopKittenSlots(kittens, side) is out (a missing side is not given). kittenSizes: the same layout in points at each size, side 1.';
  // Sizes: desktopSizeOf(raw) is out.
  out.sizes = core.DESKTOP_SIZES;
  out.sizeIds = core.DESKTOP_SIZE_IDS;
  out.defaultSize = core.DEFAULT_DESKTOP_SIZE;
  out.sizeCases = ['small', 'medium', 'large', 'Small', 'LARGE', ' large', 'large ', 'huge', '', '48', 48, null, true, ['small'], {}, '__proto__', 'constructor'].map(raw => ({ raw, out: core.desktopSizeOf(raw) }));

  // The frame rate: desktopFps(input) is out. `fps` holds the five rates and `near` the distance, in points, that counts as near.
  out.fps = core.DESKTOP_FPS;
  out.near = core.DESKTOP_NEAR;
  const F = (name, input) => ({ name, input, out: core.desktopFps(input) });
  const on = (o = {}) => ({ phase: 'onDesktop', ...o });
  out.fpsCases = [
    ...core.DESKTOP_PHASES.map(p => F(`${p}, nothing going on`, { phase: p })),
    F('dragging', on({ dragging: true })), F('an emote', on({ emote: true })), F('a kitten arriving or leaving', on({ kittenMotion: true })), F('the dance', on({ dance: true })),
    F('an agent working', on({ working: true })), F('the cursor on the cat', on({ cursorDist: 0 })), F('the cursor 149.9 points away', on({ cursorDist: 149.9 })), F('the cursor exactly 150 points away', on({ cursorDist: 150 })),
    F('the cursor 150.01 points away', on({ cursorDist: 150.01 })), F('the cursor far away', on({ cursorDist: 900 })), F('the cursor unknown, as on Wayland', on({ cursorDist: null })),
    F('idle and awake', on()), F('asleep', on({ asleep: true })), F('asleep with the cursor near', on({ asleep: true, cursorDist: 10 })), F('asleep and the agent working', on({ asleep: true, working: true })),
    F('hidden: the screen is asleep, locked or covered', on({ hidden: true })), F('hidden while dragging', on({ hidden: true, dragging: true })), F('hidden in flight', { phase: 'flyingOut', hidden: true }),
    F('motion beats sleep and work', on({ dragging: true, asleep: true, working: true })), F('a flight beats sleep', { phase: 'retracting', asleep: true }),
    F('home with everything going on', { phase: 'home', dragging: true, emote: true, kittenMotion: true, dance: true, working: true, cursorDist: 0 }),
    F('in the notch for an alert, with everything going on', { phase: 'atNotchForAlert', dragging: true, emote: true, dance: true, working: true, cursorDist: 0 }),
    F('the strings "true" and the number 1 are not true', on({ dragging: 'true', emote: 1, working: 'yes', asleep: 1, hidden: 'true' })),
    F('a cursor distance that is a string', on({ cursorDist: '10' })),
    F('no input', null), F('a number', 7), F('text', 'onDesktop'), F('an array', ['onDesktop']), F('an empty object', {}), F('a phase that is not a phase', { phase: 'flying' }), F('a phase in the wrong case', { phase: 'Home' }),
    F('a prototype name as the phase', { phase: '__proto__' }),
  ];

  // The desktop kittens: desktopKittenSlots(kittens, side) is out. `kittens` is [{id, state}], what kittenView returns (the other fields do not matter). `kittenSizes` is the same
  // layout in points at each size (every number is a multiple of the head width), side 1.
  out.kittenPlace = core.DESKTOP_KITTEN_PLACE;
  const kit = (n, states = ['approval', 'searching', 'working']) => Array.from({ length: n }, (_, i) => ({ id: 'k' + i, state: states[i] || 'working' }));
  out.kittenSlots = [
    ...[0, 1, 2, 3, 4, 8].flatMap(n => [1, -1].map(side => ({ name: `${n} kittens, side ${side}`, kittens: kit(n), side, out: core.desktopKittenSlots(kit(n), side) }))),
    ...[
      ['no side given: the right', kit(3), undefined], ['side 0 is the right', kit(2), 0], ['side 2 is the right', kit(2), 2], ['side "-1" as text is the right', kit(2), '-1'], ['side null is the right', kit(2), null],
      ['things that are not kittens are skipped', [null, 7, 'k', { id: '' }, { id: 5 }, { state: 'working' }, [], { id: 'ok', state: 7 }, { id: 'a', state: 'leaving' }], 1],
      ['not a list', 'k0', 1], ['null', null, 1], ['an object', { length: 2 }, 1],
    ].map(([name, kittens, side]) => ({ name, kittens, ...(side === undefined ? {} : { side }), out: core.desktopKittenSlots(kittens, side) })),
  ];
  out.kittenSizes = Object.entries(core.DESKTOP_SIZES).flatMap(([size, d]) => [0, 1, 3, 8].map(count => {
    const s = core.desktopKittenSlots(kit(count));
    return { size, d, count, shown: s.shown.map(q => ({ id: q.id, state: q.state, x: q.x * d, y: q.y * d, d: q.d * d })), more: s.more, moreAt: s.moreAt && { x: s.moreAt.x * d, y: s.moreAt.y * d, size: s.moreAt.size * d } };
  }));

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/desktop-cases.json
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"
```

Expected: the first run `not ok 28 - desktop-cases.json: the sizes and the frame-rate table replay, every row of the spec's table is there`, `not ok 29 - desktop-cases.json: the kitten slots replay, and the same layout at each size is a multiple of the head width`, `# tests 29`, `# pass 27`, `# fail 2` (the fixture has no such keys yet); then `wrote 15 fixture files to tests/fixtures/cat`, a `desktop-cases.json` of about 40 KB, and `# tests 29`, `# pass 29`, `# fail 0`.

- [ ] **Step 8: Run the contract and the additive check**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗|✓ [0-9]|✓ two"`
Expected: `# tests 260`, `# pass 260`, `# fail 0`, `✓ 15 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 1627851 | tail -2`
Expected: `  + desktop-cases.json is new` and `✓ fixtures changed only by addition since 1627851`.

- [ ] **Step 9: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js`, ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/desktop.test.mjs`, ` M tests/fixtures/cat/desktop-cases.json`.

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/desktop.test.mjs tests/fixtures/cat/desktop-cases.json
git commit -m "feat(cat): the desktop cat's sizes, frame rate and kitten slots, in the core

DESKTOP_SIZES, desktopFps and DESKTOP_KITTEN_PLACE with desktopKittenSlots, pinned by desktop-cases.json. KITTEN_PLACES and kittenSlots are untouched.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 3: Spots on the screens: `screenKey`, `clampSpot`, `spotFor` and `rememberSpot`

**Files:**
- Modify: `design/prototype/cat-core.js` (a third section above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (keys inside the desktop builder), `tests/cat/desktop.test.mjs` (appended)
- Regenerate: `tests/fixtures/cat/desktop-cases.json`

**Interfaces:**
- Consumes from Tasks 1 and 2: `dkSpot`, `DESKTOP_SIZES`, `desktopSizeOf`; from the core: `isPlain`, `own`, `clamp`.
- Produces in `CatCore`: `DESKTOP_MARGIN`, `DESKTOP_DEFAULT`, `MAX_DESKTOP_SPOTS`, `screenKey`, `isScreenKey`, `defaultDesktopSpot`, `clampSpot`, `cleanDesktopSpots`, `spotFor`, `rememberSpot`, exactly as in "Interface for the app plans" section 3; and the fixture keys `margin`, `defaultSpot`, `maxSpots`, `screenKeys`, `isScreenKey`, `clamps`, `defaultSpots`, `spotFor`, `remembers`, `spotMaps`.

- [ ] **Step 1: Write the failing tests**

```bash
cat >> tests/cat/desktop.test.mjs <<'EOF'

// ── Spots on the screens ─────────────────────────────────────────────────────
// A 14-inch laptop (menu bar 37 points, the Dock 70 at the bottom), a monitor to its right whose top is 100 points higher, and one to its left.
const LAPTOP = { frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true };
const MONITOR = { frame: { x: 1512, y: -100, w: 2560, h: 1440 }, visible: { x: 1512, y: -100, w: 2560, h: 1415 } };
const LEFT = { frame: { x: -1920, y: 0, w: 1920, h: 1080 }, visible: { x: -1920, y: 0, w: 1920, h: 1080 } };
const SIZES = Object.entries(core.DESKTOP_SIZES);
const inset = d => 24 + d / 2;

test('the spot constants: a 24 point margin, a default right of centre and a third down, 32 arrangements', () => {
  assert.equal(core.DESKTOP_MARGIN, 24);
  assert.deepEqual(core.DESKTOP_DEFAULT, { x: .6, y: 1 / 3 });
  assert.equal(core.MAX_DESKTOP_SPOTS, 32);
});

test('screenKey: the frames, rounded, sorted, in one string, and the order the screens come in does not matter', () => {
  assert.equal(core.screenKey([LAPTOP]), '0,0,1512,982');
  assert.equal(core.screenKey([LAPTOP, MONITOR]), '0,0,1512,982|1512,-100,2560,1440');
  assert.equal(core.screenKey([MONITOR, LAPTOP]), core.screenKey([LAPTOP, MONITOR]));
  assert.equal(core.screenKey([LEFT, MONITOR, LAPTOP]), '-1920,0,1920,1080|0,0,1512,982|1512,-100,2560,1440');
  const all = [LEFT, LAPTOP, MONITOR], perms = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]];
  assert.equal(new Set(perms.map(p => core.screenKey(p.map(i => all[i])))).size, 1, 'six orders, one key');
  assert.notEqual(core.screenKey([LAPTOP]), core.screenKey([LAPTOP, MONITOR]), 'a laptop alone and a laptop with a monitor are two arrangements');
  assert.notEqual(core.screenKey([LAPTOP, MONITOR]), core.screenKey([LAPTOP, { ...MONITOR, frame: { ...MONITOR.frame, y: 0 } }]), 'and so are two places for the same monitor');
});

test('screenKey: only the frames count, fractions round half up, and what is not a screen is left out', () => {
  assert.equal(core.screenKey([{ ...LAPTOP, visible: { x: 0, y: 25, w: 1512, h: 800 }, main: false }]), '0,0,1512,982', 'the Dock and the main flag are not part of the key');
  assert.equal(core.screenKey([{ frame: { x: .4, y: -.4, w: 1511.5, h: 981.49 } }]), '0,0,1512,981');
  assert.equal(core.screenKey([{ frame: { x: -.5, y: 2.5, w: 100.5, h: 100.4 } }]), '0,3,101,100', 'half rounds up, towards plus infinity, also below zero');
  assert.equal(core.screenKey([{ frame: { x: .3, y: 9, w: 100, h: 100 } }, { frame: { x: .4, y: 5, w: 100, h: 100 } }]), '0,5,100,100|0,9,100,100', 'sorted after the rounding, not before');
  assert.equal(core.screenKey([LAPTOP, LAPTOP]), '0,0,1512,982|0,0,1512,982', 'mirrored screens are two frames');
  for (const bad of [null, undefined, 'screens', 7, {}, [], [null], [7], [{}], [{ frame: null }], [{ frame: { x: 0, y: 0, w: 0, h: 100 } }], [{ frame: { x: 0, y: 0, w: 100, h: -5 } }], [{ frame: { x: 0, y: 0, w: .4, h: 100 } }],
    [{ frame: { x: '0', y: 0, w: 100, h: 100 } }], [{ frame: { x: NaN, y: 0, w: 100, h: 100 } }], [{ frame: { x: 0, y: 0, w: Infinity, h: 100 } }], [{ frame: { x: 2e6, y: 0, w: 100, h: 100 } }], [{ x: 0, y: 0, w: 100, h: 100 }]])
    assert.equal(core.screenKey(bad), '', String(JSON.stringify(bad)));
  assert.equal(core.screenKey([null, LAPTOP, 7, { frame: 1 }]), '0,0,1512,982', 'the good ones stay');
  const many = Array.from({ length: 40 }, (_, i) => ({ frame: { x: i * 100, y: 0, w: 100, h: 100 } }));
  assert.equal(core.screenKey(many).split('|').length, 16, 'at most sixteen');
  assert.equal(core.screenKey(many), core.screenKey([...many].reverse()));
});

test('isScreenKey: exactly what screenKey writes', () => {
  const r = core.rng(5);
  for (let i = 0; i < 300; i++) {
    const n = 1 + Math.floor(r() * 4), S = Array.from({ length: n }, () => ({ frame: { x: Math.round(r() * 8000 - 4000), y: Math.round(r() * 4000 - 2000), w: 1 + Math.round(r() * 5000), h: 1 + Math.round(r() * 3000) } }));
    assert.ok(core.isScreenKey(core.screenKey(S)), core.screenKey(S));
  }
  assert.ok(core.isScreenKey('0,0,1512,982') && core.isScreenKey('-1920,0,1920,1080|0,0,1512,982'));
  for (const bad of ['', '0,0,1512', '0,0,1512,982,1', '0,0,1512,982|', '|0,0,1512,982', '0,0,1512,982\n', ' 0,0,1512,982', '0,0,1512,982 ', '00,0,1512,982', '-0,0,1512,982', '0,0,0,982', '0,0,1512,0', '0,0,-1512,982', '1512,0,10,10|0,0,10,10',
    '0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10', '0,0,10000000,10', '1.5,0,10,10', '0x1,0,10,10',
    '__proto__', 'constructor', 'prototype', null, undefined, 7, [], ['0,0,1512,982'], {}])
    assert.ok(!core.isScreenKey(bad), String(JSON.stringify(bad)));
});

test('clampSpot: each edge of a laptop, at each size, keeps the cat 24 points from the visible frame (never under the menu bar or the Dock)', () => {
  for (const [id, d] of SIZES) {
    const m = inset(d), c = (x, y) => core.clampSpot({ x, y }, [LAPTOP], id);
    assert.deepEqual(c(0, 400), { x: m, y: 400 }, `${id} left`);
    assert.deepEqual(c(1511, 400), { x: 1512 - m, y: 400 }, `${id} right`);
    assert.deepEqual(c(700, 5), { x: 700, y: 37 + m }, `${id} in the menu bar: below it`);
    assert.deepEqual(c(700, 37), { x: 700, y: 37 + m }, `${id} at the menu bar's lower edge`);
    assert.deepEqual(c(700, 970), { x: 700, y: 37 + 875 - m }, `${id} in the Dock: above it`);
    assert.deepEqual(c(0, 0), { x: m, y: 37 + m }, `${id} top left corner`);
    assert.deepEqual(c(1511, 981), { x: 1512 - m, y: 912 - m }, `${id} bottom right corner`);
    assert.deepEqual(c(700, 400), { x: 700, y: 400 }, `${id}: a spot that is fine stays`);
  }
  assert.deepEqual(core.clampSpot({ x: -50, y: 400 }, [LAPTOP], 'small'), core.defaultDesktopSpot([LAPTOP], 'small'), 'a point outside every frame is on no screen: see below');
  assert.deepEqual(core.clampSpot({ x: 5, y: 5 }, [LAPTOP]), { x: 56, y: 93 }, 'no size is medium');
  assert.deepEqual(core.clampSpot({ x: 5, y: 5 }, [LAPTOP], 'huge'), { x: 56, y: 93 }, 'a size that is not a size is medium');
});

test('clampSpot: a Dock on the side, a menu bar that is gone, and a screen too small for the cat', () => {
  const side = { frame: { x: 0, y: 0, w: 1440, h: 900 }, visible: { x: 80, y: 25, w: 1360, h: 875 }, main: true };
  assert.deepEqual(core.clampSpot({ x: 20, y: 400 }, [side], 'medium'), { x: 80 + 56, y: 400 }, 'a Dock on the left');
  const small = { frame: { x: 0, y: 0, w: 100, h: 90 }, visible: { x: 0, y: 10, w: 100, h: 80 }, main: true };
  assert.deepEqual(core.clampSpot({ x: 90, y: 5 }, [small], 'medium'), { x: 50, y: 50 }, 'a visible frame smaller than the cat and its margins holds the centre');
  assert.deepEqual(core.clampSpot({ x: 90, y: 5 }, [small], 'small'), { x: 100 - 48, y: 10 + 40 }, 'the small size fits across the 100 points, but not down the 80');
  const novis = { frame: { x: 0, y: 0, w: 800, h: 600 } };
  assert.deepEqual(core.clampSpot({ x: 0, y: 0 }, [novis], 'small'), { x: 48, y: 48 }, 'no visible frame: the frame');
  const outside = { frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: 900, y: 900, w: 50, h: 50 } };
  assert.deepEqual(core.clampSpot({ x: 0, y: 0 }, [outside], 'small'), { x: 48, y: 48 }, 'a visible frame outside the frame is the frame');
  const wide = { frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: -100, y: -100, w: 2000, h: 2000 } };
  assert.deepEqual(core.clampSpot({ x: 799, y: 599 }, [wide], 'small'), { x: 800 - 48, y: 600 - 48 }, 'a visible frame that sticks out is held inside the frame');
});

test('clampSpot: two screens, one gone, and a spot in the gap between them', () => {
  const m = inset(64), two = [LAPTOP, MONITOR];
  assert.deepEqual(core.clampSpot({ x: 1600, y: -90 }, two, 'medium'), { x: 1600, y: -100 + m }, 'near the top of the monitor, which starts higher than the laptop');
  assert.deepEqual(core.clampSpot({ x: 1600, y: 10 }, two, 'medium'), { x: 1600, y: 10 }, 'the same spot lower down is fine');
  assert.deepEqual(core.clampSpot({ x: 1511.9, y: 400 }, two, 'medium'), { x: 1512 - m, y: 400 }, 'the last point of the laptop is the laptop');
  assert.deepEqual(core.clampSpot({ x: 1512, y: 400 }, two, 'medium'), { x: 1512 + m, y: 400 }, 'the first point of the monitor is the monitor');
  assert.deepEqual(core.clampSpot({ x: 1600, y: 1300 }, two, 'medium'), { x: 1600, y: -100 + 1415 - m }, 'the monitor\'s Dock');
  // The monitor is unplugged: a spot on it is on no screen, so it goes to the main screen's default spot.
  const dflt = core.defaultDesktopSpot([LAPTOP], 'medium');
  assert.deepEqual(core.clampSpot({ x: 3000, y: 500 }, [LAPTOP], 'medium'), dflt, 'the screen is gone');
  assert.deepEqual(core.clampSpot({ x: -10, y: 500 }, [LAPTOP], 'medium'), dflt, 'left of the only screen');
  assert.deepEqual(core.clampSpot({ x: 700, y: 5000 }, [LAPTOP], 'medium'), dflt, 'far below it');
  const gap = [LAPTOP, { frame: { x: 1700, y: 0, w: 800, h: 600 } }];
  assert.deepEqual(core.clampSpot({ x: 1600, y: 300 }, gap, 'medium'), core.defaultDesktopSpot(gap, 'medium'), 'a gap between two screens is no screen');
  assert.deepEqual(core.clampSpot({ x: -1000, y: 500 }, [LEFT, LAPTOP], 'medium'), { x: -1000, y: 500 }, 'a screen to the left, at negative coordinates');
  assert.deepEqual(core.clampSpot({ x: -1900, y: 20 }, [LEFT, LAPTOP], 'small'), { x: -1920 + 48, y: 48 });
  assert.equal(core.clampSpot({ x: 5, y: 5 }, [], 'medium'), null, 'no screens, no spot');
  assert.equal(core.clampSpot({ x: 5, y: 5 }, [null, {}, { frame: 7 }]), null);
});

test('clampSpot: a spot that is not a spot is the default spot, and the result is always a spot', () => {
  const dflt = core.defaultDesktopSpot([LAPTOP], 'large');
  for (const bad of [null, undefined, 7, 'x', [], [1, 2], {}, { x: 1 }, { x: '1', y: 2 }, { x: NaN, y: 2 }, { x: 1, y: Infinity }, { x: 1e6, y: 0 }]) assert.deepEqual(core.clampSpot(bad, [LAPTOP], 'large'), dflt, String(JSON.stringify(bad)));
  const r = core.rng(17), screens = [[LAPTOP], [LAPTOP, MONITOR], [LEFT, LAPTOP, MONITOR], [LAPTOP, { frame: { x: 1700, y: 0, w: 800, h: 600 } }]];
  for (let i = 0; i < 4000; i++) {
    const S = screens[i % 4], id = core.DESKTOP_SIZE_IDS[i % 3], d = core.DESKTOP_SIZES[id], p = { x: Math.round(r() * 8000 - 2500), y: Math.round(r() * 3500 - 800) };
    const c = core.clampSpot(p, S, id), home = S.map(s => s.visible || s.frame).find(v => c.x >= v.x + inset(d) - 1e-9 && c.x <= v.x + v.w - inset(d) + 1e-9 && c.y >= v.y + inset(d) - 1e-9 && c.y <= v.y + v.h - inset(d) + 1e-9);
    assert.ok(home, `${JSON.stringify(p)} ${id} gave ${JSON.stringify(c)}: not inside any screen's margins`);
    assert.deepEqual(core.clampSpot(c, S, id), c, 'clamping twice changes nothing');
  }
});

test('the default spot: right of centre, a third of the way down the main screen\'s visible frame, held inside its margins', () => {
  const d = core.defaultDesktopSpot([LAPTOP], 'medium');
  near(d.x, 907.2, 'x'); near(d.y, 37 + 875 / 3, 'y');
  assert.ok(d.x > 1512 / 2 && d.y > 37, 'right of the centre and below the notch');
  for (const [id] of SIZES) { const s = core.defaultDesktopSpot([LAPTOP], id); assert.deepEqual(core.clampSpot(s, [LAPTOP], id), s, `${id} is where it may sit`); }
  // The main screen: the one marked main, else the one at the origin, else the first.
  assert.deepEqual(core.defaultDesktopSpot([MONITOR, { ...LAPTOP, main: false }], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), 'the one at the origin');
  assert.notDeepEqual(core.defaultDesktopSpot([{ ...LAPTOP, main: false }, { ...MONITOR, main: true }], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), 'a screen marked main wins');
  assert.deepEqual(core.defaultDesktopSpot([LEFT, MONITOR], 'small'), core.defaultDesktopSpot([MONITOR, LEFT], 'small'), 'with none of them, the first by frame');
  assert.equal(core.defaultDesktopSpot([], 'medium'), null);
});

test('cleanDesktopSpots: an object or JSON text of screen keys to spots; anything else is dropped', () => {
  const key = core.screenKey([LAPTOP]), key2 = core.screenKey([LAPTOP, MONITOR]);
  const ok = { [key2]: { x: 2000, y: 300 }, [key]: { x: 700, y: 400 } };
  assert.deepEqual(core.cleanDesktopSpots(ok), ok);
  assert.deepEqual(Object.keys(core.cleanDesktopSpots(ok)), [key, key2].sort(), 'in code-point order');
  assert.deepEqual(core.cleanDesktopSpots(JSON.stringify(ok)), ok, 'as the JSON text the Mac stores');
  assert.deepEqual(core.cleanDesktopSpots({ [key]: { x: 1, y: 2, z: 3, name: 'x' } }), { [key]: { x: 1, y: 2 } }, 'only x and y are kept');
  for (const bad of [null, undefined, 7, true, [], [1], 'junk', '', '{"a":', "{'a':1}", '[]', 'null', '7', '{"a":1}x', {}, { cats: 1 }]) assert.deepEqual(core.cleanDesktopSpots(bad), {}, String(JSON.stringify(bad)));
  const keys = { '': { x: 1, y: 1 }, '0,0,0,0': { x: 1, y: 1 }, '00,0,100,100': { x: 1, y: 1 }, '0,0,100,100\n': { x: 1, y: 1 }, constructor: { x: 1, y: 1 }, prototype: { x: 1, y: 1 }, [key]: { x: 5, y: 5 } };
  assert.deepEqual(core.cleanDesktopSpots(keys), { [key]: { x: 5, y: 5 } });
  const spots = {}; for (const bad of [null, 7, 'x', [1, 2], {}, { x: 1 }, { x: '1', y: 2 }, { x: NaN, y: 2 }, { x: 1, y: 1e6 }, true]) spots[core.screenKey([{ frame: { x: Object.keys(spots).length, y: 0, w: 100, h: 100 } }])] = bad;
  assert.deepEqual(core.cleanDesktopSpots(spots), {}, 'a spot that is not a spot is dropped with its key');
  assert.deepEqual(core.cleanDesktopSpots(core.cleanDesktopSpots(ok)), ok);
});

test('cleanDesktopSpots: hostile files never throw, never pollute, and keep at most 32 arrangements', () => {
  const evil = JSON.parse('{"__proto__":{"x":1,"y":2},"0,0,100,100":{"__proto__":{"x":9},"x":3,"y":4}}');
  const out = core.cleanDesktopSpots(evil);
  assert.deepEqual(out, { '0,0,100,100': { x: 3, y: 4 } });
  assert.equal(Object.getPrototypeOf(out), Object.prototype); assert.equal({}.x, undefined);
  const many = Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`${i},0,100,100`, { x: i, y: 1 }]));
  const cut = core.cleanDesktopSpots(many), keys = Object.keys(cut);
  assert.equal(keys.length, 32);
  assert.deepEqual(keys, Object.keys(many).filter(core.isScreenKey).sort().slice(0, 32), 'the first 32 by code-point order');
  assert.deepEqual(core.cleanDesktopSpots(JSON.stringify(many)), cut, 'and the same from JSON text');
  const raw = { '0,0,100,100': { x: 1, y: 2 } }, a = core.cleanDesktopSpots(raw), b = core.cleanDesktopSpots(raw);
  a['0,0,100,100'].x = 99; assert.equal(b['0,0,100,100'].x, 1); assert.equal(raw['0,0,100,100'].x, 1, 'nothing is shared with the input');
});

test('spotFor: the spot remembered for this arrangement, held where the cat may sit, else the default', () => {
  const k1 = core.screenKey([LAPTOP]), k2 = core.screenKey([LAPTOP, MONITOR]);
  const spots = { [k1]: { x: 300, y: 400 }, [k2]: { x: 2000, y: 800 } };
  assert.deepEqual(core.spotFor(spots, [LAPTOP], 'medium'), { x: 300, y: 400 }, 'a laptop alone');
  assert.deepEqual(core.spotFor(spots, [MONITOR, LAPTOP], 'medium'), { x: 2000, y: 800 }, 'with the monitor, whichever order the screens come in: its own spot');
  assert.deepEqual(core.spotFor({}, [LAPTOP], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), 'nothing remembered: the default spot');
  assert.deepEqual(core.spotFor(spots, [LEFT, LAPTOP], 'medium'), core.defaultDesktopSpot([LEFT, LAPTOP], 'medium'), 'an arrangement never seen');
  assert.deepEqual(core.spotFor({ [k1]: { x: 5, y: 5 } }, [LAPTOP], 'large'), { x: 72, y: 37 + 72 }, 'a remembered spot the Dock or menu bar now covers is held inside');
  assert.deepEqual(core.spotFor({ [k1]: { x: 5000, y: 5 } }, [LAPTOP], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), 'a remembered spot that is on no screen goes to the default');
  assert.deepEqual(core.spotFor(JSON.stringify(spots), [LAPTOP], 'medium'), { x: 300, y: 400 }, 'the Mac\'s JSON text');
  for (const bad of [null, 'junk', 7, [], { [k1]: 'x' }, { constructor: 1 }]) assert.deepEqual(core.spotFor(bad, [LAPTOP], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), String(JSON.stringify(bad)));
  assert.equal(core.spotFor(spots, [], 'medium'), null);
  assert.equal(core.spotFor(spots, 'screens', 'medium'), null);
});

test('rememberSpot: this arrangement\'s spot is the clamped one, the others stay, and a full map still keeps the new key', () => {
  const k1 = core.screenKey([LAPTOP]), k2 = core.screenKey([LAPTOP, MONITOR]);
  assert.deepEqual(core.rememberSpot({}, [LAPTOP], { x: 5, y: 5 }, 'medium'), { [k1]: { x: 56, y: 93 } }, 'clamped');
  const two = core.rememberSpot({ [k1]: { x: 300, y: 400 } }, [LAPTOP, MONITOR], { x: 2000, y: 800 }, 'medium');
  assert.deepEqual(two, { [k1]: { x: 300, y: 400 }, [k2]: { x: 2000, y: 800 } }, 'the laptop alone keeps its own spot');
  assert.deepEqual(core.rememberSpot(two, [LAPTOP], { x: 600, y: 600 }, 'medium')[k2], { x: 2000, y: 800 });
  assert.deepEqual(core.rememberSpot(two, [LAPTOP], { x: 600, y: 600 }, 'medium')[k1], { x: 600, y: 600 });
  assert.deepEqual(core.rememberSpot({ [k1]: { x: 1, y: 1 } }, [LAPTOP], { x: 9000, y: 9000 }, 'medium')[k1], core.defaultDesktopSpot([LAPTOP], 'medium'), 'a spot on no screen is remembered as the default');
  assert.deepEqual(core.rememberSpot(two, [], { x: 5, y: 5 }, 'medium'), two, 'no screens: nothing changes');
  const full = Object.fromEntries(Array.from({ length: 32 }, (_, i) => [`${i},0,100,100`, { x: i, y: 1 }]));
  const grown = core.rememberSpot(full, [LAPTOP], { x: 600, y: 600 }, 'medium');
  assert.equal(Object.keys(grown).length, 32); assert.deepEqual(grown[k1], { x: 600, y: 600 }, 'the new arrangement is kept, an old one makes room');
  assert.deepEqual(Object.keys(grown), Object.keys(grown).slice().sort());
  const frozen = Object.freeze({ [k1]: Object.freeze({ x: 1, y: 1 }) });
  assert.doesNotThrow(() => core.rememberSpot(frozen, [LAPTOP], { x: 100, y: 200 }, 'small'));
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 42`, `# pass 29`, `# fail 13`: the 29 tests of Tasks 1 and 2 pass, the 13 new ones need the section.

- [ ] **Step 3: Add the section to the core**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── The desktop cat: spots on the screens (sub-project H) ────────────────────
// Where the cat sits, per arrangement of connected screens. A screen is {frame: {x, y, w, h}, visible: {x, y, w, h}, main: true}, in points with y down and the origin at
// the top left of the main screen (the Mac converts from AppKit's bottom-left origin): `frame` is the whole screen and `visible` what the menu bar and the Dock leave
// (it defaults to the frame and is held inside it); `main` marks the screen with the menu bar. A spot is the cat's head centre {x, y}.
/** The cat keeps this many points between its head and the edge of the visible frame, so it never sits under the menu bar or the Dock. */
const DESKTOP_MARGIN=24;
/** The first spot ever: this fraction of the main screen's visible frame across (right of centre) and down (a third, below the notch). */
const DESKTOP_DEFAULT={x:.6,y:1/3};
/** A stored map keeps the spots of at most this many screen arrangements (the first by code-point order of their keys). */
const MAX_DESKTOP_SPOTS=32;
const dkRect=v=>isPlain(v)&&['x','y','w','h'].every(k=>typeof v[k]==='number'&&Math.abs(v[k])<=1e6)&&v.w>=1&&v.h>=1?{x:v.x,y:v.y,w:v.w,h:v.h}:null;
/** The screens that are screens, as {frame, visible, main}, sorted by frame and at most 16. A screen without a usable frame is dropped; a visible frame that is missing or outside its frame is the frame. */
function dkScreens(raw){const out=[];
 for(const s of Array.isArray(raw)?raw.slice(0,256):[]){const f=isPlain(s)?dkRect(s.frame):null;if(!f)continue;
  const v=dkRect(s.visible),x0=v?Math.max(v.x,f.x):0,y0=v?Math.max(v.y,f.y):0,x1=v?Math.min(v.x+v.w,f.x+f.w):0,y1=v?Math.min(v.y+v.h,f.y+f.h):0;
  out.push({frame:f,visible:v&&x1>x0&&y1>y0?{x:x0,y:y0,w:x1-x0,h:y1-y0}:f,main:s.main===true})}
 return out.sort((a,b)=>a.frame.x-b.frame.x||a.frame.y-b.frame.y||a.frame.w-b.frame.w||a.frame.h-b.frame.h).slice(0,16)}
const dkRound=v=>Math.floor(v+.5);
/**
 * The key a screen arrangement is remembered under: the frames, rounded to whole points (half up: floor(v + 0.5)), sorted, written "x,y,w,h" and joined with "|". The order
 * the screens come in does not matter; the visible frames and the main flag are not part of it (moving the Dock must not forget the spot). No screens: "".
 */
function screenKey(screens){return dkScreens(screens).map(s=>[s.frame.x,s.frame.y,s.frame.w,s.frame.h].map(dkRound)).sort((a,b)=>a[0]-b[0]||a[1]-b[1]||a[2]-b[2]||a[3]-b[3]).map(r=>r.join(',')).join('|')}
const SCREEN_KEY=/^-?\d{1,7},-?\d{1,7},\d{1,7},\d{1,7}(\|-?\d{1,7},-?\d{1,7},\d{1,7},\d{1,7}){0,15}$/;
/** True for exactly the strings screenKey writes: whole-string shape, no leading zeros or -0, positive sizes, frames in sorted order, at most 16. */
const isScreenKey=k=>typeof k==='string'&&SCREEN_KEY.test(k)&&screenKey(k.split('|').map(q=>{const [x,y,w,h]=q.split(',').map(Number);return{frame:{x,y,w,h}}}))===k;
const dkHas=(r,p)=>p.x>=r.x&&p.x<r.x+r.w&&p.y>=r.y&&p.y<r.y+r.h;
const dkMain=S=>S.find(s=>s.main)||S.find(s=>dkHas(s.frame,{x:0,y:0}))||S[0];
/** The spot held inside a screen's visible frame, `d` (the head width) and DESKTOP_MARGIN from every edge; a frame too small for that holds the centre. */
const dkPlace=(s,p,d)=>{const v=s.visible,m=DESKTOP_MARGIN+d/2,at=(lo,len,c)=>len<=2*m?lo+len/2:clamp(c,lo+m,lo+len-m);return{x:at(v.x,v.w,p.x),y:at(v.y,v.h,p.y)}};
/** The first spot ever, on the main screen (the one marked main, else the one at the origin, else the first by frame), for a size ID. null with no screens. */
function defaultDesktopSpot(screens,size){const S=dkScreens(screens);if(!S.length)return null;const s=dkMain(S),v=s.visible;
 return dkPlace(s,{x:v.x+v.w*DESKTOP_DEFAULT.x,y:v.y+v.h*DESKTOP_DEFAULT.y},DESKTOP_SIZES[desktopSizeOf(size)])}
/**
 * Keeps a spot where the cat may sit: on the screen whose frame holds it, inside that screen's visible frame, DESKTOP_MARGIN from the head's edge (so the centre is
 * margin + d/2 from every edge). A spot on no screen (its screen was unplugged, or it is not a spot) moves to the main screen's default spot. `size` is a size ID
 * (anything else is medium). null with no screens.
 */
function clampSpot(spot,screens,size){const S=dkScreens(screens);if(!S.length)return null;const p=dkSpot(spot),s=p&&S.find(q=>dkHas(q.frame,p));
 return s?dkPlace(s,p,DESKTOP_SIZES[desktopSizeOf(size)]):defaultDesktopSpot(screens,size)}
/**
 * A stored map from screen key to spot, cleaned. It may be an object, or the JSON text of one (the Mac stores text; text that is not JSON is {}). A key that is not
 * what screenKey writes is dropped (`__proto__` included), and so is a value that is not a spot. The result is in code-point order of the keys, at most MAX_DESKTOP_SPOTS.
 */
function cleanDesktopSpots(raw){let v=raw;if(typeof v==='string'){try{v=JSON.parse(v)}catch{return{}}}
 const out={};if(!isPlain(v))return out;let n=0;
 for(const k of Object.keys(v).filter(isScreenKey).sort()){if(n>=MAX_DESKTOP_SPOTS)break;const s=dkSpot(v[k]);if(s){out[k]=s;n++}}
 return out}
/** The spot to use now: the one remembered for this arrangement of screens, held where the cat may sit, else the default spot. null with no screens. */
function spotFor(spots,screens,size){if(!dkScreens(screens).length)return null;const k=screenKey(screens),m=cleanDesktopSpots(spots);
 return own(m,k)?clampSpot(m[k],screens,size):defaultDesktopSpot(screens,size)}
/** The map after the cat was released at `spot` on these screens: this arrangement's spot is the clamped one, the others stay. Always keeps the new key, even in a full map. */
function rememberSpot(spots,screens,spot,size){const m=cleanDesktopSpots(spots),c=clampSpot(spot,screens,size);if(!c)return m;const k=screenKey(screens),out={};
 for(const q of Object.keys(m).filter(q=>q!==k).slice(0,MAX_DESKTOP_SPOTS-1).concat(k).sort())out[q]=q===k?c:m[q];return out}
Object.assign(api,{DESKTOP_MARGIN,DESKTOP_DEFAULT,MAX_DESKTOP_SPOTS,screenKey,isScreenKey,defaultDesktopSpot,clampSpot,cleanDesktopSpots,spotFor,rememberSpot});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 56 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 42`, `# pass 42`, `# fail 0`.

- [ ] **Step 5: Prove the guards bite (not committed)**

The margin is the head's edge's, and the key is sorted after the rounding. Take each out, see its tests fail, put it back.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const v=s.visible,m=DESKTOP_MARGIN+d/2,"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const v=s.visible,m=DESKTOP_MARGIN,"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const v=s.visible,m=DESKTOP_MARGIN,"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const v=s.visible,m=DESKTOP_MARGIN+d/2,"))
PY
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = ".sort((a,b)=>a[0]-b[0]||a[1]-b[1]||a[2]-b[2]||a[3]-b[3]).map(r=>r.join(','))"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, ".map(r=>r.join(','))"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = ".map(r=>r.join(','))"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, ".sort((a,b)=>a[0]-b[0]||a[1]-b[1]||a[2]-b[2]||a[3]-b[3]).map(r=>r.join(','))"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: first run six `not ok` lines (34, 35, 36, 37, 41 and 42: the clamps, `spotFor` and `rememberSpot`), `# pass 36`, `# fail 6`; second run `not ok 32 - screenKey: only the frames count, fractions round half up, and what is not a screen is left out`, `# pass 41`, `# fail 1`; after putting both lines back, `# pass 42` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗"`
Expected: `# tests 273`, `# pass 273`, `# fail 0`.

- [ ] **Step 7: Add the replay tests and the fixture keys**

```bash
cat >> tests/cat/desktop.test.mjs <<'EOF'

test('desktop-cases.json: the spot constants and the screen keys replay, in every order', () => {
  assert.equal(fx.margin, 24); assert.deepEqual(compare(fx.defaultSpot, core.DESKTOP_DEFAULT), []); assert.equal(fx.maxSpots, 32);
  for (const c of fx.screenKeys) assert.equal(core.screenKey(c.screens), c.out, c.name);
  for (const c of fx.isScreenKey) assert.equal(core.isScreenKey(c.key), c.out, JSON.stringify(c.key));
  const named = n => fx.screenKeys.find(c => c.name === n).out;
  assert.equal(named('a laptop and a monitor to its right'), named('the same, the other way round'));
  assert.equal(named('a monitor on each side'), named('the same, in another order'));
  assert.equal(named('a monitor on each side'), named('and another'));
  assert.equal(named('the Dock moved: the same key'), named('a laptop'));
  assert.equal(named('no visible frame: the same key'), named('a laptop'));
  assert.equal(named('nothing'), ''); assert.equal(named('null'), '');
  assert.ok(fx.isScreenKey.filter(c => c.out).length >= 3 && fx.isScreenKey.filter(c => !c.out).length >= 20);
});

test('desktop-cases.json: the clamps replay, on each edge of each size, with two screens and one gone', () => {
  for (const c of fx.clamps) assert.deepEqual(compare(roundTrip(core.clampSpot(c.spot, c.screens, c.size)), c.out), [], c.name);
  assert.equal(fx.clamps.filter(c => /^(small|medium|large): /.test(c.name)).length, 24, 'eight spots at each of the three sizes');
  const at = n => fx.clamps.find(c => c.name === n).out;
  assert.deepEqual(at('medium: on the left edge'), { x: 56, y: 400 }); assert.deepEqual(at('medium: in the menu bar'), { x: 700, y: 93 }); assert.deepEqual(at('large: in the Dock'), { x: 700, y: 840 });
  assert.deepEqual(compare(at('the monitor is unplugged: the spot is on no screen'), core.defaultDesktopSpot([fx.clamps[0].screens[0]], 'medium')), []);
  assert.equal(at('no screens'), null); assert.equal(at('screens that are not screens'), null);
  assert.ok(fx.clamps.every(c => c.out === null || ['x', 'y'].every(k => Number.isInteger(c.out[k] * 2) || Math.abs(c.out[k]) < 1000)), 'a fraction comes only below 1000 points, where 12 significant digits keep the 1e-9 tolerance');
});

test('desktop-cases.json: the default spots, the spot per arrangement and what is remembered replay', () => {
  for (const c of fx.defaultSpots) assert.deepEqual(compare(roundTrip(core.defaultDesktopSpot(c.screens, c.size)), c.out), [], c.name);
  for (const c of fx.spotFor) assert.deepEqual(compare(roundTrip(core.spotFor(c.spots, c.screens, c.size)), c.out), [], c.name);
  for (const c of fx.remembers) assert.deepEqual(compare(roundTrip(core.rememberSpot(c.spots, c.screens, c.spot, c.size)), c.out), [], c.name);
  for (const c of fx.spotMaps) assert.deepEqual(compare(roundTrip(core.cleanDesktopSpots(c.raw)), c.out), [], c.name);
  assert.equal(fx.defaultSpots.find(c => c.name === 'no screens').out, null);
  assert.equal(Object.keys(fx.spotMaps.find(c => c.name.startsWith('33 keep')).out).length, 32);
  assert.equal(Object.keys(fx.remembers.find(c => c.name === 'a full map makes room for the new arrangement').out).length, 32);
  assert.ok(fx.spotFor.find(c => c.name.startsWith('a laptop alone')).out.x !== fx.spotFor.find(c => c.name.startsWith('with the monitor')).out.x, 'two arrangements, two spots');
});
EOF
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '  // @@DESKTOP-SECTIONS: each task adds its keys to `out` immediately above this line.'
assert s.count(marker) == 1
snippet = r'''  out.note += ' screenKeys: screenKey(screens) is out. isScreenKey: isScreenKey(key) is out. clamps: clampSpot(spot, screens, size). defaultSpots: defaultDesktopSpot(screens, size). spotFor: spotFor(spots, screens, size). remembers: rememberSpot(spots, screens, spot, size). spotMaps: cleanDesktopSpots(raw). A screen is {frame, visible, main}; a missing size is not given.';
  // Spots on the screens. A screen is {frame, visible, main}: the frame is the whole screen, `visible` what the menu bar and the Dock leave, `main` marks the screen with the menu bar;
  // points, y down, the origin at the top left of the main screen. size is a size ID. `margin` is the room between the head and the visible frame's edge (the centre is margin + d/2 away).
  out.margin = core.DESKTOP_MARGIN;
  out.defaultSpot = core.DESKTOP_DEFAULT;
  out.maxSpots = core.MAX_DESKTOP_SPOTS;
  const LAPTOP = { frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true };
  const MONITOR = { frame: { x: 1512, y: -100, w: 2560, h: 1440 }, visible: { x: 1512, y: -100, w: 2560, h: 1415 } };
  const LEFT = { frame: { x: -1920, y: 0, w: 1920, h: 1080 }, visible: { x: -1920, y: 0, w: 1920, h: 1080 } };
  const WIN = { frame: { x: 0, y: 0, w: 1920, h: 1080 }, visible: { x: 0, y: 0, w: 1920, h: 1040 }, main: true };
  const GAP = { frame: { x: 1700, y: 0, w: 800, h: 600 } };
  out.screenKeys = [
    ['a laptop', [LAPTOP]], ['a laptop and a monitor to its right', [LAPTOP, MONITOR]], ['the same, the other way round', [MONITOR, LAPTOP]], ['a monitor on each side', [LEFT, LAPTOP, MONITOR]],
    ['the same, in another order', [MONITOR, LEFT, LAPTOP]], ['and another', [LAPTOP, MONITOR, LEFT]], ['a Windows desktop with a taskbar', [WIN]],
    ['the Dock moved: the same key', [{ ...LAPTOP, visible: { x: 80, y: 25, w: 1432, h: 957 }, main: false }]], ['no visible frame: the same key', [{ frame: LAPTOP.frame }]],
    ['fractions round half up', [{ frame: { x: -.5, y: 2.5, w: 100.5, h: 100.4 } }]], ['sorted after the rounding, not before', [{ frame: { x: .3, y: 9, w: 100, h: 100 } }, { frame: { x: .4, y: 5, w: 100, h: 100 } }]],
    ['mirrored screens are two frames', [LAPTOP, LAPTOP]], ['screens that are not screens are left out', [null, LAPTOP, 7, { frame: 1 }, { frame: { x: 0, y: 0, w: 0, h: 5 } }, { frame: { x: 0, y: 0, w: .4, h: 5 } }, { frame: { x: '0', y: 0, w: 5, h: 5 } }]],
    ['nothing', []], ['null', null], ['not a list', 'screens'], ['an object', {}], ['a frame beyond the limit', [{ frame: { x: 2e6, y: 0, w: 100, h: 100 } }]],
    ['40 screens: the first 16 by frame', Array.from({ length: 40 }, (_, i) => ({ frame: { x: i * 100, y: 0, w: 100, h: 100 } }))],
  ].map(([name, screens]) => ({ name, screens, out: core.screenKey(screens) }));
  out.isScreenKey = [
    '0,0,1512,982', '0,0,1512,982|1512,-100,2560,1440', '-1920,0,1920,1080|0,0,1512,982|1512,-100,2560,1440', '', '0,0,1512', '0,0,1512,982,1', '0,0,1512,982|', '|0,0,1512,982', '0,0,1512,982\n', ' 0,0,1512,982', '0,0,1512,982 ',
    '00,0,1512,982', '-0,0,1512,982', '0,0,0,982', '0,0,1512,0', '0,0,-1512,982', '1512,0,10,10|0,0,10,10', ['0,0,10,10', '0,0,10,10'].join('|'), Array(17).fill('0,0,10,10').join('|'), Array(16).fill('0,0,10,10').join('|'),
    '0,0,10000000,10', '1.5,0,10,10', '0x1,0,10,10', '__proto__', 'constructor', 'prototype', null, 7, [], {},
  ].map(key => ({ key, out: core.isScreenKey(key) }));
  const C = (name, spot, screens, size) => ({ name, spot, screens, ...(size === undefined ? {} : { size }), out: core.clampSpot(spot, screens, size) });
  out.clamps = [
    ...core.DESKTOP_SIZE_IDS.flatMap(size => [
      C(`${size}: a spot that is fine stays`, { x: 700, y: 400 }, [LAPTOP], size), C(`${size}: on the left edge`, { x: 0, y: 400 }, [LAPTOP], size), C(`${size}: on the right edge`, { x: 1511, y: 400 }, [LAPTOP], size),
      C(`${size}: in the menu bar`, { x: 700, y: 5 }, [LAPTOP], size), C(`${size}: at the menu bar's lower edge`, { x: 700, y: 37 }, [LAPTOP], size), C(`${size}: in the Dock`, { x: 700, y: 970 }, [LAPTOP], size),
      C(`${size}: the top left corner`, { x: 0, y: 0 }, [LAPTOP], size), C(`${size}: the bottom right corner`, { x: 1511, y: 981 }, [LAPTOP], size),
    ]),
    C('no size is medium', { x: 5, y: 5 }, [LAPTOP], undefined), C('a size that is not a size is medium', { x: 5, y: 5 }, [LAPTOP], 'huge'),
    C('a Windows taskbar', { x: 960, y: 1070 }, [WIN], 'large'),
    C('a Dock on the left', { x: 20, y: 400 }, [{ frame: { x: 0, y: 0, w: 1440, h: 900 }, visible: { x: 80, y: 25, w: 1360, h: 875 }, main: true }], 'medium'),
    C('a visible frame smaller than the cat and its margins holds the centre', { x: 90, y: 5 }, [{ frame: { x: 0, y: 0, w: 100, h: 90 }, visible: { x: 0, y: 10, w: 100, h: 80 }, main: true }], 'medium'),
    C('the small size fits across 100 points but not down 80', { x: 90, y: 5 }, [{ frame: { x: 0, y: 0, w: 100, h: 90 }, visible: { x: 0, y: 10, w: 100, h: 80 }, main: true }], 'small'),
    C('no visible frame: the frame', { x: 0, y: 0 }, [{ frame: { x: 0, y: 0, w: 800, h: 600 } }], 'small'),
    C('a visible frame outside the frame is the frame', { x: 0, y: 0 }, [{ frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: 900, y: 900, w: 50, h: 50 } }], 'small'),
    C('a visible frame that sticks out is held inside the frame', { x: 799, y: 599 }, [{ frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: -100, y: -100, w: 2000, h: 2000 } }], 'small'),
    C('two screens: near the top of the monitor, which starts higher', { x: 1600, y: -90 }, [LAPTOP, MONITOR], 'medium'), C('two screens: the same spot lower down', { x: 1600, y: 10 }, [LAPTOP, MONITOR], 'medium'),
    C('two screens: the last point of the laptop', { x: 1511.5, y: 400 }, [LAPTOP, MONITOR], 'medium'), C('two screens: the first point of the monitor', { x: 1512, y: 400 }, [LAPTOP, MONITOR], 'medium'),
    C('two screens: the monitor\'s bottom edge', { x: 1600, y: 1300 }, [LAPTOP, MONITOR], 'medium'),
    C('a screen to the left, at negative coordinates', { x: -1000, y: 500 }, [LEFT, LAPTOP], 'medium'), C('a screen to the left, in its corner', { x: -1900, y: 20 }, [LEFT, LAPTOP], 'small'),
    C('the monitor is unplugged: the spot is on no screen', { x: 3000, y: 500 }, [LAPTOP], 'medium'), C('left of the only screen', { x: -10, y: 500 }, [LAPTOP], 'medium'), C('far below the only screen', { x: 700, y: 5000 }, [LAPTOP], 'medium'),
    C('a gap between two screens', { x: 1600, y: 300 }, [LAPTOP, GAP], 'medium'),
    ...[['null', null], ['text', 'x'], ['a number', 7], ['an array', [1, 2]], ['an empty object', {}], ['no y', { x: 1 }], ['text coordinates', { x: '1', y: 2 }], ['beyond the limit', { x: 1e6, y: 0 }]].map(([n, spot]) => C(`a spot that is ${n}`, spot, [LAPTOP], 'large')),
    C('no screens', { x: 5, y: 5 }, [], 'medium'), C('screens that are not screens', { x: 5, y: 5 }, [null, {}, { frame: 7 }], 'medium'),
  ];
  out.defaultSpots = [
    ...core.DESKTOP_SIZE_IDS.map(size => ({ name: `a laptop, ${size}`, screens: [LAPTOP], size })), { name: 'a Windows desktop', screens: [WIN], size: 'medium' },
    { name: 'the screen marked main wins', screens: [{ ...LAPTOP, main: false }, { ...MONITOR, main: true }], size: 'medium' }, { name: 'none marked main: the one at the origin', screens: [MONITOR, { ...LAPTOP, main: false }], size: 'medium' },
    { name: 'none marked and none at the origin: the first by frame', screens: [MONITOR, LEFT], size: 'small' }, { name: 'no screens', screens: [], size: 'medium' },
  ].map(c => ({ ...c, out: core.defaultDesktopSpot(c.screens, c.size) }));
  const K1 = core.screenKey([LAPTOP]), K2 = core.screenKey([LAPTOP, MONITOR]);
  const S = (name, spots, screens, size) => ({ name, spots, screens, size, out: core.spotFor(spots, screens, size) });
  const REMEMBERED = { [K1]: { x: 300, y: 400 }, [K2]: { x: 2000, y: 800 } };
  out.spotFor = [
    S('a laptop alone has its own spot', REMEMBERED, [LAPTOP], 'medium'), S('with the monitor it has another, whichever order the screens come in', REMEMBERED, [MONITOR, LAPTOP], 'medium'),
    S('nothing remembered: the default spot', {}, [LAPTOP], 'medium'), S('an arrangement never seen', REMEMBERED, [LEFT, LAPTOP], 'medium'),
    S('a remembered spot the menu bar now covers is held inside', { [K1]: { x: 5, y: 5 } }, [LAPTOP], 'large'), S('a remembered spot on no screen is the default', { [K1]: { x: 5000, y: 5 } }, [LAPTOP], 'medium'),
    S('the Mac\'s JSON text', JSON.stringify(REMEMBERED), [LAPTOP], 'medium'), S('text that is not JSON', '{"a":', [LAPTOP], 'medium'), S('null', null, [LAPTOP], 'medium'),
    S('a spot that is not a spot', { [K1]: 'x' }, [LAPTOP], 'medium'), S('a prototype name as a key', { constructor: 1 }, [LAPTOP], 'medium'), S('no screens', REMEMBERED, [], 'medium'), S('not a list of screens', REMEMBERED, 'screens', 'medium'),
  ];
  const R = (name, spots, screens, spot, size) => ({ name, spots, screens, spot, size, out: core.rememberSpot(spots, screens, spot, size) });
  const FULL = Object.fromEntries(Array.from({ length: 32 }, (_, i) => [`${i},0,100,100`, { x: i, y: 1 }]));
  out.remembers = [
    R('into nothing, clamped', {}, [LAPTOP], { x: 5, y: 5 }, 'medium'), R('beside another arrangement', { [K1]: { x: 300, y: 400 } }, [LAPTOP, MONITOR], { x: 2000, y: 800 }, 'medium'),
    R('over the same arrangement', REMEMBERED, [LAPTOP], { x: 600, y: 600 }, 'medium'), R('a spot on no screen is remembered as the default', { [K1]: { x: 1, y: 1 } }, [LAPTOP], { x: 9000, y: 9000 }, 'medium'),
    R('no screens: nothing changes', REMEMBERED, [], { x: 5, y: 5 }, 'medium'), R('a full map makes room for the new arrangement', FULL, [LAPTOP], { x: 600, y: 600 }, 'medium'),
    R('a full map that already has the arrangement', { ...FULL, [K1]: { x: 1, y: 1 } }, [LAPTOP], { x: 700, y: 700 }, 'small'), R('JSON text in', JSON.stringify({ [K1]: { x: 300, y: 400 } }), [LAPTOP, MONITOR], { x: 2000, y: 800 }, 'large'),
  ];
  out.spotMaps = [
    ['a map', REMEMBERED], ['an empty map', {}], ['the Mac\'s JSON text', JSON.stringify(REMEMBERED)], ['only x and y are kept', { [K1]: { x: 1, y: 2, z: 3, name: 'x' } }],
    ['keys that are not screen keys', { '': { x: 1, y: 1 }, '0,0,0,0': { x: 1, y: 1 }, '00,0,100,100': { x: 1, y: 1 }, '0,0,100,100\n': { x: 1, y: 1 }, '1,0,100,100|0,0,100,100': { x: 1, y: 1 }, constructor: { x: 1, y: 1 }, prototype: { x: 1, y: 1 }, [K1]: { x: 5, y: 5 } }],
    ['values that are not spots', { '0,0,100,100': null, '1,0,100,100': 7, '2,0,100,100': 'x', '3,0,100,100': [1, 2], '4,0,100,100': {}, '5,0,100,100': { x: 1 }, '6,0,100,100': { x: '1', y: 2 }, '7,0,100,100': { x: 1, y: 1e6 }, '8,0,100,100': { x: 1, y: 2 } }],
    ['out of order comes back in order', { [K2]: { x: 2000, y: 300 }, [K1]: { x: 700, y: 400 } }], ['JSON text cut off', '{"0,0,100,100":'], ['JSON text with single quotes', "{'0,0,100,100':{'x':1,'y':2}}"], ['JSON text that is an array', '[]'],
    ['JSON text that is null', 'null'], ['text that is not JSON', 'junk'], ['null', null], ['a number', 7], ['true', true], ['an array', [{ x: 1, y: 2 }]],
    ['32 arrangements fit', FULL], ['33 keep the first 32 by code-point order', { ...FULL, '99,0,100,100': { x: 1, y: 1 }, '5,5,100,100': { x: 1, y: 1 } }],
  ].map(([name, raw]) => ({ name, raw, out: core.cleanDesktopSpots(raw) }));

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/desktop-cases.json
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"
```

Expected: the first run three `not ok` lines (43, 44 and 45: the replays of the screen keys, the clamps and the spots), `# tests 45`, `# pass 42`, `# fail 3`; then `wrote 15 fixture files to tests/fixtures/cat`, a `desktop-cases.json` of about 77 KB, and `# tests 45`, `# pass 45`, `# fail 0`.

- [ ] **Step 8: Run the contract and the additive check**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗|✓ [0-9]|✓ two"`
Expected: `# tests 276`, `# pass 276`, `# fail 0`, `✓ 15 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 1627851 | tail -2`
Expected: `  + desktop-cases.json is new` and `✓ fixtures changed only by addition since 1627851`.

- [ ] **Step 9: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js`, ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/desktop.test.mjs`, ` M tests/fixtures/cat/desktop-cases.json`.

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/desktop.test.mjs tests/fixtures/cat/desktop-cases.json
git commit -m "feat(cat): the desktop cat's spots per screen arrangement, in the core

screenKey, clampSpot, defaultDesktopSpot, spotFor, rememberSpot and cleanDesktopSpots, pinned by desktop-cases.json.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 4: The stored settings: `cleanDesktopSettings`

**Files:**
- Modify: `design/prototype/cat-core.js` (a fourth section above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (keys inside the desktop builder), `tests/cat/desktop.test.mjs` (appended)
- Regenerate: `tests/fixtures/cat/desktop-cases.json`

**Interfaces:**
- Consumes from Tasks 2 and 3: `desktopSizeOf`, `cleanDesktopSpots`, `isScreenKey`; from the core: `isPlain`, `cleanCatSettings`, `cleanDisplaySettings`.
- Produces in `CatCore`: `cleanDesktopSettings`, `defaultDesktopSettings`, exactly as in "Interface for the app plans" section 4; and the fixture keys `settingsDefaults` and `settingsCases`.

- [ ] **Step 1: Write the failing tests**

```bash
cat >> tests/cat/desktop.test.mjs <<'EOF'

// ── The stored settings ──────────────────────────────────────────────────────
const KEY = '0,0,1512,982', KEY2 = '0,0,1512,982|1512,-100,2560,1440';
const DESKTOP_DEFAULTS = { on: false, size: 'medium', spots: {} };
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
const NOT_OBJECTS = [null, undefined, 'junk', '', 7, 0, NaN, true, false, [], [1, 2], ['on']];

test('a fresh install: at home, Medium, no spots; every call gives fresh objects', () => {
  const d = core.defaultDesktopSettings();
  assert.deepEqual(Object.keys(d), ['on', 'size', 'spots']);
  assert.deepEqual(d, DESKTOP_DEFAULTS);
  assert.deepEqual(core.cleanDesktopSettings(null), d);
  d.spots.x = 1; d.size = 'large';
  assert.deepEqual(core.defaultDesktopSettings(), DESKTOP_DEFAULTS, 'changing a result never changes the next one');
  for (const raw of [...NOT_OBJECTS, {}, { on: 7, size: 7, spots: 7 }]) assert.deepEqual(core.cleanDesktopSettings(raw), DESKTOP_DEFAULTS, String(JSON.stringify(raw)));
});

test('a valid value comes back as it went in, from an object, from JSON, and with the Mac\'s text for the spots', () => {
  const valid = { on: true, size: 'large', spots: { [KEY2]: { x: 2000, y: 800 }, [KEY]: { x: 300, y: 400 } } };
  const clean = core.cleanDesktopSettings(valid);
  assert.deepEqual(clean, valid);
  assert.deepEqual(Object.keys(clean.spots), [KEY, KEY2].sort(), 'the spots in code-point order');
  assert.deepEqual(core.cleanDesktopSettings(clean), clean, 'cleaning twice changes nothing');
  assert.deepEqual(core.cleanDesktopSettings(JSON.parse(JSON.stringify(valid))), clean, 'written as JSON and read back');
  assert.deepEqual(core.cleanDesktopSettings({ ...valid, spots: JSON.stringify(valid.spots) }), clean, 'cat.desktop.spots is JSON text on the Mac');
});

test('on is true only for the boolean true, and the size is one of the three IDs', () => {
  assert.equal(core.cleanDesktopSettings({ on: true }).on, true);
  for (const bad of ['true', 'on', 'yes', 1, -1, 0, null, undefined, [], [true], {}, { on: true }, 'TRUE']) assert.equal(core.cleanDesktopSettings({ on: bad }).on, false, String(JSON.stringify(bad)));
  for (const id of core.DESKTOP_SIZE_IDS) assert.equal(core.cleanDesktopSettings({ size: id }).size, id);
  for (const bad of ['Small', 'LARGE', ' large', 'huge', 'xl', '', '48', '96', 48, 96, null, undefined, true, ['large'], {}, '__proto__', 'constructor', 'large\n']) assert.equal(core.cleanDesktopSettings({ size: bad }).size, 'medium', String(JSON.stringify(bad)));
});

test('the spots: text that is not JSON, wrong types and keys that are not screens are dropped, whole or one by one', () => {
  for (const bad of ['{"0,0,100,100":', "{'0,0,100,100':{'x':1,'y':2}}", '{"0,0,100,100":{"x":1,"y":2},}', '{"0,0,100,100":{"x":1,"y":2}} x', 'null', '[]', '7', '"x"', 'junk', '', null, 7, true, [], [{ x: 1, y: 2 }]])
    assert.deepEqual(core.cleanDesktopSettings({ on: true, size: 'small', spots: bad }), { on: true, size: 'small', spots: {} }, String(JSON.stringify(bad)));
  const out = core.cleanDesktopSettings({ spots: { [KEY]: { x: 1, y: 2 }, nonsense: { x: 3, y: 4 }, '0,0,100,100': { x: NaN, y: 4 }, '1,1,100,100': { x: '5', y: 6 }, '2,2,100,100': [7, 8], '3,3,100,100': { x: 1e6, y: 0 } } });
  assert.deepEqual(out.spots, { [KEY]: { x: 1, y: 2 } });
});

test('hostile files never throw, never pollute, and keep at most 32 arrangements', () => {
  const evil = JSON.parse('{"on":true,"__proto__":{"on":false},"size":"large","spots":{"__proto__":{"x":1,"y":2},"constructor":{"x":1,"y":2},"0,0,100,100":{"x":3,"y":4,"__proto__":{"x":9}}}}');
  const out = core.cleanDesktopSettings(evil);
  assert.deepEqual(out, { on: true, size: 'large', spots: { '0,0,100,100': { x: 3, y: 4 } } });
  assert.equal(Object.getPrototypeOf(out.spots), Object.prototype); assert.equal({}.x, undefined); assert.equal({}.on, undefined);
  const many = Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`${i},0,100,100`, { x: i, y: i }]));
  assert.equal(Object.keys(core.cleanDesktopSettings({ spots: many }).spots).length, 32);
  assert.deepEqual(core.cleanDesktopSettings({ spots: JSON.stringify(many) }), core.cleanDesktopSettings({ spots: many }));
  const raw = deepFreeze({ on: true, size: 'small', spots: { [KEY]: { x: 1, y: 2 } } });
  assert.doesNotThrow(() => core.cleanDesktopSettings(raw));
  const a = core.cleanDesktopSettings(raw), b = core.cleanDesktopSettings(raw);
  a.spots[KEY].x = 99; assert.equal(b.spots[KEY].x, 1, 'nothing is shared between results');
});

test('the Cat settings, the Display settings and these are three clean-ups of one stored block: none sees the others\' keys', () => {
  const block = { character: 'momo', collar: 'band', displayMode: 'two', pair: ['momo', 'ginger'], desktop: { on: true, size: 'large', spots: { [KEY]: { x: 1, y: 2 } } } };
  assert.deepEqual(core.cleanCatSettings(block), core.cleanCatSettings({ character: 'momo', collar: 'band' }), 'the Cat settings drop the desktop block');
  assert.deepEqual(core.cleanDisplaySettings(block), core.cleanDisplaySettings({ displayMode: 'two', pair: ['momo', 'ginger'] }), 'and the Display settings');
  assert.deepEqual(core.cleanDesktopSettings(block), DESKTOP_DEFAULTS, 'the desktop clean-up reads the desktop object, not the block');
  assert.deepEqual(core.cleanDesktopSettings(block.desktop), block.desktop);
  assert.deepEqual(Object.keys(core.defaultCatSettings()), ['character', 'motionStyle', 'collar', 'furLines', 'cats']);
  assert.deepEqual(Object.keys(core.defaultDisplaySettings()), ['displayMode', 'pair', 'agentCats']);
});

test('hostile values never throw: 3000 random desktop settings come out valid, and cleaning them again changes nothing', () => {
  const r = core.rng(2028), pool = [true, false, 'true', 'large', 'small', 'Large', '', ' ', 0, 1, -1, 7, null, [], ['large'], {}, KEY, KEY2, '__proto__', 'constructor', { x: 1, y: 2 }, { x: 'a', y: 1 }, `{"${KEY}":{"x":1,"y":2}}`, '{"0,0', 'junk'];
  const pick = () => pool[Math.floor(r() * pool.length)];
  const valid = s => typeof s.on === 'boolean' && core.DESKTOP_SIZE_IDS.includes(s.size) && Object.keys(s.spots).length <= 32
    && Object.entries(s.spots).every(([k, v]) => core.isScreenKey(k) && Number.isFinite(v.x) && Number.isFinite(v.y) && Object.keys(v).join() === 'x,y') && JSON.stringify(Object.keys(s.spots)) === JSON.stringify(Object.keys(s.spots).sort());
  for (let i = 0; i < 3000; i++) {
    const map = r() < .2 ? pick() : Object.fromEntries(Array.from({ length: Math.floor(r() * 5) }, () => [pick(), pick()]).filter(([k]) => typeof k === 'string'));
    const raw = { on: pick(), size: pick(), spots: map }, out = core.cleanDesktopSettings(raw);
    assert.ok(valid(out), JSON.stringify(raw));
    assert.deepEqual(core.cleanDesktopSettings(out), out);
  }
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 52`, `# pass 45`, `# fail 7`.

- [ ] **Step 3: Add the section to the core**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── The desktop cat: the stored settings (sub-project H) ─────────────────────
// What the cat's menu and Settings save: whether it is out, its size, and its spot for each arrangement of screens. A clean-up of its own, like cleanDisplaySettings:
// cleanCatSettings, cleanDisplaySettings and every line of settings-cases.json and display-cases.json stay as they were, and an app cleans the same stored block with
// each function it needs. Raw in, clean out, never a throw.
//   raw or clean:  {on, size, spots: {<screenKey>: {x, y}}}
//   macOS keys:    cat.desktop.on (a Bool), cat.desktop.size (small, medium or large), cat.desktop.spots (the JSON text of the map)
//   Windows and Linux: the `desktop` object of the `cat` block of settings.json, {on, size, spots} with `spots` an object.
/**
 * Everything the desktop cat saves, cleaned: {on, size, spots}. `on` is true only for the boolean true (the number 1 and the text "true" are off), `size` one of the three
 * IDs (anything else is medium), `spots` what cleanDesktopSpots keeps (an object or JSON text of screen keys to spots). Never throws.
 */
function cleanDesktopSettings(raw){const r=isPlain(raw)?raw:{};return{on:r.on===true,size:desktopSizeOf(r.size),spots:cleanDesktopSpots(r.spots)}}
/** What a fresh install holds: the cat at home, Medium, no spots. */
const defaultDesktopSettings=()=>cleanDesktopSettings(null);
Object.assign(api,{cleanDesktopSettings,defaultDesktopSettings});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 16 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 52`, `# pass 52`, `# fail 0`.

- [ ] **Step 5: Prove the strict boolean bites (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "return{on:r.on===true,size:"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "return{on:!!r.on,size:"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "return{on:!!r.on,size:"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "return{on:r.on===true,size:"))
PY
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: first run `not ok 46 - a fresh install: at home, Medium, no spots; every call gives fresh objects` and `not ok 48 - on is true only for the boolean true, and the size is one of the three IDs`, `# pass 50`, `# fail 2`; after putting the line back, `# pass 52` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗"`
Expected: `# tests 283`, `# pass 283`, `# fail 0`.

- [ ] **Step 7: Add the replay test and the fixture keys**

```bash
cat >> tests/cat/desktop.test.mjs <<'EOF'

test('desktop-cases.json: every settings case replays, and the inputs the spec worries about are in it', () => {
  assert.deepEqual(fx.settingsDefaults, DESKTOP_DEFAULTS);
  for (const c of fx.settingsCases) assert.deepEqual(compare(roundTrip(core.cleanDesktopSettings(c.raw)), c.out), [], c.name);
  const names = fx.settingsCases.map(c => c.name);
  for (const n of ['nothing stored', 'a fully valid value', 'on as text', 'on as the number 1', 'a size that is not a size', 'the spots as JSON text, as the Mac stores them', 'the spots as JSON text, cut off', 'prototype names as keys', 'spots that are not spots', 'three hundred arrangements keep the first 32', 'the Cat and Display settings are not desktop settings']) assert.ok(names.includes(n), n);
  const at = n => fx.settingsCases.find(c => c.name === n);
  assert.equal(Object.keys(at('three hundred arrangements keep the first 32').out.spots).length, 32);
  assert.equal(Object.keys(at('three hundred arrangements keep the first 32').raw.spots).length, 300);
  assert.deepEqual(at('three hundred as JSON text').out.spots, at('three hundred arrangements keep the first 32').out.spots, 'the same 32 from the Mac\'s text');
  assert.equal(at('on as text').out.on, false); assert.equal(at('a fully valid value').out.on, true);
  assert.deepEqual(at('prototype names as keys').out.spots, { '0,0,1512,982': { x: 2, y: 2 } });
  assert.ok(fx.settingsCases.filter(c => typeof c.raw === 'object' && c.raw && typeof c.raw.spots === 'string').length >= 6, 'text inputs for the spots');
});
EOF
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '  // @@DESKTOP-SECTIONS: each task adds its keys to `out` immediately above this line.'
assert s.count(marker) == 1
snippet = r'''  out.note += ' settingsCases: cleanDesktopSettings(raw) is out.';
  // The stored settings: cleanDesktopSettings(raw) is out. A raw `spots` may be an object or the JSON text of one (the Mac stores text). The block with 300 spots is built here and written out in full.
  out.settingsDefaults = core.defaultDesktopSettings();
  const MANY = Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`${i},0,100,100`, { x: i, y: i % 90 }]));
  out.settingsCases = [
    ['nothing stored', null], ['an empty object', {}], ['text instead of an object', 'junk'], ['a number', 7], ['an array', [1, 2, 3]], ['true', true],
    ['a fully valid value', { on: true, size: 'large', spots: { [K2]: { x: 2000, y: 800 }, [K1]: { x: 300, y: 400 } } }],
    ['the cat is out', { on: true }], ['the cat is home', { on: false, size: 'small' }], ['on as text', { on: 'true' }], ['on as the number 1', { on: 1 }], ['on as null', { on: null }], ['on in a list', { on: [true] }],
    ['small', { size: 'small' }], ['large', { size: 'large' }], ['a size in the wrong case', { size: 'Large' }], ['a size with a space', { size: 'large ' }], ['a size that is not a size', { size: 'huge' }],
    ['the size as its number', { size: 96 }], ['the size as null', { size: null }], ['a prototype name as the size', { size: '__proto__' }],
    ['the spots as JSON text, as the Mac stores them', { on: true, spots: JSON.stringify({ [K1]: { x: 300, y: 400 } }) }], ['the spots as JSON text, cut off', { spots: '{"0,0,1512,982":{"x":3' }],
    ['the spots as JSON text with single quotes', { spots: "{'0,0,1512,982':{'x':1,'y':2}}" }], ['the spots as JSON text with a trailing comma', { spots: '{"0,0,1512,982":{"x":1,"y":2},}' }],
    ['the spots as JSON text with garbage after it', { spots: '{"0,0,1512,982":{"x":1,"y":2}} x' }], ['the spots as JSON text that is an array', { spots: '[]' }], ['the spots as text that is not JSON', { spots: 'junk' }],
    ['the spots as a number', { spots: 7 }], ['the spots as null', { spots: null }], ['the spots as an array', { spots: [{ x: 1, y: 2 }] }],
    ['a key that is not a screen key', { spots: { nonsense: { x: 1, y: 2 }, '': { x: 1, y: 2 }, [K1]: { x: 5, y: 6 } } }], ['keys with leading zeros, a newline or the wrong order', { spots: { '00,0,100,100': { x: 1, y: 1 }, '0,0,100,100\n': { x: 1, y: 1 }, '1,0,100,100|0,0,100,100': { x: 1, y: 1 } } }],
    ['prototype names as keys', { spots: { constructor: { x: 1, y: 1 }, prototype: { x: 1, y: 1 }, ['__proto__']: { x: 1, y: 1 }, [K1]: { x: 2, y: 2 } } }],
    ['spots that are not spots', { spots: { '0,0,100,100': null, '1,0,100,100': 'x', '2,0,100,100': [1, 2], '3,0,100,100': {}, '4,0,100,100': { x: 1 }, '5,0,100,100': { x: '1', y: 2 }, '6,0,100,100': { x: 1, y: 1e6 }, '7,0,100,100': { x: 1, y: 2 } } }],
    ['a spot with more fields keeps x and y', { spots: { [K1]: { x: 1, y: 2, z: 3, name: 'cat' } } }], ['spots out of order come back in order', { spots: { [K2]: { x: 5, y: 6 }, [K1]: { x: 7, y: 8 } } }],
    ['negative coordinates are fine', { spots: { '-1920,0,1920,1080|0,0,1512,982': { x: -1000, y: 500 } } }],
    ['three hundred arrangements keep the first 32', { on: true, spots: MANY }], ['three hundred as JSON text', { spots: JSON.stringify(MANY) }],
    ['the Cat and Display settings are not desktop settings', { character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, displayMode: 'two', pair: ['momo', 'ginger'], agentCats: { agent_x: 'momo' }, cats: {} }],
  ].map(([name, raw]) => ({ name, raw, out: core.cleanDesktopSettings(raw) }));

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/desktop-cases.json
node --test tests/cat/desktop.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"
```

Expected: the first run `not ok 53 - desktop-cases.json: every settings case replays, and the inputs the spec worries about are in it`, `# tests 53`, `# pass 52`, `# fail 1`; then `wrote 15 fixture files to tests/fixtures/cat`, a `desktop-cases.json` of about 106 KB, and `# tests 53`, `# pass 53`, `# fail 0`.

- [ ] **Step 8: Run the contract and the additive check**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗|✓ [0-9]|✓ two"`
Expected: `# tests 284`, `# pass 284`, `# fail 0`, `✓ 15 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 1627851 | tail -2`
Expected: `  + desktop-cases.json is new` and `✓ fixtures changed only by addition since 1627851`.

- [ ] **Step 9: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js`, ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/desktop.test.mjs`, ` M tests/fixtures/cat/desktop-cases.json`.

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/desktop.test.mjs tests/fixtures/cat/desktop-cases.json
git commit -m "feat(cat): the desktop cat's stored settings have a clean-up of their own

cleanDesktopSettings (on, size, spots) beside cleanCatSettings and cleanDisplaySettings, which stay as they were, pinned by desktop-cases.json.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 5: The prototype: the Desktop panel

**Files:**
- Modify: `design/prototype/notchmeow.html`
- One-off, not committed: `${TMPDIR:-/tmp}/h0-shots/` (the config, the port, the server's PID and log)

**Interfaces:**
- Consumes from `CatCore`: `desktopStep`, `DESKTOP_PHASE_INFO`, `desktopFlightAt`, `DESKTOP_FLIGHT_MS`, `desktopFps`, `DESKTOP_SIZES`, `DESKTOP_SIZE_IDS`, `DEFAULT_DESKTOP_SIZE`, `desktopKittenSlots`, `screenKey`, `spotFor`, `rememberSpot`, `cleanDesktopSettings`, `defaultDesktopSettings`, `kittenPlaceOf`, `miniSlots`, `layout`, `cursorLook`, `BUSY`, `rng`; the page's own `drawCat`, `CatEngine`, `castNow`, `kitView`, `KIT`, `poolEng`, `kitPreset`, `drawKittens`, `drawSessionMinis`, `drawMenubar`, `islandPath`, `pill`, `bigCollar`, `collarOf`, `group`, `fit`, `rr`, `COMPACT`, `EXP`, `TASK`, `COL`.
- Produces in the page: the Desktop panel (`#dkPanel`): `DK` (its state), `dkSend` (one event into the machine, doing what `act` says), `dkScene`, `dkCatDraw`, `dkKittens`, `drawDesktop`, `drawStrip`, `drawSizes`, the pointer handlers and the right-click menu. The frame loop gains one call, `drawDesktop(dt)`.

What changes in the page, and what does not:
- **A new panel, "Desktop,"** after "In the notch": a trip row (Cat on the desktop, which becomes Bring the cat home while the cat is out; Send home; Approval arrives; Answered; Screens changed, which moves the mock's Dock between the bottom and the left; Restart the app, which sends `launch` when the stored `on` is true), a size picker, a state row for the desktop cat, five toggles (Mark the empty spot, Hit area, Clamp area, Hidden, Music playing), the mock screen, a readout (the phase, the last event and what it did, the frame rate asked for and the frames really drawn in the last second, the spot, the screen key, the settings it would store), the alert flight as a strip of frames and the three sizes.
- **The mock screen** is 960 by 540 points with a menu bar of 32, a Dock of 64 (or 70 on the left), two windows and the notch island in the middle of the top. Press the cat in the notch and drag it out onto the desktop: `dragOut`. Drag the cat on the desktop: `move` (the spot is clamped by `rememberSpot`, so it never goes under the menu bar or the Dock). Drop it on the island: `sendHome`. Click: the happy emote and the island opens for 2.4 s, after one double-click interval of 300 ms. Double-click: `sendHome`. Right-click: Open the notch, Send home, Size ▸ Small, Medium, Large, and the ⌃⌥D line. Only the cat's body takes the mouse (the head circle, the badge and the kitten slots).
- **Two canvases:** the base (the screen and the notch) is drawn every frame, as the notch always is; the cat's own canvas is the desktop window and is drawn only at the rate `desktopFps` asks for (0 draws nothing and clears it).
- **No existing panel changes.** The only existing line that changes is the frame loop's, which gains the call. The new CSS is new classes (`.dkdesk`, `.dkmenu` and `#dkReadout`).

- [ ] **Step 1: Apply the patch**

```bash
python3 - <<'PY'
# Task 5: the prototype's Desktop panel. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
p = 'design/prototype/notchmeow.html'
s = open(p, encoding='utf-8').read()

def rep(was, now):
    global s
    assert s.count(was) == 1, was[:70]
    s = s.replace(was, now)

# ── 1. Style: the new panel's own classes (nothing existing changes) ────────────────────────────────────────────
rep('''@media (max-width:680px){.cmp{grid-template-columns:1fr}}
</style>''', '''@media (max-width:680px){.cmp{grid-template-columns:1fr}}
.dkdesk{position:relative;max-width:960px;aspect-ratio:960/540;border-radius:12px;overflow:hidden;background:#12151c;touch-action:none}
.dkdesk canvas{position:absolute;left:0;top:0;width:100%;height:100%;display:block}
.dkdesk canvas.top{pointer-events:none}
.dkmenu{position:absolute;z-index:3;min-width:190px;background:#202227;border:1px solid var(--line);border-radius:10px;padding:4px;box-shadow:0 8px 24px rgba(0,0,0,.5)}
.dkmenu button{display:block;width:100%;text-align:left;border:0;background:none;padding:6px 10px}
.dkmenu button:hover{background:#2b2d33}
.dkmenu .sc{color:var(--dim);float:right;margin-left:14px}
.dkmenu .gap{height:1px;background:var(--line);margin:4px 2px}
#dkReadout,#dkStored{white-space:pre-line;font-variant-numeric:tabular-nums}
</style>''')

# ── 2. The panel, after "In the notch" ───────────────────────────────────────────────────────────────────────────
rep('''<section class="panel">
<h2>Greeting</h2>''', '''<section class="panel" id="dkPanel">
<h2>Desktop</h2>
<p class="tag">The big cat out of the notch, living on the desktop. Drag it out of the notch and drop it on the desktop, or use Cat on the desktop. It flies into the notch for an approval or a question and out again once that is answered; its spot in the notch stays empty while it is out. Click opens the island, double-click sends it home, drag moves it, right-click opens its menu. The mock screen is 960 by 540 points, with a menu bar of 32 and a Dock of 64. Every rule is CatCore's: desktopStep, desktopFlightAt, desktopFps, clampSpot, spotFor, rememberSpot and desktopKittenSlots, pinned by desktop-cases.json.</p>
<div class="row" id="dkTripRow"><span class="h">Trip</span></div>
<div class="row" id="dkSizeRow"><span class="h">Size</span></div>
<div class="row" id="dkStateRow"><span class="h">State</span></div>
<div class="row" id="dkViewRow"><span class="h">Show</span></div>
<div class="dkdesk" id="dkDesk" style="margin-top:12px"><canvas id="cvDkBase" aria-label="Mock desktop with the notch"></canvas><canvas class="top" id="cvDkCat" aria-label="The desktop cat"></canvas></div>
<p class="note" id="dkReadout"></p>
<p class="note" id="dkStored"></p>
<p class="tag" style="margin-top:14px"><b>The alert flight.</b> The top row: an approval arrives, the cat gives the surprised emote and flies into its notch spot while the island opens (0.6 s). The bottom row: it is answered and the cat flies back out to its spot. The dotted line is desktopFlightAt's arc. Frames at the cat's size picked above.</p>
<div class="scroll"><canvas id="dkStrip" aria-label="The alert flight, frame by frame"></canvas></div>
<p class="tag" style="margin-top:14px"><b>The three sizes.</b> Small, Medium and Large with the state badge (upper right) and the agent's kittens (up to three, then +N) from desktopKittenSlots, in units of the head width. Top: kittens on the right. Bottom: kittens on the left, which is where a cat in the right half of its screen keeps them, with the body outlined: the head circle, the badge and the kitten slots, the only places that take the mouse.</p>
<div class="scroll"><canvas id="dkSizes" aria-label="The three sizes with badge and kittens"></canvas></div>
</section>

<section class="panel">
<h2>Greeting</h2>''')

# ── 3. The script ───────────────────────────────────────────────────────────────────────────────────────────────
rep('// ── Frame loop ───', r'''// ── Desktop: the big cat out of the notch (sub-project H) ─────────────────────────────────────────────────────────
// A mock screen of 960 x 540 points. Nothing here decides anything: CatCore.desktopStep says what each event does, desktopFlightAt where the cat is in a flight, desktopFps how often to
// draw it, clampSpot, spotFor and rememberSpot where it may sit, and desktopKittenSlots where its kittens stand. Two canvases: the base is the screen with the notch and is drawn every frame (the
// notch is its own window); the cat is the desktop window and is drawn only at the frame rate desktopFps asks for.
const DKW=960,DKH=540,DKC=DKW/2,DKMENU=32,DKFLY=CatCore.DESKTOP_FLIGHT_MS;
const dkBase=document.getElementById('cvDkBase'),dkCatCv=document.getElementById('cvDkCat'),dkBox=document.getElementById('dkDesk'),dkOut=document.getElementById('dkReadout'),dkSaved=document.getElementById('dkStored');
const DK={ph:'home',size:CatCore.DEFAULT_DESKTOP_SIZE,settings:CatCore.defaultDesktopSettings(),dock:'bottom',alert:false,state:'working',spot:null,fl:null,drag:null,isl:{from:0,to:0,t0:0},peek:0,emote:0,hidden:false,music:false,
 mark:true,hit:false,clamp:false,last:'nothing yet',acc:0,stamps:[],tDraw:0,cleared:false,clickT:0,fps:0,why:''};
let dkEng=new CatEngine(PRESETS[CHAR],{state:DK.state});
/** The mock screen in the contract's terms: points, y down, the origin at the top left of the main screen. The Dock is at the bottom (64) or on the left (70). */
const dkScreens=()=>[{frame:{x:0,y:0,w:DKW,h:DKH},visible:DK.dock==='left'?{x:70,y:DKMENU,w:DKW-70,h:DKH-DKMENU}:{x:0,y:DKMENU,w:DKW,h:DKH-DKMENU-64},main:true}];
const dkPh=()=>CatCore.DESKTOP_PHASE_INFO[DK.ph],dkD=()=>CatCore.DESKTOP_SIZES[DK.size],dkSpot=()=>DK.spot||(DK.spot=CatCore.spotFor(DK.settings.spots,dkScreens(),DK.size));
/** The island opens for an alert, and for 2.4 s after a click on the cat; its big-cat spot moves with it (the notch mock's numbers). */
const dkIsl=()=>{const a=DK.isl;return lerp(a.from,a.to,EZ.out(seg(ms(),a.t0,a.t0+400)))};
const dkIslTo=to=>{if(DK.isl.to!==to)DK.isl={from:dkIsl(),to,t0:ms()}};
const dkNotch=e=>({x:DKC-lerp(COMPACT,EXP.W,e)/2+lerp(40,74,e),y:lerp(16,98,e)});
const dkProg=()=>DK.fl?clamp((ms()-DK.fl.t0)/DKFLY,0,1):0;
const dkFly=(from,to,delay=0)=>{DK.fl={from,to,t0:ms()+delay}};
/** Where the cat is on the desktop layer: under the pointer while dragged, along the flight, or at its spot. */
function dkPos(){if(DK.drag&&DK.drag.moved)return DK.drag.at;if(DK.fl&&dkPh().flight){const q=CatCore.desktopFlightAt(DK.fl.from,DK.fl.to,dkProg());return{x:q.x,y:q.y}}return DK.ph==='onDesktop'?dkSpot():null}
/** Kittens go to the left of the cat when it is in the right half of its screen, so they stay on the screen. */
const dkSide=p=>p.x>DKW/2?-1:1;
/** One event into the machine; the act it answers with is what the page does. `at` is where the cat is on screen when that is not its saved spot (a cat dropped on the notch flies home from the drop). */
function dkSend(ev,at){const prev=DK.ph,t=dkProg(),r=CatCore.desktopStep(prev,ev);DK.ph=r.state;DK.last=`${ev.type}: ${prev} → ${r.state}${r.act?` (${r.act})`:' (nothing)'}`;
 const notch=()=>dkNotch(DK.alert?1:0);
 switch(r.act){
  case 'place':case 'move':DK.settings.spots=CatCore.rememberSpot(DK.settings.spots,dkScreens(),ev.spot,DK.size);DK.spot=null;dkSpot();break;
  case 'resettle':DK.spot=null;if(DK.fl&&dkPh().flight)DK.fl.to=dkSpot();else dkSpot();break;
  case 'flyOut':dkFly(notch(),dkSpot());break;
  case 'flyHome':dkFly(at||dkSpot(),notch());break;
  case 'retract':dkEng.emote('surprised');DK.emote=ms()+1800;dkFly(dkSpot(),notch(),350);break;
  case 'turn':{const f=DK.fl;DK.fl={from:f.to,to:dkPh().dir==='in'?notch():f.from,t0:ms()-(1-t)*DKFLY};break}
  case 'land':case 'dock':case 'goHome':DK.fl=null;break}
 DK.settings=CatCore.cleanDesktopSettings({...DK.settings,on:dkPh().on,size:DK.size});dkIslTo(DK.alert||ms()<DK.peek?1:0)}
function dkTick(){if(DK.fl&&dkPh().flight&&dkProg()>=1)dkSend({type:'flightDone'});if(!DK.alert&&DK.peek&&ms()>DK.peek){DK.peek=0;dkIslTo(0)}}
const dkOpen=()=>{dkEng.emote('happy');DK.emote=ms()+1800;DK.peek=ms()+2400;dkIslTo(1)};
function dkSetSize(id){DK.size=id;DK.settings=CatCore.cleanDesktopSettings({...DK.settings,size:id});DK.spot=null;drawStrip();syncSize()}
function dkRestart(){DK.ph='home';DK.fl=null;DK.alert=false;DK.spot=null;DK.peek=0;DK.drag=null;DK.isl={from:0,to:0,t0:0};DK.last='the app restarted';if(CatCore.cleanDesktopSettings(DK.settings).on)dkSend({type:'launch'})}
const dkSync=()=>{const C=castNow(),st=DK.alert?'approval':DK.state;if(dkEng.p.name!==C.big.cat)dkEng=new CatEngine(PRESETS[C.big.cat],{state:st});if(dkEng.state!==st)dkEng.setState(st);return C};

/** One mock screen into ctx (already scaled to points): the wallpaper, two windows, the Dock, the menu bar, the island and the cat's spot in it. o: {e: how open the island is, eng, inNotch: the cat is in its notch spot, mark, C: the cast}. */
function dkScene(ctx,o){const e=o.e,W=DKW,H=DKH,left=DK.dock==='left';
 const g=ctx.createLinearGradient(0,0,W*.4,H);g.addColorStop(0,'#34405a');g.addColorStop(.55,'#1d2330');g.addColorStop(1,'#12151c');ctx.fillStyle=g;ctx.fillRect(0,0,W,H);
 for(const [x,y,w,h,t] of [[120,130,420,250,'Terminal'],[430,210,390,240,'Editor']]){ctx.fillStyle='rgba(26,29,38,.94)';rr(ctx,x,y,w,h,10);ctx.fill();ctx.strokeStyle='rgba(255,255,255,.1)';ctx.lineWidth=1;ctx.stroke();
  ctx.fillStyle='rgba(255,255,255,.07)';rr(ctx,x,y,w,26,10);ctx.fill();ctx.fillStyle='rgba(255,255,255,.5)';ctx.font='600 11px system-ui,sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText(t,x+w/2,y+13);
  ctx.fillStyle='rgba(255,255,255,.14)';for(let i=0;i<5;i++)rr(ctx,x+16,y+44+i*24,w*(.3+.11*((i*3)%5)),8,4),ctx.fill()}
 const dcol=['#E07950','#8AB4F8','#2DD4BF','#E879F9','#F7B32B','#9a9ca3','#5EEAD4'];ctx.fillStyle='rgba(255,255,255,.12)';
 if(left){rr(ctx,8,DKMENU+60,54,7*48+8,14);ctx.fill();dcol.forEach((c,i)=>{ctx.fillStyle=c;rr(ctx,15,DKMENU+66+i*48,40,40,9);ctx.fill()})}
 else{rr(ctx,DKC-190,H-58,380,50,14);ctx.fill();dcol.forEach((c,i)=>{ctx.fillStyle=c;rr(ctx,DKC-176+i*50,H-52,38,38,9);ctx.fill()})}
 drawMenubar(ctx,W,1);
 const iw=lerp(COMPACT,EXP.W,e),ih=lerp(32,EXP.H,e),x0=DKC-iw/2,sp=dkNotch(e);
 ctx.fillStyle='#000';islandPath(ctx,DKC,iw,ih,1);ctx.fill();ctx.save();islandPath(ctx,DKC,iw,ih,1);ctx.clip();
 if(e<.95)drawSessionMinis(ctx,DKC,1,CatCore.miniSlots(1,{grid:1,four:1},{W:iw,H:32}),1-seg(e,0,.25));
 if(e>.5){const a=seg(e,.55,1),T=TASK[o.C.big.pill||'integration_claude'];ctx.globalAlpha=a;ctx.textAlign='left';ctx.textBaseline='middle';ctx.fillStyle='#fff';ctx.font='600 13px system-ui,sans-serif';ctx.fillText(T.name,x0+176,24);
  ctx.fillStyle='#8d9098';ctx.font='11px system-ui,sans-serif';ctx.fillText(DK.alert||o.alertText?'wants to run npm test':'notchmeow · editing engine.ts',x0+176,40);
  if(DK.alert||o.alertText)pill(ctx,x0+iw-16,24,'needs approval',COL.approval,1);ctx.globalAlpha=1}
 if(o.inNotch){drawCat(ctx,o.eng,sp.x,sp.y,lerp(20,64,clamp(e,0,1.1)),{tint:TINTON,badgeSide:e<.5?-1:1,collar:bigCollar(o.eng),earCeiling:0,glow:e>.5});
  if(o.C.big.pill)drawKittens(ctx,CatCore.kittenPlaceOf('one',e>.5),o.C.big.pill,o.C.big.cat,TASK[o.C.big.pill].col,sp.x,sp.y,lerp(20,64,clamp(e,0,1.1)),1)}
 else if(o.mark){ctx.setLineDash([3,4]);ctx.strokeStyle='rgba(255,255,255,.38)';ctx.lineWidth=1;ctx.beginPath();ctx.arc(sp.x,sp.y,lerp(10,31,e),0,TAU);ctx.stroke();ctx.setLineDash([])}
 ctx.restore()}
/** The desktop cat's kittens: CatCore.desktopKittenSlots gives the slots in units of the cat's head width D from its centre. Returns the slots. */
function dkKittens(ctx,pill,cat,col,ox,oy,D,side,dt){const sl=CatCore.desktopKittenSlots(kitView(pill),side);
 for(const q of sl.shown){const e=poolEng(`kit:${pill}:${q.id}:${cat}`,kitPreset(cat),q.state==='leaving'?'finished':q.state);if(dt)e.update(dt);drawCat(ctx,e,ox+q.x*D,oy+q.y*D,q.d*D,{tint:TINTON,collar:collarOf(col)})}
 if(sl.moreAt){const m=sl.moreAt,sz=Math.max(9,m.size*D),text='+'+sl.more;ctx.font=`700 ${sz}px system-ui,sans-serif`;const w=ctx.measureText(text).width+sz*.6,x=ox+m.x*D,y=oy+m.y*D;
  ctx.fillStyle='#2a2c31';rr(ctx,x-w/2,y-sz*.65,w,sz*1.3,sz*.65);ctx.fill();ctx.fillStyle='#cfd0d4';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText(text,x,y+.5)}
 return sl}
/** The cat and what travels with it: the cat itself, then (when it sits on the desktop) its badge, drawn by drawCat, and its kittens. */
function dkCatDraw(ctx,eng,pos,D,C,withKittens,side,dt){drawCat(ctx,eng,pos.x,pos.y,D,{tint:TINTON,fur:FUR&&D>=60,badgeSide:1,collar:bigCollar(eng)});
 if(withKittens&&C.big.pill)dkKittens(ctx,C.big.pill,C.big.cat,TASK[C.big.pill].col,pos.x,pos.y,D,side,dt)}
const dkCircles=(pos,D,C,side,eng)=>{const L=CatCore.layout(eng.p,eng.s,pos.x,pos.y,D,{badgeSide:1}),sl=CatCore.desktopKittenSlots(C.big.pill?kitView(C.big.pill):[],side);
 return[{x:pos.x,y:pos.y,r:D*.55},{x:L.badge.x,y:L.badge.y,r:.3*L.R+3},...sl.shown.map(q=>({x:pos.x+q.x*D,y:pos.y+q.y*D,r:q.d*D/2+2})),...(sl.moreAt?[{x:pos.x+sl.moreAt.x*D,y:pos.y+sl.moreAt.y*D,r:sl.moreAt.size*D*.9}]:[])]};
function dkLook(e,rect,k){if(!e._at)return;if(mx===null){e.lookX*=.9;e.lookY*=.9;return}const g=CatCore.cursorLook((mx-rect.left)/k-e._at.x,(my-rect.top)/k-e._at.y);e.lookX=g.x;e.lookY=g.y}

/** What desktopFps is told, and the words for its answer. */
function dkFpsInput(rect,k,C){const st=dkEng.state,p=dkPos(),list=C.big.pill?(KIT[C.big.pill]||[]):[];
 return{phase:DK.ph,hidden:DK.hidden,dragging:!!(DK.drag&&DK.drag.moved),emote:ms()<DK.emote,kittenMotion:DK.ph==='onDesktop'&&list.some(q=>q.state==='leaving'||ms()-q.born<500),dance:DK.music,asleep:st==='sleeping',working:CatCore.BUSY.has(st),
  cursorDist:mx===null||!p?undefined:Math.hypot((mx-rect.left)/k-p.x,(my-rect.top)/k-p.y)}}
const dkWhy=(i,f)=>f===0?(i.hidden?'hidden: a fullscreen app, a locked or sleeping screen':'the cat is in the notch'):f===60?(CatCore.DESKTOP_PHASE_INFO[i.phase].flight?'flying':i.dragging?'being dragged':i.emote?'an emote':i.kittenMotion?'a kitten arriving or leaving':'music'):f===.5?'asleep: a still frame every 2 s':f===20?(i.working?'an agent is working':'the cursor is within 150 points'):'idle and awake';
let dkReadAt=0;
function drawDesktop(dt){const C=dkSync();dkTick();
 const [bctx,W]=fit(dkBase),k=W/DKW,rect=dkBox.getBoundingClientRect(),e=dkIsl(),dragNotch=DK.drag&&DK.drag.src==='notch'&&DK.drag.moved;
 bctx.save();bctx.scale(k,k);dkScene(bctx,{e,eng:dkEng,C,inNotch:!dkPh().notchEmpty&&!dragNotch,mark:DK.mark,alertText:DK.alert});
 if(DK.clamp){const v=dkScreens()[0].visible,m=24+dkD()/2;bctx.setLineDash([5,5]);bctx.strokeStyle='rgba(94,234,212,.7)';bctx.strokeRect(v.x+m,v.y+m,v.w-2*m,v.h-2*m);bctx.setLineDash([]);bctx.fillStyle='rgba(94,234,212,.8)';bctx.font='11px system-ui,sans-serif';bctx.textAlign='left';bctx.fillText('where the cat\'s centre may be: clampSpot',v.x+m+6,v.y+m+14)}
 bctx.restore();
 const inp=dkFpsInput(rect,k,C),fps=CatCore.desktopFps(inp);DK.fps=fps;DK.why=dkWhy(inp,fps);DK.acc+=dt;const now=ms();
 if(fps===0){if(!DK.cleared){fit(dkCatCv);DK.cleared=true}}
 else if(now-DK.tDraw>=1000/fps-3){DK.cleared=false;DK.tDraw=now;DK.stamps.push(now);const step=DK.acc;dkEng.update(step);DK.acc=0;
  const [cctx]=fit(dkCatCv),pos=dkPos(),D=dkD();cctx.save();cctx.scale(k,k);
  if(pos){dkLook(dkEng,rect,k);dkCatDraw(cctx,dkEng,pos,D,C,DK.ph==='onDesktop',dkSide(pos),step);
   if(DK.hit){cctx.setLineDash([3,3]);cctx.strokeStyle='rgba(94,234,212,.9)';cctx.lineWidth=1;for(const c of dkCircles(pos,D,C,dkSide(pos),dkEng)){cctx.beginPath();cctx.arc(c.x,c.y,c.r,0,TAU);cctx.stroke()}cctx.setLineDash([])}}
  cctx.restore()}
 while(DK.stamps.length&&DK.stamps[0]<now-1000)DK.stamps.shift();
 if(now-dkReadAt>200){dkReadAt=now;const sc=dkScreens(),sp=DK.spot;
  dkOut.textContent=`Phase: ${DK.ph} · last event: ${DK.last}\nFrame rate asked for: ${fps} fps (${DK.why}) · drawn in the last second: ${DK.stamps.length}\nSpot: ${sp?`${Math.round(sp.x)}, ${Math.round(sp.y)}`:'none yet'} · size ${DK.size} (Ø${dkD()}) · screens ${CatCore.screenKey(sc)}`;
  dkSaved.textContent=`Settings it would store (Mac: cat.desktop.on, .size, .spots; Windows and Linux: the desktop object of the cat block): ${JSON.stringify(DK.settings)}`}}

// Pointer: press the cat (in the notch or on the desktop) to pick it up; release on empty desktop to drop it; release on the island to send it home. Only the cat's body takes the mouse.
const dkPt=ev=>{const r=dkBox.getBoundingClientRect(),k=r.width/DKW;return{x:(ev.clientX-r.left)/k,y:(ev.clientY-r.top)/k}};
function dkHitTest(p){const D=dkD();
 if(DK.ph==='onDesktop'&&!DK.fl&&!DK.drag){const c=dkSpot();if(dkCircles(c,D,castNow(),dkSide(c),dkEng).some(q=>Math.hypot(p.x-q.x,p.y-q.y)<=q.r))return 'cat'}
 if(DK.ph==='home'||DK.ph==='atNotchForAlert'){const e=dkIsl(),n=dkNotch(e);if(Math.hypot(p.x-n.x,p.y-n.y)<=Math.max(12,lerp(20,64,e)*.6))return 'notch'}
 return null}
const dkOnIsland=p=>{const e=dkIsl(),iw=lerp(COMPACT,EXP.W,e),ih=lerp(32,EXP.H,e);return Math.abs(p.x-DKC)<=iw/2&&p.y<=ih};
function dkClick(){if(DK.clickT){clearTimeout(DK.clickT);DK.clickT=0;dkSend({type:'sendHome'});return}DK.clickT=setTimeout(()=>{DK.clickT=0;dkOpen()},300)}
const dkMenu=document.createElement('div');dkMenu.className='dkmenu';dkMenu.hidden=true;dkBox.appendChild(dkMenu);
dkBox.addEventListener('pointerdown',ev=>{if(ev.button!==0)return;dkMenu.hidden=true;const p=dkPt(ev),h=dkHitTest(p);if(!h)return;try{dkBox.setPointerCapture(ev.pointerId)}catch{}DK.drag={src:h,start:p,at:p,moved:false}});
dkBox.addEventListener('pointermove',ev=>{const p=dkPt(ev);if(DK.drag){DK.drag.at=p;if(!DK.drag.moved&&Math.hypot(p.x-DK.drag.start.x,p.y-DK.drag.start.y)>6)DK.drag.moved=true}else dkBox.style.cursor=dkHitTest(p)?'grab':'default'});
dkBox.addEventListener('pointerup',ev=>{const d=DK.drag;if(!d)return;DK.drag=null;const p=dkPt(ev);
 if(d.moved){if(dkOnIsland(p)){if(d.src==='cat')dkSend({type:'sendHome'},p)}else dkSend(d.src==='notch'?{type:'dragOut',spot:p}:{type:'move',spot:p})}
 else if(d.src==='cat')dkClick();else dkEng.slap()});
dkBox.addEventListener('contextmenu',ev=>{const p=dkPt(ev);if(dkHitTest(p)!=='cat')return;ev.preventDefault();dkMenu.innerHTML='';
 const add=(t,fn,sc)=>{const b=document.createElement('button');b.innerHTML=t+(sc?`<span class="sc">${sc}</span>`:'');b.onclick=()=>{dkMenu.hidden=true;fn()};dkMenu.appendChild(b)};
 add('Open the notch',dkOpen);add('Send home',()=>dkSend({type:'sendHome'}));dkMenu.insertAdjacentHTML('beforeend','<div class="gap"></div>');
 dkMenu.insertAdjacentHTML('beforeend','<div style="padding:4px 10px 2px;color:var(--dim);font-size:11px">Size ▸</div>');
 for(const id of CatCore.DESKTOP_SIZE_IDS)add(`${id[0].toUpperCase()+id.slice(1)}${id===DK.size?' ✓':''}`,()=>dkSetSize(id),`Ø${CatCore.DESKTOP_SIZES[id]}`);
 dkMenu.insertAdjacentHTML('beforeend','<div class="gap"></div>');add('Cat on the desktop',()=>dkSend({type:'toggle'}),'⌃⌥D');
 const r=dkBox.getBoundingClientRect();dkMenu.style.left=Math.min(ev.clientX-r.left,r.width-200)+'px';dkMenu.style.top=Math.min(ev.clientY-r.top,r.height-230)+'px';dkMenu.hidden=false});
addEventListener('pointerdown',ev=>{if(!dkMenu.contains(ev.target))dkMenu.hidden=true},true);

// Controls.
const dkRow=id=>document.getElementById(id),dkBtn=(row,label,fn)=>{const b=document.createElement('button');b.textContent=label;b.onclick=fn;dkRow(row).appendChild(b);return b};
const dkToggle=dkBtn('dkTripRow','Cat on the desktop',()=>dkSend({type:'toggle'}));
dkBtn('dkTripRow','Send home',()=>dkSend({type:'sendHome'}));
dkBtn('dkTripRow','Approval arrives',()=>{DK.alert=true;dkSend({type:'alertOn'})});
dkBtn('dkTripRow','Answered',()=>{DK.alert=false;dkSend({type:'alertOff'})});
dkBtn('dkTripRow','Screens changed',()=>{DK.dock=DK.dock==='left'?'bottom':'left';dkSend({type:'screensChanged'})});
dkBtn('dkTripRow','Restart the app',dkRestart);
const syncSize=group('dkSizeRow',CatCore.DESKTOP_SIZE_IDS.map(id=>[id,`${id[0].toUpperCase()+id.slice(1)} Ø${CatCore.DESKTOP_SIZES[id]}`]),()=>DK.size,v=>dkSetSize(v));
group('dkStateRow',['idle','working','thinking','searching','finished','sleeping','error'].map(s=>[s,s]),()=>DK.state,v=>{DK.state=v});
for(const [label,key] of [['Mark the empty spot','mark'],['Hit area','hit'],['Clamp area','clamp'],['Hidden (fullscreen app, locked screen)','hidden'],['Music playing','music']]){const b=dkBtn('dkViewRow',label,()=>{DK[key]=!DK[key];b.classList.toggle('on',DK[key])});b.classList.toggle('on',DK[key])}
setInterval(()=>{dkToggle.textContent=dkPh().on?'Bring the cat home':'Cat on the desktop'},100);

// The alert flight as a strip of frames: two rows of five, each a small mock screen (half size) around the notch and the cat's spot.
const dkStrip=document.getElementById('dkStrip');
function drawStrip(){const CW=216,CH=150,GAP=8,CAP=20,LAB=16,RH=CAP+CH+LAB+8,W=5*CW+4*GAP,H=2*RH,s=.5,X0=190,D=dkD(),C=castNow();
 dkStrip.style.width=W+'px';dkStrip.style.height=H+'px';const [ctx]=fit(dkStrip,W,H);ctx.fillStyle='#000';ctx.fillRect(0,0,W,H);
 const spot=CatCore.spotFor({},dkScreens(),DK.size),notch=dkNotch(1);
 const rows=[{title:'An approval arrives: the surprised emote, then it flies into its notch spot',from:spot,to:notch,state:'approval',frames:[[0,0,'surprised'],[.25,.35],[.5,.7],[.75,1],[1,1]],alert:true},
  {title:'It is answered: the cat flies back out to its spot',from:notch,to:spot,state:'working',frames:[[0,1],[.25,.65],[.5,.3],[.75,0],[1,0]],alert:false}];
 rows.forEach((row,ri)=>{const y0=ri*RH;ctx.fillStyle='#ececee';ctx.font='600 12px system-ui,sans-serif';ctx.textAlign='left';ctx.textBaseline='middle';ctx.fillText(row.title,2,y0+CAP/2);
  row.frames.forEach(([prog,open,emote],ci)=>{const x0=ci*(CW+GAP),y=y0+CAP;let t=0;const eng=new CatEngine(PRESETS[C.big.cat],{now:()=>t,rand:CatCore.rng(5),quiet:true,state:row.state});
   if(emote)eng.emote(emote);for(let i=0;i<(emote?12:90);i++){t+=1000/60;eng.update(1/60)}
   const inNotch=(ri===0&&prog===1)||(ri===1&&prog===0),pos=CatCore.desktopFlightAt(row.from,row.to,prog);
   ctx.save();ctx.beginPath();ctx.rect(x0,y,CW,CH);ctx.clip();ctx.translate(x0,y);ctx.scale(s,s);ctx.translate(-X0,0);
   dkScene(ctx,{e:open,eng,C,inNotch,mark:false,alertText:row.alert&&prog>0});
   ctx.setLineDash([2,6]);ctx.strokeStyle='rgba(255,255,255,.45)';ctx.lineWidth=2;ctx.beginPath();for(let i=0;i<=40;i++){const q=CatCore.desktopFlightAt(row.from,row.to,i/40);i?ctx.lineTo(q.x,q.y):ctx.moveTo(q.x,q.y)}ctx.stroke();ctx.setLineDash([]);
   if(!inNotch)drawCat(ctx,eng,pos.x,pos.y,D,{tint:TINTON,badgeSide:1});
   ctx.restore();ctx.fillStyle='#9a9ca3';ctx.font='11px system-ui,sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';
   ctx.fillText(emote?'the alert arrives':prog===0||prog===1?(inNotch?'in the notch':'at its spot'):`${(prog*DKFLY/1000).toFixed(2)} s`,x0+CW/2,y+CH+LAB/2+2)})})}
drawStrip();addEventListener('resize',drawStrip);

// The three sizes side by side, the cat in its working state with its badge and its agent's kittens; below, mirrored to the left, with the body outlined.
const dkSizes=document.getElementById('dkSizes'),SIZE_ENG=new Map();
function sizeEng(cat,state){const key=cat+':'+state;let e=SIZE_ENG.get(key);if(!e){let t=0;e=new CatEngine(PRESETS[cat],{now:()=>t,rand:CatCore.rng(9),quiet:true,state});for(let i=0;i<90;i++){t+=1000/60;e.update(1/60)}SIZE_ENG.set(key,e)}return e}
function drawSizes(){const C=castNow(),ids=CatCore.DESKTOP_SIZE_IDS,cw=ids.map(id=>Math.round(CatCore.DESKTOP_SIZES[id]*2.4+44)),ROW=176,LEFTW=64,W=LEFTW+cw.reduce((a,b)=>a+b,0)+8,H=2*ROW+22;
 dkSizes.style.width=W+'px';dkSizes.style.height=H+'px';const [ctx]=fit(dkSizes,W,H);ctx.fillStyle='#000';ctx.fillRect(0,0,W,H);
 const eng=sizeEng(C.big.cat,'working');let x=LEFTW;
 ids.forEach((id,i)=>{const D=CatCore.DESKTOP_SIZES[id];ctx.fillStyle='#ececee';ctx.font='600 12px system-ui,sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText(`${id[0].toUpperCase()+id.slice(1)} Ø${D}`,x+cw[i]/2,12);
  ctx.strokeStyle='#2a2c31';ctx.beginPath();ctx.moveTo(x+.5,6);ctx.lineTo(x+.5,H-6);ctx.stroke();
  [1,-1].forEach((side,ri)=>{const cy=22+ri*ROW+ROW/2,pos={x:side===1?x+22+D*.55:x+cw[i]-22-D*.55,y:cy};
   dkCatDraw(ctx,eng,pos,D,C,true,side,.25);
   if(ri){ctx.setLineDash([3,3]);ctx.strokeStyle='rgba(94,234,212,.9)';ctx.lineWidth=1;for(const c of dkCircles(pos,D,C,side,eng)){ctx.beginPath();ctx.arc(c.x,c.y,c.r,0,TAU);ctx.stroke()}ctx.setLineDash([])}});
  x+=cw[i]});
 ctx.fillStyle='#9a9ca3';ctx.font='11px system-ui,sans-serif';ctx.textAlign='left';ctx.textBaseline='middle';ctx.fillText('right',8,22+ROW/2);ctx.fillText('left, body',8,22+ROW*1.5)}
drawSizes();setInterval(drawSizes,500);addEventListener('resize',drawSizes);

// ── Frame loop ───''')

# ── 4. The frame loop draws the Desktop panel ─────────────────────────────────────────────────────────────────────
rep(''' drawDesk();drawLadder();requestAnimationFrame(frame)}''', ''' drawDesk();drawLadder();drawDesktop(dt);requestAnimationFrame(frame)}''')
open(p, 'w', encoding='utf-8').write(s)
PY
git diff --stat design/prototype/notchmeow.html

```

Expected: `1 file changed, 192 insertions(+), 1 deletion(-)`.

- [ ] **Step 2: Serve the page and load it in a headless browser**

`playwright-cli` drives the browsers that are already cached (nothing is downloaded). The server listens on `127.0.0.1` only.

```bash
SHOTS="${TMPDIR:-/tmp}/h0-shots"; mkdir -p "$SHOTS"
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
echo "$PORT" > "$SHOTS/port"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory design/prototype > "$SHOTS/server.log" 2>&1 &
echo $! > "$SHOTS/server.pid"
cat > "$SHOTS/pw-config.json" <<'EOF'
{ "browser": { "contextOptions": { "viewport": { "width": 1280, "height": 900 }, "deviceScaleFactor": 2 } } }
EOF
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$PORT/notchmeow.html"
cd "$SHOTS" && playwright-cli open "http://127.0.0.1:$PORT/notchmeow.html" --config=pw-config.json | grep -E "Page Title|Console"
playwright-cli console | head -2
playwright-cli --raw eval "[...document.querySelectorAll('h2')].map(h => h.textContent).join(' | ')"
playwright-cli --raw eval "document.querySelectorAll('canvas').length"
```

Expected: `200`, `- Page Title: NotchMeow prototype` (and no `Console:` line with errors), `Total messages: 0 (Errors: 0, Warnings: 0)`, `"Cats | Personality | More cats | In the notch | Desktop | Greeting | Size ladder | Small eyes | Collar"` and `25` (the 21 canvases the page had, plus the base and the cat canvas of the mock screen, the strip and the sizes).

- [ ] **Step 3: Click through the trip**

The page's globals are reachable from `playwright-cli eval`. This helper clicks the panel's buttons, waits, and sends pointer events to the mock screen at a point in the screen's own points; the whole trip runs in one call so the waits are the page's own (a command's latency would otherwise be part of the flight). The cat's own times: a flight is 600 ms, and an alert's retract starts about 350 ms after the click (the surprised emote).

```bash
cd "${TMPDIR:-/tmp}/h0-shots"
q() { playwright-cli --raw eval "$1"; }
q "(window.dk = { btn: n => [...document.querySelectorAll('#dkPanel button')].find(b => b.textContent === n).click(), wait: ms => new Promise(r => setTimeout(r, ms)), fire: (type, x, y) => { const r = dkBox.getBoundingClientRect(), k = r.width / DKW; dkBox.dispatchEvent(new PointerEvent(type, { clientX: r.left + x * k, clientY: r.top + y * k, button: 0, bubbles: true, pointerId: 7 })); } }, 'ready')"
q "(async () => { const log = []; const at = s => log.push(s + ': ' + DK.ph); dk.btn('Cat on the desktop'); at('toggle'); await dk.wait(900); at('after 0.9 s'); dk.btn('Approval arrives'); at('approval'); await dk.wait(500); dk.btn('Answered'); at('answered mid-flight'); await dk.wait(300); dk.btn('Approval arrives'); at('a second approval'); await dk.wait(1400); at('after 1.4 s'); dk.btn('Answered'); at('answered'); await dk.wait(1000); at('after 1 s'); dk.btn('Send home'); at('send home'); await dk.wait(900); at('after 0.9 s'); return JSON.stringify(log); })()"
q "JSON.stringify(DK.settings)"
playwright-cli console | head -2
```

Expected: `"ready"`, then one line with the log, `"[\"toggle: flyingOut\",\"after 0.9 s: onDesktop\",\"approval: retracting\",\"answered mid-flight: returning\",\"a second approval: retracting\",\"after 1.4 s: atNotchForAlert\",\"answered: returning\",\"after 1 s: onDesktop\",\"send home: flyingHome\",\"after 0.9 s: home\"]"` (the alert that clears mid-flight turned the cat around, and the second one turned it around again), `"{\"on\":false,\"size\":\"medium\",\"spots\":{}}"` and `Total messages: 0 (Errors: 0, Warnings: 0)`.

- [ ] **Step 4: Drag the cat out, move it, send it home, restart**

```bash
cd "${TMPDIR:-/tmp}/h0-shots"
q() { playwright-cli --raw eval "$1"; }
q "(async () => { const log = [], at = s => log.push(s + ': ' + DK.ph + ' ' + JSON.stringify(DK.spot)); const n = dkNotch(dkIsl());
 dk.fire('pointerdown', 120, 450); log.push('empty desktop: ' + (DK.drag === null ? 'nothing picked up' : 'picked up'));
 dk.fire('pointerdown', n.x, n.y); dk.fire('pointermove', n.x - 30, n.y + 70); dk.fire('pointermove', 250, 300); dk.fire('pointerup', 250, 300); at('dragged out of the notch to 250, 300');
 await dk.wait(300); let s = dkSpot(); dk.fire('pointerdown', s.x, s.y); dk.fire('pointermove', s.x + 50, s.y + 10); dk.fire('pointermove', 800, 530); dk.fire('pointerup', 800, 530); at('dragged into the Dock to 800, 530');
 s = dkSpot(); dk.fire('pointerdown', s.x, s.y); dk.fire('pointerup', s.x, s.y); await dk.wait(120); dk.fire('pointerdown', s.x, s.y); dk.fire('pointerup', s.x, s.y); at('double-click');
 await dk.wait(900); at('after 0.9 s'); dk.btn('Restart the app'); at('restart: the cat was home');
 dk.btn('Cat on the desktop'); await dk.wait(900); dk.btn('Restart the app'); at('restart: the cat was out'); await dk.wait(900); at('after 0.9 s');
 s = dkSpot(); dk.fire('pointerdown', s.x, s.y); dk.fire('pointerup', s.x, s.y); await dk.wait(450); log.push('one click: the island ' + (DK.peek > 0 ? 'opens' : 'stays shut'));
 return JSON.stringify(log); })()"
q "JSON.stringify(DK.settings)"
playwright-cli console | head -2
```

Expected: one line, `"[\"empty desktop: nothing picked up\",\"dragged out of the notch to 250, 300: onDesktop {\\\"x\\\":250,\\\"y\\\":300}\",\"dragged into the Dock to 800, 530: onDesktop {\\\"x\\\":800,\\\"y\\\":420}\",\"double-click: flyingHome {\\\"x\\\":800,\\\"y\\\":420}\",\"after 0.9 s: home {\\\"x\\\":800,\\\"y\\\":420}\",\"restart: the cat was home: home null\",\"restart: the cat was out: flyingOut {\\\"x\\\":800,\\\"y\\\":420}\",\"after 0.9 s: onDesktop {\\\"x\\\":800,\\\"y\\\":420}\",\"one click: the island opens\"]"` (dropped in the Dock, the spot is held 56 points above its top edge: 476 - 56 = 420; and the restarted cat flies out to the spot it remembered), then `"{\"on\":true,\"size\":\"medium\",\"spots\":{\"0,0,960,540\":{\"x\":800,\"y\":420}}}"` and `Total messages: 0 (Errors: 0, Warnings: 0)`.

- [ ] **Step 5: The frame rate, the sizes and the kittens**

```bash
cd "${TMPDIR:-/tmp}/h0-shots"
q() { playwright-cli --raw eval "$1"; }
q "(async () => { mx = null; await dk.wait(2000); const log = [], rate = () => DK.fps + ' ' + DK.why;
 dk.btn('working'); await dk.wait(300); log.push(rate()); dk.btn('idle'); await dk.wait(300); log.push(rate()); dk.btn('sleeping'); await dk.wait(2300); log.push(rate());
 dk.btn('idle'); dk.btn('Hidden (fullscreen app, locked screen)'); await dk.wait(300); log.push(rate()); dk.btn('Hidden (fullscreen app, locked screen)');
 dk.btn('Music playing'); await dk.wait(300); log.push(rate()); dk.btn('Music playing'); dk.btn('Send home'); await dk.wait(1000); log.push(rate());
 return JSON.stringify(log); })()"
q "(async () => { const log = []; dk.btn('Cat on the desktop'); await dk.wait(900); for (const [name, id] of [['Small Ø48', 'small'], ['Large Ø96', 'large'], ['Medium Ø64', 'medium']]) { dk.btn(name); await dk.wait(100); const sl = CatCore.desktopKittenSlots(kitView('integration_claude'), dkSide(dkSpot())); log.push(id + ' ' + DK.size + ' Ø' + dkD() + ' ' + sl.shown.length + ' kittens +' + sl.more + ' side ' + dkSide(dkSpot())); } dk.btn('Send home'); await dk.wait(900); return JSON.stringify(log); })()"
q "document.querySelectorAll('#dkPanel button.on').length + ' buttons on'"
playwright-cli console | head -2
```

Expected: `"[\"20 an agent is working\",\"5 idle and awake\",\"0.5 asleep: a still frame every 2 s\",\"0 hidden: a fullscreen app, a locked or sleeping screen\",\"60 music\",\"0 the cat is in the notch\"]"` (the kittens of Claude Code are four, so three are shown and one is "+1"), then `"[\"small small Ø48 3 kittens +1 side -1\",\"large large Ø96 3 kittens +1 side -1\",\"medium medium Ø64 3 kittens +1 side -1\"]"` (the cat's spot, 800 across, is in the right half of the screen, so its kittens are on its left), a count of `buttons on` (the Size button, a State button and "Mark the empty spot": `3 buttons on`) and `Total messages: 0 (Errors: 0, Warnings: 0)`.

- [ ] **Step 6: Stop the browser and the server**

```bash
cd "${TMPDIR:-/tmp}/h0-shots"
playwright-cli close
kill "$(cat server.pid)"
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$(cat port)/notchmeow.html" || true
```

Expected: `000` (nothing is listening any more).

- [ ] **Step 7: Run the contract once more and commit**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗"`
Expected: `# tests 284`, `# pass 284`, `# fail 0` (the page has no tests of its own).

Run: `git status --short`
Expected: ` M design/prototype/notchmeow.html` and nothing else (the screenshots' folder is outside the repository).

```bash
git add design/prototype/notchmeow.html
git commit -m "feat(prototype): the desktop cat on a mock screen

A Desktop panel: the big cat dragged out of the notch onto a mock desktop, its flight, an alert that flies it into the notch and back, a size picker, the frame rate desktopFps asks for next to the frames really drawn, its badge and kittens, the empty spot in the notch, a right-click menu, the alert flight as a strip of frames and the three sizes. Every rule is CatCore's; no existing panel changes.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Owner checkpoint: screenshots

**Files:**
- Create (outside the repository, never committed): `${TMPDIR:-/tmp}/h0-shots/desktop-sizes.png`, `desktop-alert-strip.png`, `desktop-home.png`, `desktop-out.png`, `desktop-notch-empty-marked.png`, `desktop-notch-empty.png`, `desktop-alert-notch.png`, `desktop-menu.png`

**Interfaces:**
- Consumes: the page from Task 5, and `playwright-cli` with its cached browsers. Produces: eight PNGs at a device scale of 2, and a stop.

The owner looks at these before anything is built on them: the three sizes with the state badge and the kittens (and the body that takes the mouse), a strip of the alert flight's frames, and the notch with its empty big-cat spot while the cat is out (marked, as the prototype can show it, and plain, as the apps will).

- [ ] **Step 1: Serve the page and take the screenshots**

```bash
SHOTS="${TMPDIR:-/tmp}/h0-shots"; mkdir -p "$SHOTS"
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
echo "$PORT" > "$SHOTS/port"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory design/prototype > "$SHOTS/server.log" 2>&1 &
echo $! > "$SHOTS/server.pid"
cat > "$SHOTS/pw-config.json" <<'EOF'
{ "browser": { "contextOptions": { "viewport": { "width": 1280, "height": 900 }, "deviceScaleFactor": 2 } } }
EOF
sleep 1
cd "$SHOTS" && playwright-cli open "http://127.0.0.1:$PORT/notchmeow.html" --config=pw-config.json > /dev/null
q() { playwright-cli --raw eval "$1"; }
shot() { playwright-cli screenshot "$1" --hires --filename="$2" > /dev/null; }
clip() { playwright-cli run-code "async page => { const r = await page.evaluate(() => { const b = document.getElementById('dkDesk').getBoundingClientRect(); return { x: b.left, y: b.top }; }); await page.screenshot({ path: '$1', clip: { x: r.x + 160, y: r.y, width: 640, height: 130 }, scale: 'device' }); }" > /dev/null; }
q "(window.dk = { btn: n => [...document.querySelectorAll('#dkPanel button')].find(b => b.textContent === n).click() }, 'ready')" > /dev/null
playwright-cli eval "document.getElementById('dkSizes').scrollIntoView({block: 'center'})" > /dev/null; sleep 1
shot "#dkSizes" desktop-sizes.png
playwright-cli eval "document.getElementById('dkStrip').scrollIntoView({block: 'center'})" > /dev/null; sleep 1
shot "#dkStrip" desktop-alert-strip.png
playwright-cli eval "document.getElementById('dkDesk').scrollIntoView({block: 'start'})" > /dev/null; sleep 1
shot "#dkDesk" desktop-home.png
q "dk.btn('Cat on the desktop')" > /dev/null; sleep 2
shot "#dkDesk" desktop-out.png
clip desktop-notch-empty-marked.png
q "dk.btn('Mark the empty spot')" > /dev/null; sleep 1
clip desktop-notch-empty.png
q "dk.btn('Mark the empty spot')" > /dev/null
q "dk.btn('Approval arrives')" > /dev/null; sleep 2.5
shot "#dkDesk" desktop-alert-notch.png
q "dk.btn('Answered')" > /dev/null; sleep 2
q "(() => { const s = dkSpot(), r = dkBox.getBoundingClientRect(), k = r.width / DKW; dkBox.dispatchEvent(new MouseEvent('contextmenu', { clientX: r.left + s.x * k, clientY: r.top + s.y * k, bubbles: true, cancelable: true })); return !dkMenu.hidden; })()"
shot "#dkDesk" desktop-menu.png
playwright-cli console | head -2
ls -1 "$SHOTS"/desktop-*.png
```

Expected: `true` (the menu opened), `Total messages: 0 (Errors: 0, Warnings: 0)` and the eight file names above, each with the `h0-shots` path in front.

- [ ] **Step 2: Look at them**

Open each PNG (the `Read` tool shows an image) and check, in this order, before reporting:
1. `desktop-sizes.png`: three columns, Small Ø48, Medium Ø64 and Large Ø96. Top row: the cat with its blue dots badge at the upper right and three kittens in a row at its lower right, then a "+1". Bottom row: the same cat on the right of its cell with the kittens on its left and the "+1" at the far left, and a dashed outline round the head, the badge, each kitten and the "+1": the body that takes the mouse.
2. `desktop-alert-strip.png`: two rows of five frames. Top: the alert arrives (the cat at its spot, surprised), 0.15 s, 0.30 s, 0.45 s along a dotted arc that bows upwards, then "in the notch" with the island open, the "!" badge and its kittens under it. Bottom: it is answered, the cat leaves the notch and flies back along the same arc to "at its spot" with the island shut.
3. `desktop-home.png`: the mock screen with the cat in the compact notch, left of it, two small kittens beside it with a "+2" above, and the four session cats on the right; two windows and the Dock below.
4. `desktop-out.png`: the cat on the desktop at about 576 across and 180 down, with its badge at the upper right and three kittens on its left with a "+1"; the notch's big-cat spot empty, with a dashed ring, and the four session cats still there.
5. `desktop-notch-empty-marked.png` and `desktop-notch-empty.png`: the notch close up, the cat out: the first with the dashed ring where the cat was, the second without it (what the apps show: the spot is simply empty, and the session cats stay).
6. `desktop-alert-notch.png`: the island open (600 by 200) with the cat at its left at Ø64 and the "!" badge, its kittens under it, "Claude Code", "wants to run npm test" and a "needs approval" pill; the desktop under it has no cat.
7. `desktop-menu.png`: the cat on the desktop with its menu: Open the notch, Send home, Size ▸ Small Ø48, Medium Ø64 (checked), Large Ø96, and Cat on the desktop with ⌃⌥D.

If something is wrong (an overlap, a wrong coat, a kitten on the badge, a cat that jumps), say what and where in the report; do not fix numbers in the core on your own.

- [ ] **Step 3: Stop the browser and the server, and stop the plan here**

```bash
cd "${TMPDIR:-/tmp}/h0-shots"
playwright-cli close
kill "$(cat server.pid)"
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$(cat port)/notchmeow.html" || true
```

Expected: `000`.

**Stop here and report to the main session:** the folder `${TMPDIR:-/tmp}/h0-shots` with the eight file names, a line on what each shows and anything that looks wrong. The main session shows the owner. **Task 7 starts only when the main session says go.** If the owner wants other numbers (the kitten slots in `DESKTOP_KITTEN_PLACE`, the arc in `DESKTOP_ARC`, the default spot in `DESKTOP_DEFAULT`, the frame rates), the change is one edit in `cat-core.js`, a regenerate and a re-run of the affected self-checks, made by the main session or by a fix task, before Task 7 documents them.

---

### Task 7: Docs and the final checks

**Files:**
- Modify: `docs/CAT-CONTRACT.md`, `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/specs/2026-10-08-desktop-cat-design.md`

**Interfaces:**
- Consumes: Tasks 1 to 6 and the owner's approval at the checkpoint. Produces: the docs the app plans cite.

- [ ] **Step 1: Write the docs**

The contract doc gains a row of the API table, a row of the fixture table, a section "The desktop cat (H-0)" before "The harness", and eight decisions. `CLAUDE.md` and `ARCHITECT.md` get one line each. The spec gets five small edits so that it says what the contract does: the seventh phase, the trip's flight called `desktopFlightAt` (the owner's answers to questions 1 and 2 below), the 24 points measured from the head's edge, and the `desktop` object of the `cat` block. If the owner's notes at the checkpoint changed a number, change the same number in the section's text before running this.

`````bash
python3 - <<'PY'
# Task 7: the docs. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

# ── docs/CAT-CONTRACT.md ──────────────────────────────────────────────────────────────────────────────────────
p = 'docs/CAT-CONTRACT.md'
s = open(p, encoding='utf-8').read()

# 1. The public surface: one more group, after "Small eyes (B-0)".
anchor = '| Small eyes (B-0) | '
assert s.count(anchor) == 1
i = s.index(anchor); j = s.index('\n', i)
rows = '''
| Desktop cat (H-0) | `DESKTOP_PHASES`, `DESKTOP_PHASE_INFO`, `DESKTOP_EVENTS`, `DESKTOP_ACTS`, `DESKTOP_NEXT`, `desktopStep`, `DESKTOP_FLIGHT_MS`, `DESKTOP_ARC`, `desktopFlightAt`; `DESKTOP_SIZES`, `DESKTOP_SIZE_IDS`, `DEFAULT_DESKTOP_SIZE`, `desktopSizeOf`, `DESKTOP_FPS`, `DESKTOP_NEAR`, `desktopFps`, `DESKTOP_KITTEN_PLACE`, `desktopKittenSlots`; `DESKTOP_MARGIN`, `DESKTOP_DEFAULT`, `MAX_DESKTOP_SPOTS`, `screenKey`, `isScreenKey`, `defaultDesktopSpot`, `clampSpot`, `cleanDesktopSpots`, `spotFor`, `rememberSpot`; `cleanDesktopSettings`, `defaultDesktopSettings` |'''
s = s[:j] + rows + s[j:]

# 2. The fixture table: one more row, after small-eye-cases.json.
anchor = '| `small-eye-cases.json` | '
assert s.count(anchor) == 1
i = s.index(anchor); j = s.index('\n', i)
rows = '''
| `desktop-cases.json` | `phaseIds`, `phases`, `events`, `acts`, `flightMs`, `arc`, `steps` (`desktopStep` for every phase and event, and for input that is neither), `trips` (a script of events, the state and act after each), `flights` (`desktopFlightAt`), `sizes`, `sizeIds`, `defaultSize`, `sizeCases`, `fps`, `near`, `fpsCases` (`desktopFps`), `kittenPlace`, `kittenSlots` (`desktopKittenSlots`), `kittenSizes` (the same in points at each size), `margin`, `defaultSpot`, `maxSpots`, `screenKeys`, `isScreenKey`, `clamps` (`clampSpot`), `defaultSpots`, `spotFor`, `remembers` (`rememberSpot`), `spotMaps` (`cleanDesktopSpots`), `settingsDefaults`, `settingsCases` (`cleanDesktopSettings`). See "The desktop cat (H-0)". |'''
s = s[:j] + rows + s[j:]

# 3. The new section, before "The harness".
anchor = '\n## The harness\n'
assert s.count(anchor) == 1
section = r'''
## The desktop cat (H-0)

Sub-project H (`docs/superpowers/specs/2026-10-08-desktop-cat-design.md`) lets the big cat leave the notch and live on the desktop. Its rules are pure and pinned by one fixture file, `desktop-cases.json`. All of it is new names and a new file: no existing function, constant or fixture line changed (`node scripts/check-fixtures-additive.mjs 1627851` proves the fixtures), so both apps stay green until their H plans land. The prototype page's Desktop panel draws it, so the page is the look and the core is the numbers. Two things differ from the spec's wording: its `flightAt(from, to, t)` is `desktopFlightAt`, because `flightAt` and `FLIGHT_MS` already belong to the file catch (380 ms, copied by both apps), and the trip has seven phases, because "flies it home" needs one of its own.

**Coordinates.** Points, y down, the origin at the top left of the main screen (the Mac converts AppKit's bottom-left origin: `yTop = primaryHeight - frame.maxY`). A *spot* is the cat's head centre `{x, y}`: two finite numbers, each no larger than 100000 in size; anything else is not a spot. A *screen* is `{frame: {x, y, w, h}, visible: {x, y, w, h}, main: true}`: `frame` is the whole screen, `visible` what the menu bar and the Dock leave (missing or outside the frame, it is the frame; otherwise it is held inside it), and `main` marks the screen with the menu bar. A frame needs finite numbers up to 1,000,000 in size and a width and height of at least 1. A size is a size ID (`small`, `medium`, `large`; anything else is `medium`).

### The trip

`desktopStep(state, event)` returns `{state, act}`: the next phase and what the app does, or the same phase and `act: null` when the event makes no sense there. A state that is not a phase counts as `home`; an event that is not an object with a known `type`, and a `dragOut` or `move` without a valid spot, change nothing.

| Phase | The cat is | Notch spot | Desktop window | Stored as "out" |
|---|---|---|---|---|
| `home` | in the notch | holds it | draws nothing | no |
| `flyingOut` | flying from the notch to the desktop spot | empty | draws it | yes |
| `onDesktop` | on the desktop | empty | draws it | yes |
| `retracting` | flying to the notch because an approval or a question arrived | empty | draws it | yes |
| `atNotchForAlert` | in the notch spot while the user answers | holds it | draws nothing | yes |
| `returning` | flying back out to its spot after the alert cleared | empty | draws it | yes |
| `flyingHome` | flying to the notch because it was sent home | empty | draws it | no |

`DESKTOP_PHASE_INFO` holds the same table as `{flight, dir ('out' towards the desktop spot, 'in' towards the notch, or null), drawn, notchEmpty, on}`. A phase that is drawn has an empty notch spot, so there are never two copies of one cat.

Events (`DESKTOP_EVENTS`): `dragOut{spot}` (the big cat was dropped on the desktop), `move{spot}` (the desktop cat was dragged), `toggle` (the menu item, ⌃⌥D, the switch), `sendHome` (a double-click, the menu, or the cat dropped on the notch), `alertOn`, `alertOff`, `flightDone`, `launch` (after the greeting, when the cat was out) and `screensChanged`. What changes (every other pair changes nothing; the fixture's `steps` pin all 63):

- `home`: `dragOut` → `onDesktop` (`place`); `toggle`, `launch` → `flyingOut` (`flyOut`).
- `flyingOut`: `toggle`, `sendHome` → `flyingHome` (`turn`); `alertOn` → `retracting` (`turn`); `flightDone` → `onDesktop` (`land`); `screensChanged` → same (`resettle`).
- `onDesktop`: `move` → same (`move`); `toggle`, `sendHome` → `flyingHome` (`flyHome`); `alertOn` → `retracting` (`retract`); `screensChanged` → same (`resettle`).
- `retracting`: `toggle`, `sendHome` → `flyingHome` (`keep`); `alertOff` → `returning` (`turn`); `flightDone` → `atNotchForAlert` (`dock`).
- `atNotchForAlert`: `toggle`, `sendHome` → `home` (`goHome`); `alertOff` → `returning` (`flyOut`).
- `returning`: `toggle`, `sendHome` → `flyingHome` (`turn`); `alertOn` → `retracting` (`turn`); `flightDone` → `onDesktop` (`land`); `screensChanged` → same (`resettle`).
- `flyingHome`: `toggle` → `flyingOut` (`turn`); `flightDone` → `home` (`dock`).

An alert that clears mid-flight turns the cat around (`retracting` + `alertOff`). A `sendHome` during an alert ends the trip at home: the flight to the notch carries on and ends in `home`, or the cat that is already in the notch spot is simply home. An approval that lands while the cat is home, or while it flies home, does not take it out.

The acts (`DESKTOP_ACTS`): `place` show the cat at `event.spot`, no flight; `flyOut` fly from the notch spot to the desktop spot; `flyHome` fly from the desktop spot to the notch spot; `retract` the surprised emote, then fly from the desktop spot to the notch spot; `turn` reverse the flight in progress, carrying on from progress `1 - t`; `keep` the flight goes on the same way under its new phase; `land` the flight ended at the desktop spot; `dock` it ended at the notch spot, which shows the cat again; `goHome` the cat was already in the notch spot; `move` clamp `event.spot` and save it (`rememberSpot`); `resettle` find the spot again (`spotFor`) and put the cat there. `turn` is exactly a change between two flight phases whose `dir` differs, and `keep` a change between two with the same `dir`.

**The flight.** `desktopFlightAt(from, to, t)` gives `{x, y, scale}`, `t` held to 0 to 1 (a `t` that is not a number is 0). The path is a quadratic arc eased in and out (`EZ.inOut`) that bows upwards by a quarter of the distance, at most 90 points (`DESKTOP_ARC`); a vertical flight bows to the right. The cat keeps its full size the whole way (`scale` is 1). `DESKTOP_FLIGHT_MS` is 600. The path is the same both ways: the position at `(from, to, t)` is the position at `(to, from, 1 - t)`, which is what makes `turn` seamless: the app keeps the flight's clock, swaps its ends and starts at progress `1 - t`. A `from` or `to` that is not a spot counts as 0, 0. A flight starts where the cat is on screen (the drop point for a cat dropped on the notch), which the app knows; the contract only draws the path.

### Frame rate

`desktopFps({phase, hidden, dragging, emote, kittenMotion, dance, asleep, working, cursorDist})`, in this order:

| When | Frames per second |
|---|---|
| the phase is not drawn on the desktop (`home`, `atNotchForAlert`), or `hidden` is true (the screen is asleep or locked, the display is off, a fullscreen app covers the cat) | 0 |
| a flight, or `dragging`, `emote`, `kittenMotion` (a kitten arriving or leaving), `dance` | 60 |
| `asleep` | 0.5: a still frame redrawn every 2 s |
| `working` (the cat's agent works, thinks or searches), or `cursorDist` within 150 points (`DESKTOP_NEAR`, inclusive) | 20 |
| anything else | 5 |

Only `true` counts for a flag, and `cursorDist` counts only as a finite number (leave it out when the app cannot know it, as on Wayland). A sleeping cat does not watch the cursor, so sleep beats it; the app clears `asleep` the moment a hover, a click or an agent event wakes the cat. `DESKTOP_FPS` is `{motion: 60, active: 20, idle: 5, asleep: 0.5, off: 0}`.

### Sizes and kittens

`DESKTOP_SIZES` is `{small: 48, medium: 64, large: 96}` (the head width in points); the IDs are frozen like the cat IDs and `desktopSizeOf` maps anything else to `medium`. The desktop cat's kittens come from `desktopKittenSlots(kittens, side)`, with the same slot maths as `kittenSlots` and a table of its own, `DESKTOP_KITTEN_PLACE` (`KITTEN_PLACES` is untouched): up to 3 kittens of 0.3 D in a row at the lower right of the cat (the first centred 0.82 D right and 0.22 D down from the head centre, 0.33 D apart), then a "+N" at the next slot; D is the cat's head width, so one table serves all three sizes. `side` -1 mirrors every x (a cat in the right half of its screen keeps its kittens on the screen); anything else is 1. The badge is where `layout` puts it (upper right), and a test keeps the kittens clear of the badge, the head and the ruff on every coat.

### Spots

- **`screenKey(screens)`** is the key an arrangement of screens is remembered under: the frames rounded to whole points (half up: `floor(v + 0.5)`), sorted, each written `x,y,w,h` and joined with `|`; no usable screen gives `""` (at most 16 frames count). The order the screens come in does not matter, and neither do the visible frames or the main flag (moving the Dock must not forget the spot). `isScreenKey(key)` is true for exactly what it writes.
- **`clampSpot(spot, screens, size)`** keeps a spot where the cat may sit: on the screen whose frame holds it (a frame holds its left and top edges), inside that screen's visible frame, `DESKTOP_MARGIN` (24) points from the *head's edge*, so the centre is `24 + D/2` from every edge (a visible frame too small for that holds the centre). A spot on no screen, or that is not a spot, goes to the main screen's default spot; no screens gives `null`.
- **`defaultDesktopSpot(screens, size)`** is 0.6 across and a third of the way down the main screen's visible frame (`DESKTOP_DEFAULT`), held inside its margins. The main screen is the one marked `main`, else the one holding the origin, else the first by frame.
- **`spotFor(spots, screens, size)`** is the spot remembered for this arrangement, clamped, else the default spot, so a laptop alone and a laptop with a monitor each keep their own. **`rememberSpot(spots, screens, spot, size)`** returns the map with this arrangement's clamped spot; the map keeps at most `MAX_DESKTOP_SPOTS` (32) arrangements and always keeps the one just written.
- **`cleanDesktopSpots(raw)`** cleans a stored map: an object or its JSON text, with only keys `isScreenKey` accepts and only values that are spots (reduced to `x` and `y`), in code-point order of the keys, the first 32.

### Stored settings

`cleanDesktopSettings(raw)` returns `{on, size, spots}` and never throws: `on` is true only for the boolean true, `size` one of the three IDs (else `medium`), `spots` as `cleanDesktopSpots`. It is a clean-up of its own, as `cleanDisplaySettings` is: `cleanCatSettings`, `cleanDisplaySettings` and every line of their fixtures stay as they were, and an app cleans what it stored with each function it needs.

| macOS key | Field |
|---|---|
| `cat.desktop.on` | `on` (a Bool) |
| `cat.desktop.size` | `size` (`small`, `medium` or `large`) |
| `cat.desktop.spots` | `spots`, as the JSON text of the map |

Windows and Linux keep `{on, size, spots}` as the `desktop` object of the `cat` block of `settings.json` (`spots` an object); `cleanDesktopSettings(block.desktop)` cleans it. "On" is stored as `DESKTOP_PHASE_INFO[phase].on`.

**Notes for ports:**
- **`desktopStep` returns a pair,** `{state, act}`, and the fixture's `steps` hold every phase and event, so a port replays all 63 plus the input that is not a phase or an event.
- **Screen coordinates are stored with 12 significant digits,** so a number of 1000 or more that is not a whole number or a half loses precision below 1e-9. The fixtures keep every such number under 1000 points or a whole number; ports compare with the 1e-9 tolerance as everywhere.
- **Rounding in `screenKey` is `floor(v + 0.5)`,** not the language's own `round` (Swift's `rounded()` rounds half away from zero, which differs below zero).
- **The key shape is matched against the whole string.** ICU and Swift's `NSRegularExpression` let `$` match before a final newline: use a whole-match, or `\z`. The fixture holds `0,0,1512,982\n` as not a screen key.
- **JSON cannot hold `NaN` or `Infinity`,** so the fixtures use `null`, a missing key or text for them; a port adds its own tests for a `t`, a spot or a `cursorDist` that is not finite (`t` is 0, a spot is not a spot, a distance is not near).
- **Key order does not matter** in a map: `spots` are written in code-point order and the cap is on that order, so a port that cannot keep a dictionary's order sorts the keys before taking the first 32.
- **Replay the fixture:** `steps` and `trips` (`desktopStep`), `flights` (`desktopFlightAt`), `sizeCases`, `fpsCases`, `kittenSlots`, `kittenSizes`, `screenKeys`, `isScreenKey`, `clamps`, `defaultSpots`, `spotFor`, `remembers`, `spotMaps` and `settingsCases`.
'''
s = s.replace(anchor, section + anchor)

# 4. Decisions to know about: more.
s = s.rstrip('\n') + '''
- **The desktop cat's flight is `desktopFlightAt`.** `flightAt` and `FLIGHT_MS` are the file catch's flight (380 ms) and both apps copy them, so the trip's flight has names of its own.
- **The trip has seven phases.** `flyingHome` is the one the spec's six lacked: a double-click, the menu or the switch "flies it home", and `retracting` ends at the notch spot for an alert. A flight that changes phase keeps its clock and either carries on (`keep`, the same direction) or turns around (`turn`, from progress `1 - t`, retracing its own path).
- **A cat dropped on the desktop is placed, not flown:** `dragOut` goes straight to `onDesktop`, because the cat is already under the pointer. Only the menu item, ⌃⌥D, the switch and a launch fly it out.
- **A spot is the head centre, and the 24 points are the head's edge's:** a Ø96 cat's centre is 72 points from the visible frame's edge, so the cat never half-leaves the screen. A spot on no screen is the main screen's default, not the nearest screen's edge.
- **The screen key is the frames only.** The Dock and the menu bar move without changing the arrangement, so the spot is not forgotten; the clamp reads the visible frame at the time.
- **Desktop settings have their own clean-up,** like the Display settings: three functions clean one stored block, and none of them sees the others' keys.
- **Sleep beats the cursor, and hidden beats everything.** A sleeping cat does not watch the cursor (20 fps), and a cat that cannot be seen is not drawn even while it flies.
- **Kittens mirror to the left in the right half of the screen** (`side` -1), so they stay on the screen; the contract gives both layouts and the apps pick one by where the cat is.
'''
open(p, 'w', encoding='utf-8').write(s)

# ── CLAUDE.md, ARCHITECT.md and the spec ──────────────────────────────────────────────────────────────────────
edit('CLAUDE.md', [("Display mode IDs (`one`, `perAgent`, `two`) are frozen like the cat IDs.\n",
 "Display mode IDs (`one`, `perAgent`, `two`) are frozen like the cat IDs.\n"
 "- `cat-core.js` also holds sub-project H's rules for the desktop cat, all new names beside B's and pinned by one fixture, `desktop-cases.json`: the trip (`desktopStep`, `desktopFlightAt`), `desktopFps`, `screenKey`, `clampSpot` and `spotFor`, `cleanDesktopSettings` (a clean-up of its own) and `desktopKittenSlots`; `docs/CAT-CONTRACT.md`, \"The desktop cat (H-0)\". The size IDs (`small`, `medium`, `large`) are frozen like the cat IDs, and `flightAt` stays the file catch's flight.\n")])
edit('ARCHITECT.md', [("swept by the cat's sleep timer, in both builds.\n",
 "swept by the cat's sleep timer, in both builds.\n"
 "   - **Sub-project H (the desktop cat):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/desktop-cases.json` (new names only; the prototype's Desktop panel draws it): the trip `desktopStep` (seven phases) with `desktopFlightAt`, `desktopFps`, `screenKey`, `clampSpot` and `spotFor`, `cleanDesktopSettings` and `desktopKittenSlots`; see `docs/CAT-CONTRACT.md`, \"The desktop cat (H-0)\". The two H app plans build on it.\n")])
edit('docs/superpowers/specs/2026-10-08-desktop-cat-design.md', [
 ("| `returning` | Flying back out to its desktop spot after the alert cleared. |\n",
  "| `returning` | Flying back out to its desktop spot after the alert cleared. |\n| `flyingHome` | Flying back to the notch because the user sent the cat home (a double-click, the menu, the menu-bar item, ⌃⌥D or the switch). |\n"),
 ("The path and its timing are a pure function in the core: `flightAt(from, to, t)` gives the position and scale at `t`.",
  "The path and its timing are a pure function in the core: `desktopFlightAt(from, to, t)` gives the position and scale at `t` (`flightAt` is the file catch's flight)."),
 ("`clampSpot` keeps the cat 24 pt inside the visible frame, never under the menu bar or the Dock.",
  "`clampSpot` keeps the cat's head 24 pt inside the visible frame, never under the menu bar or the Dock."),
 ("- Windows/Linux: the same three fields in the `cat` block of `settings.json`.",
  "- Windows/Linux: the same three fields as the `desktop` object of the `cat` block of `settings.json`."),
 ("`desktopStep`, `flightAt`, `desktopFps`", "`desktopStep`, `desktopFlightAt`, `desktopFps`"),
])
PY
git diff --stat -- CLAUDE.md ARCHITECT.md docs

`````

Expected: four files: `ARCHITECT.md` (1 line added), `CLAUDE.md` (1 added), `docs/CAT-CONTRACT.md` (95 added) and the spec (9 lines: 5 added, 4 changed), and `4 files changed, 102 insertions(+), 4 deletions(-)`.

- [ ] **Step 2: The final checks**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 284`, `# pass 284`, `# fail 0`, fifteen `✓` fixture lines, `✓ 15 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 1627851`
Expected: fourteen `✓ <file>: N old lines unchanged` lines for the old fixtures (`collar-cases.json` 187, `geometry-cases.json` 180, `motion-cases.json` 713, `personality-cases.json` 62, `presets.json` 42, `search-tools.json` 36, `sequence-cases.json` 231, `settings-cases.json` 110 and `warp-cases.json` 121, with B's five: `agent-cat-cases.json` 64, `cast-cases.json` 161, `display-cases.json` 140, `kitten-cases.json` 104 and `small-eye-cases.json` 315), `+ desktop-cases.json is new` and `✓ fixtures changed only by addition since 1627851`.

Run: `bash scripts/check-no-leftovers.sh`
Expected: five `✓` lines.

The apps still pass their own fixture tests (the new file changes none of them). The Windows tests run the shared fixtures through the app's own port; the Mac scripts compile the Swift ports with the installed toolchain (nothing is installed or downloaded) and take about three minutes in all:

The Windows tests need no `node_modules` (they run `node --experimental-strip-types`), so there is nothing to install; if one says a module is missing, stop and report it.

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `ℹ tests 272`, `ℹ pass 272`, `ℹ fail 0`.

```bash
pass=0; fail=0
for f in scripts/test-cat-*.sh; do
  if bash "$f" > "${TMPDIR:-/tmp}/h0-$(basename "$f").log" 2>&1; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "✗ $f"; fi
done
echo "Mac cat scripts: $pass passed, $fail failed"
```

Expected: `Mac cat scripts: 25 passed, 0 failed`.

Run: `git status --short`
Expected: ` M CLAUDE.md`, ` M ARCHITECT.md`, ` M docs/CAT-CONTRACT.md`, ` M docs/superpowers/specs/2026-10-08-desktop-cat-design.md`. Nothing under `NotchBuddy/` or `windows/` is modified, and `git log --oneline notchmeow/rebrand..HEAD` lists the five commits of Tasks 1 to 5 (the base is later than `1627851`, so a log from `1627851` would list `notchmeow/rebrand`'s own commits too).

- [ ] **Step 3: Commit**

```bash
git add docs/CAT-CONTRACT.md CLAUDE.md ARCHITECT.md docs/superpowers/specs/2026-10-08-desktop-cat-design.md
git commit -m "docs(cat): the desktop cat's contract is documented

CAT-CONTRACT.md gains the section and the fixture row; CLAUDE.md and ARCHITECT.md point to it; the spec says the trip has seven phases and that its flight is desktopFlightAt.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer changes `cat-core.js` and the one fixture, and the app plans pick it up.

1. **`flightAt` is taken, so the trip's flight is `desktopFlightAt`.** The spec (§1, §4) names `flightAt(from, to, t)`, but `flightAt` and `FLIGHT_MS` are the file catch's flight (380 ms, `sequence-cases.json`) and both apps copy and pin them ("only new names"). The new function is `desktopFlightAt` with `DESKTOP_FLIGHT_MS` 600, and Task 7 edits that sentence of the spec. (Assumed: yes.)
2. **The trip has seven phases, not six.** A double-click, "Send home", the menu-bar item, ⌃⌥D and the switch all "fly it home" (spec §1), but none of the six states is that flight: `retracting` ends at the notch spot for an alert. `flyingHome` is the seventh (ends in `home`); it makes "a `sendHome` during an alert ends the trip at home" exact (`retracting` + `sendHome` carries on to `flyingHome`, then `home`) and gives `toggle` something to turn around mid-flight. Task 7 adds its row to the spec's table. (Assumed: yes.)
3. **`desktopStep` returns `{state, act}`, not only the state.** The act says what the app does (`place`, `flyOut`, `flyHome`, `retract`, `turn`, `keep`, `land`, `dock`, `goHome`, `move`, `resettle`), so the two apps do not each derive "turn around" from pairs of phases. A `null` act is exactly "makes no sense: nothing changed". (Assumed: yes; an app that wants only the state reads `.state`.)
4. **A cat dropped on the desktop is placed, not flown:** `dragOut` goes straight to `onDesktop` (the cat is already under the pointer). Only the menu item, ⌃⌥D, the switch and the launch fly it out, from the notch spot to its remembered or default spot. (Assumed: yes.)
5. **`toggle` and `sendHome` are the same in every phase but `home` and `flyingHome`:** out is `toggle`, home is either; in the notch for an alert they end the trip at home at once (`goHome`); mid-flight they turn the cat around (`turn`) or, if it is already flying to the notch, let it carry on and end at home (`keep`). During the flight home, `toggle` turns it back out. `dragOut` and `move` make no sense in flight or in the notch. (Assumed: yes.)
6. **A pending alert does not stop the user taking the cat out,** and the machine keeps no flag for it: the spec says an approval that lands while the cat is home does not take it out, and "an alert becomes set" is the trigger, so a cat sent out while an approval is already open stays out until the next alert. (Assumed: yes; an app that wants the cat to stay home while an alert is pending refuses `toggle` itself.)
7. **The flight:** a quadratic arc that bows upwards by a quarter of the distance (at most 90 pt; a vertical flight bows to the right), eased with the core's cubic in-out, 600 ms, at full size the whole way (`scale` is always 1; the field exists so a later change is a core change). The path is the same both ways so a turn-around retraces itself from `1 - t`. **The pop:** a flight that ends at the compact notch spot goes from the desktop size (Ø48, Ø64 or Ø96) to the notch cat's Ø20 at its last frame, and one that ends at an alert's expanded spot (Ø64) is seamless at Medium: the prototype shows both; a short shrink over the last 100 ms would be an additive change. (Assumed: as the spec says, full size the whole way.)
8. **The default spot:** the cat's head centre 0.6 across and a third down the main screen's visible frame (`DESKTOP_DEFAULT`), held inside the margins: on a 1512 by 982 laptop, (907, 329). The main screen is the one marked `main`, else the one holding the origin, else the first by frame. (Assumed: "right of centre" is 0.6.)
9. **A spot is the head centre, and the 24 points are from the head's edge:** a Ø96 cat's centre is 72 points from the visible frame's edge, so the cat never half-leaves the screen (reading the spec's "keeps the cat 24 pt inside" as the cat's centre would let a Large cat hang 24 points off it). A spot on no screen (the monitor it was on is unplugged, a gap, or text) goes to the main screen's default spot, not to the nearest edge. The kittens and the badge are not part of the clamp; the apps pick the kittens' side (question 11). (Assumed: yes.)
10. **The frame rate:** exactly the spec's table (60, 20, 5, a still frame every 2 s as 0.5, 0), with "near" meaning 150 points inclusive. The cat in the notch for an alert counts as 0 here (the notch draws it), and `hidden` beats a flight; sleep beats the cursor (a sleeping cat does not watch it) and motion beats sleep. The flags are `dragging`, `emote`, `kittenMotion`, `dance`, `asleep`, `working`, `hidden` and `cursorDist`. (Assumed: yes.)
11. **The desktop kittens:** up to 3 of 0.3 D in a row at the lower right of the cat (the first centred 0.82 D right and 0.22 D down, 0.33 D apart, clear of the badge and the ruff on every coat), then "+N" at the next slot; `side` -1 mirrors them to the left, and the prototype puts them there when the cat is in the right half of its screen so they stay on the screen. The `side` argument is an addition to the spec's `desktopKittenSlots(kittens)`; drop it if you would rather keep them always on the right. Kittens are not drawn while the cat flies. (Assumed: yes.)
12. **Storage:** Windows and Linux keep `{on, size, spots}` as a `desktop` object inside the `cat` block (the spec says "the same three fields in the `cat` block"; loose `on`, `size` and `spots` next to `character` and `displayMode` would be ambiguous); the Mac's three UserDefaults keys are the spec's. A spot is two finite numbers of at most 100000 in size, the map holds at most 32 arrangements, and the Mac stores the map as JSON text, as it stores the pair. (Assumed: yes.)
13. **The screen key** is the frames only (`x,y,w,h`, rounded half up, sorted, joined with `|`), so the Dock and the menu bar moving does not forget the spot; mirrored screens count twice; at most 16 screens count. (Assumed: yes.)
14. **Helpers beyond the brief:** `DESKTOP_PHASE_INFO`, `DESKTOP_ACTS`, `DESKTOP_NEXT`, `DESKTOP_EVENTS`, `desktopSizeOf`, `DESKTOP_FPS`, `DESKTOP_NEAR`, `isScreenKey`, `defaultDesktopSpot`, `rememberSpot` (the write that keeps the new arrangement even in a full map), `cleanDesktopSpots`, `defaultDesktopSettings`. Each is small, and each stops the two apps reading a rule two ways. Drop any you would rather leave to the apps. (Assumed: keep.)
15. **The prototype's additions beyond the brief:** the empty notch spot is marked with a dashed ring (a toggle; the real notch draws nothing there), a frame-rate readout that shows the rate asked for next to the frames really drawn, a right-click menu, a Hit area outline, a Clamp area outline, a Dock that moves to the left (to show `screensChanged` and the visible frame), a "Restart the app" button (to show `launch` and the stored `on`), and a sheet of the three sizes with the body outlined. No existing panel changes. (Assumed: yes.)
16. **The window and the hit shape are the apps':** the contract gives the cat's numbers (head width D, `layout()`, the kitten slots) and the apps size the window for the cat, its ears, its badge and the kittens' side in use. The prototype's body (a circle of 0.55 D, the badge and the kitten slots) is a reference. (Assumed: yes.)

## Self-review notes

- **Spec coverage.** §1 "The trip": the phases and events (Task 1), the flight (Task 1), "getting it out", "bringing it home" and the alerts as acts of `desktopStep` (Task 1; the apps do them), "remembered" (`screenKey`, `clampSpot`, `spotFor`, `rememberSpot`: Task 3; `on` and `size`: Task 4; "after the greeting, a cat that was out flies back out": the `launch` event). §2 "On the desktop": the sizes and the kittens (Task 2), the badge, collar, eyes, cursor-watching, dance and sleep are the renderer's and the apps' (the prototype draws them, Task 5), the clicks, the double-click interval and the hit-testing are in the prototype and the Interface section. §3: the frame-rate rule (Task 2), the storage (Task 4), the controls and the platform notes (the Interface section). §4 step 1: the rules and the fixture (Tasks 1 to 4), the prototype (Task 5) and the owner checkpoint (Task 6). Out of scope and left out: two cats on the desktop, a cat that walks, the wardrobe, files dropped on the desktop cat, global shortcuts on Windows and Linux, sounds for the trip.
- **Placeholders.** None: every code step carries its full content, generated into this plan from the files the dry run ran.
- **Type consistency.** The names in the interface tables are the ones in the core sections, the tests, the fixture builder, the prototype and the docs; the event `{type, spot?}`, the result `{state, act}`, the spot `{x, y}`, the screen `{frame, visible, main}` and the settings `{on, size, spots}` are the same everywhere.
- **Review Focus** lines 1 to 5 each have named tests above.
- **What this plan deliberately does not do:** touch either app; add the Settings switch, the menu items or ⌃⌥D; build the window or its click-through; measure the frame rate (a bench is the app plans' job); decide the window's size and edges; add sounds.

## Dry run (2026-10-08)

Run before the plan was handed over, in throwaway clones made with `git clone --local --shared` of the repository, on branch `notchmeow/rebrand` at `1627851` (nothing was installed or downloaded: the browsers are the ones `playwright-cli` had cached, and `windows/node_modules` was not needed). The first clone was used to write and test the code, task by task, from work files; the later clones ran the plan text from its first line to its last. Each task was applied **exactly as written** by a small script that executes the plan's `bash` blocks (the five-backtick docs block included) and `Run:` lines in order, prints what each printed beside the plan's `Expected:` line, and flags any backticked token of an `Expected:` line that the output lacks (the plan text is generated from the files the first clone ran). The last clone ran all 66 items with no non-zero exit; the only flagged tokens were words of the prose (the function name in "the core has no `desktopStep` yet", `Console:`, the placeholder `<file>`, and the `NotchBuddy/`, `windows/` and `git log` of a sentence about the status). Each task's commit landed with exactly the files its `git add` names (`git log --stat` of the clone). The static server and the browser were started and stopped by the plan's own steps, and both were gone afterwards. The clones were then moved to the Trash, and nothing was committed or pushed in the main checkout, where this file is untracked.

| Task | Result |
|---|---|
| Baseline, before any change | `bash scripts/test-cat-contract.sh`: `# tests 231`, `# pass 231`, 14 fixtures, determinism check passes; the 25 `scripts/test-cat-*.sh` pass (about 2 minutes 15 seconds); `npm run check:cat`: `ℹ tests 272`, `ℹ pass 272` |
| 1 | `desktop.test.mjs` fails 13 of 13 without the section and passes 13 of 13 with it; with the alert turn-around taken out of the table, test 5 fails (`# pass 12`), with the arc's tie rule taken out, tests 11 and 12 fail (`# pass 11`); the whole contract `# tests 244`, then `# tests 248` with 15 fixtures; `desktop-cases.json` is 25,923 bytes (7 phases, 89 steps, 11 trips, 89 flights); `check-fixtures-additive.mjs 1627851`: the 14 old files keep 187, 180, 713, 62, 42, 36, 231, 110, 121, 64, 161, 140, 104 and 315 lines and `✓ fixtures changed only by addition`; with the arc's `max` at 80, `--check` prints `✗ desktop-cases.json drifted from cat-core.js (30 differences)` |
| 2 | 10 of 10 self-checks; with the cursor boundary changed from `<=` to `<`, tests 19 and 23 fail (`# pass 25`); `# tests 258`, then `# tests 260`; `desktop-cases.json` is 39,922 bytes (17 size cases, 39 frame-rate cases, 21 kitten slot rows, 12 kitten size rows) |
| 3 | 13 of 13; with the margin measured from the centre, six tests fail (`# pass 36`), with the sort after the rounding taken out, test 32 fails; `# tests 273`, then `# tests 276`; `desktop-cases.json` is 77,219 bytes (19 screen keys, 30 key shapes, 54 clamps, 8 default spots, 13 `spotFor`, 8 `rememberSpot`, 18 spot maps) |
| 4 | 7 of 7; with `on` read as truthy instead of `true`, tests 46 and 48 fail (`# pass 50`); `# tests 283`, then `# tests 284`; `desktop-cases.json` is 106,338 bytes (41 settings cases, the 300-arrangement block written out) |
| 5 | The patch applies (192 insertions, 1 deletion); the page loads with 0 console errors, the 9 panel headings and 25 canvases; the trip clicked through (an approval, answered mid-flight and the cat turned round, a second approval, answered, then home); pointer events: nothing happens on empty desktop, the cat dragged out of the notch to (250, 300), dragged into the Dock and held at (800, 420), a double-click sent it home, a restart with the cat home leaves it home and one with the cat out flies it back to the remembered spot, a click opens the island; the frame rate reads 20, 5, 0.5, 0 and 60 as the table says; the kittens are 3 and "+1" at all three sizes; the server is gone afterwards (`000`) |
| 6 | Eight PNGs at a device scale of 2 (about 61 to 337 KB) in `${TMPDIR}/h0-shots`, console empty. I looked at all of them: they show what Step 2 says they show |
| 7 | The docs apply (`CAT-CONTRACT.md` +95, `CLAUDE.md` +1, `ARCHITECT.md` +1, the spec 9 lines: `4 files changed, 102 insertions(+), 4 deletions(-)`); the final contract run `# tests 284`, 15 fixtures; the additive check as listed; `check-no-leftovers.sh` five `✓`; the Windows cat tests `ℹ tests 272`, `ℹ pass 272`; `Mac cat scripts: 25 passed, 0 failed` in 136 s |

**What drafting and the dry run changed in the plan:**
- **`flightAt` was already taken.** Reading the core for the spec's `flightAt(from, to, t)` found the file catch's `flightAt` and `FLIGHT_MS` (both apps copy them), so the trip's flight became `desktopFlightAt` (open question 1).
- **The trip needed a seventh phase.** Writing the transition table showed that "double-click flies it home" has no phase among the spec's six (open question 2), and that without an act on each transition the two apps would each derive "turn around" differently (open question 3).
- **`t` of Infinity** was first treated as "not a number" (0); the self-check caught it, and plus and minus infinity now clamp to the ends.
- **12 significant digits** cost more than the 1e-9 tolerance on a position of 1000 points or more (a flight to (1500, 900) stored 1494.3689552 for 1494.36895519613), so the fixtures' flights stay under 1000 points and a test says so.
- **A spot just outside every frame** is on no screen and goes to the default spot (the first draft's test expected the nearest edge); the decision is in the docs and open question 9.
- **A missing `side` or `size`** left an `undefined` key in the builder's rows that `--check` reported as drift; those rows now omit the key.
- **The page.** A first click-through found the pointer handler comparing against the wrong word for the desktop cat's source (nothing happened on a click); `setPointerCapture` is in a try/catch so a synthetic pointer works; a cat dropped on the notch flies home from the drop point, not from its old spot; the kittens' small engines are stepped when drawn, because the desktop layer draws them at 5 fps. `playwright-cli` needs `--hires` for a device-scale screenshot, its `eval` takes an expression, and each command takes about a second, so the trip's timings are checked in one in-page call.
- **The docs block's fence.** The docs patch sits in a five-backtick fence (the section's text has its own backticks); the first replay script skipped it, which showed up as a clean working tree at the commit step, and the script was fixed.

**Not run, by rule:** no NotchMeow app and no Tauri app was launched, and no `xcodebuild`, `cargo` or `tauri` command ran (the plan touches no app code; the Mac scripts compile the Swift ports with the installed toolchain). Task 6's stop is a human gate and the run did not wait at it. The commit steps were run in the throwaway clones, so that each later task started from its predecessor's commit.
