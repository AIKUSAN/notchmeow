#!/usr/bin/env bash
# Focus awareness rules (FocusAware): the setting, the session's host, the match against the frontmost app, the decision, the wording (P-mac's
# ProjectsRules.waitLabel), the card note, the dot, the --ask twin's Projects wait, the marks' ages and endings, and the step words' verb (SessionStepText.verb).
# Pure Foundation; nothing here launches NotchMeow or reads the frontmost app.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-focus-aware.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/FocusAware.swift $APP/HookOrigin.swift $APP/SessionStepText.swift \
    $APP/ProjectsRules.swift $APP/SidekickText.swift \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    tests/CatTestSupport.swift tests/FocusAwareTests.swift \
    -o "$TEST_DIR/focus-aware-tests"
"$TEST_DIR/focus-aware-tests"
