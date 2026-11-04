import CoreGraphics
import Foundation

@main
enum CatRendererTests {
    @MainActor static func render(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> [UInt8] { Bitmap.render(w, h, draw) }
    static func alpha(_ px: [UInt8], _ x: Int, _ y: Int, _ w: Int) -> Int { Bitmap.alpha(px, x, y, w) }
    static func coverage(_ px: [UInt8]) -> Int { Bitmap.coverage(px) }
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }
    static func rgb(_ x: Any?) -> [Double] { (x as! [NSNumber]).map(\.doubleValue) }

    /// The highest point of an ear in the world (the smallest y), found by walking the whole outline the renderer draws (the geometry test walks it the same way).
    static func earTop(_ L: CatGeometry.Layout, _ s: CatPose, _ e: CatGeometry.Ear) -> Double {
        let R = L.R, h = e.h, bw = e.bw, tip = e.tip, cx = e.cx
        let curves: [[(Double, Double)]] = [
            [(-bw, 0.25 * R), (-bw * cx, -h * 0.4), (-tip * 0.9, -h + tip * 1.3)],
            [(-tip * 0.9, -h + tip * 1.3), (0, -h - tip * 0.35), (tip * 0.9, -h + tip * 1.3)],
            [(tip * 0.9, -h + tip * 1.3), (bw * cx, -h * 0.4), (bw, 0.25 * R)],
        ]
        var best = Double.infinity
        for q in curves {
            for i in 0...400 {
                let t = Double(i) / 400, m = 1 - t
                let x = m * m * q[0].0 + 2 * m * t * q[1].0 + t * t * q[2].0, y = m * m * q[0].1 + 2 * m * t * q[1].1 + t * t * q[2].1
                let hx = e.bx + x * cos(e.rot) - y * sin(e.rot), hy = e.by + x * sin(e.rot) + y * cos(e.rot)
                best = min(best, L.head.y + sin(s.tilt) * s.sx * hx + cos(s.tilt) * s.sy * hy)
            }
        }
        return best
    }

    @MainActor static func main() {
        typealias R = CatRenderer
        typealias G = CatGeometry
        let geo = CT.fixture("geometry-cases.json")

        CT.section("every coat draws at every size, in a turned, squashed or rolled pose and with every eye shape")
        var drawn = 0, blank: [String] = []
        for id in CatPresets.ids {
            for kitten in [false, true] {
                let base = CatPresets.byID(id), p = kitten ? CatPresets.kitten(of: base) : base
                for D in [12.0, 16, 20, 28, 44, 66] {
                    let size = Int(D * 3)
                    var poses: [(String, CatPose, CatEye)] = [("rest", CatPose(), .pill)]
                    for (n, yaw, pitch) in [("right", 0.62, 0.0), ("left", -0.62, 0.0), ("up", 0.0, 0.5), ("down", 0.0, -0.5)] {
                        var s = CatPose(); s.yaw = yaw; s.pitch = pitch; poses.append((n, s, .pill))
                    }
                    var sq = CatPose(); sq.sx = 1.12; sq.sy = 0.9; sq.tilt = 0.2; sq.earU = 1.4; sq.earF = 0.6; sq.ox = 0.2; sq.oy = -0.2; sq.blush = 1; sq.tint = 0.7
                    poses.append(("squashed", sq, .happy))
                    var roll = CatPose(); roll.roll = 1.2; poses.append(("rolled", roll, .pill))
                    for e in CatEye.allCases { poses.append(("eye \(e.rawValue)", CatPose(), e)) }
                    for (name, pose, eye) in poses {
                        let px = render(size, size) { cg in
                            R.draw(cg, CatLook(preset: p, pose: pose, eye: eye, mouthOpen: eye == .wide ? 0.5 : 0), cx: Double(size) / 2, cy: Double(size) / 2, D: D)
                        }
                        drawn += 1
                        if coverage(px) == 0 { blank.append("\(p.label) \(D) \(name)") }
                    }
                }
            }
        }
        CT.check("nothing came out blank (\(drawn) drawings)", blank, [])

        CT.section("the same cat draws the same pixels twice")
        let a = render(200, 200) { R.draw($0, CatLook(preset: CatPresets.byID("shrimpy")), cx: 100, cy: 100, D: 120) }
        let b = render(200, 200) { R.draw($0, CatLook(preset: CatPresets.byID("shrimpy")), cx: 100, cy: 100, D: 120) }
        CT.checkTrue("two renders are byte for byte equal", a == b)
        CT.checkTrue("Shrimpy at Ø120 covers a good part of a 200 px square", coverage(a) > 8000)

        CT.section("a face rolled over the top of the head fades out")
        var over = CatPose(); over.roll = Double.pi
        func overRender(_ eye: CatEye) -> [UInt8] {
            render(200, 200) { R.draw($0, CatLook(preset: CatPresets.byID("momo"), pose: over, eye: eye), cx: 100, cy: 100, D: 120) }
        }
        CT.checkTrue("with the face turned away the eye shape makes no difference", overRender(.pill) == overRender(.spiral))
        CT.checkTrue("but the head is still there", coverage(overRender(.pill)) > 5000)

        CT.section("the compact detail drops the whiskers and the irises")
        func atWidth(_ D: Double) -> Int {
            coverage(render(200, 200) { R.draw($0, CatLook(preset: CatPresets.byID("momo")), cx: 100, cy: 100, D: D) })
        }
        CT.checkTrue("the full cat at Ø28 reaches further than the compact one at Ø27.9 (whiskers)", atWidth(28) > atWidth(27.9))

        CT.section("the compact detail draws flat fills (A-0b's rule, G.detailLevel(D).flatFill): a solid coat is one colour across the head below Ø28, and shaded from Ø28")
        func headColours(_ D: Double) -> Set<[Int]> {
            let p = CatPresets.byID("ginger"), unit = D / (2 * p.rx), rx = p.rx * unit, ry = p.ry * unit
            let px = render(120, 120) { R.draw($0, CatLook(preset: p), cx: 60, cy: 60, D: D) }
            // two points of the head, clear of the eyes (the coloured small eyes are wider than the ink ones were), the nose, the ears and the edge, even at Ø12
            return Set([(0.55, -0.55), (-0.85, 0.0)].map { fx, fy in
                let x = Int((60 + fx * rx).rounded()), y = Int((60 + fy * ry).rounded()), i = (y * 120 + x) * 4
                return [Int(px[i]), Int(px[i + 1]), Int(px[i + 2])]
            })
        }
        for D in [12.0, 16, 20, 24, 27.9] { CT.checkTrue("Ø\(D): one flat colour at two points of the head", headColours(D).count == 1 && CatGeometry.detailLevel(D).flatFill) }
        for D in [28.0, 44, 66] { CT.checkTrue("Ø\(D): shaded, the two points differ", headColours(D).count > 1 && !CatGeometry.detailLevel(D).flatFill) }

        CT.section("the flat fills reach the drawing: every coat's head, ears and ruff, the tabby crown band and the point mask are the contract's colours and numbers (A-0b, merged `6adf584`)")
        let flatColors = geo["flatColors"] as! [String: [String: Any]], flatFill = geo["flatFill"] as! [String: Any]
        let S = 4, side = 48, cx0 = 24.0, cy0 = 26.0
        // A compact cat (Ø20, below the Ø28 switch) at rest, drawn into a bitmap scaled up by S, so that each flat fill covers whole pixels.
        func shot(_ p: CatPreset) -> (px: [UInt8], L: G.Layout) {
            var layout: G.Layout?
            let px = render(side * S, side * S) { cg in
                cg.scaleBy(x: CGFloat(S), y: CGFloat(S))
                layout = R.draw(cg, CatLook(preset: p), cx: cx0, cy: cy0, D: 20)
            }
            return (px, layout!)
        }
        /// The pixel under the point (x, y) of the drawing: r, g, b and alpha.
        func colour(_ px: [UInt8], _ x: Double, _ y: Double) -> [Double] {
            let i = (Int(y * Double(S)) * side * S + Int(x * Double(S))) * 4
            return [Double(px[i]), Double(px[i + 1]), Double(px[i + 2]), Double(px[i + 3])]
        }
        func isColour(_ c: [Double], _ want: [Double], tol: Double = 1.5) -> Bool { c[3] == 255 && zip(c, want).allSatisfy { abs($0 - $1) <= tol } }
        var flatBad: [String] = [], tabbies = 0, points = 0
        for id in CatPresets.ids {
            let p = CatPresets.byID(id), want = flatColors[id]!, (px, L) = shot(p), headWant = rgb(want["head"]), R1 = L.R
            // The head: the flat colour covers a good part of the head's own ellipse (inside 85 % of it, clear of the ears and the ruff).
            var inside = 0, hits = 0
            for y in 0..<(side * S) {
                for x in 0..<(side * S) {
                    let fx = (Double(x) + 0.5) / Double(S), fy = (Double(y) + 0.5) / Double(S), dx = (fx - L.head.x) / (0.85 * L.rx), dy = (fy - L.head.y) / (0.85 * L.ry)
                    if dx * dx + dy * dy > 1 { continue }
                    inside += 1
                    if isColour(colour(px, fx, fy), headWant) { hits += 1 }
                }
            }
            if Double(hits) < 0.2 * Double(inside) { flatBad.append("\(id): the head's flat colour covers only \(hits) of \(inside) pixels") }
            // The ears: a point on each ear's centre line, four fifths of the way up, which is the ear's outer rim, clear of the inner ear. Patches and Mocha have
            // an ear of each colour, Latte and Cloud dark ears on a light head.
            let earsWant = (want["ears"] as! [[NSNumber]]).map { $0.map(\.doubleValue) }
            for (i, e) in L.ears.enumerated() {
                let ey = -0.8 * e.h + 0.475 * e.tip
                let wx = L.head.x + e.bx - ey * sin(e.rot), wy = L.head.y + e.by + ey * cos(e.rot), c = colour(px, wx, wy)
                if !isColour(c, earsWant[i]) { flatBad.append("\(id): ear \(i) is \(c), not its flat colour \(earsWant[i])") }
            }
            // The ruff: its flat colour is on the screen.
            if let ruff = want["ruff"] as? [NSNumber] {
                let rw = ruff.map(\.doubleValue)
                var n = 0
                for y in 0..<(side * S) { for x in 0..<(side * S) where isColour(colour(px, (Double(x) + 0.5) / Double(S), (Double(y) + 0.5) / Double(S)), rw) { n += 1 } }
                if n < 40 { flatBad.append("\(id): the ruff's flat colour covers only \(n) pixels") }
            }
            // The tabby's crown band: an ellipse of the contract's size, in the stripe colour at the contract's alpha. Two points on the row 0.08 R under its centre:
            // inside it (0.62 of its half-width) the head and the stripe mixed by the alpha, outside it (1.25 of it, still on the head) the plain flat head.
            if p.coat == "tabby" {
                tabbies += 1
                let crown = flatFill["crown"] as! [String: Any], cw = num(crown["rx"]), a = num(crown["alpha"]), y = L.head.y + (-0.88 + 0.08) * R1
                let mixed = zip(headWant, hexRGB(p.stripe ?? "#000000")).map { lerp($0, $1, a) }
                for sd in [-1.0, 1.0] {
                    let inCrown = colour(px, L.head.x + sd * 0.62 * cw * R1, y), outCrown = colour(px, L.head.x + sd * 1.25 * cw * R1, y)
                    if !isColour(inCrown, mixed, tol: 2.5) { flatBad.append("\(id): inside the crown band \(inCrown) is not the stripe at alpha \(a) over the head, \(mixed)") }
                    if !isColour(outCrown, headWant) { flatBad.append("\(id): outside the crown band \(outCrown) is not the flat head \(headWant)") }
                }
            }
            // The point mask: an ellipse of the contract's size, in the coat's point colour at the contract's alpha, at the centre the gradient had. On the forehead
            // between the eyes (x = 0), 0.75 of its height above its centre is inside it and 1.25 above is outside; on the row 0.63 of its height below the centre,
            // under the eyes, where it is 0.78 of its width wide, 0.75 of that is inside it and halfway from there to the edge of the head is outside it.
            if p.coat == "point" {
                points += 1
                let mask = flatFill["point"] as! [String: Any], mw = num(mask["rx"]), mh = num(mask["ry"]), a = num(mask["alpha"])
                let mixed = zip(headWant, rgb(want["point"])).map { lerp($0, $1, a) }
                let my = -sin(p.nosePh) * p.ry - 0.12, half = mw * (1 - 0.63 * 0.63).squareRoot()
                let headHalf = p.rx * pow(1 - pow(abs((my + 0.63 * mh) / p.ry), p.n), 1 / p.n), far = (half + headHalf) / 2   // the head's half-width on that row, from its outline
                var probes: [(String, Double, Double, Bool)] = [("above", 0, my - 0.75 * mh, true), ("far above", 0, my - 1.25 * mh, false)]
                for sd in [-1.0, 1.0] { probes += [("beside", sd * 0.75 * half, my + 0.63 * mh, true), ("far beside", sd * far, my + 0.63 * mh, false)] }
                for (label, x, y, isIn) in probes {
                    let c = colour(px, L.head.x + x * R1, L.head.y + y * R1)
                    if !isColour(c, isIn ? mixed : headWant, tol: isIn ? 2.5 : 1.5) { flatBad.append("\(id): \(label) the point mask \(c) is not \(isIn ? "the point colour at alpha \(a) over the head, \(mixed)" : "the flat head \(headWant)")") }
                }
            }
        }
        CT.check("every coat's flat head, ears and ruff, the \(tabbies) tabbies' crown band and the \(points) point cats' mask reach the drawing", flatBad, [])

        CT.section("every compact cat wears the compact ear scale, and the fit multiplies it: earScale(D) * f (A-0b, merged `6adf584`)")
        let noodle = CatPresets.byID("noodle")
        var hop = CatPose(); hop.earU = 1.4; hop.oy = -0.3; hop.tilt = 0.24
        func drawnAt(_ D: Double, _ o: CatDrawOptions = CatDrawOptions()) -> G.Layout {
            var layout: G.Layout?
            _ = render(80, 80) { layout = R.draw($0, CatLook(preset: noodle, pose: hop), cx: 40, cy: 16, D: D, o) }
            return layout!
        }
        func laidOut(_ D: Double, _ ek: Double) -> G.Layout { G.layout(noodle, hop, cx: 40, cy: 16, D: D, G.Options(earScale: ek)) }
        for D in [12.0, 20, 24, 27.999] { CT.checkNear("Ø\(D) is drawn with the compact ear scale \(G.earScale(D))", drawnAt(D).ears[0].h, laidOut(D, G.earScale(D)).ears[0].h) }
        for D in [28.0, 44, 66] { CT.checkNear("Ø\(D) is drawn with full-size ears", drawnAt(D).ears[0].h, laidOut(D, 1).ears[0].h) }
        CT.checkNear("drawn at full detail, a small cat keeps its full-size ears (scale 1)", drawnAt(20, CatDrawOptions(full: true)).ears[0].h, laidOut(20, 1).ears[0].h)
        CT.checkTrue("and it is the full cat", drawnAt(20, CatDrawOptions(full: true)).full && !drawnAt(20).full)
        let fit = G.earFit(laidOut(20, G.earScale(20)), hop, ceiling: 0)
        CT.checkTrue("this pose needs the fit (\(fit))", fit < 1 && fit > 0.35)
        CT.checkNear("under a ceiling the ears are earScale(D) * f", drawnAt(20, CatDrawOptions(earCeiling: 0)).ears[0].h, laidOut(20, G.earScale(20) * fit).ears[0].h)

        CT.section("ear headroom: in the compact notch no ear leaves the strip, and a shrunk ear sits exactly on the fit's margin")
        // A 32 pt strip with the cat in the middle, Ø20, drawn into a bitmap with 20 px of padding above the strip's top edge. The margin and the minimum are the fixture's.
        let pad = 20, strip = 32, fitFixture = geo["earFit"] as! [String: Any], margin = num(fitFixture["margin"]), minimum = num(fitFixture["minimum"])
        var worst = 0, shrunk = 0, headroom: [String] = []
        for (earU, oy, tilt) in [(1.0, 0.0, 0.0), (1.4, 0.0, 0.0), (1.4, -0.26, 0.0), (1.22, -0.26, 0.0), (1.4, -0.3, 0.24), (1.4, -0.3, -0.24)] {
            var s = CatPose(); s.earU = earU; s.oy = oy; s.tilt = tilt
            for id in ["momo", "shrimpy", "noodle", "puff", "button"] {
                let look = CatLook(preset: CatPresets.byID(id), pose: s), cy = Double(pad) + Double(strip) / 2
                var fitted: G.Layout?, bare: G.Layout?
                let px = render(120, pad + strip) { cg in
                    fitted = R.draw(cg, look, cx: 40, cy: cy, D: 20, CatDrawOptions(earCeiling: Double(pad)))
                }
                _ = render(120, pad + strip) { cg in bare = R.draw(cg, look, cx: 40, cy: cy, D: 20) }
                for y in 0..<pad { for x in 0..<120 { worst = max(worst, alpha(px, x, y, 120)) } }
                // The geometry the renderer fitted, against the same cat drawn without a ceiling: a calm cat keeps its ears, and a shrunk ear has its top on the margin.
                let ratio = fitted!.ears[0].h / bare!.ears[0].h, at = "\(id) earU \(earU) oy \(oy) tilt \(tilt)"
                if earU == 1 && oy == 0 && tilt == 0 && ratio != 1 { headroom.append("\(at): a calm cat keeps its ears, not \(ratio) of them") }
                if ratio < 1 - 1e-9 {
                    shrunk += 1
                    let top = fitted!.ears.map { earTop(fitted!, s, $0) }.min()! - Double(pad)
                    if ratio > minimum + 1e-6 && abs(top - margin) > 1e-3 { headroom.append("\(at): the top of the ears is \(top) under the strip's top, not on the margin \(margin)") }
                }
            }
        }
        CT.check("5 coats, 6 poses: a calm cat keeps its ears, and a shrunk ear sits on the margin \(margin)", headroom, [])
        CT.checkTrue("the hop pushes ears out of the strip, so the fit has work to do (\(shrunk) cases)", shrunk > 5)
        CT.checkTrue("nothing above the strip is painted more than a hair (worst alpha \(worst) of 255)", worst <= 160)

        CT.section("the engine drives the renderer: every state and emote on every coat, a few frames each")
        var engineBlank: [String] = [], nonFinite: [String] = [], sawBall = false, sawParticle = false
        for id in CatPresets.ids {
            for profile in ["playful", "classic"] {
                for start in CatState.allCases.map({ "state:" + $0.rawValue }) + ["emote:love", "emote:happy", "emote:surprised", "emote:proud", "emote:wink", "emote:yawn", "emote:annoyed", "emote:hello", "emote:zoomies", "emote:hairball"] {
                    let clock = FakeClock(), rng = CatRNG(seed: 5)
                    let e = CatEngine(CatPresets.byID(id), now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(motion: profile), quiet: true)
                    let L0 = CatGeometry.layout(e.p, e.s, cx: 0, cy: 0, D: 120)
                    e.base = L0.base; e.mouthPoint = L0.mouth
                    if start.hasPrefix("state:") { e.setState(CatState(rawValue: String(start.dropFirst(6)))!) } else { e.emote(String(start.dropFirst(6))) }
                    for frame in 1...150 {
                        clock.t += 1000.0 / 60
                        e.update(dt: 1.0 / 60)
                        if frame % 50 != 0 { continue }
                        if !PoseKey.allCases.allSatisfy({ e.s[$0].isFinite }) { nonFinite.append("\(id) \(profile) \(start) frame \(frame)") }
                        let px = render(240, 240) { R.draw($0, e.look(time: clock.t / 1000), cx: 120, cy: 130, D: 120, CatDrawOptions(glow: true)) }
                        if coverage(px) == 0 { engineBlank.append("\(id) \(profile) \(start) frame \(frame)") }
                        if !e.balls.isEmpty { sawBall = true }
                        if !e.parts.isEmpty { sawParticle = true }
                    }
                }
            }
        }
        CT.check("no state or emote leaves the pose non-finite", nonFinite, [])
        CT.check("nothing came out blank", engineBlank, [])
        CT.checkTrue("a hairball and particles were on screen at some point", sawBall && sawParticle)
        CT.section("the launch greeting draws at every moment, whether it runs its course, is cut short or is held open")
        do {
            let clock = FakeClock(), rng = CatRNG(seed: 4)
            func frame(_ t: Double, leave: Double) -> [UInt8] {
                clock.t = t * 1000
                let e = CatEngine(CatPresets.byID("shrimpy"), now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(), quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: t, leave: leave, engine: e, end: CatGreeting.Compact()) }
            }
            var blanks: [String] = []
            for leave in [CatGreeting.GT.leave, 1.0, 2.0, .infinity] {
                for step in stride(from: 0.0, through: 6.0, by: 0.1) where Bitmap.coverage(frame(step, leave: leave)) == 0 && step > 0.5 && step < 5.6 { blanks.append("leave \(leave) at \(step)") }
            }
            CT.check("no moment of the greeting is blank (leave at 4.9 s, at 1 s, at 2 s, and held open)", blanks, [])
            let settled = frame(3.8, leave: CatGreeting.GT.leave)
            CT.checkTrue("the cat sits in the middle at 3.8 s", Bitmap.alpha(settled, 320, 90, 640) > 200)
            CT.checkTrue("the header text is there at 2 s, on the left and on the right", { let f = frame(2, leave: CatGreeting.GT.leave); return (0..<30).contains { y in (20..<120).contains { Bitmap.alpha(f, $0, y, 640) > 100 } } && (0..<30).contains { y in (480..<620).contains { Bitmap.alpha(f, $0, y, 640) > 100 } } }())
            let end = frame(5.7, leave: CatGreeting.GT.leave)
            CT.checkTrue("at the end the cat is at the notch, 40 pt from the island's left edge, and the middle is empty", Bitmap.alpha(end, 320 - 144 + 40, 16, 640) > 200 && Bitmap.alpha(end, 320, 75, 640) == 0)
            let early = frame(1.0 + 0.5, leave: 1.0)
            CT.checkTrue("cut short at 1 s, the cat is already on its way to the notch", Bitmap.coverage(early) > 0)
        }
        CT.section("the greeting's last beat: the row, the glide and the fourth cat on every coat, and the last frame is the real compact grid")
        do {
            let clock = FakeClock(), rng = CatRNG(seed: 4)
            func frame(_ id: String, _ t: Double, leave: Double, end: CatGreeting.Compact = CatGreeting.Compact()) -> [UInt8] {
                clock.t = t * 1000
                let e = CatEngine(CatPresets.byID(id), now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(), quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: t, leave: leave, engine: e, end: end) }
            }
            /// What is painted in the right half of the canvas: once the island has folded the greeting's cat sits on the left and the session cats on the right.
            func right(_ px: [UInt8]) -> Int { (0..<150).reduce(0) { n, y in n + (320..<640).filter { alpha(px, $0, y, 640) > 8 }.count } }
            var blanks: [String] = []
            for id in CatPresets.ids {
                for leave in [CatGreeting.GT.leave, 1.0] {
                    for (what, after) in [("the row", 0.6), ("mid-glide", 1.1), ("the grid", 1.6)] where right(frame(id, leave + after, leave: leave)) == 0 { blanks.append("\(id), leave \(leave), \(what)") }
                }
            }
            CT.check("every coat's session cats are on screen in the row, mid-glide and in the grid, whether the greeting runs its course or is cut short", blanks, [])
            let grown = right(frame("shrimpy", CatGreeting.GT.leave + 1.6, leave: CatGreeting.GT.leave)), row = right(frame("shrimpy", CatGreeting.GT.leave + 0.6, leave: CatGreeting.GT.leave))
            CT.checkTrue("four cats paint more than three (\(grown) against \(row) pixels)", grown > row)

            // The last frame is the compact island's real grid. CompactMiniGrid: a 28 x 28 frame centred at (width - 40, height / 2) and scaled about its
            // middle by miniGridScale, with four cells 16 apart, each a MiniBotCanvasView: a cat of head width 20 * 0.6 = 12 in the middle of its cell.
            for (w, h) in [(288.0, 32.0), (344, 38), (240, 24)] {
                let end = CatGreeting.Compact(width: w, height: h), layout = IslandRestingLayout(width: CGFloat(w), height: CGFloat(h)), k = Double(layout.miniGridScale)
                let got = frame("shrimpy", CatGreeting.greetEnd + 0.3, leave: CatGreeting.GT.leave, end: end)
                let want = render(640, 150) { cg in
                    cg.translateBy(x: 320 - w / 2 + Double(layout.miniGridCenterX), y: Double(layout.botCenterY))
                    cg.scaleBy(x: k, y: k)
                    for (dx, dy) in [(-8.0, -8.0), (8, -8), (-8, 8), (8, 8)] {
                        var pose = CatPose(); pose.tint = 0.6
                        R.draw(cg, CatLook(preset: CatPresets.byID("shrimpy"), pose: pose, color: [127, 180, 234]), cx: dx, cy: dy, D: 12, CatDrawOptions(badge: false))
                    }
                }
                var worst = 0
                for y in 0..<150 { for x in 320..<640 { worst = max(worst, abs(alpha(got, x, y, 640) - alpha(want, x, y, 640))) } }
                CT.checkTrue("\(Int(w)) x \(Int(h)): the greeting's last frame is the real compact grid, pixel for pixel (worst alpha difference \(worst) of 255, \(coverage(want)) pixels painted)", worst <= 2 && coverage(want) > 100)
            }
        }

        CT.section("the greeting's session cats wear the coats they are given (the cast's), and the Main cat when they are given none")
        do {
            func grid(_ engineCoat: String, _ sessions: [String]?) -> [UInt8] {
                let e = CatEngine(CatPresets.byID(engineCoat), now: { 0 }, rand: { 0.5 }, cfg: CatConfig(), quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: CatGreeting.greetEnd + 0.3, leave: CatGreeting.GT.leave, engine: e, end: CatGreeting.Compact(), sessions: sessions) }
            }
            func right(_ px: [UInt8]) -> [UInt8] { (0..<150).flatMap { y in (320..<640).flatMap { x in (0..<4).map { px[(y * 640 + x) * 4 + $0] } } } }
            CT.checkTrue("no sessions is the engine's coat four times, as the greeting always drew", right(grid("shrimpy", nil)) == right(grid("shrimpy", ["shrimpy", "shrimpy", "shrimpy", "shrimpy"])))
            CT.checkTrue("four Momos in the grid are the same pixels as a Momo greeting's grid, whoever falls in", right(grid("shrimpy", Array(repeating: "momo", count: 4))) == right(grid("momo", nil)))
            CT.checkTrue("and they differ from four Shrimpies", right(grid("shrimpy", Array(repeating: "momo", count: 4))) != right(grid("shrimpy", nil)))
            let mixed = right(grid("shrimpy", ["momo", "ginger", "shrimpy", "latte"]))
            CT.checkTrue("each cell has its own coat: a mixed grid is none of the uniform ones", mixed != right(grid("shrimpy", nil)) && mixed != right(grid("shrimpy", Array(repeating: "momo", count: 4))))
            CT.checkTrue("a list that is too short leaves the rest to the engine's coat", right(grid("shrimpy", ["momo"])) != right(grid("shrimpy", nil)) && right(grid("shrimpy", [])) == right(grid("shrimpy", nil)))
        }

        CT.section("Two cats mode: the greeting's second cat pops in beside the settled one, and without a pair nothing is there")
        do {
            let two = CatGreeting.Compact(width: 288, height: 32, botInset: 30)
            func settle(_ pair: String?, _ after: Double) -> [UInt8] {
                let e = CatEngine(CatPresets.byID("shrimpy"), now: { 0 }, rand: { 0.5 }, cfg: CatConfig(), quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: CatGreeting.GT.leave + after, leave: CatGreeting.GT.leave, engine: e, end: two, pair: pair) }
            }
            let x2 = 320 - 144 + 30 + 24
            CT.checkTrue("0.8 s into the fold the second cat is there, 24 pt beside the first", alpha(settle("momo", 0.8), x2, 16, 640) > 200 && alpha(settle(nil, 0.8), x2, 16, 640) == 0)
            CT.checkTrue("and the first cat is where the pair's first cat lives, 30 pt from the island's edge", alpha(settle("momo", 0.8), 320 - 144 + 30, 16, 640) > 200)
            CT.checkTrue("it has not popped in when the fold begins", settle("momo", 0.1) == settle(nil, 0.1))
            CT.checkTrue("a different coat is a different cat", settle("momo", 0.8) != settle("ginger", 0.8))
        }

        CT.section("the greeting's session cats wear collars in the prototype's colours when a style is set, and none by default")
        do {
            func stand(_ style: String?) -> [UInt8] {
                let cfg = CatConfig()
                if let style { cfg.collar = style }
                let e = CatEngine(CatPresets.byID("shrimpy"), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: CatGreeting.greetEnd + 0.3, leave: CatGreeting.GT.leave, engine: e, end: CatGreeting.Compact()) }
            }
            let plainRow = stand(nil)
            CT.checkTrue("off is what the greeting always drew", stand("off") == plainRow)
            for style in ["tag", "band", "kerchief"] { CT.checkTrue("\(style): the four cats in the grid have collars", stand(style) != plainRow) }
        }

        CT.section("fur lines: off by default, and drawn only on a big full-detail cat that has fur")
        func fur(_ id: String, _ D: Double, on: Bool, full: Bool? = nil) -> [UInt8] {
            render(300, 300) { R.draw($0, CatLook(preset: CatPresets.byID(id)), cx: 150, cy: 150, D: D, CatDrawOptions(full: full, fur: on)) }
        }
        let plain = render(300, 300) { R.draw($0, CatLook(preset: CatPresets.byID("shrimpy")), cx: 150, cy: 150, D: 140) }
        CT.checkTrue("plain flat colour is the default", fur("shrimpy", 140, on: false) == plain)
        CT.checkTrue("Shrimpy at Ø140 looks different with fur lines, ruff included", fur("shrimpy", 140, on: true) != plain)
        CT.checkTrue("Momo too (her white map has strand colours of its own)", fur("momo", 140, on: true) != fur("momo", 140, on: false))
        CT.checkTrue("the same fur draws the same pixels twice", fur("momo", 140, on: true) == fur("momo", 140, on: true))
        CT.checkTrue("below a head radius of 30 px nothing changes", fur("shrimpy", 56, on: true) == fur("shrimpy", 56, on: false))
        CT.checkTrue("at the compact detail nothing changes", fur("shrimpy", 140, on: true, full: false) == fur("shrimpy", 140, on: false, full: false))
        CT.checkTrue("Noodle has no fur, so nothing changes", fur("noodle", 140, on: true) == fur("noodle", 140, on: false))

        CT.section("the collar: drawn in the front pass from Ø12 up, readable at every size, turning with the head, and the coat is never recoloured")
        let green = "#00FF66"   // no coat is anywhere near it, so the pixels of the collar can be counted
        func collared(_ id: String, _ D: Double, _ style: String?, dpr: Double = 2, yaw: Double = 0) -> [UInt8] {
            let n = Int(D * 3 * dpr)
            var s = CatPose(); s.yaw = yaw
            return render(n, n) { cg in
                cg.scaleBy(x: dpr, y: dpr)
                var o = CatDrawOptions(); o.collar = style.map { CatCollarPaint(style: $0, color: green, dpr: dpr) }
                R.draw(cg, CatLook(preset: CatPresets.byID(id), pose: s), cx: D * 1.5, cy: D * 1.5, D: D, o)
            }
        }
        /// The painted pixels that are green: the collar's colour or its tint (the tag is a lighter tint), which no coat has.
        func ink(_ px: [UInt8]) -> [(x: Int, y: Int)] {
            let w = Int(Double(px.count / 4).squareRoot())
            return stride(from: 0, to: px.count, by: 4).filter { px[$0 + 3] > 200 && px[$0 + 1] > 150 && px[$0] < 170 && px[$0 + 2] < 200 }.map { (($0 / 4) % w, ($0 / 4) / w) }
        }
        let plainCat = collared("shrimpy", 20, nil), none = CatDrawOptions().collar == nil
        CT.checkTrue("no collar is the default", none && collared("shrimpy", 20, nil) == plainCat)
        CT.checkTrue("off, and a style nobody knows, paint nothing", collared("shrimpy", 20, "off") == plainCat && collared("shrimpy", 20, "scarf") == plainCat)
        // The least ink a style may leave at Ø12 on any of these coats, at 1x and at 2x (measured with the contract's floors: a band 3 device px thick, a tag
        // 6 across, a neckerchief 7 wide and 5 deep; the neckerchief's dark edge eats most of a triangle that small, so it has the least).
        let least: [String: (Int, Int)] = ["band": (20, 45), "tag": (24, 50), "kerchief": (4, 10)]
        var weak: [String] = [], recoloured: [String] = []
        for id in ["shrimpy", "momo", "latte", "midnight", "snow", "puff"] {
            for style in ["tag", "band", "kerchief"] {
                for D in [12.0, 16, 20, 28, 44, 66] {
                    for dpr in [1.0, 2] {
                        let on = collared(id, D, style, dpr: dpr), off = collared(id, D, nil, dpr: dpr), n = ink(on).count
                        if D == 12 && n < (dpr == 1 ? least[style]!.0 : least[style]!.1) { weak.append("\(id) \(style) Ø12 at \(Int(dpr))x: \(n) pixels") }
                        if D > 12 && n == 0 { weak.append("\(id) \(style) Ø\(Int(D)) at \(Int(dpr))x: none") }
                        // Above the head's middle (a fifth of the head width above it, because a band 3 px thick at Ø12 reaches the middle row) nothing
                        // differs: the collar sits on the lower head, and the coat is never recoloured.
                        let w = Int(D * 3 * dpr), top = Int((D * 1.5 - D * 0.2) * dpr) * w * 4
                        if Array(on[0..<top]) != Array(off[0..<top]) { recoloured.append("\(id) \(style) Ø\(Int(D)) at \(Int(dpr))x") }
                    }
                }
            }
        }
        CT.checkRows("every style on six coats at Ø12 to Ø66 and at 1x and 2x leaves enough ink (Ø12 at the contract's floors)", weak)
        CT.checkRows("the upper half of the head is the same with and without a collar", recoloured)
        let straight = ink(collared("shrimpy", 66, "band")), turned = ink(collared("shrimpy", 66, "band", yaw: 0.6))
        let midStraight = Double(straight.map(\.x).reduce(0, +)) / Double(straight.count), midTurned = Double(turned.map(\.x).reduce(0, +)) / Double(turned.count)
        CT.checkTrue("the collar turns with the head (its middle moves from \(Int(midStraight)) to \(Int(midTurned)) px)", abs(midTurned - midStraight) > 3)
        let rendererText = (try? String(contentsOfFile: "NotchBuddy/Sources/App/CatRenderer.swift", encoding: .utf8)) ?? ""
        func at(_ s: String) -> Int { rendererText.range(of: s)?.lowerBound.utf16Offset(in: rendererText) ?? -1 }
        CT.checkTrue("the collar is drawn after the folded ears and before the whiskers (source pin)", at("front: true, flat") > 0 && at("front: true, flat") < at("drawCollar") && at("drawCollar") < at("CatFace.drawWhiskers"))

        // B: the coloured small eyes (CatSmallEye is the geometry; the colours are the renderer's). A cat is drawn at 8 pixels to the point, so the iris
        // covers whole pixels, and the eye is found from the layout the draw returns.
        CT.section("a compact cat's resting eyes are coloured: the iris is the coat's iris colour, on all 16 coats, as cats and as kittens, at Ø12 to Ø24 (the black coats' is flat)")
        let S8 = 8.0, side8 = 60
        func eyeLook(_ p: CatPreset, _ pose: CatPose = CatPose(), _ eye: CatEye = .pill, ink: Bool = false) -> CatLook {
            var l = CatLook(preset: p, pose: pose, eye: eye); l.inkEyes = ink; return l
        }
        func eyeSheet(_ look: CatLook, _ D: Double) -> (px: [UInt8], L: CatGeometry.Layout) {
            var laid: CatGeometry.Layout?
            let px = render(side8 * Int(S8), side8 * Int(S8)) { cg in
                cg.scaleBy(x: S8, y: S8)
                laid = R.draw(cg, look, cx: 30, cy: 30, D: D, CatDrawOptions(tint: false, badge: false))
            }
            return (px, laid!)
        }
        func rgbAt(_ px: [UInt8], _ x: Double, _ y: Double) -> [Double] {
            let i = (Int(y.rounded(.down)) * side8 * Int(S8) + Int(x.rounded(.down))) * 4
            return [Double(px[i]), Double(px[i + 1]), Double(px[i + 2])]
        }
        var wrongIris: [String] = []
        for id in CatPresets.ids {
            for kitten in [false, true] {
                let base = CatPresets.byID(id), p = kitten ? CatPresets.kitten(of: base) : base
                for D in [12.0, 16, 20, 24] {
                    let sheet = eyeSheet(eyeLook(p), D)
                    for e in sheet.L.eyes {
                        let g = CatSmallEye.eye(.pill, sd: e.sd, R: sheet.L.R, es: 1, open: 1, kitten: kitten, cat: id)!, i = g.iris!
                        let ir = (e.sd > 0 ? p.irisR : nil) ?? p.iris, a = hexRGB(ir[0]), b = hexRGB(ir[1]), t = 0.6 * i.rx / i.r
                        let want = g.flat == true ? hexRGB(CatSmallEye.flatIris(ir)) : (0..<3).map { lerp(a[$0], b[$0], t) }
                        let got = rgbAt(sheet.px, (sheet.L.head.x + e.x + 0.6 * i.rx) * S8, (sheet.L.head.y + e.y) * S8)
                        if zip(got, want).contains(where: { abs($0 - $1) > 14 }) { wrongIris.append("\(id)\(kitten ? " kitten" : "") Ø\(Int(D)) \(e.sd < 0 ? "left" : "right"): got \(got.map { Int($0) }), want \(want.map { Int($0) })") }
                    }
                }
            }
        }
        CT.checkRows("32 cats at four sizes: both eyes are the coat's iris colour at 0.6 of the iris's half-width (the odd-eyed coats' right eye is irisR; the black coats' is the flat lighter colour)", wrongIris)

        CT.section("the black coats' eyes glow: the iris is one flat colour to its edge, with no dark rim, a thin pupil and the catchlight; a normal coat keeps its rim")
        var notFlat: [String] = []
        for id in CatSmallEye.K.bright {
            for kitten in [false, true] {
                let base = CatPresets.byID(id), p = kitten ? CatPresets.kitten(of: base) : base
                for D in [16.0, 20, 24] {
                    let sheet = eyeSheet(eyeLook(p), D)
                    for e in sheet.L.eyes {
                        let g = CatSmallEye.eye(.pill, sd: e.sd, R: sheet.L.R, es: 1, open: 1, kitten: kitten, cat: id)!, i = g.iris!
                        let want = hexRGB(CatSmallEye.flatIris((e.sd > 0 ? p.irisR : nil) ?? p.iris)), cx = sheet.L.head.x + e.x, cy = sheet.L.head.y + e.y
                        // the right of the pupil, in the middle of the iris and just inside its edge (a rim would be dark there)
                        for f in [0.45, 0.8, 0.9] {
                            let got = rgbAt(sheet.px, (cx + f * i.rx) * S8, cy * S8)
                            if zip(got, want).contains(where: { abs($0 - $1) > 14 }) { notFlat.append("\(id)\(kitten ? " kitten" : "") Ø\(Int(D)) \(e.sd < 0 ? "left" : "right") at \(f): got \(got.map { Int($0) }), want \(want.map { Int($0) })") }
                        }
                    }
                }
            }
        }
        CT.checkRows("Midnight, Oreo and Mocha, as cats and as kittens, at Ø16, 20 and 24: the same flat colour at 0.45, 0.8 and 0.9 of the iris's half-width", notFlat)
        let rimmed = eyeSheet(eyeLook(CatPresets.byID("momo")), 24), mo = rimmed.L.eyes[0], mg = CatSmallEye.eye(.pill, sd: mo.sd, R: rimmed.L.R, es: 1, open: 1, cat: "momo")!.iris!
        let momoEdge = rgbAt(rimmed.px, (rimmed.L.head.x + mo.x + 0.97 * mg.rx) * S8, (rimmed.L.head.y + mo.y) * S8), momoMid = rgbAt(rimmed.px, (rimmed.L.head.x + mo.x + 0.45 * mg.rx) * S8, (rimmed.L.head.y + mo.y) * S8)
        CT.checkTrue("a normal coat (Momo) keeps its dark rim and its gradient: its edge is darker than its middle", momoEdge.reduce(0, +) < momoMid.reduce(0, +) - 40)

        CT.section("the expression shapes stay ink, and only the eyes change")
        var changedInk: [String] = []
        for shape in [CatEye.happy, .closed, .line, .flat, .spiral, .heart, .star] {
            for D in [12.0, 20, 27.9] {
                let p = CatPresets.byID("momo")
                if eyeSheet(eyeLook(p, CatPose(), shape), D).px != eyeSheet(eyeLook(p, CatPose(), shape, ink: true), D).px { changedInk.append("\(shape.rawValue) at Ø\(Int(D))") }
            }
        }
        CT.checkRows("happy, closed, line, flat, spiral, heart and star are the same pixels with and without the coloured eyes", changedInk)
        var strayed: [String] = []
        for id in CatPresets.ids {
            let p = CatPresets.byID(id), now = eyeSheet(eyeLook(p), 20), was = eyeSheet(eyeLook(p, ink: true), 20), L = now.L
            if now.px == was.px { strayed.append("\(id): nothing changed"); continue }
            for k in stride(from: 0, to: now.px.count, by: 4) where now.px[k..<k + 4] != was.px[k..<k + 4] {
                let x = Double(k / 4 % (side8 * Int(S8))) / S8, y = Double(k / 4 / (side8 * Int(S8))) / S8
                // within the eye's own frame, 0.4 of the head's radius around each eye is where the coloured eye and the ink eye can differ
                if !L.eyes.contains(where: { abs(x - (L.head.x + $0.x)) < 0.4 * L.R && abs(y - (L.head.y + $0.y)) < 0.4 * L.R }) { strayed.append("\(id): a pixel at (\(x), \(y))"); break }
            }
        }
        CT.checkRows("on every coat the resting eye's pixels are the only ones that differ, all within 0.4 R of an eye", strayed)

        CT.section("Two cats: cat 1's badge stays inside the card (a left limit for the badge, nil by default)")
        // The expanded overview: cat 1 is Ø58 and its centre is 50 pt from the island's left edge, the card starts 10 pt in. On this canvas the centre is at x = 70, so the card's edge is at 30 and the limit (a 1 pt margin) at 31.
        func badgeOnly(_ id: String, _ kind: CatBadge, side: Double, limit: Double?) -> [UInt8] {
            var pose = CatPose(); pose.badgeS = 1
            var look = CatLook(preset: CatPresets.byID(id), pose: pose); look.badge = kind; look.badgeColor = "#3B9EFF"
            func draw(_ badge: Bool) -> [UInt8] {
                var o = CatDrawOptions(badge: badge); o.badgeSide = side; o.badgeLeftLimit = limit
                return render(140, 120) { R.draw($0, look, cx: 70, cy: 60, D: 58, o) }
            }
            let with = draw(true), without = draw(false)
            var only = [UInt8](repeating: 0, count: with.count)
            for k in stride(from: 0, to: with.count, by: 4) where with[k..<k + 4] != without[k..<k + 4] { only[k + 3] = with[k + 3] }
            return only
        }
        CT.checkTrue("the limit is off by default", CatDrawOptions().badgeLeftLimit == nil)
        var overflow: [String] = [], noEffect: [String] = [], inside: [String] = [], unchanged: [String] = []
        for id in CatPresets.ids {
            for kind in [CatBadge.dots, .bang, .question, .dot] {
                let free = badgeOnly(id, kind, side: -1, limit: nil), held = badgeOnly(id, kind, side: -1, limit: 31)
                if let b = Bitmap.bounds(free, 140), b.left < 30 { overflow.append("\(id) \(kind)") }   // before the fix the badge pokes out of the card on some coat...
                guard let h = Bitmap.bounds(held, 140) else { inside.append("\(id) \(kind): no badge"); continue }
                if h.left < 30 { inside.append("\(id) \(kind): left edge at \(h.left)") }
                if let f = Bitmap.bounds(free, 140), f.left >= 31, free != held { noEffect.append("\(id) \(kind): moved though it fit") }
                if badgeOnly(id, kind, side: -1, limit: -1000) != free || badgeOnly(id, kind, side: 1, limit: nil) != badgeOnly(id, kind, side: 1, limit: -1000) { unchanged.append("\(id) \(kind)") }
            }
        }
        CT.checkTrue("without the limit the badge does poke out of the card at the left (it did, on \(overflow.count) of 64 coat and badge pairs)", overflow.count >= 32)
        CT.checkRows("with the limit no coat's badge (dots, bang, question, dot) reaches past x = 30, the card's edge on this canvas", inside)
        CT.checkRows("a badge that already fits is not moved", noEffect)
        CT.checkRows("a limit far away draws exactly what no limit draws, on the left and on the right (One cat and A cat for each agent are as they ship)", unchanged)
        CT.checkTrue("the badge on the right side is never held by a left limit", badgeOnly("shrimpy", .dots, side: 1, limit: 31) == badgeOnly("shrimpy", .dots, side: 1, limit: nil))

        CT.section("a blink closes the small eye to a line, and the coat's iris colour is gone")
        var blink = CatPose(); blink.open = 0.06
        let shut = eyeSheet(eyeLook(CatPresets.byID("shrimpy"), blink), 20), open = eyeSheet(eyeLook(CatPresets.byID("shrimpy")), 20)
        let e0 = shut.L.eyes[0], g0 = CatSmallEye.eye(.pill, sd: -1, R: shut.L.R, es: 1, open: 1)!.iris!
        let spot = (shut.L.head.x + e0.x + 0.6 * g0.rx, shut.L.head.y + e0.y)
        let iris = hexRGB(CatPresets.byID("shrimpy").iris[0]), shutRGB = rgbAt(shut.px, spot.0 * S8, spot.1 * S8), openRGB = rgbAt(open.px, spot.0 * S8, spot.1 * S8)
        CT.checkTrue("open: green at the spot; shut: not green", abs(openRGB[1] - iris[1]) < 90 && openRGB != shutRGB && shutRGB[1] - shutRGB[0] < 40)
        CT.checkTrue("a blinking cat differs from an open one", shut.px != open.px)

        CT.section("every cat gets them and a full-detail cat keeps its realistic eye: Ø28 is the same pixels with and without the switch")
        CT.checkTrue("Ø28 and Ø66 do not change", [28.0, 66].allSatisfy { eyeSheet(eyeLook(CatPresets.byID("momo")), $0).px == eyeSheet(eyeLook(CatPresets.byID("momo"), ink: true), $0).px })
        CT.finish()
    }
}
