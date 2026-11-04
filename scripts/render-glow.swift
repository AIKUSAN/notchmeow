import AppKit
import SwiftUI

// Draws the island's hover glow (IslandGlowView, IslandGlow.swift) into a PNG without launching NotchMeow: the glow's own SwiftUI view on the app's own island shape (`IslandShape`), the
// compact notch strip and the open island, on a light and a dark menu bar, with the glow on and off for comparison. One still frame (the angle is fixed); the colours are Theme.Glow.
//   bash scripts/render-glow.sh --out hover-glow.png [--scale 2] [--angle 40]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift.

@main
struct RenderGlow {
    struct Panel: View {
        let title: String
        let dark: Bool
        let expanded: Bool
        let glow: Bool
        let angle: Double
        var rowHeight: CGFloat? = nil

        var body: some View {
            let w: CGFloat = expanded ? 640 : 360, h: CGFloat = expanded ? 160 : 32
            let shape = IslandShape(width: w, height: h, cornerRadius: expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner, topRadius: 0)
            ZStack(alignment: .topLeading) {
                // The menu bar and the wallpaper under it.
                Rectangle().fill(dark ? Color(hex: "#1D1E22") : Color(hex: "#D9DCE2"))
                Rectangle().fill(dark ? Color(hex: "#2A2B31") : Color(hex: "#EEF0F4")).frame(height: 24)
                ZStack(alignment: .topLeading) {
                    shape.fill(Color.black)
                    if glow { IslandGlowView(shape: IslandShape(width: w, height: h, cornerRadius: expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner, topRadius: 0, openTop: true), fixedAngle: angle) }
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .offset(x: (700 - w) / 2, y: 0)
                Text(title).font(.system(size: 10)).foregroundColor(dark ? .white.opacity(0.55) : .black.opacity(0.5)).offset(x: 8, y: (expanded ? 160 : 32) + 14)
            }
            .frame(width: 700, height: rowHeight ?? (expanded ? 200 : 70), alignment: .topLeading)
            .clipped()
        }
    }

    @MainActor static func main() {
        var out = "hover-glow.png", scale = 2.0, angle = 40.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            case "--angle": angle = Double(it.next() ?? "") ?? angle
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let sheet = VStack(spacing: 0) {
            HStack(spacing: 0) {
                Panel(title: "compact, light menu bar, glow on", dark: false, expanded: false, glow: true, angle: angle)
                Panel(title: "compact, dark menu bar, glow on", dark: true, expanded: false, glow: true, angle: angle)
            }
            HStack(spacing: 0) {
                Panel(title: "open, light, glow on", dark: false, expanded: true, glow: true, angle: angle)
                Panel(title: "open, dark, glow on", dark: true, expanded: true, glow: true, angle: angle)
            }
            HStack(spacing: 0) {
                Panel(title: "compact, light, glow off (Settings)", dark: false, expanded: false, glow: false, angle: angle, rowHeight: 200)
                Panel(title: "open, dark, glow off (Settings)", dark: true, expanded: true, glow: false, angle: angle, rowHeight: 200)
            }
        }
        let host = NSHostingView(rootView: sheet.fixedSize())
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((size.width * scale).rounded()), pixelsHigh: Int((size.height * scale).rounded()), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { FileHandle.standardError.write(Data("cannot write \(out)\n".utf8)); exit(1) }
        print("wrote \(out) (\(Int(size.width)) x \(Int(size.height)) pt at \(scale)x)")
    }
}
