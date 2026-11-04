import Foundation

@main
enum CatPersonalityTests {
    @MainActor static func main() {
        let want = CT.fixture("personality-cases.json")

        CT.section("the six traits and the six presets")
        let traits = (want["traits"] as! [[String: Any]]).map { ($0["key"] as! String, $0["label"] as! String, $0["low"] as! String, $0["high"] as! String) }
        CT.checkJSON("traits", got: Personality.traits.map { [$0.key, $0.label, $0.low, $0.high] }, want: traits.map { [$0.0, $0.1, $0.2, $0.3] })
        let presets = want["presets"] as! [String: [String: Any]]
        CT.check("preset order", Personality.presets.map { $0.key }, ["balanced", "chill", "grumpy", "sweet", "hyper", "chatty"])
        for p in Personality.presets {
            let w = presets[p.key]!
            CT.checkJSON("preset \(p.key)", got: ["label": p.label, "energy": p.traits.energy, "curiosity": p.traits.curiosity, "chatty": p.traits.chatty,
                                                   "affection": p.traits.affection, "sass": p.traits.sass, "mischief": p.traits.mischief] as [String: Any], want: w)
        }
        CT.check("Balanced is the default personality", CatPersonality(), Personality.named("balanced"))

        CT.section("traits to multipliers and idle habits")
        for c in want["cases"] as! [[String: Any]] {
            CT.checkJSON(c["name"] as! String, got: CT.json(Personality.multipliers(c["traits"] as! [String: Any])), want: c["out"]!)
        }

        CT.section("moving a slider turns the preset into Custom")
        for c in want["slide"] as! [[String: Any]] {
            let out = Personality.slide(Personality.named(c["from"] as! String), trait: c["trait"] as! String, value: (c["value"] as! NSNumber).doubleValue)
            CT.checkJSON("\(c["from"]!) \(c["trait"]!) \(c["value"]!)", got: CT.json(out), want: c["out"]!)
        }

        CT.section("hostile input never leaves 0 to 1, NaN or a wrong type")
        let hostile: [[String: Any]] = [[:], ["energy": 7, "sass": -3], ["energy": "high", "curiosity": NSNull(), "chatty": true, "affection": [1], "sass": [String: Any](), "mischief": "0.9"],
                                        ["energy": Double.nan, "sass": Double.infinity]]
        for h in hostile {
            let p = Personality.sanitized(h)
            let all = [p.energy, p.curiosity, p.chatty, p.affection, p.sass, p.mischief]
            CT.checkTrue("sanitized \(h.keys.sorted()) stays in 0...1", all.allSatisfy { $0 >= 0 && $0 <= 1 && $0.isFinite })
        }
        CT.check("a missing trait counts as 0.5", Personality.sanitized([:]).energy, 0.5)
        CT.check("an unknown preset name gives Balanced", Personality.named("nonsense"), Personality.named("balanced"))
        CT.check("NaN is not a slider value", Personality.slide(Personality.named("chill"), trait: "sass", value: .nan), Personality.named("chill"))
        CT.finish()
    }
}
