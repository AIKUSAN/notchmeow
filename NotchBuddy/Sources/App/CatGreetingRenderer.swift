import CoreGraphics
import Foundation

/// Draws the launch greeting into a 640x150 canvas: the halo, the streaks, the header, the cat (with paws for hands) and the little
/// session cats. The island's black shape is the app's own (IslandContainer); this draws inside it. The pose comes from `CatGreeting`.
@MainActor
enum CatGreetingRenderer {
    typealias Greeting = CatGreeting

    /// Draws the greeting at `t` seconds. `engine` is the cat's engine (it blinks and flicks an ear by itself, and has been updated for this frame);
    /// `leave` is when the island starts to collapse (infinity while the pointer holds it open); `end` is the compact island it collapses into. `sessions` are the
    /// coats of the four session cats in the grid's cell order (the cast's `greeting.sessions`: in A cat for each agent mode the agents' own cats, so the glide hands over
    /// to the real grid without a change); nil: all four wear the engine's coat, the Main cat. `pair`: in Two cats mode the coat of the second cat of the pair, which pops in
    /// beside the settled one (give `end` a `botInset` of 30, where the pair's first cat lives); nil: no second cat.
    static func draw(_ cg: CGContext, t: Double, leave: Double, engine e: CatEngine, end: Greeting.Compact, sessions: [String]? = nil, pair: String? = nil) {
        let P = Greeting.pose(t, leave: leave, into: end), X = P.x, Y = P.y, D = P.hb * 1.34, p = e.p
        let st = Greeting.streakTime(t)
        if P.halo > 0 {
            let bl = P.haloBlue, c = (0..<3).map { lerp(Theme.Greeting.haloGoldRGB[$0], Theme.Greeting.haloBlueRGB[$0], bl).rounded() }
            for (rad, al) in [(D * 1.3, 0.18), (D * 2.1, 0.07)] {
                CatDraw.radial(cg, [(0, CatDraw.rgb(c, al * P.halo)), (1, CatDraw.rgb(c, 0))], center: (X, Y), r0: 0, r1: rad)
            }
        }
        for sk in Greeting.streaks {
            let q = seg(st, sk.t0, sk.t0 + 0.6)
            if q <= 0 || q >= 1 { continue }
            let dist = sk.sp * CatEase.out.at(q) * 0.9 + 10
            let line = CGMutablePath()
            line.move(to: CGPoint(x: X + cos(sk.a) * (dist - sk.len), y: Y + sin(sk.a) * (dist - sk.len) * 0.42))
            line.addLine(to: CGPoint(x: X + cos(sk.a) * dist, y: Y + sin(sk.a) * dist * 0.42))
            cg.stroke(line, CatDraw.color(sk.col, alpha: (1 - q) * P.fx), width: 1.6)
        }
        if P.header > 0.01 {
            CatDraw.text(cg, "NotchMeow", x: 20, y: 20, size: 13, bold: true, color: CatDraw.white(P.header), anchor: .left)
            CatDraw.text(cg, "Hi! \(p.label) is watching your agents.", x: 620, y: 20, size: 11.5, bold: false, color: CatDraw.rgb(Theme.Greeting.headerDimRGB, P.header), anchor: .right)
        }
        // The cat: the greeting sets its pose directly each frame; its ears, mouth and idle habits are the engine's own.
        e.s.sx = P.sx; e.s.sy = P.sy; e.s.tilt = P.tilt; e.s.open = P.open
        e.s.yaw = P.lookX * 0.55; e.s.pitch = -P.lookY * 0.45; e.s.roll = 0; e.s.oy = 0; e.s.ox = 0
        e.s.badgeS = P.badge; e.s.tint = P.tint; e.s.paws = 0
        e.eyeOv = P.eye == "happy" ? .happy : P.eye == "content" ? .closed : nil
        e.eyeUntil = .infinity
        var look = e.look()
        look.badge = .dots; look.badgeColor = Theme.Greeting.badge; look.color = Theme.Greeting.tintRGB
        let R = D / (2 * p.rx), rx = p.rx * R, ry = p.ry * R
        let on = P.wave >= 0, w = on ? P.wave * CatMath.tau * 4.2 : 0, wa = on ? seg(P.wave, 0, 0.12) * (1 - seg(P.wave, 0.9, 1.0)) : 0
        look.paws = [
            CatPaw(x: lerp(-0.35 * rx, -(rx + 0.22 * R), P.handL), y: lerp(0.85 * ry, 0.62 * ry, P.handL), k: P.handL, rot: -0.2, beans: false),
            CatPaw(x: lerp(0.35 * rx, rx + 0.2 * R, P.handR) + cos(w) * ry * 0.05 * wa, y: lerp(0.85 * ry, 0.05 * ry, P.handR) + sin(w + 0.8) * ry * 0.1 * wa,
                   k: P.handR, rot: 0.3 + sin(w) * 0.45 * wa, beans: true),
        ]
        var o = CatDrawOptions()
        o.fur = e.cfg.furLines
        o.outfit = CatOutfitDraw.big(e.cfg.outfit, dpr: 2, fade: Greeting.outfitFade(t), ceiling: 0)   // dressed once the cat has settled; the session cats below stay bare. y 0 is the island's top, the strip's top the island's own cat hands over to
        o.badgeSide = 1 - 2 * CatEase.inOut.at(seg(t, leave, leave + Greeting.GT.collapse))
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
        let slots = Greeting.miniSlots(minis: P.minis, glide: Greeting.miniGlide(t, leave: leave), width: end.width, height: end.height)
        // Two cats mode: the pair arrives together, the second cat popping in beside the one that has settled (`pair` is its coat).
        if let pair {
            let pop = Greeting.pairPop(t, leave: leave)
            if pop > 0.02 {
                var pose = CatPose(); pose.tint = 0.6
                var pairOptions = CatDrawOptions(badge: false)
                pairOptions.outfit = CatOutfitDraw.big(e.cfg.outfit, dpr: 2, ceiling: 0)   // the second cat of the pair is a big cat too
                CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(pair), pose: pose, color: Theme.Greeting.tintRGB), cx: X + D * 1.2, cy: Y, D: D * pop, pairOptions)
            }
        }
        let coats = (0..<4).map { i in sessions.flatMap { $0.indices.contains(i) ? CatPresets.byID($0[i]) : nil } ?? p }
        drawMinis(cg, slots, presets: coats, scale: end.miniScale, collarStyle: e.collarStyle)
    }

    /// The agent colours of the four session cats, in the order of the grid's cells (top left, top right, bottom left, bottom right): the prototype's, the
    /// Gemini CLI, the Codex, a Claude Code kitten and Claude Code. They wear them as collars when Settings picks a style.
    static let miniColors = ["#8AB4F8", "#2DD4BF", "#E07950", "#E07950"]

    /// The session cats: a row of three pops in as the island closes, glides into the compact island's 2x2 grid, and a fourth pops in (the real grid
    /// takes over when the last beat is over). Each is drawn the way the real grid draws one: a cat of head width 12 pt scaled about its own centre
    /// by the strip's `miniScale`. `slot.d` already holds the pop and that scale, so the head width drawn is `slot.d / scale`.
    private static func drawMinis(_ cg: CGContext, _ slots: [Greeting.Mini], presets: [CatPreset], scale k: Double, collarStyle: String) {
        guard k > 0 else { return }
        for (i, s) in slots.enumerated() where s.d >= Greeting.miniMinD {
            cg.saveGState()
            cg.translateBy(x: s.x, y: s.y)
            cg.scaleBy(x: k, y: k)
            var pose = CatPose(); pose.tint = 0.6
            var options = CatDrawOptions(badge: false)
            if collarStyle != "off" { options.collar = CatCollarPaint(style: collarStyle, color: miniColors[i % miniColors.count]) }
            CatRenderer.draw(cg, CatLook(preset: presets[i % presets.count], pose: pose, color: Theme.Greeting.tintRGB), cx: 0, cy: 0, D: s.d / k, options)
            cg.restoreGState()
        }
    }
}
