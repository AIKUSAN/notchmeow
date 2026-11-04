"""The slots, and loading and validating the set recipes in design/sounds/sets/.

A recipe entry says how one slot is built. `_shared.json` holds the entries every set shares (the
ticks, the made-in-code fill-ins and the hairball); each set file holds the rest. A set is complete
when the two together cover every slot, once each.
"""
from __future__ import annotations

import json
import os
import re
from collections import OrderedDict, namedtuple

from synth import GAPS, LAYERS

Slot = namedtuple("Slot", "name kind mood signature dark max_len touch")

# Spec section 1 (slots, lengths) and section 3 (moods, signature). Cat moments first.
_CAT = [("greet", "happy"), ("love", "happy"), ("annoyed", "upset"), ("dizzy", "upset"),
        ("slap", "calm"), ("finish", "happy"), ("error", "upset"), ("approval", "attention"),
        ("question", "attention"), ("proud", "happy"), ("wink", "happy"), ("yawn", "calm"),
        ("sleep", "calm"), ("gulp", "happy"), ("think", "attention"), ("search", "attention"),
        ("work", "calm"), ("rate", "upset"), ("hairball", "upset")]
_TICKS = ["approve", "peek", "open", "close", "hover", "blip", "tick", "send", "attach", "pop"]
_SIGNATURE = ("greet", "finish", "approval", "question", "error", "love")
_NO_TOUCH = ("hairball",)        # a hack has no voice to colour: no touch layer (spec section 3, "Hairball")

SLOTS = OrderedDict()
for _name, _mood in _CAT:
    SLOTS[_name] = Slot(_name, "cat", _mood, _name in _SIGNATURE, _name == "error",
                        3.0 if _name == "sleep" else 1.5, _name not in _NO_TOUCH)
for _name in _TICKS:
    SLOTS[_name] = Slot(_name, "tick", "none", False, False, 0.4, False)

SET_NAMES = ("studio", "steff", "kitten", "bestof", "tabby")
SHARED_NAME = "_shared"

# Spec section 1: never in any set. Matched against the file name (author and Freesound id).
EXCLUDED = ("qubodup", "857748", "lukey1028", "732521")
# Department64's kitten## files and Buddha Purr; the rest of that uploader's pack is CC BY.
DEPARTMENT64_OK = {"64004", "64005", "64007", "64008", "64011", "64012", "64015", "64017"}

EFFECTS = {  # type -> {param: (default or None if required, low, high)}
    "wobble": {"rate_hz": (5.0, 1.0, 12.0), "depth_st": (1.0, 0.0, 3.0)},
    "glide": {"from_st": (None, -12.0, 12.0), "to_st": (None, -12.0, 12.0)},
    "thump": {},
}
AUDIO_EXT = (".mp3", ".wav", ".m4a", ".aiff", ".caf")
FIELDS = {"slot", "source", "start", "end", "gain_db", "pitch_st", "effects", "hp_hz", "mood",
          "signature", "note", "segments", "synth_layers"}

# A placed sound (source "placed") is built on a timeline from `segments`, pieces of recorded clips
# placed at `at` seconds, then `synth_layers`, made-in-code parts (synth.LAYERS) mixed in at `at`.
# `start` and `end` then cut the finished timeline. Only _shared.json may hold one.
PLACED = "placed"
SEGMENT_FIELDS = {"source", "start", "end", "at", "level", "fade_in_ms", "fade_out_ms"}
SYNTH_LAYER_FIELDS = {"name", "seed", "at"}
MAX_AT = 10.0                  # seconds: a placed piece starts within the first ten

Entry = namedtuple("Entry", "slot source start end gain_db pitch_st effects hp_hz mood signature "
                            "note shared segments synth_layers")
SetRecipe = namedtuple("SetRecipe", "name title pitch_st entries")


class RecipeError(ValueError):
    pass


def _num(v, where, field, low, high):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise RecipeError("%s: %s must be a number" % (where, field))
    if not low <= v <= high:
        raise RecipeError("%s: %s=%r is outside %g..%g" % (where, field, v, low, high))
    return float(v)


def _effects(raw, where):
    if not isinstance(raw, list):
        raise RecipeError("%s: effects must be a list" % where)
    out = []
    for fx in raw:
        if not isinstance(fx, dict) or fx.get("type") not in EFFECTS:
            raise RecipeError("%s: unknown effect %r (known: %s)"
                              % (where, fx, ", ".join(sorted(EFFECTS))))
        spec = EFFECTS[fx["type"]]
        extra = set(fx) - set(spec) - {"type"}
        if extra:
            raise RecipeError("%s: effect %s has unknown parameters %s"
                              % (where, fx["type"], sorted(extra)))
        item = {"type": fx["type"]}
        for name, (default, low, high) in spec.items():
            if name not in fx and default is None:
                raise RecipeError("%s: effect %s needs %s" % (where, fx["type"], name))
            item[name] = _num(fx.get(name, default), where, fx["type"] + "." + name, low, high)
        out.append(item)
    return out


def _check_source(source, where):
    if not isinstance(source, str) or not source:
        raise RecipeError("%s: source is missing" % where)
    if source == PLACED:
        return
    low = source.lower()
    if source.startswith("synth:"):
        if source[6:] not in GAPS:
            raise RecipeError("%s: unknown synth recipe %r (known: %s)"
                              % (where, source, ", ".join(sorted(GAPS))))
        return
    for bad in EXCLUDED:
        if bad in low:
            raise RecipeError("%s: %s is an excluded source (spec section 1)" % (where, source))
    parts = source.split("/")
    if len(parts) != 2 or parts[0] not in SLOTS or ".." in source or not low.endswith(AUDIO_EXT):
        raise RecipeError("%s: source %r must be '<slot folder>/<file>' or 'synth:<name>'"
                          % (where, source))
    if "department64" in low:
        ident = parts[1].split("-")[1] if parts[1].startswith("fs-") else ""
        if ident not in DEPARTMENT64_OK:
            raise RecipeError("%s: %s is not a Department64 kitten## file or Buddha Purr"
                              % (where, source))


def _segments(raw, where):
    """The pieces of a placed sound, each checked like a recipe source and filled in with defaults."""
    if not isinstance(raw, list):
        raise RecipeError("%s: segments must be a list" % where)
    out = []
    for n, seg in enumerate(raw, 1):
        here = "%s segment %d" % (where, n)
        if not isinstance(seg, dict):
            raise RecipeError("%s: must be an object" % here)
        unknown = set(seg) - SEGMENT_FIELDS
        if unknown:
            raise RecipeError("%s: unknown fields %s" % (here, sorted(unknown)))
        for field in ("source", "start", "end", "at", "level"):
            if field not in seg:
                raise RecipeError("%s: needs %s" % (here, field))
        source = seg["source"]
        if isinstance(source, str) and (source == PLACED or source.startswith("synth:")):
            raise RecipeError("%s: a segment is a piece of a recorded clip, not %r" % (here, source))
        _check_source(source, here)
        start = _num(seg["start"], here, "start", 0.0, 600.0)
        end = _num(seg["end"], here, "end", 0.0, 600.0)
        if end <= start:
            raise RecipeError("%s: end must be after start" % here)
        out.append({"source": source, "start": start, "end": end,
                    "at": _num(seg["at"], here, "at", 0.0, MAX_AT),
                    "level": _num(seg["level"], here, "level", 0.001, 1.0),
                    "fade_in_ms": _num(seg.get("fade_in_ms", 0.0), here, "fade_in_ms", 0.0, 500.0),
                    "fade_out_ms": _num(seg.get("fade_out_ms", 0.0), here, "fade_out_ms", 0.0, 500.0)})
    return out


def _synth_layers(raw, where):
    """The made-in-code parts of a placed sound: {"name": <synth.LAYERS key>, "seed": int, "at": seconds}."""
    if not isinstance(raw, list):
        raise RecipeError("%s: synth_layers must be a list" % where)
    out = []
    for n, layer in enumerate(raw, 1):
        here = "%s synth layer %d" % (where, n)
        if not isinstance(layer, dict):
            raise RecipeError("%s: must be an object" % here)
        unknown = set(layer) - SYNTH_LAYER_FIELDS
        if unknown:
            raise RecipeError("%s: unknown fields %s" % (here, sorted(unknown)))
        for field in sorted(SYNTH_LAYER_FIELDS):
            if field not in layer:
                raise RecipeError("%s: needs %s" % (here, field))
        if layer["name"] not in LAYERS:
            raise RecipeError("%s: unknown synth layer %r (known: %s)"
                              % (here, layer["name"], ", ".join(sorted(LAYERS))))
        seed = layer["seed"]
        if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed < 2 ** 31:
            raise RecipeError("%s: seed must be a whole number from 0 to 2147483647" % here)
        out.append({"name": layer["name"], "seed": seed,
                    "at": _num(layer["at"], here, "at", 0.0, MAX_AT)})
    return out


def parse_entry(raw, where, shared=False):
    if not isinstance(raw, dict):
        raise RecipeError("%s: an entry must be an object" % where)
    slot = raw.get("slot")
    if slot not in SLOTS:
        raise RecipeError("%s: unknown slot %r" % (where, slot))
    where = "%s/%s" % (where, slot)
    unknown = set(raw) - FIELDS
    if unknown:
        raise RecipeError("%s: unknown fields %s" % (where, sorted(unknown)))
    info = SLOTS[slot]
    if raw.get("mood") != info.mood:
        raise RecipeError("%s: mood must be %r (spec section 3)" % (where, info.mood))
    if raw.get("signature") is not info.signature:
        raise RecipeError("%s: signature must be %r (spec section 3)" % (where, info.signature))
    _check_source(raw.get("source"), where)
    segments = _segments(raw.get("segments", []), where)
    synth_layers = _synth_layers(raw.get("synth_layers", []), where)
    if raw["source"] == PLACED:
        if not shared:
            raise RecipeError("%s: a placed sound belongs in %s.json, where every set shares it"
                              % (where, SHARED_NAME))
        if not segments and not synth_layers:
            raise RecipeError("%s: a placed sound needs segments or synth_layers" % where)
    elif segments or synth_layers:
        raise RecipeError("%s: segments and synth_layers need the source %r" % (where, PLACED))
    start = raw.get("start")
    end = raw.get("end")
    start = None if start is None else _num(start, where, "start", 0.0, 600.0)
    end = None if end is None else _num(end, where, "end", 0.0, 600.0)
    if start is not None and end is not None and end <= start:
        raise RecipeError("%s: end must be after start" % where)
    return Entry(slot, raw["source"], start, end,
                 _num(raw.get("gain_db", 0.0), where, "gain_db", -1.5, 1.5),
                 _num(raw.get("pitch_st", 0.0), where, "pitch_st", -12.0, 12.0),
                 _effects(raw.get("effects", []), where),
                 _num(raw.get("hp_hz", 100.0), where, "hp_hz", 100.0, 1500.0),
                 info.mood, info.signature, str(raw.get("note", "")), shared, segments, synth_layers)


def _read(path):
    with open(path, encoding="utf-8") as f:
        try:
            doc = json.load(f)
        except ValueError as e:
            raise RecipeError("%s: not valid JSON (%s)" % (path, e))
    if not isinstance(doc, dict):
        raise RecipeError("%s: a recipe file must be a JSON object" % path)
    return doc


def _entries(doc, where, shared):
    if not isinstance(doc.get("entries"), list):
        raise RecipeError("%s: 'entries' must be a list" % where)
    seen = OrderedDict()
    for raw in doc["entries"]:
        e = parse_entry(raw, where, shared)
        if e.slot in seen:
            raise RecipeError("%s: slot %s appears twice" % (where, e.slot))
        seen[e.slot] = e
    return seen


def load_set(path, shared_entries):
    """Parse one set file and join it with the shared entries. Returns a SetRecipe whose entries
    cover every slot in SLOTS order."""
    doc = _read(path)
    name = doc.get("set")
    if name not in SET_NAMES:
        raise RecipeError("%s: 'set' must be one of %s" % (path, ", ".join(SET_NAMES)))
    stem = os.path.splitext(os.path.basename(path))[0]
    if name != stem:
        raise RecipeError("%s: 'set' is %r but the file is named %s.json" % (path, name, stem))
    own = _entries(doc, name, False)
    clash = sorted(set(own) & set(shared_entries))
    if clash:
        raise RecipeError("%s: slots %s are already in %s.json" % (name, clash, SHARED_NAME))
    missing = [s for s in SLOTS if s not in own and s not in shared_entries]
    if missing:
        raise RecipeError("%s: missing slots %s" % (name, missing))
    pitch = _num(doc.get("pitch_st", 0.0), name, "pitch_st", -12.0, 12.0)
    merged = OrderedDict((s, own[s] if s in own else shared_entries[s]) for s in SLOTS)
    return SetRecipe(name, str(doc.get("title", name)), pitch, merged)


def load_recipes(sets_dir):
    """Load _shared.json and the five sets. Returns OrderedDict name -> SetRecipe."""
    shared = _entries(_read(os.path.join(sets_dir, SHARED_NAME + ".json")), SHARED_NAME, True)
    return OrderedDict((n, load_set(os.path.join(sets_dir, n + ".json"), shared)) for n in SET_NAMES)


def missing_sources(recipe, candidates_dir):
    """File sources of a set (the clips of a placed sound's segments too) that are not in the
    candidates folder, each named once."""
    out = []
    for e in recipe.entries.values():
        for source in [seg["source"] for seg in e.segments] if e.source == PLACED else [e.source]:
            if source.startswith("synth:") or source in out:
                continue
            if not os.path.isfile(os.path.join(candidates_dir, *source.split("/"))):
                out.append(source)
    return out


# --- Your mix and the round-two alternatives (stage 1b) --------------------------------------------

MINE_NAME = "mine"
ROUND2_NAME = "round2"
NONE = "none"                    # a pick that asks for a second round
MIX_TITLE = "Your mix"
ROUND2_PREFIX = "round2:"        # a pick of an alternative: round2:<moment>-<n>
ROUND2_MAX = 3                   # alternatives per moment: <moment>-1 to <moment>-3
ROUND2_ID = re.compile(r"^([a-z]+)-([1-3])$")

Mix = namedtuple("Mix", "title picks")        # picks: OrderedDict moment -> pick, in pickable order


class MixPending(RecipeError):
    """Your mix still has moments set to none, so it cannot be built for shipping."""

    def __init__(self, moments):
        RecipeError.__init__(
            self, "Your mix is not ready to build, still none: %s. Pick them on design/sounds/audition.html "
                  "(run --round2 first if nothing fits), lock in again and save the new mine.json"
                  % ", ".join(moments))
        self.moments = list(moments)


def pickable_moments(sets):
    """The cat moments that differ between the sets: the slots the set files hold themselves, that is
    everything outside _shared.json, in SLOTS order. `sets` is what load_recipes returns."""
    first = next(iter(sets.values()))
    return [slot for slot, e in first.entries.items() if not e.shared]


def _pairs_once(pairs):
    seen = OrderedDict()
    for key, value in pairs:
        if key in seen:
            raise RecipeError("%r appears twice" % key)
        seen[key] = value
    return seen


def _read_once(path):
    """Like _read, but a repeated key is an error: json.load would silently keep the last one, and a
    moment listed twice must not slip through."""
    with open(path, encoding="utf-8") as f:
        try:
            return json.load(f, object_pairs_hook=_pairs_once)
        except RecipeError as e:
            raise RecipeError("%s: %s (every key exactly once)" % (path, e))
        except ValueError as e:
            raise RecipeError("%s: not valid JSON (%s)" % (path, e))


def load_round2(path, sets):
    """round2.json: alternatives for the moments the owner marked none, as
    {"set": "round2", "entries": [{"id": "rate-1", "slot": "rate", ...an ordinary entry...}]}.
    Returns OrderedDict id -> Entry; empty when the file does not exist. Checked like any recipe
    (mood, signature, excluded sources) and, in addition, an entry may not use a window of a clip that
    one of the five sets already uses for that moment (same source, start and end)."""
    if not os.path.isfile(path):
        return OrderedDict()
    doc = _read(path)          # a broken file, or one that is not a JSON object, is already a RecipeError
    if doc.get("set", ROUND2_NAME) != ROUND2_NAME or not isinstance(doc.get("entries"), list):
        raise RecipeError("%s: must be an object with set 'round2' and a list of 'entries'" % path)
    pickable = pickable_moments(sets)
    out = OrderedDict()
    for item in doc["entries"]:
        if not isinstance(item, dict):
            raise RecipeError("%s: an entry must be an object" % ROUND2_NAME)
        item = dict(item)
        ident = item.pop("id", None)
        found = ROUND2_ID.match(ident) if isinstance(ident, str) else None
        if not found:
            raise RecipeError("%s: id %r must be <moment>-<n> with n from 1 to %d"
                              % (ROUND2_NAME, ident, ROUND2_MAX))
        where, moment = "%s/%s" % (ROUND2_NAME, ident), found.group(1)
        if moment not in pickable:
            raise RecipeError("%s: %s is not one of the 15 pickable moments" % (where, moment))
        if item.get("slot") != moment:
            raise RecipeError("%s: slot must be %r to match the id" % (where, moment))
        if ident in out:
            raise RecipeError("%s: id appears twice" % where)
        e = parse_entry(item, where)
        for name, s in sets.items():
            theirs = s.entries[moment]
            if (e.source, e.start, e.end) == (theirs.source, theirs.start, theirs.end):
                raise RecipeError("%s: %s already uses this window of %s for %s; take another clip or window"
                                  % (where, name, e.source, moment))
        out[ident] = e
    return out


def round2_recipe(round2):
    """The round-two entries as a SetRecipe keyed by id, so build_set writes <id>.wav."""
    return SetRecipe(ROUND2_NAME, "Round two", 0.0, OrderedDict(round2))


def _pick_problem(moment, pick, sets, round2):
    """Why `pick` is wrong for `moment`, or None."""
    if not isinstance(pick, str):
        return "%s: the pick must be text" % moment
    if pick == NONE or pick in sets:
        return None
    if pick.startswith(ROUND2_PREFIX):
        ident = pick[len(ROUND2_PREFIX):]
        if ident not in round2:
            return "%s: %s is not in round2.json" % (moment, pick)
        if round2[ident].slot != moment:
            return "%s: %s is an alternative for %s, not %s" % (moment, pick, round2[ident].slot, moment)
        return None
    return "%s: unknown pick %r (use %s, %s or %s<moment>-<n>)" % (moment, pick, ", ".join(sets), NONE, ROUND2_PREFIX)


def read_mix(path, sets, round2):
    """Read and check mine.json, {"title": "Your mix", "picks": {moment: pick}}: exactly the 15 pickable
    moments, each once; a pick is a set name, none, or round2:<moment>-<n> (an entry of `round2`).
    none is allowed here; mix_recipe is where it stops a build. Every problem is named in one message."""
    doc = _read_once(path)
    if not isinstance(doc, dict) or set(doc) - {"title", "picks"} or not isinstance(doc.get("picks"), dict):
        raise RecipeError('%s: must be {"title": ..., "picks": {moment: pick}} and nothing else' % path)
    title = doc.get("title", MIX_TITLE)
    if not isinstance(title, str) or not title.strip():
        raise RecipeError("%s: title must be text" % path)
    pickable, picks, problems = pickable_moments(sets), doc["picks"], []
    for moment in picks:
        if moment in pickable:
            continue
        problems.append("%s is the same in every set and is not picked" % moment if moment in SLOTS
                        else "unknown moment %r" % moment)
    problems += ["missing moment %s" % m for m in pickable if m not in picks]
    problems += [p for p in (_pick_problem(m, picks[m], sets, round2) for m in pickable if m in picks) if p]
    if problems:
        raise RecipeError("%s: %s" % (path, "; ".join(problems)))
    return Mix(title.strip(), OrderedDict((m, picks[m]) for m in pickable))


def none_moments(mix):
    return [m for m, pick in mix.picks.items() if pick == NONE]


def _picked_entry(moment, pick, sets, round2):
    """The entry Your mix builds for `moment`. A set's entry carries that set's pitch shift with it,
    because Your mix has no pitch of its own: the pipeline adds a set's shift to recorded clips only
    (never to made-in-code sounds), and so does this. A round-two entry keeps its own pitch."""
    if pick.startswith(ROUND2_PREFIX):
        return round2[pick[len(ROUND2_PREFIX):]]
    source = sets[pick]
    entry = source.entries[moment]
    shift = entry.pitch_st if entry.source.startswith("synth:") else entry.pitch_st + source.pitch_st
    if not -12.0 <= shift <= 12.0:
        raise RecipeError("%s: %s's pitch shift %+g plus its set's %+g is outside -12..12 semitones"
                          % (moment, pick, entry.pitch_st, source.pitch_st))
    return entry._replace(pitch_st=shift)


def mix_recipe(mix, sets, round2):
    """Your mix as a SetRecipe named 'mine' (an entry for every slot, in SLOTS order, pitch_st 0.0): each
    picked moment copies the picked entry, the shared sounds are the sets' shared entries (the entries of
    _shared.json). Raises MixPending while any moment is none."""
    pending = none_moments(mix)
    if pending:
        raise MixPending(pending)
    shared = next(iter(sets.values())).entries
    entries = OrderedDict((slot, _picked_entry(slot, mix.picks[slot], sets, round2) if slot in mix.picks
                           else shared[slot]) for slot in SLOTS)
    return SetRecipe(MINE_NAME, mix.title, 0.0, entries)


def load_mine(path, sets, round2):
    """mine.json as the SetRecipe 'mine'. Raises MixPending while any moment is none."""
    return mix_recipe(read_mix(path, sets, round2), sets, round2)
