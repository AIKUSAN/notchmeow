# Sub-project C: NotchMeow's sounds

**Status:** design approved in chat on 2026-10-04. This is the written spec for review. Revised the same day: the owner picks each cat moment instead of a whole set (see "Picking per moment").

**Parent spec:** `docs/superpowers/specs/2026-10-03-notchmeow-design.md`, the "Sounds" row. That row already decides:
- the mixed CC0 plus made-in-code set;
- two-tier layering;
- a per-cat pitch offset until real recordings exist;
- no in-app sound packs before then.

Candidate sources are in `design/sounds/cc0-candidates.md`. This document decides how the sounds are chosen, built, licensed and wired.

## Decisions

| Topic | Decision |
|---|---|
| Choosing | **Per moment.** Five complete sets that differ only in the cat voice are the menu. The owner auditions them side by side and picks a version for each of the 15 cat moments that differ, or "None of these", which gets a second round. The picks are locked in as **Your mix**, and that mix ships. No switching between sets inside the app. See "Picking per moment". |
| Sources | Public Freesound previews and free BigSoundBank files for auditioning. These were downloaded on 2026-10-04: 63 clips covering all 28 slots, all marked CC0, kept in the scratchpad and not in the repo. A fifth set, Tabby, added 24 more clips on 2026-10-05 (22 of foxboyprower's Tabby, plus one snore and one trill from two other uploaders), also all CC0 and kept out of the repo. Two hairball clips followed the same day (Electron John's cat vomit and har2h's cat coughs, CC0; see "Hairball"). The clips in the owner's mix are rebuilt from Freesound's full-quality originals. |
| Build | **Built ahead of time.** A build script mixes each set into finished WAVs. Both apps only play files. |
| Order | Stage 1 (sets and the audition page) can run now, and the mix picker follows it. Stage 2 (originals, final pack, licence files) runs after the owner locks in a mix with no "None of these" left. Stage 3 (wiring) runs after sub-project A, because the per-cat voice needs A's Character setting. |

## 1. Slots and sets

**Slots.** There are 29: the 28 names both apps already call, `peek, open, close, hover, blip, slap, annoyed, dizzy, greet, work, finish, error, approval, question, approve, gulp, tick, send, love, pop, proud, wink, yawn, attach, think, search, rate, sleep`, and `hairball`, added on 2026-10-05.
- **Cat moments (19):** greet, love, annoyed, dizzy, slap, finish, error, approval, question, proud, wink, yawn, sleep, gulp, think, search, work, rate, hairball.
- **Interface ticks (10):** approve, peek, open, close, hover, blip, tick, send, attach, pop. Ticks never use a meow.

**Sets.** Ticks and made-in-code fill-ins are identical in every set.

| Set | Voice |
|---|---|
| Studio | BigSoundBank's cat Emi (pro session). Trill slots borrow MBPL's soft trills. |
| Steff's cat | steffcaffrey's single male cat (twits, purrs, chirps). Gaps come from MBPL and Sadiquecat. |
| Kitten | Department64's Oscar, using only the `kitten##` files and Buddha Purr. Pitched up 1–2 semitones across the whole set. |
| Best of | The top-rated clip per slot, with one shared pitch shift so the set still sounds like one cat. |
| Tabby | foxboyprower's Tabby, an old tabby cat (13 of the 15 moments). Sleep borrows lolamadeus' snore. Search borrows jsbarrett's trill, kept as a real alternative to the made-in-code chatter. |

**Excluded from every set:**
- *Cute Computer Squeak* (qubodup): its description points to CC BY.
- *Begging Meow* (Lukey1028): the uploader mixes CC0 and CC BY uploads.
- Any Department64 upload that isn't CC0.

## 2. The build

- **Recipes.** `design/sounds/sets/<set>.json` holds one entry per slot: the source clip, trim start and end, gain, pitch in semitones, and effects (for example, the dizzy wobble).
- **Script.** `tools/sounds/build_pack.py` uses the Python 3 standard library plus macOS `afconvert`, the only external tool, and is run by the owner or an agent on the Mac. For each slot it:
  1. decodes to 48 kHz mono;
  2. high-passes at 100 Hz;
  3. fades 3 ms in and 20 ms out;
  4. sets short-term loudness to about −20 LUFS for vocals, with ticks 6–10 dB under;
  5. limits true peak to −1 dBTP or lower;
  6. synthesises the gaps;
  7. mixes the layers (§3);
  8. writes 16-bit WAVs.
- **Gap recipes.** These come from `cc0-candidates.md`, "Gaps to synthesize":
  - **yawn:** falling squeak plus breathy noise, about 0.8 s;
  - **work:** fabric-pat noise bursts, alternating left and right;
  - **search:** edited chatter, or a 12 Hz click train through a formant filter;
  - **rate:** a tail thump at 80–120 Hz;
  - **dizzy:** a ±1-semitone wobble at about 5 Hz;
  - **attach:** a collar-tag clink of two inharmonic partials at 3–6 kHz.
- **Audition.** Every set builds into the scratchpad. `design/sounds/audition.html` plays each slot in all five sets side by side, with a "play the whole set" run-through, and holds the pickers ("Picking per moment").
- **Ship.** Your mix's 29 WAVs go to `NotchBuddy/Resources/sounds/`. The Windows/Linux app already serves that folder (`vite.config.ts` `SOUNDS_DIR`).

## Picking per moment

Added on 2026-10-04, replacing the whole-set choice. The owner picks each cat moment separately, and the picks ship as **Your mix**.

**What's pickable.** The 15 moments that differ between the sets: greet, love, annoyed, dizzy, slap, finish, error, approval, question, proud, wink, sleep, think, search and rate. The other 13 (the 10 ticks, yawn, work and gulp) are the same in every set, and the page labels them "same in every set".

**On `audition.html`:**
- Each pickable row has a select dot by each set's Play button, plus **None of these**. The chosen cell is highlighted.
- Each set column has **Use this set for all**, which fills all 15 rows with that set.
- A counter shows "12 of 15 picked". None of these counts as an answer.
- **Play my mix** plays all 29 sounds in order from the already-built set files: the 15 picks and the 14 shared sounds.
- **Lock in** turns on at 15 of 15. It freezes the pickers and shows a summary (moment → set, or "none"). **Change picks** unlocks them.
- Picks survive a reload through `localStorage` (inside try/catch). That is a convenience only; the record is `mine.json`.
- After the owner locks in, the main session reads the summary from the page in the app's browser pane and writes `mine.json`. The owner downloads or pastes nothing.

**`design/sounds/sets/mine.json`** (committed) holds the title "Your mix" and, for each of the 15 moments, a set name (`studio`, `steff`, `kitten`, `bestof`), `none`, or a round-two entry (`round2:<moment>-<n>`).
- **Loading.** Each moment copies the picked entry and carries its set's pitch shift into it, so a Kitten moment keeps +1.5 semitones and a Best of moment −1.0. A round-two entry keeps its own pitch. The 13 shared sounds come from `_shared.json`.
- **Checks.** All 15 moments, each exactly once. An unknown name is an error. Listing a shared sound is an error. `none` may sit in the file, but `build_pack.py --set mine` refuses to build while any moment is `none`, and names them.
- **Build.** The same pipeline and checks as the five sets, with its own report section. Every picked file is byte-identical to its source's file, and a test pins that.

**Round two**, for moments marked None of these:
- A Sonnet subagent proposes up to 3 alternatives per moment from the 87 CC0 candidates (the 63 plus the fifth set's 24). It skips the excluded clips and the clip windows the five sets already used for that moment, leans toward the voice the owner picked most, and notes why it chose each one. The main session reviews them.
- They are ordinary entries in `design/sounds/sets/round2.json` (`rate-1` to `rate-3` and so on), with mood and signature fixed by the slot table. `build_pack.py --round2` builds them to `.claude/sounds/build/round2/`.
- The page adds Alt 1–3 columns to those rows only. The owner picks and locks in again.
- There is no automatic round three. A moment that still misses is settled in chat: a made-in-code sound, or waiting for the real Shrimpy and Momo recordings. If the candidates have nothing that fits a moment, the round-two report says so instead of padding with weak options.

**Timing.** A follow-up plan (`c1b-mix-picker`) builds this after the Stage 1 plan merges, and Stage 1 stays as written. Choosing the round-two alternatives is a data step, not code.

## 3. Layering and voice

**Touch.** Every cat moment gets one: 120 ms or shorter, about 18 dB under the vocal, aligned to the vocal's first transient.

| Mood | Slots | Touch |
|---|---|---|
| Happy | greet, love, finish, proud, wink, gulp | Two quick sine partials stepping up a major third |
| Attention | approval, question, think, search | An 80 ms glide up a fifth |
| Upset | error, annoyed, rate, dizzy | A filtered tone gliding down a minor third |
| Calm | slap, yawn, sleep, work | One soft, low-passed tick |

**Signature.** Plays on greet, finish, approval, question, error and love: about 0.2 s of rising sparkle, made of three inharmonic collar-bell partials, about 10 dB under the vocal. It starts at 60 % of the vocal's length. Error uses a lower, darker version of the same run.

Ticks get neither layer.

**Per-cat voice.** Applied at play time, to cat moments only, as playback rate 2^(st/12). The hairball is the exception: it plays at rate 1 for every cat, because a rate change would move its retch off the moment the ball comes out (by up to 177 ms for a kitten). The chattiness volume still applies to it.
- **Offsets:** Shrimpy −1 semitone, Momo +1, the 14 extra coats 0, kittens +3 (sub-project B).
- **Where it lives:** the offset is the `voice` field of each cat in `tests/fixtures/cat/presets.json`, the A-0 contract, so both apps read one value.
- **Implementation:** on macOS, `AVAudioPlayer.enableRate` and `rate`; on Windows/Linux, `AudioBufferSourceNode.playbackRate`.

**Hairball.** One shared sound in every set, like gulp: a hack has no voice to pick between sets, so it is not a pickable row and needs no touch or signature layer. The owner auditioned three versions on 2026-10-05 and picked **B, the hybrid**:
- **Heaves:** three real dry coughs from *Cat Coughing* (har2h, Freesound 561726, CC0), placed so their onsets fall at about 115, 435 and 755 ms, just before the animation's heave peaks at 140, 460 and 780 ms (`cat-core.js` `hairball()`, Playful). They are joined with 60 ms equal-power crossfades.
- **Retch and plop, made in code:** a gurgly pulse train rising from 120 to 280 Hz through the heaves' two formant band-passes, swelling from 930 ms, then a falling-sine plop at 1110 ms, when the mouth is fully open and the ball comes out, with a short low wet tail.
- **Length and level:** 1.48 s, at the cat-moment loudness target, with the usual 100 Hz high-pass and fades.
- **Reference:** the audition file `B.wav` (SHA-256 `77f70082…dfec1ca`), built by a one-off script. Plan `c1c-hairball` makes the build reproduce it from a recipe. A refused file shifts every beat by 120 ms and Playful's error by 900 ms, so the sound starts on the engine's `hairball` note, not on the file drop or the error.

**Chattiness.** The personality trait scales cat-moment volume from ×0.7 to ×1.15. Ticks are unaffected, and the existing volume setting still sets the overall level.

## 4. When sounds play

**Kept as wired today:**
- peek, open, close and hover: the island peeking, opening, closing, and hover;
- greet: the launch greeting;
- finish, error, approval, question and rate: the agent events;
- approve: clicking Allow;
- send, tick, blip and pop: chat and interface actions;
- slap and annoyed: pokes;
- love: hover and the start of an attach-drag.

**Newly wired:**

| Slot | Plays on |
|---|---|
| gulp | the gulp in the file catch |
| dizzy | the dizzy state starts |
| proud, wink, yawn | those emotes |
| attach | a file attached to the chat |
| think | a prompt is sent, once per prompt |
| search | the searching state starts |
| work | idle or thinking turns into working (kneading pats) |
| sleep | falling asleep: one soft snore, never a loop |
| hairball | the engine's `hairball` note (a refused file, Playful's error, the emote): the shared hairball sound, which covers the heaves, the retch and the ball coming out. It replaces the earlier plan of `annoyed` during the heaves and `pop` at the end. |
| zoomies | silent |

**Play rules.** Both apps follow these, from `tests/fixtures/sound/rules.json`:
- **Priority.** Cat moments never overlap. A new one replaces the one playing unless the playing one ranks higher. The order, highest first:
  1. approval, question and error;
  2. finish and rate;
  3. everything else.

  Ticks may overlap. One exception: the hairball may replace the error sound it follows, because Playful's error hiss ends in the hairball 900 ms later and both belong to the same moment.
- **Cooldowns.** The same cat moment plays at most once per 2 s. work and search play at most once per 30 s.
- **Visibility.** Background slots (think, work, search, sleep, yawn) play only while the island is visible. Alerts (approval, question, error, finish, rate) also play while it's hidden.
- **Sound off** silences everything.

## 5. Licences and credits

- **`LICENSE-ASSETS.md`** gets a carve-out: the CC0 source clips remain CC0 and are excluded from "all rights reserved". NotchMeow's own mixes and made-in-code sounds stay reserved.
- **`docs/SOUND-CREDITS.md`** lists every shipped clip: slot, title, author, page URL, licence, licence-check date, and the SHA-256 of the original. Uploaders are credited even though CC0 doesn't require it; Breviceps asks for it.
- **`design/sounds/sources.json`** is the machine-readable source list. The build refuses any source without a verified CC0 entry.
- **Re-check.** Before Stage 2, a second agent re-checks the licence on every shipped clip's own page, independently of the download agent.
- **Originals.** Getting the Freesound originals of the clips in Your mix needs a logged-in download.
  - If the owner is signed in to Freesound in Chrome, an agent downloads the listed files through that session after the owner confirms the list.
  - Otherwise the owner downloads them from the list.
  - Agents never log in or handle credentials.

## 6. Checks

- **Rules.** `tests/fixtures/sound/rules.json`: priority, cooldowns, hidden-island behaviour. Both apps have tests against it.
- **Build.**
  - Rebuilding a set gives byte-identical WAVs.
  - A loudness report checks every file against its targets.
  - All 29 files exist.
  - Lengths: cat moments up to 1.5 s, sleep up to 3 s, ticks up to 0.4 s.
  - Your mix: every picked file is byte-identical to its source's file, and a mix with a moment still `none` can't build for shipping.
- **Licences.** The build fails on any source missing a CC0 entry. `SOUND-CREDITS.md` and `sources.json` must agree.
- **Owner's manual checks.**
  - Listen through the audition page, pick each moment and lock in Your mix, with a second round if needed.
  - After wiring, check sounds through the socket-driven states.
  - Check Sound off, the cooldowns, and that background sounds are silent while the island is hidden.

## Stages (the C plan)
1. **Sets and audition.** `build_pack.py`, the five recipes, the gap synthesis, the layering, `audition.html`, and the loudness report.
   - **1b. Mix picker** (follow-up plan `c1b-mix-picker`): the pickers and Lock in, `mine.json` and its loader, `--set mine` and `--round2`. **Owner locks in Your mix**, with round two for any "None of these". Locked in on 2026-10-05 (`cbc771e`).
   - **1c. Hairball** (follow-up plan `c1c-hairball`): the 29th slot, and the build's two new recipe parts (placed clip segments and a made-in-code layer) that rebuild the owner's pick from its recipe. Before Stage 2.
2. **Final pack.** Independent licence re-check, then the originals, then rebuild Your mix into `NotchBuddy/Resources/sounds/`. Add `sources.json`, `SOUND-CREDITS.md` and the `LICENSE-ASSETS.md` carve-out.
3. **Wiring, after A.** Newly wired slots, play rules, per-cat voice and chattiness volume, on both apps.

## Risks
- **Preview versus original.** The originals may sound slightly different from the auditioned previews. The owner listens once more after the Stage 2 rebuild.
- **Loudness on short clips.** Short-term LUFS is noisy under 1 s. The report also prints RMS and peak, and the targets allow ±1.5 LU.
- **Rate-based pitch shift.** It changes length by about 6 % per semitone, which is inaudible at these lengths. If that ever matters, a time-stretch could replace it later.
- **Mixed voices.** Moments picked from different sets come from different real cats, so two moments can sound like two cats. Round two leans toward the voice picked most, the per-cat offset applies to all of them alike, and Play my mix lets the owner hear the whole mix before locking it in.

## Done means
- Your mix plays on both apps from the same 29 files.
- Every shipped clip has a re-checked CC0 entry and a credit.
- The play rules pass their shared tests on both platforms.
- The owner signs off on the sound by ear.
