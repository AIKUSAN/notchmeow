import Foundation

// How risky is one permission request, in plain words. Port of `explain` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/explain-cases.json pins it and
// docs/SIDEKICK-CONTRACT.md has the decisions. It LABELS only: it never allows, denies or blocks anything (only the user's click does), it reads no file system and starts
// nothing, and its lines hold a basename and a fixed sentence, never a command, a path or an argument. It never throws: what it cannot read is `medium` / `unsure`.
// Pure Foundation. The regular expressions use `Rx` (ICU with JavaScript's `$` and `\b`), and a pattern that ends a string ends with `\z`.

struct SKExplanation: Equatable, Sendable {
    var risk: String
    var reasonId: String
    var line: String
    var target: String
}

enum SidekickExplain {
    // MARK: The reasons, in the order that breaks a tie (the earlier one wins)

    struct Reason: Sendable { var id: String; var risk: String; var line: String; var order: Int }
    static let reasons: [Reason] = {
        let rows: [(String, String, String)] = [
            ("git_history", "high", "Deletes this project's git history."),
            ("rm_recursive", "high", "Deletes {name} and everything inside it."),
            ("sudo", "high", "Runs a command with admin rights."),
            ("pipe_to_shell", "high", "Downloads a script and runs it at once."),
            ("chmod_recursive", "high", "Changes permissions on {name} and everything inside it."),
            ("git_force_push", "high", "Overwrites the remote branch history."),
            ("git_reset_hard", "high", "Throws away local changes."),
            ("git_clean", "high", "Deletes files git doesn't track."),
            ("disk_write", "high", "Writes straight to a disk."),
            ("sql_drop", "high", "Deletes a database table or database."),
            ("sql_delete_all", "high", "Changes every row in a table."),
            ("sensitive_file", "high", "Changes {name}, which can hold secrets or settings."),
            ("write_outside", "high", "Changes {name}, outside this project."),
            ("git_push", "medium", "Sends commits to a remote."),
            ("install", "medium", "Installs software."),
            ("network_fetch", "medium", "Talks to another computer."),
            ("container", "medium", "Controls containers."),
            ("lockfile_ci", "medium", "Changes {name}, which affects every build."),
            ("reads_secrets", "medium", "Reads {name}, which can hold secrets."),
            ("mcp_tool", "medium", "Uses a tool from an add-on."),
            ("unknown_tool", "medium", "Uses a tool NotchMeow doesn\u{2019}t know."),
            ("unsure", "medium", "Runs a command NotchMeow can't fully read."),
            ("outside_project", "medium", "Touches {name}, outside this project."),
            ("rm_in_project", "medium", "Deletes {name} in this project."),
            ("read_only", "low", "Only reads files."),
            ("test_build", "low", "Runs the project's own test or build script."),
            ("edit_in_project", "low", "Edits {name} in this project."),
            ("web", "low", "Reads a web page."),
            ("subagent", "low", "Starts a helper agent."),
            ("local_command", "low", "Does a simple local step."),
        ]
        return rows.enumerated().map { Reason(id: $1.0, risk: $1.1, line: $1.2, order: $0) }
    }()
    private static let reasonById: [String: Reason] = Dictionary(uniqueKeysWithValues: reasons.map { ($0.id, $0) })
    private static let riskRank = ["low": 0, "medium": 1, "high": 2]

    private struct Cand { var reason: String; var target: String = "" }
    private struct Word { var text: String; var quoted: Bool }
    private struct Redir { var out: Bool; var dup: Bool; var rw: Bool; var target: String }
    private struct Part { var args: [Word]; var redirs: [Redir]; var op: String }

    // MARK: Paths

    /// `p` against `cwd`: `~` and `$HOME` become `home`, `.` and `..` fold away, `\` is `/`. A relative path with no `cwd` stays relative.
    static func resolvePath(_ p: String, _ cwd: String, _ home: String) -> String {
        var s = p.replacingOccurrences(of: "\\", with: "/")
        if !home.isEmpty {
            var h = home.replacingOccurrences(of: "\\", with: "/")
            while h.hasSuffix("/") { h.removeLast() }
            for pre in ["~", "$HOME", "${HOME}"] where s.hasPrefix(pre) {
                let rest = s.dropFirst(pre.count)
                if rest.isEmpty || rest.hasPrefix("/") { s = h + rest; break }
            }
        }
        if !Rx.test("^(/|[A-Za-z]:/|~)", s) {
            var base = "."
            if !cwd.isEmpty { base = cwd.replacingOccurrences(of: "\\", with: "/"); while base.hasSuffix("/") { base.removeLast() } }
            s = base + "/" + s
        }
        var root = "", rest = Substring(s)
        if Rx.test("^[A-Za-z]:/", s) { root = String(s.prefix(3)); rest = s.dropFirst(3) }
        else if s.hasPrefix("/") { root = "/"; rest = s.dropFirst(1) }
        else if s.hasPrefix("~") { root = s.hasPrefix("~/") ? "~/" : "~"; rest = s.dropFirst(root.count) }
        var out: [String] = []
        for seg in rest.split(separator: "/", omittingEmptySubsequences: false) {
            if seg.isEmpty || seg == "." { continue }
            if seg == ".." { if let l = out.last, l != ".." { out.removeLast() } else if root.isEmpty { out.append("..") } } else { out.append(String(seg)) }
        }
        let r = root + out.joined(separator: "/")
        if r.utf16.count > 1, r.hasSuffix("/"), !Rx.test("^[A-Za-z]:/\\z", r) { return String(r.dropLast()) }
        return r.isEmpty ? "." : r
    }

    private static func isAbs(_ r: String) -> Bool { Rx.test("^(/|[A-Za-z]:/|~)", r) }
    private static func lc(_ r: String) -> String { Rx.test("^[A-Za-z]:/", r) ? r.lowercased() : r }
    private static func under(_ r: String, _ root: String) -> Bool {
        let a = lc(r), b = lc(root)
        return a == b || a.hasPrefix(b.hasSuffix("/") ? b : b + "/")
    }
    /// "inside", "outside" or "unknown" (an absolute path when the project folder is not known).
    private static func whereIs(_ p: String, _ cwd: String, _ home: String) -> String {
        let r = resolvePath(p, cwd, home)
        if cwd.isEmpty { return isAbs(r) ? "unknown" : (r.hasPrefix("..") ? "outside" : "inside") }
        return under(r, resolvePath(cwd, "", home)) ? "inside" : "outside"
    }
    private static func isHomeFolder(_ r: String, _ home: String) -> Bool {
        (!home.isEmpty && lc(r) == lc(resolvePath(home, "", ""))) || Rx.test("^(/(Users|home)/[^/]+|[A-Za-z]:/Users/[^/]+)\\z", r, .caseInsensitive) || r == "~"
    }

    // MARK: What a file path means

    private static let shellRC: Set<String> = [".bashrc", ".bash_profile", ".bash_login", ".bash_logout", ".profile", ".zshrc", ".zshenv", ".zprofile", ".zlogin", ".zlogout", "config.fish"]
    private static let lockfiles: Set<String> = ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "Cargo.lock", "Gemfile.lock", "poetry.lock", "Pipfile.lock", "composer.lock", "go.sum", "Podfile.lock", "Package.resolved", ".gitlab-ci.yml", "Jenkinsfile", "azure-pipelines.yml"]
    private static let secretNames: Set<String> = [".npmrc", ".netrc", ".pypirc", ".mcp.json", ".pgpass", ".yarnrc.yml", ".gitmodules", "kubeconfig"]
    private static let sourceExt = "\\.(ts|tsx|js|jsx|mjs|cjs|py|rs|go|swift|kt|java|rb|md|txt|css|scss|less|html)\\z"

    private static func sensitivePath(_ r: String) -> Bool {
        let b = baseName(r).lowercased()
        let stem = b.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let keyword = Rx.test("credential|secret|token|passw", b) && !(Rx.test(sourceExt, b) && stem != "credentials" && stem != "secrets")
        if b.hasPrefix(".env") || b.hasSuffix(".env") || secretNames.contains(b) || b.hasPrefix("terraform.tfstate") || keyword
            || Rx.test("\\.(pem|key|p12|pfx|keystore|jks|p8|tfvars)\\z", b) || Rx.test("^id_(rsa|dsa|ecdsa|ed25519)(_sk)?([._-].*)?\\z", b) || shellRC.contains(b) { return true }
        if Rx.test("(^|/)(\\.git/(?!objects/|refs/|logs/)|\\.husky(/|\\z)|\\.githooks(/|\\z)|\\.claude/(hooks|commands)(/|\\z)|\\.(vscode|cursor)/(tasks|mcp|launch|settings)\\.json\\z)", r, .caseInsensitive)
            || Rx.test("(^|/)\\.claude/settings[^/]*\\.json\\z", r, .caseInsensitive) { return true }
        return Rx.test("(^|/)\\.(ssh|aws|gnupg|kube|docker)(/|\\z)", r, .caseInsensitive) || Rx.test("(^|/)\\.config/gh(/|\\z)", r, .caseInsensitive) || Rx.test("(^|/)secrets(/|\\z)", r, .caseInsensitive)
    }

    private static func baseName(_ p: String) -> String { SK.baseName(p) }
    private static func lockOrCi(_ r: String) -> Bool { lockfiles.contains(baseName(r)) || Rx.test("(^|/)\\.github/workflows/", r) || Rx.test("(^|/)\\.circleci/", r) }

    /// The candidate for writing to one path.
    private static func writeCandidate(_ p: String, _ cwd: String, _ home: String) -> Cand {
        let r = resolvePath(p, cwd, home), w = whereIs(p, cwd, home)
        if sensitivePath(r) { return Cand(reason: "sensitive_file", target: baseName(r)) }
        if w == "outside" { return Cand(reason: "write_outside", target: baseName(r)) }
        if w == "unknown" { return Cand(reason: "unsure") }
        if lockOrCi(r) { return Cand(reason: "lockfile_ci", target: baseName(r)) }
        return Cand(reason: "edit_in_project", target: baseName(r))
    }

    // MARK: Shell commands

    /// Splits a command at `&&`, `||`, `;`, `|`, `&`, newlines, `(` and `)`, respecting quotes. `opaque` says some of the text can't be followed as words: `$(…)`, backticks, `<(…)`,
    /// a subshell, a here-document or an open quote. `ps` (PowerShell) reads `\` as a path separator, not an escape.
    private static func splitShell(_ cmd: String, _ ps: Bool) -> (parts: [Part], opaque: Bool) {
        let s = Array(cmd.unicodeScalars)
        struct Tok { var text: String; var quoted: Bool; var redir = false; var out = false; var dup = false; var rw = false }
        var parts: [Part] = [], toks: [Tok] = [], cur = "", has = false, quoted = false, q: Unicode.Scalar? = nil, opaque = false
        func push() { if has { toks.append(Tok(text: cur, quoted: quoted)) }; cur = ""; has = false; quoted = false }
        func end(_ op: String) {
            push()
            var args: [Word] = [], redirs: [Redir] = []
            var k = 0
            while k < toks.count {
                if toks[k].redir {
                    if k + 1 < toks.count { redirs.append(Redir(out: toks[k].out, dup: toks[k].dup, rw: toks[k].rw, target: toks[k + 1].text)) }
                    k += 1
                } else { args.append(Word(text: toks[k].text, quoted: toks[k].quoted)) }
                k += 1
            }
            parts.append(Part(args: args, redirs: redirs, op: op))
            toks = []
        }
        func at(_ i: Int) -> Unicode.Scalar? { i >= 0 && i < s.count ? s[i] : nil }
        func isDigits(_ t: String) -> Bool { t.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 } }
        var i = 0
        while i < s.count {
            let c = s[i]
            if q == "'" { if c == "'" { q = nil } else { cur.unicodeScalars.append(c) }; i += 1; continue }
            if q == "\"" {
                if c == "\"" { q = nil }
                else if c == "\\", !ps, i + 1 < s.count, "$`\"\\\n".unicodeScalars.contains(s[i + 1]) { i += 1; cur.unicodeScalars.append(s[i]) }
                else { if c == "`" || (c == "$" && at(i + 1) == "(") { opaque = true }; cur.unicodeScalars.append(c) }
                i += 1; continue
            }
            if c == "'" || c == "\"" { q = c; has = true; quoted = true; i += 1; continue }
            if c == "\\" {
                if ps { cur.unicodeScalars.append(c); has = true } else if i + 1 < s.count { i += 1; cur.unicodeScalars.append(s[i]); has = true }
                i += 1; continue
            }
            if c == "`" || c == "(" || c == ")" { opaque = true; end(String(c)); i += 1; continue }
            if (c == "$" || c == "<" || c == ">"), at(i + 1) == "(" {
                opaque = true
                if c != "$" { push(); toks.append(Tok(text: String(c) + "(", quoted: false)) }
                i += 1; continue
            }
            if c == "<", at(i + 1) == "<" { opaque = true }
            if c == " " || c == "\t" || c == "\r" { push(); i += 1; continue }
            if c == "\n" { end("\n"); i += 1; continue }
            if c == ";" { end(";"); i += 1; continue }
            if c == "&", at(i + 1) == "&" { end("&&"); i += 2; continue }
            if c == "|", at(i + 1) == "|" { end("||"); i += 2; continue }
            if c == "|" { if at(i + 1) == "&" { i += 1 }; end("|"); i += 1; continue }
            if c == "&", at(i + 1) == ">" { i += 1; continue }
            if c == "&" { end("&"); i += 1; continue }
            if c == ">" || c == "<" {
                if !isDigits(cur) || quoted { push() } else { cur = ""; has = false }
                var op = String(c)
                while at(i + 1) == c { i += 1; op.unicodeScalars.append(c) }
                if c == ">", at(i + 1) == "|" { i += 1 }
                var dupText: String? = nil
                if c == ">", at(i + 1) == "&" {
                    var j = i + 2, t = ""
                    if let d = at(j), d == "-" { t = "-" } else { while let d = at(j), d.value >= 48 && d.value <= 57 { t.unicodeScalars.append(d); j += 1 } }
                    if !t.isEmpty { dupText = t }
                    i += 1
                }
                var rw = false
                if c == "<", at(i + 1) == ">" { rw = true; i += 1 }
                toks.append(Tok(text: op, quoted: false, redir: true, out: c == ">" || rw, dup: dupText != nil, rw: rw))
                if let t = dupText { toks.append(Tok(text: "&" + t, quoted: false)); i += t.unicodeScalars.count }
                i += 1; continue
            }
            cur.unicodeScalars.append(c); has = true; i += 1
        }
        if q != nil { opaque = true }
        end("")
        return (parts.filter { !$0.args.isEmpty || !$0.redirs.isEmpty }, opaque)
    }

    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "ksh", "csh", "tcsh", "ash"]
    private static let writeCmds: Set<String> = ["cp", "mv", "ln", "touch", "mkdir", "install", "tee"]
    private static let writeFlags: Set<String> = ["sensitive_file", "write_outside", "unsure", "lockfile_ci"]
    private static let outFlag: [String: (String, String)] = ["sort": ("o", "--output"), "curl": ("o", "--output"), "wget": ("O", "--output-document")]
    private static let readers: Set<String> = ["cat", "tac", "less", "more", "head", "tail", "grep", "egrep", "fgrep", "rg", "ag", "xxd", "od", "hexdump", "strings", "sort", "uniq", "cut", "nl", "wc", "jq", "base64", "sed", "awk"]
    private static let progFirst: Set<String> = ["grep", "egrep", "fgrep", "rg", "ag", "sed", "awk", "jq"]
    private static let gitReads: Set<String> = ["diff", "show", "log", "blame", "grep", "cat-file"]
    private static let execKey = "^(core\\.(askpass|sshcommand|hookspath|pager|fsmonitor|editor|gitproxy|alternaterefscommand)|uploadpack\\.packobjectshook|submodule\\..+\\.update|tar\\..+\\.command|sequence\\.editor|filter\\..+|diff\\.(.+\\.)?(external|textconv|command)|merge\\..+\\.driver|gpg\\.(.+\\.)?program|credential\\..*helper|includeif?\\..+|alias\\..+|pager\\..+|(difftool|mergetool)\\..+\\.cmd|interactive\\.difffilter)\\z"
    private static let gitNet: Set<String> = ["fetch", "pull", "clone"]
    private static let installSubs: Set<String> = ["install", "i", "add", "ci", "update", "upgrade", "remove", "uninstall", "link", "sync", "require", "reinstall"]
    private static let netCmds: Set<String> = ["curl", "wget", "ssh", "scp", "sftp", "rsync", "nc", "ncat", "ftp", "telnet"]
    private static let containerCmds: Set<String> = ["docker", "podman", "kubectl", "helm", "docker-compose", "minikube"]
    private static let sqlClis: Set<String> = ["psql", "mysql", "mariadb", "sqlite3", "sqlcmd", "mongosh"]
    private static func plain(_ args: [Word]) -> [Word] { args.filter { !$0.text.hasPrefix("-") } }

    // The allow-list: only plain, fully-read forms are low.
    private static let plainCmds: [String: (rule: String, reason: String)] = {
        var m: [String: (String, String)] = ["pwd": ("none", "read_only"), "ls": ("any", "read_only"), "echo": ("text", "local_command"), "printf": ("text", "local_command")]
        for c in ["cat", "head", "tail", "wc", "file", "stat", "du", "df"] { m[c] = ("file", "read_only") }
        m["grep"] = ("none", "read_only")
        return m
    }()
    private static let plainGit: [String: String] = ["status": "file", "diff": "file", "log": "file", "show": "file", "rev-parse": "file", "branch": "none"]
    private static let plainTests = ["npm test", "npm run test", "npm run build", "npm run lint", "make test", "make build", "cargo test", "cargo build", "go test", "go build", "swift build", "swift test", "pytest"]
    private static let safeShort = "^-[AaBbdEFGHhIiJjkLlmNnqRrSsTvwXx0-9]+\\z"
    private static let safeLong = "^--(stat|shortstat|numstat|name-only|name-status|oneline|graph|decorate|cached|staged|short|porcelain|branch|no-color|color|all|almost-all|human-readable|show-current|list|abbrev-ref|show-toplevel|verify|summary|workspace|release|all-targets|lib|bins|tests|no-fail-fast|nocapture|quiet|verbose|locked|frozen|offline|silent|if-present)\\z"

    /// The basename of a secrets file that `w` names (`rev:path` counts its path), or nil.
    private static func secretName(_ w: String, _ cwd: String, _ home: String) -> String? {
        let tail = w.lastIndex(of: ":").map { String(w[w.index(after: $0)...]) } ?? w
        for x in [tail, w] {
            let r = resolvePath(x, cwd, home)
            if !x.isEmpty && sensitivePath(r) { return baseName(r) }
        }
        return nil
    }

    /// The values of a flag: `-o FILE`, `-oFILE`, `-ro FILE` (a clustered flag takes the next word), `--output FILE`, `--output=FILE`.
    private static func flagValues(_ rest: [Word], _ short: String, _ long: String) -> [String] {
        var v: [String] = []
        for (i, a) in rest.enumerated() {
            let t = a.text
            if !t.hasPrefix("-") { continue }
            if t.hasPrefix("--") {
                if t == long { if i + 1 < rest.count { v.append(rest[i + 1].text) } } else if t.hasPrefix(long + "=") { v.append(String(t.dropFirst(long.count + 1))) }
                continue
            }
            let u = Array(t.unicodeScalars), sh = short.unicodeScalars.first!
            guard u.count > 1, let k = u[1...].firstIndex(of: sh) else { continue }
            var x = ""
            if k + 1 < u.count { var sv = String.UnicodeScalarView(); sv.append(contentsOf: u[(k + 1)...]); x = String(sv) } else if i + 1 < rest.count { x = rest[i + 1].text }
            if !x.isEmpty { v.append(x) }
        }
        return v
    }

    /// The plain words of a command that name files: the pattern or program of grep, sed, awk and jq is not one, unless -e, --expression, --regexp or -f / --file gives it.
    private static func fileWords(_ name: String, _ rest: [Word]) -> [String] {
        var pl = plain(rest).map(\.text)
        if !progFirst.contains(name) { return pl }
        let given = flagValues(rest, "e", "--expression") + flagValues(rest, "e", "--regexp")
        for g in given { if let k = pl.firstIndex(of: g) { pl.remove(at: k) } }
        return !given.isEmpty || !flagValues(rest, "f", "--file").isEmpty ? pl : Array(pl.dropFirst())
    }

    private struct Wrap { var val: [String]; var bool: [String] }
    private static let wrap: [String: Wrap] = [
        "timeout": Wrap(val: ["-s", "-k", "--signal", "--kill-after"], bool: ["-v", "--foreground", "--preserve-status", "--verbose"]),
        "nice": Wrap(val: ["-n", "--adjustment"], bool: []),
        "ionice": Wrap(val: ["-c", "-n", "-p", "-P", "-u", "--class", "--classdata", "--pid", "--pgid", "--uid"], bool: ["-t", "--ignore"]),
        "stdbuf": Wrap(val: ["-i", "-o", "-e", "--input", "--output", "--error"], bool: []),
        "xargs": Wrap(val: ["-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a", "-R", "-S", "--max-args", "--max-procs", "--max-lines", "--max-chars", "--delimiter", "--arg-file"],
                      bool: ["-0", "-r", "-t", "-p", "-x", "-o", "--null", "--no-run-if-empty", "--verbose", "--interactive", "--exit", "--open-tty"]),
    ]

    /// Takes the options of a wrapper off the front of `a`. An option outside the wrapper's lists leaves the command word unknown: everything before the first `sudo`, `doas` or `rm` is dropped, and with none of them nothing is left.
    private static func skipWrapper(_ a: inout [Word], _ w: Wrap) {
        while true {
            guard let first = a.first, Rx.test("^-.", first.text) else { return }
            let f = first.text
            a.removeFirst()
            if f == "--" { return }
            if w.val.contains(f) { if !a.isEmpty { a.removeFirst() } }
            else if f.contains("=") || w.bool.contains(f) || Rx.test("^-\\d+\\z", f) || (!f.hasPrefix("--") && f.utf16.count > 2 && w.val.contains(String(f.prefix(2)))) { continue }
            else {
                let k = a.firstIndex { Rx.test("^(sudo|doas|rm)\\z", baseName($0.text)) }
                a.removeFirst(k ?? a.count)
                return
            }
        }
    }

    /// Looks through the words that only prefix a command: `VAR=1`, `env`, `time`, `command`, `nohup`, `sudo` and `doas` (which is remembered).
    private static func skipPrefix(_ args: [Word]) -> (sudo: Bool, args: [Word]) {
        var a = args, sudo = false
        while let w = a.first {
            let t = w.text, b = baseName(t)
            if t.isEmpty { break }
            if Rx.test("^[A-Za-z_][A-Za-z0-9_]*=", t) && !w.quoted { a.removeFirst(); continue }
            if b == "sudo" || b == "doas" {
                sudo = true; a.removeFirst()
                while let n = a.first, n.text.hasPrefix("-") { let f = a.removeFirst().text; if Rx.test("^-[ugCpD]\\z", f), !a.isEmpty { a.removeFirst() } }
                continue
            }
            if b == "env" {
                a.removeFirst()
                while let n = a.first, n.text.hasPrefix("-") || Rx.test("^[A-Za-z_][A-Za-z0-9_]*=", n.text) { a.removeFirst() }
                continue
            }
            if ["time", "command", "nohup", "builtin", "exec"].contains(b) { a.removeFirst(); continue }
            if let wr = wrap[b], b != "xargs" {
                a.removeFirst()
                skipWrapper(&a, wr)
                if b == "timeout", let n = a.first, Rx.test("^[0-9.]+[smhd]?\\z", n.text) { a.removeFirst() }
                continue
            }
            break
        }
        return (sudo, a)
    }

    /// The reason id (low) when one part of a command is on the allow-list, else nil. The command word is read as typed: `/tmp/x/ls` and `FOO=1 ls` are not `ls`.
    private static func plainReason(_ part: Part, _ cwd: String, _ home: String) -> String? {
        if part.redirs.contains(where: { $0.dup || $0.rw || $0.target != "/dev/null" }) { return nil }
        guard let c = part.args.first else { return nil }
        let words = Array(part.args.dropFirst())
        var rule: String? = nil, reason = "read_only", args = words
        if let p = plainCmds[c.text] { rule = p.rule; reason = p.reason }
        else if c.text == "git", let w0 = words.first, !w0.quoted, let r = plainGit[w0.text] { rule = r; args = Array(words.dropFirst()) }
        else {
            let line = ([c] + words).map(\.text).joined(separator: " ") + " "
            if let p = plainTests.first(where: { line.hasPrefix($0 + " ") }) {
                rule = "file"; reason = "test_build"; args = Array(words.dropFirst(p.split(separator: " ").count - 1))
                if c.text == "make", !args.isEmpty { return nil }
            }
        }
        guard let rule else { return nil }
        var ops: [String] = [], flags = ""
        for a in args {
            if !a.text.hasPrefix("-") { ops.append(a.text); continue }
            if a.text == "--" { continue }
            if !Rx.test(rule == "text" ? "^-[neE]+\\z" : safeShort, a.text) && !Rx.test(safeLong, a.text) { return nil }
            flags += a.text
        }
        if progFirst.contains(c.text), !ops.isEmpty { ops.removeFirst() }
        if c.text == "grep", Rx.test("-[A-Za-z]*[rRd]", flags) { return nil }
        func isFile(_ o: String) -> Bool {
            !Rx.test("[$*?\\[{=]", o) && !o.hasSuffix("/") && whereIs(o, cwd, home) == "inside" && lc(resolvePath(o, cwd, home)) != lc(resolvePath(cwd.isEmpty ? "." : cwd, "", home)) && secretName(o, cwd, home) == nil
        }
        let ok: Bool
        switch rule {
        case "none": ok = ops.isEmpty
        case "file": ok = ops.allSatisfy(isFile)
        case "any": ok = !(Rx.test("R", flags) && ops.contains { secretName($0, cwd, home) != nil })
        default: ok = true
        }
        return ok ? reason : nil
    }

    /// The candidates of one command line; never empty. High patterns are found in every part and wherever the text hides them, then the allow-list gives low, and any part neither knows is `unsure`.
    private static func shellCandidates(_ cmd: String, _ cwd: String, _ home: String, _ depth: Int, _ ps: Bool) -> [Cand] {
        var found: [Cand] = []
        func add(_ reason: String, _ target: String = "") { found.append(Cand(reason: reason, target: target)) }
        func writeTo(_ p: String) { let c = writeCandidate(p, cwd, home); if writeFlags.contains(c.reason) { found.append(c) } }
        func name(_ p: String) -> String { baseName(resolvePath(p, cwd, home)) }
        func outsideOf(_ paths: [String]) -> String? { paths.first { whereIs($0, cwd, home) != "inside" } }
        func command(_ args: [Word], _ part: Part, _ piped: Bool) {
            let cmdName = baseName(args[0].text), rest = Array(args.dropFirst()), pl = plain(rest).map(\.text)
            let interpreters = "^(python[0-9.]*|node|deno|bun|ruby|perl|php|lua|Rscript|(pwsh|powershell)(\\.exe)?)\\z"
            if piped && (shells.contains(cmdName) || (Rx.test(interpreters, cmdName) && !(rest.first?.text == "-m" && rest.count > 1))) { add("pipe_to_shell") }
            if (shells.contains(cmdName) || cmdName == "source" || cmdName == ".") && Rx.test("\(Rx.wordStart)(curl|wget)\(Rx.wordEnd)", cmd) && rest.contains(where: { $0.text == "<(" || Rx.test("\\$\\(|`", $0.text) }) { add("pipe_to_shell") }
            if shells.contains(cmdName) {
                let ci = rest.firstIndex { Rx.test("^-[A-Za-z]*c\\z", $0.text) }
                add("unsure")
                if let ci, ci + 1 < rest.count, depth < 2 { found.append(contentsOf: shellCandidates(rest[ci + 1].text, cwd, home, depth + 1, ps)) }
                return
            }
            if cmdName == "eval" {
                add("unsure")
                if depth < 2 { found.append(contentsOf: shellCandidates(rest.map(\.text).joined(separator: " "), cwd, home, depth + 1, ps)) }
                return
            }
            if cmdName == "xargs" {
                var x = rest
                skipWrapper(&x, wrap["xargs"]!)
                let inner = skipPrefix(x)
                add("unsure")
                if inner.sudo { add("sudo") }
                if !inner.args.isEmpty { command(inner.args, part, true) }
                return
            }
            if cmdName == "rm" || cmdName.lowercased() == "remove-item" {
                if pl.contains(where: { Rx.test("(^|/)\\.git(/|\\z)", resolvePath($0, cwd, home), .caseInsensitive) }) { add("git_history"); return }
                let rec = rest.contains { Rx.test("^-[A-Za-z]*[rR][A-Za-z]*\\z", $0.text) || $0.text == "--recursive" || Rx.test("^-recurse\\z", $0.text, .caseInsensitive) }
                func all(_ t: String) -> Bool { Rx.test("[*?\\[{]", t) }
                let bad = pl.first { t in
                    let r = resolvePath(t, cwd, home)
                    return all(t) || t == "{}" || r == "/" || Rx.test("^[A-Za-z]:/\\z", r) || isHomeFolder(r, home) || r.contains("$") || whereIs(t, cwd, home) != "inside" || (!cwd.isEmpty && lc(r) == lc(resolvePath(cwd, "", home)))
                }
                let sec = pl.compactMap { secretName($0, cwd, home) }.first
                if rec && pl.isEmpty { add("rm_recursive") }
                else if rec, let bad {
                    let rb = resolvePath(bad, cwd, home)
                    add("rm_recursive", isHomeFolder(rb, home) ? "~" : Rx.test("^([A-Za-z]:)?/\\z", rb) ? rb : name(all(bad) && whereIs(bad, cwd, home) == "inside" ? "." : bad))
                }
                else if let sec { add("sensitive_file", sec) }
                else if !rec, let o = outsideOf(pl) { add("outside_project", name(o)) }
                else { add("rm_in_project", pl.isEmpty ? "" : name(pl[0])) }
                return
            }
            if cmdName == "chmod" || cmdName == "chown" || cmdName == "chgrp" {
                let paths = Array(pl.dropFirst())
                if rest.contains(where: { Rx.test("^-[A-Za-z]*R[A-Za-z]*\\z", $0.text) || $0.text == "--recursive" }) {
                    let n = name(paths.last ?? ".")
                    add("chmod_recursive", n.isEmpty ? "/" : n)
                }
                else if let o = outsideOf(paths) { add("outside_project", name(o)) }
                return
            }
            if cmdName == "dd" || cmdName.hasPrefix("mkfs") || cmdName == "fdisk" || (cmdName == "diskutil" && Rx.test("^(erase|partition|zero|secure)", pl.first ?? "", .caseInsensitive)) { add("disk_write"); return }
            if cmdName == "git" {
                var g = rest
                while let f0 = g.first, f0.text.hasPrefix("-") {
                    let f = g.removeFirst().text
                    if f == "-c" || f == "--config-env", !g.isEmpty {
                        let key = g.removeFirst().text.components(separatedBy: "=")[0]
                        if Rx.test(execKey, key, .caseInsensitive) { add("sensitive_file", "config") }
                    }
                    else if f.hasPrefix("--config-env=") { if Rx.test(execKey, String(f.dropFirst(13)).components(separatedBy: "=")[0], .caseInsensitive) { add("sensitive_file", "config") } }
                    else if f == "-C" { if !g.isEmpty { g.removeFirst() } }
                }
                let sub = g.first?.text ?? "", fl = g.dropFirst().map(\.text), vals = fl.filter { !$0.hasPrefix("-") }
                if sub == "config" {
                    if vals.count > 1 && vals.contains(where: { Rx.test(execKey, $0, .caseInsensitive) }) && !fl.contains(where: { $0.hasPrefix("--get") }) { add("sensitive_file", "config") }
                    else if fl.contains("--list") || fl.contains("-l") { add("reads_secrets", "config") }
                } else if sub == "push" {
                    add(fl.contains(where: { Rx.test("^--force(-with-lease|-if-includes)?(=|\\z)", $0) || Rx.test("^-[A-Za-z]*f[A-Za-z]*\\z", $0) || $0.hasPrefix("+") }) ? "git_force_push" : "git_push")
                }
                else if sub == "reset" { if fl.contains("--hard") { add("git_reset_hard") } }
                else if sub == "clean" { if fl.contains(where: { $0 == "--force" || Rx.test("^-[A-Za-z]*f", $0) }) { add("git_clean") } }
                else if gitNet.contains(sub) { add("network_fetch") }
                if gitReads.contains(sub), let n = vals.compactMap({ secretName($0, cwd, home) }).first { add("reads_secrets", n) }
                return
            }
            if let o = outFlag[cmdName] { flagValues(rest, o.0, o.1).forEach(writeTo) }
            if netCmds.contains(cmdName) { add("network_fetch"); return }
            if containerCmds.contains(cmdName) { add("container"); return }
            if sqlClis.contains(cmdName) {
                for st in cmd.components(separatedBy: ";") {
                    if Rx.test("\(Rx.wordStart)DROP\\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW)\(Rx.wordEnd)", st, .caseInsensitive) || Rx.test("\\.(drop|dropDatabase)\\s*\\(", st) { add("sql_drop"); return }
                    let hasWrite = Rx.test("\(Rx.wordStart)DELETE\\s+FROM\(Rx.wordEnd)", st, .caseInsensitive) || Rx.test("\(Rx.wordStart)UPDATE[^;]*?\(Rx.wordStart)SET\(Rx.wordEnd)", st, .caseInsensitive) || Rx.test("\(Rx.wordStart)TRUNCATE\(Rx.wordEnd)", st, .caseInsensitive)
                    if (hasWrite && !Rx.test("\(Rx.wordStart)WHERE\(Rx.wordEnd)", st, .caseInsensitive)) || Rx.test("deleteMany\\(\\s*\\{\\s*\\}\\s*\\)", st) { add("sql_delete_all"); return }
                }
                return
            }
            if ["npm", "pnpm", "yarn", "bun"].contains(cmdName) { if installSubs.contains(pl.first ?? "") { add("install") }; return }
            if ["pip", "pip3", "pipx", "uv", "brew", "gem", "apt", "apt-get", "composer", "poetry", "conda", "port"].contains(cmdName) { if pl.contains(where: { installSubs.contains($0) }) { add("install") }; return }
            if cmdName == "cargo" || cmdName == "go" { if ["install", "add", "get"].contains(pl.first ?? "") { add("install") }; return }
            if writeCmds.contains(cmdName) {
                let tv = flagValues(rest, "t", "--target-directory")
                if ["touch", "mkdir", "tee"].contains(cmdName) || (cmdName == "install" && rest.contains { $0.text == "-d" }) { pl.forEach(writeTo) }
                else if !tv.isEmpty { tv.forEach(writeTo) }
                else {
                    if let last = pl.last { writeTo(last) }
                    for s in pl.dropLast() where whereIs(s, cwd, home) != "inside" { add("outside_project", name(s)) }
                }
                return
            }
            if cmdName == "sed" && rest.contains(where: { Rx.test("^(-[A-Za-z]*i|--in-place)", $0.text) }) { fileWords("sed", rest).forEach(writeTo) }
            if readers.contains(cmdName) {
                let words = fileWords(cmdName, rest) + part.redirs.filter { !$0.out }.map(\.target)
                if let n = words.compactMap({ secretName($0, cwd, home) }).first { add("reads_secrets", n) }
            }
        }

        let (parts, opaque) = splitShell(cmd, ps)
        var lists = [parts]
        if opaque {
            add("unsure")
            lists.append(splitShell(cmd.replacingOccurrences(of: "[\"'`]", with: " ", options: .regularExpression), ps).parts)
        }
        for list in lists {
            for (idx, part) in list.enumerated() {
                if let low = plainReason(part, cwd, home) { add(low); continue }
                let start = found.count, raw = part.args
                if raw.count == 1, ["env", "printenv"].contains(baseName(raw[0].text)) { add("reads_secrets", "environment"); continue }
                let (sudo, args) = skipPrefix(raw)
                if sudo { add("sudo") }
                for r in part.redirs {
                    if !r.out || r.dup || Rx.test("^/dev/(null|stdout|stderr|tty|zero)\\z", r.target) { continue }
                    if r.target.hasPrefix("/dev/") { add("disk_write") } else { writeTo(r.target) }
                }
                if !args.isEmpty { command(args, part, idx > 0 && list[idx - 1].op == "|") }
                if found.count == start { add("unsure") }
            }
        }
        if found.isEmpty { add("unsure") }
        return found
    }

    // MARK: Tools

    private static let shellTools: Set<String> = ["Bash", "PowerShell", "run_shell_command", "shell", "local_shell", "exec_command"]
    private static let readTools: Set<String> = ["Read", "Glob", "Grep", "LS", "NotebookRead", "read_file", "read_many_files", "list_directory", "search_file_content", "grep_search", "glob", "grep_files"]
    private static let toolArgs: [String: Set<String>] = {
        let t: [String: String] = [
            "Read": "file_path offset limit pages", "Glob": "pattern path", "Grep": "pattern path output_mode -i -n -A -B -C context multiline head_limit offset include", "LS": "path ignore", "NotebookRead": "notebook_path cell_id",
            "Write": "file_path content", "Edit": "file_path old_string new_string replace_all", "MultiEdit": "file_path edits", "NotebookEdit": "notebook_path new_source cell_id cell_type edit_mode",
            "read_file": "file_path absolute_path path offset limit", "read_many_files": "paths include exclude recursive useDefaultExcludes respect_git_ignore respect_gemini_ignore",
            "list_directory": "dir_path path ignore file_filtering_options respect_git_ignore respect_gemini_ignore", "search_file_content": "pattern dir_path path include", "grep_search": "pattern dir_path path include",
            "glob": "pattern dir_path path case_sensitive respect_git_ignore respect_gemini_ignore", "grep_files": "pattern include path limit",
            "write_file": "file_path content", "replace": "file_path old_string new_string instruction expected_replacements", "edit_file": "file_path old_string new_string", "apply_patch": "command",
            "WebFetch": "url prompt", "WebSearch": "query allowed_domains blocked_domains", "web_fetch": "url prompt", "google_web_search": "query", "web_search": "query",
            "Task": "description prompt subagent_type model run_in_background resume", "Agent": "description prompt subagent_type model run_in_background resume",
            "TodoWrite": "todos", "write_todos": "todos", "ExitPlanMode": "plan", "AskUserQuestion": "questions", "Skill": "skill args",
        ]
        return t.mapValues { Set($0.split(separator: " ").map(String.init)) }
    }()
    private static let searchTools: Set<String> = ["Grep", "search_file_content", "grep_search", "grep_files"]
    private static let contentTools: Set<String> = ["Read", "Grep", "NotebookRead", "read_file", "read_many_files", "search_file_content", "grep_search", "grep_files"]
    private static let webTools: Set<String> = ["WebFetch", "WebSearch", "web_fetch", "google_web_search", "web_search"]
    static let writeTools: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit", "write_file", "replace", "edit_file"]
    private static let quietTools: Set<String> = ["TodoWrite", "ExitPlanMode", "AskUserQuestion", "write_todos", "Skill"]

    /// The command of a shell tool's input: a string, or a list like `["bash","-lc","ls"]` (Codex).
    private static func commandOf(_ input: [String: Any]) -> String? {
        if let c = input["command"] as? String { return c }
        guard let a = input["command"] as? [Any] else { return nil }
        let strs = a.compactMap { $0 as? String }
        guard strs.count == a.count else { return nil }
        if strs.count >= 3, shells.contains(baseName(strs[0])), Rx.test("^-[A-Za-z]*c\\z", strs[1]) { return strs[2] }
        return strs.joined(separator: " ")
    }

    /// The files a tool writes, from its input: `file_path`, `path`, `notebook_path`, or the `*** Update File:` lines of a Codex patch.
    static func pathsOf(_ tool: String, _ input: [String: Any]) -> [String] {
        if tool == "apply_patch" {
            let t = (input["command"] as? String) ?? (input["patch"] as? String) ?? ""
            return Rx.all("^\\*\\*\\* (?:Add|Update|Delete) File: (.+)$|^\\*\\*\\* Move to: (.+)$", t, .anchorsMatchLines).map { ($0[1] ?? $0[2] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        for k in ["file_path", "absolute_path", "path", "notebook_path", "target_file"] { if let p = input[k] as? String { return [p] } }
        return []
    }

    private static func asList(_ v: Any?) -> [String] {
        if let s = v as? String { return [s] }
        if let a = v as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    private static func finish(_ reason: String, _ target: String) -> SKExplanation {
        var name = target == "~" || Rx.test("^([A-Za-z]:)?/\\z", target) ? target : (target.isEmpty ? "" : baseName(target))
        if Rx.test("\\s|[;|<>()]|(?<!\\$)&", name) { name = "a file" }
        let r = reasonById[reason]!
        let has = r.line.contains("{name}")
        return SKExplanation(risk: r.risk, reasonId: r.id, line: r.line.replacingOccurrences(of: "{name}", with: name.isEmpty ? "a file" : name), target: has ? name : "")
    }

    /// Says in plain words how risky one permission request is. Labels only. `agent` is reserved (every agent is read the same way today). `tool`, `input`, `cwd` and `home` are
    /// whatever the hook gave (a tool that is not text is no tool, an input that is not an object is no input). Returns the reason, its risk, a fixed line with a basename in it, and that basename.
    static func explain(agent: String? = nil, tool: Any?, input: Any?, cwd: Any?, home: Any?) -> SKExplanation {
        let t = tool as? String ?? "", inp = input as? [String: Any] ?? [:], dir = cwd as? String ?? "", h = home as? String ?? ""
        var cands: [Cand]? = nil
        if shellTools.contains(t) {
            if let c = commandOf(inp) { cands = c.utf16.count > 20000 ? [Cand(reason: "unsure")] : shellCandidates(c, dir, h, 0, t == "PowerShell") }
        } else if t == "apply_patch" || writeTools.contains(t) {
            let ps = pathsOf(t, inp)
            cands = ps.isEmpty ? nil : ps.map { writeCandidate($0, dir, h) }
        } else if readTools.contains(t) {
            let named = ["file_path", "absolute_path", "path", "dir_path", "paths", "notebook_path", "target_file"].flatMap { asList(inp[$0]) }
            let sec = contentTools.contains(t) ? (named + asList(inp["include"])).first { sensitivePath(resolvePath($0, dir, h)) } : nil
            let dirs = asList(inp["path"]) + asList(inp["dir_path"]) + asList(inp["paths"])
            func notFile(_ p: String) -> Bool {
                p.hasSuffix("/") || !Rx.test("\\.(ts|tsx|js|jsx|mjs|json|md|txt|py|swift|rs|go|css|html|yml|yaml|toml)\\z", baseName(p), .caseInsensitive) || lc(resolvePath(p, dir, h)) == lc(resolvePath(dir.isEmpty ? "." : dir, "", h))
            }
            let wide = (searchTools.contains(t) && (dirs.isEmpty || dirs.contains(where: notFile))) || (t == "read_many_files" && asList(inp["paths"]).contains(where: notFile))
            let off = (asList(inp["paths"]) + asList(inp["include"])).contains { Rx.test("[*?\\[{]", $0) } || named.contains { whereIs($0, dir, h) != "inside" || sensitivePath(resolvePath($0, dir, h)) || (dir.isEmpty && $0 == ".") }
            let noPath = ["Read", "NotebookRead", "LS", "read_file", "read_many_files", "list_directory"].contains(t) && !named.contains { !$0.isEmpty }
            if noPath { cands = [Cand(reason: "unsure")] }
            else if let sec { cands = [Cand(reason: "reads_secrets", target: baseName(resolvePath(sec, dir, h)))] }
            else if wide || off { cands = [Cand(reason: "unsure")] }
            else { cands = [Cand(reason: "read_only")] }
        } else if webTools.contains(t) { cands = [Cand(reason: "web")] }
        else if t == "Task" || t == "Agent" { cands = [Cand(reason: "subagent")] }
        else if quietTools.contains(t) { cands = [Cand(reason: "local_command")] }
        else if t.hasPrefix("mcp__") { cands = [Cand(reason: "mcp_tool")] }
        else if !t.isEmpty { cands = [Cand(reason: "unknown_tool")] }
        if cands != nil, !shellTools.contains(t), let allowed = toolArgs[t], !inp.keys.allSatisfy({ allowed.contains($0) }) { cands!.append(Cand(reason: "unsure")) }
        guard let list = cands, !list.isEmpty else { return finish("unsure", "") }
        func rank(_ c: Cand) -> Int { let r = reasonById[c.reason]!; return riskRank[r.risk]! * 100 - r.order }
        var best = list[0]
        for c in list.dropFirst() where rank(c) > rank(best) { best = c }
        return finish(best.reason, best.target)
    }
}
