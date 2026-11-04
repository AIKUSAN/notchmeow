import Foundation

// Tuck the island away (Settings → General → Behavior): the pure rule (IslandTuckAway.swift) and the compact island's one timer in IslandStateMachine, on a clock these tests turn by hand.
// The app's files are not compiled here: where they call these rules is pinned by tests/IslandTuckAwayWiringTests.swift. The Windows and Linux twin is windows/scripts/cat-tests/fsm-tuck.test.mjs.

/// A clock for the tuck-away timer: `now` is the time the rules read, and an armed item runs when `advance` reaches its time (a cancelled item does not run).
@MainActor
final class TuckClock {
    var now: TimeInterval = 10_000
    private var items: [(at: TimeInterval, item: DispatchWorkItem)] = []
    var armed: Int { items.filter { !$0.item.isCancelled }.count }
    func arm(_ delay: TimeInterval, _ item: DispatchWorkItem) { items.append((now + delay, item)) }
    /// Runs the items due within `seconds` from now, in time order, then leaves the clock there. An item may arm another while it runs.
    func advance(_ seconds: TimeInterval) {
        let end = now + seconds
        while let next = items.filter({ !$0.item.isCancelled && $0.at <= end + 1e-9 }).min(by: { $0.at < $1.at }) {
            items.removeAll { $0.item === next.item }
            now = max(now, next.at)
            next.item.perform()
        }
        items.removeAll { $0.item.isCancelled }
        now = end
    }
}

@main
enum IslandTuckAwayTests {
    @MainActor
    static func main() {
        var passed = 0
        func ok(_ cond: Bool, _ name: String) { precondition(cond, name); passed += 1; print("✓ \(name)") }

        // The stored value: "never" unless it is one of the five choices.
        ok(IslandTuckAway.defaultsKey == "island.tuckAway", "the UserDefaults key is island.tuckAway")
        ok(IslandTuckAway.choice(stored: nil) == .never, "nothing stored: never (the default)")
        for raw in ["never", "1", "5", "15", "30"] { ok(IslandTuckAway.choice(stored: raw).rawValue == raw, "stored \"\(raw)\" is that choice") }
        for raw in ["", "7", "10", "Never", " 5", "5 ", "60", "hour"] { ok(IslandTuckAway.choice(stored: raw) == .never, "unknown \"\(raw)\" reads as never") }
        ok(IslandTuckAway.Choice.allCases.map(\.rawValue) == ["never", "1", "5", "15", "30"], "the five choices, in the order Settings shows them")
        ok(IslandTuckAway.Choice.never.minutes == nil, "never has no time")
        ok(IslandTuckAway.Choice.m1.minutes == 1 && IslandTuckAway.Choice.m30.minutes == 30, "the times are minutes")

        // Live: only a pill that is working, thinking, searching or waiting (an approval or a question). An open session that is idle does not count.
        ok(!IslandTuckAway.isLive(pillStates: ["idle", "idle"]), "idle pills: not live")
        for s in ["working", "thinking", "searching", "approval", "question"] {
            ok(IslandTuckAway.isLive(pillStates: ["idle", s]), "a pill in \(s): live")
        }
        for s in ["finished", "error", "ratelimit", "sleeping", "dizzy"] {
            ok(!IslandTuckAway.isLive(pillStates: [s]), "a pill in \(s): not live")
        }
        ok(!IslandTuckAway.isLive(pillStates: []), "no pill: not live (an open session alone is not live)")

        // The delay: nil while the island may not hide by itself; otherwise the seconds left, never negative.
        ok(IslandTuckAway.hideDelay(.never, lastActivity: 0, now: 99_999, live: false) == nil, "never: no delay, however long it has been quiet")
        ok(IslandTuckAway.hideDelay(.m5, lastActivity: 0, now: 0, live: true) == nil, "live: no delay")
        ok(IslandTuckAway.hideDelay(.m5, lastActivity: 1000, now: 1000, live: false) == 300, "five minutes from the activity: 300 s")
        ok(IslandTuckAway.hideDelay(.m5, lastActivity: 1000, now: 1120, live: false) == 180, "two minutes in: 180 s left")
        ok(IslandTuckAway.hideDelay(.m5, lastActivity: 1000, now: 1300, live: false) == 0, "the time has passed: 0, hide now")
        ok(IslandTuckAway.hideDelay(.m1, lastActivity: 1000, now: 5000, live: false) == 0, "long past: 0, never negative")

        // The state machine: "Never" (the default) keeps the compact island up for good.
        ok(IslandStateMachine().tuckAway == .never, "the state machine's default is never")
        let (n, nc) = tucked(.never)
        n.reveal()
        nc.advance(3600)
        ok(n.state == .petit && nc.armed == 0, "never: a compact island stays for an hour and arms no timer")
        n.mouseEntered(); n.mouseLeft(); nc.advance(3600)
        ok(n.state == .petit && nc.armed == 0, "never: still up after the pointer comes and goes")

        // One minute: it hides exactly a minute after the last activity, not before.
        let (m, mc) = tucked(.m1)
        m.reveal()
        ok(m.state == .petit && mc.armed == 1, "1 min: up, with exactly one timer armed")
        mc.advance(59)
        ok(m.state == .petit, "1 min: 59 s quiet: still up")
        mc.advance(1)
        ok(m.state == .hidden && mc.armed == 0, "1 min: 60 s quiet: hidden, and no timer is left")

        // A hook event or an alert starts the minute again; the one timer is re-armed, not doubled.
        let (a, ac) = tucked(.m1)
        a.reveal()
        ac.advance(50)
        a.agentActivity()
        ok(a.state == .petit && ac.armed == 1, "an activity at 50 s: still up, still one timer")
        ac.advance(50)
        ok(a.state == .petit, "the minute counts from the activity: at 100 s after the reveal, still up")
        ac.advance(10)
        ok(a.state == .hidden, "...and hidden 60 s after the activity")

        // A wing fold (the pointer leaving the island) neither starts nor shortens the countdown: the one timer is due at the same time.
        let (w, wc) = tucked(.m5)
        w.reveal()
        wc.advance(120)
        w.mouseLeft()
        ok(wc.armed == 1, "5 min: leaving at 2 min arms one timer for what is left (3 min), not a new five")
        wc.advance(179)
        ok(w.state == .petit, "5 min: at 2 min 59 s, still up")
        wc.advance(1)
        ok(w.state == .hidden, "5 min: hidden five minutes after the last activity")

        // The pointer on the island holds it, even past the time; leaving then hides it, since it is due.
        let (p, pc) = tucked(.m1)
        p.reveal()
        p.mouseEntered()
        ok(pc.armed == 0, "the pointer on the island: no timer")
        pc.advance(600)
        ok(p.state == .petit, "the pointer on the island: ten minutes past the time, still up")
        p.mouseLeft()
        pc.advance(0)
        ok(p.state == .hidden, "the pointer leaves an island that is due: hidden at once")

        // A live agent holds it however long it is quiet; when nothing is live the time counts again.
        let (l, lc) = tucked(.m1)
        l.reveal()
        l.setLive(true)
        ok(lc.armed == 0, "a live agent: no timer")
        lc.advance(600)
        ok(l.state == .petit, "a live agent: ten minutes quiet, still up")
        l.setLive(false)
        lc.advance(0)
        ok(l.state == .hidden, "nothing live any more, the minute long past: hidden at once")

        let (l2, l2c) = tucked(.m5)
        l2.reveal()
        l2c.advance(60)
        l2.setLive(true)
        l2c.advance(100)
        l2.setLive(false)
        ok(l2c.armed == 1, "nothing live again with 4 min to go: one timer for those 4 min")
        l2c.advance(139)
        ok(l2.state == .petit, "...at 4 min less 1 s after the change, still up")
        l2c.advance(1)
        ok(l2.state == .hidden, "...and hidden when the five minutes are up")

        // Changing the setting while the island is up re-arms it at once; back to never cancels it.
        let (s, sc) = tucked(.never)
        s.reveal()
        s.tuckAway = .m1
        ok(sc.armed == 1, "turning a time on arms the timer for the compact island that is up")
        sc.advance(60)
        ok(s.state == .hidden, "...and it hides a minute after the last activity, not a minute after the change")
        let (t, tc) = tucked(.m1)
        t.reveal()
        t.tuckAway = .never
        ok(tc.armed == 0, "turning it to never cancels the timer")
        tc.advance(600)
        ok(t.state == .petit, "...and the island stays")

        // An activity while the island is hidden arms nothing: a reveal is the hook's own call.
        let (h, hc) = tucked(.m1)
        h.agentActivity()
        ok(h.state == .hidden && hc.armed == 0, "an activity while hidden arms nothing")

        // Only one timer at a time, whatever is re-armed.
        let (o, oc) = tucked(.m5)
        o.reveal()
        for _ in 0..<20 { oc.advance(1); o.agentActivity(); o.setLive(false); o.mouseLeft() }
        ok(oc.armed == 1, "twenty activities, live changes and leaves: still exactly one timer")

        // A click on the island counts as activity: it restarts the minute, so the island folded after the click hides a minute after the click.
        let (ck, ckc) = tucked(.m1)
        ck.reveal()
        ckc.advance(50)
        ck.userInteracted()
        ok(ck.state == .petit && ckc.armed == 1, "a click at 50 s: still up, still one timer")
        ckc.advance(50)
        ok(ck.state == .petit, "a click restarts the minute: at 100 s after the reveal, still up")
        ckc.advance(10)
        ok(ck.state == .hidden, "...and hidden 60 s after the click")

        // A hold (a waiting card, a shelf or link hold): a due island stays up, and hides once the hold is released, with no timer in between.
        let (hd, hdc) = tucked(.m1)
        var held = true
        hd.isHeldOpen = { held }
        hd.reveal()
        ok(hdc.armed == 0, "held when it comes up: no timer")
        hdc.advance(600)
        ok(hd.state == .petit, "due while held: still up")
        held = false
        hd.scheduleTuck()
        ok(hd.state == .petit && hdc.armed == 1, "the hold released: the timer is armed again")
        hdc.advance(0)
        ok(hd.state == .hidden, "the hold released with the minute long past: hidden at once")

        // A hold that comes during the minute: the timer fires while held and does not hide the island or arm itself again.
        let (hf, hfc) = tucked(.m1)
        var heldLater = false
        hf.isHeldOpen = { heldLater }
        hf.reveal()
        heldLater = true
        hf.scheduleTuck()
        ok(hfc.armed == 0, "a hold while the timer waits: the timer is not re-armed")
        hfc.advance(60)
        ok(hf.state == .petit && hfc.armed == 0, "the minute runs out while held: still up, no timer left")
        heldLater = false
        hf.scheduleTuck()
        hfc.advance(0)
        ok(hf.state == .hidden, "the hold released: hidden at once")

        // A hold that ends while the setting is Never: nothing is armed, and the island stays up for good.
        let (nv, nvc) = tucked(.never)
        var heldNever = true
        nv.isHeldOpen = { heldNever }
        nv.reveal()
        heldNever = false
        nv.scheduleTuck()
        ok(nv.state == .petit && nvc.armed == 0, "never: a hold that ends arms no timer, and the island stays up")
        nvc.advance(3600)
        ok(nv.state == .petit && nvc.armed == 0, "never: an hour after the hold ended, still up, no timer")

        print("Island tuck away: \(passed) checks passed")
    }

    /// A compact-island state machine on the clock, with the tuck-away setting and the last activity at the clock's start.
    @MainActor
    private static func tucked(_ choice: IslandTuckAway.Choice) -> (IslandStateMachine, TuckClock) {
        let m = IslandStateMachine()
        let clock = TuckClock()
        m.now = { clock.now }
        m.armTuck = { delay, item in clock.arm(delay, item) }
        m.tuckAway = choice
        m.agentActivity()
        return (m, clock)
    }
}
