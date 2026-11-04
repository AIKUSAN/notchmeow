import Foundation

// The agent-cat drop rules: the grid cats' circles, which cat is under a point (and only for an agent with a live session), what goes on the clipboard and the line the island shows.
// Run through scripts/test-sidekick-drop.sh.

@main
enum SidekickDropTests {
    typealias D = SidekickDrop

    // MARK: Running the clipboard text in a real shell (a test may run one; the app never does)

    struct Ran { var out: [UInt8]; var err: [UInt8]; var status: Int32; var leftovers: [String] }

    /// `printf %s <text>` in a shell, from an empty scratch folder: what the shell prints, and what it left behind in the folder (a `;touch x` or a `> x` would leave a file).
    static func run(_ shell: [String], _ text: String, dir: URL, utf8: Bool, prefix: String = "printf %s ") -> Ran {
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(fileURLWithPath: shell[0])
        // The script goes in through stdin, as bytes: Process.arguments would hand the shell a file-system-normalised string (NFD, marks reordered), not the text that was copied.
        p.arguments = Array(shell.dropFirst())
        let stdin = Pipe()
        p.currentDirectoryURL = dir
        p.environment = ["PATH": "/usr/bin:/bin", "HOME": dir.path, "LC_ALL": utf8 ? "en_US.UTF-8" : "C"]
        p.standardOutput = out; p.standardError = err; p.standardInput = stdin
        do { try p.run() } catch { return Ran(out: [], err: Array("could not run".utf8), status: -1, leftovers: []) }
        stdin.fileHandleForWriting.write(Data((prefix + text + "\n").utf8))
        try? stdin.fileHandleForWriting.close()
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let left = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        for f in left { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        return Ran(out: [UInt8](o), err: [UInt8](e), status: p.terminationStatus, leftovers: left)
    }

    static let shells: [(name: String, argv: [String])] = [("sh", ["/bin/sh", "-s"]), ("bash", ["/bin/bash", "--noprofile", "--norc", "-s"]), ("zsh", ["/bin/zsh", "-f", "-s"])]
        .filter { FileManager.default.isExecutableFile(atPath: $0.argv[0]) }

    /// "" when the path is refused (nothing is copied, so nothing can run) or when a shell given the copied text prints exactly the path (compared byte for byte, not with Swift's `==`, which
    /// treats `e` + U+0301 and U+00E9 as the same) and leaves nothing behind; else what went wrong.
    static func proof(_ path: String, shells: [(name: String, argv: [String])], dir: URL, utf8: [Bool] = [false, true]) -> String {
        guard let text = D.clipboardText(paths: [path]) else { return "" }
        for sh in shells { for u in utf8 {
            let r = run(sh.argv, text, dir: dir, utf8: u)
            if r.out != Array(path.utf8) || !r.err.isEmpty || r.status != 0 || !r.leftovers.isEmpty {
                return "\(sh.name)\(u ? "/utf8" : "/C") \(path.debugDescription) -> text \(text.debugDescription) printed \(String(decoding: r.out, as: UTF8.self).debugDescription) err \(String(decoding: r.err, as: UTF8.self).debugDescription) status \(r.status) left \(r.leftovers) bytes \(r.out.count)/\(path.utf8.count)"
            }
        } }
        return ""
    }

    /// "" when a shell given the copied text of SEVERAL paths gets exactly those paths as separate arguments, in order (printf '%s\0' prints each argument NUL-terminated), prints no error and leaves nothing behind.
    static func multiProof(_ paths: [String], shells: [(name: String, argv: [String])], dir: URL, utf8: [Bool] = [false, true]) -> String {
        guard let text = D.clipboardText(paths: paths) else { return "" }
        if text.unicodeScalars.contains(where: { [0x0A, 0x0D, 0x85, 0x2028, 0x2029].contains($0.value) }) { return "text has a line break: \(text.debugDescription)" }
        var want: [UInt8] = []
        for p in paths { want += Array(p.utf8); want.append(0) }
        for sh in shells { for u in utf8 {
            let r = run(sh.argv, text, dir: dir, utf8: u, prefix: "printf '%s\\0' ")
            if r.out != want || !r.err.isEmpty || r.status != 0 || !r.leftovers.isEmpty {
                return "\(sh.name)\(u ? "/utf8" : "/C") \(paths.debugDescription) -> text \(text.debugDescription) printed \(r.out.count) bytes, wanted \(want.count); err \(String(decoding: r.err, as: UTF8.self).debugDescription) status \(r.status) left \(r.leftovers)"
            }
        } }
        return ""
    }

    static func scalars(_ ranges: ClosedRange<UInt32>...) -> [Unicode.Scalar] { ranges.flatMap { $0.compactMap(Unicode.Scalar.init) } }

    @MainActor static func main() {
        CT.section("the compact grid: four cells, 16 pt apart, centred 40 pt in from the island's right edge")
        let pills: [(pill: String, agent: Bool)] = [("agent_codex", true), ("integration_github", false), ("agent_gemini", true), ("agent_antigravity", true)]
        let cats = D.gridCats(pills: pills, panelWidth: 720, islandWidth: 300, islandHeight: 32)
        CT.check("the pill that wears no agent's coat is not a target", cats.map(\.pill), ["agent_codex", "agent_gemini", "agent_antigravity"])
        CT.check("top left of the grid: 8 pt left of and 8 pt above the centre (island left 210, right 510, centre 470, 16 down)", [cats[0].x, cats[0].y, cats[0].r], [462, 8, 8])
        CT.check("bottom left", [cats[1].x, cats[1].y], [462, 24])
        CT.check("bottom right", [cats[2].x, cats[2].y], [478, 24])
        let strip = D.gridCats(pills: pills, panelWidth: 720, islandWidth: 300, islandHeight: 24)
        CT.checkNear("a strip of 24 pt shrinks the grid like the island's grid does (20 / 28)", strip[0].r, 8 * 20.0 / 28.0)
        CT.check("at most four cells", D.gridCats(pills: (0..<6).map { ("agent_x\($0)", true) }, panelWidth: 720, islandWidth: 300, islandHeight: 32).count, 4)

        CT.section("which cat is under the point")
        let live: Set<String> = ["agent_codex", "agent_gemini"]
        CT.check("on a cat with a live session", D.agentCatAt(x: 462, y: 8, cats: cats, live: live), "agent_codex")
        CT.check("at the edge of the circle", D.agentCatAt(x: 470, y: 8, cats: cats, live: live), "agent_codex")
        CT.check("just outside it", D.agentCatAt(x: 470.1, y: 8, cats: cats, live: live), nil)
        CT.check("on a cat whose agent has no live session: the drop is what it always was", D.agentCatAt(x: 478, y: 24, cats: cats, live: live), nil)
        CT.check("on the second live cat", D.agentCatAt(x: 462, y: 24, cats: cats, live: live), "agent_gemini")
        CT.check("anywhere else on the island", D.agentCatAt(x: 300, y: 16, cats: cats, live: live), nil)
        CT.check("two circles that overlap: the nearer centre wins", D.agentCatAt(x: 6, y: 0, cats: [D.Cat(pill: "agent_a", x: 0, y: 0, r: 8), D.Cat(pill: "agent_b", x: 10, y: 0, r: 8)], live: ["agent_a", "agent_b"]), "agent_b")
        CT.check("a tie goes to the first", D.agentCatAt(x: 5, y: 0, cats: [D.Cat(pill: "agent_a", x: 0, y: 0, r: 8), D.Cat(pill: "agent_b", x: 10, y: 0, r: 8)], live: ["agent_a", "agent_b"]), "agent_a")
        CT.check("no cats, no target", D.agentCatAt(x: 0, y: 0, cats: [], live: live), nil)
        CT.check("a point that is not a number is on nothing", D.agentCatAt(x: .nan, y: 8, cats: cats, live: live), nil)

        CT.section("the clipboard and the line")
        CT.check("one file whose name holds only letters, digits and _ . / + @ % , : = -: its plain path, as it is", D.clipboardText(paths: ["/Users/me/Documents/report-2024.pdf"]), "/Users/me/Documents/report-2024.pdf")
        CT.check("one file whose name holds a space: its path between single quotes", D.clipboardText(paths: ["/Users/me/My Files/a b.txt"]), "'/Users/me/My Files/a b.txt'")
        CT.check("several files: one line, the paths space-separated, each through the single-path rule", D.clipboardText(paths: ["/a/1.txt", "/a/2 x.txt"]), "/a/1.txt '/a/2 x.txt'")
        CT.check("no file, nothing", D.clipboardText(paths: []), nil)
        CT.check("a path with a line break is never copied: a pasted line break would run what follows", D.clipboardText(paths: ["/a/ok.txt", "/a/x\nrm -rf ~"]), nil)
        CT.check("nor one with an escape or a tab", [D.clipboardText(paths: ["/a/\u{1B}[2J"]), D.clipboardText(paths: ["/a/\tb"])], [nil, nil])
        CT.check("nor one with a bidi control: it can show a name that is not the one a shell runs", ["/a/\u{202E}gnp.txt", "/a/\u{202A}x", "/a/\u{202C}x", "/a/\u{2066}x", "/a/\u{2069}x"].map { D.clipboardText(paths: [$0]) }, [nil, nil, nil, nil, nil])
        CT.check("nor one with a zero-width or format character", ["/a/a\u{200B}b", "/a/a\u{200D}b", "/a/a\u{200E}b", "/a/a\u{200F}b", "/a/a\u{2060}b", "/a/\u{FEFF}b"].map { D.clipboardText(paths: [$0]) }, [nil, nil, nil, nil, nil, nil])
        CT.check("a path with ; | or a backtick is copied in single quotes, which no shell expands", ["/a/x;y.txt", "/a/x|y.txt", "/a/x`y`.txt"].map { D.clipboardText(paths: [$0]) }, ["'/a/x;y.txt'", "'/a/x|y.txt'", "'/a/x`y`.txt'"])
        CT.check("$( and && are quoted too", ["/a/$(rm x).txt", "/a/a && b.txt"].map { D.clipboardText(paths: [$0]) }, ["'/a/$(rm x).txt'", "'/a/a && b.txt'"])
        CT.check("a lone & < > ( ) * ? [ ] { } \" # and a space are quoted: R&D plan.pdf, <, >, <(, *, ?, [, {, \", #, My File (1).pdf", ["/a/R&D plan.pdf", "/a/x<y.txt", "/a/x>y.txt", "/a/<(ls).txt", "/a/*.txt", "/a/q?.txt", "/a/[1].txt", "/a/{x}.txt", "/a/\"q\".txt", "/a/#1.txt", "/a/My File (1).pdf"].map { D.clipboardText(paths: [$0]) }, ["'/a/R&D plan.pdf'", "'/a/x<y.txt'", "'/a/x>y.txt'", "'/a/<(ls).txt'", "'/a/*.txt'", "'/a/q?.txt'", "'/a/[1].txt'", "'/a/{x}.txt'", "'/a/\"q\".txt'", "'/a/#1.txt'", "'/a/My File (1).pdf'"])
        CT.check("a single quote in the path is written as '\\'' inside the quotes", [D.clipboardText(paths: ["/a/it's;x"]), D.clipboardText(paths: ["/a/it's #1.txt"])], ["'/a/it'\\''s;x'", "'/a/it'\\''s #1.txt'"])
        CT.check("several paths: each quoted only when it needs it, space-separated on one line", D.clipboardText(paths: ["/a/1.txt", "/a/it's;x", "/a/My Files/a b.txt", "/a/2.txt"]), "/a/1.txt '/a/it'\\''s;x' '/a/My Files/a b.txt' /a/2.txt")
        CT.check("two, three and four paths: no line break anywhere in the text (CRLF is two scalars but one Character: look at the scalars)", [["/a/1.txt", "/a/2 x.txt"], ["/a/1.txt", "/a/2 x.txt", "/a/it's.txt"], ["/a/1.txt", "/a/2.txt", "/a/3.txt", "/a/4;x.txt"]].map { D.clipboardText(paths: $0)!.unicodeScalars.contains(where: { [0x0A, 0x0D, 0x85, 0x2028, 0x2029].contains($0.value) }) }, [false, false, false])
        CT.check("a single refused name refuses the whole drop, with the same line", [D.clipboardText(paths: ["/a/1.txt", "/a/x\\y"]), D.clipboardText(paths: ["/a/ok.txt", "/a/2 x.txt", "/a/x!y"])], [nil, nil])
        CT.check("a plain name, an = and a non-ASCII letter, digit or mark are copied as they are", ["/a/plain.txt", "/a/My_File+1.txt", "/a/a=b,c:d@e%f.txt", "/a/\u{E9}.txt", "/a/e\u{301}.txt", "/a/\u{65E5}\u{672C}\u{8A9E}.txt", "/a/\u{661}\u{662}.txt"].map { D.clipboardText(paths: [$0]) }, ["/a/plain.txt", "/a/My_File+1.txt", "/a/a=b,c:d@e%f.txt", "/a/\u{E9}.txt", "/a/e\u{301}.txt", "/a/\u{65E5}\u{672C}\u{8A9E}.txt", "/a/\u{661}\u{662}.txt"])
        CT.check("a space, a ~, a leading -, an emoji, a no-break space or a fullwidth ; are not in the safe set: quoted", ["/a/My File.pdf", "/Users/me/old ~", "/a/~", "/a/x -rf", "/a/\u{1F600}.txt", "/a/a\u{A0}b", "/a/a\u{FF1B}b"].map { D.clipboardText(paths: [$0]) }, ["'/a/My File.pdf'", "'/Users/me/old ~'", "'/a/~'", "'/a/x -rf'", "'/a/\u{1F600}.txt'", "'/a/a\u{A0}b'", "'/a/a\u{FF1B}b'"])
        CT.check("a path that does not start with / (never a file URL's) is quoted: a leading - would be a flag", ["-rf", "=ls", "x"].map { D.clipboardText(paths: [$0]) }, ["'-rf'", "'=ls'", "'x'"])
        CT.check("a backslash or a ! is refused: fish and csh read them inside single quotes, so the name is not copied", ["/a/back\\slash", "/a/x\\'y;curl z", "/a/x\\y.txt", "/a/Wow!.mp3", "/a/a\\'b;c", "/a/hi!.txt"].map { D.clipboardText(paths: [$0]) }, [nil, nil, nil, nil, nil, nil])
        CT.check("a control, bidi or invisible character refuses the path even with a shell character in it", ["/a/x;\u{1B}", "/a/\u{202E};x", "/a/;\u{200B}x", "/a/;\u{2028}"].map { D.clipboardText(paths: [$0]) }, [nil, nil, nil, nil])
        CT.section("a path with a control, format, line-separator or invisible character, a backslash or a ! is never copied")
        let invisible: [(String, [Unicode.Scalar])] = [
            ("control (C0, DEL, C1)", scalars(0x00...0x1F, 0x7F...0x9F)), ("line and paragraph separator", scalars(0x2028...0x2029)),
            ("tag characters", scalars(0xE0000...0xE007F)), ("variation selectors", scalars(0xFE00...0xFE0F, 0xE0100...0xE01EF)),
            ("soft hyphen, Arabic letter mark, invisible math operators", scalars(0xAD...0xAD, 0x61C...0x61C, 0x2061...0x2064, 0x206A...0x206F)),
            ("combining grapheme joiner, Hangul fillers", scalars(0x34F...0x34F, 0x3164...0x3164, 0xFFA0...0xFFA0)),
            ("interlinear annotation, musical beam", scalars(0xFFF9...0xFFFB, 0x1D173...0x1D17A)),
            ("zero-width, bidi, word joiner, BOM", scalars(0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2060, 0x2066...0x2069, 0xFEFF...0xFEFF)),
        ]
        for (label, set) in invisible {
            let bad = set.filter { D.clipboardText(paths: ["/a/x\($0)y"]) != nil }.map { String($0.value, radix: 16) }
            CT.check("\(label): every scalar refuses the path (\(set.count) tried)", bad, [])
        }
        CT.check("a backslash, a !, a newline and a carriage return refuse it, alone or among other paths", ["/a/x\\y", "/a/x!y", "/a/x\ny", "/a/x\r\ny"].map { D.clipboardText(paths: [$0]) } + [D.clipboardText(paths: ["/a/ok.txt", "/a/x\\y"])], [nil, nil, nil, nil, nil])
        CT.check("a no-break space and an emoji are not invisible: they are quoted, not refused", ["/a/a\u{A0}b", "/a/\u{1F600}"].map { D.clipboardText(paths: [$0]) != nil }, [true, true])

        CT.section("what a shell does with the copied text: prints the path and does nothing else (sh, bash and zsh, run from an empty folder)")
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp").appendingPathComponent("f1-drop-proof-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        CT.checkTrue("at least sh and zsh are there to run the text in (\(shells.map(\.name)))", shells.map(\.name).contains("sh") && shells.map(\.name).contains("zsh"))
        let injection = "/a/'\u{301};echo PWNED;#"
        CT.checkTrue("the combining-mark injection name is copied (quoted), not refused", D.clipboardText(paths: [injection]) != nil)
        CT.check("the combining-mark injection name: the shell prints the path and nothing runs", proof(injection, shells: shells, dir: dir), "")
        let long = "/a/" + String(repeating: "x", count: 4000)
        let hostile: [String] = [
            "/a/x'\u{301}", "/a/'\u{301}x", "/a/x'\u{301}y'\u{302}z", "/a/''\u{20D2}", "/a/'\u{301}'\u{301};touch f1-pwned;'", "/a/'", "/'", "'", "/a/x' ;echo PWNED; echo '", "/a/it's",
            "/a/'\u{300}\u{301}\u{302}\u{303};echo PWNED", "/a/\u{301}';echo PWNED;'", "/a/;'\u{20D2}\u{0345}; echo PWNED #",
            "/Users/me/old ~", "/a/~", "/~root", "/a/~/x", "/a/x =ls", "/a/=ls", "/a/-rf", "/a/x -rf", "/a/a=~/b", "/a/a:~", "/a/^x", "/a/x^y", "/a/*", "/a/[abc]", "/a/{a,b}", "/a/{1..3}", "/a/@(x)", "/a/+(x)", "/a/?(x)",
            "/a/$HOME", "/a/$(echo PWNED)", "/a/`echo PWNED`", "/a/${HOME}", "/a/\"q\"", "/a/#x", "/a/x #y", "/a/100%", "/a/a&b", "/a/a|b", "/a/a>b", "/a/a<b", "/a/(x)", "/a/x;touch f1-pwned", "/a/a?b",
            "/a/\u{1F600}.txt", "/a/\u{65E5}\u{672C}\u{8A9E} \u{4E2D}.txt", "/a/a\u{A0}b", "/a/a\u{3000}b", "/a/\u{FF1B}echo", "/a/e\u{301}.txt", "/a/\u{E9}.txt", "/a/My File.pdf", "/Users/me/Documents/report-2024.pdf",
            long, "/a/" + String(repeating: "'", count: 300), "/a/" + String(repeating: "'\u{301}", count: 100) + ";echo PWNED",
            "/a/\\x", "/a/x!", "/a/x\n;echo PWNED", "/a/\u{E0041}x", "/a/x\u{FE0F}",
        ]
        let failed = hostile.map { proof($0, shells: shells, dir: dir) }.filter { !$0.isEmpty }
        CT.check("every one of \(hostile.count) hostile names is refused or round-trips in every shell and both locales", failed, [])

        CT.section("a deterministic mini-fuzz: 2000 names from quotes, punctuation, combining marks, spaces, letters and CJK (sh and zsh)")
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ n: Int) -> Int { seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407; return Int((seed >> 33) % UInt64(n)) }
        let punct = scalars(0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E)
        let pool = punct + Array(repeating: Unicode.Scalar(0x27)!, count: 10) + scalars(0x300...0x36F) + scalars(0x20D2...0x20D2) + Array(repeating: Unicode.Scalar(0x20)!, count: 6) + scalars(0x30...0x39, 0x41...0x5A, 0x61...0x7A) + scalars(0x4E00...0x4E1F)
        var names: [String] = [], nonNil = 0, quoteMark = 0
        for _ in 0..<2000 {
            var n = "/a/"
            for _ in 0..<(1 + next(12)) { n.unicodeScalars.append(pool[next(pool.count)]) }
            names.append(n)
        }
        let sz = shells.filter { $0.name == "sh" || $0.name == "zsh" }
        var fuzzFailed: [String] = []
        for n in names {
            if D.clipboardText(paths: [n]) != nil { nonNil += 1 }
            let u = Array(n.unicodeScalars)
            if zip(u, u.dropFirst()).contains(where: { $0.0 == "'" && (0x300...0x36F).contains($0.1.value) }) { quoteMark += 1 }
        }
        // 100 names per shell: one `printf '%s\0' <text>` each, so a name that broke its quoting changes the whole output and the batch is then run name by name to find it.
        for start in stride(from: 0, to: names.count, by: 100) {
            let batch = names[start..<min(start + 100, names.count)].filter { D.clipboardText(paths: [$0]) != nil }
            let script = batch.map { "printf '%s\\0' " + D.clipboardText(paths: [$0])! }.joined(separator: "\n")
            var want: [UInt8] = []
            for n in batch { want += Array(n.utf8); want.append(0) }
            for sh in sz {
                let r = run(sh.argv, script, dir: dir, utf8: true, prefix: "")
                if r.out != want || !r.err.isEmpty || !r.leftovers.isEmpty { fuzzFailed += batch.map { proof($0, shells: [sh], dir: dir, utf8: [true]) }.filter { !$0.isEmpty }; if fuzzFailed.isEmpty { fuzzFailed.append("\(sh.name): a batch differs, but no name alone does") } }
            }
        }
        CT.checkTrue("the fuzz is not vacuous: \(nonNil) names are copied, \(quoteMark) hold a quote followed by a combining mark", nonNil > 1000 && quoteMark > 15)
        CT.check("every copied fuzz name round-trips in sh and zsh and leaves nothing behind", Array(fuzzFailed.prefix(3)), [])
        CT.section("several paths: one line, and the shell gets them back as separate arguments, in order (sh, bash, zsh, both locales)")
        let sets: [[String]] = [
            ["/a/1.txt", "/a/2.txt"], ["/a/plain.txt", "/a/My File.pdf"], ["/a/1.txt", "/a/2 x.txt", "/a/it's.txt"],
            ["/a/'\u{301};echo PWNED;#", "/a/ok.txt", "/a/$(rm x)"], ["/a/old ~", "/a/-rf", "/a/=ls"], ["/a/\u{65e5}\u{672c}.txt", "/a/\u{1F431} cat.png", "/a/x\u{301}y"],
            ["/a/*", "/a/[x]", "/a/{a,b}", "/a/a;b", "/a/a|b", "/a/a&b", "/a/a<b>c"], ["/a/1", "/a/2", "/a/3", "/a/4", "/a/5 five", "/a/6 'six'"],
        ]
        let multiFailed = sets.map { multiProof($0, shells: shells, dir: dir) }.filter { !$0.isEmpty }
        CT.check("every set of paths is one line and comes back as the same words in every shell", multiFailed, [])
        var multiFuzz: [String] = []
        var multiRan = 0
        for i in 0..<400 {
            let k = 2 + next(3)
            let set = (0..<k).map { j in names[(i * 7 + j * 13) % names.count] }
            if D.clipboardText(paths: set) == nil { continue }   // a set with a refused name is nil: no shell run, counted apart
            multiRan += 1
            let r = multiProof(set, shells: sz, dir: dir, utf8: [true])
            if !r.isEmpty { multiFuzz.append(r) }
            if multiRan == 150 { break }
        }
        CT.checkTrue("the multi-path fuzz is not vacuous: \(multiRan) sets were copied and run in a shell", multiRan == 150)
        CT.check("150 copied sets of 2 to 4 fuzz names come back as the same words, in sh and zsh", Array(multiFuzz.prefix(3)), [])
        CT.check("a set with a refused name is nil, whatever the others are", sets.map { D.clipboardText(paths: $0 + ["/a/x\\y"]) == nil }, Array(repeating: true, count: sets.count))
        try? FileManager.default.removeItem(at: dir)
        CT.section("the line")
        CT.check("the line for one path", D.line(agentName: "Claude Code", count: 1), "Copied the path \u{2014} paste it into Claude Code")
        CT.check("the line for several", D.line(agentName: "Codex", count: 3), "Copied 3 paths \u{2014} paste them into Codex")
        let words = [D.line(agentName: "Claude Code", count: 1), D.line(agentName: "Codex", count: 2), D.refusedLine()].joined(separator: " ").lowercased()
        CT.check("the refusal names no line break: a tab or an escape is refused too", [D.refusedLine().contains("a character a terminal would act on"), D.refusedLine().lowercased().contains("line break")], [true, false])
        CT.check("no line says sent, delivered or attached", ["sent", "delivered", "attached"].filter { words.contains($0) }, [])
        CT.finish()
    }
}
