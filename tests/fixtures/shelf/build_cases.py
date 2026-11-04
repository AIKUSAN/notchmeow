#!/usr/bin/env python3
"""Writes shelf-cases.json and zone-cases.json (standard library only).

The expected answers are written out here by hand and never computed by reference.py, so the
fixtures and the reference check each other. Run it after an intended change to a rule:
    python3 tests/fixtures/shelf/build_cases.py          # rewrite the two files
    python3 tests/fixtures/shelf/build_cases.py --check  # exit 1 if they drifted from this script
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MISSING = object()  # a key that is absent from the JSON; None is written as null


def zones():
    cases = []

    def z(name, x=MISSING, width=MISSING, out=None):
        c = {"name": name}
        if x is not MISSING:
            c["x"] = x
        if width is not MISSING:
            c["width"] = width
        c["out"] = out
        cases.append(c)

    z("left edge is Ask", 0, 600, "ask")
    z("well inside the left half", 120, 600, "ask")
    z("just left of the centre line", 299.5, 600, "ask")
    z("the centre line is Ask, as today", 300, 600, "ask")
    z("just right of the centre line", 300.5, 600, "shelf")
    z("well inside the right half", 480, 600, "shelf")
    z("right edge is Shelf", 600, 600, "shelf")
    z("just outside on the left", -0.5, 600, None)
    z("far outside on the left", -4000, 600, None)
    z("just outside on the right", 600.5, 600, None)
    z("far outside on the right", 1e9, 600, None)
    z("an odd width has an exact centre", 150.5, 301, "ask")
    z("an odd width, just right of it", 150.75, 301, "shelf")
    z("a narrow island", 10, 20, "ask")
    z("a narrow island, right half", 11, 20, "shelf")
    z("fractional pointer inside", 0.001, 600, "ask")
    z("a zero width has no halves", 0, 0, None)
    z("a negative width has no halves", 5, -600, None)
    z("x is text", "300", 600, None)
    z("width is text", 300, "600", None)
    z("x is null", None, 600, None)
    z("width is missing", 300, MISSING, None)
    z("x is true", True, 600, None)
    z("width is true", 0, True, None)
    z("x is a list", [300], 600, None)
    z("a 400-digit x far past a 600 island", 10**400, 600, None)
    z("a 400-digit island is outside, at its left edge", 0, 10**400, None)
    z("a 400-digit pointer on a 400-digit island is outside", 10**400, 10**400, None)
    z("a width one past NUMBER_MAX is outside", 0, MAX + 1, None)
    z("a pointer one past NUMBER_MAX is outside", MAX + 1, MAX, None)
    z("a float beyond NUMBER_MAX is outside", 1e300, 1e300, None)
    z("the largest island is exact: the centre line is Ask", 4503599627370495, MAX, "ask")
    z("the largest island is exact: one past the centre is Shelf", 4503599627370496, MAX, "shelf")
    z("the right edge of the largest island is Shelf", MAX, MAX, "shelf")
    return {"version": 1, "cases": cases}


MAX = 2**53 - 1


def it(i, name="f.txt", link=None, size=1, folder=False, copy=False, at=1):
    """A clean item, in the order the contract writes its keys."""
    d = {"id": i, "name": name, "size": size, "folder": folder, "copy": copy}
    if not copy:
        d["link"] = link if link is not None else "/p/" + i
    d["addedAt"] = at
    return d


def dirty(i, **kw):
    """A raw item: the clean one plus whatever the case sets (use None to delete a key)."""
    d = it(i)
    for k, v in kw.items():
        if v is None:
            d.pop(k, None)
        else:
            d[k] = v
    return d


def shelf(raw_items):
    return {"version": 1, "items": raw_items}


def shelf_cases():
    clean, add = [], []

    def c(name, raw, out):
        clean.append({"name": name, "raw": raw, "out": out})

    a, b, d = it("a", at=3), it("b", at=2), it("c", at=1)
    c("an empty file", {}, [])
    c("an empty list", shelf([]), [])
    for name, raw in [("null", None), ("a number", 7), ("text", "items"), ("a list", []), ("a bare list of items", [a]),
                      ("items is text", {"items": "x"}), ("items is an object", {"items": {"a": a}}), ("items is null", {"items": None})]:
        c("not a shelf: " + name, raw, [])
    c("one good link", shelf([a]), [a])
    c("three good items stay as they are", shelf([a, b, d]), [a, b, d])
    c("unknown fields go, on the file and on the item", {"version": 9, "extra": 1, "items": [dict(a, bookmark="x", __proto__={"x": 1}, constructor=5)]}, [a])
    c("a copied item carries no link", shelf([dirty("k", copy=True, link="/somewhere")]), [it("k", copy=True)])
    c("a copied item needs no link", shelf([dirty("k", copy=True, link=None)]), [it("k", copy=True)])
    c("a folder is a link", shelf([dirty("f", folder=True)]), [it("f", folder=True)])
    c("a copied folder is refused", shelf([dirty("f", folder=True, copy=True)]), [])
    c("copy and folder count only as the boolean true", shelf([dirty("g", copy="true", folder=1)]), [it("g")])
    # ids
    for bad in ["", "../x", "a/b", "a b", "a.b", "a\n", "\nA", "é", "z" * 65, 7, None, ["a"], {"x": 1}]:
        c("hostile id " + json.dumps(bad), shelf([dirty("x", id=bad)]), [])
    c("an id of 64 characters is fine", shelf([dirty("y" * 64, link="/y")]), [it("y" * 64, link="/y")])
    c("ids may hold letters, digits, dash and underscore", shelf([dirty("Aa_0-9")]), [it("Aa_0-9")])
    c("a missing id", shelf([dirty("x", id=None)]), [])
    # names
    for bad in ["", ".", "..", "...", "a/b", "a\\b", "tab\there", "nul\u0000x", "del\u007fx", "c1\u0085x", "n" * 256, 5, None, ["f"],
                "bidi‮x", "zero​width", "bom﻿name", "line sep", "para sep", "lone\ud800x", "lone\udfffx",
                "report.", "report ", " ", "CON", "con.txt", "NUL.tar.gz", "Com1.log", "lpt9", "AUX", "PRN.",
                "CON .txt", "COM\u00b9", "lpt\u00b3.log"]:
        c("hostile name " + json.dumps(bad), shelf([dirty("x", name=bad)]), [])
    for bad in ["CON", "nul", "Com9", "LPT1", "lpt3"]:
        c("reserved id " + bad, shelf([dirty("x", id=bad)]), [])
    c("a link with a lone surrogate is dropped", shelf([dirty("x", link="a\ud800b")]), [])
    c("a name of 255 characters is fine", shelf([dirty("x", name="n" * 255)]), [it("x", name="n" * 255)])
    c("names count code points, not bytes", shelf([dirty("x", name="😀" * 255)]), [it("x", name="😀" * 255)])
    c("a name of 256 code points is refused", shelf([dirty("x", name="😀" * 256)]), [])
    c("a leading space, dots inside and accents are fine", shelf([dirty("x", name=" Rapport été.2026.pdf")]), [it("x", name=" Rapport été.2026.pdf")])
    c("reserved words are fine when they are not the whole stem", shelf([dirty("a", name="CONSOLE.txt"), dirty("b", name="COM0"), dirty("c", name="my.con"), dirty("d", name="con-1")]),
      [it("a", name="CONSOLE.txt"), it("b", name="COM0"), it("c", name="my.con"), it("d", name="con-1")])
    # links
    for bad in ["", "a\u0000b", "a\nb", "a\u007fb", "r" * 8193, 5, None, ["/p"], True]:
        c("hostile link " + json.dumps(bad)[:40], shelf([dirty("x", link=bad)]), [])
    c("a missing link on a link item", shelf([dirty("x", link=None)]), [])
    c("a link of 8192 characters is fine", shelf([dirty("x", link="r" * 8192)]), [it("x", link="r" * 8192)])
    c("a Windows path and a bookmark are only strings", shelf([dirty("w", link="C:\\Users\\Zoé\\a b.pdf"), dirty("m", link="Ym9va21hcmtkYXRh+/==")]),
      [it("w", link="C:\\Users\\Zoé\\a b.pdf"), it("m", link="Ym9va21hcmtkYXRh+/==")])
    # size and addedAt
    for bad in [-1, 1.5, "7", None, True, [3], MAX + 1, 1e300, 2**70]:
        c("size " + json.dumps(bad) + " becomes 0", shelf([dirty("x", size=bad)]), [it("x", size=0)])
    c("size 5.0 is the number 5", shelf([dirty("x", size=5.0)]), [it("x", size=5)])
    c("the largest exact size is kept", shelf([dirty("x", size=MAX)]), [it("x", size=MAX)])
    c("size 0 is fine", shelf([dirty("x", size=0)]), [it("x", size=0)])
    c("a missing size is 0", shelf([dirty("x", size=None)]), [it("x", size=0)])
    for bad in [-1, 0.5, "9", None, True, MAX + 1]:
        c("addedAt " + json.dumps(bad) + " becomes 0", shelf([dirty("x", at=None, addedAt=bad)]), [it("x", at=0)])
    # order
    c("newest first, whatever the file's order", shelf([d, a, b]), [a, b, d])
    c("equal times keep the file's order", shelf([it("p", at=5), it("q", at=5), it("r", at=5)]), [it("p", at=5), it("q", at=5), it("r", at=5)])
    c("items without a time sink to the end, in file order", shelf([dirty("n1", addedAt=None), it("t", at=2), dirty("n2", addedAt="x")]),
      [it("t", at=2), it("n1", at=0), it("n2", at=0)])
    # duplicates
    c("the same id twice: the newer stays", shelf([it("a", link="/old", at=1), it("a", link="/new", at=9)]), [it("a", link="/new", at=9)])
    c("the same id twice at the same time: the first in the file stays", shelf([it("a", link="/one", at=4), it("a", link="/two", at=4)]), [it("a", link="/one", at=4)])
    c("the same file twice under two ids: the newer stays", shelf([it("a", link="/same", at=1), it("b", link="/same", at=2)]), [it("b", link="/same", at=2)])
    c("links compare exactly, case and all", shelf([it("a", link="/Same", at=2), it("b", link="/same", at=1)]), [it("a", link="/Same", at=2), it("b", link="/same", at=1)])
    c("a copy never clashes with a link", shelf([it("a", copy=True, at=2), it("b", link="/a", at=1)]), [it("a", copy=True, at=2), it("b", link="/a", at=1)])
    c("a hostile item does not hide a good duplicate", shelf([dirty("a", name="a/b", at=9), it("a", link="/kept", at=1)]), [it("a", link="/kept", at=1)])
    c("ids compare without case: the newer of Abc and abc stays", shelf([it("Abc", link="/one", at=1), it("abc", link="/two", at=2)]), [it("abc", link="/two", at=2)])
    c("ids compare without case: the first of equal times stays", shelf([it("Abc", link="/one", at=4), it("abc", link="/two", at=4)]), [it("Abc", link="/one", at=4)])
    c("hostile entries between good ones are skipped", shelf([a, None, 5, "x", [], {"id": "q"}, b]), [a, b])
    c("an item skipped for a repeated link reserves no id", shelf([it("a", link="/x", at=3), it("b", link="/x", at=2), it("b", link="/y", at=1)]),
      [it("a", link="/x", at=3), it("b", link="/y", at=1)])
    c("links are compared by code points: NFC and NFD of the same word are two links",
      shelf([it("nfc", link="/café", at=2), it("nfd", link="/café", at=1)]),
      [it("nfc", link="/café", at=2), it("nfd", link="/café", at=1)])
    c("a top-level __proto__ key is not items", {"__proto__": {"items": [a]}}, [])
    # the cap
    many = [it("i%02d" % n, at=100 - n) for n in range(45)]
    c("a hostile file with 45 items keeps the 30 newest", shelf(many), many[:30])
    shuffled = many[::-1]
    c("the cap keeps the newest whatever the order", shelf(shuffled), many[:30])
    c("exactly 30 items stay", shelf(many[:30]), many[:30])
    c("a duplicate does not use a place", shelf(many[:29] + [dict(many[0], addedAt=1)]), many[:29])
    c("a duplicate of the newest, past the 30th place, does not use a place", shelf(many[:31] + [dict(many[0], addedAt=101)]),
      [dict(many[0], addedAt=101)] + many[1:30])
    many31 = [it("i%02d" % n, at=100 - n) for n in range(31)]
    c("a raw shelf of 31 items keeps the 30 newest", shelf(many31), many31[:30])
    huge = [it("h%03d" % n, at=1000 - n) for n in range(300)]
    c("a 300-item file keeps the 30 newest", shelf(huge), huge[:30])

    # ---- reading the file: bytes to items (an unreadable file is an empty shelf)
    parse = []

    def p(name, data, out):
        """A file as its bytes: text when they are UTF-8, hex when they are not."""
        try:
            parse.append({"name": name, "text": data.decode("utf-8"), "out": out})
        except UnicodeDecodeError:
            parse.append({"name": name, "hex": data.hex(), "out": out})

    one = b'{"id":"a","name":"f.txt","size":1,"folder":false,"copy":false,"link":"/p/a","addedAt":1}'
    p("a valid file", b'{"version":1,"items":[' + one + b']}', [it("a", at=1)])
    p("an empty file", b"", [])
    p("a BOM only", b"\xef\xbb\xbf", [])
    p("white space only", b" \n\t", [])
    p("a truncated file", b'{"version":1,"items":[' + one[:30], [])
    p("a valid file with a BOM in front", b"\xef\xbb\xbf" + b'{"items":[' + one + b']}', [])
    p("a valid file with text after it", b'{"items":[' + one + b']} x', [])
    p("a top-level number", b"7", [])
    p("a top-level text", b'"items"', [])
    p("null", b"null", [])
    p("a top-level list of items", b"[" + one + b"]", [])
    p("NaN is not JSON", b'{"items": NaN}', [])
    p("Infinity is not JSON", b'{"items":[{"id":"a","name":"f.txt","size":Infinity,"folder":false,"copy":false,"link":"/p/a","addedAt":1}]}', [])
    p("invalid UTF-8", b'{"items": "\xff"}', [])
    p("a file nested 10000 deep", b"[" * 10000 + b"]" * 10000, [])
    p("the last of two repeated items keys wins", b'{"items":[' + one + b'], "items": []}', [])
    p("the last of two repeated id keys wins", b'{"items":[{"id":"a","id":"b","name":"f.txt","size":1,"folder":false,"copy":false,"link":"/p/b","addedAt":1}]}', [it("b", at=1)])
    p("1e2 is the number 100, -0 and -0.0 are 0",
      b'{"items":[{"id":"a","name":"f.txt","size":1e2,"folder":false,"copy":false,"link":"/p/a","addedAt":-0},'
      b'{"id":"b","name":"f.txt","size":-0.0,"folder":false,"copy":false,"link":"/p/b","addedAt":-0.0}]}',
      [it("a", size=100, at=0), it("b", size=0, at=0)])

    # ---- adding (the Shelf half of a drop)
    def ad(name, items, incoming, out_items, results):
        add.append({"name": name, "items": items, "incoming": incoming, "out": {"items": out_items, "results": results}})

    base = [it("a", at=30), it("b", at=20)]
    n1, n2, n3 = it("n1", at=300), it("n2", at=300), it("n3", at=300)
    ad("into an empty shelf", [], [n1, n2], [n1, n2], ["added", "added"])
    ad("the new ones go first, in the order given", base, [n1, n2], [n1, n2] + base, ["added", "added"])
    ad("nothing dropped", base, [], base, [])
    ad("incoming is not a list", base, None, base, [])
    ad("a file already on the shelf is a duplicate", base, [it("zz", link="/p/a", at=300)], base, ["duplicate"])
    ad("the same id is a duplicate", base, [it("a", link="/other", at=300)], base, ["duplicate"])
    ad("the same file twice in one drop is added once", base, [n1, it("n9", link="/p/n1", at=300)], [n1] + base, ["added", "duplicate"])
    ad("the same id twice in one drop is added once", base, [n1, dict(n1, link="/p/other")], [n1] + base, ["added", "duplicate"])
    ad("a hostile item is invalid, the rest go on", base, [dirty("bad", name="a/b"), n1, 5, None], [n1] + base, ["invalid", "added", "invalid", "invalid"])
    ad("an item whose link is missing is invalid", base, [dirty("x", link=None)], base, ["invalid"])
    full = [it("i%02d" % n, at=200 - n) for n in range(30)]
    ad("a full shelf refuses and removes nothing", full, [n1], full, ["full"])
    ad("a full shelf says duplicate for a file it already holds", full, [it("zz", link="/p/i00", at=999)], full, ["duplicate"])
    ad("a full shelf, one invalid and one full", full, [dirty("bad", id="../x"), n1], full, ["invalid", "full"])
    almost = full[:28]
    ad("room for two of three", almost, [n1, n2, n3], [n1, n2] + almost, ["added", "added", "full"])
    ad("room for one, a duplicate does not use it", full[:29], [dirty("zz", link="/p/i00"), n1, n2], [n1] + full[:29], ["duplicate", "added", "full"])
    ad("the shelf given is cleaned first", [dict(base[0], bookmark="x"), 5], [n1], [n1, base[0]], ["added"])
    ad("a copied item is added without a link", base, [dirty("cp", copy=True, link="/dropped", addedAt=300)], [it("cp", copy=True, at=300)] + base, ["added"])
    ad("a copied folder is invalid", base, [dirty("cf", copy=True, folder=True)], base, ["invalid"])
    ad("an older item slots in by time", base, [it("old", at=25)], [base[0], it("old", at=25), base[1]], ["added"])
    ad("a drop on a 31-item shelf acts on the 30 kept, the oldest is gone", many31, [n1], many31[:30], ["full"])
    cased = [it("abc", at=30)]
    ad("ids compare without case: ABC is a duplicate of abc", cased, [it("ABC", link="/p/new", at=300)], cased, ["duplicate"])
    for label, bad in [("bidi control", "x‮y"), ("invisible or format character", "x​y"), ("line separator", "x y"),
                       ("paragraph separator", "x y"), ("lone surrogate", "x\ud800y")]:
        ad("a name with a " + label + " is invalid", base, [dirty("bad", name=bad)], base, ["invalid"])
    ad("a name of only dots, or ending in a dot or a space, is invalid", base,
       [dirty("d1", name="..."), dirty("d2", name="report."), dirty("d3", name="report ")], base, ["invalid", "invalid", "invalid"])
    ad("a Windows device name is invalid, with or without an extension", base,
       [dirty("c1", name="con.txt"), dirty("c2", name="NUL.tar.gz"), n1], [n1] + base, ["invalid", "invalid", "added"])
    ad("a Windows device name as an id is invalid", base, [dirty("nul")], base, ["invalid"])
    ad("a link with a lone surrogate is invalid", base, [dirty("bad", link="x\ud800y")], base, ["invalid"])

    return {"version": 1, "max": 30, "idPattern": "[A-Za-z0-9_-]{1,64}", "nameMax": 255, "linkMax": 8192, "numberMax": MAX,
            "cleanCases": clean, "addCases": add, "parseCases": parse}


def render(obj):
    """One case per line: easy to read and to diff. Floats like 5.0 stay 5.0. Non-ASCII is escaped, so an invisible character shows as an escape."""
    out = []
    for k, v in obj.items():
        if isinstance(v, list):
            out.append('  "%s": [\n    %s\n  ]' % (k, ",\n    ".join(json.dumps(x) for x in v)))
        else:
            out.append('  "%s": %s' % (k, json.dumps(v)))
    return "{\n" + ",\n".join(out) + "\n}\n"


FILES = {"shelf-cases.json": shelf_cases, "zone-cases.json": zones}


def main():
    check = "--check" in sys.argv
    bad = 0
    for name, build in FILES.items():
        text = render(build())
        path = os.path.join(HERE, name)
        if check:
            have = open(path, encoding="utf-8").read() if os.path.exists(path) else None
            if have != text:
                print(f"✗ {name} drifted from build_cases.py")
                bad = 1
            else:
                print(f"✓ {name} matches build_cases.py")
        else:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            print(f"wrote {name} ({len(text)} bytes)")
    return bad


if __name__ == "__main__":
    sys.exit(main())
