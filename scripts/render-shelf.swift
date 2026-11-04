import AppKit
import SwiftUI

// Draws the shelf (sub-project G1) without launching NotchMeow: the app's own SwiftUI views go through ImageRenderer into PNGs, and the checks that need pixels run on the same bitmaps.
// Run it through scripts/render-shelf.sh:  bash scripts/render-shelf.sh --drop --out DIR   |   --ask-check

/// The same helper the app has in IslandRootView.swift (that file needs the whole app; the sheets do not).
extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        self.init(red: Double((val >> 16) & 0xFF) / 255, green: Double((val >> 8) & 0xFF) / 255, blue: Double(val & 0xFF) / 255)
    }
}

enum Shot {
    static let scale: CGFloat = 2

    @MainActor static func image<V: View>(_ view: V, opaque: Bool = true) -> CGImage? {
        let r = ImageRenderer(content: view)
        r.scale = scale
        r.isOpaque = opaque
        return r.cgImage
    }

    @MainActor static func save<V: View>(_ view: V, to url: URL) {
        guard let cg = image(view), let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("could not draw \(url.lastPathComponent)\n".utf8)); exit(1)
        }
        try! png.write(to: url)
        print("wrote \(url.path)")
    }

    /// RGBA bytes of an image, premultiplied, row by row from the top.
    static func pixels(_ cg: CGImage) -> (w: Int, h: Int, bytes: [UInt8]) {
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { p in
            let c = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (w, h, bytes)
    }
}

/// A stand-in for the upload canvas's card (the real canvas needs the cat engine): the same card, border, text and chips at the same places, so the layer's reach can be judged by eye.
/// The proof that the Ask half is untouched is `--ask-check` and `scripts/check-ask-unchanged.sh`, not this picture.
struct MockAskCanvas: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.black)
            RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.051, green: 0.055, blue: 0.063)).frame(width: 620, height: 124).offset(x: 10, y: 42)
            RoundedRectangle(cornerRadius: 19.5).strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).frame(width: 618.5, height: 122.5).offset(x: 10.75, y: 42.75)
            Text("Drop your files here").font(.system(size: 13, weight: .medium)).foregroundColor(Color(hex: "#D5D7DB")).offset(x: 196, y: 82)
            ForEach(Array(["PDF", "Images", "Code", "Docs"].enumerated()), id: \.offset) { i, chip in
                let x = [196.0, 237.5, 298.5, 346.5][i], w = Double(chip.count) * 6.5 + 16
                Text(chip).font(.system(size: 11, weight: .medium)).foregroundColor(Color(hex: "#B9BDC4")).frame(width: w, height: 18).background(Capsule().fill(Color.white.opacity(0.07))).offset(x: x, y: 103)
            }
            Image(systemName: "pawprint.fill").font(.system(size: 30)).foregroundColor(Color(hex: "#8E939C")).offset(x: 140, y: 88)
        }
        .frame(width: 640, height: 176, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct DropSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([DropHalf.ask, DropHalf.shelf], id: \.rawValue) { half in
                Text(half == .ask ? "The pointer is over the left half (Ask)" : "The pointer is over the right half (Shelf)").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                ZStack(alignment: .topLeading) {
                    MockAskCanvas()
                    ShelfDropLayer(half: half)
                }.frame(width: 640, height: 176)
            }
        }
        .padding(16)
        .frame(width: 672, height: 440, alignment: .topLeading)
        .background(Color(red: 0.30, green: 0.31, blue: 0.34))
    }
}

/// A shelf model on a store in a temp folder, filled with real files so the sizes and icons are the system's.
@MainActor
enum DemoShelf {
    /// Under the folder render-shelf.sh made for this run (NM_LOG_DIR's parent), which its trap removes: nothing is left in the system's temp folder.
    static var scratch: URL { ProcessInfo.processInfo.environment["NM_LOG_DIR"].map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? FileManager.default.temporaryDirectory }

    static func model(files: [(name: String, bytes: Int, folder: Bool)], copy: [String] = [], selected: [String] = [], missing: [String] = [], dropExtra: Int = 0) -> ShelfModel {
        let root = scratch.appendingPathComponent("shelf-\(UUID().uuidString)", isDirectory: true)
        let originals = root.appendingPathComponent("originals", isDirectory: true)
        try! FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        nonisolated(unsafe) var tick: Int64 = 0
        let store = ShelfStore(support: root.appendingPathComponent("support"), scoped: false, now: { tick += 1000; return tick }, newID: { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() })
        let model = ShelfModel(store: store)
        var made: [URL] = []
        for f in files {
            let u = originals.appendingPathComponent(f.name)
            if f.folder { try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true) } else { try! Data(count: f.bytes).write(to: u) }
            made.append(u)
        }
        if !made.isEmpty { model.add(made.map { .file($0) }) }   // an empty drop now carries a note; the empty shelf's picture is of a shelf nobody dropped on
        for c in copy {
            let u = originals.appendingPathComponent(c)
            try! Data(count: 48_000).write(to: u)
            model.add([.temporary(u)])
        }
        for name in missing { try? FileManager.default.removeItem(at: originals.appendingPathComponent(name)) }
        model.refresh()
        for item in model.items where selected.contains(item.name) { model.toggle(item.id) }
        if dropExtra > 0 {
            var extra: [ShelfIncoming] = []
            for n in 0..<dropExtra { let u = originals.appendingPathComponent("extra-\(n).txt"); try! Data(count: 10).write(to: u); extra.append(.file(u)) }
            model.add(extra)
        }
        return model
    }
}

/// The shelf view in the island: black island, the card, the cat's place and the content. The header's tabs are not drawn.
struct IslandMock: View {
    let model: ShelfModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22).fill(Color.black).frame(width: 640, height: 176)
            RoundedRectangle(cornerRadius: 20).fill(Color(hex: "#141518")).frame(width: 620, height: 124).offset(x: 10, y: 42)
            Circle().fill(Color(hex: "#C9A27E")).frame(width: 46, height: 46).offset(x: 54 - 23, y: 104 - 23)
            ShelfContent(model: model, picture: true).frame(width: 620, height: 124, alignment: .leading).offset(x: 10, y: 42)
        }
        .frame(width: 640, height: 176, alignment: .topLeading)
    }
}

struct ViewSheet: View {
    @MainActor static func make() -> ViewSheet {
        let some: [(name: String, bytes: Int, folder: Bool)] = [("Quarterly report.pdf", 2_400_000, false), ("Screenshot 2026-10-14 at 09.41.png", 880_000, false), ("Project files", 0, true), ("notes.txt", 1_200, false),
                                                                 ("a-very-long-file-name-that-has-to-be-cut-short.md", 6_000, false), ("demo.mov", 48_000_000, false), ("deleted-since.zip", 3_000_000, false)]
        let many = (0..<30).map { (name: "file-\($0).txt", bytes: 1_000 * ($0 + 1), folder: false) }
        return ViewSheet(empty: DemoShelf.model(files: []),
                         some: DemoShelf.model(files: some, copy: ["Image.png"], selected: ["Quarterly report.pdf", "Project files"], missing: ["deleted-since.zip"]),
                         full: DemoShelf.model(files: many, dropExtra: 2))
    }
    let empty: ShelfModel, some: ShelfModel, full: ShelfModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array([("An empty shelf", empty), ("Seven files and an image copy: two selected, one gone missing", some), ("A full shelf, after two more files were dropped on it", full)].enumerated()), id: \.offset) { _, row in
                Text(row.0).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                IslandMock(model: row.1)
            }
        }
        .padding(16)
        .frame(width: 672, height: 3 * 176 + 3 * 24 + 16 + 8 * 2, alignment: .topLeading)
        .background(Color(red: 0.30, green: 0.31, blue: 0.34))
    }
}

/// The compact island, 344 x 32: the black strip, the notch, the grid of agent cats beside it (cells 16 pt apart, 12 pt wide, centred 40 pt in) and the shelf's badge at its right end. `faded` is the wing
/// stepping aside for the pointer: the grid and the badge fade together. The cats are plain discs here: the strip is about where the badge sits, not about the cats.
struct CompactMock: View {
    let count: Int
    let faded: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(red: 0.30, green: 0.31, blue: 0.34)).frame(width: 440, height: 32)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(Color.black).frame(width: 344, height: 32)
                Rectangle().fill(Color(white: 0.09)).frame(width: 184, height: 32).offset(x: 80)
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill([Color(hex: "#E07950"), Color(hex: "#34D399"), Color(hex: "#60A5FA")][i]).frame(width: 12, height: 12)
                            .position(x: 344 - 40 + (i % 2 == 1 ? 8 : -8), y: 16 + (i < 2 ? -8 : 8))
                    }
                    if ShelfBadge.isShown(compact: true, count: count, greetingTail: false) {
                        ShelfBadgeView(count: count, height: 32).position(ShelfBadge.center(islandWidth: 344, height: 32))
                    }
                }
                .frame(width: 344, height: 32)
                .opacity(faded ? 0 : 1)
            }
            .offset(x: 48)
        }
        .frame(width: 440, height: 32, alignment: .topLeading)
    }
}

struct BadgeSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array([("At rest, three files on the shelf", 3, false), ("The pointer is over the wing: the grid and the badge fade together", 3, true), ("An empty shelf: no badge", 0, false), ("The shelf is full", 30, false)].enumerated()), id: \.offset) { _, row in
                Text(row.0).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                CompactMock(count: row.1, faded: row.2)
            }
        }
        .padding(16)
        .frame(width: 472, height: 4 * 64 + 32, alignment: .topLeading)
        .background(Color(red: 0.16, green: 0.17, blue: 0.19))
    }
}

@main
struct RenderShelf {
    /// The Ask half is the canvas as it ships: the layer draws nothing left of the centre line, in either state. Fails (exit 1) on a single pixel with any alpha at x < 320.
    @MainActor static func askCheck() {
        var bad = 0
        for half in [DropHalf.ask, DropHalf.shelf] {
            guard let cg = Shot.image(ShelfDropLayer(half: half), opaque: false) else { print("✗ could not draw the layer"); exit(1) }
            let p = Shot.pixels(cg)
            let split = Int(320 * Shot.scale)
            var left = 0, right = 0
            for y in 0..<p.h { for x in 0..<p.w where p.bytes[(y * p.w + x) * 4 + 3] != 0 { if x < split { left += 1 } else { right += 1 } } }
            if left == 0 && right > 0 { print("✓ over \(half.rawValue): the layer draws \(right) pixels right of the centre line and none left of it (\(p.w) x \(p.h))") } else { print("✗ over \(half.rawValue): \(left) pixels left of the centre line, \(right) right of it"); bad += 1 }
        }
        if bad > 0 { exit(1) }
    }

    /// The Debug-only panel (ShelfDevPanel.swift) in a window that is never shown: its own SwiftUI view, laid out and drawn by AppKit, with a few of its buttons pressed first. The system controls
    /// (pickers, group boxes) may come out blank in this offscreen bitmap; the shelf, the layer and the badges do not.
    @MainActor static func panel(to url: URL) {
        let host = NSHostingView(rootView: ShelfDevView(root: DemoShelf.scratch.appendingPathComponent("panel-\(UUID().uuidString)", isDirectory: true)))
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 760)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .windowBackgroundColor
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { FileHandle.standardError.write(Data("no bitmap\n".utf8)); exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let shot = rep.cgImage,
              let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(CGColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: url)
        print("wrote \(url.path)")
    }

    @MainActor static func main() {
        var out = ".", modes: [String] = []
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--drop", "--ask-check", "--view", "--badge", "--panel": modes.append(k)
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        if modes.isEmpty { FileHandle.standardError.write(Data("say what to draw: --drop, --view, --badge, --panel, --ask-check\n".utf8)); exit(2) }
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for m in modes {
            switch m {
            case "--ask-check": askCheck()
            case "--drop": Shot.save(DropSheet(), to: dir.appendingPathComponent("shelf-drop.png"))
            case "--view": Shot.save(ViewSheet.make(), to: dir.appendingPathComponent("shelf-view.png"))
            case "--badge": Shot.save(BadgeSheet(), to: dir.appendingPathComponent("shelf-badge.png"))
            case "--panel": panel(to: dir.appendingPathComponent("shelf-panel.png"))
            default: break
            }
        }
    }
}
