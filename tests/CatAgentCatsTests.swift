import Foundation

@main
enum CatAgentCatsTests {
    typealias A = CatAgentCats

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func map(_ x: Any?) -> [String: String] { (x as? [String: String]) ?? [:] }

    /// The random source a fixture row names: `{seed: n}` is the contract's seeded generator, `{values: [...]}` those numbers and then 0, and `{none: true}`
    /// must never be called. It counts its draws.
    final class Source {
        var draws = 0, forbidden = false
        private let rng: CatRNG?, values: [Double]?, none: Bool
        init(_ spec: Any?) {
            let s = spec as? [String: Any] ?? [:]
            rng = (s["seed"] as? NSNumber).map { CatRNG(seed: UInt32(truncating: $0)) }
            values = (s["values"] as? [NSNumber])?.map(\.doubleValue)
            none = s["none"] as? Bool ?? false
        }
        func next() -> Double {
            draws += 1
            if none { forbidden = true; return 0 }
            if let rng { return rng.next() }
            if let values { return draws <= values.count ? values[draws - 1] : 0 }
            return 0
        }
    }

    @MainActor static func main() {
        let fx = CT.fixture("agent-cat-cases.json")

        CT.section("the frozen values: the 16 cat IDs and the default coats")
        CT.check("the cat IDs are the contract's", CatPresets.ids, fx["ids"] as! [String])
        CT.checkJSON("the default coats are the fixture's", got: CatDisplaySettings.defaultAgentCats, want: fx["defaults"]!)

        CT.section("agentCatFor: \(rows(fx["cases"]).count) rows, and how many numbers each draws")
        var diffs: [String] = []
        for c in rows(fx["cases"]) {
            let src = Source(c["rand"])
            let got = A.agentCatFor(c["pill"] as! String, map(c["agentCats"]), mainCat: c["mainCat"] as! String, rand: src.next)
            let json: [String: Any] = ["cat": got.cat, "agentCats": got.agentCats, "assigned": got.assigned]
            var d = CT.diffs(json, c["out"]!)
            if src.draws != c["draws"] as! Int { d.append("draws \(src.draws) vs \(c["draws"]!)") }
            if src.forbidden { d.append("rand was called when it must not be") }
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every row is as the fixture says, with the same number of draws", diffs)

        CT.section("rerollAgentCat, the dice: \(rows(fx["rerolls"]).count) rows")
        diffs = []
        for c in rows(fx["rerolls"]) {
            let src = Source(c["rand"])
            let got = A.rerollAgentCat(c["pill"] as! String, map(c["agentCats"]), mainCat: c["mainCat"] as! String, rand: src.next)
            var d = CT.diffs(["cat": got.cat, "agentCats": got.agentCats] as [String: Any], c["out"]!)
            if src.draws != c["draws"] as! Int { d.append("draws \(src.draws) vs \(c["draws"]!)") }
            if src.forbidden { d.append("rand was called when it must not be") }
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every row is as the fixture says", diffs)

        CT.section("assignAgentCats, Reset to defaults and the first launch: \(rows(fx["assigns"]).count) rows")
        diffs = []
        for c in rows(fx["assigns"]) {
            let src = Source(c["rand"])
            let got = A.assignAgentCats((c["pills"] as? [String]) ?? [], map(c["agentCats"]), mainCat: c["mainCat"] as! String, rand: src.next)
            var d = CT.diffs(["agentCats": got] as [String: Any], c["out"]!)
            if src.draws != c["draws"] as! Int { d.append("draws \(src.draws) vs \(c["draws"]!)") }
            if src.forbidden { d.append("rand was called when it must not be") }
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every row is as the fixture says", diffs)

        CT.section("a random source that misbehaves (JSON cannot write NaN or infinity)")
        func first(_ r: Double, taken: [String] = ["shrimpy", "momo"]) -> String { A.pickCat(taken: taken, rand: { r }) }
        CT.check("NaN is the first free coat", first(.nan), "ginger")
        CT.check("infinity is the first free coat", first(.infinity), "ginger")
        CT.check("minus infinity is the first free coat", first(-.infinity), "ginger")
        CT.check("a huge number is the last free coat", first(1e300), "noodle")
        CT.check("a tiny negative number is the first free coat", first(-1e-300), "ginger")
        CT.check("just under 1 is the last free coat", first(0.99999999), "noodle")

        CT.section("the rules the fixture states in words")
        let a = A.agentCatFor("agent_gemini", [:], mainCat: "ginger", rand: { 0 })
        CT.check("a new agent never gets Shrimpy or Momo while Claude Code and Codex are on their defaults, nor the Main cat", [a.cat, a.assigned], ["midnight", true] as [AnyHashable])
        let again = A.agentCatFor("agent_gemini", a.agentCats, mainCat: "ginger", rand: { Double.nan })
        CT.check("and keeps it: asked again it gives the stored coat and draws nothing", [again.cat, again.assigned] as [AnyHashable], [a.cat, false] as [AnyHashable])
        let crowded = Dictionary(uniqueKeysWithValues: CatPresets.ids.dropFirst(2).enumerated().map { ("agent_x\(String(format: "%02d", $0.offset))", $0.element) })
        let full = A.agentCatFor("agent_new", crowded, mainCat: "shrimpy", rand: { fatalError("all 16 are taken: nothing is drawn") })
        CT.check("with all 16 taken the least-used coat is chosen without drawing: Shrimpy (used by Claude Code and the Main cat) is not the least", full.cat, "momo")
        CT.checkTrue("the choice for a new agent is always one of the 16 and is stored", CatPresets.ids.contains(full.cat) && full.assigned)

        CT.section("every call keeps the invariants: a coat from the 16, stored once chosen, never changed by itself, free when one is free")
        var rng = CatRNG(seed: 99), bad: [String] = []
        for round in 0..<2000 {
            var stored: [String: String] = [:]
            for i in 0..<Int(rng.next() * 18) { stored["agent_s\(i)"] = CatPresets.ids[Int(rng.next() * 16)] }
            if rng.next() < 0.3 { stored["integration_claude"] = CatPresets.ids[Int(rng.next() * 16)] }
            let main = CatPresets.ids[Int(rng.next() * 16)], draw = CatRNG(seed: UInt32(round))
            let got = A.agentCatFor("agent_new", stored, mainCat: main, rand: draw.next)
            let used = Set(CatDisplaySettings.defaultAgentCats.merging(stored) { _, s in s }.values).union([main])
            if !CatPresets.ids.contains(got.cat) { bad.append("round \(round): not a coat") }
            if used.count < 16 && used.contains(got.cat) { bad.append("round \(round): \(got.cat) is taken but a coat is free") }
            if got.assigned && got.agentCats["agent_new"] != got.cat { bad.append("round \(round): assigned but not stored") }
            let second = A.agentCatFor("agent_new", got.agentCats, mainCat: main, rand: { fatalError("a stored coat draws nothing") })
            if got.assigned && second.cat != got.cat { bad.append("round \(round): the coat changed by itself") }
            let dice = A.rerollAgentCat("agent_new", got.agentCats, mainCat: main, rand: CatRNG(seed: UInt32(round + 5)).next)
            if dice.cat == got.cat || dice.agentCats["agent_new"] != dice.cat { bad.append("round \(round): the dice gave the same coat or did not store it") }
        }
        CT.checkRows("2000 random islands", bad)

        CT.finish()
    }
}
