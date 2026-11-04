#!/usr/bin/env bash
# The shelf's wiring (sub-project G1): where the drop view, the panel and the island's view call the shelf, pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-shelf-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/ShelfWiringTests.swift \
    -o "$TEST_DIR/shelf-wiring-tests"
"$TEST_DIR/shelf-wiring-tests"
