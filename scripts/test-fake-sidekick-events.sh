#!/usr/bin/env bash
# The owner's fake sidekick session (scripts/fake-sidekick-events.py) is sent to a socket of this test's own, never the app's, and what that socket received is checked: the events of each scenario in
# order, the high-risk request only in the risk scenario, no payload with a prompt or a command that is not the marked fake. Nothing here launches or touches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-fake-sidekick.XXXXXX")"
SOCK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nmt.XXXXXX")"
[ "${#SOCK_DIR}" -le 80 ] || { rm -rf "$SOCK_DIR"; SOCK_DIR="$(mktemp -d /tmp/nmt.XXXXXX)"; }   # a socket path holds 103 bytes
SERVER=""
trap '[ -z "$SERVER" ] || { kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null; } || true; rm -rf "$TEST_DIR" "$SOCK_DIR"' EXIT

python3 tests/kitten_socket_server.py "$SOCK_DIR/s" "$SOCK_DIR/received.jsonl" &
SERVER=$!
for _ in $(seq 1 50); do [ -S "$SOCK_DIR/s" ] && break; sleep 0.1; done
[ -S "$SOCK_DIR/s" ] || { echo "the test socket did not come up"; exit 1; }

fail=0
check() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1"; echo "    got:      $2"; echo "    expected: $3"; fail=1; fi; }
names() { python3 -I -c 'import json,sys; print(" ".join(json.loads(l)["hook_event_name"] for l in open(sys.argv[1])))' "$1"; }
cmds() { python3 -I -c 'import json,sys; print("|".join(json.loads(l).get("tool_input",{}).get("command","") for l in open(sys.argv[1]) if "command" in json.loads(l).get("tool_input",{})))' "$1"; }

echo "the loop (the default)"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 > /dev/null
check "the events, in order" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PostToolUse PostToolUse PostToolUse PostToolUse"
check "the same step four times" "$(cmds "$SOCK_DIR/received.jsonl")" "echo NM-FAKE loop|echo NM-FAKE loop|echo NM-FAKE loop|echo NM-FAKE loop"

echo "the risk scenario"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario risk > /dev/null
check "a permission request, the high-risk one" "$(names "$SOCK_DIR/received.jsonl")|$(cmds "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PermissionRequest|rm -rf ~/NM-FAKE-build"

echo "the waiting scenario"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario waiting > /dev/null
check "a permission request with nothing after it" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PermissionRequest"

echo "the away scenario: a minute of work, three events a minute, and the stop"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario away --minutes 1 > /dev/null
check "three edits and a stop after the start" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PostToolUse PostToolUse PostToolUse Stop"

echo "the quiet scenario"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario quiet > /dev/null
check "a step that begins and never ends" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PreToolUse"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario quiet --finish > /dev/null
check "or one that ends and nothing follows" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PostToolUse"

echo "the end scenario"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario end > /dev/null
check "only the end of the session" "$(names "$SOCK_DIR/received.jsonl")" "SessionEnd"

echo "all: the risk scenario, then the loop"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario all > /dev/null
check "nine events: the risk scenario's three and the loop's six" "$(names "$SOCK_DIR/received.jsonl" | wc -w | tr -d ' ')" "9"
check "rm -rf appears once in the all run, in the risk request only" "$(grep -c 'rm -rf' "$SOCK_DIR/received.jsonl")" "1"
check "the one removal names only NM-FAKE-build, in the home folder: nothing real" "$(grep -o 'rm -rf [^"]*' "$SOCK_DIR/received.jsonl" | sort -u)" "rm -rf ~/NM-FAKE-build"
check "every payload of the all run has the fake cwd" "$(python3 -I -c 'import json,sys; print(sorted({json.loads(l)["cwd"] for l in open(sys.argv[1])}))' "$SOCK_DIR/received.jsonl")" "['/tmp/notchmeow-fake-sidekick']"

echo "--print sends nothing"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --print --sock "$SOCK_DIR/s" > /dev/null
check "no connection was made" "$(wc -l < "$SOCK_DIR/received.jsonl" | tr -d ' ')" "0"

echo "an unreachable socket is an error, not a hang"
set +e
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/nothing" --speed 100000 > /dev/null 2>&1
check "exit code 1" "$?" "1"
echo "a speed of 0 or less, and minutes of 0 or less, are refused"
python3 scripts/fake-sidekick-events.py --print --speed 0 > /dev/null 2>&1
check "speed 0: exit code 2" "$?" "2"
python3 scripts/fake-sidekick-events.py --print --scenario away --minutes 0 > /dev/null 2>&1
check "minutes 0: exit code 2" "$?" "2"
set -e

[ "$fail" = 0 ] && echo && echo "All tests passed." || { echo; echo "tests failed."; exit 1; }
