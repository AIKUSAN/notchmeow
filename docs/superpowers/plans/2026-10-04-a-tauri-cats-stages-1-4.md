# A-tauri Cats, Stages 1 to 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shrimpy, Momo and the fourteen other coats replace the upstream character in the Windows/Linux Tauri app: a still cat at every size, the 11 states in Playful and Classic motion with gaze and face warp, emotes, the mouth and personality, the new greeting (with its header and its session cats), the four-step file catch in the drop view, the refused-file hairball (a refused file is caught, gagged on and coughed up, then the existing note shows) and the Playful error hiss that ends in a hairball.

**Architecture:** `windows/src/mochi/` becomes `windows/src/cat/` and is split into `engine.ts` (the same public members as today), `renderer.ts`, `presets.ts`, `motion/playful.ts`, `motion/classic.ts` and `personality.ts`, plus three small modules the spec's split needs underneath them (`base.ts`, `types.ts`, `geometry.ts`). Every file is a TypeScript port of `design/prototype/cat-core.js`, the tie-breaker, and is tested in plain Node against the A-0 fixtures in `tests/fixtures/cat/` within 1e-9 R, with the clock and the randomness injected. The renderer ports the prototype's canvas drawing, in a *behind* pass, the head and a *front* pass. The look is checked by eye on a `?dev` contact sheet served by Vite alone, next to the prototype page.

**Tech Stack:** TypeScript 5 and Vite 6 (already in `windows/`), Canvas 2D, Node 22 (`node --test` reading the TypeScript source with `--experimental-strip-types`), `playwright-cli` (headless Chromium, for the eye checks only). No new npm or cargo dependency.

**Spec:** `docs/superpowers/specs/2026-10-04-cats-in-app-design.md` as revised in `a6ec93c` (the A-tauri row of §1, "Room for later sub-projects", §2 including "A-0b, contract additions", §3, §5 and "Stages"). The character rules are in `docs/superpowers/specs/2026-10-03-notchmeow-design.md`, "Sub-project A, steps" §2. The contract this plan is tested against is `docs/superpowers/plans/2026-10-04-a0-cat-contract.md`, merged as `f68b25b`, and extended by A-0b (`docs/superpowers/plans/2026-10-04-a0b-contract-additions.md`, merged as `6adf584`): `design/prototype/cat-core.js`, the eight files in `tests/fixtures/cat/` (A-0's seven and A-0b's `collar-cases.json`) and `docs/CAT-CONTRACT.md` (read its "Notes for ports" and its "Collar, ear fit and flat fills (A-0b)" section: this plan follows every one). Read `design/prototype/cat-core.js` and `design/prototype/notchmeow.html` before starting: every number in this plan is theirs.

**Base:** branch `a-tauri/stages-1-4`, in a git worktree, from `notchmeow/rebrand` at `49a9d1a` or later, so A-0 (`f68b25b`) and A-0b (`6adf584`) are both in the history. `e1/polish` (AI code under `windows/`) may merge first: this plan's edits to `island.ts`, `state.ts` and `views.ts` are anchored on lines that it does not touch. Nothing is pushed.

**A-0b, merged.** A-0b (`docs/superpowers/plans/2026-10-04-a0b-contract-additions.md`) landed as `6adf584`, so the ear fit, the compact flat fills and the collar are in `cat-core.js` and in the fixtures, and every step below is written against the merged contract. The items this plan uses are `EAR_FIT` and `earFit` (the exact solve of the ear's top edge; `earFit` and `earFitCases` in `geometry-cases.json`), `detailLevel`, `FLAT_FILL`, `mixHex` and `flatFillColors` (`flatFill`, `detailLevels` and `flatColors`), and `earScale` on every compact cat with the fit on top (`earScale(D) * f`). The collar (`COLLAR_STYLES`, `collarStyleOf`, `collarGeometry`, `COLLAR_MIN`, `COLLAR_PASS` and `collar-cases.json`, and `collarPass` in `geometry-cases.json`) is for stage 6: stages 1 to 4 draw no collar. This plan still never edits `cat-core.js` or `tests/fixtures/cat/`: if the TypeScript and a fixture disagree, the TypeScript is wrong, and a change in the core is the main session's job, done once, which this branch picks up by merging `notchmeow/rebrand`. Where the TypeScript re-implements a contract function it keeps the core's name (`EAR_FIT`, `earFit`, `detailLevel`, `FLAT_FILL`, `mixHex`, `flatFillColors`). `earFit` is tested twice, against the 92 `earFitCases` and against a brute-force walk of the ear's outline; the flat-fill rule against `detailLevels`, `flatFill` and `flatColors`, and the renderer against the same numbers. The engine's `earRoom` stays Windows' own: `earCeiling = cy - earRoom` (the room is the app's, the ceiling is the contract's). The Mac plan (`docs/superpowers/plans/2026-10-04-a-mac-cats-stages-1-4.md`, its Tasks 2 and 4) ports the same items. Wherever a step cites A-0b it reads "(A-0b, merged `6adf584`)".

## Global Constraints

Every task's requirements include this section. Values are copied from the specs.

- **Cat IDs are frozen, in this order:** `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle`. An unknown stored ID falls back to `shrimpy`. The default cat is `shrimpy` until the Settings section arrives (the next plan).
- **Tolerance:** numbers compare within **1e-9 R** against the fixtures (12 significant digits). Strings, booleans, nulls and the shape of the data compare exactly. **No pixel tests:** the look is checked by eye.
- **`cat-core.js` is the tie-breaker.** If this plan's TypeScript and a fixture disagree, the module decides: fix the TypeScript. This plan never edits `design/prototype/cat-core.js` or `tests/fixtures/cat/`: a change there is the main session's. **Randomness** comes from an injected `rand()` and the clock from an injected `now()`; the order of the `rand()` calls is part of the contract. The cat code never calls `Math.random()` or reads a clock except as the late-bound default of a `BotEngine`.
- **Detail levels:** head width Ø28 and up draws the full cat; below Ø28 the compact cat: ink eyes; no irises, "M" stripes, cheek bars or whiskers (Momo's white map and Shrimpy's crown band, pads and chin stay); **flat fills** (one colour for the head, the ears and the ruff, no rim light gradient, a flat tabby crown and a flat point mask), because a gradient cannot be seen at that size. The ears are scaled down (`earScale`: 0.8 at Ø20 and below, easing to 1 at Ø28; **provisional**, the owner confirms it at checkpoint 1) and, in the compact island, fitted under the top of the strip (`earFit`), because the strip's top is the top of the screen. The flat fills (`detailLevel`, `FLAT_FILL`, `flatFillColors`) and the ear fit (`earFit`) are the contract's (A-0b, merged `6adf584`): the flat point mask is `FLAT_FILL.point` (0.86 R by 0.54 R at alpha 0.85, in the point colour of `flatColors`), not the Mac draft's 0.5 R by 0.34 R; every compact cat wears `earScale(D)`, and where an `earCeiling` is given the fit multiplies it (`earScale(D) * f`). If the owner changes the ear scale at checkpoint 1 the session stops: the main session changes `COMPACT_EAR_SCALE` once in `cat-core.js` and its fixtures, and this branch picks it up. This plan never edits `cat-core.js`.
- **Face warp:** the face takes 82 % of the 0.62 rad gaze yaw, 60 % of the 0.5 rad pitch looking up and 32 % looking down; the muzzle stands proud by +0.12 and the nose by another 0.05 R; the outline leans 0.1 rx and the head shifts 0.08 R toward the cursor; the near eye never foreshortens below 55 %; the pupils travel up to 0.24 of the eye width; the cursor curve is tanh over 240 px across and 180 px up and down.
- **Badge:** beside the right ear, 1.4 R right and 0.92 R up; on the left in the compact notch.
- **Mouth:** the upstream slot spring, ω₀ = 2π/0.25 and ζ = 0.6, **stepped at most 1/60 s at a time** (one step at 60 fps or faster, several on a slow frame: a single step of 0.066 s or more diverges to NaN); six animatable values (open, smile, tongue, round, skew, wavy).
- **No collar in stages 1 to 4.** The agent colour becomes an optional collar (band and tag, band, neckerchief, off; the default is Off) in stage 6, together with its Settings rows. Nothing here draws one, and `bodyColor` stays unused. The collar's contract items are A-0b's (A-0b, merged `6adf584`): `collarGeometry`, `collar-cases.json`, `COLLAR_STYLES`, `collarStyleOf`, `COLLAR_MIN` and the pass, `collarPass`; stage 6 ports them, and nothing in stages 1 to 4 touches `PASSES`.
- **Hairball** 2.4 s. **Zoomies** 2 s, and they play after an agent finishes **5 minutes** of working, thinking or searching (approval and question pauses don't reset that clock) and on waking from sleep.
- **File catch, four steps:** open wide while a file hovers; snap wider on the drop while the file flies in; gulp with a squash; chew for 0.85 s with happy eyes. The file is drawn in front of the cat, hovering and flying, as in the prototype's catch, and flies along `flightAt` over `FLIGHT_MS` (380 ms).
- **Refused files, the same on both apps.** *Refused* is the app's existing refusal rule, decided in Rust by `attachments::screen` and reported by `ingest_file`: apps, archives, disk images, videos and anything over 25 MB (`files.rs`, `ai/attachments.rs`). The catch plays as for any file (open wide while hovering, snap wider on the drop, the file flies in); then, instead of gulp and chew, the cat gags and coughs the file up as a **hairball (2.4 s)**, and then the existing refusal note shows. **Its sound:** the cat plays the existing `annoyed` sound once, when the gag starts (the file has reached its mouth; the heaves follow 120 ms later), and the note that shows after the hairball plays no sound; no `approve` chime and no success check mark. The `pop` at the cough is wired later, by sound Stage 3: neither plan adds it now. Any other `ingest_file` failure (an unreadable file, a failed copy, a folder) keeps today's behaviour and sound, the note at once with its `error` sound, with no hairball.
- **Greeting:** the new greeting (`GT2`, Greeting v2 as a cat): the cat falls in with a landing squash, bounces, slides aside, pops up and does a quick paw wave, then slides back and ends like the old greeting. 5.74 s in the prototype. No upstream sound: the call sites keep the sound names `greet` and `blip`. It draws the header ("NotchMeow" on the left, "Hi! Shrimpy is watching your agents." on the right) and, as the island collapses, the session cats: four blue-tinted cats that pop in with a scale, sized and placed as the real compact island's mini grid (Ø13 here, because that is what this app's grid is).
- **The cat replaces only what is drawn inside the existing canvases.** Never restyle a shipping view (pills, cards, Settings, chat…). Never rename a pill ID or a contract string (`nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`). Leave hooks, the relay and the island state machine (`island/fsm.ts`, `island/hooks.ts`) untouched. The Rust side is untouched.
- **Files loaded by `npm run check:cat`** (everything under `windows/src/cat/` except `dev.ts` and `minibots.ts`, plus `core/sound.ts`, `core/layout.ts` and `upload/refusal.ts`) use erasable TypeScript only (no `enum`, no `namespace`, no constructor parameter properties), `import type` for types, and relative imports **with the `.ts` extension**, because Node reads the source as it is. Files outside `src/cat/` keep the repo's extension-less imports.
- **No new dependency.** No `npm install` of anything new, no cargo change. This plan has no Rust step. If one ever appears, Rust runs only through `windows/scripts/cargo-linux.sh` (Docker Desktop running), with its own target directory because other worktrees share that Docker volume: `windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/a-tauri-1-4`. Never install a toolchain on the host.
- **Performance:** 0 % CPU while the island is hidden. The island's frame loop already stops when it is hidden and nothing here may restart it.
- **Commits:** local only, never pushed. End every commit message with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; an implementer running another model names that model on that line instead.

## Review Focus

The spec says what the cats must do. It is silent on these inputs, and each would bite a person first. Each line names its test.

1. **A stored value that is not valid:** an unknown cat ID, state, emote, motion style or personality preset, and a hand-edited personality (a trait outside 0 to 1, missing, or the wrong type). Expected: a fallback (Shrimpy, Playful, Balanced), 0 to 1, missing counts as 0.5, or a no-op; never a throw and never NaN. Tests: Task 2 `catById`, Task 5 `personaNamed`, `slide` and "a hand-edited personality", Task 6 "an unknown state is ignored", Task 8 "an unknown emote changes nothing".
2. **A bad or slow frame time:** zero, negative, NaN or huge `dt`, as from a sleeping laptop, and a slow frame of a quarter of a second. Expected: the pose stays finite, `dt` is held to 0 up to 0.25 s, and the mouth spring (which blows up in one step of 0.066 s or more) is stepped at most 1/60 s at a time. Tests: Task 6 "a bad frame time" and "a slow frame is several spring steps".
3. **A head pushed past what it can show:** rolled over the top, turned away, or a head width of 0. Expected: the face fades, the eyes and nose are hidden, `mouth` is null, and no NaN reaches the canvas. Tests: Task 3 "a head pushed past what it can show", Task 4 "a cat that is turned, rolled or squashed past the normal range".
4. **A cat squeezed into the compact strip:** at Ø20 in a 32 px strip, a cat that hops with its ears up pushes them above the top of the screen, where they are cut off. Expected: the ears are fitted under the strip's top edge, and a calm cat keeps its ears. Tests: Task 3 "ear fit" (the contract's exact solve, against a brute-force outline and against `earFitCases`) and Task 4 "the ears are fitted under the strip" and "every compact cat wears the compact ear scale".
5. **A drop that is refused, or fails, in any order:** the app's refusal arriving before the file reaches the mouth, after it, or never; any other `ingest_file` failure (a folder, an unreadable file, a failed copy); a second drag after a refused one; the user leaving the drop flow while the hairball plays. Expected: a refusal gives exactly one hairball, then the note, with one `annoyed` sound as the gag starts, a silent note, no approve chime and no check mark; any other failure gives the note at once, with its `error` sound, and no hairball; nothing stuck open, and the note never yanked in after the user has left. Tests: Task 10 "a refusal that comes before the file arrives", "after the file has arrived", "a new drag after a refused drop starts clean", the stray-arrival test and "the cat plays annoyed once, when the gag starts, and nothing else"; Task 12 `refusal.test.mjs` (which failures count as a refusal, pinned to the Rust texts, and "the note of a refusal is silent"); the island's guard is checked by hand in Task 12.

---

## File Structure

All paths are under `windows/`. The first six files of `src/cat/` are the spec's split; `base.ts`, `types.ts` and `geometry.ts` are the small pure modules underneath them (the spec's `renderer.ts` and `engine.ts` would otherwise be 900 lines each), and `dev.ts` is the `?dev` page.

| Path | Responsibility |
|---|---|
| `src/cat/base.ts` | Helpers (`rng`, `EZ`, `lerp`, `clamp`, `seg`, `hex`, `wrapA`, `tm`, `own`), the state tables (`COL`, `TINT`, `GLOW`, `BADGE`, `MOUTH`, `EMOUTH`, `mouthFx`, `BUSY`) and the work clock (`workClockStep`, `zoomiesOnFinish`, `ZOOM_AFTER_MS`). |
| `src/cat/types.ts` | `CatPreset`, `Pose`, `Targets`, `Particle`, `Ball`, `EyeShape` and the other shared types. |
| `src/cat/presets.ts` | The 16 coats, `makeCat`, `kittenOf`, `CAT_IDS`, `catById`. |
| `src/cat/geometry.ts` | `newPose`, `layout`, the face warp, outline, ears, the ear fit (`EAR_FIT`, `earFit`; A-0b, merged `6adf584`), the detail rule and the flat fills (`detailLevel`, `FLAT_FILL`, `mixHex`, `flatFillColors`; A-0b, merged `6adf584`), cursor look, pupil travel, `flightAt`. No canvas. |
| `src/cat/renderer.ts` | `drawCat` = `frameOf` + `drawBehindPass` + `drawHeadPass` + `drawFrontPass`, `stillView`, `enginePaws`, `drawFileIcon`; the compact cat's flat fills and the ears under `earCeiling` (A-0b, merged `6adf584`). |
| `src/cat/personality.ts` | The six presets, `persMultipliers`, `personaNamed`, `slide`, `normPers`. |
| `src/cat/motion/classic.ts`, `src/cat/motion/playful.ts` | The two `MotionProfile`s. |
| `src/cat/engine.ts` | `BotEngine`: tweens, states, emotes, the mouth spring, zoomies, hairball, the file catch, and the old character's public members. |
| `src/cat/greeting.ts` | The new greeting: the pure `greetingPose` and the `Greeting` controller that draws it (halo, streaks, header, the cat with its paws, the four session cats). |
| `src/cat/minibots.ts` | The mini cats (moved from `mochi/`, unchanged). |
| `src/cat/dev.ts` | The `?dev` contact sheet and live panels. Dev server only. |
| `src/upload/canvas.ts`, `src/upload/sequence.ts` | The drop view draws the cat, and the file in front of it; the sequence can hold for a refused file. |
| `src/upload/refusal.ts` | `classifyIngestError`: which `ingest_file` failures are the app's refusal of a file (a hairball) and which are not. Pure. |
| `src/island/island.ts`, `src/views/views.ts`, `src/core/state.ts`, `src/main.ts` | Small edits: imports, gaze constants, badge side, the ear room in the compact notch, the drop wiring, the `?dev` entry. |
| `scripts/cat-tests/*.mjs` | The checks, run with `npm run check:cat`: one file per area (including `refusal.test.mjs`), plus `util.mjs` (fixture loader, the 1e-9 comparison and the brute-force ear top), `engine-util.mjs` (the fixtures' harness) and `fake-canvas.mjs`. |
| `dev/upload-preview.ts` | The existing drop-sequence harness, taught the catch (`?refuse` for a refused file). |
| `README.md`, `../.github/workflows/windows-tests.yml`, `../ARCHITECT.md`, `../CLAUDE.md` | Docs (the Windows lines of the two guides), and one CI step. |

**How the fixtures are loaded.** `scripts/cat-tests/util.mjs` reads `tests/fixtures/cat/<name>.json` with `fs.readFileSync(new URL("../../../tests/fixtures/cat/...", import.meta.url))`, and each test imports the `.ts` modules directly (Node 22 strips the types). `compare()` allows 1e-9 on numbers and nothing on structure, strings or key sets. `engine-util.mjs`'s `makeEngine` builds an engine the way `docs/CAT-CONTRACT.md` describes ("The harness"): a fake clock at 0, `rng(seed)`, R = 1, one `update(1/60)` per frame.

**Staged files.** `engine.ts`, `geometry.ts`, `motion/playful.ts`, `motion/classic.ts` and `dev.ts` grow over the stages. Each is created whole in its first task, with marker comments of the form `// @@S3-METHODS` at the places where a later stage adds code. A later task **inserts its block above the marker line and leaves the marker in place**, or, where a block replaces earlier code, **replaces the exact old text**. Task 13 removes every marker.

**Agents** (CLAUDE.md: the lightest model that fits). Tasks whose complete code is below are transcription plus a test run: `nm-implementer-light`. If a fixture check fails after a careful transcription and the difference is not a typo, hand that task to `nm-implementer-deep`. Tasks that also run a browser and judge screenshots, or edit the island: `nm-implementer`. Task reviews: `nm-reviewer`; the final whole-branch review: `nm-reviewer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review`.

**Order of tasks**

| Stage | Task | What | Agent |
|---|---|---|---|
| 1 | 1 | Rename `mochi/` to `cat/`, the check harness, helpers and tables | `nm-implementer-light` |
| 1 | 2 | The 16 coats and their kittens | `nm-implementer-light` |
| 1 | 3 | Geometry, the face warp and the ear fit | `nm-implementer-light` |
| 1 | 4 | The renderer (compact flat fills, ears under the strip) and the `?dev` contact sheet | `nm-implementer` |
| | | **Checkpoint 1:** the contact sheet next to the prototype, owner's OK | the executing session |
| 2 | 5 | Personality | `nm-implementer-light` |
| 2 | 6 | The engine and both motion styles: the 11 states | `nm-implementer-light` |
| 2 | 7 | The island uses the cat (gaze, badge side, ears under the strip) and the States panel | `nm-implementer` |
| 3 | 8 | Emotes, idle habits, zoomies, the paw wave, the poke | `nm-implementer` |
| 3 | 9 | The emote and personality panel | `nm-implementer` |
| 4 | 10 | The file catch, the hairball and the error hiss | `nm-implementer` |
| 4 | 11 | The new greeting (header, paws, session cats) | `nm-implementer` |
| 4 | 12 | The drop view catches the file; a refused file comes back as a hairball | `nm-implementer` |
| 4 | 13 | Cleanup, docs, CI and the final checks | `nm-implementer-light` |
| | | **Checkpoint 2:** the contact sheet and the drop view next to the prototype, owner's OK | the executing session |
| | | Whole-branch review | `nm-reviewer-deep` |

## Setup (the controller, once)

This plan runs in its own worktree chat session on **Sonnet 5.5 at high effort** (`CLAUDE.md`, worktree sessions). The main session starts it in three steps: the session's first turn only does this Setup and reports "ready", then the main session sets its model and effort, then sends the controller brief.

- [ ] Put the session's worktree on the plan's branch, and copy the main checkout's front-end packages. This plan adds no package, so nothing is downloaded: no `npm install` or `npm ci`. `cp -c` makes an APFS clone, which is instant and takes no extra disk space. It must be a real folder, not a symlink, because `windows/.gitignore` ignores `node_modules/` only as a folder.

```bash
git status                                   # must be clean
git switch -c a-tauri/stages-1-4 notchmeow/rebrand
git log --oneline -3                         # A-0's and A-0b's merges must be in history
git merge-base --is-ancestor f68b25b HEAD && git merge-base --is-ancestor 6adf584 HEAD && echo "A-0 and A-0b are in the history"
git ls-files docs/superpowers/plans/2026-10-04-a-tauri-cats-stages-1-4.md   # this plan's path: it is tracked, so the worktree has it
cp -cR "/path/to/notchmeow/windows/node_modules" windows/node_modules
git status --short                           # still empty: the copy is ignored
cd windows && node --version                 # 22.6 or newer
```

The `merge-base` line must print `A-0 and A-0b are in the history` (if it prints nothing, stop: the base is older than A-0b), and `git ls-files` must print the plan's path (if it prints nothing, the plan is not committed on this branch: stop).

- [ ] Check the base: A-0 and A-0b must be merged (`ls ../design/prototype/cat-core.js ../tests/fixtures/cat/collar-cases.json`, and `grep -c earFitCases ../tests/fixtures/cat/geometry-cases.json` prints `1`) and the starting point must be green.

```bash
npx tsc --noEmit && npm run check:ai && (cd .. && bash scripts/test-cat-contract.sh)
```

Expected: no type errors, `All AI UI checks passed`, and `✓ two generator runs write identical bytes`.

---


# Stage 1: a still cat at every size and in every coat

### Task 1: Rename `mochi/` to `cat/`, the check harness, helpers and tables

**Agent:** `nm-implementer-light`.

**Files:**
- Rename: `windows/src/mochi/` to `windows/src/cat/` (`engine.ts`, `greeting.ts`, `minibots.ts` move unchanged and still work).
- Modify: `windows/src/island/island.ts` (3 import lines), `windows/src/views/views.ts` (1), `windows/src/core/state.ts` (1), `windows/tsconfig.json`, `windows/package.json`.
- Create: `windows/src/cat/base.ts`, `windows/src/cat/types.ts`.
- Create: `windows/scripts/cat-tests/util.mjs`, `windows/scripts/cat-tests/base.test.mjs`.

**Interfaces:**
- Consumes: the A-0 fixtures `tests/fixtures/cat/motion-cases.json` (`prng`, `ease`, `rest`) and `sequence-cases.json` (`zoomAfterMs`, `workClock`).
- Produces `src/cat/base.ts`: `TAU`; `EZ` (`out`, `inOut`, `back`, `lin`, `in`, each `(t: number) => number`) and `type EaseName`; `lerp(a, b, t)`, `clamp(v, a, b)`, `seg(t, a, b)`, `wrapA(rad)`, `hex("#RRGGBB"): [r, g, b]` (0 to 255), `rng(seed): () => number`, `tm(v, lo, hi)`, `own(obj, key)`; `STATES` (11 names) and `type StateName`; `COL`, `TINT`, `GLOW`, `BADGE` (with `type BadgeKind`), `MOUTH` (state to six numbers), `MKEYS` and `type MouthKey`, `EMOUTH`, `mouthFx(state, seconds)`, `BUSY`; `ZOOM_AFTER_MS` (300000), `workClockStep(clock, state, nowMs)`, `zoomiesOnFinish(workedForMs, thresholdMs?)`, `type WorkClock`.
- Produces `src/cat/types.ts` (types only): `Pose`, `PoseKey`, `Targets`, `TargetKey`, `CatPreset` and its parts, `EyeShape`, `Particle`, `ParticleKind`, `Ball`, `Traits`, `Persona`.
- Produces `scripts/cat-tests/util.mjs`: `load(name)` (a fixture, parsed), `compare(got, want)` (the list of differences), `same(got, want, what)` (fails with the first differences), `near(a, b, eps?)`, `finite(value)`, `earTop(layout, pose, ear)` (the highest point an ear reaches, found by walking its whole outline, for the ear-fit checks), `TOLERANCE` (1e-9).
- Produces the npm script `check:cat`.

- [ ] **Step 1: Rename the folder and point the five imports at it**

```bash
cd windows
git mv src/mochi src/cat
```

In `windows/src/island/island.ts`, replace:

```ts title="windows/src/island/island.ts" old
import { BotEngine, hexToRGB } from "../mochi/engine";
import { Greeting } from "../mochi/greeting";
import { createMiniBot, pruneMiniBots, syncMiniBotStates, tickMiniBots } from "../mochi/minibots";
```

with:

```ts title="windows/src/island/island.ts" new
import { BotEngine, hexToRGB } from "../cat/engine";
import { Greeting } from "../cat/greeting";
import { createMiniBot, pruneMiniBots, syncMiniBotStates, tickMiniBots } from "../cat/minibots";
```

In `windows/src/views/views.ts`, replace:

```ts title="windows/src/views/views.ts" old
import { createMiniBot, pruneMiniBots } from "../mochi/minibots";
```

with:

```ts title="windows/src/views/views.ts" new
import { createMiniBot, pruneMiniBots } from "../cat/minibots";
```

In `windows/src/core/state.ts`, replace:

```ts title="windows/src/core/state.ts" old
import type { EyeShape } from "../mochi/engine";
```

with:

```ts title="windows/src/core/state.ts" new
import type { EyeShape } from "../cat/engine";
```

- [ ] **Step 2: Let TypeScript and Node read `.ts` imports, and add the script**

Node reads the TypeScript source as it is, so the cat's modules import each other with the `.ts` extension. `tsc` allows that when `allowImportingTsExtensions` is on (the config already has `noEmit`).

In `windows/tsconfig.json`, replace:

```json title="windows/tsconfig.json" old
    "isolatedModules": true,
```

with:

```json title="windows/tsconfig.json" new
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
```

In `windows/package.json`, replace:

```json title="windows/package.json" old
    "check:ai": "node --experimental-strip-types scripts/check-ai-ui.mjs",
```

with:

```json title="windows/package.json" new
    "check:ai": "node --experimental-strip-types scripts/check-ai-ui.mjs",
    "check:cat": "node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/*.test.mjs",
```

Run: `npx tsc --noEmit && npm run check:ai`
Expected: no output from `tsc`, and `All AI UI checks passed`. (The old character still draws everything: only its folder moved.)

- [ ] **Step 3: Write the failing tests**

Create `windows/scripts/cat-tests/util.mjs`:

```js title="windows/scripts/cat-tests/util.mjs"
// Shared by the cat checks: the fixture loader and the 1e-9 comparison.
// The fixtures in tests/fixtures/cat/ are generated from design/prototype/cat-core.js (see docs/CAT-CONTRACT.md).
import assert from "node:assert/strict";
import fs from "node:fs";

export const TOLERANCE = 1e-9;

/** One fixture file of tests/fixtures/cat/, parsed. */
export const load = (name) =>
  JSON.parse(fs.readFileSync(new URL(`../../../tests/fixtures/cat/${name}`, import.meta.url), "utf8"));

const isObj = (x) => x !== null && typeof x === "object" && !Array.isArray(x);

/** Deep compare with a numeric tolerance. Returns the list of differences, empty when equal. */
export function compare(got, want, at = "$", out = []) {
  if (typeof got === "number" && typeof want === "number") {
    if (!(Math.abs(got - want) <= TOLERANCE)) out.push(`${at}: ${got} vs ${want}`);
  } else if (Array.isArray(got) && Array.isArray(want)) {
    if (got.length !== want.length) out.push(`${at}: length ${got.length} vs ${want.length}`);
    for (let i = 0; i < Math.min(got.length, want.length); i++) compare(got[i], want[i], `${at}[${i}]`, out);
  } else if (isObj(got) && isObj(want)) {
    const gk = Object.keys(got).sort(), wk = Object.keys(want).sort();
    if (gk.join() !== wk.join()) out.push(`${at}: keys ${gk.join()} vs ${wk.join()}`);
    for (const k of gk) if (k in want) compare(got[k], want[k], `${at}.${k}`, out);
  } else if (got !== want) out.push(`${at}: ${JSON.stringify(got)} vs ${JSON.stringify(want)}`);
  return out;
}

/** Fails with the first differences listed. `got` goes through JSON first, as the fixtures did (a function or undefined drops out). */
export function same(got, want, what = "value") {
  const diffs = compare(JSON.parse(JSON.stringify(got)), want);
  assert.deepEqual(diffs.slice(0, 8), [], `${what}: ${diffs.length} difference(s) from the fixture`);
}

export const near = (a, b, eps = TOLERANCE) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);

/** Every number in a value is finite. */
export function finite(v, at = "$") {
  if (typeof v === "number") assert.ok(Number.isFinite(v), `${at} is ${v}`);
  else if (typeof v === "function") return;
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) finite(x, `${at}.${k}`);
}

/**
 * The highest point (smallest y) an ear reaches in the world, found by walking the whole outline the renderer draws (drawEar's
 * three quadratic curves) and not by the formula under test: ear space, then head space (turned by the ear's tilt, moved to
 * its base), then the world (the head's tilt and squash, then its position). `L` is a layout(), `s` the pose, `e` one of `L.ears`.
 */
export function earTop(L, s, e) {
  const R = L.R, { h, bw, tip, cx } = e;
  const segs = [
    [[-bw, 0.25 * R], [-bw * cx, -h * 0.4], [-tip * 0.9, -h + tip * 1.3]],
    [[-tip * 0.9, -h + tip * 1.3], [0, -h - tip * 0.35], [tip * 0.9, -h + tip * 1.3]],
    [[tip * 0.9, -h + tip * 1.3], [bw * cx, -h * 0.4], [bw, 0.25 * R]],
  ];
  let best = Infinity;
  for (const [a, b, c] of segs) for (let i = 0; i <= 400; i++) {
    const t = i / 400, m = 1 - t;
    const x = m * m * a[0] + 2 * m * t * b[0] + t * t * c[0], y = m * m * a[1] + 2 * m * t * b[1] + t * t * c[1];
    const hx = e.bx + x * Math.cos(e.rot) - y * Math.sin(e.rot), hy = e.by + x * Math.sin(e.rot) + y * Math.cos(e.rot);
    best = Math.min(best, L.head.y + Math.sin(s.tilt) * s.sx * hx + Math.cos(s.tilt) * s.sy * hy);
  }
  return best;
}
```

Create `windows/scripts/cat-tests/base.test.mjs`:

```js title="windows/scripts/cat-tests/base.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import { EZ, rng, tm, wrapA, hex, seg, clamp, lerp, STATES, COL, TINT, BADGE, GLOW, MOUTH, MKEYS, mouthFx, own, ZOOM_AFTER_MS, workClockStep, zoomiesOnFinish } from "../../src/cat/base.ts";
import { load, near, same } from "./util.mjs";

const motion = load("motion-cases.json");

test("rng is the seeded uint32 LCG: the fixture's sequences", () => {
  for (const { seed, values } of motion.prng) {
    const r = rng(seed);
    values.forEach((v) => near(r(), v));
  }
  assert.deepEqual(Array.from({ length: 3 }, rng(2 ** 32 + 7)), Array.from({ length: 3 }, rng(7)), "the seed wraps to uint32");
});

test("the easings match the fixture", () => {
  for (const { name, samples } of motion.ease) for (const { t, v } of samples) near(EZ[name](t), v);
  assert.deepEqual(Object.keys(EZ), ["out", "inOut", "back", "lin", "in"]);
});

test("small helpers", () => {
  near(lerp(2, 10, 0.25), 4);
  assert.equal(clamp(5, 0, 1), 1);
  assert.equal(seg(-1, 0, 2), 0);
  near(seg(1, 0, 2), 0.5);
  near(wrapA(Math.PI * 2.5), Math.PI / 2);
  near(wrapA(Math.PI), -Math.PI);
  near(tm(0, 0.3, 2), 0.3); near(tm(0.5, 0.3, 2), 1); near(tm(1, 0.3, 2), 2); near(tm(0.25, 0.3, 2), 0.65);
  assert.deepEqual(hex("#3B9EFF"), [59, 158, 255]);
  assert.equal(own({ a: 1 }, "a"), true);
  assert.equal(own({}, "toString"), false, "an inherited name is not an own one");
});

test("the eleven states and their tables match the rest fixture", () => {
  assert.equal(STATES.length, 11);
  assert.deepEqual(Object.keys(COL), [...STATES]);
  assert.deepEqual(Object.keys(MOUTH), [...STATES]);
  assert.deepEqual([...MKEYS], ["mouth", "smile", "tongue", "mround", "mskew", "wavy"]);
  for (const r of motion.rest) {
    assert.equal(COL[r.state], r.color, r.state);
    assert.equal(TINT[r.state], r.tint, r.state);
    assert.equal(BADGE[r.state] ?? null, r.badge, r.state);
    assert.equal(GLOW[r.state] ?? null, r.glow, r.state);
  }
});

test("mouthFx (hunting chatter, meows, panting, snoring) matches the rest fixture", () => {
  for (const r of motion.rest) near(mouthFx(r.state, r.T), r.mfx);
  assert.equal(mouthFx("idle", 1.234), 0);
  same(MKEYS.map((k, i) => [k, MOUTH.error[i]]), [["mouth", 0], ["smile", -0.8], ["tongue", 0], ["mround", 0], ["mskew", 0], ["wavy", 0]]);
});

const seq = load("sequence-cases.json");

test("the work clock and the zoomies rule are the fixture's: 5 minutes of work, pauses neither stop nor reset it", () => {
  assert.equal(ZOOM_AFTER_MS, seq.zoomAfterMs);
  assert.equal(ZOOM_AFTER_MS, 300000);
  for (const c of seq.workClock) {
    let clock = { busySince: null, workedFor: 0 };
    const after = c.steps.map(([t, state]) => { clock = workClockStep(clock, state, t); return { tMs: t, state, busySince: clock.busySince, workedFor: clock.workedFor }; });
    same(after, c.after, c.name);
    const last = c.steps[c.steps.length - 1];
    assert.equal(last[1] === "finished" ? zoomiesOnFinish(clock.workedFor) : null, c.zoomiesAtFinish, c.name);
  }
  assert.equal(zoomiesOnFinish(299999), false, "1 ms short");
  assert.equal(zoomiesOnFinish(300000), true, "exactly 5 minutes");
});

test("the work clock never goes negative, even when the clock steps back", () => {
  let c = workClockStep({ busySince: null, workedFor: 0 }, "working", 1000);
  c = workClockStep(c, "finished", 500);
  assert.equal(c.workedFor, 0);
  assert.equal(c.busySince, null);
  assert.equal(workClockStep({ busySince: null, workedFor: 0 }, "working", 0).busySince, 0, "a run that starts at clock 0 is open");
});
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `npm run check:cat`
Expected: FAIL. `base.test.mjs` cannot load: `ERR_MODULE_NOT_FOUND` for `src/cat/base.ts`.

- [ ] **Step 5: Create the helpers, the tables and the types**

Create `windows/src/cat/base.ts`:

```ts title="windows/src/cat/base.ts"
// The cat's small shared pieces: helpers, the state tables and the mouth table.
// A port of the first sections of design/prototype/cat-core.js, which is the tie-breaker:
// if this file and the fixtures in tests/fixtures/cat/ disagree, cat-core.js is right.
//
// Imports nothing at run time, so the plain-Node checks (npm run check:cat) can load it as it is.

export const TAU = Math.PI * 2;

export type EaseName = "out" | "inOut" | "back" | "lin" | "in";

/** The easings, by the names the fixtures and the tweens use. */
export const EZ: Record<EaseName, (t: number) => number> = {
  out: (t) => 1 - Math.pow(1 - t, 3),
  inOut: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  back: (t) => 1 + 2.7 * Math.pow(t - 1, 3) + 1.7 * Math.pow(t - 1, 2),
  lin: (t) => t,
  in: (t) => t * t * t,
};

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
/** 0 up to 1 as t runs from a to b. */
export const seg = (t: number, a: number, b: number) => clamp((t - a) / (b - a), 0, 1);
export const wrapA = (a: number) => ((((a + Math.PI) % TAU) + TAU) % TAU) - Math.PI;

/** "#RRGGBB" to [r, g, b], each 0 to 255. */
export const hex = (h: string): [number, number, number] => [
  parseInt(h.slice(1, 3), 16),
  parseInt(h.slice(3, 5), 16),
  parseInt(h.slice(5, 7), 16),
];

/** The seeded PRNG: a 32-bit LCG. The same seed gives the same sequence on every platform. */
export function rng(seed: number): () => number {
  let s = seed >>> 0;
  return () => (s = (Math.imul(s, 1103515245) + 12345) >>> 0) / 4294967296;
}

/** Maps a trait to a multiplier: lo at 0, 1 at 0.5, hi at 1. */
export const tm = (v: number, lo: number, hi: number) =>
  v < 0.5 ? lerp(lo, 1, v / 0.5) : lerp(1, hi, (v - 0.5) / 0.5);

export const own = (o: object, k: string) => Object.prototype.hasOwnProperty.call(o, k);

// ── State tables (colours and tints are upstream's) ───────────────────────────

export const STATES = [
  "idle", "working", "thinking", "searching", "approval", "question",
  "error", "finished", "ratelimit", "sleeping", "dizzy",
] as const;
export type StateName = (typeof STATES)[number];

export const COL: Record<StateName, string> = {
  idle: "#E6E9EE", working: "#3B9EFF", thinking: "#8B5CF6", searching: "#6366F1", approval: "#F5A524",
  question: "#22D3EE", error: "#F4505E", finished: "#34D399", ratelimit: "#FB923C", sleeping: "#94A3B8",
  dizzy: "#F472B6",
};
export const TINT: Record<StateName, number> = {
  idle: 0, working: 0.72, thinking: 0.72, searching: 0.72, approval: 0.78, question: 0.75,
  error: 0.78, finished: 0.35, ratelimit: 0.72, sleeping: 0.32, dizzy: 0.7,
};
export const GLOW: Partial<Record<StateName, string>> = {
  working: "#3B9EFF", thinking: "#A78BFA", searching: "#6366F1", approval: "#F5A524",
  error: "#F4505E", finished: "#34D399", ratelimit: "#F59E0B",
};
export type BadgeKind = "dots" | "bang" | "question" | "dot";
export const BADGE: Partial<Record<StateName, BadgeKind>> = {
  working: "dots", thinking: "dots", searching: "dots", approval: "bang",
  question: "question", error: "dot", finished: "dot", ratelimit: "dot",
};

// ── Mouth ─────────────────────────────────────────────────────────────────────

export type MouthKey = "mouth" | "smile" | "tongue" | "mround" | "mskew" | "wavy";
/** open, smile (-1 frown … 1 smile), tongue, round (wide D … 'o'), skew, wavy: the six animatable values. */
export const MKEYS: readonly MouthKey[] = ["mouth", "smile", "tongue", "mround", "mskew", "wavy"];

/** The rest mouth of each state, in MKEYS order. */
export const MOUTH: Record<StateName, readonly number[]> = {
  idle: [0, 0, 0, 0, 0, 0], working: [0, 0.05, 0.35, 0, 0, 0], thinking: [0, -0.15, 0, 0, 0.7, 0],
  searching: [0, 0, 0, 0, 0, 0], approval: [0, 0.1, 0, 0.35, 0, 0], question: [0.13, 0, 0, 1, 0, 0],
  error: [0, -0.8, 0, 0, 0, 0], finished: [0, 1, 0, 0, 0, 0], ratelimit: [0.3, 0, 0.85, 0.2, 0, 0],
  sleeping: [0, 0.1, 0, 1, 0, 0], dizzy: [0, 0, 0.45, 0, 0, 1],
};

/** The mouth pose of each emote, shared by both motion styles: [pose, duration in ms]. */
export const EMOUTH: Record<string, readonly [Partial<Record<MouthKey, number>>, number]> = {
  love: [{ smile: 0.8 }, 1800],
  surprised: [{ mouth: 0.6, mround: 1 }, 1000],
  proud: [{ smile: 0.75, mskew: 0.45 }, 1800],
  wink: [{ tongue: 0.8, smile: 0.4, mskew: 0.3 }, 1100],
  yawn: [{ tongue: 0.35, mround: 0.15 }, 1100],
  happy: [{ mouth: 0.5, smile: 1 }, 1300],
  annoyed: [{ smile: -0.7, mskew: -0.6 }, 850],
};

/** Per-frame mouth motion on top of the rest shape: hunting chatter, meows, panting, snoring. */
export function mouthFx(st: StateName, T: number): number {
  switch (st) {
    case "searching": {
      const ph = T % 2.6;
      return ph < 1.1 ? Math.sin((Math.PI * ph) / 1.1) * (0.24 + 0.07 * Math.sin(T * TAU * 9)) : 0;
    }
    case "approval": {
      const ph = (T % 1.4) / 1.4;
      return ph < 0.28 ? 0.5 * Math.sin((Math.PI * ph) / 0.28) : 0;
    }
    case "ratelimit":
      return 0.07 * Math.sin(T * TAU * 2.8);
    case "sleeping":
      return 0.07 * Math.max(0, Math.sin(T * 1.5));
    default:
      return 0;
  }
}

/** The states in which an agent is working: they keep the work clock running. */
export const BUSY: ReadonlySet<StateName> = new Set<StateName>(["working", "thinking", "searching"]);

// ── The work clock ────────────────────────────────────────────────────────────

/** An agent that finishes after this much working, thinking or searching earns zoomies (ms). */
export const ZOOM_AFTER_MS = 5 * 60 * 1000;

export interface WorkClock { busySince: number | null; workedFor: number }

/**
 * The work clock. Working, thinking and searching keep it running; approval and question pauses neither stop
 * nor reset it; every other state ends the run and stores how long it lasted in `workedFor` (never negative,
 * even if the clock steps back). Pure: pass the clock in, get the next one back. `busySince` is null while no run is open.
 */
export function workClockStep(clock: WorkClock, state: StateName, nowMs: number): WorkClock {
  const c = { busySince: clock.busySince, workedFor: clock.workedFor };
  if (BUSY.has(state)) {
    if (c.busySince === null) c.busySince = nowMs;
  } else if (state !== "approval" && state !== "question") {
    c.workedFor = c.busySince === null ? 0 : Math.max(0, nowMs - c.busySince);
    c.busySince = null;
  }
  return c;
}
export const zoomiesOnFinish = (workedForMs: number, thresholdMs = ZOOM_AFTER_MS) => workedForMs >= thresholdMs;
```

Create `windows/src/cat/types.ts`:

```ts title="windows/src/cat/types.ts"
// The cat's shared types. Nothing here exists at run time.
// Units are R, the head radius, unless a name says px or ms.

import type { MouthKey } from "./base.ts";

/** Every animatable property of the pose, as in cat-core.js `newPose()`. */
export type PoseKey =
  | "yaw" | "pitch" | "roll" | "tilt" | "open" | "sx" | "sy" | "oy" | "ox" | "tint" | "blush" | "es"
  | "badgeS" | "earL" | "earR" | "earU" | "earF" | "pupil" | "mouth" | "purr" | "lid" | "lift" | "wh"
  | "paws" | "smile" | "tongue" | "mround" | "mskew" | "wavy";
export type Pose = Record<PoseKey, number>;

/** The targets the pose eases toward each frame. */
export type TargetKey =
  | "yaw" | "pitch" | "tilt" | "sx" | "sy" | "es" | "oy" | "earL" | "earR" | "earU" | "earF" | "pupil"
  | "purr" | "lid" | MouthKey;
export type Targets = Record<TargetKey, number>;

export type Coat = "tuxedo" | "tabby" | "solid" | "point" | "calico";

export interface EarSpec { h: number; bw: number; rot: number; tip: number; tuft: number; cx?: number; fold?: number }
export interface EyeSpec { th: number; ph: number; w: number; h: number; round: number }
export interface WhiskSpec {
  rows: number; cols: number; x0: number; dx: number; y0: number; dy: number; slope: number; dot: number;
  wcols: number[]; a0: number; da: number; len: number; dl: number; droop: number; w: number; alpha: number; brow: number;
}
export interface RuffSpec { rx: number; ry: number; dy: number; col: [string, string] }
export interface FurOpts { n: number; l0: number; l1: number; w: number; dark: string; light: string; wDark?: string; wLight?: string }
/** A calico patch: x, y, a, b, rotation, colour, seed. */
export type Patch = [number, number, number, number, number, string, number];

/** One cat, fully resolved. The ids are frozen contract values. */
export interface CatPreset {
  name: string; label: string; desc?: string; voice: number; coat: Coat;
  rx: number; ry: number; n: number; fluff: number; ruff: RuffSpec | null; bib?: string;
  furOpts?: FurOpts; earSpread: number; ear: EarSpec;
  top: string; bot: string; rimLight?: number; white?: string; inner: string;
  light?: string; chinCol?: string; stripe?: string; point?: string; earCols?: [string, string];
  muzzle?: string; patches?: Patch[]; hairless?: number; wrinkles?: number;
  nose: string; noseLine: string; noseW: number; noseH: number; nosePh: number;
  iris: [string, string]; irisR?: [string, string]; lidTint?: string; liner: string; ink: string;
  mouthLine: string; whisk: string; padDot: string; whisk2: WhiskSpec; eye: EyeSpec;
  pupil0: number; blushAt: [number, number]; paw: string; bean: string;
  hair: string; hairDark: string; hairLight: string;
  kitten?: boolean; base?: string;
}

/** What a personality is as a cat stores it: the preset name and the six traits. */
export interface Traits { energy: number; curiosity: number; chatty: number; affection: number; sass: number; mischief: number }
export type Persona = Traits & { preset: string };

export type EyeShape =
  | "pill" | "wide" | "dot" | "line" | "flat" | "happy" | "closed"
  | "spiral" | "heart" | "star" | "tired" | "wink" | "cup";

export type ParticleKind = "heart" | "star" | "spark" | "sweat" | "dust" | "hair" | "z";
/** A little thing that floats up and fades: hearts, stars, sparks, sweat, dust, hair, z. Positions are in R from the cat. */
export interface Particle { k: ParticleKind; x: number; y: number; vx: number; vy: number; age: number; life: number; size: number; rot: number }

/** A hairball, or a refused file wrapped in fur, bouncing and rolling away. Positions are in R from the cat. */
export interface Ball { x: number; y: number; vx: number; vy: number; rot: number; age: number; life: number; file: string | null; seed: number; floor: number }
```

- [ ] **Step 6: Run the tests and the type check**

Run: `npm run check:cat && npx tsc --noEmit && npm run check:ai`
Expected: every test passes (`ℹ fail 0`), no type errors, `All AI UI checks passed`.

- [ ] **Step 7: Commit**

```bash
git add -A windows
git commit -m "feat(cat): rename mochi to cat, add the check harness, helpers and tables

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The 16 coats and their kittens

**Agent:** `nm-implementer-light`.

**Files:**
- Create: `windows/src/cat/presets.ts`
- Test: `windows/scripts/cat-tests/presets.test.mjs`

**Interfaces:**
- Consumes: `own` from `base.ts`; `CatPreset`, `Patch` from `types.ts`; fixture `presets.json` (`ids`, `cats`, `kittens`).
- Produces `src/cat/presets.ts`: `PRESETS: Record<string, CatPreset>` (all 16, by ID), `kittenOf(p: CatPreset): CatPreset` (a copy, never touches the parent), `CAT_IDS: readonly string[]` (frozen order, Shrimpy first), `DEFAULT_CAT` (`"shrimpy"`), `catById(id: unknown): CatPreset` (an unknown ID, or anything that is not a string, is Shrimpy).

- [ ] **Step 1: Write the failing test**

Create `windows/scripts/cat-tests/presets.test.mjs`:

```js title="windows/scripts/cat-tests/presets.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import { PRESETS, CAT_IDS, DEFAULT_CAT, catById, kittenOf } from "../../src/cat/presets.ts";
import { load, same } from "./util.mjs";

const fx = load("presets.json");

test("the cat ids are the frozen contract values, Shrimpy first and Momo second", () => {
  assert.deepEqual([...CAT_IDS], fx.ids);
  assert.deepEqual([...CAT_IDS].slice(0, 2), ["shrimpy", "momo"]);
  assert.equal(CAT_IDS.length, 16);
  assert.equal(DEFAULT_CAT, "shrimpy");
  assert.deepEqual(Object.keys(PRESETS).sort(), [...fx.ids].sort(), "no coat without an id, no id without a coat");
});

test("every coat is exactly the fixture's, voice included", () => {
  for (const id of fx.ids) same(PRESETS[id], fx.cats[id], `cat ${id}`);
  assert.equal(PRESETS.shrimpy.voice, -1);
  assert.equal(PRESETS.momo.voice, 1);
  assert.equal(PRESETS.ginger.voice, 0);
});

test("every kitten is exactly the fixture's, voice +3", () => {
  for (const id of fx.ids) {
    same(kittenOf(PRESETS[id]), fx.kittens[id], `kitten ${id}`);
    assert.equal(kittenOf(PRESETS[id]).voice, 3);
    assert.equal(kittenOf(PRESETS[id]).base, id);
  }
});

test("kittenOf copies: the parent is not changed", () => {
  const before = JSON.stringify(PRESETS.shrimpy);
  const k = kittenOf(PRESETS.shrimpy);
  k.ear.h = 99;
  assert.equal(JSON.stringify(PRESETS.shrimpy), before);
});

test("an unknown stored id, or anything that is not a string, is Shrimpy; it never throws", () => {
  for (const bad of ["", "nope", "toString", "__proto__", "SHRIMPY", null, undefined, 3, {}, []]) {
    assert.equal(catById(bad), PRESETS.shrimpy, String(bad));
  }
  assert.equal(catById("momo"), PRESETS.momo);
  assert.equal(catById("noodle").name, "noodle");
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npm run check:cat`
Expected: FAIL. `presets.test.mjs` cannot load `src/cat/presets.ts` (`ERR_MODULE_NOT_FOUND`); `base.test.mjs` still passes.

- [ ] **Step 3: Create the presets**

The data is `cat-core.js`'s, as written there (single quotes and short numbers included); only the types are added. Create `windows/src/cat/presets.ts`:

```ts title="windows/src/cat/presets.ts"
// The cats: Shrimpy, Momo and the fourteen extra coats, and each one's kitten.
// A port of the presets section of design/prototype/cat-core.js (the tie-breaker). Units are R, the head radius.
//
// The ids are frozen contract values (they are stored in settings), in this order:
// shrimpy, momo, ginger, midnight, latte, patches, blue, snow, oreo, mocha, silver, cloud,
// leo, button, puff, noodle. `voice` is a pitch offset in semitones for sub-project C:
// Shrimpy -1, Momo +1, the extra coats 0, every kitten +3.

import { own } from "./base.ts";
import type { CatPreset, Patch } from "./types.ts";

/** What a coat may set on top of the shorthair template: any field, and the nested ones in part. */
type CoatSpec = Partial<Omit<CatPreset, "ear" | "eye" | "whisk2">> & {
  name: string;
  ear?: Partial<CatPreset["ear"]>;
  eye?: Partial<CatPreset["eye"]>;
  whisk2?: Partial<CatPreset["whisk2"]>;
};

export const PRESETS: Record<string, CatPreset> = {
 momo:{name:'momo',label:'Momo',voice:1,coat:'tuxedo',rx:1.12,ry:.9,n:2.2,fluff:0,ruff:null,
  furOpts:{n:700,l0:.025,l1:.03,w:.008,dark:'rgba(24,24,27,.45)',light:'rgba(112,114,122,.42)',wDark:'rgba(196,190,184,.55)',wLight:'rgba(255,255,255,.5)'},
  earSpread:.8,ear:{h:.8,bw:.56,rot:.5,tip:.09,tuft:0,cx:.62},
  top:'#3D3D41',bot:'#3D3D41',rimLight:1,white:'#F6F4F1',inner:'#B98288',nose:'#E89AA6',noseLine:'#B86F7C',noseW:.25,noseH:.15,nosePh:-.48,
  iris:['#7E8A45','#D1B85F'],lidTint:'#D9BE62',liner:'#16171A',ink:'#E4D592',mouthLine:'#9A8C88',whisk:'#F6F4F1',padDot:'rgba(150,142,138,.6)',
  whisk2:{rows:3,cols:2,x0:.17,dx:.065,y0:-.01,dy:.06,slope:.02,dot:.014,wcols:[0,1],a0:-.1,da:.2,len:1.32,dl:.1,droop:.1,w:.021,alpha:.95,brow:2},
  eye:{th:.43,ph:-.02,w:.19,h:.17,round:1},pupil0:.235,blushAt:[.5,.32],paw:'#F6F4F1',bean:'#E89AA6',hair:'#56575E',hairDark:'#2E2F33',hairLight:'#9A9BA2'},
 shrimpy:{name:'shrimpy',label:'Shrimpy',voice:-1,coat:'tabby',rx:1.16,ry:.92,n:2.2,fluff:1,
  ruff:{rx:1.3,ry:.97,dy:.2,col:['#B49C7A','#7E6750']},bib:'#F3EEE6',
  furOpts:{n:420,l0:.04,l1:.05,w:.01,dark:'rgba(60,46,36,.28)',light:'rgba(214,190,150,.32)'},
  earSpread:.8,ear:{h:.8,bw:.4,rot:.44,tip:.1,tuft:1},
  top:'#A08A70',bot:'#6E5B49',light:'#D9B68A',chinCol:'#E6D0AD',stripe:'#2E241D',inner:'#DCC39A',nose:'#C07A62',noseLine:'#5E3526',noseW:.19,noseH:.12,nosePh:-.36,
  iris:['#C9D18A','#6F8445'],liner:'#231A14',ink:'#231A14',mouthLine:'#5E3526',whisk:'#F7F3EC',padDot:'#2E241D',
  whisk2:{rows:3,cols:3,x0:.14,dx:.065,y0:-.01,dy:.065,slope:.022,dot:.017,wcols:[1,2],a0:-.14,da:.2,len:1.45,dl:.12,droop:.12,w:.022,alpha:.95,brow:3},
  eye:{th:.42,ph:-.02,w:.21,h:.16,round:0},pupil0:.08,blushAt:[.6,.22],paw:'#B89C78',bean:'#6B3B2C',hair:'#9A8064',hairDark:'#5A4634',hairLight:'#D2B791'}};

/** The shorthair template for the extra coats; each cat only overrides what differs. */
function makeCat(o: CoatSpec): CatPreset {
  const base = {
    voice: 0, coat: "solid" as const, rx: 1.12, ry: 0.9, n: 2.2, fluff: 0, ruff: null, earSpread: 0.8,
    ear: { h: 0.8, bw: 0.5, rot: 0.46, tip: 0.09, tuft: 0, cx: 0.7 },
    noseW: 0.2, noseH: 0.13, nosePh: -0.42,
    whisk2: { rows: 3, cols: 2, x0: 0.16, dx: 0.065, y0: -0.01, dy: 0.06, slope: 0.02, dot: 0.014, wcols: [0, 1], a0: -0.1, da: 0.2, len: 1.32, dl: 0.1, droop: 0.1, w: 0.021, alpha: 0.95, brow: 2 },
    eye: { th: 0.43, ph: -0.02, w: 0.19, h: 0.17, round: 1 },
    pupil0: 0.2, blushAt: [0.55, 0.25] as [number, number],
  };
  const r = { ...base, ...o, ear: { ...base.ear, ...(o.ear || {}) }, eye: { ...base.eye, ...(o.eye || {}) }, whisk2: { ...base.whisk2, ...(o.whisk2 || {}) } };
  return r as CatPreset;
}

Object.assign(PRESETS,{
 ginger:makeCat({name:'ginger',label:'Ginger',desc:'orange tabby',coat:'tabby',top:'#E39B52',bot:'#C46F2E',light:'#F7DDB8',chinCol:'#FCEFDD',stripe:'#A9541C',inner:'#F2B8A8',
  nose:'#E88E80',noseLine:'#A85A4E',iris:['#E9D27A','#C99A2E'],liner:'#3A2416',ink:'#3A2416',mouthLine:'#A0624A',whisk:'#FFF6EA',padDot:'#B7682F',
  eye:{w:.2,h:.16,round:0},pupil0:.1,blushAt:[.58,.22],paw:'#F3C894',bean:'#E88E80',hair:'#D98B45',hairDark:'#9C5524',hairLight:'#F6CF9E'}),
 midnight:makeCat({name:'midnight',label:'Midnight',desc:'black shorthair',top:'#2C2C31',bot:'#1F1F23',rimLight:1,inner:'#6E5A5E',nose:'#56474D',noseLine:'#2A2024',
  iris:['#F7D45C','#D9921C'],liner:'#0E0E10',ink:'#F2D06A',mouthLine:'#77696E',whisk:'#D8D8DD',padDot:'rgba(140,140,150,.5)',eye:{w:.2,h:.18},
  paw:'#2E2E33',bean:'#56474D',hair:'#38383E',hairDark:'#1A1A1D',hairLight:'#6A6A72'}),
 latte:makeCat({name:'latte',label:'Latte',desc:'Siamese seal point',coat:'point',rx:1.04,ry:.92,n:2,top:'#F1E6D4',bot:'#DCCBB2',point:'#4A3528',earCols:['#4A3528','#4A3528'],
  ear:{h:.95,bw:.55,rot:.5,tip:.08},inner:'#7A5A4E',nose:'#3E2C24',noseLine:'#2A1C16',iris:['#B9E3FA','#3F86CF'],liner:'#2A1C16',ink:'#CFE6F5',mouthLine:'#8A7266',
  whisk:'#F5EFE6',padDot:'rgba(30,20,15,.5)',eye:{w:.21,h:.15,round:0},pupil0:.1,paw:'#4A3528',bean:'#7A5A50',hair:'#D8C6AC',hairDark:'#8A7058',hairLight:'#F4EADA'}),
 patches:makeCat({name:'patches',label:'Patches',desc:'calico',coat:'calico',top:'#F7F3EE',bot:'#E6DFD6',earCols:['#E3994E','#2C2B2F'],
  patches:[[-.48,-.36,.5,.4,.3,'#E3994E',1],[.52,-.56,.55,.36,-.4,'#2C2B2F',2],[.66,.3,.22,.15,.2,'#E3994E',3],[-.78,.36,.16,.12,-.3,'#2C2B2F',4]],
  inner:'#F2B6B8',nose:'#F0A0AE',noseLine:'#C07884',iris:['#C9DA7A','#6F9A3A'],liner:'#2A2420',ink:'#2A2420',mouthLine:'#B09A94',whisk:'#CFC8C0',padDot:'rgba(170,150,140,.55)',
  paw:'#F7F3EE',bean:'#F0A0AE',hair:'#D9B48C',hairDark:'#8A6A4A',hairLight:'#F4E6D4'}),
 blue:makeCat({name:'blue',label:'Blue',desc:'British shorthair',rx:1.22,ry:.92,n:2.5,top:'#9AA4B2',bot:'#7A8494',muzzle:'#A9B2BF',ear:{h:.62,bw:.5,rot:.55,tip:.12,cx:.8},
  inner:'#B8A0A8',nose:'#6E6C7A',noseLine:'#4C4A56',noseW:.17,nosePh:-.4,iris:['#F6B44A','#D2741E'],liner:'#2E3038',ink:'#2E3038',mouthLine:'#5A5C68',whisk:'#EEF0F4',
  padDot:'rgba(70,76,90,.45)',eye:{w:.21,h:.19},pupil0:.22,paw:'#9AA4B2',bean:'#6E6C7A',hair:'#8E98A6',hairDark:'#5E6878',hairLight:'#C2CAD4'}),
 snow:makeCat({name:'snow',label:'Snow',desc:'white longhair, odd-eyed',fluff:1,ruff:{rx:1.24,ry:.92,dy:.16,col:['#F2EFEA','#D9D3CA']},bib:'#FFFFFF',top:'#F5F3EF',bot:'#E2DED7',
  ear:{h:.82,bw:.48,tuft:1},inner:'#F4B8BE',nose:'#F2A6B0',noseLine:'#C9808C',iris:['#BCE4FA','#4A90D6'],irisR:['#F4DC7A','#D49A2A'],liner:'#3A3433',ink:'#3A3433',
  mouthLine:'#C0B4B0',whisk:'#D8D2CC',padDot:'rgba(180,165,160,.55)',paw:'#F5F3EF',bean:'#F2A6B0',hair:'#EDE8E0',hairDark:'#B8B0A6',hairLight:'#FFFFFF'}),
 oreo:makeCat({name:'oreo',label:'Oreo',desc:'black-and-white tuxedo',coat:'tuxedo',top:'#1C1C1F',bot:'#131315',rimLight:1,white:'#F6F4F1',
  furOpts:{n:700,l0:.025,l1:.03,w:.008,dark:'rgba(0,0,0,.5)',light:'rgba(96,98,108,.42)',wDark:'rgba(196,190,184,.55)',wLight:'rgba(255,255,255,.5)'},
  ear:{h:.86,bw:.54,rot:.46,tip:.08,cx:.66},inner:'#8A646C',nose:'#F2A4B2',noseLine:'#C27886',noseW:.22,noseH:.14,nosePh:-.46,
  iris:['#7FA82A','#DDEB5A'],liner:'#0B0B0D',ink:'#D8EE5E',mouthLine:'#A39A98',whisk:'#FFFFFF',padDot:'rgba(150,142,138,.6)',
  whisk2:{x0:.17,len:1.4},eye:{w:.2,h:.18},pupil0:.22,paw:'#F6F4F1',bean:'#F2A4B2',hair:'#2A2A2E',hairDark:'#101012',hairLight:'#F2F0EC'}),
 mocha:makeCat({name:'mocha',label:'Mocha',desc:'tortoiseshell',coat:'calico',top:'#30241F',bot:'#1F1713',rimLight:1,earCols:['#C9772F','#30241F'],
  patches:[[-.52,-.5,.17,.11,.6,'#C9772F',1],[-.4,-.62,.07,.05,.2,'#E2A866',2],[.06,-.62,.06,.2,.1,'#C9772F',3],[.56,-.3,.15,.09,-.5,'#C9772F',4],[.84,.12,.11,.08,.4,'#E2A866',5],
   [-.82,.16,.14,.1,-.5,'#C9772F',6],[-.32,.6,.13,.07,.25,'#E2A866',7],[.4,.58,.11,.07,-.3,'#C9772F',8],[.36,-.74,.09,.05,.3,'#E2A866',9],[-.66,.42,.07,.05,0,'#E2A866',10]],
  inner:'#7A5A54',nose:'#6E4A42',noseLine:'#3A2420',iris:['#F6C44C','#C2761A'],liner:'#120C0A',ink:'#F2C45C',mouthLine:'#8A6E64',whisk:'#EADFD0',padDot:'rgba(150,120,100,.5)',
  eye:{w:.2,h:.17},paw:'#6A4630',bean:'#2A1C18',hair:'#6A4A34',hairDark:'#2A1F1A',hairLight:'#D89A58'}),
 silver:makeCat({name:'silver',label:'Silver',desc:'silver tabby',coat:'tabby',top:'#D6DADF',bot:'#A8AEB6',light:'#EEF0F2',chinCol:'#FFFFFF',stripe:'#1D1F23',inner:'#E6BDB8',
  nose:'#C2655C',noseLine:'#7C3832',iris:['#CBE27A','#4C983C'],liner:'#16171A',ink:'#1D1F23',mouthLine:'#6E6A6C',whisk:'#FFFFFF',padDot:'#2A2C30',
  eye:{w:.2,h:.16,round:0},pupil0:.1,blushAt:[.58,.22],paw:'#D6DADF',bean:'#C2655C',hair:'#BCC1C8',hairDark:'#3A3C42',hairLight:'#F2F4F6'}),
 cloud:makeCat({name:'cloud',label:'Cloud',desc:'Ragdoll',coat:'point',fluff:1,ruff:{rx:1.3,ry:.98,dy:.2,col:['#F7F2E9','#DED4C4']},bib:'#FFFFFF',rx:1.14,ry:.92,n:2.3,
  top:'#F4EFE6',bot:'#DCD3C6',point:'#7D8796',earCols:['#7D8796','#7D8796'],muzzle:'#FBF9F6',ear:{h:.84,bw:.5,tuft:1},inner:'#C4A8AE',nose:'#D49AA4',noseLine:'#A0707A',
  iris:['#6FA8F2','#2C64D6'],liner:'#232A36',ink:'#8FC0F8',mouthLine:'#A89CA0',whisk:'#FFFFFF',padDot:'rgba(110,116,130,.45)',eye:{w:.22,h:.2},pupil0:.22,
  paw:'#FFFFFF',bean:'#D49AA4',hair:'#E8E2D8',hairDark:'#8A92A0',hairLight:'#FFFFFF'}),
 leo:makeCat({name:'leo',label:'Leo',desc:'Bengal',coat:'calico',top:'#D9A050',bot:'#B97A30',muzzle:'#F4E2C0',ear:{h:.74,bw:.5,rot:.5,tip:.1,cx:.75},
  patches:[[-.1,-.6,.024,.17,.14,'#3E2412',11],[.1,-.6,.024,.17,-.14,'#3E2412',12],[0,-.7,.022,.12,0,'#3E2412',13],[-.84,.1,.15,.022,-.3,'#3E2412',14],[.84,.1,.15,.022,.3,'#3E2412',15],
   ...[[-.6,-.42,.4,1],[.62,-.4,-.3,2],[-.34,-.76,.2,3],[.36,-.76,-.2,4],[-.84,.36,.3,5],[.86,.36,-.3,6],[-.55,.6,.2,7],[.57,.6,-.2,8]].flatMap(([x,y,r,sd]): Patch[]=>[[x,y,.12,.095,r,'#4A2A14',sd],[x,y,.06,.045,r,'#9C5E24',sd]])],
  inner:'#E2B49A',nose:'#C66E58',noseLine:'#7A3A28',iris:['#DADC62','#6C9A32'],liner:'#24160C',ink:'#24160C',mouthLine:'#7A5034',whisk:'#FFF6E6',padDot:'#3A2412',
  eye:{w:.2,h:.15,round:0},pupil0:.1,blushAt:[.58,.24],paw:'#E2B470',bean:'#4A2C18',hair:'#D09048',hairDark:'#4A2C16',hairLight:'#F2D29A'}),
 button:makeCat({name:'button',label:'Button',desc:'Scottish Fold',rx:1.2,ry:.94,n:2.5,top:'#BCA9B3',bot:'#988592',ear:{h:.58,bw:.46,rot:.62,tip:.2,cx:.9,fold:1},
  inner:'#C9A4AC',nose:'#B88A96',noseLine:'#7E5A66',noseW:.17,iris:['#F8A642','#C2561A'],liner:'#2E2630',ink:'#2E2630',mouthLine:'#6E6068',whisk:'#F4EEF0',
  padDot:'rgba(90,70,80,.4)',eye:{w:.22,h:.21},pupil0:.24,paw:'#BCA9B3',bean:'#B88A96',hair:'#ADA0A6',hairDark:'#7A6C74',hairLight:'#D8CED2'}),
 puff:makeCat({name:'puff',label:'Puff',desc:'Persian',fluff:1,ruff:{rx:1.46,ry:1.08,dy:.2,col:['#F3E4C8','#D8C09A']},bib:'#FFFFFF',rx:1.24,ry:.94,n:2.6,
  top:'#EED8B4',bot:'#D4B488',earSpread:.86,ear:{h:.5,bw:.42,rot:.62,tip:.12,cx:.8,tuft:1},nosePh:-.3,noseW:.15,noseH:.1,
  inner:'#F0B8B0',nose:'#E89A94',noseLine:'#B06A64',iris:['#F8B04A','#C8601A'],liner:'#3A2A20',ink:'#3A2A20',mouthLine:'#A88A78',whisk:'#FFF8EE',padDot:'rgba(170,140,110,.5)',
  whisk2:{len:1.2},eye:{th:.45,w:.22,h:.21},pupil0:.24,paw:'#F3E4C8',bean:'#E89A94',hair:'#EAD6B4',hairDark:'#B89A70',hairLight:'#FFF6E6'}),
 noodle:makeCat({name:'noodle',label:'Noodle',desc:'Sphynx',hairless:1,wrinkles:1,rx:1.04,ry:.94,n:2,top:'#E8C1AE',bot:'#CF9F8C',earSpread:.86,ear:{h:1.1,bw:.62,rot:.58,tip:.1,cx:.75},
  inner:'#EBA898',nose:'#D88A7C',noseLine:'#A45E50',iris:['#F6F07A','#C9C42E'],liner:'#3A2620',ink:'#3A2620',mouthLine:'#A87464',whisk:'#F4E2D8',padDot:'rgba(170,110,95,.4)',
  whisk2:{wcols:[1],len:.85,alpha:.5,brow:1},eye:{w:.21,h:.15,round:0},pupil0:.1,paw:'#E8C1AE',bean:'#D88A7C',hair:'#E0B6A2',hairDark:'#A87A66',hairLight:'#F6DED2'})});
const MORE = ['ginger','midnight','latte','patches','blue','snow','oreo','mocha','silver','cloud','leo','button','puff','noodle'];

/** Kittens keep the parent's coat; rounder head, bigger eyes and ears, shorter muzzle. */
export function kittenOf(p: CatPreset): CatPreset {
  const k: CatPreset = JSON.parse(JSON.stringify(p));
  k.kitten = true; k.base = p.name; k.label = p.label + ' kitten'; k.voice = 3;
  k.rx = p.rx * .97; k.ry = p.ry * 1.02; k.n = 2.05; k.ear.h *= 1.12; k.ear.bw *= 1.06; k.ear.tuft = 0;
  k.eye.w *= 1.2; k.eye.h *= 1.32; k.eye.round = 1; k.eye.th += .02; k.pupil0 = Math.max(p.pupil0, .18);
  k.nosePh = p.nosePh + .08; k.noseW *= .85; k.noseH *= .85; k.whisk2.len *= .7; k.whisk2.brow = 1;
  if (k.ruff) { k.ruff.rx *= .94; k.ruff.ry *= .92 }
  return k;
}

/** The cat ids, frozen and in order: Shrimpy first, Momo second, then the extra coats. */
export const CAT_IDS: readonly string[] = ['shrimpy', 'momo', ...MORE];
export const DEFAULT_CAT = 'shrimpy';

/** A stored cat id to its preset. An unknown id (or anything that is not a string) falls back to Shrimpy. */
export const catById = (id: unknown): CatPreset => (typeof id === 'string' && own(PRESETS, id) ? PRESETS[id] : PRESETS[DEFAULT_CAT]);
```

- [ ] **Step 4: Run the tests and the type check**

Run: `npm run check:cat && npx tsc --noEmit`
Expected: all pass (the presets test checks the 16 coats and the 16 kittens against `presets.json` within 1e-9), no type errors.

- [ ] **Step 5: Commit**

```bash
git add windows/src/cat/presets.ts windows/scripts/cat-tests/presets.test.mjs
git commit -m "feat(cat): the 16 coats and their kittens, tested against presets.json

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Geometry, the face warp and the ear fit

**Agent:** `nm-implementer-light` (hand it to `nm-implementer-deep` if a fixture check fails and the difference is not a typo).

**The ear fit and the flat-fill rule are the contract's (A-0b, merged `6adf584`).** `earFit` is ported from `cat-core.js` as it is: the exact solve of the ear's top edge, not of its apex (the Mac draft solved the apex only, which leaves a tip up to 0.1 px inside the margin in a few tilted poses). It is tested twice: against the fixture's 92 `earFitCases` within 1e-9, and against a brute-force walk of the ear's whole outline (`earTop` in `util.mjs`), which also pins that the fit is tight. A pose that is not a number gives 1. The same module holds the detail rule and the flat-fill constants, `detailLevel`, `FLAT_FILL`, `mixHex` and `flatFillColors`, tested against `detailLevels`, `flatFill` and `flatColors`.

**Files:**
- Create: `windows/src/cat/geometry.ts`
- Test: `windows/scripts/cat-tests/geometry.test.mjs`

**Interfaces:**
- Consumes: `TAU`, `clamp`, `hex`, `lerp`, `wrapA` from `base.ts`; `CatPreset`, `Pose` from `types.ts`; `PRESETS`, `CAT_IDS`, `kittenOf` from `presets.ts` (the tests); fixtures `geometry-cases.json` (with its `earFit`, `earFitCases`, `flatFill`, `detailLevels` and `flatColors`) and `warp-cases.json`.
- Produces `src/cat/geometry.ts`: `newPose(): Pose`; `FACE`; `DETAIL_FULL_MIN` (28), `detailOf(D)`, `COMPACT_EAR_SCALE` (0.8), `earScale(D)`, `outlineSteps(R)`, `badgeSide(compactNotch)`; `CURSOR`, `cursorLook(dx, dy): {x, y}`, `pupilOffset(yaw, pitch, w, h)`; `faceAngles(pose): {yf, pf, pt, fa}`; `supPoints(rx, ry, n, dy, spike, count, steps?, bend?)`; `mkWarp(preset, yaw, pt, R): (x, y) => [x, y]`; `flatten(cmds)`, `MOMO_WHITE`; `earGeom(...)`; `layout(preset, pose, cx, cy, D, options?)` returning `{R, D, full, rx, ry, base, at, head, yf, pf, pt, fa, W, steps, bend, ruff, eyes, nose, mouth, ears, badge}` (`mouth` is `null` while the nose is turned out of sight) and `type Layout`, `type EarLayout`, `type LayoutOptions` (`T`, `detail`, `badgeSide` as a number, `earScale`); `EAR_FIT` (`{margin: 0.5, minimum: 0.35}`) and `earFit(L, s, ceiling, margin = EAR_FIT.margin, minimum = EAR_FIT.minimum): number` (the factor, 0.35 to 1, that fits the ears under a ceiling; a pose that is not a number gives 1); `detailLevel(D, override?): DetailLevel` (`{detail, full, flatFill}`, and `flatFill` is `!full`), `FLAT_FILL`, `mixHex(a, b, t)` and `flatFillColors(preset): FlatColors` (the flat head, ear, ruff and point colours, 0 to 255, not rounded), with `type DetailLevel` and `type FlatColors` (all of these A-0b, merged `6adf584`); `PASSES` (the draw order as named layers; the collar's slot is `collarPass`, not part of it). Later stages add `FLIGHT_MS` and `flightAt` at the marker `// @@S4-FLIGHT`.

- [ ] **Step 1: Write the failing test**

Create `windows/scripts/cat-tests/geometry.test.mjs`:

```js title="windows/scripts/cat-tests/geometry.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import {
  DETAIL_FULL_MIN, COMPACT_EAR_SCALE, CURSOR, EAR_FIT, FACE, FLAT_FILL, MOMO_WHITE, PASSES, badgeSide, cursorLook, detailLevel, detailOf,
  earFit, earScale, faceAngles, flatFillColors, layout, mkWarp, newPose, outlineSteps, pupilOffset, supPoints,
} from "../../src/cat/geometry.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { earTop, finite, load, near, same } from "./util.mjs";

const geo = load("geometry-cases.json");
const warp = load("warp-cases.json");
const pose = (o = {}) => ({ ...newPose(), ...o });
const presetOf = (cat, kitten) => (kitten ? kittenOf(PRESETS[cat]) : PRESETS[cat]);
const noW = (L) => { const { W, ...rest } = L; return rest; };

test("the detail switch is at head width 28, and the compact ears ease back to full size at Ø28", () => {
  assert.equal(DETAIL_FULL_MIN, geo.detail.fullMinD);
  for (const { D, detail } of geo.detail.cases) assert.equal(detailOf(D), detail, `Ø${D}`);
  assert.equal(COMPACT_EAR_SCALE, geo.earScale.compactMin);
  for (const { D, scale } of geo.earScale.cases) near(earScale(D), scale);
  assert.equal(outlineSteps(19.9), 72);
  assert.equal(outlineSteps(20), 200);
  assert.equal(badgeSide(true), -1);
  assert.equal(badgeSide(false), 1);
});

test("detailLevel is the fixture's, and flatFill is exactly !layout().full (A-0b, merged `6adf584`)", () => {
  for (const { D, override, level } of geo.detailLevels) {
    const what = `Ø${D} ${override ?? "by its width"}`;
    same(detailLevel(D, override), level, what);
    assert.equal(!layout(PRESETS.momo, pose(), 0, 0, D, { detail: override ?? undefined }).full, level.flatFill, `${what}: flatFill is !layout().full`);
  }
  assert.ok(geo.detailLevels.some((c) => c.override === "compact" && c.D >= DETAIL_FULL_MIN) && geo.detailLevels.some((c) => c.override === "full" && c.D < DETAIL_FULL_MIN), "an override beats the width, both ways");
});

test("the flat fills: FLAT_FILL and every coat's flat colours are the fixture's, and the point mask is 0.86 R by 0.54 R (A-0b, merged `6adf584`)", () => {
  same(FLAT_FILL, geo.flatFill, "FLAT_FILL");
  assert.deepEqual(FLAT_FILL.point, { rx: 0.86, ry: 0.54, alpha: 0.85 }, "tuned to the gradient it replaces, not the Mac draft's 0.5 by 0.34");
  assert.deepEqual(Object.keys(geo.flatColors), [...CAT_IDS]);
  for (const id of CAT_IDS) same(flatFillColors(PRESETS[id]), geo.flatColors[id], `the flat colours of ${id}`);
  assert.deepEqual(flatFillColors(PRESETS.latte).point, geo.flatColors.latte.point, "a point cat has its point colour");
  assert.equal(flatFillColors(PRESETS.shrimpy).point, null, "and any other coat has none");
  assert.equal(flatFillColors(PRESETS.momo).ruff, null, "a cat without a ruff has no ruff colour");
});

test("head and ruff outlines, Shrimpy's fluffy edge included, are the fixture's", () => {
  for (const o of geo.outline) {
    const pts = supPoints(o.rx, o.ry, o.n, o.dy, o.spike, o.count, o.steps, o.bend);
    same(o.indices.map((i) => pts[i]), o.points, o.name);
  }
  assert.deepEqual(supPoints(1.16, 0.92, 2.2, 0, 0.035, 14, 200), supPoints(1.16, 0.92, 2.2, 0, 0.035, 14, 200), "the fluff is fixed, not random");
});

test("layout (head, eyes, nose, mouth, ears, badge) is the fixture's at every size, coat and pose", () => {
  for (const a of geo.anchors) {
    const L = layout(presetOf(a.cat, a.kitten), pose(a.pose), a.cx, a.cy, a.D, { T: a.T, earScale: a.earScale, badgeSide: a.badgeSide });
    same(noW(L), a.layout, `${a.cat}${a.kitten ? " kitten" : ""} Ø${a.D}`);
  }
  assert.deepEqual(PASSES, geo.passes);
});

test("the face turn: angles, pupil travel, cursor curve, warp, eyes and head lean are the fixture's", () => {
  assert.deepEqual(FACE, warp.face);
  assert.deepEqual(CURSOR, warp.cursor.px);
  for (const c of warp.cursor.cases) same(cursorLook(c.dx, c.dy), { x: c.x, y: c.y }, `cursor ${c.dx},${c.dy}`);
  for (const c of warp.angles) same(faceAngles(pose(c)), { yf: c.yf, pf: c.pf, pt: c.pt, fa: c.fa }, `angles ${c.yaw},${c.pitch},${c.lift},${c.roll}`);
  for (const c of warp.pupil) same(pupilOffset(c.yaw, c.pitch, c.w, c.h), c.offset, `pupil ${c.yaw},${c.pitch}`);
  for (const c of warp.warp) {
    const W = mkWarp(PRESETS[c.cat], c.yf, c.pt, 1);
    same(c.probes.map(([x, y]) => W(x, y)), c.out, `warp ${c.cat} ${c.yaw},${c.pitch}`);
  }
  for (const c of warp.eyes) same(layout(PRESETS[c.cat], pose({ yaw: c.yaw }), 0, 0, 2 * PRESETS[c.cat].rx).eyes, c.eyes, `eyes ${c.cat} yaw ${c.yaw}`);
  for (const c of warp.head) {
    const L = layout(PRESETS[c.cat], pose({ yaw: c.yaw, pitch: c.pitch }), 0, 0, c.D);
    same({ head: L.head, bend: L.bend, ruff: L.ruff, nose: L.nose, mouth: L.mouth }, { head: c.head, bend: c.bend, ruff: c.ruff, nose: c.nose, mouth: c.mouth }, `head ${c.cat} ${c.yaw},${c.pitch}`);
  }
});

test("the rules the spec states in numbers", () => {
  assert.deepEqual([FACE.yaw, FACE.pitch, FACE.pitchDown, FACE.muzzle, FACE.nose, FACE.bend, FACE.lean], [0.82, 0.6, 0.32, 0.12, 0.05, 0.1, 0.08]);
  const L = layout(PRESETS.momo, pose({ badgeS: 1 }), 100, 50, 66);
  near(L.badge.x - L.head.x, 1.4 * L.R);
  near(L.head.y - L.badge.y, 0.92 * L.R);
  const left = layout(PRESETS.momo, pose({ badgeS: 1 }), 100, 50, 20, { badgeSide: badgeSide(true) });
  assert.ok(left.badge.x < left.head.x, "in the compact notch the badge is on the left");
  for (const yaw of [0.62, 1.2, 1.3]) assert.ok(layout(PRESETS.momo, pose({ yaw }), 0, 0, 66).eyes.every((e) => e.fx >= 0.55), `yaw ${yaw}: the near eye keeps 55 % of its width`);
  assert.equal(MOMO_WHITE.length > 50, true);
});

test("a head pushed past what it can show never gives NaN: the face fades, the nose and mouth go", () => {
  for (const cat of ["shrimpy", "momo", "button"]) for (const D of [0, 12, 66]) for (const p of [
    { yaw: 3 }, { yaw: -3 }, { pitch: 2 }, { pitch: -2 }, { roll: Math.PI }, { roll: 20 }, { lift: 6 }, { yaw: 1.6, pitch: 1, roll: 1 },
  ]) {
    const L = layout(PRESETS[cat], pose({ ...p, badgeS: 1 }), 10, 10, D);
    finite(noW(L), `${cat} Ø${D} ${JSON.stringify(p)}`);
    if (!L.nose.visible) assert.equal(L.mouth, null, "no nose, no mouth");
  }
  const over = layout(PRESETS.momo, pose({ roll: Math.PI }), 0, 0, 66);
  assert.equal(over.fa, 0, "rolled over the top: the face is gone");
  assert.equal(over.nose.visible, false);
  assert.equal(over.mouth, null);
  const away = layout(PRESETS.momo, pose({ yaw: 3 }), 0, 0, 66);
  assert.equal(away.eyes.every((e) => !e.visible), true);
});

// The ear fit is the contract's (A-0b, merged `6adf584`): the exact solve of the ear's top edge. It is checked here against a walk of the ear's whole
// outline (earTop), with the fixture's margin and minimum (not the module's, so the check cannot move with the code), and below against earFitCases.
const { margin: MARGIN, minimum: MIN } = geo.earFit;

test("ear fit: in the compact strip no ear tip leaves the top, a shrunk ear sits exactly on the margin, a calm cat keeps its ears, and it never gives a bad number", () => {
  let shrunk = 0;
  const tops = (L, s) => Math.min(...L.ears.map((e) => earTop(L, s, e)));
  // The compact island: the cat sits in the middle of a 32 px strip at Ø20 (a 24 px strip at Ø18 is a screen without a notch).
  for (const [strip, D] of [[32, 20], [24, 18]]) {
    for (const [earU, earF, oy, tilt] of [[1, 0, 0, 0], [1.4, 0, 0, 0], [1.4, 0, -0.26, 0], [1.22, 0, -0.26, 0], [1.4, 0, -0.3, 0.24], [1.4, 0, -0.3, -0.24], [1.1, 0.45, -0.1, 0.1]]) {
      const s = pose({ earU, earF, oy, tilt }), ek = earScale(D);
      for (const id of ["momo", "shrimpy", "noodle", "puff", "button"]) {
        const L = layout(PRESETS[id], s, 40, strip / 2, D, { earScale: ek }), f = earFit(L, s, 0);
        const where = `${id} strip ${strip} Ø${D} earU ${earU} earF ${earF} oy ${oy} tilt ${tilt}`;
        assert.ok(f >= MIN && f <= 1, `${where}: the factor is ${MIN} to 1, not ${f}`);
        const after = layout(PRESETS[id], s, 40, strip / 2, D, { earScale: ek * f });
        if (f === 1) assert.ok(tops(L, s) >= MARGIN - 1e-3, `${where}: an ear that was left alone pokes out at ${tops(L, s)}`);
        else {
          shrunk++;
          if (f > MIN + 1e-9) assert.ok(Math.abs(tops(after, s) - MARGIN) <= 1e-3, `${where}: the top of the ears is at ${tops(after, s)}, not on the margin ${MARGIN}`);
          else assert.ok(tops(after, s) > tops(L, s), `${where}: held at the minimum, the tips come down`);
        }
      }
    }
  }
  assert.ok(shrunk > 10, `the poses do need the fit (${shrunk} cases)`);
  const calm = pose({ earU: 1 });
  near(earFit(layout(PRESETS.momo, calm, 40, 16, 20, { earScale: earScale(20) }), calm, 0), 1);
  const high = earFit(layout(PRESETS.momo, calm, 40, 3, 20, { earScale: 1 }), calm, 0);
  assert.ok(high < 1 && high >= MIN, `a cat too close to the top gets smaller ears, not ${high}`);
  assert.equal(earFit(layout(PRESETS.momo, calm, 40, 16, 0), calm, 0), 1, "a head of width 0 has nothing to fit");
  const nan = pose({ tilt: NaN });
  assert.equal(earFit(layout(PRESETS.momo, nan, 40, 16, 20), nan, 0), 1, "a pose that is not a number gives 1: nothing to fit");
  for (const s of [pose({ sy: Infinity }), pose({ tilt: 20, earU: 9 })]) {
    const f = earFit(layout(PRESETS.momo, s, 40, 16, 20), s, 0);
    assert.ok(Number.isFinite(f) && f >= MIN && f <= 1, `a bad pose gives a usable factor, not ${f}`);
  }
});

test("ear fit, the contract's: EAR_FIT and every earFitCases row replay from their own inputs (A-0b, merged `6adf584`)", () => {
  assert.deepEqual(EAR_FIT, geo.earFit);
  assert.ok(geo.earFitCases.length >= 80);
  for (const c of geo.earFitCases) {
    const p = presetOf(c.cat, c.kitten), s = pose(c.pose), L = layout(p, s, c.cx, c.cy, c.D, { earScale: c.earScale });
    near(earFit(L, s, c.ceiling, c.margin, c.minimum), c.fit);
  }
  const fits = geo.earFitCases.map((c) => c.fit);
  assert.ok(fits.includes(1) && fits.includes(MIN) && fits.some((f) => f > MIN && f < 1), "the cases need no fit, the minimum and something in between");
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npm run check:cat`
Expected: FAIL. `geometry.test.mjs` cannot load `src/cat/geometry.ts` (`ERR_MODULE_NOT_FOUND`).

- [ ] **Step 3: Create the geometry**

Create `windows/src/cat/geometry.ts`. The `// @@S4-...` lines are markers that Task 10 inserts above; leave them:

```ts title="windows/src/cat/geometry.ts"
// The cat's geometry: the neutral pose, the head turn (face warp), the outline, and where everything
// sits on the head. A port of the geometry section of design/prototype/cat-core.js, the tie-breaker.
// Numbers in, numbers out: no canvas here, so the plain-Node checks (npm run check:cat) can load it.
// Units are R, the head radius, unless a name says px.

import { TAU, clamp, hex, lerp, wrapA } from "./base.ts";
// @@S4-IMPORT
import type { CatPreset, Pose } from "./types.ts";

/** The neutral pose: every animatable property at rest. The engine's `s` starts here, and layout() reads one. */
export const newPose = (): Pose => ({
  yaw: 0, pitch: 0, roll: 0, tilt: 0, open: 1, sx: 1, sy: 1, oy: 0, ox: 0, tint: 0, blush: 0, es: 1, badgeS: 0,
  earL: 0, earR: 0, earU: 1, earF: 0, pupil: 0.45, mouth: 0, purr: 0, lid: 0, lift: 0, wh: 0, paws: 0,
  smile: 0, tongue: 0, mround: 0, mskew: 0, wavy: 0,
});

/**
 * Head turn toward the cursor. The face is a real 3D rotation of the head ellipsoid, with the muzzle
 * standing proud of it so it swings further than the cheeks, and the head outline leans into the turn.
 * yaw/pitch are the share of upstream's 0.62/0.5 rad gaze the face takes; the pupils carry the rest.
 */
export const FACE = { yaw: 0.82, pitch: 0.6, pitchDown: 0.32, lean: 0.08, bend: 0.1, muzzle: 0.12, nose: 0.05 };

/** Head width D (px) from which the full cat is drawn; below it the compact drawing (ink eyes, no irises, stripes or whiskers). */
export const DETAIL_FULL_MIN = 28;
export const detailOf = (D: number): "full" | "compact" => (D >= DETAIL_FULL_MIN ? "full" : "compact");

/**
 * Ear scale for the compact drawing, so the ears keep their headroom in the compact notch:
 * 1 from Ø28 up, easing down to COMPACT_EAR_SCALE at Ø20 and below.
 * PROVISIONAL: the spec only says "ears scaled down at Ø20"; the owner confirms the value on the
 * stage-1 contact sheet. If the owner changes it, the main session changes it once in cat-core.js and
 * regenerates the fixtures, this branch merges that, and this constant is set to the same number
 * (the geometry check fails until it is). This file never decides the value.
 */
export const COMPACT_EAR_SCALE = 0.8;
export const earScale = (D: number): number =>
  D >= DETAIL_FULL_MIN ? 1 : lerp(COMPACT_EAR_SCALE, 1, clamp((D - 20) / (DETAIL_FULL_MIN - 20), 0, 1));

/** Outline sample count: small heads (R under 20 px) use fewer points. */
export const outlineSteps = (R: number): number => (R < 20 ? 72 : 200);

/** The badge sits beside the right ear, and moves to the left in the compact notch so it never sits under the camera housing. */
export const badgeSide = (compactNotch: boolean): 1 | -1 => (compactNotch ? -1 : 1);

// ── Detail level and the flat fills (A-0b, merged `6adf584`: detailLevel, FLAT_FILL, mixHex and flatFillColors of cat-core.js) ──

/**
 * What the renderer draws at head width D: `detail`, `full`, and `flatFill`, which is on exactly when the cat is compact (below Ø28), that is
 * `!layout().full`. `override` is layout()'s `detail` option: an explicit "full" or "compact" wins over D.
 */
export interface DetailLevel { detail: "full" | "compact"; full: boolean; flatFill: boolean }
export const detailLevel = (D: number, override?: "full" | "compact" | null): DetailLevel => {
  const full = override ? override === "full" : D >= DETAIL_FULL_MIN;
  return { detail: full ? "full" : "compact", full, flatFill: !full };
};

/**
 * The flat drawing, for when detailLevel().flatFill is on. At Ø12 to Ø27 a gradient cannot be seen and costs a shading pass each, so:
 *   head: one fill, the preset's top and bot colour mixed headMix of the way (0.5, halfway);
 *   ears: one fill each, the ear's top and bot colour (the ear's own colour, if it has one, is both) mixed earMix of the way;
 *   ruff: one fill, the ruff's inner colour mixed ruffMix of the way (0.6) to its outer one;
 *   rim:  no rim gradient (rimGradient false). The white rim line of the dark coats stays;
 *   tabby crown band: one ellipse, radii crown.rx and crown.ry in R, at the centre where the gradient was, in the stripe colour at crown.alpha;
 *   point mask: one ellipse, radii point.rx and point.ry in R, at the centre where the gradient was, in the point colour at point.alpha.
 *     Tuned to the gradient it replaces (the same total ink, an edge between its half-strength and quarter-strength contours): 0.86 R by 0.54 R,
 *     not the Mac draft's 0.5 by 0.34, which was visibly smaller at Ø20.
 * Everything else (markings, eyes, blush, the state tint) is drawn as in the full cat.
 */
export const FLAT_FILL = { headMix: 0.5, earMix: 0.5, ruffMix: 0.6, rimGradient: false, crown: { rx: 0.4, ry: 0.26, alpha: 0.5 }, point: { rx: 0.86, ry: 0.54, alpha: 0.85 } };

/** `a` mixed `t` of the way to `b`, per channel on the 0 to 255 values (not rounded). */
export const mixHex = (a: string, b: string, t: number): number[] => {
  const y = hex(b);
  return hex(a).map((v, i) => lerp(v, y[i], t));
};

/** The flat colours of a preset, [r, g, b] in 0 to 255 (not rounded): the head, the two ears (left, right), the ruff (null without one) and the point mask (null unless the coat is "point"). */
export interface FlatColors { head: number[]; ears: [number[], number[]]; ruff: number[] | null; point: number[] | null }
export function flatFillColors(p: CatPreset): FlatColors {
  const ear = (sd: number) => {
    const c = p.earCols && p.earCols[sd < 0 ? 0 : 1];
    return mixHex(c || p.top, c || p.bot, FLAT_FILL.earMix);
  };
  return {
    head: mixHex(p.top, p.bot, FLAT_FILL.headMix),
    ears: [ear(-1), ear(1)],
    ruff: p.ruff ? mixHex(p.ruff.col[1], p.ruff.col[0], FLAT_FILL.ruffMix) : null,
    point: p.coat === "point" ? hex(p.point!) : null,
  };
}

/** Cursor to gaze: how far the cursor is from the cat in px, to -1…1 (tanh over 240 px across, 180 px up and down). */
export const CURSOR = { x: 240, y: 180 };
export const cursorLook = (dx: number, dy: number) => ({ x: Math.tanh(dx / CURSOR.x), y: -Math.tanh(dy / CURSOR.y) });

/** Pupil travel inside the eye: up to 0.24 of the eye width across and 0.18 of its height up and down. */
export const pupilOffset = (yaw: number, pitch: number, w: number, h: number): [number, number] => [
  clamp(yaw / 0.62, -1, 1) * 0.24 * w,
  -clamp(pitch / 0.5, -1, 1) * 0.18 * h,
];

/** The share of the gaze the face takes (FACE) and the roll fade: yf, pf, the warp pitch pt and the face opacity fa. */
export function faceAngles(s: Pick<Pose, "yaw" | "pitch" | "lift" | "roll">) {
  const yf = s.yaw * FACE.yaw;
  const pf = s.pitch * (s.pitch > 0 ? FACE.pitch : FACE.pitchDown);
  const pt = wrapA(pf + s.lift + s.roll);
  return { yf, pf, pt, fa: clamp((Math.cos(pt) - 0.05) / 0.3, 0, 1) };
}

/**
 * Superellipse outline as points [x, y], optionally with a fluffy edge (spike) on the lower half.
 * The fluff is a fixed sum of sines, so it needs no random numbers and is identical everywhere.
 */
export function supPoints(
  rx: number, ry: number, n: number, dy: number, spike: number, count: number, steps = 200,
  bend: readonly [number, number] | null = null,
): [number, number][] {
  const e = 2 / n;
  const pts: [number, number][] = [];
  for (let i = 0; i <= steps; i++) {
    const a = (i / steps) * TAU, c = Math.cos(a), s = Math.sin(a);
    let k = 1;
    if (spike) {
      const low = Math.max(0, s + 0.55) / 1.55;
      const vary = 0.55 + 0.45 * Math.sin(a * 5.3 + 1.1) * Math.sin(a * 2.7 + 0.4);
      k += low * spike * vary * Math.pow(Math.abs(Math.cos(a * count)), 1.8);
    }
    let x = Math.sign(c) * Math.pow(Math.abs(c), e) * rx * k;
    let y = Math.sign(s) * Math.pow(Math.abs(s), e) * ry * k + dy;
    if (bend) {
      const tx = x / rx, ty = y / ry;
      x += bend[0] * rx * Math.max(0, 1 - ty * ty);
      y += bend[1] * ry * Math.max(0, 1 - tx * tx);
    }
    pts.push([x, y]);
  }
  return pts;
}

export type Warp = (x: number, y: number) => [number, number];

/**
 * Face warp: maps a point drawn on the flat front view (units of R) onto the head ellipsoid rotated by
 * yaw and pitch, so markings, whisker pads and the muzzle turn with the eyes. Points outside the head
 * outline stay put. Identity at rest, so the rest pose matches the board exactly.
 */
export function mkWarp(p: Pick<CatPreset, "rx" | "ry" | "nosePh">, yaw: number, pt: number, R: number): Warp {
  const a = p.rx, b = p.ry, vm = Math.sin(p.nosePh) - 0.12;
  if (Math.abs(yaw) < 1e-4 && Math.abs(pt) < 1e-4) return (x, y) => [x * R, y * R];
  const cY = Math.cos(yaw), sY = Math.sin(yaw), cP = Math.cos(pt), sP = Math.sin(pt);
  return (x, y) => {
    const u = x / a, v = -y / b, q = 1 - u * u - v * v;
    if (q <= 0) return [x * R, y * R];
    const du = u / 0.55, dv = (v - vm) / 0.45;
    const w = Math.sqrt(q) + FACE.muzzle * Math.exp(-(du * du + dv * dv));
    const u1 = u * cY + w * sY, w1 = w * cY - u * sY, v1 = v * cP + w1 * sP;
    return [u1 * a * R, -v1 * b * R];
  };
}

/** A path command in units of R: Move, Quadratic curve, Line. */
export type PathCmd = readonly ["M", number, number] | readonly ["Q", number, number, number, number] | readonly ["L", number, number];

/** Flattens M/Q/L commands (units of R) into a dense point list, so the warp can bend every edge. */
export function flatten(cmds: readonly PathCmd[]): [number, number][] {
  const out: [number, number][] = [];
  let px = 0, py = 0;
  for (const c of cmds) {
    if (c[0] === "M") { px = c[1]; py = c[2]; out.push([px, py]); }
    else if (c[0] === "Q") {
      for (let i = 1; i <= 10; i++) {
        const t = i / 10, m = 1 - t;
        out.push([m * m * px + 2 * m * t * c[1] + t * t * c[3], m * m * py + 2 * m * t * c[2] + t * t * c[4]]);
      }
      px = c[3]; py = c[4];
    } else {
      for (let i = 1; i <= 8; i++) {
        const t = i / 8;
        out.push([px + (c[1] - px) * t, py + (c[2] - py) * t]);
      }
      px = c[1]; py = c[2];
    }
  }
  return out;
}

/** Momo's white map (blaze, muzzle, chin and chest), flattened so it can be warped onto the turning head. */
export const MOMO_WHITE = flatten([
  ["M", 0, -0.6], ["Q", -0.13, -0.4, -0.17, -0.12], ["Q", -0.19, 0.1, -0.26, 0.2], ["Q", -0.5, 0.38, -0.8, 0.36],
  ["L", -1.3, 0.3], ["L", -1.3, 1.3], ["L", 1.3, 1.3], ["L", 1.3, 0.3], ["L", 0.8, 0.36], ["Q", 0.5, 0.38, 0.26, 0.2],
  ["Q", 0.19, 0.1, 0.17, -0.12], ["Q", 0.13, -0.4, 0, -0.6],
]);

/** One ear, in head-local px before tilt and squash. `ek` is the compact ear scale (earScale), 1 when not compact. */
export function earGeom(p: CatPreset, s: Pose, sd: number, R: number, yf: number, pf: number, ek = 1) {
  const E = p.ear, rx = p.rx * R, ry = p.ry * R, th = sd * 0.6 + yf * 0.85, f = Math.max(0.3, Math.cos(th));
  return {
    bx: Math.sin(th) * p.earSpread * rx + Math.sin(yf) * FACE.bend * 0.54 * rx,
    by: -0.68 * ry - Math.sin(pf + s.lift) * 0.12 * ry,
    rot: sd * (E.rot + (sd < 0 ? s.earL : s.earR) + 0.95 * s.earF),
    h: E.h * R * s.earU * (1 - 0.4 * s.earF) * ek,
    bw: E.bw * R * f * ek,
    tip: E.tip * R * ek,
    cx: E.cx || 0.95,
  };
}

export interface LayoutOptions {
  /** Seconds, for the purr shake. */
  T?: number;
  detail?: "full" | "compact";
  /** 1 is the right of the head, -1 the left; a value in between slides the badge across (the greeting). */
  badgeSide?: number;
  /** Ear scale, 1 by default; apps pass earScale(D) for a compact cat. */
  earScale?: number;
}

export interface EyeLayout { sd: number; visible: boolean; x: number; y: number; fx: number; fy: number }
export interface NoseLayout { visible: boolean; nx?: number; ny?: number; nf?: number; nw?: number; nh?: number; my?: number }

/**
 * Everything geometric about one cat in one pose, in px: where the head is, the warp, the eyes, the nose
 * and mouth, the ears, the badge. Drawing code only consumes this.
 *   p preset, s pose (the engine's `s`), cx/cy the cat's resting centre, D the head width.
 * Head-local means relative to the head centre, before the tilt and squash. `mouth` is in world px
 * and null while the nose is turned out of sight. `W` maps flat-view R-units to head-local px.
 */
export function layout(p: CatPreset, s: Pose, cx: number, cy: number, D: number, o: LayoutOptions = {}) {
  const R = D / (2 * p.rx);
  const full = detailLevel(D, o.detail).full;
  const T = o.T || 0;
  const ek = o.earScale === undefined ? 1 : o.earScale;
  const rx = p.rx * R, ry = p.ry * R;
  const base = { x: cx, y: cy, R };
  const purr = s.purr > 0.01 ? Math.sin(T * TAU * 24) * 0.007 * s.purr : 0;
  cx += (s.ox + purr) * R;
  cy += s.oy * R;
  const at = { x: cx, y: cy, R, D };
  const { yf, pf, pt, fa } = faceAngles(s);
  cx += Math.sin(s.yaw) * FACE.lean * R;
  cy -= Math.sin(s.pitch) * FACE.lean * 0.8 * R;
  const W = mkWarp(p, yf, pt, R);
  const eyes: EyeLayout[] = [-1, 1].map((sd) => {
    const th = sd * p.eye.th + yf, cp = Math.cos(p.eye.ph + pt);
    const [x, y] = W(Math.sin(sd * p.eye.th) * Math.cos(p.eye.ph) * p.rx, -Math.sin(p.eye.ph) * p.ry);
    return {
      sd, visible: Math.cos(th) * cp > 0.04, x, y,
      fx: clamp(Math.cos(th) / Math.cos(p.eye.th), 0.55, 1.08),
      fy: clamp(cp / Math.cos(p.eye.ph), 0.18, 1.08),
    };
  });
  let nose: NoseLayout = { visible: false };
  let mouth: { x: number; y: number } | null = null;
  if (Math.cos(yf) * Math.cos(p.nosePh + pt) > 0.04) {
    const [nx0, ny0] = W(0, -Math.sin(p.nosePh) * p.ry);
    const nx = nx0 + Math.sin(yf) * FACE.nose * R, ny = ny0 - Math.sin(pf) * FACE.nose * 0.8 * R;
    const nf = Math.max(0.3, Math.cos(yf)), nw = p.noseW * R * nf, nh = p.noseH * R, my = ny + nh / 2;
    nose = { visible: true, nx, ny, nf, nw, nh, my };
    const lx = nx * s.sx, ly = (my + 0.12 * R) * s.sy, c = Math.cos(s.tilt), sn = Math.sin(s.tilt);
    mouth = { x: cx + lx * c - ly * sn, y: cy + lx * sn + ly * c };
  }
  const side = o.badgeSide || 1;
  return {
    R, D, full, rx, ry, base, at, head: { x: cx, y: cy }, yf, pf, pt, fa, W, steps: outlineSteps(R),
    bend: [Math.sin(yf) * FACE.bend, -Math.sin(pf) * FACE.bend * 0.7] as [number, number],
    ruff: { dx: -Math.sin(s.yaw) * FACE.lean * 1.1 * R, dy: Math.sin(s.pitch) * FACE.lean * 0.9 * R },
    eyes, nose, mouth,
    ears: [-1, 1].map((sd) => ({ sd, ...earGeom(p, s, sd, R, yf, pf, ek) })),
    badge: { x: cx + side * 1.4 * R * s.sx, y: cy - 0.92 * R * s.sy, k: s.badgeS * (full ? 1 : 1.25), small: !full, side },
  };
}
export type Layout = ReturnType<typeof layout>;
export type EarLayout = Layout["ears"][number];

// ── The ear fit (A-0b, merged `6adf584`: EAR_FIT and earFit of cat-core.js) ──

/** The ear fit's defaults: the room kept under the ceiling in px, and the smallest factor. */
export const EAR_FIT = { margin: 0.5, minimum: 0.35 };

/**
 * The factor (EAR_FIT.minimum to 1) to multiply the ear scale by so that no ear rises above `ceiling`, a y in the layout's own coordinates
 * (the top edge of the strip the cat sits in: in the compact island that is the top of the screen, where an ear is cut off).
 * 1 means the ears already fit; a cat so close to the ceiling that even the smallest ears would not fit is held at `minimum`; a pose that
 * is not a number gives 1 (nothing to fit). `margin` is the room kept under the ceiling, in px.
 *   L is a layout() made with the ear scale `ek`; the answer is the factor for ek, so layout(..., { earScale: ek * factor }) fits.
 *   s is the pose that made it (the tilt and squash turn the ears).
 * An ear scales about its own base, so the height of its top edge is linear in the scale and one solve replaces a search. The top edge of an
 * ear is a parabola (x = 0.9 tip u, y = -h + tip (0.475 + 0.825 u²) for u in -1 to 1, in ear space), and the world height of an ear-space point
 * is y0 + A x + B y, so the highest point is where u = -0.9 A / (1.65 B), held to -1 to 1. That is the exact top edge, not the apex. It does not look
 * at the sides of an ear, so ears folded far back at a large size are outside what it solves; the compact notch never gets there.
 */
export function earFit(L: Layout, s: Pick<Pose, "tilt" | "sx" | "sy">, ceiling: number, margin = EAR_FIT.margin, minimum = EAR_FIT.minimum): number {
  const ct = Math.cos(s.tilt), st = Math.sin(s.tilt);
  let f = 1;
  for (const e of L.ears) {
    const cr = Math.cos(e.rot), sr = Math.sin(e.rot);
    const A = st * s.sx * cr + ct * s.sy * sr, B = ct * s.sy * cr - st * s.sx * sr;
    const y0 = L.head.y + st * s.sx * e.bx + ct * s.sy * e.by;
    const rise = (u: number) => 0.9 * A * e.tip * u + B * (-e.h + e.tip * (0.475 + 0.825 * u * u)); // height of the top edge at u above the ear's base (negative: higher up)
    const d = Math.min(rise(-1), rise(1), rise(B > 1e-9 ? clamp((-0.9 * A) / (1.65 * B), -1, 1) : 0));
    if (y0 + d >= ceiling + margin || d >= -1e-9) continue;
    f = Math.min(f, Math.max(minimum, (ceiling + margin - y0) / d));
  }
  return Number.isFinite(f) ? Math.max(minimum, Math.min(1, f)) : 1;
}

/**
 * The draw order, as named layers. The renderer draws a *behind* pass, the head, then a *front* pass,
 * so outfits (sub-project I) can sit behind or in front of the head. Each layer's data comes from layout().
 * The collar (stage 6) is drawn in the front pass between `foldEars` and `whiskers`: the contract names that slot `collarPass` (A-0b, merged
 * `6adf584`) and leaves this list as A-0 wrote it.
 */
export const PASSES = {
  behind: ["glow", "zoomTrails", "ruff", "bib", "paws", "ears"],
  head: ["head", "markings", "tint", "rim", "blush", "eyes", "mouth", "nose"],
  front: ["foldEars", "whiskers", "badge", "particles", "balls"],
};

// @@S4-FLIGHT
```

- [ ] **Step 4: Run the tests and the type check**

Run: `npm run check:cat && npx tsc --noEmit`
Expected: all pass. The geometry test checks outlines (Shrimpy's fluffy edge included), 30 full `layout()` results, the warp, the eyes and the head lean against the fixtures, that a head rolled over the top or turned away gives no NaN; the 12 `detailLevels` (and that `flatFill` is `!layout().full`), `FLAT_FILL` and the 16 coats' `flatColors`; and that `earFit` keeps every ear tip under the strip's top and exactly on its margin when it shrinks them (against a brute-force walk of the whole outline), replays all 92 `earFitCases`, and leaves a calm cat's ears alone.

- [ ] **Step 5: Prove the ear-fit test bites**

In `EAR_FIT`, change `margin: 0.5` to `margin: -3`, run `npm run check:cat`, and see two tests fail: the "ear fit" strip test, which reads the fixture's margin and not the module's (for example `noodle strip 32 Ø20 earU 1.4 earF 0 oy 0 tilt 0: an ear that was left alone pokes out at 0.18…`), and the contract's test (`EAR_FIT` is no longer the fixture's). Change it back and run the check again: all pass. (The Mac draft's apex-only solve fails the same two tests: the strip test finds Noodle's ears at 0.43 px, not on the 0.5 margin, and an `earFitCases` row differs in the third decimal. That is why the plan takes the contract's body.)

- [ ] **Step 6: Commit**

```bash
git add windows/src/cat/geometry.ts windows/scripts/cat-tests/geometry.test.mjs
git commit -m "feat(cat): geometry, the face warp, the layout and the ear fit, tested against the fixtures

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The renderer and the `?dev` contact sheet

**Agent:** `nm-implementer`.

**Files:**
- Create: `windows/src/cat/renderer.ts`, `windows/src/cat/dev.ts`
- Modify: `windows/src/main.ts`
- Test: `windows/scripts/cat-tests/fake-canvas.mjs`, `windows/scripts/cat-tests/renderer.test.mjs`

**Interfaces:**
- Consumes: `layout`, `supPoints`, `earScale`, `earFit`, `detailLevel`, `flatFillColors`, `FLAT_FILL`, `pupilOffset`, `MOMO_WHITE`, `cursorLook`, `newPose`, `type EarLayout`, `type FlatColors` from `geometry.ts`; `PRESETS`, `CAT_IDS`, `kittenOf` from `presets.ts`; `COL`, `EZ`, `TAU`, `clamp`, `hex`, `lerp`, `rng`, `type BadgeKind`, `type StateName` from `base.ts`; the types from `types.ts`.
- Produces `src/cat/renderer.ts`: `drawCat(ctx, view, cx, cy, D, options?)`, which is `frameOf(view, cx, cy, D, options?)` followed by three separate passes, `drawBehindPass(ctx, frame)` (glow, zoomies' afterimages, ruff and bib, paws, ears), `drawHeadPass(ctx, frame)` (head, markings, tint, blush, eyes, mouth, nose, rim light) and `drawFrontPass(ctx, frame)` (a Scottish Fold's flaps, whiskers, badge, particles, balls), so outfits (sub-project I) can sit behind or in front of the head; `type CatFrame`. The `view` is a `CatView` (`p`, `s`, `state`, `col`, `gc`, `ga`, `zv`, `parts`, `balls`, `badge`, `badgeCol`, `blushBase`, `waveStart`, `waveUntil`, `eyeShape()`, `mouthOpen()`, `now()`, and the three the renderer writes: `base`, `at`, `mouthAt`) and the `options` are `DrawOptions` (`fur`, `tint`, `glow`, `paws`, `detail`, `badgeSide` as a number, `badge`, `squash: [sx, sy]`, `tilt`, `earCeiling`: the y of the top of the strip, under which the ears are fitted with the contract's `earFit`, on top of the compact ear scale; the cat below Ø28 is drawn with the flat fills of `flatFillColors` and `FLAT_FILL`; both are A-0b, merged `6adf584`); `stillView(preset, pose, state?)`: a `CatView` of a cat that never moves; `enginePaws(view, rx, ry): PawSpec[]`; `drawPaw`; `drawFileIcon(ctx, x, y, size, rot, ext)`; `type PawSpec`.
- Produces `src/cat/dev.ts`: `mountDev(root: HTMLElement): void`, the `?dev` page. This task builds its still contact sheet; later tasks add live panels at its markers.
- `main.ts` mounts it for `/?dev` on the dev server only (`import.meta.env.DEV`).

- [ ] **Step 1: Write the failing tests**

The renderer is checked by a canvas that draws nothing and fails on any number that is not finite, so a NaN that would blank a cat in a browser fails here. Create `windows/scripts/cat-tests/fake-canvas.mjs`:

```js title="windows/scripts/cat-tests/fake-canvas.mjs"
// A canvas that draws nothing and checks what it is asked to draw: every number is finite, so a NaN
// that would blank a cat in a browser fails here instead. Enough of the 2D API for the cat renderer.
import assert from "node:assert/strict";

/** Counts of the calls made, by name (`ctx.calls`), and what the flat-fill checks look at (`ctx.seen`): every string a `fillStyle` was set to, and the arguments of every `ellipse`. */
export function fakeCanvas() {
  const calls = {}, seen = { fillStyles: [], ellipses: [] };
  const note = (name, args) => {
    calls[name] = (calls[name] || 0) + 1;
    for (const a of args) if (typeof a === "number") assert.ok(Number.isFinite(a), `${name}(${args.join(", ")}) was given ${a}`);
  };
  const store = {};
  const gradient = { addColorStop: (...a) => note("addColorStop", a.slice(0, 1)) };
  const ctx = new Proxy(store, {
    get(t, k) {
      if (k === "calls") return calls;
      if (k === "seen") return seen;
      if (k in t) return t[k];
      if (k === "createLinearGradient" || k === "createRadialGradient") return (...a) => { note(k, a); return gradient; };
      if (k === "isPointInPath") return () => false;
      if (k === "measureText") return () => ({ width: 10 });
      return (...a) => { if (k === "ellipse") seen.ellipses.push(a); return note(String(k), a); };
    },
    set(t, k, v) {
      if (typeof v === "number") assert.ok(Number.isFinite(v), `${String(k)} = ${v}`);
      if (k === "fillStyle" && typeof v === "string") seen.fillStyles.push(v);
      t[k] = v;
      return true;
    },
  });
  return ctx;
}

/** The two browser globals the renderer touches: Path2D, and document.createElement("canvas") for fur lines. */
export function installBrowserStubs() {
  globalThis.Path2D = class {
    constructor() { return new Proxy(this, { get: (t, k) => (k in t ? t[k] : () => {}) }); }
  };
  globalThis.document = { createElement: () => ({ getContext: () => fakeCanvas() }) };
}
```

Create `windows/scripts/cat-tests/renderer.test.mjs`:

```js title="windows/scripts/cat-tests/renderer.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import { drawBehindPass, drawCat, drawFrontPass, drawHeadPass, frameOf, stillView } from "../../src/cat/renderer.ts";
import { hex } from "../../src/cat/base.ts";
import { earFit, earScale, layout, newPose } from "../../src/cat/geometry.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { earTop, load, near } from "./util.mjs";

installBrowserStubs();

test("every coat and every kitten draws at every size, plain and with fur lines, without a bad number", () => {
  for (const id of CAT_IDS) for (const kit of [false, true]) for (const D of [12, 20, 28, 44, 66]) for (const fur of [false, true]) {
    const ctx = fakeCanvas();
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    drawCat(ctx, stillView(p, newPose()), 100, 80, D, { fur, glow: true });
    assert.ok(ctx.calls.fill > 5, `${id} Ø${D}: something was drawn`);
  }
});

test("a cat that is turned, rolled or squashed past the normal range still draws only finite numbers", () => {
  for (const id of ["shrimpy", "momo", "latte", "button"]) for (const D of [0, 12, 66]) for (const s of [
    { yaw: 3 }, { yaw: -3 }, { pitch: 2 }, { roll: Math.PI }, { roll: 20 }, { lift: 6 }, { sx: 0 }, { open: 0 }, { es: 0 },
    { yaw: 1.6, pitch: 1, roll: 1, badgeS: 1, blush: 1, mouth: 1.3, tongue: 1, mround: 1, wavy: 1, smile: -3, mskew: 3, paws: 1 },
  ]) {
    const ctx = fakeCanvas();
    drawCat(ctx, stillView(PRESETS[id], { ...newPose(), ...s }), 50, 50, D, { fur: true });
  }
});

test("the renderer leaves where the cat was drawn, for hairballs and flying files", () => {
  const v = stillView(PRESETS.momo, newPose());
  assert.equal(v.base, null);
  drawCat(fakeCanvas(), v, 40, 30, 66);
  assert.deepEqual(v.base, { x: 40, y: 30, R: 66 / (2 * PRESETS.momo.rx) });
  assert.ok(v.mouthAt && Number.isFinite(v.mouthAt.x), "the mouth position is left for the next frame");
  assert.equal(v.at.D, 66);
});

test("the cat is drawn in three separate passes, behind the head, the head, in front of it, so outfits can sit on either side", () => {
  const v = () => stillView(PRESETS.shrimpy, newPose());
  const f = frameOf(v(), 100, 80, 66);
  const behind = fakeCanvas(), head = fakeCanvas(), front = fakeCanvas(), all = fakeCanvas();
  drawBehindPass(behind, f); drawHeadPass(head, f); drawFrontPass(front, f);
  drawCat(all, v(), 100, 80, 66);
  assert.equal(behind.calls.clip, undefined, "the behind pass has no face to clip");
  assert.ok(head.calls.clip >= 1, "the face is clipped to the head");
  assert.ok(front.calls.stroke > 30 && !(behind.calls.stroke > 30) && !(head.calls.stroke > 30), "the whiskers are in the front pass only");
  for (const name of ["fill", "stroke", "save", "restore", "translate", "quadraticCurveTo"]) {
    assert.equal(all.calls[name] || 0, (behind.calls[name] || 0) + (head.calls[name] || 0) + (front.calls[name] || 0), `${name}: drawCat is the three passes`);
  }
  assert.equal(all.calls.save, all.calls.restore, "every save is restored");
});

test("below Ø28 the cat is drawn with flat fills: no gradient for the head, ears, ruff, rim, crown or point; Ø28 and up shades them (A-0b, merged `6adf584`)", () => {
  const gradients = (ctx) => (ctx.calls.createLinearGradient || 0) + (ctx.calls.createRadialGradient || 0);
  for (const id of CAT_IDS) for (const kit of [false, true]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    for (const D of [12, 20, 27]) {
      const ctx = fakeCanvas();
      drawCat(ctx, stillView(p, newPose()), 100, 80, D);
      assert.equal(gradients(ctx), 0, `${id}${kit ? " kitten" : ""} Ø${D}: flat fills, no gradient`);
      assert.ok(ctx.calls.fill > 5, `${id} Ø${D}: something was drawn`);
    }
    const full = fakeCanvas();
    drawCat(full, stillView(p, newPose()), 100, 80, 28);
    assert.ok(gradients(full) >= 3, `${id}${kit ? " kitten" : ""} Ø28: the full cat is shaded`);
  }
});

test("the flat fills are the contract's numbers and colours: each coat's flat colours, the crown band and the point mask (A-0b, merged `6adf584`)", () => {
  const geo = load("geometry-cases.json"), rgbOf = (c) => `rgb(${c.map(Math.round)})`;
  const drawn = (id, D) => { const ctx = fakeCanvas(); drawCat(ctx, stillView(PRESETS[id], newPose()), 100, 80, D); return ctx.seen; };
  for (const id of CAT_IDS) {
    const { head, ears, ruff } = geo.flatColors[id], flat = drawn(id, 20).fillStyles;
    assert.ok(flat.includes(rgbOf(head)), `${id}: the head is one flat colour`);
    for (const e of ears) assert.ok(flat.includes(rgbOf(e)), `${id}: an ear is one flat colour`);
    if (ruff) assert.ok(flat.includes(rgbOf(ruff)), `${id}: the ruff is one flat colour`);
    assert.ok(!drawn(id, 28).fillStyles.some((s) => s.startsWith("rgb(")), `${id} Ø28: shaded, no flat colour`);
  }
  const { crown, point } = geo.flatFill, R = (id, D) => D / (2 * PRESETS[id].rx);
  const ellipse = (seen, rx, ry) => seen.ellipses.some((a) => Math.abs(a[2] - rx) < 1e-9 && Math.abs(a[3] - ry) < 1e-9);
  for (const id of ["latte", "cloud"]) {
    const seen = drawn(id, 20);
    assert.ok(ellipse(seen, point.rx * R(id, 20), point.ry * R(id, 20)), `${id}: the point mask is ${point.rx} R by ${point.ry} R`);
    assert.ok(seen.fillStyles.includes(`rgba(${geo.flatColors[id].point.map(Math.round)},${point.alpha})`), `${id}: in its point colour at alpha ${point.alpha}`);
  }
  for (const id of ["shrimpy", "ginger", "silver"]) {
    const seen = drawn(id, 20);
    assert.ok(ellipse(seen, crown.rx * R(id, 20), crown.ry * R(id, 20)), `${id}: the crown band is ${crown.rx} R by ${crown.ry} R`);
    assert.ok(seen.fillStyles.includes(`rgba(${hex(PRESETS[id].stripe)},${crown.alpha})`), `${id}: in its stripe colour at alpha ${crown.alpha}`);
  }
});

test("the ears are fitted under the strip: with an earCeiling no tip leaves it, a shrunk ear sits exactly on the margin, and a calm cat keeps its ears", () => {
  let shrunk = 0;
  for (const id of ["momo", "shrimpy", "noodle", "puff", "button"]) for (const [earU, oy, tilt] of [[1, 0, 0], [1.4, 0, 0], [1.4, -0.26, 0], [1.22, -0.26, 0], [1.4, -0.3, 0.24], [1.4, -0.3, -0.24]]) {
    const s = { ...newPose(), earU, oy, tilt };
    const bare = frameOf(stillView(PRESETS[id], s), 40, 16, 20), fitted = frameOf(stillView(PRESETS[id], s), 40, 16, 20, { earCeiling: 0 });
    const ratio = fitted.L.ears[0].h / bare.L.ears[0].h;
    if (earU === 1 && oy === 0 && tilt === 0) assert.equal(ratio, 1, `${id}: a calm cat keeps its ears`);
    if (ratio < 1 - 1e-9) {
      shrunk++;
      const top = Math.min(...fitted.L.ears.map((e) => earTop(fitted.L, fitted.s, e)));
      if (ratio > 0.35 + 1e-6) assert.ok(Math.abs(top - 0.5) <= 1e-3, `${id} earU ${earU} oy ${oy} tilt ${tilt}: the top of the ears is at ${top}, not on the margin 0.5`);
    }
    for (const e of bare.L.ears) assert.ok(Number.isFinite(e.h), "no ceiling: the ears are the scaled ones");
  }
  assert.ok(shrunk > 5, `the hop pushes ears out of the strip, so the fit has work to do (${shrunk} cases)`);
});

test("every compact cat wears the compact ear scale, and the fit multiplies it: earScale(D) * f (A-0b, merged `6adf584`)", () => {
  const p = PRESETS.noodle, s = { ...newPose(), earU: 1.4, oy: -0.3, tilt: 0.24 };
  const earH = (D, o) => frameOf(stillView(p, s), 40, 16, D, o).L.ears[0].h, want = (D, ek) => layout(p, s, 40, 16, D, { earScale: ek }).ears[0].h;
  for (const D of [12, 20, 24, 27.999]) near(earH(D), want(D, earScale(D)));
  for (const D of [28, 44, 66]) near(earH(D), want(D, 1));
  near(earH(20, { detail: "full" }), want(20, 1));                        // drawn at full detail, a small cat keeps its full ears
  const f = earFit(layout(p, s, 40, 16, 20, { earScale: earScale(20) }), s, 0);
  assert.ok(f < 1 && f > 0.35, `this pose needs the fit: ${f}`);
  near(earH(20, { earCeiling: 0 }), want(20, earScale(20) * f));
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `npm run check:cat`
Expected: FAIL. `renderer.test.mjs` cannot load `src/cat/renderer.ts` (`ERR_MODULE_NOT_FOUND`).

- [ ] **Step 3: Create the renderer**

This is the prototype's `drawCat` and its helpers, ported to TypeScript. The coats' markings, the ears (and the Scottish Fold's flap in the front pass), the eyes (the realistic almond eye at Ø28 and up, the ink shapes below it and for every expression), the mouth with all six values, the whiskers, the badge, the particles, hairballs and the paws are all here, even though the states, emotes and the catch that drive them arrive in later tasks. Create `windows/src/cat/renderer.ts`:

```ts title="windows/src/cat/renderer.ts"
// The cat renderer: draws one cat into a Canvas 2D context, no images. A port of the drawing in
// design/prototype/notchmeow.html, which is the visual source of truth for the characters.
//
// Everything geometric comes from layout() in geometry.ts. The pass order is `PASSES`: a *behind* pass
// (glow, trails, ruff and bib, paws, ears), the head and its face, then a *front* pass (folded ears,
// whiskers, badge, particles, balls), so outfits (sub-project I) can sit on either side of the head.
//
// Below head width Ø28 the cat is the compact drawing: ink eyes, no whiskers, and FLAT FILLS (`flatFillColors` and `FLAT_FILL` of geometry.ts:
// one colour for the head, the ears and the ruff, no rim gradient, a flat tabby crown and point mask), because a gradient cannot be seen at
// that size. Every compact cat wears the compact ear scale, and in the compact island the ears are also fitted under the top of the strip
// (`earCeiling`). Both are the contract's (A-0b, merged `6adf584`).

import { FLAT_FILL, MOMO_WHITE, detailLevel, earFit, earScale, flatFillColors, layout, pupilOffset, supPoints } from "./geometry.ts";
import type { EarLayout, FlatColors, Layout } from "./geometry.ts";
import { COL, EZ, TAU, clamp, hex, lerp, rng } from "./base.ts";
import type { BadgeKind, StateName } from "./base.ts";
import type { Ball, CatPreset, EyeShape, Particle, Pose } from "./types.ts";

type Ctx = CanvasRenderingContext2D;

/** What the renderer reads from a cat. The engine (BotEngine) satisfies it, and so does stillView(). */
export interface CatView {
  p: CatPreset;
  s: Pose;
  state: StateName;
  /** The state colour now, 0 to 255 (it fades between states). */
  col: number[];
  /** The glow colour now, 0 to 255, and its strength. */
  gc: number[];
  ga: number;
  /** How fast the cat is sliding sideways in R per second (zoomies leave a trail). */
  zv: number;
  parts: Particle[];
  balls: Ball[];
  badge: BadgeKind | null;
  /** Overrides the state colour of the badge. */
  badgeCol: string | null;
  blushBase: number;
  waveStart: number;
  waveUntil: number;
  eyeShape(): EyeShape;
  mouthOpen(): number;
  /** Milliseconds. */
  now(): number;
  /** The renderer leaves these for the next frame: where the cat was drawn (R, px), and where its mouth is (hairballs and files go there). */
  base: { x: number; y: number; R: number } | null;
  at: { x: number; y: number; R: number; D: number } | null;
  mouthAt: { x: number; y: number } | null;
}

/** A paw to draw behind the head: position in head-local px, how far it is out (0 to 1), rotation, toe beans showing. */
export interface PawSpec { x: number; y: number; k: number; rot: number; beans: boolean }

export interface DrawOptions {
  /** Optional fur strands. Flat colour is the default. */
  fur?: boolean;
  /** The state tint over the lower face, on by default. */
  tint?: boolean;
  /** The soft glow behind the head. */
  glow?: boolean;
  /** Paws to draw instead of the engine's wave paws. */
  paws?: readonly PawSpec[];
  /** Forces the detail level; by default head width Ø28 and up is full. */
  detail?: "full" | "compact";
  /** 1 puts the badge on the right of the head, -1 on the left (the compact notch). */
  badgeSide?: number;
  /** false hides the badge. */
  badge?: boolean;
  /** Extra squash on top of the pose, and extra tilt in radians: the drop view's travelling cat. */
  squash?: readonly [number, number];
  tilt?: number;
  /**
   * The y of the top of the strip the cat lives in, in the canvas's own coordinates: the ears are shrunk just enough that no tip rises
   * above it (the contract's earFit, on top of the compact ear scale; A-0b, merged `6adf584`). The compact island passes it, because the top of its strip
   * is the top of the screen.
   */
  earCeiling?: number;
}

/** A cat that never moves: icons, the contact sheet's first frame and tests. */
export function stillView(p: CatPreset, s: Pose, state: StateName = "idle"): CatView {
  return {
    p, s, state, col: hex(COL[state]), gc: [255, 255, 255], ga: 0.12, zv: 0, parts: [], balls: [], badge: null, badgeCol: null,
    blushBase: 0, waveStart: 0, waveUntil: 0, eyeShape: () => "pill", mouthOpen: () => 0, now: () => 0,
    base: null, at: null, mouthAt: null,
  };
}

// ── Little helpers ────────────────────────────────────────────────────────────

/** Rounded rectangle path. */
function rr(c: Ctx, x: number, y: number, w: number, h: number, r: number) {
  r = Math.max(0, Math.min(r, w / 2, h / 2));
  c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r);
  c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath();
}
function heartP(c: Ctx, s: number) {
  c.beginPath(); c.moveTo(0, 0.38 * s); c.bezierCurveTo(-1.05 * s, -0.15 * s, -0.5 * s, -0.95 * s, 0, -0.38 * s);
  c.bezierCurveTo(0.5 * s, -0.95 * s, 1.05 * s, -0.15 * s, 0, 0.38 * s); c.fill();
}
function starP(c: Ctx, o: number, i: number) {
  c.beginPath();
  for (let k = 0; k < 10; k++) { const r = k % 2 ? i : o, a = -Math.PI / 2 + (k * Math.PI) / 5; c.lineTo(Math.cos(a) * r, Math.sin(a) * r); }
  c.closePath(); c.fill();
}

/** A flat colour of `flatFillColors` (0 to 255, not rounded) as an "rgb()" string: the compact cat's one colour where a gradient cannot be seen. */
const rgbOf = (c: readonly number[]): string => `rgb(${c.map(Math.round).join(",")})`;

/** Superellipse as a Path2D; the points come from supPoints. */
function sup(rx: number, ry: number, n: number, dy: number, spike: number, count: number, steps = 200, bend: readonly [number, number] | null = null) {
  const path = new Path2D();
  supPoints(rx, ry, n, dy, spike, count, steps, bend).forEach(([x, y], i) => (i ? path.lineTo(x, y) : path.moveTo(x, y)));
  path.closePath();
  return path;
}

type W = (x: number, y: number) => [number, number];

/** An ellipse on the flat face, bent by the warp. */
function wEll(Wp: W, x: number, y: number, a: number, b: number, n = 20) {
  const P = new Path2D();
  for (let i = 0; i <= n; i++) { const t = (i / n) * TAU, [X, Y] = Wp(x + a * Math.cos(t), y + b * Math.sin(t)); i ? P.lineTo(X, Y) : P.moveTo(X, Y); }
  P.closePath();
  return P;
}
/** A wobbly patch (calico), bent by the warp. */
function wBlob(Wp: W, x: number, y: number, a: number, b: number, rot: number, seed: number, n = 32) {
  const P = new Path2D(), c = Math.cos(rot), s = Math.sin(rot);
  for (let i = 0; i <= n; i++) {
    const t = (i / n) * TAU, k = 1 + 0.12 * Math.sin(3 * t + seed) + 0.06 * Math.sin(5 * t + 2 * seed);
    const lx = a * Math.cos(t) * k, ly = b * Math.sin(t) * k;
    const [X, Y] = Wp(x + lx * c - ly * s, y + lx * s + ly * c);
    i ? P.lineTo(X, Y) : P.moveTo(X, Y);
  }
  P.closePath();
  return P;
}
/** A curved stroke on the flat face, bent by the warp. */
function wStroke(c: Ctx, Wp: W, col: string, w: number, pts: readonly number[]) {
  const [x0, y0, cx, cy, x1, y1] = pts;
  c.strokeStyle = col; c.lineWidth = w; c.lineCap = "round"; c.lineJoin = "round"; c.beginPath();
  for (let i = 0; i <= 12; i++) {
    const t = i / 12, m = 1 - t, [X, Y] = Wp(m * m * x0 + 2 * m * t * cx + t * t * x1, m * m * y0 + 2 * m * t * cy + t * t * y1);
    i ? c.lineTo(X, Y) : c.moveTo(X, Y);
  }
  c.stroke();
}
function momoWhite(Wp: W) {
  const P = new Path2D();
  MOMO_WHITE.forEach(([x, y], i) => { const [X, Y] = Wp(x, y); i ? P.lineTo(X, Y) : P.moveTo(X, Y); });
  P.closePath();
  return P;
}

// ── Optional fur lines: seeded strands, built once per preset (same seeds as the board) ──

interface Fur { head: { x: number; y: number; x2: number; y2: number; c: string }[]; ruff: { x: number; y: number; ux: number; uy: number; L: number; c: string }[] }
const FURC = new WeakMap<CatPreset, Fur>();
const FURDEF = { n: 420, l0: 0.04, l1: 0.05, w: 0.01, dark: "rgba(0,0,0,.22)", light: "rgba(255,255,255,.2)" };
let HIT: CanvasRenderingContext2D | null = null;

function furStrands(p: CatPreset): Fur {
  const cached = FURC.get(p);
  if (cached) return cached;
  const o = (p.furOpts || FURDEF) as typeof FURDEF & { wDark?: string; wLight?: string }, rx = p.rx, ry = p.ry;
  const head: Fur["head"] = [], ruff: Fur["ruff"] = [];
  let white: Path2D | null = null;
  if (p.coat === "tuxedo") { HIT ??= document.createElement("canvas").getContext("2d"); white = momoWhite((x, y) => [x * 100, y * 100]); }
  const eyes = [-1, 1].map((sd) => [Math.sin(sd * p.eye.th) * Math.cos(p.eye.ph) * rx, -Math.sin(p.eye.ph) * ry]);
  const nz = [0, -Math.sin(p.nosePh) * ry];
  let rand = rng(13);
  for (let i = 0; i < o.n; i++) {
    const x = (rand() * 2 - 1) * rx, y = (rand() * 2 - 1) * ry;
    if ((x / rx) ** 2 + (y / ry) ** 2 > 1) continue;
    if (eyes.some((q) => Math.hypot(x - q[0], (y - q[1]) * 1.25) < 0.3) || Math.hypot(x - nz[0], y - nz[1] - 0.1) < 0.32) continue;
    let dx: number, dy: number;
    if (y < -0.32) { dx = x * 0.35; dy = -1; } else { dx = x; dy = y + 0.5; }
    const m = Math.hypot(dx, dy) || 1, L = o.l0 + rand() * o.l1;
    const onW = !!(white && HIT && HIT.isPointInPath(white, x * 100, y * 100));
    head.push({ x, y, x2: x + (dx / m) * L, y2: y + (dy / m) * L, c: rand() < 0.55 ? (onW ? o.wDark! : o.dark) : (onW ? o.wLight! : o.light) });
  }
  if (p.ruff) {
    const r = p.ruff, e = 2 / 2.4;
    rand = rng(7);
    for (let i = 0; i < 300; i++) {
      const a = rand() * TAU, c = Math.cos(a), s = Math.sin(a);
      const ex = Math.sign(c) * Math.pow(Math.abs(c), e) * r.rx, ey = Math.sign(s) * Math.pow(Math.abs(s), e) * r.ry;
      const f = 0.7 + rand() * 0.32, x = ex * f, y = ey * f + r.dy;
      let dx = ex, dy = ey + 0.35 * Math.max(0, s);
      const m = Math.hypot(dx, dy) || 1;
      dx /= m; dy /= m;
      const j = (rand() - 0.5) * 0.5, ux = dx * Math.cos(j) - dy * Math.sin(j), uy = dx * Math.sin(j) + dy * Math.cos(j), L = 0.05 + rand() * 0.08;
      ruff.push({ x, y, ux, uy, L, c: rand() < 0.5 ? "rgba(214,192,156,.45)" : "rgba(84,66,50,.38)" });
    }
  }
  const out = { head, ruff };
  FURC.set(p, out);
  return out;
}

/** A whisker: a curve that thins toward its tip. */
function taper(c: Ctx, x0: number, y0: number, cx: number, cy: number, x1: number, y1: number, w0: number, col: string, a0: number) {
  const N = 16;
  c.strokeStyle = col; c.lineCap = "round";
  let px = x0, py = y0;
  for (let i = 1; i <= N; i++) {
    const s = i / N, m = 1 - s, x = m * m * x0 + 2 * m * s * cx + s * s * x1, y = m * m * y0 + 2 * m * s * cy + s * s * y1;
    c.globalAlpha = a0 * (1 - 0.7 * s); c.lineWidth = Math.max(0.35, w0 * (1 - 0.88 * s));
    c.beginPath(); c.moveTo(px, py); c.lineTo(x, y); c.stroke();
    px = x; py = y;
  }
  c.globalAlpha = 1;
}

// ── Ears, eyes ────────────────────────────────────────────────────────────────

/** One ear. `front` draws the folded flap of a Scottish Fold in the front pass, over the head. */
function drawEar(c: Ctx, p: CatPreset, ear: EarLayout, R: number, full: boolean, flat: FlatColors | null, front = false) {
  const E = p.ear, { bx, by, rot, h, bw, tip, cx, sd } = ear;
  c.save(); c.translate(bx, by); c.rotate(rot);
  const path = (k: number) => {
    c.beginPath(); c.moveTo(-bw * k, 0.25 * R); c.quadraticCurveTo(-bw * k * cx, -h * k * 0.4, -tip * 0.9, -h * k + tip * 1.3);
    c.quadraticCurveTo(0, -h * k - tip * 0.35, tip * 0.9, -h * k + tip * 1.3); c.quadraticCurveTo(bw * k * cx, -h * k * 0.4, bw * k, 0.25 * R); c.closePath();
  };
  const ec = p.earCols && p.earCols[sd < 0 ? 0 : 1];
  // Below Ø28 the ear's top-to-bottom shading cannot be seen: the flat colour of flatFillColors (the ear's own colour, if it has one) instead of a gradient.
  let g: string | CanvasGradient;
  if (flat) g = rgbOf(flat.ears[sd < 0 ? 0 : 1]);
  else { g = c.createLinearGradient(0, -h, 0, 0.25 * R); g.addColorStop(0, ec || p.top); g.addColorStop(1, ec || p.bot); }
  if (front) {
    const fw = bw * 0.62, yc = -h + tip * 0.8, ty = -h * 0.05;
    const flap = () => {
      c.beginPath(); c.moveTo(-fw, yc); c.quadraticCurveTo(0, yc - fw * 0.75, fw, yc); c.quadraticCurveTo(fw * 0.7, (yc + ty) / 2, 0, ty);
      c.quadraticCurveTo(-fw * 0.7, (yc + ty) / 2, -fw, yc); c.closePath();
    };
    c.save(); c.translate(0, 0.025 * R); c.fillStyle = "rgba(0,0,0,.2)"; flap(); c.fill(); c.restore();
    c.fillStyle = g; flap(); c.fill();
    if (full) {
      c.strokeStyle = "rgba(0,0,0,.2)"; c.lineWidth = 0.016 * R; c.lineCap = "round"; c.beginPath(); c.moveTo(-fw * 0.8, yc + 0.02 * R);
      c.quadraticCurveTo(0, yc - fw * 0.5, fw * 0.8, yc + 0.02 * R); c.stroke();
    }
    c.restore();
    return;
  }
  c.fillStyle = g; path(1); c.fill();
  if (p.rimLight) { c.strokeStyle = "rgba(255,255,255,.22)"; c.lineWidth = Math.max(0.8, 0.013 * R); path(1); c.stroke(); }
  c.fillStyle = p.inner; c.globalAlpha = 0.9; path(0.6); c.fill(); c.globalAlpha = 1;
  if (E.tuft && full) {
    c.strokeStyle = p.inner; c.globalAlpha = 0.7; c.lineCap = "round"; c.lineWidth = 0.022 * R;
    for (const k of [-1, 0, 1]) { c.beginPath(); c.moveTo(k * bw * 0.3, 0.06 * R); c.quadraticCurveTo(k * bw * 0.5, -h * 0.25, k * bw * 0.42 + (k >= 0 ? 1 : -1) * 0.02 * R, -h * 0.5); c.stroke(); }
    c.globalAlpha = 1; c.strokeStyle = p.top; c.lineWidth = 0.025 * R; c.beginPath(); c.moveTo(0, -h + tip * 0.2); c.lineTo(sd * 0.015 * R, -h - 0.05 * R); c.stroke();
  }
  c.restore();
}

function almondPath(c: Ctx, p: CatPreset, sd: number, R: number, open: number) {
  const E = p.eye, w = E.w * R, h = E.h * R * Math.max(open, 0.06), H = E.h * R, k = E.round ? 2.2 : 1.85;
  const iy = (E.round ? 0.04 : 0.12) * H, oy = (E.round ? -0.04 : -0.18) * H, ix = -sd * w, ox = sd * w;
  c.beginPath(); c.moveTo(ix, iy); c.quadraticCurveTo(0, -h * k, ox, oy); c.quadraticCurveTo(0, H * (0.55 + 0.45 * Math.max(open, 0.06)) * k, ix, iy); c.closePath();
}

/** The realistic eye: iris gradient, dilating pupil, Momo's yellow lid ring, catchlights, liner. */
function almondEye(c: Ctx, s: Pose, p: CatPreset, sd: number, R: number, pupil: number, open: number) {
  const E = p.eye, w = E.w * R, h = E.h * R, a0 = c.globalAlpha;
  if (open < 0.22) {
    c.strokeStyle = p.ink; c.globalAlpha = a0 * 0.9; c.lineWidth = Math.max(1, 0.045 * R); c.lineCap = "round"; c.beginPath();
    c.moveTo(-w, 0); c.quadraticCurveTo(0, 0.4 * h, w, 0); c.stroke(); c.globalAlpha = a0;
    return;
  }
  c.save(); almondPath(c, p, sd, R, open); c.clip();
  const g = c.createRadialGradient(0, 0, 0, 0, 0, w * 1.1), ir = (sd > 0 && p.irisR) || p.iris;
  g.addColorStop(0, ir[0]); g.addColorStop(1, ir[1]); c.fillStyle = g; c.fillRect(-w * 1.3, -h * 3, w * 2.6, h * 6);
  const [px, py] = pupilOffset(s.yaw, s.pitch, w, h);
  c.fillStyle = "#0E0B09"; c.beginPath(); c.ellipse(px, py, w * (p.pupil0 + 0.5 * pupil), h * 1.1, 0, 0, TAU); c.fill();
  if (p.lidTint) { c.save(); c.strokeStyle = p.lidTint; c.globalAlpha = a0 * 0.85; c.lineWidth = 0.04 * R; c.scale(0.92, 0.88); almondPath(c, p, sd, R, open); c.stroke(); c.restore(); }
  c.fillStyle = "rgba(255,255,255,.92)"; c.beginPath(); c.arc(-0.32 * w, -0.32 * h, 0.2 * w, 0, TAU); c.fill();
  c.beginPath(); c.arc(0.22 * w, 0.3 * h, 0.09 * w, 0, TAU); c.fill();
  c.restore(); c.strokeStyle = p.liner; c.lineWidth = 0.05 * R; almondPath(c, p, sd, R, open); c.stroke();
}

/** Expression eyes (upstream's shapes), in the cat's ink colour. They are the eyes of every compact cat. */
function inkEye(c: Ctx, shape: EyeShape, sd: number, w: number, h: number, open: number, T: number, col: string) {
  c.fillStyle = col; c.strokeStyle = col; c.lineCap = "round";
  const pill = (W: number, H: number) => { const hh = Math.max(H * open, 0.3 * W); rr(c, -W / 2, -hh / 2, W, hh, Math.min(W, hh) / 2); c.fill(); };
  const hap = () => { c.lineWidth = 0.5 * w; c.beginPath(); c.arc(0, 0.18 * h, 0.82 * w, 1.12 * Math.PI, 1.88 * Math.PI); c.stroke(); };
  switch (shape) {
    case "pill": case "cup": pill(w, h); break;
    case "wide": pill(w * 1.16, h * 1.12); break;
    case "dot": c.beginPath(); c.arc(0, 0, 0.45 * w, 0, TAU); c.fill(); break;
    case "line": c.rotate(-sd * 0.2); rr(c, -0.78 * w, -0.21 * w, 1.56 * w, 0.42 * w, 0.21 * w); c.fill(); break;
    case "flat": rr(c, -0.72 * w, -0.2 * w, 1.44 * w, 0.4 * w, 0.2 * w); c.fill(); break;
    case "happy": hap(); break;
    case "closed": c.lineWidth = 0.36 * w; c.beginPath(); c.arc(0, -0.08 * h, 0.78 * w, 0.15 * Math.PI, 0.85 * Math.PI); c.stroke(); break;
    case "spiral": {
      c.lineWidth = 0.22 * w; c.rotate(T * 9 * sd); c.beginPath();
      for (let a = 0; a < 4.4 * Math.PI; a += 0.2) { const r = 0.06 * w + 0.058 * w * a, x = Math.cos(a) * r, y = Math.sin(a) * r; a ? c.lineTo(x, y) : c.moveTo(x, y); }
      c.stroke(); break;
    }
    case "heart": c.fillStyle = "#FF4D6D"; heartP(c, 1.2 * w); break;
    case "star": c.fillStyle = "#F7B32B"; c.rotate(T * 1.5 * sd); starP(c, 1.05 * w, 0.46 * w); break;
    case "tired": rr(c, -w / 2, -0.02 * h, w, 0.38 * h, Math.min(w, 0.38 * h) / 2); c.fill(); rr(c, -0.62 * w, -0.12 * h - 0.11 * w, 1.24 * w, 0.22 * w, 0.11 * w); c.fill(); break;
    case "wink": if (sd < 0) pill(w, h); else hap(); break;
  }
}
const REAL: ReadonlySet<EyeShape> = new Set<EyeShape>(["pill", "wide", "dot", "tired"]);

// ── Paws, badge, particles, mouth, hairballs, files ───────────────────────────

export function drawPaw(c: Ctx, p: CatPreset, R: number, q: PawSpec) {
  const k = q.k, w = 0.2 * R * k, h = 0.18 * R * k;
  if (w < 0.6) return;
  c.save(); c.translate(q.x, q.y); c.rotate(q.rot || 0);
  const toes = [-1, 0, 1].map((i) => [i * w * 0.55, -h * 0.62]);
  c.fillStyle = p.paw; c.strokeStyle = "rgba(0,0,0,.28)"; c.lineWidth = Math.max(0.6, 0.012 * R);
  c.beginPath();
  for (const [x, y] of toes) { c.moveTo(x + w * 0.36, y); c.ellipse(x, y, w * 0.36, h * 0.38, 0, 0, TAU); }
  c.moveTo(w, 0); c.ellipse(0, 0, w, h * 0.85, 0, 0, TAU); c.stroke(); c.fill();
  if (q.beans) {
    c.fillStyle = p.bean; c.beginPath(); c.ellipse(0, h * 0.12, w * 0.42, h * 0.32, 0, 0, TAU); c.fill();
    for (const [x, y] of toes) { c.beginPath(); c.ellipse(x, y + h * 0.02, w * 0.16, h * 0.17, 0, 0, TAU); c.fill(); }
  } else {
    c.strokeStyle = "rgba(0,0,0,.25)";
    for (const s of [-1, 1]) { c.beginPath(); c.moveTo(s * w * 0.28, -h * 0.85); c.lineTo(s * w * 0.24, -h * 0.35); c.stroke(); }
  }
  c.restore();
}

/** Paw positions for the engine's wave (upstream greet timings), head-local. */
export function enginePaws(e: CatView, rx: number, ry: number): PawSpec[] {
  const s = e.s;
  if (s.paws <= 0.01) return [];
  const n = e.now(), bodyH = 2 * ry, waving = e.waveStart > 0 && n >= e.waveStart && n < e.waveUntil, out: PawSpec[] = [];
  for (const sd of [-1, 1]) {
    let x = sd * rx * 1.0, y = ry * 0.78, rot = 0, beans = false;
    if (sd > 0 && waving) {
      const wt = (n - e.waveStart) / 1000, rise = EZ.out(Math.min(1, wt / 0.18));
      x = lerp(x, rx * 1.12 + Math.cos(13 * wt) * 0.06 * bodyH, rise);
      y = lerp(y, -ry * 0.12 - Math.sin(13 * wt) * 0.12 * bodyH, rise);
      rot = (0.35 + Math.sin(13 * wt) * 0.3) * rise;
      beans = rise > 0.5;
    } else if (sd < 0 && waving) y += Math.sin((6 * (n - e.waveStart)) / 1000) * 0.04 * bodyH;
    out.push({ x, y, k: s.paws, rot, beans });
  }
  return out;
}

function drawBadge(c: Ctx, kind: BadgeKind, col: string, x: number, y: number, R: number, k: number, small: boolean, T: number) {
  c.save(); c.translate(x, y); c.scale(k, k);
  if (kind === "dots" && small) {
    const r = R * 0.22 * (1 + 0.25 * Math.sin(((T * 2.4) % 1) * TAU));
    c.fillStyle = "#000"; c.beginPath(); c.arc(0, 0, R * 0.26, 0, TAU); c.fill(); c.fillStyle = col; c.beginPath(); c.arc(0, 0, r, 0, TAU); c.fill();
  } else if (kind === "dots") {
    c.fillStyle = col; rr(c, -0.36 * R, -0.18 * R, 0.72 * R, 0.36 * R, 0.18 * R); c.fill(); c.fillStyle = "#fff";
    for (let i = 0; i < 3; i++) {
      const ph = (((2.4 * T - 0.22 * i) % 1) + 1) % 1, r = 0.055 * R * (1 + 0.4 * Math.max(0, Math.sin(TAU * ph)));
      c.beginPath(); c.arc((i - 1) * 0.18 * R, 0, r, 0, TAU); c.fill();
    }
  } else if (kind === "bang" || kind === "question") {
    c.fillStyle = "#000"; c.beginPath(); c.arc(0, 0, 0.3 * R, 0, TAU); c.fill(); c.fillStyle = col; c.beginPath(); c.arc(0, 0, 0.23 * R, 0, TAU); c.fill();
    if (!small) {
      c.fillStyle = "#fff"; c.font = `900 ${0.32 * R}px system-ui,sans-serif`; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText(kind === "bang" ? "!" : "?", 0, 0.02 * R);
    }
  } else {
    c.fillStyle = "#000"; c.beginPath(); c.arc(0, 0, 0.2 * R, 0, TAU); c.fill(); c.fillStyle = col; c.beginPath(); c.arc(0, 0, 0.135 * R, 0, TAU); c.fill();
  }
  c.restore();
}

function drawParticles(c: Ctx, e: CatView, cx: number, cy: number, R: number) {
  for (const p of e.parts) {
    if (p.age < 0) continue;
    const k = p.age / p.life, al = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8;
    const x = cx + (p.x + p.vx * p.age) * R * 1.3, y = cy + (p.y + p.vy * p.age) * R * 1.3, sz = R * p.size * (1 + 0.4 * k);
    c.save(); c.globalAlpha = Math.max(0, al); c.translate(x, y);
    switch (p.k) {
      case "heart": c.rotate(Math.sin(6 * p.age) * 0.3); c.fillStyle = "#FF4D6D"; heartP(c, sz * 1.6); break;
      case "star": c.rotate(p.rot + 2 * p.age); c.fillStyle = "#F7B32B"; starP(c, sz, sz * 0.45); break;
      case "spark": c.rotate(p.rot); c.fillStyle = "#fff"; starP(c, sz * 0.8, sz * 0.18); break;
      case "sweat": c.fillStyle = "#7CC7FF"; c.beginPath(); c.moveTo(0, -sz); c.quadraticCurveTo(sz * 0.8, sz * 0.3, 0, sz * 0.8); c.quadraticCurveTo(-sz * 0.8, sz * 0.3, 0, -sz); c.fill(); break;
      case "dust": c.fillStyle = "rgba(225,225,232,.55)"; c.beginPath(); c.arc(0, 0, sz * (0.6 + k * 0.9), 0, TAU); c.fill(); break;
      case "hair": c.rotate(p.rot + p.age * 1.5); c.strokeStyle = e.p.hairLight; c.lineWidth = Math.max(0.6, R * 0.014); c.lineCap = "round"; c.beginPath(); c.moveTo(-sz * 0.6, 0); c.quadraticCurveTo(0, -sz * 0.5, sz * 0.6, 0); c.stroke(); break;
      case "z": c.fillStyle = "rgb(209,219,235)"; c.font = `700 ${1.9 * sz}px system-ui,sans-serif`; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText("z", 0, 0); break;
    }
    c.restore();
  }
}

/**
 * Mouth: a closed ω that can smile, frown, skew or wobble, with an optional tongue blep,
 * or an open mouth that runs from a wide D (meow, hiss, yawn) to a round 'o'.
 */
function drawMouth(c: Ctx, p: CatPreset, s: Pose, R: number, nx: number, my: number, nf: number, full: boolean, mo: number, T: number) {
  const sm = clamp(s.smile, -1, 1), sk = clamp(s.mskew, -1, 1), tg = clamp(s.tongue, 0, 1), rd = clamp(s.mround, 0, 1), wv = clamp(s.wavy, 0, 1);
  const y0 = my + 0.05 * R, cxm = nx + sk * 0.035 * R * nf, lw = 0.03 * R;
  c.lineCap = "round"; c.lineJoin = "round";
  if (mo > 0.04) {
    const m = Math.min(mo, 1.3), w = 0.13 * R * (0.6 + 0.4 * m) * (1 - 0.45 * rd) * (1 + 0.25 * Math.max(0, sm)) * nf, h = 0.21 * R * m * (1 - 0.3 * rd) + 0.012 * R, top = y0 - 0.012 * R;
    // The opening hangs under the ω upper lip; as it rounds into an 'o' the lip lifts into the top of the ring.
    const L = 0.055 * R * (1 - rd), ty = top - h * 0.35 * rd, cty = top - h * 0.3 * rd + L, bot = top + h * (1.15 + 0.15 * rd) + L * 0.5;
    const lip = () => { c.moveTo(cxm - w, top); c.quadraticCurveTo(cxm - w * 0.5, cty, cxm, ty); c.quadraticCurveTo(cxm + w * 0.5, cty, cxm + w, top); };
    const path = () => { c.beginPath(); lip(); c.bezierCurveTo(cxm + w, bot, cxm - w, bot, cxm - w, top); c.closePath(); };
    c.fillStyle = "#3A1218"; path(); c.fill();
    c.save(); path(); c.clip(); c.fillStyle = "#E8798C"; c.beginPath(); c.ellipse(cxm, top + h * 0.95, w * 0.62, h * 0.34, 0, 0, TAU); c.fill(); c.restore();
    if (m > 0.45 && rd < 0.5 && full) {
      c.fillStyle = "#FBF7F0";
      for (const sd of [-1, 1]) { const fx = cxm + sd * w * 0.55, fy = top + L * 0.55; c.beginPath(); c.moveTo(fx - 0.022 * R, fy); c.lineTo(fx + 0.022 * R, fy); c.lineTo(fx, fy + 0.055 * R); c.closePath(); c.fill(); }
    }
    if (tg > 0.05) {
      const tl = (0.03 + 0.07 * tg) * R, tw = Math.max(w * 0.5, 0.05 * R * nf), ty2 = top + h * 0.9;
      c.fillStyle = "#E8798C"; c.beginPath(); c.moveTo(cxm - tw, top + h * 0.7); c.lineTo(cxm - tw, ty2 + tl * 0.4); c.quadraticCurveTo(cxm - tw, ty2 + tl * 1.2, cxm, ty2 + tl * 1.2);
      c.quadraticCurveTo(cxm + tw, ty2 + tl * 1.2, cxm + tw, ty2 + tl * 0.4); c.lineTo(cxm + tw, top + h * 0.7); c.closePath(); c.fill();
      if (full) { c.strokeStyle = "rgba(150,50,70,.6)"; c.lineWidth = lw * 0.6; c.beginPath(); c.moveTo(cxm, top + h * 0.95); c.lineTo(cxm, ty2 + tl * 0.9); c.stroke(); }
    }
    if (full) {
      c.strokeStyle = p.mouthLine; c.lineWidth = lw; c.beginPath(); c.moveTo(nx, my); c.lineTo(cxm, ty); c.stroke();
      const a0 = c.globalAlpha; c.globalAlpha = a0 * (1 - rd); c.beginPath(); lip(); c.stroke(); c.globalAlpha = a0;
    }
    return;
  }
  if (!full) return;
  if (tg > 0.03) {
    const th = (0.025 + 0.045 * tg) * R;
    c.fillStyle = "#E8798C"; c.beginPath(); c.ellipse(cxm, y0 + 0.035 * R + th * 0.5, 0.042 * R * nf, th, 0, 0, TAU); c.fill();
    c.strokeStyle = "rgba(150,50,70,.55)"; c.lineWidth = lw * 0.5; c.beginPath(); c.moveTo(cxm, y0 + 0.04 * R); c.lineTo(cxm, y0 + 0.035 * R + th * 0.9); c.stroke();
  }
  const mw = 0.15 * R * nf * (1 + 0.18 * Math.max(0, sm));
  c.strokeStyle = p.mouthLine; c.lineWidth = lw; c.beginPath(); c.moveTo(nx, my); c.lineTo(cxm, y0);
  if (wv > 0.05) {
    c.moveTo(cxm - mw, y0 + 0.03 * R);
    for (let i = 1; i <= 24; i++) { const t = i / 24; c.lineTo(cxm - mw + 2 * mw * t, y0 + 0.03 * R + Math.sin(t * TAU * 2.5 + T * 6) * 0.022 * R * wv); }
  } else {
    const lobe = 0.08 * R * (1 - 0.6 * Math.max(0, -sm)), cL = y0 - sm * 0.05 * R - sk * 0.035 * R, cR = y0 - sm * 0.05 * R + sk * 0.035 * R;
    c.moveTo(cxm - mw, cL); c.quadraticCurveTo(cxm - mw / 2, y0 + lobe, cxm, y0); c.quadraticCurveTo(cxm + mw / 2, y0 + lobe, cxm + mw, cR);
  }
  c.stroke();
}

/** A small file icon with its extension on it: what a refused file looks like inside a hairball, and in flight to the mouth. */
export function drawFileIcon(c: Ctx, x: number, y: number, s: number, rot: number, ext: string) {
  c.save(); c.translate(x, y); c.rotate(rot);
  const w = s * 0.78, h = s, f = s * 0.24;
  c.fillStyle = "#F4F5F7"; c.beginPath(); c.moveTo(-w / 2, -h / 2); c.lineTo(w / 2 - f, -h / 2); c.lineTo(w / 2, -h / 2 + f); c.lineTo(w / 2, h / 2); c.lineTo(-w / 2, h / 2); c.closePath(); c.fill();
  c.fillStyle = "#C9CDD4"; c.beginPath(); c.moveTo(w / 2 - f, -h / 2); c.lineTo(w / 2 - f, -h / 2 + f); c.lineTo(w / 2, -h / 2 + f); c.closePath(); c.fill();
  c.fillStyle = "#3B9EFF"; rr(c, -w / 2 + s * 0.07, h * 0.06, w - s * 0.14, s * 0.24, s * 0.05); c.fill();
  c.fillStyle = "#fff"; c.font = `700 ${s * 0.15}px system-ui,sans-serif`; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText(ext, 0, h * 0.06 + s * 0.125);
  c.restore();
}

/** Hairballs (and rejected files wrapped in fur) bounce once and roll away. */
function drawBalls(c: Ctx, e: CatView, cx: number, cy: number, R: number) {
  const p = e.p;
  for (const b of e.balls) {
    const a = Math.min(1, (b.life - b.age) / 0.5);
    c.save(); c.translate(cx + b.x * R, cy + b.y * R); c.rotate(b.rot); c.globalAlpha = Math.max(0, a);
    const r = rng(b.seed);
    let fw = 0.17 * R, fh = 0.11 * R;
    if (b.file) { drawFileIcon(c, 0, 0, 0.36 * R, 0, b.file); fw = 0.17 * R; fh = 0.2 * R; }
    else { c.fillStyle = p.hair; c.beginPath(); c.ellipse(0, 0, fw, fh, 0, 0, TAU); c.fill(); }
    c.lineCap = "round"; c.lineWidth = Math.max(0.6, 0.014 * R);
    for (let i = 0; i < (b.file ? 26 : 20); i++) {
      const t = r() * TAU, ex = Math.cos(t) * fw, ey = Math.sin(t) * fh, L = (0.03 + r() * 0.05) * R;
      c.strokeStyle = r() < 0.5 ? p.hairDark : p.hairLight;
      c.beginPath(); c.moveTo(ex * 0.75, ey * 0.75); c.quadraticCurveTo(ex + Math.cos(t + 0.9) * L * 0.6, ey + Math.sin(t + 0.9) * L * 0.6, ex + Math.cos(t + 0.3) * L, ey + Math.sin(t + 0.3) * L); c.stroke();
    }
    if (!b.file) { c.fillStyle = "rgba(255,255,255,.3)"; c.beginPath(); c.ellipse(-fw * 0.3, -fh * 0.4, fw * 0.3, fh * 0.2, -0.3, 0, TAU); c.fill(); }
    c.restore();
  }
}

// ── The cat: a behind pass, the head, a front pass ───────────────────────────

/** Everything one frame of one cat needs, worked out once and shared by the three passes. */
export interface CatFrame {
  e: CatView;
  p: CatPreset;
  /** The pose, with the options' extra squash and tilt applied. */
  s: Pose;
  L: Layout;
  o: DrawOptions;
  /** Seconds. */
  T: number;
  D: number;
  fur: Fur | null;
  /** The compact cat's flat colours (flatFillColors), or null for the full cat: `detailLevel(D, detail).flatFill`, that is `!L.full`. */
  flat: FlatColors | null;
}

/** Works out the frame: the pose, the layout and the fur. Leaves e.base and e.at for the next frame. */
export function frameOf(e: CatView, cx: number, cy: number, D: number, o: DrawOptions = {}): CatFrame {
  const p = e.p, T = e.now() / 1000;
  const s: Pose = o.squash || o.tilt ? { ...e.s, sx: e.s.sx * (o.squash ? o.squash[0] : 1), sy: e.s.sy * (o.squash ? o.squash[1] : 1), tilt: e.s.tilt + (o.tilt || 0) } : e.s;
  const lv = detailLevel(D, o.detail), k0 = lv.full ? 1 : earScale(D); // every compact cat wears the compact ear scale
  const opts = { T, detail: o.detail, badgeSide: o.badgeSide };
  let L = layout(p, s, cx, cy, D, { ...opts, earScale: k0 });
  // In the compact island the top of the strip is the top of the screen: shrink the ears just enough that no tip leaves it, on top of the
  // compact ear scale (earScale(D) * f; A-0b, merged `6adf584`).
  if (o.earCeiling !== undefined) {
    const f = earFit(L, s, o.earCeiling);
    if (f < 1) L = layout(p, s, cx, cy, D, { ...opts, earScale: k0 * f });
  }
  e.base = L.base; e.at = L.at;
  const flat = lv.flatFill ? flatFillColors(p) : null;
  const fur = o.fur && L.full && L.R >= 30 && !p.hairless ? furStrands(p) : null;
  return { e, p, s, L, o, T, D, fur, flat };
}

/** Draws in the head's own frame: its centre, tilt and squash. */
function inHead(c: Ctx, f: CatFrame, draw: () => void) {
  c.save(); c.translate(f.L.head.x, f.L.head.y); c.rotate(f.s.tilt); c.scale(f.s.sx, f.s.sy);
  draw();
  c.restore();
}

/** The behind pass: the glow, the zoomies' afterimages, the ruff and bib, the paws and the ears. */
export function drawBehindPass(c: Ctx, f: CatFrame) {
  const { e, p, L, o, D, fur, flat } = f, { R, full, rx, ry, steps } = L, { x: cx, y: cy } = L.head;
  if (o.glow && e.ga > 0.005) {
    const gr = c.createRadialGradient(cx, cy, 0, cx, cy, R * 2.3), g = e.gc.map(Math.round);
    gr.addColorStop(0, `rgba(${g},${e.ga})`); gr.addColorStop(1, `rgba(${g},0)`); c.fillStyle = gr; c.fillRect(cx - R * 2.4, cy - R * 2.4, R * 4.8, R * 4.8);
  }
  // Zoomies: afterimages and speed lines behind a cat that is moving fast.
  const zv = e.zv || 0;
  if (Math.abs(zv) > 1.1 && D >= 16) {
    const k = Math.min(1, (Math.abs(zv) - 1.1) / 2.5), dir = Math.sign(zv);
    c.save();
    for (let i = 1; i <= 3; i++) { c.globalAlpha = (0.2 * k) / i; c.fillStyle = p.ruff ? p.ruff.col[0] : p.top; c.beginPath(); c.ellipse(cx - dir * i * 0.3 * R * k, cy, rx, ry, 0, 0, TAU); c.fill(); }
    c.globalAlpha = 0.6 * k; c.strokeStyle = "#fff"; c.lineCap = "round"; c.lineWidth = Math.max(1, 0.025 * R);
    for (const [yy, l] of [[-0.5, 0.7], [-0.08, 1], [0.32, 0.8], [0.68, 0.5]]) { const x0 = cx - dir * (rx + 0.15 * R), y = cy + yy * R; c.beginPath(); c.moveTo(x0, y); c.lineTo(x0 - dir * l * 0.75 * R * k, y); c.stroke(); }
    c.restore();
  }
  inHead(c, f, () => {
    // Ruff and neck bib sit behind the head, with a little parallax.
    if (p.ruff) {
      const r = p.ruff;
      c.save(); c.translate(L.ruff.dx, L.ruff.dy);
      const rp = sup(r.rx * R, r.ry * R, 2.4, r.dy * R, 0.06, 18, steps);
      if (flat?.ruff) c.fillStyle = rgbOf(flat.ruff); // below Ø28 the ruff's shading cannot be seen: one flat colour
      else {
        const g = c.createRadialGradient(0, r.dy * R, 0.55 * R, 0, r.dy * R, 1.55 * R);
        g.addColorStop(0, r.col[1]); g.addColorStop(1, r.col[0]); c.fillStyle = g;
      }
      c.fill(rp);
      if (fur) {
        c.save(); c.clip(rp); c.lineCap = "round"; c.lineWidth = Math.max(0.6, 0.012 * R);
        for (const q of fur.ruff) { const x = q.x * R, y = q.y * R, l = q.L * R; c.strokeStyle = q.c; c.beginPath(); c.moveTo(x - q.ux * l * 0.5, y - q.uy * l * 0.5); c.quadraticCurveTo(x - q.uy * l * 0.15, y + q.ux * l * 0.15, x + q.ux * l * 0.5, y + q.uy * l * 0.5); c.stroke(); }
        c.restore();
      }
      const by = (r.ry + r.dy) * R;
      c.fillStyle = p.bib!; c.beginPath(); c.moveTo(-0.2 * R, by * 0.97); c.quadraticCurveTo(-0.12 * R, by * 0.8, 0, by * 0.72); c.quadraticCurveTo(0.12 * R, by * 0.8, 0.2 * R, by * 0.97);
      c.quadraticCurveTo(0.1 * R, by * 1.03, 0.04 * R, by * 0.99); c.lineTo(0, by * 1.06); c.lineTo(-0.04 * R, by * 0.99); c.quadraticCurveTo(-0.1 * R, by * 1.03, -0.2 * R, by * 0.97); c.fill();
      c.restore();
    }
    for (const q of o.paws || enginePaws(e, rx, ry)) drawPaw(c, p, R, q);
    for (const ear of L.ears) drawEar(c, p, ear, R, full, flat);
  });
}

/** The head: its shape, the markings, the state tint, the blush, the eyes, the mouth and the nose, and the rim light. */
export function drawHeadPass(c: Ctx, f: CatFrame) {
  const { e, p, s, L, o, T, fur, flat } = f, { R, full, rx, ry, fa, W, steps } = L;
  inHead(c, f, () => {
    const head = sup(rx, ry, p.n, 0, p.fluff ? 0.035 : 0, 14, steps, L.bend);
    if (flat) c.fillStyle = rgbOf(flat.head); // below Ø28 the coat's top-to-bottom shading cannot be seen: one flat colour
    else {
      const g = c.createLinearGradient(0.45 * rx, -ry, -0.45 * rx, ry);
      g.addColorStop(0, p.top); g.addColorStop(1, p.bot); c.fillStyle = g;
    }
    c.fill(head);
    c.save(); c.clip(head); c.globalAlpha = fa;
    // Markings, warped onto the turning head.
    if (p.coat === "tuxedo") { c.fillStyle = p.white!; c.fill(momoWhite(W)); }
    else if (p.coat === "tabby") {
      const sc = hex(p.stripe!).join(","), [bx, by] = W(0, -0.88);
      if (flat) { const k = FLAT_FILL.crown; c.fillStyle = `rgba(${sc},${k.alpha})`; c.beginPath(); c.ellipse(bx, by, k.rx * R, k.ry * R, 0, 0, TAU); c.fill(); } // the crown band, flat
      else {
        const cb = c.createRadialGradient(bx, by, 0, bx, by, 0.6 * R);
        cb.addColorStop(0, `rgba(${sc},.9)`); cb.addColorStop(1, `rgba(${sc},0)`); c.fillStyle = cb; c.fillRect(-2 * R, -2 * R, 4 * R, 4 * R);
      }
      wStroke(c, W, p.stripe!, (full ? 0.1 : 0.13) * R, [0, -0.95, 0, -0.62, 0, -0.36]);
      if (full) {
        for (const i of [-2, -1, 1, 2]) wStroke(c, W, p.stripe!, 0.042 * R, [i * 0.05, -0.3 + Math.abs(i) * 0.07, i * 0.09, -0.62, i * 0.17, -0.98]);
        for (const sd of [-1, 1]) {
          wStroke(c, W, p.stripe!, 0.04 * R, [sd * 0.62, 0.04, sd * 0.82, -0.02, sd * 1.02, -0.08]);
          wStroke(c, W, p.stripe!, 0.045 * R, [sd * 0.7, 0.3, sd * 0.88, 0.22, sd * 1.1, 0.22]);
          wStroke(c, W, p.stripe!, 0.045 * R, [sd * 0.72, 0.46, sd * 0.9, 0.42, sd * 1.1, 0.46]);
        }
      }
      const ny = -Math.sin(p.nosePh) * p.ry;
      c.fillStyle = p.light!; for (const sd of [-1, 1]) c.fill(wEll(W, sd * 0.17, ny + 0.12, 0.26, 0.21));
      c.fillStyle = p.chinCol!; c.fill(wEll(W, 0, ny + 0.34, 0.22, 0.16));
    } else if (p.coat === "point") {
      const ny = -Math.sin(p.nosePh) * p.ry, [mx, my] = W(0, ny - 0.12), pc = hex(p.point!).join(",");
      if (flat?.point) { const k = FLAT_FILL.point; c.fillStyle = `rgba(${flat.point.map(Math.round)},${k.alpha})`; c.beginPath(); c.ellipse(mx, my, k.rx * R, k.ry * R, 0, 0, TAU); c.fill(); } // the point mask, flat: the contract's 0.86 R by 0.54 R
      else {
        c.save(); c.translate(mx, my); c.scale(1.55, 1);
        const pg = c.createRadialGradient(0, 0, 0.05 * R, 0, 0, 0.66 * R);
        pg.addColorStop(0, `rgba(${pc},.97)`); pg.addColorStop(0.6, `rgba(${pc},.82)`); pg.addColorStop(1, `rgba(${pc},0)`); c.fillStyle = pg; c.fillRect(-2 * R, -2 * R, 4 * R, 4 * R); c.restore();
      }
    } else if (p.coat === "calico") {
      for (const q of p.patches || []) { c.fillStyle = q[5]; c.fill(wBlob(W, q[0], q[1], q[2], q[3], q[4], q[6] || 1)); }
    }
    if (p.muzzle) {
      const ny = -Math.sin(p.nosePh) * p.ry;
      c.fillStyle = p.muzzle; for (const sd of [-1, 1]) c.fill(wEll(W, sd * 0.16, ny + 0.12, 0.24, 0.19));
      c.fill(wEll(W, 0, ny + 0.32, 0.2, 0.14));
    }
    if (p.wrinkles && full) for (const [y, w] of [[-0.42, 0.2], [-0.54, 0.27], [-0.66, 0.18]]) wStroke(c, W, p.bot, 0.026 * R, [-w, y + 0.03, 0, y - 0.05, w, y + 0.03]);
    if (fur) {
      c.lineCap = "round"; c.lineWidth = Math.max(0.5, (p.furOpts || FURDEF).w * R);
      for (const q of fur.head) { const [a, b] = W(q.x, q.y), [c2, d] = W(q.x2, q.y2); c.strokeStyle = q.c; c.beginPath(); c.moveTo(a, b); c.lineTo(c2, d); c.stroke(); }
    }
    c.globalAlpha = 1;
    if (o.tint !== false && s.tint > 0.01) {
      const col = e.col.map(Math.round), lg = c.createLinearGradient(0, ry, 0, -ry * 0.2);
      lg.addColorStop(0, `rgba(${col},${0.4 * s.tint})`); lg.addColorStop(1, `rgba(${col},0)`); c.fillStyle = lg; c.fillRect(-2 * R, -2 * R, 4 * R, 4 * R);
    }
    // A soft edge: a rim light on dark coats, a shadow on the rest. Below Ø28 it would be a few pixels of shading: skipped (FLAT_FILL.rimGradient).
    if (!flat || FLAT_FILL.rimGradient) {
      const rg = c.createRadialGradient(0, 0, 0.2 * R, 0, 0, 1.35 * R);
      rg.addColorStop(0, "rgba(0,0,0,0)"); rg.addColorStop(0.62, "rgba(0,0,0,0)"); rg.addColorStop(1, p.rimLight ? "rgba(255,255,255,.07)" : "rgba(0,0,0,.25)");
      c.fillStyle = rg; c.fillRect(-2 * R, -2 * R, 4 * R, 4 * R);
    }
    const bl = Math.max(s.blush, e.blushBase || 0);
    if (bl > 0.01) { c.fillStyle = `rgba(255,120,150,${0.5 * bl * fa})`; for (const sd of [-1, 1]) c.fill(wEll(W, sd * p.blushAt[0], p.blushAt[1], 0.17, 0.1, 14)); }
    // Eyes on the sphere (upstream projection), normalised so the rest pose matches the board.
    const shape = e.eyeShape(), open = s.open * (1 - s.lid);
    for (const { sd, visible, x: ex, y: ey, fx, fy } of L.eyes) {
      if (!visible) continue;
      c.save(); c.translate(ex, ey); c.scale(fx, fy); c.globalAlpha = fa;
      if (full) {
        if (p.light) { c.save(); c.scale(1.22, 1.3); c.fillStyle = p.light; almondPath(c, p, sd, R, 1); c.fill(); c.restore(); }
        if (REAL.has(shape) || (shape === "wink" && sd < 0)) almondEye(c, s, p, sd, R * s.es * (shape === "wide" ? 1.12 : 1), shape === "dot" ? 1 : s.pupil, shape === "tired" ? Math.min(open, 0.42) : open);
        else inkEye(c, shape, sd, 0.27 * R * s.es, 0.31 * R * s.es, open, T, p.ink);
      } else inkEye(c, shape, sd, 0.34 * R * s.es, 0.4 * R * s.es, open, T, p.ink);
      c.restore();
    }
    // Nose and mouth (open for yawns and the file catch).
    if (L.nose.visible) {
      const { nx, ny, nf, nw, nh, my } = L.nose as Required<typeof L.nose>, mo = e.mouthOpen();
      c.globalAlpha = fa;
      drawMouth(c, p, s, R, nx, my, nf, full, mo, T);
      c.fillStyle = p.nose; c.beginPath(); c.moveTo(nx - nw / 2, ny - nh / 2); c.quadraticCurveTo(nx, ny - nh * 0.8, nx + nw / 2, ny - nh / 2);
      c.quadraticCurveTo(nx + nw * 0.1, ny + nh * 0.6, nx, ny + nh / 2); c.quadraticCurveTo(nx - nw * 0.1, ny + nh * 0.6, nx - nw / 2, ny - nh / 2); c.fill();
      if (full) { c.strokeStyle = p.noseLine; c.lineWidth = 0.02 * R; c.stroke(); }
      e.mouthAt = L.mouth;
    }
    c.globalAlpha = 1; c.restore();
    if (p.rimLight) { c.strokeStyle = "rgba(255,255,255,.22)"; c.lineWidth = Math.max(1, 0.013 * R); c.stroke(head); }
  });
}

/** The front pass: a Scottish Fold's flaps, the whiskers, then the badge, the particles and the hairballs. */
export function drawFrontPass(c: Ctx, f: CatFrame) {
  const { e, p, s, L, o, T, flat } = f, { R, full, yf, fa, W } = L;
  inHead(c, f, () => {
    if (p.ear.fold) for (const ear of L.ears) drawEar(c, p, ear, R, full, flat, true);
    // Whiskers rooted on the pad grid beside the nose, plus eyebrow whiskers.
    if (full && fa > 0.01) {
      const Wk = p.whisk2, rand = rng(29), nzy = -Math.sin(p.nosePh) * p.ry;
      for (const sd of [-1, 1]) {
        const fxs = clamp(Math.cos(yf) + sd * 0.37 * Math.sin(yf), 0.15, 1.3), pts: { row: number; col: number; x: number; y: number }[] = [];
        for (let row = 0; row < Wk.rows; row++) for (let col = 0; col < Wk.cols; col++) pts.push({ row, col, x: sd * (Wk.x0 + col * Wk.dx), y: nzy + Wk.y0 + row * Wk.dy + col * Wk.slope });
        c.fillStyle = p.padDot; c.globalAlpha = fa;
        for (const q of pts) { const [X, Y] = W(q.x, q.y); c.beginPath(); c.arc(X, Y, Wk.dot * R, 0, TAU); c.fill(); }
        c.globalAlpha = 1;
        for (const q of pts) {
          if (!Wk.wcols.includes(q.col)) continue;
          const [X, Y] = W(q.x, q.y), ang = Wk.a0 + q.row * Wk.da + q.col * 0.04 + (rand() - 0.5) * 0.06 - s.wh;
          const l = (Wk.len - q.row * Wk.dl - q.col * 0.05 + (rand() - 0.5) * 0.1) * R, dx = sd * Math.cos(ang) * fxs, dy = Math.sin(ang);
          taper(c, X, Y, X + dx * l * 0.5, Y + dy * l * 0.5 - 0.05 * R, X + dx * l, Y + dy * l + (Wk.droop * l * l) / R, Wk.w * R, p.whisk, Wk.alpha * fa);
        }
        const ex = Math.sin(sd * p.eye.th) * Math.cos(p.eye.ph) * p.rx, ey = -Math.sin(p.eye.ph) * p.ry;
        for (let k = 0; k < Wk.brow; k++) {
          const [bx, by] = W(ex + sd * (k * 0.06 - 0.03), ey - p.eye.h * 1.9 - k * 0.015), th = 1.08 - k * 0.2 - s.wh * 0.5, l = (0.38 + k * 0.08) * R;
          taper(c, bx, by, bx + sd * (Math.cos(th) * l * 0.45 * fxs + 0.07 * R), by - Math.sin(th) * l * 0.55, bx + sd * Math.cos(th) * l * fxs, by - Math.sin(th) * l, Wk.w * 0.7 * R, p.whisk, Wk.alpha * 0.85 * fa);
        }
      }
    }
  });
  if (o.badge !== false && e.badge && s.badgeS > 0.01) drawBadge(c, e.badge, e.badgeCol || COL[e.state], L.badge.x, L.badge.y, R, L.badge.k, L.badge.small, T);
  drawParticles(c, e, L.base.x, L.base.y, R);
  drawBalls(c, e, L.base.x, L.base.y, R);
}

/**
 * Draws one cat: the behind pass, the head, the front pass. D is the head width in CSS px; below Ø28 it uses the
 * compact drawing, with the ears scaled down (earScale) so they keep their headroom in the compact notch.
 * (cx, cy) is the cat's resting centre. The renderer leaves e.base, e.at and e.mouthAt for the next frame.
 * The three passes are exported so outfits (sub-project I) can be drawn between them.
 */
export function drawCat(ctx: Ctx, e: CatView, cx: number, cy: number, D: number, o: DrawOptions = {}) {
  const f = frameOf(e, cx, cy, D, o);
  drawBehindPass(ctx, f);
  drawHeadPass(ctx, f);
  drawFrontPass(ctx, f);
}
```

- [ ] **Step 4: Run the tests and the type check**

Run: `npm run check:cat && npx tsc --noEmit`
Expected: all pass. The renderer test draws every coat and every kitten at Ø12 to Ø66, plain and with fur lines, and a cat turned, rolled and squashed past the normal range, and fails on any NaN; it checks that no gradient is created below Ø28 (flat fills), that the flat colours, the crown band and the point mask are the contract's numbers and colours, that an `earCeiling` keeps the ear tips under the strip and exactly on its margin, and that the compact ear scale and the fit compose (`earScale(D) * f`).

- [ ] **Step 5: Create the contact sheet and mount it**

`dev.ts` is the `?dev` page. This version draws the still sheet: one row per coat, each at Ø12, 16, 20, 24, 28, 44 and 66 and as a kitten at Ø16 and Ø40, the same ladder as the prototype page. The cats are drawn by `stillView`, so they never move, but they turn to follow the pointer through the face warp (the pointer's gaze is set on the pose directly). Create `windows/src/cat/dev.ts`. The `// @@S2-...`, `// @@S3-...` and `// @@S4-...` lines are markers that later tasks insert above; leave them:

```ts title="windows/src/cat/dev.ts"
// The `?dev` page: the cat contact sheet. Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window
// needed) and look at every coat at every size, next to design/prototype/notchmeow.html.
// Only the dev server serves it: main.ts loads this module behind `import.meta.env.DEV`, so a release
// build does not contain it.

import { cursorLook, newPose } from "./geometry.ts";
import { drawCat, stillView } from "./renderer.ts";
import type { CatView } from "./renderer.ts";
import { CAT_IDS, PRESETS, kittenOf } from "./presets.ts";
// @@S2-IMPORT
// @@S3-IMPORT
// @@S4-IMPORT-CATCH
// @@S4-IMPORT-GREETING

const FONT = "system-ui,-apple-system,'Segoe UI',sans-serif";
const BTN = "font:inherit;font-size:12px;color:#ececee;background:#202227;border:1px solid #2a2c31;border-radius:8px;padding:4px 10px;cursor:pointer";

/** The ladder: head widths from the mini pills to the expanded island, then two kitten sizes. */
const SIZES = [
  { d: 12, l: "Ø12 mini" }, { d: 16, l: "Ø16" }, { d: 20, l: "Ø20 compact" }, { d: 24, l: "Ø24" }, { d: 28, l: "Ø28 full" },
  { d: 44, l: "Ø44" }, { d: 66, l: "Ø66 expanded" }, { d: 16, l: "kitten Ø16", kit: true }, { d: 40, l: "kitten Ø40", kit: true },
];
const slotW = (d: number) => Math.max(62, d * 2.2);
const LW = SIZES.reduce((a, z) => a + slotW(z.d), 0) + 24;
const ROWH = 150;

interface Cell { d: number; l: string; v: CatView }
interface Row { id: string; cells: Cell[] }

function rr(c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  c.beginPath(); c.roundRect(x, y, w, h, r);
}

/** A canvas sized for the screen's pixel ratio; returns its 2D context ready to draw in CSS px. */
function fit(cv: HTMLCanvasElement, w: number, h: number): CanvasRenderingContext2D {
  const dpr = Math.min(2, devicePixelRatio || 1);
  if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
  cv.style.width = `${w}px`; cv.style.height = `${h}px`;
  const c = cv.getContext("2d")!;
  c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, w, h);
  return c;
}

// @@S2-HELPERS

export function mountDev(root: HTMLElement): void {
  document.title = "NotchMeow cat sheet";
  Object.assign(document.body.style, { background: "#0f1012", overflow: "auto", height: "auto", userSelect: "text", cursor: "auto" });
  Object.assign(root.style, { position: "static", inset: "auto", padding: "20px 16px 56px", font: `14px/1.5 ${FONT}`, color: "#ececee" });

  const head = document.createElement("div");
  head.innerHTML = `<h1 style="font-size:22px;font-weight:600;margin:0 0 4px">NotchMeow cat sheet</h1>
    <p style="color:#9a9ca3;margin:0 0 14px">Every coat at every size, in the compact and full drawing, with kittens. Move the pointer over the page: the cats turn to follow it.
    Ears are scaled to 0.8 at Ø20 and below (provisional) and below Ø28 the fills are flat (no gradients): the prototype page draws both the same way (A-0b).</p>`;
  const bar = document.createElement("div");
  bar.style.cssText = "display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:14px";
  const state = { fur: false, tint: true };
  const toggle = (label: string, on: boolean, set: (v: boolean) => void) => {
    const b = document.createElement("button");
    b.style.cssText = BTN;
    const sync = () => { b.textContent = `${label}: ${on ? "on" : "off"}`; b.style.borderColor = on ? "#5EEAD4" : "#2a2c31"; };
    b.onclick = () => { on = !on; set(on); sync(); };
    sync();
    bar.append(b);
  };
  toggle("Fur lines", state.fur, (v) => (state.fur = v));
  toggle("State tint", state.tint, (v) => (state.tint = v));
  root.append(head, bar);

  let mx: number | null = null, my = 0;
  document.addEventListener("pointermove", (ev) => { mx = ev.clientX; my = ev.clientY; });
  document.documentElement.addEventListener("mouseleave", () => { mx = null; });
  /** The pointer's gaze from a point on the page, -1…1, or rest when the pointer is off the page. */
  const gazeFrom = (px: number, py: number) => (mx === null ? { x: 0, y: 0 } : cursorLook(mx - px, my - py));
  const ticks: (() => void)[] = [];
  // @@S2-REBUILD
  /** The drawing time of the still sheet and of the live cats, in ms per frame, smoothed. */
  let sheetMs = 0, liveMs = 0;

  // ── The ladder, one row per coat ──
  const rows: Row[] = CAT_IDS.map((id) => ({
    id,
    cells: SIZES.map((z) => ({ ...z, v: stillView(z.kit ? kittenOf(PRESETS[id]) : PRESETS[id], newPose()) })),
  }));
  const wrap = document.createElement("div");
  wrap.style.cssText = "overflow-x:auto;padding-bottom:4px";
  const lad = document.createElement("canvas");
  lad.setAttribute("aria-label", "Every coat at every size");
  lad.style.display = "block";
  wrap.append(lad);
  root.append(wrap);

  function drawLadder() {
    const c = fit(lad, LW, ROWH * rows.length), box = lad.getBoundingClientRect();
    rows.forEach((r, ri) => {
      const top = ri * ROWH;
      c.fillStyle = "#ececee"; c.font = `600 12px ${FONT}`; c.textAlign = "left"; c.textBaseline = "top"; c.fillText(PRESETS[r.id].label + (PRESETS[r.id].desc ? ` · ${PRESETS[r.id].desc}` : ""), 12, top + 4);
      let x = 12;
      for (const cell of r.cells) {
        const w = slotW(cell.d), cx = x + w / 2, cy = top + 20 + ROWH * 0.42;
        if (cell.l === "kitten Ø16") { c.strokeStyle = "#2a2c31"; c.beginPath(); c.moveTo(x, top + 26); c.lineTo(x, top + ROWH - 14); c.stroke(); }
        c.fillStyle = "#000"; rr(c, x + 4, top + 22, w - 8, ROWH - 46, 10); c.fill();
        // The cat looks at the pointer (no smoothing: these are stills).
        const g = gazeFrom(box.left + cx, box.top + cy);
        cell.v.s.yaw = g.x * 0.62; cell.v.s.pitch = g.y * 0.5;
        drawCat(c, cell.v, cx, cy, cell.d, { tint: state.tint, fur: state.fur && cell.d >= 60 });
        c.fillStyle = "#9a9ca3"; c.font = `11px ${FONT}`; c.textAlign = "center"; c.textBaseline = "alphabetic"; c.fillText(cell.l, cx, top + ROWH - 8);
        x += w;
      }
    });
  }
  ticks.push(drawLadder);

  // @@S2-PANEL
  // @@S3-PANEL
  // @@S4-GREETING-PANEL

  const frame = () => {
    const t0 = performance.now();
    ticks[0]();
    const t1 = performance.now();
    for (let i = 1; i < ticks.length; i++) ticks[i]();
    sheetMs += (t1 - t0 - sheetMs) * 0.05;
    liveMs += (performance.now() - t1 - liveMs) * 0.05;
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}
```

In `windows/src/main.ts`, replace:

```ts title="windows/src/main.ts" old
  const root = document.getElementById("root");
  if (!root) return;
```

with:

```ts title="windows/src/main.ts" new
  const root = document.getElementById("root");
  if (!root) return;

  // `/?dev` is the cat contact sheet. The dev server only: a release build does not contain it.
  if (import.meta.env.DEV && new URLSearchParams(location.search).has("dev")) {
    const { mountDev } = await import("./cat/dev");
    mountDev(root);
    return;
  }
```

Run: `npx tsc --noEmit`
Expected: no output.

- [ ] **Step 6: Look at it, next to the prototype**

There are no pixel tests: the look is checked by eye. Serve the front end with Vite alone (no Tauri window) and the prototype page from its folder (a browser blocks `file:` URLs in `playwright-cli`; pick a free port if 8791 is taken), then screenshot both. Keep the screenshots under a scratch folder, never in the repository.

```bash
mkdir -p "${TMPDIR:-/tmp}/a-tauri-shots" && WT="$(git rev-parse --show-toplevel)"; cd "${TMPDIR:-/tmp}/a-tauri-shots"
(cd "$WT/windows" && npx vite > vite.log 2>&1 &)                       # http://127.0.0.1:1420
(cd "$WT/design/prototype" && python3 -m http.server 8791 --bind 127.0.0.1 > proto.log 2>&1 &)

playwright-cli -s=sheet open "http://127.0.0.1:1420/?dev"
playwright-cli -s=sheet resize 1200 2700
playwright-cli -s=sheet screenshot --filename=sheet-full.png
# the first two rows only (Shrimpy, Momo), at the prototype ladder's scale
playwright-cli -s=sheet run-code "async page => { const b = await page.locator('canvas').last().boundingBox(); await page.screenshot({path: 'sheet-ladder.png', clip: {x: b.x, y: b.y, width: 726, height: 300}}); }"

playwright-cli -s=proto open "http://127.0.0.1:8791/notchmeow.html"
playwright-cli -s=proto resize 1200 1000
playwright-cli -s=proto screenshot "#ladder" --filename=proto-ladder.png
```

Open `sheet-ladder.png` and `proto-ladder.png` (the prototype lists Momo, then Shrimpy) and compare them by eye, size by size: head shape, ear shape and tilt, eye colour, nose, markings (Momo's blaze, Shrimpy's "M" and crown band), whiskers at Ø28 and up, and the compact drawing below Ø28. Then open `sheet-full.png` and check all 16 coats: no cat is cut off, no eye or nose is missing, the kittens are rounder with bigger eyes and ears, and Latte, Cloud, Button, Puff and Noodle (the coats with their own ears, folds and ruffs) look like the prototype's "More cats" panel (`playwright-cli -s=proto screenshot "#more"`).

There is no intended difference: the prototype page draws the compact ear scale (0.8 at Ø20 and below), the flat fills below Ø28 (one colour for head, ears and ruff; no rim gradient; a flat crown band and point mask) and the ear fit too (A-0b, merged `6adf584`), so the sheet and the page should match at every size. If anything differs, fix `renderer.ts` until it matches, then run `npm run check:cat` again. When done:

```bash
playwright-cli close-all
kill $(lsof -ti tcp:1420) $(lsof -ti tcp:8791)
```

- [ ] **Step 7: Commit**

```bash
git add windows/src/cat/renderer.ts windows/src/cat/dev.ts windows/src/main.ts windows/scripts/cat-tests/fake-canvas.mjs windows/scripts/cat-tests/renderer.test.mjs
git commit -m "feat(cat): the renderer and the ?dev contact sheet

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Checkpoint 1: the owner looks at the contact sheet

**Owner checkpoint** (the executing session; no agent). Stage 1 is done when the owner says so.

- [ ] Send the owner, in the chat, `sheet-full.png` (every coat at every size) **next to** `proto-ladder.png` and `proto-more.png` (the prototype's size ladder and its "More cats" panel: `playwright-cli -s=proto screenshot "#more" --filename=proto-more.png`), with three lines of text: the sheet is the `?dev` page (`npx vite`, then `http://127.0.0.1:1420/?dev`); the compact ear scale of 0.8 at Ø20 is **provisional**, and the prototype page applies the same scale, the same flat fills below Ø28 and the same ear fit (A-0b, merged `6adf584`), so there should be no visible difference; and Shrimpy and Momo are the first two rows.
- [ ] Wait for the owner's OK. **If the owner wants another ear scale, this session stops** (this plan never edits `cat-core.js`): report the new value to the main session. The main session changes `COMPACT_EAR_SCALE` once in `design/prototype/cat-core.js`, runs `node scripts/gen-cat-fixtures.mjs` and commits both on `notchmeow/rebrand`. Then, in this worktree: `git merge notchmeow/rebrand`, set the same number in `COMPACT_EAR_SCALE` in `windows/src/cat/geometry.ts` (the geometry check fails until it matches the fixture), run `npm run check:cat`, and send the owner a new sheet. If the owner finds a look problem, fix `renderer.ts` and send a new screenshot. Do not start Task 5 before the OK.


---

# Stage 2: the 11 states in both motion styles, with gaze and face warp

### Task 5: Personality

**Agent:** `nm-implementer-light`.

**Files:**
- Create: `windows/src/cat/personality.ts`
- Test: `windows/scripts/cat-tests/personality.test.mjs`

This is pulled forward from stage 3 because the engine's per-frame targets read the personality's multipliers; stage 3 adds what the personality does *in motion* (idle habits and the poke reaction).

**Interfaces:**
- Consumes: `clamp`, `own`, `tm` from `base.ts`; `Persona`, `Traits` from `types.ts`; fixture `personality-cases.json`.
- Produces `src/cat/personality.ts`: `TRAITS` (key, label, low end, high end, for Settings' six sliders), `TRAIT_KEYS`, `PERSONAS` (`balanced`, `chill`, `grumpy`, `sweet`, `hyper`, `chatty`), `normPers(traits)` (held to 0 to 1, missing or non-numeric is 0.5), `persMultipliers(traits)` (`speed`, `hop`, `blinkEvery`, `gaze`, `earFlickEvery`, `chatter`, `slowBlinkEvery` multipliers; `pupil`, `smile`, `skew`, `blush`, `lid`, `earBack` offsets; `idle: {yawn, zoomies, mew, purr, hmph, wink}`; `poke: "love" | "annoyed"`; `pokeHiss`), `type Multipliers`, `personaNamed(name): Persona` (an unknown name is Balanced), `slide(persona, trait, value): Persona` (moving a slider makes the preset `custom`; an unknown trait or a bad value changes nothing).

- [ ] **Step 1: Write the failing test**

Create `windows/scripts/cat-tests/personality.test.mjs`:

```js title="windows/scripts/cat-tests/personality.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import { PERSONAS, TRAITS, TRAIT_KEYS, normPers, persMultipliers, personaNamed, slide } from "../../src/cat/personality.ts";
import { finite, load, same } from "./util.mjs";

const fx = load("personality-cases.json");

test("the six presets and the six trait labels are the fixture's", () => {
  same(PERSONAS, fx.presets, "presets");
  same(TRAITS.map(([key, label, low, high]) => ({ key, label, low, high })), fx.traits, "traits");
  assert.deepEqual(Object.keys(PERSONAS), ["balanced", "chill", "grumpy", "sweet", "hyper", "chatty"]);
});

test("traits to multipliers and idle habits, thresholds and hand-edited values included, are the fixture's", () => {
  for (const c of fx.cases) same(persMultipliers(c.traits), c.out, c.name);
});

test("Balanced changes nothing", () => {
  const m = persMultipliers(PERSONAS.balanced);
  assert.deepEqual([m.speed, m.hop, m.blinkEvery, m.gaze, m.earFlickEvery, m.chatter, m.slowBlinkEvery], [1, 1, 1, 1, 1, 1, 1]);
  assert.deepEqual([m.pupil, m.smile, m.skew, m.blush, m.lid, m.earBack], [0, 0, 0, 0, 0, 0]);
  assert.deepEqual(Object.values(m.idle), [false, false, false, false, false, false]);
  assert.equal(m.poke, "annoyed");
});

test("moving a slider makes the preset Custom, an unknown preset is Balanced, nothing throws", () => {
  for (const c of fx.slide) same(slide(personaNamed(c.from), c.trait, c.value), c.out, `${c.from} ${c.trait}`);
  assert.equal(personaNamed("nonsense").preset, "balanced");
  assert.equal(personaNamed("toString").preset, "balanced");
  assert.equal(slide(personaNamed("chill"), "sass", NaN).preset, "chill");
});

test("a hand-edited personality is held to 0..1: missing counts as 0.5, wrong types too, nothing is NaN", () => {
  assert.deepEqual(normPers({}), { energy: 0.5, curiosity: 0.5, chatty: 0.5, affection: 0.5, sass: 0.5, mischief: 0.5 });
  assert.deepEqual(normPers(null), normPers(undefined));
  const bad = normPers({ energy: "high", curiosity: null, chatty: true, affection: [1], sass: {}, mischief: "0.9" });
  assert.deepEqual(Object.values(bad), [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]);
  assert.equal(normPers({ energy: 7 }).energy, 1);
  assert.equal(normPers({ energy: -7 }).energy, 0);
  assert.equal(normPers({ energy: NaN }).energy, 0.5);
  for (const t of [{ energy: -9, sass: 99 }, null, { chatty: Infinity }]) finite(persMultipliers(t), "multipliers");
  assert.deepEqual([...TRAIT_KEYS], ["energy", "curiosity", "chatty", "affection", "sass", "mischief"]);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npm run check:cat`
Expected: FAIL. `personality.test.mjs` cannot load `src/cat/personality.ts` (`ERR_MODULE_NOT_FOUND`).

- [ ] **Step 3: Create the personality module**

Create `windows/src/cat/personality.ts`:

```ts title="windows/src/cat/personality.ts"
// Personality: six traits, 0 to 1, that bend the behaviour a cat already has. 0.5 is neutral, so the
// Balanced preset is exactly the approved motion. Any coat can wear any personality.
// A port of the personality section of design/prototype/cat-core.js, the tie-breaker.
// Imports only base.ts, so the plain-Node checks (npm run check:cat) can load it.

import { clamp, own, tm } from "./base.ts";
import type { Persona, Traits } from "./types.ts";

export type TraitKey = keyof Traits;

/** key, label, low end, high end: what Settings shows for each slider. */
export const TRAITS: readonly (readonly [TraitKey, string, string, string])[] = [
  ["energy", "Energy", "sleepy", "bouncy"],
  ["curiosity", "Curiosity", "aloof", "nosy"],
  ["chatty", "Chattiness", "quiet", "talkative"],
  ["affection", "Affection", "independent", "cuddly"],
  ["sass", "Sass", "easy-going", "grumpy"],
  ["mischief", "Mischief", "well-behaved", "troublemaker"],
];

export const PERSONAS: Record<string, Traits & { label: string }> = {
  balanced: { label: "Balanced", energy: 0.5, curiosity: 0.5, chatty: 0.5, affection: 0.5, sass: 0.5, mischief: 0.5 },
  chill: { label: "Chill", energy: 0.12, curiosity: 0.35, chatty: 0.3, affection: 0.65, sass: 0.3, mischief: 0.2 },
  grumpy: { label: "Grumpy", energy: 0.4, curiosity: 0.3, chatty: 0.45, affection: 0.15, sass: 0.95, mischief: 0.3 },
  sweet: { label: "Sweet", energy: 0.5, curiosity: 0.55, chatty: 0.55, affection: 1, sass: 0.1, mischief: 0.3 },
  hyper: { label: "Hyper", energy: 1, curiosity: 0.9, chatty: 0.75, affection: 0.5, sass: 0.3, mischief: 1 },
  chatty: { label: "Chatty", energy: 0.6, curiosity: 0.7, chatty: 1, affection: 0.6, sass: 0.35, mischief: 0.5 },
};
export const TRAIT_KEYS: readonly TraitKey[] = TRAITS.map((t) => t[0]);

/** Traits as stored: a missing, non-numeric or NaN trait becomes 0.5, anything else is held to 0…1 (a settings file can be hand-edited). */
export function normPers(P: Partial<Record<TraitKey, unknown>> | null | undefined): Traits {
  const o = {} as Traits;
  for (const k of TRAIT_KEYS) {
    const raw = P ? P[k] : undefined;
    const v = typeof raw === "number" && Number.isFinite(raw) ? raw : 0.5;
    o[k] = clamp(v, 0, 1);
  }
  return o;
}

/**
 * What a personality changes, as numbers. The engine reads only these.
 *   speed, hop, blinkEvery, gaze, earFlickEvery, chatter, slowBlinkEvery are multipliers (1 at neutral);
 *   pupil, smile, skew, blush, lid and earBack are added to the resting pose (0 at neutral);
 *   idle says which idle habits are on; poke is the reaction to a poke; pokeHiss adds a hiss to it.
 */
export function persMultipliers(P0: Partial<Record<TraitKey, unknown>> | null | undefined) {
  const P = normPers(P0), energy = P.energy, sass = P.sass, aff = P.affection;
  return {
    speed: tm(energy, 0.55, 1.5), hop: tm(energy, 0.45, 1.4), blinkEvery: tm(energy, 1.4, 0.75), pupil: (energy - 0.5) * 0.3,
    lid: Math.max(Math.max(0, 0.5 - energy), Math.max(0, sass - 0.55) * 0.55),
    gaze: tm(P.curiosity, 0.35, 1.2), earFlickEvery: tm(P.curiosity, 1.6, 0.6), chatter: tm(P.chatty, 0.3, 1.4),
    smile: (aff - 0.5) * 0.5 - Math.max(0, sass - 0.5) * 1.1, blush: Math.max(0, aff - 0.6) * 0.9, slowBlinkEvery: tm(aff, 1.6, 0.5),
    skew: Math.max(0, sass - 0.5) * 0.9, earBack: Math.max(0, sass - 0.55) * 0.45,
    idle: { yawn: energy < 0.3, zoomies: P.mischief > 0.75 && energy > 0.7, mew: P.chatty > 0.7, purr: aff > 0.75, hmph: sass > 0.75, wink: P.mischief > 0.65 },
    poke: aff > 0.75 && sass < 0.4 ? ("love" as const) : ("annoyed" as const), pokeHiss: sass > 0.7,
  };
}
export type Multipliers = ReturnType<typeof persMultipliers>;

/** A preset as a cat stores it: its name plus the six traits. An unknown name gives Balanced. */
export function personaNamed(name: string): Persona {
  const k = own(PERSONAS, name) ? name : "balanced";
  const { label: _label, ...traits } = PERSONAS[k];
  return { preset: k, ...traits };
}

/** Moving a slider: the new value (held to 0…1) and the preset becomes 'custom'. An unknown trait or a bad value changes nothing. */
export function slide(pers: Persona, trait: string, value: number): Persona {
  return (TRAIT_KEYS as readonly string[]).includes(trait) && typeof value === "number" && Number.isFinite(value)
    ? { ...pers, [trait]: clamp(value, 0, 1), preset: "custom" }
    : { ...pers };
}
```

- [ ] **Step 4: Run the tests and the type check**

Run: `npm run check:cat && npx tsc --noEmit`
Expected: all pass. The personality test covers the six presets, 32 trait cases (thresholds and out-of-range, missing and wrong-typed values included) and the `slide` cases.

- [ ] **Step 5: Commit**

```bash
git add windows/src/cat/personality.ts windows/scripts/cat-tests/personality.test.mjs
git commit -m "feat(cat): personality presets and multipliers, tested against personality-cases.json

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The engine and both motion styles: the 11 states

**Agent:** `nm-implementer-light` (hand it to `nm-implementer-deep` if a fixture check fails and the difference is not a typo; the order of the `rand()` calls matters).

**Files:**
- Create: `windows/src/cat/motion/classic.ts`, `windows/src/cat/motion/playful.ts`
- Replace: `windows/src/cat/engine.ts` (the old character's engine; the island, the views and the mini cats keep working)
- Test: `windows/scripts/cat-tests/engine-util.mjs`, `windows/scripts/cat-tests/engine.test.mjs`

**Interfaces:**
- Consumes: everything from Tasks 1 to 5; `Sound` from `core/sound.ts` (a no-op outside a browser); fixture `motion-cases.json` (`tween`, `rest`, `enters`).
- Produces `src/cat/engine.ts`: `class BotEngine implements CatView` built as `new BotEngine(preset = Shrimpy, options?: EngineOptions)` with `EngineOptions = { mini?, now?, rand?, cfg?, quiet?, state?, log? }`; the shared `catCfg: CatCfg` (`motion`, `override` by cat ID, `pers` by cat ID, `zoomAfter`); `interface MotionProfile`; `type TweenKey`; `hexToRGB(hex): RGB` and `type RGB`; `type EyeShape`. Its members: `state`, `s` (the pose), `tg` (the targets), `setState(state, force?)` (an unknown state is ignored), `anim`, `later`, `ov`, `mpose`, `blink`, `twitch`, `emit`, `setBadge`, `slap`, `interruptGreet`, `computeTargets(tMs, tSeconds)`, `update(dt)` (`dt` held to 0..0.25 s), `eyeShape()`, `mouthOpen()`, `busy`, `draw(ctx, W, H)`, and the old character's members `isMini`, `bodyColor`, `particleOverhang`, `lookX`, `lookY`, `tgEs`, `slotH`/`slotHTarget`/`slotHVel`, `onDizzy`, `permanentEye`, `eyeOverride`/`eyeOverrideUntil`, `triggerEmote`, `gulp`, `animateMorph`/`resetMorph` (no-ops until stage 7 removes their callers), `setPermanentEmote`, `morph` (0), plus `badgeLeft` and `earRoom` (the room above the cat's centre up to the top of the island while the island is the compact strip, otherwise `null`: `draw` fits the ears under it).
- Produces `src/cat/motion/classic.ts` (`CLASSIC`) and `motion/playful.ts` (`PLAYFUL`), both `MotionProfile`s: `{ key, label, eye(state), enter(c, state, prev), targets(c, state, T, tg) → [yaw, pitch], post(c, state, T, kG), ambient(c, t), squash }`.
- Produces `scripts/cat-tests/engine-util.mjs`: `makeEngine(preset, { profile, pers, seed, quiet, state, log, zoomAfter })` returning `{ e, clock, step(frame) }` (the fixtures' harness), `rowOf(e, columns)`, `sample(...)`, `frameMs(f)`.
- Room for the desktop cat and the wardrobe (sub-projects H and I), as the spec asks: the renderer leaves the head centre and size on the engine (`engine.at`, `engine.base`), `lookX`/`lookY` are kept, the paws are a pass of their own (`enginePaws`, `DrawOptions.paws`), and the three drawing passes are separate. The Windows engine has no `dance` member today (the Apple Music bounce is macOS only), so none is kept.
- The engine's `// @@S3-...` and `// @@S4-...` marker lines are where Tasks 8 and 10 insert; leave them. At this stage `triggerEmote` only changes the eyes, `slap` only squashes and flashes the line eyes, and `gulp` is a squash: the emotes, the poke reaction and the catch arrive in stages 3 and 4.

- [ ] **Step 1: Write the failing tests**

Create `windows/scripts/cat-tests/engine-util.mjs`:

```js title="windows/scripts/cat-tests/engine-util.mjs"
// Builds an engine the way the fixtures were generated (docs/CAT-CONTRACT.md, "The harness"): a fake clock that
// starts at 0, a seeded rand, R = 1 so that a hairball lands in units of R, and one update per frame at 60 fps.
import { BotEngine } from "../../src/cat/engine.ts";
import { layout } from "../../src/cat/geometry.ts";
import { ZOOM_AFTER_MS, rng } from "../../src/cat/base.ts";

export const FPS = 60;
/** The time of frame f in ms. A fixture row's `tMs` is this, stored to 12 digits (so it can be off by up to 5e-9): rows are matched by `f`, never by `tMs`. */
export const frameMs = (f) => (f * 1000) / FPS;

export function makeEngine(preset, { profile = "playful", pers = {}, seed = 1, quiet = true, state = "idle", log = null, zoomAfter = ZOOM_AFTER_MS } = {}) {
  const clock = { t: 0 };
  const cfg = { motion: profile, override: {}, pers, zoomAfter };
  const e = new BotEngine(preset, { now: () => clock.t, rand: rng(seed), cfg, quiet, state, log });
  const L = layout(preset, e.s, 0, 0, 2 * preset.rx);
  e.base = L.base;
  e.mouthAt = L.mouth;
  return { e, clock, step: (f) => { clock.t = frameMs(f); e.update(1 / FPS); } };
}

/** One fixture row: mouth openness, spring, chew, particle and ball counts, the first ball, then the pose in the fixture's column order. */
export const rowOf = (e, columns) => [
  e.mouthOpen(), e.slotH, e.chew, e.parts.length, e.balls.length, e.balls[0] ? e.balls[0].x : 0, e.balls[0] ? e.balls[0].y : 0,
  ...columns.slice(7).map((k) => e.s[k]),
];

/** Runs from frame 0, calls `start(e)` there, and returns one { f, eye, v } per sample frame. */
export function sample(preset, opts, start, frames, columns) {
  const { e, step } = makeEngine(preset, opts);
  start(e);
  const rows = [], last = frames[frames.length - 1];
  for (let f = 0; f <= last; f++) {
    if (f > 0) step(f);
    if (frames.includes(f)) rows.push({ f, eye: e.eyeShape(), v: rowOf(e, columns) });
  }
  return rows;
}
```

Create `windows/scripts/cat-tests/engine.test.mjs`:

```js title="windows/scripts/cat-tests/engine.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import { BotEngine, catCfg, hexToRGB } from "../../src/cat/engine.ts";
import { BADGE, COL, GLOW, STATES, TINT } from "../../src/cat/base.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { finite, load, near, same } from "./util.mjs";
import { frameMs, makeEngine, sample } from "./engine-util.mjs";

const fx = load("motion-cases.json");
const { columns } = fx;
const frames = fx.clock.sampleFrames;

test("a tween eases through its keys exactly as the fixture says", () => {
  for (const c of fx.tween) {
    const { e, step } = makeEngine(PRESETS.momo);
    assert.equal(e.s[c.prop], c.from);
    e.anim(c.prop, c.keys);
    const got = [];
    for (let f = 0; f <= c.values[c.values.length - 1][0]; f++) { if (f > 0) step(f); if (c.values.some((v) => v[0] === f)) got.push([f, e.s[c.prop]]); }
    same(got, c.values, `${c.prop} tween`);
  }
});

test("every state at rest, in both motion styles, is the fixture's: eye, tint, badge, mouth, ears, pupil, lid", () => {
  for (const r of fx.rest) {
    const { e } = makeEngine(PRESETS.momo, { profile: r.profile, state: r.state });
    e.lookX = r.look[0];
    e.lookY = r.look[1];
    e.computeTargets(r.T * 1000, r.T);
    const got = { profile: r.profile, state: r.state, T: r.T, look: r.look, eye: e.prof.eye(r.state), tint: TINT[r.state], badge: BADGE[r.state] ?? null, color: COL[r.state], glow: GLOW[r.state] ?? null, mfx: e.mfx, blushBase: e.blushBase, targets: { ...e.tg } };
    same(got, r, `${r.profile} ${r.state} T=${r.T} look=${r.look}`);
  }
});

// Playful's error hiss ends in a hairball (stage 4). Until BotEngine has one, its rows after the hiss are not the fixture's.
const hasHairball = typeof BotEngine.prototype.hairball === "function";
const skipped = (r) => !hasHairball && r.profile === "playful" && r.state === "error" && r.f > 54;

test("entering each state, then 3 s of frames, is the fixture's pose frame by frame", () => {
  for (const profile of ["playful", "classic"]) for (const state of STATES) {
    const want = fx.enters.filter((r) => r.profile === profile && r.state === state);
    assert.equal(want.length, frames.length);
    const got = sample(PRESETS.momo, { profile }, (e) => e.setState(state), frames, columns);
    got.forEach((g, i) => {
      if (skipped(want[i])) return;
      assert.equal(g.eye, want[i].eye, `${profile} ${state} f${g.f}: eye`);
      same(g.v, want[i].v, `${profile} ${state} f${g.f}`);
    });
  }
});

test("the engine keeps the old character's members: setState, blink, slap, gulp, update, draw, busy, isMini, bodyColor, lookX/Y, tgEs, slotH*, onDizzy", () => {
  const e = new BotEngine();
  assert.equal(e.p.name, "shrimpy", "the default cat is Shrimpy");
  for (const m of ["setState", "triggerEmote", "slap", "blink", "gulp", "update", "draw", "animateMorph", "resetMorph", "setPermanentEmote"]) assert.equal(typeof e[m], "function", m);
  assert.deepEqual([e.isMini, e.bodyColor, e.lookX, e.lookY, e.slotH, e.slotHTarget, e.slotHVel, e.morph, e.onDizzy, e.particleOverhang, e.earRoom], [false, null, 0, 0, 0, 0, 0, 0, null, 0, null]);
  assert.deepEqual(hexToRGB("#FF8000"), [1, 128 / 255, 0]);
  e.tgEs = 1.08;
  e.computeTargets(0, 0);
  assert.equal(e.tg.es, 1.08, "the hover size is kept, not reset each frame");
  e.tgEs = 1;
  e.computeTargets(0, 0);
  assert.equal(e.tg.es, 1);
  e.slotHTarget = 0.4;
  assert.equal(e.slotT, 0.4);
  e.isMini = true;
  assert.equal(e.isMini, true);
});

test("three slaps inside 1.7 s call onDizzy and the island takes over; with nobody listening the cat goes dizzy itself", () => {
  const { e } = makeEngine(PRESETS.momo);
  let rang = 0;
  e.onDizzy = () => { rang++; };
  e.slap(); e.slap();
  assert.equal(rang, 0);
  e.slap();
  assert.equal(rang, 1);
  assert.equal(e.state, "idle", "the island sets the state, not the engine");
  const lone = makeEngine(PRESETS.momo);
  lone.e.slap(); lone.e.slap(); lone.e.slap();
  assert.equal(lone.e.state, "dizzy");
  for (let f = 1; f <= 60 * 4; f++) lone.step(f);
  assert.equal(lone.e.state, "idle", "back to where it was after 3.3 s");
});

test("slaps spread over more than 1.7 s never add up", () => {
  const { e, clock } = makeEngine(PRESETS.momo);
  let rang = 0;
  e.onDizzy = () => { rang++; };
  for (const t of [0, 1000, 2000, 3000, 4000]) { clock.t = t; e.slap(); }
  assert.equal(rang, 0);
});

test("an unknown state is ignored, an unknown motion style plays Playful, nothing throws", () => {
  const { e } = makeEngine(PRESETS.momo);
  for (const bad of ["", "nope", "toString", "__proto__", "Idle"]) { e.setState(bad); assert.equal(e.state, "idle", bad); }
  e.cfg.override.momo = "disco";
  assert.equal(e.motion, "playful");
  e.cfg.override.momo = "classic";
  assert.equal(e.motion, "classic");
  e.cfg.override.momo = null;
  e.cfg.motion = "also nonsense";
  assert.equal(e.motion, "playful");
  assert.equal(catCfg.motion, "playful", "the shared default is Playful");
});

test("a bad frame time (zero, negative, NaN, huge) keeps the pose finite and holds dt to 0..0.25 s", () => {
  for (const state of STATES) for (const dt of [0, -1, NaN, Infinity, 1e9, 0.016]) {
    const { e, clock } = makeEngine(PRESETS.shrimpy, { state, quiet: false, seed: 5 });
    for (let i = 1; i <= 10; i++) { clock.t += 100; e.update(dt); }
    finite(e.s, `${state} dt=${dt}`);
    finite(e.tg, `${state} dt=${dt}`);
  }
  const a = makeEngine(PRESETS.momo), b = makeEngine(PRESETS.momo);
  a.e.setState("working"); b.e.setState("working");
  a.clock.t = 500; b.clock.t = 500;
  a.e.update(1e9); b.e.update(0.25);
  same(a.e.s, JSON.parse(JSON.stringify(b.e.s)), "a huge dt is the same as 0.25");
});

test("a slow frame is several spring steps: the mouth stays finite and settles, one step at 60 fps, six steps for 0.1 s (a port note)", () => {
  // The mouth spring blows up in a single explicit step of 0.066 s or more (docs/CAT-CONTRACT.md). Even at the slowest frame the engine allows it must settle.
  const slow = makeEngine(PRESETS.momo);
  slow.e.slotHTarget = 1.05;
  for (let i = 1; i <= 40; i++) { slow.clock.t = i * 250; slow.e.update(0.25); }
  assert.ok(Number.isFinite(slow.e.slotH) && Number.isFinite(slow.e.slotHVel), "finite");
  assert.ok(Math.abs(slow.e.slotH - 1.05) < 0.01, `settled at the target, not ${slow.e.slotH}`);
  // At 60 fps (or faster) it is exactly one step, as the fixtures were made: from rest, H = (ω₀² · target / 60) / 60.
  const one = makeEngine(PRESETS.momo), om = (2 * Math.PI) / 0.25;
  one.e.slotHTarget = 0.55;
  one.e.update(1 / 60);
  near(one.e.slotH, (om * om * 0.55) / 3600, 1e-12);
  // A frame of 0.1 s is six steps of 1/60 s.
  const a = makeEngine(PRESETS.momo), b = makeEngine(PRESETS.momo);
  a.e.slotHTarget = 0.55; b.e.slotHTarget = 0.55;
  a.e.update(0.1);
  for (let i = 0; i < 6; i++) b.e.update(1 / 60);
  near(a.e.slotH, b.e.slotH, 1e-9);
  near(a.e.slotHVel, b.e.slotHVel, 1e-7);
});

test("the frame's clock is an injected one: a fixed clock gives the same pose twice", () => {
  const run = () => { const { e, step } = makeEngine(PRESETS.shrimpy, { state: "searching", quiet: false, seed: 9 }); for (let f = 1; f <= 120; f++) step(f); return JSON.stringify(e.s); };
  assert.equal(run(), run());
  near(frameMs(60), 1000);
});

test("a visible island keeps drawing: a cat that is not quiet is always busy, a quiet one rests", () => {
  const live = new BotEngine(PRESETS.momo, { now: () => 0, rand: () => 0.5 });
  assert.equal(live.busy, true);
  const { e, step } = makeEngine(PRESETS.momo);
  for (let f = 1; f <= 120; f++) step(f);
  assert.equal(e.busy, false, "settled and quiet");
  e.blink();
  assert.equal(e.busy, true, "a tween is running");
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `npm run check:cat`
Expected: FAIL. `engine.test.mjs` cannot load: `src/cat/engine.ts` is still the old character's (it imports `../core/anim` with no extension and has no `catCfg`), so Node stops with an import error.

- [ ] **Step 3: Create the two motion styles**

Create `windows/src/cat/motion/classic.ts`:

```ts title="windows/src/cat/motion/classic.ts"
// Classic motion: upstream's timings 1:1, with the cat's face on the same body language.
// A port of CLASSIC in design/prototype/cat-core.js, the tie-breaker.
// Imports only types from the engine, so there is no import cycle at run time.

import { TAU } from "../base.ts";
import type { StateName } from "../base.ts";
import type { BotEngine, MotionProfile } from "../engine.ts";
import type { EyeShape, Targets } from "../types.ts";

/** Eye shape and head tilt of each state at rest. */
const REST: Record<StateName, readonly [EyeShape, number]> = {
  idle: ["pill", 0], working: ["pill", 0], thinking: ["pill", 0], searching: ["pill", 0], approval: ["wide", 0],
  question: ["pill", 0.17], error: ["flat", 0], finished: ["happy", 0], ratelimit: ["tired", 0], sleeping: ["closed", 0], dizzy: ["spiral", 0],
};

export const CLASSIC: MotionProfile = {
  key: "classic",
  label: "Classic",
  eye: (st) => REST[st][0],
  enter(c: BotEngine, st: StateName, prev: StateName) {
    const a = c.anim.bind(c);
    switch (st) {
      case "idle": if (prev !== "idle") c.blink(); break;
      case "approval": a("oy", [[-0.2, 150, "out"], [0, 300, "back"]]); break;
      case "error": a("ox", [[0.08, 50, "out"], [-0.08, 70, "inOut"], [0.05, 70, "inOut"], [0, 90, "out"]]); break;
      case "finished": a("roll", [[TAU, 950, "inOut"]], () => { c.s.roll = 0; }); c.later(500, () => c.emit("spark", 5), "st"); break;
      case "ratelimit": c.emit("sweat", 1); break;
      case "dizzy": a("roll", [[2 * TAU, 1300, "inOut"]], () => { c.s.roll = 0; }); break;
      default: c.blink();
    }
  },
  targets(c: BotEngine, st: StateName, T: number, tg: Targets): [number, number] {
    tg.tilt = REST[st][1]; tg.earL = 0; tg.earR = 0; tg.earU = 1; tg.earF = 0; tg.pupil = 0.45; tg.oy = 0;
    let ty = c.lookX * 0.62, tp = c.lookY * 0.5;
    if (st === "thinking") { ty = ty * 0.35 + 0.55 * 0.55; tp = tp * 0.3 + 0.55 * 0.5; }
    if (st === "sleeping") { ty = 0; tp = -0.14; tg.sy = 1 + 0.035 * Math.sin(1.8 * T); tg.sx = 1 - 0.035 * 0.57 * Math.sin(1.8 * T); }
    if (st === "searching") { ty = Math.sin(2.6 * T) * 0.6; tp = -0.06; }
    if (st === "dizzy") ty = Math.sin(9 * T) * 0.25;
    if (st === "approval") tg.oy = -Math.abs(Math.sin(5.2 * T)) * 0.07;
    return [ty, tp];
  },
  post(c: BotEngine, _st: StateName, _T: number, kG: number) {
    if (!c.tw.ox) c.s.ox += (0 - c.s.ox) * kG;
  },
  ambient(c: BotEngine, t: number) {
    if (t < c.nextAmb) return;
    if (c.state === "sleeping") c.emit("z", 1);
    if (c.state === "ratelimit" && !c.isMini && c.rand() < 0.5) c.emit("sweat", 1);
    c.nextAmb = t + 1300;
  },
  squash: [0.78, 1.16],
  // @@S3-EMOTE
};
```

Create `windows/src/cat/motion/playful.ts`:

```ts title="windows/src/cat/motion/playful.ts"
// Playful motion: cat body language on top of the same engine (hops, ear flicks, bleps, hisses, zoomies).
// A port of PLAYFUL in design/prototype/cat-core.js, the tie-breaker.
// Imports only types from the engine, so there is no import cycle at run time.

import { TAU } from "../base.ts";
// @@S3-IMPORT
import type { StateName } from "../base.ts";
import type { BotEngine, MotionProfile } from "../engine.ts";
import type { EyeShape, Targets } from "../types.ts";

/** Eye, tilt, earL, earR, earU, earF, pupil, oy: the pose of each state at rest. */
const REST: Record<StateName, readonly [EyeShape, number, number, number, number, number, number, number]> = {
  idle: ["pill", 0, 0, 0, 1, 0, 0.45, 0],
  working: ["pill", 0, -0.08, -0.08, 1.1, 0, 0.5, 0],
  thinking: ["pill", 0.14, 0, 0.38, 1, 0, 0.55, 0],
  searching: ["wide", 0, -0.1, -0.1, 1.15, 0, 0.92, 0.05],
  approval: ["wide", 0, -0.12, -0.12, 1.22, 0, 0.75, 0],
  question: ["pill", 0.24, -0.05, 0.5, 1, 0, 0.7, 0],
  error: ["flat", 0, 0, 0, 1, 1, 0.12, 0],
  finished: ["happy", 0, 0.12, 0.12, 1, 0, 0.45, 0],
  ratelimit: ["tired", 0, 0, 0, 0.9, 0.45, 0.4, 0],
  sleeping: ["closed", 0, 0, 0, 1, 0.25, 0.45, 0.08],
  dizzy: ["spiral", 0, 0, 0, 1, 0, 0.45, 0],
};

export const PLAYFUL: MotionProfile = {
  key: "playful",
  label: "Playful",
  eye: (st) => REST[st][0],
  enter(c: BotEngine, st: StateName, prev: StateName) {
    const a = c.anim.bind(c);
    // @@S3-WAKE
    switch (st) {
      case "idle": if (prev !== "idle") c.blink(); break;
      case "working": c.blink(); c.twitch("earL"); c.later(140, () => c.twitch("earR"), "st"); break;
      case "thinking": c.blink(); break;
      case "searching": a("oy", [[0.12, 160, "out"], [0.05, 300, "inOut"]]); break;
      case "approval":
        a("oy", [[0.08, 110, "out"], [-0.26, 170, "out"], [0, 340, "back"]]);
        a("sy", [[0.88, 110, "out"], [1.1, 170, "out"], [1, 340, "back"]]);
        a("sx", [[1.08, 110, "out"], [0.94, 170, "out"], [1, 340, "back"]]);
        a("earU", [[1.4, 140, "out"], [1.22, 300, "inOut"]]);
        break;
      case "question": a("tilt", [[0.3, 220, "out"], [0.24, 300, "inOut"]]); c.blink(); break;
      case "error":
        a("sx", [[1.14, 80, "out"], [1, 450, "inOut"]]); a("sy", [[1.1, 80, "out"], [1, 450, "inOut"]]); a("oy", [[0.07, 80, "out"], [0, 420, "inOut"]]);
        a("earF", [[1, 90, "out"]]); a("wh", [[0.35, 80, "out"], [0, 500, "inOut"]]);
        c.mpose({ mouth: 0.75, smile: -1, mround: 0 }, 650, 80, 220);
        // @@S4-HISS-HAIRBALL
        break;
      case "finished":
        // @@S3-FINISHED-ZOOMIES
        a("tilt", [[0.16, 260, "inOut"], [-0.16, 420, "inOut"], [0.08, 320, "inOut"], [0, 300, "inOut"]]);
        a("blush", [[0.8, 250, "out"], [0.8, 900, "lin"], [0, 500, "inOut"]]);
        c.later(350, () => c.emit("spark", 5), "st");
        break;
      case "ratelimit": c.nextYawn = c.now() + 300; break;
    }
  },
  targets(c: BotEngine, st: StateName, T: number, tg: Targets): [number, number] {
    const r = REST[st];
    tg.tilt = r[1]; tg.earL = r[2]; tg.earR = r[3]; tg.earU = r[4]; tg.earF = r[5]; tg.pupil = r[6]; tg.oy = r[7];
    let ty = c.lookX * 0.62, tp = c.lookY * 0.5;
    if (st === "thinking") { ty = ty * 0.35 - 0.55 * 0.55; tp = tp * 0.3 + 0.55 * 0.5; }
    if (st === "sleeping") { ty = 0; tp = -0.14; tg.sy = 1 + 0.04 * Math.sin(1.2 * T); tg.sx = 1 - 0.04 * 0.57 * Math.sin(1.2 * T); }
    if (st === "searching") { ty = Math.sin(2.2 * T) * 0.55; tg.earL = -0.1 - Math.sin(2.2 * T) * 0.28; tg.earR = -0.1 + Math.sin(2.2 * T) * 0.28; }
    if (st === "dizzy") { ty = Math.sin(3.5 * T) * 0.2; tg.tilt = Math.sin(7 * T) * 0.12; tg.earL = Math.sin(9 * T) * 0.45; tg.earR = -Math.sin(9 * T + 1) * 0.45; }
    if (st === "approval") tg.oy = -Math.pow(Math.max(0, Math.sin((TAU * T) / 1.4)), 4) * 0.09;
    if (st === "working") tg.oy = -Math.pow(Math.abs(Math.sin(Math.PI * 1.6 * T)), 2) * 0.035;
    return [ty, tp];
  },
  post(c: BotEngine, st: StateName, T: number, kG: number) {
    const s = c.s;
    if (!c.tw.ox) {
      if (st === "searching") s.ox = Math.sin(16 * T) * 0.012;
      else if (st === "dizzy") s.ox = Math.cos(7 * T) * 0.07;
      else s.ox += (0 - s.ox) * kG;
    }
    if (st === "dizzy" && !c.tw.oy) s.oy = Math.sin(7 * T) * 0.05;
  },
  ambient(c: BotEngine, t: number) {
    const st = c.state;
    // @@S3-HABITS
    if (st === "sleeping" && t >= c.nextAmb) { c.emit("z", 1); c.nextAmb = t + 1600; }
  },
  squash: [0.86, 1.1],
  // @@S3-EMOTE
};
```

- [ ] **Step 4: Replace the engine**

Overwrite `windows/src/cat/engine.ts`:

```ts title="windows/src/cat/engine.ts"
// The cat engine: the state machine that moves a cat. A port of CatEngine in design/prototype/cat-core.js,
// the tie-breaker, with the same public members as the engine it replaces (the old mochi engine) so the island,
// the views and the mini cats keep working: setState, triggerEmote, slap, blink, gulp, update, draw, busy,
// isMini, bodyColor, lookX and lookY, tgEs, slotH*, onDizzy, hexToRGB and EyeShape.
//
// The engine owns no clock and no random numbers: `now()` (ms) and `rand()` are injected, so a test gives it a fake
// clock and a seeded rng(seed) and gets the same numbers on every platform. The order of the rand() calls is part of
// the contract (docs/CAT-CONTRACT.md): the fixtures pin it.

import { Sound } from "../core/sound.ts";
import { BADGE, COL, EZ, GLOW, MKEYS, MOUTH, TAU, TINT, ZOOM_AFTER_MS, clamp, hex, lerp, mouthFx, own, workClockStep } from "./base.ts";
// @@S3-IMPORT
import type { BadgeKind, EaseName, MouthKey, StateName } from "./base.ts";
import { catById, DEFAULT_CAT } from "./presets.ts";
import { PERSONAS, persMultipliers } from "./personality.ts";
import type { Multipliers } from "./personality.ts";
import { drawCat } from "./renderer.ts";
import type { CatView } from "./renderer.ts";
import { newPose } from "./geometry.ts";
import { CLASSIC } from "./motion/classic.ts";
import { PLAYFUL } from "./motion/playful.ts";
import type { Ball, CatPreset, EyeShape, Particle, ParticleKind, Persona, Pose, PoseKey, Targets } from "./types.ts";

export type { EyeShape } from "./types.ts";

/** Components 0…1, as the island's integration colours use them. */
export type RGB = readonly [number, number, number];

export function hexToRGB(h: string): RGB {
  const v = parseInt(h.replace("#", ""), 16);
  return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
}

/** One step of a tween: the value to reach, how long it takes (ms) and the easing. */
export type TweenKey = readonly [target: number, ms: number, ease: EaseName];
interface Tween { from: number; keys: readonly TweenKey[]; i: number; t0: number; done?: () => void }

/**
 * A motion style. Classic moves 1:1 like upstream; Playful has the cat's body language. Both are tables and small
 * functions over the same engine, so a cat can switch between them live.
 */
export interface MotionProfile {
  key: string;
  label: string;
  /** The eye shape a state shows when nothing overrides it. */
  eye(st: StateName): EyeShape;
  /** What the cat does on entering a state. */
  enter(c: BotEngine, st: StateName, prev: StateName): void;
  /** Fills the pose targets for the state; returns the gaze [yaw, pitch] the face turns toward. */
  targets(c: BotEngine, st: StateName, T: number, tg: Targets): [number, number];
  /** Per-frame motion applied straight to the pose, after the smoothing. */
  post(c: BotEngine, st: StateName, T: number, kG: number): void;
  /** Idle habits and the drifting z's and sweat. */
  ambient(c: BotEngine, t: number): void;
  /** The squash a slap gives: [height, width]. */
  squash: readonly [number, number];
  // @@S3-PROFILE-EMOTE
}

const PROFILES: Record<string, MotionProfile> = { classic: CLASSIC, playful: PLAYFUL };

/**
 * Shared settings every engine reads unless it is given its own: the global motion style, a per-cat motion override
 * (by cat id), a per-cat personality (preset name plus six traits), and how long a run of work earns zoomies (ms).
 */
export interface CatCfg {
  motion: string;
  override: Record<string, string | null | undefined>;
  pers: Record<string, Persona | undefined>;
  zoomAfter: number;
}
export const catCfg: CatCfg = { motion: "playful", override: {}, pers: {}, zoomAfter: ZOOM_AFTER_MS };

export interface EngineOptions {
  /** A mini cat (pills, the compact grid): it wanders with its eyes instead of following the cursor. */
  mini?: boolean;
  /** Milliseconds, default performance.now. */
  now?: () => number;
  /** 0 up to, not including, 1, default Math.random. */
  rand?: () => number;
  /** Default: the shared `catCfg`. */
  cfg?: CatCfg;
  /** Turns off every random idle habit (blinks, ear flicks, bleps, personality), leaving only what is asked for. */
  quiet?: boolean;
  state?: StateName;
  /** Collects [ms, 'name'] for blinks, flicks, bleps, licks, emotes, zoomies and hairballs. */
  log?: [number, string][] | null;
}

const TARGET_KEYS: readonly (keyof Targets)[] = ["tilt", "sx", "sy", "es", "oy", "earL", "earR", "earU", "earF", "pupil", "purr", "lid", ...MKEYS];

export class BotEngine implements CatView {
  readonly p: CatPreset;
  isMini: boolean;
  now: () => number;
  rand: () => number;
  cfg: CatCfg;
  quiet: boolean;
  log: [number, string][] | null;
  s: Pose = newPose();
  tg: Targets = {
    yaw: 0, pitch: 0, tilt: 0, sx: 1, sy: 1, es: 1, oy: 0, earL: 0, earR: 0, earU: 1, earF: 0, pupil: 0.45, purr: 0, lid: 0,
    mouth: 0, smile: 0, tongue: 0, mround: 0, mskew: 0, wavy: 0,
  };
  tw: Partial<Record<PoseKey, Tween>> = {};
  q: { at: number; fn: () => void; tag?: string }[] = [];
  parts: Particle[] = [];
  balls: Ball[] = [];
  col: number[] = hex(COL.idle);
  colT: number[] = hex(COL.idle);
  gc: number[] = [255, 255, 255];
  ga = 0.12;
  state: StateName = "idle";
  badge: BadgeKind | null = null;
  badgeCol: string | null = null;
  eyeOv: EyeShape | null = null;
  eyeUntil = 0;
  bt = 0;
  lookX = 0;
  lookY = 0;
  slaps: number[] = [];
  dizzyUntil = 0;
  saved: StateName | null = null;
  slotH = 0;
  slotT = 0;
  slotV = 0;
  chew = 0;
  chewStart = 0;
  chewUntil = 0;
  catching = false;
  waveStart = 0;
  waveUntil = 0;
  greetTok = 0;
  hbTok = 0;
  zoomTok = 0;
  zoomUntil = 0;
  zv = 0;
  mfx = 0;
  busySince: number | null = null;
  workedFor = 0;
  nextBlink: number;
  nextTw: number;
  nextSB: number;
  nextAmb: number;
  nextYawn = 0;
  nextBlep: number;
  nextPers: number;
  blushBase = 0;
  miniNext = 0;
  miniLook = { x: 0, y: 0 };
  private oxPrev: number | null = null;
  base: CatView["base"] = null;
  at: CatView["at"] = null;
  mouthAt: CatView["mouthAt"] = null;

  // What the island uses and the old engine had; some of it waits for later stages (see the Next plan).
  /** Solid colour of an integration pill or an agent. It becomes the collar in sub-project A's stage 6. */
  bodyColor: RGB | null = null;
  /** Extra canvas height above the cat so hearts can fly out without clipping. */
  particleOverhang = 0;
  /** The eye shape a mini cat keeps (never set today; removed with the other permanent emotes in stage 7). */
  permanentEye: EyeShape | null = null;
  /** True in the compact notch: the badge sits on the left of the head, away from the camera housing. */
  badgeLeft = false;
  /**
   * In the compact strip: the distance in px from the cat's centre up to the top of the island, which is the top of the screen, where an ear is
   * cut off. `draw` passes `cy - earRoom` to `drawCat` as `earCeiling`, so the ears are fitted under it with the contract's `earFit` (A-0b, merged `6adf584`): the room is the app's, the ceiling is the contract's. null everywhere else.
   */
  earRoom: number | null = null;
  /** Fired when three slaps land inside 1.7 s (the island then shows the confused view and recovers). */
  onDizzy: (() => void) | null = null;
  /** The mailbox morph of the old character is gone; kept at 0 until stage 7 removes its callers. */
  readonly morph = 0;
  private esHover = 1;

  constructor(p: CatPreset = catById(DEFAULT_CAT), o: EngineOptions = {}) {
    this.p = p;
    this.isMini = !!o.mini;
    this.now = o.now || (() => performance.now());
    this.rand = o.rand || (() => Math.random());
    this.cfg = o.cfg || catCfg;
    this.quiet = !!o.quiet;
    this.log = o.log || null;
    const t = this.now();
    this.nextBlink = t + this.u(1500, 3500);
    this.nextTw = t + this.u(2000, 5000);
    this.nextSB = t + this.u(6000, 10000);
    this.nextAmb = t + 1300;
    this.nextBlep = t + this.u(5000, 9000);
    this.nextPers = t + this.u(3000, 6000);
    this.setState(o.state || "idle", true);
  }

  /** The motion style in force for this cat: its own override, else the global style; an unknown stored value means Playful. */
  get motion(): string {
    const m = this.cfg.override[this.p.base || this.p.name] || this.cfg.motion;
    return own(PROFILES, m) ? m : "playful";
  }
  get prof(): MotionProfile { return PROFILES[this.motion]; }
  get pers(): Persona | (typeof PERSONAS)[string] { return this.cfg.pers[this.p.base || this.p.name] || PERSONAS.balanced; }
  /** What this cat's personality changes (persMultipliers). */
  pm(): Multipliers { return persMultipliers(this.pers); }
  u(a: number, b: number): number { return a + this.rand() * (b - a); }
  note(ev: string) { if (this.log) this.log.push([Math.round(this.now()), ev]); }
  anim(k: PoseKey, keys: readonly TweenKey[], done?: () => void) { this.tw[k] = { from: this.s[k], keys, i: 0, t0: this.now(), done }; }
  later(d: number, fn: () => void, tag?: string) { this.q.push({ at: this.now() + d, fn, tag }); }
  ov(shape: EyeShape, d: number) { this.eyeOv = shape; this.eyeUntil = this.now() + d; }
  /** Holds a mouth pose for d ms, then eases back to the state's mouth. */
  mpose(v: Partial<Record<MouthKey, number>>, d: number, i = 150, o = 250) {
    for (const k of Object.keys(v) as MouthKey[]) this.anim(k, [[v[k]!, i, "out"], [v[k]!, Math.max(0, d - i - o), "lin"], [this.tg[k], o, "inOut"]]);
  }

  eyeShape(): EyeShape { return this.eyeOv && this.now() < this.eyeUntil ? this.eyeOv : this.prof.eye(this.state); }
  blink() { if (this.tw.open) return; this.note("blink"); this.anim("open", [[0.06, 70, "inOut"], [1, 130, "out"]]); }
  twitch(ear: "earL" | "earR") {
    this.note("twitch:" + ear);
    const b = this.tg[ear];
    this.anim(ear, [[b + 0.5, 60, "out"], [b, 280, "back"]]);
    this.anim("wh", [[0.25, 60, "out"], [0, 300, "inOut"]]);
  }
  emit(k: ParticleKind, n: number) {
    for (let i = 0; i < n; i++) {
      this.parts.push({
        k, x: (this.rand() - 0.5) * 0.9 + (k === "z" ? 0.55 : 0) + this.s.ox / 1.3, y: -0.85 - this.rand() * 0.2 + this.s.oy / 1.3,
        vx: (this.rand() - 0.5) * 0.35 + (k === "z" ? 0.18 : 0), vy: -(0.45 + this.rand() * 0.35), age: -0.14 * i, life: 1.3 + this.rand() * 0.5,
        size: 0.15 + this.rand() * 0.08, rot: this.rand() * 6,
      });
    }
  }
  setBadge(b: BadgeKind | null) {
    const tok = ++this.bt;
    this.anim("badgeS", [[0, 90, "inOut"]]);
    this.later(100, () => { if (tok !== this.bt) return; this.badge = b; if (b) this.anim("badgeS", [[1, 280, "back"]]); });
  }
  /** Moves the cat to a state. An unknown state is ignored. */
  setState(st: StateName | string, force = false) {
    if (!own(COL, st)) return;
    const next = st as StateName;
    if (!force && next === this.state) return;
    const prev = this.state;
    this.state = next;
    this.q = this.q.filter((x) => x.tag !== "st");
    if (next !== "dizzy") this.dizzyUntil = 0;
    this.colT = hex(COL[next]);
    this.s.tint = TINT[next];
    const b = BADGE[next] || null;
    if (b !== this.badge || force) this.setBadge(b);
    for (const k of ["oy", "ox", "roll", "sx", "sy", "tilt", "earF", "earU", "lid", ...MKEYS] as PoseKey[]) delete this.tw[k];
    this.s.roll = 0;
    const wc = workClockStep({ busySince: this.busySince, workedFor: this.workedFor }, next, this.now());
    this.busySince = wc.busySince;
    this.workedFor = wc.workedFor;
    if (this.eyeUntil !== Infinity) this.eyeOv = null;
    this.prof.enter(this, next, prev);
  }
  /** A poke: a squash, and three inside 1.7 s make the cat dizzy. */
  slap() {
    this.interruptGreet();
    const t = this.now();
    this.slaps = this.slaps.filter((x) => t - x < 1700);
    this.slaps.push(t);
    const [a, b] = this.prof.squash;
    this.anim("sy", [[a, 70, "out"], [1.1, 130, "out"], [1, 170, "inOut"]]);
    this.anim("sx", [[b, 70, "out"], [0.95, 130, "out"], [1, 170, "inOut"]]);
    if (this.state === "dizzy") return;
    Sound.play("slap");
    if (this.slaps.length >= 3) {
      this.slaps = [];
      // The island, when it is listening, shows the confused view and puts the cat back itself.
      if (this.onDizzy) { this.onDizzy(); return; }
      this.saved = this.state;
      this.setState("dizzy");
      this.dizzyUntil = t + 3300;
      return;
    }
    this.ov("line", 800);
    this.later(60, () => Sound.play("annoyed"));
  }
  interruptGreet() {
    if (this.s.paws <= 0.01 && this.now() >= this.waveUntil) return;
    this.greetTok++;
    this.waveUntil = 0;
    this.waveStart = 0;
    this.anim("paws", [[0, 150, "inOut"]]);
  }

  // @@S3-METHODS

  // @@S4-METHODS

  /** How open the mouth is right now: the state's mouth plus its motion, or the file-catch spring and chew, whichever is wider. */
  mouthOpen(): number { return Math.max(this.s.mouth + (this.mfx || 0), this.slotH + this.chew); }

  /**
   * Fills `tg`, the targets the pose eases toward, for the current state: the profile's rest pose, the state's mouth,
   * the personality, and the file-catch, wave and zoomies overrides. t is the clock in ms, T the same in seconds.
   * It reads the engine's inputs (state, lookX/lookY, personality) and never the tweens, so fixtures can call it directly.
   */
  computeTargets(t: number, T: number) {
    const tg = this.tg, st = this.state, pf = this.prof;
    tg.sx = 1; tg.sy = 1; tg.es = this.esHover; tg.purr = 0; tg.lid = 0;
    const Mo = MOUTH[st];
    MKEYS.forEach((k, i) => { tg[k] = Mo[i]; });
    this.mfx = mouthFx(st, T);
    let [ty, tp] = pf.targets(this, st, T, tg);
    // Personality: gaze, resting mouth, lids, ears, bounce, pupils, blush and chatter.
    const M = this.pm();
    ty *= M.gaze; tp *= M.gaze;
    tg.smile += M.smile; tg.mskew += M.skew;
    if (st !== "sleeping") tg.lid = Math.max(tg.lid, M.lid);
    tg.earF = Math.max(tg.earF, M.earBack); tg.oy *= M.hop; tg.pupil = clamp(tg.pupil + M.pupil, 0.1, 1);
    this.blushBase = st === "sleeping" ? 0 : M.blush;
    this.mfx *= M.chatter;
    if (this.isMini && !["thinking", "searching", "sleeping", "dizzy"].includes(st)) {
      if (t > this.miniNext) { this.miniLook = { x: this.u(-0.88, 0.88), y: this.u(-0.55, 0.45) }; this.miniNext = t + this.u(500, 2000); }
      ty = this.miniLook.x * 0.62; tp = this.miniLook.y * 0.5;
      tg.sy = 1 + Math.sin(2.2 * T) * 0.04; tg.sx = 1 - Math.sin(2.2 * T) * 0.02;
    }
    if (this.catching) { tg.earU = 1.25; tg.pupil = 0.95; ty *= 0.3; tp = tp * 0.3 + 0.12; }
    if (t > this.waveStart && t < this.waveUntil) { const wt = (t - this.waveStart) / 1000; tg.tilt = -0.06 + Math.sin(TAU * 1.2 * wt) * 0.07; }
    if (t < this.zoomUntil) {
      const zv = this.zv;
      ty = clamp(zv * 0.25, -0.62, 0.62); tp = -0.05; tg.tilt = clamp(zv * 0.05, -0.2, 0.2);
      tg.sx = 1 + Math.min(0.16, Math.abs(zv) * 0.045); tg.sy = 1 - Math.min(0.09, Math.abs(zv) * 0.025);
      tg.oy = -Math.abs(Math.sin(T * TAU * 4.5)) * 0.05 * Math.min(1, Math.abs(zv) / 1.5);
    }
    tg.yaw = ty; tg.pitch = tp;
  }

  /** One frame. dt is seconds; anything outside 0…0.25 (a sleeping laptop, a clock that stepped back, NaN) is held to that range. */
  update(dt: number) {
    dt = Number.isFinite(dt) ? Math.min(Math.max(dt, 0), 0.25) : 0;
    const t = this.now(), T = t / 1000, s = this.s, tg = this.tg, st = this.state, pf = this.prof;
    for (const k of Object.keys(this.tw) as PoseKey[]) {
      const w = this.tw[k]!;
      let el = t - w.t0;
      while (w.i < w.keys.length) {
        const key = w.keys[w.i], d = Math.max(1, key[1]);
        if (el < d) { s[k] = lerp(w.from, key[0], EZ[key[2]](el / d)); break; }
        el -= d; w.t0 += d; w.from = key[0]; s[k] = key[0]; w.i++;
      }
      if (w.i >= w.keys.length) { delete this.tw[k]; if (w.done) w.done(); }
    }
    const v = (s.ox - (this.oxPrev ?? s.ox)) / Math.max(dt, 1e-3);
    this.oxPrev = s.ox;
    this.zv += (v - this.zv) * Math.min(1, dt * 18);
    const due = this.q.filter((x) => x.at <= t);
    this.q = this.q.filter((x) => x.at > t);
    due.forEach((x) => x.fn());
    this.computeTargets(t, T);
    const M = this.pm(), ke = M.speed, kL = 1 - Math.pow(0.0025, dt * ke), kG = 1 - Math.pow(0.0008, dt * ke), kC = 1 - Math.pow(0.002, dt);
    for (const k of ["yaw", "pitch"] as const) if (!this.tw[k]) s[k] += (tg[k] - s[k]) * kL;
    for (const k of TARGET_KEYS) if (!this.tw[k]) s[k] += (tg[k] - s[k]) * kG;
    pf.post(this, st, T, kG);
    const gT = hex(GLOW[st] || "#FFFFFF"), gaT = st === "dizzy" ? 0 : st === "idle" || st === "sleeping" ? 0.12 : 0.42;
    for (let i = 0; i < 3; i++) { this.col[i] += (this.colT[i] - this.col[i]) * kC; this.gc[i] += (gT[i] - this.gc[i]) * kC; }
    this.ga += (gaT - this.ga) * kC;
    if (!this.quiet && t >= this.nextBlink) {
      if (st !== "sleeping" && st !== "dizzy") { this.blink(); if (this.rand() < 0.22) this.later(230, () => this.blink()); }
      this.nextBlink = t + (2200 + this.rand() * 3200) * M.blinkEvery;
    }
    if (this.eyeOv && t > this.eyeUntil) this.eyeOv = null;
    if (!this.quiet) {
      pf.ambient(this, t);
      // @@S3-PERS
    }
    if (this.dizzyUntil && t > this.dizzyUntil) {
      const b = this.saved || "idle";
      this.dizzyUntil = 0;
      this.setState(b, true);
      // @@S3-DIZZY
    }
    for (const p of this.parts) p.age += dt;
    this.parts = this.parts.filter((p) => p.age < p.life);
    for (const b of this.balls) {
      b.age += dt; b.vy += 5.5 * dt; b.x += b.vx * dt; b.y += b.vy * dt;
      if (b.y > b.floor) { b.y = b.floor; if (b.vy > 0.6) { b.vy *= -0.38; b.vx *= 0.7; } else { b.vy = 0; b.vx *= Math.pow(0.2, dt); } }
      b.rot += b.vx * dt * 5;
    }
    this.balls = this.balls.filter((b) => b.age < b.life);
    // Mouth spring, ω₀ = 2π/0.25, ζ = 0.6 (upstream's slot spring). Stepped at most 1/60 s at a time: exactly one step at 60 fps or
    // faster, as upstream, and several on a slow frame, because a single step of about 0.066 s or more diverges to NaN.
    const om = TAU / 0.25;
    for (let r = dt; r > 0; r -= 1 / 60) {
      const h = Math.min(r, 1 / 60), acc = om * om * (this.slotT - this.slotH) - 2 * 0.6 * om * this.slotV;
      this.slotV += acc * h;
      this.slotH = Math.max(0, this.slotH + this.slotV * h);
    }
    this.chew = t >= this.chewStart && t < this.chewUntil ? 0.16 * (0.5 - 0.5 * Math.cos((TAU * 4.2 * (t - this.chewStart)) / 1000)) : 0;
  }

  // ── What the island and the views call ─────────────────────────────────────

  get eyeOverride(): EyeShape | null { return this.eyeOv; }
  set eyeOverride(v: EyeShape | null) { this.eyeOv = v; }
  get eyeOverrideUntil(): number { return this.eyeUntil; }
  set eyeOverrideUntil(v: number) { this.eyeUntil = v; }
  /** The eyes' size while the pointer rests on the cat (the island sets 1.08 and puts 1 back). */
  get tgEs(): number { return this.esHover; }
  set tgEs(v: number) { this.esHover = v; }
  get slotHTarget(): number { return this.slotT; }
  set slotHTarget(v: number) { this.slotT = v; }
  get slotHVel(): number { return this.slotV; }
  set slotHVel(v: number) { this.slotV = v; }

  /** The island's emotes: for now only the eyes (the body language arrives with the emotes). */
  triggerEmote(emote: string, _duration?: number) {
    const e = EMOTE_EYE[emote];
    if (e) this.ov(e, 1800);
  }
  /** The file has been swallowed: a squash and a blink. */
  gulp() {
    this.anim("sy", [[0.78, 80, "out"], [1.18, 130, "out"], [1, 220, "back"]]);
    this.anim("sx", [[1.28, 80, "out"], [0.92, 130, "out"], [1, 220, "back"]]);
    this.blink();
  }
  /** The mailbox morph of the old character is gone. Kept until stage 7 removes its callers in island.ts. */
  animateMorph(_target: number, _durationMs?: number) {}
  resetMorph() {}
  /** Mini cats keep the eye shape they are given. */
  setPermanentEmote(emote: string | null) {
    this.permanentEye = emote ? EMOTE_EYE[emote] ?? null : null;
    if (this.permanentEye) { this.eyeOv = this.permanentEye; this.eyeUntil = Infinity; }
    else if (this.eyeUntil === Infinity) { this.eyeOv = null; this.eyeUntil = 0; }
  }

  /**
   * True while the island must keep drawing frames. A cat that is not quiet always has an idle habit due (a blink,
   * an ear flick), so a visible island keeps animating: the old rule ("an idle cat is still") froze them.
   * The island itself stops the loop while it is hidden.
   */
  get busy(): boolean {
    return !this.quiet || Object.keys(this.tw).length > 0 || this.q.length > 0 || this.parts.length > 0 || this.balls.length > 0 ||
      Math.abs(this.slotT - this.slotH) > 0.001 || Math.abs(this.slotV) > 0.001;
  }

  /**
   * Draws the cat into a canvas of W×H CSS px (the caller has applied the DPR transform): the head is 60 % of the
   * canvas width across, as the old character's body was, centred, with `particleOverhang` of free space above for
   * hearts to fly out of.
   */
  draw(x: CanvasRenderingContext2D, W: number, H: number) {
    const cy = H / 2 + this.particleOverhang / 2;
    drawCat(x, this, W / 2, cy, W * 0.6, { badgeSide: this.badgeLeft ? -1 : 1, earCeiling: this.earRoom === null ? undefined : cy - this.earRoom });
  }
}

/** The eyes an emote shows. */
const EMOTE_EYE: Record<string, EyeShape> = { love: "heart", surprised: "dot", proud: "star", wink: "wink", yawn: "tired", happy: "happy", annoyed: "line" };
```

- [ ] **Step 5: Run the tests and the type checks**

Run: `npm run check:cat && npx tsc --noEmit && npm run check:ai`
Expected: all pass. The engine test checks the tweens, all 110 rest rows, and all 264 rows of "enter each state, then 3 s of frames" against `motion-cases.json`, and the hostile cases (a bad `dt`, a slow frame that the mouth spring must sub-step, an unknown state or motion style, three slaps). `tsc` passing means the island, the views and the mini cats compile against the new engine.

- [ ] **Step 6: Commit**

```bash
git add windows/src/cat windows/scripts/cat-tests
git commit -m "feat(cat): the engine and both motion styles, the 11 states, tested against motion-cases.json

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The island uses the cat (gaze, badge side, ears under the strip) and the States panel

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/island/island.ts`, `windows/src/cat/dev.ts`

**Interfaces:**
- Consumes: `BotEngine` (`lookX`, `lookY`, `badgeLeft`, `draw`, `update`), `cursorLook` from `geometry.ts`, `STATES` from `base.ts`, `PRESETS`/`CAT_IDS` from `presets.ts`.
- Produces: the island's cat follows the pointer with the spec's curve (tanh over 240 px across and 180 px up and down) instead of the old 260/200; its badge sits on the left in the compact notch, and its ears are fitted under the top of the strip there (`engine.earRoom`: its `cy - earRoom` is the `earCeiling` of the contract's `earFit`, A-0b, merged `6adf584`). `dev.ts` gains the `S2-*` blocks: the choice of cat and motion style, 11 live cats, one per state, each drawn through `engine.draw` as the island draws them, and a compact strip (288 by 32, the cat at Ø20) with the ear fit switchable.

- [ ] **Step 1: Point the island's gaze at the spec's curve, the badge at the compact notch, and the ears under the strip**

In `windows/src/island/island.ts`, replace:

```ts title="windows/src/island/island.ts" old
import { BotEngine, hexToRGB } from "../cat/engine";
```

with:

```ts title="windows/src/island/island.ts" new
import { BotEngine, hexToRGB } from "../cat/engine";
import { cursorLook } from "../cat/geometry";
```

Replace:

```ts title="windows/src/island/island.ts" old
    return Math.tanh((State.mouse.x - botScreenX) / 260);
```

with:

```ts title="windows/src/island/island.ts" new
    return cursorLook(State.mouse.x - botScreenX, 0).x;
```

Replace:

```ts title="windows/src/island/island.ts" old
    return -Math.tanh((State.mouse.y - this.botCy.value) / 200);
```

with:

```ts title="windows/src/island/island.ts" new
    return cursorLook(0, State.mouse.y - this.botCy.value).y;
```

Replace:

```ts title="windows/src/island/island.ts" old
    this.engine.particleOverhang = BOT_OVERHANG;
```

with:

```ts title="windows/src/island/island.ts" new
    this.engine.particleOverhang = BOT_OVERHANG;
    this.engine.badgeLeft = State.mode === "compact";
    // The top of the compact strip is the top of the screen, so the ears are fitted under it: the room above the cat's centre is botCy.
    this.engine.earRoom = State.mode === "compact" ? this.botCy.value : null;
```

Run: `npx tsc --noEmit`
Expected: no output.

- [ ] **Step 2: Add the States panel to the contact sheet**

Insert these blocks into `windows/src/cat/dev.ts`, each **above** the marker line named in its heading (the marker stays). They add the imports, the small UI helpers, the rebuild hook and the panel.

Above `// @@S2-IMPORT`:

```ts title="windows/src/cat/dev.ts" above="@@S2-IMPORT"
import { STATES } from "./base.ts";
import type { StateName } from "./base.ts";
import { BotEngine, catCfg } from "./engine.ts";
```

Above `// @@S2-HELPERS`:

```ts title="windows/src/cat/dev.ts" above="@@S2-HELPERS"
function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}

function section(title: string, note: string): HTMLElement {
  const s = document.createElement("section");
  s.style.cssText = "background:#17181b;border:1px solid #2a2c31;border-radius:16px;padding:16px;margin-bottom:20px";
  s.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">${title}</h2><p style="color:#9a9ca3;margin:0 0 12px;font-size:13px">${note}</p>`;
  return s;
}

function row(label: string): HTMLElement {
  const r = document.createElement("div");
  r.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:8px";
  const h = document.createElement("span");
  h.style.cssText = "font-size:12px;color:#9a9ca3;width:72px;flex:none"; h.textContent = label;
  r.append(h);
  return r;
}

/** A group of buttons of which one is on. */
function choice<T>(label: string, items: readonly (readonly [T, string])[], get: () => T, set: (v: T) => void): HTMLElement {
  const r = row(label), bs: [HTMLButtonElement, T][] = [];
  const sync = () => bs.forEach(([b, v]) => { b.style.borderColor = get() === v ? "#5EEAD4" : "#2a2c31"; b.style.color = get() === v ? "#5EEAD4" : "#ececee"; });
  for (const [v, l] of items) { const b = button(l, () => { set(v); sync(); }); bs.push([b, v]); r.append(b); }
  sync();
  return r;
}
```

Above `// @@S2-REBUILD`:

```ts title="windows/src/cat/dev.ts" above="@@S2-REBUILD"
  /** What to redo when the cat or the motion style changes. */
  const rebuilds: (() => void)[] = [];
  const rebuildAll = () => rebuilds.forEach((r) => r());
```

Above `// @@S2-PANEL`:

```ts title="windows/src/cat/dev.ts" above="@@S2-PANEL"
  // ── Stage 2: the 11 states, live, in either motion style ──
  const dev = { cat: "shrimpy", motion: "playful" };
  const statesBox = section("States", "Each cat is a live engine drawn the way the island draws it (engine.draw). Click a cat to poke it; three quick pokes make it dizzy.");
  const strip = document.createElement("div");
  strip.style.cssText = "display:flex;flex-wrap:wrap;gap:10px;margin-top:12px";
  statesBox.append(
    choice("Cat", CAT_IDS.map((id) => [id, PRESETS[id].label] as const), () => dev.cat, (v) => { dev.cat = v; rebuildAll(); }),
    choice("Motion", [["playful", "Playful"], ["classic", "Classic"]] as const, () => dev.motion, (v) => { dev.motion = v; catCfg.motion = v; rebuildAll(); }),
    strip,
  );
  const readout = document.createElement("p");
  readout.style.cssText = "color:#9a9ca3;font-size:12px;margin:10px 0 0";
  statesBox.append(readout);
  root.insertBefore(statesBox, wrap);

  interface Live { st: StateName; e: BotEngine; cv: HTMLCanvasElement }
  let live: Live[] = [];
  function buildStrip() {
    strip.replaceChildren();
    live = STATES.map((st) => {
      const e = new BotEngine(PRESETS[dev.cat], { state: st });
      const fig = document.createElement("figure");
      fig.style.cssText = "margin:0;background:#000;border-radius:12px;padding-bottom:6px;text-align:center";
      const cv = document.createElement("canvas");
      cv.style.cursor = "pointer";
      cv.onpointerdown = () => e.slap();
      const cap = document.createElement("figcaption");
      cap.style.cssText = "font-size:11px;color:#9a9ca3"; cap.textContent = st;
      fig.append(cv, cap); strip.append(fig);
      return { st, e, cv };
    });
  }
  rebuilds.push(buildStrip);
  buildStrip();
  let last = performance.now();
  ticks.push(() => {
    const t0 = performance.now(), dt = Math.min(0.05, (t0 - last) / 1000);
    last = t0;
    for (const { e, cv } of live) {
      const W = 120, H = 130, c = fit(cv, W, H), box = cv.getBoundingClientRect();
      e.particleOverhang = 20;
      const g = gazeFrom(box.left + W / 2, box.top + H / 2 + 10);
      e.lookX = g.x; e.lookY = g.y;
      e.update(dt);
      e.draw(c, W, H);
    }
    readout.textContent = `Drawing per frame: the live cats ${liveMs.toFixed(2)} ms (the budget is 2 ms for twelve small cats plus the big one on a Mac), the still sheet ${sheetMs.toFixed(2)} ms.`;
  });

  // The compact strip: the island's resting strip, 288 by 32, with the cat at Ø20 and 40 px in. The canvas starts at the top of the strip, as the
  // screen starts at the top of the island, so an ear that rises above it is cut off. The ear fit is the contract's (A-0b, merged `6adf584`).
  const notchBox = section("Compact notch", "The island's resting strip (288 by 32, the cat at Ø20, badge on the left). Its top edge is the top of the screen, where an ear is cut off. With the ear fit on, the ears are shrunk just enough to stay under it; switch it off and press the Hop button to see the hop push them out.");
  const notch = { ears: true, state: "approval" as StateName };
  const notchCv = document.createElement("canvas");
  notchCv.id = "notch-strip";
  notchCv.style.cssText = "display:block;margin-top:12px;background:#3a3d44";
  let notchCat = new BotEngine(PRESETS[dev.cat], { state: notch.state });
  notchBox.append(
    choice("State", (["idle", "approval", "working", "finished", "dizzy"] as StateName[]).map((v) => [v, v] as const), () => notch.state, (v) => { notch.state = v; notchCat.setState(v); }),
    choice("Fit ears", [[true, "On"], [false, "Off"]] as const, () => notch.ears, (v) => { notch.ears = v; }),
    (() => {
      // The worst pose the fit is tested with: a high hop, ears up and the head tilted. Held for 1.5 s.
      const r = row("Pose");
      r.append(button("Hop, ears up", () => {
        notchCat.anim("oy", [[-0.3, 120, "out"], [-0.3, 1500, "lin"], [0, 200, "inOut"]]);
        notchCat.anim("earU", [[1.4, 120, "out"], [1.4, 1500, "lin"], [1, 200, "inOut"]]);
        notchCat.anim("tilt", [[0.24, 120, "out"], [0.24, 1500, "lin"], [0, 200, "inOut"]]);
      }));
      return r;
    })(),
    notchCv,
  );
  root.insertBefore(notchBox, wrap);
  rebuilds.push(() => { notchCat = new BotEngine(PRESETS[dev.cat], { state: notch.state }); });
  let notchLast = performance.now();
  ticks.push(() => {
    const now = performance.now(), dt = Math.min(0.05, (now - notchLast) / 1000);
    notchLast = now;
    const c = fit(notchCv, 288, 32);
    c.fillStyle = "#000"; c.beginPath(); c.roundRect(0, 0, 288, 32, [0, 0, 14, 14]); c.fill();
    notchCat.update(dt);
    drawCat(c, notchCat, 40, 16, 20, { badgeSide: -1, earCeiling: notch.ears ? 0 : undefined });
  });
```

Run: `npx tsc --noEmit && npm run check:cat`
Expected: no type errors; the checks still pass.

- [ ] **Step 3: Look at the states, in both motion styles**

Start Vite, open `/?dev`, and screenshot the States panel (11 live cats in a strip), in Playful and then Classic. Check it against the prototype page (`http://127.0.0.1:8791/notchmeow.html`, served as in Task 4): click each state button there and look at its cats.

```bash
WT="$(git rev-parse --show-toplevel)"; cd "${TMPDIR:-/tmp}/a-tauri-shots"
(cd "$WT/windows" && npx vite > vite.log 2>&1 &)
playwright-cli -s=sheet open "http://127.0.0.1:1420/?dev"
playwright-cli -s=sheet resize 1200 1000
playwright-cli -s=sheet screenshot --filename=states-playful.png
playwright-cli -s=sheet click "getByRole('button', { name: 'Classic' })"
playwright-cli -s=sheet screenshot --filename=states-classic.png
```

By eye, for each of the 11 states: the badge (dots, `!`, `?`, a dot) on the right of the head, the state tint, the eye shape (pill, wide, flat, happy, tired, closed, spiral), the head turn (thinking looks up and to one side, searching sweeps), ears (Playful only), the mouth (tongue tip out when working, a frown on error, panting on rate limit), the `z` of sleeping and the dust or hairball after the error hiss (stage 4 adds the hairball). Move the pointer over the page and see the cats turn to follow it. Poke a cat three times: it goes dizzy for 3.3 s, then back.

Then look at the real island, driven by a fake clock so the screenshots are repeatable (the page runs in a plain browser: `IS_TAURI` is false and the page's own pointer drives the island):

```bash
playwright-cli -s=island open about:blank
playwright-cli -s=island run-code "async page => { await page.setViewportSize({width: 720, height: 320}); await page.clock.install(); await page.goto('http://127.0.0.1:1420/'); await page.clock.runFor(7000); await page.screenshot({path: 'island-compact.png'}); await page.mouse.move(360, 14); await page.clock.runFor(300); await page.mouse.down(); await page.mouse.up(); await page.clock.runFor(1800); await page.mouse.move(250, 60); await page.clock.runFor(800); await page.screenshot({path: 'island-expanded.png'}); }"
```

`island-compact.png`: the cat at Ø20 in the compact notch with its ears scaled down and fitted under the strip's top. In the sheet's Compact notch panel, press "Hop, ears up": with Fit ears off the hop pushes the ear tips above the strip, where they are cut off; with it on they stay inside and a calm cat (idle) keeps its full ears (`playwright-cli -s=sheet run-code "async page => { const b = await page.locator('#notch-strip').boundingBox(); await page.screenshot({path: 'notch-fit.png', clip: {x: b.x, y: b.y, width: b.width, height: b.height}}); }"`, once with Fit ears on and once with it off). `island-expanded.png`: the big cat in the overview card and the mini cats in the pills. (The launch greeting at the start is still the old one until Task 11. The agent colours that used to fill the old character come back as collars in the next plan.) Fix `dev.ts` or the wiring if anything is wrong, then:

```bash
playwright-cli close-all
kill $(lsof -ti tcp:1420)
```

- [ ] **Step 4: Commit**

```bash
git add windows/src/island/island.ts windows/src/cat/dev.ts
git commit -m "feat(cat): the island's cat follows the spec's gaze curve, badge side in the compact notch, States panel

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

# Stage 3: emotes and the mouth, the per-state motion, and personality

### Task 8: Emotes, idle habits, zoomies, the paw wave and the poke

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/cat/engine.ts`, `windows/src/cat/motion/playful.ts`, `windows/src/cat/motion/classic.ts` (insert at the markers named below)
- Test: `windows/scripts/cat-tests/emotes.test.mjs`

**Interfaces:**
- Consumes: the engine, profiles and fixtures of Task 6; `EMOUTH` from `base.ts`; `persMultipliers`/`personaNamed` from `personality.ts`; fixtures `motion-cases.json` (`emotes`, `ambient`) and `sequence-cases.json` (`zoomiesAndWake`).
- Produces on `BotEngine`: `emote(name)` (love, surprised, proud, wink, yawn, happy, annoyed, hello, zoomies; an unknown name does nothing), `blep()`, `lick()`, `slowBlink()`, `persAmbient(t)` (the idle habits that come from personality), `zoomies()`, `dust(dir)`, `greet()` (the paw wave: the `hello` emote); `triggerEmote(name, _duration?)` now plays the emote (and the `annoyed` sound); `slap()` now reacts by personality (annoyed by default, `love` from a cuddly cat, a hiss from a grumpy one); the dizzy recovery ends with a happy emote. `MotionProfile` gains `emote(c, name)`.
- Playful's `enter` starts zoomies on waking from sleep and on finishing after 5 minutes of work; its `ambient` adds the idle bleps and licks, ear flicks, slow blinks and the rate-limit yawn. The six mouth values are driven by `EMOUTH` poses (shared by both motion styles), the per-state rest mouth and `mouthFx` (the renderer has drawn them since Task 4).
- The hairball and the `catch*` methods are stage 4: `emote("hairball")` is not handled yet, and the checks skip the hairball rows until `BotEngine` has one.

- [ ] **Step 1: Write the failing test**

Create `windows/scripts/cat-tests/emotes.test.mjs`:

```js title="windows/scripts/cat-tests/emotes.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import { BotEngine } from "../../src/cat/engine.ts";
import { ZOOM_AFTER_MS, rng } from "../../src/cat/base.ts";
import { layout } from "../../src/cat/geometry.ts";
import { PERSONAS, personaNamed } from "../../src/cat/personality.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { finite, load, same } from "./util.mjs";
import { makeEngine, sample } from "./engine-util.mjs";

const fx = load("motion-cases.json");
const seq = load("sequence-cases.json");
const { columns } = fx;
const frames = fx.clock.sampleFrames;

// The hairball is stage 4's: until BotEngine has one its rows are not checked (catch.test.mjs checks them after).
const hasHairball = typeof BotEngine.prototype.hairball === "function";
const HAIRBALL_LATER = (r) => !hasHairball && r.emote === "hairball";

test("every emote, in both motion styles, is the fixture's pose frame by frame (eyes, ears, body and the six mouth values)", () => {
  assert.ok(fx.emotes.length > 200);
  for (const r of fx.emotes) {
    if (HAIRBALL_LATER(r)) continue;
    const got = sample(PRESETS[r.cat], { profile: r.profile }, (e) => e.emote(r.emote), [r.f], columns)[0];
    assert.equal(got.eye, r.eye, `${r.profile} ${r.emote} f${r.f}: eye`);
    same(got.v, r.v, `${r.profile} ${r.emote} f${r.f}`);
  }
});

test("45 seconds of idle habits (blinks, ear flicks, bleps, yawns, purrs...) for each personality are the fixture's, in order", () => {
  for (const a of fx.ambient) {
    const log = [];
    const { step } = makeEngine(PRESETS.momo, { profile: a.profile, quiet: false, seed: a.seed, log, pers: { momo: personaNamed(a.persona) } });
    for (let f = 1; f <= a.seconds * 60; f++) step(f);
    assert.deepEqual(log, a.events, `${a.profile} ${a.persona}`);
  }
  assert.ok(fx.ambient.some((a) => a.events.some((ev) => ev[1] === "blep")), "the fixture does have bleps");
});

test("zoomies after 5 minutes of work and on waking, and not otherwise, are the fixture's", () => {
  for (const z of seq.zoomiesAndWake) {
    const log = [], clock = { t: 0 };
    const e = new BotEngine(PRESETS.momo, { now: () => clock.t, rand: rng(1), quiet: true, log, cfg: { motion: z.profile, override: {}, pers: {}, zoomAfter: ZOOM_AFTER_MS } });
    const L = layout(PRESETS.momo, e.s, 0, 0, 2 * PRESETS.momo.rx);
    e.base = L.base; e.mouthAt = L.mouth;
    for (const [tMs, what] of z.script) { clock.t = tMs; e.setState(what.startsWith("wake:") ? "idle" : what); }
    for (let f = 0; f < 60; f++) { clock.t += 1000 / 60; e.update(1 / 60); }
    assert.deepEqual(log, z.log, `${z.profile}: ${z.name}`);
  }
});

test("a poke: annoyed by default, love from a cuddly cat, a hiss from a grumpy one, and Classic does the same", () => {
  const poke = (name, profile = "playful") => {
    const log = [];
    const { e, step } = makeEngine(PRESETS.momo, { profile, log, pers: { momo: personaNamed(name) } });
    e.slap();
    for (let f = 1; f <= 20; f++) step(f);
    return { e, log };
  };
  assert.deepEqual(poke("balanced").log.map((l) => l[1]), ["emote:annoyed"]);
  assert.deepEqual(poke("sweet").log.map((l) => l[1]), ["emote:love"]);
  assert.deepEqual(poke("sweet", "classic").log.map((l) => l[1]), ["emote:love"]);
  assert.deepEqual(poke("grumpy").log.map((l) => l[1]), ["emote:annoyed"]);
  assert.ok(poke("grumpy").e.s.mouth > poke("balanced").e.s.mouth, "a grumpy cat opens its mouth to hiss");
  assert.ok(PERSONAS.grumpy.sass > 0.7);
});

test("an unknown emote changes nothing, and the dizzy recovery ends with a happy emote", () => {
  const control = makeEngine(PRESETS.momo), poked = makeEngine(PRESETS.momo);
  poked.e.emote("nope"); poked.e.emote("__proto__"); poked.e.triggerEmote("toString");
  for (let f = 1; f <= 30; f++) { control.step(f); poked.step(f); }
  same(poked.e.s, JSON.parse(JSON.stringify(control.e.s)), "the pose is the quiet cat's");
  finite(poked.e.s);
  const lone = makeEngine(PRESETS.momo, { log: [] });
  lone.e.slap(); lone.e.slap(); lone.e.slap();
  for (let f = 1; f <= 60 * 4; f++) lone.step(f);
  assert.ok(lone.e.log.some((l) => l[1] === "emote:happy"), "the cat is happy to be back");
});

test("the island's triggerEmote plays the emote; the old duration argument is accepted and ignored", () => {
  const { e, step } = makeEngine(PRESETS.momo, { log: [] });
  e.triggerEmote("love", 5);
  step(10);
  assert.equal(e.log[0][1], "emote:love");
  assert.ok(e.s.blush > 0);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npm run check:cat`
Expected: FAIL. In `emotes.test.mjs`, `e.emote is not a function` (and the `ambient` and zoomies checks fail the same way); the other test files still pass.

- [ ] **Step 3: Insert the engine's stage-3 code**

Insert each block into `windows/src/cat/engine.ts` **above** the marker line named in its heading (the marker stays), except where it says replace.

Above `// @@S3-IMPORT`:

```ts title="windows/src/cat/engine.ts" above="@@S3-IMPORT"
import { EMOUTH } from "./base.ts";
```

Above `// @@S3-PROFILE-EMOTE`:

```ts title="windows/src/cat/engine.ts" above="@@S3-PROFILE-EMOTE"
  /** The body language of one emote. */
  emote(c: BotEngine, n: string): void;
```

Above `// @@S3-METHODS` (it contains the marker `// @@S4-EMOTE-HAIRBALL`, which stays inside `emote()`):

```ts title="windows/src/cat/engine.ts" above="@@S3-METHODS"
  /** Plays an emote: love, surprised, proud, wink, yawn, happy, annoyed, hello, zoomies or hairball. An unknown name is ignored. */
  emote(n: string) {
    this.note("emote:" + n);
    if (n === "hello") return this.greet();
    if (n === "zoomies") return this.zoomies();
    // @@S4-EMOTE-HAIRBALL
    this.prof.emote(this, n);
    if (own(EMOUTH, n)) { const m = EMOUTH[n]; this.mpose(m[0], m[1]); }
  }
  blep() { this.note("blep"); this.anim("tongue", [[0.7, 150, "out"], [0.7, 1300, "lin"], [this.tg.tongue, 220, "inOut"]]); }
  lick() { this.note("lick"); this.anim("mouth", [[0.16, 90, "out"], [this.tg.mouth, 170, "inOut"]]); this.anim("tongue", [[1, 90, "out"], [this.tg.tongue, 180, "inOut"]]); }
  slowBlink() { this.note("slowblink"); this.anim("lid", [[0.75, 380, "inOut"], [0.75, 320, "lin"], [0, 480, "inOut"]]); }
  /** Idle habits that come from personality: yawns, zoomies, mews, purrs, hmphs, winks. */
  persAmbient(t: number) {
    const I = this.pm().idle;
    if (this.state !== "idle" || t < this.nextPers) return;
    this.nextPers = t + this.u(6000, 11000);
    const r = this.rand();
    if (I.yawn && r < 0.5) return this.emote("yawn");
    if (I.zoomies && r < 0.35) return this.zoomies();
    if (I.mew && r < 0.6) return this.mpose({ mouth: 0.42, mround: 0.4, smile: 0.2 }, 420, 100, 180);
    if (I.purr && r < 0.55) { this.anim("lid", [[0.75, 380, "inOut"], [0.75, 600, "lin"], [0, 480, "inOut"]]); return this.anim("purr", [[1, 200, "out"], [1, 1000, "lin"], [0, 300, "inOut"]]); }
    if (I.hmph && r < 0.55) return this.mpose({ smile: -0.85, mskew: -0.7 }, 1000);
    if (I.wink && r < 0.5) { this.ov("wink", 550); this.blep(); }
  }
  /** Zoomies: pupils blown, ears back, side-to-side dashes with skids, then a happy flop. */
  zoomies() {
    this.note("zoomies");
    const a = this.anim.bind(this), pl = this.motion === "playful", tok = ++this.zoomTok, tg = this.tg;
    this.interruptGreet();
    this.zoomUntil = this.now() + 1950;
    this.ov("wide", 1900);
    a("pupil", [[1, 120, "out"], [1, 1750, "lin"], [tg.pupil, 400, "inOut"]]);
    a("earF", [[0.55, 150, "out"], [0.55, 1750, "lin"], [tg.earF, 400, "inOut"]]);
    a("ox", [[-0.05, 70, "inOut"], [0.04, 70, "inOut"], [-0.05, 70, "inOut"], [0.04, 70, "inOut"], [0, 60, "inOut"], [0.88, 240, "in"], [0.97, 90, "out"], [0.84, 110, "inOut"], [-0.88, 380, "inOut"], [-0.97, 90, "out"], [-0.84, 110, "inOut"], [0.3, 320, "inOut"], [0, 260, "back"]]);
    this.mpose({ mouth: 0.32, tongue: 0.9, smile: 0.6, mround: 0 }, 1950, 150, 300);
    this.later(670, () => { if (tok === this.zoomTok) this.dust(1); });
    this.later(1250, () => { if (tok === this.zoomTok) this.dust(-1); });
    this.later(1950, () => {
      if (tok !== this.zoomTok) return;
      this.ov("happy", 900);
      a("sy", [[0.84, 90, "out"], [1.06, 150, "out"], [1, 220, "back"]]);
      a("sx", [[1.14, 90, "out"], [0.96, 150, "out"], [1, 220, "back"]]);
      this.emit("spark", 3);
      if (pl) a("blush", [[0.5, 200, "out"], [0, 800, "inOut"]]);
    });
  }
  dust(dir: number) {
    const y = (this.p.ruff ? 1.1 : 0.88) / 1.3;
    for (let i = 0; i < 4; i++) {
      this.parts.push({
        k: "dust", x: (this.s.ox + dir * 0.45) / 1.3 + (this.rand() - 0.5) * 0.2, y: y + (this.rand() - 0.5) * 0.06,
        vx: -dir * this.u(0.12, 0.35), vy: -this.u(0.03, 0.12), age: -i * 0.04, life: 0.55 + this.rand() * 0.2, size: 0.09 + this.rand() * 0.05, rot: 0,
      });
    }
  }
  /** Paw wave, upstream's greet() timings with paws for hands. */
  greet() {
    const t = this.now(), tok = ++this.greetTok, a = this.anim.bind(this), ok = () => tok === this.greetTok;
    this.waveStart = t + 450;
    this.waveUntil = t + 1550;
    this.ov("happy", 2000);
    a("oy", [[-0.06, 220, "out"], [0, 220, "back"]]);
    this.later(250, () => {
      if (!ok()) return;
      a("paws", [[1, 280, "out"]]);
      a("sy", [[0.95, 100, "out"], [1, 260, "back"]]);
      a("sx", [[1.04, 100, "out"], [1, 260, "back"]]);
      if (this.motion === "playful") a("earU", [[1.15, 200, "out"], [1.15, 900, "lin"], [1, 400, "inOut"]]);
      Sound.play("greet");
    });
    this.later(450, () => { if (ok()) this.mpose({ mouth: 0.45, mround: 0.45, smile: 0.35 }, 650, 90, 200); });
    this.later(550, () => { if (ok()) this.blink(); });
    this.later(1500, () => { if (ok()) this.blink(); });
    this.later(1550, () => { if (!ok()) return; this.waveUntil = 0; a("paws", [[0, 200, "inOut"]]); });
    this.later(1750, () => { if (ok()) this.ov("happy", 300); });
  }
```

Above `// @@S3-PERS`:

```ts title="windows/src/cat/engine.ts" above="@@S3-PERS"
      this.persAmbient(t);
```

Above `// @@S3-DIZZY`:

```ts title="windows/src/cat/engine.ts" above="@@S3-DIZZY"
      this.emote("happy");
```

Replace the poke's tail in `slap()` (the marker `// @@S3-SLAP` is not there: this block replaces the two lines that exist):

```ts title="windows/src/cat/engine.ts" old
    this.ov("line", 800);
    this.later(60, () => Sound.play("annoyed"));
```

```ts title="windows/src/cat/engine.ts" new
    const M = this.pm();
    if (M.poke === "love") { this.emote("love"); return; }
    this.emote("annoyed");
    this.later(60, () => Sound.play("annoyed"));
    if (M.pokeHiss) this.mpose({ mouth: 0.6, smile: -1, mround: 0 }, 500, 60, 180);
```

Replace `triggerEmote`:

```ts title="windows/src/cat/engine.ts" old
  /** The island's emotes: for now only the eyes (the body language arrives with the emotes). */
  triggerEmote(emote: string, _duration?: number) {
    const e = EMOTE_EYE[emote];
    if (e) this.ov(e, 1800);
  }
```

```ts title="windows/src/cat/engine.ts" new
  /** The island's emotes. The duration the old engine took is gone: each emote has its own length now. */
  triggerEmote(emote: string, _duration?: number) {
    if (emote === "annoyed") this.later(60, () => Sound.play("annoyed"));
    this.emote(emote);
  }
```

- [ ] **Step 4: Insert Playful's and Classic's stage-3 code**

Above `// @@S3-IMPORT` in `windows/src/cat/motion/playful.ts`:

```ts title="windows/src/cat/motion/playful.ts" above="@@S3-IMPORT"
import { zoomiesOnFinish } from "../base.ts";
```

Above `// @@S3-WAKE`:

```ts title="windows/src/cat/motion/playful.ts" above="@@S3-WAKE"
    if (prev === "sleeping" && st !== "sleeping" && st !== "dizzy") c.later(220, () => c.zoomies(), "st");
```

Above `// @@S3-FINISHED-ZOOMIES`:

```ts title="windows/src/cat/motion/playful.ts" above="@@S3-FINISHED-ZOOMIES"
        if (zoomiesOnFinish(c.workedFor, c.cfg.zoomAfter)) { c.later(150, () => c.zoomies(), "st"); c.later(2200, () => c.emit("spark", 4), "st"); break; }
```

Above `// @@S3-HABITS`:

```ts title="windows/src/cat/motion/playful.ts" above="@@S3-HABITS"
    if (st === "idle" && t >= c.nextBlep) {
      if (!c.tw.tongue && !c.tw.mouth) { if (c.rand() < 0.55) c.blep(); else c.lick(); }
      c.nextBlep = t + c.u(8000, 15000);
    }
    if (["idle", "working", "thinking", "sleeping", "finished", "question"].includes(st) && t >= c.nextTw) {
      c.twitch(c.rand() < 0.5 ? "earL" : "earR");
      c.nextTw = t + (st === "working" ? c.u(1500, 3000) : st === "sleeping" ? c.u(4000, 8000) : c.u(3000, 7000)) * c.pm().earFlickEvery;
    }
    if (st === "idle" && t >= c.nextSB) { c.slowBlink(); c.nextSB = t + c.u(8000, 14000) * c.pm().slowBlinkEvery; }
    if (st === "ratelimit" && t >= c.nextYawn) { PLAYFUL.emote(c, "yawn"); c.nextYawn = t + 4800; }
```

Above `// @@S3-EMOTE`:

```ts title="windows/src/cat/motion/playful.ts" above="@@S3-EMOTE"
  emote(c: BotEngine, n: string) {
    const a = c.anim.bind(c), d = 1800;
    switch (n) {
      case "love":
        c.ov("closed", d); a("purr", [[1, 200, "out"], [1, d - 500, "lin"], [0, 300, "inOut"]]); a("blush", [[1, 300, "out"], [1, d - 600, "lin"], [0, 300, "inOut"]]);
        a("earL", [[0.18, 250, "out"], [0.18, d - 500, "lin"], [0, 250, "inOut"]]); a("earR", [[0.18, 250, "out"], [0.18, d - 500, "lin"], [0, 250, "inOut"]]);
        a("tilt", [[c.lookX >= 0 ? 0.12 : -0.12, 400, "inOut"], [0, 900, "inOut"]]); c.emit("heart", 3);
        break;
      case "surprised":
        c.ov("dot", 1100); a("earU", [[1.38, 90, "out"], [1, 600, "inOut"]]); a("sx", [[1.12, 80, "out"], [1, 500, "inOut"]]); a("sy", [[1.12, 80, "out"], [1, 500, "inOut"]]);
        a("oy", [[-0.2, 120, "out"], [0, 400, "back"]]); a("pupil", [[1, 100, "out"], [1, 700, "lin"], [0.45, 400, "inOut"]]); a("wh", [[0.4, 80, "out"], [0, 500, "inOut"]]);
        break;
      case "proud":
        c.ov("happy", d); a("lift", [[0.28, 260, "out"], [0.28, d - 560, "lin"], [0, 300, "inOut"]]); a("earU", [[1.15, 200, "out"], [1.15, d - 500, "lin"], [1, 300, "inOut"]]);
        c.emit("spark", 4); a("blush", [[0.5, 250, "out"], [0.5, d - 550, "lin"], [0, 300, "inOut"]]);
        break;
      case "wink": c.ov("wink", 1100); c.twitch("earR"); a("tilt", [[0.1, 180, "out"], [0.1, 700, "lin"], [0, 240, "inOut"]]); break;
      case "yawn":
        c.ov("closed", 1300); a("mouth", [[1, 450, "out"], [1, 500, "lin"], [0, 350, "inOut"]]); a("sy", [[1.12, 450, "inOut"], [1, 800, "inOut"]]);
        a("sx", [[0.94, 450, "inOut"], [1, 800, "inOut"]]); a("earF", [[0.75, 450, "inOut"], [c.tg.earF, 800, "inOut"]]);
        break;
      case "happy":
        c.ov("happy", 1400); a("oy", [[-0.06, 120, "out"], [0, 160, "inOut"], [-0.06, 120, "out"], [0, 200, "back"]]); a("earU", [[1.12, 150, "out"], [1, 600, "inOut"]]);
        a("blush", [[0.6, 200, "out"], [0, 700, "inOut"]]);
        break;
      case "annoyed": c.ov("line", 900); a("earF", [[1, 60, "out"], [1, 700, "lin"], [c.tg.earF, 400, "inOut"]]); a("wh", [[0.4, 60, "out"], [0, 400, "inOut"]]); break;
    }
  },
```

Above `// @@S3-EMOTE` in `windows/src/cat/motion/classic.ts`:

```ts title="windows/src/cat/motion/classic.ts" above="@@S3-EMOTE"
  emote(c: BotEngine, n: string) {
    const a = c.anim.bind(c), d = 1800;
    switch (n) {
      case "love": c.ov("heart", d); a("blush", [[1, 300, "out"], [1, d - 600, "lin"], [0, 300, "inOut"]]); c.emit("heart", 4); a("oy", [[-0.1, 160, "out"], [0, 300, "back"]]); break;
      case "surprised": c.ov("dot", d); a("oy", [[-0.3, 140, "out"], [0, 380, "back"]]); a("es", [[1.25, 120, "out"], [1, 500, "inOut"]]); break;
      case "proud": c.ov("star", d); c.emit("star", 5); a("tilt", [[-0.14, 220, "out"], [-0.14, d - 500, "lin"], [0, 280, "inOut"]]); a("blush", [[0.7, 250, "out"], [0.7, d - 550, "lin"], [0, 300, "inOut"]]); break;
      case "wink": c.ov("wink", d); a("tilt", [[0.12, 160, "out"], [0.12, d - 400, "lin"], [0, 240, "inOut"]]); break;
      case "yawn":
        c.ov("tired", d); a("sy", [[1.12, 500, "inOut"], [1, 500, "inOut"]]); a("sx", [[0.94, 500, "inOut"], [1, 500, "inOut"]]); a("mouth", [[0.8, 500, "inOut"], [0, 500, "inOut"]]);
        c.later(700, () => { c.ov("closed", 1100); c.emit("z", 2); });
        break;
      case "happy": c.ov("happy", d); a("blush", [[0.6, 200, "out"], [0, 600, "inOut"]]); break;
      case "annoyed": c.ov("line", 800); break;
    }
  },
```

- [ ] **Step 5: Run the tests and the type checks**

Run: `npm run check:cat && npx tsc --noEmit && npm run check:ai`
Expected: all pass. The emotes test checks every emote in both styles frame by frame (`emotes`: 288 rows less the hairball ones), 45 s of idle habits for each of the six personalities in both styles (`ambient`: the same events in the same order), the zoomies and wake rules (`zoomiesAndWake`), and the poke.

- [ ] **Step 6: Commit**

```bash
git add windows/src/cat windows/scripts/cat-tests
git commit -m "feat(cat): emotes, the mouth, idle habits, zoomies and the poke, tested against the fixtures

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The emote and personality panel

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/cat/dev.ts`

**Interfaces:**
- Consumes: `BotEngine.emote`, `setState`, `slap`, `PERSONAS`/`personaNamed`, `catCfg.pers`.
- Produces: the `S3-*` blocks of the contact sheet: one big live cat with buttons for every state, every emote and each personality preset.

- [ ] **Step 1: Add the panel**

Insert these blocks into `windows/src/cat/dev.ts` above the markers named (the markers stay). The panel's code contains the markers `// @@S4-HAIRBALL-BUTTON`, `// @@S4-CATCH` and `// @@S4-FLIGHTS` for stage 4: leave them.

Above `// @@S3-IMPORT`:

```ts title="windows/src/cat/dev.ts" above="@@S3-IMPORT"
import { PERSONAS, personaNamed } from "./personality.ts";
```

Above `// @@S3-PANEL`:

```ts title="windows/src/cat/dev.ts" above="@@S3-PANEL"
  // ── Stage 3: emotes, the mouth and personality ──
  const stageBox = section("Emotes, mouth and personality", "One big cat. The six mouth values show in every state and emote. Pick a personality: it bends the motion, and Balanced changes nothing.");
  const stageCv = document.createElement("canvas");
  stageCv.id = "stage-cat";
  stageCv.style.cssText = "background:#000;border-radius:14px;display:block;margin-top:12px;cursor:pointer";
  let stage = new BotEngine(PRESETS[dev.cat]);
  let stageState: StateName = "idle";
  const remake = () => { stage = new BotEngine(PRESETS[dev.cat], { state: stageState }); };
  const emotes = ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies"];
  const emoteRow = row("Emote");
  for (const n of emotes) emoteRow.append(button(n, () => stage.emote(n)));
  // @@S4-HAIRBALL-BUTTON
  const persRow = choice("Personality", Object.entries(PERSONAS).map(([k, v]) => [k, v.label] as const), () => catCfg.pers[dev.cat]?.preset ?? "balanced", (v) => { catCfg.pers[dev.cat] = personaNamed(v); });
  stageBox.append(
    choice("State", STATES.map((s) => [s, s] as const), () => stageState, (v) => { stageState = v; stage.setState(v); }),
    emoteRow, persRow, stageCv,
  );
  root.insertBefore(stageBox, wrap);
  stageCv.onpointerdown = () => stage.slap();
  rebuilds.push(remake);
  // @@S4-CATCH
  let sLast = performance.now();
  ticks.push(() => {
    const now = performance.now(), dt = Math.min(0.05, (now - sLast) / 1000);
    sLast = now;
    const W = 300, H = 300, c = fit(stageCv, W, H), box = stageCv.getBoundingClientRect();
    stage.particleOverhang = 60;
    const g = gazeFrom(box.left + W / 2, box.top + H / 2 + 30);
    stage.lookX = g.x; stage.lookY = g.y;
    stage.update(dt);
    stage.draw(c, W, H);
    // @@S4-FLIGHTS
  });
```

Run: `npx tsc --noEmit && npm run check:cat`
Expected: no type errors; the checks still pass.

- [ ] **Step 2: Look at the emotes, the mouth and the personalities**

```bash
WT="$(git rev-parse --show-toplevel)"; cd "${TMPDIR:-/tmp}/a-tauri-shots"
(cd "$WT/windows" && npx vite > vite.log 2>&1 &)
playwright-cli -s=sheet open "http://127.0.0.1:1420/?dev"
playwright-cli -s=sheet resize 1200 1400
playwright-cli -s=sheet screenshot --filename=stage3.png
```

The big cat is the canvas `#stage-cat`. Click an emote button, wait about as long as the emote lasts, and screenshot that canvas; repeat for love, surprised, proud, wink, yawn, happy, annoyed, hello and zoomies, in Playful and then Classic. Compare each with the prototype page's emote buttons (`playwright-cli -s=proto click "getByRole('button', { name: 'love' })"` on `http://127.0.0.1:8791/notchmeow.html`, then screenshot `#figShrimpy`). A helper for the screenshot of one canvas:

```bash
shot() { playwright-cli -s=sheet run-code "async page => { const b = await page.locator('#$2').boundingBox(); await page.screenshot({path: '$1', clip: {x: b.x, y: b.y, width: b.width, height: b.height}}); }"; }
playwright-cli -s=sheet click "getByRole('button', { name: 'zoomies' })"; sleep 0.8; shot zoomies.png stage-cat
playwright-cli -s=sheet click "getByRole('button', { name: 'yawn' })"; sleep 0.5; shot yawn.png stage-cat
```

By eye: love (closed eyes, a closed smile, hearts), surprised (round "o" mouth, wide pupils), proud (smug skewed smile, sparkles), wink (a blep), yawn (a wide open mouth with the tongue curled, ears folded back), happy (an open happy mouth), annoyed (flat ears, a "hmph" skewed to one side), hello (a paw waving with toe beans out, a "mrrp"), zoomies (pupils blown, ears back, dust). Pick Grumpy and poke the cat: it hisses. Pick Sweet and poke it: it purrs and shows love. Fix `dev.ts` if anything is wrong, then:

```bash
playwright-cli close-all
kill $(lsof -ti tcp:1420)
```

- [ ] **Step 3: Commit**

```bash
git add windows/src/cat/dev.ts
git commit -m "feat(cat): the emote and personality panel on the contact sheet

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

# Stage 4: the greeting, the file catch and the hairball

### Task 10: The file catch, the hairball and the error hiss

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/cat/engine.ts`, `windows/src/cat/geometry.ts`, `windows/src/cat/motion/playful.ts`, `windows/src/cat/dev.ts` (insert at the markers named below)
- Test: `windows/scripts/cat-tests/catch.test.mjs`

**Interfaces:**
- Consumes: the engine, geometry and renderer of Tasks 3 to 8; fixtures `sequence-cases.json` (`flight`, `catch`) and `motion-cases.json` (`emotes`, `enters`, now including the hairball rows).
- Produces on `BotEngine`: `catchOpen(on)`, `catchDrop()`, `catchArrive()`, `catchReject(ext)`, `hairball(file?)`, `spitBall(file?)`, and the drop view's flow `fileStep` (`"none" | "hover" | "flying" | "arrived"`), `fileHover(on)`, `fileDrop(name)`, `fileRefuse()`, `fileArrived()`; `emote("hairball")`; `gulp()` is now the arrival (`catchArrive`). Playful's error hiss ends in a hairball 900 ms later.
- **Sound:** `catchReject(ext)` plays the existing `annoyed` sound once, as the gag starts (`Sound.play("annoyed")`; the heaves follow 120 ms later), whichever order the drop view's events come in. The hairball itself, the error hiss's hairball and the other steps of the catch play nothing new: Stage 3 of the sound spec adds `pop` at the cough, not this plan.
- Produces in `geometry.ts`: `FLIGHT_MS` (380) and `flightAt(from, to, R, k): {x, y, size, rot}`, the arc a dropped file takes into the mouth.
- `engine.test.mjs` and `emotes.test.mjs` already skip Playful's hairball rows only while `BotEngine.prototype.hairball` does not exist, so they now check those rows too.
- `dev.ts` gains a hairball button and the catch buttons ("catch a file", "catch an unsupported file") on the big cat.

- [ ] **Step 1: Write the failing test**

Create `windows/scripts/cat-tests/catch.test.mjs`:

```js title="windows/scripts/cat-tests/catch.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import { FLIGHT_MS, flightAt } from "../../src/cat/geometry.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { Sound } from "../../src/core/sound.ts";
import { load, near, same } from "./util.mjs";
import { frameMs, makeEngine, rowOf } from "./engine-util.mjs";

const seq = load("sequence-cases.json");
const { columns } = load("motion-cases.json");

test("a dropped file arcs into the mouth: where it is, how big, how turned, along its flight", () => {
  assert.equal(FLIGHT_MS, seq.flight.flightMs);
  for (const c of seq.flight.cases) same(flightAt(c.from, c.to, c.R, c.k), c.out, `k = ${c.k}`);
  near(flightAt({ x: 0, y: 0 }, { x: 10, y: 10 }, 30, 1).size, 30 * 0.14);
});

test("rows are matched by frame f, the authority: their tMs is derived (f * 1000 / 60, stored to 12 digits) and agrees within 1e-8", () => {
  const motion = load("motion-cases.json");
  for (const r of [...motion.enters, ...motion.emotes, ...seq.catch.flatMap((c) => c.rows)]) near(r.tMs, frameMs(r.f), 1e-8);
});

test("the file catch, in four steps, in both motion styles, for a file taken and a file refused, is the fixture's", () => {
  const flightFrames = seq.catchHarness.flightFrames;
  assert.equal(flightFrames, Math.ceil(FLIGHT_MS / frameMs(1)));
  for (const c of seq.catch) {
    const { e, step } = makeEngine(PRESETS.momo, { profile: c.profile });
    const want = new Map(c.rows.map((r) => [r.f, r])), last = c.rows[c.rows.length - 1].f;
    e.catchOpen(true); // 1. open wide while the file hovers
    for (let f = 0; f <= last; f++) {
      if (f > 0) step(f);
      if (f === c.dropFrame) e.catchDrop(); // 2. snap wider on the drop, the file flies in
      if (f === c.arriveFrame) { if (c.refused) e.catchReject("EXE"); else e.catchArrive(); } // 3. gulp with a squash, 4. chew with happy eyes
      const r = want.get(f);
      if (r) { assert.equal(e.eyeShape(), r.eye, `${c.profile} refused=${c.refused} f${f}: eye`); same(rowOf(e, columns), r.v, `${c.profile} refused=${c.refused} f${f}`); }
    }
  }
});

test("the catch behaves: open while hovering, closed again when the file leaves, chewing for 0.85 s, and a refused file comes back as a hairball", () => {
  const { e, step } = makeEngine(PRESETS.shrimpy);
  e.catchOpen(true);
  for (let f = 1; f <= 30; f++) step(f);
  assert.ok(e.mouthOpen() > 0.3, "open wide while the file hovers");
  e.catchOpen(false);
  for (let f = 31; f <= 90; f++) step(f);
  assert.ok(e.mouthOpen() < 0.02, "closed again when it leaves");
  assert.equal(e.eyeOv, null);
  e.catchArrive();
  let chewing = 0;
  for (let f = 91; f <= 91 + 90; f++) { step(f); if (e.chew > 0) chewing++; }
  assert.ok(chewing > 40 && chewing < 60, `chewed for about 0.85 s, not ${chewing / 60} s`);
  const refused = makeEngine(PRESETS.shrimpy);
  refused.e.catchReject("ZIP");
  let ball = null;
  for (let f = 1; f <= 60 * 4; f++) { refused.step(f); if (refused.e.balls.length) ball = refused.e.balls[0]; }
  assert.ok(ball && ball.file === "ZIP", "the file comes back wrapped in fur");
  assert.equal(refused.e.balls.length, 0, "and rolls away");
});

test("a hairball without a known mouth position is skipped, not thrown", () => {
  const { e, step } = makeEngine(PRESETS.momo);
  e.mouthAt = null;
  e.hairball();
  for (let f = 1; f <= 200; f++) step(f);
  assert.equal(e.balls.length, 0);
});

// The drop view reports a file in whatever order things happen: the app's refusal can come before the file
// reaches the mouth, after it, or never. The cat must cough up exactly one hairball, or none, and never get stuck.
const hairballs = (log) => log.filter((l) => l[1] === "hairball").length;
const run = (script) => {
  const log = [], { e, step } = makeEngine(PRESETS.shrimpy, { log });
  let f = 0;
  const wait = (frames) => { for (let i = 0; i < frames; i++) step(++f); };
  script(e, wait);
  wait(60 * 4);
  return { e, log };
};

test("a refusal that comes before the file arrives: the cat takes it, then coughs it up, once", () => {
  const { e, log } = run((e, wait) => { e.fileHover(true); wait(30); e.fileDrop("setup.exe"); e.fileRefuse(); wait(10); e.fileArrived(); });
  assert.equal(hairballs(log), 1);
  assert.equal(e.fileStep, "arrived");
  assert.equal(e.balls.length, 0, "and the ball has rolled away");
});

test("a refusal that comes after the file has arrived: the cat has swallowed it and coughs it up, once", () => {
  const { log } = run((e, wait) => { e.fileHover(true); e.fileDrop("a.zip"); wait(23); e.fileArrived(); wait(5); e.fileRefuse(); e.fileRefuse(); });
  assert.equal(hairballs(log), 1);
});

test("a file that is taken is chewed, with no hairball; and a stray arrival without a drop does nothing", () => {
  const { log } = run((e, wait) => { e.fileArrived(); wait(3); e.fileHover(true); e.fileArrived(); e.fileDrop("notes.pdf"); wait(23); e.fileArrived(); e.fileArrived(); });
  assert.equal(hairballs(log), 0);
  const chew = makeEngine(PRESETS.shrimpy);
  chew.e.fileDrop("a.pdf"); chew.e.fileArrived();
  let chewed = 0;
  for (let f = 1; f <= 90; f++) { chew.step(f); if (chew.e.chew > 0) chewed++; }
  assert.ok(chewed > 40);
});

test("a new drag after a refused drop starts clean; a file that leaves closes the mouth; the extension is shown in capitals", () => {
  const { e, log } = run((e, wait) => { e.fileHover(true); e.fileDrop("x.exe"); e.fileRefuse(); wait(23); e.fileArrived(); wait(60 * 4); e.fileHover(true); e.fileDrop("b.pdf"); wait(23); e.fileArrived(); wait(30); e.fileHover(false); });
  assert.equal(hairballs(log), 1, "the second file is not refused");
  assert.equal(e.catching, false);
  const ball = makeEngine(PRESETS.momo);
  ball.e.fileDrop("archive.tar.gz"); ball.e.fileRefuse(); ball.e.fileArrived();
  let ext = null;
  for (let f = 1; f <= 120; f++) { ball.step(f); if (ball.e.balls[0]) ext = ball.e.balls[0].file; }
  assert.equal(ext, "GZ");
  const bare = makeEngine(PRESETS.momo);
  bare.e.fileDrop("Makefile"); bare.e.fileRefuse(); bare.e.fileArrived();
  let ext2 = null;
  for (let f = 1; f <= 120; f++) { bare.step(f); if (bare.e.balls[0]) ext2 = bare.e.balls[0].file; }
  assert.equal(ext2, "FILE", "a file with no extension shows FILE");
});

// What the cat plays during a catch. `Sound.play` is swapped for a recorder while the script runs (in plain Node it plays nothing anyway), so each sound
// comes with the frame it was played at. The cat's one sound for a refused file is `annoyed`, once, as the gag starts (the file has reached the mouth and
// the app has refused it, whichever came last); the hairball and the note after it are silent. Stage 3 of the sound spec adds `pop` at the cough.
const heard = (script) => {
  const played = [], { e, step } = makeEngine(PRESETS.shrimpy);
  let f = 0;
  Sound.play = (name) => { played.push([f, name]); };
  try {
    script(e, (frames) => { for (let i = 0; i < frames; i++) step(++f); });
    for (let i = 0; i < 60 * 4; i++) step(++f); // the heaves, the hairball and the roll that follow
  } finally {
    delete Sound.play; // back to the engine's own method
  }
  return played;
};

test("the cat plays annoyed once, when the gag starts, and nothing else: not at the hover, the drop, the hairball or the roll", () => {
  // The app's refusal comes before the file reaches the mouth: the gag starts when the file arrives (frame 40), not before.
  assert.deepEqual(heard((e, wait) => { e.fileHover(true); wait(30); e.fileDrop("setup.exe"); e.fileRefuse(); wait(10); e.fileArrived(); }), [[40, "annoyed"]]);
  // It comes after the file has arrived: the gag starts at once (frame 28), and a second refusal does not play it again.
  assert.deepEqual(heard((e, wait) => { e.fileHover(true); e.fileDrop("a.zip"); wait(23); e.fileArrived(); wait(5); e.fileRefuse(); e.fileRefuse(); }), [[28, "annoyed"]]);
  // A refused file, then a taken one: one annoyed in all.
  const two = heard((e, wait) => { e.fileHover(true); e.fileDrop("x.exe"); e.fileRefuse(); wait(23); e.fileArrived(); wait(60 * 4); e.fileHover(true); e.fileDrop("b.pdf"); wait(23); e.fileArrived(); });
  assert.deepEqual(two.map((s) => s[1]), ["annoyed"]);
});

test("a file that is taken makes no sound, and a hairball that is not a refusal makes none either", () => {
  assert.deepEqual(heard((e, wait) => { e.fileHover(true); wait(30); e.fileDrop("notes.pdf"); wait(23); e.fileArrived(); }), []);
  assert.deepEqual(heard((e) => e.emote("hairball")), [], "the hairball's pop is the sound spec's Stage 3, not here");
  assert.deepEqual(heard((e, wait) => { e.fileHover(true); wait(20); e.fileHover(false); }), [], "a file that hovers and leaves");
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npm run check:cat`
Expected: FAIL. `catch.test.mjs` cannot load `FLIGHT_MS` from `geometry.ts` (`does not provide an export named 'FLIGHT_MS'`); and the hairball rows that `engine.test.mjs` and `emotes.test.mjs` skipped are not checked yet because the method does not exist.

- [ ] **Step 3: Insert the geometry's flight**

Above `// @@S4-IMPORT` in `windows/src/cat/geometry.ts`:

```ts title="windows/src/cat/geometry.ts" above="@@S4-IMPORT"
import { EZ } from "./base.ts";
```

Above `// @@S4-FLIGHT`:

```ts title="windows/src/cat/geometry.ts" above="@@S4-FLIGHT"
/** A dropped file arcs into the cat's mouth over this long (ms). */
export const FLIGHT_MS = 380;

/** Where the file is, how big and how turned, `k` (0 to 1) of the way along its arc from `from` to the mouth `to`. R is the head radius in px. */
export function flightAt(from: { x: number; y: number }, to: { x: number; y: number }, R: number, k: number) {
  const q = EZ.inOut(k), cx = (from.x + to.x) / 2, cy = Math.min(from.y, to.y) - 60, u = 1 - q;
  return {
    x: u * u * from.x + 2 * u * q * cx + q * q * to.x, y: u * u * from.y + 2 * u * q * cy + q * q * to.y,
    size: lerp(R * 0.62, R * 0.14, q), rot: (1 - q) * 0.5 - 0.25,
  };
}
```

- [ ] **Step 4: Insert the engine's catch, hairball and drop flow**

Above `// @@S4-EMOTE-HAIRBALL` in `windows/src/cat/engine.ts`:

```ts title="windows/src/cat/engine.ts" above="@@S4-EMOTE-HAIRBALL"
    if (n === "hairball") return this.hairball();
```

Above `// @@S4-METHODS`:

```ts title="windows/src/cat/engine.ts" above="@@S4-METHODS"
  /** File catch, step 1: open wide while a file hovers over the island. `false` closes the mouth again. */
  catchOpen(on: boolean) {
    if (on === this.catching) return;
    this.catching = on;
    if (on) {
      this.slotT = 0.55;
      this.eyeOv = "wide";
      this.eyeUntil = Infinity;
      this.anim("oy", [[-0.05, 160, "out"], [-0.03, 200, "inOut"]]);
    } else {
      this.slotT = 0;
      if (this.eyeUntil === Infinity) { this.eyeOv = null; this.eyeUntil = 0; }
    }
  }
  /** Step 2: the file is dropped and flies in: snap wider. */
  catchDrop() { this.catching = true; this.slotT = 1.05; this.eyeOv = "wide"; this.eyeUntil = Infinity; }
  /** Steps 3 and 4: the file arrives: gulp with a squash, then chew for 0.85 s with happy eyes. */
  catchArrive() {
    this.catching = false;
    this.slotT = 0;
    const t = this.now(), a = this.anim.bind(this);
    this.chewStart = t + 80;
    this.chewUntil = t + 930;
    this.ov("happy", 1250);
    a("sy", [[0.8, 80, "out"], [1.16, 130, "out"], [1, 220, "back"]]);
    a("sx", [[1.24, 80, "out"], [0.92, 130, "out"], [1, 220, "back"]]);
    if (this.motion === "playful") { a("earU", [[1.15, 150, "out"], [1, 500, "inOut"]]); a("blush", [[0.6, 200, "out"], [0, 800, "inOut"]]); }
    this.later(950, () => this.lick());
    this.later(1000, () => this.emit("spark", 3));
  }
  /**
   * A file the app refuses: the cat caught it, gags and coughs it back up wrapped in fur. `ext` is shown on the file.
   * The gag starts with the cat's `annoyed` sound, once; the hairball 120 ms later, and the note after it, are silent
   * (sound Stage 3 adds the `pop` at the cough).
   */
  catchReject(ext: string) {
    this.catching = false;
    this.slotT = 0;
    this.eyeOv = null;
    this.eyeUntil = 0;
    Sound.play("annoyed");
    this.later(120, () => this.hairball(ext));
  }
  /**
   * The drop view's file, in whatever order the events come: hovering over the island, dropped and flying into the mouth,
   * swallowed. The drop view calls these four; the refusal can arrive before the file reaches the mouth, after it, or never.
   */
  fileStep: "none" | "hover" | "flying" | "arrived" = "none";
  private fileExt = "FILE";
  private fileRefused = false;
  private fileRejected = false;

  /** A file is over the island (true) or left it (false): the cat opens wide, or closes its mouth again. */
  fileHover(on: boolean) {
    if (on) { this.fileStep = "hover"; this.fileRefused = false; this.fileRejected = false; }
    else if (this.fileStep === "hover") this.fileStep = "none";
    else return;
    this.catchOpen(on);
  }
  /** The file was dropped. `name` gives the extension that a refused file shows. */
  fileDrop(name: string) {
    const dot = name.lastIndexOf(".");
    this.fileExt = ((dot >= 0 ? name.slice(dot + 1) : "") || "file").slice(0, 4).toUpperCase();
    this.fileStep = "flying";
    this.fileRefused = false;
    this.fileRejected = false;
    this.catchDrop();
  }
  /** The app can't take this file: the cat coughs it back up once it has swallowed it, at once if it already has. */
  fileRefuse() {
    this.fileRefused = true;
    if (this.fileStep === "arrived" && !this.fileRejected) { this.fileRejected = true; this.catchReject(this.fileExt); }
  }
  /** The file has reached the mouth: gulp and chew, or gag. Ignored unless a file is flying. */
  fileArrived() {
    if (this.fileStep !== "flying") return;
    this.fileStep = "arrived";
    if (this.fileRefused) { this.fileRejected = true; this.catchReject(this.fileExt); }
    else this.catchArrive();
  }
  /** Hairball: ears back, three heaves, then it comes up (with the file, if it was one). */
  hairball(file?: string) {
    this.note("hairball");
    const a = this.anim.bind(this), pl = this.motion === "playful", tok = ++this.hbTok, tg = this.tg;
    this.ov("closed", 1300);
    if (pl) a("earF", [[0.7, 150, "out"], [0.7, 1000, "lin"], [tg.earF, 400, "inOut"]]);
    a("oy", [[0.06, 140, "out"], [0, 180, "inOut"], [0.07, 140, "out"], [0, 180, "inOut"], [0.09, 140, "out"], [-0.02, 160, "inOut"], [0.11, 170, "out"], [0, 320, "back"]]);
    a("sy", [[0.92, 140, "out"], [1.04, 180, "inOut"], [0.9, 140, "out"], [1.05, 180, "inOut"], [0.88, 140, "out"], [1.06, 160, "inOut"], [0.86, 170, "out"], [1, 320, "back"]]);
    a("sx", [[1.05, 140, "out"], [0.98, 180, "inOut"], [1.07, 140, "out"], [0.97, 180, "inOut"], [1.09, 140, "out"], [0.96, 160, "inOut"], [1.1, 170, "out"], [1, 320, "back"]]);
    a("mouth", [[0.22, 140, "out"], [0, 180, "inOut"], [0.28, 140, "out"], [0, 180, "inOut"], [0.34, 140, "out"], [0, 160, "inOut"], [1.05, 170, "out"], [1.05, 160, "lin"], [tg.mouth, 260, "inOut"]]);
    a("mround", [[0.3, 140, "out"], [0.3, 800, "lin"], [0, 170, "out"], [0, 420, "lin"], [tg.mround, 200, "inOut"]]);
    a("smile", [[-0.7, 140, "out"], [-0.7, 970, "lin"], [0.5, 330, "inOut"], [0.5, 700, "lin"], [tg.smile, 300, "inOut"]]);
    this.later(1110, () => { if (tok === this.hbTok) this.spitBall(file); });
    this.later(1450, () => {
      if (tok !== this.hbTok) return;
      this.ov("happy", 900);
      if (pl) a("blush", [[0.45, 200, "out"], [0, 700, "inOut"]]);
      this.later(320, () => this.lick());
    });
  }
  spitBall(file?: string) {
    const m = this.mouthAt, b0 = this.base;
    if (!m || !b0) return;
    const R = b0.R, dir = this.rand() < 0.5 ? -1 : 1, mx = (m.x - b0.x) / R, my = (m.y - b0.y) / R;
    this.balls.push({
      x: mx, y: my, vx: dir * this.u(0.55, 0.85), vy: this.u(-0.9, -0.6), rot: 0, age: 0, life: file ? 2.6 : 2.4, file: file || null,
      seed: (this.rand() * 1e9) | 0, floor: this.p.ruff ? 1.34 : 1.12,
    });
    for (let i = 0; i < 4; i++) {
      this.parts.push({
        k: "hair", x: mx / 1.3 + (this.rand() - 0.5) * 0.15, y: my / 1.3, vx: (this.rand() - 0.5) * 0.5, vy: this.u(-0.35, -0.15),
        age: -0.05 * i, life: 0.9 + this.rand() * 0.4, size: 0.12 + this.rand() * 0.05, rot: this.rand() * 6,
      });
    }
  }
```

Replace `gulp` (a squash and a blink) with the arrival:

```ts title="windows/src/cat/engine.ts" old
  /** The file has been swallowed: a squash and a blink. */
  gulp() {
    this.anim("sy", [[0.78, 80, "out"], [1.18, 130, "out"], [1, 220, "back"]]);
    this.anim("sx", [[1.28, 80, "out"], [0.92, 130, "out"], [1, 220, "back"]]);
    this.blink();
  }
```

```ts title="windows/src/cat/engine.ts" new
  /** The file has arrived: gulp and chew. */
  gulp() { this.catchArrive(); }
```

- [ ] **Step 5: Playful's error hiss ends in a hairball**

Above `// @@S4-HISS-HAIRBALL` in `windows/src/cat/motion/playful.ts`:

```ts title="windows/src/cat/motion/playful.ts" above="@@S4-HISS-HAIRBALL"
        c.later(900, () => c.hairball(), "st");
```

- [ ] **Step 6: Run the tests and the type checks**

Run: `npm run check:cat && npx tsc --noEmit && npm run check:ai`
Expected: all pass, and the checks that were waiting now run in full: `engine.test.mjs` checks the Playful `error` rows after the hiss, `emotes.test.mjs` checks the hairball rows (both styles, Momo and Shrimpy), and `catch.test.mjs` checks the flight arc, the four-step catch in both styles for a file taken and a file refused, every order of hover, drop, refusal and arrival, and the sounds (`annoyed` once, at the gag, for a refused file; none for a taken file or a bare hairball).

- [ ] **Step 7: Add the hairball and catch buttons to the contact sheet**

Above `// @@S4-IMPORT-CATCH` in `windows/src/cat/dev.ts`:

```ts title="windows/src/cat/dev.ts" above="@@S4-IMPORT-CATCH"
import { FLIGHT_MS, flightAt } from "./geometry.ts";
import { drawFileIcon } from "./renderer.ts";
```

Above `// @@S4-HAIRBALL-BUTTON`:

```ts title="windows/src/cat/dev.ts" above="@@S4-HAIRBALL-BUTTON"
  emoteRow.append(button("hairball", () => stage.emote("hairball")));
```

Above `// @@S4-CATCH`:

```ts title="windows/src/cat/dev.ts" above="@@S4-CATCH"
  const flights: { t0: number; ext: string; reject: boolean; from: { x: number; y: number } }[] = [];
  const catchRow = row("File");
  const simulate = (ext: string, reject: boolean) => {
    stage.catchOpen(true);
    setTimeout(() => { stage.catchDrop(); flights.push({ t0: performance.now(), ext, reject, from: { x: 260, y: 40 } }); }, 420);
  };
  catchRow.append(button("catch a file", () => simulate("PDF", false)), button("catch an unsupported file", () => simulate("EXE", true)));
  stageBox.insertBefore(catchRow, stageCv);
```

Above `// @@S4-FLIGHTS`:

```ts title="windows/src/cat/dev.ts" above="@@S4-FLIGHTS"
    for (let i = flights.length - 1; i >= 0; i--) {
      const f = flights[i], k = Math.min(1, (now - f.t0) / FLIGHT_MS), m = stage.mouthAt, b = stage.base;
      if (!m || !b) continue;
      const w = flightAt(f.from, m, b.R, k);
      drawFileIcon(c, w.x, w.y, w.size, w.rot, f.ext);
      if (k >= 1) { flights.splice(i, 1); if (f.reject) stage.catchReject(f.ext); else stage.catchArrive(); }
    }
```

Run: `npx tsc --noEmit`
Expected: no output.

- [ ] **Step 8: Look at the hairball and the catch**

```bash
WT="$(git rev-parse --show-toplevel)"; cd "${TMPDIR:-/tmp}/a-tauri-shots"
(cd "$WT/windows" && npx vite > vite.log 2>&1 &)
playwright-cli -s=sheet open "http://127.0.0.1:1420/?dev"
playwright-cli -s=sheet resize 1200 1400
shot() { playwright-cli -s=sheet run-code "async page => { const b = await page.locator('#$2').boundingBox(); await page.screenshot({path: '$1', clip: {x: b.x, y: b.y, width: b.width, height: b.height}}); }"; }
playwright-cli -s=sheet click "getByRole('button', { name: 'hairball', exact: true })"; sleep 1.7; shot hairball.png stage-cat
playwright-cli -s=sheet click "getByRole('button', { name: 'catch an unsupported file' })"; sleep 2.2; shot refused.png stage-cat
```

By eye: the hairball (ears back, three heaves, a ball of fur that bounces once and rolls away, a lick of relief) and the refused file (the file icon wrapped in fur). The browser's real-time screenshots are imprecise; the drop view's own harness in Task 12 uses a fake clock for the exact moments. Then:

```bash
playwright-cli close-all
kill $(lsof -ti tcp:1420)
```

- [ ] **Step 9: Commit**

```bash
git add windows/src/cat windows/scripts/cat-tests
git commit -m "feat(cat): the file catch, the hairball and the Playful error hiss, tested against the fixtures

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 11: The new greeting

**Agent:** `nm-implementer`.

**Files:**
- Replace: `windows/src/cat/greeting.ts` (the old character's greeting)
- Modify: `windows/src/cat/dev.ts`
- Test: `windows/scripts/cat-tests/greeting.test.mjs`

**Interfaces:**
- Consumes: `layout` constants `COMPACT_W`, `NOTCH_H`, `NOTCH_W` from `core/layout.ts`; `Sound`; `EZ`, `TAU`, `lerp`, `rng`, `seg` from `base.ts`; `drawCat`, `stillView`, `type CatView`, `type PawSpec` from `renderer.ts`; `newPose`; `PRESETS`, `catById`, `DEFAULT_CAT`; fixture `sequence-cases.json` (`greetingLengthS`, `greetingTimeline`, `greetingStreaks`, `greetingSamples`).
- Produces `src/cat/greeting.ts`: `GT`, `GT2`, `GREET_LEN` (5.74), `STREAKS`, `streakTime(t)`, `greetingPose(t, leave?): GreetPose` (pure; `leave` is when the island collapses, `GT.leave` unless the pointer left early, and the cat then settles from wherever it is), `GREETING_END` (4.6), `MINI_GRID` (the compact island's mini grid, where the greeting's session cats sit: `{ d: 13, step: 16, x: 424, y: 16 }` in the 640 by 150 canvas), `class Greeting` with the same members as the old one the island uses: `start()`, `hover()`, `interrupt()`, `draw(ctx)`, `elapsed`, `done`, `onComplete`. The island's `Greeting` import and calls are unchanged.
- The greeting draws, in the island's 640×150 canvas: the card, the golden-to-blue halo, the streak burst, **the header** ("NotchMeow" on the left, "Hi! Shrimpy is watching your agents." on the right, fading in with the card: the old greeting computed `header` and never drew it), the cat (Shrimpy until Settings arrives) with its paws, and **the session cats**: four blue-tinted cats (tint 0.6, colour 127, 180, 234) that pop in with a scale as the island collapses, sized and placed as the real compact island's mini grid (`MINI_GRID`), which takes over after the greeting. The Mac plan's session cats are Ø11 at 6 px offsets because the Mac's grid is; this app's grid is Ø13, 16 px apart, so the greeting uses that, and a check reads `island.ts` and `style.css` to keep the two together. The upstream greeting sound is not used: the call sites keep the sound names `greet` (when the cat pops up) and `blip` (the badge).

- [ ] **Step 1: Write the failing test**

Create `windows/scripts/cat-tests/greeting.test.mjs`:

```js title="windows/scripts/cat-tests/greeting.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { GREET_LEN, GT, GT2, Greeting, MINI_GRID, STREAKS, greetingPose, streakTime } from "../../src/cat/greeting.ts";
import { COMPACT_W, NOTCH_H } from "../../src/core/layout.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { finite, load, near, same } from "./util.mjs";

const seq = load("sequence-cases.json");

test("the greeting's beats and streaks are the fixture's, and it is still 5.74 s", () => {
  assert.equal(GREET_LEN, seq.greetingLengthS);
  near(GREET_LEN, 5.74);
  const tl = seq.greetingTimeline;
  same({ ...GT }, Object.fromEntries(Object.keys(GT).map((k) => [k, tl[k]])), "GT");
  same({ ...GT2 }, Object.fromEntries(Object.keys(GT2).map((k) => [k, tl[`v2_${k}`]])), "GT2");
  same(STREAKS, seq.greetingStreaks, "streaks");
  near(streakTime(GT2.land), 0.1);
});

test("the greeting pose, every 100 ms and at each beat, is the fixture's", () => {
  assert.ok(seq.greetingSamples.length > 60);
  for (const s of seq.greetingSamples) same(greetingPose(s.tMs / 1000), s.pose, `t = ${s.tMs} ms`);
});

test("a greeting cut short (the pointer left) continues from where the cat is, and settles in the compact notch", () => {
  for (const tc of [0.3, 1.0, 2.0, 3.0, 4.0, 4.6]) {
    const here = greetingPose(tc), start = greetingPose(tc, tc);
    for (const k of ["x", "y", "hb", "sx", "sy", "tilt", "lookX", "lookY", "handL", "handR", "badge", "tint"]) near(start[k], here[k], 1e-9);
    const end = greetingPose(tc + GT.COLLAPSE + 0.6, tc);
    near(end.hb * 1.34, 20);
    near(end.x, 320 - 288 / 2 + 40);
    near(end.y, 16);
    assert.equal(end.minis, 1);
    assert.equal(end.handR, 0);
  }
  same(greetingPose(5, GT.leave), greetingPose(5), "the default leave is GT.leave");
});

test("the greeting never gives a bad number, before it starts or long after it ends", () => {
  for (const t of [-5, -0.001, 0, 3, GT.leave, GREET_LEN, 60, 1e6]) finite(greetingPose(t), `t = ${t}`);
  assert.equal(greetingPose(-1).card, 0);
});

/** Draws the greeting at second `t` on a canvas that records its text and translations; the clock is the test's. */
function drawAt(t) {
  installBrowserStubs();
  const g = new Greeting();
  Object.defineProperty(g, "elapsed", { get: () => t });
  const ctx = fakeCanvas(), texts = [], moves = [], scales = [];
  ctx.fillText = (text, x, y) => texts.push({ text, x, y, alpha: ctx.globalAlpha, align: ctx.textAlign });
  const translate = ctx.translate, scale = ctx.scale;
  ctx.translate = (x, y) => { moves.push([x, y]); return translate(x, y); };
  ctx.scale = (x, y) => { scales.push([x, y]); return scale(x, y); };
  g.draw(ctx);
  return { g, texts, moves, scales };
}

test("the header is drawn: the app's name on the left and the greeting on the right, fading in with the card", () => {
  assert.deepEqual(drawAt(0.2).texts, [], "not before the card starts to fade in");
  const half = drawAt(0.475).texts;
  assert.equal(half.length, 2);
  near(half[0].alpha, 0.5);
  const full = drawAt(2).texts;
  assert.deepEqual(full.map((x) => [x.text, x.x, x.y, x.align, x.alpha]), [
    ["NotchMeow", 20, 20, "left", 1],
    ["Hi! Shrimpy is watching your agents.", 620, 20, "right", 1],
  ]);
  assert.deepEqual(drawAt(5.5).texts, [], "gone once the island has collapsed");
});

test("the session cats pop in with a scale at the compact island's mini grid, blue-tinted", () => {
  assert.equal(drawAt(4).moves.filter(([x, y]) => x > 400 && y < 30).length, 0, "none before the island collapses");
  const t = 5.3, pop = greetingPose(t).minis, { g, moves, scales } = drawAt(t);
  assert.ok(pop > 0.5, `popping in (${pop})`);
  for (const [dx, dy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    const at = [MINI_GRID.x + (dx * MINI_GRID.step) / 2, MINI_GRID.y + (dy * MINI_GRID.step) / 2];
    assert.ok(moves.some(([x, y]) => x === at[0] && y === at[1]), `a session cat at ${at}`);
  }
  assert.equal(scales.filter(([x, y]) => x === pop && y === pop).length, 4, "each pops in with the same scale, 0 to 1 and a little over");
  assert.equal(g.minis.s.tint, 0.6);
  assert.deepEqual(g.minis.col, [127, 180, 234]);
});

test("the session cats sit where the compact island's real mini grid does: this app's grid, not the Mac's", () => {
  const island = fs.readFileSync(new URL("../../src/island/island.ts", import.meta.url), "utf8");
  const css = fs.readFileSync(new URL("../../src/style.css", import.meta.url), "utf8");
  const box = css.match(/#mini-grid \{[^}]*\}/)[0];
  const cell = Number(box.match(/grid-template-columns: (\d+)px/)[1]), gap = Number(box.match(/gap: (\d+)px/)[1]);
  const body = Number(island.match(/createMiniBot\(t, (\d+)\)/)[1]);
  const left = island.match(/miniGrid\.style\.left = `\$\{w - (\d+) - ([\d.]+)\}px`/), top = island.match(/miniGrid\.style\.top = `\$\{hh \/ 2 - ([\d.]+)\}px`/);
  const half = (2 * cell + gap) / 2; // the grid's box is 2 cells and a gap wide: its centre is half of that in from its left edge
  assert.deepEqual([MINI_GRID.d, MINI_GRID.step], [body, cell + gap], "the head width and the spacing of the real grid");
  assert.equal(Number(left[2]), half, "the grid's left edge is its centre minus half its width");
  assert.equal(MINI_GRID.x, 320 - COMPACT_W / 2 + (COMPACT_W - Number(left[1])), "40 px in from the island's right edge, in the 640 wide canvas");
  assert.equal(Number(top[1]), half);
  assert.equal(MINI_GRID.y, NOTCH_H / 2, "level with the middle of the strip");
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npm run check:cat`
Expected: FAIL. `greeting.test.mjs` cannot load `src/cat/greeting.ts`: it is still the old character's greeting, which imports `../core/sound` with no extension, so Node stops with an import error.

- [ ] **Step 3: Replace the greeting**

Overwrite `windows/src/cat/greeting.ts`:

```ts title="windows/src/cat/greeting.ts"
// The launch greeting. Everything is laid out in a 640×150 space, as on macOS (GreetingCanvasView.swift).
// The timeline is Greeting v2 from design/prototype/cat-core.js, the tie-breaker: the cat falls in with a landing
// squash, bounces, slides aside, pops up for a quick paw wave, slides back and settles with the badge and the tint.
// The pose is pure (`greetingPose`, tested against tests/fixtures/cat/sequence-cases.json); the Greeting class below
// owns the clock, the sounds and the drawing.

import { COMPACT_W, NOTCH_H, NOTCH_W } from "../core/layout.ts";
import { Sound } from "../core/sound.ts";
import { EZ, TAU, lerp, rng, seg } from "./base.ts";
import { DEFAULT_CAT, catById } from "./presets.ts";
import { newPose } from "./geometry.ts";
import { drawCat, stillView } from "./renderer.ts";
import type { CatView, PawSpec } from "./renderer.ts";
import type { CatPreset, EyeShape } from "./types.ts";

const NOTCH = { W: NOTCH_W, H: NOTCH_H };
const COMPACT = COMPACT_W;
const FONT = 'system-ui, "Segoe UI Variable Text", "Segoe UI", sans-serif';

/**
 * The compact island's mini grid, which takes over from the greeting's session cats once the greeting ends: four Ø13 cats, 16 px apart,
 * centred 40 px in from the island's right edge and level with the middle of the strip (`applyGeometry` in island.ts, `#mini-grid` in style.css
 * and `createMiniBot(t, 13)`; a check keeps them together). In the greeting's 640 px canvas the island is centred.
 */
export const MINI_GRID = { d: 13, step: 16, x: 320 + COMPACT_W / 2 - 40, y: NOTCH_H / 2 };
const MINI_OFFSETS: readonly (readonly [number, number])[] = [[-1, -1], [1, -1], [-1, 1], [1, 1]];

/** The shared beats: the island's growth, badge, blink and tint, and when it collapses. */
export const GT = { grow: 0.45, badge: 2.72, blink2: 3.8, tint0: 3.85, tint1: 4.15, leave: 4.9, COLLAPSE: 0.34 };
/** The new greeting's beats: fall, land, bounce, slide aside, pop up, wave, slide back. */
export const GT2 = { fall0: 0.05, land: 0.62, bounce1: 1.18, slide0: 1.25, slide1: 1.65, pop0: 1.65, wave0: 1.72, wave1: 2.72, back0: 2.75, back1: 3.25, SLIDE: 150 };
export const GREET_LEN = GT.leave + GT.COLLAPSE + 0.5;

/** The streak burst: 16 coloured streaks from seed 7, the same on every platform. */
export const STREAKS = (() => {
  const r = rng(7), cols = ["#3B9EFF", "#F29B38", "#FF5A4E", "#2EC4A0", "#A78BFA"];
  return Array.from({ length: 16 }, (_, i) => ({ a: (i / 16) * TAU + (r() - 0.5) * 0.3, sp: 230 + r() * 260, len: 6 + r() * 9, t0: 0.08 + r() * 0.14, col: cols[i % 5] }));
})();
/** Streak burst time: it starts when the cat lands. */
export const streakTime = (t: number) => t - (GT2.land - 0.1);

export type GreetEye = "dot" | "happy" | "content";

/**
 * The greeting pose at t seconds, all in the 640×150 space: island iw×ih, cat centre x,y and head width hb×1.34,
 * squash sx/sy, tilt, eye shape, gaze lookX/lookY, paw raise handL/handR, wave clock (-1 = off), blink open,
 * and the 0…1 fades badge, tint, halo, haloBlue, header, card, fx (streaks), minis (the session cats).
 */
export interface GreetPose {
  iw: number; ih: number; hb: number; x: number; y: number; sx: number; sy: number; tilt: number;
  eye: GreetEye; lookX: number; lookY: number; handL: number; handR: number; wave: number; open: number;
  badge: number; tint: number; halo: number; haloBlue: number; header: number; card: number; fx: number; minis: number;
}
interface Base { iw: number; ih: number; hb: number; base: number; open: number; badge: number; tint: number; halo: number; haloBlue: number; header: number; card: number }

/** The island and the shared beats: size, blink, badge, tint, halo, header. Everything but the cat's own motion. */
function islandBase(t: number): Base {
  const gx = seg(t, 0, 0.5), g = Math.sin((Math.PI * gx) / 2) + 0.04 * Math.sin(Math.PI * gx) * gx, gg = EZ.back(seg(t, 0.02, GT.grow));
  const blink = (tb: number) => { const k = seg(t, tb, tb + 0.12); return k > 0 && k < 1 ? 1 - Math.sin(Math.PI * k) * 0.94 : 1; };
  return {
    iw: lerp(NOTCH.W, 640, g), ih: lerp(NOTCH.H, 150, g), hb: lerp(3, 58, gg), base: lerp(16, 86, EZ.out(seg(t, 0.02, GT.grow))),
    open: Math.min(blink(1.95), blink(GT.blink2)),
    badge: EZ.back(seg(t, GT.badge, GT.badge + 0.28)), tint: 0.6 * EZ.inOut(seg(t, GT.tint0, GT.tint1)), halo: EZ.out(seg(t, 0.3, 0.7)),
    haloBlue: seg(t, GT.tint0, GT.tint1), header: seg(t, 0.35, 0.6), card: seg(t, 0.18, 0.45),
  };
}

/** The cat's fall, bounce, slide, pop and wave. */
function fallPose(t: number, B: Base): GreetPose {
  const G = GT2, hb = B.hb, D = hb * 1.34, base = B.base;
  let x = 320, y = base, sx = 1, sy = 1, tilt = 0, eye: GreetEye = "dot", lookX = 0, lookY = 0, wave = -1;
  const fall = seg(t, G.fall0, G.land);
  y -= (1 - fall * fall) * (base + 70); // 1 fall in (accelerating)
  const sq = Math.sin(Math.PI * seg(t, G.land, G.land + 0.16));
  sy -= 0.2 * sq; sx += 0.14 * sq; y += D * 0.05 * sq; // landing squash
  const b = seg(t, G.land + 0.16, G.bounce1);
  y -= 4 * b * (1 - b) * hb * 0.3; sy += 0.05 * Math.sin(Math.PI * b); // 2 small bounce
  const sq2 = Math.sin(Math.PI * seg(t, G.bounce1, G.bounce1 + 0.1));
  sy -= 0.07 * sq2; sx += 0.05 * sq2; y += D * 0.02 * sq2;
  const out = EZ.inOut(seg(t, G.slide0, G.slide1)), ret = EZ.inOut(seg(t, G.back0, G.back1)); // 3 slide aside, 5 slide back
  x += G.SLIDE * out * (1 - ret);
  tilt = 0.1 * Math.sin(Math.PI * seg(t, G.slide0, G.slide1)) - 0.1 * Math.sin(Math.PI * seg(t, G.back0, G.back1));
  const ant = Math.sin(Math.PI * seg(t, G.pop0 - 0.1, G.pop0));
  sy -= 0.08 * ant; y += D * 0.03 * ant; // 4 pop up
  const pop = EZ.back(seg(t, G.pop0, G.pop0 + 0.2)) * (1 - EZ.inOut(seg(t, G.back0, G.back0 + 0.2)));
  y -= hb * 0.16 * pop; sy += 0.07 * Math.sin(Math.PI * seg(t, G.pop0, G.pop0 + 0.2));
  const flail = 0.55 * (1 - seg(t, G.land - 0.05, G.land + 0.1)) * (t > G.fall0 ? 1 : 0); // paws up while falling
  const handL = flail, handR = Math.max(flail, pop);
  if (t >= G.wave0 && t < G.wave1 + 0.2) wave = t - G.wave0;
  if (t >= G.land && t < G.slide0) eye = "happy";
  if (t >= G.slide0 && t < G.pop0) lookX = 0.5 * out;
  if (t >= G.pop0 && t < G.back0) { eye = "happy"; lookX = 0.3; lookY = -0.4; }
  if (t >= G.back0) { const k = seg(t, G.back0, G.back1 + 0.1); eye = k < 0.9 ? "content" : "dot"; lookX = lerp(0.3, 0, EZ.inOut(k)); lookY = lerp(-0.4, 0, EZ.inOut(k)); }
  return {
    iw: B.iw, ih: B.ih, hb, x, y, sx, sy, tilt, eye, lookX, lookY, handL, handR, wave, open: B.open, badge: B.badge, tint: B.tint, halo: B.halo,
    haloBlue: B.haloBlue, header: B.header, card: B.card, fx: 1, minis: 0,
  };
}

/** From `tc` the island collapses to the compact notch and the cat settles, from wherever it is. */
function collapsePose(t: number, tc: number): GreetPose {
  const a = islandBase(tc), f = fallPose(tc, a), e = EZ.inOut(seg(t, tc, tc + GT.COLLAPSE)), bx = 320 - COMPACT / 2 + 40, bk = seg(t, tc + 0.14, tc + 0.26);
  const hands = 1 - seg(t, tc, tc + 0.15);
  return {
    iw: lerp(a.iw, COMPACT, e), ih: lerp(a.ih, 32, e), hb: lerp(f.hb, 20 / 1.34, e), x: lerp(f.x, bx, e), y: lerp(f.y, 16, e),
    sx: lerp(f.sx, 1, e), sy: lerp(f.sy, 1, e), tilt: f.tilt * (1 - e), eye: "dot", lookX: f.lookX * (1 - e), lookY: f.lookY * (1 - e),
    handL: f.handL * hands, handR: f.handR * hands, wave: -1,
    open: bk > 0 && bk < 1 ? 1 - Math.sin(Math.PI * bk) * 0.94 : 1, badge: a.badge, tint: a.tint, halo: a.halo * (1 - e), haloBlue: a.haloBlue,
    header: a.header * (1 - seg(t, tc, tc + 0.1)), card: a.card * (1 - seg(t, tc, tc + 0.18)), fx: 1 - seg(t, tc, tc + 0.2), minis: EZ.back(seg(t, tc + 0.24, tc + 0.42)),
  };
}

/** The greeting pose at t seconds. `leave` is when the island collapses (GT.leave unless the pointer left early). */
export const greetingPose = (t: number, leave = GT.leave): GreetPose => (t < leave ? fallPose(t, islandBase(t)) : collapsePose(t, leave));

// ── The controller and the drawing ────────────────────────────────────────────

/** The controller fires onComplete here (s). The collapse itself waits until GT.leave unless the pointer leaves first. */
export const GREETING_END = 4.6;

const CARD = { x: 10, y: 36, w: 620, h: 104 };
const CARD_R = 20;

function rr(x: CanvasRenderingContext2D, X: number, Y: number, W: number, H: number, R: number) {
  const r = Math.max(0, Math.min(R, W / 2, H / 2));
  x.beginPath(); x.moveTo(X + r, Y); x.arcTo(X + W, Y, X + W, Y + H, r); x.arcTo(X + W, Y + H, X, Y + H, r); x.arcTo(X, Y + H, X, Y, r); x.arcTo(X, Y, X + W, Y, r); x.closePath();
}

/** A session cat of the compact grid, in the greeting's blue: the tint the greeting ends with. */
function miniView(p: CatPreset): CatView {
  const v = stillView(p, { ...newPose(), tint: 0.6 });
  v.col = [127, 180, 234];
  return v;
}

/** The greeting cat's view: the pose is driven by the timeline, not by an engine. */
function greetView(id: string, eye: () => EyeShape): CatView {
  const v = stillView(catById(id), newPose());
  v.eyeShape = eye;
  v.badge = "dots";
  v.badgeCol = "#3BA0F5";
  v.col = [127, 180, 234];
  v.now = () => performance.now();
  return v;
}

/**
 * Runs the greeting on its own canvas. `onComplete` fires once at GREETING_END (or right after the collapse when
 * interrupted) so the island's state machine can move on.
 */
export class Greeting {
  private startMs = 0;
  private tc = Number.POSITIVE_INFINITY;
  private fired = false;
  private timers: number[] = [];
  private eye: EyeShape = "pill";
  private view: CatView = greetView(DEFAULT_CAT, () => this.eye);
  private minis: CatView = miniView(catById(DEFAULT_CAT));

  onComplete: (() => void) | null = null;

  start() {
    this.startMs = performance.now();
    this.tc = Number.POSITIVE_INFINITY;
    this.fired = false;
    this.view = greetView(DEFAULT_CAT, () => this.eye);
    this.minis = miniView(this.view.p);
    this.cancelTimers();
    this.timers.push(
      window.setTimeout(() => Sound.play("greet"), GT2.pop0 * 1000),
      window.setTimeout(() => Sound.play("blip"), GT.badge * 1000),
      window.setTimeout(() => this.fire(), (GREETING_END + 0.05) * 1000),
    );
  }

  /** Mouse entered the island during the greeting: hold it open. */
  hover() {
    if (this.tc >= GT.leave) this.tc = Number.POSITIVE_INFINITY;
  }

  /** Mouse left: collapse from now. */
  interrupt() {
    const t = (performance.now() - this.startMs) / 1000;
    if (!Number.isFinite(this.tc) || this.tc > t) this.tc = t;
    this.cancelTimers();
  }

  get elapsed(): number { return (performance.now() - this.startMs) / 1000; }
  get done(): boolean { return this.fired; }

  private fire() {
    if (this.fired) return;
    this.fired = true;
    this.cancelTimers();
    this.onComplete?.();
  }
  private cancelTimers() {
    this.timers.forEach((id) => window.clearTimeout(id));
    this.timers = [];
  }

  draw(x: CanvasRenderingContext2D) {
    const t = this.elapsed;
    if (!this.fired && t >= GREETING_END && this.tc >= GT.leave) this.fire();
    const leave = Number.isFinite(this.tc) ? Math.min(this.tc, GT.leave) : GT.leave;
    const P = greetingPose(t, leave);
    x.clearRect(0, 0, 640, 150);

    if (P.card > 0) {
      x.save(); x.globalAlpha = P.card; rr(x, CARD.x, CARD.y, CARD.w, CARD.h, CARD_R); x.fillStyle = "#141518"; x.fill(); x.restore();
      x.save(); rr(x, CARD.x, CARD.y, CARD.w, CARD.h, CARD_R); x.clip();
      const st = streakTime(t);
      for (const sk of STREAKS) {
        const q = seg(st, sk.t0, sk.t0 + 0.6);
        if (q <= 0 || q >= 1) continue;
        const dist = sk.sp * EZ.out(q) * 0.9 + 10;
        x.strokeStyle = sk.col; x.globalAlpha = (1 - q) * P.fx; x.lineWidth = 1.6; x.lineCap = "round"; x.beginPath();
        x.moveTo(P.x + Math.cos(sk.a) * (dist - sk.len), P.y + Math.sin(sk.a) * (dist - sk.len) * 0.42);
        x.lineTo(P.x + Math.cos(sk.a) * dist, P.y + Math.sin(sk.a) * dist * 0.42);
        x.stroke();
      }
      x.restore();
    }

    const D = P.hb * 1.34;
    if (D <= 0.5) return;
    // Halo: golden, then blue, two passes for a soft aura.
    if (P.halo > 0) {
      const bl = P.haloBlue, c = [lerp(232, 59, bl), lerp(195, 158, bl), lerp(154, 255, bl)].map(Math.round);
      for (const [rad, al] of [[D * 1.3, 0.18], [D * 2.1, 0.07]]) {
        const g = x.createRadialGradient(P.x, P.y, 0, P.x, P.y, rad);
        g.addColorStop(0, `rgba(${c},${al * P.halo})`); g.addColorStop(1, `rgba(${c},0)`);
        x.fillStyle = g; x.fillRect(P.x - rad, P.y - rad, rad * 2, rad * 2);
      }
    }

    // The header: the app's name on the left, a greeting on the right, fading in with the card.
    if (P.header > 0.01) {
      x.save(); x.globalAlpha = P.header; x.textBaseline = "middle";
      x.fillStyle = "#fff"; x.font = `600 13px ${FONT}`; x.textAlign = "left"; x.fillText("NotchMeow", 20, 20);
      x.fillStyle = "#8d9098"; x.font = `11.5px ${FONT}`; x.textAlign = "right"; x.fillText(`Hi! ${this.view.p.label} is watching your agents.`, 620, 20);
      x.restore();
    }

    // The cat: the timeline drives the pose directly.
    const v = this.view, s = v.s;
    Object.assign(s, { sx: P.sx, sy: P.sy, tilt: P.tilt, open: P.open, yaw: P.lookX * 0.55, pitch: -P.lookY * 0.45, roll: 0, oy: 0, ox: 0, badgeS: P.badge, tint: P.tint, paws: 0 });
    this.eye = P.eye === "happy" ? "happy" : P.eye === "content" ? "closed" : "pill";
    const R = D / (2 * v.p.rx), rx = v.p.rx * R, ry = v.p.ry * R;
    const on = P.wave >= 0, w = on ? P.wave * TAU * 4.2 : 0, wa = on ? seg(P.wave, 0, 0.12) * (1 - seg(P.wave, 0.9, 1.0)) : 0;
    const paws: PawSpec[] = [
      { x: lerp(-0.35 * rx, -(rx + 0.22 * R), P.handL), y: lerp(0.85 * ry, 0.62 * ry, P.handL), k: P.handL, rot: -0.2, beans: false },
      { x: lerp(0.35 * rx, rx + 0.2 * R, P.handR) + Math.cos(w) * ry * 0.05 * wa, y: lerp(0.85 * ry, 0.05 * ry, P.handR) + Math.sin(w + 0.8) * ry * 0.1 * wa, k: P.handR, rot: 0.3 + Math.sin(w) * 0.45 * wa, beans: true },
    ];
    drawCat(x, v, P.x, P.y, D, { paws, badgeSide: 1 - 2 * EZ.inOut(seg(t, leave, leave + GT.COLLAPSE)) });

    // The session cats of the compact grid pop in with a scale as the island collapses; the real grid takes over after the greeting.
    if (P.minis > 0.01) {
      for (const [dx, dy] of MINI_OFFSETS) {
        x.save(); x.translate(MINI_GRID.x + (dx * MINI_GRID.step) / 2, MINI_GRID.y + (dy * MINI_GRID.step) / 2); x.scale(P.minis, P.minis);
        drawCat(x, this.minis, 0, 0, MINI_GRID.d, { badge: false });
        x.restore();
      }
    }
  }
}
```

- [ ] **Step 4: Run the tests and the type checks**

Run: `npm run check:cat && npx tsc --noEmit`
Expected: all pass. The greeting test checks the beats and streaks, 70 samples of the pose across the 5.74 s, a greeting cut short at six moments (continuous at the cut, settling in the compact notch), and no bad number before the start or long after the end.

- [ ] **Step 5: Add the greeting to the contact sheet**

Above `// @@S4-IMPORT-GREETING` in `windows/src/cat/dev.ts`:

```ts title="windows/src/cat/dev.ts" above="@@S4-IMPORT-GREETING"
import { Greeting } from "./greeting.ts";
```

Above `// @@S4-GREETING-PANEL`:

```ts title="windows/src/cat/dev.ts" above="@@S4-GREETING-PANEL"
  // ── Stage 4: the greeting ──
  const greetBox = section("Greeting", "The launch greeting: the cat falls in with a landing squash, bounces, slides aside, pops up for a paw wave, then slides back and settles. Move the pointer out of the page, then press Collapse, to see it cut short.");
  const gHolder = document.createElement("div");
  gHolder.style.cssText = "width:640px;max-width:100%;height:150px;background:#000;border-radius:0 0 22px 22px;overflow:hidden;margin-top:12px";
  const gCv = document.createElement("canvas");
  gHolder.append(gCv);
  let greeting = new Greeting();
  greeting.start();
  const gRow = row("Greeting");
  gRow.append(button("Replay", () => { greeting = new Greeting(); greeting.start(); }), button("Collapse now", () => greeting.interrupt()));
  greetBox.append(gRow, gHolder);
  root.insertBefore(greetBox, wrap);
  ticks.push(() => greeting.draw(fit(gCv, 640, 150)));
```

Run: `npx tsc --noEmit`
Expected: no output.

- [ ] **Step 6: Look at the real greeting in the island**

The island's launch greeting runs on page load in a plain browser. Drive it with a fake clock so the screenshots are repeatable:

```bash
WT="$(git rev-parse --show-toplevel)"; cd "${TMPDIR:-/tmp}/a-tauri-shots"
(cd "$WT/windows" && npx vite > vite.log 2>&1 &)
cat > greeting-shots.js <<'EOF'
async page => {
  await page.setViewportSize({ width: 720, height: 320 });
  await page.clock.install();
  await page.goto("http://127.0.0.1:1420/");
  const shots = [[500, "a-fall"], [900, "b-land"], [1500, "c-slide"], [2100, "d-wave"], [2600, "e-wave"], [3100, "f-back"], [3700, "g-settle"], [4400, "h-badge"], [6500, "i-compact"]];
  let t = 0;
  for (const [at, name] of shots) { await page.clock.runFor(at - t); t = at; await page.screenshot({ path: `greeting-${name}.png` }); }
}
EOF
playwright-cli -s=island open about:blank
playwright-cli -s=island run-code --filename=greeting-shots.js
```

By eye, in order: the header ("NotchMeow" at the left edge, "Hi! Shrimpy is watching your agents." at the right, in grey) is there from the first frames after (a); the cat falls in and lands with a squash (b), slides aside with a tilt (c), pops up and waves a paw with its toe beans out (d, e), slides back and settles with the badge and the blue tint (f, g, h), and the island ends compact with the Ø20 cat and, to its right, the four blue session cats in a 2 by 2 grid (i): they pop in with a little overshoot as the island closes, and the real mini grid (empty in the browser, where there are no agent sessions) takes their place afterwards. Compare the greeting with the prototype's (`playwright-cli -s=proto` on its Greeting panel): the header and the session cats are the same idea at this app's grid size. Also open the contact sheet's Greeting panel and press "Replay", and press "Collapse now" during the wave to see it cut short. Fix `greeting.ts` if anything is wrong, then:

```bash
playwright-cli close-all
kill $(lsof -ti tcp:1420)
```

- [ ] **Step 7: Commit**

```bash
git add windows/src/cat/greeting.ts windows/src/cat/dev.ts windows/scripts/cat-tests/greeting.test.mjs
git commit -m "feat(cat): the new greeting, a cat falling in, with a paw wave

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 12: The drop view catches the file, and coughs a refused one up

**Agent:** `nm-implementer`.

**Files:**
- Create: `windows/src/upload/refusal.ts`
- Test: `windows/scripts/cat-tests/refusal.test.mjs`
- Replace: `windows/src/upload/canvas.ts`
- Modify: `windows/src/upload/sequence.ts`, `windows/src/island/island.ts`, `windows/dev/upload-preview.ts`

**Interfaces:**
- Consumes: `BotEngine` (`fileHover`, `fileDrop`, `fileRefuse`, `fileArrived`, `fileStep`, `mouthAt`, `base`, `lookX`, `lookY`, `update`), `drawCat`, `FLIGHT_MS`, `flightAt`, `catById`/`DEFAULT_CAT`; the sequence's `UploadFrame` (unchanged).
- Produces `src/upload/refusal.ts`: `REFUSAL_NOTES` (the two texts Rust gives for a refused file), `classifyIngestError(err: unknown): { message: string; refused: boolean }` and `noteSound(refused: boolean): "error" | null` (the sound that goes with the note: none for a refusal, `error` for any other failure).
- Produces: `UploadCanvas.hover(on)`, `.drop(name)`, `.refuse()`; `UploadSeq.refused` and `UploadSeq.refuse()` (the timeline holds at the moment the file reaches the mouth, so no upload is shown for a refused file).
- The drop view's mailbox (the body morph, the slot, the cup eyes and the strips that funnelled the file in) is replaced by the cat: it opens wide while a file hovers, snaps wider on the drop while the file arcs into its mouth over `FLIGHT_MS`, gulps and chews for 0.85 s with happy eyes, then shrinks into the progress ball and grows back for the choose card, as the old character did. The file is drawn in front of the cat, hovering and flying, as in the prototype's catch (the original drop view did the same).
- **A refused file** (`Bridge.ingestFile` rejects with one of the two texts of `attachments::reject_message`: an app, an archive, a disk image or a video; or a file over 25 MB) is caught like any other: open wide, snap wider, the file flies in. Then the cat gags and coughs it up as a hairball (2.4 s, after the 120 ms it takes to start), and then the existing note shows. No check mark (the sequence holds), and no approve chime: the island plays `approve` when the ingest succeeds, no longer at the drop. **The sounds of a refusal:** the cat plays `annoyed` once, as the gag starts (`BotEngine.catchReject`, Task 10); the note plays none (`noteSound(true)`). The `pop` at the cough is wired later, by sound Stage 3: not here. **Any other failure** (a folder, an unreadable file, a failed copy, no Tauri) keeps today's behaviour and sound: the note at once with its `error` sound (`noteSound(false)`), no hairball.
- The island's own cat is hidden while the drop view is up (as before), so the island still calls `engine.gulp()` and the morph shims on a hidden canvas; they are removed in stage 7.

- [ ] **Step 1: Write the failing test for the refusal classifier**

How Rust decides: `files::ingest` calls `attachments::screen`, and for `Classified::Rejected(reason)` returns `Err(attachments::reject_message(reason))`: "Files over 25 MB are too big for me." or "I can't read this kind of file." Every other failure (a folder, `cannot read …`, `cannot copy: …`) is a different string. The island only sees the string, so it tells the two apart by those two texts, and this test pins them to the Rust source: if the copy is ever changed there, the hairball would silently stop, and this test fails first.

Create `windows/scripts/cat-tests/refusal.test.mjs`:

```js title="windows/scripts/cat-tests/refusal.test.mjs"
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { REFUSAL_NOTES, classifyIngestError, noteSound } from "../../src/upload/refusal.ts";

const rust = (file) => fs.readFileSync(new URL(`../../src-tauri/src/${file}`, import.meta.url), "utf8");

test("the refusal texts are exactly the ones Rust gives for a refused file", () => {
  const fn = rust("ai/attachments.rs").match(/pub fn reject_message[\s\S]*?\n\}/)[0];
  const texts = [...fn.matchAll(/=> "([^"]+)"/g)].map((m) => m[1]);
  assert.equal(texts.length, 2, "one text for the size, one for the type");
  assert.deepEqual([...REFUSAL_NOTES].sort(), texts.sort());
  assert.match(rust("files.rs"), /Rejected\(reason\)[\s\S]*reject_message\(reason\)/, "ingest returns those texts for a refused file");
});

test("a refusal is told from every other way ingest can fail, however the error arrives", () => {
  for (const note of REFUSAL_NOTES) for (const err of [note, `Error: ${note}`, new Error(note)]) {
    assert.deepEqual(classifyIngestError(err), { message: note, refused: true }, String(err));
  }
  // The other failures of files::ingest, and what the browser gives when there is no Tauri.
  for (const other of ["Folders can't be dropped yet.", "cannot read C:\\a.txt: Access is denied. (os error 5)", "cannot copy: There is not enough space on the disk. (os error 112)", "not running inside NotchMeow", "", "I can't read this kind of file. Really."]) {
    const c = classifyIngestError(other);
    assert.equal(c.refused, false, other);
    assert.equal(c.message, other);
  }
  for (const odd of [undefined, null, 42, {}, ["I can't read this kind of file."]]) assert.equal(typeof classifyIngestError(odd).message, "string");
  assert.equal(classifyIngestError(undefined).refused, false);
  assert.ok(rust("files.rs").includes("Folders can't be dropped yet."), "a folder still gets its own text");
});

test("the note of a refusal is silent (the cat's annoyed at the gag is its only sound); any other failure keeps its error sound", () => {
  assert.equal(noteSound(true), null);
  assert.equal(noteSound(false), "error");
  for (const note of REFUSAL_NOTES) assert.equal(noteSound(classifyIngestError(note).refused), null, note);
  for (const other of ["Folders can't be dropped yet.", "cannot copy: disk full", "not running inside NotchMeow", undefined]) {
    assert.equal(noteSound(classifyIngestError(other).refused), "error", String(other));
  }
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npm run check:cat`
Expected: FAIL. `refusal.test.mjs` cannot load `src/upload/refusal.ts` (`ERR_MODULE_NOT_FOUND`).

- [ ] **Step 3: Create the classifier**

Create `windows/src/upload/refusal.ts`:

```ts title="windows/src/upload/refusal.ts"
// Which failures of `ingest_file` are the app refusing a file, and which are not.
//
// Rust decides (files::ingest calls attachments::screen: an app, an archive, a disk image, a video, or anything over 25 MB is
// `Classified::Rejected`) and reports it as a text, `attachments::reject_message`. The island only receives that text, so it
// recognises the two. A test (scripts/cat-tests/refusal.test.mjs) pins them to the Rust source.
// Imports nothing, so the plain-Node checks (npm run check:cat) can load it as it is.

/** The two texts Rust gives for a refused file: too big, or a kind of file the cat can't read. */
export const REFUSAL_NOTES: readonly string[] = ["Files over 25 MB are too big for me.", "I can't read this kind of file."];

/**
 * The note to show for a failed ingest, and whether it is a refusal. A refusal is caught, gagged on and coughed back up as a hairball
 * before the note; any other failure (a folder, an unreadable file, a failed copy) shows the note at once.
 */
export function classifyIngestError(err: unknown): { message: string; refused: boolean } {
  const message = String(err).replace(/^Error:\s*/, "");
  return { message, refused: REFUSAL_NOTES.includes(message) };
}

/**
 * The sound that goes with the note of a failed ingest. The note of a refusal is silent: the cat has already played `annoyed` once,
 * as it started to gag (`BotEngine.catchReject`), and sound Stage 3 adds the `pop` at the cough in the engine, not here. Any other
 * failure keeps today's `error` with its note.
 */
export function noteSound(refused: boolean): "error" | null {
  return refused ? null : "error";
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npm run check:cat && npx tsc --noEmit`
Expected: all pass.

- [ ] **Step 5: Let the sequence hold for a refused file**

In `windows/src/upload/sequence.ts`, replace:

```ts title="windows/src/upload/sequence.ts" old
  isActive = false;

  cursorX = 600;
```

with:

```ts title="windows/src/upload/sequence.ts" new
  isActive = false;

  /** The file is one the cat refuses: the timeline holds when the file reaches the mouth, so no upload is shown. */
  refused = false;

  cursorX = 600;
```

Replace:

```ts title="windows/src/upload/sequence.ts" old
    this.dropWall = null;
    this.isActive = true;
```

with:

```ts title="windows/src/upload/sequence.ts" new
    this.dropWall = null;
    this.refused = false;
    this.isActive = true;
```

Replace:

```ts title="windows/src/upload/sequence.ts" old
  deactivate() {
    this.isActive = false;
    this.dropWall = null;
  }
```

with:

```ts title="windows/src/upload/sequence.ts" new
  /** The app can't take the dropped file. */
  refuse() {
    this.refused = true;
  }

  deactivate() {
    this.isActive = false;
    this.dropWall = null;
    this.refused = false;
  }
```

Replace:

```ts title="windows/src/upload/sequence.ts" old
    if (this.dropWall != null) return USC.T_DROP + Math.max(0, now - this.dropWall);
```

with:

```ts title="windows/src/upload/sequence.ts" new
    if (this.dropWall != null) {
      const t = USC.T_DROP + Math.max(0, now - this.dropWall);
      return this.refused ? Math.min(t, USC.T_SUCK_END) : t;
    }
```

- [ ] **Step 6: Replace the drop canvas**

Overwrite `windows/src/upload/canvas.ts`. Everything outside the cat (the card, the dashed frame, the drop text, the progress bar, the choose card, the document icon) is the file's own code, unchanged; the mailbox body and eyes are gone and the cat takes their place:

```ts title="windows/src/upload/canvas.ts"
// The upload canvas — port of UploadCanvasView.swift.
//
// While the sequence engine is active this canvas draws the whole island body:
// card, dashed drop frame, drop text, progress bar, the choose card, the cat and
// the file flying into its mouth. The island's own cat is hidden for the duration,
// because this canvas draws its own: it catches the file in four steps (open wide
// while the file hovers, snap wider on the drop, gulp with a squash, chew for 0.85 s
// with happy eyes), and coughs a refused file back up as a hairball. The file is
// drawn in front of the cat, hovering and flying, as in the prototype's catch.

import { BotEngine } from "../cat/engine";
import { FLIGHT_MS, flightAt } from "../cat/geometry";
import { DEFAULT_CAT, catById } from "../cat/presets";
import { drawCat } from "../cat/renderer";
import { State } from "../core/state";
import { USC, lerp, progressAt, type UploadFrame } from "./sequence";

const FONT = 'system-ui, "Segoe UI Variable Text", "Segoe UI", sans-serif';

/** Mirrors the reference `rr()`: a rounded rect, radius clamped to the box. */
function rr(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  const rad = Math.max(0, Math.min(r, w / 2, h / 2));
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, rad);
}

function text(
  ctx: CanvasRenderingContext2D,
  s: string,
  x: number,
  y: number,
  font: string,
  color: string,
  align: CanvasTextAlign = "left",
) {
  ctx.font = font;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  // SwiftUI's .leading / .center / .trailing anchors are vertically centred.
  ctx.textBaseline = "middle";
  ctx.fillText(s, x, y);
}

export interface UploadCanvasActions {
  /** Primary button — hand the file to the chat. */
  ask(): void;
  /** Secondary button. */
  cancel(): void;
}

export class UploadCanvas {
  /** Wrapper holding the canvas and the two invisible choose buttons. */
  readonly el: HTMLElement;

  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D | null;
  private overlay: HTMLElement;
  private sizedFor = 0;

  /** The drop view's cat. */
  readonly cat = new BotEngine(catById(DEFAULT_CAT));
  private lastWall = 0;

  constructor(actions: UploadCanvasActions) {
    this.canvas = document.createElement("canvas");
    this.canvas.id = "upload-canvas";

    // Invisible hit areas at the reference button positions. The labels are
    // painted on the canvas; these only catch the click.
    const mk = (x: number, w: number, onclick: () => void) => {
      const b = document.createElement("button");
      b.className = "upload-hit";
      b.style.left = `${x}px`;
      b.style.top = "113px";
      b.style.width = `${w}px`;
      b.style.height = "26px";
      b.addEventListener("click", onclick);
      return b;
    };
    this.overlay = document.createElement("div");
    this.overlay.id = "upload-overlay";
    this.overlay.append(mk(114, 168, actions.ask), mk(290, 120, actions.cancel));

    this.el = document.createElement("div");
    this.el.id = "upload-layer";
    this.el.append(this.canvas, this.overlay);

    this.ctx = this.canvas.getContext("2d");
  }

  /** A file is over the island (true) or left it (false): the cat opens wide, or closes its mouth again. */
  hover(on: boolean) { this.cat.fileHover(on); }

  /** The file was dropped: the cat snaps wider while the file flies in. */
  drop(name: string) { this.cat.fileDrop(name); }

  /** The app can't take this file: the cat coughs it back up as a hairball once it has swallowed it. */
  refuse() { this.cat.fileRefuse(); }

  /** `wallTime` in seconds drives the marching dashes, like the macOS timeline. */
  draw(f: UploadFrame, wallTime: number) {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (this.sizedFor !== dpr) {
      this.sizedFor = dpr;
      this.canvas.width = Math.round(USC.W * dpr);
      this.canvas.height = Math.round(USC.ISL_H * dpr);
      this.canvas.style.width = `${USC.W}px`;
      this.canvas.style.height = `${USC.ISL_H}px`;
    }
    const ctx = this.ctx;
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, USC.W, USC.ISL_H);

    // The cat moves on the wall clock, whatever the sequence says about the file.
    const dt = this.lastWall ? Math.min(0.05, Math.max(0, wallTime - this.lastWall)) : 0;
    this.lastWall = wallTime;
    this.cat.lookX = f.lookX;
    this.cat.lookY = f.lookY;
    this.cat.update(dt);

    this.drawScene(ctx, f, wallTime);

    // The buttons only exist once the choose card has faded in.
    this.overlay.style.display = f.chooseAlpha > 0.5 ? "block" : "none";
  }

  // ── Scene ─────────────────────────────────────────────────────────────────

  private drawScene(ctx: CanvasRenderingContext2D, f: UploadFrame, wallTime: number) {
    // Island background.
    ctx.fillStyle = "#000000";
    ctx.fillRect(0, 0, USC.W, USC.ISL_H);

    // Card.
    ctx.save();
    rr(ctx, USC.CARD_X, USC.CARD_Y, USC.CARD_W, USC.CARD_H, USC.CARD_R);
    ctx.clip();
    ctx.fillStyle = "#0D0E10";
    ctx.fillRect(USC.CARD_X, USC.CARD_Y, USC.CARD_W, USC.CARD_H);

    // Green glow, fanning up from the bottom edge of the card.
    if (f.greenWash > 0) {
      const gx = USC.CARD_X + USC.CARD_W / 2;
      const gy = USC.CARD_Y + USC.CARD_H;
      const g = ctx.createRadialGradient(gx, gy, 0, gx, gy, USC.CARD_H * 1.5);
      g.addColorStop(0, `rgba(40,212,130,${f.greenWash * 0.9})`);
      g.addColorStop(0.55, `rgba(40,212,130,${f.greenWash * 0.3})`);
      g.addColorStop(1, "rgba(40,212,130,0)");
      ctx.fillStyle = g;
      ctx.fillRect(USC.CARD_X, USC.CARD_Y, USC.CARD_W, USC.CARD_H);
    }
    ctx.restore();

    // Dashed border, marching left to right at ~20 pt/s.
    if (f.zoneAlpha > 0) {
      ctx.save();
      ctx.globalAlpha = f.zoneAlpha;
      ctx.strokeStyle = f.zoneOver ? "rgba(52,212,153,0.55)" : "rgba(255,255,255,0.14)";
      ctx.lineWidth = 1.5;
      ctx.setLineDash([6, 5]);
      ctx.lineDashOffset = -wallTime * 20;
      rr(ctx, USC.CARD_X + 0.75, USC.CARD_Y + 0.75, USC.CARD_W - 1.5, USC.CARD_H - 1.5, USC.CARD_R - 0.5);
      ctx.stroke();
      ctx.restore();
    }

    if (f.zoneAlpha > 0 && f.textAlpha > 0) this.drawDropText(ctx, f);
    if (f.barAlpha > 0 || f.barReveal > 0) this.drawProgressBar(ctx, f);
    if (f.chooseAlpha > 0) this.drawChoose(ctx, f);

    // The cat first, then the file: in front of the cat while it hovers and while it flies in, as in the prototype's catch.
    this.drawCat(ctx, f);
    this.drawFile(ctx, f);
  }

  // ── Drop zone text and chips ──────────────────────────────────────────────

  private drawDropText(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    ctx.save();
    ctx.globalAlpha = f.textAlpha;
    text(ctx, "Drop your files here", USC.TEXT_X, USC.TEXT_Y - 4, `500 13px ${FONT}`, "#D5D7DB");

    let cx = USC.TEXT_X;
    for (const chip of ["PDF", "Images", "Code", "Docs"]) {
      // The macOS port measures chips the same rough way, so the row lines up.
      const w = chip.length * 6.5 + 16;
      ctx.fillStyle = "rgba(255,255,255,0.07)";
      rr(ctx, cx, USC.TEXT_Y + 9, w, 18, 9);
      ctx.fill();
      text(ctx, chip, cx + 8, USC.TEXT_Y + 18, `500 11px ${FONT}`, "#B9BDC4");
      cx += w + 6;
    }
    ctx.restore();
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  private drawProgressBar(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    ctx.save();
    ctx.globalAlpha = Math.max(f.barAlpha, 0.001);

    const x0 = USC.BAR_X0;
    const x1 = USC.BAR_X1;
    const by = USC.BAR_Y;
    const barLen = (x1 - x0) * f.barReveal;

    const name = State.droppedFile?.name ?? "file";
    text(ctx, `Uploading ${name}`, x0, by - 30, `500 12.5px ${FONT}`, "#A9ADB5");

    if (f.check > 0) {
      ctx.save();
      ctx.translate(x1 - 8, by - 30);
      ctx.scale(f.check, f.check);
      ctx.beginPath();
      ctx.arc(0, 0, 8, 0, Math.PI * 2);
      ctx.fillStyle = "#34D399";
      ctx.fill();
      ctx.beginPath();
      ctx.moveTo(-3.6, 0.2);
      ctx.lineTo(-1, 2.8);
      ctx.lineTo(3.8, -2.6);
      ctx.strokeStyle = "#07130E";
      ctx.lineWidth = 2;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.stroke();
      ctx.restore();
    } else {
      text(ctx, `${Math.round(f.progress * 100)} %`, x1, by - 30, `500 12.5px ${FONT}`, "#A9ADB5", "right");
    }

    // Track.
    if (barLen > 0) {
      ctx.fillStyle = "rgba(255,255,255,0.08)";
      rr(ctx, x0, by - 3, barLen, 6, 3);
      ctx.fill();
    }

    // Fill.
    const fx = lerp(x0, x1, f.progress);
    if (fx > x0 + 1) {
      const flashGreen = `rgb(${Math.round(lerp(52, 110, f.flash))},${Math.round(
        lerp(211, 231, f.flash),
      )},${Math.round(lerp(153, 183, f.flash))})`;
      const g = ctx.createLinearGradient(x0, 0, fx, 0);
      g.addColorStop(0, "#1FA87A");
      g.addColorStop(1, flashGreen);
      ctx.fillStyle = g;
      rr(ctx, x0, by - 3, fx - x0, 6, 3);
      ctx.fill();
    }

    // Glow trail, its length driven by how fast the bar is moving.
    if (f.progress > 0.01 && f.progress < 1) {
      const v =
        (progressAt(f.t + 0.01, USC.T_PROG_START, f.progEnd) -
          progressAt(f.t, USC.T_PROG_START, f.progEnd)) / 0.01;
      const tl = Math.max(8, Math.min(34, 8 + v * 40));
      const g = ctx.createLinearGradient(fx - tl, 0, fx, 0);
      g.addColorStop(0, "rgba(52,212,153,0)");
      g.addColorStop(1, "rgba(110,231,183,0.6)");
      ctx.save();
      ctx.filter = "blur(3px)";
      ctx.fillStyle = g;
      rr(ctx, fx - tl, by - 4, tl, 8, 4);
      ctx.fill();
      ctx.restore();
    }
    ctx.restore();
  }

  // ── Choose card ───────────────────────────────────────────────────────────

  private drawChoose(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    ctx.save();
    ctx.globalAlpha = f.chooseAlpha;
    ctx.translate(0, (1 - f.chooseAlpha) * 4);

    const name = State.droppedFile?.name ?? "file";
    text(ctx, `${name} is ready.`, 114, 80, `600 14px ${FONT}`, "#F5F6F8");
    const sub = State.dropReader ? `${State.dropReader} will read this.` : "What do you want to do with it?";
    text(ctx, sub, 114, 100, `400 12.5px ${FONT}`, "#9398A1");

    ctx.fillStyle = "#F5F6F8";
    rr(ctx, 114, 113, 168, 26, 13);
    ctx.fill();
    text(ctx, "Ask a question about it", 198, 126, `500 12.5px ${FONT}`, "#0B0C0E", "center");

    ctx.fillStyle = "rgba(255,255,255,0.09)";
    rr(ctx, 290, 113, 120, 26, 13);
    ctx.fill();
    text(ctx, "Cancel", 350, 126, `500 12.5px ${FONT}`, "#F1F2F4", "center");
    ctx.restore();
  }

  // ── The cat, and the file flying into its mouth ───────────────────────────

  private drawCat(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    // The file has reached the mouth: gulp and chew, or, for a refused file, gag.
    if (!f.fileVisible) this.cat.fileArrived();
    // After the chew the cat shrinks into the progress ball and stretches with its speed: the sequence's own squash.
    const travelling = f.t >= USC.T_CHEW_END;
    drawCat(ctx, this.cat, f.x, f.y + f.hop, f.d, { tilt: f.tilt, squash: travelling ? [f.sx, f.sy] : undefined, badge: false });
  }

  private drawFile(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    if (!f.fileVisible) return;
    const cx = f.cursorX, cy = f.cursorY + 14;
    const m = this.cat.mouthAt, b = this.cat.base;
    if (this.cat.fileStep !== "flying" || !m || !b) {
      ctx.save();
      ctx.globalAlpha = 0.92;
      drawDoc(ctx, cx, cy, 1, 1);
      ctx.restore();
      return;
    }
    // Dropped: the file arcs into the mouth over FLIGHT_MS and shrinks on the way.
    const k = Math.max(0, Math.min(1, (f.t - USC.T_DROP) / (FLIGHT_MS / 1000)));
    const w = flightAt({ x: cx, y: cy }, m, b.R, k);
    const sc = w.size / (0.62 * b.R);
    ctx.save();
    ctx.translate(w.x, w.y);
    ctx.rotate(w.rot);
    drawDoc(ctx, 0, 0, sc, sc);
    ctx.restore();
  }
}

// ── Document icon ───────────────────────────────────────────────────────────

/**
 * The generic sheet with a folded corner. macOS swaps in the real file icon from
 * NSWorkspace; Windows has no equivalent reachable from the webview, so this is
 * the shape in every case — it is the same fallback the Swift draws.
 */
function drawDoc(ctx: CanvasRenderingContext2D, cx: number, cy: number, wsc: number, hsc: number) {
  const w = 34 * wsc;
  const h = 42 * hsc;
  const x = cx - w / 2;
  const y = cy - h / 2;
  const fold = 8 * Math.min(wsc, hsc);

  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,0.45)";
  ctx.shadowBlur = 8;
  ctx.shadowOffsetY = 3;
  ctx.beginPath();
  ctx.moveTo(x + 2, y);
  ctx.lineTo(x + w - fold, y);
  ctx.lineTo(x + w, y + fold);
  ctx.lineTo(x + w, y + h - 2);
  ctx.quadraticCurveTo(x + w, y + h, x + w - 2, y + h);
  ctx.lineTo(x + 2, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - 2);
  ctx.lineTo(x, y + 2);
  ctx.quadraticCurveTo(x, y, x + 2, y);
  ctx.closePath();
  ctx.fillStyle = "#F4F4F6";
  ctx.fill();
  ctx.restore();

  ctx.beginPath();
  ctx.moveTo(x + w - fold, y);
  ctx.lineTo(x + w - fold, y + fold);
  ctx.lineTo(x + w, y + fold);
  ctx.closePath();
  ctx.fillStyle = "#D5D6DB";
  ctx.fill();

  ctx.fillStyle = "#3B82F5";
  rr(ctx, x + w * 0.18, y + h * 0.58, w * 0.64, h * 0.16, 2);
  ctx.fill();
}
```

- [ ] **Step 7: Wire the island's drop to the canvas**

In `windows/src/island/island.ts`, replace:

```ts title="windows/src/island/island.ts" old
import { cursorLook } from "../cat/geometry";
```

with:

```ts title="windows/src/island/island.ts" new
import { FLIGHT_MS, cursorLook } from "../cat/geometry";
```

In the same file, replace:

```ts title="windows/src/island/island.ts" old
import { USC, UploadSeq } from "../upload/sequence";
```

with:

```ts title="windows/src/island/island.ts" new
import { classifyIngestError, noteSound } from "../upload/refusal";
import { USC, UploadSeq } from "../upload/sequence";
```

Replace:

```ts title="windows/src/island/island.ts" old
const BOT_OVERHANG = 40;
```

with:

```ts title="windows/src/island/island.ts" new
const BOT_OVERHANG = 40;
/** Seconds from the cat's refusal to the note: the 120 ms it takes to start heaving, and the hairball's 2.4 s. */
const HAIRBALL_S = 0.12 + 2.4;
```

Replace:

```ts title="windows/src/island/island.ts" old
  private uploadTens = 0;
  private uploadDone = false;
```

with:

```ts title="windows/src/island/island.ts" new
  private uploadTens = 0;
  private uploadDone = false;
  /** Counts the drops, so the note a refusal delays can tell that another drop has happened since. */
  private dropCount = 0;
```

Replace:

```ts title="windows/src/island/island.ts" old
        UploadSeq.enterZone(State.mouseInIsland.x, State.mouseInIsland.y);
```

with:

```ts title="windows/src/island/island.ts" new
        UploadSeq.enterZone(State.mouseInIsland.x, State.mouseInIsland.y);
        this.uploadCanvas.hover(true);
```

Replace:

```ts title="windows/src/island/island.ts" old
        UploadSeq.exitZone();
```

with:

```ts title="windows/src/island/island.ts" new
        UploadSeq.exitZone();
        this.uploadCanvas.hover(false);
```

Replace:

```ts title="windows/src/island/island.ts" old
    UploadSeq.performDrop(State.uploadDuration);
```

with:

```ts title="windows/src/island/island.ts" new
    UploadSeq.performDrop(State.uploadDuration);
    this.uploadCanvas.drop(name);
    const drop = ++this.dropCount;
```

Replace the approve chime that played at the drop for every file: it now plays when the ingest succeeds, so a refused file never gets it:

```ts title="windows/src/island/island.ts" old
    this.engine.gulp();
    Sound.play("approve");
    this.engine.triggerEmote("happy");
```

with:

```ts title="windows/src/island/island.ts" new
    this.engine.gulp();
    this.engine.triggerEmote("happy");
```

```ts title="windows/src/island/island.ts" old
      .then(async (file) => {
        State.droppedFile = { name: file.name, path: file.path };
```

```ts title="windows/src/island/island.ts" new
      .then(async (file) => {
        // The file is taken: now the approve chime. A refused file never gets it.
        Sound.play("approve");
        State.droppedFile = { name: file.name, path: file.path };
```

Replace the handling of a failed ingest. A file the app refuses is caught like any other, then coughed up as a hairball, and the note follows; any other failure (a folder, an unreadable file, a failed copy) shows the note at once, as before. The sounds: a refused file plays `annoyed` once as the gag starts (the engine does it, in `catchReject`) and its note is silent (`noteSound(true)` is `null`); any other failure keeps the `error` sound with its note (`noteSound(false)`). (`forgetDrop(State)`, just above, stays: it clears the file chip at once in both cases.)

```ts title="windows/src/island/island.ts" old
        UploadSeq.deactivate();
        State.noteMessage = String(err).replace(/^Error:\s*/, "");
        this.engine.animateMorph(0);
        this.setView("note");
        Sound.play("error");
        window.setTimeout(() => this.setView(State.defaultView()), 2400);
```

with:

```ts title="windows/src/island/island.ts" new
        const { message, refused } = classifyIngestError(err);
        const showNote = () => {
          UploadSeq.deactivate();
          State.noteMessage = message;
          this.engine.animateMorph(0);
          this.setView("note");
          const sound = noteSound(refused); // none after a refusal: the cat's annoyed already played, as it started to gag
          if (sound) Sound.play(sound);
          window.setTimeout(() => this.setView(State.defaultView()), 2400);
        };
        if (!refused) {
          showNote();
          return;
        }
        // The app refuses this file (an app, an archive, a disk image, a video, over 25 MB). The cat caught it like any other: now it
        // gags and coughs it up as a hairball (`annoyed` once, as the gag starts), and the note comes after it, silent. No check mark, no approve chime.
        UploadSeq.refuse();
        this.uploadCanvas.refuse();
        const arrives = Math.max(0, FLIGHT_MS / 1000 - (UploadSeq.sinceDrop() ?? 0));
        window.setTimeout(() => {
          // Leaving the drop flow in the meantime, or a new drop, has already ended this refusal.
          if (drop === this.dropCount && UploadSeq.refused) showNote();
        }, (arrives + HAIRBALL_S) * 1000);
```

Replace:

```ts title="windows/src/island/island.ts" old
    if (since == null) return;
```

with:

```ts title="windows/src/island/island.ts" new
    if (since == null || UploadSeq.refused) return;
```

- [ ] **Step 8: Teach the drop harness the catch**

`windows/dev/upload-preview.ts` plays the whole drop sequence in a plain browser. In it, replace:

```ts title="windows/dev/upload-preview.ts" old
State.droppedFile = { name: "rapport-q3.pdf", path: "C:/tmp/rapport-q3.pdf" };
```

with:

```ts title="windows/dev/upload-preview.ts" new
// `?refuse` drops a file the cat can't take (setup.exe): it is caught, gagged on and coughed back up as a hairball.
const REFUSE = new URLSearchParams(location.search).has("refuse");
const FILE = REFUSE ? "setup.exe" : "rapport-q3.pdf";
State.droppedFile = { name: FILE, path: `C:/tmp/${FILE}` };
```

Replace:

```ts title="windows/dev/upload-preview.ts" old
let dropped = false;
UploadSeq.enterZone(520, 96);
```

with:

```ts title="windows/dev/upload-preview.ts" new
let dropped = false;
UploadSeq.enterZone(520, 96);
canvas.hover(true);
```

Replace:

```ts title="windows/dev/upload-preview.ts" old
    dropped = false;
    UploadSeq.enterZone(520, 96);
  }
```

with:

```ts title="windows/dev/upload-preview.ts" new
    dropped = false;
    UploadSeq.enterZone(520, 96);
    canvas.hover(true);
  }
```

Replace:

```ts title="windows/dev/upload-preview.ts" old
      UploadSeq.performDrop(2.4);
```

with:

```ts title="windows/dev/upload-preview.ts" new
      UploadSeq.performDrop(2.4);
      canvas.drop(FILE);
      if (REFUSE) { UploadSeq.refuse(); canvas.refuse(); }
```

Run: `npx tsc --noEmit && npm run check:cat && npm run check:ai`
Expected: no type errors; all checks pass.

- [ ] **Step 9: Look at the drop view: a file taken, and a file refused**

The harness is at `http://127.0.0.1:1420/dev/upload-preview.html` (and `?refuse`). Drive it with a fake clock so the moments are exact: the cursor walks in, the drop is at 1.2 s.

```bash
WT="$(git rev-parse --show-toplevel)"; cd "${TMPDIR:-/tmp}/a-tauri-shots"
(cd "$WT/windows" && npx vite > vite.log 2>&1 &)
cat > drop-shots.js <<'EOF'
async page => {
  const q = "";                                   // use "?refuse" for the refused file (and the shot names below)
  await page.clock.install();
  await page.goto("http://127.0.0.1:1420/dev/upload-preview.html" + q);
  const shots = [[900, "hover"], [1350, "fly"], [1700, "gulp"], [2100, "chew"], [2700, "bar"], [4300, "bar2"]];
  let t = 0;
  for (const [at, name] of shots) {
    await page.clock.runFor(at - t); t = at;
    const b = await page.locator("#stage").boundingBox();
    await page.screenshot({ path: `drop-${q ? "refuse-" : ""}${name}.png`, clip: { x: b.x, y: b.y, width: b.width, height: b.height } });
  }
}
EOF
playwright-cli -s=drop open about:blank
playwright-cli -s=drop run-code --filename=drop-shots.js
sed -e 's/const q = "";/const q = "?refuse";/' -e 's/\[\[900, "hover"\].*\];/[[1350, "fly"], [1700, "arrive"], [2300, "heave"], [2800, "ball"], [3400, "roll"]];/' drop-shots.js > drop-shots-refuse.js
playwright-cli -s=drop run-code --filename=drop-shots-refuse.js
```

By eye: `drop-hover.png` the cat with wide eyes and an open mouth, the dashed frame green, the file icon at the pointer in front of the cat (as in the prototype's catch); `drop-fly.png` the file arcing into the mouth and shrinking, the mouth snapped wider; `drop-gulp.png` and `drop-chew.png` happy eyes, the squash, chewing; `drop-bar.png` the cat as a small ball riding the progress bar; `drop-refuse-arrive.png` to `drop-refuse-roll.png` the heave with ears back and eyes shut, then the file coughed up wrapped in fur and rolling away. No upload bar for the refused file. Fix `canvas.ts` if anything is wrong, then:

```bash
playwright-cli close-all
kill $(lsof -ti tcp:1420)
```

- [ ] **Step 10: Commit**

```bash
git add windows/src/upload windows/src/island/island.ts windows/dev/upload-preview.ts
git commit -m "feat(cat): the drop view catches the file, and coughs a refused one back up

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Cleanup, docs, CI and the final checks

**Agent:** `nm-implementer-light`.

**Files:**
- Modify: `windows/src/cat/*.ts`, `windows/src/cat/motion/*.ts` (remove the `// @@S...` marker lines), `windows/README.md`, `.github/workflows/windows-tests.yml`, `ARCHITECT.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: the whole branch.
- Produces: no marker comments left; the README describes the catch and the checks; CI runs `npm run check:cat` for pull requests that touch `windows/` or the cat fixtures; `ARCHITECT.md` and `CLAUDE.md` say that Windows now draws the cat from the contract in `windows/src/cat/` (this plan owns the Windows lines of both; the Mac plan owns the macOS ones).

- [ ] **Step 1: Remove the markers**

Every marker has done its job. From the worktree root:

```bash
node -e "
const fs = require('fs'), cp = require('child_process');
for (const f of cp.execSync('git ls-files windows/src', { encoding: 'utf8' }).trim().split('\n')) {
  const s = fs.readFileSync(f, 'utf8'), t = s.split('\n').filter((l) => !/^\s*\/\/ @@S\d-/.test(l)).join('\n');
  if (s !== t) { fs.writeFileSync(f, t); console.log('cleaned', f); }
}"
grep -rn "@@" windows/src windows/scripts windows/dev ; echo "exit $? (1 means no marker is left)"
```

Expected: the files are listed as cleaned, and the `grep` finds nothing (`exit 1`).

- [ ] **Step 2: Update the README**

In `windows/README.md`, replace:

```text title="windows/README.md" old
| Drag a file onto the island | The cat turns into a box, swallows it, then offers to answer questions about it |
```

with:

```text title="windows/README.md" new
| Drag a file onto the island | The cat opens its mouth, catches the file, chews it, then offers to answer questions about it. A file the app refuses (an app, an archive, a disk image, a video, over 25 MB) is caught too, then coughed back up as a hairball before the note says why |
```

Replace:

```text title="windows/README.md" old
    mochi/             the cat and the launch greeting, in Canvas 2D
```

with:

```text title="windows/README.md" new
    cat/               the cats, their motion and the launch greeting, in Canvas 2D (`dev.ts` is the `?dev` contact sheet)
```

Replace:

```text title="windows/README.md" old
## What's different from the Mac version
```

with:

```text title="windows/README.md" new
### Testing the cats

`npm run check:cat` (Node 22.6 or newer) runs the cat's checks in plain Node: the TypeScript in
`src/cat/` against the shared fixtures in `tests/fixtures/cat/`, within 1e-9 R. The fixtures are
generated from `design/prototype/cat-core.js`, which decides if the two disagree
(`docs/CAT-CONTRACT.md`). The look is checked by eye: `npx vite`, then open
`http://127.0.0.1:1420/?dev` for every coat at every size, the 11 states, the emotes and the
greeting, next to `design/prototype/notchmeow.html`. `?dev` is only served by the dev server.
`http://127.0.0.1:1420/dev/upload-preview.html` plays the file catch (add `?refuse` for the hairball).

## What's different from the Mac version
```

- [ ] **Step 3: Update the two guides**

In `ARCHITECT.md`, the character bullet. The Mac plan edits the macOS side of the same bullet, so on a branch that does not have its edit yet the line is the original `Today:` one; replace that one. (If the Mac plan's edit is already in your base, the line reads `- **Windows:** the upstream engine still draws it (\`windows/src/mochi/\`)...`: replace just that line with the first of the two lines below and skip the second.)

```markdown title="ARCHITECT.md" old
   - **Today:** the upstream engine draws it (`BotEngine.swift`, `windows/src/mochi/`).
```

```markdown title="ARCHITECT.md" new
   - **Windows:** the cat is drawn from the contract (`windows/src/cat/`): `BotEngine` animates a `CatPreset` with the Playful and Classic profiles (`motion/`), and `renderer.ts` draws it in Canvas 2D inside the existing canvases. Checked by `npm run check:cat` against `tests/fixtures/cat/`.
   - **macOS:** the upstream engine still draws it (`BotEngine.swift`) until A-mac lands.
```

In `CLAUDE.md`, a pointer to the Windows cats, under the `windows/` line:

```markdown title="CLAUDE.md" old
- `windows/` — the Tauri app for Windows and Linux: Rust in `src-tauri/`, TypeScript in `src/`, the `notchmeow-hook` relay in `hook/`. `windows/README.md` lists what differs from the Mac.
```

```markdown title="CLAUDE.md" new
- `windows/` — the Tauri app for Windows and Linux: Rust in `src-tauri/`, TypeScript in `src/`, the `notchmeow-hook` relay in `hook/`. `windows/README.md` lists what differs from the Mac.
- `windows/src/cat/` — the Windows/Linux cats (they replace the upstream character engine): presets, geometry, the engine and its two motion profiles, the renderer and the greeting, ports of `design/prototype/cat-core.js`. `npm run check:cat` tests them against `tests/fixtures/cat/`; `npx vite` then `http://127.0.0.1:1420/?dev` is the contact sheet.
```

- [ ] **Step 4: Run the cat's checks in CI**

In `.github/workflows/windows-tests.yml`, replace:

```yaml title=".github/workflows/windows-tests.yml" old
      - 'tests/fixtures/ai/**'
```

with:

```yaml title=".github/workflows/windows-tests.yml" new
      - 'tests/fixtures/ai/**'
      - 'tests/fixtures/cat/**'
```

Replace:

```yaml title=".github/workflows/windows-tests.yml" old
      - name: Install dependencies
        run: npm ci
```

with:

```yaml title=".github/workflows/windows-tests.yml" new
      - name: Install dependencies
        run: npm ci
      - name: Cat checks
        run: npm run check:cat
```

- [ ] **Step 5: Run every check**

```bash
cd windows
npm run check:cat && npx tsc --noEmit && npm run check:ai
npx vite build --outDir "${TMPDIR:-/tmp}/a-tauri-dist" --emptyOutDir
grep -rl "cat sheet" "${TMPDIR:-/tmp}/a-tauri-dist" ; echo "exit $? (1 means the release bundle has no ?dev page)"
(cd .. && bash scripts/test-cat-contract.sh)
git diff --stat notchmeow/rebrand -- src-tauri hook ../NotchBuddy ../design/prototype/cat-core.js ../tests/fixtures/cat
```

Expected: all checks pass; the build succeeds; no `cat sheet` in the bundle; the A-0 contract still passes; and the last command prints nothing (no Rust, no hook, no macOS file, no contract file changed). Remove `${TMPDIR:-/tmp}/a-tauri-dist` afterwards.

- [ ] **Step 6: Commit**

```bash
git add -A windows .github ARCHITECT.md CLAUDE.md
git commit -m "chore(cat): remove the stage markers, document the cats in the guides and run their checks in CI

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Checkpoint 2: the owner looks at the sheet and the drop view

**Owner checkpoint** (the executing session; no agent). Stages 1 to 4 are done when the owner says so.

- [ ] Send the owner, in the chat: a full-page screenshot of the `?dev` sheet (the States strip in both motion styles, the big cat with an emote and a mouth pose, the greeting panel mid-wave, and the ladder: `playwright-cli resize 1200 3600` then `screenshot --full-page`), **next to** the prototype page (`playwright-cli -s=proto screenshot --full-page`), and the drop harness shots `drop-hover.png`, `drop-fly.png`, `drop-chew.png`, `drop-bar.png` and the refused sequence `drop-refuse-heave.png`, `drop-refuse-ball.png`; plus the island's `greeting-d-wave.png` and `island-expanded.png`, the greeting's header and session cats (the Greeting panel after "Collapse now"), and `notch-fit.png` (the compact strip with the ear fit on and off).
- [ ] Say what the owner should check by hand in a real build (`cd windows && npm run tauri dev`, on Windows or Linux): the launch greeting; the island open with the big cat and the mini cats in the pills; a real file drop and the cat's catch; a refused drop (a `.zip`, an `.exe`, a file over 25 MB): the same catch, then the cat gags and coughs the file up as a hairball, then the note, with one `annoyed` as the gag starts and then silence (a silent note), no check mark and no approve chime; a drop that fails another way (a folder): the note at once with its `error` sound, no hairball; moving the pointer away during the hairball; the cat's gaze following the pointer; the badge on the left of the head in the compact notch, with the ears inside the strip when the cat hops; and the island's CPU at 0 % while hidden.
- [ ] Wait for the owner's OK. Then run the whole-branch review (`nm-reviewer-deep`).


---

## Next plan (A-tauri, stages 5 to 7): what stays, and the interfaces it will use

Not part of this plan. It is written after the owner signs off checkpoint 2, and synced to whatever A-0's and this plan's real builds changed.

**Stage 5: the Settings section and persistence.**
- A **Cat** section in the settings window (`windows/src/settings/main.ts`), built from the existing row styles; no existing row changes. Rows: Character (the 16 cats, Shrimpy first and Momo second, each in a small live preview), Motion style (Playful or Classic), This cat's motion (follow the global style or override it), Personality (Balanced, Chill, Grumpy, Sweet, Hyper, Chatty; moving a slider makes it Custom), the six trait sliders, Apply to every cat (motion and personality now; the collar joins it in stage 6), Fur lines (off by default). The collar's two rows are not here: they land with the collar in stage 6. The previews animate only while the settings window is visible.
- A `cat` block in `windows/src-tauri/src/settings.rs` and `State.settings.cat` in `core/state.ts` (`character`, `motionStyle`, `furLines`, and per cat `motion` and `personality`). An unknown stored ID falls back to `shrimpy` through `catById`; a stored personality goes through `normPers`. The island, the greeting, the mini cats and the drop view then build their engines from the chosen cat (today they take `DEFAULT_CAT`).
- Interfaces it uses from this plan: `catById`, `CAT_IDS`, `PRESETS[id].label`, `DEFAULT_CAT`; `catCfg` (`motion`, `override[id]`, `pers[id]`); `TRAITS`, `PERSONAS`, `personaNamed`, `slide`, `normPers`; `new BotEngine(preset, options)`, `engine.draw(ctx, W, H)`; `drawCat` and `stillView` for the previews; `Greeting` (which will read the chosen cat) and `UploadCanvas.cat`. Rust runs only through `windows/scripts/cargo-linux.sh`, with its own `--target-dir /repo/windows/target/a-tauri-5-7`.

**Stage 6: collar, searching and sleeping, the music bob, icons.**
- **Collar (optional, default Off):** the agent colour (`task.color`, today `BotEngine.bodyColor`, kept unused) becomes a collar in one of three styles the user picks: `tag` (band and tag), `band` or `kerchief` (neckerchief), or `off`, the default. These style IDs are frozen contract values; an unknown stored style falls back to `off`. Small cats wear their agent's collar; the big cat wears the collar of the agent driving its current state and none when idle; the coat never changes; with the collar off each mini cat's pill still names its agent. It is drawn at every size from Ø12 up in the renderer's *front* pass, from the contract's `collarGeometry` (A-0b, merged `6adf584`: `cat-core.js` with `collar-cases.json`, tested like the other fixtures; the readability floors, `COLLAR_MIN`, are in device pixels: a band 3 px thick, a tag 6 px across and a neckerchief 7 px wide and 5 px deep, so the dpr is an input, `min(2, devicePixelRatio)`). The style IDs are `COLLAR_STYLES` (`tag`, `band`, `kerchief`, `off`) and a stored value goes through `collarStyleOf`. The pass is the contract's `collarPass` (`"front"`), between `foldEars` and `whiskers`: `PASSES` itself stays as A-0 wrote it. Stages 1 to 4 draw no collar. A `collar` option on `DrawOptions` and a `collar` member on `CatView`.
- **The collar's Settings rows land with it, in the same stage:** Collar (global: Band and tag, Band, Neckerchief or Off) and This cat's collar (follow the global style, or pick one for this cat), both in the Cat section built in stage 5; "Apply to every cat" then also copies the collar. Persistence: `cat.collar` (global) and `cat.collar.<id>` (per cat, `follow` or a style ID) in the `cat` block of `windows/src-tauri/src/settings.rs` and in `State.settings.cat`, with an unknown value falling back to `off`. Rust only through `windows/scripts/cargo-linux.sh` with its own `--target-dir /repo/windows/target/a-tauri-5-7`.
- **Searching and sleeping:** port `isSearchTool`, `toolState`, `SEARCH_TOOLS`, `sleepDelay`, `SLEEP_AFTER_MS` and `wakes` from `cat-core.js` (fixtures `search-tools.json` and `sequence-cases.json`). `island/hooks.ts` maps a PreToolUse or PostToolUse tool name in the list to `searching` and the next other tool back to `working`; a one-shot timer, reset on every hook event, puts an idle cat to sleep after 10 minutes. Any hook event, hover or click wakes it, and Playful already wakes with zoomies (Task 8). This touches the hook *handlers* in the front end only: the relay and the Rust hooks stay untouched.
- **Music bob:** the head bobs and the ears bounce on the beat where the Windows app has a music signal (the Mac's Apple Music dance bounce is the model; check what Windows exposes first).
- **Icons:** `scripts/gen-icons.mjs` is a dependency-free rasteriser. It will import `src/cat/geometry.ts` and `presets.ts` (loadable in plain Node) for the head outline, ears, eyes and nose, and keep its own scanline rasteriser, so no canvas package is added. It draws Shrimpy's and Momo's heads together; the app icon does not follow the Character setting.

**Stage 7: theme tokens, dead-code removal and the rest of the Mochi rename.**
- `shared/theme.json` feeds a small Node generator that writes `theme.generated.ts` and `theme.generated.css` (the Mac plan adds the Swift file). Only character, branding and greeting colours change.
- Dead code goes: permanent emotes (`setPermanentEmote`, `permanentEye`, `miniEye` and `AgentTask.emote`), the `cup` eye shape, the mailbox morph (`animateMorph`, `resetMorph`, `morph`, the `slotH*` aliases, the `drawBot` slot block and `engine.gulp()` in `island.ts`, and the `morph`, `mouth`, `mouthRect` and `eye` fields of `UploadFrame`). The spec also lists `engine.greet()` as dead code, but the fixtures pin the `hello` emote, which `BotEngine.greet()` plays: keep it and say so (cat-core.js decides).
- Every remaining `mochi` or Mochi identifier is renamed: the comments in `src/cat/minibots.ts` and `src/upload/sequence.ts`, `scripts/gen-icons.mjs` (`renderMochi`) and `windows/README.md` (`ARCHITECT.md`'s and `CLAUDE.md`'s Windows lines are done in Task 13).
