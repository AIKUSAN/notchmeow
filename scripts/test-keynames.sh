#!/usr/bin/env bash
# The names of keys in real keyboard layouts (US, French AZERTY, German QWERTZ). Needs a logged-in macOS
# session, like the app; it is not a CI step.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-keynames.XXXXXX")"
trap 'rm -f "$TEST_DIR/keyname-tests"; rmdir "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/KeyLayoutNames.swift tests/KeyLayoutNamesTests.swift \
    -o "$TEST_DIR/keyname-tests"
"$TEST_DIR/keyname-tests"
