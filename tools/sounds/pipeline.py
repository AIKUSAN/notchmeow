"""Turn recipe entries into finished sounds: trim, shape, layer, level, write.

The order follows the spec's section 2, except that the layers are mixed in before the loudness step, on purpose: mixing them in after the limiter would break the -1 dBTP guarantee. Steps: decode, trim, pitch, effects, 100 Hz high-pass, fades, layers, fades, loudness and true-peak limit, 16-bit WAV. `loader.load(source)` returns the decoded 48 kHz mono clip;
tests give it a dictionary, the CLI gives it afconvert.
"""
from __future__ import annotations

import os
from collections import namedtuple

import dsp
import layers
import loudness
from audio_io import read_wav, write_wav16
from recipe import PLACED, SLOTS
from synth import GAPS, LAYERS

# short-term LUFS target and tolerance in LU, by kind (spec section 6: both +-1.5). Ticks sit 8 dB under the vocals.
TARGETS = {"cat": (-20.0, 1.5), "tick": (-28.0, 1.5)}
TP_CEILING = -1.0
FADE_IN_MS, FADE_OUT_MS = 3.0, 20.0

SILENT_DB = -70.0       # a source window quieter than this is a pause, not a sound

Built = namedtuple("Built", "slot samples gain_db limit_db")


class SourceError(ValueError):
    """A recipe points at a window that is empty or silent."""


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


def source_span(entry, clip, shift):
    """(a, b) sample indices of the part of `clip` that an ordinary entry builds from: its window, or, with no
    explicit trim, what the automatic trim keeps (silence dropped, then the loudest part that fits after the shift).
    `_source` below cuts the same way; tests/test_sound_align.py pins that the two agree."""
    if entry.start is None and entry.end is None:
        return dsp.auto_trim_span(clip, SLOTS[entry.slot].max_len * 2.0 ** (shift / 12.0))
    return dsp.seconds_span(len(clip), entry.start, entry.end)


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


def build_slot(entry, loader, set_pitch_st=0.0):
    """Render one slot. `set_pitch_st` is the set's shared shift; it applies to recorded clips of
    that set only, never to the shared ticks and fill-ins."""
    info = SLOTS[entry.slot]
    recorded = not entry.shared and not entry.source.startswith("synth:")
    shift = entry.pitch_st + (set_pitch_st if recorded else 0.0)
    x = dsp.pitch_shift(_source(entry, info, loader, shift), shift)
    for fx in entry.effects:
        if fx["type"] == "wobble":
            x = dsp.wobble(x, fx["rate_hz"], fx["depth_st"])
        elif fx["type"] == "glide":
            x = dsp.glide(x, fx["from_st"], fx["to_st"])
    x = dsp.highpass(x[:int(info.max_len * dsp.SR)], entry.hp_hz)
    x = dsp.fade(x, FADE_IN_MS, FADE_OUT_MS)
    if info.kind == "cat":
        x = layers.add_layers(x, entry.mood, entry.signature, info.dark,
                              any(fx["type"] == "thump" for fx in entry.effects), info.touch)
    x = dsp.fade(x[:int(info.max_len * dsp.SR)], FADE_IN_MS, FADE_OUT_MS)
    target, _ = TARGETS[info.kind]
    y, norm = loudness.normalize(x, target + entry.gain_db, TP_CEILING)
    return Built(entry.slot, y, norm.gain_db, norm.limit_db)


def build_set(recipe, loader, out_dir, cache=None):
    """Build every slot of a SetRecipe into out_dir/<slot>.wav. Shared slots are rendered once and
    reused through `cache` (a dict) when several sets are built in one run. Returns the Built list."""
    os.makedirs(str(out_dir), exist_ok=True)
    cache = {} if cache is None else cache
    built = []
    for slot, entry in recipe.entries.items():
        key = (repr(entry), None if entry.shared else recipe.pitch_st)
        if key not in cache:
            cache[key] = build_slot(entry, loader, recipe.pitch_st)
        b = cache[key]
        write_wav16(os.path.join(str(out_dir), slot + ".wav"), b.samples)
        built.append(b)
    return built


def read_back(out_dir, slot):
    """The written WAV, as the report and the owner's ears see it."""
    return read_wav(os.path.join(str(out_dir), slot + ".wav"))[0]
