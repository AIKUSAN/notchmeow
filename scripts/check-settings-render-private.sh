#!/usr/bin/env bash
# Pins that no picture of Settings can carry a real name, path or key (the Settings restyle): the render tool uses fixed sample values and never reads this Mac's name, user or environment
# and never touches the Keychain or the app's live state, the kit and the page views take plain values and name no store, and no real person or device name is written in them. Plain greps.
set -u
cd "$(dirname "$0")/.."
fail=0
# check <what> <offending grep output>: a line of output is a failure.
check() { if [ -n "$2" ]; then printf '  ✗ %s:\n%s\n' "$1" "$2"; fail=1; else printf '  ✓ %s\n' "$1"; fi; }
HOSTREAD='Host\.current|localizedName|ComputerName|hostName|hostname|gethostname|uname|scutil|NSFullUserName|NSUserName|NSHomeDirectory|homeDirectoryForCurrentUser|getpwuid|getlogin|whoami|\$USER|\$LOGNAME|\$\{USER|LOGNAME|SCDynamicStore|ProcessInfo|getenv|environment\['
TOOL="scripts/render-settings.swift scripts/render-settings.sh"
NOTCOMMENT() { grep -vE '^[^:]*:[0-9]+:[[:space:]]*(#|//)' || true; }

check "the render tool is there" "$(ls scripts/render-settings.swift scripts/render-settings.sh 2>&1 >/dev/null || true)"
check "the render tool never reads the host name, the user or the environment" \
    "$(grep -nEi "$HOSTREAD" $TOOL | NOTCOMMENT)"
check "the render tool names no store and no live service" \
    "$(grep -nE 'KeychainStore|AppState|HookServer|AIService\.shared|LinkService\.shared|SMAppService|UserDefaults' $TOOL | NOTCOMMENT)"
# The kit and the page views (the files that exist so far; later tasks add the pages).
VIEWS="$(ls NotchBuddy/Sources/App/Settings{Shell,Page,Card,TabBar,Banner,GeneralPage,AgentsPage,ServicesPage,AIPage}.swift NotchBuddy/Sources/App/{SettingRow,SwitchRow,KeyRow,StatusChip,WrapRow,PathDisclosure,HelpText,CatSettingsView}.swift 2>/dev/null)"
check "there are kit files to look at" "$([ -n "$VIEWS" ] || echo 'no kit file found')"
check "the kit and the page views name no store, no live service and no home folder or user lookup" \
    "$(grep -nE 'AppState|KeychainStore|UserDefaults|NSHomeDirectory|homeDirectoryForCurrentUser|NSUserName|HookServer|AIService\.shared|LinkService\.shared' $VIEWS | NOTCOMMENT)"
check "no real device or person name in the kit, the page views and the render tool" \
    "$(grep -nwiE 'ike|lorenz|tazan' $VIEWS $TOOL || true)$(grep -niE 'raill' $VIEWS $TOOL || true)"
echo
if [ "$fail" = 0 ]; then echo "All tests passed."; else echo "1 test(s) failed."; exit 1; fi
