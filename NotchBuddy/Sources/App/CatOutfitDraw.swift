import CoreGraphics
import Foundation

// Paints an outfit (sub-project I): the shapes `CatOutfit.geometry` returns, into the head's frame, at the three slots the renderer calls (`behind` after the ears, `neck` after the collar,
// `top` after `neck`, always before the whiskers). The painter only paints: it never reads a coat, and the maths is `CatOutfit`. The colours are the roles of `Theme.Outfits`
// (shared/theme.json, generated); the coat itself is never recoloured. In the head's frame, so it turns, tilts and squashes with the head.

/// The shapes of one outfit on one cat in one pose, ready to paint.
struct CatDressed {
    var shapes: [CatOutfit.Shape]
    var edge: String
    var fade: Double
}

@MainActor
enum CatOutfitDraw {
    /// In every build (Debug, Release and App Store): `scripts/check-app-binary.sh` looks for it (19 bytes: a shorter string would hide in the code where `strings` cannot see it).
    static let marker = "NM_WARDROBE_OUTFITS"

    /// The outfit for a cat in the big-cat role: `id` is the resolved outfit (`CatConfig.outfit`); nil for `none` and anything that is not one of the 16 drawn outfits. This is what the
    /// five big-cat views call; the small cats and the kittens never do.
    /// `ceiling` is the top of the canvas the cat is drawn into when it is tighter than the strip (`CatOutfitPaint.ceiling`): the tall coats are shortened to the room under it.
    static func big(_ id: String, dpr: Double, fade: Double = 1, ceiling: Double? = nil) -> CatOutfitPaint? {
        Wardrobe.drawn.contains(id) ? CatOutfitPaint(id: id, role: "big", dpr: dpr, fade: fade, ceiling: ceiling) : nil
    }

    /// The outfit for a draw, or nil when the cat is bare: not in a big-cat role, no outfit, or nothing to draw. `ek` is the ears' scale as the renderer drew them; `headY` and `ceiling`
    /// are the compact notch's strip, which gives hats and bunny ears the room the ears get; the paint's own `ceiling` (a canvas tighter than the strip) decides for the outfit when it has one.
    static func dressed(_ paint: CatOutfitPaint?, _ p: CatPreset, _ s: CatPose, D: Double, full: Bool, earScale ek: Double, collar: String?, headY: Double, ceiling: Double?) -> CatDressed? {
        guard let paint, Wardrobe.worn(paint.role), paint.fade > 0.001 else { return nil }
        var o = CatOutfit.Options(dpr: paint.dpr, detail: full ? "full" : "compact", earScale: ek, collar: collar ?? "off")
        o.headY = headY; o.ceiling = paint.ceiling ?? ceiling
        var shapes = CatOutfit.geometry(paint.id, p, s, D: D, o)
        guard !shapes.isEmpty else { return nil }
        // A canvas of its own (`paint.ceiling`, from Ø28 up): the outfit's top lands on the line. The natural outfit is measured (a detail rises past a hat's tip, the party hat's star; a
        // base under the crown, the bunny ears' roots, leaves the room half empty); if it is under the line it stays natural, else the hat's height is its natural height less what pokes
        // (a hat's tip rises one for one with its height). Below Ø28 (the compact detail, the notch's Ø20 and Ø18) the strip's fit is all there is, so a cat handed over to the island's own
        // never changes.
        if full, let line = paint.ceiling, line.isFinite, headY.isFinite {
            let target = line + CatGeometry.earFitMargin
            func top(_ room: Double) -> (y: Double, shapes: [CatOutfit.Shape]) {
                o.room = room
                let sh = CatOutfit.geometry(paint.id, p, s, D: D, o)
                return (headY + (sh.map(Self.topY).min() ?? .infinity), sh)
            }
            let natural = top(.infinity)
            shapes = natural.shapes
            if natural.y < target {
                // the natural height, in the room's units: the floor's height plus how much higher the natural tip is than the floor's
                let height = CatOutfit.Min.height / (paint.dpr > 0 ? paint.dpr : 2) + top(0).y - natural.y
                shapes = top(max(0, height - (target - natural.y))).shapes
            }
        }
        return CatDressed(shapes: shapes, edge: CatOutfit.edge(p), fade: min(1, paint.fade))
    }

    /// The highest point (the smallest y, head-local) a shape paints, its stroke included.
    private static func topY(_ sh: CatOutfit.Shape) -> Double {
        let half = sh.stroke == nil ? 0 : sh.sw / 2
        switch sh.k {
        case .ellipse: return sh.y - (pow(sh.rx * sin(sh.rot), 2) + pow(sh.ry * cos(sh.rot), 2)).squareRoot() - half
        case .poly, .curve: return (sh.pts.map(\.y).min() ?? .infinity) - half
        }
    }

    /// Paints the shapes of one slot, in order, into the head's frame.
    static func paint(_ cg: CGContext, _ d: CatDressed, slot: String) {
        for sh in d.shapes where sh.slot == slot {
            let path = CGMutablePath()
            switch sh.k {
            case .ellipse:
                path.addEllipse(in: CGRect(x: -max(sh.rx, 0.01), y: -max(sh.ry, 0.01), width: 2 * max(sh.rx, 0.01), height: 2 * max(sh.ry, 0.01)), transform: CGAffineTransform(rotationAngle: sh.rot).concatenating(CGAffineTransform(translationX: sh.x, y: sh.y)))
            case .poly, .curve:
                for (i, q) in sh.pts.enumerated() { i == 0 ? path.move(to: CGPoint(x: q.x, y: q.y)) : path.addLine(to: CGPoint(x: q.x, y: q.y)) }
                if sh.k == .poly { path.closeSubpath() }
            }
            let alpha = sh.a * d.fade
            if let fill = sh.fill, let hex = hex(fill, edge: d.edge) { cg.fill(path, CatDraw.color(hex, alpha: alpha)) }
            if let stroke = sh.stroke, sh.sw > 0, let hex = hex(stroke, edge: d.edge) { cg.stroke(path, CatDraw.color(hex, alpha: alpha), width: sh.sw) }
        }
    }

    /// A colour role as "#RRGGBB": the keys of `Theme.Outfits`, and "edge" for the coat's thin edge (`light` on a dark head, `dark` on a light one). nil for a role that is not one.
    static func hex(_ role: String, edge: String) -> String? {
        typealias T = Theme.Outfits
        switch role {
        case "edge": return edge == "light" ? T.edgeLight : T.edgeDark
        case "edgeLight": return T.edgeLight
        case "edgeDark": return T.edgeDark
        case "partyA": return T.partyA
        case "partyB": return T.partyB
        case "partyStar": return T.partyStar
        case "santaRed": return T.santaRed
        case "fur": return T.fur
        case "witchHat": return T.witchHat
        case "witchBand": return T.witchBand
        case "gold": return T.gold
        case "goldDark": return T.goldDark
        case "bunnyOuter": return T.bunnyOuter
        case "bunnyInner": return T.bunnyInner
        case "lens": return T.lens
        case "frame": return T.frame
        case "glint": return T.glint
        case "beanieBody": return T.beanieBody
        case "beanieCuff": return T.beanieCuff
        case "bowRed": return T.bowRed
        case "bowKnot": return T.bowKnot
        case "scarfA": return T.scarfA
        case "scarfB": return T.scarfB
        case "rim": return T.rim
        case "glassTint": return T.glassTint
        case "gemA": return T.gemA
        case "gemB": return T.gemB
        case "gemC": return T.gemC
        case "silver": return T.silver
        case "bandanaRed": return T.bandanaRed
        case "white": return T.white
        case "fishBody": return T.fishBody
        case "fishFin": return T.fishFin
        case "petal": return T.petal
        case "shrimp": return T.shrimp
        case "shrimpDark": return T.shrimpDark
        case "blossom": return T.blossom
        case "blossomDeep": return T.blossomDeep
        case "leaf": return T.leaf
        default: return nil
        }
    }
}
