#!/usr/bin/env bash
# Builds NotchMeow-<version>-mac.dmg (and its .sha256) from a built NotchMeow.app, with macOS's own tools only.
#
#   bash scripts/make-dmg.sh <path to NotchMeow.app> <version> <existing output folder>
#
# The image holds NotchMeow.app and a link to /Applications, on a volume named "NotchMeow <version>", and nothing else a user can see. It has no
# background picture and no icon layout: a styled window needs a .DS_Store (docs/superpowers/plans/2026-10-16-d1b-dmg.md, "What a styled window
# would need"). The format is UDZO on APFS; NM_DMG_FORMAT=ULFO makes an lzfse image instead (macOS 10.11 or later).
#
# It checks what it made: the image verifies, it is sealed, and attached read-only under a folder of its own (never /Volumes, never Finder) it holds
# exactly the app and the link, the app's signature holds and the app says <version>. A mount is detached on every way out, and a failed run leaves
# no image behind. Called by scripts/release.sh --dmg; macOS only. NM_DMG_IDENTITY is the signing identity: "-" (ad hoc, the default); a Developer ID
# is D2's work and is refused for now (dmg_seal).
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
[ $# -eq 3 ] || { echo "usage: bash scripts/make-dmg.sh <path to NotchMeow.app> <version> <existing output folder>" >&2; exit 2; }
APP="$1"
VERSION="$2"
OUT="$3"
FORMAT="${NM_DMG_FORMAT-UDZO}"   # unset means UDZO; an empty value is refused below, not defaulted
IDENTITY="${NM_DMG_IDENTITY:--}"

case "$FORMAT" in
  UDZO|ULFO) ;;
  *) die "NM_DMG_FORMAT is '$FORMAT': use UDZO (the default) or ULFO" ;;
esac
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "'$VERSION' is not a version: use three whole numbers, like 0.9.0"
[ -d "$APP" ] && [ "$(basename "$APP")" = "NotchMeow.app" ] || die "$APP is not a NotchMeow.app"
[ -d "$OUT" ] || die "$OUT is not a folder"

DMGNAME="NotchMeow-$VERSION-mac.dmg"
DMG="$OUT/$DMGNAME"
VOLNAME="NotchMeow $VERSION"
[ ! -e "$DMG" ] && [ ! -e "$DMG.sha256" ] || die "$DMGNAME is already in $OUT: this script never overwrites a release file"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-dmg.XXXXXX")"
MOUNT=""
# An image can stay attached with no mount point (a check failed after hdiutil attached it, or verify left it so): detach it by its own device, found by its path.
detach_image_devices() {
  local dev
  dev=$(hdiutil info | awk -v p="$DMG" '/^image-path/ { on = (substr($0, index($0, ": ") + 2) == p) } /^=+$/ { on = 0 } on && $1 ~ /^\/dev\/disk[0-9]+$/ { print $1; exit }') || true
  if [ -n "$dev" ]; then hdiutil detach -quiet -force "$dev" > /dev/null 2>&1 || true; fi
}
cleanup() {
  local rc=$?
  if [ -n "$MOUNT" ] && [ -d "$MOUNT" ]; then
    hdiutil detach -quiet "$MOUNT" > /dev/null 2>&1 || hdiutil detach -quiet -force "$MOUNT" > /dev/null 2>&1 || true
  fi
  detach_image_devices
  rm -rf "$WORK"
  if [ "$rc" -ne 0 ]; then rm -f "$DMG" "$DMG.sha256"; fi
}
trap cleanup EXIT

# The signing step, and the one place D2 changes: a Developer ID signature of the image, then Apple's notarization of it and the ticket stapled to it.
# Until then only the ad hoc seal exists, like the app's and the zip's in a tester build.
dmg_seal() {   # dmg_seal <dmg>
  if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$1" > /dev/null 2>&1 || die "codesign could not seal the image"
  else
    die "signing the image with a Developer ID is D2's work (NM_DMG_IDENTITY must be -)"
  fi
}

# 1. Stage: ditto keeps the code signature, the extended attributes and the resource forks that cp -R can lose.
mkdir "$WORK/stage" "$WORK/mnt"
ditto "$APP" "$WORK/stage/NotchMeow.app"
ln -s /Applications "$WORK/stage/Applications"

# 2. Make the image. -srcfolder sizes it; no -ov (an existing file was refused above); -quiet keeps only the exit status.
hdiutil create -quiet -srcfolder "$WORK/stage" -volname "$VOLNAME" -fs APFS -format "$FORMAT" "$DMG" || die "hdiutil create failed"

# 3. Seal it, then prove it. (imageinfo and attach print a deprecation notice on stderr on recent macOS; stdout and the exit status are what is read.)
dmg_seal "$DMG"
codesign --verify "$DMG" > /dev/null 2>&1 || die "the sealed image does not verify"
hdiutil verify -quiet "$DMG" && VERIFIED=1 || VERIFIED=0
if [ "$VERIFIED" = 0 ]; then   # one retry (EAGAIN happens on a fresh image): the failed attempt's device goes first, then a second and last try
  detach_image_devices
  sleep 1
  hdiutil verify -quiet "$DMG" || die "hdiutil verify rejected the image twice"
fi
GOT_FORMAT=$(hdiutil imageinfo -format "$DMG" 2> /dev/null | tr -d ' \n')
[ "$GOT_FORMAT" = "$FORMAT" ] || die "the image is '$GOT_FORMAT', not $FORMAT"

MOUNT="$WORK/mnt/$VOLNAME"
hdiutil attach -nobrowse -readonly -noverify -noautoopen -mountroot "$WORK/mnt" "$DMG" > /dev/null 2>&1 || die "the image would not attach"
[ -d "$MOUNT" ] || die "the volume is not named '$VOLNAME'"
[ "$(ls "$MOUNT" | tr '\n' ' ')" = "Applications NotchMeow.app " ] || die "the image should hold NotchMeow.app and Applications and nothing else, it holds: $(ls "$MOUNT" | tr '\n' ' ')"
[ -L "$MOUNT/Applications" ] && [ "$(readlink "$MOUNT/Applications")" = "/Applications" ] || die "Applications in the image is not a link to /Applications"
codesign --verify --deep --strict "$MOUNT/NotchMeow.app" > /dev/null 2>&1 || die "the app in the image is not signed, or its signature does not hold"
IN_IMAGE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$MOUNT/NotchMeow.app/Contents/Info.plist")
[ "$IN_IMAGE" = "$VERSION" ] || die "the app in the image says $IN_IMAGE, not $VERSION"
hdiutil detach -quiet "$MOUNT" > /dev/null 2>&1 || hdiutil detach -quiet -force "$MOUNT" > /dev/null 2>&1 || die "the image would not detach"
MOUNT=""

# 4. The checksum, in the shape `shasum -a 256 -c` reads when run in the output folder.
(cd "$OUT" && shasum -a 256 "$DMGNAME" > "$DMGNAME.sha256")
echo "✓ $DMGNAME ($FORMAT, volume '$VOLNAME', sealed with $([ "$IDENTITY" = "-" ] && echo "an ad hoc signature" || echo "$IDENTITY"))"
