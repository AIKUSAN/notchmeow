#!/usr/bin/env bash
# Tuck the island away: the pure rule (IslandTuckAway) and IslandStateMachine's one timer on a clock turned by hand (the pure state machine only, no AppKit).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-tuck-away.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/IslandTuckAway.swift NotchBuddy/Sources/App/IslandStateMachine.swift tests/IslandTuckAwayTests.swift -o "$TEST_DIR/island-tuck-away-tests"
"$TEST_DIR/island-tuck-away-tests"
