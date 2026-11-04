#!/usr/bin/env bash
# The compact island's right wing stepping aside (IslandWing): its rectangle, when it is active, and the fade's timing on a fake clock.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-wing.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/IslandWing.swift \
    tests/CatTestSupport.swift tests/IslandWingTests.swift \
    -o "$TEST_DIR/island-wing-tests"
"$TEST_DIR/island-wing-tests"
