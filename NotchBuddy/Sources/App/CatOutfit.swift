import Foundation

// Where an outfit sits on a head, and the shapes it is made of (sub-project I). Port of `outfitEdge`, `outfitRoom`, `outfitAnchors`, `outfitGeometry` and `outfitDigest` in
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/wardrobe-cases.json pins them. Everything is pure: the shapes are plain data in head-local px (before the tilt and
// the squash, like `collarGeometry`), turning with the face warp, with colour roles that `Theme.Outfits` resolves. `CatOutfitDraw` paints them; nothing here reads a coat list, so the
// 16 coats and any future one fit by the same maths. Foundation only (it uses `CatGeometry`).

enum CatOutfit {
    typealias G = CatGeometry

    /// The three places a shape is drawn, without touching `CatGeometry.passes`: `behind` (after the ears of the behind pass: the bunny ears), `neck` (the front pass after the collar:
    /// scarf, bandana, bell) and `top` (after `neck`, before the whiskers: hats, crown, glasses, clips, bow, flower). The whiskers, the badge and the particles stay in front of all.
    static let slots = ["behind", "neck", "top"]

    /// The smallest sizes, in DEVICE pixels (as `CollarMin` is), so an outfit still reads on the compact notch's Ø20 cat (40 device pixels wide at 2x).
    enum Min { static let height = 6.0, line = 1.0, rim = 2.0, ball = 3.0, span = 6.0 }

    /// What the callers pass besides the coat, the pose and the head width.
    struct Options: Equatable {
        /// Pixels per point (anything not above 0 counts as 2).
        var dpr = 2.0
        /// `layout`'s explicit detail: "full" or "compact"; nil: by head width.
        var detail: String?
        /// The ears' scale as the renderer drew them; nil: what the renderer uses by default (1 from Ø28, else `earScale(D)`).
        var earScale: Double?
        /// The collar's style ("tag", "band", "kerchief", "off" or anything): the bell hangs from the collar and never changes it.
        var collar = "off"
        /// The height available above the crown (`room`); nil: no limit.
        var room: Double?
        /// The compact notch's strip: the head's y and the y of the strip's top (as `CatDrawOptions.earCeiling`). When `room` is nil and both are given, the room is worked out from them
        /// (`room(topY:headY:ceiling:)`), so a renderer asks once. nil: no limit.
        var headY: Double?
        var ceiling: Double?
    }

    // MARK: Edge and room

    /// Whether a coat's head is dark enough that an outfit's thin edge must be light to show: "light" for a dark head, "dark" for a light one (the flat head colour's luminance under 100).
    static func edge(_ p: CatPreset) -> String {
        let c = G.mixHex(p.top, p.bot, G.FlatFill.headMix)
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] < 100 ? "light" : "dark"
    }

    /// The room above the crown for a hat, in px: from the crown to `ceiling` (the y of the top of the strip the cat sits in, in the same coordinates as `headY`, the head's y), less the
    /// ear fit's margin, never negative. nil when either is missing: no limit.
    static func room(topY: Double, headY: Double?, ceiling: Double?) -> Double? {
        guard let headY, let ceiling, headY.isFinite, ceiling.isFinite else { return nil }
        return max(0, headY + topY - ceiling - G.earFitMargin)
    }

    // MARK: Anchors

    struct EarAnchor { var sd: Double, bx: Double, by: Double, rot: Double, h: Double, tipX: Double, tipY: Double }
    typealias Pt = (x: Double, y: Double)

    /// Where the outfit parts attach to one cat in one pose, in head-local px: `top` the crown between the ear bases, on the head outline; `gap` the span between the two ear bases;
    /// `half` gap/2; `lean` a hat's lean with the face turn (rad); `ears` each base with its tilt and tip; `eyes` the eye frames; `chin` the lower outline from 40 to 140 degrees, left
    /// to right, with its centre front; `neck` the point the collar's tag hangs from; `edge` "light" or "dark".
    struct Anchors {
        var R: Double, rx: Double, ry: Double, D: Double, full: Bool, dpr: Double
        var top: Pt, gap: Double, half: Double, lean: Double
        var ears: [EarAnchor]
        var eyes: [G.Eye]
        var chin: (pts: [Pt], front: Pt)
        var neck: Pt
        var edge: String

        /// As the fixtures hold it.
        var json: [String: Any] {
            ["R": R, "rx": rx, "ry": ry, "D": D, "full": full, "dpr": dpr, "top": ["x": top.x, "y": top.y], "gap": gap, "half": half, "lean": lean,
             "ears": ears.map { ["sd": $0.sd, "bx": $0.bx, "by": $0.by, "rot": $0.rot, "h": $0.h, "tipX": $0.tipX, "tipY": $0.tipY] as [String: Any] },
             "eyes": eyes.map { ["sd": $0.sd, "visible": $0.visible, "x": $0.x, "y": $0.y, "fx": $0.fx, "fy": $0.fy] as [String: Any] },
             "chin": ["pts": chin.pts.map { [$0.x, $0.y] }, "front": [chin.front.x, chin.front.y]] as [String: Any],
             "neck": ["x": neck.x, "y": neck.y], "edge": edge]
        }
    }

    static func anchors(_ p: CatPreset, _ s: CatPose, D: Double, _ o: Options = Options()) -> Anchors {
        let dpr = o.dpr > 0 ? o.dpr : 2
        let ek = o.earScale ?? (D >= G.detailFullMin ? 1 : G.earScale(D))
        let L = G.layout(p, s, cx: 0, cy: 0, D: D, G.Options(full: o.detail.map { $0 == "full" }, earScale: ek))
        let R = L.R, rx = L.rx, ry = L.ry, eL = L.ears[0], eR = L.ears[1]
        let mx = (eL.bx + eR.bx) / 2, gap = abs(eR.bx - eL.bx), tx = clamp(mx / rx, -0.95, 0.95)
        let top: Pt = (mx, -ry * pow(max(0, 1 - pow(abs(tx), p.n)), 1 / p.n) + L.bend.1 * ry * (1 - tx * tx))
        let N = 90
        let ring = Array(G.supPoints(rx: rx, ry: ry, n: p.n, dy: 0, spike: p.fluff != 0 ? 0.035 : 0, count: 14, steps: N, bend: L.bend).prefix(N))
        let arc: [Pt] = Array(ring[(N * 40 / 360)...(N * 140 / 360)].reversed()).map { (x: $0.0, y: $0.1) }   // left to right, 40° to 140°
        let front: Pt = ((arc[12].x + arc[13].x) / 2, (arc[12].y + arc[13].y) / 2)
        let width = max(0.1 * R, G.CollarMin.band / dpr)
        let k = max(0.7, min(0.92, 1 - (width / 2 + 0.5 / dpr) / (p.ry * R)))
        let n = L.warp(0, p.ry * k)
        return Anchors(R: R, rx: rx, ry: ry, D: D, full: L.full, dpr: dpr, top: top, gap: gap, half: gap / 2, lean: sin(L.yf) * 0.15,
                       ears: L.ears.map { EarAnchor(sd: $0.sd, bx: $0.bx, by: $0.by, rot: $0.rot, h: $0.h, tipX: $0.bx + $0.h * sin($0.rot), tipY: $0.by - $0.h * cos($0.rot)) },
                       eyes: L.eyes, chin: (arc, front), neck: (n.0, n.1), edge: edge(p))
    }

    // MARK: Shapes

    /// One shape, in head-local px. `fill` and `stroke` are colour roles (the keys of `Theme.Outfits`, or "edge" for the coat's thin edge); `a` the alpha; `sw` the stroke width (0 with no
    /// stroke); `fine` a detail (a glint, a star, a rib) that a cat under Ø28 leaves out. A curve has no fill; an ellipse has a centre, two radii and a rotation instead of points.
    struct Shape {
        enum Kind: String { case poly, curve, ellipse }
        var k: Kind
        var slot: String
        var fill: String?
        var stroke: String?
        var sw: Double
        var a: Double
        var fine: Bool
        var pts: [Pt] = []
        var x = 0.0, y = 0.0, rx = 0.0, ry = 0.0, rot = 0.0

        var json: [String: Any] {
            var out: [String: Any] = ["k": k.rawValue, "slot": slot, "sw": sw, "a": a, "fine": fine]
            if let stroke { out["stroke"] = stroke }
            if k != .curve, let fill { out["fill"] = fill }
            if k == .ellipse { out["x"] = x; out["y"] = y; out["rx"] = rx; out["ry"] = ry; out["rot"] = rot } else { out["pts"] = pts.map { [$0.x, $0.y] } }
            return out
        }
    }

    /// A digest of a list of shapes that two implementations compare within the contract's tolerance: how many shapes and points, the box that holds them (an ellipse counts as its
    /// axis-aligned box and its centre as a point; a stroke's width is not counted) and the mean of every point's x and of every y.
    static func digest(_ shapes: [Shape]) -> [String: Any] {
        var pts = 0, sx = 0.0, sy = 0.0, x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
        func add(_ x: Double, _ y: Double) { pts += 1; sx += x; sy += y; x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) }
        for sh in shapes {
            if sh.k == .ellipse {
                add(sh.x, sh.y)
                x0 = min(x0, sh.x - sh.rx); x1 = max(x1, sh.x + sh.rx); y0 = min(y0, sh.y - sh.ry); y1 = max(y1, sh.y + sh.ry)
            } else {
                for q in sh.pts { add(q.x, q.y) }
            }
        }
        if shapes.isEmpty { return ["n": 0, "pts": 0, "bbox": [0.0, 0.0, 0.0, 0.0], "mx": 0.0, "my": 0.0] }
        return ["n": shapes.count, "pts": pts, "bbox": [x0, y0, x1, y1], "mx": sx / Double(pts), "my": sy / Double(pts)]
    }

    // MARK: Geometry

    /// The shapes of one outfit on one cat, in paint order. An ID that is not one of the 16 drawn outfits (`none`, `auto`, anything else) gives none. A hat rises from the crown by a natural
    /// height, shortened to `o.room` but never below the floor (`Min.height`); a shape marked `fine` is left out below Ø28.
    static func geometry(_ id: String, _ p: CatPreset, _ s: CatPose, D: Double, _ o: Options = Options()) -> [Shape] {
        guard Wardrobe.drawn.contains(id) else { return [] }
        let A = anchors(p, s, D: D, o)
        let R = A.R, dpr = A.dpr, top = A.top, full = A.full
        let fHeight = Min.height / dpr, fLine = Min.line / dpr, fRim = Min.rim / dpr, fBall = Min.ball / dpr, fSpan = Min.span / dpr
        let ln = max(fLine, 0.03 * R), g = A.half, ca = cos(A.lean), sa = sin(A.lean), TAU = CatMath.tau
        let room = (o.room ?? Self.room(topY: top.y, headY: o.headY, ceiling: o.ceiling)).flatMap { $0.isFinite ? $0 : nil } ?? Double.infinity
        var out: [Shape] = []

        func Q(_ x: Double, _ y: Double, _ b: Pt? = nil) -> Pt { let b = b ?? top; return (b.x + x * ca - y * sa, b.y + x * sa + y * ca) }
        func hatH(_ nat: Double) -> Double { max(fHeight, min(nat * R, room)) }
        /// How a shape is outlined: `stroke` is a colour role (default the coat's edge) or nil for none; `sw` defaults to the thin line.
        struct St { var stroke: String? = "edge"; var sw: Double?; var a = 1.0; var fine = false }
        func poly(_ slot: String, _ pts: [Pt], _ fill: String?, _ st: St = St()) {
            out.append(Shape(k: .poly, slot: slot, fill: fill, stroke: st.stroke, sw: st.stroke == nil ? 0 : (st.sw ?? ln), a: st.a, fine: st.fine, pts: pts))
        }
        func curve(_ slot: String, _ pts: [Pt], _ stroke: String, _ sw: Double, _ st: St = St()) {
            out.append(Shape(k: .curve, slot: slot, fill: nil, stroke: stroke, sw: max(sw, fLine), a: st.a, fine: st.fine, pts: pts))
        }
        func ell(_ slot: String, _ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ rot: Double, _ fill: String?, _ st: St = St()) {
            out.append(Shape(k: .ellipse, slot: slot, fill: fill, stroke: st.stroke, sw: st.stroke == nil ? 0 : (st.sw ?? ln), a: st.a, fine: st.fine, x: x, y: y, rx: rx, ry: ry, rot: rot))
        }
        func arcPts(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, _ n: Int = 10) -> [Pt] {
            (0...n).map { i in let a = a0 + (a1 - a0) * Double(i) / Double(n); return (cx + cos(a) * rx, cy + sin(a) * ry) }
        }
        func star(_ cx: Double, _ cy: Double, _ ro: Double, _ ri: Double) -> [Pt] {
            (0..<10).map { i in let r = i % 2 == 1 ? ri : ro, a = -Double.pi / 2 + Double(i) * Double.pi / 5; return (cx + cos(a) * r, cy + sin(a) * r) }
        }
        /// A stadium shape, `w` its outer half width.
        func pill(_ slot: String, _ w: Double, _ yc: Double, _ hh: Double, _ fill: String?) {
            poly(slot, (arcPts(w - hh, yc, hh, hh, -Double.pi / 2, Double.pi / 2, 6) + arcPts(hh - w, yc, hh, hh, Double.pi / 2, Double.pi * 1.5, 6)).map { Q($0.x, $0.y) }, fill)
        }
        func ear(_ sd: Double) -> EarAnchor { A.ears.first { $0.sd == sd }! }
        func ball(_ r: Double) -> Double { max(fBall, r) }
        /// A tapered leaf along a centre line: `c(t)` the centre, `w(t)` the half width, both for t from 0 to 1.
        func leaf(_ c: (Double) -> Pt, _ w: (Double) -> Double, _ n: Int = 14) -> [Pt] {
            var l: [Pt] = [], r: [Pt] = []
            for i in 0...n {
                let t = Double(i) / Double(n), a = c(t), b = c(min(1, t + 0.02)), d = c(max(0, t - 0.02)), tx = b.x - d.x, ty = b.y - d.y, len = hypot(tx, ty) == 0 ? 1 : hypot(tx, ty)
                let nx = -ty / len, ny = tx / len, ww = w(t)
                l.append((a.x + nx * ww, a.y + ny * ww)); r.append((a.x - nx * ww, a.y - ny * ww))
            }
            return l + r.reversed()
        }

        switch id {
        // Hats: they stand between the ear bases, so they are as wide as the gap and no wider.
        case "partyhat":
            let Hh = hatH(1.35), b: Pt = (top.x, top.y + 0.05 * R), w = 0.7, tx = 0.3
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            func Lf(_ t: Double) -> Pt { H(-w + (tx + w) * t, -t) }
            func Rt(_ t: Double) -> Pt { H(w + (tx - w) * t, -t) }
            let tip = H(tx, -1)
            poly("top", arcPts(0, 0, w * g, 0.1 * R, Double.pi, 0, 8).map { Q($0.x, -$0.y, b) } + [tip], "partyA")
            for (t0, t1) in [(0.16, 0.32), (0.5, 0.64)] { poly("top", [Lf(t0), Lf(t1), Rt(t1), Rt(t0)], "partyB", St(stroke: nil)) }
            poly("top", star(tip.x, tip.y - 0.04 * R, 0.2 * R, 0.09 * R), "partyStar", St(sw: ln, fine: true))
        case "santahat":
            let Hh = hatH(0.95), b: Pt = (top.x, top.y + 0.1 * R), hw = 0.82
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            poly("top", [H(-hw, 0), H(-0.74, -0.45), H(-0.4, -0.86), H(0, -1), H(0.42, -0.88), H(0.74, -0.5), H(hw, 0)], "santaRed")
            func c(_ t: Double) -> Pt { let m = 1 - t; return H(2 * m * t * (-0.5) + t * t * (-0.58), m * m * (-0.95) + 2 * m * t * (-1.02) + t * t * (-0.5)) }
            let tip = c(1)
            poly("top", leaf(c, { (0.26 - 0.18 * $0) * g }, 10), "santaRed", St(stroke: nil))
            ell("top", tip.x, tip.y, ball(0.17 * R), ball(0.17 * R), 0, "fur")
            pill("top", 0.95 * g, 0, max(fLine * 2, 0.12 * R), "fur")
        case "witchhat":
            let Hh = hatH(1.5), b: Pt = (top.x, top.y + 0.04 * R)
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            let brim = Q(0, 0, b)
            ell("top", brim.x, brim.y, 0.95 * g, max(0.12 * R, fLine * 2), A.lean, "witchHat")
            poly("top", [H(-0.52, 0), H(-0.36, -0.4), H(-0.08, -0.72), H(0.1, -0.82), H(0.62, -1), H(0.4, -0.66), H(0.34, -0.45), H(0.52, 0)], "witchHat")
            poly("top", [H(-0.5, -0.1), H(0.5, -0.1), H(0.45, -0.3), H(-0.42, -0.3)], "witchBand", St(stroke: nil))
            poly("top", [H(-0.12, -0.06), H(0.12, -0.06), H(0.12, -0.34), H(-0.12, -0.34)], "gold", St(sw: ln))
        case "bunnyears":
            let cm = !full, Hh = hatH(cm ? 1.9 : 1.45), b: Pt = (top.x, top.y + (cm ? 0.1 : 0.5) * R)
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            // Below Ø28 the ears are taller (their base sits nearer the crown) and wider, so they show above the head at Ø18 and Ø20; the open size is unchanged.
            for sd in [-1.0, 1.0] {
                let bend = sd > 0 ? 0.9 : 0, wm = max((cm ? 0.5 : 0.3) * g, fSpan / 2)
                func c(_ t: Double) -> Pt { H(sd * (0.4 + 0.22 * t) + bend * pow(max(0, t - 0.55), 2) * 1.2, -t) }
                func w(_ t: Double) -> Double { wm * pow(sin(Double.pi * (0.2 + 0.8 * t)), 0.8) }
                poly("behind", leaf(c, w), "bunnyOuter")
                poly("behind", leaf({ c(0.06 + 0.74 * $0) }, { w(0.06 + 0.74 * $0) * 0.55 }), "bunnyInner", St(stroke: nil))
            }
        case "beanie":
            let Hh = hatH(0.78), b: Pt = (top.x, top.y + 0.26 * R), hw = 0.95
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            poly("top", arcPts(0, 0, hw, 1, Double.pi, Double.pi * 2, 14).map { H($0.x, $0.y) }, "beanieBody")
            for x in [-0.5, 0, 0.5] { curve("top", [H(x * 0.9, -0.15), H(x, -0.62), H(x * 0.5, -0.92)], "beanieCuff", ln * 0.9, St(a: 0.7, fine: true)) }
            pill("top", 0.96 * g, 0, max(0.14 * R, fSpan / 2), "beanieCuff")
            let t = H(0, -1.0)
            ell("top", t.x, t.y - 0.04 * R, ball(0.17 * R), ball(0.17 * R), 0, "fur")
        case "crown":
            let Hh = hatH(0.55), b: Pt = (top.x, top.y + 0.12 * R), hw = 0.7
            func H(_ x: Double, _ y: Double) -> Pt { Q(x * g, y * Hh, b) }
            poly("top", [H(-hw, 0), H(-hw, -0.72), H(-0.4, -0.4), H(0, -1), H(0.4, -0.4), H(hw, -0.72), H(hw, 0)], "gold")
            poly("top", [H(-hw, 0), H(hw, 0), H(hw, -0.22), H(-hw, -0.22)], "goldDark", St(stroke: nil, a: 0.85))
            for (x, y, r) in [(-hw, -0.72, "gemA"), (0, -1.0, "gemB"), (hw, -0.72, "gemC")] {
                let q = H(x, y), gr = ball(0.09 * R)
                ell("top", q.x, q.y + gr, gr, gr, 0, r)
            }
        // Glasses: they follow the eye frames and flatten with the face turn.
        case "sunglasses", "roundglasses":
            let sun = id == "sunglasses", E = p.eye
            let lr = (sun ? 1.75 : 1.95) * E.w * R, lv = (sun ? 1.55 : 1.7) * max(E.h, 0.85 * E.w) * R, fr = max(fRim, sun ? 0.06 * R : 0.045 * R)
            let eyes = A.eyes.filter(\.visible)
            for e in eyes {
                let rx = max(lr * e.fx, fBall), ry = max(lv * e.fy, fBall)
                if sun {
                    // A dark head: the frame's dark would vanish, so a thin light rim (the edge role) outlines the lens.
                    ell("top", e.x, e.y, rx, ry, 0, "lens", A.edge == "light" ? St(stroke: "edge", sw: ln, a: 0.93) : St(stroke: "frame", sw: fr, a: 0.93))
                    poly("top", [(e.x - rx * 0.5, e.y - ry * 0.15), (e.x - rx * 0.12, e.y - ry * 0.62), (e.x + rx * 0.12, e.y - ry * 0.62), (e.x - rx * 0.3, e.y + ry * 0.08)], "glint", St(stroke: nil, a: 0.55, fine: true))
                } else {
                    ell("top", e.x, e.y, rx, ry, 0, "glassTint", St(stroke: "rim", sw: fr, a: 0.22))
                    ell("top", e.x, e.y, rx, ry, 0, nil, St(stroke: "rim", sw: fr))
                    curve("top", arcPts(e.x, e.y, rx * 0.72, ry * 0.72, Double.pi * 1.05, Double.pi * 1.4, 5), "glint", ln, St(a: 0.8, fine: true))
                }
            }
            if eyes.count == 2 {
                let sorted = eyes.sorted { $0.sd < $1.sd }, a = sorted[0], b = sorted[1]
                let ax = a.x + max(lr * a.fx, fBall), bx = b.x - max(lr * b.fx, fBall), my = (a.y + b.y) / 2
                curve("top", [(ax, a.y), ((ax + bx) / 2, my - (sun ? 0.06 : 0.1) * R), (bx, b.y)], sun ? "frame" : "rim", fr)
            }
            for e in eyes.sorted(by: { $0.sd < $1.sd }) {
                let ox = e.x + e.sd * max(lr * e.fx, fBall)
                curve("top", [(ox, e.y - lv * e.fy * 0.2), (ox + e.sd * 0.3 * R * e.fx, e.y - lv * e.fy * 0.05)], sun ? "frame" : "rim", fr)
            }
        // Clips, the bow and the flower: at an ear base, turning with the ear.
        case "bow":
            let e = ear(1), cx = e.bx - 0.12 * R, cy = e.by + 0.02 * R, u = max(R * 0.9, fSpan * 1.6), rot = e.rot * 0.6
            for sd in [-1.0, 1.0] { ell("top", cx + sd * 0.3 * u * cos(rot), cy + sd * 0.3 * u * sin(rot), 0.3 * u, 0.21 * u, rot + sd * 0.35, "bowRed") }
            poly("top", [(cx - 0.05 * u, cy + 0.1 * u), (cx - 0.2 * u, cy + 0.55 * u), (cx - 0.05 * u, cy + 0.45 * u)], "bowKnot", St(fine: true))
            poly("top", [(cx + 0.05 * u, cy + 0.1 * u), (cx + 0.2 * u, cy + 0.55 * u), (cx + 0.05 * u, cy + 0.45 * u)], "bowKnot", St(fine: true))
            ell("top", cx, cy, ball(0.1 * u), ball(0.1 * u), 0, "bowKnot")
        case "fishclip":
            let e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.1 * R, u = max(R, fSpan * 1.7), rot = e.rot * 0.5
            ell("top", cx, cy, 0.27 * u, 0.13 * u, rot, "fishBody")
            poly("top", [(cx + 0.25 * u * cos(rot), cy + 0.25 * u * sin(rot)), (cx + 0.45 * u, cy - 0.14 * u), (cx + 0.45 * u, cy + 0.14 * u)], "fishFin")
            ell("top", cx - 0.13 * u, cy - 0.02 * u, 0.025 * u, 0.025 * u, 0, "lens", St(stroke: nil, fine: true))
        case "flower":
            let e = ear(1), cx = e.bx - 0.22 * R, cy = e.by + 0.1 * R, u = max(R, fSpan * 1.7)
            for i in 0..<5 { let a = -Double.pi / 2 + Double(i) * TAU / 5; ell("top", cx + cos(a) * 0.15 * u, cy + sin(a) * 0.15 * u, ball(0.13 * u), ball(0.09 * u), a, "petal") }
            ell("top", cx, cy, ball(0.07 * u), ball(0.07 * u), 0, "gold", St(sw: ln))
        case "shrimpclip":
            let e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.12 * R, u = max(R, fSpan * 1.7)
            if !full {
                // Below Ø28 (the detail cut) the shrimp is simple and bold: one thick curled C, one fanned tail with three tips, both in the shrimp colour with the edge round them.
                let r = 0.3 * u, sw = max(0.2 * u, fSpan / 2), a0 = Double.pi * 0.25, a1 = Double.pi * 1.45
                let tx = cx + r * cos(a1), ty = cy + r * sin(a1), td = (x: -sin(a1), y: cos(a1)), nd = (x: cos(a1), y: sin(a1)), L = 0.55 * u, w = 0.22 * u
                func at(_ a: Double, _ b: Double) -> Pt { (tx + a * td.x + b * nd.x, ty + a * td.y + b * nd.y) }
                curve("top", arcPts(cx, cy, r, r, a0, a1, 10), "edge", sw + 2 * ln)
                curve("top", arcPts(cx, cy, r, r, a0, a1, 10), "shrimp", sw)
                poly("top", [at(0, w * 0.5), at(L * 0.9, w), at(L * 0.45, w * 0.35), at(L * 1.1, 0), at(L * 0.45, -w * 0.35), at(L * 0.9, -w), at(0, -w * 0.5)], "shrimp")
            } else {
                let r = 0.15 * u, sw = max(0.12 * u, fSpan / 2)
                // a curled, segmented body: four segments along a C, a fine dark joint between each pair
                for i in 0..<4 { let a0 = Double.pi * (0.25 + Double(i) * 0.3); curve("top", arcPts(cx, cy, r, r, a0, a0 + Double.pi * 0.3, 4), "shrimp", sw) }
                for i in 1..<4 { let a = Double.pi * (0.25 + Double(i) * 0.3); curve("top", [(cx + 0.8 * r * cos(a), cy + 0.8 * r * sin(a)), (cx + 1.25 * r * cos(a), cy + 1.25 * r * sin(a))], "shrimpDark", ln) }
                // a fanned tail: three spikes, between notches, off the end of the C
                let a1 = Double.pi * 1.45, tx = cx + r * cos(a1), ty = cy + r * sin(a1)
                poly("top", [(tx, ty), (tx + 0.2 * u, ty - 0.14 * u), (tx + 0.13 * u, ty - 0.03 * u), (tx + 0.26 * u, ty), (tx + 0.13 * u, ty + 0.03 * u), (tx + 0.2 * u, ty + 0.14 * u)], "shrimp")
                poly("top", [(tx, ty), (tx + 0.2 * u, ty - 0.12 * u), (tx + 0.12 * u, ty - 0.02 * u)], "shrimpDark", St(fine: true))
                // two small feelers from the head end of the C
                let a2 = Double.pi * 0.25, hx = cx + r * cos(a2), hy = cy + r * sin(a2)
                curve("top", [(hx, hy), (hx + 0.1 * u, hy - 0.16 * u)], "shrimpDark", ln)
                curve("top", [(hx, hy), (hx + 0.04 * u, hy - 0.2 * u)], "shrimpDark", ln)
            }
        case "blossomclip":
            let e = ear(1), cx = e.bx - 0.22 * R, cy = e.by + 0.1 * R, u = max(R, fSpan * 1.7)
            for sd in [-1.0, 1.0] { ell("top", cx + sd * 0.2 * u, cy + 0.14 * u, ball(0.13 * u), ball(0.06 * u), sd * 0.6, "leaf") }
            for i in 0..<5 { let a = -Double.pi / 2 + Double(i) * TAU / 5; ell("top", cx + cos(a) * 0.13 * u, cy + sin(a) * 0.13 * u, ball(0.11 * u), ball(0.11 * u), a, i % 2 == 1 ? "blossomDeep" : "blossom") }
            ell("top", cx, cy, ball(0.05 * u), ball(0.05 * u), 0, "gold", St(stroke: nil))
        // Neck: over the collar.
        default:
            func inw(_ q: Pt, _ d: Double) -> Pt { let l = hypot(q.x, q.y) == 0 ? 1 : hypot(q.x, q.y); return (q.x * (1 - d / l), q.y * (1 - d / l)) }
            let pts = A.chin.pts.map { inw($0, 0.12 * R) }
            if id == "scarf" {
                let wd = max(0.42 * R, fSpan)
                curve("neck", pts, "edge", wd + 2 * ln, St(a: 0.9))
                curve("neck", pts, "scarfA", wd)
                curve("neck", pts.map { inw($0, -0.1 * R) }, "scarfB", max(0.07 * R, fLine * 1.5))
                curve("neck", pts.map { inw($0, 0.1 * R) }, "scarfB", max(0.07 * R, fLine * 1.5))
                let t0 = pts[5], tw = max(0.27 * R, fSpan), tl = 0.5 * R
                poly("neck", [(t0.x - tw / 2, t0.y - 0.05 * R), (t0.x + tw / 2, t0.y - 0.05 * R), (t0.x + tw / 2 - 0.06 * R, t0.y + tl), (t0.x - tw / 2 - 0.06 * R, t0.y + tl)], "scarfA")
                poly("neck", [(t0.x - tw / 2 - 0.015 * R, t0.y + tl * 0.55), (t0.x + tw / 2 - 0.045 * R, t0.y + tl * 0.55), (t0.x + tw / 2 - 0.05 * R, t0.y + tl * 0.7), (t0.x - tw / 2 - 0.02 * R, t0.y + tl * 0.7)], "scarfB", St(stroke: nil))
            } else if id == "bandana" {
                let apex: Pt = (A.chin.front.x, (pts.map(\.y).max() ?? 0) + 0.48 * R)
                poly("neck", pts.map { inw($0, -0.06 * R) } + [apex], "bandanaRed")
                let kn = pts[2]
                poly("neck", [(kn.x - 0.12 * R, kn.y), (kn.x - 0.4 * R, kn.y + 0.3 * R), (kn.x - 0.05 * R, kn.y + 0.26 * R)], "bandanaRed")
                ell("neck", kn.x, kn.y, ball(0.1 * R), ball(0.1 * R), 0, "bandanaRed")
                for (x, y) in [(0.0, 0.34), (-0.28, 0.18), (0.28, 0.18)] { ell("neck", A.chin.front.x + x * R, A.chin.front.y + y * R, ball(0.045 * R), ball(0.045 * R), 0, "white", St(stroke: nil, fine: true)) }
            } else {
                // The bell hangs from the collar: the tag's lower edge, the middle of the band, the kerchief's apex, or its own ring at the front of the neck with the collar off.
                let C = G.collarGeometry(p, s, D: D, style: o.collar, dpr: A.dpr, detail: o.detail)
                var at: Pt = A.neck
                if let tag = C?.tag { at = (tag.x, tag.y + tag.r) } else if let band = C?.band { at = band[band.count >> 1] } else if let kerchief = C?.kerchief { at = kerchief.apex }
                let r = ball(0.2 * R)
                ell("neck", at.x, at.y - 0.1 * R, ball(0.07 * R), ball(0.07 * R), 0, nil, St(stroke: "silver", sw: max(ln * 1.4, fLine)))
                ell("neck", at.x, at.y + 0.12 * R, r, r, 0, "gold")
                curve("neck", [(at.x - r * 0.7, at.y + 0.1 * R), (at.x + r * 0.7, at.y + 0.1 * R)], "goldDark", ln, St(fine: true))
                ell("neck", at.x, at.y + 0.12 * R + r * 0.55, ball(0.04 * R), ball(0.04 * R), 0, "goldDark", St(stroke: nil, fine: true))
            }
        }
        return full ? out : out.filter { !$0.fine }
    }
}
