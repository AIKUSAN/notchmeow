import Foundation

@main
enum CatCastTests {
    typealias C = CatCast

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    /// A JSON number; a boolean, text and null are not numbers (the contract takes them as 0).
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// The fixture's island, in the app's own types: a state that is not one of the eleven is idle, a time that is not a number is 0, and an entry that is not
    /// an object with an ID is skipped (the app never builds one).
    static func pills(_ raw: Any?) -> [C.Pill] {
        (raw as? [Any] ?? []).compactMap { entry in
            guard let t = entry as? [String: Any], let id = t["id"] as? String else { return nil }
            return C.Pill(id: id, state: (t["state"] as? String).flatMap { CatState(rawValue: $0) } ?? .idle, last: number(t["last"]) ?? 0)
        }
    }

    @MainActor static func main() {
        let fx = CT.fixture("cast-cases.json")

        CT.section("the frozen values: the modes, the states, the row and the ranks")
        CT.check("the modes", CatDisplayMode.allCases.map(\.rawValue), fx["modes"] as! [String])
        CT.check("the 11 states", CatState.allCases.map(\.rawValue), fx["states"] as! [String])
        CT.check("the row and the grid hold four", C.pillRow, fx["pillRow"] as! Int)
        var diffs: [String] = []
        for r in rows(fx["busyRank"]) {
            let got = (r["state"] as? String).flatMap { CatState(rawValue: $0) }.map { C.busyRank($0) } ?? 3
            if got != r["rank"] as! Int { diffs.append("\(r["state"]!): \(got)") }
        }
        CT.checkRows("busyRank: waiting for you 0, error 1, busy 2, anything else 3 (a state that is not one is idle)", diffs)

        CT.section("castOf: \(rows(fx["cases"]).count) rows, 44 scenarios, rankings and hostile islands in each of the three modes, and four unknown modes")
        diffs = []
        for c in rows(fx["cases"]) {
            let input = c["input"] as? [String: Any] ?? [:]
            let got = C.of(CatDisplaySettings.modeOf(c["mode"]), tasks: pills(input["tasks"]), focusId: input["focusId"] as? String, mainCat: input["mainCat"], pair: input["pair"], agentCats: input["agentCats"])
            let d = CT.diffs(got.json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!) [\(c["mode"]!)]: \(d.first!)") }
        }
        CT.checkRows("every row comes out as the fixture says", diffs)

        CT.section("a time that is not finite (JSON cannot write it): the pill is as if it had never had an event")
        func two(_ lasts: [Double]) -> String? {
            let ps = lasts.enumerated().map { C.Pill(id: "agent_\(["a", "b", "c"][$0.offset])", state: .working, last: $0.element) }
            return C.of(.two, tasks: [C.Pill(id: "integration_claude", state: .working, last: 5)] + ps, focusId: "integration_claude", mainCat: "shrimpy", pair: nil, agentCats: nil).second?.pill
        }
        CT.check("the most recent of the busy agents is cat 2", two([10, 30, 20]), "agent_b")
        CT.check("NaN is 0: the others win", two([.nan, 3, 2]), "agent_b")
        CT.check("infinity is 0 too (it is not a time)", two([.infinity, 3, 2]), "agent_b")
        CT.check("with all times 0 the first in the app's order wins", two([.nan, .infinity, -.infinity]), "agent_a")

        CT.section("the rules in words")
        let island = [C.Pill(id: "integration_claude", state: .working, last: 100), C.Pill(id: "agent_codex", state: .approval, last: 90), C.Pill(id: "agent_gemini", state: .thinking, last: 95),
                      C.Pill(id: "integration_stripe", state: .idle, last: 1)]
        let r = C.of(.two, tasks: island, focusId: "integration_claude", mainCat: "ginger", pair: ["momo", "latte"], agentCats: nil)
        CT.check("Two cats: cat 1 is the focused pill's, cat 2 the agent that waits for you, and the pair's coats are the cats", [r.big.pill, r.big.cat, r.second?.pill, r.second?.cat], ["integration_claude", "momo", "agent_codex", "latte"])
        CT.check("the second agent leaves the row, and the row wears the Main cat", r.pills.map { "\($0.pill)=\($0.cat)" }, ["agent_gemini=ginger", "integration_stripe=ginger"])
        CT.check("the drop view and the ghost wear the big cat's coat", r.drop, "momo")
        CT.check("the greeting: the Main cat falls in and the pair arrives together", [r.greeting.cat] + (r.greeting.pair ?? []), ["ginger", "momo", "latte"])
        let p = C.of(.perAgent, tasks: island, focusId: "agent_gemini", mainCat: "ginger", pair: nil, agentCats: ["agent_gemini": "snow"])
        CT.check("A cat for each agent: the big cat wears the focused agent's, the row each agent's own and integrations the Main cat", [p.big.cat] + p.pills.map(\.cat), ["snow", "shrimpy", "momo", "ginger"])
        CT.check("and the session cats are the row's cats, with the Main cat for the empty cell", p.greeting.sessions, ["shrimpy", "momo", "ginger", "ginger"])
        let o = C.of(.one, tasks: island, focusId: "agent_gemini", mainCat: "ginger", pair: ["momo", "latte"], agentCats: ["agent_gemini": "snow"])
        CT.check("One cat: the Main cat everywhere, whatever else is stored", [o.big.cat, o.drop] + o.pills.map(\.cat) + o.greeting.sessions, ["ginger", "ginger", "ginger", "ginger", "ginger", "ginger", "ginger", "ginger", "ginger"])
        CT.checkTrue("and no second cat, no pair", o.second == nil && o.greeting.pair == nil)

        CT.section("an island that is wrong in every way never throws and shows nothing twice")
        var bad: [String] = []
        var seed: UInt64 = 3
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        let ids = ["integration_claude", "agent_codex", "agent_gemini", "agent_x", "integration_stripe", "ai_openai", "Bad ID", "__proto__", "", "agent_"]
        for n in 0..<500 {
            let ps = (0..<Int(next() * 9)).map { _ in C.Pill(id: ids[Int(next() * Double(ids.count))], state: CatState.allCases[Int(next() * 11)], last: next() < 0.2 ? .nan : next() * 100) }
            let focus: String? = next() < 0.2 ? nil : ids[Int(next() * Double(ids.count))]
            for mode in CatDisplayMode.allCases {
                let r = C.of(mode, tasks: ps, focusId: focus, mainCat: "tiger", pair: "junk", agentCats: [ids[Int(next() * 4)]: "tiger"])
                let shown = r.pills.map(\.pill) + [r.big.pill, r.second?.pill].compactMap { $0 }
                if r.pills.count > 4 { bad.append("island \(n) \(mode): more than four pills") }
                if Set(r.pills.map(\.pill)).count != r.pills.count { bad.append("island \(n) \(mode): a pill twice in the row") }
                if r.pills.contains(where: { $0.pill == r.big.pill || $0.pill == r.second?.pill }) { bad.append("island \(n) \(mode): a pill in the row and the big spots") }
                if shown.contains(where: { !CatDisplaySettings.isPillId($0) }) { bad.append("island \(n) \(mode): a name that is not a pill ID") }
                if let s = r.second?.pill, !CatDisplaySettings.isAgentPill(s) { bad.append("island \(n) \(mode): an integration is cat 2") }
                if (mode == .two) != (r.second != nil) { bad.append("island \(n) \(mode): cat 2 is there only in Two cats mode") }
                if r.greeting.sessions.count != 4 || !CatPresets.ids.contains(r.big.cat) { bad.append("island \(n) \(mode): not four sessions or not a coat") }
            }
        }
        CT.checkRows("500 islands in each mode", bad)

        CT.finish()
    }
}
