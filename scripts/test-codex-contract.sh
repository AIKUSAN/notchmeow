#!/usr/bin/env bash
# The Codex engine against the shared fixtures in tests/fixtures/ai/codex/: the command line, the environment, the
# locator, the versions and the sign-in state. Never runs a real codex; reference.py also fails if it opens an auth.json.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B tests/fixtures/ai/codex/reference.py
