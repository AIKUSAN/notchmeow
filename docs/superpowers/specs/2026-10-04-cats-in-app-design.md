# Sub-project A: Shrimpy and Momo in the apps

**Status:** design approved in chat on 2026-10-04. This is the written spec for review.
**Parent spec:** `docs/superpowers/specs/2026-10-03-notchmeow-design.md`, section "Sub-project A". The approved look, motion, mouth and emote tables, personality and the 14 extra coats are defined there and in `design/prototype/notchmeow.html`. This document doesn't repeat them. It decides how they reach the macOS and Windows/Linux apps.

## Goal
Replace the upstream character in both apps with the cats from the prototype, which look and move exactly as they do there. This first build ships display mode (2): one chosen cat. Modes (1) and (3) and subagent kittens belong to sub-project B. Sounds belong to C.

## Decisions

| Topic | Decision |
|---|---|
| Scope | All of A in one design: all 16 coats and their kittens, Playful and Classic motion, every state and emote (including hairball and zoomies), personality presets and sliders, the greeting, the file catch, icons and theme tokens. Delivered step by step (see "Stages"). |
| Approach | **Contract first, then both apps in parallel**, the same pattern as E1. A-0 turns the prototype's math into shared test files. A-tauri and A-mac are then built at the same time in two worktree sessions, both tested against those files. |
| Agent colour | An **optional coloured collar** (revised 2026-10-04). The colour that used to fill the upstream figure (`task.color`) becomes a collar in one of three styles the user picks in Settings: **Band and tag**, **Band** or **Neckerchief**, or **Off** (the default). Small cats wear their agent's collar. The big cat wears the collar of the agent driving its current state, and none when idle. The coat always stays the cat's own. With the collar off, each mini cat's pill still names its agent. |
| New triggers | **Searching** runs while an agent runs a search tool. **Sleeping** starts after 10 minutes with no agent event. |
| Order | E1 merges into `notchmeow/rebrand` first, because A changes the drop view and Settings, which E1 also changed. Then A-0, then A-tauri and A-mac in parallel. Nothing is pushed. |

## 1. Architecture

| Plan | Builds | Where |
|---|---|---|
| **A-0 Cat contract** | `design/prototype/cat-core.js`, the prototype's pure parts, which the page loads with a `<script>` tag. `scripts/gen-cat-fixtures.mjs` writes `tests/fixtures/cat/`. `scripts/test-cat-contract.sh` regenerates the fixtures in memory and fails on any drift. It runs in CI next to the AI contract. | main session |
| **A-tauri** | Renames `windows/src/mochi/` to `windows/src/cat/` and splits it into `engine.ts` (the same public API as today), `renderer.ts`, `presets.ts`, `motion/playful.ts`, `motion/classic.ts` and `personality.ts`. Tests read `tests/fixtures/cat/`. | worktree session |
| **A-mac** | Replaces `BotEngine.swift` with `CatEngine.swift`, `CatRenderer.swift`, `CatPresets.swift`, `MotionProfiles.swift` and `Personality.swift`. Keeps every member that `BotCanvasView`, `MiniBotCanvasView` and `FileDropView` use today. Swift script tests read the same fixtures. | worktree session |

**What stays untouched:**
- Hooks, `HookServer`, `AppState`, the island state machine, pill IDs and contract strings.
- Every existing view's layout and style.

The cat replaces only what is drawn inside the existing canvases, plus the named changes in §3 and §4.

**Room for later sub-projects (H desktop cat, I wardrobe):**
- The renderer draws in a separate *behind* pass and *front* pass, so outfits can sit behind or in front of the head.
- The engine keeps the members a desktop cat needs: dance, head centre, `lookX`/`lookY`, and the paw passes.
- Both cost little now and spare a rewrite later.

**Greeting:** on 2026-10-04 the owner chose the new greeting, a cat version of upstream's Greeting v2. The cat falls in with a landing squash, bounces, slides aside, pops up and does a quick paw wave, then slides back and ends like the old greeting. The total is still 5.74 s, with no upstream sound. It lives in the prototype as `GT2`/`greetPose2`, next to the old one for comparison. A-0 makes it *the* greeting in `cat-core.js` and `sequence-cases.json`. The old timeline is then dropped.

**Greeting, last beat (2026-10-06):** the owner decided that the greeting's last beat brings in the session cats as the prototype's **row of three** beside the main cat in the compact island, and that the row then **glides into the 2×2 grid** the shipping compact island shows (the Mac's `CompactMiniGrid`, the Windows app's `#mini-grid`), so the hand-over to the real island never jumps. A fourth cat pops into the empty cell as the others land, so the greeting ends on the four cats both apps always drew there. The shipping compact island does not change: the glide ends on its grid, proved on the Mac by a pixel comparison and on Windows by its pinned numbers. The beat is counted from the moment the island starts to fold, so an early leave plays it the same way: the row pops in 0.24 to 0.42 s after the fold starts, holds, glides 0.8 to 1.3 s after it, and the greeting ends 1.6 s after it. `GREET_LEN` stays 5.74 s, the greeting up to the settled row; the whole greeting, glide included, ends at `GREET_END`, 6.5 s. The greeting canvas now stays up in the compact island until the beat is over, so the glide is seen live and not only in the cat panel: the real cat and the real grid are hidden meanwhile, and fade in as the canvas fades out. The prototype's resting compact island shows the grid as well.

**Mochi goes away:** every remaining `mochi`/Mochi identifier is renamed, in code, in comments and in `gen-icons.mjs`.

**Tie-breaker:** `cat-core.js` is the source of truth. If an app and a fixture disagree, the module decides.

## 2. The cat contract (A-0)

**`cat-core.js`** holds:
- the presets, the coat types and flags, and `makeCat`/`kittenOf`;
- the face warp and the geometry helpers;
- the state, mouth and emote tables, and both motion profiles;
- personality;
- the greeting and file-catch timelines.

It is numbers in, numbers out. Drawing calls stay in the page.

**Randomness.** Idle bleps, winks, ear flicks and the like draw from an injected `rand()`. The fixtures fix the random sequence, so every run and every platform gives the same values.

**Fixtures** in `tests/fixtures/cat/`:

| File | Pins |
|---|---|
| `presets.json` | All 16 coats and each one's kitten, fully resolved in units of R. It also freezes the cat IDs. Each cat also carries `voice`: a pitch offset in semitones, used by sub-project C. Shrimpy is −1, Momo +1, the extra coats 0, and kittens +3. |
| `geometry-cases.json` | Head outline samples, including Shrimpy's fluffy edge, which is a fixed, deterministic function (a sum of sines, as in the prototype). Ear, eye and nose anchors. The Ø28 detail switch and the compact-ear scale. The badge position: right, or left in the compact notch. |
| `warp-cases.json` | Yaw and pitch, then the warped marking points. Also: the near-eye 55 % floor, the 0.24 pupil travel, the cursor curve over 240/180 px (tanh), the muzzle and nose depth, and the outline lean. |
| `motion-cases.json` | For Playful and Classic: each of the 11 states at rest (eye shape, the six mouth values, ears, pupil, lid, tint, badge). Every emote sampled at fixed times, including hairball (2.4 s) and zoomies (2 s). |
| `personality-cases.json` | The six presets and some custom slider values, mapped to their multipliers and to which idle behaviours are on. |
| `sequence-cases.json` | The greeting timeline, the four-step file catch, the zoomies rule (5 minutes of work) and the sleep rule (10 minutes of quiet), each sampled over time. |
| `search-tools.json` | The tool names that mean "searching" (§3). |
| `collar-cases.json` | Added by A-0b: each collar style's geometry at several sizes, with the device-pixel floors. |

**Tolerance.** Numbers compare within 1e-9 R, because Swift and JavaScript can differ in the last bit of `sin`/`cos`.

**No pixel tests.** The look is checked by eye: a dev state panel in each app (Debug-only on the Mac, `?dev` on Windows/Linux; the Mac is the primary app and never gets less), contact sheets (§5), and the prototype side by side.

**A-0b, contract additions (2026-10-04).** After A-0 merged, comparing the two app plans showed four things both apps must draw the same way, so they move into `cat-core.js` before the app plans run:
- the three **collar styles** (`collarGeometry`), with `collar-cases.json`;
- the **ear fit**: the compact island's top is the screen's top, so `earFit` shrinks the ears just enough that no tip leaves the strip, with geometry cases;
- the **compact detail level draws flat fills** (no rim, crown or point gradients) below Ø28, shown in the prototype too;
- the **mouth spring steps at most 1/60 s** per update, which A-0 already does. Ports must sub-step the same way.

The compact ear scale (0.8 at Ø20 and below, easing to 1 at Ø28) is provisional. If the owner changes it at a checkpoint, it changes once, in `cat-core.js` and its fixtures, and both apps pick it up.

## 3. Wiring in the apps (both platforms)

| Change | How |
|---|---|
| **Searching** | A PreToolUse/PostToolUse event whose tool name is in `search-tools.json` sets "searching". The list covers web search, web fetch, grep and glob, and the Gemini and Codex equivalents. The next non-search tool goes back to "working". |
| **Sleeping** | An idle cat sleeps after 10 minutes with no agent event. It never sleeps during an approval or question. Any hook event, hover or click wakes it, and Playful wakes with zoomies. A one-shot timer is reset on each event, with no polling. |
| **Collar** | As in Decisions: `task.color` becomes the collar, in the style the user picks, drawn at every size from 12 px up in the renderer's front pass. All three styles live in the contract (`collarGeometry` in `cat-core.js`, with fixture cases), with a readability floor in device pixels: band 3 px thick, tag 6 px across, neckerchief 7 px wide and 5 px deep. |
| **Music** | The existing Apple Music dance bounce drives a head-bob, with the ears bouncing on the beat. |
| **File drop** | The upload view becomes the mouth catch: open while hovering, snap on drop, gulp, chew for 0.85 s. A refused file (apps, archives, disk images, videos, over 25 MB) is caught, gagged on and coughed back up as a hairball. |
| **Errors** | In Playful, an agent error plays the hiss and then the hairball. |
| **Zoomies** | Plays after an agent finishes 5 minutes of working, thinking or searching. Approval and question pauses don't reset the clock. Also plays on waking. |
| **Greeting** | `GreetingCanvasView.swift` and `greeting.ts` play the new greeting from the contract (`sequence-cases.json`, which the owner chose on 2026-10-04) and draw the cat, with paws for hands. |
| **Existing emotes** | Triggers are unchanged: love on hover and on attach-drag, happy on drop and on chat done, proud on a search result, wink on mail sent, surprised on a provider chip tap, annoyed on a slap. Yawn is new and comes from low-energy personalities. |
| **Removed (dead code)** | Permanent emotes, `miniEye`, the `morph`/`cup` eyes, `BotStateCfg.sound` and the mailbox morph. Mail sent keeps its wink. `engine.greet()` stays: it plays the contract's `hello` paw-wave emote, which the greeting and the fixtures use. |
| **Fixes** | The Mac clock bug: `CACurrentMediaTime()` on both sides of `dt` (`BotCanvasView.swift:15-17`, `:170-171`). Ear headroom in the compact notch: the mask (`IslandRootView.swift:98-105`) can't give room above the screen's top, so the contract's `earFit` shrinks the ears instead, with ears scaled down at Ø20. |
| **Sounds** | Call sites keep the same sound names. A adds no audio files. |

**Out of scope, filed separately:** the Mac's 60 Hz mouse-poll timer, which runs while the island is hidden (`IslandWindowController.swift:207`).

## 4. Settings

A new **Cat** section is built from the existing row styles. No existing row changes.

| Row | Behaviour | Default |
|---|---|---|
| Character | One of the 16 cats, with Shrimpy first and Momo second, each shown in a small live preview | `shrimpy` |
| Motion style | Playful or Classic, for every cat. Classic moves 1:1 like upstream. | Playful |
| This cat's motion | Follow the global style, or override it for this cat | Follow |
| Personality | Balanced, Chill, Grumpy, Sweet, Hyper or Chatty. Moving any slider turns it into Custom. | Balanced |
| Trait sliders | Energy, Curiosity, Chattiness, Affection, Sass and Mischief, each from 0 to 1 | 0.5 |
| Collar | Band and tag, Band, Neckerchief or Off, for every cat | Off |
| This cat's collar | Follow the global collar, or pick a style for this cat | Follow |
| Apply to every cat | Copies this cat's motion, personality and collar to all 16 | — |
| Fur lines | Optional fur strands. Flat colour stays the default. | Off |

**Persistence:**
- Each cat keeps its own motion override and personality.
- **macOS** (UserDefaults): `cat.character`, `cat.motionStyle`, `cat.furLines`, `cat.collar`, `cat.motion.<id>`, `cat.collar.<id>` and `cat.personality.<id>`. The personality is stored as a small JSON value: preset name plus the six traits.
- **Windows/Linux:** a `cat` block in `settings.rs` with the same fields.

**Cat IDs are frozen contract values**, like pill IDs: `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle`. An unknown stored ID falls back to `shrimpy`.

**Collar style IDs are frozen the same way:** `tag`, `band`, `kerchief` and `off`. An unknown stored style falls back to `off`.

The preview animates only while Settings is visible.

## 5. Icons, theme, checks

**Icons.** They come from `scripts/gen-icons.swift` (run it with `bash scripts/gen-icons.sh` on a Mac), which draws them with the Mac's `CatRenderer`, not a Node script. One source for both apps; Windows and Linux get the committed files. It emits:
- the Windows icons;
- the macOS `AppIcon.appiconset` (10 PNGs), showing Shrimpy's and Momo's heads together;
- the `MenuBarIcon.imageset` template, a cat-head silhouette in black plus alpha, at 24×18, 48×36 and 72×54.

The owner's pick, 2026-10-07: app icon **C Peek** (Momo peeks over Shrimpy, on night teal) and menu bar **M1 Momo** (one head).

The app icon doesn't follow the Character setting.

**Theme tokens.** `shared/theme.json` feeds a small Node generator, which writes `Theme.generated.swift`, `theme.generated.css` and `theme.generated.ts`. Only character, branding and greeting colours change.

**Checks:**
- **Contract:** `scripts/test-cat-contract.sh` in CI, plus each app's fixture tests.
- **Engine:** the public API behaves as before (states, emotes, slap → dizzy, the drop sequence), and settings save and load.
- **Contact sheets:**
  - **macOS:** `scripts/render-cats.swift` renders every coat × size × state with the real `CatRenderer` into a PNG, without launching the app.
  - **Windows/Linux:** the `?dev` page in a browser.
  - Each build session sends the owner its sheet next to the prototype after stage 1 and after stage 4.
- **Frame time:** a Debug-only readout. Twelve small cats plus the big one stay under 2 ms per frame on the Mac. Small cats use the compact detail level, with flat fills below Ø28 on both apps. The Mac may redraw small cats at 30 fps.
- **CPU:** 0 % when the island is hidden and Settings is closed. This is checked in Activity Monitor during manual testing.
- **Owner's manual checks:**
  - every state, driven through the socket (see the parent spec, Verification);
  - the Settings rows;
  - CPU when hidden;
  - a real file drop and a refused file drop;
  - the greeting at launch.

## Stages (each app's plan)
1. A still cat at every size (Ø12 to Ø66) and in every coat, with kittens. Owner checkpoint (contact sheet).
2. The 11 states in both motion styles, with gaze and face warp.
3. Emotes and the mouth: six values, the per-state motion, and personality.
4. Greeting, file catch and hairball. Owner checkpoint (contact sheet).
5. The Settings section and persistence.
6. Collar (the three styles and its Settings rows land together; the default is Off), searching and sleeping, music bob, and icons.
7. Theme tokens, dead-code removal, and the Mochi rename sweep.

## Risks
- **Shrimpy's fluffy edge** must stay a fixed, deterministic function (the prototype's sum of sines), or the apps won't match the fixtures.
- **Many small cats** could cost real frame time. The compact detail level and the 2 ms budget guard against it.
- **Splitting the prototype** into a page plus `cat-core.js` must not break the page. A-0 checks that it still loads and runs.
- **The upload view** was changed by E1. That's why A starts after the E1 merge.

## Done means
- Both apps show the chosen cat everywhere the upstream figure appeared, at every size.
- Every state and emote matches the prototype in both motion styles.
- Settings rows persist across restarts.
- Fixtures pass in CI on both platforms.
- CPU is 0 % when hidden.
- No `mochi`/Mochi identifiers remain.
- The owner signs off on the contact sheets and the manual checks.
