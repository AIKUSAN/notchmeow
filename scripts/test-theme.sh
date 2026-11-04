#!/usr/bin/env bash
# Runs the theme check: the generator's self-checks, then proof that the three generated files match shared/theme.json
# and the state colours of cat-core.js. CI runs it next to the cat contract.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v node >/dev/null || { echo "node (22 or newer) is required" >&2; exit 1; }
node --test tests/theme/*.test.mjs
node scripts/gen-theme.mjs --check
