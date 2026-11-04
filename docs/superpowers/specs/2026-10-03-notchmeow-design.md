# Plan: NotchMeow, a fork of `louis-cfm/coucou` starring Shrimpy & Momo

## Context
The user wants to fork Coucou, a notch "buddy" that watches AI coding agents (Claude Code, Codex, Gemini CLI…), and replace its character, Mochi, with animated cat heads modelled on their own cats:
- **Shrimpy** (he): long-haired brown tabby.
- **Momo** (she): gray-and-white tuxedo (bicolor).

The fork also gets its own name, theme, icons and sounds, and keeps Coucou's animation style.

**Upstream license.**
- `LICENSE-ASSETS.md` reserves the names "Coucou" and "Mochi", Mochi's "design, look, expressions and animations", the icons, the 28 sounds, and the `design/` and `docs/media/` images.
- Forks are welcome only with their own name, icon, character and sounds.
- The code is MIT: keep upstream's copyright line and add ours.

**Goal ladder:** personal use → portfolio → public release. **Platforms:** macOS (Swift, `NotchBuddy/`) and Windows/Linux (Tauri, `windows/`).

**Toolchain (verified installed):**
- Xcode 27.0 (matches `project.yml` `xcodeVersion: "27.0"`) and XcodeGen;
- Node 22, Rust 1.98, gh, python3;
- GitHub user `AIKUSAN`.

## Decisions (agreed with the user)
| Topic | Decision |
|---|---|
| Name | **NotchMeow**; repo `AIKUSAN/notchmeow` (a public GitHub fork showing "forked from louis-cfm/coucou") |
| IDs | Bundle `io.github.aikusan.notchmeow`, App Store variant `io.github.aikusan.notchmeow.store`. Short, so the App Store socket path stays ≤ 103 bytes |
| Cast | One `CatRenderer` with two presets, **Shrimpy** and **Momo**, drawn from the photos; **kittens** derived from them |
| Look | From photos. Detailed (look B style) at large sizes; automatically simplified (look A style: ink pill eyes, no stripes or irises) below Ø28 pt, for the compact notch and mini pills |
| Motion | Two profiles: **Playful cat** (prototype motion 1) and **Classic** (prototype motion 2). A global Settings toggle plus a per-cat override |
| Display modes | (1) one cat per agent; (2) a single chosen cat; (3) both cats together. Picked in Settings |
| Subagents | `SubagentStart` / `SubagentStop` hooks spawn and dismiss kittens next to the parent cat |
| File drop | The cat catches the file in its mouth: wide open mouth, then gulp and chew, reusing upstream's mouth spring and gulp. The Mochi → mailbox body morph is dropped (the morph breaks with ears) |
| Sounds | **One mixed set of cute cat sounds** (decided 2026-10-03), chosen slot by slot rather than set against set:<br>• **Character moments:** real CC0 cat vocals (chirps, trills, mews, purrs, a soft hiss).<br>• **Interface ticks:** cat-themed foley made in code (paw taps, a tiny bell, kibble). Never a meow on hover.<br>• **Gaps with no good recording** (yawn, kneading, collar-tag clink): made in code.<br><br>**NotchMeow layering, two tiers:**<br>• Every cat vocal carries a subtle made-in-code *touch*: short (≤120 ms), quiet (about 18 dB under the vocal), and coloured by mood: bright for happy, rising for attention, soft and falling for errors.<br>• The fuller *signature*, a rising sparkle of about 0.2 s, plays on the key moments: greet, finish, approval, question, error and love.<br><br>**Later:** recordings of the real Shrimpy and Momo replace the CC0 vocals slot by slot, giving each cat its own voice, which helps in "one cat per agent" mode. Until then, a small per-cat pitch offset does the same job. Switchable sound packs wait until those recordings exist.<br><br>**Licences:** every CC0 clip's licence is verified on its own page and recorded with its source in a credits file. Candidates: `design/sounds/cc0-candidates.md`; audition page: `design/sounds/listen.html`.<br><br>Upstream WAVs are removed in step 1, so the app is silent until then (the engine already skips missing files). |

## Sub-projects (each gets its own approve-then-build cycle)
- **A. Fork, rebrand and the cat character** (this plan, detailed below).
- **B.** Display modes (1)–(3) and subagent kittens, plus coloured eyes for small cats. Spec: [`2026-10-08-display-modes-kittens-design.md`](2026-10-08-display-modes-kittens-design.md).
- **C.** Sounds: the mixed CC0 + made-in-code set with NotchMeow layering (see the Sounds row above). Later, real recordings of Shrimpy and Momo.
- **D.** Public release: Developer ID signing and notarization, Windows signing, docs site. Stage 1 (tester builds 0.9.x on all three platforms and the site, no signing yet) spec: [`2026-10-08-release-prep-design.md`](2026-10-08-release-prep-design.md). Stage 2 (signing and the public 1.0.0) gets its own design.
- **E.** Local models everywhere. Find the local model servers already running, use Apple's on-device model, and bring Windows/Linux chat up to the Mac's providers. Later, an optional one-click model download. Spec: [`2026-10-03-local-models-design.md`](2026-10-03-local-models-design.md).
- **F. Smart cats**, a modern Clippy with Shrimpy and Momo as the mascots, in three stages:
  - **F1. Agent sidekick:**
    - "while you were away" recaps;
    - plain-English explanations of permission requests, with risky commands flagged;
    - nudges when an agent is stuck;
    - answers to "what's Claude doing?";
    - drop a file on a cat to hand it to that cat's agent.
  - **F2. Desktop helper:** press a hotkey to explain selected text or a screenshot.
  - **F3. Companion:** memory you can see and edit, and personality that grows over time.
- **G.** File shelf and transfer. Park files in the notch, send them to other devices AirDrop-style, and move files between your own machines running NotchMeow. Spec: [`2026-10-04-file-shelf-transfer-design.md`](2026-10-04-file-shelf-transfer-design.md).
- **H. Desktop cat** (added 2026-10-04, inspired by upstream Coucou 0.1.6). Spec: [`2026-10-08-desktop-cat-design.md`](2026-10-08-desktop-cat-design.md). Drag a cat out of the notch onto the desktop:
  - It watches the cursor, dances to music and sleeps when idle.
  - It flies back to the notch with an approval or a question, then returns to its spot.
  - Its position is remembered.

  It comes after A and B, because B decides which cat leaves the notch. Its upstream 60 Hz timer must be throttled to keep 0 % CPU when hidden.
- **I. Wardrobe for the cats** (added 2026-10-04, inspired by upstream Coucou 0.1.5). The cats get outfits and an Auto mode that dresses them for the seasons:
  - Outfits are redrawn around the ears and each coat's head shape, because upstream's outfits are shaped for its own character.
  - The seasonal logic, persistence and grid UI port from upstream.

  It comes after A, and ideally after B. It needs its own design pass with the owner.
- **Upstream ports** (owner-approved 2026-10-04). Each one is ported by hand, never as a `git merge upstream/main`, because a merge would bring back Coucou's identity and reserved assets:
  - **Keyboard shortcuts** (upstream 0.1.7, #205), after E1 merges. The desktop and wardrobe actions arrive with H and I.
  - **Windows Gemini CLI and Antigravity hooks** (upstream branch `n22-gemini`), after `e1/tauri` merges, with the identifiers renamed to NotchMeow's.
  - **`release.sh` Info.plist version check** (#199, #201).
  - **Launch greeting:** the owner compares the current greeting with a cat version of upstream's Greeting v2 in the prototype, then picks one before A-0. Upstream's greeting sound is a reserved asset and is not used.

Research behind E and F, done 2026-10-03, covered Clippy, proactive assistants and local runtimes. Its lessons drive F: speak only at task boundaries, remember every dismissal, look at the work rather than stare at the user, and never cover the user's work.

A ships display mode (2), a single chosen cat, with a "Character: Shrimpy / Momo" setting.

## Sub-project A, steps

### 1. Fork, folder and identity
- **Repo and folder.**
  - `gh repo fork louis-cfm/coucou --fork-name notchmeow --clone=false`.
  - Clone into `…/notchmeow` and switch this session there (`ccd_directory` change_directory).
  - The empty `untitled folder` is left for the user to delete.
- **Design spec.** Copy this plan to `docs/superpowers/specs/2026-10-03-notchmeow-design.md` and commit it.
- **Rename identity and contract values together, in one commit, before the first run.** This stops collisions with an installed Coucou and silent hook failures.

  | Area | Files | Rename |
  |---|---|---|
  | Bundle IDs, team, product names | `NotchBuddy/project.yml` | Keep the `NotchBuddy/` folder and target name: generic, and referenced by CI and scripts |
  | Keychain service | `ClaudeService.swift:7` | → bundle ID |
  | Keyring service | `windows/src-tauri/src/secrets.rs:6` | → bundle ID |
  | Support folder, socket, relay script | `HookServer.swift:15-30`, embedded Python `:1942`, `:2210` | `Application Support/NotchMeow`, `nm.sock`, `nm-hook` |
  | Hook-entry markers | `HookServer.swift`; `windows/src-tauri/src/hooks.rs:37` | `"NotchBuddy"` / `"coucou"` / `"nb-hook"` / `"coucou-hook"` → `"NotchMeow"` / `"nm-hook"` / `"notchmeow-hook"` |
  | Antigravity root key | `HookServer.swift` | → `notchmeow` |
  | Payload fields | everywhere, incl. `docs/AGENTS.md` | `coucou_kind` / `coucou_agent` → `nm_kind` / `nm_agent` |
  | Pipe and socket pairs (both ends) | `pipe.rs:66` ↔ `hook/src/win.rs:32`; `platform/linux.rs:119` ↔ `hook/src/unix.rs:26` | `notchmeow-<sid>`, `notchmeow.sock` |
  | Relay crate and binary | `windows/hook/Cargo.toml`; `package.json`; `tauri.conf.json` | → `notchmeow-hook` |
  | Tauri identifier and product name | `tauri.conf.json`, `tauri.linux.conf.json` | → NotchMeow |
  | Data and log folders, uninstaller paths | `platform/*.rs`, `log.rs`, `nsis/hooks.nsh` | → NotchMeow |
  | Linux env var | `platform/linux.rs` | `COUCOU_LAYER_SHELL` → `NOTCHMEOW_LAYER_SHELL` |
  | App logs and preference keys | `AppLog.swift:21`; `coucouHooksInstalled`, `coucou.musicAutomationGranted` | → NotchMeow |
  | Release and CI names | `scripts/release.sh`, `.github/workflows/*` | → NotchMeow |

- **Text and content.**
  - User-visible strings "Coucou" → "NotchMeow".
  - Chat persona "You are Mochi" (`ClaudeService.swift:201`, `claude.rs:25`) → the active cat's name.
  - Remove the upstream author's personal data: project colours `IslandTypes.swift:194-205` and `core/layout.ts:193-204`, the n8n URL in `docs/INTEGRATIONS.md`.
  - Team ID `256AUJ9555`: left blank (Debug builds unsigned) until sub-project D.
- **Rights-reserved assets.**
  - `git rm` the upstream sounds, `docs/media/*`, `design/captures/*`, `design/prototype/notch-buddy.html`, `design/animations/*` and `windows/screenshots/*`.
  - Rewrite README, `LICENSE-ASSETS.md` (NotchMeow's own assets) and `CLAUDE.md` (new identity; the "keep bundle ID" rule now points at ours).
  - Keep the MIT LICENSE, adding a NotchMeow copyright line.
- **Check:** `rg -n "louisraille|coucou|Coucou|Mochi|nb-hook|nb\.sock"` returns only the LICENSE attribution and CHANGELOG history.

### 2. Character design from the photos (design gate)
The user drops 2–4 photos of each cat into chat.
- **Extract per cat:**
  - palette as hex (fur light and shadow, inner ear, nose, iris, muzzle);
  - markings map (Momo: charcoal cap, mask and blaze on a gray-and-white bicolor; Shrimpy: brown tabby markings and a long-hair ruff);
  - ear shape and tufts;
  - head proportions.
- **Wireframe board:** construction lines on an inline widget (head superellipse, ears, eye line, nose and muzzle anchors). Shrimpy's fluffy outline comes from a smooth-noise perturbation of the superellipse radius.
- **Prototype:** `design/prototype/notchmeow.html`, the new visual source of truth. It extends the approved four-cat prototype with:
  - the presets, both motion profiles, and a size ladder (Ø20 compact, Ø44–66 expanded, 12–24 px minis, kittens);
  - the greeting and file-catch sequences.
- **Gate:** the user approves the look and motion. Then invoke `superpowers:writing-plans` for the detailed implementation plan of steps 3–6.

#### Approved character design (2026-10-03)
Approved on the reference board, then animated in `design/prototype/notchmeow.html`. The prototype's `PRESETS` block holds the exact values, in units of R (the head radius). The reference photos stay out of the repository.

**Finish:** plain (flat colour, no fur strands) is the default. Fur lines stay available as an optional setting.

| | Momo (she) | Shrimpy (he) |
|---|---|---|
| Breed and coat | Domestic shorthair, gray-and-white bicolor in the tuxedo distribution. An even charcoal coat, no tabby striping | Domestic longhair brown tabby with Maine Coon-like traits |
| Head | Superellipse rx 1.12, ry 0.90, n 2.2, smooth outline | rx 1.16, ry 0.92, n 2.2 with a slightly fluffy edge, inside a ruff (rx 1.3, ry 0.97, set 0.2 lower) whose top stays at head level |
| Ears | Medium-large, wide bases, set wide and tilted outward (h 0.8, base 0.56, tilt 0.5 rad) | Small, wide-set, tilted outward, with tan tufts inside and tufted tips (h 0.8, base 0.4, tilt 0.44 rad) |
| Markings | Charcoal cap and mask ending just below the eyes. A narrow blaze starts at the crown and widens into the white muzzle. White chin and chest | Dark crown band running into the tabby "M", mascara lines, cheek bars, two peach whisker pads and a cream-tan chin. White only on the neck bib |
| Eyes | Round. Olive-green #7E8A45 near the pupil turning yellow-gold #D1B85F, with a yellow lid ring #D9BE62 | Open almond, no heavy lid. Green-gold #C9D18A to #6F8445 inside a tan rim #D9B68A |
| Nose | Large bubblegum pink #E89AA6, set low | Brick-rose #C07A62 |
| Coat colours | Coat #3D3D41 with a 22 % white rim light so it reads on the black notch. White #F6F4F1, inner ear #B98288 | Coat #A08A70 to #6E5B49, ruff #B49C7A / #7E6750, stripes #2E241D, inner ear #DCC39A, bib #F3EEE6 |
| Whiskers | White, rooted on a 3×2 dot grid beside and under the nose, plus 2 eyebrow whiskers | White, rooted on a 3×3 spotted pad grid, plus 3 eyebrow whiskers |
| Expression ink | Pale gold #E4D592, which reads on the dark mask | Dark brown #231A14 |
| Paws (wave) | White with pink toe beans | Tan #B89C78 with dark beans |

**Rules the engine ports carry over:**
- **Detail levels:**
  - Ø28 and up (head width): the full cat, with irises, all markings and whiskers.
  - Below Ø28: the compact cat. Ink eyes; no irises, "M" stripes, cheek bars or whiskers. Momo's white map and Shrimpy's crown band, pads and chin stay.
- **Face warp:**
  - Markings, pads and whisker roots are drawn on the flat front view, then warped onto the head sphere by yaw and pitch. They turn with the eyes, and the warp is the identity at rest.
  - The warp is a true rotation of the head ellipsoid, not a stretch of the flat drawing:
    - Turn: up to 82 % of upstream's 0.62 rad gaze yaw. Looking up takes 60 % of its 0.5 rad pitch; looking down takes only 32 %, so the chin never folds into the jaw line.
    - The muzzle stands proud of the sphere (depth +0.12), and the nose by another 0.05 R, so they swing a little further than the cheeks.
    - The head outline leans into the turn (0.1 rx at mid-height, top and bottom anchored), and the head shifts 0.08 R toward the cursor. The ears ride the outline; the ruff stays with the body.
    - The near eye never foreshortens below 55 % of its width.
    - Marking outlines (Momo's white map, the tabby stripes) are densely sampled before warping, so their edges curve with the head instead of cutting across it.
    - The pupils travel up to 0.24 of the eye width for the rest of the gaze.
    - Cursor response builds over 240 px horizontally and 180 px vertically (tanh).
  - Blinks bring the upper lid down rather than squashing the eye from both sides.
  - The face fades out as a roll carries it over the top of the head.
- **Kittens (`kittenOf`):** the parent's coat with:
  - a rounder head (n 2.05);
  - ears ×1.12;
  - round eyes, ×1.2 wide and ×1.32 tall;
  - the nose 0.08 rad higher;
  - whiskers ×0.7 and one eyebrow whisker;
  - the ruff ×0.93.
- **Badge:** beside the right ear, 1.4 R right and 0.92 R up. In the compact notch it moves to the left so it never sits under the camera housing.
- **Mouth:** the upstream slot spring (ω₀ = 2π/0.25, ζ = 0.6) drives an open mouth for yawns and the file catch. The catch sequence:
  1. open wide while a file hovers;
  2. snap wider on the drop while the file flies in;
  3. gulp with a squash;
  4. chew for 0.85 s with happy eyes.
- **Greeting:** the upstream greeting timeline, in the same 640×150 space, with paws for hands. The right paw waves with its toe beans out.
- **Motion:** Playful and Classic, as in the four-cat prototype, selectable globally with a per-cat override.
- **Mouth on every state and emote (both styles):**
  - Six animatable values: open, smile (−1 frown to 1 smile), tongue, round (wide D to "o"), skew, wavy. An open mouth hangs under the ω upper lip, so even a small opening still reads as a cat mouth. As it rounds into an "o", the lip lifts into the top of the ring. Each state has a rest mouth (`MOUTH` table in the prototype); emotes hold a pose, then ease back.
  - Per-frame motion on top:

    | State | Mouth |
    |---|---|
    | idle | soft closed mouth; Playful adds the odd blep or lip lick |
    | working | tongue tip out in concentration |
    | thinking | mouth pushed to one side |
    | searching | hunting chatter: bursts of 1.1 s every 2.6 s. The jaw eases open under the ω upper lip, trembles at 9 Hz and eases shut |
    | approval | a meow every 1.4 s, in step with the hop |
    | question | small "mrr?" |
    | error | frown; Playful opens with a hiss |
    | finished | cat smile |
    | ratelimit | panting with the tongue out |
    | sleeping | slightly open mouth with the breath |
    | dizzy | wavy mouth, tongue lolling out |

  - Emotes:

    | Emote | Mouth |
    |---|---|
    | love | closed smile while purring |
    | happy | open happy mouth |
    | surprised | "O" |
    | proud | smug smile |
    | wink | blep |
    | yawn | tongue curled |
    | annoyed | "hmph", pushed to one side |
    | hello | "mrrp!" |
    | file catch | ends with a lip lick |
- **Hairball** (new emote, 2.4 s): ears back, three heaves, then a hairball comes up. It bounces once, rolls away and fades; a lick of relief follows. It also plays:
  - in Playful, after the hiss when an agent errors;
  - when a dropped file can't be read (apps, archives, disk images, videos, or over 25 MB). The cat catches the file, gags and coughs it back up wrapped in fur.
- **Zoomies** (new emote, 2 s): a pre-pounce wiggle, then side-to-side dashes with skids, dust puffs, speed lines and afterimages. Pupils go wide, ears go back and the tongue flaps; it ends in a happy flop. Playful also triggers it:
  - when the cat wakes from sleeping;
  - when an agent finishes after a long stretch of work. That's 5 min of working, thinking or searching in the app (12 s in the prototype); approval and question pauses don't reset the clock.

#### Personality (mix and match)
Personality is a separate setting from the coat and from the motion style, so any cat can wear any personality. Each cat has six traits from 0 to 1; 0.5 is neutral, so the default **Balanced** preset reproduces the approved motion exactly (and Classic stays 1:1 with upstream). Kittens inherit their parent's personality.

| Trait | Low end, high end | What it bends |
|---|---|---|
| Energy | sleepy, bouncy | Animation speed (×0.55 to ×1.5); hop and bounce height. Below 0.5, resting lids droop. Pupil size; blink rate; idle yawns when below 0.3 |
| Curiosity | aloof, nosy | How far it turns toward the cursor (×0.35 to ×1.2); how often its ears flick |
| Chattiness | quiet, talkative | Strength of meows, chatter, panting and snoring (×0.3 to ×1.4); idle "mew"s above 0.7 |
| Affection | independent, cuddly | Resting smile; resting blush above 0.6; slow-blink frequency; idle purrs above 0.75. Pokes get a "love" reaction instead of "annoyed" when affection is above 0.75 and sass below 0.4 |
| Sass | easy-going, grumpy | Resting frown and "hmph" skew; heavy lids and ears slightly back above 0.55; idle "hmph"s; a hiss on pokes above 0.7 |
| Mischief | well-behaved, troublemaker | Idle winks with a blep; random idle zoomies when mischief is above 0.75 and energy above 0.7 |

Presets:

| Preset | Energy | Curiosity | Chattiness | Affection | Sass | Mischief |
|---|---|---|---|---|---|---|
| Balanced (default) | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 |
| Chill | 0.12 | 0.35 | 0.3 | 0.65 | 0.3 | 0.2 |
| Grumpy | 0.4 | 0.3 | 0.45 | 0.15 | 0.95 | 0.3 |
| Sweet | 0.5 | 0.55 | 0.55 | 1 | 0.1 | 0.3 |
| Hyper | 1 | 0.9 | 0.75 | 0.5 | 0.3 | 1 |
| Chatty | 0.6 | 0.7 | 1 | 0.6 | 0.35 | 0.5 |

Moving any slider turns the cat's preset into **Custom**. Settings shows, per cat: Character, Motion style, Personality preset and the six trait sliders, plus an "Apply to every cat" action. All of it is persisted with the other settings.

#### More cats
**Shrimpy and Momo are the defaults everywhere:** the Character setting (Shrimpy first), the "both together" mode, and the order cats are handed out in "one cat per agent" mode. Fourteen extra coats are optional picks in Settings, built on a shorthair template (`makeCat`); a coat is only used once the user picks it. Each is only a preset; the renderer gained these coat types and options:
- `solid`, with an optional lighter muzzle;
- `point`: an elliptical mask centred on the nose;
- `calico`: wobbly patches warped with the face;
- per-ear colours and per-eye irises;
- `hairless`: no fur strands, even with fur lines on;
- `wrinkles`: three faint forehead wrinkles in a darker skin tone, full detail only;
- `ear.fold`: a short rounded cap whose tip folds forward and down over the head, with a soft crease and the inner ear mostly hidden. The flap is drawn in a second pass over the head, and kittens keep it.

| Name | Coat | Look |
|---|---|---|
| Ginger | orange tabby | tabby markings in orange, cream muzzle, amber almond eyes |
| Midnight | black shorthair | rim light, copper-gold round eyes, pale expression ink |
| Latte | Siamese seal point | cream coat, seal mask and ears, blue almond eyes, wedge-ish head (n 2.0) |
| Patches | calico | white with orange and black patches, one orange and one black ear, green eyes |
| Blue | British shorthair | chubby round head (n 2.5), small rounded ears, plush muzzle, copper eyes |
| Snow | white longhair | soft ruff and ear tufts, odd eyes (blue and gold) |
| Oreo | black-and-white tuxedo | jet black (not Momo's charcoal) with a white blaze, muzzle and paws, rim light, yellow-green eyes, pink nose |
| Mocha | tortoiseshell | dark brown-black mottled with small orange and cream patches, one orange ear, amber eyes |
| Silver | silver tabby | pale silver with crisp near-black stripes, white chin, green eyes, brick-pink nose |
| Cloud | Ragdoll | longhair with a cream ruff and white bib, blue-grey point and ears, white muzzle, big round deep-blue eyes |
| Leo | Bengal | gold with two-tone rosettes, forehead streaks and cheek "mascara" lines, cream muzzle, green-gold almond eyes |
| Button | Scottish Fold | solid lilac-grey, very round head (n 2.5), small ears folded forward and down, big round copper eyes |
| Puff | Persian | flat face with the nose set high, very round wide head (n 2.6), big cream ruff and white bib, tiny tufted ears, big round copper eyes |
| Noodle | Sphynx | hairless peach skin with forehead wrinkles, big bat ears, wedge-ish head (n 2.0), lemon-yellow almond eyes, sparse short whiskers |

> **Updated 2026-10-04:** steps 3–5 are now built from `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`. That spec puts a shared cat contract (A-0) first, then builds the TypeScript and Swift engines in parallel. It also adds the agent collar, the searching and sleeping triggers, and the Cat settings section. The steps below are the original outline.

### 3. TypeScript engine refactor (Windows/Linux first: fastest iteration in the browser)
- **Rename `windows/src/mochi/` to `windows/src/cat/` and split it:**
  - `engine.ts` keeps today's public API, so `island/*`, `views/*`, `hooks.ts` and the Rust side are unchanged. API: `setState`, `triggerEmote`, `slap`, `blink`, `gulp`, `update`, `draw`, `busy`, `isMini`, `bodyColor`, `lookX/Y`, `tgEs`, `slotH*`, `onDizzy`, `hexToRGB`, `EyeShape`.
  - `renderer.ts`: head, ears, eyes (ink set plus almond with dilating pupils), nose, mouth, whiskers, fur, and the size-based detail level.
  - `presets.ts`: Shrimpy, Momo, kitten derivation.
  - `motion/playful.ts`, `motion/classic.ts`, implementing `MotionProfile { enter(state, prev), loop(T, targets), emote(name), ambient(t) }`.
- **Reuse unchanged:** `core/anim.ts` (Ease, Spring), the tween and lock mechanism, smoothing, blink scheduler, particles, badge, squash, slap → dizzy, the mouth spring.
- **Engine additions:**
  - new animatable properties `earL`, `earR`, `earU`, `earF`, `pupil`, `lid`, `purr`, `lift`, `wh`, `mouth`;
  - an ambient flag in `busy`, so idle twitches and blinks don't freeze when the RAF loop sleeps (`island.ts:730-743`);
  - badge moved beside the right ear;
  - head-only clip path.
- **Greeting** (`greeting.ts`) and **upload** (`upload/canvas.ts`) redrawn with the cat renderer. The upload sequence becomes the mouth-catch.
- **Icons:** `windows/scripts/gen-icons.mjs` draws the active cat head (reusing its renderer math). It also emits the macOS `AppIcon.appiconset` (10 PNGs) and the `MenuBarIcon.imageset` template (24×18 / 48×36 / 72×54, black plus alpha).
- **Settings:** Character, Motion style, and per-cat motion override (Tauri `settings.rs` and `settings/main.ts`).

### 4. Swift port (macOS)
- Mirror the split: `CatEngine.swift`, `CatRenderer.swift`, `CatPresets.swift`, `MotionProfiles.swift`. Keep the members `BotCanvasView.swift` uses, so `IslandViewContent`, `HookServer`, `AppState` and the FSM are untouched.
- **Fix the clock bug:** use `CACurrentMediaTime()` on both sides of `dt` (`BotCanvasView.swift:15-17`, `:170-171`).
- `GreetingCanvasView.swift` and `UploadCanvasView.swift` redrawn.
- **Ear headroom:** compact mask (`IslandRootView.swift:98-103`) and Ø20 compact sizing (`IslandScreenGeometry.swift`). Ears are scaled down at the compact detail level.
- Settings rows in `SettingsView.swift`, persisted in UserDefaults.

### 5. Theme tokens
- `shared/theme.json` (palette, state colours, radii, type scale) → a small Node generator → `Theme.generated.swift`, `theme.generated.css`, `theme.generated.ts`.
- Character and greeting colours come from the presets.
- Only character, branding and greeting colours change. Existing UI views keep upstream styling (upstream rule).

## Verification
- **Prototype:** the user reviews it interactively (states, emotes, presets, sizes) before step 3.
- **TypeScript:**
  - `cd windows && npm install && npm run dev`, browser preview; `bridge.ts` no-ops outside Tauri. Add a `?dev` state panel to drive every state and emote.
  - `npx tsc --noEmit`.
  - Windows/Linux builds via the fork's `windows.yml` / `linux.yml` CI.
- **macOS:**
  - `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build`, then run the app.
  - Settings → install hooks. Check the `~/.claude/settings.json` diff and backup, and that entries point at `Application Support/NotchMeow/nm-hook`.
  - Drive states deterministically by piping JSON events to the socket, e.g. `printf '{"hook_event_name":"Stop","term_program":"vscode",...}' | nc -U ~/Library/Application\ Support/NotchMeow/nm.sock`.
  - Then run real Claude Code in a VS Code terminal. The macOS build only accepts VS Code, Cursor, Codex and tagged agents. Check: prompt → thinking, tool → working, permission → approval card, finish → finished, error → error.
- **Tests:** `scripts/test-*.sh` (8 swiftc tests) and the fork's `build.yml` CI.
- **Identity check:** the `rg` in step 1, plus confirming that upstream Coucou (if installed) and NotchMeow don't remove each other's hook entries.
