#!/usr/bin/env bash
# AI core: provider catalog vs providers.json, router-cases.json, http-errors.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-router.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

# The core must stay Foundation-only so these swiftc tests can build it.
bad=$(grep -h '^import ' NotchBuddy/Sources/App/AI/Core/*.swift | sort -u | grep -v '^import Foundation$' || true)
if [ -n "$bad" ]; then echo "AI/Core imports more than Foundation: $bad" >&2; exit 1; fi

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIRouterTests.swift \
    -o "$TEST_DIR/ai-router-tests"
"$TEST_DIR/ai-router-tests"
