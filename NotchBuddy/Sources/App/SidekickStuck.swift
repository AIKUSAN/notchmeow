import Foundation

// When does an agent look stuck. Port of `stuckStep`, `markNudged` and `nudgeText` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/stuck-cases.json pins them and
// docs/SIDEKICK-CONTRACT.md explains them. Four rules, at most one nudge at a time, one nudge per session, and the time the next deadline falls due, for the app's ONE one-shot timer
// (like `CatSleepClock`): `stuck.loop` and `stuck.errors` are looked at when an event arrives and need no timer, `stuck.waiting` and `stuck.silent` have a deadline. It reads the
// ledger, never changes it, and labels only. Pure Foundation.

struct SKNudge: Equatable, Sendable {
    /// stuck.loop, stuck.errors, stuck.waiting or stuck.silent: they are the kinds of dismissal too.
    var kind: String
    var reasonId: String
    /// The session's ledger key (`agentId|sessionId`).
    var key: String
    var agentId: String
}

/// What the app knows that the ledger does not: the cat shows the rate limit, the user is away, and the waiting nudge is for a request whose card is not on screen.
struct SKStuckContext: Equatable, Sendable {
    var ratelimit = false
    var away = false
    var cardShown = false
    /// "mac", "windows" or "linux" (anything else is the Mac): when the app gave up on the request.
    var platform = "mac"
    /// The nudge kinds the user muted. `step` skips them when it chooses the nudge (a muted loop must not hide a quiet session) and leaves a muted waiting or quiet deadline out of `nextAt`.
    /// Anything that is not one of the four kinds (`recap`, a typo) mutes nothing.
    var muted: [String] = []
}

struct SKStuckResult: Equatable, Sendable {
    var nudge: SKNudge?
    /// The earliest future deadline of the waiting and quiet rules, for the one-shot timer; nil when nothing is live (the clock is then not set).
    var nextAt: Double?
}

enum SidekickStuck {
    static let loopCalls = 8, loopSame = 4, errors = 3
    static let windowMs = 10 * SK.minute, waitMs = 60000.0, silentMs = 5 * SK.minute, silentPreMs = 15 * SK.minute, kittenMs = 10 * SK.minute
    static let giveUpMs: [String: Double] = ["mac": 115000, "windows": 110000, "linux": 110000]
    /// The kinds in the order they are tried when two fire together.
    static let kinds = ["stuck.loop", "stuck.errors", "stuck.waiting", "stuck.silent"]
    private static let active: Set<String> = ["thinking", "working", "searching"]
    private static let writeSet = SidekickExplain.writeTools.union(["apply_patch"])

    private static func isCall(_ r: SKRing) -> Bool { r.kind == "tool" || r.kind == "failure" }

    /// The same tool and key four times in the last eight calls, within ten minutes, with no successful edit or write after the first of them.
    static func loopFires(_ s: SKSession, now: Double) -> Bool {
        guard active.contains(s.state), now - s.lastEventAt <= windowMs else { return false }
        let calls = Array(s.ring.enumerated().filter { isCall($0.element) }.suffix(loopCalls))
        guard calls.count >= loopSame, let newest = calls.last else { return false }
        let inWindow = calls.filter { newest.element.at - $0.element.at <= windowMs }
        var order: [String] = [], groups: [String: [(offset: Int, element: SKRing)]] = [:]
        for r in inWindow where !r.element.tool.isEmpty {
            let k = "\(r.element.tool)\u{0}\(r.element.key)"
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(r)
        }
        for k in order {
            let members = groups[k]!
            if members.count < loopSame { continue }
            let after = s.ring[(members[0].offset + 1)...]
            if !after.contains(where: { $0.kind == "tool" && $0.ok && writeSet.contains($0.tool) }) { return true }
        }
        return false
    }

    /// Three failures in a row, within ten minutes, with no success between. Claude Code only: the other agents send no failure event.
    static func errorsFire(_ s: SKSession, now: Double) -> Bool {
        guard s.agentId == "integration_claude", active.contains(s.state) else { return false }
        let last = s.ring.filter(isCall).suffix(errors)
        guard last.count == errors, last.allSatisfy({ $0.kind == "failure" }), let first = last.first, let end = last.last else { return false }
        return end.at - first.at <= windowMs && now - end.at <= windowMs
    }

    static func waitingDue(_ s: SKSession) -> Double? { s.state == "approval" ? s.pendingApprovalAt.map { $0 + waitMs } : nil }

    /// When the quiet rule is due: 5 minutes after a finished step, a prompt or a subagent's stop, 15 after a step that began and never ended; never while a kitten is under 10 minutes old.
    static func silentDue(_ s: SKSession) -> Double? {
        guard active.contains(s.state) else { return nil }
        let gap: Double
        if s.last == "preTool" { gap = silentPreMs } else if ["tool", "failure", "prompt", "subagentStop"].contains(s.last) { gap = silentMs } else { return nil }
        return max(s.lastEventAt + gap, s.subagents.map(\.at).max().map { $0 + kittenMs } ?? 0)
    }

    /// At most one nudge, and when the next one could fall due. Each session is nudged once (`nudgedAt`). Nothing is said while the user is away or the agent is rate-limited, and then no deadline
    /// is given either: the caller asks again when that ends. The waiting deadline is left out while its card is on screen; the caller asks again when the card hides.
    /// A kind in `ctx.muted` is not chosen (the next-ranked kind that is due can fire for the same session) and its deadline is not given.
    static func step(_ ledger: SKLedger, now: Double, ctx: SKStuckContext = SKStuckContext()) -> SKStuckResult {
        var out = SKStuckResult(nudge: nil, nextAt: nil)
        guard now.isFinite, !ctx.ratelimit, !ctx.away else { return out }
        let off = Set(ctx.muted)
        let loopOff = off.contains(kinds[0]), errorsOff = off.contains(kinds[1]), waitingOff = off.contains(kinds[2]), silentOff = off.contains(kinds[3])
        var best: (rank: Int, s: SKSession)?
        for s in ledger.sessions {
            if s.endedAt != nil || s.nudgedAt != nil { continue }
            let wd = waitingDue(s), sd = silentDue(s)
            let fired: Int? = !loopOff && loopFires(s, now: now) ? 0 : !errorsOff && errorsFire(s, now: now) ? 1
                : (!waitingOff && wd.map { now >= $0 } == true && !ctx.cardShown) ? 2 : (!silentOff && sd.map { now >= $0 } == true) ? 3 : nil
            if let fired, best == nil || fired < best!.rank { best = (fired, s) }
            for due in [ctx.cardShown || waitingOff ? nil : wd, silentOff ? nil : sd] {
                if let due, due > now, out.nextAt == nil || due < out.nextAt! { out.nextAt = due }
            }
        }
        if let best {
            let kind = kinds[best.rank]
            out.nudge = SKNudge(kind: kind, reasonId: String(kind.dropFirst(6)), key: best.s.key, agentId: best.s.agentId)
        }
        return out
    }

    /// The ledger with that session marked as nudged: it gets no second nudge.
    static func markNudged(_ ledger: SKLedger, key: String, now: Double) -> SKLedger {
        SKLedger(sessions: ledger.sessions.map { s in var c = s; if s.key == key { c.nudgedAt = now }; return c })
    }

    /// The words of a nudge: a fixed template with the agent's name and a whole number of minutes. The waiting line switches to the terminal line once the platform's give-up time has passed.
    static func text(_ nudge: SKNudge, _ ledger: SKLedger, now: Double, platform: String = "mac") -> String {
        let s = ledger.sessions.first { $0.key == nudge.key }
        let agent = SK.agentName(nudge.agentId)
        switch nudge.kind {
        case "stuck.loop": return "\(agent) has run the same step \(loopSame) times."
        case "stuck.errors": return "\(agent) hit \(errors) errors in a row."
        case "stuck.waiting":
            let giveUp = giveUpMs[platform] ?? giveUpMs["mac"]!
            if let s, let at = s.pendingApprovalAt, now - at >= giveUp { return "\(agent) is waiting for your OK in the terminal." }
            return "\(agent) is still waiting for your OK."
        case "stuck.silent": return "\(agent) has been quiet for \(s.map { now.isFinite ? Int(((now - $0.lastEventAt) / SK.minute).rounded(.down)) : 0 } ?? 0) minutes."
        default: return ""
        }
    }
}
