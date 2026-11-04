"""Tests for the sound-set build (sub-project C, stage 1): tools/sounds/.

Standard library only. Run: bash scripts/test-sound-build.sh
"""
import hashlib
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

    def test_a_vocal_without_the_touch_keeps_only_the_layers_asked_for(self):
        self.assertEqual(layers.add_layers(self.vocal, "upset", False, False, False, False), self.vocal)
        self.assertNotEqual(layers.add_layers(self.vocal, "upset", True, False, False, False), self.vocal)
        self.assertNotEqual(layers.add_layers(self.vocal, "upset"), self.vocal)               # the touch is on by default


import recipe  # noqa: E402

# The slots every set shares: the ten ticks, the three made-in-code or foley fill-ins and the hairball.
SHARED_SLOTS = ["yawn", "work", "gulp", "hairball", "approve", "peek", "open", "close", "hover", "blip",
                "tick", "send", "attach", "pop"]


def raw(slot, source=None, **extra):
    """A valid raw recipe entry for `slot`, with `extra` fields on top."""
    info = recipe.SLOTS[slot]
    entry = {"slot": slot, "source": "synth:blip" if source is None else source, "mood": info.mood,
             "signature": info.signature}
    entry.update(extra)
    return entry


def placed(slot="slap", **extra):
    """A raw placed entry: one segment of '<slot>/c.wav' and one made-in-code layer."""
    fields = {"segments": [{"source": "%s/c.wav" % slot, "start": 0.1, "end": 0.4, "at": 0.0, "level": 0.2}],
              "synth_layers": [{"name": "hairball_retch_plop", "seed": 7, "at": 0.3}]}
    fields.update(extra)
    return raw(slot, "placed", **fields)


def write_json(path, doc):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f)


def write_recipes(directory, source_for, pitch_for=lambda name: 0.0):
    """A complete recipe folder: _shared.json and every set. `source_for(slot)` picks each source,
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
        self.assertEqual((len(cats), len(ticks), len(recipe.SLOTS)), (19, 10, 29))
        moods = {}
        for s in cats:
            moods.setdefault(s.mood, set()).add(s.name)
        self.assertEqual(moods["happy"], {"greet", "love", "finish", "proud", "wink", "gulp"})
        self.assertEqual(moods["attention"], {"approval", "question", "think", "search"})
        self.assertEqual(moods["upset"], {"error", "annoyed", "rate", "dizzy", "hairball"})
        self.assertEqual(moods["calm"], {"slap", "yawn", "sleep", "work"})
        self.assertEqual({s.name for s in recipe.SLOTS.values() if s.signature},
                         {"greet", "finish", "approval", "question", "error", "love"})
        self.assertEqual([s.name for s in recipe.SLOTS.values() if s.dark], ["error"])
        self.assertEqual({s.name: s.max_len for s in recipe.SLOTS.values() if s.max_len != 1.5},
                         dict(sleep=3.0, **{t.name: 0.4 for t in ticks}))
        self.assertTrue(all(t.mood == "none" and not t.signature for t in ticks))
        self.assertEqual(list(recipe.SLOTS)[18], "hairball")                   # the last cat moment, then the ticks
        self.assertEqual([s.name for s in cats if not s.touch], ["hairball"])    # the one cat moment without the touch
        self.assertFalse(any(t.touch for t in ticks))

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
        self.assertIn("source", self.bad(source="SYNTH:blip"))

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

    def test_load_set_needs_every_slot_once(self):
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "synth:blip")
        shared = recipe._entries(recipe._read(os.path.join(d, "_shared.json")), "_shared", True)
        self.assertEqual(len(recipe.load_set(os.path.join(d, "studio.json"), shared).entries), len(recipe.SLOTS))
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
        write_json(os.path.join(d, "kitten.json"), dict(doc, set="steff"))
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_set(os.path.join(d, "kitten.json"), shared)
        self.assertIn("is named kitten.json", str(ctx.exception))

    def test_broken_json_is_a_recipe_error_not_a_traceback(self):
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "synth:blip")
        with open(os.path.join(d, "steff.json"), "w") as f:
            f.write("{ not json")
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_recipes(d)
        self.assertIn("not valid JSON", str(ctx.exception))
        write_json(os.path.join(d, "steff.json"), [1, 2])
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_recipes(d)
        self.assertIn("JSON object", str(ctx.exception))

    def test_load_recipes_returns_five_complete_sets_sharing_their_shared_entries(self):
        d = os.path.join(self.tmp, "r")
        write_recipes(d, lambda s: "synth:blip")
        sets = recipe.load_recipes(d)
        self.assertEqual(list(sets), ["studio", "steff", "kitten", "bestof", "tabby"])
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

    def test_build_set_writes_every_slot_and_a_second_run_is_byte_identical(self):
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
                self.assertEqual(len(built), len(recipe.SLOTS))
                self.assertEqual(sorted(os.listdir(folder)), sorted(slot + ".wav" for slot in recipe.SLOTS))
                out[(run, name)] = {f: read_bytes(os.path.join(folder, f)) for f in os.listdir(folder)}
        for name in ("studio", "kitten"):
            self.assertEqual(out[("one", name)], out[("two", name)], name)
        # shared slots are the same bytes in every set; the pitch shift changed the kitten's own slots
        for slot in SHARED_SLOTS:
            self.assertEqual(out[("one", "studio")][slot + ".wav"], out[("one", "kitten")][slot + ".wav"], slot)
        self.assertNotEqual(out[("one", "studio")]["love.wav"], out[("one", "kitten")]["love.wav"])


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

    def test_vocals_and_ticks_may_both_be_1_5_lu_off(self):
        self.assertEqual(report.check("greet", m(lufs=-21.4)), [])
        self.assertEqual(report.check("greet", m(lufs=-18.6)), [])
        self.assertTrue(report.check("greet", m(lufs=-21.6)))
        self.assertEqual(report.check("tick", m(lufs=-29.4, seconds=0.2)), [])
        self.assertEqual(report.check("tick", m(lufs=-26.6, seconds=0.2)), [])
        self.assertTrue(report.check("tick", m(lufs=-29.6, seconds=0.2)))
        self.assertTrue(report.check("tick", m(lufs=-26.4, seconds=0.2)))

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
        bad = report.Row("tick", "tick", -33.0, -28.0, -30.0, -3.0, 0.2, 0.0, ["loudness -33.0 LUFS is not -28.0 +-1.5"])
        results = {"studio": [ok, bad], "kitten": [ok]}
        text = report.render(results)
        self.assertIn("2 of 3 files meet their targets.", text)
        self.assertIn("## studio: 1 of 2 pass", text)
        self.assertIn("## kitten: 1 of 1 pass", text)
        self.assertIn("| tick | tick | -33.0 |", text)
        self.assertIn("FAIL: loudness -33.0 LUFS", text)
        self.assertEqual(report.failures(results), ["studio/tick: loudness -33.0 LUFS is not -28.0 +-1.5"])


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
        self.assertIn("recipes ok: 5 sets x %d slots" % len(recipe.SLOTS), out)
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
        git = ["git", "-C", main, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
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
        total = len(recipe.SLOTS)
        self.assertEqual(len([f for f in os.listdir(out) if f.endswith(".wav")]), total)
        self.assertIn("(%d of %d files meet their targets)" % (total - 1, total), stdout)
        self.assertIn("FAIL studio/tick", err)
        with open(os.path.join(out, "report.md"), encoding="utf-8") as f:
            self.assertIn("## studio: %d of %d pass" % (total - 1, total), f.read())

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
        with open(os.path.join(cands, "greet", "c.wav"), "wb") as f:
            f.write(b"not audio at all")
        code, _, err = self.run_main("--set", "studio", "--recipes", self.recipes, "--candidates", cands,
                                     "--out", os.path.join(self.tmp, "out"))
        self.assertEqual(code, 2)
        self.assertIn("greet", err)
        self.assertIn("c.wav", err)
        self.assertNotIn("Traceback", err)

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


SHARED_SLOTS_IN_ORDER = [s for s in recipe.SLOTS if s in SHARED_SLOTS]
SETS_DIR = os.path.join(ROOT, "design", "sounds", "sets")
CANDIDATES = build_pack.find_candidates()
HAIRBALL_CLIP = "hairball/fs-561726-har2h.mp3"
HAIRBALL_SHA256 = "77f70082aa72a6ce68a8137f69002960b29995f3e7da9882882db5e1dfdec1ca"     # B.wav, the owner's pick of 2026-10-05
# B.wav itself is git-ignored: $NM_HAIRBALL_REFERENCE, else next to the candidates folder (.claude/sounds/build/hairball/B.wav
# in the main checkout, which a worktree shares). Without it the SHA-256 above is the reference.
HAIRBALL_REFERENCE = os.environ.get("NM_HAIRBALL_REFERENCE") or (
    os.path.join(os.path.dirname(CANDIDATES), "build", "hairball", "B.wav") if CANDIDATES else "")
HAS_HAIRBALL_CLIP = bool(CANDIDATES) and os.path.isfile(os.path.join(CANDIDATES, *HAIRBALL_CLIP.split("/")))


def own_files(s):
    """The recorded clips a set picked itself (not the shared ticks and fill-ins)."""
    return [e.source for e in s.entries.values() if not e.shared and not e.source.startswith("synth:")]


class TestRealRecipes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sets = recipe.load_recipes(SETS_DIR)

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

    def test_tabby_is_foxboyprowers_old_cat_with_a_snore_and_a_trill_from_two_others(self):
        s = self.sets["tabby"]
        self.assertEqual(s.title, "Tabby")
        self.assertEqual(s.pitch_st, 0.0)
        own = [e for e in s.entries.values() if not e.shared]
        self.assertFalse([e.slot for e in own if e.source.startswith("synth:")])      # all recorded, search included
        borrowed = {e.slot: e.source for e in own if "-foxboyprower." not in e.source}
        self.assertEqual(borrowed, {"sleep": "sleep/fs-196255-lolamadeus.mp3", "search": "search/fs-200336-jsbarrett.mp3"})
        self.assertEqual(len(own) - len(borrowed), 13)
        for e in own:                       # every window was measured from the audio, never left to auto-trim
            self.assertIsNotNone(e.start, e.slot)
            self.assertIsNotNone(e.end, e.slot)

    def test_tabbys_error_question_rate_and_dizzy_get_the_same_shaping_as_the_other_sets(self):
        e = self.sets["tabby"].entries
        self.assertEqual(e["error"].effects, [{"type": "glide", "from_st": 0.0, "to_st": -4.0}])
        self.assertEqual(e["question"].effects, [{"type": "glide", "from_st": 0.0, "to_st": 3.0}])
        self.assertEqual(e["rate"].effects, [{"type": "thump"}])
        self.assertEqual(e["dizzy"].effects, [{"type": "wobble", "rate_hz": 5.0, "depth_st": 1.0}])
        self.assertEqual(e["think"].effects, [])

    def test_round_two_refuses_a_window_tabby_already_uses(self):
        tmp = tempfile.mkdtemp(prefix="nm tabby ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        path = os.path.join(tmp, "round2.json")
        t = self.sets["tabby"].entries["slap"]
        write_json(path, {"set": "round2", "entries": [dict(raw("slap", t.source, start=t.start, end=t.end), id="slap-1")]})
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_round2(path, self.sets)
        self.assertIn("tabby already uses this window", str(ctx.exception))

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
    def setUp(self):
        self.path = os.path.join(ROOT, "design", "sounds", "audition.html")
        with open(self.path, encoding="utf-8") as f:
            self.html = f.read()
        self.data = json.loads(re.search(r'<script type="application/json" id="data">(.*?)</script>',
                                         self.html, re.S).group(1))

    def test_the_slot_table_is_the_builds(self):
        page = [(s["slot"], s["kind"], s["mood"], s["signature"], s["dark"], s["touch"]) for s in self.data["slots"]]
        build = [(i.name, i.kind, i.mood, i.signature, i.dark, i.touch) for i in recipe.SLOTS.values()]
        self.assertEqual(page, build)
        self.assertTrue(all(s["when"] for s in self.data["slots"]))

    def test_the_five_sets_are_the_recipes(self):
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
        self.assertIn("if (current !== c) return;", self.html)
        self.assertIn("endRun(); setStatus(); playCell(c);", self.html)

    def test_it_tells_the_owner_how_to_build_when_files_are_missing(self):
        self.assertIn("python3 tools/sounds/build_pack.py --all --report", self.html)
        self.assertIn("Play the whole set", self.html)

from collections import OrderedDict  # noqa: E402

# The 15 moments that differ between the sets (spec, "Picking per moment"), in the spec's order.
PICKABLE_SPEC = ["greet", "love", "annoyed", "dizzy", "slap", "finish", "error", "approval", "question",
                 "proud", "wink", "sleep", "think", "search", "rate"]
SET_PITCH = {"studio": 0.0, "steff": 0.0, "kitten": 1.5, "bestof": -1.0, "tabby": 0.0}          # the spec's set shifts
CLIP_FREQ = {"studio": 600.0, "steff": 700.0, "kitten": 800.0, "bestof": 900.0, "tabby": 1100.0, "r2": 1000.0,
             "shared": 500.0}
# One pick per moment, from all five sets and from round two (the alternatives written below).
MIX_PICKS = {"greet": "kitten", "love": "bestof", "annoyed": "kitten", "dizzy": "tabby",
             "slap": "round2:slap-1", "finish": "steff", "error": "bestof", "approval": "studio",
             "question": "kitten", "proud": "steff", "wink": "bestof", "sleep": "kitten", "think": "studio",
             "search": "kitten", "rate": "round2:rate-2"}


def write_distinct_sets(directory):
    """Five complete recipe sets whose clips differ, so a picked file can only have come from its set:
    set S reads '<slot>/S.wav'. Kitten shifts greet by a further +1 itself and makes its search in code,
    so the carried pitch meets a recorded entry with its own pitch and a made-in-code one."""
    os.makedirs(directory, exist_ok=True)
    write_json(os.path.join(directory, "_shared.json"), {"set": "_shared", "entries": [
        raw(s, "synth:%s" % s if s in synth.GAPS else "%s/shared.wav" % s) for s in SHARED_SLOTS]})
    own = [s for s in recipe.SLOTS if s not in SHARED_SLOTS]
    for name in recipe.SET_NAMES:
        entries = []
        for slot in own:
            extra = {"pitch_st": 1.0} if (name, slot) == ("kitten", "greet") else {}
            source = "synth:search" if (name, slot) == ("kitten", "search") else "%s/%s.wav" % (slot, name)
            entries.append(raw(slot, source, **extra))
        write_json(os.path.join(directory, name + ".json"), {
            "set": name, "title": name, "pitch_st": SET_PITCH[name], "entries": entries})


_DISTINCT = []


def distinct_clips():
    """A DictLoader with a stand-in clip for every '<slot>/<tag>.wav' (tags: the five sets, r2 for
    round two, shared). One sine burst per tag, so a built file can be traced to the tag it came from.
    Built once and shared by the tests."""
    if not _DISTINCT:
        bursts = {tag: burst(freq, 0.25, lead=0.03, amp=0.2) for tag, freq in CLIP_FREQ.items()}
        _DISTINCT.append(DictLoader({"%s/%s.wav" % (slot, tag): clip
                                     for slot in recipe.SLOTS for tag, clip in bursts.items()}))
    return _DISTINCT[0]


def r2raw(slot, n, source=None, **extra):
    """A raw round-two entry: an ordinary entry plus its id '<slot>-<n>'."""
    item = raw(slot, "%s/r2.wav" % slot if source is None else source, **extra)
    item["id"] = "%s-%d" % (slot, n)
    return item


def write_round2(directory, *entries):
    write_json(os.path.join(directory, "round2.json"), {"set": "round2", "entries": list(entries)})


def write_default_round2(directory):
    """Three alternatives: slap-1, rate-2 and rate-3 (so rate-1 does not exist)."""
    write_round2(directory, r2raw("slap", 1, start=0.0, end=0.2, pitch_st=2.0),
                 r2raw("rate", 2, pitch_st=-1.0), r2raw("rate", 3, start=0.0, end=0.15))


def write_mine(directory, picks, **top):
    doc = {"title": "Your mix", "picks": picks}
    doc.update(top)
    write_json(os.path.join(directory, "mine.json"), doc)


class TestMix(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm mix ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.d = os.path.join(self.tmp, "sets")
        write_distinct_sets(self.d)
        write_default_round2(self.d)
        self.sets = recipe.load_recipes(self.d)
        self.round2 = recipe.load_round2(os.path.join(self.d, "round2.json"), self.sets)
        self.mine = os.path.join(self.d, "mine.json")

    def read(self):
        return recipe.read_mix(self.mine, self.sets, self.round2)

    def fail_text(self, picks=None):
        """The message of the RecipeError that reading mine.json raises (after writing `picks`)."""
        if picks is not None:
            write_mine(self.d, picks)
        with self.assertRaises(recipe.RecipeError) as ctx:
            self.read()
        return str(ctx.exception)

    def r2(self, *entries):
        write_round2(self.d, *entries)
        return recipe.load_round2(os.path.join(self.d, "round2.json"), self.sets)

    def r2_fails(self, *entries):
        with self.assertRaises(recipe.RecipeError) as ctx:
            self.r2(*entries)
        return str(ctx.exception)

    # --- what is pickable -------------------------------------------------------------------

    def test_the_pickable_moments_are_the_15_the_set_files_hold(self):
        self.assertEqual(recipe.pickable_moments(self.sets), PICKABLE_SPEC)
        real = recipe.load_recipes(os.path.join(ROOT, "design", "sounds", "sets"))
        self.assertEqual(recipe.pickable_moments(real), PICKABLE_SPEC)
        self.assertTrue(set(SHARED_SLOTS).isdisjoint(PICKABLE_SPEC))
        self.assertEqual(len(PICKABLE_SPEC) + len(SHARED_SLOTS), len(recipe.SLOTS))

    # --- the mix ----------------------------------------------------------------------------

    def test_a_mix_copies_each_picked_entry_and_carries_its_sets_pitch(self):
        write_mine(self.d, dict(MIX_PICKS))
        mine = recipe.load_mine(self.mine, self.sets, self.round2)
        self.assertEqual((mine.name, mine.title, mine.pitch_st), ("mine", "Your mix", 0.0))
        self.assertEqual(list(mine.entries), list(recipe.SLOTS))
        e = mine.entries
        self.assertEqual((e["greet"].pitch_st, e["greet"].source), (2.5, "greet/kitten.wav"))   # +1.0 own, +1.5 set
        self.assertEqual(e["annoyed"].pitch_st, 1.5)          # kitten
        self.assertEqual(e["love"].pitch_st, -1.0)            # bestof
        self.assertEqual(e["dizzy"].pitch_st, 0.0)            # studio
        self.assertEqual((e["search"].pitch_st, e["search"].source), (0.0, "synth:search"))  # made in code: no shift
        self.assertEqual((e["slap"].pitch_st, e["slap"].source), (2.0, "slap/r2.wav"))       # round two keeps its own
        self.assertEqual(e["rate"].pitch_st, -1.0)
        self.assertEqual(e["finish"], self.sets["steff"].entries["finish"])    # steff has no shift: the entry is the set's
        for slot in SHARED_SLOTS:                                              # shared sounds pass through untouched
            self.assertEqual(e[slot], self.sets["studio"].entries[slot])
            self.assertTrue(e[slot].shared)
        self.assertFalse(any(e[m].shared for m in PICKABLE_SPEC))

    def test_use_this_set_for_all_gives_each_real_set_back(self):
        real = recipe.load_recipes(os.path.join(ROOT, "design", "sounds", "sets"))
        for name, s in real.items():
            mix = recipe.Mix("Your mix", OrderedDict((m, name) for m in PICKABLE_SPEC))
            mine = recipe.mix_recipe(mix, real, OrderedDict())
            for slot, src in s.entries.items():
                recorded = not src.shared and not src.source.startswith("synth:")
                self.assertEqual(mine.entries[slot].pitch_st, src.pitch_st + (s.pitch_st if recorded else 0.0), (name, slot))
                self.assertEqual(mine.entries[slot]._replace(pitch_st=0.0), src._replace(pitch_st=0.0), (name, slot))

    def test_the_carried_pitch_must_stay_in_range(self):
        doc = recipe._read(os.path.join(self.d, "kitten.json"))
        doc["pitch_st"] = 11.0
        doc["entries"][0]["pitch_st"] = 5.0                  # greet
        write_json(os.path.join(self.d, "kitten.json"), doc)
        sets = recipe.load_recipes(self.d)
        write_mine(self.d, dict(MIX_PICKS))
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_mine(self.mine, sets, self.round2)
        self.assertIn("greet", str(ctx.exception))
        self.assertIn("-12..12", str(ctx.exception))

    def test_none_is_allowed_in_the_file_but_the_recipe_refuses_while_any_moment_is_none(self):
        write_mine(self.d, dict(MIX_PICKS, rate="none", search="none"))
        mix = self.read()
        self.assertEqual(recipe.none_moments(mix), ["search", "rate"])
        with self.assertRaises(recipe.MixPending) as ctx:
            recipe.load_mine(self.mine, self.sets, self.round2)
        self.assertEqual(ctx.exception.moments, ["search", "rate"])
        self.assertIn("search, rate", str(ctx.exception))
        self.assertIsInstance(ctx.exception, recipe.RecipeError)
        with self.assertRaises(recipe.MixPending):
            recipe.mix_recipe(mix, self.sets, self.round2)

    # --- the checks on mine.json ------------------------------------------------------------

    def test_every_moment_exactly_once(self):
        picks = dict(MIX_PICKS)
        del picks["wink"]
        self.assertIn("missing moment wink", self.fail_text(picks))
        with open(self.mine, "w", encoding="utf-8") as f:       # json.load would silently keep the last "greet"
            f.write('{"title": "Your mix", "picks": {"greet": "studio", "greet": "kitten"}}')
        self.assertIn("'greet' appears twice", self.fail_text())

    def test_a_typo_names_both_the_unknown_moment_and_the_missing_one(self):
        picks = dict(MIX_PICKS)
        picks["anoyed"] = picks.pop("annoyed")
        text = self.fail_text(picks)
        self.assertIn("unknown moment 'anoyed'", text)
        self.assertIn("missing moment annoyed", text)

    def test_a_shared_sound_cannot_be_listed(self):
        for slot in ("tick", "yawn", "gulp", "work", "approve", "hairball"):
            self.assertIn("%s is the same in every set" % slot, self.fail_text(dict(MIX_PICKS, **{slot: "studio"})))
        self.assertIn("unknown moment 'purr'", self.fail_text(dict(MIX_PICKS, purr="studio")))

    def test_unknown_picks_are_errors(self):
        for value, part in (("studo", "unknown pick 'studo'"), ("", "unknown pick ''"),
                            ("Studio", "unknown pick 'Studio'"), ("_shared", "unknown pick '_shared'"),
                            (7, "must be text"), (None, "must be text"),
                            ("round2:slap-9", "is not in round2.json"),
                            ("round2:rate-2", "an alternative for rate, not greet")):
            self.assertIn(part, self.fail_text(dict(MIX_PICKS, greet=value)), repr(value))

    def test_the_file_shape_is_checked(self):
        for doc in ([], {"title": "Your mix"}, {"title": "Your mix", "picks": []},
                    {"title": "Your mix", "picks": dict(MIX_PICKS), "note": "x"}):
            write_json(self.mine, doc)
            self.assertIn("must be", self.fail_text(), repr(doc))
        write_json(self.mine, {"title": " ", "picks": dict(MIX_PICKS)})
        self.assertIn("title must be text", self.fail_text())
        with open(self.mine, "w", encoding="utf-8") as f:
            f.write("{ not json")
        self.assertIn("not valid JSON", self.fail_text())

    def test_a_mine_json_without_a_title_is_called_your_mix(self):
        write_json(self.mine, {"picks": dict(MIX_PICKS)})
        self.assertEqual(self.read().title, "Your mix")

    # --- round two --------------------------------------------------------------------------

    def test_round_two_entries_are_ordinary_entries_with_ids(self):
        r = self.r2(r2raw("rate", 1), r2raw("rate", 3, pitch_st=2), r2raw("search", 1, "synth:clink"))
        self.assertEqual(list(r), ["rate-1", "rate-3", "search-1"])
        self.assertEqual((r["rate-3"].slot, r["rate-3"].pitch_st, r["rate-3"].shared), ("rate", 2.0, False))
        self.assertEqual(recipe.round2_recipe(r).entries, r)
        os.remove(os.path.join(self.d, "round2.json"))
        self.assertEqual(recipe.load_round2(os.path.join(self.d, "round2.json"), self.sets), OrderedDict())

    def test_round_two_ids_must_name_a_pickable_moment_and_n_from_1_to_3(self):
        for ident in ("rate-0", "rate-4", "rate", "Rate-1", "rate-01", "rate-1-1", "-1", ""):
            item = r2raw("rate", 1)
            item["id"] = ident
            self.assertIn("must be <moment>-<n>", self.r2_fails(item), ident)
        item = r2raw("rate", 1)
        del item["id"]
        self.assertIn("must be <moment>-<n>", self.r2_fails(item))
        for slot in ("yawn", "tick", "gulp"):                  # shared sounds are not pickable
            item = r2raw(slot, 1)
            self.assertIn("not one of the 15", self.r2_fails(item), slot)
        item = r2raw("rate", 1)
        item["id"] = "purr-1"
        self.assertIn("not one of the 15", self.r2_fails(item))

    def test_a_round_two_id_and_slot_must_agree_and_ids_are_unique(self):
        item = r2raw("rate", 1)
        item["slot"] = "greet"
        item["mood"], item["signature"] = "happy", True
        self.assertIn("slot must be 'rate'", self.r2_fails(item))
        self.assertIn("appears twice", self.r2_fails(r2raw("rate", 1), r2raw("rate", 1, start=0.0, end=0.1)))

    def test_the_existing_source_checks_apply_to_round_two(self):
        self.assertIn("excluded source", self.r2_fails(r2raw("rate", 1, "rate/fs-857748-qubodup.mp3")))
        self.assertIn("excluded source", self.r2_fails(r2raw("rate", 1, "rate/fs-732521-Lukey1028.mp3")))
        self.assertIn("not a Department64", self.r2_fails(r2raw("rate", 1, "rate/fs-211234-Department64.mp3")))
        self.assertIn("mood must be", self.r2_fails(dict(r2raw("rate", 1), mood="happy")))
        self.assertIn("unknown fields", self.r2_fails(dict(r2raw("rate", 1), volume=3)))
        self.assertIn("pitch_st", self.r2_fails(r2raw("rate", 1, pitch_st=40)))
        self.r2(r2raw("rate", 1, "rate/fs-64012-Department64.mp3"))        # a kitten## file is fine

    def test_round_two_files_get_the_loaders_strictness_too(self):
        path = os.path.join(self.d, "round2.json")
        write_json(path, [])                                     # C1's _read: a recipe file is a JSON object
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_round2(path, self.sets)
        self.assertIn("must be a JSON object", str(ctx.exception))
        write_json(path, {"set": "studio", "entries": []})       # a file that names another set
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_round2(path, self.sets)
        self.assertIn("set 'round2'", str(ctx.exception))
        self.assertIn("source 'SYNTH:blip' must be", self.r2_fails(r2raw("rate", 1, "SYNTH:blip")))   # odd-case synth:

    def test_a_pick_of_tabby_is_accepted_like_any_set(self):
        write_mine(self.d, dict(MIX_PICKS, greet="tabby", search="tabby"))
        self.assertEqual(self.read().picks["greet"], "tabby")
        mine = recipe.mix_recipe(self.read(), self.sets, self.round2)
        self.assertEqual(mine.entries["greet"].source, "greet/tabby.wav")
        self.assertIn("unknown pick 'tabbi'", self.fail_text(dict(MIX_PICKS, greet="tabbi")))

    def test_a_round_two_entry_may_not_reuse_a_sets_exact_window(self):
        for name in recipe.SET_NAMES:
            text = self.r2_fails(r2raw("rate", 1, "rate/%s.wav" % name))   # same clip, no window: the set's own
            self.assertIn("%s already uses this window" % name, text)
        self.assertIn("already uses", self.r2_fails(r2raw("search", 1, "synth:search")))   # kitten's made-in-code search
        self.r2(r2raw("rate", 1, "rate/studio.wav", start=0.1, end=0.2))   # same clip, another window
        self.r2(r2raw("rate", 1, "rate/studio.wav", start=0.0))            # a different window is enough
        self.r2(r2raw("greet", 1, "rate/studio.wav"))                      # the same clip for another moment is fine


class TestMixBuild(unittest.TestCase):
    """Your mix, built through the same pipeline, is the picked sources' own files, byte for byte."""

    def test_every_picked_file_is_byte_identical_to_its_sources_file(self):
        tmp = tempfile.mkdtemp(prefix="nm mix build ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        d = os.path.join(tmp, "sets")
        write_distinct_sets(d)
        write_default_round2(d)
        write_mine(d, dict(MIX_PICKS))
        sets = recipe.load_recipes(d)
        round2 = recipe.load_round2(os.path.join(d, "round2.json"), sets)
        mine = recipe.load_mine(os.path.join(d, "mine.json"), sets, round2)
        loader, cache = distinct_clips(), {}
        for name, s in sets.items():
            pipeline.build_set(s, loader, os.path.join(tmp, name), cache)
        pipeline.build_set(recipe.round2_recipe(round2), loader, os.path.join(tmp, "round2"), cache)
        pipeline.build_set(mine, loader, os.path.join(tmp, "mine"), {})       # its own cache: nothing is reused

        def read(*parts):
            return read_bytes(os.path.join(tmp, *parts))

        self.assertEqual(sorted(os.listdir(os.path.join(tmp, "mine"))), sorted(s + ".wav" for s in recipe.SLOTS))
        for moment, pick in MIX_PICKS.items():
            source = os.path.join("round2", pick[len(recipe.ROUND2_PREFIX):]) if pick.startswith(recipe.ROUND2_PREFIX) \
                else os.path.join(pick, moment)
            self.assertEqual(read("mine", moment + ".wav"), read(source + ".wav"), (moment, pick))
        for slot in SHARED_SLOTS:
            self.assertEqual(read("mine", slot + ".wav"), read("studio", slot + ".wav"), slot)
        # the comparison can tell the sets apart, and a mix that forgot the set's pitch would not match
        self.assertNotEqual(read("kitten", "greet.wav"), read("studio", "greet.wav"))
        self.assertNotEqual(read("mine", "greet.wav"), read("studio", "greet.wav"))
        forgot = pipeline.build_slot(sets["kitten"].entries["greet"], loader)       # kitten's entry, without the set's +1.5
        self.assertNotEqual(len(forgot.samples), len(pipeline.read_back(os.path.join(tmp, "kitten"), "greet")))


class TestReportFiles(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm report files ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.built = pipeline.build_slot(entry("rate"), DictLoader({"rate/c.wav": burst(700.0, 0.4, amp=0.2)}))

    def test_rows_are_named_by_file_and_checked_against_the_slots_targets(self):
        audio_io.write_wav16(os.path.join(self.tmp, "rate-2.wav"), self.built.samples)
        rows = report.measure_files([("rate-2", self.built)], self.tmp)
        self.assertEqual((rows[0].slot, rows[0].kind, rows[0].problems), ("rate-2", "cat", []))
        audio_io.write_wav16(os.path.join(self.tmp, "rate.wav"), self.built.samples)       # a set's files are named by slot
        self.assertEqual(report.measure_set([self.built], self.tmp), report.measure_files([("rate", self.built)], self.tmp))

    def test_a_round_two_file_that_misses_its_targets_is_named_by_its_id(self):
        audio_io.write_wav16(os.path.join(self.tmp, "rate-2.wav"), sine(500, 0.5, 0.01))   # about -43 LUFS
        rows = report.measure_files([("rate-2", self.built)], self.tmp)
        self.assertTrue(rows[0].problems)
        self.assertTrue(report.failures({"round2": rows})[0].startswith("round2/rate-2: loudness"))

    def test_the_waiting_note_names_the_moments_or_is_empty(self):
        self.assertEqual(report.render_waiting([]), "")
        self.assertIn("No round-two alternative for: rate, search", report.render_waiting(["rate", "search"]))


class TestMixCli(unittest.TestCase):
    """build_pack.py --set mine, --round2 and --check-recipes on stand-in clips: the decoder is replaced,
    so no afconvert and no candidate clips are needed."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm mix cli ")                 # a space in every path
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.recipes = os.path.join(self.tmp, "recipe folder")
        write_distinct_sets(self.recipes)
        self.cands = os.path.join(self.tmp, "my candidates")
        loader = distinct_clips()
        for source in loader.clips:       # empty placeholders: the build checks the files exist, the stand-in never reads them
            path = os.path.join(self.cands, *source.split("/"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w").close()
        patch = mock.patch.object(build_pack, "AfconvertLoader", lambda folder: loader)
        patch.start()
        self.addCleanup(patch.stop)

    def run_main(self, *argv, **kw):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = build_pack.main(list(argv) + ["--recipes", self.recipes, "--candidates", kw.get("cands", self.cands)])
        return code, out.getvalue(), err.getvalue()

    def folder(self, *names):
        return os.path.join(self.tmp, *names)

    def files(self, *names):
        return sorted(os.listdir(self.folder(*names)))

    def test_set_mine_refuses_while_any_moment_is_none_and_names_them(self):
        picks = dict.fromkeys(PICKABLE_SPEC, "studio")
        picks.update(rate="none", search="none")
        write_mine(self.recipes, picks)
        for extra in ([], ["--report"]):
            code, out, err = self.run_main("--set", "mine", "--out", self.folder("mine out"), *extra)
            self.assertEqual(code, 2)
            self.assertIn("search, rate", err)
            self.assertNotIn("built", out)
        self.assertFalse(os.path.exists(self.folder("mine out")))

    def test_set_mine_builds_the_picks_byte_identical_to_the_sets_files_and_reports(self):
        write_default_round2(self.recipes)
        picks = dict.fromkeys(PICKABLE_SPEC, "kitten")
        picks.update(slap="round2:slap-1", rate="round2:rate-2")
        write_mine(self.recipes, picks)
        self.assertEqual(self.run_main("--set", "kitten", "--out", self.folder("kitten"))[0], 0)
        self.assertEqual(self.run_main("--round2", "--out", self.folder("round2"))[0], 0)
        code, out, err = self.run_main("--set", "mine", "--out", self.folder("mine"), "--report")
        self.assertEqual(code, 0, err)
        total = len(recipe.SLOTS)
        self.assertIn("built mine: %d files" % total, out)
        self.assertIn("(%d of %d files meet their targets)" % (total, total), out)
        self.assertEqual(self.files("mine"), sorted([s + ".wav" for s in recipe.SLOTS] + ["report.md"]))
        for slot in recipe.SLOTS:
            pick = picks.get(slot, "")
            source = self.folder("round2", pick[len(recipe.ROUND2_PREFIX):] + ".wav") \
                if pick.startswith(recipe.ROUND2_PREFIX) else self.folder("kitten", slot + ".wav")
            self.assertEqual(read_bytes(self.folder("mine", slot + ".wav")), read_bytes(source), slot)
        with open(self.folder("mine", "report.md"), encoding="utf-8") as f:
            self.assertIn("## mine: %d of %d pass" % (total, total), f.read())

    def test_set_mine_without_a_mine_json_says_where_it_comes_from(self):
        code, _, err = self.run_main("--set", "mine", "--out", self.folder("never"))
        self.assertEqual(code, 2)
        self.assertIn("mine.json", err)
        self.assertIn("audition.html", err)
        self.assertFalse(os.path.exists(self.folder("never")))

    def test_all_builds_the_five_sets_only_and_never_mine(self):
        write_default_round2(self.recipes)
        write_mine(self.recipes, dict(MIX_PICKS))                # a complete mine.json and a round2.json are right there
        built = []

        def record(rec, loader, out, cache=None):               # stands in for the 145-file build: only who gets built
            built.append((rec.name, os.path.basename(out)))
            return []

        with mock.patch.object(build_pack.pipeline, "build_set", record):
            code, _, err = self.run_main("--all", "--out", self.folder("all"))
            self.assertEqual(code, 0, err)
            self.assertEqual(built, [(name, name) for name in recipe.SET_NAMES])
            write_json(os.path.join(self.recipes, "mine.json"), [1])     # a broken mine.json is not even read
            code, _, err = self.run_main("--all", "--out", self.folder("all"))
            self.assertEqual(code, 0, err)
            self.assertEqual(len(built), 2 * len(recipe.SET_NAMES))

    def test_a_broken_mine_json_stops_mine_and_the_check_but_not_the_five_sets(self):
        with open(os.path.join(self.recipes, "mine.json"), "w", encoding="utf-8") as f:
            f.write('{"title": "Your mix", "picks": {"greet": "studio", "greet": "kitten"}}')
        for argv in (["--set", "mine", "--out", self.folder("never")], ["--check-recipes"]):
            code, _, err = self.run_main(*argv)
            self.assertEqual(code, 2, argv)
            self.assertIn("recipe error", err)
            self.assertIn("appears twice", err)
        code, _, err = self.run_main("--set", "studio", "--out", self.folder("never"), cands=self.folder("nowhere"))
        self.assertIn("candidates folder not found", err)        # it got past the recipes
        self.assertNotIn("mine.json", err)
        code, _, err = self.run_main("--all", "--out", self.folder("never"), cands=self.folder("nowhere"))
        self.assertIn("candidates folder not found", err)        # --all does not read mine.json either
        self.assertNotIn("mine.json", err)
        self.assertFalse(os.path.exists(self.folder("never")))

    def test_round2_builds_the_alternatives_with_their_own_report_section(self):
        write_default_round2(self.recipes)
        code, out, err = self.run_main("--round2", "--out", self.folder("alts"), "--report")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.files("alts"), ["rate-2.wav", "rate-3.wav", "report.md", "slap-1.wav"])
        self.assertIn("built round2: 3 files", out)
        with open(self.folder("alts", "report.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertIn("## round2: 3 of 3 pass", text)
        self.assertIn("| rate-2 | cat |", text)

    def test_round2_removes_alternatives_an_earlier_round_left_behind(self):
        write_default_round2(self.recipes)
        self.run_main("--round2", "--out", self.folder("alts"))
        for other in ("greet.wav", "notes.txt", "rate-4.wav"):       # not alternatives the page would probe
            open(self.folder("alts", other), "w").close()
        write_round2(self.recipes, r2raw("rate", 2, pitch_st=-1.0))
        code, out, _ = self.run_main("--round2", "--out", self.folder("alts"))
        self.assertEqual(code, 0)
        self.assertEqual(self.files("alts"), ["greet.wav", "notes.txt", "rate-2.wav", "rate-4.wav"])
        self.assertIn("removed stale rate-3.wav", out)
        self.assertIn("removed stale slap-1.wav", out)

    def test_round2_says_which_none_moments_have_no_alternative(self):
        write_round2(self.recipes, r2raw("rate", 1))
        picks = dict.fromkeys(PICKABLE_SPEC, "studio")
        picks.update(rate="none", search="none")
        write_mine(self.recipes, picks)
        code, out, _ = self.run_main("--round2", "--out", self.folder("alts"), "--report")
        self.assertEqual(code, 0)
        self.assertIn("no round-two alternative for: search", out)
        self.assertNotIn("for: rate", out)
        with open(self.folder("alts", "report.md"), encoding="utf-8") as f:
            self.assertIn("No round-two alternative for: search", f.read())

    def test_round2_with_nothing_to_build_is_an_error(self):
        code, _, err = self.run_main("--round2", "--out", self.folder("alts"))
        self.assertEqual(code, 2)
        self.assertIn("round2.json", err)
        write_round2(self.recipes)
        code, _, err = self.run_main("--round2", "--out", self.folder("alts"))
        self.assertEqual(code, 2)
        self.assertFalse(os.path.exists(self.folder("alts")))

    def test_a_round_two_clip_that_cannot_be_decoded_stops_with_exit_2_and_no_traceback(self):
        write_default_round2(self.recipes)
        good = distinct_clips()
        bad = os.path.join(self.cands, "slap", "r2.wav")

        class Undecodable:
            clips = good.clips

            def load(self, source):
                if source == "slap/r2.wav":                      # what AfconvertLoader raises for a clip it cannot read
                    raise subprocess.CalledProcessError(1, ["afconvert", "-f", "WAVE", bad, "decoded.wav"])
                return good.load(source)

        with mock.patch.object(build_pack, "AfconvertLoader", lambda folder: Undecodable()):
            code, out, err = self.run_main("--round2", "--out", self.folder("alts"), "--report")
        self.assertEqual(code, 2)
        self.assertIn("round2:", err)
        self.assertIn("slap/r2.wav", err)
        self.assertNotIn("Traceback", err)
        self.assertNotIn("built round2", out)

    def test_check_recipes_validates_mine_json_and_round2_json_when_they_exist(self):
        code, out, _ = self.run_main("--check-recipes")
        self.assertEqual(code, 0)
        self.assertIn("recipes ok: 5 sets x %d slots" % len(recipe.SLOTS), out)
        self.assertNotIn("mine.json", out)
        self.assertNotIn("round2.json", out)
        write_default_round2(self.recipes)
        write_mine(self.recipes, dict(MIX_PICKS, search="none"))
        code, out, _ = self.run_main("--check-recipes")
        self.assertEqual(code, 0)
        self.assertIn("round2.json ok: 3 alternatives for rate, slap", out)
        self.assertIn("mine.json ok: 15 picks, 1 none (search)", out)
        os.remove(os.path.join(self.cands, "rate", "r2.wav"))
        code, _, err = self.run_main("--check-recipes")
        self.assertEqual(code, 2)
        self.assertIn("missing clip - round2: rate/r2.wav", err)
        write_mine(self.recipes, dict(MIX_PICKS, greet="studo"))
        code, _, err = self.run_main("--check-recipes")
        self.assertEqual(code, 2)
        self.assertIn("unknown pick 'studo'", err)


class TestAuditionPicker(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(ROOT, "design", "sounds", "audition.html"), encoding="utf-8") as f:
            self.html = f.read()
        self.data = json.loads(re.search(r'<script type="application/json" id="data">(.*?)</script>',
                                         self.html, re.S).group(1))

    def js(self, name):
        """The text of a `var NAME = "...";` line of the page."""
        return re.search(r'var %s = "([^"]*)"' % name, self.html).group(1)

    def test_the_pickable_moments_are_the_specs_fifteen_and_the_recipes(self):
        sets = recipe.load_recipes(os.path.join(ROOT, "design", "sounds", "sets"))
        self.assertEqual(self.data["pickable"], PICKABLE_SPEC)
        self.assertEqual(self.data["pickable"], recipe.pickable_moments(sets))

    def test_the_other_fourteen_rows_are_the_shared_sounds(self):
        rest = [s["slot"] for s in self.data["slots"] if s["slot"] not in self.data["pickable"]]
        self.assertEqual(len(rest), 14)
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

    def test_the_page_speaks_the_loaders_vocabulary(self):
        self.assertEqual(self.js("TITLE"), recipe.MIX_TITLE)
        self.assertEqual(self.js("NONE"), recipe.NONE)
        self.assertEqual(self.js("ROUND2_PREFIX"), recipe.ROUND2_PREFIX)
        self.assertEqual(int(re.search(r"var ALT_COUNT = (\d+);", self.html).group(1)), recipe.ROUND2_MAX)
        self.assertEqual([s["id"] for s in self.data["sets"]], list(recipe.SET_NAMES))

    def test_alternatives_are_probed_in_the_folder_build_pack_writes(self):
        sub = re.search(r'var ROUND2 = BASE \+ "([^"]+)"', self.html).group(1)
        self.assertEqual(os.path.normpath(os.path.join(build_pack.BUILD_DIR, sub)), build_pack.ROUND2_DIR)
        self.assertIn('ROUND2 + slot + "-" + n + ".wav"', self.html)

    def test_the_picker_controls_and_labels_are_there(self):
        for ident in ("counter", "play-mix", "lock", "unlock", "summary", "summary-note", "summary-body", "mine-json"):
            self.assertIn('id="%s"' % ident, self.html, ident)
        for text in ("None of these", "Use this set for all", "Play my mix", "Lock in", "Change picks", '" picked"'):
            self.assertIn(text, self.html, text)

    def test_picks_are_stored_only_inside_try_catch(self):
        lines = [line for line in self.html.splitlines() if "localStorage" in line]
        self.assertGreaterEqual(len(lines), 2)
        for line in lines:
            self.assertIn("try {", line)
            self.assertIn("catch", line)
        self.assertIn("notchmeow.audition.picks", self.html)

    def test_alt_cells_stay_on_a_row_that_holds_a_round_two_pick(self):
        # controller's ruling: a picked Alt stays visible and changeable, so a row asks for its Alt cells
        # while it is none and also while it holds a round2: pick
        self.assertIn("var wantsAlts = v === NONE || isAlt(v);", self.html)
        self.assertIn("var show = wantsAlts && alt.found;", self.html)

    def test_a_file_that_fails_to_load_is_asked_for_once_more_after_400_ms(self):
        # controller's ruling, kept: a simple server can drop a request on a cold load of 145 files
        self.assertIn("if (!c.retried) { c.retried = true; setTimeout(function () { c.audio.src = url; }, 400); return; }",
                      self.html)
