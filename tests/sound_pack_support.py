"""Helpers the stage-2 sound tests share (sub-project C). Standard library only.

Importing test_sound_build puts tools/sounds on sys.path, so the build modules import by bare name here too."""
import copy
import math  # noqa: F401  (used by the helpers later tasks add)
import os
import random  # noqa: F401
import struct  # noqa: F401
import wave  # noqa: F401
from collections import OrderedDict, namedtuple

from test_sound_build import ROOT, entry  # noqa: F401

import dsp  # noqa: E402
import recipe  # noqa: E402
import sources  # noqa: E402

SR = dsp.SR
SETS_DIR = os.path.join(ROOT, "design", "sounds", "sets")
SOURCES_JSON = os.path.join(ROOT, "design", "sounds", "sources.json")


def your_mix():
    sets = recipe.load_recipes(SETS_DIR)
    return recipe.load_mine(os.path.join(SETS_DIR, "mine.json"), sets,
                            recipe.load_round2(os.path.join(SETS_DIR, "round2.json"), sets))


# A stand-in for the hairball's entry, in the shape plan c1c-hairball gives it: the source "placed", `segments` a list
# of dicts (a window of a recorded clip each, with where it is placed and its level and fades) and `synth_layers` a
# list of dicts. The tests of the tools use this, not c1c's own types, so they only depend on the fields `clip_uses`
# documents. `start` and `end` of the entry cut the finished timeline; they are not a clip window.
FakeEntry = namedtuple("FakeEntry", "slot source start end pitch_st segments synth_layers")
HAIRBALL_CLIP = "hairball/fs-1004-Dana.wav"


def hairball_like(slot="hairball", clip=HAIRBALL_CLIP, windows=((0.10, 0.30), (0.50, 0.70), (0.90, 1.10))):
    """An entry that takes several windows of one recorded clip and has a made-in-code layer too."""
    segments = [{"source": clip, "start": a, "end": b, "at": 0.01 + 0.32 * n, "level": 0.2, "fade_in_ms": 5.0, "fade_out_ms": 60.0}
                for n, (a, b) in enumerate(windows)]
    return FakeEntry(slot, "placed", 0.0, 1.48, 0.0, segments, [{"name": "hairball_retch_plop", "seed": 1205, "at": 0.93}])


def with_hairball(rec, entry_=None):
    """`rec` plus a hairball-like entry (a copy of the recipe: the original is not changed)."""
    entries = OrderedDict(rec.entries)
    entries["hairball"] = entry_ or hairball_like()
    return rec._replace(entries=entries)


def blanked(doc):
    """A copy of a sources.json document as the seed had it: every clip named, nothing checked, pinned or measured.
    The tests of the tools use this, so they keep passing after the real file is filled in."""
    out = copy.deepcopy(doc)
    for e in out["sources"].values():
        e.update(licence=None, licence_url=None, checked_on=None, checked_by=None, original=None, hq_preview=None,
                 offset_s=None, windows=OrderedDict())
    return out


def mini_recipe(*items):
    """A SetRecipe named mine from (slot, source) or (slot, source, {fields}) tuples: enough to test the originals."""
    entries = OrderedDict()
    for slot, source, *fields in items:
        entries[slot] = entry(slot, source, **(fields[0] if fields else {}))
    return recipe.SetRecipe("mine", "Your mix", 0.0, entries)


def blank_doc(rec):
    """A sources.json document for the recorded clips of `rec`, as the seed has it: nothing checked yet."""
    doc = OrderedDict(title="test", sources=OrderedDict())
    for source in sources.file_sources(rec):
        doc["sources"][source] = OrderedDict(
            title="Clip %s" % sources.freesound_id(source), author=sources.freesound_author(source),
            page=sources.page_url(source), stated={"type": "Wave (.wav)", "duration": "0:00.900", "size": "84.4 KB"},
            licence=None, licence_url=None, checked_on=None, checked_by=None, original=None, hq_preview=None,
            offset_s=None, windows=OrderedDict())
    return doc


def verify_all(doc, **fields):
    for e in doc["sources"].values():
        e.update(licence=sources.CC0, licence_url=sources.CC0_URLS[0], checked_on="2026-10-06", checked_by="a test")
        e.update(fields)
    return doc


def voice(seed, seconds=0.7, lead=0.15, tail=0.15):
    """A made-up meow: a gliding tone with three partials, a little noise and a two-hump envelope, with silence
    either side. The seed picks its pitch and glide, so two seeds are two different takes."""
    rng = random.Random(seed)
    f0, glide = 330.0 + 45.0 * (seed % 7), (60.0 + 13.0 * seed) * (-1) ** seed
    out, phase = [], 0.0
    for i in range(int(seconds * SR)):
        t = i / SR
        phase += 2 * math.pi * (f0 + glide * t + 25.0 * math.sin(2 * math.pi * 5.5 * t)) / SR
        env = math.sin(math.pi * t / seconds) ** 2 * (0.75 + 0.25 * math.sin(2 * math.pi * 3.0 * t + seed))
        out.append(0.4 * env * (math.sin(phase) + 0.5 * math.sin(2 * phase) + 0.25 * math.sin(3 * phase)
                                + 0.05 * (rng.random() - 0.5)))
    return [0.0] * int(lead * SR) + out + [0.0] * int(tail * SR)


def write_original(path, ints, rate=SR, channels=1, width=2):
    """A WAV standing in for a downloaded original: `ints` are 16-bit sample values, written as 16- or 24-bit
    PCM at `rate`, `channels` identical channels."""
    frames = bytearray()
    for v in ints:
        frames += (struct.pack("<h", v) if width == 2 else struct.pack("<i", v << 8)[:3]) * channels
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(width)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def quantise(x):
    """(16-bit ints, the floats a decoder gives back for them): what an original holds and what a preview shows."""
    ints = [max(-32768, min(32767, int(round(v * 32768)))) for v in x]
    return ints, [i / 32768.0 for i in ints]
