#!/usr/bin/env bash
# The Debug-only shelf panel's model (sub-project G1): its buttons fill a shelf of its own, in a temp folder.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-shelf-devpanel.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/ShelfRules.swift $APP/ShelfDrop.swift $APP/ShelfStore.swift $APP/ShelfModel.swift $APP/ShelfDevModel.swift \
    tests/CatTestSupport.swift tests/ShelfDevModelTests.swift \
    -o "$TEST_DIR/shelf-devpanel-tests"
"$TEST_DIR/shelf-devpanel-tests"
