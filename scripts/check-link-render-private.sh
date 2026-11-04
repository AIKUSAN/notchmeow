#!/usr/bin/env bash
# Pins that no picture of the link can carry a real device or person name (sub-project G2): the render tool uses fixed sample names and never reads this Mac's name or user, no other link
# source reads them either (LinkService's init default is the one place that reads the Mac's name), and no real name is written in the link's sources, tests or scripts. Plain greps.
set -u
cd "$(dirname "$0")/.."
fail=0
# check <what> <offending grep output>: a line of output is a failure.
check() { if [ -n "$2" ]; then printf '  ✗ %s:\n%s\n' "$1" "$2"; fail=1; else printf '  ✓ %s\n' "$1"; fi; }
HOSTREAD='Host\.current|localizedName|ComputerName|hostName|hostname|gethostname|uname|scutil|NSFullUserName|NSUserName|NSHomeDirectory|homeDirectoryForCurrentUser|getpwuid|getlogin|whoami|\$USER|\$LOGNAME|\$\{USER|LOGNAME|SCDynamicStore|ProcessInfo|getenv|environment\['

check "the render tool never reads the host name, the user or the environment" \
    "$(grep -nEi "$HOSTREAD" scripts/render-link.swift scripts/render-link.sh | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)"
# (LinkFiles reads the home folder to find Downloads: a folder, never a name.)
SOURCEREAD="$(printf '%s' "$HOSTREAD" | sed 's/|NSHomeDirectory|homeDirectoryForCurrentUser//; s/|ProcessInfo//')"
check "no other link source reads the Mac's name or the user (LinkService.swift's init default is the one place)" \
    "$(grep -nE "$SOURCEREAD" $(ls NotchBuddy/Sources/App/Link*.swift | grep -v '/LinkService\.swift$') || true)"
check "LinkService reads the Mac's name only as the default of its init" \
    "$(grep -nE 'Host\.current|localizedName|ComputerName|NSFullUserName|NSUserName' NotchBuddy/Sources/App/LinkService.swift | grep -v 'host: String = Host\.current()\.localizedName' || true)"
FILES="$(ls NotchBuddy/Sources/App/Link*.swift tests/Link*.swift scripts/test-link-*.sh scripts/render-link.* 2>/dev/null)"
check "no real device or person name in the link's sources, tests and scripts" \
    "$(grep -nwiE 'ike|lorenz|tazan' $FILES || true)$(grep -niE 'raill' $FILES || true)"
echo
if [ "$fail" = 0 ]; then echo "All tests passed."; else echo "1 test(s) failed."; exit 1; fi
