import Foundation

// The sidekick's memory: a hook payload becomes a small normalised event (`eventFrom`), and the ledger folds events into one record per session (`apply`). Port of `eventFrom`,
// `ledgerApply` and their helpers in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/hook-cases.json pins them and docs/SIDEKICK-CONTRACT.md explains them.
// The ledger keeps a basename, a command key (a hash) and counts, and nothing else: no prompt, no assistant text, no `transcript_path`, no command, no full path, no file content.
// It is memory only (never written to disk, never logged) and a value: every function returns a new ledger and leaves the one it is given alone. Pure Foundation.

struct SKEvent: Equatable, Sendable {
    var at: Double
    var agentId: String
    var sessionId: String
    /// sessionStart, prompt, preTool, question, tool, failure, approvalAsked, approvalAnswered, stop, stopFailure, subagentStart, subagentStop, sessionEnd or notification.
    var kind: String
    var name = ""
    var tool = ""
    var target = ""
    var file = ""
    var key = ""
    var ok = true
    var project = ""
    var subagentId = ""

    var json: [String: Any] {
        ["at": at, "agentId": agentId, "sessionId": sessionId, "kind": kind, "name": name, "tool": tool, "target": target, "file": file, "key": key, "ok": ok, "project": project, "subagentId": subagentId]
    }
}

struct SKRing: Equatable, Sendable {
    var at: Double
    var kind: String
    var tool: String
    var target: String
    var file: String
    var key: String
    var ok: Bool

    var json: [String: Any] { ["at": at, "kind": kind, "tool": tool, "target": target, "file": file, "key": key, "ok": ok] }
}

struct SKSession: Equatable, Sendable {
    var key: String
    var agentId: String
    var sessionId: String
    var startedAt: Double
    var lastEventAt: Double
    var endedAt: Double? = nil
    /// The cat's words: idle, thinking, working, searching, approval, question, finished, error.
    var state = "idle"
    var last = "sessionStart"
    var project = ""
    var ring: [SKRing] = []
    var pendingApprovalAt: Double? = nil
    var pendingKey: String? = nil
    /// The helpers that are alive, each with when it started, in the order they came.
    var subagents: [Sub] = []
    var nudgedAt: Double? = nil

    struct Sub: Equatable, Sendable { var id: String; var at: Double }

    var aliveSubagents: Int { subagents.count }
    var isDone: Bool { endedAt != nil || state == "finished" || state == "error" }

    private static func opt(_ x: Double?) -> Any { x.map { $0 as Any } ?? NSNull() }

    var json: [String: Any] {
        ["key": key, "agentId": agentId, "sessionId": sessionId, "startedAt": startedAt, "lastEventAt": lastEventAt, "endedAt": Self.opt(endedAt), "state": state, "last": last, "project": project,
         "ring": ring.map(\.json), "pendingApprovalAt": Self.opt(pendingApprovalAt), "pendingKey": pendingKey.map { $0 as Any } ?? NSNull(),
         "subagents": Dictionary(subagents.map { ($0.id, $0.at) }, uniquingKeysWith: { $1 }), "nudgedAt": Self.opt(nudgedAt)]
    }

    /// A session as the fixtures hold it (a ledger's record). Anything that is not a number or text where one belongs takes the default, so a hand-made record never throws.
    init(json j: [String: Any]) {
        func num(_ x: Any?) -> Double? { guard let n = x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }; return n.doubleValue }
        key = j["key"] as? String ?? ""
        agentId = j["agentId"] as? String ?? ""
        sessionId = j["sessionId"] as? String ?? ""
        startedAt = num(j["startedAt"]) ?? 0
        lastEventAt = num(j["lastEventAt"]) ?? 0
        endedAt = num(j["endedAt"])
        state = j["state"] as? String ?? "idle"
        last = j["last"] as? String ?? "sessionStart"
        project = j["project"] as? String ?? ""
        pendingApprovalAt = num(j["pendingApprovalAt"])
        pendingKey = j["pendingKey"] as? String
        nudgedAt = num(j["nudgedAt"])
        ring = (j["ring"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map {
            SKRing(at: num($0["at"]) ?? 0, kind: $0["kind"] as? String ?? "", tool: $0["tool"] as? String ?? "", target: $0["target"] as? String ?? "", file: $0["file"] as? String ?? "", key: $0["key"] as? String ?? "", ok: ($0["ok"] as? Bool) ?? true)
        }
        subagents = (j["subagents"] as? [String: Any] ?? [:]).compactMap { k, v in num(v).map { Sub(id: k, at: $0) } }.sorted { $0.at < $1.at || ($0.at == $1.at && $0.id < $1.id) }
    }

    init(key: String, agentId: String, sessionId: String, startedAt: Double, lastEventAt: Double) {
        self.key = key; self.agentId = agentId; self.sessionId = sessionId; self.startedAt = startedAt; self.lastEventAt = lastEventAt
    }
}

struct SKLedger: Equatable, Sendable {
    var sessions: [SKSession] = []
    var json: [String: Any] { ["sessions": sessions.map(\.json)] }
    init(sessions: [SKSession] = []) { self.sessions = sessions }
    init(json j: Any?) { sessions = ((j as? [String: Any])?["sessions"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map(SKSession.init(json:)) }
}

enum SidekickLedger {
    static let ringMax = 40, sessionsMax = 8, subagentsMax = 20
    static let endedKeepMs = 30 * SK.minute, silentKeepMs = 12 * 60 * SK.minute

    private static let cursorBundle = "com.todesktop.230313mzl4w4u92"
    /// Both the names the relays send and the agents' own.
    private static let eventKind: [String: String] = [
        "SessionStart": "sessionStart", "startup": "sessionStart",
        "UserPromptSubmit": "prompt", "BeforeAgent": "prompt", "PreInvocation": "prompt",
        "PreToolUse": "preTool", "BeforeTool": "preTool",
        "PostToolUse": "tool", "AfterTool": "tool",
        "PostToolUseFailure": "failure",
        "PermissionRequest": "approvalAsked",
        "Stop": "stop", "AfterAgent": "stop", "PostInvocation": "stop", "Interrupt": "stop",
        "StopFailure": "stopFailure",
        "SubagentStart": "subagentStart", "SubagentStop": "subagentStop",
        "SessionEnd": "sessionEnd", "exit": "sessionEnd",
        "Notification": "notification",
    ]
    private static let searchTools: Set<String> = ["WebSearch", "WebFetch", "Grep", "Glob", "google_web_search", "web_fetch", "grep_search", "search_file_content", "glob", "web_search", "grep_files"]
    /// The state a tool puts an agent in: a search tool is searching, any other is working (the cat's rule).
    static func toolState(_ tool: String) -> String { searchTools.contains(tool) ? "searching" : "working" }

    /// Which pill a payload belongs to: a valid `nm_agent` (not "claude"), Codex, Cursor by its bundle ID, else Claude Code.
    private static func agentId(of payload: [String: Any], codex: Bool) -> String {
        let tag = payload["nm_agent"] as? String ?? ""
        if tag == "codex" && codex { return "agent_codex" }
        if tag != "claude" && Rx.test("^[a-z0-9-]{1,24}\\z", tag) { return "agent_" + tag }
        if let b = payload["bundle_id"] as? String, b.lowercased() == cursorBundle { return "agent_cursor" }
        return "integration_claude"
    }

    /// The first 128 code points of a name or an id.
    static func capId(_ s: String) -> String {
        let u = s.unicodeScalars
        guard u.count > 128 else { return s }
        var v = String.UnicodeScalarView(); v.append(contentsOf: u.prefix(128)); return String(v)
    }

    /// A payload's session key: the first non-empty of `session_id` and `conversation_id`, capped (`capId`); "unknown" when neither. The ledger keys its sessions by it, and so does the focus mark
    /// (FocusAwareApp), so a stepped-back session and its ledger entry are the same session.
    static func sessionKey(_ p: [String: Any]) -> String {
        capId([p["session_id"], p["conversation_id"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? "unknown")
    }

    /// Turns a hook payload into the event the ledger takes, or nil for an event it does not know, a payload that is not an object and a time that is not finite. `now` is the time the app received it (ms).
    /// `codex` is false in the App Store build. The event holds a basename, a command key and counts, never the prompt, the assistant's text, a command or a path.
    static func eventFrom(_ payload: Any?, now: Double, codex: Bool = true) -> SKEvent? {
        guard let p = payload as? [String: Any], now.isFinite else { return nil }
        let name = p["hook_event_name"] as? String ?? ""
        guard var kind = eventKind[name] else { return nil }
        let tool = (p["tool_name"] as? String).map(capId) ?? ""
        let input = p["tool_input"] as? [String: Any] ?? [:]
        if tool == "AskUserQuestion" && (kind == "preTool" || kind == "approvalAsked") { kind = "question" }
        let cwd = p["cwd"] as? String ?? ""
        var ev = SKEvent(at: now, agentId: agentId(of: p, codex: codex), sessionId: sessionKey(p), kind: kind, name: name, tool: tool, ok: kind != "failure" && kind != "stopFailure", project: cwd.isEmpty ? "" : SK.baseName(cwd))
        if ["tool", "failure", "approvalAsked", "preTool", "question"].contains(kind) {
            let files = SidekickExplain.pathsOf(tool, input)
            ev.key = SK.commandKey(tool: tool, input: input)
            ev.target = files.first.map { SK.baseName($0) } ?? ev.key
            ev.file = files.first.map { SK.baseName($0) } ?? ""
        }
        if kind == "subagentStart" || kind == "subagentStop" { ev.subagentId = (p["agent_id"] as? String).map(capId) ?? "" }
        return ev
    }

    /// The event for the user's click on an approval card: the app makes it (it is not a hook).
    static func approvalAnswered(agentId: String, sessionId: String, now: Double) -> SKEvent {
        SKEvent(at: now, agentId: agentId, sessionId: sessionId, kind: "approvalAnswered")
    }

    /// Drops the sessions that are over: 30 minutes after SessionEnd, 12 hours after the last event of one that never ended.
    static func prune(_ ledger: SKLedger, now: Double) -> SKLedger {
        SKLedger(sessions: ledger.sessions.filter { s in s.endedAt.map { now - $0 <= endedKeepMs } ?? (now - s.lastEventAt <= silentKeepMs) })
    }

    private static func fold(_ s: inout SKSession, _ ev: SKEvent) {
        s.lastEventAt = max(s.lastEventAt, ev.at)
        if !ev.project.isEmpty { s.project = ev.project }
        if ev.kind == "notification" { return }   // only the time of the last event moves: a finished session stays finished
        if s.endedAt != nil && ev.kind != "sessionEnd" { s.endedAt = nil }
        func ring(_ kind: String, tool: String? = nil, target: String? = nil, ok: Bool = true) {
            s.ring.append(SKRing(at: ev.at, kind: kind, tool: tool ?? ev.tool, target: target ?? ev.target, file: ev.file, key: ev.key, ok: ok))
            if s.ring.count > ringMax { s.ring.removeFirst(s.ring.count - ringMax) }
        }
        func clearPending() { s.pendingApprovalAt = nil; s.pendingKey = nil }
        switch ev.kind {
        case "sessionStart": s.state = "idle"; clearPending()
        case "prompt": s.state = "thinking"; clearPending()
        case "preTool": s.state = toolState(ev.tool)
        case "question": s.state = "question"
        case "tool", "failure":
            ring(ev.kind, ok: ev.kind == "tool")
            if let k = s.pendingKey, ev.key == k { clearPending() }
            if s.pendingKey == nil { s.state = "thinking" }   // while another request still waits, the cat stays on it
        case "approvalAsked": ring("approvalAsked"); s.pendingApprovalAt = ev.at; s.pendingKey = ev.key; s.state = "approval"
        case "approvalAnswered": ring("approvalAnswered", tool: "", target: ""); clearPending(); if s.state == "approval" { s.state = "working" }
        case "stop": ring("stop", tool: "", target: ""); s.state = "finished"; clearPending(); s.subagents = []
        case "stopFailure": ring("stopFailure", tool: "", target: "", ok: false); s.state = "error"; clearPending(); s.subagents = []
        case "subagentStart":
            ring("subagentStart", tool: "", target: "")
            if !ev.subagentId.isEmpty && ev.subagentId != "__proto__" {
                if let i = s.subagents.firstIndex(where: { $0.id == ev.subagentId }) { s.subagents[i].at = ev.at } else { s.subagents.append(SKSession.Sub(id: ev.subagentId, at: ev.at)) }
                if s.subagents.count > subagentsMax {
                    let oldest = s.subagents.enumerated().min { $0.element.at < $1.element.at || ($0.element.at == $1.element.at && $0.offset < $1.offset) }!.offset
                    s.subagents.remove(at: oldest)
                }
            }
        case "subagentStop": ring("subagentStop", tool: "", target: ""); s.subagents.removeAll { $0.id == ev.subagentId }
        case "sessionEnd": s.endedAt = ev.at; s.state = "finished"; clearPending(); s.subagents = []
        default: break
        }
        s.last = ev.kind
    }

    /// The ledger after one event. Pure: the ledger it is given is not changed. The key of a session is `agentId|sessionId`. At most 8 sessions are kept (a finished one goes first,
    /// the oldest first), each ring keeps its last 40 entries. An event with a time that is not finite changes nothing.
    static func apply(_ ledger: SKLedger, _ ev: SKEvent) -> SKLedger {
        guard ev.at.isFinite else { return ledger }
        let key = "\(ev.agentId)|\(ev.sessionId)"
        var sessions = prune(ledger, now: ev.at).sessions
        let i = sessions.firstIndex { $0.key == key }
        if i == nil && (ev.kind == "sessionEnd" || ev.kind == "notification") { return SKLedger(sessions: sessions) }   // a pruned or unknown session is not brought back
        var s = i.map { sessions[$0] } ?? SKSession(key: key, agentId: ev.agentId, sessionId: ev.sessionId, startedAt: ev.at, lastEventAt: ev.at)
        fold(&s, ev)
        if let i { sessions[i] = s } else { sessions.append(s) }
        while sessions.count > sessionsMax {
            let victims = sessions.enumerated().filter { $0.element.key != key }
            let pool = victims.filter { $0.element.isDone }
            let from = pool.isEmpty ? victims : pool
            var pick = from[0]
            for v in from.dropFirst() where v.element.lastEventAt < pick.element.lastEventAt { pick = v }
            sessions.remove(at: pick.offset)
        }
        return SKLedger(sessions: sessions)
    }

    /// The sessions that have not ended, as the status answer and the recap's "still working" see them.
    static func live(_ ledger: SKLedger) -> [SKSession] { ledger.sessions.filter { $0.endedAt == nil } }
}
