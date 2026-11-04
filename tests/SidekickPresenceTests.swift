import Foundation

// The presence rule and the show gate against tests/fixtures/sidekick/presence-cases.json and show-cases.json, and what the fixture cannot write (a time that is not finite, a signal
// nobody knows). Run through scripts/test-sidekick-presence.sh.

@main
enum SidekickPresenceTests {
    typealias P = SidekickPresence
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func number(_ v: Any?) -> Double? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }; return n.doubleValue }

    /// The fixture's signal, or nil when it is not one the app has (not an object, an unknown type, an idle with no number of seconds).
    static func signal(_ raw: Any?) -> SKSignal? {
        guard let o = raw as? [String: Any], let type = o["type"] as? String else { return nil }
        switch type {
        case "lock": return .lock
        case "unlock": return .unlock
        case "sleep": return .sleep
        case "wake": return .wake
        case "displayOff": return .displayOff
        case "displayOn": return .displayOn
        case "idle": return number(o["seconds"]).map { .idle(seconds: $0) }
        default: return nil
        }
    }

    static func state(_ raw: Any?) -> SKPresence {
        let o = raw as? [String: Any] ?? [:]
        return SKPresence(reasons: (o["reasons"] as? [Any] ?? []).compactMap { $0 as? String }.filter(P.order.contains), awaySince: number(o["awaySince"]), wasAway: false)
    }

    static func json(_ s: SKPresence) -> [String: Any] { ["reasons": s.reasons, "awaySince": s.awaySince as Any? ?? NSNull(), "wasAway": s.wasAway] }

    static func showInput(_ raw: Any?) -> SKShowInput {
        let o = raw as? [String: Any] ?? [:]
        var i = SKShowInput()
        i.on = (o["on"] as? Bool) != false
        i.kind = o["kind"] as? String ?? ""
        i.dismissals = SidekickSettings.cleanDismissals(o["dismissals"])
        i.away = (o["away"] as? Bool) == true
        i.ratelimit = (o["ratelimit"] as? Bool) == true
        i.card = o["card"] as? String
        i.ownCard = (o["ownCard"] as? Bool) == true
        i.inputFocused = (o["inputFocused"] as? Bool) == true
        if let v = o["visible"] as? [String: Any] { i.visible = SKShowInput.Visible(kind: v["kind"] as? String, seen: (v["seen"] as? Bool) == true) }
        i.lastShownAt = number(o["lastShownAt"])
        i.now = number(o["now"])
        i.nudged = (o["nudged"] as? Bool) == true
        i.recapGiven = (o["recapGiven"] as? Bool) == true
        return i
    }

    @MainActor static func main() {
        let px = CT.fixture("presence-cases.json", dir: "sidekick"), sx = CT.fixture("show-cases.json", dir: "sidekick")

        CT.section("the thresholds")
        let idle = px["idle"] as! [String: Any]
        CT.check("300 s without input is away, under 3 s is back", [P.awaySeconds, P.backSeconds], [number(idle["AWAY_S"])!, number(idle["BACK_S"])!])
        CT.check("a nudge is held 30 s, a recap 2 minutes, and notes are 60 s apart", [SidekickGate.holdMs["nudge"]!, SidekickGate.holdMs["recap"]!, SidekickGate.noteGapMs], [30000, 120000, 60000] as [Double])
        let hold = sx["holdMs"] as! [String: Any]
        CT.check("the same numbers as the fixture", [number(hold["nudge"])!, number(hold["recap"])!, number(sx["noteGapMs"])!], [30000, 120000, 60000] as [Double])

        let cases = rows(px["cases"])
        CT.section("presenceStep: \(cases.count) cases, the state and the back after every signal")
        var diffs: [String] = []
        for c in cases {
            var s = state(c["start"])
            for (i, st) in rows(c["steps"]).enumerated() {
                let now = number(st["at"]) ?? .nan
                let r = P.step(s, signal(st["signal"]), now: now)
                s = r.state
                var d = CT.diffs(json(s), st["state"]!)
                let back: Any = r.back.map { ["back": true, "awaySince": $0.awaySince, "awayMs": $0.awayMs] as [String: Any] } ?? false
                d += CT.diffs(back, st["back"]!)
                if !d.isEmpty { diffs.append("\(c["name"] as! String) step \(i): \(d.first!)") }
            }
        }
        CT.checkRows("every step is the fixture's", diffs)

        let shows = rows(sx["cases"])
        CT.section("shouldShow: \(shows.count) cases, show, reason and replace each")
        diffs = []
        for c in shows {
            let got = SidekickGate.shouldShow(showInput(c["input"]))
            let d = CT.diffs(got.json, c["show"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every decision is the fixture's", diffs)

        CT.section("what the fixture cannot write")
        let r1 = P.step(SKPresence(), .lock, now: .nan)
        CT.check("a time that is not finite changes nothing", r1.state, SKPresence())
        CT.check("an idle sample that is not finite changes nothing", P.step(SKPresence(), .idle(seconds: .nan), now: 5).state, SKPresence())
        CT.check("a signal nobody knows (nil) changes nothing", P.step(SKPresence(reasons: ["lock"], awaySince: 5), nil, now: 9).state, SKPresence(reasons: ["lock"], awaySince: 5, wasAway: true))
        let night = [SKSignal.lock, .displayOff, .sleep, .wake, .displayOn, .unlock]
        var s = SKPresence(), back: SKBack?
        for (i, sig) in night.enumerated() { let r = P.step(s, sig, now: Double(1000 + i * 1000)); s = r.state; back = r.back ?? back }
        CT.check("a whole night is one back, told once, from the first lock", back, SKBack(awaySince: 1000, awayMs: 5000))

        CT.section("the Mac's notifications become events only when something changes")
        var f = SKPresenceFlags()
        CT.check("a screen lock is a lock", f.set(.screenLock, true), .lock)
        CT.check("the session switch that comes with it is not another lock", f.set(.session, true), nil)
        CT.check("one of them letting go does not unlock while the other holds", f.set(.screenLock, false), nil)
        CT.check("the last one unlocks", f.set(.session, false), .unlock)
        CT.check("an unlock again is nothing", f.set(.session, false), nil)
        CT.check("the displays sleep and wake", [f.set(.display, true), f.set(.display, true), f.set(.display, false)], [.displayOff, nil, .displayOn])
        CT.check("the Mac sleeps and wakes", [f.set(.system, true), f.set(.system, false), f.set(.system, false)], [.sleep, .wake, nil])
        CT.check("each event is the presence rule's signal", [SKPresenceFlags.Event.lock, .unlock, .displayOff, .displayOn, .sleep, .wake].map(\.signal), [.lock, .unlock, .displayOff, .displayOn, .sleep, .wake])
        CT.check("the flags tell what holds now", { var g = SKPresenceFlags(); _ = g.set(.session, true); _ = g.set(.display, true); return [g.locked, g.displayOff, g.asleep] }(), [true, true, false])

        CT.section("the idle sample: on a tick that already exists, and only while an agent has a live session")
        typealias I = SidekickIdle
        CT.check("no live session: never asked", I.sampleDue(now: 100_000, last: nil, liveSessions: false, idleAway: false), false)
        CT.check("the first sample is due at once", I.sampleDue(now: 100_000, last: nil, liveSessions: true, idleAway: false), true)
        CT.check("not again under 5 s", I.sampleDue(now: 104_999, last: 100_000, liveSessions: true, idleAway: false), false)
        CT.check("5 s later", I.sampleDue(now: 105_000, last: 100_000, liveSessions: true, idleAway: false), true)
        CT.check("while the user is away by idle it is every second", [I.sampleDue(now: 100_999, last: 100_000, liveSessions: true, idleAway: true), I.sampleDue(now: 101_000, last: 100_000, liveSessions: true, idleAway: true)], [false, true])
        CT.check("a clock that went backwards samples again", I.sampleDue(now: 50_000, last: 100_000, liveSessions: true, idleAway: false), true)
        CT.check("a time that is not finite is never due", [I.sampleDue(now: .nan, last: nil, liveSessions: true, idleAway: false), I.sampleDue(now: 5, last: .nan, liveSessions: false, idleAway: false)], [false, false])
        CT.finish()
    }
}
