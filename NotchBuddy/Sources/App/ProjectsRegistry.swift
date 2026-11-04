import Foundation

// The Projects registry (sub-project P-mac): a hook payload becomes an event, the events fold into the registry (the sessions in memory), and a session's
// state is read at a time. A port of shared/projects-core.js (hook events, registry, states; docs/PROJECTS-CONTRACT.md), replayed against
// tests/fixtures/projects/ by scripts/test-projects-registry.sh. Pure Foundation: no clock, no files, no network. An event keeps only the ids and names
// the notch shows: never a prompt, a transcript path, a tool's input or output, or a message.
//
// Porting rules are those of ProjectsRules.swift: a code point is a Unicode scalar, text order is UTF-16, ids compare byte for byte, a JSON boolean is
// a CFBoolean and never a number, and every sort breaks ties on the input index.

struct PJEvent: Equatable, Sendable {
    var at: Double
    var agent: String
    var kind: String
    var sessionId = ""
    var cwd = ""
    var subagentId = ""
    var subagentType = ""
    var fromApp = false
    var termProgram = ""
    var bundleId = ""
    var waitIn = ""
    var stepped = false

    /// The core's keys.
    var json: [String: Any] {
        [
            "at": at, "agent": agent, "kind": kind, "sessionId": sessionId, "cwd": cwd,
            "subagentId": subagentId, "subagentType": subagentType, "fromApp": fromApp,
            "termProgram": termProgram, "bundleId": bundleId, "waitIn": waitIn, "stepped": stepped,
        ]
    }
}

/// An ask still open or closed: an approval or a question, `by` the subagent that asked ("" for the main session).
struct PJPending: Equatable, Sendable {
    var by: String
    var kind: String
    var at: Double
    var inApp: Bool
    var waitIn: String

    var json: [String: Any] {
        ["by": by, "kind": kind, "at": at, "inApp": inApp, "waitIn": waitIn]
    }
}

struct PJSubagent: Equatable, Sendable {
    var id: String
    var type: String
    var state: String
    var born: Double
    var last: Double

    var json: [String: Any] {
        ["id": id, "type": type, "state": state, "born": born, "last": last]
    }
}

struct PJSession: Equatable, Sendable {
    var id: String
    var cwd: String
    var root: String
    var worktree: String
    var seq: Int
    var startedAt: Double
    var lastAt: Double
    var run: String
    var finishedAt: Double?
    var pending: [PJPending]
    var fromApp: Bool
    var termProgram: String
    var bundleId: String
    var subagents: [PJSubagent]

    var json: [String: Any] {
        [
            "id": id, "cwd": cwd, "root": root, "worktree": worktree, "seq": seq,
            "startedAt": startedAt, "lastAt": lastAt, "run": run,
            "finishedAt": ProjectsRegistry.orNull(finishedAt), "pending": pending.map { $0.json },
            "fromApp": fromApp, "termProgram": termProgram, "bundleId": bundleId,
            "subagents": subagents.map { $0.json },
        ]
    }
}

struct PJRegistry: Equatable, Sendable {
    var version = 1
    var home: String
    var sessions: [PJSession] = []
    var otherAgentSeen = false
    var nextSeq = 1

    /// An empty registry for the home folder (normalized; "" when none is given).
    static func empty(home: Any?) -> PJRegistry {
        PJRegistry(home: ProjectsRules.normPath(home))
    }
}

// Lenient readers: a field of the wrong type takes its default, so a stored or hook value never breaks a session.
extension PJPending {
    init(json: [String: Any]) {
        self.init(by: (json["by"] as? String) ?? "", kind: (json["kind"] as? String) ?? "", at: ProjectsRegistry.numOf(json["at"]),
                  inApp: ProjectsRegistry.isTrue(json["inApp"]), waitIn: (json["waitIn"] as? String) ?? "")
    }
}

extension PJSubagent {
    init(json: [String: Any]) {
        self.init(id: (json["id"] as? String) ?? "", type: (json["type"] as? String) ?? "", state: (json["state"] as? String) ?? "working",
                  born: ProjectsRegistry.numOf(json["born"]), last: ProjectsRegistry.numOf(json["last"]))
    }
}

extension PJSession {
    /// The root and the cwd are normalized as the registry holds them (ProjectsRules.normPath).
    init(json: [String: Any]) {
        self.init(id: (json["id"] as? String) ?? "", cwd: ProjectsRules.normPath(json["cwd"]), root: ProjectsRules.normPath(json["root"]),
                  worktree: (json["worktree"] as? String) ?? "", seq: ProjectsRegistry.wholeInt(json["seq"]),
                  startedAt: ProjectsRegistry.numOf(json["startedAt"]), lastAt: ProjectsRegistry.numOf(json["lastAt"]),
                  run: (json["run"] as? String) ?? "idle", finishedAt: ProjectsRegistry.numberOf(json["finishedAt"]),
                  pending: ProjectsRegistry.objects(json["pending"]).map { PJPending(json: $0) },
                  fromApp: ProjectsRegistry.isTrue(json["fromApp"]), termProgram: (json["termProgram"] as? String) ?? "",
                  bundleId: (json["bundleId"] as? String) ?? "",
                  subagents: ProjectsRegistry.objects(json["subagents"]).map { PJSubagent(json: $0) })
    }
}

enum ProjectsRegistry {
    /// Claude Code's hook events and the kind each one is (the core's CLAUDE_EVENTS). Any other name is no event for the registry.
    static let claudeEvents: [String: String] = [
        "SessionStart": "start", "UserPromptSubmit": "prompt", "PreToolUse": "preTool", "PostToolUse": "tool",
        "PostToolUseFailure": "tool", "PermissionRequest": "approval", "Notification": "note", "Stop": "stop",
        "StopFailure": "halt", "Interrupt": "halt", "SubagentStart": "subStart", "SubagentStop": "subStop", "SessionEnd": "end",
    ]
    static let claudeTag = "claude"
    static let claudeAppTag = "claude-desktop"
    static let cursorBundle = "com.todesktop.230313mzl4w4u92"
    static let idMax = 128, subagentTypeMax = 64, waitInMax = 32
    // The contract's CWD_MAX_BYTES and PENDING_MAX (shared/projects-core.js, docs/PROJECTS-CONTRACT.md), replayed from event-cases.json and registry-cases.json. The hook socket takes payloads up to 1 MB and a cwd is compared with
    // every session's root on the main actor before the app answers, so a hostile same-user process could stall it with one long cwd, or grow a session's `pending` with distinct
    // agent_ids (every later event filters it in full). A real path is far under `cwdMaxBytes`, and a session has at most 9 askers (the main agent and `subagentsMax` subagents).
    static let cwdMaxBytes = 4096, pendingMax = 16
    static let questionMark: Unicode.Scalar = "?"
    static let dash: Unicode.Scalar = "-"

    // MARK: - Values from JSON

    /// A JSON boolean (a CFBoolean), never a number 0 or 1.
    static func isJSONBool(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    /// A JSON boolean that is true; anything else is false.
    static func isTrue(_ v: Any?) -> Bool {
        isJSONBool(v) && ((v as? NSNumber)?.boolValue ?? false)
    }

    /// A finite JSON number that is not a boolean; nil for anything else.
    static func numberOf(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, !isJSONBool(n) else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    /// A finite JSON number, else 0 (the core's numOr0).
    static func numOf(_ v: Any?) -> Double {
        numberOf(v) ?? 0
    }

    /// A finite number, else 0.
    static func finite0(_ x: Double) -> Double {
        x.isFinite ? x : 0
    }

    /// A JSON number as a whole number, truncated toward zero, within the safe range; 0 when it is not a number.
    static func wholeInt(_ v: Any?) -> Int {
        let d = numOf(v).rounded(.towardZero)
        return Int(max(-9_007_199_254_740_992, min(9_007_199_254_740_992, d)))
    }

    /// The objects of a JSON list, in order; any other item is dropped (the core's arrOf). Empty when the value is not a list.
    static func objects(_ v: Any?) -> [[String: Any]] {
        guard let list = v as? [Any] else { return [] }
        return list.compactMap { $0 as? [String: Any] }
    }

    /// A value as JSON: the value, or NSNull when there is none.
    static func orNull<T>(_ v: T?) -> Any {
        v.map { $0 as Any } ?? NSNull()
    }

    /// Byte-for-byte equality, as the core's `===` reads text.
    static func same(_ a: String, _ b: String) -> Bool {
        a.utf8.elementsEqual(b.utf8)
    }

    /// Whether `needle` occurs in `hay`, byte for byte (the core's `includes`).
    static func hasText(_ hay: String, _ needle: String) -> Bool {
        let h = Array(hay.utf8), n = Array(needle.utf8)
        guard n.count <= h.count else { return false }
        return (0...(h.count - n.count)).contains { h[$0..<($0 + n.count)].elementsEqual(n) }
    }

    /// A value as an id-like text, cut to `idMax` code points; "" when it is not text.
    static func idText(_ v: Any?) -> String {
        guard let s = v as? String else { return "" }
        return ProjectsRules.cutTo(s, idMax)
    }

    /// A subagent's type as text: invisible characters out, `/` and `\` as `-`, a hard cut at 64 code points (no `…`); "" when not text.
    static func subTypeText(_ v: Any?) -> String {
        guard let s = v as? String else { return "" }
        let cleaned = s.unicodeScalars.filter { !ProjectsRules.isInvisible($0) }.map { ($0 == "/" || $0 == "\\") ? dash : $0 }
        return String(String.UnicodeScalarView(cleaned.prefix(subagentTypeMax)))
    }

    /// `^[a-z0-9-]{1,24}$`: an agent tag (Claude Code's own tag is handled first).
    static func isAgentTag(_ s: String) -> Bool {
        let u = Array(s.unicodeScalars)
        return (1...24).contains(u.count) && u.allSatisfy { c in
            (c.value >= 0x61 && c.value <= 0x7A) || (c.value >= 0x30 && c.value <= 0x39) || c == "-"
        }
    }

    // MARK: - Events

    /// A hook payload as an event, or nil. Claude Code's events need a session id; another agent's event is `kind: "other"` with every other field
    /// empty. `waitIn` is the host a session steps back to: a name, cut to 32 code points, "" when absent, not text or blank. `stepped` is true when the
    /// raw `waitIn` is a non-blank text (so an in-app wait is still one when its host cleans to nothing). A time that is not finite gives nil.
    static func eventFrom(_ payload: Any?, now: Double, waitIn: Any? = nil) -> PJEvent? {
        guard now.isFinite, let p = payload as? [String: Any] else { return nil }
        let tag = (p["nm_agent"] as? String) ?? ""
        let fromApp = tag == claudeAppTag
        let bundle = (p["bundle_id"] as? String)?.lowercased() ?? ""
        var agent = claudeTag
        if !fromApp, tag != claudeTag, isAgentTag(tag) {
            agent = "agent_" + tag
        } else if !fromApp, bundle == cursorBundle {
            agent = "agent_cursor"
        }
        if agent != claudeTag {
            return PJEvent(at: now, agent: agent, kind: "other")
        }
        guard var kind = claudeEvents[(p["hook_event_name"] as? String) ?? ""] else { return nil }
        if kind == "preTool" || kind == "approval", (p["tool_name"] as? String) == "AskUserQuestion" {
            kind = "question"
        }
        if kind == "note", let message = p["message"] as? String, ProjectsRules.jsTrim(message).unicodeScalars.last == questionMark {
            kind = "question"
        }
        let direct = idText(p["session_id"])
        let sessionId = direct.isEmpty ? idText(p["conversation_id"]) : direct
        guard !sessionId.isEmpty else { return nil }
        let stepped = !fromApp && ((waitIn as? String).map { !ProjectsRules.jsTrim($0).isEmpty } ?? false)
        let cwd = (p["cwd"] as? String).flatMap { $0.utf8.count <= cwdMaxBytes ? $0 : nil } ?? ""   // over the cap: read as none (a first-seen ask files under home, other kinds start nothing)
        return PJEvent(at: now, agent: claudeTag, kind: kind, sessionId: sessionId, cwd: cwd,
                       subagentId: idText(p["agent_id"]), subagentType: subTypeText(p["agent_type"]), fromApp: fromApp,
                       termProgram: idText(p["term_program"]), bundleId: idText(p["bundle_id"]),
                       waitIn: fromApp ? "" : ProjectsRules.cutTo(ProjectsRules.hostText(waitIn), waitInMax), stepped: stepped)
    }

    // MARK: - The registry

    /// The time an event or a view reads: `now` when it is finite, else the newest last activity (0 when there is none).
    static func timeOf(_ now: Double?, _ sessions: [PJSession]) -> Double {
        if let n = now, n.isFinite { return n }
        return sessions.reduce(0) { max($0, finite0($1.lastAt)) }
    }

    /// The registry without the sessions 2 h quiet at `now`; a `now` that is not finite prunes nothing.
    static func prune(_ registry: PJRegistry, now: Double) -> PJRegistry {
        guard now.isFinite else { return registry }
        var c = registry
        c.sessions = c.sessions.filter { now - finite0($0.lastAt) < ProjectsRules.removeMs }
        return c
    }

    /// Drops the least of `list` (by `less`) until at most `max` remain; a tie goes to the earlier one (the core's trimTo).
    static func trim<T>(_ list: inout [T], to max: Int, _ less: (T, T) -> Bool) {
        while list.count > max {
            var k = 0
            for i in list.indices.dropFirst() where less(list[i], list[k]) {
                k = i
            }
            list.remove(at: k)
        }
    }

    /// The least recently active session goes first; a tie goes to the earlier start.
    static func lessActive(_ a: PJSession, _ b: PJSession) -> Bool {
        let x = finite0(a.lastAt), y = finite0(b.lastAt)
        return x < y || (x == y && a.seq < b.seq)
    }

    /// The index of the event's session in `c`, made first when the event can start one; nil when it starts nothing.
    private static func sessionIndex(for ev: PJEvent, in c: inout PJRegistry, at: Double) -> Int? {
        if let i = c.sessions.firstIndex(where: { same($0.id, ev.sessionId) }) {
            return i
        }
        if ev.kind == "end" { return nil }
        var cwd = ProjectsRules.normPath(ev.cwd)
        let asks = ev.kind == "approval" || ev.kind == "question"
        // A first-seen ask with no usable folder is filed under the home project, so it is still shown and counted waiting.
        if cwd.isEmpty, asks, !c.home.isEmpty { cwd = c.home }
        if cwd.isEmpty { return nil }
        var roots: [String] = []
        for s in c.sessions where !roots.contains(where: { same($0, s.root) }) {
            roots.append(s.root)
        }
        guard let place = ProjectsRules.projectOf(cwd, roots: roots, home: c.home) else { return nil }
        let seq = c.nextSeq
        c.nextSeq = seq + 1
        c.sessions.append(PJSession(id: ev.sessionId, cwd: cwd, root: place.root, worktree: place.worktree, seq: seq, startedAt: at,
                                    lastAt: at, run: "idle", finishedAt: nil, pending: [], fromApp: false, termProgram: "",
                                    bundleId: "", subagents: []))
        trim(&c.sessions, to: ProjectsRules.sessionsMax, lessActive)
        return c.sessions.firstIndex { $0.seq == seq && same($0.id, ev.sessionId) }
    }

    /// The registry after one event: a new registry, the input never changed. It prunes first at the event's time; a session takes its project from
    /// its first folder and keeps it. An approval or question with a non-blank waitIn is a stepped-back wait (`inApp`, which ends at APP_WAIT_MS).
    static func apply(_ registry: PJRegistry, _ ev: PJEvent) -> PJRegistry {
        let at = timeOf(ev.at, registry.sessions)
        var c = prune(registry, now: at)
        if ev.agent != claudeTag {
            c.otherAgentSeen = true
            return c
        }
        guard let idx = sessionIndex(for: ev, in: &c, at: at) else { return c }
        var s = c.sessions[idx]
        s.lastAt = max(finite0(s.lastAt), at)
        if !ev.termProgram.isEmpty { s.termProgram = ev.termProgram }
        if !ev.bundleId.isEmpty { s.bundleId = ev.bundleId }
        if ev.fromApp { s.fromApp = true }
        let by = ev.subagentId
        let sub: Int? = by.isEmpty ? nil : s.subagents.firstIndex(where: { same($0.id, by) })
        // The subagent that acted, when it is shown: its state and its last activity.
        func touch(_ state: String) {
            guard let k = sub else { return }
            s.subagents[k].state = state
            s.subagents[k].last = max(finite0(s.subagents[k].last), at)
        }
        switch ev.kind {
        case "end":
            c.sessions.remove(at: idx)
            return c
        case "prompt":
            s.run = "working"
            s.pending = []
        case "preTool", "tool":
            s.run = "working"
            s.pending = s.pending.filter { !same($0.by, by) }
            touch("working")
        case "approval", "question":
            s.run = "working"
            s.pending = s.pending.filter { !same($0.by, by) }
            s.pending.append(PJPending(by: by, kind: ev.kind, at: at, inApp: s.fromApp || ev.stepped, waitIn: ev.waitIn))
            if s.pending.count > pendingMax { s.pending.removeFirst(s.pending.count - pendingMax) }   // the newest asks stay (see `pendingMax`)
            touch("approval")
        case "stop":
            s.run = "finished"
            s.finishedAt = at
            s.pending = []
            s.subagents = []
        case "halt":
            s.run = "idle"
            s.finishedAt = nil
            s.pending = []
            s.subagents = []
        case "subStart":
            guard !by.isEmpty else { break }
            if let k = sub {
                s.subagents[k].last = max(finite0(s.subagents[k].last), at)
                if !ev.subagentType.isEmpty { s.subagents[k].type = ev.subagentType }
            } else {
                s.subagents.append(PJSubagent(id: by, type: ev.subagentType, state: "working", born: at, last: at))
                trim(&s.subagents, to: ProjectsRules.subagentsMax) { finite0($0.born) < finite0($1.born) }
            }
        case "subStop":
            guard !by.isEmpty else { break }
            s.subagents = s.subagents.filter { !same($0.id, by) }
            s.pending = s.pending.filter { !same($0.by, by) }
        default:
            break
        }
        c.sessions[idx] = s
        return c
    }

    // MARK: - States in time

    /// An ask still open at `now`: an in-app ask (the Claude App, or a stepped-back wait) lasts APP_WAIT_MS; on a notch card a question lasts
    /// CARD_QUESTION_MS and an approval CARD_APPROVAL_MS. A clock behind the ask counts it as open.
    static func liveAsk(_ e: PJPending, now: Double) -> Bool {
        guard e.kind == "approval" || e.kind == "question" else { return false }
        let wait = e.inApp ? ProjectsRules.appWaitMs : (e.kind == "approval" ? ProjectsRules.cardApprovalMs : ProjectsRules.cardQuestionMs)
        return now - finite0(e.at) < wait
    }

    struct SessionState: Equatable, Sendable {
        var state: String
        var dim: Bool
        var gone: Bool
        var waitingInApp: Bool

        var json: [String: Any] {
            ["state": state, "dim": dim, "gone": gone, "waitingInApp": waitingInApp]
        }
    }

    /// A session's state at `now` (a `now` that is not finite reads the session's own lastAt). The session is not changed.
    static func sessionStateAt(_ s: PJSession, now: Double?) -> SessionState {
        let lastAt = finite0(s.lastAt)
        let t = now.flatMap { $0.isFinite ? $0 : nil } ?? lastAt
        let age = max(0, t - lastAt)
        let dim = age >= ProjectsRules.dimMs, gone = age >= ProjectsRules.removeMs
        let live = s.pending.filter { liveAsk($0, now: t) }
        if !live.isEmpty {
            let state = live.contains { $0.kind == "approval" } ? "approval" : "question"
            return SessionState(state: state, dim: dim, gone: gone, waitingInApp: live.contains { $0.inApp })
        }
        var state = "idle"
        if s.run == "working", age < ProjectsRules.quietIdleMs {
            state = "working"
        } else if s.run == "finished", t - finite0(s.finishedAt ?? 0) < ProjectsRules.finishedMs {
            state = "finished"
        }
        return SessionState(state: state, dim: dim, gone: gone, waitingInApp: false)
    }
}
