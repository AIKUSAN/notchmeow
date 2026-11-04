#!/usr/bin/env bash
# Projects model (ProjectsModel, Task 5): the scenarios replayed through feed, a session's step, the pin and the click, the layout and the panel, the one tick
# (armed while expanded only), the clock's edges and what publishes. A fake clock and a fake scheduler: no timer runs. Foundation and Combine only.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-projects-model.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/ProjectsRules.swift $APP/ProjectsRegistry.swift $APP/ProjectsSnapshot.swift $APP/ProjectsLayout.swift $APP/ShelfBadge.swift \
    $APP/SessionStepText.swift $APP/ProjectsModel.swift \
    tests/CatTestSupport.swift tests/ProjectsFixtureRows.swift tests/ProjectsModelTests.swift \
    -o "$TEST_DIR/projects-model-tests"
"$TEST_DIR/projects-model-tests"
