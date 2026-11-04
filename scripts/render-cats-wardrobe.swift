import CoreGraphics
import Foundation

// The wardrobe's sheets (sub-project I), part of scripts/render-cats.sh (`--wardrobe`, see the list at the top of scripts/render-cats.swift). They draw through the real `CatRenderer` and
// `CatOutfitDraw`, in the role a big cat has, and are laid out like the Wardrobe panel of design/prototype/notchmeow.html, so the two can be looked at side by side. `--part` picks one:
//   sheet     all 16 outfits on all 16 coats at Ø40 (the default)       preview  one coat at five sizes, the compact notch at 1x and 3x, and two small cats, bare
//   compact   the compact notch's big cat, Ø20 in the 32 pt strip and Ø18 in the 24 pt strip, magnified 2.5x, four coats       compact1  all 16 coats at 1x
//   turned    four coats with the head turned a full yaw each way       collars  the neck outfits over the four collar styles
// `--cats` limits the coats of `sheet`, `compact`, `compact1` and `turned`. The island, the desktop and the pair of Two cats are the existing sheets with `--outfit <id>`.

extension RenderCats {
    /// The outfit the island and desktop sheets dress their big cats in (`--outfit`); "none" is bare.
    @MainActor static var sheetOutfit = "none"

    /// One cat, in the big-cat role, wearing `id`, at rest or with the head turned; `strip` puts it in the compact notch (the cat's ears and the outfit share the strip's room).
    @MainActor static func dressedCat(_ cg: CGContext, _ coat: String, _ id: String?, cx: Double, cy: Double, D: Double, role: String = "big", yaw: Double = 0, pitch: Double = 0, ceiling: Double? = nil, collar: CatCollarPaint? = nil, dpr: Double = 2) {
        var pose = CatPose()
        pose.yaw = yaw; pose.pitch = pitch
        var o = CatDrawOptions(tint: false, badge: false)
        o.earCeiling = ceiling
        o.collar = collar
        if let id, let paint = CatOutfitDraw.big(id, dpr: dpr) { o.outfit = CatOutfitPaint(id: paint.id, role: role, dpr: dpr) }
        CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(coat), pose: pose), cx: cx, cy: cy, D: D, o)
    }

    /// Column heads: a long name breaks at its spaces and hyphens so it fits its column.
    @MainActor private static func heads(_ cg: CGContext, _ ids: [String], left: Double, cw: Double) {
        for (i, id) in ids.enumerated() {
            // "Round glasses" is shortened and a hyphenated word breaks after its hyphen, so the long names fit their column.
            let name = (Wardrobe.names[id] ?? id).replacingOccurrences(of: "Round glasses", with: "Round glass.").replacingOccurrences(of: "-", with: "- ")
            let words = name.split(separator: " ").map(String.init)
            for (j, w) in words.enumerated() { CatDraw.text(cg, w, x: left + Double(i) * cw + cw / 2, y: 12 + Double(j) * 11, size: 10, bold: true, color: CatDraw.white(0.93)) }
        }
    }

    @MainActor static func wardrobeSheet(_ a: Args) -> Sheet {
        let ids = Wardrobe.drawn
        switch a.part {
        case "compact": return wardrobeCompact(a, cats: a.cats.count == CatPresets.ids.count ? ["momo", "shrimpy", "latte", "midnight"] : a.cats, magnify: 2.5)
        case "compact1": return wardrobeCompact(a, cats: a.cats, magnify: 1)
        case "turned": return wardrobeTurned(a)
        case "collars": return wardrobeCollars(a)
        case "preview": return wardrobePreview(a)
        default:
            let cw = 66.0, rh = 64.0, lw = 78.0, hh = 34.0
            let sheet = Sheet(width: lw + Double(ids.count) * cw, height: hh + Double(a.cats.count) * rh, scale: a.scale)
            let cg = sheet.cg
            cg.fill(CatDraw.roundRect(0, 0, sheet.width, sheet.height, 0), CatDraw.rgb([11, 12, 14]))
            heads(cg, ids, left: lw, cw: cw)
            for (j, coat) in a.cats.enumerated() {
                CatDraw.text(cg, coat, x: 8, y: hh + Double(j) * rh + rh / 2 + 4, size: 11, bold: false, color: CatDraw.rgb([154, 156, 163]), anchor: .left)
                for (i, id) in ids.enumerated() { dressedCat(cg, coat, id, cx: lw + Double(i) * cw + cw / 2, cy: hh + Double(j) * rh + rh / 2 + 4, D: 40, dpr: a.scale) }
            }
            return sheet
        }
    }

    /// The compact notch's big cat: Ø20 in the 32 pt strip, Ø18 in the 24 pt strip of a screen without a notch, magnified `magnify` times (the floors stay the real device's).
    @MainActor static func wardrobeCompact(_ a: Args, cats: [String], magnify k: Double) -> Sheet {
        let ids = Wardrobe.drawn, cw = 42.0, lw = 64.0, hh = 30.0, gap = 3.0, rows: [(h: Double, d: Double)] = [(32, 20), (24, 18)]
        let rowH = rows.reduce(0) { $0 + $1.h + gap }
        let sheet = Sheet(width: lw + Double(ids.count) * cw * k, height: hh + Double(cats.count) * rowH * k, scale: a.scale)
        let cg = sheet.cg
        cg.fill(CatDraw.roundRect(0, 0, sheet.width, sheet.height, 0), CatDraw.rgb([22, 23, 26]))
        heads(cg, ids, left: lw, cw: cw * k)
        for (j, coat) in cats.enumerated() {
            var y = hh + Double(j) * rowH * k
            for r in k == 1 ? [rows[0]] : rows {
                CatDraw.text(cg, "\(coat) Ø\(Int(r.d))", x: 4, y: y + r.h * k / 2 + 3, size: 10, bold: false, color: CatDraw.rgb([154, 156, 163]), anchor: .left)
                cg.saveGState()
                cg.translateBy(x: lw, y: y)
                cg.scaleBy(x: k, y: k)
                for (i, id) in ids.enumerated() {
                    let x = Double(i) * cw
                    cg.fill(CatDraw.roundRect(x + 1, 0, cw - 2, r.h, 0), CatDraw.black(1))
                    cg.fill(CatDraw.roundRect(x + 1, 0, cw - 2, 1 / a.scale, 0), CatDraw.rgb([58, 60, 66]))
                    cg.saveGState()
                    cg.clip(to: CGRect(x: x + 1, y: 0, width: cw - 2, height: r.h))
                    dressedCat(cg, coat, id, cx: x + cw / 2, cy: r.h / 2, D: r.d, ceiling: 0, dpr: a.scale)
                    cg.restoreGState()
                }
                cg.restoreGState()
                y += (r.h + gap) * k
            }
        }
        return sheet
    }

    /// Four coats with the head turned a full yaw each way: parts on the face flatten with it, hats and the bow slide with the head.
    @MainActor static func wardrobeTurned(_ a: Args) -> Sheet {
        let cats = a.cats.count == CatPresets.ids.count ? ["momo", "shrimpy", "button", "midnight"] : a.cats
        let ids = Wardrobe.drawn, turns: [Double] = [-0.6, 0.6], cw = 66.0, rh = 64.0, lw = 96.0, hh = 34.0
        let sheet = Sheet(width: lw + Double(ids.count) * cw, height: hh + Double(cats.count * turns.count) * rh, scale: a.scale)
        let cg = sheet.cg
        cg.fill(CatDraw.roundRect(0, 0, sheet.width, sheet.height, 0), CatDraw.rgb([11, 12, 14]))
        heads(cg, ids, left: lw, cw: cw)
        for (j, coat) in cats.enumerated() {
            for (t, yaw) in turns.enumerated() {
                let y = hh + Double(j * 2 + t) * rh + rh / 2 + 4
                CatDraw.text(cg, "\(coat) \(yaw < 0 ? "left" : "right")", x: 8, y: y + 4, size: 11, bold: false, color: CatDraw.rgb([154, 156, 163]), anchor: .left)
                for (i, id) in ids.enumerated() { dressedCat(cg, coat, id, cx: lw + Double(i) * cw + cw / 2, cy: y, D: 40, yaw: yaw, pitch: 0.15, dpr: a.scale) }
            }
        }
        return sheet
    }

    /// The bell, bandana and scarf over the four collar styles, on a light and a dark coat: the collar is drawn first, the outfit over it, never the other way.
    @MainActor static func wardrobeCollars(_ a: Args) -> Sheet {
        let styles = ["off", "tag", "band", "kerchief"], cols = [("momo", "bell"), ("momo", "bandana"), ("momo", "scarf"), ("ginger", "bell"), ("ginger", "bandana"), ("ginger", "scarf")]
        let cw = 124.0, rh = 116.0, lw = 70.0, hh = 22.0
        let sheet = Sheet(width: lw + Double(cols.count) * cw, height: hh + Double(styles.count) * rh, scale: a.scale)
        let cg = sheet.cg
        cg.fill(CatDraw.roundRect(0, 0, sheet.width, sheet.height, 0), CatDraw.rgb([11, 12, 14]))
        for (i, c) in cols.enumerated() { CatDraw.text(cg, "\(c.0) · \(c.1)", x: lw + Double(i) * cw + cw / 2, y: 14, size: 11, bold: true, color: CatDraw.white(0.93)) }
        for (j, style) in styles.enumerated() {
            CatDraw.text(cg, "collar: \(style)", x: 6, y: hh + Double(j) * rh + rh / 2 + 4, size: 11, bold: false, color: CatDraw.rgb([154, 156, 163]), anchor: .left)
            for (i, c) in cols.enumerated() {
                let paint = style == "off" ? nil : CatCollarPaint(style: style, color: agentColors[0].hex, dpr: a.scale)
                dressedCat(cg, c.0, c.1, cx: lw + Double(i) * cw + cw / 2, cy: hh + Double(j) * rh + rh / 2, D: 78, collar: paint, dpr: a.scale)
            }
        }
        return sheet
    }

    /// One coat (the first of `--cats`, else Momo) wearing the outfit of `--outfit` (else the Santa hat) at five sizes, the compact notch at 1x and 3x, and two small cats, which stay bare.
    @MainActor static func wardrobePreview(_ a: Args) -> Sheet {
        let coat = a.cats.count == CatPresets.ids.count ? "momo" : a.cats[0], id = a.outfit == "none" ? "santahat" : a.outfit, top = 46.0
        let sheet = Sheet(width: 820, height: 270 + top, scale: a.scale)
        let cg = sheet.cg
        cg.fill(CatDraw.roundRect(0, 0, 820, 270 + top, 0), CatDraw.rgb([11, 12, 14]))
        cg.translateBy(x: 0, y: top)
        let label = CatDraw.rgb([154, 156, 163])
        dressedCat(cg, coat, id, cx: 130, cy: 150, D: 170, dpr: a.scale)
        CatDraw.text(cg, "\(coat), \(Wardrobe.name(id))", x: 130, y: 262, size: 11, bold: false, color: label)
        for (d, text, x) in [(64.0, "Ø64", 270.0), (48, "Ø48", 360), (28, "Ø28", 430)] {
            dressedCat(cg, coat, id, cx: x, cy: 150, D: d, dpr: a.scale)
            CatDraw.text(cg, text, x: x, y: 262, size: 11, bold: false, color: label)
        }
        cg.fill(CatDraw.roundRect(480, 98, 60, 32, 0), CatDraw.black(1))
        dressedCat(cg, coat, id, cx: 510, cy: 114, D: 20, ceiling: 98, dpr: a.scale)
        CatDraw.text(cg, "Ø20 notch", x: 510, y: 262, size: 11, bold: false, color: label)
        cg.saveGState()
        cg.translateBy(x: 560, y: 50)
        cg.scaleBy(x: 3, y: 3)
        cg.fill(CatDraw.roundRect(0, 0, 60, 32, 0), CatDraw.black(1))
        dressedCat(cg, coat, id, cx: 30, cy: 16, D: 20, ceiling: 0, dpr: a.scale)
        cg.restoreGState()
        CatDraw.text(cg, "Ø20 × 3", x: 650, y: 262, size: 11, bold: false, color: label)
        dressedCat(cg, coat, id, cx: 740, cy: 100, D: 20, role: "small", dpr: a.scale)
        dressedCat(cg, coat, id, cx: 780, cy: 100, D: 12, role: "small", dpr: a.scale)
        CatDraw.text(cg, "small cats: bare", x: 760, y: 128, size: 11, bold: false, color: label)
        return sheet
    }
}
