import Foundation

// The notes' bookkeeping (held, shown, dropped, replaced) and the sidekick's one clock, driven by hand: a clock that moves when the test says, a timer that runs when the test says.
// Run through scripts/test-sidekick-notes.sh.

@main
enum SidekickNotesTests {
    /// A clock and a timer by hand: `advance` moves the time and runs what falls due.
    @MainActor final class Hand {
        var t = 0.0
        var timers: [(id: Int, at: Double, fire: @MainActor @Sendable () -> Void)] = []
        var next = 0
        func schedule(_ after: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> SidekickClock.Cancel {
            next += 1
            let id = next
            timers.append((id, t + after, fire))
            return { [self] in MainActor.assumeIsolated { timers.removeAll { $0.id == id } } }
        }
        func advance(_ ms: Double) {
            t += ms
            while let d = timers.filter({ $0.at <= t }).min(by: { $0.at < $1.at }) { timers.removeAll { $0.id == d.id }; d.fire() }
        }
    }

    static func note(_ id: Int, _ kind: String, key: String? = nil, awaySince: Double? = nil) -> SKNote { SKNote(id: id, kind: kind, text: "t\(id)", key: key, awaySince: awaySince) }

    @MainActor static func main() {
        CT.section("held notes: kept for 30 s (a nudge) or 2 minutes (a recap), then dropped")
        var n = SidekickNotes()
        n.offer(note(1, "stuck.loop", key: "a|1"), now: 1000)
        n.offer(note(2, "recap", awaySince: 5), now: 1000)
        n.offer(note(3, "stuck.loop", key: "a|1"), now: 1500)
        CT.check("the same nudge is not kept twice", n.held.count, 2)
        CT.check("a recap goes first in the queue", n.queue.map(\.id), [2, 1])
        n.offer(note(4, "recap", awaySince: 9), now: 2000)
        CT.check("a new recap replaces the held one", n.queue.map(\.id), [4, 1])
        CT.check("the nearest deadline is the nudge's: 30 s after it was held", n.nextDeadline, 31000)
        CT.check("nothing is dropped early", n.dropExpired(now: 30999).map(\.id), [])
        CT.check("the nudge is dropped at 30 s", n.dropExpired(now: 31000).map(\.id), [1])
        CT.check("the recap is still held at 2 minutes less a moment, and gone at 2 minutes", [n.dropExpired(now: 121999).map(\.id), n.dropExpired(now: 122000).map(\.id)], [[], [4]])
        CT.check("nothing held, nothing on screen: no deadline", n.nextDeadline, nil)

        CT.section("a shown note: seen, replaced, retired, and its time")
        var m = SidekickNotes()
        m.offer(note(1, "stuck.silent", key: "a|1"), now: 0)
        CT.check("it shows", m.show(1, now: 100)?.id, 1)
        CT.check("the gate sees it as not yet seen", m.visible, SKShowInput.Visible(kind: "stuck.silent", seen: false))
        m.markSeen()
        CT.check("and then as seen", m.visible, SKShowInput.Visible(kind: "stuck.silent", seen: true))
        CT.check("a nudge stays 20 s", [m.showingExpired(now: 20099), m.showingExpired(now: 20100)], [false, true])
        CT.check("the deadline is its time", m.nextDeadline, 20100)
        CT.check("it was shown at 100", m.lastShownAt, 100)
        CT.check("the same nudge offered while it is on screen is not kept", { var k = m; k.offer(note(9, "stuck.silent", key: "a|1"), now: 200); return k.held.count }(), 0)
        m.offer(note(2, "recap", awaySince: 77), now: 300)
        CT.check("a recap replaces it", m.show(2, now: 400)?.id, 2)
        CT.check("the recap is the one on screen", m.showing?.note.id, 2)
        CT.check("for 45 s", m.showing?.expiresAt, 45400)
        CT.check("its away period has had its recap, another has not, and none is none", [m.recapGiven(for: 77), m.recapGiven(for: 78), m.recapGiven(for: nil)], [true, false, false])
        CT.check("retire returns the note and clears the screen", [m.retire()?.id, m.showing?.note.id], [2, nil])
        CT.check("retire with nothing on screen is nothing", m.retire()?.id, nil)
        CT.check("a note that is not held does not show", m.show(99, now: 1), nil)

        CT.section("a nudge's words change in place")
        var w = SidekickNotes()
        w.offer(note(1, "stuck.waiting", key: "a|1"), now: 0)
        w.retext(kind: "stuck.waiting", key: "a|1", text: "in the terminal")
        CT.check("a held note", w.held[0].note.text, "in the terminal")
        _ = w.show(1, now: 5)
        w.retext(kind: "stuck.waiting", key: "a|1", text: "again")
        CT.check("a shown note", w.showing?.note.text, "again")
        CT.check("and no second nudge is held", w.held.count, 0)
        CT.check("a note of another session or kind is left alone", { var k = SidekickNotes(); k.offer(note(1, "stuck.waiting", key: "a|1"), now: 0); k.retext(kind: "stuck.waiting", key: "b|2", text: "x"); k.retext(kind: "stuck.loop", key: "a|1", text: "x"); return k.held[0].note.text }(), "t1")

        CT.section("the rows the card shows")
        func recap(_ lines: [String]) -> SKNote { SKNote(id: 1, kind: "recap", text: lines.joined(separator: "\n")) }
        let a = "While you were away, Claude Code in proj ran 2 steps and finished.", b = "While you were away, Codex in site ran 4 steps and is still working.", c = "While you were away, Gemini CLI in docs ran 1 step and finished."
        CT.check("a nudge is one row", SKNote(id: 1, kind: "stuck.loop", text: "Claude Code has run the same step 4 times.").rows, ["Claude Code has run the same step 4 times."])
        CT.check("a recap of one agent is one row, as it is", recap([a]).rows, [a])
        CT.check("two agents: one row each, the second without the prefix", recap([a, b]).rows, [a, "Codex in site ran 4 steps and is still working."])
        CT.check("three agents are three rows", recap([a, b, c]).rows, [a, "Codex in site ran 4 steps and is still working.", "Gemini CLI in docs ran 1 step and finished."])
        CT.check("more than three rows: cut at three, the third ends with an ellipsis", recap([a, b, c, "+2 more"]).rows, [a, "Codex in site ran 4 steps and is still working.", "Gemini CLI in docs ran 1 step and finished…"])
        CT.check("four agents: the same cut, no count", recap([a, b, c, "While you were away, Antigravity in api ran 3 steps and finished."]).rows, [a, "Codex in site ran 4 steps and is still working.", "Gemini CLI in docs ran 1 step and finished…"])
        CT.check("a long recap's last row always ends with the ellipsis and never says how many more", recap([a, b, c, "+9 more"]).rows.last?.hasSuffix("…") == true && !recap([a, b, c, "+9 more"]).rows.joined().contains("more"), true)
        CT.check("a sentence from the local voice is one row", recap(["Claude Code finished two steps in proj."]).rows, ["Claude Code finished two steps in proj."])
        CT.check("a recap with nothing in it is one row, not a crash", recap([]).rows, [""])

        CT.section("the pointer is on the note: it is kept a little longer; a held note can be dropped unseen")
        var x = SidekickNotes()
        x.offer(note(1, "stuck.silent", key: "a|1"), now: 0)
        _ = x.show(1, now: 0)
        x.extendShowing(to: 30000)
        CT.check("a longer time", [x.showingExpired(now: 20000), x.showingExpired(now: 30000)], [false, true])
        x.offer(note(2, "stuck.loop", key: "a|2"), now: 0)
        x.drop(2)
        CT.check("a dropped note is gone", x.held.count, 0)

        CT.section("which views of the open island host a note")
        CT.check("a hidden or compact island hosts it, whatever its last view was", [SidekickHost.canHost(expanded: false, view: "prompt"), SidekickHost.canHost(expanded: false, view: "approval")], [true, true])
        CT.check("the views the user is only looking at", ["overview", "empty", "finished", "note", "sidekick"].map { SidekickHost.canHost(expanded: true, view: $0) }, [true, true, true, true, true])
        CT.check("never a card, the chat, a mail draft, the drop flow, the shelf or Settings", ["approval", "question", "error", "confused", "upload", "uploading", "choose", "mail", "prompt", "searching", "result", "settings", "greeting", "shelf"].filter { SidekickHost.canHost(expanded: true, view: $0) }, [])

        CT.section("the nearest deadline")
        CT.check("two deadlines: the nearer", SidekickNotes.nearest(9, 4), 4)
        CT.check("one deadline", [SidekickNotes.nearest(nil, 4), SidekickNotes.nearest(9, nil)], [4, 9])
        CT.check("none: the clock is not set", SidekickNotes.nearest(nil, nil), nil)

        CT.section("the clock: one one-shot timer, set to one deadline, moved or cancelled, never set when nothing runs")
        let hand = Hand()
        let clock = SidekickClock(now: { hand.t }, schedule: { hand.schedule($0, $1) })
        var fired = 0
        clock.onFire = { fired += 1 }
        /// "deadline / timers ever scheduled / timers waiting now", with -1 for no deadline.
        func state() -> String { "\(clock.deadline.map { Int($0) } ?? -1) / \(clock.scheduled) / \(hand.timers.count)" }
        CT.check("nothing set, nothing scheduled", state(), "-1 / 0 / 0")
        clock.set(nil)
        CT.check("set(nil) with nothing set schedules nothing", state(), "-1 / 0 / 0")
        clock.set(5000)
        CT.check("a deadline schedules one timer", state(), "5000 / 1 / 1")
        clock.set(5000)
        CT.check("the same deadline leaves the timer alone", state(), "5000 / 1 / 1")
        clock.set(8000)
        CT.check("another deadline replaces it (still one timer waiting)", state(), "8000 / 2 / 1")
        hand.advance(7999)
        CT.check("it has not fired a moment early", fired, 0)
        hand.advance(1)
        CT.check("it fires once at the deadline and is spent", [fired, hand.timers.count], [1, 0])
        CT.check("a spent clock has no deadline", state(), "-1 / 2 / 0")
        clock.set(20000)
        clock.set(nil)
        CT.check("set(nil) cancels", state(), "-1 / 3 / 0")
        hand.advance(100000)
        CT.check("a cancelled timer never fires", fired, 1)
        clock.set(.nan)
        CT.check("a deadline that is not finite sets nothing", state(), "-1 / 3 / 0")
        CT.finish()
    }
}
