import AppKit
import SwiftUI

// Draws Settings → Cat (CatSettingsView.swift) into a PNG without launching NotchMeow: the section's own SwiftUI view goes into a window that is never
// shown, and AppKit lays it out and draws it into a bitmap. It runs on a store of its own (a dictionary and a CatConfig of its own, no UserDefaults), so
// nothing the user saved is read or changed. The previews are live engines, stepped for 1.5 s before the shot. The system controls (pickers, sliders,
// group boxes, buttons) may come out blank in this offscreen bitmap; the cats and the layout do not.
// Run it through scripts/render-cat-settings.sh:
//   bash scripts/render-cat-settings.sh [--out settings.png] [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur] [--collar band]
//                                       [--mode one|perAgent|two] [--pair momo,latte] [--agents] [--outfit santahat]
//   --mode picks the display mode; --pair the two cats of Two cats mode; --agents lists the Display preview's five sample pills (and gives the new ones their coats)
//   as the agents Settings has seen, so "Cats for your agents" has rows.

final class MemoryBacking: CatSettingsBacking {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func allKeys() -> [String] { Array(values.keys) }
}

@main
struct RenderCatSettings {
    @MainActor static func main() {
        var out = "cat-settings.png", height = 1500.0, width = 520.0, character = "momo", preset = "chill", fur = false, collar = "off"
        var mode = "one", pair = "shrimpy,momo", withAgents = false, outfit = "auto"
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--height": height = Double(it.next() ?? "") ?? height
            case "--width": width = Double(it.next() ?? "") ?? width
            case "--character": character = it.next() ?? character
            case "--preset": preset = it.next() ?? preset
            case "--fur": fur = true
            case "--collar": collar = it.next() ?? collar
            case "--mode": mode = it.next() ?? mode
            case "--pair": pair = it.next() ?? pair
            case "--agents": withAgents = true
            case "--outfit": outfit = it.next() ?? outfit
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let store = CatSettingsStore(backing: MemoryBacking(), config: CatConfig())
        store.setCharacter(character)
        store.setPreset(preset, for: character)
        store.setFurLines(fur)
        store.setCollar(collar)
        store.setDisplayMode(CatDisplaySettings.modeOf(mode))
        store.setOutfit(outfit)
        // The app's WardrobeClock writes the resolved outfit into config.outfit (where the previews read it); this render has no clock, so it resolves the same way: Auto for today's date.
        store.config.outfit = Wardrobe.resolve(store.wardrobe.outfit, Wardrobe.today())
        for (slot, cat) in pair.split(separator: ",").map(String.init).enumerated() { store.setPairCat(cat, slot: slot) }
        let agents = withAgents ? CatDisplaySample.pills.filter { CatDisplaySettings.isAgentPill($0.id) }.enumerated().map { CatAgentList.Agent(id: $1.id, name: $1.name, color: $1.color, last: Double(100 - $0 * 10)) } : []
        store.ensureAgentCats(for: agents.map(\.id))
        let host = NSHostingView(rootView: ScrollView { CatSettingsView(store: store, alwaysActive: true, agents: agents).padding(20) }.frame(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .windowBackgroundColor
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))   // SwiftUI lays out, and the previews' engines run for a moment
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
