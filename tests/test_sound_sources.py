"""Tests for sources.json and the licence gate (sub-project C, stage 2, task 2). Standard library only."""
import copy
import os
import shutil
import tempfile
import unittest
from collections import OrderedDict

from sound_pack_support import (HAIRBALL_CLIP, SOURCES_JSON, blank_doc, blanked, hairball_like, mini_recipe, verify_all,
                               with_hairball, your_mix)
from test_sound_build import raw

import recipe  # noqa: E402
import sources  # noqa: E402


class TestSources(unittest.TestCase):
    def setUp(self):
        self.mix = your_mix()
        self.live = sources.load(SOURCES_JSON)
        self.seed = blanked(self.live)

    def test_sources_json_names_exactly_the_recorded_clips_of_your_mix(self):
        self.assertEqual(list(self.live["sources"]), list(sources.file_sources(self.mix)))
        self.assertIn("hairball", sources.file_sources(self.mix)["hairball/fs-561726-har2h.mp3"])      # Cat Coughing, har2h
        made_in_code = [s for s, e in self.mix.entries.items() if not sources.clip_uses(e)]
        self.assertEqual(made_in_code, ["yawn", "work", "blip", "attach"])               # nothing recorded in them

    def test_every_page_and_author_follows_the_source_name(self):
        for source, e in self.live["sources"].items():
            self.assertEqual(e["page"], "https://freesound.org/people/%s/sounds/%s/" % (e["author"], sources.freesound_id(source)))
            self.assertTrue(e["title"].strip())

    def test_a_blank_entry_claims_neither_a_licence_nor_a_download(self):
        for e in self.seed["sources"].values():
            self.assertFalse(sources.is_verified(e))
            self.assertIsNone(e["original"])
            self.assertIsNone(e["offset_s"])
            self.assertEqual(e["windows"], {})

    def test_the_pages_figures_parse(self):
        self.assertEqual(sources.parse_duration("1:00.103"), 60.103)
        self.assertEqual(sources.parse_duration("0:00.643"), 0.643)
        self.assertEqual(sources.parse_size("110.9 KB"), int(round(110.9 * 1024)))
        self.assertEqual(sources.parse_size("1.4 MB"), int(round(1.4 * 1024 * 1024)))
        for bad in ("", "soon", "12", "1.4 mb "):
            with self.assertRaises(sources.SourcesError):
                sources.parse_size(bad)
        for bad in ("", "soon", "0.643", "1:5"):
            with self.assertRaises(sources.SourcesError):
                sources.parse_duration(bad)
        for e in self.live["sources"].values():
            sources.parse_duration(e["stated"]["duration"])
            sources.parse_size(e["stated"]["size"])

    def test_a_verified_licence_needs_cc0_the_link_a_date_and_a_checker(self):
        good = dict(licence="CC0-1.0", licence_url="https://creativecommons.org/publicdomain/zero/1.0/",
                    checked_on="2026-10-06", checked_by="the re-check agent")
        self.assertTrue(sources.is_verified(good))
        for field, bad in (("licence", "CC-BY-4.0"), ("licence", "CC0"), ("licence_url", "https://example.com/cc0"),
                           ("checked_on", "yesterday"), ("checked_on", None), ("checked_by", " "), ("checked_by", None)):
            self.assertFalse(sources.is_verified(dict(good, **{field: bad})), (field, bad))

    def test_half_a_licence_entry_is_a_shape_error(self):
        doc = copy.deepcopy(self.seed)
        first = next(iter(doc["sources"].values()))
        first["licence"] = "CC0-1.0"                       # no link, date or checker
        self.assertTrue(any("licence entry needs" in p for p in sources.problems(doc)))
        verify_all(doc)
        self.assertEqual(sources.problems(doc), [])

    def test_shape_errors_name_the_clip(self):
        doc = copy.deepcopy(self.seed)
        doc["sources"]["love/fs-64017-Department64.mp3"]["page"] = "https://freesound.org/people/Department64/sounds/1/"
        doc["sources"]["annoyed/fs-64008-Department64.mp3"]["original"] = {"file": "x.wav", "bytes": 5, "sha256": "ABC"}
        doc["sources"]["dizzy/fs-64007-Department64.mp3"]["stated"]["size"] = "big"
        said = "; ".join(sources.problems(doc))
        self.assertIn("love/fs-64017-Department64.mp3: page must be", said)
        self.assertIn("annoyed/fs-64008-Department64.mp3: original needs", said)
        self.assertIn("dizzy/fs-64007-Department64.mp3: size 'big'", said)
        tmp = tempfile.mkdtemp(prefix="nm sources ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        path = os.path.join(tmp, "sources.json")
        sources.save(path, doc)
        with self.assertRaises(sources.SourcesError) as ctx:
            sources.load(path)
        self.assertIn("love/fs-64017-Department64.mp3: page must be", str(ctx.exception))

    def test_a_malformed_window_is_a_shape_error_not_a_crash(self):
        for bad in ("x", {"start": 0, "end": 1}, {"start": "0", "end": 1, "r": 0.9, "ok": True},
                    {"start": 0, "end": 1, "r": 0.9, "ok": 1}):
            doc = copy.deepcopy(self.seed)
            doc["sources"]["love/fs-64017-Department64.mp3"]["windows"] = {"love": [bad]}
            said = sources.problems(doc)
            self.assertEqual(len(said), 1, said)
            self.assertIn("love/fs-64017-Department64.mp3: each window needs", said[0])

    def test_an_excluded_clip_can_never_be_a_source(self):
        doc = copy.deepcopy(self.seed)
        doc["sources"]["tick/fs-857748-qubodup.mp3"] = copy.deepcopy(next(iter(doc["sources"].values())))
        self.assertTrue(any("excluded source" in p for p in sources.problems(doc)))

    def test_the_build_refuses_a_source_missing_from_sources_json(self):
        doc = verify_all(copy.deepcopy(self.seed))
        self.assertEqual(sources.licence_problems(doc, self.mix), [])
        del doc["sources"]["sleep/fs-260881-Trautwein.mp3"]
        said = sources.licence_problems(doc, self.mix)
        self.assertEqual(len(said), 1)
        self.assertIn("1 clips are not in sources.json: sleep/fs-260881-Trautwein.mp3", said[0])
        self.assertEqual(sources.gate(doc, self.mix)[0], said[0])

    def test_the_build_refuses_a_source_without_a_verified_cc0_entry(self):
        doc = verify_all(copy.deepcopy(self.seed))
        doc["sources"]["pop/fs-258269-jcallison.mp3"]["checked_on"] = None
        doc["sources"]["send/fs-402453-jimmyfisher.mp3"]["licence"] = "CC-BY-4.0"
        said = "; ".join(sources.licence_problems(doc, self.mix))
        self.assertIn("2 clips have no verified CC0 entry", said)
        self.assertIn("pop/fs-258269-jcallison.mp3", said)
        self.assertIn("send/fs-402453-jimmyfisher.mp3", said)

    def test_a_long_list_of_problems_is_shortened(self):
        said = sources.gate(self.seed, self.mix)
        self.assertTrue(all(len(line) < 400 for line in said), said)
        self.assertTrue(any("and %d more" % (len(self.seed["sources"]) - 4) in line for line in said))

    def test_find_original_takes_the_pinned_name_else_the_one_file_named_by_the_id(self):
        tmp = tempfile.mkdtemp(prefix="nm originals ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        source = "love/fs-64017-Department64.mp3"
        e = {"original": None}
        with self.assertRaises(sources.SourcesError) as ctx:
            sources.find_original(tmp, source, e)
        self.assertIn("64017__", str(ctx.exception))
        for name in ("64017__department64__kitten22.wav", "640170__other__x.wav", ".64017__hidden.wav"):
            open(os.path.join(tmp, name), "w").close()
        self.assertEqual(os.path.basename(sources.find_original(tmp, source, e)), "64017__department64__kitten22.wav")
        open(os.path.join(tmp, "64017__department64__kitten22 (1).wav"), "w").close()      # a browser's second copy
        with self.assertRaises(sources.SourcesError) as ctx:
            sources.find_original(tmp, source, e)
        self.assertIn("more than one", str(ctx.exception))
        e = {"original": {"file": "64017__department64__kitten22.wav"}}                       # pinned: no guessing
        self.assertTrue(sources.find_original(tmp, source, e).endswith("kitten22.wav"))
        e = {"original": {"file": "gone.wav"}}
        with self.assertRaises(sources.SourcesError):
            sources.find_original(tmp, source, e)

    def test_a_preview_mp3_saved_by_mistake_is_not_a_wave(self):
        e = {"stated": {"type": "Wave (.wav)"}}
        self.assertTrue(sources.type_matches(e, "/x/64017__a__b.wav"))
        self.assertTrue(sources.type_matches(e, "/x/64017__a__b.WAV"))
        self.assertFalse(sources.type_matches(e, "/x/64017_861714-lq.mp3"))
        self.assertTrue(sources.type_matches({"stated": {"type": "Ogg Vorbis (.ogg)"}}, "/x/258269__a__b.ogg"))
        self.assertFalse(sources.type_matches({"stated": {"type": "Ogg Vorbis (.ogg)"}}, "/x/258269__a__b.wav"))

    def test_the_download_list_gives_every_clip_its_page_and_what_the_page_says(self):
        text = sources.download_list_text(self.seed, self.mix, "/o/originals")
        n = len(self.seed["sources"])
        self.assertIn("%d clips." % n, text)
        self.assertIn("Needs your Freesound sign-in: download these yourself (%d)" % n, text)
        self.assertIn("Direct links, with your OK before anything is downloaded (0)", text)
        self.assertIn("None: Your mix uses no BigSoundBank clip.", text)
        self.assertEqual(text.count("- [ ] **"), n)
        for source, e in self.seed["sources"].items():
            self.assertIn(e["page"], text)
            self.assertIn("`%s__`" % sources.freesound_id(source), text)
        self.assertIn(" by Department64, for dizzy, slap", text)                      # one file, two slots
        self.assertIn("by har2h, for hairball", text)                                  # one file, three windows, one slot
        pop = self.seed["sources"]["pop/fs-258269-jcallison.mp3"]["stated"]
        self.assertIn("the page says: %s, %s, %s" % (pop["type"], pop["duration"], pop["size"]), text)

    def test_a_bigsoundbank_clip_would_go_in_the_direct_link_group_with_its_link(self):
        rec = mini_recipe(("greet", "greet/bsb-s1885.mp3"))
        doc = blank_doc(rec)
        e = doc["sources"]["greet/bsb-s1885.mp3"]
        e.update(author="BigSoundBank", page="https://bigsoundbank.com/growling-cat-1-s1885.html",
                 download={"url": "https://bigsoundbank.com/UPLOAD/wav/1885.wav", "file": "bsb-1885.wav"})
        self.assertEqual(sources.problems(doc), [])
        text = sources.download_list_text(doc, rec, "/o")
        self.assertIn("Needs your Freesound sign-in: download these yourself (0)", text)
        self.assertIn("Direct links, with your OK before anything is downloaded (1)", text)
        self.assertIn("direct link: https://bigsoundbank.com/UPLOAD/wav/1885.wav", text)
        self.assertIn("save it as `bsb-1885.wav`", text)

    def test_credits_list_every_recorded_slot_once_per_clip_and_name_the_made_in_code_ones(self):
        doc = verify_all(copy.deepcopy(self.seed))
        for i, e in enumerate(doc["sources"].values()):
            e["original"] = {"file": "x%d.wav" % i, "bytes": 10 + i, "sha256": ("%02x" % i) * 32}
        text = sources.credits_text(doc, self.mix)
        rows = [l for l in text.splitlines() if l.startswith("| ") and not l.startswith("| Slot") and not l.startswith("|---")]
        want = sum(len(OrderedDict.fromkeys(s for s, _a, _b in sources.clip_uses(e))) for e in self.mix.entries.values())
        self.assertEqual(len(rows), want)
        first = doc["sources"]["love/fs-64017-Department64.mp3"]
        self.assertIn("| greet | %s | Department64 | <https://freesound.org/people/Department64/sounds/64017/> "
                      "| CC0 1.0 | 2026-10-06 | original WAV | `" % first["title"] + "00" * 32 + "` |", text)
        self.assertIn("Made in code, with no source clip: yawn (yawn), work (work), blip (blip), attach (clink).", text)
        self.assertEqual(text, sources.credits_text(doc, self.mix))                  # same input, same text

    # --- an entry that takes several windows of one clip, and also has a made-in-code layer (the hairball)

    def test_clip_uses_lists_every_recorded_window_of_an_entry_in_order(self):
        plain = recipe.parse_entry(raw("love", "love/fs-1-A.wav", start=0.1, end=0.6), "t")
        self.assertEqual(sources.clip_uses(plain), [("love/fs-1-A.wav", 0.1, 0.6)])
        self.assertEqual(sources.clip_uses(recipe.parse_entry(raw("blip", "synth:blip"), "t")), [])
        self.assertEqual(sources.clip_uses(hairball_like()),
                         [(HAIRBALL_CLIP, 0.10, 0.30), (HAIRBALL_CLIP, 0.50, 0.70), (HAIRBALL_CLIP, 0.90, 1.10)])

    def test_a_placed_sounds_own_cut_is_not_a_clip_window_and_a_layers_only_sound_has_no_source(self):
        cut = hairball_like()
        self.assertEqual((cut.start, cut.end), (0.0, 1.48))                                # the timeline's cut ...
        self.assertNotIn((HAIRBALL_CLIP, 0.0, 1.48), sources.clip_uses(cut))               # ... is never read as a window
        layers_only = cut._replace(segments=[])
        self.assertEqual(sources.clip_uses(layers_only), [])

    def test_a_slot_with_three_windows_of_one_clip_is_one_source_and_one_slot(self):
        rec = with_hairball(mini_recipe(("love", "love/fs-1002-Bob.wav")))
        self.assertEqual(sources.file_sources(rec), OrderedDict([("love/fs-1002-Bob.wav", ["love"]), (HAIRBALL_CLIP, ["hairball"])]))
        self.assertEqual(sources.slot_windows(rec, "hairball", HAIRBALL_CLIP), [(0.10, 0.30), (0.50, 0.70), (0.90, 1.10)])
        text = sources.download_list_text(blank_doc(rec), rec, "/o")
        self.assertEqual(text.count("by Dana, for hairball"), 1)

    def test_every_window_of_such_a_slot_is_checked_and_named(self):
        rec = with_hairball(mini_recipe(("love", "love/fs-1002-Bob.wav")))
        doc = verify_all(blank_doc(rec))
        for e in doc["sources"].values():
            e["original"] = {"file": "x.wav", "bytes": 5, "sha256": "ab" * 32}
            e["offset_s"] = 0.0
        ok = lambda a, b: {"start": a, "end": b, "r": 0.99, "ok": True}
        bob = doc["sources"]["love/fs-1002-Bob.wav"]
        bob["windows"] = {"love": [ok(0.0, 0.5)]}
        dana = doc["sources"][HAIRBALL_CLIP]
        dana["windows"] = {"hairball": [ok(0.10, 0.30), ok(0.50, 0.70)]}                       # one window short
        self.assertEqual(sources.gate(doc, rec), ["3 windows are not pinned and checked: hairball 1 of 3, hairball 2 of 3, hairball 3 of 3"])
        dana["windows"]["hairball"] = [ok(0.10, 0.30), dict(ok(0.50, 0.70), ok=False, r=0.41), ok(0.90, 1.10)]
        self.assertEqual(sources.gate(doc, rec), ["1 windows do not hold the same sound as the preview: hairball 2 of 3 (r=0.41)"])
        dana["windows"]["hairball"] = [ok(0.10, 0.30), ok(0.50, 0.70), ok(0.95, 1.10)]           # a window moved since it was pinned
        self.assertEqual(sources.gate(doc, rec), ["1 windows changed in the recipe since they were pinned: hairball 3 of 3"])
        dana["windows"]["hairball"] = [ok(0.10, 0.30), ok(0.50, 0.70), ok(0.90, 1.10)]
        self.assertEqual(sources.gate(doc, rec), [])

    def test_credits_give_such_a_slot_one_row_and_say_the_made_in_code_part_is_partly_made_in_code(self):
        rec = with_hairball(mini_recipe(("love", "love/fs-1002-Bob.wav"), ("blip", "synth:blip")))
        doc = verify_all(blank_doc(rec))
        for i, e in enumerate(doc["sources"].values()):
            e["original"] = {"file": "x%d.wav" % i, "bytes": 5, "sha256": ("%02x" % (i + 1)) * 32}
        text = sources.credits_text(doc, rec)
        rows = [l.split("|")[1].strip() for l in text.splitlines() if l.startswith("| ") and not l.startswith("| Slot") and not l.startswith("|---")]
        self.assertEqual(rows, ["love", "hairball"])                                           # one row for the three windows
        self.assertIn("Made in code, with no source clip: blip (blip).", text)
        self.assertIn("Partly made in code, the recorded part credited above: hairball.", text)
        layers_only = with_hairball(mini_recipe(("blip", "synth:blip")), hairball_like()._replace(segments=[]))
        self.assertIn("Made in code, with no source clip: blip (blip), hairball (hairball_retch_plop).",
                      sources.credits_text(verify_all(blank_doc(layers_only)), layers_only))

if __name__ == "__main__":
    unittest.main()
