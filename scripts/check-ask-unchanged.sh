#!/usr/bin/env bash
# The Ask half of the drop view is the canvas that ships (sub-project G1): the upload canvas, its sequence engine and its cat driver have not changed since the base, and
# FileDropHandler (what an Ask drop does) is the same text. The layer's own proof, that it draws nothing left of the centre line, is `bash scripts/render-shelf.sh --ask-check`.
#   bash scripts/check-ask-unchanged.sh <base>        <base> is the commit G1 started from (the ledger has it)
set -euo pipefail
cd "$(dirname "$0")/.."
BASE="${1:?usage: check-ask-unchanged.sh <base commit>}"
git rev-parse --verify "$BASE^{commit}" > /dev/null
APP=NotchBuddy/Sources/App
for f in UploadCanvasView.swift UploadSequenceEngine.swift UploadCatDriver.swift CatFileRule.swift; do
    if git diff --quiet "$BASE" -- "$APP/$f"; then echo "✓ $f is as it was at $BASE"; else echo "✗ $f changed since $BASE" >&2; exit 1; fi
done
# FileDropHandler: everything from its MARK to the end of the file.
handler() { awk '/^\/\/ MARK: - File drop handler/{p=1} p' ; }
if diff -q <(git show "$BASE:$APP/FileDropView.swift" | handler) <(handler < "$APP/FileDropView.swift") > /dev/null; then
    echo "✓ FileDropHandler (what an Ask drop does) is the same text as at $BASE"
else
    echo "✗ FileDropHandler changed since $BASE" >&2; exit 1
fi
