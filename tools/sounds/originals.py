#!/usr/bin/env python3
"""Stage 2's steps on the Freesound originals: the download list, pinning the downloaded files, aligning
them with the preview clips, and the credits file. build_pack.py builds from the result.

  originals.py list      write the list of originals to download (git-ignored folder) and print it
  originals.py pin       check every downloaded original (type, size, length, decodes) and pin its SHA-256; a clip with
                         no original is pinned from its Freesound HQ preview (--hq-previews DIR) instead
  originals.py align     measure each original's offset against its preview and check every window
  originals.py credits   write docs/SOUND-CREDITS.md from sources.json
  originals.py page SRC  read a clip's own Freesound page (its HTML on stdin) and record its licence for source SRC:
                           curl -sL "<page>" | python3 tools/sounds/originals.py page love/fs-64017-Department64.mp3 --by "..."
                         Only a page that says Creative Commons 0, with the CC0 link and the right maker, is recorded.

All of them read design/sounds/sources.json (--sources) and Your mix (design/sounds/sets/mine.json).
`pin` and `align` write their results into sources.json. Nothing here downloads anything or asks for a login.
An HQ preview is the MP3 Freesound serves for a clip (`<id>_<n>-hq.mp3`): the same CC0 sound at better quality
than the candidates folder's previews. An original WAV, where there is one, wins over it.
Needs Python 3 and macOS afconvert; the preview clips are only needed by `align`.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import os
import sys
from collections import namedtuple

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))

import align  # noqa: E402
import audio_io  # noqa: E402
import dsp  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402
import sources  # noqa: E402
from dsp import SR  # noqa: E402

SOURCES_PATH = os.path.join(ROOT, "design", "sounds", sources.SOURCES_NAME)
CREDITS_PATH = os.path.join(ROOT, "docs", "SOUND-CREDITS.md")
HQ_PADDING_S = 0.2             # an HQ preview may run up to 0.2 s longer than its page says (encoder padding)
SIZE_TOLERANCE = 0.10          # a downloaded file within 10 % of the size its page states
LENGTH_TOLERANCE_S = 0.005     # and as long as its page says, to 5 ms


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def load_mine(recipes_dir):
    """Your mix as a SetRecipe (one entry per slot), from the recipes folder."""
    sets = recipe.load_recipes(recipes_dir)
    round2 = recipe.load_round2(os.path.join(recipes_dir, recipe.ROUND2_NAME + ".json"), sets)
    return recipe.load_mine(os.path.join(recipes_dir, recipe.MINE_NAME + ".json"), sets, round2)


def pinned_audio(entry, folder, hq_folder):
    """(pin record, path, label) of the audio a clip is built from: its pinned original in `folder`, else its pinned HQ
    preview in `hq_folder`; None when neither is pinned."""
    kind = sources.audio_kind(entry)
    if kind is None:
        return None
    rec, where, label = (entry["original"], folder, "original") if kind == "original" else (entry["hq_preview"], hq_folder, "HQ preview")
    return rec, os.path.join(str(where or ""), rec["file"]), label


class OriginalsLoader:
    """Decodes the pinned originals (or, for a clip with none, its pinned HQ previews) and moves each one into
    preview time by its measured offset, so a recipe window means the same sound it meant on the preview. `load` has
    the loader interface of pipeline.build_set."""

    def __init__(self, folder, doc, hq_folder=None):
        self.folder, self.doc, self.hq_folder, self._clips = str(folder), doc, hq_folder, {}

    def load(self, source):
        if source not in self._clips:
            e = self.doc["sources"][source]
            pinned = pinned_audio(e, self.folder, self.hq_folder)
            if pinned is None:
                raise pipeline.SourceError("%s: nothing pinned in sources.json (no original, no HQ preview)" % source)
            record, path, label = pinned
            if not os.path.isfile(path):
                raise pipeline.SourceError("%s: the %s %s is not in %s" % (source, label, record["file"], os.path.dirname(path)))
            if sha256_file(path) != record["sha256"]:
                raise pipeline.SourceError("%s: %s is not the file pinned in sources.json (its SHA-256 differs)"
                                           % (source, path))
            self._clips[source] = align.shift_clip(audio_io.decode_clip(path), int(round(e["offset_s"] * SR)))
        return self._clips[source]


def with_windows(entry, windows):
    """`entry` with the window of each of its clip uses (`sources.clip_uses` order) replaced by the matching
    (start, end) of `windows`. Like `clip_uses`, one of the two places that know the shape of an entry."""
    segments = getattr(entry, "segments", None) or ()
    if segments:
        return entry._replace(segments=[dict(seg, start=a, end=b) for seg, (a, b) in zip(segments, windows)])
    return entry._replace(start=windows[0][0], end=windows[0][1])


def pinned_recipe(rec, doc):
    """`rec` with every recorded window written out as the window pinned (and checked) in sources.json, so the
    originals are cut exactly where the previews were. Made-in-code entries are left as they are."""
    entries = type(rec.entries)()
    for slot, e in rec.entries.items():
        taken, pinned = {}, []
        for source, _start, _end in sources.clip_uses(e):
            n = taken[source] = taken.get(source, -1) + 1
            w = doc["sources"][source]["windows"][slot][n]
            pinned.append((w["start"], w["end"]))
        entries[slot] = with_windows(e, pinned) if pinned else e
    return rec._replace(entries=entries)


def check_original(source, entry, folder):
    """Look at a downloaded original: returns (problems, path, bytes, seconds). Nothing is written."""
    try:
        path = sources.find_original(folder, source, entry)
    except sources.SourcesError as e:
        return [str(e)], None, 0, 0.0
    out, size = [], os.path.getsize(path)
    if not sources.type_matches(entry, path):
        out.append("%s is not a %s file" % (os.path.basename(path), entry["stated"]["type"]))
    said = sources.parse_size(entry["stated"]["size"])
    if abs(size - said) > SIZE_TOLERANCE * said:
        out.append("%s is %d bytes, its page says %s" % (os.path.basename(path), size, entry["stated"]["size"]))
    seconds = 0.0
    try:
        seconds = len(audio_io.decode_clip(path)) / float(SR)
    except Exception as e:                      # afconvert refuses it: the message says which file
        out.append("afconvert cannot read %s (%s)" % (os.path.basename(path), str(e).strip()[:120]))
        return out, path, size, seconds
    want = sources.parse_duration(entry["stated"]["duration"])
    if abs(seconds - want) > LENGTH_TOLERANCE_S:
        out.append("%s lasts %.3f s, its page says %s" % (os.path.basename(path), seconds, entry["stated"]["duration"]))
    return out, path, size, seconds


def mpeg_sample_rate(path):
    """The sample rate in the first frame header of an MP3 (after an ID3v2 tag and zero padding), read by hand.
    Raises ValueError unless the file starts with an MPEG audio layer III frame."""
    with open(path, "rb") as f:
        head = f.read(10)
        if head[:3] == b"ID3" and len(head) == 10:
            f.seek(10 + ((head[6] & 0x7F) << 21 | (head[7] & 0x7F) << 14 | (head[8] & 0x7F) << 7 | (head[9] & 0x7F)))
        else:
            f.seek(0)
        frame = f.read(4096)
    frame = frame.lstrip(b"\x00")
    if len(frame) < 4:
        raise ValueError("%s: no MPEG audio frame" % os.path.basename(path))
    word = int.from_bytes(frame[:4], "big")
    version, layer, bitrate, rate = (word >> 19) & 3, (word >> 17) & 3, (word >> 12) & 15, (word >> 10) & 3
    if word >> 21 != 0x7FF or version == 1 or layer != 1 or bitrate in (0, 15) or rate == 3:
        raise ValueError("%s does not start with an MPEG audio layer III frame" % os.path.basename(path))
    return {3: (44100, 48000, 32000), 2: (22050, 24000, 16000), 0: (11025, 12000, 8000)}[version][rate]


def check_hq_preview(source, entry, folder):
    """Look at a Freesound HQ preview: returns (problems, path, bytes, seconds, sample_rate_hz). An .mp3 that starts with
    an MPEG layer III frame, that afconvert decodes, and that lasts what the page says (to 5 ms short, 0.2 s long:
    the encoder pads it). Its size is not compared with the page's, an MP3 being much smaller than the WAV.
    Nothing is written."""
    try:
        path = sources.find_hq_preview(folder, source, entry)
    except sources.SourcesError as e:
        return [str(e)], None, 0, 0.0, 0
    name, out, size, seconds, rate = os.path.basename(path), [], os.path.getsize(path), 0.0, 0
    if os.path.splitext(path)[1].lower() != ".mp3":
        return ["%s is not an .mp3 file" % name], path, size, seconds, rate
    try:
        rate = mpeg_sample_rate(path)
    except ValueError:
        return ["%s is not an MP3 (layer III) file" % name], path, size, seconds, rate
    try:
        seconds = len(audio_io.decode_clip(path)) / float(SR)
    except Exception as e:                      # afconvert refuses it: the message says which file
        return ["afconvert cannot read %s (%s)" % (name, str(e).strip()[:120])], path, size, seconds, rate
    want = sources.parse_duration(entry["stated"]["duration"])
    if not want - LENGTH_TOLERANCE_S <= seconds <= want + HQ_PADDING_S:
        out.append("%s lasts %.3f s, its page says %s" % (name, seconds, entry["stated"]["duration"]))
    return out, path, size, seconds, rate


def _has_original(folder, source, entry):
    """True when a WAV original is pinned for the clip or a file Freesound named for it sits in `folder`."""
    if (entry.get("original") or {}).get("file"):
        return True
    if folder is None or not os.path.isdir(folder):
        return False
    try:
        return bool(sources.find_original(folder, source, entry))
    except sources.SourcesError as e:           # two files count: pinning the original reports the doubt
        return "more than one" in str(e)


def _new_pin(entry, key, record):
    """Write a new audio record and forget the alignment of the old one: align must be run again."""
    entry[key], entry["offset_s"], entry["windows"] = record, None, {}


def _pin_hq(source, entry, hq_folder):
    bad, path, size, seconds, rate = check_hq_preview(source, entry, hq_folder)
    if not bad:
        digest, old = sha256_file(path), entry.get("hq_preview")
        if old and old["sha256"] != digest:
            bad = ["%s differs from the file pinned earlier; if the new one is right, set its hq_preview to null "
                   "in sources.json and pin again" % os.path.basename(path)]
        elif not old:
            _new_pin(entry, "hq_preview", {"file": os.path.basename(path), "bytes": size, "sha256": digest, "format": "MP3",
                                           "sample_rate_hz": rate, "seconds": round(seconds, 6)})
    return bad


def pin(doc, rec, folder, hq_folder=None):
    """Check every clip of `rec` and pin it in `doc`: its WAV original in `folder` (file, bytes, SHA-256) when there is
    one, otherwise its Freesound HQ preview in `hq_folder` (file, bytes, SHA-256, format, rate, length). A file that
    differs from an earlier pin is a problem, never overwritten. `folder` may be missing when the HQ previews are
    there. Returns the problems."""
    problems, have_hq = [], hq_folder is not None and os.path.isdir(hq_folder)
    for source in sources.file_sources(rec):
        entry = doc["sources"][source]
        if have_hq and not _has_original(folder, source, entry):
            bad = _pin_hq(source, entry, hq_folder)
        elif folder is None or not os.path.isdir(folder):
            bad = ["the originals folder %s does not exist" % folder]
        else:
            bad, path, size, _ = check_original(source, entry, folder)
            if not bad and path is not None:
                digest = sha256_file(path)
                old = entry.get("original")
                if old and old["sha256"] != digest:
                    bad = ["%s differs from the file pinned earlier; if the new one is right, set its original to null "
                           "in sources.json and pin again" % os.path.basename(path)]
                elif not old:
                    _new_pin(entry, "original", {"file": os.path.basename(path), "bytes": size, "sha256": digest})
        problems += ["%s: %s" % (source, b) for b in bad]
    return problems


Row = namedtuple("Row", "slot source offset_ms r preview_s original_s ok")


def use_spans(rec, slot, source, preview):
    """[(a, b)] sample spans of `preview` for each window `slot` takes from `source`: the window the recipe gives,
    or, for an entry with none, the span the build's automatic trim chooses on the preview."""
    entry = rec.entries[slot]
    if getattr(entry, "segments", None):
        return [dsp.seconds_span(len(preview), a, b) for a, b in sources.slot_windows(rec, slot, source)]
    return [pipeline.source_span(entry, preview, entry.pitch_st)]


def align_all(doc, rec, folder, previews, hq_folder=None):
    """For every recorded clip of `rec`: measure the offset between its pinned audio (the original, else the HQ preview
    in `hq_folder`) and its low-quality preview, shift the
    original into preview time and check every window of every slot (align.py's rule). Writes offset_s and windows
    into `doc` (windows[slot] is a list, one per window the slot takes from the clip); returns one Row per window.
    `previews` is a loader of the preview clips."""
    rows = []
    for source, slots in sources.file_sources(rec).items():
        entry = doc["sources"][source]
        preview = previews.load(source)
        original = audio_io.decode_clip(pinned_audio(entry, folder, hq_folder)[1])
        spans = {s: use_spans(rec, s, source, preview) for s in slots}
        offset, _ = align.measure_offset(preview, original, *spans[slots[0]][0])
        moved = align.shift_clip(original, offset)
        entry["offset_s"] = round(offset / float(SR), 6)
        entry["windows"] = {}
        for slot in slots:
            entry["windows"][slot] = []
            for n, (a, b) in enumerate(spans[slot]):
                v = align.window_verdict(preview, moved, a, b)
                entry["windows"][slot].append({"start": round(a / float(SR), 6), "end": round(b / float(SR), 6),
                                               "r": v.r, "ok": bool(v.ok)})
                name = slot if len(spans[slot]) == 1 else "%s %d of %d" % (slot, n + 1, len(spans[slot]))
                rows.append(Row(name, source, offset * 1000.0 / SR, v.r,
                                len(preview) / float(SR), len(original) / float(SR), bool(v.ok)))
    return rows


def render_rows(rows):
    lines = ["| slot | source | offset ms | r | preview s | original s | window |", "|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append("| %s | %s | %+.2f | %.3f | %.3f | %.3f | %s |" % (
            r.slot, r.source, r.offset_ms, r.r, r.preview_s, r.original_s, "same sound" if r.ok else "FAILS"))
    return "\n".join(lines)


def record_page(args, doc, rec):
    """`page`: the HTML of one clip's own page on stdin. Records the licence only when the page vouches for it."""
    if args.source not in sources.file_sources(rec):
        print("page: %r is not a recorded clip of Your mix" % args.source, file=sys.stderr)
        return 2
    if not args.by or not args.by.strip():
        print("page: say who read the page with --by", file=sys.stderr)
        return 2
    on = args.date or datetime.date.today().isoformat()
    if not sources.DATE.match(on):
        print("page: --date must be YYYY-MM-DD", file=sys.stderr)
        return 2
    page = sources.parse_page(sys.stdin.read())
    entry = doc["sources"][args.source]
    bad = sources.check_page(entry, page)
    if bad:
        print("NOT RECORDED %s: %s" % (args.source, "; ".join(bad)), file=sys.stderr)
        return 1
    for warning in sources.record_check(entry, page, args.by.strip(), on):
        print("WARN %s: %s" % (args.source, warning), file=sys.stderr)
    sources.save(args.sources, doc)
    print("recorded %s: %s by %s, read on %s" % (args.source, page["licence_name"], page["author"], on))
    return 0


def _folder(explicit, name, env):
    """A git-ignored folder: the flag, $<env> (taken even before the folder exists, so `list` can name it),
    <repo>/.claude/sounds/<name>, then the same folder in the main checkout."""
    want = explicit or os.environ.get(env)
    if want:
        return os.path.abspath(want)
    import build_pack           # imported here because build_pack imports this module
    return build_pack.find_folder(None, env, name) or os.path.join(build_pack.ROOT, ".claude", "sounds", name)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=("list", "pin", "align", "credits", "page"))
    ap.add_argument("source", nargs="?", help="page: the recipe source name the page on stdin belongs to")
    ap.add_argument("--by", help="page: who read the page, for sources.json (e.g. 'licence re-check agent, Sonnet 5.5')")
    ap.add_argument("--date", help="page: the day it was read, YYYY-MM-DD (default: today)")
    ap.add_argument("--sources", default=SOURCES_PATH, help="sources.json (default: design/sounds/sources.json)")
    ap.add_argument("--recipes", default=os.path.join(ROOT, "design", "sounds", "sets"))
    ap.add_argument("--originals", help="folder of downloaded originals (default: .claude/sounds/originals)")
    ap.add_argument("--hq-previews", help="folder of Freesound HQ previews, for clips with no original (default: "
                                          ".claude/sounds/hq-previews)")
    ap.add_argument("--candidates", help="folder of preview clips (align only)")
    ap.add_argument("--credits", default=CREDITS_PATH, help="where `credits` writes (default: docs/SOUND-CREDITS.md)")
    args = ap.parse_args(argv)
    try:
        rec = load_mine(args.recipes)
        doc = sources.load(args.sources)
    except (recipe.RecipeError, sources.SourcesError, OSError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 2
    missing = [s for s in sources.file_sources(rec) if s not in doc["sources"]]
    if missing:
        print("error: not in sources.json: %s" % ", ".join(missing), file=sys.stderr)
        return 2
    folder = _folder(args.originals, "originals", "NM_SOUND_ORIGINALS")
    hq_folder = _folder(args.hq_previews, "hq-previews", "NM_SOUND_HQ_PREVIEWS")
    hq_folder = hq_folder if os.path.isdir(hq_folder) else None

    if args.command == "page":
        return record_page(args, doc, rec)
    if args.command == "list":
        text = sources.download_list_text(doc, rec, folder)
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "DOWNLOAD-LIST.md"), "w", encoding="utf-8") as f:
            f.write(text)
        print(text)
        return 0
    if args.command == "credits":
        bad = sources.licence_problems(doc, rec) + sources.pin_problems(doc, rec)
        if bad:
            print("credits: not ready: %s" % "; ".join(bad), file=sys.stderr)
            return 2
        with open(args.credits, "w", encoding="utf-8") as f:
            f.write(sources.credits_text(doc, rec))
        print("wrote %s" % args.credits)
        return 0
    if not os.path.isdir(folder) and hq_folder is None:
        print("%s: neither the originals folder %s nor an HQ previews folder exists yet" % (args.command, folder), file=sys.stderr)
        return 2
    if args.command == "pin":
        bad = pin(doc, rec, folder, hq_folder)
        sources.save(args.sources, doc)
        for line in bad:
            print("PROBLEM " + line, file=sys.stderr)
        print("pinned %d of %d clips" % (sum(1 for s in sources.file_sources(rec) if sources.audio_kind(doc["sources"][s])),
                                         len(sources.file_sources(rec))))
        return 1 if bad else 0
    not_pinned = sources.pin_problems(doc, rec)
    if not_pinned:
        print("align: pin the originals first: %s" % "; ".join(not_pinned), file=sys.stderr)
        return 2
    import build_pack
    cands = build_pack.find_candidates(args.candidates)
    if cands is None:
        print("align: the preview clips (candidates folder) were not found; pass --candidates", file=sys.stderr)
        return 2
    rows = align_all(doc, rec, folder, audio_io.AfconvertLoader(cands), hq_folder)
    sources.save(args.sources, doc)
    print(render_rows(rows))
    failed = [r for r in rows if not r.ok]
    print("%d of %d windows hold the same sound" % (len(rows) - len(failed), len(rows)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
