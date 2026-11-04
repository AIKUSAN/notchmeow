#!/usr/bin/env bash
# Tests the release tools on temporary copies of the version files. Nothing in the repository is touched, nothing is built, and no app is run.
#   - set-version.sh: exactly which files and lines change, the App Store target's own 1.0 left alone, the build number up by one on every run;
#   - a bad version refused with nothing changed, a missing field refused before any write, a failed xcodegen putting every file back;
#   - check-versions.sh failing for every kind of disagreement, and reading a checkout with Windows line endings;
#   - the three permission strings in English, in project.yml and in both Info.plists xcodegen makes from it;
#   - release.sh --tester refusing before it runs xcodegen or xcodebuild, working from any branch without gh, and the arguments it gives xcodebuild
#     (the build itself is checked by Task 6 of docs/superpowers/plans/2026-10-08-d1-tools.md);
#   - the QA brief's sample payloads (docs/QA-MAC.md): valid JSON, and marked as the QA session's own.
# Needs xcodegen (the macOS job installs it). Usage: bash scripts/test-release-tools.sh
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
command -v xcodegen >/dev/null || { echo "✗ xcodegen is needed to test the version tools (brew install xcodegen)" >&2; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-versions.XXXXXX")"
detach_all() {   # an image a failing test left attached, found by its mount folder: all of them are under $TMP
    local m
    for m in "$TMP"/dmg/mnt/* "$TMP"/dmg/tmp/*/mnt/*; do
        if [ -d "$m" ]; then hdiutil detach -quiet -force "$m" > /dev/null 2>&1 || true; fi   # a plain if: a missing folder must not make the trap fail the run
    done
    # an image attached with no mount point (hdiutil verify can leave one) has no mount folder: detach it by its own device, found by its path under $TMP
    local dev
    for dev in $(hdiutil info | awk -v p="$TMP/" '/^image-path/ { on = (index(substr($0, index($0, ": ") + 2), p) == 1) } /^=+$/ { on = 0 } on && $1 ~ /^\/dev\/disk[0-9]+$/ { print $1 }') ; do
        hdiutil detach -quiet -force "$dev" > /dev/null 2>&1 || true
    done
}
trap 'detach_all; rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "✓ $1"; }
no() {
    fail=$((fail + 1))
    echo "✗ $1"
    shift
    for line in "$@"; do printf '%s\n' "$line" | sed 's/^/    /'; done
}
expect() {   # expect <description> <got> <wanted>
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "wanted: $3" "got:    $2"; fi
}
contains() {   # contains <description> <text> <word>
    if grep -qF -- "$3" <<<"$2"; then ok "$1"; else no "$1" "wanted a line with: $3" "got:" "$2"; fi
}

VERSION_FILES="NotchBuddy/project.yml NotchBuddy/Resources/Info.plist NotchBuddy/Resources/InfoAppStore.plist windows/package.json windows/package-lock.json windows/src-tauri/tauri.conf.json windows/Cargo.toml windows/Cargo.lock"
TOOLS="scripts/set-version.sh scripts/check-versions.sh scripts/version-fields.sh scripts/version-fields.awk scripts/release.sh scripts/make-dmg.sh scripts/check-app-binary.sh"
GIT="git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false"

tree() {   # tree <name>: a git repository holding copies of the version files, the tools, the changelog, the Xcode project and what xcodegen reads from it
    local d="$TMP/$1" f
    mkdir -p "$d/NotchBuddy/Resources"
    cp -Rp "$REPO/NotchBuddy/Sources" "$REPO/NotchBuddy/Assets.xcassets" "$REPO/NotchBuddy/NotchBuddy.xcodeproj" "$d/NotchBuddy/"
    cp -Rp "$REPO/NotchBuddy/Resources/sounds" "$d/NotchBuddy/Resources/"
    for f in $VERSION_FILES $TOOLS CHANGELOG.md; do
        mkdir -p "$d/$(dirname "$f")"
        cp -p "$REPO/$f" "$d/$f"
    done
    (cd "$d" && git -c init.defaultBranch=main init -q && git add -A && $GIT commit -qm base)
    echo "$d"
}
field() {   # field <tree> <field>: the value the tools read
    VF_ROOT="$1" bash -c 'source "$VF_ROOT/scripts/version-fields.sh"; vf_get "$0"' "$2"
}
setfield() {   # setfield <tree> <field> <value>: the tools' own writer, to make a disagreement
    VF_ROOT="$1" bash -c 'source "$VF_ROOT/scripts/version-fields.sh"; vf_put "$0" "$1"' "$2" "$3"
}
run() {   # run <tree> <output file> <command...>: prints the exit code
    local d="$1" out="$2" rc=0
    shift 2
    (cd "$d" && "$@") > "$out" 2>&1 || rc=$?
    echo "$rc"
}
changes() {   # changes <tree>: every changed line of every changed tracked file, as "file<TAB>-old line" or "file<TAB>+new line", sorted
    local d="$1" f
    for f in $(cd "$d" && git diff --name-only); do
        (cd "$d" && git diff -U0 --no-color -- "$f") | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' | sed "s|^|$f$(printf '\t')|" || true
    done | LC_ALL=C sort
}
sorted() { LC_ALL=C sort; }

# ── 1. set-version.sh writes exactly the lines the spec lists ───────────────────────────────────────────────────────
P="$(tree pristine)"
o_yml=$(field "$P" yml); o_plist=$(field "$P" plist); o_pkg=$(field "$P" pkg); o_lt=$(field "$P" lock_top); o_lr=$(field "$P" lock_root)
o_tauri=$(field "$P" tauri); o_cargo=$(field "$P" cargo); o_la=$(field "$P" lock_app); o_lh=$(field "$P" lock_hook); ob=$(field "$P" yml_build)
nb=$((ob + 1))
A="$(tree a)"
expect "set-version.sh 7.7.7 succeeds" "$(run "$A" "$TMP/a1.out" bash scripts/set-version.sh 7.7.7)" 0
{
    printf 'NotchBuddy/Resources/Info.plist\t-\t<string>%s</string>\n' "$o_plist"
    printf 'NotchBuddy/Resources/Info.plist\t-\t<string>%s</string>\n' "$ob"
    printf 'NotchBuddy/Resources/Info.plist\t+\t<string>%s</string>\n' 7.7.7
    printf 'NotchBuddy/Resources/Info.plist\t+\t<string>%s</string>\n' "$nb"
    printf 'NotchBuddy/project.yml\t-        CFBundleShortVersionString: "%s"\n' "$o_yml"
    printf 'NotchBuddy/project.yml\t-        CFBundleVersion: "%s"\n' "$ob"
    printf 'NotchBuddy/project.yml\t+        CFBundleShortVersionString: "%s"\n' 7.7.7
    printf 'NotchBuddy/project.yml\t+        CFBundleVersion: "%s"\n' "$nb"
    printf 'windows/Cargo.lock\t-version = "%s"\n' "$o_la" "$o_lh"
    printf 'windows/Cargo.lock\t+version = "%s"\n' 7.7.7 7.7.7
    printf 'windows/Cargo.toml\t-version = "%s"\n' "$o_cargo"
    printf 'windows/Cargo.toml\t+version = "%s"\n' 7.7.7
    printf 'windows/package-lock.json\t-  "version": "%s",\n' "$o_lt"
    printf 'windows/package-lock.json\t-      "version": "%s",\n' "$o_lr"
    printf 'windows/package-lock.json\t+  "version": "%s",\n' 7.7.7
    printf 'windows/package-lock.json\t+      "version": "%s",\n' 7.7.7
    printf 'windows/package.json\t-  "version": "%s",\n' "$o_pkg"
    printf 'windows/package.json\t+  "version": "%s",\n' 7.7.7
    printf 'windows/src-tauri/tauri.conf.json\t-  "version": "%s",\n' "$o_tauri"
    printf 'windows/src-tauri/tauri.conf.json\t+  "version": "%s",\n' 7.7.7
} | sorted > "$TMP/wanted.txt"
changes "$A" > "$TMP/got.txt"
if diff "$TMP/wanted.txt" "$TMP/got.txt" > "$TMP/lines.diff"; then
    ok "7 files change, on 11 lines (project.yml 2, Info.plist 2, package.json 1, package-lock.json 2, tauri.conf.json 1, Cargo.toml 1, Cargo.lock 2) and no other"
else
    no "the changed files and lines are not the ones the spec lists" "$(cat "$TMP/lines.diff")"
fi
expect "the build number went from $ob to $nb in project.yml" "$(field "$A" yml_build)" "$nb"
expect "and in Info.plist" "$(field "$A" plist_build)" "$nb"
expect "the App Store target keeps its own 1.0" "$(field "$A" yml_store)" "1.0"
expect "check-versions.sh 7.7.7 agrees" "$(run "$A" "$TMP/a2.out" bash scripts/check-versions.sh 7.7.7)" 0
contains "and prints the App Store number without comparing it" "$(cat "$TMP/a2.out")" "1.0  (its own number, not compared)"
expect "a second run, set-version.sh 7.7.8, succeeds" "$(run "$A" "$TMP/a3.out" bash scripts/set-version.sh 7.7.8)" 0
expect "every run raises the build number by one" "$(field "$A" yml_build) $(field "$A" plist_build)" "$((nb + 1)) $((nb + 1))"
expect "and the new version is everywhere" "$(run "$A" "$TMP/a4.out" bash scripts/check-versions.sh 7.7.8)" 0

# ── 2. A bad version is refused and nothing changes ─────────────────────────────────────────────────────────────────
B="$(tree bad)"
for v in "0.9" "0.9.0.1" "v0.9.0" "0.9.x" "01.2.3" "0.9.0-beta" " 0.9.0" "0.9.0 " "-1.0.0" "" "0.9.0"$'\n'"1.0.0" "9999999999.0.0"; do
    rc=$(run "$B" "$TMP/bad.out" bash scripts/set-version.sh "$v")
    if [ "$rc" = 1 ] && [ -z "$(cd "$B" && git status --porcelain)" ]; then ok "refused, nothing changed: '$(printf '%s' "$v" | tr '\n' '|')'"; else no "'$v' should be refused with nothing changed (exit $rc)" "$(cd "$B" && git status --porcelain)"; fi
done
expect "no argument is a usage error (2)" "$(run "$B" "$TMP/bad.out" bash scripts/set-version.sh)" 2
expect "two arguments are a usage error (2)" "$(run "$B" "$TMP/bad.out" bash scripts/set-version.sh 0.9.0 --force)" 2
for v in 0.9.0 1.0.0 10.20.30 0.0.1; do
    vf=$(VF_ROOT="$B" bash -c 'source "$VF_ROOT/scripts/version-fields.sh"; vf_whole "$0" && echo yes || echo no' "$v")
    expect "'$v' is a version" "$vf" yes
done

# A field that is not there exactly once stops the run before it writes anything.
D="$(tree missing)"
(cd "$D" && awk '/^name = "notchmeow-hook"$/ { print; getline; next } { print }' windows/Cargo.lock > "$TMP/lock" && cat "$TMP/lock" > windows/Cargo.lock && git add -A && $GIT commit -qm broken)
rc=$(run "$D" "$TMP/d.out" bash scripts/set-version.sh 7.7.7)
if [ "$rc" != 0 ] && [ -z "$(cd "$D" && git status --porcelain)" ]; then ok "a missing Cargo.lock entry is refused before any file is written"; else no "a missing field should stop the run (exit $rc)" "$(cd "$D" && git status --porcelain)"; fi
contains "and the message names the file" "$(cat "$TMP/d.out")" "windows/Cargo.lock"

# xcodegen failing puts every file back.
mkdir -p "$TMP/failing"
printf '#!/bin/sh\nexit 1\n' > "$TMP/failing/xcodegen"
chmod +x "$TMP/failing/xcodegen"
C="$(tree rollback)"
rc=0
(cd "$C" && PATH="$TMP/failing:$PATH" bash scripts/set-version.sh 7.7.7) > "$TMP/c.out" 2>&1 || rc=$?
if [ "$rc" != 0 ] && [ -z "$(cd "$C" && git status --porcelain)" ]; then ok "a failing xcodegen leaves every file as it was"; else no "a failing xcodegen should put the files back (exit $rc)" "$(cd "$C" && git status --porcelain)"; fi

# xcodegen that rewrites the Xcode project and then fails: the project comes back byte for byte, with nothing else changed.
mkdir -p "$TMP/touching"
printf '#!/bin/sh\necho "// stub" >> NotchBuddy.xcodeproj/project.pbxproj\nexit 1\n' > "$TMP/touching/xcodegen"
chmod +x "$TMP/touching/xcodegen"
X="$(tree project-rollback)"
cp -p "$X/NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj" "$TMP/pbxproj.orig"
rc=0
(cd "$X" && PATH="$TMP/touching:$PATH" bash scripts/set-version.sh 7.7.7) > "$TMP/x.out" 2>&1 || rc=$?
if [ "$rc" != 0 ] && cmp -s "$TMP/pbxproj.orig" "$X/NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj" && [ -z "$(cd "$X" && git status --porcelain)" ]; then ok "a failing xcodegen that wrote the Xcode project leaves the project byte for byte as it was"; else no "the Xcode project should be restored after a failing xcodegen (exit $rc)" "$(cd "$X" && git status --porcelain)"; fi

# A build number with a leading zero is counted in decimal: 08 goes to 9, and the run does not read it as octal.
G="$(tree build08)"
setfield "$G" yml_build 08
expect "a build number 08 is raised to 9 (exit 0, build 9)" "$(run "$G" "$TMP/g.out" bash scripts/set-version.sh 7.7.7):$(field "$G" yml_build)" "0:9"

# ── 3. check-versions.sh catches disagreement ──────────────────────────────────────────────────────────────────────
E="$(tree good)"
(cd "$E" && bash scripts/set-version.sh 7.7.7 > /dev/null && git add -A && $GIT commit -qm "7.7.7")
expect "check-versions.sh passes when every field agrees" "$(run "$E" "$TMP/e.out" bash scripts/check-versions.sh)" 0
for f in yml plist pkg lock_top lock_root tauri cargo lock_app lock_hook; do
    cp -R "$E" "$TMP/e-$f"
    setfield "$TMP/e-$f" "$f" 7.7.9
    rc=$(run "$TMP/e-$f" "$TMP/e-$f.out" bash scripts/check-versions.sh)
    if [ "$rc" = 1 ] && grep -q "the versions disagree: " "$TMP/e-$f.out" && grep -q "7.7.9 (1 field)" "$TMP/e-$f.out" && grep -q "7.7.7 (8 fields)" "$TMP/e-$f.out"; then ok "one field different is caught: $f"; else no "$f at 7.7.9 should fail with a disagreement (exit $rc)" "$(cat "$TMP/e-$f.out")"; fi
done
cp -R "$E" "$TMP/e-build"
setfield "$TMP/e-build" plist_build 99
rc=$(run "$TMP/e-build" "$TMP/e-build.out" bash scripts/check-versions.sh)
if [ "$rc" = 1 ] && grep -q "the build number is" "$TMP/e-build.out" && ! grep -q "missing or not in the shape" "$TMP/e-build.out"; then ok "an Info.plist with another build number is caught, and no 'missing' message comes with it"; else no "a stale build number should fail (exit $rc)" "$(cat "$TMP/e-build.out")"; fi
cp -R "$E" "$TMP/e-gone"
(cd "$TMP/e-gone" && awk '/^name = "notchmeow"$/ { print; getline; next } { print }' windows/Cargo.lock > "$TMP/lock2" && cat "$TMP/lock2" > windows/Cargo.lock)
rc=$(run "$TMP/e-gone" "$TMP/e-gone.out" bash scripts/check-versions.sh)
if [ "$rc" = 1 ] && grep -q "not found exactly once" "$TMP/e-gone.out"; then ok "a field that cannot be found is caught"; else no "a missing field should fail (exit $rc)" "$(cat "$TMP/e-gone.out")"; fi
cp -R "$E" "$TMP/e-two"
for f in yml plist pkg lock_top lock_root tauri cargo lock_app lock_hook; do setfield "$TMP/e-two" "$f" 7.7; done
rc=$(run "$TMP/e-two" "$TMP/e-two.out" bash scripts/check-versions.sh)
if [ "$rc" = 1 ] && grep -q "not three whole numbers" "$TMP/e-two.out"; then ok "fields that agree on something that is not three whole numbers are caught"; else no "7.7 everywhere should fail (exit $rc)" "$(cat "$TMP/e-two.out")"; fi
expect "check-versions.sh 7.7.7 passes" "$(run "$E" "$TMP/e.out" bash scripts/check-versions.sh 7.7.7)" 0
expect "check-versions.sh 7.7.8 fails when the fields say 7.7.7" "$(run "$E" "$TMP/e.out" bash scripts/check-versions.sh 7.7.8)" 1
contains "and says so" "$(cat "$TMP/e.out")" "every field says 7.7.7, not 7.7.8"
expect "check-versions.sh banana is a usage error (2)" "$(run "$E" "$TMP/e.out" bash scripts/check-versions.sh banana)" 2
expect "check-versions.sh \"\" is a usage error (2), even when the fields agree" "$(run "$E" "$TMP/e.out" bash scripts/check-versions.sh "")" 2

# A checkout with Windows line endings (the Windows runner may have one) reads the same, and is written back the same.
cp -R "$E" "$TMP/e-crlf"
CR="$(printf '\r')"
for f in $VERSION_FILES; do sed "s/\$/$CR/" "$E/$f" > "$TMP/e-crlf/$f"; done
expect "a checkout with CRLF line endings agrees" "$(run "$TMP/e-crlf" "$TMP/crlf.out" bash scripts/check-versions.sh 7.7.7)" 0
setfield "$TMP/e-crlf" pkg 7.7.9
expect "and a version written into it is there" "$(field "$TMP/e-crlf" pkg)" 7.7.9
expect "and every line of that file still ends in CRLF" "$(grep -c "$CR\$" "$TMP/e-crlf/windows/package.json")" "$(wc -l < "$TMP/e-crlf/windows/package.json" | tr -d ' ')"

# ── 4. The three permission strings are in English, in project.yml and in both Info.plists ────────────────────────────
APPLE='NotchMeow uses this to jump to your terminal, send mail and control Music or Spotify.'
AX="NotchMeow uses this to read the active window's title and attach it as context."
NET='NotchMeow uses this to reach an AI model server you added on your network, and, only if you turn on Visible on this network, to find and pair with your other Macs and PCs and send files to them.'
yml="$REPO/NotchBuddy/project.yml"
expect "project.yml: NSAppleEventsUsageDescription, once" "$(grep -cF "NSAppleEventsUsageDescription: \"$APPLE\"" "$yml")" 1
expect "project.yml: NSAccessibilityUsageDescription, once" "$(grep -cF "NSAccessibilityUsageDescription: \"$AX\"" "$yml")" 1
expect "project.yml: NSLocalNetworkUsageDescription, in both targets" "$(grep -cF "NSLocalNetworkUsageDescription: \"$NET\"" "$yml")" 2
expect "project.yml: no French usage string is left" "$(grep -c 'UsageDescription: "Pour ' "$yml" || true)" 0
S="$(tree strings)"
(cd "$S/NotchBuddy" && xcodegen generate --quiet)
for p in Info.plist InfoAppStore.plist; do
    if cmp -s "$S/NotchBuddy/Resources/$p" "$REPO/NotchBuddy/Resources/$p"; then ok "$p is what xcodegen makes of project.yml"; else no "$p is stale: run cd NotchBuddy && xcodegen, and commit it"; fi
done
plist="$REPO/NotchBuddy/Resources/Info.plist"
expect "Info.plist asks to jump to the terminal in English" "$(plutil -extract NSAppleEventsUsageDescription raw -o - "$plist")" "$APPLE"
expect "Info.plist asks to read the window title in English" "$(plutil -extract NSAccessibilityUsageDescription raw -o - "$plist")" "$AX"
expect "Info.plist asks to reach a model server in English" "$(plutil -extract NSLocalNetworkUsageDescription raw -o - "$plist")" "$NET"
expect "InfoAppStore.plist asks to reach a model server in English" "$(plutil -extract NSLocalNetworkUsageDescription raw -o - "$REPO/NotchBuddy/Resources/InfoAppStore.plist")" "$NET"
if plutil -extract NSAppleEventsUsageDescription raw -o - "$REPO/NotchBuddy/Resources/InfoAppStore.plist" > /dev/null 2>&1; then no "the App Store build asks for Apple events, which it never did"; else ok "the App Store build still asks for the local network only"; fi

# ── 5. release.sh --tester: what it refuses, and what it hands xcodebuild ─────────────────────────────────────────────
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/xcodegen" <<'STUB'
#!/bin/sh
echo "$PWD $*" >> "$STUB_LOG/xcodegen.log"
STUB
cat > "$STUBS/xcodebuild" <<'STUB'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >> "$STUB_LOG/xcodebuild.log"
echo "stub xcodebuild: not building" >&2
exit 1
STUB
chmod +x "$STUBS/xcodegen" "$STUBS/xcodebuild"
NOGH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin"   # no Homebrew on the path: no gh, and the stubs stand in for xcodegen and xcodebuild
if (PATH="$NOGH"; command -v gh > /dev/null); then no "gh is on the test's own path, so 'needs no gh' cannot be tested here"; else ok "the test's path has no gh"; fi
rel() {   # rel <tree> <logs> <args...>: release.sh with the stubs; prints the exit code, leaves the output in <logs>/out
    local d="$1" logs="$2" rc=0
    shift 2
    mkdir -p "$logs"
    (cd "$d" && STUB_LOG="$logs" PATH="$NOGH" NM_TESTER_OUT="$logs/result" bash scripts/release.sh "$@") > "$logs/out" 2>&1 || rc=$?
    echo "$rc"
}
untouched() { [ ! -e "$1/xcodegen.log" ] && [ ! -e "$1/xcodebuild.log" ]; }

R="$TMP/release"
cp -R "$E" "$R"
printf '\n## 7.7.7 — tester build\n\n- the test'"'"'s one line\n' >> "$R/CHANGELOG.md"
(cd "$R" && $GIT commit -qam "changelog")

rc=$(rel "$R" "$TMP/l1" 7.7.7 --bogus)
if [ "$rc" != 0 ] && grep -q "unknown option" "$TMP/l1/out" && untouched "$TMP/l1"; then ok "release.sh refuses an option it does not know"; else no "release.sh 7.7.7 --bogus should be refused (exit $rc)" "$(cat "$TMP/l1/out")"; fi

rc=$(rel "$E" "$TMP/l2" 7.7.7 --tester)
if [ "$rc" != 0 ] && grep -q "CHANGELOG.md has no '## 7.7.7' section" "$TMP/l2/out" && untouched "$TMP/l2"; then ok "--tester needs a CHANGELOG section for the version"; else no "a missing CHANGELOG section should be refused (exit $rc)" "$(cat "$TMP/l2/out")"; fi

cp -R "$R" "$TMP/dirty"
echo "edit" >> "$TMP/dirty/CHANGELOG.md"
rc=$(rel "$TMP/dirty" "$TMP/l3" 7.7.7 --tester)
if [ "$rc" != 0 ] && grep -q "commit or stash your changes" "$TMP/l3/out" && untouched "$TMP/l3"; then ok "--tester refuses a tree with an uncommitted change to a tracked file"; else no "a dirty tree should be refused (exit $rc)" "$(cat "$TMP/l3/out")"; fi

cp -R "$R" "$TMP/split"
setfield "$TMP/split" pkg 7.7.9
(cd "$TMP/split" && $GIT commit -qam "package.json drifts")
rc=$(rel "$TMP/split" "$TMP/l4" 7.7.7 --tester)
if [ "$rc" != 0 ] && grep -q "the versions disagree" "$TMP/l4/out" && untouched "$TMP/l4"; then ok "--tester refuses version fields that disagree"; else no "disagreeing fields should be refused (exit $rc)" "$(cat "$TMP/l4/out")"; fi

cp -R "$R" "$TMP/other"
printf '\n## 7.7.8 — tester build\n\n- another\n' >> "$TMP/other/CHANGELOG.md"
(cd "$TMP/other" && $GIT commit -qam "changelog 7.7.8")
rc=$(rel "$TMP/other" "$TMP/l5" 7.7.8 --tester)
if [ "$rc" != 0 ] && grep -q "every field says 7.7.7, not 7.7.8" "$TMP/l5/out" && untouched "$TMP/l5"; then ok "--tester refuses a version the files do not say"; else no "7.7.8 against files that say 7.7.7 should be refused (exit $rc)" "$(cat "$TMP/l5/out")"; fi

# The good case runs as far as xcodebuild, whatever the branch, and needs no gh. The stub xcodebuild fails, so nothing is built.
(cd "$R" && git switch -q -c feature/anything)
rc=$(rel "$R" "$TMP/l6" 7.7.7 --tester)
if [ "$rc" != 0 ] && [ -s "$TMP/l6/xcodegen.log" ] && [ -s "$TMP/l6/xcodebuild.log" ]; then ok "--tester gets as far as xcodegen and xcodebuild from a branch that is not main, without gh on the path"; else no "the good case should reach xcodebuild (exit $rc)" "$(cat "$TMP/l6/out")"; fi
(cd "$R" && git switch -q --detach)
rc=$(rel "$R" "$TMP/l7" 7.7.7 --tester)
if [ -s "$TMP/l7/xcodebuild.log" ]; then ok "and from a detached HEAD"; else no "a detached HEAD should be fine (exit $rc)" "$(cat "$TMP/l7/out")"; fi
# xcodegen that changes a tracked file (here CHANGELOG.md) stops the tester build before check-versions.sh and xcodebuild.
mkdir -p "$TMP/xstubs" "$TMP/l8"
printf '#!/bin/sh\necho "stub line" >> ../CHANGELOG.md\nexit 0\n' > "$TMP/xstubs/xcodegen"
chmod +x "$TMP/xstubs/xcodegen"
cp "$STUBS/xcodebuild" "$TMP/xstubs/xcodebuild"
cp -R "$R" "$TMP/xdirty"
rc=0
(cd "$TMP/xdirty" && PATH="$TMP/xstubs:/usr/bin:/bin:/usr/sbin:/sbin" NM_TESTER_OUT="$TMP/l8/result" bash scripts/release.sh 7.7.7 --tester) > "$TMP/l8/out" 2>&1 || rc=$?
if [ "$rc" != 0 ] && grep -q "xcodegen changed a tracked file" "$TMP/l8/out" && [ ! -e "$TMP/l8/xcodebuild.log" ]; then ok "--tester refuses when xcodegen changes a tracked file"; else no "xcodegen changing a tracked file should stop the tester build (exit $rc)" "$(cat "$TMP/l8/out")"; fi

contains "xcodegen ran in the NotchBuddy folder" "$(cat "$TMP/l6/xcodegen.log")" "/release/NotchBuddy generate --quiet"
args="$(cat "$TMP/l6/xcodebuild.log")"
contains "xcodebuild gets the Release configuration" "$(grep -A1 -x -- '-configuration' <<<"$args")" "Release"
contains "an ad hoc signature (CODE_SIGN_IDENTITY=-)" "$args" "CODE_SIGN_IDENTITY=-"
contains "with signing still on" "$args" "CODE_SIGNING_ALLOWED=YES"
contains "and project.yml's --timestamp dropped" "$(grep -x 'OTHER_CODE_SIGN_FLAGS=' <<<"$args")" "OTHER_CODE_SIGN_FLAGS="
contains "and its products in the result folder's build/" "$args" "CONFIGURATION_BUILD_DIR=$TMP/l6/result/build"
if grep -q "Developer ID" <<<"$args"; then no "no Developer ID identity may reach xcodebuild" "$args"; else ok "no Developer ID identity reaches xcodebuild"; fi
expect "a failed build leaves no zip behind" "$(ls "$TMP/l6/result" | grep -c zip || true)" 0

# --dmg: where it works, where it is refused, and that the plain tester run did not change.
cp -R "$R" "$TMP/dmgrel"
(cd "$TMP/dmgrel" && git switch -q -c feature/dmg)
mkdir -p "$TMP/l9"; rc=0
(cd "$TMP/dmgrel" && STUB_LOG="$TMP/l9" PATH="$NOGH" NM_TESTER_OUT="$TMP/l9/result" bash -x scripts/release.sh 7.7.7 --tester --dmg) > "$TMP/l9/out" 2>&1 || rc=$?
if [ "$rc" != 0 ] && grep -qxF '+ WANT_DMG=1' "$TMP/l9/out" && [ -s "$TMP/l9/xcodebuild.log" ] && ! ls "$TMP/l9/result" 2> /dev/null | grep -q dmg; then ok "--tester --dmg gets as far as xcodebuild, without gh (the stub build fails, so no image)"; else no "--tester --dmg should reach xcodebuild with WANT_DMG=1 (exit $rc)" "$(cat "$TMP/l9/out")"; fi
rc=$(rel "$TMP/dmgrel" "$TMP/l10" 7.7.7 --dmg --tester)
if [ -s "$TMP/l10/xcodebuild.log" ]; then ok "the flags can come in either order"; else no "--dmg --tester should reach xcodebuild (exit $rc)" "$(cat "$TMP/l10/out")"; fi
rc=$(rel "$TMP/dmgrel" "$TMP/l11" 7.7.7 --dmg)
if [ "$rc" != 0 ] && grep -q "D2" "$TMP/l11/out" && untouched "$TMP/l11"; then ok "the signed release refuses --dmg until D2, before xcodegen"; else no "7.7.7 --dmg without --tester should be refused (exit $rc)" "$(cat "$TMP/l11/out")"; fi
rc=$(rel "$TMP/dmgrel" "$TMP/l12" 7.7.7 --finish --dmg)
if [ "$rc" != 0 ] && grep -q "D2" "$TMP/l12/out" && untouched "$TMP/l12"; then ok "--finish --dmg is refused too"; else no "--finish --dmg should be refused (exit $rc)" "$(cat "$TMP/l12/out")"; fi
rc=$(rel "$TMP/dmgrel" "$TMP/l13" 7.7.7 --tester --finish)
if [ "$rc" != 0 ] && grep -q "only one of" "$TMP/l13/out" && untouched "$TMP/l13"; then ok "--tester --finish is refused"; else no "--tester --finish should be refused (exit $rc)" "$(cat "$TMP/l13/out")"; fi
rc=$(rel "$TMP/dmgrel" "$TMP/l14" 7.7.7 --tester --dmg --bogus)
if [ "$rc" != 0 ] && grep -q "unknown option" "$TMP/l14/out" && untouched "$TMP/l14"; then ok "an unknown option after --dmg is still refused"; else no "--bogus should be refused (exit $rc)" "$(cat "$TMP/l14/out")"; fi

# What the tester block may never do, and what the signed release still does (the signed block is read, not run).
block="$(sed -n '/^# ── Tester build/,/^# ── End of the tester build/p' scripts/release.sh | grep -vE '^[[:space:]]*#')"
[ -n "$block" ] || no "release.sh has no tester block between its two marker comments"
if grep -nE 'notarytool|stapler|git tag|git push|gh |ls-remote|find-identity' <<<"$block" > "$TMP/forbidden.txt"; then no "the tester block must not notarize, tag, push or publish" "$(cat "$TMP/forbidden.txt")"; else ok "the tester block never notarizes, tags, pushes or publishes"; fi
if printf '%s\n' "$block" | grep -A1 -x '  exit 0' | sed -n 2p | grep -qx 'fi'; then ok "the tester block ends in exit 0 and leaves, so it cannot fall through into the signed steps"; else no "the tester block must end in exit 0 followed by fi, or it can fall through into the signed steps"; fi
dmgblock="$(sed -n '/^[[:space:]]*if \[ "\$WANT_DMG" = 1 \]; then/,/^[[:space:]]*fi$/p' <<<"$block")"
if [ -n "$dmgblock" ] && grep -qF 'bash scripts/make-dmg.sh "$APP" "$VERSION" "$OUT"' <<<"$dmgblock"; then ok "the tester block calls make-dmg.sh only when --dmg was given"; else no "the tester block should call make-dmg.sh inside its if WANT_DMG block" "$dmgblock"; fi
signed_head="$(sed -n '1,/^# ── Tester build/p' scripts/release.sh)"
if grep -qF 'D2' <<<"$signed_head" && grep -qE 'WANT_DMG.*--tester|--tester.*WANT_DMG' <<<"$signed_head"; then ok "the signed release refuses --dmg before the tester block (it names D2)"; else no "release.sh must refuse --dmg outside --tester, naming D2, before the tester block"; fi
for w in 'xcrun notarytool submit' 'xcrun stapler staple' 'git tag "$TAG" "$COMMIT"' 'git push origin "$TAG"' 'gh release create' 'Developer ID Application'; do
    if grep -qF -- "$w" scripts/release.sh; then ok "the signed release still has: $w"; else no "the signed release lost: $w"; fi
done
# The same check-versions.sh line is in the tester block, so the pin reads only what comes after the tester block's end marker.
signed="$(sed -n '/^# ── End of the tester build/,$p' scripts/release.sh)"
if grep -qF 'bash "$REPO_ROOT/scripts/check-versions.sh" "$VERSION" || die "the version fields do not all say $VERSION: run scripts/set-version.sh $VERSION and commit"' <<<"$signed"; then ok "the signed release runs check-versions.sh after its Info.plist check"; else no "the signed release does not run check-versions.sh"; fi

# ── 5b. make-dmg.sh: a real disk image from a tiny fake app ───────────────────────────────────────────────────────────
# Real hdiutil, a fake NotchMeow.app (a three-line shell script in a bundle, signed ad hoc, never run), everything under $TMP. Each image is built
# once (the first create is slow) and shared between the assertions. Nothing is mounted under /Volumes: the script and inspect() use -mountroot.
DMGT="$TMP/dmg"
mkdir -p "$DMGT/tmp" "$DMGT/mnt"
mkfake() {   # mkfake <dir> <version> <signed|unsigned>: a NotchMeow.app in <dir>
    local a="$1/NotchMeow.app/Contents"
    mkdir -p "$a/MacOS"
    printf '#!/bin/sh\nexit 0\n' > "$a/MacOS/NotchMeow"
    chmod +x "$a/MacOS/NotchMeow"
    cat > "$a/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NotchMeow</string>
<key>CFBundleIdentifier</key><string>invalid.test.notchmeow</string>
<key>CFBundleName</key><string>NotchMeow</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$2</string>
</dict></plist>
PLIST
    if [ "$3" = signed ]; then codesign --force --sign - "$1/NotchMeow.app" > /dev/null 2>&1; fi
}
mkdmg() {   # mkdmg <output file> <make-dmg.sh arguments...>: runs it with a TMPDIR of its own; prints the exit code
    local out="$1" rc=0
    shift
    TMPDIR="$DMGT/tmp" bash "$REPO/scripts/make-dmg.sh" "$@" > "$out" 2>&1 || rc=$?
    echo "$rc"
}
inspect() {   # inspect <dmg>: attaches it read-only under $DMGT/mnt and prints "<volume>|<visible entries>|<link target>", then detaches (a failed detach adds DETACH FAILED)
    local m="$DMGT/mnt" v out
    hdiutil attach -nobrowse -readonly -noverify -noautoopen -mountroot "$m" "$1" > /dev/null 2>&1 || { echo "attach failed"; return; }
    v=$(ls "$m")
    out="$v|$(ls "$m/$v" | tr '\n' ' ')|$(readlink "$m/$v/Applications")"
    hdiutil detach -quiet "$m/$v" > /dev/null 2>&1 || { sleep 2; hdiutil detach -quiet -force "$m/$v" > /dev/null 2>&1; }
    [ "$(still_mounted "$m/$v")" = 0 ] || out="$out DETACH FAILED"
    echo "$out"
}
still_mounted() { mount | grep -cF "${1:-$DMGT/tmp}" || true; }   # still_mounted [dir]: how many mounts are under dir (default: the script's temp folder)

mkdir -p "$DMGT/good" "$DMGT/out1"
mkfake "$DMGT/good" 7.7.7 signed
GOOD="$DMGT/out1/NotchMeow-7.7.7-mac.dmg"
expect "make-dmg.sh builds an image from a signed app (exit 0)" "$(mkdmg "$DMGT/g.out" "$DMGT/good/NotchMeow.app" 7.7.7 "$DMGT/out1")" 0
expect "and the image and its checksum are the only files in the folder" "$(ls "$DMGT/out1" | tr '\n' ' ')" "NotchMeow-7.7.7-mac.dmg NotchMeow-7.7.7-mac.dmg.sha256 "
expect "the checksum file checks out (shasum -c, run in the folder)" "$(cd "$DMGT/out1" && shasum -a 256 -c NotchMeow-7.7.7-mac.dmg.sha256 > /dev/null 2>&1; echo $?)" 0
expect "the volume is named 'NotchMeow 7.7.7', holds the app and a link to /Applications, and nothing else" "$(inspect "$GOOD")" "NotchMeow 7.7.7|Applications NotchMeow.app |/Applications"
expect "and nothing is left attached under the inspect mount folder" "$(still_mounted "$DMGT/mnt")" 0
rc=0; hdiutil verify "$GOOD" > "$DMGT/verify.out" 2>&1 || rc=$?
expect "hdiutil verify accepts the image" "$rc" 0
[ "$rc" = 0 ] || sed 's/^/    /' "$DMGT/verify.out"
expect "the format is UDZO" "$(hdiutil imageinfo -format "$GOOD" 2> /dev/null | tr -d ' \n')" "UDZO"
expect "the image is signed ad hoc and the signature holds" "$(codesign --verify "$GOOD" > /dev/null 2>&1; echo $?)" 0
contains "the image is ad hoc, not signed by a Developer ID" "$(codesign -dv "$GOOD" 2>&1)" "Signature=adhoc"
expect "nothing stays mounted and the script's temp folder is gone" "$(still_mounted):$(ls "$DMGT/tmp" | wc -l | tr -d ' ')" "0:0"
expect "no image of this test is still attached" "$(hdiutil info | grep -cF "$DMGT/" || true)" 0

# ULFO is the one switch; any other format is refused before anything is staged.
mkdir -p "$DMGT/out2"
expect "NM_DMG_FORMAT=ULFO builds an image" "$(NM_DMG_FORMAT=ULFO mkdmg "$DMGT/u.out" "$DMGT/good/NotchMeow.app" 7.7.7 "$DMGT/out2")" 0
expect "and it is ULFO" "$(hdiutil imageinfo -format "$DMGT/out2/NotchMeow-7.7.7-mac.dmg" 2> /dev/null | tr -d ' \n')" "ULFO"
for f in UDRW ZIP ""; do
    mkdir -p "$DMGT/outf"
    rc=$(NM_DMG_FORMAT="$f" mkdmg "$DMGT/f.out" "$DMGT/good/NotchMeow.app" 7.7.7 "$DMGT/outf")
    if [ "$rc" = 1 ] && [ -z "$(ls "$DMGT/outf")" ]; then ok "format '$f' is refused with nothing written"; else no "format '$f' should be refused (exit $rc)" "$(cat "$DMGT/f.out")"; fi
done

# A version that looks right and is not, and an app that is not the app.
for v in "0.9" "v0.9.0" "0.9.0-beta" "01.2.3"; do
    rc=$(mkdmg "$DMGT/v.out" "$DMGT/good/NotchMeow.app" "$v" "$DMGT/outf")
    if [ "$rc" = 1 ] && [ -z "$(ls "$DMGT/outf")" ]; then ok "version '$v' is refused with nothing written"; else no "version '$v' should be refused (exit $rc)" "$(cat "$DMGT/v.out")"; fi
done
expect "the app's own version must match: 7.7.8 against an app that says 7.7.7" "$(mkdmg "$DMGT/m.out" "$DMGT/good/NotchMeow.app" 7.7.8 "$DMGT/outf"):$(ls "$DMGT/outf" | wc -l | tr -d ' '):$(still_mounted)" "1:0:0"
contains "and the message says so" "$(cat "$DMGT/m.out")" "says 7.7.7, not 7.7.8"
expect "a missing app is refused" "$(mkdmg "$DMGT/n.out" "$DMGT/nothing/NotchMeow.app" 7.7.7 "$DMGT/outf")" 1
mkdir -p "$DMGT/other"
mkfake "$DMGT/other" 7.7.7 signed
mv "$DMGT/other/NotchMeow.app" "$DMGT/other/Other.app"
expect "an app that is not named NotchMeow.app is refused" "$(mkdmg "$DMGT/o.out" "$DMGT/other/Other.app" 7.7.7 "$DMGT/outf")" 1
expect "a missing output folder is refused" "$(mkdmg "$DMGT/p.out" "$DMGT/good/NotchMeow.app" 7.7.7 "$DMGT/nope")" 1
expect "no arguments is a usage error (2)" "$(mkdmg "$DMGT/q.out")" 2

# Running it twice into one folder: the second run refuses and the first image is untouched.
before=$(shasum -a 256 "$GOOD")
expect "an existing dmg is refused" "$(mkdmg "$DMGT/r.out" "$DMGT/good/NotchMeow.app" 7.7.7 "$DMGT/out1")" 1
expect "and left alone, byte for byte" "$(shasum -a 256 "$GOOD")" "$before"

# A check that fails after the image is mounted: an unsigned app. Nothing may stay mounted, and no half-made file may stay.
mkdir -p "$DMGT/bare" "$DMGT/out3"
mkfake "$DMGT/bare" 7.7.7 unsigned
rc=$(mkdmg "$DMGT/s.out" "$DMGT/bare/NotchMeow.app" 7.7.7 "$DMGT/out3")
if [ "$rc" = 1 ] && [ -z "$(ls "$DMGT/out3")" ] && [ "$(still_mounted)" = 0 ] && [ -z "$(ls "$DMGT/tmp")" ]; then ok "a failing check leaves no mount, no temp folder and no dmg"; else no "an unsigned app should fail cleanly (exit $rc, mounted: $(still_mounted))" "$(cat "$DMGT/s.out")" "$(ls "$DMGT/out3" "$DMGT/tmp")"; fi
contains "and the message names the signature" "$(cat "$DMGT/s.out")" "not signed"

# D2's hook: a Developer ID is refused for now, naming D2, with nothing written.
mkdir -p "$DMGT/out4"
rc=$(NM_DMG_IDENTITY="Developer ID Application: Someone (ABCDE12345)" mkdmg "$DMGT/d.out" "$DMGT/good/NotchMeow.app" 7.7.7 "$DMGT/out4")
if [ "$rc" = 1 ] && [ -z "$(ls "$DMGT/out4")" ] && grep -q "D2" "$DMGT/d.out"; then ok "a Developer ID identity is refused until D2, and the message names D2"; else no "NM_DMG_IDENTITY other than - should be refused (exit $rc)" "$(cat "$DMGT/d.out")"; fi

# What the script may never do or touch (read, not run).
if grep -nE 'notarytool|stapler|git |gh |/Volumes|/Applications/|sudo|curl|create-dmg|appdmg|osascript' scripts/make-dmg.sh | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vF 'ln -s /Applications' | grep -vF '"/Applications"' > "$DMGT/forbidden.txt"; then no "make-dmg.sh must not notarize, publish, mount under /Volumes, use sudo, the network or a third-party tool" "$(cat "$DMGT/forbidden.txt")"; else ok "make-dmg.sh never notarizes, publishes, mounts under /Volumes or uses a third-party tool"; fi
for w in '-nobrowse' '-readonly' '-mountroot' '-noautoopen' 'trap cleanup EXIT' 'dmg_seal()'; do
    if grep -qF -- "$w" scripts/make-dmg.sh; then ok "make-dmg.sh has: $w"; else no "make-dmg.sh lost: $w"; fi
done
# The verify retry, read from the script: two verify lines, the failed image's device detached between them, one sleep 1 between them. (Static: no EAGAIN is forced.)
verify_n=$(grep -c 'hdiutil verify' scripts/make-dmg.sh || true)
v1=$(grep -n 'hdiutil verify' scripts/make-dmg.sh | sed -n 1p | cut -d: -f1)
v2=$(grep -n 'hdiutil verify' scripts/make-dmg.sh | sed -n 2p | cut -d: -f1)
det=$(awk -v a="$v1" -v b="$v2" 'NR > a && NR < b && /^ *detach_image_devices$/ { print NR; exit }' scripts/make-dmg.sh)
slp=$(awk -v a="$v1" -v b="$v2" 'NR > a && NR < b && /^ *sleep 1$/ { n++ } END { print n + 0 }' scripts/make-dmg.sh)
expect "make-dmg.sh has exactly two hdiutil verify lines (the retry)" "$verify_n" 2
expect "make-dmg.sh retries hdiutil verify once, after detaching the failed image" "$( [ -n "$det" ] && [ "$det" -gt "$v1" ] && [ "$det" -lt "$v2" ] && echo yes || echo no)" yes
expect "make-dmg.sh waits one second between the two verify attempts" "$slp" 1
expect "no image of section 5b is left attached" "$(hdiutil info | grep -cF "$TMP/" || true)" 0

# ── 6. The QA brief's sample payloads ───────────────────────────────────────────────────────────────────────────────
# The payloads docs/QA-MAC.md has the QA session pipe into the relay must be valid JSON (an invalid one is dropped without a word), each marked as the
# QA session's own (a session_id that starts with qa- and a cwd under /tmp/notchmeow-qa), and every file the brief reads must be one it writes.
python3 - "$REPO/docs/QA-MAC.md" > "$TMP/qa-payloads.txt" <<'PY'
import json, re, sys
doc = open(sys.argv[1], encoding='utf-8').read()
made = dict(re.findall(r'cat > "\$QA/payloads/([a-z-]+)\.json" <<\'JSON\'\n(.*?)\nJSON\n', doc, re.S))
used = set(re.findall(r'"\$QA/payloads/([a-z-]+)\.json"', doc))
invalid, unmarked = [], []
for name, body in made.items():
    try:
        p = json.loads(body)
    except ValueError:
        invalid.append(name)
        continue
    if not (str(p.get('session_id', '')).startswith('qa-') and str(p.get('cwd', '')).startswith('/tmp/notchmeow-qa')):
        unmarked.append(name)
print('payloads', len(made))
print('invalid', ' '.join(sorted(invalid)) or '-')
print('unmarked', ' '.join(sorted(unmarked)) or '-')
print('missing', ' '.join(sorted(used - set(made))) or '-')
PY
expect "the QA brief writes 14 payloads" "$(sed -n 1p "$TMP/qa-payloads.txt")" "payloads 14"
expect "and every one is valid JSON" "$(sed -n 2p "$TMP/qa-payloads.txt")" "invalid -"
expect "and every one is marked as the QA session's own" "$(sed -n 3p "$TMP/qa-payloads.txt")" "unmarked -"
expect "and the brief reads no payload it does not write" "$(sed -n 4p "$TMP/qa-payloads.txt")" "missing -"

# The demo scenario the QA brief runs must still hold the three markers the brief depends on.
DEMO="$REPO/tests/fixtures/mac/subagent-scenarios.json"
for m in 'S1' '/tmp/notchmeow-demo' 'echo kittens'; do
    n=$(grep -cF -- "$m" "$DEMO" || true)
    if [ "$n" -ge 1 ]; then ok "the demo scenario has the marker: $m"; else no "the demo scenario lost the marker the QA brief relies on: $m"; fi
done

echo
if [ "$fail" = 0 ]; then echo "All $pass tests passed."; else echo "$fail of $((pass + fail)) test(s) failed."; exit 1; fi
