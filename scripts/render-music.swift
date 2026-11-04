import AppKit
import SwiftUI

// Draws the music pill's checkpoint rows into one PNG without launching NotchMeow or any music app: MusicCardView (the card) and MusicPill (the pill), each drawn right after its state is set,
// on black, top to bottom:
//   1. the card, Apple Music playing "Blue in Green" by "Miles Davis";
//   2. the card, Spotify paused "Sunday Morning" by "Maroon 5" (Apple Music stopped first);
//   3. the pill (134 pt) for row 2's state, not hovered;
//   4. the pill with nothing shown (Spotify stopped: the pill reads "Music");
//   5. the card after Spotify's refusal (Spotify playing, noteDenied).
// The states come through MusicController.receive and noteDenied, the same calls the notifications and the script refusals make: nothing is sent to Music or Spotify.
//   bash scripts/render-music.sh --out music.png [--scale 2]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift.

@main
struct RenderMusic {
    @MainActor static func main() {
        var out = "music.png", scale = 2.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let state = AppState.shared
        guard let def = PillCatalog.definition(for: "integration_music") else {
            FileHandle.standardError.write(Data("the music pill is not in the catalog\n".utf8)); exit(1)
        }
        state.tasks = [AgentTask(id: def.id, name: def.name, color: def.color, state: .idle, steps: [], source: def.source, isIntegration: true)]
        state.activeIntegrations.insert("integration_music")
        let music = MusicController.shared
        let pillTask = { AppState.shared.tasks.first { $0.id == "integration_music" } ?? state.tasks[0] }

        var rows: [NSBitmapImageRep] = []

        // 1. Apple Music playing
        music.receive(.appleMusic, playerState: "Playing", name: "Blue in Green", artist: "Miles Davis", album: "Kind of Blue")
        rows.append(draw(MusicCardView().frame(width: 360, alignment: .topLeading), scale: scale))

        // 2. Apple Music stopped, Spotify paused
        music.receive(.appleMusic, playerState: "Stopped", name: nil, artist: nil, album: nil)
        music.receive(.spotify, playerState: "Paused", name: "Sunday Morning", artist: "Maroon 5", album: "Songs About Jane")
        rows.append(draw(MusicCardView().frame(width: 360, alignment: .topLeading), scale: scale))

        // 3. The pill for row 2's state, not hovered
        rows.append(draw(MusicPill(task: pillTask(), cat: "shrimpy", state: state, swapping: .constant(false)) {}.frame(width: 134), scale: scale))

        // 4. Spotify stopped: nothing shown, the pill reads its catalog name
        music.receive(.spotify, playerState: "Stopped", name: nil, artist: nil, album: nil)
        rows.append(draw(MusicPill(task: pillTask(), cat: "shrimpy", state: state, swapping: .constant(false)) {}.frame(width: 134), scale: scale))

        // 5. Spotify playing, then its refusal
        music.receive(.spotify, playerState: "Playing", name: "Sunday Morning", artist: "Maroon 5", album: "Songs About Jane")
        music.noteDenied(.spotify)
        rows.append(draw(MusicCardView().frame(width: 360, alignment: .topLeading), scale: scale))

        guard let picture = stack(rows, scale: scale),
              let png = picture.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { FileHandle.standardError.write(Data("cannot write \(out)\n".utf8)); exit(1) }
        print("wrote \(out) (\(rows.count) rows, \(scale)x)")
        // The tool's own AppState and defaults live in the tool's domain: the .sh deletes them.
    }

    /// One row: the view on black, drawn once its state is set (the run loop lets SwiftUI lay it out first).
    @MainActor static func draw<V: View>(_ view: V, scale: Double) -> NSBitmapImageRep {
        let root = view
            .padding(14)
            .background(Color.black)
            .foregroundColor(Color(hex: "#F5F6F8"))
            .fixedSize()
        let host = NSHostingView(rootView: root)
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
        return rep
    }

    /// The rows one under another, on black, the first at the top.
    @MainActor static func stack(_ rows: [NSBitmapImageRep], scale: Double) -> NSBitmapImageRep? {
        let width = rows.map(\.size.width).max() ?? 0
        let height = rows.map(\.size.height).reduce(0, +)
        guard let picture = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((width * scale).rounded()), pixelsHigh: Int((height * scale).rounded()), bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: picture) else { return nil }
        picture.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The context counts pixels; the rows and the fill below are in points.
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        var top = height
        for row in rows {
            top -= row.size.height
            row.draw(in: NSRect(x: 0, y: top, width: row.size.width, height: row.size.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        return picture
    }
}
