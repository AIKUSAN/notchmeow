"""Loudness measurement: ITU-R BS.1770 K-weighting, short-term loudness, true peak, RMS.

Standard library only. The K-weighting coefficients are the ones the standard gives for 48 kHz,
so every measurement here works on 48 kHz audio only.
"""
from __future__ import annotations

import math
from collections import namedtuple

from dsp import SR, biquad, gain, limit, lin_to_db, peak, rms

# BS.1770-4, 48 kHz: stage 1 is the high shelf, stage 2 the RLB high-pass.
_K1 = (1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585)
_K2 = (1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621)

BLOCK = int(SR * 0.400)   # 400 ms measurement block
HOP = int(SR * 0.100)     # 75 % overlap
SILENT_LUFS = -120.0

Measurement = namedtuple("Measurement", "lufs rms_db tp_db peak_db seconds")
Norm = namedtuple("Norm", "gain_db limit_db")


def k_weight(x):
    return biquad(biquad(x, *_K1), *_K2)


def short_term_lufs(x, sr=SR):
    """Loudest 400 ms block, in LUFS (no gating). A clip shorter than 400 ms is zero-padded to one
    block, so a short sound is measured the way it will sit in the mix, not stretched to fill it."""
    if sr != SR:
        raise ValueError("loudness is only defined here for 48 kHz audio")
    if not x:
        return SILENT_LUFS
    w = k_weight(x)
    cs = [0.0]
    for v in w:
        cs.append(cs[-1] + v * v)
    n = len(w)
    last = max(n - BLOCK, 0)
    starts = list(range(0, last + 1, HOP))
    if starts[-1] != last:
        starts.append(last)
    best = 0.0
    for s in starts:
        e = cs[min(s + BLOCK, n)] - cs[s]
        best = max(best, e / BLOCK)
    if best <= 0.0:
        return SILENT_LUFS
    return -0.691 + 10.0 * math.log10(best)


def rms_dbfs(x):
    return lin_to_db(rms(x))


def _sinc(t):
    if t == 0.0:
        return 1.0
    return math.sin(math.pi * t) / (math.pi * t)


_L = 12
# Lanczos kernels for the three in-between points of a 4x oversample, taps for x[i-L+1 .. i+L]
_KERNELS = [[_sinc(k - f) * _sinc((k - f) / _L) for k in range(-_L + 1, _L + 1)]
            for f in (0.25, 0.5, 0.75)]


def true_peak_dbtp(x, sr=SR):
    """Approximate true peak by 4x oversampling (BS.1770 Annex 2 style). Only the neighbourhoods of
    samples within 6 dB of the peak are interpolated: elsewhere no in-between value can top it.
    Never lower than the sample peak."""
    p = peak(x)
    if p == 0.0:
        return lin_to_db(0.0)
    n = len(x)
    thr = p * 0.5
    best = p
    for i, v in enumerate(x):
        if abs(v) < thr:
            continue
        for base in (i - 1, i):
            if base < 0 or base >= n - 1:
                continue
            for taps in _KERNELS:
                acc = 0.0
                for k, h in enumerate(taps):
                    idx = base - _L + 1 + k
                    if 0 <= idx < n:
                        acc += x[idx] * h
                a = abs(acc)
                if a > best:
                    best = a
    return lin_to_db(best)


def measure(x, sr=SR):
    return Measurement(short_term_lufs(x, sr), rms_dbfs(x), true_peak_dbtp(x, sr),
                       lin_to_db(peak(x)), len(x) / float(sr))


def normalize(x, target_lufs, ceiling_dbtp=-1.0, sr=SR):
    """Gain `x` to `target_lufs` short-term loudness with its true peak at or under `ceiling_dbtp`.

    Peaky sounds (a pat, a click, a short meow) cannot reach the target before their peaks hit the
    ceiling, so a look-ahead limiter takes the peaks down and the gain goes up again to make up the
    loudness the limiter removed. If the limited signal still overshoots between samples, the
    limiter's own ceiling comes down by the overshoot. A few rounds settle both. Returns
    (samples, Norm(gain_db, limit_db)), limit_db being the deepest gain reduction the limiter
    applied. Silence comes back untouched."""
    lufs = short_term_lufs(x, sr)
    if lufs <= SILENT_LUFS:
        return list(x), Norm(0.0, 0.0)
    g = target_lufs - lufs
    head = ceiling_dbtp - 0.5            # the limiter's sample-peak ceiling
    for _ in range(6):
        hot = gain(x, g)
        y = limit(hot, head)
        tp = true_peak_dbtp(y, sr)
        if tp > ceiling_dbtp + 0.01:
            head -= tp - ceiling_dbtp
            continue
        short = target_lufs - short_term_lufs(y, sr)
        if short < 0.1:
            break
        g += short
    limited = max(lin_to_db(peak(hot)) - lin_to_db(peak(y)), 0.0)
    if tp > ceiling_dbtp:                # settled badly: fall back to plain gain reduction
        y = gain(y, ceiling_dbtp - tp)
        g += ceiling_dbtp - tp
    return y, Norm(g, limited)
