import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws NotchMeow's own icons with the real CatRenderer, without launching the app: the macOS app icon, the menu-bar template and the
// Windows and Linux (Tauri) icons. The owner picked the designs on 2026-10-07: app icon C Peek (Momo peeks over Shrimpy, on night teal)
// and menu bar M1 Momo (one head, pure black plus alpha). Run it through scripts/gen-icons.sh:
//   bash scripts/gen-icons.sh              writes the 18 files in place, under their existing names
//   bash scripts/gen-icons.sh <outDir>     writes the same tree under <outDir> instead (to compare before replacing)
// Nothing here is hand-drawn cat art: the only shapes of its own are the app-icon body (a continuous-corner rounded square), the
// backgrounds and the menu-bar eye and nose holes. Contents.json is not written: the repo's own stays.

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Bitmaps

/// A y-down RGBA bitmap in pixels that owns its bytes, so pixel work (masks, box filters) is plain array code.
final class Bitmap {
    let w: Int, h: Int
    let cg: CGContext
    private let buf: UnsafeMutableRawPointer

    init(_ w: Int, _ h: Int) {
        self.w = w; self.h = h
        buf = UnsafeMutableRawPointer.allocate(byteCount: w * h * 4, alignment: 16)
        buf.initializeMemory(as: UInt8.self, repeating: 0, count: w * h * 4)
        cg = CGContext(data: buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.translateBy(x: 0, y: CGFloat(h))
        cg.scaleBy(x: 1, y: -1)
        cg.setAllowsAntialiasing(true)
        cg.setShouldAntialias(true)
        cg.interpolationQuality = .high
    }
    deinit { buf.deallocate() }

    var bytes: UnsafeMutablePointer<UInt8> { buf.assumingMemoryBound(to: UInt8.self) }
    var image: CGImage { cg.makeImage()! }

    func pngData() -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        precondition(CGImageDestinationFinalize(dest), "could not encode a PNG")
        return data as Data
    }

    func writePNG(_ path: String) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        precondition(CGImageDestinationFinalize(dest), "could not write \(path)")
    }
}

@MainActor func hex(_ s: String) -> CGColor { CatDraw.color(s) }

// MARK: - The app-icon body (macOS Big Sur+ grid)

/// A continuous-corner rounded square ("squircle") of side `S` at (`origin`, `origin`): the corner is a circular arc blended into the
/// straight edges by two cubic Béziers on each side (the construction behind Figma's corner smoothing; 0.6 is the iOS/macOS look).
func squirclePath(origin: Double, size S: Double, radius r: Double, smoothing: Double = 0.6) -> CGPath {
    func rad(_ d: Double) -> Double { d * .pi / 180 }
    let p = (1 + smoothing) * r
    let arcMeasure = 90 * (1 - smoothing)
    let arc = sin(rad(arcMeasure / 2)) * r * 2.0.squareRoot()
    let alpha = (90 - arcMeasure) / 2
    let p3p4 = r * tan(rad(alpha / 2))
    let beta = 45 * smoothing
    let c = p3p4 * cos(rad(beta)), d = c * tan(rad(beta))
    let b = (p - arc - c - d) / 3, a = 2 * b
    func rot(_ x: Double, _ y: Double, _ k: Int) -> CGPoint {
        var (px, py) = (x, y)
        for _ in 0..<k { (px, py) = (S - py, px) }   // a quarter turn clockwise about the centre, y down
        return CGPoint(x: px + origin, y: py + origin)
    }
    let path = CGMutablePath()
    for k in 0..<4 {
        let s0 = rot(S - p, 0, k)
        k == 0 ? path.move(to: s0) : path.addLine(to: s0)
        path.addCurve(to: rot(S - p + a + b + c, d, k), control1: rot(S - p + a, 0, k), control2: rot(S - p + a + b, 0, k))
        let a0 = atan2(d - r, (S - p + a + b + c) - (S - r)), a1 = atan2(d + arc - r, (S - d) - (S - r))
        path.addArc(center: rot(S - r, r, k), radius: r, startAngle: a0 + Double(k) * .pi / 2, endAngle: a1 + Double(k) * .pi / 2, clockwise: false)
        path.addCurve(to: rot(S, p, k), control1: rot(S, d + arc + c, k), control2: rot(S, d + arc + b + c, k))
    }
    path.closeSubpath()
    return path
}

enum Grid {
    /// The 1024 canvas: an 824 body, 100 of margin each side, corner radius 185.4 (22.5 %), a soft shadow below it.
    static let canvas = 1024.0, margin = 100.0, body = 824.0, radius = 185.4
    static let shadowDY = 10.0, shadowBlur = 24.0, shadowAlpha = 0.34
    static var path: CGPath { squirclePath(origin: margin, size: body, radius: radius) }
}

// MARK: - C Peek

/// One cat in the composition, in 1024-canvas units. `D` is the head width, as in CatRenderer.
struct Placement {
    var id: String
    var cx: Double, cy: Double, D: Double
    var tilt = 0.0, yaw = 0.0, smile = 0.0
}

/// Where the icon goes. The Mac gets the Big Sur grid with its shadow baked in (macOS does not add one); Windows gets the same body with a thin margin and no shadow.
enum Layout { case mac, windows }

@MainActor
enum Icons {
    /// Momo peeks over Shrimpy's head (drawn in this order, last in front).
    static let cats = [
        Placement(id: "momo", cx: 540, cy: 372, D: 336, tilt: -0.07, yaw: -0.08, smile: 0.3),
        Placement(id: "shrimpy", cx: 500, cy: 648, D: 450, smile: 0.5),
    ]

    /// A deep night teal (the notch's black, lifted) with a soft halo behind Momo.
    static func background(_ cg: CGContext) {
        CatDraw.linear(cg, [(0, hex("#3B6E8C")), (1, hex("#0C1722"))], from: (0, Grid.margin), to: (0, Grid.margin + Grid.body))
        CatDraw.radial(cg, [(0, CatDraw.rgb([150, 222, 236], 0.50)), (1, CatDraw.rgb([150, 222, 236], 0))], center: (540, 330), r0: 0, r1: 440)
    }

    /// An optical size for the small icons: the cats are enlarged around the canvas centre (fewer, bigger shapes).
    static func zoom(_ px: Int) -> Double { px <= 16 ? 1.1 : px <= 32 ? 1.06 : 1 }

    /// The body's margin in pixels: the Big Sur proportion (100 of 1024) from 128 px up, tighter at the small sizes so the body keeps its pixels.
    static func margin(_ px: Int, _ layout: Layout) -> Double {
        if layout == .windows { return max(0.5, Double(px) * 32 / Grid.canvas) }
        switch px {
        case ..<24: return 1
        case ..<48: return 2
        case ..<96: return 5
        default: return Grid.margin * Double(px) / Grid.canvas
        }
    }

    /// Draws the icon at `px` pixels. The cats are drawn at their true pixel size, so the renderer picks its own detail
    /// (flat fills and ink eyes below a head width of 28 px).
    static func render(px: Int, layout: Layout = .mac) -> Bitmap {
        let bm = Bitmap(px, px), cg = bm.cg
        let m = margin(px, layout), s = (Double(px) - 2 * m) / Grid.body       // pixels per canvas unit inside the body
        cg.saveGState()
        cg.translateBy(x: CGFloat(m - Grid.margin * s), y: CGFloat(m - Grid.margin * s))
        cg.scaleBy(x: CGFloat(s), y: CGFloat(s))

        // The body, with its shadow underneath.
        let body = Grid.path
        if layout == .mac && px >= 32 {
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -Grid.shadowDY * s), blur: CGFloat(Grid.shadowBlur * s), color: CatDraw.black(Grid.shadowAlpha))
            cg.fill(body, CatDraw.black(1))
            cg.restoreGState()
        }
        cg.saveGState()
        cg.clip(body)
        cg.clear(CGRect(x: -100, y: -100, width: Grid.canvas + 200, height: Grid.canvas + 200))   // the shadow's fill is only there to cast it
        background(cg)

        // The cats, enlarged around the canvas centre at the small sizes.
        let z = zoom(px)
        for c in cats {
            let cx = 512 + (c.cx - 512) * z, cy = 512 + (c.cy - 512) * z, D = c.D * z
            var pose = CatPose()
            pose.tilt = c.tilt; pose.yaw = c.yaw; pose.smile = c.smile
            var look = CatLook(preset: CatPresets.byID(c.id), pose: pose)
            look.inkEyes = true   // the approved icons keep the flat ink eyes at the small sizes: the coloured small eyes are for the app's cats
            var opts = CatDrawOptions(tint: false)
            opts.badge = false
            cg.saveGState()
            cg.scaleBy(x: CGFloat(1 / s), y: CGFloat(1 / s))
            CatRenderer.draw(cg, look, cx: cx * s, cy: cy * s, D: D * s, opts)
            cg.restoreGState()
        }
        // A faint light along the top edge, like the system icons have.
        if px >= 64 {
            cg.saveGState()
            cg.addPath(body)
            cg.setLineWidth(5)
            cg.replacePathWithStrokedPath()
            cg.clip()
            CatDraw.linear(cg, [(0, CatDraw.white(0.5)), (0.45, CatDraw.white(0.0)), (1, CatDraw.white(0))], from: (0, Grid.margin), to: (0, Grid.margin + Grid.body))
            cg.restoreGState()
        }
        cg.restoreGState()
        cg.restoreGState()
        return bm
    }
}

// MARK: - M1 Momo: the menu-bar template (pure black plus alpha)

@MainActor
enum MenuBar {
    static let ptW = 24, ptH = 18
    /// The master is drawn at 24 px per point, so 1x, 2x and 3x are whole-number box reductions (24, 12 and 8).
    static let ss = 24

    /// The alpha master at `ss` px per point: 576 x 432, one byte per pixel. One head, Momo (the plain round outline with big ears),
    /// with the compact renderer's ink eyes and nose cut out as holes.
    static func master() -> [UInt8] {
        let W = ptW * ss, H = ptH * ss, n = W * H
        let tmp = Bitmap(W, H)
        let pose = CatPose()
        var look = CatLook(preset: CatPresets.byID("momo"), pose: pose)
        look.inkEyes = true
        var opts = CatDrawOptions(tint: false); opts.badge = false; opts.full = false   // the compact drawing: no whiskers, flat fills, ink eyes
        let L = CatRenderer.draw(tmp.cg, look, cx: 12 * Double(ss), cy: 10.6 * Double(ss), D: 16.4 * Double(ss), opts)
        var acc = [UInt8](repeating: 0, count: n)
        for i in 0..<n { acc[i] = tmp.bytes[i * 4 + 3] }
        // the eyes and nose, as holes: the compact ink eye's own size, in the head's frame
        let holes = Bitmap(W, H), hc = holes.cg
        let R = L.R
        hc.saveGState()
        hc.translateBy(x: L.head.x, y: L.head.y)
        hc.rotate(by: pose.tilt)
        hc.scaleBy(x: pose.sx, y: pose.sy)
        for e in L.eyes where e.visible {
            hc.saveGState()
            hc.translateBy(x: e.x, y: e.y)
            hc.scaleBy(x: e.fx, y: e.fy)
            let w = 0.34 * R * pose.es, h = 0.4 * R * pose.es
            hc.setFillColor(CatDraw.black(1))
            hc.addPath(CatDraw.roundRect(-w / 2, -h / 2, w, h, min(w, h) / 2))
            hc.fillPath()
            hc.restoreGState()
        }
        if L.nose.visible {
            let k = 1.1, nx = L.nose.nx, ny = L.nose.ny, nw = L.nose.nw * k, nh = L.nose.nh * k   // the hole is a bit larger than the renderer's nose
            let nose = CGMutablePath()
            nose.move(to: CGPoint(x: nx - nw / 2, y: ny - nh / 2))
            nose.addQuadCurve(to: CGPoint(x: nx + nw / 2, y: ny - nh / 2), control: CGPoint(x: nx, y: ny - nh * 0.8))
            nose.addQuadCurve(to: CGPoint(x: nx, y: ny + nh / 2), control: CGPoint(x: nx + nw * 0.1, y: ny + nh * 0.6))
            nose.addQuadCurve(to: CGPoint(x: nx - nw / 2, y: ny - nh / 2), control: CGPoint(x: nx - nw * 0.1, y: ny + nh * 0.6))
            hc.setFillColor(CatDraw.black(1)); hc.addPath(nose); hc.fillPath()
        }
        hc.restoreGState()
        for i in 0..<n { acc[i] = UInt8(Double(acc[i]) * (1 - Double(holes.bytes[i * 4 + 3]) / 255)) }
        return acc
    }

    /// The master reduced by `f` (a whole number) with a box filter, as pure black plus alpha.
    static func reduced(_ m: [UInt8], by f: Int) -> Bitmap {
        let W = ptW * ss, w = W / f, h = ptH * ss / f
        let bm = Bitmap(w, h)
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0
                for dy in 0..<f { for dx in 0..<f { sum += Int(m[(y * f + dy) * W + x * f + dx]) } }
                let a = UInt8((Double(sum) / Double(f * f)).rounded())
                let o = (y * w + x) * 4
                bm.bytes[o] = 0; bm.bytes[o + 1] = 0; bm.bytes[o + 2] = 0; bm.bytes[o + 3] = a   // premultiplied black is just alpha
            }
        }
        return bm
    }

    /// 1x, 2x and 3x: 24 x 18, 48 x 36, 72 x 54.
    static func render() -> [(scale: Int, bm: Bitmap)] {
        let m = master()
        return [1, 2, 3].map { ($0, reduced(m, by: ss / $0)) }
    }
}

// MARK: - The file sets

/// PNG-in-ICO written by hand (Vista and later): a 6-byte header, one 16-byte entry per image, then the PNG files.
func icoData(_ pngs: [(size: Int, png: Data)]) -> Data {
    var d = Data()
    func u16(_ v: Int) { d.append(UInt8(v & 0xff)); d.append(UInt8((v >> 8) & 0xff)) }
    func u32(_ v: Int) { u16(v & 0xffff); u16((v >> 16) & 0xffff) }
    u16(0); u16(1); u16(pngs.count)
    var offset = 6 + 16 * pngs.count
    for (size, png) in pngs {
        d.append(UInt8(size >= 256 ? 0 : size)); d.append(UInt8(size >= 256 ? 0 : size))   // width, height (0 means 256)
        d.append(0); d.append(0)                                                           // colours, reserved
        u16(1); u16(32)                                                                    // planes, bits per pixel
        u32(png.count); u32(offset)
        offset += png.count
    }
    for (_, png) in pngs { d.append(png) }
    return d
}

// MARK: - Entry point

@main
enum GenIcons {
    /// The exact files and sizes the three asset folders hold, written under `out` at their repo paths.
    @MainActor static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "."
        // macOS AppIcon.appiconset: icon_<pt>x<pt>[@2x].png, pixel = pt x scale
        for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                           ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
            Icons.render(px: px).writePNG("\(out)/NotchBuddy/Assets.xcassets/AppIcon.appiconset/\(name).png")
        }
        // macOS MenuBarIcon.imageset: template, black plus alpha
        for (sc, bm) in MenuBar.render() {
            bm.writePNG("\(out)/NotchBuddy/Assets.xcassets/MenuBarIcon.imageset/menubar\(sc == 1 ? "" : "@\(sc)x").png")
        }
        // Windows and Linux (Tauri)
        let w = "\(out)/windows/src-tauri/icons"
        for (name, px) in [("32x32", 32), ("128x128", 128), ("128x128@2x", 256), ("icon", 512)] {
            Icons.render(px: px, layout: .windows).writePNG("\(w)/\(name).png")
        }
        let ico = icoData([16, 24, 32, 48, 64, 128, 256].map { ($0, Icons.render(px: $0, layout: .windows).pngData()) })
        try! ico.write(to: URL(fileURLWithPath: "\(w)/icon.ico"))
        print("wrote the 18 icon files under \(out)")
    }
}
