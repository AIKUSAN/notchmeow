#!/usr/bin/env bash
# The outside click's rules (IslandOutsideClick.swift, Foundation only). Where IslandWindowController calls them is pinned by scripts/test-u1-wiring.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-outside.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"
swiftc -swift-version 6 NotchBuddy/Sources/App/IslandOutsideClick.swift tests/IslandOutsideClickTests.swift -o "$TEST_DIR/island-outside-tests"
"$TEST_DIR/island-outside-tests"
