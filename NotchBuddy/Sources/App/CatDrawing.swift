import CoreGraphics
import CoreText
import Foundation

// Colours, paths and text for the cat renderer. Everything draws into a CGContext whose y axis points down (the SwiftUI Canvas's
// `withCGContext` already is, and the contact-sheet script flips its bitmap context to match), so a drawing call here reads like the
// prototype's Canvas 2D call it was ported from.

@MainActor
enum CatDraw {
    // MARK: Colours

    private static var cache: [String: CGColor] = [:]
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A preset colour ("#RRGGBB" or "rgba(r,g,b,a)", the strings the contract holds) as a CGColor, cached.
    static func color(_ s: String) -> CGColor {
        if let c = cache[s] { return c }
        var r = 0.0, g = 0.0, b = 0.0, a = 1.0
        if s.hasPrefix("#") {
            let v = hexRGB(s)
            r = v[0] / 255; g = v[1] / 255; b = v[2] / 255
        } else if s.hasPrefix("rgba(") {
            let n = s.dropFirst(5).dropLast().split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if n.count >= 3 { r = n[0] / 255; g = n[1] / 255; b = n[2] / 255 }
            if n.count >= 4 { a = n[3] }
        }
        let c = CGColor(colorSpace: space, components: [r, g, b, a])!
        cache[s] = c
        return c
    }

    /// A colour with its alpha multiplied.
    static func color(_ s: String, alpha: Double) -> CGColor {
        let c = color(s)
        return c.copy(alpha: c.alpha * alpha) ?? c
    }

    /// The colour halfway (or `t` of the way) from a to b.
    static func mix(_ a: CGColor, _ b: CGColor, _ t: Double) -> CGColor {
        let x = a.components ?? [0, 0, 0, 1], y = b.components ?? [0, 0, 0, 1]
        return CGColor(colorSpace: space, components: (0..<4).map { CGFloat(lerp(Double(x[$0]), Double(y[$0]), t)) })!
    }

    /// [r, g, b] in 0...255 with an alpha.
    static func rgb(_ c: [Double], _ a: Double = 1) -> CGColor {
        CGColor(colorSpace: space, components: [c[0] / 255, c[1] / 255, c[2] / 255, a])!
    }

    static func white(_ a: Double) -> CGColor { CGColor(colorSpace: space, components: [1, 1, 1, a])! }
    static func black(_ a: Double) -> CGColor { CGColor(colorSpace: space, components: [0, 0, 0, a])! }

    // MARK: Gradients

    static func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { CGFloat($0.0) })!
    }

    /// A linear gradient padded past both ends, like a Canvas gradient.
    static func linear(_ cg: CGContext, _ stops: [(Double, CGColor)], from: (Double, Double), to: (Double, Double)) {
        cg.drawLinearGradient(gradient(stops), start: CGPoint(x: from.0, y: from.1), end: CGPoint(x: to.0, y: to.1),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// A radial gradient between two concentric circles, padded past both ends like a Canvas gradient.
    static func radial(_ cg: CGContext, _ stops: [(Double, CGColor)], center: (Double, Double), r0: Double, r1: Double) {
        let c = CGPoint(x: center.0, y: center.1)
        cg.drawRadialGradient(gradient(stops), startCenter: c, startRadius: r0, endCenter: c, endRadius: r1,
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // MARK: Paths

    static func poly(_ pts: [(Double, Double)]) -> CGPath {
        let p = CGMutablePath()
        for (i, q) in pts.enumerated() { i == 0 ? p.move(to: CGPoint(x: q.0, y: q.1)) : p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }

    /// A rounded rectangle whose radius is held to half the short side, like the prototype's `rr`.
    static func roundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> CGPath {
        let rr = max(0, min(r, w / 2, h / 2))
        return CGPath(roundedRect: CGRect(x: x, y: y, width: max(0, w), height: max(0, h)), cornerWidth: rr, cornerHeight: rr, transform: nil)
    }

    static func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    static func circle(_ x: Double, _ y: Double, _ r: Double) -> CGPath { ellipse(x, y, r, r) }

    /// A heart of size `s`, centred on its middle.
    static func heart(_ s: Double) -> CGPath {
        let q = CGMutablePath()
        q.move(to: CGPoint(x: 0, y: 0.38 * s))
        q.addCurve(to: CGPoint(x: 0, y: -0.38 * s), control1: CGPoint(x: -1.05 * s, y: -0.15 * s), control2: CGPoint(x: -0.5 * s, y: -0.95 * s))
        q.addCurve(to: CGPoint(x: 0, y: 0.38 * s), control1: CGPoint(x: 0.5 * s, y: -0.95 * s), control2: CGPoint(x: 1.05 * s, y: -0.15 * s))
        q.closeSubpath()
        return q
    }

    /// A five-pointed star with the given outer and inner radii, one point straight up.
    static func star(_ outer: Double, _ inner: Double) -> CGPath {
        poly((0..<10).map { k in
            let r = k % 2 == 1 ? inner : outer, a = -Double.pi / 2 + Double(k) * Double.pi / 5
            return (cos(a) * r, sin(a) * r)
        })
    }

    /// A quadratic Bézier from (x0,y0) via (cx,cy) to (x1,y1), as a stroke-able path.
    static func quad(_ x0: Double, _ y0: Double, _ cx: Double, _ cy: Double, _ x1: Double, _ y1: Double) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addQuadCurve(to: CGPoint(x: x1, y: y1), control: CGPoint(x: cx, y: cy))
        return p
    }

    // MARK: Text

    enum Anchor { case center, left, right }

    /// Text centred on (x, y) (or starting or ending at x), in a context whose y axis points down. `bold` uses the heavy system face.
    static func text(_ cg: CGContext, _ s: String, x: Double, y: Double, size: Double, bold: Bool, color: CGColor, anchor: Anchor = .center) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let left = anchor == .center ? x - b.midX : anchor == .left ? x - b.minX : x - b.maxX
        cg.saveGState()
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cg.textPosition = CGPoint(x: left, y: y + b.midY)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }
}

extension CGContext {
    func fill(_ path: CGPath, _ color: CGColor) {
        setFillColor(color)
        addPath(path)
        fillPath()
    }

    func stroke(_ path: CGPath, _ color: CGColor, width: Double, cap: CGLineCap = .round, join: CGLineJoin = .round) {
        setStrokeColor(color)
        setLineWidth(width)
        setLineCap(cap)
        setLineJoin(join)
        addPath(path)
        strokePath()
    }

    /// Clips to a path for the rest of the current graphics state.
    func clip(_ path: CGPath) {
        addPath(path)
        clip()
    }
}
