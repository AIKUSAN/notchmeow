#!/usr/bin/env bash
# The shelf's storage (sub-project G1): ShelfStore against real files in a temp folder.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-shelf-store.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/ShelfRules.swift NotchBuddy/Sources/App/ShelfStore.swift \
    tests/CatTestSupport.swift tests/ShelfStoreTests.swift \
    -o "$TEST_DIR/shelf-store-tests"
"$TEST_DIR/shelf-store-tests"
