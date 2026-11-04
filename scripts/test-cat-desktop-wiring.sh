#!/usr/bin/env bash
# Desktop cat wiring (sub-project H): where the app's own files call the pure parts, pinned as source text (the panel, the click-through, the one timer, the trip's one entry point, the
# empty notch spot, the drop rule and the App Store split). The controller and the island need the whole app, so no test program can run them.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 tests/CatTestSupport.swift tests/DesktopCatWiringTests.swift -o "$TEST_DIR/desktop-wiring-tests"
"$TEST_DIR/desktop-wiring-tests"
