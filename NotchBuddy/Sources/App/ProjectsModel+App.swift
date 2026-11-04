import AppKit
import Combine
import Foundation

// The Projects model's app side (P-mac, Tasks 8 and 9): the shared instance the hook server feeds and the island reads, its sinks on the island's mode and focus,
// and the view the screen draws. The home is the user's real one (Sidekick.realHome), the clock is the wall clock in ms, and the tick is one one-shot timer on the
// main queue, the way the cat's sleep clock runs. Nothing here stores or logs anything.
//
// Task 11: `ProjectsHits` (where each project pill is, for the right-click that pins it) and `ProjectPinTarget` (what the pin menu's one item does) live here, so the
// pure views (which the render tool compiles without this file) never name them.

extension ProjectsModel {
    /// The app's subscriptions to the island (the mode and the focus). They live as long as the app, so the model stays in step with the island.
    private static var subscriptions = Set<AnyCancellable>()

    /// The app's model. Its layout starts from the real pills, folded, so a Claude-only user gets the projects layout at the first fold. The app creates it at launch
    /// (AppDelegate), outside any view's body, since its layout is published.
    static let shared: ProjectsModel = {
        let model = ProjectsModel(
            home: Sidekick.realHome,
            now: { Date().timeIntervalSince1970 * 1000 },
            schedule: { afterMs, fire in
                let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
                DispatchQueue.main.asyncAfter(deadline: .now() + afterMs / 1000, execute: item)
                return { item.cancel() }
            })
        let app = AppState.shared
        model.refreshFromApp()
        // Every input of the layout has a sink. A published value's sink is given the new value (the stored one is written after the publisher fires), so each passes its own and
        // `refreshFromApp` reads the rest fresh. The mode's reads the layout BEFORE it tells the model the island is expanded: the island reads its height on that same change,
        // and a section whose projects all timed out while it was folded (no feed, no tick) would otherwise open as an empty 92 pt.
        subscriptions.insert(app.$mode.sink { mode in
            model.refreshFromApp { $0.expanded = mode == .expanded }
            model.islandExpanded(mode == .expanded)
        })
        subscriptions.insert(app.$focusId.sink { focus in
            model.refreshFromApp { $0.focusId = focus }
        })
        subscriptions.insert(app.$activeIntegrations.sink { ids in
            model.refreshFromApp { $0.activeIntegrations = ids }
        })
        subscriptions.insert(app.$mainPillId.sink { pill in
            model.refreshFromApp { $0.mainPillId = pill }
        })
        subscriptions.insert(CatSettingsStore.shared.$display.sink { display in
            model.refreshFromApp { $0.twoCats = display.mode == .two }
        })
        return model
    }()

    /// The view as the island draws it: the project cats from Settings and the main cat, read at the moment it is asked (no cat is kept here).
    func appView() -> PJView {
        view(projectCats: CatSettingsStore.shared.projectCats, mainCat: CatSettingsStore.shared.settings.character)
    }

    /// One hook payload from the hook server: the registry's feed, then the layout read again while the island is open, so the last project ending while open
    /// drops the section and its height at once.
    func feedFromHook(payload: [String: Any], waitIn: String?) {
        feed(payload: payload, waitIn: waitIn)
        refreshFromApp()
    }

    /// The layout, read from every input as it is now: the pills (the main pill and the active integrations), the focus, whether the island is expanded and Two cats mode (the display
    /// mode). The one place these are read, so no sink or hook can reuse a stale copy of another's. `published` replaces the one value whose publisher just fired (its stored value is
    /// written after the sink runs).
    fileprivate func refreshFromApp(_ published: (inout LayoutInputs) -> Void = { _ in }) {
        let app = AppState.shared
        var i = LayoutInputs(expanded: app.mode == .expanded, focusId: app.focusId, mainPillId: app.mainPillId, activeIntegrations: app.activeIntegrations,
                             twoCats: CatSettingsStore.shared.display.mode == .two)
        published(&i)
        refreshLayout(activePills: [i.mainPillId] + i.activeIntegrations.sorted(), open: i.expanded, focusId: i.focusId, twoCats: i.twoCats)
    }
}

/// The app's inputs to the island's layout (`ProjectsModel.refreshFromApp`).
fileprivate struct LayoutInputs {
    var expanded: Bool
    var focusId: String?
    var mainPillId: String
    var activeIntegrations: Set<String>
    var twoCats: Bool
}

// The big cat follows the big card's project while the expanded overview shows the Claude-only card (owner's answer 3: one cat, one project), and is today's otherwise: in
// every other view, folded, with other agents and in Two cats mode these three are the cast's coat, the effective state and no project kittens.
extension AppState {
    /// The big card's project on the expanded overview when it is the Claude-only card (never in Two cats mode); nil everywhere else. It reads the model on that view only.
    private var projectsBigCard: PJProject? {
        guard mode == .expanded, view == .overview else { return nil }
        let model = ProjectsModel.shared, v = model.appView()
        guard ProjectsLayout.usesProjects(layout: model.layout, focusId: focusId, projectCount: v.projects.count, twoCats: cast.second != nil) else { return nil }
        return model.bigCard(in: v)
    }

    /// A project's peek is open over the left card: only on the expanded overview (the peek exists nowhere else). The big cat and the kittens fade while it is.
    var projectPeeking: Bool {
        mode == .expanded && view == .overview && ProjectsModel.shared.peekingProject != nil
    }

    /// The coat the big cat wears: the big card's project's cat on the Claude-only card, else the cast's.
    var bigCatCoat: String {
        let card = projectsBigCard
        return ProjectsLayout.bigCoat(castCoat: cast.big.cat, usesProjects: card != nil, expandedOverview: mode == .expanded && view == .overview, projectCat: card?.cat)
    }

    /// The state the big cat shows: the big card's project's state on the Claude-only card (asleep once the sleep timer has fired, as any idle cat), else the effective state.
    var bigCatState: BotState {
        let card = projectsBigCard
        let name = ProjectsLayout.bigState(castState: effectiveState.rawValue, usesProjects: card != nil, expandedOverview: mode == .expanded && view == .overview, projectState: card?.state)
        return BotState(rawValue: name)?.shown(asleep: catAsleep) ?? effectiveState
    }

    /// The big card project's subagents (all its sessions'), drawn as kittens beside the big cat; nil unless the overview shows the Claude-only card.
    var projectKittens: [PJSubagentRow]? {
        guard let card = projectsBigCard else { return nil }
        return card.sessions.flatMap { $0.subagents }
    }
}

/// Where each project pill is, in the island's own coordinates (the named space "nm.island"): written by the overview's pills through their frame closures, read by the
/// island controller's right-click monitor, and cleared when the island folds or leaves the overview. Main actor only, in memory only.
@MainActor enum ProjectsHits {
    static var pillFrames: [String: CGRect] = [:]
}

/// The target of the pin menu's one item (Pin or Unpin): the item carries the project's id, and the shared model toggles its pin.
@MainActor
final class ProjectPinTarget: NSObject {
    static let shared = ProjectPinTarget()

    @objc func toggle(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        ProjectsModel.shared.togglePin(id)
    }
}
