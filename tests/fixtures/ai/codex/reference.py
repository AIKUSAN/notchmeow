#!/usr/bin/env python3
"""Reference implementation of the Codex engine's contract (F3a2-0, Tasks 1 and 2).

Every fixture in this folder is run against a small Python model: the command line per level and turn, the cleaned
environment, where codex is looked for, the versions, and the sign-in state. The app plans (F3a2-mac, F3a2-tauri)
port these functions one for one and replay the same fixtures; this file decides when they disagree. It never runs
the real `codex`, and it fails if anything opens an auth.json.
"""
import contextlib
import datetime
import io
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FAILURES = 0


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


def check(label, got, expected):
    global FAILURES
    if got == expected:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}\n    got:      {got!r}\n    expected: {expected!r}")
        FAILURES += 1


# Credentials are never read: any open of a file named auth.json fails the run (plan Global Constraints).
# str, bytes and PathLike paths all count (os.fsdecode reads all three); an open by file descriptor is not a path.
_probing = False


def names_auth_json(arg):
    try:
        return os.path.basename(os.fsdecode(arg)) == "auth.json"
    except TypeError:
        return False


def _fail_auth():
    global FAILURES
    FAILURES += 1
    if not _probing:
        print("  ✗ opened an auth.json")


sys.addaudithook(lambda ev, args: ev == "open" and bool(args) and names_auth_json(args[0]) and _fail_auth())


# ── the command line ─────────────────────────────────────────────────────────────

BASE = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
        "--ignore-user-config", "--ignore-rules"]
# Shell, unified exec, apps, browser, computer use and web search off (recorded/shell-off-flags.txt, FINDINGS step 13).
# Without it a read-only Codex still ran commands and searched the web (FINDINGS steps 5, 7, 10).
SHELL_OFF = ["--disable", "shell_tool", "--disable", "unified_exec", "--disable", "apps", "--disable", "browser_use",
             "--disable", "computer_use", "--disable", "in_app_browser", "-c", "web_search=\"disabled\""]
MODEL_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$"
MODEL_RE = re.compile(MODEL_PATTERN)
# Owner rulings (2026-10-28): quick actions (none) and Chat only are offered. read (R1) and agent (R4) are not.
OFFERED_LEVELS = ("none", "chat")


def build_args(level, model, images):
    """One turn's argv. The chat folder is the cwd (see turn_cwd) and never appears here."""
    if level not in OFFERED_LEVELS:
        return {"error": "nm_level_unavailable"}
    if model is not None and not MODEL_RE.fullmatch(model):
        return {"error": "nm_bad_model"}
    args = BASE + SHELL_OFF
    if model is not None:
        args += ["--model", model]
    # One --image=<path> per picture (probe of codex-cli 0.165.0, 2026-10-29). The bare `--image <path>` form lets the
    # CLI read the final `-` as a second picture, so the prompt on stdin is never read as one.
    for path in images:
        args += [f"--image={path}"]
    return args + ["-"]


def turn_cwd(level, folder):
    """The process's working directory. A read or agent turn without a folder falls back to the chat folder."""
    if level in ("read", "agent") and folder:
        return "folder"
    return "chatFolder"


def clean_env(base, platform):
    spec = load("expected-env.json")
    ci = platform == "windows"
    names = {n.upper() if ci else n for n in spec["stripped"]}
    prefixes = [p.upper() if ci else p for p in spec["strippedPrefixes"]]
    out = {}
    for k, v in base.items():
        key = k.upper() if ci else k
        if key in names or any(key.startswith(p) for p in prefixes):
            continue
        out[k] = v
    return out


def locate(platform, home, env, executables, login_shell):
    """Returns (path or None, shim_only, login_shell_called)."""
    exe = set(executables)
    if platform == "windows":
        folders = [home + "\\.local\\bin"] + [d.rstrip("\\") for d in (env.get("PATH") or "").split(";") if d]
        for folder in folders:
            if folder + "\\codex.exe" in exe:
                return folder + "\\codex.exe", False, False
        shim = any(folder + "\\" + name in exe for folder in folders for name in ("codex.cmd", "codex.ps1"))
        return None, shim, False
    candidates = [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                  home + "/.npm-global/bin/codex"]
    if env.get("NPM_CONFIG_PREFIX"):
        candidates.append(env["NPM_CONFIG_PREFIX"].rstrip("/") + "/bin/codex")
    for c in candidates:
        if c in exe:
            return c, False, False
    # The login shell may print a banner first: its answer is the last non-empty line, and it counts only as an absolute
    # path to an installed file named exactly codex.
    lines = [ln.strip() for ln in (login_shell or "").splitlines() if ln.strip()]
    answer = lines[-1] if lines else ""
    if answer.startswith("/") and answer in exe and answer.rsplit("/", 1)[-1] == "codex":
        return answer, False, True
    return None, False, True


def parse_version(text):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", text)
    return [int(m.group(1)), int(m.group(2)), int(m.group(3))] if m else None


def check_version(version, minimum):
    if version is None or minimum is None:
        return "unknown"
    return "ok" if version >= minimum else "old"


def login_state(exit_code, stdout, stderr=""):
    """Only the exit code decides the state. The mode is read from the text, stdout then stderr joined (probe of
    codex-cli 0.165.0, 2026-10-29: the sign-in words can be on stderr), by fixed substrings, and only when signed in."""
    if exit_code is None:
        return {"state": "unknown", "mode": None}
    if exit_code != 0:
        return {"state": "signedOut", "mode": None}
    text = (stdout + "\n" + stderr).lower()
    mode = "chatgpt" if "chatgpt" in text else "api_key" if "api key" in text else "unknown"
    return {"state": "signedIn", "mode": mode}


def check_args():
    print("expected-args.json")
    data = load("expected-args.json")
    check("base", data["base"], BASE)
    check("the shell-off set", data["shellOff"], SHELL_OFF)
    check("the model rule", data["modelPattern"], MODEL_PATTERN)
    for c in data["cases"]:
        got = build_args(c["level"], c["model"], c["images"])
        check(c["name"], got, c["expect"])
        if "cwd" in c:
            check(c["name"] + " (cwd)", turn_cwd(c["level"], c.get("folder")), c["cwd"])
        if "modelLength" in c:
            check(c["name"] + " (model length)", len(c["model"]), c["modelLength"])
        if isinstance(got, list):
            forbidden = [p for p in (data["chatFolder"], c.get("folder")) if p]
            check(c["name"] + " (no folder in the arguments)",
                  [p for p in forbidden if any(p in a for a in got)], [])
            check(c["name"] + " (images in the image folder)",
                  all(p.startswith(data["imageFolder"] + "/") for p in c["images"]), True)


# ── the environment ──────────────────────────────────────────────────────────────

def check_env():
    print("expected-env.json")
    data = load("expected-env.json")
    check("the stripped names", data["stripped"],
          ["OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORG_ID", "OPENAI_PROJECT_ID"])
    check("the kept names survive", clean_env({k: "x" for k in data["kept"]}, "mac"),
          {k: "x" for k in data["kept"]})
    for c in data["cases"]:
        check(c["name"], clean_env(c["base"], c["platform"]), c["expect"])


# ── where codex is looked for ────────────────────────────────────────────────────

def check_locator():
    print("locator-cases.json")
    for c in load("locator-cases.json")["cases"]:
        got = locate(c["platform"], c["home"], c["env"], c["executables"], c["loginShell"])
        check(c["name"], got, (c["expect"], c["shimOnly"], c["loginShellCalled"]))


# ── versions and sign-in state ───────────────────────────────────────────────────

def check_versions():
    print("versions.json")
    data = load("versions.json")
    for c in data["parse"]:
        check(f"parse {c['text']!r}", parse_version(c["text"]), c["expect"])
    for c in data["check"]:
        minimum = c.get("minimum", data["minimum"])
        check(f"check {c['version']} against {minimum}", check_version(c["version"], minimum), c["expect"])


def check_login():
    print("login-status.json")
    for c in load("login-status.json")["cases"]:
        check(c["name"], login_state(c["exit"], c["stdout"], c.get("stderr", "")), c["expect"])


def check_auth_guard():
    """The guard counts an open of auth.json by str, bytes or PathLike once each, and nothing else."""
    global FAILURES, _probing
    print("the auth.json guard (self-test)")
    saved = FAILURES
    FAILURES = 0
    _probing = True
    try:
        with tempfile.TemporaryDirectory() as tmp:
            auth = os.path.join(tmp, "auth.json")
            notes = os.path.join(tmp, "notes.txt")
            staged = os.path.join(tmp, "staged")
            with open(staged, "w", encoding="utf-8"):
                pass
            os.rename(staged, auth)  # a rename is not an open, so the file is created without tripping the guard
            counted = []
            for path in (auth, os.fsencode(auth), pathlib.Path(auth)):
                before = FAILURES
                with open(path, "rb"):
                    pass
                counted.append(FAILURES - before)
            before = FAILURES
            with open(notes, "w", encoding="utf-8"):
                pass
            other = FAILURES - before
    finally:
        _probing = False
        FAILURES = saved
    check("each str, bytes and PathLike path to an auth.json is counted once", counted, [1, 1, 1])
    check("another file is not counted", other, 0)


# ── what a turn means at each level (Task 2) ────────────────────────────────────

# No real person's path may appear. The Task 1 fixtures use stand-in homes (zoe, Zoe), and the model-length cases
# use a run of letters; those exact strings are the allow-list.
PRIVATE_PATH = re.compile(r"/Users/\w+|/home/\w+|[A-Za-z]:\\+Users\\+\w+")
ALLOWED_PATHS = {"/Users/zoe", "/home/zoe", "C:/Users/Zoe"}  # backslashes read as "/" before the lookup
ALLOWED_KEYS = {"abcdefgh" * 8, "abcdefgh" * 8 + "i"}  # the 64- and 65-character model names in expected-args.json
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[a-z]{2,}")
KEY_LIKE = re.compile(r"\bsk-[A-Za-z0-9_-]{8,}|\bgh[pousr]_[A-Za-z0-9]{8,}|\beyJ[A-Za-z0-9_-]{10,}|[A-Za-z0-9_-]{32,}")
PLACEHOLDER = re.compile(r"__[A-Z]+(?:_\d+)?__")
TOOL_ITEMS = {"command_execution", "web_search", "mcp_tool_call", "file_change"}


def reset_time(epoch, locale):
    # UTC only, as the fixture: English is 12-hour, the others 24-hour.
    d = datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc)
    if locale.startswith("en"):
        return f"{d.hour % 12 or 12}:{d.minute:02d} {'am' if d.hour < 12 else 'pm'}"
    return f"{d.hour:02d}:{d.minute:02d}"


def copy_text(code, resets=None, locale="en_US"):
    """The words for a code. A plan limit with a reset time says when it resets, in the viewer's locale."""
    if code == "nm_plan_limit" and resets is not None:
        return f"Your OpenAI plan's limit resets at {reset_time(resets, locale)}."
    for c in load("copy.json")["cases"]:
        if c["code"] == code and c.get("resetsAt") is None:
            return c["text"]
    raise KeyError(code)


def model_chip(mode):
    return {"chatgpt": "OpenAI · your plan", "api_key": "OpenAI · API key in Codex"}.get(mode, "OpenAI · Codex")


def folder_name(folder):
    return re.split(r"[/\\]", folder.rstrip("/\\"))[-1] or folder[:1]


def level_chip(level, folder):
    words = {"chat": "Chat only", "none": "No tools"}[level]
    if level == "chat" or not folder:
        return words
    return f"{words} · {folder_name(folder)}"


def _object(line):
    """The JSON object on a line, or None when the line is not one (such lines are skipped)."""
    try:
        ev = json.loads(line)
    except ValueError:
        return None
    return ev if isinstance(ev, dict) else None


def _shape(ev):
    item = ev.get("item")
    is_item = isinstance(item, dict)
    return (ev.get("type"), item.get("type") if is_item else None, tuple(sorted(ev)),
            tuple(sorted(item)) if is_item else None)


def _classify(text, where, copy):
    """The code for a failure text by copy.json's match table, or None when nothing matches."""
    if not isinstance(text, str):
        return None
    for m in copy["match"]:
        if m["in"] == where and any(s in text for s in m["contains"]):
            return m["code"]
    return None


def _thread_id(ev):
    # Order-free (Swift cannot know JSON key order). The contract's key is thread_id. The scrub rule renames it to
    # __ID_1__ in the recordings (rule 6), so the id is otherwise the one key besides "type", when there is exactly one.
    if isinstance(ev.get("thread_id"), str):
        return ev["thread_id"]
    others = [k for k in ev if k != "type"]
    if len(others) == 1 and isinstance(ev[others[0]], str):
        return ev[others[0]]
    return None


def _usage(usage):
    """The integers of a usage object, bool excluded (a bool is an int in Python); null when it is not an object."""
    if not isinstance(usage, dict):
        return None
    return {k: v for k, v in usage.items() if isinstance(v, int) and not isinstance(v, bool)}


def _fail(code, engine, copy):
    kind = next(c["kind"] for c in copy["cases"] if c["code"] == code)
    return {"engine": engine, "text": "", "steps": [], "finish": None,
            "error": {"kind": kind, "code": code, "resetsAt": None}}


def parse(lines, exit_code, stderr, level):
    """What one Codex run means at a level. Fails closed: the first started or completed item the level does not
    allow ends the turn, even when it never completes."""
    spec = load("levels.json")
    copy = load("copy.json")
    if level not in spec["levels"]:
        return _fail("nm_level_unavailable", None, copy)
    allowed = set(spec["levels"][level]["items"])
    notes = set(spec["notes"])
    cap = spec["stepFieldCap"]
    engine, texts, steps, finish, seen = None, [], [], None, 0
    for line in lines:
        ev = _object(line)
        if ev is None:
            continue
        seen += 1
        t = ev.get("type")
        if t == "thread.started":
            engine = {"threadId": _thread_id(ev), "version": None}
        elif t in ("item.started", "item.completed"):
            item = ev.get("item") if isinstance(ev.get("item"), dict) else {}
            kind = item.get("type")
            if kind in notes:
                continue
            if kind not in allowed:
                return _fail("nm_level_exceeded", engine, copy)
            if t == "item.completed" and kind == "agent_message" and isinstance(item.get("text"), str):
                texts.append(item["text"])
            if t == "item.completed" and kind in spec["stepFields"]:
                field = spec["stepFields"][kind][0]
                value = item.get(field) if isinstance(item.get(field), str) else ""
                state = "done" if item.get("status") == "completed" else "failed"
                steps.append({"kind": spec["stepKinds"][kind], field: value[:cap], "state": state})
        elif t == "turn.completed":
            finish = {"usage": _usage(ev.get("usage"))}
        elif t == "turn.failed":
            err = ev.get("error") if isinstance(ev.get("error"), dict) else {}
            return _fail(_classify(err.get("message"), "message", copy) or "nm_codex_crashed", engine, copy)
        elif t == "error":
            message = ev.get("message")
            if isinstance(message, str) and any(message.startswith(p) for p in spec["retryNotes"]):
                continue
            return _fail(_classify(message, "message", copy) or "nm_codex_crashed", engine, copy)
    if finish is not None:
        return {"engine": engine, "text": "\n\n".join(texts), "steps": steps, "finish": finish, "error": None}
    code = _classify(stderr, "stderr", copy)
    if code:
        return _fail(code, engine, copy)
    if seen == 0 and exit_code == 0:
        return _fail("nm_codex_unreadable", engine, copy)
    return _fail("nm_codex_crashed", engine, copy)


def check_levels():
    print("levels.json")
    doc = load("levels.json")
    check("every stepFields key has a stepKinds name", sorted(doc["stepFields"]), sorted(doc["stepKinds"]))
    spec = doc["levels"]
    check("the offered levels are the ones build_args allows", sorted(k for k, v in spec.items() if v["offered"]),
          sorted(OFFERED_LEVELS))
    for level, v in spec.items():
        if not v["offered"]:
            continue
        args = build_args(level, None, [])
        check(f"{level}: the shell-off set is in the arguments exactly when shellOff",
              all(part in args for part in SHELL_OFF), v["shellOff"])
        check(f"{level}: takes no command, search, file change or MCP call",
              sorted(set(v["items"]) & TOOL_ITEMS), [])


def check_shapes():
    """Every transcript is a copy of a recording (byte for byte), or hand-written from shapes a recording has."""
    print("transcripts/ against recorded/")
    rdir = os.path.join(HERE, "recorded")
    tdir = os.path.join(HERE, "transcripts")
    shapes = set()
    for name in os.listdir(rdir):
        if name.endswith(".jsonl"):
            with open(os.path.join(rdir, name), encoding="utf-8") as f:
                for ln in f.read().splitlines():
                    ev = _object(ln)
                    if ev is not None:
                        shapes.add(_shape(ev))
    levels = load("levels.json")
    unrecorded = levels["unrecordedTypes"]
    unrecorded_events = levels["unrecordedEvents"]
    for name in sorted(os.listdir(tdir)):
        with open(os.path.join(tdir, name), "rb") as f:
            data = f.read()
        twin = os.path.join(rdir, name)
        if os.path.exists(twin):
            with open(twin, "rb") as f:
                check(f"{name} is a copy of recorded/{name}", data == f.read(), True)
            continue
        outside, nonjson = [], 0
        for ln in data.decode("utf-8").splitlines():
            try:
                ev = json.loads(ln)
            except ValueError:
                nonjson += 1
                continue
            if not isinstance(ev, dict):
                outside.append(ln[:60])
                continue
            s = _shape(ev)
            if s in shapes or name in unrecorded.get(s[1], {}).get("files", []) \
                    or name in unrecorded_events.get(s[0], {}).get("files", []):
                continue
            outside.append(f"{s[0]} {s[1]}")
        check(f"{name}: only shapes a recording has, or a named exception", outside, [])
        check(f"{name}: lines that are not JSON", nonjson, 1 if name == "crash.jsonl" else 0)


def check_parse():
    print("expected-parse.json")
    data = load("expected-parse.json")
    for c in data["cases"]:
        with open(os.path.join(HERE, "transcripts", c["transcript"]), encoding="utf-8") as f:
            lines = f.read().splitlines()
        got = parse(lines, c["exit"], c["stderr"], c["level"])
        expect = json.loads(json.dumps(c["expect"]).replace("<cmd200>", "cmd " * 50))
        check(c["name"], got, expect)


def check_copy():
    print("copy.json")
    for c in load("copy.json")["cases"]:
        label = c["code"] + (f" {c['locale']}" if "locale" in c else "")
        check(label, copy_text(c["code"], c.get("resetsAt"), c.get("locale", "en_US")), c["text"])
    check("the unreadable sentence is the spec's", copy_text("nm_codex_unreadable"),
          "NotchMeow can't read this version of the command line tool. Pick another brain.")
    check("the sign-in line opens nothing and names codex login",
          next(c["detail"] for c in load("copy.json")["cases"] if c["code"] == "nm_codex_signed_out"),
          "Open your terminal and run `codex login`. NotchMeow opens nothing.")


def check_labels():
    print("labels.json")
    data = load("labels.json")
    for c in data["modelChip"]:
        check(c["name"], model_chip(c["mode"]), c["expect"])
    for c in data["levelChip"]:
        check(c["name"], level_chip(c["level"], c["folder"]), c["expect"])
    check("the row's own label never says Codex", "Codex" in data["rowLabel"], False)


def check_no_private():
    print("codex/ holds no private path, email or key (reference.py holds the patterns, so it is not read)")
    found = []
    for dirpath, _, names in os.walk(HERE):
        for name in names:
            if dirpath == HERE and name == "reference.py":
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
            rel = os.path.relpath(path, HERE)
            paths = [re.sub(r"\\+", "/", m.group(0)) for m in PRIVATE_PATH.finditer(text)]
            found += [f"{rel}: {p}" for p in paths if p not in ALLOWED_PATHS]
            found += [f"{rel}: {m.group(0)}" for m in EMAIL.finditer(text)]
            found += [f"{rel}: {m.group(0)}" for m in KEY_LIKE.finditer(PLACEHOLDER.sub("", text))
                      if m.group(0) not in ALLOWED_KEYS]
    check("nothing private", found, [])


# ── the fake codex and the sentinel auth.json (Task 3) ───────────────────────────

FAKE = os.path.join(HERE, "fake_codex.py")
ID_ANY = re.compile(r"__ID_\d+__|thread_id|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def _ids_aside(line):
    return ID_ANY.sub("<ID>", line)


def _env(home, extra):
    """A minimal environment for one fake run, with the sentinel HOME (plan, Global Constraints)."""
    env = {"PATH": os.environ.get("PATH", ""), "HOME": home, "LANG": "C.UTF-8"}
    env.update(extra)
    return env


def _fake(args, home, cwd, extra, stdin_text=""):
    return subprocess.run([sys.executable, FAKE, *args], input=stdin_text.encode("utf-8"), stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, cwd=cwd, env=_env(home, extra), timeout=30)


def _sentinel(tmp):
    """A mode-000 auth.json under a fake HOME. Made by rename, so the audit hook never sees an open of it."""
    home = os.path.join(tmp, "home")
    folder = os.path.join(home, ".codex")
    os.makedirs(folder)
    staged = os.path.join(folder, "staged")
    with open(staged, "w", encoding="utf-8"):
        pass
    auth = os.path.join(folder, "auth.json")
    os.rename(staged, auth)
    os.chmod(auth, 0o000)
    return home, auth


def _wait_for_pid(path, seconds=10):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read().strip()
            if text.isdigit():
                return int(text)
        except OSError:
            pass
        time.sleep(0.05)
    return None


def _gone(pid, seconds=5):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        time.sleep(0.05)
    return False


AUTH_NAME = "auth.json"


def guard_fake(text):
    """The fake never names an auth.json. The audit hook above sees only this process, never the fake child (a child
    is a separate process), so this text check is the guard for the child (plan, Global Constraints)."""
    check("fake_codex.py never names an auth.json", AUTH_NAME not in text, True)


def check_fake_guard():
    """The static guard catches a planted name: one counted failure for one planted copy."""
    print("the static auth.json guard on fake_codex.py (self-test)")
    if not os.path.exists(FAKE):
        return
    global FAILURES
    with open(FAKE, encoding="utf-8") as f:
        text = f.read()
    saved = FAILURES
    FAILURES = 0
    planted = text + '\nopen(os.path.join(home, ".codex", "auth.json"), "rb").close()\n'
    with contextlib.redirect_stdout(io.StringIO()):
        guard_fake(planted)
    counted = FAILURES
    FAILURES = saved
    check("a copy with a planted open of an auth.json fails the guard exactly once", counted, 1)


def check_fixture_files():
    print("fake_codex.py: the replay, what it records, the answers, the hang, the refused write, the sentinel")
    if not os.path.exists(FAKE):
        check("fake_codex.py exists", False, True)
        return
    with open(FAKE, encoding="utf-8") as f:
        guard_fake(f.read())
    args = build_args("chat", None, [])
    tdir = os.path.join(HERE, "transcripts")
    chat = os.path.join(tdir, "chat.jsonl")
    # Every transcript is JSON lines except the named lines that are not: crash.jsonl's panic, and the stderr lines the
    # owner's real runs printed into stdout (byte copies of recorded/, kept as recorded; the parser skips them): the
    # rmcp line of shell-off-wants-command.jsonl (re-scrubbed, FINDINGS) and the seven tracing lines of signed-out-exec.
    not_json = {"crash.jsonl": 1, "image.jsonl": 1, "shell-off-wants-command.jsonl": 1, "signed-out-exec.jsonl": 7}
    counts = {}
    for name in sorted(os.listdir(tdir)):
        with open(os.path.join(tdir, name), encoding="utf-8") as f:
            n = sum(1 for ln in f.read().splitlines() if _object(ln) is None)
        if n != not_json.get(name, 0):
            counts[name] = n
    check("every transcript is JSON lines, except the named lines that are not", counts, {})
    with open(os.path.join(HERE, "recorded", "v.txt"), encoding="utf-8") as f:
        recorded_version = f.read()

    with tempfile.TemporaryDirectory(prefix="f3a20-") as tmp:
        home, auth = _sentinel(tmp)
        before = os.stat(auth).st_atime
        work = os.path.join(tmp, "work")
        os.mkdir(work)

        log = os.path.join(tmp, "replay.jsonl")
        run = _fake(args, home, work, {"NM_FAKE_CODEX_LOG": log, "NM_FAKE_CODEX_TRANSCRIPT": chat},
                    stdin_text="Say hello in five words.\n")
        with open(chat, encoding="utf-8") as f:
            want = [_ids_aside(ln) for ln in f.read().splitlines()]
        got = [_ids_aside(ln) for ln in run.stdout.decode("utf-8").splitlines()]
        check("the fake replays chat.jsonl line for line, ids aside", got, want)
        check("the replay exits 0 by default", run.returncode, 0)
        with open(log, encoding="utf-8") as f:
            entry = json.loads(f.readline())
        check("the log records the argv", entry["argv"], args)
        check("the log records the stdin", entry["stdin"], "Say hello in five words.\n")
        check("the log records the environment (the sentinel HOME)", entry["env"].get("HOME"), home)
        check("the log records the working folder", os.path.realpath(entry["cwd"]), os.path.realpath(work))

        run = _fake(["--version"], home, work, {})
        check("--version prints the recorded version when NM_FAKE_CODEX_VERSION is unset",
              run.stdout.decode("utf-8"), recorded_version)
        run = _fake(["--version"], home, work, {"NM_FAKE_CODEX_VERSION": "codex-cli 9.9.9"})
        check("--version prints NM_FAKE_CODEX_VERSION", run.stdout.decode("utf-8"), "codex-cli 9.9.9\n")
        run = _fake(["login", "status"], home, work, {})
        check("login status is signed in by default", (run.returncode, run.stdout.decode("utf-8")),
              (0, "Logged in using ChatGPT\n"))
        run = _fake(["login", "status"], home, work,
                    {"NM_FAKE_CODEX_LOGIN_EXIT": "1", "NM_FAKE_CODEX_LOGIN_STDOUT": "Not logged in"})
        check("login status takes NM_FAKE_CODEX_LOGIN_EXIT and NM_FAKE_CODEX_LOGIN_STDOUT",
              (run.returncode, run.stdout.decode("utf-8")), (1, "Not logged in\n"))
        run = _fake(["login", "status"], home, work,
                    {"NM_FAKE_CODEX_LOGIN_STREAM": "stderr", "NM_FAKE_CODEX_LOGIN_STDOUT": "Logged in using ChatGPT"})
        check("login status with NM_FAKE_CODEX_LOGIN_STREAM=stderr prints the line on stderr only",
              (run.returncode, run.stdout.decode("utf-8"), run.stderr.decode("utf-8")),
              (0, "", "Logged in using ChatGPT\n"))
        # Pictures: one --image=<path> each, the prompt's `-` last. The bare `--image <path>` form and a picture named
        # `-` are refused by the fake, so a Swift argv in the old form fails every provider run.
        run = _fake(["exec", "--sandbox", "read-only", "--image=/x/one.png", "-"], home, work, {}, stdin_text="hi\n")
        check("the fake takes --image=<path> and reads the prompt from the dash", run.returncode, 0)
        run = _fake(["exec", "--sandbox", "read-only", "--image", "/x/one.png", "-"], home, work, {}, stdin_text="hi\n")
        check("the fake refuses the bare --image form (exit 2)", run.returncode, 2)
        run = _fake(["exec", "--sandbox", "read-only", "--image=-", "-"], home, work, {}, stdin_text="hi\n")
        check("the fake refuses a picture named - (exit 2)", run.returncode, 2)

        pidfile = os.path.join(tmp, "child.pid")
        hung = subprocess.Popen([sys.executable, FAKE, *args], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, cwd=work,
                                env=_env(home, {"NM_FAKE_CODEX_TRANSCRIPT": chat, "NM_FAKE_CODEX_HANG_AFTER": "1",
                                                "NM_FAKE_CODEX_CHILD_PIDFILE": pidfile}))
        hung.stdin.write(b"hi\n")
        hung.stdin.close()
        child = _wait_for_pid(pidfile)
        hung.terminate()
        try:
            code = hung.wait(timeout=10)
        except subprocess.TimeoutExpired:
            hung.kill()
            code = None
        gone = child is not None and _gone(child)
        if child is not None:
            try:
                os.kill(child, signal.SIGKILL)  # never leave the child behind, whatever the check said
            except OSError:
                pass
        check("HANG_AFTER: a SIGTERM ends the fake and its child with it", (code, gone), (130, True))

        os.chmod(work, 0o500)
        try:
            log3 = os.path.join(tmp, "write.jsonl")
            _fake(args, home, work, {"NM_FAKE_CODEX_LOG": log3, "NM_FAKE_CODEX_TRANSCRIPT": chat,
                                     "NM_FAKE_CODEX_TRY_WRITE": "made.txt"}, stdin_text="write it\n")
            with open(log3, encoding="utf-8") as f:
                writes = [e["write"] for e in map(json.loads, f.read().splitlines()) if "write" in e]
            check("TRY_WRITE in a 0500 folder records a refused write", writes, ["refused"])
            check("TRY_WRITE leaves no made.txt", os.path.exists(os.path.join(work, "made.txt")), False)
        finally:
            os.chmod(work, 0o700)

        check("the sentinel auth.json is still there, mode 000",
              (os.path.exists(auth), oct(os.stat(auth).st_mode & 0o777)), (True, "0o0"))
        if before:
            check("the sentinel auth.json's atime did not change", os.stat(auth).st_atime, before)
        else:
            print("  - the sentinel auth.json's atime is not recorded on this file system, so it is not compared")


CHECKS = [check_auth_guard, check_args, check_env, check_locator, check_versions, check_login,
          check_levels, check_shapes, check_parse, check_copy, check_labels, check_fake_guard, check_fixture_files,
          check_no_private]


def main():
    for fn in CHECKS:
        fn()
    if FAILURES:
        print(f"\n{FAILURES} failure(s)")
        sys.exit(1)
    print("\nAll Codex contract checks passed")


if __name__ == "__main__":
    main()
