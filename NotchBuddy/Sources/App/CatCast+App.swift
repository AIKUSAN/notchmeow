import Foundation

// The app's way into the cast: the island's own state and Settings, read as `CatCast`'s plain values. Nothing here is in the contract, and the test programs do not
// compile this file (`tests/CatWiringTests.swift` pins where the views and the hook server call it).

extension AppState {
    /// Which cat appears where on the island right now: the big cat, cat 2 (Two cats mode), the pills and the 2x2 grid, the drop view and the drag ghost, and the
    /// greeting. The big cat shows the focused pill (`focusTask`, as everything else does); each pill's last event is `pillLastEvent`.
    var cast: CatCast.Result {
        let store = CatSettingsStore.shared
        return CatCast.of(store.display.mode,
                          tasks: tasks.map { CatCast.Pill(id: $0.id, state: CatState(rawValue: $0.state.rawValue) ?? .idle, last: pillLastEvent[$0.id] ?? 0) },
                          focusId: focusTask?.id, mainCat: store.settings.character, pair: store.display.pair, agentCats: store.display.agentCats)
    }

    /// Whether the compact island has a right wing at all: a cat in the grid. The same rule as `CompactMiniGrid.others` (the cast's pills that are tasks), which
    /// `IslandWingWiringTests` pins in both places.
    var hasMiniGrid: Bool { cast.pills.contains { p in tasks.contains { $0.id == p.pill } } }

    /// The display mode Settings has: where the big cat sits (`botPosition`) depends on it, and so does the hit test of a slap.
    var displayMode: CatDisplayMode { CatSettingsStore.shared.display.mode }

    /// What the island calls an agent: the pill catalog's name (Codex, Gemini CLI), Claude Code for the Claude Code pill, else the name the pill came with.
    func agentName(for pillId: String) -> String {
        pillId == "integration_claude" ? "Claude Code" : PillCatalog.definition(for: pillId)?.name ?? tasks.first { $0.id == pillId }?.name ?? pillId
    }

    /// A pill that has just been created gets its coat now, before anything draws it, and keeps it: an agent pill is given one if it has none (Claude Code is
    /// Shrimpy and Codex is Momo; every other agent a random coat that no other agent and not the Main cat wears), and any other pill is left alone.
    func giveCoat(to pillId: String) { CatSettingsStore.shared.ensureAgentCat(for: pillId) }
}
