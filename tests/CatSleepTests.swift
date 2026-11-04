import Foundation

/// Timers the tests move by hand: a clock in milliseconds and the one-shot timers set on it. It counts every timer ever set, so a test can show that
/// nothing polls.
@MainActor
final class FakeTimers {
    struct Pending { var id: Int; var at: Double; var fire: @MainActor @Sendable () -> Void }
    var t = 0.0
    private(set) var pending: [Pending] = []
    private(set) var scheduled = 0
    private var next = 0

    func schedule(_ afterMs: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> CatSleepClock.Cancel {
        scheduled += 1; next += 1
        let id = next
        pending.append(Pending(id: id, at: t + afterMs, fire: fire))
        return { [weak self] in MainActor.assumeIsolated { self?.pending.removeAll { $0.id == id } } }
    }

    /// Moves the clock on, firing the timers that fall due on the way, in order.
    func advance(_ ms: Double) {
        let end = t + ms
        while let due = pending.filter({ $0.at <= end }).min(by: { $0.at < $1.at }) {
            pending.removeAll { $0.id == due.id }
            t = max(t, due.at)
            due.fire()
        }
        t = end
    }

    /// Fires the next timer now, before it is due (a scheduler that is early).
    func fireEarly() {
        guard let first = pending.first else { return }
        pending.removeAll { $0.id == first.id }
        first.fire()
    }
}

@main
enum CatSleepTests {
    static let minute = 60_000.0

    @MainActor static func make(keepAwake: @escaping () -> Bool = { false }) -> (clock: CatSleepClock, timers: FakeTimers, changes: Box) {
        let timers = FakeTimers(), box = Box()
        let clock = CatSleepClock(now: { timers.t }, schedule: { timers.schedule($0, $1) }, keepAwake: keepAwake)
        clock.onChange = { box.changes.append($0) }
        clock.start()
        return (clock, timers, box)
    }
    @MainActor final class Box { var changes: [Bool] = [] }

    @MainActor static func main() {
        CT.section("ten minutes with no agent event put an idle cat to sleep")
        do {
            let (clock, timers, box) = make()
            CT.check("a timer is set at the start, the one timer", timers.pending.count, 1)
            timers.advance(10 * minute - 1)
            CT.check("not yet after 9 min 59.999 s", clock.asleep, false)
            timers.advance(1)
            CT.check("asleep at ten minutes", clock.asleep, true)
            CT.check("and the app was told once", box.changes, [true])
            CT.check("the timer is spent: nothing is left pending", timers.pending.count, 0)
        }

        CT.section("every agent event starts the ten minutes again")
        do {
            let (clock, timers, _) = make()
            timers.advance(9 * minute); clock.agentEvent()
            timers.advance(9 * minute)
            CT.check("nine minutes after the event the cat is still awake", clock.asleep, false)
            timers.advance(minute)
            CT.check("ten minutes after it, asleep", clock.asleep, true)
        }

        CT.section("no polling: at most one timer is ever waiting, and an hour of quiet sets one")
        do {
            let (clock, timers, _) = make()
            timers.advance(60 * minute)
            CT.check("an hour with no event: one timer set in all", timers.scheduled, 1)
            let (c2, t2, _) = make()
            var most = 0
            for i in 0..<200 { t2.advance(7_000); if i % 3 == 0 { c2.agentEvent() }; most = max(most, t2.pending.count) }
            CT.check("two hundred events: never more than one timer waiting", most, 1)
            CT.checkTrue("and the first cat went on sleeping", clock.asleep)
        }

        CT.section("only an idle cat sleeps: never during an approval, a question or any other state, and the timer stops")
        for st in CatState.allCases where st != .idle {
            let (clock, timers, _) = make()
            clock.stateChanged(st)
            CT.check("\(st.rawValue): no timer is waiting", timers.pending.count, 0)
            timers.advance(60 * minute)
            CT.check("\(st.rawValue): an hour later the cat has not gone to sleep", clock.asleep, false)
        }
        do {
            let (clock, timers, _) = make()
            clock.stateChanged(.working)
            timers.advance(30 * minute)
            clock.stateChanged(.idle)
            CT.check("back to idle: one timer again", timers.pending.count, 1)
            timers.advance(9 * minute)
            CT.check("the ten minutes count from the return to idle, not from the last event long ago", clock.asleep, false)
            timers.advance(minute)
            CT.check("and the cat sleeps ten minutes after it", clock.asleep, true)
        }

        CT.section("any agent event, a hover or a click wakes a sleeping cat; other kinds do nothing")
        do {
            let (clock, timers, box) = make()
            timers.advance(10 * minute)
            clock.wake("keyboard")
            CT.check("an unknown kind leaves it asleep", clock.asleep, true)
            clock.wake("hover")
            CT.check("a hover wakes it", clock.asleep, false)
            timers.advance(9 * minute)
            CT.check("and the ten minutes start again from the wake", clock.asleep, false)
            timers.advance(minute)
            CT.check("asleep again ten minutes after", clock.asleep, true)
            clock.wake("click")
            CT.check("a click wakes it", clock.asleep, false)
            timers.advance(10 * minute)
            clock.agentEvent()
            CT.check("an agent event wakes it", clock.asleep, false)
            CT.check("each change was reported once, in order", box.changes, [true, false, true, false, true, false])
            let (awake, t2, _) = make()
            t2.advance(5 * minute); awake.wake("hover"); awake.wake("click")
            t2.advance(5 * minute)
            CT.check("hovering an awake cat does not push its bedtime back", awake.asleep, true)
        }
        do {
            let (clock, timers, _) = make()
            timers.advance(10 * minute)
            clock.stateChanged(.dizzy)
            CT.check("a sleeping cat that is made dizzy wakes", clock.asleep, false)
        }

        CT.section("something else can keep an idle cat awake: Apple Music, which makes it dance, or a card that is waiting")
        do {
            var music = true
            let (clock, timers, _) = make(keepAwake: { music })
            timers.advance(10 * minute)
            CT.check("music is playing: the cat stays awake", clock.asleep, false)
            CT.check("and the timer is set again, still one", timers.pending.count, 1)
            timers.advance(10 * minute)
            CT.check("ten minutes later, still playing: awake", clock.asleep, false)
            music = false
            timers.advance(10 * minute)
            CT.check("the music stops: ten minutes later it sleeps", clock.asleep, true)
        }

        CT.section("music keeps an idle cat awake only when the integration is active too (same two conditions as the dance)")
        do {
            // Test all 8 combinations of (musicPlaying, musicIntegrationOn, cardWaiting), with chatApprovalWaiting: false
            let cases: [(music: Bool, integration: Bool, card: Bool, expect: Bool)] = [
                (false, false, false, false),  // nothing -> sleep
                (false, false, true, true),    // card -> awake
                (false, true, false, false),   // integration alone -> sleep
                (false, true, true, true),     // card + integration -> awake
                (true, false, false, false),   // music alone -> sleep (no integration)
                (true, false, true, true),     // music + card but no integration -> awake (card)
                (true, true, false, true),     // music + integration -> awake
                (true, true, true, true),      // all three -> awake
            ]
            for (i, testCase) in cases.enumerated() {
                let result = CatSleepClock.keepsAwake(musicPlaying: testCase.music, musicIntegrationOn: testCase.integration, cardWaiting: testCase.card, chatApprovalWaiting: false)
                let expected = testCase.expect
                let desc = "case \(i+1): music=\(testCase.music) integration=\(testCase.integration) card=\(testCase.card) chatApproval=false -> \(expected)"
                CT.check(desc, result, expected)
            }
        }

        CT.section("a chat approval waiting keeps an idle cat awake regardless of other conditions")
        do {
            // Test all 8 combinations with chatApprovalWaiting: true - all should keep awake
            let cases: [(music: Bool, integration: Bool, card: Bool)] = [
                (false, false, false),
                (false, false, true),
                (false, true, false),
                (false, true, true),
                (true, false, false),
                (true, false, true),
                (true, true, false),
                (true, true, true),
            ]
            for (i, testCase) in cases.enumerated() {
                let result = CatSleepClock.keepsAwake(musicPlaying: testCase.music, musicIntegrationOn: testCase.integration, cardWaiting: testCase.card, chatApprovalWaiting: true)
                let desc = "case \(i+1): chatApproval=true with music=\(testCase.music) integration=\(testCase.integration) card=\(testCase.card) -> awake"
                CT.check(desc, result, true)
            }
        }

        CT.section("clock integration: music awake only with integration, chat approval overrides all (fake clock test)")
        do {
            // Music playing with integration off -> cat sleeps
            let (clock1, timers1, _) = make(keepAwake: { CatSleepClock.keepsAwake(musicPlaying: true, musicIntegrationOn: false, cardWaiting: false, chatApprovalWaiting: false) })
            timers1.advance(10 * minute)
            CT.check("music without integration: cat sleeps", clock1.asleep, true)

            // Music playing with integration on -> cat stays awake
            let (clock2, timers2, _) = make(keepAwake: { CatSleepClock.keepsAwake(musicPlaying: true, musicIntegrationOn: true, cardWaiting: false, chatApprovalWaiting: false) })
            timers2.advance(10 * minute)
            CT.check("music with integration: cat stays awake", clock2.asleep, false)
            CT.check("and timer is set again", timers2.pending.count, 1)

            // Chat approval waiting -> cat stays awake regardless of other conditions
            var chatApproval = true
            let (clock3, timers3, _) = make(keepAwake: { CatSleepClock.keepsAwake(musicPlaying: false, musicIntegrationOn: false, cardWaiting: false, chatApprovalWaiting: chatApproval) })
            timers3.advance(10 * minute)
            CT.check("chat approval waiting: cat stays awake", clock3.asleep, false)
            CT.check("and timer is set again", timers3.pending.count, 1)
            timers3.advance(10 * minute)
            CT.check("ten minutes later with approval still waiting: still awake", clock3.asleep, false)
            chatApproval = false
            timers3.advance(10 * minute)
            CT.check("after approval is cleared, ten minutes later: asleep", clock3.asleep, true)
        }

        CT.section("a timer that fires early waits for the rest, and a state change that raced it is not an error")
        do {
            let (clock, timers, _) = make(keepAwake: { CatSleepClock.keepsAwake(musicPlaying: false, musicIntegrationOn: false, cardWaiting: false, chatApprovalWaiting: false) })
            timers.advance(4 * minute)
            timers.fireEarly()
            CT.check("six minutes early: not asleep", clock.asleep, false)
            CT.check("and a timer waits for the rest", timers.pending.count, 1)
            timers.advance(6 * minute)
            CT.check("it sleeps at the ten minutes", clock.asleep, true)
        }

        CT.section("what an idle cat shows")
        CT.check("idle and asleep shows sleeping", CatRules.shown(.idle, asleep: true), CatState.sleeping)
        CT.check("idle and awake shows idle", CatRules.shown(.idle, asleep: false), CatState.idle)
        for st in CatState.allCases where st != .idle { CT.check("\(st.rawValue) shows itself, asleep or not", [CatRules.shown(st, asleep: true), CatRules.shown(st, asleep: false)], [st, st]) }

        CT.section("sleeping in the app (source pins: no test program can run the island)")
        func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/" + file, encoding: .utf8)) ?? "" }
        let hook = source("HookServer.swift"), app = source("AppState.swift"), island = source("IslandWindowController.swift"), canvases = source("BotCanvasView.swift")
        CT.check("every agent event wakes the cat and resets the timer: events, permission requests and questions", hook.components(separatedBy: "CatSleepClock.shared.agentEvent()").count - 1, 3)
        CT.checkTrue("the app holds whether the cat sleeps, and the cat shows sleeping instead of idle", app.contains("@Published var catAsleep") && app.contains("var baseState: BotState") && app.contains(".shown(asleep: catAsleep)"))
        CT.checkTrue("a hover on the island and a click wake it", island.contains("CatSleepClock.shared.wake(\"hover\")") && island.contains("CatSleepClock.shared.wake(\"click\")"))
        CT.checkTrue("the small cats of idle pills sleep with the big one", canvases.contains("task.state.shown(asleep: AppState.shared.catAsleep)") && canvases.contains("newState.shown(asleep: AppState.shared.catAsleep)"))
        CT.checkTrue("the clock is attached to the app when the island is set up", source("AppDelegate.swift").contains("CatSleepClock.shared.attach(to: AppState.shared)"))
        CT.checkTrue("the app's clock keeps an idle cat awake while music plays (with integration active), a card waits, or a chat approval waits", source("CatSleep+App.swift").contains("app.musicPlaying") && source("CatSleep+App.swift").contains("integration_music") && source("CatSleep+App.swift").contains("app.pendingApproval != nil || app.pendingQuestion != nil") && source("CatSleep+App.swift").contains("app.chatApproval"))
        CT.finish()
    }
}
