#!/usr/bin/env bash
# The link's wire shapes (LinkFrames.swift: records, the first record, the hello, the advert, the six frames): every case of tests/fixtures/link/frames.json. Foundation only.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-frames.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift \
    tests/CatTestSupport.swift tests/LinkFramesTests.swift \
    -o "$TEST_DIR/link-frames-tests"
"$TEST_DIR/link-frames-tests"
