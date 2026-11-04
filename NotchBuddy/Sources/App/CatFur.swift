import CoreGraphics
import Foundation

// Optional fur lines (Settings → Cat → Fur lines, off by default): seeded strands on the head and on a ruff, built once per coat. Port of the
// prototype's `furStrands` (design/prototype/notchmeow.html): the same seeds (13 for the head, 7 for the ruff), so the same strands. They are
// not part of the contract (cat-core.js holds no fur): the renderer draws them from seeded noise, and tests/CatFurTests.swift pins them
// against the prototype's own numbers.

enum CatFur {
    /// A head strand, in units of R, from (x, y) to (x2, y2), with its colour ("rgba(...)").
    struct HeadStrand { var x: Double, y: Double, x2: Double, y2: Double, color: String }
    /// A ruff strand, in units of R: centred on (x, y), along (ux, uy), L long.
    struct RuffStrand { var x: Double, y: Double, ux: Double, uy: Double, L: Double, color: String }
    struct Strands { var head: [HeadStrand]; var ruff: [RuffStrand] }

    /// What a coat without its own `furOpts` uses (a flat-coloured shorthair).
    static let fallback = CatPreset.FurOpts(n: 420, l0: 0.04, l1: 0.05, w: 0.01, dark: "rgba(0,0,0,.22)", light: "rgba(255,255,255,.2)", wDark: nil, wLight: nil)

    /// Fur is drawn on a full-detail cat from a head radius of 30 px (a head of Ø60 and more), and never on a hairless coat.
    static func shows(_ p: CatPreset, R: Double, full: Bool) -> Bool { full && R >= 30 && p.hairless == nil }

    /// The stroke width of a head strand, in px.
    static func headWidth(_ p: CatPreset, R: Double) -> Double { max(0.5, (p.furOpts ?? fallback).w * R) }

    @MainActor private static var cache: [String: Strands] = [:]

    /// The strands of a coat (a kitten has its own: its head is another shape), built the first time and kept.
    @MainActor static func strands(for p: CatPreset) -> Strands {
        let key = p.name + (p.kitten == true ? "-kitten" : "")
        if let s = cache[key] { return s }
        let s = build(p)
        cache[key] = s
        return s
    }

    private static func build(_ p: CatPreset) -> Strands {
        let o = p.furOpts ?? fallback, rx = p.rx, ry = p.ry
        var head: [HeadStrand] = [], ruff: [RuffStrand] = []
        // Momo's white map: strands that start on it use the white colours (a winding test, like the canvas's isPointInPath).
        var white: CGPath?
        if p.coat == "tuxedo" {
            let path = CGMutablePath()
            for (i, q) in CatGeometry.momoWhite.enumerated() { i == 0 ? path.move(to: CGPoint(x: q.0 * 100, y: q.1 * 100)) : path.addLine(to: CGPoint(x: q.0 * 100, y: q.1 * 100)) }
            path.closeSubpath()
            white = path
        }
        let eyes = [-1.0, 1.0].map { sd in (x: sin(sd * p.eye.th) * cos(p.eye.ph) * rx, y: -sin(p.eye.ph) * ry) }
        let nose = (x: 0.0, y: -sin(p.nosePh) * ry)
        var rand = CatRNG(seed: 13)
        for _ in 0..<o.n {
            let x = (rand.next() * 2 - 1) * rx, y = (rand.next() * 2 - 1) * ry
            if pow(x / rx, 2) + pow(y / ry, 2) > 1 { continue }
            if eyes.contains(where: { hypot(x - $0.x, (y - $0.y) * 1.25) < 0.3 }) || hypot(x - nose.x, y - nose.y - 0.1) < 0.32 { continue }
            let dx: Double, dy: Double
            if y < -0.32 { dx = x * 0.35; dy = -1 } else { dx = x; dy = y + 0.5 }
            let m = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy)
            let len = o.l0 + rand.next() * o.l1
            let onWhite = white?.contains(CGPoint(x: x * 100, y: y * 100), using: .winding) ?? false
            let dark = rand.next() < 0.55
            head.append(HeadStrand(x: x, y: y, x2: x + dx / m * len, y2: y + dy / m * len,
                                   color: dark ? (onWhite ? o.wDark ?? o.dark : o.dark) : (onWhite ? o.wLight ?? o.light : o.light)))
        }
        if let r = p.ruff {
            let e = 2 / 2.4
            rand = CatRNG(seed: 7)
            for _ in 0..<300 {
                let a = rand.next() * CatMath.tau, c = cos(a), s = sin(a)
                let ex = (c > 0 ? 1.0 : c < 0 ? -1.0 : 0) * pow(abs(c), e) * r.rx, ey = (s > 0 ? 1.0 : s < 0 ? -1.0 : 0) * pow(abs(s), e) * r.ry
                let f = 0.7 + rand.next() * 0.32, x = ex * f, y = ey * f + r.dy
                var dx = ex, dy = ey + 0.35 * max(0, s)
                let m = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy)
                dx /= m; dy /= m
                let j = (rand.next() - 0.5) * 0.5
                let ux = dx * cos(j) - dy * sin(j), uy = dx * sin(j) + dy * cos(j), len = 0.05 + rand.next() * 0.08
                ruff.append(RuffStrand(x: x, y: y, ux: ux, uy: uy, L: len, color: rand.next() < 0.5 ? "rgba(214,192,156,.45)" : "rgba(84,66,50,.38)"))
            }
        }
        return Strands(head: head, ruff: ruff)
    }
}
