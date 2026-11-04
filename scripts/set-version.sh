#!/usr/bin/env bash
# Writes one version into every field that carries it, so a tester build says the same thing on every platform.
#
#   bash scripts/set-version.sh 0.9.0
#
# It changes, and nothing else:
#   NotchBuddy/project.yml          the main app's CFBundleShortVersionString, and its CFBundleVersion (the build number) raised by one
#   NotchBuddy/Resources/Info.plist rewritten by xcodegen from project.yml (the file release.sh reads)
#   windows/package.json            version
#   windows/package-lock.json       the two top-level version fields (the file's, and packages[""])
#   windows/src-tauri/tauri.conf.json   version
#   windows/Cargo.toml              [workspace.package] version
#   windows/Cargo.lock              the notchmeow and notchmeow-hook entries
# The App Store target keeps its own 1.0. A version is three whole numbers (0.9.0), because macOS reads CFBundleShortVersionString that way.
# Every run raises the build number by one. It commits nothing: look at `git diff`, add the CHANGELOG section, and commit. Needs xcodegen.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/version-fields.sh"

die() { echo "error: $*" >&2; exit 1; }

[ $# -eq 1 ] || { echo "usage: bash scripts/set-version.sh <version>   (three whole numbers, like 0.9.0)" >&2; exit 2; }
VERSION="$1"
vf_whole "$VERSION" || die "'$VERSION' is not a version: use three whole numbers, like 0.9.0 (no 'v', no extra part, no leading zero)"
command -v xcodegen >/dev/null || die "xcodegen is not installed (brew install xcodegen)"

# Every field to write must be there exactly once, or nothing is touched.
WRITTEN="yml yml_build pkg lock_top lock_root tauri cargo lock_app lock_hook"
for f in $WRITTEN; do
    vf_get "$f" >/dev/null || die "can't find $(vf_label "$f") in $(vf_file "$f") exactly once: nothing was changed"
done
OLD_BUILD=$(vf_get yml_build)
[[ "$OLD_BUILD" =~ ^[0-9]+$ ]] || die "the build number in NotchBuddy/project.yml is '$OLD_BUILD', not a whole number: nothing was changed"
NEW_BUILD=$((10#$OLD_BUILD + 1))

# A copy of each file and of the Xcode project (xcodegen rewrites it), put back if anything below fails.
FILES="NotchBuddy/project.yml NotchBuddy/Resources/Info.plist NotchBuddy/Resources/InfoAppStore.plist windows/package.json windows/package-lock.json windows/src-tauri/tauri.conf.json windows/Cargo.toml windows/Cargo.lock"
XCODEPROJ="NotchBuddy/NotchBuddy.xcodeproj"
BAK=$(mktemp -d "${TMPDIR:-/tmp}/nm-set-version.XXXXXX")
DONE=0
BACKED=0
restore() {
    KEEP=0
    if [ "$DONE" != 1 ] && [ "$BACKED" = 1 ]; then
        for f in $FILES; do cp -p "$BAK/$(echo "$f" | tr / _)" "$VF_ROOT/$f"; done
        # The project is removed only after its copy is in place, so a failed copy never leaves it missing.
        XC_NEW="$VF_ROOT/$XCODEPROJ.restore"
        if rm -rf "$XC_NEW" && cp -Rp "$BAK/xcodeproj" "$XC_NEW" && rm -rf "$VF_ROOT/$XCODEPROJ" && mv "$XC_NEW" "$VF_ROOT/$XCODEPROJ"; then
            echo "(every file is back as it was)" >&2
        else
            KEEP=1
            echo "error: could not put $XCODEPROJ back. Your backup is still in $BAK: copy it back by hand." >&2
        fi
    fi
    if [ "$KEEP" != 1 ]; then rm -rf "$BAK"; fi
}
trap restore EXIT
for f in $FILES; do cp -p "$VF_ROOT/$f" "$BAK/$(echo "$f" | tr / _)"; done
cp -Rp "$VF_ROOT/$XCODEPROJ" "$BAK/xcodeproj"
BACKED=1

for f in yml pkg lock_top lock_root tauri cargo lock_app lock_hook; do vf_put "$f" "$VERSION"; done
vf_put yml_build "$NEW_BUILD"
(cd "$VF_ROOT/NotchBuddy" && xcodegen generate --quiet) || die "xcodegen failed"

bash "$VF_ROOT/scripts/check-versions.sh" "$VERSION" || die "the files do not agree after writing"
DONE=1
echo "✓ version $VERSION, build number $OLD_BUILD → $NEW_BUILD. Nothing is committed: look at git diff, add the CHANGELOG section, and commit."
