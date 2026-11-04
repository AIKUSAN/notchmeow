#!/usr/bin/env bash
# Stage 7 of sub-project A, kept true: the old character's names and the cat's dead code stay out of the Mac code, its scripts and its tests.
#   - no "mochi" in any form (Done means: no mochi/Mochi identifiers remain; the cat coat "mocha" is another word);
#   - no BotEngine (the engine the cats replaced);
#   - none of the dead names the sweep removed: permanent emotes, miniEye and the eye alias, the morph and cup eyes, the mailbox morph, the mouth rect and
#     the suction, and the notifications nothing posts or observes (.botMorphTo, .botReject, .botGreet).
# Historical plans, specs and the git history keep their words; this reads only code, scripts and tests.
# Usage: bash scripts/check-no-leftovers.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SELF="check-no-leftovers.sh"
failed=0
check() {   # check <description> <grep -E pattern> [extra grep flags]
    local what="$1" pattern="$2"; shift 2
    local hits
    # The extra --exclude flags come after the --include list: BSD grep (macOS) ignores an --exclude given before the --include list.
    hits="$(grep -rInE --include='*.swift' --include='*.sh' --include='*.yml' --include='*.plist' --include='*.json' --exclude="$SELF" \
        --exclude-dir=build --exclude-dir=fixtures "$@" -- "$pattern" NotchBuddy scripts tests 2>/dev/null || true)"
    if [ -n "$hits" ]; then
        echo "✗ $what"
        echo "$hits" | head -8 | sed 's/^/    /'
        failed=1
    else
        echo "✓ $what"
    fi
}
check 'no "mochi" in the Mac code, scripts and tests' 'mochi' -i
check "no BotEngine: the cats replaced it" 'BotEngine'
check "no permanent emote, miniEye or eye alias" 'setPermanentEmote|miniEye|holdEye|\bEyeShape\b'
check "no mailbox morph, cup eye, mouth rect or suction in the drop view" 'USEyeShape|USMouthRect|\bmorph\b|botMorphTo|mailbox'
check "no notification that nothing posts or observes" 'botReject|botGreet|greetNotif'
check 'the old Settings tags live only in SettingsRoute.migrate (and its test)' '"activepills"|"integrations"' --exclude=SettingsRoute.swift --exclude=SettingsRulesTests.swift
check 'no Active pills page and no Hotkey group in Settings' 'title: "Active pills"|GroupBox\("Hotkey"\)|Save integrations'
# The step words are English now ("Reads · README.md"). The comments that quoted the old French ones ("Lit · README.md", "French step labels") stay gone, in the Mac code and in
# windows/src/core/claude.ts, the one file outside NotchBuddy/ that quoted them.
french="$(grep -nF -e 'Lit ·' -e 'French step' -- NotchBuddy/Sources/App/ClaudeChatViews.swift NotchBuddy/Sources/App/HookServer.swift windows/src/core/claude.ts || true)"
if [ -n "$french" ]; then
    echo "✗ no French step word in the comments"
    echo "$french" | head -8 | sed 's/^/    /'
    failed=1
else
    echo "✓ no French step word in the comments"
fi
exit "$failed"
