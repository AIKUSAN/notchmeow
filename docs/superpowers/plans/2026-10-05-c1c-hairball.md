# c1c-hairball Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The sound build gains its 29th slot, `hairball`, and rebuilds the version the owner picked on 2026-10-05 (B, the hybrid) from a recipe, byte for byte, instead of from a one-off script.

**Architecture:** The recipe format gets two small, general parts. A **placed sound** (`"source": "placed"`) is laid out on a timeline: `segments` are windows of recorded clips, each faded with equal-power fades, set to a level and placed at a time, and `synth_layers` are named made-in-code parts (`synth.LAYERS`) mixed in at a time. Everything after the timeline is the pipeline's usual cat-moment path. `hairball` is a cat moment (mood upset) in `_shared.json`, so every set and Your mix carry it, it is not pickable, and a new `touch` flag on the slot table switches off its touch layer. The audition page learns the 29th row.

**Tech Stack:** Python 3 standard library and macOS `afconvert` (the build's only tools), `unittest`, one static HTML page. No third-party packages, no network.

**Spec:** `docs/superpowers/specs/2026-10-04-sounds-design.md`: section 1 "Slots" (29, the cat moments), "Picking per moment" (Play my mix: 29 sounds, 14 shared), section 3 "Hairball" and "Per-cat voice", section 4 (the `hairball` row of the wiring table and the play-rule exception), section 6 "Checks" (Build: all 29 files exist), and "Stages" (1c). Tests and docs take the slot count from `recipe.SLOTS`, never from a typed number.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec unless marked.

- **Slots:** 29. The 28 existing names plus `hairball`, added on 2026-10-05. Cat moments (19) now end with `hairball`; the 10 interface ticks are unchanged. The slot table order stays "cat moments first, then the ticks", so `hairball` follows `rate`.
- **The hairball is one shared sound in every set, like gulp:** "a hack has no voice to pick between sets, so it is not a pickable row and needs no touch or signature layer". Mood `upset`. The 15 pickable moments and `mine.json` do not change; Play my mix plays "all 29 sounds in order from the already-built set files: the 15 picks and the 14 shared sounds".
- **What B is:** "Three real dry coughs from *Cat Coughing* (har2h, Freesound 561726, CC0), placed so their onsets fall at about 115, 435 and 755 ms, just before the animation's heave peaks at 140, 460 and 780 ms ... joined with 60 ms equal-power crossfades." Then, made in code, "a gurgly pulse train rising from 120 to 280 Hz through the heaves' two formant band-passes, swelling from 930 ms, then a falling-sine plop at 1110 ms ... with a short low wet tail".
- **Length and level:** "1.48 s, at the cat-moment loudness target, with the usual 100 Hz high-pass and fades": cat moments −20 LUFS short-term (±1.5 LU), true peak at or under −1 dBTP, up to 1.5 s.
- **Reference:** the audition file `B.wav`, SHA-256 `77f70082aa72a6ce68a8137f69002960b29995f3e7da9882882db5e1dfdec1ca`, git-ignored at `.claude/sounds/build/hairball/B.wav`. The build must reproduce it from the recipe.
- **Byte-identical builds:** "Rebuilding a set gives byte-identical WAVs." Adding the slot changes no existing file: the 140 set files and the 28 old files of Your mix stay the same bytes (Task 5 compares them with a baseline built in Task 1).
- **Made-in-code sounds are deterministic:** `random.Random` with a fixed seed (the retch and plop use 1205), 48 kHz floats, no clocks, no unseeded randomness.
- **Sources:** CC0 only; the excluded list stays excluded; a recipe source is `<slot folder>/<file>`, and the folder is a slot name. The har2h clip is `hairball/fs-561726-har2h.mp3` in the git-ignored candidates folder; its manifest row exists.
- **Not in this plan (spec, Stage 3, "after sub-project A"):** the hairball plays at rate 1 for every cat; "the hairball may replace the error sound it follows"; it starts on the engine's `hairball` note. See "Notes for Stage 3".
- **Repo rules (`CLAUDE.md`):** local commits only, never push; Python 3 standard library only; the clips and the build folder are git-ignored; `NotchBuddy/` and `windows/` are not touched; nothing of Coucou's comes back. Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, or with the model that wrote it when an implementer runs on another one (the light tasks name `Claude Haiku 4.5`).
- **House rules for this session:** never launch, quit or replace the installed NotchMeow app (`~/Library/Logs/NotchMeow/nm.log` must not grow); do not start or stop anything on port 8768. The audition page is checked from a `file://` URL.

## Review Focus

The spec says what the hairball is. It is silent on these inputs, and each would bite a person (or a later plan) first. Each line names its test.

1. **A hand-edited placed entry that is nearly right:** segments on an ordinary source, a placed sound in a set file (where the set's pitch shift would reach it), a segment whose source is `synth:` or `placed`, a window with `end` before `start`, a level of 0 or over 1, an `at` that is negative, over 10 s or NaN, a negative or boolean seed. Expected: a `RecipeError` that names the entry and the field, never a traceback and never a silent default. Tests: Task 2 "a placed entry belongs in the shared file…", "every segment field is checked", "every synth layer field is checked".
2. **A segment window beyond the end of its clip, or in a silent stretch** (the decoder returned a shorter clip, or the file is another recording). Expected: the build stops with exit 2 and the message names the slot, the segment number and the clip, like a plain slot does. Test: Task 2 "a segment window outside its clip or in a pause…".
3. **The har2h clip is missing** (the clips are git-ignored: a fresh checkout, CI). Expected: `--check-recipes` names it once, not once per segment, and builds stop before anything is written; the byte-for-byte test skips instead of failing. Tests: Task 2 "missing_sources names a placed sound's clips once", Task 3 "the recipe rebuilds the audition file…" (skipped without the clip).
4. **A placed timeline longer than the 1.5 s cap** (the plop's wet tail runs to 1.59 s). Expected: the recipe's `end` cuts it to exactly 1.48 s before the fades, and with no `end` the pipeline's cap still cuts it, so the fade-out is never off the end of the file. Test: Task 2 "a placed sound longer than the cap is cut to it".
5. **A build folder from before this plan** (the owner opens the audition page after pulling, before rebuilding). Expected: the five hairball cells say "missing", the red banner says "5 of 145" and tells them to run `build_pack.py --all --report`, and Play my mix skips the hairball by name instead of stopping. Check: Task 4, the browser step. Also: `mine.json` that lists `hairball` as a pick is refused as "the same in every set". Test: Task 3 "a shared sound cannot be listed".

---

## File Structure

| Path | Responsibility |
|---|---|
| `tools/sounds/dsp.py` | Gains `fade_equal_power`, `env_peak` and `scale_to_env_peak` (the 4 ms RMS level scale the one-off scripts used). |
| `tools/sounds/synth.py` | Gains the hairball's retch and plop (`hairball_retch_plop(seed)`) and the registry `LAYERS` of made-in-code layers. |
| `tools/sounds/recipe.py` | `PLACED`, the parsed `segments` and `synth_layers` on `Entry`, `missing_sources` that sees a placed sound's clips; the slot table gains `hairball` and the `touch` flag. |
| `tools/sounds/pipeline.py` | `_placed` builds the timeline; `_audible` is the empty-or-silent check both kinds of source share; `build_slot` passes the touch flag on. |
| `tools/sounds/layers.py` | `add_layers` takes `with_touch` (the hairball is the one cat moment without it). |
| `tools/sounds/build_pack.py` | Docstring only: 29 WAVs, and what a placed sound is. |
| `design/sounds/sets/_shared.json` | The `hairball` entry: the owner's pick as a recipe. |
| `design/sounds/audition.html` | A `hairball` row among the shared rows, a `touch` field on every row, the counts in its text. |
| `design/sounds/cc0-candidates-hairball.md` | The research that found the clips, committed as a record (untracked in the main checkout today) with a short outcome section. |
| `tests/test_sound_build.py` | New tests per task; every typed 28 becomes `len(recipe.SLOTS)`. |

`scripts/test-sound-build.sh` and `.github/workflows/build.yml` need no change: CI runs the same script, and the tests that need the git-ignored clips skip there.

**Where the numbers come from.** They were measured on the one-off scripts that built `B.wav` (kept in the session scratchpad, not in the repo) and then replayed: running the script's `make("B")` gives exactly `B.wav`, with no placement nudge (its adjustments came out 0). The decoded `har2h` clip has coughs that start at 2.258, 4.276 and 7.358 s. Window = start of the cough minus a pre-roll (the first piece 115 ms, the others 80 ms) to 300 ms after it. A piece's level is `0.22 × (0.60, 0.78, 1.00)` on the 4 ms RMS scale (the loudest 4 ms RMS stretch, windows every 1 ms), which is the scale the retch (`0.22 × 0.85`) and plop (`0.22`) use too. Fades are equal-power: 5 ms in for the first piece, 48 ms in for the others (0.6 × their 80 ms pre-roll), 60 ms out for all. The cut is 1.48 s. The recipe stores exactly these numbers; the retch and plop maths is ported line for line and was compared sample for sample with the script's.

**Agents** (`CLAUDE.md`: the lightest model that fits). Tasks 1 and 5 give every line, so they are transcription: `nm-implementer-light` (Haiku 4.5). Tasks 2, 3 and 4 touch several files and a 1700-line test file, and Task 4 judges a page in a browser: `nm-implementer` (Sonnet 5.5, medium). If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep`. Task reviews: `nm-reviewer`; the final whole-branch review: `nm-reviewer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review`.

**Order of tasks:**

1. DSP helpers and the hairball's retch and plop
2. Placed sounds: the two recipe parts
3. The 29th slot, rebuilt from its recipe
4. The audition page
5. The record, and the final checks

## Execution

One worktree chat session runs the whole plan: branch `c1c/hairball`, model **Sonnet 5.5 at medium effort** (`ARCHITECT.md`: a plan whose tasks are mostly given in full). Nothing is pushed.

**Before the session starts,** the controller commits this plan file to `notchmeow/rebrand` (a docs-only commit, with the owner's OK), so the branch the session starts from already holds the plan it runs. The spec edit that adds the "Hairball" paragraph (`docs/superpowers/specs/2026-10-04-sounds-design.md`) is already committed there as `479c41a`, after the `.gitignore` commit `fdcffe6`. **The base is `479c41a` or later**, and `git merge-base --is-ancestor 479c41a HEAD` must succeed. The clips and `B.wav` are git-ignored and live in the main checkout: in a worktree `build_pack.py` finds the clips by itself (`git rev-parse --git-common-dir`), and the tests find `B.wav` next to them. If either is missing, the tests that need them skip and Task 5 says so in its report.

**The session is started in three steps** (`ARCHITECT.md`), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c c1c/hairball notchmeow/rebrand`, then check three things: `git merge-base --is-ancestor 479c41a HEAD` must succeed, `git ls-files docs/superpowers/plans/2026-10-05-c1c-hairball.md` must print the plan's path, and `grep -c '^\*\*Hairball\.\*\*' docs/superpowers/specs/2026-10-04-sounds-design.md` must print 1. If any check fails, say so and stop. Then check the clips: `ls "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.claude/sounds/candidates/hairball/fs-561726-har2h.mp3"` must list the file; say so if it does not. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/plans/2026-10-05-c1c-hairball.md` and `docs/superpowers/specs/2026-10-04-sounds-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message:

   > Run `docs/superpowers/plans/2026-10-05-c1c-hairball.md` with `superpowers:subagent-driven-development`, task by task, on this branch. Dispatch each task to the agent the plan names for it, then to `nm-reviewer`; fix what the review finds before the next task. After Task 5, dispatch `nm-reviewer-deep` over the whole branch. Commit only as the plan's commit steps say, and never push. When you are done, report: the commits, the output of `bash scripts/test-sound-build.sh` with the test count, the `--all --report` and `--set mine --report` summary lines, the SHA-256 of the rebuilt `hairball.wav` next to `B.wav`'s, what the browser check on the audition page showed (the counts and the "of 29" line), and anything you could not settle.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

**Locally** every test and build step below needs the git-ignored clips. In a worktree they are found by themselves. In any other checkout, point `NM_SOUND_CANDIDATES` at the main checkout's `.claude/sounds/candidates` first; `NM_HAIRBALL_REFERENCE` can name `B.wav` if it is not next to that folder.

---

### Task 1: DSP helpers and the hairball's retch and plop

**Files:**
- Modify: `tools/sounds/dsp.py`
- Modify: `tools/sounds/synth.py`
- Test: `tests/test_sound_build.py`

**Interfaces:**
- Consumes: nothing new. `dsp.SR`, `dsp.bandpass`, `dsp.lowpass`, `dsp.mix_at`, `dsp.peak`; `synth._noise(rng, count)` and `synth._smooth(t, a, b)`.
- Produces in `dsp.py`: `fade_equal_power(x, in_ms=0.0, out_ms=0.0, sr=SR)` returns a new list: a sine fade in over `in_ms`, a cosine fade out over `out_ms`, either cut to the length of `x`; the last sample is not forced to zero. `env_peak(x, win_ms=4.0, hop_ms=1.0, sr=SR)` returns the loudest sliding RMS of `x` as a float (windows of 4 ms, a new one every 1 ms; 0.0 when `x` is shorter than one window). `scale_to_env_peak(x, target)` returns `x` scaled so `env_peak` is `target` (a copy of `x` when it is silent or too short).
- Produces in `synth.py`: `hairball_retch_plop(seed)` returns a list of floats, exactly 31680 samples (660 ms at 48 kHz): the retch in the first 175 ms (loudest 4 ms RMS `0.22 × 0.85`), 5 ms of exact silence, then the plop from 180 ms on (loudest 4 ms RMS `0.22`). `LAYERS = {"hairball_retch_plop": hairball_retch_plop}`: made-in-code layers take a seed and return a list. Constants `HAIRBALL_LEVEL = 0.22` and `RETCH_TO_PLOP_MS = 180`.

- [ ] **Step 1: Record the baseline build**

Before any code changes, build the five sets and Your mix as they are now, so Task 5 can prove nothing else moved. The folder is outside the repo; `TMPDIR` is the session's scratch folder.

Run: `mkdir -p "${TMPDIR:-/tmp}/c1c-base" && python3 tools/sounds/build_pack.py --all --out "${TMPDIR:-/tmp}/c1c-base/all" && python3 tools/sounds/build_pack.py --set mine --out "${TMPDIR:-/tmp}/c1c-base/mine"`
Expected: PASS, with `built studio: 28 files` through `built tabby: 28 files` and `built mine: 28 files`. (Without the git-ignored clips the build stops with "candidates folder not found": say so in the report and skip the comparison in Task 5.)

- [ ] **Step 2: Write the failing tests**

In `tests/test_sound_build.py` (class `TestDsp`), replace:

```python
    def test_mix_at_extends_and_adds(self):
        out = dsp.mix_at([1.0, 1.0], [0.5, 0.5, 0.5], 1)
        self.assertEqual(out, [1.0, 1.5, 0.5, 0.5])
```

with:

```python
    def test_mix_at_extends_and_adds(self):
        out = dsp.mix_at([1.0, 1.0], [0.5, 0.5, 0.5], 1)
        self.assertEqual(out, [1.0, 1.5, 0.5, 0.5])

    def test_equal_power_fades_keep_the_power_of_two_sounds_that_overlap(self):
        n = int(0.06 * SR)
        gain_in = dsp.fade_equal_power([1.0] * n, 60.0, 0.0)
        gain_out = dsp.fade_equal_power([1.0] * n, 0.0, 60.0)
        self.assertEqual((gain_in[0], gain_out[0]), (0.0, 1.0))
        for i in (1, n // 4, n // 2, n - 1):
            self.assertAlmostEqual(gain_in[i] ** 2 + gain_out[i] ** 2, 1.0, places=9)
        self.assertAlmostEqual(gain_in[n // 2], math.sin(math.pi / 4), places=9)

    def test_equal_power_fades_are_cut_to_the_sound_and_zero_fades_change_nothing(self):
        x = sine(300, 0.01, 0.3)
        self.assertEqual(dsp.fade_equal_power(x, 0.0, 0.0), x)
        short = dsp.fade_equal_power([1.0] * 10, 500.0, 500.0)
        self.assertEqual(len(short), 10)
        self.assertTrue(all(math.isfinite(v) for v in short))
        self.assertEqual(dsp.fade_equal_power([], 5.0, 5.0), [])

    def test_env_peak_is_the_loudest_4ms_rms(self):
        self.assertAlmostEqual(dsp.env_peak(sine(1000, 0.1, 0.5)), 0.5 / math.sqrt(2), delta=1e-3)
        quiet_then_loud = sine(1000, 0.05, 0.1) + sine(1000, 0.05, 0.4)
        self.assertAlmostEqual(dsp.env_peak(quiet_then_loud), 0.4 / math.sqrt(2), delta=1e-3)
        self.assertEqual(dsp.env_peak(sine(1000, 0.003, 0.5)), 0.0)         # shorter than one window
        self.assertEqual(dsp.env_peak([]), 0.0)

    def test_scale_to_env_peak_sets_the_level_and_leaves_silence_alone(self):
        x = sine(700, 0.1, 0.5)
        self.assertAlmostEqual(dsp.env_peak(dsp.scale_to_env_peak(x, 0.1)), 0.1, places=9)
        self.assertEqual(dsp.scale_to_env_peak([0.0] * 500, 0.1), [0.0] * 500)
        self.assertEqual(dsp.scale_to_env_peak([0.3] * 10, 0.1), [0.3] * 10)    # shorter than a window: unchanged
```

In `tests/test_sound_build.py` (class `TestSynth`), replace:

```python
        self.assertGreaterEqual(len(peaks), 8)
        self.assertLessEqual(len(peaks), 13)
```

with:

```python
        self.assertGreaterEqual(len(peaks), 8)
        self.assertLessEqual(len(peaks), 13)

    def test_the_hairballs_retch_and_plop_is_one_deterministic_piece(self):
        a = synth.hairball_retch_plop(1205)
        self.assertEqual(a, synth.hairball_retch_plop(1205))
        self.assertNotEqual(a, synth.hairball_retch_plop(1206))
        self.assertEqual(len(a), int(round(0.660 * SR)))                    # 180 ms to the plop, which lasts 480 ms
        self.assertTrue(all(math.isfinite(v) for v in a))
        self.assertIs(synth.LAYERS["hairball_retch_plop"], synth.hairball_retch_plop)

    def test_the_retch_swells_and_the_plop_lands_at_once_and_dies_away(self):
        x = synth.hairball_retch_plop(1205)
        retch, gap, plop = x[:8400], x[8400:8640], x[8640:]               # 175 ms, 5 ms of silence, the plop from 180 ms
        self.assertEqual(max(abs(v) for v in gap), 0.0)
        self.assertAlmostEqual(dsp.env_peak(retch), 0.22 * 0.85, places=9)  # 0.22 is the loudest heave on the timeline
        self.assertAlmostEqual(dsp.env_peak(plop), 0.22, places=9)

        def loudest_ms(part):                                               # the 4 ms RMS window that peaks, in ms
            env = [dsp.rms(part[i:i + 192]) for i in range(0, len(part) - 191, 48)]
            return env.index(max(env))
        self.assertGreater(loudest_ms(retch), 100)                          # the gurgle swells towards its end
        self.assertLess(loudest_ms(plop), 10)                               # the ball lands at once
        self.assertLess(dsp.rms(plop[int(0.30 * SR):]), 0.01 * dsp.env_peak(plop))      # a short wet tail: quiet 300 ms on

    def test_the_retch_and_plop_still_sound_like_the_owners_pick(self):
        # A fingerprint of the maths: the owner picked these exact numbers (B.wav, 2026-10-05). Changing the
        # sound on purpose means a new pick; then re-measure the two sums with
        #   python3 -c "import sys; sys.path.insert(0, 'tools/sounds'); import synth; x = synth.hairball_retch_plop(1205); print(sum(map(abs, x)), sum(v * v for v in x))"
        x = synth.hairball_retch_plop(1205)
        self.assertAlmostEqual(sum(abs(v) for v in x), 790.218, delta=0.005)
        self.assertAlmostEqual(sum(v * v for v in x), 104.827, delta=0.005)
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py' -k equal_power -k env_peak -k scale_to_env_peak -k hairballs_retch -k retch_swells -k retch_and_plop`
Expected: FAIL, 7 errors, each `AttributeError: module 'dsp' has no attribute ...` or `module 'synth' has no attribute 'hairball_retch_plop'`.

- [ ] **Step 4: Add the DSP helpers**

In `tools/sounds/dsp.py`, replace:

```python
# --- resampling: pitch shift, glide, wobble ---------------------------------------------
```

with:

```python
def fade_equal_power(x, in_ms=0.0, out_ms=0.0, sr=SR):
    """Equal-power fades, a sine in and a cosine out. Two sounds that do not match sample for sample,
    crossfaded over the same span, keep their level; half-cosine fades would dip about 3 dB at the
    seam. Unlike `fade`, the last sample is not forced to zero. A fade longer than x is cut to x."""
    n = len(x)
    n_in = min(int(round(in_ms * sr / 1000.0)), n)
    n_out = min(int(round(out_ms * sr / 1000.0)), n)
    out = list(x)
    for i in range(n_in):
        out[i] *= math.sin(0.5 * math.pi * i / n_in)
    for j in range(n_out):
        out[n - n_out + j] *= math.cos(0.5 * math.pi * j / n_out)
    return out


# --- level measured the way the made-in-code sounds are scaled ---------------------------

def env_peak(x, win_ms=4.0, hop_ms=1.0, sr=SR):
    """The loudest short RMS of x (linear): windows of `win_ms`, a new one every `hop_ms`. 0.0 when x
    is shorter than one window."""
    w = int(round(win_ms * sr / 1000.0))
    h = int(round(hop_ms * sr / 1000.0))
    cs = [0.0]
    for v in x:
        cs.append(cs[-1] + v * v)
    best, i = 0.0, 0
    while i + w <= len(x):
        best = max(best, math.sqrt((cs[i + w] - cs[i]) / w))
        i += h
    return best


def scale_to_env_peak(x, target):
    """x with its loudest 4 ms RMS (`env_peak`) set to `target`. A silent x comes back unchanged."""
    top = env_peak(x)
    return [v * target / top for v in x] if top > 0 else list(x)


# --- resampling: pitch shift, glide, wobble ---------------------------------------------
```

- [ ] **Step 5: Run the DSP tests**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py' -k equal_power -k env_peak -k scale_to_env_peak`
Expected: PASS, 4 tests.

- [ ] **Step 6: Add the hairball's retch and plop**

In `tools/sounds/synth.py`, replace:

```python
"""Made-in-code sounds that fill the gaps in the recordings (spec section 2, "Gap recipes").

Every recipe returns a list of floats at 48 kHz, about 0.5 of full scale; the build normalises the
level afterwards. Noise comes from random.Random with a fixed seed, so the output never changes.
"""
from __future__ import annotations

import math
import random

from dsp import SR, bandpass, lowpass
```

with:

```python
"""Made-in-code sounds that fill the gaps in the recordings (spec section 2, "Gap recipes").

Every recipe in GAPS returns a list of floats at 48 kHz, about 0.5 of full scale; the build
normalises the level afterwards. Noise comes from random.Random with a fixed seed, so the output
never changes. LAYERS holds the made-in-code parts a placed sound mixes in among its clip segments
(recipe "synth_layers"): they take a seed and are scaled on the 4 ms RMS scale of the segments' levels.
"""
from __future__ import annotations

import math
import random

from dsp import SR, bandpass, lowpass, mix_at, peak, scale_to_env_peak
```

In `tools/sounds/synth.py`, replace:

```python
GAPS = {"blip": blip, "clink": clink, "yawn": yawn, "work": work, "search": search}
```

with:

```python
GAPS = {"blip": blip, "clink": clink, "yawn": yawn, "work": work, "search": search}


# --- the hairball's retch and plop (spec section 3, "Hairball") --------------------------------

HAIRBALL_LEVEL = 0.22        # the 4 ms RMS peak of the loudest heave on the hairball's timeline
RETCH_TO_PLOP_MS = 180       # the plop starts this long after the retch does (930 and 1110 ms)


def _ms(n):
    return int(round(n * SR / 1000.0))


def _pulses(rng, n, f_of_t, jitter=0.05, shimmer=0.25):
    """A pulse train whose rate follows f_of_t(seconds), with a little jitter in the spacing and
    shimmer in the height."""
    out = [0.0] * n
    phase, jit = 1.0, 1.0
    for i in range(n):
        phase += f_of_t(i / SR) * jit / SR
        if phase >= 1.0:
            phase -= 1.0
            out[i] = 1.0 + shimmer * (rng.random() * 2.0 - 1.0)
            jit = 1.0 + jitter * (rng.random() * 2.0 - 1.0)
    return out


def _formants(x, f1=650.0, q1=4.0, f2=1900.0, q2=5.0, w2=0.6, drive=2.2):
    """Two formant band-passes, then a soft saturation: a sparse pulse train rings with tall, narrow
    peaks, and the saturation (the throat's own grit) brings the crest factor down."""
    a, b = bandpass(x, f1, q1), bandpass(x, f2, q2)
    y = [p + w2 * q for p, q in zip(a, b)]
    top = peak(y) or 1.0
    return lowpass([math.tanh(drive * v / top) for v in y], 3200.0, SR, 0.7)   # keep the grit out of the hiss band


def _retch(rng):
    """The rising gurgle, 175 ms: a pulse train gliding from 120 to 280 Hz through the formants, with
    a little breath and a 28 Hz flutter, swelling for 160 ms and off by 175."""
    n = _ms(175)

    def f(t):
        return 120.0 + (280.0 - 120.0) * min(t / 0.180, 1.0)
    x = _formants(_pulses(rng, n, f, jitter=0.07, shimmer=0.35))
    br = bandpass(_noise(rng, n), 1500.0, 0.9)
    out = []
    for i in range(n):
        t = i / SR
        flutter = 1.0 - 0.5 * (0.5 + 0.5 * math.sin(2.0 * math.pi * 28.0 * t))
        swell = _smooth(t, 0.0, 0.160)
        stop = 1.0 - _smooth(t, 0.165, 0.175)
        out.append((x[i] + 0.25 * br[i] * 4.0) * flutter * swell * stop)
    return scale_to_env_peak(out, HAIRBALL_LEVEL * 0.85)


def _plop(rng):
    """The ball comes out at t=0, 480 ms: a falling sine with a short tail, a wet body and a faint
    tick, then a low wet tail of about 200 ms."""
    n = _ms(480)
    out = [0.0] * n
    ph = 0.0
    body = lowpass(_noise(rng, _ms(40)), 1200.0)
    for i in range(n):
        t = i / SR
        ph += 2.0 * math.pi * (180.0 + 340.0 * math.exp(-t / 0.015)) / SR
        env = _smooth(t, 0.0, 0.001) * math.exp(-t / 0.035)
        out[i] += env * (math.sin(ph) + 0.25 * math.sin(2.0 * ph))
    out = scale_to_env_peak(out, 1.0)                       # the sine's 4 ms RMS peak = 1.0
    for i, v in enumerate(body):
        out[i] += 0.45 * v * 4.0 * math.exp(-(i / SR) / 0.012) * _smooth(i / SR, 0.0, 0.0015)
    for i in range(_ms(30)):
        t = i / SR
        out[i] += 0.12 * math.sin(2.0 * math.pi * 3400.0 * t) * math.exp(-t / 0.006)
    tail = lowpass(_noise(rng, n), 800.0)
    for i in range(n):
        t = i / SR
        if t < 0.020:
            continue
        flutter = 0.5 + 0.5 * math.sin(2.0 * math.pi * 25.0 * t)
        a = _smooth(t, 0.020, 0.040) * (1.0 - _smooth(t, 0.220, 0.340))
        out[i] += 0.05 * 4.0 * tail[i] * (0.5 + 0.5 * flutter) * a
    return scale_to_env_peak(out, HAIRBALL_LEVEL)


def hairball_retch_plop(seed):
    """The hairball's made-in-code ending as one piece, 660 ms: the retch from 0 to 175 ms, the plop
    from 180 ms on. The placed sound puts it at 930 ms, so the plop lands at 1110, when the mouth is
    fully open and the ball comes out."""
    rng = random.Random(seed)
    retch = _retch(rng)
    plop = _plop(rng)
    return mix_at(retch, plop, _ms(RETCH_TO_PLOP_MS))


LAYERS = {"hairball_retch_plop": hairball_retch_plop}
```

- [ ] **Step 7: Run the new tests and the whole file**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py' -k equal_power -k env_peak -k scale_to_env_peak -k hairballs_retch -k retch_swells -k retch_and_plop`
Expected: PASS, 7 tests.

Run: `bash scripts/test-sound-build.sh`
Expected: PASS: every test passes (the 147 that were there, plus these 7), then `recipes ok: 5 sets x 28 slots`, `mine.json ok: 15 picks, 0 none` and `clips ok in ...` (the last only where the clips are found).

- [ ] **Step 8: Commit**

Commit:

```bash
git add tools/sounds/dsp.py tools/sounds/synth.py tests/test_sound_build.py
git commit -q -m "feat(sounds): equal-power fades, the 4 ms level scale and the hairball's retch and plop" -m "Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Placed sounds: the two recipe parts

**Files:**
- Modify: `tools/sounds/recipe.py`
- Modify: `tools/sounds/pipeline.py`
- Test: `tests/test_sound_build.py`

**Interfaces:**
- Consumes: `dsp.fade_equal_power`, `dsp.scale_to_env_peak`, `dsp.mix_at`, `dsp.seconds_slice` (Task 1 and the existing module); `synth.LAYERS` (Task 1).
- Produces in `recipe.py`: `PLACED = "placed"`; `Entry` gains two fields at the end, `segments` and `synth_layers`, both lists (empty on every ordinary entry); `parse_entry` fills them. A segment is `{"source": "<slot folder>/<file>", "start": s, "end": s, "at": s, "level": x, "fade_in_ms": ms, "fade_out_ms": ms}` (seconds; `level` is the loudest 4 ms RMS of the placed piece, 0.001 to 1; fades default to 0, 0 to 500 ms). A synth layer is `{"name": <key of synth.LAYERS>, "seed": int, "at": s}`. `at` is 0 to 10 s. An entry with `"source": "placed"` needs at least one of the two lists, and may only be in `_shared.json` (`shared=True`); any other source with either list is an error. `start` and `end` on a placed entry cut the finished timeline. `missing_sources` also names a placed entry's segment clips, each once.
- Produces in `pipeline.py`: `_placed(entry, loader)` returns the timeline as a list (every segment: window of its clip, equal-power fades, set to its level, mixed in at `round(at × 48000)`, in list order; then every synth layer mixed in the same way); `_audible(x, where, whole)` returns `x` or raises `SourceError` ("... is empty" / "... is silent"); `_source` returns a placed entry's timeline cut by `start` and `end`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_sound_build.py`, replace:

```python
    entry.update(extra)
    return entry


def write_json(path, doc):
```

with:

```python
    entry.update(extra)
    return entry


def placed(slot="slap", **extra):
    """A raw placed entry: one segment of '<slot>/c.wav' and one made-in-code layer."""
    fields = {"segments": [{"source": "%s/c.wav" % slot, "start": 0.1, "end": 0.4, "at": 0.0, "level": 0.2}],
              "synth_layers": [{"name": "hairball_retch_plop", "seed": 7, "at": 0.3}]}
    fields.update(extra)
    return raw(slot, "placed", **fields)


def write_json(path, doc):
```

In `tests/test_sound_build.py` (class `TestRecipe`), replace:

```python
    def test_sources_must_be_folder_slash_file(self):
        for src in ("fs-1-x.mp3", "nowhere/fs-1-x.mp3", "greet/../x.mp3", "greet/x.txt", "", 5):
            self.assertIn("source", self.bad(source=src), src)
```

with:

```python
    def test_sources_must_be_folder_slash_file(self):
        for src in ("fs-1-x.mp3", "nowhere/fs-1-x.mp3", "greet/../x.mp3", "greet/x.txt", "", 5):
            self.assertIn("source", self.bad(source=src), src)

    def test_a_placed_entry_parses_with_its_defaults(self):
        e = recipe.parse_entry(placed(), "t", True)
        self.assertEqual(e.source, "placed")
        self.assertEqual(e.segments, [{"source": "slap/c.wav", "start": 0.1, "end": 0.4, "at": 0.0, "level": 0.2,
                                       "fade_in_ms": 0.0, "fade_out_ms": 0.0}])
        self.assertEqual(e.synth_layers, [{"name": "hairball_retch_plop", "seed": 7, "at": 0.3}])
        plain = recipe.parse_entry(raw("slap"), "t")
        self.assertEqual((plain.segments, plain.synth_layers), ([], []))
        self.assertEqual(recipe.parse_entry(placed(segments=[]), "t", True).segments, [])      # layers alone are enough

    def bad_placed(self, shared=True, **extra):
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.parse_entry(placed(**extra), "t", shared)
        return str(ctx.exception)

    def test_a_placed_entry_belongs_in_the_shared_file_and_needs_something_to_place(self):
        self.assertIn("_shared.json", self.bad_placed(shared=False))
        self.assertIn("needs segments or synth_layers", self.bad_placed(segments=[], synth_layers=[]))
        for field in ("segments", "synth_layers"):
            self.assertIn("need the source 'placed'", self.bad(**{field: placed()[field]}))    # a plain entry may not carry them
        self.assertIn("segments must be a list", self.bad_placed(segments={}))
        self.assertIn("synth_layers must be a list", self.bad_placed(synth_layers="x"))

    def test_every_segment_field_is_checked(self):
        seg = placed()["segments"][0]

        def with_(**change):
            return self.bad_placed(segments=[dict(seg, **change)])
        for field in ("source", "start", "end", "at", "level"):
            self.assertIn("segment 1: needs %s" % field,
                          self.bad_placed(segments=[{k: v for k, v in seg.items() if k != field}]))
        self.assertIn("unknown fields ['gain']", with_(gain=1))
        self.assertIn("end must be after start", with_(start=0.5))
        for field, value in (("start", -1), ("end", "2"), ("at", -0.1), ("at", 11), ("at", float("nan")), ("level", 0),
                             ("level", 1.5), ("fade_in_ms", -1), ("fade_out_ms", 501)):
            self.assertIn(field, with_(**{field: value}), (field, value))
        for source in ("synth:blip", "placed"):
            self.assertIn("a piece of a recorded clip", with_(source=source))
        self.assertIn("excluded source", with_(source="slap/fs-732521-Lukey1028.mp3"))
        self.assertIn("source", with_(source="nowhere/x.mp3"))
        self.assertIn("must be an object", self.bad_placed(segments=["x"]))

    def test_every_synth_layer_field_is_checked(self):
        layer = placed()["synth_layers"][0]

        def with_(**change):
            return self.bad_placed(synth_layers=[dict(layer, **change)])
        for field in ("name", "seed", "at"):
            self.assertIn("synth layer 1: needs %s" % field,
                          self.bad_placed(synth_layers=[{k: v for k, v in layer.items() if k != field}]))
        self.assertIn("unknown synth layer 'hairball'", with_(name="hairball"))
        for seed in (-1, 1.5, "7", True, 2 ** 31):
            self.assertIn("seed must be a whole number", with_(seed=seed), repr(seed))
        self.assertIn("at", with_(at=-1))
        self.assertIn("unknown fields ['gain']", with_(gain=1))
        self.assertIn("must be an object", self.bad_placed(synth_layers=[3]))

    def test_missing_sources_names_a_placed_sounds_clips_once(self):
        seg = placed()["segments"][0]
        e = recipe.parse_entry(placed(segments=[dict(seg, at=a) for a in (0.0, 0.2, 0.4)]), "t", True)
        rec = recipe.SetRecipe("t", "t", 0.0, {"slap": e})
        cands = os.path.join(self.tmp, "c")
        self.assertEqual(recipe.missing_sources(rec, cands), ["slap/c.wav"])
        os.makedirs(os.path.join(cands, "slap"))
        open(os.path.join(cands, "slap", "c.wav"), "w").close()
        self.assertEqual(recipe.missing_sources(rec, cands), [])
```

In `tests/test_sound_build.py` (class `TestPipeline`), replace:

```python
    def test_a_very_quiet_clip_is_brought_up_without_clipping(self):
        self.loader.clips["greet/c.wav"] = burst(700.0, 0.4, amp=0.0005)         # -66 dBFS
        m = loudness.measure(self.build("greet").samples)
        self.assertAlmostEqual(m.lufs, -20.0, delta=1.5)
        self.assertLessEqual(m.tp_db, -1.0 + 0.05)
```

with:

```python
    def test_a_very_quiet_clip_is_brought_up_without_clipping(self):
        self.loader.clips["greet/c.wav"] = burst(700.0, 0.4, amp=0.0005)         # -66 dBFS
        m = loudness.measure(self.build("greet").samples)
        self.assertAlmostEqual(m.lufs, -20.0, delta=1.5)
        self.assertLessEqual(m.tp_db, -1.0 + 0.05)

    def placed_entry(self, **fields):
        return entry("slap", "placed", True, **fields)

    def test_a_placed_sound_puts_every_segment_at_its_place_and_level(self):
        self.loader.clips["slap/c.wav"] = sine(500, 1.0, 0.4)
        e = self.placed_entry(segments=[
            {"source": "slap/c.wav", "start": 0.0, "end": 0.20, "at": 0.0, "level": 0.1},
            {"source": "slap/c.wav", "start": 0.3, "end": 0.50, "at": 0.50, "level": 0.2}])
        x = pipeline._placed(e, self.loader)
        self.assertEqual(len(x), 33600)                                          # 0.70 s
        self.assertAlmostEqual(dsp.env_peak(x[:9600]), 0.1, places=6)           # the first piece, 0.20 s
        self.assertAlmostEqual(dsp.env_peak(x[24000:]), 0.2, places=6)          # the second, from 0.50 s
        self.assertEqual(max(abs(v) for v in x[9600:24000]), 0.0)               # nothing between them

    def test_a_placed_sounds_pieces_are_faded_levelled_and_mixed_in_that_order(self):
        clip = sine(500, 1.0, 0.4)
        self.loader.clips["slap/c.wav"] = clip
        e = self.placed_entry(segments=[
            {"source": "slap/c.wav", "start": 0.0, "end": 0.30, "at": 0.0, "level": 0.2,
             "fade_in_ms": 5.0, "fade_out_ms": 60.0},
            {"source": "slap/c.wav", "start": 0.0, "end": 0.30, "at": 0.24, "level": 0.1, "fade_in_ms": 60.0}])
        first = dsp.scale_to_env_peak(dsp.fade_equal_power(clip[:14400], 5.0, 60.0), 0.2)       # 0.30 s pieces
        second = dsp.scale_to_env_peak(dsp.fade_equal_power(clip[:14400], 60.0, 0.0), 0.1)
        self.assertEqual(pipeline._placed(e, self.loader), dsp.mix_at(first, second, 11520))    # the second at 0.24 s

    def test_a_placed_sound_mixes_in_its_synth_layers_and_the_window_cuts_the_timeline(self):
        self.loader.clips["slap/c.wav"] = sine(500, 1.0, 0.4)
        segs = [{"source": "slap/c.wav", "start": 0.0, "end": 0.1, "at": 0.0, "level": 0.1}]
        layer = {"name": "hairball_retch_plop", "seed": 7, "at": 0.3}
        x = pipeline._placed(self.placed_entry(segments=segs, synth_layers=[layer]), self.loader)
        self.assertEqual(len(x), 14400 + 31680)                                  # from 0.30 s, the layer's 660 ms
        self.assertEqual(x[14400:], synth.hairball_retch_plop(7))               # nothing else is there: exactly the layer
        cut = self.placed_entry(segments=segs, synth_layers=[layer], start=0.3, end=0.5)
        self.assertEqual(pipeline._source(cut, recipe.SLOTS["slap"], self.loader, 0.0), x[14400:24000])

    def test_a_placed_sound_longer_than_the_cap_is_cut_to_it(self):
        self.loader.clips["slap/c.wav"] = sine(500, 2.0, 0.4)
        segs = [{"source": "slap/c.wav", "start": 0.0, "end": 1.0, "at": 0.0, "level": 0.1},
                {"source": "slap/c.wav", "start": 0.0, "end": 1.0, "at": 0.9, "level": 0.1}]       # 1.9 s in all
        self.assertEqual(len(pipeline.build_slot(self.placed_entry(segments=segs), self.loader).samples), 72000)
        self.assertEqual(len(pipeline.build_slot(self.placed_entry(segments=segs, end=1.2), self.loader).samples), 57600)

    def test_a_segment_window_outside_its_clip_or_in_a_pause_is_a_clear_error(self):
        self.loader.clips["slap/c.wav"] = sine(500, 0.5, 0.4)
        seg = {"source": "slap/c.wav", "start": 0.0, "end": 0.2, "at": 0.0, "level": 0.1}
        with self.assertRaises(pipeline.SourceError) as ctx:
            pipeline.build_slot(self.placed_entry(segments=[seg, dict(seg, start=3.0, end=3.2)]), self.loader)
        for part in ("slap", "segment 2", "slap/c.wav", "empty"):
            self.assertIn(part, str(ctx.exception))
        with self.assertRaises(pipeline.SourceError) as ctx:                     # a window that cuts the timeline to nothing
            pipeline.build_slot(self.placed_entry(segments=[seg], start=5.0, end=6.0), self.loader)
        self.assertIn("empty", str(ctx.exception))
        self.loader.clips["slap/c.wav"] = [0.0] * SR
        with self.assertRaises(pipeline.SourceError) as ctx:
            pipeline.build_slot(self.placed_entry(segments=[seg]), self.loader)
        self.assertIn("silent", str(ctx.exception))
        self.assertIn("segment 1", str(ctx.exception))
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py' -k placed -k segment -k synth_layer`
Expected: FAIL: errors in the 10 new tests (`unknown fields`/`AttributeError` and the like), and the existing tests still pass.

- [ ] **Step 3: Teach the recipe about placed sounds**

In `tools/sounds/recipe.py`, replace:

```python
from synth import GAPS
```

with:

```python
from synth import GAPS, LAYERS
```

In `tools/sounds/recipe.py`, replace:

```python
FIELDS = {"slot", "source", "start", "end", "gain_db", "pitch_st", "effects", "hp_hz", "mood",
          "signature", "note"}

Entry = namedtuple("Entry", "slot source start end gain_db pitch_st effects hp_hz mood signature "
                            "note shared")
```

with:

```python
FIELDS = {"slot", "source", "start", "end", "gain_db", "pitch_st", "effects", "hp_hz", "mood",
          "signature", "note", "segments", "synth_layers"}

# A placed sound (source "placed") is built on a timeline from `segments`, pieces of recorded clips
# placed at `at` seconds, then `synth_layers`, made-in-code parts (synth.LAYERS) mixed in at `at`.
# `start` and `end` then cut the finished timeline. Only _shared.json may hold one.
PLACED = "placed"
SEGMENT_FIELDS = {"source", "start", "end", "at", "level", "fade_in_ms", "fade_out_ms"}
SYNTH_LAYER_FIELDS = {"name", "seed", "at"}
MAX_AT = 10.0                  # seconds: a placed piece starts within the first ten

Entry = namedtuple("Entry", "slot source start end gain_db pitch_st effects hp_hz mood signature "
                            "note shared segments synth_layers")
```

In `tools/sounds/recipe.py`, replace:

```python
def _check_source(source, where):
    if not isinstance(source, str) or not source:
        raise RecipeError("%s: source is missing" % where)
    low = source.lower()
```

with:

```python
def _check_source(source, where):
    if not isinstance(source, str) or not source:
        raise RecipeError("%s: source is missing" % where)
    if source == PLACED:
        return
    low = source.lower()
```

In `tools/sounds/recipe.py`, replace:

```python
def parse_entry(raw, where, shared=False):
```

with:

```python
def _segments(raw, where):
    """The pieces of a placed sound, each checked like a recipe source and filled in with defaults."""
    if not isinstance(raw, list):
        raise RecipeError("%s: segments must be a list" % where)
    out = []
    for n, seg in enumerate(raw, 1):
        here = "%s segment %d" % (where, n)
        if not isinstance(seg, dict):
            raise RecipeError("%s: must be an object" % here)
        unknown = set(seg) - SEGMENT_FIELDS
        if unknown:
            raise RecipeError("%s: unknown fields %s" % (here, sorted(unknown)))
        for field in ("source", "start", "end", "at", "level"):
            if field not in seg:
                raise RecipeError("%s: needs %s" % (here, field))
        source = seg["source"]
        if isinstance(source, str) and (source == PLACED or source.startswith("synth:")):
            raise RecipeError("%s: a segment is a piece of a recorded clip, not %r" % (here, source))
        _check_source(source, here)
        start = _num(seg["start"], here, "start", 0.0, 600.0)
        end = _num(seg["end"], here, "end", 0.0, 600.0)
        if end <= start:
            raise RecipeError("%s: end must be after start" % here)
        out.append({"source": source, "start": start, "end": end,
                    "at": _num(seg["at"], here, "at", 0.0, MAX_AT),
                    "level": _num(seg["level"], here, "level", 0.001, 1.0),
                    "fade_in_ms": _num(seg.get("fade_in_ms", 0.0), here, "fade_in_ms", 0.0, 500.0),
                    "fade_out_ms": _num(seg.get("fade_out_ms", 0.0), here, "fade_out_ms", 0.0, 500.0)})
    return out


def _synth_layers(raw, where):
    """The made-in-code parts of a placed sound: {"name": <synth.LAYERS key>, "seed": int, "at": seconds}."""
    if not isinstance(raw, list):
        raise RecipeError("%s: synth_layers must be a list" % where)
    out = []
    for n, layer in enumerate(raw, 1):
        here = "%s synth layer %d" % (where, n)
        if not isinstance(layer, dict):
            raise RecipeError("%s: must be an object" % here)
        unknown = set(layer) - SYNTH_LAYER_FIELDS
        if unknown:
            raise RecipeError("%s: unknown fields %s" % (here, sorted(unknown)))
        for field in sorted(SYNTH_LAYER_FIELDS):
            if field not in layer:
                raise RecipeError("%s: needs %s" % (here, field))
        if layer["name"] not in LAYERS:
            raise RecipeError("%s: unknown synth layer %r (known: %s)"
                              % (here, layer["name"], ", ".join(sorted(LAYERS))))
        seed = layer["seed"]
        if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed < 2 ** 31:
            raise RecipeError("%s: seed must be a whole number from 0 to 2147483647" % here)
        out.append({"name": layer["name"], "seed": seed,
                    "at": _num(layer["at"], here, "at", 0.0, MAX_AT)})
    return out


def parse_entry(raw, where, shared=False):
```

In `tools/sounds/recipe.py`, replace:

```python
    _check_source(raw.get("source"), where)
    start = raw.get("start")
```

with:

```python
    _check_source(raw.get("source"), where)
    segments = _segments(raw.get("segments", []), where)
    synth_layers = _synth_layers(raw.get("synth_layers", []), where)
    if raw["source"] == PLACED:
        if not shared:
            raise RecipeError("%s: a placed sound belongs in %s.json, where every set shares it"
                              % (where, SHARED_NAME))
        if not segments and not synth_layers:
            raise RecipeError("%s: a placed sound needs segments or synth_layers" % where)
    elif segments or synth_layers:
        raise RecipeError("%s: segments and synth_layers need the source %r" % (where, PLACED))
    start = raw.get("start")
```

In `tools/sounds/recipe.py`, replace:

```python
                 info.mood, info.signature, str(raw.get("note", "")), shared)
```

with:

```python
                 info.mood, info.signature, str(raw.get("note", "")), shared, segments, synth_layers)
```

In `tools/sounds/recipe.py`, replace:

```python
def missing_sources(recipe, candidates_dir):
    """File sources of a set that are not in the candidates folder."""
    out = []
    for e in recipe.entries.values():
        if not e.source.startswith("synth:"):
            if not os.path.isfile(os.path.join(candidates_dir, *e.source.split("/"))):
                out.append(e.source)
    return out
```

with:

```python
def missing_sources(recipe, candidates_dir):
    """File sources of a set (the clips of a placed sound's segments too) that are not in the
    candidates folder, each named once."""
    out = []
    for e in recipe.entries.values():
        for source in [seg["source"] for seg in e.segments] if e.source == PLACED else [e.source]:
            if source.startswith("synth:") or source in out:
                continue
            if not os.path.isfile(os.path.join(candidates_dir, *source.split("/"))):
                out.append(source)
    return out
```

- [ ] **Step 4: Run the recipe tests**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py' -k placed_entry -k segment_field -k synth_layer_field -k missing_sources`
Expected: PASS, 6 tests (the five new recipe tests and the existing `missing_sources` test; the pipeline tests are not selected by these names).

- [ ] **Step 5: Build placed sounds in the pipeline**

In `tools/sounds/pipeline.py`, replace:

```python
from recipe import SLOTS
from synth import GAPS
```

with:

```python
from recipe import PLACED, SLOTS
from synth import GAPS, LAYERS
```

In `tools/sounds/pipeline.py`, replace:

```python
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
```

with:

```python
def _audible(x, where, whole):
    """x, or a SourceError when the window is empty or silent. `whole` is what it was cut from."""
    if not x:
        raise SourceError("%s is empty: the clip is only %.2f s long" % (where, len(whole) / dsp.SR))
    if dsp.lin_to_db(dsp.peak(x)) < SILENT_DB:
        raise SourceError("%s is silent (peak %.0f dBFS)" % (where, dsp.lin_to_db(dsp.peak(x))))
    return x


def _placed(entry, loader):
    """The timeline of a placed sound: every segment (a window of a clip, equal-power faded, set to its
    level) mixed in at its place, then the made-in-code layers."""
    out = []
    for n, seg in enumerate(entry.segments, 1):
        where = "%s: segment %d, %s [%s..%s]" % (entry.slot, n, seg["source"], seg["start"], seg["end"])
        clip = loader.load(seg["source"])
        piece = _audible(dsp.seconds_slice(clip, seg["start"], seg["end"]), where, clip)
        piece = dsp.fade_equal_power(piece, seg["fade_in_ms"], seg["fade_out_ms"])
        out = dsp.mix_at(out, dsp.scale_to_env_peak(piece, seg["level"]), int(round(seg["at"] * dsp.SR)))
    for layer in entry.synth_layers:
        out = dsp.mix_at(out, LAYERS[layer["name"]](layer["seed"]), int(round(layer["at"] * dsp.SR)))
    return out


def _source(entry, info, loader, shift):
    if entry.source.startswith("synth:"):
        return GAPS[entry.source[6:]]()
    if entry.source == PLACED:
        timeline = _placed(entry, loader)
        where = "%s: placed [%s..%s]" % (entry.slot, entry.start, entry.end)
        return _audible(dsp.seconds_slice(timeline, entry.start, entry.end), where, timeline)
    clip = loader.load(entry.source)
    if entry.start is None and entry.end is None:
        # no explicit trim: drop the silence and keep the loudest window that still fits after the shift
        x = dsp.auto_trim(clip, info.max_len * 2.0 ** (shift / 12.0))
    else:
        x = dsp.seconds_slice(clip, entry.start, entry.end)
    where = "%s: %s [%s..%s]" % (entry.slot, entry.source, entry.start, entry.end)
    return _audible(x, where, clip)
```

- [ ] **Step 6: Run the new tests and the whole file**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py' -k placed -k segment -k synth_layer -k missing_sources`
Expected: PASS, 11 tests (the 10 new ones and the existing `missing_sources` test).

Run: `bash scripts/test-sound-build.sh`
Expected: PASS: every test passes, then `recipes ok: 5 sets x 28 slots` and the rest as before. Nothing built changed yet.

- [ ] **Step 7: Commit**

Commit:

```bash
git add tools/sounds/recipe.py tools/sounds/pipeline.py tests/test_sound_build.py
git commit -q -m "feat(sounds): placed sounds, a recipe built from clip segments and made-in-code layers" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The 29th slot, rebuilt from its recipe

**Files:**
- Modify: `tools/sounds/recipe.py`
- Modify: `tools/sounds/layers.py`
- Modify: `tools/sounds/pipeline.py`
- Modify: `tools/sounds/build_pack.py` (docstring)
- Modify: `design/sounds/sets/_shared.json`
- Modify: `design/sounds/audition.html` (its slot table only, so the page's own tests stay green)
- Test: `tests/test_sound_build.py`

**Interfaces:**
- Consumes: everything from Tasks 1 and 2.
- Produces in `recipe.py`: `SLOTS` has 29 entries, `hairball` the 19th cat moment (kind `cat`, mood `upset`, no signature, not dark, 1.5 s); `Slot` gains a last field `touch` (True for every cat moment but `hairball`, False for the ticks); every set and Your mix now carry the `hairball` entry of `_shared.json`.
- Produces in `layers.py`: `add_layers(vocal, mood, with_signature=False, dark=False, with_thump=False, with_touch=True)`.
- Produces in `audition.html`: a `hairball` row after `rate` in the `#data` slot table (Task 4 adds the `touch` field and the text).
- Produces in `_shared.json`: `{"slot": "hairball", "source": "placed", "end": 1.48, ...}` with three segments of `hairball/fs-561726-har2h.mp3` and one synth layer. `tests/test_sound_build.py` gains `HAIRBALL_CLIP`, `HAIRBALL_SHA256`, `HAIRBALL_REFERENCE` and `HAS_HAIRBALL_CLIP`, and its `SHARED_SLOTS` list gains `hairball`.

- [ ] **Step 1: Update the shared constants and the typed counts (red)**

These edits make the existing tests describe 29 slots, so they fail until the slot exists.

In `tests/test_sound_build.py`, replace:

```python
import json
import math
```

with:

```python
import hashlib
import json
import math
```

In `tests/test_sound_build.py`, replace:

```python
# The slots every set shares: the ten ticks and the three made-in-code or foley fill-ins.
SHARED_SLOTS = ["yawn", "work", "gulp", "approve", "peek", "open", "close", "hover", "blip", "tick",
                "send", "attach", "pop"]
```

with:

```python
# The slots every set shares: the ten ticks, the three made-in-code or foley fill-ins and the hairball.
SHARED_SLOTS = ["yawn", "work", "gulp", "hairball", "approve", "peek", "open", "close", "hover", "blip",
                "tick", "send", "attach", "pop"]
```

In `tests/test_sound_build.py`, replace:

```python
        self.assertEqual((len(cats), len(ticks), len(recipe.SLOTS)), (18, 10, 28))
```

with:

```python
        self.assertEqual((len(cats), len(ticks), len(recipe.SLOTS)), (19, 10, 29))
```

In `tests/test_sound_build.py`, replace:

```python
        self.assertEqual(moods["upset"], {"error", "annoyed", "rate", "dizzy"})
```

with:

```python
        self.assertEqual(moods["upset"], {"error", "annoyed", "rate", "dizzy", "hairball"})
```

In `tests/test_sound_build.py`, replace:

```python
        self.assertTrue(all(t.mood == "none" and not t.signature for t in ticks))
```

with:

```python
        self.assertTrue(all(t.mood == "none" and not t.signature for t in ticks))
        self.assertEqual(list(recipe.SLOTS)[18], "hairball")                   # the last cat moment, then the ticks
        self.assertEqual([s.name for s in cats if not s.touch], ["hairball"])    # the one cat moment without the touch
        self.assertFalse(any(t.touch for t in ticks))
```

In `tests/test_sound_build.py`, replace:

```python
    def test_load_set_needs_all_28_slots_once(self):
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "synth:blip")
        shared = recipe._entries(recipe._read(os.path.join(d, "_shared.json")), "_shared", True)
        self.assertEqual(len(recipe.load_set(os.path.join(d, "studio.json"), shared).entries), 28)
```

with:

```python
    def test_load_set_needs_every_slot_once(self):
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "synth:blip")
        shared = recipe._entries(recipe._read(os.path.join(d, "_shared.json")), "_shared", True)
        self.assertEqual(len(recipe.load_set(os.path.join(d, "studio.json"), shared).entries), len(recipe.SLOTS))
```

In `tests/test_sound_build.py`, replace:

```python
    def test_build_set_writes_28_files_and_a_second_run_is_byte_identical(self):
```

with:

```python
    def test_build_set_writes_every_slot_and_a_second_run_is_byte_identical(self):
```

In `tests/test_sound_build.py`, replace:

```python
                self.assertEqual(len(built), 28)
```

with:

```python
                self.assertEqual(len(built), len(recipe.SLOTS))
```

In `tests/test_sound_build.py`, replace:

```python
        self.assertEqual(code, 0)
        self.assertIn("recipes ok: 5 sets x 28 slots", out)
        doc = recipe._read(os.path.join(self.recipes, "steff.json"))
```

with:

```python
        self.assertEqual(code, 0)
        self.assertIn("recipes ok: 5 sets x %d slots" % len(recipe.SLOTS), out)
        doc = recipe._read(os.path.join(self.recipes, "steff.json"))
```

In `tests/test_sound_build.py`, replace:

```python
        self.assertEqual(len([f for f in os.listdir(out) if f.endswith(".wav")]), 28)
        self.assertIn("(27 of 28 files meet their targets)", stdout)
        self.assertIn("FAIL studio/tick", err)
        with open(os.path.join(out, "report.md"), encoding="utf-8") as f:
            self.assertIn("## studio: 27 of 28 pass", f.read())
```

with:

```python
        total = len(recipe.SLOTS)
        self.assertEqual(len([f for f in os.listdir(out) if f.endswith(".wav")]), total)
        self.assertIn("(%d of %d files meet their targets)" % (total - 1, total), stdout)
        self.assertIn("FAIL studio/tick", err)
        with open(os.path.join(out, "report.md"), encoding="utf-8") as f:
            self.assertIn("## studio: %d of %d pass" % (total - 1, total), f.read())
```

In `tests/test_sound_build.py`, replace:

```python
    def test_the_other_thirteen_rows_are_the_shared_sounds(self):
        rest = [s["slot"] for s in self.data["slots"] if s["slot"] not in self.data["pickable"]]
        self.assertEqual(len(rest), 13)
```

with:

```python
    def test_the_other_fourteen_rows_are_the_shared_sounds(self):
        rest = [s["slot"] for s in self.data["slots"] if s["slot"] not in self.data["pickable"]]
        self.assertEqual(len(rest), 14)
```

In `tests/test_sound_build.py`, replace:

```python
        for slot in ("tick", "yawn", "gulp", "work", "approve"):
```

with:

```python
        for slot in ("tick", "yawn", "gulp", "work", "approve", "hairball"):
```

In `tests/test_sound_build.py`, replace:

```python
        self.assertIn("built mine: 28 files", out)
        self.assertIn("(28 of 28 files meet their targets)", out)
```

with:

```python
        total = len(recipe.SLOTS)
        self.assertIn("built mine: %d files" % total, out)
        self.assertIn("(%d of %d files meet their targets)" % (total, total), out)
```

In `tests/test_sound_build.py`, replace:

```python
            self.assertIn("## mine: 28 of 28 pass", f.read())
```

with:

```python
            self.assertIn("## mine: %d of %d pass" % (total, total), f.read())
```

In `tests/test_sound_build.py`, replace:

```python
        def record(rec, loader, out, cache=None):               # stands in for the 140-file build: only who gets built
```

with:

```python
        def record(rec, loader, out, cache=None):               # stands in for the 145-file build: only who gets built
```

In `tests/test_sound_build.py`, replace:

```python
        self.assertEqual(code, 0)
        self.assertIn("recipes ok: 5 sets x 28 slots", out)
        self.assertNotIn("mine.json", out)
```

with:

```python
        self.assertEqual(code, 0)
        self.assertIn("recipes ok: 5 sets x %d slots" % len(recipe.SLOTS), out)
        self.assertNotIn("mine.json", out)
```

- [ ] **Step 2: Add the new tests (red)**

In `tests/test_sound_build.py` (class `TestLayers`), replace:

```python
        self.assertGreater(power(layer, 100.0), 20 * power(layer, 400.0))
```

with:

```python
        self.assertGreater(power(layer, 100.0), 20 * power(layer, 400.0))

    def test_a_vocal_without_the_touch_keeps_only_the_layers_asked_for(self):
        self.assertEqual(layers.add_layers(self.vocal, "upset", False, False, False, False), self.vocal)
        self.assertNotEqual(layers.add_layers(self.vocal, "upset", True, False, False, False), self.vocal)
        self.assertNotEqual(layers.add_layers(self.vocal, "upset"), self.vocal)               # the touch is on by default
```

In `tests/test_sound_build.py` (class `TestPipeline`), replace:

```python
    def test_a_segment_window_outside_its_clip_or_in_a_pause_is_a_clear_error(self):
```

with:

```python
    def test_the_hairball_gets_no_touch_layer_and_no_signature(self):
        self.loader.clips["hairball/c.wav"] = sine(300, 1.0, 0.3)
        segs = [{"source": "hairball/c.wav", "start": 0.0, "end": 0.5, "at": 0.0, "level": 0.1}]

        def plain(e):                       # the cat-moment path with no layer at all: high-pass, fades, level
            x = dsp.highpass(pipeline._placed(e, self.loader), 100.0)
            x = dsp.fade(dsp.fade(x, 3.0, 20.0), 3.0, 20.0)
            return loudness.normalize(x, -20.0, -1.0)[0]
        hairball = entry("hairball", "placed", True, segments=segs)
        self.assertEqual(pipeline.build_slot(hairball, self.loader).samples, plain(hairball))
        slap = entry("slap", "placed", True, segments=segs)                                  # a slot with the touch is not that
        self.loader.clips["slap/c.wav"] = self.loader.clips["hairball/c.wav"]
        self.assertNotEqual(pipeline.build_slot(slap, self.loader).samples, plain(slap))

    def test_a_segment_window_outside_its_clip_or_in_a_pause_is_a_clear_error(self):
```

In `tests/test_sound_build.py`, replace:

```python
    def test_five_complete_sets_of_28_slots(self):
        self.assertEqual(list(self.sets), ["studio", "steff", "kitten", "bestof", "tabby"])
        for s in self.sets.values():
            self.assertEqual(list(s.entries), list(recipe.SLOTS))
```

with:

```python
    def test_five_complete_sets_of_every_slot(self):
        self.assertEqual(list(self.sets), ["studio", "steff", "kitten", "bestof", "tabby"])
        for s in self.sets.values():
            self.assertEqual(list(s.entries), list(recipe.SLOTS))
            self.assertEqual(len(s.entries), 29)

    def test_the_hairball_is_one_placed_sound_shared_by_every_set(self):
        for name, s in self.sets.items():
            e = s.entries["hairball"]
            self.assertEqual((e.shared, e.source, e.mood, e.signature, e.end), (True, "placed", "upset", False, 1.48), name)
            self.assertEqual(e, self.sets["studio"].entries["hairball"], name)
        e = self.sets["studio"].entries["hairball"]
        self.assertEqual({seg["source"] for seg in e.segments}, {HAIRBALL_CLIP})
        self.assertEqual([layer["name"] for layer in e.synth_layers], ["hairball_retch_plop"])
        self.assertNotIn("hairball", recipe.pickable_moments(self.sets))

    def test_the_hairballs_beats_land_on_the_animations(self):
        # spec, "Hairball": three real coughs whose onsets fall at about 115, 435 and 755 ms (the heave peaks are at
        # 140, 460 and 780), joined with 60 ms equal-power fades; the plop at 1110 ms, when the ball comes out
        e = self.sets["studio"].entries["hairball"]
        onsets = (2.258, 4.276, 7.358)            # where each cough starts in har2h's clip, measured on the decoded audio
        for seg, onset, want in zip(e.segments, onsets, (115, 435, 755)):
            self.assertAlmostEqual((seg["at"] + onset - seg["start"]) * 1000.0, want, delta=1.0)
            self.assertEqual(seg["fade_out_ms"], 60.0)
            self.assertGreater(seg["end"] - onset, 0.29)                     # a cough's whole decay is in its window
        for a, b in zip(e.segments, e.segments[1:]):
            self.assertLess(b["at"], a["at"] + (a["end"] - a["start"]))      # each piece overlaps the next: a crossfade
        layer = e.synth_layers[0]
        self.assertAlmostEqual(layer["at"] * 1000.0 + synth.RETCH_TO_PLOP_MS, 1110.0, delta=1.0)
        self.assertEqual(layer["seed"], 1205)

    def test_your_mix_has_an_entry_for_every_slot_and_the_hairball_is_the_shared_one(self):
        round2, mix = build_pack.load_extras(SETS_DIR, self.sets)
        mine = recipe.mix_recipe(mix, self.sets, round2)
        self.assertEqual(list(mine.entries), list(recipe.SLOTS))
        self.assertEqual(len(mine.entries), 29)
        self.assertEqual(mine.entries["hairball"], self.sets["studio"].entries["hairball"])
        self.assertTrue(mine.entries["hairball"].shared)
        self.assertEqual(len(mix.picks), 15)                                 # the hairball is not one of the picks
        self.assertNotIn("hairball", mix.picks)

    def test_the_usage_text_counts_the_slots_the_build_has(self):
        self.assertIn("%d WAVs in --out" % len(recipe.SLOTS), build_pack.__doc__)
        self.assertIn("Your mix: %d WAVs" % len(recipe.SLOTS), build_pack.__doc__)
```

In `tests/test_sound_build.py`, replace:

```python
CANDIDATES = build_pack.find_candidates()
```

with:

```python
CANDIDATES = build_pack.find_candidates()
HAIRBALL_CLIP = "hairball/fs-561726-har2h.mp3"
HAIRBALL_SHA256 = "77f70082aa72a6ce68a8137f69002960b29995f3e7da9882882db5e1dfdec1ca"     # B.wav, the owner's pick of 2026-10-05
# B.wav itself is git-ignored: $NM_HAIRBALL_REFERENCE, else next to the candidates folder (.claude/sounds/build/hairball/B.wav
# in the main checkout, which a worktree shares). Without it the SHA-256 above is the reference.
HAIRBALL_REFERENCE = os.environ.get("NM_HAIRBALL_REFERENCE") or (
    os.path.join(os.path.dirname(CANDIDATES), "build", "hairball", "B.wav") if CANDIDATES else "")
HAS_HAIRBALL_CLIP = bool(CANDIDATES) and os.path.isfile(os.path.join(CANDIDATES, *HAIRBALL_CLIP.split("/")))
```

In `tests/test_sound_build.py`, replace:

```python
class TestAuditionPage(unittest.TestCase):
```

with:

```python
class TestOnTheRealClips(unittest.TestCase):
    """Local-only checks: they need macOS afconvert and the git-ignored candidate clips, and skip without them."""

    @unittest.skipUnless(HAS_AFCONVERT and HAS_HAIRBALL_CLIP, "needs afconvert and the har2h clip")
    def test_the_hairballs_recipe_rebuilds_the_audition_file_byte_for_byte(self):
        tmp = tempfile.mkdtemp(prefix="nm hairball ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        sets = recipe.load_recipes(SETS_DIR)
        built = pipeline.build_slot(sets["studio"].entries["hairball"], audio_io.AfconvertLoader(CANDIDATES))
        path = os.path.join(tmp, "hairball.wav")
        audio_io.write_wav16(path, built.samples)
        got = read_bytes(path)
        self.assertEqual(hashlib.sha256(got).hexdigest(), HAIRBALL_SHA256)
        if os.path.isfile(HAIRBALL_REFERENCE):                              # the audition file itself, when it is there
            self.assertEqual(got, read_bytes(HAIRBALL_REFERENCE))
        self.assertEqual(len(audio_io.read_wav(path)[0]), round(1.48 * SR))

    @unittest.skipUnless(HAS_AFCONVERT and CANDIDATES, "needs afconvert and the candidate clips")
    def test_your_mix_builds_all_the_files_with_the_hairball_in_them_and_on_target(self):
        tmp = tempfile.mkdtemp(prefix="nm real mix ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = build_pack.main(["--set", "mine", "--out", os.path.join(tmp, "mine"), "--report"])
        self.assertEqual(code, 0, err.getvalue())
        total = len(recipe.SLOTS)
        self.assertIn("built mine: %d files" % total, out.getvalue())
        self.assertIn("(%d of %d files meet their targets)" % (total, total), out.getvalue())
        wavs = sorted(f for f in os.listdir(os.path.join(tmp, "mine")) if f.endswith(".wav"))
        self.assertEqual(wavs, sorted(s + ".wav" for s in recipe.SLOTS))
        self.assertIn("hairball.wav", wavs)


class TestAuditionPage(unittest.TestCase):
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py'`
Expected: FAIL: errors across the file, because `SHARED_SLOTS` names a slot `recipe.SLOTS` does not have (`KeyError: 'hairball'`) and `Slot` has no `touch`.

- [ ] **Step 4: Add the slot and the touch flag**

In `tools/sounds/recipe.py`, replace:

```python
"""The 28 slots, and loading and validating the set recipes in design/sounds/sets/.

A recipe entry says how one slot is built. `_shared.json` holds the entries every set shares (the
ticks and the made-in-code fill-ins); each set file holds the rest. A set is complete when the two
together cover all 28 slots, once each.
"""
```

with:

```python
"""The slots, and loading and validating the set recipes in design/sounds/sets/.

A recipe entry says how one slot is built. `_shared.json` holds the entries every set shares (the
ticks, the made-in-code fill-ins and the hairball); each set file holds the rest. A set is complete
when the two together cover every slot, once each.
"""
```

In `tools/sounds/recipe.py`, replace:

```python
Slot = namedtuple("Slot", "name kind mood signature dark max_len")
```

with:

```python
Slot = namedtuple("Slot", "name kind mood signature dark max_len touch")
```

In `tools/sounds/recipe.py`, replace:

```python
        ("work", "calm"), ("rate", "upset")]
```

with:

```python
        ("work", "calm"), ("rate", "upset"), ("hairball", "upset")]
```

In `tools/sounds/recipe.py`, replace:

```python
_SIGNATURE = ("greet", "finish", "approval", "question", "error", "love")

SLOTS = OrderedDict()
for _name, _mood in _CAT:
    SLOTS[_name] = Slot(_name, "cat", _mood, _name in _SIGNATURE, _name == "error",
                        3.0 if _name == "sleep" else 1.5)
for _name in _TICKS:
    SLOTS[_name] = Slot(_name, "tick", "none", False, False, 0.4)
```

with:

```python
_SIGNATURE = ("greet", "finish", "approval", "question", "error", "love")
_NO_TOUCH = ("hairball",)        # a hack has no voice to colour: no touch layer (spec section 3, "Hairball")

SLOTS = OrderedDict()
for _name, _mood in _CAT:
    SLOTS[_name] = Slot(_name, "cat", _mood, _name in _SIGNATURE, _name == "error",
                        3.0 if _name == "sleep" else 1.5, _name not in _NO_TOUCH)
for _name in _TICKS:
    SLOTS[_name] = Slot(_name, "tick", "none", False, False, 0.4, False)
```

In `tools/sounds/recipe.py`, replace:

```python
    cover all 28 slots in SLOTS order."""
```

with:

```python
    cover every slot in SLOTS order."""
```

In `tools/sounds/recipe.py`, replace:

```python
    """Your mix as a SetRecipe named 'mine' (28 entries in SLOTS order, pitch_st 0.0): each picked moment
    copies the picked entry, the 13 shared sounds are the sets' shared entries (the entries of
    _shared.json). Raises MixPending
    while any moment is none."""
```

with:

```python
    """Your mix as a SetRecipe named 'mine' (an entry for every slot, in SLOTS order, pitch_st 0.0): each
    picked moment copies the picked entry, the shared sounds are the sets' shared entries (the entries of
    _shared.json). Raises MixPending while any moment is none."""
```

In `tools/sounds/layers.py`, replace:

```python
def add_layers(vocal, mood, with_signature=False, dark=False, with_thump=False):
    """The vocal with its layers mixed in. Every layer is scaled against the vocal alone, never
    against the other layers. The result can run past the vocal's end."""
    out = list(vocal)
    parts = [touch_layer(vocal, mood)]
```

with:

```python
def add_layers(vocal, mood, with_signature=False, dark=False, with_thump=False, with_touch=True):
    """The vocal with its layers mixed in. Every layer is scaled against the vocal alone, never
    against the other layers. The result can run past the vocal's end. The hairball is the one cat
    moment without the touch."""
    out = list(vocal)
    parts = [touch_layer(vocal, mood)] if with_touch else []
```

In `tools/sounds/pipeline.py`, replace:

```python
        x = layers.add_layers(x, entry.mood, entry.signature, info.dark,
                              any(fx["type"] == "thump" for fx in entry.effects))
```

with:

```python
        x = layers.add_layers(x, entry.mood, entry.signature, info.dark,
                              any(fx["type"] == "thump" for fx in entry.effects), info.touch)
```

In `tools/sounds/pipeline.py`, replace:

```python
    """Build all 28 slots of a SetRecipe into out_dir/<slot>.wav.
```

with:

```python
    """Build every slot of a SetRecipe into out_dir/<slot>.wav.
```

- [ ] **Step 5: Run the tests**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py'`
Expected: FAIL, but only in the tests that read the real recipes or the page: `missing slots ['hairball']` from `load_recipes(SETS_DIR)` (the `TestRealRecipes` class cannot even start, so its tests drop out of the count), the audition page tests (the page has no `hairball` row yet) and the real-mix build in `TestOnTheRealClips`. Everything built from the tests' own recipes passes.

- [ ] **Step 6: Write the hairball's recipe**

In `design/sounds/sets/_shared.json`, replace:

```json
    {"slot": "approve", "source": "approve/fs-487999-BenDrain.mp3"
```

with:

```json
    {"slot": "hairball", "source": "placed", "end": 1.48, "mood": "upset", "signature": false,
     "segments": [
       {"source": "hairball/fs-561726-har2h.mp3", "start": 2.143, "end": 2.558, "at": 0.0, "level": 0.132, "fade_in_ms": 5.0, "fade_out_ms": 60.0},
       {"source": "hairball/fs-561726-har2h.mp3", "start": 4.196, "end": 4.576, "at": 0.355, "level": 0.1716, "fade_in_ms": 48.0, "fade_out_ms": 60.0},
       {"source": "hairball/fs-561726-har2h.mp3", "start": 7.278, "end": 7.658, "at": 0.675, "level": 0.22, "fade_in_ms": 48.0, "fade_out_ms": 60.0}],
     "synth_layers": [{"name": "hairball_retch_plop", "seed": 1205, "at": 0.93}],
     "note": "The owner's pick of 2026-10-05, version B, the hybrid. Three real dry coughs from har2h's Cat Coughing (Freesound 561726, CC0). The coughs start at 2.258, 4.276 and 7.358 s in the clip; each window runs from before its cough (115 ms for the first, 80 ms for the others) to 300 ms after it, and the pieces are placed so the onsets fall at 115, 435 and 755 ms, just before the animation's heave peaks at 140, 460 and 780 ms. They are joined with equal-power fades (60 ms out; 48 ms in, 5 ms for the first), and their levels follow the mouth: 0.60, 0.78 and 1.00 of 0.22 on the 4 ms RMS scale. Then the made-in-code retch from 930 ms and the plop at 1110 ms, when the ball comes out (synth.hairball_retch_plop, seed 1205). 1.48 s. No touch layer, no signature; plays at rate 1 for every cat."},
    {"slot": "approve", "source": "approve/fs-487999-BenDrain.mp3"
```

- [ ] **Step 7: Give the audition page its 29th row**

The page's own tests compare its slot table with the build and with `SHARED_SLOTS`, so the row goes in now. Task 4 does the rest of the page.

In `design/sounds/audition.html`, replace:

```json
{"slot":"rate","kind":"cat","mood":"upset","signature":false,"dark":false,"when":"rate-limited"},
```

with:

```json
{"slot":"rate","kind":"cat","mood":"upset","signature":false,"dark":false,"when":"rate-limited"},
{"slot":"hairball","kind":"cat","mood":"upset","signature":false,"dark":false,"when":"the engine's hairball note: a refused file, Playful's error, the emote"},
```

- [ ] **Step 8: Update the usage text**

In `tools/sounds/build_pack.py`, replace:

```python
  build_pack.py --set studio --candidates DIR --out DIR   one set, 28 WAVs in --out
```

with:

```python
  build_pack.py --set studio --candidates DIR --out DIR   one set, 29 WAVs in --out
```

In `tools/sounds/build_pack.py`, replace:

```python
  build_pack.py --set mine [--report]                     Your mix: 28 WAVs from the owner's picks
```

with:

```python
  build_pack.py --set mine [--report]                     Your mix: 29 WAVs from the owner's picks
```

In `tools/sounds/build_pack.py`, replace:

```python
Needs Python 3 and, for decoding the candidate clips, macOS afconvert. Nothing else.
```

with:

```python
The hairball is the 29th sound and the same in every set. It is a placed sound: the recipe in
design/sounds/sets/_shared.json lays three coughs of one recording on a timeline and mixes in a retch and
plop made in code (recipe.py, source "placed"). It rebuilds the owner's pick of 2026-10-05 (the audition
file B.wav) byte for byte, which tests/test_sound_build.py checks wherever the clip is found.

Needs Python 3 and, for decoding the candidate clips, macOS afconvert. Nothing else.
```

- [ ] **Step 9: Run the whole suite, the recipe check and the builds**

Run: `bash scripts/test-sound-build.sh`
Expected: PASS: `Ran 172 tests` and `OK` (the 147 from before, plus 7 from Task 1, 10 from Task 2 and 8 from this task), then `recipes ok: 5 sets x 29 slots`, `mine.json ok: 15 picks, 0 none` and `clips ok in ...`. Without the clips the real-clip tests are skipped, not failed.

Run: `python3 tools/sounds/build_pack.py --check-recipes`
Expected: PASS: `recipes ok: 5 sets x 29 slots`.

Run: `python3 tools/sounds/build_pack.py --set studio --out "${TMPDIR:-/tmp}/c1c-new/studio" --report`
Expected: PASS: `built studio: 29 files`, `(29 of 29 files meet their targets)`. In `report.md` the hairball row reads `| hairball | cat | -20.0 | -25.0 | -6.54 | 1.48 | 0.0 | pass |`.

Run: `shasum -a 256 "${TMPDIR:-/tmp}/c1c-new/studio/hairball.wav"`
Expected: PASS: `77f70082aa72a6ce68a8137f69002960b29995f3e7da9882882db5e1dfdec1ca`, the same as `B.wav`.

- [ ] **Step 10: Commit**

Commit:

```bash
git add tools/sounds/recipe.py tools/sounds/layers.py tools/sounds/pipeline.py tools/sounds/build_pack.py design/sounds/sets/_shared.json design/sounds/audition.html tests/test_sound_build.py
git commit -q -m "feat(sounds): the hairball, the 29th slot, rebuilt from its recipe" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The audition page

**Files:**
- Modify: `design/sounds/audition.html`
- Test: `tests/test_sound_build.py`

**Interfaces:**
- Consumes: `recipe.SLOTS` with `touch` (Task 3), `SHARED_SLOTS` in the tests, the `hairball` row Task 3 put in the page's slot table.
- Produces: every row of the page's `#data` slot table gets `"touch": true|false` (between `dark` and `when`), and a row without the touch shows the chip "no layers". The page's text counts 29 sounds and 14 shared rows. It asks for 5 sets × 29 slots = 145 files, and Play my mix queues 29.

- [ ] **Step 1: Write the failing tests**

In `tests/test_sound_build.py`, replace:

```python
        page = [(s["slot"], s["kind"], s["mood"], s["signature"], s["dark"]) for s in self.data["slots"]]
        build = [(i.name, i.kind, i.mood, i.signature, i.dark) for i in recipe.SLOTS.values()]
```

with:

```python
        page = [(s["slot"], s["kind"], s["mood"], s["signature"], s["dark"], s["touch"]) for s in self.data["slots"]]
        build = [(i.name, i.kind, i.mood, i.signature, i.dark, i.touch) for i in recipe.SLOTS.values()]
```

In `tests/test_sound_build.py`, replace:

```python
        self.assertEqual(sorted(rest), sorted(SHARED_SLOTS))
        self.assertIn("same in every set", self.html)
```

with:

```python
        self.assertEqual(sorted(rest), sorted(SHARED_SLOTS))
        self.assertIn("same in every set", self.html)
        self.assertIn("The other %d rows are the same in every set" % len(SHARED_SLOTS), self.html)

    def test_the_hairball_row_is_a_shared_cat_moment_with_no_layers(self):
        row = next(s for s in self.data["slots"] if s["slot"] == "hairball")
        self.assertEqual((row["kind"], row["mood"], row["signature"], row["touch"]), ("cat", "upset", False, False))
        self.assertNotIn("hairball", self.data["pickable"])
        slots = [s["slot"] for s in self.data["slots"]]
        self.assertEqual(slots[slots.index("rate") + 1], "hairball")             # the last cat moment, before the ticks
        self.assertIn("if (!s.touch) {", self.html)                              # a row without the touch says "no layers"

    def test_the_page_asks_for_a_file_per_set_and_slot_and_says_how_many_sounds(self):
        self.assertEqual(len(self.data["slots"]), len(recipe.SLOTS))
        self.assertEqual(len(self.data["sets"]) * len(self.data["slots"]), 145)         # 5 sets x 29 sounds
        self.assertIn("Five complete sets of the %d sounds" % len(recipe.SLOTS), self.html)
        self.assertIn("hairball are the same in all five", self.html)
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py' -k TestAuditionPage -k TestAuditionPicker`
Expected: FAIL: `KeyError: 'touch'` in two tests, and the texts "The other 14 rows are the same in every set" and "Five complete sets of the 29 sounds" not found (2 failures, 2 errors).

- [ ] **Step 3: Update the page's slot table**

This rewrites the `slots` rows of the `#data` block in the build's own slot order and adds `touch` from the slot table to every row, so the page cannot disagree with `recipe.py`. The rows' other fields and their `when` texts are kept.

Run:

```bash
python3 - <<'PY'
import json, re, sys
sys.path.insert(0, "tools/sounds")
import recipe
path = "design/sounds/audition.html"
html = open(path, encoding="utf-8").read()
m = re.search(r'("slots":\[\n)(.*?)(\]\}\n</script>)', html, re.S)
old = {}
for line in m.group(2).strip().split("\n"):
    row = json.loads(line.rstrip(","))
    old[row["slot"]] = row
rows = []
for slot, info in recipe.SLOTS.items():
    r = old[slot]
    rows.append(json.dumps({"slot": r["slot"], "kind": r["kind"], "mood": r["mood"], "signature": r["signature"],
                            "dark": r["dark"], "touch": info.touch, "when": r["when"]},
                           separators=(",", ":"), ensure_ascii=False))
open(path, "w", encoding="utf-8").write(html[:m.start(2)] + ",\n".join(rows) + html[m.end(2):])
PY
```

Expected: PASS: no output. `git diff --stat design/sounds/audition.html` shows one file changed, and `grep -c '"touch"' design/sounds/audition.html` prints 29.

- [ ] **Step 4: Update the page's text and its chips**

In `design/sounds/audition.html`, replace:

```html
(sub-project C, stages 1 and 1b)
```

with:

```html
(sub-project C, stages 1, 1b and 1c)
```

In `design/sounds/audition.html`, replace:

```html
Five complete sets of the 28 sounds. They differ only in the cat's voice; the ticks, yawn, work and gulp are the same in all five
```

with:

```html
Five complete sets of the 29 sounds. They differ only in the cat's voice; the ticks, yawn, work, gulp and hairball are the same in all five
```

In `design/sounds/audition.html`, replace:

```html
Ticks get neither. The per-cat voice (pitch offset) and the chattiness volume are applied in the app at play time, so they are not in these files.
```

with:

```html
Ticks get neither, and neither does the hairball, which is real coughs plus a retch and plop made in code. The per-cat voice (pitch offset) and the chattiness volume are applied in the app at play time, so they are not in these files; the hairball plays at normal speed for every cat, so its retch stays on the beat.
```

In `design/sounds/audition.html`, replace:

```html
The other 13 rows are the same in every set
```

with:

```html
The other 14 rows are the same in every set
```

In `design/sounds/audition.html`, replace:

```js
  var sharedTds = [];      // the "same in every set" cells of the 13 shared rows
```

with:

```js
  var sharedTds = [];      // the "same in every set" cells of the 14 shared rows
```

In `design/sounds/audition.html`, replace:

```js
  // the 28 sounds in slot order: a pick from its set's (or round two's) file, a shared sound from the
```

with:

```js
  // the 29 sounds in slot order: a pick from its set's (or round two's) file, a shared sound from the
```

In `design/sounds/audition.html`, replace:

```js
      // 140 files are asked for at once, and a simple local web server can drop some of them on a cold
```

with:

```js
      // 145 files are asked for at once, and a simple local web server can drop some of them on a cold
```

In `design/sounds/audition.html`, replace:

```js
      if (s.kind === "tick") {
        chips.appendChild(el("span", "chip", "no layers"));
      } else {
```

with:

```js
      if (!s.touch) {
        chips.appendChild(el("span", "chip", "no layers"));
      } else {
```

In `tests/test_sound_build.py`, replace:

```python
        # controller's ruling, kept: a simple server can drop a request on a cold load of 140 files
```

with:

```python
        # controller's ruling, kept: a simple server can drop a request on a cold load of 145 files
```

- [ ] **Step 5: Run the page tests and the whole suite**

Run: `python3 -m unittest discover -s tests -p 'test_sound_build.py' -k TestAuditionPage -k TestAuditionPicker`
Expected: PASS, every page test.

Run: `bash scripts/test-sound-build.sh`
Expected: PASS: `Ran 174 tests` and `OK` (the 172 from Task 3 and 2 new page tests), then the three check lines.

- [ ] **Step 6: Look at the page in a browser**

Not scripted: this step is a human-style check with the Browser pane (or `playwright-cli`), from a `file://` URL: no server is started, and nothing may be started or stopped on port 8768. If no browser tool will open a `file:` URL in your session (the Browser pane needs the project folder open; `playwright-cli` blocks the protocol), say so in the report and do not work around it: Task 4's tests cover the page's data and text, and this step only adds the run-time view.

Build the files the page plays, if they are not there yet: `python3 tools/sounds/build_pack.py --all --report` and `python3 tools/sounds/build_pack.py --set mine --report` (they write to `.claude/sounds/build/`, which is git-ignored).

1. Open `design/sounds/audition.html` as a `file://` URL. After a moment the status line reads `145 of 145 files found.` and there is no red banner. The **Cat moments** group ends with a `hairball` row (after `rate`), with the chip "no layers", the text "the engine's hairball note: a refused file, Playful's error, the emote", five Play buttons of `1.48 s` each, and "same in every set" in the last column, with no select dots. The 13 other shared rows say the same, and `greet` still shows its chips `touch: happy` and `signature`.
2. Put Your mix's picks in the page: in the page's console, `localStorage.setItem("notchmeow.audition.picks", JSON.stringify({picks: <the picks object of design/sounds/sets/mine.json>, locked: false}))`, then reload. The counter reads `15 of 15 picked`. Click **Play my mix**: the status line reads `Playing my mix: greet (1 of 29)`. Click it again to stop.
3. Review Focus 5: temporarily move the five `hairball.wav` files of `.claude/sounds/build/` (the five set folders) out of the way and reload: the status line reads `140 of 145 files found; run build_pack.py --all for the rest.`, the banner says `5 of 145 sound files are missing.`, the five hairball cells say "missing", and Play my mix reads `Playing my mix (no sound yet for hairball): greet (1 of 28)`. Put the files back (or rebuild) and reload.

Expected: all three as described. Report the status lines you saw. Leave `localStorage` as you found it (remove the key you set).

- [ ] **Step 7: Commit**

Commit:

```bash
git add design/sounds/audition.html tests/test_sound_build.py
git commit -q -m "feat(sounds): the audition page shows the hairball among the shared rows" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The record, and the final checks

**Files:**
- Create: `design/sounds/cc0-candidates-hairball.md` (copied from the main checkout, where it is untracked, plus an outcome section)

**Interfaces:**
- Consumes: the whole branch.
- Produces: the research file committed as the record; the evidence for the final report.

- [ ] **Step 1: Bring the research file in**

The research that found the clips was written in the main checkout and is not committed there. Copy it unless it is already in the tree.

Run: `test -f design/sounds/cc0-candidates-hairball.md || cp "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/design/sounds/cc0-candidates-hairball.md" design/sounds/`
Expected: PASS, and `design/sounds/cc0-candidates-hairball.md` exists (`head -1` of it reads `# CC0 cat sound candidates, the hairball (sub-project C)`).

- [ ] **Step 2: Add the outcome**

Append to `design/sounds/cc0-candidates-hairball.md`:

```markdown

## Outcome, 2026-10-05

The owner auditioned three versions built from these clips and picked **B, the hybrid**: three coughs of har2h's *Cat Coughing* (rank 2) with the retch and plop of "The made-in-code fallback" (version A used rank 1's heaves and its own final hurk; version C was all made in code). Electron John's *cat vomit 2* is therefore not in the shipped recipe, and the rank 3 clip was never downloaded.

The windows above were estimates, and the build uses measured ones: the coughs of the decoded har2h clip start at 2.258, 4.276 and 7.358 s (the estimates were 2.23, 4.25 and 7.32 s). The recipe is the `hairball` entry of `design/sounds/sets/_shared.json`, a placed sound (`recipe.py`, source `placed`): three windows of the clip, equal-power faded and placed so the onsets fall at 115, 435 and 755 ms, then `synth.hairball_retch_plop` (seed 1205) at 930 ms. `tests/test_sound_build.py` checks that it rebuilds the audition file `B.wav` byte for byte (SHA-256 `77f70082aa72a6ce68a8137f69002960b29995f3e7da9882882db5e1dfdec1ca`) wherever the clip is found.

Stage 2 swaps the preview mp3 for the full-quality original. The decoded timeline may shift (a decoder's start padding), so re-measure the three onsets on the original, move the windows to match, and pin the new SHA-256 in the test.
```

- [ ] **Step 3: Commit**

Commit:

```bash
git add design/sounds/cc0-candidates-hairball.md
git commit -q -m "docs(sounds): the hairball research, with the outcome of the owner's pick" -m "Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: The full test script**

Run: `bash scripts/test-sound-build.sh`
Expected: PASS: `Ran 174 tests` and `OK`, then `recipes ok: 5 sets x 29 slots`, `mine.json ok: 15 picks, 0 none`, `clips ok in ...`.

- [ ] **Step 5: Every set and Your mix**

Run: `python3 tools/sounds/build_pack.py --all --report --out "${TMPDIR:-/tmp}/c1c-new/all"`
Expected: PASS: `report: .../report.md (145 of 145 files meet their targets)`.

Run: `python3 tools/sounds/build_pack.py --set mine --report --out "${TMPDIR:-/tmp}/c1c-new/mine"`
Expected: PASS: `built mine: 29 files`, `(29 of 29 files meet their targets)`.

- [ ] **Step 6: Nothing old moved, and the hairball is the owner's pick**

Compare every file of the baseline from Task 1 with its new build, and the new hairball with `B.wav`. It needs the baseline from Task 1 (skip this step, and say so, if it could not be built).

Run:

```bash
python3 - <<'PY'
import hashlib, os, sys
sys.path.insert(0, "tools/sounds")
import build_pack
tmp = os.environ.get("TMPDIR", "/tmp")
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
same = differ = 0
for kind, names in (("all", ["studio", "steff", "kitten", "bestof", "tabby"]), ("mine", [""])):
    for n in names:
        old, new = os.path.join(tmp, "c1c-base", kind, n), os.path.join(tmp, "c1c-new", kind, n)
        for f in sorted(os.listdir(old)):
            if f.endswith(".wav"):
                if sha(os.path.join(old, f)) == sha(os.path.join(new, f)):
                    same += 1
                else:
                    differ += 1
                    print("DIFFERS", kind, n, f)
print("identical=%d differ=%d" % (same, differ))
ref = os.environ.get("NM_HAIRBALL_REFERENCE") or os.path.join(os.path.dirname(build_pack.find_candidates()), "build", "hairball", "B.wav")
mine = os.path.join(tmp, "c1c-new", "mine", "hairball.wav")
print("hairball.wav", sha(mine))
print("B.wav       ", sha(ref))
sys.exit(1 if differ or sha(mine) != sha(ref) else 0)
PY
```

Expected: PASS: `identical=168 differ=0` (140 files of the five sets and 28 of Your mix), and the two SHA-256 lines equal, `77f70082aa72a6ce68a8137f69002960b29995f3e7da9882882db5e1dfdec1ca`.

- [ ] **Step 7: What the branch changed**

Run: `git status --short`
Expected: PASS: nothing is listed (every change is committed, and the build folder and the clips are git-ignored).

Run: `git diff --stat "$(git merge-base notchmeow/rebrand HEAD)" HEAD -- . ':!docs/superpowers/plans'`
Expected: PASS: ten files and nothing else: `design/sounds/audition.html`, `design/sounds/cc0-candidates-hairball.md`, `design/sounds/sets/_shared.json`, `tests/test_sound_build.py` and `tools/sounds/{build_pack,dsp,layers,pipeline,recipe,synth}.py`. Nothing under `NotchBuddy/`, `windows/`, `design/prototype/`, `tests/cat/` or `tests/fixtures/`.


---

## Files touched, and overlap

**This plan changes:** `tools/sounds/dsp.py`, `synth.py`, `recipe.py`, `pipeline.py`, `layers.py`, `build_pack.py` (docstring only); `design/sounds/sets/_shared.json`; `design/sounds/audition.html`; `design/sounds/cc0-candidates-hairball.md` (new); `tests/test_sound_build.py`. It reads but does not change the spec (the controller commits its edit first), `mine.json` (15 picks, unchanged), the five set files, `scripts/test-sound-build.sh` and `.github/workflows/build.yml`.

**Overlap with the running plans: none in files.** The cat plans (`2026-10-04-a-mac-cats-stages-1-4.md`, `2026-10-04-a-tauri-cats-stages-1-4.md`) change `NotchBuddy/`, `windows/`, `design/prototype/`, `tests/cat/`, `tests/fixtures/cat/` and `docs/CAT-CONTRACT.md`; the three port plans of 2026-10-05 change `NotchBuddy/`, `windows/`, `scripts/check-plist-version.sh`, `scripts/release.sh`, `.github/workflows/build.yml`, `README.md`, `CHANGELOG.md` and `docs/`. One **meaning** overlap, for Stage 3 and not now: the Mac cat plan still plays `annoyed` for the refused-file gag (`FileDropView.swift`) and `pop` is not yet wired; the hairball sound replaces that pair (see below).

**Overlap with the Stage 2 plan** (`2026-10-05-c2-final-pack.md`, drafted after this one, from this plan's shape): it touches `tools/sounds/{build_pack,dsp,pipeline}.py`, `tests/test_sound_build.py` and `design/sounds/audition.html` (two `voice` strings), among other files, so it must start after this plan has merged. It anchors its edits on text this plan leaves alone (the line `def _source(`, which this plan keeps once, `TARGETS`, `dsp.seconds_slice` and the trims, the two voice strings). The hairball hands it three things: (1) the swap from the preview mp3 to the original WAV, which can shift the timeline by a decoder's start padding, so the three windows need re-checking on the original and `HAIRBALL_SHA256` in the tests needs a second pin or a retirement once the shipped file is the reference (Stage 2 chooses to keep this recipe on the preview and map the original onto it, which leaves the byte test working); (2) "all 29 files exist" and `sources.json` / `SOUND-CREDITS.md` need the har2h clip's CC0 entry (it is in the manifest already; the Electron John clip is not used); (3) `build_pack.py --set mine --out NotchBuddy/Resources/sounds` now writes 29 WAVs, and `NotchBuddy/Resources/sounds/README.md` (its list of 28 expected files) and `windows/README.md` (line "The 28 sounds") gain the new name at the same time.

## Notes for Stage 3 (wiring, after sub-project A)

There is no `tests/fixtures/sound/` folder yet, so no `rules.json` to extend: the play rules and the per-slot exceptions are Stage 3's to write. When it writes them, the hairball carries:

- **Rate:** the hairball plays at rate 1 for every cat. The per-cat voice offset (`tests/fixtures/cat/presets.json`, the `voice` field) applies to cat moments except this one, and a test says so for both apps (`AVAudioPlayer.rate` on macOS, `playbackRate` on Windows/Linux). The chattiness volume still applies.
- **Priority:** "the hairball may replace the error sound it follows": Playful's error hiss ends in the hairball 900 ms later. A shared test pairs `error` playing and then `hairball` starting.
- **Trigger:** the engine's `hairball` note (a refused file, Playful's error, the emote), not the file drop or the error. A refused file shifts every beat by 120 ms and Playful's error by 900 ms.
- **Cooldown and visibility:** the hairball is an ordinary cat moment (once per 2 s) and, like `annoyed`, not an alert: it plays only while the island is visible.
- **Slot lists in the apps:** `NotchBuddy/Sources/App/SoundEngine.swift` (its name list), `windows/src/core/sound.ts` and the two READMEs name the 28 files; each gains `hairball`. The cat plans' calls that play `annoyed` for the refused-file gag are replaced by one `hairball` on the note.

## Self-review

**Spec coverage** (section "Hairball", Slots, the wiring table, the exceptions, Stage 1c):
- 29 slots, `hairball` a cat moment, mood upset, shared and not pickable, no touch or signature: Task 3 (slot table with `touch`, `_shared.json`, tests "slot table", "shared by every set", "your mix has an entry for every slot").
- Three real coughs at 115, 435 and 755 ms with 60 ms equal-power joins; retch from 930 ms and plop at 1110; 1.48 s at the cat loudness target with the usual high-pass and fades: Task 1 (maths), Task 2 (the two recipe parts), Task 3 (the recipe, "beats land on the animation's", the report line, the byte test).
- The build reproduces `B.wav`: Task 3 step 9 and `TestOnTheRealClips` (byte for byte with `B.wav`, and the pinned SHA-256 where `B.wav` is gone), Task 5 step 6.
- Rebuilding gives byte-identical WAVs, and existing builds do not move: the existing determinism tests, and Task 5 step 6 (168 files).
- "All 29 files exist", "the 15 picks and the 14 shared sounds": the counts come from `recipe.SLOTS` in the tests (Task 3 step 1, Task 4), and Your mix builds 29 (Task 3 tests, Task 5 step 5).
- The audition page row, 145 files, Play my mix 29: Task 3 (the row) and Task 4 (the rest).
- The rate exception and the priority exception: no sound fixture exists to hold them, so they are left to Stage 3 in "Notes for Stage 3" (the spec's wiring table is Stage 3's).
- Research record: Task 5. `build_pack.py` docstring: Task 3.

**Placeholder scan:** no "TBD", no "similar to Task N"; every code step shows its code. The three browser checks of Task 4 step 6 are described, not scripted, on purpose (a page is judged by looking).

**Type consistency:** `segments` and `synth_layers` are lists of dicts with the keys named in Task 2's Produces and used by `_segments`, `_synth_layers`, `_placed` and the tests; `PLACED` is `"placed"` everywhere (recipe, pipeline, `_shared.json`, tests); `Slot.touch` is read by `pipeline.build_slot` (Task 3) and by the page data (Task 4); `synth.RETCH_TO_PLOP_MS` (Task 1) is used by Task 3's beat test; `HAIRBALL_CLIP` is the one clip name.

**Review Focus coverage:** 1 → Task 2's three recipe tests; 2 → Task 2's window test; 3 → Task 2's `missing_sources` test and Task 3's skipping real-clip tests; 4 → Task 2's cap test; 5 → Task 3's "shared sound cannot be listed" and Task 4's browser step.

## Dry run (when this plan was drafted)

Every task was replayed, red then green, in a clean clone of `479c41a` (a script applied each edit block of this file and ran each `Run:` line, comparing PASS or FAIL with its `Expected:`; no mismatch). Tests: 147 before, 154 after Task 1, 164 after Task 2, 172 after Task 3, 174 after Tasks 4 and 5. `--check-recipes`: `5 sets x 29 slots`. `--all --report`: 145 of 145 on target. `--set mine --report`: 29 of 29. The rebuilt `hairball.wav` has SHA-256 `77f70082…dfec1ca`, byte for byte `B.wav` (so no tolerance is needed), and the 168 existing files (140 of the five sets, 28 of Your mix) are unchanged. The byte test was also shown to fail when `B.wav` is replaced by another file, and when a segment level moves by 0.001; it passes on the pinned SHA-256 alone when `NM_HAIRBALL_REFERENCE` names a file that does not exist, and the three clip-dependent tests skip with no candidates folder. The drafting session's browser tools refused `file:` URLs, so Task 4's step 6 was exercised by running the page's own script against a small fake DOM in Node instead: `145 of 145 files found.`, a `hairball` row with the chip "no layers" and five buttons of 1.48 s, `Playing my mix: greet (1 of 29)`, and with the five `hairball.wav` files absent `140 of 145 files found; run build_pack.py --all for the rest.`, the banner `5 of 145` and `Playing my mix (no sound yet for hairball): greet (1 of 28)`.
