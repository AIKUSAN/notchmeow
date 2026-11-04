import CoreGraphics
import Foundation

// The compact island stepping aside for the pointer on either wing, drawn without the app (part of scripts/render-cats.sh: `--wing`). Four strips on a mock menu bar with other apps' icons on both
// sides of the notch: the island as it rests (its cats and grid cover the first icons), a frame mid-swoosh (the black narrowing, the cats fading), the swooshed-in state (the island is the notch's own width,
// the icons show, and both wings are dashed: the parts that count), and a pointer on the left wing. The island is `drawCompact`, the app's own layout numbers; the dashed parts are `IslandWing.wings`,
// the rule the poll uses; the widths are `IslandWing.width`, a linear stand-in for the app's spring.

extension RenderCats {

    /// A menu bar `width` by 32 pt at (x, y) with an icon at each of `icons` (offsets from x), as other apps' status items would sit beside the notch.
    @MainActor static func mockMenuBar(_ cg: CGContext, x: Double, y: Double, width: Double, icons: [Double]) {
        cg.fill(CatDraw.roundRect(x, y, width, 32, 0), CatDraw.rgb([76, 78, 86]))
        for dx in icons {
            cg.fill(CatDraw.roundRect(x + dx, y + 9, 14, 14, 4), CatDraw.white(0.72))
            cg.fill(CatDraw.roundRect(x + dx + 4, y + 13, 6, 6, 2), CatDraw.rgb([76, 78, 86]))
        }
    }

    /// A pointer arrow with its tip at (x, y).
    @MainActor static func mockPointer(_ cg: CGContext, x: Double, y: Double) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + 16)); p.addLine(to: CGPoint(x: x + 4.5, y: y + 12))
        p.addLine(to: CGPoint(x: x + 8, y: y + 19)); p.addLine(to: CGPoint(x: x + 10.5, y: y + 18)); p.addLine(to: CGPoint(x: x + 7, y: y + 11)); p.addLine(to: CGPoint(x: x + 12, y: y + 11))
        p.closeSubpath()
        cg.addPath(p); cg.setFillColor(CatDraw.white(1)); cg.setStrokeColor(CatDraw.black(1)); cg.setLineWidth(1); cg.drawPath(using: .fillStroke)
    }

    @MainActor static func wingSheet(_ a: Args) -> Sheet {
        let rowH = 78.0, left = 150.0, W = 345.0, H = 32.0, barW = W + 150, pad = 60.0
        let rows: [(String, Double, Bool, Bool)] = [("At rest", 0, false, false), ("Mid-swoosh", 0.5, false, true), ("Swooshed in", 1, true, true), ("Pointer, left wing", 1, true, true)]
        let sheet = Sheet(width: left + barW + 16, height: rowH * Double(rows.count) + 8, scale: a.scale)
        let cg = sheet.cg
        let cast = CatDisplaySample.cast(CatDisplaySettings(mode: a.display, pair: CatDisplaySettings.defaultPair, agentCats: [:]), main: "shrimpy")
        let notch = W - 160   // the mock's notch (the lighter middle of the strip), as wide as drawCompact draws it
        for (i, row) in rows.enumerated() {
            let top = Double(i) * rowH + 8, oy = top + 28
            let (title, swoosh, dashed, pointer) = row
            CatDraw.text(cg, title, x: 14, y: oy + 20, size: 12, bold: true, color: CatDraw.white(0.9), anchor: .left)
            // icons under the left wing (3) and under the right wing (4), as a crowded menu bar has them
            mockMenuBar(cg, x: left, y: oy, width: barW, icons: [pad + 6, pad + 26, pad + 46] + [pad + W - 76, pad + W - 56, pad + W - 36, pad + W - 16])
            drawCompact(cg, cast, ox: left + pad, oy: oy, swoosh: swoosh)
            if dashed {
                let wings = IslandWing.wings(island: CGRect(x: left + pad, y: oy, width: W, height: H), notchWidth: notch, slop: 0)
                cg.saveGState()
                cg.setStrokeColor(CatDraw.white(0.9)); cg.setLineWidth(1); cg.setLineDash(phase: 0, lengths: [4, 3])
                cg.stroke(wings.left); cg.stroke(wings.right)
                cg.restoreGState()
                if pointer { mockPointer(cg, x: (i == 3 ? wings.left : wings.right).midX - 2, y: wings.left.midY - 4) }
            }
        }
        return sheet
    }
}
