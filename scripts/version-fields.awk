# The one place that knows which line of which file holds a version. set-version.sh writes through it and check-versions.sh reads through it,
# so the two cannot disagree about a line. POSIX awk only: it runs in macOS's awk, mawk (Ubuntu) and gawk (Git for Windows).
#
#   awk -v f=<field> -f scripts/version-fields.awk <file>              prints the field's value, once per matching line (a healthy file: one line)
#   awk -v f=<field> -v new=<value> -f scripts/version-fields.awk <file>   prints the file with that value in place of the old one
#
# The fields: yml, yml_build, yml_store (project.yml: the main app's version, its build number, and the App Store target's version); plist,
# plist_build (Info.plist); pkg (package.json); lock_top, lock_root (the two top-level versions of package-lock.json); tauri (tauri.conf.json);
# cargo ([workspace.package] in Cargo.toml); lock_app, lock_hook (the notchmeow and notchmeow-hook entries of Cargo.lock).

# The value on a line: the last "quoted" text, or the text of a <string> tag.
function val(s,   a, n) {
    if (s ~ /<string>/) { sub(/.*<string>/, "", s); sub(/<\/string>.*/, "", s); return s }
    n = split(s, a, "\"")
    return a[n - 1]
}

# The same line with another value in that place.
function put(s, v,   a, n, i, r) {
    if (s ~ /<string>/) { sub(/<string>[^<]*<\/string>/, "<string>" v "</string>", s); return s }
    n = split(s, a, "\"")
    a[n - 1] = v
    r = a[1]
    for (i = 2; i <= n; i++) r = r "\"" a[i]
    return r
}

{
    cr = ""
    if (sub(/\r$/, "")) cr = "\r"     # a checkout with Windows line endings reads the same, and is written back the same
    hit = 0
    if (f == "yml" || f == "yml_build" || f == "yml_store") {
        if ($0 ~ /^[^ #]/) top = $1
        if (top == "targets:" && $0 ~ /^  [A-Za-z]+:$/) tgt = $1
        want = (f == "yml_store") ? "NotchMeowAppStore:" : "NotchBuddy:"
        key = (f == "yml_build") ? "CFBundleVersion" : "CFBundleShortVersionString"
        hit = (top == "targets:" && tgt == want && index($0, "        " key ": \"") == 1)
    } else if (f == "plist" || f == "plist_build") {
        key = (f == "plist_build") ? "CFBundleVersion" : "CFBundleShortVersionString"
        hit = (prev == "<key>" key "</key>" && $0 ~ /<string>/)
        prev = $0
        sub(/^[ \t]+/, "", prev)
        sub(/[ \t]+$/, "", prev)
    } else if (f == "pkg" || f == "tauri" || f == "lock_top") {
        hit = ($0 ~ /^  "version": "/)
    } else if (f == "lock_root") {
        if ($0 ~ /^    "": [{]$/) inroot = 1
        else if ($0 ~ /^    [}],?$/) inroot = 0
        hit = (inroot && $0 ~ /^      "version": "/)
    } else if (f == "cargo") {
        if ($0 ~ /^\[/) sect = $0
        hit = (sect == "[workspace.package]" && $0 ~ /^version = "/)
    } else if (f == "lock_app" || f == "lock_hook") {
        want = (f == "lock_app") ? "notchmeow" : "notchmeow-hook"
        if ($0 ~ /^\[\[package\]\]/) nm = ""
        else if ($0 ~ /^name = "/) nm = val($0)
        hit = (nm == want && $0 ~ /^version = "/)
    } else {
        print "version-fields.awk: no field called '" f "'" > "/dev/stderr"
        exit 2
    }
    if (hit && new == "") print val($0)
    else if (hit) print put($0, new) cr
    else if (new != "") print $0 cr
}
