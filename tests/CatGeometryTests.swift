import Foundation

@main
enum CatGeometryTests {
    typealias G = CatGeometry

    static func pose(_ delta: [String: Any]) -> CatPose {
        var s = CatPose()
        for (k, v) in delta {
            guard let key = PoseKey(rawValue: k), let n = v as? NSNumber else { fatalError("unknown pose key \(k)") }
            s[key] = n.doubleValue
        }
        return s
    }
    static func preset(_ cat: String, _ kitten: Bool) -> CatPreset {
        let p = CatPresets.byID(cat)
        return kitten ? CatPresets.kitten(of: p) : p
    }
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }

    /// A layout as the fixtures hold it (the warp closure is not data).
    static func json(_ L: G.Layout) -> [String: Any] {
        let nose: [String: Any] = L.nose.visible
            ? ["visible": true, "nx": L.nose.nx, "ny": L.nose.ny, "nf": L.nose.nf, "nw": L.nose.nw, "nh": L.nose.nh, "my": L.nose.my]
            : ["visible": false]
        return [
            "R": L.R, "D": L.D, "full": L.full, "rx": L.rx, "ry": L.ry,
            "base": ["x": L.base.x, "y": L.base.y, "R": L.base.R],
            "at": ["x": L.at.x, "y": L.at.y, "R": L.at.R, "D": L.at.D],
            "head": ["x": L.head.x, "y": L.head.y],
            "yf": L.yf, "pf": L.pf, "pt": L.pt, "fa": L.fa, "steps": L.steps,
            "bend": [L.bend.0, L.bend.1],
            "ruff": ["dx": L.ruff.dx, "dy": L.ruff.dy],
            "eyes": L.eyes.map { ["sd": $0.sd, "visible": $0.visible, "x": $0.x, "y": $0.y, "fx": $0.fx, "fy": $0.fy] as [String: Any] },
            "nose": nose,
            "mouth": L.mouth.map { ["x": $0.x, "y": $0.y] as [String: Any] } ?? NSNull(),
            "ears": L.ears.map { ["sd": $0.sd, "bx": $0.bx, "by": $0.by, "rot": $0.rot, "h": $0.h, "bw": $0.bw, "tip": $0.tip, "cx": $0.cx] as [String: Any] },
            "badge": ["x": L.badge.x, "y": L.badge.y, "k": L.badge.k, "small": L.badge.small, "side": L.badge.side],
        ]
    }

    @MainActor static func main() {
        let geo = CT.fixture("geometry-cases.json"), warp = CT.fixture("warp-cases.json")

        CT.section("detail levels and the compact ear scale")
        let detail = geo["detail"] as! [String: Any]
        CT.check("the full detail starts at Ø28", G.detailFullMin, num(detail["fullMinD"]))
        for c in detail["cases"] as! [[String: Any]] {
            let D = num(c["D"])
            CT.check("Ø\(D) is \(c["detail"]!)", G.isFull(D) ? "full" : "compact", c["detail"] as! String)
        }

        CT.section("the detail levels and the flat drawing (A-0b, merged `6adf584`): `detailLevels`, `flatFill` and `flatColors` of geometry-cases.json")
        let levels = geo["detailLevels"] as! [[String: Any]]
        for c in levels {
            let D = num(c["D"]), over = c["override"] as? String, what = "Ø\(D) \(over ?? "by its width")"
            CT.checkJSON(what, got: CT.json(G.detailLevel(D, override: over)), want: c["level"]!)
            // flatFill is exactly !layout().full: the renderer needs no switch of its own, the override rows included
            let L = G.layout(CatPresets.byID("momo"), CatPose(), cx: 0, cy: 0, D: D, G.Options(full: over.map { $0 == "full" }))
            CT.check("\(what): flatFill is !layout().full", !L.full, (c["level"] as! [String: Any])["flatFill"] as! Bool)
        }
        CT.checkTrue("an override beats the width, both ways", levels.contains { ($0["override"] as? String) == "compact" && num($0["D"]) >= G.detailFullMin } && levels.contains { ($0["override"] as? String) == "full" && num($0["D"]) < G.detailFullMin })
        let crown = ["rx": G.FlatFill.crown.rx, "ry": G.FlatFill.crown.ry, "alpha": G.FlatFill.crown.alpha], point = ["rx": G.FlatFill.point.rx, "ry": G.FlatFill.point.ry, "alpha": G.FlatFill.point.alpha]
        CT.checkJSON("the numbers of the flat drawing", got: ["headMix": G.FlatFill.headMix, "earMix": G.FlatFill.earMix, "ruffMix": G.FlatFill.ruffMix, "rimGradient": G.FlatFill.rimGradient, "crown": crown, "point": point] as [String: Any], want: geo["flatFill"]!)
        let flatColors = geo["flatColors"] as! [String: Any]
        for id in CatPresets.ids { CT.checkJSON("the flat colours of \(id)", got: CT.json(G.flatFillColors(CatPresets.byID(id))), want: flatColors[id]!) }
        let ears = geo["earScale"] as! [String: Any]
        CT.checkNear("the compact ear scale", G.compactEarScale, num(ears["compactMin"]))
        for c in ears["cases"] as! [[String: Any]] { CT.checkNear("ear scale at Ø\(num(c["D"]))", G.earScale(num(c["D"])), num(c["scale"])) }

        CT.section("head and ruff outlines (Shrimpy's fluffy edge is a fixed sum of sines)")
        for o in geo["outline"] as! [[String: Any]] {
            var bend: (Double, Double)?
            if let b = o["bend"] as? [Double] { bend = (b[0], b[1]) }
            let pts = G.supPoints(rx: num(o["rx"]), ry: num(o["ry"]), n: num(o["n"]), dy: num(o["dy"]), spike: num(o["spike"]), count: num(o["count"]), steps: Int(num(o["steps"])), bend: bend)
            let idx = (o["indices"] as! [Int])
            CT.checkJSON(o["name"] as! String, got: idx.map { [pts[$0].0, pts[$0].1] }, want: o["points"]!)
        }

        CT.section("anchors: the full layout of a cat in a pose")
        for (i, c) in (geo["anchors"] as! [[String: Any]]).enumerated() {
            let cat = c["cat"] as! String, kitten = c["kitten"] as! Bool, D = num(c["D"])
            let L = G.layout(preset(cat, kitten), pose(c["pose"] as! [String: Any]), cx: num(c["cx"]), cy: num(c["cy"]), D: D,
                             G.Options(time: num(c["T"]), badgeSide: num(c["badgeSide"]), earScale: num(c["earScale"])))
            CT.checkJSON("\(i): \(cat)\(kitten ? " kitten" : "") Ø\(D)", got: json(L), want: c["layout"]!)
        }
        CT.check("the draw passes: behind, the head, then front", G.passes, geo["passes"] as! [String: [String]])

        CT.section("a missing ear.cx and a zero one both mean 0.95 (the core uses E.cx || .95)")
        var noCx = CatPresets.byID("momo"); noCx.ear.cx = nil
        var zeroCx = CatPresets.byID("momo"); zeroCx.ear.cx = 0
        for (label, p) in [("missing", noCx), ("zero", zeroCx)] { CT.checkNear("a \(label) cx is 0.95", G.earGeom(p, CatPose(), sd: 1, R: 10, yf: 0, pf: 0).cx, 0.95) }
        CT.checkNear("a real cx is kept", G.earGeom(CatPresets.byID("momo"), CatPose(), sd: 1, R: 10, yf: 0, pf: 0).cx, 0.62)

        CT.section("the face warp")
        let face = warp["face"] as! [String: Any]
        CT.checkNear("face yaw share", G.Face.yaw, num(face["yaw"])); CT.checkNear("face pitch share", G.Face.pitch, num(face["pitch"]))
        CT.checkNear("face pitch down share", G.Face.pitchDown, num(face["pitchDown"])); CT.checkNear("head lean", G.Face.lean, num(face["lean"]))
        CT.checkNear("outline bend", G.Face.bend, num(face["bend"])); CT.checkNear("muzzle depth", G.Face.muzzle, num(face["muzzle"]))
        CT.checkNear("nose depth", G.Face.nose, num(face["nose"]))
        let cursor = warp["cursor"] as! [String: Any]
        for c in cursor["cases"] as! [[String: Any]] {
            let g = G.cursorLook(dx: num(c["dx"]), dy: num(c["dy"]))
            CT.checkJSON("cursor \(num(c["dx"])), \(num(c["dy"]))", got: [g.x, g.y], want: [c["x"]!, c["y"]!])
        }
        for c in warp["angles"] as! [[String: Any]] {
            let a = G.faceAngles(pose(["yaw": c["yaw"]!, "pitch": c["pitch"]!, "lift": c["lift"]!, "roll": c["roll"]!]))
            CT.checkJSON("angles yaw \(num(c["yaw"])) pitch \(num(c["pitch"])) lift \(num(c["lift"])) roll \(num(c["roll"]))", got: [a.yf, a.pf, a.pt, a.fa], want: [c["yf"]!, c["pf"]!, c["pt"]!, c["fa"]!])
        }
        for c in warp["pupil"] as! [[String: Any]] {
            let o = G.pupilOffset(yaw: num(c["yaw"]), pitch: num(c["pitch"]), w: num(c["w"]), h: num(c["h"]))
            CT.checkJSON("pupil travel yaw \(num(c["yaw"])) pitch \(num(c["pitch"]))", got: [o.x, o.y], want: c["offset"]!)
        }
        for c in warp["warp"] as! [[String: Any]] {
            let p = CatPresets.byID(c["cat"] as? String), a = G.faceAngles(pose(["yaw": c["yaw"]!, "pitch": c["pitch"]!]))
            let W = G.makeWarp(p, yaw: a.yf, pt: a.pt, R: 1)
            let probes = c["probes"] as! [[Double]]
            CT.checkJSON("warp \(p.name) yaw \(num(c["yaw"])) pitch \(num(c["pitch"]))", got: ["yf": a.yf, "pt": a.pt, "out": probes.map { let q = W($0[0], $0[1]); return [q.0, q.1] }] as [String: Any], want: ["yf": c["yf"]!, "pt": c["pt"]!, "out": c["out"]!] as [String: Any])
        }
        for c in warp["eyes"] as! [[String: Any]] {
            let p = CatPresets.byID(c["cat"] as? String)
            let L = G.layout(p, pose(["yaw": c["yaw"]!]), cx: 0, cy: 0, D: 2 * p.rx)
            CT.checkJSON("eyes \(p.name) yaw \(num(c["yaw"]))", got: json(L)["eyes"]!, want: c["eyes"]!)
        }
        for c in warp["head"] as! [[String: Any]] {
            let p = CatPresets.byID(c["cat"] as? String)
            let L = G.layout(p, pose(["yaw": c["yaw"]!, "pitch": c["pitch"]!]), cx: 0, cy: 0, D: num(c["D"]))
            let j = json(L)
            CT.checkJSON("head \(p.name) yaw \(num(c["yaw"])) pitch \(num(c["pitch"]))", got: ["head": j["head"]!, "bend": j["bend"]!, "ruff": j["ruff"]!, "nose": j["nose"]!, "mouth": j["mouth"]!] as [String: Any],
                         want: ["head": c["head"]!, "bend": c["bend"]!, "ruff": c["ruff"]!, "nose": c["nose"]!, "mouth": c["mouth"]!] as [String: Any])
        }

        CT.section("extreme poses never produce NaN, and a head turned away hides its face")
        var finite = true, hidden = true
        for id in CatPresets.ids {
            for D in [0.0, 1, 12, 66] {
                for (yaw, pitch, roll) in [(0.0, 0.0, 0.0), (1.4, 0.0, 0.0), (-1.6, 0.0, 0.0), (3.0, 0.0, 0.0), (0.0, 2.0, 0.0), (0.0, -2.0, 0.0), (0.0, 0.0, Double.pi), (0.62, 0.5, 3.2)] {
                    var s = CatPose(); s.yaw = yaw; s.pitch = pitch; s.roll = roll; s.lift = 0.28
                    let L = G.layout(CatPresets.byID(id), s, cx: 10, cy: 10, D: D, G.Options(earScale: G.earScale(D)))
                    let nums: [Double] = [L.R, L.head.x, L.head.y, L.fa, L.badge.x, L.badge.y] + L.eyes.flatMap { [$0.x, $0.y, $0.fx, $0.fy] } + L.ears.flatMap { [$0.bx, $0.by, $0.h, $0.bw] }
                    if nums.contains(where: { !$0.isFinite }) { finite = false; print("    NaN: \(id) D\(D) yaw \(yaw) pitch \(pitch) roll \(roll)") }
                    if !L.nose.visible && L.mouth != nil { hidden = false }
                }
            }
        }
        CT.checkTrue("every number is finite for all 16 coats, head widths 0 to 66 and eight extreme poses", finite)
        CT.checkTrue("a nose turned out of sight has no mouth point", hidden)
        var away = CatPose(); away.yaw = 3.0
        let back = G.layout(CatPresets.byID("momo"), away, cx: 0, cy: 0, D: 66)
        CT.checkTrue("a head turned right round shows neither eye nor nose", back.eyes.allSatisfy { !$0.visible } && !back.nose.visible)
        CT.check("the Ø0 head has no size", G.layout(CatPresets.byID("momo"), CatPose(), cx: 0, cy: 0, D: 0).R, 0)

        CT.section("ear headroom: in the compact strip no ear tip leaves the top, a shrunk ear sits exactly on the margin, and a calm cat keeps its ears")
        let fitFixture = geo["earFit"] as! [String: Any], margin = num(fitFixture["margin"]), minimum = num(fitFixture["minimum"])
        func tops(_ L: G.Layout, _ s: CatPose) -> Double { L.ears.map { bruteTop(L, s, $0) }.min()! }
        var shrunk = 0, headroom: [String] = []
        for (strip, D) in [(32.0, 20.0), (24.0, 18.0)] {
            for (earU, earF, oy, tilt) in [(1.0, 0.0, 0.0, 0.0), (1.4, 0.0, 0.0, 0.0), (1.4, 0.0, -0.26, 0.0), (1.22, 0.0, -0.26, 0.0), (1.4, 0.0, -0.3, 0.24), (1.4, 0.0, -0.3, -0.24), (1.1, 0.45, -0.1, 0.1)] {
                var s = CatPose(); s.earU = earU; s.earF = earF; s.oy = oy; s.tilt = tilt
                for id in ["momo", "shrimpy", "noodle", "puff", "button"] {
                    let p = CatPresets.byID(id), ek = G.earScale(D)
                    let L = G.layout(p, s, cx: 40, cy: strip / 2, D: D, G.Options(earScale: ek)), f = G.earFit(L, s, ceiling: 0)
                    let after = G.layout(p, s, cx: 40, cy: strip / 2, D: D, G.Options(earScale: ek * f))
                    let at = "\(id) strip \(strip) Ø\(D) earU \(earU) earF \(earF) oy \(oy) tilt \(tilt)"
                    if f < minimum || f > 1 { headroom.append("\(at): the factor is \(f), not \(minimum) to 1") }
                    if f == 1 {
                        if tops(L, s) < margin - 1e-3 { headroom.append("\(at): an ear that was left alone pokes out at \(tops(L, s))") }
                    } else {
                        shrunk += 1
                        if f > minimum + 1e-9 {
                            if abs(tops(after, s) - margin) > 1e-3 { headroom.append("\(at): the top of the ears is at \(tops(after, s)), not on the margin \(margin)") }
                        } else if tops(after, s) <= tops(L, s) { headroom.append("\(at): held at the minimum, the tips do not come down") }
                    }
                }
            }
        }
        CT.checkRows("5 coats, 2 strips, 7 poses: no ear leaves the strip, and a shrunk ear sits on the margin", headroom)
        CT.checkTrue("the poses do need the fit (\(shrunk) cases)", shrunk > 10)
        var calm = CatPose(); calm.earU = 1
        let calmL = G.layout(CatPresets.byID("momo"), calm, cx: 40, cy: 16, D: 20, G.Options(earScale: G.earScale(20)))
        CT.checkNear("an idle cat in the notch keeps its ears", G.earFit(calmL, calm, ceiling: 0), 1)
        let high = G.layout(CatPresets.byID("momo"), calm, cx: 40, cy: 3, D: 20, G.Options(earScale: 1))
        CT.checkTrue("a cat too close to the top gets smaller ears, never smaller than 0.35", G.earFit(high, calm, ceiling: 0) < 1 && G.earFit(high, calm, ceiling: 0) >= 0.35)

        CT.section("ear headroom against the contract (A-0b, merged `6adf584`): `earFit` and `earFitCases` of geometry-cases.json")
        let contractFit = geo["earFit"] as! [String: Any]
        CT.checkNear("the margin under the ceiling", G.earFitMargin, num(contractFit["margin"]))
        CT.checkNear("the smallest factor", G.earFitMinimum, num(contractFit["minimum"]))
        var fitDiffs: [String] = []
        let fitCases = geo["earFitCases"] as! [[String: Any]]
        for (i, c) in fitCases.enumerated() {
            let s = pose(c["pose"] as! [String: Any]), p = preset(c["cat"] as! String, c["kitten"] as! Bool)
            let L = G.layout(p, s, cx: num(c["cx"]), cy: num(c["cy"]), D: num(c["D"]), G.Options(earScale: num(c["earScale"])))
            let got = G.earFit(L, s, ceiling: num(c["ceiling"]), margin: num(c["margin"]), minimum: num(c["minimum"])), want = num(c["fit"])
            if abs(got - want) > 1e-9 { fitDiffs.append("case \(i) \(p.name) Ø\(num(c["D"])): \(got) vs \(want)") }
        }
        CT.checkRows("\(fitCases.count) contract cases", fitDiffs)

        CT.section("ear fit: a head of width 0, a cat upside down and a pose that is not a number give a number in range, never NaN")
        func fitOf(_ p: CatPreset, _ s: CatPose, D: Double) -> Double {
            G.earFit(G.layout(p, s, cx: 40, cy: 16, D: D, G.Options(earScale: G.earScale(D))), s, ceiling: 0)
        }
        CT.check("a head of width 0 needs no fit", fitOf(CatPresets.byID("momo"), CatPose(), D: 0), 1)
        var weird: [CatPose] = []
        for (k, v) in [("tilt", Double.pi), ("tilt", .nan), ("sy", .infinity), ("sx", .nan), ("tilt", 20)] {
            var s = CatPose(); s[PoseKey(rawValue: k)!] = v
            if k == "tilt" && v == .pi { s.earU = 1.4 }
            if k == "tilt" && v == 20 { s.earU = 9 }
            if k == "sx" { s.oy = .nan }
            weird.append(s)
        }
        for (i, s) in weird.enumerated() {
            let f = fitOf(CatPresets.byID("noodle"), s, D: 20)
            CT.checkTrue("pose \(i): \(f) is finite and between 0.35 and 1", f.isFinite && f >= 0.35 && f <= 1)
        }
        var notANumber = CatPose(); notANumber.tilt = .nan
        CT.check("a tilt that is not a number leaves nothing to fit: 1", fitOf(CatPresets.byID("momo"), notANumber, D: 20), 1)

        CT.section("the collar (A-0b, merged `6adf584`): collar-cases.json")
        let col = CT.fixture("collar-cases.json")
        let cases = col["cases"] as! [[String: Any]], floors = col["min"] as! [String: Any]
        CT.check("the styles that are drawn, in the contract's order, then off", G.collarStyles + ["off"], col["styles"] as! [String])
        CT.check("the readability floors, in device pixels", [G.CollarMin.band, G.CollarMin.tag, G.CollarMin.kerchiefW, G.CollarMin.kerchiefDrop],
                 ["band", "tag", "kerchiefW", "kerchiefDrop"].map { num(floors[$0]) })
        CT.check("the collar is drawn in the front pass", G.collarPass, geo["collarPass"] as! String)
        var collarDiffs: [String] = []
        for c in cases {
            let p = preset(c["cat"] as! String, c["kitten"] as! Bool), s = pose(c["pose"] as! [String: Any]), D = num(c["D"]), style = c["style"] as! String
            let got: Any = G.collarGeometry(p, s, D: D, style: style, dpr: num(c["dpr"]))?.json ?? NSNull()
            let d = CT.diffs(got, c["out"] ?? NSNull())
            if !d.isEmpty { collarDiffs.append("\(c["cat"]!) \(style) Ø\(D) dpr \(c["dpr"]!) \(c["pose"]!): \(d.first!)") }
        }
        CT.checkRows("\(cases.count) cases: each style at Ø12 to Ø66, at pixel ratio 1 and 2, at rest and with the head turned", collarDiffs)
        CT.checkTrue("off, and a style nobody knows, have no collar", G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "off") == nil && G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "scarf") == nil)
        CT.checkTrue("a pixel ratio that is not above 0 counts as 2", G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "band", dpr: 0)?.width == G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "band", dpr: 2)?.width
                     && G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "band", dpr: .nan)?.width == G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "band", dpr: 2)?.width)
        // The floors: at Ø12 a band is never thinner than 3 device pixels, a tag never smaller than 6 across, a neckerchief never narrower than 7 or shallower than 5.
        var floorDiffs: [String] = []
        for id in CatPresets.ids {
            for dpr in [1.0, 2, 3] {
                let p = CatPresets.byID(id)
                if let b = G.collarGeometry(p, CatPose(), D: 12, style: "band", dpr: dpr), b.width! * dpr < G.CollarMin.band - 1e-9 { floorDiffs.append("\(id) band at dpr \(dpr): \(b.width! * dpr) px") }
                if let t = G.collarGeometry(p, CatPose(), D: 12, style: "tag", dpr: dpr), t.tag!.r * 2 * dpr < G.CollarMin.tag - 1e-9 { floorDiffs.append("\(id) tag at dpr \(dpr)") }
                if let k = G.collarGeometry(p, CatPose(), D: 12, style: "kerchief", dpr: dpr)?.kerchief {
                    let xs = k.pts.map { $0.x }, drop = k.apex.y - k.pts.map { $0.y }.max()!
                    if (xs.max()! - xs.min()!) * dpr < G.CollarMin.kerchiefW - 1e-9 || drop * dpr < G.CollarMin.kerchiefDrop - 1e-9 { floorDiffs.append("\(id) kerchief at dpr \(dpr)") }
                }
            }
        }
        CT.checkRows("all 16 coats at Ø12 and at pixel ratios 1, 2 and 3 keep the floors of the contract", floorDiffs)
        CT.finish()
    }

    /// The highest point of an ear in the world (the smallest y), found by walking the whole outline the renderer draws, not by the formula under test.
    static func bruteTop(_ L: G.Layout, _ s: CatPose, _ e: G.Ear) -> Double {
        let R = L.R, h = e.h, bw = e.bw, tip = e.tip, cx = e.cx
        let curves: [[(Double, Double)]] = [
            [(-bw, 0.25 * R), (-bw * cx, -h * 0.4), (-tip * 0.9, -h + tip * 1.3)],
            [(-tip * 0.9, -h + tip * 1.3), (0, -h - tip * 0.35), (tip * 0.9, -h + tip * 1.3)],
            [(tip * 0.9, -h + tip * 1.3), (bw * cx, -h * 0.4), (bw, 0.25 * R)],
        ]
        var best = Double.infinity
        for q in curves {
            for i in 0...400 {
                let t = Double(i) / 400, m = 1 - t
                let x = m * m * q[0].0 + 2 * m * t * q[1].0 + t * t * q[2].0, y = m * m * q[0].1 + 2 * m * t * q[1].1 + t * t * q[2].1
                let hx = e.bx + x * cos(e.rot) - y * sin(e.rot), hy = e.by + x * sin(e.rot) + y * cos(e.rot)
                best = min(best, L.head.y + sin(s.tilt) * s.sx * hx + cos(s.tilt) * s.sy * hy)
            }
        }
        return best
    }
}
