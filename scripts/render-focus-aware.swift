import AppKit
import SwiftUI

// Draws focus awareness's pictures (the amber dot, the compact dots and the note) into one PNG, without launching NotchMeow: the app's own views on the app's own AppState,
// with marks recorded as a stepped-back request would record them, on four labelled rows:
//   1. the agent pills: Claude Code with a live mark (the dot), Gemini with a live mark and an approval badge (the badge only), Cursor with a live mark and a waiting card (no dot), Codex plain;
//   2. the compact notch, fed row 1's state: the mini grid (Gemini badged, Cursor waiting: no dots) and the compact big cat's dot on Claude Code, on a 240 x 32 strip (a grey stand-in for the cat);
//   3. the Claude Code card (IntegrationCardView, 322 x 98) with a mark "Waiting in iTerm: Edits" under the ticker;
//   4. a tagged agent's card (OverviewView, 640 x 98, Gemini) with a mark "Waiting in Ghostty: Runs" under the ticker;
//   5. and 6. the overview in Two cats mode under the owner's rule (2026-10-22): while a mark lives the note takes cat 2's line, unless that line is a waiting card.
//      Row 5 has cat 2 waiting on a card (its line stays, no note); row 6 has cat 2 idle (the note takes its line). Both are OverviewView itself, one state each.
//   bash scripts/render-focus-aware.sh --out focus-aware.png [--scale 2]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift.

@main
struct RenderFocusAware {
    @MainActor static func main() {
        var out = "focus-aware.png", scale = 2.0
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
        let now = FocusAwareApp.now()
        func def(_ id: String) -> PillDefinition { PillCatalog.definition(for: id)! }
        func task(_ id: String, _ state: BotState, steps: [String] = [], badge: PillBadge? = nil) -> AgentTask {
            let d = def(id)
            return AgentTask(id: d.id, name: d.id == "integration_claude" ? "Claude Code" : d.name, color: d.color, state: state, steps: steps,
                             source: id == "integration_claude" ? .claudeCode : .agent, isIntegration: id == "integration_claude", pillBadge: badge)
        }
        let claudeSteps = ["Reads 3 files", "Runs the tests"]
        func marks() {
            state.focusMarks = FocusAware.Marks()
            state.focusMarks.record(.init(sessionId: "S-claude", pillId: "integration_claude", host: "iTerm", kind: .permission, words: "Edits", at: now))
            state.focusMarks.record(.init(sessionId: "S-gemini", pillId: "agent_gemini", host: "Ghostty", kind: .permission, words: "Runs", at: now))
            state.focusMarks.record(.init(sessionId: "S-cursor", pillId: "agent_cursor", host: "Cursor", kind: .permission, words: "Edits", at: now))
        }

        // Row 1: the pills. Gemini carries the approval badge (the badge wins: no dot); Cursor carries a waiting card (no dot).
        marks()
        state.focusId = "integration_claude"
        state.tasks = [task("integration_claude", .working, steps: claudeSteps), task("agent_gemini", .approval, badge: .approval),
                       task("agent_cursor", .working), task("agent_codex", .idle)]
        state.pendingApproval = ApprovalInfo(sessionId: "S-cursor", tool: "Bash", command: "", inputKey: "", pillId: "agent_cursor")
        let pills = HStack(spacing: 8) {
            ForEach(state.tasks, id: \.id) { t in
                AgentPill(task: t, cat: "shrimpy", state: state, swapping: .constant(false)) {}
                    .frame(width: 134)
            }
        }
        .padding(14)
        let row1 = snapshot(pills, width: 620, height: 72, scale: scale)

        // Row 2: the compact notch, fed the same state as row 1 (no reassignment): Gemini keeps its approval badge and Cursor its waiting card, so neither gets a dot
        // in the grid; the only dot is Claude Code's live mark, on the big cat.
        let strip = ZStack(alignment: .topLeading) {
            Circle().stroke(Color(hex: "#3A3F48"), lineWidth: 1).frame(width: 20, height: 20).position(x: CGFloat(CatIslandLayout.compactX(.one)[0]), y: 16)
            CompactMiniGrid(state: state)
                .scaleEffect(IslandRestingLayout(width: 240, height: 32).miniGridScale)
                .position(x: 240 - 40, y: 16)
            FocusWaitCompactDots(state: state, islandW: 240, islandH: 32)
        }
        .frame(width: 240, height: 32, alignment: .topLeading)
        .background(Color.black)
        let row2 = snapshot(strip, width: 240, height: 32, scale: scale)

        // Row 3: the Claude Code card, the note under its ticker.
        state.tasks = [task("integration_claude", .working, steps: claudeSteps)]
        let claudeCard = IntegrationCardView(task: state.tasks[0], showingDetail: .constant(false))
            .frame(width: 322, height: 98, alignment: .topLeading)
            .background(Color.black)
        let row3 = snapshot(claudeCard, width: 322, height: 98, scale: scale)

        // Row 4: a tagged agent's card (Gemini is not an integration), the note under its ticker.
        state.tasks = [task("agent_gemini", .working, steps: ["Reads the repository", "Runs the build"])]
        state.focusId = "agent_gemini"
        let overview = OverviewView(state: state)
            .frame(width: 640, height: 98, alignment: .topLeading)
            .background(Color.black)
        let row4 = snapshot(overview, width: 640, height: 98, scale: scale)

        // Rows 5 and 6: the overview in Two cats mode, Gemini focused with the Ghostty mark, cat 2 (Codex) with its line. The owner's rule: row 5 has cat 2 waiting on a
        // card, so its line stays and no note is drawn there; row 6 has cat 2 idle (working, no card), so the note takes its line.
        CatSettingsStore.shared.setDisplayMode(.two)
        state.focusId = "agent_gemini"
        let ghostty = FocusAware.Mark(sessionId: "S-gemini", pillId: "agent_gemini", host: "Ghostty", kind: .permission, words: "Runs", at: now)
        let geminiSteps = ["Reads the repository", "Runs the build"]
        state.focusMarks = FocusAware.Marks()
        state.focusMarks.record(ghostty)
        state.tasks = [task("agent_gemini", .working, steps: geminiSteps), task("agent_codex", .approval)]
        state.pendingApproval = ApprovalInfo(sessionId: "S-codex", tool: "Bash", command: "", inputKey: "", pillId: "agent_codex")
        let optionWaiting = OverviewView(state: state).frame(width: 640, height: 98, alignment: .topLeading).background(Color.black)
        let row5 = snapshot(optionWaiting, width: 640, height: 98, scale: scale)
        state.tasks = [task("agent_gemini", .working, steps: geminiSteps), task("agent_codex", .working)]
        state.pendingApproval = nil
        let optionIdle = OverviewView(state: state).frame(width: 640, height: 98, alignment: .topLeading).background(Color.black)
        let row6 = snapshot(optionIdle, width: 640, height: 98, scale: scale)

        let rows: [(String, NSBitmapImageRep?)] = [
            ("1. Agent pills: Claude Code dotted, Gemini badged (no dot), Cursor waiting (no dot), Codex plain", row1),
            ("2. Compact notch: the big cat's dot (Claude Code); Gemini (badged) and Cursor (waiting) get none", row2),
            ("3. Claude Code card: \"Waiting in iTerm: Edits\" under the ticker", row3),
            ("4. Tagged agent card (Gemini): \"Waiting in Ghostty: Runs\" under the ticker", row4),
            ("5. Cat 2 waiting (Codex's card): its line stays, no note is drawn (owner's rule)", row5),
            ("6. Cat 2 idle (Codex working): the note replaces its line (owner's rule)", row6),
        ]
        guard compose(rows, out: out, scale: scale) else { FileHandle.standardError.write(Data("cannot write \(out)\n".utf8)); exit(1) }
        print("wrote \(out)")
    }

    /// One view drawn into a bitmap of its own size, as the app shows it: dark appearance, one run-loop turn for the layout.
    @MainActor static func snapshot<V: View>(_ view: V, width: CGFloat, height: CGFloat, scale: Double) -> NSBitmapImageRep? {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((width * scale).rounded()), pixelsHigh: Int((height * scale).rounded()), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: width, height: height)
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    /// The rows one under another on black, each under its label, into one PNG.
    @MainActor static func compose(_ rows: [(String, NSBitmapImageRep?)], out: String, scale: Double) -> Bool {
        let pad: CGFloat = 16, labelH: CGFloat = 18
        let width = max(rows.compactMap { $0.1?.size.width }.max() ?? 0, 620) + pad * 2
        let height = rows.reduce(pad) { acc, r in acc + labelH + (r.1?.size.height ?? 0) + pad }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((width * scale).rounded()), pixelsHigh: Int((height * scale).rounded()), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = NSSize(width: width, height: height)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        var y = height - pad
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1)]
        for (label, image) in rows {
            y -= labelH
            (label as NSString).draw(at: NSPoint(x: pad, y: y + 2), withAttributes: labelAttrs)
            guard let image else { y -= pad; continue }
            y -= image.size.height
            let img = NSImage(size: image.size)
            img.addRepresentation(image)
            img.draw(in: NSRect(x: pad, y: y, width: image.size.width, height: image.size.height))
            y -= pad
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { return false }
        return true
    }
}
