#!/usr/bin/env bash
# Cat presets: the 16 coats, their kittens and the frozen IDs against tests/fixtures/cat/presets.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-presets.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatPresets.swift \
    tests/CatTestSupport.swift tests/CatPresetsTests.swift \
    -o "$TEST_DIR/cat-presets-tests"
"$TEST_DIR/cat-presets-tests"
