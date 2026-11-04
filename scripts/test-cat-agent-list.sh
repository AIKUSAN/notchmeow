#!/usr/bin/env bash
# Cat agent list: the rows of "Cats for your agents" (most recent first, stored agents after), the Display preview's sample island, and the compact island's
# cat positions.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-agent-list.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift \
    tests/CatTestSupport.swift tests/CatAgentListTests.swift \
    -o "$TEST_DIR/cat-agent-list-tests"
"$TEST_DIR/cat-agent-list-tests"
