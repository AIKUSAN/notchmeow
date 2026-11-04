"""Small DSP helpers on plain Python lists of floats (mono, 48 kHz).

Standard library only. Everything here is deterministic: no clocks, no unseeded randomness.
"""
from __future__ import annotations

import math
from collections import deque

SR = 48000


def db_to_lin(db):
    return 10.0 ** (db / 20.0)


def lin_to_db(x):
    return 20.0 * math.log10(max(x, 1e-12))


def peak(x):
    return max((abs(v) for v in x), default=0.0)


def rms(x):
    if not x:
        return 0.0
    return math.sqrt(sum(v * v for v in x) / len(x))


def gain(x, db):
    g = db_to_lin(db)
    return [v * g for v in x]


def mix_at(base, layer, offset):
    """Sum `layer` into `base` starting at sample `offset`. Returns a new list."""
    n = max(len(base), offset + len(layer))
    out = list(base) + [0.0] * (n - len(base))
    for i, v in enumerate(layer):
        out[offset + i] += v
    return out


# --- filters -----------------------------------------------------------------------------

def biquad(x, b0, b1, b2, a1, a2):
    """Transposed direct form II. The a0 coefficient is already normalised to 1."""
    z1 = z2 = 0.0
    out = []
    for v in x:
        y = b0 * v + z1
        z1 = b1 * v - a1 * y + z2
        z2 = b2 * v - a2 * y
        out.append(y)
    return out


def _rbj(kind, fc, q, sr):
    w0 = 2.0 * math.pi * fc / sr
    cw, sw = math.cos(w0), math.sin(w0)
    alpha = sw / (2.0 * q)
    if kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    elif kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    else:  # "bp": constant 0 dB peak gain
        b0, b1, b2 = alpha, 0.0, -alpha
    a0 = 1 + alpha
    return b0 / a0, b1 / a0, b2 / a0, (-2 * cw) / a0, (1 - alpha) / a0


def highpass(x, fc, sr=SR, q=0.7071067811865476):
    return biquad(x, *_rbj("hp", fc, q, sr))


def lowpass(x, fc, sr=SR, q=0.7071067811865476):
    return biquad(x, *_rbj("lp", fc, q, sr))


def bandpass(x, fc, q, sr=SR):
    return biquad(x, *_rbj("bp", fc, q, sr))


# --- fades -------------------------------------------------------------------------------

def fade(x, in_ms=3.0, out_ms=20.0, sr=SR):
    """Half-cosine fades. The first and the last sample come out exactly 0."""
    n = len(x)
    if n < 2:
        return [0.0] * n
    n_in = min(int(round(in_ms * sr / 1000.0)), n // 2)
    n_out = min(int(round(out_ms * sr / 1000.0)), n - n_in)
    out = list(x)
    for i in range(n_in):
        out[i] *= 0.5 * (1.0 - math.cos(math.pi * i / n_in))
    for j in range(n_out):
        out[n - n_out + j] *= 0.5 * (1.0 + math.cos(math.pi * j / max(n_out - 1, 1)))
    out[0] = 0.0
    out[-1] = 0.0
    return out


def fade_equal_power(x, in_ms=0.0, out_ms=0.0, sr=SR):
    """Equal-power fades, a sine in and a cosine out. Two sounds that do not match sample for sample,
    crossfaded over the same span, keep their level; half-cosine fades would dip about 3 dB at the
    seam. Unlike `fade`, the last sample is not forced to zero. A fade longer than x is cut to x."""
    n = len(x)
    n_in = min(int(round(in_ms * sr / 1000.0)), n)
    n_out = min(int(round(out_ms * sr / 1000.0)), n)
    out = list(x)
    for i in range(n_in):
        out[i] *= math.sin(0.5 * math.pi * i / n_in)
    for j in range(n_out):
        out[n - n_out + j] *= math.cos(0.5 * math.pi * j / n_out)
    return out


# --- level measured the way the made-in-code sounds are scaled ---------------------------

def env_peak(x, win_ms=4.0, hop_ms=1.0, sr=SR):
    """The loudest short RMS of x (linear): windows of `win_ms`, a new one every `hop_ms`. 0.0 when x
    is shorter than one window."""
    w = int(round(win_ms * sr / 1000.0))
    h = int(round(hop_ms * sr / 1000.0))
    cs = [0.0]
    for v in x:
        cs.append(cs[-1] + v * v)
    best, i = 0.0, 0
    while i + w <= len(x):
        best = max(best, math.sqrt((cs[i + w] - cs[i]) / w))
        i += h
    return best


def scale_to_env_peak(x, target):
    """x with its loudest 4 ms RMS (`env_peak`) set to `target`. A silent x comes back unchanged."""
    top = env_peak(x)
    return [v * target / top for v in x] if top > 0 else list(x)


# --- resampling: pitch shift, glide, wobble ---------------------------------------------

def _cubic(x, pos, last):
    i = int(pos)
    t = pos - i
    p0 = x[i - 1] if i > 0 else x[0]
    p1 = x[i]
    p2 = x[i + 1] if i + 1 <= last else x[last]
    p3 = x[i + 2] if i + 2 <= last else x[last]
    return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                  + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t)


def varispeed(x, ratio_at):
    """Read `x` at a varying speed. `ratio_at(j, progress)` gives the read-speed ratio for output
    sample j, where progress is the read position as a fraction of the input (0..1).
    Ratio 2 reads twice as fast: one octave up, half as long."""
    n = len(x)
    if n < 2:
        return list(x)
    last = n - 1
    out = []
    pos = 0.0
    j = 0
    while pos <= last:
        out.append(_cubic(x, pos, last))
        pos += ratio_at(j, pos / last)
        j += 1
    return out


def pitch_shift(x, semitones):
    """Pitch shift by resampling (the length changes by 2^(st/12))."""
    if semitones == 0:
        return list(x)
    r = 2.0 ** (semitones / 12.0)
    return varispeed(x, lambda j, p: r)


def glide(x, st_from, st_to):
    """Pitch ramp: the pitch offset moves linearly from st_from to st_to over the clip."""
    def ratio(j, p):
        return 2.0 ** ((st_from + (st_to - st_from) * p) / 12.0)
    return varispeed(x, ratio)


def wobble(x, rate_hz=5.0, depth_st=1.0, sr=SR):
    """Vibrato: the pitch swings +-depth_st semitones, rate_hz times a second."""
    w = 2.0 * math.pi * rate_hz / sr

    def ratio(j, p):
        return 2.0 ** (depth_st * math.sin(w * j) / 12.0)
    return varispeed(x, ratio)


# --- trimming and onsets -----------------------------------------------------------------

def seconds_span(n, start=None, end=None, sr=SR):
    """(a, b) sample indices of the part of an n-sample clip between two times; (0, 0) when it is empty."""
    a = 0 if start is None else max(0, int(round(start * sr)))
    b = n if end is None else min(n, int(round(end * sr)))
    return (a, b) if b > a else (0, 0)


def seconds_slice(x, start=None, end=None, sr=SR):
    a, b = seconds_span(len(x), start, end, sr)
    return list(x[a:b])


def frame_rms(x, frame):
    return [rms(x[i:i + frame]) for i in range(0, len(x), frame)]


def trim_silence_span(x, sr=SR, floor_db=-35.0, pad_ms=5.0):
    """(a, b) of the part of x that trim_silence keeps."""
    frame = int(sr * 0.010)
    env = frame_rms(x, frame)
    if not env or max(env) == 0.0:
        return 0, len(x)
    thr = max(env) * db_to_lin(floor_db)
    idx = [i for i, e in enumerate(env) if e >= thr]
    pad = int(sr * pad_ms / 1000.0)
    return max(0, idx[0] * frame - pad), min(len(x), (idx[-1] + 1) * frame + pad)


def trim_silence(x, sr=SR, floor_db=-35.0, pad_ms=5.0):
    """Cut leading and trailing frames more than |floor_db| below the loudest 10 ms frame."""
    a, b = trim_silence_span(x, sr, floor_db, pad_ms)
    return list(x[a:b])


def loudest_window_span(x, length, sr=SR):
    """(a, b) of the `length`-sample window with the most energy, searched in 10 ms steps."""
    if len(x) <= length:
        return 0, len(x)
    cs = [0.0]
    for v in x:
        cs.append(cs[-1] + v * v)
    step = int(sr * 0.010)
    best_i, best_e = 0, -1.0
    for i in range(0, len(x) - length + 1, step):
        e = cs[i + length] - cs[i]
        if e > best_e:
            best_i, best_e = i, e
    return best_i, best_i + length


def loudest_window(x, length, sr=SR):
    a, b = loudest_window_span(x, length, sr)
    return list(x[a:b])


def auto_trim_span(x, max_len_s, sr=SR):
    """(a, b) of the part of x that auto_trim keeps: the silence dropped, then the loudest window of at most
    max_len_s."""
    a, b = trim_silence_span(x, sr)
    i, j = loudest_window_span(x[a:b], int(max_len_s * sr), sr)
    return a + i, a + j


def auto_trim(x, max_len_s, sr=SR):
    """No explicit trim: drop the silence, then keep the loudest window of at most max_len_s."""
    a, b = auto_trim_span(x, max_len_s, sr)
    return list(x[a:b])


def onset_index(x, rel_db=-24.0):
    """Index of the first sample within |rel_db| of the clip's peak: the first transient."""
    p = peak(x)
    if p == 0.0:
        return 0
    thr = p * db_to_lin(rel_db)
    for i, v in enumerate(x):
        if abs(v) >= thr:
            return i
    return 0


def active_rms(x, sr=SR):
    """RMS over the 10 ms frames within 20 dB of the loudest frame: the level of the sound itself,
    not of the silence around it."""
    frame = int(sr * 0.010)
    env = frame_rms(x, frame)
    if not env or max(env) == 0.0:
        return 0.0
    thr = max(env) * db_to_lin(-20.0)
    energy, count = 0.0, 0
    for i, e in enumerate(env):
        if e >= thr:
            seg = x[i * frame:(i + 1) * frame]
            energy += sum(v * v for v in seg)
            count += len(seg)
    return math.sqrt(energy / count)


# --- peak limiter ------------------------------------------------------------------------

def limit(x, ceiling_db, lookahead_ms=5.0, sr=SR):
    """Look-ahead limiter: no sample ends above `ceiling_db`. The gain starts to fall one look-ahead
    before a peak and comes back over one look-ahead after it. Untouched when nothing is over."""
    c = db_to_lin(ceiling_db)
    n = len(x)
    if n == 0 or peak(x) <= c:
        return list(x)
    la = max(1, int(round(lookahead_ms * sr / 1000.0)))
    need = [c / abs(v) if abs(v) > c else 1.0 for v in x]
    # m[j] = min(need[j .. j+la]), by a monotonic queue
    q, m = deque(), [1.0] * n
    for j in range(n - 1, -1, -1):
        while q and need[q[-1]] >= need[j]:
            q.pop()
        q.append(j)
        while q[0] > j + la:
            q.popleft()
        m[j] = need[q[0]]
    # g[i] = mean(m[i-la .. i]); each of those windows contains i, so g[i] <= need[i]
    out, acc = [], 0.0
    for i in range(n):
        acc += m[i]
        if i > la:
            acc -= m[i - la - 1]
        out.append(x[i] * (acc / min(i + 1, la + 1)))
    return out
