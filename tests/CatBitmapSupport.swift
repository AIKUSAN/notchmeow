import CoreGraphics
import Foundation

/// Draws into a transparent RGBA bitmap whose y axis points down, like a SwiftUI Canvas, so the tests can look at pixels.
enum Bitmap {
    @MainActor static func render(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> [UInt8] {
        let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.translateBy(x: 0, y: CGFloat(h))
        cg.scaleBy(x: 1, y: -1)
        draw(cg)
        let p = cg.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        return Array(UnsafeBufferPointer(start: p, count: w * h * 4))
    }

    /// The alpha (0...255) of the pixel at x, y.
    static func alpha(_ px: [UInt8], _ x: Int, _ y: Int, _ w: Int) -> Int { Int(px[(y * w + x) * 4 + 3]) }

    /// How many pixels are painted at all.
    static func coverage(_ px: [UInt8]) -> Int { stride(from: 3, to: px.count, by: 4).filter { px[$0] > 8 }.count }

    /// The columns and rows where something is painted: left, top, right, bottom (nil when nothing is).
    static func bounds(_ px: [UInt8], _ w: Int) -> (left: Int, top: Int, right: Int, bottom: Int)? {
        var l = Int.max, t = Int.max, r = -1, b = -1
        for i in stride(from: 3, to: px.count, by: 4) where px[i] > 8 {
            let x = (i / 4) % w, y = (i / 4) / w
            l = min(l, x); r = max(r, x); t = min(t, y); b = max(b, y)
        }
        return r < 0 ? nil : (l, t, r, b)
    }
}
