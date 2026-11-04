#!/usr/bin/env bash
# Cat wiring (sub-project B): what no test program can run, because the app's windows and servers are not in it: where the app's own files call the pure
# parts, pinned as source text (the last event of each pill, the coat each cat view is given, the kittens' hook events, and the App Store split).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/CatWiringTests.swift \
    -o "$TEST_DIR/cat-wiring-tests"
"$TEST_DIR/cat-wiring-tests"
