#!/usr/bin/env bash
# Tuck the island away, wiring: where the app's files call the pure rule and the state machine, pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-tuck-away-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/IslandTuckAwayWiringTests.swift \
    -o "$TEST_DIR/island-tuck-away-wiring-tests"
"$TEST_DIR/island-tuck-away-wiring-tests"
