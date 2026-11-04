#!/usr/bin/env bash
# Projects leak pins (Task 5): a session's whole life fed through ProjectsModel with a marker planted in every field that must not show, store or log.
# HOME is a fresh empty folder for the run, and the script checks afterwards that the run wrote nothing into it. Through an injected dictionary
# (MemoryBacking): never UserDefaults, never a suite.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-projects-leak.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
mkdir -p "$NM_LOG_DIR"

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/Wardrobe.swift $APP/WardrobeSettings.swift \
    $APP/ProjectsRules.swift $APP/ProjectCatSettings.swift $APP/CatSettingsStore.swift \
    $APP/ProjectsRegistry.swift $APP/ProjectsSnapshot.swift $APP/ProjectsLayout.swift $APP/ShelfBadge.swift \
    $APP/SessionStepText.swift $APP/ProjectsModel.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/ProjectsLeakTests.swift \
    -o "$TEST_DIR/projects-leak-tests"

HOME_DIR="$TEST_DIR/home"
mkdir -p "$HOME_DIR"
HOME="$HOME_DIR" "$TEST_DIR/projects-leak-tests"
left="$(find "$HOME_DIR" -mindepth 1 | wc -l | tr -d ' ')"
if [ "$left" != "0" ]; then
    echo "the run wrote $left item(s) under HOME"
    exit 1
fi
echo "HOME is still empty after the run."
