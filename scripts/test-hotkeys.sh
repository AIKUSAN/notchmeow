#!/usr/bin/env bash
# The Carbon plumbing of HotKeyCenter (register, conflict, release, a simulated press). Needs a logged-in
# macOS session, like the app; it is not a CI step.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-hotkeys.XXXXXX")"
trap 'rm -f "$TEST_DIR/hotkey-tests"; rmdir "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/ShortcutLogic.swift NotchBuddy/Sources/App/HotKeyCenter.swift \
    tests/HotKeyCenterTests.swift -o "$TEST_DIR/hotkey-tests"
"$TEST_DIR/hotkey-tests"
