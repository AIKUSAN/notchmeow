import AppKit

// A drop on an agent's own cat, in the app. The rules are `SidekickDrop` (tested); this is what only the app can do: find the cats under the pointer, copy the path to the clipboard, bring the agent's app
// forward (`AgentTarget`, the routes the pill's ↗ button uses) and say so in one line. The big cat is never a target: only the grid's cats in A cat for each agent mode and cat 2 in Two cats mode, and only
// for an agent that has a live session. NotchMeow never pastes, types or sends anything into another app (no key event is made here), never starts a process and never says "sent", "delivered" or "attached".
// The line shows in the island's `.sidekick` row (owner's answer 2, 2026-10-14), not in the `.note` view, which is the AI error flow.

extension Notification.Name {
    /// An agent's own cat (a grid cat or cat 2) answers a drop on it with the happy emote: the object is the agent's pill ID.
    static let sidekickCatEmote = Notification.Name("notchBuddy.sidekickCatEmote")
}

@MainActor
enum SidekickDropApp {
    /// How long the line stays up when the user does not answer it. One drop's line is not ended by an older drop's turn.
    private static let lineSeconds = 4.0
    private static var lineGeneration = 0

    /// The agent whose own cat is under `loc` (the drag's place in the island panel's window, y up), and only when that agent has a live session. nil: the drop is what it always was.
    static func agentCat(atWindowPoint loc: CGPoint, panelWidth: Double, panelHeight: Double, live: Set<String>, state: AppState = .shared) -> String? {
        guard state.mode != .hidden, !live.isEmpty else { return nil }
        let (islandW, fixedH) = islandSize(mode: state.mode, view: state.view, progress: state.uploadProgress, nw: state.notchWidth, nh: state.notchHeight)
        let islandH: CGFloat = (state.mode == .expanded && state.view == .prompt) ? ChatSizing.islandHeight(messages: state.chatHistory.count) : fixedH
        var cats: [SidekickDrop.Cat] = []
        // The compact island's grid: only in A cat for each agent mode (in the other modes its cats wear the Main cat and stand for no agent), and only while it is drawn.
        if state.mode == .compact, state.displayMode == .perAgent, !state.wingYielded, !state.greetingTail {
            let pills = state.cast.pills.filter { p in state.tasks.contains { $0.id == p.pill } }.map { (pill: $0.pill, agent: CatDisplaySettings.isAgentPill($0.pill)) }
            cats += SidekickDrop.gridCats(pills: pills, panelWidth: panelWidth, islandWidth: Double(islandW), islandHeight: Double(islandH))
        }
        // Cat 2 of Two cats mode, where it is drawn (compact, or beside the big cat in the overview).
        if let pill = state.cast.second?.pill, let place = secondCatPlace(state: state, islandW: islandW, islandH: islandH) {
            let left = (panelWidth - Double(islandW)) / 2
            cats.append(SidekickDrop.Cat(pill: pill, x: left + Double(place.cx), y: Double(place.cy), r: place.compact ? Double(place.d / 0.6 / 2) : Double(place.d / 2)))
        }
        guard !cats.isEmpty else { return nil }
        return SidekickDrop.agentCatAt(x: Double(loc.x), y: panelHeight - Double(loc.y), cats: cats, live: live)
    }

    /// The drop: the original path (or paths, space-separated on one line, each quoted when its name needs it) goes to the clipboard, the agent's app comes forward, the agent's cat is happy and the island says what was done. A path with a character a terminal would
    /// act on (see `SidekickDrop.isRefused`) is refused, and the line says so. This is user-started, so it does not go through the show gate.
    static func handoff(urls: [URL], pillId: String, state: AppState = .shared) {
        let name = state.agentName(for: pillId)
        let line: String
        if let text = SidekickDrop.clipboardText(paths: urls.map(\.path)) {
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(text, forType: .string)
            AgentTarget.bringForward(pillId: pillId)
            line = SidekickDrop.line(agentName: name, count: urls.count)
            NotificationCenter.default.post(name: .sidekickCatEmote, object: pillId)   // the cat is happy only when the path was copied
        } else {
            line = SidekickDrop.refusedLine()
        }
        showLine(line, state: state)
    }

    /// One line in the `.sidekick` row, which opens the island the way a finished task does and goes back by itself a few seconds later (or at OK or ×). Where the island was is kept in the sidekick's own
    /// `inputs`, as for a note, so the island folds again only if this line opened it.
    private static func showLine(_ line: String, state: AppState) {
        let inputs = Sidekick.shared.inputs
        if state.view != .sidekick { inputs.mode = state.mode }
        inputs.collapsePending = false
        state.sidekickDropLine = line
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.sidekick)
        lineGeneration += 1
        let mine = lineGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + lineSeconds) {
            MainActor.assumeIsolated { if mine == lineGeneration { endLine(state: state) } }
        }
    }

    /// The line goes (its time is up, or OK or ×). The row goes back to the overview, and the island folds if the line had opened it; a sidekick note that is on screen keeps the row.
    static func endLine(state: AppState = .shared) {
        guard state.sidekickDropLine != nil else { return }
        state.sidekickDropLine = nil
        guard state.view == .sidekick, Sidekick.shared.engine.showing == nil else { return }
        state.view = state.tasks.isEmpty ? .empty : .overview
        guard Sidekick.shared.inputs.mode != .expanded else { return }
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
    }
}
