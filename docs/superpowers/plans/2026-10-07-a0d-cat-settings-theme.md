# A-0d Cat Settings and Theme Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both apps what stages 5 to 7 of sub-project A need from the shared contract, before the app plans run: one clean-up rule for the cat settings that Settings saves (`cleanCatSettings` in `cat-core.js`, pinned by a new fixture, `settings-cases.json`), and one small generator that turns `shared/theme.json` into `Theme.generated.swift`, `theme.generated.css` and `theme.generated.ts`, with a `--check` mode for CI. The apps do not use the theme files yet: that is stage 7 of each app plan.

**Architecture:** Settings go in the one plain script, `design/prototype/cat-core.js`, as a new section after the engine. It reuses the personality rules already there (`normPers`, `personaNamed`, `PERSONAS`), the collar styles (`COLLAR_STYLES`) and the cat IDs (`CAT_IDS`); it adds the words `follow`, the two motion styles and the clean-up functions. `scripts/gen-cat-fixtures.mjs` writes one new file, `settings-cases.json`; no existing fixture line changes, and `scripts/check-fixtures-additive.mjs` proves it. The theme generator is a separate Node script, `scripts/gen-theme.mjs`: it reads `shared/theme.json`, adds the state colours, glows and streak palette that `cat-core.js` already pins, and writes one file per platform. Its `--check` mode and its self-checks run in CI through `scripts/test-theme.sh`.

**Tech Stack:** JavaScript (one file for a browser and Node 22), `node:test` and `node:assert` (no npm packages), Bash, Swift (a typecheck and the Debug build) and TypeScript (`tsc --noEmit`) to prove the generated files compile.

**Spec:** `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`: §4 "Settings" (rows, defaults, persistence, frozen IDs), §5 "Theme tokens" and "Checks", "Stages" 5 to 7 and "Done means". It extends `docs/CAT-CONTRACT.md` and `design/prototype/cat-core.js` as merged by A-0, A-0b and the greeting's last beat (plans `2026-10-04-a0-cat-contract.md`, `2026-10-04-a0b-contract-additions.md`, for format). Read the spec's §4 and §5 before starting.

**Base:** branch `a0d/cat-settings-theme`, created from `notchmeow/rebrand` at `947e2d3` or later, with this plan file already committed to `notchmeow/rebrand`. The cat contract and its eight fixtures must still be the ones from `947e2d3`: the additive check compares with that commit. This plan touches no app code under `NotchBuddy/` or `windows/`. It adds three generated files there (`NotchBuddy/Sources/App/Theme.generated.swift`, `windows/src/theme.generated.css`, `windows/src/theme.generated.ts`) and the six lines `xcodegen` adds to `project.pbxproj` for the Swift one; the apps use none of them yet. **It changes no pixel and no behaviour in either app.**

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed again under "Open questions for the owner".

- **Cat IDs are frozen contract values, in this order:** `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle`. An unknown stored ID falls back to `shrimpy`.
- **Collar style IDs are frozen:** `tag`, `band`, `kerchief` and `off`. An unknown stored style falls back to `off`.
- **The Cat section's rows and defaults (spec §4):** Character `shrimpy`; Motion style Playful or Classic, default Playful; This cat's motion: follow the global style or override it, default Follow; Personality: Balanced, Chill, Grumpy, Sweet, Hyper or Chatty, and moving any slider turns it into Custom, default Balanced; six trait sliders (Energy, Curiosity, Chattiness, Affection, Sass, Mischief), each from 0 to 1, default 0.5; Collar Band and tag, Band, Neckerchief or Off, default Off; This cat's collar: follow or a style, default Follow; Apply to every cat: copies this cat's motion, personality and collar to all 16; Fur lines, default Off.
- **Persistence (spec §4):** each cat keeps its own motion override and personality. macOS (UserDefaults): `cat.character`, `cat.motionStyle`, `cat.furLines`, `cat.collar`, `cat.motion.<id>`, `cat.collar.<id>` and `cat.personality.<id>`; the personality is a small JSON value, the preset name plus the six traits. Windows/Linux: a `cat` block in `settings.rs` with the same fields.
- **Unknown or hostile stored values never throw** (A-0 Review Focus, restated for settings): an unknown cat ID falls back to Shrimpy, an unknown motion style plays Playful, personality values outside 0 to 1 are held to that range and missing ones count as 0.5.
- **A per-cat override that is not valid is `follow`** and **a preset name is kept only while the traits still match it** (plan decisions).
- **Tolerance:** fixtures store 12 significant digits and apps compare within **1e-9**. There are no pixel tests.
- **`cat-core.js` is the tie-breaker:** if an app and a fixture disagree, the module decides. It stays numbers in, numbers out: no canvas, no DOM, no clock, no `Math.random`.
- **Fixtures change only by addition:** one new file, `settings-cases.json`. Every existing line stays byte-identical. `node scripts/check-fixtures-additive.mjs 947e2d3` proves it.
- **Theme tokens (spec §5):** `shared/theme.json` feeds a small Node generator that writes `Theme.generated.swift`, `theme.generated.css` and `theme.generated.ts`. **Only the character, branding and greeting colours change** — in the apps, and only at stage 7. Existing views keep their styling. This plan creates the generator, `theme.json` and the generated files, and does not make either app use them.
- **Icons are out of scope.** The icon design is chosen separately; no icon, no icon palette.
- **Node standard library only, no npm packages;** Node 22 or newer. Same code style as A-0: compact one-liners in the core, plain commented code elsewhere.
- **Never edit `NotchBuddy.xcodeproj` by hand.** The one task that adds a Swift file runs `cd NotchBuddy && xcodegen` and commits the regenerated `project.pbxproj`.
- **Nothing of Coucou's comes back, and the names Coucou and Mochi appear in no new code.** No `UserDefaults` suite in any test (these tests use none). `main` is the App Store build.
- **Commits:** local only, never pushed. End every commit message with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, or with the model that wrote it when an implementer runs on another one (the light tasks below name `Claude Haiku 4.5`).
- **House rules for the session:** install nothing and download nothing (`npx --no-install` only, never `npm install`, `npm run build` or `npm run dev`); never launch, quit or replace a NotchMeow app (a Debug *build* in the worktree is fine); use `trash` and not `rm -rf` for anything you delete by hand; if a command is denied by a permission prompt, stop and report it.

## Review Focus

The spec says what Settings saves and what the theme covers. It is silent on these inputs, and each would bite a person (or a port) first. Each line names its test.

1. **A personality that is bad JSON, not an object, or the wrong types.** The Mac keeps it as JSON text and its `Codable` decoding throws on a bad one. Expected: Balanced, or 0.5 for each trait that is not a number, and never a throw. Tests: Task 1 "personality: JSON that is not JSON, or not an object, is Balanced" and "personality: traits are held to 0..1…", and the 47 `personalities` rows of the fixture (Task 2).
2. **A stored word that no longer exists or never did:** a hand edit, an old build, a prototype name (`siamese`, `scarf`), a wrong case, `follow` used as a global style. Expected: Shrimpy, Playful, Off for the globals and `follow` for a cat's own override. Tests: Task 1 "the character…", "the global motion style and collar…" and "a cat's own motion and collar…".
3. **A value of the wrong type that a platform bridges for you:** `furLines` as `1` or `"true"` (Swift's `UserDefaults.bool` says yes to both), a number where a word goes. Expected: off, and the neutral word. Tests: Task 1 "fur lines are on only for a real boolean true" and the fixture's `fur lines as the number 1` / `as the text true` rows.
4. **A partial or hostile `cats` map:** cats missing, an entry that is not an object, unknown IDs, keys such as `constructor` or `__proto__`. Expected: all 16 cats, in order, the defaults for what is missing, nothing extra, and no object shared between two cats. Tests: Task 1 "anything that is not an object gives the defaults…", "the cats map…", "applyToAllCats…" and the 3000-case fuzz.
5. **A theme file that is stale or mistyped:** someone edits `theme.json` or a state colour in `cat-core.js` and forgets to regenerate, or writes a lowercase hex, a three-digit hex or an unknown group. Expected: CI fails and names the file or the field. Tests: Task 3 "a theme.json with a mistake is refused…", "--check's test…" and the `--check` bite step; Task 4 wires it into CI.

---

## Hard-coded colours today (the inventory)

These are the places where the character, branding and greeting colours are hard-coded on 2026-10-07, at `947e2d3`, on both apps and on the prototype. Task 3 proves each line (175 checks) and Task 4 copies this table into `docs/THEME.md` for stage 7. Line numbers move; a colour is found again by its value.

| Token | macOS (`NotchBuddy/Sources/App/`) | Windows and Linux (`windows/src/`) | Prototype (`design/prototype/`) |
|---|---|---|---|
| `brand.accent` `#5EEAD4` | none | `cat/dev.ts:72, 93` | `notchmeow.html:15` |
| `brand.page` `#0F1012` | `CatDevPanel.swift:330` (as 0.059, 0.063, 0.071) | `cat/dev.ts:80` | `notchmeow.html:15` |
| `brand.panel` `#17181B` | none | `cat/dev.ts:55` | `notchmeow.html:15` |
| `brand.line` `#2A2C31` | none | `cat/dev.ts:19, 55, 72, 93, 135` | `notchmeow.html:15, 497` |
| `brand.ink` `#ECECEE` | none | `cat/dev.ts:19, 72, 81, 131` | `notchmeow.html:15, 496` |
| `brand.dim` `#9A9CA3` | none | `cat/dev.ts:56, 64, 85, 141, 159, 175` | `notchmeow.html:15, 499` |
| `brand.button` `#202227` | none | `cat/dev.ts:19` | `notchmeow.html:26` |
| `cat.pupil` `#0E0B09` | `CatFace.swift:64` | `cat/renderer.ts:275` | `notchmeow.html:203` |
| `cat.mouthInside` `#3A1218` | `CatFace.swift:170` | `cat/renderer.ts:403` | `notchmeow.html:260` |
| `cat.tongue` `#E8798C` | `CatFace.swift:154` | `cat/renderer.ts:404, 411, 424` | `notchmeow.html:261, 263, 268` |
| `cat.teeth` `#FBF7F0` | `CatFace.swift:178` | `cat/renderer.ts:406` | `notchmeow.html:262` |
| `cat.heart` `#FF4D6D` | `CatFace.swift:116`, `CatEffects.swift:127` | `cat/renderer.ts:300, 377` | `notchmeow.html:218, 241` |
| `cat.star` `#F7B32B` | `CatFace.swift:120`, `CatEffects.swift:130` | `cat/renderer.ts:301, 378` | `notchmeow.html:219, 242` |
| `cat.sweat` `#7CC7FF` | `CatEffects.swift:139` | `cat/renderer.ts:380` | `notchmeow.html:244` |
| `cat.paper` `#F4F5F7` | `CatEffects.swift:158` | `cat/renderer.ts:443` | `notchmeow.html:398` |
| `cat.paperFold` `#C9CDD4` | `CatEffects.swift:159` | `cat/renderer.ts:444` | `notchmeow.html:399` |
| `cat.paperLabel` `#3B9EFF` | `CatEffects.swift:160` | `cat/renderer.ts:445` | `notchmeow.html:400` |
| `greeting.badge` `#3BA0F5` | `CatGreetingRenderer.swift:41` | `cat/greeting.ts:186` | `notchmeow.html:476` |
| `greeting.tint` `#7FB4EA` (127, 180, 234) | `CatGreetingRenderer.swift:41, 66` | `cat/greeting.ts:177, 187` | `notchmeow.html:476` |
| `greeting.haloGold` `#E8C39A`, `greeting.haloBlue` `#3B9EFF` (the ends of a `lerp`) | `CatGreetingRenderer.swift:16` | `cat/greeting.ts:291` | `notchmeow.html:471` |
| `greeting.headerDim` `#8D9098` (141, 144, 152) | `CatGreetingRenderer.swift:32` | `cat/greeting.ts:303` | `notchmeow.html:458, 461, 463, 474` |
| `greeting.card` `#141518` | none: the Mac draws no card | `cat/greeting.ts:272` | none |
| `greeting.streaks` (5 colours; from `cat-core.js`) | `CatGreeting.swift:94` | `cat/greeting.ts:74` | `cat-core.js:418` |
| `state.color` (11 colours; from `cat-core.js`) | `MotionProfiles.swift:10-11` | `cat/base.ts:54-56` | `cat-core.js:37` |
| `state.glow` (7 colours; from `cat-core.js`) | `MotionProfiles.swift:18`; the island's glow, `IslandRootView.swift:342-348` | `cat/base.ts:63-64`; the island's glow, `core/layout.ts:163-175` (every other line) | `cat-core.js:39` |

**Why the state colours, glows and streak palette are not in `theme.json`:** `tests/fixtures/cat/motion-cases.json` and `sequence-cases.json` pin them, so `cat-core.js` is their one home and the generator reads them from it. A second copy in `theme.json` could drift from the fixtures. **The same hex value in an existing view** (`#F5A524` in `IslandViewContent.swift`, `#F4505E` in `style.css`, and so on) is upstream's UI colour and stays; the two island-glow rows above are the exception, edited code of an existing view that stage 7 touches only with the owner's OK (same values, no change of look).

---

## File Structure

| Path | Responsibility |
|---|---|
| `design/prototype/cat-core.js` | The contract. A new section "Stored settings" above the end-of-core marker: `FOLLOW`, `MOTION_STYLES`, `motionStyleOf`, `motionOverrideOf`, `collarOverrideOf`, `catIdOf`, `cleanPersonality`, `cleanCatSettings`, `defaultCatSettings`, `applyToAllCats`, `motionFor`, `collarFor`, `engineCfg`. |
| `scripts/gen-cat-fixtures.mjs` | Gains the `settings-cases.json` builder above the `@@BUILDERS` marker. |
| `tests/fixtures/cat/settings-cases.json` | New fixture (generated, about 163 KB). |
| `tests/cat/settings.test.mjs` | New self-checks (19) and the fixture replay (3). |
| `tests/cat/fixtures.test.mjs` | The file list gains `settings-cases.json` (nine files). |
| `shared/theme.json` | New. The colours of the cat's details, the greeting and the fork's own pages. The one source for them. |
| `scripts/gen-theme.mjs` | New. Writes the three theme files from `theme.json` and the state colours of `cat-core.js`; `--check` fails when one is stale. Exports `problems`, `tokens`, `renderSwift`, `renderCss`, `renderTs`, `generate`, `stale`, `write`, `OUTPUTS`, `GROUPS`. |
| `NotchBuddy/Sources/App/Theme.generated.swift` | Generated. `enum Theme` with `Brand`, `Cat`, `Greeting`, `State`. Unused until stage 7. |
| `windows/src/theme.generated.css`, `windows/src/theme.generated.ts` | Generated. Unused until stage 7. |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | Regenerated by `xcodegen`: six lines for the new Swift file. |
| `tests/theme/gen-theme.test.mjs` | New self-checks for the generator (8). |
| `scripts/test-theme.sh` | New runner: the self-checks, then `--check`. |
| `.github/workflows/build.yml` | One CI step next to the cat contract. |
| `docs/CAT-CONTRACT.md` | A "Stored settings" section, the fixture row, the API row, three decisions. |
| `docs/THEME.md` | New. The tokens, the generated names, the inventory above, what is not a token. |
| `CLAUDE.md`, `ARCHITECT.md` | One pointer each (two bullets in `CLAUDE.md`). |

The "prove it bites" steps (Tasks 1 to 3) and Task 3's inventory check are one-offs and are never committed; the inventory script lives in `${TMPDIR:-/tmp}/a0d-check/`.

**Order of tasks:** the settings contract first (core, then its fixture), then the theme generator, then CI, docs and the final checks.

1. Stored cat settings in the core
2. `settings-cases.json`
3. Theme tokens: `theme.json`, the generator, the generated files
4. Runner, CI, docs and the final checks

## Tasks and agents

CLAUDE.md: the lightest model that fits. Tasks 1, 2 and 4 give every line of their code and docs, so they are transcription: `nm-implementer-light` (Haiku 4.5). Task 3 also gives its code, but it runs a typechecker, `xcodegen` and a long Debug build and judges their output, so it is `nm-implementer` (Sonnet 5.5, medium). Each task is then reviewed by `nm-reviewer`; the whole branch by `nm-reviewer-deep` after Task 4. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep`.

| Task | Deliverable | Agent | Review |
|---|---|---|---|
| 1. Stored cat settings in the core | `cat-core.js` section, `tests/cat/settings.test.mjs` (19 self-checks) | `nm-implementer-light` | `nm-reviewer` |
| 2. `settings-cases.json` | The generator builder, the fixture, 3 replay tests, nine-file list | `nm-implementer-light` | `nm-reviewer` |
| 3. Theme tokens | `theme.json`, `gen-theme.mjs`, 8 self-checks, the three generated files, the regenerated Xcode project, a green Debug build, the 175-site check | `nm-implementer` | `nm-reviewer` |
| 4. Runner, CI, docs, final checks | `test-theme.sh`, the CI step, `CAT-CONTRACT.md`, `THEME.md`, two pointers, the final checks | `nm-implementer-light` | `nm-reviewer` |
| After Task 4 | The whole branch: cross-task contracts, privacy and security rules | `nm-reviewer-deep` | — |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`).

## Execution

One worktree chat session runs the whole plan: branch `a0d/cat-settings-theme`, model **Sonnet 5.5 at medium effort** (ARCHITECT.md: a plan whose tasks are mostly given in full). Nothing is pushed. The Mac and Windows/Linux stage 5 to 7 plans are drafted from this plan's "Interface for the app plans" and can start once this branch is merged.

**Before the session starts,** the plan file is committed to `notchmeow/rebrand` (a docs-only commit): the controller does this, with the owner's OK, so the branch the session starts from already holds the plan it runs. **The base is `947e2d3` or later:** `git merge-base --is-ancestor 947e2d3 HEAD` must succeed.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c a0d/cat-settings-theme notchmeow/rebrand`, then `git merge-base --is-ancestor 947e2d3 HEAD` and `git ls-files docs/superpowers/plans/2026-10-07-a0d-cat-settings-theme.md`: the first must succeed and the second must print the plan's path. If either fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/plans/2026-10-07-a0d-cat-settings-theme.md` and `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message:

   > Run `docs/superpowers/plans/2026-10-07-a0d-cat-settings-theme.md` with `superpowers:subagent-driven-development`, task by task, on this branch. Dispatch each task to the agent the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. After Task 4, dispatch `nm-reviewer-deep` over the whole branch. Commit only as the plan's commit steps say, and never push. Never launch the app: Task 3 builds a Debug app in the worktree and only builds it. The work installs and downloads nothing (`npx --no-install` only). When you are done, report: the commits; the output of `node scripts/check-fixtures-additive.mjs 947e2d3`; the test counts of `bash scripts/test-cat-contract.sh` and `bash scripts/test-theme.sh`; the line `✓ all 175 sites hold the colour of their token`; whether the Debug build succeeded; and anything you could not settle.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

## Interface for the app plans

What the Mac and Windows/Linux plans for stages 5 to 7 consume. Names are exact.

### Stage 5 and 6: stored settings (`design/prototype/cat-core.js`, global `CatCore` / `require`)

| Name | Signature and meaning |
|---|---|
| `FOLLOW` | `'follow'`: a cat has no override of its own. Stored as this word. Not a motion style and not a collar style. |
| `MOTION_STYLES` | `['playful', 'classic']`, in the order Settings lists them. |
| `motionStyleOf(v)` | A stored global motion style to `'playful'` or `'classic'`; anything else is `'playful'`. |
| `motionOverrideOf(v)` | `'follow'`, `'playful'` or `'classic'`; anything else is `'follow'`. |
| `collarOverrideOf(v)` | `'follow'`, `'tag'`, `'band'`, `'kerchief'` or `'off'`; anything else is `'follow'`. (`collarStyleOf` from A-0b is the global one: anything else is `'off'`.) |
| `catIdOf(v)` | A stored cat ID to one of the 16 IDs; anything else is `'shrimpy'`. |
| `cleanPersonality(raw)` | An object, or JSON text of one, to `{preset, energy, curiosity, chatty, affection, sass, mischief}`. Not JSON, or not an object: Balanced. Traits through `normPers`. |
| `cleanCatSettings(raw)` | Anything to `{character, motionStyle, collar, furLines, cats: {<id>: {motion, collar, personality}}}` with all 16 cats, in `CAT_IDS` order. Never throws. |
| `defaultCatSettings()` | What a fresh install holds: `cleanCatSettings(null)`. |
| `applyToAllCats(settings, id)` | "Apply to every cat": copies cat `id`'s `motion`, `collar` and `personality` to all 16. Character and globals stay. |
| `motionFor(settings, id)` | The motion style a cat plays: its override, else the global style. |
| `collarFor(settings, id)` | The collar style a cat wears: its override, else the global collar. |
| `engineCfg(settings)` | `{motion, override, pers}`: the engine's `cfg` without `zoomAfter`. `override` has an entry only for a cat with a non-`follow` motion; `pers` has all 16 personalities. Feeds `CatConfig` (Mac) and `catCfg` (Windows/Linux), whose `override`/`pers` are keyed by cat ID. |

**How Custom is represented:** `preset: 'custom'`, with the six traits beside it (`{"preset":"custom","energy":0.27,…}`). It is the value `slide()` returns, it is not a key of `PERSONAS`, and the preset picker shows "Custom" when it sees it. A preset name is kept only when it is one of `balanced`, `chill`, `grumpy`, `sweet`, `hyper`, `chatty` **and** the traits equal that preset's (within 1e-9); otherwise the stored preset becomes `custom`. The Mac's existing `Personality.sanitized` keeps any string as the preset name: stage 5 changes it to follow this rule, and routes **every** stored `cat.personality.<id>` through it (the `Codable` decoding that throws on bad JSON is not used for stored values).

**The raw shape, and where it comes from.**

| macOS (`UserDefaults`) | Raw field |
|---|---|
| `cat.character` | `character` |
| `cat.motionStyle` | `motionStyle` |
| `cat.collar` | `collar` |
| `cat.furLines` | `furLines` (read the object, not `bool(forKey:)`: it must be a real boolean) |
| `cat.motion.<id>` | `cats.<id>.motion` |
| `cat.collar.<id>` | `cats.<id>.collar` |
| `cat.personality.<id>` | `cats.<id>.personality` (JSON text) |

**Writing back:** a change in Settings stores the clean value; a personality is stored as the JSON text of the clean object (keys in any order); `follow` is stored as the word `follow` (an absent key reads the same). Never store a value that did not go through the clean-up.

Windows and Linux: the `cat` block of `settings.rs` has the same shape (camelCase). Hold it as `serde_json::Value` when loading and run the Rust port of `cleanCatSettings` on it; a typed struct would make one bad field fail the whole settings file. Each app ports the clean-up natively and replays the fixture.

**Fixture:** `tests/fixtures/cat/settings-cases.json` (version 1, tolerance 1e-9). Keys: `ids` (the 16 IDs in order), `follow`, `motionStyles`, `collarStyles`, `defaults` (a clean value), `cases` (37 rows `{name, raw, out}`: `cleanCatSettings(raw) = out`), `personalities` (47 rows `{name, raw, out}`: `cleanPersonality(raw) = out`; a string `raw` is JSON text), `applyAll` (5 rows `{name, settings, from, out}`: `settings` is already clean), `derived` (3 rows `{name, settings, engineCfg, motionFor, collarFor}`: `settings` is already clean; `motionFor` and `collarFor` list one value per cat in `ids` order). The inputs include bad JSON text, wrong types, unknown IDs, out-of-range traits, missing fields, prototype names (`__proto__`, `constructor`) and a fully valid value. NaN and Infinity cannot be written in JSON: a port adds its own test for a real NaN trait (it counts as 0.5). `docs/CAT-CONTRACT.md` "Stored settings" has the notes for ports.

### Stage 7: theme tokens

| What | Value |
|---|---|
| Source | `shared/theme.json` (groups `brand`, `cat`, `greeting`); the `state` group and `greeting.streaks` are read from `cat-core.js` |
| Generate / check | `node scripts/gen-theme.mjs` / `node scripts/gen-theme.mjs --check` / `bash scripts/test-theme.sh` (CI) |
| macOS | `NotchBuddy/Sources/App/Theme.generated.swift`: `enum Theme { enum Brand, Cat, Greeting, State }`. A colour is `Theme.Cat.pupil` (`"#0E0B09"`) and `Theme.Cat.pupilRGB` (`[Double]`, `[14, 11, 9]`). `Theme.Greeting.streaks` (`[String]`), `Theme.Greeting.streaksRGB` (`[[Double]]`), `Theme.State.color["working"]`, `Theme.State.colorRGB`, `Theme.State.glow`, `Theme.State.glowRGB` (`[String: String]` and `[String: [Double]]`, keyed by `CatState.rawValue`). |
| Windows/Linux (TS) | `windows/src/theme.generated.ts`: `THEME.cat.pupil`, `THEME_RGB.cat.pupil`, `THEME.greeting.streaks[0]`, `THEME.state.color.working`, `THEME.state.glow.working` (both `as const`; hex and `[r, g, b]`). |
| Windows/Linux (CSS) | `windows/src/theme.generated.css`: `--nm-<group>-<name>` and `--nm-<group>-<name>-rgb`, for example `--nm-cat-pupil`, `--nm-cat-mouth-inside-rgb` (`58, 18, 24`), `--nm-greeting-streak-1`, `--nm-state-color-working`, `--nm-state-glow-working`. |
| Tokens (`brand`) | `accent`, `page`, `panel`, `line`, `ink`, `dim`, `button` |
| Tokens (`cat`) | `pupil`, `mouthInside`, `tongue`, `teeth`, `heart`, `star`, `sweat`, `paper`, `paperFold`, `paperLabel` |
| Tokens (`greeting`) | `badge`, `tint`, `haloGold`, `haloBlue`, `headerDim`, `card`, `streaks` (5) |
| Tokens (`state`) | `color` (11 states, in `STATES` order), `glow` (7 states) |
| Sites to replace | the table "Hard-coded colours today" above, copied to `docs/THEME.md` |

Stage 7 replaces exactly those sites, keeps every value, and so changes no pixel. A stage-7 plan that finds a value that differs from its token stops and asks.

---

### Task 1: Stored cat settings in the core

**Files:**
- Modify: `design/prototype/cat-core.js` (a new section above the `@@END-OF-CORE` marker)
- Create: `tests/cat/settings.test.mjs`

**Interfaces:**
- Consumes from the core: `own`, `CAT_IDS`, `COLLAR_STYLES`, `collarStyleOf`, `TRAIT_KEYS`, `PERSONAS`, `normPers`, `personaNamed`, `PROFILES` (in a test), `CatEngine`, `rng`, `ZOOM_AFTER_MS`, `slide`, `kittenOf`, `PRESETS`.
- Produces in `CatCore`: `FOLLOW`, `MOTION_STYLES`, `motionStyleOf`, `motionOverrideOf`, `collarOverrideOf`, `catIdOf`, `cleanPersonality`, `cleanCatSettings`, `defaultCatSettings`, `applyToAllCats`, `motionFor`, `collarFor`, `engineCfg`, exactly as in "Interface for the app plans" above.

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/cat/settings.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const IDS = core.CAT_IDS;
const TRAITS = core.TRAIT_KEYS;
const BALANCED = { preset: 'balanced', energy: .5, curiosity: .5, chatty: .5, affection: .5, sass: .5, mischief: .5 };
const clean = core.cleanCatSettings;
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
const cats = (id, entry) => ({ cats: { [id]: entry } });
const NOT_OBJECTS = [null, undefined, 'junk', '', 7, 0, NaN, true, false, [], [1, 2], ['character']];

test('the frozen words: FOLLOW, the two motion styles in Settings order, the four collar styles', () => {
  assert.equal(core.FOLLOW, 'follow');
  assert.deepEqual(core.MOTION_STYLES, ['playful', 'classic']);
  assert.deepEqual([...core.MOTION_STYLES].sort(), Object.keys(core.PROFILES).sort(), 'every motion profile is a style and the other way round');
  assert.ok(!core.MOTION_STYLES.includes('follow') && !core.COLLAR_STYLES.includes('follow'), 'follow is an override, never a style');
});

test('a fresh install: Shrimpy, Playful, collar off, no fur lines, 16 cats that follow the globals and are Balanced', () => {
  const d = core.defaultCatSettings();
  assert.deepEqual(Object.keys(d), ['character', 'motionStyle', 'collar', 'furLines', 'cats']);
  assert.deepEqual([d.character, d.motionStyle, d.collar, d.furLines], ['shrimpy', 'playful', 'off', false]);
  assert.deepEqual(Object.keys(d.cats), IDS);
  assert.deepEqual(IDS.slice(0, 2), ['shrimpy', 'momo']);
  for (const id of IDS) assert.deepEqual(d.cats[id], { motion: 'follow', collar: 'follow', personality: BALANCED }, id);
  assert.notEqual(core.defaultCatSettings().cats.momo, d.cats.momo, 'every call gives fresh objects');
});

test('anything that is not an object gives the defaults, and so does an object with nothing in it', () => {
  for (const raw of [...NOT_OBJECTS, {}, { cats: [] }, { cats: 'x' }, { cats: null }, { cats: 7 }]) assert.deepEqual(clean(raw), core.defaultCatSettings(), String(JSON.stringify(raw)));
});

test('a valid value comes back as it went in, and cleaning twice changes nothing', () => {
  const valid = clean({ character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, cats: {
    momo: { motion: 'playful', collar: 'kerchief', personality: core.personaNamed('chill') },
    shrimpy: { motion: 'classic', collar: 'off', personality: { ...core.personaNamed('sweet'), preset: 'sweet' } },
    ginger: { motion: 'follow', collar: 'tag', personality: { preset: 'custom', energy: .27, curiosity: .83, chatty: .41, affection: .58, sass: .12, mischief: .99 } } } });
  assert.deepEqual([valid.character, valid.motionStyle, valid.collar, valid.furLines], ['momo', 'classic', 'band', true]);
  assert.deepEqual(valid.cats.momo, { motion: 'playful', collar: 'kerchief', personality: core.personaNamed('chill') });
  assert.deepEqual(valid.cats.shrimpy.personality.preset, 'sweet');
  assert.deepEqual(valid.cats.ginger, { motion: 'follow', collar: 'tag', personality: { preset: 'custom', energy: .27, curiosity: .83, chatty: .41, affection: .58, sass: .12, mischief: .99 } });
  assert.deepEqual(clean(valid), valid);
  assert.deepEqual(clean(JSON.parse(JSON.stringify(valid))), valid, 'it survives being written as JSON and read back');
});

test('the character: the 16 frozen IDs stay, everything else is Shrimpy, prototype names included', () => {
  for (const id of IDS) assert.equal(clean({ character: id }).character, id);
  for (const bad of ['tiger', 'Momo', 'MOMO', ' momo', 'momo ', '', 'momo kitten', 'siamese', '__proto__', 'constructor', 'toString', 'hasOwnProperty', null, undefined, 7, true, {}, ['momo']]) assert.equal(clean({ character: bad }).character, 'shrimpy', String(bad));
});

test('the global motion style and collar: only the frozen words count, and "follow" is not one of them', () => {
  for (const s of core.MOTION_STYLES) assert.equal(clean({ motionStyle: s }).motionStyle, s);
  for (const bad of ['follow', 'Classic', 'PLAYFUL', ' classic', 'bogus', '', null, 7, true, ['classic']]) assert.equal(clean({ motionStyle: bad }).motionStyle, 'playful', String(bad));
  for (const s of core.COLLAR_STYLES) assert.equal(clean({ collar: s }).collar, s);
  for (const bad of ['follow', 'scarf', 'Tag', ' tag', 'bowtie', '', null, 7, true, ['band']]) assert.equal(clean({ collar: bad }).collar, 'off', String(bad));
});

test('fur lines are on only for a real boolean true', () => {
  assert.equal(clean({ furLines: true }).furLines, true);
  for (const bad of [false, 1, 0, 'true', 'yes', 'on', 'TRUE', null, [true], { value: true }, 7]) assert.equal(clean({ furLines: bad }).furLines, false, String(JSON.stringify(bad)));
});

test('a cat\'s own motion and collar: a valid word stays, anything else means "follow", and "off" is a real override', () => {
  for (const m of ['follow', ...core.MOTION_STYLES]) assert.equal(clean(cats('momo', { motion: m })).cats.momo.motion, m);
  for (const bad of ['Classic', 'bogus', '', null, 7, true, ['classic'], {}]) assert.equal(clean(cats('momo', { motion: bad })).cats.momo.motion, 'follow', String(JSON.stringify(bad)));
  for (const c of ['follow', ...core.COLLAR_STYLES]) assert.equal(clean(cats('momo', { collar: c })).cats.momo.collar, c);
  for (const bad of ['scarf', 'Tag', 'bogus', '', null, 7, true, ['tag'], {}]) assert.equal(clean(cats('momo', { collar: bad })).cats.momo.collar, 'follow', String(JSON.stringify(bad)));
  assert.equal(clean({ collar: 'tag', ...cats('momo', { collar: 'off' }) }).cats.momo.collar, 'off', 'a cat can be set to no collar while the global one is on');
});

test('the cats map: always the 16 cats in order, unknown IDs and unknown keys dropped, a bad entry is the defaults', () => {
  const raw = { theme: 'dark', cats: { tiger: { motion: 'classic' }, momo: 'x', ginger: null, noodle: [], puff: { motion: 'classic', wardrobe: 'hat', personality: { preset: 'balanced', label: 'Balanced', hat: 1 } }, constructor: { motion: 'classic' }, ['__proto__']: { motion: 'classic' } } };
  const out = clean(raw);
  assert.deepEqual(Object.keys(out), ['character', 'motionStyle', 'collar', 'furLines', 'cats']);
  assert.deepEqual(Object.keys(out.cats), IDS);
  for (const id of IDS) assert.deepEqual(Object.keys(out.cats[id]), ['motion', 'collar', 'personality'], id);
  assert.deepEqual(out.cats.momo, core.defaultCatSettings().cats.momo);
  assert.deepEqual(out.cats.ginger, core.defaultCatSettings().cats.ginger);
  assert.deepEqual(out.cats.puff, { motion: 'classic', collar: 'follow', personality: BALANCED });
  assert.equal(Object.getPrototypeOf(out.cats), Object.prototype);
  assert.ok(!Object.keys(out.cats).includes('tiger') && !Object.keys(out.cats).includes('constructor'));
});

test('personality: the six presets, as an object and as the JSON text the Mac stores, come back the same', () => {
  for (const name of Object.keys(core.PERSONAS)) {
    const p = core.personaNamed(name);
    assert.deepEqual(core.cleanPersonality(p), p, name);
    assert.deepEqual(core.cleanPersonality(JSON.stringify(p)), p, `${name} as JSON text`);
    assert.deepEqual(Object.keys(core.cleanPersonality(p)), ['preset', ...TRAITS]);
  }
});

test('personality: Custom is the word "custom" with the six traits, and a slider move stays Custom even back on a preset\'s numbers', () => {
  const moved = core.slide(core.personaNamed('chill'), 'sass', .9);
  assert.equal(moved.preset, 'custom');
  assert.deepEqual(core.cleanPersonality(moved), moved);
  assert.deepEqual(core.cleanPersonality(JSON.stringify(moved)), moved);
  const back = core.slide(core.personaNamed('chill'), 'energy', .12);
  assert.deepEqual(back, { ...core.personaNamed('chill'), preset: 'custom' });
  assert.equal(core.cleanPersonality(back).preset, 'custom');
  assert.ok(!('custom' in core.PERSONAS), 'custom is not one of the six presets');
});

test('personality: a preset name is kept only while the traits are still that preset\'s', () => {
  const chill = core.personaNamed('chill');
  assert.equal(core.cleanPersonality({ ...chill, energy: .12000000000000001 }).preset, 'chill', 'float noise is within the tolerance');
  assert.equal(core.cleanPersonality({ ...chill, energy: .120000000001 }).preset, 'chill', '1e-12 away is still Chill');
  assert.equal(core.cleanPersonality({ ...chill, energy: .120001 }).preset, 'custom', '1e-6 away is a different personality');
  assert.equal(core.cleanPersonality({ ...chill, energy: .9 }).preset, 'custom');
  assert.equal(core.cleanPersonality({ ...chill, preset: 'sweet' }).preset, 'custom', 'a name that does not match the traits');
  assert.equal(core.cleanPersonality({ ...chill, preset: 'Chill' }).preset, 'custom');
  assert.equal(core.cleanPersonality({ ...chill, preset: 'moody' }).preset, 'custom');
  assert.equal(core.cleanPersonality({ ...chill, preset: 7 }).preset, 'custom');
  const noName = { ...chill }; delete noName.preset;
  assert.equal(core.cleanPersonality(noName).preset, 'custom', 'traits that equal a preset but name none are Custom');
  assert.deepEqual(core.cleanPersonality({ preset: 'chill' }), { preset: 'custom', ...Object.fromEntries(TRAITS.map(k => [k, .5])) }, 'a name alone: the traits are missing, so 0.5, which is not Chill');
  assert.deepEqual(core.cleanPersonality({ preset: 'balanced' }), BALANCED);
});

test('personality: JSON that is not JSON, or not an object, is Balanced', () => {
  for (const bad of ['', ' ', 'not json', '{', '{"energy":0.2', "{'energy':0.2}", '{"energy":0.2,}', '{"energy":NaN}', '{"energy":Infinity}', '{"energy":0.2} x', 'undefined', '[1,2]', 'null', '"x"', '42', 'true', '[]', '{"preset"', null, undefined, 7, true, [], [1], NaN]) {
    assert.deepEqual(core.cleanPersonality(bad), BALANCED, String(JSON.stringify(bad)));
  }
  assert.deepEqual(core.cleanPersonality('{}'), { preset: 'custom', ...Object.fromEntries(TRAITS.map(k => [k, .5])) }, 'an object with nothing in it is not "nothing stored": its traits are the missing ones');
});

test('personality: traits are held to 0..1, a missing or non-number trait is 0.5, and nothing is NaN', () => {
  const wrong = { energy: 'high', curiosity: null, chatty: true, affection: [1], sass: {}, mischief: '0.9' };
  assert.deepEqual(core.cleanPersonality(wrong), { preset: 'custom', ...Object.fromEntries(TRAITS.map(k => [k, .5])) });
  assert.deepEqual(core.cleanPersonality(JSON.stringify(wrong)), core.cleanPersonality(wrong));
  const wild = core.cleanPersonality({ energy: 7, curiosity: -2, chatty: NaN, affection: Infinity, sass: -Infinity, mischief: 1e300 });
  assert.deepEqual([wild.energy, wild.curiosity, wild.chatty, wild.affection, wild.sass, wild.mischief], [1, 0, .5, .5, .5, 1]);
  for (const v of Object.values(wild)) assert.ok(typeof v === 'string' || Number.isFinite(v));
  assert.equal(Object.is(core.cleanPersonality({ energy: -0 }).energy, -0), false, 'minus zero is stored as 0');
});

test('applyToAllCats copies one cat\'s motion override, collar override and personality to all 16, and nothing else', () => {
  const s = clean({ character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, cats: {
    ginger: { motion: 'playful', collar: 'off', personality: { ...core.personaNamed('hyper') } }, momo: { motion: 'classic', collar: 'tag', personality: core.personaNamed('grumpy') } } });
  const before = JSON.stringify(s);
  const out = core.applyToAllCats(s, 'ginger');
  assert.equal(JSON.stringify(s), before, 'the input is not touched');
  assert.deepEqual([out.character, out.motionStyle, out.collar, out.furLines], ['momo', 'classic', 'band', true]);
  assert.deepEqual(Object.keys(out.cats), IDS);
  for (const id of IDS) assert.deepEqual(out.cats[id], { motion: 'playful', collar: 'off', personality: core.personaNamed('hyper') }, id);
  out.cats.momo.personality.energy = .01;
  assert.equal(out.cats.ginger.personality.energy, 1, 'no two cats share one personality object');
  assert.equal(core.applyToAllCats(s, 'shrimpy').cats.momo.motion, 'follow', 'follow is copied as follow: the cats keep following the global style');
  assert.deepEqual(core.applyToAllCats(s, 'tiger'), core.applyToAllCats(s, 'shrimpy'), 'an unknown cat is Shrimpy');
  assert.deepEqual(core.applyToAllCats(core.applyToAllCats(s, 'ginger'), 'ginger'), core.applyToAllCats(s, 'ginger'), 'doing it twice changes nothing');
  assert.deepEqual(core.applyToAllCats({ cats: { momo: { motion: 'classic' } } }, 'momo').cats.noodle.motion, 'classic', 'a dirty input is cleaned first');
});

test('motionFor and collarFor: the cat\'s own word, else the global one', () => {
  const s = clean({ motionStyle: 'classic', collar: 'band', cats: { momo: { motion: 'playful', collar: 'off' }, ginger: { motion: 'follow', collar: 'kerchief' } } });
  assert.deepEqual(['momo', 'ginger', 'shrimpy'].map(id => core.motionFor(s, id)), ['playful', 'classic', 'classic']);
  assert.deepEqual(['momo', 'ginger', 'shrimpy'].map(id => core.collarFor(s, id)), ['off', 'kerchief', 'band']);
  assert.equal(core.motionFor(s, 'tiger'), 'classic', 'an unknown cat is Shrimpy, which follows');
  assert.equal(core.collarFor(null, 'momo'), 'off');
  assert.equal(core.motionFor(null, 'momo'), 'playful');
});

test('engineCfg is what the engine reads: the global style, the overrides that exist, every personality', () => {
  const s = clean({ motionStyle: 'classic', cats: { momo: { motion: 'playful', personality: core.personaNamed('sweet') }, ginger: { motion: 'follow' }, noodle: { motion: 'bogus' } } });
  const cfg = core.engineCfg(s);
  assert.deepEqual(Object.keys(cfg), ['motion', 'override', 'pers']);
  assert.equal(cfg.motion, 'classic');
  assert.deepEqual(cfg.override, { momo: 'playful' });
  assert.deepEqual(Object.keys(cfg.pers), IDS);
  assert.deepEqual(cfg.pers.momo, core.personaNamed('sweet'));
  const make = (preset, id) => new core.CatEngine(preset, { cfg: { ...core.engineCfg(s), zoomAfter: core.ZOOM_AFTER_MS }, quiet: true, now: () => 0, rand: core.rng(1), state: 'idle' });
  assert.equal(make(core.PRESETS.momo).motion, 'playful');
  assert.equal(make(core.PRESETS.ginger).motion, 'classic');
  assert.equal(make(core.PRESETS.shrimpy).motion, 'classic');
  assert.equal(make(core.kittenOf(core.PRESETS.momo)).motion, 'playful', 'a kitten plays its parent\'s style');
  assert.equal(make(core.kittenOf(core.PRESETS.momo)).pers.preset, 'sweet', 'and wears its parent\'s personality');
});

test('the input is never changed, even when it is frozen', () => {
  const raw = deepFreeze({ character: 'momo', cats: { momo: { motion: 'classic', personality: { preset: 'chill', energy: .12 } } } });
  assert.doesNotThrow(() => clean(raw));
  assert.doesNotThrow(() => core.applyToAllCats(raw, 'momo'));
});

test('hostile values never throw: 3000 random settings come out valid, and cleaning them again changes nothing', () => {
  const r = core.rng(2026), pool = ['momo', 'tiger', 'classic', 'playful', 'follow', 'off', 'band', 'tag', 'kerchief', '', ' ', 'chill', 'custom', '{', '{"energy":2}', '{"preset":"sweet","affection":1,"energy":0.5,"curiosity":0.55,"chatty":0.55,"sass":0.1,"mischief":0.3}', '__proto__', 'constructor', null, true, false, 0, 1, -1, .5, 7, 1e300, [], [1], {}, { energy: 9 }, { preset: 'hyper' }];
  const pick = () => pool[Math.floor(r() * pool.length)];
  const entry = () => ({ motion: pick(), collar: pick(), personality: pick() });
  const valid = s => IDS.includes(s.character) && core.MOTION_STYLES.includes(s.motionStyle) && core.COLLAR_STYLES.includes(s.collar) && typeof s.furLines === 'boolean'
    && JSON.stringify(Object.keys(s.cats)) === JSON.stringify(IDS)
    && IDS.every(id => ['follow', ...core.MOTION_STYLES].includes(s.cats[id].motion) && ['follow', ...core.COLLAR_STYLES].includes(s.cats[id].collar)
      && TRAITS.every(k => Number.isFinite(s.cats[id].personality[k]) && s.cats[id].personality[k] >= 0 && s.cats[id].personality[k] <= 1)
      && (s.cats[id].personality.preset === 'custom' || own(core.PERSONAS, s.cats[id].personality.preset)));
  const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
  for (let i = 0; i < 3000; i++) {
    const raw = { character: pick(), motionStyle: pick(), collar: pick(), furLines: pick(), cats: r() < .1 ? pick() : Object.fromEntries(IDS.filter(() => r() < .5).map(id => [id, r() < .1 ? pick() : entry()])) };
    const out = clean(raw);
    assert.ok(valid(out), JSON.stringify(raw));
    assert.deepEqual(clean(out), out);
    assert.ok(valid(core.applyToAllCats(raw, pick())));
    assert.doesNotThrow(() => core.engineCfg(raw));
  }
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/settings.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 19`, `# pass 0`, `# fail 19`: the core has no `cleanCatSettings` yet.

- [ ] **Step 3: Add the section to the core**

This inserts "Stored settings" above the `@@END-OF-CORE` marker, after the engine. It reuses `normPers`, `personaNamed`, `PERSONAS`, `COLLAR_STYLES` and `CAT_IDS`; nothing else in the file changes.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── Stored settings: what the Cat section of Settings saves, cleaned ────────
// Settings saves a character, a motion style, a collar style and the fur-lines switch, and per cat a motion override, a collar
// override and a personality. A settings file can be hand-edited, copied from an older build or half written, so both apps pass
// what they read through cleanCatSettings before anything else sees it. Raw in, clean out, never a throw.
// The shape is the same on both sides, raw or clean (the Mac builds the raw one from its UserDefaults keys, cat.character,
// cat.motion.<id> and so on; Windows and Linux read their `cat` block):
//   {character, motionStyle, collar, furLines, cats: {<id>: {motion, collar, personality}}}   with all 16 cat IDs once clean.
/** "No override: use the global setting." Stored as this word. It is not a motion style and not a collar style. */
const FOLLOW='follow';
/** The motion styles, in the order Settings lists them. Playful is the default; an unknown stored style plays Playful. */
const MOTION_STYLES=['playful','classic'];
const motionStyleOf=v=>MOTION_STYLES.includes(v)?v:'playful';
/** A cat's own motion: 'follow' or a style. Anything else (an unknown style, a number, null) is 'follow': no valid override. */
const motionOverrideOf=v=>MOTION_STYLES.includes(v)?v:FOLLOW;
/** A cat's own collar: 'follow' or one of the four collar styles ('off' included, which is an override like any other). Anything else is 'follow'. */
const collarOverrideOf=v=>COLLAR_STYLES.includes(v)?v:FOLLOW;
/** A stored cat ID to a cat ID. An unknown ID, or anything that is not a string, is Shrimpy (as catById does). */
const catIdOf=v=>CAT_IDS.includes(v)?v:'shrimpy';
const isPlain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const sameTraits=(a,b)=>TRAIT_KEYS.every(k=>Math.abs(a[k]-b[k])<=1e-9);
/**
 * A stored personality to a clean one: {preset, energy, curiosity, chatty, affection, sass, mischief}. It may be an object, or the JSON
 * text of one (the Mac keeps the text). Text that is not JSON, and JSON that is not an object, give Balanced. The traits go through
 * normPers (held to 0..1, missing or not a number is 0.5). 'custom' is how a hand-tuned personality is stored: the preset is kept only
 * when it names one of the six AND the traits are still that preset's (within 1e-9); anything else, a missing or unknown name included, is 'custom'.
 */
function cleanPersonality(raw){let v=raw;
 if(typeof v==='string'){try{v=JSON.parse(v)}catch{return personaNamed('balanced')}}
 if(!isPlain(v))return personaNamed('balanced');
 const traits=normPers(v),named=typeof v.preset==='string'&&own(PERSONAS,v.preset)?v.preset:null;
 return{preset:named&&sameTraits(traits,PERSONAS[named])?named:'custom',...traits}}
/** Everything Settings saves, cleaned. Never throws; unknown keys are dropped; the result always holds all 16 cats, in CAT_IDS order. */
function cleanCatSettings(raw){const r=isPlain(raw)?raw:{},cats=isPlain(r.cats)?r.cats:{},out={character:catIdOf(r.character),motionStyle:motionStyleOf(r.motionStyle),collar:collarStyleOf(r.collar),furLines:r.furLines===true,cats:{}};
 for(const id of CAT_IDS){const c=own(cats,id)&&isPlain(cats[id])?cats[id]:{};out.cats[id]={motion:motionOverrideOf(c.motion),collar:collarOverrideOf(c.collar),personality:cleanPersonality(c.personality)}}
 return out}
/** What a fresh install holds: Shrimpy, Playful, collar off, no fur lines, every cat following the globals with a Balanced personality. */
const defaultCatSettings=()=>cleanCatSettings(null);
/** "Apply to every cat": every cat gets the motion override, collar override and personality of cat `id` (an unknown ID is Shrimpy). The character and the global settings stay. */
function applyToAllCats(settings,id){const s=cleanCatSettings(settings),from=s.cats[catIdOf(id)],out={...s,cats:{}};
 for(const c of CAT_IDS)out.cats[c]={motion:from.motion,collar:from.collar,personality:{...from.personality}};
 return out}
/** The motion style a cat plays: its own override, else the global style. */
function motionFor(settings,id){const s=cleanCatSettings(settings),m=s.cats[catIdOf(id)].motion;return m===FOLLOW?s.motionStyle:m}
/** The collar style a cat wears (when it has a colour to wear): its own override, else the global style. */
function collarFor(settings,id){const s=cleanCatSettings(settings),c=s.cats[catIdOf(id)].collar;return c===FOLLOW?s.collar:c}
/** The shared settings an engine reads (the `cfg` of CatEngine, without zoomAfter): the global style, an override for each cat that has one, every cat's personality. */
function engineCfg(settings){const s=cleanCatSettings(settings),override={},pers={};
 for(const id of CAT_IDS){const c=s.cats[id];if(c.motion!==FOLLOW)override[id]=c.motion;pers[id]=c.personality}
 return{motion:s.motionStyle,override,pers}}
Object.assign(api,{FOLLOW,MOTION_STYLES,motionStyleOf,motionOverrideOf,collarOverrideOf,catIdOf,cleanPersonality,cleanCatSettings,defaultCatSettings,applyToAllCats,motionFor,collarFor,engineCfg});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 51 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/settings.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 19`, `# pass 19`, `# fail 0`.

- [ ] **Step 5: Prove the strict-boolean test bites (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = 'furLines:r.furLines===true'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'furLines:!!r.furLines'))
PY
node --test tests/cat/settings.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = 'furLines:!!r.furLines'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'furLines:r.furLines===true'))
PY
node --test tests/cat/settings.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: first run `not ok 7 - fur lines are on only for a real boolean true`, `# pass 18`, `# fail 1`; after putting the line back, `# pass 19` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 135`, `# pass 135`, `# fail 0`; eight `✓` fixture lines, `✓ 8 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. (No fixture changed yet: the 116 old tests and the 19 new ones.)

- [ ] **Step 7: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js` and `?? tests/cat/settings.test.mjs` (plus, in a dry-run clone, the `windows/node_modules` link; never `git add` it).

```bash
git add design/prototype/cat-core.js tests/cat/settings.test.mjs
git commit -m "feat(cat): the settings Settings saves are cleaned by cleanCatSettings, in the core

Reuses the personality rules and the frozen cat and collar IDs. follow is the word for no override.
Custom is the word custom with the six traits. A bad value is the neutral one and never a throw.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: `settings-cases.json`

**Files:**
- Modify: `scripts/gen-cat-fixtures.mjs` (a new builder above the `@@BUILDERS` marker)
- Modify: `tests/cat/settings.test.mjs` (three replay tests appended), `tests/cat/fixtures.test.mjs` (nine files, not eight)
- Create: `tests/fixtures/cat/settings-cases.json` (generated)

**Interfaces:**
- Consumes: Task 1's functions; `compare`, `fix`, `format` and `FILES` from the generator.
- Produces: `settings-cases.json` with the keys listed in "Interface for the app plans". It is the only file added or changed under `tests/fixtures/cat/`.

- [ ] **Step 1: Write the failing replay tests**

```bash
cat >> tests/cat/settings.test.mjs <<'EOF'

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/settings-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));

test('settings-cases.json: the frozen words, the defaults and the cat IDs are the core\'s', () => {
  assert.deepEqual(fx.ids, IDS);
  assert.equal(fx.follow, core.FOLLOW);
  assert.deepEqual(fx.motionStyles, core.MOTION_STYLES);
  assert.deepEqual(fx.collarStyles, core.COLLAR_STYLES);
  assert.deepEqual(compare(roundTrip(core.defaultCatSettings()), fx.defaults), []);
});

test('settings-cases.json: every case replays from its own input', () => {
  for (const c of fx.cases) assert.deepEqual(compare(roundTrip(clean(c.raw)), c.out), [], c.name);
  for (const c of fx.personalities) assert.deepEqual(compare(roundTrip(core.cleanPersonality(c.raw)), c.out), [], c.name);
  for (const c of fx.applyAll) assert.deepEqual(compare(roundTrip(core.applyToAllCats(c.settings, c.from)), c.out), [], c.name);
  for (const c of fx.derived) {
    assert.deepEqual(compare(roundTrip(core.engineCfg(c.settings)), c.engineCfg), [], c.name);
    assert.deepEqual(IDS.map(id => core.motionFor(c.settings, id)), c.motionFor, c.name);
    assert.deepEqual(IDS.map(id => core.collarFor(c.settings, id)), c.collarFor, c.name);
  }
});

test('settings-cases.json: the inputs the spec worries about are in it (bad JSON, wrong types, unknown IDs, out-of-range traits, a valid value)', () => {
  const names = fx.cases.map(c => c.name), people = fx.personalities.map(c => c.name);
  for (const n of ['nothing stored', 'a fully valid value', 'an unknown character', 'follow is not a global style', 'fur lines as the number 1', 'overrides that are not valid', 'cats is an array', 'prototype names as cats', 'a personality that is not JSON', 'a personality stored as JSON text']) assert.ok(names.includes(n), n);
  for (const n of ['a cut-off object', 'NaN written in the text', 'wrong types', 'traits out of range', 'a name that does not match the traits', 'custom with the numbers of a preset', 'float noise on a preset is still the preset', 'JSON that is an array']) assert.ok(people.includes(n), n);
  assert.ok(fx.personalities.filter(c => typeof c.raw === 'string').length >= 14, 'text inputs');
  assert.ok(fx.cases.some(c => c.out.character === 'momo' && c.out.furLines === true), 'a valid value that keeps its settings');
});
EOF
python3 - <<'PY'
p = 'tests/cat/fixtures.test.mjs'
s = open(p, encoding='utf-8').read()
for was, now in [("'presets.json', 'search-tools.json', 'sequence-cases.json', 'warp-cases.json'];", "'presets.json', 'search-tools.json', 'sequence-cases.json', 'settings-cases.json', 'warp-cases.json'];"), ('holds exactly the eight contract files', 'holds exactly the nine contract files')]:
    assert s.count(was) == 1, was
    s = s.replace(was, now)
open(p, 'w', encoding='utf-8').write(s)
PY
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/settings.test.mjs tests/cat/fixtures.test.mjs 2>&1 | grep -E "^(not ok|# (pass|fail))|ENOENT" | head`
Expected: `not ok` lines for the fixtures tests (the list now says nine files, and `settings-cases.json` does not exist yet), `ENOENT` lines that name `settings-cases.json`, and `not ok … - tests/cat/settings.test.mjs`: the replay part of that file cannot load without the fixture. The 19 self-checks from Task 1 still pass.

- [ ] **Step 3: Add the builder and generate the fixture**

The builder goes above the `@@BUILDERS` marker. Its rows are what a settings file could hold, written as JSON.

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '// @@BUILDERS: each task adds'
assert s.count(marker) == 1
snippet = r'''// ── Stored cat settings (A-0d): what the Cat section of Settings saves, cleaned ──
// Every `raw` is something a settings file could hold, written as JSON (so no NaN or Infinity: the self-checks cover those, and
// a number that no JSON parser reads the same way, such as 1e999, is left out on purpose). `out` is what cleanCatSettings returns.
FILES['settings-cases.json'] = () => {
  const J = JSON.stringify, P = n => core.personaNamed(n), clean = core.cleanCatSettings;
  const custom = { preset: 'custom', energy: .27, curiosity: .83, chatty: .41, affection: .58, sass: .12, mischief: .99 };
  const noise = '{"preset":"chill","energy":0.12000000000000001,"curiosity":0.35,"chatty":0.3,"affection":0.65,"sass":0.3,"mischief":0.2}';
  const wrongTypes = { energy: 'high', curiosity: null, chatty: true, affection: [1], sass: {}, mischief: '0.9' };
  const one = (id, entry, rest = {}) => ({ ...rest, cats: { [id]: entry } });
  const rows = [
    ['nothing stored', null],
    ['an empty object', {}],
    ['text instead of an object', 'junk'],
    ['a number instead of an object', 7],
    ['an array instead of an object', [1, 2, 3]],
    ['true instead of an object', true],
    ['a fully valid value', { character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, cats: {
      momo: { motion: 'playful', collar: 'kerchief', personality: P('chill') },
      shrimpy: { motion: 'classic', collar: 'off', personality: P('sweet') },
      ginger: { motion: 'follow', collar: 'tag', personality: custom } } }],
    ['only the global settings', { character: 'momo', motionStyle: 'classic', collar: 'tag', furLines: true }],
    ['an unknown character', { character: 'tiger' }],
    ['a character in the wrong case', { character: 'Momo' }],
    ['a kitten is not a character', { character: 'momo kitten' }],
    ['a prototype name as the character', { character: '__proto__' }],
    ['another prototype name as the character', { character: 'constructor' }],
    ['a number as the character', { character: 7 }],
    ['styles that do not exist', { motionStyle: 'bogus', collar: 'scarf' }],
    ['follow is not a global style', { motionStyle: 'follow', collar: 'follow' }],
    ['styles in the wrong case', { motionStyle: 'Classic', collar: 'Band' }],
    ['styles of the wrong type', { motionStyle: 7, collar: true }],
    ['fur lines true', { furLines: true }],
    ['fur lines as the number 1', { furLines: 1 }],
    ['fur lines as the text true', { furLines: 'true' }],
    ['fur lines as null', { furLines: null }],
    ['valid overrides for some cats', { cats: { momo: { motion: 'classic', collar: 'band' }, ginger: { motion: 'playful', collar: 'off' }, noodle: { motion: 'follow', collar: 'kerchief' } } }],
    ['overrides that are not valid', { cats: { momo: { motion: 'bogus', collar: 'scarf' }, ginger: { motion: 7, collar: null }, noodle: { motion: 'Classic', collar: 'Tag' } } }],
    ['off is an override, not a missing collar', { collar: 'tag', cats: { momo: { collar: 'off' } } }],
    ['cats is an array', { cats: [] }],
    ['cats is text', { cats: 'x' }],
    ['cats is null', { cats: null }],
    ['cat entries that are not objects', { cats: { momo: 'x', ginger: null, noodle: [], puff: 7 } }],
    ['unknown cats and unknown keys', { theme: 'dark', cats: { tiger: { motion: 'classic' }, momo: { wardrobe: 'hat' } } }],
    ['prototype names as cats', { cats: { constructor: { motion: 'classic' }, ['__proto__']: { motion: 'classic' } } }],
    ['a personality stored as JSON text', one('momo', { personality: J(P('grumpy')) }, { character: 'momo' })],
    ['a personality that is not JSON', one('momo', { personality: '{"energy":' })],
    ['a personality that is not an object', { cats: { momo: { personality: 7 }, ginger: { personality: [1] }, noodle: { personality: null } } }],
    ['a personality with the wrong types', one('momo', { personality: wrongTypes })],
    ['a preset whose traits were changed', one('momo', { personality: { ...P('chill'), energy: .9 } })],
    ['a preset name that matches the traits', one('momo', { personality: P('hyper') })],
  ];
  const people = [
    ...Object.keys(core.PERSONAS).map(n => [`preset ${n} as an object`, P(n)]),
    ...Object.keys(core.PERSONAS).map(n => [`preset ${n} as JSON text`, J(P(n))]),
    ['custom values as an object', custom],
    ['custom values as JSON text', J(custom)],
    ['float noise on a preset is still the preset', noise],
    ['a preset changed by one slider', { ...P('chill'), sass: .9 }],
    ['a preset changed by 1e-6', { ...P('chill'), energy: .120001 }],
    ['custom with the numbers of a preset', { ...P('chill'), preset: 'custom' }],
    ['a name that does not match the traits', { ...P('chill'), preset: 'sweet' }],
    ['a preset name in the wrong case', { ...P('chill'), preset: 'Chill' }],
    ['an unknown preset name', { ...P('chill'), preset: 'moody' }],
    ['a preset name that is not text', { ...P('chill'), preset: 7 }],
    ['traits without a preset name', { energy: .12, curiosity: .35, chatty: .3, affection: .65, sass: .3, mischief: .2 }],
    ['a preset name alone', { preset: 'chill' }],
    ['balanced alone', { preset: 'balanced' }],
    ['an empty object', {}],
    ['an empty object as text', '{}'],
    ['traits out of range', { preset: 'custom', energy: 7, curiosity: -2, chatty: 1.5, affection: 100, sass: -.1, mischief: 2 }],
    ['wrong types', wrongTypes],
    ['wrong types as JSON text', J(wrongTypes)],
    ['numbers as text', { preset: 'custom', energy: '0.9', curiosity: '1' }],
    ['unknown keys are dropped', { ...P('sweet'), label: 'Sweet', hat: 1 }],
    ['nothing stored', null],
    ['text that is not JSON', 'not json'],
    ['an empty string', ''],
    ['a cut-off object', '{"preset":"chill","energy":0.12'],
    ['single quotes', "{'energy':0.2}"],
    ['a trailing comma', '{"energy":0.2,}'],
    ['NaN written in the text', '{"energy":NaN}'],
    ['garbage after the object', '{"energy":0.2} x'],
    ['JSON that is an array', '[1,2]'],
    ['JSON that is null', 'null'],
    ['JSON that is a number', '42'],
    ['JSON that is a string', '"x"'],
    ['a number instead of an object', 7],
    ['an array instead of an object', [0.1, 0.2]],
    ['true instead of an object', true],
  ];
  const applySource = clean({ character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, cats: {
    ginger: { motion: 'playful', collar: 'off', personality: P('hyper') }, momo: { motion: 'classic', collar: 'tag', personality: P('grumpy') }, noodle: { personality: custom } } });
  const apply = [
    ['a customised cat to every cat', applySource, 'ginger'],
    ['a cat that follows to every cat', applySource, 'shrimpy'],
    ['a personality that is Custom to every cat', applySource, 'noodle'],
    ['an unknown cat is Shrimpy', applySource, 'tiger'],
    ['a default install', core.defaultCatSettings(), 'momo'],
  ].map(([name, settings, from]) => ({ name, settings, from, out: core.applyToAllCats(settings, from) }));
  const derive = [
    ['a default install', core.defaultCatSettings()],
    ['global Classic with a few overrides', clean({ motionStyle: 'classic', collar: 'band', cats: { momo: { motion: 'playful', collar: 'off' }, ginger: { motion: 'follow', collar: 'kerchief' }, noodle: { motion: 'classic', collar: 'tag', personality: P('sweet') } } })],
    ['global Playful, every cat overridden', core.applyToAllCats(clean({ cats: { momo: { motion: 'classic', collar: 'kerchief', personality: P('chatty') } } }), 'momo')],
  ].map(([name, settings]) => ({ name, settings, engineCfg: core.engineCfg(settings), motionFor: core.CAT_IDS.map(id => core.motionFor(settings, id)), collarFor: core.CAT_IDS.map(id => core.collarFor(settings, id)) }));
  return {
    version: 1,
    note: 'Raw is what a settings file might hold, written as JSON. cases: cleanCatSettings(raw) is out. personalities: cleanPersonality(raw) is out; a raw string is JSON text. applyAll, derived: settings are already clean. motionFor and collarFor list one value per cat in ids order.',
    ids: core.CAT_IDS,
    follow: core.FOLLOW,
    motionStyles: core.MOTION_STYLES,
    collarStyles: core.COLLAR_STYLES,
    defaults: core.defaultCatSettings(),
    cases: rows.map(([name, raw]) => ({ name, raw, out: clean(raw) })),
    personalities: people.map(([name, raw]) => ({ name, raw, out: core.cleanPersonality(raw) })),
    applyAll: apply,
    derived: derive,
  };
};

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/settings-cases.json
```

Expected: `wrote 9 fixture files to tests/fixtures/cat` and a `settings-cases.json` of about 163 KB (under the 400 KB the fixtures test allows).

- [ ] **Step 4: Run the tests and the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok|✓|✗"`
Expected: `# tests 138`, `# pass 138`, `# fail 0`; nine `✓` fixture lines (`settings-cases.json` among them), `✓ 9 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 5: Prove the fixture is additive**

Run: `node scripts/check-fixtures-additive.mjs 947e2d3`
Expected: eight `✓ <file>: N old lines unchanged` lines (`collar-cases.json` 187, `geometry-cases.json` 180, `motion-cases.json` 713, `personality-cases.json` 62, `presets.json` 42, `search-tools.json` 36, `sequence-cases.json` 231, `warp-cases.json` 121), `+ settings-cases.json is new` and `✓ fixtures changed only by addition since 947e2d3`.

Run: `git diff --stat -- tests/fixtures/cat`
Expected: no output (no existing fixture changed; the new one is untracked).

- [ ] **Step 6: Prove the no-drift check covers the new file (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = 'furLines:r.furLines===true'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'furLines:!!r.furLines'))
PY
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E "✗|Fixtures drifted"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = 'furLines:!!r.furLines'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'furLines:r.furLines===true'))
PY
node scripts/gen-cat-fixtures.mjs --check | tail -1
```

Expected: first `✗ settings-cases.json drifted from cat-core.js (` followed by a number of differences, and `Fixtures drifted. cat-core.js is the tie-breaker…`; after putting the line back, `✓ 9 fixture files match cat-core.js`.

- [ ] **Step 7: Commit**

Run: `git status --short`
Expected: ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/fixtures.test.mjs`, ` M tests/cat/settings.test.mjs`, `?? tests/fixtures/cat/settings-cases.json` (and the dry-run `windows/node_modules` link).

```bash
git add scripts/gen-cat-fixtures.mjs tests/cat/fixtures.test.mjs tests/cat/settings.test.mjs tests/fixtures/cat/settings-cases.json
git commit -m "test(cat): settings-cases.json pins the stored-settings clean-up for both apps

37 settings, 47 personalities, 5 apply-to-every-cat and 3 derived cases. Bad JSON, wrong types, unknown IDs,
out-of-range traits, missing fields, prototype names and a valid value. The other eight fixtures are untouched.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 3: Theme tokens: `theme.json`, the generator, the generated files

**Files:**
- Create: `shared/theme.json`, `scripts/gen-theme.mjs`, `tests/theme/gen-theme.test.mjs`
- Create (generated): `NotchBuddy/Sources/App/Theme.generated.swift`, `windows/src/theme.generated.css`, `windows/src/theme.generated.ts`
- Modify (regenerated): `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`
- One-off, not committed: `${TMPDIR:-/tmp}/a0d-check/sites.mjs`

**Interfaces:**
- Consumes: `CatCore.COL`, `GLOW`, `STATES`, `STREAKS` from the core (read with `require`).
- Produces `scripts/gen-theme.mjs`: exports `GROUPS` (`['brand', 'cat', 'greeting']`), `OUTPUTS` (`{swift, css, ts}`, paths relative to the repository root), `problems(theme)` to a list of messages (empty when `theme.json` is valid), `tokens(theme, core)` to the tree `{brand, cat, greeting, state}` (`greeting.streaks` is the five-colour palette; `state` is `{color, glow}`), `renderSwift(tree)`, `renderCss(tree)`, `renderTs(tree)`, `generate(theme?, core?)` to `{path: text}`, `stale(files, root?)` to the paths whose file is missing or differs, `write(files, root?)`. Command line: `node scripts/gen-theme.mjs` writes the three files; `--check` writes nothing and exits 1 naming the stale ones. Generated names are in "Interface for the app plans".

- [ ] **Step 1: Write the failing tests**

```bash
mkdir -p tests/theme
cat > tests/theme/gen-theme.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { GROUPS, OUTPUTS, generate, problems, stale, tokens, write } from '../../scripts/gen-theme.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const ROOT = new URL('../../', import.meta.url).pathname;
const theme = JSON.parse(fs.readFileSync(path.join(ROOT, 'shared/theme.json'), 'utf8'));
const bad = patch => problems({ ...structuredClone(theme), ...patch });

test('shared/theme.json is valid: version 1, the three groups, every colour #RRGGBB in capitals', () => {
  assert.deepEqual(problems(theme), []);
  assert.deepEqual(Object.keys(theme).filter(k => k !== 'version' && k !== 'note'), GROUPS);
  assert.deepEqual(GROUPS, ['brand', 'cat', 'greeting']);
});

test('a theme.json with a mistake is refused, with a message that names it', () => {
  assert.match(problems(null)[0], /not an object/);
  assert.match(bad({ version: 2 })[0], /version must be 1/);
  assert.match(bad({ wardrobe: {} })[0], /unknown key "wardrobe"/);
  assert.match(bad({ brand: undefined })[0], /group "brand" is missing/);
  assert.match(bad({ brand: {} })[0], /group "brand" is missing or empty/);
  assert.match(bad({ cat: { ...theme.cat, pupil: '#0e0b09' } })[0], /cat\.pupil.*capitals/);
  assert.match(bad({ cat: { ...theme.cat, pupil: '#FFF' } })[0], /cat\.pupil/);
  assert.match(bad({ cat: { ...theme.cat, pupil: 7 } })[0], /cat\.pupil/);
  assert.match(bad({ cat: { ...theme.cat, 'mouth-inside': '#3A1218' } })[0], /lowerCamelCase/);
  assert.match(bad({ greeting: { ...theme.greeting, streaks: '#3B9EFF' } }).join(), /reserved/);
  assert.throws(() => tokens({ ...theme, version: 2 }, core), /shared\/theme.json: version must be 1/);
});

test('the tokens: theme.json\'s groups, the greeting\'s streak palette and the state colours from the cat core', () => {
  const t = tokens(theme, core);
  assert.deepEqual(Object.keys(t), ['brand', 'cat', 'greeting', 'state']);
  assert.deepEqual(t.greeting.streaks, ['#3B9EFF', '#F29B38', '#FF5A4E', '#2EC4A0', '#A78BFA']);
  assert.deepEqual(Object.keys(t.state.color), core.STATES);
  assert.deepEqual(Object.keys(t.state.glow), core.STATES.filter(s => core.GLOW[s]));
  for (const s of core.STATES) assert.equal(t.state.color[s], core.COL[s].toUpperCase(), s);
  for (const s of Object.keys(t.state.glow)) assert.equal(t.state.glow[s], core.GLOW[s].toUpperCase(), s);
  for (const sk of core.STREAKS) assert.ok(t.greeting.streaks.includes(sk.col.toUpperCase()));
});

test('the Swift file: one enum per group, every colour with its RGB twin, valid Swift 6 values', () => {
  const swift = generate()[OUTPUTS.swift];
  assert.match(swift, /^\/\/ GENERATED by scripts\/gen-theme.mjs/);
  assert.deepEqual([...swift.matchAll(/^ {4}enum (\w+) \{/gm)].map(m => m[1]), ['Brand', 'Cat', 'Greeting', 'State']);
  assert.match(swift, /static let pupil = "#0E0B09"\n {8}static let pupilRGB: \[Double\] = \[14, 11, 9\]\n/);
  assert.match(swift, /static let tintRGB: \[Double\] = \[127, 180, 234\]/);
  assert.match(swift, /static let streaks: \[String\] = \["#3B9EFF", "#F29B38", "#FF5A4E", "#2EC4A0", "#A78BFA"\]/);
  assert.match(swift, /static let glow: \[String: String\] = \["working": "#3B9EFF", "thinking": "#A78BFA"/);
  const hexes = [...swift.matchAll(/static let (\w+) = "#/g)].map(m => m[1]);
  for (const name of hexes) assert.ok(swift.includes(`static let ${name}RGB: [Double]`), name);
  assert.ok(swift.endsWith('}\n'));
});

test('the CSS file: custom properties with the --nm- prefix, every colour with its -rgb twin', () => {
  const css = generate()[OUTPUTS.css];
  assert.match(css, /^\/\* GENERATED by scripts\/gen-theme.mjs/);
  assert.match(css, /\n:root \{\n {2}--nm-brand-accent: #5EEAD4;\n {2}--nm-brand-accent-rgb: 94, 234, 212;\n/);
  assert.match(css, /--nm-cat-mouth-inside: #3A1218;/);
  assert.match(css, /--nm-greeting-streak-5: #A78BFA;/);
  assert.match(css, /--nm-state-color-ratelimit: #FB923C;/);
  assert.match(css, /--nm-state-glow-ratelimit: #F59E0B;/);
  const names = [...css.matchAll(/^ {2}(--nm-[a-z0-9-]+): #/gm)].map(m => m[1]);
  assert.equal(names.length, 7 + 10 + 6 + 5 + 11 + 7, 'brand, cat, greeting, streaks, state colours, state glows');
  for (const n of names) assert.ok(css.includes(`  ${n}-rgb: `), n);
  assert.equal(new Set(names).size, names.length, 'no name twice');
  assert.ok(css.endsWith('}\n'));
});

test('the TypeScript file is plain data that matches the tokens, as hex and as RGB', () => {
  const ts = generate()[OUTPUTS.ts];
  assert.match(ts, /^\/\/ GENERATED by scripts\/gen-theme.mjs/);
  const js = ts.replace(/export const (\w+) = /g, 'const $1 = ').replace(/ as const;/g, ';');
  const { THEME, THEME_RGB } = new Function(`${js}\nreturn { THEME, THEME_RGB };`)();
  const t = tokens(theme, core);
  assert.deepEqual(THEME, t);
  const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const walk = (v, f) => (typeof v === 'string' ? f(v) : Array.isArray(v) ? v.map(x => walk(x, f)) : Object.fromEntries(Object.entries(v).map(([k, x]) => [k, walk(x, f)])));
  assert.deepEqual(THEME_RGB, walk(t, rgb));
  assert.deepEqual(THEME_RGB.greeting.tint, [127, 180, 234]);
  assert.ok(ts.includes('} as const;'));
});

test('the generated files are the ones in the repository, and the generator is deterministic', () => {
  assert.deepEqual(stale(generate(), ROOT), []);
  assert.deepEqual(generate(), generate());
  assert.deepEqual(Object.values(OUTPUTS), ['NotchBuddy/Sources/App/Theme.generated.swift', 'windows/src/theme.generated.css', 'windows/src/theme.generated.ts']);
});

test('--check\'s test: a missing, edited or untouched file is told apart', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nm-theme-'));
  try {
    for (const rel of Object.values(OUTPUTS)) fs.mkdirSync(path.join(dir, path.dirname(rel)), { recursive: true });
    const files = generate();
    assert.deepEqual(stale(files, dir), Object.values(OUTPUTS), 'nothing written yet: all three are missing');
    write(files, dir);
    assert.deepEqual(stale(files, dir), []);
    fs.appendFileSync(path.join(dir, OUTPUTS.css), '\n');
    assert.deepEqual(stale(files, dir), [OUTPUTS.css], 'a stray newline is enough');
    write(files, dir);
    const changed = generate({ ...structuredClone(theme), cat: { ...theme.cat, heart: '#FF0000' } });
    assert.deepEqual(stale(changed, dir), Object.values(OUTPUTS), 'a changed token makes all three stale');
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/theme/gen-theme.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (pass|fail)"`
Expected: `ERR_MODULE_NOT_FOUND` for `scripts/gen-theme.mjs`, `# fail 1`.

- [ ] **Step 3: Write `theme.json` and the generator**

`theme.json` holds exactly the values that are hard-coded today (the inventory above). The generator is table-driven: one token tree, three renderers.

```bash
mkdir -p shared
cat > shared/theme.json <<'EOF'
{
  "version": 1,
  "note": "NotchMeow's colours that are not in the cat presets: the cat's own details, the launch greeting, and the fork's own pages. Colours only, as #RRGGBB in capitals. The state colours, the state glows and the greeting's streak colours are not here: they are pinned by tests/fixtures/cat/, so the generator reads them from design/prototype/cat-core.js. Edit this file, then run: node scripts/gen-theme.mjs",
  "brand": {
    "accent": "#5EEAD4",
    "page": "#0F1012",
    "panel": "#17181B",
    "line": "#2A2C31",
    "ink": "#ECECEE",
    "dim": "#9A9CA3",
    "button": "#202227"
  },
  "cat": {
    "pupil": "#0E0B09",
    "mouthInside": "#3A1218",
    "tongue": "#E8798C",
    "teeth": "#FBF7F0",
    "heart": "#FF4D6D",
    "star": "#F7B32B",
    "sweat": "#7CC7FF",
    "paper": "#F4F5F7",
    "paperFold": "#C9CDD4",
    "paperLabel": "#3B9EFF"
  },
  "greeting": {
    "badge": "#3BA0F5",
    "tint": "#7FB4EA",
    "haloGold": "#E8C39A",
    "haloBlue": "#3B9EFF",
    "headerDim": "#8D9098",
    "card": "#141518"
  }
}
EOF
cat > scripts/gen-theme.mjs <<'EOF'
#!/usr/bin/env node
// Writes the three theme files from shared/theme.json:
//   NotchBuddy/Sources/App/Theme.generated.swift   (macOS)
//   windows/src/theme.generated.css                (Windows and Linux, CSS custom properties)
//   windows/src/theme.generated.ts                 (Windows and Linux, TypeScript)
//   node scripts/gen-theme.mjs            write them
//   node scripts/gen-theme.mjs --check    write nothing; exit 1 if a file differs from what would be written (CI)
// The state colours, the state glows and the greeting's streak colours are pinned by tests/fixtures/cat/, so they are read from
// design/prototype/cat-core.js rather than copied into theme.json. Node standard library only.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const THEME_JSON = path.join(ROOT, 'shared/theme.json');
export const OUTPUTS = {
  swift: 'NotchBuddy/Sources/App/Theme.generated.swift',
  css: 'windows/src/theme.generated.css',
  ts: 'windows/src/theme.generated.ts',
};
/** The groups of theme.json, in output order. `state` is not one of them: it comes from the cat core. */
export const GROUPS = ['brand', 'cat', 'greeting'];
const HEX = /^#[0-9A-F]{6}$/, NAME = /^[a-z][A-Za-z0-9]*$/;
const isObj = x => x !== null && typeof x === 'object' && !Array.isArray(x);

/** What is wrong with a parsed theme.json, as a list of messages. Empty when it is fine. */
export function problems(theme) {
  const out = [];
  if (!isObj(theme)) return ['theme.json is not an object'];
  if (theme.version !== 1) out.push(`version must be 1, not ${JSON.stringify(theme.version)}`);
  for (const key of Object.keys(theme)) if (key !== 'version' && key !== 'note' && !GROUPS.includes(key)) out.push(`unknown key "${key}" (the groups are ${GROUPS.join(', ')})`);
  for (const g of GROUPS) {
    if (!isObj(theme[g]) || !Object.keys(theme[g]).length) { out.push(`group "${g}" is missing or empty`); continue; }
    for (const [name, value] of Object.entries(theme[g])) {
      if (!NAME.test(name)) out.push(`${g}.${name}: a name is lowerCamelCase letters and digits`);
      if (typeof value !== 'string' || !HEX.test(value)) out.push(`${g}.${name}: ${JSON.stringify(value)} is not #RRGGBB in capitals`);
    }
  }
  if (isObj(theme.greeting) && 'streaks' in theme.greeting) out.push('greeting.streaks is reserved: it comes from the cat core');
  return out;
}

/** The whole token tree: theme.json's groups, plus greeting.streaks and state.{color, glow} from the cat core. */
export function tokens(theme, core) {
  const bad = problems(theme);
  if (bad.length) throw new Error(`shared/theme.json: ${bad.join('; ')}`);
  const tree = Object.fromEntries(GROUPS.map(g => [g, { ...theme[g] }]));
  tree.greeting.streaks = [...new Set(core.STREAKS.map(s => s.col.toUpperCase()))]; // the palette the sixteen streaks cycle through
  tree.state = { color: Object.fromEntries(core.STATES.map(s => [s, core.COL[s].toUpperCase()])), glow: Object.fromEntries(core.STATES.filter(s => core.GLOW[s]).map(s => [s, core.GLOW[s].toUpperCase()])) };
  return tree;
}

const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const kebab = n => n.replace(/[A-Z]/g, c => `-${c.toLowerCase()}`);
const pascal = n => n[0].toUpperCase() + n.slice(1);
const HEAD = 'GENERATED by scripts/gen-theme.mjs from shared/theme.json and design/prototype/cat-core.js. Do not edit: change the source and run `node scripts/gen-theme.mjs`.';
const NOTE = 'Colours of the cat, the launch greeting and NotchMeow\'s own pages. Each is "#RRGGBB" and, as RGB, [r, g, b] from 0 to 255.';
/** A value of the tree is a colour, a list of colours or a map of name to colour. */
const kind = v => (typeof v === 'string' ? 'one' : Array.isArray(v) ? 'list' : 'map');

export function renderSwift(t) {
  const lines = [`// ${HEAD}`, `// ${NOTE}`, '', 'enum Theme {'];
  const arr = c => `[${rgb(c).join(', ')}]`;
  Object.entries(t).forEach(([g, group], gi) => {
    if (gi) lines.push('');
    lines.push(`    enum ${pascal(g)} {`);
    for (const [name, v] of Object.entries(group)) {
      if (kind(v) === 'one') lines.push(`        static let ${name} = "${v}"`, `        static let ${name}RGB: [Double] = ${arr(v)}`);
      else if (kind(v) === 'list') lines.push(`        static let ${name}: [String] = [${v.map(c => `"${c}"`).join(', ')}]`, `        static let ${name}RGB: [[Double]] = [${v.map(arr).join(', ')}]`);
      else lines.push(`        static let ${name}: [String: String] = [${Object.entries(v).map(([k, c]) => `"${k}": "${c}"`).join(', ')}]`, `        static let ${name}RGB: [String: [Double]] = [${Object.entries(v).map(([k, c]) => `"${k}": ${arr(c)}`).join(', ')}]`);
    }
    lines.push('    }');
  });
  lines.push('}');
  return `${lines.join('\n')}\n`;
}

export function renderCss(t) {
  const lines = [`/* ${HEAD} */`, `/* ${NOTE} */`, ':root {'];
  const pair = (n, c) => lines.push(`  --nm-${n}: ${c};`, `  --nm-${n}-rgb: ${rgb(c).join(', ')};`);
  for (const [g, group] of Object.entries(t)) for (const [name, v] of Object.entries(group)) {
    if (kind(v) === 'one') pair(`${g}-${kebab(name)}`, v);
    else if (kind(v) === 'list') v.forEach((c, i) => pair(`${g}-${kebab(name).replace(/s$/, '')}-${i + 1}`, c));
    else for (const [k, c] of Object.entries(v)) pair(`${g}-${kebab(name)}-${k}`, c);
  }
  lines.push('}');
  return `${lines.join('\n')}\n`;
}

export function renderTs(t) {
  const lines = [`// ${HEAD}`, `// ${NOTE}`];
  const block = (name, doc, f) => {
    lines.push('', `/** ${doc} */`, `export const ${name} = {`);
    for (const [g, group] of Object.entries(t)) {
      lines.push(`  ${g}: {`);
      for (const [n, v] of Object.entries(group)) {
        if (kind(v) === 'one') lines.push(`    ${n}: ${f(v)},`);
        else if (kind(v) === 'list') lines.push(`    ${n}: [${v.map(f).join(', ')}],`);
        else lines.push(`    ${n}: { ${Object.entries(v).map(([k, c]) => `${k}: ${f(c)}`).join(', ')} },`);
      }
      lines.push('  },');
    }
    lines.push('} as const;');
  };
  block('THEME', 'Every colour as "#RRGGBB".', c => `"${c}"`);
  block('THEME_RGB', 'The same colours as [r, g, b], 0 to 255, for canvas code that builds rgba() strings.', c => `[${rgb(c).join(', ')}]`);
  return `${lines.join('\n')}\n`;
}

/** All three files as {relative path: text}. */
export function generate(theme = JSON.parse(fs.readFileSync(THEME_JSON, 'utf8')), core = createRequire(import.meta.url)('../design/prototype/cat-core.js')) {
  const t = tokens(theme, core);
  return { [OUTPUTS.swift]: renderSwift(t), [OUTPUTS.css]: renderCss(t), [OUTPUTS.ts]: renderTs(t) };
}

/** The paths (relative to `root`) of the generated files that are missing or differ from `files`. */
export function stale(files, root = ROOT) {
  return Object.keys(files).filter(rel => !fs.existsSync(path.join(root, rel)) || fs.readFileSync(path.join(root, rel), 'utf8') !== files[rel]);
}

/** Writes the generated files under `root`. */
export function write(files, root = ROOT) {
  for (const [rel, text] of Object.entries(files)) fs.writeFileSync(path.join(root, rel), text);
}

function main(argv) {
  const files = generate();
  if (argv.includes('--check')) {
    const old = stale(files);
    for (const rel of Object.keys(files)) console.log(`  ${old.includes(rel) ? '✗' : '✓'} ${rel}`);
    if (old.length) { console.log('Theme files are stale. Run: node scripts/gen-theme.mjs, then commit the result.'); process.exit(1); }
    console.log(`✓ ${Object.keys(files).length} theme files match shared/theme.json`);
    return;
  }
  write(files);
  console.log(`wrote ${Object.keys(files).length} theme files`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) main(process.argv.slice(2));
EOF
```

- [ ] **Step 4: Run the tests (one still fails: the generated files do not exist yet)**

Run: `node --test tests/theme/gen-theme.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `not ok 7 - the generated files are the ones in the repository, and the generator is deterministic`, `# tests 8`, `# pass 7`, `# fail 1`.

- [ ] **Step 5: Generate the three files, and run the tests again**

Run: `node scripts/gen-theme.mjs`
Expected: `wrote 3 theme files`.

Run: `node --test tests/theme/gen-theme.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 8`, `# pass 8`, `# fail 0`.

Run: `node scripts/gen-theme.mjs --check; echo "exit $?"`
Expected: three `  ✓ <path>` lines, `✓ 3 theme files match shared/theme.json` and `exit 0`.

- [ ] **Step 6: Prove `--check` bites (not committed)**

```bash
sed -i.bak 's/"heart": "#FF4D6D"/"heart": "#FF4D6E"/' shared/theme.json
node scripts/gen-theme.mjs --check; echo "exit $?"
mv shared/theme.json.bak shared/theme.json
node scripts/gen-theme.mjs --check | tail -1
git status --short shared
```

Expected: first three `  ✗ <path>` lines, `Theme files are stale. Run: node scripts/gen-theme.mjs, then commit the result.` and `exit 1`; then `✓ 3 theme files match shared/theme.json`; and `?? shared/` (the directory is still untracked, no `.bak` left inside: `ls shared` shows only `theme.json`).

- [ ] **Step 7: Prove the generated Swift and TypeScript compile**

Run: `swiftc -swift-version 6 -strict-concurrency=complete -typecheck NotchBuddy/Sources/App/Theme.generated.swift; echo "exit $?"`
Expected: `exit 0` and no other output (Swift 6 with the project's strict concurrency).

A fresh worktree has no `windows/node_modules`. Link the main checkout's (never install); in a dry-run clone it is already linked:

```bash
[ -e windows/node_modules ] || ln -s "$(git worktree list --porcelain | sed -n '1s/^worktree //p')/windows/node_modules" windows/node_modules
ls windows/node_modules/.bin/tsc
```

Expected: `windows/node_modules/.bin/tsc`. The link shows as `?? windows/node_modules` in `git status`: never `git add` it.

Run: `cd windows && npx --no-install tsc --noEmit; echo "exit $?"; cd ..`
Expected: `exit 0` and no other output. (`windows/node_modules` is in the worktree; in a dry-run clone it is a link to the main checkout's.)

- [ ] **Step 8: Add the Swift file to the Xcode project and build**

The project is generated by XcodeGen, so the new file needs a regenerated `project.pbxproj`. Never edit it by hand.

Run: `cd NotchBuddy && xcodegen && cd ..`
Expected: `Created project at …/NotchBuddy/NotchBuddy.xcodeproj`.

Run: `git diff --stat -- NotchBuddy/NotchBuddy.xcodeproj`
Expected: ` NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj | 6 ++++++` and `1 file changed, 6 insertions(+)`: the file in the group, and in the Sources phase of the NotchBuddy target and of the App Store target. Nothing else differs.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **` (a few minutes on a cold build). The build only builds: do not open the app. `NotchBuddy/build/` is ignored by git.

- [ ] **Step 9: Prove the inventory (not committed)**

This checks every line of the table "Hard-coded colours today" (175 checks): the line must hold its token's colour, as hex in any case or as `r, g, b`. It also proves that `theme.json` holds exactly today's values, so stage 7 changes no pixel.

```bash
mkdir -p "${TMPDIR:-/tmp}/a0d-check"
cat > "${TMPDIR:-/tmp}/a0d-check/sites.mjs" <<'EOF'
// One-off: proves that every hard-coded site listed in docs/THEME.md still holds the colour its token says (run from the repo root).
import fs from 'node:fs';
import { createRequire } from 'node:module';
const core = createRequire(import.meta.url)(`${process.cwd()}/design/prototype/cat-core.js`);
const theme = JSON.parse(fs.readFileSync('shared/theme.json', 'utf8'));
const A = 'NotchBuddy/Sources/App/', W = 'windows/src/', P = 'design/prototype/';
const CF = `${A}CatFace.swift`, CE = `${A}CatEffects.swift`, CG = `${A}CatGreetingRenderer.swift`, RT = `${W}cat/renderer.ts`, GT = `${W}cat/greeting.ts`, HT = `${P}notchmeow.html`, DV = `${W}cat/dev.ts`;
// token -> [[file, line, ...], ...]; a token matches a line by its hex (any case), its r, g, b triple, or a special needle
const SITES = {
  'cat.pupil': [[CF, 64], [RT, 275], [HT, 203]],
  'cat.mouthInside': [[CF, 170], [RT, 403], [HT, 260]],
  'cat.tongue': [[CF, 154], [RT, 404, 411, 424], [HT, 261, 263, 268]],
  'cat.teeth': [[CF, 178], [RT, 406], [HT, 262]],
  'cat.heart': [[CF, 116], [CE, 127], [RT, 300, 377], [HT, 218, 241]],
  'cat.star': [[CF, 120], [CE, 130], [RT, 301, 378], [HT, 219, 242]],
  'cat.sweat': [[CE, 139], [RT, 380], [HT, 244]],
  'cat.paper': [[CE, 158], [RT, 443], [HT, 398]],
  'cat.paperFold': [[CE, 159], [RT, 444], [HT, 399]],
  'cat.paperLabel': [[CE, 160], [RT, 445], [HT, 400]],
  'greeting.badge': [[CG, 41], [GT, 186], [HT, 476]],
  'greeting.tint': [[CG, 41, 66], [GT, 177, 187], [HT, 476]],
  'greeting.haloGold': [[CG, 16], [GT, 291], [HT, 471]],
  'greeting.haloBlue': [[CG, 16], [GT, 291], [HT, 471]],
  'greeting.headerDim': [[CG, 32], [GT, 303], [HT, 458, 461, 463, 474]],
  'greeting.card': [[GT, 272]],
  'brand.accent': [[HT, 15], [DV, 72, 93]],
  'brand.page': [[`${A}CatDevPanel.swift`, 330], [DV, 80], [HT, 15]],
  'brand.panel': [[DV, 55], [HT, 15]],
  'brand.line': [[DV, 19, 55, 72, 93, 135], [HT, 15, 497]],
  'brand.ink': [[DV, 19, 72, 81, 131], [HT, 15, 496]],
  'brand.dim': [[DV, 56, 64, 85, 141, 159, 175], [HT, 15, 499]],
  'brand.button': [[DV, 19], [HT, 26]],
};
const SPECIAL = { 'greeting.haloGold': /lerp\(232, ?59, ?bl\)/, 'greeting.haloBlue': /lerp\(232, ?59, ?bl\)/, 'brand.page': /#0F1012|blue: 0\.071/i };
const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
let bad = 0, n = 0;
const check = (name, hex, file, line) => {
  const text = fs.readFileSync(file, 'utf8').split('\n')[line - 1] ?? '';
  const [r, g, b] = rgb(hex), special = SPECIAL[name];
  const ok = text.toLowerCase().includes(hex.toLowerCase()) || new RegExp(`\\b${r}, ?${g}, ?${b}\\b`).test(text) || (special && special.test(text));
  n++; if (!ok) { bad++; console.log(`  ✗ ${name} ${hex} is not on ${file}:${line}: ${text.trim().slice(0, 100)}`); }
};
for (const [name, list] of Object.entries(SITES)) {
  const [g, k] = name.split('.');
  for (const [file, ...lines] of list) for (const line of lines) check(name, theme[g][k], file, line);
}
// the contract-held colours: each table line holds its colours
const tables = [[`${A}MotionProfiles.swift`, [10, 11], core.COL], [`${A}MotionProfiles.swift`, [18], core.GLOW], [`${W}cat/base.ts`, [54, 55, 56], core.COL], [`${W}cat/base.ts`, [63, 64], core.GLOW],
  [`${P}cat-core.js`, [37], core.COL], [`${P}cat-core.js`, [39], core.GLOW]];
const glowSites = [[`${A}IslandRootView.swift`, 342, 343, 344, 345, 346, 347, 348], [`${W}core/layout.ts`, 163, 165, 167, 169, 171, 173, 175]];
const glowOrder = ['working', 'thinking', 'searching', 'approval', 'error', 'finished', 'ratelimit'];
for (const [file, ...lines] of glowSites) lines.forEach((l, i) => check(`state.glow.${glowOrder[i]}`, core.GLOW[glowOrder[i]], file, l));
const streakSites = [[`${A}CatGreeting.swift`, 94], [`${W}cat/greeting.ts`, 74], [`${P}cat-core.js`, 418]];
for (const [file, line] of streakSites) for (const c of [...new Set(core.STREAKS.map(s => s.col))]) check('greeting.streaks', c, file, line);
for (const [file, lines, table] of tables) for (const hex of new Set(Object.values(table))) {
  const text = lines.map(l => fs.readFileSync(file, 'utf8').split('\n')[l - 1]).join('\n').toLowerCase();
  n++; if (!text.includes(hex.toLowerCase())) { bad++; console.log(`  ✗ state table ${hex} is not on ${file}:${lines.join(',')}`); }
}
console.log(bad ? `${bad} of ${n} sites do not hold their colour` : `✓ all ${n} sites hold the colour of their token`);
process.exit(bad ? 1 : 0);
EOF
node "${TMPDIR:-/tmp}/a0d-check/sites.mjs"
```

Expected: `✓ all 175 sites hold the colour of their token`. A line that moved prints `✗ <token> <hex> is not on <file>:<line>: …`; if one does, find the new line number by value (`grep -nE '#0E0B09' <file>`), correct this plan's table and `docs/THEME.md` in Task 4 and the script, and say so in the report. Do not change a value.

- [ ] **Step 10: Commit**

Run: `git status --short`
Expected: ` M NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`, `?? NotchBuddy/Sources/App/Theme.generated.swift`, `?? scripts/gen-theme.mjs`, `?? shared/`, `?? tests/theme/`, `?? windows/src/theme.generated.css`, `?? windows/src/theme.generated.ts` (and the dry-run `windows/node_modules` link).

```bash
git add shared/theme.json scripts/gen-theme.mjs tests/theme/gen-theme.test.mjs NotchBuddy/Sources/App/Theme.generated.swift windows/src/theme.generated.css windows/src/theme.generated.ts NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(theme): shared/theme.json and a generator for the Swift, CSS and TypeScript theme files

23 colours of the cat's details, the greeting and the fork's own pages, plus the state colours, glows and streak
palette that cat-core.js pins. --check fails when a generated file is stale. The apps do not use the files yet (stage 7).

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Runner, CI, docs and the final checks

**Files:**
- Create: `scripts/test-theme.sh`, `docs/THEME.md`
- Modify: `.github/workflows/build.yml`, `docs/CAT-CONTRACT.md`, `CLAUDE.md`, `ARCHITECT.md`

**Interfaces:**
- Consumes: Tasks 1 to 3.
- Produces: `bash scripts/test-theme.sh` (the self-checks, then `--check`; CI runs it); the docs the app plans cite.

- [ ] **Step 1: The runner**

```bash
cat > scripts/test-theme.sh <<'EOF'
#!/usr/bin/env bash
# Runs the theme check: the generator's self-checks, then proof that the three generated files match shared/theme.json
# and the state colours of cat-core.js. CI runs it next to the cat contract.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v node >/dev/null || { echo "node (22 or newer) is required" >&2; exit 1; }
node --test tests/theme/*.test.mjs
node scripts/gen-theme.mjs --check
EOF
```

Run: `bash scripts/test-theme.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 8`, `# pass 8`, `# fail 0`, three `  ✓ <path>` lines and `✓ 3 theme files match shared/theme.json`.

- [ ] **Step 2: The CI step and the pointers**

One CI step next to the cat contract, one bullet pair in `CLAUDE.md` and one sentence in `ARCHITECT.md`.

```bash
python3 - <<'PY'
# CI step, and one pointer each in CLAUDE.md and ARCHITECT.md.
def patch(path, anchor, add, where='after'):
    s = open(path, encoding='utf-8').read()
    assert s.count(anchor) == 1, (path, anchor)
    i = s.index(anchor)
    j = s.index('\n', i + len(anchor) - 1) if where == 'eol' else i + len(anchor)
    open(path, 'w', encoding='utf-8').write(s[:j] + add + s[j:])

patch('.github/workflows/build.yml',
      '        run: bash scripts/test-cat-contract.sh\n',
      '\n      - name: Theme tokens (generator self-checks, generated files up to date)\n        run: bash scripts/test-theme.sh\n')

patch('CLAUDE.md',
      'After changing it, run `node scripts/gen-cat-fixtures.mjs` and commit the fixtures.\n',
      '- `cleanCatSettings` in `cat-core.js` is the one clean-up rule for the Cat settings both apps store (`tests/fixtures/cat/settings-cases.json`; `docs/CAT-CONTRACT.md`, "Stored settings"). An app reads the stored values as plain JSON values, cleans them, and uses only the result.\n'
      '- `shared/theme.json` holds the colours of the cat\'s details, the greeting and the fork\'s own pages; the state colours come from `cat-core.js`. `node scripts/gen-theme.mjs` writes `Theme.generated.swift`, `theme.generated.css` and `theme.generated.ts` from them, and `bash scripts/test-theme.sh` fails on stale ones (`docs/THEME.md`). Existing views keep their colours.\n')

patch('ARCHITECT.md',
      'in `tests/fixtures/cat/` (see `docs/CAT-CONTRACT.md`).',
      ' The Cat settings both apps store are cleaned by `cleanCatSettings` (`settings-cases.json`), and `shared/theme.json` feeds the generated theme files (`docs/THEME.md`).')
PY
git diff --stat -- .github CLAUDE.md ARCHITECT.md
```

Expected: `.github/workflows/build.yml | 3 +++`, `ARCHITECT.md | 2 +-`, `CLAUDE.md | 2 ++` and `3 files changed, 6 insertions(+), 1 deletion(-)`.

- [ ] **Step 3: `docs/CAT-CONTRACT.md` and `docs/THEME.md`**

The contract doc gains the API row, the fixture row, a "Stored settings" section before "The harness", and three decisions. `THEME.md` is new: it carries the inventory for stage 7.

````bash
python3 - <<'PY'
p = 'docs/CAT-CONTRACT.md'
s = open(p, encoding='utf-8').read()

# 1. The public surface: one more group.
anchor = '| Timelines | '
assert s.count(anchor) == 1
i = s.index(anchor); j = s.index('\n', i)
row = '\n| Stored settings | `FOLLOW`, `MOTION_STYLES`, `motionStyleOf`, `motionOverrideOf`, `collarOverrideOf`, `catIdOf`, `cleanPersonality`, `cleanCatSettings`, `defaultCatSettings`, `applyToAllCats`, `motionFor`, `collarFor`, `engineCfg` |'
s = s[:j] + row + s[j:]

# 2. The fixture table: one more row, after collar-cases.json.
anchor = '| `collar-cases.json` | `styles` (the frozen IDs)'
assert s.count(anchor) == 1
i = s.index(anchor); j = s.index('\n', i)
row = '\n| `settings-cases.json` | `ids`, `follow`, `motionStyles`, `collarStyles`, `defaults` (what a fresh install holds), `cases` (raw settings to clean ones: bad ones and a valid one), `personalities` (a stored personality, an object or JSON text, to a clean one), `applyAll` ("Apply to every cat"), `derived` (the engine\'s `cfg`, and the motion style and collar style each cat gets). See "Stored settings". |'
s = s[:j] + row + s[j:]

# 3. The new section, before "The harness".
anchor = '\n## The harness\n'
assert s.count(anchor) == 1
section = r'''
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
'''
s = s.replace(anchor, section + anchor)

# 4. Decisions to know about: three more.
s = s.rstrip('\n') + '''
- **A stored word that is not valid is the neutral one.** The global character, styles and collar fall back to the spec's defaults: Shrimpy, Playful and Off. A per-cat override that is not valid is `follow`, not a style: a typo never forces a style or a collar on one cat, or turns one off.
- **Custom is a word, and the traits are the truth.** The engine reads only the six traits. The preset name is a label that is kept only while it is honest (see Stored settings), so a hand-edited file can never show "Sweet" while the cat acts like Chill.
- **Fur lines are on only for a real `true`.** A settings file that holds `1` or `"true"` does not switch them on. It is the strict reading, the same on every platform.
'''
open(p, 'w', encoding='utf-8').write(s)
PY
cat > docs/THEME.md <<'EOF'
# Theme tokens

`shared/theme.json` holds the colours of NotchMeow's own drawing that no other contract file holds: the cat's details (pupil, mouth, tongue, teeth, the heart, star and sweat drop, the file sheet of the file catch), the launch greeting (badge, tint, halo, header text, card) and the palette of the fork's own pages (the prototype, the Windows/Linux `?dev` sheet, the Debug cat panel). `scripts/gen-theme.mjs` turns it into one file per platform, so each colour has one home.

**Only the character, branding and greeting colours are here.** Existing views keep their own colours (the island, Settings, chat, the pills and the upload view), even where they use the same hex value. Coat colours are in `tests/fixtures/cat/presets.json`; the state colours, the state glows and the greeting's streak palette are pinned by `tests/fixtures/cat/`, so the generator reads them from `design/prototype/cat-core.js` instead of copying them into `theme.json`. If `cat-core.js` changes one, regenerate the fixtures and then the theme files.

**The apps do not use these files yet.** The generator, `theme.json` and the three files were added by the settings and theme contract plan. Making the Mac and the Windows/Linux app read them, and removing the hard-coded copies listed below, is stage 7 of each app's plan. Stage 7 must change no pixel: every value below is the one that is hard-coded today.

## Run it

```
node scripts/gen-theme.mjs           # write the three files after editing shared/theme.json (or a state colour in cat-core.js)
node scripts/gen-theme.mjs --check   # write nothing; exit 1 and name the file if one is stale
bash scripts/test-theme.sh           # the generator's self-checks, then --check (CI runs this)
```

Node 22 or newer, no npm packages. Commit `theme.json` and the three generated files together; CI fails when they disagree.

| Platform | Generated file | Names |
|---|---|---|
| macOS | `NotchBuddy/Sources/App/Theme.generated.swift` | `Theme.Cat.pupil` (a `"#RRGGBB"` String), `Theme.Cat.pupilRGB` (`[Double]`); lists and maps: `Theme.Greeting.streaks`, `Theme.State.color["working"]`, `Theme.State.glowRGB["working"]` |
| Windows and Linux | `windows/src/theme.generated.ts` | `THEME.cat.pupil`, `THEME_RGB.cat.pupil`, `THEME.greeting.streaks[0]`, `THEME.state.color.working` (both are `as const`) |
| Windows and Linux | `windows/src/theme.generated.css` | `--nm-cat-pupil` and `--nm-cat-pupil-rgb` (`14, 11, 9`, for `rgba(var(--nm-cat-pupil-rgb), .5)`), `--nm-greeting-streak-1`, `--nm-state-color-working`, `--nm-state-glow-working` |

## The tokens

| Group | Token | Value | What it is |
|---|---|---|---|
| `brand` | `accent` | `#5EEAD4` | The accent of the fork's own pages |
| `brand` | `page`, `panel`, `line`, `ink`, `dim`, `button` | `#0F1012`, `#17181B`, `#2A2C31`, `#ECECEE`, `#9A9CA3`, `#202227` | The dark page, panel, border, text, dim text and button of those pages |
| `cat` | `pupil` | `#0E0B09` | The pupil |
| `cat` | `mouthInside`, `tongue`, `teeth` | `#3A1218`, `#E8798C`, `#FBF7F0` | The open mouth, the tongue, the small fangs |
| `cat` | `heart`, `star`, `sweat` | `#FF4D6D`, `#F7B32B`, `#7CC7FF` | The love heart, the happy star, the sweat drop |
| `cat` | `paper`, `paperFold`, `paperLabel` | `#F4F5F7`, `#C9CDD4`, `#3B9EFF` | The file the cat catches: sheet, folded corner, label |
| `greeting` | `badge`, `tint` | `#3BA0F5`, `#7FB4EA` | The greeting's badge, and the blue its cats end in |
| `greeting` | `haloGold`, `haloBlue` | `#E8C39A`, `#3B9EFF` | The halo's two ends (golden, then blue) |
| `greeting` | `headerDim`, `card` | `#8D9098`, `#141518` | The header's right-hand text, the Windows greeting's card |
| `greeting` | `streaks` | `#3B9EFF`, `#F29B38`, `#FF5A4E`, `#2EC4A0`, `#A78BFA` | The five colours the sixteen streaks cycle through. From `cat-core.js` |
| `state` | `color` | the 11 `COL` colours | The cat's state colour. From `cat-core.js` |
| `state` | `glow` | the 7 `GLOW` colours | The glow behind a working cat. From `cat-core.js` |

## Where each colour is hard-coded today

Line numbers are as of commit `947e2d3`. They move; find a colour by its value (`grep -rniE '#0E0B09' NotchBuddy/Sources windows/src design/prototype`). Stage 7 replaces each of these, and only these, with the token.

| Token | macOS (`NotchBuddy/Sources/App/`) | Windows and Linux (`windows/src/`) | Prototype (`design/prototype/`) |
|---|---|---|---|
| `brand.accent` | none | `cat/dev.ts:72, 93` | `notchmeow.html:15` |
| `brand.page` | `CatDevPanel.swift:330` (as 0.059, 0.063, 0.071) | `cat/dev.ts:80` | `notchmeow.html:15` |
| `brand.panel` | none | `cat/dev.ts:55` | `notchmeow.html:15` |
| `brand.line` | none | `cat/dev.ts:19, 55, 72, 93, 135` | `notchmeow.html:15, 497` |
| `brand.ink` | none | `cat/dev.ts:19, 72, 81, 131` | `notchmeow.html:15, 496` |
| `brand.dim` | none | `cat/dev.ts:56, 64, 85, 141, 159, 175` | `notchmeow.html:15, 499` |
| `brand.button` | none | `cat/dev.ts:19` | `notchmeow.html:26` |
| `cat.pupil` | `CatFace.swift:64` | `cat/renderer.ts:275` | `notchmeow.html:203` |
| `cat.mouthInside` | `CatFace.swift:170` | `cat/renderer.ts:403` | `notchmeow.html:260` |
| `cat.tongue` | `CatFace.swift:154` | `cat/renderer.ts:404, 411, 424` | `notchmeow.html:261, 263, 268` |
| `cat.teeth` | `CatFace.swift:178` | `cat/renderer.ts:406` | `notchmeow.html:262` |
| `cat.heart` | `CatFace.swift:116`, `CatEffects.swift:127` | `cat/renderer.ts:300, 377` | `notchmeow.html:218, 241` |
| `cat.star` | `CatFace.swift:120`, `CatEffects.swift:130` | `cat/renderer.ts:301, 378` | `notchmeow.html:219, 242` |
| `cat.sweat` | `CatEffects.swift:139` | `cat/renderer.ts:380` | `notchmeow.html:244` |
| `cat.paper` | `CatEffects.swift:158` | `cat/renderer.ts:443` | `notchmeow.html:398` |
| `cat.paperFold` | `CatEffects.swift:159` | `cat/renderer.ts:444` | `notchmeow.html:399` |
| `cat.paperLabel` | `CatEffects.swift:160` | `cat/renderer.ts:445` | `notchmeow.html:400` |
| `greeting.badge` | `CatGreetingRenderer.swift:41` | `cat/greeting.ts:186` | `notchmeow.html:476` |
| `greeting.tint` (127, 180, 234) | `CatGreetingRenderer.swift:41, 66` | `cat/greeting.ts:177, 187` | `notchmeow.html:476` |
| `greeting.haloGold`, `greeting.haloBlue` (the two ends of a `lerp`) | `CatGreetingRenderer.swift:16` | `cat/greeting.ts:291` | `notchmeow.html:471` |
| `greeting.headerDim` (141, 144, 152) | `CatGreetingRenderer.swift:32` | `cat/greeting.ts:303` | `notchmeow.html:458, 461, 463, 474` |
| `greeting.card` | none: the Mac draws no card | `cat/greeting.ts:272` | none |
| `greeting.streaks` | `CatGreeting.swift:94` | `cat/greeting.ts:74` | `cat-core.js:418` |
| `state.color` | `MotionProfiles.swift:10-11` | `cat/base.ts:54-56` | `cat-core.js:37` |
| `state.glow` | `MotionProfiles.swift:18`; the island's glow, `IslandRootView.swift:342-348` | `cat/base.ts:63-64`; the island's glow, `core/layout.ts:163-175` (every other line) | `cat-core.js:39` |

The two island glow rows are the cat's glow drawn by existing island code, with the same values as `GLOW`. Replacing the literals there with `state.glow` changes no pixel, but it is edited code of an existing view: stage 7 does it only with the owner's OK.

## Not tokens

- **The same hex value in an existing view.** `#F5A524`, `#F4505E`, `#34D399`, `#F7B32B`, `#C9CDD4` and others also appear in `IslandViewContent.swift`, `SettingsView.swift`, `windows/src/style.css` and the like. Those are upstream's UI colours and stay as they are.
- **Alpha-only black and white** (`rgba(0,0,0,.42)`, `rgba(255,255,255,.85)`, the collar's edge and highlight) and colours computed from a coat or an agent.
- **Coat colours.** They are in `presets.json`, pinned by the contract.
- **The agent colours** of the collar. They come from the pill catalog (`PillCatalog.swift` on the Mac).
- **Icons.** Their palette is chosen separately.
EOF
git diff --stat -- docs/CAT-CONTRACT.md
grep -c "" docs/THEME.md
````

Expected: `1 file changed, 55 insertions(+)` for `docs/CAT-CONTRACT.md`, and `82` for the line count of `docs/THEME.md`.

- [ ] **Step 4: The final checks**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 138`, `# pass 138`, `# fail 0`, nine `✓` fixture lines, `✓ 9 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`.

Run: `bash scripts/test-theme.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 8`, `# pass 8`, `# fail 0`, `✓ 3 theme files match shared/theme.json`.

Run: `node scripts/check-fixtures-additive.mjs 947e2d3 | tail -2`
Expected: `  + settings-cases.json is new` and `✓ fixtures changed only by addition since 947e2d3`.

The apps still pass their own fixture tests (the new file changes none of them):

Run: `cd windows && node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/*.test.mjs 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `ℹ tests 89`, `ℹ pass 89`, `ℹ fail 0`.

Run: `bash scripts/test-cat-personality.sh 2>&1 | tail -1 && bash scripts/test-cat-presets.sh 2>&1 | tail -1`
Expected: `All tests passed.` twice.

Run: `git status --short`
Expected: ` M .github/workflows/build.yml`, ` M ARCHITECT.md`, ` M CLAUDE.md`, ` M docs/CAT-CONTRACT.md`, `?? docs/THEME.md`, `?? scripts/test-theme.sh` (and the dry-run `windows/node_modules` link). Nothing under `NotchBuddy/` or `windows/` is modified, and `git log --oneline 947e2d3..HEAD` lists the three commits of Tasks 1 to 3.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-theme.sh docs/THEME.md .github/workflows/build.yml docs/CAT-CONTRACT.md CLAUDE.md ARCHITECT.md
git commit -m "docs(theme): the settings contract and the theme tokens are documented, and CI checks the generated files

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer changes `cat-core.js` and the fixture once, and the app plans pick it up.

1. **The name.** `docs/CAT-CONTRACT.md` and `cat-core.js` already call the greeting's last beat "A-0c", so this plan was renamed **A-0d** (file, branch and labels) before it was handed over.
2. **An invalid per-cat override is `follow`,** not a fallback style: a typo in `cat.motion.momo` or `cat.collar.momo` never forces a style or turns a collar off. The *global* collar and style fall back to Off and Playful, as the spec says. OK?
3. **A preset name is trusted only while the traits match it.** `{"preset":"sweet"}` with Chill's numbers becomes Custom, and a name alone (`{"preset":"chill"}`) is Custom with six 0.5s, because a missing trait is 0.5 (the existing rule), not the preset's value. The alternative is to fill the missing traits from the named preset. Which do you want? (Assumed: the first. Nothing the apps write has a name alone.)
4. **Fur lines are on only for a real boolean `true`.** `1` and `"true"` are off. The alternative is to accept `1`. (Assumed: strict. It is the only rule every platform reads the same.)
5. **The state colours, glows and streak palette are not in `theme.json`.** The fixtures pin them, so `cat-core.js` stays their one home and the generator reads them from it. The parent spec listed "state colours" under `theme.json`; radii and the type scale are left out because sub-project A's spec says colours only. OK?
6. **"Branding" is the palette of the fork's own pages** (the prototype, the Windows/Linux `?dev` sheet, the Debug cat panel): accent `#5EEAD4` and six surface colours. There is no app brand palette yet and the icon palette is deliberately left out. When the brand colours are chosen, they go in the `brand` group.
7. **The prototype keeps its hard-coded colours.** The spec names three outputs; a fourth, `theme.generated.js`, would let the prototype page read the tokens. (Assumed: no. The one-off inventory check keeps the prototype and `theme.json` equal today.)
8. **The Mac target compiles `Theme.generated.swift` now** (an unused `enum Theme`, plus six lines of regenerated `project.pbxproj`). The alternative is to add the file at stage 7. (Assumed: now, so stage 7 is only "use it". The Debug build is proved in Task 3.)
9. **The island's glow** (`IslandRootView.swift:342-348`, `core/layout.ts:163-175`) is existing view code that draws the same seven `GLOW` colours. May stage 7 swap those literals for `Theme.State.glow` / `THEME.state.glow`? Same values, no change of look. (Assumed: yes, with your OK in the stage 7 plan.)
10. **"Apply to every cat" copies what is stored,** not what is in force: a cat that follows the global style keeps following it, and every cat gets its own copy of the personality. The other reading would bake today's global style and collar into all 16 cats, so a later change of the global style would stop doing anything. (Assumed: the first. The two readings differ, which is why the function is in the contract.)
11. **Four helpers beyond the brief:** `defaultCatSettings`, `motionFor`, `collarFor` and `engineCfg`. They are small, and they stop the two apps resolving "follow" differently. Drop them if you prefer the apps to carry that logic.

## Self-review notes

- **Spec coverage.** §4 rows: character (Task 1 "the character"), motion style and per-cat override ("the global motion style…", "a cat's own motion…"), personality and Custom (the five `personality:` tests and 47 fixture rows), collar and per-cat collar, fur lines, apply to every cat (`applyToAllCats`, 5 fixture rows); persistence keys (interface table); frozen IDs (Global Constraints, Task 1 tests). §5 theme tokens: `theme.json`, the generator, the three outputs, `--check`, CI (Task 3, Task 4). Checks: contract in CI plus fixtures (Task 2, Task 4). Icons: left out entirely.
- **Placeholders.** None: every code step carries its full content, generated into this plan from the files the dry run ran.
- **Type consistency.** The function names in the interface table are the ones in Task 1's code, the tests, the fixture builder and the docs; the token names in the interface table are the ones in `theme.json`, the generated files and the inventory.
- **Review Focus** lines 1 to 5 each have a named test above.
- **What this plan deliberately does not do:** make either app use the settings functions or the theme files; add the Settings rows; icons; the `theme.generated.js` for the prototype.

## Dry run (2026-10-07)

Run before the plan was handed over, in throwaway clones made with `git clone --local --shared` of the repository, on branch `notchmeow/rebrand` at `947e2d3`, with `windows/node_modules` linked to the main checkout's (nothing was installed or downloaded). Four clones were used: the first to write and test the code and the docs, the second to rehearse the plan task by task as it was first built, the third to run the final text from the first line to the last. Each task was applied **exactly as written** by a small script that executes the plan's `bash` blocks and `Run:` lines in order (the plan text is generated from the files the first clone ran, and the third clone's results are byte-identical to the first's: `cmp` on the 18 files the plan creates or changes). Every `Run:` line printed what its `Expected:` line says. One last edit followed (a legacy cat name was removed from a list of bad IDs in a test, because new code carries no such name), so Tasks 1 and 2 were run once more in a fourth clone; Tasks 3 and 4 do not touch that file. The clones were then moved to the Trash, and nothing was committed or pushed in them or in the main checkout.

| Task | Result |
|---|---|
| Baseline, before any change | `bash scripts/test-cat-contract.sh`: `# tests 116`, `# pass 116`, 8 fixtures, determinism check passes |
| 1 | `settings.test.mjs` fails 19 of 19 without the section and passes 19 of 19 with it; with `furLines` weakened to `!!r.furLines`, test 7 fails (`# pass 18`, `# fail 1`); the whole contract: `# tests 135`, `# pass 135` |
| 2 | `settings-cases.json` is 163,289 bytes (37 cases, 47 personalities, 5 apply-to-all, 3 derived); the contract: `# tests 138`, `# pass 138`, 9 fixtures; `check-fixtures-additive.mjs 947e2d3`: the eight old files keep 187, 180, 713, 62, 42, 36, 231 and 121 lines, and `✓ fixtures changed only by addition`; `git diff --stat -- tests/fixtures/cat` prints nothing; with the core weakened, `--check` prints `✗ settings-cases.json drifted from cat-core.js (2 differences)` |
| 3 | Theme tests `# pass 8`; `--check` exits 0, and exits 1 naming all three files after `theme.json` is edited; `swiftc -swift-version 6 -strict-concurrency=complete -typecheck` exits 0; `tsc --noEmit` exits 0; `xcodegen` changes `project.pbxproj` by 6 lines; **the Debug build ends `** BUILD SUCCEEDED **`** (the generated file is compiled into the target, with no warning); the inventory script: `✓ all 175 sites hold the colour of their token` (and exits 1 when a line number is moved by one: tried in the first clone) |
| 4 | `bash scripts/test-theme.sh`: `# tests 8`, `# pass 8`; the diffs: `build.yml` +3, `CLAUDE.md` +2, `ARCHITECT.md` 1 line, `CAT-CONTRACT.md` +55, `THEME.md` 82 lines; the apps still pass: Windows `scripts/cat-tests` `ℹ tests 89`, `ℹ pass 89`; Mac `test-cat-personality.sh` and `test-cat-presets.sh` print `All tests passed.` |

**What the dry run changed in the plan:**
- **The Xcode project is tracked.** `NotchBuddy.xcodeproj/project.pbxproj` is in git, so a new Swift file needs `xcodegen` and a committed `project.pbxproj` (six lines). Task 3 now does that and builds the Debug app to prove the generated file compiles in the target. The first draft had only a `swiftc` typecheck.
- **`greeting.streaks` is the five-colour palette.** `cat-core.js`'s `STREAKS` is sixteen streaks that cycle through five colours; the first draft of the generator listed sixteen colours.
- **The state maps in CSS are `--nm-state-color-<state>` and `--nm-state-glow-<state>`** (the generic `<group>-<key>-<name>` rule), not `--nm-state-<state>`. The tests say so.
- **Two mistakes in the first self-checks** were found by running them: an assertion on `'constructor' in Object.keys(...)` (true for any array), and a "different personality" example that was 1e-10 away, inside the 1e-9 tolerance. Both are fixed; the fixture uses 1e-12 (kept) and 1e-6 (changed).
- **A fresh worktree has no `windows/node_modules`.** Task 3 links the main checkout's before `tsc` (never installs).
- **The inventory check** first counted 229 "sites" because of a leftover no-op loop; the real number is 175.

**Not run, by rule:** the commit steps (nothing may be committed in a clone), so `git log --oneline 947e2d3..HEAD` in Task 4 Step 4 was not run. `npm run check:cat` was not used; its command was run directly (`node --experimental-strip-types --test … scripts/cat-tests/*.test.mjs`). The CI step was not run on GitHub; its YAML diff is three lines in the same shape as its neighbours.

## The owner's answers (2026-10-07)

- **Plan:** approved, run in a worktree session on Sonnet 5.5, effort medium, as "Execution" says.
- **Question 1, the name:** renamed A-0d before hand-over.
- **Questions 2 to 11:** approved as assumed (an invalid per-cat override is `follow`; a preset name is kept only while the traits match; fur lines only for a real `true`; state colours, glows and streaks stay in `cat-core.js`; "branding" is the fork's own pages; no `theme.generated.js`; `Theme.generated.swift` compiled now; "apply to every cat" copies what is stored; the four helpers stay). Question 9, the island glow, is asked again in the stage 7 plans.
