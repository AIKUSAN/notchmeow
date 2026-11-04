#!/usr/bin/env bash
# The owner's scripted Projects run (scripts/fake-projects-events.py) is sent to a socket of this test's own, never the app's, and what that socket received is checked:
# the scenarios listed, each scenario's events in the fixture's order, every payload's cwd (and session_id, except the Codex event's), the home folder expanded,
# --print sending nothing, and the refusals (an unknown scenario, a speed of 0, an unreachable socket). Nothing here launches or touches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
SCEN="tests/fixtures/mac/projects-scenarios.json"
SOCK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nmp.XXXXXX")"
[ "${#SOCK_DIR}" -le 80 ] || { rm -rf "$SOCK_DIR"; SOCK_DIR="$(mktemp -d /tmp/nmp.XXXXXX)"; }   # a socket path holds 103 bytes
SERVER=""
trap '[ -z "$SERVER" ] || { kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null; } || true; rm -rf "$SOCK_DIR"' EXIT

python3 tests/kitten_socket_server.py "$SOCK_DIR/s" "$SOCK_DIR/received.jsonl" &
SERVER=$!
for _ in $(seq 1 50); do [ -f "$SOCK_DIR/received.jsonl" ] && break; sleep 0.1; done   # the server makes this file after it listens
[ -S "$SOCK_DIR/s" ] || { echo "the test socket did not come up"; exit 1; }

fail=0
check() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1"; echo "    got:      $2"; echo "    expected: $3"; fail=1; fi; }
# runs the script with the arguments, its output in $SOCK_DIR/out.txt; prints the exit code
run() { local rc=0; python3 -I scripts/fake-projects-events.py "$@" > "$SOCK_DIR/out.txt" 2>&1 || rc=$?; echo "$rc"; }
# the event names the fixture scripts for a scenario (or all, in file order): the expected values come from the fixture, not from the script
fixture_names() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); n=list(d["scenarios"]) if sys.argv[2]=="all" else [sys.argv[2]]; print(" ".join(s["event"]["hook_event_name"] for x in n for s in d["scenarios"][x]["steps"] if s.get("event")))' "$SCEN" "$1"; }
received() { python3 -I -c 'import json,sys; print(" ".join(json.loads(l)["hook_event_name"] for l in open(sys.argv[1]) if l.strip()))' "$SOCK_DIR/received.jsonl"; }
# yes when every received payload carries the key (and there is at least one)
all_have() { python3 -I -c 'import json,sys; ps=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print("yes" if ps and all(p.get(sys.argv[2]) for p in ps) else "no")' "$SOCK_DIR/received.jsonl" "$1"; }
# how many received payloads have this cwd, and how many start with a literal ~
count_cwd() { python3 -I -c 'import json,sys; ps=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print(sum(p.get("cwd")==sys.argv[2] for p in ps))' "$SOCK_DIR/received.jsonl" "$1"; }
count_tilde() { python3 -I -c 'import json,sys; ps=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print(sum(str(p.get("cwd","")).startswith("~") for p in ps))' "$SOCK_DIR/received.jsonl"; }
fixture_tilde() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for s in d["scenarios"]["collide-and-home"]["steps"] if s.get("event") and s["event"].get("cwd")=="~"))' "$SCEN"; }

echo "the five scenarios are listed"
check "--list names them in file order" "$(python3 -I scripts/fake-projects-events.py --list | awk '{print $1}' | paste -sd' ' -)" "two-projects claude-app-wait collide-and-home other-agent end"

echo "each scenario sends its events in order, through the test socket"
for name in two-projects claude-app-wait collide-and-home other-agent end; do
  : > "$SOCK_DIR/received.jsonl"
  rc=$(run --scenario "$name" --speed 100000 --sock "$SOCK_DIR/s")
  check "$name: exit 0" "$rc" "0"
  check "$name: the events, in order" "$(received)" "$(fixture_names "$name")"
  check "$name: every payload carries a cwd" "$(all_have cwd)" "yes"
  # the other-agent scenario's Codex event carries a cwd but no session_id (the fixture), so only the Claude sessions are checked for one
  if [ "$name" != other-agent ]; then check "$name: and a session_id" "$(all_have session_id)" "yes"; fi
done

echo "the other agent's event is not a Claude session"
: > "$SOCK_DIR/received.jsonl"
rc=$(run --scenario other-agent --speed 100000 --sock "$SOCK_DIR/s")
check "other-agent: the payload says codex" "$(python3 -I -c 'import json,sys; print(" ".join(sorted({json.loads(l).get("nm_agent","") for l in open(sys.argv[1]) if l.strip()})))' "$SOCK_DIR/received.jsonl")" "codex"

echo "--scenario all runs the five in file order"
: > "$SOCK_DIR/received.jsonl"
rc=$(run --scenario all --speed 100000 --sock "$SOCK_DIR/s")
check "all: exit 0" "$rc" "0"
check "all: the events of the five, in file order" "$(received)" "$(fixture_names all)"

echo "a home folder is expanded, and no literal ~ is sent"
: > "$SOCK_DIR/received.jsonl"
rc=$(run --scenario collide-and-home --speed 100000 --sock "$SOCK_DIR/s")
check "collide-and-home: exit 0" "$rc" "0"
check "collide-and-home: the home steps send this machine's \$HOME" "$(count_cwd "$HOME")" "$(fixture_tilde)"
check "collide-and-home: no cwd starts with a literal ~" "$(count_tilde)" "0"

echo "--print sends nothing"
: > "$SOCK_DIR/received.jsonl"
rc=$(run --print --scenario two-projects --sock "$SOCK_DIR/s")
check "--print: exit 0" "$rc" "0"
check "--print: nothing reaches the socket" "$(wc -l < "$SOCK_DIR/received.jsonl" | tr -d ' ')" "0"
check "--print: the payloads are printed" "$(grep -c '"hook_event_name"' "$SOCK_DIR/out.txt")" "$(fixture_names two-projects | wc -w | tr -d ' ')"

echo "the socket it sends to is printed first, so the owner sees which app they hit"
: > "$SOCK_DIR/received.jsonl"
rc=$(run --scenario end --speed 100000 --sock "$SOCK_DIR/s")
check "the first line names the target socket" "$(head -n 1 "$SOCK_DIR/out.txt")" "sending to $SOCK_DIR/s"
rc=$(run --print --scenario end --sock "$SOCK_DIR/s")
check "--print sends nothing, so it names no target" "$(grep -c 'sending to' "$SOCK_DIR/out.txt" || true)" "0"

echo "a card nobody answers is a stop, not an unreachable app"
# a socket that takes every event and answers all but a PermissionRequest, which it holds open like a card still waiting for the click
python3 -I -c '
import json, os, socket, sys, threading, time
path = sys.argv[1]
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); srv.bind(path); srv.listen(8)
def one(conn):
    raw = b""
    while not raw.endswith(b"\n"):
        chunk = conn.recv(4096)
        if not chunk: break
        raw += chunk
    if json.loads(raw).get("hook_event_name") == "PermissionRequest": time.sleep(5)
    else: conn.sendall(b"{\"ok\":true}\n")
    conn.close()
while True:
    conn, _ = srv.accept(); threading.Thread(target=one, args=(conn,), daemon=True).start()
' "$SOCK_DIR/held" &
HELD=$!
for _ in $(seq 1 50); do [ -S "$SOCK_DIR/held" ] && break; sleep 0.1; done
rc=$(run --scenario claude-app-wait --speed 100000 --permission-timeout 0.3 --sock "$SOCK_DIR/held")
kill "$HELD" 2>/dev/null; wait "$HELD" 2>/dev/null || true
check "claude-app-wait against a card that is never answered: exit 3" "$rc" "3"
check "it says the card is still waiting, and does not say the socket could not be reached" "$(grep -c 'card still waiting for an answer, stopping' "$SOCK_DIR/out.txt")/$(grep -c 'could not reach' "$SOCK_DIR/out.txt" || true)" "1/0"

echo "the refusals"
check "--scenario nope: exit 2" "$(run --scenario nope --sock "$SOCK_DIR/s")" "2"
check "--speed 0 is refused: exit 2" "$(run --print --speed 0)" "2"
check "an unreachable socket is an error, not a hang: exit 1" "$(run --scenario end --speed 100000 --sock "$SOCK_DIR/nothing")" "1"

[ "$fail" = 0 ] && echo && echo "All tests passed." || { echo; echo "tests failed."; exit 1; }
