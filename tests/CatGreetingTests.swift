import Foundation

@main
enum CatGreetingTests {
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }

    @MainActor static func main() {
        let seq = CT.fixture("sequence-cases.json")
        typealias G = CatGreeting

        CT.section("the timeline's beats")
        let t = seq["greetingTimeline"] as! [String: Any]
        let beats: [String: Double] = [
            "grow": G.GT.grow, "badge": G.GT.badge, "blink2": G.GT.blink2, "tint0": G.GT.tint0, "tint1": G.GT.tint1, "leave": G.GT.leave, "COLLAPSE": G.GT.collapse,
            "v2_fall0": G.GT2.fall0, "v2_land": G.GT2.land, "v2_bounce1": G.GT2.bounce1, "v2_slide0": G.GT2.slide0, "v2_slide1": G.GT2.slide1, "v2_pop0": G.GT2.pop0,
            "v2_wave0": G.GT2.wave0, "v2_wave1": G.GT2.wave1, "v2_back0": G.GT2.back0, "v2_back1": G.GT2.back1, "v2_SLIDE": G.GT2.slide,
            "notchW": G.notchW, "notchH": G.notchH, "compact": G.compact,
        ]
        CT.checkJSON("every beat", got: beats, want: t)
        CT.checkNear("the greeting lasts 5.74 s", G.length, num(seq["greetingLengthS"]))

        CT.section("the streaks")
        CT.checkJSON("sixteen seeded streaks", got: G.streaks.map { ["a": $0.a, "sp": $0.sp, "len": $0.len, "t0": $0.t0, "col": $0.col] as [String: Any] }, want: seq["greetingStreaks"]!)

        CT.section("the pose every 100 ms and at each beat")
        var diffs: [String] = []
        for s in seq["greetingSamples"] as! [[String: Any]] {
            let ms = num(s["tMs"])
            diffs += CT.diffs(CT.json(G.pose(ms / 1000)), s["pose"]!).map { "t \(ms) ms: \($0)" }
        }
        CT.checkRows("\((seq["greetingSamples"] as! [Any]).count) samples", diffs)

        CT.section("a dropped file's flight")
        let fl = seq["flight"] as! [String: Any]
        CT.checkNear("380 ms", CatEngine.flightMs, num(fl["flightMs"]))
        for c in fl["cases"] as! [[String: Any]] {
            let f = c["from"] as! [String: Any], to = c["to"] as! [String: Any]
            let o = G.flightAt(from: (num(f["x"]), num(f["y"])), to: (num(to["x"]), num(to["y"])), R: num(c["R"]), k: num(c["k"]))
            CT.checkJSON("k = \(c["k"]!)", got: ["x": o.x, "y": o.y, "size": o.size, "rot": o.rot] as [String: Any], want: c["out"]!)
        }

        CT.section("leaving early: the pointer left mid-greeting, or holds the island open")
        // An early leave starts from the pose the cat is in; the island always ends compact with the cat at the notch.
        for leave in [1.0, 1.7, 2.0, 3.0] {
            let end = G.pose(leave + 0.34 + 0.1, leave: leave)
            CT.checkNear("leave at \(leave): the island ends compact (width)", end.iw, G.compact)
            CT.checkNear("leave at \(leave): and the cat is at the notch", end.x, 320 - G.compact / 2 + 40)
            CT.checkTrue("leave at \(leave): the cat is back to rest and hands are down", end.sx == 1 && end.sy == 1 && end.tilt == 0 && end.handL == 0 && end.handR == 0)
            let during = G.pose(leave + 0.05, leave: leave), before = G.pose(leave, leave: leave)
            CT.checkTrue("leave at \(leave): no jump at the moment of leaving", abs(during.x - before.x) < 20 && abs(during.y - before.y) < 20 && abs(during.hb - before.hb) < 4)
        }
        // The real compact island of a screen: its width, height and the cat's size follow it.
        let real = G.Compact(width: 344, height: 38)
        let landed = G.pose(G.GT.leave + 0.34 + 0.1, into: real)
        CT.checkNear("a real compact island: the width", landed.iw, 344); CT.checkNear("the height", landed.ih, 38)
        CT.checkNear("the cat settles at x = 40 from the island's left edge", landed.x, 320 - 344 / 2 + 40)
        CT.checkNear("in the middle of the strip", landed.y, 19); CT.checkNear("at the compact size, Ø20", landed.hb * 1.34, 20)
        CT.checkNear("on a 24 pt strip (no notch) the cat is Ø18", G.Compact(width: 80, height: 24).botDiameter, 18)
        CT.checkNear("the contract's compact island is the default", G.pose(5.3, into: G.Compact()).iw, G.compact)
        CT.checkNear("holding the island open keeps the settled pose forever (x)", G.pose(60, leave: .infinity).x, 320)
        CT.checkNear("and the island stays at full width", G.pose(60, leave: .infinity).iw, 640)
        var finite = true
        for ms in stride(from: -500, through: 8000, by: 50) { let p = CT.json(G.pose(Double(ms) / 1000)) as! [String: Any]; if p.values.contains(where: { ($0 as? Double)?.isFinite == false }) { finite = false } }
        CT.checkTrue("every pose from before the start to well after the end is finite", finite)

        // The last beat: the session cats pop in as a row of three, glide into the compact island's 2x2 grid, and a fourth joins.
        CT.section("the last beat: the glide's timeline and geometry")
        CT.checkJSON("the beats", got: ["glide0": G.GT3.glide0, "glide1": G.GT3.glide1, "four0": G.GT3.four0, "end": G.GT3.end, "greetEnd": G.greetEnd] as [String: Any], want: seq["miniTimeline"]!)
        CT.checkNear("the whole greeting, glide included, ends at 6.5 s", G.greetEnd, 6.5)
        CT.checkNear("and its first part is still 5.74 s", G.length, 5.74)
        CT.checkJSON("the row, the grid's cells and which row cat glides into which cell", got: [
            "row": ["d": G.miniRow.d, "step": G.miniRow.step, "inset": G.miniRow.inset, "dy": G.miniRow.dy],
            "grid": ["step": G.miniCell.step, "inset": G.miniCell.inset, "d": G.miniCell.d],
            "from": G.miniFrom.map { $0 == nil ? NSNull() : $0! as Any },
            "minD": G.miniMinD,
        ] as [String: Any], want: seq["miniGeometry"]!)

        CT.section("the glide's samples, with the timeline's own leave and two early ones")
        var glideDiffs: [String] = []
        for c in seq["miniGlideSamples"] as! [[String: Any]] {
            let g = G.miniGlide(num(c["tMs"]) / 1000, leave: num(c["leave"]))
            glideDiffs += CT.diffs(["grid": g.grid, "four": g.four] as [String: Any], c["glide"]!).map { "leave \(c["leave"]!), \(c["tMs"]!) ms: \($0)" }
        }
        CT.checkRows("\((seq["miniGlideSamples"] as! [Any]).count) samples", glideDiffs)
        CT.checkTrue("held open (leave is infinity) the island has not folded, so there is no glide", G.miniGlide(60, leave: .infinity) == G.Glide(grid: 0, four: 0))

        CT.section("the slots: the row, the glide and the end, on every island the fixture lists")
        var slotDiffs: [String] = []
        for c in seq["miniSlotCases"] as! [[String: Any]] {
            let slots = G.miniSlots(minis: num(c["minis"]), glide: G.Glide(grid: num(c["grid"]), four: num(c["four"])), width: num(c["W"]), height: num(c["H"]), d: num(c["d"]))
            slotDiffs += CT.diffs(slots.map { ["x": $0.x, "y": $0.y, "d": $0.d] as [String: Any] }, c["slots"]!).map { "\(c["name"]!), \(c["tMs"]!) ms: \($0)" }
        }
        CT.checkRows("\((seq["miniSlotCases"] as! [Any]).count) cases", slotDiffs)

        CT.section("the end of the glide is the compact island's real grid")
        // CompactMiniGrid: a 28 x 28 frame of 12 pt cells 4 apart (cell centres 8 either side of its middle), scaled about its middle by
        // miniGridScale and centred at (width - 40, height / 2) in the island; IslandRestingLayout is the compact view's own arithmetic.
        for (w, h) in [(288.0, 32.0), (344, 38), (344, 32), (240, 24), (200, 20)] {
            let layout = IslandRestingLayout(width: CGFloat(w), height: CGFloat(h)), k = Double(layout.miniGridScale)
            CT.checkNear("\(Int(w)) x \(Int(h)): the greeting's scale is the compact view's miniGridScale", G.Compact(width: w, height: h).miniScale, k)
            let cx = 320 - w / 2 + Double(layout.miniGridCenterX), cy = Double(layout.botCenterY)
            let want = [(-8.0, -8.0), (8, -8), (-8, 8), (8, 8)].map { G.Mini(x: cx + $0.0 * k, y: cy + $0.1 * k, d: 12 * k) }
            let got = G.miniSlots(minis: 1, glide: G.Glide(grid: 1, four: 1), width: w, height: h)
            var off = 0.0
            for (a, b) in zip(got, want) { off = max(off, abs(a.x - b.x), abs(a.y - b.y), abs(a.d - b.d)) }
            CT.checkTrue("\(Int(w)) x \(Int(h)): the four cats are on the grid's four cells (worst \(off))", off < 1e-9)
        }
        // The view's own literals cannot be called from a test, so they are pinned: if one changes, change the contract's grid with it.
        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandRootView.swift", encoding: .utf8)
        for (what, text) in [
            ("CompactMiniGrid: two columns of 12 pt cells 4 pt apart", "GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)"),
            ("4 pt between its rows", "LazyVGrid(columns: cols, spacing: 4)"),
            ("each cat is 20 * 0.6 = 12 pt across", ".frame(width: 12 / 0.6, height: 12 / 0.6)"),
            ("in a 28 x 28 frame", ".frame(width: 28, height: 28)"),
            ("scaled by miniGridScale", ".scaleEffect(IslandRestingLayout(width: islandWidth, height: islandHeight).miniGridScale)"),
            ("centred 40 pt in from the right edge and level with the strip's middle", ".position(x: islandWidth - 40, y: islandHeight / 2)"),
        ] { CT.checkTrue(what, view.contains(text)) }

        CT.section("leaving early: the last beat follows the island's fold")
        for leave in [0.3, 2.0, 3.0, G.GT.leave] {
            let at = { (o: Double) in G.miniSlots(minis: G.pose(leave + o, leave: leave).minis, glide: G.miniGlide(leave + o, leave: leave)).map { $0.d > 0 } }
            CT.check("leave at \(leave): no cat 0.2 s after the fold starts", at(0.2), [false, false, false, false])
            CT.check("leave at \(leave): a row of three at 0.6 s", at(0.6), [true, true, false, true])
            CT.check("leave at \(leave): the grid's four at the end", at(G.GT3.end), [true, true, true, true])
        }
        var slotsFinite = true
        for ms in stride(from: -500, through: 9000, by: 50) {
            for leave in [G.GT.leave, 1.0, .infinity] {
                for h in [0.0, 6, 24, 32, 200] {
                    let t = Double(ms) / 1000
                    let s = G.miniSlots(minis: G.pose(t, leave: leave).minis, glide: G.miniGlide(t, leave: leave), height: h)
                    if s.contains(where: { !$0.x.isFinite || !$0.y.isFinite || !$0.d.isFinite }) { slotsFinite = false }
                }
            }
        }
        CT.checkTrue("every slot is finite, before the start and after the end, held open, on a strip of any height", slotsFinite)
        CT.section("Two cats mode: the settled cat is 30 pt in, and the second cat pops in beside it as the island folds")
        let two = G.Compact(width: 288, height: 32, botInset: 30), one = G.Compact(width: 288, height: 32)
        let settled = G.pose(G.length + 1, leave: G.GT.leave, into: two), alone = G.pose(G.length + 1, leave: G.GT.leave, into: one)
        CT.check("the greeting's cat ends 30 pt from the island's left edge, where the pair's first cat lives", settled.x, 320 - 144 + 30)
        CT.check("and 40 pt, as it always did, when nothing says otherwise", alone.x, 320 - 144 + 40)
        CT.check("a Compact made the old way has the old inset", [G.Compact().botInset, G.Compact(width: 288, height: 32).botInset], [40, 40])
        CT.checkNear("the pose is the same but for x: the greeting's own beats are untouched", G.pose(2.0, leave: G.GT.leave, into: two).x, G.pose(2.0, leave: G.GT.leave, into: one).x)
        CT.checkNear("the pop has not started when the island begins to fold", G.pairPop(G.GT.leave + 0.1), 0)
        CT.checkNear("it is whole 0.42 s after", G.pairPop(G.GT.leave + 0.42), 1)
        CT.checkTrue("it overshoots on the way, like the session cats' pop", (0..<18).map { G.pairPop(G.GT.leave + 0.24 + Double($0) * 0.01) }.max()! > 1.02)
        CT.check("it never starts while the pointer holds the island open", [G.pairPop(5, leave: .infinity), G.pairPop(100, leave: .infinity)], [0.0, 0.0])
        CT.checkNear("and a greeting cut short pops from its own fold", G.pairPop(1.0 + 0.42, leave: 1.0), 1)

        CT.section("the outfit: it comes on once the cat has settled (sub-project I)")
        CT.check("it is not on while the cat falls, bounces and waves", [G.outfitFade(0), G.outfitFade(G.GT2.land), G.outfitFade(G.GT2.wave1), G.outfitFade(G.GT2.back1 - 0.01)], [0.0, 0.0, 0.0, 0.0])
        CT.checkNear("it is half on a eighth of a second after the cat has slid back", G.outfitFade(G.GT2.back1 + 0.125), 0.5)
        CT.check("and whole a quarter of a second after, until the end", [G.outfitFade(G.GT2.back1 + 0.25), G.outfitFade(G.GT.leave), G.outfitFade(G.length)], [1.0, 1.0, 1.0])

        CT.finish()
    }
}
