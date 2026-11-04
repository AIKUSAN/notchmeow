#!/usr/bin/env bash
# The Settings window, wiring: what the kit and the pages must hold, pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-settings-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/SettingsWiringTests.swift \
    -o "$TEST_DIR/settings-wiring-tests"
"$TEST_DIR/settings-wiring-tests"
