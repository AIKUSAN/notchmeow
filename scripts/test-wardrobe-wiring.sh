#!/usr/bin/env bash
# Wardrobe wiring (sub-project I): where the app's own files call the pure parts, pinned as source text (the five big-cat views, the draw order, the clock's attach and its one timer, and,
# added by later tasks, the menus, the shortcut and the Debug panel). The views and the island need the whole app, so no test program can run them.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/WardrobeWiringTests.swift \
    -o "$TEST_DIR/wardrobe-wiring-tests"
"$TEST_DIR/wardrobe-wiring-tests"
