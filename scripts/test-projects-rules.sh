#!/usr/bin/env bash
# Projects rules (ProjectsRules): paths, names, roles, order, ids, cats, steps and the layout switch against tests/fixtures/projects/, and the rules those
# fixtures cannot write (the invisible set, JavaScript's whitespace, UTF-16 order, the cat pick against CatAgentCats). Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-projects-rules.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/ProjectsRules.swift $APP/SidekickText.swift \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    tests/CatTestSupport.swift tests/ProjectsFixtureRows.swift tests/ProjectsRulesTests.swift \
    -o "$TEST_DIR/projects-rules-tests"
"$TEST_DIR/projects-rules-tests"
