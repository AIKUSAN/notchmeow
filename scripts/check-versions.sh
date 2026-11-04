#!/usr/bin/env bash
# Prints every field that carries NotchMeow's version and fails when any two differ. The fields are the ones scripts/set-version.sh writes:
# the main app in project.yml and Info.plist, the Windows and Linux app in package.json, package-lock.json, tauri.conf.json, Cargo.toml and Cargo.lock.
# The App Store target keeps its own number, so it is printed and not compared.
#
#   bash scripts/check-versions.sh              every field must agree, and be three whole numbers (0.9.0)
#   bash scripts/check-versions.sh 0.9.0        and that number must be 0.9.0
#
# scripts/release.sh runs it, and so do the Windows and Linux workflows on tags and on manual runs. It does not run on every push: until
# set-version.sh has been run once, the inherited versions of the two apps differ. Plain bash, awk and grep: it runs on the Windows runner too.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/version-fields.sh"

[ $# -le 1 ] || { echo "usage: bash scripts/check-versions.sh [<version>]" >&2; exit 2; }
want="${1:-}"
if [ $# -eq 1 ] && ! vf_whole "$want"; then
    echo "error: '$want' is not a version: use three whole numbers, like 0.9.0" >&2
    echo "usage: bash scripts/check-versions.sh [<version>]" >&2
    exit 2
fi

failed=0
missing=0
rows=""
for f in $VF_FIELDS; do
    if v=$(vf_get "$f"); then
        rows="$rows$v $f"$'\n'
    else
        v="(not found exactly once)"
        missing=1
    fi
    printf '  %-36s %-54s %s\n' "$(vf_file "$f")" "$(vf_label "$f")" "$v"
done

# The build number: project.yml and the Info.plist xcodegen wrote from it must agree.
build_yml=$(vf_get yml_build || echo "?")
build_plist=$(vf_get plist_build || echo "?")
printf '  %-36s %-54s %s\n' "$(vf_file yml_build)" "$(vf_label yml_build)" "$build_yml"
printf '  %-36s %-54s %s\n' "$(vf_file plist_build)" "$(vf_label plist_build)" "$build_plist"
printf '  %-36s %-54s %s  (its own number, not compared)\n' "$(vf_file yml_store)" "$(vf_label yml_store)" "$(vf_get yml_store || echo "?")"

if [ "$build_yml" != "$build_plist" ] || ! [[ "$build_yml" =~ ^[0-9]+$ ]]; then
    echo "✗ the build number is $build_yml in project.yml and $build_plist in Info.plist: run xcodegen (scripts/set-version.sh does)" >&2
    failed=1
fi

# The distinct versions, in the order they were first seen, with how many fields carry each.
distinct=$(printf '%s' "$rows" | awk '!($1 in n) { order[++k] = $1 } { n[$1]++ } END { for (i = 1; i <= k; i++) printf "%s%s (%d field%s)", (i > 1 ? ", " : ""), order[i], n[order[i]], (n[order[i]] == 1 ? "" : "s") }')
count=$(printf '%s' "$rows" | awk '{ print $1 }' | sort -u | grep -c . || true)
if [ "$missing" = 1 ] && [ "$count" -le 1 ]; then
    echo "✗ a version field is missing or not in the shape set-version.sh writes (see above)" >&2
    failed=1
elif [ "$count" -gt 1 ]; then
    echo "✗ the versions disagree: $distinct" >&2
    failed=1
elif [ "$failed" = 0 ]; then
    agreed=$(printf '%s' "$rows" | awk 'NR == 1 { print $1 }')
    if ! vf_whole "$agreed"; then
        echo "✗ every field says '$agreed', which is not three whole numbers (like 0.9.0)" >&2
        failed=1
    elif [ -n "$want" ] && [ "$agreed" != "$want" ]; then
        echo "✗ every field says $agreed, not $want" >&2
        failed=1
    else
        echo "✓ every version field is $agreed"
    fi
fi
exit "$failed"
