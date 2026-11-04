import AppKit

// Bringing an agent's app forward: the routes the pill's ↗ button has always used (`OverviewView.openAgentTarget`), moved here so a drop on an agent's cat and a sidekick note's "Show me"
// use the SAME routes and cannot drift from them. Claude Code: the app of the session the user is looking at (a terminal, `HookOrigin.tapHost`), else VS Code. Cursor and Codex: their own apps.
// Gemini and Antigravity: the first running terminal. All but Claude Code's VS Code route are the GitHub build's (`#if !APPSTORE`), as before. It brings an app to the front; it does not pick a tab,
// type, paste or send anything.

enum AgentTarget {
    @MainActor
    static func bringForward(pillId: String) {
        switch pillId {
        case "integration_claude":
            // The app of the session the user is looking at (HookOrigin.tapHost): the open card's session on this pill, else the pill's current one.
            let appState = AppState.shared
            let cardSession = appState.pendingApproval.flatMap { $0.pillId == pillId ? $0.sessionId : nil }
            let host = HookOrigin.tapHost(cardSession: cardSession, currentSession: appState.pillSessions[pillId], sessionHosts: appState.sessionHosts, pillHost: appState.hostBundleIds[pillId])
            // A session from the Claude app: that app, in every build, started again when it was quit (such a session is in no terminal).
            if case .app(let id) = host, id == HookOrigin.desktopBundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
                return
            }
            #if !APPSTORE
            if case .app(let id) = host, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
                app.activate(options: .activateIgnoringOtherApps)
                return
            }
            #endif
            // VS Code's route, below, is as it was.
            let vscodeBundleId = "com.microsoft.VSCode"
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
                app.activate(options: .activateIgnoringOtherApps)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
            }
        case "agent_cursor":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case "agent_codex":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.openai.codex") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case HookOrigin.desktopPill:
            // Sessions from the Claude desktop app live there, not in a terminal.
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: HookOrigin.desktopBundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
        case "agent_gemini", "agent_antigravity":
            #if !APPSTORE
            let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                     "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
            if let hit = terminalBundleIds.compactMap({ id in
                NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
            }).first {
                hit.activate(options: .activateIgnoringOtherApps)
            }
            #endif
        default:
            break
        }
    }

    /// The app a session runs in, brought forward (Projects, P-mac): the session's own host (`AppState.sessionHosts`, noted when its events arrive), so a Claude
    /// Code session in a terminal opens its terminal and one from the Claude app opens that app. With no host, VS Code's route, as the pill's.
    @MainActor
    static func bringForward(session sessionId: String) {
        let host = AppState.shared.sessionHosts[sessionId] ?? .noApp
        if case .app(let id) = host, id == HookOrigin.desktopBundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            return
        }
        #if !APPSTORE
        if case .app(let id) = host, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
            app.activate(options: .activateIgnoringOtherApps)
            return
        }
        #endif
        let vscodeBundleId = "com.microsoft.VSCode"
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
            app.activate(options: .activateIgnoringOtherApps)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
        }
    }
}
