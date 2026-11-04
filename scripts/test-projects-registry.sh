#!/usr/bin/env bash
# Projects registry (ProjectsRegistry, ProjectsSnapshot): the hook events, the registry's steps, caps and clock edges, the states, the order and the view
# against tests/fixtures/projects/, and the rules those fixtures cannot write down. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-projects-registry.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/ProjectsRules.swift $APP/ProjectsRegistry.swift $APP/ProjectsSnapshot.swift \
    $APP/HookOrigin.swift \
    tests/CatTestSupport.swift tests/SourceScan.swift tests/ProjectsFixtureRows.swift tests/ProjectsRegistryTests.swift \
    -o "$TEST_DIR/projects-registry-tests"
"$TEST_DIR/projects-registry-tests"
