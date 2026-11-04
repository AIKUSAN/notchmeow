#!/usr/bin/env bash
# The Debug-only cat panel's model: which cat, size, motion style and state it shows, and the engines it builds. It compiles the model with
# -D DEBUG, the way a Debug build does (a Release build has no panel: scripts/check-app-binary.sh proves it).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-devpanel.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatFileRule.swift $APP/CatDevModel.swift \
    $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
    tests/CatTestSupport.swift tests/CatEngineSupport.swift tests/CatDevModelTests.swift \
    -o "$TEST_DIR/cat-devpanel-tests"
"$TEST_DIR/cat-devpanel-tests"
