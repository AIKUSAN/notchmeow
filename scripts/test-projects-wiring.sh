#!/usr/bin/env bash
# Projects wiring (P-mac, Task 8): where HookServer feeds the registry, the session's jump in AgentTarget, the app's shared model, and the rule that no view or
# controller reads the registry or a path, pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-projects-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/SourceScan.swift tests/ProjectsWiringTests.swift \
    -o "$TEST_DIR/projects-wiring-tests"
"$TEST_DIR/projects-wiring-tests"
