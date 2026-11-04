import Foundation

// Which cat appears where (the "cast"): a cat stands for an agent's pill, the big cat shows the focused pill, and `CatCast.of` says, for the chosen display mode,
// which coat each place wears. Port of the "Display modes: which cat appears where" section of design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/cast-cases.json pins it. It reads stored coats and defaults only and never draws a random number: an agent with neither wears the Main cat
// until `CatAgentCats.agentCatFor` has given it a coat, which the app does when it first sees the agent. Foundation only.
//   one:      the Main cat everywhere.
//   perAgent: the focused agent's cat is the big cat (the Main cat when the focus is an integration or nothing); every agent pill wears its agent's cat;
//             integration pills wear the Main cat.
//   two:      the pair: cat 1 is the big cat and shows the focused pill, cat 2 shows the busiest other agent; pills wear the Main cat.

enum CatCast {
    /// The most pills the row and the 2x2 grid hold (`others.prefix(4)`).
    static let pillRow = 4

    /// One pill of the island, in the app's own order: its ID, the state its cat shows, and the time of its last event (ms, any one clock; not a number is 0).
    struct Pill: Equatable {
        var id: String
        var state: CatState
        var last: Double
    }
    /// The coat a place wears and the pill it shows (nil: none, for the big cat when nothing is focused, and for cat 2 when there is no other agent).
    struct Spot: Equatable { var pill: String?; var cat: String }
    struct PillCat: Equatable { var pill: String; var cat: String }
    /// The launch greeting: `cat` falls in (the Main cat in every mode), `pair` is nil or, in Two cats mode, the pair that arrives together, and `sessions` are
    /// the four session cats in the grid's cell order (top left, top right, bottom left, bottom right).
    struct Greeting: Equatable { var cat: String; var pair: [String]?; var sessions: [String] }

    /// `big`: the big cat, compact or expanded. `second`: nil, or in Two cats mode pair cat 2 and the busiest other agent. `pills`: the row and the 2x2 grid, the
    /// tasks other than the focused one (and, in Two cats mode, other than cat 2's), the first four, in the app's order. `drop`: the drop view's and the drag ghost's coat,
    /// the big cat's.
    struct Result: Equatable {
        var mode: CatDisplayMode
        var big: Spot
        var second: Spot?
        var pills: [PillCat]
        var drop: String
        var greeting: Greeting

        /// As the fixtures hold it, a JSON-shaped dictionary.
        var json: [String: Any] {
            func spot(_ s: Spot) -> [String: Any] { ["pill": s.pill ?? NSNull(), "cat": s.cat] }
            return ["mode": mode.rawValue, "big": spot(big), "second": second.map(spot) ?? NSNull(), "pills": pills.map { ["pill": $0.pill, "cat": $0.cat] },
                    "drop": drop, "greeting": ["cat": greeting.cat, "pair": greeting.pair ?? NSNull(), "sessions": greeting.sessions] as [String: Any]]
        }
    }

    /// How busy an agent is, for the busiest-other rule: 0 waits for you (an approval or a question), 1 an error, 2 working, thinking or searching, 3 anything else.
    static func busyRank(_ s: CatState) -> Int {
        s == .approval || s == .question ? 0 : s == .error ? 1 : s.isBusy ? 2 : 3
    }

    /// The cast of one mode. `tasks` are the island's pills in the app's order (an ID that is not a pill ID is skipped, and a pill listed twice counts once),
    /// `focusId` the focused pill, `mainCat`, `pair` and `agentCats` as stored (they are cleaned here, so a raw value is fine). The busiest other agent (Two cats mode)
    /// is the agent pill other than the focused one that ranks first by `busyRank`, then by the most recent `last`, then by its place in `tasks`; an integration is
    /// never chosen, and with no other agent pill `second.pill` is nil (cat 2 idles, with no badge).
    static func of(_ mode: CatDisplayMode, tasks: [Pill], focusId: String?, mainCat: Any?, pair: Any?, agentCats: Any?) -> Result {
        let main = CatSettings.catIdOf(mainCat), pr = CatDisplaySettings.cleanPair(pair), map = CatDisplaySettings.cleanAgentCats(agentCats)
        var seen = Set<String>(), list: [Pill] = []
        for t in tasks where CatDisplaySettings.isPillId(t.id) && !seen.contains(t.id) {
            seen.insert(t.id)
            list.append(Pill(id: t.id, state: t.state, last: t.last.isFinite ? t.last : 0))
        }
        let focus = focusId.flatMap { CatDisplaySettings.isPillId($0) ? $0 : nil }
        func catOf(_ id: String?) -> String {
            guard mode == .perAgent, let id, CatDisplaySettings.isAgentPill(id) else { return main }
            return map[id] ?? CatDisplaySettings.defaultAgentCat(id) ?? main
        }
        let big = Spot(pill: focus, cat: mode == .two ? pr[0] : catOf(focus))
        var second: Spot?
        if mode == .two {
            var best: (id: String, rank: Int, last: Double, at: Int)?
            for (i, t) in list.enumerated() where t.id != focus && CatDisplaySettings.isAgentPill(t.id) {
                let rank = busyRank(t.state)
                if let b = best, !(rank < b.rank || (rank == b.rank && (t.last > b.last || (t.last == b.last && i < b.at)))) { continue }
                best = (t.id, rank, t.last, i)
            }
            second = Spot(pill: best?.id, cat: pr[1])
        }
        let pills = list.filter { $0.id != focus && $0.id != second?.pill }.prefix(pillRow).map { PillCat(pill: $0.id, cat: catOf($0.id)) }
        let sessions = (0..<4).map { pills.indices.contains($0) ? pills[$0].cat : main }
        return Result(mode: mode, big: big, second: second, pills: Array(pills), drop: big.cat,
                      greeting: Greeting(cat: main, pair: mode == .two ? pr : nil, sessions: sessions))
    }
}
