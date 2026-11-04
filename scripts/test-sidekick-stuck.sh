#!/usr/bin/env bash
# Sidekick stuck rules (stuckStep, nudgeText, markNudged): every timeline of tests/fixtures/sidekick/stuck-cases.json, and what the fixture cannot write. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-stuck.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift \
    tests/CatTestSupport.swift tests/SidekickStuckTests.swift \
    -o "$TEST_DIR/sidekick-stuck-tests"
"$TEST_DIR/sidekick-stuck-tests"
