#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-shortcuts.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/ShortcutLogic.swift \
    tests/ShortcutTests.swift -o "$TEST_DIR/shortcut-tests"
"$TEST_DIR/shortcut-tests"
