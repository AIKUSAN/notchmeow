#!/usr/bin/env bash
# Cat theme: the Mac's character, branding and greeting colours come from Theme.generated.swift and no hex literal of one is left in the drawing code
# (source pins). That no pixel changed is proved by comparing contact sheets drawn before and after (docs/THEME.md).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-theme.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 tests/CatTestSupport.swift tests/CatThemeTests.swift -o "$TEST_DIR/cat-theme-tests"
"$TEST_DIR/cat-theme-tests"
