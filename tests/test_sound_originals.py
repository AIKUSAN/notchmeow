"""Tests for building Your mix from the Freesound originals (sub-project C, stage 2, task 4). Standard library plus
macOS afconvert, which the end-to-end tests skip without."""
import contextlib
import copy
import io
import os
import random
import shutil
import tempfile
import unittest
from collections import OrderedDict
from unittest import mock

from sound_pack_support import (HAIRBALL_CLIP, SOURCES_JSON, SR, blank_doc, blanked, hairball_like, mini_recipe, quantise,
                               verify_all, voice, write_original)
from test_sound_build import (HAS_AFCONVERT, MIX_PICKS, DictLoader, read_bytes, write_default_round2, write_distinct_sets,
                              write_mine)

import audio_io  # noqa: E402
import build_pack  # noqa: E402
import dsp  # noqa: E402
import originals  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402
import sources  # noqa: E402


@unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
class TestOriginals(unittest.TestCase):
    ALICE, BOB, CY = "greet/fs-1001-Alice.wav", "love/fs-1002-Bob.wav", "tick/fs-1003-Cy.wav"

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm originals test ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.folder = os.path.join(self.tmp, "originals folder")
        os.makedirs(self.folder)
        self.rec = mini_recipe(("greet", self.ALICE, {"start": 0.2, "end": 0.7}),
                               ("wink", self.ALICE, {"start": 0.3, "end": 0.6}),          # a second window of one clip
                               ("love", self.BOB),                                       # no window: trimmed automatically
                               ("tick", self.CY),
                               ("blip", "synth:blip"))
        takes = {self.ALICE: voice(2, 0.7, 0.2, 0.1), self.BOB: voice(3, 0.5, 0.1, 0.1), self.CY: voice(4, 0.2, 0.02, 0.02)}
        self.ints = {k: quantise(v)[0] for k, v in takes.items()}
        self.previews = {k: quantise(v)[1] for k, v in takes.items()}
        self.doc = blank_doc(self.rec)

    def install(self, lead_ms=0, tail_ms=0, only=None, ints=None, **wav):
        """Write every clip's original into the folder: `lead_ms` of silence in front (the original later than the
        preview; negative cuts the front), `tail_ms` after. Fills in what the pages say."""
        for source, own in (ints or self.ints).items():
            if only and source not in only:
                continue
            body = ([0] * (lead_ms * 48) + own if lead_ms >= 0 else own[-lead_ms * 48:]) + [0] * (tail_ms * 48)
            name = "%s__someone__%s.wav" % (sources.freesound_id(source), os.path.basename(source)[:-4])
            path = os.path.join(self.folder, name)
            write_original(path, body, **wav)
            seconds = audio_io.decode_clip(path)
            e = self.doc["sources"][source]
            e["stated"] = {"type": "Wave (.wav)", "duration": "0:%06.3f" % (len(seconds) / SR),
                           "size": "%.1f KB" % (os.path.getsize(path) / 1024.0)}

    def build(self, rec, loader, name):
        out = os.path.join(self.tmp, name)
        pipeline.build_set(rec, loader, out)
        return {f: read_bytes(os.path.join(out, f)) for f in sorted(os.listdir(out))}

    def test_a_right_original_passes_the_check_and_a_wrong_one_is_named(self):
        self.install()
        source = self.ALICE
        entry_ = self.doc["sources"][source]
        bad, path, size, seconds = originals.check_original(source, entry_, self.folder)
        self.assertEqual(bad, [])
        self.assertAlmostEqual(seconds, 1.0, places=3)
        wrong = dict(entry_, stated={"type": "Ogg Vorbis (.ogg)", "duration": "0:00.500", "size": "9.0 KB"})
        said = " | ".join(originals.check_original(source, wrong, self.folder)[0])
        self.assertIn("is not a Ogg Vorbis (.ogg) file", said)
        self.assertIn("its page says 9.0 KB", said)
        self.assertIn("its page says 0:00.500", said)
        with open(path, "wb") as f:
            f.write(b"this is not audio")
        bad = originals.check_original(source, dict(entry_, stated=dict(entry_["stated"], size="0.0 KB")), self.folder)[0]
        self.assertTrue(any("afconvert cannot read" in b for b in bad), bad)

    def test_a_missing_or_doubled_original_is_a_problem_not_a_crash(self):
        self.install(only=[self.ALICE])
        said = originals.pin(self.doc, self.rec, self.folder)
        self.assertEqual(len(said), 2)                            # Bob and Cy are not there
        self.assertTrue(all("no file named" in s for s in said), said)
        self.assertIsNotNone(self.doc["sources"][self.ALICE]["original"])       # the good one is still pinned
        self.assertIsNone(self.doc["sources"][self.BOB]["original"])

    def test_pin_writes_name_size_and_sha256_and_never_overwrites_a_pin(self):
        self.install()
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])
        for source, e in self.doc["sources"].items():
            path = os.path.join(self.folder, e["original"]["file"])
            self.assertEqual(e["original"]["bytes"], os.path.getsize(path))
            self.assertEqual(e["original"]["sha256"], originals.sha256_file(path))
        before = copy.deepcopy(self.doc)
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])           # pinning twice changes nothing
        self.assertEqual(self.doc, before)
        e = self.doc["sources"][self.CY]
        write_original(os.path.join(self.folder, e["original"]["file"]), self.ints[self.CY][:-480])    # a different file, same name
        e["stated"]["size"] = "%.1f KB" % (os.path.getsize(os.path.join(self.folder, e["original"]["file"])) / 1024.0)
        e["stated"]["duration"] = "0:00.230"
        said = originals.pin(self.doc, self.rec, self.folder)
        self.assertEqual(len(said), 1)
        self.assertIn("differs from the file pinned earlier", said[0])
        self.assertEqual(self.doc["sources"][self.CY]["original"], before["sources"][self.CY]["original"])

    def test_the_loader_refuses_a_file_that_is_not_the_pinned_one(self):
        self.install()
        originals.pin(self.doc, self.rec, self.folder)
        self.doc["sources"][self.ALICE]["offset_s"] = 0.0
        loader = originals.OriginalsLoader(self.folder, self.doc)
        self.assertEqual(len(loader.load(self.ALICE)), len(self.ints[self.ALICE]))
        write_original(os.path.join(self.folder, self.doc["sources"][self.BOB]["original"]["file"]), [1, 2, 3])
        self.doc["sources"][self.BOB]["offset_s"] = 0.0
        with self.assertRaises(pipeline.SourceError) as ctx:
            originals.OriginalsLoader(self.folder, self.doc).load(self.BOB)
        self.assertIn("is not the file pinned", str(ctx.exception))

    def test_the_loader_moves_each_original_into_preview_time(self):
        self.install(lead_ms=30)
        originals.pin(self.doc, self.rec, self.folder)
        self.doc["sources"][self.ALICE]["offset_s"] = 0.03
        moved = originals.OriginalsLoader(self.folder, self.doc).load(self.ALICE)
        self.assertEqual(moved, self.previews[self.ALICE])

    def test_align_finds_the_offset_pins_every_window_and_the_build_matches_the_preview_build(self):
        for lead, tail in ((0, 0), (30, 120), (-20, 0)):      # the same sound, later / with a longer tail / earlier
            self.setUp()
            self.install(lead_ms=lead, tail_ms=tail)
            self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])
            rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
            self.assertEqual(len(rows), 4, (lead, tail))                   # one per recorded slot
            self.assertTrue(all(r.ok for r in rows), originals.render_rows(rows))
            for source in (self.ALICE, self.BOB, self.CY):
                self.assertAlmostEqual(self.doc["sources"][source]["offset_s"], lead / 1000.0, places=3)
            windows = self.doc["sources"][self.ALICE]["windows"]
            self.assertEqual([(w["start"], w["end"]) for w in windows["greet"]], [(0.2, 0.7)])
            self.assertEqual([(w["start"], w["end"]) for w in windows["wink"]], [(0.3, 0.6)])
            auto = self.doc["sources"][self.BOB]["windows"]["love"][0]    # an automatic window, now written out
            self.assertTrue(0.0 <= auto["start"] < auto["end"] <= 0.7)
            verify_all(self.doc)
            self.assertEqual(sources.gate(self.doc, self.rec), [])
            from_originals = self.build(originals.pinned_recipe(self.rec, self.doc),
                                        originals.OriginalsLoader(self.folder, self.doc), "from originals")
            from_previews = self.build(self.rec, DictLoader(self.previews), "from previews")
            self.assertEqual(sorted(from_originals), ["blip.wav", "greet.wav", "love.wav", "tick.wav", "wink.wav"])
            self.assertEqual(from_originals, from_previews, (lead, tail))

    def test_pinning_keeps_the_previews_window_when_the_originals_noise_floor_would_move_it(self):
        rng = random.Random(5)
        hissy = {s: [max(-32768, min(32767, v + int(rng.gauss(0, 900)))) for v in ints] for s, ints in self.ints.items()}
        self.install(ints=hissy)                                       # the originals carry hiss at about -31 dBFS
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])
        rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
        self.assertTrue(all(r.ok for r in rows), originals.render_rows(rows))
        a, b = pipeline.source_span(self.rec.entries["love"], self.previews[self.BOB], 0.0)         # the preview's window
        pinned = self.doc["sources"][self.BOB]["windows"]["love"][0]
        self.assertEqual((pinned["start"], pinned["end"]), (round(a / float(SR), 6), round(b / float(SR), 6)))
        own = audio_io.decode_clip(os.path.join(self.folder, self.doc["sources"][self.BOB]["original"]["file"]))
        self.assertNotEqual(dsp.auto_trim_span(own, 1.5), (a, b))      # trimming the hissy original itself would cut elsewhere

    def test_another_take_in_the_original_fails_its_window_and_stops_the_build(self):
        self.install()
        other = os.path.join(self.folder, "1002__someone__fs-1002-Bob.wav")
        write_original(other, quantise(voice(5, 0.5, 0.1, 0.1))[0])        # Bob's file is a different take of the cat
        e = self.doc["sources"][self.BOB]
        e["stated"]["size"] = "%.1f KB" % (os.path.getsize(other) / 1024.0)
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])      # the page's figures cannot tell
        rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
        self.assertEqual([r.slot for r in rows if not r.ok], ["love"])
        self.assertFalse(self.doc["sources"][self.BOB]["windows"]["love"][0]["ok"])
        said = sources.gate(verify_all(self.doc), self.rec)
        self.assertEqual(len(said), 1)
        self.assertIn("1 windows do not hold the same sound as the preview: love (r=", said[0])

    def test_a_recipe_window_that_moved_after_pinning_is_refused(self):
        self.install()
        originals.pin(self.doc, self.rec, self.folder)
        originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
        verify_all(self.doc)
        self.assertEqual(sources.gate(self.doc, self.rec), [])
        moved = mini_recipe(("greet", self.ALICE, {"start": 0.25, "end": 0.7}), ("wink", self.ALICE, {"start": 0.3, "end": 0.6}),
                            ("love", self.BOB), ("tick", self.CY))
        self.assertEqual(sources.gate(self.doc, moved), ["1 windows changed in the recipe since they were pinned: greet"])

    def test_the_pinned_recipe_writes_automatic_windows_out_and_leaves_made_in_code_sounds_alone(self):
        self.install()
        originals.pin(self.doc, self.rec, self.folder)
        originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
        pinned = originals.pinned_recipe(self.rec, self.doc)
        self.assertEqual(list(pinned.entries), list(self.rec.entries))
        self.assertEqual(pinned.entries["blip"], self.rec.entries["blip"])
        for slot in ("greet", "wink", "love", "tick"):
            self.assertIsNotNone(pinned.entries[slot].start)
            self.assertIsNotNone(pinned.entries[slot].end)
            self.assertEqual(pinned.entries[slot].pitch_st, self.rec.entries[slot].pitch_st)
        self.assertIsNone(self.rec.entries["love"].start)                  # the original recipe is untouched

    def test_a_slot_that_takes_three_windows_of_one_clip_is_aligned_pinned_and_cut_window_by_window(self):
        # the hairball: a placed sound, three windows of one recorded clip plus a made-in-code layer
        gap = [0.0] * 14400
        coughs = [0.0] * 4800 + voice(6, 0.2, 0.05, 0.05) + gap + voice(7, 0.2, 0.05, 0.05) + gap + voice(8, 0.2, 0.05, 0.05) + [0.0] * 4800
        ints, floats = quantise(coughs)
        windows = ((0.08, 0.38), (0.68, 0.98), (1.28, 1.58))
        rec = recipe.SetRecipe("mine", "Your mix", 0.0, OrderedDict(hairball=hairball_like(windows=windows)))      # source "placed"
        doc = blank_doc(rec)
        path = os.path.join(self.folder, "1004__someone__cough.wav")
        write_original(path, [0] * 480 + ints)                                           # the original starts 10 ms later
        doc["sources"][HAIRBALL_CLIP]["stated"] = {"type": "Wave (.wav)", "duration": "0:%06.3f" % ((len(ints) + 480) / float(SR)),
                                                    "size": "%.1f KB" % (os.path.getsize(path) / 1024.0)}
        self.assertEqual(originals.pin(doc, rec, self.folder), [])
        rows = originals.align_all(doc, rec, self.folder, DictLoader({HAIRBALL_CLIP: floats}))
        self.assertEqual([r.slot for r in rows], ["hairball 1 of 3", "hairball 2 of 3", "hairball 3 of 3"])
        self.assertTrue(all(r.ok for r in rows), originals.render_rows(rows))
        clip = doc["sources"][HAIRBALL_CLIP]
        self.assertAlmostEqual(clip["offset_s"], 0.01, places=3)                         # one offset for the clip
        self.assertEqual([(w["start"], w["end"]) for w in clip["windows"]["hairball"]], list(windows))
        verify_all(doc)
        self.assertEqual(sources.gate(doc, rec), [])
        pinned = originals.pinned_recipe(rec, doc)
        self.assertEqual([(s["start"], s["end"]) for s in pinned.entries["hairball"].segments], list(windows))
        self.assertEqual([s["at"] for s in pinned.entries["hairball"].segments], [s["at"] for s in rec.entries["hairball"].segments])
        self.assertEqual(pinned.entries["hairball"].synth_layers, rec.entries["hairball"].synth_layers)   # the made-in-code layer is left alone
        self.assertEqual((pinned.entries["hairball"].source, pinned.entries["hairball"].end), ("placed", 1.48))
        clip["windows"]["hairball"][1]["start"] = 0.70                                   # what is pinned wins over the recipe's 0.68
        self.assertEqual(originals.pinned_recipe(rec, doc).entries["hairball"].segments[1]["start"], 0.70)
        clip["windows"]["hairball"][1]["start"] = 0.68
        self.assertEqual(originals.OriginalsLoader(self.folder, doc).load(HAIRBALL_CLIP), floats)    # moved back into preview time

    def test_originals_in_other_formats_decode_and_align(self):
        # the formats Freesound's pages state: 44.1 kHz stereo 16-bit, 96 kHz stereo 24-bit
        for rate, channels, width in ((44100, 2, 2), (96000, 2, 3)):
            self.setUp()
            body = {s: dsp.pitch_shift(f, 0.0) for s, f in self.previews.items()}
            for source, floats in body.items():
                step = rate / float(SR)
                ints = [int(round(32768 * floats[min(len(floats) - 1, int(i * SR / rate))])) for i in range(int(len(floats) * step))]
                path = os.path.join(self.folder, "%s__x__y.wav" % sources.freesound_id(source))
                write_original(path, [max(-32768, min(32767, v)) for v in ints], rate, channels, width)
                self.doc["sources"][source]["stated"] = {"type": "Wave (.wav)", "duration": "0:%06.3f" % (len(floats) / SR),
                                                         "size": "%.1f KB" % (os.path.getsize(path) / 1024.0)}
            self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [], (rate, channels, width))
            rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
            self.assertTrue(all(r.ok for r in rows), (rate, originals.render_rows(rows)))
            self.assertTrue(all(abs(r.offset_ms) < 1.0 for r in rows))
            self.assertTrue(all(r.r > 0.95 for r in rows))


class TestBuildFromOriginals(unittest.TestCase):
    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = build_pack.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_a_blank_sources_json_is_not_ready_and_the_build_says_what_is_missing_and_writes_nothing(self):
        tmp = tempfile.mkdtemp(prefix="nm originals cli ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        out, path = os.path.join(tmp, "out"), os.path.join(tmp, "sources.json")
        sources.save(path, blanked(sources.load(SOURCES_JSON)))
        code, stdout, err = self.run_main("--set", "mine", "--originals", tmp, "--sources", path, "--out", out)
        self.assertEqual(code, 2)
        self.assertIn("the originals are not ready", err)
        n = len(sources.load(path)["sources"])
        self.assertIn("%d clips have no verified CC0 entry" % n, err)
        self.assertIn("%d originals are not pinned" % n, err)
        self.assertFalse(os.path.exists(out))

    def test_a_source_missing_from_sources_json_stops_the_build(self):
        tmp = tempfile.mkdtemp(prefix="nm originals cli ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        doc = blanked(sources.load(SOURCES_JSON))
        del doc["sources"]["rate/fs-64012-Department64.mp3"]
        path = os.path.join(tmp, "sources.json")
        sources.save(path, doc)
        code, _, err = self.run_main("--set", "mine", "--originals", tmp, "--sources", path, "--out", os.path.join(tmp, "out"))
        self.assertEqual(code, 2)
        self.assertIn("1 clips are not in sources.json: rate/fs-64012-Department64.mp3", err)

    def test_originals_belong_to_your_mix_only(self):
        for argv in (["--set", "studio", "--originals"], ["--all", "--originals"]):
            code, _, err = self.run_main(*argv)
            self.assertEqual(code, 2, argv)
            self.assertIn("--originals builds Your mix only", err)

    def test_only_a_build_from_originals_may_write_the_shipping_folder(self):
        ship = os.path.join(build_pack.SHIP_DIR)
        mine = (recipe.MINE_NAME, None, ship)
        self.assertIsNone(build_pack.refuse_shipping_folder([mine], True))
        self.assertIn("Freesound originals", build_pack.refuse_shipping_folder([mine], False))
        self.assertIn("Freesound originals", build_pack.refuse_shipping_folder([("studio", None, ship)], True))
        self.assertIsNone(build_pack.refuse_shipping_folder([("studio", None, os.path.join(build_pack.BUILD_DIR, "studio"))], False))


@unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
class TestShipBuildEndToEnd(unittest.TestCase):
    """The whole path on stand-in clips: recipes, a verified and pinned sources.json, the originals folder, then
    `build_pack.py --set mine --originals --out <shipping folder> --report`."""

    def test_your_mix_ships_every_slots_wav_and_nothing_else_identical_to_the_preview_build(self):
        tmp = tempfile.mkdtemp(prefix="nm ship e2e ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        recipes, folder = os.path.join(tmp, "recipes"), os.path.join(tmp, "originals")
        ship = os.path.join(tmp, "NotchBuddy", "Resources", "sounds")
        os.makedirs(folder)
        os.makedirs(ship)
        open(os.path.join(ship, "README.md"), "w").close()
        write_distinct_sets(recipes)
        write_default_round2(recipes)
        write_mine(recipes, MIX_PICKS)
        sets = recipe.load_recipes(recipes)
        mine = recipe.load_mine(os.path.join(recipes, "mine.json"), sets, recipe.load_round2(os.path.join(recipes, "round2.json"), sets))
        clips = {}
        doc = OrderedDict(title="e2e", sources=OrderedDict())
        for n, source in enumerate(sources.file_sources(mine)):
            ints, floats = quantise(voice(10 + n, 0.25, 0.03, 0.02))
            name = "%s.wav" % source.replace("/", "_")
            path = os.path.join(folder, name)
            write_original(path, [0] * 480 + ints)                         # every original 10 ms later than its preview
            clips[source] = floats
            doc["sources"][source] = OrderedDict(
                title=source, author="tester", page="https://example.org/" + source, licence=sources.CC0,
                licence_url=sources.CC0_URLS[0], checked_on="2026-10-06", checked_by="the test",
                stated={"type": "Wave (.wav)", "duration": "0:00.300", "size": "30 KB"},
                original={"file": name, "bytes": os.path.getsize(path), "sha256": originals.sha256_file(path)},
                offset_s=None, windows=OrderedDict())
        previews = DictLoader(clips)
        self.assertTrue(all(r.ok for r in originals.align_all(doc, mine, folder, previews)))
        sources_path = os.path.join(tmp, "sources.json")
        sources.save(sources_path, doc)
        expected_dir = os.path.join(tmp, "from previews")
        pipeline.build_set(mine, previews, expected_dir)
        with mock.patch.object(build_pack, "SHIP_DIR", ship), mock.patch.object(build_pack, "BUILD_DIR", os.path.join(tmp, "build")):
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = build_pack.main(["--set", "mine", "--originals", folder, "--sources", sources_path,
                                        "--recipes", recipes, "--out", ship, "--report"])
            self.assertIn(code, (0, 1), err.getvalue())                    # a stand-in burst may miss a loudness target
            self.assertEqual(build_pack.ship_problems(ship), [])
            self.assertEqual(sorted(os.listdir(ship)), sorted(["README.md"] + [s + ".wav" for s in recipe.SLOTS]))
            self.assertTrue(os.path.isfile(os.path.join(tmp, "build", "ship-report.md")))
            for slot in recipe.SLOTS:
                self.assertEqual(read_bytes(os.path.join(ship, slot + ".wav")), read_bytes(os.path.join(expected_dir, slot + ".wav")), slot)


if __name__ == "__main__":
    unittest.main()
