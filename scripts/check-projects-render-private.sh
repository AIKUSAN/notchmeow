#!/usr/bin/env bash
# Pins that no picture of the Projects views can carry a real name, path or key (P-mac, Task 6): the render tool and the views never read this Mac's name, user or
# environment, the views name no store, no live service and no home-folder lookup (they take plain values and closures out), and no real person or device name
# is written in them. Plain greps.
set -u
cd "$(dirname "$0")/.."
fail=0
# check <what> <offending grep output>: a line of output is a failure.
check() { if [ -n "$2" ]; then printf '  ✗ %s:\n%s\n' "$1" "$2"; fail=1; else printf '  ✓ %s\n' "$1"; fi; }
HOSTREAD='Host\.current|localizedName|ComputerName|hostName|hostname|gethostname|uname|scutil|NSFullUserName|NSUserName|NSHomeDirectory|homeDirectoryForCurrentUser|getpwuid|getlogin|whoami|\$USER|\$LOGNAME|\$\{USER|LOGNAME|SCDynamicStore|ProcessInfo|getenv|environment\['
TOOL="scripts/render-projects.swift scripts/render-projects.sh"
VIEWS="NotchBuddy/Sources/App/ProjectsViews.swift"
NOTCOMMENT() { grep -vE '^[^:]*:[0-9]+:[[:space:]]*(#|//)' || true; }

check "the render tool and its script are there" "$(ls $TOOL 2>&1 >/dev/null || true)"
check "the views file is there" "$(ls $VIEWS 2>&1 >/dev/null || true)"
check "the render tool never reads the host name, the user or the environment" \
    "$(grep -HnEi "$HOSTREAD" $TOOL | NOTCOMMENT)"
check "the render tool and the views name no store, no live service and no home-folder lookup" \
    "$(grep -HnE 'AppState|ProjectsModel\.shared|ProjectsHits|UserDefaults|KeychainStore|HookServer|NSHomeDirectory|homeDirectoryForCurrentUser|NSUserName|AIService\.shared|LinkService\.shared' $TOOL $VIEWS | NOTCOMMENT)"
check "the views take plain values: they name no model, no registry and no session store" \
    "$(grep -HnE 'ProjectsModel|ProjectsRegistry|ProjectsRules|PJRegistry|\.registry|\.cwd' $VIEWS | NOTCOMMENT)"
check "no real device or person name in the views, the render tool and its script" \
    "$(grep -HnwiE 'ike|lorenz|tazan' $TOOL $VIEWS || true)$(grep -niE 'raill' $TOOL $VIEWS || true)"
# The render's own gate: every string the views draw, the peek's frame against the left card's, and its "+N more" line against the project's lines. One run
# (one compile), its output captured in a variable; nothing is written to disk, so there is no temp folder to clean up.
CHECK_OUT="$(bash scripts/render-projects.sh --check 2>&1)"; CHECK_RC=$?
check "the views' strings carry no path separator, the peek is the left card's frame, and its \"+N more\" lines are the project's (render-projects.sh --check, exit $CHECK_RC)" \
    "$([ "$CHECK_RC" = 0 ] || printf '%s\n(exit %s)' "$CHECK_OUT" "$CHECK_RC")"
echo
if [ "$fail" = 0 ]; then echo "All tests passed."; else echo "1 test(s) failed."; exit 1; fi
