"""Does an original still hold the same sound as the preview clip a window was chosen on?

The recipes were written against the Freesound preview clips (MP3, decoded to 48 kHz mono). Stage 2 builds
from the full-quality originals instead, and an original can differ from its preview in offset (a trimmed
start), in length, or be a different file altogether. The rule, applied to every window of every clip:

  1. Offset. Search the original for the preview's window, within +-100 ms: a coarse pass on 1 ms
     loudness envelopes, then a fine pass on the waveform (low-passed at 3 kHz and cut to 8 kHz, which the
     MP3 keeps faithfully) in steps of 0.125 ms. The best lag is the clip's offset; the build shifts the
     original by it, so every recipe window keeps its meaning.
  2. Same sound. After the shift, the waveform of the original's window must correlate with the preview's
     window at 0.80 or better (a residual of +-1 ms is allowed). A window that runs off the end of a shorter
     original, a different take of the same cat, and a clip at another speed all fall far below that.

Calibrated on the 24 real windows of Your mix (preview clips, 2026-10-05): the same window through a gain
change, noise at -40 dB, or a 5 kHz low-pass (all harsher than the MP3) scores 0.87 or better; 548 pairs of
different real clips, each searched for its best offset, score 0.35 at the most and none passes. (A second
test, the time a window stays within 30 dB of its peak, was tried and dropped: hiss in an original lifts a
quiet fade above the threshold and moves it by 40 ms or more, while the waveform still matches at 0.99.)

Pure Python, standard library only. Samples are 48 kHz mono lists of floats.
"""
from __future__ import annotations

import math
from collections import namedtuple

import dsp
from dsp import SR

HOP = SR // 1000            # 1 ms: the coarse envelope
DECIMATE = 6                # 48 kHz -> 8 kHz for the fine pass
FINE_HZ = 3000.0
MAX_LAG_S = 0.100
MARGIN_S = 0.150            # context around a window when measuring the offset
FINE_SPAN_MS = 3            # the fine pass looks +-3 ms around the coarse lag
MIN_R = 0.80
RESIDUAL_MS = 1

Verdict = namedtuple("Verdict", "r ok")


def envelope(x):
    """RMS of every 1 ms block."""
    return [math.sqrt(sum(v * v for v in x[i:i + HOP]) / HOP) for i in range(0, len(x) - HOP + 1, HOP)]


def pearson(a, b):
    """Correlation of two equal-length lists; 0.0 when either is flat."""
    n = min(len(a), len(b))
    if n < 2:
        return 0.0
    ma, mb = sum(a[:n]) / n, sum(b[:n]) / n
    sab = saa = sbb = 0.0
    for i in range(n):
        da, db = a[i] - ma, b[i] - mb
        sab += da * db
        saa += da * da
        sbb += db * db
    return sab / math.sqrt(saa * sbb) if saa > 0.0 and sbb > 0.0 else 0.0


def decimate(x):
    return dsp.lowpass(dsp.lowpass(x, FINE_HZ), FINE_HZ)[::DECIMATE]


def padded(x, a, b):
    """x[a:b] with zeros where the range runs outside the clip."""
    out = [0.0] * max(0, -a) + list(x[max(a, 0):max(b, 0)])
    return out + [0.0] * (b - a - len(out))


def measure_offset(p, o, a, b):
    """How much later the preview's window p[a:b] sits in the original o: returns (offset in samples, r).
    o[i + offset] matches p[i]. r is the waveform correlation at that offset, 0 to 1."""
    ra, rb = max(0, a - int(MARGIN_S * SR)), min(len(p), b + int(MARGIN_S * SR))
    ra -= ra % HOP
    rb -= (rb - ra) % HOP
    reach = int(MAX_LAG_S * SR)
    pad = reach + FINE_SPAN_MS * HOP                    # a multiple of DECIMATE, so the fine grid lines up
    wide = padded(o, ra - pad, rb + pad)
    pe = envelope(p[ra:rb])
    oe = envelope(wide)
    lead = pad // HOP                                   # envelope blocks before the region starts
    steps = reach // HOP
    best_ms, best_r = 0, -2.0
    for lag in sorted(range(-steps, steps + 1), key=abs):
        r = pearson(pe, oe[lead + lag: lead + lag + len(pe)])
        if r > best_r + 1e-12:
            best_ms, best_r = lag, r
    pd, od = decimate(p[ra:rb]), decimate(wide)
    best_lag, best = 0, -2.0
    span = FINE_SPAN_MS * HOP // DECIMATE
    centre = best_ms * HOP // DECIMATE
    for k in sorted(range(-span, span + 1), key=abs):
        start = pad // DECIMATE + centre + k
        r = pearson(pd, od[start:start + len(pd)])
        if r > best + 1e-12:
            best_lag, best = (centre + k) * DECIMATE, r
    return best_lag, max(best, 0.0)


def shift_clip(o, offset):
    """The original moved into preview time: the result's sample i is o[i + offset]."""
    return list(o[offset:]) if offset >= 0 else [0.0] * -offset + list(o)


def window_verdict(p, q, a, b):
    """Does q[a:b] (the original, already shifted into preview time) hold the same sound as p[a:b]?"""
    pd, qd = decimate(p[a:b]), decimate(padded(q, a, b))
    r = max((pearson(pd[max(0, -k):], qd[max(0, k):]) for k in range(-RESIDUAL_MS * 8, RESIDUAL_MS * 8 + 1)),
            default=0.0)
    return Verdict(round(max(r, 0.0), 4), r >= MIN_R)
