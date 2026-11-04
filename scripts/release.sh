#!/usr/bin/env bash
# Builds, notarizes and publishes NotchMeow for macOS (GitHub build).
#
#   ./scripts/release.sh 0.1.2            build, sign, notarize, staple, tag, publish
#   ./scripts/release.sh 0.1.2 --finish   finish after an interrupted notarization wait
#   ./scripts/release.sh 0.9.0 --tester   a tester build: signed ad hoc, zipped with its checksum and notes in /tmp/notchmeow-release-0.9.0/,
#                                         from any branch; it never notarizes, tags, pushes or publishes
#   ./scripts/release.sh 0.9.0 --tester --dmg   the same, and a disk image beside the zip (scripts/make-dmg.sh); --dmg on the signed release is D2's work
#
# Run it from a clean checkout of main. CFBundleShortVersionString in
# NotchBuddy/project.yml must match the version, and CHANGELOG.md needs a
# "## <version>" section: it becomes the release notes. (--tester also needs
# scripts/set-version.sh to have been run: scripts/check-versions.sh must pass.)
set -euo pipefail

VERSION="${1:?Usage: $0 <version> [--finish|--tester] [--dmg]}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/notchmeow-release-$VERSION"
APP="$BUILD_DIR/NotchMeow.app"
ZIP="$BUILD_DIR/NotchMeow.zip"
COMMIT_FILE="$BUILD_DIR/commit"
TAG="v$VERSION"

die() { echo "error: $*" >&2; exit 1; }

MODE=""
WANT_DMG=0
for opt in "${@:2}"; do
  case "$opt" in
    --dmg) WANT_DMG=1 ;;
    --finish|--tester)
      [ -z "$MODE" ] || die "give only one of --finish and --tester"
      MODE="$opt" ;;
    *) die "unknown option '$opt' (the options are --finish, --tester and --dmg)" ;;
  esac
done
# The signed release's disk image needs a Developer ID signature, notarization and a stapled ticket: that is D2 (scripts/make-dmg.sh, dmg_seal).
[ "$WANT_DMG" = 0 ] || [ "$MODE" = "--tester" ] || die "--dmg works with --tester for now: the signed release's disk image is D2's work"

cd "$REPO_ROOT"

# ── Checks shared by both modes ───────────────────────────────────────────────
[ "$MODE" = "--tester" ] || command -v gh >/dev/null || die "gh is not installed (brew install gh)"

# The "## <version>" section of CHANGELOG.md, without leading or trailing blank lines.
CHANGES=$(awk -v head="## $VERSION" '
  index($0, head " ") == 1 || $0 == head { found = 1; next }
  found && /^## / { exit }
  found {
    if ($0 ~ /^[ \t\r]*$/) { if (started) blanks++; next }
    while (blanks > 0) { print ""; blanks-- }
    print; started = 1
  }
' CHANGELOG.md)
[ -n "$CHANGES" ] || die "CHANGELOG.md has no '## $VERSION' section"

# ── Tester build ──────────────────────────────────────────────────────────────
# A Release build signed ad hoc (the hardened runtime and the entitlements stay), from any branch, zipped with its checksum and notes. It notarizes,
# tags, pushes and publishes nothing, so it needs no gh, no Developer ID and no network. Nothing below this block changes for it, and this block
# changes nothing for the signed release. NM_TESTER_OUT puts the files in another (new or empty) folder: for tests and dry runs.
if [ "$MODE" = "--tester" ]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "commit or stash your changes first, the tester build has to match a commit"
  fi
  COMMIT=$(git rev-parse HEAD)
  BRANCH=$(git symbolic-ref --short -q HEAD || echo "(detached HEAD)")
  command -v xcodegen >/dev/null || die "xcodegen is not installed (brew install xcodegen)"
  bash scripts/check-versions.sh "$VERSION" || die "the version fields do not all say $VERSION: run scripts/set-version.sh $VERSION and commit"

  OUT="${NM_TESTER_OUT:-$BUILD_DIR}"
  APP="$OUT/build/NotchMeow.app"
  ZIPNAME="NotchMeow-$VERSION-mac.zip"
  if [ -n "${NM_TESTER_OUT:-}" ]; then
    [ -z "$(ls -A "$OUT" 2>/dev/null)" ] || die "$OUT is not empty"
  else
    rm -rf "$OUT"
  fi
  mkdir -p "$OUT"

  (cd NotchBuddy && xcodegen generate --quiet)
  git diff --quiet || die "xcodegen changed a tracked file: commit what xcodegen wrote, then run the tester build again"
  bash scripts/check-versions.sh "$VERSION" >/dev/null || die "xcodegen wrote files that do not all say $VERSION: commit the Info.plist it made"

  # OTHER_CODE_SIGN_FLAGS= drops project.yml's --timestamp, which would ask Apple's server for a timestamp an ad hoc signature does not need.
  # The STRIP settings take the debug map out of the binary before it is signed: without them it lists every object file by its full path, this Mac's home folder included.
  xcodebuild \
    -project NotchBuddy/NotchBuddy.xcodeproj \
    -scheme NotchBuddy \
    -configuration Release \
    -derivedDataPath "$OUT/build/derived" \
    build \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    OTHER_CODE_SIGN_FLAGS= \
    DEPLOYMENT_POSTPROCESSING=YES \
    STRIP_INSTALLED_PRODUCT=YES \
    STRIP_STYLE=debugging \
    CONFIGURATION_BUILD_DIR="$OUT/build"

  # Nothing of the Mac that built it: no path under its home folder anywhere in the app.
  if grep -r -a -q -F "$HOME/" "$APP"; then die "the app holds a path under $HOME: the debug map was not stripped"; fi

  # What was built: no debug panel, both kinds of Mac, a signature that holds, the runtime and the entitlements still on, and this version.
  bash scripts/check-app-binary.sh "$APP" release
  ARCHS_BUILT=$(lipo -archs "$APP/Contents/MacOS/NotchMeow")
  for arch in arm64 x86_64; do
    case " $ARCHS_BUILT " in
      *" $arch "*) ;;
      *) die "the app has no $arch code (it has: $ARCHS_BUILT): a tester build must run on Apple silicon and Intel" ;;
    esac
  done
  echo "✓ Apple silicon and Intel in one app ($ARCHS_BUILT)"
  codesign --verify --deep --strict "$APP" || die "codesign --verify failed"
  SIGNATURE=$(codesign -dv "$APP" 2>&1)
  grep -q "Signature=adhoc" <<<"$SIGNATURE" || die "the app is not signed ad hoc"
  grep -Eq "flags=0x[0-9a-f]+\([^)]*runtime" <<<"$SIGNATURE" || die "the hardened runtime is off in this build"
  ENTITLEMENTS=$(codesign -d --entitlements - "$APP" 2>/dev/null)
  grep -q "com.apple.security.automation.apple-events" <<<"$ENTITLEMENTS" || die "the entitlements are missing from this build"
  echo "✓ Signed ad hoc, hardened runtime on, entitlements in, signature intact"
  BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
  BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
  [ "$BUILT_VERSION" = "$VERSION" ] || die "the built app says $BUILT_VERSION, not $VERSION"

  ditto -c -k --keepParent "$APP" "$OUT/$ZIPNAME"
  (cd "$OUT" && shasum -a 256 "$ZIPNAME" > "$ZIPNAME.sha256")
  DMGNAME="NotchMeow-$VERSION-mac.dmg"
  if [ "$WANT_DMG" = 1 ]; then
    bash scripts/make-dmg.sh "$APP" "$VERSION" "$OUT"
  fi
  cat > "$OUT/NOTES.txt" <<NOTES
NotchMeow $VERSION, a tester build for macOS 15 or later (Apple silicon and Intel)
Build number $BUILD_NUMBER. Signed ad hoc, not notarized: macOS asks you to confirm it once.

Branch:  $BRANCH
Commit:  $COMMIT
Built:   $(date '+%Y-%m-%d %H:%M %Z')

Install
1. Unzip and drag NotchMeow to Applications, then open it. macOS refuses it once, because it isn't notarized.
2. Go to System Settings → Privacy & Security, click Open Anyway, and confirm.
3. To update to a later tester build, replace the app. macOS then asks once whether the new build may read NotchMeow's saved keys,
   because an unsigned build's identity changes with every build. Answer Always Allow.

What to try, and what to tell the owner: https://aikusan.github.io/notchmeow/testers.html
Check the download: shasum -a 256 -c $ZIPNAME.sha256
NOTES
  if [ "$WANT_DMG" = 1 ]; then
    cat >> "$OUT/NOTES.txt" <<NOTES

Disk image
The same app is also in $DMGNAME: open it and drag NotchMeow onto the Applications link, then follow steps 1 to 3 above from "open it".
Check the download: shasum -a 256 -c $DMGNAME.sha256
NOTES
  fi
  echo
  echo "✓ Tester build $VERSION ($BRANCH, $(git rev-parse --short "$COMMIT"))"
  echo "  $OUT/$ZIPNAME"
  echo "  $OUT/$ZIPNAME.sha256"
  echo "  $OUT/NOTES.txt"
  if [ "$WANT_DMG" = 1 ]; then
    echo "  $OUT/$DMGNAME"
    echo "  $OUT/$DMGNAME.sha256"
  fi
  echo "Nothing was notarized, tagged, pushed or published."
  exit 0
fi
# ── End of the tester build ───────────────────────────────────────────────────

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "tag $TAG already exists here"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists on GitHub"
fi

if [ "$MODE" != "--finish" ]; then
  # The release must match a commit: no uncommitted changes to tracked files.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "commit or stash your changes first, the release has to match a commit"
  fi
  COMMIT=$(git rev-parse HEAD)

  # ── 1. Developer ID identity ────────────────────────────────────────────────
  # "|| true": with pipefail, grep finding nothing would end the script silently.
  IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(Developer ID Application[^"]*\)".*/\1/' || true)
  [ -n "$IDENTITY" ] || die "no 'Developer ID Application' certificate found. Install it via Xcode → Settings → Accounts."
  echo "Signing with: $IDENTITY"

  # ── 2. xcodegen + Release build ─────────────────────────────────────────────
  cd "$REPO_ROOT/NotchBuddy"
  PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || true)
  [ "$PLIST_VERSION" = "$VERSION" ] || die "NotchBuddy/Resources/Info.plist is version $PLIST_VERSION, not $VERSION: run xcodegen and commit Info.plist"
  bash "$REPO_ROOT/scripts/check-versions.sh" "$VERSION" || die "the version fields do not all say $VERSION: run scripts/set-version.sh $VERSION and commit"
  xcodegen generate
  PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
  [ "$PLIST_VERSION" = "$VERSION" ] || die "project.yml says $PLIST_VERSION, not $VERSION: update CFBundleShortVersionString in NotchBuddy/project.yml"

  rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
  echo "$COMMIT" > "$COMMIT_FILE"

  xcodebuild \
    -project NotchBuddy.xcodeproj \
    -scheme NotchBuddy \
    -configuration Release \
    build \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEPLOYMENT_POSTPROCESSING=YES \
    STRIP_INSTALLED_PRODUCT=YES \
    STRIP_STYLE=debugging \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR"

  # ── 3. Zip + notarize ───────────────────────────────────────────────────────
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo
  echo "Sending to Apple for notarization. If you stop the wait (Ctrl+C), Apple keeps going:"
  echo "  check it with  xcrun notarytool history --keychain-profile notchmeow-notary"
  echo "  once Accepted  ./scripts/release.sh $VERSION --finish"
  echo
  xcrun notarytool submit "$ZIP" --keychain-profile notchmeow-notary --wait \
    || die "notarization failed: see xcrun notarytool log <id> --keychain-profile notchmeow-notary (the id is printed above)"
  cd "$REPO_ROOT"
else
  [ -d "$APP" ] && [ -f "$COMMIT_FILE" ] || die "nothing to finish in $BUILD_DIR, run ./scripts/release.sh $VERSION first"
  COMMIT=$(cat "$COMMIT_FILE")
fi

# ── 4. Staple + verify ────────────────────────────────────────────────────────
xcrun stapler staple "$APP" \
  || die "stapling failed: Apple has not accepted the build yet. Check xcrun notarytool history --keychain-profile notchmeow-notary, then run ./scripts/release.sh $VERSION --finish"
spctl -a -vv "$APP"

# ── 5. Re-zip (with the stapled app) ──────────────────────────────────────────
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Release zip ready: $ZIP"

# ── 6. Tag the built commit + GitHub release ──────────────────────────────────
NOTES="NotchMeow $VERSION for macOS 15 or later (Apple silicon and Intel).

Signed with a Developer ID and notarized by Apple.

## What's new

$CHANGES

## Install

1. Download NotchMeow.zip below and unzip it.
2. Move NotchMeow.app to your Applications folder, replacing the old one if you have it.
3. Launch it, and click Open when macOS asks you to confirm.

Linux and Windows: see the [README](https://github.com/AIKUSAN/notchmeow#readme)."

echo
echo "──────── Release notes ────────"
echo "$NOTES"
echo "───────────────────────────────"
echo
read -r -p "Tag $(git rev-parse --short "$COMMIT") as $TAG and publish this release? [y/N] " ANSWER
case "$ANSWER" in
  y|Y|yes|oui|o|O) ;;
  *) die "stopped before tagging. Run ./scripts/release.sh $VERSION --finish to publish later." ;;
esac

git tag "$TAG" "$COMMIT"
git push origin "$TAG"

gh release create "$TAG" "$ZIP" \
  --repo AIKUSAN/notchmeow \
  --title "NotchMeow $VERSION" \
  --latest \
  --notes "$NOTES"

echo "✓ $TAG released: https://github.com/AIKUSAN/notchmeow/releases/tag/$TAG"
