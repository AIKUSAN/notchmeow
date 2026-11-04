import Foundation

// Giving agents their cats (Settings → Cat → Display, A cat for each agent): the coat of an agent pill is the one stored for it, else its default (Claude Code
// is Shrimpy, Codex is Momo), else a coat chosen when the agent is first seen, at random from those no other agent and not the Main cat wears. Port of the
// "Display modes: giving agents their cats" section of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/agent-cat-cases.json pins it,
// including how many random numbers each call draws. Random numbers come in only through `rand`, which the app gives `Double.random(in: 0..<1)` and a test a
// counted seeded source. Foundation only.

enum CatAgentCats {
    /// What `agentCatFor` returns: the coat, the cleaned map (with the pill added when `assigned`), and whether the map gained the pill, which is the cue to
    /// store it and never change it by itself afterwards.
    struct Pick: Equatable {
        var cat: String
        var agentCats: [String: String]
        var assigned: Bool
    }

    /// One coat for a new agent. `taken` lists the cat IDs already in use (a coat used twice is listed twice), `rand` returns 0 up to, not including, 1, and `avoid`
    /// is a coat that is never chosen. A coat nobody uses is chosen at random (`rand` is called once, and only then); when every coat is in use the least-used one
    /// is chosen, ties broken in the 16's order (`rand` is not called). A `rand` that is not a number is 0, one under 0 is the first free coat and one of 1 or more is
    /// the last.
    static func pickCat(taken: [String], rand: () -> Double, avoid: String? = nil) -> String {
        var use: [String: Int] = [:]
        for c in taken { use[c, default: 0] += 1 }
        let pool = CatPresets.ids.filter { $0 != avoid }, free = pool.filter { use[$0] == nil }
        if !free.isEmpty {
            let r = rand(), x = floor(r.isFinite ? r * Double(free.count) : 0)
            return free[Int(min(Double(free.count - 1), max(0, x)))]
        }
        var best = pool[0]
        for c in pool where use[c, default: 0] < use[best, default: 0] { best = c }
        return best
    }

    /// The cat of an agent pill: its stored coat, else its default, else a coat chosen now: random, from those used neither by another agent (a stored one, or a
    /// default that no stored coat has replaced) nor as the Main cat; when all 16 are taken, the least-used (see `pickCat`). A pill that is not an agent pill (an
    /// integration, or an ID that is not a pill ID) gets the Main cat and is never stored.
    static func agentCatFor(_ pillId: String, _ agentCats: [String: String], mainCat: String, rand: () -> Double) -> Pick {
        let map = CatDisplaySettings.cleanAgentCats(agentCats), main = CatSettings.catIdOf(mainCat)
        guard CatDisplaySettings.isAgentPill(pillId) else { return Pick(cat: main, agentCats: map, assigned: false) }
        if let own = map[pillId] { return Pick(cat: own, agentCats: map, assigned: false) }
        if let d = CatDisplaySettings.defaultAgentCat(pillId) { return Pick(cat: d, agentCats: map, assigned: false) }
        let inUse = CatDisplaySettings.defaultAgentCats.merging(map) { _, stored in stored }
        let cat = pickCat(taken: Array(inUse.values) + [main], rand: rand), next = CatDisplaySettings.cleanAgentCats(map.merging([pillId: cat]) { _, new in new })
        return Pick(cat: cat, agentCats: next, assigned: next[pillId] != nil)
    }

    /// The dice button: a new random coat for one agent. Its current coat (stored or default) is never chosen again, and the rest is `agentCatFor`'s rule, with
    /// this agent's own coat set aside. Always stored, a default agent included.
    static func rerollAgentCat(_ pillId: String, _ agentCats: [String: String], mainCat: String, rand: () -> Double) -> (cat: String, agentCats: [String: String]) {
        let map = CatDisplaySettings.cleanAgentCats(agentCats), main = CatSettings.catIdOf(mainCat)
        guard CatDisplaySettings.isAgentPill(pillId) else { return (main, map) }
        var eff = CatDisplaySettings.defaultAgentCats.merging(map) { _, stored in stored }
        let current = eff.removeValue(forKey: pillId)
        let cat = pickCat(taken: Array(eff.values) + [main], rand: rand, avoid: current)
        return (cat, CatDisplaySettings.cleanAgentCats(map.merging([pillId: cat]) { _, new in new }))
    }

    /// `agentCatFor` for each pill in turn (integrations are skipped): the map after every agent has a coat. "Reset to defaults" is this with an empty map.
    static func assignAgentCats(_ pillIds: [String], _ agentCats: [String: String], mainCat: String, rand: () -> Double) -> [String: String] {
        var map = CatDisplaySettings.cleanAgentCats(agentCats)
        for id in pillIds { map = agentCatFor(id, map, mainCat: mainCat, rand: rand).agentCats }
        return map
    }
}
