import CoreGraphics
import Foundation

@main
enum WardrobeDrawTests {
    static func ink(_ px: [UInt8]) -> Int { stride(from: 3, to: px.count, by: 4).reduce(0) { $0 + Int(px[$1]) } }

    /// One cat drawn into a bitmap, with or without an outfit.
    @MainActor static func draw(_ cat: String, D: Double, w: Int = 160, h: Int = 160, paint: CatOutfitPaint? = nil, collar: CatCollarPaint? = nil, ceiling: Double? = nil, cy: Double? = nil, pose: CatPose = CatPose()) -> [UInt8] {
        Bitmap.render(w, h) { cg in
            var o = CatDrawOptions(badge: false)
            o.outfit = paint; o.collar = collar; o.earCeiling = ceiling
            CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(cat), pose: pose), cx: Double(w) / 2, cy: cy ?? Double(h) / 2, D: D, o)
        }
    }

    @MainActor static func main() {
        CT.section("colour roles: every role an outfit uses is a colour")
        var unknown = Set<String>()
        for cat in CatPresets.ids {
            let p = CatPresets.byID(cat)
            for id in Wardrobe.drawn {
                for D in [18.0, 27.0, 28.0, 64.0] {
                    for sh in CatOutfit.geometry(id, p, CatPose(), D: D, CatOutfit.Options(dpr: 2, collar: "tag")) {
                        for role in [sh.fill, sh.stroke].compactMap({ $0 }) where CatOutfitDraw.hex(role, edge: "light") == nil || CatOutfitDraw.hex(role, edge: "dark") == nil { unknown.insert(role) }
                    }
                }
            }
        }
        CT.check("no role is unknown (16 outfits, 16 coats, four sizes)", unknown.sorted(), [])
        CT.check("the coat's edge is the theme's light or dark edge", [CatOutfitDraw.hex("edge", edge: "light"), CatOutfitDraw.hex("edge", edge: "dark")], [Theme.Outfits.edgeLight, Theme.Outfits.edgeDark])
        CT.check("a role that is not one has no colour", CatOutfitDraw.hex("fancy", edge: "dark"), nil)
        CT.check("the marker the binary check looks for is 19 bytes long", [CatOutfitDraw.marker, "\(CatOutfitDraw.marker.utf8.count)"], ["NM_WARDROBE_OUTFITS", "19"])

        CT.section("who wears it: the role decides, never the diameter")
        let bare = draw("momo", D: 64)
        let big = draw("momo", D: 64, paint: CatOutfitDraw.big("santahat", dpr: 1))
        CT.checkTrue("a big cat in a Santa hat is not the bare cat", big != bare && ink(big) > ink(bare))
        for role in ["small", "kitten", "Big", " big", "", "desktop"] {
            CT.checkTrue("a cat in the role \"\(role)\" is bare, pixel for pixel", draw("momo", D: 64, paint: CatOutfitPaint(id: "santahat", role: role, dpr: 1)) == bare)
        }
        let tiny = draw("momo", D: 12, w: 40, h: 40), tinyBig = draw("momo", D: 12, w: 40, h: 40, paint: CatOutfitDraw.big("crown", dpr: 1))
        CT.checkTrue("a big-cat role at Ø12 is dressed, and a small cat at Ø66 is not", tiny != tinyBig && draw("momo", D: 66, paint: CatOutfitPaint(id: "crown", role: "small", dpr: 1)) == draw("momo", D: 66))
        CT.check("none, auto and a made-up name are no outfit", [CatOutfitDraw.big("none", dpr: 1) == nil, CatOutfitDraw.big("auto", dpr: 1) == nil, CatOutfitDraw.big("fancyhat", dpr: 1) == nil], [true, true, true])
        let p = CatPresets.byID("momo")
        CT.checkTrue("a bare cat costs no geometry: the role is checked first", CatOutfitDraw.dressed(CatOutfitPaint(id: "crown", role: "small", dpr: 2), p, CatPose(), D: 64, full: true, earScale: 1, collar: nil, headY: 80, ceiling: nil) == nil)
        CT.checkTrue("and a fade of 0 costs none either", CatOutfitDraw.dressed(CatOutfitDraw.big("crown", dpr: 2, fade: 0), p, CatPose(), D: 64, full: true, earScale: 1, collar: nil, headY: 80, ceiling: nil) == nil)

        CT.section("the fade: the greeting puts the outfit on once the cat has settled")
        let half = draw("momo", D: 64, paint: CatOutfitDraw.big("santahat", dpr: 1, fade: 0.5))
        CT.checkTrue("0 is bare", draw("momo", D: 64, paint: CatOutfitDraw.big("santahat", dpr: 1, fade: 0)) == bare)
        CT.checkTrue("half shows between bare and full", ink(bare) < ink(half) && ink(half) < ink(big))

        CT.section("every outfit on every coat, big, at Ø64 and at the compact notch's Ø20")
        var blank: [String] = [], same: [String] = [], above: [String] = []
        for cat in CatPresets.ids {
            for id in Wardrobe.drawn {
                let a = draw(cat, D: 64), b = draw(cat, D: 64, paint: CatOutfitDraw.big(id, dpr: 1))
                if b == a { blank.append("\(id) on \(cat) Ø64") }
                // The notch's Ø20 cat: a strip from y 20 to 52 (the island's top is the screen's top), the ears fitted under it, the outfit given the same room.
                let c = draw(cat, D: 20, w: 60, h: 80, ceiling: 20, cy: 36), d = draw(cat, D: 20, w: 60, h: 80, paint: CatOutfitDraw.big(id, dpr: 2), ceiling: 20, cy: 36)
                if c == d { blank.append("\(id) on \(cat) Ø20") }
                if let top = Bitmap.bounds(d, 60)?.top, top < 19 { above.append("\(id) on \(cat) Ø20 reaches row \(top)") }
                if Bitmap.bounds(d, 60) == nil { same.append("\(id) on \(cat) is empty") }
            }
        }
        CT.checkRows("each one changes the picture (256 pairs at Ø64 and at Ø20)", blank)
        CT.checkRows("and never draws above the strip at Ø20 (a pixel of anti-aliasing allowed)", above)
        CT.checkRows("and the picture is never empty", same)

        CT.section("headroom: the outfit's own ceiling, for a canvas that is tighter than the notch's strip")
        // A tall outfit on a canvas with too little room above the head (a Settings preview, cat 2 in the overview, the upload bar, the ghost, the greeting) is fitted to the canvas top,
        // exactly as the compact notch fits it to the strip's: shortened to the room, held at the floor, never hidden. `CatOutfitPaint.ceiling` is that line; the ears never use it.
        var cutOff: [String] = [], notShortened: [String] = [], hidden: [String] = [], short: [String] = []
        for cat in ["noodle", "momo"] {
            let bareTop = Bitmap.bounds(draw(cat, D: 64, h: 200, cy: 110), 160)!.top
            for id in ["partyhat", "witchhat", "santahat", "bunnyears"] {
                let freeTop = Bitmap.bounds(draw(cat, D: 64, h: 200, paint: CatOutfitDraw.big(id, dpr: 1), cy: 110), 160)!.top
                let line = Double(freeTop) + 12   // a canvas whose top is 12 rows under the free outfit's tip
                var tight = CatOutfitDraw.big(id, dpr: 1)!
                tight.ceiling = line
                let t = draw(cat, D: 64, h: 200, paint: tight, cy: 110)
                if Double(Bitmap.bounds(t, 160)!.top) < min(line, Double(bareTop)) - 1 { cutOff.append("\(id) on \(cat)") }
                if Bitmap.bounds(t, 160)!.top <= freeTop { notShortened.append("\(id) on \(cat)") }
                if t == draw(cat, D: 64, h: 200, cy: 110) { hidden.append("\(id) on \(cat)") }
                if Double(Bitmap.bounds(t, 160)!.top) > line + 3 { short.append("\(id) on \(cat)") }   // the room is used, not left half empty (the bunny ears' base is under the crown)
            }
        }
        CT.checkRows("a tall outfit never draws above the canvas line (a pixel of anti-aliasing allowed)", cutOff)
        CT.checkRows("it is shortened to the room, not left at its natural height", notShortened)
        CT.checkRows("and it is still there", hidden)
        CT.checkRows("it reaches the canvas line (within 3 rows), whatever its base sits under the crown", short)
        let noodle = CatPresets.byID("noodle")
        func extent(_ d: CatDressed?) -> Double? {
            guard let d else { return nil }
            let ys = d.shapes.flatMap { sh in sh.k == .ellipse ? [sh.y - sh.ry, sh.y + sh.ry] : sh.pts.map(\.y) }
            return ys.max()! - ys.min()!
        }
        func witch(ceiling: Double?) -> CatOutfitPaint { var q = CatOutfitDraw.big("witchhat", dpr: 2)!; q.ceiling = ceiling; return q }
        let natural = extent(CatOutfitDraw.dressed(witch(ceiling: nil), noodle, CatPose(), D: 64, full: true, earScale: 1, collar: nil, headY: 100, ceiling: nil))!
        let held = extent(CatOutfitDraw.dressed(witch(ceiling: 100), noodle, CatPose(), D: 64, full: true, earScale: 1, collar: nil, headY: 100, ceiling: nil))
        CT.checkTrue("with no room at all the hat is held at the floor (3 pt at 2x), not hidden", held != nil && held! >= 3 - 0.01 && held! < natural)
        CT.check("the paint's ceiling decides over the draw's (the strip's) for the outfit", extent(CatOutfitDraw.dressed(witch(ceiling: 100), noodle, CatPose(), D: 64, full: true, earScale: 1, collar: nil, headY: 100, ceiling: -1000)), held)
        CT.check("and without one the draw's is used, as it always was", extent(CatOutfitDraw.dressed(witch(ceiling: nil), noodle, CatPose(), D: 64, full: true, earScale: 1, collar: nil, headY: 100, ceiling: 100)), held)
        // The ears are the shipped look: the outfit's ceiling never touches them, and a ceiling equal to the strip's changes nothing.
        func with(_ id: String, _ outfitCeiling: Double?, strip: Double?) -> [UInt8] {
            var q = CatOutfitPaint(id: id, role: "big", dpr: 1); q.ceiling = outfitCeiling
            return draw("noodle", D: 20, w: 60, h: 80, paint: q, ceiling: strip, cy: 36)
        }
        CT.checkTrue("a bare cat with an outfit ceiling in its paint is the bare cat, ears included", with("none", 0, strip: 20) == draw("noodle", D: 20, w: 60, h: 80, ceiling: 20, cy: 36))
        CT.checkTrue("a coat that does not rise (sunglasses) is the same with and without it: the ears are fitted by the strip alone", with("sunglasses", 0, strip: 20) == with("sunglasses", nil, strip: 20))
        CT.checkTrue("at Ø20 a ceiling equal to the strip's is the strip's, pixel for pixel (the greeting's cat is handed over to the island's with no change)", with("witchhat", 20, strip: 20) == with("witchhat", nil, strip: 20)
            && with("bunnyears", 20, strip: 20) == with("bunnyears", nil, strip: 20))
        CT.checkTrue("and a tighter one than the strip's shortens the hat", with("witchhat", 26, strip: 20) != with("witchhat", nil, strip: 20))

        CT.section("the wardrobe's tile (66x56 at Ø34) and the Debug preview (200x170 at Ø96): the canvas top is the line")
        // The tile and the Debug panel's canvas are tight: the tall hats of a tall coat are shortened to the room under the canvas top, never cut. The bitmap has 40 spare rows above the canvas.
        var tileCut: [String] = [], tileHidden: [String] = []
        for (w, h, D, fy) in [(66, 56, 34.0, 0.66), (200, 170, 96.0, 0.64)] {
            for cat in ["noodle", "latte"] {
                for id in ["partyhat", "witchhat", "bunnyears", "santahat"] {
                    var paint = CatOutfitDraw.big(id, dpr: 2)!
                    paint.ceiling = 40
                    let px = Bitmap.render(w, h + 40) { cg in
                        var o = CatDrawOptions(tint: false, badge: false)
                        o.outfit = paint
                        CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(cat)), cx: Double(w) / 2, cy: 40 + Double(h) * fy, D: D, o)
                    }
                    let bare = Bitmap.render(w, h + 40) { cg in
                        CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(cat)), cx: Double(w) / 2, cy: 40 + Double(h) * fy, D: D, CatDrawOptions(tint: false, badge: false))
                    }
                    let bareTop = Bitmap.bounds(bare, w)!.top
                    if Double(Bitmap.bounds(px, w)!.top) < min(40, Double(bareTop)) - 1 { tileCut.append("\(id) on \(cat) Ø\(Int(D))") }
                    if px == bare { tileHidden.append("\(id) on \(cat) Ø\(Int(D))") }
                }
            }
        }
        CT.checkRows("nothing of a tall outfit is above the canvas top (a pixel of anti-aliasing allowed)", tileCut)
        CT.checkRows("and it is shortened, not hidden", tileHidden)

        CT.section("the party hat's star lands on the line, whatever room the line leaves")
        // A line 1.35R to 1.54R over the crown leaves the hat at its natural height, and the star (0.24R past the tip) is the part that has to give way.
        var starPokes: [String] = []
        for cat in ["noodle", "latte"] {
            let p = CatPresets.byID(cat), R = CatGeometry.layout(p, CatPose(), cx: 0, cy: 0, D: 96, CatGeometry.Options()).R
            let topY = CatOutfit.anchors(p, CatPose(), D: 96, CatOutfit.Options(dpr: 2, detail: "full")).top.y
            for k in [1.0, 1.2, 1.35, 1.4, 1.45, 1.5, 1.54, 1.8, 2.5] {
                var paint = CatOutfitDraw.big("partyhat", dpr: 2)!
                paint.ceiling = 100 + topY - CatGeometry.earFitMargin - k * R   // room = k R over the crown (headY 100)
                guard let d = CatOutfitDraw.dressed(paint, p, CatPose(), D: 96, full: true, earScale: 1, collar: nil, headY: 100, ceiling: nil) else { starPokes.append("\(cat) \(k) is bare"); continue }
                let top = 100 + d.shapes.flatMap { sh in sh.k == .ellipse ? [sh.y - sh.ry] : sh.pts.map(\.y) }.min()!
                if top < paint.ceiling! + CatGeometry.earFitMargin - 0.3 { starPokes.append("\(cat) at \(k)R pokes \(paint.ceiling! + CatGeometry.earFitMargin - top)") }
            }
        }
        CT.checkRows("the star is never above the line (nine rooms, two coats, Ø96)", starPokes)

        CT.section("the collar is drawn first and never changed")
        let tag = CatCollarPaint(style: "tag", color: "#E07950", dpr: 1)
        let collared = draw("momo", D: 64, paint: nil, collar: tag), bell = draw("momo", D: 64, paint: CatOutfitDraw.big("bell", dpr: 1), collar: tag), bellOff = draw("momo", D: 64, paint: CatOutfitDraw.big("bell", dpr: 1))
        CT.checkTrue("a bell over a collar and a bell with the collar off both draw", bell != collared && bellOff != bare)
        let hat = draw("momo", D: 64, paint: CatOutfitDraw.big("crown", dpr: 1), collar: tag), lower = 80 * 160 * 4   // the head's middle and down: the crown sits above it
        CT.checkTrue("a hat leaves the pixels from the head's middle down, collar included, as they were", Array(hat[lower...]) == Array(collared[lower...]))
        CT.finish()
    }
}
