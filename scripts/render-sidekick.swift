import AppKit
import SwiftUI

// Draws the sidekick's notes (SidekickView, in SidekickView.swift) into a PNG without launching NotchMeow: each note is made by the real engine, driven by a clock by hand and the hook events of a
// made-up session, and its own SwiftUI view goes into a window that is never shown, in a mock of the open island (a black shape of the expanded size with the card where IslandContentView puts it, 10 pt
// in, 42 pt down, 98 pt high, and the big cat beside it, drawn by the real renderer where the island puts it). The three notes the owner sees: the recap after a lock, the nudge for a loop, and the
// nudge for a request nobody is looking at.
//   bash scripts/render-sidekick.sh --out sidekick-notes.png [--scale 2] [--settings-out sidekick-settings.png]
// --settings-out also draws Settings → Sidekick (SidekickSettingsView) on a store of its own, with two kinds muted and a local model "found". The system controls (switches, group boxes, buttons) may
// come out blank in an offscreen bitmap; the text and the layout do not.
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift, and runs in a home folder of its own.

@main
struct RenderSidekick {
    final class Clock { var t = 0.0 }
    /// A settings store on a dictionary: the tool never writes the user's preferences.
    final class DictBacking: CatSettingsBacking {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func removeObject(forKey key: String) { values[key] = nil }
        func allKeys() -> [String] { Array(values.keys) }
    }

    @MainActor static func bigCat(_ cg: CGContext, coat: String, state: CatState, colour: String, cx: Double, cy: Double, d: Double) {
        let clock = Clock(), rng = CatRNG(seed: 3), preset = CatPresets.byID(coat)
        let e = CatEngine(preset, mini: false, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(motion: "playful"), quiet: true, state: state)
        func place() { let L = CatGeometry.layout(preset, e.s, cx: 0, cy: 0, D: d); e.base = L.base; e.mouthPoint = L.mouth }
        place()
        for _ in 0..<72 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60); place() }
        e.collar = CatRules.bigCatCollar(colour: colour, state: state)
        CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: cx, cy: cy, D: d, CatDrawOptions(badge: true))
    }

    static func hook(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var p: [String: Any] = ["hook_event_name": name, "session_id": "render", "cwd": "/Users/me/NotchMeow", "term_program": "vscode"]
        for (k, v) in extra { p[k] = v }
        return p
    }
    static func edit(_ file: String) -> [String: Any] { hook("PostToolUse", ["tool_name": "Edit", "tool_input": ["file_path": "/Users/me/NotchMeow/\(file)", "old_string": "a", "new_string": "b"]]) }

    /// A new engine on a clock by hand: no timer is ever set, and nothing is stored.
    @MainActor static func engine(_ now: Ref) -> SidekickEngine {
        let clock = SidekickClock(now: { now.t }, schedule: { _, _ in {} })
        var env = SidekickEngine.Env(now: { now.t })
        env.canHost = { true }
        return SidekickEngine(store: SidekickStore(backing: DictBacking()), clock: clock, env: env)
    }
    final class Ref { var t = 100_000_000.0 }

    /// The three notes, each shown by its own engine.
    @MainActor static func notes() -> [SidekickEngine] {
        let sec = 1000.0, min = 60_000.0
        // 1. The recap: a lock, an agent that edits three files and finishes while the user is away, and the return.
        let r = Ref(), recap = engine(r)
        recap.feed(payload: hook("SessionStart"))
        recap.presenceEvent(.lock)
        for f in ["SidekickEngine.swift", "SidekickView.swift", "docs/SPEC.md"] { r.t += 20 * sec; recap.feed(payload: edit(f)) }
        for c in ["swift build", "npm test"] { r.t += 20 * sec; recap.feed(payload: hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": c]])) }
        r.t += 20 * sec; recap.feed(payload: hook("Stop"))
        r.t += 3 * min; recap.presenceEvent(.unlock)
        // 2. The loop: the same step four times.
        let l = Ref(), loop = engine(l)
        loop.feed(payload: hook("SessionStart"))
        for _ in 0..<4 { l.t += 2 * sec; loop.feed(payload: hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "swift test"]])) }
        // 3. A request nobody is looking at, a minute on.
        let w = Ref(), waiting = engine(w)
        waiting.feed(payload: hook("SessionStart"))
        waiting.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push origin main"]]))
        w.t += 61 * sec; waiting.envChanged()
        // 4. The busiest recap there is: three agents, each with files, and one more.
        let b = Ref(), busy = engine(b)
        let agents: [(tag: String, project: String)] = [("", "NotchMeow"), ("codex", "site"), ("gemini", "docs"), ("antigravity", "api")]
        for a in agents { busy.feed(payload: hook("SessionStart", a.tag.isEmpty ? [:] : ["nm_agent": a.tag, "session_id": a.tag, "cwd": "/Users/me/\(a.project)"])) }
        busy.presenceEvent(.lock)
        for (i, a) in agents.enumerated() {
            for f in ["index.html", "site.css", "main.js", "README.md"] {
                b.t += 5 * sec
                var extra: [String: Any] = ["tool_name": "Edit", "tool_input": ["file_path": "/Users/me/\(a.project)/\(f)", "old_string": "a", "new_string": "b"]]
                if !a.tag.isEmpty { extra["nm_agent"] = a.tag; extra["session_id"] = a.tag; extra["cwd"] = "/Users/me/\(a.project)" }
                busy.feed(payload: hook("PostToolUse", extra))
            }
            _ = i
        }
        b.t += 3 * min; busy.presenceEvent(.unlock)
        return [recap, loop, waiting, busy]
    }

    @MainActor static func render(_ engine: SidekickEngine, scale: Double) -> CGImage? {
        let state = AppState.shared
        let (islandW, islandH) = islandSize(mode: .expanded, view: .sidekick)
        let (botX, botY, botD, _) = botPosition(mode: .expanded, view: .sidekick, islandW: islandW, islandH: islandH, uploadProgress: 0)
        let island = ZStack(alignment: .topLeading) {
            Color.black
            SidekickView(engine: engine, state: state).frame(width: Double(islandW) - 20, height: 98).offset(x: 10, y: 42)
        }
        .frame(width: islandW, height: islandH, alignment: .topLeading)
        .foregroundColor(Color(hex: "#F5F6F8"))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: IslandConst.expandedCorner, bottomTrailingRadius: IslandConst.expandedCorner))
        let host = NSHostingView(rootView: island)
        host.frame = NSRect(x: 0, y: 0, width: islandW, height: islandH)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((Double(islandW) * scale).rounded()), pixelsHigh: Int((Double(islandH) * scale).rounded()), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let shot = rep.cgImage,
              let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.translateBy(x: 0, y: Double(shot.height))
        cg.scaleBy(x: scale, y: -scale)
        bigCat(cg, coat: "shrimpy", state: .working, colour: "#E07950", cx: Double(botX), cy: Double(botY), d: Double(botD))
        return cg.makeImage()
    }

    @MainActor static func main() {
        var out = "sidekick-notes.png", scale = 2.0, settingsOut = ""
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            case "--settings-out": settingsOut = it.next() ?? settingsOut
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let engines = notes()
        guard engines.allSatisfy({ $0.showing != nil }) else { FileHandle.standardError.write(Data("an engine showed no note\n".utf8)); exit(1) }
        let images = engines.compactMap { render($0, scale: scale) }
        guard images.count == engines.count else { exit(1) }
        // The page's dark with 16 pt around the islands and 12 pt between them.
        let margin = 16.0 * scale, gap = 12.0 * scale
        let W = Double(images[0].width) + 2 * margin, H = images.reduce(margin) { $0 + Double($1.height) + gap }
        guard let cg = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(CGColor(srgbRed: 0.059, green: 0.063, blue: 0.071, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var y = H - margin
        for img in images { y -= Double(img.height); cg.draw(img, in: CGRect(x: margin, y: y, width: Double(img.width), height: Double(img.height))); y -= gap }
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
        if !settingsOut.isEmpty { renderSettings(to: settingsOut) }
    }

    /// Settings → Sidekick as the app draws it: a store on a dictionary with the recap and the waiting nudge muted, and a local model found.
    @MainActor static func renderSettings(to path: String) {
        let store = SidekickStore(backing: DictBacking())
        for k in ["recap", "stuck.waiting"] { store.dismiss(k); store.dismiss(k) }
        let width = 520.0
        let page = SidekickSettingsView(store: store, found: "Local \u{00B7} qwen3.5:2b").padding(20).frame(width: width)
        // The page's own height: the Sidekick tab is as tall as its five cards, so a fixed height would cut them off.
        let height = NSHostingController(rootView: page).sizeThatFits(in: CGSize(width: width, height: 100_000)).height.rounded(.up)
        let host = NSHostingView(rootView: page.frame(width: width, height: height, alignment: .topLeading))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .windowBackgroundColor
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let shot = rep.cgImage,
              let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(CGColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
