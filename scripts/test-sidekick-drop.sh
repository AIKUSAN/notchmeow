#!/usr/bin/env bash
# Sidekick drop on an agent's own cat: the grid cats' circles, the hit test, the clipboard text and the line. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-drop.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/SidekickDrop.swift \
    tests/CatTestSupport.swift tests/SidekickDropTests.swift \
    -o "$TEST_DIR/sidekick-drop-tests"
"$TEST_DIR/sidekick-drop-tests"
