# Sound Sets and Audition Page (C, Stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build four complete, loudness-checked sets of NotchMeow's 28 sounds from the CC0 candidate clips, and a static page to audition them side by side, so the owner can pick one set.

**Architecture:** A pure-Python (standard library) pipeline in `tools/sounds/` reads recipes from `design/sounds/sets/`. For each slot it decodes a candidate clip with macOS `afconvert` (or synthesises a gap sound), trims, pitch-shifts, applies effects, high-passes, fades, mixes the touch and signature layers, levels to the spec's loudness, limits the true peak and writes a 16-bit mono 48 kHz WAV, then measures the written files for a report. `design/sounds/audition.html` plays the result over `file://`. Nothing in this stage touches the apps.

**Tech Stack:** Python 3.9 or newer (the macOS system `python3` is 3.9), standard library only (`wave`, `struct`, `math`, `array`, `json`, `random` with fixed seeds, `unittest`), macOS `afconvert`, plain HTML and JavaScript with no external scripts.

**Spec:** `docs/superpowers/specs/2026-10-04-sounds-design.md`. This plan is Stage 1: sections 1, 2 and 3, the "Build" checks of section 6, and "Stages" item 1. Stages 2 (final pack, licence files) and 3 (wiring, per-cat voice) get their own plans; this plan only keeps room for them (see "Interfaces for Stages 2 and 3" at the end). Candidate sources: `design/sounds/cc0-candidates.md`.

**Execution.** Run this plan in a git worktree on a new branch `c1/sound-sets` cut from `notchmeow/rebrand`, with subagent-driven development. The plan was written when the branch was at `6a7caac` and replayed on `683163f`, after the E1 merges landed; nothing in the plan touches a file those merges changed except `.github/workflows/build.yml`, whose step list Task 11 describes as of `683163f`. The controller creates the worktree once:

```bash
cd "/path/to/notchmeow"
git worktree add .claude/worktrees/c1-sound-sets -b c1/sound-sets notchmeow/rebrand
cd .claude/worktrees/c1-sound-sets
```

Every command in the tasks runs from the worktree root. The 63 candidate clips are git-ignored, so the worktree does not have them: `build_pack.py` finds them in the main checkout on its own (Task 8), or take them from `NM_SOUND_CANDIDATES`.

Agents (from `CLAUDE.md`): Tasks 1 to 6, 9, 10 and 11 hand over complete code, so `nm-implementer-light` can transcribe them; Tasks 7, 8 and 12 integrate and run things, so use `nm-implementer`; each task gets an `nm-reviewer`, and the finished branch an `nm-reviewer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`. The commit steps below carry the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`: an implementer running on another model puts that model's name in the trailer instead (for example `Claude Haiku 4.5`). Never push.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and the brief.

- **Slots (28):** `peek, open, close, hover, blip, slap, annoyed, dizzy, greet, work, finish, error, approval, question, approve, gulp, tick, send, love, pop, proud, wink, yawn, attach, think, search, rate, sleep`. Cat moments (18): greet, love, annoyed, dizzy, slap, finish, error, approval, question, proud, wink, yawn, sleep, gulp, think, search, work, rate. Interface ticks (10): approve, peek, open, close, hover, blip, tick, send, attach, pop. Ticks never use a meow.
- **Sets (4):** Studio (BigSoundBank's cat Emi; trill slots borrow MBPL's soft trills), Steff's cat (steffcaffrey; gaps from MBPL and Sadiquecat), Kitten (Department64's `kitten##` files and Buddha Purr only), Best of (the strongest clip per slot, one shared pitch shift). Ticks and made-in-code fill-ins are identical in every set.
- **Excluded from every set:** *Cute Computer Squeak* (qubodup), *Begging Meow* (Lukey1028), any Department64 upload that is not a `kitten##` file or Buddha Purr.
- **Tools:** Python 3 standard library plus macOS `afconvert`. Nothing else, no pip. Code must run on Python 3.9 (no `match`, no `X | Y` types at runtime, no 3.10+ library calls) and on current Python 3.
- **Output:** `.claude/sounds/build/<set>/<slot>.wav`, 48 kHz, mono, 16-bit, 28 files per set; plus `.claude/sounds/build/report.md`.
- **Processing, in the spec's order:** decode to 48 kHz mono; high-pass at 100 Hz; fades 3 ms in and 20 ms out; vocals at about -20 LUFS short-term (+-1.5 LU); ticks 6 to 10 dB under the vocals; true peak at or below -1 dBTP; write 16-bit WAV.
- **Lengths:** cat moments up to 1.5 s, sleep up to 3 s, ticks up to 0.4 s.
- **Touch (every cat moment):** 120 ms or shorter, about -18 dB relative to the vocal, aligned to the vocal's first transient. Happy (greet, love, finish, proud, wink, gulp): two quick sine partials stepping up a major third. Attention (approval, question, think, search): an 80 ms glide up a fifth. Upset (error, annoyed, rate, dizzy): a filtered tone gliding down a minor third. Calm (slap, yawn, sleep, work): one soft, low-passed tick.
- **Signature:** about 0.2 s, three inharmonic collar-bell partials rising, about -10 dB relative to the vocal, starting at 60 % of the vocal's length. Only on greet, finish, approval, question, error and love. Error gets a lower, darker version. Ticks get neither layer.
- **Pitch:** Kitten is +1 to +2 semitones for the whole set. Best of uses one shared shift. The per-cat voice offset is a play-time feature of Stage 3 and is NOT baked into these files.
- **Determinism:** running the build twice gives byte-identical WAVs. A test asserts it with synthetic inputs, because CI has no candidate clips.
- **Git:** commit `tools/sounds/`, `design/sounds/sets/`, `design/sounds/audition.html`, `tests/test_sound_build.py`, `scripts/test-sound-build.sh` and the CI change. Never commit WAVs or anything under `.claude/`. Never push. Stage files by name; never `git add -A`.
- **Candidates:** `.claude/sounds/candidates/<slot>/` holds 63 CC0 previews and a `manifest.json` whose `file` paths point at an old scratch folder; recipes name clips as `<slot folder>/<file name>` and the build resolves them inside the candidates folder. The folder is git-ignored and must never be committed.
- **Repo rules that apply:** new views follow the existing app style (the audition page follows `design/sounds/listen.html`); never restyle what ships; `NotchBuddy/Resources/sounds/` stays untouched (the final pack is Stage 2).

## Review Focus

Inputs and conditions the spec implies but never spells out, most likely first. Each has a test in the task named after it.

1. **A recipe window outside the clip, an empty clip, or a window in a pause.** A person editing `start` and `end` by ear will get these wrong. Expected: a one-line error naming the slot, the clip and the window, and exit code 2, not a traceback and not an empty or silent WAV. Tests: Task 7 `test_a_window_outside_the_clip_or_in_a_pause_is_a_clear_error`, Task 8 `test_a_silent_window_stops_the_build_with_the_slot_named`.
2. **Paths with spaces, and running from another directory.** The repo lives under a folder whose name has spaces. Expected: the build and the recipe check work from any directory and any path containing spaces. Tests: Task 8 `test_the_script_runs_from_another_directory_with_spaces_in_every_path`, and every temporary folder in the tests has a space in its name.
3. **A git worktree has no clips.** `.claude/` is git-ignored, so a fresh worktree has no `.claude/sounds/candidates`. Expected: the build finds the main checkout's folder by itself, and says clearly when there is none. Tests: Task 8 `test_a_worktree_finds_the_main_checkouts_git_ignored_clips`, `test_find_candidates_order`, `test_a_build_without_clips_stops_with_a_message`.
4. **An excluded or non-CC0 source slipping into a recipe**, in any letter case or folder. Expected: the recipe is rejected before anything is built. Tests: Task 6 `test_excluded_and_non_cc0_sources_are_rejected_in_any_case`, Task 9 `test_no_set_uses_an_excluded_clip`.
5. **A source far quieter or louder than the others** (the downloaded clips peak anywhere from -38 to 0 dBFS). Expected: it still lands on the loudness target with its true peak under -1 dBTP, with no clipping and no runaway gain. Tests: Task 2 `test_normalize_handles_very_quiet_and_very_loud_clips`, Task 7 `test_a_very_quiet_clip_is_brought_up_without_clipping`.

## File Structure

`tools/sounds/` is a flat folder of modules that import each other by bare name (`import dsp`); `build_pack.py` puts its own folder on `sys.path`, and the tests do the same. No package, no `__init__.py`.

| File | Responsibility |
|---|---|
| `tools/sounds/dsp.py` | Filters (biquad high-pass, low-pass, band-pass), fades, resample-based pitch shift, glide and wobble, trims, onset and active-level helpers, peak limiter, gain, mixing |
| `tools/sounds/loudness.py` | BS.1770 K-weighting, short-term (400 ms) loudness, approximate true peak (4x oversampling), RMS, `normalize` |
| `tools/sounds/audio_io.py` | 16-bit WAV writing, WAV reading, afconvert decoding, the clip loader |
| `tools/sounds/synth.py` | Gap recipes made in code: blip, clink, yawn, work, search |
| `tools/sounds/layers.py` | Touch (four moods), signature (normal and dark), tail thump, and the mixing of layers against the vocal |
| `tools/sounds/recipe.py` | The 28-slot table, loading and validating `design/sounds/sets/*.json` |
| `tools/sounds/pipeline.py` | `build_slot` and `build_set`: one recipe entry to one finished sound |
| `tools/sounds/report.py` | Checks a measurement against the targets, renders `report.md` |
| `tools/sounds/build_pack.py` | The command line: `--set`, `--all`, `--report`, `--check-recipes`, candidate-folder lookup |
| `design/sounds/sets/_shared.json` | The 13 slots every set shares: ten ticks, yawn, work, gulp |
| `design/sounds/sets/{studio,steff,kitten,bestof}.json` | Each set's own 15 slots, with set-level pitch shift |
| `design/sounds/audition.html` | The static audition page |
| `tests/test_sound_build.py` | All unit tests (standard-library `unittest`) |
| `scripts/test-sound-build.sh` | Runs the unit tests and the recipe check; `--real` also builds everything from the real clips |
| `.github/workflows/build.yml` | One new step that runs the script |

**Recipe format.** A set file is `{"set", "title", "pitch_st", "entries": [...]}`; `_shared.json` is `{"set": "_shared", "entries": [...]}`. An entry is `{slot, source, start?, end?, gain_db?, pitch_st?, effects?, hp_hz?, mood, signature, note}`.

- `source` is `<slot folder>/<file name>` inside the candidates folder, or `synth:<recipe>`.
- `start` and `end` (seconds in the source clip) are optional; with neither, the build drops the silence and keeps the loudest window that fits the slot's maximum length.
- `gain_db` nudges the loudness target by up to +-1.5 dB; `pitch_st` adds to the set's `pitch_st` (the set's shift reaches only recorded clips of that set, never the shared entries or synths).
- `effects` is a list of `{"type": "wobble", "rate_hz", "depth_st"}`, `{"type": "glide", "from_st", "to_st"}` (a pitch ramp) and `{"type": "thump"}` (the tail thump of the rate slot).
- `hp_hz` overrides the 100 Hz high-pass (100 to 1500).
- `mood` and `signature` repeat the spec's table; the loader rejects an entry that disagrees with it.
- `note` records why the clip was chosen.

## Source choices (measured, not auditioned)

Nobody can listen while writing this plan, so every window below comes from measurement (energy envelopes in 50 ms frames, band energy above 1 kHz and 3 kHz, autocorrelation pitch tracks of the short clips), run on the 63 decoded previews. The owner's audition is the real test, and each choice is one line in a JSON file to change.

| Slot | Studio | Steff's cat | Kitten (+1.5 st) | Best of (-1 st) |
|---|---|---|---|---|
| greet | MBPL trill 3 | steff Twit1 | kitten22, first 0.42 s, +1 | steff Twit1, +3 |
| love | MBPL trill 1, 0.02-0.60 s, +2 | steff Happy Purr/Twitter2 | kitten22 | Mafon2 short purr |
| annoyed | Emi growl, 0.52-1.48 s | Sadiquecat food meow, 0-0.7 s, -2 | kitten13 | kitten13 |
| dizzy | MBPL trill 1, wobble | MBPL trill 1, wobble | kitten12, wobble | MBPL trill 1, wobble |
| slap | Emi #11, 0.03-0.27 s, -2 | steff Twit4 | kitten12, 0-0.3 s, -1 | steff Twit4, +3 |
| finish | MBPL trill 4 | steff catwhirr | kitten16, 0.05-0.65 s, rise | steff catwhirr |
| error | Emi #6, fall | Sadiquecat food meow, 0.55-1.18 s, fall | kitten20, fall | Breviceps, -3, fall |
| approval | Emi #2 | Sadiquecat Pearl | kitten10 | Emi #2 |
| question | MBPL trill 5, rise | steff Twit5, rise | kitten20, 0.1-0.6 s, rise | nathan-osman, -3, rise |
| proud | Emi #11, +3 | steff Twit6 | kitten10, 0-0.4 s, +2 | dreamstobecome chirp, 2.5-3.0 s |
| wink | Emi #6, 0.05-0.40 s, +3 | steff Meow2 | kitten13, 0.45-0.80 s, +2 | Mafon2 Cat Meow, -3 |
| sleep | Trautwein purr, 4.0-6.8 s | Sadiquecat snore, 1.2-2.6 s | Buddha Purr | Sadiquecat snore, 1.2-2.6 s |
| think | Emi #2, 0.10-0.75 s, -3 | MBPL trill 3, -3 | kitten16, 0.55-0.95 s, -2 | Sadiquecat MmRrm, 0.3-1.2 s |
| search | synth chatter | synth chatter | synth chatter | Hunting chatter, 12.85-13.75 s |
| rate | Emi #2, 0.3-0.9 s, -2, thump | Sadiquecat food meow, 0-0.6 s, thump | kitten17, thump | kitten17, thump |

Shared by all four (`_shared.json`): yawn (synth), work (synth), gulp (Sadiquecat paw licking, 0-0.9 s, high-passed at 1 kHz), and the ten ticks: approve (BenDrain cardboard stamp), peek (JoshuaPomeroy sleigh bell), open (newagesoup box flap, 0.22-0.62 s), close (Mafon2 item placed, 0.20-0.56 s), hover (Mafon2 water click), blip (synth, because the only recorded candidate is excluded), tick (Mafon2 ceramic click), send (jimmyfisher kibble), attach (synth clink), pop (jcallison mouth pop).

What the measurements said, and what the recipes do about it:

- **Question wants to rise and none of the clips does.** Pitch tracks: steff Twit5 falls 387 to 315 Hz, nathan-osman meow-1 falls about 1000 to 630 Hz, MBPL trill 5 sits flat near 1300 Hz. Every question entry therefore carries a rising `glide`. The error clips are flat (Emi #6 near 800 Hz, kitten20 near 520 Hz), so error entries carry a falling `glide`.
- **The 106 s yawn clip has no yawn to cut.** It is a steady purr; its band above 1 kHz stays at -50 dB or lower, with only a click about every 1.5 s between 73 and 82 s. No window isolates a yawn, so yawn is the spec's synth recipe in every set. If the owner finds a yawn by ear, set `start` and `end` on a `yawn/fs-383473-Daphne_in_Wonderland.mp3` entry in `_shared.json`.
- **The 7.8 s chirp** has chirps at 0.6 s (a loud frame at -24.7 dB with two small bits before it), 2.6 to 2.9 s (frames at -44, -35, -31 and -48 dB, the longest clean one), 4.9 to 5.3 s and 6.4 to 6.9 s. Best of takes 2.50 to 3.00 s.
- **The 66.8 s hunting clip** is dominated by low rumble (-15 dB) with chatter bursts above 1 kHz at 12.95, 13.35 and 13.65 s (-23 to -27 dB in that band). Best of takes 12.85 to 13.75 s, high-passed at 900 Hz so the loudness is the chatter, not the rumble.
- **Milk lapping (kyles) was tried for gulp and dropped.** Its laps are 0.15 s apart and spiky, so the limiter had to remove 10.5 dB. Sadiquecat's paw licking is continuous and needs 1.9 dB; above 1 kHz is where the licking is.
- **Sleep.** Sadiquecat's snore clip has one burst at 1.55 to 1.95 s (and one at 4.5 to 4.8 s) with quiet breath around it; 1.20 to 2.60 s holds the burst and its breath. Trautwein's studio purr is steady, so Studio takes 4.0 to 6.8 s; Studio uses it because Emi has no snore or purr (the one slot where Studio goes outside Emi and MBPL, as the brief allows).
- **Emi has four clips in the download** (little meows #2 and #6, meow #11, the growl), so Studio re-cuts them at different windows and pitches for its 15 slots, and takes the rest from MBPL's four trills. Downloading more of Emi's series (little meows #1 and #3 to #10) would give Studio distinct clips; that is a recipe edit.
- **Not used:** Begging Meow and Cute Computer Squeak (excluded); yahsay chirping (peak -27 dBFS, lossy); CatPhony (8 kHz); aunrea hissing; megrez purr loop; Tyler31898 chirps; ArcticWanderer kneading (purr and kneading together, so work is synthesised); the milk lapping; Adriena licking; the single bell; the box-lid, keys, kibble-bowl and squeaky-toy clips.
- **Limiter use.** In the dry run the deepest limiter reduction is 1.9 dB (gulp), all 112 files pass, and the report prints the limiter column so a squashed slot is visible.


---

### Task 1: DSP helpers

Small signal-processing functions on plain lists of floats at 48 kHz. Everything is deterministic. The peak limiter is here because peaky sounds (a pat, a lick, a short meow) cannot reach their loudness target before their peaks touch -1 dBTP; Task 2 uses it. Pitch shifting is resampling, so a clip's length changes by 2^(semitones/12), as the spec's Risks section accepts.

**Files:**
- Create: `tools/sounds/dsp.py`
- Create: `tests/test_sound_build.py` (the file every later task appends to)

**Interfaces:**
- Consumes: nothing.
- Produces (all in `dsp`): `SR = 48000`; `db_to_lin(db)`, `lin_to_db(x)`, `peak(x)`, `rms(x)`, `gain(x, db)`, `mix_at(base, layer, offset)`; filters `biquad(x, b0, b1, b2, a1, a2)`, `highpass(x, fc, sr=SR, q=0.7071)`, `lowpass(x, fc, sr=SR, q=0.7071)`, `bandpass(x, fc, q, sr=SR)`; `fade(x, in_ms=3.0, out_ms=20.0, sr=SR)` (first and last sample exactly 0); resampling `varispeed(x, ratio_at)`, `pitch_shift(x, semitones)`, `glide(x, st_from, st_to)`, `wobble(x, rate_hz=5.0, depth_st=1.0, sr=SR)`; trimming `seconds_slice(x, start=None, end=None, sr=SR)`, `frame_rms(x, frame)`, `trim_silence(x, sr=SR, floor_db=-35.0, pad_ms=5.0)`, `loudest_window(x, length, sr=SR)`, `auto_trim(x, max_len_s, sr=SR)`; `onset_index(x, rel_db=-24.0)`, `active_rms(x, sr=SR)`; `limit(x, ceiling_db, lookahead_ms=5.0, sr=SR)` (no sample ends above the ceiling; a signal already under it comes back unchanged).

- [ ] **Step 1: Write the failing tests**

**Create `tests/test_sound_build.py`**

```python
"""Tests for the sound-set build (sub-project C, stage 1): tools/sounds/.

Standard library only. Run: bash scripts/test-sound-build.sh
"""
import json
import math
import os
import random
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "sounds"))

import dsp  # noqa: E402

SR = dsp.SR
HAS_AFCONVERT = shutil.which("afconvert") is not None


def sine(freq, seconds, amp=0.5, phase=0.0):
    return [amp * math.sin(2 * math.pi * freq * i / SR + phase) for i in range(int(seconds * SR))]


def burst(freq=800.0, seconds=0.4, lead=0.05, tail=0.0, amp=0.3):
    """Silence, then a faded sine, then silence: a stand-in for a meow."""
    body = dsp.fade(sine(freq, seconds, amp))
    return [0.0] * int(lead * SR) + body + [0.0] * int(tail * SR)


def power(x, freq):
    """Goertzel: signal power at one frequency (about amp^2 / 4 for a sine of that frequency)."""
    w = 2 * math.pi * freq / SR
    c = 2 * math.cos(w)
    s1 = s2 = 0.0
    for v in x:
        s1, s2 = v + c * s1 - s2, s1
    return (s1 * s1 + s2 * s2 - c * s1 * s2) / (len(x) / 2.0) ** 2


def crossings(x):
    return sum(1 for a, b in zip(x, x[1:]) if (a < 0) != (b < 0))


def db(ratio):
    return 20 * math.log10(ratio)


class TestDsp(unittest.TestCase):
    def test_highpass_cuts_30hz_and_passes_1khz(self):
        low = dsp.highpass(sine(30, 1.0), 100)[SR // 2:]
        mid = dsp.highpass(sine(1000, 1.0), 100)[SR // 2:]
        self.assertLess(db(dsp.rms(low) / dsp.rms(sine(30, 0.5))), -15.0)
        self.assertAlmostEqual(db(dsp.rms(mid) / dsp.rms(sine(1000, 0.5))), 0.0, delta=0.5)

    def test_fades_start_and_end_at_zero(self):
        for n in (4800, 300, 3, 2):
            y = dsp.fade([0.8] * n)
            self.assertEqual(y[0], 0.0, n)
            self.assertEqual(y[-1], 0.0, n)
        self.assertEqual(dsp.fade([]), [])
        self.assertEqual(dsp.fade([0.7]), [0.0])

    def test_fade_lengths_are_3ms_in_and_20ms_out(self):
        y = dsp.fade([1.0] * SR)
        self.assertLess(y[100], 1.0)           # still inside the 144-sample fade-in
        self.assertEqual(y[200], 1.0)          # past it
        self.assertEqual(y[-1000], 1.0)        # just before the 960-sample fade-out
        self.assertLess(y[-500], 1.0)

    def test_pitch_shift_changes_length_and_pitch(self):
        x = sine(440, 1.0)
        up = dsp.pitch_shift(x, 12)
        self.assertAlmostEqual(len(up), len(x) / 2, delta=2)
        self.assertAlmostEqual(len(dsp.pitch_shift(x, -12)), len(x) * 2, delta=2)
        self.assertEqual(dsp.pitch_shift(x, 0), x)
        self.assertAlmostEqual(crossings(up) / (len(up) / SR), 2 * 440 * 2, delta=20)

    def test_glide_moves_the_pitch_across_the_clip(self):
        y = dsp.glide(sine(440, 1.0), 0.0, 12.0)
        q = len(y) // 4
        self.assertGreater(crossings(y[-q:]) / crossings(y[:q]), 1.5)

    def test_wobble_keeps_the_length_and_adds_motion(self):
        x = sine(440, 1.0)
        y = dsp.wobble(x, 5.0, 1.0)
        self.assertAlmostEqual(len(y), len(x), delta=len(x) * 0.02)
        self.assertNotEqual(y[:2000], x[:2000])

    def test_trim_silence_cuts_the_edges(self):
        x = [0.0] * SR + sine(500, 0.3) + [0.0] * SR
        y = dsp.trim_silence(x)
        self.assertAlmostEqual(len(y) / SR, 0.3, delta=0.03)

    def test_auto_trim_keeps_the_loudest_window(self):
        quiet, loud = sine(500, 0.5, 0.05), sine(500, 0.5, 0.5)
        x = quiet + [0.0] * (SR // 2) + loud
        y = dsp.auto_trim(x, 0.5)
        self.assertEqual(len(y), int(0.5 * SR))
        self.assertGreater(dsp.peak(y), 0.4)

    def test_onset_index_finds_the_first_transient(self):
        x = burst(lead=0.05)
        self.assertAlmostEqual(dsp.onset_index(x) / SR, 0.05, delta=0.004)

    def test_active_rms_ignores_the_silence_around_the_sound(self):
        x = burst(lead=0.5, tail=0.5)
        self.assertAlmostEqual(dsp.active_rms(x), dsp.rms(sine(800, 0.4, 0.3)), delta=0.01)

    def test_limit_caps_peaks_and_leaves_quiet_signals_alone(self):
        x = sine(300, 0.1, 0.3)
        x[2000:2010] = [2.0] * 10
        y = dsp.limit(x, -1.0)
        self.assertLessEqual(dsp.peak(y), dsp.db_to_lin(-1.0) + 1e-9)
        quiet = sine(300, 0.1, 0.3)
        self.assertEqual(dsp.limit(quiet, -1.0), quiet)
        self.assertEqual(y[100], x[100])        # far from the peak: untouched

    def test_mix_at_extends_and_adds(self):
        out = dsp.mix_at([1.0, 1.0], [0.5, 0.5, 0.5], 1)
        self.assertEqual(out, [1.0, 1.5, 0.5, 0.5])
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: FAIL, `ModuleNotFoundError: No module named 'dsp'`

- [ ] **Step 3: Write the implementation**

**Create `tools/sounds/dsp.py`**

```python
"""Small DSP helpers on plain Python lists of floats (mono, 48 kHz).

Standard library only. Everything here is deterministic: no clocks, no unseeded randomness.
"""
from __future__ import annotations

import math
from collections import deque

SR = 48000


def db_to_lin(db):
    return 10.0 ** (db / 20.0)


def lin_to_db(x):
    return 20.0 * math.log10(max(x, 1e-12))


def peak(x):
    return max((abs(v) for v in x), default=0.0)


def rms(x):
    if not x:
        return 0.0
    return math.sqrt(sum(v * v for v in x) / len(x))


def gain(x, db):
    g = db_to_lin(db)
    return [v * g for v in x]


def mix_at(base, layer, offset):
    """Sum `layer` into `base` starting at sample `offset`. Returns a new list."""
    n = max(len(base), offset + len(layer))
    out = list(base) + [0.0] * (n - len(base))
    for i, v in enumerate(layer):
        out[offset + i] += v
    return out


# --- filters -----------------------------------------------------------------------------

def biquad(x, b0, b1, b2, a1, a2):
    """Transposed direct form II. The a0 coefficient is already normalised to 1."""
    z1 = z2 = 0.0
    out = []
    for v in x:
        y = b0 * v + z1
        z1 = b1 * v - a1 * y + z2
        z2 = b2 * v - a2 * y
        out.append(y)
    return out


def _rbj(kind, fc, q, sr):
    w0 = 2.0 * math.pi * fc / sr
    cw, sw = math.cos(w0), math.sin(w0)
    alpha = sw / (2.0 * q)
    if kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    elif kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    else:  # "bp": constant 0 dB peak gain
        b0, b1, b2 = alpha, 0.0, -alpha
    a0 = 1 + alpha
    return b0 / a0, b1 / a0, b2 / a0, (-2 * cw) / a0, (1 - alpha) / a0


def highpass(x, fc, sr=SR, q=0.7071067811865476):
    return biquad(x, *_rbj("hp", fc, q, sr))


def lowpass(x, fc, sr=SR, q=0.7071067811865476):
    return biquad(x, *_rbj("lp", fc, q, sr))


def bandpass(x, fc, q, sr=SR):
    return biquad(x, *_rbj("bp", fc, q, sr))


# --- fades -------------------------------------------------------------------------------

def fade(x, in_ms=3.0, out_ms=20.0, sr=SR):
    """Half-cosine fades. The first and the last sample come out exactly 0."""
    n = len(x)
    if n < 2:
        return [0.0] * n
    n_in = min(int(round(in_ms * sr / 1000.0)), n // 2)
    n_out = min(int(round(out_ms * sr / 1000.0)), n - n_in)
    out = list(x)
    for i in range(n_in):
        out[i] *= 0.5 * (1.0 - math.cos(math.pi * i / n_in))
    for j in range(n_out):
        out[n - n_out + j] *= 0.5 * (1.0 + math.cos(math.pi * j / max(n_out - 1, 1)))
    out[0] = 0.0
    out[-1] = 0.0
    return out


# --- resampling: pitch shift, glide, wobble ---------------------------------------------

def _cubic(x, pos, last):
    i = int(pos)
    t = pos - i
    p0 = x[i - 1] if i > 0 else x[0]
    p1 = x[i]
    p2 = x[i + 1] if i + 1 <= last else x[last]
    p3 = x[i + 2] if i + 2 <= last else x[last]
    return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                  + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t)


def varispeed(x, ratio_at):
    """Read `x` at a varying speed. `ratio_at(j, progress)` gives the read-speed ratio for output
    sample j, where progress is the read position as a fraction of the input (0..1).
    Ratio 2 reads twice as fast: one octave up, half as long."""
    n = len(x)
    if n < 2:
        return list(x)
    last = n - 1
    out = []
    pos = 0.0
    j = 0
    while pos <= last:
        out.append(_cubic(x, pos, last))
        pos += ratio_at(j, pos / last)
        j += 1
    return out


def pitch_shift(x, semitones):
    """Pitch shift by resampling (the length changes by 2^(st/12))."""
    if semitones == 0:
        return list(x)
    r = 2.0 ** (semitones / 12.0)
    return varispeed(x, lambda j, p: r)


def glide(x, st_from, st_to):
    """Pitch ramp: the pitch offset moves linearly from st_from to st_to over the clip."""
    def ratio(j, p):
        return 2.0 ** ((st_from + (st_to - st_from) * p) / 12.0)
    return varispeed(x, ratio)


def wobble(x, rate_hz=5.0, depth_st=1.0, sr=SR):
    """Vibrato: the pitch swings +-depth_st semitones, rate_hz times a second."""
    w = 2.0 * math.pi * rate_hz / sr

    def ratio(j, p):
        return 2.0 ** (depth_st * math.sin(w * j) / 12.0)
    return varispeed(x, ratio)


# --- trimming and onsets -----------------------------------------------------------------

def seconds_slice(x, start=None, end=None, sr=SR):
    a = 0 if start is None else max(0, int(round(start * sr)))
    b = len(x) if end is None else min(len(x), int(round(end * sr)))
    return list(x[a:b]) if b > a else []


def frame_rms(x, frame):
    return [rms(x[i:i + frame]) for i in range(0, len(x), frame)]


def trim_silence(x, sr=SR, floor_db=-35.0, pad_ms=5.0):
    """Cut leading and trailing frames more than |floor_db| below the loudest 10 ms frame."""
    frame = int(sr * 0.010)
    env = frame_rms(x, frame)
    if not env or max(env) == 0.0:
        return list(x)
    thr = max(env) * db_to_lin(floor_db)
    idx = [i for i, e in enumerate(env) if e >= thr]
    pad = int(sr * pad_ms / 1000.0)
    a = max(0, idx[0] * frame - pad)
    b = min(len(x), (idx[-1] + 1) * frame + pad)
    return list(x[a:b])


def loudest_window(x, length, sr=SR):
    """The `length`-sample window with the most energy, searched in 10 ms steps."""
    if len(x) <= length:
        return list(x)
    cs = [0.0]
    for v in x:
        cs.append(cs[-1] + v * v)
    step = int(sr * 0.010)
    best_i, best_e = 0, -1.0
    for i in range(0, len(x) - length + 1, step):
        e = cs[i + length] - cs[i]
        if e > best_e:
            best_i, best_e = i, e
    return list(x[best_i:best_i + length])


def auto_trim(x, max_len_s, sr=SR):
    """No explicit trim: drop the silence, then keep the loudest window of at most max_len_s."""
    return loudest_window(trim_silence(x, sr), int(max_len_s * sr), sr)


def onset_index(x, rel_db=-24.0):
    """Index of the first sample within |rel_db| of the clip's peak: the first transient."""
    p = peak(x)
    if p == 0.0:
        return 0
    thr = p * db_to_lin(rel_db)
    for i, v in enumerate(x):
        if abs(v) >= thr:
            return i
    return 0


def active_rms(x, sr=SR):
    """RMS over the 10 ms frames within 20 dB of the loudest frame: the level of the sound itself,
    not of the silence around it."""
    frame = int(sr * 0.010)
    env = frame_rms(x, frame)
    if not env or max(env) == 0.0:
        return 0.0
    thr = max(env) * db_to_lin(-20.0)
    energy, count = 0.0, 0
    for i, e in enumerate(env):
        if e >= thr:
            seg = x[i * frame:(i + 1) * frame]
            energy += sum(v * v for v in seg)
            count += len(seg)
    return math.sqrt(energy / count)


# --- peak limiter ------------------------------------------------------------------------

def limit(x, ceiling_db, lookahead_ms=5.0, sr=SR):
    """Look-ahead limiter: no sample ends above `ceiling_db`. The gain starts to fall one look-ahead
    before a peak and comes back over one look-ahead after it. Untouched when nothing is over."""
    c = db_to_lin(ceiling_db)
    n = len(x)
    if n == 0 or peak(x) <= c:
        return list(x)
    la = max(1, int(round(lookahead_ms * sr / 1000.0)))
    need = [c / abs(v) if abs(v) > c else 1.0 for v in x]
    # m[j] = min(need[j .. j+la]), by a monotonic queue
    q, m = deque(), [1.0] * n
    for j in range(n - 1, -1, -1):
        while q and need[q[-1]] >= need[j]:
            q.pop()
        q.append(j)
        while q[0] > j + la:
            q.popleft()
        m[j] = need[q[0]]
    # g[i] = mean(m[i-la .. i]); each of those windows contains i, so g[i] <= need[i]
    out, acc = [], 0.0
    for i in range(n):
        acc += m[i]
        if i > la:
            acc -= m[i - la - 1]
        out.append(x[i] * (acc / min(i + 1, la + 1)))
    return out
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 12 tests`, `OK`

- [ ] **Step 5: Commit**

```bash
git add tools/sounds/dsp.py tests/test_sound_build.py
git commit -m "feat(sounds): DSP helpers for the sound-set build" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 2: Loudness measurement and normalisation

BS.1770 K-weighting at 48 kHz (the standard's own coefficients), short-term loudness as the loudest 400 ms block (a clip under 400 ms is zero-padded to one block, so a short sound is measured the way it sits in the mix), RMS, and an approximate true peak by 4x oversampling (Lanczos kernels; only the neighbourhoods of samples within 6 dB of the peak are interpolated, since nothing else can top it). `normalize` gains a clip to a target, limiting peaks and raising the gain again to make up the loudness the limiter took, until loudness and true peak both settle (six rounds at most).

**Files:**
- Create: `tools/sounds/loudness.py`
- Modify: `tests/test_sound_build.py` (append)

**Interfaces:**
- Consumes (`dsp`): `SR`, `biquad`, `gain`, `limit`, `lin_to_db`, `peak`, `rms`.
- Produces (`loudness`): `Measurement(lufs, rms_db, tp_db, peak_db, seconds)`; `Norm(gain_db, limit_db)`; `SILENT_LUFS = -120.0`; `k_weight(x)`; `short_term_lufs(x, sr=SR)` (raises `ValueError` unless `sr == 48000`); `rms_dbfs(x)`; `true_peak_dbtp(x, sr=SR)` (never below the sample peak); `measure(x, sr=SR) -> Measurement`; `normalize(x, target_lufs, ceiling_dbtp=-1.0, sr=SR) -> (samples, Norm)` where `limit_db` is the deepest gain reduction the limiter applied (silence comes back untouched with `Norm(0.0, 0.0)`).

- [ ] **Step 1: Write the failing tests** (they include Review Focus 5: very quiet and very loud clips)

**Append to `tests/test_sound_build.py`**

```python
import loudness  # noqa: E402


class TestLoudness(unittest.TestCase):
    def test_a_1khz_sine_measures_its_level(self):
        # K-weighting adds about +0.7 dB at 1 kHz and the standard's -0.691 offset takes it back
        # out, so LUFS is the sine's RMS level: its peak level minus 3.01 dB.
        for peak_db in (-10.0, -23.0, -40.0):
            x = sine(1000, 1.0, dsp.db_to_lin(peak_db))
            self.assertAlmostEqual(loudness.short_term_lufs(x), peak_db - 3.01, delta=0.5)

    def test_6_db_more_gain_is_6_lu_more(self):
        x = sine(700, 0.6, 0.1)
        a, b = loudness.short_term_lufs(x), loudness.short_term_lufs(dsp.gain(x, 6.0))
        self.assertAlmostEqual(b - a, 6.0, delta=0.05)

    def test_a_clip_shorter_than_400ms_is_padded_not_stretched(self):
        full = loudness.short_term_lufs(sine(1000, 0.6, 0.2))
        half = loudness.short_term_lufs(sine(1000, 0.2, 0.2))      # 200 ms of 400 ms
        self.assertAlmostEqual(full - half, 3.01, delta=0.5)

    def test_short_term_is_the_loudest_block(self):
        x = sine(1000, 1.0, 0.01) + sine(1000, 0.5, 0.5)
        self.assertAlmostEqual(loudness.short_term_lufs(x), loudness.short_term_lufs(sine(1000, 0.5, 0.5)),
                               delta=0.2)

    def test_silence_and_a_wrong_sample_rate(self):
        self.assertEqual(loudness.short_term_lufs([0.0] * 4800), loudness.SILENT_LUFS)
        self.assertEqual(loudness.short_term_lufs([]), loudness.SILENT_LUFS)
        with self.assertRaises(ValueError):
            loudness.short_term_lufs(sine(1000, 0.5), sr=44100)

    def test_true_peak_is_never_below_the_sample_peak(self):
        rng = random.Random(7)
        for amp in (0.1, 0.5, 0.9):
            x = [amp * (rng.random() * 2 - 1) for _ in range(4000)]
            self.assertGreaterEqual(loudness.true_peak_dbtp(x), dsp.lin_to_db(dsp.peak(x)))

    def test_true_peak_finds_the_peak_between_samples(self):
        # a sine at a quarter of the sample rate, 45 degrees in: every sample is +-0.707, the wave peaks at 1.0
        x = [math.sin(math.pi * n / 2 + math.pi / 4) for n in range(4800)]
        self.assertAlmostEqual(dsp.lin_to_db(dsp.peak(x)), -3.01, delta=0.01)
        self.assertAlmostEqual(loudness.true_peak_dbtp(x), 0.0, delta=0.3)

    def test_normalize_hits_the_target_under_the_ceiling(self):
        y, n = loudness.normalize(sine(1000, 0.5, 0.01), -20.0)
        self.assertAlmostEqual(loudness.short_term_lufs(y), -20.0, delta=0.1)
        self.assertLessEqual(loudness.true_peak_dbtp(y), -1.0 + 0.05)
        self.assertEqual(n.limit_db, 0.0)

    def test_normalize_limits_a_peaky_sound_and_still_reaches_the_target(self):
        # a decaying 300 Hz knock every 250 ms: far more peak than loudness
        x = [0.0] * SR
        for k in range(0, SR, SR // 4):
            for i in range(2400):
                x[k + i] = 0.5 * math.exp(-i / SR / 0.015) * math.sin(2 * math.pi * 300 * i / SR)
        y, n = loudness.normalize(x, -16.0)
        self.assertGreater(n.limit_db, 3.0)
        self.assertLessEqual(loudness.true_peak_dbtp(y), -1.0 + 0.05)
        self.assertAlmostEqual(loudness.short_term_lufs(y), -16.0, delta=0.5)

    def test_normalize_handles_very_quiet_and_very_loud_clips(self):
        quiet, _ = loudness.normalize(sine(500, 0.5, 0.001), -20.0)       # -60 dBFS
        loud, _ = loudness.normalize([0.99 if (i // 50) % 2 else -0.99 for i in range(SR // 2)], -20.0)
        for y in (quiet, loud):
            self.assertAlmostEqual(loudness.short_term_lufs(y), -20.0, delta=1.5)
            self.assertLessEqual(loudness.true_peak_dbtp(y), -1.0 + 0.05)

    def test_normalize_leaves_silence_alone(self):
        y, n = loudness.normalize([0.0] * 1000, -20.0)
        self.assertEqual(y, [0.0] * 1000)
        self.assertEqual(n.gain_db, 0.0)
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: FAIL, `ModuleNotFoundError: No module named 'loudness'`

- [ ] **Step 3: Write the implementation**

**Create `tools/sounds/loudness.py`**

```python
"""Loudness measurement: ITU-R BS.1770 K-weighting, short-term loudness, true peak, RMS.

Standard library only. The K-weighting coefficients are the ones the standard gives for 48 kHz,
so every measurement here works on 48 kHz audio only.
"""
from __future__ import annotations

import math
from collections import namedtuple

from dsp import SR, biquad, gain, limit, lin_to_db, peak, rms

# BS.1770-4, 48 kHz: stage 1 is the high shelf, stage 2 the RLB high-pass.
_K1 = (1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585)
_K2 = (1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621)

BLOCK = int(SR * 0.400)   # 400 ms measurement block
HOP = int(SR * 0.100)     # 75 % overlap
SILENT_LUFS = -120.0

Measurement = namedtuple("Measurement", "lufs rms_db tp_db peak_db seconds")
Norm = namedtuple("Norm", "gain_db limit_db")


def k_weight(x):
    return biquad(biquad(x, *_K1), *_K2)


def short_term_lufs(x, sr=SR):
    """Loudest 400 ms block, in LUFS (no gating). A clip shorter than 400 ms is zero-padded to one
    block, so a short sound is measured the way it will sit in the mix, not stretched to fill it."""
    if sr != SR:
        raise ValueError("loudness is only defined here for 48 kHz audio")
    if not x:
        return SILENT_LUFS
    w = k_weight(x)
    cs = [0.0]
    for v in w:
        cs.append(cs[-1] + v * v)
    n = len(w)
    last = max(n - BLOCK, 0)
    starts = list(range(0, last + 1, HOP))
    if starts[-1] != last:
        starts.append(last)
    best = 0.0
    for s in starts:
        e = cs[min(s + BLOCK, n)] - cs[s]
        best = max(best, e / BLOCK)
    if best <= 0.0:
        return SILENT_LUFS
    return -0.691 + 10.0 * math.log10(best)


def rms_dbfs(x):
    return lin_to_db(rms(x))


def _sinc(t):
    if t == 0.0:
        return 1.0
    return math.sin(math.pi * t) / (math.pi * t)


_L = 12
# Lanczos kernels for the three in-between points of a 4x oversample, taps for x[i-L+1 .. i+L]
_KERNELS = [[_sinc(k - f) * _sinc((k - f) / _L) for k in range(-_L + 1, _L + 1)]
            for f in (0.25, 0.5, 0.75)]


def true_peak_dbtp(x, sr=SR):
    """Approximate true peak by 4x oversampling (BS.1770 Annex 2 style). Only the neighbourhoods of
    samples within 6 dB of the peak are interpolated: elsewhere no in-between value can top it.
    Never lower than the sample peak."""
    p = peak(x)
    if p == 0.0:
        return lin_to_db(0.0)
    n = len(x)
    thr = p * 0.5
    best = p
    for i, v in enumerate(x):
        if abs(v) < thr:
            continue
        for base in (i - 1, i):
            if base < 0 or base >= n - 1:
                continue
            for taps in _KERNELS:
                acc = 0.0
                for k, h in enumerate(taps):
                    idx = base - _L + 1 + k
                    if 0 <= idx < n:
                        acc += x[idx] * h
                a = abs(acc)
                if a > best:
                    best = a
    return lin_to_db(best)


def measure(x, sr=SR):
    return Measurement(short_term_lufs(x, sr), rms_dbfs(x), true_peak_dbtp(x, sr),
                       lin_to_db(peak(x)), len(x) / float(sr))


def normalize(x, target_lufs, ceiling_dbtp=-1.0, sr=SR):
    """Gain `x` to `target_lufs` short-term loudness with its true peak at or under `ceiling_dbtp`.

    Peaky sounds (a pat, a click, a short meow) cannot reach the target before their peaks hit the
    ceiling, so a look-ahead limiter takes the peaks down and the gain goes up again to make up the
    loudness the limiter removed. If the limited signal still overshoots between samples, the
    limiter's own ceiling comes down by the overshoot. A few rounds settle both. Returns
    (samples, Norm(gain_db, limit_db)), limit_db being the deepest gain reduction the limiter
    applied. Silence comes back untouched."""
    lufs = short_term_lufs(x, sr)
    if lufs <= SILENT_LUFS:
        return list(x), Norm(0.0, 0.0)
    g = target_lufs - lufs
    head = ceiling_dbtp - 0.5            # the limiter's sample-peak ceiling
    for _ in range(6):
        hot = gain(x, g)
        y = limit(hot, head)
        tp = true_peak_dbtp(y, sr)
        if tp > ceiling_dbtp + 0.01:
            head -= tp - ceiling_dbtp
            continue
        short = target_lufs - short_term_lufs(y, sr)
        if short < 0.1:
            break
        g += short
    limited = max(lin_to_db(peak(hot)) - lin_to_db(peak(y)), 0.0)
    if tp > ceiling_dbtp:                # settled badly: fall back to plain gain reduction
        y = gain(y, ceiling_dbtp - tp)
        g += ceiling_dbtp - tp
    return y, Norm(g, limited)
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 23 tests`, `OK`

- [ ] **Step 5: Commit**

```bash
git add tools/sounds/loudness.py tests/test_sound_build.py
git commit -m "feat(sounds): BS.1770 loudness, true peak and normalisation" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 3: WAV input and output, and clip decoding

`write_wav16` writes mono 16-bit PCM (the `wave` module writes no timestamps, so equal samples give equal bytes). `read_wav` reads 16- or 32-bit PCM and averages any channel count to mono. `decode_clip` runs `afconvert -f WAVE -d LEI32@48000`, which decodes MP3 and friends and resamples to 48 kHz while keeping the channels; the mono downmix is ours. `AfconvertLoader` decodes on demand and keeps the result for the run. Tests use temporary folders with a space in the name.

**Files:**
- Create: `tools/sounds/audio_io.py`
- Modify: `tests/test_sound_build.py` (append)

**Interfaces:**
- Consumes (`dsp`): `SR`.
- Produces (`audio_io`): `write_wav16(path, x, sr=SR)`; `read_wav(path) -> (array('d'), rate)`; `decode_clip(path) -> array('d')` (48 kHz mono, needs afconvert); `AfconvertLoader(candidates_dir)` with `.load(source) -> array('d')`, where `source` is `'<folder>/<file>'` under the candidates folder; raises `FileNotFoundError` for a missing clip and returns the same object on a second load.

- [ ] **Step 1: Write the failing tests**

**Append to `tests/test_sound_build.py`**

```python
import audio_io  # noqa: E402


def write_pcm16(path, samples, rate, channels=1):
    """A test WAV written without audio_io, so reading can be tested on its own."""
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<%dh" % len(samples), *samples))


class TestAudioIo(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm sound test ")      # a space in the path, as in the repo's own
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def path(self, name):
        return os.path.join(self.tmp, name)

    def test_write_then_read_is_within_one_step(self):
        x = sine(440, 0.1, 0.7)
        audio_io.write_wav16(self.path("a.wav"), x)
        y, rate = audio_io.read_wav(self.path("a.wav"))
        self.assertEqual(rate, SR)
        self.assertEqual(len(y), len(x))
        self.assertLessEqual(max(abs(a - b) for a, b in zip(x, y)), 1.0 / 32768)

    def test_the_file_is_mono_16_bit_48k(self):
        audio_io.write_wav16(self.path("a.wav"), sine(440, 0.05))
        with wave.open(self.path("a.wav"), "rb") as w:
            self.assertEqual((w.getnchannels(), w.getsampwidth(), w.getframerate()), (1, 2, 48000))

    def test_over_range_samples_clamp_instead_of_wrapping(self):
        audio_io.write_wav16(self.path("a.wav"), [1.5, -1.5, 0.0])
        y, _ = audio_io.read_wav(self.path("a.wav"))
        self.assertGreater(y[0], 0.99)
        self.assertLess(y[1], -0.99)

    def test_equal_samples_give_equal_bytes(self):
        x = sine(440, 0.05)
        audio_io.write_wav16(self.path("a.wav"), x)
        audio_io.write_wav16(self.path("b.wav"), list(x))
        with open(self.path("a.wav"), "rb") as a, open(self.path("b.wav"), "rb") as b:
            self.assertEqual(a.read(), b.read())

    def test_stereo_is_averaged_to_mono(self):
        write_pcm16(self.path("s.wav"), [16384, 0, 16384, 0, -16384, 0], SR, channels=2)
        y, _ = audio_io.read_wav(self.path("s.wav"))
        self.assertEqual([round(v, 3) for v in y], [0.25, 0.25, -0.25])

    @unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
    def test_decode_clip_resamples_to_48k_mono(self):
        src = [int(12000 * math.sin(2 * math.pi * 500 * i / 44100)) for i in range(44100)]
        interleaved = [v for s in src for v in (s, s)]
        write_pcm16(self.path("clip.wav"), interleaved, 44100, channels=2)
        y = audio_io.decode_clip(self.path("clip.wav"))
        self.assertAlmostEqual(len(y) / SR, 1.0, delta=0.01)
        self.assertAlmostEqual(dsp.peak(y), 12000 / 32768.0, delta=0.02)

    @unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
    def test_the_loader_finds_clips_by_folder_and_name_and_reports_a_missing_one(self):
        os.makedirs(self.path("greet"))
        write_pcm16(self.path("greet/a.wav"), [0, 1000, -1000, 0] * 100, SR)
        loader = audio_io.AfconvertLoader(self.tmp)
        self.assertEqual(len(loader.load("greet/a.wav")), 400)
        self.assertIs(loader.load("greet/a.wav"), loader.load("greet/a.wav"))
        with self.assertRaises(FileNotFoundError):
            loader.load("greet/missing.wav")
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: FAIL, `ModuleNotFoundError: No module named 'audio_io'`

- [ ] **Step 3: Write the implementation**

**Create `tools/sounds/audio_io.py`**

```python
"""WAV reading and writing, and decoding of the candidate clips with macOS afconvert."""
from __future__ import annotations

import os
import struct
import subprocess
import tempfile
import wave
from array import array

from dsp import SR


def write_wav16(path, x, sr=SR):
    """Write mono 16-bit PCM. Samples are rounded to the nearest step and clamped; the wave module
    writes no timestamps, so equal samples always give equal bytes."""
    ints = []
    for v in x:
        i = int(v * 32768.0 + 0.5) if v >= 0 else -int(-v * 32768.0 + 0.5)
        ints.append(32767 if i > 32767 else (-32768 if i < -32768 else i))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(struct.pack("<%dh" % len(ints), *ints))


def read_wav(path):
    """Read 16-bit or 32-bit PCM, any channel count (averaged to mono). Returns (samples, rate)."""
    with wave.open(str(path), "rb") as w:
        ch, width, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width == 2:
        ints, scale = struct.unpack("<%dh" % (n * ch), raw), 32768.0
    elif width == 4:
        ints, scale = struct.unpack("<%di" % (n * ch), raw), 2147483648.0
    else:
        raise ValueError("%s: only 16-bit and 32-bit PCM are supported" % path)
    if ch == 1:
        return array("d", [v / scale for v in ints]), sr
    mono = array("d", [sum(ints[i:i + ch]) / (ch * scale) for i in range(0, len(ints), ch)])
    return mono, sr


def decode_clip(path):
    """Decode any clip afconvert can read to 48 kHz, as a mono array('d'). The sample-rate
    conversion is afconvert's; the mono downmix (channel average) is ours."""
    with tempfile.TemporaryDirectory(prefix="nm-sound-") as tmp:
        out = os.path.join(tmp, "decoded.wav")
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI32@%d" % SR, str(path), out],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        x, sr = read_wav(out)
    if sr != SR:
        raise ValueError("%s decoded at %d Hz, expected %d" % (path, sr, SR))
    return x


class AfconvertLoader:
    """Decodes candidate clips on demand and keeps them for the run. `source` is
    '<folder>/<file>' under the candidates directory."""

    def __init__(self, candidates_dir):
        self.root = str(candidates_dir)
        self._cache = {}

    def load(self, source):
        if source not in self._cache:
            path = os.path.join(self.root, *source.split("/"))
            if not os.path.isfile(path):
                raise FileNotFoundError("candidate clip not found: %s" % path)
            self._cache[source] = decode_clip(path)
        return self._cache[source]
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 30 tests`, `OK` (the two afconvert tests are skipped on a machine without afconvert)

- [ ] **Step 5: Commit**

```bash
git add tools/sounds/audio_io.py tests/test_sound_build.py
git commit -m "feat(sounds): WAV io and afconvert clip decoding" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 4: Gap recipes made in code

The sounds the recordings cannot give: `blip` (a small rising bloop, because the one recorded blip is excluded), `clink` (collar-tag: two inharmonic partials at 3.18 and 5.29 kHz, decay about 150 ms), `yawn` (a squeak falling from 1.2 kHz to 500 Hz over breathy noise, 0.8 s), `work` (three soft fabric pats 0.5 s apart, 1.3 s), `search` (a 620 Hz pulse train through two formant resonators, gated at 12 Hz, 0.9 s). Noise comes from `random.Random` with a fixed seed and only `.random()`, so it never changes between runs or Python versions. The build normalises the level afterwards.

**Files:**
- Create: `tools/sounds/synth.py`
- Modify: `tests/test_sound_build.py` (append)

**Interfaces:**
- Consumes (`dsp`): `SR`, `bandpass`, `lowpass`.
- Produces (`synth`): `blip()`, `clink()`, `yawn()`, `work()`, `search()`, each returning a list of floats at 48 kHz (0.1, 0.25, 0.8, 1.3 and 0.9 s long); `GAPS = {"blip": blip, "clink": clink, "yawn": yawn, "work": work, "search": search}`.

- [ ] **Step 1: Write the failing tests**

**Append to `tests/test_sound_build.py`**

```python
import synth  # noqa: E402


class TestSynth(unittest.TestCase):
    def test_every_recipe_is_deterministic_finite_and_audible(self):
        for name, make in synth.GAPS.items():
            a, b = make(), make()
            self.assertEqual(a, b, name)
            self.assertTrue(all(math.isfinite(v) for v in a), name)
            self.assertGreater(dsp.peak(a), 0.01, name)

    def test_lengths(self):
        want = {"blip": 0.1, "clink": 0.25, "yawn": 0.8, "work": 1.3, "search": 0.9}
        for name, seconds in want.items():
            self.assertAlmostEqual(len(synth.GAPS[name]()) / SR, seconds, delta=0.005, msg=name)

    def test_the_clink_rings_at_two_inharmonic_partials(self):
        x = synth.clink()
        for freq in (3180.0, 5290.0):
            self.assertGreater(power(x, freq), 20 * power(x, freq * 0.8), freq)
        self.assertNotAlmostEqual(5290.0 / 3180.0, round(5290.0 / 3180.0), delta=0.1)

    def test_the_yawn_falls_from_1200_hz_toward_500_hz(self):
        x = synth.yawn()
        early, late = x[int(0.15 * SR):int(0.30 * SR)], x[int(0.65 * SR):int(0.80 * SR)]
        self.assertGreater(power(early, 900.0), 10 * power(early, 550.0))
        self.assertGreater(power(late, 550.0), 10 * power(late, 900.0))

    def test_the_blip_rises(self):
        x = synth.blip()
        self.assertGreater(crossings(x[len(x) // 2:]), crossings(x[:len(x) // 2]) * 0.95)
        self.assertGreater(power(x[-1200:], 1700.0), power(x[-1200:], 1250.0))

    def test_work_is_three_pats_half_a_second_apart(self):
        x = synth.work()
        frame = int(0.020 * SR)
        env = [dsp.rms(x[i:i + frame]) for i in range(0, len(x), frame)]
        loud = [i for i, e in enumerate(env) if e > 0.3 * max(env)]
        starts = [i for k, i in enumerate(loud) if k == 0 or i - loud[k - 1] > 5]
        self.assertEqual(len(starts), 3)
        self.assertAlmostEqual((starts[1] - starts[0]) * 0.020, 0.5, delta=0.06)

    def test_search_is_a_12_hz_chatter(self):
        x = synth.search()
        frame = int(0.010 * SR)
        env = [dsp.rms(x[i:i + frame]) for i in range(0, len(x), frame)]
        top = max(env)
        peaks = [i for i in range(1, len(env) - 1)
                 if env[i] > 0.4 * top and env[i] >= env[i - 1] and env[i] > env[i + 1]]
        self.assertGreaterEqual(len(peaks), 8)
        self.assertLessEqual(len(peaks), 13)
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: FAIL, `ModuleNotFoundError: No module named 'synth'`

- [ ] **Step 3: Write the implementation**

**Create `tools/sounds/synth.py`**

```python
"""Made-in-code sounds that fill the gaps in the recordings (spec section 2, "Gap recipes").

Every recipe returns a list of floats at 48 kHz, about 0.5 of full scale; the build normalises the
level afterwards. Noise comes from random.Random with a fixed seed, so the output never changes.
"""
from __future__ import annotations

import math
import random

from dsp import SR, bandpass, lowpass


def _n(seconds):
    return int(round(seconds * SR))


def _noise(rng, count):
    return [rng.random() * 2.0 - 1.0 for _ in range(count)]


def _smooth(t, a, b):
    """0 before a, 1 after b, a raised-cosine ramp between."""
    if t <= a:
        return 0.0
    if t >= b:
        return 1.0
    return 0.5 * (1.0 - math.cos(math.pi * (t - a) / (b - a)))


def blip():
    """A small rising 'bloop' for the interface blip. 0.1 s."""
    out, phase = [], 0.0
    for i in range(_n(0.100)):
        t = i / SR
        f = 1250.0 + 450.0 * (t / 0.100)
        phase += 2.0 * math.pi * f / SR
        env = _smooth(t, 0.0, 0.003) * math.exp(-t / 0.030)
        out.append(0.5 * env * (math.sin(phase) + 0.25 * math.sin(2.0 * phase)))
    return out


def clink():
    """Collar-tag clink: two inharmonic partials at 3.2 and 5.3 kHz, decay about 150 ms, plus a
    2 ms click. 0.25 s."""
    rng = random.Random(1201)
    out = []
    for i in range(_n(0.250)):
        t = i / SR
        a = math.exp(-t / 0.045) * math.sin(2.0 * math.pi * 3180.0 * t)
        b = 0.6 * math.exp(-t / 0.028) * math.sin(2.0 * math.pi * 5290.0 * t + 0.7)
        click = 0.5 * (rng.random() * 2.0 - 1.0) * math.exp(-t / 0.0008)
        out.append(0.4 * (a + b + click))
    return out


def yawn():
    """A falling squeak (1.2 kHz down to 500 Hz) over breathy noise. 0.8 s."""
    rng = random.Random(1202)
    total = _n(0.800)
    noise = bandpass(_noise(rng, total), 2600.0, 0.7)
    out, phase = [], 0.0
    for i in range(total):
        t = i / SR
        f = 1200.0 * (500.0 / 1200.0) ** (t / 0.800)
        phase += 2.0 * math.pi * f / SR
        tone_env = _smooth(t, 0.10, 0.32) * (1.0 - _smooth(t, 0.45, 0.80))
        tone = tone_env * (math.sin(phase) + 0.4 * math.sin(2.0 * phase) + 0.15 * math.sin(3.0 * phase))
        breath_env = _smooth(t, 0.0, 0.35) * (1.0 - _smooth(t, 0.40, 0.80))
        out.append(0.35 * tone + 0.5 * breath_env * noise[i])
    return out


def work():
    """Kneading: three soft fabric pats, 0.5 s apart (2 Hz), alternating a darker and a brighter
    pat (the stereo left and right of the recipe, folded to mono). 1.3 s."""
    rng = random.Random(1203)
    total = _n(1.300)
    out = [0.0] * total
    for k, (start, length, cutoff, level) in enumerate(
            [(0.05, 0.080, 500.0, 1.0), (0.55, 0.060, 800.0, 0.8), (1.05, 0.080, 500.0, 1.0)]):
        n = _n(length)
        burst = lowpass(_noise(rng, n), cutoff, SR, 0.7)
        a = _n(start)
        for i in range(n):
            t = i / SR
            env = _smooth(t, 0.0, 0.006) * (1.0 - _smooth(t, length * 0.4, length))
            out[a + i] += level * env * burst[i]
    return out


def search():
    """A chatter: a 620 Hz pulse train through two formant resonators, gated at 12 Hz (a click
    train with a throat). 0.9 s."""
    rng = random.Random(1204)
    total = _n(0.900)
    carrier = [0.0] * total
    step = SR / 620.0
    pos = 0.0
    while int(pos) < total:
        carrier[int(pos)] = 0.8 + 0.2 * rng.random()
        pos += step
    low = bandpass(carrier, 1100.0, 3.5)
    high = bandpass(carrier, 2700.0, 4.0)
    out = []
    for i in range(total):
        t = i / SR
        phase = (t * 12.0) % 1.0                      # position inside one 83 ms chirp
        gate = math.sin(math.pi * phase / 0.4) ** 2 if phase < 0.4 else 0.0
        env = _smooth(t, 0.0, 0.06) * (1.0 - _smooth(t, 0.70, 0.90))
        out.append(4.0 * gate * env * (low[i] + 0.7 * high[i]))
    return out


GAPS = {"blip": blip, "clink": clink, "yawn": yawn, "work": work, "search": search}
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 37 tests`, `OK`

- [ ] **Step 5: Commit**

```bash
git add tools/sounds/synth.py tests/test_sound_build.py
git commit -m "feat(sounds): gap recipes made in code" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 5: The touch, the signature and the tail thump

The two layers of spec section 3, plus the thump of the rate slot. Layers are scaled against the vocal's *active* RMS (the 10 ms frames within 20 dB of its loudest) and never against each other. The touch is placed on the vocal's first transient, the signature at 60 % of the vocal's length (rising: its three partials enter 40 ms apart, each higher than the last; `dark=True` is the error version, an octave lower and slower), the thump 20 ms before the vocal ends.

**Files:**
- Create: `tools/sounds/layers.py`
- Modify: `tests/test_sound_build.py` (append)

**Interfaces:**
- Consumes (`dsp`): `SR`, `active_rms`, `db_to_lin`, `lowpass`, `mix_at`, `onset_index`, `rms`.
- Produces (`layers`): `MOODS = ("happy", "attention", "upset", "calm")`; `TOUCH_DB = -18.0`; `SIGNATURE_DB = -10.0`; `SIGNATURE_START = 0.60`; `touch(mood)` (a layer of 60 to 110 ms, `ValueError` for an unknown mood); `signature(dark=False)` (0.2 s); `thump()` (0.16 s); `scaled(layer, vocal, rel_db)`; `touch_layer(vocal, mood) -> (offset, samples)`; `signature_layer(vocal, dark=False) -> (offset, samples)`; `thump_layer(vocal) -> (offset, samples)`; `add_layers(vocal, mood, with_signature=False, dark=False, with_thump=False) -> list` (always adds the touch; may run past the vocal's end).

- [ ] **Step 1: Write the failing tests**

**Append to `tests/test_sound_build.py`**

```python
import layers  # noqa: E402


def level(layer, vocal):
    """The layer's RMS relative to the vocal's active RMS, in dB."""
    return db(dsp.rms(layer) / dsp.active_rms(vocal))


class TestLayers(unittest.TestCase):
    def setUp(self):
        self.vocal = burst(800.0, 0.5, lead=0.05)

    def test_every_touch_is_120ms_or_shorter(self):
        for mood in layers.MOODS:
            self.assertLessEqual(len(layers.touch(mood)) / SR, 0.120, mood)
            self.assertGreater(len(layers.touch(mood)) / SR, 0.05, mood)

    def test_touch_sits_18_db_under_the_vocal(self):
        for mood in layers.MOODS:
            offset, layer = layers.touch_layer(self.vocal, mood)
            self.assertAlmostEqual(level(layer, self.vocal), -18.0, delta=0.5, msg=mood)

    def test_touch_starts_on_the_vocals_first_transient(self):
        for mood in layers.MOODS:
            offset, layer = layers.touch_layer(self.vocal, mood)
            self.assertAlmostEqual(offset / SR, 0.05, delta=0.002, msg=mood)
            mixed = layers.add_layers(self.vocal, mood)
            first = next(i for i, (a, b) in enumerate(zip(mixed, self.vocal)) if a != b)
            self.assertGreaterEqual(first, offset)
            self.assertLess((first - offset) / SR, 0.002, mood)
            self.assertEqual(mixed[:offset], self.vocal[:offset])

    def test_the_happy_touch_steps_up_a_major_third(self):
        x = layers.touch("happy")
        first, second = x[:int(0.04 * SR)], x[int(0.065 * SR):]
        self.assertGreater(power(first, 784.0), 10 * power(first, 988.0))
        self.assertGreater(power(second, 988.0), 10 * power(second, 784.0))

    def test_the_attention_touch_glides_up_and_the_upset_touch_glides_down(self):
        up, down = layers.touch("attention"), layers.touch("upset")
        self.assertAlmostEqual(len(up) / SR, 0.080, delta=0.002)
        h, k = len(up) // 2, len(down) // 2
        self.assertGreater(crossings(up[h:]), crossings(up[:h]))
        self.assertLess(crossings(down[k:]), crossings(down[:k]))

    def test_the_calm_touch_is_low_passed(self):
        x = layers.touch("calm")
        self.assertLess(power(x, 6000.0), 0.01 * power(x, 500.0))

    def test_unknown_mood_is_an_error(self):
        with self.assertRaises(ValueError):
            layers.touch("sleepy")

    def test_signature_is_three_inharmonic_partials_about_a_fifth_of_a_second(self):
        x = layers.signature()
        self.assertAlmostEqual(len(x) / SR, 0.2, delta=0.01)
        for freq in (2250.0, 3400.0, 5050.0):
            self.assertGreater(power(x, freq), 20 * power(x, freq * 0.85), freq)
        for ratio in (3400.0 / 2250.0, 5050.0 / 2250.0):
            self.assertGreater(abs(ratio - round(ratio)), 0.1)

    def test_signature_climbs(self):
        x = layers.signature()
        self.assertGreater(power(x[int(0.12 * SR):], 5050.0), power(x[:int(0.03 * SR)], 5050.0))

    def test_signature_sits_10_db_under_the_vocal_at_60_percent_of_its_length(self):
        offset, layer = layers.signature_layer(self.vocal)
        self.assertAlmostEqual(level(layer, self.vocal), -10.0, delta=0.5)
        self.assertAlmostEqual(offset / len(self.vocal), 0.6, delta=0.002)

    def test_the_dark_signature_is_an_octave_lower_and_slower(self):
        bright, dark = layers.signature(), layers.signature(dark=True)
        for freq in (1125.0, 1700.0, 2525.0):
            self.assertGreater(power(dark, freq), 20 * power(dark, freq * 0.85), freq)
            self.assertGreater(power(dark, freq), 20 * power(bright, freq), freq)
        def fade_ratio(x, freq):      # power late in the first partial over power early in it
            return power(x[int(0.10 * SR):int(0.16 * SR)], freq) / power(x[:int(0.06 * SR)], freq)
        self.assertGreater(fade_ratio(dark, 1125.0), fade_ratio(bright, 2250.0))

    def test_add_layers_scales_every_layer_against_the_vocal_alone(self):
        mixed = layers.add_layers(self.vocal, "happy", with_signature=True)
        offset, sig = layers.signature_layer(self.vocal)
        self.assertGreaterEqual(len(mixed), offset + len(sig))
        tail = [m - (self.vocal[offset + i] if offset + i < len(self.vocal) else 0.0)
                for i, m in enumerate(mixed[offset:offset + len(sig)])]
        self.assertAlmostEqual(level(tail, self.vocal), -10.0, delta=0.6)

    def test_the_thump_is_a_100hz_tail_6_db_under_the_vocal(self):
        offset, layer = layers.thump_layer(self.vocal)
        self.assertAlmostEqual(level(layer, self.vocal), -6.0, delta=0.5)
        self.assertAlmostEqual((len(self.vocal) - offset) / SR, 0.020, delta=0.001)
        self.assertGreater(power(layer, 100.0), 20 * power(layer, 400.0))
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: FAIL, `ModuleNotFoundError: No module named 'layers'`

- [ ] **Step 3: Write the implementation**

**Create `tools/sounds/layers.py`**

```python
"""The two layers on top of a cat moment (spec section 3): the touch and the signature.

Both are made in code and scaled against the vocal they sit on. The touch is a short musical hint
of the mood, placed on the vocal's first transient. The signature is three inharmonic collar-bell
partials that climb, placed at 60 % of the vocal's length.
"""
from __future__ import annotations

import math
import random

from dsp import SR, active_rms, db_to_lin, lowpass, mix_at, onset_index, rms

MOODS = ("happy", "attention", "upset", "calm")
TOUCH_DB = -18.0
SIGNATURE_DB = -10.0
SIGNATURE_START = 0.60


def _n(seconds):
    return int(round(seconds * SR))


def _attack(t, seconds):
    return min(1.0, t / seconds) if seconds > 0 else 1.0


def _tail(t, length, seconds=0.005):
    """A short fade at the end of a layer so it never clicks off."""
    return min(1.0, max(0.0, (length - t) / seconds))


def _peak_to(x, level):
    top = max(abs(v) for v in x)
    return [level * v / top for v in x]


def touch(mood):
    """The touch layer for a mood, 120 ms at most, peak 0.5 (the level is set against the vocal)."""
    if mood == "happy":          # two sine partials, a major third apart, one after the other
        length = 0.110
        out = [0.0] * _n(length)
        for start, freq in ((0.0, 784.0), (0.045, 784.0 * 2.0 ** (4.0 / 12.0))):
            for i in range(_n(length - start)):
                t = i / SR
                out[_n(start) + i] += (math.sin(2.0 * math.pi * freq * t) * _attack(t, 0.003)
                                       * math.exp(-t / 0.020))
        return _peak_to([v * _tail(i / SR, length) for i, v in enumerate(out)], 0.5)
    if mood == "attention":      # an 80 ms glide up a fifth
        length = 0.080
        out, phase = [], 0.0
        for i in range(_n(length)):
            t = i / SR
            phase += 2.0 * math.pi * 600.0 * 2.0 ** (7.0 / 12.0 * t / length) / SR
            out.append(math.sin(phase) * _attack(t, 0.004) * (1.0 - t / length) ** 0.5
                       * _tail(t, length))
        return _peak_to(out, 0.5)
    if mood == "upset":          # a filtered buzzy tone gliding down a minor third
        length = 0.110
        out, phase = [], 0.0
        for i in range(_n(length)):
            t = i / SR
            phase += 2.0 * math.pi * 330.0 * 2.0 ** (-3.0 / 12.0 * t / length) / SR
            buzz = sum(math.sin(k * phase) / k for k in range(1, 7))
            out.append(buzz * _attack(t, 0.003) * math.exp(-t / 0.055) * _tail(t, length))
        return _peak_to(lowpass(out, 1200.0, SR, 0.7), 0.5)
    if mood == "calm":           # one soft, low-passed tick
        length = 0.060
        rng = random.Random(1301)
        out = [(rng.random() * 2.0 - 1.0) * math.exp(-(i / SR) / 0.008) * _attack(i / SR, 0.001)
               * _tail(i / SR, length) for i in range(_n(length))]
        return _peak_to(lowpass(out, 1800.0, SR, 0.7), 0.5)
    raise ValueError("unknown mood: %r" % (mood,))


def signature(dark=False):
    """Three inharmonic collar-bell partials that climb, 0.2 s. `dark` is the lower, slower version
    the error slot gets."""
    if dark:
        freqs, t60s = (1125.0, 1700.0, 2525.0), (0.20, 0.17, 0.14)
    else:
        freqs, t60s = (2250.0, 3400.0, 5050.0), (0.14, 0.12, 0.10)
    length = 0.200
    out = [0.0] * _n(length)
    for k, (freq, t60) in enumerate(zip(freqs, t60s)):
        start = 0.040 * k                       # each partial enters higher than the last
        for i in range(_n(length - start)):
            t = i / SR
            out[_n(start) + i] += (0.3 * math.sin(2.0 * math.pi * freq * t + 0.5 * k)
                                   * _attack(t, 0.002) * 10.0 ** (-3.0 * t / t60))
    return [v * _tail(i / SR, length) for i, v in enumerate(out)]


def thump():
    """The tail thump for the rate slot: 100 Hz, fast decay, 0.16 s."""
    length = 0.160
    return [0.8 * math.sin(2.0 * math.pi * 100.0 * (i / SR)) * _attack(i / SR, 0.002)
            * math.exp(-(i / SR) / 0.045) * _tail(i / SR, length) for i in range(_n(length))]


def scaled(layer, vocal, rel_db):
    """`layer` with its RMS set to rel_db from the vocal's active RMS."""
    level = rms(layer)
    if level == 0.0:
        return list(layer)
    k = active_rms(vocal) * db_to_lin(rel_db) / level
    return [v * k for v in layer]


def touch_layer(vocal, mood):
    """(offset, samples): the mood's touch, TOUCH_DB under the vocal, on its first transient."""
    return onset_index(vocal), scaled(touch(mood), vocal, TOUCH_DB)


def signature_layer(vocal, dark=False):
    """(offset, samples): the signature, SIGNATURE_DB under the vocal, at 60 % of its length."""
    return int(SIGNATURE_START * len(vocal)), scaled(signature(dark), vocal, SIGNATURE_DB)


def thump_layer(vocal):
    """(offset, samples): the tail thump, 6 dB under the vocal, starting 20 ms before it ends."""
    return max(0, len(vocal) - _n(0.020)), scaled(thump(), vocal, -6.0)


def add_layers(vocal, mood, with_signature=False, dark=False, with_thump=False):
    """The vocal with its layers mixed in. Every layer is scaled against the vocal alone, never
    against the other layers. The result can run past the vocal's end."""
    out = list(vocal)
    parts = [touch_layer(vocal, mood)]
    if with_signature:
        parts.append(signature_layer(vocal, dark))
    if with_thump:
        parts.append(thump_layer(vocal))
    for offset, layer in parts:
        out = mix_at(out, layer, offset)
    return out
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 50 tests`, `OK`

- [ ] **Step 5: Commit**

```bash
git add tools/sounds/layers.py tests/test_sound_build.py
git commit -m "feat(sounds): touch, signature and thump layers" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 6: Slot table, recipe loading and validation

One place holds the 28 slots with their kind, mood, signature flag and length limit (`SLOTS`). Recipes are checked hard, so a typo cannot silently change what ships: unknown slot, field, effect or synth; a `mood` or `signature` that disagrees with the spec's table; numbers out of range; `end <= start`; a source that is malformed, excluded (qubodup, Lukey1028, matched case-insensitively on author and Freesound id) or a Department64 file that is not a `kitten##` or Buddha Purr (Freesound ids 64004, 64005, 64007, 64008, 64011, 64012, 64015, 64017). A set is complete only when its own entries plus `_shared.json` cover all 28 slots exactly once.

**Files:**
- Create: `tools/sounds/recipe.py`
- Modify: `tests/test_sound_build.py` (append)

**Interfaces:**
- Consumes (`synth`): `GAPS` (the valid `synth:<name>` names).
- Produces (`recipe`): `Slot(name, kind, mood, signature, dark, max_len)`; `SLOTS` (an `OrderedDict` of 28, cat moments first); `SET_NAMES = ("studio", "steff", "kitten", "bestof")`; `SHARED_NAME = "_shared"`; `EXCLUDED`; `DEPARTMENT64_OK`; `EFFECTS`; `Entry(slot, source, start, end, gain_db, pitch_st, effects, hp_hz, mood, signature, note, shared)`; `SetRecipe(name, title, pitch_st, entries)` where `entries` is an `OrderedDict` slot to `Entry` in `SLOTS` order; `RecipeError(ValueError)`; `parse_entry(raw, where, shared=False) -> Entry`; `load_set(path, shared_entries) -> SetRecipe`; `load_recipes(sets_dir) -> OrderedDict name -> SetRecipe`; `missing_sources(recipe, candidates_dir) -> [source, ...]`; helpers `_read(path)` and `_entries(doc, where, shared)` that the tests also call.

- [ ] **Step 1: Write the failing tests** (they include Review Focus 4: excluded sources in any case)

**Append to `tests/test_sound_build.py`**

```python
import recipe  # noqa: E402

# The slots every set shares: the ten ticks and the three made-in-code or foley fill-ins.
SHARED_SLOTS = ["yawn", "work", "gulp", "approve", "peek", "open", "close", "hover", "blip", "tick",
                "send", "attach", "pop"]


def raw(slot, source=None, **extra):
    """A valid raw recipe entry for `slot`, with `extra` fields on top."""
    info = recipe.SLOTS[slot]
    entry = {"slot": slot, "source": "synth:blip" if source is None else source, "mood": info.mood,
             "signature": info.signature}
    entry.update(extra)
    return entry


def write_json(path, doc):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f)


def write_recipes(directory, source_for, pitch_for=lambda name: 0.0):
    """A complete recipe folder: _shared.json and four sets. `source_for(slot)` picks each source,
    `pitch_for(set name)` each set's shared pitch shift."""
    os.makedirs(directory, exist_ok=True)
    write_json(os.path.join(directory, "_shared.json"), {
        "set": "_shared", "entries": [raw(s, source_for(s)) for s in SHARED_SLOTS]})
    own = [s for s in recipe.SLOTS if s not in SHARED_SLOTS]
    for name in recipe.SET_NAMES:
        write_json(os.path.join(directory, name + ".json"), {
            "set": name, "title": name, "pitch_st": pitch_for(name), "entries": [raw(s, source_for(s)) for s in own]})


class TestRecipe(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm recipes ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def bad(self, slot="greet", **extra):
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.parse_entry(raw(slot, **extra), "t")
        return str(ctx.exception)

    def test_the_slot_table_is_the_specs(self):
        cats = [s for s in recipe.SLOTS.values() if s.kind == "cat"]
        ticks = [s for s in recipe.SLOTS.values() if s.kind == "tick"]
        self.assertEqual((len(cats), len(ticks), len(recipe.SLOTS)), (18, 10, 28))
        moods = {}
        for s in cats:
            moods.setdefault(s.mood, set()).add(s.name)
        self.assertEqual(moods["happy"], {"greet", "love", "finish", "proud", "wink", "gulp"})
        self.assertEqual(moods["attention"], {"approval", "question", "think", "search"})
        self.assertEqual(moods["upset"], {"error", "annoyed", "rate", "dizzy"})
        self.assertEqual(moods["calm"], {"slap", "yawn", "sleep", "work"})
        self.assertEqual({s.name for s in recipe.SLOTS.values() if s.signature},
                         {"greet", "finish", "approval", "question", "error", "love"})
        self.assertEqual([s.name for s in recipe.SLOTS.values() if s.dark], ["error"])
        self.assertEqual({s.name: s.max_len for s in recipe.SLOTS.values() if s.max_len != 1.5},
                         dict(sleep=3.0, **{t.name: 0.4 for t in ticks}))
        self.assertTrue(all(t.mood == "none" and not t.signature for t in ticks))

    def test_a_valid_entry_parses_with_defaults(self):
        e = recipe.parse_entry(raw("greet", "greet/fs-262306-steffcaffrey.mp3"), "t")
        self.assertEqual((e.slot, e.start, e.end, e.gain_db, e.pitch_st, e.hp_hz, e.effects),
                         ("greet", None, None, 0.0, 0.0, 100.0, []))
        e = recipe.parse_entry(raw("dizzy", effects=[{"type": "wobble"}], start=1, end=2.5, pitch_st=2), "t")
        self.assertEqual(e.effects, [{"type": "wobble", "rate_hz": 5.0, "depth_st": 1.0}])
        self.assertEqual((e.start, e.end, e.pitch_st), (1.0, 2.5, 2.0))

    def test_unknown_slot_field_effect_and_synth_are_rejected(self):
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.parse_entry(dict(raw("greet"), slot="purr"), "t")
        self.assertIn("unknown slot", str(ctx.exception))
        self.assertIn("unknown fields", self.bad(volume=3))
        self.assertIn("unknown effect", self.bad(effects=[{"type": "reverb"}]))
        self.assertIn("unknown parameters", self.bad(effects=[{"type": "thump", "gain": 3}]))
        self.assertIn("needs from_st", self.bad(effects=[{"type": "glide", "to_st": 2}]))
        self.assertIn("unknown synth", self.bad(source="synth:meow"))

    def test_mood_and_signature_must_match_the_spec(self):
        self.assertIn("mood must be", self.bad(mood="calm"))
        self.assertIn("signature must be", self.bad(signature=False))
        self.assertIn("signature must be", self.bad("slap", signature=True))
        self.assertIn("mood must be", self.bad("tick", mood="happy"))

    def test_numbers_must_be_in_range(self):
        for field, value in (("gain_db", 3.0), ("pitch_st", 13), ("hp_hz", 50), ("start", -1), ("end", "2")):
            self.assertIn(field, self.bad(**{field: value}))
        self.assertIn("end must be after start", self.bad(start=2.0, end=1.0))

    def test_excluded_and_non_cc0_sources_are_rejected_in_any_case(self):
        for src in ("blip/fs-857748-qubodup.mp3", "blip/FS-857748-QUBODUP.mp3", "approval/fs-732521-Lukey1028.mp3",
                    "approval/fs-732521-lukey1028.MP3", "greet/fs-1-Lukey1028.mp3"):
            self.assertIn("excluded source", self.bad(source=src), src)
        self.assertIn("not a Department64", self.bad(source="annoyed/fs-211234-Department64.mp3"))
        self.assertIn("not a Department64", self.bad(source="annoyed/fs-DEPARTMENT64.mp3"))
        recipe.parse_entry(raw("annoyed", "annoyed/fs-64008-Department64.mp3"), "t")
        recipe.parse_entry(raw("sleep", "sleep/fs-64004-Department64.mp3"), "t")

    def test_sources_must_be_folder_slash_file(self):
        for src in ("fs-1-x.mp3", "nowhere/fs-1-x.mp3", "greet/../x.mp3", "greet/x.txt", "", 5):
            self.assertIn("source", self.bad(source=src), src)

    def test_load_set_needs_all_28_slots_once(self):
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "synth:blip")
        shared = recipe._entries(recipe._read(os.path.join(d, "_shared.json")), "_shared", True)
        self.assertEqual(len(recipe.load_set(os.path.join(d, "studio.json"), shared).entries), 28)
        doc = recipe._read(os.path.join(d, "studio.json"))
        gone = doc["entries"].pop()
        write_json(os.path.join(d, "studio.json"), doc)
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_set(os.path.join(d, "studio.json"), shared)
        self.assertIn("missing slots ['%s']" % gone["slot"], str(ctx.exception))
        doc["entries"] += [gone, gone]
        write_json(os.path.join(d, "studio.json"), doc)
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_set(os.path.join(d, "studio.json"), shared)
        self.assertIn("appears twice", str(ctx.exception))

    def test_a_set_cannot_redefine_a_shared_slot_and_must_be_named(self):
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "synth:blip")
        shared = recipe._entries(recipe._read(os.path.join(d, "_shared.json")), "_shared", True)
        doc = recipe._read(os.path.join(d, "kitten.json"))
        write_json(os.path.join(d, "kitten.json"), dict(doc, entries=doc["entries"] + [raw("tick")]))
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_set(os.path.join(d, "kitten.json"), shared)
        self.assertIn("already in _shared.json", str(ctx.exception))
        write_json(os.path.join(d, "kitten.json"), dict(doc, set="puppy"))
        with self.assertRaises(recipe.RecipeError):
            recipe.load_set(os.path.join(d, "kitten.json"), shared)

    def test_broken_json_is_a_recipe_error_not_a_traceback(self):
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "synth:blip")
        with open(os.path.join(d, "steff.json"), "w") as f:
            f.write("{ not json")
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_recipes(d)
        self.assertIn("not valid JSON", str(ctx.exception))

    def test_load_recipes_returns_four_complete_sets_sharing_their_shared_entries(self):
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "synth:blip")
        sets = recipe.load_recipes(d)
        self.assertEqual(list(sets), ["studio", "steff", "kitten", "bestof"])
        for s in sets.values():
            self.assertEqual(list(s.entries), list(recipe.SLOTS))
        for slot in SHARED_SLOTS:
            self.assertTrue(all(s.entries[slot] == sets["studio"].entries[slot] for s in sets.values()))
            self.assertTrue(sets["kitten"].entries[slot].shared)
        self.assertFalse(sets["kitten"].entries["greet"].shared)

    def test_missing_sources_lists_absent_clips_only(self):
        os.makedirs(os.path.join(self.tmp, "c", "greet"))
        open(os.path.join(self.tmp, "c", "greet", "a.mp3"), "w").close()
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "greet/a.mp3" if s == "greet" else "synth:blip")
        sets = recipe.load_recipes(d)
        self.assertEqual(recipe.missing_sources(sets["studio"], os.path.join(self.tmp, "c")), [])
        self.assertEqual(recipe.missing_sources(sets["studio"], os.path.join(self.tmp, "nope")), ["greet/a.mp3"])
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: FAIL, `ModuleNotFoundError: No module named 'recipe'`

- [ ] **Step 3: Write the implementation**

**Create `tools/sounds/recipe.py`**

```python
"""The 28 slots, and loading and validating the set recipes in design/sounds/sets/.

A recipe entry says how one slot is built. `_shared.json` holds the entries every set shares (the
ticks and the made-in-code fill-ins); each set file holds the rest. A set is complete when the two
together cover all 28 slots, once each.
"""
from __future__ import annotations

import json
import os
from collections import OrderedDict, namedtuple

from synth import GAPS

Slot = namedtuple("Slot", "name kind mood signature dark max_len")

# Spec section 1 (slots, lengths) and section 3 (moods, signature). Cat moments first.
_CAT = [("greet", "happy"), ("love", "happy"), ("annoyed", "upset"), ("dizzy", "upset"),
        ("slap", "calm"), ("finish", "happy"), ("error", "upset"), ("approval", "attention"),
        ("question", "attention"), ("proud", "happy"), ("wink", "happy"), ("yawn", "calm"),
        ("sleep", "calm"), ("gulp", "happy"), ("think", "attention"), ("search", "attention"),
        ("work", "calm"), ("rate", "upset")]
_TICKS = ["approve", "peek", "open", "close", "hover", "blip", "tick", "send", "attach", "pop"]
_SIGNATURE = ("greet", "finish", "approval", "question", "error", "love")

SLOTS = OrderedDict()
for _name, _mood in _CAT:
    SLOTS[_name] = Slot(_name, "cat", _mood, _name in _SIGNATURE, _name == "error",
                        3.0 if _name == "sleep" else 1.5)
for _name in _TICKS:
    SLOTS[_name] = Slot(_name, "tick", "none", False, False, 0.4)

SET_NAMES = ("studio", "steff", "kitten", "bestof")
SHARED_NAME = "_shared"

# Spec section 1: never in any set. Matched against the file name (author and Freesound id).
EXCLUDED = ("qubodup", "857748", "lukey1028", "732521")
# Department64's kitten## files and Buddha Purr; the rest of that uploader's pack is CC BY.
DEPARTMENT64_OK = {"64004", "64005", "64007", "64008", "64011", "64012", "64015", "64017"}

EFFECTS = {  # type -> {param: (default or None if required, low, high)}
    "wobble": {"rate_hz": (5.0, 1.0, 12.0), "depth_st": (1.0, 0.0, 3.0)},
    "glide": {"from_st": (None, -12.0, 12.0), "to_st": (None, -12.0, 12.0)},
    "thump": {},
}
AUDIO_EXT = (".mp3", ".wav", ".m4a", ".aiff", ".caf")
FIELDS = {"slot", "source", "start", "end", "gain_db", "pitch_st", "effects", "hp_hz", "mood",
          "signature", "note"}

Entry = namedtuple("Entry", "slot source start end gain_db pitch_st effects hp_hz mood signature "
                            "note shared")
SetRecipe = namedtuple("SetRecipe", "name title pitch_st entries")


class RecipeError(ValueError):
    pass


def _num(v, where, field, low, high):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise RecipeError("%s: %s must be a number" % (where, field))
    if not low <= v <= high:
        raise RecipeError("%s: %s=%r is outside %g..%g" % (where, field, v, low, high))
    return float(v)


def _effects(raw, where):
    if not isinstance(raw, list):
        raise RecipeError("%s: effects must be a list" % where)
    out = []
    for fx in raw:
        if not isinstance(fx, dict) or fx.get("type") not in EFFECTS:
            raise RecipeError("%s: unknown effect %r (known: %s)"
                              % (where, fx, ", ".join(sorted(EFFECTS))))
        spec = EFFECTS[fx["type"]]
        extra = set(fx) - set(spec) - {"type"}
        if extra:
            raise RecipeError("%s: effect %s has unknown parameters %s"
                              % (where, fx["type"], sorted(extra)))
        item = {"type": fx["type"]}
        for name, (default, low, high) in spec.items():
            if name not in fx and default is None:
                raise RecipeError("%s: effect %s needs %s" % (where, fx["type"], name))
            item[name] = _num(fx.get(name, default), where, fx["type"] + "." + name, low, high)
        out.append(item)
    return out


def _check_source(source, where):
    if not isinstance(source, str) or not source:
        raise RecipeError("%s: source is missing" % where)
    low = source.lower()
    if low.startswith("synth:"):
        if source[6:] not in GAPS:
            raise RecipeError("%s: unknown synth recipe %r (known: %s)"
                              % (where, source, ", ".join(sorted(GAPS))))
        return
    for bad in EXCLUDED:
        if bad in low:
            raise RecipeError("%s: %s is an excluded source (spec section 1)" % (where, source))
    parts = source.split("/")
    if len(parts) != 2 or parts[0] not in SLOTS or ".." in source or not low.endswith(AUDIO_EXT):
        raise RecipeError("%s: source %r must be '<slot folder>/<file>' or 'synth:<name>'"
                          % (where, source))
    if "department64" in low:
        ident = parts[1].split("-")[1] if parts[1].startswith("fs-") else ""
        if ident not in DEPARTMENT64_OK:
            raise RecipeError("%s: %s is not a Department64 kitten## file or Buddha Purr"
                              % (where, source))


def parse_entry(raw, where, shared=False):
    if not isinstance(raw, dict):
        raise RecipeError("%s: an entry must be an object" % where)
    slot = raw.get("slot")
    if slot not in SLOTS:
        raise RecipeError("%s: unknown slot %r" % (where, slot))
    where = "%s/%s" % (where, slot)
    unknown = set(raw) - FIELDS
    if unknown:
        raise RecipeError("%s: unknown fields %s" % (where, sorted(unknown)))
    info = SLOTS[slot]
    if raw.get("mood") != info.mood:
        raise RecipeError("%s: mood must be %r (spec section 3)" % (where, info.mood))
    if raw.get("signature") is not info.signature:
        raise RecipeError("%s: signature must be %r (spec section 3)" % (where, info.signature))
    _check_source(raw.get("source"), where)
    start = raw.get("start")
    end = raw.get("end")
    start = None if start is None else _num(start, where, "start", 0.0, 600.0)
    end = None if end is None else _num(end, where, "end", 0.0, 600.0)
    if start is not None and end is not None and end <= start:
        raise RecipeError("%s: end must be after start" % where)
    return Entry(slot, raw["source"], start, end,
                 _num(raw.get("gain_db", 0.0), where, "gain_db", -1.5, 1.5),
                 _num(raw.get("pitch_st", 0.0), where, "pitch_st", -12.0, 12.0),
                 _effects(raw.get("effects", []), where),
                 _num(raw.get("hp_hz", 100.0), where, "hp_hz", 100.0, 1500.0),
                 info.mood, info.signature, str(raw.get("note", "")), shared)


def _read(path):
    with open(path, encoding="utf-8") as f:
        try:
            return json.load(f)
        except ValueError as e:
            raise RecipeError("%s: not valid JSON (%s)" % (path, e))


def _entries(doc, where, shared):
    if not isinstance(doc.get("entries"), list):
        raise RecipeError("%s: 'entries' must be a list" % where)
    seen = OrderedDict()
    for raw in doc["entries"]:
        e = parse_entry(raw, where, shared)
        if e.slot in seen:
            raise RecipeError("%s: slot %s appears twice" % (where, e.slot))
        seen[e.slot] = e
    return seen


def load_set(path, shared_entries):
    """Parse one set file and join it with the shared entries. Returns a SetRecipe whose entries
    cover all 28 slots in SLOTS order."""
    doc = _read(path)
    name = doc.get("set")
    if name not in SET_NAMES:
        raise RecipeError("%s: 'set' must be one of %s" % (path, ", ".join(SET_NAMES)))
    own = _entries(doc, name, False)
    clash = sorted(set(own) & set(shared_entries))
    if clash:
        raise RecipeError("%s: slots %s are already in %s.json" % (name, clash, SHARED_NAME))
    missing = [s for s in SLOTS if s not in own and s not in shared_entries]
    if missing:
        raise RecipeError("%s: missing slots %s" % (name, missing))
    pitch = _num(doc.get("pitch_st", 0.0), name, "pitch_st", -12.0, 12.0)
    merged = OrderedDict((s, own[s] if s in own else shared_entries[s]) for s in SLOTS)
    return SetRecipe(name, str(doc.get("title", name)), pitch, merged)


def load_recipes(sets_dir):
    """Load _shared.json and the four sets. Returns OrderedDict name -> SetRecipe."""
    shared = _entries(_read(os.path.join(sets_dir, SHARED_NAME + ".json")), SHARED_NAME, True)
    return OrderedDict((n, load_set(os.path.join(sets_dir, n + ".json"), shared)) for n in SET_NAMES)


def missing_sources(recipe, candidates_dir):
    """File sources of a set that are not in the candidates folder."""
    out = []
    for e in recipe.entries.values():
        if not e.source.startswith("synth:"):
            if not os.path.isfile(os.path.join(candidates_dir, *e.source.split("/"))):
                out.append(e.source)
    return out
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 62 tests`, `OK`

- [ ] **Step 5: Commit**

```bash
git add tools/sounds/recipe.py tests/test_sound_build.py
git commit -m "feat(sounds): slot table and recipe validation" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 7: The pipeline, one entry to one finished sound

`build_slot` runs the spec's order: source (a synth, or a decoded clip trimmed by `start` and `end`, or by automatic trim), pitch shift (the set's shared shift plus the entry's, recorded clips of the set only), effects in the order listed, hard length cap, high-pass (100 Hz, or `hp_hz`), fades 3 ms in and 20 ms out, the layers (cat moments only: the touch always, the signature when the entry says so, the thump when it has a `thump` effect), the length cap again and fades again, then `loudness.normalize` to the kind's target plus `gain_db`. A window that is empty or in a pause (peak under -70 dBFS) raises `SourceError` naming the slot, the clip and the window. `build_set` writes all 28 WAVs and renders shared slots once per run through a cache.

**Files:**
- Create: `tools/sounds/pipeline.py`
- Modify: `tests/test_sound_build.py` (append)

**Interfaces:**
- Consumes: `dsp` (`SR`, `auto_trim`, `seconds_slice`, `pitch_shift`, `wobble`, `glide`, `highpass`, `fade`, `peak`, `lin_to_db`), `layers.add_layers(vocal, mood, with_signature, dark, with_thump)`, `loudness.normalize(x, target, ceiling) -> (samples, Norm)`, `audio_io` (`read_wav`, `write_wav16`), `recipe.SLOTS`, `synth.GAPS`; a loader object with `.load(source)`.
- Produces (`pipeline`): `TARGETS = {"cat": (-20.0, 1.5), "tick": (-28.0, 2.0)}` (target LUFS, tolerance in LU); `TP_CEILING = -1.0`; `SILENT_DB = -70.0`; `Built(slot, samples, gain_db, limit_db)`; `SourceError(ValueError)`; `build_slot(entry, loader, set_pitch_st=0.0) -> Built`; `build_set(recipe, loader, out_dir, cache=None) -> [Built, ...]` (writes `out_dir/<slot>.wav`); `read_back(out_dir, slot) -> samples`.

- [ ] **Step 1: Write the failing tests** (they include Review Focus 1 and 5, and the determinism test the brief asks for)

**Append to `tests/test_sound_build.py`**

```python
import pipeline  # noqa: E402


class DictLoader:
    """Stands in for the afconvert loader: clips come from a dictionary."""

    def __init__(self, clips):
        self.clips = clips

    def load(self, source):
        return self.clips[source]


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def entry(slot, source=None, shared=False, **fields):
    return recipe.parse_entry(raw(slot, source or "%s/c.wav" % slot, **fields), "t", shared)


class TestPipeline(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm pipeline ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.clip = burst(700.0, 0.4, lead=0.05, amp=0.2)
        self.loader = DictLoader({"%s/c.wav" % s: self.clip for s in recipe.SLOTS})

    def build(self, slot, set_pitch=0.0, **fields):
        return pipeline.build_slot(entry(slot, **fields), self.loader, set_pitch)

    def test_a_cat_moment_is_leveled_faded_and_peak_safe(self):
        b = self.build("question")
        m = loudness.measure(b.samples)
        self.assertAlmostEqual(m.lufs, -20.0, delta=0.5)
        self.assertLessEqual(m.tp_db, -1.0 + 0.05)
        self.assertEqual((b.samples[0], b.samples[-1]), (0.0, 0.0))
        self.assertLessEqual(m.seconds, 1.5)

    def test_ticks_sit_8_db_under_the_vocals_and_get_neither_layer(self):
        tick = self.build("tick")
        self.assertAlmostEqual(loudness.short_term_lufs(tick.samples), -28.0, delta=0.5)
        cat = self.build("greet")
        # the happy touch (784/988 Hz) and the signature (2250 Hz) only exist on the cat moment
        for freq in (988.0, 2250.0):
            self.assertLess(power(tick.samples, freq), 1e-3 * power(tick.samples, 700.0), freq)
        self.assertGreater(power(cat.samples[int(0.2 * SR):], 2250.0), 1e-3 * power(cat.samples, 700.0))

    def test_the_signature_follows_the_entry_flag(self):
        with_sig = self.build("greet")
        no_sig = pipeline.build_slot(entry("greet")._replace(signature=False), self.loader)
        late = slice(int(0.2 * SR), None)
        self.assertGreater(power(with_sig.samples[late], 2250.0), 10 * power(no_sig.samples[late], 2250.0))

    def test_lengths_are_cut_to_each_kinds_maximum(self):
        long_clip = sine(300, 3.5, 0.2)
        self.loader.clips.update({"greet/c.wav": long_clip, "sleep/c.wav": long_clip, "tick/c.wav": long_clip})
        for slot, longest in (("greet", 1.5), ("sleep", 3.0), ("tick", 0.4)):
            n = len(self.build(slot, start=0.0, end=3.2).samples)
            self.assertEqual(n, int(longest * SR), slot)

    def test_explicit_trim_is_honoured_and_auto_trim_drops_the_silence(self):
        self.loader.clips["slap/c.wav"] = sine(300, 1.0, 0.2)
        self.assertEqual(len(self.build("slap", start=0.25, end=0.75).samples), int(0.5 * SR))
        self.loader.clips["slap/c.wav"] = [0.0] * SR + sine(300, 0.3, 0.2) + [0.0] * SR
        self.assertAlmostEqual(len(self.build("slap").samples) / SR, 0.3, delta=0.03)

    def test_the_sets_shared_pitch_shift_reaches_recorded_clips_only(self):
        self.loader.clips["slap/c.wav"] = sine(300, 1.0, 0.2)
        flat = self.build("slap", start=0.0, end=1.0)
        up = self.build("slap", set_pitch=12.0, start=0.0, end=1.0)
        self.assertAlmostEqual(len(up.samples), len(flat.samples) / 2, delta=3)
        shared = pipeline.build_slot(entry("slap", shared=True, start=0.0, end=1.0), self.loader, 12.0)
        self.assertEqual(len(shared.samples), len(flat.samples))
        synthetic = pipeline.build_slot(entry("work", "synth:work"), self.loader, 12.0)
        self.assertEqual(len(synthetic.samples), len(pipeline.build_slot(entry("work", "synth:work"), self.loader).samples))

    def test_the_entry_pitch_adds_to_the_sets(self):
        self.loader.clips["slap/c.wav"] = sine(300, 1.0, 0.2)
        both = self.build("slap", set_pitch=5.0, start=0.0, end=1.0, pitch_st=7.0)
        self.assertAlmostEqual(len(both.samples), SR / 2, delta=3)

    def test_wobble_glide_and_thump_effects(self):
        self.loader.clips["dizzy/c.wav"] = sine(500, 0.8, 0.2)
        plain = self.build("dizzy", start=0.0, end=0.8)
        wob = self.build("dizzy", start=0.0, end=0.8, effects=[{"type": "wobble"}])
        self.assertNotEqual(plain.samples[:3000], wob.samples[:3000])
        self.assertAlmostEqual(len(wob.samples), len(plain.samples), delta=0.02 * SR)
        gl = self.build("dizzy", start=0.0, end=0.8, effects=[{"type": "glide", "from_st": 0, "to_st": 12}])
        self.assertLess(len(gl.samples), 0.8 * len(plain.samples))
        self.loader.clips["rate/c.wav"] = sine(500, 0.6, 0.2)
        dry = self.build("rate", start=0.0, end=0.6)
        thumped = self.build("rate", start=0.0, end=0.6, effects=[{"type": "thump"}])
        self.assertAlmostEqual((len(thumped.samples) - len(dry.samples)) / SR, 0.14, delta=0.01)
        tail = thumped.samples[-int(0.12 * SR):]
        self.assertGreater(power(tail, 100.0), 20 * power(dry.samples[-int(0.12 * SR):], 100.0))

    def test_a_window_outside_the_clip_or_in_a_pause_is_a_clear_error(self):
        with self.assertRaises(pipeline.SourceError) as ctx:
            self.build("greet", start=5.0, end=6.0)
        self.assertIn("greet", str(ctx.exception))
        self.assertIn("greet/c.wav", str(ctx.exception))
        self.assertIn("empty", str(ctx.exception))
        self.loader.clips["greet/c.wav"] = [0.0] * SR
        with self.assertRaises(pipeline.SourceError) as ctx:
            self.build("greet", start=0.0, end=0.5)
        self.assertIn("silent", str(ctx.exception))
        self.loader.clips["greet/c.wav"] = []
        with self.assertRaises(pipeline.SourceError):
            self.build("greet")

    def test_a_very_quiet_clip_is_brought_up_without_clipping(self):
        self.loader.clips["greet/c.wav"] = burst(700.0, 0.4, amp=0.0005)         # -66 dBFS
        m = loudness.measure(self.build("greet").samples)
        self.assertAlmostEqual(m.lufs, -20.0, delta=1.5)
        self.assertLessEqual(m.tp_db, -1.0 + 0.05)

    def test_build_set_writes_28_files_and_a_second_run_is_byte_identical(self):
        d = os.path.join(self.tmp, "recipes")
        write_recipes(d, lambda slot: "synth:%s" % slot if slot in synth.GAPS else "%s/c.wav" % slot,
                      pitch_for=lambda name: 1.5 if name == "kitten" else 0.0)
        sets = recipe.load_recipes(d)
        out = {}
        for run in ("one", "two"):
            cache = {}
            for name in ("studio", "kitten"):
                folder = os.path.join(self.tmp, run, name)
                built = pipeline.build_set(sets[name], self.loader, folder, cache)
                self.assertEqual(len(built), 28)
                self.assertEqual(sorted(os.listdir(folder)), sorted(slot + ".wav" for slot in recipe.SLOTS))
                out[(run, name)] = {f: read_bytes(os.path.join(folder, f)) for f in os.listdir(folder)}
        for name in ("studio", "kitten"):
            self.assertEqual(out[("one", name)], out[("two", name)], name)
        # shared slots are the same bytes in every set; the pitch shift changed the kitten's own slots
        for slot in SHARED_SLOTS:
            self.assertEqual(out[("one", "studio")][slot + ".wav"], out[("one", "kitten")][slot + ".wav"], slot)
        self.assertNotEqual(out[("one", "studio")]["love.wav"], out[("one", "kitten")]["love.wav"])
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: FAIL, `ModuleNotFoundError: No module named 'pipeline'`

- [ ] **Step 3: Write the implementation**

**Create `tools/sounds/pipeline.py`**

```python
"""Turn recipe entries into finished sounds: trim, shape, layer, level, write.

The order is the spec's (section 2): decode, trim, pitch, effects, 100 Hz high-pass, fades, layers,
loudness, true-peak limit, 16-bit WAV. `loader.load(source)` returns the decoded 48 kHz mono clip;
tests give it a dictionary, the CLI gives it afconvert.
"""
from __future__ import annotations

import os
from collections import namedtuple

import dsp
import layers
import loudness
from audio_io import read_wav, write_wav16
from recipe import SLOTS
from synth import GAPS

# short-term LUFS target and tolerance in LU, by kind. Ticks sit 6 to 10 dB under the vocals.
TARGETS = {"cat": (-20.0, 1.5), "tick": (-28.0, 2.0)}
TP_CEILING = -1.0
FADE_IN_MS, FADE_OUT_MS = 3.0, 20.0

SILENT_DB = -70.0       # a source window quieter than this is a pause, not a sound

Built = namedtuple("Built", "slot samples gain_db limit_db")


class SourceError(ValueError):
    """A recipe points at a window that is empty or silent."""


def _source(entry, info, loader, shift):
    if entry.source.startswith("synth:"):
        return GAPS[entry.source[6:]]()
    clip = loader.load(entry.source)
    if entry.start is None and entry.end is None:
        # no explicit trim: drop the silence and keep the loudest window that still fits after the shift
        x = dsp.auto_trim(clip, info.max_len * 2.0 ** (shift / 12.0))
    else:
        x = dsp.seconds_slice(clip, entry.start, entry.end)
    where = "%s: %s [%s..%s]" % (entry.slot, entry.source, entry.start, entry.end)
    if not x:
        raise SourceError("%s is empty: the clip is only %.2f s long" % (where, len(clip) / dsp.SR))
    if dsp.lin_to_db(dsp.peak(x)) < SILENT_DB:
        raise SourceError("%s is silent (peak %.0f dBFS)" % (where, dsp.lin_to_db(dsp.peak(x))))
    return x


def build_slot(entry, loader, set_pitch_st=0.0):
    """Render one slot. `set_pitch_st` is the set's shared shift; it applies to recorded clips of
    that set only, never to the shared ticks and fill-ins."""
    info = SLOTS[entry.slot]
    recorded = not entry.shared and not entry.source.startswith("synth:")
    shift = entry.pitch_st + (set_pitch_st if recorded else 0.0)
    x = dsp.pitch_shift(_source(entry, info, loader, shift), shift)
    for fx in entry.effects:
        if fx["type"] == "wobble":
            x = dsp.wobble(x, fx["rate_hz"], fx["depth_st"])
        elif fx["type"] == "glide":
            x = dsp.glide(x, fx["from_st"], fx["to_st"])
    x = dsp.highpass(x[:int(info.max_len * dsp.SR)], entry.hp_hz)
    x = dsp.fade(x, FADE_IN_MS, FADE_OUT_MS)
    if info.kind == "cat":
        x = layers.add_layers(x, entry.mood, entry.signature, info.dark,
                              any(fx["type"] == "thump" for fx in entry.effects))
    x = dsp.fade(x[:int(info.max_len * dsp.SR)], FADE_IN_MS, FADE_OUT_MS)
    target, _ = TARGETS[info.kind]
    y, norm = loudness.normalize(x, target + entry.gain_db, TP_CEILING)
    return Built(entry.slot, y, norm.gain_db, norm.limit_db)


def build_set(recipe, loader, out_dir, cache=None):
    """Build all 28 slots of a SetRecipe into out_dir/<slot>.wav. Shared slots are rendered once and
    reused through `cache` (a dict) when several sets are built in one run. Returns the Built list."""
    os.makedirs(str(out_dir), exist_ok=True)
    cache = {} if cache is None else cache
    built = []
    for slot, entry in recipe.entries.items():
        key = (repr(entry), None if entry.shared else recipe.pitch_st)
        if key not in cache:
            cache[key] = build_slot(entry, loader, recipe.pitch_st)
        b = cache[key]
        write_wav16(os.path.join(str(out_dir), slot + ".wav"), b.samples)
        built.append(b)
    return built


def read_back(out_dir, slot):
    """The written WAV, as the report and the owner's ears see it."""
    return read_wav(os.path.join(str(out_dir), slot + ".wav"))[0]
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 73 tests`, `OK` (about 20 seconds: the determinism test builds two sets twice, 28 slots each)

- [ ] **Step 5: Commit**

```bash
git add tools/sounds/pipeline.py tests/test_sound_build.py
git commit -m "feat(sounds): pipeline from recipe entry to finished WAV" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 8: The report and the command line

`report.check` turns a measurement into the list of targets it misses: loudness outside the kind's target and tolerance (cat -20 +-1.5, tick -28 +-2.0 LUFS), true peak over -1 dBTP (with 0.05 dB for 16-bit rounding), length over the slot's maximum or under 50 ms. `report.measure_set` measures the WAVs as written. `build_pack.py` is the command line; exit codes: 0 fine, 1 a file missed its targets (only with `--report`), 2 a recipe, clip or source problem. It finds the candidates folder from `--candidates`, then `$NM_SOUND_CANDIDATES`, then `<repo>/.claude/sounds/candidates`, then the main checkout's folder (through `git rev-parse --git-common-dir`), so a worktree works.

**Files:**
- Create: `tools/sounds/report.py`
- Create: `tools/sounds/build_pack.py`
- Modify: `tests/test_sound_build.py` (append)

**Interfaces:**
- Consumes: `loudness.measure`, `loudness.Measurement`, `pipeline` (`TARGETS`, `TP_CEILING`, `read_back`, `build_set`, `SourceError`), `recipe` (`SLOTS`, `SET_NAMES`, `load_recipes`, `missing_sources`, `RecipeError`), `audio_io.AfconvertLoader`.
- Produces: `report.TP_SLACK_DB = 0.05`; `report.MIN_SECONDS = 0.05`; `report.Row(slot, kind, lufs, target, rms_db, tp_db, seconds, limit_db, problems)`; `report.check(slot, measurement) -> [str]`; `report.measure_set(built, out_dir) -> [Row]`; `report.failures(results) -> ["set/slot: problem; ...", ...]`; `report.render(results) -> markdown str`; `build_pack.ROOT`, `build_pack.SETS_DIR`, `build_pack.BUILD_DIR`; `build_pack.find_candidates(explicit=None, root=ROOT) -> abs path or None`; `build_pack.main(argv=None) -> exit code`. Command line: `--set NAME | --all | --check-recipes`, `--candidates DIR`, `--out DIR`, `--recipes DIR`, `--report`.

- [ ] **Step 1: Write the failing tests** (they include Review Focus 1, 2 and 3)

**Append to `tests/test_sound_build.py`**

```python
import contextlib  # noqa: E402
import io  # noqa: E402
from unittest import mock  # noqa: E402

import build_pack  # noqa: E402
import report  # noqa: E402


def m(lufs=-20.0, tp=-3.0, seconds=0.8, rms_db=-24.0):
    return loudness.Measurement(lufs, rms_db, tp, tp, seconds)


class TestReport(unittest.TestCase):
    def test_a_file_on_target_passes(self):
        self.assertEqual(report.check("greet", m()), [])
        self.assertEqual(report.check("tick", m(lufs=-28.0, seconds=0.2)), [])

    def test_vocals_may_be_1_5_lu_off_and_ticks_2_lu(self):
        self.assertEqual(report.check("greet", m(lufs=-21.4)), [])
        self.assertEqual(report.check("greet", m(lufs=-18.6)), [])
        self.assertTrue(report.check("greet", m(lufs=-21.6)))
        self.assertEqual(report.check("tick", m(lufs=-29.9, seconds=0.2)), [])
        self.assertEqual(report.check("tick", m(lufs=-26.1, seconds=0.2)), [])
        self.assertTrue(report.check("tick", m(lufs=-30.1, seconds=0.2)))

    def test_true_peak_over_minus_one_fails_with_a_hair_of_slack(self):
        self.assertEqual(report.check("greet", m(tp=-0.97)), [])
        self.assertTrue(any("true peak" in p for p in report.check("greet", m(tp=-0.5))))

    def test_length_limits_are_1_5_s_for_cats_3_s_for_sleep_and_0_4_s_for_ticks(self):
        self.assertTrue(any("longer" in p for p in report.check("greet", m(seconds=1.51))))
        self.assertEqual(report.check("greet", m(seconds=1.5)), [])
        self.assertEqual(report.check("sleep", m(seconds=3.0)), [])
        self.assertTrue(report.check("sleep", m(seconds=3.1)))
        self.assertTrue(report.check("tick", m(lufs=-28.0, seconds=0.41)))
        self.assertTrue(any("shorter" in p for p in report.check("greet", m(seconds=0.01))))

    def test_silence_fails(self):
        self.assertTrue(report.check("greet", m(lufs=loudness.SILENT_LUFS)))

    def test_the_markdown_counts_passes_and_names_the_failures(self):
        ok = report.Row("greet", "cat", -20.0, -20.0, -24.0, -3.0, 0.8, 0.0, [])
        bad = report.Row("tick", "tick", -33.0, -28.0, -30.0, -3.0, 0.2, 0.0, ["loudness -33.0 LUFS is not -28.0 +-2.0"])
        results = {"studio": [ok, bad], "kitten": [ok]}
        text = report.render(results)
        self.assertIn("2 of 3 files meet their targets.", text)
        self.assertIn("## studio: 1 of 2 pass", text)
        self.assertIn("## kitten: 1 of 1 pass", text)
        self.assertIn("| tick | tick | -33.0 |", text)
        self.assertIn("FAIL: loudness -33.0 LUFS", text)
        self.assertEqual(report.failures(results), ["studio/tick: loudness -33.0 LUFS is not -28.0 +-2.0"])


class TestCli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm cli test ")           # a space in every path
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.recipes = os.path.join(self.tmp, "recipe folder")

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = build_pack.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def make_candidates(self, clip):
        cands = os.path.join(self.tmp, "my candidates")
        for slot in recipe.SLOTS:
            os.makedirs(os.path.join(cands, slot))
            write_pcm16(os.path.join(cands, slot, "c.wav"), [int(v * 32767) for v in clip], SR)
        return cands

    def test_check_recipes_accepts_good_recipes_and_rejects_bad_ones(self):
        write_recipes(self.recipes, lambda s: "synth:blip")
        code, out, _ = self.run_main("--check-recipes", "--recipes", self.recipes, "--candidates", self.tmp)
        self.assertEqual(code, 0)
        self.assertIn("recipes ok: 4 sets x 28 slots", out)
        doc = recipe._read(os.path.join(self.recipes, "steff.json"))
        doc["entries"][0]["mood"] = "calm"
        write_json(os.path.join(self.recipes, "steff.json"), doc)
        code, _, err = self.run_main("--check-recipes", "--recipes", self.recipes, "--candidates", self.tmp)
        self.assertEqual(code, 2)
        self.assertIn("recipe error", err)

    def test_check_recipes_lists_the_clips_that_are_missing(self):
        write_recipes(self.recipes, lambda s: "greet/gone.mp3" if s == "greet" else "synth:blip")
        code, _, err = self.run_main("--check-recipes", "--recipes", self.recipes, "--candidates", self.tmp)
        self.assertEqual(code, 2)
        self.assertIn("missing clip", err)
        self.assertIn("greet/gone.mp3", err)

    def test_a_build_without_clips_stops_with_a_message(self):
        write_recipes(self.recipes, lambda s: "synth:blip")
        code, _, err = self.run_main("--set", "studio", "--recipes", self.recipes,
                                     "--candidates", os.path.join(self.tmp, "nowhere"))
        self.assertEqual(code, 2)
        self.assertIn("candidates folder not found", err)

    def test_find_candidates_order(self):
        cands = os.path.join(self.tmp, "c")
        os.makedirs(cands)
        with mock.patch.dict(os.environ):
            os.environ.pop("NM_SOUND_CANDIDATES", None)
            self.assertEqual(build_pack.find_candidates(cands), os.path.abspath(cands))
            self.assertIsNone(build_pack.find_candidates(os.path.join(self.tmp, "no")))
            os.environ["NM_SOUND_CANDIDATES"] = cands
            self.assertEqual(build_pack.find_candidates(None, root=self.tmp), os.path.abspath(cands))
            os.environ.pop("NM_SOUND_CANDIDATES")
            os.makedirs(os.path.join(self.tmp, ".claude", "sounds", "candidates"))
            self.assertEqual(build_pack.find_candidates(None, root=self.tmp),
                             os.path.join(self.tmp, ".claude", "sounds", "candidates"))

    @unittest.skipUnless(shutil.which("git"), "needs git")
    def test_a_worktree_finds_the_main_checkouts_git_ignored_clips(self):
        main = os.path.join(self.tmp, "main checkout")
        os.makedirs(os.path.join(main, ".claude", "sounds", "candidates"))
        git = ["git", "-C", main, "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run(git + ["init", "-q"], check=True)
        subprocess.run(git + ["commit", "-q", "--allow-empty", "-m", "x"], check=True)
        work = os.path.join(self.tmp, "a worktree")
        subprocess.run(git + ["worktree", "add", "-q", work, "-b", "c1/test"], check=True)
        with mock.patch.dict(os.environ):
            os.environ.pop("NM_SOUND_CANDIDATES", None)
            found = build_pack.find_candidates(None, root=work)
        self.assertEqual(os.path.realpath(found),
                         os.path.realpath(os.path.join(main, ".claude", "sounds", "candidates")))

    @unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
    def test_a_set_builds_end_to_end_and_the_report_fails_the_run_on_a_missed_target(self):
        write_recipes(self.recipes, lambda s: "%s/c.wav" % s)
        cands = self.make_candidates(burst(700.0, 0.4, amp=0.2))
        spike = [0.0] * 2000 + [0.9] + [0.0] * 3000        # one click: far too peaky for a tick to reach -28 LUFS
        write_pcm16(os.path.join(cands, "tick", "c.wav"), [int(v * 32767) for v in spike], SR)
        out = os.path.join(self.tmp, "build out", "studio")
        code, stdout, err = self.run_main("--set", "studio", "--recipes", self.recipes, "--candidates", cands,
                                          "--out", out, "--report")
        self.assertEqual(code, 1, err)
        self.assertEqual(len([f for f in os.listdir(out) if f.endswith(".wav")]), 28)
        self.assertIn("(27 of 28 files meet their targets)", stdout)
        self.assertIn("FAIL studio/tick", err)
        with open(os.path.join(out, "report.md"), encoding="utf-8") as f:
            self.assertIn("## studio: 27 of 28 pass", f.read())

    @unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
    def test_a_silent_window_stops_the_build_with_the_slot_named(self):
        write_recipes(self.recipes, lambda s: "%s/c.wav" % s)
        cands = self.make_candidates(burst(700.0, 0.4, amp=0.2))
        write_pcm16(os.path.join(cands, "greet", "c.wav"), [0] * 20000, SR)
        code, _, err = self.run_main("--set", "studio", "--recipes", self.recipes, "--candidates", cands,
                                     "--out", os.path.join(self.tmp, "out"))
        self.assertEqual(code, 2)
        self.assertIn("greet/c.wav", err)
        self.assertIn("silent", err)

    @unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
    def test_the_script_runs_from_another_directory_with_spaces_in_every_path(self):
        write_recipes(self.recipes, lambda s: "%s/c.wav" % s)
        cands = self.make_candidates(burst(700.0, 0.4, amp=0.2))
        elsewhere = os.path.join(self.tmp, "some other dir")
        os.makedirs(elsewhere)
        done = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sounds", "build_pack.py"),
                               "--check-recipes", "--recipes", self.recipes, "--candidates", cands],
                              cwd=elsewhere, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("clips ok", done.stdout)
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: FAIL, `ModuleNotFoundError: No module named 'report'` (raised while importing `build_pack`)

- [ ] **Step 3: Write the implementation**

**Create `tools/sounds/report.py`**

```python
"""The loudness report: every slot of every built set against the targets of spec section 2."""
from __future__ import annotations

from collections import namedtuple

import loudness
from pipeline import TARGETS, TP_CEILING, read_back
from recipe import SLOTS

TP_SLACK_DB = 0.05      # 16-bit rounding can move the true peak by a few thousandths of a dB
MIN_SECONDS = 0.05

Row = namedtuple("Row", "slot kind lufs target rms_db tp_db seconds limit_db problems")


def check(slot, m):
    """The ways measurement `m` of `slot` misses its targets, as short sentences. Empty means pass."""
    info = SLOTS[slot]
    target, tol = TARGETS[info.kind]
    out = []
    if abs(m.lufs - target) > tol:
        out.append("loudness %.1f LUFS is not %.1f +-%.1f" % (m.lufs, target, tol))
    if m.tp_db > TP_CEILING + TP_SLACK_DB:
        out.append("true peak %.2f dBTP is over %.1f" % (m.tp_db, TP_CEILING))
    if m.seconds > info.max_len + 1.0 / 48000:
        out.append("%.2f s is longer than %.1f s" % (m.seconds, info.max_len))
    if m.seconds < MIN_SECONDS:
        out.append("%.3f s is shorter than %.2f s" % (m.seconds, MIN_SECONDS))
    return out


def measure_set(built, out_dir):
    """Rows for one built set, measured from the WAV files as written."""
    rows = []
    for b in built:
        info = SLOTS[b.slot]
        m = loudness.measure(read_back(out_dir, b.slot))
        rows.append(Row(b.slot, info.kind, m.lufs, TARGETS[info.kind][0], m.rms_db, m.tp_db,
                        m.seconds, b.limit_db, check(b.slot, m)))
    return rows


def failures(results):
    """['set/slot: problem; problem', ...] over all sets."""
    return ["%s/%s: %s" % (name, r.slot, "; ".join(r.problems))
            for name, rows in results.items() for r in rows if r.problems]


def render(results):
    """Markdown. `results` maps set name to its Rows."""
    total = sum(len(rows) for rows in results.values())
    bad = failures(results)
    lines = ["# Sound sets: loudness report", "",
             "%d of %d files meet their targets." % (total - len(bad), total), "",
             "Targets: cat moments %.0f LUFS short-term (+-%.1f LU), ticks %.0f (+-%.1f LU); true peak "
             "at or under %.0f dBTP; length up to 1.5 s (sleep 3 s, ticks 0.4 s). Short-term is the "
             "loudest 400 ms block. \"Limiter\" is the deepest gain reduction the peak limiter applied."
             % (TARGETS["cat"][0], TARGETS["cat"][1], TARGETS["tick"][0], TARGETS["tick"][1],
                TP_CEILING), ""]
    for name, rows in results.items():
        passed = sum(1 for r in rows if not r.problems)
        lines += ["## %s: %d of %d pass" % (name, passed, len(rows)), "",
                  "| slot | kind | LUFS-S | RMS dBFS | TP dBTP | length s | limiter dB | result |",
                  "|---|---|---|---|---|---|---|---|"]
        for r in rows:
            res = "pass" if not r.problems else "FAIL: " + "; ".join(r.problems)
            lines.append("| %s | %s | %.1f | %.1f | %.2f | %.2f | %.1f | %s |"
                         % (r.slot, r.kind, r.lufs, r.rms_db, r.tp_db, r.seconds, r.limit_db, res))
        lines.append("")
    return "\n".join(lines)
```


**Create `tools/sounds/build_pack.py`**

```python
#!/usr/bin/env python3
"""Build NotchMeow's sound sets from the recipes in design/sounds/sets/.

  build_pack.py --set studio --candidates DIR --out DIR   one set, 28 WAVs in --out
  build_pack.py --all [--report]                          all four sets under .claude/sounds/build
  build_pack.py --check-recipes                           validate the recipes (and the clips, if found)

--report also writes report.md next to the WAVs and exits 1 when any file misses its targets.
Needs Python 3 and, for decoding the candidate clips, macOS afconvert. Nothing else.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))

import pipeline  # noqa: E402
import recipe  # noqa: E402
import report  # noqa: E402
from audio_io import AfconvertLoader  # noqa: E402

SETS_DIR = os.path.join(ROOT, "design", "sounds", "sets")
BUILD_DIR = os.path.join(ROOT, ".claude", "sounds", "build")


def find_candidates(explicit=None, root=ROOT):
    """The candidates folder: --candidates, $NM_SOUND_CANDIDATES, <root>/.claude/sounds/candidates,
    then the same folder in the main checkout (a git worktree does not carry the git-ignored clips).
    None when there is none."""
    wanted = [explicit] if explicit else [os.environ.get("NM_SOUND_CANDIDATES"),
                                          os.path.join(root, ".claude", "sounds", "candidates")]
    for path in wanted:
        if path and os.path.isdir(path):
            return os.path.abspath(path)
    if explicit:
        return None
    try:
        common = subprocess.run(["git", "-C", root, "rev-parse", "--path-format=absolute",
                                 "--git-common-dir"], check=True, capture_output=True,
                                text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    path = os.path.join(os.path.dirname(common), ".claude", "sounds", "candidates")
    return path if os.path.isdir(path) else None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    what = ap.add_mutually_exclusive_group(required=True)
    what.add_argument("--set", choices=recipe.SET_NAMES)
    what.add_argument("--all", action="store_true")
    what.add_argument("--check-recipes", action="store_true")
    ap.add_argument("--candidates", help="folder of candidate clips (default: .claude/sounds/candidates)")
    ap.add_argument("--out", help="output folder: the set's WAVs (--set) or the build root (--all)")
    ap.add_argument("--recipes", default=SETS_DIR, help="folder of set recipes")
    ap.add_argument("--report", action="store_true", help="write report.md and fail if targets are missed")
    args = ap.parse_args(argv)

    try:
        recipes = recipe.load_recipes(args.recipes)
    except (recipe.RecipeError, OSError) as e:
        print("recipe error: %s" % e, file=sys.stderr)
        return 2
    cands = find_candidates(args.candidates)

    if args.check_recipes:
        print("recipes ok: %d sets x %d slots" % (len(recipes), len(recipe.SLOTS)))
        if cands is None:
            print("candidates folder not found: the clip files were not checked")
            return 0
        gone = sorted({"%s: %s" % (n, s) for n, r in recipes.items()
                       for s in recipe.missing_sources(r, cands)})
        for line in gone:
            print("missing clip - " + line, file=sys.stderr)
        print("clips ok in %s" % cands if not gone else "%d missing clip(s)" % len(gone))
        return 2 if gone else 0

    if cands is None:
        print("candidates folder not found; pass --candidates or set NM_SOUND_CANDIDATES", file=sys.stderr)
        return 2
    chosen = list(recipes) if args.all else [args.set]
    root_out = os.path.abspath(args.out or BUILD_DIR) if args.all else None
    loader, cache, results = AfconvertLoader(cands), {}, OrderedDict()
    for name in chosen:
        out = os.path.join(root_out, name) if args.all else os.path.abspath(args.out or os.path.join(BUILD_DIR, name))
        gone = recipe.missing_sources(recipes[name], cands)
        if gone:
            print("%s: missing clips in %s: %s" % (name, cands, ", ".join(gone)), file=sys.stderr)
            return 2
        try:
            built = pipeline.build_set(recipes[name], loader, out, cache)
        except pipeline.SourceError as e:
            print("%s: %s" % (name, e), file=sys.stderr)
            return 2
        print("built %s: %d files in %s" % (name, len(built), out))
        if args.report:
            results[name] = report.measure_set(built, out)
    if args.report:
        target = os.path.join(root_out if args.all else out, "report.md")
        with open(target, "w", encoding="utf-8") as f:
            f.write(report.render(results) + "\n")
        bad = report.failures(results)
        total = sum(len(r) for r in results.values())
        print("report: %s (%d of %d files meet their targets)" % (target, total - len(bad), total))
        for line in bad:
            print("FAIL " + line, file=sys.stderr)
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
```


Make the command executable:

```bash
chmod +x tools/sounds/build_pack.py
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 87 tests`, `OK` (about 30 seconds)

- [ ] **Step 5: Commit**

```bash
git add tools/sounds/report.py tools/sounds/build_pack.py tests/test_sound_build.py
git commit -m "feat(sounds): loudness report and build_pack command line" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 9: The recipes for the four sets

The shared entries and the four sets, from the "Source choices" section above; every entry carries a `note` saying why. `_shared.json` holds the 13 slots all sets share (ten ticks, yawn, work, gulp); each set file holds its own 15 (greet, love, annoyed, dizzy, slap, finish, error, approval, question, proud, wink, sleep, think, search, rate), with the set's pitch shift: Studio 0, Steff's cat 0, Kitten +1.5 (inside the spec's +1 to +2), Best of -1.0. The tests pin the set identities (Studio is Emi and MBPL, plus Trautwein's purr for sleep; Kitten is Oscar only; and so on) so a later edit cannot quietly change what a set is.

**Files:**
- Create: `design/sounds/sets/_shared.json`
- Create: `design/sounds/sets/studio.json`
- Create: `design/sounds/sets/steff.json`
- Create: `design/sounds/sets/kitten.json`
- Create: `design/sounds/sets/bestof.json`
- Modify: `tests/test_sound_build.py` (append)

**Interfaces:**
- Consumes: `recipe.load_recipes`, `recipe.missing_sources`, `build_pack.find_candidates`.
- Produces: the five JSON files in the format described under "Recipe format" above; Task 10's page reads their titles (`Studio`, `Steff's cat`, `Kitten`, `Best of`) through `recipe.load_recipes`.

- [ ] **Step 1: Write the failing tests** (they include Review Focus 4: no excluded clip in any set)

**Append to `tests/test_sound_build.py`**

```python
SHARED_SLOTS_IN_ORDER = [s for s in recipe.SLOTS if s in SHARED_SLOTS]
SETS_DIR = os.path.join(ROOT, "design", "sounds", "sets")
CANDIDATES = build_pack.find_candidates()


def own_files(s):
    """The recorded clips a set picked itself (not the shared ticks and fill-ins)."""
    return [e.source for e in s.entries.values() if not e.shared and not e.source.startswith("synth:")]


class TestRealRecipes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sets = recipe.load_recipes(SETS_DIR)

    def test_four_complete_sets_of_28_slots(self):
        self.assertEqual(list(self.sets), ["studio", "steff", "kitten", "bestof"])
        for s in self.sets.values():
            self.assertEqual(list(s.entries), list(recipe.SLOTS))

    def test_the_ticks_and_fill_ins_are_shared_and_identical(self):
        for s in self.sets.values():
            self.assertEqual([slot for slot, e in s.entries.items() if e.shared], SHARED_SLOTS_IN_ORDER)
            for slot in SHARED_SLOTS:
                self.assertEqual(s.entries[slot], self.sets["studio"].entries[slot])
        ticks = [slot for slot, info in recipe.SLOTS.items() if info.kind == "tick"]
        self.assertTrue(set(ticks) <= set(SHARED_SLOTS))

    def test_every_own_entry_says_why_it_was_chosen(self):
        for name, s in self.sets.items():
            own = [e for e in s.entries.values() if not e.shared]
            self.assertEqual(len(own), 15, name)
            self.assertTrue(all(len(e.note) > 20 for e in own), name)
            self.assertTrue(all(e.note for e in s.entries.values()), name)

    def test_only_the_search_slot_is_made_in_code_inside_a_set(self):
        for name, s in self.sets.items():
            synths = {e.source for e in s.entries.values() if not e.shared and e.source.startswith("synth:")}
            self.assertLessEqual(synths, {"synth:search"}, name)

    def test_studio_is_emi_and_the_mbpl_trills_with_one_studio_purr_for_sleep(self):
        s = self.sets["studio"]
        files = own_files(s)
        outside = [f for f in files if not (os.path.basename(f).startswith("bsb-") or f.endswith("-MBPL.mp3"))]
        self.assertEqual(outside, ["sleep/fs-260881-Trautwein.mp3"])      # Emi has no snore or purr to use
        self.assertTrue(any(os.path.basename(f).startswith("bsb-") for f in files))
        self.assertTrue(any(f.endswith("-MBPL.mp3") for f in files))
        self.assertEqual(s.pitch_st, 0.0)

    def test_steffs_cat_is_steffcaffrey_with_gaps_from_mbpl_and_sadiquecat(self):
        files = own_files(self.sets["steff"])
        for f in files:
            self.assertTrue(f.endswith(("-steffcaffrey.mp3", "-MBPL.mp3", "-Sadiquecat.mp3")), f)
        self.assertGreaterEqual(sum(f.endswith("-steffcaffrey.mp3") for f in files), 6)

    def test_the_kitten_is_oscar_only_and_up_one_to_two_semitones(self):
        files = own_files(self.sets["kitten"])
        self.assertTrue(all("-Department64.mp3" in f for f in files), files)
        self.assertTrue(1.0 <= self.sets["kitten"].pitch_st <= 2.0)

    def test_best_of_mixes_voices_under_one_shared_shift(self):
        s = self.sets["bestof"]
        voices = {os.path.basename(f).rsplit("-", 1)[-1] for f in own_files(s)}
        self.assertGreaterEqual(len(voices), 5)
        self.assertNotEqual(s.pitch_st, 0.0)
        self.assertTrue(all(abs(e.pitch_st) <= 3.0 for e in s.entries.values()))

    def test_no_set_uses_an_excluded_clip(self):
        for name, s in self.sets.items():
            for e in s.entries.values():
                low = e.source.lower()
                self.assertFalse("qubodup" in low or "lukey" in low or "857748" in low or "732521" in low, (name, e.slot))

    def test_clips_longer_than_a_few_seconds_are_always_cut_to_an_explicit_window(self):
        long_clips = ("dreamstobecome", "Tyler31898", "Rudenko", "kyles", "itinerantmonk108", "Trautwein",
                      "megrez7274", "Daphne", "ArcticWanderer", "730097")
        for name, s in self.sets.items():
            for e in s.entries.values():
                if any(tag in e.source for tag in long_clips):
                    self.assertIsNotNone(e.start, (name, e.slot))
                    self.assertIsNotNone(e.end, (name, e.slot))
                    self.assertLessEqual(e.end - e.start, 3.0, (name, e.slot))

    @unittest.skipUnless(CANDIDATES, "no .claude/sounds/candidates folder: local-only check")
    def test_every_clip_the_recipes_name_is_in_the_candidates_folder(self):
        for name, s in self.sets.items():
            self.assertEqual(recipe.missing_sources(s, CANDIDATES), [], name)
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest tests.test_sound_build.TestRealRecipes`
Expected: FAIL, `FileNotFoundError` for `design/sounds/sets/_shared.json`

- [ ] **Step 3: Write the recipes**

**Create `design/sounds/sets/_shared.json`**

```json
{
  "set": "_shared",
  "title": "Shared: ticks and made-in-code fill-ins, identical in every set",
  "entries": [
    {"slot": "yawn", "source": "synth:yawn", "mood": "calm", "signature": false, "note": "Made in code. The only real yawn found (Daphne_in_Wonderland, 106 s of purring) has no burst in the energy survey that isolates a yawn: steady purr, band above 1 kHz at -50 dB or lower."},
    {"slot": "work", "source": "synth:work", "mood": "calm", "signature": false, "note": "Made in code: three soft fabric pats at 2 Hz. The real clip (ArcticWanderer) is purr and kneading together, with no clean pat to cut."},
    {"slot": "gulp", "source": "gulp/fs-730097-Sadiquecat.mp3", "start": 0.0, "end": 0.9, "hp_hz": 1000, "mood": "happy", "signature": false, "note": "Foley, same in every set. Sadiquecat's paw licking, the first 0.9 s, high-passed at 1 kHz (below that the clip is body and room noise). kyles' milk lapping was tried first and dropped: its laps are so spiky the limiter had to take off 10 dB."},
    {"slot": "approve", "source": "approve/fs-487999-BenDrain.mp3", "mood": "none", "signature": false, "note": "Soft cardboard paw stamp. The bell (connersaw8) stays free for tick."},
    {"slot": "peek", "source": "peek/fs-541360-JoshuaPomeroy.mp3", "mood": "none", "signature": false, "note": "Tiny sleigh-bell jingle, a collar bell."},
    {"slot": "open", "source": "open/fs-364740-newagesoup.mp3", "start": 0.22, "end": 0.62, "mood": "none", "signature": false, "note": "Box flap: the impact is at 0.26 s, then rustle. Cut to 0.4 s."},
    {"slot": "close", "source": "close/fs-320847-Mafon2.mp3", "start": 0.2, "end": 0.56, "mood": "none", "signature": false, "note": "Soft thunk; the impact is at 0.26 s."},
    {"slot": "hover", "source": "hover/fs-371274-Mafon2.mp3", "mood": "none", "signature": false, "note": "Bead into a water bowl."},
    {"slot": "blip", "source": "synth:blip", "mood": "none", "signature": false, "note": "Made in code. The recorded candidate (qubodup, Cute Computer Squeak) is excluded from every set."},
    {"slot": "tick", "source": "tick/fs-371278-Mafon2.mp3", "mood": "none", "signature": false, "note": "Ceramic ball click."},
    {"slot": "send", "source": "send/fs-402453-jimmyfisher.mp3", "mood": "none", "signature": false, "note": "Kibble rattle."},
    {"slot": "attach", "source": "synth:clink", "mood": "none", "signature": false, "note": "Made in code: collar-tag clink, two inharmonic partials at 3.2 and 5.3 kHz."},
    {"slot": "pop", "source": "pop/fs-258269-jcallison.mp3", "mood": "none", "signature": false, "note": "Soft mouth pop."}
  ]
}
```


**Create `design/sounds/sets/studio.json`**

```json
{
  "set": "studio",
  "title": "Studio",
  "pitch_st": 0.0,
  "entries": [
    {"slot": "greet", "source": "greet/fs-668820-MBPL.mp3", "mood": "happy", "signature": true, "note": "MBPL trill 3, a soft short trill (trill slot)."},
    {"slot": "love", "source": "dizzy/fs-668822-MBPL.mp3", "start": 0.02, "end": 0.6, "pitch_st": 2.0, "mood": "happy", "signature": true, "note": "MBPL trill 1, first two syllables, up two semitones (trill slot). Emi has no purr in the download."},
    {"slot": "annoyed", "source": "annoyed/bsb-s1885.mp3", "start": 0.52, "end": 1.48, "mood": "upset", "signature": false, "note": "Emi's growl: the plateau and the natural drop, 0.96 s; the first half second is a quiet build-up."},
    {"slot": "dizzy", "source": "dizzy/fs-668822-MBPL.mp3", "effects": [{"type": "wobble", "rate_hz": 5.0, "depth_st": 1.0}], "mood": "upset", "signature": false, "note": "MBPL trill 1 with the 5 Hz, +-1 semitone wobble."},
    {"slot": "slap", "source": "slap/bsb-s1899.mp3", "start": 0.03, "end": 0.27, "pitch_st": -2.0, "mood": "calm", "signature": false, "note": "Emi meow 11, first syllable only, down two semitones."},
    {"slot": "finish", "source": "finish/fs-668825-MBPL.mp3", "mood": "happy", "signature": true, "note": "MBPL trill 4, soft (trill slot)."},
    {"slot": "error", "source": "error/bsb-s1476.mp3", "effects": [{"type": "glide", "from_st": 0.0, "to_st": -4.0}], "mood": "upset", "signature": true, "note": "Emi little meow 6 with a falling pitch ramp (0 to -4 semitones)."},
    {"slot": "approval", "source": "approval/bsb-s1472.mp3", "mood": "attention", "signature": true, "note": "Emi little meow 2, asking for attention."},
    {"slot": "question", "source": "question/fs-668824-MBPL.mp3", "effects": [{"type": "glide", "from_st": 0.0, "to_st": 3.0}], "mood": "attention", "signature": true, "note": "MBPL trill 5 with a rising pitch ramp (0 to +3 semitones) so it asks (trill slot)."},
    {"slot": "proud", "source": "slap/bsb-s1899.mp3", "pitch_st": 3.0, "mood": "happy", "signature": false, "note": "Emi meow 11, whole, up three semitones."},
    {"slot": "wink", "source": "error/bsb-s1476.mp3", "start": 0.05, "end": 0.4, "pitch_st": 3.0, "mood": "happy", "signature": false, "note": "Emi little meow 6, the first 0.35 s, up three semitones."},
    {"slot": "sleep", "source": "sleep/fs-260881-Trautwein.mp3", "start": 4.0, "end": 6.8, "mood": "calm", "signature": false, "note": "Trautwein's studio purr, a steady 2.8 s (Emi has no snore). One soft purr, not a loop."},
    {"slot": "think", "source": "approval/bsb-s1472.mp3", "start": 0.1, "end": 0.75, "pitch_st": -3.0, "mood": "attention", "signature": false, "note": "Emi little meow 2, the low middle, down three semitones: a questioning 'hm'."},
    {"slot": "search", "source": "synth:search", "mood": "attention", "signature": false, "note": "Made in code: 12 Hz chatter."},
    {"slot": "rate", "source": "approval/bsb-s1472.mp3", "start": 0.3, "end": 0.9, "pitch_st": -2.0, "effects": [{"type": "thump"}], "mood": "upset", "signature": false, "note": "Emi little meow 2, the tail, down two semitones, then the tail thump."}
  ]
}
```


**Create `design/sounds/sets/steff.json`**

```json
{
  "set": "steff",
  "title": "Steff's cat",
  "pitch_st": 0.0,
  "entries": [
    {"slot": "greet", "source": "greet/fs-262306-steffcaffrey.mp3", "mood": "happy", "signature": true, "note": "Cat_Twit1, rated 5.0: a happy twit. The source is quiet (peak -17 dBFS); the build lifts it."},
    {"slot": "love", "source": "love/fs-262307-steffcaffrey.mp3", "mood": "happy", "signature": true, "note": "Happy Purr/Twitter2, the same cat as the greeting: a warm purr-twit."},
    {"slot": "annoyed", "source": "rate/fs-730098-Sadiquecat.mp3", "start": 0.0, "end": 0.7, "pitch_st": -2.0, "mood": "upset", "signature": false, "note": "Sadiquecat's impatient meow, the first 0.7 s, down two semitones to make it grumbly."},
    {"slot": "dizzy", "source": "dizzy/fs-668822-MBPL.mp3", "effects": [{"type": "wobble", "rate_hz": 5.0, "depth_st": 1.0}], "mood": "upset", "signature": false, "note": "MBPL trill 1 with the 5 Hz, +-1 semitone wobble."},
    {"slot": "slap", "source": "slap/fs-262309-steffcaffrey.mp3", "mood": "calm", "signature": false, "note": "Cat Purr/Twit4, rated 4.9, the shortest clip of this cat (0.37 s): a quick mrp."},
    {"slot": "finish", "source": "finish/fs-415107-steffcaffrey.mp3", "mood": "happy", "signature": true, "note": "catwhirr, a happy whirr at food: the closest this cat has to a pleased, done sound."},
    {"slot": "error", "source": "rate/fs-730098-Sadiquecat.mp3", "start": 0.55, "end": 1.18, "effects": [{"type": "glide", "from_st": 0.0, "to_st": -4.0}], "mood": "upset", "signature": true, "note": "Sadiquecat's meow, the falling second half, with a further falling pitch ramp (0 to -4 semitones)."},
    {"slot": "approval", "source": "greet/fs-844502-Sadiquecat.mp3", "mood": "attention", "signature": true, "note": "Pearl's 'I'm here' mrrow, from Sadiquecat."},
    {"slot": "question", "source": "question/fs-262310-steffcaffrey.mp3", "effects": [{"type": "glide", "from_st": -1.0, "to_st": 4.0}], "mood": "attention", "signature": true, "note": "Cat Purr/Twit5 falls on its own, so a rising pitch ramp (-1 to +4 semitones) makes it ask."},
    {"slot": "proud", "source": "proud/fs-262311-steffcaffrey.mp3", "mood": "happy", "signature": false, "note": "Cat Purr/Twit6, rated 5.0: a short, chesty twit."},
    {"slot": "wink", "source": "wink/fs-262313-steffcaffrey.mp3", "mood": "happy", "signature": false, "note": "Cat Meow2: one small meow, the same cat as the greeting."},
    {"slot": "sleep", "source": "sleep/fs-752418-Sadiquecat.mp3", "start": 1.2, "end": 2.6, "mood": "calm", "signature": false, "note": "Pearl's snore: one burst at 1.55 to 1.95 s, with its breath before and after."},
    {"slot": "think", "source": "greet/fs-668820-MBPL.mp3", "pitch_st": -3.0, "mood": "attention", "signature": false, "note": "MBPL trill 3, down three semitones: a soft 'hm'."},
    {"slot": "search", "source": "synth:search", "mood": "attention", "signature": false, "note": "Made in code: 12 Hz chatter."},
    {"slot": "rate", "source": "rate/fs-730098-Sadiquecat.mp3", "start": 0.0, "end": 0.6, "effects": [{"type": "thump"}], "mood": "upset", "signature": false, "note": "Sadiquecat's impatient meow, the first 0.6 s, then the tail thump."}
  ]
}
```


**Create `design/sounds/sets/kitten.json`**

```json
{
  "set": "kitten",
  "title": "Kitten",
  "pitch_st": 1.5,
  "entries": [
    {"slot": "greet", "source": "love/fs-64017-Department64.mp3", "start": 0.0, "end": 0.42, "pitch_st": 1.0, "mood": "happy", "signature": true, "note": "kitten22, the first 0.4 s, up one more semitone."},
    {"slot": "love", "source": "love/fs-64017-Department64.mp3", "mood": "happy", "signature": true, "note": "kitten22, a friendly purr-meow."},
    {"slot": "annoyed", "source": "annoyed/fs-64008-Department64.mp3", "mood": "upset", "signature": false, "note": "kitten13, the offended half-growl."},
    {"slot": "dizzy", "source": "dizzy/fs-64007-Department64.mp3", "effects": [{"type": "wobble", "rate_hz": 5.0, "depth_st": 1.0}], "mood": "upset", "signature": false, "note": "kitten12, a short howl, with the 5 Hz wobble."},
    {"slot": "slap", "source": "dizzy/fs-64007-Department64.mp3", "start": 0.0, "end": 0.3, "pitch_st": -1.0, "mood": "calm", "signature": false, "note": "kitten12, the first 0.3 s, down one semitone."},
    {"slot": "finish", "source": "rate/fs-64011-Department64.mp3", "start": 0.05, "end": 0.65, "effects": [{"type": "glide", "from_st": 0.0, "to_st": 2.0}], "mood": "happy", "signature": true, "note": "kitten16, its loud first meow, with a rising pitch ramp (0 to +2 semitones)."},
    {"slot": "error", "source": "error/fs-64015-Department64.mp3", "effects": [{"type": "glide", "from_st": 0.0, "to_st": -4.0}], "mood": "upset", "signature": true, "note": "kitten20, the sad howl-meow, with a falling pitch ramp (0 to -4 semitones)."},
    {"slot": "approval", "source": "approval/fs-64005-Department64.mp3", "mood": "attention", "signature": true, "note": "kitten10, a friendly alert meow."},
    {"slot": "question", "source": "error/fs-64015-Department64.mp3", "start": 0.1, "end": 0.6, "effects": [{"type": "glide", "from_st": -2.0, "to_st": 4.0}], "mood": "attention", "signature": true, "note": "kitten20, its middle, with a rising pitch ramp (-2 to +4 semitones)."},
    {"slot": "proud", "source": "approval/fs-64005-Department64.mp3", "start": 0.0, "end": 0.4, "pitch_st": 2.0, "mood": "happy", "signature": false, "note": "kitten10, the first 0.4 s, up two semitones."},
    {"slot": "wink", "source": "annoyed/fs-64008-Department64.mp3", "start": 0.45, "end": 0.8, "pitch_st": 2.0, "mood": "happy", "signature": false, "note": "kitten13, the last third, up two semitones."},
    {"slot": "sleep", "source": "sleep/fs-64004-Department64.mp3", "mood": "calm", "signature": false, "note": "Buddha Purr, close-mic."},
    {"slot": "think", "source": "rate/fs-64011-Department64.mp3", "start": 0.55, "end": 0.95, "pitch_st": -2.0, "mood": "attention", "signature": false, "note": "kitten16, the low tail, down two semitones: 'hmm'."},
    {"slot": "search", "source": "synth:search", "mood": "attention", "signature": false, "note": "Made in code: 12 Hz chatter."},
    {"slot": "rate", "source": "rate/fs-64012-Department64.mp3", "effects": [{"type": "thump"}], "mood": "upset", "signature": false, "note": "kitten17, getting frustrated, then the tail thump."}
  ]
}
```


**Create `design/sounds/sets/bestof.json`**

```json
{
  "set": "bestof",
  "title": "Best of",
  "pitch_st": -1.0,
  "entries": [
    {"slot": "greet", "source": "greet/fs-262306-steffcaffrey.mp3", "pitch_st": 3.0, "mood": "happy", "signature": true, "note": "Cat_Twit1, rated 5.0; up three semitones to sit with the other voices (about 450 Hz)."},
    {"slot": "love", "source": "love/fs-436542-Mafon2.mp3", "mood": "happy", "signature": true, "note": "Cat short purr, rated 4.9."},
    {"slot": "annoyed", "source": "annoyed/fs-64008-Department64.mp3", "mood": "upset", "signature": false, "note": "kitten13: grumbly, not scary."},
    {"slot": "dizzy", "source": "dizzy/fs-668822-MBPL.mp3", "effects": [{"type": "wobble", "rate_hz": 5.0, "depth_st": 1.0}], "mood": "upset", "signature": false, "note": "MBPL trill 1 with the 5 Hz, +-1 semitone wobble."},
    {"slot": "slap", "source": "slap/fs-262309-steffcaffrey.mp3", "pitch_st": 3.0, "mood": "calm", "signature": false, "note": "Cat Purr/Twit4, rated 4.9; up three semitones."},
    {"slot": "finish", "source": "finish/fs-415107-steffcaffrey.mp3", "mood": "happy", "signature": true, "note": "catwhirr, a happy whirr at food: the closest this cat has to a pleased, done sound."},
    {"slot": "error", "source": "error/fs-448084-Breviceps.mp3", "pitch_st": -3.0, "effects": [{"type": "glide", "from_st": 0.0, "to_st": -3.0}], "mood": "upset", "signature": true, "note": "Cute Kitten Meow, rated 4.8; down three semitones, with a falling pitch ramp (0 to -3 semitones)."},
    {"slot": "approval", "source": "approval/bsb-s1472.mp3", "mood": "attention", "signature": true, "note": "Emi little meow 2, a studio recording."},
    {"slot": "question", "source": "question/fs-686775-nathan-osman.mp3", "pitch_st": -3.0, "effects": [{"type": "glide", "from_st": -1.0, "to_st": 4.0}], "mood": "attention", "signature": true, "note": "meow-1, rated 4.9; down three semitones, with a rising pitch ramp (-1 to +4 semitones)."},
    {"slot": "proud", "source": "proud/fs-451250-dreamstobecome.mp3", "start": 2.5, "end": 3.0, "mood": "happy", "signature": false, "note": "One contented chirp cut from the 7.8 s clip: the chirp rises at 2.6 s and ends by 3.0 s (the next ones are at 4.9 and 6.4 s)."},
    {"slot": "wink", "source": "wink/fs-436541-Mafon2.mp3", "pitch_st": -3.0, "mood": "happy", "signature": false, "note": "Cat Meow, rated 4.7; down three semitones."},
    {"slot": "sleep", "source": "sleep/fs-752418-Sadiquecat.mp3", "start": 1.2, "end": 2.6, "mood": "calm", "signature": false, "note": "Pearl's snore: one burst at 1.55 to 1.95 s, with its breath before and after."},
    {"slot": "think", "source": "dizzy/fs-730102-Sadiquecat.mp3", "start": 0.3, "end": 1.2, "mood": "attention", "signature": false, "note": "Cat MmRrm noise, the steady middle: it reads as 'hmm'."},
    {"slot": "search", "source": "search/fs-499362-16H_Panska_Rudenko_Angelika.mp3", "start": 12.85, "end": 13.75, "hp_hz": 900, "mood": "attention", "signature": false, "note": "Cat_Hunting, three chatter bursts (at 12.95, 13.35 and 13.65 s). High-passed at 900 Hz: the clip is mostly low rumble."},
    {"slot": "rate", "source": "rate/fs-64012-Department64.mp3", "effects": [{"type": "thump"}], "mood": "upset", "signature": false, "note": "kitten17, getting frustrated, then the tail thump."}
  ]
}
```


- [ ] **Step 4: Run the tests to verify they pass, and check the clips if you have them**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 98 tests`, `OK`. One test is skipped when no candidates folder can be found; in a worktree of the main checkout the folder is found, so nothing is skipped.

Run: `python3 tools/sounds/build_pack.py --check-recipes`
Expected: `recipes ok: 4 sets x 28 slots`, then `clips ok in <the candidates folder>` (or `candidates folder not found: the clip files were not checked` when there is none)

- [ ] **Step 5: Commit**

```bash
git add design/sounds/sets/_shared.json design/sounds/sets/studio.json design/sounds/sets/steff.json design/sounds/sets/kitten.json design/sounds/sets/bestof.json tests/test_sound_build.py
git commit -m "feat(sounds): recipes for the four sound sets" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 10: The audition page

A static page, `design/sounds/audition.html`: one row per slot (28, cat moments then ticks), one column per set (4), each cell a Play button for `../../.claude/sounds/build/<set>/<slot>.wav` plus the clip's length once its metadata loads. Each row shows the slot, when it plays, its mood and whether it has the signature (ticks: no layers). Each set column has a "Play the whole set" run-through (28 in order, 450 ms between sounds; the button turns into Stop). One sound plays at a time. A file that fails to load disables its button and shows "missing"; a notice then tells the owner to run `python3 tools/sounds/build_pack.py --all --report`. Colours, type and card style follow `design/sounds/listen.html` (light and dark, a theme switch remembered in `localStorage` inside try/catch). No scripts from outside, no network. The slot table is embedded as a JSON block so a test can check it against `recipe.SLOTS` and the page cannot drift from the build.

**Files:**
- Create: `design/sounds/audition.html`
- Modify: `tests/test_sound_build.py` (append)

**Interfaces:**
- Consumes: `recipe.SLOTS`, `recipe.load_recipes` (titles), `build_pack.BUILD_DIR`.
- Produces: the page. It reads the WAVs Task 8's command writes, nothing else.

- [ ] **Step 1: Write the failing tests**

**Append to `tests/test_sound_build.py`**

```python
class TestAuditionPage(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(ROOT, "design", "sounds", "audition.html")
        with open(self.path, encoding="utf-8") as f:
            self.html = f.read()
        self.data = json.loads(re.search(r'<script type="application/json" id="data">(.*?)</script>',
                                         self.html, re.S).group(1))

    def test_the_slot_table_is_the_builds(self):
        page = [(s["slot"], s["kind"], s["mood"], s["signature"], s["dark"]) for s in self.data["slots"]]
        build = [(i.name, i.kind, i.mood, i.signature, i.dark) for i in recipe.SLOTS.values()]
        self.assertEqual(page, build)
        self.assertTrue(all(s["when"] for s in self.data["slots"]))

    def test_the_four_sets_are_the_recipes(self):
        sets = recipe.load_recipes(os.path.join(ROOT, "design", "sounds", "sets"))
        self.assertEqual([s["id"] for s in self.data["sets"]], list(sets))
        self.assertEqual([s["title"] for s in self.data["sets"]], [s.title for s in sets.values()])

    def test_it_loads_nothing_from_the_network(self):
        self.assertNotIn("<script src", self.html)
        self.assertIsNone(re.search(r"""(?:src|href)\s*=\s*["']?(?:https?:)?//""", self.html))
        self.assertNotIn("http://", self.html)
        self.assertNotIn("https://", self.html)
        self.assertIsNone(re.search(r"\bfetch\(|XMLHttpRequest|@import", self.html))

    def test_it_plays_the_build_folder_from_file_urls(self):
        base = re.search(r'var BASE = "([^"]+)"', self.html).group(1)
        self.assertEqual(os.path.normpath(os.path.join(os.path.dirname(self.path), base)),
                         os.path.normpath(build_pack.BUILD_DIR))
        self.assertIn('BASE + set.id + "/" + s.slot + ".wav"', self.html)

    def test_it_tells_the_owner_how_to_build_when_files_are_missing(self):
        self.assertIn("python3 tools/sounds/build_pack.py --all --report", self.html)
        self.assertIn("Play the whole set", self.html)
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest tests.test_sound_build.TestAuditionPage`
Expected: FAIL, `FileNotFoundError` for `design/sounds/audition.html`

- [ ] **Step 3: Write the page**

**Create `design/sounds/audition.html`**

```html
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark light">
<title>NotchMeow sound sets</title>
<!--
  Audition page for the four sound sets (sub-project C, stage 1). Static: no scripts from anywhere,
  no network. It plays the WAVs that tools/sounds/build_pack.py wrote to .claude/sounds/build/, which is
  not in git, so build them first:  python3 tools/sounds/build_pack.py --all --report
  Works from file://. Colours, type and cards follow design/sounds/listen.html.
  The slot table in the JSON block below is checked against tools/sounds/recipe.py by
  tests/test_sound_build.py, so it cannot drift from the build.
-->
<style>
:root{--bg:#0f1012;--card:#17181b;--sub:#131417;--line:#2a2c31;--line2:#43464e;--ink:#ececee;--dim:#9a9ca3;--acc:#5EEAD4;--btn:#202227;--warn:#f2c46d;--bar:rgba(23,24,27,.94);color-scheme:dark}
@media (prefers-color-scheme:light){:root:not([data-theme="dark"]){--bg:#f3f3f5;--card:#ffffff;--sub:#f8f8fa;--line:#dcdde2;--line2:#b4b7bf;--ink:#17181b;--dim:#5b5e66;--acc:#0b7f71;--btn:#f0f1f3;--warn:#8a5a00;--bar:rgba(255,255,255,.94);color-scheme:light}}
:root[data-theme="light"]{--bg:#f3f3f5;--card:#ffffff;--sub:#f8f8fa;--line:#dcdde2;--line2:#b4b7bf;--ink:#17181b;--dim:#5b5e66;--acc:#0b7f71;--btn:#f0f1f3;--warn:#8a5a00;--bar:rgba(255,255,255,.94);color-scheme:light}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;background:var(--sub);border:1px solid var(--line);border-radius:6px;padding:0 5px}
.wrap{max-width:1200px;margin:0 auto;padding:24px 16px 40px}
.top{display:flex;gap:12px;align-items:flex-start;justify-content:space-between}
h1{font-size:22px;font-weight:600;margin:0 0 4px}
h2{font-size:17px;font-weight:600;margin:0}
.sub{color:var(--dim);margin:0 0 14px}
button{font:inherit;font-size:12px;color:var(--ink);background:var(--btn);border:1px solid var(--line);border-radius:8px;padding:4px 10px;cursor:pointer;line-height:1.5}
button:hover:not(:disabled){border-color:var(--line2)}
button:disabled{cursor:default;opacity:.5}
button.on{border-color:var(--acc);color:var(--acc)}
button:focus-visible{outline:2px solid var(--acc);outline-offset:2px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin:0 0 16px}
.panel p{margin:0}.panel p+p{margin-top:6px;color:var(--dim);font-size:13px}
.warn{border-color:var(--warn)}
.scroll{overflow-x:auto;border:1px solid var(--line);border-radius:16px;background:var(--card)}
table{border-collapse:collapse;width:100%;min-width:760px}
th,td{padding:8px 12px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}
thead th{position:sticky;top:0;background:var(--card);z-index:2;border-bottom:1px solid var(--line2)}
tbody tr:last-child td{border-bottom:0}
tbody th{font-weight:400}
th.slot{width:28%}
.set-h{display:flex;flex-direction:column;gap:6px;align-items:flex-start}
.set-h b{font-size:15px;font-weight:600}
.set-h span{color:var(--dim);font-size:12px;font-weight:400}
tr.group th{background:var(--sub);font-size:12px;color:var(--dim);text-transform:uppercase;letter-spacing:.04em}
.name{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-weight:600}
.when{color:var(--dim);font-size:13px}
.chips{display:flex;flex-wrap:wrap;gap:4px;margin-top:4px}
.chip{font-size:11px;color:var(--dim);border:1px solid var(--line);border-radius:999px;padding:0 8px}
.chip.sig{border-color:var(--acc);color:var(--acc)}
.cell{display:flex;align-items:center;gap:8px;min-height:30px}
.cell .len{color:var(--dim);font-size:12px}
.cell.missing .len{color:var(--warn)}
.cell.now button{border-color:var(--acc);color:var(--acc);background:var(--sub)}
.bar{position:sticky;bottom:0;z-index:5;background:var(--bar);border-top:1px solid var(--line);-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px)}
.bar-in{max-width:1200px;margin:0 auto;padding:10px 16px;font-size:13px;color:var(--dim)}
</style></head><body>
<div class="wrap">
<div class="top">
<div>
<h1>NotchMeow sound sets</h1>
<p class="sub">Four complete sets of the 28 sounds. They differ only in the cat's voice; the ticks and the made-in-code fill-ins are the same in all four. Listen, then pick one set: that set ships.</p>
</div>
<button id="theme" type="button" aria-label="Switch colour theme">Light</button>
</div>

<div class="panel" id="missing" hidden role="alert">
<p><b id="missing-n"></b> sound files are missing. Build the sets, then reload this page:</p>
<p><code>python3 tools/sounds/build_pack.py --all --report</code></p>
</div>

<div class="panel" role="note">
<p>Each cat moment is the cat sound plus a short <b>touch</b> in its mood, and some also get the <b>signature</b> (collar-bell sparkle). Ticks get neither. The per-cat voice (pitch offset) and the chattiness volume are applied in the app at play time, so they are not in these files.</p>
<p>"Play the whole set" runs through all 28 with a short gap. Sounds play from <code>.claude/sounds/build/</code>, which is not in git.</p>
</div>

<div class="scroll">
<table id="grid">
<thead><tr id="head"><th class="slot" scope="col">Slot</th></tr></thead>
</table>
</div>
</div>

<footer class="bar"><div class="bar-in" id="status" role="status" aria-live="polite">Looking for the built files…</div></footer>

<script type="application/json" id="data">
{"sets":[
{"id":"studio","title":"Studio","voice":"BigSoundBank's cat Emi, with MBPL's soft trills"},
{"id":"steff","title":"Steff's cat","voice":"steffcaffrey's cat; gaps from MBPL and Sadiquecat"},
{"id":"kitten","title":"Kitten","voice":"Department64's Oscar (kitten files, Buddha Purr), up 1.5 semitones"},
{"id":"bestof","title":"Best of","voice":"The strongest clip per slot, one shared pitch shift"}],
"slots":[
{"slot":"greet","kind":"cat","mood":"happy","signature":true,"dark":false,"when":"the greeting"},
{"slot":"love","kind":"cat","mood":"happy","signature":true,"dark":false,"when":"love emote, hover on the cat, a file drag starts"},
{"slot":"annoyed","kind":"cat","mood":"upset","signature":false,"dark":false,"when":"poked too often"},
{"slot":"dizzy","kind":"cat","mood":"upset","signature":false,"dark":false,"when":"dizzy after slaps"},
{"slot":"slap","kind":"cat","mood":"calm","signature":false,"dark":false,"when":"poked"},
{"slot":"finish","kind":"cat","mood":"happy","signature":true,"dark":false,"when":"agent finished"},
{"slot":"error","kind":"cat","mood":"upset","signature":true,"dark":true,"when":"agent error"},
{"slot":"approval","kind":"cat","mood":"attention","signature":true,"dark":false,"when":"an agent needs your approval"},
{"slot":"question","kind":"cat","mood":"attention","signature":true,"dark":false,"when":"an agent asks a question"},
{"slot":"proud","kind":"cat","mood":"happy","signature":false,"dark":false,"when":"proud emote"},
{"slot":"wink","kind":"cat","mood":"happy","signature":false,"dark":false,"when":"wink emote"},
{"slot":"yawn","kind":"cat","mood":"calm","signature":false,"dark":false,"when":"yawn emote"},
{"slot":"sleep","kind":"cat","mood":"calm","signature":false,"dark":false,"when":"falling asleep (one soft snore)"},
{"slot":"gulp","kind":"cat","mood":"happy","signature":false,"dark":false,"when":"catching a file"},
{"slot":"think","kind":"cat","mood":"attention","signature":false,"dark":false,"when":"a prompt is sent"},
{"slot":"search","kind":"cat","mood":"attention","signature":false,"dark":false,"when":"searching"},
{"slot":"work","kind":"cat","mood":"calm","signature":false,"dark":false,"when":"working (kneading pats)"},
{"slot":"rate","kind":"cat","mood":"upset","signature":false,"dark":false,"when":"rate-limited"},
{"slot":"approve","kind":"tick","mood":"none","signature":false,"dark":false,"when":"you approved an agent's request"},
{"slot":"peek","kind":"tick","mood":"none","signature":false,"dark":false,"when":"the island peeks"},
{"slot":"open","kind":"tick","mood":"none","signature":false,"dark":false,"when":"the island opens"},
{"slot":"close","kind":"tick","mood":"none","signature":false,"dark":false,"when":"the island closes"},
{"slot":"hover","kind":"tick","mood":"none","signature":false,"dark":false,"when":"hover"},
{"slot":"blip","kind":"tick","mood":"none","signature":false,"dark":false,"when":"small UI blip"},
{"slot":"tick","kind":"tick","mood":"none","signature":false,"dark":false,"when":"ticker tick"},
{"slot":"send","kind":"tick","mood":"none","signature":false,"dark":false,"when":"sending a chat message"},
{"slot":"attach","kind":"tick","mood":"none","signature":false,"dark":false,"when":"attaching a file"},
{"slot":"pop","kind":"tick","mood":"none","signature":false,"dark":false,"when":"popover pop"}]}
</script>

<script>
"use strict";
(function () {
  var BASE = "../../.claude/sounds/build/";
  var GAP_MS = 450;
  var DATA = JSON.parse(document.getElementById("data").textContent);
  var GROUPS = [["cat", "Cat moments"], ["tick", "Interface ticks"]];
  var cells = {};          // "set/slot" -> {audio, cell, button, len, found}
  var current = null;      // the cell playing now
  var run = null;          // the running whole-set pass: {set, token}
  var timer = null;
  var statusEl = document.getElementById("status");

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function key(set, slot) { return set + "/" + slot; }

  function stopNow() {
    if (timer) { clearTimeout(timer); timer = null; }
    if (current) {
      current.audio.pause();
      try { current.audio.currentTime = 0; } catch (e) { /* not seekable yet */ }
      current.cell.classList.remove("now");
      current = null;
    }
  }
  function playCell(c, onEnd) {
    stopNow();
    current = c;
    c.cell.classList.add("now");
    c.audio.onended = function () {
      c.cell.classList.remove("now");
      if (current === c) current = null;
      if (onEnd) onEnd();
    };
    var p = c.audio.play();
    if (p && p.catch) p.catch(function () { c.cell.classList.remove("now"); current = null; if (onEnd) onEnd(); });
  }
  function endRun() {
    if (run) {
      var b = document.getElementById("run-" + run.set);
      b.textContent = "Play the whole set";
      b.classList.remove("on");
      run = null;
    }
  }
  function runSet(set) {
    var wasThis = run && run.set === set;
    endRun();
    stopNow();
    if (wasThis) { setStatus(); return; }
    var queue = [];
    DATA.slots.forEach(function (s) { var c = cells[key(set, s.slot)]; if (c.found) queue.push(c); });
    var mine = { set: set };
    run = mine;
    var b = document.getElementById("run-" + set);
    b.textContent = "Stop";
    b.classList.add("on");
    (function next(i) {
      if (run !== mine) return;
      if (i >= queue.length) { endRun(); setStatus(); return; }
      statusEl.textContent = "Playing " + set + ": " + queue[i].slot + " (" + (i + 1) + " of " + queue.length + ")";
      playCell(queue[i], function () {
        timer = setTimeout(function () { next(i + 1); }, GAP_MS);
      });
    })(0);
  }

  function setStatus() {
    var total = 0, found = 0, missing = 0;
    Object.keys(cells).forEach(function (k) {
      total++;
      if (cells[k].found) found++;
      if (cells[k].missing) missing++;
    });
    var box = document.getElementById("missing");
    box.hidden = missing === 0;
    document.getElementById("missing-n").textContent = missing + " of " + total;
    statusEl.textContent = found + " of " + total + " files found" +
      (found + missing < total ? ", still looking…" : (missing ? "; run build_pack.py --all for the rest." : "."));
  }

  // header: one column per set, each with its run-through button
  var head = document.getElementById("head");
  DATA.sets.forEach(function (s) {
    var th = el("th"); th.scope = "col";
    var box = el("div", "set-h");
    box.appendChild(el("b", "", s.title));
    box.appendChild(el("span", "", s.voice));
    var b = el("button", "", "Play the whole set");
    b.type = "button"; b.id = "run-" + s.id;
    b.addEventListener("click", function () { runSet(s.id); });
    box.appendChild(b);
    th.appendChild(box); head.appendChild(th);
  });

  // body: a group heading, then one row per slot
  var table = document.getElementById("grid");
  GROUPS.forEach(function (g) {
    var tbody = el("tbody");
    var gr = el("tr", "group"), gh = el("th", "", g[1]);
    gh.colSpan = DATA.sets.length + 1; gr.appendChild(gh); tbody.appendChild(gr);
    DATA.slots.filter(function (s) { return s.kind === g[0]; }).forEach(function (s) {
      var tr = el("tr");
      var th = el("th"); th.scope = "row";
      th.appendChild(el("div", "name", s.slot));
      th.appendChild(el("div", "when", s.when));
      var chips = el("div", "chips");
      if (s.kind === "tick") {
        chips.appendChild(el("span", "chip", "no layers"));
      } else {
        chips.appendChild(el("span", "chip", "touch: " + s.mood));
        if (s.signature) chips.appendChild(el("span", "chip sig", s.dark ? "signature, dark" : "signature"));
      }
      th.appendChild(chips); tr.appendChild(th);
      DATA.sets.forEach(function (set) {
        var td = el("td"), cell = el("div", "cell");
        var b = el("button", "", "▶ Play"); b.type = "button";
        b.setAttribute("aria-label", "Play " + s.slot + ", " + set.title);
        var len = el("span", "len", "…");
        var audio = new Audio();
        var c = { slot: s.slot, audio: audio, cell: cell, found: false, missing: false };
        cells[key(set.id, s.slot)] = c;
        audio.preload = "metadata";
        audio.addEventListener("loadedmetadata", function () {
          c.found = true; len.textContent = audio.duration.toFixed(2) + " s"; setStatus();
        });
        audio.addEventListener("error", function () {
          if (c.found) return;
          c.missing = true; b.disabled = true; cell.classList.add("missing"); len.textContent = "missing"; setStatus();
        });
        audio.src = BASE + set.id + "/" + s.slot + ".wav";
        b.addEventListener("click", function () { endRun(); playCell(c); });
        cell.appendChild(b); cell.appendChild(len); td.appendChild(cell); tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
  });
  setStatus();

  // colour theme, remembered in this browser only
  var themeBtn = document.getElementById("theme");
  function readStore() { try { return window.localStorage.getItem("notchmeow.audition.theme"); } catch (e) { return null; } }
  function writeStore(v) { try { window.localStorage.setItem("notchmeow.audition.theme", v); } catch (e) { /* storage unavailable */ } }
  function applyTheme(t) {
    document.documentElement.setAttribute("data-theme", t);
    themeBtn.textContent = t === "dark" ? "Light" : "Dark";
  }
  var saved = readStore();
  if (saved === "dark" || saved === "light") applyTheme(saved);
  else applyTheme(window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");
  themeBtn.addEventListener("click", function () {
    var next = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
    writeStore(next); applyTheme(next);
  });
})();
</script>
</body></html>
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 103 tests`, `OK`

The page itself is checked in a browser in Task 12.

- [ ] **Step 5: Commit**

```bash
git add design/sounds/audition.html tests/test_sound_build.py
git commit -m "design(sounds): audition page for the four sound sets" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 11: The test script and the CI step

`scripts/test-sound-build.sh` runs the unit tests and the recipe check; with `--real` it also builds all four sets from the real clips and fails if any file misses its targets (opt-in and local: the clips are git-ignored, so CI never has them). `--real` with no clips folder is an error, not a silent skip: opting in and getting nothing would hide a problem. The recipe check inside the script also verifies that every named clip exists when the folder is found.

**Files:**
- Create: `scripts/test-sound-build.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `tests/test_sound_build.py`, `tools/sounds/build_pack.py` (`--check-recipes`, `--all --report`).
- Produces: `bash scripts/test-sound-build.sh [--real]`, exit code 0 when everything passes.

- [ ] **Step 1: Write the script**

**Create `scripts/test-sound-build.sh`**

```bash
#!/usr/bin/env bash
# Tests for the sound-set build (tools/sounds/): Python 3 standard library plus macOS afconvert.
#   bash scripts/test-sound-build.sh          unit tests and the recipe check (CI runs this)
#   bash scripts/test-sound-build.sh --real   also builds all four sets from the real candidate clips
#                                             and fails if any file misses its targets (local only:
#                                             the clips are git-ignored)
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p 'test_sound_build.py'
python3 tools/sounds/build_pack.py --check-recipes
if [ "${1:-}" = "--real" ]; then
    python3 tools/sounds/build_pack.py --all --report
fi
```


```bash
chmod +x scripts/test-sound-build.sh
```

- [ ] **Step 2: Run it**

Run: `bash scripts/test-sound-build.sh`
Expected: `Ran 103 tests`, `OK`, then `recipes ok: 4 sets x 28 slots` and either `clips ok in ...` or `candidates folder not found: the clip files were not checked`. The exit code is 0.

- [ ] **Step 3: Add the CI step**

The brief asks for one step right after the AI contract step. On `683163f` that step is "AI contract (fixtures + fake server)", which runs `scripts/test-ai-contract.sh`. In `.github/workflows/build.yml`, replace

```yaml
      - name: AI contract (fixtures + fake server)
        run: bash scripts/test-ai-contract.sh

      - name: Test chat parsing
```

with

```yaml
      - name: AI contract (fixtures + fake server)
        run: bash scripts/test-ai-contract.sh

      - name: Sound build tests
        run: bash scripts/test-sound-build.sh

      - name: Test chat parsing
```

If that step has been renamed or moved by the time this branch is cut, put the new step directly after whatever step runs `scripts/test-ai-contract.sh`. If the step does not exist at all, add the new step after the last existing test step instead, before "Build", and tell the controller.

- [ ] **Step 4: Check the workflow change**

Run: `python3 -c "t=open('.github/workflows/build.yml').read(); assert t.count('- name: Sound build tests')==1 and t.index('scripts/test-ai-contract.sh') < t.index('scripts/test-sound-build.sh') < t.index('scripts/test-chat-parsing.sh'); print('step present once, after the AI contract step')"`
Expected: `step present once, after the AI contract step`

(There is no YAML parser in the standard library; the diff is the real check.)

Run: `git diff .github/workflows/build.yml`
Expected: only three added lines after the "AI contract" step: the `- name: Sound build tests` line, the `run: bash scripts/test-sound-build.sh` line and one blank line.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-sound-build.sh .github/workflows/build.yml
git commit -m "build(ci): run the sound build tests" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```



---

### Task 12: Verify on the real clips (no commit)

Nothing new is written. This task proves the stage works on the real 63 clips, and produces what the owner needs for the audition. Paste the evidence into the report to the controller.

- [ ] **Step 1: Run the whole check, including the real build**

Run: `bash scripts/test-sound-build.sh --real`
Expected: `Ran 103 tests` and `OK` (no skips when the clips are found), `recipes ok: 4 sets x 28 slots`, `clips ok in ...`, four lines `built <set>: 28 files in ...`, and `report: ... (112 of 112 files meet their targets)`. Exit code 0. If a file misses a target, the run prints `FAIL <set>/<slot>: <why>`; read `.claude/sounds/build/report.md`, fix the recipe entry (a window, a `gain_db`, a `pitch_st`) and re-run. Do not loosen the targets.

- [ ] **Step 2: Check the output**

```bash
for s in studio steff kitten bestof; do echo "$s: $(ls .claude/sounds/build/$s/*.wav | wc -l | tr -d ' ') files"; done
head -8 .claude/sounds/build/report.md
```

Expected: `28 files` for each set, and a report that starts `112 of 112 files meet their targets.`

- [ ] **Step 3: Check that a second run gives identical files**

```bash
(cd .claude/sounds/build && find . -name '*.wav' | sort | xargs shasum -a 256) > .claude/sounds/hashes-1.txt
python3 tools/sounds/build_pack.py --all --out .claude/sounds/build-again
(cd .claude/sounds/build-again && find . -name '*.wav' | sort | xargs shasum -a 256) > .claude/sounds/hashes-2.txt
diff .claude/sounds/hashes-1.txt .claude/sounds/hashes-2.txt && echo IDENTICAL
wc -l < .claude/sounds/hashes-1.txt
```

Expected: `IDENTICAL` and `112`.

- [ ] **Step 4: Check the unit tests on the system Python 3.9 as well**

Run: `/usr/bin/python3 --version && /usr/bin/python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Python 3.9.x`, then `Ran 103 tests` and `OK`.

- [ ] **Step 5: Open the audition page and check the console**

The built-in browser pane renders local files as static snapshots, so use `playwright-cli`. It blocks `file:` unless the session's config allows it:

```bash
mkdir -p .claude/pw/.playwright && cd .claude/pw
echo '{"allowUnrestrictedFileAccess": true}' > .playwright/cli.config.json
playwright-cli open "file://$(cd ../.. && pwd)/design/sounds/audition.html"
playwright-cli console
playwright-cli --raw eval "JSON.stringify({rows: document.querySelectorAll('tbody tr:not(.group)').length, play: document.querySelectorAll('td button').length, runs: document.querySelectorAll('thead button').length, status: document.getElementById('status').textContent, noticeHidden: document.getElementById('missing').hidden})"
```

Expected: `Total messages: 0 (Errors: 0, Warnings: 0)` from the console, and `{"rows":28,"play":112,"runs":4,"status":"112 of 112 files found.","noticeHidden":true}`.

Then check the run-through and the missing-file notice:

```bash
playwright-cli click "#run-studio"
sleep 2
playwright-cli --raw eval "document.getElementById('status').textContent"
playwright-cli click "#run-studio"
playwright-cli --raw eval "document.getElementById('run-studio').textContent"
cd ../.. && mv .claude/sounds/build/kitten .claude/sounds/build/kitten.off
cd .claude/pw && playwright-cli reload && playwright-cli --raw eval "JSON.stringify({status: document.getElementById('status').textContent, noticeHidden: document.getElementById('missing').hidden, missing: document.querySelectorAll('.cell.missing').length})"
cd ../.. && mv .claude/sounds/build/kitten.off .claude/sounds/build/kitten
cd .claude/pw && playwright-cli close && cd ../..
```

Expected: a status such as `Playing studio: annoyed (3 of 28)`; after the second click the button reads `Play the whole set`; with the Kitten folder moved away, `{"status":"84 of 112 files found; run build_pack.py --all for the rest.","noticeHidden":false,"missing":28}`. (The console then shows 28 `ERR_FILE_NOT_FOUND` lines from the browser itself; that is the browser reporting the missing files, and it only happens in that test.) Put the folder back, as the last command does.

- [ ] **Step 6: Check nothing forbidden is staged or tracked**

```bash
git status --short
git ls-files | grep -E '\.wav$|^\.claude/' || echo "no wav and nothing under .claude is tracked"
git log --oneline notchmeow/rebrand..HEAD
```

Expected: `git status --short` prints nothing (everything is committed; `.claude/` is ignored), the second command prints `no wav and nothing under .claude is tracked`, and the log lists the eleven commits of Tasks 1 to 11.

- [ ] **Step 7: Tell the controller what to do next**

The owner listens: open `design/sounds/audition.html` in a browser (from the worktree, or copy the built folder: the page reads `../../.claude/sounds/build/` relative to itself). Three slots deserve a close listen because their windows come from measurements and not from ears: **yawn** (synth in every set), **search** in Best of (the hunting chatter), and **proud** in Best of (the cut chirp). Stage 2 starts after the owner picks a set.

## Interfaces for Stages 2 and 3

Nothing here builds them; this is what they can rely on.

- **Stage 2 (final pack, licences).** `python3 tools/sounds/build_pack.py --set <name> --candidates <folder of originals> --out NotchBuddy/Resources/sounds --report` writes the chosen set's 28 `<slot>.wav` files and a report; only the recipe `source` names change when the Freesound originals replace the previews. `recipe._check_source` is where the spec's "the build refuses any source without a verified CC0 entry" belongs: it already rejects the excluded clips, and can look the source up in `design/sounds/sources.json` once that exists. `report.failures` is the gate for the rebuilt set.
- **Stage 3 (wiring, per-cat voice).** The WAVs carry no per-cat pitch; the apps apply the playback rate 2^(st/12) at play time. `recipe.SLOTS` (kind, mood, signature, length limit) is the single table; the audition page's embedded copy is test-checked against it, and the same table can feed `tests/fixtures/sound/rules.json` when that contract is written.

## Spec coverage

| Spec item | Where |
|---|---|
| Section 1: 28 slots, four sets, exclusions | Task 6 (slot table, exclusions), Task 9 (sets) |
| Section 2: recipes, `build_pack.py`, processing order, gap recipes | Tasks 1 to 9 |
| Section 2: audition page with a whole-set run-through | Task 10 |
| Section 3: touch, signature, per-set pitch, nothing per-cat baked in | Task 5 (layers), Task 9 (set pitch), Task 7 (set pitch reaches recorded clips only) |
| Section 6, Build: byte-identical rebuild | Task 7 test, Task 12 step 3 |
| Section 6, Build: loudness report against targets | Task 8, Task 12 step 1 |
| Section 6, Build: all 28 files, length limits | Task 7 (cap), Task 8 (check) |
| Stages, item 1 | the whole plan |
| Sections 4, 5, 6 (rules, licences, sources.json) and Stages 2, 3 | not in this plan (Stages 2 and 3) |
