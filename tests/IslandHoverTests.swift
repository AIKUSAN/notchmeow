import Foundation

// Open on hover (Settings → General → Behavior): the state machine's rules. The dwell before the island opens is armed through `armHoverOpen`, which these tests replace with a clock they turn
// by hand, so 149 ms and 150 ms can be told apart exactly; the fold after the pointer leaves uses real, short timers. The Windows and Linux twin is windows/scripts/cat-tests/fsm-hover.test.mjs.

/// A clock for the dwell timer: items armed with a delay run when `advance` reaches their time (a cancelled item does not run).
@MainActor
final class HoverClock {
    var now: TimeInterval = 0
    private var items: [(at: TimeInterval, item: DispatchWorkItem)] = []
    var armed: Int { items.filter { !$0.item.isCancelled }.count }
    func arm(_ delay: TimeInterval, _ item: DispatchWorkItem) { items.append((now + delay, item)) }
    func advance(ms: Int) {
        let end = now + Double(ms) / 1000
        for entry in items.sorted(by: { $0.at < $1.at }) where entry.at <= end + 1e-9 { entry.item.perform() }
        items.removeAll { $0.at <= end + 1e-9 }
        now = end
    }
}

@main
enum IslandHoverTests {
    @MainActor
    static func main() async throws {
        var passed = 0
        func ok(_ cond: Bool, _ name: String) { precondition(cond, name); passed += 1; print("✓ \(name)") }

        // Off (the default): hovering only peeks, as before, and arms nothing.
        let (off, offClock) = machine(on: false)
        off.mouseEntered()
        offClock.advance(ms: 1000)
        ok(off.state == .petit && !off.openedByHover && offClock.armed == 0, "open on hover off: hovering only peeks and arms no timer")

        // The dwell: 150 ms by default, 149 ms is not enough, 150 ms opens.
        ok(IslandStateMachine().hoverDwell == 0.15, "the dwell is 150 ms")
        let (a, ac) = machine()
        a.mouseEntered()
        ok(a.state == .petit && ac.armed == 1, "hover peeks at once and arms exactly one dwell timer")
        ac.advance(ms: 149)
        ok(a.state == .petit && !a.openedByHover, "149 ms over the island: no open")
        ac.advance(ms: 1)
        ok(a.state == .home && a.openedByHover, "150 ms over the island: it opens")
        ok(ac.armed == 0, "no timer is left armed once it has opened")

        // Leaving before the dwell is over cancels the open (and leaves the usual peek alone).
        let (b, bc) = machine()
        b.mouseEntered()
        bc.advance(ms: 100)
        b.mouseLeft()
        ok(bc.armed == 0, "leaving at 100 ms cancels the dwell timer")
        bc.advance(ms: 500)
        ok(b.state == .petit && !b.openedByHover, "leaving at 100 ms: the island never opens")

        // Coming back starts the dwell again from zero.
        b.mouseEntered()
        bc.advance(ms: 149)
        ok(b.state == .petit, "a new hover starts a new dwell (149 ms: no open)")
        bc.advance(ms: 1)
        ok(b.state == .home, "a new hover opens after its own 150 ms")

        // The fold: leaving a hover-opened island folds it after the short grace period (real timers, made short).
        let (c, cc) = machine()
        c.hoverCloseDelay = 0.5   // wide: a busy CI runner can sleep 20 ms for much longer than 80
        c.mouseEntered(); cc.advance(ms: 150)
        ok(c.state == .home, "hover-opened")
        c.mouseLeft()
        try await Task.sleep(for: .milliseconds(20))
        ok(c.state == .home, "it does not fold at once")
        try await waitFor(.petit, c, timeout: 3)
        ok(!c.openedByHover, "folded, no longer hover-opened")

        // Coming back before the grace period keeps it open.
        let (d, dc) = machine()
        d.hoverCloseDelay = 0.08
        d.mouseEntered(); dc.advance(ms: 150)
        d.mouseLeft()
        d.mouseEntered()
        try await Task.sleep(for: .milliseconds(150))
        ok(d.state == .home, "coming back before the grace period keeps it open")

        // A click inside turns it into a normal open island: the auto-close delay applies.
        let (e, ec) = machine()
        e.homeToPetitDelay = 1.0
        e.mouseEntered(); ec.advance(ms: 150)
        e.userInteracted()
        e.mouseLeft()
        try await Task.sleep(for: .milliseconds(150))
        ok(e.state == .home, "after a click the short delay no longer applies")
        try await waitFor(.petit, e, timeout: 3)
        ok(e.state == .petit, "after a click the normal auto-close applies")

        // A waiting card holds the island: hover opens it as an ordinary island, never arms the dwell, never folds it.
        let (f, fc) = machine()
        f.isHeldOpen = { true }
        f.mouseEntered()
        ok(f.state == .home && !f.openedByHover && fc.armed == 0, "a waiting card: hover opens it as an ordinary open island and arms no dwell")
        f.mouseLeft()
        try await Task.sleep(for: .milliseconds(150))
        ok(f.state == .home, "a waiting card: the island does not fold")

        // A card that arrives during the dwell stops the dwell from opening anything.
        let (g, gc) = machine()
        g.mouseEntered()
        g.isHeldOpen = { true }
        gc.advance(ms: 150)
        ok(g.state == .petit, "a card that holds the island during the dwell: the dwell opens nothing")

        // An island opened by an alert keeps the normal delay even with hover on.
        let (h, hc) = machine()
        h.homeToPetitDelay = 1.0
        h.openedExternally()
        h.mouseEntered()
        ok(hc.armed == 0, "an island that is already open arms no dwell")
        h.mouseLeft()
        try await Task.sleep(for: .milliseconds(150))
        ok(h.state == .home, "an alert-opened island keeps the normal delay")

        // From a hidden island the same dwell opens it, and an alert during the dwell cancels it.
        let (i, ic) = machine()
        i.mouseEntered()
        i.openedExternally()
        ic.advance(ms: 150)
        ok(i.state == .home && !i.openedByHover, "an alert during the dwell wins: it is not a hover-opened island")

        // The dwell's open is asynchronous: with the pointer still over the island (no mouseLeft yet) it does not start folding, however long it stays.
        let (k, kc) = machine()
        k.hoverCloseDelay = 0.05
        k.homeToPetitDelay = 0.05
        k.mouseEntered(); kc.advance(ms: 150)
        try await Task.sleep(for: .milliseconds(250))
        ok(k.state == .home && k.openedByHover, "opened by the dwell, the pointer still over it: no fold starts")

        // A waiting question or a pin (the hover-only hold) keeps hover from opening, and keeps a hover-opened island from folding.
        let (j, jc) = machine()
        var held = true
        j.isHoverHeld = { held }
        j.mouseEntered(); jc.advance(ms: 150)
        ok(j.state == .petit && !j.openedByHover, "a hover hold (question or pin): hover does not open the island")
        held = false
        j.mouseLeft(); j.mouseEntered(); jc.advance(ms: 150)
        ok(j.state == .home && j.openedByHover, "the hold gone: it opens as usual")
        held = true
        j.hoverCloseDelay = 0.05
        j.mouseLeft()
        try await Task.sleep(for: .milliseconds(200))
        ok(j.state == .home && !j.openedByHover, "a hover hold keeps a hover-opened island open, as an ordinary one")

        // A wing (the compact island's left or right part beside the notch) is a hover-only hold: the pointer there never opens the island, however long it stays.
        let (w, wc) = machine()
        var onWing = true
        w.isHoverHeld = { onWing }
        w.mouseEntered()
        ok(w.state == .petit && wc.armed == 0, "on a wing: hover still peeks and arms no dwell")
        wc.advance(ms: 150)
        ok(w.state == .petit && !w.openedByHover, "on a wing: 150 ms and no open")
        wc.advance(ms: 850)
        ok(w.state == .petit && !w.openedByHover, "on a wing: 1 s and no open")
        // Moving into the notch zone (still over the island, so no new enter edge) arms a fresh dwell, which opens after its own 150 ms.
        onWing = false
        w.hoverResume()
        ok(wc.armed == 1, "from the wing into the notch: exactly one dwell timer is armed")
        wc.advance(ms: 149)
        ok(w.state == .petit, "after the resume 149 ms: no open")
        wc.advance(ms: 1)
        ok(w.state == .home && w.openedByHover, "after the resume 150 ms: it opens")
        // A resume with nothing to arm arms nothing: switch off, a hold, a card, an island already open.
        let (r0, r0c) = machine(on: false)
        r0.mouseEntered(); r0.hoverResume()
        ok(r0c.armed == 0, "open on hover off: a resume arms nothing")
        let (r1, r1c) = machine()
        r1.mouseEntered(); r1c.advance(ms: 150)
        r1.hoverResume()
        ok(r1c.armed == 0, "an island that is already open: a resume arms nothing")
        let (r2, r2c) = machine()
        r2.isHoverHeld = { true }
        r2.mouseEntered(); r2.hoverResume()
        ok(r2c.armed == 0, "a hold that still stands: a resume arms nothing")
        let (r3, r3c) = machine()
        r3.mouseEntered(); r3c.advance(ms: 50)
        r3.hoverResume()
        r3c.advance(ms: 100)
        ok(r3.state == .petit && r3c.armed == 1, "a resume re-arms one dwell: the first one (50 ms in) is cancelled, not doubled")
        r3c.advance(ms: 50)
        ok(r3.state == .home && r3c.armed == 0, "...and the re-armed one opens at its own 150 ms")
        // A hold that appears during the dwell cancels the open (the pointer moved from the notch onto a wing before the 150 ms).
        let (x, xc) = machine()
        var wingNow = false
        x.isHoverHeld = { wingNow }
        x.mouseEntered()
        ok(xc.armed == 1, "on the notch: the dwell is armed")
        wingNow = true
        xc.advance(ms: 150)
        ok(x.state == .petit && !x.openedByHover, "the pointer moved onto a wing during the dwell: it does not open")

        print("Island open on hover: \(passed) checks passed")
    }

    @MainActor
    private static func machine(on: Bool = true) -> (IslandStateMachine, HoverClock) {
        let m = IslandStateMachine()
        let clock = HoverClock()
        m.openOnHover = on
        m.hoverCloseDelay = 0.08
        m.armHoverOpen = { delay, item in clock.arm(delay, item) }
        return (m, clock)
    }

    @MainActor
    private static func waitFor(_ s: IslandStateMachine.State, _ m: IslandStateMachine, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while m.state != s && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        precondition(m.state == s, "state \(m.state) after \(timeout) s, expected \(s)")
    }
}
