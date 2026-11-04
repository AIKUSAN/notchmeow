"""design/sounds/sources.json: where every shipped clip comes from, and what the build may do with it.

One entry per recorded clip of Your mix, keyed by the recipe's source name ('love/fs-64017-Department64.mp3').
An entry says who made the clip and where its page is, the licence as read on that page (when, and by whom),
the original file the owner downloaded (its name, size and SHA-256) or, when there is none, the Freesound HQ
preview of it (`hq_preview`: an MP3, pinned the same way, with its decoded rate and length; it is never
presented as the original's figures), the offset between that audio and the preview clip the recipes were written
against, and the window each slot takes from it.

The build from the originals refuses a source that is not here, whose licence is not a verified CC0, whose
original is not pinned, or whose windows were not checked (spec section 5: "the build refuses any source
without a verified CC0 entry"). Standard library only; nothing here touches audio.
"""
from __future__ import annotations

import html
import json
import os
import re
from collections import OrderedDict

import recipe

SOURCES_NAME = "sources.json"
CC0 = "CC0-1.0"
CC0_URLS = ("http://creativecommons.org/publicdomain/zero/1.0/", "https://creativecommons.org/publicdomain/zero/1.0/")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
FS_SOURCE = re.compile(r"^[a-z0-9]+/fs-(\d+)-(.+)\.[a-z0-9]+$")
EXTENSIONS = {"wave": (".wav",), "ogg vorbis": (".ogg",), "flac": (".flac",), "aiff": (".aif", ".aiff"),
              "mp3": (".mp3",), "m4a": (".m4a",)}       # the Type a Freesound page states, by extension


class SourcesError(ValueError):
    pass


def freesound_id(source):
    """'love/fs-64017-Department64.mp3' -> '64017'; None for a source that is not a Freesound clip."""
    found = FS_SOURCE.match(source)
    return found.group(1) if found else None


def freesound_author(source):
    found = FS_SOURCE.match(source)
    return found.group(2) if found else None


def page_url(source):
    """The clip's own Freesound page, which the licence re-check reads."""
    fid = freesound_id(source)
    return None if fid is None else "https://freesound.org/people/%s/sounds/%s/" % (freesound_author(source), fid)


def parse_duration(text):
    """'1:00.103' -> 60.103, '0:00.643' -> 0.643 (a Freesound page's Duration)."""
    found = re.match(r"^(\d+):(\d{2}(?:\.\d+)?)$", text.strip())
    if not found:
        raise SourcesError("duration %r is not m:ss.mmm" % text)
    return int(found.group(1)) * 60 + float(found.group(2))


def parse_size(text):
    """'110.9 KB' -> 113562 (bytes; Freesound's KB and MB are 1024-based)."""
    found = re.match(r"^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB)$", text.strip())
    if not found:
        raise SourcesError("size %r is not '<number> KB' or '<number> MB'" % text)
    return int(round(float(found.group(1)) * {"B": 1, "KB": 1024, "MB": 1024 ** 2, "GB": 1024 ** 3}[found.group(2)]))


def load(path):
    """sources.json as a dict, checked for shape (see `problems`). Raises SourcesError."""
    with open(path, encoding="utf-8") as f:
        try:
            doc = json.load(f, object_pairs_hook=OrderedDict)
        except ValueError as e:
            raise SourcesError("%s: not valid JSON (%s)" % (path, e))
    bad = problems(doc)
    if bad:
        raise SourcesError("%s: %s" % (path, "; ".join(bad)))
    return doc


def save(path, doc):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")


def is_verified(e):
    """A verified CC0: the licence read on the clip's own page, with the page's CC0 link, the date it was
    read and who read it."""
    return (e.get("licence") == CC0 and e.get("licence_url") in CC0_URLS
            and isinstance(e.get("checked_on"), str) and bool(DATE.match(e["checked_on"]))
            and isinstance(e.get("checked_by"), str) and bool(e["checked_by"].strip()))


def _is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def audio_kind(entry):
    """What the build decodes for a clip: 'original' (a WAV the owner downloaded) beats 'hq-preview' (the Freesound
    HQ preview MP3); None when neither is pinned."""
    return "original" if entry.get("original") else "hq-preview" if entry.get("hq_preview") else None


def problems(doc):
    """What is wrong with the shape of a sources.json document, as short sentences. Empty means fine.
    Not about completeness: an entry may still wait for its re-check or its download."""
    if not isinstance(doc, dict) or not isinstance(doc.get("sources"), dict):
        return ['must be an object with a "sources" object']
    out = []
    for source, e in doc["sources"].items():
        where = source
        if not isinstance(e, dict):
            out.append("%s: must be an object" % where)
            continue
        try:
            recipe._check_source(source, where)         # an excluded clip is never a source
        except recipe.RecipeError as err:
            out.append(str(err))
            continue
        if source.startswith("synth:"):
            out.append("%s: a made-in-code sound has no source entry" % where)
            continue
        fid = freesound_id(source)
        if fid is not None and e.get("page") != page_url(source):
            out.append("%s: page must be %s" % (where, page_url(source)))
        if fid is None and not str(e.get("page", "")).startswith("https://"):
            out.append("%s: page must be the clip's own https page" % where)
        want_author = freesound_author(source)
        if (e.get("author") != want_author) if want_author else not str(e.get("author", "")).strip():
            out.append("%s: author must be %s" % (where, want_author or "the maker's name"))
        if not isinstance(e.get("title"), str) or not e["title"].strip():
            out.append("%s: title is missing" % where)
        stated = e.get("stated")
        if not isinstance(stated, dict) or not {"type", "duration", "size"} <= set(stated):
            out.append("%s: stated needs type, duration and size as the page shows them" % where)
        else:
            try:
                parse_duration(stated["duration"])
                parse_size(stated["size"])
            except SourcesError as err:
                out.append("%s: %s" % (where, err))
        if any(e.get(k) is not None for k in ("licence", "licence_url", "checked_on", "checked_by")) and not is_verified(e):
            out.append("%s: a licence entry needs licence %s, the page's CC0 link, checked_on (YYYY-MM-DD) and "
                       "checked_by, or all four left null" % (where, CC0))
        orig = e.get("original")
        if orig is not None and not (isinstance(orig, dict) and SHA256.match(str(orig.get("sha256", "")))
                                     and isinstance(orig.get("file"), str) and orig["file"]
                                     and isinstance(orig.get("bytes"), int) and orig["bytes"] > 0):
            out.append("%s: original needs file, bytes and a lower-case sha256" % where)
        hq = e.get("hq_preview")
        if hq is not None and not (isinstance(hq, dict) and isinstance(hq.get("file"), str) and hq["file"]
                                   and _is_int(hq.get("bytes")) and hq["bytes"] > 0
                                   and SHA256.match(str(hq.get("sha256", ""))) and hq.get("format") == "MP3"
                                   and _is_int(hq.get("sample_rate_hz")) and hq["sample_rate_hz"] > 0
                                   and isinstance(hq.get("seconds"), (int, float)) and not isinstance(hq["seconds"], bool)
                                   and hq["seconds"] > 0):
            out.append("%s: hq_preview needs file, bytes, a lower-case sha256, format MP3, sample_rate_hz and seconds" % where)
        if e.get("offset_s") is not None and (isinstance(e["offset_s"], bool)
                                              or not isinstance(e["offset_s"], (int, float))):
            out.append("%s: offset_s must be a number" % where)
        if not isinstance(e.get("windows", {}), dict):
            out.append("%s: windows must be an object" % where)
        elif not all(isinstance(w, dict) and all(_is_num(w.get(k)) for k in ("start", "end", "r"))
                     and isinstance(w.get("ok"), bool) for ws in e.get("windows", {}).values()
                     for w in (ws if isinstance(ws, list) else [None])):
            out.append("%s: each window needs a numeric start, end and r and a true or false ok" % where)
    return out


def clip_uses(entry):
    """The recorded windows a recipe entry builds from, in order: [(source, start, end)], start and end in seconds on
    the source clip or None. An ordinary entry has one (its source and the window its recipe gives); a made-in-code
    entry has none. The hairball's entry (plan c1c-hairball) is a "placed" sound: its recorded part is
    `entry.segments`, a list of dicts with `source`, `start` and `end` (seconds on the clip) among others, and its
    made-in-code part is `entry.synth_layers`; the entry's own `start` and `end` cut the finished timeline and are not
    a clip window. This function and `originals.with_windows` are the only code that reads that shape: if c1c's
    final recipe names it differently, change those two."""
    segments = getattr(entry, "segments", None) or ()
    if segments:
        return [(seg["source"], seg["start"], seg["end"]) for seg in segments]
    if entry.source.startswith("synth:") or entry.source == "placed":
        return []
    return [(entry.source, entry.start, entry.end)]


def file_sources(rec):
    """OrderedDict source -> [slots that build from it], in slot order, for the recorded clips of a SetRecipe
    (Your mix); a slot is listed once per source however many windows it takes (the hairball takes three of one
    clip). The made-in-code sounds have no source."""
    out = OrderedDict()
    for slot, e in rec.entries.items():
        for source, _start, _end in clip_uses(e):
            if slot not in out.setdefault(source, []):
                out[source].append(slot)
    return out


def slot_windows(rec, slot, source):
    """[(start, end)] the recipe gives for each window `slot` takes from `source`, in order (None for a window the
    build's automatic trim chooses)."""
    return [(a, b) for s, a, b in clip_uses(rec.entries[slot]) if s == source]


def _say(count_sentence, names, limit=4):
    """'3 sources have no verified CC0 entry: a, b, c' (at most `limit` names, then 'and N more'); [] for none."""
    names = list(names)
    if not names:
        return []
    shown = ", ".join(names[:limit]) + (" and %d more" % (len(names) - limit) if len(names) > limit else "")
    return ["%d %s: %s" % (len(names), count_sentence, shown)]


def licence_problems(doc, rec):
    """The recorded clips of `rec` that may not ship: not in sources.json, or without a verified CC0."""
    uses = file_sources(rec)
    absent = [s for s in uses if s not in doc["sources"]]
    unverified = [s for s in uses if s in doc["sources"] and not is_verified(doc["sources"][s])]
    return (_say("clips are not in %s" % SOURCES_NAME, absent)
            + _say("clips have no verified CC0 entry (licence, the page's link, date and checker)", unverified))


def pin_problems(doc, rec):
    """A clip is pinned when it has an original or an HQ preview (the word 'originals' is generic)."""
    return _say("originals are not pinned (file, size and SHA-256)",
                [s for s in file_sources(rec) if not audio_kind(doc["sources"].get(s) or {})])


def window_problems(doc, rec):
    """Each slot's window must be checked against the original (the align step) and must still be the recipe's
    own window when the recipe gives one."""
    no_offset, unchecked, differ, stale = [], [], [], []
    for source, slots in file_sources(rec).items():
        e = doc["sources"].get(source) or {}
        if e.get("offset_s") is None:
            no_offset.append(source)
        for slot in slots:
            want = slot_windows(rec, slot, source)
            got = (e.get("windows") or {}).get(slot) or []
            names = [slot if len(want) == 1 else "%s %d of %d" % (slot, n + 1, len(want)) for n in range(len(want))]
            if len(got) != len(want):
                unchecked += names
                continue
            for name, (start, end), w in zip(names, want, got):
                if w.get("ok") is not True:
                    differ.append("%s (r=%s)" % (name, w.get("r")))
                if start is not None and end is not None and (
                        abs(w["start"] - start) > 1e-6 or abs(w["end"] - end) > 1e-6):
                    stale.append(name)
    return (_say("clips have no measured offset between preview and original", no_offset)
            + _say("windows are not pinned and checked", unchecked)
            + _say("windows do not hold the same sound as the preview", differ)
            + _say("windows changed in the recipe since they were pinned", stale))


def gate(doc, rec):
    """Everything the build from the originals needs before it writes a file. Empty means go."""
    return licence_problems(doc, rec) + pin_problems(doc, rec) + window_problems(doc, rec)


STATED_LABELS = OrderedDict([("Type", "type"), ("Duration", "duration"), ("File size", "size"), ("Sample rate", "sample_rate"),
                             ("Bit depth", "bit_depth"), ("Bitrate", "bitrate"), ("Channels", "channels")])


def parse_page(text):
    """What a Freesound sound page says, read from its HTML: title and author (its <meta> tags), the licence link and
    its name, and the Sound information block (type, duration, size, sample rate, bit depth or bitrate, channels) as
    printed. A value the page does not show is None (stated: empty). More than one distinct creativecommons.org
    link on the page leaves the licence None: the page is ambiguous."""
    def meta(prop):
        found = re.search(r'<meta\s+property="%s"\s+content="([^"]*)"' % re.escape(prop), text)
        return html.unescape(found.group(1)).strip() if found else None
    links = re.findall(r'<a\s[^>]*href="(https?://creativecommons\.org/[^"]*)"[^>]*>\s*([^<]*?)\s*</a>', text)
    one = links[0] if len({url for url, _ in links}) == 1 else (None, None)
    stated = OrderedDict()
    for label, value in re.findall(r'<p class="text-grey no-margins">\s*([^<]+?)\s*</p>\s*<p class="no-margins">\s*([^<]*?)\s*</p>', text):
        if label in STATED_LABELS and STATED_LABELS[label] not in stated:
            stated[STATED_LABELS[label]] = " ".join(html.unescape(value).split())      # the page puts a no-break space before KB
    return {"title": meta("og:audio:title"), "author": meta("og:audio:artist"),
            "licence_name": one[1] and html.unescape(one[1]), "licence_url": one[0], "stated": stated}


def check_page(entry, page):
    """What stops a page from vouching for its clip: not the maker the entry names, not a plain Creative Commons 0
    licence with the CC0 link, or no Type, Duration and File size to check the download against. Empty means go."""
    out = []
    if page["author"] != entry["author"]:
        out.append("the page's maker is %r, not %r" % (page["author"], entry["author"]))
    if page["licence_name"] != "Creative Commons 0":
        out.append("the page's licence is %r, not 'Creative Commons 0'" % page["licence_name"])
    if page["licence_url"] not in CC0_URLS:
        out.append("the page's licence link is %r, not a CC0 link" % page["licence_url"])
    for key in ("type", "duration", "size"):
        if key not in page["stated"]:
            out.append("the page shows no %s in its Sound information" % key)
    return out


def record_check(entry, page, by, on):
    """Write what the page vouched for into the entry: the licence, its link, who read it and when, the title as the
    page shows it and the page's own Sound information. Returns warnings: what the page says now that differs from
    what the entry had (the caller has run check_page first)."""
    changed = ["%s was %r, the page says %r" % (k, entry["stated"].get(k), v)
               for k, v in page["stated"].items() if entry["stated"].get(k) != v]
    changed += ["%s was %r, the page shows none" % (k, v) for k, v in entry["stated"].items() if k not in page["stated"]]
    entry.update(licence=CC0, licence_url=page["licence_url"], checked_on=on, checked_by=by, stated=OrderedDict(page["stated"]))
    if page["title"]:
        entry["title"] = page["title"]
    return changed


def find_original(folder, source, entry):
    """The downloaded original of a source in `folder`: the pinned file name if there is one, otherwise the
    one file Freesound named '<id>__<user>__<name>.<ext>'. Raises SourcesError when there is none or two."""
    pinned = (entry.get("original") or {}).get("file")
    if pinned:
        path = os.path.join(folder, pinned)
        if not os.path.isfile(path):
            raise SourcesError("%s: %s is not in %s" % (source, pinned, folder))
        return path
    fid = freesound_id(source)
    if fid is None:
        raise SourcesError("%s: no way to name its original; pin it by hand" % source)
    found = sorted(n for n in os.listdir(folder) if n.startswith(fid + "__") and not n.startswith("."))
    if not found:
        raise SourcesError("%s: no file named %s__* in %s" % (source, fid, folder))
    if len(found) > 1:
        raise SourcesError("%s: more than one file for it in %s: %s" % (source, folder, ", ".join(found)))
    return os.path.join(folder, found[0])


def find_hq_preview(folder, source, entry):
    """The Freesound HQ preview of a source in `folder`: the pinned file name if there is one, otherwise the one
    file named '<id>_*-hq.mp3'. Raises SourcesError when there is none or two."""
    pinned = (entry.get("hq_preview") or {}).get("file")
    if pinned:
        path = os.path.join(folder, pinned)
        if not os.path.isfile(path):
            raise SourcesError("%s: %s is not in %s" % (source, pinned, folder))
        return path
    fid = freesound_id(source)
    if fid is None:
        raise SourcesError("%s: no way to name its HQ preview; pin it by hand" % source)
    found = sorted(n for n in os.listdir(folder) if n.startswith(fid + "_") and n.endswith("-hq.mp3") and not n.startswith("."))
    if not found:
        raise SourcesError("%s: no file named %s_*-hq.mp3 in %s" % (source, fid, folder))
    if len(found) > 1:
        raise SourcesError("%s: more than one HQ preview for it in %s: %s" % (source, folder, ", ".join(found)))
    return os.path.join(folder, found[0])


def type_matches(entry, path):
    """The file's extension is the Type the page states (a preview MP3 saved by mistake is not a Wave)."""
    said = entry["stated"]["type"].lower()
    ext = os.path.splitext(path)[1].lower()
    for key, exts in EXTENSIONS.items():
        if said.startswith(key):
            return ext in exts
    return True


def _made_by(entry):
    """What makes the made-in-code part of an entry: 'yawn' for synth:yawn, the layer names of a placed sound, or ''."""
    if entry.source.startswith("synth:"):
        return entry.source[6:]
    return ", ".join(layer["name"] for layer in getattr(entry, "synth_layers", None) or ())


BUILT_FROM_HQ = "Freesound HQ preview (MP3) of the CC0 original"


def _cell(text):
    return str(text).replace("|", "\\|")


def credits_text(doc, rec):
    """docs/SOUND-CREDITS.md: every shipped clip, written from sources.json so the two cannot disagree."""
    lines = ["# Sound credits", "",
             "NotchMeow's sounds are built from clips released under Creative Commons Zero (CC0 1.0), which asks "
             "for no credit. Each clip is credited anyway, because its maker deserves it (Breviceps asks for it). "
             "The mixes built from them, and the sounds made in code, are NotchMeow's own and stay under "
             "`LICENSE-ASSETS.md`.", "",
             "A clip is built from the Freesound HQ preview (MP3) of its CC0 original; where a WAV original is ever "
             "added, the table says so. The licence belongs to the sound and covers any rendition of it. "
             "The last column is the SHA-256 of the file that was used.", "",
             "This file is written from `design/sounds/sources.json` by `python3 tools/sounds/originals.py credits`. "
             "Do not edit it by hand: `tests/test_sound_shipped.py` fails when the two differ.", "",
             "| Slot | Title | Author | Page | Licence | Checked on | Built from | SHA-256 of the audio used |",
             "|---|---|---|---|---|---|---|---|"]
    for slot, ent in rec.entries.items():
        for source in OrderedDict((s, None) for s, _a, _b in clip_uses(ent)):
            e = doc["sources"][source]
            hq = audio_kind(e) == "hq-preview"
            lines.append("| %s | %s | %s | <%s> | CC0 1.0 | %s | %s | `%s` |" % (
                slot, _cell(e["title"]), _cell(e["author"]), e["page"], e["checked_on"],
                BUILT_FROM_HQ if hq else "original WAV", e["hq_preview" if hq else "original"]["sha256"]))
    made = [("%s (%s)" % (s, _made_by(ent))) for s, ent in rec.entries.items() if not clip_uses(ent)]
    partly = [s for s, ent in rec.entries.items() if clip_uses(ent) and _made_by(ent)]
    lines += ["", "Made in code, with no source clip: %s." % ", ".join(made)]
    if partly:
        lines += ["", "Partly made in code, the recorded part credited above: %s." % ", ".join(partly)]
    lines.append("")
    return "\n".join(lines)


def download_list_text(doc, rec, folder):
    """The list the owner works from: every original to get, with its page and what the page says about it."""
    uses = file_sources(rec)
    freesound = [s for s in uses if freesound_id(s) is not None]
    direct = [s for s in uses if freesound_id(s) is None]
    lines = ["# Originals to download", "",
             "Save every file into `%s` and leave its name as the site gave it (Freesound names it "
             "`<id>__<user>__<name>.<ext>`). %d clips." % (folder, len(uses)), ""]

    def row(source):
        e = doc["sources"][source]
        st = e["stated"]
        said = ", ".join(str(st[k]) for k in ("type", "duration", "size", "sample_rate", "bit_depth", "channels")
                         if st.get(k))
        name = ("the file name starts with `%s__`" % freesound_id(source) if freesound_id(source)
                else "save it as `%s`" % e.get("download", {}).get("file", "(name it in sources.json)"))
        return ["- [ ] **%s** by %s, for %s" % (_cell(e["title"]), e["author"], ", ".join(uses[source])),
                "  - page: %s" % e["page"],
                "  - the page says: %s" % said,
                "  - %s" % name]

    lines += ["## Needs your Freesound sign-in: download these yourself (%d)" % len(freesound), ""]
    for s in freesound:
        lines += row(s)
    lines += ["", "## Direct links, with your OK before anything is downloaded (%d)" % len(direct), ""]
    for s in direct:
        lines += row(s) + ["  - direct link: %s" % doc["sources"][s].get("download", {}).get("url", "(missing)")]
    if not direct:
        lines += ["None: Your mix uses no BigSoundBank clip."]
    lines.append("")
    return "\n".join(lines)
