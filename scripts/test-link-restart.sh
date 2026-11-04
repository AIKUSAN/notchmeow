#!/usr/bin/env bash
# The restart table of a listener or a browser that failed (LinkRestarter) and its one-shot wait (LinkRestartWait), sub-project G2b. Foundation only: no network, no Keychain, no real clock but the
# short waits of the last section.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-restart.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkRestart.swift \
    tests/CatTestSupport.swift tests/LinkRestartTests.swift \
    -o "$TEST_DIR/link-restart-tests"
"$TEST_DIR/link-restart-tests"
