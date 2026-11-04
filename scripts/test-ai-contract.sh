#!/usr/bin/env bash
# Runs the language-neutral AI contract: fixture reference checks + fake server tests.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/fixtures/ai/reference.py
python3 tests/fixtures/ai/claude-code/reference.py
python3 tests/test_fake_server.py
