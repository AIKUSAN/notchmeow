"""Tests for the window rule: does an original still hold the sound the preview's window held? (sub-project C, stage 2,
task 3). Standard library only."""
import random
import unittest

from sound_pack_support import SR, voice

import align  # noqa: E402
import dsp  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402
from test_sound_build import DictLoader, entry  # noqa: E402


class TestSpans(unittest.TestCase):
    """The trims now also say where they cut, so a window can be pinned. They must cut exactly as before."""

    def test_every_span_is_the_slice_the_old_function_returned(self):
        rng = random.Random(3)
        for _ in range(12):
            x = [0.0] * rng.randrange(0, 3000) + voice(rng.randrange(1, 9), rng.uniform(0.05, 0.9)) + [0.0] * rng.randrange(0, 3000)
            a, b = dsp.trim_silence_span(x)
            self.assertEqual(dsp.trim_silence(x), x[a:b])
            for length in (900, 20000, 200000):
                i, j = dsp.loudest_window_span(x, length)
                self.assertEqual(dsp.loudest_window(x, length), x[i:j])
            for max_len in (0.05, 0.4, 1.5):
                a, b = dsp.auto_trim_span(x, max_len)
                self.assertEqual(dsp.auto_trim(x, max_len), x[a:b])
                self.assertLessEqual(b - a, int(max_len * SR))

    def test_a_silent_or_empty_clip_has_a_whole_clip_span_and_no_crash(self):
        self.assertEqual(dsp.trim_silence_span([0.0] * 500), (0, 500))
        self.assertEqual(dsp.trim_silence_span([]), (0, 0))
        self.assertEqual(dsp.auto_trim_span([], 1.5), (0, 0))

    def test_seconds_span_clamps_like_seconds_slice(self):
        self.assertEqual(dsp.seconds_span(1000, None, None), (0, 1000))
        self.assertEqual(dsp.seconds_span(1000, 0.0, 0.01), (0, 480))
        self.assertEqual(dsp.seconds_span(1000, 0.01, 5.0), (480, 1000))
        self.assertEqual(dsp.seconds_span(1000, 5.0, 6.0), (0, 0))               # past the end: empty
        self.assertEqual(dsp.seconds_slice(list(range(1000)), 0.01, 5.0), list(range(480, 1000)))

    def test_the_pipeline_cuts_where_source_span_says(self):
        """`source_span` is a second statement of how `pipeline._source` picks a window (the pinned windows come from
        it), so a test pins that the two agree, for a window, for an automatic trim and for one that a shift shortens."""
        clip = voice(2, 0.5, lead=0.3, tail=0.3)
        long_clip = voice(3, 2.5, lead=0.3, tail=0.3)
        explicit = entry("love", "love/c.wav", start=0.2, end=0.5)
        self.assertEqual(pipeline.source_span(explicit, clip, 0.0), (9600, 24000))
        for e, shift, source in ((entry("love", "love/c.wav"), 0.0, clip), (explicit, 0.0, clip),
                                 (entry("greet", "love/c.wav"), 7.0, long_clip), (entry("greet", "love/c.wav"), 0.0, long_clip)):
            a, b = pipeline.source_span(e, source, shift)
            got = pipeline._source(e, recipe.SLOTS[e.slot], DictLoader({"love/c.wav": source}), shift)
            self.assertEqual(got, list(source[a:b]), (e.slot, e.start, shift))
        a, b = pipeline.source_span(entry("greet", "love/c.wav"), long_clip, 12.0)             # +12 st: room for 3 s
        self.assertLessEqual(b - a, int(3.0 * SR))


class TestAlign(unittest.TestCase):
    def setUp(self):
        self.p = voice(2)                                   # the preview: 1.0 s, the sound from 0.15 s to 0.85 s
        self.a, self.b = int(0.2 * SR), int(0.8 * SR)       # the window a recipe took

    def offset_of(self, original):
        return align.measure_offset(self.p, original, self.a, self.b)

    def verdict_of(self, original):
        off, _ = self.offset_of(original)
        return align.window_verdict(self.p, align.shift_clip(original, off), self.a, self.b)

    def test_pearson_and_envelope(self):
        self.assertAlmostEqual(align.pearson([1, 2, 3, 4], [2, 4, 6, 8]), 1.0)
        self.assertAlmostEqual(align.pearson([1, 2, 3, 4], [8, 6, 4, 2]), -1.0)
        self.assertEqual(align.pearson([1, 1, 1], [1, 2, 3]), 0.0)               # a flat list correlates with nothing
        self.assertEqual(align.pearson([], []), 0.0)
        self.assertEqual(len(align.envelope([0.5] * 4800)), 100)
        self.assertAlmostEqual(align.envelope([0.5] * 96)[0], 0.5)

    def test_shift_clip_moves_the_original_into_preview_time(self):
        o = [1.0, 2.0, 3.0, 4.0]
        self.assertEqual(align.shift_clip(o, 2), [3.0, 4.0])
        self.assertEqual(align.shift_clip(o, -2), [0.0, 0.0, 1.0, 2.0, 3.0, 4.0])
        self.assertEqual(align.shift_clip(o, 0), o)

    def test_the_offset_is_found_whichever_way_the_original_is_shifted(self):
        for ms in (0, 37, -42, 95, -100):
            original = align.shift_clip(self.p, -ms * 48)               # the same sound, `ms` later in the original
            off, r = self.offset_of(original)
            self.assertLessEqual(abs(off - ms * 48), 6, ms)            # within a quarter millisecond
            self.assertGreater(r, 0.99, ms)

    def test_a_shifted_original_holds_the_same_sound_once_shifted_back(self):
        for ms in (0, 25, -30):
            v = self.verdict_of(align.shift_clip(self.p, -ms * 48))
            self.assertTrue(v.ok, (ms, v))
            self.assertGreater(v.r, 0.99)

    def test_a_quieter_noisier_duller_original_still_holds_the_same_sound(self):
        rng = random.Random(1)
        dull = dsp.lowpass([0.3 * v + rng.gauss(0, 0.002) for v in self.p], 7000.0)
        v = self.verdict_of(dull)
        self.assertTrue(v.ok, v)

    def test_another_take_of_the_cat_does_not(self):
        for seed in (3, 4, 5):
            v = self.verdict_of(voice(seed))
            self.assertFalse(v.ok, (seed, v))
            self.assertLess(v.r, 0.5)

    def test_an_original_that_ends_inside_the_window_does_not(self):
        v = self.verdict_of(self.p[:int(0.45 * SR)])                      # 0.35 s of the 0.6 s window is missing
        self.assertFalse(v.ok, v)

    def test_an_original_at_another_speed_does_not(self):
        faster = dsp.pitch_shift(self.p, 1.0)                              # 6 % faster: the window no longer lines up
        self.assertFalse(self.verdict_of(faster).ok)

    def test_hiss_in_the_original_does_not_fail_a_window_that_matches(self):
        rng = random.Random(2)
        hissy = [v + rng.gauss(0, 0.03) for v in self.p]                      # hiss at about -30 dBFS
        v = self.verdict_of(hissy)
        self.assertTrue(v.ok, v)
        self.assertGreater(v.r, 0.97)


if __name__ == "__main__":
    unittest.main()
