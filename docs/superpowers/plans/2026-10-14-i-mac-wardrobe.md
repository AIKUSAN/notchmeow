# I-mac: The Wardrobe in the macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sub-project I on the Mac. The user dresses the big cats: Settings → Cat → Wardrobe (a live preview, a coat picker that stores nothing, 18 tiles), a Wardrobe submenu in a new right-click menu on the island cat and in the desktop cat's menu, and **⌃⌥G**. One of 16 outfits, **None**, or **Auto**, which follows the calendar (new year, Christmas, Halloween, Easter, summer) and looks again at the next local midnight with one one-shot timer. Every cat in a big-cat role wears it at every size, the compact notch's Ø20 cat included (the island's main cat, both cats of Two cats mode, each agent's big cat, the cat that catches a file, the desktop cat and the launch greeting's cat once it settles); kittens and the small cats stay bare, whatever their diameter. It costs nothing while hidden and nothing measurable while shown.

**Architecture:** Every rule is a pure Foundation file tested against I-0's fixture by a `swiftc` program, as A, B and H did it: `Wardrobe` (the 18 frozen IDs, `idOf`, who wears it, the ⌃⌥G cycle), `WardrobeSettings` (`cat.outfit`, `WardrobeSettings.clean`), `WardrobeAuto` (Easter, the five dated rules, `resolve`, the menus' items, and `WardrobeClock`: the resolved outfit and the one timer) and `CatOutfit` (a port of `outfitAnchors`, `outfitGeometry` and `outfitDigest`: plain shapes in head-local px with colour roles). `CatOutfitDraw` paints the shapes into the head's frame at the three slots `CatRenderer` calls (`behind` after the ears, `neck` after the collar, `top` after `neck`, always before the whiskers); the colours are `Theme.Outfits`. **The role decides, never the diameter:** `CatDrawOptions.outfit` is set only by the five big-cat views (from `engine.cfg.outfit`, which `WardrobeClock` keeps), and the renderer checks `Wardrobe.worn(role)` before it builds any geometry. `CatSettingsStore` holds the stored choice beside the Cat, Display and Desktop settings; Settings, both menus and the shortcut all end in `store.setOutfit`. Nothing is checked by launching the app: the pictures come from `render-cats.sh --wardrobe` (and `--outfit <id>` on the island, desktop, greeting and bench sheets) and `render-cat-settings.sh`, and the wiring from source pins.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit (`NSMenu`, `NSEvent` monitors, a wall-clock `DispatchQueue` one-shot), Combine, CoreGraphics, Carbon hot keys (existing), XcodeGen, `swiftc` test programs, Bash.

**Spec:** `docs/superpowers/specs/2026-10-14-wardrobe-design.md` (all of it; "Rounds" gives the order and the three owner checkpoints). The contract is I-0's, merged as `d050fc2` (the spec's "bow in the top slot" fix is `619b407`): the wardrobe section of `design/prototype/cat-core.js`, `tests/fixtures/cat/wardrobe-cases.json` and `docs/CAT-CONTRACT.md`, "The wardrobe (I-0)". The visual source of truth is the Wardrobe panel of `design/prototype/notchmeow.html`. The format and the Mac code's conventions are B-mac's and H-mac's (`docs/superpowers/plans/2026-10-08-b-mac-display-kittens.md`, `2026-10-12-h-mac-desktop-cat.md`).

**Base:** a new branch `i/mac-wardrobe` in a git worktree, from `notchmeow/rebrand` at **`619b407` or later** (`git merge-base --is-ancestor 619b407 HEAD` must succeed). I-0 is merged and this plan applies nothing of it. This plan never edits `design/prototype/cat-core.js`, a fixture of `tests/fixtures/cat/`, `shared/theme.json`, a generated theme file or anything under `windows/`. It touches no file that Windows and Linux build from.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and from I-0's contract; a line marked "(plan decision)" is a choice this plan makes where the spec is silent, and each is listed again under "Open questions for the owner".

- **Swift 6, SwiftUI and AppKit, no third-party dependencies.** Outfits are drawn in code (`CGContext`), no images. The pure files (`Wardrobe`, `WardrobeSettings`, `WardrobeAuto`, `CatOutfit`) stay Foundation-only and carry no build condition except the Debug-only `WardrobeDev` names in `WardrobeAuto.swift`; `CatOutfitDraw` knows only CoreGraphics and the cat's drawing files.
- **16 outfits, 18 selection IDs, frozen and in this order** (the grid's, the menus' and the shortcut's cycle): `auto`, `none`, `partyhat`, `santahat`, `witchhat`, `bunnyears`, `sunglasses`, `beanie`, `bow`, `scarf`, `roundglasses`, `crown`, `bell`, `bandana`, `fishclip`, `flower`, `shrimpclip`, `blossomclip`. The stored key is `cat.outfit` (a string), default `auto`; an unknown, mis-cased, padded or non-string stored value is `auto`. The shortcut's action ID **`wardrobe`** is frozen like `desktop`; its keys follow the others (`shortcut.wardrobe.keyCode`, `.flags`, `.enabled`).
- **Who wears it: the role, never the diameter.** `big` wears it at every size (Ø20 in the 32-point notch strip, Ø18 in the 24-point strip of a screen without a notch); `small` (the pills' cats, the mini row, the grid) and `kitten` never do. One outfit at a time, for every big cat: it is global, not per cat, and `AppState.cast` does not change.
- **Draw order and slots:** behind pass `... ears, outfit.behind`; front pass `foldEars, collar, outfit.neck, outfit.top, whiskers, badge, particles, balls`. `CatGeometry.passes` stays as A-0 pinned it. The collar is drawn first and never changed; the whiskers and the badge stay in front of every outfit. A coat is never recoloured: the outfit's thin edge is light on a dark head and dark on a light one (`CatOutfit.edge`).
- **Floors and fit:** `CatOutfit.Min` is in **device** pixels (`height` 6, `line` 1, `rim` 2, `ball` 3, `span` 6). In the compact notch the hats and the bunny ears get the room the ears get (`room`), are shortened to it and never below the floor; a detail marked `fine` (a glint, a star, a rib) is left out below Ø28.
- **Auto:** the local calendar date on the northern calendar, the first matching rule wins: Dec 31 to Jan 2 `partyhat`; Dec 1 to Dec 26 `santahat`; Oct 1 to Nov 1 `witchhat`; Good Friday to Easter Monday (Easter minus 2 days to plus 1, Gregorian, Meeus/Jones/Butcher, counted on date numbers, never on clock times) `bunnyears`; Jun 21 to Aug 31 `sunglasses`; anything else none. The stored value stays `auto`; the clock resolves it at launch, when the choice changes and at the next local midnight with **one** one-shot timer that exists only while the choice is `auto`. It uses the wall clock (`wallDeadline`), so a Mac that slept through midnight fires it on waking. **No polling, no repeating timer, no second timer.**
- **0 % CPU when hidden.** Outfits are part of the existing frame draw: no layer, no window, no timer of their own. `desktopFps` is unchanged. A bare cat (small, kitten, `none`, a fade of 0) builds no geometry. The bench (`render-cats.sh --bench` and `--bench-desktop`, with `--outfit`) proves the cost.
- **Never restyle a shipping view.** The island, the pills, Settings' other groups, the Main cat's and the Display preview's cats look exactly as they ship. The new things: a cat wearing something, Settings' new Wardrobe group (after Desktop, in the existing style), a right-click menu on the island cat with **only Wardrobe in it**, and a Wardrobe submenu in the desktop cat's menu. The right-click monitor reads no left-button event: a click, a drag, a slap and the drag-out of the cat are as they were.
- **Frozen contract values and keys.** Cat IDs, pill IDs, the display mode IDs, the size IDs, the shortcut action IDs (`desktop` and now `wardrobe`), the 18 outfit IDs and every existing UserDefaults key never change or get reused. `cat.outfit` is new. Never rename a pill ID or a contract string (`nm-hook`, `nm.sock`, `nm_kind`, `nm_agent`, bundle identifiers).
- **Stored values never throw and never skip the clean-up.** Every outfit read from UserDefaults goes through `WardrobeSettings.clean` (I-0's `cleanWardrobeSettings`, a clean-up of its own: `CatSettings.clean`, `CatDisplaySettings.clean`, `DesktopCatSettings.clean` and their fixtures are as they were), and a value is written only after it was cleaned.
- **Fixtures decide.** Numbers compare within **1e-9**; strings, booleans, nulls and shapes compare exactly. `cat-core.js` is the tie-breaker; this plan never edits it or a fixture. The fixture holds a few inputs a Swift `Int` cannot take (2024.5, "2024", null for a year or a date): the tests check those as "cannot be asked", which the contract answers with null (Easter) and none (Auto).
- **The wardrobe ships in Debug, Release and App Store builds, ⌃⌥G included** (the App Store build has no front-window or terminal shortcut, and does have the desktop cat's and this one). `scripts/check-app-binary.sh` finds the marker `NM_WARDROBE_OUTFITS` in all three (19 bytes: Swift keeps a shorter string inside the code, where `strings` cannot see it). The Debug panel's Wardrobe section (marker `NM_CAT_DEV_WARDROBE`) and the Debug date override are compiled out of Release and App Store.
- **Never block Claude Code, no telemetry, no network, no secrets.** Nothing here is on the hook path, sends or receives anything, or touches a key.
- **Never edit `NotchBuddy.xcodeproj` by hand.** A task that adds a Swift file to the app runs `cd NotchBuddy && xcodegen` before it builds and commits the regenerated `project.pbxproj`. A new Swift file that a test or render script compiles is added to that script's list (the edits below do it).
- **No `UserDefaults` suite, and no `UserDefaults.standard` write, in any test or script.** A test builds `CatSettingsStore(backing:config:)` on a `MemoryBacking`. The tests never register a hot key except `HotKeyCenterTests`, which already does, under combinations nobody uses.
- **Nothing of Coucou's comes back.** No upstream wardrobe code, art, name, key, outfit list as drawn, pumpkin or sound is read, ported or reused; the names Coucou and Mochi appear in no new code (`mocha` is a coat). No sound is added for changing outfit. `scripts/check-no-leftovers.sh` stays green.
- **Models and commits** (CLAUDE.md, "Working with AI agents", 2026-10-12): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local only, never pushed, lists only the files its task names, and ends with the `Co-Authored-By` line of the model that did the task: `Claude Haiku 5.5` for `nm-implementer-light` and `nm-implementer`, `Claude Sonnet 5.5` for `nm-implementer-deep`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app, and never open the installed one. A Debug, Release or App Store **build** in the worktree is fine and is only built; the scripts that draw a PNG (`render-cats.sh`, `render-cat-settings.sh`, `render-cat-panel.sh`, `gen-icons.sh <outDir>`) are not the app and may run. No task sends a hook event to the app's socket.
  2. Install nothing. No network calls, no downloads (`npx --no-install` only; this plan needs neither `npm` nor `cargo`).
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; put scratch files under `${TMPDIR:-/tmp}` with a unique folder name. (The test scripts clean their own `mktemp` folders with `rm -rf` in a `trap`, as every `scripts/test-*.sh` does: that is the repo's convention, not a command an agent runs.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or to `~/Library` in a test or script; tests write no log outside a temp `NM_LOG_DIR`.
  5. Never edit `design/prototype/cat-core.js`, a fixture of `tests/fixtures/cat/`, `shared/theme.json`, a generated theme file or anything under `windows/`.
  6. Never push. Commit only in a task's commit step, after checking the worktree and the branch.
  7. Haiku 5.5 for every task except Tasks 11 and 12 (Sonnet 5.5, `nm-implementer-deep`); never Opus or Fable.
  8. Never rename a frozen ID, and write no `Coucou` or `Mochi` name anywhere in code, comments, scripts or tests.
  9. If a command is denied by a permission prompt, or a find text of an Edit occurs zero or two times, stop and report it. Do not look for a workaround.

## Review Focus

The spec says what the wardrobe does. It is silent on these inputs and conditions, and each would bite a person first, most likely first. Each line names the test that pins it.

1. **The compact notch's Ø20 cat in a 32-point strip.** A witch hat or a pair of bunny ears that leaves the strip is cut off at the top of the screen, a hat shortened to nothing disappears, and a pompom, a bell or a rim thinner than a device pixel is mush. Expected: every outfit on every coat stays inside the strip, above its floors, at Ø20 and Ø18, and a hat with no room is held at the floor's height, not hidden. Tests: Task 3 ("the compact notch": 256 pairs at each size) and Task 4 (the same 256 pairs drawn, none above the strip).
2. **Auto on the wrong day, and after a sleep.** Easter in a March year, Good Friday across a month end, 31 December into January, a day that is 23 or 25 hours long, a Mac that sleeps through midnight, a timer that fires a hair early, a stored choice that is not `auto` (no timer at all). Expected: the fixture's boundaries and Easter windows, the date numbers never shifted by daylight saving, a late fire recomputed from the date then, an early fire waiting for the rest, one timer and never two. Tests: Task 1 (the 34 dates, the 12 Easter windows, `secondsToMidnight` across both daylight-saving changes, the clock's early, late and cancelled timers) and Task 6's pins (wall clock, one `asyncAfter`).
3. **A small cat or a kitten in a hat.** Twelve pills' cats, the mini row, the grid and every kitten are drawn by the same renderer at diameters that overlap the big cat's (a kitten at Ø40, a pill's cat at Ø28). Expected: they stay bare whatever their diameter, and a made-up role is bare. Tests: Task 1 (the 16 roles), Task 4 ("who wears it": a Ø66 small cat is pixel-identical to the bare one) and Task 5's pins (only the five big-cat views ask).
4. **The island cat's new right-click menu.** The island has no right-click menu today: a press that opens one must not slap the cat, start a drag-out, change the click that opens the island or fold the island under the menu, and in Two cats mode the overlap of the two cats must not decide the menu by accident. Expected: the monitor reads only the right button, uses the big cats' hit test (both cats, the nearer centre wins), keeps the island open while the menu is up and shows nothing for a right-click anywhere else. Tests: Task 11's pins (one right-click monitor, the left-button monitors unchanged) and the owner's real-build check.
5. **A hand-edited or half-written store.** `cat.outfit` as a number, a list, data, `Bow`, ` bow ` or an outfit that was renamed in a later version. Expected: `auto`, never a throw, Settings still opens, loading writes nothing. Tests: Task 1 (the 38 stored values, the 11 blocks, "a store that is wrong in every way") and Task 2.

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/Wardrobe.swift` | New. `Wardrobe`: the 18 IDs, names, groups, the 16 drawn, `idOf`, `worn`, `next(after:)`. Foundation only. |
| `NotchBuddy/Sources/App/WardrobeSettings.swift` | New. `WardrobeSettings` (the clean-up, the edit, the key `cat.outfit`, load and save). Foundation only. |
| `NotchBuddy/Sources/App/WardrobeAuto.swift` | New. `easterOf`, `autoOutfit`, `resolve`, the date and the seconds to midnight, `parseDay` and `nextDay`; `WardrobeMenu.items`; `WardrobeClock` (the resolved outfit and the one timer); the Debug-only `WardrobeDev` names. Foundation only. |
| `NotchBuddy/Sources/App/CatOutfit.swift` | New. The port of `outfitEdge`, `outfitRoom`, `outfitAnchors`, `outfitGeometry` and `outfitDigest`. Foundation only (uses `CatGeometry`). |
| `NotchBuddy/Sources/App/CatOutfitDraw.swift` | New. `CatOutfitDraw`: the shapes' painter, the colour roles, the marker `NM_WARDROBE_OUTFITS`, `CatDressed`. |
| `NotchBuddy/Sources/App/CatLook.swift`, `CatRenderer.swift`, `CatEngine.swift` | `CatOutfitPaint` and `CatDrawOptions.outfit`; the three slots and the ear scale as drawn; `CatConfig.outfit`. |
| `NotchBuddy/Sources/App/CatSettingsStore.swift` | The store holds `wardrobe` and its setters (`setOutfit`, `nextOutfit`). |
| `NotchBuddy/Sources/App/BotCanvasView.swift`, `PairCatViews.swift`, `UploadCanvasView.swift`, `DesktopCatDraw.swift`, `CatGreetingRenderer.swift`, `CatGreeting.swift` | The five big-cat views dress their cat; the greeting's fade (`outfitFade`). |
| `NotchBuddy/Sources/App/WardrobeClock+App.swift`, `AppDelegate.swift` | New, and one line. The app's clock (real date, the wall-clock one-shot, the store and `CatConfig` links, the Debug override) attached first thing in `setupIsland`. |
| `NotchBuddy/Sources/App/WardrobePreviewViews.swift`, `WardrobeSettingsView.swift`, `CatSettingsView.swift`, `CatSettingsSection.swift` | New, and small edits. The still tile and the live preview; Settings → Cat → Wardrobe after Desktop; the app hands the clock's date. |
| `NotchBuddy/Sources/App/WardrobeMenuApp.swift`, `DesktopCatInput.swift`, `DesktopCatController.swift`, `IslandWindowController.swift` | New, and edits. The `NSMenu` of the island cat's right-click menu; the pure Wardrobe submenu of the desktop cat's menu; the right-click monitor, the both-cats hit test and the menu-open flag. |
| `NotchBuddy/Sources/App/ShortcutLogic.swift` | The `wardrobe` action, appended last (Carbon identifies a hot key by its index in `allCases`), ⌃⌥G, off by default. |
| `NotchBuddy/Sources/App/WardrobeDevPanel.swift`, `CatDevPanel.swift` | New, and one line. The Wardrobe section of the Debug-only "Cats (Debug)…" panel (marker `NM_CAT_DEV_WARDROBE`): compiled out of Release and App Store. |
| `tests/WardrobeSettingsTests.swift`, `WardrobeAutoTests.swift`, `WardrobeGeometryTests.swift`, `WardrobeDrawTests.swift`, `WardrobeWiringTests.swift` | New. One program each (the wiring program is the source pins of the app files no test program can compile). |
| `tests/CatSettingsStoreTests.swift`, `CatGreetingTests.swift`, `DesktopCatInputTests.swift`, `ShortcutTests.swift`, `HotKeyCenterTests.swift` | New sections: the store's wardrobe, the greeting's fade, the Wardrobe submenu, the tenth action. |
| `scripts/test-wardrobe-{settings,auto,geometry,draw,wiring}.sh` | New. One script for each new test program. |
| `scripts/render-cats-wardrobe.swift`, `render-cats.swift`, `render-cats-desktop.swift`, `render-cats.sh`, `render-cat-settings.{swift,sh}`, `render-cat-panel.sh`, `gen-icons.sh`, `test-cat-renderer.sh`, `test-cat-desktop-devpanel.sh`, `test-cat-desktop-input.sh`, `test-cat-settings-store.sh`, `check-app-binary.sh` | `--wardrobe [--part …]` and `--outfit <id>`; the compile lists gain the new files; the wardrobe's marker is checked in all three builds and the Debug panel's is proved absent from Release and App Store. |
| `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `README.md`, `docs/SPEC.md` | One CI step for each new script; the Mac lines; the roadmap row; the French spec: "La garde-robe". |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | Regenerated by `xcodegen`, never by hand. |

**Order of tasks** (the spec's step numbers in brackets). Tasks 1 and 2 are the settings and clean-up port with the store [1]; Task 3 the pure geometry port [2]; Task 4 the drawing at the three slots and the sheets [3]; Task 5 dresses the big cats; Task 6 is Auto's clock and its one-shot [4]; Task 7 the Wardrobe section [5]; Task 8 is **owner checkpoint 1**; Task 9 adds the bench and the Two cats and per-agent sheets and Task 10 is **owner checkpoint 2**; Task 11 the right-click menus [6]; Task 12 ⌃⌥G [7]; Task 13 the Debug panel's controls; Task 14 docs, CI and the final checks [8]; Task 15 the whole-branch review; Task 16 **owner checkpoint 3**. **Two things moved against the spec's list.** (1) The Wardrobe section (the spec's step 5) comes before the menus so that checkpoint 1 can show it, which the spec asks for; the menus and ⌃⌥G follow checkpoint 2. (2) **The pure ports come first and the app's classes are thin carriers of tested rules**, as B-mac and H-mac did, so each task has code a reviewer can reject on its own.

## Tasks and agents

CLAUDE.md: the lightest model that fits. **Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** The code is given in full in every task and its tests prove it, so most tasks are Haiku. **Tasks 11 and 12 are `nm-implementer-deep` (Sonnet 5.5, high): trigger 1**, platform APIs the task must get right rather than copy (an `NSMenu` popped up from a local event monitor on a non-activating, click-through island panel without disturbing its hover timers, a menu on the desktop cat's never-key panel, a Carbon hot key's index in `allCases`). If a Haiku task's expected output differs and the cause is not obvious, or it fails twice, hand that task to `nm-implementer-deep` (trigger 2) and say so in the ledger. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Effort: **medium** for light tasks (code given in full), **high** for `nm-implementer` and for every review.

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | The IDs, the clean-up, Auto and its clock (step 1) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 2 | The store holds the wardrobe (step 1) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 3 | The geometry in Swift: anchors, 16 outfits, digests (step 2) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 4 | The drawing at the three slots, and the sheets (step 3) | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 5 | The big cats wear it: five views, the greeting's fade | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 6 | Auto's clock reaches the cats: one wall-clock timer (step 4) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 7 | Settings → Cat → Wardrobe (step 5) | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 8 | **Owner checkpoint 1:** the sheets against the prototype, and the Wardrobe section | the main session and the owner | none |
| 9 | The bench with an outfit on, and the Two cats and per-agent sheets | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 10 | **Owner checkpoint 2:** the bench numbers and the island sheets | the main session and the owner | none |
| 11 | The right-click menus: the island cat's (new) and the desktop cat's (step 6) | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 12 | ⌃⌥G, the next outfit (step 7) | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 13 | The Debug panel's wardrobe controls and the date override | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 14 | Docs, CI and the final checks (step 8) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 15 | The whole branch: cross-task contracts, privacy and security rules, the Review Focus | `nm-reviewer-deep`, Sonnet 5.5, high | none |
| 16 | **Owner checkpoint 3:** sign-off, then the owner's real-build checks | the main session and the owner | none |

## Execution

One worktree chat session runs the whole plan: branch `i/mac-wardrobe`, model **Sonnet 5.5 at high effort** (trigger 1: AppKit menus on a non-activating panel and a Carbon hot key; and trigger 5, an app plan with several cross-task interfaces; `ARCHITECT.md`). Nothing is pushed. It runs in a worktree of its own, in parallel with the Windows and Linux twin (I-tauri), which touches nothing under `NotchBuddy/`.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c i/mac-wardrobe notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-14-i-mac-wardrobe.md`: only its Steps 1 to 3 (the base checks: `git merge-base --is-ancestor 619b407 HEAD` must succeed, I-0 is merged and nothing of it is applied). Read `CLAUDE.md`, `ARCHITECT.md`, that plan, `docs/superpowers/specs/2026-10-14-wardrobe-design.md` and `docs/CAT-CONTRACT.md` ("The wardrobe (I-0)"). If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-14-i-mac-wardrobe.md` with `superpowers:subagent-driven-development`, task by task, on branch `i/mac-wardrobe`. Dispatch each task to the agent the plan's "Tasks and agents" table names (`nm-implementer` and `nm-implementer-light` on Haiku 5.5; `nm-implementer-deep` on Sonnet 5.5 for the menu and hot-key tasks, 11 and 12, and for a task Haiku failed twice), then to `nm-reviewer`; fix what the review finds before the next task. After Task 14 dispatch `nm-reviewer-deep` over the whole branch. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `i/mac-wardrobe`. If either is wrong, stop and report. Commit with `git commit -F <file>`, never `-m`, with the trailer of the model that did the task. Never push.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-i-mac-wardrobe/progress.md` (the SDD plugin's scripts are refused by auto mode, so you write it by hand): one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files, never `..` and never a diff against a moving working tree.
> - **Every ```` ```bash ```` block in the plan passes `bash -n` before it is run** (a find or replacement text of a script is marked `text`: it is a fragment), and a script you write passes it too.
> - **Find texts.** If an Edit's find text occurs zero or two times, stop and report: the tree is not what the plan expects.
> - **Servers and processes.** Stop a server only by the PID you saved when you started it. **Never launch, quit or replace a NotchMeow app, and never touch the installed one:** the builds are builds (Debug with `CODE_SIGNING_ALLOWED=NO`), the PNGs come from `render-cats.sh`, `render-cat-settings.sh` and `render-cat-panel.sh`. Install and download nothing.
> - **Stop and report on any refusal** (a denied command, a permission prompt): do not look for a workaround.
> - **Pings.** At each owner checkpoint, at the end, and whenever you stop (a refusal, a failed check, a question), send your report with `SendMessage` addressed to the main session's ListAgents name `NotchMeow — fork research & cat design`, as well as writing it in your own chat.
> - **Owner checkpoints.** Run Tasks 1 to 7, then stop and report for owner checkpoint 1 (Task 8: copy the pictures into `.claude/checkpoints/i-mac/` of the worktree, which is gitignored, and say what to look for). After the owner's reply run Task 9, then stop again for checkpoint 2 (Task 10). Then run Tasks 11 to 14, dispatch `nm-reviewer-deep` over the whole branch, fix what it finds, and stop for checkpoint 3 (Task 16).
>
> Report: the commits; the output of every `bash scripts/test-wardrobe-*.sh`, `bash scripts/test-cat-*.sh`, `bash scripts/test-shortcuts.sh`, `bash scripts/test-hotkeys.sh`, `bash scripts/test-theme.sh` and `bash scripts/check-no-leftovers.sh`; the Debug, Release and App Store build lines and the three `check-app-binary.sh` lines; the bench lines; the paths of the PNGs of each checkpoint; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see. A test program's failing run prints `✗` lines, and its last line is `N test(s) failed.`; a passing one ends `All tests passed.` A compile that cannot find a file prints `error opening input file`, and one that finds a missing name prints `cannot find … in scope` (a red run before the code exists). A new script is made executable with the `chmod +x` line that follows its block.

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-*.sh`; none needs Xcode. A build is `cd NotchBuddy && xcodegen && cd ..` and then `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`; the Release build is `-configuration Release -derivedDataPath NotchBuddy/build/release` and the App Store target `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, each with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (git ignores `NotchBuddy/build/`). Add `2>&1 | tail -3` to read the last lines. **Never start a built app.** The scripts that draw a PNG write wherever `--out` says; this plan writes them under `${TMPDIR:-/tmp}/i-mac-1` and so on, and the checkpoints copy the ones the owner sees to `.claude/checkpoints/i-mac/` of the worktree (never committed). The bench wants an optimised build: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench`.

**Looking at an image.** Several steps end with "look at it". The agent that ran the step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank or broken image is a failed step. The owner's look is the checkpoint.

**Stages of one file.** `render-cats.swift`, `render-cats.sh`, `render-cat-settings.sh`, `render-cat-panel.sh`, `render-cats-desktop.swift`, `check-app-binary.sh`, `IslandWindowController.swift` and `WardrobeWiringTests.swift` are edited by several tasks. Each later task's **Edit** blocks are written against the file exactly as the earlier tasks left it; apply them in the order the plan gives them. `WardrobeWiringTests.swift` grows by sections, each added above the line `// @@WIRING-SECTIONS`.

**Dry-run clones.** A throwaway clone made with `git clone --local --shared` has no `windows/node_modules` and no Docker; nothing here needs either. Commit steps are not run in a clone.

---
## Tasks

### Task 0: Worktree and baseline

No code and no commit: this makes sure the base is the one the plan expects. Its first three steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c i/mac-wardrobe notchmeow/rebrand
git merge-base --is-ancestor 619b407 HEAD && echo "I-0 (619b407) is in the base"
git log --oneline -6                          # I-0's merge and the spec's bow fix are in the history
```

Expected: `I-0 (619b407) is in the base`. If that line is missing, the worktree was cut from an older base: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check that I-0's files are there and the contract is green**

Run: `for f in design/prototype/cat-core.js tests/fixtures/cat/wardrobe-cases.json docs/CAT-CONTRACT.md; do test -f $f && echo "ok $f"; done; grep -c "function outfitGeometry" design/prototype/cat-core.js`
Expected: three `ok …` lines and `1`.

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|fixture files match|identical bytes"`
Expected: `# tests 319`, `# pass 319`, `# fail 0`, `✓ 16 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 5f9051c 2>&1 | tail -1`
Expected: `✓ fixtures changed only by addition since 5f9051c`.

- [ ] **Step 3: Check that the Mac cat tests are green, read the frame times, and build**

```bash
for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done
```

Expected: thirty-four lines: `scripts/test-cat-contract.sh` ends `✓ two generator runs write identical bytes` and the other thirty-three end `All tests passed.`

Run: `bash scripts/test-shortcuts.sh 2>&1 | tail -1; bash scripts/test-hotkeys.sh 2>&1 | tail -1; bash scripts/test-theme.sh 2>&1 | tail -1`
Expected: `Shortcuts: 508 cases passed`, `HotKeyCenter: 19 cases passed` and `✓ 3 theme files match shared/theme.json`. Task 12 changes the first two programs, so write the counts down.

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench 2>&1 | tail -1; RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench-desktop 2>&1 | grep "idle, no"`
Expected: `12 small cats (30 fps) + the big one (60 fps), update and draw, CPU time: avg 1.9x ms, …` and three `Ø48/Ø64/Ø96 idle, no kittens` lines at about 0.3, 0.4 and 0.65 % of a core (the dry run read 1.93 ms, 0.29, 0.39 and 0.64 %; they move by 0.1 to 0.2 ms and a few hundredths of a percent with the machine's load). Task 9 reads them again with an outfit on.

```bash
cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `Created project at …` and the last lines end with `** BUILD SUCCEEDED **` (a few minutes on a cold build). The build only builds: do not open the app.

- [ ] **Step 4: Read the base once**

Read, without changing: `NotchBuddy/Sources/App/CatRenderer.swift` (`draw`, `drawBehind`, `drawFront`), `CatGeometry.swift` (`layout`, `collarGeometry`, `earFit`), `CatLook.swift` (`CatDrawOptions`), `CatSettingsStore.swift`, `DesktopCatSettings.swift` (the pattern `WardrobeSettings` follows), `CatSleep.swift` (the pattern `WardrobeClock` follows), `BotCanvasView.swift`, `PairCatViews.swift`, `DesktopCatDraw.swift`, `IslandWindowController.swift` (`startKeyMonitor`, `pollFrame`, `isBotHit`, `handleHotKey`), `DesktopCatController.swift` (`showMenu`), `ShortcutLogic.swift`, `CatSettingsView.swift`, the Wardrobe panel of `design/prototype/notchmeow.html`, and I-0's section of `docs/CAT-CONTRACT.md`. Nothing to report.


### Task 1: The IDs, the clean-up, Auto and its clock (step 1)

Everything here is Foundation-only and replays `wardrobe-cases.json`: the 18 frozen IDs, `idOf`, `WardrobeSettings.clean`, who wears it, the ⌃⌥G cycle, the key `cat.outfit`, the menus' items, Easter, the five dated rules, `resolve`, the date and the seconds to midnight, and the clock with its one timer. `WardrobeMenu.items` is a pure list that both right-click menus turn into an `NSMenu`.

**Files:** create `Wardrobe.swift`, `WardrobeSettings.swift`, `WardrobeAuto.swift`, `tests/WardrobeSettingsTests.swift`, `tests/WardrobeAutoTests.swift` and their two scripts.

**Interfaces.** Produces: `Wardrobe.ids`, `.names`, `.groups`, `.drawn`, `.defaultOutfit`, `.idOf(_ Any?) -> String`, `.worn(_ Any?)`, `.worn(Role)`, `.next(after:)`, `.name(_)`; `Wardrobe.Day`, `.easterOf(_ Int)`, `.autoOutfit(y,m,d)` and `.autoOutfit(Day)`, `.resolve(_ Any?, …)`, `.autoLabel(today:)`, `.parseDay(_)`, `.nextDay(_)`, `.today(now:calendar:)`, `.secondsToMidnight(now:calendar:)`; `WardrobeSettings` (`clean`, `json`, `withOutfit`, `Key.outfit`, `load(from:)`, `save(to:replacing:)`); `WardrobeMenu.items(selected:autoToday:) -> [Item]`; `WardrobeClock` (`start()`, `setChoice(_)`, `dateChanged()`, `resolved`, `choice`, `isArmed`, `onChange`); Debug-only `WardrobeDev.dateNote`, `.midnightNote`.

- [ ] **Step 1: Write the tests and their scripts**

**Create `tests/WardrobeSettingsTests.swift`**

```swift
import Foundation

@main
enum WardrobeSettingsTests {
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    @MainActor static func main() {
        let fx = CT.fixture("wardrobe-cases.json")

        CT.section("the frozen values: the 18 IDs in order, their names, the grid's rows, the 16 that are drawn, the default and the roles")
        CT.check("the IDs, in order", Wardrobe.ids, fx["ids"] as! [String])
        CT.check("the names", Wardrobe.names, fx["names"] as! [String: String])
        func line(_ id: String, _ name: String, _ ids: [String]) -> String { id + "|" + name + "|" + ids.joined(separator: ",") }
        CT.check("the grid's rows", Wardrobe.groups.map { line($0.id, $0.name, $0.ids) }, rows(fx["groups"]).map { line($0["id"] as! String, $0["name"] as! String, $0["ids"] as! [String]) })
        CT.check("the 16 that are drawn", Wardrobe.drawn, fx["drawn"] as! [String])
        CT.check("the default", Wardrobe.defaultOutfit, fx["defaultOutfit"] as! String)
        CT.check("the roles", Wardrobe.roles, fx["roles"] as! [String])
        CT.check("the groups hold each ID once, in the IDs' order", Wardrobe.groups.flatMap(\.ids), Wardrobe.ids)

        CT.section("idOf: \(rows(fx["clean"]).count) stored values")
        var diffs: [String] = []
        for c in rows(fx["clean"]) where Wardrobe.idOf(c["input"]) != c["out"] as! String { diffs.append("\(c["name"] as! String): \(Wardrobe.idOf(c["input"]))") }
        CT.checkRows("every stored value is as the fixture says (an ID exactly as written is kept, everything else is auto)", diffs)

        CT.section("WardrobeSettings.clean: \(rows(fx["settings"]).count) stored blocks")
        diffs = []
        for c in rows(fx["settings"]) {
            let d = CT.diffs(WardrobeSettings.clean(c["input"]).json, c["out"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every block is as the fixture says, and only the `outfit` key is read", diffs)

        CT.section("who wears it: \(rows(fx["worn"]).count) roles")
        diffs = []
        for c in rows(fx["worn"]) where Wardrobe.worn(c["role"]) != c["out"] as! Bool { diffs.append("\(String(describing: c["role"])): \(Wardrobe.worn(c["role"]))") }
        CT.checkRows("only the text big is worn, whatever else it is called", diffs)
        CT.check("the app's three roles", [Wardrobe.worn(Wardrobe.Role.big), Wardrobe.worn(Wardrobe.Role.small), Wardrobe.worn(Wardrobe.Role.kitten)], [true, false, false])

        CT.section("the ⌃⌥G cycle: the grid's order, Auto and None included")
        var walk = ["auto"]
        for _ in 0..<17 { walk.append(Wardrobe.next(after: walk.last!)) }
        CT.check("eighteen presses visit every ID once, in the grid's order", walk, Wardrobe.ids)
        CT.check("and the next one wraps from blossomclip to auto", Wardrobe.next(after: "blossomclip"), "auto")
        CT.check("Auto goes to None", Wardrobe.next(after: "auto"), "none")
        CT.check("an ID that is not one counts as Auto, so the next is None", Wardrobe.next(after: "fancyhat"), "none")

        CT.section("the UserDefaults key, through a dictionary store")
        let store = MemoryBacking()
        CT.check("an empty store loads auto", WardrobeSettings.load(from: store), WardrobeSettings())
        store.values = ["cat.outfit": "crown", "cat.character": "momo"]
        let loaded = WardrobeSettings.load(from: store)
        CT.check("what is stored is loaded (and the other cat keys are not read)", loaded, WardrobeSettings(outfit: "crown"))
        let fresh = MemoryBacking()
        loaded.save(to: fresh)
        CT.check("the one key it writes", fresh.writes, ["cat.outfit"])
        CT.check("and loads back as it was", WardrobeSettings.load(from: fresh), loaded)
        let before = fresh.writes.count
        loaded.save(to: fresh, replacing: loaded)
        CT.check("nothing that did not change is written", fresh.writes.count, before)
        loaded.withOutfit("bow").save(to: fresh, replacing: loaded)
        CT.check("a change writes the key again", Array(fresh.writes[before...]), ["cat.outfit"])
        CT.check("an edit with a made-up name is auto", loaded.withOutfit("Crown"), WardrobeSettings(outfit: "auto"))

        CT.section("a store that is wrong in every way still loads")
        let wild = MemoryBacking()
        for (label, value) in [("a number", 7 as Any), ("a list", ["bow"] as Any), ("data", Data("bow".utf8) as Any), ("a boolean", true as Any), ("a capital", "Bow" as Any), ("padding", " bow " as Any)] {
            wild.values = ["cat.outfit": value]
            CT.check("\(label) is auto", WardrobeSettings.load(from: wild), WardrobeSettings())
        }

        CT.section("the menus' items")
        let items = WardrobeMenu.items(selected: "scarf", autoToday: "santahat")
        let choices = items.compactMap { i -> (String, String, Bool)? in if case .choice(let id, let t, let c) = i { return (id, t, c) } else { return nil } }
        CT.check("the 18 choices in the grid's order", choices.map(\.0), Wardrobe.ids)
        CT.check("one is ticked: the stored one", choices.filter(\.2).map(\.0), ["scarf"])
        CT.check("Auto's label shows today's result", choices[0].1, "Auto: today, Santa hat")
        CT.check("and None's is its name", choices[1].1, "None")
        CT.check("a day with nothing to wear says none", WardrobeMenu.items(selected: "auto", autoToday: "none").compactMap { i -> String? in if case .choice("auto", let t, _) = i { return t } else { return nil } }, ["Auto: today, none"])
        CT.check("the headings are the four groups', and the groups are set apart", items.compactMap { i -> String? in if case .heading(let h) = i { return h } else { return nil } }, ["Seasonal", "Everyday", "Cat extras", "The cats' own"])
        CT.check("four separators", items.filter { $0 == .separator }.count, 4)
        CT.check("a stored value that is not an ID ticks Auto", WardrobeMenu.items(selected: "nope", autoToday: "none").compactMap { i -> String? in if case .choice(let id, _, true) = i { return id } else { return nil } }, ["auto"])
        CT.finish()
    }
}
```

**Create `scripts/test-wardrobe-settings.sh`**

```bash
#!/usr/bin/env bash
# Wardrobe settings (sub-project I): the 18 frozen IDs and their order, the clean-up of a stored outfit (outfitIdOf, cleanWardrobeSettings), who wears it, the ⌃⌥G cycle, the one
# UserDefaults key `cat.outfit` and the menus' items, against wardrobe-cases.json, and what the fixture cannot write (a number, a list, data and padding in the store).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/Wardrobe.swift $APP/WardrobeSettings.swift $APP/WardrobeAuto.swift $APP/CatSettings.swift $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/WardrobeSettingsTests.swift \
    -o "$TEST_DIR/wardrobe-settings-tests"
"$TEST_DIR/wardrobe-settings-tests"
```

**Create `tests/WardrobeAutoTests.swift`**

```swift
import Foundation

@main
enum WardrobeAutoTests {
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func int(_ x: Any?) -> Int { (x as! NSNumber).intValue }
    /// An integer the way the contract's `Number.isInteger` means it: a whole number, and not text, a boolean, a fraction or null. The fixture holds a few such inputs (2024.5,
    /// "2024", null); the app's functions take `Int`, so those rows are checked as "cannot be asked", which the contract answers with null (Easter) and none (Auto).
    static func whole(_ x: Any?) -> Int? {
        guard let n = x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 1e9 else { return nil }
        return n.intValue
    }
    /// Values of different types as one line, to compare.
    static func s(_ x: Any...) -> String { x.map { "\($0)" }.joined(separator: " ") }

    /// A clock for `WardrobeClock` that a test moves by hand: the date, the seconds to midnight, and a list of the timers that were asked for.
    @MainActor final class Fake {
        var day = Wardrobe.Day(y: 2026, m: 12, d: 24)
        var toMidnight = 5400.0
        var timers: [(after: Double, fire: @MainActor @Sendable () -> Void, cancelled: Bool, fired: Bool)] = []
        var waiting: Int { timers.filter { !$0.cancelled && !$0.fired }.count }
        lazy var clock = WardrobeClock(today: { [unowned self] in self.day }, secondsToMidnight: { [unowned self] in self.toMidnight },
                                       schedule: { [unowned self] after, fire in
                                           let i = self.timers.count
                                           self.timers.append((after, fire, false, false))
                                           return { MainActor.assumeIsolated { self.timers[i].cancelled = true } }
                                       })
        /// Fires the newest timer that has not been cancelled, as the system would at its time.
        func fireLast() { let i = timers.lastIndex { !$0.cancelled && !$0.fired }!; timers[i].fired = true; timers[i].fire() }
    }

    @MainActor static func main() {
        let fx = CT.fixture("wardrobe-cases.json")

        CT.section("easterOf: \(rows(fx["easter"]).count) years")
        var diffs: [String] = []
        for c in rows(fx["easter"]) {
            let got = whole(c["year"]).flatMap { Wardrobe.easterOf($0) }, want = c["out"] as? [String: Any]
            if got?.month != want.map({ int($0["month"]) }) || got?.day != want.map({ int($0["day"]) }) { diffs.append("\(String(describing: c["year"])): \(String(describing: got))") }
        }
        CT.checkRows("Easter Sunday of every year is as the fixture says (the earliest, the latest, a leap year, a year in March)", diffs)
        CT.check("1582 and 10000 have none", [Wardrobe.easterOf(1582) == nil, Wardrobe.easterOf(10000) == nil], [true, true])

        CT.section("autoOutfit: \(rows(fx["auto"]).count) dates, each side of every boundary, and the dates that are not dates")
        diffs = []
        for c in rows(fx["auto"]) {
            let got = (whole(c["y"]).flatMap { y in whole(c["m"]).flatMap { m in whole(c["d"]).map { Wardrobe.autoOutfit(y, m, $0) } } }) ?? "none"
            if got != c["out"] as! String { diffs.append("\(String(describing: c["y"]))-\(String(describing: c["m"]))-\(String(describing: c["d"])): \(got)") }
        }
        CT.checkRows("every date is as the fixture says", diffs)
        CT.check("a day that is not a day is none", [Wardrobe.autoOutfit(2026, 2, 30), Wardrobe.autoOutfit(2026, 13, 1), Wardrobe.autoOutfit(2026, 12, 0), Wardrobe.autoOutfit(0, 12, 24), Wardrobe.autoOutfit(10000, 12, 24), Wardrobe.autoOutfit(2023, 2, 29), Wardrobe.autoOutfit(2100, 2, 29)], Array(repeating: "none", count: 7))
        CT.check("29 February of a leap year is a day (and nothing to wear)", Wardrobe.autoOutfit(2024, 2, 29), "none")

        CT.section("Easter's window, walked with the calendar: \(rows(fx["easterWindows"]).count) years")
        diffs = []
        for w in rows(fx["easterWindows"]) {
            for d in rows(w["days"]) where Wardrobe.autoOutfit(int(d["y"]), int(d["m"]), int(d["d"])) != d["out"] as! String { diffs.append("k \(int(d["k"])) of \(int(w["year"]))") }
        }
        CT.checkRows("Good Friday to Easter Monday wears the bunny ears and the days round it nothing, in March and in April", diffs)

        CT.section("resolve: \(rows(fx["resolve"]).count) choices")
        diffs = []
        for c in rows(fx["resolve"]) where Wardrobe.resolve(c["id"], int(c["y"]), int(c["m"]), int(c["d"])) != c["out"] as! String { diffs.append("\(String(describing: c["id"]))") }
        CT.checkRows("Auto is resolved for the date, an outfit stays, a made-up name is Auto", diffs)
        CT.check("the label for Auto", [Wardrobe.autoLabel(today: "santahat"), Wardrobe.autoLabel(today: "none")], ["Auto: today, Santa hat", "Auto: today, none"])

        CT.section("the Debug panel's date field and its next day")
        CT.check("a real date is read", Wardrobe.parseDay("2026-12-24"), Wardrobe.Day(y: 2026, m: 12, d: 24))
        CT.check("and nothing else is", ["2026-12-2", "2026-2-24", "26-12-24", "2026-13-01", "2026-02-30", "2026-12-24 ", "2026/12/24", "٢٠٢٦-١٢-٢٤", "", "2026-12", "2026--12-24", "+026-12-24"].compactMap { Wardrobe.parseDay($0) }.count, 0)
        CT.check("the day after", [Wardrobe.nextDay(.init(y: 2026, m: 12, d: 26)), Wardrobe.nextDay(.init(y: 2026, m: 12, d: 31)), Wardrobe.nextDay(.init(y: 2024, m: 2, d: 28)), Wardrobe.nextDay(.init(y: 2023, m: 2, d: 28)), Wardrobe.nextDay(.init(y: 2100, m: 2, d: 28)), Wardrobe.nextDay(.init(y: 2026, m: 4, d: 30))],
                 [.init(y: 2026, m: 12, d: 27), .init(y: 2027, m: 1, d: 1), .init(y: 2024, m: 2, d: 29), .init(y: 2023, m: 3, d: 1), .init(y: 2100, m: 3, d: 1), .init(y: 2026, m: 5, d: 1)])

        CT.section("the date and the seconds to midnight, from the calendar")
        var ny = Calendar(identifier: .gregorian); ny.timeZone = TimeZone(identifier: "America/New_York")!
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date { ny.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))! }
        CT.check("a late evening is still today", Wardrobe.today(now: at(2026, 12, 24, 23, 30), calendar: ny), Wardrobe.Day(y: 2026, m: 12, d: 24))
        CT.checkNear("and midnight is half an hour away", Wardrobe.secondsToMidnight(now: at(2026, 12, 24, 23, 30), calendar: ny), 1800)
        CT.checkNear("the day the clocks go forward is 23 hours long: 00:30 is 22 and a half hours from the next midnight", Wardrobe.secondsToMidnight(now: at(2026, 3, 8, 0, 30), calendar: ny), 22.5 * 3600)
        CT.checkNear("the day they go back is 25 hours long: 00:30 is 24 and a half hours from the next midnight", Wardrobe.secondsToMidnight(now: at(2026, 11, 1, 0, 30), calendar: ny), 24.5 * 3600)
        CT.checkNear("one second before midnight is asked for a full second", Wardrobe.secondsToMidnight(now: ny.date(from: DateComponents(year: 2026, month: 12, day: 24, hour: 23, minute: 59, second: 59, nanosecond: 900_000_000))!, calendar: ny), 1)

        CT.section("the clock: Auto waits for midnight with one one-shot timer")
        let f = Fake()
        var seen: [String] = []
        f.clock.onChange = { seen.append($0) }
        CT.check("before it starts nothing is armed", [f.timers.count, f.clock.isArmed ? 1 : 0], [0, 0])
        f.clock.start()
        CT.check("at launch on 24 December Auto wears the Santa hat", f.clock.resolved, "santahat")
        CT.check("and one timer waits for a second after midnight", [f.timers.count, Int(f.timers[0].after)], [1, 5401])
        CT.check("nothing was announced: the first outfit is read from `resolved`", seen, [])
        f.day = Wardrobe.Day(y: 2026, m: 12, d: 27); f.toMidnight = 86400
        f.fireLast()
        CT.check("at midnight it looks at the date again: nothing to wear on the 27th", f.clock.resolved, "none")
        CT.check("the change was announced", seen, ["none"])
        CT.check("and the next midnight is already waiting (one timer, not two)", [f.timers.count, f.waiting, Int(f.timers[1].after)], [2, 1, 86401])
        f.fireLast()
        CT.check("a timer that fires on the same day changes nothing and waits again", s(f.clock.resolved, seen.count, f.waiting), s("none", 1, 1))
        f.day = Wardrobe.Day(y: 2027, m: 6, d: 25); f.toMidnight = 40000
        f.fireLast()
        CT.check("a timer that fires days late (the Mac slept) recomputes from the date then", f.clock.resolved, "sunglasses")

        CT.section("the clock: an outfit, or None, cancels the timer")
        f.clock.setChoice("bow")
        CT.check("picking the bow shows it, at once, and cancels the timer", s(f.clock.resolved, f.waiting, f.clock.isArmed ? 1 : 0), s("bow", 0, 0))
        f.clock.setChoice("none")
        CT.check("None wears nothing and arms nothing", s(f.clock.resolved, f.waiting), s("none", 0))
        let made = f.timers.count
        f.clock.setChoice("bell")
        CT.check("another outfit arms nothing", f.timers.count, made)
        f.clock.setChoice("auto")
        CT.check("Auto again resolves for the date and arms one timer", s(f.clock.resolved, f.waiting, f.timers.count), s("sunglasses", 1, made + 1))
        f.clock.setChoice("auto")
        CT.check("the same choice again leaves one timer (the old one is cancelled)", f.waiting, 1)
        f.clock.setChoice("Bow")
        CT.check("a made-up name is Auto", s(f.clock.choice, f.clock.resolved, f.waiting), s("auto", "sunglasses", 1))
        f.day = Wardrobe.Day(y: 2026, m: 12, d: 25)
        f.clock.dateChanged()
        CT.check("a date override (Debug panel) is looked at now and the timer is re-armed", s(f.clock.resolved, f.waiting), s("santahat", 1))

        CT.section("the clock: an outfit chosen at launch never starts a timer")
        let g = Fake()
        g.clock.setChoice("crown")
        g.clock.start()
        CT.check("the crown is worn and no timer was asked for", s(g.clock.resolved, g.timers.count), s("crown", 0))
        g.toMidnight = 0.2
        g.clock.setChoice("auto")
        CT.check("a clock that is a hair from midnight still waits a full second", Int(g.timers[0].after), 1)
        CT.finish()
    }
}
```

**Create `scripts/test-wardrobe-auto.sh`**

```bash
#!/usr/bin/env bash
# Wardrobe Auto (sub-project I): Easter (Meeus/Jones/Butcher), the five dated rules in their order, resolve, the date and the seconds to midnight (daylight saving included) and the
# clock with its ONE one-shot timer, against wardrobe-cases.json, and what the fixture cannot write (a timer that fires early, one that fires days late, a date override).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-auto.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/Wardrobe.swift $APP/WardrobeSettings.swift $APP/WardrobeAuto.swift $APP/CatSettings.swift $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift \
    tests/CatTestSupport.swift tests/WardrobeAutoTests.swift \
    -o "$TEST_DIR/wardrobe-auto-tests"
"$TEST_DIR/wardrobe-auto-tests"
```


```bash
chmod +x scripts/test-wardrobe-settings.sh scripts/test-wardrobe-auto.sh
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-wardrobe-settings.sh 2>&1 | tail -3; bash scripts/test-wardrobe-auto.sh 2>&1 | tail -3`
Expected: FAIL, `error opening input file 'NotchBuddy/Sources/App/Wardrobe.swift'` (the sources do not exist yet).

- [ ] **Step 3: Write the sources**

**Create `NotchBuddy/Sources/App/Wardrobe.swift`**

```swift
import Foundation

// The wardrobe's frozen names (sub-project I). Port of the "wardrobe" section of design/prototype/cat-core.js (the tie-breaker): the 18 selection IDs and their order, `outfitIdOf`
// and `outfitWorn`; tests/fixtures/cat/wardrobe-cases.json pins them. The IDs and their order are frozen, because they are stored (`cat.outfit`) and because the grid, the menus and the
// ⌃⌥G cycle all follow the order. Foundation only, and nothing else: the renderer files compile it without the settings.

enum Wardrobe {
    /// The 18 selection IDs: Auto, None, then the 16 outfits in the grid's order. Frozen.
    static let ids = ["auto", "none", "partyhat", "santahat", "witchhat", "bunnyears", "sunglasses", "beanie", "bow", "scarf", "roundglasses", "crown", "bell", "bandana", "fishclip", "flower", "shrimpclip", "blossomclip"]
    /// The names the UI shows, by ID.
    static let names: [String: String] = [
        "auto": "Auto", "none": "None", "partyhat": "Party hat", "santahat": "Santa hat", "witchhat": "Witch hat", "bunnyears": "Bunny ears", "sunglasses": "Sunglasses",
        "beanie": "Beanie", "bow": "Bow", "scarf": "Scarf", "roundglasses": "Round glasses", "crown": "Crown", "bell": "Bell", "bandana": "Bandana", "fishclip": "Fish clip",
        "flower": "Flower", "shrimpclip": "Shrimp clip", "blossomclip": "Peach-blossom clip",
    ]
    /// The grid's rows: the two choices (no heading), then the four groups with their headings.
    struct Group: Equatable, Sendable { var id: String; var name: String; var ids: [String] }
    static let groups = [
        Group(id: "choice", name: "", ids: ["auto", "none"]),
        Group(id: "seasonal", name: "Seasonal", ids: ["partyhat", "santahat", "witchhat", "bunnyears", "sunglasses"]),
        Group(id: "everyday", name: "Everyday", ids: ["beanie", "bow", "scarf", "roundglasses", "crown"]),
        Group(id: "extras", name: "Cat extras", ids: ["bell", "bandana", "fishclip", "flower"]),
        Group(id: "own", name: "The cats' own", ids: ["shrimpclip", "blossomclip"]),
    ]
    /// The 16 that are drawn: everything but Auto and None.
    static let drawn = Array(ids.dropFirst(2))
    static let defaultOutfit = "auto"

    /// The name to show for an ID ("Auto" for anything that is not one).
    static func name(_ id: String) -> String { names[id] ?? "Auto" }

    /// A stored outfit to an ID: exactly one of the 18, as written (lowercase, no trimming); anything else, or no string at all, is "auto".
    static func idOf(_ v: Any?) -> String {
        guard let s = v as? String, ids.contains(s) else { return defaultOutfit }
        return s
    }

    /// The next ID in the grid's order, `auto` and `none` included, wrapping from `blossomclip` to `auto` (⌃⌥G). An ID that is not one counts as `auto`.
    static func next(after id: String) -> String {
        let i = ids.firstIndex(of: idOf(id)) ?? 0
        return ids[(i + 1) % ids.count]
    }

    /// Who wears an outfit: the cats in a big-cat role, at every size. The role decides, never the diameter.
    enum Role: String, Sendable { case big, small, kitten }
    static let roles = ["big", "small", "kitten"]
    /// `outfitWorn`: true for the text "big" and nothing else (a diameter, `null`, a wrong case and a made-up role are all bare).
    static func worn(_ role: Any?) -> Bool { (role as? String) == "big" }
    static func worn(_ role: Role) -> Bool { role == .big }
}
```

**Create `NotchBuddy/Sources/App/WardrobeSettings.swift`**

```swift
import Foundation

// What the wardrobe saves (sub-project I): the stored choice `cat.outfit`. Port of `cleanWardrobeSettings` in design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/wardrobe-cases.json pins it. A preferences file can be hand-edited, so everything read back goes through `WardrobeSettings.clean`: raw in, clean out, never a
// throw. It is a clean-up of its own, as `DesktopCatSettings.clean` is: the Cat, Display and Desktop clean-ups and their fixtures are as they were. Foundation only.

struct WardrobeSettings: Equatable, Sendable {
    /// One of the 18 IDs. `auto` is a choice, not an outfit: the clock resolves it for drawing (`WardrobeClock`).
    var outfit = Wardrobe.defaultOutfit

    // MARK: Cleaning

    /// Everything the wardrobe saves, cleaned. `raw` is a dictionary shaped like `{outfit}`; anything else gives the default. Never throws.
    static func clean(_ raw: Any?) -> WardrobeSettings {
        let r = raw as? [String: Any] ?? [:]
        return WardrobeSettings(outfit: Wardrobe.idOf(r["outfit"]))
    }

    /// The settings as the fixtures hold them.
    var json: [String: Any] { ["outfit": outfit] }

    // MARK: Edits

    func withOutfit(_ id: String) -> WardrobeSettings { WardrobeSettings(outfit: Wardrobe.idOf(id)) }

    // MARK: UserDefaults

    enum Key { static let outfit = "cat.outfit" }

    /// What is stored, cleaned. The stored object is read as it is, so a number or a list is `auto`.
    static func load(from store: any CatSettingsBacking) -> WardrobeSettings {
        var raw: [String: Any] = [:]
        if let v = store.object(forKey: Key.outfit) { raw["outfit"] = v }
        return clean(raw)
    }

    /// Writes what differs from `old` (everything, when there is no `old`). Only a cleaned value is ever passed in.
    func save(to store: any CatSettingsBacking, replacing old: WardrobeSettings? = nil) {
        if old?.outfit != outfit { store.set(outfit, forKey: Key.outfit) }
    }
}
```

**Create `NotchBuddy/Sources/App/WardrobeAuto.swift`**

```swift
import Foundation

// What Auto wears and when it looks again (sub-project I). Port of `easterOf`, `autoOutfitFor` and `resolveOutfit` in design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/wardrobe-cases.json pins them. Everything works on date numbers (year, month, day): no clock, no time zone, so a daylight-saving change can never shift
// Easter's window, and the same date gives the same outfit on every platform. `WardrobeClock` keeps the resolved outfit and the ONE one-shot timer Auto needs (the same shape as
// `CatSleepClock`): it takes its date and its timer from outside, so a test moves both by hand. Foundation only.

extension Wardrobe {
    /// A local calendar date as numbers.
    struct Day: Equatable, Sendable { var y: Int, m: Int, d: Int }

    /// Gregorian Easter Sunday of a year from 1583 to 9999 (the Meeus/Jones/Butcher computation); nil for any other year.
    static func easterOf(_ year: Int) -> (month: Int, day: Int)? {
        guard year >= 1583, year <= 9999 else { return nil }
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451, n = h + l - 7 * m + 114
        return (n / 31, n % 31 + 1)
    }

    /// Days since 1970-01-01 of a calendar date, from the date numbers alone, so a difference of two dates can never be shifted by daylight saving.
    static func days(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let yy = m <= 2 ? y - 1 : y, era = yy / 400, yoe = yy - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1, doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// Whether the numbers are a real date (a year from 1 to 9999).
    static func isDate(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        guard y >= 1, y <= 9999, m >= 1, m <= 12, d >= 1 else { return false }
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
        return d <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
    }

    /// What Auto wears on a local date. The first rule that matches wins, and the order is the contract: 1 Dec 31 to Jan 2 `partyhat`; 2 Dec 1 to Dec 26 `santahat`;
    /// 3 Oct 1 to Nov 1 `witchhat`; 4 Good Friday to Easter Monday (Easter minus 2 days to plus 1) `bunnyears`; 5 Jun 21 to Aug 31 `sunglasses`. Anything else, and a date that is
    /// not a real date, is `none`.
    static func autoOutfit(_ y: Int, _ m: Int, _ d: Int) -> String {
        guard isDate(y, m, d) else { return "none" }
        if (m == 12 && d == 31) || (m == 1 && d <= 2) { return "partyhat" }
        if m == 12 && d <= 26 { return "santahat" }
        if m == 10 || (m == 11 && d == 1) { return "witchhat" }
        if let e = easterOf(y) {
            let k = days(y, m, d) - days(y, e.month, e.day)
            if k >= -2 && k <= 1 { return "bunnyears" }
        }
        if (m == 6 && d >= 21) || m == 7 || m == 8 { return "sunglasses" }
        return "none"
    }

    static func autoOutfit(_ day: Day) -> String { autoOutfit(day.y, day.m, day.d) }

    /// The outfit to draw: the stored choice cleaned, with `auto` replaced by what Auto says for the date (`none` when nothing is worn). Never `auto`.
    static func resolve(_ id: Any?, _ y: Int, _ m: Int, _ d: Int) -> String {
        let o = idOf(id)
        return o == "auto" ? autoOutfit(y, m, d) : o
    }

    static func resolve(_ id: Any?, _ day: Day) -> String { resolve(id, day.y, day.m, day.d) }

    /// Settings' and the menus' label for Auto: "Auto: today, Santa hat" or "Auto: today, none". `today` is `autoOutfit` for today.
    static func autoLabel(today id: String) -> String { "Auto: today, " + (id == "none" ? "none" : name(id)) }

    /// "2026-12-24" as a date: exactly four digits, a hyphen, two, a hyphen, two, and a real date; nil for anything else (the Debug panel's date field).
    static func parseDay(_ text: String) -> Day? {
        let p = text.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2, p.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), isDate(y, m, d) else { return nil }
        return Day(y: y, m: m, d: d)
    }

    /// The next calendar day (the Debug panel's "midnight in 5 seconds").
    static func nextDay(_ day: Day) -> Day {
        let leap = day.y % 4 == 0 && (day.y % 100 != 0 || day.y % 400 == 0)
        let last = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][max(1, min(12, day.m)) - 1]
        if day.d < last { return Day(y: day.y, m: day.m, d: day.d + 1) }
        return day.m == 12 ? Day(y: day.y + 1, m: 1, d: 1) : Day(y: day.y, m: day.m + 1, d: 1)
    }

    /// The local calendar date now.
    static func today(now: Date = Date(), calendar: Calendar = .current) -> Day {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return Day(y: c.year ?? 1970, m: c.month ?? 1, d: c.day ?? 1)
    }

    /// Seconds from `now` to the next local midnight (at least a second, so a clock that is a hair early never asks for zero).
    static func secondsToMidnight(now: Date = Date(), calendar: Calendar = .current) -> Double {
        guard let next = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) else { return 3600 }
        return max(1, next.timeIntervalSince(now))
    }
}

/// The menus' items, by the grid's order. The island cat's menu and the desktop cat's menu both turn them into an `NSMenu`.
enum WardrobeMenu {
    enum Item: Equatable, Sendable {
        case choice(id: String, title: String, checked: Bool)
        case heading(String)
        case separator
    }

    /// The 18 entries in their groups, a check on the stored choice. `autoToday` is what Auto wears today (`Wardrobe.autoOutfit`), for the first label.
    static func items(selected: String, autoToday: String) -> [Item] {
        let chosen = Wardrobe.idOf(selected)
        var list: [Item] = []
        for (i, g) in Wardrobe.groups.enumerated() {
            if i > 0 { list.append(.separator) }
            if !g.name.isEmpty { list.append(.heading(g.name)) }
            for id in g.ids { list.append(.choice(id: id, title: id == "auto" ? Wardrobe.autoLabel(today: autoToday) : Wardrobe.name(id), checked: id == chosen)) }
        }
        return list
    }
}

/// Keeps the outfit every big cat wears now. `auto` is resolved from the date: at launch (`start`), when the choice changes, and at the next local midnight, with one one-shot
/// timer that exists only while the choice is `auto` (picking an outfit, or None, cancels it). When the timer fires late, after a long sleep, it recomputes from the date then;
/// when it fires early, it asks again for the rest. Nothing polls.
@MainActor
final class WardrobeClock {
    /// Cancels a scheduled call.
    typealias Cancel = () -> Void

    private let today: () -> Wardrobe.Day
    private let secondsToMidnight: () -> Double
    private let schedule: (_ afterSeconds: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> Cancel
    private var cancel: Cancel?
    private(set) var choice = Wardrobe.defaultOutfit
    /// The outfit to draw: one of the 16 IDs, or `none`. Never `auto`.
    private(set) var resolved = "none"
    /// Called with the new outfit when it changes.
    var onChange: ((String) -> Void)?
    /// Whether the one-shot is waiting (true only while the choice is `auto`).
    var isArmed: Bool { cancel != nil }

    init(today: @escaping () -> Wardrobe.Day, secondsToMidnight: @escaping () -> Double, schedule: @escaping (Double, @escaping @MainActor @Sendable () -> Void) -> Cancel) {
        self.today = today; self.secondsToMidnight = secondsToMidnight; self.schedule = schedule
        resolved = Wardrobe.resolve(choice, today())
    }

    /// Resolves the stored choice for today and, for `auto`, waits for midnight.
    func start() { refresh(); rearm() }

    /// The stored choice changed (or was just loaded).
    func setChoice(_ raw: Any?) {
        choice = Wardrobe.idOf(raw)
        refresh()
        rearm()
    }

    /// The date changed under us (the Debug panel's date override): look again now.
    func dateChanged() { refresh(); rearm() }

    private func refresh() {
        let next = Wardrobe.resolve(choice, today())
        guard next != resolved else { return }
        resolved = next
        onChange?(next)
    }

    private func rearm() {
        cancel?(); cancel = nil
        guard choice == "auto" else { return }
        cancel = schedule(max(1, secondsToMidnight() + 1)) { [weak self] in self?.fire() }
    }

    private func fire() {
        cancel = nil
        refresh()
        rearm()
    }
}

#if DEBUG && !APPSTORE
/// The names the Debug cat panel's Wardrobe section and the app's `WardrobeClock` share (a Debug build only; compiled out of Release and App Store): the panel posts them, the clock listens, so the
/// panel compiles without the app's files.
enum WardrobeDev {
    /// userInfo `["day": "2026-12-24"]` (text that `Wardrobe.parseDay` reads; anything else is "no date pretended").
    static let dateNote = Notification.Name("nm.wardrobe.debugDate")
    /// "The next midnight is five seconds away" (the clock's one-shot is asked for it and the pretend date moves on a day).
    static let midnightNote = Notification.Name("nm.wardrobe.debugMidnight")
}
#endif
```


- [ ] **Step 4: Run them to see them pass**

Run: `bash scripts/test-wardrobe-settings.sh 2>&1 | grep -v "✓"; bash scripts/test-wardrobe-auto.sh 2>&1 | grep -v "✓"`
Expected: PASS, the section titles (`the frozen values…`, `idOf: 38 stored values`, `WardrobeSettings.clean: 11 stored blocks`, `who wears it: 16 roles`, `easterOf: 24 years`, `autoOutfit: 34 dates…`, `Easter's window, walked with the calendar: 12 years`, `the clock: …`) and the last line `All tests passed.` for each.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/Wardrobe.swift NotchBuddy/Sources/App/WardrobeSettings.swift NotchBuddy/Sources/App/WardrobeAuto.swift tests/WardrobeSettingsTests.swift tests/WardrobeAutoTests.swift scripts/test-wardrobe-settings.sh scripts/test-wardrobe-auto.sh
printf '%s\n' 'feat(wardrobe): the IDs, the clean-up, Auto and its clock (I-mac task 1)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 2: The store holds the wardrobe (step 1)

`CatSettingsStore` holds `wardrobe` beside `settings`, `display` and `desktop`, saves only the key that changed, cleans what it is given, and offers the two edits every picker uses: `setOutfit(_:)` and `nextOutfit()` (⌃⌥G). `CatConfig.outfit` is the resolved outfit every big cat reads on every frame; the clock (Task 6) writes it, the store never does.

**Interfaces.** Consumes: `WardrobeSettings` and `Wardrobe` (Task 1). Produces: `CatSettingsStore.wardrobe: WardrobeSettings` (published), `updateWardrobe(_:)`, `setOutfit(_ id: String)`, `nextOutfit()`; `CatConfig.outfit: String` (`"none"` at first).

- [ ] **Step 1: Write the test (and the scripts' lists)**

**Edit `tests/CatSettingsStoreTests.swift`**

Find:

```swift
        CT.check("a store that is wrong in every way still loads the defaults", CatSettingsStore(backing: wild, config: CatConfig()).desktop, DesktopCatSettings())
        CT.check("and loading wrote nothing", wild.writes.count, 0)
```

Replace with:

```swift
        CT.check("a store that is wrong in every way still loads the defaults", CatSettingsStore(backing: wild, config: CatConfig()).desktop, DesktopCatSettings())
        CT.check("and loading wrote nothing", wild.writes.count, 0)
    }

    /// I: the stored outfit is held, saved, cycled and cleaned by the same store.
    @MainActor static func wardrobeSettings() {
        CT.section("wardrobe settings: the store starts from what is stored, saves only what changed and cleans what it is given")
        let mem = MemoryBacking()
        mem.values = ["cat.outfit": "witchhat", "cat.character": "latte"]
        let cfg = CatConfig()
        let store = CatSettingsStore(backing: mem, config: cfg)
        CT.check("the stored outfit is loaded", store.wardrobe, WardrobeSettings(outfit: "witchhat"))
        CT.check("and the Cat settings beside it", store.settings.character, "latte")
        CT.check("nothing was written yet", mem.writes.count, 0)
        CT.check("the engines' resolved outfit starts at none: the wardrobe's clock sets it, not the store", cfg.outfit, "none")
        store.setOutfit("santahat")
        CT.check("a pick is stored", [store.wardrobe.outfit, mem.values["cat.outfit"] as? String ?? ""], ["santahat", "santahat"])
        store.setOutfit("santahat")
        CT.check("the same pick again writes nothing", mem.writes, ["cat.outfit"])
        store.setOutfit("Bow")
        CT.check("a made-up name is auto, and that is what is stored", [store.wardrobe.outfit, mem.values["cat.outfit"] as? String ?? ""], ["auto", "auto"])
        store.nextOutfit()
        CT.check("the shortcut moves to the next ID: Auto goes to None", store.wardrobe.outfit, "none")
        store.nextOutfit()
        CT.check("and None to the first outfit", store.wardrobe.outfit, "partyhat")
        store.setOutfit("blossomclip")
        store.nextOutfit()
        CT.check("the last wraps to Auto", store.wardrobe.outfit, "auto")
        store.setCharacter("momo")
        CT.check("the Main cat is another row: no wardrobe key moves with it", mem.writes.last ?? "", "cat.character")
        store.updateWardrobe { $0.outfit = "fancyhat" }
        CT.check("a bad value is cleaned before it is stored or used", store.wardrobe.outfit, "auto")
        store.setOutfit("crown")
        CT.check("a second store on the same keys reads the same choice back", CatSettingsStore(backing: mem, config: CatConfig()).wardrobe, store.wardrobe)
        let wild = MemoryBacking()
        wild.values = ["cat.outfit": 7]
        CT.check("a store that is wrong in every way still loads auto", CatSettingsStore(backing: wild, config: CatConfig()).wardrobe, WardrobeSettings())
        CT.check("and loading wrote nothing", wild.writes.count, 0)
```

**Edit `tests/CatSettingsStoreTests.swift`**

Find:

```swift
        desktopSettings()
        CT.finish()
```

Replace with:

```swift
        desktopSettings()
        wardrobeSettings()
        CT.finish()
```

**Edit `scripts/test-cat-settings-store.sh`**

Find:

```text
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/CatSettingsStore.swift \
```

Replace with:

```text
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/Wardrobe.swift $APP/WardrobeSettings.swift $APP/CatSettingsStore.swift \
```

**Edit `scripts/render-cat-settings.sh`**

Find:

```text
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/CatSettingsStore.swift $APP/CatDisplayPreview.swift $APP/CatSettingsView.swift \
```

Replace with:

```text
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/WardrobeSettings.swift $APP/WardrobeAuto.swift $APP/CatSettingsStore.swift $APP/CatDisplayPreview.swift $APP/CatSettingsView.swift \
```


- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | tail -4`
Expected: FAIL, `value of type 'CatSettingsStore' has no member 'wardrobe'` (and `CatConfig` has no member `outfit`).

- [ ] **Step 3: Write the code**

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**

Find:

```swift
    var collarOverride: [String: String] = [:]
```

Replace with:

```swift
    var collarOverride: [String: String] = [:]
    /// Settings → Cat → Wardrobe: the outfit every cat in a big-cat role wears now, resolved (one of the 16 IDs, or "none"; never "auto"). The wardrobe's clock keeps it
    /// (`WardrobeClock`); a view reads it on every frame, so a change shows on the next one.
    var outfit = "none"
```

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**

Find:

```swift
    @Published private(set) var desktop: DesktopCatSettings
    private let backing: any CatSettingsBacking
```

Replace with:

```swift
    @Published private(set) var desktop: DesktopCatSettings
    /// Settings → Cat → Wardrobe, the island cat's and the desktop cat's menus and ⌃⌥G: the stored choice (`auto`, `none` or one of the 16 outfits). Cleaned by its own
    /// `WardrobeSettings.clean`, beside the others. The outfit to draw is `config.outfit`, which `WardrobeClock` resolves from this.
    @Published private(set) var wardrobe: WardrobeSettings
    private let backing: any CatSettingsBacking
```

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**

Find:

```swift
        desktop = DesktopCatSettings.load(from: backing)
        config.apply(settings)
```

Replace with:

```swift
        desktop = DesktopCatSettings.load(from: backing)
        wardrobe = WardrobeSettings.load(from: backing)
        config.apply(settings)
```

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**

Find:

```swift
    func rememberDesktopSpot(_ spot: DesktopSpot, on screens: [DesktopScreen]) { updateDesktop { $0 = $0.remembering(spot, on: screens) } }
}
```

Replace with:

```swift
    func rememberDesktopSpot(_ spot: DesktopSpot, on screens: [DesktopScreen]) { updateDesktop { $0 = $0.remembering(spot, on: screens) } }

    // MARK: The wardrobe

    /// Changes the wardrobe settings the same way `update` changes the Cat settings: the closure edits a copy, the copy is cleaned, and when it differs it is published and
    /// saved (only the key that changed).
    func updateWardrobe(_ change: (inout WardrobeSettings) -> Void) {
        var next = wardrobe
        change(&next)
        next = WardrobeSettings.clean(next.json)
        guard next != wardrobe else { return }
        next.save(to: backing, replacing: wardrobe)
        wardrobe = next
    }
    /// One of the 18 IDs (Settings' tiles, the menus' items): a made-up name is `auto`. The new choice is stored, and the clock that resolves it follows `$wardrobe`.
    func setOutfit(_ id: String) { updateWardrobe { $0 = $0.withOutfit(id) } }
    /// ⌃⌥G: the next ID in the grid's order, `auto` and `none` included, wrapping to `auto`.
    func nextOutfit() { setOutfit(Wardrobe.next(after: wardrobe.outfit)) }
}
```


- [ ] **Step 4: Run it to see it pass**

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | grep -v "✓" | tail -5`
Expected: PASS, a `wardrobe settings: the store starts from what is stored, saves only what changed and cleans what it is given` section and `All tests passed.`

Run: `bash scripts/test-cat-engine.sh 2>&1 | tail -1`
Expected: `All tests passed.` (`CatConfig` gained one property; nothing else moved.)

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/CatEngine.swift NotchBuddy/Sources/App/CatSettingsStore.swift tests/CatSettingsStoreTests.swift scripts/test-cat-settings-store.sh scripts/render-cat-settings.sh
printf '%s\n' 'feat(wardrobe): the store holds the stored outfit (I-mac task 2)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 3: The geometry in Swift: anchors, 16 outfits, digests (step 2)

A port of `outfitEdge`, `outfitRoom`, `outfitAnchors`, `outfitGeometry` and `outfitDigest`. The shapes are plain data in head-local px (`poly`, `curve`, `ellipse`), each with a slot, colour roles, an alpha, a stroke width and a `fine` flag. The test replays the fixture's 32 anchors, its 4 pinned geometry cases, **1024 digests (all 16 outfits on all 16 coats at Ø18, Ø20, Ø48 and Ø64)**, the 12 collar cases, the detail cut, the sunglasses' rims and the compact notch's floors.

**Interfaces.** Consumes: `Wardrobe.drawn` (Task 1), `CatGeometry.layout`, `.supPoints`, `.collarGeometry`, `.earScale`, `.mixHex`. Produces: `CatOutfit.Options` (`dpr`, `detail`, `earScale`, `collar`, `room`, and the strip's `headY` and `ceiling`), `CatOutfit.Min`, `.slots`, `.edge(_ p) -> "light"|"dark"`, `.room(topY:headY:ceiling:)`, `.anchors(_ p, _ s, D:, _ o)`, `.geometry(_ id, _ p, _ s, D:, _ o) -> [Shape]`, `.digest(_ shapes)`, `CatOutfit.Shape` (`k`, `slot`, `fill`, `stroke`, `sw`, `a`, `fine`, `pts`, `x`, `y`, `rx`, `ry`, `rot`, `json`).

- [ ] **Step 1: Write the test and its script**

**Create `tests/WardrobeGeometryTests.swift`**

```swift
import Foundation

@main
enum WardrobeGeometryTests {
    typealias O = CatOutfit
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func num(_ x: Any?) -> Double? { (x as? NSNumber).map(\.doubleValue) }

    static var rest: CatPose { CatPose() }
    static var turned: CatPose { var s = CatPose(); s.yaw = 0.6; s.pitch = 0.15; return s }
    /// The options a renderer would pass: the notch's strips give the compact cat its room above the crown (a 32 pt strip for the Ø20 cat, a 24 pt strip for the Ø18 one).
    static func opts(_ p: CatPreset, _ s: CatPose, _ D: Double, collar: String = "off", strips: [String: Double]) -> O.Options {
        var o = O.Options(dpr: 2, collar: collar)
        if let strip = strips["\(Int(D))"] { o.room = O.room(topY: O.anchors(p, s, D: D, o).top.y, headY: strip / 2, ceiling: 0) }
        return o
    }

    /// The highest and lowest point of a list of shapes in a strip, stroke widths included.
    static func extent(_ shapes: [O.Shape], headY: Double) -> (hi: Double, lo: Double) {
        var hi = Double.infinity, lo = -Double.infinity
        for sh in shapes {
            let w = (sh.stroke != nil ? sh.sw : 0) / 2
            if sh.k == .ellipse { let r = hypot(sh.rx * sin(sh.rot), sh.ry * cos(sh.rot)); hi = min(hi, headY + sh.y - r - w); lo = max(lo, headY + sh.y + r + w) }
            else { for q in sh.pts { hi = min(hi, headY + q.y - w); lo = max(lo, headY + q.y + w) } }
        }
        return (hi, lo)
    }

    @MainActor static func main() {
        let fx = CT.fixture("wardrobe-cases.json")
        let strips = (fx["strips"] as! [String: NSNumber]).mapValues(\.doubleValue)
        func geo(_ id: String, _ cat: String, _ D: Double, _ pose: CatPose = rest, collar: String = "off") -> [O.Shape] {
            let p = CatPresets.byID(cat)
            return O.geometry(id, p, pose, D: D, opts(p, pose, D, collar: collar, strips: strips))
        }

        CT.section("the frozen values: the slots and the floors")
        CT.check("the three slots", O.slots, fx["slots"] as! [String])
        let min = fx["min"] as! [String: NSNumber]
        CT.check("the floors, in device pixels", [O.Min.height, O.Min.line, O.Min.rim, O.Min.ball, O.Min.span], ["height", "line", "rim", "ball", "span"].map { min[$0]!.doubleValue })

        CT.section("outfitEdge: all 16 coats")
        let edges = fx["edge"] as! [String: String]
        CT.check("light on a dark head, dark on a light one", Dictionary(uniqueKeysWithValues: CatPresets.ids.map { ($0, O.edge(CatPresets.byID($0))) }), edges)

        CT.section("outfitRoom: \(rows(fx["rooms"]).count) cases")
        var diffs: [String] = []
        for c in rows(fx["rooms"]) {
            let got = O.room(topY: num(c["top"])!, headY: num(c["headY"]), ceiling: num(c["ceiling"])), want = num(c["out"])
            if (got == nil) != (want == nil) || (got != nil && abs(got! - want!) > CT.tolerance) { diffs.append("headY \(String(describing: c["headY"])) ceiling \(String(describing: c["ceiling"])): \(String(describing: got))") }
        }
        CT.checkRows("the distance to the strip less the ear fit's margin, never negative, none without a number", diffs)

        CT.section("outfitAnchors: \((fx["anchors"] as! [String: Any]).count) cases")
        diffs = []
        for (key, want) in (fx["anchors"] as! [String: Any]).sorted(by: { $0.key < $1.key }) {
            let part = key.split(separator: "/").map(String.init), p = CatPresets.byID(part[0]), D = Double(part[1])!
            let got = O.anchors(p, part[2] == "rest" ? rest : turned, D: D, O.Options(dpr: 2)).json
            let d = CT.diffs(got, want)
            if !d.isEmpty { diffs.append("\(key): \(d.first!)") }
        }
        CT.checkRows("four coats at Ø20, Ø28, Ø48 and Ø64, at rest and with the head turned", diffs)

        CT.section("outfitGeometry: \((fx["geometry"] as! [String: Any]).count) pinned cases")
        diffs = []
        for (key, byOutfit) in (fx["geometry"] as! [String: Any]).sorted(by: { $0.key < $1.key }) {
            let part = key.split(separator: "/").map(String.init), D = Double(part[1])!
            for (id, want) in (byOutfit as! [String: Any]).sorted(by: { $0.key < $1.key }) {
                let d = CT.diffs(geo(id, part[0], D, part[2] == "rest" ? rest : turned).map(\.json), want)
                if !d.isEmpty { diffs.append("\(key) \(id): \(d.first!)") }
            }
        }
        CT.checkRows("every shape of every outfit: kind, slot, roles, widths, alpha, fine flag and points", diffs)

        CT.section("outfitDigest: \((fx["digests"] as! [String: Any]).count) pairs (16 outfits on 16 coats at Ø18, Ø20, Ø48 and Ø64)")
        diffs = []
        for (key, want) in (fx["digests"] as! [String: Any]).sorted(by: { $0.key < $1.key }) {
            let part = key.split(separator: "/").map(String.init)
            let d = CT.diffs(O.digest(geo(part[1], part[0], Double(part[2])!)), want)
            if !d.isEmpty { diffs.append("\(key): \(d.first!)") }
        }
        CT.checkRows("any drift in any pair fails", diffs)
        CT.check("nothing digests to zeros", CT.diffs(O.digest([]), ["n": 0, "pts": 0, "bbox": [0, 0, 0, 0], "mx": 0, "my": 0]), [])

        CT.section("the collar: the bell, bandana and scarf over each of the four styles")
        diffs = []
        let momo = CatPresets.byID("momo")
        for (key, want) in (fx["collars"] as! [String: Any]).sorted(by: { $0.key < $1.key }) {
            let part = key.split(separator: "/").map(String.init), style = part[1], w = want as! [String: Any]
            let shapes = O.geometry(part[0], momo, rest, D: 64, O.Options(dpr: 2, collar: style))
            var d = CT.diffs(shapes.map(\.json), w["shapes"]!)
            if let c = CatGeometry.collarGeometry(momo, rest, D: 64, style: style, dpr: 2) { d += CT.diffs(c.json, w["collar"]!) }
            if !d.isEmpty { diffs.append("\(key): \(d.first!)") }
        }
        CT.checkRows("the shapes, and the collar they were read from (which they never change)", diffs)

        CT.section("a stranger, and the detail cut")
        diffs = []
        for c in rows(fx["unknown"]) { if let id = c["id"] as? String, !geo(id, "momo", 64).isEmpty { diffs.append(id) } }
        CT.checkRows("none, auto and a made-up name have no shapes", diffs)
        diffs = []
        for c in rows(fx["fine"]) {
            let id = c["id"] as! String
            if geo(id, "momo", 27).count != (c["at27"] as! NSNumber).intValue || geo(id, "momo", 28).count != (c["at28"] as! NSNumber).intValue { diffs.append(id) }
        }
        CT.checkRows("a fine shape (a glint, a star, a rib) is left out below Ø28", diffs)
        let sw = fx["shrimpSwitch"] as! [String: Any]
        diffs = []
        for r in rows(sw["rows"]) {
            let D = num(r["D"])!, got = geo("shrimpclip", "momo", D).map { [$0.k.rawValue, $0.slot, $0.fill ?? "", $0.stroke ?? "", $0.fine ? "fine" : ""].joined(separator: "|") }
            let want = (r["shapes"] as! [[Any]]).map { $0.map { $0 is NSNull ? "" : ($0 as? Bool).map { $0 ? "fine" : "" } ?? ($0 as! String) }.joined(separator: "|") }
            if got != want { diffs.append("Ø\(D)") }
            if (r["full"] as! Bool) != (D >= CatGeometry.detailFullMin) { diffs.append("full at Ø\(D)") }
        }
        CT.checkRows("the shrimp clip is a simple C below Ø28 and the detailed one from Ø28", diffs)
        diffs = []
        for r in rows(fx["lensRims"]) {
            let lenses = geo("sunglasses", r["cat"] as! String, 64).filter { $0.k == .ellipse && $0.fill == "lens" }.map { ["stroke": $0.stroke as Any, "sw": $0.sw] as [String: Any] }
            let d = CT.diffs(lenses, r["lenses"]!)
            if !d.isEmpty { diffs.append("\(r["cat"] as! String): \(d.first!)") }
        }
        CT.checkRows("a dark head's lenses get the thin light edge, a light head's keep the frame", diffs)

        CT.section("the compact notch: every outfit on every coat at Ø20 and Ø18")
        diffs = []
        let dpr = 2.0
        for (H, D) in [(32.0, 20.0), (24.0, 18.0)] {
            for cat in CatPresets.ids {
                let p = CatPresets.byID(cat), A = O.anchors(p, rest, D: D, O.Options(dpr: dpr)), room = O.room(topY: A.top.y, headY: H / 2, ceiling: 0)!
                if room < O.Min.height / dpr - 1e-9 { diffs.append("\(cat) Ø\(Int(D)): the strip leaves \(room) pt") }
                for id in Wardrobe.drawn {
                    let shapes = geo(id, cat, D), at = "\(id) on \(cat) Ø\(Int(D))", ext = extent(shapes, headY: H / 2)
                    if shapes.isEmpty { diffs.append("\(at): nothing drawn") }
                    if ext.hi < -1e-9 { diffs.append("\(at): above the strip by \(-ext.hi)") }
                    if ext.lo > H + 1e-9 { diffs.append("\(at): below the strip by \(ext.lo - H)") }
                    for sh in shapes {
                        if sh.stroke != nil && sh.sw > 0 && sh.sw < O.Min.line / dpr - 1e-9 { diffs.append("\(at): a stroke under the line floor") }
                        if sh.k == .ellipse && !sh.fine && Swift.min(sh.rx, sh.ry) < 0.5 * O.Min.ball / dpr - 1e-9 { diffs.append("\(at): an ellipse smaller than half a ball") }
                    }
                    let xs = shapes.flatMap { $0.k == .ellipse ? [$0.x - $0.rx, $0.x + $0.rx] : $0.pts.map(\.x) }, ys = shapes.flatMap { $0.k == .ellipse ? [$0.y - $0.ry, $0.y + $0.ry] : $0.pts.map(\.y) }
                    if let xa = xs.min(), let xb = xs.max(), let ya = ys.min(), let yb = ys.max(), Swift.max(xb - xa, yb - ya) < O.Min.span / dpr { diffs.append("\(at): less than a span across") }
                }
            }
        }
        CT.checkRows("inside the strip top and bottom, above every floor, at least a span across (256 pairs at each size)", diffs)
        let p = CatPresets.byID("momo")
        func rise(_ room: Double?) -> Double { -(O.geometry("partyhat", p, rest, D: 20, O.Options(dpr: dpr, room: room)).filter { $0.k == .poly }.flatMap { $0.pts.map(\.y) }.min() ?? 0) }
        CT.checkTrue("a short room gives a shorter hat, a tall one the natural height", rise(3) < rise(100) && rise(100) > rise(3) + 1)
        CT.checkNear("no room is held at the floor, as is a room of one", rise(0), rise(1))
        CT.checkTrue("and no room still draws a hat", rise(0) != 0)
        CT.checkJSON("no room at all (nil) is no limit", got: O.geometry("partyhat", p, rest, D: 20, O.Options(dpr: dpr, room: nil)).map(\.json), want: O.geometry("partyhat", p, rest, D: 20, O.Options(dpr: dpr)).map(\.json))
        CT.finish()
    }
}
```

**Create `scripts/test-wardrobe-geometry.sh`**

```bash
#!/usr/bin/env bash
# Wardrobe geometry (sub-project I): outfitEdge, outfitRoom, outfitAnchors, the shapes of all 16 outfits (outfitGeometry), their digests on all 16 coats at four sizes, the bell, bandana
# and scarf over each collar style, the detail cut and the compact notch's floors, against wardrobe-cases.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-geometry.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Wardrobe.swift $APP/CatOutfit.swift \
    tests/CatTestSupport.swift tests/WardrobeGeometryTests.swift \
    -o "$TEST_DIR/wardrobe-geometry-tests"
"$TEST_DIR/wardrobe-geometry-tests"
```


```bash
chmod +x scripts/test-wardrobe-geometry.sh
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-wardrobe-geometry.sh 2>&1 | tail -3`
Expected: FAIL, `error opening input file 'NotchBuddy/Sources/App/CatOutfit.swift'`.

- [ ] **Step 3: Write the port**

**Create `NotchBuddy/Sources/App/CatOutfit.swift`**

```swift
import Foundation

// Where an outfit sits on a head, and the shapes it is made of (sub-project I). Port of `outfitEdge`, `outfitRoom`, `outfitAnchors`, `outfitGeometry` and `outfitDigest` in
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/wardrobe-cases.json pins them. Everything is pure: the shapes are plain data in head-local px (before the tilt and
// the squash, like `collarGeometry`), turning with the face warp, with colour roles that `Theme.Outfits` resolves. `CatOutfitDraw` paints them; nothing here reads a coat list, so the
// 16 coats and any future one fit by the same maths. Foundation only (it uses `CatGeometry`).

enum CatOutfit {
    typealias G = CatGeometry

    /// The three places a shape is drawn, without touching `CatGeometry.passes`: `behind` (after the ears of the behind pass: the bunny ears), `neck` (the front pass after the collar:
    /// scarf, bandana, bell) and `top` (after `neck`, before the whiskers: hats, crown, glasses, clips, bow, flower). The whiskers, the badge and the particles stay in front of all.
    static let slots = ["behind", "neck", "top"]

    /// The smallest sizes, in DEVICE pixels (as `CollarMin` is), so an outfit still reads on the compact notch's Ø20 cat (40 device pixels wide at 2x).
    enum Min { static let height = 6.0, line = 1.0, rim = 2.0, ball = 3.0, span = 6.0 }

    /// What the callers pass besides the coat, the pose and the head width.
    struct Options: Equatable {
        /// Pixels per point (anything not above 0 counts as 2).
        var dpr = 2.0
        /// `layout`'s explicit detail: "full" or "compact"; nil: by head width.
        var detail: String?
        /// The ears' scale as the renderer drew them; nil: what the renderer uses by default (1 from Ø28, else `earScale(D)`).
        var earScale: Double?
        /// The collar's style ("tag", "band", "kerchief", "off" or anything): the bell hangs from the collar and never changes it.
        var collar = "off"
        /// The height available above the crown (`room`); nil: no limit.
        var room: Double?
        /// The compact notch's strip: the head's y and the y of the strip's top (as `CatDrawOptions.earCeiling`). When `room` is nil and both are given, the room is worked out from them
        /// (`room(topY:headY:ceiling:)`), so a renderer asks once. nil: no limit.
        var headY: Double?
        var ceiling: Double?
    }

    // MARK: Edge and room

    /// Whether a coat's head is dark enough that an outfit's thin edge must be light to show: "light" for a dark head, "dark" for a light one (the flat head colour's luminance under 100).
    static func edge(_ p: CatPreset) -> String {
        let c = G.mixHex(p.top, p.bot, G.FlatFill.headMix)
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] < 100 ? "light" : "dark"
    }

    /// The room above the crown for a hat, in px: from the crown to `ceiling` (the y of the top of the strip the cat sits in, in the same coordinates as `headY`, the head's y), less the
    /// ear fit's margin, never negative. nil when either is missing: no limit.
    static func room(topY: Double, headY: Double?, ceiling: Double?) -> Double? {
        guard let headY, let ceiling, headY.isFinite, ceiling.isFinite else { return nil }
        return max(0, headY + topY - ceiling - G.earFitMargin)
    }

    // MARK: Anchors

    struct EarAnchor { var sd: Double, bx: Double, by: Double, rot: Double, h: Double, tipX: Double, tipY: Double }
    typealias Pt = (x: Double, y: Double)

    /// Where the outfit parts attach to one cat in one pose, in head-local px: `top` the crown between the ear bases, on the head outline; `gap` the span between the two ear bases;
    /// `half` gap/2; `lean` a hat's lean with the face turn (rad); `ears` each base with its tilt and tip; `eyes` the eye frames; `chin` the lower outline from 40 to 140 degrees, left
    /// to right, with its centre front; `neck` the point the collar's tag hangs from; `edge` "light" or "dark".
    struct Anchors {
        var R: Double, rx: Double, ry: Double, D: Double, full: Bool, dpr: Double
        var top: Pt, gap: Double, half: Double, lean: Double
        var ears: [EarAnchor]
        var eyes: [G.Eye]
        var chin: (pts: [Pt], front: Pt)
        var neck: Pt
        var edge: String

        /// As the fixtures hold it.
        var json: [String: Any] {
            ["R": R, "rx": rx, "ry": ry, "D": D, "full": full, "dpr": dpr, "top": ["x": top.x, "y": top.y], "gap": gap, "half": half, "lean": lean,
             "ears": ears.map { ["sd": $0.sd, "bx": $0.bx, "by": $0.by, "rot": $0.rot, "h": $0.h, "tipX": $0.tipX, "tipY": $0.tipY] as [String: Any] },
             "eyes": eyes.map { ["sd": $0.sd, "visible": $0.visible, "x": $0.x, "y": $0.y, "fx": $0.fx, "fy": $0.fy] as [String: Any] },
             "chin": ["pts": chin.pts.map { [$0.x, $0.y] }, "front": [chin.front.x, chin.front.y]] as [String: Any],
             "neck": ["x": neck.x, "y": neck.y], "edge": edge]
        }
    }

    static func anchors(_ p: CatPreset, _ s: CatPose, D: Double, _ o: Options = Options()) -> Anchors {
        let dpr = o.dpr > 0 ? o.dpr : 2
        let ek = o.earScale ?? (D >= G.detailFullMin ? 1 : G.earScale(D))
        let L = G.layout(p, s, cx: 0, cy: 0, D: D, G.Options(full: o.detail.map { $0 == "full" }, earScale: ek))
        let R = L.R, rx = L.rx, ry = L.ry, eL = L.ears[0], eR = L.ears[1]
        let mx = (eL.bx + eR.bx) / 2, gap = abs(eR.bx - eL.bx), tx = clamp(mx / rx, -0.95, 0.95)
        let top: Pt = (mx, -ry * pow(max(0, 1 - pow(abs(tx), p.n)), 1 / p.n) + L.bend.1 * ry * (1 - tx * tx))
        let N = 90
        let ring = Array(G.supPoints(rx: rx, ry: ry, n: p.n, dy: 0, spike: p.fluff != 0 ? 0.035 : 0, count: 14, steps: N, bend: L.bend).prefix(N))
        let arc: [Pt] = Array(ring[(N * 40 / 360)...(N * 140 / 360)].reversed()).map { (x: $0.0, y: $0.1) }   // left to right, 40° to 140°
        let front: Pt = ((arc[12].x + arc[13].x) / 2, (arc[12].y + arc[13].y) / 2)
        let width = max(0.1 * R, G.CollarMin.band / dpr)
        let k = max(0.7, min(0.92, 1 - (width / 2 + 0.5 / dpr) / (p.ry * R)))
        let n = L.warp(0, p.ry * k)
        return Anchors(R: R, rx: rx, ry: ry, D: D, full: L.full, dpr: dpr, top: top, gap: gap, half: gap / 2, lean: sin(L.yf) * 0.15,
                       ears: L.ears.map { EarAnchor(sd: $0.sd, bx: $0.bx, by: $0.by, rot: $0.rot, h: $0.h, tipX: $0.bx + $0.h * sin($0.rot), tipY: $0.by - $0.h * cos($0.rot)) },
                       eyes: L.eyes, chin: (arc, front), neck: (n.0, n.1), edge: edge(p))
    }

    // MARK: Shapes

    /// One shape, in head-local px. `fill` and `stroke` are colour roles (the keys of `Theme.Outfits`, or "edge" for the coat's thin edge); `a` the alpha; `sw` the stroke width (0 with no
    /// stroke); `fine` a detail (a glint, a star, a rib) that a cat under Ø28 leaves out. A curve has no fill; an ellipse has a centre, two radii and a rotation instead of points.
    struct Shape {
        enum Kind: String { case poly, curve, ellipse }
        var k: Kind
        var slot: String
        var fill: String?
        var stroke: String?
        var sw: Double
        var a: Double
        var fine: Bool
        var pts: [Pt] = []
        var x = 0.0, y = 0.0, rx = 0.0, ry = 0.0, rot = 0.0

        var json: [String: Any] {
            var out: [String: Any] = ["k": k.rawValue, "slot": slot, "sw": sw, "a": a, "fine": fine]
            if let stroke { out["stroke"] = stroke }
            if k != .curve, let fill { out["fill"] = fill }
            if k == .ellipse { out["x"] = x; out["y"] = y; out["rx"] = rx; out["ry"] = ry; out["rot"] = rot } else { out["pts"] = pts.map { [$0.x, $0.y] } }
            return out
        }
    }

    /// A digest of a list of shapes that two implementations compare within the contract's tolerance: how many shapes and points, the box that holds them (an ellipse counts as its
    /// axis-aligned box and its centre as a point; a stroke's width is not counted) and the mean of every point's x and of every y.
    static func digest(_ shapes: [Shape]) -> [String: Any] {
        var pts = 0, sx = 0.0, sy = 0.0, x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
        func add(_ x: Double, _ y: Double) { pts += 1; sx += x; sy += y; x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) }
        for sh in shapes {
            if sh.k == .ellipse {
                add(sh.x, sh.y)
                x0 = min(x0, sh.x - sh.rx); x1 = max(x1, sh.x + sh.rx); y0 = min(y0, sh.y - sh.ry); y1 = max(y1, sh.y + sh.ry)
            } else {
                for q in sh.pts { add(q.x, q.y) }
            }
        }
        if shapes.isEmpty { return ["n": 0, "pts": 0, "bbox": [0.0, 0.0, 0.0, 0.0], "mx": 0.0, "my": 0.0] }
        return ["n": shapes.count, "pts": pts, "bbox": [x0, y0, x1, y1], "mx": sx / Double(pts), "my": sy / Double(pts)]
    }

    // MARK: Geometry

    /// The shapes of one outfit on one cat, in paint order. An ID that is not one of the 16 drawn outfits (`none`, `auto`, anything else) gives none. A hat rises from the crown by a natural
    /// height, shortened to `o.room` but never below the floor (`Min.height`); a shape marked `fine` is left out below Ø28.
    static func geometry(_ id: String, _ p: CatPreset, _ s: CatPose, D: Double, _ o: Options = Options()) -> [Shape] {
        guard Wardrobe.drawn.contains(id) else { return [] }
        let A = anchors(p, s, D: D, o)
        let R = A.R, dpr = A.dpr, top = A.top, full = A.full
        let fHeight = Min.height / dpr, fLine = Min.line / dpr, fRim = Min.rim / dpr, fBall = Min.ball / dpr, fSpan = Min.span / dpr
        let ln = max(fLine, 0.03 * R), g = A.half, ca = cos(A.lean), sa = sin(A.lean), TAU = CatMath.tau
        let room = (o.room ?? Self.room(topY: top.y, headY: o.headY, ceiling: o.ceiling)).flatMap { $0.isFinite ? $0 : nil } ?? Double.infinity
        var out: [Shape] = []

        func Q(_ x: Double, _ y: Double, _ b: Pt? = nil) -> Pt { let b = b ?? top; return (b.x + x * ca - y * sa, b.y + x * sa + y * ca) }
        func hatH(_ nat: Double) -> Double { max(fHeight, min(nat * R, room)) }
        /// How a shape is outlined: `stroke` is a colour role (default the coat's edge) or nil for none; `sw` defaults to the thin line.
        struct St { var stroke: String? = "edge"; var sw: Double?; var a = 1.0; var fine = false }
        func poly(_ slot: String, _ pts: [Pt], _ fill: String?, _ st: St = St()) {
            out.append(Shape(k: .poly, slot: slot, fill: fill, stroke: st.stroke, sw: st.stroke == nil ? 0 : (st.sw ?? ln), a: st.a, fine: st.fine, pts: pts))
        }
        func curve(_ slot: String, _ pts: [Pt], _ stroke: String, _ sw: Double, _ st: St = St()) {
            out.append(Shape(k: .curve, slot: slot, fill: nil, stroke: stroke, sw: max(sw, fLine), a: st.a, fine: st.fine, pts: pts))
        }
        func ell(_ slot: String, _ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ rot: Double, _ fill: String?, _ st: St = St()) {
            out.append(Shape(k: .ellipse, slot: slot, fill: fill, stroke: st.stroke, sw: st.stroke == nil ? 0 : (st.sw ?? ln), a: st.a, fine: st.fine, x: x, y: y, rx: rx, ry: ry, rot: rot))
        }
        func arcPts(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, _ n: Int = 10) -> [Pt] {
            (0...n).map { i in let a = a0 + (a1 - a0) * Double(i) / Double(n); return (cx + cos(a) * rx, cy + sin(a) * ry) }
        }
        func star(_ cx: Double, _ cy: Double, _ ro: Double, _ ri: Double) -> [Pt] {
            (0..<10).map { i in let r = i % 2 == 1 ? ri : ro, a = -Double.pi / 2 + Double(i) * Double.pi / 5; return (cx + cos(a) * r, cy + sin(a) * r) }
        }
        /// A stadium shape, `w` its outer half width.
        func pill(_ slot: String, _ w: Double, _ yc: Double, _ hh: Double, _ fill: String?) {
            poly(slot, (arcPts(w - hh, yc, hh, hh, -Double.pi / 2, Double.pi / 2, 6) + arcPts(hh - w, yc, hh, hh, Double.pi / 2, Double.pi * 1.5, 6)).map { Q($0.x, $0.y) }, fill)
        }
        func ear(_ sd: Double) -> EarAnchor { A.ears.first { $0.sd == sd }! }
        func ball(_ r: Double) -> Double { max(fBall, r) }
        /// A tapered leaf along a centre line: `c(t)` the centre, `w(t)` the half width, both for t from 0 to 1.
        func leaf(_ c: (Double) -> Pt, _ w: (Double) -> Double, _ n: Int = 14) -> [Pt] {
            var l: [Pt] = [], r: [Pt] = []
            for i in 0...n {
                let t = Double(i) / Double(n), a = c(t), b = c(min(1, t + 0.02)), d = c(max(0, t - 0.02)), tx = b.x - d.x, ty = b.y - d.y, len = hypot(tx, ty) == 0 ? 1 : hypot(tx, ty)
                let nx = -ty / len, ny = tx / len, ww = w(t)
                l.append((a.x + nx * ww, a.y + ny * ww)); r.append((a.x - nx * ww, a.y - ny * ww))
            }
            return l + r.reversed()
        }

        switch id {
        // Hats: they stand between the ear bases, so they are as wide as the gap and no wider.
        case "partyhat":
            let Hh = hatH(1.35), b: Pt = (top.x, top.y + 0.05 * R), w = 0.7, tx = 0.3
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            func Lf(_ t: Double) -> Pt { H(-w + (tx + w) * t, -t) }
            func Rt(_ t: Double) -> Pt { H(w + (tx - w) * t, -t) }
            let tip = H(tx, -1)
            poly("top", arcPts(0, 0, w * g, 0.1 * R, Double.pi, 0, 8).map { Q($0.x, -$0.y, b) } + [tip], "partyA")
            for (t0, t1) in [(0.16, 0.32), (0.5, 0.64)] { poly("top", [Lf(t0), Lf(t1), Rt(t1), Rt(t0)], "partyB", St(stroke: nil)) }
            poly("top", star(tip.x, tip.y - 0.04 * R, 0.2 * R, 0.09 * R), "partyStar", St(sw: ln, fine: true))
        case "santahat":
            let Hh = hatH(0.95), b: Pt = (top.x, top.y + 0.1 * R), hw = 0.82
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            poly("top", [H(-hw, 0), H(-0.74, -0.45), H(-0.4, -0.86), H(0, -1), H(0.42, -0.88), H(0.74, -0.5), H(hw, 0)], "santaRed")
            func c(_ t: Double) -> Pt { let m = 1 - t; return H(2 * m * t * (-0.5) + t * t * (-0.58), m * m * (-0.95) + 2 * m * t * (-1.02) + t * t * (-0.5)) }
            let tip = c(1)
            poly("top", leaf(c, { (0.26 - 0.18 * $0) * g }, 10), "santaRed", St(stroke: nil))
            ell("top", tip.x, tip.y, ball(0.17 * R), ball(0.17 * R), 0, "fur")
            pill("top", 0.95 * g, 0, max(fLine * 2, 0.12 * R), "fur")
        case "witchhat":
            let Hh = hatH(1.5), b: Pt = (top.x, top.y + 0.04 * R)
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            let brim = Q(0, 0, b)
            ell("top", brim.x, brim.y, 0.95 * g, max(0.12 * R, fLine * 2), A.lean, "witchHat")
            poly("top", [H(-0.52, 0), H(-0.36, -0.4), H(-0.08, -0.72), H(0.1, -0.82), H(0.62, -1), H(0.4, -0.66), H(0.34, -0.45), H(0.52, 0)], "witchHat")
            poly("top", [H(-0.5, -0.1), H(0.5, -0.1), H(0.45, -0.3), H(-0.42, -0.3)], "witchBand", St(stroke: nil))
            poly("top", [H(-0.12, -0.06), H(0.12, -0.06), H(0.12, -0.34), H(-0.12, -0.34)], "gold", St(sw: ln))
        case "bunnyears":
            let cm = !full, Hh = hatH(cm ? 1.9 : 1.45), b: Pt = (top.x, top.y + (cm ? 0.1 : 0.5) * R)
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            // Below Ø28 the ears are taller (their base sits nearer the crown) and wider, so they show above the head at Ø18 and Ø20; the open size is unchanged.
            for sd in [-1.0, 1.0] {
                let bend = sd > 0 ? 0.9 : 0, wm = max((cm ? 0.5 : 0.3) * g, fSpan / 2)
                func c(_ t: Double) -> Pt { H(sd * (0.4 + 0.22 * t) + bend * pow(max(0, t - 0.55), 2) * 1.2, -t) }
                func w(_ t: Double) -> Double { wm * pow(sin(Double.pi * (0.2 + 0.8 * t)), 0.8) }
                poly("behind", leaf(c, w), "bunnyOuter")
                poly("behind", leaf({ c(0.06 + 0.74 * $0) }, { w(0.06 + 0.74 * $0) * 0.55 }), "bunnyInner", St(stroke: nil))
            }
        case "beanie":
            let Hh = hatH(0.78), b: Pt = (top.x, top.y + 0.26 * R), hw = 0.95
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            poly("top", arcPts(0, 0, hw, 1, Double.pi, Double.pi * 2, 14).map { H($0.x, $0.y) }, "beanieBody")
            for x in [-0.5, 0, 0.5] { curve("top", [H(x * 0.9, -0.15), H(x, -0.62), H(x * 0.5, -0.92)], "beanieCuff", ln * 0.9, St(a: 0.7, fine: true)) }
            pill("top", 0.96 * g, 0, max(0.14 * R, fSpan / 2), "beanieCuff")
            let t = H(0, -1.0)
            ell("top", t.x, t.y - 0.04 * R, ball(0.17 * R), ball(0.17 * R), 0, "fur")
        case "crown":
            let Hh = hatH(0.55), b: Pt = (top.x, top.y + 0.12 * R), hw = 0.7
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            poly("top", [H(-hw, 0), H(-hw, -0.72), H(-0.4, -0.4), H(0, -1), H(0.4, -0.4), H(hw, -0.72), H(hw, 0)], "gold")
            poly("top", [H(-hw, 0), H(hw, 0), H(hw, -0.22), H(-hw, -0.22)], "goldDark", St(stroke: nil, a: 0.85))
            for (x, y, r) in [(-hw, -0.72, "gemA"), (0, -1.0, "gemB"), (hw, -0.72, "gemC")] {
                let q = H(x, y), gr = ball(0.09 * R)
                ell("top", q.x, q.y + gr, gr, gr, 0, r)
            }
        // Glasses: they follow the eye frames and flatten with the face turn.
        case "sunglasses", "roundglasses":
            let sun = id == "sunglasses", E = p.eye
            let lr = (sun ? 1.75 : 1.95) * E.w * R, lv = (sun ? 1.55 : 1.7) * max(E.h, 0.85 * E.w) * R, fr = max(fRim, sun ? 0.06 * R : 0.045 * R)
            let eyes = A.eyes.filter(\.visible)
            for e in eyes {
                let rx = max(lr * e.fx, fBall), ry = max(lv * e.fy, fBall)
                if sun {
                    // A dark head: the frame's dark would vanish, so a thin light rim (the edge role) outlines the lens.
                    ell("top", e.x, e.y, rx, ry, 0, "lens", A.edge == "light" ? St(stroke: "edge", sw: ln, a: 0.93) : St(stroke: "frame", sw: fr, a: 0.93))
                    poly("top", [(e.x - rx * 0.5, e.y - ry * 0.15), (e.x - rx * 0.12, e.y - ry * 0.62), (e.x + rx * 0.12, e.y - ry * 0.62), (e.x - rx * 0.3, e.y + ry * 0.08)], "glint", St(stroke: nil, a: 0.55, fine: true))
                } else {
                    ell("top", e.x, e.y, rx, ry, 0, "glassTint", St(stroke: "rim", sw: fr, a: 0.22))
                    ell("top", e.x, e.y, rx, ry, 0, nil, St(stroke: "rim", sw: fr))
                    curve("top", arcPts(e.x, e.y, rx * 0.72, ry * 0.72, Double.pi * 1.05, Double.pi * 1.4, 5), "glint", ln, St(a: 0.8, fine: true))
                }
            }
            if eyes.count == 2 {
                let sorted = eyes.sorted { $0.sd < $1.sd }, a = sorted[0], b = sorted[1]
                let ax = a.x + max(lr * a.fx, fBall), bx = b.x - max(lr * b.fx, fBall), my = (a.y + b.y) / 2
                curve("top", [(ax, a.y), ((ax + bx) / 2, my - (sun ? 0.06 : 0.1) * R), (bx, b.y)], sun ? "frame" : "rim", fr)
            }
            for e in eyes.sorted(by: { $0.sd < $1.sd }) {
                let ox = e.x + e.sd * max(lr * e.fx, fBall)
                curve("top", [(ox, e.y - lv * e.fy * 0.2), (ox + e.sd * 0.3 * R * e.fx, e.y - lv * e.fy * 0.05)], sun ? "frame" : "rim", fr)
            }
        // Clips, the bow and the flower: at an ear base, turning with the ear.
        case "bow":
            let e = ear(1), cx = e.bx - 0.12 * R, cy = e.by + 0.02 * R, u = max(R * 0.9, fSpan * 1.6), rot = e.rot * 0.6
            for sd in [-1.0, 1.0] { ell("top", cx + sd * 0.3 * u * cos(rot), cy + sd * 0.3 * u * sin(rot), 0.3 * u, 0.21 * u, rot + sd * 0.35, "bowRed") }
            poly("top", [(cx - 0.05 * u, cy + 0.1 * u), (cx - 0.2 * u, cy + 0.55 * u), (cx - 0.05 * u, cy + 0.45 * u)], "bowKnot", St(fine: true))
            poly("top", [(cx + 0.05 * u, cy + 0.1 * u), (cx + 0.2 * u, cy + 0.55 * u), (cx + 0.05 * u, cy + 0.45 * u)], "bowKnot", St(fine: true))
            ell("top", cx, cy, ball(0.1 * u), ball(0.1 * u), 0, "bowKnot")
        case "fishclip":
            let e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.1 * R, u = max(R, fSpan * 1.7), rot = e.rot * 0.5
            ell("top", cx, cy, 0.27 * u, 0.13 * u, rot, "fishBody")
            poly("top", [(cx + 0.25 * u * cos(rot), cy + 0.25 * u * sin(rot)), (cx + 0.45 * u, cy - 0.14 * u), (cx + 0.45 * u, cy + 0.14 * u)], "fishFin")
            ell("top", cx - 0.13 * u, cy - 0.02 * u, 0.025 * u, 0.025 * u, 0, "lens", St(stroke: nil, fine: true))
        case "flower":
            let e = ear(1), cx = e.bx - 0.22 * R, cy = e.by + 0.1 * R, u = max(R, fSpan * 1.7)
            for i in 0..<5 { let a = -Double.pi / 2 + Double(i) * TAU / 5; ell("top", cx + cos(a) * 0.15 * u, cy + sin(a) * 0.15 * u, ball(0.13 * u), ball(0.09 * u), a, "petal") }
            ell("top", cx, cy, ball(0.07 * u), ball(0.07 * u), 0, "gold", St(sw: ln))
        case "shrimpclip":
            let e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.12 * R, u = max(R, fSpan * 1.7)
            if !full {
                // Below Ø28 (the detail cut) the shrimp is simple and bold: one thick curled C, one fanned tail with three tips, both in the shrimp colour with the edge round them.
                let r = 0.3 * u, sw = max(0.2 * u, fSpan / 2), a0 = Double.pi * 0.25, a1 = Double.pi * 1.45
                let tx = cx + r * cos(a1), ty = cy + r * sin(a1), td = (x: -sin(a1), y: cos(a1)), nd = (x: cos(a1), y: sin(a1)), L = 0.55 * u, w = 0.22 * u
                func at(_ a: Double, _ b: Double) -> Pt { (tx + a * td.x + b * nd.x, ty + a * td.y + b * nd.y) }
                curve("top", arcPts(cx, cy, r, r, a0, a1, 10), "edge", sw + 2 * ln)
                curve("top", arcPts(cx, cy, r, r, a0, a1, 10), "shrimp", sw)
                poly("top", [at(0, w * 0.5), at(L * 0.9, w), at(L * 0.45, w * 0.35), at(L * 1.1, 0), at(L * 0.45, -w * 0.35), at(L * 0.9, -w), at(0, -w * 0.5)], "shrimp")
            } else {
                let r = 0.15 * u, sw = max(0.12 * u, fSpan / 2)
                // a curled, segmented body: four segments along a C, a fine dark joint between each pair
                for i in 0..<4 { let a0 = Double.pi * (0.25 + Double(i) * 0.3); curve("top", arcPts(cx, cy, r, r, a0, a0 + Double.pi * 0.3, 4), "shrimp", sw) }
                for i in 1..<4 { let a = Double.pi * (0.25 + Double(i) * 0.3); curve("top", [(cx + 0.8 * r * cos(a), cy + 0.8 * r * sin(a)), (cx + 1.25 * r * cos(a), cy + 1.25 * r * sin(a))], "shrimpDark", ln) }
                // a fanned tail: three spikes, between notches, off the end of the C
                let a1 = Double.pi * 1.45, tx = cx + r * cos(a1), ty = cy + r * sin(a1)
                poly("top", [(tx, ty), (tx + 0.2 * u, ty - 0.14 * u), (tx + 0.13 * u, ty - 0.03 * u), (tx + 0.26 * u, ty), (tx + 0.13 * u, ty + 0.03 * u), (tx + 0.2 * u, ty + 0.14 * u)], "shrimp")
                poly("top", [(tx, ty), (tx + 0.2 * u, ty - 0.12 * u), (tx + 0.12 * u, ty - 0.02 * u)], "shrimpDark", St(fine: true))
                // two small feelers from the head end of the C
                let a2 = Double.pi * 0.25, hx = cx + r * cos(a2), hy = cy + r * sin(a2)
                curve("top", [(hx, hy), (hx + 0.1 * u, hy - 0.16 * u)], "shrimpDark", ln)
                curve("top", [(hx, hy), (hx + 0.04 * u, hy - 0.2 * u)], "shrimpDark", ln)
            }
        case "blossomclip":
            let e = ear(1), cx = e.bx - 0.22 * R, cy = e.by + 0.1 * R, u = max(R, fSpan * 1.7)
            for sd in [-1.0, 1.0] { ell("top", cx + sd * 0.2 * u, cy + 0.14 * u, ball(0.13 * u), ball(0.06 * u), sd * 0.6, "leaf") }
            for i in 0..<5 { let a = -Double.pi / 2 + Double(i) * TAU / 5; ell("top", cx + cos(a) * 0.13 * u, cy + sin(a) * 0.13 * u, ball(0.11 * u), ball(0.11 * u), a, i % 2 == 1 ? "blossomDeep" : "blossom") }
            ell("top", cx, cy, ball(0.05 * u), ball(0.05 * u), 0, "gold", St(stroke: nil))
        // Neck: over the collar.
        default:
            func inw(_ q: Pt, _ d: Double) -> Pt { let l = hypot(q.x, q.y) == 0 ? 1 : hypot(q.x, q.y); return (q.x * (1 - d / l), q.y * (1 - d / l)) }
            let pts = A.chin.pts.map { inw($0, 0.12 * R) }
            if id == "scarf" {
                let wd = max(0.42 * R, fSpan)
                curve("neck", pts, "edge", wd + 2 * ln, St(a: 0.9))
                curve("neck", pts, "scarfA", wd)
                curve("neck", pts.map { inw($0, -0.1 * R) }, "scarfB", max(0.07 * R, fLine * 1.5))
                curve("neck", pts.map { inw($0, 0.1 * R) }, "scarfB", max(0.07 * R, fLine * 1.5))
                let t0 = pts[5], tw = max(0.27 * R, fSpan), tl = 0.5 * R
                poly("neck", [(t0.x - tw / 2, t0.y - 0.05 * R), (t0.x + tw / 2, t0.y - 0.05 * R), (t0.x + tw / 2 - 0.06 * R, t0.y + tl), (t0.x - tw / 2 - 0.06 * R, t0.y + tl)], "scarfA")
                poly("neck", [(t0.x - tw / 2 - 0.015 * R, t0.y + tl * 0.55), (t0.x + tw / 2 - 0.045 * R, t0.y + tl * 0.55), (t0.x + tw / 2 - 0.05 * R, t0.y + tl * 0.7), (t0.x - tw / 2 - 0.02 * R, t0.y + tl * 0.7)], "scarfB", St(stroke: nil))
            } else if id == "bandana" {
                let apex: Pt = (A.chin.front.x, (pts.map(\.y).max() ?? 0) + 0.48 * R)
                poly("neck", pts.map { inw($0, -0.06 * R) } + [apex], "bandanaRed")
                let kn = pts[2]
                poly("neck", [(kn.x - 0.12 * R, kn.y), (kn.x - 0.4 * R, kn.y + 0.3 * R), (kn.x - 0.05 * R, kn.y + 0.26 * R)], "bandanaRed")
                ell("neck", kn.x, kn.y, ball(0.1 * R), ball(0.1 * R), 0, "bandanaRed")
                for (x, y) in [(0.0, 0.34), (-0.28, 0.18), (0.28, 0.18)] { ell("neck", A.chin.front.x + x * R, A.chin.front.y + y * R, ball(0.045 * R), ball(0.045 * R), 0, "white", St(stroke: nil, fine: true)) }
            } else {
                // The bell hangs from the collar: the tag's lower edge, the middle of the band, the kerchief's apex, or its own ring at the front of the neck with the collar off.
                let C = G.collarGeometry(p, s, D: D, style: o.collar, dpr: A.dpr, detail: o.detail)
                var at: Pt = A.neck
                if let tag = C?.tag { at = (tag.x, tag.y + tag.r) } else if let band = C?.band { at = band[band.count >> 1] } else if let kerchief = C?.kerchief { at = kerchief.apex }
                let r = ball(0.2 * R)
                ell("neck", at.x, at.y - 0.1 * R, ball(0.07 * R), ball(0.07 * R), 0, nil, St(stroke: "silver", sw: max(ln * 1.4, fLine)))
                ell("neck", at.x, at.y + 0.12 * R, r, r, 0, "gold")
                curve("neck", [(at.x - r * 0.7, at.y + 0.1 * R), (at.x + r * 0.7, at.y + 0.1 * R)], "goldDark", ln, St(fine: true))
                ell("neck", at.x, at.y + 0.12 * R + r * 0.55, ball(0.04 * R), ball(0.04 * R), 0, "goldDark", St(stroke: nil, fine: true))
            }
        }
        return full ? out : out.filter { !$0.fine }
    }
}
```


- [ ] **Step 4: Run it to see it pass**

Run: `bash scripts/test-wardrobe-geometry.sh 2>&1 | grep -v "✓"`
Expected: PASS, the section titles (`outfitAnchors: 32 cases`, `outfitGeometry: 4 pinned cases`, `outfitDigest: 1024 pairs (…)`, `the collar: …`, `a stranger, and the detail cut`, `the compact notch: every outfit on every coat at Ø20 and Ø18`) and `All tests passed.` Nothing red: the port matches the fixture to 1e-9 on every number.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/CatOutfit.swift tests/WardrobeGeometryTests.swift scripts/test-wardrobe-geometry.sh
printf '%s\n' 'feat(wardrobe): the anchors and the shapes of the 16 outfits (I-mac task 3)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 4: The drawing at the three slots, and the sheets (step 3)

`CatOutfitDraw` paints the shapes into the head's frame; `CatRenderer` builds them for a cat in the big-cat role and paints them at the three slots; `CatDrawOptions.outfit` carries the outfit and its role (a plain struct in `CatLook.swift`, so every file that draws a cat can take it without the wardrobe). The renderer fits the outfit to the ears **as drawn** (after the ear fit) and, in the compact notch, to the strip's room. Six scripts compile `CatRenderer` and gain the three new files. `render-cats.sh --wardrobe` draws the contact sheets that checkpoint 1 looks at, laid out like the prototype's Wardrobe panel.

**Interfaces.** Consumes: `CatOutfit` (Task 3), `Wardrobe` (Task 1), `Theme.Outfits`. Produces: `CatOutfitPaint` (`id`, `role`, `dpr`, `fade`), `CatDrawOptions.outfit`, `CatOutfitDraw.big(_ id:, dpr:, fade:) -> CatOutfitPaint?`, `.dressed(…)`, `.paint(_ cg, _ dressed, slot:)`, `.hex(_ role, edge:)`, `.marker`, `CatDressed`; `RenderCats.sheetOutfit`, `.dressedCat(…)`, `.wardrobeSheet(_ a)`.

- [ ] **Step 1: Write the test and its script**

**Create `tests/WardrobeDrawTests.swift`**

```swift
import CoreGraphics
import Foundation

@main
enum WardrobeDrawTests {
    static func ink(_ px: [UInt8]) -> Int { stride(from: 3, to: px.count, by: 4).reduce(0) { $0 + Int(px[$1]) } }

    /// One cat drawn into a bitmap, with or without an outfit.
    @MainActor static func draw(_ cat: String, D: Double, w: Int = 160, h: Int = 160, paint: CatOutfitPaint? = nil, collar: CatCollarPaint? = nil, ceiling: Double? = nil, cy: Double? = nil, pose: CatPose = CatPose()) -> [UInt8] {
        Bitmap.render(w, h) { cg in
            var o = CatDrawOptions(badge: false)
            o.outfit = paint; o.collar = collar; o.earCeiling = ceiling
            CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(cat), pose: pose), cx: Double(w) / 2, cy: cy ?? Double(h) / 2, D: D, o)
        }
    }

    @MainActor static func main() {
        CT.section("colour roles: every role an outfit uses is a colour")
        var unknown = Set<String>()
        for cat in CatPresets.ids {
            let p = CatPresets.byID(cat)
            for id in Wardrobe.drawn {
                for D in [18.0, 27.0, 28.0, 64.0] {
                    for sh in CatOutfit.geometry(id, p, CatPose(), D: D, CatOutfit.Options(dpr: 2, collar: "tag")) {
                        for role in [sh.fill, sh.stroke].compactMap({ $0 }) where CatOutfitDraw.hex(role, edge: "light") == nil || CatOutfitDraw.hex(role, edge: "dark") == nil { unknown.insert(role) }
                    }
                }
            }
        }
        CT.check("no role is unknown (16 outfits, 16 coats, four sizes)", unknown.sorted(), [])
        CT.check("the coat's edge is the theme's light or dark edge", [CatOutfitDraw.hex("edge", edge: "light"), CatOutfitDraw.hex("edge", edge: "dark")], [Theme.Outfits.edgeLight, Theme.Outfits.edgeDark])
        CT.check("a role that is not one has no colour", CatOutfitDraw.hex("fancy", edge: "dark"), nil)
        CT.check("the marker the binary check looks for is 19 bytes long", [CatOutfitDraw.marker, "\(CatOutfitDraw.marker.utf8.count)"], ["NM_WARDROBE_OUTFITS", "19"])

        CT.section("who wears it: the role decides, never the diameter")
        let bare = draw("momo", D: 64)
        let big = draw("momo", D: 64, paint: CatOutfitDraw.big("santahat", dpr: 1))
        CT.checkTrue("a big cat in a Santa hat is not the bare cat", big != bare && ink(big) > ink(bare))
        for role in ["small", "kitten", "Big", " big", "", "desktop"] {
            CT.checkTrue("a cat in the role \"\(role)\" is bare, pixel for pixel", draw("momo", D: 64, paint: CatOutfitPaint(id: "santahat", role: role, dpr: 1)) == bare)
        }
        let tiny = draw("momo", D: 12, w: 40, h: 40), tinyBig = draw("momo", D: 12, w: 40, h: 40, paint: CatOutfitDraw.big("crown", dpr: 1))
        CT.checkTrue("a big-cat role at Ø12 is dressed, and a small cat at Ø66 is not", tiny != tinyBig && draw("momo", D: 66, paint: CatOutfitPaint(id: "crown", role: "small", dpr: 1)) == draw("momo", D: 66))
        CT.check("none, auto and a made-up name are no outfit", [CatOutfitDraw.big("none", dpr: 1) == nil, CatOutfitDraw.big("auto", dpr: 1) == nil, CatOutfitDraw.big("fancyhat", dpr: 1) == nil], [true, true, true])
        let p = CatPresets.byID("momo")
        CT.checkTrue("a bare cat costs no geometry: the role is checked first", CatOutfitDraw.dressed(CatOutfitPaint(id: "crown", role: "small", dpr: 2), p, CatPose(), D: 64, full: true, earScale: 1, collar: nil, headY: 80, ceiling: nil) == nil)
        CT.checkTrue("and a fade of 0 costs none either", CatOutfitDraw.dressed(CatOutfitDraw.big("crown", dpr: 2, fade: 0), p, CatPose(), D: 64, full: true, earScale: 1, collar: nil, headY: 80, ceiling: nil) == nil)

        CT.section("the fade: the greeting puts the outfit on once the cat has settled")
        let half = draw("momo", D: 64, paint: CatOutfitDraw.big("santahat", dpr: 1, fade: 0.5))
        CT.checkTrue("0 is bare", draw("momo", D: 64, paint: CatOutfitDraw.big("santahat", dpr: 1, fade: 0)) == bare)
        CT.checkTrue("half shows between bare and full", ink(bare) < ink(half) && ink(half) < ink(big))

        CT.section("every outfit on every coat, big, at Ø64 and at the compact notch's Ø20")
        var blank: [String] = [], same: [String] = [], above: [String] = []
        for cat in CatPresets.ids {
            for id in Wardrobe.drawn {
                let a = draw(cat, D: 64), b = draw(cat, D: 64, paint: CatOutfitDraw.big(id, dpr: 1))
                if b == a { blank.append("\(id) on \(cat) Ø64") }
                // The notch's Ø20 cat: a strip from y 20 to 52 (the island's top is the screen's top), the ears fitted under it, the outfit given the same room.
                let c = draw(cat, D: 20, w: 60, h: 80, ceiling: 20, cy: 36), d = draw(cat, D: 20, w: 60, h: 80, paint: CatOutfitDraw.big(id, dpr: 2), ceiling: 20, cy: 36)
                if c == d { blank.append("\(id) on \(cat) Ø20") }
                if let top = Bitmap.bounds(d, 60)?.top, top < 19 { above.append("\(id) on \(cat) Ø20 reaches row \(top)") }
                if Bitmap.bounds(d, 60) == nil { same.append("\(id) on \(cat) is empty") }
            }
        }
        CT.checkRows("each one changes the picture (256 pairs at Ø64 and at Ø20)", blank)
        CT.checkRows("and never draws above the strip at Ø20 (a pixel of anti-aliasing allowed)", above)
        CT.checkRows("and the picture is never empty", same)

        CT.section("the collar is drawn first and never changed")
        let tag = CatCollarPaint(style: "tag", color: "#E07950", dpr: 1)
        let collared = draw("momo", D: 64, paint: nil, collar: tag), bell = draw("momo", D: 64, paint: CatOutfitDraw.big("bell", dpr: 1), collar: tag), bellOff = draw("momo", D: 64, paint: CatOutfitDraw.big("bell", dpr: 1))
        CT.checkTrue("a bell over a collar and a bell with the collar off both draw", bell != collared && bellOff != bare)
        let hat = draw("momo", D: 64, paint: CatOutfitDraw.big("crown", dpr: 1), collar: tag), lower = 80 * 160 * 4   // the head's middle and down: the crown sits above it
        CT.checkTrue("a hat leaves the pixels from the head's middle down, collar included, as they were", Array(hat[lower...]) == Array(collared[lower...]))
        CT.finish()
    }
}
```

**Create `scripts/test-wardrobe-draw.sh`**

```bash
#!/usr/bin/env bash
# Wardrobe drawing (sub-project I): every colour role is a colour, only the big-cat role wears an outfit (never a small cat or a kitten, whatever the diameter), the fade, and all 16 outfits
# on all 16 coats drawn big at Ø64 and at the compact notch's Ø20 (each changes the picture, none reaches above the strip), drawn into bitmaps by the real CatRenderer.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-draw.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/WardrobeDrawTests.swift \
    -o "$TEST_DIR/wardrobe-draw-tests"
"$TEST_DIR/wardrobe-draw-tests"
```


```bash
chmod +x scripts/test-wardrobe-draw.sh
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-wardrobe-draw.sh 2>&1 | tail -3`
Expected: FAIL, `error opening input file 'NotchBuddy/Sources/App/CatOutfitDraw.swift'`.

- [ ] **Step 3: Write the painter, the options and the three slots**

**Create `NotchBuddy/Sources/App/CatOutfitDraw.swift`**

```swift
import CoreGraphics
import Foundation

// Paints an outfit (sub-project I): the shapes `CatOutfit.geometry` returns, into the head's frame, at the three slots the renderer calls (`behind` after the ears, `neck` after the collar,
// `top` after `neck`, always before the whiskers). The painter only paints: it never reads a coat, and the maths is `CatOutfit`. The colours are the roles of `Theme.Outfits`
// (shared/theme.json, generated); the coat itself is never recoloured. In the head's frame, so it turns, tilts and squashes with the head.

/// The shapes of one outfit on one cat in one pose, ready to paint.
struct CatDressed {
    var shapes: [CatOutfit.Shape]
    var edge: String
    var fade: Double
}

@MainActor
enum CatOutfitDraw {
    /// In every build (Debug, Release and App Store): `scripts/check-app-binary.sh` looks for it (20 bytes: a shorter string would hide in the code where `strings` cannot see it).
    static let marker = "NM_WARDROBE_OUTFITS"

    /// The outfit for a cat in the big-cat role: `id` is the resolved outfit (`CatConfig.outfit`); nil for `none` and anything that is not one of the 16 drawn outfits. This is what the
    /// five big-cat views call; the small cats and the kittens never do.
    static func big(_ id: String, dpr: Double, fade: Double = 1) -> CatOutfitPaint? {
        Wardrobe.drawn.contains(id) ? CatOutfitPaint(id: id, role: "big", dpr: dpr, fade: fade) : nil
    }

    /// The outfit for a draw, or nil when the cat is bare: not in a big-cat role, no outfit, or nothing to draw. `ek` is the ears' scale as the renderer drew them; `headY` and `ceiling`
    /// are the compact notch's strip, which gives hats and bunny ears the room the ears get.
    static func dressed(_ paint: CatOutfitPaint?, _ p: CatPreset, _ s: CatPose, D: Double, full: Bool, earScale ek: Double, collar: String?, headY: Double, ceiling: Double?) -> CatDressed? {
        guard let paint, Wardrobe.worn(paint.role), paint.fade > 0.001 else { return nil }
        var o = CatOutfit.Options(dpr: paint.dpr, detail: full ? "full" : "compact", earScale: ek, collar: collar ?? "off")
        o.headY = headY; o.ceiling = ceiling
        let shapes = CatOutfit.geometry(paint.id, p, s, D: D, o)
        guard !shapes.isEmpty else { return nil }
        return CatDressed(shapes: shapes, edge: CatOutfit.edge(p), fade: min(1, paint.fade))
    }

    /// Paints the shapes of one slot, in order, into the head's frame.
    static func paint(_ cg: CGContext, _ d: CatDressed, slot: String) {
        for sh in d.shapes where sh.slot == slot {
            let path = CGMutablePath()
            switch sh.k {
            case .ellipse:
                path.addEllipse(in: CGRect(x: -max(sh.rx, 0.01), y: -max(sh.ry, 0.01), width: 2 * max(sh.rx, 0.01), height: 2 * max(sh.ry, 0.01)), transform: CGAffineTransform(rotationAngle: sh.rot).concatenating(CGAffineTransform(translationX: sh.x, y: sh.y)))
            case .poly, .curve:
                for (i, q) in sh.pts.enumerated() { i == 0 ? path.move(to: CGPoint(x: q.x, y: q.y)) : path.addLine(to: CGPoint(x: q.x, y: q.y)) }
                if sh.k == .poly { path.closeSubpath() }
            }
            let alpha = sh.a * d.fade
            if let fill = sh.fill, let hex = hex(fill, edge: d.edge) { cg.fill(path, CatDraw.color(hex, alpha: alpha)) }
            if let stroke = sh.stroke, sh.sw > 0, let hex = hex(stroke, edge: d.edge) { cg.stroke(path, CatDraw.color(hex, alpha: alpha), width: sh.sw) }
        }
    }

    /// A colour role as "#RRGGBB": the keys of `Theme.Outfits`, and "edge" for the coat's thin edge (`light` on a dark head, `dark` on a light one). nil for a role that is not one.
    static func hex(_ role: String, edge: String) -> String? {
        typealias T = Theme.Outfits
        switch role {
        case "edge": return edge == "light" ? T.edgeLight : T.edgeDark
        case "edgeLight": return T.edgeLight
        case "edgeDark": return T.edgeDark
        case "partyA": return T.partyA
        case "partyB": return T.partyB
        case "partyStar": return T.partyStar
        case "santaRed": return T.santaRed
        case "fur": return T.fur
        case "witchHat": return T.witchHat
        case "witchBand": return T.witchBand
        case "gold": return T.gold
        case "goldDark": return T.goldDark
        case "bunnyOuter": return T.bunnyOuter
        case "bunnyInner": return T.bunnyInner
        case "lens": return T.lens
        case "frame": return T.frame
        case "glint": return T.glint
        case "beanieBody": return T.beanieBody
        case "beanieCuff": return T.beanieCuff
        case "bowRed": return T.bowRed
        case "bowKnot": return T.bowKnot
        case "scarfA": return T.scarfA
        case "scarfB": return T.scarfB
        case "rim": return T.rim
        case "glassTint": return T.glassTint
        case "gemA": return T.gemA
        case "gemB": return T.gemB
        case "gemC": return T.gemC
        case "silver": return T.silver
        case "bandanaRed": return T.bandanaRed
        case "white": return T.white
        case "fishBody": return T.fishBody
        case "fishFin": return T.fishFin
        case "petal": return T.petal
        case "shrimp": return T.shrimp
        case "shrimpDark": return T.shrimpDark
        case "blossom": return T.blossom
        case "blossomDeep": return T.blossomDeep
        case "leaf": return T.leaf
        default: return nil
        }
    }
}
```

**Edit `NotchBuddy/Sources/App/CatLook.swift`**

Find:

```swift

struct CatDrawOptions {
```

Replace with:

```swift

/// An outfit to wear on this draw (sub-project I). `role` is who the cat is (`big`, `small` or `kitten`): only `big` wears it, at every size (`Wardrobe.worn`). `CatOutfitDraw.big` makes
/// the paint of a big cat. Plain values, so every file that draws a cat can take it without the wardrobe.
struct CatOutfitPaint {
    /// One of the 16 drawn IDs.
    var id: String
    var role = "small"
    /// Pixels per point, which the readability floors are in (as the collar's).
    var dpr = 2.0
    /// 0 to 1: how much of it shows (the launch greeting puts it on once the cat has settled).
    var fade = 1.0
}

struct CatDrawOptions {
```

**Edit `NotchBuddy/Sources/App/CatLook.swift`**

Find:

```swift
    var collar: CatCollarPaint?
}
```

Replace with:

```swift
    var collar: CatCollarPaint?
    /// The wardrobe (sub-project I): the outfit this cat wears, in the three slots of the passes. nil: bare, which every small cat and every kitten is (`Wardrobe.worn`): the role in the
    /// paint decides, never the diameter.
    var outfit: CatOutfitPaint?
}
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**

Find:

```swift
        var L = layout(ek)
```

Replace with:

```swift
        var L = layout(ek), drawnEk = ek   // drawnEk: the ears' scale as they are drawn (the outfit is fitted to the same ears)
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**

Find:

```swift
            if f < 1 { L = layout(ek * f) }
```

Replace with:

```swift
            if f < 1 { drawnEk = ek * f; L = layout(drawnEk) }
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**

Find:

```swift
        }
        let fur = o.fur && CatFur.shows(p, R: L.R, full: L.full) ? CatFur.strands(for: p) : nil   // the optional fur strands
```

Replace with:

```swift
        }
        // The wardrobe: the outfit of a cat in the big-cat role, in head-local px, painted at three slots below. Bare for every other cat (nil).
        let dressed = CatOutfitDraw.dressed(o.outfit, p, s, D: D, full: full, earScale: drawnEk, collar: o.collar?.style, headY: L.head.y, ceiling: o.earCeiling)
        let fur = o.fur && CatFur.shows(p, R: L.R, full: L.full) ? CatFur.strands(for: p) : nil   // the optional fur strands
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**

Find:

```swift
        drawBehind(cg, look, L, flat, fur)
```

Replace with:

```swift
        drawBehind(cg, look, L, flat, fur, dressed)
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**

Find:

```swift
        drawFront(cg, p, s, L, flat, o.collar)
```

Replace with:

```swift
        drawFront(cg, p, s, L, flat, o.collar, dressed)
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**

Find:

```swift
    private static func drawBehind(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ flat: G.FlatColors?, _ fur: CatFur.Strands?) {
```

Replace with:

```swift
    private static func drawBehind(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ flat: G.FlatColors?, _ fur: CatFur.Strands?, _ dressed: CatDressed?) {
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**

Find:

```swift
        for e in L.ears { drawEar(cg, p, e, R: R, full: L.full, front: false, flat: flat?.ears[e.sd < 0 ? 0 : 1]) }
    }
```

Replace with:

```swift
        for e in L.ears { drawEar(cg, p, e, R: R, full: L.full, front: false, flat: flat?.ears[e.sd < 0 ? 0 : 1]) }
        // The outfit's `behind` slot, after the ears: the bunny ears, so the head covers their roots.
        if let dressed { CatOutfitDraw.paint(cg, dressed, slot: "behind") }
    }
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**

Find:

```swift
    private static func drawFront(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ L: G.Layout, _ flat: G.FlatColors?, _ collar: CatCollarPaint?) {
```

Replace with:

```swift
    private static func drawFront(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ L: G.Layout, _ flat: G.FlatColors?, _ collar: CatCollarPaint?, _ dressed: CatDressed?) {
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**

Find:

```swift
        }
        if L.full && L.fa > 0.01 { CatFace.drawWhiskers(cg, p, s, L) }
```

Replace with:

```swift
        }
        // The outfit's `neck` slot over the collar (scarf, bandana, bell), then its `top` slot (hats, crown, glasses, clips, bow, flower): both under the whiskers, the badge and the particles.
        if let dressed { CatOutfitDraw.paint(cg, dressed, slot: "neck"); CatOutfitDraw.paint(cg, dressed, slot: "top") }
        if L.full && L.fa > 0.01 { CatFace.drawWhiskers(cg, p, s, L) }
```


- [ ] **Step 4: Add the new files to the scripts that compile the renderer**

**Edit `scripts/test-cat-renderer.sh`**

Find:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift \
```

Replace with:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift \
```

**Edit `scripts/test-cat-desktop-devpanel.sh`**

Find:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```

Replace with:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```

**Edit `scripts/gen-icons.sh`**

Find:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift \
```

Replace with:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift \
```

**Edit `scripts/render-cat-settings.sh`**

Find:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```

Replace with:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```

**Edit `scripts/render-cat-panel.sh`**

Find:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```

Replace with:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```


- [ ] **Step 5: Run the drawing test, and the renderer's own tests**

Run: `bash scripts/test-wardrobe-draw.sh 2>&1 | grep -v "✓"`
Expected: PASS: `colour roles…`, `who wears it…`, `the fade…`, `every outfit on every coat, big, at Ø64 and at the compact notch's Ø20`, `the collar is drawn first and never changed` and `All tests passed.`

Run: `for f in test-cat-renderer test-cat-effects test-cat-engine test-cat-desktop-devpanel test-cat-greeting test-cat-fur test-cat-small-eye; do printf '%-34s' $f; bash scripts/$f.sh 2>&1 | tail -1; done`
Expected: seven lines ending `All tests passed.` (a bare cat is drawn exactly as before).

Run: `OUT="${TMPDIR:-/tmp}/i-mac-icons"; bash scripts/gen-icons.sh "$OUT" 2>&1 | tail -1; (cd "$OUT" && find . -type f | while read f; do cmp -s "$f" "$OLDPWD/$f" || echo "DIFF $f"; done); echo checked`
Expected: `wrote the 18 icon files under …` and no `DIFF` line before `checked`: the icons and the menu-bar template are drawn by the renderer with no outfit, and are byte for byte the ones in the repo.

- [ ] **Step 6: Write the sheets**

**Create `scripts/render-cats-wardrobe.swift`**

```swift
import CoreGraphics
import Foundation

// The wardrobe's sheets (sub-project I), part of scripts/render-cats.sh (`--wardrobe`, see the list at the top of scripts/render-cats.swift). They draw through the real `CatRenderer` and
// `CatOutfitDraw`, in the role a big cat has, and are laid out like the Wardrobe panel of design/prototype/notchmeow.html, so the two can be looked at side by side. `--part` picks one:
//   sheet     all 16 outfits on all 16 coats at Ø40 (the default)       preview  one coat at five sizes, the compact notch at 1x and 3x, and two small cats, bare
//   compact   the compact notch's big cat, Ø20 in the 32 pt strip and Ø18 in the 24 pt strip, magnified 2.5x, four coats       compact1  all 16 coats at 1x
//   turned    four coats with the head turned a full yaw each way       collars  the neck outfits over the four collar styles
// `--cats` limits the coats of `sheet`, `compact`, `compact1` and `turned`. The island, the desktop and the pair of Two cats are the existing sheets with `--outfit <id>`.

extension RenderCats {
    /// The outfit the island and desktop sheets dress their big cats in (`--outfit`); "none" is bare.
    @MainActor static var sheetOutfit = "none"

    /// One cat, in the big-cat role, wearing `id`, at rest or with the head turned; `strip` puts it in the compact notch (the cat's ears and the outfit share the strip's room).
    @MainActor static func dressedCat(_ cg: CGContext, _ coat: String, _ id: String?, cx: Double, cy: Double, D: Double, role: String = "big", yaw: Double = 0, pitch: Double = 0, ceiling: Double? = nil, collar: CatCollarPaint? = nil, dpr: Double = 2) {
        var pose = CatPose()
        pose.yaw = yaw; pose.pitch = pitch
        var o = CatDrawOptions(tint: false, badge: false)
        o.earCeiling = ceiling
        o.collar = collar
        if let id, let paint = CatOutfitDraw.big(id, dpr: dpr) { o.outfit = CatOutfitPaint(id: paint.id, role: role, dpr: dpr) }
        CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(coat), pose: pose), cx: cx, cy: cy, D: D, o)
    }

    /// Column heads: a long name breaks at its spaces and hyphens so it fits its column.
    @MainActor private static func heads(_ cg: CGContext, _ ids: [String], left: Double, cw: Double) {
        for (i, id) in ids.enumerated() {
            // "Round glasses" is shortened and a hyphenated word breaks after its hyphen, so the long names fit their column.
            let name = (Wardrobe.names[id] ?? id).replacingOccurrences(of: "Round glasses", with: "Round glass.").replacingOccurrences(of: "-", with: "- ")
            let words = name.split(separator: " ").map(String.init)
            for (j, w) in words.enumerated() { CatDraw.text(cg, w, x: left + Double(i) * cw + cw / 2, y: 12 + Double(j) * 11, size: 10, bold: true, color: CatDraw.white(0.93)) }
        }
    }

    @MainActor static func wardrobeSheet(_ a: Args) -> Sheet {
        let ids = Wardrobe.drawn
        switch a.part {
        case "compact": return wardrobeCompact(a, cats: a.cats.count == CatPresets.ids.count ? ["momo", "shrimpy", "latte", "midnight"] : a.cats, magnify: 2.5)
        case "compact1": return wardrobeCompact(a, cats: a.cats, magnify: 1)
        case "turned": return wardrobeTurned(a)
        case "collars": return wardrobeCollars(a)
        case "preview": return wardrobePreview(a)
        default:
            let cw = 66.0, rh = 64.0, lw = 78.0, hh = 34.0
            let sheet = Sheet(width: lw + Double(ids.count) * cw, height: hh + Double(a.cats.count) * rh, scale: a.scale)
            let cg = sheet.cg
            cg.fill(CatDraw.roundRect(0, 0, sheet.width, sheet.height, 0), CatDraw.rgb([11, 12, 14]))
            heads(cg, ids, left: lw, cw: cw)
            for (j, coat) in a.cats.enumerated() {
                CatDraw.text(cg, coat, x: 8, y: hh + Double(j) * rh + rh / 2 + 4, size: 11, bold: false, color: CatDraw.rgb([154, 156, 163]), anchor: .left)
                for (i, id) in ids.enumerated() { dressedCat(cg, coat, id, cx: lw + Double(i) * cw + cw / 2, cy: hh + Double(j) * rh + rh / 2 + 4, D: 40, dpr: a.scale) }
            }
            return sheet
        }
    }

    /// The compact notch's big cat: Ø20 in the 32 pt strip, Ø18 in the 24 pt strip of a screen without a notch, magnified `magnify` times (the floors stay the real device's).
    @MainActor static func wardrobeCompact(_ a: Args, cats: [String], magnify k: Double) -> Sheet {
        let ids = Wardrobe.drawn, cw = 42.0, lw = 64.0, hh = 30.0, gap = 3.0, rows: [(h: Double, d: Double)] = [(32, 20), (24, 18)]
        let rowH = rows.reduce(0) { $0 + $1.h + gap }
        let sheet = Sheet(width: lw + Double(ids.count) * cw * k, height: hh + Double(cats.count) * rowH * k, scale: a.scale)
        let cg = sheet.cg
        cg.fill(CatDraw.roundRect(0, 0, sheet.width, sheet.height, 0), CatDraw.rgb([22, 23, 26]))
        heads(cg, ids, left: lw, cw: cw * k)
        for (j, coat) in cats.enumerated() {
            var y = hh + Double(j) * rowH * k
            for r in k == 1 ? [rows[0]] : rows {
                CatDraw.text(cg, "\(coat) Ø\(Int(r.d))", x: 4, y: y + r.h * k / 2 + 3, size: 10, bold: false, color: CatDraw.rgb([154, 156, 163]), anchor: .left)
                cg.saveGState()
                cg.translateBy(x: lw, y: y)
                cg.scaleBy(x: k, y: k)
                for (i, id) in ids.enumerated() {
                    let x = Double(i) * cw
                    cg.fill(CatDraw.roundRect(x + 1, 0, cw - 2, r.h, 0), CatDraw.black(1))
                    cg.fill(CatDraw.roundRect(x + 1, 0, cw - 2, 1 / a.scale, 0), CatDraw.rgb([58, 60, 66]))
                    cg.saveGState()
                    cg.clip(to: CGRect(x: x + 1, y: 0, width: cw - 2, height: r.h))
                    dressedCat(cg, coat, id, cx: x + cw / 2, cy: r.h / 2, D: r.d, ceiling: 0, dpr: a.scale)
                    cg.restoreGState()
                }
                cg.restoreGState()
                y += (r.h + gap) * k
            }
        }
        return sheet
    }

    /// Four coats with the head turned a full yaw each way: parts on the face flatten with it, hats and the bow slide with the head.
    @MainActor static func wardrobeTurned(_ a: Args) -> Sheet {
        let cats = a.cats.count == CatPresets.ids.count ? ["momo", "shrimpy", "button", "midnight"] : a.cats
        let ids = Wardrobe.drawn, turns: [Double] = [-0.6, 0.6], cw = 66.0, rh = 64.0, lw = 96.0, hh = 34.0
        let sheet = Sheet(width: lw + Double(ids.count) * cw, height: hh + Double(cats.count * turns.count) * rh, scale: a.scale)
        let cg = sheet.cg
        cg.fill(CatDraw.roundRect(0, 0, sheet.width, sheet.height, 0), CatDraw.rgb([11, 12, 14]))
        heads(cg, ids, left: lw, cw: cw)
        for (j, coat) in cats.enumerated() {
            for (t, yaw) in turns.enumerated() {
                let y = hh + Double(j * 2 + t) * rh + rh / 2 + 4
                CatDraw.text(cg, "\(coat) \(yaw < 0 ? "left" : "right")", x: 8, y: y + 4, size: 11, bold: false, color: CatDraw.rgb([154, 156, 163]), anchor: .left)
                for (i, id) in ids.enumerated() { dressedCat(cg, coat, id, cx: lw + Double(i) * cw + cw / 2, cy: y, D: 40, yaw: yaw, pitch: 0.15, dpr: a.scale) }
            }
        }
        return sheet
    }

    /// The bell, bandana and scarf over the four collar styles, on a light and a dark coat: the collar is drawn first, the outfit over it, never the other way.
    @MainActor static func wardrobeCollars(_ a: Args) -> Sheet {
        let styles = ["off", "tag", "band", "kerchief"], cols = [("momo", "bell"), ("momo", "bandana"), ("momo", "scarf"), ("ginger", "bell"), ("ginger", "bandana"), ("ginger", "scarf")]
        let cw = 124.0, rh = 116.0, lw = 70.0, hh = 22.0
        let sheet = Sheet(width: lw + Double(cols.count) * cw, height: hh + Double(styles.count) * rh, scale: a.scale)
        let cg = sheet.cg
        cg.fill(CatDraw.roundRect(0, 0, sheet.width, sheet.height, 0), CatDraw.rgb([11, 12, 14]))
        for (i, c) in cols.enumerated() { CatDraw.text(cg, "\(c.0) · \(c.1)", x: lw + Double(i) * cw + cw / 2, y: 14, size: 11, bold: true, color: CatDraw.white(0.93)) }
        for (j, style) in styles.enumerated() {
            CatDraw.text(cg, "collar: \(style)", x: 6, y: hh + Double(j) * rh + rh / 2 + 4, size: 11, bold: false, color: CatDraw.rgb([154, 156, 163]), anchor: .left)
            for (i, c) in cols.enumerated() {
                let paint = style == "off" ? nil : CatCollarPaint(style: style, color: agentColors[0].hex, dpr: a.scale)
                dressedCat(cg, c.0, c.1, cx: lw + Double(i) * cw + cw / 2, cy: hh + Double(j) * rh + rh / 2, D: 78, collar: paint, dpr: a.scale)
            }
        }
        return sheet
    }

    /// One coat (the first of `--cats`, else Momo) wearing the outfit of `--outfit` (else the Santa hat) at five sizes, the compact notch at 1x and 3x, and two small cats, which stay bare.
    @MainActor static func wardrobePreview(_ a: Args) -> Sheet {
        let coat = a.cats.count == CatPresets.ids.count ? "momo" : a.cats[0], id = a.outfit == "none" ? "santahat" : a.outfit, top = 46.0
        let sheet = Sheet(width: 820, height: 270 + top, scale: a.scale)
        let cg = sheet.cg
        cg.fill(CatDraw.roundRect(0, 0, 820, 270 + top, 0), CatDraw.rgb([11, 12, 14]))
        cg.translateBy(x: 0, y: top)
        let label = CatDraw.rgb([154, 156, 163])
        dressedCat(cg, coat, id, cx: 130, cy: 150, D: 170, dpr: a.scale)
        CatDraw.text(cg, "\(coat), \(Wardrobe.name(id))", x: 130, y: 262, size: 11, bold: false, color: label)
        for (d, text, x) in [(64.0, "Ø64", 270.0), (48, "Ø48", 360), (28, "Ø28", 430)] {
            dressedCat(cg, coat, id, cx: x, cy: 150, D: d, dpr: a.scale)
            CatDraw.text(cg, text, x: x, y: 262, size: 11, bold: false, color: label)
        }
        cg.fill(CatDraw.roundRect(480, 98, 60, 32, 0), CatDraw.black(1))
        dressedCat(cg, coat, id, cx: 510, cy: 114, D: 20, ceiling: 98, dpr: a.scale)
        CatDraw.text(cg, "Ø20 notch", x: 510, y: 262, size: 11, bold: false, color: label)
        cg.saveGState()
        cg.translateBy(x: 560, y: 50)
        cg.scaleBy(x: 3, y: 3)
        cg.fill(CatDraw.roundRect(0, 0, 60, 32, 0), CatDraw.black(1))
        dressedCat(cg, coat, id, cx: 30, cy: 16, D: 20, ceiling: 0, dpr: a.scale)
        cg.restoreGState()
        CatDraw.text(cg, "Ø20 × 3", x: 650, y: 262, size: 11, bold: false, color: label)
        dressedCat(cg, coat, id, cx: 740, cy: 100, D: 20, role: "small", dpr: a.scale)
        dressedCat(cg, coat, id, cx: 780, cy: 100, D: 12, role: "small", dpr: a.scale)
        CatDraw.text(cg, "small cats: bare", x: 760, y: 128, size: 11, bold: false, color: label)
        return sheet
    }
}
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
//   bash scripts/render-cats.sh --bench-desktop                    the desktop cat's frame cost at each size and what it is at each frame rate (idle and awake must be under 1 % of a core)
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.
```

Replace with:

```swift
//   bash scripts/render-cats.sh --bench-desktop                    the desktop cat's frame cost at each size and what it is at each frame rate (idle and awake must be under 1 % of a core)
//   bash scripts/render-cats.sh --wardrobe [--part sheet|preview|compact|compact1|turned|collars] --scale 2   sub-project I: the 16 outfits on the 16 coats (sheet), one coat at five sizes (preview), the compact notch's
//                                                                  Ø20 and Ø18 big cat (compact, compact1), the head turned and the neck outfits over the collars; see scripts/render-cats-wardrobe.swift
//   bash scripts/render-cats.sh --island|--desktop|--desktop-flight --outfit bunnyears   the island (all three display modes), the desktop cat at three sizes, with every big cat dressed (kittens and small cats stay bare)
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        case wing
    }
```

Replace with:

```swift
        case wing
        case wardrobe
    }
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        var shapes = false
    }
```

Replace with:

```swift
        var shapes = false
        var part = "sheet"
        var outfit = "none"
    }
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
            case "--wing": a.mode = .wing
            case "--scenario": a.scenario = it.next() ?? a.scenario
```

Replace with:

```swift
            case "--wing": a.mode = .wing
            case "--wardrobe": a.mode = .wardrobe
            case "--part": a.part = it.next() ?? a.part
            case "--outfit": let id = it.next() ?? ""; a.outfit = Wardrobe.ids.contains(id) && id != "auto" ? id : "none"
            case "--scenario": a.scenario = it.next() ?? a.scenario
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        let a = parse()
        let sheet: Sheet
```

Replace with:

```swift
        let a = parse()
        sheetOutfit = a.outfit
        let sheet: Sheet
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        case .wing: sheet = wingSheet(a)
        case .emotes: sheet = emotes(a)
```

Replace with:

```swift
        case .wing: sheet = wingSheet(a)
        case .wardrobe: sheet = wardrobeSheet(a)
        case .emotes: sheet = emotes(a)
```

**Edit `scripts/render-cats.sh`**

Find:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift \
```

Replace with:

```text
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift \
```

**Edit `scripts/render-cats.sh`**

Find:

```text
    scripts/render-cats.swift scripts/render-cats-desktop.swift scripts/render-cats-wing.swift \
```

Replace with:

```text
    scripts/render-cats.swift scripts/render-cats-desktop.swift scripts/render-cats-wing.swift scripts/render-cats-wardrobe.swift \
```


- [ ] **Step 7: Draw the sheets and look at them**

```bash
OUT="${TMPDIR:-/tmp}/i-mac-1"; mkdir -p "$OUT"
for part in sheet preview compact compact1 turned collars; do bash scripts/render-cats.sh --wardrobe --part $part --scale 2 --out "$OUT/wardrobe-$part.png" 2>&1 | tail -1; done
```

Expected: six `wrote …/wardrobe-<part>.png` lines (the first build takes a minute). Look at each, next to the Wardrobe panel of `design/prototype/notchmeow.html` (`open design/prototype/notchmeow.html`, then Wardrobe): `sheet` is 16 outfits by 16 coats at Ø40 (2268 by 2116 pixels), `preview` one coat at Ø170, Ø64, Ø48, Ø28, the notch's Ø20 at 1x and 3x, and two small cats that are bare; `compact` and `compact1` the notch's cat in its strip (Ø20 in 32 pt, Ø18 in 24 pt), `turned` four coats with the head turned each way and `collars` the bell, the bandana and the scarf over the four collar styles. Say in one sentence per image what you see: every outfit is on its coat, the hats stand between the ears, the glasses sit on the eyes, nothing leaves the strip, the small cats in `preview` are bare. A blank or broken image is a failed step.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/CatOutfitDraw.swift NotchBuddy/Sources/App/CatLook.swift NotchBuddy/Sources/App/CatRenderer.swift tests/WardrobeDrawTests.swift scripts/test-wardrobe-draw.sh scripts/render-cats-wardrobe.swift scripts/render-cats.swift scripts/render-cats.sh scripts/render-cat-settings.sh scripts/render-cat-panel.sh scripts/gen-icons.sh scripts/test-cat-renderer.sh scripts/test-cat-desktop-devpanel.sh
printf '%s\n' 'feat(wardrobe): the outfits drawn at the three slots, and the contact sheets (I-mac task 4)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 5: The big cats wear it: five views, the greeting's fade

The five views that draw a cat in the big-cat role ask for the outfit (`engine.cfg.outfit`) and nothing else does: the island's main cat (compact and open), the second cat of Two cats mode, the cat that catches a file, the desktop cat and the launch greeting's cat and the pair's second cat. The greeting puts it on once the cat has settled (the owner's answer): `Greeting.outfitFade(t)` is 0 until the cat has slid back and waved (`GT2.back1`), then 1 over a quarter of a second. The pills' cats (`MiniBotCanvasView`), the kittens, the grid, Settings' previews and the Display preview never ask. The sheets learn `--outfit <id>`.

**Interfaces.** Consumes: `CatOutfitDraw.big` (Task 4), `CatConfig.outfit` (Task 2). Produces: `CatGreeting.outfitFade(_ t: Double) -> Double`.

- [ ] **Step 1: Write the pins and the fade's test**

**Create `tests/WardrobeWiringTests.swift`**

```swift
import Foundation

// Source pins for the wardrobe (sub-project I) in the app files no test program can compile (the views, the island window, the app delegate). Each says where a call must be, so a missed
// call site fails here and not on the owner's screen. Run from the repository root. Each later task of the plan adds its section above the last line of `main`.

@main
enum WardrobeWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        CT.section("who wears it: the five big-cat views dress their cat, and nothing else does")
        let bot = source("BotCanvasView.swift"), pair = source("PairCatViews.swift"), upload = source("UploadCanvasView.swift"), desktop = source("DesktopCatDraw.swift"), greeting = source("CatGreetingRenderer.swift")
        CT.checkTrue("the sources were read", bot.contains("struct BotCanvasView") && pair.contains("struct PairCatCanvasView") && upload.contains("drawCat(ctx") && desktop.contains("enum DesktopCatDraw") && greeting.contains("enum CatGreetingRenderer"))
        CT.check("the island's main cat (compact and open) asks for the outfit once", count("CatOutfitDraw.big(engine.cfg.outfit", in: bot), 1)
        CT.checkTrue("and it is in the big cat's view, before the mini cat's view starts", at("CatOutfitDraw.big(engine.cfg.outfit", in: bot) > 0 && at("CatOutfitDraw.big(engine.cfg.outfit", in: bot) < at("struct MiniBotCanvasView", in: bot))
        CT.check("the second cat of Two cats mode asks once", count("CatOutfitDraw.big(engine.cfg.outfit", in: pair), 1)
        CT.check("the file catch's cat asks once", count("CatOutfitDraw.big(catEngine.cfg.outfit", in: upload), 1)
        CT.check("the desktop cat asks once", count("CatOutfitDraw.big(engine.cfg.outfit", in: desktop), 1)
        CT.check("the greeting dresses its cat and the pair's second cat, and no one else", count("CatOutfitDraw.big(e.cfg.outfit", in: greeting), 2)
        CT.checkTrue("the greeting's cat is dressed with the fade, once it has settled", greeting.contains("fade: Greeting.outfitFade(t)"))
        CT.checkTrue("the mini cat's view, the kittens, the Display preview and Settings' own previews never ask", !source("CatKittenDraw.swift").contains("outfit") && !source("KittenViews.swift").contains("outfit") && !source("CatDisplayPreview.swift").contains("outfit") && !source("CatSettingsView.swift").contains("CatOutfitDraw")
            && !String(bot[bot.range(of: "struct MiniBotCanvasView")!.lowerBound...]).contains("outfit"))

        CT.section("the draw order: behind after the ears, then the collar, the outfit's neck and top, then the whiskers")
        let r = source("CatRenderer.swift")
        CT.checkTrue("the source was read", r.contains("enum CatRenderer"))
        CT.checkTrue("the behind slot follows the ears of the behind pass", at("front: false, flat: flat?.ears[e.sd < 0 ? 0 : 1]) }\n        // The outfit's `behind` slot", in: r) > 0 && at("CatOutfitDraw.paint(cg, dressed, slot: \"behind\")", in: r) > at("front: false, flat:", in: r))
        let collar = at("CatEffects.drawCollar(cg, g", in: r), neck = at("slot: \"neck\"", in: r), top = at("slot: \"top\"", in: r), whiskers = at("CatFace.drawWhiskers(cg, p, s, L)", in: r)
        CT.checkTrue("the neck slot is after the collar, the top slot after the neck, and the whiskers after both", collar > 0 && neck > collar && top > neck && whiskers > top)
        CT.checkTrue("the outfit is fitted to the ears as drawn (after the ear fit) and to the notch's strip", r.contains("earScale: drawnEk") && r.contains("ceiling: o.earCeiling"))
        CT.checkTrue("a bare cat (a small cat, a kitten) never builds the geometry: the role is checked first", source("CatOutfitDraw.swift").contains("guard let paint, Wardrobe.worn(paint.role), paint.fade > 0.001 else { return nil }"))

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
        CT.finish()
    }
}
```

**Create `scripts/test-wardrobe-wiring.sh`**

```bash
#!/usr/bin/env bash
# Wardrobe wiring (sub-project I): where the app's own files call the pure parts, pinned as source text (the five big-cat views, the draw order, the clock's attach and its one timer, and,
# added by later tasks, the menus, the shortcut and the Debug panel). The views and the island need the whole app, so no test program can run them.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/WardrobeWiringTests.swift \
    -o "$TEST_DIR/wardrobe-wiring-tests"
"$TEST_DIR/wardrobe-wiring-tests"
```

**Edit `tests/CatGreetingTests.swift`**

Find:

```swift

        CT.finish()
```

Replace with:

```swift

        CT.section("the outfit: it comes on once the cat has settled (sub-project I)")
        CT.check("it is not on while the cat falls, bounces and waves", [G.outfitFade(0), G.outfitFade(G.GT2.land), G.outfitFade(G.GT2.wave1), G.outfitFade(G.GT2.back1 - 0.01)], [0.0, 0.0, 0.0, 0.0])
        CT.checkNear("it is half on a eighth of a second after the cat has slid back", G.outfitFade(G.GT2.back1 + 0.125), 0.5)
        CT.check("and whole a quarter of a second after, until the end", [G.outfitFade(G.GT2.back1 + 0.25), G.outfitFade(G.GT.leave), G.outfitFade(G.length)], [1.0, 1.0, 1.0])

        CT.finish()
```


```bash
chmod +x scripts/test-wardrobe-wiring.sh
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-wardrobe-wiring.sh 2>&1 | grep "✗"; bash scripts/test-cat-greeting.sh 2>&1 | tail -3`
Expected: FAIL: seven `✗` lines from the wiring pins (the views do not ask yet) and `type 'G' (aka 'CatGreeting') has no member 'outfitFade'`.

- [ ] **Step 3: Write the code**

**Edit `NotchBuddy/Sources/App/CatGreeting.swift`**

Find:

```swift
    static let length = GT.leave + GT.collapse + 0.5
```

Replace with:

```swift
    static let length = GT.leave + GT.collapse + 0.5
    /// How much of the outfit shows at `t` seconds (sub-project I): none while the cat falls, bounces and waves, then it comes on over a quarter of a second once the cat has slid back and settled.
    static func outfitFade(_ t: Double) -> Double { seg(t, GT2.back1, GT2.back1 + 0.25) }
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**

Find:

```swift
        o.fur = e.cfg.furLines
        o.badgeSide = 1 - 2 * CatEase.inOut.at(seg(t, leave, leave + Greeting.GT.collapse))
```

Replace with:

```swift
        o.fur = e.cfg.furLines
        o.outfit = CatOutfitDraw.big(e.cfg.outfit, dpr: 2, fade: Greeting.outfitFade(t))   // dressed once the cat has settled; the session cats below stay bare
        o.badgeSide = 1 - 2 * CatEase.inOut.at(seg(t, leave, leave + Greeting.GT.collapse))
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**

Find:

```swift
                CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(pair), pose: pose, color: Theme.Greeting.tintRGB), cx: X + D * 1.2, cy: Y, D: D * pop, CatDrawOptions(badge: false))
```

Replace with:

```swift
                var pairOptions = CatDrawOptions(badge: false)
                pairOptions.outfit = CatOutfitDraw.big(e.cfg.outfit, dpr: 2)   // the second cat of the pair is a big cat too
                CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(pair), pose: pose, color: Theme.Greeting.tintRGB), cx: X + D * 1.2, cy: Y, D: D * pop, pairOptions)
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**

Find:

```swift
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))   // Settings → Cat → Collar
                if state.mode == .compact {
```

Replace with:

```swift
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))   // Settings → Cat → Collar
                options.outfit = CatOutfitDraw.big(engine.cfg.outfit, dpr: Double(context.environment.displayScale))   // Settings → Cat → Wardrobe: the big cat, at every size
                if state.mode == .compact {
```

**Edit `NotchBuddy/Sources/App/PairCatViews.swift`**

Find:

```swift
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))
                var laid: CatGeometry.Layout?
```

Replace with:

```swift
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))
                options.outfit = CatOutfitDraw.big(engine.cfg.outfit, dpr: Double(context.environment.displayScale))   // both cats of Two cats mode are big cats
                var laid: CatGeometry.Layout?
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`**

Find:

```swift
        look.badge = nil
        ctx.withCGContext { cg in
```

Replace with:

```swift
        look.badge = nil
        var options = CatDrawOptions(fur: catEngine.cfg.furLines)
        options.outfit = CatOutfitDraw.big(catEngine.cfg.outfit, dpr: Double(ctx.environment.displayScale))   // the big cat catches the file in the outfit it wears everywhere else
        ctx.withCGContext { cg in
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`**

Find:

```swift
            laid = CatRenderer.draw(cg, look, cx: f.x, cy: f.y + f.hop, D: f.d, CatDrawOptions(fur: catEngine.cfg.furLines))
```

Replace with:

```swift
            laid = CatRenderer.draw(cg, look, cx: f.x, cy: f.y + f.hop, D: f.d, options)
```

**Edit `NotchBuddy/Sources/App/DesktopCatDraw.swift`**

Find:

```swift
        options.collar = engine.collarPaint(dpr: scene.dpr)     // Settings → Cat → Collar
        cg.saveGState()
```

Replace with:

```swift
        options.collar = engine.collarPaint(dpr: scene.dpr)     // Settings → Cat → Collar
        options.outfit = CatOutfitDraw.big(engine.cfg.outfit, dpr: scene.dpr)   // Settings → Cat → Wardrobe: the desktop cat is a big cat; its kittens (below) stay bare
        cg.saveGState()
```


- [ ] **Step 4: Teach the sheets `--outfit`**

**Edit `scripts/render-cats.swift`**

Find:

```swift
                let (e, clock, step) = scene(CatPresets.byID(id), profile: "playful", D: 80, quiet: true)
```

Replace with:

```swift
                let (e, clock, step) = scene(CatPresets.byID(id), profile: "playful", D: 80, quiet: true); e.cfg.outfit = sheetOutfit
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        var options = CatDrawOptions(badge: big)
        options.badgeSide = badgeSide
```

Replace with:

```swift
        var options = CatDrawOptions(badge: big)
        if big { options.outfit = CatOutfitDraw.big(sheetOutfit, dpr: 2) }   // `--outfit`: every big cat of the island sheets is dressed, the small ones are not
        options.badgeSide = badgeSide
```

**Edit `scripts/render-cats-desktop.swift`**

Find:

```swift
        e.collar = colour
        let rng = CatRNG(seed: 5), herd = CatKittenHerd()
```

Replace with:

```swift
        e.collar = colour
        e.cfg.outfit = sheetOutfit   // `--outfit`: the desktop cat is a big cat; its kittens stay bare
        let rng = CatRNG(seed: 5), herd = CatKittenHerd()
```


- [ ] **Step 5: Run the tests**

Run: `bash scripts/test-wardrobe-wiring.sh 2>&1 | grep -v "✓"; bash scripts/test-cat-greeting.sh 2>&1 | tail -3`
Expected: PASS: the two sections of the pins and `All tests passed.`; the greeting test ends `…whole a quarter of a second after, until the end` and `All tests passed.`

Run: `for f in test-cat-desktop-devpanel test-cat-renderer test-cat-upload test-cat-cast test-cat-press; do printf '%-34s' $f; bash scripts/$f.sh 2>&1 | tail -1; done`
Expected: five lines ending `All tests passed.`

- [ ] **Step 6: Draw the island, the desktop and the greeting dressed, and look**

```bash
OUT="${TMPDIR:-/tmp}/i-mac-1"
bash scripts/render-cats.sh --island --outfit bunnyears --out "$OUT/island-bunnyears.png" 2>&1 | tail -1
bash scripts/render-cats.sh --island --mode two --outfit santahat --out "$OUT/island-two-santahat.png" 2>&1 | tail -1
bash scripts/render-cats.sh --desktop --outfit witchhat --out "$OUT/desktop-witchhat.png" 2>&1 | tail -1
bash scripts/render-cats.sh --greeting --cats momo --outfit crown --out "$OUT/greeting-crown.png" 2>&1 | tail -1
```

Expected: four `wrote …` lines. Look at them: in the island sheets the big cat (compact and open, both cats in Two cats) wears the outfit and the small cats of the pills and the grid are bare; in the desktop sheet the cat wears it at Ø48, Ø64 and Ø96 and its kittens beside it are bare; in the greeting sheet the cat is bare while it falls and waves and dressed in the last frames.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/CatGreeting.swift NotchBuddy/Sources/App/CatGreetingRenderer.swift NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/PairCatViews.swift NotchBuddy/Sources/App/UploadCanvasView.swift NotchBuddy/Sources/App/DesktopCatDraw.swift tests/WardrobeWiringTests.swift scripts/test-wardrobe-wiring.sh tests/CatGreetingTests.swift scripts/render-cats.swift scripts/render-cats-desktop.swift
printf '%s\n' 'feat(wardrobe): the five big-cat views wear the outfit, the greeting puts it on once it settles (I-mac task 5)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 6: Auto's clock reaches the cats: one wall-clock timer (step 4)

`WardrobeClock.shared` is the app's clock: the real date, **one** `DispatchQueue.main.asyncAfter(wallDeadline:)` one-shot (so a Mac that sleeps through midnight fires it on waking), the stored choice from the store and the resolved outfit written to `CatConfig.outfit`, which every big cat reads on its next frame. It is attached first thing in `setupIsland`, before the island window and its greeting exist. A change of the system clock or time zone looks at the date again (an event, not a poll). In a Debug build a date override and a pretend midnight are available through two notifications (Task 13 posts them).

**Interfaces.** Consumes: `WardrobeClock`, `Wardrobe.today`, `Wardrobe.secondsToMidnight`, `Wardrobe.nextDay`, `WardrobeDev` (Task 1), `CatSettingsStore.$wardrobe`, `CatConfig.outfit` (Task 2). Produces: `WardrobeClock.shared`, `.attach(to:config:)`, `.appToday()`, `.appSecondsToMidnight()`, Debug-only `.debugDay`, `.debugMidnightAt`.

- [ ] **Step 1: Write the pins**

**Edit `tests/WardrobeWiringTests.swift`**

Find:

```swift

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```

Replace with:

```swift

        CT.section("the choice, and Auto's one midnight timer: attached before the first cat is drawn")
        let delegate = source("AppDelegate.swift"), clock = source("WardrobeClock+App.swift")
        CT.checkTrue("the sources were read", delegate.contains("private func setupIsland()") && clock.contains("extension WardrobeClock"))
        CT.checkTrue("the clock is attached first thing in setupIsland, before the island window (and its greeting) exists", at("WardrobeClock.shared.attach(", in: delegate) > at("private func setupIsland()", in: delegate) && at("WardrobeClock.shared.attach(", in: delegate) < at("islandController = IslandWindowController()", in: delegate))
        CT.checkTrue("the timer is a wall-clock one-shot, and it is the clock's only timer: no repeating timer, no polling", clock.contains("asyncAfter(wallDeadline:") && count("asyncAfter", in: clock) == 1 && !clock.contains("Timer.scheduledTimer") && !clock.contains("DispatchSource"))
        CT.checkTrue("the clock follows the stored choice, and a change of the system clock or time zone is an event", clock.contains("store.$wardrobe") && clock.contains("NSSystemClockDidChange") && clock.contains("NSSystemTimeZoneDidChange"))
        CT.checkTrue("the date override is Debug-only", clock.contains("#if DEBUG && !APPSTORE\n    /// Debug builds only") && clock.contains("static var debugDay"))

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```


- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-wardrobe-wiring.sh 2>&1 | grep -v "✓" | tail -5`
Expected: FAIL: the section `the choice, and Auto's one midnight timer: …` with `✗` lines (the file does not exist).

- [ ] **Step 3: Write the clock's app side and attach it**

**Create `NotchBuddy/Sources/App/WardrobeClock+App.swift`**

```swift
import Combine
import Foundation

// The app's way into the wardrobe clock: the real date, ONE wall-clock one-shot timer on the main queue (a Mac that sleeps through midnight fires it on waking), and the links to the
// store (the choice) and to `CatConfig` (the outfit every big cat reads on every frame). Nothing here is in the contract, and the test programs do not compile this file.

extension WardrobeClock {
    /// The app's clock. `schedule` uses the wall clock (`wallDeadline`), not the monotonic one, so a timer set for midnight is not still waiting after the Mac slept through it.
    static let shared = WardrobeClock(
        today: { appToday() },
        secondsToMidnight: { appSecondsToMidnight() },
        schedule: { afterSeconds, fire in
            let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + afterSeconds, execute: item)
            return { item.cancel() }
        })

    #if DEBUG && !APPSTORE
    /// Debug builds only (the cat panel's Wardrobe section): a date Auto reads instead of today's, so the owner can see each season without waiting for it, and a pretend midnight a few seconds
    /// away, so the one-shot timer can be watched. Compiled out of Release and App Store (`scripts/check-app-binary.sh` proves it).
    static var debugDay: Wardrobe.Day?
    static var debugMidnightAt: Date?
    static func appToday() -> Wardrobe.Day {
        if let at = debugMidnightAt, Date() >= at { debugMidnightAt = nil; debugDay = Wardrobe.nextDay(debugDay ?? Wardrobe.today()) }
        return debugDay ?? Wardrobe.today()
    }
    /// With a pretend midnight pending, the timer is asked for the seconds left to it (the clock adds its second of slack).
    static func appSecondsToMidnight() -> Double { debugMidnightAt.map { max(1, $0.timeIntervalSinceNow - 1) } ?? Wardrobe.secondsToMidnight() }
    #else
    static func appToday() -> Wardrobe.Day { Wardrobe.today() }
    static func appSecondsToMidnight() -> Double { Wardrobe.secondsToMidnight() }
    #endif

    private static var subscriptions = Set<AnyCancellable>()

    /// Starts the clock and keeps it in step with the app: the stored choice feeds `setChoice`, and the resolved outfit goes to `config.outfit`, which the big cats read. A change of
    /// the system clock or time zone looks at the date again (an event, not a poll).
    func attach(to store: CatSettingsStore, config: CatConfig) {
        onChange = { [weak config] outfit in config?.outfit = outfit }
        store.$wardrobe.map(\.outfit).removeDuplicates()
            .sink { [weak self, weak config] choice in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.setChoice(choice)
                    config?.outfit = self.resolved
                }
            }
            .store(in: &Self.subscriptions)
        #if DEBUG && !APPSTORE
        // The Debug cat panel's Wardrobe section talks to the clock through notifications, so the panel compiles without the app's files.
        NotificationCenter.default.publisher(for: WardrobeDev.dateNote)
            .sink { [weak self] note in MainActor.assumeIsolated { Self.debugDay = (note.userInfo?["day"] as? String).flatMap(Wardrobe.parseDay); self?.dateChanged() } }
            .store(in: &Self.subscriptions)
        NotificationCenter.default.publisher(for: WardrobeDev.midnightNote)
            .sink { [weak self] _ in MainActor.assumeIsolated { Self.debugMidnightAt = Date().addingTimeInterval(5); self?.dateChanged() } }
            .store(in: &Self.subscriptions)
        #endif
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.dateChanged() } }
                .store(in: &Self.subscriptions)
        }
    }
}
```

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`**

Find:

```swift
    private func setupIsland() {
        islandController = IslandWindowController()
```

Replace with:

```swift
    private func setupIsland() {
        WardrobeClock.shared.attach(to: .shared, config: CatSettingsStore.shared.config)   // the outfit every big cat wears: Auto's date, resolved, and its one midnight timer
        islandController = IslandWindowController()
```


- [ ] **Step 4: Run the pins, regenerate the project and build**

Run: `bash scripts/test-wardrobe-wiring.sh 2>&1 | tail -2`
Expected: PASS, `All tests passed.`

```bash
cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `Created project at …` and `** BUILD SUCCEEDED **`. The build only builds: do not open the app.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/WardrobeClock+App.swift NotchBuddy/Sources/App/AppDelegate.swift tests/WardrobeWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
printf '%s\n' 'feat(wardrobe): Auto resolves for the date, with one wall-clock timer for midnight (I-mac task 6)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 7: Settings → Cat → Wardrobe (step 5)

A new group after Display and Desktop, in the existing style (a `GroupBox`, grey 11 pt notes, tiles like the Main cat's): a live preview of the big cat wearing the tile under the pointer (else the chosen outfit), a coat picker beside it that changes nothing that is stored, and 18 tiles in the grid's order with the four groups' headings. The Auto tile says what Auto wears today ("Auto: today, Santa hat" or "Auto: today, none"). A tile is a still cat (no timeline, no engine), so 18 tiles cost nothing while Settings sits there; only the preview is live, and only while Settings is on screen. Nothing existing changes but one line in `CatSettingsView`'s body, a parameter with a default, and the app's section handing it the clock's date. `check-app-binary.sh` learns the wardrobe's marker.

**Interfaces.** Consumes: `CatSettingsStore.setOutfit`, `.wardrobe` (Task 2), `CatOutfitDraw.big` and `.marker` (Task 4), `WardrobeClock.appToday` (Task 6). Produces: `WardrobeSettingsGroup(store:active:day:)`, `WardrobeTileView(coat:outfit:)`, `WardrobePreviewView(coat:outfit:head:active:config:)`.

- [ ] **Step 1: Write the pins**

**Edit `tests/WardrobeWiringTests.swift`**

Find:

```swift

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```

Replace with:

```swift

        CT.section("Settings → Cat → Wardrobe: after Desktop, and the app hands it the clock's date")
        let view = source("CatSettingsView.swift"), section = source("CatSettingsSection.swift"), group = source("WardrobeSettingsView.swift")
        CT.checkTrue("the sources were read", view.contains("struct CatSettingsView") && section.contains("CatSettingsSection") && group.contains("struct WardrobeSettingsGroup"))
        CT.checkTrue("the group follows Desktop and comes before the pair and the agents", at("desktopGroup\n            WardrobeSettingsGroup(store: store, active: active, day: wardrobeDay)", in: view) > 0 && at("WardrobeSettingsGroup(store", in: view) < at("pairGroup }", in: view))
        CT.checkTrue("the app's section passes the wardrobe clock's date (a Debug build can override it)", section.contains("wardrobeDay: { WardrobeClock.appToday() }"))
        CT.checkTrue("a tile stores through the store, the coat picker stores nothing, and the preview is the only live cat", group.contains("store.setOutfit(id)") && group.contains("@State private var previewCoat") && !group.contains("setCharacter") && count("TimelineView", in: group) == 0 && source("WardrobePreviewViews.swift").contains("TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active))"))
        CT.checkTrue("the group carries the binary check's marker", group.contains(".accessibilityIdentifier(CatOutfitDraw.marker)"))

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```


- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-wardrobe-wiring.sh 2>&1 | grep -v "✓" | tail -5`
Expected: FAIL: `Settings → Cat → Wardrobe: after Desktop, …` with `✗` lines.

- [ ] **Step 3: Write the views and put the group in Settings**

**Create `NotchBuddy/Sources/App/WardrobePreviewViews.swift`**

```swift
import AppKit
import QuartzCore
import SwiftUI

// The wardrobe's two small cat views (sub-project I): a still tile and the live preview. Both draw a cat in the big-cat role wearing the outfit they are given. They know no store, so Settings'
// Wardrobe group and the Debug cat panel's Wardrobe section both use them.

/// A still cat in an outfit for a tile: drawn once, with no timeline and no engine, so 18 tiles cost nothing while Settings sits there.
struct WardrobeTileView: View {
    let coat: String
    /// The outfit to wear: an ID, or "none".
    let outfit: String

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                var o = CatDrawOptions(tint: false, badge: false)
                o.outfit = CatOutfitDraw.big(outfit, dpr: Double(context.environment.displayScale))
                CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(coat)), cx: Double(size.width) / 2, cy: Double(size.height) * 0.66, D: 34, o)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The live preview: one silent engine on the store's `CatConfig`, drawn big, in the big-cat role. It draws only while `active`.
struct WardrobePreviewView: View {
    let coat: String
    let outfit: String
    let head: Double
    let active: Bool
    let config: CatConfig
    @StateObject private var engine: CatEngine

    init(coat: String, outfit: String, head: Double, active: Bool, config: CatConfig) {
        self.coat = coat; self.outfit = outfit; self.head = head; self.active = active; self.config = config
        _engine = StateObject(wrappedValue: CatEngine(CatPresets.byID(coat), now: { CACurrentMediaTime() * 1000 }, cfg: config))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                engine.useCharacter(coat)
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                var o = CatDrawOptions(badge: false)
                o.fur = config.furLines
                o.outfit = CatOutfitDraw.big(outfit, dpr: Double(context.environment.displayScale))
                context.withCGContext { cg in
                    CatRenderer.draw(cg, engine.look(), cx: Double(size.width) / 2, cy: Double(size.height) * 0.64, D: head, o)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
```

**Create `NotchBuddy/Sources/App/WardrobeSettingsView.swift`**

```swift
import AppKit
import QuartzCore
import SwiftUI

// Settings → Cat → Wardrobe (sub-project I), a group after Display and Desktop, built from the rows Settings already has (a GroupBox, a label of 130 pt, grey 11 pt notes, tiles like the
// Main cat's): no existing row changes. A live preview of the Main cat shows the outfit under the pointer, else the chosen one; a coat picker beside it shows the same outfit on any of the
// 16 coats and changes nothing that is stored. A tile click chooses and stores (`CatSettingsStore.setOutfit`). The Auto tile shows what Auto wears today.

struct WardrobeSettingsGroup: View {
    @ObservedObject var store: CatSettingsStore
    let active: Bool
    /// Today's date, for Auto (the app passes `WardrobeClock.appToday`, which a Debug build can override).
    let day: () -> Wardrobe.Day
    /// The tile under the pointer, shown in the preview.
    @State private var hovered: String?
    /// The coat the preview shows. It starts as the Main cat and is never stored.
    @State private var previewCoat: String?

    private var coat: String { previewCoat ?? store.settings.character }
    private var chosen: String { store.wardrobe.outfit }
    private var shown: String { hovered ?? chosen }
    /// What Auto wears today: an outfit's ID or "none".
    private var autoToday: String { Wardrobe.autoOutfit(day()) }
    private func resolved(_ id: String) -> String { Wardrobe.resolve(id, day()) }

    var body: some View {
        GroupBox("Wardrobe") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    WardrobePreviewView(coat: coat, outfit: resolved(shown), head: 76, active: active, config: store.config)
                        .frame(width: 130, height: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(shown == "auto" ? Wardrobe.autoLabel(today: autoToday) : Wardrobe.name(shown)).font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 8) {
                            Text("Preview on").frame(width: 74, alignment: .leading)
                            Picker("", selection: Binding(get: { coat }, set: { previewCoat = $0 })) {
                                ForEach(CatPresets.ids, id: \.self) { Text(CatPresets.byID($0).label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        Text("Every big cat wears it: the notch's cat, both cats of Two cats mode, each agent's big cat and the cat on your desktop. Kittens and the small cats stay bare. The coat only changes this preview.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(Wardrobe.groups, id: \.id) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        if !group.name.isEmpty { Text(group.name).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                            ForEach(group.ids, id: \.self) { tile($0) }
                        }
                    }
                }
                Text("Auto follows the date: new year, Christmas, Halloween, Easter and summer. Pick one outfit to keep it all year.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(6)
            .accessibilityIdentifier(CatOutfitDraw.marker)
        }
    }

    private func tile(_ id: String) -> some View {
        let selected = id == chosen, label = id == "auto" ? Wardrobe.autoLabel(today: autoToday) : Wardrobe.name(id)
        return Button { store.setOutfit(id) } label: {
            VStack(spacing: 0) {
                WardrobeTileView(coat: coat, outfit: resolved(id))
                    .frame(width: 66, height: 56)
                Text(label)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
                    .foregroundColor(selected ? .primary : .secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = id } else if hovered == id { hovered = nil }
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**

Find:

```swift
    private let lookup: (String) -> (name: String, color: String)?
```

Replace with:

```swift
    private let lookup: (String) -> (name: String, color: String)?
    /// Today's date, for the Wardrobe group's Auto tile (the app passes the wardrobe clock's, which a Debug build can override).
    private let wardrobeDay: () -> Wardrobe.Day
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**

Find:

```swift
    init(store: CatSettingsStore = .shared, alwaysActive: Bool = false, agents: [CatAgentList.Agent] = [], lookup: @escaping (String) -> (name: String, color: String)? = { _ in nil }) {
```

Replace with:

```swift
    init(store: CatSettingsStore = .shared, alwaysActive: Bool = false, agents: [CatAgentList.Agent] = [], lookup: @escaping (String) -> (name: String, color: String)? = { _ in nil },
         wardrobeDay: @escaping () -> Wardrobe.Day = { Wardrobe.today() }) {
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**

Find:

```swift
        self.lookup = lookup
    }
```

Replace with:

```swift
        self.lookup = lookup
        self.wardrobeDay = wardrobeDay
    }
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**

Find:

```swift
            desktopGroup
            if store.display.mode == .two { pairGroup }
```

Replace with:

```swift
            desktopGroup
            WardrobeSettingsGroup(store: store, active: active, day: wardrobeDay)
            if store.display.mode == .two { pairGroup }
```

**Edit `NotchBuddy/Sources/App/CatSettingsSection.swift`**

Find:

```swift
        CatSettingsView(agents: agents, lookup: { id in PillCatalog.definition(for: id).map { ($0.name, $0.color) } })
```

Replace with:

```swift
        CatSettingsView(agents: agents, lookup: { id in PillCatalog.definition(for: id).map { ($0.name, $0.color) } }, wardrobeDay: { WardrobeClock.appToday() })
```


- [ ] **Step 4: Teach the render script and the binary check**

**Edit `scripts/render-cat-settings.swift`**

Find:

```swift
//                                       [--mode one|perAgent|two] [--pair momo,latte] [--agents]
```

Replace with:

```swift
//                                       [--mode one|perAgent|two] [--pair momo,latte] [--agents] [--outfit santahat]
```

**Edit `scripts/render-cat-settings.swift`**

Find:

```swift
        var mode = "one", pair = "shrimpy,momo", withAgents = false
```

Replace with:

```swift
        var mode = "one", pair = "shrimpy,momo", withAgents = false, outfit = "auto"
```

**Edit `scripts/render-cat-settings.swift`**

Find:

```swift
            case "--agents": withAgents = true
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
```

Replace with:

```swift
            case "--agents": withAgents = true
            case "--outfit": outfit = it.next() ?? outfit
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
```

**Edit `scripts/render-cat-settings.swift`**

Find:

```swift
        store.setDisplayMode(CatDisplaySettings.modeOf(mode))
        for (slot, cat) in pair.split(separator: ",").map(String.init).enumerated() { store.setPairCat(cat, slot: slot) }
```

Replace with:

```swift
        store.setDisplayMode(CatDisplaySettings.modeOf(mode))
        store.setOutfit(outfit)
        for (slot, cat) in pair.split(separator: ",").map(String.init).enumerated() { store.setPairCat(cat, slot: slot) }
```

**Edit `scripts/render-cat-settings.sh`**

Find:

```text
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/WardrobeSettings.swift $APP/WardrobeAuto.swift $APP/CatSettingsStore.swift $APP/CatDisplayPreview.swift $APP/CatSettingsView.swift \
```

Replace with:

```text
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/WardrobeSettings.swift $APP/WardrobeAuto.swift $APP/CatSettingsStore.swift $APP/CatDisplayPreview.swift $APP/WardrobePreviewViews.swift $APP/WardrobeSettingsView.swift $APP/CatSettingsView.swift \
```

**Edit `scripts/check-app-binary.sh`**

Find:

```text
    echo "✓ The desktop cat is in this build"
fi
```

Replace with:

```text
    echo "✓ The desktop cat is in this build"
    # The wardrobe (sub-project I) is in every build too: the painter and Settings' Wardrobe group carry this marker.
    has NM_WARDROBE_OUTFITS || { echo "✗ the wardrobe (NM_WARDROBE_OUTFITS) is missing from this build" >&2; exit 1; }
    echo "✓ The wardrobe is in this build"
fi
```


- [ ] **Step 5: Run the pins, draw the section and build**

Run: `bash scripts/test-wardrobe-wiring.sh 2>&1 | tail -2; bash scripts/test-cat-settings-store.sh 2>&1 | tail -1`
Expected: two lines ending `All tests passed.`

```bash
OUT="${TMPDIR:-/tmp}/i-mac-1"
bash scripts/render-cat-settings.sh --height 1700 --width 620 --outfit scarf --out "$OUT/settings-wardrobe.png" 2>&1 | tail -1
bash scripts/render-cat-settings.sh --height 1700 --width 620 --character shrimpy --outfit crown --out "$OUT/settings-wardrobe-shrimpy.png" 2>&1 | tail -1
```

Expected: two `wrote …` lines. Look at the first: Display, Desktop and then **Wardrobe**: a preview of the Main cat in the scarf, a "Preview on" coat picker, then the tiles in their groups (Auto and None first with no heading, then Seasonal, Everyday, Cat extras, The cats' own), the scarf tile selected, and the Auto tile reading "Auto: today, …" with today's result; the Main cat group and the rest below are as they were. The system controls (the picker, the group box's frame) may come out blank in this offscreen bitmap; the cats and the layout do not.

```bash
cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/WardrobePreviewViews.swift NotchBuddy/Sources/App/WardrobeSettingsView.swift NotchBuddy/Sources/App/CatSettingsView.swift NotchBuddy/Sources/App/CatSettingsSection.swift tests/WardrobeWiringTests.swift scripts/render-cat-settings.swift scripts/render-cat-settings.sh scripts/check-app-binary.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
printf '%s\n' 'feat(wardrobe): Settings -> Cat -> Wardrobe, with a live preview and a coat picker (I-mac task 7)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 8: Owner checkpoint 1: the sheets against the prototype, and the Wardrobe section

No code and no commit. The main session and the owner look; the session only gathers the pictures.

- [ ] **Step 1: Gather the pictures**

```bash
mkdir -p .claude/checkpoints/i-mac
cp "${TMPDIR:-/tmp}"/i-mac-1/*.png .claude/checkpoints/i-mac/
ls -1 .claude/checkpoints/i-mac
```

Expected: the sheets of Task 4 (`wardrobe-sheet.png`, `-preview`, `-compact`, `-compact1`, `-turned`, `-collars`), the island, desktop and greeting sheets of Task 5 and the two Settings pictures of Task 7 (`.claude/` is gitignored: nothing here is committed).

- [ ] **Step 2: Report to the main session and stop**

Send the report to the main session (the ping rule) with the paths, and say what to look for:

1. **The sheet against the prototype** (`design/prototype/notchmeow.html`, Wardrobe): the 16 outfits on the 16 coats at Ø40 are the same drawings, the same colours, the same places. Anything that differs is a bug of this port, because `cat-core.js` decides.
2. **The compact notch**, `wardrobe-compact.png` and `-compact1.png`: every outfit reads at Ø20 (32 pt strip) and Ø18 (24 pt strip), nothing leaves the strip, the hats are shortened to the room. The owner may ask for a simpler drawing of an outfit at that size: that is a contract change (I-0), not this plan's.
3. **The head turned** and **the collars**: glasses flatten with the face, hats and the bow slide with the head, the bell hangs from the collar and the scarf and bandana cover it.
4. **The small cats are bare** (`wardrobe-preview.png`, the two at the right), and in the island sheets only the big cats are dressed.
5. **Settings → Cat → Wardrobe** (`settings-wardrobe*.png`): the section sits after Display and Desktop, looks like the rest of Settings, the Auto tile says what Auto wears today.

Then stop. Do not start Task 9 until the owner has answered. The owner's change requests to a shape or a colour go to I-0's contract (and its fixture), not to this plan.

### Task 9: The bench with an outfit on, and the Two cats and per-agent sheets

The spec's checkpoint 2 asks for the cost with an outfit on, and the Two cats and per-agent mode sheets. The sheets already take `--outfit` (Task 5); the benches learn it here, so the cost of a hat on the 60 fps big cat and of the desktop cat at each size is measured by the same tools as before.

- [ ] **Step 1: Teach the benches `--outfit`**

**Edit `scripts/render-cats.swift`**

Find:

```swift
        let big = scene(CatPresets.byID("shrimpy"), profile: "playful", D: 66, state: .working)
        // kittens (Ø15, with their state badges), drawn at 30 fps like the small cats: they are small cats too
```

Replace with:

```swift
        let big = scene(CatPresets.byID("shrimpy"), profile: "playful", D: 66, state: .working)
        var bigOptions = CatDrawOptions()
        bigOptions.outfit = CatOutfitDraw.big(sheetOutfit, dpr: 2)   // `--outfit`: the big cat's cost with an outfit on
        // kittens (Ø15, with their state badges), drawn at 30 fps like the small cats: they are small cats too
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
            CatRenderer.draw(sheet.cg, big.e.look(time: big.clock.t / 1000), cx: 320, cy: 130, D: 66, CatDrawOptions())
```

Replace with:

```swift
            CatRenderer.draw(sheet.cg, big.e.look(time: big.clock.t / 1000), cx: 320, cy: 130, D: 66, bigOptions)
```

**Edit `scripts/render-cats-desktop.swift`**

Find:

```swift
            e.collar = state == .idle || state == .sleeping ? nil : "#E07950"
            let rng = CatRNG(seed: 5), herd = CatKittenHerd()
```

Replace with:

```swift
            e.collar = state == .idle || state == .sleeping ? nil : "#E07950"
            e.cfg.outfit = sheetOutfit   // `--outfit`: the cost with an outfit on
            let rng = CatRNG(seed: 5), herd = CatKittenHerd()
```


- [ ] **Step 2: Measure**

```bash
for id in none witchhat shrimpclip; do
  echo "== $id"
  RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench --outfit $id 2>&1 | tail -1
  RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench-desktop --outfit $id 2>&1 | grep "idle, no kittens"
done
```

Expected: for each of the three: a `12 small cats (30 fps) + the big one (60 fps) …` line within about 0.3 ms of Task 0's, and three `Ø48/Ø64/Ø96 idle, no kittens` lines each under 1 % of a core (the dry run: none 1.91 ms and Ø96 at 0.64 %; witchhat 1.97 ms and Ø96 at 0.68 %; shrimpclip, the busiest drawing, 1.99 ms and Ø96 at 0.69 %). `none` is the bare cat: its numbers are Task 0's. If any desktop line says `(held, under 1 %: NO)`, stop and report: the shape that did it goes to the owner.

- [ ] **Step 3: Draw the per-agent and Two cats sheets and look**

```bash
OUT="${TMPDIR:-/tmp}/i-mac-2"; mkdir -p "$OUT"
for mode in one perAgent two; do bash scripts/render-cats.sh --island --mode $mode --outfit partyhat --out "$OUT/island-$mode.png" 2>&1 | tail -1; done
bash scripts/render-cats.sh --island --mode two --outfit sunglasses --out "$OUT/island-two-sunglasses.png" 2>&1 | tail -1
bash scripts/render-cats.sh --desktop --outfit bell --out "$OUT/desktop-bell.png" 2>&1 | tail -1
bash scripts/render-cats.sh --desktop-flight --outfit crown --out "$OUT/desktop-flight-crown.png" 2>&1 | tail -1
```

Expected: six `wrote …` lines. Look at them: in One cat, A cat for each agent and Two cats the island's compact strip and the overview show every big cat dressed (in A cat for each agent the focused agent's coat, in Two cats both cats, each on its own coat) and every pill's cat bare; the desktop cat is dressed at three sizes with bare kittens, and the flight strip keeps the outfit on the cat through the arc.

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add scripts/render-cats.swift scripts/render-cats-desktop.swift
printf '%s\n' 'feat(wardrobe): the benches and the sheets take an outfit (I-mac task 9)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 10: Owner checkpoint 2: the bench numbers and the island sheets

No code and no commit.

- [ ] **Step 1: Gather the pictures and the numbers**

```bash
mkdir -p .claude/checkpoints/i-mac
cp "${TMPDIR:-/tmp}"/i-mac-2/*.png .claude/checkpoints/i-mac/
```

- [ ] **Step 2: Report to the main session and stop**

Send the report (the ping rule) with the bench lines of Task 9 for `none`, `witchhat` and `shrimpclip` and the paths of `island-one.png`, `island-perAgent.png`, `island-two.png`, `island-two-sunglasses.png`, `desktop-bell.png` and `desktop-flight-crown.png`, and say what to look for:

1. **The cost:** with an outfit on, the notch's big cat and the desktop cat cost what they did, and the desktop cat at every size stays under 1 % of a core idle and awake.
2. **Two cats and A cat for each agent:** every big cat is dressed on its own coat; the pills' cats are bare.
3. **The desktop cat** at three sizes with its kittens bare, and through the alert flight.

Then stop. Do not start Task 11 until the owner has answered.

### Task 11: The right-click menus: the island cat's (new) and the desktop cat's (step 6)

**`nm-implementer-deep`: trigger 1.** The desktop cat's menu gains a Wardrobe submenu after Size: `DesktopCatMenu.entries` takes the stored choice and today's Auto (a pure list, tested; without them the menu is exactly what H shipped), and the controller's `NSMenu` builder gets one more action (tags 100 to 117, the same numbers the island's menu uses). The island cat has **no right-click menu today**, so its menu is new, with **only Wardrobe in it**: a local `.rightMouseDown` monitor, which uses the big cats' hit test (`isBotHit(_, includeSecond: true)`: both cats of Two cats mode, the nearer centre wins), pops `WardrobeMenuTarget.islandCatMenu()` and returns the event as used. It reads **no** left-button event: the left-button monitors, the slap, the click that opens the island and the drag-out of the cat are untouched. While the menu is up the pointer is on it, outside the island, so the poll does not tell the island's state machine that the pointer left (`wardrobeMenuOpen` holds back `fsm.mouseLeft()` and keeps `wasInIsland` true) and the island is not folded under the user; when the menu closes the next poll sees the pointer outside and the normal leave runs. The `inIsland` line itself is not touched (`scripts/test-island-wing-wiring.sh` pins it). While the desktop cat is out the notch's cat spot is empty and `isBotHit` already says no, so the island shows no menu where there is no cat.

**What the implementer must check by reading** (and report one line each): `ignoresMouseEvents` is false while the pointer is in the island (the poll sets it), so the right-click arrives at the local monitor; `NSMenu.popUpContextMenu` blocks until the menu closes, so `defer` resets the flag; a right-click on the desktop cat's panel goes to `DesktopCatPanel.rightMouseDown`, never to this monitor; the 18 tags map to `Wardrobe.ids` by index.

**Interfaces.** Consumes: `WardrobeMenu.items`, `Wardrobe.autoOutfit`, `WardrobeClock.appToday` (Tasks 1 and 6), `CatSettingsStore.setOutfit` and `.wardrobe` (Task 2). Produces: `DesktopCatMenu.Action.outfit(String)`, `DesktopCatMenu.entries(size:shortcut:outfit:autoToday:)`, `WardrobeMenuTarget` (`shared`, `tag(for:)`, `id(forTag:)`, `picked(_:)`, `wardrobeSubmenu()`, `islandCatMenu()`).

- [ ] **Step 1: Write the tests**

**Edit `tests/DesktopCatInputTests.swift`**

Find:

```swift
        CT.check("and an empty shortcut is none", DesktopCatMenu.entries(size: .small, shortcut: "").count, 4)
```

Replace with:

```swift
        CT.check("and an empty shortcut is none", DesktopCatMenu.entries(size: .small, shortcut: "").count, 4)
        CT.check("the Wardrobe submenu is not there unless the caller gives the stored choice (the menu as H shipped it)", DesktopCatMenu.entries(size: .medium, shortcut: "⌃⌥D", outfit: nil), m)
        let dressed = DesktopCatMenu.entries(size: .medium, shortcut: "⌃⌥D", outfit: "bow", autoToday: "witchhat")
        CT.check("with it: Open the notch, Send home, Size, Wardrobe and the shortcut's line, in that order", dressed.count, 7)
        if case .submenu(let title, let items) = dressed[4] {
            CT.check("the Wardrobe menu", title, "Wardrobe")
            let choices = items.compactMap { e -> (String, String, Bool)? in if case .action(let t, .outfit(let id), let c) = e { return (id, t, c) } else { return nil } }
            CT.check("holds the 18 choices in the grid's order", choices.map(\.0), Wardrobe.ids)
            CT.check("with the stored one ticked and nothing else", choices.filter(\.2).map(\.0), ["bow"])
            CT.check("Auto's label shows today's result", choices[0].1, "Auto: today, Witch hat")
            CT.check("the groups' headings are greyed notes and the groups are set apart", [items.filter { if case .note = $0 { return true } else { return false } }.count, items.filter { $0 == .separator }.count], [4, 4])
        } else { CT.checkTrue("the fifth entry is the Wardrobe menu", false) }
        CT.check("and the shortcut's line is still last", dressed[6], .note("Out or home: ⌃⌥D"))
```

**Edit `scripts/test-cat-desktop-input.sh`**

Find:

```text
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatInput.swift \
```

Replace with:

```text
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/Wardrobe.swift $APP/WardrobeAuto.swift $APP/DesktopCatLayout.swift $APP/DesktopCatInput.swift \
```

**Edit `tests/WardrobeWiringTests.swift`**

Find:

```swift

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```

Replace with:

```swift

        CT.section("the island cat's right-click menu and the desktop cat's Wardrobe submenu")
        let island = source("IslandWindowController.swift"), menus = source("WardrobeMenuApp.swift"), dcc = source("DesktopCatController.swift")
        CT.checkTrue("the sources were read", island.contains("final class IslandWindowController") && menus.contains("WardrobeMenuTarget") && dcc.contains("func showMenu"))
        CT.check("one right-click monitor, and it asks the big cats' hit test (both of Two cats') before it shows anything", [count("matching: .rightMouseDown", in: island), count("isBotHit(event.locationInWindow, includeSecond: true)", in: island)], [1, 1])
        CT.checkTrue("the left-button monitors still use the hit test as before (cat 1 only)", count("guard self.isBotHit(event.locationInWindow) else { return }", in: island) == 1)
        CT.checkTrue("the menu keeps the island open while it is up (the pointer is on the menu, outside the island)", island.contains("if !inIsland && wasInIsland && !wardrobeMenuOpen {") && island.contains("wasInIsland = inIsland || wardrobeMenuOpen"))
        CT.checkTrue("the island cat's menu has Wardrobe in it and nothing else for now: one item", count("menu.addItem(", in: menus) == 1 && menus.contains("NSMenuItem(title: \"Wardrobe\"") && menus.contains("static func islandCatMenu()"))
        CT.checkTrue("the desktop cat's menu is given the stored choice and today's Auto, and a pick goes to the store", dcc.contains("outfit: store.wardrobe.outfit, autoToday: Wardrobe.autoOutfit(WardrobeClock.appToday())") && dcc.contains("store.setOutfit(WardrobeMenuTarget.id(forTag: t)!)"))

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```


- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-cat-desktop-input.sh 2>&1 | tail -3; bash scripts/test-wardrobe-wiring.sh 2>&1 | grep "✗" | head -4`
Expected: FAIL: `extra argument 'outfit' in call` for `DesktopCatMenu.entries` and the wiring section `the island cat's right-click menu and the desktop cat's Wardrobe submenu` with `✗` lines.

- [ ] **Step 3: Write the pure submenu, the menu builder and the two menus**

**Edit `NotchBuddy/Sources/App/DesktopCatInput.swift`**

Find:

```swift
/// The right-click menu: Open the notch, Send home, Size ▸ Small, Medium, Large (the current one ticked) and, on the Mac, a line showing the shortcut.
```

Replace with:

```swift
/// The right-click menu: Open the notch, Send home, Size ▸ Small, Medium, Large (the current one ticked), Wardrobe ▸ the 18 choices in their groups (sub-project I, the current one ticked)
/// and, on the Mac, a line showing the shortcut.
```

**Edit `NotchBuddy/Sources/App/DesktopCatInput.swift`**

Find:

```swift
    enum Action: Equatable, Sendable { case openNotch, sendHome, size(DesktopSize) }
```

Replace with:

```swift
    enum Action: Equatable, Sendable { case openNotch, sendHome, size(DesktopSize), outfit(String) }
```

**Edit `NotchBuddy/Sources/App/DesktopCatInput.swift`**

Find:

```swift
    /// `shortcut` is the display string of the `desktop` shortcut ("⌃⌥D") when it is on, nil when it is off or the platform has none.
    static func entries(size: DesktopSize, shortcut: String?) -> [Entry] {
```

Replace with:

```swift
    /// `shortcut` is the display string of the `desktop` shortcut ("⌃⌥D") when it is on, nil when it is off or the platform has none. `outfit` is the stored wardrobe choice and
    /// `autoToday` what Auto wears today (`Wardrobe.autoOutfit`): the Wardrobe submenu is there only when `outfit` is given.
    static func entries(size: DesktopSize, shortcut: String?, outfit: String? = nil, autoToday: String = "none") -> [Entry] {
```

**Edit `NotchBuddy/Sources/App/DesktopCatInput.swift`**

Find:

```swift
        ]
        if let shortcut, !shortcut.isEmpty { list += [.separator, .note("Out or home: \(shortcut)")] }
```

Replace with:

```swift
        ]
        if let outfit {
            list.append(.submenu(title: "Wardrobe", WardrobeMenu.items(selected: outfit, autoToday: autoToday).map { item in
                switch item {
                case .choice(let id, let title, let checked): return .action(title: title, .outfit(id), checked: checked)
                case .heading(let name): return .note(name)
                case .separator: return .separator
                }
            }))
        }
        if let shortcut, !shortcut.isEmpty { list += [.separator, .note("Out or home: \(shortcut)")] }
```

**Create `NotchBuddy/Sources/App/WardrobeMenuApp.swift`**

```swift
import AppKit

// The island cat's right-click menu (sub-project I): a new menu with only Wardrobe in it for now, as an `NSMenu` built from the pure `WardrobeMenu.items` (the same items the desktop cat's menu
// turns into its own Wardrobe submenu). A pick goes to the store (`CatSettingsStore.setOutfit`); the clock that resolves it follows. The menu is built on every right-click, so the check and
// Auto's label are always today's. Not in the contract, and the test programs do not compile this file.

@MainActor
final class WardrobeMenuTarget: NSObject {
    static let shared = WardrobeMenuTarget()
    /// The tag of a menu item that picks `Wardrobe.ids[tag - tagBase]` (the desktop cat's menu uses the same numbers).
    static let tagBase = 100

    static func tag(for id: String) -> Int { tagBase + (Wardrobe.ids.firstIndex(of: id) ?? 0) }
    static func id(forTag tag: Int) -> String? { Wardrobe.ids.indices.contains(tag - tagBase) ? Wardrobe.ids[tag - tagBase] : nil }

    @objc func picked(_ item: NSMenuItem) {
        guard let id = Self.id(forTag: item.tag) else { return }
        CatSettingsStore.shared.setOutfit(id)
    }

    /// The Wardrobe submenu: 18 choices in their groups, a check on the stored one.
    static func wardrobeSubmenu() -> NSMenu {
        let sub = NSMenu(title: "Wardrobe")
        for item in WardrobeMenu.items(selected: CatSettingsStore.shared.wardrobe.outfit, autoToday: Wardrobe.autoOutfit(WardrobeClock.appToday())) {
            switch item {
            case .separator: sub.addItem(.separator())
            case .heading(let name):
                let h = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                h.isEnabled = false
                sub.addItem(h)
            case .choice(let id, let title, let checked):
                let i = NSMenuItem(title: title, action: #selector(WardrobeMenuTarget.picked(_:)), keyEquivalent: "")
                i.target = shared; i.tag = tag(for: id); i.state = checked ? .on : .off
                sub.addItem(i)
            }
        }
        return sub
    }

    /// The island cat's menu: Wardrobe, and nothing else for now.
    static func islandCatMenu() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Wardrobe", action: nil, keyEquivalent: "")
        item.submenu = wardrobeSubmenu()
        menu.addItem(item)
        return menu
    }
}
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**

Find:

```swift
        add(DesktopCatMenu.entries(size: store.desktop.size, shortcut: shortcut), to: menu)
```

Replace with:

```swift
        add(DesktopCatMenu.entries(size: store.desktop.size, shortcut: shortcut, outfit: store.wardrobe.outfit, autoToday: Wardrobe.autoOutfit(WardrobeClock.appToday())), to: menu)
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**

Find:

```swift
        case .size(let s): return 10 + DesktopSize.allCases.firstIndex(of: s)!
        }
```

Replace with:

```swift
        case .size(let s): return 10 + DesktopSize.allCases.firstIndex(of: s)!
        case .outfit(let id): return WardrobeMenuTarget.tag(for: id)   // 100 to 117
        }
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**

Find:

```swift
        case 10...12: store.setDesktopSize(DesktopSize.allCases[item.tag - 10])
        default: break
```

Replace with:

```swift
        case 10...12: store.setDesktopSize(DesktopSize.allCases[item.tag - 10])
        case let t where WardrobeMenuTarget.id(forTag: t) != nil: store.setOutfit(WardrobeMenuTarget.id(forTag: t)!)   // Wardrobe ▸ (sub-project I)
        default: break
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift
        if !inIsland && wasInIsland {
```

Replace with:

```swift
        if !inIsland && wasInIsland && !wardrobeMenuOpen {   // the Wardrobe menu is up: the pointer is on it, and the island stays open under it
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift
        wasInIsland = inIsland
```

Replace with:

```swift
        wasInIsland = inIsland || wardrobeMenuOpen
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift

        // Track last external app for window context capture
```

Replace with:

```swift

        // A right-click on a big cat opens the Wardrobe menu (sub-project I). It reads no left-button event: a click, a drag, a slap and the drag-out of the cat are as they were.
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.showWardrobeMenu(for: event) }
            return handled ? nil : event
        }

        // Track last external app for window context capture
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift
                self.state.lastExternalApp = app
            }
        }
    }

    /// The big cat was let go at `mouse` (AppKit's coordinates). A drop on another app's window attaches that window to a chat, exactly as before (not in the App Store build);
```

Replace with:

```swift
                self.state.lastExternalApp = app
            }
        }
    }

    /// Whether the island's cat menu is open: the pointer is on the menu, outside the island, and the island must not fold under it while the user picks.
    private var wardrobeMenuOpen = false

    /// The island cat's right-click menu, with only Wardrobe in it for now. True when it was shown (the event is used), false for a right-click anywhere else (it goes on as it did).
    private func showWardrobeMenu(for event: NSEvent) -> Bool {
        guard event.window === window, wasInIsland, isBotHit(event.locationInWindow, includeSecond: true), let view = window?.contentView else { return false }
        wardrobeMenuOpen = true
        defer { wardrobeMenuOpen = false }
        NSMenu.popUpContextMenu(WardrobeMenuTarget.islandCatMenu(), with: event, for: view)
        return true
    }

    /// The big cat was let go at `mouse` (AppKit's coordinates). A drop on another app's window attaches that window to a chat, exactly as before (not in the App Store build);
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift
    private func isBotHit(_ windowPoint: CGPoint) -> Bool {
```

Replace with:

```swift
    /// `includeSecond`: a press on cat 2 of Two cats mode counts too (the right-click menu belongs to both big cats; the slap and the drag-out stay cat 1's).
    private func isBotHit(_ windowPoint: CGPoint, includeSecond: Bool = false) -> Bool {
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift
        return CatIslandLayout.bigCatPressed(x: Double(windowPoint.x), y: Double(windowPoint.y), cat1: .init(x: Double(botX), y: Double(botY), r: Double(radius)), cat2: second)
```

Replace with:

```swift
        let first = CatIslandLayout.HitCircle(x: Double(botX), y: Double(botY), r: Double(radius))
        let hit = CatIslandLayout.bigCatPressed(x: Double(windowPoint.x), y: Double(windowPoint.y), cat1: first, cat2: second)
        guard !hit, includeSecond, let second else { return hit }
        return CatIslandLayout.bigCatPressed(x: Double(windowPoint.x), y: Double(windowPoint.y), cat1: second, cat2: first)
```

**Edit `scripts/render-cats.sh`**

Find:

```text
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatInput.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift \
```

Replace with:

```text
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/WardrobeAuto.swift $APP/DesktopCatLayout.swift $APP/DesktopCatInput.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift \
```


- [ ] **Step 4: Run the tests, regenerate the project and build**

Run: `bash scripts/test-cat-desktop-input.sh 2>&1 | grep -v "✓" | tail -4; bash scripts/test-wardrobe-wiring.sh 2>&1 | tail -2; bash scripts/test-cat-press.sh 2>&1 | tail -1; bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -1; bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1`
Expected: five runs ending `All tests passed.` (the press test is the big-cat hit test, `CatIslandLayout.bigCatPressed`, which this task calls and does not change; the two wiring programs pin the H and wing code in the files this task edits).

```bash
cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **` and no new warning in `WardrobeMenuApp.swift`, `IslandWindowController.swift` or `DesktopCatController.swift`. The build only builds: the menus are checked on the owner's real build (Task 16).

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/DesktopCatInput.swift NotchBuddy/Sources/App/WardrobeMenuApp.swift NotchBuddy/Sources/App/DesktopCatController.swift NotchBuddy/Sources/App/IslandWindowController.swift tests/DesktopCatInputTests.swift scripts/test-cat-desktop-input.sh scripts/render-cats.sh tests/WardrobeWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
printf '%s\n' 'feat(wardrobe): a right-click Wardrobe menu on the island cat and on the desktop cat (I-mac task 11)' '' 'Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 12: ⌃⌥G, the next outfit (step 7)

**`nm-implementer-deep`: trigger 1.** The `wardrobe` action is **appended last** to `ShortcutAction` (Carbon identifies a registered hot key by its index in `allCases`, so no registered key moves), with ⌃⌥G (virtual key 5, the same `ctrlOpt` flags as ⌃⌥D), **off by default** (⌃⌥D is on by default; this one is not, so it can't take a key from someone who never asked), in every build, App Store included. Each press runs `CatSettingsStore.nextOutfit()`: the next ID in the grid's order, `auto` and `none` included, wrapping from `blossomclip` to `auto`. Settings → Shortcuts lists it with the others (the list is `ShortcutLogic.available()`: no view changes) and the existing conflict check applies. The shortcut tests and the hot-key test count the tenth action; their numbers change by the shape of one more action (the sixth default-on action stays six, the off ones become four).

**What the implementer must check by reading** (and report one line each): `ShortcutLogic.defaults` has a spec for every case (the test requires it); ⌃⌥G is not used by another default (A, T, W, M, D, `]`, `[`, Space and ⌘⇧N are); `HotKeyCenter` registers by iterating `allCases`, so it needs no edit.

**Interfaces.** Consumes: `CatSettingsStore.nextOutfit()` (Task 2). Produces: `ShortcutAction.wardrobe` (displayName "Next outfit").

- [ ] **Step 1: Write the tests**

**Edit `tests/ShortcutTests.swift`**

Find:

```swift
        check(ShortcutAction.allCases.first == .toggleIsland && ShortcutAction.allCases.last == .desktop,
```

Replace with:

```swift
        check(ShortcutAction.allCases.first == .toggleIsland && ShortcutAction.allCases.last == .wardrobe,
```

**Edit `tests/ShortcutTests.swift`**

Find:

```swift
    /// The owner's decision: five on, three off, and since sub-project H the desktop cat's ⌃⌥D on as well (six on). The off ones keep their combinations so that turning one on is a click.
```

Replace with:

```swift
    /// The owner's decision: five on, three off, and since sub-project H the desktop cat's ⌃⌥D on as well (six on). Since sub-project I ⌃⌥G, the next outfit, is off at first (four off), so it
    /// cannot take a key from someone who never asked. The off ones keep their combinations so that turning one on is a click.
```

**Edit `tests/ShortcutTests.swift`**

Find:

```swift
        let off: Set<ShortcutAction> = [.toggleIsland, .openChat, .jumpToTerminal]
```

Replace with:

```swift
        let off: Set<ShortcutAction> = [.toggleIsland, .openChat, .jumpToTerminal, .wardrobe]
```

**Edit `tests/ShortcutTests.swift`**

Find:

```swift
            check(ShortcutLogic.hotKey(for: .desktop, in: ud) == ShortcutSpec(keyCode: 2, nsFlags: ctrlOpt), "⌃⌥D is the desktop cat's")
            // Off at first, and the combination is still there: a click turns it on.
```

Replace with:

```swift
            check(ShortcutLogic.hotKey(for: .desktop, in: ud) == ShortcutSpec(keyCode: 2, nsFlags: ctrlOpt), "⌃⌥D is the desktop cat's")
            check(ShortcutLogic.hotKey(for: .wardrobe, in: ud) == ShortcutSpec(keyCode: 5, nsFlags: ctrlOpt) && !ShortcutLogic.isEnabled(.wardrobe, in: ud), "⌃⌥G is the wardrobe's, and it is off at first")
            // Off at first, and the combination is still there: a click turns it on.
```

**Edit `tests/ShortcutTests.swift`**

Find:

```swift
        // Nothing is taken: everything comes on, and only the three that were off are tried.
```

Replace with:

```swift
        // Nothing is taken: everything comes on, and only the four that were off are tried.
```

**Edit `tests/ShortcutTests.swift`**

Find:

```swift
            check(tried == [.toggleIsland, .openChat, .jumpToTerminal], "only the shortcuts that were off are tried, in list order: \(tried)")
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == Set(ShortcutAction.allCases), "all nine are on")
```

Replace with:

```swift
            check(tried == [.toggleIsland, .openChat, .jumpToTerminal, .wardrobe], "only the shortcuts that were off are tried, in list order: \(tried)")
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == Set(ShortcutAction.allCases), "all ten are on")
```

**Edit `tests/ShortcutTests.swift`**

Find:

```swift
            check(left.isEmpty && asked == [.toggleIsland, .openChat], "the App Store build tries only what it offers: \(asked)")
```

Replace with:

```swift
            check(left.isEmpty && asked == [.toggleIsland, .openChat, .wardrobe], "the App Store build tries only what it offers: \(asked)")
```

**Edit `tests/HotKeyCenterTests.swift`**

Find:

```swift
    static let fKeys: [UInt16] = [105, 107, 113, 106, 64, 79, 80, 10]
```

Replace with:

```swift
    static let fKeys: [UInt16] = [105, 107, 113, 106, 64, 79, 80, 10, 111]
```

**Edit `tests/HotKeyCenterTests.swift`**

Find:

```swift
        check(actions.count == 8, "eight actions besides the island shortcut")
```

Replace with:

```swift
        check(actions.count == 9, "nine actions besides the island shortcut")
```

**Edit `tests/HotKeyCenterTests.swift`**

Find:

```swift
        // Start: what is on at first is registered (six of the nine), and a press runs the right action, once.
```

Replace with:

```swift
        // Start: what is on at first is registered (six of the ten), and a press runs the right action, once.
```

**Edit `tests/HotKeyCenterTests.swift`**

Find:

```swift
        // "Turn all on" with the real thing behind it: the other three are registered (the desktop cat's is on already), and delivered.
```

Replace with:

```swift
        // "Turn all on" with the real thing behind it: the other four are registered (the desktop cat's is on already), and delivered.
```

**Edit `tests/HotKeyCenterTests.swift`**

Find:

```swift
        check(center.registered == Set(ShortcutAction.allCases), "all nine are registered")
```

Replace with:

```swift
        check(center.registered == Set(ShortcutAction.allCases), "all ten are registered")
```

**Edit `tests/HotKeyCenterTests.swift`**

Find:

```swift
        check(center.registered.count == 8, "the others stay")
```

Replace with:

```swift
        check(center.registered.count == 9, "the others stay")
```

**Edit `tests/HotKeyCenterTests.swift`**

Find:

```swift
        check(center.registered.count == 8 && !center.registered.contains(.muteToggle),
              "nine are on, the refused one is not registered: \(center.registered.count)")
```

Replace with:

```swift
        check(center.registered.count == 9 && !center.registered.contains(.muteToggle),
              "ten are on, the refused one is not registered: \(center.registered.count)")
```

**Edit `tests/WardrobeWiringTests.swift`**

Find:

```swift

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```

Replace with:

```swift

        CT.section("⌃⌥G: the last action, off by default, in every build")
        let logic = source("ShortcutLogic.swift")
        CT.checkTrue("the source was read", logic.contains("enum ShortcutAction"))
        CT.checkTrue("it is after the desktop cat's, off at first, and not an App Store exclusion", logic.contains("case wardrobe ") && at("case wardrobe ", in: logic) > at("case desktop ", in: logic) && logic.contains("case .toggleIsland, .openChat, .jumpToTerminal, .wardrobe: return false") && !logic.contains("case .wardrobe: return true") && logic.contains("var isNonAppStore: Bool { self == .jumpToTerminal || self == .attachFrontWindow }"))
        CT.checkTrue("the press moves the stored choice on", island.contains("case .wardrobe:\n            CatSettingsStore.shared.nextOutfit()"))

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```


- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-shortcuts.sh 2>&1 | tail -2; bash scripts/test-hotkeys.sh 2>&1 | tail -2; bash scripts/test-wardrobe-wiring.sh 2>&1 | grep "✗" | head -3`
Expected: FAIL: a compile error that names `wardrobe` (`ShortcutAction` has no such member) for the first two and the section `⌃⌥G: the last action, off by default, in every build` with `✗` lines.

- [ ] **Step 3: Write the action and its press**

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**

Find:

```swift
    case desktop            // ⌃⌥D: the big cat out on the desktop, or home in the notch. On by default; in the App Store build too. The action ID is frozen.
```

Replace with:

```swift
    case desktop            // ⌃⌥D: the big cat out on the desktop, or home in the notch. On by default; in the App Store build too. The action ID is frozen.
    case wardrobe           // ⌃⌥G: the next outfit in the wardrobe's order (Auto and None included, wrapping). Off by default; in the App Store build too. The action ID is frozen.
```

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**

Find:

```swift
        case .desktop:           return "Cat on the desktop"
        }
```

Replace with:

```swift
        case .desktop:           return "Cat on the desktop"
        case .wardrobe:          return "Next outfit"
        }
```

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**

Find:

```swift
        case .toggleIsland, .openChat, .jumpToTerminal: return false
```

Replace with:

```swift
        case .toggleIsland, .openChat, .jumpToTerminal, .wardrobe: return false
```

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**

Find:

```swift
        case .toggleIsland, .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle, .desktop:
```

Replace with:

```swift
        case .toggleIsland, .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle, .desktop, .wardrobe:
```

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**

Find:

```swift
        .desktop:           ShortcutSpec(keyCode: 2,  nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥D
    ]
```

Replace with:

```swift
        .desktop:           ShortcutSpec(keyCode: 2,  nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥D
        .wardrobe:          ShortcutSpec(keyCode: 5,  nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥G
    ]
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift
            desktop?.toggle()
        }
```

Replace with:

```swift
            desktop?.toggle()

        case .wardrobe:
            CatSettingsStore.shared.nextOutfit()   // the next outfit in the grid's order, Auto and None included
        }
```


- [ ] **Step 4: Run the tests and build**

Run: `bash scripts/test-shortcuts.sh 2>&1 | tail -1; bash scripts/test-hotkeys.sh 2>&1 | tail -1; bash scripts/test-wardrobe-wiring.sh 2>&1 | tail -1`
Expected: `Shortcuts: 520 cases passed` (Task 0 read 508), `HotKeyCenter: 19 cases passed` and `All tests passed.`

```bash
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```

Expected: two `** BUILD SUCCEEDED **`: the switch in `handleHotKey` is exhaustive in both builds.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/ShortcutLogic.swift NotchBuddy/Sources/App/IslandWindowController.swift tests/ShortcutTests.swift tests/HotKeyCenterTests.swift tests/WardrobeWiringTests.swift
printf '%s\n' 'feat(wardrobe): control-option-G puts on the next outfit, off by default (I-mac task 12)' '' 'Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 13: The Debug panel's wardrobe controls and the date override

The Debug-only "Cats (Debug)…" panel gains a Wardrobe section below Desktop: a live big cat in any of the 16 outfits on any coat at six sizes (on a `CatConfig` of its own: the app's cats are untouched), and the two controls the owner's real-build checks need, which DO reach the running app's Auto: **Pretend today is** (a date field, `Apply` and `Back to today`) and **Midnight in 5 s** (the wardrobe's one timer fires in five seconds and the pretend date moves on a day, so the one-shot can be watched). They go through two notifications that `WardrobeClock+App` listens to in a Debug build (Task 6), so the panel compiles without the app's files. The whole section is `#if DEBUG && !APPSTORE`, marker `NM_CAT_DEV_WARDROBE`, and `check-app-binary.sh` proves a Release build and an App Store build do not contain it.

**Interfaces.** Consumes: `WardrobePreviewView` (Task 7), `WardrobeDev`, `Wardrobe.parseDay` (Task 1). Produces: `WardrobeDevView`, `WardrobeDev.marker`, `.sizes`.

- [ ] **Step 1: Write the pins**

**Edit `tests/WardrobeWiringTests.swift`**

Find:

```swift

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```

Replace with:

```swift

        CT.section("the Debug panel's Wardrobe section: Debug-only, below Desktop, talking to the clock through notifications")
        let dev = source("WardrobeDevPanel.swift"), devPanel = source("CatDevPanel.swift")
        CT.checkTrue("the sources were read", dev.contains("struct WardrobeDevView") && devPanel.contains("DesktopCatDevView()"))
        CT.checkTrue("the file is compiled in Debug builds only", dev.hasPrefix("import SwiftUI\nimport QuartzCore\n\n#if DEBUG && !APPSTORE") && dev.hasSuffix("#endif\n"))
        CT.checkTrue("it is below the Desktop section", at("WardrobeDevView()", in: devPanel) > at("DesktopCatDevView()", in: devPanel))
        CT.checkTrue("the panel posts the date and the midnight, and the app's clock listens for them (Debug only)", dev.contains("NotificationCenter.default.post(name: WardrobeDev.dateNote") && dev.contains("NotificationCenter.default.post(name: WardrobeDev.midnightNote") && source("WardrobeClock+App.swift").contains("publisher(for: WardrobeDev.dateNote)") && source("WardrobeAuto.swift").contains("#if DEBUG && !APPSTORE\n/// The names the Debug cat panel's Wardrobe section"))

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
```


- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-wardrobe-wiring.sh 2>&1 | grep "✗" | head -3`
Expected: FAIL: `the Debug panel's Wardrobe section: …` with `✗` lines.

- [ ] **Step 3: Write the section**

**Create `NotchBuddy/Sources/App/WardrobeDevPanel.swift`**

```swift
import SwiftUI
import QuartzCore

#if DEBUG && !APPSTORE

/// The Wardrobe section of the Debug-only cat panel (sub-project I): a live big cat in any outfit on any coat at any size (on a `CatConfig` of its own: the app's cats are untouched), and the two
/// controls the owner's real-build checks need, which DO reach the running app's Auto: a date Auto reads instead of today's, and a pretend midnight five seconds away. They go through
/// notifications that the app's `WardrobeClock` listens to in a Debug build, so this file compiles without the app. Compiled in Debug builds only (`WardrobeDev.marker`).
extension WardrobeDev {
    /// In a Debug build and in no other (19 bytes: a shorter string would hide in the code where `strings` cannot see it).
    static let marker = "NM_CAT_DEV_WARDROBE"
    static let sizes: [Double] = [12, 20, 28, 48, 64, 96]
}

struct WardrobeDevView: View {
    @State private var outfit = "santahat"
    @State private var coat = "momo"
    @State private var size = 64.0
    @State private var date = ""
    @State private var note = "No date is pretended: Auto reads today's."
    private let config = CatConfig()

    var body: some View {
        GroupBox("Wardrobe") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    WardrobePreviewView(coat: coat, outfit: outfit, head: size, active: true, config: config)
                        .frame(width: 200, height: 170)
                        .accessibilityIdentifier(WardrobeDev.marker)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Outfit", selection: $outfit) { ForEach(Wardrobe.drawn, id: \.self) { Text(Wardrobe.name($0)).tag($0) } }
                        Picker("Coat", selection: $coat) { ForEach(CatPresets.ids, id: \.self) { Text(CatPresets.byID($0).label).tag($0) } }
                        Picker("Size", selection: $size) { ForEach(WardrobeDev.sizes, id: \.self) { Text("Ø\(Int($0))").tag($0) } }.pickerStyle(.segmented)
                    }
                }
                HStack(spacing: 8) {
                    Text("Pretend today is").frame(width: 120, alignment: .leading)
                    TextField("2026-12-24", text: $date).frame(width: 120)
                    Button("Apply") {
                        if let day = Wardrobe.parseDay(date) {
                            NotificationCenter.default.post(name: WardrobeDev.dateNote, object: nil, userInfo: ["day": date])
                            note = "Auto reads \(date) and wears \(Wardrobe.autoLabel(today: Wardrobe.autoOutfit(day)).replacingOccurrences(of: "Auto: today, ", with: ""))."
                        } else { note = "A date looks like 2026-12-24." }
                    }
                    Button("Back to today") {
                        date = ""
                        NotificationCenter.default.post(name: WardrobeDev.dateNote, object: nil, userInfo: ["day": ""])
                        note = "No date is pretended: Auto reads today's."
                    }
                    Button("Midnight in 5 s") {
                        NotificationCenter.default.post(name: WardrobeDev.midnightNote, object: nil)
                        note = "The wardrobe's one timer fires in five seconds and the pretend date moves on a day."
                    }
                }
                Text(note).font(.system(size: 11)).foregroundColor(.secondary)
                Text("The cat above is drawn on its own settings. The date and the midnight reach the running app's Auto (only while Auto is the stored choice), in Debug builds only.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

#endif
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`**

Find:

```swift
            DesktopCatDevView()
            ladder
```

Replace with:

```swift
            DesktopCatDevView()
            WardrobeDevView()
            ladder
```

**Edit `scripts/render-cat-panel.sh`**

Find:

```text
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift $APP/DesktopCatDevModel.swift $APP/DesktopCatDevPanel.swift \
```

Replace with:

```text
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift $APP/DesktopCatDevModel.swift $APP/DesktopCatDevPanel.swift $APP/WardrobeAuto.swift $APP/WardrobePreviewViews.swift $APP/WardrobeDevPanel.swift \
```

**Edit `scripts/check-app-binary.sh`**

Find:

```text
# The Desktop section of the cat panel (sub-project H) is Debug-only too.
```

Replace with:

```text
# The Desktop section of the cat panel (sub-project H) and its Wardrobe section (sub-project I) are Debug-only too.
```

**Edit `scripts/check-app-binary.sh`**

Find:

```text
devdesk=0; has NM_CAT_DEV_DESKTOP && devdesk=1
override=0; has NM_CLAUDE_CODE_PATH_OVERRIDE && override=1
```

Replace with:

```text
devdesk=0; has NM_CAT_DEV_DESKTOP && devdesk=1
devward=0; has NM_CAT_DEV_WARDROBE && devward=1
override=0; has NM_CLAUDE_CODE_PATH_OVERRIDE && override=1
```

**Edit `scripts/check-app-binary.sh`**

Find:

```text
        [ "$devdesk" = 0 ] || { echo "✗ the Debug-only Desktop section of the cat panel (NM_CAT_DEV_DESKTOP) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is in this build" >&2; exit 1; }
```

Replace with:

```text
        [ "$devdesk" = 0 ] || { echo "✗ the Debug-only Desktop section of the cat panel (NM_CAT_DEV_DESKTOP) is in this build" >&2; exit 1; }
        [ "$devward" = 0 ] || { echo "✗ the Debug-only Wardrobe section of the cat panel (NM_CAT_DEV_WARDROBE) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is in this build" >&2; exit 1; }
```

**Edit `scripts/check-app-binary.sh`**

Find:

```text
        [ "$devdesk" = 0 ] || { echo "✗ the Debug-only Desktop section of the cat panel (NM_CAT_DEV_DESKTOP) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override is in this build" >&2; exit 1; }
```

Replace with:

```text
        [ "$devdesk" = 0 ] || { echo "✗ the Debug-only Desktop section of the cat panel (NM_CAT_DEV_DESKTOP) is in this build" >&2; exit 1; }
        [ "$devward" = 0 ] || { echo "✗ the Debug-only Wardrobe section of the cat panel (NM_CAT_DEV_WARDROBE) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override is in this build" >&2; exit 1; }
```

**Edit `scripts/check-app-binary.sh`**

Find:

```text
        [ "$devdesk" = 1 ] || { echo "✗ the cat panel's Desktop section (NM_CAT_DEV_DESKTOP) is missing from this Debug build" >&2; exit 1; }
        [ "$override" = 1 ] || { echo "✗ the Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is missing from this Debug build" >&2; exit 1; }
```

Replace with:

```text
        [ "$devdesk" = 1 ] || { echo "✗ the cat panel's Desktop section (NM_CAT_DEV_DESKTOP) is missing from this Debug build" >&2; exit 1; }
        [ "$devward" = 1 ] || { echo "✗ the cat panel's Wardrobe section (NM_CAT_DEV_WARDROBE) is missing from this Debug build" >&2; exit 1; }
        [ "$override" = 1 ] || { echo "✗ the Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is missing from this Debug build" >&2; exit 1; }
```


- [ ] **Step 4: Run the pins, draw the panel and build the three builds**

Run: `bash scripts/test-wardrobe-wiring.sh 2>&1 | tail -1; bash scripts/test-cat-devpanel.sh 2>&1 | tail -1`
Expected: two `All tests passed.`

```bash
OUT="${TMPDIR:-/tmp}/i-mac-3"; mkdir -p "$OUT"
bash scripts/render-cat-panel.sh --height 2700 --out "$OUT/panel.png" 2>&1 | tail -1
```

Expected: `wrote …/panel.png`. Look at it: below the Desktop section is a **Wardrobe** section with the cat in a Santa hat, the Outfit, Coat and Size pickers, the date field and its three buttons.

```bash
cd NotchBuddy && xcodegen && cd ..
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -2
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -2
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -2
bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug 2>&1 | tail -5
bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app release 2>&1 | tail -5
bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore 2>&1 | tail -5
```

Expected: three `** BUILD SUCCEEDED **`, then for each binary `✓ The desktop cat is in this build` and `✓ The wardrobe is in this build`; the Debug one ends `✓ The cat panel, the Claude Code engine and its override are in this Debug build`, the Release one `✓ No cat panel and no Claude Code override in this build; the Claude Code engine is in it`, the App Store one `✓ No cat panel and no Claude Code engine in this build`. (`NM_CAT_DEV_WARDROBE` is required in the Debug build and refused in the other two; `NM_WARDROBE_OUTFITS` is required in all three.)

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add NotchBuddy/Sources/App/WardrobeDevPanel.swift NotchBuddy/Sources/App/CatDevPanel.swift scripts/render-cat-panel.sh scripts/check-app-binary.sh tests/WardrobeWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
printf '%s\n' 'feat(wardrobe): the Debug panel wardrobe controls and the date override (I-mac task 13)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 14: Docs, CI and the final checks (step 8)

CLAUDE.md gets the Mac line of sub-project I (the files, the role rule, the tests, the marker), ARCHITECT.md the Mac paragraph, README the roadmap row, `docs/SPEC.md` the French section "La garde-robe" (after "Le chat de bureau") and the Windows tests workflow aside, `.github/workflows/build.yml` one step for each new script. Then the full run of everything this plan touched.

- [ ] **Step 1: Write the docs and the CI steps**

**Edit `CLAUDE.md`**

Find:

```markdown
- Sub-project H on the Mac (the desktop cat): the pure rules are `DesktopCatSpots.swift` (screens, `screenKey`, `clampSpot`, `spotFor`), `DesktopCatSettings.swift` (the keys `cat.desktop.on`, `cat.desktop.size` and `cat.desktop.spots`, cleaned by `DesktopCatSettings.clean`), `DesktopCatTrip.swift` (`desktopStep`, the flight and its clock, `desktopFps`, the kittens' slots), `DesktopCatLayout.swift` (the window around the cat and its body shape), `DesktopCatInput.swift` (click, double-click and drag, the right-click menu), `DesktopCatDrop.swift` (a window attaches, empty desktop places the cat) and `DesktopCatPacer.swift` (the one timer); the app's side is `DesktopCatController.swift` (the trip, the frame timer, the mouse), `DesktopCatPanel.swift` (a non-activating floating panel that is never key, on every Space, outside fullscreen), `DesktopCatDraw.swift` (one function draws it, in the app and on the sheets) and `DesktopCatScreensApp.swift`. **It is in Debug, Release and App Store builds** (`check-app-binary.sh` looks for `NM_DESKTOP_CAT_PANEL`), and the notch's big-cat spot, its kittens and its hit area are empty while the cat is out (`AppState.desktopPhase`). The shortcut action ID `desktop` (⌃⌥D, on by default) is frozen like the size IDs. The tests are `scripts/test-cat-desktop-{settings,trip,layout,input,drop,pacer,wiring,devpanel}.sh`; `render-cats.sh --desktop [--shapes]`, `--desktop-flight` and `--bench-desktop` draw and measure it without the app, and the Debug-only "Cats (Debug)…" panel has a live Desktop section (`DesktopCatDevPanel.swift`, marker `NM_CAT_DEV_DESKTOP`, compiled out of Release and App Store).
- `tests/fixtures/shelf/`, `docs/SHELF-CONTRACT.md` — the shelf contract (sub-project G1-0): `zoneAt` (Ask or Shelf half), `shelfClean` (how `shelf.json` is read: ids, names, links, duplicates, the 30-item cap, newest first) and `shelfAdd` (a drop never evicts). `reference.py` (Python, standard library) decides when an app and a fixture disagree; `build_cases.py` writes the two JSON files; `scripts/test-shelf-contract.sh` runs them. No Swift, TypeScript or JS source holds these rules until the G1 app plans port them.
```

Replace with:

```markdown
- Sub-project H on the Mac (the desktop cat): the pure rules are `DesktopCatSpots.swift` (screens, `screenKey`, `clampSpot`, `spotFor`), `DesktopCatSettings.swift` (the keys `cat.desktop.on`, `cat.desktop.size` and `cat.desktop.spots`, cleaned by `DesktopCatSettings.clean`), `DesktopCatTrip.swift` (`desktopStep`, the flight and its clock, `desktopFps`, the kittens' slots), `DesktopCatLayout.swift` (the window around the cat and its body shape), `DesktopCatInput.swift` (click, double-click and drag, the right-click menu), `DesktopCatDrop.swift` (a window attaches, empty desktop places the cat) and `DesktopCatPacer.swift` (the one timer); the app's side is `DesktopCatController.swift` (the trip, the frame timer, the mouse), `DesktopCatPanel.swift` (a non-activating floating panel that is never key, on every Space, outside fullscreen), `DesktopCatDraw.swift` (one function draws it, in the app and on the sheets) and `DesktopCatScreensApp.swift`. **It is in Debug, Release and App Store builds** (`check-app-binary.sh` looks for `NM_DESKTOP_CAT_PANEL`), and the notch's big-cat spot, its kittens and its hit area are empty while the cat is out (`AppState.desktopPhase`). The shortcut action ID `desktop` (⌃⌥D, on by default) is frozen like the size IDs. The tests are `scripts/test-cat-desktop-{settings,trip,layout,input,drop,pacer,wiring,devpanel}.sh`; `render-cats.sh --desktop [--shapes]`, `--desktop-flight` and `--bench-desktop` draw and measure it without the app, and the Debug-only "Cats (Debug)…" panel has a live Desktop section (`DesktopCatDevPanel.swift`, marker `NM_CAT_DEV_DESKTOP`, compiled out of Release and App Store).
- Sub-project I on the Mac (the wardrobe): the pure rules are `Wardrobe.swift` (the 18 frozen selection IDs and their order, `idOf`, who wears it, the ⌃⌥G cycle), `WardrobeSettings.swift` (the key `cat.outfit`, cleaned by `WardrobeSettings.clean`, default `auto`), `WardrobeAuto.swift` (`easterOf`, `autoOutfit`, `resolve`, `WardrobeMenu`, and `WardrobeClock`: the resolved outfit and Auto's ONE wall-clock one-shot at the next local midnight, which exists only while the choice is `auto`; no polling) and `CatOutfit.swift` (the anchors, the shapes of the 16 outfits, the digest: a port of `outfitAnchors` and `outfitGeometry`, replayed against `wardrobe-cases.json` by `scripts/test-wardrobe-{settings,auto,geometry}.sh`). `CatOutfitDraw.swift` paints the shapes at the three slots `CatRenderer` calls (`behind` after the ears, `neck` after the collar, `top` after `neck`, always before the whiskers); the colours are `Theme.Outfits`. **Who wears it is the role, never the diameter:** `CatDrawOptions.outfit` is set only by the five big-cat views (`BotCanvasView`, `PairCatCanvasView`, the file catch's cat in `UploadCanvasView`, `DesktopCatDraw` and the greeting, which puts it on once the cat has settled) from `engine.cfg.outfit`, which `WardrobeClock` keeps (`WardrobeClock+App.swift`); the pills' cats, the mini row, the grid and the kittens never set it. Pickers: `WardrobeSettingsView.swift` (Settings → Cat → Wardrobe, a live preview and a coat picker that stores nothing), the island cat's new right-click menu with only Wardrobe in it (`WardrobeMenuApp.swift`, the monitor in `IslandWindowController`), a Wardrobe submenu in the desktop cat's menu, and ⌃⌥G (action ID `wardrobe`, frozen, off by default, in every build). **It is in Debug, Release and App Store builds** (`check-app-binary.sh` looks for `NM_WARDROBE_OUTFITS`); the Debug-only "Cats (Debug)…" panel has a Wardrobe section with a date override and a pretend midnight (`WardrobeDevPanel.swift`, marker `NM_CAT_DEV_WARDROBE`, compiled out of Release and App Store). The other tests are `scripts/test-wardrobe-{draw,wiring}.sh`; `render-cats.sh --wardrobe [--part sheet|preview|compact|compact1|turned|collars]` and `--island|--desktop|--greeting|--bench-desktop --outfit <id>` draw and measure it without the app, and `render-cat-settings.sh --outfit <id>` draws the section.
- `tests/fixtures/shelf/`, `docs/SHELF-CONTRACT.md` — the shelf contract (sub-project G1-0): `zoneAt` (Ask or Shelf half), `shelfClean` (how `shelf.json` is read: ids, names, links, duplicates, the 30-item cap, newest first) and `shelfAdd` (a drop never evicts). `reference.py` (Python, standard library) decides when an app and a fixture disagree; `build_cases.py` writes the two JSON files; `scripts/test-shelf-contract.sh` runs them. No Swift, TypeScript or JS source holds these rules until the G1 app plans port them.
```

**Edit `ARCHITECT.md`**

Find:

```markdown
   - **Sub-project I (the wardrobe):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/wardrobe-cases.json` (new names only; the prototype's Wardrobe panel draws it, and `shared/theme.json` has the `outfits` colours): `OUTFIT_IDS` and `cleanWardrobeSettings`, Auto's calendar (`easterOf`, `autoOutfitFor`, `resolveOutfit`), who wears it (`outfitWorn(role)`: the big-cat role at every size, the compact notch included), where it sits (`outfitAnchors`, `outfitRoom`, the slots `OUTFIT_SLOTS` and `OUTFIT_ORDER`) and its shapes (`outfitGeometry`, checked by `outfitDigest`); see `docs/CAT-CONTRACT.md`, "The wardrobe (I-0)". The two app plans (I-mac, I-tauri) build on it.
```

Replace with:

```markdown
   - **Sub-project I (the wardrobe):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/wardrobe-cases.json` (new names only; the prototype's Wardrobe panel draws it, and `shared/theme.json` has the `outfits` colours): `OUTFIT_IDS` and `cleanWardrobeSettings`, Auto's calendar (`easterOf`, `autoOutfitFor`, `resolveOutfit`), who wears it (`outfitWorn(role)`: the big-cat role at every size, the compact notch included), where it sits (`outfitAnchors`, `outfitRoom`, the slots `OUTFIT_SLOTS` and `OUTFIT_ORDER`) and its shapes (`outfitGeometry`, checked by `outfitDigest`); see `docs/CAT-CONTRACT.md`, "The wardrobe (I-0)". The two app plans (I-mac, I-tauri) build on it. **On the Mac** it is built: `Wardrobe`, `WardrobeSettings` (`cat.outfit`) and `WardrobeAuto` hold the IDs, the clean-up and Auto; `WardrobeClock` resolves the stored choice for the date into `CatConfig.outfit` and keeps one wall-clock one-shot for the next midnight (only while the choice is `auto`); `CatOutfit` ports the anchors and shapes, `CatOutfitDraw` paints them at the renderer's three slots, and only the five big-cat views ask for an outfit (the role decides, never the diameter); Settings → Cat → Wardrobe, the island cat's right-click menu (new, Wardrobe only), the desktop cat's Wardrobe submenu and ⌃⌥G (`wardrobe`, off by default) all end in `CatSettingsStore.setOutfit`.
```

**Edit `README.md`**

Find:

```markdown
| H | A desktop cat: drag the big cat out of the notch and keep it on the desktop | built on macOS, Windows and Linux; real-build checks pending |
```

Replace with:

```markdown
| H | A desktop cat: drag the big cat out of the notch and keep it on the desktop | built on macOS, Windows and Linux; real-build checks pending |
| I | A wardrobe: 16 outfits for the big cats, or Auto, which follows the calendar | built on macOS (Windows and Linux in progress); real-build checks pending |
```

**Edit `docs/SPEC.md`**

Find:

```markdown

## 9. Sons
```

Replace with:

```markdown

### La garde-robe

On peut habiller les gros chats (sous-projet I ; le contrat : `docs/CAT-CONTRACT.md`, « The wardrobe (I-0) »). **16 vêtements** dessinés dans le code (fêtes : chapeau de fête, bonnet de Père Noël, chapeau de sorcière, oreilles de lapin, lunettes de soleil ; tous les jours : bonnet, nœud, écharpe, lunettes rondes, couronne ; extras de chat : grelot, bandana, pince poisson, fleur ; ceux des chats : pince crevette, pince fleur de pêcher), plus **None** et **Auto** : 18 choix, dans cet ordre, figés comme les identifiants de chats. Un seul vêtement à la fois ; il va à tous les chats en rôle « gros chat », **à toutes les tailles, le notch compact compris** (Ø 20, ou Ø 18 sans encoche) : le chat du notch (compact et ouvert), les deux chats du mode Two cats, le gros chat de chaque agent, le chat de bureau, et le chat qui attrape un fichier. Les chatons et les petits chats (pastilles, rangée du mini, grille) restent nus, **quel que soit leur diamètre** : c'est le rôle qui décide.

- **Auto** suit la date locale du calendrier nord, règles dans cet ordre : 31 déc. au 2 janv. chapeau de fête ; 1er au 26 déc. Père Noël ; 1er oct. au 1er nov. sorcière ; du vendredi saint au lundi de Pâques (Pâques par Meeus/Jones/Butcher, jours comptés sur des numéros de date) lapin ; 21 juin au 31 août lunettes de soleil ; sinon rien. Le choix stocké reste `auto` ; l'app le résout au lancement et au prochain minuit local avec **un seul minuteur** (`WardrobeClock`, sur l'horloge murale, donc un Mac qui dort à minuit le déclenche au réveil), qui n'existe que tant que le choix est `auto`. Rien ne tourne en boucle.
- **Choisir** : Réglages → Cat → Wardrobe (après Display et Desktop : un aperçu vivant du Main cat avec le vêtement sous le curseur, un sélecteur de pelage qui ne stocke rien, 18 tuiles en groupes ; la tuile Auto dit « Auto: today, Santa hat ») ; le **clic droit sur le chat du notch** (nouveau menu, avec seulement Wardrobe pour l'instant, sur les deux chats en Two cats) ; le sous-menu Wardrobe du menu du chat de bureau ; **⌃⌥G** (action `wardrobe`, **désactivée par défaut**, dans tous les builds), qui passe au suivant dans l'ordre de la grille, Auto et None compris, et revient à Auto après `blossomclip`.
- **Dessin** : trois emplacements, sans toucher `PASSES` : `behind` après les oreilles (oreilles de lapin), `neck` après le collier (écharpe, bandana, grelot), `top` après `neck` (chapeaux, lunettes, pinces, nœud, fleur), toujours avant les moustaches ; la pastille d'état et les particules restent devant. La forme vient des nombres du pelage (jamais d'une liste de pelages) ; les petites parties ont des planchers en pixels de l'écran ; en dessous de Ø 28 les détails fins (reflets, étoile, côtes) sont omis ; le bord fin du vêtement est clair sur un pelage sombre et sombre sur un pelage clair.
- **Stockage** : `cat.outfit` (texte), nettoyé par `WardrobeSettings.clean` (`cleanWardrobeSettings` : un des 18 identifiants tels qu'écrits, sinon `auto`). Coût : dans le dessin existant, aucun minuteur de plus que le minuteur d'Auto, 0 % de CPU île cachée. `scripts/render-cats.sh --wardrobe` dessine les planches.

## 9. Sons
```

**Edit `.github/workflows/build.yml`**

Find:

```yaml

      - name: "Cat press (Two cats: a press in cat 2's part of the overlap drags nothing)"
```

Replace with:

```yaml

      - name: Wardrobe settings (the 18 frozen IDs, the clean-up, the cycle, the menus' items)
        run: bash scripts/test-wardrobe-settings.sh

      - name: Wardrobe Auto (Easter, the dated rules, the clock and its one timer)
        run: bash scripts/test-wardrobe-auto.sh

      - name: Wardrobe geometry (anchors and the 16 outfits on the 16 coats)
        run: bash scripts/test-wardrobe-geometry.sh

      - name: Wardrobe drawing (only the big-cat role wears an outfit)
        run: bash scripts/test-wardrobe-draw.sh

      - name: Wardrobe wiring (source pins of the app files)
        run: bash scripts/test-wardrobe-wiring.sh

      - name: "Cat press (Two cats: a press in cat 2's part of the overlap drags nothing)"
```


- [ ] **Step 2: Run every test this plan added or changed**

```bash
for f in scripts/test-wardrobe-*.sh scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done
bash scripts/test-shortcuts.sh 2>&1 | tail -1; bash scripts/test-hotkeys.sh 2>&1 | tail -1; bash scripts/test-theme.sh 2>&1 | tail -1
bash scripts/check-no-leftovers.sh 2>&1 | tail -3
node scripts/check-fixtures-additive.mjs 5f9051c 2>&1 | tail -1
bash scripts/test-island-wing.sh 2>&1 | tail -1; bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1
```

Expected: thirty-nine lines for the first loop (five new scripts and the thirty-four cat scripts of Task 0): every one ends `All tests passed.` except `scripts/test-cat-contract.sh`, which ends `✓ two generator runs write identical bytes`; then `Shortcuts: 520 cases passed`, `HotKeyCenter: 19 cases passed` and `✓ 3 theme files match shared/theme.json`; the `check-no-leftovers.sh` lines all `✓`; `✓ fixtures changed only by addition since 5f9051c`; and two `All tests passed.` for the island wing (the island window controller's neighbours).

- [ ] **Step 3: Build the three builds and run the three binary checks**

```bash
cd NotchBuddy && xcodegen && cd ..
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -2
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -2
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -2
bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug 2>&1 | tail -4
bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app release 2>&1 | tail -5
bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore 2>&1 | tail -4
```

Expected: three `** BUILD SUCCEEDED **` and the three binary checks as in Task 13.

- [ ] **Step 4: Read the benches once more**

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench 2>&1 | tail -1; RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench-desktop 2>&1 | grep "idle, no kittens"`
Expected: the notch's own cost is Task 0's (within the machine's noise: the bare cat draws exactly as before and no cat has an outfit here) and the desktop lines are under 1 % of a core.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, and i/mac-wardrobe
git add CLAUDE.md ARCHITECT.md README.md docs/SPEC.md .github/workflows/build.yml
printf '%s\n' 'docs(wardrobe): the Mac lines, the roadmap row, "La garde-robe" and the CI steps (I-mac task 14)' '' 'Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>' > "${TMPDIR:-/tmp}/i-mac-msg" && git commit -F "${TMPDIR:-/tmp}/i-mac-msg"
```

### Task 15: The whole-branch review

No code. Dispatch **`nm-reviewer-deep`** (Sonnet 5.5, high; skills `ponytail:ponytail-review` and `superpowers:requesting-code-review`) over `git diff notchmeow/rebrand...HEAD` (three dots). Its brief carries the spec, the Global Constraints, the Review Focus and these questions, and nothing else of this plan:

1. **Cross-task contracts.** `CatConfig.outfit` is written only by `WardrobeClock`'s `onChange` and `attach`; `CatDrawOptions.outfit` is set only at the five big-cat sites; `store.setOutfit` is the one way a pick is stored; the tags 100 to 117 mean the same in both menus; the three slots are called in the order the contract gives.
2. **The role rule.** No path draws an outfit on a pill's cat, a kitten, the mini row or the grid, whatever the diameter; Settings' own previews and the Display preview are bare.
3. **Timers and polling.** Exactly one new timer exists (`asyncAfter(wallDeadline:)` in `WardrobeClock+App`), only while the choice is `auto`; nothing polls; a bare cat builds no geometry; the island's hidden state is as it was.
4. **The island panel.** The right-click monitor reads only the right button; the left-button monitors, the slap, the click and the drag-out are as they were; `wardrobeMenuOpen` cannot stay true (the `defer`); the menu is shown only for a right-click on a big cat inside the island's window.
5. **Privacy and security rules.** No network, no telemetry, no secret, no file written but `cat.outfit`; the Debug date override and the pretend midnight are compiled out of Release and App Store; nothing of the upstream wardrobe is read, ported or reused; `scripts/check-no-leftovers.sh` is green.
6. **The Review Focus**, each line against the test that pins it.

Fix what it finds (a fix round goes to the agent that wrote the task, then `nm-reviewer` over the fix), re-run Task 14's Steps 2 and 3, and stop for checkpoint 3.

### Task 16: Owner checkpoint 3: sign-off, then the owner's real-build checks

No code. Report to the main session (the ping rule) with the commits, the review's verdict, every test line and build line of Task 14, and the bench lines. The owner signs the branch off; the main session merges it only when the owner says so, and never pushes.

**The owner's real-build checks** (a Debug build, or the tester build; nothing of this was launched by the plan):

1. **Each outfit on the island.** Settings → Cat → Wardrobe: pick each of the 16 in turn; the notch's cat, compact and open, wears it at once. The compact cat reads at Ø20 and nothing is cut off at the top of the screen.
2. **The desktop cat at three sizes.** Take it out (⌃⌥D or the Settings switch), pick an outfit, then Small, Medium and Large from its menu: it is dressed at each size, and its kittens beside it are bare.
3. **Two cats mode and A cat for each agent.** Both cats are dressed in Two cats mode, each agent's big cat in per-agent mode, the pills' cats bare.
4. **Auto on a faked date.** Cats (Debug)… → Wardrobe → Pretend today is: 2026-12-24 (Santa hat), 2026-12-31 (party hat), 2026-10-31 (witch hat), 2027-03-26 (Good Friday: bunny ears), 2026-07-01 (sunglasses), 2026-05-05 (nothing). Settings' Auto tile says the same. Back to today.
5. **The midnight change.** Pretend 2026-12-26, then Midnight in 5 s: five seconds later the cat has taken off the Santa hat (the 27th has nothing to wear) with no restart.
6. **The right-click menus.** Right-click the notch cat (compact and open, and cat 2 in Two cats mode): a menu with only Wardrobe appears, the stored choice is ticked, a pick puts it on; the island does not fold while the menu is up; a click, a drag-out and a slap still work as before. Right-click the desktop cat: Open the notch, Send home, Size, Wardrobe (and the shortcut's line).
7. **⌃⌥G.** Off at first. Turn it on in Settings → Shortcuts; each press moves to the next outfit in the grid's order, None and Auto included, and wraps from the peach-blossom clip to Auto.
8. **The launch greeting.** Quit and relaunch: the cat is bare while it falls and waves and is dressed when it has settled.
9. **CPU.** With an outfit on, the island hidden: Activity Monitor shows nothing for NotchMeow beyond its usual idle; with the island open or the desktop cat out, nothing measurable more than without an outfit.

## Parity with Windows/Linux

I-tauri (a separate plan) builds the same contract in `windows/src/cat/` and Rust. The Mac gets at least what Windows and Linux get; where they differ:

- **Mac only:** ⌃⌥G (Windows and Linux have no global shortcuts), the Debug panel's date override and pretend midnight, and the wall-clock one-shot that survives a sleep through midnight (the Tauri twin picks its own timer).
- **Same:** the 18 IDs and their order, the clean-up, Auto's dates and Easter, who wears it (the role), the three slots, the floors and the fit, the colours (`shared/theme.json`), the Wardrobe section and the two menus. The shapes come from `cat-core.js` on both, and both replay `wardrobe-cases.json`, so a difference between the two apps is a bug of one of them.
- **Neither:** combining outfits, per-cat outfits, a southern-hemisphere Auto, holidays beyond the five rules, outfits on the site's live cats (spec, "Out of scope").

## Open questions for the owner

Each has a recommended answer, which the plan already uses; say if you want another.

1. **Settings' own previews** (the Main cat group, the Personality preview and the Display preview, which draw the Main cat or the cast): bare, as they ship **(recommended: the spec says never restyle what ships, and the Wardrobe group's own preview is where you see an outfit)**, or dressed.
2. **The launch greeting** (your answer: dressed once it settles): it fades on over a quarter of a second after the cat has slid back and waved (3.25 s into the greeting) **(recommended)**, or it appears the moment the cat lands, or only in the compact notch at the end.
3. **Right-click on cat 2 in Two cats mode:** the menu opens on both big cats, the nearer centre winning where the circles overlap **(recommended)**, or on cat 1 only (the slap and the drag-out stay cat 1's either way).
4. **The cat that catches a file** (the drop view's mouth catch): dressed, as it is the same big cat **(recommended)**, or bare for the length of the catch.
5. **Auto's timer** uses the wall clock, so a Mac that slept through midnight changes outfit on waking **(recommended)**, or the monotonic clock `CatSleep` uses (late by the length of the sleep).

## Self-review

- **Spec coverage.** Outfits, IDs and groups (Tasks 1, 3, 4); one at a time and global (Global Constraints, Task 5); Auto and its rules, Easter and the one-shot (Tasks 1 and 6); who wears it, every size, the compact notch (Tasks 3, 4, 5); the pickers: Settings (Task 7), the two menus (Task 11), ⌃⌥G (Task 12); storage `cat.outfit` and the clean-up (Tasks 1 and 2); the contract's slots, floors, fit, collar interplay, edge colour and digests (Tasks 3 and 4); performance and the bench (Task 9); the Debug date override (Task 13); the sheets, the checkpoints and the real-build checks (Tasks 4, 8, 10, 16); docs and CI (Task 14); the three builds' binary check (Tasks 7, 13, 14). Not here, by the spec: Windows and Linux, the site's cats, combining outfits.
- **Placeholders.** None: every code step is a full file or an exact find and replacement, and every command has its expected output.
- **Types.** `CatOutfit.Options`, `CatOutfitPaint`, `CatDressed`, `WardrobeMenu.Item` and `WardrobeClock`'s members are used with the names and signatures their tasks give (the dry run compiled all fourteen tasks in order).
- **Review Focus.** Each of the five lines has its pinning test named in the Review Focus section; the right-click menu's is a source pin plus the owner's real-build check, because no test program can run the island's panel.

## Dry run (2026-10-14)

Done in a throwaway clone of `619b407` under the session's scratchpad (`imac-dry/clone2`), by a script that applies the plan's **Create** and **Edit** blocks task by task (so the find texts are proved to occur exactly once, in the order given), then runs the task's commands; commits were not run. Everything below was run and was green:

- **Tasks 1 to 14 in order.** After each: its tests (`test-wardrobe-settings`, `-auto`, `-geometry`, `-draw`, `-wiring`, the store, greeting, desktop input, shortcuts and hot-key programs), the renderer's neighbours, and (Tasks 6, 7, 11, 12, 13, 14) `xcodegen` and a Debug build; Task 12 also the App Store target. The last run of Task 14's second step: 39 lines `All tests passed.` (five new scripts and 33 cat scripts) plus `test-cat-contract.sh`'s `✓ two generator runs write identical bytes`, `Shortcuts: 520 cases passed`, `HotKeyCenter: 19 cases passed`, `✓ 3 theme files match shared/theme.json`, `check-no-leftovers.sh` all `✓`, `✓ fixtures changed only by addition since 5f9051c`, and both island-wing programs `All tests passed.`
- **Three builds, three binary checks.** Debug, Release and App Store built; `check-app-binary.sh` printed `✓ The wardrobe is in this build` for all three, found `NM_CAT_DEV_WARDROBE` only in the Debug build, and the Release and App Store lines ended as Task 13 says.
- **Sheets, looked at.** `--wardrobe` `sheet`, `preview`, `compact`, `compact1`, `turned` and `collars`; `--island --outfit` (all three display modes), `--desktop --outfit`, `--greeting --outfit`; `render-cat-settings.sh` (the Wardrobe group, with the Auto tile reading today's result) and `render-cat-panel.sh` (the Debug Wardrobe section). Every outfit is on its coat, the compact Ø20 and Ø18 cats keep every outfit inside the strip, the head turned flattens the glasses, the bell hangs from each collar style and the scarf and bandana cover it, the small cats and the kittens are bare. `gen-icons.sh <outDir>` wrote the 18 icons byte for byte as the repo has them.
- **The bench**, optimised build: none 1.91 ms for the 12 small cats plus the big one (Task 0's 1.93 ms); Santa hat/witch hat 1.97 ms; shrimp clip 1.99 ms. The desktop cat idle and awake at Ø48, Ø64 and Ø96: 0.28, 0.38 and 0.64 % bare; 0.32, 0.41 and 0.68 % in the witch hat; 0.31, 0.42 and 0.69 % in the shrimp clip.

**Defects found by the dry run and fixed in this plan** (the first draft of the code had each):

1. `WardrobeSettings` needs `CatSettingsBacking`, which pulled `CatSettings.swift` into every renderer's compile list through `Wardrobe.drawn`. The IDs live in their own file, `Wardrobe.swift`, which the renderer lists compile alone.
2. The fixture holds a few inputs a Swift `Int` cannot take (a year of 2024.5, "2024", null); the tests check those as "cannot be asked" (`whole(_:)` in the test), as the contract answers them.
3. A first expectation of 23.5 hours for the day the clocks go forward was wrong: from 00:30 the next midnight is 22.5 hours away, 24.5 on the day they go back. The test says so.
4. `WardrobeClock` announced nothing at its first resolve (the first outfit is read from `resolved`); the test says that, and the fake timer marks fired timers so "one timer, not two" is a real check.
5. The first menu-open fix edited `let inIsland = …`, which `scripts/test-island-wing-wiring.sh` pins; it now holds back `fsm.mouseLeft()` and keeps `wasInIsland` true instead, so no shipped pin changed.
6. `render-cat-settings.sh`'s list named `Wardrobe.swift` twice (a duplicate source file); the edits name each file once.
7. The sheets' long column heads ("Peach-blossom clip") were cut off at the right edge, and the compact sheet's heads overlapped the strips; both fixed in `render-cats-wardrobe.swift`.
8. Two Swift expressions were too long for the type checker (a nested `allSatisfy`); the test slices the bitmap instead.

## The owner's answers (2026-10-14, from the spec)

1. The big cat is dressed at every size, the compact notch included; the role decides, `outfitWorn` takes the role.
2. The island cat's right-click menu is new, with only Wardrobe in it.
3. ⌃⌥G cycles through `auto`, `none` and the 16 outfits in the grid's order, and is off by default.
4. The two cats' own clips are open to every coat.
5. Models: I-mac on Sonnet 5.5 high (trigger 1); the greeting's cat is dressed once it settles.
6. A coat picker in Settings' preview that changes nothing stored.

## The owner's answers (2026-10-14)

The owner approved this plan with these answers:
- Settings' own big-cat previews (Main cat, Display mode) and the drop view's cat are **dressed**.
- The greeting's cat: the outfit **fades on after the cat settles** (about 3.25 s). Wardrobe is **its own section** under Cat in Settings.
- The right-click Wardrobe menu is on **both cats** in Two cats mode; a right-click opens the menu only (no tap or slap reaction).
- The desktop cat's hat **does not take clicks**: the click shape stays as today.
