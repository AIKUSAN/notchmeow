#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-poller.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/IslandPoller.swift \
    tests/IslandPollerTests.swift -o "$TEST_DIR/island-poller-tests"
"$TEST_DIR/island-poller-tests"
