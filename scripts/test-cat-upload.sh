#!/usr/bin/env bash
# The cat in the drop view: the upload sequence's frames drive the four-step file catch, a refused file is decided at the drop by the app's own
# rule (read from the AI fixtures) and coughed up as a hairball, and the sequence of a refused file has no bar and no check mark.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-upload.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/UploadSequenceEngine.swift $APP/CatFileRule.swift $APP/UploadCatDriver.swift \
    $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
    tests/CatTestSupport.swift tests/CatEngineSupport.swift tests/UploadCatDriverTests.swift \
    -o "$TEST_DIR/cat-upload-tests"
"$TEST_DIR/cat-upload-tests"
