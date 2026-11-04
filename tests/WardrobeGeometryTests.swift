import Foundation

@main
enum WardrobeGeometryTests {
    typealias O = CatOutfit
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func num(_ x: Any?) -> Double? { (x as? NSNumber).map(\.doubleValue) }

    static var rest: CatPose { CatPose() }
    static var turned: CatPose { var s = CatPose(); s.yaw = 0.6; s.pitch = 0.15; return s }
    /// The options a renderer would pass: the notch's strips give the compact cat its room above the crown (a 32 pt strip for the Ø20 cat, a 24 pt strip for the Ø18 one).
    static func opts(_ p: CatPreset, _ s: CatPose, _ D: Double, collar: String = "off", strips: [String: Double]) -> O.Options {
        var o = O.Options(dpr: 2, collar: collar)
        if let strip = strips["\(Int(D))"] { o.room = O.room(topY: O.anchors(p, s, D: D, o).top.y, headY: strip / 2, ceiling: 0) }
        return o
    }

    /// The highest and lowest point of a list of shapes in a strip, stroke widths included.
    static func extent(_ shapes: [O.Shape], headY: Double) -> (hi: Double, lo: Double) {
        var hi = Double.infinity, lo = -Double.infinity
        for sh in shapes {
            let w = (sh.stroke != nil ? sh.sw : 0) / 2
            if sh.k == .ellipse { let r = hypot(sh.rx * sin(sh.rot), sh.ry * cos(sh.rot)); hi = min(hi, headY + sh.y - r - w); lo = max(lo, headY + sh.y + r + w) }
            else { for q in sh.pts { hi = min(hi, headY + q.y - w); lo = max(lo, headY + q.y + w) } }
        }
        return (hi, lo)
    }

    @MainActor static func main() {
        let fx = CT.fixture("wardrobe-cases.json")
        let strips = (fx["strips"] as! [String: NSNumber]).mapValues(\.doubleValue)
        func geo(_ id: String, _ cat: String, _ D: Double, _ pose: CatPose = rest, collar: String = "off") -> [O.Shape] {
            let p = CatPresets.byID(cat)
            return O.geometry(id, p, pose, D: D, opts(p, pose, D, collar: collar, strips: strips))
        }

        CT.section("the frozen values: the slots and the floors")
        CT.check("the three slots", O.slots, fx["slots"] as! [String])
        let min = fx["min"] as! [String: NSNumber]
        CT.check("the floors, in device pixels", [O.Min.height, O.Min.line, O.Min.rim, O.Min.ball, O.Min.span], ["height", "line", "rim", "ball", "span"].map { min[$0]!.doubleValue })

        CT.section("outfitEdge: all 16 coats")
        let edges = fx["edge"] as! [String: String]
        CT.check("light on a dark head, dark on a light one", Dictionary(uniqueKeysWithValues: CatPresets.ids.map { ($0, O.edge(CatPresets.byID($0))) }), edges)

        CT.section("outfitRoom: \(rows(fx["rooms"]).count) cases")
        var diffs: [String] = []
        for c in rows(fx["rooms"]) {
            let got = O.room(topY: num(c["top"])!, headY: num(c["headY"]), ceiling: num(c["ceiling"])), want = num(c["out"])
            if (got == nil) != (want == nil) || (got != nil && abs(got! - want!) > CT.tolerance) { diffs.append("headY \(String(describing: c["headY"])) ceiling \(String(describing: c["ceiling"])): \(String(describing: got))") }
        }
        CT.checkRows("the distance to the strip less the ear fit's margin, never negative, none without a number", diffs)

        CT.section("outfitAnchors: \((fx["anchors"] as! [String: Any]).count) cases")
        diffs = []
        for (key, want) in (fx["anchors"] as! [String: Any]).sorted(by: { $0.key < $1.key }) {
            let part = key.split(separator: "/").map(String.init), p = CatPresets.byID(part[0]), D = Double(part[1])!
            let got = O.anchors(p, part[2] == "rest" ? rest : turned, D: D, O.Options(dpr: 2)).json
            let d = CT.diffs(got, want)
            if !d.isEmpty { diffs.append("\(key): \(d.first!)") }
        }
        CT.checkRows("four coats at Ø20, Ø28, Ø48 and Ø64, at rest and with the head turned", diffs)

        CT.section("outfitGeometry: \((fx["geometry"] as! [String: Any]).count) pinned cases")
        diffs = []
        for (key, byOutfit) in (fx["geometry"] as! [String: Any]).sorted(by: { $0.key < $1.key }) {
            let part = key.split(separator: "/").map(String.init), D = Double(part[1])!
            for (id, want) in (byOutfit as! [String: Any]).sorted(by: { $0.key < $1.key }) {
                let d = CT.diffs(geo(id, part[0], D, part[2] == "rest" ? rest : turned).map(\.json), want)
                if !d.isEmpty { diffs.append("\(key) \(id): \(d.first!)") }
            }
        }
        CT.checkRows("every shape of every outfit: kind, slot, roles, widths, alpha, fine flag and points", diffs)

        CT.section("outfitDigest: \((fx["digests"] as! [String: Any]).count) pairs (16 outfits on 16 coats at Ø18, Ø20, Ø48 and Ø64)")
        diffs = []
        for (key, want) in (fx["digests"] as! [String: Any]).sorted(by: { $0.key < $1.key }) {
            let part = key.split(separator: "/").map(String.init)
            let d = CT.diffs(O.digest(geo(part[1], part[0], Double(part[2])!)), want)
            if !d.isEmpty { diffs.append("\(key): \(d.first!)") }
        }
        CT.checkRows("any drift in any pair fails", diffs)
        CT.check("nothing digests to zeros", CT.diffs(O.digest([]), ["n": 0, "pts": 0, "bbox": [0, 0, 0, 0], "mx": 0, "my": 0]), [])

        CT.section("the collar: the bell, bandana and scarf over each of the four styles")
        diffs = []
        let momo = CatPresets.byID("momo")
        for (key, want) in (fx["collars"] as! [String: Any]).sorted(by: { $0.key < $1.key }) {
            let part = key.split(separator: "/").map(String.init), style = part[1], w = want as! [String: Any]
            let shapes = O.geometry(part[0], momo, rest, D: 64, O.Options(dpr: 2, collar: style))
            var d = CT.diffs(shapes.map(\.json), w["shapes"]!)
            if let c = CatGeometry.collarGeometry(momo, rest, D: 64, style: style, dpr: 2) { d += CT.diffs(c.json, w["collar"]!) }
            if !d.isEmpty { diffs.append("\(key): \(d.first!)") }
        }
        CT.checkRows("the shapes, and the collar they were read from (which they never change)", diffs)

        CT.section("a stranger, and the detail cut")
        diffs = []
        for c in rows(fx["unknown"]) { if let id = c["id"] as? String, !geo(id, "momo", 64).isEmpty { diffs.append(id) } }
        CT.checkRows("none, auto and a made-up name have no shapes", diffs)
        diffs = []
        for c in rows(fx["fine"]) {
            let id = c["id"] as! String
            if geo(id, "momo", 27).count != (c["at27"] as! NSNumber).intValue || geo(id, "momo", 28).count != (c["at28"] as! NSNumber).intValue { diffs.append(id) }
        }
        CT.checkRows("a fine shape (a glint, a star, a rib) is left out below Ø28", diffs)
        let sw = fx["shrimpSwitch"] as! [String: Any]
        diffs = []
        for r in rows(sw["rows"]) {
            let D = num(r["D"])!, got = geo("shrimpclip", "momo", D).map { [$0.k.rawValue, $0.slot, $0.fill ?? "", $0.stroke ?? "", $0.fine ? "fine" : ""].joined(separator: "|") }
            let want = (r["shapes"] as! [[Any]]).map { $0.map { $0 is NSNull ? "" : ($0 as? Bool).map { $0 ? "fine" : "" } ?? ($0 as! String) }.joined(separator: "|") }
            if got != want { diffs.append("Ø\(D)") }
            if (r["full"] as! Bool) != (D >= CatGeometry.detailFullMin) { diffs.append("full at Ø\(D)") }
        }
        CT.checkRows("the shrimp clip is a simple C below Ø28 and the detailed one from Ø28", diffs)
        diffs = []
        for r in rows(fx["lensRims"]) {
            let lenses = geo("sunglasses", r["cat"] as! String, 64).filter { $0.k == .ellipse && $0.fill == "lens" }.map { ["stroke": $0.stroke as Any, "sw": $0.sw] as [String: Any] }
            let d = CT.diffs(lenses, r["lenses"]!)
            if !d.isEmpty { diffs.append("\(r["cat"] as! String): \(d.first!)") }
        }
        CT.checkRows("a dark head's lenses get the thin light edge, a light head's keep the frame", diffs)

        CT.section("the compact notch: every outfit on every coat at Ø20 and Ø18")
        diffs = []
        let dpr = 2.0
        for (H, D) in [(32.0, 20.0), (24.0, 18.0)] {
            for cat in CatPresets.ids {
                let p = CatPresets.byID(cat), A = O.anchors(p, rest, D: D, O.Options(dpr: dpr)), room = O.room(topY: A.top.y, headY: H / 2, ceiling: 0)!
                if room < O.Min.height / dpr - 1e-9 { diffs.append("\(cat) Ø\(Int(D)): the strip leaves \(room) pt") }
                for id in Wardrobe.drawn {
                    let shapes = geo(id, cat, D), at = "\(id) on \(cat) Ø\(Int(D))", ext = extent(shapes, headY: H / 2)
                    if shapes.isEmpty { diffs.append("\(at): nothing drawn") }
                    if ext.hi < -1e-9 { diffs.append("\(at): above the strip by \(-ext.hi)") }
                    if ext.lo > H + 1e-9 { diffs.append("\(at): below the strip by \(ext.lo - H)") }
                    for sh in shapes {
                        if sh.stroke != nil && sh.sw > 0 && sh.sw < O.Min.line / dpr - 1e-9 { diffs.append("\(at): a stroke under the line floor") }
                        if sh.k == .ellipse && !sh.fine && Swift.min(sh.rx, sh.ry) < 0.5 * O.Min.ball / dpr - 1e-9 { diffs.append("\(at): an ellipse smaller than half a ball") }
                    }
                    let xs = shapes.flatMap { $0.k == .ellipse ? [$0.x - $0.rx, $0.x + $0.rx] : $0.pts.map(\.x) }, ys = shapes.flatMap { $0.k == .ellipse ? [$0.y - $0.ry, $0.y + $0.ry] : $0.pts.map(\.y) }
                    if let xa = xs.min(), let xb = xs.max(), let ya = ys.min(), let yb = ys.max(), Swift.max(xb - xa, yb - ya) < O.Min.span / dpr { diffs.append("\(at): less than a span across") }
                }
            }
        }
        CT.checkRows("inside the strip top and bottom, above every floor, at least a span across (256 pairs at each size)", diffs)
        let p = CatPresets.byID("momo")
        func rise(_ room: Double?) -> Double { -(O.geometry("partyhat", p, rest, D: 20, O.Options(dpr: dpr, room: room)).filter { $0.k == .poly }.flatMap { $0.pts.map(\.y) }.min() ?? 0) }
        CT.checkTrue("a short room gives a shorter hat, a tall one the natural height", rise(3) < rise(100) && rise(100) > rise(3) + 1)
        CT.checkNear("no room is held at the floor, as is a room of one", rise(0), rise(1))
        CT.checkTrue("and no room still draws a hat", rise(0) != 0)
        CT.checkJSON("no room at all (nil) is no limit", got: O.geometry("partyhat", p, rest, D: 20, O.Options(dpr: dpr, room: nil)).map(\.json), want: O.geometry("partyhat", p, rest, D: 20, O.Options(dpr: dpr)).map(\.json))

        CT.section("the compact notch's strip: headY and ceiling give the room that outfitRoom computes")
        diffs = []
        for (H, D) in [(32.0, 20.0), (24.0, 18.0)] {
            for cat in ["momo", "latte", "shrimpy"] {
                let p = CatPresets.byID(cat), top = O.anchors(p, rest, D: D, O.Options(dpr: dpr)).top.y
                let byRoom = O.Options(dpr: dpr, room: O.room(topY: top, headY: H / 2, ceiling: 0)), byStrip = O.Options(dpr: dpr, headY: H / 2, ceiling: 0)
                for id in ["partyhat", "witchhat", "bunnyears", "beanie"] {
                    let d = CT.diffs(O.geometry(id, p, rest, D: D, byStrip).map(\.json), O.geometry(id, p, rest, D: D, byRoom).map(\.json))
                    if !d.isEmpty { diffs.append("\(id) on \(cat) Ø\(Int(D)): \(d.first!)") }
                }
            }
        }
        CT.checkRows("headY and ceiling give the same shapes as the room they work out, for 4 outfits on 3 coats at Ø20 and Ø18", diffs)
        let hatP = CatPresets.byID("momo")
        CT.checkTrue("the strip really limits a hat (the natural hat is taller)", !CT.diffs(O.geometry("partyhat", hatP, rest, D: 18, O.Options(dpr: dpr, headY: 12, ceiling: 0)).map(\.json),
            O.geometry("partyhat", hatP, rest, D: 18, O.Options(dpr: dpr)).map(\.json)).isEmpty)
        CT.checkJSON("a headY without a ceiling (or the reverse) is no limit", got: O.geometry("partyhat", hatP, rest, D: 18, O.Options(dpr: dpr, headY: 12)).map(\.json), want: O.geometry("partyhat", hatP, rest, D: 18, O.Options(dpr: dpr)).map(\.json))
        CT.finish()
    }
}
