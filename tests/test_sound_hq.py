"""Tests for the HQ previews as the audio source (sub-project C, stage 2, task 6b). Standard library plus macOS
afconvert. This Mac has no MP3 encoder, so the stand-in "HQ previews" are files that begin with a real MPEG-1
layer III frame header (what the header check reads) and whose decoding is replaced by a fake that returns the
stand-in voices; the real afconvert decode of an MP3 is tested on a hand-built silent file."""
import contextlib
import copy
import io
import os
import shutil
import tempfile
import unittest
from collections import OrderedDict
from unittest import mock

from sound_pack_support import SR, blank_doc, blanked, mini_recipe, quantise, verify_all, voice
from test_sound_build import HAS_AFCONVERT, MIX_PICKS, DictLoader, read_bytes, write_default_round2, write_distinct_sets, write_mine

import audio_io  # noqa: E402
import build_pack  # noqa: E402
import originals  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402
import sources  # noqa: E402

FRAME_44K = bytes([0xFF, 0xFB, 0x90, 0x00])         # MPEG-1 layer III, 44.1 kHz, no padding, stereo
FRAME_48K = bytes([0xFF, 0xFB, 0x94, 0x00])


def stand_in_bytes(seed, header=FRAME_44K):
    """A file that starts like an MP3 and differs per seed (so its SHA-256 does)."""
    return header + bytes((seed * 7 + i) % 251 for i in range(300))


def silent_mp3(frames=40):
    """A real, decodable MP3: frames whose side info and main data are all zero decode to silence."""
    return (FRAME_44K + bytes(413)) * frames


class TestMpegHeader(unittest.TestCase):
    def test_reads_the_sample_rate_of_a_layer_3_frame(self):
        with tempfile.TemporaryDirectory() as tmp:
            for header, rate in ((FRAME_44K, 44100), (FRAME_48K, 48000)):
                path = os.path.join(tmp, "a.mp3")
                open(path, "wb").write(stand_in_bytes(1, header))
                self.assertEqual(originals.mpeg_sample_rate(path), rate)

    def test_an_id3_tag_in_front_is_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "a.mp3")
            tag = b"ID3\x03\x00\x00" + bytes([0, 0, 0, 20]) + bytes(20)         # synchsafe size 20
            open(path, "wb").write(tag + stand_in_bytes(1, FRAME_48K))
            self.assertEqual(originals.mpeg_sample_rate(path), 48000)

    def test_anything_but_a_layer_3_frame_is_refused(self):
        bad = {"a wave file": b"RIFF\x24\x00\x00\x00WAVEfmt " + bytes(40),
               "layer II": bytes([0xFF, 0xFD, 0x90, 0x00]) + bytes(300),
               "layer I": bytes([0xFF, 0xFF, 0x90, 0x00]) + bytes(300),
               "a reserved sample rate": bytes([0xFF, 0xFB, 0x9C, 0x00]) + bytes(300),
               "a free bitrate": bytes([0xFF, 0xFB, 0x00, 0x00]) + bytes(300),
               "a bad bitrate": bytes([0xFF, 0xFB, 0xF0, 0x00]) + bytes(300),
               "a reserved version": bytes([0xFF, 0xEB, 0x90, 0x00]) + bytes(300),
               "too short": bytes([0xFF, 0xFB]),
               "empty": b""}
        with tempfile.TemporaryDirectory() as tmp:
            for what, data in bad.items():
                path = os.path.join(tmp, "a.mp3")
                open(path, "wb").write(data)
                with self.assertRaises(ValueError, msg=what):
                    originals.mpeg_sample_rate(path)


class TestSourcesHq(unittest.TestCase):
    A, B = "love/fs-1001-Alice.wav", "greet/fs-1002-Bob.wav"

    def setUp(self):
        self.rec = mini_recipe(("love", self.A), ("greet", self.B))
        self.doc = verify_all(blank_doc(self.rec))
        self.hq = {"file": "1001_55-hq.mp3", "bytes": 700, "sha256": "ab" * 32, "format": "MP3",
                   "sample_rate_hz": 44100, "seconds": 0.69}

    def test_audio_kind_names_what_a_clip_is_built_from(self):
        e = self.doc["sources"][self.A]
        self.assertIsNone(sources.audio_kind(e))
        e["hq_preview"] = self.hq
        self.assertEqual(sources.audio_kind(e), "hq-preview")
        e["original"] = {"file": "x.wav", "bytes": 5, "sha256": "cd" * 32}
        self.assertEqual(sources.audio_kind(e), "original")                      # an original wins
        del e["hq_preview"]                                                     # an entry without the key is null
        self.assertEqual(sources.audio_kind(e), "original")

    def test_an_entry_without_the_key_or_with_a_right_one_has_a_good_shape(self):
        del self.doc["sources"][self.A]["hq_preview"]
        self.assertEqual(sources.problems(self.doc), [])
        self.doc["sources"][self.A]["hq_preview"] = self.hq
        self.assertEqual(sources.problems(self.doc), [])

    def test_a_malformed_hq_preview_is_a_shape_error(self):
        wrong = {"a string": "x.mp3", "no file": dict(self.hq, file=""), "zero bytes": dict(self.hq, bytes=0),
                 "upper-case sha": dict(self.hq, sha256="AB" * 32), "short sha": dict(self.hq, sha256="ab"),
                 "not MP3": dict(self.hq, format="WAV"), "no rate": dict(self.hq, sample_rate_hz=0),
                 "rate as text": dict(self.hq, sample_rate_hz="44100"), "no seconds": dict(self.hq, seconds=None),
                 "negative seconds": dict(self.hq, seconds=-1.0), "bool bytes": dict(self.hq, bytes=True)}
        wrong["missing field"] = {k: v for k, v in self.hq.items() if k != "format"}
        for what, bad in wrong.items():
            doc = copy.deepcopy(self.doc)
            doc["sources"][self.A]["hq_preview"] = bad
            said = sources.problems(doc)
            self.assertEqual(len(said), 1, (what, said))
            self.assertIn("%s: hq_preview needs" % self.A, said[0])

    def test_find_hq_preview_takes_the_pinned_name_else_the_one_file_named_by_the_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            e = {"hq_preview": None}
            with self.assertRaises(sources.SourcesError) as ctx:
                sources.find_hq_preview(tmp, self.A, e)
            self.assertIn("1001_*-hq.mp3", str(ctx.exception))
            self.assertIn(tmp, str(ctx.exception))
            for name in ("1001_55-hq.mp3", ".1001_66-hq.mp3", "10019_1-hq.mp3", "1001_55-hq.mp3.part", "1001_77.mp3"):
                open(os.path.join(tmp, name), "w").close()
            self.assertEqual(os.path.basename(sources.find_hq_preview(tmp, self.A, e)), "1001_55-hq.mp3")
            open(os.path.join(tmp, "1001_88-hq.mp3"), "w").close()
            with self.assertRaises(sources.SourcesError) as ctx:
                sources.find_hq_preview(tmp, self.A, e)
            self.assertIn("more than one", str(ctx.exception))
            e = {"hq_preview": {"file": "1001_88-hq.mp3"}}                      # pinned: no guessing
            self.assertTrue(sources.find_hq_preview(tmp, self.A, e).endswith("1001_88-hq.mp3"))
            with self.assertRaises(sources.SourcesError):
                sources.find_hq_preview(tmp, self.A, {"hq_preview": {"file": "gone.mp3"}})

    def test_a_clip_with_an_hq_preview_counts_as_pinned_for_the_gate(self):
        self.assertEqual(len(sources.pin_problems(self.doc, self.rec)), 1)
        self.assertIn("2 originals are not pinned (file, size and SHA-256)", sources.pin_problems(self.doc, self.rec)[0])
        self.doc["sources"][self.A]["hq_preview"] = self.hq
        self.assertIn("1 originals are not pinned", sources.pin_problems(self.doc, self.rec)[0])
        self.doc["sources"][self.B]["hq_preview"] = dict(self.hq, file="1002_9-hq.mp3")
        self.assertEqual(sources.pin_problems(self.doc, self.rec), [])
        self.assertTrue(all("originals are not pinned" not in p for p in sources.gate(self.doc, self.rec)))

    def test_credits_say_which_clips_were_built_from_an_hq_preview(self):
        self.doc["sources"][self.A]["hq_preview"] = self.hq
        self.doc["sources"][self.B]["original"] = {"file": "b.wav", "bytes": 5, "sha256": "cd" * 32}
        text = sources.credits_text(self.doc, self.rec)
        self.assertIn("| Built from | SHA-256 of the audio used |", text)
        self.assertIn("Freesound HQ preview (MP3) of the CC0 original", text)
        rows = {l.split("|")[1].strip(): l for l in text.splitlines() if l.startswith("| love") or l.startswith("| greet")}
        self.assertIn("| Freesound HQ preview (MP3) of the CC0 original | `%s` |" % ("ab" * 32), rows["love"])
        self.assertIn("| original WAV | `%s` |" % ("cd" * 32), rows["greet"])
        self.assertNotIn("HQ preview", rows["greet"])
        self.assertIn("built from the Freesound HQ preview (MP3) of its CC0 original", text)


@unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
class TestHqPreviewCheck(unittest.TestCase):
    A = "love/fs-1001-Alice.wav"

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm hq check ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.rec = mini_recipe(("love", self.A))
        self.entry = blank_doc(self.rec)["sources"][self.A]
        self.path = os.path.join(self.tmp, "1001_5-hq.mp3")
        open(self.path, "wb").write(silent_mp3(40))                              # 40 frames = 1.0449 s at 44.1 kHz

    def stated(self, text):
        self.entry["stated"] = {"type": "Wave (.wav)", "duration": text, "size": "10.0 KB"}

    def test_a_real_mp3_is_decoded_and_its_rate_and_length_are_read(self):
        self.stated("0:01.000")
        bad, path, size, seconds, rate = originals.check_hq_preview(self.A, self.entry, self.tmp)
        self.assertEqual(bad, [])
        self.assertEqual((path, rate, size), (self.path, 44100, os.path.getsize(self.path)))
        self.assertAlmostEqual(seconds, 1.0449, places=2)

    def test_the_length_must_lie_between_the_pages_and_the_pages_plus_the_encoder_padding(self):
        for said, fine in (("0:01.040", True), ("0:00.900", True), ("0:00.800", False), ("0:01.100", False)):
            self.stated(said)
            bad = originals.check_hq_preview(self.A, self.entry, self.tmp)[0]
            self.assertEqual(bad == [], fine, (said, bad))
        self.assertIn("its page says 0:01.100", bad[0])

    def test_a_wrong_file_is_named_not_guessed_at(self):
        self.stated("0:01.000")
        wave_path = os.path.join(self.tmp, "1001_5-hq.mp3")
        open(wave_path, "wb").write(b"RIFF" + bytes(60))
        bad = originals.check_hq_preview(self.A, self.entry, self.tmp)[0]
        self.assertEqual(len(bad), 1)
        self.assertIn("1001_5-hq.mp3 is not an MP3 (layer III) file", bad[0])
        open(wave_path, "wb").write(FRAME_44K + b"junk")                         # a header but nothing afconvert can decode
        bad = originals.check_hq_preview(self.A, self.entry, self.tmp)[0]
        self.assertTrue(any("afconvert cannot read" in b for b in bad), bad)
        os.rename(wave_path, os.path.join(self.tmp, "1001_5-hq.mp3.part"))
        bad, path, *_ = originals.check_hq_preview(self.A, self.entry, self.tmp)
        self.assertIsNone(path)
        self.assertIn("no file named 1001_*-hq.mp3", bad[0])
        self.entry["hq_preview"] = {"file": "pinned.wav"}                        # a pinned name must be an .mp3 too
        open(os.path.join(self.tmp, "pinned.wav"), "wb").write(silent_mp3(40))
        self.assertIn("is not an .mp3 file", " | ".join(originals.check_hq_preview(self.A, self.entry, self.tmp)[0]))


@unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
class TestHqOriginals(unittest.TestCase):
    ALICE, BOB, CY = "greet/fs-1001-Alice.wav", "love/fs-1002-Bob.wav", "tick/fs-1003-Cy.wav"

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm hq test ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.hq_folder = os.path.join(self.tmp, "hq previews")
        self.folder = os.path.join(self.tmp, "originals folder")          # absent unless a test makes it
        os.makedirs(self.hq_folder)
        self.rec = mini_recipe(("greet", self.ALICE, {"start": 0.2, "end": 0.7}), ("wink", self.ALICE, {"start": 0.3, "end": 0.6}),
                               ("love", self.BOB), ("tick", self.CY), ("blip", "synth:blip"))
        takes = {self.ALICE: voice(2, 0.7, 0.2, 0.1), self.BOB: voice(3, 0.5, 0.1, 0.1), self.CY: voice(4, 0.2, 0.02, 0.02)}
        self.ints = {k: quantise(v)[0] for k, v in takes.items()}
        self.previews = {k: quantise(v)[1] for k, v in takes.items()}
        self.doc = blank_doc(self.rec)
        self.decoded = {}                                                  # file name -> what the fake decode gives
        real = audio_io.decode_clip

        def fake(path):
            name = os.path.basename(path)
            return list(self.decoded[name]) if name in self.decoded else real(path)
        patch = mock.patch.object(audio_io, "decode_clip", fake)
        patch.start()
        self.addCleanup(patch.stop)

    def install(self, lead_ms=0, tail_ms=0, only=None, seed=1):
        """An HQ preview stand-in per clip, `lead_ms` of silence later than the low-quality preview."""
        for n, (source, own) in enumerate(self.ints.items()):
            if only and source not in only:
                continue
            body = ([0] * (lead_ms * 48) + own if lead_ms >= 0 else own[-lead_ms * 48:]) + [0] * (tail_ms * 48)
            name = "%s_%d-hq.mp3" % (sources.freesound_id(source), 861714 + n)
            open(os.path.join(self.hq_folder, name), "wb").write(stand_in_bytes(seed + n))
            self.decoded[name] = [v / 32768.0 for v in body]
            self.doc["sources"][source]["stated"] = {"type": "Wave (.wav)", "duration": "0:%06.3f" % (len(body) / float(SR) - 0.04),
                                                     "size": "10.0 KB"}

    def build(self, rec, loader, name):
        out = os.path.join(self.tmp, name)
        pipeline.build_set(rec, loader, out)
        return {f: read_bytes(os.path.join(out, f)) for f in sorted(os.listdir(out))}

    def test_pin_writes_the_hq_preview_and_works_without_an_originals_folder(self):
        self.install()
        self.assertFalse(os.path.exists(self.folder))
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder, self.hq_folder), [])
        for source, e in self.doc["sources"].items():
            hq = e["hq_preview"]
            path = os.path.join(self.hq_folder, hq["file"])
            self.assertIsNone(e["original"])
            self.assertEqual((hq["bytes"], hq["sha256"], hq["format"]), (os.path.getsize(path), originals.sha256_file(path), "MP3"))
            self.assertEqual(hq["sample_rate_hz"], 44100)
            self.assertAlmostEqual(hq["seconds"], len(self.decoded[hq["file"]]) / float(SR), places=6)
            self.assertEqual(sources.audio_kind(e), "hq-preview")
        self.assertEqual(sources.problems(self.doc), [])                      # what it wrote has the shape it must

    def test_pin_never_overwrites_an_earlier_hq_pin(self):
        self.install()
        originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        before = copy.deepcopy(self.doc)
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder, self.hq_folder), [])        # twice: no change
        self.assertEqual(self.doc, before)
        name = self.doc["sources"][self.CY]["hq_preview"]["file"]
        open(os.path.join(self.hq_folder, name), "wb").write(stand_in_bytes(99))                   # same name, other file
        said = originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        self.assertEqual(len(said), 1)
        self.assertIn("differs from the file pinned earlier", said[0])
        self.assertEqual(self.doc["sources"][self.CY]["hq_preview"], before["sources"][self.CY]["hq_preview"])

    def looks_aligned(self, source):
        self.doc["sources"][source].update(offset_s=0.01, windows={"love": [{"start": 0.0, "end": 0.5, "r": 0.99, "ok": True}]})

    def test_a_new_hq_pin_forgets_the_old_offset_and_windows_so_align_must_run_again(self):
        self.install()
        self.looks_aligned(self.BOB)                                          # first pin of an entry that looks aligned
        originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        self.assertIsNone(self.doc["sources"][self.BOB]["offset_s"])
        self.assertEqual(self.doc["sources"][self.BOB]["windows"], {})
        self.looks_aligned(self.BOB)                                          # an aligned pin, then the user nulls it
        self.doc["sources"][self.BOB]["hq_preview"] = None
        self.install(seed=50, only=[self.BOB])
        originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        self.assertIsNone(self.doc["sources"][self.BOB]["offset_s"])
        said = "; ".join(sources.window_problems(self.doc, self.rec))
        self.assertIn("no measured offset", said)
        self.assertIn("not pinned and checked", said)

    def test_an_unchanged_pin_keeps_its_offset_and_windows(self):
        self.install()
        originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        self.looks_aligned(self.BOB)
        originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        self.assertEqual(self.doc["sources"][self.BOB]["offset_s"], 0.01)

    def test_a_new_wav_pin_forgets_the_old_offset_and_windows_too(self):
        self.install()
        os.makedirs(self.folder)
        from sound_pack_support import write_original
        alice = os.path.join(self.folder, "1001__someone__a.wav")
        write_original(alice, self.ints[self.ALICE])
        self.doc["sources"][self.ALICE]["stated"] = {"type": "Wave (.wav)", "duration": "0:%06.3f" % (len(self.ints[self.ALICE]) / float(SR)),
                                                     "size": "%.1f KB" % (os.path.getsize(alice) / 1024.0)}
        self.looks_aligned(self.ALICE)
        originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        self.assertIsNone(self.doc["sources"][self.ALICE]["offset_s"])
        self.assertEqual(self.doc["sources"][self.ALICE]["windows"], {})

    def test_pin_prefers_a_wav_original_when_both_exist(self):
        self.install()
        os.makedirs(self.folder)
        alice = os.path.join(self.folder, "1001__someone__a.wav")
        from sound_pack_support import write_original
        write_original(alice, self.ints[self.ALICE])
        self.doc["sources"][self.ALICE]["stated"] = {"type": "Wave (.wav)", "duration": "0:%06.3f" % (len(self.ints[self.ALICE]) / float(SR)),
                                                     "size": "%.1f KB" % (os.path.getsize(alice) / 1024.0)}
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder, self.hq_folder), [])
        a, b = self.doc["sources"][self.ALICE], self.doc["sources"][self.BOB]
        self.assertEqual((a["original"]["file"], a["hq_preview"]), ("1001__someone__a.wav", None))
        self.assertEqual(sources.audio_kind(a), "original")
        self.assertIsNone(b["original"])
        self.assertEqual(sources.audio_kind(b), "hq-preview")                 # the others fall back to the preview

    def test_a_missing_or_doubled_hq_preview_is_a_problem_not_a_crash(self):
        self.install(only=[self.ALICE])
        open(os.path.join(self.hq_folder, "1002_1-hq.mp3"), "wb").write(stand_in_bytes(5))
        open(os.path.join(self.hq_folder, "1002_2-hq.mp3"), "wb").write(stand_in_bytes(6))        # Bob has two
        said = originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        self.assertEqual(len(said), 2)
        self.assertTrue(any("more than one" in s and self.BOB in s for s in said), said)
        self.assertTrue(any("no file named 1003_*-hq.mp3" in s and self.CY in s for s in said), said)
        self.assertIsNotNone(self.doc["sources"][self.ALICE]["hq_preview"])        # the good one is still pinned
        self.assertIsNone(self.doc["sources"][self.BOB]["hq_preview"])

    def test_with_no_originals_folder_and_no_hq_folder_each_clip_is_a_problem(self):
        said = originals.pin(self.doc, self.rec, self.folder)
        self.assertEqual(len(said), 3)
        self.assertTrue(all("does not exist" in s for s in said), said)

    def test_the_loader_refuses_a_swapped_hq_preview_and_moves_a_good_one_into_preview_time(self):
        self.install(lead_ms=30)
        originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        for e in self.doc["sources"].values():
            e["offset_s"] = 0.03
        loader = originals.OriginalsLoader(self.folder, self.doc, self.hq_folder)
        self.assertEqual(loader.load(self.ALICE), self.previews[self.ALICE])
        open(os.path.join(self.hq_folder, self.doc["sources"][self.BOB]["hq_preview"]["file"]), "wb").write(stand_in_bytes(77))
        with self.assertRaises(pipeline.SourceError) as ctx:
            originals.OriginalsLoader(self.folder, self.doc, self.hq_folder).load(self.BOB)
        self.assertIn("is not the file pinned", str(ctx.exception))
        os.remove(os.path.join(self.hq_folder, self.doc["sources"][self.CY]["hq_preview"]["file"]))
        with self.assertRaises(pipeline.SourceError) as ctx:
            originals.OriginalsLoader(self.folder, self.doc, self.hq_folder).load(self.CY)
        self.assertIn("HQ preview", str(ctx.exception))
        with self.assertRaises(pipeline.SourceError):                       # no HQ folder at all
            originals.OriginalsLoader(self.folder, self.doc).load(self.ALICE)
        self.doc["sources"][self.ALICE]["hq_preview"] = None
        with self.assertRaises(pipeline.SourceError) as ctx:                # nothing pinned
            originals.OriginalsLoader(self.folder, self.doc, self.hq_folder).load(self.ALICE)
        self.assertIn("nothing pinned", str(ctx.exception))

    def test_align_and_build_from_hq_previews_match_the_preview_build(self):
        for lead, tail in ((0, 0), (30, 120), (-20, 0)):
            self.setUp()
            self.install(lead_ms=lead, tail_ms=tail)
            self.assertEqual(originals.pin(self.doc, self.rec, self.folder, self.hq_folder), [])
            rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews), self.hq_folder)
            self.assertEqual(len(rows), 4, (lead, tail))
            self.assertTrue(all(r.ok for r in rows), originals.render_rows(rows))
            for source in self.previews:
                self.assertAlmostEqual(self.doc["sources"][source]["offset_s"], lead / 1000.0, places=3)
            verify_all(self.doc)
            self.assertEqual(sources.gate(self.doc, self.rec), [])
            from_hq = self.build(originals.pinned_recipe(self.rec, self.doc),
                                 originals.OriginalsLoader(self.folder, self.doc, self.hq_folder), "from hq")
            from_previews = self.build(self.rec, DictLoader(self.previews), "from previews")
            self.assertEqual(from_hq, from_previews, (lead, tail))

    def test_a_different_take_as_hq_preview_fails_its_window(self):
        self.install()
        self.decoded["1002_%d-hq.mp3" % (861714 + 1)] = quantise(voice(5, 0.5, 0.1, 0.1))[1]
        originals.pin(self.doc, self.rec, self.folder, self.hq_folder)
        rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews), self.hq_folder)
        self.assertEqual([r.slot for r in rows if not r.ok], ["love"])


class TestCli(unittest.TestCase):
    def test_pin_and_align_take_an_hq_folder_and_only_refuse_when_there_is_no_folder_at_all(self):
        tmp = tempfile.mkdtemp(prefix="nm hq cli ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        out, err = io.StringIO(), io.StringIO()
        gone = os.path.join(tmp, "gone")
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = originals.main(["pin", "--originals", gone, "--hq-previews", gone])
        self.assertEqual(code, 2)
        self.assertIn("neither the originals folder", err.getvalue())

        sources_path = os.path.join(tmp, "sources.json")
        sources.save(sources_path, blanked(sources.load(originals.SOURCES_PATH)))     # not the live pins: they name hq files
        hq = os.path.join(tmp, "hq")
        os.makedirs(hq)
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = originals.main(["pin", "--sources", sources_path, "--originals", gone, "--hq-previews", hq])
        self.assertEqual(code, 1)                                              # an empty folder: every clip is a problem
        self.assertNotIn("does not exist yet", err.getvalue())
        self.assertIn("no file named", err.getvalue())
        self.assertIn("pinned 0 of", out.getvalue())


@unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
class TestShipBuildFromHq(unittest.TestCase):
    """build_pack.py --set mine --originals --hq-previews DIR on stand-in previews: the whole path, with the originals
    folder absent."""

    def test_your_mix_builds_from_hq_previews_alone_and_matches_the_preview_build(self):
        tmp = tempfile.mkdtemp(prefix="nm hq e2e ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        recipes, hq = os.path.join(tmp, "recipes"), os.path.join(tmp, "hq")
        os.makedirs(hq)
        write_distinct_sets(recipes)
        write_default_round2(recipes)
        write_mine(recipes, MIX_PICKS)
        sets = recipe.load_recipes(recipes)
        mine = recipe.load_mine(os.path.join(recipes, "mine.json"), sets, recipe.load_round2(os.path.join(recipes, "round2.json"), sets))
        clips, decoded, doc = {}, {}, OrderedDict(title="e2e", sources=OrderedDict())
        for n, source in enumerate(sources.file_sources(mine)):
            ints, floats = quantise(voice(10 + n, 0.25, 0.03, 0.02))
            name = "%d_%d-hq.mp3" % (50000 + n, 7)
            data = stand_in_bytes(n)
            open(os.path.join(hq, name), "wb").write(data)
            decoded[name] = [0.0] * 480 + floats                                 # 10 ms later than the low-quality preview
            clips[source] = floats
            doc["sources"][source] = OrderedDict(
                title=source, author="tester", page="https://example.org/" + source, licence=sources.CC0,
                licence_url=sources.CC0_URLS[0], checked_on="2026-10-06", checked_by="the test",
                stated={"type": "Wave (.wav)", "duration": "0:00.300", "size": "30 KB"}, original=None,
                hq_preview={"file": name, "bytes": len(data), "sha256": originals.sha256_file(os.path.join(hq, name)),
                            "format": "MP3", "sample_rate_hz": 44100, "seconds": 0.29},
                offset_s=None, windows=OrderedDict())
        real = audio_io.decode_clip
        with mock.patch.object(audio_io, "decode_clip", lambda p: list(decoded[os.path.basename(p)]) if os.path.basename(p) in decoded else real(p)):
            previews = DictLoader(clips)
            self.assertTrue(all(r.ok for r in originals.align_all(doc, mine, os.path.join(tmp, "no originals"), previews, hq)))
            sources_path = os.path.join(tmp, "sources.json")
            sources.save(sources_path, doc)
            expected = os.path.join(tmp, "from previews")
            pipeline.build_set(mine, previews, expected)
            out_dir = os.path.join(tmp, "out")
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                    mock.patch.object(build_pack, "BUILD_DIR", os.path.join(tmp, "build")):
                code = build_pack.main(["--set", "mine", "--originals", os.path.join(tmp, "no originals"), "--hq-previews", hq,
                                        "--sources", sources_path, "--recipes", recipes, "--out", out_dir])
            self.assertEqual(code, 0, err.getvalue())
            for slot in recipe.SLOTS:
                self.assertEqual(read_bytes(os.path.join(out_dir, slot + ".wav")), read_bytes(os.path.join(expected, slot + ".wav")), slot)
            # a missing HQ folder is named, and nothing is written
            out2, err2 = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out2), contextlib.redirect_stderr(err2):
                code = build_pack.main(["--set", "mine", "--originals", os.path.join(tmp, "no originals"), "--hq-previews",
                                        os.path.join(tmp, "nowhere"), "--sources", sources_path, "--recipes", recipes,
                                        "--out", os.path.join(tmp, "out2")])
            self.assertEqual(code, 2)
            self.assertIn("HQ previews folder", err2.getvalue())
            self.assertFalse(os.path.exists(os.path.join(tmp, "out2")))


if __name__ == "__main__":
    unittest.main()
