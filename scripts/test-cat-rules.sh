#!/usr/bin/env bash
# Cat rules: the work clock and zoomies, the sleep timer, what wakes a cat and the search tool names
# against sequence-cases.json and search-tools.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-rules.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatRules.swift \
    tests/CatTestSupport.swift tests/CatRulesTests.swift \
    -o "$TEST_DIR/cat-rules-tests"
"$TEST_DIR/cat-rules-tests"
