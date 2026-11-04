#!/usr/bin/env bash
# Project cats (P-mac, Task 4): what is stored under cat.projectCat.<folder name>, cleaned on load and on every change, the store's group beside the wardrobe,
# and the rows Settings shows. Through an injected dictionary (MemoryBacking): never UserDefaults, never a suite.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-projects-cats.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/Wardrobe.swift $APP/WardrobeSettings.swift \
    $APP/ProjectsRules.swift $APP/ProjectCatSettings.swift $APP/CatSettingsStore.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/ProjectCatsTests.swift \
    -o "$TEST_DIR/projects-cats-tests"
"$TEST_DIR/projects-cats-tests"
