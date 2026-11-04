import Foundation

// What happened while the user was away, and what the agents are doing now, in fixed sentences. Port of `recapOf`, `statusOf` and `matchStatusQuestion` in `shared/sidekick-core.js` (the
// tie-breaker); tests/fixtures/sidekick/recap-cases.json and status-cases.json pin them and docs/SIDEKICK-CONTRACT.md explains them. A line is a template filled with an agent's
// name, a project's basename, counts and up to three file basenames: never a command, a path or a word of the agent. `facts` is the same in numbers and names, and is the only thing the
// local voice may be given. Pure Foundation.

struct SKFacts: Equatable, Sendable {
    var agent: String
    var agentId: String
    var project: String
    var steps: Int
    var stepsAtLeast: Bool
    var files: [String]
    var more: Int
    var errors: Int
    var approvals: Int
    /// finished, waiting, error, question, quiet or working.
    var end: String
    var quietMinutes: Int

    var json: [String: Any] {
        ["agent": agent, "agentId": agentId, "project": project, "steps": steps, "stepsAtLeast": stepsAtLeast, "files": files, "more": more, "errors": errors, "approvals": approvals, "end": end, "quietMinutes": quietMinutes]
    }
}

struct SKLines: Equatable, Sendable {
    var lines: [String]
    var facts: [SKFacts]
    var json: [String: Any] { ["lines": lines, "facts": facts.map(\.json)] }
}

enum SidekickRecap {
    static let minAwayMs = 2 * SK.minute, maxLines = 3, maxFiles = 3, statusFinishedMs = 10 * SK.minute
    private static let active: Set<String> = ["thinking", "working", "searching"]
    private static let writeSet = SidekickExplain.writeTools.union(["apply_patch"])

    private static func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
    private static func isCall(_ r: SKRing) -> Bool { r.kind == "tool" || r.kind == "failure" }

    /// How a session stands now: finished, waiting (for an OK), question, error, quiet (active, with nothing heard for 5 minutes) or working.
    private static func endOf(_ s: SKSession, now: Double) -> String {
        if s.state == "approval" && s.pendingApprovalAt != nil { return "waiting" }
        if s.state == "question" { return "question" }
        if s.state == "error" { return "error" }
        if s.state == "finished" { return "finished" }
        return active.contains(s.state) && s.lastEventAt.isFinite && now - s.lastEventAt >= SidekickStuck.silentMs ? "quiet" : "working"
    }

    /// What one agent did since `since` (ms; 0 for everything the ledger holds), over all its sessions: counts, up to three file names, and how it stands.
    private static func factsOf(_ sessions: [SKSession], since: Double, now: Double) -> (facts: SKFacts, lastEventAt: Double) {
        let entries = sessions.flatMap { $0.ring.filter { $0.at >= since } }
        var files: [String] = []
        for r in entries where r.kind == "tool" && r.ok && writeSet.contains(r.tool) && !r.file.isEmpty && !files.contains(r.file) { files.append(r.file) }
        var rep = sessions[0]
        for s in sessions.dropFirst() where s.lastEventAt > rep.lastEventAt { rep = s }
        let end = endOf(rep, now: now)
        let atLeast = sessions.contains { $0.ring.count >= SidekickLedger.ringMax && $0.ring[0].at >= since }
        let f = SKFacts(agent: SK.agentName(rep.agentId), agentId: rep.agentId, project: rep.project, steps: entries.filter(isCall).count, stepsAtLeast: atLeast,
                        files: Array(files.prefix(maxFiles)), more: max(0, files.count - maxFiles), errors: entries.filter { $0.kind == "failure" }.count,
                        approvals: entries.filter { $0.kind == "approvalAsked" }.count, end: end, quietMinutes: end == "quiet" ? Int(((now - rep.lastEventAt) / SK.minute).rounded(.down)) : 0)
        return (f, rep.lastEventAt)
    }

    private static func nameList(_ f: SKFacts) -> String {
        if f.more > 0 { return "\(f.files.joined(separator: ", ")) and \(f.more) more" }
        if f.files.count > 1 { return "\(f.files.dropLast().joined(separator: ", ")) and \(f.files.last!)" }
        return f.files.first ?? ""
    }

    private static let tail = ["finished": "finished", "waiting": "is waiting for your OK", "error": "stopped on an error", "question": "is waiting for your answer", "working": "is still working"]

    /// The rest of a line after the subject: what it ran, in brackets what went wrong or was asked, the files it edited, and how it stands.
    private static func lineBody(_ f: SKFacts, has: String) -> String {
        let subject = f.project.isEmpty ? f.agent : "\(f.agent) in \(f.project)"
        let end = f.end == "quiet" ? "has been quiet for \(plural(f.quietMinutes, "minute", "minutes"))" : tail[f.end] ?? ""
        if f.steps == 0 && f.approvals == 0 { return "\(subject) \(end)." }
        let did = f.steps > 0 ? "\(has)\(f.stepsAtLeast ? "\(SidekickLedger.ringMax) or more steps" : plural(f.steps, "step", "steps"))" : "asked for \(plural(f.approvals, "approval", "approvals"))"
        var counts: [String] = []
        if f.errors > 0 { counts.append(plural(f.errors, "error", "errors")) }
        if f.steps > 0 && f.approvals > 0 { counts.append("\(plural(f.approvals, "approval", "approvals")) asked") }
        let edited = f.files.isEmpty ? "" : ", edited \(nameList(f))"
        return "\(subject) \(did)\(counts.isEmpty ? "" : " (\(counts.joined(separator: ", ")))")\(edited)\(edited.isEmpty ? "" : ",") and \(end)."
    }

    /// Groups sessions by agent, the agent that spoke last first, and writes at most three lines, then "+N more".
    private static func linesOf(_ groups: [[SKSession]], prefix: String, has: String, now: Double, since: Double) -> SKLines {
        let facts = groups.map { factsOf($0, since: since, now: now) }.sorted { $0.lastEventAt != $1.lastEventAt ? $0.lastEventAt > $1.lastEventAt : $0.facts.agentId < $1.facts.agentId }
        var lines = facts.prefix(maxLines).map { prefix + lineBody($0.facts, has: has) }
        if facts.count > maxLines { lines.append("+\(facts.count - maxLines) more") }
        return SKLines(lines: lines, facts: facts.map(\.facts))
    }

    private static func byAgent(_ sessions: [SKSession]) -> [[SKSession]] {
        var order: [String] = [], m: [String: [SKSession]] = [:]
        for s in sessions { if m[s.agentId] == nil { order.append(s.agentId) }; m[s.agentId, default: []].append(s) }
        return order.map { m[$0]! }
    }

    /// What happened while the user was away, or nil when the away time was under two minutes or no agent did anything in it (a recap is never "nothing happened"). It looks only at ring entries at or after `awaySince`.
    static func recap(awaySince: Double, now: Double, sessions: [SKSession]) -> SKLines? {
        guard awaySince.isFinite, now.isFinite, now - awaySince >= minAwayMs else { return nil }
        let groups = byAgent(sessions).map { $0.filter { s in s.ring.contains { $0.at >= awaySince } } }.filter { !$0.isEmpty }
        if groups.isEmpty { return nil }
        return linesOf(groups, prefix: "While you were away, ", has: "ran ", now: now, since: awaySince)
    }

    /// The answer to "What's Claude doing?": the same templates over everything the ledger holds, for the live sessions (a finished one for 10 minutes), or for one agent.
    static func status(now: Double, sessions: [SKSession], agent: String? = nil) -> SKLines {
        let named = agent.flatMap { $0.isEmpty ? nil : $0 }
        let none = SKLines(lines: [named.map { "\(SK.agentName($0)) is not running right now." } ?? "No agent is running right now."], facts: [])
        guard now.isFinite else { return none }
        let live = sessions.filter { s in s.endedAt == nil && (s.state != "finished" || now - s.lastEventAt <= statusFinishedMs) && (agent == nil || agent!.isEmpty || s.agentId == agent) }
        if live.isEmpty { return none }
        return linesOf(byAgent(live), prefix: "", has: "has run ", now: now, since: 0)
    }

    private static let agents = ["claude": "integration_claude", "claude code": "integration_claude", "codex": "agent_codex", "gemini": "agent_gemini", "gemini cli": "agent_gemini", "antigravity": "agent_antigravity", "cursor": "agent_cursor"]
    private static let everyone: Set<String> = ["the agents", "my agents", "the agent", "my agent", "everyone", "everybody"]

    /// Is this message the status question? It must be the whole message: a short text that, lower-cased and stripped of punctuation, is "what's claude doing", "what is codex doing",
    /// "what are the agents doing" or "status" (with an optional agent name and an optional "right now"). Anything longer or different is a normal chat message.
    /// `agentId` is nil for "all of them".
    static func matchStatusQuestion(_ text: String) -> (matched: Bool, agentId: String?) {
        guard text.utf16.count <= 80 else { return (false, nil) }
        var t = text.lowercased()
        t = t.replacingOccurrences(of: "[\u{2018}\u{2019}\u{02BC}']", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: " (right )?now\\z", with: "", options: .regularExpression)
        if t == "status" || t == "agent status" || t == "agents status" { return (true, nil) }
        if let m = Rx.groups("^(?:whats|what is) (.+?) doing\\z", t) ?? Rx.groups("^what (?:are|is) (.+?) doing\\z", t), let who = m[1] {
            if let id = agents[who] { return (true, id) }
            if everyone.contains(who) { return (true, nil) }
            return (false, nil)
        }
        if let m = Rx.groups("^(.+) status\\z", t), let who = m[1], let id = agents[who] { return (true, id) }
        return (false, nil)
    }
}
