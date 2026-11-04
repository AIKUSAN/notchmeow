#!/usr/bin/env bash
# Sourced by the render scripts that build the app's own state (scripts/render-approval-card.sh). It runs a program in a home folder of its own and proves the program never
# reads the real one.
#   . scripts/render-home-guard.sh
#   render_home_guard <fake-home> <program> [args...]
# Why: `FileManager.default.homeDirectoryForCurrentUser` asks the user database and ignores $HOME, so the app's code (the "is Claude Code connected" checks read
# ~/.claude/settings.json) would read the real file whatever $HOME says. Two layers:
#   1. CFFIXED_USER_HOME points Foundation at the fake home, so the program reads the empty one;
#   2. a sandbox profile kills the program the moment it opens anything under the real ~/.claude, ~/.gemini or ~/.codex (the agent configs the app knows), for reading or writing,
#      so a new code path that bypasses layer 1 fails the render loudly instead of reading a file of the owner's.
# macOS only (dscl, sandbox-exec). It fails closed: with no way to fence the real home off, it runs nothing.
render_real_home() { dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}'; }

render_home_guard() {
    local fake="$1"; shift
    local real profile dir
    real="$(render_real_home)"
    if [ -z "$real" ] || [ "$real" = "$fake" ]; then echo "render-home-guard: cannot tell the real home from the fake one" >&2; return 1; fi
    command -v sandbox-exec > /dev/null || { echo "render-home-guard: sandbox-exec is missing, so the real home cannot be fenced off" >&2; return 1; }
    profile="(version 1)(allow default)"
    for dir in .claude .gemini .codex; do
        profile+="(deny file-read* file-write* (with send-signal SIGKILL) (subpath \"$real/$dir\"))"
    done
    HOME="$fake" CFFIXED_USER_HOME="$fake" sandbox-exec -p "$profile" "$@"
}
