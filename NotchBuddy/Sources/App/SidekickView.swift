import SwiftUI

// The island's `.sidekick` view: one note from the sidekick, in the style of the island's other cards (the same card, the cat at the left, a title, the words, the same buttons). It is a row of its own
// (`IslandConst.viewLayouts[.sidekick]`), not the `.note` view, which is the AI error flow. It opens the way a finished task does (`.hookExpand`) and goes by itself (the engine's clock), so it
// never covers a card, the chat or the user's other work, and never opens a window. OK and × are the same thing and count as a dismissal; Not now counts too; Show me brings the agent's app forward
// and does not. It shows words and buttons and nothing else: a note never answers a request.

struct SidekickView: View {
    @ObservedObject var engine: SidekickEngine
    @ObservedObject var state: AppState

    /// The first line of the card.
    static func title(_ kind: String) -> String {
        switch kind {
        case "recap": return "Welcome back"
        case "stuck.loop": return "Going in circles"
        case "stuck.errors": return "Running into errors"
        case "stuck.waiting": return "Waiting for you"
        case "stuck.silent": return "Gone quiet"
        default: return ""
        }
    }

    /// The island is open on this note: the user has seen it.
    private var seen: Bool { state.mode == .expanded && state.view == .sidekick && engine.showing != nil }

    /// A drop on an agent's own cat: the one line it says (copied the path, or why not), with OK and ×. It is the user's own action, so it shows at once and is not a note of the engine's: nothing is counted.
    private func dropLine(_ line: String) -> some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(line)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                PrimaryButton("OK") { SidekickDropApp.endLine(state: state) }
            }
            .padding(.leading, 116)
            .padding(.trailing, 34)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { SidekickDropApp.endLine(state: state) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color(hex: "#5F646D"))
                    .frame(width: 16, height: 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .padding(.top, 8).padding(.trailing, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            if let line = state.sidekickDropLine {
                dropLine(line)
            } else if let note = engine.showing {
                // One sentence gets a title and two lines. A recap of several agents has no title and one line for each agent (the card is 98 pt high: it never grows).
                let rows = note.rows
                VStack(alignment: .leading, spacing: 6) {
                    if rows.count == 1 { Text(Self.title(note.kind)).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")) }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Text(row)
                                .font(.system(size: 12)).foregroundColor(Color(hex: "#C8CDD4"))
                                .lineLimit(rows.count == 1 ? 2 : 1).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 8) {
                        if note.isRecap {
                            PrimaryButton("OK") { engine.dismiss() }
                        } else {
                            SecondaryButton("Not now") { engine.dismiss() }
                            PrimaryButton("Show me") {
                                if let shown = engine.act(), let agent = shown.agentId { AgentTarget.bringForward(pillId: agent) }
                            }
                        }
                    }
                }
                .padding(.leading, 116)
                .padding(.trailing, 34)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

                // × is the same as OK.
                Button { engine.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(hex: "#5F646D"))
                        .frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .padding(.top, 8).padding(.trailing, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .accessibilityIdentifier(Sidekick.marker)   // in every build's binary: the binary check looks for it
        .onChange(of: seen) { _, nowSeen in if nowSeen { engine.noteSeen() } }
    }
}
