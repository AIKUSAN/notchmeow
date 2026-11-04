import CoreGraphics
import Foundation

/// What is drawn around the cat rather than as part of it: the glow, the zoomies' afterimages, the paws, the badge, the particles and
/// the hairballs. Port of the prototype's drawing of the same names.
@MainActor
enum CatEffects {
    typealias G = CatGeometry

    // MARK: Behind the cat, in the world

    static func drawGlow(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        guard look.glowAlpha > 0.005 else { return }
        let g = look.glowColor.map { $0.rounded() }, R = L.R, cx = L.head.x, cy = L.head.y
        cg.saveGState()
        CatDraw.radial(cg, [(0, CatDraw.rgb(g, look.glowAlpha)), (1, CatDraw.rgb(g, 0))], center: (cx, cy), r0: 0, r1: R * 2.3)
        cg.restoreGState()
    }

    /// Afterimages and speed lines behind a cat that is moving fast (the zoomies).
    static func drawZoomTrails(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        let zv = look.zoomVelocity, p = look.preset
        guard abs(zv) > 1.1 && L.D >= 16 else { return }
        let k = min(1, (abs(zv) - 1.1) / 2.5), dir = zv > 0 ? 1.0 : -1.0, R = L.R, cx = L.head.x, cy = L.head.y
        let tint = p.ruff?.col[0] ?? p.top
        for i in 1...3 {
            cg.fill(CatDraw.ellipse(cx - dir * Double(i) * 0.3 * R * k, cy, L.rx, L.ry), CatDraw.color(tint, alpha: 0.2 * k / Double(i)))
        }
        for (yy, l) in [(-0.5, 0.7), (-0.08, 1.0), (0.32, 0.8), (0.68, 0.5)] {
            let x0 = cx - dir * (L.rx + 0.15 * R), y = cy + yy * R
            let line = CGMutablePath()
            line.move(to: CGPoint(x: x0, y: y))
            line.addLine(to: CGPoint(x: x0 - dir * l * 0.75 * R * k, y: y))
            cg.stroke(line, CatDraw.white(0.6 * k), width: max(1, 0.025 * R))
        }
    }

    // MARK: Paws (behind the head, in its frame)

    /// The paws of the engine's wave: both rest at the cheeks, the right one rises and waves with its toe beans out.
    static func wavePaws(pawsOut: Double, wave: CatWave, rx: Double, ry: Double) -> [CatPaw] {
        if pawsOut <= 0.01 { return [] }
        let n = wave.now, bodyH = 2 * ry, waving = wave.start > 0 && n >= wave.start && n < wave.until
        return [-1.0, 1.0].map { sd in
            var x = sd * rx, y = ry * 0.78, rot = 0.0, beans = false
            if sd > 0 && waving {
                let wt = (n - wave.start) / 1000, rise = CatEase.out.at(min(1, wt / 0.18))
                x = lerp(x, rx * 1.12 + cos(13 * wt) * 0.06 * bodyH, rise)
                y = lerp(y, -ry * 0.12 - sin(13 * wt) * 0.12 * bodyH, rise)
                rot = (0.35 + sin(13 * wt) * 0.3) * rise
                beans = rise > 0.5
            } else if sd < 0 && waving {
                y += sin(6 * (n - wave.start) / 1000) * 0.04 * bodyH
            }
            return CatPaw(x: x, y: y, k: pawsOut, rot: rot, beans: beans)
        }
    }

    static func drawPaw(_ cg: CGContext, _ p: CatPreset, _ R: Double, _ q: CatPaw) {
        let k = q.k, w = 0.2 * R * k, h = 0.18 * R * k
        if w < 0.6 { return }
        cg.saveGState()
        cg.translateBy(x: q.x, y: q.y)
        cg.rotate(by: q.rot)
        let toes = [-1.0, 0.0, 1.0].map { (x: $0 * w * 0.55, y: -h * 0.62) }
        let shape = CGMutablePath()
        for t in toes { shape.addEllipse(in: CGRect(x: t.x - w * 0.36, y: t.y - h * 0.38, width: w * 0.72, height: h * 0.76)) }
        shape.addEllipse(in: CGRect(x: -w, y: -h * 0.85, width: w * 2, height: h * 1.7))
        cg.stroke(shape, CatDraw.black(0.28), width: max(0.6, 0.012 * R))
        cg.fill(shape, CatDraw.color(p.paw))
        if q.beans {
            let bean = CatDraw.color(p.bean)
            cg.fill(CatDraw.ellipse(0, h * 0.12, w * 0.42, h * 0.32), bean)
            for t in toes { cg.fill(CatDraw.ellipse(t.x, t.y + h * 0.02, w * 0.16, h * 0.17), bean) }
        } else {
            for s in [-1.0, 1.0] {
                let line = CGMutablePath()
                line.move(to: CGPoint(x: s * w * 0.28, y: -h * 0.85))
                line.addLine(to: CGPoint(x: s * w * 0.24, y: -h * 0.35))
                cg.stroke(line, CatDraw.black(0.25), width: max(0.6, 0.012 * R))
            }
        }
        cg.restoreGState()
    }

    // MARK: In front, in the world

    static func drawBadge(_ cg: CGContext, _ kind: CatBadge, _ colorHex: String, _ L: G.Layout, _ T: Double, leftLimit: Double? = nil) {
        let R = L.R
        var b = L.badge
        let col = CatDraw.color(colorHex)
        if let leftLimit {   // nudged right, never resized, until the whole shape is past the limit
            let half = (kind == .dots ? (b.small ? 0.26 : 0.36) : kind == .dot ? 0.2 : 0.3) * R * b.k
            b.x = max(b.x, leftLimit + half)
        }
        cg.saveGState()
        cg.translateBy(x: b.x, y: b.y)
        cg.scaleBy(x: b.k, y: b.k)
        switch kind {
        case .dots where b.small:
            let r = R * 0.22 * (1 + 0.25 * sin(((T * 2.4).truncatingRemainder(dividingBy: 1)) * CatMath.tau))
            cg.fill(CatDraw.circle(0, 0, R * 0.26), CatDraw.black(1))
            cg.fill(CatDraw.circle(0, 0, r), col)
        case .dots:
            cg.fill(CatDraw.roundRect(-0.36 * R, -0.18 * R, 0.72 * R, 0.36 * R, 0.18 * R), col)
            for i in 0..<3 {
                let ph = ((2.4 * T - 0.22 * Double(i)).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                let r = 0.055 * R * (1 + 0.4 * max(0, sin(CatMath.tau * ph)))
                cg.fill(CatDraw.circle(Double(i - 1) * 0.18 * R, 0, r), CatDraw.white(1))
            }
        case .bang, .question:
            cg.fill(CatDraw.circle(0, 0, 0.3 * R), CatDraw.black(1))
            cg.fill(CatDraw.circle(0, 0, 0.23 * R), col)
            if !b.small { CatDraw.text(cg, kind == .bang ? "!" : "?", x: 0, y: 0.02 * R, size: 0.32 * R, bold: true, color: CatDraw.white(1)) }
        case .dot:
            cg.fill(CatDraw.circle(0, 0, 0.2 * R), CatDraw.black(1))
            cg.fill(CatDraw.circle(0, 0, 0.135 * R), col)
        }
        cg.restoreGState()
    }

    static func drawParticles(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        let R = L.R, cx = L.base.x, cy = L.base.y, p = look.preset
        for q in look.particles where q.age >= 0 {
            let k = q.age / q.life, al = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8
            let x = cx + (q.x + q.vx * q.age) * R * 1.3, y = cy + (q.y + q.vy * q.age) * R * 1.3, sz = R * q.size * (1 + 0.4 * k)
            cg.saveGState()
            cg.setAlpha(max(0, al))
            cg.translateBy(x: x, y: y)
            switch q.kind {
            case .heart:
                cg.rotate(by: sin(6 * q.age) * 0.3)
                cg.fill(CatDraw.heart(sz * 1.6), CatDraw.color(Theme.Cat.heart))
            case .star:
                cg.rotate(by: q.rot + 2 * q.age)
                cg.fill(CatDraw.star(sz, sz * 0.45), CatDraw.color(Theme.Cat.star))
            case .spark:
                cg.rotate(by: q.rot)
                cg.fill(CatDraw.star(sz * 0.8, sz * 0.18), CatDraw.white(1))
            case .sweat:
                let d = CGMutablePath()
                d.move(to: CGPoint(x: 0, y: -sz))
                d.addQuadCurve(to: CGPoint(x: 0, y: sz * 0.8), control: CGPoint(x: sz * 0.8, y: sz * 0.3))
                d.addQuadCurve(to: CGPoint(x: 0, y: -sz), control: CGPoint(x: -sz * 0.8, y: sz * 0.3))
                cg.fill(d, CatDraw.color(Theme.Cat.sweat))
            case .dust:
                cg.fill(CatDraw.circle(0, 0, sz * (0.6 + k * 0.9)), CatDraw.rgb([225, 225, 232], 0.55))
            case .hair:
                cg.rotate(by: q.rot + q.age * 1.5)
                cg.stroke(CatDraw.quad(-sz * 0.6, 0, 0, -sz * 0.5, sz * 0.6, 0), CatDraw.color(p.hairLight), width: max(0.6, R * 0.014))
            case .z:
                CatDraw.text(cg, "z", x: 0, y: 0, size: 1.9 * sz, bold: true, color: CatDraw.rgb([209, 219, 235]))
            }
            cg.restoreGState()
        }
    }

    /// A small file icon (a folded corner and an extension label), for a refused file wrapped in fur.
    static func drawFile(_ cg: CGContext, x: Double, y: Double, size s: Double, rot: Double, ext: String) {
        cg.saveGState()
        cg.translateBy(x: x, y: y)
        cg.rotate(by: rot)
        let w = s * 0.78, h = s, f = s * 0.24
        cg.fill(CatDraw.poly([(-w / 2, -h / 2), (w / 2 - f, -h / 2), (w / 2, -h / 2 + f), (w / 2, h / 2), (-w / 2, h / 2)]), CatDraw.color(Theme.Cat.paper))
        cg.fill(CatDraw.poly([(w / 2 - f, -h / 2), (w / 2 - f, -h / 2 + f), (w / 2, -h / 2 + f)]), CatDraw.color(Theme.Cat.paperFold))
        cg.fill(CatDraw.roundRect(-w / 2 + s * 0.07, h * 0.06, w - s * 0.14, s * 0.24, s * 0.05), CatDraw.color(Theme.Cat.paperLabel))
        CatDraw.text(cg, ext, x: 0, y: h * 0.06 + s * 0.125, size: s * 0.15, bold: true, color: CatDraw.white(1))
        cg.restoreGState()
    }

    /// Hairballs (and refused files wrapped in fur) bounce once and roll away.
    static func drawBalls(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        let p = look.preset, R = L.R, cx = L.base.x, cy = L.base.y
        for b in look.balls {
            let a = min(1, (b.life - b.age) / 0.5)
            cg.saveGState()
            cg.translateBy(x: cx + b.x * R, y: cy + b.y * R)
            cg.rotate(by: b.rot)
            cg.setAlpha(max(0, a))
            let r = CatRNG(seed: UInt32(truncatingIfNeeded: b.seed))
            var fw = 0.17 * R, fh = 0.11 * R
            if let file = b.file {
                drawFile(cg, x: 0, y: 0, size: 0.36 * R, rot: 0, ext: file)
                fw = 0.17 * R; fh = 0.2 * R
            } else {
                cg.fill(CatDraw.ellipse(0, 0, fw, fh), CatDraw.color(p.hair))
            }
            for _ in 0..<(b.file != nil ? 26 : 20) {
                let t = r.next() * CatMath.tau, ex = cos(t) * fw, ey = sin(t) * fh, len = (0.03 + r.next() * 0.05) * R
                let strand = CGMutablePath()
                strand.move(to: CGPoint(x: ex * 0.75, y: ey * 0.75))
                strand.addQuadCurve(to: CGPoint(x: ex + cos(t + 0.3) * len, y: ey + sin(t + 0.3) * len), control: CGPoint(x: ex + cos(t + 0.9) * len * 0.6, y: ey + sin(t + 0.9) * len * 0.6))
                cg.stroke(strand, CatDraw.color(r.next() < 0.5 ? p.hairDark : p.hairLight), width: max(0.6, 0.014 * R))
            }
            if b.file == nil {
                cg.saveGState()
                cg.translateBy(x: -fw * 0.3, y: -fh * 0.4)
                cg.rotate(by: -0.3)
                cg.fill(CatDraw.ellipse(0, 0, fw * 0.3, fh * 0.2), CatDraw.white(0.3))
                cg.restoreGState()
            }
            cg.restoreGState()
        }
    }

    // MARK: The collar

    /// The collar, painted (the prototype's `drawCollar`; the maths is `CatGeometry.collarGeometry`). In the head's frame, in the front pass. A thin
    /// dark edge keeps a light collar apart from a light coat; the tag is a lighter tint of the colour; at full detail the tag has a highlight and the
    /// neckerchief a crease.
    static func drawCollar(_ cg: CGContext, _ g: G.Collar, color: String, full: Bool, dpr: Double) {
        let e1 = 1 / (dpr > 0 ? dpr : 2), edge = CatDraw.black(0.42), base = CatDraw.color(color)
        func tint(_ k: Double) -> CGColor { CatDraw.rgb(hexRGB(color).map { ($0 + (255 - $0) * k).rounded() }) }
        cg.saveGState()
        if let k = g.kerchief, let apex = Optional(k.apex) {
            let path = CGMutablePath()
            for (i, q) in k.pts.enumerated() { i == 0 ? path.move(to: CGPoint(x: q.x, y: q.y)) : path.addLine(to: CGPoint(x: q.x, y: q.y)) }
            path.addLine(to: CGPoint(x: apex.x, y: apex.y))
            path.closeSubpath()
            cg.fill(path, base)
            cg.stroke(path, edge, width: 1.5 * e1)
            if full, k.pts.count > 1 {
                let m = k.pts[k.pts.count >> 1]
                cg.stroke(CatDraw.quad(m.x, m.y + g.R * 0.05, m.x, m.y + g.R * 0.05, apex.x, apex.y - g.R * 0.08), tint(0.45), width: max(e1, g.R * 0.025))
            }
        } else if let band = g.band, let width = g.width, band.count > 1 {
            let path = CGMutablePath()
            for (i, q) in band.enumerated() { i == 0 ? path.move(to: CGPoint(x: q.x, y: q.y)) : path.addLine(to: CGPoint(x: q.x, y: q.y)) }
            cg.stroke(path, edge, width: width + 2 * e1)
            cg.stroke(path, base, width: width)
            if let t = g.tag {
                cg.fill(CatDraw.circle(t.x, t.y, t.r), tint(0.55))
                cg.stroke(CatDraw.circle(t.x, t.y, t.r), edge, width: 1.5 * e1)
                if full { cg.fill(CatDraw.circle(t.x - t.r * 0.3, t.y - t.r * 0.3, t.r * 0.25), CatDraw.white(0.85)) }
            }
        }
        cg.restoreGState()
    }

    // MARK: Apple Music dance

    /// A 112 BPM hop and sway around the bottom of the head. Apply it to the context before drawing; `level` is the engine's dancing level.
    static func applyDance(_ cg: CGContext, level l: Double, seconds: Double, pivotX px: Double, pivotY py: Double, size R: Double) {
        guard l > 0.001 else { return }
        let beat = CatDance.beat(seconds), (hop, land) = CatDance.curves(seconds)
        cg.translateBy(x: px + 0.08 * R * sin(Double.pi * beat) * l, y: py - 0.20 * R * hop * l)
        cg.rotate(by: 0.10 * sin(Double.pi * beat) * l)
        cg.scaleBy(x: 1 + 0.045 * land * l, y: 1 - 0.06 * land * l)
        cg.translateBy(x: -px, y: -py)
    }
}
