# CC0 cat sound candidates, the hairball (sub-project C)

Researched 2026-10-05. The research downloaded no audio and listened to nothing. Pages were read over plain HTTP (no login, no API key, no account), waveform and spectrogram images were read as images, and a HEAD request read each preview's size.

**Short answer: I found exactly three CC0 recordings of a real cat coughing or retching (all on Freesound), and none matches the animation unedited.** A clip described in other words could still exist, but these searches covered the descriptions, titles and tags. The best one, `cat vomit 2.wav` by Electron John, has the rhythmic "hack, hack, hack ... hurk" in it, but at a third of the animation's tempo and with a wet ending, so it needs splicing. Nothing on BigSoundBank or OpenGameArt applies. The two other real cat-vomit recordings on Freesound are CC BY, not CC0, so the spec excludes them.

## Method

- **Freesound.** Read the public search pages with the Creative Commons 0 filter on and "group by pack" off. Well over 100 queries across hairball, furball, cat cough, cat retch, cat gag, cat vomit, cat puke, hack, hawk, heave, wheeze, throw up and the same words with kitten, kitty and feline. Also searches by tag with the CC0 filter (`cat` plus each of vomit, puke, cough, coughing, retching, gagging, hairball). I ran the same queries without the CC0 filter, to see the whole pool and make sure no CC0 sound was missed. Every sound that looked relevant got its own page read: description, tags, uploader and the licence box.
- **BigSoundBank.** Searched cat, cough, vomit, retch, gag, hairball, sick. See "Checked and rejected".
- **OpenGameArt.** Advanced search with the Sound Effect type and the CC0 licence chosen: hairball, vomit, retch, gag, hack, sick, cough, cat, feline, kitten. See "Checked and rejected".
- **Wikimedia Commons** (not on the brief's list, checked for completeness): nothing usable.
- **Licence.** Read on each chosen sound's own page. The licence box says Creative Commons 0 and links `creativecommons.org/publicdomain/zero/1.0/` on all three, checked 2026-10-05.
- **Windows.** Estimated from the waveform images (780 px wide, so 15.5 ms per pixel for the 12 s clip, 27 ms per pixel for the 21 s clip) and the spectrograms. I decoded the PNG envelope to find each burst's start and end. **Treat every window as an estimate (about 30 to 55 ms), and verify it against the decoded audio before building, as the fifth-set pass did.**
- **Excluded:** every clip already in `.claude/sounds/candidates/manifest.json`, `cc0-candidates.md` and `cc0-candidates-set5.md`. None of the three below appears in them.

## The hairball's timeline, from `design/prototype/cat-core.js`

Measured by running `CatEngine` headless at 60 fps: `emote('hairball')`, `catchReject('exe')` and `setState('error')` in Playful. All times are ms from the start of `hairball()`, which also logs the note `hairball` at that moment.

| Beat | ms | What the engine does |
|---|---|---|
| Start | 0 | Ears back (150 ms ease), eyes closed until 1300, mouth and body start to move |
| Heave 1 | 140 | Mouth peak 0.22, head up 0.06, squash. Opens 0 to 140, closes 140 to 320 |
| Heave 2 | 460 | Mouth peak 0.28. Period 320 ms (3.1 per second) |
| Heave 3 | 780 | Mouth peak 0.34, head up 0.09 |
| **Retch, ball out** | **1110** | Mouth wide open 1.05 (opens 940 to 1110). `spitBall` fires at 1110: the ball plus 4 fur puffs |
| Hold, close | 1270, 1530 | Mouth held open to 1270, closed by 1530 |
| Relief | 1450 | Happy eyes (900 ms), blush, smile 0.5 |
| Lick | 1770 | Tongue flick, 90 ms |
| Ball lands | about 1800 to 1900 | First floor hit. Measured over four seeds and two mouth heights: 1800 to 1900 ms |
| Ball bounces | about 2220 to 2380 | Second hit, then a tiny third at 2370 to 2550 |
| End | 2440 | Smile eases back. The spec's 2.4 s |
| Ball off screen | 3510 | The ball lives 2.4 s from the spawn (2.6 s when it carries a refused file, so 3710) |

Where it starts:
- **Emote or prototype button:** t = 0.
- **Refused file:** `catchReject` waits 120 ms, so the heaves are at 260, 580 and 900, the retch at 1230, the lick at about 1890 and the end at about 2560.
- **Error state (Playful only):** `hairball()` runs 900 ms after the error state starts, so the heaves are at 1040, 1360 and 1680, the retch at 2010 and the end at about 3340. The error state's hiss pose (mouth open 80 to 650 ms) comes before it.
- **Classic motion:** the error state has no hairball. A refused file still does.

## Candidates, ranked

Formats are kHz/bit depth, for the Freesound original (the preview is an mp3). "Heaves" are the dry hacks; the animation has 3 and then the retch.

| Slot | Candidate (author) | URL | Duration | Format | Note |
|---|---|---|---|---|---|
| hairball | **cat vomit 2.wav (Electron John), rank 1** | https://freesound.org/people/Electron%20John/sounds/82543/ | 12.12 s | 44.1/16 mono WAV | A real cat (the uploader's wife's cat, Monkey) vomiting, from a video clip; uploader says "the quality is not great". Rated 4.0 (21 ratings), 1043 downloads, tags cat, puke, vomit. **About 11 heave pulses** in the waveform (and a smaller 12th), then a wet cluster. The heaves are discrete, sharp pulses with a short tail, each about 0.13 s wide (estimated). Their onsets (estimated): 0.26, 0.45, 0.76, 1.15, 1.88, 2.58, 3.37, 4.20, 4.94, 5.92, 6.82 s. The loudest and most even are the last four (peaks about -10 to -12 dBFS): **4.20, 4.94, 5.92, 6.82 s**, spaced 0.74, 0.98 and 0.90 s apart. A smaller hack at 7.24 s, then the **retch and wet cluster at 7.68 to 8.30 s** (strongest 7.68 to 8.11). Past 8.3 s there are only faint blips (9.34, 10.27 s). **Fit:** the structure is right (hack, hack, hack, big hurk) but the tempo is 0.7 to 1.0 s per heave against the animation's 0.32 s, so it can't play unedited: a straight 4.1 to 8.4 s window is 4.3 s long. It needs a splice, below. Noise floor: about 24 dB under the peaks in the waveform, steady room and video-soundtrack noise; the spectrogram is cut off at about 16 kHz (probably the video's audio track). The wet cluster is the part to watch: it is crackly rather than liquid in the spectrogram, but it is a real vomit and could read as gross, so the splice keeps it to about 0.5 s or swaps it for a made-in-code plop. No sustained speech-like segment is visible in the 0 to 8.3 s region of the waveform. Licence checked on page. |
| hairball | **Cat Coughing.wav (har2h), rank 2** | https://freesound.org/people/har2h/sounds/561726/ | 21.00 s | 48/16 stereo WAV | The uploader's own cat coughing after two cold nights outside. Tags cat, cough, coughing, flu. No ratings yet, 142 downloads. **Seven single dry coughs** with silence between them, each a sharp broadband pop about 0.3 s wide including its decay (estimated): 2.23 to 2.56 s (peak about -5 dBFS), **4.25 to 4.55 s (the loudest, -3 dBFS)**, **7.32 to 7.62 s**, **10.85 to 11.12 s** (both about -4 dBFS), 14.35 to 14.62 s (about -11 dBFS), 17.93 to 18.22 s (-8), 19.84 to 20.16 s (-13). A faint tick at 0.7 s. **Fit:** these are one-shot hacks, so they are good raw material for the three heaves (take 4.25, 7.32 and 10.85 s, matched in level) but they are 3 s apart and there is no run and no final retch. The ending would have to come from the Electron John cluster or a made-in-code plop. Noise floor about 30 dB under the coughs, the cleanest of the three, but a low-frequency room band (the lowest part of the spectrogram) that the build's 100 Hz high-pass won't fully remove. Licence checked on page. |
| hairball | **01-01 Cat_Cough.wav (14GPanskaZakopcanik_Jonas), rank 3, weak** | https://freesound.org/people/14GPanskaZakopcanik_Jonas/sounds/420086/ | 2.49 s | 48/24 mono WAV | A school-project recording ("Pets"; the same pack has a degu, a dog and a cat meowing). No ratings, 63 downloads. **One cough event, estimated 0.76 to 1.17 s**, with faint ticks around it. Very quiet: the whole waveform peaks near -30 dBFS, and the noise floor is only about 14 dB under it, so the build would lift the room noise with it. Not usable as the heaves. Kept in the list only because it is the only other real CC0 cat cough. Licence checked on page. |

**No clip is a clean recording of the whole sequence at the animation's tempo.** The real recordings are raw material for a splice, not a finished moment. Peak levels below are read off the waveform images, assuming they are drawn at full scale (the very quiet third clip suggests they are).

### How a splice from rank 1 would line up with the animation

Estimated windows from `82543`, butted with about 8 ms crossfades. Each hack takes 0.12 s before its onset and 0.20 s after.

| Piece | Source window | Placed at (out ms) | Onset lands at | Animation beat |
|---|---|---|---|---|
| Hack A | 4.82 to 5.14 s | 10 | 130 | heave 1 at 140 |
| Hack B | 5.80 to 6.12 s | 330 | 450 | heave 2 at 460 |
| Hack C | 6.70 to 7.02 s | 650 | 770 | heave 3 at 780 |
| Retch and wet cluster | 7.56 to 8.09 s | 970 | 1090 | retch at 1110 |

That ends at about 1.50 s, which is the spec's cap for a cat moment. The 7.24 s hack and the blip at 7.38 s are left out. The same recipe works with rank 2's coughs for A, B and C (windows onset minus 0.10 s to onset plus 0.22 s around 4.25, 7.32 and 10.85 s), with the retch from rank 1 or from the fallback below.

## Checked and rejected

| What | Where | Why not |
|---|---|---|
| raw_cat_vomiting.mp3 (NoiseCollector) | https://freesound.org/people/NoiseCollector/sounds/100115/ | A real cat vomiting, 11.4 s, but the licence box is **CC BY 3.0**, not CC0 |
| catpuking.mp3 (NoiseCollector, "Mocha the fat cat throwing up") | https://freesound.org/people/NoiseCollector/sounds/80778/ | Real cat, 34.8 s, **CC BY 3.0** |
| Human impression of cat hacking up hairball (pfranzen) | https://freesound.org/people/pfranzen/sounds/347541/ | The one sound actually tagged hairball and hacking, but a **human voice** and **CC BY 4.0**, 2.8 s |
| Furball, Hairball, Fluffball (LilMati) | https://freesound.org/people/LilMati/sounds/453089/ | CC0, but a 0.3 s cartoon "fluffball" creature sound, not a cat |
| Steady The Calico (BalancedEnergy10) | https://freesound.org/people/BalancedEnergy10/sounds/265541/ | CC0, tagged hairball only because the description mentions them; a synthetic cat sound |
| Brushing cat - MS RAW (Sadiquecat) | https://freesound.org/people/Sadiquecat/sounds/807199/ | CC0, "hairball" is a joke about cat hair on a brush; no cough |
| Human gags and coughs: gagging (chestnutjam 399290), Gagging 1 (Turroe22 135415), Gagging / Vomit / Throwing up (Breviceps 446001), Gagging Sounds (bbrocer 382663), hack-coughing (Gerent 580332), Wheezing (thedapperdan 205012), throw up 2 (TheLittleCrow 456972), coughs_mixed (Leemuffin 585440), human dog barf (juanto9889 414878) | Freesound, all CC0 | **Human voices**, which the brief rules out. chestnutjam's description says it was made "with vomiting cats in mind", and it is a person gagging |
| BigSoundBank | https://bigsoundbank.com/search?q=cough and `q=vomit` | Nothing for a cat: "Cough" has men, a woman, a child and a horse, "Vomit" has four men, "Hairball" and "Retch" have no results, the cat series is meows, purrs, growls and roars |
| OpenGameArt | CC0 sound search | Nothing: hairball, vomit, retch, gag and puke have no results; "cat" and "feline" return only meows, purrs and a kitten mew; "sick" returns two results (Sick Noises, Gastric Distress), neither tagged cat |
| Wikimedia Commons | `filetype:audio` search | Only word-pronunciation files ("hairball" in English, "vomit" in Catalan), no cat recording |

## Download list

Previews are the HQ mp3 from the page's own player (the page lists the `-lq` URL; the `-hq` file is the same name, as in the set-5 list). Sizes are Content-Length from a HEAD request, all returned HTTP 200. File names follow the manifest convention. The Electron John name drops the space in the uploader's username. Note that `recipe.py` only accepts a source of the form `<slot folder>/<file>` where the folder is a slot, so these folders need a `hairball` slot (see "How it could fit"), or the clips go in an existing folder.

| Local file | Preview URL | Bytes |
|---|---|---|
| hairball/fs-82543-ElectronJohn.mp3 | https://cdn.freesound.org/previews/82/82543_1315778-hq.mp3 | 268928 |
| hairball/fs-561726-har2h.mp3 | https://cdn.freesound.org/previews/561/561726_8384492-hq.mp3 | 503328 |
| hairball/fs-420086-14GPanskaZakopcanikJonas.mp3 | https://cdn.freesound.org/previews/420/420086_7249762-hq.mp3 | 60720 |

**Total: 3 files, 832,976 bytes (about 813 KB).** Ranks 1 and 2 alone: 772,256 bytes (about 754 KB). For Stage 2 the originals are WAVs of 1.0 MB, 3.9 MB and 350 KB, which need the owner's logged-in download as in the spec.

## The made-in-code fallback

A new `hairball()` in `tools/sounds/synth.py`, registered in `GAPS` as `synth:hairball`, deterministic like the others (`random.Random(1205)`, 48 kHz floats, about half scale, normalised by the build). It is about 1.45 s long and is **timed to the animation**: every beat below is in ms from the start of `hairball()`. The pieces already exist in `dsp.py` and `synth.py`: `bandpass`, `lowpass`, `mix_at`, `_smooth`, `_noise`, and the pattern of `yawn()` (a tone whose frequency follows a contour by accumulating phase) and `search()` (a pulse train pushed through two formant `bandpass` filters).

**Each heave (three of them), onset 10 ms before the mouth peak:** onsets 130, 450 and 770 ms, 150 ms long.
- **The croak:** a pulse train at a pitch that falls from about 150 Hz to 105 Hz over the heave (starting at 150, 165 and 180 Hz for the three), through two `bandpass` resonators at about 650 Hz (Q 4) and 1900 Hz (Q 5), the same trick as `search()` at a lower pitch. Envelope: 4 ms attack, then exponential decay with a time constant of about 45 ms.
- **The burst:** a 40 ms noise burst through `bandpass` at 1.3, 1.5 and 1.7 kHz (Q about 1.1) with a decay of about 18 ms. This is the dry "hack" on top of the croak.
- **The click:** 1.5 ms of noise at the very start, level 0.5, the same device as `clink()`'s onset click.
- **Levels:** 0.60, 0.78 and 1.00, following the mouth's 0.22, 0.28 and 0.34 opening.
- **Between heaves:** a breathy intake about 80 ms long at 300 and 620 ms, `bandpass` at 2.8 kHz (Q 0.7) at about -20 dB, like the breath layer of `yawn()`.

**The retch, 930 to 1110 ms:** 180 ms of the same croak, but the pitch rises from 120 to 280 Hz, with a 28 Hz amplitude flutter at 50 % depth (the gurgle). It swells with `_smooth` from 930 to 1090 ms and stops abruptly at 1110 ms, the frame the ball leaves the mouth.

**The release, at 1110 ms:**
- A "plop": a sine gliding from 520 Hz down to 180 Hz with a decay of about 35 ms, the shape of `blip()` turned upside down.
- A 40 ms burst of noise through `lowpass` at 1.2 kHz for the wet body.
- A faint 3.4 kHz tick (one `clink()` partial).
- **A 200 ms wet tail** of `lowpass` noise at 800 Hz with a 25 Hz flutter, about -26 dB, then a fade out by 1450 ms. This replaces `pop` at the ball-out.

**Optional, past the 1.5 s cap:** two soft low-passed thumps (about 180 Hz, 25 ms) at about 1850 and 2300 ms for the ball's two hits. Only worth it if the cap moves; the ball is quiet and the toy squeak was the stand-in.

**Hybrid:** the same retch and plop on top of rank 2's coughs for the three heaves. That puts real hacks in front of a made-in-code finish and avoids the wet vomit.

In `_shared.json`: `{"slot": "hairball", "source": "synth:hairball", "mood": "upset", "signature": false}`. The upset touch (a falling filtered tone under 120 ms, 18 dB under) would sit on the first heave, which the owner may want to turn off for this slot.

## How it could fit

- **What it replaces.** Both. The `annoyed` meow during the heaves is wrong for the gag (a meow is not a hack), and the `pop` at 1110 ms is a toy squeak. One baked 1.45 s sound covers the heaves, the retch and the plop, fixed to the animation's beats. `pop` stays as the interface tick.
- **Slot and length.** It would be a 29th cat moment (spec section 1 lists 28; `hairball` is wired but not a slot today, so `recipe.py`'s `SLOTS`, the "all 28 files exist" test and the Windows/Mac sound tables each gain one). It fits the 1.5 s cap for cat moments at about 1.45 to 1.5 s. It would sit in the "everything else" tier of the priority order.
- **One shared sound, not a per-set pick.** Like gulp. There is no voice to match, hacks are cat-neutral, and there is only one recorded source to choose from, so nothing for the five sets to differ on. Put it in `_shared.json`, and add it to the audition page's "same in every set" list; the 15 pickable moments don't change.
- **Per-cat pitch offset: exempt it.** The offset is playback rate, 2^(st/12), which moves the beats. The retch at 1110 ms would land at 1176 ms for Shrimpy (-1 st, 66 ms late), 1048 ms for Momo (+1 st, 62 ms early) and 933 ms for the kittens (+3 st, 177 ms early), so the sound would stop lining up with the mouth. A cough is not a voice, so skipping the offset costs little. The chattiness volume (x0.7 to x1.15) can still apply. If a per-cat pitch is wanted, play the three hacks and the retch as separate small samples scheduled on the beats instead of one baked file.
- **Trigger.** On the engine's `hairball` note, which fires at the start of the sequence in all three paths (the emote, the refused file and the error state), not on the error or drop event itself.
- **Watch: the error path.** In Playful the hairball starts 900 ms after the error sound. The priority rule says a new cat moment never replaces a higher-ranked one that is still playing, and error ranks above "everything else". If the error clip runs past 900 ms, the hairball is dropped. Most error clips are 0.25 to 0.9 s, but the rule needs a decision: let the hairball overlap, or keep the error clip under 0.9 s. The hairball is silent while the island is hidden under the visibility rule, which suits it.

## Gaps and risks

- **Quality.** The best real recording comes from a phone video in 2009 and is ranked first because it has the pattern, not because it is clean. Expect to gate or lightly denoise the gaps, and to listen for any human or room sound in the 7.6 to 8.3 s cluster.
- **Wet part.** A real vomit tail is the thing most likely to read as unpleasant in a cute app. The splice keeps it under about 0.5 s and the made-in-code release can replace it entirely.
- **Not listened.** No window above was heard. Each one needs the decode-and-measure pass the set-5 research did before it goes in a recipe.
- **Build tooling.** `build_pack.py` takes one start and one end per entry, so a splice needs either a new `segments` field in the recipe (a list of source windows and the output offset for each) or a one-off edit outside the pipeline. The made-in-code route needs no tool change beyond the new slot.
- **Thin pool.** If real hacks matter more than CC0 purity, the CC BY 3.0 NoiseCollector recordings above are real cat vomiting at a much higher count of heaves. That would need a spec change (the `LICENSE-ASSETS.md` carve-out is CC0 only) and a credit line.

## Outcome, 2026-10-05

The owner auditioned three versions built from these clips and picked **B, the hybrid**: three coughs of har2h's *Cat Coughing* (rank 2) with the retch and plop of "The made-in-code fallback" (version A used rank 1's heaves and its own final hurk; version C was all made in code). Electron John's *cat vomit 2* is therefore not in the shipped recipe, and the rank 3 clip was never downloaded.

The windows above were estimates, and the build uses measured ones: the coughs of the decoded har2h clip start at 2.258, 4.276 and 7.358 s (the estimates were 2.23, 4.25 and 7.32 s). The recipe is the `hairball` entry of `design/sounds/sets/_shared.json`, a placed sound (`recipe.py`, source `placed`): three windows of the clip, equal-power faded and placed so the onsets fall at 115, 435 and 755 ms, then `synth.hairball_retch_plop` (seed 1205) at 930 ms. `tests/test_sound_build.py` checks that it rebuilds the audition file `B.wav` byte for byte (SHA-256 `77f70082aa72a6ce68a8137f69002960b29995f3e7da9882882db5e1dfdec1ca`) wherever the clip is found.

Stage 2 swaps the preview mp3 for the full-quality original. The decoded timeline may shift (a decoder's start padding), so re-measure the three onsets on the original, move the windows to match, and pin the new SHA-256 in the test.
