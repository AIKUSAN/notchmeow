#!/usr/bin/env bash
# Cat kitten hooks: the scripted subagent events (tests/fixtures/mac/subagent-scenarios.json) are sent by scripts/fake-subagent-events.py to a socket of the test's own
# (never the app's), and what that socket received is replayed through CatKittenHooks and CatKittens: the start, the tool events with and without an agent_id, a
# permission request, the stop, a stop that never comes and the parent's stop. Nothing here launches or touches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-kitten-hooks.XXXXXX")"
SOCK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nmk.XXXXXX")"
[ "${#SOCK_DIR}" -le 80 ] || { rm -rf "$SOCK_DIR"; SOCK_DIR="$(mktemp -d /tmp/nmk.XXXXXX)"; }   # a socket path holds 103 bytes
SERVER=""
trap '[ -z "$SERVER" ] || { kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null; } || true; rm -rf "$TEST_DIR" "$SOCK_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

python3 tests/kitten_socket_server.py "$SOCK_DIR/s" "$SOCK_DIR/received.jsonl" &
SERVER=$!
for _ in $(seq 1 50); do [ -S "$SOCK_DIR/s" ] && break; sleep 0.1; done
[ -S "$SOCK_DIR/s" ] || { echo "the test socket did not come up"; exit 1; }
mkdir -p "$TEST_DIR/received"
for name in $(python3 scripts/fake-subagent-events.py --list | awk '{print $1}'); do
    : > "$SOCK_DIR/received.jsonl"
    python3 scripts/fake-subagent-events.py --scenario "$name" --sock "$SOCK_DIR/s" --speed 100000 > /dev/null
    cp "$SOCK_DIR/received.jsonl" "$TEST_DIR/received/$name.jsonl"
done
export NM_KITTEN_RECEIVED="$TEST_DIR/received"

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift \
    $APP/CatKittens.swift $APP/CatKittenHooks.swift \
    tests/CatTestSupport.swift tests/CatKittenHooksTests.swift \
    -o "$TEST_DIR/cat-kitten-hooks-tests"
"$TEST_DIR/cat-kitten-hooks-tests"
