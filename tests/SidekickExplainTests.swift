import Foundation

// The risk rules against tests/fixtures/sidekick/explain-cases.json, and what the fixture cannot write (a tool that is not text, an input that is not an object, a huge command, a
// fuzz of hostile text that must never throw and never leak a command, a path or an argument into a line). Run through scripts/test-sidekick-explain.sh.

@main
enum SidekickExplainTests {
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    @MainActor static func main() {
        let fx = CT.fixture("explain-cases.json", dir: "sidekick")

        CT.section("the frozen reasons: \(rows(fx["reasons"]).count) ids with their risk and their line, in the contract's order")
        let want = rows(fx["reasons"]).map { "\($0["id"] as! String)|\($0["risk"] as! String)|\($0["line"] as! String)" }
        CT.check("the table is the contract's", SidekickExplain.reasons.map { "\($0.id)|\($0.risk)|\($0.line)" }, want)

        let cases = rows(fx["cases"])
        CT.section("explain: \(cases.count) cases, risk, reason, line and target each")
        var diffs: [String] = []
        for c in cases {
            let got = SidekickExplain.explain(agent: c["agent"] as? String, tool: c["tool"], input: c["input"], cwd: c["cwd"], home: c["home"])
            let w = SKExplanation(risk: c["risk"] as! String, reasonId: c["reasonId"] as! String, line: c["line"] as! String, target: c["target"] as? String ?? "")
            if got != w { diffs.append("\(c["name"] as! String): got \(got.risk)/\(got.reasonId) \"\(got.line)\" [\(got.target)], want \(w.risk)/\(w.reasonId) \"\(w.line)\" [\(w.target)]") }
        }
        CT.checkRows("every case gives the fixture's answer", diffs)

        CT.section("what the fixture cannot write")
        func e(_ tool: Any?, _ input: Any?, cwd: Any? = "/Users/me/proj", home: Any? = "/Users/me") -> SKExplanation { SidekickExplain.explain(tool: tool, input: input, cwd: cwd, home: home) }
        CT.check("a tool that is not text is no tool", e(42, ["command": "ls"]).reasonId, "unsure")
        CT.check("a missing tool is no tool", e(nil, nil).reasonId, "unsure")
        CT.check("a command that is not text or a list of text is unsure", e("Bash", ["command": 7]).reasonId, "unsure")
        CT.check("an input that is a list is no input", e("Bash", ["rm", "-rf", "/"]).reasonId, "unsure")
        CT.check("a command of 20,001 characters is not read: unsure", e("Bash", ["command": "sudo " + String(repeating: "a", count: 20001)]).reasonId, "unsure")
        CT.check("a command of 20,000 characters is still read", e("Bash", ["command": "sudo " + String(repeating: "a", count: 19995)]).reasonId, "sudo")
        CT.check("no cwd, no home: a relative path is inside", e("Edit", ["file_path": "a.txt"], cwd: nil, home: nil).reasonId, "edit_in_project")
        CT.check("an absolute path with no cwd is unsure for a write", e("Edit", ["file_path": "/etc/hosts"], cwd: nil, home: nil).reasonId, "unsure")

        CT.section("a fuzz of hostile text: never a throw, always a known reason, never the marker in the line")
        let marker = "ZZ-SECRET-MARKER-9137"
        let pieces = ["rm", "-rf", "sudo", "git", "push", "--force", "|", "&&", ";", "$(", "`", "'", "\"", "<<", ">", "2>&1", "~", "/", "..", ".env", marker, "\\", "\n", "curl", "sh", "-c", "bash", "(", ")", "{", "}", "*", "xargs", "env", "FOO=1", "\u{202E}", "é", "😀"]
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        var bad: [String] = []
        for _ in 0..<3000 {
            let n = 1 + next() % 12
            let cmd = (0..<n).map { _ in pieces[next() % pieces.count] }.joined(separator: next() % 3 == 0 ? "" : " ")
            let r = e("Bash", ["command": cmd])
            let known = SidekickExplain.reasons.contains { $0.id == r.reasonId }
            if !known { bad.append("unknown reason for \(cmd.debugDescription)") }
            if r.line.contains(marker) && !r.target.contains(marker) { bad.append("the marker leaked into a line: \(cmd.debugDescription)") }
            if r.line.contains("/") || r.line.contains("`") || r.line.contains("\n") { bad.append("a path or a command char in the line: \(r.line.debugDescription)") }
        }
        CT.checkRows("3000 random commands", bad)
        CT.finish()
    }
}
