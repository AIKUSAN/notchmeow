#!/usr/bin/env bash
# The drop halves (sub-project G1): which half the pointer is in, what each half accepts, which buttons work, when the shelf holds the island open, and the compact badge's rules.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-shelf-drop.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/ShelfRules.swift NotchBuddy/Sources/App/ShelfDrop.swift NotchBuddy/Sources/App/ShelfBadge.swift \
    tests/CatTestSupport.swift tests/ShelfDropTests.swift \
    -o "$TEST_DIR/shelf-drop-tests"
"$TEST_DIR/shelf-drop-tests"
