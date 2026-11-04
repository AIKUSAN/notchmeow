#!/usr/bin/env bash
# Runs the projects contract: the rules' own tests, a no-drift check of tests/fixtures/projects/ against projects-core.js, and a determinism check (two generator runs
# must write identical bytes).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v node >/dev/null || { echo "node (22 or newer) is required" >&2; exit 1; }
node --test tests/projects/*.test.mjs
node scripts/gen-projects-fixtures.mjs --check
a=$(mktemp -d -t p0-); b=$(mktemp -d -t p0-)
trap 'rm -rf "$a" "$b"' EXIT
node scripts/gen-projects-fixtures.mjs --out "$a" >/dev/null
node scripts/gen-projects-fixtures.mjs --out "$b" >/dev/null
diff -r "$a" "$b" >/dev/null || { echo "✗ two generator runs wrote different bytes" >&2; exit 1; }
echo "✓ two generator runs write identical bytes"
