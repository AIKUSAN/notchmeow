#!/usr/bin/env bash
# Every test script that builds code which can write the app log (AppLog.swift, LocalChat.swift or
# AI/Core) must set NM_LOG_DIR, so no test run appends to ~/Library/Logs/NotchMeow/nm.log.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for script in scripts/test-*.sh; do
    if grep -qE 'AppLog\.swift|LocalChat\.swift|AI/Core/' "$script" && ! grep -q 'NM_LOG_DIR' "$script"; then
        echo "✗ $script builds the app log code but doesn't set NM_LOG_DIR" >&2
        status=1
    fi
done
[ "$status" = 0 ] && echo "✓ every log-writing test script sets NM_LOG_DIR"
exit "$status"
