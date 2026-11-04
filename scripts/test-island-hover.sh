#!/usr/bin/env bash
# Open on hover: IslandStateMachine's rules with short real timers (the pure state machine only, no AppKit).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-hover.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/IslandTuckAway.swift NotchBuddy/Sources/App/IslandStateMachine.swift tests/IslandHoverTests.swift -o "$TEST_DIR/island-hover-tests"
"$TEST_DIR/island-hover-tests"
