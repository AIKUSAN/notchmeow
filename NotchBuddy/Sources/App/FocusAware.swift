import Foundation

// Focus awareness (the spec docs/superpowers/specs/2026-10-17-focus-awareness-design.md): when a permission request or a question arrives from a session whose
// app is the frontmost app, NotchMeow answers "ask" at once and stays silent. This file holds every decision: the setting, the session's host, the match against the
// frontmost app, the decision, the marks and their endings, and the wording. The app side (FocusAwareApp) reads the frontmost app once per request and keeps the marks.
// The label is ProjectsRules.waitLabel (P-mac, fixture-tested). Pure Foundation: every time is a parameter, so nothing here reads the clock or the system.
// The Windows/Linux twin is windows/src/core/focusaware.ts. Tested by scripts/test-focus-aware.sh.

enum FocusAware {
    /// The one switch, Settings → General → Island → "Step back when I'm already in the app" (on by default).
    static let defaultsKey = "island.focusAware"
    static let markLifetime: Double = 600                        // seconds (spec rule 4, APP_WAIT_MS); the Windows twin pins this exact line
    static let endingEvents: [String] = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "UserPromptSubmit", "Stop", "StopFailure", "Interrupt", "SessionEnd"]
    static let marksMax = 64
    static let codexBundleId = "com.openai.codex"
    /// NotchMeow's own bundle ID (the Debug and Store builds too): a claude process it launches inherits it, so the app is never a session's host.
    static let ownBundlePrefix = "io.github.aikusan.notchmeow"

    enum Kind: String, Equatable, Sendable { case permission, question }

    /// The app a session runs in, as the frontmost app must match it. `vscodeFamily` is VS Code and its forks (any bundle ID with "vscode" in it).
    enum Host: Equatable, Sendable { case app(String); case vscodeFamily }

    /// One stepped-back request: its session, its pill, the host's words ("VS Code", "iTerm", "Claude App"), the kind, the step words (permissions only) and the time (a wall-clock reference time).
    struct Mark: Equatable, Sendable {
        var sessionId: String
        var pillId: String
        var host: String
        var kind: Kind
        var words: String?
        var at: Double
    }

    /// The marks, in memory only. Ended by the session's own events (`end`), aged at read time (`live`), never by a timer.
    struct Marks: Equatable, Sendable {
        private(set) var entries: [Mark]

        init() { entries = [] }

        /// A newer request of the same session and pill replaces its mark. Marks older than the lifetime at this request are dropped, and the newest `marksMax` are kept.
        mutating func record(_ mark: Mark) {
            entries.removeAll { $0.pillId == mark.pillId && $0.sessionId == mark.sessionId }
            entries.removeAll { !FocusAware.isLive($0, now: mark.at) }
            entries.append(mark)
            if entries.count > FocusAware.marksMax { entries = Array(entries.sorted { $0.at < $1.at }.suffix(FocusAware.marksMax)) }
        }

        /// The session's own events end its mark. The --ask twin of a question (`PreToolUse` of `AskUserQuestion`) ends nothing: Projects reads it as the same wait.
        mutating func end(sessionId: String, event: String, tool: String) {
            guard wouldEnd(sessionId: sessionId, event: event, tool: tool) else { return }
            entries.removeAll { $0.sessionId == sessionId }
        }

        /// Whether `end` would remove a mark, read without writing: the app's published setter runs on any write, so the caller checks this first.
        func wouldEnd(sessionId: String, event: String, tool: String) -> Bool {
            FocusAware.endingEvents.contains(event) && !(event == "PreToolUse" && tool == "AskUserQuestion") && entries.contains { $0.sessionId == sessionId }
        }

        func live(now: Double) -> [Mark] { entries.filter { FocusAware.isLive($0, now: now) } }

        func forPill(_ pillId: String, now: Double) -> Mark? { newest(live(now: now).filter { $0.pillId == pillId }) }

        func forSession(_ sessionId: String, now: Double) -> Mark? { newest(live(now: now).filter { $0.sessionId == sessionId }) }

        private func newest(_ marks: [Mark]) -> Mark? { marks.max { $0.at < $1.at } }
    }

    /// The stored switch. Absent or not a Bool reads as on.
    static func enabled(stored: Any?) -> Bool { stored as? Bool ?? true }

    /// The session's host. A Claude app session is the Claude app whatever its route. Else by route: Codex, Cursor, Claude Code (terminal or VS Code) and, in the GitHub build only,
    /// a tagged agent (matched by the terminal its own event names, never by a guess). Nil when no host can be named exactly.
    static func host(route: HookOrigin.Route, rawAgent: String, termProgram: String, bundleId: String, githubBuild: Bool) -> Host? {
        if bundleId.lowercased().hasPrefix(ownBundlePrefix) { return nil }
        if HookOrigin.isDesktop(rawAgent: rawAgent) { return .app(HookOrigin.desktopBundleId) }
        switch route {
        case .codex: return .app(codexBundleId)
        case .cursor: return .app(HookOrigin.cursorBundleId)
        case .claude: return sessionHost(termProgram: termProgram, bundleId: bundleId)
        case .external: return githubBuild ? sessionHost(termProgram: termProgram, bundleId: bundleId) : nil
        }
    }

    /// VS Code (or a fork), Cursor, or the terminal that started the session. Nil when the event names none of them.
    private static func sessionHost(termProgram: String, bundleId: String) -> Host? {
        if HookOrigin.isVSCode(termProgram: termProgram, bundleId: bundleId) { return .vscodeFamily }
        if bundleId.lowercased() == HookOrigin.cursorBundleId { return .app(HookOrigin.cursorBundleId) }
        guard let terminal = HookOrigin.terminalBundleId(termProgram: termProgram, bundleId: bundleId) else { return nil }
        return .app(terminal)
    }

    /// Whether the frontmost app (its bundle ID, or nil when unreadable) is the session's host. An empty or nil ID is never a match.
    static func matches(_ host: Host, frontmost: String?) -> Bool {
        guard let front = frontmost?.lowercased(), !front.isEmpty else { return false }
        switch host {
        case .app(let id): return front == id.lowercased()
        case .vscodeFamily: return front.contains("vscode")
        }
    }

    /// Step back only when the setting is on, the host is known and the frontmost app is that host. `frontmost` is read only when the first two hold.
    static func decide(enabled: Bool, host: Host?, frontmost: () -> String?) -> Bool {
        guard enabled, let host else { return false }
        return matches(host, frontmost: frontmost())
    }

    /// The host's words for the mark and the note: the Claude app, Cursor, Codex, else the name of the terminal (VS Code for VS Code). A tagged agent is named by its terminal.
    static func hostWords(route: HookOrigin.Route, rawAgent: String, termProgram: String, bundleId: String) -> String {
        if HookOrigin.isDesktop(rawAgent: rawAgent) { return HookOrigin.hostName(pillId: HookOrigin.desktopPill, termProgram: termProgram, bundleId: bundleId) }
        switch route {
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .claude, .external: return HookOrigin.hostName(pillId: "integration_claude", termProgram: termProgram, bundleId: bundleId)
        }
    }

    /// "Waiting in <host>", then ": <step words>" when there are words. The label is ProjectsRules.waitLabel, so Projects and the note read the same.
    static func noteText(host: String, words: String?) -> String {
        let label = ProjectsRules.waitLabel(host)
        guard let words, !words.isEmpty else { return label }
        return "\(label): \(words)"
    }

    /// The card's "Handled in …" note, replaced by the wait's note while the session has a live mark (call 7).
    static func cardNote(_ note: String, mark: Mark?) -> String {
        guard let mark else { return note }
        return noteText(host: mark.host, words: mark.words)
    }

    /// The amber dot on the pill: while a mark lives, in the badge place, and never with a badge or a waiting card (call 3).
    static func showsDot(markLive: Bool, badgeShown: Bool, cardWaiting: Bool) -> Bool { markLive && !badgeShown && !cardWaiting }

    /// Whether the overview's note takes cat 2's second line while a mark lives (the owner's rule, 2026-10-22). It does, unless that line is itself a waiting alert: a
    /// card or question waiting on cat 2's pill, the same rule as the dot. The line stays then and the note is not drawn there. No cat 2 means no line, so the note shows.
    static func showsNoteOverSecondLine(markLive: Bool, secondWaiting: Bool) -> Bool { markLive && !secondWaiting }

    /// What Projects gets for the `--ask` twin of a question: the mark's host, so the stepped-back wait stays "Waiting in <host>" whichever of the two hooks lands first.
    static func twinWaitIn(event: String, tool: String, mark: Mark?) -> String? {
        guard event == "PreToolUse", tool == "AskUserQuestion", let mark, mark.kind == .question else { return nil }
        return mark.host
    }

    /// The Sidekick-clock time (ms) at which a mark made at `markAt` (the wall clock, seconds since the reference date) ends: the rest of its lifetime from `now`, added to `nowMs`.
    static func lapseMs(markAt: Double, now: Double, nowMs: Double) -> Double { nowMs + (markAt + markLifetime - now) * 1000 }

    /// A mark lives while its age (now minus its time) is under the lifetime. A mark a little ahead of `now` (the clock went back) counts as just made; one a whole
    /// lifetime or more ahead of it (the clock stepped back by more than that) is gone.
    private static func isLive(_ mark: Mark, now: Double) -> Bool {
        let age = now - mark.at
        return age < markLifetime && age > -markLifetime
    }
}
