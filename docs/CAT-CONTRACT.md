# The cat contract

`design/prototype/cat-core.js` holds everything about Shrimpy, Momo and the other fourteen coats that can be written as numbers in, numbers out. `tests/fixtures/cat/*.json` are generated from it. The macOS app (Swift) and the Windows/Linux app (TypeScript) each reimplement the core natively and test themselves against those fixtures, the same way both apps test their AI layer against `tests/fixtures/ai/`.

**`cat-core.js` is the tie-breaker.** The fixtures are generated from it, so if an app and a fixture disagree, the app is wrong. If the core itself must change, change it, regenerate the fixtures and commit both together. CI fails when they drift apart.

**Apps read the fixtures, so they change only by addition** (a new file, new keys, new cases): every line of an existing case stays byte for byte. `check-fixtures-additive.mjs` proves it against a commit. It is not part of the runner, because CI checks out one commit.

The look is not tested here. There are no pixel tests; the look is checked by eye against `design/prototype/notchmeow.html`, which draws with the same core.

## Run it

```
bash scripts/test-cat-contract.sh      # self-checks, no-drift check, determinism check
node scripts/gen-cat-fixtures.mjs      # rewrite tests/fixtures/cat/ after an intended change to the core
node scripts/gen-cat-fixtures.mjs --check
node scripts/check-fixtures-additive.mjs [BASE_REF]   # prove the cat and sidekick fixtures changed only by addition since BASE_REF (default HEAD)
```

Node 22 or newer, no npm packages. CI runs the script next to the AI contract.

## One file, two worlds

`cat-core.js` is a plain script. A page loads it with `<script src="cat-core.js">` and gets one global, `CatCore`. Node loads it with `require()` and gets the same object. No build step.

| Group | Names |
|---|---|
| Helpers | `rng`, `EZ`, `lerp`, `clamp`, `seg`, `hex`, `wrapA`, `tm`, `TAU` |
| Tables | `STATES`, `COL`, `TINT`, `GLOW`, `BADGE`, `MOUTH`, `MKEYS`, `EMOUTH`, `mouthFx`, `BUSY` |
| Presets | `PRESETS`, `CAT_IDS`, `MORE`, `makeCat`, `kittenOf`, `catById` |
| Geometry | `layout`, `mkWarp`, `supPoints`, `earGeom`, `faceAngles`, `cursorLook`, `pupilOffset`, `detailOf`, `earScale`, `badgeSide`, `outlineSteps`, `MOMO_WHITE`, `FACE`, `PASSES`, `newPose` |
| Ear fit | `earFit`, `EAR_FIT` |
| Compact detail | `detailLevel`, `FLAT_FILL`, `flatFillColors`, `mixHex` |
| Collar | `COLLAR_STYLES`, `collarStyleOf`, `collarGeometry`, `COLLAR_MIN`, `COLLAR_PASS` |
| Personality | `PERSONAS`, `TRAITS`, `persMultipliers`, `personaNamed`, `slide`, `normPers` |
| Motion | `CLASSIC`, `PLAYFUL`, `PROFILES`, `CatEngine`, `enginePaws`, `cfg` |
| Rules | `workClockStep`, `zoomiesOnFinish`, `ZOOM_AFTER_MS`, `sleepDelay`, `SLEEP_AFTER_MS`, `wakes`, `isSearchTool`, `toolState`, `SEARCH_TOOLS` |
| Timelines | `greetingPose`, `GREET_LEN`, `GT`, `GT2`, `STREAKS`, `flightAt`, `FLIGHT_MS`; the last beat (A-0c): `GT3`, `GREET_END`, `miniGlide`, `miniSlots`, `MINI_ROW`, `MINI_GRID`, `MINI_FROM`, `MINI_MIN_D` |
| Stored settings | `FOLLOW`, `MOTION_STYLES`, `motionStyleOf`, `motionOverrideOf`, `collarOverrideOf`, `catIdOf`, `cleanPersonality`, `cleanCatSettings`, `defaultCatSettings`, `applyToAllCats`, `motionFor`, `collarFor`, `engineCfg` |
| Display modes (B-0) | `DISPLAY_MODES`, `displayModeOf`, `DEFAULT_PAIR`, `DEFAULT_AGENT_CATS`, `MAX_AGENT_CATS`, `PILL_ID`, `isPillId`, `isAgentPill`, `defaultAgentCat`, `cleanPair`, `cleanAgentCats`, `cleanDisplaySettings`, `defaultDisplaySettings`, `pickCat`, `agentCatFor`, `rerollAgentCat`, `assignAgentCats`, `PILL_ROW`, `busyRank`, `castOf` |
| Kittens (B-0) | `KITTEN_MAX`, `KITTEN_LEAVE_MS`, `KITTEN_STATES`, `cleanKittens`, `kittenStep`, `kittenOrder`, `kittenView`, `KITTEN_PLACES`, `kittenPlaceOf`, `kittenSlots` |
| Small eyes (B-0) | `SMALL_EYE_SHAPES`, `SMALL_EYE`, `usesSmallEye`, `smallEye` |
| Desktop cat (H-0) | `DESKTOP_PHASES`, `DESKTOP_PHASE_INFO`, `DESKTOP_EVENTS`, `DESKTOP_ACTS`, `DESKTOP_NEXT`, `desktopStep`, `DESKTOP_FLIGHT_MS`, `DESKTOP_ARC`, `desktopFlightAt`; `DESKTOP_SIZES`, `DESKTOP_SIZE_IDS`, `DEFAULT_DESKTOP_SIZE`, `desktopSizeOf`, `DESKTOP_FPS`, `DESKTOP_NEAR`, `desktopFps`, `DESKTOP_KITTEN_PLACE`, `desktopKittenSlots`; `DESKTOP_MARGIN`, `DESKTOP_DEFAULT`, `MAX_DESKTOP_SPOTS`, `screenKey`, `isScreenKey`, `defaultDesktopSpot`, `clampSpot`, `cleanDesktopSpots`, `spotFor`, `rememberSpot`; `cleanDesktopSettings`, `defaultDesktopSettings` |
| Wardrobe (I-0) | `OUTFIT_IDS`, `OUTFIT_NAMES`, `OUTFIT_GROUPS`, `OUTFIT_DRAWN`, `DEFAULT_OUTFIT`, `outfitIdOf`, `cleanWardrobeSettings`; `easterOf`, `autoOutfitFor`, `resolveOutfit`; `OUTFIT_ROLES`, `outfitWorn`; `OUTFIT_SLOTS`, `OUTFIT_ORDER`, `OUTFIT_MIN`, `outfitEdge`, `outfitRoom`, `outfitAnchors`; `outfitGeometry`, `outfitDigest` |

The table lists the public surface a port needs, not every export: the module also exports `VERSION`, `own`, `COMPACT_EAR_SCALE`, `DETAIL_FULL_MIN`, `CURSOR`, `flatten`, `TRAIT_KEYS`, `WAKE_EVENTS`, `NOTCH`, `COMPACT`, `streakTime` and `islandBase`. The file-catch calls `catchOpen`, `catchDrop`, `catchArrive` and `catchReject` are methods of `CatEngine`, not exports.

Not in the core, on purpose:
- **Canvas drawing** stays in `notchmeow.html` and in each app's renderer. The core hands the renderer what it needs: `layout()` returns the head centre, warp, eyes, nose, mouth, ears and badge in px, and `PASSES` names the draw order as a *behind* pass, the head and a *front* pass, so outfits (sub-project I) can sit on either side of the head.
- **The Apple Music dance** is an existing member of each app's engine (`setDancing`, `applyDance`). The prototype has no music, so the core adds nothing for it.
- **Fur-line strands** (optional, off by default) are drawn from seeded noise by the renderer. They are not part of the contract.
- **Which files a cat refuses** (apps, archives, disk images, videos, over 25 MB) belongs to the AI contract (`tests/fixtures/ai/attachment-cases.json`, where 25 MB is 26,214,400 bytes). The cat only needs to be told "refused": `catchReject(ext)`.

## Conventions

- **Units.** Presets, the warp and the pose are in **R**, the head radius. `layout()` and the greeting are in px, the greeting in a 640×150 space. Times in a fixture are integer milliseconds or frame numbers. The one exception is a `tMs` column in `enters`, `emotes` and `catch` rows: it is derived data, exactly `f * 1000 / 60`, and `f` is the authority. Twelve significant digits keep only eight decimals at 1000 and above, so a stored `tMs` can differ from the true value by up to 5e-9. Compute it from `f`, or compare it within 1e-8.
- **Frames.** A fixture that steps the engine uses 60 frames per second: frame `f` is at `f * 1000 / 60` ms and the engine is updated once per frame with `dt = 1/60`.
- **Tolerance.** Every number is stored with 12 significant digits, and apps compare within **1e-9 R**. Swift and JavaScript can differ in the last bit of `sin`/`cos`/`pow`, so never compare floats exactly. Strings, booleans, nulls and the shape of the data compare exactly. Each fixture file carries `"tolerance": 1e-9`.
- **Seeding.** The core never calls `Math.random()` and never reads a clock. An engine is given `now()` (milliseconds) and `rand()` (0 up to, not including, 1). Fixtures use `rng(seed)`, a 32-bit LCG: `state = (state * 1103515245 + 12345) mod 2^32`, then `state / 2^32`, with the seed taken modulo 2^32. In Swift that is `UInt32` wrapping arithmetic (`&*` and `&+`). The first four values of seed 13 are 0.3401210163719952, 0.7113941803108901, 0.17734891548752785 and 0.924706461140886; `motion-cases.json` lists more. **The order of `rand()` calls is part of the contract**: an engine that draws a random number for a blink, a flick or a bleep must do so at the same moment and in the same order as the core, or its random schedule drifts.
- **Quiet engines.** `quiet: true` switches off every random idle habit (blinks, ear flicks, bleps, personality). Fixtures use it, so an emote is sampled on its own. The `ambient` cases run the other way, with a seeded rand, and list what the cat does by itself.

## The fixtures

| File | Pins |
|---|---|
| `presets.json` | `ids` (the frozen cat IDs, Shrimpy first and Momo second), `cats` and `kittens` by ID: every coat fully resolved, including `voice` (a pitch offset in semitones for sub-project C: Shrimpy −1, Momo +1, extra coats 0, every kitten +3). |
| `geometry-cases.json` | `detail` (the Ø28 switch), `earScale`, `outline` (head and ruff outline samples, including Shrimpy's fluffy edge), `anchors` (a full `layout()` per cat, size and pose, with the compact notch case), `collarPass` (the pass the collar is drawn in, see below; `passes` itself stays as A-0 wrote it), `earFit` and `earFitCases` (the ear fit, see below), `flatFill`, `detailLevels` and `flatColors` (the flat-fill rule, see below), `passes`. |
| `warp-cases.json` | `face` constants, `cursor` (tanh over 240/180 px), `angles`, `pupil` travel (0.24 of the eye width across and 0.18 of its height up and down, with yaw and pitch normalised by 0.62 and 0.5), `warp` (probe and marking points through the face warp), `eyes` (near-eye 55 % floor, hidden far eye), `head` (outline lean, nose and mouth depth). |
| `motion-cases.json` | `ease`, `tween`, `prng`; `rest` (every state at rest, in both styles and at five time and look combinations: eye shape, the six mouth values, ears, pupil, lid, tint, badge, colour, glow, mouth motion, blush and the full target set); `enters` (each state's entry, sampled over 3 s); `emotes` (every emote, hairball 2.4 s and zoomies 2 s included); `ambient` (45 s of idle habits for each personality). Rows are `v` arrays whose meaning is in `columns`. |
| `personality-cases.json` | The six presets, the six trait labels, `cases` (traits to multipliers and idle habits, including thresholds and hand-edited values), `slide` (moving a slider makes the preset Custom). |
| `sequence-cases.json` | `greetingSamples` (the 5.74 s greeting, every 100 ms and at each beat), `greetingStreaks`, `flight`, `workClock` (the 5-minute zoomies rule), `sleep` (the 10-minute rule and what wakes the cat), `catch` (the four-step file catch, in both styles, refused or not), `zoomiesAndWake` (when the engine starts zoomies); and, added in A-0c, `miniUnits`, `miniTimeline`, `miniGeometry`, `miniGlideSamples` and `miniSlotCases` (the greeting's last beat: the row of session cats gliding into the grid). |
| `search-tools.json` | The tool names that mean "searching", for Claude Code, Gemini CLI and Codex, and cases. |
| `collar-cases.json` | `styles` (the frozen IDs), `min` (the device-pixel floors), `resolve` (a stored value to a style), `cases` (each style's geometry at Ø12 to Ø66, at pixel ratio 1 and 2, at rest and with the head turned). |
| `settings-cases.json` | `ids`, `follow`, `motionStyles`, `collarStyles`, `defaults` (what a fresh install holds), `cases` (raw settings to clean ones: bad ones and a valid one), `personalities` (a stored personality, an object or JSON text, to a clean one), `applyAll` ("Apply to every cat"), `derived` (the engine's `cfg`, and the motion style and collar style each cat gets). See "Stored settings". |
| `display-cases.json` | `ids`, `modes`, `defaultPair`, `defaultAgentCats`, `maxAgentCats`, `pillIdPattern`, `defaults`, `cases` (raw Display settings to clean ones), `pairs` (a stored pair, an array or JSON text, to two cats), `agentCats` (a stored map to a clean one), `pillIds` (`isPillId`, `isAgentPill`, `defaultAgentCat`). See "Display modes, agent coats, kittens and small eyes (B-0)". |
| `agent-cat-cases.json` | `ids`, `defaults`, `cases` (`agentCatFor`), `rerolls` (`rerollAgentCat`), `assigns` (`assignAgentCats`). Each row names its random source and says how many numbers the call drew. |
| `cast-cases.json` | `ids`, `modes`, `pillRow`, `states`, `busyRank`, `cases` (`castOf`: every scenario, ranking and hostile input once per mode). |
| `kitten-cases.json` | `limits`, `states`, `places` (`KITTEN_PLACES`), `scripts` (`kittenStep` over events, the whole list after each), `order`, `views`, `cleans`, `slots` (`kittenSlots`), `placeOf`. See "Kittens". |
| `small-eye-cases.json` | `constants` (`SMALL_EYE`), `shapes`, `uses` (`usesSmallEye`), `sizes`, `squints`, `gazes`, `scales`, `others`, `hostile` (`smallEye`), `bright` (the list) and `brights` (`smallEye` with `cat` set, kittens too). See "Small coloured eyes". |
| `desktop-cases.json` | `phaseIds`, `phases`, `events`, `acts`, `flightMs`, `arc`, `steps` (`desktopStep` for every phase and event, and for input that is neither), `trips` (a script of events, the state and act after each), `flights` (`desktopFlightAt`), `sizes`, `sizeIds`, `defaultSize`, `sizeCases`, `fps`, `near`, `fpsCases` (`desktopFps`), `kittenPlace`, `kittenSlots` (`desktopKittenSlots`), `kittenSizes` (the same in points at each size), `margin`, `defaultSpot`, `maxSpots`, `screenKeys`, `isScreenKey`, `clamps` (`clampSpot`), `defaultSpots`, `spotFor`, `remembers` (`rememberSpot`), `spotMaps` (`cleanDesktopSpots`), `settingsDefaults`, `settingsCases` (`cleanDesktopSettings`), and from the file catch `catchNote`, `catchWaitMs`, `alertCases` (`desktopAlert`) and `catchReady` (`desktopCatchReady`), and from the transfer offer `offerNote` and `offerCases` (`desktopAlert` again). See "The desktop cat (H-0)", "The file catch" and "The transfer offer". |
| `wardrobe-cases.json` | `ids`, `names`, `groups`, `drawn`, `defaultOutfit`, `roles`, `clean` (`outfitIdOf`), `settings` (`cleanWardrobeSettings`), `easter`, `auto` (`autoOutfitFor`: every boundary and bad dates), `easterWindows` (six days round Easter in twelve years, walked with the calendar), `resolve`, `worn`, `slots`, `order`, `min`, `edge` (all 16 coats), `rooms` (`outfitRoom`), `anchors` (`outfitAnchors`: four coats at Ø20, Ø28, Ø48 and Ø64, at rest and with the head turned), `strips`, `geometry` (every outfit's shapes on four pinned cases), `digests` (`outfitDigest` of every outfit on every coat at Ø18, Ø20, Ø48 and Ø64), `collars` (the bell, bandana and scarf over each collar style), `unknown` and `fine`, `tolerance` (the 1e-9 the apps compare within, as in every file), `shrimpSwitch` (the shrimp clip's shapes at Ø18, Ø20, Ø27, Ø28 and Ø48, with the detail cut) and `lensRims` (the sunglasses' lens stroke on four coats, the edge role on a dark head). See "The wardrobe (I-0)". |

## Collar, ear fit and flat fills (A-0b)

Added after A-0 merged, because comparing the two app plans showed four things both apps must draw the same way: the collar styles, the ear fit, the flat fills and the mouth spring. The first three are below. The fourth was already in this file: the spring is stepped at most 1/60 s at a time, so a port sub-steps a slow frame (the harness list). So was the note that a stored `tMs` can be 5e-9 off, so compare it within 1e-8 or compute it from `f` (Conventions, Units).

**Collar.** The colour that used to fill the upstream figure is worn as a thin collar, or not at all.
- **Style IDs are frozen,** like cat IDs, in this order: `tag` (Band and tag), `band` (Band), `kerchief` (Neckerchief) and `off`, the default. `collarStyleOf(id)` maps a stored value to a style: an unknown ID, or anything that is not a string, is `off`.
- **`collarGeometry(preset, pose, D, style, {dpr})`** gives the shape in head-local px (before the tilt and the squash), turning with the face warp, and `null` for `off`. The parts depend on the style:

  | Style | Result | What it holds |
  |---|---|---|
  | `tag` | `{style, R, width, band, tag}` | `band`: a polyline of 26 points along the lower outline, left to right, inset so its outer edge stays inside the head; `width`: its stroke width; `tag`: `{x, y, r}`, a round tag at centre front. |
  | `band` | `{style, R, width, band}` | The band alone. |
  | `kerchief` | `{style, R, kerchief}` | `kerchief`: `{pts, apex}`, a triangle under the chin: `pts` along the lower outline, `apex` below them. No band. |

- **Sizes and floors.** The band is a tenth of R thick, the tag 0.16 R in radius and the kerchief 0.34 R deep, and none of them gets smaller than `COLLAR_MIN` in **device** pixels: band 3 thick, tag 6 across, kerchief 7 wide and 5 deep. So `dpr`, the screen's device pixel ratio, is an input (the page uses `min(2, devicePixelRatio)`; a value that is not above 0 counts as 2). Ø12 and Ø20 are where the floors bite.
- **Drawing.** The renderer draws it in the *front* pass, over the head and the folded ears and under the whiskers, from Ø12 up. `PASSES.front` is `foldEars, whiskers, badge, particles, balls`, and the collar is the one slot between the first two. `PASSES` is the line A-0 wrote and stays as it is (fixtures change only by addition), so the pass is named by its own key, `collarPass` in `geometry-cases.json` (`COLLAR_PASS` in the core). The coat is never recoloured. The paint (a thin dark edge so a light collar stays apart from a light coat, a lighter tag, a crease on the neckerchief at full detail) is the page's `drawCollar`, the reference for the look; it is not tested. Which colour a cat wears is not in the core: small cats wear their agent's, the big cat wears the agent driving its state and none when idle, with the global style and a per-cat override in Settings (`cat.collar`, `cat.collar.<id>`).

**Ear fit.** The compact island's top edge is the top of the screen, and a mask cannot give ears room above it. `earFit(L, pose, ceiling, margin = 0.5, minimum = 0.35)` returns the factor, from `minimum` to 1, to multiply the ear scale by so that no ear rises above `ceiling`. `L` is a `layout()` made with the ear scale `ek`:

```
ek = full ? 1 : earScale(D)
L = layout(preset, pose, cx, cy, D, {earScale: ek})
f = earFit(L, pose, 0)                 // 0: the top edge of the strip the cat sits in, in the layout's own coordinates
if (f < 1) L = layout(preset, pose, cx, cy, D, {earScale: ek * f})
```

- 1 means the ears already fit. A cat so close to the ceiling that even the smallest ears would not fit is held at `minimum`. `margin` is the room kept under the ceiling, in px.
- It is a closed-form solve, not a search: an ear scales about its own base, so the height of its top edge is linear in the scale. It finds the highest point of the ear's top edge, exactly. It does not look at the sides of an ear, so ears folded far back at a large size (a base corner higher than the top edge) are outside what it solves. The compact notch never gets there: `tests/cat/earfit.test.mjs` walks every state and emote in both styles against a brute-force outline.
- A pose that is not a number (NaN, Infinity) gives 1: there is nothing to fit.
- Apps pass the ceiling in the compact notch only (the prototype page does the same for the notch cat). The draw option is called `earCeiling` on the page and in both app plans: the y of the top of the strip, in the canvas's coordinates. An engine that knows the room above its cat's centre (the Windows engine's `earRoom`) passes `cy - room`: the room is the app's, the ceiling is the contract's.
- In `geometry-cases.json`, `earFit` holds the defaults and `earFitCases` the inputs (cat, head width, position, ear scale, pose, ceiling, margin, minimum) and the factor.
- **The scale and the fit compose.** Every compact cat is laid out with the compact ear scale `earScale(D)`; where a ceiling is given, the fit multiplies it. The prototype page does exactly this, so it shows what the apps draw.
- **Adopting it.** Both app plans already declare `earFit(L, s, ceiling, margin = 0.5, minimum = 0.35)` and compose `earScale(D) * f`. Keep the signature and the composition, and take this body, the exact solve of the ear's top edge: the controller ruled that the app plans adopt the contract's version. (The drafts solve for the ear's apex only, which leaves a tip up to 0.1 px inside the margin in some tilted poses, and the fixture cases show it.) Add a loop over `earFitCases`, and keep a brute-force test.

**Flat fills.** At Ø12 to Ø27 a gradient cannot be seen and costs a shading pass each, so a compact cat is drawn with flat fills. `detailLevel(D, override)` returns `{detail, full, flatFill}`, and `flatFill` is on exactly when the cat is compact (below Ø28, or when `override` says `'compact'`). When it is on:

| Part | Flat drawing |
|---|---|
| Head | One fill: the coat's `top` and `bot` colours mixed halfway (`FLAT_FILL.headMix` = 0.5), instead of the 45° gradient. |
| Ears | One fill each: the ear's `top` and `bot` mixed halfway (`earMix` = 0.5); an ear with its own colour (`earCols`) keeps it. The folded-ear flap too. |
| Ruff | One fill: the ruff's inner colour mixed 0.6 of the way to its outer one (`ruffMix`), instead of the radial gradient. |
| Rim | No edge gradient (`rimGradient` = false). The white rim line of the dark coats stays. |
| Tabby crown band | One ellipse of radii 0.4 R by 0.26 R (`crown`) at the centre the gradient had, in the stripe colour at alpha 0.5. |
| Point mask | One ellipse of radii 0.86 R by 0.54 R (`point`) at the centre the gradient had, in the point colour at alpha 0.85. Tuned to the gradient it replaces (see Decisions to know about). |

`flatFill` is exactly `!layout(...).full`, so an app that already branches on `L.full` (both app plans do) needs no new function: only the constants (`FLAT_FILL`: the head, ear, ruff and crown numbers are the ones both plan drafts already hard-code, the point mask is not, see Decisions to know about) and a loop over `detailLevels` that checks `!full` against `flatFill`. Everything else (markings, eyes, blush, the state tint) is drawn as in the full cat. `flatFillColors(preset)` returns the flat head, ear, ruff and point colours as `[r, g, b]` in 0 to 255, unrounded (`ruff` is `null` without a ruff, and `point` unless the coat is `point`). `geometry-cases.json` holds `flatFill` (the constants), `detailLevels` (head widths and overrides to levels) and `flatColors` (every cat's flat colours, the point mask's included). The mix is per channel, on the 0 to 255 values.

## The greeting's last beat (A-0c)

Added on 2026-10-06 (the owner's decision, in the cat spec's greeting paragraphs). The greeting used to end with the session cats popping in as the prototype's row of three on the page and as the 2×2 grid in the apps. It now ends on the row and then glides into the grid, so the hand-over to the real compact island never jumps. Everything is new keys, constants and functions: `greetingPose` and every old fixture line are untouched.

- **Timing.** All times are seconds after `leave`, the moment the island starts to fold (`GT.leave`, 4.9 s, or earlier when the pointer left). The row pops in 0.24 to 0.42 s after it (`greetingPose().minis`, as before), holds, glides 0.8 to 1.3 s after it (`GT3.glide0`, `GT3.glide1`), a fourth cat pops in from 1.0 s (`GT3.four0`), and the greeting ends 1.6 s after it (`GT3.end`). `GREET_LEN` stays 5.74 s, the old end, so the fixture line and the app tests that pin it do not move. `GREET_END` = `GT.leave + GT3.end` = 6.5 s is where the whole greeting ends.
- **`miniGlide(t, leave = GT.leave)`** returns `{grid, four}`: `grid` is the row becoming the grid (0 to 1, eased in and out) and `four` is the fourth cat's pop (0 to 1, with the same little overshoot as `minis`).
- **`miniSlots(minis, g, {W, H, d})`** returns the four cats in the order of the grid's cells (top left, top right, bottom left, bottom right) as `{x, y, d}`: centre and head width in px in the 640×150 space, the island centred at x = 320. `minis` is the pose's pop-in, `g` the glide, `W` and `H` the compact island (288×32 by default; on the Mac 344 or so by the notch's height), `d` the grid cat's head width (`MINI_GRID.d`, the Mac's 12; the Windows app passes 13). `d` is 0 for a cat that is not there and already holds the pop and the strip's scale, so an app draws every slot with `d > 0` and nothing else. A head narrower than `MINI_MIN_D` (2 px) counts as not there.
- **Row to grid.** The row is the prototype's: Ø11 cats, 14 px apart, the first 12 px in from the island's right edge and 1 px below the strip's middle (`MINI_ROW`). The grid is the compact island's: cells 16 px between centres, its centre 40 px in from the right edge and level with the strip's middle (`MINI_GRID`); the Mac's 12 pt cells with a 4 pt gap and the Windows app's 13 px cells with a 3 px gap are both 16 apart. The row's three cats glide to the cells top left, top right and bottom right (`MINI_FROM`: cell to row cat, 0 being the right-most), which keeps their paths apart (never closer than 0.88 of a head width), and the fourth pops into the bottom left. A strip shorter than 32 px shrinks the whole thing by `min(1, (H - 4) / 28)`, the Mac's `miniGridScale`.
- **What proves "equal to the compact island".** Not the contract alone, which is only the greeting's side. Each app tests its own compact island's numbers against the glide's last frame: the Mac reads `IslandRestingLayout`, pins the literals of `CompactMiniGrid`'s source and draws the last frame next to a grid laid out the way the view lays it out (a pixel test); the Windows app pins `#mini-grid`'s CSS and `applyGeometry` and compares the slots with the cells.
- **Fixtures.** `sequence-cases.json` gains `miniUnits`, `miniTimeline`, `miniGeometry`, `miniGlideSamples` (`miniGlide` for the timeline's own leave and two early ones) and `miniSlotCases` (`miniSlots` on five islands: the contract's, a Mac with a notch, a Mac without one, the Windows app's 13 px cats and a strip too short to hold a cat). Nothing existing changed: `node scripts/check-fixtures-additive.mjs` proves it.

## Stored settings

What Settings → Cat saves (spec §4) goes through one function before anything uses it. A settings file can be hand-edited, copied from an older build or half written, and on the Mac a personality is JSON text, which a strict decoder throws on. So each app reads what it stored as plain JSON values into the shape below, hands that to `cleanCatSettings`, and uses only the result. It never decodes the stored values straight into its own types. Raw in, clean out, never a throw.

**The shape** is the same raw or clean. The Mac builds the raw one from its UserDefaults keys; Windows and Linux read their `cat` block.

```text
{ character, motionStyle, collar, furLines, cats: { <catId>: { motion, collar, personality } } }
```

| macOS key | Field |
|---|---|
| `cat.character` | `character` |
| `cat.motionStyle` | `motionStyle` |
| `cat.collar` | `collar` |
| `cat.furLines` | `furLines` |
| `cat.motion.<id>` | `cats.<id>.motion` |
| `cat.collar.<id>` | `cats.<id>.collar` |
| `cat.personality.<id>` | `cats.<id>.personality`, as JSON text |

What each field becomes. Words are matched exactly: case, spaces and the type all count.

| Field | Kept when it is | Anything else becomes |
|---|---|---|
| `character` | one of the 16 cat IDs | `shrimpy` |
| `motionStyle` | `playful` or `classic` | `playful`. `follow` is a per-cat word, not a global style |
| `collar` | `tag`, `band`, `kerchief` or `off` | `off`. `follow` is not a global style either |
| `furLines` | the boolean `true` | `false`: the number 1, the text `"true"` and `null` are all off |
| `cats` | an object | no cats stored. The result always holds all 16 cats in `CAT_IDS` order, and drops unknown IDs, unknown keys and prototype names such as `constructor` |
| `cats.<id>.motion` | `follow`, `playful` or `classic` | `follow` |
| `cats.<id>.collar` | `follow`, `tag`, `band`, `kerchief` or `off` | `follow`. `off` is a real override: this cat wears no collar while the global one is on |
| `cats.<id>.personality` | see below | Balanced |

**Personality.** The value is an object, or the JSON text of one (the Mac stores text). Text that is not JSON, and JSON that is not an object (an array, `null`, a number, a string), give Balanced. Otherwise `cleanPersonality` reuses the rules above: the six traits go through `normPers` (held to 0 to 1, a missing or non-number trait is 0.5, a numeric string is never parsed), and the result is `{preset, energy, curiosity, chatty, affection, sass, mischief}`.

**Custom** is the word `custom` in `preset`, with the six traits beside it. It is what `slide()` returns when a slider moves, and it is not one of the six presets. A preset name is kept only when it names one of the six **and** the traits are still that preset's (within 1e-9). A name that does not match the traits, an unknown or mis-cased name, a name that is not text, a missing name, and a name alone (`{"preset": "chill"}`, whose traits are therefore 0.5) are all `custom`. A slider moved back onto a preset's numbers stays `custom`, which is what `slide()` returned, so a restart shows what the user saw.

**Apply to every cat.** `applyToAllCats(settings, id)` copies the motion override, the collar override and the personality of cat `id` to all 16 cats. It copies the stored words, so a cat that follows keeps following (the global style is not baked in), and every cat gets its own copy of the personality. The character and the global settings stay. An unknown `id` is Shrimpy.

**Using the result.** `motionFor(settings, id)` and `collarFor(settings, id)` give the style a cat plays and wears: its own word, else the global one (an unknown `id` is Shrimpy). `engineCfg(settings)` gives `{motion, override, pers}`, which is the engine's `cfg` without `zoomAfter`: the global style, an `override` entry only for each cat that has one, and all 16 personalities. Kittens use their parent's entry, as the engine already does. The functions clean what they are given first, so they accept any raw value, but an app that holds a clean value does not need to.

**Notes for ports:**
- **Read the stored values as JSON values, not as your own types.** Swift: `Any` from UserDefaults and `JSONSerialization`. Rust: `serde_json::Value`; a serde struct with typed fields rejects the whole settings file for one bad field. TypeScript: `unknown`.
- **A boolean is not a number.** `furLines` is on only for a real boolean. `UserDefaults.bool(forKey:)` turns `"true"` and 1 into `true`, so read the object and check for a boolean (`CFGetTypeID(n) == CFBooleanGetTypeID()`), the check the personality traits already need so that `true` does not become 1.0.
- **JSON text** goes through the platform's strict JSON parser, and any failure means "not JSON". The fixture holds only text that every strict parser rejects (cut off, single quotes, a trailing comma, `NaN`, garbage after the value) or accepts alike. A number that parsers read differently, such as `1e999`, is left out on purpose.
- **NaN and Infinity cannot be written in a fixture.** A real NaN or infinite trait counts as "not a number" (0.5), and a port adds a test for it. The fixture holds `NaN` as invalid text.
- **Key order does not matter** in objects. Read the cats through `ids`.
- **The trait tolerance is 1e-9,** the contract's, when deciding whether a preset name still matches. Do not compare floats exactly.
- **Replay the fixture:** `cases` (raw to clean), `personalities` (raw, an object or text, to clean), `applyAll` and `derived` (their `settings` are already clean).

## Display modes, agent coats, kittens and small eyes (B-0)

Sub-project B (`docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`) adds four sets of pure rules to the core, each pinned by fixtures. All of it is new names and new files: no existing function, constant or fixture line changed (`node scripts/check-fixtures-additive.mjs 6c14947` proves the fixtures). The prototype page draws all of it (the Display switch, the kittens, the small-eye sheet), so the page is the look and the core is the numbers. In Two cats mode the page puts the pair at 30 and 54 px from the island's left edge when compact, and expanded cat 1 (Ø58) at 56 and cat 2 (Ø46, 8 px lower) at 114: a 6 px gap. Those are layout, not contract.

### Display settings

Settings → Cat → Display saves a mode, a pair of cats and the agents' coats. They go through `cleanDisplaySettings`, a function of its own: adding the fields to `cleanCatSettings` would have changed every line of `settings-cases.json`, which apps already replay. **An app cleans the same raw `cat` block with both functions** and keeps both results: `cleanCatSettings` still returns only `{character, motionStyle, collar, furLines, cats}` and drops the display keys.

```text
{ displayMode, pair, agentCats: { <pillId>: <catId> } }
```

| macOS key | Field |
|---|---|
| `cat.displayMode` | `displayMode` |
| `cat.pair` | `pair`, as the JSON text of two cat IDs |
| `cat.agentCat.<pillId>` | `agentCats.<pillId>` (the Mac lists its UserDefaults keys with that prefix) |

| Field | Kept when it is | Anything else becomes |
|---|---|---|
| `displayMode` | `one`, `perAgent` or `two` (frozen, like the cat IDs) | `one` |
| `pair` | two different valid cat IDs, as an array or as the JSON text of one | Shrimpy and Momo, whole: one bad ID spoils the pair. Two of the same coat make cat 2 the next coat in `CAT_IDS` order, the first after the last |
| `agentCats` | an object | no coats stored |
| `agentCats.<pillId>` | a valid cat ID | the pill's default coat when it has one (`integration_claude` Shrimpy, `agent_codex` Momo), else dropped: assignment gives that agent a coat again |

- **A pill ID** matches `^[a-z][a-z0-9_-]{1,63}$` as a whole string, and is not `constructor` or `prototype`. An unknown pill ID is kept (agents come and go); `__proto__` and anything else that is not a pill ID is dropped. The result is in code-point order of the IDs and holds at most `MAX_AGENT_CATS` (256) pills: the first 256 in that order. `pillIds` in the fixture pins the shape.
- **Agent pills** are `integration_claude` (despite its prefix) and every `agent_*` pill (`isAgentPill`). Integrations and AI providers are not agents and never get a coat of their own.

### Giving agents their cats

`agentCatFor(pillId, agentCats, mainCat, rand)` returns `{cat, agentCats, assigned}`: the pill's stored coat, else its default, else a new coat that no other agent and not the Main cat uses, chosen at random; when all 16 are taken, the least-used one, ties in `CAT_IDS` order. A default coat that a stored coat has replaced counts as free; a default that is still in force counts as taken, whether or not that agent has been seen yet. `assigned` is true when `agentCats` gained the pill: store it then, and never change it by itself afterwards. `rerollAgentCat` is the dice button (never the current coat, always stored); `assignAgentCats(pillIds, agentCats, mainCat, rand)` gives every agent in a list a coat, and "Reset to defaults" is that call with an empty map.

- **Random numbers.** `rand()` returns 0 up to, not including, 1. It is called **once, and only when a free coat is chosen at random**; the least-used rule draws nothing, and nor do stored coats, defaults and non-agent pills. A number that is not finite is 0, and the index is held to the last free coat. The rows of `agent-cat-cases.json` name their source (`{seed}` is `rng(seed)`, `{values}` those numbers in order and then 0, `{none}` must never be called) and `draws`, the number of calls: a port that draws one more or one fewer drifts from the rows after it.
- **The 256 cap.** The cleaned `agentCats` holds at most 256 pills, in code-point order of pill IDs. With 256 or more stored pills, a new agent whose ID sorts after the 256th gets `assigned: false` (coat not stored, so it is re-rolled each launch) and a new ID that sorts early evicts a stored one (the first 256 in code-point order are kept, later ones dropped). Only reachable with 256+ stored pills; ports replicate this (`cleanAgentCats` pins the cap).
- **To change a coat** (the picker in Settings), put `{...agentCats, [pillId]: catId}` through `cleanAgentCats`.

### The cast

`castOf(mode, {tasks, focusId, mainCat, pair, agentCats})` says which coat each place wears. A cat stands for an agent's pill; the big cat shows the focused pill.

| Place | One cat | A cat for each agent | Two cats |
|---|---|---|---|
| Big cat, compact and expanded (`big`) | Main cat | the focused agent's cat; the Main cat when the focus is an integration or nothing | pair cat 1, showing the focused pill |
| Second spot (`second`) | none | none | pair cat 2, showing the busiest other agent |
| Row and 2×2 grid (`pills`) | Main cat | agent pills in their own cats, integrations in the Main cat | Main cat |
| Drop view and drag ghost (`drop`) | Main cat | the big cat's | the big cat's |
| Launch greeting (`greeting`) | the Main cat falls in; four session cats in the Main cat | the Main cat falls in; the four session cats are the cats of `pills` | the Main cat falls in and the pair arrives together; four session cats in the Main cat |

- **`tasks`** are the island's pills in the app's order, each `{id, state, last}`: `last` is the time of the pill's last event in ms (a missing or non-number one is 0), so **each app keeps a last-event time per pill**. A state that is not one of `STATES` is idle. A pill listed twice counts once.
- **The busiest other agent** is, among the agent pills other than the focused one, the first by `busyRank` (0 waiting for you, approval or question; 1 error; 2 working, thinking or searching; 3 anything else), then by the most recent `last`, then by its place in `tasks`. An integration is never chosen, and neither is the focused pill; Claude Code can be, when another agent is focused. With no other agent pill, `second.pill` is null and cat 2 idles with no badge. An idle agent that is the only other one is shown (idle), not skipped.
- **The row** is the first `PILL_ROW` (4) tasks other than the focused one and, in Two cats mode, other than `second.pill`, in the app's order.
- **An agent with no stored coat and no default** wears the Main cat here: the app gives it a coat with `agentCatFor` the first time it sees it, before it draws it.
- **Kittens' parents.** A kitten is `kittenOf` the coat its parent is drawn in at that spot: `big.cat`, `second.cat` or the pill's `cat` in `pills`.

### Kittens

A subagent is a kitten of its parent's cat. Each agent pill keeps a list, and `kittenStep(list, event)` is the one reducer that changes it. It is pure: the time is in the event (`t`, ms, any one clock), nothing is read from a clock, and nothing is changed in place. A kitten is `{id, type, session, state, born, last, until}`: `state` is `working`, `searching`, `approval` or `leaving`.

| Hook | Reducer event |
|---|---|
| `SubagentStart` (`agent_id`, `agent_type`, `session_id`) | `{type: 'start', id, agentType, session, t}`: a working kitten |
| `PreToolUse` or `PostToolUse` with an `agent_id` | `{type: 'tool', id, tool, t}`: searching for a tool in `search-tools.json`, else working |
| `PermissionRequest` with an `agent_id`, and its answer | `{type: 'permission', id, t}`: approval; `{type: 'resolved', id, t}`: working |
| `SubagentStop` | `{type: 'stop', id, t}`: leaving for `KITTEN_LEAVE_MS` (600 ms), then gone |
| the parent's `Stop`, or the session ending | `{type: 'end', session, t}`: every kitten goes; with a `session`, only that session's and those with none |
| the cat's sleep timer fires | `{type: 'sweep', t}`: a kitten whose last event is `SLEEP_AFTER_MS` (10 minutes) or more old goes |

- **Which pill:** the one the event belongs to, found as every other event finds its pill. Tool events without an `agent_id` belong to the parent and change no kitten: that is the fallback for a Claude Code that sends none (kittens still appear at start and leave at stop, in the working pose).
- **No timer.** A leaving kitten is dropped by the next event of any kind (`tick` is the event that only brings the time), and `kittenView(list, now)` hides it from its `until`, so the view is right between events. At most `KITTEN_MAX` (8) are kept: a ninth start drops the oldest by `born`.
- **An event for an id with no kitten, or for one that is leaving, changes nothing.** A late tool event after `SubagentStop` must not bring a kitten back, and without a start there is nothing to show.
- **Tool events and approval.** A tool event always sets `working` or `searching` and so ends an approval: the kitten flips out of the `approval` state the moment the hook delivers `PreToolUse` or `PostToolUse` with an `agent_id`. With parallel tools in one subagent, tool B's `PreToolUse` can flip a kitten out of approval while tool A's card is still open. Whether Claude Code puts `agent_id` on a subagent's tool events is not proven by a recorded session. Without it, tool events change no kitten, so a kitten still appears at start and leaves at stop, and stays in the working pose unless a permission request put it in `approval`, when it stays there until resolved or stopped.
- **Order:** `kittenOrder` puts a kitten waiting on an approval first, then the newest (`born`, and a later place in the list when they tie). `kittenView` is the order, without the expired leaving kittens, and is what `kittenSlots` takes.
- **`end` and two sessions.** Two sessions of one agent share a pill. Give `start` the hook's `session_id` and an `end` for one session leaves the other's kittens alone; an `end` with no session takes all, as the spec says.

`kittenSlots(place, kittens)` gives the slots. Every number is a multiple of a unit: `D`, the parent's head width, from its head centre (x right, y down), or `H`, the pill's height, from the pill's trailing edge (so x is negative inside it) and the middle of its height. The numbers are the brainstorm mockup's, divided by its parent's size.

| Place (`kittenPlaceOf(mode, expanded)`) | Unit | Up to | Kitten Ø | First centre (x, y) | Next | Overflow "+N" at |
|---|---|---|---|---|---|---|
| `bigExpanded` (One cat, A cat for each agent) | D | 3 | 15/58 | 24/58, 34/58 | 18/58 right | the next slot |
| `bigCompact` (One cat, A cat for each agent) | D | 2 | 12/20 | 22/20, 5/20 | 13/20 right | 42/20, -10/20 |
| `pairCompact` (Two cats) | D of cat 2 | 0 | none | none | none | a label "×N" at 1.1, 0.3 (the count of both cats' kittens) |
| `pairExpanded` (Two cats, for each cat) | D | 3 | 15/58 | a row centred under the cat, at y 34/58 | 18/58 apart | 0, 50/58 |
| `pill` (an agent pill, not focused) | H | 3 | 15/28 | -17.5/28, 0 | 16/28 inwards | the next slot |

The result is `{place, unit, count, shown: [{id, state, x, y, d}], more, moreAt: {x, y, size} | null, label: {text, x, y, size} | null}`. An unknown place shows nothing.

### Small coloured eyes

Below Ø28 the plain resting eyes (`pill`, `wide`, `dot`, `tired`, and the left eye of a `wink`) are small coloured eyes instead of ink pills; the expression shapes stay ink. `usesSmallEye(shape, sd)` says which, and `smallEye(shape, {sd, R, es, open, yaw, pitch, kitten, cat})` is the geometry, in px of the eye's own frame (the centre at the origin, y down, inside the renderer's foreshortening). It returns `{shape, closed: false, iris: {rx, ry, r}, pupil: {x, y, rx, ry}, light: {x, y, r}, rim}` (a bright coat's eye adds `flat: true` and has `rim: 0`), or `{shape, closed: true, line: {x0, y0, cx, cy, x1, y1, width}}` for an eye closed to a line, and `null` for an ink shape.

- **Sizes** (`SMALL_EYE`, fractions of `R * es`, full widths): the iris 0.42 by 0.46, the pupil 0.18 by 0.40, the catchlight radius `max(0.075 R, 0.45)` at (-0.11, -0.10) and the rim `max(0.05 R, 0.5)`. `wide` is the iris times (1.16, 1.12), `dot` a round iris (0.42) with a round, dilated pupil (0.26), `tired` shows at most 0.42 of the eye. A kitten's eye is 1.2 times wider and 1.32 times taller, which is what `kittenOf` does to a kitten's eyes.
- **Squint.** `open` (the pose's `open * (1 - lid)`) scales the iris's height, and under 0.22 the eye is the closed line, as the realistic eye does. The pupil's height is held to 0.87 of the iris's and the catchlight keeps its place in the iris, so its centre follows a squint; the radius is max(0.075 u, 0.45 px) and is not scaled, so on a heavy squint at tiny sizes it can poke up to about 0.4 px above the iris (e.g. R 10, open 0.3: iris ry 0.69, light y −0.30, r 0.75). Ports must not clamp.
- **Gaze.** The pupil moves with `yaw / 0.62` and `pitch / 0.5` (each held to -1 to 1) by at most 0.2 of the iris's half-width across and 0.08 of its half-height up or down, so it never leaves the iris (a test brute-forces it).
- **Colours are the renderer's.** For a normal coat the iris is a radial gradient from `iris[0]` at the centre to `iris[1]` at radius `iris.r` (`irisR` for the right eye, `sd` 1, when the coat has one); the pupil is `Theme.Cat.pupil`; the catchlight is white at 0.92; the rim is stroked in the preset's `liner` colour on the iris's edge; the closed line is stroked in `ink` at 0.9 alpha. The prototype's `smallEyeDraw` is the reference. For a bright coat (below) the flat fill replaces the gradient and there is no rim.
- **Bright eyes (the black coats).** `SMALL_EYE.bright` lists `midnight`, `oreo` and `mocha`, and `SMALL_EYE.brightPupil` is `{w: 0.12}`. An eye is bright when the input `cat` (the coat id) is exactly a string in `bright`; anything else, a missing `cat` or a non-string is a normal eye. A bright eye is filled flat with the lighter of the coat's two iris colours by luminance (Midnight #F7D45C, Oreo #DDEB5A, Mocha #F6C44C), has no rim, keeps its catchlight, and its slit pupil is 0.12 of `R * es` wide instead of 0.18 (the `dot` shape keeps its round pupil). Kittens of those coats are bright too (they keep the coat id). The output has `flat: true` and `rim: 0`; a normal eye has no `flat` key, and the closed line is the same for both. The renderer passes the coat id as `cat` (the prototype's call site is `cat: p.name`).
- **Not part of this:** every expression shape (they stay ink), the large cats' realistic eye, and the flat-fill rule.

**Notes for ports:**
- **Settings are read as plain JSON values,** as for the Cat settings (see "Stored settings"). `cleanPair` accepts the JSON text the Mac stores; text that is not strict JSON is "not a pair".
- **The pill-ID pattern is matched against the whole string.** ICU and Swift's `NSRegularExpression` let `$` match before a final newline: use a whole-match, or `\z`. The fixture holds `agent_x\n` and `agent_x ` as not pill IDs.
- **Key order does not matter** in a map; `cleanAgentCats` writes its keys in code-point order, and the cap is on that order, so a port that cannot keep a dictionary's order sorts the keys before taking the first 256.
- **Events cannot carry NaN or Infinity in a fixture,** and a missing key or `null` stands for "not there". A port adds its own tests for a time that is not finite (the event changes nothing) and for NaN in `smallEye`'s inputs (taken as the default; `R` is held to 0 up to 10000, `es` to 0 up to 10).
- **Replay the fixtures:** `display-cases.json` (`cases`, `pairs`, `agentCats`, `pillIds`), `agent-cat-cases.json` (with the harness above), `cast-cases.json` (`cases`), `kitten-cases.json` (`scripts` one event at a time, then the rest) and `small-eye-cases.json` (every group).

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

**A rejected drop snaps back.** `desktopStep` returns `act: null` for a `dragOut` without a valid spot and changes nothing, so the cat is not placed: it stays in the notch. A `move` without a valid spot changes nothing either, so the cat stays where it was on the desktop.

**A take-out during a pending alert waits for the next alert.** A `toggle` that takes the cat out while an approval is already pending flies it out (`home` → `flyingOut`, `flyOut`), but `alertOn` is not sent again, and `home` has no entry for it, so the cat stays out until the next alert arrives.

The acts (`DESKTOP_ACTS`): `place` show the cat at `event.spot`, no flight; `flyOut` fly from the notch spot to the desktop spot; `flyHome` fly from the desktop spot to the notch spot; `retract` the surprised emote, then fly from the desktop spot to the notch spot; `turn` reverse the flight in progress, carrying on from progress `1 - t`; `keep` the flight goes on the same way under its new phase; `land` the flight ended at the desktop spot; `dock` it ended at the notch spot, which shows the cat again; `goHome` the cat was already in the notch spot; `move` clamp `event.spot` and save it (`rememberSpot`); `resettle` find the spot again (`spotFor`) and put the cat there. `turn` is exactly a change between two flight phases whose `dir` differs, and `keep` a change between two with the same `dir`.

**The notch end of a flight.** On `turn` the app keeps the flight's clock and swaps its ends, so the notch end is the notch spot at that moment: the compact place, or the expanded place while the island is open for an alert. A flight can therefore change its notch end between compact and expanded when an alert arrives or clears.

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

**Desktop settings.** `cleanDesktopSettings(raw)` returns `{on, size, spots}` and never throws: `on` is true only for the boolean true, `size` one of the three IDs (else `medium`), `spots` as `cleanDesktopSpots`. It is a clean-up of its own, as `cleanDisplaySettings` is: `cleanCatSettings`, `cleanDisplaySettings` and every line of their fixtures stay as they were, and an app cleans what it stored with each function it needs.

| macOS key | Field |
|---|---|
| `cat.desktop.on` | `on` (a Bool) |
| `cat.desktop.size` | `size` (`small`, `medium` or `large`) |
| `cat.desktop.spots` | `spots`, as the JSON text of the map |

Windows and Linux keep `{on, size, spots}` as the `desktop` object of the `cat` block of `settings.json` (`spots` an object); `cleanDesktopSettings(block.desktop)` cleans it. "On" is stored as `DESKTOP_PHASE_INFO[phase].on`.

**The `on` boolean.** `UserDefaults.bool(forKey:)` turns `"true"` and 1 into `true`, so read the stored object and check that it is a boolean (as the `furLines` note above says). The fixture rows "on as text" and "on as the number 1" in `desktop-cases.json`, `settingsCases`, pin that both are off.

**Notes for ports:**
- **`desktopStep` returns a pair,** `{state, act}`, and the fixture's `steps` hold every phase and event, so a port replays all 63 plus the input that is not a phase or an event.
- **Screen coordinates are stored with 12 significant digits,** so a number of 1000 or more that is not a whole number or a half loses precision below 1e-9. The fixtures keep every such number under 1000 points or a whole number; ports compare with the 1e-9 tolerance as everywhere.
- **Rounding in `screenKey` is `floor(v + 0.5)`,** not the language's own `round` (Swift's `rounded()` rounds half away from zero, which differs below zero).
- **The key shape is matched against the whole string.** ICU and Swift's `NSRegularExpression` let `$` match before a final newline: use a whole-match, or `\z`. The fixture holds `0,0,1512,982\n` as not a screen key.
- **JSON cannot hold `NaN` or `Infinity`,** so the fixtures use `null`, a missing key or text for them; a port adds its own tests for a `t`, a spot or a `cursorDist` that is not finite (`t` is 0, a spot is not a spot, a distance is not near).
- **Key order does not matter** in a map: `spots` are written in code-point order and the cap is on that order, so a port that cannot keep a dictionary's order sorts the keys before taking the first 32.
- **Replay the fixture:** `steps` and `trips` (`desktopStep`, the four "a file catch" trips included), `alertCases` (`desktopAlert`), `catchReady` (`desktopCatchReady`), `catchWaitMs`, `flights` (`desktopFlightAt`), `sizeCases`, `fpsCases`, `kittenSlots`, `kittenSizes`, `screenKeys`, `isScreenKey`, `clamps`, `defaultSpots`, `spotFor`, `remembers`, `spotMaps` and `settingsCases`.

### The file catch (fixes after H)

A file on its way into the island is an alert to the desktop cat. The cat flies to the notch the way it does for an approval (the surprised emote, then the 600 ms arc), the island's catch plays with that one cat, and the cat flies back to its spot when the drop flow is over. To `desktopStep` this is `alertOn` and `alertOff`: **no phase, event or act was added**, every older row of `desktop-cases.json` stands (`node scripts/check-fixtures-additive.mjs <base>` proves it), and an `alertOn` at `home` still does nothing.

What is new is three names and some fixture keys, all additive:

- `desktopAlert({approval, question, chatApproval, pillStates, fileCatch})` is the one rule for "something wants the cat at the notch": true when any flag is exactly `true`, or `pillStates` (a list of state names) holds `'approval'` or `'question'`. A flag that is text, a number, `null` or a list is false, and input that is not an object is no alert. `fileCatch` is the app's own fact: a file is dragged over the island, a drop is waiting for the cat, or the drop flow (the upload, uploading and choose views) is on screen. Fixture: `alertCases`.
- `desktopCatchReady(phase)` says whether the big cat is at the notch, so the island may draw it and a catch may play with it: the phases whose notch spot is not empty, `home` and `atNotchForAlert`, which are exactly the phases the desktop window does not draw. A value that is not a phase counts as `home`. Fixture: `catchReady`.
- `DESKTOP_CATCH_WAIT_MS` (1500) is how long a dropped file waits for `desktopCatchReady` before the catch plays anyway. The flight is 600 ms and the surprise 450 ms, so a cat that left at the first sign of the drag is usually there already. Fixture: `catchWaitMs`.
- Four trips in `trips` are named "a file catch": the whole catch, the drop view folding before the cat has landed (the cat turns round mid-flight), a file that arrives while the cat is still flying out, and a catch with the cat at home (nothing happens).

**What an app does with it.** It feeds `fileCatch` from the drop flow it already has; it draws no cat of its own in the catch while the cat is not `desktopCatchReady` (never two copies of one cat, as everywhere in H); it holds a dropped file for at most `DESKTOP_CATCH_WAIT_MS` until the cat is ready; and the catch's cat sits where the notch spot is for the open drop view, so the dock does not jump. The island keeps the drop view open after a drag that leaves without a drop (the drag session may come back), so the cat stays at the notch until the island folds that view. The prototype page's Desktop panel is unchanged.

### The transfer offer (G2-0)

Sub-project G2 (`docs/LINK-CONTRACT.md`) lets another machine offer a file. The offer is a card ("<name> wants to send <file>", Accept and Decline) that only a click answers, so it is an alert like an approval: the island opens even when hidden, holds open, and the desktop cat flies to the notch. To `desktopStep` it is `alertOn` and `alertOff` again, so there is no new phase, event or act and every older row stands.

What is new is one flag and some fixture keys, all additive:

- `desktopAlert` also counts `transferOffer`: true only when exactly `true`, like the other flags (text, a number, `null`, a list or an object is false). Fixture: `offerCases`. **`alertCases` is untouched and holds no `transferOffer`**, so an app that replays it today keeps passing before it learns the flag.
- Three trips in `trips` are named "a transfer offer": the whole offer, an offer answered before the cat has landed (the cat turns round mid-flight), and an offer with the cat at home (nothing happens).

**What an app does with it.** It feeds `transferOffer` from the link's offer card, true from the moment the card is shown until it is answered, expired (2 minutes) or withdrawn. The G2 app plans add `offerCases` to their replay of `desktop-cases.json`.

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
- **The shrimp clip's two drawings.** `shrimpclip` is split at `DETAIL_FULL_MIN` (28): the detailed one (four segments, joints, feelers and a three-tip tail) at 28 and above, and a simple C with a three-tip tail below it, and `shrimpSwitch` pins the split.
- **The sunglasses' rim.** On a dark head (`outfitEdge` `light`) each lens gets a thin light rim in the `edge` role, because the frame's dark would vanish there, and `lensRims` pins which coats get it.

### Known limit (accepted by the owner, 2026-10-14)

The floors are in **device** pixels, so on a 1x (non-Retina) display the 24 pt strip of a screen without a notch (Ø18) can be too short for the tallest hats and the beanie's pompom: about 96 of the 256 outfit × coat pairs at Ø18 in that strip poke above it, and 13 of 256 at Ø20 in the 32 pt notch strip, measured at dpr 1. At dpr 2 none does: that is every notched Mac and every Retina display. The owner accepts this; the prototype and the fixtures are unchanged for it, and the apps draw as the contract says.

### Notes for ports

- Replay `wardrobe-cases.json` with `dpr` 2 unless a case says otherwise; the `strips` key says which strip each compact size sits in (`room` is `outfitRoom(anchors, strip / 2, 0)`).
- An app draws the shapes with its own painter and resolves the roles through the theme (`Theme.Outfits` on the Mac, `THEME.outfits` on Windows and Linux). The painter only paints: it never reads a coat.
- The apps compute `room` themselves where `earCeiling` is given, and pass the ear scale they drew the ears with as `o.earScale`.
- Auto for years before 1583 is unspecified; the apps only ever pass the current date.
- **The prototype page keeps a copy of the palette** between `@@OUTFIT-PALETTE` markers; `tests/cat/wardrobe.test.mjs` keeps it equal to `shared/theme.json`.

## The harness

`motion-cases.json` and `sequence-cases.json` describe how to build the engine, and `makeEngine` in `scripts/gen-cat-fixtures.mjs` is the reference:

1. a fake clock starting at 0, and `rand = rng(seed)`;
2. the cat (Momo unless the case says otherwise) with `motion` set to the case's style, no overrides, Balanced personality unless the case says otherwise, and `zoomAfter` of 5 minutes;
3. `_base = {x:0, y:0, R:1}` and `_mouth` from `layout()` at rest with the head width `2 * rx`, so R is exactly 1 and a hairball lands in units of R;
4. for `rest`: set `lookX`/`lookY`, then `computeTargets(T * 1000, T)`; for `enters`, `emotes` and `catch`: act at frame 0, then update once per frame and read the pose at the sample frames.
5. these facts are part of the contract, because a port that gets one wrong drifts from the rows without any error:
   - **The constructor draws five `rand()` values first**, in this order: the next blink, the next ear flick, the next slow blink, the next bleep and the next personality habit. Quiet engines draw them too, so every later draw is offset by five.
   - **The order of draws inside an action is fixed.** `emit` draws seven values per particle; `spitBall` draws the direction, then the two velocities, then the seed, then four particles; `dust` draws per particle. The columns `parts`, `ballX` and `ballY` only match if a port draws in the same order.
   - **`_base` and `_mouth` are set once, at construction**, from `layout(preset, e.s, 0, 0, 2 * rx)` with the rest pose, and are not refreshed per frame. A port that recomputes the layout every frame (as a renderer does) gets different `ballX` and `ballY`.
   - **Frame 0 is sampled before any update.** The action (`setState`, `emote`, `anim`, `catchOpen(true)`) is called at frame 0, the row for frame 0 is read straight away, and the first `update` is frame 1. This holds for `tween`, `enters`, `emotes` and `catch`.
   - **The `catch` cases call `catchOpen(true)` at frame 0**, `catchDrop()` at frame 60, and `catchArrive()` (or `catchReject("EXE")` when refused) at frame 60 plus the flight, 23 frames.
   - **`setState('idle')` on an engine that is already idle does nothing**, so the `idle` rows in `enters` show a cat with nothing triggered.
   - **`ambient` uses `quiet: false`, seed 7 and `pers: { momo: <preset> }`**, runs 45 seconds at 60 frames per second, and lists the engine's log as `[milliseconds rounded, name]`.
   - **The mouth spring is stepped at most 1/60 s at a time**, so a slow frame is several steps. One step of 0.066 s or more diverges to NaN. At 60 frames per second or faster it is exactly one step.
   - **The `zoomiesAndWake` cases in `sequence-cases.json` use a simpler harness, not frame stepping.** The engine is Momo with `quiet: true`, seed 1, the case's `profile`, no overrides, a Balanced personality and `zoomAfter` of 5 minutes, with `_base` and `_mouth` set as above. For each `[tMs, what]` in `script`, set the clock to `tMs` and call `setState(what)`, where `wake:idle` means `setState('idle')`. Do NOT call `update` between the steps. After the last step, run 60 updates of `dt = 1/60`, advancing the clock by 1000/60 ms before each, and read the engine's log: it is `log`, as `[milliseconds rounded, name]`.
   - **In the `catch` cases, an action at frame f runs after that frame's update, and the row is read after the action.** At frame 60 call `update` for frame 60, then `catchDrop()`, then read the row; at frame 83 (60 plus the 23 flight frames) call `update`, then `catchArrive()` (or `catchReject("EXE")` when refused), then read the row. Calling the action before the update gives different numbers (the mouth is 0.64 instead of 0.55 at frame 60). Frame 0 is the exception: `catchOpen(true)` is called, the row is read, and the first update is frame 1.

## Notes for ports

Things that are easy to get wrong when reading the fixtures from Swift or TypeScript:

- **Optional preset keys.** In `presets.json`, `bib`, `furOpts`, `light`, `chinCol`, `stripe`, `rimLight`, `white`, `lidTint`, `point`, `earCols`, `patches`, `muzzle`, `irisR`, `hairless`, `wrinkles` and `desc` exist only on some cats, so decode them as optionals. `ruff` is always present but is `null` or an object. A kitten also has `kitten: true` and `base`. The key `ear.cx` is optional and defaults to 0.95 when it is missing (the core uses `E.cx || .95`, so 0 also counts as missing); `geometry-cases.json` holds the resolved value. `patches` rows are mixed tuples: `[x, y, rx, ry, rot, '#RRGGBB', seed]`.
- **Shapes that change.** In `layout()` output, `nose` is `{visible: false}` or a full object, and `mouth` is `null` while the nose is turned out of sight.
- **Order comes from arrays, not objects.** Rows are read through `columns`, cats through `ids`. The persona order (Balanced, Chill, Grumpy, Sweet, Hyper, Chatty) and the state order (`STATES`) are only implicit in object key order, so hard-code them; a Swift dictionary loses order.
- **The "wrong types" personality case** (`personality-cases.json`) stores `{energy: 'high', curiosity: null, chatty: true, affection: [1], sass: {}, mischief: '0.9'}`. Every one of those counts as 0.5: a boolean is not a number and a string is never parsed. Decode traits as raw JSON values, not as `[String: Double]`, and make sure `true` does not bridge to 1.0.
- **Numbers.** Seeds go past 32-bit signed (4294967295 and 4294967296 appear), so decode them as `UInt32` or `Double`. `rng` is `UInt32` wrapping arithmetic (`&*` and `&+`) divided by 2^32. `wrapA` uses JavaScript's `%`, which keeps the sign of the dividend; in Swift use `truncatingRemainder`, not `remainder`. `greetingSamples` runs to 5800 ms, past the 5740 ms end, so clamp rather than extrapolate. `greetingStreaks` pins the values; if a port regenerates them from `rng(7)`, the draws per streak are, in order, angle, speed, length, start time.
- **`update(dt)`** holds `dt` to 0 up to 0.25 s: a negative number is 0, `NaN` and `±Infinity` become 0, and anything finite and larger than 0.25 (for example 1e9) becomes 0.25.
- **`quiet: true` does not silence mini cats completely.** A `mini` engine still draws from `rand()` for its gaze wander, even in quiet mode, so a mini cat shifts the random sequence. No fixture covers mini engines, so copy that branch from the source.
- **Kittens share their parent's settings.** The engine looks up the motion override and the personality with `p.base || p.name`, so a kitten uses its parent's.
- **Callback order.** Delayed callbacks (`later`) run in the order they were queued, not by due time. Tweens are advanced first, then the queue, then the targets, and the mouth spring last. `setState` drops pending callbacks tagged for the old state, but a callback already due in that frame still runs. `eyeUntil = Infinity` is an internal sentinel and is never stored in a fixture.
- **The paw-wave `hello` emote and `enginePaws` are part of the contract.** The `emotes` rows include `hello` for both motion styles, so an engine that drops `greet()` fails them. `enginePaws` positions have no fixture, and neither do mini engines, the `mkWarp` shortcut for angles below 1e-4, slow frames (every fixture runs at 60 frames per second), and the renderer-only preset fields (`fold`, `hairless`, `wrinkles`, `furOpts`); their only reference is the source.

## Decisions to know about

- **The compact ear scale is provisional.** The spec says ears are scaled down at Ø20 and gives no number. `COMPACT_EAR_SCALE` is 0.8 at Ø20 and below, easing to 1 at Ø28. Apps pass `earScale(D)` to `layout()`, and so does the prototype page, so its compact ears are the apps' ears. Change the constant and regenerate if the owner wants another value.
- **The ear scale and the ear fit are two things.** The scale makes every compact ear smaller; the fit shrinks further, only when a tip would leave the strip. The apps and the page apply both: `earScale(D)` first, then the fit (`earScale(D) * f`) where a ceiling is given, in the compact notch.
- **The flat point mask is tuned to the gradient it replaces.** The macOS draft's 0.5 R by 0.34 R held about 37 % of the gradient's ink and was visibly smaller at Ø20. `FLAT_FILL.point` is 0.86 R by 0.54 R at alpha 0.85: the same total ink as the gradient, and an edge between where the gradient had fallen to half and to a quarter of its strength. It was checked side by side with the gradient at Ø20 and Ø28 on Latte and Cloud, and `flatfill.test.mjs` pins both facts. If the owner wants it softer or tighter, change `FLAT_FILL.point` once, in the core and the fixtures.
- **Shrimpy's fluffy edge is a fixed sum of sines**, not noise from a seed, so it needs no random numbers and is identical everywhere. `geometry-cases.json` pins samples of it.
- **Only an idle cat sleeps.** `sleepDelay` is 10 minutes after the last agent event, and `null` for every other state, approval and question included. An app that leaves an agent on `finished` will not see the cat sleep until it returns to idle.
- **Playful wakes with zoomies** on any move out of sleeping except into dizzy, an approval included. That is what the prototype does.
- **The prototype page shortens the zoomies rule to 12 seconds** (`cfg.zoomAfter`), so you can watch it. The apps use `ZOOM_AFTER_MS`, 5 minutes.
- **Search tool names.** Claude Code's come from the repo's hook mapping. Gemini CLI's come from the installed CLI (0.39.1: `grep_search`, with `search_file_content` as its older name). Codex's `web_search` and `grep_files` are unverified, and Antigravity's tool names are not known. A name that is missing only means the cat stays in "working" for that tool.
- **Hostile input.** An unknown cat ID falls back to Shrimpy, an unknown state or emote is ignored, an unknown motion style plays Playful, personality values outside 0 to 1 are held to that range and missing ones count as 0.5, and `update(dt)` holds `dt` to 0 up to 0.25 s. Apps do the same.
- **A stored word that is not valid is the neutral one.** The global character, styles and collar fall back to the spec's defaults: Shrimpy, Playful and Off. A per-cat override that is not valid is `follow`, not a style: a typo never forces a style or a collar on one cat, or turns one off.
- **Custom is a word, and the traits are the truth.** The engine reads only the six traits. The preset name is a label that is kept only while it is honest (see Stored settings), so a hand-edited file can never show "Sweet" while the cat acts like Chill.
- **Fur lines are on only for a real `true`.** A settings file that holds `1` or `"true"` does not switch them on. It is the strict reading, the same on every platform.
- **Display settings have their own clean-up.** `cleanDisplaySettings` is separate from `cleanCatSettings` so that no line of `settings-cases.json` moves. An app that stores both in one block must keep the display keys when it writes the block back: a clean-up that rebuilds the block from `cleanCatSettings` alone drops them.
- **A pair is whole or default.** One bad ID in a stored pair makes it Shrimpy and Momo, not a pair with one repaired side.
- **The cast never invents a coat.** An agent with neither a stored coat nor a default wears the Main cat until `agentCatFor` has given it one; random choices happen only there, with an injected `rand`.
- **Kittens come only from a start.** An event for an id that never started, or already left, creates and changes nothing.
- **Cat 2 can be an idle agent.** "The busiest other agent" ends with the most recent event, so when no other agent is busy cat 2 shows the most recent one, idle or finished; it is empty only when there is no other agent pill.
- **The small eye's pupil travels little.** A slit pupil that nearly fills the iris has no room to move; 0.2 and 0.08 of the iris's half-axes are the most that keep it inside at every squint, which a test checks by brute force.
- **Bright eyes are an explicit list.** The three black coats glow through `SMALL_EYE.bright`, not a field on the presets, so `presets.json` and the old fixtures do not move. A port must pass the coat id as `cat`; without it the eye is a normal one.
- **The desktop cat's flight is `desktopFlightAt`.** `flightAt` and `FLIGHT_MS` are the file catch's flight (380 ms) and both apps copy them, so the trip's flight has names of its own.
- **The trip has seven phases.** `flyingHome` is the one the spec's six lacked: a double-click, the menu or the switch "flies it home", and `retracting` ends at the notch spot for an alert. A flight that changes phase keeps its clock and either carries on (`keep`, the same direction) or turns around (`turn`, from progress `1 - t`, retracing its own path).
- **A cat dropped on the desktop is placed, not flown:** `dragOut` goes straight to `onDesktop`, because the cat is already under the pointer. Only the menu item, ⌃⌥D, the switch and a launch fly it out.
- **A spot is the head centre, and the 24 points are the head's edge's:** a Ø96 cat's centre is 72 points from the visible frame's edge, so the cat never half-leaves the screen. A spot on no screen is the main screen's default, not the nearest screen's edge.
- **The screen key is the frames only.** The Dock and the menu bar move without changing the arrangement, so the spot is not forgotten; the clamp reads the visible frame at the time.
- **Desktop settings have their own clean-up,** like the Display settings: three functions clean one stored block, and none of them sees the others' keys.
- **Sleep beats the cursor, and hidden beats everything.** A sleeping cat does not watch the cursor (20 fps), and a cat that cannot be seen is not drawn even while it flies.
- **Kittens mirror to the left in the right half of the screen** (`side` -1), so they stay on the screen; the contract gives both layouts and the apps pick one by where the cat is.
- **Outfits belong to a role, not to a size.** The compact notch's Ø20 cat is dressed; the floors and the room (`outfitRoom`) keep every outfit readable and inside the strip there, and the pills' small cats and the kittens stay bare at any size.
- **Auto is a choice, not an outfit.** The stored value stays `auto`; `resolveOutfit` gives what is drawn. Its dates have no hemisphere or locale (the same for everyone).
- **The wardrobe has its own clean-up,** like Display and Desktop: `cleanWardrobeSettings` reads only `outfit`.
