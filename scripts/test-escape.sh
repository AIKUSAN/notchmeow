#!/usr/bin/env bash
# Which view takes ⎋ before the island closes, with real SwiftUI views in an invisible panel. Needs a
# logged-in macOS session, like the app; it is not a CI step.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-escape.XXXXXX")"
trap 'rm -f "$TEST_DIR/escape-tests"; rmdir "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/EscapeRouting.swift tests/EscapeRoutingTests.swift \
    -o "$TEST_DIR/escape-tests"
"$TEST_DIR/escape-tests"
