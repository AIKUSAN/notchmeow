import CoreGraphics
import Foundation

/// Draws a cat. D is the head width in px. The cat is drawn in three passes, so outfits (sub-project I) can sit behind or in front
/// of the head: *behind* (ruff, bib, paws, ears), the head (with its markings and face), then *front* (folded ears, whiskers).
/// The badge, the particles and the hairballs are drawn last, in the world, not in the head's turning frame.
@MainActor
enum CatRenderer {
    typealias G = CatGeometry

    /// Draws one cat and returns its layout (the engine wants `base` and `mouth` back for the hairball).
    @discardableResult
    static func draw(_ cg: CGContext, _ look: CatLook, cx: Double, cy: Double, D: Double, _ o: CatDrawOptions = CatDrawOptions()) -> G.Layout {
        let p = look.preset, s = look.pose
        let level = G.detailLevel(D, override: o.full.map { $0 ? "full" : "compact" })
        let full = level.full
        let flat = level.flatFill ? G.flatFillColors(p) : nil   // the compact detail's flat colours (A-0b's), worked out once per draw
        let ek = full ? 1.0 : G.earScale(D)
        func layout(_ ek: Double) -> G.Layout {
            G.layout(p, s, cx: cx, cy: cy, D: D, G.Options(full: o.full, time: look.time, badgeSide: o.badgeSide, earScale: ek))
        }
        var L = layout(ek), drawnEk = ek   // drawnEk: the ears' scale as they are drawn (the outfit is fitted to the same ears)
        if let ceiling = o.earCeiling {
            let f = G.earFit(L, s, ceiling: ceiling)
            if f < 1 { drawnEk = ek * f; L = layout(drawnEk) }
        }
        // The wardrobe: the outfit of a cat in the big-cat role, in head-local px, painted at three slots below. Bare for every other cat (nil).
        let dressed = CatOutfitDraw.dressed(o.outfit, p, s, D: D, full: full, earScale: drawnEk, collar: o.collar?.style, headY: L.head.y, ceiling: o.earCeiling)
        let fur = o.fur && CatFur.shows(p, R: L.R, full: L.full) ? CatFur.strands(for: p) : nil   // the optional fur strands
        if o.glow { CatEffects.drawGlow(cg, look, L) }
        CatEffects.drawZoomTrails(cg, look, L)
        cg.saveGState()
        cg.translateBy(x: L.head.x, y: L.head.y)
        cg.rotate(by: s.tilt)
        cg.scaleBy(x: s.sx, y: s.sy)
        drawBehind(cg, look, L, flat, fur, dressed)
        drawHead(cg, look, L, o, flat, fur)
        drawFront(cg, p, s, L, flat, o.collar, dressed)
        cg.restoreGState()
        if o.badge, let kind = look.badge, s.badgeS > 0.01 { CatEffects.drawBadge(cg, kind, look.badgeColor, L, look.time, leftLimit: o.badgeLeftLimit) }
        CatEffects.drawParticles(cg, look, L)
        CatEffects.drawBalls(cg, look, L)
        return L
    }

    // MARK: Behind pass

    private static func drawBehind(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ flat: G.FlatColors?, _ fur: CatFur.Strands?, _ dressed: CatDressed?) {
        let p = look.preset, R = L.R
        // Ruff and neck bib sit behind the head, with a little parallax.
        if let r = p.ruff {
            cg.saveGState()
            cg.translateBy(x: L.ruff.dx, y: L.ruff.dy)
            let rp = CatDraw.poly(G.supPoints(rx: r.rx * R, ry: r.ry * R, n: 2.4, dy: r.dy * R, spike: 0.06, count: 18, steps: L.steps))
            if L.full {
                cg.saveGState()
                cg.clip(rp)
                CatDraw.radial(cg, [(0, CatDraw.color(r.col[1])), (1, CatDraw.color(r.col[0]))], center: (0, r.dy * R), r0: 0.55 * R, r1: 1.55 * R)
                cg.restoreGState()
            } else if let c = flat?.ruff {
                cg.fill(rp, CatDraw.rgb(c))
            }
            if let fur {
                // Fur strands on the ruff, curved a little, inside its outline.
                cg.saveGState()
                cg.clip(rp)
                for q in fur.ruff {
                    let x = q.x * R, y = q.y * R, len = q.L * R
                    let strand = CGMutablePath()
                    strand.move(to: CGPoint(x: x - q.ux * len * 0.5, y: y - q.uy * len * 0.5))
                    strand.addQuadCurve(to: CGPoint(x: x + q.ux * len * 0.5, y: y + q.uy * len * 0.5), control: CGPoint(x: x - q.uy * len * 0.15, y: y + q.ux * len * 0.15))
                    cg.stroke(strand, CatDraw.color(q.color), width: max(0.6, 0.012 * R))
                }
                cg.restoreGState()
            }
            if let bib = p.bib {
                let by = (r.ry + r.dy) * R
                let b = CGMutablePath()
                b.move(to: CGPoint(x: -0.2 * R, y: by * 0.97))
                b.addQuadCurve(to: CGPoint(x: 0, y: by * 0.72), control: CGPoint(x: -0.12 * R, y: by * 0.8))
                b.addQuadCurve(to: CGPoint(x: 0.2 * R, y: by * 0.97), control: CGPoint(x: 0.12 * R, y: by * 0.8))
                b.addQuadCurve(to: CGPoint(x: 0.04 * R, y: by * 0.99), control: CGPoint(x: 0.1 * R, y: by * 1.03))
                b.addLine(to: CGPoint(x: 0, y: by * 1.06))
                b.addLine(to: CGPoint(x: -0.04 * R, y: by * 0.99))
                b.addQuadCurve(to: CGPoint(x: -0.2 * R, y: by * 0.97), control: CGPoint(x: -0.1 * R, y: by * 1.03))
                b.closeSubpath()
                cg.fill(b, CatDraw.color(bib))
            }
            cg.restoreGState()
        }
        let paws = look.paws ?? look.wave.map { CatEffects.wavePaws(pawsOut: look.pose.paws, wave: $0, rx: L.rx, ry: L.ry) } ?? []
        for q in paws { CatEffects.drawPaw(cg, p, R, q) }
        for e in L.ears { drawEar(cg, p, e, R: R, full: L.full, front: false, flat: flat?.ears[e.sd < 0 ? 0 : 1]) }
        // The outfit's `behind` slot, after the ears: the bunny ears, so the head covers their roots.
        if let dressed { CatOutfitDraw.paint(cg, dressed, slot: "behind") }
    }

    /// One ear, in the head's frame. `front` is the folded-ear flap, drawn over the head after it. `flat` is the ear's flat colour at the compact detail.
    static func drawEar(_ cg: CGContext, _ p: CatPreset, _ g: G.Ear, R: Double, full: Bool, front: Bool, flat: [Double]?) {
        let E = p.ear, h = g.h, bw = g.bw, tip = g.tip, cx = g.cx, sd = g.sd
        cg.saveGState()
        cg.translateBy(x: g.bx, y: g.by)
        cg.rotate(by: g.rot)
        func outline(_ k: Double) -> CGPath {
            let q = CGMutablePath()
            q.move(to: CGPoint(x: -bw * k, y: 0.25 * R))
            q.addQuadCurve(to: CGPoint(x: -tip * 0.9, y: -h * k + tip * 1.3), control: CGPoint(x: -bw * k * cx, y: -h * k * 0.4))
            q.addQuadCurve(to: CGPoint(x: tip * 0.9, y: -h * k + tip * 1.3), control: CGPoint(x: 0, y: -h * k - tip * 0.35))
            q.addQuadCurve(to: CGPoint(x: bw * k, y: 0.25 * R), control: CGPoint(x: bw * k * cx, y: -h * k * 0.4))
            q.closeSubpath()
            return q
        }
        let ec = p.earCols.map { sd < 0 ? $0[0] : $0[1] }
        let top = CatDraw.color(ec ?? p.top), bot = CatDraw.color(ec ?? p.bot)
        func fillGradient(_ path: CGPath) {
            if let c = flat {
                // Below Ø28 the ear gradient cannot be seen and costs a shading pass per ear: the contract's flat colour does.
                cg.fill(path, CatDraw.rgb(c))
                return
            }
            cg.saveGState()
            cg.clip(path)
            CatDraw.linear(cg, [(0, top), (1, bot)], from: (0, -h), to: (0, 0.25 * R))
            cg.restoreGState()
        }
        // Folded ear (front pass, drawn over the head): the tip folds forward and down over the inner ear, with a soft crease.
        if front {
            let fw = bw * 0.62, yc = -h + tip * 0.8, ty = -h * 0.05
            let flap = CGMutablePath()
            flap.move(to: CGPoint(x: -fw, y: yc))
            flap.addQuadCurve(to: CGPoint(x: fw, y: yc), control: CGPoint(x: 0, y: yc - fw * 0.75))
            flap.addQuadCurve(to: CGPoint(x: 0, y: ty), control: CGPoint(x: fw * 0.7, y: (yc + ty) / 2))
            flap.addQuadCurve(to: CGPoint(x: -fw, y: yc), control: CGPoint(x: -fw * 0.7, y: (yc + ty) / 2))
            flap.closeSubpath()
            cg.saveGState()
            cg.translateBy(x: 0, y: 0.025 * R)
            cg.fill(flap, CatDraw.black(0.2))
            cg.restoreGState()
            fillGradient(flap)
            if full {
                cg.stroke(CatDraw.quad(-fw * 0.8, yc + 0.02 * R, 0, yc - fw * 0.5, fw * 0.8, yc + 0.02 * R), CatDraw.black(0.2), width: 0.016 * R)
            }
            cg.restoreGState()
            return
        }
        fillGradient(outline(1))
        if p.rimLight != nil {
            cg.stroke(outline(1), CatDraw.white(0.22), width: max(0.8, 0.013 * R), join: .miter)
        }
        cg.fill(outline(0.6), CatDraw.color(p.inner, alpha: 0.9))
        if E.tuft != 0 && full {
            let inner = CatDraw.color(p.inner, alpha: 0.7)
            for k in [-1.0, 0.0, 1.0] {
                let t = CGMutablePath()
                t.move(to: CGPoint(x: k * bw * 0.3, y: 0.06 * R))
                t.addQuadCurve(to: CGPoint(x: k * bw * 0.42 + (k >= 0 ? 1 : -1) * 0.02 * R, y: -h * 0.5), control: CGPoint(x: k * bw * 0.5, y: -h * 0.25))
                cg.stroke(t, inner, width: 0.022 * R)
            }
            let t = CGMutablePath()
            t.move(to: CGPoint(x: 0, y: -h + tip * 0.2))
            t.addLine(to: CGPoint(x: sd * 0.015 * R, y: -h - 0.05 * R))
            cg.stroke(t, CatDraw.color(p.top), width: 0.025 * R)
        }
        cg.restoreGState()
    }

    // MARK: Head pass

    private static func drawHead(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ o: CatDrawOptions, _ flat: G.FlatColors?, _ fur: CatFur.Strands?) {
        let p = look.preset, s = look.pose, R = L.R, rx = L.rx, ry = L.ry, fa = L.fa, W = L.warp
        let head = CatDraw.poly(G.supPoints(rx: rx, ry: ry, n: p.n, dy: 0, spike: p.fluff != 0 ? 0.035 : 0, count: 14, steps: L.steps, bend: L.bend))
        if L.full {
            cg.saveGState()
            cg.clip(head)
            CatDraw.linear(cg, [(0, CatDraw.color(p.top)), (1, CatDraw.color(p.bot))], from: (0.45 * rx, -ry), to: (-0.45 * rx, ry))
            cg.restoreGState()
        } else if let c = flat?.head {
            // Below Ø28 the coat's top-to-bottom shading cannot be seen: one flat fill instead of a shading pass.
            cg.fill(head, CatDraw.rgb(c))
        }

        cg.saveGState()
        cg.clip(head)
        cg.setAlpha(fa)
        drawMarkings(cg, p, L, flat)
        if let fur {
            // Fur strands on the head, bent by the warp like the markings, under the state tint.
            let width = CatFur.headWidth(p, R: R)
            for q in fur.head {
                let a = L.warp(q.x, q.y), b = L.warp(q.x2, q.y2), strand = CGMutablePath()
                strand.move(to: CGPoint(x: a.0, y: a.1)); strand.addLine(to: CGPoint(x: b.0, y: b.1))
                cg.stroke(strand, CatDraw.color(q.color), width: width)
            }
        }
        cg.setAlpha(1)
        // The state tint, rising from the chin.
        if o.tint && s.tint > 0.01 {
            let c = look.color.map { $0.rounded() }
            CatDraw.linear(cg, [(0, CatDraw.rgb(c, 0.4 * s.tint)), (1, CatDraw.rgb(c, 0))], from: (0, ry), to: (0, -ry * 0.2))
        }
        // A soft edge: dark on dark coats, a rim light on the rest. Nothing happens inside 0.913 R, so the shading starts there.
        // (Below Ø28 it is skipped: it would be a few pixels of shading.)
        if L.full {
            CatDraw.radial(cg, [(0, CatDraw.black(0)), (1, p.rimLight != nil ? CatDraw.white(0.07) : CatDraw.black(0.25))],
                           center: (0, 0), r0: 0.913 * R, r1: 1.35 * R)
        }
        let bl = max(s.blush, look.blushBase)
        if bl > 0.01 {
            for sd in [-1.0, 1.0] { cg.fill(wEll(W, sd * p.blushAt[0], p.blushAt[1], 0.17, 0.1, 14), CatDraw.rgb([255, 120, 150], 0.5 * bl * fa)) }
        }
        CatFace.drawEyes(cg, look, L)
        CatFace.drawNoseAndMouth(cg, look, L)
        cg.restoreGState()
        if p.rimLight != nil { cg.stroke(head, CatDraw.white(0.22), width: max(1, 0.013 * R)) }
    }

    // MARK: Markings (drawn flat, warped onto the turning head)

    private static func wEll(_ W: G.Warp, _ x: Double, _ y: Double, _ a: Double, _ b: Double, _ n: Int = 20) -> CGPath {
        CatDraw.poly((0...n).map { i in let t = Double(i) / Double(n) * CatMath.tau; return W(x + a * cos(t), y + b * sin(t)) })
    }

    private static func wBlob(_ W: G.Warp, _ x: Double, _ y: Double, _ a: Double, _ b: Double, _ rot: Double, _ seed: Double, _ n: Int = 32) -> CGPath {
        let c = cos(rot), s = sin(rot)
        return CatDraw.poly((0...n).map { i in
            let t = Double(i) / Double(n) * CatMath.tau, k = 1 + 0.12 * sin(3 * t + seed) + 0.06 * sin(5 * t + 2 * seed)
            let lx = a * cos(t) * k, ly = b * sin(t) * k
            return W(x + lx * c - ly * s, y + lx * s + ly * c)
        })
    }

    /// A quadratic stroke drawn flat and bent by the warp: (x0,y0) via (cx,cy) to (x1,y1).
    private static func wStroke(_ cg: CGContext, _ W: G.Warp, _ col: CGColor, _ w: Double, _ x0: Double, _ y0: Double, _ cx: Double, _ cy: Double, _ x1: Double, _ y1: Double) {
        let path = CGMutablePath()
        for i in 0...12 {
            let t = Double(i) / 12, m = 1 - t
            let q = W(m * m * x0 + 2 * m * t * cx + t * t * x1, m * m * y0 + 2 * m * t * cy + t * t * y1)
            i == 0 ? path.move(to: CGPoint(x: q.0, y: q.1)) : path.addLine(to: CGPoint(x: q.0, y: q.1))
        }
        cg.stroke(path, col, width: w)
    }

    private static func drawMarkings(_ cg: CGContext, _ p: CatPreset, _ L: G.Layout, _ flat: G.FlatColors?) {
        let R = L.R, W = L.warp, full = L.full
        let ny = -sin(p.nosePh) * p.ry
        switch p.coat {
        case "tuxedo":
            cg.fill(CatDraw.poly(G.momoWhite.map { W($0.0, $0.1) }), CatDraw.color(p.white ?? "#FFFFFF"))
        case "tabby":
            let stripe = CatDraw.color(p.stripe ?? "#000000"), sc = hexRGB(p.stripe ?? "#000000")
            let (bx, by) = W(0, -0.88)
            if full {
                CatDraw.radial(cg, [(0, CatDraw.rgb(sc, 0.9)), (1, CatDraw.rgb(sc, 0))], center: (bx, by), r0: 0, r1: 0.6 * R)
            } else {
                cg.fill(CatDraw.ellipse(bx, by, G.FlatFill.crown.rx * R, G.FlatFill.crown.ry * R), CatDraw.rgb(sc, G.FlatFill.crown.alpha))   // the crown band, without the shading pass
            }
            wStroke(cg, W, stripe, (full ? 0.1 : 0.13) * R, 0, -0.95, 0, -0.62, 0, -0.36)
            if full {
                for i in [-2.0, -1.0, 1.0, 2.0] { wStroke(cg, W, stripe, 0.042 * R, i * 0.05, -0.3 + abs(i) * 0.07, i * 0.09, -0.62, i * 0.17, -0.98) }
                for sd in [-1.0, 1.0] {
                    wStroke(cg, W, stripe, 0.04 * R, sd * 0.62, 0.04, sd * 0.82, -0.02, sd * 1.02, -0.08)
                    wStroke(cg, W, stripe, 0.045 * R, sd * 0.7, 0.3, sd * 0.88, 0.22, sd * 1.1, 0.22)
                    wStroke(cg, W, stripe, 0.045 * R, sd * 0.72, 0.46, sd * 0.9, 0.42, sd * 1.1, 0.46)
                }
            }
            for sd in [-1.0, 1.0] { cg.fill(wEll(W, sd * 0.17, ny + 0.12, 0.26, 0.21), CatDraw.color(p.light ?? p.top)) }
            cg.fill(wEll(W, 0, ny + 0.34, 0.22, 0.16), CatDraw.color(p.chinCol ?? p.top))
        case "point":
            let (mx, my) = W(0, ny - 0.12), pc = hexRGB(p.point ?? "#000000")
            if full {
                cg.saveGState()
                cg.translateBy(x: mx, y: my)
                cg.scaleBy(x: 1.55, y: 1)
                CatDraw.radial(cg, [(0, CatDraw.rgb(pc, 0.97)), (0.6, CatDraw.rgb(pc, 0.82)), (1, CatDraw.rgb(pc, 0))], center: (0, 0), r0: 0.05 * R, r1: 0.66 * R)
                cg.restoreGState()
            } else if let c = flat?.point {
                // The contract's flat mask: the colour is `flatFillColors(p).point`, the size and alpha are `FlatFill.point`.
                cg.fill(CatDraw.ellipse(mx, my, G.FlatFill.point.rx * R, G.FlatFill.point.ry * R), CatDraw.rgb(c, G.FlatFill.point.alpha))
            }
        case "calico":
            for q in p.patches ?? [] { cg.fill(wBlob(W, q.x, q.y, q.a, q.b, q.rot, Double(q.seed)), CatDraw.color(q.color)) }
        default:
            break
        }
        if let m = p.muzzle {
            for sd in [-1.0, 1.0] { cg.fill(wEll(W, sd * 0.16, ny + 0.12, 0.24, 0.19), CatDraw.color(m)) }
            cg.fill(wEll(W, 0, ny + 0.32, 0.2, 0.14), CatDraw.color(m))
        }
        if p.wrinkles != nil && full {
            for (y, w) in [(-0.42, 0.2), (-0.54, 0.27), (-0.66, 0.18)] { wStroke(cg, W, CatDraw.color(p.bot), 0.026 * R, -w, y + 0.03, 0, y - 0.05, w, y + 0.03) }
        }
    }

    // MARK: Front pass

    private static func drawFront(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ L: G.Layout, _ flat: G.FlatColors?, _ collar: CatCollarPaint?, _ dressed: CatDressed?) {
        let R = L.R
        if p.ear.fold != nil { for e in L.ears { drawEar(cg, p, e, R: R, full: L.full, front: true, flat: flat?.ears[e.sd < 0 ? 0 : 1]) } }
        // The collar sits over the head and the folded ears and under the whiskers (the contract's `collarPass`), at every size from Ø12 up.
        if let collar, let g = G.collarGeometry(p, R: R, warp: L.warp, style: collar.style, dpr: collar.dpr) {
            CatEffects.drawCollar(cg, g, color: collar.color, full: L.full, dpr: collar.dpr)
        }
        // The outfit's `neck` slot over the collar (scarf, bandana, bell), then its `top` slot (hats, crown, glasses, clips, bow, flower): both under the whiskers, the badge and the particles.
        if let dressed { CatOutfitDraw.paint(cg, dressed, slot: "neck"); CatOutfitDraw.paint(cg, dressed, slot: "top") }
        if L.full && L.fa > 0.01 { CatFace.drawWhiskers(cg, p, s, L) }
    }
}
