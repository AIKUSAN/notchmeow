import Foundation

@main
enum CatRulesTests {
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }

    @MainActor static func main() {
        let seq = CT.fixture("sequence-cases.json"), tools = CT.fixture("search-tools.json")

        CT.section("the work clock earns zoomies after five minutes")
        CT.check("the threshold is five minutes", CatRules.zoomAfterMs, num(seq["zoomAfterMs"]))
        for c in seq["workClock"] as! [[String: Any]] {
            var clock = CatRules.WorkClock()
            var got: [[String: Any]] = []
            for step in c["steps"] as! [[Any]] {
                let t = num(step[0]), st = CatState(rawValue: step[1] as! String)!
                clock = CatRules.workClockStep(clock, state: st, nowMs: t)
                got.append(["tMs": t, "state": st.rawValue, "busySince": clock.busySince.map { $0 as Any } ?? NSNull(), "workedFor": clock.workedFor])
            }
            CT.checkJSON(c["name"] as! String, got: got, want: c["after"]!)
            if let want = c["zoomiesAtFinish"] as? Bool { CT.check("  zoomies at the finish", CatRules.zoomiesOnFinish(workedForMs: clock.workedFor), want) }
        }
        CT.check("the clock stepping backwards never goes negative", CatRules.workClockStep(.init(busySince: 1000), state: .finished, nowMs: 500).workedFor, 0)

        CT.section("only an idle cat sleeps, after ten minutes of quiet")
        let sleep = seq["sleep"] as! [String: Any]
        CT.check("ten minutes", CatRules.sleepAfterMs, num(sleep["afterMs"]))
        var diffs: [String] = []
        for c in sleep["cases"] as! [[String: Any]] {
            let got = CatRules.sleepDelay(state: CatState(rawValue: c["state"] as! String)!, quietMs: num(c["quietMs"]))
            let want = c["delayMs"] as? NSNumber
            if got != want?.doubleValue { diffs.append("\(c["state"]!) quiet \(c["quietMs"]!): \(String(describing: got)) vs \(String(describing: want))") }
        }
        CT.checkRows("\((sleep["cases"] as! [Any]).count) cases, approval and question never sleep", diffs)
        CT.check("a non-finite quiet time counts as 0", CatRules.sleepDelay(state: .idle, quietMs: .nan), CatRules.sleepAfterMs)
        for w in sleep["wake"] as! [[String: Any]] { CT.check("\"\(w["kind"]!)\" wakes: \(w["wakes"]!)", CatRules.wakes(w["kind"] as! String), w["wakes"] as! Bool) }

        CT.section("which collar a stored word means (collar-cases.json `resolve`)")
        let collars = CT.fixture("collar-cases.json")
        CT.check("the four styles, in the contract's order", CatRules.collarStyles, collars["styles"] as! [String])
        var resolveDiffs: [String] = []
        for r in collars["resolve"] as! [[String: Any]] where CatRules.collarStyleOf(r["id"] ?? NSNull()) != r["style"] as! String { resolveDiffs.append("\(r["id"] ?? "null") should be \(r["style"]!)") }
        CT.checkRows("\((collars["resolve"] as! [Any]).count) stored words: an unknown style, a wrong case, a number or null is off", resolveDiffs)
        CT.check("a missing value is off", CatRules.collarStyleOf(nil), "off")

        CT.section("the big cat wears the collar of the agent driving its state, and none when idle, asleep or dizzy")
        let agent = "#E07950"
        for st in CatState.allCases {
            let none = st == .idle || st == .sleeping || st == .dizzy
            CT.check("\(st.rawValue): \(none ? "no collar" : "the agent's colour")", CatRules.bigCatCollar(colour: agent, state: st), none ? nil : agent)
        }
        CT.check("with no agent colour there is nothing to wear", CatRules.bigCatCollar(colour: nil, state: .working), nil)

        CT.section("which tool names mean searching")
        CT.checkJSON("the lists", got: CatRules.searchTools, want: tools["agents"]!)
        for c in tools["cases"] as! [[String: Any]] {
            let name = c["tool"] as! String
            CT.check("\"\(name)\" is \(c["state"]!)", [CatRules.isSearchTool(name) ? "yes" : "no", CatRules.toolState(name).rawValue], [(c["searching"] as! Bool) ? "yes" : "no", c["state"] as! String])
        }
        CT.check("a missing tool name is plain work", CatRules.toolState(nil), CatState.working)

        CT.section("searching in the app (source pins: no test program can run the hook server)")
        let hook = (try? String(contentsOfFile: "NotchBuddy/Sources/App/HookServer.swift", encoding: .utf8)) ?? ""
        /// The text of one `case "…":` of `processEvent`, up to the next case.
        func eventCase(_ name: String) -> String {
            guard let start = hook.range(of: "        case \"\(name)\":") else { return "" }
            let rest = hook[start.upperBound...]
            return String(rest[..<(rest.range(of: "\n        case \"")?.lowerBound ?? rest.endIndex)])
        }
        CT.checkTrue("PreToolUse puts a search tool in the searching state and any other tool in working", eventCase("PreToolUse").contains("state.updateTask(id: agentId, state: BotState(CatRules.toolState(tool)))"))
        CT.checkTrue("PostToolUse does the same with the tool that finished, so the next tool of any other kind puts the cat back to working", eventCase("PostToolUse").contains("BotState(CatRules.toolState(diffTool))"))
        CT.checkTrue("a failed tool is plain work", eventCase("PostToolUseFailure").contains("state: .working") && !eventCase("PostToolUseFailure").contains("toolState"))
        CT.checkTrue("nothing else in the hook server decides between searching and working", hook.components(separatedBy: "CatRules.toolState").count == 3)

        let island = (try? String(contentsOfFile: "NotchBuddy/Sources/App/IslandViewContent.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("a searching agent is still active in the ticker", island.contains("task?.state == .thinking || task?.state == .working || task?.state == .searching"))
        CT.finish()
    }
}
