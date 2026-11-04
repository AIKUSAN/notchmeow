#!/usr/bin/env bash
# The hover glow's rules (IslandGlow.swift, Foundation only). Its call sites are pinned by scripts/test-u1-wiring.sh; its colours by scripts/test-theme.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-glow.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/IslandGlow.swift tests/IslandGlowTests.swift -o "$TEST_DIR/island-glow-tests"
"$TEST_DIR/island-glow-tests"
