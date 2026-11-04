import AppKit
import Foundation

// Focus awareness, the app side (the spec docs/superpowers/specs/2026-10-17-focus-awareness-design.md): the one read of the frontmost app per request, the session's
// bookkeeping and the mark. HookServer calls `stepBack` in its two request handlers before the Projects feed and the answer; nothing here starts a timer, an observer
// or a poll, and no log line, mark or published value names an app, a bundle ID or a path. Every decision is FocusAware's (FocusAware.swift).

@MainActor
enum FocusAwareApp {
    /// The wall clock, in seconds since the reference date: a Mac asleep for ten minutes reads a mark as old (the end is judged when a view reads it).
    nonisolated static func now() -> Double { Date().timeIntervalSinceReferenceDate }

    /// The request's step-back. Non-nil when the request stepped back to its own app: the mark is recorded, the session's pill is touched, and the caller answers "ask"
    /// and feeds Projects with the mark's host. Nil when it did not: the caller goes on exactly as before.
    static func stepBack(payload: [String: Any], route: HookOrigin.Route, kind: FocusAware.Kind) -> FocusAware.Mark? {
        let state = AppState.shared
        guard state.focusAware else { return nil }
        let rawAgent = payload["nm_agent"] as? String ?? ""
        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId = payload["bundle_id"] as? String ?? ""
        let sessionId = SidekickLedger.sessionKey(payload)   // the ledger's own key (first non-empty, capped), so the hold matches the ledger's session
        #if APPSTORE
        let githubBuild = false
        #else
        let githubBuild = true
        #endif
        let host = FocusAware.host(route: route, rawAgent: rawAgent, termProgram: termProgram, bundleId: bundleId, githubBuild: githubBuild)
        // The only read of the frontmost app: only when the setting is on and the session's host is known (FocusAware.decide).
        guard FocusAware.decide(enabled: true, host: host, frontmost: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) else { return nil }

        let pillId = HookOrigin.pillId(route)
        let mark = FocusAware.Mark(
            sessionId: sessionId, pillId: pillId,
            host: FocusAware.hostWords(route: route, rawAgent: rawAgent, termProgram: termProgram, bundleId: bundleId),
            kind: kind,
            words: kind == .permission ? SessionStepText.verb(tool: payload["tool_name"] as? String ?? "") : nil,
            at: now())
        // Recorded before the feed, so the Sidekick's evaluation already sees it.
        state.focusMarks.record(mark)
        state.touchPill(pillId)
        if route == .claude { state.noteHost(pillId, session: payload["session_id"] as? String ?? payload["conversation_id"] as? String ?? "unknown", HookOrigin.hostBundleId(rawAgent: rawAgent, termProgram: termProgram, bundleId: bundleId)) }   // the pill's own key, as before focus awareness
        Sidekick.shared.feed(payload: payload)
        appendAppLog("nm.log", "\(kind == .permission ? "PermissionRequest" : "Question") stepped back [\(pillId)]")
        return mark
    }
}
