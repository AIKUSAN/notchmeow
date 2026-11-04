#!/usr/bin/env bash
# Settings, the pure rules: pages, tabs and the old tags; the widths; the drafts; the status words; the Sidekick tab. Nothing here launches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-settings-rules.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SettingsRoute.swift $APP/SettingsLayout.swift $APP/SettingsDraftBook.swift $APP/SettingsStatus.swift $APP/SettingsSidekick.swift \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift \
    tests/CatTestSupport.swift tests/SettingsRulesTests.swift \
    -o "$TEST_DIR/settings-rules-tests"
"$TEST_DIR/settings-rules-tests"
