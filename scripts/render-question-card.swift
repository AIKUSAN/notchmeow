import AppKit
import SwiftUI

// Draws the question card of the island (QuestionView, in IslandViewContent.swift) into a PNG without launching NotchMeow: the card's own SwiftUI view in a window that is never shown, on the
// app's own AppState with a made-up AskUserQuestion in it, inside a black island of the size `islandSize` gives that question (so a card with option descriptions is as tall as the app makes it).
//   bash scripts/render-question-card.sh --out question-card.png [--scale 2] [--plain]
// `--plain` draws a question with no option descriptions: the card as it always was (160 pt, chips). Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift.

@main
struct RenderQuestionCard {
    @MainActor static func main() {
        var out = "question-card.png", scale = 2.0, plain = false
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            case "--plain": plain = true
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        let options: [[String: Any]] = plain
            ? [["label": "Postgres"], ["label": "Meilisearch"], ["label": "Algolia"]]
            : [["label": "Postgres full-text", "description": "Built in, nothing new to run. Good enough up to a few hundred thousand rows."],
               ["label": "Meilisearch", "description": "A small separate server with typo tolerance and instant results. One more service to keep running."],
               ["label": "Algolia", "description": "Hosted and fast, priced per request. The least to operate and the most to pay."]]
        let input: [String: Any] = ["questions": [["question": "Which search engine should the new catalogue page use, given that the data fits on one machine and the team is two people?",
                                                   "header": "Search", "options": options, "multiSelect": false]]]
        _ = NSApplication.shared
        let state = AppState.shared
        let task = AgentTask(id: "integration_claude", name: "Claude Code", color: "#E07950", state: .question, steps: [], source: .claudeCode)
        state.tasks = [task]
        state.focusId = task.id
        state.pendingQuestion = AskQuestion.parse(toolInput: input)

        let (islandW, islandH) = islandSize(mode: .expanded, view: .question)
        let island = ZStack(alignment: .topLeading) {
            Color.black
            QuestionView(state: state).frame(width: Double(islandW) - 20, height: Double(islandH) - 62).offset(x: 10, y: 42)
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
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { FileHandle.standardError.write(Data("cannot write \(out)\n".utf8)); exit(1) }
        print("wrote \(out) (island \(Int(islandW)) x \(Int(islandH)) pt, \(plain ? "no descriptions" : "with descriptions"))")
        // The tool's own AppState saved a few defaults into the tool's domain: the .sh deletes them.
    }
}
