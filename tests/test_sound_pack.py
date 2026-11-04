"""Tests for the final sound pack (sub-project C, stage 2), part 1: the checklist notes, the shipping folder and the
audition page's voices. Standard library only. Run: bash scripts/test-sound-build.sh
Builds on the helpers of test_sound_build.py (stage 1), which unittest finds in the same folder."""
import contextlib
import io
import json
import os
import re
import shutil
import tempfile
import unittest
from unittest import mock

from test_sound_build import ROOT, write_recipes  # noqa: F401  (also puts tools/sounds on sys.path)

import build_pack  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402

SETS_DIR = os.path.join(ROOT, "design", "sounds", "sets")


class TestChecklistNotes(unittest.TestCase):
    """The three notes the owner's checklist left for stage 2."""

    def test_the_loudness_targets_are_the_specs_for_cats_and_ticks(self):
        self.assertEqual(pipeline.TARGETS, {"cat": (-20.0, 1.5), "tick": (-28.0, 1.5)})


class TestShippingFolder(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm ship test ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.ship = os.path.join(self.tmp, "NotchBuddy", "Resources", "sounds")
        os.makedirs(self.ship)
        patch = mock.patch.object(build_pack, "SHIP_DIR", self.ship)
        patch.start()
        self.addCleanup(patch.stop)

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = build_pack.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_a_report_sits_beside_the_wavs_everywhere_but_in_the_shipping_folder(self):
        elsewhere = os.path.join(self.tmp, "build", "mine")
        self.assertEqual(build_pack.report_path(elsewhere), os.path.join(elsewhere, "report.md"))
        self.assertEqual(build_pack.report_path(self.ship),
                         os.path.join(build_pack.BUILD_DIR, "ship-report.md"))
        self.assertEqual(build_pack.report_path(os.path.join(self.ship, "..", "sounds")),
                         os.path.join(build_pack.BUILD_DIR, "ship-report.md"))        # however the path is spelt

    def test_ship_problems_names_what_is_missing_and_what_is_extra(self):
        slots = list(recipe.SLOTS)
        for slot in slots:
            open(os.path.join(self.ship, slot + ".wav"), "wb").close()
        open(os.path.join(self.ship, "README.md"), "w").close()
        open(os.path.join(self.ship, ".DS_Store"), "w").close()           # Finder litter is allowed, git ignores it
        self.assertEqual(build_pack.ship_problems(self.ship), [])
        open(os.path.join(self.ship, "report.md"), "w").close()
        os.remove(os.path.join(self.ship, "gulp.wav"))
        self.assertEqual(build_pack.ship_problems(self.ship), ["missing gulp.wav", "unexpected report.md"])

    def test_a_build_from_previews_may_not_write_into_the_shipping_folder(self):
        recipes = os.path.join(self.tmp, "recipes")
        write_recipes(recipes, lambda s: "synth:blip")
        cands = os.path.join(self.tmp, "cands")
        os.makedirs(cands)
        for argv in (["--set", "studio", "--out", self.ship],
                     ["--set", "studio", "--out", os.path.join(self.ship, "studio")],
                     ["--all", "--out", self.ship]):
            code, _, err = self.run_main(*argv, "--recipes", recipes, "--candidates", cands)
            self.assertEqual(code, 2, argv)
            self.assertIn("Freesound originals", err)
        self.assertEqual(os.listdir(self.ship), [])        # nothing written, not even a folder


class TestShippedPackOnDisk(unittest.TestCase):
    def test_the_shipping_folder_is_empty_or_exactly_one_wav_per_slot(self):
        ship = build_pack.SHIP_DIR
        names = os.listdir(ship)
        if any(n.endswith(".wav") for n in names):
            self.assertEqual(build_pack.ship_problems(ship), [])
        else:
            self.assertEqual([n for n in names if n not in build_pack.SHIP_KEEPS], [])


def uploader(source):
    """Who recorded a clip, from the name the candidates folder gives it (stage 1 naming)."""
    name = os.path.basename(source)
    if name.startswith("bsb-"):
        return "BigSoundBank"
    found = re.match(r"fs-\d+-(.+)\.[a-z0-9]+$", name)
    return found.group(1) if found else None


class TestAuditionVoice(unittest.TestCase):
    """The page's one-line voice of each set must say what the recipe really uses."""

    def setUp(self):
        with open(os.path.join(ROOT, "design", "sounds", "audition.html"), encoding="utf-8") as f:
            html = f.read()
        data = json.loads(re.search(r'<script type="application/json" id="data">(.*?)</script>', html, re.S).group(1))
        self.voice = {s["id"]: s["voice"] for s in data["sets"]}
        self.sets = recipe.load_recipes(SETS_DIR)

    def own_uploaders(self, s):
        return {uploader(e.source) for e in s.entries.values() if not e.shared and not e.source.startswith("synth:")}

    def test_every_uploader_a_set_uses_is_named_in_its_voice(self):
        for name, s in self.sets.items():
            if name == "bestof":            # Best of mixes a dozen voices on purpose; its line says so
                continue
            for who in self.own_uploaders(s):
                self.assertIsNotNone(who, name)
                self.assertIn(who.lower(), self.voice[name].lower(), "%s does not name %s" % (name, who))

    def test_the_pitch_a_voice_states_is_the_recipes(self):
        for name, s in self.sets.items():
            said = re.search(r"\b(up|down) (\d+(?:\.\d+)?) semitones?\b", self.voice[name])
            if s.pitch_st == 0.0:
                self.assertIsNone(said, "%s states a pitch shift its recipe does not have" % name)
                self.assertNotIn("semitone", self.voice[name])
            else:
                self.assertIsNotNone(said, "%s does not state its %+g semitones" % (name, s.pitch_st))
                self.assertEqual(said.group(1), "up" if s.pitch_st > 0 else "down", name)
                self.assertEqual(float(said.group(2)), abs(s.pitch_st), name)

    def test_every_set_has_a_voice_and_nothing_else_does(self):
        self.assertEqual(list(self.voice), list(self.sets))
        self.assertTrue(all(v.strip() for v in self.voice.values()))


if __name__ == "__main__":
    unittest.main()
