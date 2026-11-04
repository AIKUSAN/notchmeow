import Foundation

// Two cats mode: a press in cat 2's part of the overlap with cat 1 drags nothing out of the notch (CatIslandLayout.bigCatPressed), with the island's own numbers, and the island's hit test is
// that rule. Run it through scripts/test-cat-press.sh.
@main
enum CatPressTests {
    typealias H = CatIslandLayout.HitCircle

    @MainActor static func main() {
        CT.section("the expanded overview: cat 1 (Ø58, circle 29) and cat 2 (Ø46, circle 23), 40 pt apart")
        let c1 = H(x: 50, y: 101, r: 29), c2 = H(x: 90, y: 109, r: 23)
        func p(_ x: Double, _ y: Double, second: H? = c2) -> Bool { CatIslandLayout.bigCatPressed(x: x, y: y, cat1: c1, cat2: second) }
        CT.check("a press only cat 1 covers is on the big cat", p(30, 101), true)
        CT.check("a press in the overlap, nearer cat 1's centre, is still the big cat's", p(70, 104), true)
        CT.check("a press in the overlap, nearer cat 2's centre, is cat 2's: it drags nothing", p(72, 105), false)
        CT.check("a press only cat 2 covers is not the big cat", p(105, 109), false)
        CT.check("a press outside both is not", p(200, 101), false)
        CT.check("a tie goes to cat 1", CatIslandLayout.bigCatPressed(x: 70, y: 105, cat1: H(x: 60, y: 105, r: 20), cat2: H(x: 80, y: 105, r: 20)), true)
        CT.check("without a second cat the old rule holds: cat 1's circle alone, edge included", [p(72, 105, second: nil), p(79, 101, second: nil), p(79.5, 101, second: nil)], [true, true, false])

        CT.section("the compact island: two Ø20 heads 24 pt apart, each with the canvas circle of 16.7 pt")
        let k1 = H(x: 30, y: 16, r: 20 / 0.6 / 2), k2 = H(x: 54, y: 16, r: 20 / 0.6 / 2)
        func q(_ x: Double) -> Bool { CatIslandLayout.bigCatPressed(x: x, y: 16, cat1: k1, cat2: k2) }
        CT.check("left of the overlap, cat 1's", q(15), true)
        CT.check("in the overlap, nearer cat 1", q(40), true)
        CT.check("in the overlap, exactly between the two, cat 1's (a tie)", q(42), true)
        CT.check("in the overlap, nearer cat 2: not the big cat", q(44), false)
        CT.check("right of the overlap, cat 2's only", q(65), false)

        CT.section("the island's hit test is that rule, with cat 2's circle when there is a second cat")
        let island = (try? String(contentsOfFile: "NotchBuddy/Sources/App/IslandWindowController.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("it asks the rule", island.contains("CatIslandLayout.bigCatPressed("))
        CT.checkTrue("with cat 2's place when Two cats shows a second cat", island.contains("s.cast.second != nil") && island.contains("secondCatPlace(state: s, islandW: islandW, islandH: islandH)"))
        CT.checkTrue("and no longer with cat 1's circle alone", !island.contains("return dx*dx + dy*dy <= radius * radius"))
        CT.finish()
    }
}
