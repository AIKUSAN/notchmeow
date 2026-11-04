import SwiftUI

// Settings → Cat in the app: `CatSettingsView` with the agents the island has now, so "Cats for your agents" follows them as they come and go. The view itself
// takes plain values (the render script has no app state), so this wrapper is the only place that reads `AppState`.

struct CatSettingsSection: View {
    /// The tab to draw; nil (today's Settings call, until the page's tabs are wired in) draws every group.
    var tab: SettingsRoute.Tab? = nil
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var projects = ProjectsModel.shared

    var body: some View {
        let agents = app.tasks.filter { CatDisplaySettings.isAgentPill($0.id) }.map {
            CatAgentList.Agent(id: $0.id, name: PillCatalog.definition(for: $0.id)?.name ?? $0.name, color: $0.color, last: app.pillLastEvent[$0.id] ?? 0)
        }
        // Project cats: only a folder's name and its cat key leave the model (never a path).
        let live = projects.appView().projects.map { ProjectCatList.Live(catKey: $0.catKey, name: $0.name) }
        CatSettingsView(agents: agents, lookup: { id in PillCatalog.definition(for: id).map { ($0.name, $0.color) } }, wardrobeDay: { WardrobeClock.appToday() }, tab: tab, projects: live)
    }
}
