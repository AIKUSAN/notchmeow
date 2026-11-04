#!/usr/bin/env python3
"""Reference implementation of NotchMeow's shelf contract (sub-project G1).

Three rules, all pure: zone_at (which half of the open island a pointer is in),
shelf_clean (how shelf.json is read) and shelf_add (what happens when files are
dropped on the Shelf half). Runs every fixture in tests/fixtures/shelf/ against them,
then a few self-checks and a seeded fuzz. Standard library only; exit status 1 if
anything fails. Both apps implement the same rules natively; this file is the
tie-breaker when they disagree.
"""
import json
import math
import os
import random
import re
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
FAILURES = 0


def zone_at(x, width):
    """'ask' (left half, the centre line included), 'shelf' (right half) or None (outside the island, not numbers,
    or beyond NUMBER_MAX). Integers up to NUMBER_MAX are compared exactly; the arithmetic never divides."""
    for v in (x, width):
        if (isinstance(v, bool) or not isinstance(v, (int, float)) or (isinstance(v, float) and not math.isfinite(v))
                or abs(v) > NUMBER_MAX):
            return None
    if width <= 0 or x < 0 or x > width:
        return None
    return "ask" if x * 2 <= width else "shelf"


SHELF_MAX = 30                      # items on the shelf
ID_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")   # matched against the WHOLE string
NAME_MAX = 255                      # code points
LINK_MAX = 8192                     # code points
NUMBER_MAX = 2**53 - 1              # largest size / addedAt (every language holds it exactly)


# Unicode categories a name may not hold: controls (C0, DEL, C1), format characters (bidi controls, zero-width
# space, BOM), lone surrogates, and the line and paragraph separators (U+2028, U+2029).
BAD_NAME_CATEGORIES = {"Cc", "Cf", "Cs", "Zl", "Zp"}
# Windows device names, refused as a name's stem (the part before the first dot, trailing spaces trimmed) or as an
# id, ASCII case-insensitively. The superscript digits COM1-3 and LPT1-3 are reserved too.
RESERVED = ({"CON", "PRN", "AUX", "NUL"} | {"COM%d" % n for n in range(1, 10)} | {"LPT%d" % n for n in range(1, 10)}
            | {"COM\u00b9", "COM\u00b2", "COM\u00b3", "LPT\u00b9", "LPT\u00b2", "LPT\u00b3"})
ASCII_UPPER = {c: c - 32 for c in range(ord("a"), ord("z") + 1)}


def reserved(s):
    return s.split(".", 1)[0].rstrip(" ").translate(ASCII_UPPER) in RESERVED


def name_ok(name):
    """A name the app can create as a file: 1 to 255 code points, no bad character, no path separator,
    not only dots, not ending in a dot or a space, not a Windows device name."""
    if not isinstance(name, str) or not 1 <= len(name) <= NAME_MAX:
        return False
    if any(unicodedata.category(c) in BAD_NAME_CATEGORIES for c in name):
        return False
    if "/" in name or "\\" in name or set(name) == {"."} or name.endswith((".", " ")):
        return False
    return not reserved(name)


def has_control(s):
    """True for a C0 control, DEL or a C1 control (U+0000-001F, U+007F-009F)."""
    return any(ord(c) < 0x20 or 0x7F <= ord(c) <= 0x9F for c in s)


def has_lone_surrogate(s):
    """True for a lone surrogate: no real path or bookmark can hold one, so a link never does."""
    return any(unicodedata.category(c) == "Cs" for c in s)


def whole(v):
    """A whole number from 0 to NUMBER_MAX (5 and 5.0 are the same JSON number to JavaScript), else 0."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return 0
    if isinstance(v, float) and (v != v or v in (float("inf"), float("-inf")) or not v.is_integer()):
        return 0
    n = int(v)
    return n if 0 <= n <= NUMBER_MAX else 0


def item_clean(raw):
    """One stored item to its clean form, or None when it cannot be kept."""
    if not isinstance(raw, dict):
        return None
    i, name = raw.get("id"), raw.get("name")
    if not isinstance(i, str) or not ID_RE.fullmatch(i) or reserved(i):
        return None
    if not name_ok(name):
        return None
    copy, folder = raw.get("copy") is True, raw.get("folder") is True
    if copy and folder:
        return None                 # a folder is only ever a link
    out = {"id": i, "name": name, "size": whole(raw.get("size")), "folder": folder, "copy": copy}
    if not copy:
        link = raw.get("link")
        if not isinstance(link, str) or not 1 <= len(link) <= LINK_MAX or has_control(link) or has_lone_surrogate(link):
            return None
        out["link"] = link
    out["addedAt"] = whole(raw.get("addedAt"))
    return out


def tidy(items):
    """Newest first (stable), then the first of each id and of each link, then the first SHELF_MAX.
    Ids compare ASCII case-insensitively (Abc is abc); links compare exactly."""
    items = sorted(items, key=lambda it: -it["addedAt"])
    # One pass in sorted order: an item skipped for a repeated link reserves nothing, so its id stays free.
    seen_id, seen_link, out = set(), set(), []
    for it in items:
        if it["id"].lower() in seen_id or ("link" in it and it["link"] in seen_link):
            continue
        seen_id.add(it["id"].lower())
        if "link" in it:
            seen_link.add(it["link"])
        out.append(it)
    return out[:SHELF_MAX]


def shelf_clean(raw):
    """The parsed content of shelf.json to the list of items the shelf holds. Never raises."""
    if not isinstance(raw, dict) or not isinstance(raw.get("items"), list):
        return []
    return tidy([c for c in (item_clean(r) for r in raw["items"]) if c is not None])


def shelf_add(items, incoming):
    """Files dropped on the Shelf half. Returns {items, results}; results has one word per incoming item:
    'added', 'duplicate', 'full' or 'invalid'. Nothing already on the shelf is ever removed."""
    current = shelf_clean({"items": items})
    ids = {it["id"].lower() for it in current}
    links = {it["link"] for it in current if "link" in it}
    accepted, results = [], []
    for raw in incoming if isinstance(incoming, list) else []:
        it = item_clean(raw)
        if it is None:
            results.append("invalid")
        elif it["id"].lower() in ids or ("link" in it and it["link"] in links):
            results.append("duplicate")         # refused items reserve nothing, as in tidy()
        elif len(current) + len(accepted) >= SHELF_MAX:
            results.append("full")
        else:
            accepted.append(it)
            ids.add(it["id"].lower())
            if "link" in it:
                links.add(it["link"])
            results.append("added")
    return {"items": tidy(accepted + current), "results": results}


def _not_json(name):
    raise ValueError(name + " is not JSON")


def read_shelf(data):
    """The bytes of shelf.json to the items it holds. Unreadable bytes are an empty shelf; never raises.
    UTF-8 read strictly (a BOM is not stripped), NaN and Infinity refused, the last of a repeated key wins."""
    try:
        raw = json.loads(data.decode("utf-8"), parse_constant=_not_json)
    except (ValueError, RecursionError):
        return []
    return shelf_clean(raw)


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


def check(label, got, expected):
    global FAILURES
    if got == expected:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}\n    got:      {str(got)[:400]}\n    expected: {str(expected)[:400]}")
        FAILURES += 1


def check_zones():
    print("zone-cases.json")
    z = load("zone-cases.json")
    for c in z["cases"]:
        got = zone_at(c.get("x"), c.get("width"))
        check(c["name"], got, c["out"])


def check_shelf():
    print("shelf-cases.json")
    s = load("shelf-cases.json")
    check("constants", (s["max"], s["idPattern"], s["nameMax"], s["linkMax"], s["numberMax"]),
          (SHELF_MAX, ID_RE.pattern, NAME_MAX, LINK_MAX, NUMBER_MAX))
    for c in s["cleanCases"]:
        check("clean: " + c["name"], shelf_clean(c["raw"]), c["out"])
    for c in s["addCases"]:
        check("add: " + c["name"], shelf_add(c["items"], c["incoming"]), c["out"])
    for c in s["parseCases"]:
        data = c["text"].encode("utf-8") if "text" in c else bytes.fromhex(c["hex"])
        check("parse: " + c["name"], read_shelf(data), c["out"])


def check_properties():
    print("properties")
    rnd = random.Random(7)
    words = ["a", "b", "c", "/x", "..", ".", "", "x" * 300, "n\n", "ok", "é", "😀", "a/b", "a\\b"]

    def junk():
        kind = rnd.randrange(8)
        if kind == 0:
            return rnd.choice([None, True, 7, -1, 2.5, 1e300, "text", [], {}])
        return {"id": rnd.choice(["a1", "b2", "c3", "d4", "../x", "", "a b", "z" * 65, "a\n"]),
                "name": rnd.choice(words), "size": rnd.choice([0, 5, -1, 2.5, "7", None, 2**60]),
                "folder": rnd.choice([True, False, 1, "true"]), "copy": rnd.choice([True, False, 0, None]),
                "link": rnd.choice(["/p", "/q", "", "a\x00b", None, 5, "r" * 9000, "/p"]),
                "addedAt": rnd.choice([1, 2, 3, 3, -1, "x", None, 2.0, 1e30]), "extra": {"__proto__": 1}}

    ok, last = True, None
    for _ in range(3000):
        raw = {"items": [junk() for _ in range(rnd.randrange(0, 40))]}
        try:
            out = shelf_clean(raw)
            again = shelf_clean({"items": out})
        except Exception as e:                     # noqa: BLE001 - the point is that nothing raises
            ok, last = False, repr(e)
            break
        ids = [it["id"].lower() for it in out]
        links = [it["link"] for it in out if "link" in it]
        if (again != out or len(out) > SHELF_MAX or len(set(ids)) != len(ids) or len(set(links)) != len(links)
                or any(a["addedAt"] < b["addedAt"] for a, b in zip(out, out[1:]))):
            ok, last = False, raw
            break
    check("3000 hostile shelves: never raises, clean twice is clean once, no duplicates, newest first, at most 30", ok, True)
    if not ok:
        print("    first failure:", last)
    # Adding never removes anything, never grows the shelf past the cap, and answers one word per item.
    WORDS = {"added", "duplicate", "full", "invalid"}

    def valid(prefix, n):
        return {"id": "%s%d" % (prefix, n), "name": "f%d" % n, "size": rnd.randrange(0, 1000), "folder": False,
                "copy": False, "link": "/%s/%d" % (prefix, n), "addedAt": rnd.randrange(1, 10**6)}

    ok, counts, fresh = True, {w: 0 for w in WORDS}, 0
    for _ in range(1500):
        base = shelf_clean({"items": [valid("v", n) for n in range(rnd.randrange(28, 36))]})
        incoming = []
        for _ in range(rnd.randrange(0, 12)):
            kind = rnd.randrange(3)
            if kind == 0:
                incoming.append(junk())
            elif kind == 1:
                incoming.append(valid("v", rnd.randrange(0, 36)))     # same id and link as one already on the shelf
            else:
                incoming.append(valid("w", fresh))
                fresh += 1
        res = shelf_add(base, incoming)
        old = {it["id"] for it in base}
        for w in res["results"]:
            counts[w] = counts.get(w, 0) + 1
        if (len(res["results"]) != len(incoming) or any(w not in WORDS for w in res["results"])
                or len(res["items"]) > SHELF_MAX or not old <= {it["id"] for it in res["items"]}
                or res["results"].count("added") != len(res["items"]) - len(base)):
            ok = False
            break
    check("1500 drops: one word per item, nothing already shelved is removed, the cap holds, the added count matches", ok, True)
    check("1500 drops: the cap is reached (full appears at least once)", counts["full"] > 0, True)


def main():
    check_zones()
    check_shelf()
    check_properties()
    print(f"\n{'FAILED: ' + str(FAILURES) if FAILURES else 'all shelf contract checks passed'}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
