#!/usr/bin/env bash
# Runs the companion contract: the rules' own tests, a no-drift check of tests/fixtures/companion/ against companion-core.js, and a determinism check (two generator runs
# must write identical bytes).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v node >/dev/null || { echo "node (22 or newer) is required" >&2; exit 1; }
node --test tests/companion/*.test.mjs
node scripts/gen-companion-fixtures.mjs --check
a=$(mktemp -d -t f3a0-); b=$(mktemp -d -t f3a0-)
trap 'rm -rf "$a" "$b"' EXIT
node scripts/gen-companion-fixtures.mjs --out "$a" >/dev/null
node scripts/gen-companion-fixtures.mjs --out "$b" >/dev/null
diff -r "$a" "$b" >/dev/null || { echo "✗ two generator runs wrote different bytes" >&2; exit 1; }
echo "✓ two generator runs write identical bytes"
