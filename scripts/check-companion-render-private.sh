#!/usr/bin/env bash
# Plain greps over the companion's render tool (F3a-mac, Task 10). What they prove, literally: the tool itself (scripts/render-companion.swift and its script) names no host or
# user lookup, no real pasteboard, no defaults suite, no Keychain type and no hook server; it names one real store path, in the root check that stops it outside its home folder;
# no literal home-folder or private-temp path appears in it; and no real person or device name is written in it. These greps are not the guard: the runtime root check in the
# tool is (it refuses to draw if the store would be outside the --home folder).
# What the greps cannot cover, stated plainly: the app's own views read the Keychain on appear (PromptView.onAppear → AIService.prewarm → KeychainStore.shared loads the items
# of service io.github.aikusan.notchmeow, read-only), and if ImageRenderer fires ModelPickerView.onAppear it probes 127.0.0.1 local-model ports. Nothing from those reads is
# printed, drawn, sent or stored. The script itself reads $TMPDIR and $HOME to make its folders and clean up.
set -u
cd "$(dirname "$0")/.."
fail=0
# check <what> <offending grep output>: a line of output is a failure.
check() { if [ -n "$2" ]; then printf '  ✗ %s:\n%s\n' "$1" "$2"; fail=1; else printf '  ✓ %s\n' "$1"; fi; }
HOSTREAD='Host\.current|localizedName|ComputerName|hostName|hostname|gethostname|uname|scutil|NSFullUserName|NSUserName|NSHomeDirectory|homeDirectoryForCurrentUser|getpwuid|getlogin|whoami|\$USER|\$LOGNAME|\$\{USER|LOGNAME|SCDynamicStore|ProcessInfo|getenv|environment\['
TOOL="scripts/render-companion.swift scripts/render-companion.sh"
# Drops the lines whose first code is a comment. Every grep below runs with -H, so each line starts with file:line: and the pattern can match it.
NOTCOMMENT() { grep -vE '^[^:]*:[0-9]+:[[:space:]]*(#|//)' || true; }

check "the render tool and its script are there" "$(ls scripts/render-companion.swift scripts/render-companion.sh 2>&1 >/dev/null || true)"
check "the render tool (both files) names no host, user or environment lookup" \
    "$(grep -HnEi "$HOSTREAD" $TOOL | NOTCOMMENT)"
check "the render tool itself names no real pasteboard, no defaults suite and no Keychain type" \
    "$(grep -HnE 'NSPasteboard|UserDefaults|KeychainStore|suiteName' scripts/render-companion.swift | NOTCOMMENT)"
check "the render tool itself names no hook server and no send or live-service call" \
    "$(grep -HnE 'HookServer|LinkService\.shared|AIService\.shared\.(discover|refresh)|ClaudeService\.shared\.send|Sidekick\.shared' scripts/render-companion.swift | NOTCOMMENT)"
check "the only real store path named is the root check (exactly one line, no other mention of the real store)" \
    "$(grep -HnE 'CompanionFiles\.standard\(\)' scripts/render-companion.swift | grep -vE '^[^:]*:[0-9]+:[[:space:]]*let storeRoot = CompanionFiles\.standard\(\)\.root\.resolvingSymlinksInPath\(\)\.path[[:space:]]*$' | NOTCOMMENT)"
check "no literal home-folder or private-temp Library path in the tool and its script (a literal grep; the runtime root check is the real guard)" \
    "$(grep -HnE '/Users/|~/|/home/|/private/var/folders/[^"]*/Library' $TOOL | NOTCOMMENT)"
check "no sample text carries a home-folder path (a literal grep on the string literals)" \
    "$(grep -HnE '"[^"]*(/Users/|~/)' scripts/render-companion.swift | NOTCOMMENT)"
check "no real device or person name in the render tool and its script" \
    "$(grep -nwiE 'ike|lorenz|tazan' $TOOL || true)$(grep -niE 'raill' $TOOL || true)"
echo
if [ "$fail" = 0 ]; then echo "All tests passed."; else echo "1 test(s) failed."; exit 1; fi
