import Foundation

// Where the cats sit in the island, as numbers: one place for the compact notch's and (from the Two cats layout) the expanded overview's, read by the views, the
// hit test, the greeting, the Settings preview and the contact sheets, so they cannot disagree. Foundation only. One cat keeps the numbers that ship.

enum CatIslandLayout {
    /// The compact island's cats in the left ear, as the distance of each centre from the island's left edge (pt; the head width is `IslandRestingLayout.botDiameter`, 20
    /// on a 32 pt strip). One cat and A cat for each agent: the one big cat, 40 pt in, as it has always been. Two cats: two cats side by side, 30 and 54 pt in
    /// (the prototype's numbers), which the 80 pt ear holds.
    static func compactX(_ mode: CatDisplayMode) -> [Double] { mode == .two ? [30, 54] : [40] }

    /// Whether cat 2 is drawn beside cat 1 in the expanded island: Two cats mode, overview only. Cat 1's badge flips left (clear of cat 2) exactly there.
    static func secondBesideBig(_ mode: CatDisplayMode, overview: Bool) -> Bool { mode == .two && overview }

    /// A circle a press can land in, in any one coordinate space (both circles of a test must use the same one).
    struct HitCircle: Equatable, Sendable { var x: Double, y: Double, r: Double }

    /// Whether a press at (x, y) is on the big cat. Where cat 1's circle and cat 2's overlap (Two cats mode: `cat2` is given) the cat whose centre is nearer wins and a tie goes to cat 1, the
    /// same rule as Windows' `catClickTarget`; a press that is cat 2's is not on the big cat and drags nothing out of the notch. Without a second cat it is cat 1's circle alone, as it was.
    static func bigCatPressed(x: Double, y: Double, cat1: HitCircle, cat2: HitCircle?) -> Bool {
        func d(_ c: HitCircle) -> Double { (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) }
        guard d(cat1) <= cat1.r * cat1.r else { return false }
        guard let c2 = cat2, d(c2) <= c2.r * c2.r else { return true }
        return d(c2) >= d(cat1)
    }

    /// The overview's left card in Two cats mode. The island's cards sit 10 pt in from its left edge; the one big cat is at `IslandConst.viewLayouts[.overview].botX` (68),
    /// 58 across, and the ticker's text starts 21 pt after its edge (108 pt into the card). With two cats the first moves 18 pt left, the second (46 across, 8 pt lower) sits
    /// beside it 40 pt to the right of where the one cat was, which leaves a 6 pt gap between the two heads (the prototype's numbers: cat 2 at 114 where the one cat is at 74),
    /// and the text starts 21 pt after the second's edge.
    struct PairExpanded: Equatable {
        var cat1X: Double
        var cat2X: Double, cat2Y: Double, cat2D: Double
        /// Where the ticker's text starts, in points from the left edge of the card.
        var textLeading: Double
    }
    static let cardX = 10.0, oneTextLeading = 108.0, textGap = 21.0, pairCat2D = 46.0
    /// `botX` and `cy` are where `botPosition` puts the one big cat in the overview. Cat 1 keeps the diameter the one cat has there, so it is not the layout's to say.
    static func pairExpanded(botX: Double, cy: Double) -> PairExpanded {
        let cat2X = botX + 40
        return PairExpanded(cat1X: botX - 18, cat2X: cat2X, cat2Y: cy + 8, cat2D: pairCat2D, textLeading: cat2X + pairCat2D / 2 + textGap - cardX)
    }

    /// How far left of cat 1's centre its badge may reach in the pair's overview: to the card's edge plus `badgeMargin`. The badge sits on cat 1's left there (clear of cat 2) and, on a Ø58 head, would
    /// otherwise stick out of the card by a few points; the badge is held back to the card (it then overlaps the head's left corner a little) rather than the pair moved.
    static let badgeMargin = 1.0
    static func pairBadgeReach(cat1X: Double) -> Double { cat1X - (cardX + badgeMargin) }

    /// How far the overview's hosted cards (an integration's, the plan's, a diff) move right to make room for cat 2: what the ticker's text moves (142 instead of 108, so 34 pt) when
    /// there is a cat 2, and 0 otherwise (One cat and A cat for each agent), so those cards are exactly what ships.
    static func overviewCardShift(second: Bool, botX: Double) -> Double {
        second ? pairExpanded(botX: botX, cy: 0).textLeading - oneTextLeading : 0
    }

    /// The Claude plan card's rows. The card is 322 pt wide; its gauge rows start 108 pt in and keep 12 pt on the right (the header keeps the same 12), so they have 202 pt as the card ships and 34 pt
    /// less when it is shifted for cat 2. Shipping, a row is one line (label, bar, percent, arrow, reset time), about 200 pt, which does not fit 168: in the shifted card (`stacked`) the reset time goes
    /// on a second line under the bar, so the widest line is label + bar + percent and their two gaps. The percent column is 34 pt in both rows: "100%" is about 33 pt wide, and in the 30 pt the
    /// shipping row used to have it wrapped to "100" over "%". Both rows in `ClaudePlanCardView.swift` read these numbers.
    static let cardWidth = 322.0, planRowsTrailing = 12.0
    static let planLabelWidth = 40.0, planBarWidth = 50.0, planPercentWidth = 34.0, planRowSpacing = 5.0
    static func planRowsWidth(shift: Double) -> Double { cardWidth - oneTextLeading - planRowsTrailing - shift }
    static let planStackedLineWidth = planLabelWidth + planBarWidth + planPercentWidth + 2 * planRowSpacing
    /// Where a stacked row's reset line starts: under the bar (the label's column and one gap in).
    static let planResetIndent = planLabelWidth + planRowSpacing

    /// The box a place's kittens, their "+N" and the pair's "×N" can be drawn in, in the place's unit, from the parent's head centre (or, for `pill`, from the pill's trailing edge and the
    /// middle of its height): x from `x0` to `x1`, y from `y0` to `y1`. The kitten layer is a transparent canvas of this size, so it covers no more of the island than it needs.
    static func kittenBox(_ place: String) -> (x0: Double, y0: Double, x1: Double, y1: Double) {
        switch place {
        case "bigExpanded": return (-0.2, 0.25, 2.1, 1.0)
        case "bigCompact": return (0.6, -1.0, 2.8, 0.7)
        case "pairExpanded": return (-1.0, 0.25, 1.0, 1.1)
        case "pairCompact": return (0.3, -0.3, 2.1, 0.9)
        case "pill": return (-3.0, -0.55, 0.15, 0.55)
        default: return (0, 0, 0, 0)
        }
    }

    /// One layer of kittens: which cat is the parent (0 the big cat, 1 cat 2), the place, the unit (the parent's head width), where the parent is, and whether the layer counts
    /// both cats' kittens (the pair's "×N" in the compact island).
    struct KittenParent: Equatable {
        var cat: Int
        var place: String
        var unit: Double
        var x: Double, y: Double
        var countsBoth = false
    }

    /// The layers of kittens for a mode, in the compact island or in the overview. One cat and A cat for each agent: the big cat's, tucked beside it (compact) or in a row under it.
    /// Two cats, expanded: each cat's under it. Two cats, compact: there is no room beside the pair, so one layer by cat 2 draws a count of both cats' kittens.
    static func kittenParents(_ mode: CatDisplayMode, expanded: Bool, big: (x: Double, y: Double, d: Double), second: (x: Double, y: Double, d: Double)?) -> [KittenParent] {
        let place = CatKittens.placeOf(mode, expanded: expanded)
        guard mode == .two else { return [KittenParent(cat: 0, place: place, unit: big.d, x: big.x, y: big.y)] }
        guard let second else { return [] }
        if !expanded { return [KittenParent(cat: 1, place: place, unit: second.d, x: second.x, y: second.y, countsBoth: true)] }
        return [KittenParent(cat: 0, place: place, unit: big.d, x: big.x, y: big.y), KittenParent(cat: 1, place: place, unit: second.d, x: second.x, y: second.y)]
    }

    /// How much of a pill's trailing end its kittens and their "+N" take (in pt, for a pill `h` high): the pill's title keeps clear of them.
    static func pillKittenReserve(_ slots: CatKittens.Slots, pillHeight h: Double) -> Double {
        guard let last = slots.shown.last else { return 0 }
        let kittens = -last.x + last.d / 2 + 0.2
        return max(kittens, slots.moreAt.map { -$0.x + $0.size * 1.0 } ?? 0) * h
    }

    /// Where the "+N" of the overview's kitten rows starts (its left edge, in the place's unit): 0.85 kitten heads right of the last shown kitten's centre, so it clears that kitten's
    /// state badge. nil for every other place and when nothing is left over: those keep `moreAt`.
    static func moreLabelLeft(_ slots: CatKittens.Slots) -> Double? {
        guard slots.moreAt != nil, slots.place == "bigExpanded" || slots.place == "pairExpanded", let last = slots.shown.last else { return nil }
        return last.x + 0.85 * last.d
    }

    /// What cat 2's agent is doing, for the second line of the overview's ticker ("Codex · waiting for you").
    static func stateWords(_ s: CatState) -> String {
        switch s {
        case .idle: return "idle"
        case .working: return "working"
        case .thinking: return "thinking"
        case .searching: return "searching"
        case .approval: return "waiting for you"
        case .question: return "has a question"
        case .error: return "hit an error"
        case .finished: return "finished"
        case .ratelimit: return "rate limited"
        case .sleeping: return "asleep"
        case .dizzy: return "dizzy"
        }
    }
}
