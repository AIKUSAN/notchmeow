# I-tauri The Wardrobe Implementation Plan (Windows and Linux)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows/Linux Tauri app gets sub-project I: the user dresses the big cats. **Settings… → Wardrobe** and a right-click **Wardrobe** menu on the island cat and on the desktop cat pick one of 16 outfits, **None**, or **Auto** (the season, by the local date); every big cat wears it at every size, the compact notch's Ø20 cat included, and the small cats and the kittens stay bare. Auto looks again at the next local midnight with one one-shot timer that exists only while the choice is Auto. The choice is stored as the `outfit` key of the `cat` block. There is no global shortcut here (Windows and Linux have none).

**Architecture:** The rules and the shapes are the contract's (`design/prototype/cat-core.js`, "The wardrobe (I-0)", pinned by `tests/fixtures/cat/wardrobe-cases.json`): `cat/wardrobe.ts` ports the IDs, the clean-up, Auto and the roles, `cat/outfit.ts` ports the anchors and the shapes (head-local px with colour roles), and a small painter, `cat/outfitdraw.ts`, paints them at the contract's three slots from `cat/renderer.ts` when `DrawOptions.outfit` is set. `BotEngine.outfit` is set by exactly three views: the island's main cat, cat 2 in Two cats mode and the desktop cat (the greeting's settled cat is drawn by its own call). The stored value goes through `cleanCatBlock` and its Rust twin `clean_cat_block` like B's and H's keys; the island resolves it for today (`State.outfit`) with `island/wardrobe.ts`; Settings gets a card with a live preview; one shared builder (`core/wardrobemenu.ts`) makes the Wardrobe submenu of both right-click menus.

**Tech Stack:** TypeScript (Canvas 2D, erasable syntax for everything `npm run check:cat` loads), Rust (`serde_json`) for the settings twin, Tauri 2's native menu API, Node 22.6+ for the checks, `playwright-cli` for the headless pictures.

**Spec:** `docs/superpowers/specs/2026-10-14-wardrobe-design.md` (sub-project I; the Windows/Linux side of its "Rounds" step 2, in the order it lists). The contract is merged (I-0, `d050fc2`, with the bow fix `619b407`): `design/prototype/cat-core.js` ("The wardrobe" sections), `tests/fixtures/cat/wardrobe-cases.json` and `docs/CAT-CONTRACT.md` ("The wardrobe (I-0)"). The prototype's **Wardrobe panel** (`design/prototype/notchmeow.html`) is the look. The format and the conventions are the last Windows plans': `docs/superpowers/plans/2026-10-08-b-tauri-display-kittens.md` and `docs/superpowers/plans/2026-10-12-h-tauri-desktop-cat.md`. The Mac twin (I-mac) is drafted at the same time; "Parity with macOS" below says what differs. Read the Windows cat code first (`windows/src/cat/`, `windows/src/island/`, `windows/src/core/state.ts`, `windows/src/settings/cat.ts`, `windows/src/desktop/body.ts`, `windows/src-tauri/src/cat_settings.rs`, `settings.rs`) and `windows/README.md`. **Never read, copy or port upstream Coucou's wardrobe code or art: they are reserved.** Every outfit here is the contract's own drawing.

**Base:** branch `i/tauri-wardrobe`, in a git worktree, from `notchmeow/rebrand` **at `619b407` or later** (I-0 is merged: nothing of the I-0 plan is applied by this plan; the Setup block checks `git merge-base --is-ancestor d050fc2 HEAD`). Nothing is pushed.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and the contract; a line marked "(plan decision)" is a choice this plan makes where the spec is silent, and is listed again under "Open questions for the owner".

- **Frozen IDs.** The 18 selection IDs, in the order of the grid, the menus and the settings: `auto`, `none`, `partyhat`, `santahat`, `witchhat`, `bunnyears`, `sunglasses`, `beanie`, `bow`, `scarf`, `roundglasses`, `crown`, `bell`, `bandana`, `fishclip`, `flower`, `shrimpclip`, `blossomclip` (16 drawn). Lowercase letters only. A stored value that is not exactly one of them (a capital, padding, a number, an object, a made-up name) is `auto`. The default is `auto`. The action ID `wardrobe` is frozen too, and **does not exist here**: Windows and Linux have no global shortcuts, and the README says so. Cat IDs, collar style IDs, display mode IDs and the desktop size IDs are as before.
- **Who wears it (spec "Who wears it").** One choice dresses every cat in a **big-cat role**, at every size: the island's main cat (compact and open, in every display mode, so each agent's big cat in A cat for each agent mode too), cat 2 in Two cats mode, the desktop cat (Ø48, Ø64, Ø96), and the greeting's settled cat and its second cat. **Bare, always:** every kitten and every small cat (the pills' cats, the mini row, the grid), whatever their diameter. The role decides, never the diameter (`outfitWorn(role)`; the Ø28 switch `DETAIL_FULL_MIN` only changes how a cat is drawn). In this app the role is **where an engine is told its outfit**: only `Island.drawBot`, `Island.drawBot2` and `drawDesktopCat` set `BotEngine.outfit`; an engine that is never given one is bare. (Plan decisions: the Display preview in Settings and the drop view's travelling cat stay bare, so no existing picture changes; the Wardrobe card's own preview is dressed.)
- **Slots, floors, colours (contract).** Three slots, in the draw order `behind` (after the ears in the behind pass: bunny ears), then in the front pass `foldEars`, collar, `neck` (scarf, bandana, bell), `top` (hats, crown, glasses, clips, flower, bow), `whiskers`, badge, particles, balls. `PASSES` stays as A-0 wrote it. Floors `OUTFIT_MIN` in **device** pixels `{height: 6, line: 1, rim: 2, ball: 3, span: 6}`. The thin `edge` colour is light on a coat whose flat head colour has a luminance under 100 and dark otherwise (`outfitEdge`). A `fine` shape (a glint, a star, a rib, a bell's slot) is left out below Ø28. In the compact notch a hat is shortened to `outfitRoom` (the ears' ceiling less the 0.5 px margin) and held at the floor, never hidden. Colours are roles resolved through `THEME.outfits` (`shared/theme.json`, 38 colours): a coat is never recoloured. The bell hangs from the collar (the tag's lower edge, the middle of the band, the kerchief's apex, or its own ring at the chin's centre front with the collar off); the scarf and the bandana cover the collar; the collar is never changed.
- **Auto (spec "Auto rules").** The local calendar date on the northern calendar, first match wins: Dec 31 to Jan 2 `partyhat`; Dec 1 to Dec 26 `santahat`; Oct 1 to Nov 1 `witchhat`; Good Friday to Easter Monday `bunnyears`; Jun 21 to Aug 31 `sunglasses`; anything else (and a date that is not a date) `none`. Easter is the Gregorian Easter of the date's own year, counted on date numbers, never on clock times. Auto is a choice, not an outfit: the stored value stays `auto`; the island resolves it at launch and at the next local midnight with **one one-shot timer that exists only while the stored value is `auto`**; a timer that fires late recomputes from the date then; nothing polls. Settings shows today's result: the Auto tile is labelled "Auto: today, Santa hat" (or "Auto: today, none").
- **Storage (spec "Storage").** The `outfit` key of the `cat` block of `settings.json`, through `cleanWardrobeSettings` (a clean-up of its own: `settings-cases.json`, `display-cases.json` and `desktop-cases.json` stay byte for byte). **Every clean-up of the block, in TypeScript and in Rust, cleans all four parts** (`cleanCatBlock`, `clean_cat_block`), or a save from a part that does not carry `outfit` would drop it: `settings::sanitized` keeps it at every save. A fresh install is `auto`.
- **Pickers (spec "Pickers").** Settings → **Wardrobe**: a grid of 18 tiles in the ID order (Auto and None first, then Seasonal, Everyday, Cat extras, The cats' own with small headings), a live preview of the Main cat wearing the tile under the pointer, else the chosen one, and a coat picker that shows the same outfit on any of the 16 coats and **stores nothing** (not the Main cat, not the outfit); a click stores. The Wardrobe submenu (18 entries in groups, a tick on the current one) is in a **new right-click menu on the island's big cat (only Wardrobe in it for now)** and in the desktop cat's existing menu, beside Open the notch, Send home and Size. (Plan decision: in this app's single-page Settings, Wardrobe is its own card right under Cat.)
- **Cost (spec "Performance").** Outfits are part of the existing frame draw: no layer, no window, no timer, except Auto's one-shot. `none`, every small cat and every kitten cost nothing (the outfit is never computed for them). The desktop cat's frame-rate rule (`desktopFps`) is unchanged; an outfit adds no motion. **0 % CPU while the island is hidden** is unchanged.
- **Never restyle what ships.** The island, the pills, the cards and every existing Settings row look as they did. The Wardrobe card is built from the window's own `.cat-cell`, `.row`, `select` and `.hint`; the only new CSS is new class names (`.wardrobe-tiles`, `.wardrobe-grid`, `.wardrobe-cell`). The only change in the island is a cat wearing something, and the right-click menu on a big cat. **A right press on a big cat now opens that menu instead of acting as a click** (plan decision: it used to slap the cat); every left press, click and drag out of the notch is the code it was, pinned by Task 10's tests.
- **Tolerance and tie-breaker.** Numbers compare within **1e-9** against the fixture. **`cat-core.js` is the tie-breaker.** This plan never edits `design/prototype/cat-core.js`, `design/prototype/notchmeow.html`, `shared/theme.json`, `tests/fixtures/cat/`, `scripts/gen-cat-fixtures.mjs` or `docs/CAT-CONTRACT.md`: a change there is the main session's (a shape or a colour the owner wants changed at Checkpoint 1 is a contract change: stop and report it). The cat code never calls `Math.random()` and reads a clock only as the late-bound default of a constructor or a parameter.
- **Files loaded by `npm run check:cat`** (everything under `windows/src/cat/` except `dev.ts`, `devdesktop.ts` and `devwardrobe.ts`, plus `core/layout.ts`, `core/notchspot.ts`, `core/state.ts`, `island/sleep.ts`, `island/wardrobe.ts` and the others the earlier plans listed) use erasable TypeScript only (no `enum`, no `namespace`, no constructor parameter properties), `import type` for types, and relative imports **with the `.ts` extension**, because Node reads the source as it is. Files outside that set (`island/island.ts`, `island/desktop.ts`, `desktop/`, `settings/`, `core/wardrobemenu.ts`, `main.ts`, `core/bridge.ts`) keep the repo's extension-less imports.
- **No Coucou or Mochi names, no upstream wardrobe code, art, sound or key** anywhere (`mocha` is a coat, not a name to avoid); `names.test.mjs` keeps guarding `windows/`, and `scripts/check-no-leftovers.sh` keeps out `mochi`, a pumpkin and a top hat. **No telemetry, no network:** nothing here touches any.
- **No new dependency.** No `npm install` of anything, **no change to `Cargo.lock` or `Cargo.toml`**. Rust runs **only** through `windows/scripts/cargo-linux.sh` (Docker Desktop running), with this plan's own target directory, because other worktrees share that script's Docker volume: `windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/i-tauri`. Never install a toolchain on the host.
- **Commits:** local only, never pushed, via `git commit -F -` with the message on stdin. End every commit message with the line `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` for a task a Haiku agent ran, or `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` for a Sonnet one (Task 10, and any task handed to `nm-implementer-deep`): the table says which.
- **The model rule** (`CLAUDE.md`, "Working with AI agents", 2026-10-12): Haiku 5.5 first, Sonnet 5.5 only for a named trigger, never Opus or Fable. The session and its controller run on **Haiku 5.5 at high effort** (the owner's brief for this plan). **Task 10 uses `nm-implementer-deep` for trigger 1** (a native menu in the island's click-through, non-activating, auto-collapsing window; layer-shell on Linux); the whole branch goes to `nm-reviewer-deep` (trigger 4).
- **House rules for every session and every subagent brief (the SUBAGENT RULES block):**
  1. **Never launch, quit or replace any NotchMeow app, and never start the Tauri app** (`npm run tauri dev`, a built `notchmeow.exe`): the owner runs it. Serving the front end with `npx --no-install vite` and looking at it in the headless `playwright-cli` browser is allowed, and only that.
  2. **Install nothing and download nothing.** `npx --no-install` only; never `npm install`, `npm ci`, `npm run build`, `npm run dev` or `npm run tauri`. The site bundle is rebuilt with `npx --no-install vite build --config vite.site.config.ts` (Task 11), never `npm run build`.
  3. **Rust only through `windows/scripts/cargo-linux.sh`** with `--target-dir /repo/windows/target/i-tauri`. Check the image first: `docker image inspect notchmeow-linux-dev`. **Never build or pull the image** (the script would, if it is missing): if the image is missing or the daemon is down, **the step stops and the session reports it**; the TypeScript tasks go on, and the Rust steps are owed (Task 3 has them).
  4. **Use `trash`, never `rm -rf`.** Pictures and the one-off scripts go in `.claude/checkpoints/i-tauri/` (gitignored), never anywhere that git tracks. Stop the dev server **by its saved PID only** (`kill "$(cat .claude/checkpoints/i-tauri/vite.pid)"`), never `kill $(lsof ...)`; close every browser session **by its name** (`playwright-cli -s=<name> close`), never `close-all`. Run `playwright-cli` with the default `TMPDIR` (a long one breaks its socket path), from `.claude/checkpoints/i-tauri/` so that its own `.playwright-cli` folder lands in the gitignored place.
  5. **Never push.** Commit only in a task's commit step, with `git commit -F -`, after `git rev-parse --show-toplevel` and `git branch --show-current` have said that the session is in its worktree on `i/tauri-wardrobe`. Never edit `CLAUDE.md` or `ARCHITECT.md` except where Task 11 says so.
  6. **If a command is denied by a permission prompt, stop and report it.** Do not look for a workaround.
  7. Every shell block of this plan passes `bash -n`; a block that a brief edits must still pass it.

## Review Focus

The spec says what the wardrobe must do. It is silent on these inputs, and each would bite a person first. Each line names its test.

1. **A hand-edited or half-written `outfit`, and the next save.** `"Bow"`, `" bow"`, `7`, `["bow"]`, `{"outfit": "bow"}`, `null`, `"__proto__"`, a key missing; then a Cat settings row, the Display row or the desktop switch saves. Expected: the app starts, the rest of the block is kept, no `settings.json.bad-…` appears, `outfit` is `auto` (or the valid ID) and **is still there after the save** (a clean-up of the block from the Cat settings alone would drop it). Tests: Task 3 (`wardrobe-settings.test.mjs`; `display.test.mjs`'s key list; the Rust `the_wardrobe_clean_up_replays_the_fixture`, `the_whole_block_holds_the_outfit…`, `the_outfit_survives_a_save_a_load_and_a_round_trip…`).
2. **The clock: midnight, a day with a daylight-saving change, a long sleep, a timer left behind.** The new-year midnight, Good Friday arriving at midnight, a computer asleep for 20 days, a spring-forward day, choosing an explicit outfit while Auto's timer is armed, choosing Auto again, a bad clock. Expected: one timer while the choice is `auto` and none otherwise, the next day's outfit at the next local midnight by the calendar, a late timer recomputing from the date it finds, never two timers, never a poll. Tests: Task 6 (`wardrobe-clock.test.mjs`).
3. **Dressing the wrong cat.** A kitten beside the desktop cat, a pill's mini cat, the grid's cats, the Display preview in Settings, the drop view's travelling cat, the site's cats, an engine nobody dressed, `none` and `auto` (never drawn as `auto`). Expected: bare, drawing exactly what they drew before; the outfit is never computed for them. Tests: Task 4 (`outfit-draw.test.mjs`: "none, auto, no outfit and anything that is not an outfit draw exactly what a bare cat draws"), Task 7 (`wardrobe-wiring.test.mjs`: the source pins on every file that must not mention an outfit, and the desktop kittens).
4. **The compact notch.** Every outfit on every coat at Ø20 in the 32 pt strip and at Ø18 in the 24 pt strip: nothing above the strip, no stroke under its floor, hats shortened to the ears' room and not hidden, the bunny ears taller and wider below Ø28, the shrimp clip simple below Ø28. Expected: the contract's 512 digests, and every shape inside the strip. Tests: Task 2 (`outfit.test.mjs`: "in the compact notch every outfit…"), Task 4 ("the notch gives a hat its room"), Checkpoint 1's pictures.
5. **A right-click that was a click, or a menu where there is no cat.** A right press on the cat while the greeting or the drop view owns the island, while the island is hidden, on the empty spot of a cat that is out on the desktop, on cat 2 and on the overlap of the two cats; a left press, a click and a drag out of the notch next to all that. Expected: the menu opens only on a big cat the island is showing, a right press there is not also a slap, and every other press is the line it was. Tests: Task 10 (`wardrobe-island-menu.test.mjs`).

---

## File Structure

All paths are under `windows/` unless they say otherwise.

| Path | Responsibility |
|---|---|
| `src/cat/wardrobe.ts` | New. The contract's rules: `OUTFIT_IDS` (18), `OUTFIT_DRAWN` (16), `OUTFIT_NAMES`, `OUTFIT_GROUPS`, `outfitIdOf`, `cleanWardrobeSettings`, `easterOf`, `autoOutfitFor`, `resolveOutfit`, `OUTFIT_ROLES`, `outfitWorn`. |
| `src/cat/outfit.ts` | New. Where an outfit sits and what it is made of: `OUTFIT_SLOTS`, `OUTFIT_ORDER`, `OUTFIT_MIN`, `outfitEdge`, `outfitRoom`, `outfitAnchors`, `outfitGeometry` (16 outfits as `poly`, `curve` and `ellipse` shapes with colour roles), `outfitDigest`. |
| `src/cat/outfitdraw.ts` | New. `outfitColor` (a role through `THEME.outfits`), `outfitShapes` (the shapes for one frame, with the strip's room), `paintOutfit` (one slot into a 2D context in the head's frame). |
| `src/cat/renderer.ts`, `src/cat/engine.ts` | Changed. `DrawOptions.outfit` and `outfitCeiling`; `CatFrame` carries the shapes; the three slots (`behind` after the ears, `neck` and `top` after the collar); `BotEngine.outfit`. |
| `src/cat/display.ts`, `src-tauri/src/cat_settings.rs`, `src-tauri/src/settings.rs` | Changed. `outfit` in the block (`CatBlock`, `cleanCatBlock`, `withOutfit`); the Rust twin `clean_wardrobe_settings` and `OUTFIT_IDS`; `clean_cat_block` cleans all four parts; `sanitized` keeps it at every save. |
| `src/island/wardrobe.ts`, `src/core/state.ts`, `src/island/island.ts` | New and changed. `WardrobeClock` (Auto's one-shot), `State.outfit`, the island's two big cats dressed, the greeting started with the outfit, the island cat's right-click menu. |
| `src/cat/greeting.ts` | Changed. `greetingDressed`, `Greeting.start(cast, outfit)`: the settled cat and the pair's cat 2 are dressed. |
| `src/cat/desktopdraw.ts`, `desktoptrip.ts`, `src/island/desktop.ts`, `src/desktop/body.ts` | Changed. `DesktopLook.outfit`, `BodyLook.outfit` and `outfitChoice`, the `outfit` message, the Wardrobe submenu in the desktop cat's menu. |
| `src/core/wardrobemenu.ts`, `src/cat/menuhit.ts` | New. The shared Wardrobe items of a native menu (built once, ticked before each popup); where a right-click opens the island cat's menu (`wardrobeMenuHit`, pure). |
| `src/cat/wardrobeui.ts`, `src/settings/wardrobe.ts`, `src/settings/cat.ts`, `src/settings/main.ts`, `src/settings/settings.css` | New and changed. The Settings card: the tiles, Auto's label, the preview's outfit (pure); the card with its live preview and coat picker; the card is returned by `catSection` and placed after Cat; three new CSS classes. |
| `src/cat/devwardrobe.ts`, `src/cat/dev.ts`, `src/cat/devdesktop.ts` | New and changed. The `?dev` Wardrobe panel (16 by 16 sheet, Ø20 and Ø18 strips, head turned, neck outfits over each collar, desktop sizes, Two cats pair, Auto for any date); an Outfit row for the mock desktop and the greeting; the bench with the witch hat on. |
| `scripts/cat-tests/*.test.mjs` | New: `wardrobe`, `outfit`, `wardrobe-settings`, `outfit-draw`, `wardrobe-dev`, `wardrobe-clock`, `wardrobe-wiring`, `wardrobe-ui`, `wardrobe-desktop-menu`, `wardrobe-island-menu`. Changed: `display.test.mjs` (the block has ten keys), `desktop-look.test.mjs`, `desktop-island.test.mjs`, `sites.test.mjs` and `two-cats.test.mjs` (one pinned line each). |
| `../docs/assets/cats.js`, `README.md`, `../CLAUDE.md`, `../ARCHITECT.md` | Task 11. The site bundle is rebuilt (the renderer is in it); the docs. **`../.github/workflows/windows-tests.yml` needs no change:** it already runs on `windows/**` and `tests/fixtures/cat/**`. |

**Staged edits.** Most tasks edit files earlier tasks created or changed. Every edit below is a Python script whose `edit` helper asserts that the find text occurs exactly once; the text is what the tree has after the tasks before it. Run each script from the repository root, as it is. If a find text occurs zero or two times, **stop and report**: the tree is not what the plan expects.

## Tasks and agents

`CLAUDE.md`: Haiku 5.5 first, Sonnet 5.5 only on a named trigger. Tasks 1, 2, 6 and 11 give every line of their code: transcription, `nm-implementer-light` (Haiku 5.5, medium). Tasks 3, 4, 5, 7, 8 and 9 are multi-file with their code given, and some run a browser or Docker: `nm-implementer` (Haiku 5.5, high). **Task 10 is `nm-implementer-deep` (Sonnet 5.5, high), trigger 1:** a native context menu in the island's window, which is click-through, non-activating, collapses when the pointer leaves it and is a layer-shell surface on Linux, next to a press handler whose click and drag must not change. Each task is then reviewed by `nm-reviewer` (Haiku 5.5, high), and the whole branch by `nm-reviewer-deep` (Sonnet 5.5, high) after Checkpoint 3. If a step's expected output differs and the cause is not obvious (a Rust compile error, a layout that overlaps, a menu that does not open), hand that task to `nm-implementer-deep` (trigger 2); a task Haiku has failed twice goes there too. Task 9 is the same menu API in the desktop window, which H already uses: Haiku, unless it fails.

| # | Task | Agent | Model | Review |
|---|---|---|---|---|
| 1 | The wardrobe's rules in TypeScript (replays `wardrobe-cases.json`: IDs, clean-up, Easter, Auto, who wears it) | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 2 | The outfits' anchors and shapes in TypeScript (replays the anchors, the shapes and all 256 digests) | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 3 | The stored `outfit`: the block (TypeScript and Rust), kept at every save | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 4 | Drawing the outfits: the painter, the renderer's three slots, `BotEngine.outfit` | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 5 | The `?dev` Wardrobe panel: the contact sheet and the compact strips | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 1:** the 16 by 16 sheet, the Ø20 and Ø18 strips, the head turned and the collar strips, next to the prototype's | the executing session | | |
| 6 | Auto's one-shot and `State.outfit` | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| 7 | Who wears it: the island's two big cats, the desktop cat, the greeting; the bench with an outfit on | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 8 | Settings → Wardrobe: the card, the live preview, the coat picker | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 2:** the Settings card, Two cats and per-agent mode dressed, the desktop cat dressed at three sizes, the greeting, the bench numbers | the executing session | | |
| 9 | The desktop cat's right-click Wardrobe submenu | `nm-implementer` | Haiku 5.5 | `nm-reviewer` |
| 10 | The island cat's right-click menu | `nm-implementer-deep` (trigger 1) | Sonnet 5.5 | `nm-reviewer` |
| 11 | Docs, the site bundle and the final checks | `nm-implementer-light` | Haiku 5.5 | `nm-reviewer` |
| | **Checkpoint 3:** the owner signs off; the real-build checklists | the executing session | | |
| Final | Whole-branch review | `nm-reviewer-deep` (trigger 4) | Sonnet 5.5 | none |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; `nm-implementer-deep` also `superpowers:systematic-debugging`. Reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Ponytail never cuts what this plan or the spec asks for, nor tests, security or privacy rules. The agents of Tasks 5, 7 and 8 also load `playwright-cli`.

## Execution

**One worktree chat session** runs the whole plan: branch `i/tauri-wardrobe`, model **Haiku 5.5 at high effort** (the owner's brief: the plan gives the code in full; Sonnet only for the named trigger of Task 10), in parallel with the Mac twin, which has its own worktree. It runs on a base where **I-0 is merged** (`619b407` on `notchmeow/rebrand`, or any later commit). Nothing is pushed. The session never starts the Tauri app: the owner's real-build checks are listed at the end.

**The session is started in three steps** (`ARCHITECT.md`), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run the Setup block of `docs/superpowers/plans/2026-10-14-i-tauri-wardrobe.md`. If any check in it fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, that plan and `docs/superpowers/specs/2026-10-14-wardrobe-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief below as the next message.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

**Controller brief** (what the main session sends the worktree session once its model is set):

> Run `docs/superpowers/plans/2026-10-14-i-tauri-wardrobe.md` with `superpowers:subagent-driven-development`, task by task, on branch `i/tauri-wardrobe`. Do its Setup first. You are the controller: Haiku 5.5 at high effort. Dispatch each task to the agent and model the plan's "Tasks and agents" table names (`nm-implementer-light`, `nm-implementer`; **`nm-implementer-deep` only for Task 10, trigger 1, or on a named trigger**: an unknown failure or a task Haiku failed twice), then to `nm-reviewer`; fix what the review finds before the next task. After Task 11 and the owner's sign-off, `nm-reviewer-deep` reads the whole branch. These rules hold for you and for every brief you write:
>
> 1. **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this session's worktree and the second `i/tauri-wardrobe`. If either differs, stop and report. Commit with `git commit -F -`, the message on stdin, ending with the `Co-Authored-By` line of the model that did the task. **Never push.**
> 2. **The ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-i-tauri-wardrobe/progress.md` (the SDD plugin's scripts are refused by auto mode): one line per task with its status, its commit, the test counts it printed, the model and agent that ran it, the trigger if it was `nm-implementer-deep`, and what the review found and how it was fixed. Write it after every step that changes a status.
> 3. **Briefs are task-sized.** A subagent gets one task: its text from the plan, the Global Constraints, the SUBAGENT RULES block, the files to read and the exact commands. Never hand it the whole plan.
> 4. **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots) restricted to the task's files, never two-dot, and the task's own text.
> 5. **Stop if a find text fails.** Every edit script asserts that its find text occurs exactly once. If one fails, **stop and report which task, file and text**: do not edit around it, and do not let a subagent "fix" the script.
> 6. **Shell.** Every shell block you write or edit passes `bash -n` first. Stop the dev server by its saved PID only (`kill "$(cat .claude/checkpoints/i-tauri/vite.pid)"`), never `kill $(lsof ...)`. Close `playwright-cli` browsers by session name (`-s=<name> close`), never `close-all`. Run `playwright-cli` with the default `TMPDIR`, from `.claude/checkpoints/i-tauri/`.
> 7. **Never** launch, quit or replace a NotchMeow app or start the Tauri app; install, download or build a Docker image (if `docker image inspect notchmeow-linux-dev` fails or the daemon is down, say so: the Rust steps of Task 3 are owed, and the TypeScript tasks go on); use the network; or use `rm -rf` (use `trash`). Rust only through `windows/scripts/cargo-linux.sh` with `--target-dir /repo/windows/target/i-tauri`.
> 8. **Refusals.** If any command is refused by a permission prompt, stop and report it. Do not look for another way.
> 9. **Pings.** Send the main session a `SendMessage` addressed to its ListAgents name `NotchMeow — fork research & cat design` at each checkpoint, at the end, and **whenever you stop** (a failed find text, a refusal, a missing image, a failed review): say where you are, what ran, the test counts and what you need.
> 10. **Checkpoints.** Run Tasks 1 to 5, then stop for **Checkpoint 1**: copy the pictures into `.claude/checkpoints/i-tauri/` (the sheet, the strips, the turned heads and the collar strips, and the prototype's same panels), send the owner their paths and the list under the checkpoint, and wait. After the owner's reply run Tasks 6 to 8 and stop for **Checkpoint 2** (the Settings card, Two cats and per-agent mode dressed, the desktop cat dressed, the dressed greeting, the bench numbers). After the owner's reply run Tasks 9 to 11 and stop for **Checkpoint 3**; after the owner's OK dispatch `nm-reviewer-deep` over the whole branch. Never start the next stage before the owner's reply.
> 11. **Report:** the commits; for `windows/`: `npx --no-install tsc --noEmit`, `npm run check:cat`, `npm run check:ai`, `npm run check:claude` and the `cargo test --workspace` counts (or that the image was missing); the output of `bash scripts/test-cat-contract.sh`, `bash scripts/check-site.sh`, `bash scripts/test-theme.sh`, `node scripts/check-fixtures-additive.mjs 5f9051c` and `bash scripts/check-no-leftovers.sh`; the bench numbers of Task 7; the pictures of the three checkpoints; the Windows `cargo check` and a release build (owed to CI); and anything you could not settle.

## Setup (the controller, once)

- [ ] Put the session's worktree on the plan's branch, check that I-0 is merged (`d050fc2` is an ancestor of `HEAD`), check that the base has what the plan reads (the fixture and the contract's numbers that Tasks 1 and 2 copy), and copy the main checkout's front-end packages. This plan adds no package, so nothing is downloaded: no `npm install` or `npm ci`. `cp -c` makes an APFS clone, which is instant and takes no extra disk space. It must be a real folder, not a symlink, because `.gitignore` ignores `/windows/node_modules` as a folder.

```bash
git status                                   # must be clean
git switch -c i/tauri-wardrobe notchmeow/rebrand
git merge-base --is-ancestor d050fc2 HEAD && echo "I-0 is merged (d050fc2)"   # if this prints nothing, stop
git log --oneline -3
git ls-files tests/fixtures/cat/wardrobe-cases.json docs/CAT-CONTRACT.md docs/superpowers/specs/2026-10-14-wardrobe-design.md docs/superpowers/plans/2026-10-14-i-tauri-wardrobe.md
git rev-parse --show-toplevel; git branch --show-current
cp -cR "/path/to/notchmeow/windows/node_modules" windows/node_modules
git status --short                           # still empty: the copy is ignored
mkdir -p .claude/checkpoints/i-tauri .superpowers/sdd/2026-10-14-i-tauri-wardrobe
cd windows && node --version                 # 22.6 or newer
```

`I-0 is merged (d050fc2)` must print, and so must the four paths (if the fixture is missing I-0 is not merged: stop; if the plan's own path prints nothing, the plan is not committed on this branch: stop).

- [ ] Check that the contract is the one this plan was written against: the IDs, the floors, the slots, the roles and the ear fit's margin that Tasks 1 and 2 copy must be the core's, and a later change to any of them must be copied into those tasks first.

```bash
node -e '
const core = require("./design/prototype/cat-core.js"), assert = require("node:assert/strict");
const json = (v) => JSON.parse(JSON.stringify(v));
assert.deepEqual(core.OUTFIT_IDS, ["auto", "none", "partyhat", "santahat", "witchhat", "bunnyears", "sunglasses", "beanie", "bow", "scarf", "roundglasses", "crown", "bell", "bandana", "fishclip", "flower", "shrimpclip", "blossomclip"]);
assert.deepEqual(json(core.OUTFIT_MIN), { height: 6, line: 1, rim: 2, ball: 3, span: 6 });
assert.deepEqual(core.OUTFIT_SLOTS, ["behind", "neck", "top"]);
assert.deepEqual(core.OUTFIT_ROLES, ["big", "small", "kitten"]);
assert.equal(core.DEFAULT_OUTFIT, "auto");
assert.equal(core.EAR_FIT.margin, 0.5);
assert.equal(core.DETAIL_FULL_MIN, 28);
assert.equal(typeof core.outfitGeometry, "function");
assert.deepEqual(json(core.cleanWardrobeSettings({ outfit: "bow" })), { outfit: "bow" });
assert.equal(core.autoOutfitFor(2025, 12, 24), "santahat");
console.log("the contract is the one this plan was written against");
'
```

Expected: `the contract is the one this plan was written against`. If an assertion fails, stop and tell the main session which value differs.

- [ ] Check that the starting point is green.

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1
(cd .. && bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two generator")
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && echo "image ok" || echo "image missing or the daemon is down: the Rust steps are owed"
```

Expected: `tsc exit 0` with no type error before it, `ℹ tests 372`, `ℹ pass 372`, `ℹ fail 0`, `All AI UI checks passed`, `All Claude Code UI checks passed`, `# tests 319`, `# pass 319`, `# fail 0`, `✓ 16 fixture files match cat-core.js`, `✓ two generator runs write identical bytes` and `image ok`. If `image ok` does not print, **do not build the image**: do the TypeScript tasks only and report that the Rust steps (Task 3's `cargo-linux.sh` runs) are owed. Their code is complete either way, and CI's `windows-tests.yml` runs `cargo test`.

## How to run this plan

**Blocks.** A code step is a `bash` block: either a file written with `cat > path <<'EOF'` (the file's exact content, from the repository root), or a Python script whose `edit` helper replaces text that must occur exactly once in the file it names, or a plain command. Run each block from the repository root, as it is. Never type a block from memory and never "improve" one. A `Run:` block's `Expected:` line says what it prints (every backticked literal must appear). A `Run:` block that starts with `cd windows` ends in `cd ..` and came back. URLs with a `?` are quoted, because the shell would read the `?` as a wildcard.

**Red first.** Each task writes its tests, runs them to see them fail, writes the code, and runs them to see them pass. A "prove it bites" step changes one line with the given script, runs the tests, and puts the line back (the script restores the file itself): it is never committed.

**Pixels.** There are no pixel tests. The look is checked by eye in a headless browser (`playwright-cli`, with Vite alone, never the Tauri app) and the cost by the `?dev` page's own bench. Keep every picture in `.claude/checkpoints/i-tauri/`, and say what you saw. **What no test program and no headless browser can show** is what the owner's real-build checks at the end are for (a native menu, the window itself, click-through, layer-shell, the midnight change); never claim them.

**The owner's checkpoints** are marked `Checkpoint N`: the session stops there, sends the owner the pictures and the list, and waits. Never start the next stage before the owner's OK.

**Starting and stopping the dev server** (Tasks 5, 7 and 8 use it; port 14613 so that it never meets another worktree's):

```bash
mkdir -p .claude/checkpoints/i-tauri
cd windows
(npx --no-install vite --port 14613 --strictPort > ../.claude/checkpoints/i-tauri/vite.log 2>&1 & echo $! > ../.claude/checkpoints/i-tauri/vite.pid)
sleep 3
cd ..
tail -3 .claude/checkpoints/i-tauri/vite.log
```

Expected: `VITE v6` and `http://127.0.0.1:14613/`. When a task is done with it: `kill "$(cat .claude/checkpoints/i-tauri/vite.pid)"` (nothing else) and, for each session it opened, `playwright-cli -s=<name> close`.

---

**The "prove it bites" helper** (written once, here; every proof step below calls it). It changes one line, runs the given test files, prints the pass and fail counts and puts the file back; it refuses a change whose find text does not occur exactly once.

```bash
mkdir -p .claude/checkpoints/i-tauri
cat > .claude/checkpoints/i-tauri/mut.py <<'EOF'
import sys, subprocess, shutil, os
# usage, from windows/: python3 ../.claude/checkpoints/i-tauri/mut.py <file> <find> <replace> <test files...>
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

# Stage 1: the rules and the stored value

### Task 1: The wardrobe's rules in TypeScript

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `windows/src/cat/wardrobe.ts`
- Test: `windows/scripts/cat-tests/wardrobe.test.mjs`

**Interfaces:**
- Consumes: nothing from earlier tasks; the contract's `wardrobe-cases.json`.
- Produces (everything later tasks import, from `windows/src/cat/wardrobe.ts`): `OUTFIT_IDS` (the 18 IDs, a `const` tuple), `OutfitId`, `DrawnOutfit`, `OUTFIT_DRAWN: readonly OutfitId[]` (the last 16), `DEFAULT_OUTFIT: OutfitId` (`"auto"`), `OUTFIT_NAMES: Readonly<Record<OutfitId, string>>`, `OUTFIT_GROUPS: readonly { id: string; name: string; ids: readonly OutfitId[] }[]`, `outfitIdOf(v: unknown): OutfitId`, `cleanWardrobeSettings(raw: unknown): { outfit: OutfitId }`, `easterOf(year: unknown): { month: number; day: number } | null`, `autoOutfitFor(y: unknown, m: unknown, d: unknown): OutfitId`, `resolveOutfit(id: unknown, y: unknown, m: unknown, d: unknown): OutfitId` (never `auto`), `OUTFIT_ROLES`, `OutfitRole`, `outfitWorn(role: unknown): boolean` (true for `"big"` only).

- [ ] **Step 1: Write the test**

```bash
cat > windows/scripts/cat-tests/wardrobe.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_OUTFIT, OUTFIT_DRAWN, OUTFIT_GROUPS, OUTFIT_IDS, OUTFIT_NAMES, OUTFIT_ROLES, autoOutfitFor, cleanWardrobeSettings, easterOf, outfitIdOf, outfitWorn, resolveOutfit,
} from "../../src/cat/wardrobe.ts";
import { load, same } from "./util.mjs";

// The wardrobe's rules, replayed from tests/fixtures/cat/wardrobe-cases.json (I-0), and the facts the contract's own tests check.
const fx = load("wardrobe-cases.json");

test("the frozen values are the fixture's: 18 IDs in the grid's order, 16 of them drawn, five rows, the names and the roles", () => {
  assert.deepEqual([...OUTFIT_IDS], fx.ids);
  assert.deepEqual([...OUTFIT_DRAWN], fx.drawn);
  assert.deepEqual(OUTFIT_IDS.slice(2), OUTFIT_DRAWN);
  assert.deepEqual(OUTFIT_GROUPS, fx.groups);
  assert.deepEqual(OUTFIT_GROUPS.flatMap((g) => g.ids), [...OUTFIT_IDS], "the groups hold every ID once, in the order of the IDs");
  assert.deepEqual(OUTFIT_NAMES, fx.names);
  assert.deepEqual(Object.keys(OUTFIT_NAMES), [...OUTFIT_IDS]);
  assert.equal(DEFAULT_OUTFIT, fx.defaultOutfit);
  assert.deepEqual([...OUTFIT_ROLES], fx.roles);
  assert.ok(OUTFIT_IDS.every((id) => /^[a-z]+$/.test(id)), "lowercase letters only");
});

test("a stored outfit: one of the 18 exactly as written, anything else is auto (the fixture's cases)", () => {
  assert.ok(fx.clean.length >= 38);
  for (const c of fx.clean) assert.equal(outfitIdOf(c.input), c.out, c.name);
  for (const c of fx.settings) same(cleanWardrobeSettings(c.input), c.out, c.name);
  assert.deepEqual(cleanWardrobeSettings({ character: "momo", outfit: "crown", desktop: { on: true } }), { outfit: "crown" }, "only its own key is read");
  for (const v of [undefined, () => "bow", NaN, Symbol.iterator.description]) assert.equal(outfitIdOf(v), "auto", String(v));
});

test("Easter and Auto: every row of the fixture, the windows walked with the calendar, and the dates that are not dates", () => {
  for (const c of fx.easter) assert.deepEqual(easterOf(c.year), c.out, String(c.year));
  for (const c of fx.auto) assert.equal(autoOutfitFor(c.y, c.m, c.d), c.out, `${c.y}-${c.m}-${c.d}`);
  for (const w of fx.easterWindows) {
    assert.deepEqual(easterOf(w.year), w.easter, String(w.year));
    for (const d of w.days) assert.equal(autoOutfitFor(d.y, d.m, d.d), d.out, `${w.year} Easter ${d.k}`);
  }
  for (const c of fx.resolve) assert.equal(resolveOutfit(c.id, c.y, c.m, c.d), c.out, `${c.id} ${c.y}-${c.m}-${c.d}`);
  for (const id of OUTFIT_IDS) assert.notEqual(resolveOutfit(id, 2025, 7, 1), "auto", "resolved is never auto");
  assert.equal(autoOutfitFor(2024, 1, 1.5), "none");
  assert.equal(autoOutfitFor(undefined, undefined, undefined), "none");
});

test("who wears it: the big-cat role only, the fixture's rows", () => {
  for (const c of fx.worn) assert.equal(outfitWorn(c.role), c.out, JSON.stringify(c.role));
  assert.equal(outfitWorn("big"), true);
  for (const role of ["small", "kitten", "Big", 28, null, undefined]) assert.equal(outfitWorn(role), false, String(role));
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe.test.mjs 2>&1 | grep -E "^# (pass|fail)|ERR_MODULE_NOT_FOUND" | sort -u
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND` and `# fail 1` (the module does not exist yet).

- [ ] **Step 3: Write the code**

```bash
cat > windows/src/cat/wardrobe.ts <<'EOF'
// The wardrobe's rules (sub-project I): the 18 selection IDs and their clean-up, Auto's calendar, and who wears an outfit. A port of the first half of "The wardrobe (sub-project I)"
// in design/prototype/cat-core.js, the tie-breaker (fixture tests/fixtures/cat/wardrobe-cases.json; docs/CAT-CONTRACT.md "The wardrobe (I-0)"). Pure: numbers and strings in, strings out,
// no clock and no canvas, so the plain-Node checks (npm run check:cat) can load it. The shapes an outfit is made of are in outfit.ts; the Auto timer is island/wardrobe.ts.

/** The 18 selection IDs in the order of the grid, the menus and the settings: frozen contract values, because they are stored. */
export const OUTFIT_IDS = [
  "auto", "none", "partyhat", "santahat", "witchhat", "bunnyears", "sunglasses", "beanie", "bow", "scarf", "roundglasses", "crown", "bell", "bandana", "fishclip", "flower", "shrimpclip", "blossomclip",
] as const;
export type OutfitId = (typeof OUTFIT_IDS)[number];
/** The 16 outfits that are drawn: everything but the two choices. */
export const OUTFIT_DRAWN: readonly OutfitId[] = OUTFIT_IDS.slice(2);
export type DrawnOutfit = Exclude<OutfitId, "auto" | "none">;
export const DEFAULT_OUTFIT: OutfitId = "auto";

/** The names the UI shows, by ID. */
export const OUTFIT_NAMES: Readonly<Record<OutfitId, string>> = {
  auto: "Auto", none: "None", partyhat: "Party hat", santahat: "Santa hat", witchhat: "Witch hat", bunnyears: "Bunny ears", sunglasses: "Sunglasses", beanie: "Beanie", bow: "Bow",
  scarf: "Scarf", roundglasses: "Round glasses", crown: "Crown", bell: "Bell", bandana: "Bandana", fishclip: "Fish clip", flower: "Flower", shrimpclip: "Shrimp clip", blossomclip: "Peach-blossom clip",
};

/** The grid's rows: the two choices, then the four groups with their headings. */
export const OUTFIT_GROUPS: readonly { id: string; name: string; ids: readonly OutfitId[] }[] = [
  { id: "choice", name: "", ids: ["auto", "none"] },
  { id: "seasonal", name: "Seasonal", ids: ["partyhat", "santahat", "witchhat", "bunnyears", "sunglasses"] },
  { id: "everyday", name: "Everyday", ids: ["beanie", "bow", "scarf", "roundglasses", "crown"] },
  { id: "extras", name: "Cat extras", ids: ["bell", "bandana", "fishclip", "flower"] },
  { id: "own", name: "The cats' own", ids: ["shrimpclip", "blossomclip"] },
];

const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/** A stored outfit to an ID: exactly one of the 18, as written (lowercase, no trimming); anything else, or no string at all, is `auto`. */
export const outfitIdOf = (v: unknown): OutfitId => (typeof v === "string" && (OUTFIT_IDS as readonly string[]).includes(v) ? (v as OutfitId) : DEFAULT_OUTFIT);

/** What Settings stores for the wardrobe, cleaned: `{outfit}`. `raw` is the stored `cat` block as plain JSON; it reads only `outfit`. Never throws. */
export const cleanWardrobeSettings = (raw: unknown): { outfit: OutfitId } => ({ outfit: outfitIdOf(isPlain(raw) ? raw.outfit : undefined) });

/** Gregorian Easter Sunday of a year from 1583 to 9999 as {month, day} (the Meeus/Jones/Butcher computation); null for any other year. */
export function easterOf(year: unknown): { month: number; day: number } | null {
  if (typeof year !== "number" || !Number.isInteger(year) || year < 1583 || year > 9999) return null;
  const a = year % 19, b = Math.floor(year / 100), c = year % 100, d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451), n = h + l - 7 * m + 114;
  return { month: Math.floor(n / 31), day: (n % 31) + 1 };
}

/** Days since 1970-01-01 of a calendar date, from the date numbers alone (no clock, no time zone), so a difference of two dates can never be shifted by daylight saving. */
const owDays = (y: number, m: number, d: number): number => {
  const yy = m <= 2 ? y - 1 : y, era = Math.floor(yy / 400), yoe = yy - era * 400, doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
  return era * 146097 + (yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy) - 719468;
};
const owValid = (y: unknown, m: unknown, d: unknown): boolean =>
  typeof y === "number" && typeof m === "number" && typeof d === "number" && Number.isInteger(y) && Number.isInteger(m) && Number.isInteger(d) && y >= 1 && y <= 9999 && m >= 1 && m <= 12 && d >= 1 &&
  d <= [31, y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];

/**
 * What Auto wears on a local date (year, month, day as numbers; the northern calendar, the same for everyone). The first rule that matches wins, and the order is the contract:
 *   1 Dec 31 to Jan 2 partyhat   2 Dec 1 to Dec 26 santahat   3 Oct 1 to Nov 1 witchhat   4 Good Friday to Easter Monday (Easter -2 to +1) bunnyears   5 Jun 21 to Aug 31 sunglasses
 * Anything else, and a date that is not a real date, is `none`.
 */
export function autoOutfitFor(y: unknown, m: unknown, d: unknown): OutfitId {
  if (!owValid(y, m, d)) return "none";
  const Y = y as number, M = m as number, Dd = d as number;
  if ((M === 12 && Dd === 31) || (M === 1 && Dd <= 2)) return "partyhat";
  if (M === 12 && Dd <= 26) return "santahat";
  if (M === 10 || (M === 11 && Dd === 1)) return "witchhat";
  const E = easterOf(Y);
  if (E) {
    const k = owDays(Y, M, Dd) - owDays(Y, E.month, E.day);
    if (k >= -2 && k <= 1) return "bunnyears";
  }
  if ((M === 6 && Dd >= 21) || M === 7 || M === 8) return "sunglasses";
  return "none";
}

/** The outfit to draw: the stored choice cleaned, with `auto` replaced by what autoOutfitFor says for the date (`none` when nothing is worn). Never `auto`. */
export const resolveOutfit = (id: unknown, y: unknown, m: unknown, d: unknown): OutfitId => {
  const o = outfitIdOf(id);
  return o === "auto" ? autoOutfitFor(y, m, d) : o;
};

/** The roles a drawn cat can have. The views map to them: the island's big cats and the desktop cat are `big`, the pills', the mini row's and the grid's cats `small`, the kittens `kitten`. */
export const OUTFIT_ROLES = ["big", "small", "kitten"] as const;
export type OutfitRole = (typeof OUTFIT_ROLES)[number];
/** Who wears the outfit: the big-cat role, at every size (the compact notch's Ø20 cat included). Anything else, and anything that is not a role, is bare. */
export const outfitWorn = (role: unknown): boolean => role === "big";
EOF
```

- [ ] **Step 4: Run it to see it pass**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe.test.mjs 2>&1 | grep -E "^# (pass|fail)"
cd ..
```

Expected: `# pass 4` and `# fail 0`.

- [ ] **Step 5: Prove it bites**

Run (Easter minus 2 days is Good Friday; moving the window one day makes Good Friday plain):

```bash
cd windows
python3 ../.claude/checkpoints/i-tauri/mut.py src/cat/wardrobe.ts "k >= -2 && k <= 1" "k >= -1 && k <= 1" scripts/cat-tests/wardrobe.test.mjs
cd ..
```

Expected: `wardrobe.ts | k >= -1 && k <= 1 | # pass 3 # fail 1`.

- [ ] **Step 6: Type check and the whole suite**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `tsc exit 0` with no type error before it, `ℹ tests 376`, `ℹ pass 376` and `ℹ fail 0`.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/cat/wardrobe.ts windows/scripts/cat-tests/wardrobe.test.mjs
git commit -F - <<'MSG'
feat(wardrobe): the wardrobe's rules in TypeScript

The 18 selection IDs and their clean-up, Easter and Auto's calendar, resolveOutfit and who wears an outfit, ported from cat-core.js and replayed from wardrobe-cases.json.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

### Task 2: The outfits' anchors and shapes in TypeScript

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `windows/src/cat/outfit.ts`
- Test: `windows/scripts/cat-tests/outfit.test.mjs`

**Interfaces:**
- Consumes: `wardrobe.ts` (`OUTFIT_DRAWN`); `geometry.ts` (`layout`, `supPoints`, `earScale`, `mixHex`, `FLAT_FILL`, `EAR_FIT`, `DETAIL_FULL_MIN`); `collar.ts` (`collarGeometry`, `COLLAR_MIN`); `base.ts` (`TAU`, `clamp`).
- Produces (from `windows/src/cat/outfit.ts`): `OUTFIT_SLOTS`, `OutfitSlot`, `OUTFIT_ORDER`, `OUTFIT_MIN`, `outfitEdge(p: CatPreset): "light" | "dark"`, `outfitRoom(a: { top: { y: number } }, headY: unknown, ceiling: unknown): number | null`, `OutfitOptions` (`dpr`, `detail`, `earScale`, `collar`, `room`), `outfitAnchors(p, s, D, o?): OutfitAnchors`, `PolyShape`, `CurveShape`, `EllipseShape`, `OutfitShape`, `outfitGeometry(id: unknown, p: CatPreset, s: Pose, D: number, o?: OutfitOptions): OutfitShape[]` (head-local px; `[]` for anything that is not one of the 16), `outfitDigest(shapes): { n, pts, bbox, mx, my }`.

- [ ] **Step 1: Write the test**

```bash
cat > windows/scripts/cat-tests/outfit.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { newPose } from "../../src/cat/geometry.ts";
import { collarGeometry } from "../../src/cat/collar.ts";
import { OUTFIT_MIN, OUTFIT_ORDER, OUTFIT_SLOTS, outfitAnchors, outfitDigest, outfitEdge, outfitGeometry, outfitRoom } from "../../src/cat/outfit.ts";
import { OUTFIT_DRAWN } from "../../src/cat/wardrobe.ts";
import { CAT_IDS, PRESETS } from "../../src/cat/presets.ts";
import { PASSES } from "../../src/cat/geometry.ts";
import { finite, load, same } from "./util.mjs";

// The outfits' anchors and shapes, replayed from tests/fixtures/cat/wardrobe-cases.json (I-0).
const fx = load("wardrobe-cases.json");
const POSES = { rest: newPose(), turned: { ...newPose(), yaw: 0.6, pitch: 0.15 } };
/** The options a renderer would pass: the notch's strips give the compact cat its room above the crown (32 pt for the Ø20 cat, 24 pt for the Ø18 one on a screen without a notch). */
const opts = (p, s, D, extra = {}) => {
  const o = { dpr: 2, ...extra };
  if (fx.strips[D]) o.room = outfitRoom(outfitAnchors(p, s, D, o), fx.strips[D] / 2, 0);
  return o;
};

test("the slots, the draw order, the floors and every coat's edge are the fixture's, and PASSES is untouched", () => {
  assert.deepEqual([...OUTFIT_SLOTS], fx.slots);
  assert.deepEqual(OUTFIT_ORDER, fx.order);
  assert.deepEqual({ ...OUTFIT_MIN }, fx.min);
  for (const id of CAT_IDS) assert.equal(outfitEdge(PRESETS[id]), fx.edge[id], id);
  assert.equal(OUTFIT_ORDER.front.indexOf("outfit.neck"), OUTFIT_ORDER.front.indexOf("collar") + 1, "the neck slot is just after the collar");
  assert.equal(OUTFIT_ORDER.front.indexOf("outfit.top"), OUTFIT_ORDER.front.indexOf("outfit.neck") + 1);
  assert.equal(OUTFIT_ORDER.front.indexOf("whiskers"), OUTFIT_ORDER.front.indexOf("outfit.top") + 1, "the whiskers stay in front of every outfit");
  assert.deepEqual(OUTFIT_ORDER.behind.slice(0, -1), PASSES.behind);
});

test("the room above the crown: the fixture's rows, and none without a number", () => {
  for (const r of fx.rooms) same(outfitRoom({ top: { y: r.top } }, r.headY, r.ceiling), r.out, JSON.stringify([r.headY, r.ceiling]));
});

test("the anchors replay: four coats at Ø20, Ø28, Ø48 and Ø64, at rest and with the head turned", () => {
  const keys = Object.keys(fx.anchors);
  assert.equal(keys.length, 32);
  for (const k of keys) {
    const [cat, D, pose] = k.split("/");
    same(outfitAnchors(PRESETS[cat], POSES[pose], Number(D), { dpr: 2 }), fx.anchors[k], k);
  }
});

test("the shapes replay: every outfit on four pinned cases, the collar strips, the unknown IDs and the detail cut", () => {
  for (const [k, byOutfit] of Object.entries(fx.geometry)) {
    const [cat, D, pose] = k.split("/");
    for (const id of OUTFIT_DRAWN) same(outfitGeometry(id, PRESETS[cat], POSES[pose], Number(D), opts(PRESETS[cat], POSES[pose], Number(D))), byOutfit[id], `${k} ${id}`);
  }
  for (const [k, row] of Object.entries(fx.collars)) {
    const [id, style] = k.split("/");
    same(collarGeometry(PRESETS.momo, POSES.rest, 64, style, { dpr: 2 }), row.collar, `${k} collar`);
    same(outfitGeometry(id, PRESETS.momo, POSES.rest, 64, { dpr: 2, collar: style }), row.shapes, k);
  }
  for (const u of fx.unknown) assert.deepEqual(outfitGeometry(u.id, PRESETS.momo, POSES.rest, 64, { dpr: 2 }), u.out, String(u.id));
  for (const f of fx.fine) {
    assert.equal(outfitGeometry(f.id, PRESETS.momo, POSES.rest, 27, { dpr: 2 }).length, f.at27, `${f.id} at Ø27`);
    assert.equal(outfitGeometry(f.id, PRESETS.momo, POSES.rest, 28, { dpr: 2 }).length, f.at28, `${f.id} at Ø28`);
  }
  for (const row of fx.shrimpSwitch.rows) {
    const shapes = outfitGeometry("shrimpclip", PRESETS.momo, POSES.rest, row.D, opts(PRESETS.momo, POSES.rest, row.D)).map((sh) => [sh.k, sh.slot, sh.fill ?? null, sh.stroke ?? null, sh.fine]);
    assert.deepEqual(shapes, row.shapes, `the shrimp clip at Ø${row.D}`);
  }
  for (const r of fx.lensRims) {
    const lenses = outfitGeometry("sunglasses", PRESETS[r.cat], POSES.rest, 64, opts(PRESETS[r.cat], POSES.rest, 64)).filter((sh) => sh.k === "ellipse" && sh.fill === "lens").map((sh) => ({ stroke: sh.stroke, sw: sh.sw }));
    same(lenses, r.lenses, `${r.cat}'s lenses`);
    assert.equal(outfitEdge(PRESETS[r.cat]), r.edge);
  }
});

test("all 256 outfit and coat pairs at Ø18, Ø20, Ø48 and Ø64 digest as the fixture says", () => {
  const keys = Object.keys(fx.digests);
  assert.equal(keys.length, 16 * 16 * 4);
  for (const k of keys) {
    const [cat, id, D] = k.split("/");
    same(outfitDigest(outfitGeometry(id, PRESETS[cat], POSES.rest, Number(D), opts(PRESETS[cat], POSES.rest, Number(D)))), fx.digests[k], k);
  }
  assert.deepEqual(outfitDigest([]), { n: 0, pts: 0, bbox: [0, 0, 0, 0], mx: 0, my: 0 });
});

test("in the compact notch every outfit on every coat has only finite numbers, no line under its floor, and stays inside the strip", () => {
  for (const [D, strip] of [[20, 32], [18, 24]]) for (const cat of CAT_IDS) for (const id of OUTFIT_DRAWN) {
    const p = PRESETS[cat], shapes = outfitGeometry(id, p, POSES.rest, D, opts(p, POSES.rest, D));
    assert.ok(shapes.length > 0, `${cat} ${id} Ø${D} is drawn`);
    finite(shapes, `${cat} ${id} Ø${D}`);
    for (const sh of shapes) assert.ok(sh.k === "curve" || sh.stroke === null ? true : sh.sw >= OUTFIT_MIN.line / 2 - 1e-9, `${cat} ${id} Ø${D}: a stroke under the floor`);
    for (const sh of shapes) if (sh.k === "curve") assert.ok(sh.sw >= OUTFIT_MIN.line / 2 - 1e-9, `${cat} ${id} Ø${D}: a curve under the floor`);
    const top = outfitDigest(shapes).bbox[1] + strip / 2;
    assert.ok(top >= -1e-9, `${cat} ${id} Ø${D}: rises ${-top.toFixed(3)} px above the strip`);
  }
});

test("a pose the engine can reach, a bad option and a bad preset ID never throw or give NaN", () => {
  const p = PRESETS.shrimpy, wild = { ...newPose(), yaw: 1.4, pitch: -1, earU: 1.4, oy: -0.3, tilt: 0.24 };
  for (const id of OUTFIT_DRAWN) for (const D of [12, 18, 20, 27, 28, 40, 66, 96]) for (const o of [{}, { dpr: 1 }, { dpr: 0 }, { dpr: -3 }, { room: 0 }, { room: NaN }, { room: null }, { collar: "bogus" }, { collar: "tag" }, { collar: "kerchief" }, { earScale: 0.5 }]) {
    finite(outfitGeometry(id, p, wild, D, o), `${id} Ø${D} ${JSON.stringify(o)}`);
  }
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/outfit.test.mjs 2>&1 | grep -E "^# (pass|fail)|ERR_MODULE_NOT_FOUND" | sort -u
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND` and `# fail 1`.

- [ ] **Step 3: Write the code**

This is a transcription of `outfitAnchors`, `outfitGeometry` and `outfitDigest` of `design/prototype/cat-core.js`, number for number. Do not change a constant: the fixture's 1024 digests compare them to 1e-9.

```bash
cat > windows/src/cat/outfit.ts <<'EOF'
// Where an outfit sits on a head and the shapes it is made of (sub-project I). A port of the second half of "The wardrobe (sub-project I)" in design/prototype/cat-core.js, the
// tie-breaker (fixture tests/fixtures/cat/wardrobe-cases.json; docs/CAT-CONTRACT.md "The wardrobe (I-0)"). Pure maths in head-local px (before the tilt and squash, like
// collarGeometry): outfitAnchors says where the parts attach, outfitGeometry returns the shapes with colour roles, and outfitdraw.ts paints them. Nothing here reads a coat list, a
// clock or a canvas. Imports geometry.ts, collar.ts and wardrobe.ts, so the plain-Node checks (npm run check:cat) can load it.

import { TAU, clamp } from "./base.ts";
import { collarGeometry, COLLAR_MIN } from "./collar.ts";
import { DETAIL_FULL_MIN, EAR_FIT, FLAT_FILL, earScale, layout, mixHex, supPoints } from "./geometry.ts";
import { OUTFIT_DRAWN } from "./wardrobe.ts";
import type { CatPreset, Pose } from "./types.ts";

/** Where in the draw order a shape goes: `behind` (after the ears in the behind pass), `neck` (the front pass after the collar) and `top` (after `neck`, before the whiskers). */
export const OUTFIT_SLOTS = ["behind", "neck", "top"] as const;
export type OutfitSlot = (typeof OUTFIT_SLOTS)[number];
/** The whole draw order with the outfit's three places in it (PASSES itself stays as A-0 wrote it). */
export const OUTFIT_ORDER = {
  behind: ["glow", "zoomTrails", "ruff", "bib", "paws", "ears", "outfit.behind"],
  head: ["head", "markings", "tint", "rim", "blush", "eyes", "mouth", "nose"],
  front: ["foldEars", "collar", "outfit.neck", "outfit.top", "whiskers", "badge", "particles", "balls"],
};
/** Smallest sizes, in DEVICE pixels (as COLLAR_MIN is), so an outfit still reads on the compact notch's Ø20 cat (40 device pixels wide at 2x). */
export const OUTFIT_MIN = { height: 6, line: 1, rim: 2, ball: 3, span: 6 } as const;

/** Whether a coat's head is dark enough that an outfit's thin edge must be light to show: `light` for a dark head, `dark` for a light one (the flat head colour's luminance under 100). */
export function outfitEdge(p: CatPreset): "light" | "dark" {
  const c = mixHex(p.top, p.bot, FLAT_FILL.headMix);
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] < 100 ? "light" : "dark";
}

/** The room above the crown for a hat, in px: from the crown to `ceiling` (the y of the strip's top, in the coordinates of `headY`) less the ear fit's margin. null without a number ceiling: no limit. */
export const outfitRoom = (a: { top: { y: number } }, headY: unknown, ceiling: unknown): number | null =>
  typeof ceiling === "number" && Number.isFinite(ceiling) && typeof headY === "number" && Number.isFinite(headY) ? Math.max(0, headY + a.top.y - ceiling - EAR_FIT.margin) : null;

export interface OutfitOptions {
  /** The device pixel ratio, default 2. */
  dpr?: number;
  detail?: "full" | "compact";
  /** The ear scale the cat's ears were drawn with (layout's `earScale`); default what the renderer uses: 1 from Ø28, else earScale(D). */
  earScale?: number;
  /** The collar style the cat wears (the bell hangs from it). */
  collar?: string;
  /** From outfitRoom: the height a hat may rise above the crown. */
  room?: number | null;
}

type Pt = [number, number];
export interface OutfitAnchors {
  R: number; rx: number; ry: number; D: number; full: boolean; dpr: number;
  top: { x: number; y: number }; gap: number; half: number; lean: number;
  ears: { sd: number; bx: number; by: number; rot: number; h: number; tipX: number; tipY: number }[];
  eyes: { sd: number; visible: boolean; x: number; y: number; fx: number; fy: number }[];
  chin: { pts: Pt[]; front: Pt };
  neck: { x: number; y: number };
  edge: "light" | "dark";
}

/** Where the outfit parts attach to one cat in one pose, in head-local px. `o.dpr` defaults to 2. */
export function outfitAnchors(p: CatPreset, s: Pose, D: number, o: OutfitOptions = {}): OutfitAnchors {
  const dpr = typeof o.dpr === "number" && o.dpr > 0 ? o.dpr : 2, ek = o.earScale === undefined ? (D >= DETAIL_FULL_MIN ? 1 : earScale(D)) : o.earScale;
  const L = layout(p, s, 0, 0, D, { detail: o.detail, earScale: ek }), { R, rx, ry, W } = L, [eL, eR] = L.ears;
  const mx = (eL.bx + eR.bx) / 2, gap = Math.abs(eR.bx - eL.bx), tx = clamp(mx / rx, -0.95, 0.95);
  const top = { x: mx, y: -ry * Math.pow(Math.max(0, 1 - Math.pow(Math.abs(tx), p.n)), 1 / p.n) + L.bend[1] * ry * (1 - tx * tx) };
  const N = 90, ring = supPoints(rx, ry, p.n, 0, p.fluff ? 0.035 : 0, 14, N, L.bend).slice(0, N);
  const arc = ring.slice((N * 40) / 360, (N * 140) / 360 + 1).reverse(), front: Pt = [(arc[12][0] + arc[13][0]) / 2, (arc[12][1] + arc[13][1]) / 2];
  const width = Math.max(0.1 * R, COLLAR_MIN.band / dpr), k = Math.max(0.7, Math.min(0.92, 1 - (width / 2 + 0.5 / dpr) / (p.ry * R))), [nx, ny] = W(0, p.ry * k);
  return {
    R, rx, ry, D, full: L.full, dpr, top, gap, half: gap / 2, lean: Math.sin(L.yf) * 0.15,
    ears: L.ears.map((e) => ({ sd: e.sd, bx: e.bx, by: e.by, rot: e.rot, h: e.h, tipX: e.bx + e.h * Math.sin(e.rot), tipY: e.by - e.h * Math.cos(e.rot) })),
    eyes: L.eyes.map((e) => ({ sd: e.sd, visible: e.visible, x: e.x, y: e.y, fx: e.fx, fy: e.fy })),
    chin: { pts: arc, front }, neck: { x: nx, y: ny }, edge: outfitEdge(p),
  };
}

/** A shape of an outfit, in head-local px. `fill` and `stroke` are colour roles (the keys of THEME.outfits) or `edge`; `a` is the alpha, `sw` the stroke width in px. */
export interface PolyShape { k: "poly"; slot: OutfitSlot; fill: string | null; stroke: string | null; sw: number; a: number; fine: boolean; pts: Pt[] }
export interface CurveShape { k: "curve"; slot: OutfitSlot; stroke: string; sw: number; a: number; fine: boolean; pts: Pt[] }
export interface EllipseShape { k: "ellipse"; slot: OutfitSlot; fill: string | null; stroke: string | null; sw: number; a: number; fine: boolean; x: number; y: number; rx: number; ry: number; rot: number }
export type OutfitShape = PolyShape | CurveShape | EllipseShape;

interface Style { stroke?: string | null; sw?: number; a?: number; fine?: boolean }

/**
 * The shapes of one outfit on one cat, in paint order. A hat rises by a natural height, shortened to `o.room` and never below the floor; a `fine` shape (a glint, a star, a rib) is left out
 * below Ø28, as the cat's own fine details are. An ID that is not one of the 16 drawn outfits (`none`, `auto`, anything else) gives [].
 */
export function outfitGeometry(id: unknown, p: CatPreset, s: Pose, D: number, o: OutfitOptions = {}): OutfitShape[] {
  if (typeof id !== "string" || !(OUTFIT_DRAWN as readonly string[]).includes(id)) return [];
  const A = outfitAnchors(p, s, D, o), { R, dpr, top, full } = A, fl = (n: keyof typeof OUTFIT_MIN) => OUTFIT_MIN[n] / dpr, ln = Math.max(fl("line"), 0.03 * R), g = A.half, ca = Math.cos(A.lean), sa = Math.sin(A.lean);
  const out: OutfitShape[] = [];
  const Q = (x: number, y: number, b: Pt = [top.x, top.y]): Pt => [b[0] + x * ca - y * sa, b[1] + x * sa + y * ca];
  const room = typeof o.room === "number" && Number.isFinite(o.room) ? o.room : Infinity, hatH = (nat: number) => Math.max(fl("height"), Math.min(nat * R, room));
  const poly = (slot: OutfitSlot, pts: Pt[], fill: string | null, st: Style = {}) =>
    out.push({ k: "poly", slot, fill, stroke: st.stroke === undefined ? "edge" : st.stroke, sw: st.stroke === null ? 0 : st.sw || ln, a: st.a === undefined ? 1 : st.a, fine: !!st.fine, pts });
  const curve = (slot: OutfitSlot, pts: Pt[], stroke: string, sw: number, st: Style = {}) =>
    out.push({ k: "curve", slot, stroke, sw: Math.max(sw, fl("line")), a: st.a === undefined ? 1 : st.a, fine: !!st.fine, pts });
  const ell = (slot: OutfitSlot, x: number, y: number, rx: number, ry: number, rot: number, fill: string | null, st: Style = {}) =>
    out.push({ k: "ellipse", slot, fill, stroke: st.stroke === undefined ? "edge" : st.stroke, sw: st.stroke === null ? 0 : st.sw || ln, a: st.a === undefined ? 1 : st.a, fine: !!st.fine, x, y, rx, ry, rot });
  const arcPts = (cx: number, cy: number, rx: number, ry: number, a0: number, a1: number, n = 10): Pt[] => Array.from({ length: n + 1 }, (_, i) => {
    const a = a0 + ((a1 - a0) * i) / n;
    return [cx + Math.cos(a) * rx, cy + Math.sin(a) * ry];
  });
  const star = (cx: number, cy: number, ro: number, ri: number): Pt[] => Array.from({ length: 10 }, (_, i) => {
    const r = i % 2 ? ri : ro, a = -Math.PI / 2 + (i * Math.PI) / 5;
    return [cx + Math.cos(a) * r, cy + Math.sin(a) * r];
  });
  /** A stadium shape, `w` its outer half width. */
  const pill = (slot: OutfitSlot, w: number, yc: number, hh: number, fill: string) =>
    poly(slot, [...arcPts(w - hh, yc, hh, hh, -Math.PI / 2, Math.PI / 2, 6), ...arcPts(hh - w, yc, hh, hh, Math.PI / 2, Math.PI * 1.5, 6)].map((q) => Q(q[0], q[1])), fill);
  const ear = (sd: number) => A.ears.find((e) => e.sd === sd)!;
  const ball = (r: number) => Math.max(fl("ball"), r);
  /** A tapered leaf along a centre line: `c(t)` the centre, `w(t)` the half width, both for t from 0 to 1. */
  const leaf = (c: (t: number) => Pt, w: (t: number) => number, n = 14): Pt[] => {
    const Lf: Pt[] = [], Rr: Pt[] = [];
    for (let i = 0; i <= n; i++) {
      const t = i / n, a = c(t), b = c(Math.min(1, t + 0.02)), d = c(Math.max(0, t - 0.02)), tx = b[0] - d[0], ty = b[1] - d[1], l = Math.hypot(tx, ty) || 1, nx = -ty / l, ny = tx / l, ww = w(t);
      Lf.push([a[0] + nx * ww, a[1] + ny * ww]);
      Rr.push([a[0] - nx * ww, a[1] - ny * ww]);
    }
    return [...Lf, ...Rr.reverse()];
  };

  // ── Hats: they stand between the ear bases, so they are as wide as the gap and no wider
  if (id === "partyhat") {
    const Hh = hatH(1.35), b: Pt = [top.x, top.y + 0.05 * R], w = 0.7, tx = 0.3, H = (x: number, y: number) => Q(x * g, y * Hh, b);
    const Lf = (t: number) => H(-w + (tx + w) * t, -t), Rt = (t: number) => H(w + (tx - w) * t, -t), tip = H(tx, -1);
    poly("top", [...arcPts(0, 0, w * g, 0.1 * R, Math.PI, 0, 8).map((q) => Q(q[0], -q[1], b)), tip], "partyA");
    for (const [t0, t1] of [[0.16, 0.32], [0.5, 0.64]]) poly("top", [Lf(t0), Lf(t1), Rt(t1), Rt(t0)], "partyB", { stroke: null });
    poly("top", star(tip[0], tip[1] - 0.04 * R, 0.2 * R, 0.09 * R), "partyStar", { fine: true, sw: ln });
  } else if (id === "santahat") {
    const Hh = hatH(0.95), b: Pt = [top.x, top.y + 0.1 * R], hw = 0.82, H = (x: number, y: number) => Q(x * g, y * Hh, b);
    poly("top", [H(-hw, 0), H(-0.74, -0.45), H(-0.4, -0.86), H(0, -1), H(0.42, -0.88), H(0.74, -0.5), H(hw, 0)], "santaRed");
    const c = (t: number): Pt => { const m = 1 - t; return H(2 * m * t * -0.5 + t * t * -0.58, m * m * -0.95 + 2 * m * t * -1.02 + t * t * -0.5); }, tip = c(1);
    poly("top", leaf(c, (t) => (0.26 - 0.18 * t) * g, 10), "santaRed", { stroke: null });
    ell("top", tip[0], tip[1], ball(0.17 * R), ball(0.17 * R), 0, "fur");
    pill("top", 0.95 * g, 0, Math.max(fl("line") * 2, 0.12 * R), "fur");
  } else if (id === "witchhat") {
    const Hh = hatH(1.5), b: Pt = [top.x, top.y + 0.04 * R], H = (x: number, y: number) => Q(x * g, y * Hh, b);
    const q0 = Q(0, 0, b);
    ell("top", q0[0], q0[1], 0.95 * g, Math.max(0.12 * R, fl("line") * 2), A.lean, "witchHat");
    poly("top", [H(-0.52, 0), H(-0.36, -0.4), H(-0.08, -0.72), H(0.1, -0.82), H(0.62, -1), H(0.4, -0.66), H(0.34, -0.45), H(0.52, 0)], "witchHat");
    poly("top", [H(-0.5, -0.1), H(0.5, -0.1), H(0.45, -0.3), H(-0.42, -0.3)], "witchBand", { stroke: null });
    poly("top", [H(-0.12, -0.06), H(0.12, -0.06), H(0.12, -0.34), H(-0.12, -0.34)], "gold", { sw: ln });
  } else if (id === "bunnyears") {
    const cm = !full, Hh = hatH(cm ? 1.9 : 1.45), b: Pt = [top.x, top.y + (cm ? 0.1 : 0.5) * R], H = (x: number, y: number) => Q(x * g, y * Hh, b);
    // Below Ø28 the ears are taller (their base sits nearer the crown) and wider, so they show above the head at Ø18 and Ø20; the open size is unchanged.
    for (const sd of [-1, 1]) {
      const bend = sd > 0 ? 0.9 : 0, c = (t: number): Pt => { const x = sd * (0.4 + 0.22 * t) + bend * Math.pow(Math.max(0, t - 0.55), 2) * 1.2; return H(x, -t); };
      const wm = Math.max((cm ? 0.5 : 0.3) * g, fl("span") / 2), w = (t: number) => wm * Math.pow(Math.sin(Math.PI * (0.2 + 0.8 * t)), 0.8);
      poly("behind", leaf(c, w), "bunnyOuter");
      poly("behind", leaf((t) => c(0.06 + 0.74 * t), (t) => w(0.06 + 0.74 * t) * 0.55), "bunnyInner", { stroke: null });
    }
  } else if (id === "beanie") {
    const Hh = hatH(0.78), b: Pt = [top.x, top.y + 0.26 * R], hw = 0.95, H = (x: number, y: number) => Q(x * g, y * Hh, b);
    poly("top", arcPts(0, 0, hw, 1, Math.PI, Math.PI * 2, 14).map((q) => H(q[0], q[1])), "beanieBody");
    for (const x of [-0.5, 0, 0.5]) curve("top", [H(x * 0.9, -0.15), H(x, -0.62), H(x * 0.5, -0.92)], "beanieCuff", ln * 0.9, { fine: true, a: 0.7 });
    pill("top", 0.96 * g, 0, Math.max(0.14 * R, fl("span") / 2), "beanieCuff");
    const t = H(0, -1.0);
    ell("top", t[0], t[1] - 0.04 * R, ball(0.17 * R), ball(0.17 * R), 0, "fur");
  } else if (id === "crown") {
    const Hh = hatH(0.55), b: Pt = [top.x, top.y + 0.12 * R], hw = 0.7, H = (x: number, y: number) => Q(x * g, y * Hh, b);
    poly("top", [H(-hw, 0), H(-hw, -0.72), H(-0.4, -0.4), H(0, -1), H(0.4, -0.4), H(hw, -0.72), H(hw, 0)], "gold");
    poly("top", [H(-hw, 0), H(hw, 0), H(hw, -0.22), H(-hw, -0.22)], "goldDark", { stroke: null, a: 0.85 });
    ([[-hw, -0.72, "gemA"], [0, -1, "gemB"], [hw, -0.72, "gemC"]] as const).forEach(([x, y, r]) => {
      const q = H(x, y), gr = ball(0.09 * R);
      ell("top", q[0], q[1] + gr, gr, gr, 0, r);
    });
  // ── Glasses: they follow the eye frames and flatten with the face turn
  } else if (id === "sunglasses" || id === "roundglasses") {
    const sun = id === "sunglasses", E = p.eye, lr = (sun ? 1.75 : 1.95) * E.w * R, lv = (sun ? 1.55 : 1.7) * Math.max(E.h, 0.85 * E.w) * R, fr = Math.max(fl("rim"), sun ? 0.06 * R : 0.045 * R);
    const eyes = A.eyes.filter((e) => e.visible);
    for (const e of eyes) {
      const rx = Math.max(lr * e.fx, fl("ball")), ry = Math.max(lv * e.fy, fl("ball"));
      if (sun) {
        const rim = A.edge === "light"; // a dark head: the frame's dark would vanish, so a thin light rim (the edge role) outlines the lens
        ell("top", e.x, e.y, rx, ry, 0, "lens", rim ? { stroke: "edge", sw: ln, a: 0.93 } : { stroke: "frame", sw: fr, a: 0.93 });
        poly("top", [[e.x - rx * 0.5, e.y - ry * 0.15], [e.x - rx * 0.12, e.y - ry * 0.62], [e.x + rx * 0.12, e.y - ry * 0.62], [e.x - rx * 0.3, e.y + ry * 0.08]], "glint", { stroke: null, a: 0.55, fine: true });
      } else {
        ell("top", e.x, e.y, rx, ry, 0, "glassTint", { stroke: "rim", sw: fr, a: 0.22 });
        ell("top", e.x, e.y, rx, ry, 0, null, { stroke: "rim", sw: fr });
        curve("top", arcPts(e.x, e.y, rx * 0.72, ry * 0.72, Math.PI * 1.05, Math.PI * 1.4, 5), "glint", ln, { fine: true, a: 0.8 });
      }
    }
    if (eyes.length === 2) {
      const [a, b2] = eyes.sort((u, v) => u.sd - v.sd), ax = a.x + Math.max(lr * a.fx, fl("ball")), bx = b2.x - Math.max(lr * b2.fx, fl("ball")), my = (a.y + b2.y) / 2;
      curve("top", [[ax, a.y], [(ax + bx) / 2, my - (sun ? 0.06 : 0.1) * R], [bx, b2.y]], sun ? "frame" : "rim", fr);
    }
    for (const e of eyes) {
      const ox = e.x + e.sd * Math.max(lr * e.fx, fl("ball"));
      curve("top", [[ox, e.y - lv * e.fy * 0.2], [ox + e.sd * 0.3 * R * e.fx, e.y - lv * e.fy * 0.05]], sun ? "frame" : "rim", fr);
    }
  // ── Clips, the bow and the flower: at an ear base, turning with the ear
  } else if (id === "bow") {
    const e = ear(1), cx = e.bx - 0.12 * R, cy = e.by + 0.02 * R, u = Math.max(R * 0.9, fl("span") * 1.6), rot = e.rot * 0.6;
    for (const sd of [-1, 1]) ell("top", cx + sd * 0.3 * u * Math.cos(rot), cy + sd * 0.3 * u * Math.sin(rot), 0.3 * u, 0.21 * u, rot + sd * 0.35, "bowRed");
    poly("top", [[cx - 0.05 * u, cy + 0.1 * u], [cx - 0.2 * u, cy + 0.55 * u], [cx - 0.05 * u, cy + 0.45 * u]], "bowKnot", { fine: true });
    poly("top", [[cx + 0.05 * u, cy + 0.1 * u], [cx + 0.2 * u, cy + 0.55 * u], [cx + 0.05 * u, cy + 0.45 * u]], "bowKnot", { fine: true });
    ell("top", cx, cy, ball(0.1 * u), ball(0.1 * u), 0, "bowKnot");
  } else if (id === "fishclip") {
    const e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.1 * R, u = Math.max(R, fl("span") * 1.7), rot = e.rot * 0.5;
    ell("top", cx, cy, 0.27 * u, 0.13 * u, rot, "fishBody");
    poly("top", [[cx + 0.25 * u * Math.cos(rot), cy + 0.25 * u * Math.sin(rot)], [cx + 0.45 * u, cy - 0.14 * u], [cx + 0.45 * u, cy + 0.14 * u]], "fishFin");
    ell("top", cx - 0.13 * u, cy - 0.02 * u, 0.025 * u, 0.025 * u, 0, "lens", { stroke: null, fine: true });
  } else if (id === "flower") {
    const e = ear(1), cx = e.bx - 0.22 * R, cy = e.by + 0.1 * R, u = Math.max(R, fl("span") * 1.7);
    for (let i = 0; i < 5; i++) {
      const a = -Math.PI / 2 + (i * TAU) / 5;
      ell("top", cx + Math.cos(a) * 0.15 * u, cy + Math.sin(a) * 0.15 * u, ball(0.13 * u), ball(0.09 * u), a, "petal");
    }
    ell("top", cx, cy, ball(0.07 * u), ball(0.07 * u), 0, "gold", { sw: ln });
  } else if (id === "shrimpclip" && !full) {
    // Below Ø28 (the detail cut) the shrimp is simple and bold: one thick curled C, one fanned tail with three tips, both in the shrimp colour with the edge round them.
    const e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.12 * R, u = Math.max(R, fl("span") * 1.7), r = 0.3 * u, sw = Math.max(0.2 * u, fl("span") / 2), a0 = Math.PI * 0.25, a1 = Math.PI * 1.45;
    const tx = cx + r * Math.cos(a1), ty = cy + r * Math.sin(a1), td = [-Math.sin(a1), Math.cos(a1)], nd = [Math.cos(a1), Math.sin(a1)], L2 = 0.55 * u, w = 0.22 * u;
    const at = (a: number, b: number): Pt => [tx + a * td[0] + b * nd[0], ty + a * td[1] + b * nd[1]];
    curve("top", arcPts(cx, cy, r, r, a0, a1, 10), "edge", sw + 2 * ln);
    curve("top", arcPts(cx, cy, r, r, a0, a1, 10), "shrimp", sw);
    poly("top", [at(0, w * 0.5), at(L2 * 0.9, w), at(L2 * 0.45, w * 0.35), at(L2 * 1.1, 0), at(L2 * 0.45, -w * 0.35), at(L2 * 0.9, -w), at(0, -w * 0.5)], "shrimp");
  } else if (id === "shrimpclip") {
    const e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.12 * R, u = Math.max(R, fl("span") * 1.7), r = 0.15 * u, sw = Math.max(0.12 * u, fl("span") / 2);
    // a curled, segmented body: four segments along a C, a fine dark joint between each pair
    for (let i = 0; i < 4; i++) {
      const a0 = Math.PI * (0.25 + i * 0.3);
      curve("top", arcPts(cx, cy, r, r, a0, a0 + Math.PI * 0.3, 4), "shrimp", sw);
    }
    for (let i = 1; i < 4; i++) {
      const a = Math.PI * (0.25 + i * 0.3);
      curve("top", [[cx + 0.8 * r * Math.cos(a), cy + 0.8 * r * Math.sin(a)], [cx + 1.25 * r * Math.cos(a), cy + 1.25 * r * Math.sin(a)]], "shrimpDark", ln);
    }
    // a fanned tail: three spikes, between notches, off the end of the C
    const a1 = Math.PI * 1.45, tx = cx + r * Math.cos(a1), ty = cy + r * Math.sin(a1);
    poly("top", [[tx, ty], [tx + 0.2 * u, ty - 0.14 * u], [tx + 0.13 * u, ty - 0.03 * u], [tx + 0.26 * u, ty], [tx + 0.13 * u, ty + 0.03 * u], [tx + 0.2 * u, ty + 0.14 * u]], "shrimp", {});
    poly("top", [[tx, ty], [tx + 0.2 * u, ty - 0.12 * u], [tx + 0.12 * u, ty - 0.02 * u]], "shrimpDark", { fine: true });
    // two small feelers from the head end of the C
    const a2 = Math.PI * 0.25, hx = cx + r * Math.cos(a2), hy = cy + r * Math.sin(a2);
    curve("top", [[hx, hy], [hx + 0.1 * u, hy - 0.16 * u]], "shrimpDark", ln);
    curve("top", [[hx, hy], [hx + 0.04 * u, hy - 0.2 * u]], "shrimpDark", ln);
  } else if (id === "blossomclip") {
    const e = ear(1), cx = e.bx - 0.22 * R, cy = e.by + 0.1 * R, u = Math.max(R, fl("span") * 1.7);
    for (const sd of [-1, 1]) ell("top", cx + sd * 0.2 * u, cy + 0.14 * u, ball(0.13 * u), ball(0.06 * u), sd * 0.6, "leaf");
    for (let i = 0; i < 5; i++) {
      const a = -Math.PI / 2 + (i * TAU) / 5;
      ell("top", cx + Math.cos(a) * 0.13 * u, cy + Math.sin(a) * 0.13 * u, ball(0.11 * u), ball(0.11 * u), a, i % 2 ? "blossomDeep" : "blossom");
    }
    ell("top", cx, cy, ball(0.05 * u), ball(0.05 * u), 0, "gold", { stroke: null });
  // ── Neck: over the collar
  } else if (id === "scarf" || id === "bandana" || id === "bell") {
    const inw = (q: Pt, d: number): Pt => { const l = Math.hypot(q[0], q[1]) || 1; return [q[0] * (1 - d / l), q[1] * (1 - d / l)]; }, pts = A.chin.pts.map((q) => inw(q, 0.12 * R));
    if (id === "scarf") {
      const wd = Math.max(0.42 * R, fl("span"));
      curve("neck", pts, "edge", wd + 2 * ln, { a: 0.9 });
      curve("neck", pts, "scarfA", wd);
      curve("neck", pts.map((q) => inw(q, -0.1 * R)), "scarfB", Math.max(0.07 * R, fl("line") * 1.5));
      curve("neck", pts.map((q) => inw(q, 0.1 * R)), "scarfB", Math.max(0.07 * R, fl("line") * 1.5));
      const t0 = pts[5], tw = Math.max(0.27 * R, fl("span")), tl = 0.5 * R;
      poly("neck", [[t0[0] - tw / 2, t0[1] - 0.05 * R], [t0[0] + tw / 2, t0[1] - 0.05 * R], [t0[0] + tw / 2 - 0.06 * R, t0[1] + tl], [t0[0] - tw / 2 - 0.06 * R, t0[1] + tl]], "scarfA");
      poly("neck", [[t0[0] - tw / 2 - 0.015 * R, t0[1] + tl * 0.55], [t0[0] + tw / 2 - 0.045 * R, t0[1] + tl * 0.55], [t0[0] + tw / 2 - 0.05 * R, t0[1] + tl * 0.7], [t0[0] - tw / 2 - 0.02 * R, t0[1] + tl * 0.7]], "scarfB", { stroke: null });
    } else if (id === "bandana") {
      const apex: Pt = [A.chin.front[0], Math.max(...pts.map((q) => q[1])) + 0.48 * R];
      poly("neck", [...pts.map((q) => inw(q, -0.06 * R)), apex], "bandanaRed");
      const kn = pts[2];
      poly("neck", [[kn[0] - 0.12 * R, kn[1]], [kn[0] - 0.4 * R, kn[1] + 0.3 * R], [kn[0] - 0.05 * R, kn[1] + 0.26 * R]], "bandanaRed", {});
      ell("neck", kn[0], kn[1], ball(0.1 * R), ball(0.1 * R), 0, "bandanaRed");
      ([[0, 0.34], [-0.28, 0.18], [0.28, 0.18]] as const).forEach(([x, y]) => ell("neck", A.chin.front[0] + x * R, A.chin.front[1] + y * R, ball(0.045 * R), ball(0.045 * R), 0, "white", { stroke: null, fine: true }));
    } else {
      const G = collarGeometry(p, s, D, o.collar, { dpr: A.dpr, detail: o.detail });
      let at: Pt = [A.neck.x, A.neck.y];
      if (G && G.tag) at = [G.tag.x, G.tag.y + G.tag.r]; else if (G && G.band) at = G.band[G.band.length >> 1] as Pt; else if (G && G.kerchief) at = G.kerchief.apex as Pt;
      const r = ball(0.2 * R);
      ell("neck", at[0], at[1] - 0.1 * R, ball(0.07 * R), ball(0.07 * R), 0, null, { stroke: "silver", sw: Math.max(ln * 1.4, fl("line")) });
      ell("neck", at[0], at[1] + 0.12 * R, r, r, 0, "gold");
      curve("neck", [[at[0] - r * 0.7, at[1] + 0.1 * R], [at[0] + r * 0.7, at[1] + 0.1 * R]], "goldDark", ln, { fine: true });
      ell("neck", at[0], at[1] + 0.12 * R + r * 0.55, ball(0.04 * R), ball(0.04 * R), 0, "goldDark", { stroke: null, fine: true });
    }
  }
  return full ? out : out.filter((sh) => !sh.fine);
}

/** A digest two implementations can compare within the tolerance: the number of shapes and points, the box that holds them (an ellipse counts as its axis-aligned box and its centre as a point) and the mean point. */
export function outfitDigest(shapes: readonly OutfitShape[]): { n: number; pts: number; bbox: number[]; mx: number; my: number } {
  let pts = 0, sx = 0, sy = 0, x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  const add = (x: number, y: number) => { pts++; sx += x; sy += y; x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); };
  for (const sh of shapes) {
    if (sh.k === "ellipse") { add(sh.x, sh.y); x0 = Math.min(x0, sh.x - sh.rx); x1 = Math.max(x1, sh.x + sh.rx); y0 = Math.min(y0, sh.y - sh.ry); y1 = Math.max(y1, sh.y + sh.ry); }
    else for (const q of sh.pts) add(q[0], q[1]);
  }
  return shapes.length ? { n: shapes.length, pts, bbox: [x0, y0, x1, y1], mx: sx / pts, my: sy / pts } : { n: 0, pts: 0, bbox: [0, 0, 0, 0], mx: 0, my: 0 };
}
EOF
```

- [ ] **Step 4: Run it to see it pass**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/outfit.test.mjs 2>&1 | grep -E "^# (pass|fail)"
cd ..
```

Expected: `# pass 7` and `# fail 0`.

- [ ] **Step 5: Prove it bites**

Run (the party hat's natural height, 1.35 R, is in the digests of every coat):

```bash
cd windows
python3 ../.claude/checkpoints/i-tauri/mut.py src/cat/outfit.ts "hatH(1.35)" "hatH(1.3)" scripts/cat-tests/outfit.test.mjs
cd ..
```

Expected: `outfit.ts | hatH(1.3) | # pass 5 # fail 2`.

- [ ] **Step 6: Type check and the whole suite**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `tsc exit 0` with no type error before it, `ℹ tests 383`, `ℹ pass 383` and `ℹ fail 0`.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/cat/outfit.ts windows/scripts/cat-tests/outfit.test.mjs
git commit -F - <<'MSG'
feat(wardrobe): the outfits' anchors and shapes in TypeScript

outfitAnchors, outfitGeometry (16 outfits), outfitRoom, outfitEdge and outfitDigest, ported from cat-core.js and replayed from wardrobe-cases.json: the anchors, the shapes on four pinned cases, the collar strips, and all 256 outfit and coat pairs at four sizes.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

### Task 3: The stored `outfit`: the block, TypeScript and Rust

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Modify: `windows/src/cat/display.ts` (`CatBlock`, `cleanCatBlock`, `withOutfit`)
- Modify: `windows/src-tauri/src/cat_settings.rs` (`OUTFIT_IDS`, `clean_wardrobe_settings`, `clean_cat_block`, tests), `windows/src-tauri/src/settings.rs` (one test)
- Modify: `windows/scripts/cat-tests/display.test.mjs` (the block now has ten keys)
- Test: `windows/scripts/cat-tests/wardrobe-settings.test.mjs`

**Interfaces:**
- Consumes: `wardrobe.ts` (`cleanWardrobeSettings`, `outfitIdOf`, `OutfitId`).
- Produces: `CatBlock` gains `outfit: OutfitId`; `cleanCatBlock(raw)` returns it cleaned (`auto` when missing or bad) next to the other three parts; `withOutfit(b: CatBlock, v: unknown): CatBlock`. Rust: `pub const OUTFIT_IDS: [&str; 18]`, `pub fn clean_wardrobe_settings(raw: &Value) -> Value` (`{"outfit": …}`), and `clean_cat_block` inserting the `outfit` key; `settings::sanitized` runs the block through it already, so a save keeps it.

- [ ] **Step 1: Write the new test and update the one that counts the block's keys**

```bash
cat > windows/scripts/cat-tests/wardrobe-settings.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { cleanCatBlock, defaultCatBlock, withCatSettings, withDesktopOn, withDisplayMode, withOutfit } from "../../src/cat/display.ts";
import { cleanCatSettings, withCollar } from "../../src/cat/settings.ts";
import { OUTFIT_IDS, cleanWardrobeSettings } from "../../src/cat/wardrobe.ts";
import { load } from "./util.mjs";

// The `outfit` key of the `cat` block (sub-project I): cleaned with the other three parts, kept by every edit of the others, and a fresh install is auto.
const fx = load("wardrobe-cases.json");

test("a fresh install holds auto, and every stored ID of the fixture comes through the block as written", () => {
  assert.equal(defaultCatBlock().outfit, "auto");
  assert.equal(cleanCatBlock(null).outfit, "auto");
  for (const id of OUTFIT_IDS) assert.equal(cleanCatBlock({ outfit: id }).outfit, id, id);
  for (const c of fx.settings) assert.deepEqual({ outfit: cleanCatBlock(c.input).outfit }, c.out, c.name);
  assert.deepEqual(cleanCatBlock({ outfit: "crown" }).outfit, cleanWardrobeSettings({ outfit: "crown" }).outfit);
});

test("a hand-edited or half-written outfit becomes auto and the rest of the block is untouched", () => {
  for (const bad of [7, null, true, [], ["bow"], {}, "Bow", " bow", "party-hat", "fancyhat", "", "__proto__"]) {
    const b = cleanCatBlock({ character: "momo", displayMode: "two", desktop: { on: true, size: "large" }, outfit: bad });
    assert.equal(b.outfit, "auto", JSON.stringify(bad));
    assert.deepEqual([b.character, b.displayMode, b.desktop.on, b.desktop.size], ["momo", "two", true, "large"], "the other parts are kept");
  }
  const block = cleanCatBlock({ outfit: "bow", collar: "band" });
  assert.deepEqual(cleanCatBlock(block), block, "cleaning twice changes nothing");
  assert.deepEqual(cleanCatBlock(JSON.parse(JSON.stringify(block))), block, "it survives JSON");
});

test("every other edit keeps the outfit, and the outfit edit keeps everything else", () => {
  const b = withOutfit(defaultCatBlock(), "santahat");
  assert.equal(b.outfit, "santahat");
  assert.equal(withCatSettings(b, withCollar(cleanCatSettings(b), "band")).outfit, "santahat", "a Cat settings row");
  assert.equal(withDisplayMode(b, "two").outfit, "santahat", "the Display row");
  assert.equal(withDesktopOn(b, true).outfit, "santahat", "the desktop cat's switch");
  const c = withOutfit(withDisplayMode(withDesktopOn(defaultCatBlock(), true), "two"), "none");
  assert.deepEqual([c.outfit, c.displayMode, c.desktop.on], ["none", "two", true]);
  assert.equal(withOutfit(b, "Crown").outfit, "auto", "a value that is not an ID is auto");
  assert.equal(withOutfit(b, undefined).outfit, "auto");
  assert.equal("outfit" in cleanCatSettings(b), false, "cleanCatSettings drops it: that is why the block has a clean-up of its own");
});
EOF
```

Then the existing `display.test.mjs` is told that the block has a tenth key and a default of its own:

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

t = "windows/scripts/cat-tests/display.test.mjs"
edit(t, '''["agentCats", "cats", "character", "collar", "desktop", "displayMode", "furLines", "motionStyle", "pair"]''',
        '''["agentCats", "cats", "character", "collar", "desktop", "displayMode", "furLines", "motionStyle", "outfit", "pair"]''')
edit(t, '''{ ...defaultCatSettings(), ...DEFAULTS, desktop: { on: false, size: "medium", spots: {} } }''',
        '''{ ...defaultCatSettings(), ...DEFAULTS, desktop: { on: false, size: "medium", spots: {} }, outfit: "auto" }''')
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe-settings.test.mjs scripts/cat-tests/display.test.mjs 2>&1 | grep -E "^# (pass|fail)|does not provide an export" | sort -u
cd ..
```

Expected: `does not provide an export named 'withOutfit'` and `# fail 2`.

- [ ] **Step 3: Write the TypeScript**

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

d = "windows/src/cat/display.ts"
edit(d, '''import { catIdOf, cleanCatSettings } from "./settings.ts";
import type { CatSettings } from "./settings.ts";
''', '''import { catIdOf, cleanCatSettings } from "./settings.ts";
import type { CatSettings } from "./settings.ts";
import { cleanWardrobeSettings, outfitIdOf } from "./wardrobe.ts";
import type { OutfitId } from "./wardrobe.ts";
''')
edit(d, '''/** The `cat` block of settings.json, clean: the Cat settings (settings.ts), the Display settings and the desktop cat's (`desktop`, desktop.ts: sub-project H). */
export type CatBlock = CatSettings & DisplaySettings & { desktop: DesktopSettings };

/** Cleans the block with all three clean-ups: a clean-up that used cleanCatSettings alone would drop the display keys and `desktop` at the next save. Never throws. */
export const cleanCatBlock = (raw: unknown): CatBlock => ({ ...cleanCatSettings(raw), ...cleanDisplaySettings(raw), desktop: cleanDesktopSettings(isPlain(raw) ? raw.desktop : undefined) });''',
'''/** The `cat` block of settings.json, clean: the Cat settings (settings.ts), the Display settings, the desktop cat's (`desktop`, desktop.ts: sub-project H) and the wardrobe's (`outfit`, wardrobe.ts: sub-project I). */
export type CatBlock = CatSettings & DisplaySettings & { desktop: DesktopSettings; outfit: OutfitId };

/** Cleans the block with all four clean-ups: a clean-up that used cleanCatSettings alone would drop the display keys, `desktop` and `outfit` at the next save. Never throws. */
export const cleanCatBlock = (raw: unknown): CatBlock => ({
  ...cleanCatSettings(raw), ...cleanDisplaySettings(raw), desktop: cleanDesktopSettings(isPlain(raw) ? raw.desktop : undefined), ...cleanWardrobeSettings(raw),
});''')
edit(d, '''/** The dice and "Reset to defaults" give back a whole map''', '''/** The Wardrobe section and the two cats' menus: one of the 18 selection IDs (anything else is `auto`). */
export const withOutfit = (b: CatBlock, v: unknown): CatBlock => cleanCatBlock({ ...b, outfit: outfitIdOf(v) });
/** The dice and "Reset to defaults" give back a whole map''')
EOF
```

- [ ] **Step 4: Run them to see them pass**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe-settings.test.mjs scripts/cat-tests/display.test.mjs 2>&1 | grep -E "^# (pass|fail)"
cd ..
```

Expected: `# pass 13` and `# fail 0`.

- [ ] **Step 5: Prove it bites**

Run (a block cleaned without the wardrobe's clean-up has no `outfit`):

```bash
cd windows
python3 ../.claude/checkpoints/i-tauri/mut.py src/cat/display.ts "...cleanWardrobeSettings(raw)," "" scripts/cat-tests/wardrobe-settings.test.mjs
cd ..
```

Expected: `display.ts |  | # pass 0 # fail 3`.

- [ ] **Step 6: Write the Rust twin**

`clean_wardrobe_settings` uses the file's own `word` helper, so a stored value is kept only when it is a string equal to one of the 18, as written. The tests replay `wardrobe-cases.json` and prove that `sanitized` keeps the key at a save and cleans a hand-edited file without moving it aside.

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

r = "windows/src-tauri/src/cat_settings.rs"
edit(r, '''// (tests/fixtures/cat/desktop-cases.json): `desktop: { on, size, spots: { <screenKey>: { x, y } } }`. `clean_cat_block` cleans that too.
''', '''// (tests/fixtures/cat/desktop-cases.json): `desktop: { on, size, spots: { <screenKey>: { x, y } } }`. `clean_cat_block` cleans that too.
//
// And the wardrobe's (sub-project I), cleaned by `clean_wardrobe_settings`, a port of `cleanWardrobeSettings` (tests/fixtures/cat/wardrobe-cases.json): `outfit`, one of the 18 selection IDs.
''')
edit(r, '''/// The whole `cat` block: the Cat settings, the Display settings and the desktop cat's, each cleaned by its own clean-up. This is what `settings::sanitized` runs the block through.
pub fn clean_cat_block(raw: &Value) -> Value {''', '''// ── The wardrobe's settings (sub-project I) ───────────────────────────────────────────────────────────────────────────────────────────────────

/// The 18 outfit selection IDs, in the order of the grid: frozen contract values, because they are stored. Anything else stored is `auto`.
pub const OUTFIT_IDS: [&str; 18] = [
    "auto", "none", "partyhat", "santahat", "witchhat", "bunnyears", "sunglasses", "beanie", "bow", "scarf", "roundglasses", "crown", "bell", "bandana", "fishclip", "flower", "shrimpclip", "blossomclip",
];

/// Everything the wardrobe saves, cleaned: `{ outfit }`. The ID is kept only when it is a string equal to one of the 18, as written (no case folding, no trimming); anything else, or no
/// value, is `auto`. Reads only its own key. Never panics.
pub fn clean_wardrobe_settings(raw: &Value) -> Value {
    json!({ "outfit": word(raw.as_object().and_then(|r| r.get("outfit")), &OUTFIT_IDS, "auto") })
}

/// The whole `cat` block: the Cat settings, the Display settings, the desktop cat's and the wardrobe's, each cleaned by its own clean-up. This is what `settings::sanitized` runs the block through.
pub fn clean_cat_block(raw: &Value) -> Value {''')
edit(r, '''        o.insert("desktop".to_string(), clean_desktop_settings(raw.get("desktop").unwrap_or(&NULL)));
    }
    block''', '''        o.insert("desktop".to_string(), clean_desktop_settings(raw.get("desktop").unwrap_or(&NULL)));
        o.insert("outfit".to_string(), clean_wardrobe_settings(raw)["outfit"].clone());
    }
    block''')
edit(r, '''    #[test]
    fn the_whole_block_holds_the_desktop_settings_and_cleaning_it_twice_changes_nothing() {''', '''    #[test]
    fn the_wardrobe_clean_up_replays_the_fixture() {
        let fx = fixture("wardrobe-cases.json");
        let ids: Vec<&str> = fx["ids"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(ids, OUTFIT_IDS);
        assert_eq!(fx["defaultOutfit"], "auto");
        let clean = fx["clean"].as_array().unwrap();
        assert!(clean.len() >= 38);
        for c in clean {
            assert_eq!(clean_wardrobe_settings(&json!({ "outfit": c["input"] }))["outfit"], c["out"], "{}", c["name"]);
        }
        let settings = fx["settings"].as_array().unwrap();
        assert!(settings.len() >= 11);
        for c in settings {
            assert_same(&clean_wardrobe_settings(&c["input"]), &c["out"], c["name"].as_str().unwrap());
        }
        assert_eq!(clean_wardrobe_settings(&Value::Null), json!({"outfit": "auto"}));
        for id in OUTFIT_IDS {
            assert_eq!(clean_wardrobe_settings(&json!({"outfit": id})), json!({"outfit": id}), "{id}");
        }
    }

    #[test]
    fn the_whole_block_holds_the_outfit_and_every_clean_up_of_the_block_keeps_it() {
        let raw = json!({"character": "momo", "displayMode": "two", "desktop": {"on": true}, "outfit": "crown"});
        let block = clean_cat_block(&raw);
        assert_eq!((&block["outfit"], &block["character"], &block["displayMode"], &block["desktop"]["on"]), (&json!("crown"), &json!("momo"), &json!("two"), &json!(true)));
        assert_eq!(clean_cat_block(&block), block, "cleaning twice changes nothing");
        assert_eq!(block_default()["outfit"], "auto");
        for bad in [json!(7), json!(null), json!(true), json!([]), json!(["bow"]), json!({}), json!("Bow"), json!(" bow"), json!("bow\\n"), json!("party-hat"), json!("")] {
            assert_eq!(clean_cat_block(&json!({"character": "momo", "outfit": bad}))["outfit"], "auto", "{bad}");
        }
        assert!(clean_cat_settings(&raw).get("outfit").is_none(), "the Cat settings clean-up alone drops it: that is why the block has a clean-up of its own");
        assert!(clean_display_settings(&raw).get("outfit").is_none());
        assert!(clean_desktop_settings(&raw).get("outfit").is_none());
    }

    #[test]
    fn the_whole_block_holds_the_desktop_settings_and_cleaning_it_twice_changes_nothing() {''')

s = "windows/src-tauri/src/settings.rs"
edit(s, '''    /// A hand-edited file with a bad `desktop` is cleaned without failing the file or touching the rest of the block.''', '''    /// The wardrobe's `outfit` sits in the same `cat` block: a save keeps it, a load gives it back, and a bad one is auto without failing the file.
    #[test]
    fn the_outfit_survives_a_save_a_load_and_a_round_trip_and_a_bad_one_is_auto() {
        let dir = std::env::temp_dir().join(format!("notchmeow-outfit-key-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.cat = serde_json::json!({"character": "momo", "displayMode": "two", "desktop": {"on": true, "size": "large"}, "outfit": "blossomclip"});
        let sent = sanitized(s);
        assert_eq!(sent.cat["outfit"], "blossomclip");
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = load_from(&path);
        assert_eq!(back.cat, sent.cat, "what was saved is what loads");
        assert_eq!((&back.cat["outfit"], &back.cat["displayMode"], &back.cat["desktop"]["size"]), (&serde_json::json!("blossomclip"), &serde_json::json!("two"), &serde_json::json!("large")), "the other parts are still there");
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).cat, back.cat, "a second round trip changes nothing");
        for cat in [r#"{"character":"momo","outfit":7}"#, r#"{"character":"momo","outfit":"Santahat"}"#, r#"{"character":"momo","outfit":["bow"]}"#, r#"{"character":"momo"}"#] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"cat":{cat}}}"#)).unwrap();
            let s = load_from(&path);
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {cat}");
            assert_eq!((&s.cat["outfit"], &s.cat["character"]), (&serde_json::json!("auto"), &serde_json::json!("momo")), "{cat}");
            assert!(path.exists(), "the file is not moved aside: {cat}");
        }
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A hand-edited file with a bad `desktop` is cleaned without failing the file or touching the rest of the block.''')
EOF
```

Check that the file still parses (this needs no Docker and no crate):

```bash
rustfmt --check --edition 2021 windows/src-tauri/src/cat_settings.rs >/dev/null 2>.claude/checkpoints/i-tauri/rustfmt.err; grep -c "^error" .claude/checkpoints/i-tauri/rustfmt.err
rustfmt --check --edition 2021 windows/src-tauri/src/settings.rs >/dev/null 2>.claude/checkpoints/i-tauri/rustfmt2.err; grep -c "^error" .claude/checkpoints/i-tauri/rustfmt2.err
```

Expected: `0` and `0` (`rustfmt --check` exits 1 here because the repository is not formatted to its defaults: only an `error` line would be a parse error; if `rustfmt` is not on the host, skip this).

- [ ] **Step 7: Run the Rust tests**

Run (needs the image; otherwise this step and Step 8 are owed):

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/i-tauri -- cat_settings:: settings:: 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok.` with no `error` and no `warning`; the three new tests are `the_wardrobe_clean_up_replays_the_fixture` and `the_whole_block_holds_the_outfit_and_every_clean_up_of_the_block_keeps_it` (in `cat_settings`), and `the_outfit_survives_a_save_a_load_and_a_round_trip_and_a_bad_one_is_auto` (in `settings`). To run only these three, put their names after the `--` instead of `cat_settings:: settings::`: `the_wardrobe the_whole_block_holds_the_outfit the_outfit_survives`. (In a scratch crate holding `cat_settings.rs` alone, the file's 17 tests pass, the two new ones included.)

- [ ] **Step 8: Run the whole Rust suite**

Run:

```bash
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/i-tauri 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `test result: ok.` for the app's library and the relay, no `error`, no `warning`.

- [ ] **Step 9: Type check and the whole suite**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `tsc exit 0` with no type error before it, `ℹ tests 386`, `ℹ pass 386` and `ℹ fail 0`.

- [ ] **Step 10: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/cat/display.ts windows/scripts/cat-tests/display.test.mjs windows/scripts/cat-tests/wardrobe-settings.test.mjs windows/src-tauri/src/cat_settings.rs windows/src-tauri/src/settings.rs
git commit -F - <<'MSG'
feat(wardrobe): the outfit in the cat block, TypeScript and Rust

The cat block holds the wardrobe's outfit; every clean-up of the block cleans all four parts, so a save keeps it, and a bad stored value is auto without failing the settings file.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

# Stage 2: drawing the outfits

### Task 4: The painter, the renderer's three slots and `BotEngine.outfit`

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Create: `windows/src/cat/outfitdraw.ts`
- Modify: `windows/src/cat/renderer.ts`, `windows/src/cat/engine.ts`
- Test: `windows/scripts/cat-tests/outfit-draw.test.mjs`

**Interfaces:**
- Consumes: `outfit.ts` (`outfitAnchors`, `outfitGeometry`, `outfitRoom`, `outfitEdge`, `OutfitShape`, `OutfitSlot`, `OutfitOptions`); `wardrobe.ts`; the generated theme (`THEME.outfits`).
- Produces: `outfitColor(role: string, edge: "light" | "dark"): string`; `outfitShapes(id, p, s, D, headY, ceiling, o): OutfitShape[] | null` (null for none, auto and anything that is not drawn; the hat's room comes from `ceiling` the way the ears' does); `paintOutfit(c, shapes, slot, edge): void` (one slot, in the head's frame, state saved and restored). In `renderer.ts`: `DrawOptions.outfit?: string | null` (a resolved ID; the caller decides who wears it) and `DrawOptions.outfitCeiling?: number` (the room's ceiling when it is not the ears'), `CatFrame.outfit` and `CatFrame.edge`; the three slots are drawn by `drawBehindPass` (after the ears) and `drawFrontPass` (`neck` then `top`, after the collar and before the whiskers). `BotEngine.outfit: string | null` (default null) is passed to `drawCat`.

- [ ] **Step 1: Write the test**

```bash
cat > windows/scripts/cat-tests/outfit-draw.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { drawBehindPass, drawCat, drawFrontPass, drawHeadPass, frameOf, stillView } from "../../src/cat/renderer.ts";
import { BotEngine } from "../../src/cat/engine.ts";
import { newPose } from "../../src/cat/geometry.ts";
import { outfitColor, outfitShapes, paintOutfit } from "../../src/cat/outfitdraw.ts";
import { outfitDigest, outfitGeometry } from "../../src/cat/outfit.ts";
import { OUTFIT_DRAWN, OUTFIT_IDS } from "../../src/cat/wardrobe.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { THEME } from "../../src/theme.generated.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const COL = "#8AB4F8";
const draw = (p, D, o = {}) => { const ctx = fakeCanvas(); drawCat(ctx, stillView(p, newPose()), 100, 80, D, { dpr: 2, ...o }); return ctx; };
const total = (ctx) => Object.values(ctx.calls).reduce((a, b) => a + b, 0);
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("every outfit on every coat at every size from Ø12 up draws with only finite numbers, adds drawing, and leaves the context as it found it", () => {
  for (const id of CAT_IDS) for (const D of [12, 18, 20, 27, 28, 40, 66, 96]) for (const outfit of OUTFIT_DRAWN) {
    const p = PRESETS[id], bare = draw(p, D), worn = draw(p, D, { outfit });
    assert.ok(total(worn) > total(bare), `${id} Ø${D} ${outfit}: something was added`);
    assert.equal(worn.calls.save, worn.calls.restore, `${id} Ø${D} ${outfit}: every save is restored`);
  }
});

test("none, auto, no outfit and anything that is not an outfit draw exactly what a bare cat draws", () => {
  const p = PRESETS.momo, bare = draw(p, 40);
  for (const outfit of ["none", "auto", null, undefined, "", "fancyhat", "Bow", " bow", "__proto__", 7, {}, []]) assert.deepEqual(draw(p, 40, { outfit }).calls, bare.calls, JSON.stringify(outfit));
});

test("a kitten and a mini cat's engine are bare because nothing gives them an outfit, and an engine draws the outfit it was given", () => {
  const strokes = (e, head) => { const ctx = fakeCanvas(); e.draw(ctx, head / 0.6, head / 0.6); return total(ctx); };
  const make = (outfit, p = PRESETS.momo) => { const e = new BotEngine(p, { cfg: { motion: "playful", override: {}, pers: {}, zoomAfter: 300000 }, quiet: true, now: () => 0, rand: () => 0.5, mini: true }); e.outfit = outfit; return e; };
  assert.equal(new BotEngine(PRESETS.momo, { quiet: true, now: () => 0, rand: () => 0.5 }).outfit, null, "an engine is bare until a view dresses it");
  for (const head of [13, 20, 24, 66]) {
    assert.ok(strokes(make("crown"), head) > strokes(make(null), head), `Ø${head} an engine wears what it is given`);
    assert.equal(strokes(make("none"), head), strokes(make(null), head), `Ø${head} none`);
  }
  assert.equal(strokes(make(null, kittenOf(PRESETS.momo)), 14), strokes(make(null, kittenOf(PRESETS.momo)), 14));
});

test("the outfit is drawn at the contract's three slots: bunny ears in the behind pass only, a scarf and a hat in the front pass only, the head untouched", () => {
  const view = () => stillView(PRESETS.shrimpy, newPose());
  const count = (outfit) => {
    const f = frameOf(view(), 100, 80, 66, { outfit, dpr: 2 }), behind = fakeCanvas(), head = fakeCanvas(), front = fakeCanvas();
    drawBehindPass(behind, f); drawHeadPass(head, f); drawFrontPass(front, f);
    return { behind: total(behind), head: total(head), front: total(front) };
  };
  const bare = count(null), ears = count("bunnyears"), scarf = count("scarf"), hat = count("crown");
  assert.ok(ears.behind > bare.behind && ears.front === bare.front && ears.head === bare.head, "bunny ears: behind only");
  assert.ok(scarf.front > bare.front && scarf.behind === bare.behind && scarf.head === bare.head, "scarf: front only");
  assert.ok(hat.front > bare.front && hat.behind === bare.behind && hat.head === bare.head, "crown: front only");
  const src = source("cat/renderer.ts");
  const collar = src.indexOf("if (G) drawCollar(c, G, o.collar.col, full, dpr);"), neck = src.indexOf('paintOutfit(c, f.outfit, "neck", f.edge); paintOutfit(c, f.outfit, "top", f.edge);'), whiskers = src.indexOf("// Whiskers rooted on the pad grid");
  assert.ok(collar > 0 && neck > collar && whiskers > neck, `${collar} < ${neck} < ${whiskers}: collar, outfit, whiskers`);
  const ears2 = src.indexOf("for (const ear of L.ears) drawEar(c, p, ear, R, full, flat);"), behindPaint = src.indexOf('paintOutfit(c, f.outfit, "behind", f.edge);');
  assert.ok(ears2 > 0 && behindPaint > ears2, "the behind slot is after the ears");
});

test("the coat is never recoloured, and every colour role the outfits use is in the theme", () => {
  const a = draw(PRESETS.latte, 40), b = draw(PRESETS.latte, 40, { outfit: "beanie" });
  for (const c of a.seen.fillStyles) assert.ok(b.seen.fillStyles.includes(c), `the coat's fill ${c} is still drawn`);
  const roles = new Set();
  for (const id of CAT_IDS) for (const outfit of OUTFIT_DRAWN) for (const D of [20, 66]) for (const col of [null, "tag", "band", "kerchief"]) for (const sh of outfitGeometry(outfit, PRESETS[id], newPose(), D, { dpr: 2, collar: col })) { if (sh.fill) roles.add(sh.fill); if (sh.stroke) roles.add(sh.stroke); }
  for (const r of roles) if (r !== "edge") assert.ok(Object.hasOwn(THEME.outfits, r) && /^#[0-9A-F]{6}$/i.test(THEME.outfits[r]), `${r} is a theme colour`);
  assert.equal(outfitColor("edge", "light"), THEME.outfits.edgeLight);
  assert.equal(outfitColor("edge", "dark"), THEME.outfits.edgeDark);
  assert.equal(outfitColor("gold", "dark"), THEME.outfits.gold);
  assert.equal(outfitColor("__proto__", "dark"), THEME.outfits.edgeDark, "a role the theme has not is the dark edge");
});

test("the notch gives a hat its room: with a ceiling the hat is shorter, without one it is natural, and the floor is kept", () => {
  const p = PRESETS.momo, s = newPose(), o = { dpr: 2 };
  // How far above the head's centre the highest point of the witch hat reaches (head-local px, up is smaller y), with the strip's top at `ceil` and the head at y 16.
  const reach = (ceil) => { const sh = outfitShapes("witchhat", p, s, 20, 16, ceil, o); assert.ok(sh && sh.length > 0, `drawn at ${ceil}`); return -outfitDigest(sh).bbox[1]; };
  const natural = reach(undefined), roomy = reach(-20), tight = reach(0), floor = reach(15.9);
  assert.equal(roomy, natural, "a ceiling out of reach changes nothing");
  assert.ok(tight < natural - 1, `a ceiling at the top of a 32 pt strip shortens the hat: ${tight} < ${natural}`);
  assert.ok(floor < tight && floor > 8.5, `no room at all is the floor's height, and the hat is still there: ${floor}`);
  assert.equal(outfitShapes("none", p, s, 20, 16, 0, o), null);
  assert.equal(outfitShapes("auto", p, s, 20, 16, 0, o), null);
  const compact = (ceiling) => { const ctx = fakeCanvas(); drawCat(ctx, stillView(p, newPose()), 40, 16, 20, { dpr: 2, outfit: "witchhat", earCeiling: ceiling, badgeSide: -1 }); return ctx; };
  assert.ok(total(compact(0)) > 0 && total(compact(undefined)) > 0, "the renderer passes the ears' ceiling through");
});

test("painting one slot touches only that slot, restores the state, and skips shapes of other slots", () => {
  const sh = outfitGeometry("scarf", PRESETS.momo, newPose(), 66, { dpr: 2 });
  assert.ok(sh.some((q) => q.slot === "neck"));
  const none = fakeCanvas(); paintOutfit(none, sh, "behind", "dark");
  assert.deepEqual(none.calls, {}, "no behind shape: nothing is even saved");
  const neck = fakeCanvas(); paintOutfit(neck, sh, "neck", "dark");
  assert.equal(neck.calls.save, 1); assert.equal(neck.calls.restore, 1);
  assert.equal(neck.calls.beginPath, sh.filter((q) => q.slot === "neck").length);
  assert.equal(OUTFIT_IDS.length, 18);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/outfit-draw.test.mjs 2>&1 | grep -E "^# (pass|fail)|ERR_MODULE_NOT_FOUND" | sort -u
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND` and `# fail 1`.

- [ ] **Step 3: Write the painter**

```bash
cat > windows/src/cat/outfitdraw.ts <<'EOF'
// Painting an outfit (sub-project I). outfit.ts says where the shapes go and what they are (head-local px, colour roles); this only paints them into a 2D context that is already in
// the head's own frame (the renderer's `inHead`), one slot at a time, and resolves the roles through the theme (`THEME.outfits`, shared/theme.json). It never reads a coat. Imports
// outfit.ts, wardrobe.ts and the generated theme, so the plain-Node checks (npm run check:cat) can load it.

import { TAU } from "./base.ts";
import { outfitAnchors, outfitGeometry, outfitRoom } from "./outfit.ts";
import type { OutfitOptions, OutfitShape, OutfitSlot } from "./outfit.ts";
import type { CatPreset, Pose } from "./types.ts";
import { THEME } from "../theme.generated.ts";

type Ctx = CanvasRenderingContext2D;

/** Every colour role an outfit uses, as "#RRGGBB": the keys of the theme's `outfits` group. */
const ROLES: Readonly<Record<string, string>> = THEME.outfits;

/** The colour of a role: the thin `edge` is light on a dark head and dark on a light one; a role the theme does not have is the dark edge (the tests prove there is none). */
export function outfitColor(role: string, edge: "light" | "dark"): string {
  if (role === "edge") return edge === "light" ? THEME.outfits.edgeLight : THEME.outfits.edgeDark;
  return Object.prototype.hasOwnProperty.call(ROLES, role) ? ROLES[role] : THEME.outfits.edgeDark;
}

/**
 * The shapes of the outfit one cat wears this frame, or null for none. `headY` is the head's y and `ceiling` the y of the top of the strip it sits in (the compact island passes it, as it
 * does for the ears): a hat is shortened to the room between them. Anything that is not one of the 16 drawn outfits is null.
 */
export function outfitShapes(id: unknown, p: CatPreset, s: Pose, D: number, headY: number, ceiling: number | undefined, o: OutfitOptions): OutfitShape[] | null {
  const room = ceiling === undefined ? null : outfitRoom(outfitAnchors(p, s, D, o), headY, ceiling);
  const shapes = outfitGeometry(id, p, s, D, { ...o, room });
  return shapes.length ? shapes : null;
}

/** Paints the shapes of one slot, in order. The context is in the head's frame; its state is saved and restored. */
export function paintOutfit(c: Ctx, shapes: readonly OutfitShape[], slot: OutfitSlot, edge: "light" | "dark"): void {
  if (!shapes.some((sh) => sh.slot === slot)) return;
  c.save();
  c.lineCap = "round";
  c.lineJoin = "round";
  for (const sh of shapes) {
    if (sh.slot !== slot) continue;
    c.globalAlpha = sh.a;
    c.beginPath();
    if (sh.k === "ellipse") c.ellipse(sh.x, sh.y, sh.rx, sh.ry, sh.rot, 0, TAU);
    else {
      sh.pts.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y)));
      if (sh.k === "poly") c.closePath();
    }
    if (sh.k !== "curve" && sh.fill) {
      c.fillStyle = outfitColor(sh.fill, edge);
      c.fill();
    }
    if (sh.stroke && sh.sw > 0) {
      c.strokeStyle = outfitColor(sh.stroke, edge);
      c.lineWidth = sh.sw;
      c.stroke();
    }
  }
  c.restore();
}
EOF
```

- [ ] **Step 4: Call it from the renderer and the engine**

The renderer works out the ear scale it drew the ears with (`ek`) and gives it to the outfit, because the contract's anchors follow the ears; `HEX6` (already in the file) decides whether the collar is really drawn, so a bell hangs from a collar that is there and from its own ring when it is not.

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

r = "windows/src/cat/renderer.ts"
edit(r, '''import { smallEye } from "./smalleye.ts";
import type { SmallEye } from "./smalleye.ts";
''', '''import { smallEye } from "./smalleye.ts";
import type { SmallEye } from "./smalleye.ts";
import { outfitEdge } from "./outfit.ts";
import type { OutfitShape } from "./outfit.ts";
import { outfitShapes, paintOutfit } from "./outfitdraw.ts";
''')
edit(r, '''  /** `ink` draws the compact cat's plain resting eyes''', '''  /**
   * The outfit this cat wears (sub-project I): one of the 16 drawn outfit IDs, already resolved (never `auto`; `none`, null and anything else draw nothing). The caller decides who
   * wears it by the cat's role (outfitWorn): only a big cat gets one here. It is drawn at the contract's three slots, from `outfitGeometry`, and needs `earCeiling` for the compact island's room.
   */
  outfit?: string | null;
  /** `ink` draws the compact cat's plain resting eyes''')
edit(r, '''  /** The compact cat's flat colours (flatFillColors), or null for the full cat: `detailLevel(D, detail).flatFill`, that is `!L.full`. */
  flat: FlatColors | null;
}''', '''  /** The compact cat's flat colours (flatFillColors), or null for the full cat: `detailLevel(D, detail).flatFill`, that is `!L.full`. */
  flat: FlatColors | null;
  /** The shapes of the outfit it wears this frame (outfit.ts), or null when it is bare; `edge` is the thin edge's colour on this coat. */
  outfit: OutfitShape[] | null;
  edge: "light" | "dark";
}''')
edit(r, '''  let L = layout(p, s, cx, cy, D, { ...opts, earScale: k0 });''', '''  let ek = k0;
  let L = layout(p, s, cx, cy, D, { ...opts, earScale: ek });''')
edit(r, '''    if (f < 1) L = layout(p, s, cx, cy, D, { ...opts, earScale: k0 * f });''', '''    if (f < 1) { ek = k0 * f; L = layout(p, s, cx, cy, D, { ...opts, earScale: ek }); }''')
edit(r, '''  return { e, p, s, L, o, T, D, fur, flat };
}''', '''  // The outfit, if this cat wears one: its shapes for this pose, with the room above the crown that the compact island's strip leaves a hat (the ears' ceiling).
  const outfit = o.outfit ? outfitShapes(o.outfit, p, s, D, L.head.y, o.earCeiling, { dpr: dprOf(o), detail: o.detail, earScale: ek, collar: o.collar && HEX6.test(o.collar.col) ? o.collar.style : undefined }) : null;
  return { e, p, s, L, o, T, D, fur, flat, outfit, edge: outfit ? outfitEdge(p) : "dark" };
}''')
edit(r, '''    for (const ear of L.ears) drawEar(c, p, ear, R, full, flat);
  });
}''', '''    for (const ear of L.ears) drawEar(c, p, ear, R, full, flat);
    if (f.outfit) paintOutfit(c, f.outfit, "behind", f.edge); // bunny ears: the head covers their roots
  });
}''')
edit(r, '''      if (G) drawCollar(c, G, o.collar.col, full, dpr);
    }
''', '''      if (G) drawCollar(c, G, o.collar.col, full, dpr);
    }
    // The outfit (sub-project I): the neck slot over the collar, then the top slot, both under the whiskers, the badge and the particles.
    if (f.outfit) { paintOutfit(c, f.outfit, "neck", f.edge); paintOutfit(c, f.outfit, "top", f.edge); }
''')

e = "windows/src/cat/engine.ts"
edit(e, '''  collarColor: string | null = null;
''', '''  collarColor: string | null = null;
  /**
   * The outfit this cat wears (sub-project I): a resolved ID (never `auto`) or null for none. Only the views that show a big cat set it (the island's main cat, cat 2 in Two cats mode,
   * the desktop cat); a mini cat, a kitten and every other engine keep null and stay bare, whatever their size.
   */
  outfit: string | null = null;
''')
edit(e, '''      collar: this.collarColor ? { style: this.collarStyle, col: this.collarColor } : null });''', '''      collar: this.collarColor ? { style: this.collarStyle, col: this.collarColor } : null, outfit: this.outfit });''')
EOF
```

- [ ] **Step 5: Run the test to see it pass**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
node --experimental-strip-types --test scripts/cat-tests/outfit-draw.test.mjs 2>&1 | grep -E "^# (pass|fail)"
cd ..
```

Expected: `tsc exit 0` and `# pass 7`, `# fail 0`.

- [ ] **Step 6: Prove it bites**

Run (without the `neck` call a scarf, a bandana and a bell are never drawn):

```bash
cd windows
python3 ../.claude/checkpoints/i-tauri/mut.py src/cat/renderer.ts 'paintOutfit(c, f.outfit, "neck", f.edge); paintOutfit(c, f.outfit, "top", f.edge);' 'paintOutfit(c, f.outfit, "top", f.edge);' scripts/cat-tests/outfit-draw.test.mjs
cd ..
```

Expected: `renderer.ts | paintOutfit(c, f.outfit, "top", f.edge); | # pass 5 # fail 2`.

- [ ] **Step 7: The whole suite**

Run:

```bash
cd windows
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `ℹ tests 393`, `ℹ pass 393` and `ℹ fail 0` (the older collar, ear-fit, renderer and engine tests are unchanged and still pass: a cat with no outfit draws what it drew).

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/cat/outfitdraw.ts windows/src/cat/renderer.ts windows/src/cat/engine.ts windows/scripts/cat-tests/outfit-draw.test.mjs
git commit -F - <<'MSG'
feat(wardrobe): paint the outfits at the contract's three slots

outfitdraw.ts resolves the colour roles through the theme and paints one slot; the renderer draws bunny ears after the ears and the neck and top slots after the collar, under the whiskers; BotEngine.outfit is passed to drawCat and is null until a big-cat view sets it.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

### Task 5: The `?dev` Wardrobe panel

**Agent:** `nm-implementer` (Haiku 5.5, high); it runs a browser, so it also loads `playwright-cli`.

**Files:**
- Create: `windows/src/cat/devwardrobe.ts`
- Modify: `windows/src/cat/dev.ts`
- Test: `windows/scripts/cat-tests/wardrobe-dev.test.mjs`

**Interfaces:**
- Consumes: `renderer.ts` (`drawCat`, `stillView` with `outfit`), `outfit.ts` (`outfitGeometry`, `outfitDigest`), `wardrobe.ts`, `presets.ts`.
- Produces: `mountWardrobeDev(root: HTMLElement, before: HTMLElement): void`: a "Wardrobe" section with the canvases `#wardrobe-sheet` (16 outfits on 16 coats at Ø40, the head facing or turned), `#wardrobe-notch` (Ø20 in the 32 pt strip and Ø18 in the 24 pt strip, magnified 2 times), `#wardrobe-turned` (a full yaw each way), `#wardrobe-neck` (the bell, bandana and scarf over each collar style), `#wardrobe-extra` (the desktop sizes and a Two cats pair), the text `#wardrobe-fits` and `#wardrobe-auto` (Auto for any date). It draws stills when a control changes: no timer and no loop.

- [ ] **Step 1: Write the test**

```bash
cat > windows/scripts/cat-tests/wardrobe-dev.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The ?dev page's Wardrobe panel (sub-project I): the contact sheet is pinned by source (it needs a browser; the headless pictures are the plan's Checkpoint 1) and it runs nothing of its own.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("dev.ts mounts the Wardrobe panel after the Desktop cat's, and the panel is built from the app's renderer and the contract's rules", () => {
  const dev = source("cat/dev.ts"), w = source("cat/devwardrobe.ts");
  assert.match(dev, /import \{ mountWardrobeDev \} from "\.\/devwardrobe\.ts";/);
  assert.match(dev, /mountDesktopDev\(root, wrap, ticks\);\s*\/\/[^\n]*\n\s*mountWardrobeDev\(root, wrap\);/);
  assert.match(w, /import \{ drawCat, stillView \} from "\.\/renderer\.ts";/);
  assert.match(w, /OUTFIT_DRAWN\.forEach/);
  for (const s of ["wardrobe-sheet", "wardrobe-notch", "wardrobe-turned", "wardrobe-neck", "wardrobe-extra", "wardrobe-fits", "wardrobe-auto"]) assert.ok(w.includes(`"${s}"`) || w.includes(`${s}`), s);
  assert.match(w, /const STRIPS: readonly \(readonly \[number, number\]\)\[\] = \[\[20, 32\], \[18, 24\]\];/, "the compact notch's two strips: Ø20 in 32 pt and Ø18 in 24 pt");
});

test("the panel draws stills when a control changes: no timer, no frame callback, no loop", () => {
  const w = source("cat/devwardrobe.ts");
  assert.doesNotMatch(w, /requestAnimationFrame|setInterval|setTimeout|ticks/);
});

test("the release build does not contain the panel: only dev.ts imports it, and dev.ts is loaded behind import.meta.env.DEV", () => {
  assert.match(source("main.ts"), /import\.meta\.env\.DEV/);
  for (const rel of ["main.ts", "island/island.ts", "settings/main.ts", "desktop/main.ts"]) assert.ok(!/devwardrobe/.test(source(rel)), `${rel} does not import it`);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe-dev.test.mjs 2>&1 | grep -E "^# (pass|fail)"
cd ..
```

Expected: `# fail 2` and `# pass 1` (the third test, that no release file imports the panel, holds already).

- [ ] **Step 3: Write the panel**

```bash
cat > windows/src/cat/devwardrobe.ts <<'EOF'
// The `?dev` page's "Wardrobe" panel (sub-project I): the contact sheet of all 16 outfits on all 16 coats, the compact notch's Ø20 and Ø18 big cat in their strips, the head turned a full yaw
// each way, the three neck outfits over each collar style, the desktop sizes, a Two cats pair, and Auto for any date. Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window
// needed) and compare it with the Wardrobe panel of design/prototype/notchmeow.html, which is the look. The cats are stills drawn when a control changes: the panel runs no timer and no
// frame loop. Only the dev server serves it: main.ts loads dev.ts behind `import.meta.env.DEV`, so a release build does not contain it.

import { newPose } from "./geometry.ts";
import { outfitDigest, outfitGeometry } from "./outfit.ts";
import { drawCat, stillView } from "./renderer.ts";
import { CAT_IDS, PRESETS } from "./presets.ts";
import { OUTFIT_DRAWN, OUTFIT_NAMES, resolveOutfit } from "./wardrobe.ts";
import type { OutfitId } from "./wardrobe.ts";
import { AGENT_PILL_COLORS } from "../core/pills.ts";
import { THEME } from "../theme.generated.ts";

const FONT = "system-ui,-apple-system,'Segoe UI',sans-serif";
const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;
const COLLAR_COLOR = AGENT_PILL_COLORS.agent_gemini;
const CELL = 64, LEFT = 74, TOP = 34, STRIP_SCALE = 2;
/** The compact notch's strips: [head width, strip height in pt]. A 32 pt strip for the Ø20 cat, a 24 pt strip for the Ø18 one on a screen without a notch. */
const STRIPS: readonly (readonly [number, number])[] = [[20, 32], [18, 24]];

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
  s.id = "wardrobe-dev";
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
function scroller(cv: HTMLCanvasElement, label: string): HTMLElement {
  const w = document.createElement("div");
  w.style.cssText = "overflow-x:auto;margin-top:12px;padding-bottom:4px";
  cv.setAttribute("aria-label", label); cv.style.display = "block";
  w.append(cv);
  return w;
}
const caption = (c: CanvasRenderingContext2D, text: string, x: number, y: number, align: CanvasTextAlign = "center") => {
  c.fillStyle = B.dim; c.font = `10px ${FONT}`; c.textAlign = align; c.textBaseline = "alphabetic"; c.fillText(text, x, y);
};

/** Puts the "Wardrobe" panel into the `?dev` page before `before`. */
export function mountWardrobeDev(root: HTMLElement, before: HTMLElement): void {
  const st = { coat: "momo", turned: false, collar: "off", outfit: "witchhat" as OutfitId, date: "2025-12-24" };
  const box = section("Wardrobe", "16 outfits on 16 coats, drawn by the app's renderer from the contract's shapes (outfit.ts), to compare with the Wardrobe panel of the prototype page. Hats are as wide as the gap between the ears; the thin edge of an outfit is light on a dark coat and dark on a light one.");
  const sheet = document.createElement("canvas"), notch = document.createElement("canvas"), turned = document.createElement("canvas"), neck = document.createElement("canvas"), extra = document.createElement("canvas");
  sheet.id = "wardrobe-sheet"; notch.id = "wardrobe-notch"; turned.id = "wardrobe-turned"; neck.id = "wardrobe-neck"; extra.id = "wardrobe-extra";
  const fits = document.createElement("p");
  fits.id = "wardrobe-fits"; fits.style.cssText = `color:${B.ink};font-size:12px;margin:10px 0 0`;
  const autoOut = document.createElement("p");
  autoOut.id = "wardrobe-auto"; autoOut.style.cssText = `color:${B.ink};font-size:12px;margin:6px 0 0`;
  const date = document.createElement("input");
  date.type = "date"; date.value = st.date; date.setAttribute("aria-label", "Date for Auto"); date.style.cssText = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:3px 8px`;

  const view = (id: string, yaw = 0) => stillView(PRESETS[id], { ...newPose(), yaw, pitch: yaw ? 0.15 : 0 });
  const collar = () => (st.collar === "off" ? null : { style: st.collar, col: COLLAR_COLOR });
  const cellBg = (c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) => { c.fillStyle = "#101114"; c.beginPath(); c.roundRect(x, y, w, h, 8); c.fill(); };

  function drawSheet() {
    const c = fit(sheet, LEFT + CELL * 16, TOP + CELL * 16);
    OUTFIT_DRAWN.forEach((id, i) => OUTFIT_NAMES[id].split(" ").forEach((word, k) => caption(c, word, LEFT + CELL * i + CELL / 2, 14 + k * 10)));
    CAT_IDS.forEach((cat, r) => {
      c.fillStyle = B.ink; c.font = `600 11px ${FONT}`; c.textAlign = "left"; c.textBaseline = "middle"; c.fillText(PRESETS[cat].label, 6, TOP + CELL * r + CELL / 2);
      const v = view(cat, st.turned ? 0.6 : 0);
      OUTFIT_DRAWN.forEach((id, i) => {
        const x = LEFT + CELL * i, y = TOP + CELL * r;
        cellBg(c, x + 2, y + 2, CELL - 4, CELL - 4);
        drawCat(c, v, x + CELL / 2, y + CELL / 2 + 6, 40, { tint: false, badge: false, outfit: id, collar: collar() });
      });
    });
  }

  function drawNotch() {
    const W = 56, per = W * STRIP_SCALE + 6, rowH = 32 * STRIP_SCALE + 18;
    const c = fit(notch, per * 16, rowH * STRIPS.length);
    STRIPS.forEach(([D, h], r) => {
      OUTFIT_DRAWN.forEach((id, i) => {
        const x = i * per, y = r * rowH;
        c.save(); c.translate(x, y + 10); c.scale(STRIP_SCALE, STRIP_SCALE);
        c.fillStyle = "#000"; c.beginPath(); c.roundRect(0, 0, W, h, [0, 0, 8, 8]); c.fill();
        drawCat(c, view(st.coat), W / 2, h / 2, D, { badgeSide: -1, badge: false, earCeiling: 0, outfit: id });
        c.restore();
        if (r === 0) caption(c, OUTFIT_NAMES[id], x + (W * STRIP_SCALE) / 2, y + 8);
      });
      caption(c, `Ø${D} in the ${h} pt strip, magnified ${STRIP_SCALE} times`, 4, r * rowH + rowH - 2, "left");
    });
  }

  function drawTurned() {
    const c = fit(turned, CELL * 1.5 * 16, CELL * 1.5 * 2 + 18);
    [-0.6, 0.6].forEach((yaw, r) => OUTFIT_DRAWN.forEach((id, i) => {
      const x = CELL * 1.5 * i, y = r * CELL * 1.5;
      cellBg(c, x + 2, y + 2, CELL * 1.5 - 4, CELL * 1.5 - 4);
      drawCat(c, view(st.coat, yaw), x + CELL * 0.75, y + CELL * 0.8, 52, { tint: false, badge: false, outfit: id, collar: collar() });
    }));
    caption(c, "The head turned a full yaw to the left (top row) and to the right (bottom row)", 4, CELL * 3 + 14, "left");
  }

  function drawNeck() {
    const ids: OutfitId[] = ["bell", "bandana", "scarf"], styles = ["off", "tag", "band", "kerchief"], cw = CELL * 1.5;
    const c = fit(neck, cw * styles.length * ids.length, cw + 18);
    ids.forEach((id, a) => styles.forEach((style, b) => {
      const x = cw * (a * styles.length + b);
      cellBg(c, x + 2, 2, cw - 4, cw - 4);
      drawCat(c, view(st.coat), x + cw / 2, cw * 0.55, 52, { tint: false, badge: false, outfit: id, collar: style === "off" ? null : { style, col: COLLAR_COLOR } });
      caption(c, `${OUTFIT_NAMES[id]} · collar ${style}`, x + cw / 2, cw + 12);
    }));
  }

  function drawExtra() {
    const c = fit(extra, 720, 190);
    // The desktop cat's three sizes, then a Two cats pair in the compact strip (cat 1 the chosen coat, cat 2 the next one), all wearing the chosen outfit.
    [[48, 70], [64, 170], [96, 290]].forEach(([D, x]) => {
      cellBg(c, x - 56, 4, 112, 112);
      drawCat(c, view(st.coat), x, 64, D * 0.9, { tint: false, badge: false, outfit: st.outfit, collar: collar() });
      caption(c, `desktop Ø${D}`, x, 130);
    });
    const next = CAT_IDS[(CAT_IDS.indexOf(st.coat) + 1) % CAT_IDS.length];
    c.save(); c.translate(380, 20); c.scale(STRIP_SCALE, STRIP_SCALE);
    c.fillStyle = "#000"; c.beginPath(); c.roundRect(0, 0, 144, 32, [0, 0, 12, 12]); c.fill();
    drawCat(c, view(st.coat), 36, 16, 20, { badgeSide: -1, badge: false, earCeiling: 0, outfit: st.outfit });
    drawCat(c, view(next), 108, 16, 20, { badgeSide: -1, badge: false, earCeiling: 0, outfit: st.outfit });
    c.restore();
    caption(c, "Two cats, compact", 524, 110);
  }

  function checkFits() {
    let pairs = 0, bad = 0;
    for (const [D] of STRIPS) for (const cat of CAT_IDS) for (const id of OUTFIT_DRAWN) {
      pairs++;
      const box = outfitDigest(outfitGeometry(id, PRESETS[cat], newPose(), D, { dpr: Math.min(2, devicePixelRatio || 1) })).bbox;
      if (!box.every(Number.isFinite)) bad++;
    }
    fits.textContent = `${pairs} outfit and coat pairs worked out for the compact strips (Ø20 in 32 pt, Ø18 in 24 pt): ${bad === 0 ? "all have shapes with finite numbers" : `${bad} are broken`}. The contract's tests check that none rises above the strip.`;
  }

  function showAuto() {
    const [y, m, d] = date.value.split("-").map(Number);
    const out = resolveOutfit("auto", y, m, d);
    autoOut.textContent = `Auto on ${date.value || "(no date)"}: ${out === "none" ? "no outfit" : OUTFIT_NAMES[out]}`;
  }

  const redraw = () => { drawSheet(); drawNotch(); drawTurned(); drawNeck(); drawExtra(); showAuto(); };
  date.onchange = () => { showAuto(); };
  box.append(
    choice("Coat", CAT_IDS.map((c) => [c, PRESETS[c].label] as const), () => st.coat, (v) => { st.coat = v; redraw(); }),
    choice("Head", [[false, "Facing"], [true, "Turned (the sheet)"]] as const, () => st.turned, (v) => { st.turned = v; redraw(); }),
    choice("Collar", ([["off", "Off"], ["tag", "Band and tag"], ["band", "Band"], ["kerchief", "Neckerchief"]] as const), () => st.collar, (v) => { st.collar = v; redraw(); }),
    choice("Outfit", OUTFIT_DRAWN.map((id) => [id, OUTFIT_NAMES[id]] as const), () => st.outfit, (v) => { st.outfit = v; redraw(); }),
    scroller(sheet, "Every outfit on every coat"),
    scroller(notch, "Every outfit on the compact notch's big cat"),
    scroller(turned, "Every outfit with the head turned each way"),
    scroller(neck, "The bell, bandana and scarf over each collar style"),
    scroller(extra, "The chosen outfit at the desktop sizes and on a Two cats pair"),
    fits,
  );
  const ar = row("Auto");
  ar.append(date);
  box.append(ar, autoOut);
  root.insertBefore(box, before);
  redraw();
  checkFits();
}
EOF
```

Then `dev.ts` mounts it after the Desktop cat's panel:

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

d = "windows/src/cat/dev.ts"
edit(d, '''import { mountDesktopDev } from "./devdesktop.ts";
''', '''import { mountDesktopDev } from "./devdesktop.ts";
import { mountWardrobeDev } from "./devwardrobe.ts";
''')
edit(d, '''  mountDesktopDev(root, wrap, ticks);
''', '''  mountDesktopDev(root, wrap, ticks);
  // ── Sub-project I: the wardrobe ──
  mountWardrobeDev(root, wrap);
''')
EOF
```

- [ ] **Step 4: Run the test and the type check**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
node --experimental-strip-types --test scripts/cat-tests/wardrobe-dev.test.mjs 2>&1 | grep -E "^# (pass|fail)"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `tsc exit 0`, `# pass 3`, `# fail 0`, then `ℹ tests 396`, `ℹ pass 396` and `ℹ fail 0`.

- [ ] **Step 5: Look at it, and at the prototype's panel next to it**

Start the dev server with the block under "How to run this plan" (port 14613), and a second Vite for the prototype page (a browser opened with `playwright-cli` refuses `file:` URLs):

```bash
cd windows
(npx --no-install vite ../design/prototype --port 14614 --strictPort --host 127.0.0.1 > ../.claude/checkpoints/i-tauri/vite-proto.log 2>&1 & echo $! > ../.claude/checkpoints/i-tauri/vite-proto.pid)
sleep 3
cd ..
tail -2 .claude/checkpoints/i-tauri/vite-proto.log
```

Expected: `http://127.0.0.1:14614/`. Then take the pictures (a wide window, so the 16 columns fit):

```bash
cd .claude/checkpoints/i-tauri
playwright-cli -s=iwd open "http://127.0.0.1:14613/?dev"
playwright-cli -s=iwd resize 1900 1200
playwright-cli -s=iwd eval "document.querySelector('#wardrobe-fits').textContent"
for id in sheet notch turned neck extra; do playwright-cli -s=iwd screenshot "#wardrobe-$id" --filename=dev-$id.png; done
playwright-cli -s=iwp open "http://127.0.0.1:14614/notchmeow.html"
playwright-cli -s=iwp resize 1900 1200
for id in wdSheet wdCompact3 wdTurn wdCollars; do playwright-cli -s=iwp screenshot "#$id" --filename=proto-$id.png; done
cd ../../..
ls .claude/checkpoints/i-tauri/*.png
```

Expected: the `eval` prints `512 outfit and coat pairs worked out for the compact strips (Ø20 in 32 pt, Ø18 in 24 pt): all have shapes with finite numbers.` followed by the sentence about the contract's tests, and nine PNG files are there. Open each picture and say what you see: **every one of the 16 columns is a different outfit on every coat; hats stand between the ears and none is wider than the gap (the witch hat's brim the widest); the sunglasses cover the eyes and the round glasses leave them showing; a dark coat (Midnight, Oreo, Mocha) shows a light edge round its sunglasses' lenses; the scarf, the bandana and the bell are at the neck; the clips sit at an ear base; no outfit hides the whiskers; at Ø20 and Ø18 every hat is still there above the head and nothing is cut off at the strip's top; the head turned left and right keeps glasses on the eyes and hats on the crown.** Compare each `dev-*.png` with its prototype twin: the shapes and colours are the same (the prototype draws its cats from its idle engines and the panel from still poses, so a whisker or a blink may differ).

Stop the servers by their saved PIDs and close the two sessions:

```bash
kill "$(cat .claude/checkpoints/i-tauri/vite.pid)"; kill "$(cat .claude/checkpoints/i-tauri/vite-proto.pid)"
playwright-cli -s=iwd close; playwright-cli -s=iwp close
```

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/cat/devwardrobe.ts windows/src/cat/dev.ts windows/scripts/cat-tests/wardrobe-dev.test.mjs
git commit -F - <<'MSG'
feat(wardrobe): the ?dev Wardrobe panel

The contact sheet of 16 outfits on 16 coats, the compact notch's Ø20 and Ø18 big cat in their strips, the head turned each way, the neck outfits over each collar style, the desktop sizes, a Two cats pair and Auto for any date, drawn by the app's renderer as stills.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

## Checkpoint 1: the owner looks at the sheet

Stop here. Send the owner the paths of the nine pictures in `.claude/checkpoints/i-tauri/` (`dev-sheet.png`, `dev-notch.png`, `dev-turned.png`, `dev-neck.png`, `dev-extra.png`, and the prototype's `proto-wdSheet.png`, `proto-wdCompact3.png`, `proto-wdTurn.png`, `proto-wdCollars.png`), the counts so far (`ℹ tests 396`), and this list, and wait:

1. **Does the app's sheet show what the prototype's does?** (The shapes and the colours are the contract's: if the owner wants a shape or a colour changed, that is a change to `cat-core.js` and `shared/theme.json` by the main session, the fixtures are regenerated, and this branch merges it before Task 6. Do not change anything here.)
2. **Do all 16 outfits read at Ø20 and Ø18 in the strips?** (The contract may be asked for a simpler drawing at that size.)
3. **Are there coats where an outfit vanishes?** (The thin edge switches by the coat's luminance: say which pairs look wrong.)
4. **The head turned and the neck outfits over each collar style: are they right?**

Do not start Task 6 before the owner's reply.

# Stage 3: who wears it, and when

### Task 6: Auto's one-shot and `State.outfit`

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `windows/src/island/wardrobe.ts`
- Modify: `windows/src/core/state.ts`, `windows/src/island/island.ts`
- Test: `windows/scripts/cat-tests/wardrobe-clock.test.mjs`

**Interfaces:**
- Consumes: `wardrobe.ts` (`outfitIdOf`, `resolveOutfit`, `OutfitId`); `State.settings.cat.outfit` (Task 3).
- Produces: `msToNextMidnight(now: Date): number`; `interface WardrobeEnv { now(): Date; choice(): unknown; set(fn, ms): number; clear(id): void; apply(outfit: OutfitId): void }`; `class WardrobeClock { constructor(env); get outfit(): OutfitId | null; sync(): void }` (`sync` resolves the stored choice for today, calls `apply` only when the outfit changed, and keeps exactly one midnight timer while the choice is `auto`, none otherwise); `State.outfit: OutfitId` (`"none"` before the first sync): the outfit the big cats wear now, never `auto`. `Island.applySettings` calls `sync`, so a launch, the Settings window's save and the tray's changes all resolve it again.

- [ ] **Step 1: Write the test**

```bash
cat > windows/scripts/cat-tests/wardrobe-clock.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { State } from "../../src/core/state.ts";
import { WardrobeClock, msToNextMidnight } from "../../src/island/wardrobe.ts";

// Auto's one-shot (sub-project I): one timer, only while the stored choice is auto, re-resolved at the next local midnight and after a long sleep, never polled.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const HOUR = 3_600_000;

/** A local clock and a timer queue the test turns by hand, and an island that records what it is told. */
function world(choice, start) {
  const w = { t: start.getTime(), choice, timers: new Map(), id: 1, sets: 0, clears: 0, applied: [] };
  const env = {
    now: () => new Date(w.t), choice: () => w.choice,
    set: (fn, ms) => { const id = w.id++; w.sets++; w.timers.set(id, { fn, at: w.t + ms }); return id; },
    clear: (id) => { w.clears++; w.timers.delete(id); },
    apply: (o) => w.applied.push(o),
  };
  w.advance = (ms) => {
    const end = w.t + ms;
    for (;;) {
      const due = [...w.timers.entries()].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      w.t = due[1].at; w.timers.delete(due[0]); due[1].fn();
    }
    w.t = end;
  };
  return { w, clock: new WardrobeClock(env) };
}

test("the next local midnight is counted by the calendar: 0:00 of the next date, never under a second away", () => {
  for (const d of [new Date(2025, 5, 1, 12, 0, 0), new Date(2025, 11, 31, 23, 59, 59, 500), new Date(2024, 1, 29, 0, 0, 0, 0), new Date(2025, 0, 1, 0, 0, 0, 1)]) {
    const at = new Date(d.getTime() + msToNextMidnight(d));
    assert.deepEqual([at.getHours(), at.getMinutes(), at.getSeconds()], [0, 0, 0], d.toString());
    assert.ok(msToNextMidnight(d) >= 1000);
  }
  assert.equal(msToNextMidnight(new Date(2025, 5, 1, 12, 0, 0)), 12 * HOUR);
  assert.equal(msToNextMidnight(new Date(2025, 5, 1, 23, 59, 59, 999)), 1000, "a timer that fires a moment early cannot spin");
  assert.equal(msToNextMidnight(new Date(NaN)), HOUR, "a bad clock is an hour, not NaN");
});

test("a day with a daylight-saving change is 23 or 25 hours long, and the timer follows the calendar", () => {
  const old = process.env.TZ;
  try {
    process.env.TZ = "America/New_York";
    assert.equal(msToNextMidnight(new Date(2025, 2, 9, 0, 0, 0)), 23 * HOUR, "spring forward");
    assert.equal(msToNextMidnight(new Date(2025, 10, 2, 0, 0, 0)), 25 * HOUR, "fall back");
    assert.equal(msToNextMidnight(new Date(2025, 2, 9, 12, 0, 0)), 12 * HOUR, "after the change the rest of the day is as long as it reads");
    assert.equal(msToNextMidnight(new Date(2025, 2, 9, 0, 30, 0)), 23 * HOUR - 30 * 60_000, "before it, an hour is missing");
    process.env.TZ = "Pacific/Auckland";
    const d = new Date(2025, 8, 28, 1, 0, 0), at = new Date(d.getTime() + msToNextMidnight(d));
    assert.deepEqual([at.getDate(), at.getHours()], [29, 0]);
  } finally { if (old === undefined) delete process.env.TZ; else process.env.TZ = old; }
});

test("auto: the outfit for today is applied once, one timer is armed, and it fires at midnight and applies the next day's outfit", () => {
  const { w, clock } = world("auto", new Date(2025, 11, 25, 12, 0, 0));
  clock.sync();
  assert.deepEqual(w.applied, ["santahat"]);
  assert.equal(w.timers.size, 1, "one timer");
  w.advance(14 * HOUR); // 02:00 on Dec 26: still Santa
  assert.deepEqual(w.applied, ["santahat"], "the same outfit is not applied twice");
  assert.equal(w.timers.size, 1, "re-armed for the next midnight");
  w.advance(24 * HOUR); // 02:00 on Dec 27
  assert.deepEqual(w.applied, ["santahat", "none"]);
  assert.equal(clock.outfit, "none");
  assert.equal(w.timers.size, 1);
});

test("the new year's midnight, an Easter weekend and a launch on a day with no outfit", () => {
  const nye = world("auto", new Date(2025, 11, 31, 23, 0, 0));
  nye.clock.sync();
  assert.deepEqual(nye.w.applied, ["partyhat"]);
  nye.w.advance(2 * HOUR);
  assert.deepEqual(nye.w.applied, ["partyhat"], "Jan 1 is still the party hat");
  const easter = world("auto", new Date(2025, 3, 17, 12, 0, 0)); // Maundy Thursday: Easter is Apr 20, Good Friday Apr 18
  easter.clock.sync();
  assert.deepEqual(easter.w.applied, ["none"]);
  easter.w.advance(13 * HOUR);
  assert.deepEqual(easter.w.applied, ["none", "bunnyears"]);
  const plain = world("auto", new Date(2025, 4, 5, 9, 0, 0));
  plain.clock.sync();
  assert.deepEqual(plain.w.applied, ["none"], "none is applied at launch too, so the island knows");
});

test("a timer that fires late, after a long sleep, recomputes from the date then", () => {
  const { w, clock } = world("auto", new Date(2025, 5, 10, 22, 0, 0));
  clock.sync();
  assert.deepEqual(w.applied, ["none"]);
  w.advance(20 * 24 * HOUR); // the computer slept for 20 days: it is Jun 30 now
  assert.deepEqual(w.applied, ["none", "sunglasses"]);
  assert.equal(w.timers.size, 1);
});

test("an explicit outfit or none needs no timer: choosing one cancels it, choosing auto again arms it, and nothing is ever polled", () => {
  const { w, clock } = world("auto", new Date(2025, 11, 25, 12, 0, 0));
  clock.sync();
  assert.equal(w.timers.size, 1);
  w.choice = "crown"; clock.sync();
  assert.equal(w.timers.size, 0, "an explicit outfit: no timer");
  assert.deepEqual(w.applied, ["santahat", "crown"]);
  w.advance(10 * 24 * HOUR);
  assert.deepEqual(w.applied, ["santahat", "crown"], "nothing fires");
  w.choice = "none"; clock.sync();
  assert.equal(w.timers.size, 0);
  assert.deepEqual(w.applied.slice(-1), ["none"]);
  w.choice = "auto"; clock.sync();
  assert.equal(w.timers.size, 1);
  const sets = w.sets;
  w.choice = "auto"; clock.sync(); clock.sync();
  assert.equal(w.timers.size, 1, "a sync never leaves two timers");
  assert.equal(w.sets, sets + 2);
});

test("a stored value that is not an outfit is auto, and a bad clock never throws", () => {
  for (const bad of [undefined, null, 7, "Crown", "", {}, ["bow"]]) {
    const { w, clock } = world(bad, new Date(2025, 11, 25, 12, 0, 0));
    clock.sync();
    assert.deepEqual(w.applied, ["santahat"], String(bad));
    assert.equal(w.timers.size, 1);
  }
  const { w, clock } = world("auto", new Date(NaN));
  assert.doesNotThrow(() => clock.sync());
  assert.deepEqual(w.applied, ["none"]);
});

test("the island keeps it in State after each sync, wears nothing before the first one, and the clock is built once with real timers", () => {
  assert.equal(State.outfit, "none");
  const island = source("island/island.ts"), state = source("core/state.ts");
  assert.match(island, /private wardrobe = new WardrobeClock\(\{\s*now: \(\) => new Date\(\),\s*choice: \(\) => State\.settings\.cat\.outfit,\s*set: \(fn, ms\) => window\.setTimeout\(fn, ms\),\s*clear: \(id\) => window\.clearTimeout\(id\),\s*apply: \(outfit\) => \{ State\.outfit = outfit; State\.notify\(\); \},\s*\}\);/);
  assert.match(island, /State\.settings\.cat = block;\s*this\.wardrobe\.sync\(\);\s*State\.notify\(\);/);
  assert.match(state, /outfit: OutfitId = "none";/);
  assert.equal((island.match(/new WardrobeClock\(/g) || []).length, 1);
  assert.ok(!/setInterval/.test(source("island/wardrobe.ts")), "nothing polls");
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe-clock.test.mjs 2>&1 | grep -E "^# (pass|fail)|ERR_MODULE_NOT_FOUND" | sort -u
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND` and `# fail 1`.

- [ ] **Step 3: Write the clock**

```bash
cat > windows/src/island/wardrobe.ts <<'EOF'
// Auto's one-shot (sub-project I, spec "Auto rules"): the outfit the big cats wear is the stored choice resolved for today (`resolveOutfit`, cat/wardrobe.ts, the contract's rules), and while the
// choice is `auto` it is looked at again at the next local midnight with ONE timer, never a poll. The timer exists only while the stored value is `auto`: an explicit outfit or `none` cancels it.
// A timer that fires late (the computer was asleep) recomputes from the date then. Pure: the clock, the timer and the island are injected, so the plain-Node checks can turn time by hand.

import { outfitIdOf, resolveOutfit } from "../cat/wardrobe.ts";
import type { OutfitId } from "../cat/wardrobe.ts";

/** Milliseconds from `now` to the next local midnight, by the calendar (a day with a daylight-saving change is 23 or 25 hours long), and never under a second, so a timer that fires a moment early cannot spin. */
export function msToNextMidnight(now: Date): number {
  const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0, 0);
  const ms = next.getTime() - now.getTime();
  return Number.isFinite(ms) ? Math.max(1000, ms) : 3_600_000;
}

export interface WardrobeEnv {
  /** The local clock. */
  now(): Date;
  /** The stored choice (State.settings.cat.outfit): any value, cleaned here. */
  choice(): unknown;
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
  /** The outfit to draw changed (never `auto`): the island keeps it in State and redraws. */
  apply(outfit: OutfitId): void;
}

export class WardrobeClock {
  private timer: number | null = null;
  private shown: OutfitId | null = null;
  private readonly env: WardrobeEnv;

  constructor(env: WardrobeEnv) { this.env = env; }

  /** The outfit being drawn now, or null before the first `sync`. */
  get outfit(): OutfitId | null { return this.shown; }

  /** The app started or the stored choice may have changed: resolve it for today, tell the island if it differs, and keep a midnight timer exactly while the choice is `auto`. */
  sync(): void {
    if (this.timer !== null) { this.env.clear(this.timer); this.timer = null; }
    const d = this.env.now(), choice = outfitIdOf(this.env.choice()), out = resolveOutfit(choice, d.getFullYear(), d.getMonth() + 1, d.getDate());
    if (out !== this.shown) { this.shown = out; this.env.apply(out); }
    if (choice === "auto") this.timer = this.env.set(() => { this.timer = null; this.sync(); }, msToNextMidnight(d));
  }
}
EOF
```

- [ ] **Step 4: Put it in the island and in `State`**

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

st = "windows/src/core/state.ts"
edit(st, '''  /** The big cat's spot in the notch is empty: the desktop cat has left it (sub-project H).''', '''  /** The outfit the big cats wear now (sub-project I): the stored choice resolved for today (island/wardrobe.ts), one of the 16 drawn outfit IDs or `none`, never `auto`. Only a big cat gets it. */
  outfit: OutfitId = "none";

  /** The big cat's spot in the notch is empty: the desktop cat has left it (sub-project H).''')
edit(st, '''import type { CatBlock } from "../cat/display.ts";
''', '''import type { CatBlock } from "../cat/display.ts";
import type { OutfitId } from "../cat/wardrobe.ts";
''')

i = "windows/src/island/island.ts"
edit(i, '''import { SleepClock } from "./sleep";
''', '''import { SleepClock } from "./sleep";
import { WardrobeClock } from "./wardrobe";
''')
edit(i, '''  private root: HTMLElement;
  private islandEl!: HTMLElement;''', '''  /** Auto's one-shot (sub-project I): the outfit is the stored choice resolved for today, looked at again at the next local midnight, and only while the choice is `auto` (island/wardrobe.ts). */
  private wardrobe = new WardrobeClock({
    now: () => new Date(),
    choice: () => State.settings.cat.outfit,
    set: (fn, ms) => window.setTimeout(fn, ms),
    clear: (id) => window.clearTimeout(id),
    apply: (outfit) => { State.outfit = outfit; State.notify(); },
  });

  private root: HTMLElement;
  private islandEl!: HTMLElement;''')
edit(i, '''    applyCatSettings(catCfg, block);
    State.settings.cat = block;
    State.notify();''', '''    applyCatSettings(catCfg, block);
    State.settings.cat = block;
    this.wardrobe.sync();
    State.notify();''')
EOF
```

- [ ] **Step 5: Run the test to see it pass**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
node --experimental-strip-types --test scripts/cat-tests/wardrobe-clock.test.mjs 2>&1 | grep -E "^# (pass|fail)"
cd ..
```

Expected: `tsc exit 0` and `# pass 8`, `# fail 0` (the daylight-saving test sets `process.env.TZ` for a moment and puts it back).

- [ ] **Step 6: Prove it bites**

Run (without the guard, an explicit outfit would keep a timer):

```bash
cd windows
python3 ../.claude/checkpoints/i-tauri/mut.py src/island/wardrobe.ts 'if (choice === "auto") this.timer' 'this.timer' scripts/cat-tests/wardrobe-clock.test.mjs
cd ..
```

Expected: `wardrobe.ts | this.timer | # pass 7 # fail 1`.

- [ ] **Step 7: The whole suite**

Run:

```bash
cd windows
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `ℹ tests 404`, `ℹ pass 404` and `ℹ fail 0`.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/island/wardrobe.ts windows/src/core/state.ts windows/src/island/island.ts windows/scripts/cat-tests/wardrobe-clock.test.mjs
git commit -F - <<'MSG'
feat(wardrobe): Auto's one-shot at midnight and State.outfit

The island resolves the stored outfit for today at launch and whenever the settings change, and looks again at the next local midnight with one timer that exists only while the choice is auto; a late timer recomputes from the date it finds.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

### Task 7: Who wears it

**Agent:** `nm-implementer` (Haiku 5.5, high); it runs a browser, so it also loads `playwright-cli`.

**Files:**
- Modify: `windows/src/cat/renderer.ts` (`outfitCeiling`), `windows/src/island/island.ts`, `windows/src/cat/greeting.ts`, `windows/src/cat/desktoptrip.ts`, `windows/src/island/desktop.ts`, `windows/src/cat/desktopdraw.ts`, `windows/src/desktop/body.ts`, `windows/src/cat/dev.ts`, `windows/src/cat/devdesktop.ts`
- Modify (four existing tests, one pinned line each): `windows/scripts/cat-tests/desktop-look.test.mjs`, `desktop-island.test.mjs`, `sites.test.mjs`, `two-cats.test.mjs`
- Test: `windows/scripts/cat-tests/wardrobe-wiring.test.mjs`

**Interfaces:**
- Consumes: `State.outfit` (Task 6), `BotEngine.outfit` and `DrawOptions.outfit` (Task 4).
- Produces: `Island.drawBot` and `drawBot2` set `engine.outfit` / `engine2.outfit` to `State.outfit` (the two big cats; every other engine is never given one); `greetingDressed(t: number, leave?: number): boolean` and `Greeting.start(cast?, outfit?: string | null)` (the settled cat and the pair's cat 2 wear it; the session cats never; `outfitCeiling: 0` keeps a hat under the canvas's top without touching the ears); `DesktopLook.outfit?: string | null` (`drawDesktopCat` sets `engine.outfit`; the kittens' engines are never touched), `BodyLook.outfit: string` (the brain sends `State.outfit`); `DrawOptions.outfitCeiling?: number`. In the `?dev` page: the mock desktop's cats and the Greeting panel get an Outfit row, and the bench measures a frame with the witch hat on.

- [ ] **Step 1: Write the test**

```bash
cat > windows/scripts/cat-tests/wardrobe-wiring.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { BotEngine } from "../../src/cat/engine.ts";
import { drawDesktopCat } from "../../src/cat/desktopdraw.ts";
import { desktopWindowLayout } from "../../src/cat/desktopview.ts";
import { GT, GT2, Greeting, greetingDressed } from "../../src/cat/greeting.ts";
import { KittenPool } from "../../src/cat/kittendraw.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

// Who wears the outfit (sub-project I): the big cats, in every view that shows one, and nobody else. Behaviour where it can be run, source pins where the island's page cannot.
installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const total = (ctx) => Object.values(ctx.calls).reduce((a, b) => a + b, 0);
const K = (id, state = "working") => ({ id, type: "", session: null, state, born: 0, last: 0, until: null });
const engine = () => new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 });
const look = (o = {}) => ({ coat: "momo", collar: "#8AB4F8", kittens: [], lookX: 0, lookY: 0, dancing: false, pill: "integration_claude", ...o });

test("the desktop cat wears the outfit it is told at every size, its kittens stay bare, and none or nothing draws what it drew before", () => {
  for (const size of ["small", "medium", "large"]) {
    const L = desktopWindowLayout(size, "momo", 0, 1), bare = fakeCanvas(), worn = fakeCanvas(), none = fakeCanvas(), e = engine();
    drawDesktopCat(bare, engine(), new KittenPool(), L, look(), 1 / 60);
    drawDesktopCat(worn, e, new KittenPool(), L, look({ outfit: "crown" }), 1 / 60);
    drawDesktopCat(none, engine(), new KittenPool(), L, look({ outfit: "none" }), 1 / 60);
    assert.ok(total(worn) > total(bare), `${size}: the crown is drawn`);
    assert.deepEqual(none.calls, bare.calls, `${size}: none draws nothing`);
    assert.equal(e.outfit, "crown");
  }
  const L = desktopWindowLayout("medium", "momo", 3, 1), pool = new KittenPool(), kittens = [K("a"), K("b"), K("c")];
  drawDesktopCat(fakeCanvas(), engine(), pool, L, look({ kittens, outfit: "witchhat" }), 1 / 60);
  for (const k of kittens) assert.equal(pool.get(`desktop:integration_claude:${k.id}`, "momo", "working").outfit, null, `kitten ${k.id} is bare`);
  const taken = fakeCanvas(); drawDesktopCat(taken, engine(), new KittenPool(), L, look({ kittens, outfit: null }), 1 / 60);
  const dressed = fakeCanvas(); drawDesktopCat(dressed, engine(), new KittenPool(), L, look({ kittens, outfit: "witchhat" }), 1 / 60);
  assert.ok(total(dressed) > total(taken), "the cat is dressed with its kittens beside it");
});

test("the greeting's cat is dressed once it has settled (or as the island folds, if that comes first), and the session cats never are", () => {
  assert.equal(greetingDressed(0), false);
  assert.equal(greetingDressed(GT2.back1 - 0.001), false);
  assert.equal(greetingDressed(GT2.back1), true);
  assert.equal(greetingDressed(GT.leave + 1), true);
  assert.equal(greetingDressed(1.0, 1.0), true, "the pointer left early: dressed as the island folds");
  assert.equal(greetingDressed(0.9, 1.0), false);
  const drawAt = (t, outfit, cast) => {
    globalThis.window = { setTimeout: () => 1, clearTimeout: () => {} };
    const g = new Greeting();
    g.start(cast, outfit);
    Object.defineProperty(g, "elapsed", { get: () => t });
    const ctx = fakeCanvas(); g.draw(ctx);
    return total(ctx);
  };
  for (const outfit of ["crown", "witchhat", "scarf", "bunnyears", "sunglasses"]) {
    assert.equal(drawAt(1.0, outfit), drawAt(1.0, null), `${outfit}: not dressed while it is still bouncing and waving`);
    assert.ok(drawAt(GT2.back1 + 0.1, outfit) > drawAt(GT2.back1 + 0.1, null), `${outfit}: dressed once settled`);
    assert.ok(drawAt(GT.leave + 0.6, outfit) > drawAt(GT.leave + 0.6, null), `${outfit}: and through the compact notch's tail`);
  }
  assert.equal(drawAt(GT2.back1 + 0.1, "none"), drawAt(GT2.back1 + 0.1, null), "none draws nothing");
  assert.equal(drawAt(GT2.back1 + 0.1, "crown", undefined), drawAt(GT2.back1 + 0.1, "crown", undefined), "deterministic");
});

test("the island dresses the main cat and cat 2, and no other engine: the mini bots, the kittens and the drop view's cat are bare", () => {
  const island = source("island/island.ts");
  assert.match(island, /this\.engine\.collarColor = bigCatCollar\(State\.effectiveState, focus\?\.color\);\s*this\.engine\.outfit = State\.outfit;/);
  assert.match(island, /this\.engine2\.collarColor = bigCatCollar\(state, task\?\.color\);\s*this\.engine2\.outfit = State\.outfit;/);
  assert.equal((island.match(/this\.\w*[eE]ngine\w*\.outfit = /g) || []).length, 2, "exactly two engines of the island are dressed");
  for (const rel of ["cat/minibots.ts", "cat/kittendraw.ts", "cat/kittens.ts", "upload/canvas.ts", "site/main.ts", "settings/display.ts", "cat/agentcat.ts"]) assert.ok(!/outfit/i.test(source(rel)), `${rel} gives no outfit`);
  assert.match(source("island/island.ts"), /this\.greeting\.start\(State\.cast\.greeting, State\.outfit\);/);
});

test("the desktop cat's window is told the outfit by the brain and draws it, and the ?dev bench measures with one on", () => {
  assert.match(source("island/desktop.ts"), /size: desktopSizeOf\(State\.settings\.cat\.desktop\.size\), now: performance\.now\(\),\s*outfit: State\.outfit,/);
  assert.match(source("cat/desktoptrip.ts"), /outfit: string;/);
  assert.match(source("desktop/body.ts"), /dancing: look\.dancing, pill: look\.pill, outfit: look\.outfit \}, dt\);/);
  assert.match(source("cat/desktopdraw.ts"), /engine\.outfit = look\.outfit \?\? null;/);
  assert.ok(!/e\.outfit|engine\.outfit/.test(source("cat/desktopdraw.ts").split("const slots")[1]), "the kittens' engines are never dressed");
  assert.match(source("cat/devdesktop.ts"), /once\(id, 60, 3, "witchhat"\)/);
  assert.match(source("cat/devdesktop.ts"), /pill: "dev", outfit: st\.outfit \};/, "the mock desktop's cats can be dressed");
  assert.match(source("cat/dev.ts"), /greeting\.start\(undefined, dressed\.outfit\);/, "and so can the greeting's");
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe-wiring.test.mjs 2>&1 | grep -E "^# (pass|fail)|does not provide an export" | sort -u
cd ..
```

Expected: `does not provide an export named 'greetingDressed'` and `# fail 1`.

- [ ] **Step 3: Wire it**

One script changes the renderer's option, the two island engines, the greeting, the desktop cat's look, draw and body, the `?dev` page's rows and bench, and the four existing tests that pinned the lines it changes (the greeting's two calls, the brain's look and the body's draw call).

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

# The renderer: the room a hat gets may come from a ceiling of its own (the greeting's canvas), so the ears are not touched.
r = "windows/src/cat/renderer.ts"
edit(r, '''  outfit?: string | null;
  /** `ink` draws''', '''  outfit?: string | null;
  /** The y of the top of the canvas an outfit must stay under, when that is not the ears' `earCeiling` (the greeting's canvas); default `earCeiling`. */
  outfitCeiling?: number;
  /** `ink` draws''')
edit(r, '''outfitShapes(o.outfit, p, s, D, L.head.y, o.earCeiling, {''', '''outfitShapes(o.outfit, p, s, D, L.head.y, o.outfitCeiling ?? o.earCeiling, {''')

# The island's two big cats: the main cat (compact and open, in every display mode) and cat 2 in Two cats mode. Nothing else on the island gets one.
i = "windows/src/island/island.ts"
edit(i, '''    this.engine.collarColor = bigCatCollar(State.effectiveState, focus?.color);
''', '''    this.engine.collarColor = bigCatCollar(State.effectiveState, focus?.color);
    this.engine.outfit = State.outfit; // a big cat in every size, the compact notch's included (sub-project I)
''')
edit(i, '''    this.engine2.collarColor = bigCatCollar(state, task?.color);
''', '''    this.engine2.collarColor = bigCatCollar(state, task?.color);
    this.engine2.outfit = State.outfit; // cat 2 is a big cat too
''')
edit(i, '''          this.greeting.start(State.cast.greeting);''', '''          this.greeting.start(State.cast.greeting, State.outfit);''')

# The greeting: the cat is dressed once it has settled, the second cat of Two cats mode when it pops in.
g = "windows/src/cat/greeting.ts"
edit(g, '''/** A session cat of the compact grid, in the greeting's blue: the tint the greeting ends with. */''', '''/** Whether the greeting's big cat wears the outfit yet (sub-project I): once it has settled after its wave (`GT2.back1`), or as soon as the island folds (`leave`), whichever comes first. */
export const greetingDressed = (t: number, leave = GT.leave): boolean => t >= Math.min(GT2.back1, leave);

/** A session cat of the compact grid, in the greeting's blue: the tint the greeting ends with. */''')
edit(g, '''  private pairView: CatView | null = null;
  private readonly now: () => number;''', '''  private pairView: CatView | null = null;
  /** The outfit the big cats wear (State.outfit, resolved): the settled cat and cat 2 wear it; the session cats stay bare. */
  private outfit: string | null = null;
  private readonly now: () => number;''')
edit(g, '''  start(cast?: GreetingCast) {
    this.startMs = this.now();''', '''  start(cast?: GreetingCast, outfit: string | null = null) {
    this.outfit = outfit;
    this.startMs = this.now();''')
edit(g, '''    drawCat(x, v, P.x + room, P.y, D, { paws, badgeSide: 1 - 2 * fold });''', '''    // The canvas's top edge is the screen's top: a hat is held under it (`outfitCeiling`), and the ears are left as the greeting always drew them.
    drawCat(x, v, P.x + room, P.y, D, { paws, badgeSide: 1 - 2 * fold, outfit: greetingDressed(t, leave) ? this.outfit : null, outfitCeiling: 0 });''')
edit(g, '''PAIR.compact.d * pop, { badge: false });''', '''PAIR.compact.d * pop, { badge: false, outfit: this.outfit, outfitCeiling: 0 });''')

# The desktop cat: the brain says which outfit, the body draws it, the kittens beside it stay bare.
t = "windows/src/cat/desktoptrip.ts"
edit(t, '''  coat: string; state: string; collar: string | null; kittens: Kitten[]; pill: string; dancing: boolean; working: boolean; asleep: boolean; size: DesktopSizeId; now: number;
}''', '''  coat: string; state: string; collar: string | null; kittens: Kitten[]; pill: string; dancing: boolean; working: boolean; asleep: boolean; size: DesktopSizeId; now: number;
  /** The outfit it wears (State.outfit, resolved: a drawn outfit ID or `none`). The kittens beside it never wear one. */
  outfit: string;
}''')
d = "windows/src/island/desktop.ts"
edit(d, '''size: desktopSizeOf(State.settings.cat.desktop.size), now: performance.now(),
    };''', '''size: desktopSizeOf(State.settings.cat.desktop.size), now: performance.now(),
      outfit: State.outfit,
    };''')
dd = "windows/src/cat/desktopdraw.ts"
edit(dd, '''  /** The agent pill the kittens belong to (their engines are kept per pill). */
  pill: string;
}''', '''  /** The agent pill the kittens belong to (their engines are kept per pill). */
  pill: string;
  /** The outfit the cat wears (a resolved ID, or none/null for none). Only the cat: its kittens stay bare. */
  outfit?: string | null;
}''')
edit(dd, '''  engine.collarColor = look.collar;
  engine.particleOverhang = lay.overhang;''', '''  engine.collarColor = look.collar;
  engine.outfit = look.outfit ?? null;
  engine.particleOverhang = lay.overhang;''')
b = "windows/src/desktop/body.ts"
edit(b, '''dancing: look.dancing, pill: look.pill }, dt);''', '''dancing: look.dancing, pill: look.pill, outfit: look.outfit }, dt);''')

# The existing pins that name these two lines.
lt = "windows/scripts/cat-tests/desktop-look.test.mjs"
edit(lt, '''size: desktopSizeOf\\(State\\.settings\\.cat\\.desktop\\.size\\), now: performance\\.now\\(\\),/);''', '''size: desktopSizeOf\\(State\\.settings\\.cat\\.desktop\\.size\\), now: performance\\.now\\(\\),\\s*outfit: State\\.outfit,/);''')
edit(lt, '''dancing: look\\.dancing, pill: look\\.pill \\}, dt\\);/);''', '''dancing: look\\.dancing, pill: look\\.pill, outfit: look\\.outfit \\}, dt\\);/);''')

# The bench: one run with the tallest hat on, to prove an outfit adds no motion and little drawing.
dv = "windows/src/cat/devdesktop.ts"
edit(dv, '''  const once = (id: DesktopSizeId, frames: number, kittens = 3): number => {
    const e = new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 }), pool = new KittenPool(), lay = desktopWindowLayout(id, "shrimpy", kittens, 1);
    const c = fit(document.createElement("canvas"), lay.w, lay.h), look: DesktopLook = { coat: "shrimpy", collar: COLLAR, kittens: kittensOf(kittens), lookX: 0.2, lookY: 0, dancing: false, pill: "bench" }, t0 = performance.now();''', '''  const once = (id: DesktopSizeId, frames: number, kittens = 3, outfit: string | null = null): number => {
    const e = new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 }), pool = new KittenPool(), lay = desktopWindowLayout(id, "shrimpy", kittens, 1);
    const c = fit(document.createElement("canvas"), lay.w, lay.h), look: DesktopLook = { coat: "shrimpy", collar: COLLAR, kittens: kittensOf(kittens), lookX: 0.2, lookY: 0, dancing: false, pill: "bench", outfit }, t0 = performance.now();''')
edit(dv, '''    lines.push("", "The cursor check''', '''    lines.push("", "With the witch hat on (the tallest outfit; an outfit adds no motion, so the frame rates are the same):");
    for (const id of ["small", "medium", "large"] as const) {
      once(id, 20, 3, "witchhat");
      const bare = median([once(id, 60, 3), once(id, 60, 3), once(id, 60, 3)]), worn = median([once(id, 60, 3, "witchhat"), once(id, 60, 3, "witchhat"), once(id, 60, 3, "witchhat")]);
      lines.push(`${id.padEnd(7)} bare ${bare.toFixed(2)} ms, dressed ${worn.toFixed(2)} ms per frame (${(worn - bare >= 0 ? "+" : "") + (worn - bare).toFixed(2)} ms)`);
    }
    lines.push("", "The cursor check''')

# The mock desktop's own Outfit row, so the three sizes can be looked at dressed (the bench above uses the witch hat on its own).
edit(dv, '''  const st = { coat: "shrimpy", state: null as StateName | null, kittens: 5, collar: true };''', '''  const st = { coat: "shrimpy", state: null as StateName | null, kittens: 5, collar: true, outfit: null as string | null };''')
edit(dv, '''    choice("Collar", ([[true, "on"], [false, "off"]] as const), () => st.collar, (v) => { st.collar = v; }),
''', '''    choice("Collar", ([[true, "on"], [false, "off"]] as const), () => st.collar, (v) => { st.collar = v; }),
    choice("Outfit", ([null, "partyhat", "witchhat", "bunnyears", "sunglasses", "crown", "scarf", "bell"] as const).map((o) => [o, o ?? "none"] as const), () => st.outfit, (v) => { st.outfit = v; }),
''')
edit(dv, '''lookY: Math.sin(t * 0.5) * 0.3, dancing: false, pill: "dev" };''', '''lookY: Math.sin(t * 0.5) * 0.3, dancing: false, pill: "dev", outfit: st.outfit };''')

# The ?dev page's Greeting panel gets an Outfit row, so the settled cat can be looked at dressed (and replayed).
dev = "windows/src/cat/dev.ts"
edit(dev, '''  let greeting = new Greeting();
  greeting.start();
''', '''  const dressed = { outfit: "witchhat" as string | null };
  let greeting = new Greeting();
  greeting.start(undefined, dressed.outfit);
''')
edit(dev, '''button("Replay", () => { greeting = new Greeting(); greeting.start(); })''', '''button("Replay", () => { greeting = new Greeting(); greeting.start(undefined, dressed.outfit); })''')
edit(dev, '''  greetBox.append(gRow, gHolder);''', '''  greetBox.append(choice("Outfit", ([null, "witchhat", "crown", "sunglasses", "scarf"] as const).map((o) => [o, o ?? "none"] as const), () => dressed.outfit, (v) => { dressed.outfit = v; }), gRow, gHolder);''')

# The three existing pins that name the greeting's two changed lines.
edit("windows/scripts/cat-tests/desktop-island.test.mjs", r"""this\.greeting\.start\(State\.cast\.greeting\);\s*break;""", r"""this\.greeting\.start\(State\.cast\.greeting, State\.outfit\);\s*break;""")
edit("windows/scripts/cat-tests/sites.test.mjs", r"""/this\.greeting\.start\(State\.cast\.greeting\);/""", r"""/this\.greeting\.start\(State\.cast\.greeting, State\.outfit\);/""")
edit("windows/scripts/cat-tests/two-cats.test.mjs", r"""PAIR\.compact\.d \* pop, \{ badge: false \}\)/""", r"""PAIR\.compact\.d \* pop, \{ badge: false, outfit: this\.outfit, outfitCeiling: 0 \}\)/""")
EOF
```

- [ ] **Step 4: Run the test, the type check and the whole suite**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
node --experimental-strip-types --test scripts/cat-tests/wardrobe-wiring.test.mjs 2>&1 | grep -E "^# (pass|fail)"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `tsc exit 0`, `# pass 4`, `# fail 0`, then `ℹ tests 408`, `ℹ pass 408` and `ℹ fail 0` (the four edited tests still pass).

- [ ] **Step 5: Prove it bites**

Run (cat 2 undressed, and a greeting dressed from its first frame):

```bash
cd windows
python3 ../.claude/checkpoints/i-tauri/mut.py src/island/island.ts "    this.engine2.outfit = State.outfit; // cat 2 is a big cat too
" "" scripts/cat-tests/wardrobe-wiring.test.mjs
python3 ../.claude/checkpoints/i-tauri/mut.py src/cat/greeting.ts 't >= Math.min(GT2.back1, leave)' 't >= 0' scripts/cat-tests/wardrobe-wiring.test.mjs
cd ..
```

Expected: `island.ts |  | # pass 3 # fail 1` and `greeting.ts | t >= 0 | # pass 3 # fail 1`.

- [ ] **Step 6: Look at the big cats dressed, in the island, the greeting, the desktop and the bench**

Start the dev server (port 14613, "How to run this plan"). The island's page in the dev server has `window.__nm = { island, State, hook }`: set the stored outfit as Settings would, and let the island apply it.

```bash
cd .claude/checkpoints/i-tauri
playwright-cli -s=iwi open "http://127.0.0.1:14613/?display=two"
playwright-cli -s=iwi resize 760 300
playwright-cli -s=iwi eval "(()=>{const n=window.__nm; n.State.settings.cat={...n.State.settings.cat, outfit:'witchhat'}; n.island.applySettings(); return JSON.stringify([n.State.cast.mode, n.State.outfit])})()"
playwright-cli -s=iwi screenshot --filename=island-two-cats.png
playwright-cli -s=iwi goto "http://127.0.0.1:14613/?display=perAgent"
playwright-cli -s=iwi eval "(()=>{const n=window.__nm; n.hook({hook_event_name:'PreToolUse',tool_name:'Bash',session_id:'s1',nm_kind:'hook'}); n.State.settings.cat={...n.State.settings.cat, outfit:'bunnyears'}; n.island.applySettings(); return JSON.stringify([n.State.cast.mode, n.State.cast.big.cat, n.State.outfit])})()"
playwright-cli -s=iwi screenshot --filename=island-per-agent.png
playwright-cli -s=iwi goto "http://127.0.0.1:14613/"
playwright-cli -s=iwi eval "(()=>{const n=window.__nm; n.State.settings.cat={...n.State.settings.cat, outfit:'none'}; n.island.applySettings(); return n.State.outfit})()"
playwright-cli -s=iwi screenshot --filename=island-none.png
playwright-cli -s=iwi close
cd ../../..
```

Expected: the first `eval` prints `["two","witchhat"]`, the second `["perAgent","shrimpy","bunnyears"]` and the third `none`. Open the three pictures: **in Two cats mode both cats of the compact strip wear a witch hat, and the grid's three small cats on the right wear nothing; in A cat for each agent mode the big cat (Claude Code's Shrimpy) wears bunny ears and the 2 by 2 grid is bare; with `none` the island is as it was.** (Both hats are shortened to the strip, as the ears are; the notch's top edge cuts nothing but the tip.)

Then the `?dev` page: the mock desktop's cats dressed at the three sizes with their kittens bare, the greeting's settled cat dressed, and the bench with the witch hat on:

```bash
cd .claude/checkpoints/i-tauri
playwright-cli -s=iwd open "http://127.0.0.1:14613/?dev"
playwright-cli -s=iwd resize 1100 1200
playwright-cli -s=iwd eval "(()=>{const s=document.querySelector('#desktop-mock').closest('section'); [...s.querySelectorAll('button')].find(x=>x.textContent==='witchhat').click(); return 'dressed'})()"
playwright-cli -s=iwd screenshot "#desktop-mock" --filename=desktop-dressed.png
playwright-cli -s=iwd eval "(()=>{document.querySelector('#desktop-bench-run').click(); return document.querySelector('#desktop-bench').textContent})()"
playwright-cli -s=iwd eval "(()=>{const g=[...document.querySelectorAll('section')].find(s=>s.querySelector('h2')?.textContent==='Greeting'); g.id='greet'; [...g.querySelectorAll('button')].find(b=>b.textContent==='Replay').click(); return 'replayed'})()"
sleep 3.6
playwright-cli -s=iwd screenshot "#greet" --filename=greeting-dressed.png
playwright-cli -s=iwd close
cd ../../..
```

Expected: `dressed`; the bench prints its usual table and then `With the witch hat on (the tallest outfit; an outfit adds no motion, so the frame rates are the same):` followed by three lines `small   bare … ms, dressed … ms per frame (+… ms)` (the same size, about 0.02 to 0.05 ms more); `replayed`. In `desktop-dressed.png` **the three desktop cats wear the witch hat, the badge and the collar are where they were, and the kittens beside each cat are bare**; in `greeting-dressed.png` the settled cat, after its wave and its slide back, wears the hat. Keep the numbers: they go to Checkpoint 2.

Stop the dev server by its saved PID: `kill "$(cat .claude/checkpoints/i-tauri/vite.pid)"`.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/cat windows/src/island windows/src/desktop windows/scripts/cat-tests
git commit -F - <<'MSG'
feat(wardrobe): the big cats wear it

The island's main cat and cat 2, the desktop cat and the greeting's settled cat are dressed with State.outfit; mini cats, kittens, the Display preview and the drop view stay bare. The dev page can dress the mock desktop and the greeting, and its bench measures a frame with the witch hat on.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

### Task 8: Settings → Wardrobe

**Agent:** `nm-implementer` (Haiku 5.5, high); it runs a browser, so it also loads `playwright-cli`.

**Files:**
- Create: `windows/src/cat/wardrobeui.ts`, `windows/src/settings/wardrobe.ts`
- Modify: `windows/src/settings/cat.ts`, `windows/src/settings/main.ts`, `windows/src/settings/settings.css`
- Test: `windows/scripts/cat-tests/wardrobe-ui.test.mjs`

**Interfaces:**
- Consumes: `wardrobe.ts`, `display.ts` (`withOutfit`, `cleanCatBlock`, `CatBlock`), `engine.ts` (`BotEngine`), `renderer.ts` (`drawCat`, `stillView`), `settings/display.ts` (`UiKit`).
- Produces: `cat/wardrobeui.ts` (pure): `LocalDate`, `localDate(now: Date)`, `tileOutfit(id, on)`, `autoLabel(on)` (`"Auto: today, Santa hat"` or `"Auto: today, none"`), `wardrobeTiles(on): TileGroup[]` (the 18 tiles in five rows; only Auto is wide), `previewOutfit(stored, hover, on): string | null` (the tile under the pointer, else the chosen, resolved for today), `storedFor(tileId)`. `settings/wardrobe.ts`: `wardrobeSection(host: { block(): CatBlock; put(next: CatBlock, final: boolean): void }, ui: UiKit): { el: HTMLElement; sync(): void; draw(dt: number): void }`. `catSection` now returns `{ el, wardrobe, sync }` and `settings/main.ts` puts `cat.wardrobe` right after `cat.el`. New CSS classes only: `.wardrobe-tiles`, `.wardrobe-grid`, `.wardrobe-cell`.

- [ ] **Step 1: Write the test**

```bash
cat > windows/scripts/cat-tests/wardrobe-ui.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { OUTFIT_IDS } from "../../src/cat/wardrobe.ts";
import { autoLabel, localDate, previewOutfit, storedFor, tileOutfit, wardrobeTiles } from "../../src/cat/wardrobeui.ts";

// What Settings → Wardrobe shows (sub-project I): the pure parts replayed, the page's glue pinned by source (it needs a browser; the headless pictures are in the plan's checkpoints).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const on = (y, m, d) => ({ y, m, d });

test("the tiles are the 18 IDs in the grid's order, in five rows with their headings, and only Auto is wide", () => {
  const groups = wardrobeTiles(on(2025, 7, 4));
  assert.deepEqual(groups.map((g) => g.name), ["", "Seasonal", "Everyday", "Cat extras", "The cats' own"]);
  assert.deepEqual(groups.flatMap((g) => g.tiles.map((t) => t.id)), [...OUTFIT_IDS]);
  assert.deepEqual(groups.flatMap((g) => g.tiles).filter((t) => t.wide).map((t) => t.id), ["auto"]);
  assert.deepEqual(groups[1].tiles.map((t) => t.label), ["Party hat", "Santa hat", "Witch hat", "Bunny ears", "Sunglasses"]);
  assert.equal(groups[0].tiles[1].label, "None");
  assert.equal(groups[0].tiles[1].wears, "none");
});

test("the Auto tile shows today's result: its label and what its cat wears, for the five rules and for a plain day", () => {
  assert.equal(autoLabel(on(2025, 12, 24)), "Auto: today, Santa hat");
  assert.equal(autoLabel(on(2026, 1, 1)), "Auto: today, Party hat");
  assert.equal(autoLabel(on(2025, 10, 31)), "Auto: today, Witch hat");
  assert.equal(autoLabel(on(2025, 4, 18)), "Auto: today, Bunny ears");
  assert.equal(autoLabel(on(2025, 7, 4)), "Auto: today, Sunglasses");
  assert.equal(autoLabel(on(2025, 3, 3)), "Auto: today, none");
  assert.equal(wardrobeTiles(on(2025, 12, 24))[0].tiles[0].wears, "santahat");
  assert.equal(wardrobeTiles(on(2025, 3, 3))[0].tiles[0].wears, "none");
  assert.deepEqual(localDate(new Date(2025, 11, 24, 23, 59)), on(2025, 12, 24));
  assert.equal(tileOutfit("auto", on(2025, 12, 24)), "santahat");
  assert.equal(tileOutfit("bow", on(2025, 12, 24)), "bow");
});

test("the preview wears the tile under the pointer, else the chosen outfit, resolved for today, and null for none", () => {
  const xmas = on(2025, 12, 24), plain = on(2025, 3, 3);
  assert.equal(previewOutfit("crown", null, xmas), "crown", "the chosen one");
  assert.equal(previewOutfit("crown", "bow", xmas), "bow", "the tile under the pointer wins");
  assert.equal(previewOutfit("crown", "auto", xmas), "santahat", "the Auto tile shows today's result");
  assert.equal(previewOutfit("auto", null, xmas), "santahat");
  assert.equal(previewOutfit("auto", null, plain), null, "nothing today: bare");
  assert.equal(previewOutfit("crown", "none", xmas), null, "hovering None shows a bare cat");
  assert.equal(previewOutfit("junk", undefined, xmas), "santahat", "a stored value that is not an ID is auto");
  assert.equal(previewOutfit(undefined, undefined, plain), null);
});

test("a click stores the tile's own ID: Auto stays auto and a made-up ID is auto", () => {
  for (const id of OUTFIT_IDS) assert.equal(storedFor(id), id);
  for (const bad of [undefined, null, 7, "Crown", "", "fancyhat"]) assert.equal(storedFor(bad), "auto", String(bad));
});

test("the section: its own card after Cat, built from the window's own rows, the preview coat stores nothing, and nothing runs a loop of its own", () => {
  const w = source("settings/wardrobe.ts"), cat = source("settings/cat.ts"), main = source("settings/main.ts");
  assert.match(w, /host\.put\(withOutfit\(now\(\), storedFor\(t\.id\)\), true\)/, "a click stores the tile's ID through withOutfit");
  assert.equal((w.match(/host\.put\(/g) || []).length, 1, "that click is the only thing that stores");
  assert.match(w, /\(v\) => \{ coat = v; preview\.setCoat\(coat\); drawTiles\(\); \}/, "the coat picker changes the preview and the stills only");
  assert.match(w, /"Only the preview: nothing is stored\."/);
  assert.doesNotMatch(w, /requestAnimationFrame|setInterval|setTimeout|VisibleLoop/);
  assert.match(w, /preview\.outfit = previewOutfit\(now\(\)\.outfit, hover, localDate\(new Date\(\)\)\);/);
  assert.match(cat, /drawOne\(preview, previewCv, PREVIEW_W, PREVIEW_H, dt\);\s*display\.draw\(dt\);\s*wardrobe\.draw\(dt\);/);
  assert.match(cat, /display\.sync\(\);\s*wardrobe\.sync\(\);/);
  assert.match(cat, /return \{ el, wardrobe: wardrobe\.el, sync: paint \};/);
  assert.match(main, /cat\.el,\s*cat\.wardrobe,\s*generalSection\(\),/);
});

test("the new CSS is new class names only: the Wardrobe block adds .wardrobe-tiles, .wardrobe-grid and .wardrobe-cell, and no existing selector", () => {
  const css = source("settings/settings.css"), start = css.indexOf("/* Wardrobe (sub-project I)");
  assert.ok(start > 0);
  const block = css.slice(start).replace(/\/\*[\s\S]*?\*\//g, "");
  const selectors = [...block.matchAll(/([^{}]+)\{/g)].map((m) => m[1].trim());
  assert.ok(selectors.length >= 4, `${selectors.length} selectors`);
  for (const sel of selectors) assert.match(sel, /^\.wardrobe-(tiles|grid|cell)\b/, sel);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe-ui.test.mjs 2>&1 | grep -E "^# (pass|fail)|ERR_MODULE_NOT_FOUND" | sort -u
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND` and `# fail 1`.

- [ ] **Step 3: Write the pure part**

```bash
cat > windows/src/cat/wardrobeui.ts <<'EOF'
// What Settings → Wardrobe shows (sub-project I): the tiles in the grid's order with their labels, today's result for the Auto tile, and which outfit the live preview wears. Pure, so the plain-Node
// checks (npm run check:cat) can run it; settings/wardrobe.ts only builds the page from it. The preview and its coat picker store nothing: the only stored value is `outfit`.

import { OUTFIT_GROUPS, OUTFIT_NAMES, outfitIdOf, resolveOutfit } from "./wardrobe.ts";
import type { OutfitId } from "./wardrobe.ts";

/** A local calendar date as the contract's Auto reads it. */
export interface LocalDate { y: number; m: number; d: number }
export const localDate = (now: Date): LocalDate => ({ y: now.getFullYear(), m: now.getMonth() + 1, d: now.getDate() });

/** What a tile stands for today: itself, or for Auto what the calendar says (`none` when nothing is worn). Never `auto`. */
export const tileOutfit = (id: unknown, on: LocalDate): OutfitId => resolveOutfit(id, on.y, on.m, on.d);

/** The Auto tile's label: "Auto: today, Santa hat" or "Auto: today, none". */
export const autoLabel = (on: LocalDate): string => {
  const out = tileOutfit("auto", on);
  return `Auto: today, ${out === "none" ? "none" : OUTFIT_NAMES[out]}`;
};

export interface Tile { id: OutfitId; label: string; /** What the tile's cat wears: a drawn outfit or `none`. */ wears: OutfitId; wide: boolean }
export interface TileGroup { id: string; name: string; tiles: Tile[] }

/** The grid: the two choices first, then the four groups with their headings, in the contract's order. The Auto tile is wide because its label is long. */
export const wardrobeTiles = (on: LocalDate): TileGroup[] =>
  OUTFIT_GROUPS.map((g) => ({
    id: g.id, name: g.name,
    tiles: g.ids.map((id) => ({ id, label: id === "auto" ? autoLabel(on) : OUTFIT_NAMES[id], wears: tileOutfit(id, on), wide: id === "auto" })),
  }));

/** The outfit the live preview draws: the tile under the pointer, else the chosen one, resolved for today; null for none (the engine takes null as bare). */
export const previewOutfit = (stored: unknown, hover: unknown, on: LocalDate): string | null => {
  const out = tileOutfit(hover === null || hover === undefined ? stored : hover, on);
  return out === "none" ? null : out;
};

/** The ID a tile click stores: the tile's own, never its resolved outfit (Auto stays `auto`). */
export const storedFor = (tileId: unknown): OutfitId => outfitIdOf(tileId);
EOF
```

- [ ] **Step 4: Write the card**

The card follows the Display rows' pattern: it is built from the Cat section's own helpers (`menu`, `row`, `sized`), its preview draws only when the Cat section's one `VisibleLoop` calls `draw`, the tiles are stills redrawn when what they show changes, and the coat picker changes only what is drawn (it never calls `put`).

```bash
cat > windows/src/settings/wardrobe.ts <<'EOF'
// Settings → Wardrobe (sub-project I): dress the big cats. A live preview of the Main cat (or any coat you pick, which changes nothing) wearing the tile under the pointer, else the chosen outfit,
// and the grid of 18 tiles in the contract's order: Auto and None, then Seasonal, Everyday, Cat extras and The cats' own. A click stores the tile's ID. Built from the window's own styles
// (.cat-grid's cells, .row, select, .hint); the new rules in settings.css are new class names only. The preview draws only while the window can be seen: the Cat section's one loop
// (cat/loop.ts) calls `draw`, the tiles are stills redrawn when something they show changes, and nothing here runs a timer or a loop of its own.

import { BotEngine } from "../cat/engine";
import { newPose } from "../cat/geometry";
import { CAT_IDS, PRESETS } from "../cat/presets";
import { drawCat, stillView } from "../cat/renderer";
import { cleanCatBlock, withOutfit } from "../cat/display";
import type { CatBlock } from "../cat/display";
import { localDate, previewOutfit, storedFor, wardrobeTiles } from "../cat/wardrobeui";
import type { OutfitId } from "../cat/wardrobe";
import { h } from "../views/dom";
import type { UiKit } from "./display";

/** What the section needs from the Cat section: the `cat` block as it is now, and a place to put the new one. */
export interface WardrobeHost {
  block(): CatBlock;
  put(next: CatBlock, final: boolean): void;
}

const TILE = 48;
const PREVIEW_W = 140;
const PREVIEW_H = 150;
/** The preview's collar colour: no agent is driving it, so it wears a sample, to show how the neck outfits sit over the collar style chosen in the Cat section. */
const SAMPLE_COLLAR = "#F29B38";

export function wardrobeSection(host: WardrobeHost, ui: UiKit) {
  const now = (): CatBlock => cleanCatBlock(host.block());
  let hover: OutfitId | null = null;
  // The coat the preview and the tiles show. It starts as the Main cat and is never stored: picking another only changes what you see here.
  let coat = now().character;

  const tiles = new Map<OutfitId, { btn: HTMLButtonElement; cv: HTMLCanvasElement; text: HTMLElement }>();
  const groups = wardrobeTiles(localDate(new Date())).map((g) => {
    const grid = h("div", { class: "wardrobe-grid", role: "group", "aria-label": g.name || "Choices" });
    for (const t of g.tiles) {
      const cv = h("canvas", {});
      ui.sized(cv, TILE, TILE);
      const text = h("span", { text: t.label });
      const btn = h("button", { class: `cat-cell wardrobe-cell${t.wide ? " wide" : ""}`, "aria-pressed": "false", title: t.label, onclick: () => host.put(withOutfit(now(), storedFor(t.id)), true) }, cv, text);
      btn.addEventListener("mouseenter", () => { hover = t.id; });
      btn.addEventListener("mouseleave", () => { hover = null; });
      btn.addEventListener("focus", () => { hover = t.id; });
      btn.addEventListener("blur", () => { hover = null; });
      tiles.set(t.id, { btn, cv, text });
      grid.append(btn);
    }
    return { name: g.name, grid };
  });

  const previewCv = h("canvas", {});
  ui.sized(previewCv, PREVIEW_W, PREVIEW_H);
  const preview = new BotEngine(PRESETS[coat]);
  preview.particleOverhang = 40;
  preview.collarColor = SAMPLE_COLLAR;

  const picker = ui.menu(CAT_IDS.map((id) => [id, PRESETS[id].label] as const), (v) => { coat = v; preview.setCoat(coat); drawTiles(); });
  const pickerRow = ui.row("Preview on", picker, h("span", { class: "hint", text: "Only the preview: nothing is stored." }));
  const chosen = h("div", { class: "hint" });

  /** The tiles are stills of the preview's coat wearing what each tile stands for. */
  function drawTiles() {
    const on = localDate(new Date()), view = stillView(PRESETS[coat], newPose()), dpr = Math.min(2, window.devicePixelRatio || 1);
    for (const g of wardrobeTiles(on)) for (const t of g.tiles) {
      const e = tiles.get(t.id);
      const ctx = e?.cv.getContext("2d");
      if (!e || !ctx) continue;
      e.text.textContent = t.label;
      e.btn.title = t.label;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, TILE, TILE);
      drawCat(ctx, view, TILE / 2, TILE / 2 + 8, 26, { tint: false, badge: false, outfit: t.wears === "none" ? null : t.wears, dpr });
    }
  }

  /** Follows the stored block: the pressed tile, the chosen line and the stills (Auto's tile shows today). */
  function sync() {
    const b = now(), on = localDate(new Date());
    for (const [id, e] of tiles) e.btn.setAttribute("aria-pressed", String(id === b.outfit));
    const name = [...wardrobeTiles(on).flatMap((g) => g.tiles)].find((t) => t.id === b.outfit)?.label ?? "";
    chosen.textContent = `Worn by every big cat: ${name}. The small cats and the kittens stay bare.`;
    picker.value = coat;
    drawTiles();
  }

  /** One frame of the preview, `dt` seconds after the last (the Cat section's loop calls it only while the window can be seen and has focus). */
  function draw(dt: number) {
    const ctx = previewCv.getContext("2d");
    if (!ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    preview.outfit = previewOutfit(now().outfit, hover, localDate(new Date()));
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, PREVIEW_W, PREVIEW_H);
    preview.update(dt);
    preview.draw(ctx, PREVIEW_W, PREVIEW_H);
  }

  const el = h("section", {},
    h("h2", {}, h("span", { text: "Wardrobe" })),
    h("div", { class: "hint", text: "Dress your big cats: one outfit at a time, or let Auto pick for the season. It fits every coat. Point at a tile to try it on." }),
    h("div", { class: "cat-top" }, h("div", { class: "wardrobe-tiles" },
      ...groups.flatMap((g) => [...(g.name ? [h("div", { class: "hint", text: g.name })] : []), g.grid])), h("div", { class: "cat-preview" }, previewCv)),
    pickerRow,
    chosen,
  );
  sync();
  return { el, sync, draw };
}
EOF
```

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

c = "windows/src/settings/cat.ts"
edit(c, '''import { displayRows } from "./display";
''', '''import { displayRows } from "./display";
import { wardrobeSection } from "./wardrobe";
''')
edit(c, '''  const display = displayRows({ block: () => host.cat(), put: (next, final) => change(next, final) }, { menu, row, sized });
''', '''  const display = displayRows({ block: () => host.cat(), put: (next, final) => change(next, final) }, { menu, row, sized });
  // Wardrobe (sub-project I): its own card under this one. It shares this section's loop and its edits go through the same `change`, so the block keeps every part.
  const wardrobe = wardrobeSection({ block: () => host.cat(), put: (next, final) => change(next, final) }, { menu, row, sized });
''')
edit(c, '''    display.sync();
  };''', '''    display.sync();
    wardrobe.sync();
  };''')
edit(c, '''      display.draw(dt);
    },''', '''      display.draw(dt);
      wardrobe.draw(dt);
    },''')
edit(c, '''export function catSection(host: CatHost): { el: HTMLElement; sync(): void } {''', '''export function catSection(host: CatHost): { el: HTMLElement; wardrobe: HTMLElement; sync(): void } {''')
edit(c, '''  return { el, sync: paint };''', '''  return { el, wardrobe: wardrobe.el, sync: paint };''')

m = "windows/src/settings/main.ts"
edit(m, '''    cat.el,
    generalSection(),''', '''    cat.el,
    cat.wardrobe,
    generalSection(),''')

css = "windows/src/settings/settings.css"
s = open(css).read()
s += '''
/* Wardrobe (sub-project I): the tiles reuse .cat-cell; these are new class names only. */
.wardrobe-tiles {
  display: flex;
  flex-direction: column;
  gap: 6px;
  flex: 1 1 344px;
  min-width: 0;
}

.wardrobe-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, 64px);
  gap: 6px;
}

.wardrobe-cell {
  width: 64px;
  text-align: center;
}

.wardrobe-cell.wide {
  grid-column: span 2;
  width: auto;
}

.wardrobe-cell span {
  padding: 0 3px;
  line-height: 1.15;
}
'''
open(css, "w").write(s)
EOF
```

- [ ] **Step 5: Run the test and the type check**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
node --experimental-strip-types --test scripts/cat-tests/wardrobe-ui.test.mjs 2>&1 | grep -E "^# (pass|fail)"
cd ..
```

Expected: `tsc exit 0` and `# pass 6`, `# fail 0`.

- [ ] **Step 6: Prove it bites**

Run (the preview that ignores the tile under the pointer):

```bash
cd windows
python3 ../.claude/checkpoints/i-tauri/mut.py src/cat/wardrobeui.ts 'hover === null || hover === undefined ? stored : hover' 'stored' scripts/cat-tests/wardrobe-ui.test.mjs
cd ..
```

Expected: `wardrobeui.ts | stored | # pass 5 # fail 1`.

- [ ] **Step 7: The whole suite**

Run:

```bash
cd windows
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `ℹ tests 414`, `ℹ pass 414` and `ℹ fail 0` (`settings-ui.test.mjs` still finds every Cat row in its order).

- [ ] **Step 8: Look at the card**

Start the dev server (port 14613). The Settings page runs in a plain browser too (it shows its defaults).

```bash
cd .claude/checkpoints/i-tauri
playwright-cli -s=iws open "http://127.0.0.1:14613/settings.html"
playwright-cli -s=iws resize 640 900
playwright-cli -s=iws eval "(()=>{const s=[...document.querySelectorAll('section')].find(x=>x.querySelector('h2')?.textContent==='Wardrobe'); s.id='wd'; return [...document.querySelectorAll('section > h2')].map(e=>e.textContent).join(' | ')})()"
playwright-cli -s=iws screenshot "#wd" --filename=settings-wardrobe.png
playwright-cli -s=iws eval "(()=>{const b=[...document.querySelectorAll('#wd .wardrobe-cell')].find(x=>x.title==='Crown'); b.click(); const on=[...document.querySelectorAll('#wd .wardrobe-cell[aria-pressed=true]')].map(x=>x.title); const s=document.querySelectorAll('#wd select')[0]; s.value='snow'; s.dispatchEvent(new Event('change')); return JSON.stringify([on, [...document.querySelectorAll('#wd .wardrobe-cell[aria-pressed=true]')].map(x=>x.title), s.value])})()"
playwright-cli -s=iws resize 460 900
playwright-cli -s=iws screenshot "#wd" --filename=settings-wardrobe-460.png
playwright-cli -s=iws close
cd ../../..
```

Expected: the first `eval` prints `Claude Code | Gemini CLI | Antigravity (agy) | AI | Integrations | Cat | Wardrobe | General` (the card is right under Cat), the second prints `[["Crown"],["Crown"],"snow"]` (a click chooses the tile; picking another coat for the preview leaves the choice alone). Open the two pictures: **the Auto tile (twice as wide) reads "Auto: today, <today's outfit>" or "Auto: today, none", None is next to it, then Seasonal, Everyday, Cat extras and The cats' own with their headings, every tile a small cat wearing its outfit, the pressed tile has the light border the Main cat's grid has, the black preview on the right wears the chosen outfit (or the one under the pointer), and under it a "Preview on" menu and the line "Worn by every big cat: …". At 460 px the preview wraps under the grid and nothing overflows.** The rest of Settings looks as it did.

Stop the dev server by its saved PID: `kill "$(cat .claude/checkpoints/i-tauri/vite.pid)"`.

- [ ] **Step 9: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/cat/wardrobeui.ts windows/src/settings windows/scripts/cat-tests/wardrobe-ui.test.mjs
git commit -F - <<'MSG'
feat(wardrobe): Settings -> Wardrobe

A card under Cat with a live preview of the Main cat wearing the tile under the pointer, 18 tiles in the contract's order (the Auto tile shows today's result), and a coat picker that stores nothing. One click stores the tile's ID through withOutfit.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

## Checkpoint 2: the owner looks at the dressed cats and the Settings card

Stop here. Send the owner the paths of the pictures in `.claude/checkpoints/i-tauri/` (`island-two-cats.png`, `island-per-agent.png`, `island-none.png`, `desktop-dressed.png`, `greeting-dressed.png`, `settings-wardrobe.png`, `settings-wardrobe-460.png`), the bench numbers of Task 7 (a frame bare and dressed at each size), the counts so far (`ℹ tests 414`) and this list, and wait:

1. **Two cats and A cat for each agent:** are both big cats dressed and the small cats bare? Do the hats in the compact strip read?
2. **The desktop cat at three sizes:** does the outfit sit right with the badge, the collar and the kittens? (The hat does not take the mouse: the cat's hit shape is the head, the badge and the kitten slots, as in H. Say if the hat should.)
3. **The greeting:** is the cat dressed at the right moment (after its wave, as it settles)?
4. **The Wardrobe card:** does it look like the rest of Settings? Is the Auto tile's label clear?
5. **The bench:** an outfit adds about 0.02 to 0.05 ms a frame and no motion: acceptable?

Do not start Task 9 before the owner's reply.

# Stage 4: the right-click menus

### Task 9: The desktop cat's right-click Wardrobe submenu

**Agent:** `nm-implementer` (Haiku 5.5, high). If it cannot make the menu build or tick after two tries, hand it to `nm-implementer-deep` (trigger 2).

**Files:**
- Create: `windows/src/core/wardrobemenu.ts`
- Modify: `windows/src/desktop/body.ts`, `windows/src/cat/desktoptrip.ts`, `windows/src/island/desktop.ts`, `windows/src/island/island.ts`
- Test: `windows/scripts/cat-tests/wardrobe-desktop-menu.test.mjs`

**Interfaces:**
- Consumes: `wardrobe.ts` (`OUTFIT_GROUPS`, `OUTFIT_IDS`, `OUTFIT_NAMES`, `outfitIdOf`), `display.ts` (`withOutfit`), `Bridge.saveSettings`, `WardrobeClock.sync` (Task 6); `@tauri-apps/api/menu` (already used by `desktop/body.ts`; the desktop window's capability already has `core:menu:default`).
- Produces: `core/wardrobemenu.ts`: `interface WardrobeItems { items: (CheckMenuItem | MenuItem | PredefinedMenuItem)[]; ticks: CheckMenuItem[] }`, `buildWardrobeItems(pick: (id: OutfitId) => void): Promise<WardrobeItems>` (18 check items in the contract's order, groups apart with a separator and a disabled heading each; built once and reused), `tickWardrobe(w, choice: unknown): Promise<void>` (the tick on the stored choice, `auto` for anything that is not an ID). `BodyLook.outfitChoice: string` (the stored choice); `BrainMsg` gains `{ k: "outfit"; id: string }`; `DesktopHost.outfitChanged(): void` (the island implements it as `this.wardrobe.sync()`); the brain stores the pick through `withOutfit`, saves, calls `outfitChanged` and sends the body its look again. The desktop cat's menu is now Open the notch, Send home, Size, Wardrobe.

- [ ] **Step 1: Write the test**

```bash
cat > windows/scripts/cat-tests/wardrobe-desktop-menu.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The desktop cat's right-click menu gains a Wardrobe submenu (sub-project I). It needs the native menu of a Tauri window, so it is pinned by source here and looked at in the owner's real-build checks.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const root = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the menu keeps Open the notch, Send home and Size as they were, and adds Wardrobe last", () => {
  const b = source("desktop/body.ts");
  assert.match(b, /const open = await MenuItem\.new\(\{ id: "open", text: "Open the notch"/);
  assert.match(b, /const home = await MenuItem\.new\(\{ id: "home", text: "Send home"/);
  assert.match(b, /items: \[open, home, await Submenu\.new\(\{ text: "Size", items: sizes \}\), await Submenu\.new\(\{ text: "Wardrobe", items: wardrobe\.items \}\)\]/);
  assert.match(b, /const sizes = await Promise\.all\(DESKTOP_SIZE_IDS\.map\(/, "the size items are built as before");
  assert.match(b, /private menuParts: Promise<\{ menu: Menu; sizes: CheckMenuItem\[\]; wardrobe: WardrobeItems \}> \| null = null;/, "the menu is still built once and reused");
  assert.match(b, /tickWardrobe\(parts\.wardrobe, this\.look\?\.outfitChoice\)/);
  assert.match(b, /buildWardrobeItems\(\(id\) => this\.say\(\{ k: "outfit", id \}\)\)/);
});

test("the shared items: the 18 choices in the contract's order, the groups apart with a disabled heading each, and a tick that follows the stored choice", () => {
  const m = source("core/wardrobemenu.ts");
  assert.match(m, /import \{ OUTFIT_GROUPS, OUTFIT_IDS, OUTFIT_NAMES, outfitIdOf \} from "\.\.\/cat\/wardrobe";/);
  assert.match(m, /OUTFIT_IDS\.map\(\(id\) => CheckMenuItem\.new\(\{ id: `outfit-\$\{id\}`, text: OUTFIT_NAMES\[id\], checked: false, action: \(\) => pick\(id\) \}\)\)/);
  assert.match(m, /for \(const \[gi, g\] of OUTFIT_GROUPS\.entries\(\)\) \{\s*if \(gi\) items\.push\(await PredefinedMenuItem\.new\(\{ item: "Separator" \}\)\);\s*if \(g\.name\) items\.push\(await MenuItem\.new\(\{ id: `outfit-group-\$\{g\.id\}`, text: g\.name, enabled: false \}\)\);\s*for \(const id of g\.ids\) items\.push\(ticks\[OUTFIT_IDS\.indexOf\(id\)\]\);/);
  assert.match(m, /const id = outfitIdOf\(choice\);\s*await Promise\.all\(w\.ticks\.map\(\(c, i\) => c\.setChecked\(OUTFIT_IDS\[i\] === id\)\)\);/);
});

test("a pick goes to the island's page, which stores it through withOutfit, saves, resolves it again and tells the body how the cat looks", () => {
  const t = source("cat/desktoptrip.ts"), d = source("island/desktop.ts"), i = source("island/island.ts");
  assert.match(t, /\| \{ k: "outfit"; id: string \}/);
  assert.match(t, /outfitChoice: string;/);
  assert.match(d, /outfitChoice: State\.settings\.cat\.outfit,/);
  assert.match(d, /case "outfit":\s*\/\/[^\n]*\n\s*State\.settings\.cat = withOutfit\(State\.settings\.cat, m\.id\);\s*void Bridge\.saveSettings\(State\.settings\);\s*this\.host\.outfitChanged\(\);\s*this\.sendLook\(true\);\s*break;/);
  assert.match(d, /outfitChanged\(\): void;/);
  assert.match(i, /outfitChanged: \(\) => this\.wardrobe\.sync\(\),/);
});

test("the desktop window may show a menu already, and its Rust side needed no change", () => {
  assert.match(root("src-tauri/capabilities/desktop.json"), /"core:menu:default"/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe-desktop-menu.test.mjs 2>&1 | grep -E "^# (pass|fail)"
cd ..
```

Expected: `# fail 3` and `# pass 1` (the last test, that the window may show a menu already, holds).

- [ ] **Step 3: Write the shared items**

```bash
cat > windows/src/core/wardrobemenu.ts <<'EOF'
// The Wardrobe items of a native right-click menu (sub-project I), shared by the desktop cat's menu (desktop/body.ts) and the island cat's (island/island.ts): the 18 choices in the contract's order
// (`OUTFIT_GROUPS`), the groups apart with a separator and a disabled heading each, and a tick on the stored choice. It only builds and ticks items; what a pick does is the caller's. Tauri's menu API
// is not available to the plain-Node checks, so this file is pinned by source (scripts/cat-tests/wardrobe-desktop-menu.test.mjs) and looked at in the real build.

import { CheckMenuItem, MenuItem, PredefinedMenuItem } from "@tauri-apps/api/menu";
import { OUTFIT_GROUPS, OUTFIT_IDS, OUTFIT_NAMES, outfitIdOf } from "../cat/wardrobe";
import type { OutfitId } from "../cat/wardrobe";

/** The items for a Submenu named Wardrobe, and the 18 check items in the order of `OUTFIT_IDS` (the ones `tickWardrobe` moves the tick between). */
export interface WardrobeItems {
  items: (CheckMenuItem | MenuItem | PredefinedMenuItem)[];
  ticks: CheckMenuItem[];
}

/** Builds the items once (a native menu's items are resources in Rust that nothing frees, so a menu is built once and reused). `pick` is called with the ID of the item the user chose. */
export async function buildWardrobeItems(pick: (id: OutfitId) => void): Promise<WardrobeItems> {
  const ticks = await Promise.all(OUTFIT_IDS.map((id) => CheckMenuItem.new({ id: `outfit-${id}`, text: OUTFIT_NAMES[id], checked: false, action: () => pick(id) })));
  const items: WardrobeItems["items"] = [];
  for (const [gi, g] of OUTFIT_GROUPS.entries()) {
    if (gi) items.push(await PredefinedMenuItem.new({ item: "Separator" }));
    if (g.name) items.push(await MenuItem.new({ id: `outfit-group-${g.id}`, text: g.name, enabled: false }));
    for (const id of g.ids) items.push(ticks[OUTFIT_IDS.indexOf(id)]);
  }
  return { items, ticks };
}

/** Puts the tick on the stored choice (anything that is not one of the 18 IDs is `auto`), and takes it off the others. Call it before every popup: only the tick changes between two right-clicks. */
export async function tickWardrobe(w: WardrobeItems, choice: unknown): Promise<void> {
  const id = outfitIdOf(choice);
  await Promise.all(w.ticks.map((c, i) => c.setChecked(OUTFIT_IDS[i] === id)));
}
EOF
```

- [ ] **Step 4: Put Wardrobe in the desktop cat's menu and the pick on its way to the island**

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

t = "windows/src/cat/desktoptrip.ts"
edit(t, '''  /** The outfit it wears (State.outfit, resolved: a drawn outfit ID or `none`). The kittens beside it never wear one. */
  outfit: string;
}''', '''  /** The outfit it wears (State.outfit, resolved: a drawn outfit ID or `none`). The kittens beside it never wear one. */
  outfit: string;
  /** The stored choice (one of the 18 IDs, `auto` included): the right-click menu's Wardrobe submenu ticks it. */
  outfitChoice: string;
}''')
edit(t, '''  | { k: "menu"; item: "open" | "home" | "small" | "medium" | "large" }
''', '''  | { k: "menu"; item: "open" | "home" | "small" | "medium" | "large" }
  /** The Wardrobe submenu of the right-click menu: the user picked one of the 18 selection IDs. */
  | { k: "outfit"; id: string }
''')

d = "windows/src/island/desktop.ts"
edit(d, '''import { cleanCatBlock, withDesktopSize } from "../cat/display";''', '''import { cleanCatBlock, withDesktopSize, withOutfit } from "../cat/display";''')
edit(d, '''  /** A point of the island window (px) is over the notch''', '''  /** The stored outfit changed (the desktop cat's Wardrobe menu): the island resolves it for today again and keeps Auto's one-shot only while it is `auto`. */
  outfitChanged(): void;
  /** A point of the island window (px) is over the notch''')
edit(d, '''      outfit: State.outfit,
    };''', '''      outfit: State.outfit, outfitChoice: State.settings.cat.outfit,
    };''')
edit(d, '''      case "screens": void this.refresh().then(() => this.trip.screensChanged()); break;''', '''      case "screens": void this.refresh().then(() => this.trip.screensChanged()); break;
      case "outfit":
        // The desktop cat's Wardrobe submenu: the same choice as Settings → Wardrobe, stored once and applied at once.
        State.settings.cat = withOutfit(State.settings.cat, m.id);
        void Bridge.saveSettings(State.settings);
        this.host.outfitChanged();
        this.sendLook(true);
        break;''')

i = "windows/src/island/island.ts"
edit(i, '''      overNotch: (x, y) => this.overNotch(x, y),
    };''', '''      overNotch: (x, y) => this.overNotch(x, y),
      outfitChanged: () => this.wardrobe.sync(),
    };''')

b = "windows/src/desktop/body.ts"
edit(b, '''import { Bridge, onEvent } from "../core/bridge";''', '''import { Bridge, onEvent } from "../core/bridge";
import { buildWardrobeItems, tickWardrobe } from "../core/wardrobemenu";
import type { WardrobeItems } from "../core/wardrobemenu";''')
edit(b, '''  private menuParts: Promise<{ menu: Menu; sizes: CheckMenuItem[] }> | null = null;''', '''  private menuParts: Promise<{ menu: Menu; sizes: CheckMenuItem[]; wardrobe: WardrobeItems }> | null = null;''')
edit(b, '''  /** The right-click menu: Open the notch, Send home and Size. A native menu, so it needs no room in the window. */
  private async menu(): Promise<void> {
    this.menuParts ??= this.buildMenu();
    let parts: { menu: Menu; sizes: CheckMenuItem[] };
    try { parts = await this.menuParts; } catch { this.menuParts = null; return; }
    // Only the tick moves from one right-click to the next.
    const size = desktopSizeOf(this.look?.size);
    await Promise.all(parts.sizes.map((c, i) => c.setChecked(DESKTOP_SIZE_IDS[i] === size)));
    await parts.menu.popup();
  }

  private async buildMenu(): Promise<{ menu: Menu; sizes: CheckMenuItem[] }> {''', '''  /** The right-click menu: Open the notch, Send home, Size and Wardrobe. A native menu, so it needs no room in the window. */
  private async menu(): Promise<void> {
    this.menuParts ??= this.buildMenu();
    let parts: { menu: Menu; sizes: CheckMenuItem[]; wardrobe: WardrobeItems };
    try { parts = await this.menuParts; } catch { this.menuParts = null; return; }
    // Only the ticks move from one right-click to the next.
    const size = desktopSizeOf(this.look?.size);
    await Promise.all([...parts.sizes.map((c, i) => c.setChecked(DESKTOP_SIZE_IDS[i] === size)), tickWardrobe(parts.wardrobe, this.look?.outfitChoice)]);
    await parts.menu.popup();
  }

  private async buildMenu(): Promise<{ menu: Menu; sizes: CheckMenuItem[]; wardrobe: WardrobeItems }> {''')
edit(b, '''    return { menu: await Menu.new({ items: [open, home, await Submenu.new({ text: "Size", items: sizes })] }), sizes };''', '''    // Wardrobe (sub-project I): the 18 choices in the contract's order, with a tick on the stored one (core/wardrobemenu.ts).
    const wardrobe = await buildWardrobeItems((id) => this.say({ k: "outfit", id }));
    return { menu: await Menu.new({ items: [open, home, await Submenu.new({ text: "Size", items: sizes }), await Submenu.new({ text: "Wardrobe", items: wardrobe.items })] }), sizes, wardrobe };''')
EOF
```

- [ ] **Step 5: Run the test, the type check and the whole suite**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
node --experimental-strip-types --test scripts/cat-tests/wardrobe-desktop-menu.test.mjs 2>&1 | grep -E "^# (pass|fail)"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `tsc exit 0`, `# pass 4`, `# fail 0`, then `ℹ tests 418`, `ℹ pass 418` and `ℹ fail 0` (`desktop-menu.test.mjs` and the window tests still pass: Open the notch, Send home and Size are the lines they were).

- [ ] **Step 6: Prove it bites**

Run (a desktop menu without its Wardrobe submenu):

```bash
cd windows
python3 ../.claude/checkpoints/i-tauri/mut.py src/desktop/body.ts ', await Submenu.new({ text: "Wardrobe", items: wardrobe.items })' '' scripts/cat-tests/wardrobe-desktop-menu.test.mjs
cd ..
```

Expected: `body.ts |  | # pass 3 # fail 1`.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/core/wardrobemenu.ts windows/src/desktop/body.ts windows/src/cat/desktoptrip.ts windows/src/island/desktop.ts windows/src/island/island.ts windows/scripts/cat-tests/wardrobe-desktop-menu.test.mjs
git commit -F - <<'MSG'
feat(wardrobe): a Wardrobe submenu in the desktop cat's menu

The shared builder makes the 18 choices in groups with a tick on the stored one; a pick goes to the island's page, which stores it, applies it and tells the desktop window how the cat looks. Open the notch, Send home and Size are as they were.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

### Task 10: The island cat's right-click menu

**Agent:** `nm-implementer-deep` (Sonnet 5.5, high), **trigger 1**: a native menu in a window that is click-through, non-activating, collapses when the pointer leaves it, and is a layer-shell surface on Linux. Load `superpowers:systematic-debugging` too. The code is given and the tests pin it; the agent's job is to make the same text build, to read the island's mouse and fsm code once more for anything the menu could disturb (the hover, the cursor poll's `mouseLeft`, a press during the greeting), and to report what only the real build can show. It never starts the Tauri app.

**Files:**
- Create: `windows/src/cat/menuhit.ts`
- Modify: `windows/src/island/island.ts`
- Test: `windows/scripts/cat-tests/wardrobe-island-menu.test.mjs`

**Interfaces:**
- Consumes: `core/wardrobemenu.ts` (`buildWardrobeItems`, `tickWardrobe`, `WardrobeItems`), `display.ts` (`withOutfit`), `core/layout.ts` (`catClickTarget`, `Circle`), the island's `botCircle()`, `bot2Circle()`, `greetingShown()`, `uploadActive`, `State.desktopNotchEmpty`, `WardrobeClock.sync`.
- Produces: `cat/menuhit.ts`: `interface MenuScene { mode: string; greeting: boolean; upload: boolean; desktopOut: boolean; bot: Circle; bot2: Circle | null }`, `wardrobeMenuHit(x, y, scene): boolean` (true on a big cat the island is showing; never while hidden, in the greeting or the drop sequence; cat 1 never while it is out on the desktop). In `island.ts`: a `contextmenu` listener on the island element that opens the menu (a menu with only Wardrobe in it, built once) and prevents the default, only on a big cat; a right press (`button === 2`) on a big cat returns before `pressed` (it is not also a click); a pick stores through `withOutfit`, saves and calls `wardrobe.sync()`. Every left press, click and drag out of the notch is the code it was.

- [ ] **Step 1: Write the test**

```bash
cat > windows/scripts/cat-tests/wardrobe-island-menu.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { wardrobeMenuHit } from "../../src/cat/menuhit.ts";

// The island cat's right-click menu (sub-project I): where it opens is pure and replayed here; what the window does with the event is pinned by source (it needs a Tauri window).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const scene = (o = {}) => ({ mode: "compact", greeting: false, upload: false, desktopOut: false, bot: { cx: 100, cy: 20, r: 12 }, bot2: null, ...o });

test("a right-click opens the menu on the big cat in the compact and the open island, and nowhere else", () => {
  assert.equal(wardrobeMenuHit(100, 20, scene()), true);
  assert.equal(wardrobeMenuHit(111, 20, scene()), true, "inside the circle");
  assert.equal(wardrobeMenuHit(113, 20, scene()), false, "just outside");
  assert.equal(wardrobeMenuHit(100, 20, scene({ mode: "expanded" })), true);
  assert.equal(wardrobeMenuHit(300, 20, scene()), false, "off the cat");
  assert.equal(wardrobeMenuHit(Number.NaN, 20, scene()), false, "a point that is not a number hits nothing");
});

test("not while the island is hidden, the greeting or the drop sequence owns it, and not at the empty spot of a cat that is out on the desktop", () => {
  assert.equal(wardrobeMenuHit(100, 20, scene({ mode: "hidden" })), false);
  assert.equal(wardrobeMenuHit(100, 20, scene({ greeting: true })), false);
  assert.equal(wardrobeMenuHit(100, 20, scene({ upload: true })), false);
  assert.equal(wardrobeMenuHit(100, 20, scene({ desktopOut: true })), false);
});

test("Two cats: both cats open it, where the circles overlap the nearer cat's is the click, and a cat that is out leaves cat 2's menu", () => {
  const two = { bot: { cx: 80, cy: 20, r: 12 }, bot2: { cx: 100, cy: 20, r: 12 } };
  assert.equal(wardrobeMenuHit(70, 20, scene(two)), true, "cat 1");
  assert.equal(wardrobeMenuHit(110, 20, scene(two)), true, "cat 2");
  assert.equal(wardrobeMenuHit(90, 20, scene(two)), true, "the overlap");
  assert.equal(wardrobeMenuHit(70, 20, scene({ ...two, desktopOut: true })), false, "cat 1 is on the desktop: its spot is empty");
  assert.equal(wardrobeMenuHit(110, 20, scene({ ...two, desktopOut: true })), true, "cat 2 is still in the notch");
});

test("the island opens the menu on a right-click on a big cat, a right press there is not also a click, and every other press and the drag out are as they were", () => {
  const i = source("island/island.ts");
  assert.match(i, /this\.islandEl\.addEventListener\("contextmenu", \(e\) => \{\s*if \(!this\.onBigCat\(e\.clientX, e\.clientY\)\) return;\s*e\.preventDefault\(\);\s*void this\.showWardrobeMenu\(\);\s*\}\);/);
  assert.match(i, /if \(e\.button === 2 && this\.onBigCat\(x, y\)\) return;\s*if \(e\.button === 0 && this\.desktop\?\.canCarry && !State\.desktopNotchEmpty && State\.mode !== "hidden" && !this\.greetingShown\(\) && !this\.uploadActive && this\.isBotHit\(x, y\)\) \{\s*this\.press\.press\(x, y\);\s*this\.pressAction = \(\) => this\.pressed\(x, y\);\s*return;\s*\}\s*this\.pressed\(x, y\);/, "the left press, the click and the drag out are the lines they were");
  assert.match(i, /wardrobeMenuHit\(x, y, \{ mode: State\.mode, greeting: this\.greetingShown\(\), upload: this\.uploadActive, desktopOut: State\.desktopNotchEmpty, bot: this\.botCircle\(\), bot2: this\.cast\.second\?\.pill \? this\.bot2Circle\(\) : null \}\)/);
  assert.match(i, /items: \[await Submenu\.new\(\{ text: "Wardrobe", items: wardrobe\.items \}\)\]/, "only Wardrobe is in it for now");
  assert.match(i, /await tickWardrobe\(parts\.wardrobe, State\.settings\.cat\.outfit\);\s*await parts\.menu\.popup\(\);/);
  assert.match(i, /private pickOutfit\(id: OutfitId\): void \{\s*State\.settings\.cat = withOutfit\(State\.settings\.cat, id\);\s*void Bridge\.saveSettings\(State\.settings\);\s*this\.wardrobe\.sync\(\);\s*\}/);
  assert.equal((i.match(/Menu\.new\(/g) || []).length, 1, "one menu, built once");
});

test("the island's window may show a menu: core:default holds the menu permission", () => {
  const cap = fs.readFileSync(new URL("../../src-tauri/capabilities/default.json", import.meta.url), "utf8");
  assert.match(cap, /"windows": \["island", "settings"\]/);
  assert.match(cap, /"core:default"/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run:

```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/wardrobe-island-menu.test.mjs 2>&1 | grep -E "^# (pass|fail)|ERR_MODULE_NOT_FOUND" | sort -u
cd ..
```

Expected: `ERR_MODULE_NOT_FOUND` and `# fail 1`.

- [ ] **Step 3: Write the hit test**

```bash
cat > windows/src/cat/menuhit.ts <<'EOF'
// Where a right-click opens the island cat's menu (sub-project I): on a big cat the island is showing, and nowhere else. Pure: the circles are the island's, in its window's px. The press that
// opens the menu is the right button's; a left press, a click and a drag out of the notch are decided elsewhere (pressdrag.ts) and are not touched by this.

import { catClickTarget } from "../core/layout.ts";
import type { Circle } from "../core/layout.ts";

/** What the island is showing at the moment of the right-click. */
export interface MenuScene {
  /** The island's mode (`hidden`, `compact` or `expanded`). */
  mode: string;
  /** The launch greeting's canvas is up: it draws its own cat. */
  greeting: boolean;
  /** The drop sequence owns the island. */
  upload: boolean;
  /** The big cat's spot in the notch is empty: the desktop cat is out (cat 2 in Two cats mode is still there). */
  desktopOut: boolean;
  /** The big cat's circle, and cat 2's in Two cats mode (null otherwise). */
  bot: Circle;
  bot2: Circle | null;
}

/** Whether a right-click at (x, y) is on a big cat the island is showing. In Two cats mode a click where the circles overlap is the nearer cat's, as for a press. */
export function wardrobeMenuHit(x: number, y: number, s: MenuScene): boolean {
  if (s.mode === "hidden" || s.greeting || s.upload) return false;
  const hit = catClickTarget(x, y, s.bot, s.bot2);
  return hit === 2 || (hit === 1 && !s.desktopOut);
}
EOF
```

- [ ] **Step 4: Open the menu from the island**

The right press on a big cat is held back from `pressed` (it used to slap the cat in the open island or open the compact one; the menu replaces that for the right button only); the `contextmenu` event then opens the menu. The left press, the click and the drag out are the lines they were: the test pins the whole `if` block as it is.

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

i = "windows/src/island/island.ts"
edit(i, '''import { cleanCatBlock } from "../cat/display";''', '''import { cleanCatBlock, withOutfit } from "../cat/display";''')
edit(i, '''import { PressDrag } from "../cat/pressdrag";
''', '''import { PressDrag } from "../cat/pressdrag";
import { wardrobeMenuHit } from "../cat/menuhit";
import type { OutfitId } from "../cat/wardrobe";
import { Menu, Submenu } from "@tauri-apps/api/menu";
import { buildWardrobeItems, tickWardrobe } from "../core/wardrobemenu";
import type { WardrobeItems } from "../core/wardrobemenu";
''')
edit(i, '''      const x = e.clientX, y = e.clientY;
      if (e.button === 0 && this.desktop?.canCarry''', '''      const x = e.clientX, y = e.clientY;
      // A right press on a big cat opens its menu (the contextmenu event below) instead of acting as a click. Every other press is as it was.
      if (e.button === 2 && this.onBigCat(x, y)) return;
      if (e.button === 0 && this.desktop?.canCarry''')
edit(i, '''    // A move with the primary button up means the release was lost''', '''    // Right-click on a big cat (sub-project I): a native menu with only Wardrobe in it. Anywhere else the page keeps what it did.
    this.islandEl.addEventListener("contextmenu", (e) => {
      if (!this.onBigCat(e.clientX, e.clientY)) return;
      e.preventDefault();
      void this.showWardrobeMenu();
    });
    // A move with the primary button up means the release was lost''')
edit(i, '''  /** What a press on the island does:''', '''  /** A point of the island window is on a big cat the island is showing: the main cat, or cat 2 in Two cats mode (cat/menuhit.ts). */
  private onBigCat(x: number, y: number): boolean {
    return wardrobeMenuHit(x, y, { mode: State.mode, greeting: this.greetingShown(), upload: this.uploadActive, desktopOut: State.desktopNotchEmpty, bot: this.botCircle(), bot2: this.cast.second?.pill ? this.bot2Circle() : null });
  }

  /** The island cat's right-click menu, built once and reused (a native menu's items are resources in Rust that nothing frees): only Wardrobe for now. */
  private wardrobeMenu: Promise<{ menu: Menu; wardrobe: WardrobeItems }> | null = null;

  private async showWardrobeMenu(): Promise<void> {
    this.wardrobeMenu ??= (async () => {
      const wardrobe = await buildWardrobeItems((id) => this.pickOutfit(id));
      return { menu: await Menu.new({ items: [await Submenu.new({ text: "Wardrobe", items: wardrobe.items })] }), wardrobe };
    })();
    let parts: { menu: Menu; wardrobe: WardrobeItems };
    try { parts = await this.wardrobeMenu; } catch { this.wardrobeMenu = null; return; }
    await tickWardrobe(parts.wardrobe, State.settings.cat.outfit);
    await parts.menu.popup();
  }

  /** A pick of the island cat's Wardrobe submenu: the same choice as Settings → Wardrobe, stored once and applied at once. */
  private pickOutfit(id: OutfitId): void {
    State.settings.cat = withOutfit(State.settings.cat, id);
    void Bridge.saveSettings(State.settings);
    this.wardrobe.sync();
  }

  /** What a press on the island does:''')
EOF
```

- [ ] **Step 5: Run the test, the type check and the whole suite**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
node --experimental-strip-types --test scripts/cat-tests/wardrobe-island-menu.test.mjs 2>&1 | grep -E "^# (pass|fail)"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
cd ..
```

Expected: `tsc exit 0`, `# pass 5`, `# fail 0`, then `ℹ tests 423`, `ℹ pass 423` and `ℹ fail 0` (`desktop-island.test.mjs` still pins the press, the click and the drag out).

- [ ] **Step 6: Prove it bites**

Run (a hit test that forgets the cat that is out on the desktop):

```bash
cd windows
python3 ../.claude/checkpoints/i-tauri/mut.py src/cat/menuhit.ts 'hit === 2 || (hit === 1 && !s.desktopOut)' 'hit !== 0' scripts/cat-tests/wardrobe-island-menu.test.mjs
cd ..
```

Expected: `menuhit.ts | hit !== 0 | # pass 3 # fail 2`.

- [ ] **Step 7: Report what only the real build can show**

Write into the ledger, and in the message to the main session, which of these the code could not prove, so that the owner's Windows and Linux checks (below) cover them: the menu pops up at the pointer from a click-through, non-activating window; the island does not collapse under the menu while the pointer moves onto it (and what it does after a pick); a right-click while the compact island is a thin strip; GNOME's Wayland session and a layer-shell compositor; a right-click on the second cat. If a read of `island.ts`'s fsm and cursor code finds a way for the menu to be dismissed by the island's own collapse, say where, but do not change the code: that is a question for the main session.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/src/cat/menuhit.ts windows/src/island/island.ts windows/scripts/cat-tests/wardrobe-island-menu.test.mjs
git commit -F - <<'MSG'
feat(wardrobe): a right-click menu on the island's big cat

A native menu with only Wardrobe in it opens on a right-click on a big cat the island is showing, and nowhere else; a right press on the cat is no longer also a click. The left press, the click and the drag out of the notch are as they were, and a pick is stored and applied at once.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
```

# Stage 5: the docs, the site and the final checks

### Task 11: The docs, the site bundle and the final checks

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Modify: `windows/README.md`, `CLAUDE.md`, `ARCHITECT.md`, `docs/assets/cats.js` (rebuilt)

**Interfaces:**
- Consumes: everything above.
- Produces: the docs say what the wardrobe is, where it lives and what differs from the Mac (no global shortcut; Wardrobe is its own Settings card); the site's committed bundle is what a fresh build makes.

- [ ] **Step 1: Write the docs**

One script edits `windows/README.md` (the "Using it" table, a "The wardrobe" paragraph under "Your cat", the "Testing the cats" text, and "What's different from the Mac version"), `CLAUDE.md` (one bullet, after the desktop cat's) and `ARCHITECT.md` (one bullet in the architecture list). It changes no other line.

```bash
python3 - <<'EOF'
def edit(path, find, replace):
    s = open(path).read()
    assert s.count(find) == 1, (path, find[:60], s.count(find))
    open(path, "w").write(s.replace(find, replace))

r = "windows/README.md"
edit(r, '''| `Esc` | Closes the island |
| Tray icon |''', '''| Right-click a big cat in the island | A **Wardrobe** menu: Auto, None and 16 outfits, with a tick on the one you have. The same menu is in the desktop cat's right-click menu |
| `Esc` | Closes the island |
| Tray icon |''')
edit(r, '''
## Claude Code
''', '''
**The wardrobe.** **Settings… → Wardrobe** (its own card, right under Cat) dresses the big cats: 16 outfits drawn in code (five seasonal, five everyday, four cat extras and two that belong to Shrimpy and Momo), plus **None** and **Auto**. One outfit at a time, worn by every big cat at every size: the island's main cat (compact and open, the compact notch's Ø20 cat too), both cats of Two cats mode, each agent's big cat and the desktop cat. The small cats (the pills, the mini row, the grid) and the subagent kittens stay bare, whatever their size. Auto follows the local date on the northern calendar: Dec 31 to Jan 2 a party hat, Dec 1 to 26 a Santa hat, Oct 1 to Nov 1 a witch hat, Good Friday to Easter Monday bunny ears, Jun 21 to Aug 31 sunglasses, anything else nothing; it looks again at the next local midnight with one timer that exists only while the choice is Auto (nothing polls). Point at a tile to see it on the live preview; the coat picker beside the preview shows an outfit on any of the 16 coats and stores nothing. Settings stores one value, `outfit`, in the `cat` block of `settings.json`. There is no global shortcut for it here (the Mac has ⌃⌥G): Windows and Linux have no global shortcuts, so the Settings card and the two right-click menus do it.

## Claude Code
''')
edit(r, '''
`npm run check:cat` (Node 22.6 or newer) runs the cat's checks in plain Node''', '''
The wardrobe (sub-project I) is ported from the same contract: `src/cat/wardrobe.ts` (the 18 IDs, `cleanWardrobeSettings`, `easterOf`, `autoOutfitFor`, `resolveOutfit`, `outfitWorn`) and `src/cat/outfit.ts` (`outfitAnchors`, `outfitGeometry`, `outfitRoom`, `outfitDigest`), replayed from `wardrobe-cases.json` (all 256 outfit and coat pairs at four sizes), painted by `cat/outfitdraw.ts` at the contract's three slots from `cat/renderer.ts`; `BotEngine.outfit` is set only by the island's two big cats and the desktop cat. The `outfit` key of the `cat` block is cleaned by `cleanCatBlock` and its Rust twin `clean_wardrobe_settings`; `island/wardrobe.ts` is Auto's one-shot; `settings/wardrobe.ts` and `cat/wardrobeui.ts` are the Settings card; `core/wardrobemenu.ts` builds the Wardrobe submenu of the island cat's and the desktop cat's right-click menus. `?dev` has a **Wardrobe** panel: 16 outfits on 16 coats, the compact notch's Ø20 and Ø18 cat in their strips, the head turned each way, the neck outfits over each collar style, the desktop sizes and a Two cats pair, and Auto for any date; the bench in the Desktop cat panel also measures a frame with the witch hat on. The site's cats are not dressed (the site passes no outfit), but its bundle contains the renderer, so it is rebuilt with it.

`npm run check:cat` (Node 22.6 or newer) runs the cat's checks in plain Node''')
edit(r, '''- The desktop cat has no global shortcut here''', '''- The wardrobe has no global shortcut here (the Mac's ⌃⌥G, off by default): Windows and Linux have no global shortcuts. Settings… → Wardrobe, the island cat's right-click menu and the desktop cat's right-click menu do the same. In Settings, Wardrobe is its own card right under Cat (the Mac puts it inside its Cat section).
- The desktop cat has no global shortcut here''')

c = "CLAUDE.md"
edit(c, '''- `docs/index.html`, `docs/testers.html`, `docs/site.css`''', '''- Sub-project I on Windows/Linux (the wardrobe): `windows/src/cat/wardrobe.ts` (the 18 IDs, `cleanWardrobeSettings`, Auto's `autoOutfitFor`, `resolveOutfit`, `outfitWorn`) and `outfit.ts` (`outfitAnchors`, `outfitGeometry`, `outfitRoom`, `outfitDigest`) port `design/prototype/cat-core.js`'s wardrobe, tested against `tests/fixtures/cat/wardrobe-cases.json`; `cat/outfitdraw.ts` paints the shapes at the contract's slots from `cat/renderer.ts` (`DrawOptions.outfit`), and only the views that show a big cat set `BotEngine.outfit` (the island's two big cats, the desktop cat, the greeting's settled cat; **never a mini cat, a kitten, the Display preview or the drop view**). Stored as the `outfit` key of the `cat` block (`cat/display.ts` `cleanCatBlock`, Rust `clean_wardrobe_settings` in `cat_settings.rs`); `island/wardrobe.ts` is Auto's one-shot at midnight, `settings/wardrobe.ts` the Settings card, `core/wardrobemenu.ts` the Wardrobe submenu of the island cat's and the desktop cat's right-click menus. No global shortcut (the Mac has one). `?dev` has a Wardrobe panel (`cat/devwardrobe.ts`).
- `docs/index.html`, `docs/testers.html`, `docs/site.css`''')

a = "ARCHITECT.md"
edit(a, '''
## Code map (graphify)
''', '''   - **Sub-project I on Windows/Linux:** the `cat` block's `outfit` key is cleaned with the rest of the block by `cat/display.ts` and `clean_cat_block` (`clean_wardrobe_settings`). `cat/wardrobe.ts` and `cat/outfit.ts` port the contract's rules and shapes; `cat/outfitdraw.ts` paints them and `cat/renderer.ts` calls it at the three slots (behind, neck, top) when `DrawOptions.outfit` is set, which `BotEngine.outfit` does for the island's main cat, cat 2 and the desktop cat only. `island/wardrobe.ts` resolves the stored choice for today (`State.outfit`) and is Auto's one-shot midnight timer; the desktop cat's page is told the outfit in `BodyLook`. `settings/wardrobe.ts` is the Settings card, `core/wardrobemenu.ts` the shared Wardrobe submenu of the two right-click menus. There is no global shortcut.

## Code map (graphify)
''')
EOF
```

- [ ] **Step 2: Rebuild the site's bundle**

The site's live cats are the Windows engine, bundled from `windows/src/site/main.ts` (it imports the renderer, which now knows about outfits; the site passes none, so its cats are drawn as before). `check-site.sh` fails on a stale bundle, so rebuild it **with the site's own config, never `npm run build`**:

```bash
bash scripts/check-site.sh 2>&1 | head -2
cd windows
npx --no-install vite build --config vite.site.config.ts 2>&1 | tail -4
cd ..
git status --short docs
bash scripts/check-site.sh 2>&1 | tail -3
```

Expected: the first `check-site.sh` prints `✗ docs/assets/cats.js is not what a fresh build makes: run  cd windows && npx --no-install vite build --config vite.site.config.ts  and commit it` (the renderer changed); the build prints `✓ built in` with `cats.css` and `cats.js` sizes; `git status` shows ` M docs/assets/cats.js` and nothing else under `docs` (`cats.css` does not change: the theme's outfit colours were already in it); the last `check-site.sh` prints three `✓` lines: `docs/assets/cats.js and cats.css are what a fresh build makes`, `docs: no outside request, no cookie, alt text everywhere, the names as they should be` and `docs/assets/img: no outside address in any picture or its metadata`.

- [ ] **Step 3: The final checks**

Run:

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)|^✖"
npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1
cd ..
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two generator"
node scripts/check-fixtures-additive.mjs 5f9051c 2>&1 | tail -1
bash scripts/test-theme.sh 2>&1 | tail -1
bash scripts/check-no-leftovers.sh >/dev/null 2>&1; echo "leftovers exit $?"
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/i-tauri 2>&1 | grep -E "^test result|^error|^warning" || echo "image missing or the daemon is down: owed"
```

Expected: `tsc exit 0`; `ℹ tests 423`, `ℹ pass 423`, `ℹ fail 0`; `All AI UI checks passed`; `All Claude Code UI checks passed`; `# tests 319`, `# pass 319`, `# fail 0`, `✓ 16 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`; `✓ fixtures changed only by addition since 5f9051c`; `✓ 3 theme files match shared/theme.json`; `leftovers exit 0`; and `test result: ok.` for the app's library and the relay with no `error` and no `warning` (or the owed line). Nothing under `design/`, `shared/`, `tests/` or `docs/CAT-CONTRACT.md` changed: `git diff --stat notchmeow/rebrand... -- design shared tests docs/CAT-CONTRACT.md scripts` prints nothing.

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and i/tauri-wardrobe
git add windows/README.md CLAUDE.md ARCHITECT.md docs/assets/cats.js
git commit -F - <<'MSG'
docs(wardrobe): the Windows and Linux wardrobe, and the site bundle rebuilt

The README, CLAUDE.md and ARCHITECT.md say where the wardrobe lives and what differs from the Mac (no global shortcut; Wardrobe is its own Settings card); the site's committed bundle is rebuilt with the renderer that now knows about outfits.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

## Checkpoint 3: the owner signs off

Stop here. Send the owner: the commits, every count and gate of Step 3 above, the three checkpoints' pictures, the Rust runs (or that they are owed), Task 10's report of what only the real build can show, and the checklists below. After the owner's OK, dispatch `nm-reviewer-deep` over the whole branch (`git diff notchmeow/rebrand...HEAD`), then ping the main session with its findings.

## The owner's real-build checks

What no test and no headless browser can show. Do them on a built app (`cd windows && npm run tauri dev`, or the tester build), **one list for Windows and one for Linux** (KDE or another layer-shell compositor, and GNOME's Wayland session).

**Windows**
1. **Settings… → Wardrobe.** The card sits under Cat; point at a tile: the preview changes; click Crown: the island's cat wears a crown at once, and so does the desktop cat if it is out; restart the app: it is still Crown. Pick **None**, then **Auto**; the Auto tile's label names today's outfit.
2. **Every outfit on the island.** Compact (the notch strip at the top of the screen) and open: each of the 16 reads, the whiskers are in front, the badge and the state glow are where they were. In **Two cats** both cats wear it; in **A cat for each agent** the focused agent's cat wears it; the pills' small cats and the 2 by 2 grid stay bare; subagent kittens (run a Claude Code task that starts one) stay bare.
3. **The desktop cat at Small, Medium and Large**, with and without a collar and with kittens: the outfit follows the cat when it is dragged and when it flies into the notch for an approval and back.
4. **Right-click the island cat** (compact and open): a menu with only **Wardrobe**; its submenu has Auto, None and 16 outfits in groups with a tick on the current one; a pick applies at once. The menu does not close the moment it opens; a right-click does not slap the cat or open the island; **a left click, three clicks (dizzy) and a drag out of the notch work exactly as before.** Right-click on cat 2 in Two cats mode. No menu on an empty place, while the greeting plays, while the island is hidden, or on the notch's empty spot while the cat is out on the desktop.
5. **Right-click the desktop cat:** Open the notch, Send home, Size and **Wardrobe** with the tick.
6. **Auto on a faked date.** There is no date override in the app (the Mac has a Debug-only one): set the system date to Dec 24 (Santa hat), Oct 31 (witch hat), Jul 4 (sunglasses), the Good Friday of the year (bunny ears) and Jan 1 (party hat), and restart the app each time (the `?dev` page's date field shows the same rules without that). **The midnight change:** with Auto chosen, set the clock to 23:59 on Dec 31 and wait: the cat changes to the party hat at midnight without a restart.
7. **CPU.** In Task Manager, with an outfit on and the island hidden (and with the desktop cat out and awake): the app idles as it did without one; the island hidden with the cat at home costs nothing.
8. **Never restyle:** the island, the pills, the cards and the other Settings rows look as they did.

**Linux** (the same eight, and)
9. **Layer-shell compositor (KDE Plasma, COSMIC, Hyprland, Sway):** the right-click menu opens over the island's top-layer surface at the pointer and takes the click; the desktop cat's menu too.
10. **GNOME's Wayland session:** the menus open (the windows are regular windows there); the desktop cat's position is the system's, as in H.
11. **X11:** the same as Windows.

# Parity with macOS

The Mac gets at least what this app gets. What differs, on purpose:

- **No global shortcut here.** The Mac's `wardrobe` action (⌃⌥G, off by default, cycling `auto`, `none` and the 16 outfits) is the Mac's extra; Windows and Linux have no global shortcuts. The README says so.
- **Settings.** The Mac's Wardrobe is a section of Settings → Cat after Display and Desktop; here, where Settings is one page of cards, it is its own card right under Cat.
- **The date override.** The Mac has a Debug-only one for the owner's real-build check; here the `?dev` page has a date field and the real-build check changes the system date.
- **The island cat's menu** is a native Tauri menu on the island's window (`Menu.popup`); the Mac's is an AppKit menu on its non-activating panel. Same entries.
- **Everything else is the same by contract:** the 18 IDs, the roles, the slots, the floors, the edge colour, Auto's rules and its one-shot, `none` costing nothing, the compact notch's Ø20 and Ø18 cat dressed, kittens and small cats bare, the desktop cat dressed at every size, the greeting's settled cat dressed.

# Open questions for the owner

Each has the plan's choice first (the answer is used until the owner says otherwise).

1. **Where is Wardrobe in Windows Settings?** (a) **Its own card right under Cat** (this plan; the page is one column of cards, and the Cat card is already long). (b) Inside the Cat card, after the Desktop switch.
2. **A right press on a big cat.** (a) **It opens the Wardrobe menu and is not also a click** (this plan; a right press used to slap the cat in the open island). (b) It opens the menu and acts as a click too.
3. **Which other views that show a cat stay bare?** (a) **The Display preview in Settings and the drop view's travelling cat stay bare** (this plan: no existing picture changes; the Wardrobe card's own preview is dressed). (b) Dress them too, so Settings shows what the island will.
4. **Does the desktop cat's outfit take the mouse?** (a) **No: the hit shape stays the head with its ears, the badge and the kitten slots, as in H** (this plan; a hat is decoration, and a click on it goes to the window under it). (b) Extend the hit shape to the outfit (a change to H's layout and tests).
5. **When is the greeting's cat dressed?** (a) **From the moment it has settled after its wave (`GT2.back1`, 3.25 s), or as the island folds if that comes first** (this plan). (b) Only once the island has folded into the notch. (c) From the first frame.

# Self-review notes

- **Spec coverage.** The 18 IDs and the clean-up (Tasks 1, 3); Auto's rules, Easter on date numbers and its one-shot (Tasks 1, 6); who wears it, by role, at every size (Tasks 4, 7); anchors, shapes, slots, floors, edge, room and the collar interplay (Tasks 2, 4); the storage in the block, TypeScript and Rust, kept at every save (Task 3); the Wardrobe section with the live preview, the Auto label and the coat picker that stores nothing (Task 8); the two right-click menus (Tasks 9, 10); no shortcut and the README (Task 11); the contact sheet at 16 by 16 with the Ø20 and Ø18 strips, the head turned and the collar strips (Task 5); the bench with an outfit on (Task 7); the site bundle (Task 11); the owner's checkpoints and the real-build checklists. Not here, on purpose: a Debug date override (the Mac's), a global shortcut, outfits on kittens, the small cats or the site's cats.
- **Placeholders.** None: every code step is a file or an edit script, every run step has its expected output.
- **Types.** `OutfitId`, `OutfitShape`, `OutfitOptions`, `WardrobeItems`, `BodyLook.outfit` and `outfitChoice`, `DesktopLook.outfit` and `DesktopHost.outfitChanged` are named the same in the tasks that define and use them (the dry run type-checks the whole sequence).
- **Review Focus.** Each of the five lines names its tests above.

# Dry run (2026-10-14)

The plan was dry-run in a throwaway clone of `notchmeow/rebrand` at `619b407`, with `windows/node_modules` cloned in: every task applied in order, as written, test first (red, then green) with the counts below, then the whole sequence again in a second fresh clone from the plan's own scripts and files.

- **TypeScript, all 11 tasks: dry-run.** `tsc` exits 0 after every task. `check:cat` goes 372 (the starting point) to 376, 383, 386, 393, 396, 404, 408, 414, 418, 423, with no failure. Every red run failed as the plan says (`ERR_MODULE_NOT_FOUND`, `does not provide an export named …`, or the counts) and every green run passed (4, 7, 13, 7, 3, 8, 4, 6, 4, 5 tests). Every "prove it bites" step failed the tests it names. The final gates pass: `check:ai`, `check:claude`, `test-cat-contract.sh` (319 tests, 16 fixture files), `check-fixtures-additive.mjs`, `test-theme.sh`, `check-no-leftovers.sh`; `check-site.sh` fails on the stale bundle before Task 11 Step 2 and passes after the rebuild.
- **Pictures, headless: dry-run.** The `?dev` Wardrobe panel (all five canvases and the readout), the prototype's panel beside it, the Settings card at 640 and 460 px (and a click on a tile and a change of the preview coat), the island in Two cats mode and A cat for each agent mode dressed, the desktop mock dressed at three sizes, the dressed greeting, the bench numbers (a frame with the witch hat on costs 0.02 to 0.04 ms more).
- **Rust, partly.** Docker was not running (`docker info` failed and the image is missing), so **`cargo-linux.sh` was not run and the settings.rs test was not compiled**. What was checked instead: `cat_settings.rs` as edited was built and tested in a scratch crate offline (`serde_json` 1.0.151 with `preserve_order`, as the app uses, the fixtures reached by the same relative path): all 17 of its tests pass, the two new ones included; `rustfmt` parses both edited files. Not dry-run: the new `settings.rs` test (it needs the whole crate), `cargo test --workspace`, the Windows build.
- **Not dry-run, and not provable headless:** every native menu (the island's and the desktop cat's), the right-click event in a click-through window, the window and the hit areas on Windows and Linux, layer-shell, the midnight change in a running app, CPU in Task Manager. They are Task 10's report and the owner's checklists.
- **What the dry run changed in the plan.** Six existing tests pin lines this plan changes (the block's key list in `display.test.mjs`, and one line each in `desktop-look`, `desktop-island`, `sites` and `two-cats`); their edits are in Tasks 3 and 7. A browser opened with `playwright-cli` refuses `file:` URLs, so the prototype is served by a second Vite (port 14614). `check-site.sh` does need the rebuild: the renderer is in the site's bundle.

## The owner's answers (2026-10-14)

The owner approved this plan with these answers:
- Settings' own big-cat previews (Main cat, Display mode) and the drop view's cat are **dressed**.
- The greeting's cat: the outfit **fades on after the cat settles** (about 3.25 s). Wardrobe is **its own section** under Cat in Settings.
- The right-click Wardrobe menu is on **both cats** in Two cats mode; a right-click opens the menu only (no tap or slap reaction).
- The desktop cat's hat **does not take clicks**: the click shape stays as today.
