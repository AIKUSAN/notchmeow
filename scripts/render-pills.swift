import AppKit
import SwiftUI

// Draws the island's agent pills (AgentPill, in IslandViewContent.swift) into a PNG without launching NotchMeow: the app's own pill view on a black strip, for the Claude Code pill (its label is
// "Claude Code"), Claude Desktop (a session from the Claude desktop app) and two agents for comparison, each with the cat the app gives it.
//   bash scripts/render-pills.sh --out pills.png [--scale 2]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift.

@main
struct RenderPills {
    @MainActor static func main() {
        var out = "pills.png", scale = 2.0
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
        let defs = ["integration_claude", "agent_claude-desktop", "agent_gemini", "agent_cursor"].compactMap { PillCatalog.definition(for: $0) }
        let tasks = defs.map { AgentTask(id: $0.id, name: $0.id == "agent_claude-desktop" ? $0.name : $0.name, color: $0.color, state: .idle, steps: [], source: $0.source) }
        state.tasks = tasks
        let row = HStack(spacing: 8) {
            ForEach(tasks, id: \.id) { task in
                AgentPill(task: task, cat: "shrimpy", state: state, swapping: .constant(false)) {}
                    .frame(width: 134)
            }
        }
        .padding(14)
        .background(Color.black)
        .foregroundColor(Color(hex: "#F5F6F8"))
        let host = NSHostingView(rootView: row.fixedSize())
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
        print("wrote \(out) (\(Int(size.width)) x \(Int(size.height)) pt at \(scale)x): \(tasks.map(\.name).joined(separator: ", "))")
        // The tool's own AppState saved a few defaults into the tool's domain: the .sh deletes them.
    }
}
