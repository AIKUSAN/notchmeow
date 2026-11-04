import AppKit
import SwiftUI

// Draws the Debug-only cat panel (CatDevPanel.swift) into a PNG without launching NotchMeow: the panel's own SwiftUI view goes into a window
// that is never shown, and AppKit lays it out and draws it into a bitmap. The cats are live engines, stepped for 1.5 s before the shot.
// The system controls (pickers, buttons, group boxes) may come out blank in this offscreen bitmap; the cats and the layout do not.
// Run it through scripts/render-cat-panel.sh:  bash scripts/render-cat-panel.sh [--out panel.png] [--height 2200]

@main
struct RenderCatPanel {
    @MainActor static func main() {
        var out = "cat-panel.png", height = 2200.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--height": height = Double(it.next() ?? "") ?? height
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let host = NSHostingView(rootView: CatDevView())
        host.frame = NSRect(x: 0, y: 0, width: 980, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .windowBackgroundColor
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))   // SwiftUI lays out, and the engines run for a moment
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { FileHandle.standardError.write(Data("no bitmap\n".utf8)); exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        // The offscreen bitmap has no window background (the text is for a dark window): put it on one.
        guard let shot = rep.cgImage,
              let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(CGColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
