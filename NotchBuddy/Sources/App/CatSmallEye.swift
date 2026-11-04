import Foundation

// The small coloured eyes of the compact detail level: below a head of Ø28 the plain resting eyes (pill, wide, dot and tired, and the left eye of a wink)
// are a round iris in the coat's colours, a slit pupil, one catchlight and a thin rim instead of an ink pill. This is the geometry only, in px of the
// eye's own frame (the centre is the origin, y down, before the renderer's foreshortening); the colours and the drawing are `CatFace`'s. Port of the
// "Small eyes" section of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/small-eye-cases.json pins it. The black coats (`K.bright`) glow:
// their eye is `flat` (the renderer fills the iris flat with `flatIris`, no rim) with a thinner slit pupil, and `cat` says which coat the eye is on. Foundation only.

enum CatSmallEye {
    /// The numbers of the contract (`SMALL_EYE`). Sizes are fractions of `u = R * es` (the head radius times the expression scale), full widths and heights.
    enum K {
        static let irisW = 0.42, irisH = 0.46
        static let pupilW = 0.18, pupilH = 0.40
        static let wideW = 1.16, wideH = 1.12
        static let dotIris = 0.42, dotPupil = 0.26
        /// A tired eye shows at most this much of itself.
        static let tiredOpen = 0.42
        static let lightX = -0.11, lightY = -0.10, lightR = 0.075, lightMinR = 0.45
        static let rimK = 0.05, rimMin = 0.5
        /// The pupil moves at most this much of the iris's half-width across and half-height up or down, so it never leaves the iris.
        static let travelX = 0.2, travelY = 0.08
        /// Under this much of the eye's height a blink or a squint closes it to a line, as the realistic eye does.
        static let closeBelow = 0.22
        static let pupilFit = 0.87
        /// A kitten's eye is this much wider and taller: what `CatPresets.kitten(of:)` does to a kitten's eyes.
        static let kittenW = 1.2, kittenH = 1.32
        static let lineWidth = 0.045, lineMinWidth = 1.0, lineCurve = 0.4
        /// The black coats glow. An explicit list, not a preset field, so the other coats and the preset fixtures do not move; a kitten keeps its parent's coat ID.
        static let bright = ["midnight", "oreo", "mocha"]
        /// A bright eye's slit pupil is this wide (the round pupil of a dot keeps its size).
        static let brightPupilW = 0.12
    }

    struct Iris: Encodable, Equatable, Sendable { var rx: Double, ry: Double, r: Double }
    struct Pupil: Encodable, Equatable, Sendable { var x: Double, y: Double, rx: Double, ry: Double }
    struct Light: Encodable, Equatable, Sendable { var x: Double, y: Double, r: Double }
    struct Line: Encodable, Equatable, Sendable { var x0: Double, y0: Double, cx: Double, cy: Double, x1: Double, y1: Double, width: Double }

    /// One small eye: the two ellipses' radii and centres, the gradient radius, the catchlight and the rim; or, when a blink or a squint closes it, the arc
    /// (drawn in the coat's ink colour at 0.9 alpha). A bright coat's eye has `flat` true and a rim of 0 (nil for every other eye).
    struct Eye: Encodable, Equatable, Sendable {
        var shape: String
        var closed: Bool
        var iris: Iris?
        var pupil: Pupil?
        var light: Light?
        var rim: Double?
        var line: Line?
        var flat: Bool?
    }

    /// The resting shapes that become a small coloured eye. The left eye of a wink is one too (its right eye is an ink arc).
    static let shapes: [CatEye] = [.pill, .wide, .dot, .tired]

    /// True when shape `shape` of the eye `sd` (-1 the left, 1 the right) is drawn with `eye(...)` at the compact level; false when it stays ink.
    static func uses(_ shape: CatEye, sd: Double) -> Bool { shapes.contains(shape) || (shape == .wink && sd < 0) }

    /// A number that is not finite is the default.
    private static func num(_ v: Double, _ d: Double) -> Double { v.isFinite ? v : d }

    /// One small eye, or nil for a shape that stays ink. `R` is the head radius (held to 0 up to 10000), `es` the pose's expression scale (0 up to 10),
    /// `open` is `pose.open * (1 - pose.lid)` (0 to 1), `yaw` and `pitch` the pose's, `kitten` the preset's `kitten`, `cat` the coat ID (the preset's `name`: only an
    /// exact ID in `K.bright` is a bright coat, anything else, nil too, is a normal one). A value that is not finite is its default.
    static func eye(_ shape: CatEye, sd: Double = -1, R: Double, es: Double = 1, open: Double = 1, yaw: Double = 0, pitch: Double = 0, kitten: Bool = false, cat: String? = nil) -> Eye? {
        guard uses(shape, sd: sd == 1 ? 1 : -1) else { return nil }
        let r = max(0, min(1e4, num(R, 0))), u = r * max(0, min(10, num(es, 1)))
        let sh: CatEye = shape == .wink ? .pill : shape
        let kw = kitten ? K.kittenW : 1, kh = kitten ? K.kittenH : 1, bright = cat.map { K.bright.contains($0) } ?? false
        let o = max(0, min(1, num(open, 1))), op = sh == .tired ? min(o, K.tiredOpen) : o
        let baseW = sh == .dot ? K.dotIris : K.irisW * (sh == .wide ? K.wideW : 1), baseH = sh == .dot ? K.dotIris : K.irisH * (sh == .wide ? K.wideH : 1)
        let rx0 = baseW / 2 * kw * u, ry0 = baseH / 2 * kh * u
        if op < K.closeBelow {
            return Eye(shape: shape.rawValue, closed: true, iris: nil, pupil: nil, light: nil, rim: nil,
                       line: Line(x0: -rx0, y0: 0, cx: 0, cy: K.lineCurve * ry0, x1: rx0, y1: 0, width: max(K.lineMinWidth, K.lineWidth * u)))
        }
        let ry = ry0 * op
        let pw = (sh == .dot ? K.dotPupil : bright ? K.brightPupilW : K.pupilW) / 2 * kw * u
        let pry = min((sh == .dot ? K.dotPupil : K.pupilH) / 2 * kh * u, K.pupilFit * ry)
        let gx = max(-1, min(1, num(yaw, 0) / 0.62)), gy = max(-1, min(1, num(pitch, 0) / 0.5))
        return Eye(shape: shape.rawValue, closed: false,
                   iris: Iris(rx: rx0, ry: ry, r: max(rx0, ry)),
                   pupil: Pupil(x: gx * K.travelX * rx0, y: -gy * K.travelY * ry, rx: pw, ry: pry),
                   light: Light(x: K.lightX / (K.irisW / 2) * rx0, y: K.lightY / (K.irisH / 2) * ry, r: max(K.lightR * u, K.lightMinR)),
                   rim: bright ? 0 : max(K.rimK * u, K.rimMin), line: nil, flat: bright ? true : nil)
    }

    /// What a bright eye's iris is filled with, flat: the lighter of the coat's two iris colours by luminance (Midnight #F7D45C, Oreo #DDEB5A, Mocha #F6C44C).
    static func flatIris(_ iris: [String]) -> String {
        func lum(_ hex: String) -> Double {
            let n = UInt32(hex.dropFirst(), radix: 16) ?? 0
            return 0.2126 * Double(n >> 16 & 255) + 0.7152 * Double(n >> 8 & 255) + 0.0722 * Double(n & 255)
        }
        guard iris.count == 2 else { return iris.first ?? "" }
        return lum(iris[0]) >= lum(iris[1]) ? iris[0] : iris[1]
    }
}
