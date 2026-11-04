#!/usr/bin/env bash
# Focus awareness, wiring: where the app's files call the pure rules and the app side (the frontmost read, the marks, the answer, the Projects feed, the Sidekick), pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-focus-aware-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/FocusAwareWiringTests.swift \
    -o "$TEST_DIR/focus-aware-wiring-tests"
"$TEST_DIR/focus-aware-wiring-tests"
