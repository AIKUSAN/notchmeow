import Foundation

// The Projects registry's Task 2 pins: the hook events, the registry (its steps, caps and clock edges), the states, the order, the view and its steps,
// replayed against tests/fixtures/projects/ (event-cases, registry-cases, state-cases, order-cases, step-cases), and the rules those fixtures cannot write.
@main
enum ProjectsRegistryTests {
    typealias R = ProjectsRegistry
    typealias S = ProjectsSnapshot
    typealias P = ProjectsRules

    /// A JSON boolean (a CFBoolean), never a number 0 or 1.
    static func isBool(_ x: Any?) -> Bool {
        guard let n = x as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    /// A JSON number that is not a boolean, as Double; nil for anything else.
    static func number(_ x: Any?) -> Double? {
        guard let n = x as? NSNumber, !isBool(n) else { return nil }
        return n.doubleValue
    }

    /// The registry a fixture case builds: its home folder, then each row of `key` (a payload at its time) applied. A row without a payload fails the run (it used to be
    /// skipped, so a renamed key left a case replaying nothing).
    @MainActor
    static func replay(_ c: [String: Any], _ key: String) -> PJRegistry {
        var r = PJRegistry.empty(home: c["home"])
        for row in PJFixtureRows.nested("registry-cases.json/step-cases.json", c, key) {
            guard let p = row["payload"] else {
                CT.checkTrue("\(c["name"] as? String ?? "?"): a row of \(key) has a payload", false)
                continue
            }
            if let e = R.eventFrom(p, now: number(row["at"]) ?? .nan, waitIn: row["waitIn"]) { r = R.apply(r, e) }
        }
        return r
    }

    /// The view a case shows at its time, with its steps, project cats and main cat (an absent or null time reads the newest activity).
    static func viewOf(_ c: [String: Any], _ r: PJRegistry) -> PJView {
        let opts = c["opts"] as? [String: Any] ?? [:]
        return S.view(r, now: number(c["at"]), steps: opts["steps"] as? [String: String] ?? [:],
                      projectCats: opts["projectCats"] as? [String: String] ?? [:], mainCat: opts["mainCat"] as? String)
    }

    /// A session row's typed short form: `label:state`, `:dim` and `:app` when set, then ` +` and the subagent types.
    static func typedRow(_ r: PJSessionRow) -> String {
        var s = "\(r.label):\(r.state)"
        if r.dim { s += ":dim" }
        if r.waitingInApp { s += ":app" }
        if !r.subagents.isEmpty { s += " +" + r.subagents.map { $0.type }.joined(separator: ",") }
        return s
    }

    /// The typed form of a view's projects, as the cases' `expect` lists them.
    static func typedProjects(_ v: PJView) -> [[String: Any]] {
        v.projects.map { p -> [String: Any] in
            ["name": p.name, "state": p.state, "dim": p.dim, "waiting": p.waiting, "sessions": p.sessions.map { typedRow($0) }]
        }
    }

    /// The typed form of a presentation's `expect`: only the keys it names; a key it names that is not one of these fails the run.
    @MainActor
    static func typedPresentation(_ v: PJView, _ want: [String: Any]) -> [String: Any] {
        var got: [String: Any] = [:]
        for key in want.keys {
            switch key {
            case "projects": got[key] = v.projects.count
            case "step": got[key] = v.projects.first?.step ?? ""
            case "host": got[key] = v.projects.first?.host ?? ""
            case "rows": got[key] = v.projects.flatMap { $0.sessions }.map { "\($0.label):\($0.host)" }
            case "state": got[key] = v.projects.first?.state ?? ""
            case "waiting": got[key] = v.projects.first?.waiting ?? 0
            default: CT.checkTrue("presentation expect: the key \(key) is one the test reads", false)
            }
        }
        return got
    }

    /// The order keys of a fixture's `projects` list (a missing state is "", a missing lastAt is 0).
    static func keysOf(_ x: Any?) -> [PJOrderKey] {
        ((x as? [[String: Any]]) ?? []).map {
            PJOrderKey(id: $0["id"] as? String ?? "", state: $0["state"] as? String ?? "", lastAt: number($0["lastAt"]) ?? 0)
        }
    }

    @MainActor
    static func main() {
        CT.section("event-cases.json: eventFrom")
        let events = CT.fixture("event-cases.json", dir: "projects")
        let eventRows = PJFixtureRows.group("event-cases.json", events, "cases", expect: 53, keys: ["name", "payload", "now", "expect"])
        var diffs: [String] = []
        for c in eventRows {
            let got: Any = R.eventFrom(c["payload"], now: number(c["now"]) ?? .nan, waitIn: c["waitIn"])?.json ?? NSNull()
            diffs += CT.diffs(got, c["expect"] ?? NSNull()).map { "\(c["name"] as? String ?? ""): \($0)" }
        }
        CT.checkRows("eventFrom (\(eventRows.count) rows)", diffs)

        CT.section("registry-cases.json, cases: the steps, the views, the notes and the typed short form")
        let reg = CT.fixture("registry-cases.json", dir: "projects")
        let regCases = PJFixtureRows.group("registry-cases.json", reg, "cases", expect: 31, keys: ["name", "home", "steps"])
        let regCaps = PJFixtureRows.group("registry-cases.json", reg, "caps", expect: 8, keys: ["name", "home", "events", "expect"])
        let regPresentation = PJFixtureRows.group("registry-cases.json", reg, "presentation", expect: 7, keys: ["name", "home", "payloads", "view", "expect"])
        // Every step is exactly one of two things: an event to apply (`payload`) or a view to check (`view` with its `expect`). A step that is neither, or both, or a view
        // without its expect, is a renamed key: it fails instead of being skipped. The numbers are the fixture's today (103 and 52: a deliberate change updates them).
        var payloadSteps = 0, viewSteps = 0
        for c in regCases {
            let name = c["name"] as? String ?? ""
            var r = PJRegistry.empty(home: c["home"])
            var d: [String] = []
            for step in PJFixtureRows.nested("registry-cases.json", c, "steps") {
                let at = number(step["at"])
                let hasPayload = step["payload"] != nil, hasView = step["view"] != nil
                if hasPayload == hasView { CT.checkTrue("\(name): a step has a payload or a view, one of them", false) }
                if hasView && step["expect"] == nil { CT.checkTrue("\(name): a step with a view has its expect", false) }
                if hasPayload { payloadSteps += 1 }
                if hasView { viewSteps += 1 }
                if let p = step["payload"], let e = R.eventFrom(p, now: at ?? .nan, waitIn: step["waitIn"]) { r = R.apply(r, e) }
                guard let want = step["view"] else { continue }
                let view = S.view(r, now: at)
                d += CT.diffs(view.json, want)
                if let notes = step["notes"] {
                    // The fixtures list only the rows that carry a note (a row with no note is not in the list).
                    let noted = view.projects.flatMap { $0.sessions }.filter { !$0.note.isEmpty }.map { "\($0.label):\($0.note)" }
                    d += CT.diffs(noted, notes).map { "notes: \($0)" }
                }
                if let typed = step["expect"] {
                    d += CT.diffs(typedProjects(view), typed).map { "typed: \($0)" }
                }
            }
            CT.checkRows(name, d)
        }
        CT.check("registry-cases.json: the cases hold 103 event steps and 52 view steps", [payloadSteps, viewSteps], [103, 52])

        CT.section("registry-cases.json, caps: the caps and the clock's edges")
        for c in regCaps {
            let r = replay(c, "events")
            let want = c["expect"] as? [String: Any] ?? [:]
            var got: [String: Any] = [:]
            for key in want.keys {
                switch key {
                case "sessions":
                    got[key] = r.sessions.map { "\($0.id)#\($0.seq)" }
                case "subagents":
                    var m: [String: [String]] = [:]
                    for sid in (want[key] as? [String: Any] ?? [:]).keys {
                        m[sid] = r.sessions.first { $0.id == sid }?.subagents.map { $0.id } ?? []
                    }
                    got[key] = m
                case "lastAt":
                    var m: [String: Double] = [:]
                    for sid in (want[key] as? [String: Any] ?? [:]).keys {
                        m[sid] = r.sessions.first { $0.id == sid }?.lastAt ?? 0
                    }
                    got[key] = m
                case "nextSeq":
                    got[key] = r.nextSeq
                default:
                    CT.checkTrue("\(c["name"] as? String ?? "?"): the caps expect key \(key) is one the test reads", false)
                }
            }
            CT.checkRows(c["name"] as? String ?? "", CT.diffs(got, want))
        }

        CT.section("registry-cases.json, presentation: the view as the notch shows it")
        for c in regPresentation {
            let view = viewOf(c, replay(c, "payloads"))
            var d = CT.diffs(view.json, c["view"] ?? NSNull())
            d += CT.diffs(typedPresentation(view, c["expect"] as? [String: Any] ?? [:]), c["expect"] ?? NSNull())
            CT.checkRows(c["name"] as? String ?? "", d)
        }

        CT.section("state-cases.json: sessionStateAt, projectStateOf, agoOf")
        let st = CT.fixture("state-cases.json", dir: "projects")
        let stateSessions = PJFixtureRows.group("state-cases.json", st, "sessions", expect: 30, keys: ["name", "session", "expect"])
        let stateProjects = PJFixtureRows.group("state-cases.json", st, "projects", expect: 6, keys: ["name", "states", "expect"])
        let agoRows = PJFixtureRows.group("state-cases.json", st, "agoCases", expect: 5, keys: ["name", "now", "lastAt", "expect"])
        diffs = []
        for c in stateSessions {
            let s = PJSession(json: c["session"] as? [String: Any] ?? [:])
            diffs += CT.diffs(R.sessionStateAt(s, now: number(c["now"])).json, c["expect"] ?? NSNull()).map { "\(c["name"] as? String ?? ""): \($0)" }
        }
        CT.checkRows("sessionStateAt (\(stateSessions.count) rows)", diffs)
        diffs = []
        for c in stateProjects {
            diffs += CT.diffs(P.projectStateOf(c["states"] as? [String] ?? []), c["expect"] ?? NSNull()).map { "\(c["name"] as? String ?? ""): \($0)" }
        }
        CT.checkRows("projectStateOf (\(stateProjects.count) rows)", diffs)
        diffs = []
        for c in agoRows {
            let got = P.agoOf(now: number(c["now"]) ?? .nan, lastAt: number(c["lastAt"]) ?? 0)
            diffs += CT.diffs(got, c["expect"] ?? NSNull()).map { "\(c["name"] as? String ?? ""): \($0)" }
        }
        CT.checkRows("agoOf (\(agoRows.count) rows)", diffs)

        CT.section("order-cases.json: projectOrder, bigCardOf, waitingCount")
        let order = CT.fixture("order-cases.json", dir: "projects")
        let orderOrderRows = PJFixtureRows.group("order-cases.json", order, "order", expect: 4, keys: ["name", "projects", "expect"])
        let bigCardRows = PJFixtureRows.group("order-cases.json", order, "bigCard", expect: 8, keys: ["name", "projects", "pinned", "clicked", "expect"])
        let waitingRows = PJFixtureRows.group("order-cases.json", order, "waiting", expect: 3, keys: ["name", "projects", "expect"])
        diffs = []
        for c in orderOrderRows {
            diffs += CT.diffs(S.projectOrder(keysOf(c["projects"])), c["expect"] ?? NSNull()).map { "\(c["name"] as? String ?? ""): \($0)" }
        }
        CT.checkRows("projectOrder (\(orderOrderRows.count) rows)", diffs)
        diffs = []
        for c in bigCardRows {
            let card = S.bigCardOf(keysOf(c["projects"]), pinned: c["pinned"] as? String, clicked: c["clicked"] as? String)
            diffs += CT.diffs(card.json, c["expect"] ?? NSNull()).map { "\(c["name"] as? String ?? ""): \($0)" }
        }
        CT.checkRows("bigCardOf (\(bigCardRows.count) rows)", diffs)
        diffs = []
        for c in waitingRows {
            let counts = ((c["projects"] as? [[String: Any]]) ?? []).map { S.wholeCount($0["waiting"]) }
            diffs += CT.diffs(S.waitingCount(counts), c["expect"] ?? NSNull()).map { "\(c["name"] as? String ?? ""): \($0)" }
        }
        CT.checkRows("waitingCount (\(waitingRows.count) rows)", diffs)

        CT.section("step-cases.json, views: the view with the steps")
        let sc = CT.fixture("step-cases.json", dir: "projects")
        for c in PJFixtureRows.group("step-cases.json", sc, "views", expect: 1, keys: ["name", "home", "payloads", "view"]) {
            CT.checkRows(c["name"] as? String ?? "", CT.diffs(viewOf(c, replay(c, "payloads")).json, c["view"] ?? NSNull()))
        }

        CT.section("what the fixtures cannot write")
        let base = 1_760_000_000_000.0
        let payload: [String: Any] = ["hook_event_name": "UserPromptSubmit", "session_id": "s1", "cwd": "/Users/sam/Code/a"]
        let r0 = PJRegistry.empty(home: "/Users/sam")
        let r1 = R.eventFrom(payload, now: base).map { R.apply(r0, $0) } ?? r0
        CT.check("one prompt makes one session", r1.sessions.count, 1)
        for x in [Double.nan, Double.infinity] {
            let got = R.apply(r1, PJEvent(at: x, agent: "claude", kind: "prompt", sessionId: "s1"))
            CT.checkTrue("an event at \(x) prunes nothing and keeps lastAt", got.sessions.count == 1 && got.sessions[0].lastAt == base)
        }
        CT.checkTrue("eventFrom gives nothing at a time that is not finite",
                     R.eventFrom(payload, now: Double.nan) == nil && R.eventFrom(payload, now: Double.infinity) == nil)
        let working: [String: Any] = ["state": "working", "dim": false, "gone": false, "waitingInApp": false]
        CT.checkJSON("sessionStateAt at infinity reads the session's own lastAt", got: R.sessionStateAt(r1.sessions[0], now: Double.infinity).json, want: working)
        CT.checkJSON("sessionStateAt at nan reads the session's own lastAt", got: R.sessionStateAt(r1.sessions[0], now: Double.nan).json, want: working)
        let before = r1
        let afterStop = R.apply(r1, PJEvent(at: base + 1_000, agent: "claude", kind: "stop", sessionId: "s1"))
        CT.checkTrue("apply changes only its copy", r1 == before && r1.sessions[0].run == "working" && afterStop.sessions[0].run == "finished")
        let numericId: [String: Any] = ["hook_event_name": "UserPromptSubmit", "session_id": 7, "cwd": "/Users/sam/Code/a"]
        CT.checkTrue("a session_id that is a number is no session", R.eventFrom(numericId, now: base) == nil)
        let codexPayload: [String: Any] = ["nm_agent": "codex", "hook_event_name": "PreToolUse", "session_id": "x", "cwd": "/Users/sam/Code/c"]
        let codex = R.eventFrom(codexPayload, now: base)
        let rc = codex.map { R.apply(r0, $0) } ?? r0
        CT.checkTrue("Codex sets otherAgentSeen and makes no session", codex?.kind == "other" && rc.otherAgentSeen && rc.sessions.isEmpty)

        CT.section("Swift-port hardening (not in shared/projects-core.js): a hostile cwd and a flood of asks are capped")
        let longCwd = "/Users/sam/Code/" + String(repeating: "x", count: 5000 - 16)
        CT.check("the hostile cwd is 5000 bytes", longCwd.utf8.count, 5000)
        let hostile = R.eventFrom(["hook_event_name": "UserPromptSubmit", "session_id": "h1", "cwd": longCwd], now: base)
        CT.check("a cwd over 4096 bytes is read as none", hostile?.cwd.isEmpty, true)   // (booleans: a failing run would print 5000 bytes)
        CT.check("so an event that starts a session from it starts nothing", hostile.map { R.apply(r0, $0).sessions.count }, 0)
        let hostileAsk = R.eventFrom(["hook_event_name": "PermissionRequest", "session_id": "h2", "cwd": longCwd, "tool_name": "Bash"], now: base)
        let askedAt = hostileAsk.map { R.apply(r0, $0) } ?? r0
        CT.check("a first-seen approval with such a cwd files under home, as one with no cwd does", askedAt.sessions.map { $0.root == "/Users/sam" && $0.cwd == "/Users/sam" }, [true])
        let exact = "/Users/sam/Code/" + String(repeating: "y", count: 4096 - 16)
        CT.check("a cwd of exactly 4096 bytes is kept", R.eventFrom(["hook_event_name": "UserPromptSubmit", "session_id": "h3", "cwd": exact], now: base)?.cwd == exact, true)
        var flood = r1
        for i in 0..<50 {
            let ask = R.eventFrom(["hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/Users/sam/Code/a", "agent_id": "sub-\(i)", "tool_name": "Bash"], now: base + 1_000 + Double(i))
            if let ask { flood = R.apply(flood, ask) }
        }
        CT.check("50 asks from distinct agent_ids keep at most 16 pending", flood.sessions[0].pending.count, 16)
        CT.check("and they are the newest 16 (sub-34 to sub-49)", flood.sessions[0].pending.map { $0.by }, (34..<50).map { "sub-\($0)" })
        let rep = R.eventFrom(["hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/Users/sam/Code/a", "agent_id": "sub-40", "tool_name": "Bash"], now: base + 2_000).map { R.apply(flood, $0) } ?? flood
        CT.check("an ask from one of them again replaces its own and moves it last, the count unchanged", [rep.sessions[0].pending.count, rep.sessions[0].pending.last?.by == "sub-40" ? 1 : 0], [16, 1])

        CT.section("copies of the app's values: the registry's literals are the hook server's")
        CT.check("claudeAppTag is HookOrigin.desktopTag (the relays' tag for a session from the Claude app)", R.claudeAppTag, HookOrigin.desktopTag)
        CT.check("cursorBundle is HookOrigin.cursorBundleId", R.cursorBundle, HookOrigin.cursorBundleId)
        // BotState is in IslandTypes.swift with the island's other types, which no test program compiles alone; its cases are read as source text (comments removed).
        let islandTypes = (try? String(contentsOfFile: "NotchBuddy/Sources/App/IslandTypes.swift", encoding: .utf8)) ?? ""
        let botStates = SourceScan.enumCases("BotState", in: SourceScan.code(islandTypes)) ?? []
        CT.checkTrue("IslandTypes.swift is read and BotState's cases are found (\(botStates.count))", botStates.contains("idle") && botStates.contains("approval") && botStates.count >= P.states.count)
        CT.check("every project state word (ProjectsRules.states) is a BotState raw value, so the big cat can show it", P.states.filter { !botStates.contains($0) }, [])

        CT.finish()
    }
}
