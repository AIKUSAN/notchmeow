#!/usr/bin/env bash
# The frame-time meter behind the Debug-only readout: draws that start together add up to one frame, against a 2 ms budget.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-meter.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatFrameMeter.swift \
    tests/CatTestSupport.swift tests/CatFrameMeterTests.swift \
    -o "$TEST_DIR/cat-meter-tests"
"$TEST_DIR/cat-meter-tests"
