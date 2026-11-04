import AppKit
import SwiftUI

// Draws the link's pictures (sub-project G2) without launching NotchMeow: the app's own SwiftUI views (LinkViews.swift, and the shelf bar's "To a device" button) go through ImageRenderer into PNGs.
// Run it through scripts/render-link.sh:  bash scripts/render-link.sh --cards --out DIR   |   --devices --out DIR   |   --shelf --out DIR
// LinkViews.swift uses the island's CardBackground and buttons (IslandViewContent.swift), so the .sh compiles every file of the app but NotchBuddyApp.swift, as render-approval-card.sh does.

enum Shot {
    static let scale: CGFloat = 2

    /// A view with AppKit-backed controls (GroupBox, Toggle, TextField, Button): drawn through a hosting view, which ImageRenderer cannot do.
    @MainActor static func saveHosted<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        print("wrote \(url.path)")
    }

    @MainActor static func save<V: View>(_ view: V, to url: URL) {
        let r = ImageRenderer(content: view)
        r.scale = scale
        r.isOpaque = true
        guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("could not draw \(url.lastPathComponent)\n".utf8)); exit(1)
        }
        try! png.write(to: url)
        print("wrote \(url.path)")
    }
}

/// The island around a card, as the island puts it: black, the card 10 pt in and 42 down, 98 high, and a round stand-in where the cat is (the cat needs the engine; the card is what is under test).
struct IslandAround<Content: View>: View {
    let caption: String
    let content: Content
    init(_ caption: String, @ViewBuilder content: () -> Content) { self.caption = caption; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.85))
            ZStack(alignment: .topLeading) {
                Color.black
                content.frame(width: 620, height: 98).offset(x: 10, y: 42)
                Circle().fill(Color(hex: "#C9A27E")).frame(width: 56, height: 56).offset(x: 62 - 28, y: 96 - 28)
            }
            .frame(width: 640, height: 160, alignment: .topLeading)
            .foregroundColor(Color(hex: "#F5F6F8"))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: IslandConst.expandedCorner, bottomTrailingRadius: IslandConst.expandedCorner))
        }
    }
}

struct CardsSheet: View {
    static let offer = LinkOffer(transferId: String(repeating: "a1", count: 16), name: "Quarterly report.pdf", size: 2_400_000, peerId: String(repeating: "e1", count: 16), peerName: "Desk PC")
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IslandAround("Pairing: this Mac and Desk PC show the same six digits") { LinkCardView(card: .pair(code: "483291", peer: "Desk PC", answered: false)) }
            IslandAround("Pairing: this user answered, waiting for the other machine") { LinkCardView(card: .pair(code: "483291", peer: "Desk PC", answered: true)) }
            IslandAround("Accept card: nothing happens until a click") { LinkCardView(card: .offer(Self.offer)) }
            IslandAround("Receiving") { LinkCardView(card: .receiving(Self.offer, received: 1_080_000)) }
            IslandAround("Done") { LinkCardView(card: .result(title: "Received", detail: "Saved as Quarterly report.pdf in Downloads/NotchMeow.", file: URL(fileURLWithPath: "/tmp/x"))) }
            IslandAround("The other side stopped") { LinkCardView(card: .result(title: "Transfer stopped", detail: "The connection ended before the file was complete. Nothing was saved.", file: nil)) }
        }
        .padding(16).frame(width: 672, alignment: .topLeading).background(Color(red: 0.30, green: 0.31, blue: 0.34))
    }
}

struct DevicesSheet: View {
    static let rows: [LinkDirectory.Row] = [.init(id: "1", name: "Desk PC", state: .pairedOnline), .init(id: "2", name: "Old laptop", state: .pairedOffline), .init(id: "3", name: "Studio Mac", state: .available)]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Off (the default): nothing listens, nothing is announced").font(.system(size: 12, weight: .semibold))
            DevicesSettingsView(visible: false, deviceName: "Sam's MacBook Pro", listening: false, problem: nil, note: nil, rows: [])
            Divider()
            Text("On, with machines").font(.system(size: 12, weight: .semibold))
            DevicesSettingsView(visible: true, deviceName: "Sam's MacBook Pro", listening: true, problem: nil, note: "Wait 30 seconds before trying again.", rows: Self.rows)
            Divider()
            Text("On, nothing found, and the listener could not start").font(.system(size: 12, weight: .semibold))
            DevicesSettingsView(visible: true, deviceName: "Sam's MacBook Pro", listening: false, problem: "This Mac can't listen right now. Check System Settings, Privacy & Security, Local Network.", note: nil, rows: [])
        }
        .padding(20).frame(width: 640, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark)
    }
}

@MainActor
struct ShelfBarSheet: View {
    /// The "To a device" machines are open, in place of the buttons (the chips' picture: four paired machines, one with a long name, two of them off).
    var chips = false
    var body: some View {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("render-link-\(UUID().uuidString)", isDirectory: true)
        let _ = try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Quarterly report.pdf"); let _ = try? Data(count: 2_400_000).write(to: file)
        let model = ShelfModel(store: ShelfStore(support: dir.appendingPathComponent("support"), scoped: false))
        let _ = model.add([.file(file)])
        let _ = model.toggle(model.items[0].id)
        let devices = chips
            ? [ShelfDeviceChoice(id: "1", name: "Desk PC", online: true), ShelfDeviceChoice(id: "2", name: "Sam's MacBook Pro with a very long name", online: true),
               ShelfDeviceChoice(id: "3", name: "Studio Mac", online: false), ShelfDeviceChoice(id: "4", name: "Old laptop", online: false)]
            : [ShelfDeviceChoice(id: "1", name: "Desk PC", online: true), ShelfDeviceChoice(id: "2", name: "Old laptop", online: false)]
        let buttons = ShelfButtons(ask: { _ in }, show: { _ in }, send: { _ in }, airDrop: { _ in }, showDevicesButton: true,
                                   devices: devices, deviceLine: "Sending Quarterly report.pdf to Desk PC, 45 %", cancelSend: {})
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22).fill(Color.black).frame(width: 640, height: 176)
            RoundedRectangle(cornerRadius: 20).fill(Color(hex: "#141518")).frame(width: 620, height: 124).offset(x: 10, y: 42)
            ShelfContent(model: model, picture: true, buttons: buttons, startsChoosing: chips).frame(width: 620, height: 124, alignment: .leading).offset(x: 10, y: 42)
        }.frame(width: 640, height: 176, alignment: .topLeading).padding(16).background(Color(red: 0.30, green: 0.31, blue: 0.34))
    }
}

@main
struct RenderLink {
    @MainActor static func main() {
        var out = ".", cards = false, devices = false, shelf = false
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--cards": cards = true
            case "--devices": devices = true
            case "--shelf": shelf = true
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if cards { Shot.save(CardsSheet(), to: dir.appendingPathComponent("link-cards.png")) }
        if devices { Shot.saveHosted(DevicesSheet(), size: CGSize(width: 640, height: 1580), to: dir.appendingPathComponent("link-devices.png")) }
        if shelf {
            Shot.save(ShelfBarSheet(), to: dir.appendingPathComponent("link-shelf-bar.png"))
            Shot.save(ShelfBarSheet(chips: true), to: dir.appendingPathComponent("link-shelf-chips.png"))
        }
        if !cards && !devices && !shelf { print("usage: render-link.sh --cards|--devices|--shelf --out DIR"); exit(2) }
    }
}
