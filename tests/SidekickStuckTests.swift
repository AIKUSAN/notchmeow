import Foundation

// The four stuck rules against tests/fixtures/sidekick/stuck-cases.json (timelines of hook payloads and probes), the thresholds, and what the fixture cannot write: a time that is not
// finite, a ledger the call must not change, the one-shot timer's deadline moving as the ledger does. Run through scripts/test-sidekick-stuck.sh.

@main
enum SidekickStuckTests {
    typealias S = SidekickStuck
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func number(_ v: Any?) -> Double? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }; return n.doubleValue }

    static func ctx(_ j: Any?) -> SKStuckContext {
        let o = j as? [String: Any] ?? [:]
        // `muted` is an array of kinds; anything else in it, or a `muted` that is not an array, is ignored (the contract says so).
        let muted = (o["muted"] as? [Any])?.compactMap { $0 as? String } ?? []
        return SKStuckContext(ratelimit: o["ratelimit"] as? Bool ?? false, away: o["away"] as? Bool ?? false, cardShown: o["cardShown"] as? Bool ?? false, platform: o["platform"] as? String ?? "mac", muted: muted)
    }

    @MainActor static func main() {
        let fx = CT.fixture("stuck-cases.json", dir: "sidekick")

        CT.section("the thresholds are the contract's")
        let t = fx["thresholds"] as! [String: Any]
        CT.check("loop: 4 of the last 8 calls", [S.loopSame, S.loopCalls], [Int(number(t["LOOP_SAME"])!), Int(number(t["LOOP_CALLS"])!)])
        CT.check("three errors in a row", S.errors, Int(number(t["ERRORS"])!))
        CT.check("ten-minute window, 60 s wait, 5 and 15 minutes quiet, ten minutes for a kitten", [S.windowMs, S.waitMs, S.silentMs, S.silentPreMs, S.kittenMs], ["WINDOW_MS", "WAIT_MS", "SILENT_MS", "SILENT_PRE_MS", "KITTEN_MS"].map { number(t[$0])! })
        CT.check("the app gives up at 115 s on the Mac, 110 s on Windows and Linux", S.giveUpMs, (t["GIVE_UP_MS"] as! [String: Any]).mapValues { number($0)! })
        CT.check("the kinds, in the order they are tried", S.kinds, fx["kinds"] as! [String])

        let cases = rows(fx["cases"])
        CT.section("stuckStep: \(cases.count) timelines, each probe's answer, deadline and words")
        var diffs: [String] = []
        var probes = 0
        for c in cases {
            var ledger = SKLedger()
            for st in rows(c["steps"]) {
                let at = number(st["at"])!
                if let p = st["payload"] {
                    if let ev = SidekickLedger.eventFrom(p, now: at) { ledger = SidekickLedger.apply(ledger, ev) }
                    continue
                }
                probes += 1
                let probe = st["probe"] as? [String: Any] ?? [:]
                let cx = ctx(probe["ctx"])
                let r = S.step(ledger, now: at, ctx: cx)
                let label = "\(c["name"] as! String) @\(at)"
                if r.nudge?.kind != st["expect"] as? String { diffs.append("\(label): kind \(r.nudge?.kind ?? "nil"), want \(st["expect"] ?? "nil")") }
                if st.keys.contains("nextAt") {
                    let want = number(st["nextAt"])
                    if r.nextAt != want { diffs.append("\(label): nextAt \(String(describing: r.nextAt)), want \(String(describing: want))") }
                }
                if let words = st["text"] as? String {
                    let got = r.nudge.map { S.text($0, ledger, now: at, platform: cx.platform) }
                    if got != words { diffs.append("\(label): text \(got ?? "nil"), want \(words)") }
                }
                if probe["mark"] as? Bool == true, let n = r.nudge { ledger = S.markNudged(ledger, key: n.key, now: at) }
            }
        }
        CT.checkRows("every probe gives the fixture's answer (\(probes) probes)", diffs)

        CT.section("what the fixture cannot write")
        func session(state: String = "working", last: String = "tool", lastEventAt: Double = 1000, agent: String = "integration_claude") -> SKLedger {
            var s = SKSession(key: "\(agent)|S", agentId: agent, sessionId: "S", startedAt: 0, lastEventAt: lastEventAt)
            s.state = state; s.last = last
            return SKLedger(sessions: [s])
        }
        let quiet = session()
        CT.check("a time that is not finite gives nothing", [S.step(quiet, now: .nan), S.step(quiet, now: .infinity)], [SKStuckResult(nudge: nil, nextAt: nil), SKStuckResult(nudge: nil, nextAt: nil)])
        let silentNudge = SKNudge(kind: "stuck.silent", reasonId: "silent", key: "integration_claude|S", agentId: "integration_claude")
        CT.check("the words of a nudge for a time that is not finite do not trap", [S.text(silentNudge, quiet, now: .nan), S.text(silentNudge, quiet, now: .infinity)], ["Claude Code has been quiet for 0 minutes.", "Claude Code has been quiet for 0 minutes."])
        CT.check("the quiet rule falls due 5 minutes after the last step, and the timer is told", S.step(quiet, now: 2000).nextAt, 1000 + 5 * 60000)
        CT.check("at that time it fires", S.step(quiet, now: 1000 + 5 * 60000).nudge?.kind, "stuck.silent")
        CT.check("no live session, no deadline: the clock is not set", S.step(SKLedger(), now: 1).nextAt, nil)
        CT.check("a finished session sets no deadline", S.step(session(state: "finished"), now: 2000).nextAt, nil)
        CT.check("away or rate-limited: nothing and no deadline", [S.step(quiet, now: 2000, ctx: SKStuckContext(away: true)).nextAt, S.step(quiet, now: 2000, ctx: SKStuckContext(ratelimit: true)).nextAt], [nil, nil])
        let before = quiet
        _ = S.markNudged(quiet, key: "integration_claude|S", now: 5)
        CT.check("markNudged does not change the ledger it is given", quiet, before)
        CT.check("a nudged session is not nudged again", S.step(S.markNudged(quiet, key: "integration_claude|S", now: 5), now: 1000 + 6 * 60000).nudge, nil)
        // A loop that holds, in a session that has also gone quiet: what a muted kind does to the choice and to the clock.
        let loopy: SKLedger = {
            var l = session()
            l.sessions[0].ring = (0..<4).map { SKRing(at: 1000 + Double($0) * 1000, kind: "tool", tool: "Bash", target: "", file: "", key: "tool#same", ok: true) }
            l.sessions[0].lastEventAt = 4000
            return l
        }()
        let quietAt = 4000 + 5 * 60000.0
        CT.check("the loop comes first when nothing is muted", S.step(loopy, now: 5000).nudge?.kind, "stuck.loop")
        CT.check("a muted loop gives the quiet rule its turn: nothing yet, and the clock is told", S.step(loopy, now: 5000, ctx: SKStuckContext(muted: ["stuck.loop"])), SKStuckResult(nudge: nil, nextAt: quietAt))
        CT.check("a muted loop: the quiet nudge fires for the same session when it falls due", S.step(loopy, now: quietAt, ctx: SKStuckContext(muted: ["stuck.loop"])).nudge?.kind, "stuck.silent")
        CT.check("a muted quiet rule is left out of the deadline", S.step(loopy, now: 5000, ctx: SKStuckContext(muted: ["stuck.silent"])).nextAt, nil)
        CT.check("and never fires", S.step(loopy, now: quietAt, ctx: SKStuckContext(muted: ["stuck.loop", "stuck.silent"])).nudge?.kind, nil)
        CT.check("every kind muted: nothing and no deadline", S.step(loopy, now: 5000, ctx: SKStuckContext(muted: S.kinds)), SKStuckResult(nudge: nil, nextAt: nil))
        CT.check("a kind that is not one of the four, and a duplicate, mute nothing more", S.step(loopy, now: 5000, ctx: SKStuckContext(muted: ["recap", "nope", "stuck.silent", "stuck.silent"])).nudge?.kind, "stuck.loop")
        var waiting = session(state: "approval", last: "approvalAsked")
        waiting.sessions[0].pendingApprovalAt = 2000
        CT.check("a muted waiting is left out of the deadline", [S.step(waiting, now: 3000).nextAt, S.step(waiting, now: 3000, ctx: SKStuckContext(muted: ["stuck.waiting"])).nextAt], [62000, nil])
        CT.check("and gives no nudge when it falls due, while unmuted it does", [S.step(waiting, now: 63000).nudge?.kind, S.step(waiting, now: 63000, ctx: SKStuckContext(muted: ["stuck.waiting"])).nudge?.kind], ["stuck.waiting", nil])
        CT.check("a platform that is not known is the Mac", S.text(SKNudge(kind: "stuck.waiting", reasonId: "waiting", key: "k", agentId: "agent_codex"), SKLedger(), now: 0, platform: "plan9"), "Codex is still waiting for your OK.")
        CT.finish()
    }
}
