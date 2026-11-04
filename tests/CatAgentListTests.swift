import AppKit
import Foundation

@main
enum CatAgentListTests {
    typealias L = CatAgentList
    typealias D = CatDisplaySettings

    @MainActor static func main() {
        CT.section("the rows: the agents on the island, the most recent event first; integrations are not agents")
        let agents = [L.Agent(id: "integration_stripe", name: "Stripe", color: "#0570DE", last: 900), L.Agent(id: "integration_claude", name: "Claude Code", color: "#E07950", last: 10),
                      L.Agent(id: "agent_gemini", name: "Gemini CLI", color: "#8AB4F8", last: 50), L.Agent(id: "agent_codex", name: "Codex", color: "#2DD4BF", last: 30),
                      L.Agent(id: "ai_openai", name: "OpenAI", color: "#10A37F", last: 70)]
        let display = D(mode: .perAgent, pair: ["shrimpy", "momo"], agentCats: ["agent_gemini": "latte"])
        let rows = L.rows(agents: agents, display: display, main: "ginger")
        CT.check("Gemini CLI (50), then Codex (30), then Claude Code (10)", rows.map(\.id), ["agent_gemini", "agent_codex", "integration_claude"])
        CT.check("their coats: stored, then the default, then the default", rows.map(\.cat), ["latte", "momo", "shrimpy"])
        CT.check("they are on the island, and keep the name and colour the island shows", [rows[0].present, rows[0].name == "Gemini CLI", rows[0].color == "#8AB4F8"], [true, true, true])

        CT.section("a pill with no event yet comes after the pills that had one, in the island's order")
        let quiet = [L.Agent(id: "agent_a", name: "A", color: "#111111"), L.Agent(id: "agent_b", name: "B", color: "#222222", last: 5), L.Agent(id: "agent_c", name: "C", color: "#333333")]
        CT.check("B, then A and C as the island lists them", L.rows(agents: quiet, display: D(), main: "ginger").map(\.id), ["agent_b", "agent_a", "agent_c"])
        CT.check("a time that is NaN counts as no event", L.rows(agents: [L.Agent(id: "agent_a", name: "A", color: "#111111", last: .nan), L.Agent(id: "agent_b", name: "B", color: "#222222", last: 1)], display: D(), main: "ginger").map(\.id), ["agent_a", "agent_b"])
        CT.check("an agent listed twice is one row", L.rows(agents: quiet + quiet, display: D(), main: "ginger").count, 3)
        CT.check("a new agent with no stored coat wears the Main cat until it is given one", L.rows(agents: quiet, display: D(), main: "ginger").map(\.cat), ["ginger", "ginger", "ginger"])

        CT.section("agents that are only stored come after, in code-point order, named by the pill catalog when it knows them")
        let stored = D(mode: .perAgent, pair: ["shrimpy", "momo"], agentCats: ["agent_zed": "snow", "agent_alpha": "blue", "agent_gemini": "latte", "ai_openai": "puff", "agent_codex": "momo"])
        let known: (String) -> (name: String, color: String)? = { $0 == "agent_codex" ? ("Codex", "#2DD4BF") : nil }
        let all = L.rows(agents: [agents[3]], display: stored, main: "ginger", lookup: known)
        CT.check("Codex is on the island; Alpha, Gemini and Zed are not; the AI provider is no agent", all.map(\.id), ["agent_codex", "agent_alpha", "agent_gemini", "agent_zed"])
        CT.check("the stored ones are not present, with a name made from the ID and the grey", [all[1].present, all[1].name, all[1].color], [false, "Alpha", L.fallbackColor] as [AnyHashable])
        CT.check("and wear their coats", all.map(\.cat), ["momo", "blue", "latte", "snow"])
        CT.check("a stored Codex that is not on the island is named by the catalog", L.rows(agents: [], display: stored, main: "ginger", lookup: known).first { $0.id == "agent_codex" }.map { [$0.name, $0.color] }, ["Codex", "#2DD4BF"])

        CT.section("names made from an ID")
        CT.check("agent_my-tool is My tool", L.title("agent_my-tool"), "My tool")
        CT.check("agent_gemini is Gemini", L.title("agent_gemini"), "Gemini")
        CT.check("integration_claude is Claude Code", L.title("integration_claude"), "Claude Code")
        CT.check("nothing after the prefix is the ID itself", L.title("agent_"), "agent_")

        CT.section("nothing to list")
        CT.check("no agents and nothing stored: no rows", L.rows(agents: [], display: D(), main: "ginger"), [])

        CT.section("the list's order follows the events live: an event reorders it unless that pill already had the latest one")
        CT.check("nothing recorded yet: the first event does", L.touchReorders([:], id: "agent_a"), true)
        CT.check("the pill with the latest event has another: the order stays", L.touchReorders(["agent_a": 30, "agent_b": 20], id: "agent_a"), false)
        CT.check("another pill's event moves it to the front: the order changes", L.touchReorders(["agent_a": 30, "agent_b": 20], id: "agent_b"), true)
        CT.check("a pill with no event yet gets its first: the order changes", L.touchReorders(["agent_a": 30], id: "agent_c"), true)
        func order(_ last: [String: Double]) -> [String] {
            L.rows(agents: ["agent_a", "agent_b", "agent_c"].map { L.Agent(id: $0, name: $0, color: "#000000", last: last[$0] ?? 0) }, display: D(), main: "ginger").map(\.id)
        }
        for id in ["agent_a", "agent_b", "agent_c"] {
            var last: [String: Double] = ["agent_a": 30, "agent_b": 20]   // agent_c has had no event
            let before = order(last), predicted = L.touchReorders(last, id: id)
            last[id] = 99
            CT.check("an event for \(id): the list reorders exactly when touchReorders says so", order(last) != before, predicted)
        }

        CT.section("the Display preview's sample island: what each mode shows")
        let one = CatDisplaySample.cast(D(), main: "ginger"), per = CatDisplaySample.cast(D(mode: .perAgent), main: "ginger"), two = CatDisplaySample.cast(D(mode: .two), main: "ginger")
        CT.check("One cat: the Main cat everywhere, the big cat and the four others in the row", [one.big.cat] + one.pills.map(\.cat), ["ginger", "ginger", "ginger", "ginger", "ginger"])
        CT.check("A cat for each agent: Claude Code Shrimpy, Codex Momo, and the others a coat of their own that is not taken", [per.big.cat, per.pills[0].cat, per.pills[1].cat], ["shrimpy", "momo", per.pills[1].cat])
        CT.checkTrue("the sample's two new agents wear different coats, not Shrimpy, Momo or the Main cat", { let c = [per.pills[1].cat, per.pills[2].cat]; return Set(c).count == 2 && !c.contains("shrimpy") && !c.contains("momo") && !c.contains("ginger") }())
        CT.check("Two cats: the pair, and Codex, which waits for you, is cat 2", [two.big.cat, two.second?.cat ?? "", two.second?.pill ?? ""], ["shrimpy", "momo", "agent_codex"])
        CT.check("and Codex has left the row", two.pills.map(\.pill), ["agent_gemini", "agent_antigravity", "integration_stripe"])
        CT.check("the preview never stores a coat", CatDisplaySample.coats(D(), main: "ginger").count > 0 && D().agentCats.isEmpty, true)
        CT.check("it is the same every time", CatDisplaySample.cast(D(mode: .perAgent), main: "ginger"), per)

        CT.section("the compact island's cats: what ships stays, and Two cats has two in the left ear")
        CT.check("One cat and A cat for each agent: one cat, 40 pt in", [CatIslandLayout.compactX(.one), CatIslandLayout.compactX(.perAgent)], [[40], [40]])
        CT.check("Two cats: 30 and 54 pt in", CatIslandLayout.compactX(.two), [30, 54])
        CT.check("the greeting settles its cat where the pair's first cat lives, and the second pops in 24 pt (1.2 of Ø20) beside it", [CatIslandLayout.compactX(.two)[0], CatIslandLayout.compactX(.two)[1] - CatIslandLayout.compactX(.two)[0]], [30, 24])

        CT.section("the overview's left card in Two cats mode: the numbers of the prototype, and the text keeps its gap")
        let shippingLeading = CatIslandLayout.oneTextLeading, p = CatIslandLayout.pairExpanded(botX: 68, cy: 101)
        CT.check("cat 1 moves 18 pt left (its size is the one cat's, Ø58, and is not the layout's to say)", p.cat1X, 50)
        CT.check("cat 2 is 46 across, 40 pt right of where the one cat was and 8 pt lower", [p.cat2X, p.cat2Y, p.cat2D], [108, 109, 46])
        CT.check("the text starts 21 pt after cat 2's edge, 142 pt into the card", p.textLeading, 142)
        CT.check("as it starts 21 pt after the one cat's edge, 108 pt into the card, as it ships", 68 + 58 / 2 + CatIslandLayout.textGap - CatIslandLayout.cardX, shippingLeading)
        CT.checkTrue("the two heads do not touch: a 6 pt gap between cat 1's right edge and cat 2's left edge", (p.cat2X - p.cat2D / 2) - (p.cat1X + 58.0 / 2) == 6)
        CT.check("cat 1's badge may reach 39 pt left of cat 1's centre: the card's edge (10 pt in) plus a 1 pt margin", CatIslandLayout.pairBadgeReach(cat1X: p.cat1X), 39)
        CT.check("and the reach follows the cat (cat 1 at 60 reaches 49)", CatIslandLayout.pairBadgeReach(cat1X: 60), 49)
        CT.check("the fix moves nothing else: the numbers above are the owner's (cat 1 at 50, cat 2 at 108, Ø46, text at 142)", [p.cat1X, p.cat2X, p.cat2D, p.textLeading], [50, 108, 46, 142])
        CT.check("the overview's hosted cards (integrations, the plan, a diff) move right by what the ticker's text moves, 34 pt, when there is a cat 2", CatIslandLayout.overviewCardShift(second: true, botX: 68), p.textLeading - shippingLeading)
        CT.check("One cat and A cat for each agent have no cat 2: the cards do not move", CatIslandLayout.overviewCardShift(second: false, botX: 68), 0)
        CT.section("the Claude plan card: the percent, the rows and the header fit, as it ships and in Two cats mode (text widths are measured with the system font, not guessed)")
        func textWidth(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, digits: Bool = false) -> Double {
            let font = digits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            return Double((s as NSString).size(withAttributes: [.font: font]).width)
        }
        let shipRows = CatIslandLayout.planRowsWidth(shift: 0), shiftedRows = CatIslandLayout.planRowsWidth(shift: CatIslandLayout.overviewCardShift(second: true, botX: 68))
        CT.check("the rows have 202 pt in the card as it ships (322 - 108 - 12) and 168 pt with cat 2's 34 pt shift", [shipRows, shiftedRows], [202, 168])
        CT.check("the percent column is 34 pt in both rows, and a stacked row's widest line is the label, the bar and the percent: 40 + 50 + 34 + 2 x 5 = 134", [CatIslandLayout.planPercentWidth, CatIslandLayout.planStackedLineWidth], [34, 134])
        CT.checkTrue("'100%' (about 33 pt, measured) fits that column on one line: in the 30 pt the shipping row used to have, it wrapped to '100' over '%'", textWidth("100%", 11, .semibold, digits: true) + 1 <= CatIslandLayout.planPercentWidth)
        CT.checkTrue("the stacked row fits the shifted width with 30 pt to spare", CatIslandLayout.planStackedLineWidth <= shiftedRows - 30)
        CT.check("the reset line is indented under the bar: the label column and one gap, 45 pt", CatIslandLayout.planResetIndent, 45)
        let arrow = 8.0   // the clockwise arrow, a symbol set at 8 pt
        CT.checkTrue("the stacked reset line (indent + arrow + gap + 'Resetting…', the longest label, measured) fits the shifted width", CatIslandLayout.planResetIndent + arrow + CatIslandLayout.planRowSpacing + textWidth("Resetting…", 10) <= shiftedRows)
        func shippingRow(_ reset: String) -> Double { CatIslandLayout.planLabelWidth + CatIslandLayout.planBarWidth + CatIslandLayout.planPercentWidth + arrow + 4 * CatIslandLayout.planRowSpacing + textWidth(reset, 10) }
        CT.checkTrue("the shipping row with its longest date label ('Thu 14:30') fits the 202 pt it has, and would not fit 168: that is why only the shifted card stacks", shippingRow("Thu 14:30") <= shipRows && shippingRow("Thu 14:30") > shiftedRows)
        CT.checkTrue("even with 'Resetting…' the shipping row stays inside the card, 6 pt from its edge", CatIslandLayout.oneTextLeading + shippingRow("Resetting…") <= CatIslandLayout.cardWidth - 6)
        let titleAndDot = 7 + 6 + textWidth("Claude plan", 12, .semibold)
        CT.checkTrue("the header fits its longest ordinary subtitle, '59 min ago' (the dot, the title and the subtitle: about 147 pt measured), in the shifted card's 168 pt: with the 36 pt right margin it used to have, it had 144 and cut it to '59 min a…'", titleAndDot + 6 + textWidth("59 min ago", 11) <= shiftedRows)
        CT.checkTrue("and the title stays whole next to the longest subtitle there is, 'Waiting for a Claude Code reply', which gives way instead", titleAndDot + 6 + textWidth("Waiting for a Claude Code reply", 11) > shipRows && titleAndDot <= shiftedRows)
        CT.check("what cat 2's agent is doing, in words", [CatIslandLayout.stateWords(.approval), CatIslandLayout.stateWords(.question), CatIslandLayout.stateWords(.thinking)], ["waiting for you", "has a question", "thinking"])
        CT.check("every one of the 11 states has words", CatState.allCases.map { CatIslandLayout.stateWords($0) }.filter { $0.isEmpty }, [])

        CT.section("which cats have kittens, and where: One cat and A cat for each agent the big cat, Two cats each cat (expanded) or a count by cat 2 (compact)")
        let bigAt = (x: 40.0, y: 16.0, d: 20.0), secondAt = (x: 54.0, y: 16.0, d: 20.0)
        let parentsOne = CatIslandLayout.kittenParents(.one, expanded: false, big: bigAt, second: nil)
        CT.check("One cat, compact: the big cat's, tucked beside it", parentsOne.map { [$0.place, "\($0.cat)", "\($0.unit)", "\($0.countsBoth)"] }, [["bigCompact", "0", "20.0", "false"]])
        CT.check("A cat for each agent, expanded: the big cat's, in a row under it", CatIslandLayout.kittenParents(.perAgent, expanded: true, big: (68, 101, 58), second: nil).map(\.place), ["bigExpanded"])
        let parentsTwo = CatIslandLayout.kittenParents(.two, expanded: false, big: bigAt, second: secondAt)
        CT.check("Two cats, compact: one layer, by cat 2, counting both cats' kittens", parentsTwo.map { [$0.place, "\($0.cat)", "\($0.x)", "\($0.countsBoth)"] }, [["pairCompact", "1", "54.0", "true"]])
        CT.check("Two cats, expanded: each cat's, centred under it", CatIslandLayout.kittenParents(.two, expanded: true, big: (50, 101, 58), second: (108, 109, 46)).map { [$0.place, "\($0.cat)", "\($0.unit)"] }, [["pairExpanded", "0", "58.0"], ["pairExpanded", "1", "46.0"]])
        CT.check("Two cats with no cat 2 to hang a count on: nothing", CatIslandLayout.kittenParents(.two, expanded: false, big: bigAt, second: nil), [])

        CT.section("the kitten layer's boxes hold every kitten, every \"+N\" and the pair's \"×N\", whatever the count")
        var outside: [String] = []
        for place in ["bigExpanded", "bigCompact", "pairExpanded", "pairCompact", "pill"] {
            let box = CatIslandLayout.kittenBox(place)
            for count in 0...9 {
                let list = (0..<count).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: Double($0), last: 0) }
                let s = CatKittens.slots(place, list)
                var inside = s.shown.allSatisfy { $0.x - $0.d / 2 >= box.x0 && $0.x + $0.d / 2 <= box.x1 && $0.y - $0.d / 2 >= box.y0 && $0.y + $0.d / 2 <= box.y1 }
                if let m = s.moreAt { inside = inside && m.x - m.size * 1.4 >= box.x0 && m.x + m.size * 1.4 <= box.x1 && m.y - m.size >= box.y0 && m.y + m.size <= box.y1 }
                if let l = s.label { inside = inside && l.x - l.size * 1.4 >= box.x0 && l.x + l.size * 1.4 <= box.x1 && l.y - l.size >= box.y0 && l.y + l.size <= box.y1 }
                if !inside { outside.append("\(place) with \(count)") }
            }
        }
        CT.checkRows("five places, 0 to 9 kittens", outside)
        func crowd(_ place: String, _ n: Int) -> CatKittens.Slots { CatKittens.slots(place, (0..<n).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: Double($0), last: 0) }) }
        CT.check("overview (one cat and the pair): the \"+N\" starts 0.85 kitten heads right of the last shown kitten's centre, so it clears that kitten's badge", ["bigExpanded", "pairExpanded"].map { p in let s = crowd(p, 5); return CatIslandLayout.moreLabelLeft(s) == s.shown.last.map { $0.x + 0.85 * $0.d } }, [true, true])
        CT.checkTrue("the compact strip, the pill, the pair's \"×N\" and a crowd that fits keep the label where it was (no new anchor)", ["bigCompact", "pairCompact", "pill"].allSatisfy { CatIslandLayout.moreLabelLeft(crowd($0, 5)) == nil } && CatIslandLayout.moreLabelLeft(crowd("bigExpanded", 3)) == nil && CatIslandLayout.moreLabelLeft(crowd("pairExpanded", 0)) == nil)
        var spill: [String] = []
        for place in ["bigExpanded", "pairExpanded"] {
            let box = CatIslandLayout.kittenBox(place)
            for n in 4...9 {
                let s = crowd(place, n)
                if let left = CatIslandLayout.moreLabelLeft(s), let m = s.moreAt, left + (Double("+\(s.more)".count) * 0.62 + 0.9) * m.size > box.x1 { spill.append("\(place) with \(n)") }
            }
        }
        CT.checkRows("the moved \"+N\" stays inside the kitten layer's box", spill)
        CT.check("a pill with three kittens reserves their width: 3 slots of 16/28, from the edge to the third's far side and a little more", CatIslandLayout.pillKittenReserve(CatKittens.slots("pill", (0..<3).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: Double($0), last: 0) }), pillHeight: 28), (17.5 / 28 + 2 * 16.0 / 28 + 15.0 / 56 + 0.2) * 28)
        CT.checkTrue("with a fourth, the '+N' after the third is reserved too", CatIslandLayout.pillKittenReserve(CatKittens.slots("pill", (0..<5).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: Double($0), last: 0) }), pillHeight: 28) > 3 * 16.0 + 17.5)
        CT.check("and a pill without kittens reserves nothing", CatIslandLayout.pillKittenReserve(CatKittens.slots("pill", []), pillHeight: 28), 0)

        CT.section("cat 2 is drawn beside cat 1 in the expanded island only in Two cats mode's overview")
        CT.check("Two cats, overview: yes; Two cats, any other view: no", [true, false], [CatIslandLayout.secondBesideBig(.two, overview: true), CatIslandLayout.secondBesideBig(.two, overview: false)])
        CT.check("One cat and A cat for each agent: never", [CatIslandLayout.secondBesideBig(.one, overview: true), CatIslandLayout.secondBesideBig(.one, overview: false), CatIslandLayout.secondBesideBig(.perAgent, overview: true), CatIslandLayout.secondBesideBig(.perAgent, overview: false)], [false, false, false, false])

        CT.finish()
    }
}
