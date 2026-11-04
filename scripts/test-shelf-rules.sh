#!/usr/bin/env bash
# The shelf contract on the Mac (sub-project G1): ShelfRules (zoneAt, shelfClean, shelfAdd and the strict JSON reader) against tests/fixtures/shelf/, and what the fixtures cannot write.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-shelf-rules.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/ShelfRules.swift \
    tests/CatTestSupport.swift tests/ShelfRulesTests.swift \
    -o "$TEST_DIR/shelf-rules-tests"
"$TEST_DIR/shelf-rules-tests"
