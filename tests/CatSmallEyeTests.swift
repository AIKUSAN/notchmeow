import Foundation

@main
enum CatSmallEyeTests {
    typealias E = CatSmallEye

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    /// A JSON number (a boolean, a string and null are not numbers: the contract takes them as the default).
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// `smallEye(shape, o)` of the fixture, called the way the app calls it: a missing or odd value is the default.
    static func call(_ shape: Any?, _ o: Any?) -> E.Eye? {
        guard let name = shape as? String, let s = CatEye(rawValue: name) else { return nil }
        let r = o as? [String: Any] ?? [:]
        return E.eye(s, sd: number(r["sd"]) == 1 ? 1 : -1, R: number(r["R"]) ?? 0, es: number(r["es"]) ?? 1, open: number(r["open"]) ?? 1,
                     yaw: number(r["yaw"]) ?? 0, pitch: number(r["pitch"]) ?? 0, kitten: (r["kitten"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false,
                     cat: r["cat"] as? String)
    }

    static func all(_ e: E.Eye) -> [Double] {
        [e.iris?.rx, e.iris?.ry, e.iris?.r, e.pupil?.x, e.pupil?.y, e.pupil?.rx, e.pupil?.ry, e.light?.x, e.light?.y, e.light?.r, e.rim,
         e.line?.x0, e.line?.y0, e.line?.cx, e.line?.cy, e.line?.x1, e.line?.y1, e.line?.width].compactMap { $0 }
    }

    @MainActor static func main() {
        let fx = CT.fixture("small-eye-cases.json")

        CT.section("the numbers and the shape list are the contract's")
        CT.check("the four resting shapes, in the contract's order", E.shapes.map(\.rawValue), fx["shapes"] as! [String])
        let k: [String: Any] = [
            "iris": ["w": E.K.irisW, "h": E.K.irisH], "pupil": ["w": E.K.pupilW, "h": E.K.pupilH], "wide": ["w": E.K.wideW, "h": E.K.wideH],
            "dot": ["iris": [E.K.dotIris, E.K.dotIris], "pupil": [E.K.dotPupil, E.K.dotPupil]], "tired": ["open": E.K.tiredOpen],
            "light": ["x": E.K.lightX, "y": E.K.lightY, "r": E.K.lightR, "minR": E.K.lightMinR], "rim": ["k": E.K.rimK, "min": E.K.rimMin],
            "travel": ["x": E.K.travelX, "y": E.K.travelY], "closeBelow": E.K.closeBelow, "pupilFit": E.K.pupilFit, "kitten": ["w": E.K.kittenW, "h": E.K.kittenH],
            "line": ["width": E.K.lineWidth, "minWidth": E.K.lineMinWidth, "curve": E.K.lineCurve],
            "bright": E.K.bright, "brightPupil": ["w": E.K.brightPupilW],
        ]
        CT.checkJSON("SMALL_EYE", got: k, want: fx["constants"]!)
        CT.check("the bright coats, in the contract's order", E.K.bright, fx["bright"] as! [String])

        CT.section("usesSmallEye: \(rows(fx["uses"]).count) rows")
        var diffs: [String] = []
        for r in rows(fx["uses"]) {
            let got = CatEye(rawValue: r["shape"] as! String).map { E.uses($0, sd: number(r["sd"])!) } ?? false
            if got != (r["out"] as! Bool) { diffs.append("\(r["shape"]!) \(r["sd"]!): \(got)") }
        }
        CT.checkRows("every shape and side is as the fixture says (ink shapes and the right eye of a wink stay ink)", diffs)

        for group in ["sizes", "squints", "gazes", "scales", "others", "hostile", "brights"] {
            CT.section("smallEye, \(group): \(rows(fx[group]).count) rows")
            diffs = []
            for r in rows(fx[group]) {
                let got: Any = call(r["shape"], r["o"]).map { CT.json($0) } ?? NSNull()
                let d = CT.diffs(got, r["out"] ?? NSNull())
                if !d.isEmpty { diffs.append("\(r["shape"] ?? "nil") \(r["o"] ?? "nil"): \(d.first!)") }
            }
            CT.checkRows("every row comes out as the fixture says", diffs)
        }

        CT.section("a real NaN or infinity (JSON cannot write them, a call can)")
        let nan = Double.nan, inf = Double.infinity
        let base = E.eye(.pill, R: 9)!, odd = E.eye(.pill, sd: nan, R: 9, es: nan, open: nan, yaw: nan, pitch: nan)!
        CT.check("NaN in es, open, yaw, pitch and sd is the default", odd, base)
        CT.check("NaN in R is a head of 0", E.eye(.pill, R: nan)!, E.eye(.pill, R: 0)!)
        CT.check("infinity in R is a head of 0 too (it is not a number)", E.eye(.pill, R: inf)!, E.eye(.pill, R: 0)!)
        CT.check("a huge R is held to 10000", E.eye(.pill, R: 1e300)!, E.eye(.pill, R: 1e4)!)
        CT.check("a huge es is held to 10", E.eye(.pill, R: 9, es: 1e300)!, E.eye(.pill, R: 9, es: 10)!)
        CT.check("an ink shape is nil whatever else is wrong", E.eye(.happy, R: nan), nil)

        CT.section("the black coats' eyes glow: flat, no rim, a thinner slit pupil, and nothing else about the eye changes")
        for id in E.K.bright { for kitten in [false, true] {
            let b = E.eye(.pill, R: 9, kitten: kitten, cat: id)!, n = E.eye(.pill, R: 9, kitten: kitten, cat: "momo")!
            CT.check("\(id)\(kitten ? " kitten" : ""): flat, no rim", [b.flat == true, b.rim == 0], [true, true])
            CT.check("\(id)\(kitten ? " kitten" : ""): the same iris and catchlight as a normal coat's, a pupil 0.12 wide instead of 0.18", [b.iris == n.iris, b.light == n.light, abs(b.pupil!.rx / n.pupil!.rx - 0.12 / 0.18) < 1e-12, b.pupil!.ry == n.pupil!.ry], [true, true, true, true])
        } }
        CT.check("a normal coat has no flat key and keeps its rim", [E.eye(.pill, R: 9, cat: "momo")!.flat == nil, E.eye(.pill, R: 9)!.flat == nil, E.eye(.pill, R: 9)!.rim! > 0], [true, true, true])
        CT.check("only an exact coat ID is bright: a capital, a space, an empty string and nil are normal coats", ["Midnight", "midnight ", "", "mocha\n"].map { E.eye(.pill, R: 9, cat: $0)!.flat == nil } + [E.eye(.pill, R: 9, cat: nil)!.flat == nil], [true, true, true, true, true])
        CT.check("the round pupil of a dot keeps its size on a bright coat", E.eye(.dot, R: 9, cat: "oreo")!.pupil, E.eye(.dot, R: 9)!.pupil)
        CT.check("a closed bright eye is the same line as a normal one, and an ink shape is still nil", [E.eye(.pill, R: 9, open: 0, cat: "mocha")! == E.eye(.pill, R: 9, open: 0)!, E.eye(.happy, R: 9, cat: "mocha") == nil], [true, true])
        CT.check("the flat iris is the lighter of the two iris colours: Midnight #F7D45C, Oreo #DDEB5A, Mocha #F6C44C (and the first on a tie)",
                 [E.flatIris(["#F7D45C", "#D9921C"]), E.flatIris(["#7FA82A", "#DDEB5A"]), E.flatIris(["#F6C44C", "#C2761A"]), E.flatIris(["#102030", "#102030"])], ["#F7D45C", "#DDEB5A", "#F6C44C", "#102030"])

        CT.section("the floors: at Ø6 the catchlight and the rim are not thinner than half a point")
        var floors = true
        for s in E.shapes { for kitten in [false, true] {
            let e = E.eye(s, R: 3, kitten: kitten)!
            floors = floors && e.light!.r >= E.K.lightMinR && e.rim! >= E.K.rimMin
            if let b = E.eye(s, R: 3, kitten: kitten, cat: "midnight") { floors = floors && b.light!.r >= E.K.lightMinR && b.rim == 0 }
        } }
        CT.checkTrue("catchlight radius at least 0.45 and rim at least 0.5, every shape, kitten or not", floors)

        CT.section("a blink or a squint closes the eye to a line under 0.22 of its height; a tired eye is never wider than 0.42")
        CT.check("0.21 of an eye is a line", E.eye(.pill, R: 9, open: 0.21)!.closed, true)
        CT.check("0.22 of an eye is an eye", E.eye(.pill, R: 9, open: 0.22)!.closed, false)
        CT.check("a tired eye that is wide open is as open as 0.42", E.eye(.tired, R: 9, open: 1)!, E.eye(.tired, R: 9, open: E.K.tiredOpen)!)
        CT.checkNear("the closed line is never thinner than one point", E.eye(.pill, R: 3, open: 0)!.line!.width, 1)

        CT.section("the pupil never leaves the iris, at every squint, gaze, size, kitten and expression scale")
        var worst = 0.0, count = 0
        for s in E.shapes { for kitten in [false, true] { for es in [0.5, 1, 1.5] { for open in [0.22, 0.3, 0.5, 0.8, 1] {
            for yaw in [-2.0, -0.62, 0, 0.31, 0.62, 2] { for pitch in [-1.0, -0.5, 0, 0.25, 0.5, 1] {
                let e = E.eye(s, R: 9, es: es, open: open, yaw: yaw, pitch: pitch, kitten: kitten)!
                guard !e.closed, let i = e.iris, let p = e.pupil else { continue }
                for a in 0..<48 {
                    let t = Double(a) / 48 * 2 * Double.pi, x = p.x + p.rx * cos(t), y = p.y + p.ry * sin(t)
                    worst = max(worst, (x / i.rx) * (x / i.rx) + (y / i.ry) * (y / i.ry))
                }
                count += 1
            } }
        } } } }
        CT.checkTrue("every pupil edge point is inside the iris (\(count) eyes, the farthest at \(String(format: "%.4f", worst)) of the iris's edge)", worst <= 1 + 1e-9)

        CT.section("nothing is NaN, whatever the inputs")
        var finite = true
        var seed: UInt64 = 7
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        let wild: [Double] = [nan, inf, -inf, -1, 0, 1, 1e300, -1e300, 5e-324]
        for _ in 0..<3000 {
            func pick() -> Double { next() < 0.5 ? wild[Int(next() * Double(wild.count))] : (next() - 0.5) * 40 }
            let s = CatEye.allCases[Int(next() * Double(CatEye.allCases.count))]
            let coat = ["midnight", "oreo", "mocha", "momo", "", "MIDNIGHT"]
            if let e = E.eye(s, sd: pick(), R: pick(), es: pick(), open: pick(), yaw: pick(), pitch: pick(), kitten: next() < 0.5, cat: next() < 0.5 ? coat[Int(next() * Double(coat.count))] : nil) { finite = finite && all(e).allSatisfy(\.isFinite) }
        }
        CT.checkTrue("3000 calls with NaN, infinities and huge numbers give finite numbers only", finite)

        CT.finish()
    }
}
