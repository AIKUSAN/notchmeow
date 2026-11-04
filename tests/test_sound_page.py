"""Tests for the licence re-check: reading a clip's own Freesound page (sub-project C, stage 2, task 5). Standard library only."""
import contextlib
import io
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

from sound_pack_support import SOURCES_JSON, blanked

import originals  # noqa: E402
import sources  # noqa: E402


PAGE = """<html><head>
<title>Freesound - kitten22.wav by Department64</title>
<meta property="og:title" content="kitten22.wav by Department64" />
<meta property="og:audio:artist" content="Department64" />
<meta property="og:audio:title" content="kitten22.wav" />
</head><body>
<span class="bw-icon-zero"></span> <a title="Go to the full license text" href="%(url)s" target="_blank" class="bw-link--black">%(name)s</a>
<div class="row">
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Type</p>
<p class="no-margins">Wave (.wav)</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Duration</p>
<p class="no-margins">0:00.643</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">File size</p>
<p class="no-margins">110.9 KB</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Sample rate</p>
<p class="no-margins">44100.0 Hz</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Bit depth</p>
<p class="no-margins">16 bit</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Channels</p>
<p class="no-margins">Stereo</p>
</div>
</div>
</body></html>"""
CC0_PAGE = PAGE % {"url": "http://creativecommons.org/publicdomain/zero/1.0/", "name": "Creative Commons 0"}
BY_PAGE = PAGE % {"url": "https://creativecommons.org/licenses/by/4.0/", "name": "Attribution 4.0"}


class TestPageCheck(unittest.TestCase):
    """The licence re-check reads each clip's own page. The tool reads the page's HTML; it takes nobody's word for it."""
    SOURCE = "love/fs-64017-Department64.mp3"

    def setUp(self):
        self.doc = blanked(sources.load(SOURCES_JSON))
        self.entry = self.doc["sources"][self.SOURCE]

    def test_the_page_is_read_from_its_own_tags(self):
        page = sources.parse_page(CC0_PAGE)
        self.assertEqual({k: v for k, v in page.items() if k != "stated"},
                         {"title": "kitten22.wav", "author": "Department64", "licence_name": "Creative Commons 0",
                          "licence_url": "http://creativecommons.org/publicdomain/zero/1.0/"})
        self.assertEqual(list(page["stated"].items()),
                         [("type", "Wave (.wav)"), ("duration", "0:00.643"), ("size", "110.9 KB"),
                          ("sample_rate", "44100.0 Hz"), ("bit_depth", "16 bit"), ("channels", "Stereo")])
        self.assertEqual(sources.check_page(self.entry, page), [])
        self.assertEqual(sources.parse_page("<html>nothing here</html>"),
                         {"title": None, "author": None, "licence_name": None, "licence_url": None, "stated": {}})

    def test_a_no_break_space_before_the_unit_is_read_as_a_space(self):
        page = sources.parse_page(CC0_PAGE.replace("110.9 KB", "110.9 KB").replace("0:00.643", "0:00.643 "))
        self.assertEqual((page["stated"]["size"], page["stated"]["duration"]), ("110.9 KB", "0:00.643"))

    def test_the_sound_information_of_an_ogg_page_has_a_bitrate_and_no_bit_depth(self):
        ogg = CC0_PAGE.replace("Wave (.wav)", "Ogg Vorbis (.ogg)").replace(
            '<p class="text-grey no-margins">Bit depth</p>\n<p class="no-margins">16 bit</p>',
            '<p class="text-grey no-margins">Bitrate</p>\n<p class="no-margins">232 kbps</p>')
        stated = sources.parse_page(ogg)["stated"]
        self.assertEqual((stated["type"], stated["bitrate"]), ("Ogg Vorbis (.ogg)", "232 kbps"))
        self.assertNotIn("bit_depth", stated)

    def test_the_seeds_figures_are_the_ones_a_page_prints(self):
        for source, e in self.doc["sources"].items():
            self.assertRegex(e["stated"]["sample_rate"], r"^\d+(\.\d+)? k?Hz$", source)       # '44100.0 Hz' or '44.1 kHz', as the page has it

    def test_only_a_plain_cc0_page_by_the_right_maker_vouches_for_a_clip(self):
        said = sources.check_page(self.entry, sources.parse_page(BY_PAGE))
        self.assertEqual(len(said), 2)
        self.assertIn("not 'Creative Commons 0'", said[0])
        self.assertIn("not a CC0 link", said[1])
        other = sources.parse_page(CC0_PAGE.replace('content="Department64"', 'content="Somebody"'))
        self.assertIn("maker is 'Somebody'", sources.check_page(self.entry, other)[0])
        nothing = sources.check_page(self.entry, sources.parse_page("<html></html>"))
        self.assertEqual(len(nothing), 6)                    # maker, licence name, link, and the three figures
        no_figures = sources.check_page(self.entry, sources.parse_page(CC0_PAGE.replace("Duration", "Length")))
        self.assertEqual(no_figures, ["the page shows no duration in its Sound information"])

    def test_a_page_with_two_different_creative_commons_links_is_ambiguous(self):
        both = CC0_PAGE.replace("</body>", '<a href="https://creativecommons.org/licenses/by/4.0/">Attribution 4.0</a></body>')
        page = sources.parse_page(both)
        self.assertIsNone(page["licence_url"])
        self.assertTrue(sources.check_page(self.entry, page))
        twice = CC0_PAGE.replace("</body>", '<a href="http://creativecommons.org/publicdomain/zero/1.0/">CC0 again</a></body>')
        self.assertEqual(sources.check_page(self.entry, sources.parse_page(twice)), [])      # the same link twice is fine

    def test_recording_writes_the_licence_the_reader_the_day_and_the_pages_own_figures(self):
        self.entry["stated"] = dict(sources.parse_page(CC0_PAGE)["stated"])      # the test page's six figures, whatever the live seed prints
        self.assertEqual(sources.record_check(self.entry, sources.parse_page(CC0_PAGE), "a re-check agent", "2026-10-06"), [])
        self.assertTrue(sources.is_verified(self.entry))
        self.assertEqual((self.entry["checked_by"], self.entry["checked_on"]), ("a re-check agent", "2026-10-06"))
        longer = sources.parse_page(CC0_PAGE.replace("0:00.643", "0:00.700").replace("kitten22.wav by", "x by"))
        warnings = sources.record_check(self.entry, longer, "a re-check agent", "2026-10-07")
        self.assertEqual(warnings, ["duration was '0:00.643', the page says '0:00.700'"])
        self.assertEqual(self.entry["stated"]["duration"], "0:00.700")                   # the page's figure wins, and is reported

    def run_page(self, html, *argv):
        tmp = tempfile.mkdtemp(prefix="nm page ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        path = os.path.join(tmp, "sources.json")
        sources.save(path, self.doc)
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO(html)), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = originals.main(["page", *argv, "--sources", path])
        return code, out.getvalue(), err.getvalue(), sources.load(path)

    def test_the_command_records_a_cc0_page_and_only_that(self):
        code, out, err, saved = self.run_page(CC0_PAGE, self.SOURCE, "--by", "a re-check agent", "--date", "2026-10-06")
        self.assertEqual(code, 0, err)
        self.assertIn("recorded %s: Creative Commons 0 by Department64, read on 2026-10-06" % self.SOURCE, out)
        self.assertTrue(sources.is_verified(saved["sources"][self.SOURCE]))
        self.assertFalse(sources.is_verified(saved["sources"]["love/fs-436542-Mafon2.mp3"]))       # only the one clip
        code, _, err, saved = self.run_page(BY_PAGE, self.SOURCE, "--by", "a re-check agent")
        self.assertEqual(code, 1)
        self.assertIn("NOT RECORDED %s" % self.SOURCE, err)
        self.assertFalse(sources.is_verified(saved["sources"][self.SOURCE]))

    def test_the_command_wants_a_clip_of_your_mix_a_reader_and_a_real_date(self):
        self.assertEqual(self.run_page(CC0_PAGE, "love/fs-1-Nobody.mp3", "--by", "x")[0], 2)
        self.assertEqual(self.run_page(CC0_PAGE, self.SOURCE)[0], 2)
        self.assertEqual(self.run_page(CC0_PAGE, self.SOURCE, "--by", "x", "--date", "6 October")[0], 2)


if __name__ == "__main__":
    unittest.main()
