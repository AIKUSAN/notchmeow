"""The loudness report: every slot of every built set against the targets of spec section 2."""
from __future__ import annotations

from collections import namedtuple

import loudness
from pipeline import TARGETS, TP_CEILING, read_back
from recipe import SLOTS

TP_SLACK_DB = 0.05      # 16-bit rounding can move the true peak by a few thousandths of a dB
MIN_SECONDS = 0.05

Row = namedtuple("Row", "slot kind lufs target rms_db tp_db seconds limit_db problems")


def check(slot, m):
    """The ways measurement `m` of `slot` misses its targets, as short sentences. Empty means pass."""
    info = SLOTS[slot]
    target, tol = TARGETS[info.kind]
    out = []
    if abs(m.lufs - target) > tol:
        out.append("loudness %.1f LUFS is not %.1f +-%.1f" % (m.lufs, target, tol))
    if m.tp_db > TP_CEILING + TP_SLACK_DB:
        out.append("true peak %.2f dBTP is over %.1f" % (m.tp_db, TP_CEILING))
    if m.seconds > info.max_len + 1.0 / 48000:
        out.append("%.2f s is longer than %.1f s" % (m.seconds, info.max_len))
    if m.seconds < MIN_SECONDS:
        out.append("%.3f s is shorter than %.2f s" % (m.seconds, MIN_SECONDS))
    return out


def measure_files(pairs, out_dir):
    """Rows for built sounds, measured from the WAV files as written. `pairs` is [(file name, Built)]:
    out_dir/<file name>.wav holds the sound and the Built says which slot's targets apply. A set's file
    is named by its slot; a round-two alternative's by its id (rate-1)."""
    rows = []
    for name, b in pairs:
        info = SLOTS[b.slot]
        m = loudness.measure(read_back(out_dir, name))
        rows.append(Row(name, info.kind, m.lufs, TARGETS[info.kind][0], m.rms_db, m.tp_db,
                        m.seconds, b.limit_db, check(b.slot, m)))
    return rows


def measure_set(built, out_dir):
    """Rows for one built set, measured from the WAV files as written."""
    return measure_files([(b.slot, b) for b in built], out_dir)


def failures(results):
    """['set/slot: problem; problem', ...] over all sets."""
    return ["%s/%s: %s" % (name, r.slot, "; ".join(r.problems))
            for name, rows in results.items() for r in rows if r.problems]


def render(results):
    """Markdown. `results` maps set name to its Rows."""
    total = sum(len(rows) for rows in results.values())
    bad = failures(results)
    lines = ["# Sound sets: loudness report", "",
             "%d of %d files meet their targets." % (total - len(bad), total), "",
             "Targets: cat moments %.0f LUFS short-term (+-%.1f LU), ticks %.0f (+-%.1f LU); true peak "
             "at or under %.0f dBTP; length up to 1.5 s (sleep 3 s, ticks 0.4 s). Short-term is the "
             "loudest 400 ms block. \"Limiter\" is the deepest gain reduction the peak limiter applied."
             % (TARGETS["cat"][0], TARGETS["cat"][1], TARGETS["tick"][0], TARGETS["tick"][1],
                TP_CEILING), ""]
    for name, rows in results.items():
        passed = sum(1 for r in rows if not r.problems)
        lines += ["## %s: %d of %d pass" % (name, passed, len(rows)), "",
                  "| slot | kind | LUFS-S | RMS dBFS | TP dBTP | length s | limiter dB | result |",
                  "|---|---|---|---|---|---|---|---|"]
        for r in rows:
            res = "pass" if not r.problems else "FAIL: " + "; ".join(r.problems)
            lines.append("| %s | %s | %.1f | %.1f | %.2f | %.2f | %.1f | %s |"
                         % (r.slot, r.kind, r.lufs, r.rms_db, r.tp_db, r.seconds, r.limit_db, res))
        lines.append("")
    return "\n".join(lines)


def render_waiting(moments):
    """A closing paragraph for the round-two report: moments still none that have no alternative.
    Nothing is invented for them; they are settled in chat."""
    if not moments:
        return ""
    return ("\nNo round-two alternative for: %s. Nothing in the candidates fits these moments; settle them in "
            "chat (a made-in-code sound, or wait for the real recordings).\n" % ", ".join(moments))
