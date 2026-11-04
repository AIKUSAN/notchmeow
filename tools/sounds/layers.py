"""The two layers on top of a cat moment (spec section 3): the touch and the signature.

Both are made in code and scaled against the vocal they sit on. The touch is a short musical hint
of the mood, placed on the vocal's first transient. The signature is three inharmonic collar-bell
partials that climb, placed at 60 % of the vocal's length.
"""
from __future__ import annotations

import math
import random

from dsp import SR, active_rms, db_to_lin, lowpass, mix_at, onset_index, rms

MOODS = ("happy", "attention", "upset", "calm")
TOUCH_DB = -18.0
SIGNATURE_DB = -10.0
SIGNATURE_START = 0.60


def _n(seconds):
    return int(round(seconds * SR))


def _attack(t, seconds):
    return min(1.0, t / seconds) if seconds > 0 else 1.0


def _tail(t, length, seconds=0.005):
    """A short fade at the end of a layer so it never clicks off."""
    return min(1.0, max(0.0, (length - t) / seconds))


def _peak_to(x, level):
    top = max(abs(v) for v in x)
    return [level * v / top for v in x]


def touch(mood):
    """The touch layer for a mood, 120 ms at most, peak 0.5 (the level is set against the vocal)."""
    if mood == "happy":          # two sine partials, a major third apart, one after the other
        length = 0.110
        out = [0.0] * _n(length)
        for start, freq in ((0.0, 784.0), (0.045, 784.0 * 2.0 ** (4.0 / 12.0))):
            for i in range(_n(length - start)):
                t = i / SR
                out[_n(start) + i] += (math.sin(2.0 * math.pi * freq * t) * _attack(t, 0.003)
                                       * math.exp(-t / 0.020))
        return _peak_to([v * _tail(i / SR, length) for i, v in enumerate(out)], 0.5)
    if mood == "attention":      # an 80 ms glide up a fifth
        length = 0.080
        out, phase = [], 0.0
        for i in range(_n(length)):
            t = i / SR
            phase += 2.0 * math.pi * 600.0 * 2.0 ** (7.0 / 12.0 * t / length) / SR
            out.append(math.sin(phase) * _attack(t, 0.004) * (1.0 - t / length) ** 0.5
                       * _tail(t, length))
        return _peak_to(out, 0.5)
    if mood == "upset":          # a filtered buzzy tone gliding down a minor third
        length = 0.110
        out, phase = [], 0.0
        for i in range(_n(length)):
            t = i / SR
            phase += 2.0 * math.pi * 330.0 * 2.0 ** (-3.0 / 12.0 * t / length) / SR
            buzz = sum(math.sin(k * phase) / k for k in range(1, 7))
            out.append(buzz * _attack(t, 0.003) * math.exp(-t / 0.055) * _tail(t, length))
        return _peak_to(lowpass(out, 1200.0, SR, 0.7), 0.5)
    if mood == "calm":           # one soft, low-passed tick
        length = 0.060
        rng = random.Random(1301)
        out = [(rng.random() * 2.0 - 1.0) * math.exp(-(i / SR) / 0.008) * _attack(i / SR, 0.001)
               * _tail(i / SR, length) for i in range(_n(length))]
        return _peak_to(lowpass(out, 1800.0, SR, 0.7), 0.5)
    raise ValueError("unknown mood: %r" % (mood,))


def signature(dark=False):
    """Three inharmonic collar-bell partials that climb, 0.2 s. `dark` is the lower, slower version
    the error slot gets."""
    if dark:
        freqs, t60s = (1125.0, 1700.0, 2525.0), (0.20, 0.17, 0.14)
    else:
        freqs, t60s = (2250.0, 3400.0, 5050.0), (0.14, 0.12, 0.10)
    length = 0.200
    out = [0.0] * _n(length)
    for k, (freq, t60) in enumerate(zip(freqs, t60s)):
        start = 0.040 * k                       # each partial enters higher than the last
        for i in range(_n(length - start)):
            t = i / SR
            out[_n(start) + i] += (0.3 * math.sin(2.0 * math.pi * freq * t + 0.5 * k)
                                   * _attack(t, 0.002) * 10.0 ** (-3.0 * t / t60))
    return [v * _tail(i / SR, length) for i, v in enumerate(out)]


def thump():
    """The tail thump for the rate slot: 100 Hz, fast decay, 0.16 s."""
    length = 0.160
    return [0.8 * math.sin(2.0 * math.pi * 100.0 * (i / SR)) * _attack(i / SR, 0.002)
            * math.exp(-(i / SR) / 0.045) * _tail(i / SR, length) for i in range(_n(length))]


def scaled(layer, vocal, rel_db):
    """`layer` with its RMS set to rel_db from the vocal's active RMS."""
    level = rms(layer)
    if level == 0.0:
        return list(layer)
    k = active_rms(vocal) * db_to_lin(rel_db) / level
    return [v * k for v in layer]


def touch_layer(vocal, mood):
    """(offset, samples): the mood's touch, TOUCH_DB under the vocal, on its first transient."""
    return onset_index(vocal), scaled(touch(mood), vocal, TOUCH_DB)


def signature_layer(vocal, dark=False):
    """(offset, samples): the signature, SIGNATURE_DB under the vocal, at 60 % of its length."""
    return int(SIGNATURE_START * len(vocal)), scaled(signature(dark), vocal, SIGNATURE_DB)


def thump_layer(vocal):
    """(offset, samples): the tail thump, 6 dB under the vocal, starting 20 ms before it ends."""
    return max(0, len(vocal) - _n(0.020)), scaled(thump(), vocal, -6.0)


def add_layers(vocal, mood, with_signature=False, dark=False, with_thump=False, with_touch=True):
    """The vocal with its layers mixed in. Every layer is scaled against the vocal alone, never
    against the other layers. The result can run past the vocal's end. The hairball is the one cat
    moment without the touch."""
    out = list(vocal)
    parts = [touch_layer(vocal, mood)] if with_touch else []
    if with_signature:
        parts.append(signature_layer(vocal, dark))
    if with_thump:
        parts.append(thump_layer(vocal))
    for offset, layer in parts:
        out = mix_at(out, layer, offset)
    return out
