#!/usr/bin/env bash
# The Projects scenarios (tests/fixtures/mac/projects-scenarios.json) replayed through shared/projects-core.js: the hand-typed expectations the Swift model test replays
# through the port are checked against the core itself. Node only; reads two files and writes nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v node >/dev/null || { echo "node (22 or newer) is required" >&2; exit 1; }
node scripts/test-projects-scenarios-core.mjs
