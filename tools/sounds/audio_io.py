"""WAV reading and writing, and decoding of the candidate clips with macOS afconvert."""
from __future__ import annotations

import os
import struct
import subprocess
import tempfile
import wave
from array import array

from dsp import SR


def write_wav16(path, x, sr=SR):
    """Write mono 16-bit PCM. Samples are rounded to the nearest step and clamped; the wave module
    writes no timestamps, so equal samples always give equal bytes."""
    ints = []
    for v in x:
        i = int(v * 32768.0 + 0.5) if v >= 0 else -int(-v * 32768.0 + 0.5)
        ints.append(32767 if i > 32767 else (-32768 if i < -32768 else i))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(struct.pack("<%dh" % len(ints), *ints))


def read_wav(path):
    """Read 16-bit or 32-bit PCM, any channel count (averaged to mono). Returns (samples, rate)."""
    with wave.open(str(path), "rb") as w:
        ch, width, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width == 2:
        ints, scale = struct.unpack("<%dh" % (n * ch), raw), 32768.0
    elif width == 4:
        ints, scale = struct.unpack("<%di" % (n * ch), raw), 2147483648.0
    else:
        raise ValueError("%s: only 16-bit and 32-bit PCM are supported" % path)
    if ch == 1:
        return array("d", [v / scale for v in ints]), sr
    mono = array("d", [sum(ints[i:i + ch]) / (ch * scale) for i in range(0, len(ints), ch)])
    return mono, sr


def decode_clip(path):
    """Decode any clip afconvert can read to 48 kHz, as a mono array('d'). The sample-rate
    conversion is afconvert's; the mono downmix (channel average) is ours."""
    with tempfile.TemporaryDirectory(prefix="nm-sound-") as tmp:
        out = os.path.join(tmp, "decoded.wav")
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI32@%d" % SR, str(path), out],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        x, sr = read_wav(out)
    if sr != SR:
        raise ValueError("%s decoded at %d Hz, expected %d" % (path, sr, SR))
    return x


class AfconvertLoader:
    """Decodes candidate clips on demand and keeps them for the run. `source` is
    '<folder>/<file>' under the candidates directory."""

    def __init__(self, candidates_dir):
        self.root = str(candidates_dir)
        self._cache = {}

    def load(self, source):
        if source not in self._cache:
            path = os.path.join(self.root, *source.split("/"))
            if not os.path.isfile(path):
                raise FileNotFoundError("candidate clip not found: %s" % path)
            self._cache[source] = decode_clip(path)
        return self._cache[source]
