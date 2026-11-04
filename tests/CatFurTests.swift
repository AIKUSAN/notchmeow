import CoreGraphics
import Foundation

@main
enum CatFurTests {
    typealias G = CatGeometry
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 }

    @MainActor static func main() {
        // The strand counts and the first strands below come from running the prototype's `furStrands` (design/prototype/notchmeow.html) in Node on
        // cat-core.js's presets, with a winding test in place of the canvas's isPointInPath: the same seeds (13 for the head, 7 for the ruff).
        let counts: [String: (head: Int, ruff: Int)] = [
            "shrimpy": (254, 300), "momo": (434, 0), "ginger": (251, 0), "midnight": (251, 0), "latte": (248, 0), "patches": (251, 0), "blue": (259, 0), "snow": (251, 300),
            "oreo": (432, 0), "mocha": (251, 0), "silver": (251, 0), "cloud": (252, 300), "leo": (251, 0), "button": (257, 0), "puff": (257, 300), "noodle": (249, 0),
        ]

        CT.section("the strands are the prototype's: same seeds, same counts, same first strands")
        var diffs: [String] = []
        for id in CatPresets.ids {
            let f = CatFur.strands(for: CatPresets.byID(id)), want = counts[id]!
            if f.head.count != want.head || f.ruff.count != want.ruff { diffs.append("\(id): \(f.head.count) head and \(f.ruff.count) ruff, not \(want.head) and \(want.ruff)") }
        }
        CT.checkRows("the head and ruff strand counts of the 16 coats", diffs)
        let s = CatFur.strands(for: CatPresets.byID("shrimpy")), h = s.head[0], r = s.ruff[0]
        CT.checkTrue("Shrimpy's first head strand", close(h.x, -0.3709192420169711) && close(h.y, 0.38896529177203776) && close(h.x2, -0.3897367613151183) && close(h.y2, 0.4340643851551145) && h.color == "rgba(214,190,150,.32)")
        CT.checkTrue("Shrimpy's first ruff strand", close(r.x, 0.35669339683776213) && close(r.y, -0.4974516900928963) && close(r.ux, 0.3009259855363654) && close(r.uy, -0.9536474984127874) && close(r.L, 0.07767893617972732) && r.color == "rgba(214,192,156,.45)")
        let m = CatFur.strands(for: CatPresets.byID("momo"))
        CT.checkTrue("Momo's first head strand", close(m.head[0].x, -0.35812892332673074) && close(m.head[0].y2, 0.4085957288856934) && m.head[0].color == "rgba(255,255,255,.5)")
        CT.check("160 of Momo's strands lie on her white map and use the white colours", m.head.filter { $0.color == "rgba(196,190,184,.55)" || $0.color == "rgba(255,255,255,.5)" }.count, 160)

        CT.section("the strands stay on the head, away from the eyes and the nose, and are built once")
        for id in CatPresets.ids {
            let p = CatPresets.byID(id), f = CatFur.strands(for: p)
            let inside = f.head.allSatisfy { pow($0.x / p.rx, 2) + pow($0.y / p.ry, 2) <= 1 + 1e-12 }
            let nz = (x: 0.0, y: -sin(p.nosePh) * p.ry)
            let clear = f.head.allSatisfy { hypot($0.x - nz.x, $0.y - nz.y - 0.1) >= 0.32 - 1e-12 }
            if !inside || !clear { diffs.append(id) }
        }
        CT.checkRows("no strand outside the head or on the nose, in any coat", diffs)
        CT.checkTrue("the same coat gives the same strands twice", CatFur.strands(for: CatPresets.byID("shrimpy")).head.count == s.head.count)
        CT.checkTrue("a kitten has strands of its own", CatFur.strands(for: CatPresets.kitten(of: CatPresets.byID("shrimpy"))).head[0].x != h.x)

        CT.section("when fur is drawn: a full-detail cat from a head radius of 30 px, never a hairless one")
        CT.checkTrue("Shrimpy at Ø66", CatFur.shows(CatPresets.byID("shrimpy"), R: 33, full: true))
        CT.checkTrue("not below R 30", !CatFur.shows(CatPresets.byID("shrimpy"), R: 29.9, full: true))
        CT.checkTrue("not at the compact detail", !CatFur.shows(CatPresets.byID("shrimpy"), R: 40, full: false))
        CT.checkTrue("not on Noodle, who has no fur", !CatFur.shows(CatPresets.byID("noodle"), R: 40, full: true))
        CT.finish()
    }
}
