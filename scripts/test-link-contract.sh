#!/usr/bin/env bash
# Runs the link contract (sub-project G2): the fixtures in tests/fixtures/link/ against the Python reference,
# and a no-drift check of the JSON files against the script that writes them.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B tests/fixtures/link/reference.py
python3 -B tests/fixtures/link/build_cases.py --check
# Each fixture must also parse in node. node's JSON.parse accepts lone-surrogate escapes, so the surrogate rule is
# enforced by the strict Python check in reference.py; this node check only proves that each file parses in node.
# It reads each file with fs and writes nothing.
if ! command -v node >/dev/null 2>&1; then
  echo "node is missing: the node JSON check cannot run" >&2
  exit 1
fi
count=0
for f in tests/fixtures/link/*.json; do
  if ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$f"; then
    echo "node cannot parse $f" >&2
    exit 1
  fi
  count=$((count + 1))
done
echo "node: $count fixtures parse with JSON.parse"
