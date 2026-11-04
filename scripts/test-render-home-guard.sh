#!/usr/bin/env bash
# Proves that the render tools which build the app's own state never read the real home (scripts/render-home-guard.sh): the app's home lookup follows the fake home inside the
# guard, a program that opens the real ~/.claude, ~/.gemini or ~/.codex is killed before it reads a byte, and the render script runs its tool through the guard. Nothing here
# opens a real file: the programs that try are killed first (a guard that failed would show a file's text only to /dev/null).
#   bash scripts/test-render-home-guard.sh
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/render-home-guard.sh
TMP="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-test-home-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
expect() {   # expect NAME WANTED GOT
    if [ "$2" = "$3" ]; then ok "$1"; else failed=$((failed + 1)); echo "FAIL $1 (wanted [$2], got [$3])"; fi
}

FAKE="$(cd "$TMP" && pwd -P)/home"
mkdir -p "$FAKE/.claude"
echo '{"fake":true}' > "$FAKE/.claude/settings.json"
REAL="$(render_real_home)"
swiftc -swift-version 6 -o "$TMP/probe" tests/HomeProbe.swift || { echo "FAIL the probe does not compile"; exit 1; }

expect "the real home is known, and is not the fake one" yes "$([ -n "$REAL" ] && [ "$REAL" != "$FAKE" ] && echo yes || echo no)"
expect "inside the guard the app's home lookup gives the fake home" "$FAKE" "$(cd "$(render_home_guard "$FAKE" "$TMP/probe")" 2>/dev/null && pwd -P)"
expect "and its read of .claude/settings.json is the fake file" '{"fake":true}' "$(render_home_guard "$FAKE" "$TMP/probe" read)"

# A program that opens the real agent configs is killed (SIGKILL, exit 137) before it reads anything.
for f in .claude/settings.json .gemini/settings.json .codex/hooks.json; do
    if [ ! -e "$REAL/$f" ]; then echo "skip $f: not under the real home here (kill row not run)"; continue; fi
    render_home_guard "$FAKE" /bin/cat "$REAL/$f" > /dev/null 2>&1; code=$?
    expect "a program that opens the real ~/$f is killed" 137 "$code"
done
if [ ! -e "$REAL/.claude" ]; then echo "skip .claude: not under the real home here (kill row not run)"; else
    render_home_guard "$FAKE" /bin/ls "$REAL/.claude" > /dev/null 2>&1; code=$?
    expect "and so is one that lists the real ~/.claude" 137 "$code"
fi
render_home_guard "$FAKE" /bin/cat "$FAKE/.claude/settings.json" > /dev/null 2>&1; code=$?
expect "a program that opens the fake home's file is not" 0 "$code"
render_home_guard "$FAKE" /bin/cat /etc/hosts > /dev/null 2>&1; code=$?
expect "nor one that reads anything else" 0 "$code"

# The guard fails closed: with no way to tell the homes apart it runs nothing.
out="$(render_home_guard "$REAL" /bin/echo ran 2>&1)"; code=$?
expect "given the real home as the fake one, it refuses and runs nothing" "1:render-home-guard: cannot tell the real home from the fake one" "$code:$out"

# The render script runs its tool through the guard, and no script that builds the whole app can skip it.
expect "render-approval-card.sh runs the tool through the guard" 1 "$(grep -c 'render_home_guard "\$BUILD_DIR/home" "\$BUILD_DIR/render-approval-card"' scripts/render-approval-card.sh)"
expect "and no longer runs it with only HOME changed" 0 "$(grep -c 'HOME="\$BUILD_DIR/home" "\$BUILD_DIR' scripts/render-approval-card.sh)"
for f in scripts/*.sh; do
    if grep -q "find \"\$APP\" -name '\*.swift'" "$f"; then
        expect "$f builds the whole app, so it runs through the guard" yes "$(grep -q render_home_guard "$f" && echo yes || echo no)"
    fi
done

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
