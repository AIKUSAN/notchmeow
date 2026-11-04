#!/usr/bin/env bash
# Cat sleep: the one-shot timer (ten minutes with no agent event, reset by each event, never while busy, no polling), what wakes a sleeping cat,
# and what an idle cat shows, on timers the test moves by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-sleep.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatRules.swift NotchBuddy/Sources/App/CatSleep.swift \
    tests/CatTestSupport.swift tests/CatSleepTests.swift \
    -o "$TEST_DIR/cat-sleep-tests"
"$TEST_DIR/cat-sleep-tests"
