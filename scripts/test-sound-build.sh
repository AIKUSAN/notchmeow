#!/usr/bin/env bash
# Tests for the sound build (tools/sounds/, stages 1 and 2): Python 3 standard library plus macOS afconvert.
#   bash scripts/test-sound-build.sh          unit tests and the recipe check (CI runs this)
#   bash scripts/test-sound-build.sh --real   also builds all five sets from the real candidate clips
#                                             and fails if any file misses its targets (local only:
#                                             the clips are git-ignored)
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p 'test_sound_*.py'
python3 tools/sounds/build_pack.py --check-recipes
if [ "${1:-}" = "--real" ]; then
    python3 tools/sounds/build_pack.py --all --report
fi
