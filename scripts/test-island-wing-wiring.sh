#!/usr/bin/env bash
# The right wing stepping aside, wiring: where the panel's poll, AppState and the island's view call the pure rules (IslandWing), pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-wing-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/IslandWingWiringTests.swift \
    -o "$TEST_DIR/island-wing-wiring-tests"
"$TEST_DIR/island-wing-wiring-tests"
