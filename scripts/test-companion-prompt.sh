#!/usr/bin/env bash
# Companion prompt and "Right now" (F3a-mac, Task 1): the prompt's order, the quiet rule, the moods and the memory budget, "Right now", the cloud line and the
# text helpers, replayed against tests/fixtures/companion/prompt-cases.json, quiet-cases.json and rightnow-cases.json, and the rules those fixtures cannot
# write. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-companion-prompt.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
# -O: the 200 ms rows measure the rules at optimized speed (the app's Debug build is -Onone and the rules never see 100,000 characters there).
swiftc -O -swift-version 6 \
    $APP/AI/Core/AICatalog.swift $APP/CompanionText.swift $APP/CompanionPrompt.swift $APP/CompanionRightNow.swift \
    $APP/ProjectsRules.swift $APP/ProjectsRegistry.swift $APP/ProjectsSnapshot.swift $APP/HookOrigin.swift \
    tests/CatTestSupport.swift tests/CompanionPromptTests.swift \
    -o "$TEST_DIR/companion-prompt-tests"
"$TEST_DIR/companion-prompt-tests"
