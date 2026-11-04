#!/usr/bin/env bash
# Projects island layout (ProjectsLayout): the grid's and the panel's cells, the layout switch, the big cat's coat and state, the compact waiting badge's place
# (checked against ShelfBadge's own geometry) and the words. Foundation and CoreGraphics only.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-projects-layout.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/ProjectsRules.swift $APP/ProjectsLayout.swift $APP/ShelfBadge.swift \
    tests/CatTestSupport.swift tests/ProjectsLayoutTests.swift \
    -o "$TEST_DIR/projects-layout-tests"
"$TEST_DIR/projects-layout-tests"
