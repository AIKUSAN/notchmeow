#!/usr/bin/env bash
# Cat settings in the app: the store loads what is stored (through an injected dictionary, never a UserDefaults suite), hands it to the engines
# through CatConfig, saves only what changed, and the character switches a running engine.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-settings-store.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/Wardrobe.swift $APP/WardrobeSettings.swift $APP/ProjectsRules.swift $APP/ProjectCatSettings.swift $APP/CatSettingsStore.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatSettingsStoreTests.swift \
    -o "$TEST_DIR/cat-settings-store-tests"
"$TEST_DIR/cat-settings-store-tests"
