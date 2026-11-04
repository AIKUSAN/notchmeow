# I-0 Wardrobe Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both apps what sub-project I (the wardrobe) needs from the shared contract before the app plans run: the 18 outfit IDs and their clean-up, Auto's calendar, who wears an outfit (the big-cat role, at every size, the compact notch included), where an outfit sits on a head (slots, floors, anchors, room) and the shapes of the 16 outfits, all in `design/prototype/cat-core.js` and pinned by one new fixture, `wardrobe-cases.json`; the outfits' colours in `shared/theme.json`; and the prototype's Wardrobe panel that draws it, which the owner approves at a checkpoint on a contact sheet of all 16 outfits on all 16 coats. The apps use none of it yet: that is the I-mac and I-tauri plans.

**Architecture:** One new section goes into the one plain script, above the end-of-core marker, reusing what is there (`layout`, `supPoints`, `earGeom`, `collarGeometry`, `mixHex`, `FLAT_FILL`, `COLLAR_MIN`, `EAR_FIT`, `isPlain`). Everything is a new name: `PASSES`, `COLLAR_STYLES`, `collarGeometry` and every existing fixture line stay exactly as they are, so both apps stay green on `notchmeow/rebrand` until their I plans land. An outfit is a short list of shapes (`poly`, `curve`, `ellipse`) in head-local px with colour roles; the renderers only paint them. `scripts/gen-cat-fixtures.mjs` gains one builder for one new file, grown a task at a time; `scripts/check-fixtures-additive.mjs 5f9051c` proves that no existing line moved. The theme gains an `outfits` group (`scripts/gen-theme.mjs` writes it into the three generated files, and the site's bundled CSS is rebuilt). The prototype gets a Wardrobe panel driven by the core and a hook in `drawCat` at the three slots; the owner's pictures are taken headless with `playwright-cli` against a local static server, so no browser login is involved.

**Tech Stack:** JavaScript (one file for a browser and Node 22), `node:test` and `node:assert` (no npm packages), Bash, Python 3 for the patches, `playwright-cli` with its cached browsers for the pictures.

**Spec:** `docs/superpowers/specs/2026-10-14-wardrobe-design.md` (the whole of it: "Outfits", "Auto rules", "Who wears it", "Contract", "Drawing and fitting", "Testing", "Rounds" step 1; the owner's answers of 2026-10-14 are at its end). It extends `docs/CAT-CONTRACT.md` and `design/prototype/cat-core.js` as merged by A, B and H (plan `2026-10-08-h0-desktop-cat-contract.md` is the format). Read the whole spec before starting.

**Base:** branch `i0/wardrobe-contract`, created from `notchmeow/rebrand` at `5f9051c` or later, with this plan and the spec already committed to `notchmeow/rebrand`. The cat contract must still be the one from `5f9051c` (288 tests, 15 fixtures): the additive check compares with that commit. This plan touches no app code under `NotchBuddy/` or `windows/` except the two generated theme files and the site's rebuilt `docs/assets/cats.css`. **It changes no pixel and no behaviour in either app** (the new `Theme.Outfits` enum and `THEME.outfits` are new names nobody reads yet). In the prototype page it adds one panel, one parameter family on `drawCat` and the big-cat calls' `outfit` and `role`; no existing panel changes its look when no outfit is worn.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed again under "Open questions for the owner".

- **Only new names.** Change no existing constant or function that the apps copy or pin: `PASSES`, `COLLAR_STYLES`, `COLLAR_MIN`, `collarGeometry`, `earFit`, `EAR_FIT`, `cleanCatSettings`, `cleanDisplaySettings`, `cleanDesktopSettings` and the rest. `tests/cat/fixtures.test.mjs`'s file list gains only `wardrobe-cases.json`. Every existing fixture stays byte-identical: `node scripts/check-fixtures-additive.mjs 5f9051c` must pass. The Mac cat tests (`scripts/test-cat-*.sh`) and the Windows `npm run check:cat` must pass unchanged.
- **18 selection IDs, frozen** (they are stored), in this order: `auto`, `none`, `partyhat`, `santahat`, `witchhat`, `bunnyears`, `sunglasses`, `beanie`, `bow`, `scarf`, `roundglasses`, `crown`, `bell`, `bandana`, `fishclip`, `flower`, `shrimpclip`, `blossomclip`. Lowercase letters only. An unknown stored value, or anything that is not exactly one of the 18 strings, is `auto`; the default is `auto`. The action ID `wardrobe` is frozen too. The two cats' own clips (`shrimpclip`, `blossomclip`) are open to every coat.
- **Who wears it (the owner's answer, 2026-10-14):** the big cat is always dressed, at every size, the compact notch included. "Big cat" is a role: the island's main cat (compact and open), both cats in Two cats mode, each agent's big cat in A cat for each agent mode, and the desktop cat. Bare: kittens and the small cats (the pills' cats, the mini row and the grid), whatever their diameter. `outfitWorn(role)` takes the role, never the diameter. The compact big cat is Ø20 in the 32-point notch strip and Ø18 in the 24-point strip of a screen without a notch (`islandBase`/`collapsePose` in `cat-core.js`: `hb` ends at `20/1.34`), and every outfit must still read there: the floors `OUTFIT_MIN` must cover that size.
- **Storage:** macOS `UserDefaults` key `cat.outfit`; Windows and Linux the `outfit` key of the `cat` block. `cleanWardrobeSettings(raw)` is a clean-up of its own, so `settings-cases.json`, `display-cases.json` and `desktop-cases.json` stay byte for byte.
- **Auto (spec "Auto rules"):** the local calendar date on the northern calendar, first match wins, in this order: Dec 31 to Jan 2 `partyhat`; Dec 1 to Dec 26 `santahat`; Oct 1 to Nov 1 `witchhat`; Easter minus 2 days to plus 1 day `bunnyears` (Gregorian Easter by the Meeus/Jones/Butcher computation, the difference counted on calendar-date numbers); Jun 21 to Aug 31 `sunglasses`; anything else no outfit. No setting, no hemisphere, no locale.
- **Slots (spec "Contract"):** `behind` (after `ears` in the behind pass: bunny ears), `neck` (front pass after the collar, before `whiskers`: scarf, bandana, bell) and `top` (after `neck`, before `whiskers`: hats, crown, glasses, clips, bow, flower). The front pass reads `foldEars`, collar, `outfit.neck`, `outfit.top`, `whiskers`, `badge`, `particles`, `balls`. `PASSES` stays as A-0 wrote it.
- **Fit (spec "Drawing and fitting"):** the geometry comes from the coat's own numbers (ear bases, eye frames, head outline), never from a coat list. Hats are narrower than the gap between the ear bases (the witch brim narrower than the ear spread); glasses follow the eye frames and turn with the face; clips, the bow and the flower sit at an ear base; the bell hangs from the collar (and from its own ring with the collar off); the scarf and the bandana cover the collar and still draw with it off; the collar is read and never changed. In the compact notch hats and bunny ears take the ear fit's room (`outfitRoom`): shortened to it, held at a floor and not hidden.
- **Colours:** every shape's colour is a role, and every role is a key of the `outfits` group of `shared/theme.json` (generated into `Theme.generated.swift`, `theme.generated.css` and `theme.generated.ts`), or `edge`, which stands for the theme's `edgeLight` or `edgeDark` by the coat's head luminance. A coat is never recoloured.
- **Tolerance:** fixtures store 12 significant digits and apps compare within **1e-9**. There are no pixel tests. A fixture number of 1000 or more is a whole number or a half, or the 12 digits would cost more than the tolerance (so the digest holds a mean point, not a sum).
- **`cat-core.js` is the tie-breaker:** numbers in, numbers out: no canvas, no DOM, no clock, no `Math.random`.
- **Never restyle what ships.** The prototype is the visual source of truth for new character work. Its existing panels stay as they are: the Wardrobe panel is new, with new CSS rules, and `drawCat` gains an optional `outfit` and `role`.
- **Node standard library only, no npm packages;** Node 22 or newer. Same code style as the core: compact one-liners with a comment above, plain commented code elsewhere.
- **Every outfit's drawing is NotchMeow's own.** Never read or copy upstream Coucou's wardrobe code or art (reserved assets, with the names Coucou and Mochi and their pop sound): nothing of it is opened, ported or traced. The only borrowed ideas are the Auto mode that follows the calendar, the fall-back to Auto and the preview. The names Coucou and Mochi appear in no new code (`mocha` is a coat). `scripts/check-no-leftovers.sh` must stay green.
- **Commits:** local only, never pushed, one per task, with `git commit -F <file>` and the trailer `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` (or the model that did the task).

## SUBAGENT RULES

Every subagent and the controller follow these; the controller puts them in each brief.

- **Never launch, quit or replace a NotchMeow app or the Tauri app.** The work is files, Node tests, a static page in a headless browser and, for the theme check, one `swiftc` test program.
- **Install and download nothing.** `npx --no-install` only; never `npm install`, `npm run build` or `npm run dev`; `playwright-cli` uses the browsers already cached. `windows/node_modules` is already there (Task 0 checks).
- **Delete with `trash`, never `rm -rf`,** and give scratch files unique names (the prefix `i0-`). Scratch files live in `${TMPDIR:-/tmp}/i0-work` and pictures in `${TMPDIR:-/tmp}/i0-shots`, outside the repository. The static server listens on `127.0.0.1` only, and every server and browser a task starts is stopped before the task ends, by the PID saved when it was started.
- **Never run the real `claude` binary, never read tokens, never sign in.** The pictures need no login: the page is a local file served over `127.0.0.1`.
- **Never write to `~/Library/Logs/NotchMeow/` or to an app's preferences.** Nothing in this plan touches `UserDefaults`.
- **Never read or copy upstream's wardrobe** (Coucou's code, art or names, reserved). Nothing in this plan needs it: every shape is given in full below.
- **Commit only in a task's commit step, and never push.**
- **Subagents are the `nm-*` agents** (Haiku 5.5 first; Sonnet 5.5 only on a named CLAUDE.md trigger, named in the ledger; never Opus or Fable); the table below says which one runs each task.
- **Every shell block passes `bash -n` before it is run.**
- **If a command is denied by a permission prompt, or a find text fails (an anchor that occurs other than once), stop and report it.** Do not look for a workaround.

## Review Focus

The spec says what the rules are. It is silent on these inputs, and each would bite a person (or a port) first. Each line names its test.

1. **A hostile stored outfit:** the wrong case (`Bow`), padding or a newline, a number, an object, a list, the keys `__proto__`, `constructor` and `toString`, a settings block that is not an object. Expected: `auto`, never a throw, nothing read from the prototype chain. Tests: Task 1 "a stored outfit…" and the fixture's `clean` and `settings` rows.
2. **Auto on awkward dates:** 29 February in a leap and in a common year, dates that are not dates (month 13, 31 April, a year 0 or 10000, a text year), the new year's three days across two years, Easter in March (the earliest, 22 March) and in late April (the latest, 25 April), a year before the Gregorian calendar, and a day count that daylight saving could shift. Expected: `none` for a bad date, the five rules at every boundary, and four bunny-ear days in every year from 1583 to 2600, found by walking the calendar and not by the contract's own day count. Tests: Task 1 "Auto: every boundary…", "Auto: Good Friday to Easter Monday…" and "Auto: dates that are not dates…".
3. **The compact notch:** the Ø20 cat in the 32-point strip and the Ø18 cat in the 24-point strip, on all 16 coats (Noodle's tall ears and Latte's low crown leave the least room). Expected: every outfit on every coat stays inside the strip (nothing above its top or below its bottom), a hat is shortened to the room and never below its floor, no stroke is thinner than the line floor, and every outfit still spans at least the span floor. Tests: Task 3 "the compact notch…" (on 2 sizes × 16 coats × 16 outfits) and the fixture's Ø18 and Ø20 digests.
4. **The head turned all the way:** a yaw of 0.6 and of 1.2 rad, a pitch, so that an eye is out of sight. Expected: the glasses flatten with the eyes and a lens whose eye is out of sight is not drawn, hats lean with the face, and nothing becomes NaN. Tests: Task 3 "the head turned…" and "what an outfit is made of…" (finite numbers on every coat, size and turn).
5. **Every collar style under the neck outfits, and the collar off:** the bell on the tag, the band, the kerchief and no collar, the scarf and the bandana over each. Expected: all three still draw, the bell hangs from the right point, the scarf is wider than the band and the bandana bigger than the kerchief, and `collarGeometry` is the same before and after. Tests: Task 3 "the collar…" and the fixture's `collars` rows.

---

## File Structure

| Path | Responsibility |
|---|---|
| `design/prototype/cat-core.js` | The contract. Three new blocks above the end-of-core marker: the IDs, Auto and who wears it (`OUTFIT_IDS`, `OUTFIT_NAMES`, `OUTFIT_GROUPS`, `OUTFIT_DRAWN`, `DEFAULT_OUTFIT`, `outfitIdOf`, `cleanWardrobeSettings`, `easterOf`, `autoOutfitFor`, `resolveOutfit`, `OUTFIT_ROLES`, `outfitWorn`); slots, floors and anchors (`OUTFIT_SLOTS`, `OUTFIT_ORDER`, `OUTFIT_MIN`, `outfitEdge`, `outfitRoom`, `outfitAnchors`); the shapes (`outfitGeometry`, `outfitDigest`). |
| `scripts/gen-cat-fixtures.mjs` | Gains one builder above the `@@BUILDERS` marker, `FILES['wardrobe-cases.json']`, which each task grows above its own marker. |
| `tests/fixtures/cat/wardrobe-cases.json` | The new fixture (generated: about 340 KB, under the 400 KB limit). |
| `tests/cat/wardrobe.test.mjs` | The self-checks (7, 5, 9, 1 and 1: 23) and the fixture replays (3), grown a task at a time. |
| `tests/cat/fixtures.test.mjs` | The file list gains `wardrobe-cases.json` (16 files). |
| `shared/theme.json`, `scripts/gen-theme.mjs`, `tests/theme/gen-theme.test.mjs` | The `outfits` group (38 colours) and its place in the generator and its tests. |
| `NotchBuddy/Sources/App/Theme.generated.swift`, `windows/src/theme.generated.css`, `windows/src/theme.generated.ts`, `docs/assets/cats.css` | Generated from the theme (the CSS also feeds the site's bundle, rebuilt in Task 4). |
| `design/prototype/notchmeow.html` | The Wardrobe panel (the chooser, the coat picker, the date for Auto, the preview, the 16 by 16 sheet, the compact rows, the head turned, the collar strips), the painter `owPaint`, and `drawCat`'s three slots. |
| `docs/CAT-CONTRACT.md`, `docs/THEME.md`, `CLAUDE.md`, `ARCHITECT.md` | One row each in the tables, a section "The wardrobe (I-0)", three decisions and the two pointer bullets. |
| `${TMPDIR:-/tmp}/i0-work/`, `${TMPDIR:-/tmp}/i0-shots/` | Scratch files and the owner's pictures. Outside the repository, never committed. |

The "prove it bites" idea of earlier plans is the red run of each task's first test step. **CI needs no change:** `scripts/test-cat-contract.sh`, which CI already runs, globs `tests/cat/*.test.mjs` and its `--check` covers every builder in the generator; `scripts/test-theme.sh` and `scripts/check-site.sh` cover the theme and the site.

**Order of tasks:** the rules and their fixtures one by one, each with its tests (1 the IDs, Auto and who wears it; 2 slots, floors and anchors; 3 the shapes), then the colours, the prototype, the pictures for the owner's checkpoint, then the docs.

0. Base checks and the work folder
1. The IDs, the clean-up, Auto and who wears it
2. Slots, floors and anchors
3. The shapes of the 16 outfits
4. The outfits' colours: the theme group and the site bundle
5. The prototype: the Wardrobe panel
6. Owner checkpoint: the pictures
7. Docs and the final checks

## Tasks and agents

CLAUDE.md: the lightest model that fits (the owner's answer of 2026-10-14: I-0 runs on **Haiku 5.5, medium**; the design work was in drafting this plan). Every task below gives every line of its code, its patches and its docs, so Tasks 0 to 4 and 7 are transcription: `nm-implementer-light` (Haiku 5.5, medium). Task 5 also gives its patch in full, but it loads a page in a headless browser and clicks through it, and Task 6 reads pictures and reports what they show, so both are `nm-implementer` (Haiku 5.5, high: visual checks). Each task is then reviewed by `nm-reviewer`; the whole branch by `nm-reviewer-deep` (Sonnet 5.5, trigger 4: a whole-branch review) after Task 7. If a step's expected output differs and the cause is not obvious, or a task fails twice, hand that task to `nm-implementer-deep` (Sonnet 5.5, trigger 2) and write the trigger in the ledger.

| Task | Deliverable | Agent | Review |
|---|---|---|---|
| 0. Base checks | the branch, the work folder, the baseline numbers | `nm-implementer-light` | none |
| 1. IDs, Auto, who wears it | `cat-core.js` block, `wardrobe.test.mjs` (7 self-checks, 1 replay), `wardrobe-cases.json` (first keys) | `nm-implementer-light` | `nm-reviewer` |
| 2. Slots, floors, anchors | `cat-core.js` block, 4 self-checks, 1 replay, the fixture's slots, edges, rooms and anchors | `nm-implementer-light` | `nm-reviewer` |
| 3. The 16 outfits | `cat-core.js` block, 9 self-checks, 1 replay, the fixture's shapes, digests and collars | `nm-implementer-light` | `nm-reviewer` |
| 4. Colours | `theme.json`, the generator, its tests, the three generated files and the site's CSS, 1 self-check | `nm-implementer-light` | `nm-reviewer` |
| 5. The prototype | `notchmeow.html` patched, loaded and clicked through in a headless browser, console empty, 1 self-check | `nm-implementer` | `nm-reviewer` |
| 6. Owner checkpoint | 9 pictures in `${TMPDIR:-/tmp}/i0-shots`, and a stop | `nm-implementer` | the owner |
| 7. Docs, final checks | `CAT-CONTRACT.md`, `THEME.md`, two pointers, every check | `nm-implementer-light` | `nm-reviewer` |
| After Task 7 | The whole branch: cross-task contracts, privacy and licensing rules | `nm-reviewer-deep` | n/a |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). The Task 5 and 6 agents also load `playwright-cli`.

## Execution

One worktree chat session runs the whole plan: branch `i0/wardrobe-contract`, model **Haiku 5.5 at medium effort** (the owner's decision, 2026-10-14: the plan gives the code in full). Nothing is pushed. The Mac and Windows/Linux I plans (I-mac on Sonnet 5.5 high, trigger 1; I-tauri on Haiku 5.5 high) are drafted from this plan's "Interface for the app plans" and start once the owner has approved the checkpoint and this branch is merged.

**Before the session starts,** the plan file and the spec are committed to `notchmeow/rebrand` (a docs-only commit): the main session does this, with the owner's OK, so the branch the session starts from already holds the plan it runs. **The base is `5f9051c` or later:** `git merge-base --is-ancestor 5f9051c HEAD` must succeed.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up, and carries the owner's advance approval of the brief the main session will send as the next message:

   > Run `git switch -c i0/wardrobe-contract notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-14-i0-wardrobe-contract.md`: only its Steps 1 and 2 (the base checks: `git merge-base --is-ancestor 5f9051c HEAD` must succeed, and `git ls-files` must print the plan and the spec). Read `CLAUDE.md`, `ARCHITECT.md`, `docs/CAT-CONTRACT.md`, that plan and `docs/superpowers/specs/2026-10-14-wardrobe-design.md`. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message:

   > Run `docs/superpowers/plans/2026-10-14-i0-wardrobe-contract.md` with `superpowers:subagent-driven-development`, task by task, on branch `i0/wardrobe-contract`. Dispatch each task to the agent the plan's "Tasks and agents" table names (`nm-implementer-light`, `nm-implementer` and `nm-reviewer`: Haiku 5.5 first; Sonnet 5.5 only on a named CLAUDE.md trigger, which goes in the ledger; never Opus or Fable), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
   >
   > - **Never push.** Commit once per task, in the plan's commit step, with `git commit -F <file>` (never `-m`) and the trailer of the model that did the task.
   > - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `i0/wardrobe-contract`. If either is wrong, stop and report.
   > - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-i0-wardrobe-contract/progress.md`: one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger. The SDD skill's plugin scripts may be refused by the auto-mode permission check: if so, do not call them; write each task brief with the Write tool just before you dispatch it, and write each review's diff with `git diff` into a file under the ledger's folder.
   > - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
   > - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files, never `..`.
   > - **Every shell block in the plan passes `bash -n` before it is run,** and a script you write passes it too.
   > - **Stop and report if a find text fails** (a patch whose anchor is not there exactly once), and on any refusal (a denied command, a permission prompt): do not look for a workaround.
   > - **Servers and processes.** Stop a server only by the PID you saved when you started it. Never launch, quit or replace a NotchMeow app. Install and download nothing (`npx --no-install` only; `playwright-cli` uses the cached browsers). Never read the real `~/.claude`.
   > - **Ping the main session.** The main session is named `NotchMeow — fork research & cat design`. Look its address up with `ListAgents` first (the `local_…` id does not work), then at the owner checkpoint (after Task 6), at the end, and whenever you stop (a refusal, a failed check, a question) send your report to it with `SendMessage`, as well as writing it in your own chat, so the main session can double-check the work (its own clone, merge and full checks) before anything reaches the owner.
   > - **Stop after Task 6.** Report the picture folder `${TMPDIR:-/tmp}/i0-shots`, each file name and what it shows, and any doubt, to the main session (ping, as above), and wait for its go: the owner approves or asks for changes to the shapes and colours at this checkpoint, and their notes may change numbers in the core, the palette or the page, which the fixture and Task 7 then follow. After the go, run Task 7, then dispatch `nm-reviewer-deep` over the whole branch, fix what it finds, and report (ping) once more.
   >
   > Report: the commits; the output of `bash scripts/test-cat-contract.sh` (the test count and the `✓ 16 fixture files match cat-core.js` line); `node scripts/check-fixtures-additive.mjs 5f9051c`; `bash scripts/test-theme.sh`; `bash scripts/test-cat-theme.sh`; `bash scripts/check-site.sh`; `bash scripts/check-no-leftovers.sh`; `cd windows && npm run check:cat` and `npx tsc --noEmit`; the picture folder; and anything you could not settle.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

## Interface for the app plans

What the Mac (I-mac) and Windows/Linux (I-tauri) plans consume. Names are exact: every one is a member of `CatCore` (the global on a page, `require()` in Node). Each app ports the rules natively and replays the fixture; the prototype page is the look. `docs/CAT-CONTRACT.md`, "The wardrobe (I-0)", has the notes for ports (Task 7 writes it).

| Name | Signature and meaning |
|---|---|
| `OUTFIT_IDS`, `OUTFIT_NAMES`, `OUTFIT_GROUPS`, `OUTFIT_DRAWN`, `DEFAULT_OUTFIT` | The 18 IDs in order (frozen), their UI names, the grid's five rows (`{id, name, ids}`), the 16 drawn IDs, `'auto'`. |
| `outfitIdOf(v)`, `cleanWardrobeSettings(raw)` | A stored value to an ID (anything that is not exactly one of the 18 is `'auto'`); `{outfit}` from the stored block's `outfit` key. Never throw. |
| `easterOf(year)`, `autoOutfitFor(y, m, d)`, `resolveOutfit(id, y, m, d)` | `{month, day}` or `null`; the Auto outfit ID or `'none'`; the ID to draw (`'none'` for none, never `'auto'`). Date numbers in, so the same everywhere. |
| `OUTFIT_ROLES`, `outfitWorn(role)` | `['big', 'small', 'kitten']`; true for `'big'` only. |
| `OUTFIT_SLOTS`, `OUTFIT_ORDER` | `['behind', 'neck', 'top']` and the draw order with `outfit.behind`, `outfit.neck` and `outfit.top` in place. |
| `OUTFIT_MIN` | `{height: 6, line: 1, rim: 2, ball: 3, span: 6}`, in **device** pixels (divide by `dpr`). |
| `outfitEdge(p)` | `'light'` for a dark head, `'dark'` for a light one. |
| `outfitRoom(anchors, headY, ceiling)` | px above the crown to the strip's top, less `EAR_FIT.margin`; `null` without a numeric ceiling. |
| `outfitAnchors(p, s, D, {dpr, detail, earScale})` | `{R, rx, ry, D, full, dpr, top, gap, half, lean, ears, eyes, chin: {pts, front}, neck, edge}`, head-local px. |
| `outfitGeometry(id, p, s, D, {dpr, detail, earScale, collar, room})` | The outfit's shapes in paint order: `{k: 'poly' \| 'curve' \| 'ellipse', slot, fill, stroke, sw, a, fine, ...}`; `[]` for `none`, `auto` or anything unknown; `fine` shapes are dropped below Ø28. |
| `outfitDigest(shapes)` | `{n, pts, bbox, mx, my}`, comparable within 1e-9. |

**What each app does.** Draw the shapes of `outfitGeometry` with its own painter at the three slots, for a cat whose view maps to the role `big`, after `resolveOutfit` has turned the stored choice into an ID (re-resolve at launch and at the next local midnight, one one-shot timer, only while the choice is `auto`). Pass `earScale` (the ear scale the cat's ears were drawn with, after the ear fit) and, in the compact notch only, `room = outfitRoom(outfitAnchors(...), headY, ceiling)` with the strip's ceiling (the renderers' `earCeiling`). Resolve the roles through the theme (`Theme.Outfits`, `THEME.outfits`), with `edge` standing for `edgeLight` or `edgeDark` as `anchors.edge` says. Paint a `curve` with round caps and joins, a `poly` closed, an `ellipse` rotated by `rot`; apply `a` to the fill and the stroke. The collar is the app's own and is unchanged.

---

## Tasks

### Task 0: Base checks and the work folder

**Files:** none in the repository. Creates `${TMPDIR:-/tmp}/i0-work/ins.py` (a helper outside the repository).

- [ ] **Step 1: The base**

```bash
git rev-parse --show-toplevel
git branch --show-current
git merge-base --is-ancestor 5f9051c HEAD && echo "base ok"
git ls-files docs/superpowers/plans/2026-10-14-i0-wardrobe-contract.md docs/superpowers/specs/2026-10-14-wardrobe-design.md
```

Expected: the worktree's folder, `i0/wardrobe-contract`, `base ok`, and the two paths. If the branch is another one, run `git switch -c i0/wardrobe-contract notchmeow/rebrand`. If `base ok` is missing, or `git ls-files` prints fewer than two paths, stop and say so.

- [ ] **Step 2: The tools and the baseline**

```bash
node -v
ls -d windows/node_modules | head -1
command -v playwright-cli swiftc python3 trash
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗|fixture files"
node scripts/check-fixtures-additive.mjs 5f9051c | tail -1
bash scripts/test-theme.sh 2>&1 | tail -1
bash scripts/check-site.sh 2>&1 | head -1
```

Expected: Node 22 or newer, `windows/node_modules`, four paths, `# tests 288`, `# pass 288`, `# fail 0`, `✓ 15 fixture files match cat-core.js`, `✓ fixtures changed only by addition since 5f9051c`, `✓ 3 theme files match shared/theme.json` and a line beginning `✓ docs/assets/cats.js and cats.css are what a fresh build makes`. If any differs, stop and report: the base is not the one this plan was run on.

- [ ] **Step 3: The work folder and the insert helper**

```bash
W="${TMPDIR:-/tmp}/i0-work"; mkdir -p "$W"
cat > "$W/ins.py" <<'PY_EOF'
#!/usr/bin/env python3
"""usage: ins.py FILE MARKER PART  -- inserts PART's text immediately above the line that holds MARKER (exactly one such line, else it stops)."""
import sys
f, marker, part = sys.argv[1:4]
s = open(f, encoding='utf-8').read()
assert s.count(marker) == 1, f'{marker!r} is in {f} {s.count(marker)} times, not once'
i = s.index(marker); i = s.rfind('\n', 0, i) + 1
add = open(part, encoding='utf-8').read()
if not add.endswith('\n'): add += '\n'
open(f, 'w', encoding='utf-8').write(s[:i] + add + s[i:])
print(f'inserted {len(add.splitlines())} lines into {f}')
PY_EOF
python3 -m py_compile "$W/ins.py" && echo "ins.py ok"
git status --short | wc -l
```

Expected: `ins.py ok` and `0` (a clean tree). The helper inserts a file's text immediately above the one line that holds a marker, and stops if the marker is not there exactly once. Nothing here is committed.

---

### Task 1: The IDs, the clean-up, Auto and who wears it

**Files:**
- Modify: `design/prototype/cat-core.js` (a new block above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (a builder above the `@@BUILDERS` marker), `tests/cat/fixtures.test.mjs` (the file list)
- Create: `tests/cat/wardrobe.test.mjs`, `tests/fixtures/cat/wardrobe-cases.json` (generated)

**Interfaces:**
- Consumes from the core: `isPlain`; from the generator: `compare`, `fix`, `format`, `finish`, `FILES`.
- Produces in `CatCore`: `OUTFIT_IDS`, `OUTFIT_NAMES`, `OUTFIT_GROUPS`, `OUTFIT_DRAWN`, `DEFAULT_OUTFIT`, `outfitIdOf`, `cleanWardrobeSettings`, `easterOf`, `autoOutfitFor`, `resolveOutfit`, `OUTFIT_ROLES`, `outfitWorn`, exactly as in "Interface for the app plans"; and the first keys of `wardrobe-cases.json` (`ids`, `names`, `groups`, `drawn`, `defaultOutfit`, `roles`, `clean`, `settings`, `easter`, `auto`, `easterWindows`, `resolve`, `worn`). The block also holds `owDays` and `owValid` (a day count and a date check, not exported), which Auto uses.

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/cat/wardrobe.test.mjs <<'JS_EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const fixture = () => JSON.parse(fs.readFileSync(new URL('../fixtures/cat/wardrobe-cases.json', import.meta.url), 'utf8'));
const near = (a, b, msg) => assert.ok(Math.abs(a - b) <= 1e-9, `${msg}: ${a} vs ${b}`);
const REST = core.newPose(), TURNED = { ...core.newPose(), yaw: .6, pitch: .15 };
const STRIPS = [[32, 20], [24, 18]]; // [height of the strip the cat sits in, head width]: the notch, and a screen without one
const finite = v => typeof v === 'number' ? Number.isFinite(v) : Array.isArray(v) ? v.every(finite) : v && typeof v === 'object' ? Object.values(v).every(finite) : true;
JS_EOF
cat >> tests/cat/wardrobe.test.mjs <<'JS_EOF'
test('the frozen values: 18 selection IDs in the grid order, 16 of them drawn, five rows of the grid, the roles', () => {
  assert.deepEqual(core.OUTFIT_IDS, ['auto', 'none', 'partyhat', 'santahat', 'witchhat', 'bunnyears', 'sunglasses', 'beanie', 'bow', 'scarf', 'roundglasses', 'crown', 'bell', 'bandana', 'fishclip', 'flower', 'shrimpclip', 'blossomclip']);
  assert.deepEqual(core.OUTFIT_DRAWN, core.OUTFIT_IDS.slice(2));
  assert.deepEqual(core.OUTFIT_GROUPS.flatMap(g => g.ids), core.OUTFIT_IDS, 'the groups hold every ID once, in the order of the IDs');
  assert.deepEqual(core.OUTFIT_GROUPS.map(g => g.name), ['', 'Seasonal', 'Everyday', 'Cat extras', "The cats' own"]);
  assert.deepEqual(Object.keys(core.OUTFIT_NAMES), core.OUTFIT_IDS);
  assert.ok(core.OUTFIT_IDS.every(id => /^[a-z]+$/.test(id)), 'lowercase letters only');
  assert.equal(core.DEFAULT_OUTFIT, 'auto');
  assert.deepEqual(core.OUTFIT_ROLES, ['big', 'small', 'kitten']);
});

test('a stored outfit: one of the 18 exactly as written, anything else is auto', () => {
  for (const id of core.OUTFIT_IDS) assert.equal(core.outfitIdOf(id), id);
  for (const v of ['Auto', 'BOW', ' bow', 'bow ', 'bow\n', '', 'fancyhat', 'pumpkin', 'tophat', '__proto__', 'constructor', 'toString', null, undefined, 7, true, [], ['bow'], {}, { outfit: 'bow' }, NaN, () => 'bow'])
    assert.equal(core.outfitIdOf(v), 'auto', String(v));
  assert.deepEqual(core.cleanWardrobeSettings({ outfit: 'bow' }), { outfit: 'bow' });
  for (const v of [null, undefined, 'bow', 7, [], ['bow'], {}, { outfit: 7 }, { outfit: 'Bow' }, JSON.parse('{"__proto__":{"outfit":"bow"}}')]) assert.deepEqual(core.cleanWardrobeSettings(v), { outfit: 'auto' });
  assert.deepEqual(core.cleanWardrobeSettings({ character: 'momo', outfit: 'crown', desktop: { on: true } }), { outfit: 'crown' }, 'only its own key is read');
});

test('Easter: the known dates, the earliest and the latest, and the years it does not answer for', () => {
  const known = { 1818: [3, 22], 1943: [4, 25], 1961: [4, 2], 2000: [4, 23], 2008: [3, 23], 2016: [3, 27], 2024: [3, 31], 2025: [4, 20], 2026: [4, 5], 2038: [4, 25], 2285: [3, 22] };
  for (const [y, [month, day]] of Object.entries(known)) assert.deepEqual(core.easterOf(+y), { month, day }, y);
  for (const y of [1582, 0, -5, 10000, 2024.5, '2024', null, NaN, undefined]) assert.equal(core.easterOf(y), null, String(y));
  for (let y = 1583; y <= 2500; y++) { const e = core.easterOf(y), d = new Date(Date.UTC(y, e.month - 1, e.day)); assert.equal(d.getUTCDay(), 0, `${y} is a Sunday`); assert.ok(e.month === 3 ? e.day >= 22 : e.month === 4 && e.day <= 25, `${y}`); }
});

test('Auto: every boundary of the five rules, in their priority order', () => {
  const at = (y, m, d) => core.autoOutfitFor(y, m, d);
  const rules = [['partyhat', [[2025, 12, 31], [2026, 1, 1], [2026, 1, 2]], [[2025, 12, 30], [2026, 1, 3]]], ['santahat', [[2025, 12, 1], [2025, 12, 26]], [[2025, 11, 30], [2025, 12, 27]]],
    ['witchhat', [[2025, 10, 1], [2025, 10, 31], [2025, 11, 1]], [[2025, 9, 30], [2025, 11, 2]]], ['sunglasses', [[2025, 6, 21], [2025, 7, 15], [2025, 8, 31]], [[2025, 6, 20], [2025, 9, 1]]]];
  for (const [id, inside, outside] of rules) { for (const d of inside) assert.equal(at(...d), id, `${d} is ${id}`); for (const d of outside) assert.notEqual(at(...d), id, `${d} is not ${id}`); }
  assert.equal(at(2025, 3, 15), 'none'); assert.equal(at(2025, 5, 5), 'none');
  assert.equal(at(2024, 2, 29), 'none'); assert.equal(at(2024, 7, 4), 'sunglasses');
});

test('Auto: Good Friday to Easter Monday wears bunny ears, in every year, by the calendar and not by the day count', () => {
  const walk = (y, m, d, k) => { const t = new Date(Date.UTC(y, m - 1, d + k)); return [t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate()]; };
  let seen = 0;
  for (let y = 1583; y <= 2600; y++) {
    const e = core.easterOf(y);
    for (let k = -4; k <= 3; k++) {
      const out = core.autoOutfitFor(...walk(y, e.month, e.day, k));
      assert.equal(out, k >= -2 && k <= 1 ? 'bunnyears' : 'none', `${y}: Easter ${k >= 0 ? '+' : ''}${k}`);
      if (out === 'bunnyears') seen++;
    }
  }
  assert.equal(seen, 4 * (2600 - 1583 + 1), 'four days a year, and the other four rules never touch them');
  assert.equal(core.autoOutfitFor(1500, 4, 1), 'none', 'a year before the Gregorian calendar has no Easter rule');
});

test('Auto: dates that are not dates, and the chosen value resolved for drawing', () => {
  for (const d of [[2023, 2, 29], [2024, 2, 30], [2024, 13, 1], [2024, 0, 1], [2024, 4, 31], [0, 1, 1], [10000, 1, 1], [2024.5, 1, 1], ['2024', 1, 1], [null, 1, 1], [2024, 1, 1.5]]) assert.equal(core.autoOutfitFor(...d), 'none', String(d));
  assert.equal(core.resolveOutfit('auto', 2025, 12, 24), 'santahat'); assert.equal(core.resolveOutfit('auto', 2025, 3, 3), 'none');
  assert.equal(core.resolveOutfit('none', 2025, 12, 24), 'none'); assert.equal(core.resolveOutfit('bow', 2025, 12, 24), 'bow');
  assert.equal(core.resolveOutfit('Bow', 2025, 12, 24), 'santahat', 'a value that is not an ID is auto');
  assert.equal(core.resolveOutfit(null, 2024, 3, 29), 'bunnyears');
  for (const id of core.OUTFIT_IDS) assert.notEqual(core.resolveOutfit(id, 2025, 7, 1), 'auto', 'never auto');
});

test('who wears it: the big-cat role at every size, never a kitten or a small cat', () => {
  assert.equal(core.outfitWorn('big'), true);
  for (const v of ['small', 'kitten', 'Big', ' big', '', null, undefined, 28, 20, 64, true, {}, []]) assert.equal(core.outfitWorn(v), false, String(v));
});

test('the fixture replays, part 1: the IDs, the clean-up, Easter, Auto and who wears it', () => {
  const f = fixture();
  assert.deepEqual(Object.keys(f).slice(0, 3), ['version', 'tolerance', 'note']);
  assert.deepEqual(compare(f.ids, core.OUTFIT_IDS), []); assert.deepEqual(compare(f.groups, core.OUTFIT_GROUPS), []); assert.deepEqual(compare(f.names, core.OUTFIT_NAMES), []);
  assert.equal(f.clean.length, 18 + 20); assert.equal(f.easterWindows.length, 12); assert.equal(f.worn.length, 16);
  for (const row of f.clean) assert.equal(core.outfitIdOf(row.input), row.out, row.name);
  for (const row of f.settings) assert.deepEqual(core.cleanWardrobeSettings(row.input), row.out, row.name);
  for (const row of f.easter) assert.deepEqual(core.easterOf(row.year), row.out, String(row.year));
  for (const row of f.auto) assert.equal(core.autoOutfitFor(row.y, row.m, row.d), row.out, `${row.y}-${row.m}-${row.d}`);
  for (const w of f.easterWindows) for (const d of w.days) assert.equal(core.autoOutfitFor(d.y, d.m, d.d), d.out, `${w.year} ${d.k}`);
  for (const row of f.resolve) assert.equal(core.resolveOutfit(row.id, row.y, row.m, row.d), row.out);
  for (const row of f.worn) assert.equal(core.outfitWorn(row.role), row.out, String(row.role));
});
JS_EOF
node --check tests/cat/wardrobe.test.mjs && echo "syntax ok"
```

- [ ] **Step 2: Run them to see them fail**

```bash
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
```

Expected: `# tests 8`, `# pass 0`, `# fail 8` (`core.OUTFIT_IDS` and the other new names are not there yet, and the fixture file is not either).

- [ ] **Step 3: Write the code**

The block goes into the core, the first builder into the generator, the file into the test's list, and the fixture is generated.

```bash
W="${TMPDIR:-/tmp}/i0-work"
cat > "$W/ids.js" <<'JS_EOF'
// ── The wardrobe (sub-project I): outfits for the big cats ───────────────────
// Sixteen outfits, drawn new for NotchMeow, and two ways to choose: None and Auto (the season). One outfit at a time, worn by every cat in a big-cat role (the
// island's main cat, both cats of Two cats mode, each agent's big cat, the desktop cat) at every size, and never by a kitten or a small cat. Everything here is pure:
// the IDs and their clean-up, Auto's calendar, who wears it, where an outfit sits on a head (anchors) and the shapes it is made of (geometry). The renderers paint the
// shapes; the colours are roles that the theme (shared/theme.json, the `outfits` group) resolves. Only new names: nothing above this section changed.
// The 18 selection IDs and their order (the grid's, the menu's and the shortcut's cycle) are frozen contract values: they are stored.
const OUTFIT_IDS=['auto','none','partyhat','santahat','witchhat','bunnyears','sunglasses','beanie','bow','scarf','roundglasses','crown','bell','bandana','fishclip','flower','shrimpclip','blossomclip'];
/** The names the UI shows, by ID. */
const OUTFIT_NAMES={auto:'Auto',none:'None',partyhat:'Party hat',santahat:'Santa hat',witchhat:'Witch hat',bunnyears:'Bunny ears',sunglasses:'Sunglasses',beanie:'Beanie',bow:'Bow',scarf:'Scarf',roundglasses:'Round glasses',crown:'Crown',bell:'Bell',bandana:'Bandana',fishclip:'Fish clip',flower:'Flower',shrimpclip:'Shrimp clip',blossomclip:'Peach-blossom clip'};
/** The grid's rows: the two choices, then the four groups with their headings. */
const OUTFIT_GROUPS=[{id:'choice',name:'',ids:['auto','none']},{id:'seasonal',name:'Seasonal',ids:['partyhat','santahat','witchhat','bunnyears','sunglasses']},{id:'everyday',name:'Everyday',ids:['beanie','bow','scarf','roundglasses','crown']},{id:'extras',name:'Cat extras',ids:['bell','bandana','fishclip','flower']},{id:'own',name:"The cats' own",ids:['shrimpclip','blossomclip']}];
/** The 16 outfits that are drawn (everything but the two choices). */
const OUTFIT_DRAWN=OUTFIT_IDS.slice(2);
const DEFAULT_OUTFIT='auto';
/** A stored outfit to an ID: exactly one of the 18, as written (lowercase, no trimming); anything else, or no string at all, is 'auto'. */
const outfitIdOf=v=>typeof v==='string'&&OUTFIT_IDS.includes(v)?v:DEFAULT_OUTFIT;
/**
 * What Settings stores for the wardrobe, cleaned: {outfit}. `raw` is the stored block as plain JSON (the `cat` block of settings.json, or the Mac's values gathered into one
 * object); a clean-up of its own, like cleanDisplaySettings, so cleanCatSettings and the older fixtures stay as they were. Never throws.
 *   macOS key: cat.outfit (a string)     Windows and Linux: the `outfit` key of the `cat` block of settings.json
 */
function cleanWardrobeSettings(raw){const r=isPlain(raw)?raw:{};return{outfit:outfitIdOf(r.outfit)}}
/** Gregorian Easter Sunday of a year from 1583 to 9999 as {month, day} (the Meeus/Jones/Butcher computation); null for any other year. */
function easterOf(year){if(!Number.isInteger(year)||year<1583||year>9999)return null;
 const a=year%19,b=Math.floor(year/100),c=year%100,d=Math.floor(b/4),e=b%4,f=Math.floor((b+8)/25),g=Math.floor((b-f+1)/3),h=(19*a+b-d-g+15)%30,i=Math.floor(c/4),k=c%4,l=(32+2*e+2*i-h-k)%7,m=Math.floor((a+11*h+22*l)/451),n=h+l-7*m+114;
 return{month:Math.floor(n/31),day:n%31+1}}
/** Days since 1970-01-01 of a calendar date, from the date numbers alone (no clock, no time zone), so a difference of two dates can never be shifted by daylight saving. */
const owDays=(y,m,d)=>{const yy=m<=2?y-1:y,era=Math.floor(yy/400),yoe=yy-era*400,doy=Math.floor((153*(m+(m>2?-3:9))+2)/5)+d-1,doe=yoe*365+Math.floor(yoe/4)-Math.floor(yoe/100)+doy;return era*146097+doe-719468};
const owValid=(y,m,d)=>Number.isInteger(y)&&Number.isInteger(m)&&Number.isInteger(d)&&y>=1&&y<=9999&&m>=1&&m<=12&&d>=1&&d<=[31,y%4===0&&(y%100!==0||y%400===0)?29:28,31,30,31,30,31,31,30,31,30,31][m-1];
/**
 * What Auto wears on a local date (year, month, day as numbers; the northern calendar, the same for everyone). The first rule that matches wins, and the order is the contract:
 *   1 Dec 31 to Jan 2 partyhat   2 Dec 1 to Dec 26 santahat   3 Oct 1 to Nov 1 witchhat   4 Good Friday to Easter Monday (Easter -2 to +1) bunnyears   5 Jun 21 to Aug 31 sunglasses
 * Anything else, and a date that is not a real date, is 'none'. Pure: the same in Node, Swift and TypeScript.
 */
function autoOutfitFor(y,m,d){if(!owValid(y,m,d))return'none';
 if((m===12&&d===31)||(m===1&&d<=2))return'partyhat';
 if(m===12&&d<=26)return'santahat';
 if(m===10||(m===11&&d===1))return'witchhat';
 const E=easterOf(y);if(E){const k=owDays(y,m,d)-owDays(y,E.month,E.day);if(k>=-2&&k<=1)return'bunnyears'}
 if((m===6&&d>=21)||m===7||m===8)return'sunglasses';
 return'none'}
/** The outfit to draw: the stored choice cleaned, with 'auto' replaced by what autoOutfitFor says for the date ('none' when nothing is worn). Never 'auto'. */
const resolveOutfit=(id,y,m,d)=>{const o=outfitIdOf(id);return o==='auto'?autoOutfitFor(y,m,d):o};
/** The roles a drawn cat can have. The apps map their views: the cast's big cats and the desktop cat are 'big', the pills' cats, the mini row and the grid 'small', the subagent kittens 'kitten'. */
const OUTFIT_ROLES=['big','small','kitten'];
/** Who wears the outfit: the big-cat role, at every size (the compact notch's Ø20 cat included). Anything else, and anything that is not a role, is bare. */
const outfitWorn=role=>role==='big';
Object.assign(api,{OUTFIT_IDS,OUTFIT_NAMES,OUTFIT_GROUPS,OUTFIT_DRAWN,DEFAULT_OUTFIT,outfitIdOf,cleanWardrobeSettings,easterOf,autoOutfitFor,resolveOutfit,OUTFIT_ROLES,outfitWorn});
JS_EOF
cat > "$W/builder1.js" <<'JS_EOF'
FILES['wardrobe-cases.json'] = () => {
  const out = { version: 1, note: 'The wardrobe (sub-project I). The IDs, their order and the action ID wardrobe are frozen contract values: they are stored. Geometry is in head-local px; shapes carry colour roles, which shared/theme.json resolves.' };
  out.ids = core.OUTFIT_IDS; out.names = core.OUTFIT_NAMES; out.groups = core.OUTFIT_GROUPS; out.drawn = core.OUTFIT_DRAWN; out.defaultOutfit = core.DEFAULT_OUTFIT; out.roles = core.OUTFIT_ROLES;
  out.clean = [
    ...core.OUTFIT_IDS.map(id => [`the ID ${id}`, id]),
    ['a capital', 'Auto'], ['all capitals', 'SANTAHAT'], ['padded', ' bow '], ['a trailing newline', 'bow\n'], ['empty', ''], ['null', null], ['a number', 7], ['true', true], ['a list', []], ['a list of an ID', ['bow']], ['an object', {}], ['an object with the key', { outfit: 'bow' }],
    ['a made-up name', 'fancyhat'], ['a made-up key', 'outfitId'], ['an outfit that is not here', 'pumpkin'], ['another', 'tophat'], ['a prototype name', '__proto__'], ['another', 'constructor'], ['another', 'toString'], ['a separator', 'party-hat'],
  ].map(([name, input]) => ({ name, input, out: core.outfitIdOf(input) }));
  out.settings = [
    ['null', null], ['text', 'bow'], ['a list', ['bow']], ['an empty object', {}], ['a clean value', { outfit: 'bow' }], ['a capital', { outfit: 'Bow' }], ['a number', { outfit: 7 }], ['null', { outfit: null }],
    ['none', { outfit: 'none', other: 1 }], ['the whole cat block', { character: 'momo', collar: 'tag', outfit: 'crown', desktop: { on: true } }], ['a prototype key', JSON.parse('{"__proto__": {"outfit": "bow"}}')],
  ].map(([name, input]) => ({ name, input, out: core.cleanWardrobeSettings(input) }));
  out.easter = [1583, 1600, 1700, 1818, 1900, 1943, 1961, 2000, 2008, 2016, 2024, 2025, 2026, 2038, 2100, 2285, 9999, 1582, 0, -5, 10000, 2024.5, '2024', null].map(year => ({ year, out: core.easterOf(year) }));
  const D = (y, m, d) => ({ y, m, d, out: core.autoOutfitFor(y, m, d) });
  out.auto = [
    D(2025, 12, 30), D(2025, 12, 31), D(2026, 1, 1), D(2026, 1, 2), D(2026, 1, 3), D(2025, 11, 30), D(2025, 12, 1), D(2025, 12, 26), D(2025, 12, 27), D(2025, 9, 30), D(2025, 10, 1), D(2025, 10, 31), D(2025, 11, 1), D(2025, 11, 2),
    D(2025, 6, 20), D(2025, 6, 21), D(2025, 8, 31), D(2025, 9, 1), D(2025, 3, 15), D(2025, 5, 5), D(2024, 2, 29), D(2024, 7, 4), D(2023, 2, 29), D(2024, 2, 30), D(2024, 13, 1), D(2024, 0, 1), D(2024, 4, 31), D(0, 1, 1), D(10000, 1, 1),
    D(2024.5, 1, 1), D('2024', 1, 1), D(null, 1, 1), D(1500, 12, 25), D(1500, 4, 1),
  ];
  const E = (y, m, d) => new Date(Date.UTC(y, m - 1, d)), iso = t => ({ y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate() });
  out.easterWindows = [1818, 1943, 1961, 2000, 2008, 2016, 2024, 2025, 2026, 2038, 2100, 2285].map(year => {
    const e = core.easterOf(year); // the dates are walked with the calendar (Date.UTC), not with the contract's own day count
    return { year, easter: e, days: [-3, -2, -1, 0, 1, 2].map(k => { const t = iso(E(year, e.month, e.day + k)); return { k, ...D(t.y, t.m, t.d) }; }) };
  });
  out.resolve = [
    ['auto', 2025, 12, 24], ['auto', 2025, 3, 3], ['none', 2025, 12, 24], ['bow', 2025, 12, 24], ['Bow', 2025, 12, 24], [null, 2025, 12, 24], ['auto', 2024, 3, 29], ['crown', 2024, 99, 1], ['auto', 2024, 99, 1],
  ].map(([id, y, m, d]) => ({ id, y, m, d, out: core.resolveOutfit(id, y, m, d) }));
  out.worn = ['big', 'small', 'kitten', 'Big', ' big', 'BIG', '', null, 28, 20, 64, true, {}, [], 'bigcat', 'desktop'].map(role => ({ role, out: core.outfitWorn(role) }));
  // @@WARDROBE-SECTIONS: each task adds its keys to `out` immediately above this line.
  return out;
};
JS_EOF
python3 "$W/ins.py" design/prototype/cat-core.js '// @@END-OF-CORE' "$W/ids.js"
python3 "$W/ins.py" scripts/gen-cat-fixtures.mjs '// @@BUILDERS' "$W/builder1.js"
python3 - <<'PY'
p = 'tests/cat/fixtures.test.mjs'
s = open(p, encoding='utf-8').read()
was = "'small-eye-cases.json', 'warp-cases.json'"
assert s.count(was) == 1, was
open(p, 'w', encoding='utf-8').write(s.replace(was, "'small-eye-cases.json', 'wardrobe-cases.json', 'warp-cases.json'"))
PY
node scripts/gen-cat-fixtures.mjs
```

Expected: `inserted 48 lines into design/prototype/cat-core.js` (or close), `inserted 32 lines into scripts/gen-cat-fixtures.mjs` and `wrote 16 fixture files to tests/fixtures/cat`.

- [ ] **Step 4: Run the tests, the contract and the additive check**

```bash
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗|fixture files|identical"
node scripts/check-fixtures-additive.mjs 5f9051c | tail -3
```

Expected: `# tests 8`, `# pass 8`, `# fail 0`; then `# tests 296`, `# pass 296`, `# fail 0`, `✓ 16 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`; then `+ wardrobe-cases.json is new` and `✓ fixtures changed only by addition since 5f9051c`.

- [ ] **Step 5: Commit**

```bash
W="${TMPDIR:-/tmp}/i0-work"
git rev-parse --show-toplevel; git branch --show-current
git status --short
cat > "$W/msg.txt" <<'MSG_EOF'
feat(cat-core): the wardrobe's IDs, clean-up, Auto and who wears it

The 18 outfit selection IDs (frozen: they are stored), outfitIdOf and cleanWardrobeSettings (a clean-up of its own), easterOf, autoOutfitFor and resolveOutfit (Auto's five date rules, counted on date numbers), and outfitWorn(role): the big-cat role at every size, never a kitten or a small cat. Pinned by the new wardrobe-cases.json; every existing fixture line is unchanged.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG_EOF
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/fixtures.test.mjs tests/cat/wardrobe.test.mjs tests/fixtures/cat/wardrobe-cases.json
git commit -q -F "$W/msg.txt" && git log --oneline -1
```

Expected: the status shows ` M` for three files and `??` for the two new ones, and one commit line.

---

### Task 2: Slots, floors and anchors

**Files:**
- Modify: `design/prototype/cat-core.js` (a new block above the marker), `scripts/gen-cat-fixtures.mjs` (keys above the `@@WARDROBE-SECTIONS` marker), `tests/cat/wardrobe.test.mjs` (appended)
- Regenerate: `tests/fixtures/cat/wardrobe-cases.json`

**Interfaces:**
- Consumes from the core: `PASSES`, `layout`, `supPoints`, `earScale`, `DETAIL_FULL_MIN`, `COLLAR_MIN`, `EAR_FIT`, `mixHex`, `FLAT_FILL`, `clamp`; from Task 1: `OUTFIT_DRAWN`.
- Produces in `CatCore`: `OUTFIT_SLOTS`, `OUTFIT_ORDER`, `OUTFIT_MIN`, `outfitEdge`, `outfitRoom`, `outfitAnchors`, exactly as in "Interface for the app plans"; and the fixture's `slots`, `order`, `min`, `edge`, `rooms` and `anchors`. The builder also defines `POSES` (`rest` and `turned`: yaw 0.6, pitch 0.15), `FOUR` (momo, shrimpy, button, midnight: a round coat, a fluffy one, a folded-ear one and a black one) and `SIZES` (20, 28, 48, 64), which Task 3 reuses.

- [ ] **Step 1: Write the failing tests**

```bash
cat >> tests/cat/wardrobe.test.mjs <<'JS_EOF'

test('the draw order: three slots that do not touch PASSES', () => {
  assert.deepEqual(core.OUTFIT_SLOTS, ['behind', 'neck', 'top']);
  assert.deepEqual(core.OUTFIT_ORDER.front, ['foldEars', 'collar', 'outfit.neck', 'outfit.top', 'whiskers', 'badge', 'particles', 'balls']);
  assert.deepEqual(core.OUTFIT_ORDER.behind, [...core.PASSES.behind, 'outfit.behind']);
  assert.equal(core.OUTFIT_ORDER.behind.indexOf('outfit.behind'), core.OUTFIT_ORDER.behind.indexOf('ears') + 1);
  assert.deepEqual(core.PASSES.front, ['foldEars', 'whiskers', 'badge', 'particles', 'balls'], 'PASSES stays as A-0 wrote it');
  assert.deepEqual(core.OUTFIT_MIN, { height: 6, line: 1, rim: 2, ball: 3, span: 6 });
});

test('the edge of a coat: light on a dark head, dark on a light one', () => {
  const light = core.CAT_IDS.filter(id => core.outfitEdge(core.PRESETS[id]) === 'light');
  assert.deepEqual(light, ['momo', 'midnight', 'oreo', 'mocha']);
  assert.equal(core.outfitEdge(core.PRESETS.ginger), 'dark'); assert.equal(core.outfitEdge(core.PRESETS.snow), 'dark');
});

test('anchors: the crown sits on the head between the ear bases, the chin runs left to right, on every coat at every size and turn', () => {
  for (const id of core.CAT_IDS) for (const D of [12, 18, 20, 28, 48, 64, 96]) for (const s of [REST, TURNED]) {
    const p = core.PRESETS[id], A = core.outfitAnchors(p, s, D, { dpr: 2 }), at = `${id} Ø${D}`;
    assert.ok(finite(A), at);
    assert.ok(A.top.y < -.6 * A.ry && A.top.y > -1.1 * A.ry, `${at}: the crown is at the top of the head`);
    assert.ok(A.gap > .3 * A.rx && A.gap < 1.2 * A.rx, `${at}: the ear bases are a head apart`);
    near(A.half * 2, A.gap, at);
    assert.equal(A.ears.length, 2); assert.deepEqual(A.ears.map(e => e.sd), [-1, 1]);
    assert.ok(A.ears[0].tipX < A.ears[0].bx && A.ears[1].tipX > A.ears[1].bx, `${at}: the ears lean outwards`);
    assert.ok(A.ears.every(e => e.tipY < e.by), `${at}: the tips are above the bases`);
    assert.equal(A.chin.pts.length, 26);
    assert.ok(A.chin.pts[0][0] < 0 && A.chin.pts[25][0] > 0, `${at}: the chin runs left to right`);
    assert.ok(A.chin.front[1] > .5 * A.ry && Math.abs(A.chin.front[0]) < .1 * A.rx + Math.abs(s.yaw) * A.rx, `${at}: the front of the chin`);
    assert.equal(A.edge, core.outfitEdge(p));
    assert.equal(A.eyes.length, 2);
  }
  const A2 = core.outfitAnchors(core.PRESETS.momo, REST, 64), A3 = core.outfitAnchors(core.PRESETS.momo, REST, 64, { dpr: 0 });
  assert.deepEqual(A2, A3, 'a dpr that is not above 0 is 2');
  assert.ok(Math.abs(core.outfitAnchors(core.PRESETS.momo, TURNED, 64).lean) > .05 && core.outfitAnchors(core.PRESETS.momo, REST, 64).lean === 0, 'a hat leans with the face turn');
});

test('the room above the crown: the distance to the strip, less the ear fit margin; none without a ceiling', () => {
  const A = { top: { x: 0, y: -8 } };
  near(core.outfitRoom(A, 16, 0), 7.5, 'the notch'); near(core.outfitRoom(A, 12, 0), 3.5, 'the strip without a notch'); assert.equal(core.outfitRoom(A, 4, 0), 0, 'no room is 0, never negative');
  for (const c of [null, undefined, 'x', NaN, Infinity]) assert.equal(core.outfitRoom(A, 16, c), null, String(c));
  for (const h of [null, undefined, 'x', NaN]) assert.equal(core.outfitRoom(A, h, 0), null, String(h));
});

test('the fixture replays, part 2: slots, floors, edges, rooms and anchors', () => {
  const f = fixture();
  assert.deepEqual(f.slots, core.OUTFIT_SLOTS); assert.deepEqual(f.order, core.OUTFIT_ORDER); assert.deepEqual(f.min, core.OUTFIT_MIN);
  assert.equal(Object.keys(f.anchors).length, 4 * 4 * 2);
  for (const [id, edge] of Object.entries(f.edge)) assert.equal(core.outfitEdge(core.PRESETS[id]), edge, id);
  for (const r of f.rooms) assert.equal(core.outfitRoom({ top: { x: 0, y: r.top } }, r.headY, r.ceiling), r.out, JSON.stringify(r));
  for (const [key, want] of Object.entries(f.anchors)) { const [cat, D, pose] = key.split('/'); assert.deepEqual(compare(core.outfitAnchors(core.PRESETS[cat], pose === 'rest' ? REST : TURNED, +D, { dpr: 2 }), want), [], key); }
});
JS_EOF
node --check tests/cat/wardrobe.test.mjs && echo "syntax ok"
```

- [ ] **Step 2: Run them to see them fail**

```bash
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
```

Expected: `# tests 13`, `# pass 8`, `# fail 5` (the five new tests: `core.OUTFIT_SLOTS` and `core.outfitAnchors` are not there yet).

- [ ] **Step 3: Write the code**

```bash
W="${TMPDIR:-/tmp}/i0-work"
cat > "$W/anchors.js" <<'JS_EOF'

// ── Where an outfit sits: slots, floors, anchors ─────────────────────────────
// An outfit is a short list of shapes in head-local px (before the tilt and squash, like collarGeometry), turning with the face warp. Three slots say where in the draw
// order a shape goes, without touching PASSES (A-0 pinned it): behind (after the cat's ears in the behind pass: bunny ears, so the head covers their roots), neck (in the
// front pass after the collar: scarf, bandana, bell) and top (after neck, before the whiskers: hats, crown, glasses, clips, bow, flower). The whiskers, the badge and the
// particles stay in front of every outfit. OUTFIT_ORDER is the whole order with the outfit's three places in it.
const OUTFIT_SLOTS=['behind','neck','top'];
const OUTFIT_ORDER={behind:[...PASSES.behind,'outfit.behind'],head:[...PASSES.head],front:['foldEars','collar','outfit.neck','outfit.top','whiskers','badge','particles','balls']};
/**
 * Smallest sizes, in DEVICE pixels (as COLLAR_MIN is), so an outfit still reads on the compact notch's Ø20 cat (40 device pixels wide at 2x):
 *   height  a hat's, a crown's or a bunny ear's height above the crown, when the room above it is short   line  the thinnest stroke   rim  a glasses rim
 *   ball    the radius of a pompom, a bell or a gem                                                          span  the narrowest solid part (an ear of the bunny, a tail, a clip)
 */
const OUTFIT_MIN={height:6,line:1,rim:2,ball:3,span:6};
/** Whether a coat's head is dark enough that an outfit's thin edge must be light to show: 'light' for a dark head, 'dark' for a light one (the flat head colour's luminance under 100). */
function outfitEdge(p){const c=mixHex(p.top,p.bot,FLAT_FILL.headMix);return .2126*c[0]+.7152*c[1]+.0722*c[2]<100?'light':'dark'}
/**
 * The room above the crown for a hat, in px: the distance from the crown to `ceiling` (the y of the top of the strip the cat sits in, in the same coordinates as `headY`, the head's y),
 * less the ear fit's margin. null when there is no ceiling (a number is required), which means no limit. `a` is outfitAnchors().
 */
const outfitRoom=(a,headY,ceiling)=>typeof ceiling==='number'&&Number.isFinite(ceiling)&&typeof headY==='number'&&Number.isFinite(headY)?Math.max(0,headY+a.top.y-ceiling-EAR_FIT.margin):null;
/**
 * Where the outfit parts attach to one cat in one pose, in head-local px:
 *   top   the crown between the ear bases, on the head outline        gap   the span between the two ear bases       half  gap/2       lean  a hat's lean with the face turn, rad
 *   ears  each ear {sd, bx, by, rot, h, tipX, tipY}: its base, its tilt and its tip     eyes  each eye frame {sd, visible, x, y, fx, fy}
 *   chin  {pts, front}: the lower head outline from 40 to 140 degrees, left to right, and its centre front     neck  the point the collar's tag hangs from (collarGeometry's)
 *   edge  'light' or 'dark' (outfitEdge)      R, rx, ry, D, full, dpr
 * o.dpr is the device pixel ratio (default 2); o.detail, o.earScale as in layout() (earScale defaults to what the renderer uses: 1 from Ø28, else earScale(D)).
 */
function outfitAnchors(p,s,D,o={}){
 const dpr=o.dpr>0?o.dpr:2,ek=o.earScale===undefined?(D>=DETAIL_FULL_MIN?1:earScale(D)):o.earScale,L=layout(p,s,0,0,D,{detail:o.detail,earScale:ek}),{R,rx,ry,W}=L,[eL,eR]=L.ears;
 const mx=(eL.bx+eR.bx)/2,gap=Math.abs(eR.bx-eL.bx),tx=clamp(mx/rx,-.95,.95),top={x:mx,y:-ry*Math.pow(Math.max(0,1-Math.pow(Math.abs(tx),p.n)),1/p.n)+L.bend[1]*ry*(1-tx*tx)};
 const N=90,ring=supPoints(rx,ry,p.n,0,p.fluff?.035:0,14,N,L.bend).slice(0,N),arc=ring.slice(N*40/360,N*140/360+1).reverse(),front=[(arc[12][0]+arc[13][0])/2,(arc[12][1]+arc[13][1])/2];
 const width=Math.max(.1*R,COLLAR_MIN.band/dpr),k=Math.max(.7,Math.min(.92,1-(width/2+.5/dpr)/(p.ry*R))),[nx,ny]=W(0,p.ry*k);
 return{R,rx,ry,D,full:L.full,dpr,top,gap,half:gap/2,lean:Math.sin(L.yf)*.15,
  ears:L.ears.map(e=>({sd:e.sd,bx:e.bx,by:e.by,rot:e.rot,h:e.h,tipX:e.bx+e.h*Math.sin(e.rot),tipY:e.by-e.h*Math.cos(e.rot)})),
  eyes:L.eyes.map(e=>({sd:e.sd,visible:e.visible,x:e.x,y:e.y,fx:e.fx,fy:e.fy})),chin:{pts:arc,front},neck:{x:nx,y:ny},edge:outfitEdge(p)}}
Object.assign(api,{OUTFIT_SLOTS,OUTFIT_ORDER,OUTFIT_MIN,outfitEdge,outfitRoom,outfitAnchors});
JS_EOF
cat > "$W/builder2.js" <<'JS_EOF'
  const POSES = { rest: core.newPose(), turned: { ...core.newPose(), yaw: .6, pitch: .15 } }, FOUR = ['momo', 'shrimpy', 'button', 'midnight'], SIZES = [20, 28, 48, 64];
  out.slots = core.OUTFIT_SLOTS; out.order = core.OUTFIT_ORDER; out.min = core.OUTFIT_MIN;
  out.edge = Object.fromEntries(core.CAT_IDS.map(id => [id, core.outfitEdge(core.PRESETS[id])]));
  out.rooms = [[0, 8, 0], [0, 16 - 8.04, 0], [0, 4.27, 0], [0, 0.2, 0], [0, 12, 4], [0, 12, null], [0, 12, 'x'], [0, null, 0]].map(([, headY, ceiling]) => ({ headY, ceiling, top: -8.04, out: core.outfitRoom({ top: { x: 0, y: -8.04 } }, headY, ceiling) }));
  out.anchors = Object.fromEntries(FOUR.flatMap(cat => SIZES.flatMap(D => Object.entries(POSES).map(([pose, s]) => [`${cat}/${D}/${pose}`, core.outfitAnchors(core.PRESETS[cat], s, D, { dpr: 2 })]))));
JS_EOF
python3 "$W/ins.py" design/prototype/cat-core.js '// @@END-OF-CORE' "$W/anchors.js"
python3 "$W/ins.py" scripts/gen-cat-fixtures.mjs '// @@WARDROBE-SECTIONS' "$W/builder2.js"
node scripts/gen-cat-fixtures.mjs
```

Expected: two `inserted` lines and `wrote 16 fixture files to tests/fixtures/cat`.

- [ ] **Step 4: Run the tests and the contract**

```bash
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗|fixture files|identical"
node scripts/check-fixtures-additive.mjs 5f9051c | tail -1
```

Expected: `# tests 13`, `# pass 13`, `# fail 0`; then `# tests 301`, `# pass 301`, `# fail 0`, `✓ 16 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`; then `✓ fixtures changed only by addition since 5f9051c`.

- [ ] **Step 5: Commit**

```bash
W="${TMPDIR:-/tmp}/i0-work"
git rev-parse --show-toplevel; git branch --show-current
cat > "$W/msg.txt" <<'MSG_EOF'
feat(cat-core): where an outfit sits: slots, floors, anchors and room

OUTFIT_SLOTS and OUTFIT_ORDER (the outfit's three places in the draw order, PASSES untouched), OUTFIT_MIN (floors in device pixels, set for the compact notch's Ø20 cat), outfitEdge (light or dark by the coat's head luminance), outfitRoom (the room above the crown that the ear fit leaves a hat) and outfitAnchors (the crown between the ear bases, the ears, the eye frames, the chin and the neck, in head-local px, turning with the face warp). Pinned by the fixture.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG_EOF
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/wardrobe.test.mjs tests/fixtures/cat/wardrobe-cases.json
git commit -q -F "$W/msg.txt" && git log --oneline -1
```

---

### Task 3: The shapes of the 16 outfits

**Files:**
- Modify: `design/prototype/cat-core.js` (a new block above the marker), `scripts/gen-cat-fixtures.mjs` (keys above the `@@WARDROBE-SECTIONS` marker), `tests/cat/wardrobe.test.mjs` (appended)
- Regenerate: `tests/fixtures/cat/wardrobe-cases.json`

**Interfaces:**
- Consumes from the core: everything of Tasks 1 and 2, `collarGeometry`, `COLLAR_STYLES`, `TAU`; from the builder: `POSES`, `FOUR`, `SIZES`.
- Produces in `CatCore`: `outfitGeometry` and `outfitDigest`, as in "Interface for the app plans"; and the fixture's `strips`, `geometry`, `digests`, `collars`, `unknown` and `fine`. **The shapes' colour roles are the 38 keys of the theme's `outfits` group that Task 4 writes** (`partyA`, `partyB`, `partyStar`, `santaRed`, `fur`, `witchHat`, `witchBand`, `gold`, `goldDark`, `bunnyOuter`, `bunnyInner`, `lens`, `frame`, `glint`, `beanieBody`, `beanieCuff`, `bowRed`, `bowKnot`, `scarfA`, `scarfB`, `rim`, `glassTint`, `gemA`, `gemB`, `gemC`, `silver`, `bandanaRed`, `white`, `fishBody`, `fishFin`, `petal`, `shrimp`, `shrimpDark`, `blossom`, `blossomDeep`, `leaf`, plus `edgeLight` and `edgeDark` for the role `edge`).

What the shapes are (the owner's checkpoint judges the look; this is the intent from the spec): a party hat (a slim two-stripe cone leaning to the right ear, a star on the tip), a Santa hat (red, a white fur band, the tip bent left with a pompom), a witch hat (a dark purple bent cone with a buckled band on a brim narrower than the ear spread), bunny ears (two tall ears with a pink inside rising from behind the crown, one bent), sunglasses (two dark lenses on the eyes with a bridge and arms), a beanie (a ribbed cuff and a pompom between the ear bases), a bow (two loops and a knot at the right ear), a scarf (two stripes under the chin and a tail on the left), round glasses (thin gold rims with a faint tint), a crown (three points with a gem on each), a bell (gold, hanging from the collar), a bandana (a red triangle with white dots, knotted at the side), a fish clip (left ear), a flower (right ear), a shrimp clip (left ear) and a peach-blossom clip (right ear). Each is built only from the coat's anchors.

- [ ] **Step 1: Write the failing tests**

```bash
cat >> tests/cat/wardrobe.test.mjs <<'JS_EOF'

const geo = (id, cat, D, s = REST, extra = {}) => {
  const p = core.PRESETS[cat], o = { dpr: 2, ...extra };
  if (D <= 20 && o.room === undefined) o.room = core.outfitRoom(core.outfitAnchors(p, s, D, o), (D === 20 ? 32 : 24) / 2, 0);
  return core.outfitGeometry(id, p, s, D, o);
};
const extent = (shapes, headY) => { // the highest and lowest point of a list of shapes in the strip, stroke widths included
  let hi = Infinity, lo = -Infinity;
  for (const sh of shapes) {
    const w = (sh.stroke ? sh.sw : 0) / 2;
    if (sh.k === 'ellipse') { const r = Math.hypot(sh.rx * Math.sin(sh.rot), sh.ry * Math.cos(sh.rot)); hi = Math.min(hi, headY + sh.y - r - w); lo = Math.max(lo, headY + sh.y + r + w); }
    else for (const q of sh.pts) { hi = Math.min(hi, headY + q[1] - w); lo = Math.max(lo, headY + q[1] + w); }
  }
  return { hi, lo };
};

test('what an outfit is made of: only the three kinds, real slots and roles, finite numbers, and nothing for the choices or a stranger', () => {
  const roles = new Set();
  for (const id of core.OUTFIT_DRAWN) for (const cat of core.CAT_IDS) for (const D of [18, 20, 28, 48, 64, 96]) for (const s of [REST, TURNED]) {
    const shapes = geo(id, cat, D, s), at = `${id} on ${cat} Ø${D}`;
    assert.ok(shapes.length > 0 && finite(shapes), at);
    for (const sh of shapes) {
      assert.ok(['poly', 'curve', 'ellipse'].includes(sh.k), at); assert.ok(core.OUTFIT_SLOTS.includes(sh.slot), at);
      for (const r of [sh.fill, sh.stroke]) if (r) roles.add(r);
      assert.ok(sh.a > 0 && sh.a <= 1 && sh.sw >= 0, at);
      if (sh.k === 'curve') assert.ok(sh.stroke && sh.sw > 0 && !('fill' in sh), `${at}: a curve is a stroke`);
      if (sh.k === 'ellipse') assert.ok(sh.rx > 0 && sh.ry > 0, at); else assert.ok(sh.pts.length >= 2 && sh.pts.every(q => q.length === 2), at);
      assert.equal(typeof sh.fine, 'boolean');
      if (sh.fine) assert.ok(D >= core.DETAIL_FULL_MIN, `${at}: a fine shape is left out below Ø28`);
    }
  }
  for (const id of ['none', 'auto', 'pumpkin', '', null, 7, '__proto__', 'constructor']) assert.deepEqual(core.outfitGeometry(id, core.PRESETS.momo, REST, 64), [], String(id));
});

test('only the slots the design names: bunny ears behind, the neck three over the collar, the rest on top', () => {
  const slotsOf = id => [...new Set(geo(id, 'momo', 64).map(sh => sh.slot))];
  assert.deepEqual(slotsOf('bunnyears'), ['behind']);
  for (const id of ['scarf', 'bandana', 'bell']) assert.deepEqual(slotsOf(id), ['neck'], id);
  for (const id of ['partyhat', 'santahat', 'witchhat', 'sunglasses', 'beanie', 'bow', 'roundglasses', 'crown', 'fishclip', 'flower', 'shrimpclip', 'blossomclip']) assert.deepEqual(slotsOf(id), ['top'], id);
});

test('fit across 16 coats: hats stand between the ears, glasses sit on the eyes, clips and the bow at an ear base', () => {
  for (const cat of core.CAT_IDS) {
    const p = core.PRESETS[cat], A = core.outfitAnchors(p, REST, 64, { dpr: 2 }), x = shapes => shapes.flatMap(sh => sh.k === 'ellipse' ? [sh.x - sh.rx, sh.x + sh.rx] : sh.pts.map(q => q[0]));
    for (const id of ['partyhat', 'santahat', 'beanie', 'crown']) { const xs = x(geo(id, cat, 64)); assert.ok(Math.max(...xs) <= A.half * .97 && Math.min(...xs) >= -A.half * .97, `${cat} ${id}: narrower than the gap between the ear bases`); }
    { const xs = x(geo('witchhat', cat, 64)); assert.ok(Math.max(...xs) < A.half && Math.min(...xs) > -A.half, `${cat}: the witch brim is narrower than the ear spread`); }
    for (const id of ['sunglasses', 'roundglasses']) { const sh = geo(id, cat, 64).filter(q => q.k === 'ellipse'), e = A.eyes.filter(v => v.visible); for (const lens of sh.slice(0, 2)) assert.ok(e.some(v => Math.hypot(v.x - lens.x, v.y - lens.y) < 1e-9), `${cat} ${id}: a lens on an eye`); }
    for (const [id, sd] of [['bow', 1], ['flower', 1], ['blossomclip', 1], ['fishclip', -1], ['shrimpclip', -1]]) { const e = A.ears.find(v => v.sd === sd), d = geo(id, cat, 64).filter(q => q.k !== 'curve').map(q => q.k === 'ellipse' ? [q.x, q.y] : q.pts[0]).map(([a, b]) => Math.hypot(a - e.bx, b - e.by)); assert.ok(Math.min(...d) < .7 * A.R, `${cat} ${id}: at its ear base`); }
  }
});

test('the head turned: the glasses flatten with the eyes and a lens that turns out of sight is not drawn', () => {
  const lens = s => geo('sunglasses', 'momo', 64, s).filter(q => q.k === 'ellipse');
  assert.equal(lens(REST).length, 2); assert.ok(lens(TURNED).length >= 1);
  const big = lens(REST)[0].rx, narrow = lens({ ...REST, yaw: 1.2 }).map(l => l.rx);
  assert.ok(Math.min(...narrow) < big * .8, 'a turned lens is narrower');
  for (const id of core.OUTFIT_DRAWN) { const a = geo(id, 'momo', 64, REST), b = geo(id, 'momo', 64, TURNED); assert.notDeepEqual(a, b, `${id} follows the turn`); }
});

test('the collar: the bell hangs from each style, the neck outfits draw with the collar off, and nothing changes the collar', () => {
  const p = core.PRESETS.momo;
  for (const style of core.COLLAR_STYLES) {
    const before = JSON.stringify(core.collarGeometry(p, REST, 64, style, { dpr: 2 }));
    for (const id of ['bell', 'bandana', 'scarf']) { const s = core.outfitGeometry(id, p, REST, 64, { dpr: 2, collar: style }); assert.ok(s.length > 0, `${id} with ${style}`); assert.ok(s.every(q => q.slot === 'neck')); }
    assert.equal(JSON.stringify(core.collarGeometry(p, REST, 64, style, { dpr: 2 })), before, 'reading the collar never changes it');
  }
  const bellAt = style => { const s = core.outfitGeometry('bell', p, REST, 64, { dpr: 2, collar: style }), e = s.filter(q => q.k === 'ellipse'); return e.find(q => q.fill === 'gold'); };
  const tag = core.collarGeometry(p, REST, 64, 'tag', { dpr: 2 }), band = core.collarGeometry(p, REST, 64, 'band', { dpr: 2 }), ker = core.collarGeometry(p, REST, 64, 'kerchief', { dpr: 2 }), A = core.outfitAnchors(p, REST, 64, { dpr: 2 });
  assert.ok(bellAt('tag').y > tag.tag.y + tag.tag.r, 'below the tag'); near(bellAt('tag').x, tag.tag.x, 'tag');
  near(bellAt('band').x, band.band[band.band.length >> 1][0], 'band'); assert.ok(bellAt('band').y > band.band[band.band.length >> 1][1]);
  near(bellAt('kerchief').x, ker.kerchief.apex[0], 'kerchief'); assert.ok(bellAt('kerchief').y > ker.kerchief.apex[1] - 1e-9);
  near(bellAt('off').x, A.neck.x, 'off: its own ring at the front of the neck'); assert.ok(bellAt('off').y > A.neck.y);
  const sc = core.outfitGeometry('scarf', p, REST, 64, { dpr: 2 }), bd = core.outfitGeometry('bandana', p, REST, 64, { dpr: 2 });
  assert.ok(sc[0].sw > core.collarGeometry(p, REST, 64, 'band', { dpr: 2 }).width * 2, 'the scarf is wider than the band collar, so it covers it');
  const w = shapes => { const xs = shapes.flatMap(q => q.k === 'ellipse' ? [q.x] : q.pts.map(v => v[0])); return Math.max(...xs) - Math.min(...xs); };
  assert.ok(w(bd) > w([{ k: 'poly', pts: ker.kerchief.pts }]), 'the bandana is bigger than the kerchief collar');
});

test('fine details are left out below Ø28, and the rest stays', () => {
  const some = core.OUTFIT_DRAWN.filter(id => geo(id, 'momo', 28).length > geo(id, 'momo', 27).length);
  assert.ok(some.length >= 6, `${some}`);
  for (const id of core.OUTFIT_DRAWN) { assert.ok(geo(id, 'momo', 27).length > 0, id); assert.ok(geo(id, 'momo', 28).filter(q => !q.fine).length === geo(id, 'momo', 27).length, `${id}: what is left is what is not fine`); }
});

test('the compact notch: every outfit on every coat reads at Ø20 and Ø18, stays inside the strip and never goes below its floors', () => {
  const dpr = 2, fl = n => core.OUTFIT_MIN[n] / dpr;
  for (const [H, D] of STRIPS) for (const cat of core.CAT_IDS) for (const id of core.OUTFIT_DRAWN) {
    const p = core.PRESETS[cat], A = core.outfitAnchors(p, REST, D, { dpr }), room = core.outfitRoom(A, H / 2, 0), shapes = geo(id, cat, D), at = `${id} on ${cat} Ø${D}`;
    assert.ok(room >= fl('height') - 1e-9, `${at}: the strip leaves ${room.toFixed(2)} pt, the floor is ${fl('height')}`);
    const { hi, lo } = extent(shapes, H / 2);
    assert.ok(hi >= -1e-9, `${at}: nothing above the strip (${hi.toFixed(2)})`); assert.ok(lo <= H + 1e-9, `${at}: nothing below the strip (${lo.toFixed(2)})`);
    for (const sh of shapes) { assert.ok(sh.k === 'ellipse' || sh.sw >= 0); if (sh.sw > 0) assert.ok(sh.sw >= fl('line') - 1e-9, `${at}: a stroke under the line floor`); if (sh.k === 'ellipse') assert.ok(Math.min(sh.rx, sh.ry) >= .5 * fl('ball') - 1e-9 || sh.fine, `${at}: an ellipse smaller than half a ball`); }
    const xs = shapes.flatMap(q => q.k === 'ellipse' ? [q.x - q.rx, q.x + q.rx] : q.pts.map(v => v[0])), ys = shapes.flatMap(q => q.k === 'ellipse' ? [q.y - q.ry, q.y + q.ry] : q.pts.map(v => v[1]));
    assert.ok(Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys)) >= fl('span'), `${at}: at least a span across`);
  }
  // A hat is shortened to the room, and held at the floor when even that is short; no room means no limit.
  const p = core.PRESETS.momo, rise = (room, D = 20) => -Math.min(...core.outfitGeometry('partyhat', p, REST, D, { dpr, room }).filter(q => q.k === 'poly').flatMap(q => q.pts.map(v => v[1])));
  assert.ok(rise(3) < rise(100), 'a short room gives a shorter hat'); assert.ok(rise(0) > 0, 'and no room still draws one'); near(rise(0), rise(1), 'both are held at the floor');
  assert.ok(rise(100) > rise(3) + 1, 'a tall room gives the natural height');
  assert.deepEqual(core.outfitGeometry('partyhat', p, REST, 20, { dpr, room: null }), core.outfitGeometry('partyhat', p, REST, 20, { dpr }), 'no room is no limit');
});

test('the digest: counts, a box and the mean point; zeros for nothing', () => {
  assert.deepEqual(core.outfitDigest([]), { n: 0, pts: 0, bbox: [0, 0, 0, 0], mx: 0, my: 0 });
  assert.deepEqual(core.outfitDigest([{ k: 'poly', pts: [[0, 0], [2, 0], [2, 4]] }, { k: 'ellipse', x: 1, y: 1, rx: 3, ry: 1 }]), { n: 2, pts: 4, bbox: [-2, 0, 4, 4], mx: 1.25, my: 1.25 });
});

test('the fixture replays, part 3: shapes, digests, collars, fine details', () => {
  const f = fixture();
  assert.equal(Object.keys(f.digests).length, 16 * 16 * 4); assert.equal(Object.keys(f.geometry).length, 4); assert.deepEqual(f.strips, { 18: 24, 20: 32 });
  for (const [key, byOutfit] of Object.entries(f.geometry)) { const [cat, D, pose] = key.split('/'); for (const [id, want] of Object.entries(byOutfit)) assert.deepEqual(compare(geo(id, cat, +D, pose === 'rest' ? REST : TURNED), want), [], `${key} ${id}`); }
  for (const [key, want] of Object.entries(f.digests)) { const [cat, id, D] = key.split('/'); assert.deepEqual(compare(core.outfitDigest(geo(id, cat, +D)), want), [], key); }
  for (const [key, want] of Object.entries(f.collars)) { const [id, style] = key.split('/'); assert.deepEqual(compare(core.outfitGeometry(id, core.PRESETS.momo, REST, 64, { dpr: 2, collar: style }), want.shapes), [], key); assert.deepEqual(compare(core.collarGeometry(core.PRESETS.momo, REST, 64, style, { dpr: 2 }), want.collar), [], key); }
  for (const row of f.unknown) assert.deepEqual(core.outfitGeometry(row.id, core.PRESETS.momo, REST, 64, { dpr: 2 }), row.out, String(row.id));
  for (const row of f.fine) { assert.equal(core.outfitGeometry(row.id, core.PRESETS.momo, REST, 27, { dpr: 2 }).length, row.at27); assert.equal(core.outfitGeometry(row.id, core.PRESETS.momo, REST, 28, { dpr: 2 }).length, row.at28); }
});
JS_EOF
node --check tests/cat/wardrobe.test.mjs && echo "syntax ok"
```

- [ ] **Step 2: Run them to see them fail**

```bash
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
```

Expected: `# tests 22`, `# pass 13`, `# fail 9` (`core.outfitGeometry` is not there yet).

- [ ] **Step 3: Write the code**

```bash
W="${TMPDIR:-/tmp}/i0-work"
cat > "$W/geometry.js" <<'JS_EOF'

// ── What an outfit is made of ────────────────────────────────────────────────
// outfitGeometry returns the shapes of one outfit on one cat, in paint order, as plain data in head-local px, in a vocabulary of three:
//   {k:'poly',    slot, fill, stroke, sw, a, fine, pts}               a closed polygon (rounded shapes are sampled)
//   {k:'curve',   slot,       stroke, sw, a, fine, pts}               an open polyline, stroked with round caps and joins
//   {k:'ellipse', slot, fill, stroke, sw, a, fine, x, y, rx, ry, rot} an ellipse (rot in rad)
// `fill` and `stroke` are colour roles (the keys of the theme's `outfits` group) or null; the role 'edge' stands for the thin edge of this coat (anchors.edge: 'light' or 'dark',
// the theme's edgeLight and edgeDark). `a` is the alpha, `sw` the stroke width in px (0 with no stroke). A `fine` shape (a glint, a star, a rib) is left out of the cat drawn below
// Ø28, as the cat's own fine details are. A hat rises from the crown by a natural height, shortened to `o.room` (see outfitRoom) but never below the floor.
// o: {dpr, detail, earScale, collar, room}. `collar` is a collar style (it is read for the bell, which hangs from it, and never changed). 'none', 'auto' and anything unknown give [].
function outfitGeometry(id,p,s,D,o={}){
 if(!OUTFIT_DRAWN.includes(id))return[];
 const A=outfitAnchors(p,s,D,o),{R,dpr,top,full}=A,fl=n=>OUTFIT_MIN[n]/dpr,ln=Math.max(fl('line'),.03*R),g=A.half,ca=Math.cos(A.lean),sa=Math.sin(A.lean),out=[];
 const Q=(x,y,b=[top.x,top.y])=>[b[0]+x*ca-y*sa,b[1]+x*sa+y*ca],room=typeof o.room==='number'&&Number.isFinite(o.room)?o.room:Infinity,hatH=nat=>Math.max(fl('height'),Math.min(nat*R,room));
 const poly=(slot,pts,fill,st={})=>out.push({k:'poly',slot,fill,stroke:st.stroke===undefined?'edge':st.stroke,sw:st.stroke===null?0:st.sw||ln,a:st.a===undefined?1:st.a,fine:!!st.fine,pts});
 const curve=(slot,pts,stroke,sw,st={})=>out.push({k:'curve',slot,stroke,sw:Math.max(sw,fl('line')),a:st.a===undefined?1:st.a,fine:!!st.fine,pts});
 const ell=(slot,x,y,rx,ry,rot,fill,st={})=>out.push({k:'ellipse',slot,fill,stroke:st.stroke===undefined?'edge':st.stroke,sw:st.stroke===null?0:st.sw||ln,a:st.a===undefined?1:st.a,fine:!!st.fine,x,y,rx,ry,rot});
 const arcPts=(cx,cy,rx,ry,a0,a1,n=10)=>Array.from({length:n+1},(_,i)=>{const a=a0+(a1-a0)*i/n;return[cx+Math.cos(a)*rx,cy+Math.sin(a)*ry]});
 const quad=(a,b,c,n=10)=>Array.from({length:n+1},(_,i)=>{const t=i/n,m=1-t;return[m*m*a[0]+2*m*t*b[0]+t*t*c[0],m*m*a[1]+2*m*t*b[1]+t*t*c[1]]});
 const star=(cx,cy,ro,ri)=>Array.from({length:10},(_,i)=>{const r=i%2?ri:ro,a=-Math.PI/2+i*Math.PI/5;return[cx+Math.cos(a)*r,cy+Math.sin(a)*r]});
 const pill=(slot,w,yc,hh,fill,st)=>poly(slot,[...arcPts(w-hh,yc,hh,hh,-Math.PI/2,Math.PI/2,6),...arcPts(hh-w,yc,hh,hh,Math.PI/2,Math.PI*1.5,6)].map(q=>Q(q[0],q[1])),fill,st); // a stadium shape, w its outer half width
 const ear=sd=>A.ears.find(e=>e.sd===sd),vis=sd=>A.eyes.find(e=>e.sd===sd);
 const ball=r=>Math.max(fl('ball'),r);
 /** A tapered leaf along a centre line: `c(t)` the centre, `w(t)` the half width, both for t from 0 to 1. */
 const leaf=(c,w,n=14)=>{const L=[],Rr=[];for(let i=0;i<=n;i++){const t=i/n,a=c(t),b=c(Math.min(1,t+.02)),d=c(Math.max(0,t-.02)),tx=b[0]-d[0],ty=b[1]-d[1],l=Math.hypot(tx,ty)||1,nx=-ty/l,ny=tx/l,ww=w(t);L.push([a[0]+nx*ww,a[1]+ny*ww]);Rr.push([a[0]-nx*ww,a[1]-ny*ww])}return[...L,...Rr.reverse()]};
 // ── Hats: they stand between the ear bases, so they are as wide as the gap and no wider
 if(id==='partyhat'){const Hh=hatH(1.35),b=[top.x,top.y+.05*R],w=.7,tx=.3,H=(x,y)=>Q(x*g,y*Hh,b),Lf=t=>H(-w+(tx+w)*t,-t),Rt=t=>H(w+(tx-w)*t,-t),tip=H(tx,-1);
  poly('top',[...arcPts(0,0,w*g,.1*R,Math.PI,0,8).map(q=>Q(q[0],-q[1],b)),tip],'partyA');
  for(const [t0,t1] of [[.16,.32],[.5,.64]])poly('top',[Lf(t0),Lf(t1),Rt(t1),Rt(t0)],'partyB',{stroke:null});
  poly('top',star(tip[0],tip[1]-.04*R,.2*R,.09*R),'partyStar',{fine:true,sw:ln})}
 else if(id==='santahat'){const Hh=hatH(.95),b=[top.x,top.y+.1*R],hw=.82,H=(x,y)=>Q(x*g,y*Hh,b);
  poly('top',[H(-hw,0),H(-.74,-.45),H(-.4,-.86),H(0,-1),H(.42,-.88),H(.74,-.5),H(hw,0)],'santaRed');
  const c=t=>H(...quad([0,-.95],[-.5,-1.02],[-.58,-.5],10)[Math.round(t*10)]),tip=c(1);
  poly('top',leaf(c,t=>(.34-.18*t)*g,10),'santaRed',{stroke:null});
  ell('top',tip[0],tip[1],ball(.17*R),ball(.17*R),0,'fur');
  pill('top',.95*g,0,Math.max(fl('line')*2,.12*R),'fur')}
 else if(id==='witchhat'){const Hh=hatH(1.5),b=[top.x,top.y+.04*R],H=(x,y)=>Q(x*g,y*Hh,b);
  ell('top',...Q(0,0,b),.95*g,Math.max(.12*R,fl('line')*2),A.lean,'witchHat');
  poly('top',[H(-.52,0),H(-.36,-.4),H(-.08,-.72),H(.1,-.82),H(.62,-1),H(.4,-.66),H(.34,-.45),H(.52,0)],'witchHat');
  poly('top',[H(-.5,-.1),H(.5,-.1),H(.45,-.3),H(-.42,-.3)],'witchBand',{stroke:null});
  poly('top',[H(-.12,-.06),H(.12,-.06),H(.12,-.34),H(-.12,-.34)],'gold',{sw:ln})}
 else if(id==='bunnyears'){const Hh=hatH(1.45),b=[top.x,top.y+.5*R],H=(x,y)=>Q(x*g,y*Hh,b);
  for(const sd of [-1,1]){const bend=sd>0?.9:0,c=t=>[H(sd*(.4+.22*t)+bend*Math.pow(Math.max(0,t-.55),2)*1.2,-t)[0],H(sd*(.4+.22*t)+bend*Math.pow(Math.max(0,t-.55),2)*1.2,-t)[1]],wm=Math.max(.3*g,fl('span')/2),w=t=>wm*Math.pow(Math.sin(Math.PI*(.2+.8*t)),.8);
   poly('behind',leaf(c,w),'bunnyOuter');
   poly('behind',leaf(t=>c(.06+.74*t),t=>w(.06+.74*t)*.55),'bunnyInner',{stroke:null})}}
 else if(id==='beanie'){const Hh=hatH(.78),b=[top.x,top.y+.26*R],hw=.95,H=(x,y)=>Q(x*g,y*Hh,b);
  poly('top',arcPts(0,0,hw,1,Math.PI,Math.PI*2,14).map(q=>H(q[0],q[1])),'beanieBody');
  for(const x of [-.5,0,.5])curve('top',[H(x*.9,-.15),H(x,-.62),H(x*.5,-.92)],'beanieCuff',ln*.9,{fine:true,a:.7});
  pill('top',.96*g,0,Math.max(.14*R,fl('span')/2),'beanieCuff');
  const t=H(0,-1.0);ell('top',t[0],t[1]-.04*R,ball(.17*R),ball(.17*R),0,'fur')}
 else if(id==='crown'){const Hh=hatH(.55),b=[top.x,top.y+.12*R],hw=.7,H=(x,y)=>Q(x*g,y*Hh,b);
  poly('top',[H(-hw,0),H(-hw,-.72),H(-.4,-.4),H(0,-1),H(.4,-.4),H(hw,-.72),H(hw,0)],'gold');
  poly('top',[H(-hw,0),H(hw,0),H(hw,-.22),H(-hw,-.22)],'goldDark',{stroke:null,a:.85});
  [[-hw,-.72,'gemA'],[0,-1,'gemB'],[hw,-.72,'gemC']].forEach(([x,y,r])=>{const q=H(x,y),gr=ball(.09*R);ell('top',q[0],q[1]+gr,gr,gr,0,r)})}
 // ── Glasses: they follow the eye frames and flatten with the face turn
 else if(id==='sunglasses'||id==='roundglasses'){const sun=id==='sunglasses',E=p.eye,lr=(sun?1.75:1.95)*E.w*R,lv=(sun?1.55:1.7)*Math.max(E.h,.85*E.w)*R,fr=Math.max(fl('rim'),sun?.06*R:.045*R),eyes=A.eyes.filter(e=>e.visible);
  for(const e of eyes){const rx=Math.max(lr*e.fx,fl('ball')),ry=Math.max(lv*e.fy,fl('ball'));
   if(sun){ell('top',e.x,e.y,rx,ry,0,'lens',{stroke:'frame',sw:fr,a:.93});poly('top',[[e.x-rx*.5,e.y-ry*.15],[e.x-rx*.12,e.y-ry*.62],[e.x+rx*.12,e.y-ry*.62],[e.x-rx*.3,e.y+ry*.08]],'glint',{stroke:null,a:.55,fine:true})}
   else{ell('top',e.x,e.y,rx,ry,0,'glassTint',{stroke:'rim',sw:fr,a:.22});ell('top',e.x,e.y,rx,ry,0,null,{stroke:'rim',sw:fr});curve('top',arcPts(e.x,e.y,rx*.72,ry*.72,Math.PI*1.05,Math.PI*1.4,5),'glint',ln,{fine:true,a:.8})}}
  if(eyes.length===2){const [a,b]=eyes.sort((u,v)=>u.sd-v.sd),ax=a.x+Math.max(lr*a.fx,fl('ball')),bx=b.x-Math.max(lr*b.fx,fl('ball')),my=(a.y+b.y)/2;curve('top',[[ax,a.y],[(ax+bx)/2,my-(sun?.06:.1)*R],[bx,b.y]],sun?'frame':'rim',fr)}
  for(const e of eyes){const ox=e.x+e.sd*Math.max(lr*e.fx,fl('ball'));curve('top',[[ox,e.y-lv*e.fy*.2],[ox+e.sd*.3*R*e.fx,e.y-lv*e.fy*.05]],sun?'frame':'rim',fr)}}
 // ── Clips, the bow and the flower: at an ear base, turning with the ear
 else if(id==='bow'){const e=ear(1),cx=e.bx-.12*R,cy=e.by+.02*R,u=Math.max(R*.9,fl('span')*1.6),rot=e.rot*.6;
  for(const sd of [-1,1])ell('top',cx+sd*.3*u*Math.cos(rot),cy+sd*.3*u*Math.sin(rot),.3*u,.21*u,rot+sd*.35,'bowRed');
  poly('top',[[cx-.05*u,cy+.1*u],[cx-.2*u,cy+.55*u],[cx-.05*u,cy+.45*u]],'bowKnot',{fine:true});poly('top',[[cx+.05*u,cy+.1*u],[cx+.2*u,cy+.55*u],[cx+.05*u,cy+.45*u]],'bowKnot',{fine:true});
  ell('top',cx,cy,ball(.1*u),ball(.1*u),0,'bowKnot')}
 else if(id==='fishclip'){const e=ear(-1),cx=e.bx+.24*R,cy=e.by+.1*R,u=Math.max(R,fl('span')*1.7),rot=e.rot*.5;
  ell('top',cx,cy,.27*u,.13*u,rot,'fishBody');
  poly('top',[[cx+.25*u*Math.cos(rot),cy+.25*u*Math.sin(rot)],[cx+.45*u,cy-.14*u],[cx+.45*u,cy+.14*u]],'fishFin');
  ell('top',cx-.13*u,cy-.02*u,.025*u,.025*u,0,'lens',{stroke:null,fine:true})}
 else if(id==='flower'){const e=ear(1),cx=e.bx-.22*R,cy=e.by+.1*R,u=Math.max(R,fl('span')*1.7);
  for(let i=0;i<5;i++){const a=-Math.PI/2+i*TAU/5;ell('top',cx+Math.cos(a)*.15*u,cy+Math.sin(a)*.15*u,ball(.13*u),ball(.09*u),a,'petal')}
  ell('top',cx,cy,ball(.07*u),ball(.07*u),0,'gold',{sw:ln})}
 else if(id==='shrimpclip'){const e=ear(-1),cx=e.bx+.24*R,cy=e.by+.12*R,u=Math.max(R,fl('span')*1.7);
  curve('top',arcPts(cx,cy,.15*u,.15*u,Math.PI*.2,Math.PI*1.9,10),'shrimp',Math.max(.12*u,fl('span')/2));
  poly('top',[[cx+.12*u,cy+.2*u],[cx+.3*u,cy+.18*u],[cx+.3*u,cy+.32*u],[cx+.1*u,cy+.3*u]],'shrimpDark',{});
  curve('top',arcPts(cx,cy,.15*u,.15*u,Math.PI*.55,Math.PI*1.6,6),'shrimpDark',ln,{fine:true,a:.7})}
 else if(id==='blossomclip'){const e=ear(1),cx=e.bx-.22*R,cy=e.by+.1*R,u=Math.max(R,fl('span')*1.7);
  for(const sd of [-1,1])ell('top',cx+sd*.2*u,cy+.14*u,ball(.13*u),ball(.06*u),sd*.6,'leaf');
  for(let i=0;i<5;i++){const a=-Math.PI/2+i*TAU/5;ell('top',cx+Math.cos(a)*.13*u,cy+Math.sin(a)*.13*u,ball(.11*u),ball(.11*u),a,i%2?'blossomDeep':'blossom')}
  ell('top',cx,cy,ball(.05*u),ball(.05*u),0,'gold',{stroke:null})}
 // ── Neck: over the collar
 else if(id==='scarf'||id==='bandana'||id==='bell'){
  const inw=(q,d)=>{const l=Math.hypot(q[0],q[1])||1;return[q[0]*(1-d/l),q[1]*(1-d/l)]},pts=A.chin.pts.map(q=>inw(q,.12*R));
  if(id==='scarf'){const wd=Math.max(.42*R,fl('span'));curve('neck',pts,'edge',wd+2*ln,{a:.9});curve('neck',pts,'scarfA',wd);curve('neck',pts.map(q=>inw(q,-.1*R)),'scarfB',Math.max(.07*R,fl('line')*1.5));curve('neck',pts.map(q=>inw(q,.1*R)),'scarfB',Math.max(.07*R,fl('line')*1.5));
   const t0=pts[5],tw=Math.max(.27*R,fl('span')),tl=.5*R;poly('neck',[[t0[0]-tw/2,t0[1]-.05*R],[t0[0]+tw/2,t0[1]-.05*R],[t0[0]+tw/2-.06*R,t0[1]+tl],[t0[0]-tw/2-.06*R,t0[1]+tl]],'scarfA');
   poly('neck',[[t0[0]-tw/2-.015*R,t0[1]+tl*.55],[t0[0]+tw/2-.045*R,t0[1]+tl*.55],[t0[0]+tw/2-.05*R,t0[1]+tl*.7],[t0[0]-tw/2-.02*R,t0[1]+tl*.7]],'scarfB',{stroke:null})}
  else if(id==='bandana'){const apex=[A.chin.front[0],Math.max(...pts.map(q=>q[1]))+.48*R];
   poly('neck',[...pts.map(q=>inw(q,-.06*R)),apex],'bandanaRed');
   const kn=pts[2];poly('neck',[[kn[0]-.12*R,kn[1]],[kn[0]-.4*R,kn[1]+.3*R],[kn[0]-.05*R,kn[1]+.26*R]],'bandanaRed',{});
   ell('neck',kn[0],kn[1],ball(.1*R),ball(.1*R),0,'bandanaRed');
   [[0,.34],[-.28,.18],[.28,.18]].forEach(([x,y])=>ell('neck',A.chin.front[0]+x*R,A.chin.front[1]+y*R,ball(.045*R),ball(.045*R),0,'white',{stroke:null,fine:true}))}
  else{const G=collarGeometry(p,s,D,o.collar,{dpr:A.dpr,detail:o.detail});let at=[A.neck.x,A.neck.y];
   if(G&&G.tag)at=[G.tag.x,G.tag.y+G.tag.r];else if(G&&G.band)at=G.band[G.band.length>>1];else if(G&&G.kerchief)at=G.kerchief.apex;
   const r=ball(.2*R);ell('neck',at[0],at[1]-.1*R,ball(.07*R),ball(.07*R),0,null,{stroke:'silver',sw:Math.max(ln*1.4,fl('line'))});
   ell('neck',at[0],at[1]+.12*R,r,r,0,'gold');curve('neck',[[at[0]-r*.7,at[1]+.1*R],[at[0]+r*.7,at[1]+.1*R]],'goldDark',ln,{fine:true});ell('neck',at[0],at[1]+.12*R+r*.55,ball(.04*R),ball(.04*R),0,'goldDark',{stroke:null,fine:true})}}
 return full?out:out.filter(sh=>!sh.fine)}
Object.assign(api,{outfitGeometry});
/**
 * A digest of a list of shapes that two implementations can compare within the contract's tolerance: how many shapes and points, the box that holds them (an ellipse counts as
 * its axis-aligned box and its centre as a point, a stroke's width is not counted) and the mean of every point's x and of every y (a sum would be too big for the fixture's 12 digits). An empty list digests to zeros.
 */
function outfitDigest(shapes){let pts=0,sx=0,sy=0,x0=Infinity,y0=Infinity,x1=-Infinity,y1=-Infinity;
 const add=(x,y)=>{pts++;sx+=x;sy+=y;x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y)};
 for(const sh of shapes){if(sh.k==='ellipse'){add(sh.x,sh.y);x0=Math.min(x0,sh.x-sh.rx);x1=Math.max(x1,sh.x+sh.rx);y0=Math.min(y0,sh.y-sh.ry);y1=Math.max(y1,sh.y+sh.ry)}else for(const q of sh.pts)add(q[0],q[1])}
 return shapes.length?{n:shapes.length,pts,bbox:[x0,y0,x1,y1],mx:sx/pts,my:sy/pts}:{n:0,pts:0,bbox:[0,0,0,0],mx:0,my:0}}
Object.assign(api,{outfitDigest});
JS_EOF
cat > "$W/builder3.js" <<'JS_EOF'
  /** The options a renderer would pass: the notch's strips give the compact cat its room above the crown (a 32 pt strip for the Ø20 cat, a 24 pt strip for the Ø18 one on a screen without a notch). */
  const STRIP = { 20: 32, 18: 24 }, opts = (p, s, D, extra = {}) => { const o = { dpr: 2, ...extra }; if (STRIP[D]) o.room = core.outfitRoom(core.outfitAnchors(p, s, D, o), STRIP[D] / 2, 0); return o; };
  out.strips = STRIP;
  out.geometry = Object.fromEntries([['momo', 64, 'rest'], ['momo', 64, 'turned'], ['shrimpy', 20, 'rest'], ['midnight', 28, 'rest']].map(([cat, D, pose]) =>
    [`${cat}/${D}/${pose}`, Object.fromEntries(core.OUTFIT_DRAWN.map(id => [id, core.outfitGeometry(id, core.PRESETS[cat], POSES[pose], D, opts(core.PRESETS[cat], POSES[pose], D))]))]));
  out.digests = Object.fromEntries(core.CAT_IDS.flatMap(cat => core.OUTFIT_DRAWN.flatMap(id => [18, 20, 48, 64].map(D => [`${cat}/${id}/${D}`, core.outfitDigest(core.outfitGeometry(id, core.PRESETS[cat], POSES.rest, D, opts(core.PRESETS[cat], POSES.rest, D)))]))));
  out.collars = Object.fromEntries(['bell', 'bandana', 'scarf'].flatMap(id => core.COLLAR_STYLES.map(style => [`${id}/${style}`, { collar: core.collarGeometry(core.PRESETS.momo, POSES.rest, 64, style, { dpr: 2 }), shapes: core.outfitGeometry(id, core.PRESETS.momo, POSES.rest, 64, { dpr: 2, collar: style }) }])));
  out.unknown = ['none', 'auto', 'pumpkin', '', null, 7, '__proto__'].map(id => ({ id, out: core.outfitGeometry(id, core.PRESETS.momo, POSES.rest, 64, { dpr: 2 }) }));
  out.fine = core.OUTFIT_DRAWN.map(id => ({ id, at27: core.outfitGeometry(id, core.PRESETS.momo, POSES.rest, 27, { dpr: 2 }).length, at28: core.outfitGeometry(id, core.PRESETS.momo, POSES.rest, 28, { dpr: 2 }).length }));
JS_EOF
python3 "$W/ins.py" design/prototype/cat-core.js '// @@END-OF-CORE' "$W/geometry.js"
python3 "$W/ins.py" scripts/gen-cat-fixtures.mjs '// @@WARDROBE-SECTIONS' "$W/builder3.js"
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/wardrobe-cases.json | awk '{print $5}'
```

Expected: two `inserted` lines, `wrote 16 fixture files to tests/fixtures/cat` and a size near 339000 (under the 400000 limit that `tests/cat/fixtures.test.mjs` enforces).

- [ ] **Step 4: Run the tests and the contract**

```bash
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗|fixture files|identical"
node scripts/check-fixtures-additive.mjs 5f9051c | tail -1
```

Expected: `# tests 22`, `# pass 22`, `# fail 0`; then `# tests 310`, `# pass 310`, `# fail 0`, `✓ 16 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`; then `✓ fixtures changed only by addition since 5f9051c`.

- [ ] **Step 5: Commit**

```bash
W="${TMPDIR:-/tmp}/i0-work"
git rev-parse --show-toplevel; git branch --show-current
cat > "$W/msg.txt" <<'MSG_EOF'
feat(cat-core): the shapes of the sixteen outfits

outfitGeometry gives each outfit as a short list of poly, curve and ellipse shapes in head-local px with colour roles, built only from the coat's own anchors: hats between the ear bases and shortened to the room the compact notch leaves them, glasses on the eye frames, clips and the bow at an ear base, the bell on the collar and the scarf and bandana over it. outfitDigest lets a port compare them within the tolerance. Every outfit on every coat is checked at Ø18 and Ø20 in the notch's strips against the floors, and pinned by digests for all 256 pairs. All drawings are NotchMeow's own.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG_EOF
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/wardrobe.test.mjs tests/fixtures/cat/wardrobe-cases.json
git commit -q -F "$W/msg.txt" && git log --oneline -1
```

---

### Task 4: The outfits' colours: the theme group and the site bundle

**Files:**
- Modify: `shared/theme.json`, `scripts/gen-theme.mjs`, `tests/theme/gen-theme.test.mjs`, `tests/cat/wardrobe.test.mjs` (appended)
- Regenerate: `NotchBuddy/Sources/App/Theme.generated.swift`, `windows/src/theme.generated.css`, `windows/src/theme.generated.ts`, `docs/assets/cats.css` (the site's bundle, rebuilt)

**Interfaces:**
- Consumes: the roles Task 3's shapes use. Produces: the `outfits` group of `shared/theme.json` (38 colours, `#RRGGBB` in capitals), `Theme.Outfits`, `THEME.outfits`, `THEME_RGB.outfits` and `--nm-outfits-*`; the apps read none of them yet.

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/cat/wardrobe.test.mjs <<'JS_EOF'

test('the colours: every role the shapes use is a colour of the theme\'s outfits group, and every colour is used', () => {
  const PAL = JSON.parse(fs.readFileSync(new URL('../../shared/theme.json', import.meta.url), 'utf8')).outfits, roles = new Set();
  assert.ok(PAL && Object.keys(PAL).length > 20, 'the theme has an outfits group');
  for (const id of core.OUTFIT_DRAWN) for (const cat of core.CAT_IDS) for (const sh of geo(id, cat, 64)) for (const r of [sh.fill, sh.stroke]) if (r) roles.add(r);
  roles.delete('edge');
  assert.deepEqual([...roles].sort(), Object.keys(PAL).filter(k => k !== 'edgeLight' && k !== 'edgeDark').sort());
  assert.ok(['edgeLight', 'edgeDark'].every(k => k in PAL), 'the two edges are there');
  assert.ok(Object.values(PAL).every(v => /^#[0-9A-F]{6}$/.test(v)), 'every colour is #RRGGBB in capitals');
});
JS_EOF
node --check tests/cat/wardrobe.test.mjs && echo "syntax ok"
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
```

Expected: `syntax ok`, `# tests 23`, `# pass 22`, `# fail 1` (the theme has no `outfits` group yet).

- [ ] **Step 2: Write the palette, the group and the test changes**

The patch adds the group to `shared/theme.json` after the greeting, puts `outfits` into the generator's group list and updates the theme tests' expectations (four groups, `Outfits` among the Swift enums, 38 more CSS names).

```bash
W="${TMPDIR:-/tmp}/i0-work"
cat > "$W/outfits.json" <<'JSON_EOF'
{
  "edgeLight": "#F4F1EA",
  "edgeDark": "#2B2430",
  "partyA": "#F25C7A",
  "partyB": "#FFD166",
  "partyStar": "#FFF3B0",
  "santaRed": "#D93A3A",
  "fur": "#F7F4EE",
  "witchHat": "#4B2E83",
  "witchBand": "#2A1A4A",
  "gold": "#F2B632",
  "goldDark": "#B97F12",
  "bunnyOuter": "#F4EFEA",
  "bunnyInner": "#F5A9B8",
  "lens": "#17171F",
  "frame": "#0F0F14",
  "glint": "#DCE6F5",
  "beanieBody": "#3F7CAC",
  "beanieCuff": "#2E5C82",
  "bowRed": "#E85D75",
  "bowKnot": "#C73E5C",
  "scarfA": "#E4572E",
  "scarfB": "#F3D6A0",
  "rim": "#C79A3B",
  "glassTint": "#A8D8F0",
  "gemA": "#E8456B",
  "gemB": "#3BA0F5",
  "gemC": "#3DBE8A",
  "silver": "#B8BEC8",
  "bandanaRed": "#D63B3B",
  "white": "#FAF7F2",
  "fishBody": "#7FB6D9",
  "fishFin": "#4F8DB5",
  "petal": "#F6A8C9",
  "shrimp": "#F26B4E",
  "shrimpDark": "#C94A34",
  "blossom": "#F9B5C2",
  "blossomDeep": "#E8869B",
  "leaf": "#5DAA68"
}
JSON_EOF
cat > "$W/theme_patch.py" <<'PY_EOF'
# Task 4: the theme's `outfits` group. Run from the repository root with the path of the palette JSON. Every replacement asserts that its anchor is there exactly once.
import json, sys
pal = json.load(open(sys.argv[1], encoding='utf-8'))
p = 'shared/theme.json'
d = json.load(open(p, encoding='utf-8'))
assert 'outfits' not in d
d['outfits'] = pal
open(p, 'w', encoding='utf-8').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')

def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('scripts/gen-theme.mjs', [("export const GROUPS = ['brand', 'cat', 'greeting'];", "export const GROUPS = ['brand', 'cat', 'greeting', 'outfits'];")])
edit('tests/theme/gen-theme.test.mjs', [
    ("the three groups, every colour", "the four groups, every colour"),
    ("assert.deepEqual(GROUPS, ['brand', 'cat', 'greeting']);", "assert.deepEqual(GROUPS, ['brand', 'cat', 'greeting', 'outfits']);"),
    ("['Brand', 'Cat', 'Greeting', 'State']);", "['Brand', 'Cat', 'Greeting', 'Outfits', 'State']);"),
    ("assert.deepEqual(Object.keys(t), ['brand', 'cat', 'greeting', 'state']);", "assert.deepEqual(Object.keys(t), ['brand', 'cat', 'greeting', 'outfits', 'state']);"),
    ("assert.equal(names.length, 7 + 10 + 6 + 5 + 11 + 7, 'brand, cat, greeting, streaks, state colours, state glows');", f"assert.equal(names.length, 7 + 10 + 6 + {len(pal)} + 5 + 11 + 7, 'brand, cat, greeting, outfits, streaks, state colours, state glows');"),
])
PY_EOF
python3 "$W/theme_patch.py" "$W/outfits.json"
node scripts/gen-theme.mjs
```

Expected: `wrote 3 theme files`.

- [ ] **Step 3: Rebuild the site's bundle**

The site's CSS carries the theme's tokens (`windows/src/site/main.ts` imports `theme.generated.css`), so `docs/assets/cats.css` changes and `scripts/check-site.sh` fails until it is rebuilt. The JavaScript bundle does not change.

```bash
cd windows && npx --no-install vite build --config vite.site.config.ts 2>&1 | tail -3; cd ..
git status --short
```

Expected: `✓ built in` a few hundred ms, and ` M` for `NotchBuddy/Sources/App/Theme.generated.swift`, `docs/assets/cats.css`, `scripts/gen-theme.mjs`, `shared/theme.json`, `tests/cat/wardrobe.test.mjs`, `tests/theme/gen-theme.test.mjs`, `windows/src/theme.generated.css` and `windows/src/theme.generated.ts` (and not `docs/assets/cats.js`).

- [ ] **Step 4: Run the checks**

```bash
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
bash scripts/test-theme.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗|✓"
bash scripts/test-cat-theme.sh 2>&1 | tail -1
bash scripts/check-site.sh 2>&1 | grep -E "✗|✓"
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)"
```

Expected: `# tests 23`, `# pass 23`, `# fail 0`; then `# tests 8`, `# pass 8`, `# fail 0` and `✓ 3 theme files match shared/theme.json` (plus the three files' lines); `All tests passed.` (the Mac program compiles the new `Theme.Outfits`); three `✓` lines from the site check; and `# tests 311`, `# pass 311`, `# fail 0`.

- [ ] **Step 5: Commit**

```bash
W="${TMPDIR:-/tmp}/i0-work"
git rev-parse --show-toplevel; git branch --show-current
cat > "$W/msg.txt" <<'MSG_EOF'
feat(theme): the outfits' colours

An outfits group in shared/theme.json (38 colours: the outfits' roles and the two edges), in the generator's group list and its tests, with the three generated files and the site's rebuilt CSS. A test keeps the roles of every shape equal to the colours of the group. No app reads them yet.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG_EOF
git add shared/theme.json scripts/gen-theme.mjs tests/theme/gen-theme.test.mjs tests/cat/wardrobe.test.mjs NotchBuddy/Sources/App/Theme.generated.swift windows/src/theme.generated.css windows/src/theme.generated.ts docs/assets/cats.css
git commit -q -F "$W/msg.txt" && git log --oneline -1
```

---

### Task 5: The prototype: the Wardrobe panel

**Files:**
- Modify: `design/prototype/notchmeow.html`, `tests/cat/wardrobe.test.mjs` (appended)
- One-off, not committed: `${TMPDIR:-/tmp}/i0-shots/` (the config, the port, the server's PID and log)

**Interfaces:**
- Consumes from `CatCore`: `OUTFIT_IDS`, `OUTFIT_NAMES`, `OUTFIT_GROUPS`, `OUTFIT_DRAWN`, `CAT_IDS`, `COLLAR_STYLES`, `resolveOutfit`, `autoOutfitFor`, `easterOf`, `outfitWorn`, `outfitAnchors`, `outfitRoom`, `outfitGeometry`; from the page: `drawCat`, `sizeEng`, `fit`, `group`, `DPR`, `AGENT_COL`, `TAU`.
- Produces in the page: the Wardrobe panel (`#wdPanel`), `WD` (its state), `wdBig()` (the outfit every big cat wears now, or `null`), `OW_PAL` (a copy of the theme's `outfits` group between `@@OUTFIT-PALETTE` markers), `owPaint(ctx, G, slot)` (the painter), `owCat` and the sheets' draw functions. `drawCat` gains `o.outfit` (an outfit ID) and `o.role`: the three `owPaint` calls sit after the cat's ears (`behind`) and after the collar (`neck`, then `top`).

What changes in the page, and what does not:
- **A new panel, "Wardrobe,"** before "Desktop": the chooser (18 buttons in the grid's five rows, the Auto button labelled "Auto: today, Santa hat" or with the date picked), a coat picker (16 buttons, changing only what the panel shows), a date field for Auto with a Today button, a readout, a preview of the chosen outfit on the chosen coat at Ø170, Ø64, Ø48, Ø28, the notch's Ø20 (true size and three times), and the small cats bare; **the sheet of all 16 outfits on all 16 coats**; the compact notch's Ø20 (32-point strip) and Ø18 (24-point strip) rows on four coats magnified 2.5 times, and Ø20 on all 16 coats at true size; the head turned left and right on four coats; and the bell, the bandana and the scarf over each collar style.
- **The big cats wear the chosen outfit** (resolved for the date): the notch's main cat compact and open, cat 2 of Two cats mode, the desktop cat (in the notch, in flight and at rest) and the two stage cats. The pills' small cats, the kittens, the greeting's cat (plan decision: see the open questions), the size ladder and the eye sheets are untouched.
- **No existing panel changes** when the choice is `none` (and the default is Auto, so a page opened on a day that has an outfit shows it on the big cats).

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/cat/wardrobe.test.mjs <<'JS_EOF'

test('the prototype page: its copy of the palette is the theme\'s, it paints the three slots, and only the big cats wear the outfit', () => {
  const html = fs.readFileSync(new URL('../../design/prototype/notchmeow.html', import.meta.url), 'utf8'), theme = JSON.parse(fs.readFileSync(new URL('../../shared/theme.json', import.meta.url), 'utf8'));
  const m = /@@OUTFIT-PALETTE \*\/\s*const OW_PAL=(\{[^;]*\});\s*\/\* @@END-OUTFIT-PALETTE/.exec(html);
  assert.ok(m, 'the page has the marked palette');
  assert.deepEqual(JSON.parse(m[1]), theme.outfits);
  for (const slot of core.OUTFIT_SLOTS) assert.ok(html.includes(`owPaint(ctx,OWG,'${slot}')`), slot);
  assert.ok(html.includes('CatCore.outfitWorn(o.role)'), 'drawCat asks the contract who is dressed');
  assert.equal([...html.matchAll(/drawCat\([^\n]*?outfit:wdBig\(\),role:'big'/g)].length, 6, 'the six big-cat calls pass the role');
});
JS_EOF
node --check tests/cat/wardrobe.test.mjs && echo "syntax ok"
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
```

Expected: `syntax ok`, `# tests 24`, `# pass 23`, `# fail 1` (the page has no palette copy yet).

- [ ] **Step 2: Apply the patch**

Every replacement asserts that its anchor is there exactly once. It reads the palette from `shared/theme.json`.

```bash
W="${TMPDIR:-/tmp}/i0-work"
cat > "$W/wd-head.js" <<'JS_EOF'
// ── Wardrobe, the part drawCat needs: the choice, the palette and the painter. The outfits are CatCore.outfitGeometry; this only paints their shapes ─────
// The theme's `outfits` group, as hex; a test keeps this copy equal to shared/theme.json.
/* @@OUTFIT-PALETTE */
const OW_PAL=@@PALETTE@@;
/* @@END-OUTFIT-PALETTE */
const WD={choice:'auto',date:null,coat:'momo'};
const wdToday=()=>{const d=new Date();return[d.getFullYear(),d.getMonth()+1,d.getDate()]};
const wdDay=()=>WD.date||wdToday();
const wdResolved=()=>CatCore.resolveOutfit(WD.choice,...wdDay());
/** The outfit every cat in a big-cat role wears now, or null for none. */
const wdBig=()=>{const r=wdResolved();return r==='none'?null:r};
const owCol=(role,edge)=>OW_PAL[role==='edge'?(edge==='light'?'edgeLight':'edgeDark'):role];
/** Paints one slot of an outfit into a head-local context (the one drawCat has translated, tilted and squashed). G is {shapes, edge}. */
function owPaint(ctx,G,slot){if(!G)return;ctx.save();ctx.lineCap='round';ctx.lineJoin='round';
 for(const sh of G.shapes){if(sh.slot!==slot)continue;ctx.globalAlpha=sh.a;ctx.beginPath();
  if(sh.k==='ellipse')ctx.ellipse(sh.x,sh.y,Math.max(sh.rx,.01),Math.max(sh.ry,.01),sh.rot,0,TAU);
  else{sh.pts.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));if(sh.k==='poly')ctx.closePath()}
  if(sh.fill){ctx.fillStyle=owCol(sh.fill,G.edge);ctx.fill()}
  if(sh.stroke&&sh.sw>0){ctx.strokeStyle=owCol(sh.stroke,G.edge);ctx.lineWidth=sh.sw;ctx.stroke()}}
 ctx.restore()}
JS_EOF
cat > "$W/wd.js" <<'JS_EOF'
// ── Wardrobe panel: the chooser, the preview and the sheets ─────────────────────────────────────────────────────────────────────
const wdAutoName=()=>{const r=CatCore.autoOutfitFor(...wdDay());return r==='none'?'none':CatCore.OUTFIT_NAMES[r]};
const wdLabel=id=>id==='auto'?`Auto: ${WD.date?WD.date.join('-'):'today'}, ${wdAutoName()}`:CatCore.OUTFIT_NAMES[id];
const wdBtns={};
{const pick=document.getElementById('wdPick');
 for(const G of CatCore.OUTFIT_GROUPS){const row=document.createElement('div');row.className='row';const h=document.createElement('span');h.className='h';h.textContent=G.name||'Choose';row.appendChild(h);
  for(const id of G.ids){const b=document.createElement('button');b.onclick=()=>{WD.choice=id;wdRefresh()};wdBtns[id]=b;row.appendChild(b)}pick.appendChild(row)}
 group('wdCoatRow',CatCore.CAT_IDS.map(id=>[id,id]),()=>WD.coat,v=>{WD.coat=v;drawWardrobe()});
 document.getElementById('wdDate').oninput=ev=>{const m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(ev.target.value);WD.date=m?[+m[1],+m[2],+m[3]]:null;wdRefresh()};
 document.getElementById('wdNow').onclick=()=>{document.getElementById('wdDate').value='';WD.date=null;wdRefresh()}}
function wdRefresh(){for(const id of CatCore.OUTFIT_IDS){wdBtns[id].textContent=wdLabel(id);wdBtns[id].classList.toggle('on',WD.choice===id)}
 const [y,m,d]=wdDay(),E=CatCore.easterOf(y);
 document.getElementById('wdReadout').textContent=`${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}: Auto wears ${wdAutoName()}. Easter ${y} is ${E?`${E.day}/${E.month}`:'out of range'}. Every big cat wears: ${wdBig()?CatCore.OUTFIT_NAMES[wdBig()]:'nothing'}.`;
 drawWardrobe()}
/** One cat from the shared idle engines, optionally with the head turned, dressed for a big-cat role. */
function owCat(ctx,cat,id,cx,cy,D,o={}){const e=sizeEng(cat,'idle'),sv=[e.s.yaw,e.s.pitch];if(o.yaw!==undefined)e.s.yaw=o.yaw;if(o.pitch!==undefined)e.s.pitch=o.pitch;
 drawCat(ctx,e,cx,cy,D,{tint:false,badge:false,outfit:id,role:o.role||'big',earCeiling:o.earCeiling,collar:o.collar,detail:o.detail});e.s.yaw=sv[0];e.s.pitch=sv[1]}
const owShort=id=>CatCore.OUTFIT_NAMES[id].replace('Peach-blossom','Blossom').replace('Round glasses','Round glass.').split(' ');
function owHeads(ctx,ids,LW,CW,font){ctx.fillStyle='#ececee';ctx.font=font;ctx.textAlign='center';ids.forEach((id,i)=>{const w=owShort(id);w.forEach((t,j)=>ctx.fillText(t,LW+i*CW+CW/2,12+j*11))})}
function drawWdSheet(){const cv=document.getElementById('wdSheet'),cats=CatCore.CAT_IDS,ids=CatCore.OUTFIT_DRAWN,CW=66,RH=64,LW=78,HH=34,W=LW+ids.length*CW,H=HH+cats.length*RH;
 cv.style.width=W+'px';cv.style.height=H+'px';const [ctx]=fit(cv,W,H);ctx.fillStyle='#0b0c0e';ctx.fillRect(0,0,W,H);owHeads(ctx,ids,LW,CW,'600 10px system-ui,sans-serif');
 cats.forEach((c,j)=>{ctx.fillStyle='#9a9ca3';ctx.font='11px system-ui,sans-serif';ctx.textAlign='left';ctx.fillText(c,8,HH+j*RH+RH/2+4);
  ids.forEach((id,i)=>owCat(ctx,c,id,LW+i*CW+CW/2,HH+j*RH+RH/2+4,40))})}
/** The compact notch's big cat: Ø20 in the 32 pt strip, Ø18 in the 24 pt strip of a screen without a notch, magnified k times. */
function drawWdCompact(cv,k,cats,rows){const ids=CatCore.OUTFIT_DRAWN,CW=42,LW=64,HH=26,gap=3,rowH=rows.reduce((a,r)=>a+r.H+gap,0),W=LW+ids.length*CW*k,H=HH+cats.length*rowH*k;
 cv.style.width=W+'px';cv.style.height=H+'px';const [ctx]=fit(cv,W,H);ctx.fillStyle='#16171a';ctx.fillRect(0,0,W,H);owHeads(ctx,ids,LW,CW*k,'600 10px system-ui,sans-serif');
 cats.forEach((c,j)=>{let y=HH+j*rowH*k;rows.forEach(r=>{ctx.fillStyle='#9a9ca3';ctx.font='10px system-ui,sans-serif';ctx.textAlign='left';ctx.fillText(`${c} Ø${r.D}`,4,y+r.H*k/2+3);
  ctx.save();ctx.translate(LW,y);ctx.scale(k,k);ids.forEach((id,i)=>{ctx.fillStyle='#000';ctx.fillRect(i*CW+1,0,CW-2,r.H);ctx.fillStyle='#3a3c42';ctx.fillRect(i*CW+1,0,CW-2,1/DPR());owCat(ctx,c,id,i*CW+CW/2,r.H/2,r.D,{earCeiling:0})});ctx.restore();y+=(r.H+gap)*k})})}
const WD_STRIPS=[{H:32,D:20},{H:24,D:18}];
function drawWdTurn(){const cv=document.getElementById('wdTurn'),cats=['momo','shrimpy','button','midnight'],turns=[-.6,.6],ids=CatCore.OUTFIT_DRAWN,CW=66,RH=64,LW=96,HH=34,W=LW+ids.length*CW,H=HH+cats.length*turns.length*RH;
 cv.style.width=W+'px';cv.style.height=H+'px';const [ctx]=fit(cv,W,H);ctx.fillStyle='#0b0c0e';ctx.fillRect(0,0,W,H);owHeads(ctx,ids,LW,CW,'600 10px system-ui,sans-serif');
 cats.forEach((c,j)=>turns.forEach((yw,t)=>{const y=HH+(j*2+t)*RH+RH/2+4;ctx.fillStyle='#9a9ca3';ctx.font='11px system-ui,sans-serif';ctx.textAlign='left';ctx.fillText(`${c} ${yw<0?'left':'right'}`,8,y+4);
  ids.forEach((id,i)=>owCat(ctx,c,id,LW+i*CW+CW/2,y,40,{yaw:yw,pitch:.15}))}))}
function drawWdCollars(){const cv=document.getElementById('wdCollars'),styles=CatCore.COLLAR_STYLES,cols=[['momo','bell'],['momo','bandana'],['momo','scarf'],['ginger','bell'],['ginger','bandana'],['ginger','scarf']],CW=124,RH=116,LW=70,HH=22,W=LW+cols.length*CW,H=HH+styles.length*RH;
 cv.style.width=W+'px';cv.style.height=H+'px';const [ctx]=fit(cv,W,H);ctx.fillStyle='#0b0c0e';ctx.fillRect(0,0,W,H);ctx.fillStyle='#ececee';ctx.font='600 11px system-ui,sans-serif';ctx.textAlign='center';
 cols.forEach(([c,id],i)=>ctx.fillText(`${c} · ${id}`,LW+i*CW+CW/2,14));
 styles.forEach((st,j)=>{ctx.fillStyle='#9a9ca3';ctx.textAlign='left';ctx.fillText(`collar: ${st}`,6,HH+j*RH+RH/2+4);cols.forEach(([c,id],i)=>owCat(ctx,c,id,LW+i*CW+CW/2,HH+j*RH+RH/2,78,{collar:collarOf2(st)}))})}
const collarOf2=style=>style==='off'?null:{style,col:AGENT_COL['Claude Code']};
function drawWdPreview(){const cv=document.getElementById('wdPreview'),id=wdBig(),c=WD.coat,W=820,H=270;cv.style.width=W+'px';cv.style.height=H+'px';const [ctx]=fit(cv,W,H);ctx.fillStyle='#0b0c0e';ctx.fillRect(0,0,W,H);
 owCat(ctx,c,id,130,150,170);ctx.fillStyle='#9a9ca3';ctx.font='11px system-ui,sans-serif';ctx.textAlign='center';ctx.fillText(`${c}, ${id?CatCore.OUTFIT_NAMES[id]:'no outfit'}`,130,262);
 [[64,'Ø64',270],[48,'Ø48',360],[28,'Ø28',430]].forEach(([D,l,x])=>{owCat(ctx,c,id,x,150,D);ctx.fillText(l,x,262)});
 ctx.fillStyle='#000';ctx.fillRect(480,98,60,32);ctx.fillStyle='#3a3c42';ctx.fillRect(480,98,60,1/DPR());owCat(ctx,c,id,510,114,20,{earCeiling:98});ctx.fillStyle='#9a9ca3';ctx.fillText('Ø20 notch',510,262);
 ctx.save();ctx.translate(560,50);ctx.scale(3,3);ctx.fillStyle='#000';ctx.fillRect(0,0,60,32);ctx.fillStyle='#3a3c42';ctx.fillRect(0,0,60,1/DPR());owCat(ctx,c,id,30,16,20,{earCeiling:0});ctx.restore();ctx.fillText('Ø20 × 3',650,262);
 owCat(ctx,c,id,740,100,20,{role:'small'});owCat(ctx,c,id,780,100,12,{role:'small'});ctx.fillText('small cats: bare',760,128)}
function drawWardrobe(){drawWdPreview();drawWdSheet();drawWdCompact(document.getElementById('wdCompact3'),2.5,['momo','shrimpy','latte','midnight'],WD_STRIPS);drawWdCompact(document.getElementById('wdCompact1'),1,CatCore.CAT_IDS,WD_STRIPS.slice(0,1));drawWdTurn();drawWdCollars()}
JS_EOF
cat > "$W/proto_patch.py" <<'PY_EOF'
# Task: the prototype's Wardrobe panel. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
import json, sys
p = 'design/prototype/notchmeow.html'
s = open(p, encoding='utf-8').read()

def rep(was, now):
    global s
    assert s.count(was) == 1, was[:80]
    s = s.replace(was, now)

PAL = json.dumps(json.load(open('shared/theme.json', encoding='utf-8'))['outfits'], separators=(',', ':'))
WDH = open(sys.argv[1], encoding='utf-8').read().replace('@@PALETTE@@', PAL).rstrip('\n')
WD = open(sys.argv[2], encoding='utf-8').read().rstrip('\n')

# 1. Style: new classes only
rep('''#dkReadout,#dkStored{white-space:pre-line;font-variant-numeric:tabular-nums}
</style>''', '''#dkReadout,#dkStored{white-space:pre-line;font-variant-numeric:tabular-nums}
#wdPanel canvas{display:block;border-radius:10px}
#wdPanel input[type=date]{font:inherit;font-size:12px;color:var(--ink);background:#202227;border:1px solid var(--line);border-radius:8px;padding:3px 8px;color-scheme:dark}
#wdPanel h3{font-size:14px;font-weight:600;margin:18px 0 4px}
</style>''')

# 2. The panel, before "Desktop"
rep('''<section class="panel" id="dkPanel">''', '''<section class="panel" id="wdPanel">
<h2>Wardrobe</h2>
<p class="tag">Sixteen outfits for the big cats: the island's main cat (compact and open), both cats of Two cats mode, each agent's big cat and the desktop cat. Kittens and the small cats stay bare, whatever their size. One outfit at a time; Auto follows the date. Pick an outfit, a coat and, for Auto, a date. The cat below is the big cat; the coat picker only changes what you see here.</p>
<div id="wdPick"></div>
<div class="row" id="wdCoatRow"><span class="h">Coat</span></div>
<div class="row"><span class="h">Date</span><input type="date" id="wdDate" aria-label="Date for Auto"><button id="wdNow">Today</button></div>
<p class="note" id="wdReadout"></p>
<div class="scroll" style="margin-top:12px"><canvas id="wdPreview" aria-label="The chosen outfit on the chosen coat at five sizes"></canvas></div>
<h3>All 16 outfits on all 16 coats (Ø40)</h3>
<div class="scroll"><canvas id="wdSheet" aria-label="Sixteen outfits on sixteen coats"></canvas></div>
<h3>The compact notch: Ø20 in the 32 pt strip and Ø18 in the 24 pt strip, magnified 2.5 times</h3>
<div class="scroll"><canvas id="wdCompact3" aria-label="Compact notch, magnified"></canvas></div>
<h3>The compact notch at true size, all 16 coats (Ø20)</h3>
<div class="scroll"><canvas id="wdCompact1" aria-label="Compact notch, true size"></canvas></div>
<h3>The head turned (left, then right)</h3>
<div class="scroll"><canvas id="wdTurn" aria-label="Outfits with the head turned"></canvas></div>
<h3>The bell, the bandana and the scarf with each collar style</h3>
<div class="scroll"><canvas id="wdCollars" aria-label="Neck outfits over the four collar styles"></canvas></div>
</section>

<section class="panel" id="dkPanel">''')

# 3. drawCat: the three slots
rep('''e._base=L.base;e._at=L.at;cx=L.head.x;cy=L.head.y;''', '''e._base=L.base;e._at=L.at;cx=L.head.x;cy=L.head.y;
 // The outfit (sub-project I): worn by the big-cat role at every size. In the compact notch the hats get the room the ears get (o.earCeiling).
 let OWG=null;if(o.outfit&&CatCore.outfitWorn(o.role)){const ob={dpr:DPR(),detail:o.detail,earScale:ek,collar:o.collar?o.collar.style:'off'},A0=CatCore.outfitAnchors(p,s,D,ob);
  if(o.earCeiling!==undefined)ob.room=CatCore.outfitRoom(A0,cy,o.earCeiling);OWG={shapes:CatCore.outfitGeometry(o.outfit,p,s,D,ob),edge:A0.edge}}''')
rep('''drawEar(ctx,p,s,-1,R,rx,ry,full,yf,pf,false,ek,flat);drawEar(ctx,p,s,1,R,rx,ry,full,yf,pf,false,ek,flat);''', '''drawEar(ctx,p,s,-1,R,rx,ry,full,yf,pf,false,ek,flat);drawEar(ctx,p,s,1,R,rx,ry,full,yf,pf,false,ek,flat);
 owPaint(ctx,OWG,'behind');''')
rep('''if(G)drawCollar(ctx,G,o.collar.col,full)}
 // Whiskers''', '''if(G)drawCollar(ctx,G,o.collar.col,full)}
 owPaint(ctx,OWG,'neck');owPaint(ctx,OWG,'top');
 // Whiskers''')

# 4. The big cats wear it
rep('''collar:bigCollar(notchEng),earCeiling:0});''', '''collar:bigCollar(notchEng),earCeiling:0,outfit:wdBig(),role:'big'});''')
rep('''collar:C.second.pill?collarOf(TASK[C.second.pill].col):null,earCeiling:0})}''', '''collar:C.second.pill?collarOf(TASK[C.second.pill].col):null,earCeiling:0,outfit:wdBig(),role:'big'})}''')
rep('''collar:bigCollar(o.eng),earCeiling:0,glow:e>.5});''', '''collar:bigCollar(o.eng),earCeiling:0,glow:e>.5,outfit:wdBig(),role:'big'});''')
rep('''{tint:TINTON,fur:FUR&&D>=60,badgeSide:1,collar:bigCollar(eng)});''', '''{tint:TINTON,fur:FUR&&D>=60,badgeSide:1,collar:bigCollar(eng),outfit:wdBig(),role:'big'});''')
rep('''if(!inNotch)drawCat(ctx,eng,pos.x,pos.y,D,{tint:TINTON,badgeSide:1});''', '''if(!inNotch)drawCat(ctx,eng,pos.x,pos.y,D,{tint:TINTON,badgeSide:1,outfit:wdBig(),role:'big'});''')
rep('''{fur:FUR,tint:TINTON,glow:true,collar:bigCollar(S.e)});drawFlights(ctx,S.flights)}''', '''{fur:FUR,tint:TINTON,glow:true,collar:bigCollar(S.e),outfit:wdBig(),role:'big'});drawFlights(ctx,S.flights)}''')

# 5. The state and the painter, early (drawCat runs while the page loads); the panel's code before the frame loop; its first draw after the loop starts
rep('''const ms=()=>performance.now(),nowS=()=>performance.now()/1000;''', '''const ms=()=>performance.now(),nowS=()=>performance.now()/1000;
''' + WDH)
rep('''// ── Frame loop ───''', WD + '''
// ── Frame loop ───''')
rep('''requestAnimationFrame(frame);
</script></body></html>''', '''requestAnimationFrame(frame);
wdRefresh();
</script></body></html>''')
open(p, 'w', encoding='utf-8').write(s)
PY_EOF
python3 "$W/proto_patch.py" "$W/wd-head.js" "$W/wd.js" && echo "patched"
node --test tests/cat/wardrobe.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
```

Expected: `patched`, then `# tests 24`, `# pass 24`, `# fail 0`.

- [ ] **Step 3: Serve the page and click through it**

```bash
REPO="$(git rev-parse --show-toplevel)"
SHOTS="${TMPDIR:-/tmp}/i0-shots"; mkdir -p "$SHOTS"
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
echo "$PORT" > "$SHOTS/port"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$REPO/design/prototype" > "$SHOTS/server.log" 2>&1 &
echo $! > "$SHOTS/server.pid"
cat > "$SHOTS/pw-config.json" <<'EOF'
{ "browser": { "contextOptions": { "viewport": { "width": 2700, "height": 1500 }, "deviceScaleFactor": 2 } } }
EOF
sleep 1
cd "$SHOTS" && playwright-cli open "http://127.0.0.1:$PORT/notchmeow.html" --config=pw-config.json > /dev/null
q() { playwright-cli --raw eval "$1"; }
q "(() => { const i = document.getElementById('wdDate'); i.value = '2025-12-24'; i.dispatchEvent(new Event('input', { bubbles: true })); return document.getElementById('wdReadout').textContent; })()"
q "(() => { const log = []; for (const id of CatCore.OUTFIT_IDS) { wdBtns[id].click(); log.push(id + ':' + (wdBig() || 'none')); } wdBtns.auto.click(); return log.join(' '); })()"
q "document.querySelectorAll('#wdCoatRow button').length + ' coats, ' + Object.keys(wdBtns).length + ' choices'"
q "(async () => { const wait = ms => new Promise(r => setTimeout(r, ms)); wdBtns.none.click(); await wait(400); const a = document.getElementById('cvDesk').toDataURL(); wdBtns.witchhat.click(); await wait(400); const b = document.getElementById('cvDesk').toDataURL(); wdBtns.auto.click(); return a !== b; })()"
playwright-cli console | head -2
```

Expected, in this order: `"2025-12-24: Auto wears Santa hat. Easter 2025 is 20/4. Every big cat wears: Santa hat."`; `"auto:santahat none:none partyhat:partyhat santahat:santahat witchhat:witchhat bunnyears:bunnyears sunglasses:sunglasses beanie:beanie bow:bow scarf:scarf roundglasses:roundglasses crown:crown bell:bell bandana:bandana fishclip:fishclip flower:flower shrimpclip:shrimpclip blossomclip:blossomclip"`; `"16 coats, 18 choices"`; `true` (the notch's cat is drawn differently with the witch hat on); and a console line `Total messages: 0 (Errors: 0, Warnings: 0)`.

- [ ] **Step 4: Stop the browser and the server**

```bash
cd "${TMPDIR:-/tmp}/i0-shots"
playwright-cli close
kill "$(cat server.pid)"
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$(cat port)/notchmeow.html" || true
```

Expected: `000` (nothing is listening any more).

- [ ] **Step 5: Run the contract once more and commit**

```bash
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗"
git status --short
```

Expected: `# tests 312`, `# pass 312`, `# fail 0`; then ` M design/prototype/notchmeow.html` and ` M tests/cat/wardrobe.test.mjs` and nothing else (the pictures' folder is outside the repository).

```bash
W="${TMPDIR:-/tmp}/i0-work"
git rev-parse --show-toplevel; git branch --show-current
cat > "$W/msg.txt" <<'MSG_EOF'
feat(prototype): the Wardrobe panel

A Wardrobe panel: the 18 choices, a coat picker, a date for Auto, a preview from Ø170 down to the notch's Ø20, the sheet of all 16 outfits on all 16 coats, the compact notch's Ø20 and Ø18 strips, the head turned and the collar styles. drawCat paints an outfit at the three slots for the big-cat role (the notch's cats, the desktop cat and the stage cats); the pills' small cats and the kittens stay bare. Every shape is CatCore's; no existing panel changes.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG_EOF
git add design/prototype/notchmeow.html tests/cat/wardrobe.test.mjs
git commit -q -F "$W/msg.txt" && git log --oneline -1
```

---

### Task 6: Owner checkpoint: the pictures

**Files:**
- Create (outside the repository, never committed): `${TMPDIR:-/tmp}/i0-shots/wardrobe-preview.png`, `wardrobe-sheet.png`, `wardrobe-compact-x2.5.png`, `wardrobe-compact-true.png`, `wardrobe-turn.png`, `wardrobe-collars.png`, `wardrobe-auto.png`, `wardrobe-notch.png`, `wardrobe-stage.png`

**Interfaces:**
- Consumes: the page from Task 5, and `playwright-cli` with its cached browsers (no login: the page is served from `127.0.0.1`). Produces: nine PNGs at a device scale of 2, and a stop.

The owner looks at these before anything is built on them: the contact sheet of all 16 outfits on all 16 coats, the compact notch's Ø20 and Ø18 big cat (magnified and at true size, which is where an outfit is most likely to stop reading), the head turned and the collar strips, the date-driven Auto, and the notch and the stage with an outfit on.

- [ ] **Step 1: Serve the page and take the pictures**

```bash
REPO="$(git rev-parse --show-toplevel)"
SHOTS="${TMPDIR:-/tmp}/i0-shots"; mkdir -p "$SHOTS"
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
echo "$PORT" > "$SHOTS/port"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$REPO/design/prototype" > "$SHOTS/server.log" 2>&1 &
echo $! > "$SHOTS/server.pid"
cat > "$SHOTS/pw-config.json" <<'EOF'
{ "browser": { "contextOptions": { "viewport": { "width": 2700, "height": 1500 }, "deviceScaleFactor": 2 } } }
EOF
sleep 1
cd "$SHOTS" && playwright-cli open "http://127.0.0.1:$PORT/notchmeow.html" --config=pw-config.json > /dev/null
q() { playwright-cli --raw eval "$1"; }
shot() { playwright-cli eval "document.querySelector('$1').scrollIntoView({block: 'center'})" > /dev/null; sleep 1; playwright-cli screenshot "$1" --hires --filename="$SHOTS/$2" > /dev/null; }
q "(() => { document.querySelector('.wrap').style.maxWidth = 'none'; document.querySelectorAll('.scroll').forEach(e => { e.style.overflow = 'visible'; }); const i = document.getElementById('wdDate'); i.value = '2025-12-24'; i.dispatchEvent(new Event('input', { bubbles: true })); wdBtns.witchhat.click(); return wdBig(); })()"
shot "#wdPreview" wardrobe-preview.png
shot "#wdSheet" wardrobe-sheet.png
shot "#wdCompact3" wardrobe-compact-x2.5.png
shot "#wdCompact1" wardrobe-compact-true.png
shot "#wdTurn" wardrobe-turn.png
shot "#wdCollars" wardrobe-collars.png
q "(() => { wdBtns.auto.click(); return wdBig(); })()"
shot "#wdPick" wardrobe-auto.png
q "(() => { document.querySelector('.wrap').style.maxWidth = ''; wdBtns.crown.click(); return wdBig(); })()"
shot "#desk" wardrobe-notch.png
shot "#figMomo" wardrobe-stage.png
q "(() => { wdBtns.auto.click(); return 'reset'; })()" > /dev/null
playwright-cli console | head -2
ls -1 "$SHOTS"/wardrobe-*.png
```

Expected: `"witchhat"`, `"santahat"`, `"crown"`, `Total messages: 0 (Errors: 0, Warnings: 0)` and the nine file names above, each with the `i0-shots` path in front.

- [ ] **Step 2: Look at them**

Open each PNG (the `Read` tool shows an image) and check, in this order, before reporting:
1. `wardrobe-sheet.png`: 16 columns (Party hat, Santa hat, Witch hat, Bunny ears, Sunglasses, Beanie, Bow, Scarf, Round glasses, Crown, Bell, Bandana, Fish clip, Flower, Shrimp clip, Blossom clip) by 16 rows (shrimpy, momo, ginger, midnight, latte, patches, blue, snow, oreo, mocha, silver, cloud, leo, button, puff, noodle). Every cell has its outfit in the right place: hats between the ears, the glasses on the eyes, the clips and the bow at an ear base, the scarf, bandana and bell at the chin. A thin light edge shows on the dark coats (momo, midnight, oreo, mocha) and a dark one on the light coats. Say which pairs look wrong (an outfit lost on a coat, one that hides the face, a hat that covers an ear).
2. `wardrobe-compact-x2.5.png`: for momo, shrimpy, latte and midnight, two rows each, the cat in a black strip at Ø20 (32 pt) and at Ø18 (24 pt) with a line at the strip's top: every outfit still reads, nothing rises above the line, nothing is cut at the bottom. Say which outfits stop reading (the bunny ears are the likeliest: two short bars) and on which coat.
3. `wardrobe-compact-true.png`: the same at true size for all 16 coats at Ø20.
4. `wardrobe-turn.png`: four coats with the head turned left and right: the hats lean with the head, the glasses flatten with the eyes, the clips stay at the ear base.
5. `wardrobe-collars.png`: momo and ginger with the bell, the bandana and the scarf over four collar styles (tag, band, kerchief, off): the bell hangs from the tag, the band and the kerchief's point, and from its own ring with the collar off; the scarf and the bandana cover the collar.
6. `wardrobe-preview.png`: the witch hat on momo at Ø170, Ø64, Ø48, Ø28, the notch's Ø20 at true size and at three times, and two small cats that are bare.
7. `wardrobe-auto.png`: the chooser with the Auto button reading "Auto: 2025-12-24, Santa hat" and Auto on.
8. `wardrobe-notch.png`: the notch mock with the crown on the notch's cat (compact), and `wardrobe-stage.png`: the Momo stage cat wearing it, with its collar.

If something is wrong (a clipped hat, an outfit that hides an eye, a glaring colour), say what and where in the report; do not fix numbers in the core on your own.

- [ ] **Step 3: Stop the browser and the server, and stop the plan here**

```bash
cd "${TMPDIR:-/tmp}/i0-shots"
playwright-cli close
kill "$(cat server.pid)"
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$(cat port)/notchmeow.html" || true
```

Expected: `000`.

**Stop here and report to the main session** (with `SendMessage`, as the brief says): the folder `${TMPDIR:-/tmp}/i0-shots` with the nine file names, a line on what each shows and anything that looks wrong. The main session shows the owner. **Task 7 starts only when the main session says go.** If the owner wants other shapes or colours, the numbers live in the `geometry` block of `cat-core.js` (shapes, sizes, positions), `OUTFIT_MIN` (floors) and the `outfits` group of `shared/theme.json` (colours); after any change, regenerate the fixture (`node scripts/gen-cat-fixtures.mjs`), the theme files (`node scripts/gen-theme.mjs`), the site CSS (Task 4, Step 3) and the page's palette copy (the test in `tests/cat/wardrobe.test.mjs` fails until it equals the theme), run the contract and take the pictures again.

---

### Task 7: Docs and the final checks

**Files:**
- Modify: `docs/CAT-CONTRACT.md`, `docs/THEME.md`, `CLAUDE.md`, `ARCHITECT.md`

**Interfaces:**
- Consumes: Tasks 1 to 6 and the owner's approval at the checkpoint. Produces: the docs the app plans cite.

- [ ] **Step 1: Write the docs**

The contract doc gains a row of the API table, a row of the fixture table, a section "The wardrobe (I-0)" before "The harness" and three decisions. `docs/THEME.md` gets a row for the `outfits` group. `CLAUDE.md` and `ARCHITECT.md` get one pointer bullet each, after the matching sub-project H bullet. If the owner's notes at the checkpoint changed a number (a floor, a size, a rule), change its sentence in the text below first.

````bash
W="${TMPDIR:-/tmp}/i0-work"
cat > "$W/docs_patch.py" <<'PY_EOF'
# Task 7: the docs. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def after_line(path, prefix, text):
    s = open(path, encoding='utf-8').read()
    lines = s.split('\n')
    hits = [i for i, l in enumerate(lines) if l.startswith(prefix)]
    assert len(hits) == 1, (path, prefix, len(hits))
    lines.insert(hits[0] + 1, text)
    open(path, 'w', encoding='utf-8').write('\n'.join(lines))

def edit(path, was, now):
    s = open(path, encoding='utf-8').read()
    assert s.count(was) == 1, (path, was[:70])
    open(path, 'w', encoding='utf-8').write(s.replace(was, now))

C = 'docs/CAT-CONTRACT.md'
after_line(C, '| Desktop cat (H-0) |', "| Wardrobe (I-0) | `OUTFIT_IDS`, `OUTFIT_NAMES`, `OUTFIT_GROUPS`, `OUTFIT_DRAWN`, `DEFAULT_OUTFIT`, `outfitIdOf`, `cleanWardrobeSettings`; `easterOf`, `autoOutfitFor`, `resolveOutfit`; `OUTFIT_ROLES`, `outfitWorn`; `OUTFIT_SLOTS`, `OUTFIT_ORDER`, `OUTFIT_MIN`, `outfitEdge`, `outfitRoom`, `outfitAnchors`; `outfitGeometry`, `outfitDigest` |")
after_line(C, '| `desktop-cases.json` |', "| `wardrobe-cases.json` | `ids`, `names`, `groups`, `drawn`, `defaultOutfit`, `roles`, `clean` (`outfitIdOf`), `settings` (`cleanWardrobeSettings`), `easter`, `auto` (`autoOutfitFor`: every boundary and bad dates), `easterWindows` (six days round Easter in twelve years, walked with the calendar), `resolve`, `worn`, `slots`, `order`, `min`, `edge` (all 16 coats), `rooms` (`outfitRoom`), `anchors` (`outfitAnchors`: four coats at Ø20, Ø28, Ø48 and Ø64, at rest and with the head turned), `strips`, `geometry` (every outfit's shapes on four pinned cases), `digests` (`outfitDigest` of every outfit on every coat at Ø18, Ø20, Ø48 and Ø64), `collars` (the bell, bandana and scarf over each collar style), `unknown` and `fine`. See \"The wardrobe (I-0)\". |")

section = r'''
## The wardrobe (I-0)

Sub-project I (`docs/superpowers/specs/2026-10-14-wardrobe-design.md`) lets the user dress the big cats: one of 16 outfits, or Auto, which follows the calendar. Its rules are pure and pinned by one fixture file, `wardrobe-cases.json`. All of it is new names, a new file and a new `outfits` group in `shared/theme.json`: no existing function, constant or fixture line changed (`node scripts/check-fixtures-additive.mjs 5f9051c` proves the fixtures). The prototype page draws all of it (the Wardrobe panel), so the page is the look and the core is the numbers. The 16 drawings are NotchMeow's own.

### The IDs and what is stored

- **18 selection IDs, in this order** (the grid's, the menus' and the shortcut's cycle): `auto`, `none`, `partyhat`, `santahat`, `witchhat`, `bunnyears`, `sunglasses`, `beanie`, `bow`, `scarf`, `roundglasses`, `crown`, `bell`, `bandana`, `fishclip`, `flower`, `shrimpclip`, `blossomclip`. They are frozen like the cat IDs, because they are stored; a new outfit gets a new ID at the end of its group. `OUTFIT_NAMES` has the UI names, `OUTFIT_GROUPS` the five rows of the grid (the two choices, Seasonal, Everyday, Cat extras, The cats' own) and `OUTFIT_DRAWN` the 16 that are drawn.
- **`outfitIdOf(v)`** keeps a string that is one of the 18 exactly as written and turns anything else (a capital, padding, a made-up name, a number, an object) into `auto`. **`cleanWardrobeSettings(raw)`** reads the `outfit` key of a stored block and returns `{outfit}`; it is a clean-up of its own, so `cleanCatSettings`, `cleanDisplaySettings`, `cleanDesktopSettings` and their fixtures stay as they were, and an app cleans the same stored block with each. Never throws.
- **Stored in:** macOS `UserDefaults` key `cat.outfit` (a string); Windows and Linux the `outfit` key of the `cat` block of `settings.json` (the Rust side must carry it through `clean_cat_block`, as it does for B's and H's keys). A fresh install is `auto`. The shortcut's action ID `wardrobe` is frozen too.

### Auto

`autoOutfitFor(y, m, d)` reads date numbers (the local calendar date, the northern calendar, the same for everyone) and the first matching rule wins, in this order: Dec 31 to Jan 2 `partyhat`; Dec 1 to Dec 26 `santahat`; Oct 1 to Nov 1 `witchhat`; Good Friday to Easter Monday (Easter minus 2 days to plus 1) `bunnyears`; Jun 21 to Aug 31 `sunglasses`; anything else, and a date that is not a real date, `none`. `easterOf(year)` is the Meeus/Jones/Butcher computation for 1583 to 9999 (`null` outside). The day difference is counted on date numbers, so a daylight-saving change cannot shift it; the fixture's `easterWindows` are walked with the calendar instead, as an independent check. `resolveOutfit(id, y, m, d)` is what is drawn: the stored ID cleaned, with `auto` replaced by the rule's answer (never `auto` itself). The stored value stays `auto`; an app re-resolves at launch and at the next local midnight.

### Who wears it

The role decides, not the diameter: `outfitWorn(role)` is true for `big` only. The apps map their views to roles: the cast's big cats (the island's main cat compact and open, both cats of Two cats mode, each agent's big cat) and the desktop cat are `big`; the pills' cats, the mini row and the grid are `small`; the subagent kittens are `kitten`. The compact notch's big cat is dressed too, at Ø20 in the 32-point strip (Ø18 in the 24-point strip of a screen without a notch).

### Where an outfit sits

- **Slots.** `OUTFIT_SLOTS` is `behind`, `neck`, `top`, and `OUTFIT_ORDER` shows the whole draw order with them in place without touching `PASSES`: behind pass `... ears, outfit.behind` (bunny ears, so the head covers their roots), front pass `foldEars, collar, outfit.neck, outfit.top, whiskers, badge, particles, balls` (the collar is not in `PASSES.front`; `COLLAR_PASS` places it). The whiskers and the badge stay in front of every outfit.
- **Anchors.** `outfitAnchors(p, s, D, o)` gives, in head-local px (before the tilt and squash, like `collarGeometry`): `top` (the crown between the ear bases, on the head outline), `gap` and `half` (the span between the ear bases), `lean` (a hat's lean with the face turn), `ears` (each base, tilt and tip), `eyes` (the eye frames), `chin` (the lower outline from 40 to 140 degrees, left to right, and its centre front), `neck` (the point the collar's tag hangs from) and `edge`. `o` is `{dpr, detail, earScale}`; `earScale` defaults to what the renderers use.
- **The edge.** `outfitEdge(p)` is `light` for a coat whose flat head colour has a luminance under 100 and `dark` otherwise; a shape whose colour role is `edge` is drawn in the theme's `edgeLight` or `edgeDark`.
- **Room.** `outfitRoom(anchors, headY, ceiling)` is the distance from the crown to the strip's top (`ceiling`, in the same coordinates as `headY`) less the ear fit's 0.5 pt margin, never negative; `null` without a ceiling. The apps pass `earCeiling` only in the compact notch, so only there is the room finite.

### What an outfit is made of

`outfitGeometry(id, p, s, D, o)` returns the outfit's shapes in paint order as plain data (an empty list for `none`, `auto` and anything unknown), in three kinds, all in head-local px: `{k:'poly', slot, fill, stroke, sw, a, fine, pts}` (closed), `{k:'curve', slot, stroke, sw, a, fine, pts}` (open, round caps and joins) and `{k:'ellipse', slot, fill, stroke, sw, a, fine, x, y, rx, ry, rot}`. `fill` and `stroke` are colour roles: the keys of the theme's `outfits` group (`shared/theme.json`, 38 colours) or `edge`. `a` is the alpha and `sw` the stroke width in px. A `fine` shape (a glint, a star, a rib, a bell's slot) is left out when `D` is under 28. `o` is `{dpr, detail, earScale, collar, room}`; `collar` is a collar style: the bell hangs from the collar (the tag's lower edge, the middle of the band, the kerchief's apex, or its own ring at the front of the neck with the collar off) and `outfitGeometry` never changes the collar. The scarf covers the band, the bandana covers the kerchief and is bigger than it, and the bow, hats, glasses and clips leave the collar alone.

- **One rule for every coat.** The shapes come from the coat's own numbers (the ear bases, the eye frames, the head outline), never from a coat list. Hats are as wide as the gap between the ear bases (the witch brim is the widest, and stays narrower than the ear spread); the glasses follow the eye frames and flatten with the face turn (a lens whose eye is out of sight is not drawn); clips, the bow and the flower sit at an ear base.
- **Floors.** `OUTFIT_MIN` is in **device** pixels, as `COLLAR_MIN` is: `height` 6 (a hat, crown or bunny ear's rise), `line` 1, `rim` 2, `ball` 3 (the radius of a pompom, a bell or a gem), `span` 6 (the narrowest solid part). The compact notch's Ø20 cat is 40 device pixels wide at 2x, and the floors are set for it: the fixture's `digests` and the self-checks cover every outfit on every coat at Ø18 and Ø20.
- **Fit to the strip.** A hat, the crown and the bunny ears rise by a natural height, shortened to `o.room` and held at the `height` floor when even that is short (not hidden). At Ø20 and Ø18 every outfit stays inside the strip, top and bottom, on every coat: the self-checks prove it.
- **The digest.** `outfitDigest(shapes)` is `{n, pts, bbox, mx, my}`: the number of shapes and points, the box that holds them (an ellipse counts as its axis-aligned box), and the mean point. The fixture's `digests` pin it for all 256 pairs at four sizes, so a port compares numbers within 1e-9 and never a float checksum.

### Notes for ports

- Replay `wardrobe-cases.json` with `dpr` 2 unless a case says otherwise; the `strips` key says which strip each compact size sits in (`room` is `outfitRoom(anchors, strip / 2, 0)`).
- An app draws the shapes with its own painter and resolves the roles through the theme (`Theme.Outfits` on the Mac, `THEME.outfits` on Windows and Linux). The painter only paints: it never reads a coat.
- The apps compute `room` themselves where `earCeiling` is given, and pass the ear scale they drew the ears with as `o.earScale`.
- **The prototype page keeps a copy of the palette** between `@@OUTFIT-PALETTE` markers; `tests/cat/wardrobe.test.mjs` keeps it equal to `shared/theme.json`.
'''
edit(C, '\n## The harness\n', section + '\n## The harness\n')
after_line(C, '- **Kittens mirror to the left in the right half of the screen**', "- **Outfits belong to a role, not to a size.** The compact notch's Ø20 cat is dressed; the floors and the room (`outfitRoom`) keep every outfit readable and inside the strip there, and the pills' small cats and the kittens stay bare at any size.\n- **Auto is a choice, not an outfit.** The stored value stays `auto`; `resolveOutfit` gives what is drawn. Its dates have no hemisphere or locale (the same for everyone).\n- **The wardrobe has its own clean-up,** like Display and Desktop: `cleanWardrobeSettings` reads only `outfit`.")

after_line('docs/THEME.md', '| `greeting` | `streaks` |', "| `outfits` | the 38 colours of `shared/theme.json` | The outfits' colour roles (`partyA`, `santaRed`, `gold`, `bunnyInner` and so on) and the two edges `edgeLight` and `edgeDark`. `Theme.Outfits`, `THEME.outfits` and `--nm-outfits-*`. The prototype's Wardrobe panel keeps a copy that a test holds equal |")

after_line('CLAUDE.md', '- `cat-core.js` also holds sub-project H\'s rules for the desktop cat', "- `cat-core.js` also holds sub-project I's rules for the wardrobe (the outfits), all new names pinned by one fixture, `wardrobe-cases.json`: the IDs and `cleanWardrobeSettings` (a clean-up of its own), `easterOf`, `autoOutfitFor` and `resolveOutfit` (Auto's dates), `outfitWorn(role)` (**the big-cat role is dressed at every size, the compact notch's Ø20 cat included; kittens and small cats are bare**), `outfitAnchors`, `outfitRoom` and `outfitGeometry` (the shapes of the 16 outfits, with colour roles from the `outfits` group of `shared/theme.json`) and `outfitDigest`; `docs/CAT-CONTRACT.md`, \"The wardrobe (I-0)\". The 18 selection IDs (`auto`, `none` and the 16 outfits) and the action ID `wardrobe` are frozen like the cat IDs. Every outfit's drawing is NotchMeow's own: never read or copy upstream Coucou's wardrobe code or art (reserved).")

after_line('ARCHITECT.md', '   - **Sub-project H on Windows/Linux:**', "   - **Sub-project I (the wardrobe):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/wardrobe-cases.json` (new names only; the prototype's Wardrobe panel draws it, and `shared/theme.json` has the `outfits` colours): `OUTFIT_IDS` and `cleanWardrobeSettings`, Auto's calendar (`easterOf`, `autoOutfitFor`, `resolveOutfit`), who wears it (`outfitWorn(role)`: the big-cat role at every size, the compact notch included), where it sits (`outfitAnchors`, `outfitRoom`, the slots `OUTFIT_SLOTS` and `OUTFIT_ORDER`) and its shapes (`outfitGeometry`, checked by `outfitDigest`); see `docs/CAT-CONTRACT.md`, \"The wardrobe (I-0)\". The two app plans (I-mac, I-tauri) build on it.")
print('docs written')
PY_EOF
python3 "$W/docs_patch.py"
git diff --stat | tail -6
````

Expected: `docs written` and a stat of four files changed (`ARCHITECT.md`, `CLAUDE.md`, `docs/CAT-CONTRACT.md`, `docs/THEME.md`).

- [ ] **Step 2: Every check**

```bash
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗|fixture files|identical"
node scripts/check-fixtures-additive.mjs 5f9051c | tail -2
node scripts/gen-theme.mjs --check | tail -1
bash scripts/test-theme.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗"
bash scripts/test-cat-theme.sh 2>&1 | tail -1
bash scripts/check-site.sh 2>&1 | grep -E "✗|✓"
bash scripts/check-no-leftovers.sh 2>&1 | grep -E "✗|✓" | head -3
(cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)" && npx --no-install tsc --noEmit && echo "tsc ok")
git status --short
```

Expected: `# tests 312`, `# pass 312`, `# fail 0`, `✓ 16 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`; `+ wardrobe-cases.json is new` and `✓ fixtures changed only by addition since 5f9051c`; `✓ 3 theme files match shared/theme.json`; `# tests 8`, `# pass 8`, `# fail 0`; `All tests passed.`; three `✓` lines from the site check; `✓` lines from the leftovers check and no `✗`; `ℹ pass 372`, `ℹ fail 0` and `tsc ok`; and ` M` for the four doc files only.

- [ ] **Step 3: Commit**

```bash
W="${TMPDIR:-/tmp}/i0-work"
git rev-parse --show-toplevel; git branch --show-current
cat > "$W/msg.txt" <<'MSG_EOF'
docs: the wardrobe contract

A section "The wardrobe (I-0)" in docs/CAT-CONTRACT.md (the IDs and what is stored, Auto, who wears it, slots and anchors, the shapes, floors and fit, the digest, notes for ports), its two table rows and three decisions, the outfits group in docs/THEME.md, and the pointer bullets in CLAUDE.md and ARCHITECT.md.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG_EOF
git add docs/CAT-CONTRACT.md docs/THEME.md CLAUDE.md ARCHITECT.md
git commit -q -F "$W/msg.txt" && git log --oneline -6
```

Expected: the six commits of this plan on top of the base.

Then the controller dispatches `nm-reviewer-deep` over the whole branch (`git diff notchmeow/rebrand...HEAD`): cross-task contracts (the roles of the shapes against the theme, the fixture against the core, the page against the contract), the licensing rule (no upstream wardrobe, no Coucou or Mochi names in the new code), the privacy rules (nothing here touches the network, a secret or the hook path) and the "only new names" rule. It fixes what the review finds and reports (and pings the main session).

---

## Open questions for the owner

Each has the answer this plan used.

1. **The greeting's cat.** The cat that falls in at launch is a big cat. This plan leaves it bare in the prototype (it starts at Ø4 and the floors would swamp it), and the apps' plans decide whether it wears the outfit once it has landed. Proposed: dress it from the moment it settles, so the greeting ends on the dressed cat.
2. **The looks.** Every shape is an intent from the spec, drawn once; the checkpoint's pictures are how the owner changes any of them. The bunny ears at Ø18 and Ø20 are the likeliest to want a bolder drawing (they are two short bars), and the bell is small on the notch's cat.
3. **Floors.** `OUTFIT_MIN.height` is 6 device pixels (3 points) so that the smallest room (Noodle's tall ears under the 24-point strip leave 3.4 points) still gets a hat. A larger floor would push a hat past the strip's top on that coat.
4. **Auto's clock.** The dates are the local calendar date; Auto changes at the next local midnight. A Mac left running over midnight in another time zone changes at its own midnight.

## The owner's answers (2026-10-14)

The owner approved the spec and this plan with every proposed answer above:
1. The greeting's cat wears the outfit from the moment it settles (the apps' plans do it; the prototype's greeting stays as this plan has it).
2. The looks at the notch's size are fine as drawn, including the bunny ears and the bell; the checkpoint pictures remain the place to change any shape.
3. `OUTFIT_MIN.height` stays 6 device pixels.
4. Auto changes at the local midnight.

One change asked by the main session before the checkpoint: **the shrimp clip must read as a shrimp**, not an orange "C" (the dry run's sheet). In Task 3, draw it with a curled, segmented body, a fanned tail and small legs or feelers, and check it on the Task 6 pictures at the open and the compact sizes.

## Self-review notes

- **Spec coverage:** Outfits (the 18 IDs, order, names, groups, the 16 drawings): Tasks 1 and 3. One at a time, Auto: Task 1. Who wears it by role at every size, the compact Ø20 and Ø18 checked against floors: Tasks 1 and 3 and the pictures. Pickers (a Wardrobe section with a live preview and a coat picker that stores nothing, the island cat's new menu, the desktop cat's menu, ⌃⌥G cycling through `auto` and `none` too): the panel here is the look (preview, coat picker, date); the menus and the shortcut belong to I-mac and I-tauri, which the contract's `OUTFIT_IDS` order and the `wardrobe` action ID serve. Storage: `cleanWardrobeSettings` and the key names (Task 1, docs). Contract: IDs, Auto, who, anchors, geometry, slots and order, floors, fit to the strip, collar interplay (Tasks 1 to 3). Colours in `shared/theme.json`: Task 4. Testing: the fixture (every section the spec lists), the 16 by 16 sheet and the strips (Task 6), `check-fixtures-additive.mjs`, `test-theme.sh`, `check-no-leftovers.sh`. Rounds step 1 (I-0) and its owner checkpoint: Tasks 6 and 7. The app plans' work (settings, drawing, the one-shot, menus, shortcut) is out of this plan.
- **Placeholders:** none; every step shows its code or its command and its expected output.
- **Names:** `outfitRoom`, `outfitAnchors`, `outfitGeometry`, `outfitDigest`, `OUTFIT_*` and the fixture's keys are spelled the same in the core, the generator, the tests, the page and the docs (`wardrobe.test.mjs` replays every fixture section, and the page test pins the call sites).
- **Differences from the spec's wording, chosen while writing the plan:** `OUTFIT_NAMES`, `OUTFIT_GROUPS` (rows of the grid), `OUTFIT_ROLES`, `OUTFIT_ORDER`, `outfitRoom` and `outfitDigest` are named in the plan and added to the spec's list; the digest holds a mean point instead of a checksum (a float checksum cannot be compared within a tolerance); `chin` is the real head outline's lower arc (with Shrimpy's fluff) rather than the collar's inset ring, and the collar's own geometry is read separately for the bell.

## Dry run (2026-10-14)

The plan was run before it was handed over, in a throwaway `git clone --local --shared --branch notchmeow/rebrand` at `5f9051c` (the scratchpad's `i0-replay`, with the plan and the spec committed on top as the controller does, a new branch `i0/wardrobe-contract` and `windows/node_modules` copied with `cp -cR`), by a small runner that extracted every fenced `bash` block of Tasks 0 to 7 (34 blocks) and ran them in order, each in its own shell. `bash -n` reported 0 problems, every block exited 0, and every expected output above is what it printed: the red runs (`# fail 8`, `5`, `9`, `1`, `1`), the green runs (`# tests 8`, `13`, `22`, `23`, `24`), the contract's 296, 301, 310, 311 and 312 tests, `✓ 16 fixture files match cat-core.js`, the additive check, the theme, Swift (`All tests passed.`), site and leftovers checks, the Windows `npm run check:cat` (372 pass) and `npx tsc --noEmit`, the page's click-through (Auto on 2025-12-24 is the Santa hat, the 18 choices resolve, the notch's canvas changes with the witch hat, no console errors) and the nine pictures, which were opened and looked at: the 16 by 16 sheet, the compact rows at Ø20 and Ø18 on all 16 coats, the head turned and the collar strips. Nothing was committed to the main checkout, pushed or installed, no NotchMeow app was started, and the only files this work added to the main checkout are this plan and the edits to the spec.

What drafting the plan against the code found, all fixed in the text above: the 12-digit fixture format cannot hold a sum of coordinates (1000 or more), so the digest holds a mean point; a hat's pompom, a crown's gems and a stadium shape's end caps stuck out of the gap between the ear bases or above the strip, so they are sized from their outer edge; the 10 device-pixel hat floor left no room for Noodle's ears under the 24-point strip (3.4 points), so the floor is 6; the scarf's tail and the bandana's apex went below the 24-point strip; adding a theme group made the site's bundled CSS stale (`scripts/check-site.sh` fails until `docs/assets/cats.css` is rebuilt: Task 4, Step 3); the theme tests list the groups and the Swift enums, so they change too; the first compact picture cut off its right-hand columns, so Task 6 widens the page before it takes the sheets.
