import Foundation

// The companion's prompt, quiet and "Right now" (F3a-mac, Task 1), replayed against tests/fixtures/companion/prompt-cases.json, quiet-cases.json and
// rightnow-cases.json, and the rules those fixtures cannot write: the prompt's order, a real view's text, a stepped-back wait, the text helpers, and the
// 100,000-character inputs that every entry point must finish in under 200 ms. Run through scripts/test-companion-prompt.sh.
@MainActor
@main
enum CompanionPromptTests {
    typealias T = CompanionText
    typealias P = CompanionPrompt
    typealias RN = CompanionRightNow
    typealias Row = [String: Any]

    /// The rows of a fixture group, with the count the test expects written here: a renamed group or a lost row fails the run.
    static func rows(_ fixture: [String: Any], _ group: String, expect: Int) -> [Row] {
        let list = fixture[group] as? [Row] ?? []
        CT.check("\(group): \(expect) rows (a deliberate fixture change updates this number)", list.count, expect)
        return list
    }

    /// Rows named here are skipped by the replay, because Swift cannot hold a lone surrogate; the skipped names are collected. None of the three fixtures has one.
    static let loneSurrogateRows: Set<String> = []

    static func replayable(_ list: [Row], _ skipped: inout [String]) -> [Row] {
        list.filter { row in
            let name = row["name"] as? String ?? ""
            if loneSurrogateRows.contains(name) {
                skipped.append(name)
                return false
            }
            return true
        }
    }

    /// Byte-for-byte equality: Swift's `==` is canonical equivalence, and the fixtures compare by their code units.
    static func exact(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.utf8.elementsEqual(b.utf8)
    }

    /// The expected prompt without its memory paragraph (the paragraph starts `What you remember`).
    static func withoutMemory(_ text: String) -> String {
        text.components(separatedBy: "\n\n").filter { !$0.hasPrefix("What you remember") }.joined(separator: "\n\n")
    }

    /// A memory row: the memory is on and the input carries a memory object (the prompt does not read it here).
    static func isMemoryRow(_ input: Row?) -> Bool {
        ProjectsRegistry.isTrue(input?["useMemory"]) && (input?["memory"] as? Row) != nil
    }

    /// A "Right now" block for one project with one session at `step`.
    static func stepText(_ step: String) -> String {
        RN.text(json: [
            "projects": [["name": "a", "state": "working", "waiting": 0, "sessions": [
                ["role": "main", "label": "main", "state": "working", "waitingInApp": false, "note": "", "step": step],
            ]]],
            "waiting": 0, "otherAgentSeen": false,
        ])
    }

    static func main() {
        var skipped: [String] = []
        promptRows(&skipped)
        quietRows(&skipped)
        rightNowRows(&skipped)
        CT.check("skipped lone-surrogate rows", skipped.count, 0)
        orderAndQuiet()
        realView()
        steppedWait()
        helpers()
        timing()
        CT.finish()
    }

    static func promptRows(_ skipped: inout [String]) {
        let cases = replayable(rows(CT.fixture("prompt-cases.json", dir: "companion"), "cases", expect: 15), &skipped)
        CT.section("promptOf: \(cases.count) cases")
        var diffs: [String] = []
        var memory = 0
        for c in cases {
            let name = c["name"] as? String ?? "?"
            let input = c["input"] as? Row
            var want = c["expect"] as? String
            if isMemoryRow(input) {
                memory += 1
                want = want.map(withoutMemory)
            }
            let got = P.promptOf(CompanionPromptInput(json: c["input"]))
            if !exact(got, want) { diffs.append("\(name): got \(got.debugDescription)") }
        }
        CT.check("memory rows, compared without their memory paragraph", memory, 3)
        CT.checkRows("every prompt is the fixture's", diffs)
    }

    static func quietRows(_ skipped: inout [String]) {
        let file = CT.fixture("quiet-cases.json", dir: "companion")
        CT.section("quiet, mood and memory tokens")
        let quiet = replayable(rows(file, "quiet", expect: 5), &skipped)
        let moods = replayable(rows(file, "mood", expect: 12), &skipped)
        let tokens = replayable(rows(file, "tokens", expect: 7), &skipped)
        CT.checkRows("companionQuiet is the fixture's", quiet.compactMap { r in
            P.quiet(json: r["input"]) == (r["expect"] as? Bool) ? nil : (r["name"] as? String ?? "?")
        })
        CT.checkRows("moodHint is the fixture's", moods.compactMap { r in
            exact(P.moodHint(r["state"] as? String), r["expect"] as? String) ? nil : (r["name"] as? String ?? "?")
        })
        CT.checkRows("memoryTokensFor is the fixture's", tokens.compactMap { r in
            P.memoryTokens(placement: r["placement"] as? String, contextTokens: T.wholeNumber(r["contextTokens"])) == (r["expect"] as? Int) ? nil : (r["name"] as? String ?? "?")
        })
    }

    static func rightNowRows(_ skipped: inout [String]) {
        let file = CT.fixture("rightnow-cases.json", dir: "companion")
        CT.section("rightNowOf, cloudNotice, needsCloudNotice")
        let cases = replayable(rows(file, "cases", expect: 32), &skipped)
        let notices = replayable(rows(file, "notice", expect: 4), &skipped)
        let needs = replayable(rows(file, "needs", expect: 5), &skipped)
        CT.checkRows("every Right now block is the fixture's", cases.compactMap { c in
            exact(RN.text(json: c["view"]), c["expect"] as? String) ? nil : (c["name"] as? String ?? "?")
        })
        CT.checkRows("every cloud line is the fixture's", notices.compactMap { c in
            exact(RN.cloudNotice(provider: c["provider"]), c["expect"] as? String) ? nil : (c["name"] as? String ?? "?")
        })
        CT.checkRows("every needsCloudNotice is the fixture's", needs.compactMap { c in
            RN.needsCloudNotice(json: c["input"]) == (c["expect"] as? Bool) ? nil : (c["name"] as? String ?? "?")
        })
    }

    static func orderAndQuiet() {
        CT.section("the order is fixed, and quiet drops the joke line and the mood")
        var input = CompanionPromptInput()
        input.seeSessions = true
        input.rightNow = "MARK-NOW"
        input.today = "2026-10-17"
        let text = P.promptOf(input)
        let conduct = text.range(of: "How to behave")?.lowerBound
        let now = text.range(of: "MARK-NOW")?.lowerBound
        let today = text.range(of: "Today is 2026-10-17.")?.lowerBound
        CT.checkTrue("the prompt starts with the cat's line", text.hasPrefix("You are Shrimpy"))
        CT.checkTrue("conduct, then Right now, then the date", conduct != nil && now != nil && today != nil && conduct! < now! && now! < today!)

        var quiet = CompanionPromptInput()
        quiet.quiet = true
        quiet.mood = "finished"
        quiet.humor = "more"
        let text2 = P.promptOf(quiet)
        CT.checkTrue("quiet holds the quiet line", text2.contains(P.quietLine))
        CT.checkTrue("quiet holds no mood and no joke line", !text2.contains(P.moods["finished"] ?? "?") && !text2.contains(P.humorLines["more"] ?? "?"))
    }

    /// Thirty sessions at once: the text stays within 600 code points, names no path and counts the projects it cut.
    static func realView() {
        CT.section("a real view: no path, at most 600 code points, the rest counted")
        let now = 1_760_000_000_000.0
        var registry = PJRegistry.empty(home: "/Users/sam")
        var sent = 0
        for i in 0..<30 {
            guard let e = ProjectsRegistry.eventFrom(["hook_event_name": "PreToolUse", "session_id": "s\(i)", "cwd": "/Users/sam/Code/project-\(i)", "tool_name": "Bash"], now: now) else { continue }
            registry = ProjectsRegistry.apply(registry, e)
            sent += 1
        }
        CT.check("30 sessions were sent", sent, 30)
        let view = ProjectsSnapshot.view(registry, now: now + 100, steps: ["s0": "Edit /Users/sam/Code/project-0/src/main.rs"])
        let text = RN.text(view)
        CT.check("the view has 30 projects", view.projects.count, 30)
        CT.checkTrue("at most 600 code points (\(T.codePoints(text)))", T.codePoints(text) <= 600)
        CT.checkTrue("no path: no /Users and no backslash", !text.contains("/Users") && !text.contains("\\"))
        CT.checkTrue("the last line counts the projects it cut", text.components(separatedBy: "\n").last?.hasSuffix("more projects") == true)
    }

    /// A permission request that steps back into Ghostty: named in the block, counted, and the chat is quiet.
    static func steppedWait() {
        CT.section("a real stepped-back wait is named, counted and keeps the chat quiet")
        let now = 1_760_000_000_000.0
        guard let e = ProjectsRegistry.eventFrom(["hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/Users/sam/Code/site", "tool_name": "Bash"], now: now, waitIn: "Ghostty") else {
            CT.checkTrue("the permission request is an event", false)
            return
        }
        let registry = ProjectsRegistry.apply(PJRegistry.empty(home: "/Users/sam"), e)
        let view = ProjectsSnapshot.view(registry, now: now + 1_000)
        let want = RN.head + "\n- site: main waiting for approval (Waiting in Ghostty)\nWaiting for the user: 1."
        CT.checkTrue("the block names the wait and counts it", exact(RN.text(view), want))
        CT.check("the view counts one waiting session", view.waiting, 1)
        CT.check("a waiting session keeps the chat quiet", P.quiet(waiting: view.waiting, card: false), true)
    }

    /// The helpers, pinned by hand against the core (companion-core.js: isDay, and the secret and word rules read through Right now).
    static func helpers() {
        CT.section("the text helpers, pinned by hand")
        CT.check("isDay: a leap day", T.isDay("2024-02-29"), true)
        CT.check("isDay: no 2026-02-30", T.isDay("2026-02-30"), false)
        CT.check("isDay: 2100 is no leap year", T.isDay("2100-02-29"), false)
        CT.check("isDay: year 0000 is a leap year", T.isDay("0000-02-29"), true)
        CT.check("isDay: a fullwidth digit is no digit", T.isDay("２０２６-10-17"), false)
        CT.check("isDay: a short month is no day", T.isDay("2026-1-01"), false)
        CT.check("isDay: a number is no day", T.isDay(20_261_017), false)
        CT.check("clean takes the invisible characters out, with no space", T.clean("a\u{202E}b\tc"), "abc")
        CT.check("cutTo keeps a short text whole", T.cutTo("abc", 4), "abc")
        CT.check("cutTo cuts with an ellipsis", T.cutTo("abcdef", 4), "abc…")
        CT.check("lastPart: the text after the last / or backslash", T.lastPart("a\\b/c"), "c")
        CT.check("lastPart: a word with no separator is itself", T.lastPart("plain"), "plain")
        CT.check("codePoints counts an emoji as one", T.codePoints("😀a"), 2)
        CT.check("a card number in one word is dropped", stepText("Edit 4111111111111111"), RN.head + "\n- a: main working (Edit)")
        CT.check("a password word is dropped", stepText("Set password=hunter2"), RN.head + "\n- a: main working (Set)")
        CT.check("an ISO date is kept", stepText("Open 2026-10-17"), RN.head + "\n- a: main working (Open 2026-10-17)")
        CT.check("a kebab name is kept", stepText("Use a-b-c-d"), RN.head + "\n- a: main working (Use a-b-c-d)")
        CT.check("a long random word with a slash is dropped", stepText("Read tests/AbCdEfGhIjKlMnOpQrStUvWx12"), RN.head + "\n- a: main working (Read)")
        CT.check("a web address keeps its last part", stepText("Read https://u:p@host.com/x"), RN.head + "\n- a: main working (Read x)")
        CT.check("a bearer word with no token is kept", stepText("Edit Bearer abcdefghijklmnopqrstuvwxyz0123"), RN.head + "\n- a: main working (Edit Bearer)")
        CT.check("a path into a key segment is dropped whole", stepText("Go /tmp/sk-abcdefghijklmnopqrstuvwxyz1234x/y/z.md"), RN.head + "\n- a: main working (Go)")
        CT.checkTrue("the conduct text still holds the sentence the Claude plan's tools line answers (ClaudeService adds its line at Read-only and Agent)", P.conduct.contains("You cannot act on the Mac yet (open apps, play music, change files)"))
        // Short userinfo words: the core has no 8-character floor (expected values printed by running node against shared/companion-core.js).
        CT.check("isSecret: ab://:@ is a secret (userinfo)", T.isSecret("ab://:@"), true)
        CT.check("isSecret: x://:@y is a secret (userinfo)", T.isSecret("x://:@y"), true)
        CT.check("isSecret: a://:@ is a secret (userinfo)", T.isSecret("a://:@"), true)
        CT.check("isSecret: p:@ is no secret", T.isSecret("p:@"), false)
        CT.check("shownWord: ab://:@ is dropped", T.shownWord("ab://:@"), "")
        CT.check("shownWord: x://:@y keeps its last part", T.shownWord("x://:@y"), ":@y")
        CT.check("shownWord: a://:@ keeps its last part", T.shownWord("a://:@"), ":@")
    }

    /// Every entry point, on 100,000-character inputs of each hostile shape, finishes in under 200 ms.
    static func timing() {
        CT.section("100,000-character inputs: every entry point under 200 ms")
        func fill(_ unit: String) -> String { String(String(repeating: unit, count: 100_000 / unit.count + 1).prefix(100_000)) }
        let inputs: [(String, String)] = [
            ("dots", "a" + String(repeating: ".", count: 99_998) + "a"),
            ("digits", String(repeating: "1", count: 100_000)),
            ("digit pairs", fill("1 ")),
            ("digit dashes", fill("1-")),
            ("slashes", String(repeating: "/", count: 100_000)),
            ("path steps", fill("/a")),
            ("spaces", String(repeating: " ", count: 100_000)),
            ("sk runs", fill("sk-")),
            ("letters", String(repeating: "a", count: 100_000)),
            ("random runs", fill("Ab1")),
            ("dates", fill("2026-10-17 ")),
            ("userinfo", "https://" + fill("a:").prefix(99_992) + "@x"),
            ("bearer", "bearer " + String(repeating: "a", count: 99_993)),
        ]
        let entryPoints: [(String, (String) -> Void)] = [
            ("isSecret", { _ = T.isSecret($0) }),
            ("shownWord", { _ = T.shownWord($0) }),
            ("clean", { _ = T.clean($0) }),
            ("cutTo", { _ = T.cutTo($0, 80) }),
            ("lastPart", { _ = T.lastPart($0) }),
            ("isDay", { _ = T.isDay($0) }),
            ("cloudNotice", { _ = RN.cloudNotice(provider: $0) }),
            ("needsCloudNotice", { _ = RN.needsCloudNotice(json: ["placement": "cloud", "seeSessions": true, "provider": $0, "shown": []]) }),
            ("Right now", { text in
                _ = RN.text(json: ["projects": [["name": text, "state": "approval", "waiting": 1, "sessions": [[
                    "role": "side", "label": text, "state": "approval", "waitingInApp": true, "note": text, "step": text,
                ]]]], "waiting": 1, "otherAgentSeen": true])
            }),
            ("personality name", { _ = P.personalityLine(CompanionPromptInput(json: ["catName": $0, "userName": $0])) }),
            ("prompt", { _ = P.promptOf(CompanionPromptInput(json: ["rightNow": $0, "seeSessions": true, "today": "2026-10-17"])) }),
        ]
        var slow: [String] = []
        var worst = 0.0
        for (label, text) in inputs {
            for (name, run) in entryPoints {
                let t0 = ProcessInfo.processInfo.systemUptime
                run(text)
                let ms = (ProcessInfo.processInfo.systemUptime - t0) * 1000
                worst = max(worst, ms)
                if ms >= 200 { slow.append("\(name) on \(label): \(Int(ms)) ms") }
            }
        }
        print("  slowest call: \(String(format: "%.1f", worst)) ms")
        CT.checkRows("every entry point on every 100,000-character input is under 200 ms", slow)
    }
}
