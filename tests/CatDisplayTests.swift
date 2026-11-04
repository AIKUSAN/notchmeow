import Foundation

@main
enum CatDisplayTests {
    typealias D = CatDisplaySettings

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func strings(_ x: Any?) -> [String] { x as! [String] }

    @MainActor static func main() {
        let fx = CT.fixture("display-cases.json")

        CT.section("the frozen words: the display modes, the default pair, the default coats and the limit")
        CT.check("the three modes, One cat first", CatDisplayMode.allCases.map(\.rawValue), strings(fx["modes"]))
        CT.check("the 16 cat IDs are the contract's", CatPresets.ids, strings(fx["ids"]))
        CT.check("the default pair", D.defaultPair, strings(fx["defaultPair"]))
        CT.checkJSON("the default coats: Claude Code Shrimpy, Codex Momo", got: D.defaultAgentCats, want: fx["defaultAgentCats"]!)
        CT.check("at most 256 pills are kept", D.maxAgentCats, fx["maxAgentCats"] as! Int)
        CT.check("the pill-ID rule is the contract's, in words", fx["pillIdPattern"] as! String, "^[a-z][a-z0-9_-]{1,63}$")

        CT.section("a fresh install: One cat, Shrimpy and Momo, no stored agent coats")
        CT.checkJSON("the defaults are the fixture's", got: D().json, want: fx["defaults"]!)
        CT.checkJSON("clean(nothing) is the defaults", got: D.clean(nil).json, want: fx["defaults"]!)

        CT.section("cleanDisplaySettings: \(rows(fx["cases"]).count) stored values, from nothing to a fully valid one")
        var diffs: [String] = []
        for c in rows(fx["cases"]) {
            let d = CT.diffs(D.clean(c["raw"]).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every case comes out as the fixture says", diffs)
        let valid = D.clean(rows(fx["cases"]).first { ($0["name"] as! String) == "a fully valid value" }!["raw"])
        CT.checkJSON("cleaning twice changes nothing", got: D.clean(valid.json).json, want: valid.json)

        CT.section("cleanPair: \(rows(fx["pairs"]).count) stored pairs (a string is JSON text, and not strict JSON is not JSON)")
        diffs = []
        for c in rows(fx["pairs"]) {
            let d = CT.diffs(D.cleanPair(c["raw"]), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every pair comes out as the fixture says", diffs)
        CT.check("bytes that spell a pair are not a pair either: only an array or its text is", D.cleanPair(Data("[\"momo\",\"ginger\"]".utf8)), D.defaultPair)
        CT.check("a byte-order mark before the text is not JSON", D.cleanPair("\u{FEFF}[\"momo\",\"ginger\"]"), D.defaultPair)

        CT.section("cleanAgentCats: \(rows(fx["agentCats"]).count) stored maps")
        diffs = []
        for c in rows(fx["agentCats"]) {
            let d = CT.diffs(D.cleanAgentCats(c["raw"]), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every map comes out as the fixture says", diffs)

        CT.section("pill IDs: \(rows(fx["pillIds"]).count) rows (isPillId, isAgentPill, defaultAgentCat), the whole string and not before a final newline")
        diffs = []
        for r in rows(fx["pillIds"]) {
            let id = r["id"] as! String
            let got: [String: Any] = ["pill": D.isPillId(id), "agent": D.isAgentPill(id), "default": D.defaultAgentCat(id) ?? NSNull()]
            let d = CT.diffs(got, ["pill": r["pill"]!, "agent": r["agent"]!, "default": r["default"] ?? NSNull()])
            if !d.isEmpty { diffs.append("\"\(id)\": \(d.first!)") }
        }
        CT.checkRows("every ID is as the fixture says", diffs)
        CT.checkTrue("a number, nothing and a list are not pill IDs", !D.isPillId(7) && !D.isPillId(nil) && !D.isPillId(["agent_x"]) && !D.isAgentPill(nil) && D.defaultAgentCat(nil) == nil)

        CT.section("the edits of the Settings rows: each changes one thing and returns a clean value")
        let base = D.clean(["displayMode": "two", "pair": ["momo", "ginger"], "agentCats": ["agent_gemini": "latte"]])
        CT.check("the mode", base.withMode(.perAgent), D(mode: .perAgent, pair: ["momo", "ginger"], agentCats: ["agent_gemini": "latte"]))
        CT.check("cat 1 of the pair", base.withPairCat("noodle", slot: 0).pair, ["noodle", "ginger"])
        CT.check("cat 2 of the pair", base.withPairCat("noodle", slot: 1).pair, ["momo", "noodle"])
        CT.check("the same coat for cat 1 and cat 2 makes cat 2 the next coat", base.withPairCat("ginger", slot: 0).pair, ["ginger", "midnight"])
        CT.check("an unknown coat leaves the pair as Shrimpy and Momo", base.withPairCat("tiger", slot: 0).pair, ["shrimpy", "momo"])
        CT.check("a slot that is not 0 or 1 changes nothing", base.withPairCat("noodle", slot: 2).pair, ["momo", "ginger"])
        CT.check("an agent's coat", base.withAgentCat("agent_gemini", "blue").agentCats, ["agent_gemini": "blue"])
        CT.check("an agent that is new", base.withAgentCat("agent_zed", "snow").agentCats, ["agent_gemini": "latte", "agent_zed": "snow"])
        CT.check("a bad coat for an agent with no default is dropped", base.withAgentCat("agent_gemini", "tiger").agentCats, [:])
        CT.check("a bad coat for Codex is its default, Momo", base.withAgentCat("agent_codex", "tiger").agentCats["agent_codex"], "momo")
        CT.check("a name that is not a pill ID is not stored", base.withAgentCat("Not A Pill", "momo").agentCats, ["agent_gemini": "latte"])
        CT.check("the input is never touched", base, D.clean(["displayMode": "two", "pair": ["momo", "ginger"], "agentCats": ["agent_gemini": "latte"]]))

        CT.section("the coat an agent wears: stored, else its default, else the Main cat")
        let wear = D(mode: .perAgent, pair: ["momo", "ginger"], agentCats: ["agent_gemini": "latte", "integration_claude": "oreo"])
        CT.check("a stored coat", wear.catFor(agent: "agent_gemini", main: "snow"), "latte")
        CT.check("a stored coat beats the default", wear.catFor(agent: "integration_claude", main: "snow"), "oreo")
        CT.check("Codex's default, Momo", wear.catFor(agent: "agent_codex", main: "snow"), "momo")
        CT.check("an agent with neither wears the Main cat", wear.catFor(agent: "agent_new", main: "snow"), "snow")
        CT.check("an integration wears the Main cat", wear.catFor(agent: "integration_stripe", main: "snow"), "snow")
        CT.check("and a Main cat that is not a cat is Shrimpy", wear.catFor(agent: "agent_new", main: "tiger"), "shrimpy")

        CT.section("the UserDefaults keys, through a dictionary store")
        let store = MemoryBacking()
        CT.check("an empty store loads the defaults", D.load(from: store), D())
        store.values = ["cat.displayMode": "perAgent", "cat.pair": "[\"noodle\",\"leo\"]", "cat.agentCat.agent_zed": "snow", "cat.agentCat.integration_claude": "oreo", "cat.character": "momo"]
        let loaded = D.load(from: store)
        CT.check("what is stored is loaded (and the other cat keys are not read)", loaded, D(mode: .perAgent, pair: ["noodle", "leo"], agentCats: ["agent_zed": "snow", "integration_claude": "oreo"]))
        let fresh = MemoryBacking()
        loaded.save(to: fresh)
        CT.check("the keys it writes: the mode, the pair as JSON text and one key per agent", fresh.writes, ["cat.displayMode", "cat.pair", "cat.agentCat.agent_zed", "cat.agentCat.integration_claude"])
        CT.check("the pair is stored as strict JSON text", fresh.values["cat.pair"] as? String, "[\"noodle\",\"leo\"]")
        CT.check("and loads back as it was", D.load(from: fresh), loaded)
        let next = loaded.withAgentCat("agent_zed", "puff")
        let before = fresh.writes.count
        next.save(to: fresh, replacing: loaded)
        CT.check("only the key that changed is written", Array(fresh.writes[before...]), ["cat.agentCat.agent_zed"])
        var dropped = next
        dropped.agentCats = [:]
        dropped.save(to: fresh, replacing: next)
        CT.check("an agent that is gone from the map loses its key", Set(fresh.values.keys), ["cat.displayMode", "cat.pair"])

        CT.section("a store that is wrong in every way still loads")
        let wild = MemoryBacking()
        wild.values = ["cat.displayMode": 7, "cat.pair": Data("x".utf8), "cat.agentCat.__proto__": "momo", "cat.agentCat.Bad ID": "momo", "cat.agentCat.agent_x": 7,
                       "cat.agentCat.agent_y": "tiger", "cat.agentCat.integration_claude": "tiger", "cat.agentCat.agent_ok": "momo", "cat.agentCat.": "momo"]
        let tough = D.load(from: wild)
        CT.check("the mode is One cat and the pair Shrimpy and Momo", [tough.mode.rawValue] + tough.pair, ["one", "shrimpy", "momo"])
        CT.checkTrue("Claude Code's bad coat is Shrimpy, agent_ok is kept, and none of the bad IDs and coats are", tough.agentCats["integration_claude"] == "shrimpy" && tough.agentCats["agent_ok"] == "momo" && tough.agentCats["agent_x"] == nil && tough.agentCats["agent_y"] == nil && tough.agentCats.keys.allSatisfy { D.isPillId($0) })
        tough.save(to: wild)
        CT.checkTrue("saving it removes the keys the clean-up refused", !wild.values.keys.contains("cat.agentCat.__proto__") && !wild.values.keys.contains("cat.agentCat.Bad ID") && !wild.values.keys.contains("cat.agentCat.agent_x") && !wild.values.keys.contains("cat.agentCat."))

        CT.section("three hundred stored agents keep the first 256 in code-point order, and the next save drops the rest")
        let crowd = MemoryBacking()
        for i in 0..<300 { crowd.values["cat.agentCat.agent_a\(String(format: "%03d", i))"] = CatPresets.ids[i % 16] }
        let kept = D.load(from: crowd)
        CT.check("256 are kept", kept.agentCats.count, 256)
        CT.checkTrue("agent_a255 is the last one", kept.agentCats["agent_a255"] == CatPresets.ids[255 % 16] && kept.agentCats["agent_a256"] == nil)
        kept.save(to: crowd)
        CT.check("the 44 keys over the limit are removed from the store", crowd.values.keys.filter { $0.hasPrefix("cat.agentCat.") }.count, 256)

        CT.finish()
    }
}
