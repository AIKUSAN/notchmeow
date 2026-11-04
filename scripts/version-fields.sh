# Sourced by set-version.sh and check-versions.sh (not run on its own): where every version of NotchMeow lives.
# The lines themselves are found by version-fields.awk, which both scripts go through.
# Bash 3.2 (macOS) and Git for Windows' bash are enough: no arrays, no associative arrays.

VF_ROOT="${VF_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VF_AWK="$VF_ROOT/scripts/version-fields.awk"

# The fields that must all carry one version, in the order check-versions.sh prints them.
VF_FIELDS="yml plist pkg lock_top lock_root tauri cargo lock_app lock_hook"

# The file a field lives in, relative to the repository root.
vf_file() {
    case "$1" in
        yml|yml_build|yml_store) echo NotchBuddy/project.yml ;;
        plist|plist_build) echo NotchBuddy/Resources/Info.plist ;;
        pkg) echo windows/package.json ;;
        lock_top|lock_root) echo windows/package-lock.json ;;
        tauri) echo windows/src-tauri/tauri.conf.json ;;
        cargo) echo windows/Cargo.toml ;;
        lock_app|lock_hook) echo windows/Cargo.lock ;;
        *) return 1 ;;
    esac
}

# What the field is called in the file.
vf_label() {
    case "$1" in
        yml) echo "CFBundleShortVersionString (NotchBuddy target)" ;;
        yml_build) echo "CFBundleVersion (NotchBuddy target)" ;;
        yml_store) echo "CFBundleShortVersionString (NotchMeowAppStore target)" ;;
        plist) echo "CFBundleShortVersionString" ;;
        plist_build) echo "CFBundleVersion" ;;
        pkg|tauri) echo "version" ;;
        lock_top) echo "version (top of the file)" ;;
        lock_root) echo 'version (packages[""])' ;;
        cargo) echo "version ([workspace.package])" ;;
        lock_app) echo 'version (package "notchmeow")' ;;
        lock_hook) echo 'version (package "notchmeow-hook")' ;;
        *) return 1 ;;
    esac
}

# vf_get <field>: prints the field's value. Fails, printing nothing, unless the field's line is there exactly once.
vf_get() {
    local out n
    out=$(awk -v f="$1" -f "$VF_AWK" "$VF_ROOT/$(vf_file "$1")") || return 1
    n=$(printf '%s\n' "$out" | grep -c .)
    [ "$n" = 1 ] || return 1
    printf '%s\n' "$out"
}

# vf_put <field> <value>: changes that one line of the file in place. The file's mode and every other line stay as they are.
vf_put() {
    local file tmp
    file="$VF_ROOT/$(vf_file "$1")"
    tmp=$(mktemp "${TMPDIR:-/tmp}/nm-version.XXXXXX") || return 1
    if awk -v f="$1" -v new="$2" -f "$VF_AWK" "$file" > "$tmp"; then
        cat "$tmp" > "$file"
        rm -f "$tmp"
    else
        rm -f "$tmp"
        return 1
    fi
}

# vf_whole <text>: succeeds for three whole numbers with dots between them (0.9.0), without leading zeros: what macOS and Cargo both accept.
vf_whole() {
    local re='^(0|[1-9][0-9]{0,8})(\.(0|[1-9][0-9]{0,8})){2}$'
    [[ "$1" =~ $re ]]
}
