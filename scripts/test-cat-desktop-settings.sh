#!/usr/bin/env bash
# Desktop cat settings (sub-project H): the screens, the key and the spots (screenKey, clampSpot, spotFor, rememberSpot), the stored block (cleanDesktopSettings) and its three
# UserDefaults keys against desktop-cases.json, and what the fixture cannot write (a NaN, a boolean, a screen too small, a thousand arrangements).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatSettingsTests.swift \
    -o "$TEST_DIR/desktop-settings-tests"
"$TEST_DIR/desktop-settings-tests"
