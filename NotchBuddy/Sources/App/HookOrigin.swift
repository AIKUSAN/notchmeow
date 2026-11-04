import Foundation

// Which pill a hook event belongs to, and where its user answers: the rules `HookServer` used to hold as three copies of an editor test.
// Claude Code reaches the Claude Code pill (`integration_claude`) from VS Code or from any terminal (Terminal, iTerm, Ghostty, Warp, kitty and the rest),
// as it does on Windows and Linux. Cursor and Codex keep their own pills, and a tagged agent (`nm_agent`) keeps its own.
// Pure Foundation, tested by scripts/test-hook-origin.sh. The pill's ID does not change, and its label is "Claude Code" (it was "VS Code" until U1).

enum HookOrigin {
    enum Route: Equatable {
        case codex
        case external(String)   // a valid `nm_agent`
        case cursor
        case claude             // Claude Code, from VS Code or from a terminal
    }

    static let cursorBundleId = "com.todesktop.230313mzl4w4u92"

    /// Claude Code sessions started from the Claude desktop app (its Code tab) set `CLAUDE_CODE_ENTRYPOINT=claude-desktop` and run in no terminal. The relay tags them with this agent name
    /// when no `--agent` was given. The tag only says that the session runs in the Claude app: the session belongs to the Claude Code pill (`integration_claude`), its host is the
    /// Claude app (`desktopBundleId`, which the pill's button opens), and its permission requests and questions stay in that app. `desktopPill` is a frozen ID that no event reaches.
    static let desktopTag = "claude-desktop"
    static let desktopPill = "agent_claude-desktop"
    static let desktopBundleId = "com.anthropic.claudefordesktop"

    /// The relay's tag rule, which the two Python relays in `HookServer.swift` repeat (`scripts/test-hook-relay.sh` runs them): an explicit `--agent` wins, else the entrypoint says Claude Desktop, else no tag.
    static func agentTag(explicit: String, entrypoint: String?) -> String {
        if !explicit.isEmpty { return explicit }
        return entrypoint == desktopTag ? desktopTag : ""
    }

    /// Whether the relay tagged the event as a session from the Claude app.
    static func isDesktop(rawAgent: String) -> Bool { rawAgent == desktopTag }

    /// `codexEnabled` is false in the App Store build, where a Codex tag is an ordinary external agent. `validAgent` is `rawAgent` once `HookServer.validateAgent` has passed it.
    static func route(rawAgent: String, validAgent: String?, codexEnabled: Bool, bundleId: String) -> Route {
        if codexEnabled && rawAgent == "codex" { return .codex }
        if isDesktop(rawAgent: rawAgent) { return .claude }
        if let agent = validAgent { return .external(agent) }
        if bundleId.lowercased() == cursorBundleId { return .cursor }
        return .claude
    }

    static func pillId(_ route: Route) -> String {
        switch route {
        case .codex: return "agent_codex"
        case .external(let agent): return "agent_\(agent)"
        case .cursor: return "agent_cursor"
        case .claude: return "integration_claude"
        }
    }

    /// The editor test the three call sites used to repeat (Cursor is told apart before it, by its bundle ID).
    static func isVSCode(termProgram: String, bundleId: String) -> Bool {
        bundleId.lowercased() != cursorBundleId && (termProgram.lowercased().contains("vscode") || bundleId.lowercased().contains("vscode"))
    }

    private static let terminalNames: [(bundlePrefix: String, program: String, name: String)] = [
        ("com.apple.terminal", "apple_terminal", "Terminal"),
        ("com.googlecode.iterm2", "iterm.app", "iTerm"),
        ("com.mitchellh.ghostty", "ghostty", "Ghostty"),
        ("dev.warp.", "warpterminal", "Warp"),
        ("net.kovidgoyal.kitty", "kitty", "kitty"),
        ("org.alacritty", "alacritty", "Alacritty"),
        ("com.github.wez.wezterm", "wezterm", "WezTerm"),
        ("co.zeit.hyper", "hyper", "Hyper"),
    ]

    /// Where the user is, in the words of the notes "Handled in …" and "Still waiting in …". VS Code, Cursor and Codex read as they always did.
    static func hostName(pillId: String, termProgram: String, bundleId: String) -> String {
        switch pillId {
        case "agent_cursor": return "Cursor"
        case "agent_codex": return "Codex"
        case "agent_claude-desktop": return "Claude App"
        case "integration_claude":
            if isVSCode(termProgram: termProgram, bundleId: bundleId) { return "VS Code" }
            let b = bundleId.lowercased(), p = termProgram.lowercased()
            return terminalNames.first { b.hasPrefix($0.bundlePrefix) || p == $0.program }?.name ?? "the terminal"
        default: return "the terminal"
        }
    }

    static func note(host: String, stillWaiting: Bool) -> String { stillWaiting ? "Still waiting in \(host)." : "Handled in \(host)." }

    /// The app to bring forward for a Claude Code session that is not in VS Code: the app that started it (the relay's `__CFBundleIdentifier`), else the terminal the
    /// `TERM_PROGRAM` names. nil for VS Code and Cursor, whose routes stay as they were, and when nothing is known.
    static func terminalBundleId(termProgram: String, bundleId: String) -> String? {
        if isVSCode(termProgram: termProgram, bundleId: bundleId) || bundleId.lowercased() == cursorBundleId { return nil }
        if !bundleId.isEmpty { return bundleId }
        let programs = ["apple_terminal": "com.apple.Terminal", "iterm.app": "com.googlecode.iterm2", "ghostty": "com.mitchellh.ghostty",
                        "warpterminal": "dev.warp.Warp-Stable", "kitty": "net.kovidgoyal.kitty", "alacritty": "org.alacritty",
                        "wezterm": "com.github.wez.wezterm", "hyper": "co.zeit.hyper"]
        return programs[termProgram.lowercased()]
    }

    /// The app a Claude Code session runs in, as the session's host records it: the Claude app for a session from it (whatever the relay saw), else `terminalBundleId`.
    static func hostBundleId(rawAgent: String, termProgram: String, bundleId: String) -> String? {
        isDesktop(rawAgent: rawAgent) ? desktopBundleId : terminalBundleId(termProgram: termProgram, bundleId: bundleId)
    }

    /// Where a Claude Code pill's tap brings the user: a terminal app, by bundle ID, or `.noApp` (no terminal app is known for this session: VS Code's route, as before).
    enum TapHost: Equatable { case app(String), noApp }

    /// Whether a session's host is the Claude app: its finished card offers "Open Claude" and its tap opens that app (AgentTarget).
    static func isClaudeAppHost(_ host: TapHost?) -> Bool { host == .app(desktopBundleId) }

    /// Whether a request is answered "ask" at once, with no card: a tagged agent's, and a Claude Code session from the Claude app's (its approvals and questions stay in the app).
    static func answersAskAtOnce(route: Route, rawAgent: String) -> Bool {
        if case .external = route { return true }
        return isDesktop(rawAgent: rawAgent)
    }

    /// The host the pill's tap brings forward. The session is the open card's on this pill, else the pill's current one (the last session that sent it an event).
    /// A session in `sessionHosts` answers with its own entry, an app or `.noApp`. An unknown one, or none, falls back to the pill's last host, and no host at all is VS Code's route.
    static func tapHost(cardSession: String?, currentSession: String?, sessionHosts: [String: TapHost], pillHost: String?) -> TapHost {
        if let session = cardSession ?? currentSession, let host = sessionHosts[session] { return host }
        return pillHost.map { .app($0) } ?? .noApp
    }

    /// What a hook event does to the permission request pending on its pill: `resolves` it (its own session's turn or exact tool call ended), `passes` it (another session's
    /// event: processed for that session, the card untouched) or `holds` (the pending session's own other events wait, as before). `sameTool` and `sameInput` matter to PostToolUse.
    enum PendingVerdict: Equatable { case resolves, passes, holds }

    static func pendingVerdict(eventName: String, sameSession: Bool, sameTool: Bool, sameInput: Bool) -> PendingVerdict {
        if !sameSession { return .passes }
        switch eventName {
        case "PostToolUse", "PostToolUseFailure": return sameTool && sameInput ? .resolves : .holds
        case "Stop", "StopFailure", "UserPromptSubmit", "SessionEnd", "Interrupt": return .resolves
        default: return .holds
        }
    }

    /// What a pill shows when a state is asked of it. While a card (an approval or a question) waits on the pill, it keeps what it shows: the asked state is held by AppState and
    /// shown when the card closes. Generic, so the rule can be tested without BotState.
    static func shownWhileCard<T>(cardWaiting: Bool, requested: T, current: T) -> T { cardWaiting ? current : requested }

    /// What the pill shows once its card closes: the latest state held for it while the card was up, else the fallback.
    static func shownAfterCard<T>(held: T?, fallback: T) -> T { held ?? fallback }

    /// The final line a pill holds while a card waits on it: the held entry's line when there is an entry, even a nil one (a line cleared while the card waited stays cleared),
    /// else the pill's own line. `held` is nil both for no entry and for a cleared line, so `entryExists` tells them apart.
    static func heldLine<T>(entryExists: Bool, held: T?, current: T?) -> T? { entryExists ? held : current }

    /// Whether a finished-to-idle timer may act when it fires: it is still the latest one scheduled for the pill (a later schedule supersedes it), and no card waits on the pill.
    static func finishedIdleApplies(captured: Int, latest: Int, cardWaiting: Bool) -> Bool { captured == latest && !cardWaiting }
}
