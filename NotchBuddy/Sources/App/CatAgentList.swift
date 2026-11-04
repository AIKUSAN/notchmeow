import Foundation

// The "Cats for your agents" list of Settings → Cat → Display (A cat for each agent mode): one row per agent NotchMeow has seen, most recent first. The rows are
// built here, from plain values, so the order and the coats are tested without the app; `CatSettingsView` draws them. Foundation only.

enum CatAgentList {
    /// An agent pill on the island now: its ID, the name and the colour it shows, and the time of its last event (ms; 0 when it has had none).
    struct Agent: Equatable {
        var id: String
        var name: String
        var color: String
        var last: Double = 0
    }

    /// One row: the agent, the coat it wears (stored, else its default, else the Main cat), and whether it is on the island now.
    struct Row: Equatable {
        var id: String
        var name: String
        var color: String
        var cat: String
        var present: Bool
    }

    /// The colour of an agent that is not on the island and has no pill definition: a neutral grey.
    static let fallbackColor = "#8D9098"

    /// A readable name for an agent that is only in the store: `agent_my-tool` is "My tool", `integration_claude` is "Claude Code".
    static func title(_ id: String) -> String {
        if id == "integration_claude" { return "Claude Code" }
        let words = id.dropFirst(id.hasPrefix("agent_") ? 6 : 0).split(whereSeparator: { $0 == "-" || $0 == "_" }).joined(separator: " ")
        return words.isEmpty ? id : words.prefix(1).uppercased() + words.dropFirst()
    }

    /// Whether an event for `id` changes the order of this list (most recent event first): it does, unless that pill already had the latest event. The app announces a change then and only then, so
    /// Settings follows the order as it changes without every hook event invalidating every view. `last` is each pill's last event time (ms), as `AppState.pillLastEvent` holds it.
    static func touchReorders(_ last: [String: Double], id: String) -> Bool {
        guard let newest = last.max(by: { $0.value < $1.value })?.key else { return true }
        return newest != id
    }

    /// The agents on the island first, the most recent event first (a pill with no event yet comes after those that had one, in the island's order), then the agents
    /// that are only stored, in code-point order of their IDs. Integrations and AI providers are not agents and are not listed. `lookup` names and colours a stored
    /// agent that is not on the island (the app asks the pill catalog).
    static func rows(agents: [Agent], display: CatDisplaySettings, main: String, lookup: (String) -> (name: String, color: String)? = { _ in nil }) -> [Row] {
        var out: [Row] = [], seen = Set<String>()
        let present = agents.enumerated().filter { CatDisplaySettings.isAgentPill($0.element.id) }
            .sorted { a, b in a.element.last.isFinite && b.element.last.isFinite && a.element.last != b.element.last ? a.element.last > b.element.last : a.offset < b.offset }
        for (_, a) in present where seen.insert(a.id).inserted {
            out.append(Row(id: a.id, name: a.name, color: a.color, cat: display.catFor(agent: a.id, main: main), present: true))
        }
        for id in display.agentCats.keys.sorted() where CatDisplaySettings.isAgentPill(id) && !seen.contains(id) {
            let known = lookup(id)
            out.append(Row(id: id, name: known?.name ?? title(id), color: known?.color ?? fallbackColor, cat: display.catFor(agent: id, main: main), present: false))
        }
        return out
    }
}

/// The sample island the Display preview of Settings draws: five pills with a state each, the first focused. In Two cats mode the agent waiting for you is cat 2.
enum CatDisplaySample {
    struct Pill: Equatable {
        var id: String
        var name: String
        var color: String
        var state: CatState
    }
    static let pills = [
        Pill(id: "integration_claude", name: "Claude Code", color: "#E07950", state: .working),
        Pill(id: "agent_codex", name: "Codex", color: "#2DD4BF", state: .approval),
        Pill(id: "agent_gemini", name: "Gemini CLI", color: "#8AB4F8", state: .thinking),
        Pill(id: "agent_antigravity", name: "Antigravity", color: "#E879F9", state: .idle),
        Pill(id: "integration_stripe", name: "Stripe", color: "#0570DE", state: .idle),
    ]
    static let focus = "integration_claude"

    /// The coats the sample agents wear: the stored ones, and for a sample agent with none the one the app would give it (a fixed random source, so the preview is
    /// the same every time). Nothing is stored.
    static func coats(_ display: CatDisplaySettings, main: String) -> [String: String] {
        CatAgentCats.assignAgentCats(pills.map(\.id), display.agentCats, mainCat: main, rand: CatRNG(seed: 3).next)
    }

    /// The cast of the sample island in the chosen mode: what the preview draws.
    static func cast(_ display: CatDisplaySettings, main: String) -> CatCast.Result {
        CatCast.of(display.mode, tasks: pills.enumerated().map { CatCast.Pill(id: $1.id, state: $1.state, last: Double(100 - $0 * 10)) }, focusId: focus,
                   mainCat: main, pair: display.pair, agentCats: coats(display, main: main))
    }
}
