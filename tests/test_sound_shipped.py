"""Tests for the shipped pack (sub-project C, stage 2, task 8a). Standard library only."""
import os
import re
import unittest
import wave
from collections import OrderedDict

from sound_pack_support import ROOT, SOURCES_JSON, your_mix

import audio_io  # noqa: E402
import build_pack  # noqa: E402
import recipe  # noqa: E402
import sources  # noqa: E402


CREDITS = os.path.join(ROOT, "docs", "SOUND-CREDITS.md")


class TestShippedPack(unittest.TestCase):
    """The pack as committed: one file per slot, their format and loudness, and the paper trail that goes with them."""

    @classmethod
    def setUpClass(cls):
        cls.ship = build_pack.SHIP_DIR
        cls.mix = your_mix()
        cls.doc = sources.load(SOURCES_JSON)

    def test_every_file_is_48_khz_16_bit_mono(self):
        for slot in recipe.SLOTS:
            with wave.open(os.path.join(self.ship, slot + ".wav"), "rb") as w:
                self.assertEqual((w.getframerate(), w.getsampwidth(), w.getnchannels()), (48000, 2, 1), slot)

    def test_every_file_meets_its_loudness_peak_and_length_targets(self):
        import loudness
        import report
        failed = {}
        for slot in recipe.SLOTS:
            samples = audio_io.read_wav(os.path.join(self.ship, slot + ".wav"))[0]
            bad = report.check(slot, loudness.measure(samples))
            if bad:
                failed[slot] = bad
        self.assertEqual(failed, {})

    def test_every_source_is_verified_pinned_and_checked(self):
        self.assertEqual(sources.gate(self.doc, self.mix), [])

    def test_the_credits_file_and_sources_json_agree(self):
        with open(CREDITS, encoding="utf-8") as f:
            self.assertEqual(f.read(), sources.credits_text(self.doc, self.mix))

    def test_every_recorded_slot_is_credited_and_every_credited_slot_ships(self):
        with open(CREDITS, encoding="utf-8") as f:
            rows = [l.split("|")[1].strip() for l in f.read().splitlines()
                    if l.startswith("| ") and not l.startswith("| Slot")]
        recorded = [s for s, e in self.mix.entries.items() for _ in OrderedDict.fromkeys(src for src, _a, _b in sources.clip_uses(e))]
        self.assertEqual(rows, recorded)
        self.assertTrue(all(os.path.isfile(os.path.join(self.ship, s + ".wav")) for s in rows))

    def test_every_credits_row_says_it_was_built_from_an_hq_preview(self):
        with open(CREDITS, encoding="utf-8") as f:
            rows = [l for l in f.read().splitlines() if l.startswith("| ") and not l.startswith("| Slot")]
        self.assertTrue(rows)
        self.assertTrue(all("HQ preview" in r for r in rows), [r for r in rows if "HQ preview" not in r])

    def test_nothing_of_coucous_is_credited_or_sourced(self):
        for path in (CREDITS, SOURCES_JSON):
            with open(path, encoding="utf-8") as f:
                self.assertIsNone(re.search(r"coucou|mochi", f.read(), re.I), path)


class TestShippingFolderIsThePack(unittest.TestCase):
    def test_the_shipping_folder_is_exactly_one_wav_per_slot_and_its_readme(self):
        ship = build_pack.SHIP_DIR
        self.assertEqual(build_pack.ship_problems(ship), [])
        self.assertEqual(sorted(n for n in os.listdir(ship) if n not in build_pack.SHIP_KEEPS),
                         sorted(slot + ".wav" for slot in recipe.SLOTS))
        self.assertTrue(os.path.isfile(os.path.join(ship, "README.md")))


class TestLicenceFiles(unittest.TestCase):
    def test_licence_assets_carves_out_the_cc0_clips_and_keeps_the_mixes_reserved(self):
        with open(os.path.join(ROOT, "LICENSE-ASSETS.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertIn("## The CC0 source clips", text)
        self.assertIn("excluded from the \"all\nrights reserved\"", text)
        self.assertIn("docs/SOUND-CREDITS.md", text)
        self.assertIn("design/sounds/sources.json", text)
        self.assertIn("NotchMeow's own sounds in `NotchBuddy/Resources/sounds/`", text)
        self.assertIn("HQ preview", text)
        self.assertNotIn("- the sounds in `NotchBuddy/Resources/sounds/`;", text)       # the bare line, without the carve-out

    def test_claude_md_no_longer_says_the_sounds_folder_is_empty(self):
        with open(os.path.join(ROOT, "CLAUDE.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("empty until the sounds land", text)
        self.assertIn("docs/SOUND-CREDITS.md", text)
        self.assertIn("Coucou's are reserved and must never be added back", text)

    def test_windows_readme_no_longer_counts_the_sounds(self):
        with open(os.path.join(ROOT, "windows", "README.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("The 28 sounds", text)
        self.assertIn("The sounds are the macOS app's own files", text)

    def test_the_shipping_folders_readme_no_longer_says_it_is_empty(self):
        with open(os.path.join(build_pack.SHIP_DIR, "README.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("Empty on purpose", text)
        self.assertIn("docs/SOUND-CREDITS.md", text)
        self.assertIn("HQ previews", text)
        for slot in recipe.SLOTS:
            self.assertIn(slot, text.split("Slots:")[-1].split(), slot)               # the README lists every slot
        self.assertIn("Louis Raillé", text)            # the reminder that Coucou's sounds never come back


if __name__ == "__main__":
    unittest.main()
