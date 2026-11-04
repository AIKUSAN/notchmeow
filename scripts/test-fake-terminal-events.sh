#!/usr/bin/env bash
# The owner's fake terminal session (scripts/fake-terminal-events.py) is sent to a socket of this test's own, never the app's, and what that socket received is checked:
# the events in order, every one carrying the terminal's TERM_PROGRAM and bundle ID, the permission request only with --approval. Nothing here launches or touches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-fake-terminal.XXXXXX")"
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
field() { python3 -I -c 'import json,sys; print(" ".join(sorted({json.loads(l)[sys.argv[2]] for l in open(sys.argv[1])})))' "$1" "$2"; }

echo "the default session: Apple Terminal"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-terminal-events.py --sock "$SOCK_DIR/s" --speed 100000 > /dev/null
check "the events, in order" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PreToolUse PostToolUse Stop"
check "every one says Apple_Terminal" "$(field "$SOCK_DIR/received.jsonl" term_program)" "Apple_Terminal"
check "and com.apple.Terminal" "$(field "$SOCK_DIR/received.jsonl" bundle_id)" "com.apple.Terminal"
check "and is no tagged agent" "$(python3 -I -c 'import json,sys; print(sum("nm_agent" in json.loads(l) for l in open(sys.argv[1])))' "$SOCK_DIR/received.jsonl")" "0"

echo "iTerm, with an approval"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-terminal-events.py --sock "$SOCK_DIR/s" --speed 100000 --term-program iTerm.app --bundle-id com.googlecode.iterm2 --approval > /dev/null
check "the permission request is there, before the stop" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PreToolUse PostToolUse PermissionRequest Stop"
check "every one says iTerm.app" "$(field "$SOCK_DIR/received.jsonl" term_program)" "iTerm.app"

echo "--print sends nothing"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-terminal-events.py --print --sock "$SOCK_DIR/s" > /dev/null
check "no connection was made" "$(wc -l < "$SOCK_DIR/received.jsonl" | tr -d ' ')" "0"

echo "an unreachable socket is an error, not a hang"
set +e
python3 scripts/fake-terminal-events.py --sock "$SOCK_DIR/nothing" --speed 100000 > /dev/null 2>&1
check "exit code 1" "$?" "1"
set -e

echo "a speed of 0 or less is refused"
set +e
python3 scripts/fake-terminal-events.py --print --speed 0 > /dev/null 2>&1
check "exit code 2" "$?" "2"
python3 scripts/fake-terminal-events.py --print --speed -1 > /dev/null 2>&1
check "a negative speed too: exit code 2" "$?" "2"
set -e

[ "$fail" = 0 ] && echo && echo "All tests passed." || { echo; echo "tests failed."; exit 1; }
