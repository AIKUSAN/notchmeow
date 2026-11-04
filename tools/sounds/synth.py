"""Made-in-code sounds that fill the gaps in the recordings (spec section 2, "Gap recipes").

Every recipe in GAPS returns a list of floats at 48 kHz, about 0.5 of full scale; the build
normalises the level afterwards. Noise comes from random.Random with a fixed seed, so the output
never changes. LAYERS holds the made-in-code parts a placed sound mixes in among its clip segments
(recipe "synth_layers"): they take a seed and are scaled on the 4 ms RMS scale of the segments' levels.
"""
from __future__ import annotations

import math
import random

from dsp import SR, bandpass, lowpass, mix_at, peak, scale_to_env_peak


def _n(seconds):
    return int(round(seconds * SR))


def _noise(rng, count):
    return [rng.random() * 2.0 - 1.0 for _ in range(count)]


def _smooth(t, a, b):
    """0 before a, 1 after b, a raised-cosine ramp between."""
    if t <= a:
        return 0.0
    if t >= b:
        return 1.0
    return 0.5 * (1.0 - math.cos(math.pi * (t - a) / (b - a)))


def blip():
    """A small rising 'bloop' for the interface blip. 0.1 s."""
    out, phase = [], 0.0
    for i in range(_n(0.100)):
        t = i / SR
        f = 1250.0 + 450.0 * (t / 0.100)
        phase += 2.0 * math.pi * f / SR
        env = _smooth(t, 0.0, 0.003) * math.exp(-t / 0.030)
        out.append(0.5 * env * (math.sin(phase) + 0.25 * math.sin(2.0 * phase)))
    return out


def clink():
    """Collar-tag clink: two inharmonic partials at 3.2 and 5.3 kHz, decay about 150 ms, plus a
    2 ms click. 0.25 s."""
    rng = random.Random(1201)
    out = []
    for i in range(_n(0.250)):
        t = i / SR
        a = math.exp(-t / 0.045) * math.sin(2.0 * math.pi * 3180.0 * t)
        b = 0.6 * math.exp(-t / 0.028) * math.sin(2.0 * math.pi * 5290.0 * t + 0.7)
        click = 0.5 * (rng.random() * 2.0 - 1.0) * math.exp(-t / 0.0008)
        out.append(0.4 * (a + b + click))
    return out


def yawn():
    """A falling squeak (1.2 kHz down to 500 Hz) over breathy noise. 0.8 s."""
    rng = random.Random(1202)
    total = _n(0.800)
    noise = bandpass(_noise(rng, total), 2600.0, 0.7)
    out, phase = [], 0.0
    for i in range(total):
        t = i / SR
        f = 1200.0 * (500.0 / 1200.0) ** (t / 0.800)
        phase += 2.0 * math.pi * f / SR
        tone_env = _smooth(t, 0.10, 0.32) * (1.0 - _smooth(t, 0.45, 0.80))
        tone = tone_env * (math.sin(phase) + 0.4 * math.sin(2.0 * phase) + 0.15 * math.sin(3.0 * phase))
        breath_env = _smooth(t, 0.0, 0.35) * (1.0 - _smooth(t, 0.40, 0.80))
        out.append(0.35 * tone + 0.5 * breath_env * noise[i])
    return out


def work():
    """Kneading: three soft fabric pats, 0.5 s apart (2 Hz), alternating a darker and a brighter
    pat (the stereo left and right of the recipe, folded to mono). 1.3 s."""
    rng = random.Random(1203)
    total = _n(1.300)
    out = [0.0] * total
    for k, (start, length, cutoff, level) in enumerate(
            [(0.05, 0.080, 500.0, 1.0), (0.55, 0.060, 800.0, 0.8), (1.05, 0.080, 500.0, 1.0)]):
        n = _n(length)
        burst = lowpass(_noise(rng, n), cutoff, SR, 0.7)
        a = _n(start)
        for i in range(n):
            t = i / SR
            env = _smooth(t, 0.0, 0.006) * (1.0 - _smooth(t, length * 0.4, length))
            out[a + i] += level * env * burst[i]
    return out


def search():
    """A chatter: a 620 Hz pulse train through two formant resonators, gated at 12 Hz (a click
    train with a throat). 0.9 s."""
    rng = random.Random(1204)
    total = _n(0.900)
    carrier = [0.0] * total
    step = SR / 620.0
    pos = 0.0
    while int(pos) < total:
        carrier[int(pos)] = 0.8 + 0.2 * rng.random()
        pos += step
    low = bandpass(carrier, 1100.0, 3.5)
    high = bandpass(carrier, 2700.0, 4.0)
    out = []
    for i in range(total):
        t = i / SR
        phase = (t * 12.0) % 1.0                      # position inside one 83 ms chirp
        gate = math.sin(math.pi * phase / 0.4) ** 2 if phase < 0.4 else 0.0
        env = _smooth(t, 0.0, 0.06) * (1.0 - _smooth(t, 0.70, 0.90))
        out.append(4.0 * gate * env * (low[i] + 0.7 * high[i]))
    return out


GAPS = {"blip": blip, "clink": clink, "yawn": yawn, "work": work, "search": search}


# --- the hairball's retch and plop (spec section 3, "Hairball") --------------------------------

HAIRBALL_LEVEL = 0.22        # the 4 ms RMS peak of the loudest heave on the hairball's timeline
RETCH_TO_PLOP_MS = 180       # the plop starts this long after the retch does (930 and 1110 ms)


def _ms(n):
    return int(round(n * SR / 1000.0))


def _pulses(rng, n, f_of_t, jitter=0.05, shimmer=0.25):
    """A pulse train whose rate follows f_of_t(seconds), with a little jitter in the spacing and
    shimmer in the height."""
    out = [0.0] * n
    phase, jit = 1.0, 1.0
    for i in range(n):
        phase += f_of_t(i / SR) * jit / SR
        if phase >= 1.0:
            phase -= 1.0
            out[i] = 1.0 + shimmer * (rng.random() * 2.0 - 1.0)
            jit = 1.0 + jitter * (rng.random() * 2.0 - 1.0)
    return out


def _formants(x, f1=650.0, q1=4.0, f2=1900.0, q2=5.0, w2=0.6, drive=2.2):
    """Two formant band-passes, then a soft saturation: a sparse pulse train rings with tall, narrow
    peaks, and the saturation (the throat's own grit) brings the crest factor down."""
    a, b = bandpass(x, f1, q1), bandpass(x, f2, q2)
    y = [p + w2 * q for p, q in zip(a, b)]
    top = peak(y) or 1.0
    return lowpass([math.tanh(drive * v / top) for v in y], 3200.0, SR, 0.7)   # keep the grit out of the hiss band


def _retch(rng):
    """The rising gurgle, 175 ms: a pulse train gliding from 120 to 280 Hz through the formants, with
    a little breath and a 28 Hz flutter, swelling for 160 ms and off by 175."""
    n = _ms(175)

    def f(t):
        return 120.0 + (280.0 - 120.0) * min(t / 0.180, 1.0)
    x = _formants(_pulses(rng, n, f, jitter=0.07, shimmer=0.35))
    br = bandpass(_noise(rng, n), 1500.0, 0.9)
    out = []
    for i in range(n):
        t = i / SR
        flutter = 1.0 - 0.5 * (0.5 + 0.5 * math.sin(2.0 * math.pi * 28.0 * t))
        swell = _smooth(t, 0.0, 0.160)
        stop = 1.0 - _smooth(t, 0.165, 0.175)
        out.append((x[i] + 0.25 * br[i] * 4.0) * flutter * swell * stop)
    return scale_to_env_peak(out, HAIRBALL_LEVEL * 0.85)


def _plop(rng):
    """The ball comes out at t=0, 480 ms: a falling sine with a short tail, a wet body and a faint
    tick, then a low wet tail of about 200 ms."""
    n = _ms(480)
    out = [0.0] * n
    ph = 0.0
    body = lowpass(_noise(rng, _ms(40)), 1200.0)
    for i in range(n):
        t = i / SR
        ph += 2.0 * math.pi * (180.0 + 340.0 * math.exp(-t / 0.015)) / SR
        env = _smooth(t, 0.0, 0.001) * math.exp(-t / 0.035)
        out[i] += env * (math.sin(ph) + 0.25 * math.sin(2.0 * ph))
    out = scale_to_env_peak(out, 1.0)                       # the sine's 4 ms RMS peak = 1.0
    for i, v in enumerate(body):
        out[i] += 0.45 * v * 4.0 * math.exp(-(i / SR) / 0.012) * _smooth(i / SR, 0.0, 0.0015)
    for i in range(_ms(30)):
        t = i / SR
        out[i] += 0.12 * math.sin(2.0 * math.pi * 3400.0 * t) * math.exp(-t / 0.006)
    tail = lowpass(_noise(rng, n), 800.0)
    for i in range(n):
        t = i / SR
        if t < 0.020:
            continue
        flutter = 0.5 + 0.5 * math.sin(2.0 * math.pi * 25.0 * t)
        a = _smooth(t, 0.020, 0.040) * (1.0 - _smooth(t, 0.220, 0.340))
        out[i] += 0.05 * 4.0 * tail[i] * (0.5 + 0.5 * flutter) * a
    return scale_to_env_peak(out, HAIRBALL_LEVEL)


def hairball_retch_plop(seed):
    """The hairball's made-in-code ending as one piece, 660 ms: the retch from 0 to 175 ms, the plop
    from 180 ms on. The placed sound puts it at 930 ms, so the plop lands at 1110, when the mouth is
    fully open and the ball comes out."""
    rng = random.Random(seed)
    retch = _retch(rng)
    plop = _plop(rng)
    return mix_at(retch, plop, _ms(RETCH_TO_PLOP_MS))


LAYERS = {"hairball_retch_plop": hairball_retch_plop}
