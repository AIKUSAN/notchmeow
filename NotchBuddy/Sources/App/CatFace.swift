import CoreGraphics
import Foundation

/// The face: eyes, nose, mouth and whiskers. Port of the prototype's eye, mouth and whisker drawing; all in the head's frame.
@MainActor
enum CatFace {
    typealias G = CatGeometry

    // MARK: Eyes

    static func drawEyes(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        let p = look.preset, s = look.pose, R = L.R
        let open = s.open * (1 - s.lid), shape = look.eye
        for e in L.eyes where e.visible {
            cg.saveGState()
            cg.translateBy(x: e.x, y: e.y)
            cg.scaleBy(x: e.fx, y: e.fy)
            cg.setAlpha(L.fa)
            if L.full {
                if let light = p.light {
                    cg.saveGState()
                    cg.scaleBy(x: 1.22, y: 1.3)
                    cg.fill(almondPath(p, e.sd, R, 1), CatDraw.color(light))
                    cg.restoreGState()
                }
                if shape.isRealistic || (shape == .wink && e.sd < 0) {
                    almondEye(cg, p, e.sd, R * s.es * (shape == .wide ? 1.12 : 1), pupil: shape == .dot ? 1 : s.pupil,
                              open: shape == .tired ? min(open, 0.42) : open, yaw: s.yaw, pitch: s.pitch)
                } else {
                    inkEye(cg, shape, e.sd, 0.27 * R * s.es, 0.31 * R * s.es, open, look.time, CatDraw.color(p.ink))
                }
            } else if !look.inkEyes, let small = CatSmallEye.eye(shape, sd: e.sd, R: R, es: s.es, open: open, yaw: s.yaw, pitch: s.pitch, kitten: p.kitten == true, cat: p.name) {
                smallEye(cg, p, e.sd, small)
            } else {
                inkEye(cg, shape, e.sd, 0.34 * R * s.es, 0.4 * R * s.es, open, look.time, CatDraw.color(p.ink))
            }
            cg.restoreGState()
        }
    }

    /// The small coloured eye of the compact detail level (`CatSmallEye` is the geometry, in the eye's own frame): a round iris in the coat's colours
    /// (`irisR` for the right eye of an odd-eyed coat) as a soft gradient, a slit pupil, one catchlight and a thin rim in the liner colour; or, when a
    /// blink or a squint has closed it, the arc in the ink colour. The black coats (`CatSmallEye.K.bright`, their kittens too) fill the iris flat with the lighter of the
    /// two iris colours and draw no rim: they glow like the old ink pill. The prototype's `smallEyeDraw` is the reference.
    private static func smallEye(_ cg: CGContext, _ p: CatPreset, _ sd: Double, _ g: CatSmallEye.Eye) {
        if g.closed, let l = g.line {
            cg.stroke(CatDraw.quad(l.x0, l.y0, l.cx, l.cy, l.x1, l.y1), CatDraw.color(p.ink, alpha: 0.9), width: l.width)
            return
        }
        guard let i = g.iris, let pupil = g.pupil, let light = g.light, let rim = g.rim else { return }
        let ir = (sd > 0 ? p.irisR : nil) ?? p.iris
        if g.flat == true {
            cg.fill(CatDraw.ellipse(0, 0, i.rx, i.ry), CatDraw.color(CatSmallEye.flatIris(ir)))
        } else {
            cg.saveGState()
            cg.clip(CatDraw.ellipse(0, 0, i.rx, i.ry))
            CatDraw.radial(cg, [(0, CatDraw.color(ir[0])), (1, CatDraw.color(ir[1]))], center: (0, 0), r0: 0, r1: i.r)
            cg.restoreGState()
        }
        cg.fill(CatDraw.ellipse(pupil.x, pupil.y, pupil.rx, pupil.ry), CatDraw.color(Theme.Cat.pupil))
        cg.fill(CatDraw.circle(light.x, light.y, light.r), CatDraw.white(0.92))
        if g.flat != true { cg.stroke(CatDraw.ellipse(0, 0, i.rx, i.ry), CatDraw.color(p.liner), width: rim) }
    }

    private static func almondPath(_ p: CatPreset, _ sd: Double, _ R: Double, _ open: Double) -> CGPath {
        let E = p.eye, w = E.w * R, h = E.h * R * max(open, 0.06), H = E.h * R
        let round = E.round != 0, k = round ? 2.2 : 1.85
        let iy = (round ? 0.04 : 0.12) * H, oy = (round ? -0.04 : -0.18) * H, ix = -sd * w, ox = sd * w
        let q = CGMutablePath()
        q.move(to: CGPoint(x: ix, y: iy))
        q.addQuadCurve(to: CGPoint(x: ox, y: oy), control: CGPoint(x: 0, y: -h * k))
        q.addQuadCurve(to: CGPoint(x: ix, y: iy), control: CGPoint(x: 0, y: H * (0.55 + 0.45 * max(open, 0.06)) * k))
        q.closeSubpath()
        return q
    }

    /// The realistic eye: iris gradient, dilating pupil, Momo's yellow lid ring, catchlights, liner.
    private static func almondEye(_ cg: CGContext, _ p: CatPreset, _ sd: Double, _ R: Double, pupil: Double, open: Double, yaw: Double, pitch: Double) {
        let E = p.eye, w = E.w * R, h = E.h * R
        if open < 0.22 {
            cg.stroke(CatDraw.quad(-w, 0, 0, 0.4 * h, w, 0), CatDraw.color(p.ink, alpha: 0.9), width: max(1, 0.045 * R))
            return
        }
        let outline = almondPath(p, sd, R, open)
        cg.saveGState()
        cg.clip(outline)
        let ir = (sd > 0 ? p.irisR : nil) ?? p.iris
        CatDraw.radial(cg, [(0, CatDraw.color(ir[0])), (1, CatDraw.color(ir[1]))], center: (0, 0), r0: 0, r1: w * 1.1)
        let off = G.pupilOffset(yaw: yaw, pitch: pitch, w: w, h: h)
        cg.fill(CatDraw.ellipse(off.x, off.y, w * (p.pupil0 + 0.5 * pupil), h * 1.1), CatDraw.color(Theme.Cat.pupil))
        if let ring = p.lidTint {
            cg.saveGState()
            cg.scaleBy(x: 0.92, y: 0.88)
            cg.stroke(almondPath(p, sd, R, open), CatDraw.color(ring, alpha: 0.85), width: 0.04 * R, join: .miter)
            cg.restoreGState()
        }
        cg.fill(CatDraw.circle(-0.32 * w, -0.32 * h, 0.2 * w), CatDraw.white(0.92))
        cg.fill(CatDraw.circle(0.22 * w, 0.3 * h, 0.09 * w), CatDraw.white(0.92))
        cg.restoreGState()
        cg.stroke(outline, CatDraw.color(p.liner), width: 0.05 * R, join: .miter)
    }

    /// Expression eyes (upstream's shapes), in the cat's ink colour. w and h are the eye's width and height; `sd` is -1 for the left eye.
    private static func inkEye(_ cg: CGContext, _ shape: CatEye, _ sd: Double, _ w: Double, _ h: Double, _ open: Double, _ T: Double, _ ink: CGColor) {
        func pill(_ W: Double, _ H: Double) {
            let hh = max(H * open, 0.3 * W)
            cg.fill(CatDraw.roundRect(-W / 2, -hh / 2, W, hh, min(W, hh) / 2), ink)
        }
        func happy() {
            let a = CGMutablePath()
            a.addArc(center: CGPoint(x: 0, y: 0.18 * h), radius: 0.82 * w, startAngle: 1.12 * Double.pi, endAngle: 1.88 * Double.pi, clockwise: false)
            cg.stroke(a, ink, width: 0.5 * w)
        }
        switch shape {
        case .pill: pill(w, h)
        case .wide: pill(w * 1.16, h * 1.12)
        case .dot: cg.fill(CatDraw.circle(0, 0, 0.45 * w), ink)
        case .line:
            cg.saveGState()
            cg.rotate(by: -sd * 0.2)
            cg.fill(CatDraw.roundRect(-0.78 * w, -0.21 * w, 1.56 * w, 0.42 * w, 0.21 * w), ink)
            cg.restoreGState()
        case .flat: cg.fill(CatDraw.roundRect(-0.72 * w, -0.2 * w, 1.44 * w, 0.4 * w, 0.2 * w), ink)
        case .happy: happy()
        case .closed:
            let a = CGMutablePath()
            a.addArc(center: CGPoint(x: 0, y: -0.08 * h), radius: 0.78 * w, startAngle: 0.15 * Double.pi, endAngle: 0.85 * Double.pi, clockwise: false)
            cg.stroke(a, ink, width: 0.36 * w)
        case .spiral:
            cg.saveGState()
            cg.rotate(by: T * 9 * sd)
            let sp = CGMutablePath()
            var a = 0.0, first = true
            while a < 4.4 * Double.pi {
                let r = 0.06 * w + 0.058 * w * a, pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                first ? sp.move(to: pt) : sp.addLine(to: pt)
                first = false
                a += 0.2
            }
            cg.stroke(sp, ink, width: 0.22 * w)
            cg.restoreGState()
        case .heart: cg.fill(CatDraw.heart(1.2 * w), CatDraw.color(Theme.Cat.heart))
        case .star:
            cg.saveGState()
            cg.rotate(by: T * 1.5 * sd)
            cg.fill(CatDraw.star(1.05 * w, 0.46 * w), CatDraw.color(Theme.Cat.star))
            cg.restoreGState()
        case .tired:
            cg.fill(CatDraw.roundRect(-w / 2, -0.02 * h, w, 0.38 * h, min(w, 0.38 * h) / 2), ink)
            cg.fill(CatDraw.roundRect(-0.62 * w, -0.12 * h - 0.11 * w, 1.24 * w, 0.22 * w, 0.11 * w), ink)
        case .wink:
            sd < 0 ? pill(w, h) : happy()
        }
    }

    // MARK: Nose and mouth

    static func drawNoseAndMouth(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        guard L.nose.visible else { return }
        let p = look.preset, s = look.pose, R = L.R
        let nx = L.nose.nx, ny = L.nose.ny, nf = L.nose.nf, nw = L.nose.nw, nh = L.nose.nh, my = L.nose.my
        cg.saveGState()
        cg.setAlpha(L.fa)
        drawMouth(cg, p, s, R, nx, my, nf, L.full, look.mouthOpen, look.time)
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: nx - nw / 2, y: ny - nh / 2))
        nose.addQuadCurve(to: CGPoint(x: nx + nw / 2, y: ny - nh / 2), control: CGPoint(x: nx, y: ny - nh * 0.8))
        nose.addQuadCurve(to: CGPoint(x: nx, y: ny + nh / 2), control: CGPoint(x: nx + nw * 0.1, y: ny + nh * 0.6))
        nose.addQuadCurve(to: CGPoint(x: nx - nw / 2, y: ny - nh / 2), control: CGPoint(x: nx - nw * 0.1, y: ny + nh * 0.6))
        cg.fill(nose, CatDraw.color(p.nose))
        if L.full { cg.stroke(nose, CatDraw.color(p.noseLine), width: 0.02 * R) }
        cg.restoreGState()
    }

    /// A closed ω that can smile, frown, skew or wobble, with an optional tongue blep, or an open mouth that runs from a wide D
    /// (meow, hiss, yawn) to a round 'o'.
    private static func drawMouth(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ R: Double, _ nx: Double, _ my: Double, _ nf: Double, _ full: Bool, _ mo: Double, _ T: Double) {
        let sm = clamp(s.smile, -1, 1), sk = clamp(s.mskew, -1, 1), tg = clamp(s.tongue, 0, 1), rd = clamp(s.mround, 0, 1), wv = clamp(s.wavy, 0, 1)
        let y0 = my + 0.05 * R, cxm = nx + sk * 0.035 * R * nf, lw = 0.03 * R
        let line = CatDraw.color(p.mouthLine), tongueColor = CatDraw.color(Theme.Cat.tongue)
        if mo > 0.04 {
            let m = min(mo, 1.3)
            let w = 0.13 * R * (0.6 + 0.4 * m) * (1 - 0.45 * rd) * (1 + 0.25 * max(0, sm)) * nf
            let h = 0.21 * R * m * (1 - 0.3 * rd) + 0.012 * R, top = y0 - 0.012 * R
            // The opening hangs under the ω upper lip; as it rounds into an 'o' the lip lifts into the top of the ring.
            let L = 0.055 * R * (1 - rd), ty = top - h * 0.35 * rd, cty = top - h * 0.3 * rd + L, bot = top + h * (1.15 + 0.15 * rd) + L * 0.5
            func lip(_ q: CGMutablePath) {
                q.move(to: CGPoint(x: cxm - w, y: top))
                q.addQuadCurve(to: CGPoint(x: cxm, y: ty), control: CGPoint(x: cxm - w * 0.5, y: cty))
                q.addQuadCurve(to: CGPoint(x: cxm + w, y: top), control: CGPoint(x: cxm + w * 0.5, y: cty))
            }
            let open = CGMutablePath()
            lip(open)
            open.addCurve(to: CGPoint(x: cxm - w, y: top), control1: CGPoint(x: cxm + w, y: bot), control2: CGPoint(x: cxm - w, y: bot))
            open.closeSubpath()
            cg.fill(open, CatDraw.color(Theme.Cat.mouthInside))
            cg.saveGState()
            cg.clip(open)
            cg.fill(CatDraw.ellipse(cxm, top + h * 0.95, w * 0.62, h * 0.34), tongueColor)
            cg.restoreGState()
            if m > 0.45 && rd < 0.5 && full {
                for sd in [-1.0, 1.0] {
                    let fx = cxm + sd * w * 0.55, fy = top + L * 0.55
                    cg.fill(CatDraw.poly([(fx - 0.022 * R, fy), (fx + 0.022 * R, fy), (fx, fy + 0.055 * R)]), CatDraw.color(Theme.Cat.teeth))
                }
            }
            if tg > 0.05 {
                let tl = (0.03 + 0.07 * tg) * R, tw = max(w * 0.5, 0.05 * R * nf), tty = top + h * 0.9
                let t = CGMutablePath()
                t.move(to: CGPoint(x: cxm - tw, y: top + h * 0.7))
                t.addLine(to: CGPoint(x: cxm - tw, y: tty + tl * 0.4))
                t.addQuadCurve(to: CGPoint(x: cxm, y: tty + tl * 1.2), control: CGPoint(x: cxm - tw, y: tty + tl * 1.2))
                t.addQuadCurve(to: CGPoint(x: cxm + tw, y: tty + tl * 0.4), control: CGPoint(x: cxm + tw, y: tty + tl * 1.2))
                t.addLine(to: CGPoint(x: cxm + tw, y: top + h * 0.7))
                t.closeSubpath()
                cg.fill(t, tongueColor)
                if full {
                    let c = CGMutablePath()
                    c.move(to: CGPoint(x: cxm, y: top + h * 0.95))
                    c.addLine(to: CGPoint(x: cxm, y: tty + tl * 0.9))
                    cg.stroke(c, CatDraw.rgb([150, 50, 70], 0.6), width: lw * 0.6)
                }
            }
            if full {
                let stem = CGMutablePath()
                stem.move(to: CGPoint(x: nx, y: my))
                stem.addLine(to: CGPoint(x: cxm, y: ty))
                cg.stroke(stem, line, width: lw)
                let upper = CGMutablePath()
                lip(upper)
                cg.stroke(upper, CatDraw.color(p.mouthLine, alpha: 1 - rd), width: lw)
            }
            return
        }
        if !full { return }
        if tg > 0.03 {
            let th = (0.025 + 0.045 * tg) * R
            cg.fill(CatDraw.ellipse(cxm, y0 + 0.035 * R + th * 0.5, 0.042 * R * nf, th), tongueColor)
            let c = CGMutablePath()
            c.move(to: CGPoint(x: cxm, y: y0 + 0.04 * R))
            c.addLine(to: CGPoint(x: cxm, y: y0 + 0.035 * R + th * 0.9))
            cg.stroke(c, CatDraw.rgb([150, 50, 70], 0.55), width: lw * 0.5)
        }
        let mw = 0.15 * R * nf * (1 + 0.18 * max(0, sm))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: nx, y: my))
        path.addLine(to: CGPoint(x: cxm, y: y0))
        if wv > 0.05 {
            path.move(to: CGPoint(x: cxm - mw, y: y0 + 0.03 * R))
            for i in 1...24 {
                let t = Double(i) / 24
                path.addLine(to: CGPoint(x: cxm - mw + 2 * mw * t, y: y0 + 0.03 * R + sin(t * CatMath.tau * 2.5 + T * 6) * 0.022 * R * wv))
            }
        } else {
            let lobe = 0.08 * R * (1 - 0.6 * max(0, -sm)), cL = y0 - sm * 0.05 * R - sk * 0.035 * R, cR = y0 - sm * 0.05 * R + sk * 0.035 * R
            path.move(to: CGPoint(x: cxm - mw, y: cL))
            path.addQuadCurve(to: CGPoint(x: cxm, y: y0), control: CGPoint(x: cxm - mw / 2, y: y0 + lobe))
            path.addQuadCurve(to: CGPoint(x: cxm + mw, y: cR), control: CGPoint(x: cxm + mw / 2, y: y0 + lobe))
        }
        cg.stroke(path, line, width: lw)
    }

    // MARK: Whiskers

    /// How many strokes a hair is drawn with: each is a little thinner and a little fainter than the one before.
    private static let hairSegments = 8

    /// The hairs of one width, gathered so that each segment index is stroked once for all of them (a few strokes, not a hundred and fifty).
    @MainActor private struct Hairs {
        var segments = (0..<hairSegments).map { _ in CGMutablePath() }

        /// Adds one hair, a quadratic from (x0,y0) via (cx,cy) to (x1,y1), as `hairSegments` short lines.
        mutating func add(_ x0: Double, _ y0: Double, _ cx: Double, _ cy: Double, _ x1: Double, _ y1: Double) {
            var px = x0, py = y0
            for i in 1...hairSegments {
                let s = Double(i) / Double(hairSegments), m = 1 - s
                let x = m * m * x0 + 2 * m * s * cx + s * s * x1, y = m * m * y0 + 2 * m * s * cy + s * s * y1
                segments[i - 1].move(to: CGPoint(x: px, y: py))
                segments[i - 1].addLine(to: CGPoint(x: x, y: y))
                px = x; py = y
            }
        }

        /// Strokes every segment: each thinner (from `w0`) and fainter (from alpha `a0`) than the one before, so a hair thins and fades toward its tip.
        func stroke(_ cg: CGContext, _ w0: Double, _ col: String, _ a0: Double) {
            for i in 1...hairSegments {
                let s = Double(i) / Double(hairSegments)
                cg.stroke(segments[i - 1], CatDraw.color(col, alpha: a0 * (1 - 0.7 * s)), width: max(0.35, w0 * (1 - 0.88 * s)))
            }
        }
    }

    /// Whiskers rooted on the pad grid beside the nose, plus eyebrow whiskers. Full detail only.
    static func drawWhiskers(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ L: G.Layout) {
        let Wk = p.whisk2, R = L.R, W = L.warp, yf = L.yf, fa = L.fa
        let rand = CatRNG(seed: 29), nzy = -sin(p.nosePh) * p.ry
        var hairs = Hairs(), brows = Hairs()
        for sd in [-1.0, 1.0] {
            let fxs = clamp(cos(yf) + sd * 0.37 * sin(yf), 0.15, 1.3)
            var pts: [(row: Int, col: Int, x: Double, y: Double)] = []
            for row in 0..<Wk.rows {
                for col in 0..<Wk.cols {
                    pts.append((row, col, sd * (Wk.x0 + Double(col) * Wk.dx), nzy + Wk.y0 + Double(row) * Wk.dy + Double(col) * Wk.slope))
                }
            }
            let dot = CatDraw.color(p.padDot, alpha: fa)
            for q in pts { let (X, Y) = W(q.x, q.y); cg.fill(CatDraw.circle(X, Y, Wk.dot * R), dot) }
            for q in pts where Wk.wcols.contains(q.col) {
                let (X, Y) = W(q.x, q.y)
                let jitterA = rand.next(), jitterL = rand.next()
                let ang = Wk.a0 + Double(q.row) * Wk.da + Double(q.col) * 0.04 + (jitterA - 0.5) * 0.06 - s.wh
                let len = (Wk.len - Double(q.row) * Wk.dl - Double(q.col) * 0.05 + (jitterL - 0.5) * 0.1) * R
                let dx = sd * cos(ang) * fxs, dy = sin(ang)
                hairs.add(X, Y, X + dx * len * 0.5, Y + dy * len * 0.5 - 0.05 * R, X + dx * len, Y + dy * len + Wk.droop * len * len / R)
            }
            let ex = sin(sd * p.eye.th) * cos(p.eye.ph) * p.rx, ey = -sin(p.eye.ph) * p.ry
            for k in 0..<Wk.brow {
                let kk = Double(k)
                let (bx, by) = W(ex + sd * (kk * 0.06 - 0.03), ey - p.eye.h * 1.9 - kk * 0.015)
                let th = 1.08 - kk * 0.2 - s.wh * 0.5, len = (0.38 + kk * 0.08) * R
                brows.add(bx, by, bx + sd * (cos(th) * len * 0.45 * fxs + 0.07 * R), by - sin(th) * len * 0.55, bx + sd * cos(th) * len * fxs, by - sin(th) * len)
            }
        }
        hairs.stroke(cg, Wk.w * R, p.whisk, Wk.alpha * fa)
        brows.stroke(cg, Wk.w * 0.7 * R, p.whisk, Wk.alpha * 0.85 * fa)
    }
}
