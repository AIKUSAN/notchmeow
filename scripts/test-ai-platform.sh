#!/usr/bin/env bash
# AI platform files (Network, FoundationModels) built for the macOS 15 floor: a missing
# availability guard fails the build, and FoundationModels must be weak-linked.
# Real Apple generation is opt-in: NM_TEST_APPLE=1 bash scripts/test-ai-platform.sh
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check-sdk.sh
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-platform.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 -target "$(uname -m)-apple-macos15.0" -warnings-as-errors \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AI/Platform/NetworkMonitor.swift \
    NotchBuddy/Sources/App/AI/Platform/AppleOnDeviceProvider.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIPlatformTests.swift \
    -o "$TEST_DIR/ai-platform-tests"
if grep -q FoundationModels < <(otool -l "$TEST_DIR/ai-platform-tests" | grep -A2 'LC_LOAD_DYLIB$'); then
    echo "FoundationModels is strongly linked: the app would not launch on macOS 15" >&2
    exit 1
fi
"$TEST_DIR/ai-platform-tests"
