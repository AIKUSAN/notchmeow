import Foundation

@main
enum CatKittenHooksTests {
    typealias K = CatKittens
    typealias H = CatKittenHooks

    static func dict(_ x: Any?) -> [String: Any] { x as? [String: Any] ?? [:] }
    static func shown(_ list: [K.Kitten]) -> [String] { list.map { "\($0.id):\($0.state.rawValue)" } }

    /// What the hook server does with one payload: a permission request goes to `permission`, every other event to `event`, and an event that carries no kitten event
    /// changes nothing (not even a tick).
    static func apply(_ list: [K.Kitten], _ payload: [String: Any], at t: Double) -> [K.Kitten] {
        let name = payload["hook_event_name"] as? String ?? ""
        let ev = name == "PermissionRequest" ? H.permission(payload: payload, now: t) : H.event(name: name, payload: payload, now: t)
        return ev.map { K.step(list, $0) } ?? list
    }

    @MainActor static func main() {
        CT.section("the hooks' words: which events carry a kitten event, and which are the parent's own")
        let start = H.event(name: "SubagentStart", payload: ["agent_id": "a1", "agent_type": "Explore", "session_id": "S1"], now: 7)
        CT.check("SubagentStart with an agent_id adds a kitten, with its type and session", [start?.kind.rawValue, start?.id, start?.agentType, start?.session], ["start", "a1", "Explore", "S1"])
        CT.check("the session can be a conversation_id", H.event(name: "SubagentStart", payload: ["agent_id": "a1", "conversation_id": "C9"], now: 0)?.session, "C9")
        CT.check("SubagentStop", H.event(name: "SubagentStop", payload: ["agent_id": "a1"], now: 1)?.kind, .stop)
        for name in ["PreToolUse", "PostToolUse"] {
            let ev = H.event(name: name, payload: ["agent_id": "a1", "tool_name": "Grep"], now: 2)
            CT.check("\(name) with an agent_id sets the kitten's state from the tool", [ev?.kind.rawValue, ev?.id, ev?.tool], ["tool", "a1", "Grep"])
            CT.checkTrue("\(name) without one is the parent's own event", H.event(name: name, payload: ["tool_name": "Grep"], now: 2) == nil)
        }
        CT.check("a permission request from a subagent", H.permission(payload: ["agent_id": "a1"], now: 3)?.kind, .permission)
        CT.checkTrue("a permission request from the parent is not a kitten event", H.permission(payload: ["tool_name": "Bash"], now: 3) == nil)
        CT.check("a request answered is the kitten back to work", H.resolved(subagentId: "a1", now: 4).kind, .resolved)
        for name in ["Stop", "StopFailure", "SessionEnd", "Interrupt"] {
            CT.check("\(name) of the parent takes its session's kittens", [H.event(name: name, payload: ["session_id": "S1"], now: 5)?.kind.rawValue, H.event(name: name, payload: ["session_id": "S1"], now: 5)?.session], ["end", "S1"])
        }
        CT.check("a Stop with no session takes every kitten", H.event(name: "Stop", payload: [:], now: 5)?.session, nil)
        CT.checkTrue("a Stop that names a subagent is not the parent's", H.event(name: "Stop", payload: ["agent_id": "a1"], now: 5) == nil)
        for name in ["SessionStart", "UserPromptSubmit", "Notification", "PostToolUseFailure", "SomethingNew", ""] {
            CT.checkTrue("\(name.isEmpty ? "an unnamed event" : name) is no kitten event", H.event(name: name, payload: ["agent_id": "a1"], now: 6) == nil)
        }

        CT.section("an agent_id that is not one: not text, empty, or longer than 128 characters is the parent's own")
        for (label, v) in [("a number", 7 as Any), ("null", NSNull()), ("an empty string", ""), ("a list", ["a"]), ("129 characters", String(repeating: "x", count: 129))] {
            CT.checkTrue("\(label): SubagentStart, a tool event, a permission request and a stop make no kitten event", H.event(name: "SubagentStart", payload: ["agent_id": v], now: 1) == nil && H.event(name: "PreToolUse", payload: ["agent_id": v], now: 1) == nil && H.permission(payload: ["agent_id": v], now: 1) == nil && H.event(name: "SubagentStop", payload: ["agent_id": v], now: 1) == nil)
        }
        CT.check("128 characters is an ID", H.subagentId(["agent_id": String(repeating: "x", count: 128)])?.count, 128)
        CT.check("a type that is not text is no type", H.event(name: "SubagentStart", payload: ["agent_id": "a", "agent_type": 7], now: 1)?.agentType, nil)

        guard let dir = ProcessInfo.processInfo.environment["NM_KITTEN_RECEIVED"] else { print("NM_KITTEN_RECEIVED is not set: run this through scripts/test-cat-kitten-hooks.sh"); exit(2) }
        let data = CT.fixtureURL("subagent-scenarios.json", dir: "mac")
        let fx = try! JSONSerialization.jsonObject(with: Data(contentsOf: data)) as! [String: Any]
        let common = dict(fx["common"]), scenarios = dict(fx["scenarios"])

        CT.section("the scripted events, through a socket and back: \(scenarios.count) scenarios, each step's list and, after a farewell, what is drawn")
        for name in scenarios.keys.sorted() {
            let steps = dict(scenarios[name])["steps"] as! [[String: Any]]
            let text = (try? String(contentsOfFile: dir + "/\(name).jsonl", encoding: .utf8)) ?? ""
            var received = text.split(separator: "\n").map { dict(try? JSONSerialization.jsonObject(with: Data($0.utf8))) }.makeIterator()
            var list: [K.Kitten] = [], problems: [String] = []
            for (n, step) in steps.enumerated() {
                let at = (step["at"] as! NSNumber).doubleValue
                if let sent = step["event"] as? [String: Any] {
                    guard let got = received.next() else { problems.append("step \(n + 1): the socket received nothing"); break }
                    let want = common.merging(sent) { _, s in s }
                    if !CT.diffs(got, want).isEmpty { problems.append("step \(n + 1): the socket received \(got) and not \(want)"); break }
                    list = apply(list, got, at: at)
                } else if let inner = step["internal"] as? [String: Any] {
                    switch inner["type"] as? String {
                    case "resolved": list = K.step(list, H.resolved(subagentId: inner["id"] as! String, now: at))
                    case "sweep": list = K.step(list, .sweep(t: at))
                    default: list = K.step(list, .tick(t: at))
                    }
                }
                if shown(list) != step["kittens"] as! [String] { problems.append("step \(n + 1) (\(step["say"]!)): \(shown(list)) and not \(step["kittens"]!)") }
                if let view = step["view"] as? [String], let after = step["viewAt"] as? NSNumber, shown(K.view(list, now: at + after.doubleValue)) != view {
                    problems.append("step \(n + 1): \(after) ms later \(shown(K.view(list, now: at + after.doubleValue))) is drawn and not \(view)")
                }
            }
            if received.next() != nil { problems.append("the socket received more than the scenario has") }
            CT.checkRows("\(name): \(steps.count) steps, \(text.split(separator: "\n").count) events sent", problems)
        }

        CT.section("the farewell needs no timer: the view hides the kitten when its time is up, and the next event of any kind drops it")
        var l = apply([], ["hook_event_name": "SubagentStart", "agent_id": "a1"], at: 0)
        l = apply(l, ["hook_event_name": "SubagentStop", "agent_id": "a1"], at: 100)
        CT.check("at 699 ms it is still waving, at 700 it is gone from the view, and it is still in the list", [K.view(l, now: 699).count, K.view(l, now: 700).count, l.count], [1, 0, 1])
        CT.check("a tool event of the parent does not touch the list (no kitten event), a start does", [apply(l, ["hook_event_name": "PreToolUse", "tool_name": "Edit"], at: 900).count, apply(l, ["hook_event_name": "SubagentStart", "agent_id": "a2"], at: 900).count], [1, 1])

        CT.finish()
    }
}
