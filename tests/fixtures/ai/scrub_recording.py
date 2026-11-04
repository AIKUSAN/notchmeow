#!/usr/bin/env python3
"""Scrub a recorded CLI run before it is committed as a fixture (F3a2-0).

scrub(text, home, user, hosts=(), name="") replaces, in this order: the home path (also with backslash
separators and a Windows drive letter) with __HOME__; the user name as a whole word with __USER__; every
email with __EMAIL__; every UUID and every thread_/ses_/msg_/prt_/per_ id with __ID_n__, numbered by first
appearance in the file; the port of every http://127.0.0.1 URL with __PORT__; every key-like string with
__KEY__ (never inside a placeholder); the host names with __HOST__; the git user's full name with __NAME__.
Standard library only, `re` for matching.

CLI: scrub_recording.py IN OUT --host H [--host H2] --name N
Home and user come from the environment (HOME, USER). OUT is not written if the real home, user, host or
name is still in the result.
"""
import argparse
import os
import re
import sys


UUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
ID = re.compile(UUID + r"|\b(?:thread|ses|msg|prt|per)_[A-Za-z0-9]+")
EMAIL = re.compile(r"[\w.%+-]+@[\w-]+(?:\.[\w-]+)+")
PORT = re.compile(r"(http://127\.0\.0\.1:)\d+")
KEY = re.compile(r"\bsk-[A-Za-z0-9_-]{8,}|\bgh[pousr]_[A-Za-z0-9]{8,}|\beyJ[A-Za-z0-9_-]{10,}|[A-Za-z0-9_-]{32,}")
PLACEHOLDER = re.compile(r"(__[A-Z]+(?:_\d+)?__)")


def _word(s):
    """A whole word: not part of a longer name, path segment or host."""
    return r"(?<![\w-])" + re.escape(s) + r"(?![\w-])"


def _home_re(home):
    """The home path with forward slashes, or with backslashes and an optional drive letter (also JSON-escaped)."""
    parts = [p for p in re.split(r"[\\/]+", home) if p]
    forward = re.escape(home)
    windows = r"(?:[A-Za-z]:)?" + "".join(r"\\\\?" + re.escape(p) for p in parts)
    return re.compile("(?:" + forward + "|" + windows + r")(?![\w-])")


def _scrub_ids(text):
    seen = {}

    def number(m):
        if m.group(0) not in seen:
            seen[m.group(0)] = len(seen) + 1
        return "__ID_%d__" % seen[m.group(0)]

    return ID.sub(number, text)


def _scrub_keys(text):
    # Odd parts of the split are placeholders: the key rule never reads into them, so __ID_n__ and the
    # rest of the scrubbed tokens stay whole.
    parts = PLACEHOLDER.split(text)
    for i in range(0, len(parts), 2):
        parts[i] = KEY.sub("__KEY__", parts[i])
    return "".join(parts)


def scrub(text, home, user, hosts=(), name=""):
    home = home.rstrip("/\\")
    if home:
        text = _home_re(home).sub("__HOME__", text)
    if user:
        text = re.sub(_word(user), "__USER__", text)
    text = EMAIL.sub("__EMAIL__", text)
    text = _scrub_ids(text)
    text = PORT.sub(r"\g<1>__PORT__", text)
    text = _scrub_keys(text)
    for host in hosts:
        if host:
            text = re.sub(_word(host), "__HOST__", text, flags=re.I)
    if name:
        text = re.sub(re.escape(name), "__NAME__", text, flags=re.I)
    return text


def self_test():
    out = scrub(SAMPLE, HOME, USER, hosts=[HOST], name=NAME)
    checks = [
        ("home path with a slash", "__HOME__/x" in out),
        ("home path with backslashes", "__HOME__\\x" in out),
        ("email", "__EMAIL__" in out and "zoe@example.com" not in out),
        ("UUID twice as one id", out.count("__ID_1__") == 2),
        ("ses_ id as the second id", "__ID_2__" in out),
        ("localhost port", "http://127.0.0.1:__PORT__" in out),
        ("apiKey value", '"apiKey":"__KEY__"' in out),
        ("gh token", "token __KEY__" in out),
        ("host name", "__HOST__" in out and "zoes-mbp" not in out),
        ("full name", "__NAME__" in out and "Zoe Example" not in out),
        ("user name nowhere", "zoe" not in out and "Zoe" not in out),
        ("UUID nowhere", "11111111" not in out),
        ("placeholder survives the key rule", "long __KEY____HOME____KEY__" in out),
        ("scrubbing twice changes nothing", scrub(out, HOME, USER, hosts=[HOST], name=NAME) == out),
    ]
    failed = [label for label, ok in checks if not ok]
    if failed:
        for label in failed:
            print("scrub self-test failed: " + label, file=sys.stderr)
        return 1
    print("scrub self-test passed")
    return 0


HOME = "/Users/zoe"
USER = "zoe"
HOST = "zoes-mbp"
NAME = "Zoe Example"
SAMPLE = "\n".join([
    "path /Users/zoe/x",
    "win C:\\Users\\zoe\\x",
    "mail zoe@example.com",
    "id 11111111-1111-4111-8111-111111111111 and 11111111-1111-4111-8111-111111111111",
    "ses ses_abc",
    "url http://127.0.0.1:51234",
    '{"apiKey":"sk-proj-abcdefghijkl"}',
    "token ghp_abcdefghij12",
    "host zoes-mbp",
    "name Zoe Example",
    "long " + "a" * 40 + "__HOME__" + "b" * 40,
])


def main(argv):
    if argv[:1] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description="Scrub a recorded CLI run before it is committed.")
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("--host", action="append", default=[])
    ap.add_argument("--name", default="")
    args = ap.parse_args(argv)
    home = os.environ.get("HOME", "").rstrip("/\\")
    user = os.environ.get("USER") or os.environ.get("LOGNAME", "")
    with open(args.inp, encoding="utf-8", errors="replace", newline="") as f:
        out = scrub(f.read(), home, user, hosts=args.host, name=args.name)
    leftovers = []
    if home and _home_re(home).search(out):
        leftovers.append("the home path")
    if user and re.search(_word(user), out):
        leftovers.append("the user name")
    if any(h and re.search(_word(h), out, re.I) for h in args.host):
        leftovers.append("a host name")
    if args.name and re.search(re.escape(args.name), out, re.I):
        leftovers.append("the full name")
    if leftovers:
        print("refusing to write %s: it still contains %s" % (args.out, ", ".join(leftovers)), file=sys.stderr)
        return 2
    with open(args.out, "w", encoding="utf-8", newline="") as f:
        f.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
