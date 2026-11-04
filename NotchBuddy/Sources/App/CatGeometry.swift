import Foundation

// Everything geometric about a cat, as numbers in and numbers out: the pose, the head outline, the face warp,
// the ears, the eyes, the nose, the mouth point and the badge. Port of the "Geometry" section of
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/geometry-cases.json and warp-cases.json pin it.
// Units are R, the head radius, unless a name says px. No drawing here: CatRenderer consumes a `CatLayout`.

// MARK: - Pose

/// The animatable properties of a cat, by name (the engine tweens them by key).
enum PoseKey: String, CaseIterable {
    case yaw, pitch, roll, tilt, open, sx, sy, oy, ox, tint, blush, es, badgeS
    case earL, earR, earU, earF, pupil, mouth, purr, lid, lift, wh, paws
    case smile, tongue, mround, mskew, wavy
}

/// The neutral pose: every animatable property at rest. The engine's pose starts here, and `layout` reads one.
struct CatPose: Equatable {
    var yaw = 0.0, pitch = 0.0, roll = 0.0, tilt = 0.0, open = 1.0, sx = 1.0, sy = 1.0, oy = 0.0, ox = 0.0
    var tint = 0.0, blush = 0.0, es = 1.0, badgeS = 0.0, earL = 0.0, earR = 0.0, earU = 1.0, earF = 0.0
    var pupil = 0.45, mouth = 0.0, purr = 0.0, lid = 0.0, lift = 0.0, wh = 0.0, paws = 0.0
    var smile = 0.0, tongue = 0.0, mround = 0.0, mskew = 0.0, wavy = 0.0

    subscript(k: PoseKey) -> Double {
        get {
            switch k {
            case .yaw: return yaw
            case .pitch: return pitch
            case .roll: return roll
            case .tilt: return tilt
            case .open: return open
            case .sx: return sx
            case .sy: return sy
            case .oy: return oy
            case .ox: return ox
            case .tint: return tint
            case .blush: return blush
            case .es: return es
            case .badgeS: return badgeS
            case .earL: return earL
            case .earR: return earR
            case .earU: return earU
            case .earF: return earF
            case .pupil: return pupil
            case .mouth: return mouth
            case .purr: return purr
            case .lid: return lid
            case .lift: return lift
            case .wh: return wh
            case .paws: return paws
            case .smile: return smile
            case .tongue: return tongue
            case .mround: return mround
            case .mskew: return mskew
            case .wavy: return wavy
            }
        }
        set {
            switch k {
            case .yaw: yaw = newValue
            case .pitch: pitch = newValue
            case .roll: roll = newValue
            case .tilt: tilt = newValue
            case .open: open = newValue
            case .sx: sx = newValue
            case .sy: sy = newValue
            case .oy: oy = newValue
            case .ox: ox = newValue
            case .tint: tint = newValue
            case .blush: blush = newValue
            case .es: es = newValue
            case .badgeS: badgeS = newValue
            case .earL: earL = newValue
            case .earR: earR = newValue
            case .earU: earU = newValue
            case .earF: earF = newValue
            case .pupil: pupil = newValue
            case .mouth: mouth = newValue
            case .purr: purr = newValue
            case .lid: lid = newValue
            case .lift: lift = newValue
            case .wh: wh = newValue
            case .paws: paws = newValue
            case .smile: smile = newValue
            case .tongue: tongue = newValue
            case .mround: mround = newValue
            case .mskew: mskew = newValue
            case .wavy: wavy = newValue
            }
        }
    }
}

// MARK: - The Apple Music dance

/// The Apple Music dance rides on a 112 BPM beat: the whole cat hops, sways and squashes to it (`CatEffects.applyDance`), and its head and ears bob
/// to it (`pose`, which the engine adds to the pose it hands the renderer). Not in the contract: the prototype has no music.
enum CatDance {
    static let bpm = 112.0

    /// How many beats have passed after `seconds`.
    static func beat(_ seconds: Double) -> Double { seconds * bpm / 60 }

    /// Where the cat is in a beat: `hop` is 0 on the beat and 1 half a beat later (how high it is), `land` is 1 on the beat and gone a moment later (how
    /// hard it lands).
    static func curves(_ seconds: Double) -> (hop: Double, land: Double) {
        let hop = abs(sin(Double.pi * beat(seconds)))
        return (hop, pow(1 - hop, 6))
    }

    /// The head-bob and the ear bounce, added to a pose: the head tips back a little on the way up and nods down on the landing, the ears stretch
    /// with the hop and flop outward as the cat lands. `level` is the engine's dancing level, 0 to 1 (it fades in over 0.3 s and out over 0.5 s); at 0
    /// the pose comes back as it was. Nothing else about the pose changes.
    static func pose(_ p: CatPose, level l: Double, seconds: Double) -> CatPose {
        guard l > 0.001 else { return p }
        let (hop, land) = curves(seconds)
        var q = p
        q.pitch += l * (0.08 * hop - 0.16 * land)
        q.earU *= 1 + l * 0.14 * hop
        q.earL += l * 0.2 * land
        q.earR += l * 0.2 * land
        return q
    }
}

// MARK: - Constants

enum CatGeometry {
    /// Head turn toward the cursor. The face is a real 3D rotation of the head ellipsoid, with the muzzle standing proud of it
    /// so it swings further than the cheeks, and the head outline leans into the turn. yaw/pitch are the share of upstream's
    /// 0.62/0.5 rad gaze the face takes; the pupils carry the rest.
    enum Face {
        static let yaw = 0.82, pitch = 0.6, pitchDown = 0.32, lean = 0.08, bend = 0.1, muzzle = 0.12, nose = 0.05
    }

    /// Head width D (px) from which the full cat is drawn; below it the compact drawing (ink eyes, no irises, stripes or whiskers).
    static let detailFullMin = 28.0
    static func isFull(_ D: Double) -> Bool { detailLevel(D).full }

    // MARK: Detail level and the flat drawing (A-0b, merged `6adf584`)

    /// What the renderer draws at head width D: `detail` ("full" or "compact"), `full`, and `flatFill`, which is on exactly when the cat is compact
    /// (below Ø28). `override` is `layout`'s explicit detail: "full" or "compact" wins over D.
    struct DetailLevel: Encodable, Equatable { var detail: String; var full: Bool; var flatFill: Bool }
    static func detailLevel(_ D: Double, override: String? = nil) -> DetailLevel {
        let full = override.flatMap { $0.isEmpty ? nil : $0 == "full" } ?? (D >= detailFullMin)
        return DetailLevel(detail: full ? "full" : "compact", full: full, flatFill: !full)
    }

    /// The flat drawing the compact detail uses (radii in R), the contract's `FLAT_FILL`. At Ø12 to Ø27 a gradient cannot be seen and costs a shading pass each,
    /// so the head is one fill, each ear one fill, the ruff one fill, there is no rim gradient, and the tabby's crown and the point's mask are one ellipse each.
    /// The point mask (0.86 R by 0.54 R) is tuned to the gradient it replaces: the same total ink.
    enum FlatFill {
        static let headMix = 0.5, earMix = 0.5, ruffMix = 0.6, rimGradient = false
        static let crown = (rx: 0.4, ry: 0.26, alpha: 0.5), point = (rx: 0.86, ry: 0.54, alpha: 0.85)
    }

    /// `a` to `b` by `t`, as [r, g, b] in 0...255, not rounded.
    static func mixHex(_ a: String, _ b: String, _ t: Double) -> [Double] {
        let y = hexRGB(b)
        return hexRGB(a).enumerated().map { lerp($0.element, y[$0.offset], t) }
    }

    /// The flat colours of a coat: the head, the two ears (left, right), the ruff (nil without one) and the point mask (nil unless the coat is `point`),
    /// [r, g, b] in 0...255, not rounded.
    struct FlatColors: Encodable, Equatable { var head: [Double]; var ears: [[Double]]; var ruff: [Double]?; var point: [Double]? }
    static func flatFillColors(_ p: CatPreset) -> FlatColors {
        func ear(_ i: Int) -> [Double] { let c = p.earCols?[i]; return mixHex(c ?? p.top, c ?? p.bot, FlatFill.earMix) }
        return FlatColors(head: mixHex(p.top, p.bot, FlatFill.headMix), ears: [ear(0), ear(1)], ruff: p.ruff.map { mixHex($0.col[1], $0.col[0], FlatFill.ruffMix) },
                          point: p.coat == "point" ? p.point.map(hexRGB) : nil)
    }

    /// The compact ears are scaled down so they keep their headroom in the compact notch: 1 from Ø28 up,
    /// easing down to `compactEarScale` at Ø20 and below. PROVISIONAL: the spec only says "ears scaled down at Ø20".
    static let compactEarScale = 0.8
    static func earScale(_ D: Double) -> Double {
        D >= detailFullMin ? 1 : lerp(compactEarScale, 1, clamp((D - 20) / (detailFullMin - 20), 0, 1))
    }

    /// Outline sample count: small heads (R under 20 px) use fewer points.
    static func outlineSteps(_ R: Double) -> Int { R < 20 ? 72 : 200 }

    /// The badge sits beside the right ear, and moves to the left in the compact notch so it never sits under the camera housing.
    static func badgeSide(compactNotch: Bool) -> Double { compactNotch ? -1 : 1 }

    /// Cursor to gaze: how far the cursor is from the cat in px, to -1…1 (tanh over 240 px across, 180 px up and down).
    static let cursorX = 240.0, cursorY = 180.0
    static func cursorLook(dx: Double, dy: Double) -> (x: Double, y: Double) {
        (tanh(dx / cursorX), -tanh(dy / cursorY))
    }

    /// Pupil travel inside the eye: up to 0.24 of the eye width across and 0.18 of its height up and down.
    static func pupilOffset(yaw: Double, pitch: Double, w: Double, h: Double) -> (x: Double, y: Double) {
        (clamp(yaw / 0.62, -1, 1) * 0.24 * w, -clamp(pitch / 0.5, -1, 1) * 0.18 * h)
    }

    /// The share of the gaze the face takes, and the roll fade: yf, pf, the warp pitch pt and the face opacity fa.
    static func faceAngles(_ s: CatPose) -> (yf: Double, pf: Double, pt: Double, fa: Double) {
        let yf = s.yaw * Face.yaw
        let pf = s.pitch * (s.pitch > 0 ? Face.pitch : Face.pitchDown)
        let pt = wrapA(pf + s.lift + s.roll)
        return (yf, pf, pt, clamp((cos(pt) - 0.05) / 0.3, 0, 1))
    }

    // MARK: Outline

    /// Superellipse outline as points, optionally with a fluffy edge (spike) on the lower half. The fluff is a fixed sum of
    /// sines, so it needs no random numbers and is identical everywhere.
    static func supPoints(rx: Double, ry: Double, n: Double, dy: Double, spike: Double, count: Double, steps: Int = 200, bend: (Double, Double)? = nil) -> [(Double, Double)] {
        let e = 2 / n
        var pts: [(Double, Double)] = []
        pts.reserveCapacity(steps + 1)
        for i in 0...steps {
            let a = Double(i) / Double(steps) * CatMath.tau, c = cos(a), s = sin(a)
            var k = 1.0
            if spike != 0 {
                let low = max(0, s + 0.55) / 1.55
                let vary = 0.55 + 0.45 * sin(a * 5.3 + 1.1) * sin(a * 2.7 + 0.4)
                k += low * spike * vary * pow(abs(cos(a * count)), 1.8)
            }
            var x = sign(c) * pow(abs(c), e) * rx * k
            var y = sign(s) * pow(abs(s), e) * ry * k + dy
            if let bend {
                let tx = x / rx, ty = y / ry
                x += bend.0 * rx * max(0, 1 - ty * ty)
                y += bend.1 * ry * max(0, 1 - tx * tx)
            }
            pts.append((x, y))
        }
        return pts
    }

    private static func sign(_ v: Double) -> Double { v > 0 ? 1 : (v < 0 ? -1 : 0) }

    // MARK: Face warp

    /// Maps a point drawn on the flat front view (units of R) onto the head ellipsoid rotated by yaw and pitch, so markings,
    /// whisker pads and the muzzle turn with the eyes. Points outside the head outline stay put. Identity at rest.
    typealias Warp = (Double, Double) -> (Double, Double)

    static func makeWarp(_ p: CatPreset, yaw: Double, pt: Double, R: Double) -> Warp {
        let a = p.rx, b = p.ry, vm = sin(p.nosePh) - 0.12
        if abs(yaw) < 1e-4 && abs(pt) < 1e-4 { return { x, y in (x * R, y * R) } }
        let cY = cos(yaw), sY = sin(yaw), cP = cos(pt), sP = sin(pt)
        return { x, y in
            let u = x / a, v = -y / b, q = 1 - u * u - v * v
            if q <= 0 { return (x * R, y * R) }
            let du = u / 0.55, dv = (v - vm) / 0.45
            let w = q.squareRoot() + Face.muzzle * exp(-(du * du + dv * dv))
            let u1 = u * cY + w * sY, w1 = w * cY - u * sY, v1 = v * cP + w1 * sP
            return (u1 * a * R, -v1 * b * R)
        }
    }

    /// Momo's white map (the tuxedo blaze, muzzle and chin), as a dense point list so the warp can bend every edge.
    static let momoWhite: [(Double, Double)] = {
        enum Cmd { case m(Double, Double), q(Double, Double, Double, Double), l(Double, Double) }
        let cmds: [Cmd] = [.m(0, -0.6), .q(-0.13, -0.4, -0.17, -0.12), .q(-0.19, 0.1, -0.26, 0.2), .q(-0.5, 0.38, -0.8, 0.36), .l(-1.3, 0.3), .l(-1.3, 1.3), .l(1.3, 1.3), .l(1.3, 0.3), .l(0.8, 0.36), .q(0.5, 0.38, 0.26, 0.2), .q(0.19, 0.1, 0.17, -0.12), .q(0.13, -0.4, 0, -0.6)]
        var out: [(Double, Double)] = [], px = 0.0, py = 0.0
        for c in cmds {
            switch c {
            case .m(let x, let y): px = x; py = y; out.append((px, py))
            case .q(let cx, let cy, let x, let y):
                for i in 1...10 {
                    let t = Double(i) / 10, m = 1 - t
                    out.append((m * m * px + 2 * m * t * cx + t * t * x, m * m * py + 2 * m * t * cy + t * t * y))
                }
                px = x; py = y
            case .l(let x, let y):
                for i in 1...8 {
                    let t = Double(i) / 8
                    out.append((px + (x - px) * t, py + (y - py) * t))
                }
                px = x; py = y
            }
        }
        return out
    }()

    // MARK: Ears

    struct Ear {
        var sd: Double, bx: Double, by: Double, rot: Double, h: Double, bw: Double, tip: Double, cx: Double
    }

    /// One ear, in head-local px before tilt and squash. `ek` is the compact ear scale (earScale), 1 when not compact.
    static func earGeom(_ p: CatPreset, _ s: CatPose, sd: Double, R: Double, yf: Double, pf: Double, ek: Double = 1) -> Ear {
        let E = p.ear, rx = p.rx * R, ry = p.ry * R, th = sd * 0.6 + yf * 0.85, f = max(0.3, cos(th))
        return Ear(sd: sd,
                   bx: sin(th) * p.earSpread * rx + sin(yf) * Face.bend * 0.54 * rx,
                   by: -0.68 * ry - sin(pf + s.lift) * 0.12 * ry,
                   rot: sd * (E.rot + (sd < 0 ? s.earL : s.earR) + 0.95 * s.earF),
                   h: E.h * R * s.earU * (1 - 0.4 * s.earF) * ek,
                   bw: E.bw * R * f * ek,
                   tip: E.tip * R * ek,
                   cx: E.cx.flatMap { $0 == 0 ? nil : $0 } ?? 0.95)   // the core uses E.cx || .95, so a zero counts as missing
    }

    // MARK: Layout

    struct Eye { var sd: Double, visible: Bool, x: Double, y: Double, fx: Double, fy: Double }
    struct Nose { var visible: Bool, nx = 0.0, ny = 0.0, nf = 0.0, nw = 0.0, nh = 0.0, my = 0.0 }
    struct Badge { var x: Double, y: Double, k: Double, small: Bool, side: Double }

    struct Options {
        /// nil: by head width (full from Ø28).
        var full: Bool?
        var time = 0.0
        /// +1 beside the right ear, -1 beside the left; anything in between while the greeting moves it across.
        var badgeSide = 1.0
        var earScale = 1.0
    }

    /// Everything geometric about one cat in one pose, in px: where the head is, the warp, the eyes, the nose and mouth, the ears,
    /// the badge. Drawing code only consumes this.
    struct Layout {
        var R: Double, D: Double, full: Bool, rx: Double, ry: Double
        var base: (x: Double, y: Double, R: Double)
        var at: (x: Double, y: Double, R: Double, D: Double)
        var head: (x: Double, y: Double)
        var yf: Double, pf: Double, pt: Double, fa: Double
        var warp: Warp
        var steps: Int
        var bend: (Double, Double)
        var ruff: (dx: Double, dy: Double)
        var eyes: [Eye]
        var nose: Nose
        var mouth: (x: Double, y: Double)?
        var ears: [Ear]
        var badge: Badge
    }

    /// `p` preset, `s` pose (the engine's), `cx`/`cy` the cat's resting centre, `D` the head width.
    static func layout(_ p: CatPreset, _ s: CatPose, cx cx0: Double, cy cy0: Double, D: Double, _ o: Options = Options()) -> Layout {
        let R = D / (2 * p.rx), full = detailLevel(D, override: o.full.map { $0 ? "full" : "compact" }).full, T = o.time, ek = o.earScale, rx = p.rx * R, ry = p.ry * R
        var cx = cx0, cy = cy0
        let base = (x: cx, y: cy, R: R)
        let purr = s.purr > 0.01 ? sin(T * CatMath.tau * 24) * 0.007 * s.purr : 0
        cx += (s.ox + purr) * R
        cy += s.oy * R
        let at = (x: cx, y: cy, R: R, D: D)
        let (yf, pf, pt, fa) = faceAngles(s)
        cx += sin(s.yaw) * Face.lean * R
        cy -= sin(s.pitch) * Face.lean * 0.8 * R
        let W = makeWarp(p, yaw: yf, pt: pt, R: R)
        let eyes = [-1.0, 1.0].map { sd -> Eye in
            let th = sd * p.eye.th + yf, cp = cos(p.eye.ph + pt)
            let (x, y) = W(sin(sd * p.eye.th) * cos(p.eye.ph) * p.rx, -sin(p.eye.ph) * p.ry)
            return Eye(sd: sd, visible: cos(th) * cp > 0.04, x: x, y: y,
                       fx: clamp(cos(th) / cos(p.eye.th), 0.55, 1.08), fy: clamp(cp / cos(p.eye.ph), 0.18, 1.08))
        }
        var nose = Nose(visible: false)
        var mouth: (x: Double, y: Double)?
        if cos(yf) * cos(p.nosePh + pt) > 0.04 {
            let (nx0, ny0) = W(0, -sin(p.nosePh) * p.ry)
            let nx = nx0 + sin(yf) * Face.nose * R, ny = ny0 - sin(pf) * Face.nose * 0.8 * R
            let nf = max(0.3, cos(yf)), nw = p.noseW * R * nf, nh = p.noseH * R, my = ny + nh / 2
            nose = Nose(visible: true, nx: nx, ny: ny, nf: nf, nw: nw, nh: nh, my: my)
            let lx = nx * s.sx, ly = (my + 0.12 * R) * s.sy, c = cos(s.tilt), sn = sin(s.tilt)
            mouth = (cx + lx * c - ly * sn, cy + lx * sn + ly * c)
        }
        let side = o.badgeSide == 0 ? 1 : o.badgeSide
        return Layout(R: R, D: D, full: full, rx: rx, ry: ry, base: base, at: at, head: (cx, cy), yf: yf, pf: pf, pt: pt, fa: fa,
                      warp: W, steps: outlineSteps(R),
                      bend: (sin(yf) * Face.bend, -sin(pf) * Face.bend * 0.7),
                      ruff: (-sin(s.yaw) * Face.lean * 1.1 * R, sin(s.pitch) * Face.lean * 0.9 * R),
                      eyes: eyes, nose: nose, mouth: mouth,
                      ears: [-1.0, 1.0].map { earGeom(p, s, sd: $0, R: R, yf: yf, pf: pf, ek: ek) },
                      badge: Badge(x: cx + side * 1.4 * R * s.sx, y: cy - 0.92 * R * s.sy, k: s.badgeS * (full ? 1 : 1.25), small: !full, side: side))
    }

    /// The factor (0.35 to 1) to multiply the ear scale by so that no ear rises above `ceiling`, a y in the same coordinates as the layout (the top edge of
    /// the strip the cat lives in, for the compact notch). 1 means the ears already fit, and so does a pose that is not a number; a cat so close to the
    /// ceiling that even the smallest ears would not fit is held at `minimum`. An ear scales about its own base, so its highest point rises in proportion to
    /// the scale and one linear solve replaces a search. The top edge of an ear is a parabola (x = 0.9 tip u, y = -h + tip (0.475 + 0.825 u²) for u in
    /// -1...1, in ear space), and the world height of an ear-space point is y0 + A x + B y, so the highest point is where u = -0.9 A / (1.65 B), held to
    /// -1...1. This is the contract's `earFit` (A-0b, merged `6adf584`), ported with JavaScript's rules for NaN (`jsMin` and `jsMax` pass it on).
    static let earFitMargin = 0.5, earFitMinimum = 0.35
    static func earFit(_ L: Layout, _ s: CatPose, ceiling: Double, margin: Double = earFitMargin, minimum: Double = earFitMinimum) -> Double {
        func jsMin(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : min(a, b) }
        func jsMax(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : max(a, b) }
        let ct = cos(s.tilt), st = sin(s.tilt)
        var f = 1.0
        for e in L.ears {
            let cr = cos(e.rot), sr = sin(e.rot)
            let A = st * s.sx * cr + ct * s.sy * sr, B = ct * s.sy * cr - st * s.sx * sr
            let y0 = L.head.y + st * s.sx * e.bx + ct * s.sy * e.by
            func rise(_ u: Double) -> Double { 0.9 * A * e.tip * u + B * (-e.h + e.tip * (0.475 + 0.825 * u * u)) }   // the top edge at u, above the ear's base (negative: higher up)
            let d = jsMin(jsMin(rise(-1), rise(1)), rise(B > 1e-9 ? jsMax(-1, jsMin(1, -0.9 * A / (1.65 * B))) : 0))
            if y0 + d >= ceiling + margin || d >= -1e-9 { continue }
            f = jsMin(f, jsMax(minimum, (ceiling + margin - y0) / d))
        }
        return f.isFinite ? max(minimum, min(1, f)) : 1
    }

    // MARK: Collar (the contract's `collarGeometry`, A-0b)

    /// The collar styles that are drawn, in the contract's order (the fourth, "off", draws nothing). Frozen: Settings stores them (`CatRules.collarStyles`).
    static let collarStyles = ["tag", "band", "kerchief"]
    /// The renderer pass the collar is drawn in: between `foldEars` and `whiskers` of the front pass. `passes` itself stays as A-0 pinned it.
    static let collarPass = "front"
    /// The smallest sizes, in DEVICE pixels, so a collar still reads as a colour at Ø12 and Ø20 (the contract's `COLLAR_MIN`).
    enum CollarMin { static let band = 3.0, tag = 6.0, kerchiefW = 7.0, kerchiefDrop = 5.0 }

    /// Where one collar sits, in head-local px (before the tilt and the squash), turning with the face warp.
    /// `band`: a polyline along the lower outline, left to right, inset so its outer edge stays inside the head, drawn `width` thick (tag and band);
    /// `tag`: a round tag at centre front; `kerchief`: a triangle under the chin, `pts` along the lower outline and `apex` below them.
    struct Collar {
        var style: String
        var R: Double
        var width: Double?
        var band: [(x: Double, y: Double)]?
        var tag: (x: Double, y: Double, r: Double)?
        var kerchief: (pts: [(x: Double, y: Double)], apex: (x: Double, y: Double))?

        /// The collar as the fixtures hold it (key `out` of collar-cases.json).
        var json: [String: Any] {
            var out: [String: Any] = ["style": style, "R": R]
            if let width { out["width"] = width }
            if let band { out["band"] = band.map { [$0.x, $0.y] } }
            if let tag { out["tag"] = ["x": tag.x, "y": tag.y, "r": tag.r] }
            if let kerchief { out["kerchief"] = ["pts": kerchief.pts.map { [$0.x, $0.y] }, "apex": [kerchief.apex.x, kerchief.apex.y]] as [String: Any] }
            return out
        }
    }

    /// The collar for a style, given the head's radius `R` (px) and its warp. `dpr` is the device pixel ratio (a value that is not above 0 counts as 2).
    /// nil for "off", and for a style that is not one of the three. This is what the renderer calls (it already has `R` and the warp of the cat it draws).
    static func collarGeometry(_ p: CatPreset, R: Double, warp W: Warp, style: String, dpr dprIn: Double = 2) -> Collar? {
        guard collarStyles.contains(style) else { return nil }
        let dpr = dprIn > 0 ? dprIn : 2
        let width = max(0.1 * R, CollarMin.band / dpr)                       // a tenth of R, never under 3 device px
        let k = max(0.7, min(0.92, 1 - (width / 2 + 0.5 / dpr) / (p.ry * R)))
        let n = 90
        let ring = Array(supPoints(rx: p.rx * k, ry: p.ry * k, n: p.n, dy: 0, spike: 0, count: 0, steps: n).prefix(n))   // R units; index i is i/90 of a turn, y down
        var out = Collar(style: style, R: R)
        if style == "kerchief" {
            let hw = min(p.rx * k, max(0.5 * p.rx, CollarMin.kerchiefW / dpr / R * 0.65))
            let arc = ring.enumerated().filter { $0.element.1 > 0 && abs($0.element.0) <= hw }
                .sorted { $0.element.0 < $1.element.0 || ($0.element.0 == $1.element.0 && $0.offset < $1.offset) }.map { $0.element }
            let (ax, ay) = W(0, p.ry * k)
            let pts = arc.map { W($0.0, $0.1) }, top = pts.map { $0.1 }.max() ?? -Double.infinity
            out.kerchief = (pts.map { (x: $0.0, y: $0.1) }, (x: ax, y: max(ay, top) + max(0.34 * R, CollarMin.kerchiefDrop / dpr)))
        } else {
            let lower = Array(ring[(n * 40 / 360)...(n * 140 / 360)].reversed())   // left to right, 40° to 140°
            out.width = width
            out.band = lower.map { q in let w = W(q.0, q.1); return (x: w.0, y: w.1) }
            if style == "tag" {
                let (x, y) = W(0, p.ry * k)
                out.tag = (x: x, y: y, r: max(0.16 * R, CollarMin.tag / dpr / 2))
            }
        }
        return out
    }

    /// The same for a pose and a head width, the way the contract's `collarGeometry(preset, pose, D, style, {dpr, detail})` is called: it makes the
    /// layout itself to get `R` and the warp. `detail` is as in `layout`.
    static func collarGeometry(_ p: CatPreset, _ s: CatPose, D: Double, style: String, dpr: Double = 2, detail: String? = nil) -> Collar? {
        let L = layout(p, s, cx: 0, cy: 0, D: D, Options(full: detail.map { $0 == "full" }))
        return collarGeometry(p, R: L.R, warp: L.warp, style: style, dpr: dpr)
    }

    /// The draw order, as named layers. The renderer draws a *behind* pass, the head, then a *front* pass, so outfits
    /// (sub-project I) can sit behind or in front of the head. Each layer's data comes from `layout`. The collar of stage 6 goes in the
    /// front pass between `foldEars` and `whiskers` (the contract's `collarPass`, "front"); `passes` stays as A-0 pinned it.
    static let passes: [String: [String]] = [
        "behind": ["glow", "zoomTrails", "ruff", "bib", "paws", "ears"],
        "head": ["head", "markings", "tint", "rim", "blush", "eyes", "mouth", "nose"],
        "front": ["foldEars", "whiskers", "badge", "particles", "balls"],
    ]
}
