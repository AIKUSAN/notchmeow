import Foundation

// The recap, the status answer and the status question's matcher against tests/fixtures/sidekick/recap-cases.json and status-cases.json, and what the fixture cannot write (a time that is
// not finite, a marker planted in every input that must never reach a line or a fact). Run through scripts/test-sidekick-recap.sh.

@main
enum SidekickRecapTests {
    typealias R = SidekickRecap
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func number(_ v: Any?) -> Double? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }; return n.doubleValue }
    static func sessions(_ snap: [String: Any]) -> [SKSession] { rows(snap["sessions"]).map(SKSession.init(json:)) }

    @MainActor static func main() {
        let rx = CT.fixture("recap-cases.json", dir: "sidekick"), st = CT.fixture("status-cases.json", dir: "sidekick")

        CT.section("the frozen numbers")
        CT.check("a recap needs two minutes away", R.minAwayMs, number(rx["min"])!)

        let recaps = rows(rx["cases"])
        CT.section("recapOf: \(recaps.count) cases, the lines and the facts each one gives (or nothing)")
        var diffs: [String] = []
        for c in recaps {
            let snap = c["snapshot"] as! [String: Any]
            let got = R.recap(awaySince: number(snap["awaySince"])!, now: number(snap["now"])!, sessions: sessions(snap))
            let d = CT.diffs(got?.json ?? NSNull(), c["recap"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every recap is the fixture's", diffs)

        let statuses = rows(st["cases"])
        CT.section("statusOf: \(statuses.count) cases")
        diffs = []
        for c in statuses {
            let snap = c["snapshot"] as! [String: Any]
            let got = R.status(now: number(snap["now"])!, sessions: sessions(snap), agent: c["agent"] as? String)
            let d = CT.diffs(got.json, c["status"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every status is the fixture's", diffs)

        let matcher = rows(st["matcher"])
        CT.section("matchStatusQuestion: \(matcher.count) messages")
        diffs = []
        for m in matcher {
            let got = R.matchStatusQuestion(m["text"] as! String)
            if got.matched != (m["matched"] as! Bool) || got.agentId != (m["agentId"] as? String) { diffs.append("\(m["text"] as! String): \(got), want \(m["matched"] ?? "?") \(m["agentId"] ?? "nil")") }
        }
        CT.checkRows("a whole short message is the question, anything else is a normal message", diffs)

        CT.section("what the fixture cannot write")
        CT.check("a time that is not finite gives no recap", R.recap(awaySince: .nan, now: 5_000_000, sessions: []) == nil && R.recap(awaySince: 0, now: .infinity, sessions: []) == nil, true)
        CT.check("nothing is running, and the answer says so, with a time that is not finite too", [R.status(now: .nan, sessions: []).lines, R.status(now: 5, sessions: []).lines], [["No agent is running right now."], ["No agent is running right now."]])
        CT.check("a named agent that is not running", R.status(now: 5, sessions: [], agent: "agent_codex").lines, ["Codex is not running right now."])
        var s = SKSession(key: "integration_claude|S", agentId: "integration_claude", sessionId: "S", startedAt: 0, lastEventAt: 10_000)
        s.project = "proj"; s.state = "working"
        s.ring = [SKRing(at: 5000, kind: "tool", tool: "Edit", target: "a.js", file: "a.js", key: "Edit#1", ok: true), SKRing(at: 6000, kind: "tool", tool: "Bash", target: "Bash#2", file: "", key: "Bash#2", ok: true)]
        var inf = s; inf.lastEventAt = -.infinity
        CT.check("a session whose last event time is not finite is working, and the answer does not trap", R.status(now: 1_000_000, sessions: [inf]).lines.isEmpty, false)
        let out = R.recap(awaySince: 0, now: 500_000, sessions: [s])!
        let text = (out.lines + out.facts.map { "\($0.json)" }).joined(separator: "\n")
        CT.check("the recap holds a basename and a count, never a command key", [text.contains("Edit#1"), text.contains("Bash#2")], [false, false])

        CT.section("markdownPlain: the status answer is shown as its words, whatever a file name holds")
        var inline = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        inline.failurePolicy = .returnPartiallyParsedIfPossible
        let answers = ["__init__.py is being edited", "a*b*.txt", "`code`.md", "[x](y).js", "<b>.html", "~~x~~", "#1 notes.md", "back\\slash", "a&amp;b.txt", "1. step.txt", "- dash.txt", "> q.txt", "a|b.txt", "a!b.txt", "icon@2x.png", "me@x.dev wrote", "Codex is not running right now.", "first line\n- item\n# heading\n```"]
        CT.check("shown as the markdown parser would show it, every answer is its own words", answers.map { (try? AttributedString(markdown: SK.markdownPlain($0), options: inline)).map { String($0.characters) } ?? "not parsed" }, answers)
        CT.check("a line that would start a block is escaped at its start", [SK.markdownPlain("- item").hasPrefix("\\-"), SK.markdownPlain("# heading").hasPrefix("\\#"), SK.markdownPlain("1. step").hasPrefix("1\\."), SK.markdownPlain("> q").hasPrefix("\\>")], [true, true, true, true])
        CT.check("an @ is kept as it is: its words stay, and the autolink it can make is inert (only http and https open)", SK.markdownPlain("icon@2x.png"), "icon@2x\\.png")
        CT.finish()
    }
}
