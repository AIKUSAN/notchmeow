#!/usr/bin/env bash
# Runs the shelf contract (sub-project G1): the fixtures in tests/fixtures/shelf/ against the Python reference,
# and a no-drift check of the two JSON files against the script that writes them.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/fixtures/shelf/reference.py
python3 tests/fixtures/shelf/build_cases.py --check
