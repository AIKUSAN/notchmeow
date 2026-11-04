#!/usr/bin/env bash
# Wardrobe settings (sub-project I): the 18 frozen IDs and their order, the clean-up of a stored outfit (outfitIdOf, cleanWardrobeSettings), who wears it, the ⌃⌥G cycle, the one
# UserDefaults key `cat.outfit` and the menus' items, against wardrobe-cases.json, and what the fixture cannot write (a number, a list, data and padding in the store).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/Wardrobe.swift $APP/WardrobeSettings.swift $APP/WardrobeAuto.swift $APP/CatSettings.swift $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/WardrobeSettingsTests.swift \
    -o "$TEST_DIR/wardrobe-settings-tests"
"$TEST_DIR/wardrobe-settings-tests"
