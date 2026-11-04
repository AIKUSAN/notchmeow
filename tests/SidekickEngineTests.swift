import Combine
import Foundation

// The sidekick's brain, driven by hand: a world the test controls (the clock, the idle seconds, what is in front of the island, typing, the pointer) and a timer that runs when the test says. The scripted
// runs prove the whole flow the owner will see: a recap after a lock, a nudge for a loop, a nudge for a request nobody is looking at, a note that is held and dropped, a kind that is muted after two
// dismissals and comes back with Unmute, and that nothing runs (no timer is set) when no agent does. Run through scripts/test-sidekick-engine.sh.

@main
enum SidekickEngineTests {
    @MainActor final class World {
        var t = 10_000_000.0
        var idle = 0.0
        /// How many times the OS was asked for the idle time.
        var idleCalls = 0
        var card: String?
        var ownCard = false
        /// The sessions (by session ID) whose request stepped back to its own app (focus awareness) and still waits there.
        var stepBack: Set<String> = []
        /// The sessions whose stepped-back mark lapses at this time (the engine's clock, ms): held until then, and no longer after.
        var stepBackUntil: [String: Double] = [:]
        /// When set, what the island shows now is read from here (a published value), not from `ownCard`.
        var ownCardLive: (() -> Bool)?
        var host = true
        /// The view the island is open on, nil while it is hidden or compact.
        var view: String?
        var typing = false
        var ratelimited = false
        var pointer = false
        var polishReply: String?
        var presented: [SKNote] = []
        /// How many times the app was told to redraw its pill (a stepped-back mark ran out).
        var redraws = 0
        var retracted: [SKNote] = []
        var timers: [(id: Int, at: Double, fire: @MainActor @Sendable () -> Void)] = []
        var next = 0

        func schedule(_ after: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> SidekickClock.Cancel {
            next += 1
            let id = next
            timers.append((id, t + after, fire))
            return { [self] in MainActor.assumeIsolated { timers.removeAll { $0.id == id } } }
        }
        /// Moves the time on and runs the timers that fall due on the way, in order, each at its own time.
        func advance(_ ms: Double) {
            let end = t + ms
            while let d = timers.filter({ $0.at <= end }).min(by: { $0.at < $1.at }) { timers.removeAll { $0.id == d.id }; t = max(t, d.at); d.fire() }
            t = end
        }
    }

    /// The app's own state, as two published values: what is on the island and whether it is open (`AppState.view` and `.mode`).
    @MainActor final class Probe: ObservableObject {
        @Published var view = "approval"
        @Published var expanded = true
    }

    /// One turn of the main queue: what a `receive(on: DispatchQueue.main)` waits for.
    static func turn() async { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }

    @MainActor static func make(_ w: World, store: SidekickStore = SidekickStore(backing: MemoryBacking())) -> SidekickEngine {
        let clock = SidekickClock(now: { w.t }, schedule: { w.schedule($0, $1) })
        var env = SidekickEngine.Env(now: { w.t })
        env.idleSeconds = { w.idleCalls += 1; return w.idle }
        env.cardInFront = { w.card }
        env.ownCardShown = { w.ownCardLive?() ?? w.ownCard }
        // A session in `stepBack` has a live mark for good (no end: infinity, which the clock never sets); one in `stepBackUntil` until its time.
        env.stepBackEnd = { id in
            if w.stepBack.contains(id) { return Double.infinity }
            if let until = w.stepBackUntil[id], w.t < until { return until }
            return nil
        }
        // The earliest end of any live mark, whatever its session (the ledger may not hold it): the marks, not the ledger, are the source of the lapse.
        env.focusLapseAt = { w.stepBackUntil.values.filter { $0 > w.t }.min() }
        env.canHost = { w.host }
        env.openView = { w.view }
        env.typing = { w.typing }
        env.ratelimited = { w.ratelimited }
        env.pointerOver = { w.pointer }
        env.present = { w.presented.append($0) }
        env.retract = { w.retracted.append($0) }
        env.polish = { _ in w.polishReply }
        env.focusLapsed = { w.redraws += 1 }
        return SidekickEngine(store: store, clock: clock, env: env)
    }

    static func hook(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var p: [String: Any] = ["hook_event_name": name, "session_id": "S1", "cwd": "/Users/me/proj", "term_program": "vscode"]
        for (k, v) in extra { p[k] = v }
        return p
    }
    static func post(_ command: String) -> [String: Any] { hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": command]]) }
    static func edit(_ file: String) -> [String: Any] { hook("PostToolUse", ["tool_name": "Edit", "tool_input": ["file_path": "/Users/me/proj/\(file)", "old_string": "a", "new_string": "b"]]) }

    @MainActor static func main() async {
        let sec = 1000.0, min = 60_000.0

        CT.section("a recap after a lock: while you were away, once, at the return")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("UserPromptSubmit", ["prompt": "SECRET"]))
            w.advance(1 * sec); e.presenceEvent(.lock)
            w.advance(30 * sec); e.feed(payload: edit("a.js"))
            w.advance(30 * sec); e.feed(payload: post("npm test"))
            w.advance(30 * sec); e.feed(payload: hook("Stop", ["last_assistant_message": "SECRET"]))
            CT.check("nothing shows while the user is away", w.presented.count, 0)
            CT.check("and the clock has nothing to wait for (a nudge falls due while away is dropped, the recap covers it)", e.clock.deadline, nil)
            w.advance(2 * min); e.presenceEvent(.unlock)
            CT.check("at the return the recap shows", w.presented.map(\.kind), ["recap"])
            CT.check("in the template's words, with a basename and counts", w.presented.first?.text, "While you were away, Claude Code in proj ran 2 steps, edited a.js, and finished.")
            CT.check("it is on the island for the note's time (45 s): the clock is set to it", e.clock.deadline, w.t + 45 * sec)
            e.dismiss()
            CT.check("OK counts as a dismissal of the recap, and the note leaves the island", "\(e.store.settings.dismissals["recap"] ?? -1) / \(w.retracted.count)", "1 / 1")
            CT.check("and the clock is idle again", e.clock.deadline, nil)
            CT.check("the same away period does not give a second recap", { e.presenceEvent(.unlock); return w.presented.count }(), 1)
        }

        CT.section("two dismissals mute the recap; Unmute brings it back")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            func away(_ file: String) {
                e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit(file)); w.advance(3 * min); e.presenceEvent(.unlock)
            }
            away("a.js"); e.dismiss()
            away("b.js"); e.dismiss()
            CT.check("two dismissals", e.store.settings.dismissals["recap"], 2)
            let before = w.presented.count
            away("c.js")
            CT.check("a muted recap never shows", w.presented.count, before)
            e.store.unmute("recap")
            away("d.js")
            CT.check("Unmute: the next return shows it again", w.presented.count, before + 1)
        }

        CT.section("a nudge for a loop: four of the same step, once per session")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for i in 0..<3 { w.advance(1 * sec); e.feed(payload: post("npm test")); _ = i }
            CT.check("three are not a loop", w.presented.count, 0)
            w.advance(1 * sec); e.feed(payload: post("npm test"))
            CT.check("the fourth is", w.presented.map(\.text), ["Claude Code has run the same step 4 times."])
            CT.check("it is a stuck.loop note about the Claude Code session", [w.presented[0].kind, w.presented[0].agentId ?? ""], ["stuck.loop", "integration_claude"])
            w.advance(1 * sec); e.feed(payload: post("npm test"))
            CT.check("the session has had its nudge: no second", w.presented.count, 1)
            w.advance(25 * sec)
            CT.check("a nudge goes by itself after 20 s", "\(e.showing == nil) / \(w.retracted.count)", "true / 1")
            CT.check("and that is not a dismissal", e.store.settings.dismissals["stuck.loop"], 0)
            w.advance(1 * sec); e.feed(payload: post("npm test"))
            CT.check("it was shown, so the session has had its nudge: the loop going on makes no second", "\(w.presented.count) / \(e.notes.held.count)", "1 / 0")
        }

        CT.section("a request nobody is looking at: the waiting nudge at 60 s, its words change at the give-up time")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            w.ownCard = true; e.envChanged()
            CT.check("its own card is on screen: no deadline for it", e.clock.deadline, nil)
            w.advance(100 * sec); e.envChanged()
            CT.check("the card on screen says it all: no nudge", w.presented.count, 0)
            w.ownCard = false; w.card = "approval"
            e.envChanged()
            CT.check("a card is in front but not its own: the waiting nudge shows", w.presented.map(\.text), ["Claude Code is still waiting for your OK."])
            CT.check("the clock is set to the app's give-up time, 15 s on", e.clock.deadline, w.t + 15 * sec)
            w.advance(15 * sec)
            CT.check("at the Mac's give-up time (115 s) the words change in place", e.showing?.text, "Claude Code is waiting for your OK in the terminal.")
            CT.check("and it is not a second nudge", w.presented.count, 1)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            w.advance(60 * sec)
            CT.check("the clock fires at 60 s with nobody looking: the nudge shows", w.presented.map(\.kind), ["stuck.waiting"])
            e.approvalAnswered(agentId: "integration_claude", sessionId: "S1")
            CT.check("the user answers: the nudge is no longer true and goes, uncounted", "\(e.showing == nil) / \(e.store.settings.dismissals["stuck.waiting"] ?? -1)", "true / 0")
        }
        do {
            let w = World(), e = make(w)
            w.stepBack = ["S1"]
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            w.advance(120 * sec); e.envChanged()
            CT.check("a request that stepped back to its own app gets no waiting nudge", w.presented.map(\.kind).filter { $0 == "stuck.waiting" }, [])
        }
        do {
            // The hold is per session: session S1's request stepped back, session S2's did not. S1 gets no waiting nudge; S2's still fires at its 60 s, and S1 is never nudged for it.
            let w = World(), e = make(w)
            w.stepBack = ["S1"]
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            e.feed(payload: hook("SessionStart", ["session_id": "S2"]))
            e.feed(payload: hook("PermissionRequest", ["session_id": "S2", "tool_name": "Bash", "tool_input": ["command": "git push"]]))
            let keyS2 = e.ledger.sessions.first { $0.sessionId == "S2" }?.key
            w.advance(60 * sec); e.envChanged()
            CT.check("session S2's waiting nudge fires at its 60 s, and it is for S2, not for the stepped-back S1", w.presented.filter { $0.kind == "stuck.waiting" }.map(\.key), [keyS2])
            w.advance(60 * sec); e.envChanged()
            CT.check("and the stepped-back S1 is never nudged for its waiting request", w.presented.filter { $0.kind == "stuck.waiting" }.map(\.key), [keyS2])
        }
        do {
            // A waiting nudge already held for a session goes when that session's request steps back: the hold is the rule's, not only the clock's.
            let w = World(), e = make(w)
            w.host = false
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            w.advance(60 * sec)
            CT.check("the waiting nudge is held (the island cannot host it)", e.notes.held.map(\.note.kind), ["stuck.waiting"])
            w.stepBack = ["S1"]
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            CT.check("the request steps back: the held nudge for its session goes", e.notes.held.count, 0)
        }
        do {
            // A held request's waiting nudge is due again when its mark lapses (ten minutes). A blocked agent sends no more events, so nothing else wakes the engine for it. S2's request never
            // stepped back: it is nudged at its own 60 s, and S1's nudge comes once, at the lapse.
            let w = World(), e = make(w)
            w.stepBackUntil = ["S1": w.t + 600 * sec]
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            e.feed(payload: hook("SessionStart", ["session_id": "S2"]))
            e.feed(payload: hook("PermissionRequest", ["session_id": "S2", "tool_name": "Bash", "tool_input": ["command": "git push"]]))
            let keyS1 = e.ledger.sessions.first { $0.sessionId == "S1" }?.key
            let keyS2 = e.ledger.sessions.first { $0.sessionId == "S2" }?.key
            func waiting() -> [String?] { w.presented.filter { $0.kind == "stuck.waiting" }.map(\.key) }
            w.advance(60 * sec)
            CT.check("at 60 s only S2, which never stepped back, is nudged", waiting(), [keyS2])
            w.advance(539 * sec)
            CT.check("S1 is still held at 599 s", waiting(), [keyS2])
            w.advance(1 * sec)
            CT.check("S1's mark lapses at 600 s with no other event: its waiting nudge shows once", waiting(), [keyS2, keyS1])
            w.advance(120 * sec); e.envChanged()
            CT.check("and never a second time", waiting(), [keyS2, keyS1])
        }
        do {
            // A waiting nudge already ON SCREEN goes when its own session's request steps back (the rule no longer holds it, and it is not a dismissal). Another session stepping back leaves it up.
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            w.advance(60 * sec)
            CT.check("S1's waiting nudge is on screen at 60 s", e.showing?.kind, "stuck.waiting")
            w.stepBack.insert("S2"); e.envChanged()
            CT.check("another session (S2) stepping back leaves S1's shown nudge up", "\(e.showing?.kind ?? "") / \(w.retracted.count)", "stuck.waiting / 0")
            w.stepBack.insert("S1"); e.envChanged()
            CT.check("S1's own step-back retires its shown nudge, uncounted", "\(e.showing == nil) / \(w.retracted.count) / \(e.store.settings.dismissals["stuck.waiting"] ?? -1)", "true / 1 / 0")
        }

        do {
            // Focus awareness: a stepped-back mark runs out ten minutes on, and the app is told once to redraw its pill (its dot and note are read when drawn, so nothing else would clear them).
            // It is told with the Sidekick OFF too: a blocked agent sends no event, and the dot must not stay on after its time.
            let w = World(), store = SidekickStore(backing: MemoryBacking()), e = make(w, store: store)
            store.update { $0.on = false }
            w.stepBackUntil = ["S1": w.t + 600 * sec]
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            w.advance(599 * sec)
            CT.check("the app is not told before the mark runs out (599 s)", w.redraws, 0)
            w.advance(1 * sec)
            CT.check("the app is told once at the lapse (600 s), with the Sidekick off", w.redraws, 1)
            w.advance(120 * sec); e.envChanged()
            CT.check("and never a second time", w.redraws, 1)
        }

        do {
            // A live mark whose session the ledger has dropped (nine sessions fed: S1, the oldest, goes when the ninth arrives) still lapses on its own: the app is told once at 600 s, with the Sidekick
            // OFF. The lapse comes from the marks, not the ledger, so an evicted session's dot and note do not stay on until some other redraw.
            let w = World(), store = SidekickStore(backing: MemoryBacking()), e = make(w, store: store)
            store.update { $0.on = false }
            w.stepBackUntil = ["S1": w.t + 600 * sec]
            let until = w.t + 600 * sec
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            for n in 2...9 { w.advance(1 * sec); e.feed(payload: hook("SessionStart", ["session_id": "S\(n)"])) }
            CT.check("the ledger has dropped S1 (eight sessions held)", e.ledger.sessions.contains { $0.sessionId == "S1" }, false)
            w.advance(until - 1 - w.t)
            CT.check("the app is not told before the evicted mark runs out (599 s)", w.redraws, 0)
            w.advance(1)
            CT.check("the app is told once at the lapse (600 s), though the ledger no longer holds S1, with the Sidekick off", w.redraws, 1)
            w.advance(120 * sec); e.envChanged()
            CT.check("and never a second time", w.redraws, 1)
        }

        do {
            // Two live marks (focus awareness): the wake is armed for the one that ends first. When that one ends early (its session's next event), the wake moves to the next live lapse,
            // so nothing is told at the ended mark's old time; the app is told once at the next lapse, and never again for either mark.
            let w = World(), store = SidekickStore(backing: MemoryBacking()), e = make(w, store: store)
            store.update { $0.on = false }
            let start = w.t
            w.stepBackUntil = ["S1": start + 600 * sec, "S2": start + 900 * sec]
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            e.feed(payload: hook("SessionStart", ["session_id": "S2"]))
            e.feed(payload: hook("PermissionRequest", ["session_id": "S2", "tool_name": "Bash", "tool_input": ["command": "git push"]]))
            CT.check("two live marks: the wake is armed for the one that ends first (600 s)", e.clock.deadline, start + 600 * sec)
            w.advance(100 * sec)
            w.stepBackUntil["S1"] = nil; e.envChanged()
            CT.check("S1 ends early: the wake is re-armed for S2's lapse (900 s), not left at 600 s", e.clock.deadline, start + 900 * sec)
            w.advance(500 * sec)
            CT.check("nothing is told at S1's old lapse (600 s)", w.redraws, 0)
            w.advance(300 * sec)
            CT.check("the app is told once, at S2's lapse (900 s)", w.redraws, 1)
            w.advance(120 * sec); e.envChanged()
            CT.check("and never a second time", w.redraws, 1)
        }

        do {
            // A mark replaced by a newer request of the same session: the wake moves to the replacement's lapse (700 s), and the replaced mark's lapse (600 s) is never told.
            let w = World(), store = SidekickStore(backing: MemoryBacking()), e = make(w, store: store)
            store.update { $0.on = false }
            let start = w.t
            w.stepBackUntil = ["S1": start + 600 * sec]
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            w.advance(100 * sec)
            w.stepBackUntil["S1"] = w.t + 600 * sec
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            CT.check("replaced: the wake moves to the newer mark's lapse (700 s)", e.clock.deadline, start + 700 * sec)
            w.advance(500 * sec)
            CT.check("the replaced mark's lapse (600 s) is not told", w.redraws, 0)
            w.advance(200 * sec)
            CT.check("the newer mark's lapse (700 s) is told once", w.redraws, 1)
        }

        CT.section("an observer of the app's state evaluates after the write has landed, not during it")
        do {
            // The app's own published values change in `willSet`: a sink that re-reads the state in the same call finds the OLD value. The card goes behind the chat; the waiting nudge must come back.
            let w = World(), e = make(w), probe = Probe()
            w.ownCardLive = { probe.view == "approval" && probe.expanded }
            var bag = Set<AnyCancellable>()
            e.watch(probe.$view.combineLatest(probe.$expanded).map { $0 == "approval" && $1 }.removeDuplicates().dropFirst()).store(in: &bag)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            CT.check("its card is on screen: no deadline for the waiting nudge", e.clock.deadline, nil)
            let asked = w.t
            probe.view = "chat"
            await turn()
            CT.check("the user opens the chat over it: the deadline is the request's 60 s", e.clock.deadline, asked + 60 * sec)
            w.advance(60 * sec)
            CT.check("and the nudge shows", w.presented.map(\.kind), ["stuck.waiting"])
        }
        do {
            // The same for a setting: "Recaps and nudges" off while a note is on screen takes it away at once.
            let w = World(), store = SidekickStore(backing: MemoryBacking()), e = make(w, store: store)
            var bag = Set<AnyCancellable>()
            e.watch(store.$settings.dropFirst()).store(in: &bag)
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            CT.check("a nudge is on screen", e.showing?.kind, "stuck.loop")
            store.setOn(false)
            await turn()
            CT.check("the switch goes off: the note goes with it, without waiting for it to expire", "\(e.showing == nil) / \(w.retracted.count)", "true / 1")
        }

        CT.section("a note that another view took the island from, before the user saw it, was never given")
        do {
            // Stop right after the unlock: the finished card opens over the recap. The recap was never seen, so it is not counted as given.
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            w.view = "sidekick"
            CT.check("the recap is on the island", [w.presented.map(\.kind), [e.showing?.kind ?? ""]], [["recap"], ["recap"]])
            w.view = "finished"; e.envChanged()
            CT.check("a finished card takes the island: the recap goes, and it is not a dismissal", "\(e.showing == nil) / \(w.retracted.map(\.kind)) / \(e.store.settings.dismissals["recap"] ?? 0)", "true / [\"recap\"] / 0")
            CT.check("it is held again, not shown over the card that took the island", "\(e.notes.held.map(\.note.kind)) / \(w.presented.count)", "[\"recap\"] / 1")
            w.advance(10 * sec); e.tick()
            CT.check("and it stays held while that card is there", "\(e.showing == nil) / \(w.presented.count)", "true / 1")
            w.view = "overview"; e.envChanged()
            CT.check("the card goes: the recap shows, once more", [w.presented.map(\.kind), [e.showing?.kind ?? ""]], [["recap", "recap"], ["recap"]])
            w.view = "sidekick"; e.noteSeen(); w.advance(46 * sec)
            CT.check("seen and gone by itself: given, and not a dismissal", "\(e.showing == nil) / \(e.notes.held.count) / \(e.store.settings.dismissals["recap"] ?? 0)", "true / 0 / 0")
            e.presenceEvent(.unlock)
            CT.check("the period has had its recap: no third", w.presented.count, 2)
        }
        do {
            // The held recap keeps its own 2 minutes: a card that stays is the end of it.
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            w.view = "sidekick"; w.view = "finished"; e.envChanged()
            w.advance(2 * min + 1 * sec); e.tick()
            CT.check("the hold runs out under the card: dropped silently, never shown a second time", "\(e.notes.held.filter(\.note.isRecap).count) / \(w.presented.filter(\.isRecap).count) / \(e.store.settings.dismissals["recap"] ?? 0)", "0 / 1 / 0")
        }
        do {
            // A nudge: the ledger's mark is undone, the rules offer it again, and once shown and seen it is given.
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            w.view = "sidekick"
            CT.check("the loop nudge is on the island, and the session is marked nudged", "\(e.showing?.kind ?? "-") / \(e.ledger.sessions.first?.nudgedAt != nil)", "stuck.loop / true")
            w.view = "error"; e.envChanged()
            CT.check("an error card takes the island: the nudge goes, uncounted, and the session is not marked", "\(e.showing == nil) / \(e.ledger.sessions.first?.nudgedAt == nil) / \(e.store.settings.dismissals["stuck.loop"] ?? 0)", "true / true / 0")
            CT.check("the rules offer it again, held under the card", "\(e.notes.held.map(\.note.kind)) / \(w.presented.count)", "[\"stuck.loop\"] / 1")
            w.view = nil; e.envChanged()
            CT.check("the island folds: it shows again, at once (an unseen note does not count toward the gap between notes)", w.presented.map(\.kind), ["stuck.loop", "stuck.loop"])
            CT.check("and the session is marked again", e.ledger.sessions.first?.nudgedAt != nil, true)
            w.view = "sidekick"; e.noteSeen(); w.advance(21 * sec)
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            CT.check("seen, and gone: it was given, no third", "\(e.showing == nil) / \(w.presented.count)", "true / 2")
        }
        do {
            // A note the user has seen is given, whatever takes the island afterwards.
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            w.view = "sidekick"; e.noteSeen()
            w.view = "finished"; e.envChanged()
            CT.check("a seen nudge goes with the card, counted as given: not offered again", "\(e.showing == nil) / \(e.notes.held.count) / \(e.ledger.sessions.first?.nudgedAt != nil)", "true / 0 / true")
            w.view = nil; e.envChanged(); w.advance(1 * sec); e.feed(payload: post("make"))
            CT.check("and not shown again", w.presented.count, 1)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            w.view = "sidekick"; e.noteSeen()
            w.view = "finished"; e.envChanged()
            w.view = nil; e.envChanged(); e.presenceEvent(.unlock)
            CT.check("a seen recap is given too: not offered again", "\(w.presented.count) / \(e.notes.held.count) / \(e.showing == nil)", "1 / 0 / true")
        }

        CT.section("the gate holds a note, and drops it silently when its time is up")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.typing = true
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            CT.check("the user is typing: the nudge is held, not shown", "\(w.presented.count) / \(e.notes.held.count)", "0 / 1")
            CT.check("the clock waits for the hold to run out (30 s)", e.clock.deadline, w.t + 30 * sec)
            w.typing = false
            w.advance(10 * sec); e.envChanged()
            CT.check("typing stops within 30 s: it shows", w.presented.count, 1)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.typing = true
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            w.typing = false
            e.tick()
            CT.check("a held note is asked again on the island's own tick: typing stopped, and nothing but the tick noticed", w.presented.count, 1)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.host = false
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            e.tick()
            w.host = true
            e.tick()
            CT.check("the held note is asked again at most once a second: not at once", w.presented.count, 0)
            w.advance(1100); e.tick()
            CT.check("and after a second the tick finds the gate open", w.presented.count, 1)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.host = false
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            w.advance(31 * sec)
            CT.check("the island is open on something else for 30 s: the held nudge runs out, silently (no dismissal)", "\(w.presented.count) / \(e.store.settings.dismissals["stuck.loop"] ?? -1)", "0 / 0")
            CT.check("it was never shown, so it was never given: the session is offered the nudge again", e.notes.held.count, 1)
            w.host = true; e.envChanged()
            CT.check("the moment the island can host it, it shows, once", w.presented.map(\.text), ["Claude Code has run the same step 4 times."])
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            CT.check("and once shown the session has had its nudge: no second", w.presented.count, 1)
        }

        CT.section("a recap replaces a nudge nobody has seen; the switch turns it all off")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            w.pointer = true   // the pointer is on the island: the nudge stays
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min)
            CT.check("a nudge is on screen, unseen", [w.presented.map(\.kind), [e.showing?.kind ?? ""]], [["stuck.loop"], ["stuck.loop"]])
            e.presenceEvent(.unlock)
            CT.check("the recap replaces it", w.presented.map(\.kind), ["stuck.loop", "recap"])
            CT.check("and the nudge left the island", w.retracted.map(\.kind), ["stuck.loop"])
            e.store.setOn(false)
            e.envChanged()
            CT.check("the master switch off: the note on screen goes", e.showing == nil, true)
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make2")) }
            CT.check("and no nudge shows", w.presented.count, 2)
            CT.check("and no deadline is waited for", e.clock.deadline, nil)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            e.noteSeen()
            w.pointer = true
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            CT.check("a nudge the user has seen is not replaced: the recap waits for the gate and is dropped when its time is up", [w.presented.map(\.kind), e.notes.held.map(\.note.kind)], [["stuck.loop"], ["recap"]])
            w.advance(2 * min + 1 * sec)
            CT.check("two minutes on, the held recap's time is up and it is dropped silently (never shown, no dismissal)", "\(e.notes.held.count) / \(w.presented.map(\.kind)) / \(e.store.settings.dismissals["recap"] ?? -1)", "0 / [\"stuck.loop\"] / 0")
        }
        do {
            // A store observer that re-enters the engine while a dismissal is being written must not be clobbered by it.
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            e.noteSeen()
            w.pointer = true
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            var bag = Set<AnyCancellable>()
            e.store.$settings.sink { _ in e.envChanged() }.store(in: &bag)
            e.dismiss()
            CT.check("a store observer that calls envChanged inside the dismissal: the held recap shows and the engine agrees with the notes", "\(e.showing?.kind ?? "-") / \(e.showing == e.notes.showing?.note)", "recap / true")
            CT.check("and the dismissal was counted once", e.store.settings.dismissals["stuck.loop"], 1)
            CT.check("and the nudge left the island once", w.retracted.map(\.kind), ["stuck.loop"])
        }

        CT.section("a held nudge goes when it is no longer true; a loop that is still true shows once the gate opens")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.host = false
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            CT.check("the loop is held", e.notes.held.map(\.note.kind), ["stuck.loop"])
            w.advance(1 * sec); e.feed(payload: edit("a.js"))
            CT.check("a successful edit ends the loop: the held nudge is gone", e.notes.held.count, 0)
            w.host = true; e.envChanged()
            CT.check("the gate opens and nothing shows", w.presented.count, 0)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.host = false
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            w.advance(1 * sec); e.feed(payload: post("make"))
            CT.check("a loop that goes on is still held", e.notes.held.map(\.note.kind), ["stuck.loop"])
            w.host = true; e.envChanged()
            CT.check("and shows once the gate opens", w.presented.map(\.text), ["Claude Code has run the same step 4 times."])
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.host = false
            for _ in 0..<3 { w.advance(1 * sec); e.feed(payload: hook("PostToolUseFailure", ["tool_name": "Bash", "tool_input": ["command": "make \(w.t)"], "error": "x"])) }
            CT.check("three failures in a row are held as the errors nudge", e.notes.held.map(\.note.kind), ["stuck.errors"])
            w.advance(1 * sec); e.feed(payload: post("ls"))
            CT.check("a success ends it: the held nudge is gone", e.notes.held.count, 0)
        }

        CT.section("quiet for five minutes; and nothing runs when no agent does")
        do {
            let w = World(), e = make(w)
            CT.check("a fresh engine sets no timer and has none scheduled", "\(e.clock.deadline == nil) / \(e.clock.scheduled) / \(w.timers.count)", "true / 0 / 0")
            for _ in 0..<50 { w.advance(100); e.tick() }
            CT.check("fifty ticks with no live session never ask the OS for the idle time", w.idleCalls, 0)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("UserPromptSubmit"))
            CT.check("a session that is thinking sets the clock to 5 minutes after its last event", e.clock.deadline, w.t + 5 * min)

            w.advance(5 * min)
            CT.check("at that time it is quiet", w.presented.map(\.text), ["Claude Code has been quiet for 5 minutes."])
            e.feed(payload: hook("SessionEnd"))
            CT.check("the session ends: the note about it goes (stale), and no timer is left", "\(e.showing == nil) / \(e.clock.deadline == nil)", "true / true")
        }

        CT.section("a muted loop does not starve the quiet nudge, and the clock waits only for what can show")
        do {
            let w = World(), e = make(w)
            e.store.dismiss("stuck.loop"); e.store.dismiss("stuck.loop")
            CT.check("two dismissals mute the loop kind", e.store.settings.mutedKinds, ["stuck.loop"])
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("npm test")) }
            let last = w.t
            CT.check("a loop that holds shows nothing, as muted", "\(w.presented.count) / \(e.notes.held.count)", "0 / 0")
            CT.check("and the clock is set to the quiet deadline, not woken for the loop", e.clock.deadline, last + 5 * min)
            w.advance(12 * min)
            CT.check("twelve quiet minutes: the quiet nudge showed for the same session, by the clock alone, once", w.presented.map { [$0.kind, $0.text].joined(separator: ": ") }, ["stuck.silent: Claude Code has been quiet for 5 minutes."])
            CT.check("and the clock has nothing more to wait for", e.clock.deadline, nil)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("npm test")) }
            CT.check("control, nothing muted: the loop shows first", w.presented.map(\.kind), ["stuck.loop"])
        }
        do {
            let w = World(), e = make(w)
            e.store.dismiss("stuck.waiting"); e.store.dismiss("stuck.waiting")
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            CT.check("a muted waiting kind sets no clock for the request", e.clock.deadline, nil)
            w.advance(2 * min)
            CT.check("and says nothing", w.presented.count, 0)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            CT.check("control, nothing muted: the clock is set for the request's 60 s", e.clock.deadline, w.t + 60 * sec)
        }

        CT.section("the idle time is read at most every 5 s, on the island's own tick, and only while an agent has a live session")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            let calls = w.idleCalls
            for _ in 0..<40 { w.advance(100); e.tick() }
            CT.check("forty ticks in four seconds: not read again", w.idleCalls, calls)
            w.advance(1500); e.tick()
            CT.check("the first tick past 5 s reads it once", w.idleCalls, calls + 1)
            e.feed(payload: hook("SessionEnd"))
            let after = w.idleCalls
            for _ in 0..<100 { w.advance(100); e.tick() }
            CT.check("once no session is live it is not read at all", w.idleCalls, after)
        }

        CT.section("away by idle: a tick that already exists reads the idle time, and a return is noticed")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("UserPromptSubmit"))
            w.advance(60 * sec); w.idle = 60; e.tick()
            w.advance(10 * sec); e.feed(payload: edit("a.js"))
            w.advance(5 * sec); w.idle = 400; e.tick()
            CT.check("300 s idle or more is away", e.presence.reasons, ["idle"])
            w.advance(60 * sec); e.feed(payload: post("ls"))
            w.advance(2 * min)
            w.idle = 1; e.tick()
            CT.check("a sample under 3 s is back, and the agent's work in between is recapped", w.presented.map(\.kind), ["recap"])
            CT.check("the recap counts what happened since the idle began (400 s before the sample)", w.presented.first?.text.contains("ran 2 steps"), true)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.idle = 400
            e.feed(payload: hook("PostToolUse", ["tool_name": "Read", "tool_input": ["file_path": "/Users/me/proj/a.js"]]))
            CT.check("a hook event reads the idle time too", e.presence.reasons, ["idle"])
        }

        CT.section("the local voice: a nicer sentence replaces the template once, unless the pointer is on the note")
        do {
            let w = World(), e = make(w)
            w.polishReply = "Claude Code ran 2 steps in proj, edited a.js and finished."
            e.feed(payload: hook("SessionStart"))
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.feed(payload: post("ls")); e.presenceEvent(.unlock)
            await e.polishTask?.value
            CT.check("it replaced the words", e.showing?.text, "Claude Code ran 2 steps in proj, edited a.js and finished.")
        }
        do {
            let w = World(), e = make(w)
            w.polishReply = "A nicer line."; w.pointer = true
            e.feed(payload: hook("SessionStart"))
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            await e.polishTask?.value
            CT.check("with the pointer on the note the words stay", e.showing?.text.hasPrefix("While you were away"), true)
        }
        do {
            let w = World(), e = make(w)
            e.store.setLocal(false)
            w.polishReply = "A nicer line."
            e.feed(payload: hook("SessionStart"))
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            CT.check("with the local voice off, no request is made", e.polishTask == nil, true)
        }

        CT.section("an idle time that is astronomically large or not a number never traps and never makes a recap")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.advance(10 * sec); e.feed(payload: edit("a.js"))
            w.idle = 1e308   // 1e308 s in ms overflows: the away began "at minus infinity"
            e.feed(payload: post("ls"))
            CT.check("a huge idle time is away", e.presence.reasons, ["idle"])
            CT.check("and the away start is a finite number or nothing the engine converts", e.presence.awaySince.map { $0.isFinite || $0 == -.infinity } ?? true, true)
            w.advance(10 * min); w.idle = 0; e.tick()
            CT.check("the return does not trap and gives no recap (an away start that is not finite is no away start; the quiet nudge of the ten minutes is another note)", "\(e.presence.isAway) / \(w.presented.map(\.kind))", "false / [\"stuck.silent\"]")
            w.idle = .infinity; w.advance(10 * sec); e.feed(payload: post("ls"))
            w.idle = .nan; w.advance(10 * sec); e.feed(payload: post("ls"))
            w.idle = -1e308; w.advance(10 * sec); e.feed(payload: post("ls"))
            CT.check("infinity, NaN and a huge negative are no sample at all", e.presence.isAway, false)
            CT.check("the status answer still works", e.status(for: "status")?.lines, ["Claude Code in proj has run 5 steps, edited a.js, and is still working."])
            for _ in 0..<4 {
                w.advance(1 * sec)
                e.feed(payload: hook("PostToolUse", ["session_id": "S2", "tool_name": "Bash", "tool_input": ["command": "make"]]))
            }
            w.advance(61 * sec); e.envChanged()   // the 60 s between two notes has passed
            CT.check("and the engine still nudges another session", w.presented.map(\.kind), ["stuck.silent", "stuck.loop"])
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("UserPromptSubmit"))
            w.advance(10 * sec)
            w.idle = 1e306; e.tick()     // the sample is due only after 5 s: 10 s have passed
            w.advance(2 * sec); w.idle = 1e308; e.feed(payload: edit("a.js"))
            e.presenceEvent(.lock)
            w.advance(3 * min); e.presenceEvent(.unlock)
            w.idle = 0; w.advance(2 * sec); e.tick()
            CT.check("a huge idle sample with a lock on top: back at the last release, no trap", e.presence.isAway, false)
            CT.check("whatever recap there is, its text holds no count that is not a whole number", w.presented.allSatisfy { !$0.text.contains("inf") && !$0.text.contains("nan") }, true)
        }

        CT.section("a clock that reads a time which is not finite never traps")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("UserPromptSubmit"))
            for bad in [Double.nan, .infinity, -.infinity] {
                let good = w.t
                w.t = bad
                e.feed(payload: post("ls")); e.tick(); e.envChanged(); e.presenceEvent(.lock); e.presenceEvent(.unlock)
                _ = e.status(for: "what's claude doing")
                w.t = good
                e.envChanged(); e.tick()
            }
            CT.check("it survived the reads, and the clock holds a finite deadline or none", e.clock.deadline.map { $0.isFinite } ?? true, true)
            CT.check("and the ledger was not wiped by the pruning: the session is still live", e.liveAgents, ["integration_claude"])
            CT.check("and the status answer still says so", e.status(for: "status")?.lines.first?.hasPrefix("Claude Code in proj"), true)
        }

        CT.section("the status question is answered from the ledger, on this machine")
        do {
            let w = World(), e = make(w)
            CT.check("a normal chat message is not the question", e.status(for: "can you tell me what claude is doing in the build"), nil)
            CT.check("nothing is running", e.status(for: "What are the agents doing?")?.lines, ["No agent is running right now."])
            CT.check("asked about one agent", e.status(for: "What's Claude doing?")?.lines, ["Claude Code is not running right now."])
            e.feed(payload: hook("SessionStart")); e.feed(payload: hook("UserPromptSubmit")); w.advance(5 * sec); e.feed(payload: post("ls"))
            CT.check("a live session: the template's words", e.status(for: "what's claude doing")?.lines, ["Claude Code in proj has run 1 step and is still working."])
            CT.check("and who is live", e.liveAgents, ["integration_claude"])
            e.feed(payload: hook("SessionEnd"))
            CT.check("an ended session is no longer live", e.liveAgents, [])
        }
        CT.section("the chat chip's source of truth is published, and only when the set of live agents changes")
        do {
            let w = World(), e = make(w)
            var seen: [Set<String>] = []
            let sub = e.$liveAgents.dropFirst().sink { seen.append($0) }
            e.feed(payload: hook("SessionStart"))
            CT.check("the first live session publishes once", seen, [["integration_claude"]])
            e.feed(payload: hook("UserPromptSubmit")); w.advance(5 * sec); e.feed(payload: post("ls")); e.tick(); e.envChanged()
            CT.check("events, ticks and re-evaluations that leave the set as it is publish nothing", seen.count, 1)
            e.feed(payload: hook("SessionEnd"))
            CT.check("the last session ending publishes the empty set, once", seen, [["integration_claude"], []])
            e.feed(payload: hook("SessionStart", ["session_id": "S2"]))
            w.advance(13 * 3_600_000); e.envChanged()
            CT.check("a session pruned for being silent too long publishes the empty set with no hook event (the evaluation that prunes it)", seen, [["integration_claude"], [], ["integration_claude"], []])
            sub.cancel()
        }

        CT.section("the session key: the first non-empty of session_id and conversation_id, capped at 128 (the ledger's, and the focus mark's)")
        CT.check("an empty session_id falls to conversation_id", SidekickLedger.sessionKey(["session_id": "", "conversation_id": "C9"]), "C9")
        CT.check("neither: unknown", SidekickLedger.sessionKey([:]), "unknown")
        CT.check("a 200-code-point session_id keys on the capped form", SidekickLedger.sessionKey(["session_id": String(repeating: "a", count: 200)]), String(repeating: "a", count: 128))
        CT.check("and so does a 200-code-point conversation_id", SidekickLedger.sessionKey(["session_id": "", "conversation_id": String(repeating: "b", count: 200)]).unicodeScalars.count, 128)

        CT.finish()
    }
}
