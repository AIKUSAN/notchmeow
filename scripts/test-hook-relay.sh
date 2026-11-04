#!/usr/bin/env bash
# The hook relay's answers on stdout, run for real: the two Python relays embedded in HookServer.swift (GitHub and App Store) are cut out
# of the Swift source, written to a temporary folder and run with python3 in a home folder of their own, so no socket is reachable (the
# relay never blocks: with the app unreachable it still prints its answer). Antigravity reads "{}" on PreToolUse as a denial, so it is
# answered {"decision":"ask"}: its own prompt stays, and NotchMeow never allows a tool by itself.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-hook-relay.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/home"

python3 -I - "$TEST_DIR" <<'PY'
import re, sys
out = sys.argv[1]
src = open("NotchBuddy/Sources/App/HookServer.swift", encoding="utf-8").read()
for name, label in (("nbHookPythonGitHub", "github"), ("nbHookPythonAppStore", "appstore")):
    m = re.search(r'private let ' + name + r' = """\n(.*?)\n"""', src, re.S)
    if not m:
        sys.exit("cannot find " + name + " in HookServer.swift")
    body = m.group(1).replace("\\\\", "\\")   # Swift's escape for one backslash
    open(f"{out}/nm-hook-{label}.py", "w", encoding="utf-8").write(body + "\n")
PY

pass=0; fail=0
# relay <label> <stdin JSON> <args...>: prints what the relay wrote on stdout
relay() {
    local label="$1" input="$2"; shift 2
    printf '%s' "$input" | HOME="$TEST_DIR/home" python3 -I "$TEST_DIR/nm-hook-$label.py" "$@" 2>/dev/null || true
}
expect() {   # expect <name> <got> <want>
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "✓ $1"; else fail=$((fail + 1)); echo "✗ $1: got [$2], wanted [$3]"; fi
}
for label in github appstore; do
    tool='{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/tmp/p","tool_name":"run_command","tool_input":{"command":"ls"}}'
    expect "$label: antigravity PreToolUse is asked, never allowed" "$(relay $label "$tool" --agent antigravity PreToolUse)" '{"decision":"ask"}'
    expect "$label: antigravity BeforeTool (its other spelling) is asked too" "$(relay $label '{"hook_event_name":"BeforeTool","session_id":"s1","toolCall":{"name":"x","args":{}}}' --agent antigravity)" '{"decision":"ask"}'
    for ev in PostToolUse PreInvocation PostInvocation Stop; do
        expect "$label: antigravity $ev keeps the empty answer" "$(relay $label "{\"hook_event_name\":\"$ev\",\"session_id\":\"s1\"}" --agent antigravity $ev)" '{}'
    done
    expect "$label: gemini PreToolUse keeps the empty answer" "$(relay $label "$tool" --agent gemini PreToolUse)" '{}'
    expect "$label: Claude Code PreToolUse stays silent" "$(relay $label "$tool" PreToolUse)" ''
done
# The entrypoint tag (upstream 344dc12): a Claude Code session from the Claude desktop app (CLAUDE_CODE_ENTRYPOINT=claude-desktop) is tagged nm_agent "claude-desktop" when no --agent was
# given; an explicit --agent wins; any other entrypoint stays untagged. The test listens on the socket the relay opens and reads what it sent. (A socket path is limited to 104 bytes: short home.)
SOCK_HOME="$(mktemp -d /tmp/nmr.XXXXXX)"
trap 'rm -rf "$TEST_DIR" "$SOCK_HOME"' EXIT
cat > "$TEST_DIR/tag-test.py" <<'PY'
import json, os, socket, subprocess, sys
test_dir, home = sys.argv[1], sys.argv[2]
SOCKS = {"github": "Library/Application Support/NotchMeow/nm.sock",
         "appstore": "Library/Containers/io.github.aikusan.notchmeow.store/Data/nm.sock"}
CASES = [("claude-desktop", [], "claude-desktop", "a desktop session is tagged claude-desktop"),
         ("claude-desktop", ["--agent", "gemini"], "gemini", "an explicit --agent wins over the entrypoint"),
         ("cli", [], None, "the CLI entrypoint is untagged"),
         ("vscode", [], None, "the VS Code entrypoint is untagged"),
         ("Claude-Desktop", [], None, "a look-alike entrypoint is untagged"),
         (None, [], None, "no entrypoint is untagged")]
for label, rel in SOCKS.items():
    path = os.path.join(home, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for entry, extra, want, name in CASES:
        if os.path.exists(path): os.remove(path)
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(path); srv.listen(1); srv.settimeout(5)
        env = {"HOME": home, "PATH": os.environ.get("PATH", "")}
        if entry is not None: env["CLAUDE_CODE_ENTRYPOINT"] = entry
        p = subprocess.Popen([sys.executable, "-I", f"{test_dir}/nm-hook-{label}.py", *extra, "Stop"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
        p.stdin.write(b'{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp/p"}'); p.stdin.close()
        got = "no connection"
        try:
            conn, _ = srv.accept(); conn.settimeout(5)
            buf = b""
            while b"\n" not in buf:
                chunk = conn.recv(4096)
                if not chunk: break
                buf += chunk
            got = json.loads(buf.decode()).get("nm_agent")
        except Exception as e:
            got = repr(e)
        p.wait(10); srv.close()
        print(("PASS " if got == want else "FAIL ") + f"{label}: {name} (got {got!r})")
PY
# (the script is written to a file first: bash 3.2 mangles a heredoc inside a process substitution)
while IFS= read -r line; do
    case "$line" in
        PASS*) pass=$((pass + 1)); echo "✓ ${line#PASS }" ;;
        FAIL*) fail=$((fail + 1)); echo "✗ ${line#FAIL }" ;;
    esac
done < <(python3 -I "$TEST_DIR/tag-test.py" "$TEST_DIR" "$SOCK_HOME")

# The plan gauge's relay (Settings → Agents → Plan usage): Claude Code runs `nm-hook --statusline` with its status line JSON on stdin. The relay must hand NotchMeow the rate_limits (and nothing else of
# the session), and keep the user's own status line working: the command saved in statusline-previous.json (next to the relay) gets the same stdin and its output is what Claude Code shows.
cat > "$TEST_DIR/statusline-test.py" <<'PY'
import json, os, shutil, socket, subprocess, sys
test_dir, home = sys.argv[1], sys.argv[2]
SOCKS = {"github": "Library/Application Support/NotchMeow/nm.sock",
         "appstore": "Library/Containers/io.github.aikusan.notchmeow.store/Data/nm.sock"}
LIMITS = {"five_hour": {"used_percentage": 42.5, "resets_at": 1900000000}, "seven_day": {"used_percentage": 10, "resets_at": 1900500000}}
PAYLOAD = json.dumps({"session_id": "s1", "cwd": "/Users/me/secret-project", "transcript_path": "/Users/me/t.jsonl", "model": {"id": "m"}, "rate_limits": LIMITS}).encode()
def run(label, rel, previous):
    relay_dir = os.path.join(test_dir, "sl-" + label + ("-prev" if previous else ""))
    os.makedirs(relay_dir, exist_ok=True)
    shutil.copy(f"{test_dir}/nm-hook-{label}.py", relay_dir)
    if previous:
        json.dump({"type": "command", "command": "cat > /dev/null; echo previous-line"}, open(os.path.join(relay_dir, "statusline-previous.json"), "w"))
    path = os.path.join(home, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path): os.remove(path)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path); srv.listen(1); srv.settimeout(5)
    p = subprocess.Popen([sys.executable, "-I", os.path.join(relay_dir, f"nm-hook-{label}.py"), "--statusline"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env={"HOME": home, "PATH": os.environ.get("PATH", "")})
    p.stdin.write(PAYLOAD); p.stdin.close()
    sent = None
    try:
        conn, _ = srv.accept(); conn.settimeout(5)
        buf = b""
        while b"\n" not in buf:
            chunk = conn.recv(4096)
            if not chunk: break
            buf += chunk
        sent = json.loads(buf.decode())
        try: conn.sendall(b'{"ok":true}\n')   # the relay does not wait for the answer: it may be gone (the app ignores SIGPIPE for the same reason)
        except OSError: pass
        conn.close()
    except Exception as e:
        sent = repr(e)
    out = p.stdout.read(); p.wait(10); srv.close()
    return sent, out
for label, rel in SOCKS.items():
    sent, out = run(label, rel, previous=False)
    ok = isinstance(sent, dict) and sent.get("nm_kind") == "statusline" and sent.get("rate_limits") == LIMITS
    print(("PASS " if ok else "FAIL ") + f"{label}: the status line relay sends the rate limits as nm_kind statusline (got {sent!r})")
    print(("PASS " if isinstance(sent, dict) and set(sent) == {"nm_kind", "session_id", "rate_limits"} else "FAIL ") + f"{label}: and nothing else of the session (no cwd, no transcript path, no model)")
    print(("PASS " if out == b"" else "FAIL ") + f"{label}: with no status line of the user's, Claude Code is shown nothing (got {out!r})")
    sent, out = run(label, rel, previous=True)
    print(("PASS " if out == b"previous-line\n" else "FAIL ") + f"{label}: the user's own status line still runs and is what Claude Code shows (got {out!r})")
    print(("PASS " if isinstance(sent, dict) and sent.get("rate_limits") == LIMITS else "FAIL ") + f"{label}: and the rate limits still reach NotchMeow")
PY
while IFS= read -r line; do
    case "$line" in
        PASS*) pass=$((pass + 1)); echo "✓ ${line#PASS }" ;;
        FAIL*) fail=$((fail + 1)); echo "✗ ${line#FAIL }" ;;
    esac
done < <(python3 -I "$TEST_DIR/statusline-test.py" "$TEST_DIR" "$SOCK_HOME")

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
