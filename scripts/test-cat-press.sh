#!/usr/bin/env bash
# Two cats mode: a press in cat 2's part of the overlap with cat 1 drags nothing out of the notch (CatIslandLayout.bigCatPressed), and the island's hit test is that rule.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-press.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift \
    tests/CatTestSupport.swift tests/CatPressTests.swift \
    -o "$TEST_DIR/cat-press-tests"
"$TEST_DIR/cat-press-tests"
