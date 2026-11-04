import Foundation

// The launch greeting: a cat version of Greeting v2, 5.74 s in a 640x150 space. The island grows, the cat falls in with a landing
// squash, bounces, slides aside, pops up for a quick paw wave, slides back, and settles with the badge and the tint; then the island
// collapses to the compact notch. Port of the "Timelines" section of design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/sequence-cases.json pins the timeline, the streaks and the flight of a dropped file.

enum CatGreeting {
    /// The pose at one moment, all in the 640x150 space: island iw x ih, cat centre x, y and head width hb * 1.34, squash sx/sy, tilt,
    /// eye shape, gaze lookX/lookY, paw raise handL/handR, the wave clock (-1 = off), blink `open`, and the 0...1 fades.
    struct Pose: Encodable, Equatable {
        var iw: Double, ih: Double, hb: Double, x: Double, y: Double, sx: Double, sy: Double, tilt: Double
        var eye: String
        var lookX: Double, lookY: Double, handL: Double, handR: Double, wave: Double, open: Double
        /// The badge, the tint, the halo (gold to blue), the header text, the card, the streaks and the session cats.
        var badge: Double, tint: Double, halo: Double, haloBlue: Double, header: Double, card: Double, fx: Double, minis: Double
    }

    static let notchW = 184.0, notchH = 32.0, compact = 288.0

    /// Where the island ends up and where the cat settles in it. The defaults are the contract's (a 288 x 32 island, a Ø20 cat in the middle
    /// of it); the app passes the real compact island of the screen it is on.
    struct Compact {
        var width = CatGreeting.compact, height = CatGreeting.notchH, botCenterY = 16.0, botDiameter = 20.0
        /// How far the settled cat is from the island's left edge: 40 pt, or 30 pt when two cats share the left ear (Two cats mode: `CatIslandLayout.compactX`).
        var botInset = 40.0
        init() {}
        init(width: Double, height: Double, botInset: Double = 40) {
            self.width = width; self.height = height; botCenterY = height / 2; botDiameter = min(20, max(0, height - 6)); self.botInset = botInset
        }
        /// How much the compact island's mini grid shrinks on a strip shorter than 32 pt: `IslandRestingLayout.miniGridScale`, which the compact view uses.
        var miniScale: Double { min(1, max(0, height - 4) / 28) }
    }

    /// The island's beats, shared with the old greeting: when the badge and the tint arrive and when the island leaves.
    enum GT {
        static let grow = 0.45, badge = 2.72, blink2 = 3.8, tint0 = 3.85, tint1 = 4.15, leave = 4.9, collapse = 0.34
    }
    /// The cat's beats: fall, land, bounce, slide aside, pop up and wave, slide back.
    enum GT2 {
        static let fall0 = 0.05, land = 0.62, bounce1 = 1.18, slide0 = 1.25, slide1 = 1.65, pop0 = 1.65, wave0 = 1.72, wave1 = 2.72,
                   back0 = 2.75, back1 = 3.25, slide = 150.0
    }
    static let length = GT.leave + GT.collapse + 0.5
    /// How much of the outfit shows at `t` seconds (sub-project I): none while the cat falls, bounces and waves, then it comes on over a quarter of a second once the cat has slid back and settled.
    static func outfitFade(_ t: Double) -> Double { seg(t, GT2.back1, GT2.back1 + 0.25) }

    // MARK: The last beat: the session cats

    /// The last beat's timings, in seconds after `leave`, the moment the island starts to fold: the row of session cats holds, glides into the
    /// compact island's 2x2 grid, a fourth cat pops into the empty cell, and the greeting ends. Port of GT3 in cat-core.js.
    enum GT3 { static let glide0 = 0.8, glide1 = 1.3, four0 = 1.0, end = 1.6 }
    /// Where the whole greeting, glide included, ends. `length` stays 5.74 s, up to the settled row.
    static let greetEnd = GT.leave + GT3.end

    /// The glide's two progress values: `grid` is the row becoming the grid (0...1), `four` the fourth cat's pop (0...1 and a little over).
    struct Glide: Equatable { var grid: Double, four: Double }

    /// Port of `miniGlide`. Held open (`leave` is infinity) the island has not started to fold, so there is no glide.
    static func miniGlide(_ t: Double, leave: Double = GT.leave) -> Glide {
        guard leave.isFinite else { return Glide(grid: 0, four: 0) }
        return Glide(grid: CatEase.inOut.at(seg(t, leave + GT3.glide0, leave + GT3.glide1)), four: CatEase.back.at(seg(t, leave + GT3.four0, leave + GT3.glide1)))
    }

    /// Two cats mode: how far the second cat's pop-in has got (0 to a little over 1) `t` seconds in, when the island starts to fold at `leave`: it pops in beside the cat
    /// that has settled, from 0.24 s to 0.42 s after the fold begins, with the same overshoot as the session cats. Never (0) while the pointer holds the island open.
    static func pairPop(_ t: Double, leave: Double = GT.leave) -> Double { leave.isFinite ? CatEase.back.at(seg(t, leave + 0.24, leave + 0.42)) : 0 }

    /// The prototype's row: head width, spacing, the first cat's inset from the island's right edge, and how far it sits below the strip's middle (pt).
    static let miniRow = (d: 11.0, step: 14.0, inset: 12.0, dy: 1.0)
    /// The compact island's grid (`CompactMiniGrid`): cells 16 pt between centres, its centre 40 in from the island's right edge, and its cats' head width.
    static let miniCell = (step: 16.0, inset: 40.0, d: 12.0)
    /// Grid cell (top left, top right, bottom left, bottom right) to the row cat that glides into it, 0 being the row's right-most; the bottom left has none.
    static let miniFrom: [Int?] = [2, 1, nil, 0]
    /// A session cat narrower than this is not drawn: the first frames of a pop, or a strip too short to hold it.
    static let miniMinD = 2.0

    /// One session cat: centre and head width in the 640x150 space; d is 0 for a cat that is not there.
    struct Mini: Equatable { var x: Double, y: Double, d: Double }

    /// Port of `miniSlots`: the four session cats in the order of the grid's cells. `minis` is the row's pop-in (`Pose.minis`), `glide` is `miniGlide`,
    /// `width` and `height` the compact island, `d` the grid cat's head width. A strip shorter than 32 pt shrinks everything like `miniGridScale`.
    static func miniSlots(minis: Double, glide g: Glide, width W: Double = compact, height H: Double = notchH, d: Double = miniCell.d) -> [Mini] {
        let k = min(1, max(0, H - 4) / 28), right = 320 + W / 2, gx = right - miniCell.inset, gy = H / 2, s = miniCell.step / 2 * k
        return miniFrom.enumerated().map { i, from in
            let x1 = gx + (i % 2 == 1 ? s : -s), y1 = gy + (i < 2 ? -s : s)
            let x: Double, y: Double, dd: Double
            if let from {
                x = lerp(right - (miniRow.inset + miniRow.step * Double(from)) * k, x1, g.grid)
                y = lerp(gy + miniRow.dy * k, y1, g.grid)
                dd = lerp(miniRow.d, d, g.grid) * minis * k
            } else {
                x = x1; y = y1; dd = d * g.four * k
            }
            return Mini(x: x, y: y, d: dd < miniMinD ? 0 : dd)
        }
    }

    /// Sixteen colour streaks that burst out when the cat lands; seeded, so they are the same everywhere.
    struct Streak: Equatable { var a: Double, sp: Double, len: Double, t0: Double, col: String }
    static let streaks: [Streak] = {
        let r = CatRNG(seed: 7), cols = Theme.Greeting.streaks
        return (0..<16).map { i in
            let a = Double(i) / 16 * CatMath.tau + (r.next() - 0.5) * 0.3
            let sp = 230 + r.next() * 260, len = 6 + r.next() * 9, t0 = 0.08 + r.next() * 0.14
            return Streak(a: a, sp: sp, len: len, t0: t0, col: cols[i % 5])
        }
    }()
    /// Streak time: it starts when the cat lands.
    static func streakTime(_ t: Double) -> Double { t - (GT2.land - 0.1) }

    /// The island and the shared beats: size, blink, badge, tint, halo, header. Everything but the cat's own motion.
    struct Base { var iw: Double, ih: Double, hb: Double, base: Double, open: Double, badge: Double, tint: Double, halo: Double, haloBlue: Double, header: Double, card: Double }

    static func islandBase(_ t: Double) -> Base {
        let gx = seg(t, 0, 0.5), g = sin(Double.pi * gx / 2) + 0.04 * sin(Double.pi * gx) * gx
        let gg = CatEase.back.at(seg(t, 0.02, GT.grow))
        func blink(_ tb: Double) -> Double { let k = seg(t, tb, tb + 0.12); return k > 0 && k < 1 ? 1 - sin(Double.pi * k) * 0.94 : 1 }
        return Base(iw: lerp(notchW, 640, g), ih: lerp(notchH, 150, g), hb: lerp(3, 58, gg), base: lerp(16, 86, CatEase.out.at(seg(t, 0.02, GT.grow))),
                    open: min(blink(1.95), blink(GT.blink2)), badge: CatEase.back.at(seg(t, GT.badge, GT.badge + 0.28)),
                    tint: 0.6 * CatEase.inOut.at(seg(t, GT.tint0, GT.tint1)), halo: CatEase.out.at(seg(t, 0.3, 0.7)), haloBlue: seg(t, GT.tint0, GT.tint1),
                    header: seg(t, 0.35, 0.6), card: seg(t, 0.18, 0.45))
    }

    /// The cat's fall, bounce, slide, pop and wave.
    static func fallPose(_ t: Double, _ B: Base) -> Pose {
        typealias G = GT2
        let hb = B.hb, D = hb * 1.34, base = B.base
        var x = 320.0, y = base, sx = 1.0, sy = 1.0, tilt = 0.0, eye = "dot", lookX = 0.0, lookY = 0.0, wave = -1.0
        let fall = seg(t, G.fall0, G.land)
        y -= (1 - fall * fall) * (base + 70)                                                            // 1 fall in (accelerating)
        let sq = sin(Double.pi * seg(t, G.land, G.land + 0.16))
        sy -= 0.2 * sq; sx += 0.14 * sq; y += D * 0.05 * sq                                              // landing squash
        let b = seg(t, G.land + 0.16, G.bounce1)
        y -= 4 * b * (1 - b) * hb * 0.3; sy += 0.05 * sin(Double.pi * b)                                // 2 small bounce
        let sq2 = sin(Double.pi * seg(t, G.bounce1, G.bounce1 + 0.1))
        sy -= 0.07 * sq2; sx += 0.05 * sq2; y += D * 0.02 * sq2
        let out = CatEase.inOut.at(seg(t, G.slide0, G.slide1)), ret = CatEase.inOut.at(seg(t, G.back0, G.back1))   // 3 slide aside, 5 slide back
        x += G.slide * out * (1 - ret)
        tilt = 0.1 * sin(Double.pi * seg(t, G.slide0, G.slide1)) - 0.1 * sin(Double.pi * seg(t, G.back0, G.back1))
        let ant = sin(Double.pi * seg(t, G.pop0 - 0.1, G.pop0))
        sy -= 0.08 * ant; y += D * 0.03 * ant                                                            // 4 pop up
        let pop = CatEase.back.at(seg(t, G.pop0, G.pop0 + 0.2)) * (1 - CatEase.inOut.at(seg(t, G.back0, G.back0 + 0.2)))
        y -= hb * 0.16 * pop; sy += 0.07 * sin(Double.pi * seg(t, G.pop0, G.pop0 + 0.2))
        let flail = 0.55 * (1 - seg(t, G.land - 0.05, G.land + 0.1)) * (t > G.fall0 ? 1 : 0)             // paws up while falling
        let handL = flail, handR = max(flail, pop)
        if t >= G.wave0 && t < G.wave1 + 0.2 { wave = t - G.wave0 }
        if t >= G.land && t < G.slide0 { eye = "happy" }
        if t >= G.slide0 && t < G.pop0 { lookX = 0.5 * out }
        if t >= G.pop0 && t < G.back0 { eye = "happy"; lookX = 0.3; lookY = -0.4 }
        if t >= G.back0 {
            let k = seg(t, G.back0, G.back1 + 0.1)
            eye = k < 0.9 ? "content" : "dot"
            lookX = lerp(0.3, 0, CatEase.inOut.at(k)); lookY = lerp(-0.4, 0, CatEase.inOut.at(k))
        }
        return Pose(iw: B.iw, ih: B.ih, hb: hb, x: x, y: y, sx: sx, sy: sy, tilt: tilt, eye: eye, lookX: lookX, lookY: lookY, handL: handL, handR: handR, wave: wave,
                    open: B.open, badge: B.badge, tint: B.tint, halo: B.halo, haloBlue: B.haloBlue, header: B.header, card: B.card, fx: 1, minis: 0)
    }

    /// After `leave` the island collapses to the compact notch and the cat settles. When `leave` is the timeline's 4.9 s the cat is already at
    /// rest and this is the contract; an earlier `leave` (the pointer left mid-greeting) carries the cat's pose to rest on the way.
    static func collapsePose(_ t: Double, leave tc: Double = GT.leave, into end: Compact = Compact()) -> Pose {
        let a = islandBase(tc), from = fallPose(tc, a)
        let e = CatEase.inOut.at(seg(t, tc, tc + GT.collapse)), bx = 320 - end.width / 2 + end.botInset, bk = seg(t, tc + 0.14, tc + 0.26)
        let hands = 1 - seg(t, tc, tc + 0.15)
        return Pose(iw: lerp(a.iw, end.width, e), ih: lerp(a.ih, end.height, e), hb: lerp(a.hb, end.botDiameter / 1.34, e), x: lerp(from.x, bx, e), y: lerp(from.y, end.botCenterY, e),
                    sx: lerp(from.sx, 1, e), sy: lerp(from.sy, 1, e), tilt: lerp(from.tilt, 0, e), eye: "dot", lookX: lerp(from.lookX, 0, e), lookY: lerp(from.lookY, 0, e),
                    handL: from.handL * hands, handR: from.handR * hands, wave: from.wave,
                    open: bk > 0 && bk < 1 ? 1 - sin(Double.pi * bk) * 0.94 : 1, badge: a.badge, tint: a.tint, halo: a.halo * (1 - e), haloBlue: a.haloBlue,
                    header: a.header * (1 - seg(t, tc, tc + 0.1)), card: a.card * (1 - seg(t, tc, tc + 0.18)), fx: 1 - seg(t, tc, tc + 0.2),
                    minis: CatEase.back.at(seg(t, tc + 0.24, tc + 0.42)))
    }

    /// The greeting pose at t seconds (0 ... `length`). `leave` is when the island starts to collapse: 4.9 s by itself, earlier when the
    /// pointer leaves, never (infinity) while the pointer holds the island open.
    static func pose(_ t: Double, leave: Double = GT.leave, into end: Compact = Compact()) -> Pose {
        t < leave ? fallPose(t, islandBase(t)) : collapsePose(t, leave: leave, into: end)
    }

    // MARK: A dropped file's flight

    /// Where a file is k (0...1) of the way along its arc from `from` to `to`, how big it is and how it is turned.
    static func flightAt(from: (x: Double, y: Double), to: (x: Double, y: Double), R: Double, k: Double) -> (x: Double, y: Double, size: Double, rot: Double) {
        let q = CatEase.inOut.at(k), cx = (from.x + to.x) / 2, cy = min(from.y, to.y) - 60, u = 1 - q
        return (u * u * from.x + 2 * u * q * cx + q * q * to.x, u * u * from.y + 2 * u * q * cy + q * q * to.y, lerp(R * 0.62, R * 0.14, q), (1 - q) * 0.5 - 0.25)
    }
}
