import AppKit
import SwiftUI

// Draws the approval card (ApprovalView, in IslandViewContent.swift) into a PNG without launching NotchMeow: the card's own SwiftUI view goes into a window that is never shown, on
// the app's own AppState with a made-up Claude Code request in it, and the big cat is drawn beside it with the real renderer, in the place the island puts it (`botPosition`). The
// island is a mock around them: a black shape of the expanded size (`islandSize`) with the card where IslandContentView puts it (10 pt in, 42 pt down, 98 pt high), and no header.
//   bash scripts/render-approval-card.sh --out approval-card.png [--scale 2] [--command "npm test"] [--line "Runs the project's own test or build script."] [--risk high] [--explain]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift, and runs in a home folder of its own.

@main
struct RenderApprovalCard {
    final class Clock { var t = 0.0 }

    /// The big cat in `state`, 1.2 s into it on a fake clock, drawn `d` across at (cx, cy) with its badge and the agent's colour.
    @MainActor static func bigCat(_ cg: CGContext, coat: String, state: CatState, colour: String, cx: Double, cy: Double, d: Double) {
        let clock = Clock(), rng = CatRNG(seed: 3), preset = CatPresets.byID(coat)
        let e = CatEngine(preset, mini: false, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(motion: "playful"), quiet: true, state: state)
        func place() { let L = CatGeometry.layout(preset, e.s, cx: 0, cy: 0, D: d); e.base = L.base; e.mouthPoint = L.mouth }
        place()
        for _ in 0..<72 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60); place() }
        e.collar = CatRules.bigCatCollar(colour: colour, state: state)
        CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: cx, cy: cy, D: d, CatDrawOptions(badge: true))
    }

    @MainActor static func main() {
        var out = "approval-card.png", scale = 2.0, command = "npm test", line = "", risk = "", explain = false
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            case "--command": command = it.next() ?? command
            case "--line": line = it.next() ?? line
            case "--risk": risk = it.next() ?? risk
            case "--explain": explain = true   // the risk and the line the real rules give this command, for a project at /Users/me/proj
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        if explain {
            let why = SidekickExplain.explain(agent: "integration_claude", tool: "Bash", input: ["command": command], cwd: "/Users/me/proj", home: "/Users/me")
            risk = why.risk; line = why.line
        }
        _ = NSApplication.shared
        let state = AppState.shared
        let task = AgentTask(id: "integration_claude", name: "Claude Code", color: "#E07950", state: .approval, steps: [], source: .claudeCode)
        state.tasks = [task]
        state.focusId = task.id
        state.pendingApproval = ApprovalInfo(sessionId: "render", tool: "Bash", command: command, inputKey: "", pillId: task.id, risk: risk, line: line)

        let (islandW, islandH) = islandSize(mode: .expanded, view: .approval)
        let (botX, botY, botD, _) = botPosition(mode: .expanded, view: .approval, islandW: islandW, islandH: islandH, uploadProgress: 0)
        let island = ZStack(alignment: .topLeading) {
            Color.black
            ApprovalView(state: state).frame(width: Double(islandW) - 20, height: 98).offset(x: 10, y: 42)
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
        // A bitmap of our own, so the scale is the one asked for and not the screen's.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((Double(islandW) * scale).rounded()), pixelsHigh: Int((Double(islandH) * scale).rounded()), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let shot = rep.cgImage else { FileHandle.standardError.write(Data("no bitmap\n".utf8)); exit(1) }

        // The page's dark with 16 pt around the island (its top edge is the top of the screen, so no margin there), then the card, then the cat.
        let margin = 16.0, W = Double(islandW) + 2 * margin, H = Double(islandH) + margin
        guard let cg = CGContext(data: nil, width: Int((W * scale).rounded()), height: Int((H * scale).rounded()), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(CGColor(srgbRed: 0.059, green: 0.063, blue: 0.071, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: W * scale, height: H * scale))
        cg.draw(shot, in: CGRect(x: margin * scale, y: margin * scale, width: Double(islandW) * scale, height: Double(islandH) * scale))
        cg.translateBy(x: 0, y: H * scale)
        cg.scaleBy(x: scale, y: -scale)
        bigCat(cg, coat: "shrimpy", state: .approval, colour: task.color, cx: margin + Double(botX), cy: Double(botY), d: Double(botD))
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
