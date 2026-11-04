#!/usr/bin/env bash
# The link's file-name rules (LinkName.swift): every case of tests/fixtures/link/filename-cases.json, and the invariants the reference fuzzes. Foundation only.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-name.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkName.swift \
    tests/CatTestSupport.swift tests/LinkNameTests.swift \
    -o "$TEST_DIR/link-name-tests"
"$TEST_DIR/link-name-tests"
