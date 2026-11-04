#!/usr/bin/env bash
# Cat settings: the clean-up of what Settings saves (cleanCatSettings, cleanPersonality, Apply to every cat, the resolvers) against
# settings-cases.json, a real NaN, and the UserDefaults keys through an injected dictionary store (no UserDefaults suite).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatMath.swift NotchBuddy/Sources/App/CatPresets.swift NotchBuddy/Sources/App/Personality.swift \
    NotchBuddy/Sources/App/CatRules.swift NotchBuddy/Sources/App/CatSettings.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatSettingsTests.swift \
    -o "$TEST_DIR/cat-settings-tests"
"$TEST_DIR/cat-settings-tests"
