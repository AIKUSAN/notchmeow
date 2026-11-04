#!/usr/bin/env python3
"""Reference implementation of the Claude Code engine's contract (E3).

Every fixture in this folder is run against a small, obviously-correct Python model: the command line per
level and turn, the cleaned environment, what a transcript means, `claude auth status`, versions, where
claude is looked for, which hook payloads belong to a chat, and the words on the chips. It also runs the
fake `claude` once to prove it replays what it is given. Both apps implement the same behaviour natively;
this file is the tie-breaker when they disagree. It never runs the real `claude`.
"""
import datetime
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading

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


# ── the command line ─────────────────────────────────────────────────────────────

BASE = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--include-partial-messages"]
READ_TOOLS = "Read,Grep,Glob,WebSearch,WebFetch"
CHAT_TOOLS = "WebSearch,WebFetch"
# The no-tools level (quick actions): an empty --tools list, nothing allowed, every MCP server blocked.
NONE_ARGS = ["--safe-mode", "--tools", "", "--disallowedTools", "WebSearch,WebFetch,mcp__*", "--permission-mode",
             "dontAsk"]
# The tools `init` must report for a level that checks them. Other levels are not in this table and never check.
INIT_TOOLS = {"none": []}
REFUSED_ERROR = {"kind": "bad_request", "code": "nm_tools_present", "resetsAt": None}


def build_args(platform, level, model, resume, session_id):
    args = BASE + (["--resume", session_id] if resume else ["--session-id", session_id]) + ["--model", model]
    if level == "none":
        return args + NONE_ARGS
    if level == "chat":
        return args + ["--safe-mode", "--tools", CHAT_TOOLS, "--allowedTools", CHAT_TOOLS,
                       "--disallowedTools", "mcp__*", "--permission-mode", "dontAsk"]
    if level == "read":
        return args + ["--safe-mode", "--tools", READ_TOOLS, "--allowedTools", READ_TOOLS,
                       "--permission-mode", "dontAsk",
                       "--settings", '{"permissions":{"blockReadsOutsideWorkingDirectories":true}}']
    args += ["--permission-mode", "default"]
    if platform != "windows":
        args += ["--settings", '{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":false}}']
    return args


def check_args():
    print("expected-args.json")
    data = load("expected-args.json")
    check("models", data["models"], ["sonnet", "opus", "haiku"])
    for c in data["cases"]:
        check(c["name"], build_args(c["platform"], c["level"], c["model"], c["resume"], c["sessionId"]), c["argv"])
        check(c["name"] + " (the folder is not in the arguments)",
              any(c.get("folder", "\0") in a for a in c["argv"]), False)


# ── the environment ──────────────────────────────────────────────────────────────

def clean_env(base, platform, stripped, prefixes):
    ci = platform == "windows"
    names = {n.upper() if ci else n for n in stripped}
    pre = [p.upper() if ci else p for p in prefixes]
    out = {}
    for k, v in base.items():
        key = k.upper() if ci else k
        if key in names or any(key.startswith(p) for p in pre):
            continue
        out[k] = v
    return out


def check_env():
    print("expected-env.json")
    data = load("expected-env.json")
    for c in data["cases"]:
        check(c["name"], clean_env(c["base"], c["platform"], data["stripped"], data["strippedPrefixes"]), c["expect"])


# ── what a transcript means ──────────────────────────────────────────────────────

STEP_FIELDS = ["command", "file_path", "path", "query", "pattern", "url"]
STEP_FIELD_CAP = 200
KEY_SOURCES = {"none": "plan", "oauth": "plan", "user": "api_key", "project": "api_key", "org": "api_key",
               "temporary": "api_key"}


def step_input(raw):
    out = {}
    for k in STEP_FIELDS:
        v = raw.get(k) if isinstance(raw, dict) else None
        if isinstance(v, str):
            out[k] = v[:STEP_FIELD_CAP]
    return out


def shows_something(ev):
    """An event that would put something on screen (or run a tool) before the tools are checked."""
    t = ev.get("type")
    if t == "stream_event":
        return (ev.get("event") or {}).get("type") in ("content_block_start", "content_block_delta")
    if t in ("assistant", "user"):
        want = "tool_use" if t == "assistant" else "tool_result"
        content = (ev.get("message") or {}).get("content")
        return any(isinstance(b, dict) and b.get("type") == want for b in (content if isinstance(content, list) else []))
    return False


def refused(engine):
    return {"engine": engine, "text": "", "steps": [], "finish": None, "error": dict(REFUSED_ERROR)}


def parse(lines, exit_code, stderr, platform="mac", level="chat"):
    engine, text, steps, order = None, "", {}, []
    needs_break = False
    result, assistant_error, rejected, retried = None, None, None, False
    expect_tools = INIT_TOOLS.get(level)
    checking = expect_tools is not None
    vetted = False
    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if not isinstance(ev, dict):
            continue
        t = ev.get("type")
        if checking and not vetted and shows_something(ev):
            return refused(engine)
        if t == "system" and ev.get("subtype") == "init":
            engine = {"sessionId": ev.get("session_id"), "model": ev.get("model"),
                      "paidBy": KEY_SOURCES.get(ev.get("apiKeySource"), "unknown"),
                      "version": ev.get("claude_code_version")}
            if checking and not vetted:
                tools = ev.get("tools")
                if not (isinstance(tools, list) and all(isinstance(x, str) for x in tools) and tools == expect_tools):
                    return refused(engine)
                vetted = True
        elif t == "system" and ev.get("subtype") == "api_retry":
            retried = True
        elif t == "stream_event":
            e = ev.get("event") or {}
            et = e.get("type")
            if et == "message_start":
                needs_break = needs_break or text != ""
            elif et == "content_block_start":
                block = e.get("content_block") or {}
                if block.get("type") == "tool_use" and isinstance(block.get("id"), str):
                    needs_break = needs_break or text != ""
                    if block["id"] not in steps:
                        order.append(block["id"])
                    steps[block["id"]] = {"id": block["id"], "tool": block.get("name", ""), "input": {},
                                          "state": "running"}
                elif block.get("type") == "text" and needs_break and text != "":
                    text += "\n\n"
                    needs_break = False
            elif et == "content_block_delta":
                d = e.get("delta") or {}
                if d.get("type") == "text_delta" and isinstance(d.get("text"), str):
                    if needs_break and text != "":
                        text += "\n\n"
                    needs_break = False
                    text += d["text"]
        elif t == "assistant":
            if isinstance(ev.get("error"), str):
                assistant_error = ev["error"]
            for block in (ev.get("message") or {}).get("content") or []:
                if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("id") in steps:
                    steps[block["id"]]["input"] = step_input(block.get("input"))
        elif t == "user":
            content = (ev.get("message") or {}).get("content")
            for block in content if isinstance(content, list) else []:
                if isinstance(block, dict) and block.get("type") == "tool_result" and block.get("tool_use_id") in steps:
                    steps[block["tool_use_id"]]["state"] = "failed" if block.get("is_error") else "done"
        elif t == "rate_limit_event":
            info = ev.get("rate_limit_info") or {}
            if info.get("status") == "rejected":
                rejected = info.get("resetsAt") if isinstance(info.get("resetsAt"), (int, float)) else 0
        elif t == "result":
            result = ev
    out = {"engine": engine, "text": text, "steps": [steps[i] for i in order], "finish": None, "error": None}
    if result is not None and not result.get("is_error") and result.get("subtype") == "success":
        out["finish"] = "stop"
        return out
    if result is not None and result.get("subtype") == "error_max_turns":
        out["finish"] = "length"
        return out
    words = ((result or {}).get("result") if result is not None else "") or ""
    blob = (words + "\n" + stderr).lower()
    paid = engine["paidBy"] if engine else None

    def failure(kind, code=None, resets=None):
        out["error"] = {"kind": kind, "code": code, "resetsAt": resets}
        return out

    if "git-bash" in blob or "claude_code_git_bash_path" in blob or "git for windows" in blob:
        return failure("bad_request", "nm_needs_git")
    if assistant_error == "authentication_failed" or "not logged in" in blob or "please run /login" in blob:
        return failure("auth", "nm_signed_out")
    if "unknown option" in blob:
        return failure("bad_request", "nm_claude_old")
    if rejected is not None or (assistant_error == "rate_limit" and paid == "plan"):
        return failure("billing", "nm_plan_limit", int(rejected) if rejected else None)
    if assistant_error == "rate_limit":
        return failure("rate_limited")
    if assistant_error == "billing_error":
        return failure("billing", "billing_error")
    if assistant_error == "overloaded":
        return failure("overloaded")
    if assistant_error == "server_error":
        return failure("server")
    if result is not None and (retried or "unable to connect" in blob):
        return failure("unreachable", "nm_claude_offline")
    return failure("interrupted", "nm_claude_crashed")


def check_parse():
    print("expected-parse.json")
    data = load("expected-parse.json")
    for c in data["cases"]:
        with open(os.path.join(HERE, "transcripts", c["transcript"]), encoding="utf-8") as f:
            raw = f.read().replace("__SESSION_ID__", data["sessionId"]).replace("__CWD__", data["cwd"])
        got = parse(raw.splitlines(), c["exit"], c["stderr"], c["platform"], c.get("level", "chat"))
        expect = json.loads(json.dumps(c["expect"]).replace("<sid>", data["sessionId"]))
        check(c["name"], got, expect)


# ── auth status, versions, the locator ───────────────────────────────────────────

def auth_status(exit_code, stdout):
    if exit_code is None:
        return {"state": "unknown", "authMethod": None}
    method = None
    try:
        parsed = json.loads(stdout)
        if isinstance(parsed, dict) and isinstance(parsed.get("authMethod"), str):
            method = parsed["authMethod"]
    except ValueError:
        pass
    if exit_code == 1 or method == "none":
        return {"state": "signedOut", "authMethod": None}
    if exit_code == 0:
        return {"state": "signedIn", "authMethod": method}
    return {"state": "unknown", "authMethod": None}


def parse_version(text):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", text)
    return [int(m.group(1)), int(m.group(2)), int(m.group(3))] if m else None


def check_version(version, minimum):
    if version is None:
        return "unknown"
    return "ok" if version >= minimum else "tooOld"


def check_status_and_versions():
    print("auth-status.json")
    for c in load("auth-status.json")["cases"]:
        check(c["name"], auth_status(c["exit"], c["stdout"]), c["expect"])
    print("versions.json")
    data = load("versions.json")
    for c in data["parse"]:
        check(f"parse {c['text']!r}", parse_version(c["text"]), c["expect"])
    for c in data["check"]:
        check(f"check {c['version']}", check_version(c["version"], data["minimum"]), c["expect"])


def locate(platform, home, env, executables, login_shell):
    """Returns (path or None, shim_only, login_shell_called)."""
    exe = set(executables)
    if platform == "windows":
        markers = load("locator-cases.json")["windowsDesktopMarkers"]
        candidates = [home + "\\.local\\bin\\claude.exe"]
        shim = False
        for d in (env.get("PATH") or "").split(";"):
            if not d:
                continue
            if any(m in d.lower() for m in markers):
                continue
            candidates.append(d.rstrip("\\") + "\\claude.exe")
            shim = shim or (d.rstrip("\\") + "\\claude.cmd") in exe
        for c in candidates:
            if c in exe:
                return c, False, False
        return None, shim, False
    candidates = [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                  home + "/.npm-global/bin/claude"]
    if env.get("NPM_CONFIG_PREFIX"):
        candidates.append(env["NPM_CONFIG_PREFIX"].rstrip("/") + "/bin/claude")
    for c in candidates:
        if c in exe:
            return c, False, False
    lines = [ln.strip() for ln in (login_shell or "").splitlines() if ln.strip()]
    asked = True
    if lines and lines[-1].startswith("/") and lines[-1] in exe:
        return lines[-1], False, asked
    return None, False, asked


def check_locator():
    print("locator-cases.json")
    for c in load("locator-cases.json")["cases"]:
        path, shim, called = locate(c["platform"], c["home"], c["env"], c["executables"], c["loginShell"])
        # An unusual case: nothing earlier exists and the shell had nothing to say: it is still asked.
        check(c["name"], (path, shim, called if c["platform"] != "windows" else False),
              (c["expect"], c["shimOnly"], c["loginShellCalled"]))


# ── hook routing and the chips ───────────────────────────────────────────────────

def route_hook(payload, live):
    sid = payload.get("session_id")
    if isinstance(payload.get("nm_agent"), str) and payload["nm_agent"] != "":
        return "other"
    return "chat" if isinstance(sid, str) and sid != "" and sid in live else "other"


def check_hooks():
    print("hook-routing.json")
    data = load("hook-routing.json")
    for c in data["cases"]:
        check(c["name"], route_hook(c["payload"], set(c.get("live", data["live"]))), c["expect"])


def model_chip(auth_method, paid_by):
    if auth_method == "third_party":
        return "Claude"
    if paid_by == "plan":
        return "Claude · your plan"
    if paid_by == "api_key":
        return "Claude · API key"
    if auth_method in ("claude.ai", "oauth_token"):
        return "Claude · your plan"
    if auth_method in ("api_key", "api_key_helper"):
        return "Claude · API key"
    return "Claude"


def folder_name(folder):
    trimmed = folder.rstrip("/\\")
    if trimmed == "":
        return folder[:1] or ""
    return re.split(r"[/\\]", trimmed)[-1]


def level_chip(level, folder):
    words = {"chat": "Chat only", "read": "Read-only", "agent": "Agent", "none": "No tools"}[level]
    if level in ("chat", "none") or not folder:
        return words
    return f"{words} · {folder_name(folder)}"


def check_labels():
    print("labels.json")
    data = load("labels.json")
    for c in data["modelChip"]:
        check(c["name"], model_chip(c["authMethod"], c["paidBy"]), c["expect"])
    for c in data["levelChip"]:
        check(f"{c['level']} {c['folder']!r}", level_chip(c["level"], c["folder"]), c["expect"])


def reset_time(epoch, tz, locale):
    # The two locales the fixture uses: UTC only, English 12-hour and French 24-hour.
    d = datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc)
    if locale.startswith("en"):
        return f"{d.hour % 12 or 12}:{d.minute:02d} {'am' if d.hour < 12 else 'pm'}"
    return f"{d.hour:02d}:{d.minute:02d}"


def check_copy():
    print("copy.json")
    for c in load("copy.json")["cases"]:
        if c["code"] == "nm_plan_limit" and c.get("resetsAt"):
            text = f"Your Claude plan's limit resets at {reset_time(c['resetsAt'], c['timeZone'], c['locale'])}."
        elif c["code"] == "nm_plan_limit":
            text = "Your Claude plan's limit was reached."
        else:
            text = {"nm_claude_missing": "Claude Code isn't installed.", "nm_signed_out": "Claude Code is signed out.",
                    "nm_claude_old": "Update Claude Code.", "nm_claude_crashed": "Claude stopped unexpectedly.",
                    "nm_claude_offline": "Couldn't reach Claude.",
                    "nm_needs_git": "Claude Code needs Git for Windows.",
                    "nm_folder_missing": "That folder isn't there any more. Pick another one.",
                    "nm_tools_present": "Claude Code started with tools a quick action must not have, so NotchMeow stopped it."}[c["code"]]
        check(f"{c['code']} {c.get('locale', '')}", text, c["text"])


def check_companion_words():
    # The one sentence the chat shows for a refused quick action is owned by the companion contract.
    print("copy.json against tests/fixtures/companion/quick-cases.json")
    with open(os.path.join(HERE, "..", "..", "companion", "quick-cases.json"), encoding="utf-8") as f:
        words = json.load(f)["words"]
    row = next(c for c in load("copy.json")["cases"] if c["code"] == "nm_tools_present")
    check("nm_tools_present text is the companion's words.toolsRefused", row["text"], words["toolsRefused"])


# ── the transcripts and the fake claude ──────────────────────────────────────────

def check_fixture_files():
    print("transcripts/ and the fake claude")
    tdir = os.path.join(HERE, "transcripts")
    for name in sorted(os.listdir(tdir)):
        with open(os.path.join(tdir, name), encoding="utf-8") as f:
            lines = f.read().splitlines()
        bad = 0
        for ln in lines:
            try:
                json.loads(ln)
            except ValueError:
                bad += 1
        check(f"{name}: lines that are not JSON", bad, 1 if name == "crash.jsonl" else 0)
    fake = os.path.join(HERE, "fake_claude.py")
    with tempfile.TemporaryDirectory() as tmp:
        log = os.path.join(tmp, "log.jsonl")
        env = {"PATH": os.environ.get("PATH", ""), "NM_FAKE_CLAUDE_LOG": log,
               "NM_FAKE_CLAUDE_TRANSCRIPT": os.path.join(tdir, "success.jsonl"), "NM_FAKE_CLAUDE_EXIT": "0",
               "CANARY": "kept"}
        sid = "11111111-1111-4111-8111-111111111111"
        run = subprocess.run([sys.executable, fake, "-p", "--session-id", sid, "--model", "sonnet"],
                             input='{"type":"user"}\n', capture_output=True, text=True, cwd=tmp, env=env, timeout=30)
        check("the fake replays the transcript, one line each", len(run.stdout.splitlines()), 11)
        check("the fake fills in the session id", sid in run.stdout and "__SESSION_ID__" not in run.stdout, True)
        entry = json.loads(open(log, encoding="utf-8").read().splitlines()[0])
        check("the fake records argv, stdin and the environment",
              (entry["argv"][:3], entry["stdin"], entry["env"].get("CANARY")),
              (["-p", "--session-id", sid], '{"type":"user"}\n', "kept"))
        version = subprocess.run([sys.executable, fake, "--version"], capture_output=True, text=True, env=env, timeout=30)
        check("the fake's version", version.stdout.strip(), "2.1.211 (Claude Code)")
        status = subprocess.run([sys.executable, fake, "auth", "status"],
                                capture_output=True, text=True, env=dict(env, NM_FAKE_CLAUDE_AUTH_EXIT="1"), timeout=30)
        check("the fake's auth status exit", status.returncode, 1)
        # It can ask for a permission the way the hook relay does, for checking the approval card by hand.
        sock_path = os.path.join(tmp, "nm.sock")
        seen = []

        def serve():
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as srv:
                srv.bind(sock_path)
                srv.listen(1)
                conn, _ = srv.accept()
                with conn:
                    seen.append(json.loads(conn.makefile("r", encoding="utf-8").readline()))
                    conn.sendall(b'{"permissionDecision":"allow"}\n')

        server = threading.Thread(target=serve, daemon=True)
        server.start()
        while not os.path.exists(sock_path):
            pass
        ask_log = os.path.join(tmp, "ask.jsonl")
        subprocess.run([sys.executable, fake, "-p", "--session-id", sid],
                       input="{}\n", capture_output=True, text=True, cwd=tmp, timeout=30,
                       env=dict(env, NM_FAKE_CLAUDE_LOG=ask_log, NM_FAKE_CLAUDE_ASK_SOCKET=sock_path))
        server.join(10)
        check("the fake asks for a permission with its session id",
              (seen[0]["hook_event_name"], seen[0]["session_id"]) if seen else None, ("PermissionRequest", sid))
        entries = [json.loads(line) for line in open(ask_log, encoding="utf-8").read().splitlines()]
        check("and records the answer", entries[-1], {"permission": '{"permissionDecision":"allow"}'})


CHECKS = [check_args, check_env, check_parse, check_status_and_versions, check_locator, check_hooks, check_labels,
          check_copy, check_companion_words, check_fixture_files]


def main():
    for fn in CHECKS:
        fn()
    if FAILURES:
        print(f"\n{FAILURES} failure(s)")
        sys.exit(1)
    print("\nAll Claude Code contract checks passed")


if __name__ == "__main__":
    main()
