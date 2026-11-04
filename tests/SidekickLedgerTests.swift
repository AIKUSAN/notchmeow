import Foundation

// The hook adapter and the ledger against tests/fixtures/sidekick/hook-cases.json (every payload gives the event it records, every sequence the ledger it records), the command key's
// pinned values, and what the fixture cannot write: a time that is not finite, a ledger that is never changed by the call, and a marker planted in every input that must never come out.
// Run through scripts/test-sidekick-ledger.sh.

@main
enum SidekickLedgerTests {
    typealias L = SidekickLedger
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func number(_ v: Any?) -> Double? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }; return n.doubleValue }

    @MainActor static func main() {
        let fx = CT.fixture("hook-cases.json", dir: "sidekick")

        CT.section("the command key: FNV-1a over canonical JSON, pinned")
        CT.check("fnv1a of nothing", SK.fnv1a(""), "811c9dc5")
        CT.check("fnv1a of a", SK.fnv1a("a"), "e40c292c")
        CT.check("a command", SK.commandKey(tool: "Bash", input: ["command": "ls -la"]), "Bash#d3abe9d5")
        CT.check("extra spaces in a command do not make another step", SK.commandKey(tool: "Bash", input: ["command": "  ls   -la "]), "Bash#d3abe9d5")
        CT.check("no input at all", SK.commandKey(tool: "X", input: nil), "X#77074ba4")
        CT.check("lists, text with an accent, null and a boolean", SK.commandKey(tool: "X", input: ["x": [1, "é", NSNull(), true] as [Any], "file_path": "/a"] as [String: Any]), "X#63e27ca3")
        CT.check("key order does not matter", SK.commandKey(tool: "X", input: ["a": 1, "b": 2]), SK.commandKey(tool: "X", input: ["b": 2, "a": 1]))
        CT.checkTrue("the tool is part of the key", SK.commandKey(tool: "Bash", input: ["command": "ls"]) != SK.commandKey(tool: "Read", input: ["command": "ls"]))

        let cases = rows(fx["cases"])
        CT.section("eventFrom: \(cases.count) payloads, the event each one records")
        var diffs: [String] = []
        for c in cases {
            let name = c["name"] as! String
            let opts = c["opts"] as? [String: Any]
            let got: Any
            if let now = number(c["now"]) { got = L.eventFrom(c["payload"], now: now, codex: opts?["codex"] as? Bool ?? true)?.json ?? NSNull() } else { got = NSNull() }
            let d = CT.diffs(got, c["event"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(name): \(d.first!)") }
        }
        CT.checkRows("every payload gives its event", diffs)

        let seqs = rows(fx["sequences"])
        CT.section("ledgerApply: \(seqs.count) sequences, the ledger each one ends with")
        diffs = []
        for s in seqs {
            var ledger = SKLedger()
            for st in rows(s["steps"]) {
                let at = number(st["at"])!
                if let a = st["answered"] as? [String: Any] { ledger = L.apply(ledger, L.approvalAnswered(agentId: a["agentId"] as! String, sessionId: a["sessionId"] as! String, now: at)) }
                else if let ev = L.eventFrom(st["payload"], now: at, codex: (st["opts"] as? [String: Any])?["codex"] as? Bool ?? true) { ledger = L.apply(ledger, ev) }
            }
            let d = CT.diffs(ledger.json, s["ledger"]!)
            if !d.isEmpty { diffs.append("\(s["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every sequence ends with its ledger", diffs)

        CT.section("what the fixture cannot write")
        let start = L.eventFrom(["hook_event_name": "SessionStart", "session_id": "S", "cwd": "/a/b"], now: 1000)!
        CT.check("a time that is not finite gives no event", [L.eventFrom(["hook_event_name": "Stop"], now: .nan) == nil, L.eventFrom(["hook_event_name": "Stop"], now: .infinity) == nil], [true, true])
        let ledger1 = L.apply(SKLedger(), start)
        CT.check("an event with a time that is not finite changes nothing", L.apply(ledger1, SKEvent(at: .nan, agentId: "integration_claude", sessionId: "S", kind: "stop")), ledger1)
        let before = ledger1
        _ = L.apply(ledger1, SKEvent(at: 2000, agentId: "integration_claude", sessionId: "S", kind: "prompt"))
        CT.check("the ledger it is given is not changed", ledger1, before)
        CT.check("a session id of a million characters is kept to 128 code points", L.eventFrom(["hook_event_name": "Stop", "session_id": String(repeating: "x", count: 1_000_000)], now: 1)!.sessionId.unicodeScalars.count, 128)
        CT.check("a payload with no object is nothing", [L.eventFrom(nil, now: 1) == nil, L.eventFrom("Stop", now: 1) == nil, L.eventFrom([1, 2], now: 1) == nil], [true, true, true])
        var deep: Any = "x"
        for _ in 0..<5000 { deep = ["a": deep] }
        CT.check("an input nested 5000 deep gives a fixed key, not a crash", SK.commandKey(tool: "Bash", input: ["command": deep]), "Bash#too-deep")

        CT.section("nothing secret reaches an event or the ledger")
        let secrets = ["SECRET-PROMPT", "SECRET-OUTPUT", "SECRET-MSG", "SECRET-CONTENT", "SECRET-DIR", "SECRET-CMD", "SECRET-TRANSCRIPT"]
        func hook(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] { var p: [String: Any] = ["hook_event_name": name, "session_id": "S1", "cwd": "/Users/\(secrets[4])/proj"]; for (k, v) in extra { p[k] = v }; return p }
        let payloads: [[String: Any]] = [
            hook("UserPromptSubmit", ["prompt": secrets[0], "transcript_path": "/Users/me/.claude/\(secrets[6]).jsonl"]),
            hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "echo \(secrets[5])"], "tool_response": ["stdout": secrets[1]]]),
            hook("PostToolUse", ["tool_name": "Write", "tool_input": ["file_path": "/Users/\(secrets[4])/proj/a.js", "content": secrets[3]]]),
            hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "curl https://\(secrets[5])"]]),
            hook("Stop", ["last_assistant_message": secrets[2]]),
        ]
        var l = SKLedger()
        for (i, p) in payloads.enumerated() { l = L.apply(l, L.eventFrom(p, now: 9_000_000 + Double(i) * 1000)!) }
        let text = String(data: try! JSONSerialization.data(withJSONObject: l.json), encoding: .utf8)!
        CT.check("no marker is in the ledger", secrets.filter { text.contains($0) }, [])
        CT.finish()
    }
}
