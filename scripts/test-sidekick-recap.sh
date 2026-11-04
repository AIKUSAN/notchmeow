#!/usr/bin/env bash
# Sidekick recap, status answer and status question (recapOf, statusOf, matchStatusQuestion): tests/fixtures/sidekick/recap-cases.json and status-cases.json, and what they cannot write.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-recap.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift \
    tests/CatTestSupport.swift tests/SidekickRecapTests.swift \
    -o "$TEST_DIR/sidekick-recap-tests"
"$TEST_DIR/sidekick-recap-tests"
