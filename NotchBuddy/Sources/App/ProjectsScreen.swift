import SwiftUI

// The Projects screen in the island (sub-project P-mac, Task 9): the `.projects` view, ProjectsScreenContent (ProjectsViews.swift) fed by the shared model. It is built
// only while it is the island's view (IslandViewContent), so an island on another view draws none of it. Its animations run only while the island is expanded on this
// view (0 % CPU when hidden). A row's click opens that session's waiting card, or brings the session's own app forward.

struct ProjectsScreenHost: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var model = ProjectsModel.shared

    var body: some View {
        ProjectsScreenContent(view: model.appView(), active: state.mode == .expanded && state.view == .projects, onRow: { ProjectsScreenHost.open($0) })
            .accessibilityIdentifier(ProjectsModel.marker)
    }

    /// A row's click, for the registry's session id (the raw session id, the key `AppState.sessionHosts` uses): that session's waiting approval opens its card, else
    /// its waiting question, else its own app comes forward. The island is expanded here (the screen is on it), so the view changes and nothing else does.
    @MainActor static func open(_ session: String) {
        let state = AppState.shared
        if let approval = state.pendingApproval, ProjectsRegistry.same(approval.sessionId, session) {
            state.view = .approval
        } else if state.pendingQuestion != nil, ProjectsRegistry.same(state.questionSessionId, session) {
            state.view = .question
        } else {
            AgentTarget.bringForward(session: session)
        }
        state.lastActivity = .now
    }
}
